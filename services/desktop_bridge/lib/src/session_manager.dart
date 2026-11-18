import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'native_pty.dart';
import 'provider_registry.dart';
import 'util.dart';

const int maxSessionBuffer = 700000;
const int maxChunkChars = 196608;

final class AgentCommand {
  const AgentCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

final class DesktopAttachResult {
  const DesktopAttachResult({
    required this.opened,
    this.terminal,
    this.error,
  });

  final bool opened;
  final String? terminal;
  final String? error;
}

typedef DesktopOpener =
    Future<DesktopAttachResult> Function(ManagedSession session);

final class ManagedSession {
  ManagedSession({
    required this.id,
    required this.provider,
    required this.title,
    required this.cwd,
    required this.startedAt,
    required this.openOnDesktop,
    required this.columns,
    required this.rows,
    required this.pty,
    this.initialPrompt,
    this.resumeSessionId,
  });

  final String id;
  final AgentProvider provider;
  final String cwd;
  final DateTime startedAt;
  final bool openOnDesktop;
  final NativePty pty;
  final String? initialPrompt;
  final String? resumeSessionId;
  final String? model;
  final List<String> extraArgs;
  String title;
  String status = 'starting';
  int? exitCode;
  DateTime? endedAt;
  DateTime? lastActivityAt;
  int columns;
  int rows;
  bool openRequested = false;
  bool desktopAttached = false;
  String? desktopTerminal;
  String? error;

  final StringBuffer _buffer = StringBuffer();
  int _dropped = 0;
  int _cursor = 0;

  bool get isActive => status == 'running' || status == 'starting';

  LiveSession toModel() => LiveSession(
    id: id,
    provider: provider,
    title: title,
    cwd: cwd,
    startedAt: startedAt,
    status: status,
    openOnDesktop: openOnDesktop,
    columns: columns,
    rows: rows,
    outputCursor: _cursor,
    exitCode: exitCode,
    endedAt: endedAt,
    initialPrompt: initialPrompt,
    resumeSessionId: resumeSessionId,
    model: model,
    extraArgs: extraArgs,
    desktopAttached: desktopAttached,
    desktopTerminal: desktopTerminal,
    error: error,
  );

  Map<String, Object?> toJson() => toModel().toJson();

  void append(String text) {
    if (text.isEmpty) return;
    _buffer.write(text);
    _cursor += text.length;
    lastActivityAt = DateTime.now().toUtc();
    final overflow = _buffer.length - maxSessionBuffer;
    if (overflow > 0) {
      final current = _buffer.toString();
      var cut = overflow;
      if (cut < current.length &&
          cut > 0 &&
          _isLowSurrogate(current.codeUnitAt(cut - 1)) &&
          _isHighSurrogate(current.codeUnitAt(cut))) {
        cut += 1;
      }
      _buffer
        ..clear()
        ..write(current.substring(cut));
      _dropped += cut;
    }
  }

  TerminalChunk read({
    required int cursor,
    required int limit,
    required bool plain,
  }) {
    final dropped = cursor < _dropped;
    final start = cursor < _dropped ? _dropped : cursor;
    final safeStart = start > _cursor ? _cursor : start;
    final maxEnd = _cursor;
    final wantedEnd = safeStart + limit;
    final end = wantedEnd > maxEnd ? maxEnd : wantedEnd;
    final source = _buffer.toString();
    final offset = safeStart - _dropped;
    final length = (end - safeStart).clamp(0, source.length - offset);
    var output = length <= 0
        ? ''
        : source.substring(offset, offset + length);
    if (plain) output = stripAnsi(output);
    return TerminalChunk(
      output: output,
      cursor: end,
      dropped: _dropped,
      truncated: dropped,
      running: isActive,
      status: status,
      exitCode: exitCode,
      hasMore: end < _cursor,
      columns: columns,
      rows: rows,
    );
  }

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;
  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;
}

final class SessionManager {
  SessionManager({
    required this.providers,
    DesktopOpener? desktopOpener,
    this.keepEndedSessions = 40,
  }) : _desktopOpener = desktopOpener;

  final ProviderRegistry providers;
  final int keepEndedSessions;
  final Map<String, ManagedSession> _sessions = {};
  final _changes = StreamController<void>.broadcast();
  final Map<String, Timer> _forceKillTimers = {};
  DesktopOpener? _desktopOpener;

  Stream<void> get changes => _changes.stream;

