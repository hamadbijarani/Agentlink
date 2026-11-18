import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

abstract interface class SessionAdapter {
  AgentProvider get provider;
  Future<List<AgentSession>> discover({int limit = 100});
  Future<SessionDetail?> detail(String ref);
}

final class FileSessionAdapter implements SessionAdapter {
  FileSessionAdapter({required this.provider, required this.roots});

  @override
  final AgentProvider provider;
  final List<Directory> roots;

  @override
  Future<List<AgentSession>> discover({int limit = 100}) async {
    final files = <File>[];
    for (final root in roots) {
      if (!await root.exists()) continue;
      try {
        await for (final entity in root.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File && _isCandidate(entity.path)) files.add(entity);
        }
      } on FileSystemException {
        // A single unreadable tool directory should not hide other providers.
      }
    }

    final dated = <({File file, DateTime modified})>[];
    for (final file in files) {
      try {
        dated.add((file: file, modified: (await file.stat()).modified));
      } on FileSystemException {
        // The file may disappear while a tool rotates its session store.
      }
    }
    dated.sort((a, b) => b.modified.compareTo(a.modified));

    final sessions = <AgentSession>[];
    for (final item in dated.take(limit * 2)) {
      final parsed = await _parseFile(item.file, metadataOnly: true);
      if (parsed != null) sessions.add(parsed.session);
      if (sessions.length >= limit) break;
    }
    return sessions;
  }

  @override
  Future<SessionDetail?> detail(String ref) async {
    late final String path;
    try {
      path = decodeRef(ref);
    } on FormatException {
      return null;
    }
    if (!await _isAllowedPath(path)) return null;
    final file = File(path);
    if (!await file.exists() || !_isCandidate(path)) return null;
    return _parseFile(file, metadataOnly: false);
  }

  Future<bool> _isAllowedPath(String path) async {
    try {
      final candidate = await File(path).resolveSymbolicLinks();
      for (final root in roots) {
        if (!await root.exists()) continue;
        final resolvedRoot = await root.resolveSymbolicLinks();
        final prefix = resolvedRoot.endsWith(Platform.pathSeparator)
            ? resolvedRoot
            : '$resolvedRoot${Platform.pathSeparator}';
        if (candidate.startsWith(prefix)) return true;
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }

  bool _isCandidate(String path) {
    final lower = path.toLowerCase();
    switch (provider) {
      case AgentProvider.claude:
      case AgentProvider.codex:
        return lower.endsWith('.jsonl');
      case AgentProvider.gemini:
        return lower.endsWith('.json') || lower.endsWith('.jsonl');
      case AgentProvider.opencode:
        return false;
    }
  }

  Future<SessionDetail?> _parseFile(
    File file, {
    required bool metadataOnly,
  }) async {
    try {
      return await switch (provider) {
        AgentProvider.claude => _parseJsonLines(
          file,
          metadataOnly,
          _claudeMessage,
        ),
        AgentProvider.codex => _parseJsonLines(
          file,
          metadataOnly,
          _codexMessage,
        ),
        AgentProvider.gemini => _parseGemini(file, metadataOnly),
        AgentProvider.opencode => Future.value(null),
      };
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<SessionDetail?> _parseJsonLines(
    File file,
    bool metadataOnly,
    SessionMessage? Function(Map<String, dynamic>) parseMessage,
  ) async {
    final messages = <SessionMessage>[];
    String? id;
    String? cwd;
    String? explicitTitle;
    var messageCount = 0;
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      Map<String, dynamic> map;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) continue;
        map = decoded;
      } on FormatException {
        continue;
      }
      id ??= map['sessionId'] as String?;
      cwd ??= map['cwd'] as String?;
      explicitTitle ??= map['summary'] as String?;
      final payload = map['payload'];
      if (payload is Map) {
        id ??= payload['id'] as String?;
        cwd ??= payload['cwd'] as String?;
      }
      final message = parseMessage(map);
      if (message != null) {
        messageCount++;
        if (!metadataOnly || messages.isEmpty) {
          messages.add(message);
          if (!metadataOnly && messages.length > 500) messages.removeAt(0);
        }
      }
    }
    if (id == null && messageCount == 0) return null;
    final stat = await file.stat();
    final session = AgentSession(
      id: id ?? _fileStem(file.path),
      ref: encodeRef(file.absolute.path),
      provider: provider,
      title: explicitTitle ?? shortTitle(messages.firstOrNull?.text ?? ''),
      projectPath: cwd ?? _projectFromPath(file.path),
      updatedAt: stat.modified,
      messageCount: messageCount,
    );
    return SessionDetail(
      session: session,
      messages: metadataOnly ? const [] : messages,
    );
  }

  SessionMessage? _claudeMessage(Map<String, dynamic> map) {
    final type = map['type']?.toString();
    if (type != 'user' && type != 'assistant') return null;
    final message = map['message'];
    final text = message is Map
        ? flattenText(message['content'])
        : flattenText(message);
    if (text.trim().isEmpty) return null;
    return SessionMessage(
      role: type!,
      text: text,
      timestamp: parseTimestamp(map['timestamp']),
    );
  }

  SessionMessage? _codexMessage(Map<String, dynamic> map) {
    final payload = map['payload'];
    if (payload is! Map) return null;
    final payloadType = payload['type']?.toString() ?? '';
    String? role;
    Object? content;
    if (payloadType == 'user_message') {
      role = 'user';
      content = payload['message'];
    } else if (payloadType == 'agent_message') {
      role = 'assistant';
      content = payload['message'];
    } else if (map['type'] == 'response_item' && payloadType == 'message') {
      role = payload['role']?.toString();
      content = payload['content'];
    } else if (payloadType.contains('tool')) {
      role = 'tool';
      content = payload;
    }
    final text = flattenText(content);
    if (role == null || text.trim().isEmpty) return null;
    return SessionMessage(
      role: role,
      text: text,
      timestamp: parseTimestamp(map['timestamp']),
      kind: role == 'tool' ? 'tool' : 'text',
    );
  }

  Future<SessionDetail?> _parseGemini(File file, bool metadataOnly) async {
    final stat = await file.stat();
    if (stat.size > 20 * 1024 * 1024) return null;
    final content = await file.readAsString();
    final messages = <SessionMessage>[];
    String? id;
    String? cwd;
    Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      return _parseJsonLines(file, metadataOnly, _genericMessage);
    }
    if (decoded is Map) {
      id = decoded['sessionId']?.toString() ?? decoded['id']?.toString();
      cwd = decoded['cwd']?.toString() ?? decoded['projectPath']?.toString();
      final rawMessages =
          decoded['messages'] ?? decoded['history'] ?? decoded['conversation'];
      if (rawMessages is List) {
        for (final raw in rawMessages) {
          if (raw is Map) {
            final message = _genericMessage(Map<String, dynamic>.from(raw));
            if (message != null) messages.add(message);
          }
        }
      }
    } else if (decoded is List) {
      for (final raw in decoded) {
        if (raw is Map) {
          final message = _genericMessage(Map<String, dynamic>.from(raw));
          if (message != null) messages.add(message);
        }
      }
    }
    if (messages.isEmpty) return null;
    final session = AgentSession(
      id: id ?? _fileStem(file.path),
      ref: encodeRef(file.absolute.path),
      provider: provider,
      title: shortTitle(messages.first.text),
      projectPath: cwd ?? _projectFromPath(file.path),
      updatedAt: stat.modified,
      messageCount: messages.length,
    );
    return SessionDetail(
      session: session,
      messages: metadataOnly ? const [] : messages,
    );
  }

  SessionMessage? _genericMessage(Map<String, dynamic> map) {
    final role = (map['role'] ?? map['type'] ?? map['author'])?.toString();
    final text = flattenText(map['content'] ?? map['message'] ?? map['text']);
    if (role == null || text.trim().isEmpty) return null;
    return SessionMessage(
      role: role == 'model' ? 'assistant' : role,
      text: text,
      timestamp: parseTimestamp(map['timestamp'] ?? map['createdAt']),
    );
  }

  String _fileStem(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? name : name.substring(0, dot);
  }

  String _projectFromPath(String path) {
    final parent = File(path).parent.path;
    return parent;
  }
}

