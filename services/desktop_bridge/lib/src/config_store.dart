import 'dart:convert';
import 'dart:io';

import 'util.dart';

const _unset = Object();

final class ConfigException implements Exception {
  const ConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DeviceRecord {
  const DeviceRecord({
    required this.id,
    required this.name,
    required this.platform,
    required this.tokenHash,
    required this.pairedAt,
  });

  final String id;
  final String name;
  final String platform;
  final String tokenHash;
  final String pairedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'tokenHash': tokenHash,
    'pairedAt': pairedAt,
  };

  factory DeviceRecord.fromJson(Map<String, dynamic> json) => DeviceRecord(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Android device',
    platform: json['platform']?.toString() ?? 'android',
    tokenHash: json['tokenHash']?.toString() ?? '',
    pairedAt: json['pairedAt']?.toString() ?? nowIso(),
  );
}

final class BridgeConfig {
  const BridgeConfig({
    required this.bridgeId,
    required this.name,
    required this.createdAt,
    required this.relayUrl,
    required this.relayToken,
    required this.relaySecret,
    required this.httpHost,
    required this.httpPort,
    this.httpsCert = '',
    this.httpsKey = '',
    required this.openDesktopByDefault,
    required this.localAttachToken,
    required this.device,
    required this.pairingSecret,
    required this.pairingCreatedAt,
  });

  final String bridgeId;
  final String name;
  final String createdAt;
  final String relayUrl;
  final String relayToken;
  final String relaySecret;
  final String httpHost;
  final int httpPort;
  final String httpsCert;
  final String httpsKey;
  final bool openDesktopByDefault;
  final String localAttachToken;
  final DeviceRecord? device;
  final String? pairingSecret;
  final String? pairingCreatedAt;

  bool get isPaired => device != null;
  bool get relayEnabled => relayUrl.isNotEmpty;
  bool get tlsEnabled => httpsCert.isNotEmpty && httpsKey.isNotEmpty;
  bool get canPair => !isPaired && pairingSecret != null;

  BridgeConfig copyWith({
    String? name,
    String? relayUrl,
    String? relayToken,
    String? relaySecret,
    String? httpHost,
    int? httpPort,
    String? httpsCert,
    String? httpsKey,
    bool? openDesktopByDefault,
    String? localAttachToken,
    Object? device = _unset,
    Object? pairingSecret = _unset,
    Object? pairingCreatedAt = _unset,
  }) => BridgeConfig(
    bridgeId: bridgeId,
    name: name ?? this.name,
    createdAt: createdAt,
    relayUrl: relayUrl ?? this.relayUrl,
    relayToken: relayToken ?? this.relayToken,
    relaySecret: relaySecret ?? this.relaySecret,
    httpHost: httpHost ?? this.httpHost,
    httpPort: httpPort ?? this.httpPort,
    httpsCert: httpsCert ?? this.httpsCert,
    httpsKey: httpsKey ?? this.httpsKey,
    openDesktopByDefault:
        openDesktopByDefault ?? this.openDesktopByDefault,
    localAttachToken: localAttachToken ?? this.localAttachToken,
    device: device == _unset ? this.device : device as DeviceRecord?,
    pairingSecret: pairingSecret == _unset
        ? this.pairingSecret
        : pairingSecret as String?,
    pairingCreatedAt: pairingCreatedAt == _unset
        ? this.pairingCreatedAt
        : pairingCreatedAt as String?,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'bridgeId': bridgeId,
    'name': name,
    'createdAt': createdAt,
    'relay': {
      'url': relayUrl,
      'token': relayToken,
      'secret': relaySecret,
    },
    'http': {
      'host': httpHost,
      'port': httpPort,
      'tlsCert': httpsCert,
      'tlsKey': httpsKey,
    },
    'desktop': {
      'openByDefault': openDesktopByDefault,
    },
    'localAttachToken': localAttachToken,
    'device': device?.toJson(),
    'pairing': pairingSecret == null
        ? null
        : {
            'secret': pairingSecret,
            'createdAt': pairingCreatedAt,
          },
  };

  factory BridgeConfig.fromJson(Map<String, dynamic> json) {
    final relay = json['relay'] is Map
        ? Map<String, dynamic>.from(json['relay'] as Map)
        : const <String, dynamic>{};
    final http = json['http'] is Map
        ? Map<String, dynamic>.from(json['http'] as Map)
        : const <String, dynamic>{};
    final desktop = json['desktop'] is Map
        ? Map<String, dynamic>.from(json['desktop'] as Map)
        : const <String, dynamic>{};
    final pairing = json['pairing'] is Map
        ? Map<String, dynamic>.from(json['pairing'] as Map)
        : null;
    final device = json['device'] is Map
        ? DeviceRecord.fromJson(
            Map<String, dynamic>.from(json['device'] as Map),
          )
        : null;
    return BridgeConfig(
      bridgeId: json['bridgeId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'AgentLink desktop',
      createdAt: json['createdAt']?.toString() ?? nowIso(),
      relayUrl: relay['url']?.toString() ?? '',
      relayToken: relay['token']?.toString() ?? '',
      relaySecret: relay['secret']?.toString() ?? '',
      httpHost: http['host']?.toString() ?? '0.0.0.0',
      httpPort: (http['port'] as num?)?.toInt() ?? 7331,
      httpsCert: http['tlsCert']?.toString() ?? '',
      httpsKey: http['tlsKey']?.toString() ?? '',
      openDesktopByDefault: desktop['openByDefault'] as bool? ?? true,
      localAttachToken: json['localAttachToken']?.toString() ?? '',
      device: device,
      pairingSecret: pairing?['secret']?.toString(),
      pairingCreatedAt: pairing?['createdAt']?.toString(),
    );
  }
}

final class ConfigStore {
  ConfigStore({File? file}) : file = file ?? defaultConfigFile();