  List<ManagedSession> get sessions {
    final list = _sessions.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  ManagedSession? get(String id) => _sessions[id];

  void setDesktopOpener(DesktopOpener? opener) {
    _desktopOpener = opener;
  }

  Future<ManagedSession> start({
    required AgentProvider provider,
    required String cwd,
    String? prompt,
    String? title,
    String? resumeSessionId,
    String? model,
    List<String>? extraArgs,
    bool? openOnDesktop,
  }) async {
    final directory = Directory(cwd);
    if (!await directory.exists()) {
      throw const SessionException(
        'The selected working directory does not exist.',
      );
    }
    final resolved = await directory.resolveSymbolicLinks();
    if (!await FileSystemEntity.isDirectory(resolved)) {
      throw const SessionException('The selected path is not a directory.');
    }
    final info = providers.get(provider);
    if (!info.available) {
      throw SessionException(
        '${provider.label} is not installed or not on the bridge PATH.',
      );
    }
    final cleanPrompt = prompt?.trim() ?? '';
    final cleanResume = resumeSessionId?.trim() ?? '';
    if (cleanResume.isNotEmpty) {
      if (!provider.canResume) {
        throw SessionException('${provider.label} does not support resume.');
      }
      if (!isSafeSessionToken(cleanResume)) {
        throw const SessionException('The resume session id is invalid.');
      }
    }
    final command = commandFor(
      provider: provider,
      prompt: cleanPrompt,
      resumeSessionId: cleanResume,
      model: model,
      extraArgs: extraArgs,
    );
    final id = randomId(10);
    final columns = 100;
    final rows = 32;
    final environment = <String, String>{
      ...Platform.environment,
      'PATH': enrichedPath(),
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
      'FORCE_COLOR': '1',
      'AGENTLINK_SESSION_ID': id,
      'AGENTLINK_BRIDGE': '1',
    };
    if (!environment.containsKey('LANG')) environment['LANG'] = 'C.UTF-8';

    late final NativePty pty;
    try {
      pty = NativePty.start(
        info.command,
        command.arguments,
        workingDirectory: resolved,
        environment: environment,
        columns: columns,
        rows: rows,
      );
    } on ProcessException catch (error) {
      throw SessionException(
        'Could not start ${provider.label}: ${error.message}',
      );
    }

    final session = ManagedSession(
      id: id,
      provider: provider,
      title: title?.trim().isNotEmpty == true
          ? shortTitle(title!, fallback: provider.label)
          : shortTitle(
              cleanPrompt,
              fallback:
                  '${provider.label} · ${DateTime.now().toLocal().hour.toString().padLeft(2, '0')}:'
                  '${DateTime.now().toLocal().minute.toString().padLeft(2, '0')}',
            ),
      cwd: resolved,
      startedAt: DateTime.now().toUtc(),
      openOnDesktop: openOnDesktop ?? true,
      columns: columns,
      rows: rows,
      pty: pty,
      initialPrompt: cleanPrompt.isEmpty ? null : cleanPrompt,
      resumeSessionId: cleanResume.isEmpty ? null : cleanResume,
      model: model,
      extraArgs: extraArgs ?? const [],
    );
    _sessions[id] = session;
    session.status = 'running';
    _changes.add(null);

    pty.output
        .map<List<int>>((data) => data)
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (text) {
            session.append(text);
          },
          onError: (Object error) {
            session.error = 'Terminal stream error: $error';
          },
        );

    unawaited(
      pty.exitCode.then((code) {
        _forceKillTimers.remove(id)?.cancel();
        session.exitCode = code;
        session.endedAt = DateTime.now().toUtc();
        if (session.openRequested) {
          session.status = 'stopped';
        } else if (code == 0) {
          session.status = 'exited';
        } else {
          session.status = 'failed';
        }
        session.desktopAttached = false;
        _changes.add(null);
        _prune();
      }),
    );

    if (session.openOnDesktop) {
      unawaited(_openDesktop(session));
    }
    return session;
  }

  Future<DesktopAttachResult> attachToDesktop(String id) async {
    final session = _sessions[id];
    if (session == null) {
      throw const SessionException('Session not found.');
    }
    if (!session.isActive) {
      throw const SessionException('This session has already ended.');
    }
    return _openDesktop(session);
  }

  Future<DesktopAttachResult> _openDesktop(ManagedSession session) async {
    final opener = _desktopOpener;
    if (opener == null) {
      return const DesktopAttachResult(
        opened: false,
        error: 'Desktop attach is not available in this bridge mode.',
      );
    }
    try {
      final result = await opener(session);
      session.desktopAttached = result.opened;
      session.desktopTerminal = result.terminal;
      _changes.add(null);
      return result;
    } on Object catch (error) {
      final result = DesktopAttachResult(
        opened: false,
        error: 'Could not open a desktop terminal: $error',
      );
      _changes.add(null);
      return result;
    }
  }