final class OpenCodeSessionAdapter implements SessionAdapter {
  @override
  AgentProvider get provider => AgentProvider.opencode;

  @override
  Future<List<AgentSession>> discover({int limit = 100}) async {
    final result = await _run([
      'session',
      'list',
      '--max-count',
      '$limit',
      '--format',
      'json',
    ]);
    if (result == null || result.exitCode != 0) return const [];
    final decoded = _decodeJson(result.stdout);
    final rawList = decoded is List
        ? decoded
        : decoded is Map && decoded['sessions'] is List
        ? decoded['sessions'] as List
        : const [];
    return rawList
        .whereType<Map>()
        .map((raw) {
          final item = Map<String, dynamic>.from(raw);
          final id = (item['id'] ?? item['sessionID'] ?? '').toString();
          final directory = (item['directory'] ?? item['cwd'] ?? '').toString();
          return AgentSession(
            id: id,
            ref: encodeRef(id),
            provider: provider,
            title: shortTitle((item['title'] ?? '').toString()),
            projectPath: directory,
            updatedAt:
                parseTimestamp(
                  item['updatedAt'] ??
                      item['updated'] ??
                      item['timeUpdated'] ??
                      item['time']?['updated'] ??
                      item['created'],
                ) ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            messageCount: (item['messageCount'] as num?)?.toInt() ?? 0,
          );
        })
        .where((session) => session.id.isNotEmpty)
        .toList();
  }