  final File file;
  BridgeConfig? _current;

  BridgeConfig get current {
    final value = _current;
    if (value == null) {
      throw const ConfigException('Bridge configuration is not loaded.');
    }
    return value;
  }

  bool get isLoaded => _current != null;

  Future<BridgeConfig> loadOrCreate() async {
    if (await file.exists()) {
      BridgeConfig config;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) {
          throw const FormatException('Expected a JSON object');
        }
        config = BridgeConfig.fromJson(Map<String, dynamic>.from(decoded));
      } on FormatException catch (error) {
        throw ConfigException(
          'Could not parse ${file.path}: ${error.message}. '
          'Move the file away to create a fresh configuration.',
        );
      }
      if (config.bridgeId.isEmpty) {
        throw ConfigException(
          '${file.path} has no bridgeId. Move it away to repair the bridge.',
        );
      }
      var repaired = config.copyWith(
        relaySecret: config.relaySecret.isEmpty
            ? randomToken(32)
            : config.relaySecret,
        localAttachToken: config.localAttachToken.isEmpty
            ? randomToken(32)
            : config.localAttachToken,
        name: config.name.trim().isEmpty ? hostname() : config.name,
      );
      if (repaired.device != null) {
        repaired = repaired.copyWith(
          pairingSecret: null,
          pairingCreatedAt: null,
        );
      } else if (repaired.pairingSecret == null ||
          repaired.pairingSecret!.isEmpty) {
        repaired = repaired.copyWith(
          pairingSecret: randomToken(18),
          pairingCreatedAt: nowIso(),
        );
      }
      _current = repaired;
      if (repaired != config) await save(repaired);
      return repaired;
    }

    final config = BridgeConfig(
      bridgeId: randomId(10),
      name: hostname(),
      createdAt: nowIso(),
      relayUrl: '',
      relayToken: '',
      relaySecret: randomToken(32),
      httpHost: '0.0.0.0',
      httpPort: 7331,
      openDesktopByDefault: true,
      localAttachToken: randomToken(32),
      device: null,
      pairingSecret: randomToken(18),
      pairingCreatedAt: nowIso(),
    );
    _current = config;
    await save(config);
    return config;
  }

  Future<void> save(BridgeConfig config) async {
    _current = config;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(config.toJson())}\n',
      flush: true,
    );
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', temp.path]);
      } on ProcessException {
        // Best effort. The file is still only in the user's home directory.
      }
    }
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      await temp.copy(file.path);
      try {
        await temp.delete();
      } on FileSystemException {
        // Ignore cleanup failure.
      }
    }
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } on ProcessException {
        // Best effort.
      }
    }
  }

  Future<BridgeConfig> configure({
    String? name,
    String? relayUrl,
    String? relayToken,
    String? httpHost,
    int? httpPort,
    String? httpsCert,
    String? httpsKey,
    bool? openDesktopByDefault,
    bool clearRelay = false,
  }) async {
    final config = current.copyWith(
      name: name,
      relayUrl: clearRelay ? '' : relayUrl,
      relayToken: clearRelay ? '' : relayToken,
      httpHost: httpHost,
      httpPort: httpPort,
      openDesktopByDefault: openDesktopByDefault,
    );
    await save(config);
    return config;
  }

  bool verifyDeviceToken(String token) {
    final device = current.device;
    if (device == null || token.isEmpty) return false;
    return constantTimeEquals(device.tokenHash, sha256Hex(token));
  }

  bool verifyPairingSecret(String secret) {
    final expected = current.pairingSecret;
    if (expected == null || expected.isEmpty || current.isPaired) return false;
    final created = DateTime.tryParse(current.pairingCreatedAt ?? '');
    if (created != null &&
        DateTime.now().toUtc().difference(created.toUtc()) >
            const Duration(minutes: 10)) {
      return false;
    }
    return constantTimeEquals(expected, secret);
  }

  Future<PairingGrant> pairDevice({
    required String deviceName,
    required String platform,
  }) async {
    final config = current;
    if (config.isPaired) {
      throw const ConfigException('This PC is already paired.');
    }
    final token = randomToken(32);
    final device = DeviceRecord(
      id: randomId(10),
      name: deviceName.trim().isEmpty ? 'Android device' : deviceName.trim(),
      platform: platform.trim().isEmpty ? 'android' : platform.trim(),
      tokenHash: sha256Hex(token),
      pairedAt: nowIso(),
    );
    final updated = config.copyWith(
      device: device,
      pairingSecret: null,
      pairingCreatedAt: null,
    );
    await save(updated);
    return PairingGrant(device: device, token: token, config: updated);
  }

  Future<BridgeConfig> resetDevice() async {
    final updated = current.copyWith(
      device: null,
      pairingSecret: randomToken(18),
      pairingCreatedAt: nowIso(),
    );
    await save(updated);
    return updated;
  }

  static File defaultConfigFile() {
    final override = Platform.environment['AGENTLINK_CONFIG'];
    if (override != null && override.isNotEmpty) return File(override);
    return File('${homeDirectory()}/.agentlink/bridge.json');
  }
}

final class PairingGrant {
  const PairingGrant({
    required this.device,
    required this.token,
    required this.config,
  });

  final DeviceRecord device;
  final String token;
  final BridgeConfig config;
}