  bool input(String id, String text) {
    final session = _sessions[id];
    if (session == null || !session.isActive) return false;
    session.pty.write(utf8.encode(text));
    return true;
  }

  bool inputBytes(String id, List<int> bytes) {
    final session = _sessions[id];
    if (session == null || !session.isActive) return false;
    session.pty.write(bytes);
    return true;
  }

  bool resize(String id, int columns, int rows) {
    final session = _sessions[id];
    if (session == null || !session.isActive) return false;
    final safeColumns = columns.clamp(20, 400);
    final safeRows = rows.clamp(5, 200);
    session.columns = safeColumns;
    session.rows = safeRows;
    session.pty.resize(safeColumns, safeRows);
    _changes.add(null);
    return true;
  }

  bool rename(String id, String title) {
    final session = _sessions[id];
    if (session == null) return false;
    final clean = title.trim();
    if (clean.isEmpty) return false;
    session.title = shortTitle(clean, fallback: session.title);
    _changes.add(null);
    return true;
  }

  bool stop(String id) {
    final session = _sessions[id];
    if (session == null || !session.isActive) return false;
    session.openRequested = true;
    session.status = 'stopping';
    _changes.add(null);
    session.pty.kill(ProcessSignal.sigterm);
    _forceKillTimers[id] = Timer(const Duration(seconds: 4), () {
      final current = _sessions[id];
      if (current != null && !current.pty.isClosed) {
        current.pty.kill(ProcessSignal.sigkill);
      }
    });
    return true;
  }

  Future<void> stopAll() async {
    final active = _sessions.values.where((session) => session.isActive).toList();
    if (active.isEmpty) return;
    for (final session in active) {
      session.openRequested = true;
      session.status = 'stopping';
      session.pty.kill(ProcessSignal.sigterm);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final session in active) {
      if (session.isActive) session.pty.kill(ProcessSignal.sigkill);
    }
  }

  void _prune() {
    final ended = _sessions.values
        .where((session) => !session.isActive)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    for (var index = keepEndedSessions; index < ended.length; index++) {
      _sessions.remove(ended[index].id);
    }
  }

  Future<void> dispose() async {
    for (final timer in _forceKillTimers.values) {
      timer.cancel();
    }
    _forceKillTimers.clear();
    await stopAll();
    await _changes.close();
  }
}

final class SessionException implements Exception {
  const SessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

List<String> _modelArgs(AgentProvider provider, String model) => switch (provider) {
  AgentProvider.claude => ['--model', model],
  AgentProvider.opencode => ['--model', model],
  AgentProvider.codex => ['--model', model],
  AgentProvider.gemini => ['--model', model],
};

AgentCommand commandFor({
  required AgentProvider provider,
  String prompt = '',
  String resumeSessionId = '',
  String? model,
  List<String>? extraArgs,
}) {
  final hasPrompt = prompt.trim().isNotEmpty;
  final cleanPrompt = prompt.trim();
  final resume = resumeSessionId.trim();
  final hasResume = resume.isNotEmpty;
  final cleanModel = model?.trim() ?? '';
  final hasModel = cleanModel.isNotEmpty;
  final args = <String>[
    if (hasModel) ..._modelArgs(provider, cleanModel),
    ...?extraArgs,
  ];
  return switch (provider) {
    AgentProvider.claude => AgentCommand('claude', [
      if (hasResume) ...['--resume', resume],
      ...args,
      if (hasPrompt) cleanPrompt,
    ]),
    AgentProvider.opencode => AgentCommand('opencode', [
      if (hasResume) ...['--session', resume],
      ...args,
      if (hasPrompt) ...['--prompt', cleanPrompt],
    ]),
    AgentProvider.codex => AgentCommand('codex', [
      if (hasResume) ...['resume', resume],
      ...args,
      if (hasPrompt) cleanPrompt,
    ]),
    AgentProvider.gemini => AgentCommand('gemini', [
      ...args,
      if (hasPrompt) ...['-i', cleanPrompt],
    ]),
  };
}

final _ansiPattern = RegExp(
  '[\u001B\u009B][[\\]()#;?]*'
  '(?:(?:(?:[a-zA-Z\\d]*(?:;[-a-zA-Z\\d/#&.:=?%@~_]+)*)?\u0007)|'
  '(?:(?:\\d{1,4}(?:[;:]\\d{0,4})*)?[\\dA-PR-TZcf-nq-uy=><~]))',
);

String stripAnsi(String input) {
  var value = input.replaceAll(_ansiPattern, '');
  value = value.replaceAll('\r\n', '\n');
  value = value.replaceAll('\r', '\n');
  value = value.replaceAll('\u0000', '');
  return value;
}