  @override
  Future<SessionDetail?> detail(String ref) async {
    late final String id;
    try {
      id = decodeRef(ref);
    } on FormatException {
      return null;
    }
    if (!RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(id)) return null;
    final result = await _run(['session', 'export', id]);
    if (result == null || result.exitCode != 0) return null;
    final decoded = _decodeJson(result.stdout);
    if (decoded is! Map) return null;
    final info = decoded['info'] is Map ? decoded['info'] as Map : decoded;
    final rawMessages = decoded['messages'];
    final messages = <SessionMessage>[];
    if (rawMessages is List) {
      for (final raw in rawMessages) {
        if (raw is! Map) continue;
        final role =
            (raw['role'] ??
                    raw['type'] ??
                    raw['info']?['role'] ??
                    raw['info']?['type'] ??
                    'assistant')
                .toString();
        final text = flattenText(
          raw['parts'] ?? raw['content'] ?? raw['message'],
        );
        if (text.trim().isEmpty) continue;
        messages.add(SessionMessage(role: role, text: text));
      }
    }
    final summary = AgentSession(
      id: id,
      ref: ref,
      provider: provider,
      title: shortTitle(
        (info['title'] ?? messages.firstOrNull?.text ?? '').toString(),
      ),
      projectPath: (info['directory'] ?? '').toString(),
      updatedAt:
          parseTimestamp(info['time']?['updated']) ?? DateTime.now().toUtc(),
      messageCount: messages.length,
    );
    return SessionDetail(session: summary, messages: messages);
  }

  Object? _decodeJson(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      final start = value.indexOf(RegExp(r'[\[{]'));
      if (start < 0) return null;
      try {
        return jsonDecode(value.substring(start));
      } on FormatException {
        return null;
      }
    }
  }

  Future<ProcessResult?> _run(List<String> arguments) async {
    try {
      final process = await Process.start(
        'opencode',
        arguments,
        runInShell: false,
      );
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      return ProcessResult(
        process.pid,
        exitCode,
        await stdoutFuture,
        await stderrFuture,
      );
    } on ProcessException {
      return null;
    }
  }
}

List<SessionAdapter> defaultSessionAdapters() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  Directory dir(String path) => Directory(path);
  final claudeHome =
      Platform.environment['CLAUDE_CONFIG_DIR'] ?? '$home/.claude';
  final codexHome = Platform.environment['CODEX_HOME'] ?? '$home/.codex';
  final geminiHome = Platform.environment['GEMINI_HOME'] ?? '$home/.gemini';
  return [
    FileSessionAdapter(
      provider: AgentProvider.claude,
      roots: [dir('$claudeHome/projects')],
    ),
    OpenCodeSessionAdapter(),
    FileSessionAdapter(
      provider: AgentProvider.codex,
      roots: [
        dir('$codexHome/sessions'),
        dir('$codexHome/archived_sessions'),
        dir('$codexHome/headless'),
      ],
    ),
    FileSessionAdapter(
      provider: AgentProvider.gemini,
      roots: [dir('$geminiHome/tmp')],
    ),
  ];
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
