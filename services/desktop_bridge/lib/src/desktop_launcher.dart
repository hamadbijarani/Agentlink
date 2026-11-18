import 'dart:async';
import 'dart:io';

import 'config_store.dart';
import 'session_manager.dart';
import 'util.dart';

final class DesktopLauncher {
  DesktopLauncher({required this.configStore});

  final ConfigStore configStore;
  int? _port;

  void setPort(int port) => _port = port;

  bool get isSupported =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  Future<DesktopAttachResult> open(ManagedSession session) async {
    final port = _port;
    if (port == null) {
      return const DesktopAttachResult(
        opened: false,
        error: 'The local HTTP endpoint is not running.',
      );
    }
    final config = configStore.current;
    final command = _attachCommand(session.id);
    if (command == null) {
      return const DesktopAttachResult(
        opened: false,
        error: 'Could not locate the AgentLink attach client.',
      );
    }
    final environment = <String, String>{
      ...Platform.environment,
      'AGENTLINK_ENDPOINT': 'http://127.0.0.1:$port',
      'AGENTLINK_ATTACH_TOKEN': config.localAttachToken,
      'AGENTLINK_SESSION_ID': session.id,
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
    };

    if (Platform.isMacOS) {
      return _openMac(command, environment, session);
    }
    if (Platform.isWindows) {
      return _openWindows(command, environment);
    }
    return _openLinux(command, environment);
  }

  String? _attachCommand(String sessionId) {
    final executable = Platform.executable;
    final script = Platform.script;
    final scriptPath = script.scheme == 'file' ? script.toFilePath() : '';
    if (scriptPath.endsWith('.dart')) {
      final dartPath = findExecutable('dart') ?? executable;
      return [
        _quote(dartPath),
        'run',
        _quote(scriptPath),
        'attach',
        _quote(sessionId),
      ].join(' ');
    }
    if (executable.isEmpty) return null;
    return [_quote(executable), 'attach', _quote(sessionId)].join(' ');
  }

  Future<DesktopAttachResult> _openLinux(
    String command,
    Map<String, String> environment,
  ) async {
    final shellCommand = 'exec $command';
    final candidates = <_TerminalCandidate>[
      _TerminalCandidate('gnome-terminal', [
        '--',
        'bash',
        '-lc',
        shellCommand,
      ]),
      _TerminalCandidate('kgx', ['--', 'bash', '-lc', shellCommand]),
      _TerminalCandidate('konsole', ['-e', 'bash', '-lc', shellCommand]),
      _TerminalCandidate('xfce4-terminal', [
        '-x',
        'bash',
        '-lc',
        shellCommand,
      ]),
      _TerminalCandidate('alacritty', ['-e', 'bash', '-lc', shellCommand]),
      _TerminalCandidate('kitty', ['bash', '-lc', shellCommand]),
      _TerminalCandidate('xterm', ['-e', 'bash', '-lc', shellCommand]),
      _TerminalCandidate('x-terminal-emulator', [
        '-e',
        'bash',
        '-lc',
        shellCommand,
      ]),
    ];
    for (final candidate in candidates) {
      final executable = findExecutable(candidate.name);
      if (executable == null) continue;
      final started = await _tryStart(
        executable,
        candidate.arguments,
        environment,
      );
      if (started) {
        return DesktopAttachResult(
          opened: true,
          terminal: candidate.name,
        );
      }
    }
    return const DesktopAttachResult(
      opened: false,
      error:
          'No graphical terminal was found. Install gnome-terminal, konsole, '
          'alacritty, or xterm to see sessions on the desktop.',
    );
  }

  Future<DesktopAttachResult> _openMac(
    String command,
    Map<String, String> environment,
    ManagedSession session,
  ) async {
    final directory = Directory('${homeDirectory()}/.agentlink/attach');
    await directory.create(recursive: true);
    final script = File('${directory.path}/${session.id}.command');
    final buffer = StringBuffer('#!/bin/sh\n');
    for (final entry in environment.entries) {
      if (entry.key == 'PATH') continue;
      buffer.writeln(
        'export ${entry.key}=${_quote(entry.value)}',
      );
    }
    buffer.writeln('exec $command');
    await script.writeAsString(buffer.toString(), flush: true);
    await Process.run('chmod', ['700', script.path]);
    try {
      final process = await Process.start('open', [
        '-a',
        'Terminal',
        script.path,
      ]);
      final result = await _waitForLaunch(process);
      if (result) {
        return const DesktopAttachResult(opened: true, terminal: 'Terminal');
      }
    } on ProcessException {
      // Fall through to the error below.
    }
    return const DesktopAttachResult(
      opened: false,
      error: 'Could not open Terminal.app.',
    );
  }

  Future<DesktopAttachResult> _openWindows(
    String command,
    Map<String, String> environment,
  ) async {
    try {
      final process = await Process.start(
        'cmd',
        ['/c', 'start', '""', 'cmd', '/k', command],
        environment: environment,
      );
      final result = await _waitForLaunch(process);
      if (result) {
        return const DesktopAttachResult(
          opened: true,
          terminal: 'Command Prompt',
        );
      }
    } on ProcessException {
      // Fall through to the error below.
    }
    return const DesktopAttachResult(
      opened: false,
      error: 'Could not open a Windows terminal.',
    );
  }

  Future<bool> _tryStart(
    String executable,
    List<String> arguments,
    Map<String, String> environment,
  ) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        environment: environment,
      );
      process.stdout.drain<void>();
      process.stderr.drain<void>();
      return await _waitForLaunch(process);
    } on ProcessException {
      return false;
    }
  }

  Future<bool> _waitForLaunch(Process process) async {
    final exitCode = await Future.any<int?>([
      process.exitCode,
      Future<int?>.delayed(
        const Duration(milliseconds: 650),
        () => null,
      ),
    ]);
    return exitCode == null || exitCode == 0;
  }

  static String _quote(String value) {
    if (value.isEmpty) return "''";
    if (RegExp(r'^[A-Za-z0-9_./:@%+=,-]+$').hasMatch(value)) return value;
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}

final class _TerminalCandidate {
  const _TerminalCandidate(this.name, this.arguments);

  final String name;
  final List<String> arguments;
}
