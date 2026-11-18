import 'dart:convert';

enum AgentProvider {
  claude(
    id: 'claude',
    label: 'Claude Code',
    command: 'claude',
    canResume: true,
  ),
  opencode(
    id: 'opencode',
    label: 'OpenCode',
    command: 'opencode',
    canResume: true,
  ),
  codex(
    id: 'codex',
    label: 'Codex CLI',
    command: 'codex',
    canResume: true,
  ),
  gemini(
    id: 'gemini',
    label: 'Gemini CLI',
    command: 'gemini',
    canResume: false,
  );

  const AgentProvider({
    required this.id,
    required this.label,
    required this.command,
    required this.canResume,
  });

  final String id;
  final String label;
  final String command;
  final bool canResume;

  static AgentProvider? fromId(String? value) {
    for (final provider in values) {
      if (provider.id == value) return provider;
    }
    return null;
  }
}

final class ProviderTheme {
  const ProviderTheme({
    required this.name,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.muted,
    required this.surface,
    required this.border,
  });

  final String name;
  final String background;
  final String foreground;
  final String accent;
  final String muted;
  final String surface;
  final String border;

  Map<String, Object?> toJson() => {
    'name': name,
    'background': background,
    'foreground': foreground,
    'accent': accent,
    'muted': muted,
    'surface': surface,
    'border': border,
  };
}

ProviderTheme themeForProvider(AgentProvider provider) => switch (provider) {
  AgentProvider.claude => const ProviderTheme(
    name: 'Claude Dusk',
    background: '#1B1A17',
    foreground: '#F2EEE5',
    accent: '#D97757',
    muted: '#918A7D',
    surface: '#26241F',
    border: '#3A3730',
  ),
  AgentProvider.opencode => const ProviderTheme(
    name: 'OpenCode Graphite',
    background: '#0B0B0C',
    foreground: '#EDEDED',
    accent: '#F5A742',
    muted: '#8B8B8B',
    surface: '#161617',
    border: '#2C2C2E',
  ),
  AgentProvider.codex => const ProviderTheme(
    name: 'Codex Terminal',
    background: '#0B0F0E',
    foreground: '#ECF2F0',
    accent: '#10A37F',
    muted: '#82908C',
    surface: '#151C1A',
    border: '#2A3733',
  ),
  AgentProvider.gemini => const ProviderTheme(
    name: 'Gemini Midnight',
    background: '#0B0F19',
    foreground: '#E8EAED',
    accent: '#8AB4F8',
    muted: '#8F9BB3',
    surface: '#141B2A',
    border: '#293449',
  ),
};

final class ProviderInfo {
  ProviderInfo({
    required this.provider,
    required this.available,
    required this.version,
    required this.theme,
    required this.command,
    required this.capabilities,
  });

  final AgentProvider provider;
  final bool available;
  final String? version;
  final ProviderTheme theme;
  final String command;
  final Map<String, bool> capabilities;

  Map<String, Object?> toJson() => {
    'id': provider.id,
    'label': provider.label,
    'available': available,
    'version': version,
    'command': command,
    'theme': theme.toJson(),
    'capabilities': capabilities,
  };
}

final class AgentSession {
  AgentSession({
    required this.id,
    required this.ref,
    required this.provider,
    required this.title,
    required this.projectPath,
    required this.updatedAt,
    required this.messageCount,
  });

  final String id;
  final String ref;
  final AgentProvider provider;
  final String title;
  final String projectPath;
  final DateTime updatedAt;
  final int messageCount;

  Map<String, Object?> toJson() => {
    'id': id,
    'ref': ref,
    'provider': provider.id,
    'providerLabel': provider.label,
    'title': title,
    'projectPath': projectPath,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'messageCount': messageCount,
    'kind': 'history',
  };
}

final class LiveSession {
  LiveSession({
    required this.id,
    required this.provider,
    required this.title,
    required this.cwd,
    required this.startedAt,
    required this.status,
    required this.openOnDesktop,
    required this.columns,
    required this.rows,
    required this.outputCursor,
    this.exitCode,
    this.endedAt,
    this.initialPrompt,
    this.resumeSessionId,
    this.model,
    this.extraArgs = const [],
    this.desktopAttached = false,
    this.desktopTerminal,
    this.error,
  });

  final String id;
  final AgentProvider provider;
  final String title;
  final String cwd;
  final DateTime startedAt;
  final String status;
  final bool openOnDesktop;
  final int columns;
  final int rows;
  final int outputCursor;
  final int? exitCode;
  final DateTime? endedAt;
  final String? initialPrompt;
  final String? resumeSessionId;
  final String? model;
  final List<String> extraArgs;
  final bool desktopAttached;
  final String? desktopTerminal;
  final String? error;

  bool get isActive => status == 'running' || status == 'starting';

