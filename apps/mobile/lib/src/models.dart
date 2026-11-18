enum AgentProvider {
  claude('claude', 'Claude Code'),
  opencode('opencode', 'OpenCode'),
  codex('codex', 'Codex CLI'),
  gemini('gemini', 'Gemini CLI');

  const AgentProvider(this.id, this.label);

  final String id;
  final String label;

  static AgentProvider? fromIdOrNull(String? value) {
    for (final provider in values) {
      if (provider.id == value) return provider;
    }
    return null;
  }

  static AgentProvider fromId(String value) =>
      fromIdOrNull(value) ?? AgentProvider.opencode;
}

final class ConnectionProfile {
  const ConnectionProfile({
    required this.bridgeId,
    required this.bridgeName,
    required this.desktopName,
    required this.deviceToken,
    this.relayUrl = '',
    this.relayToken = '',
    this.endpoints = const [],
    this.pairedAt,
    this.deviceName = 'Android device',
  });

  final String bridgeId;
  final String bridgeName;
  final String desktopName;
  final String deviceToken;
  final String relayUrl;
  final String relayToken;
  final List<String> endpoints;
  final DateTime? pairedAt;
  final String deviceName;

  bool get usesRelay => relayUrl.trim().isNotEmpty;

  String get connectionLabel => usesRelay ? 'Internet relay' : 'LAN direct';

  String get primaryEndpoint =>
      endpoints.isEmpty ? '' : endpoints.first.trim();

  Map<String, Object?> toJson() => {
    'version': 1,
    'bridgeId': bridgeId,
    'bridgeName': bridgeName,
    'desktopName': desktopName,
    'deviceToken': deviceToken,
    'relayUrl': relayUrl,
    'relayToken': relayToken,
    'endpoints': endpoints,
    if (pairedAt != null) 'pairedAt': pairedAt!.toUtc().toIso8601String(),
    'deviceName': deviceName,
  };

  factory ConnectionProfile.fromJson(Map<String, dynamic> json) {
    final endpoints = (json['endpoints'] as List? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return ConnectionProfile(
      bridgeId: json['bridgeId']?.toString() ?? '',
      bridgeName: json['bridgeName']?.toString() ?? 'AgentLink desktop',
      desktopName:
          json['desktopName']?.toString() ??
          json['bridgeName']?.toString() ??
          'AgentLink desktop',
      deviceToken: json['deviceToken']?.toString() ?? '',
      relayUrl: json['relayUrl']?.toString() ?? '',
      relayToken: json['relayToken']?.toString() ?? '',
      endpoints: endpoints,
      pairedAt: DateTime.tryParse(json['pairedAt']?.toString() ?? ''),
      deviceName: json['deviceName']?.toString() ?? 'Android device',
    );
  }
}

final class PairingPayload {
  const PairingPayload({
    required this.bridgeId,
    required this.name,
    required this.secret,
    this.relayUrl = '',
    this.relayToken = '',
    this.endpoints = const [],
  });

  final String bridgeId;
  final String name;
  final String secret;
  final String relayUrl;
  final String relayToken;
  final List<String> endpoints;

  Uri toUri() => Uri(
    scheme: 'agentlink',
    host: 'pair',
    queryParameters: {
      'v': '1',
      'bridge': bridgeId,
      'name': name,
      'secret': secret,
      if (relayUrl.isNotEmpty) 'relay': relayUrl,
      if (relayToken.isNotEmpty) 'relayToken': relayToken,
      if (endpoints.isNotEmpty) 'endpoints': endpoints.join(','),
    },
  );

  String encode() => toUri().toString();