  Map<String, Object?> toJson() => {
    'id': id,
    'provider': provider.id,
    'providerLabel': provider.label,
    'title': title,
    'cwd': cwd,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'status': status,
    'openOnDesktop': openOnDesktop,
    'desktopAttached': desktopAttached,
    if (desktopTerminal != null) 'desktopTerminal': desktopTerminal,
    'columns': columns,
    'rows': rows,
    'outputCursor': outputCursor,
    if (exitCode != null) 'exitCode': exitCode,
    if (endedAt != null) 'endedAt': endedAt!.toUtc().toIso8601String(),
    if (initialPrompt != null) 'initialPrompt': initialPrompt,
    if (resumeSessionId != null) 'resumeSessionId': resumeSessionId,
    if ((model ?? '').isNotEmpty) 'model': model,
    if (extraArgs.isNotEmpty) 'extraArgs': extraArgs,
    if (error != null) 'error': error,
    'active': isActive,
    'kind': 'live',
  };
}

final class TerminalChunk {
  const TerminalChunk({
    required this.output,
    required this.cursor,
    required this.dropped,
    required this.truncated,
    required this.running,
    required this.status,
    this.exitCode,
    this.hasMore = false,
    this.columns = 0,
    this.rows = 0,
  });

  final String output;
  final int cursor;
  final int dropped;
  final bool truncated;
  final bool running;
  final String status;
  final int? exitCode;
  final bool hasMore;
  final int columns;
  final int rows;

  Map<String, Object?> toJson() => {
    'output': output,
    'cursor': cursor,
    'dropped': dropped,
    'truncated': truncated,
    'running': running,
    'status': status,
    if (exitCode != null) 'exitCode': exitCode,
    'hasMore': hasMore,
    'columns': columns,
    'rows': rows,
  };
}

final class SessionMessage {
  SessionMessage({
    required this.role,
    required this.text,
    this.timestamp,
    this.kind = 'text',
  });

  final String role;
  final String text;
  final DateTime? timestamp;
  final String kind;

  Map<String, Object?> toJson() => {
    'role': role,
    'text': text,
    'kind': kind,
    if (timestamp != null) 'timestamp': timestamp!.toUtc().toIso8601String(),
  };
}

final class SessionDetail {
  SessionDetail({required this.session, required this.messages});

  final AgentSession session;
  final List<SessionMessage> messages;

  Map<String, Object?> toJson() => {
    'session': session.toJson(),
    'messages': messages.map((message) => message.toJson()).toList(),
  };
}

final class FsRoot {
  const FsRoot({required this.label, required this.path, required this.kind});

  final String label;
  final String path;
  final String kind;

  Map<String, Object?> toJson() => {
    'label': label,
    'path': path,
    'kind': kind,
  };
}

final class FsEntry {
  const FsEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.isHidden,
    this.isLink = false,
    this.size,
    this.modifiedAt,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final bool isHidden;
  final bool isLink;
  final int? size;
  final DateTime? modifiedAt;

  Map<String, Object?> toJson() => {
    'name': name,
    'path': path,
    'isDirectory': isDirectory,
    'isHidden': isHidden,
    'isLink': isLink,
    if (size != null) 'size': size,
    if (modifiedAt != null) 'modifiedAt': modifiedAt!.toUtc().toIso8601String(),
  };
}

final class FsListing {
  const FsListing({
    required this.path,
    required this.parent,
    required this.entries,
    this.truncated = false,
  });

  final String path;
  final String? parent;
  final List<FsEntry> entries;
  final bool truncated;

  Map<String, Object?> toJson() => {
    'path': path,
    'parent': parent,
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'truncated': truncated,
  };
}

final class BridgeRequest {
  const BridgeRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.headers,
    required this.body,
    this.remoteAddress,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> headers;
  final Object? body;
  final String? remoteAddress;

  String get authorization => headers['authorization'] ?? '';
}

final class BridgeResponse {
  const BridgeResponse(this.status, this.body, {this.headers = const {}});

  final int status;
  final Object? body;
  final Map<String, String> headers;
}

String encodeRef(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

String decodeRef(String value) {
  final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  return utf8.decode(base64Url.decode(padded));
}

DateTime? parseTimestamp(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is int) {
    final milliseconds = value < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }
  return null;
}

String flattenText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    return value
        .map(flattenText)
        .where((item) => item.trim().isNotEmpty)
        .join('\n');
  }
  if (value is Map) {
    for (final key in ['text', 'content', 'message', 'output', 'result']) {
      if (value.containsKey(key)) {
        final result = flattenText(value[key]);
        if (result.trim().isNotEmpty) return result;
      }
    }
  }
  return '';
}

String shortTitle(String text, {String fallback = 'Untitled session'}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return fallback;
  return normalized.length <= 80
      ? normalized
      : '${normalized.substring(0, 77)}...';
}