  static PairingPayload? tryParse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'agentlink') return null;
    if (uri.host != 'pair' && uri.path != '/pair') return null;
    final params = uri.queryParameters;
    final bridgeId = params['bridge'] ?? '';
    final secret = params['secret'] ?? '';
    if (bridgeId.isEmpty || secret.length < 16) return null;
    final endpoints = (params['endpoints'] ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return PairingPayload(
      bridgeId: bridgeId,
      name: params['name'] ?? 'AgentLink desktop',
      secret: secret,
      relayUrl: params['relay'] ?? '',
      relayToken: params['relayToken'] ?? '',
      endpoints: endpoints,
    );
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

  factory ProviderTheme.fromJson(Map<String, dynamic> json) => ProviderTheme(
    name: json['name']?.toString() ?? 'Terminal',
    background: json['background']?.toString() ?? '#0B0B0C',
    foreground: json['foreground']?.toString() ?? '#EDEDED',
    accent: json['accent']?.toString() ?? '#F5A742',
    muted: json['muted']?.toString() ?? '#8B8B8B',
    surface: json['surface']?.toString() ?? '#161617',
    border: json['border']?.toString() ?? '#2C2C2E',
  );

  static const fallback = ProviderTheme(
    name: 'Agent Graphite',
    background: '#0B0B0C',
    foreground: '#EDEDED',
    accent: '#F5A742',
    muted: '#8B8B8B',
    surface: '#161617',
    border: '#2C2C2E',
  );
}

final class ProviderInfo {
  const ProviderInfo({
    required this.provider,
    required this.label,
    required this.available,
    required this.theme,
    required this.command,
    this.version,
    this.canResume = false,
    this.capabilities = const {},
  });

  final AgentProvider provider;
  final String label;
  final bool available;
  final String? version;
  final ProviderTheme theme;
  final String command;
  final bool canResume;
  final Map<String, bool> capabilities;

  factory ProviderInfo.fromJson(Map<String, dynamic> json) {
    final capabilities = <String, bool>{};
    final raw = json['capabilities'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        capabilities[entry.key.toString()] = entry.value == true;
      }
    }
    return ProviderInfo(
      provider: AgentProvider.fromId(json['id']?.toString() ?? ''),
      label: json['label']?.toString() ?? 'Agent',
      available: json['available'] == true,
      version: json['version']?.toString(),
      theme: ProviderTheme.fromJson(
        json['theme'] is Map
            ? Map<String, dynamic>.from(json['theme'] as Map)
            : const {},
      ),
      command: json['command']?.toString() ?? '',
      canResume: capabilities['resume'] ?? false,
      capabilities: capabilities,
    );
  }
}

final class AgentSession {
  const AgentSession({
    required this.id,
    required this.ref,
    required this.provider,
    required this.title,
    required this.projectPath,
    required this.updatedAt,
    required this.messageCount,
  });

  factory AgentSession.fromJson(Map<String, dynamic> json) => AgentSession(
    id: json['id']?.toString() ?? '',
    ref: json['ref']?.toString() ?? '',
    provider: AgentProvider.fromId(json['provider']?.toString() ?? ''),
    title: json['title']?.toString() ?? 'Untitled session',
    projectPath: json['projectPath']?.toString() ?? '',
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal() ??
        DateTime(1970),
    messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String ref;
  final AgentProvider provider;
  final String title;
  final String projectPath;
  final DateTime updatedAt;
  final int messageCount;
}

final class SessionMessage {
  const SessionMessage({
    required this.role,
    required this.text,
    required this.kind,
    this.timestamp,
  });

  factory SessionMessage.fromJson(Map<String, dynamic> json) => SessionMessage(
    role: json['role']?.toString() ?? 'assistant',
    text: json['text']?.toString() ?? '',
    kind: json['kind']?.toString() ?? 'text',
    timestamp: DateTime.tryParse(
      json['timestamp']?.toString() ?? '',
    )?.toLocal(),
  );

  final String role;
  final String text;
  final String kind;
  final DateTime? timestamp;
}

final class SessionDetail {
  const SessionDetail({required this.session, required this.messages});

  factory SessionDetail.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List? ?? const [];
    return SessionDetail(
      session: AgentSession.fromJson(
        Map<String, dynamic>.from(json['session'] as Map),
      ),
      messages: rawMessages
          .whereType<Map>()
          .map(
            (item) => SessionMessage.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  final AgentSession session;
  final List<SessionMessage> messages;
}

final class LiveSession {
  const LiveSession({
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
    this.desktopAttached = false,
    this.desktopTerminal,
    this.error,
  });

  factory LiveSession.fromJson(Map<String, dynamic> json) => LiveSession(
    id: json['id']?.toString() ?? '',
    provider: AgentProvider.fromId(json['provider']?.toString() ?? ''),
    title: json['title']?.toString() ?? 'Agent session',
    cwd: json['cwd']?.toString() ?? '',
    startedAt:
        DateTime.tryParse(json['startedAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    status: json['status']?.toString() ?? 'unknown',
    openOnDesktop: json['openOnDesktop'] == true,
    columns: (json['columns'] as num?)?.toInt() ?? 100,
    rows: (json['rows'] as num?)?.toInt() ?? 32,
    outputCursor: (json['outputCursor'] as num?)?.toInt() ?? 0,
    exitCode: (json['exitCode'] as num?)?.toInt(),
    endedAt: DateTime.tryParse(
      json['endedAt']?.toString() ?? '',
    )?.toLocal(),
    initialPrompt: json['initialPrompt']?.toString(),
    resumeSessionId: json['resumeSessionId']?.toString(),
    desktopAttached: json['desktopAttached'] == true,
    desktopTerminal: json['desktopTerminal']?.toString(),
    error: json['error']?.toString(),
  );

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
  final bool desktopAttached;
  final String? desktopTerminal;
  final String? error;

  bool get isRunning => status == 'running' || status == 'starting';
  bool get isStopping => status == 'stopping';
  bool get isActive => isRunning || isStopping;

  String get statusLabel => switch (status) {
    'starting' => 'Starting',
    'running' => 'Running',
    'stopping' => 'Stopping',
    'stopped' => 'Stopped',
    'exited' => 'Exited',
    'failed' => 'Failed',
    _ => status,
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

  factory TerminalChunk.fromJson(Map<String, dynamic> json) => TerminalChunk(
    output: json['output']?.toString() ?? '',
    cursor: (json['cursor'] as num?)?.toInt() ?? 0,
    dropped: (json['dropped'] as num?)?.toInt() ?? 0,
    truncated: json['truncated'] == true,
    running: json['running'] == true,
    status: json['status']?.toString() ?? 'unknown',
    exitCode: (json['exitCode'] as num?)?.toInt(),
    hasMore: json['hasMore'] == true,
    columns: (json['columns'] as num?)?.toInt() ?? 0,
    rows: (json['rows'] as num?)?.toInt() ?? 0,
  );

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
}

final class FsRoot {
  const FsRoot({required this.label, required this.path, required this.kind});

  factory FsRoot.fromJson(Map<String, dynamic> json) => FsRoot(
    label: json['label']?.toString() ?? 'Folder',
    path: json['path']?.toString() ?? '',
    kind: json['kind']?.toString() ?? 'folder',
  );

  final String label;
  final String path;
  final String kind;
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

  factory FsEntry.fromJson(Map<String, dynamic> json) => FsEntry(
    name: json['name']?.toString() ?? '',
    path: json['path']?.toString() ?? '',
    isDirectory: json['isDirectory'] == true,
    isHidden: json['isHidden'] == true,
    isLink: json['isLink'] == true,
    size: (json['size'] as num?)?.toInt(),
    modifiedAt: DateTime.tryParse(
      json['modifiedAt']?.toString() ?? '',
    )?.toLocal(),
  );

  final String name;
  final String path;
  final bool isDirectory;
  final bool isHidden;
  final bool isLink;
  final int? size;
  final DateTime? modifiedAt;

  String get sizeLabel {
    final bytes = size;
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

final class FsListing {
  const FsListing({
    required this.path,
    required this.parent,
    required this.entries,
    this.truncated = false,
  });

  factory FsListing.fromJson(Map<String, dynamic> json) => FsListing(
    path: json['path']?.toString() ?? '',
    parent: json['parent']?.toString(),
    truncated: json['truncated'] == true,
    entries: (json['entries'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => FsEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
  );

  final String path;
  final String? parent;
  final List<FsEntry> entries;
  final bool truncated;
}

final class PairingDevice {
  const PairingDevice({
    required this.name,
    required this.platform,
    required this.pairedAt,
  });

  factory PairingDevice.fromJson(Map<String, dynamic> json) => PairingDevice(
    name: json['name']?.toString() ?? 'Android device',
    platform: json['platform']?.toString() ?? 'android',
    pairedAt: DateTime.tryParse(
      json['pairedAt']?.toString() ?? '',
    )?.toLocal(),
  );

  final String name;
  final String platform;
  final DateTime? pairedAt;
}

final class RelayInfo {
  const RelayInfo({
    required this.state,
    required this.url,
    required this.configured,
    this.error,
  });

  factory RelayInfo.fromJson(Map<String, dynamic> json) => RelayInfo(
    state: json['state']?.toString() ?? 'disabled',
    url: json['url']?.toString() ?? '',
    configured: json['configured'] == true,
    error: json['error']?.toString(),
  );

  final String state;
  final String url;
  final bool configured;
  final String? error;

  bool get connected => state == 'connected';
}

final class BridgeInfo {
  const BridgeInfo({
    required this.name,
    required this.version,
    required this.bridgeId,
    required this.desktopName,
    required this.platform,
    required this.hostname,
    required this.paired,
    required this.relay,
    required this.endpoints,
    this.device,
    this.httpHost = '',
    this.httpPort = 0,
    this.openDesktopByDefault = false,
    this.desktopSupported = false,
  });

  factory BridgeInfo.fromJson(Map<String, dynamic> json) {
    final device = json['device'];
    final relay = json['relay'];
    final http = json['http'];
    final desktop = json['desktop'];
    return BridgeInfo(
      name: json['name']?.toString() ?? 'AgentLink desktop bridge',
      version: json['version']?.toString() ?? '',
      bridgeId: json['bridgeId']?.toString() ?? '',
      desktopName: json['desktopName']?.toString() ?? 'AgentLink desktop',
      platform: json['platform']?.toString() ?? '',
      hostname: json['hostname']?.toString() ?? '',
      paired: json['paired'] == true,
      relay: RelayInfo.fromJson(
        relay is Map ? Map<String, dynamic>.from(relay) : const {},
      ),
      endpoints: (json['endpoints'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      device: device is Map
          ? PairingDevice.fromJson(Map<String, dynamic>.from(device))
          : null,
      httpHost: http is Map ? http['host']?.toString() ?? '' : '',
      httpPort: http is Map ? (http['port'] as num?)?.toInt() ?? 0 : 0,
      openDesktopByDefault: desktop is Map
          ? desktop['openByDefault'] == true
          : false,
      desktopSupported: desktop is Map
          ? desktop['supported'] == true
          : false,
    );
  }

  final String name;
  final String version;
  final String bridgeId;
  final String desktopName;
  final String platform;
  final String hostname;
  final bool paired;
  final RelayInfo relay;
  final List<String> endpoints;
  final PairingDevice? device;
  final String httpHost;
  final int httpPort;
  final bool openDesktopByDefault;
  final bool desktopSupported;
}

final class PairingResult {
  const PairingResult({
    required this.profile,
    required this.providers,
  });

  final ConnectionProfile profile;
  final List<ProviderInfo> providers;
}

int colorValue(String hex) {
  final clean = hex.replaceFirst('#', '').trim();
  final value = int.tryParse(clean, radix: 16) ?? 0xF5A742;
  return 0xFF000000 | (value & 0xFFFFFF);
}
