import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

bool _constantTimeEquals(String left, String right) {
  final a = utf8.encode(left);
  final b = utf8.encode(right);
  var diff = a.length ^ b.length;
  final max = a.length > b.length ? a.length : b.length;
  for (var index = 0; index < max; index++) {
    final av = index < a.length ? a[index] : 0;
    final bv = index < b.length ? b[index] : 0;
    diff |= av ^ bv;
  }
  return diff == 0;
}

final class RelayBridgeRecord {
  RelayBridgeRecord({
    required this.id,
    required this.secretHash,
    required this.name,
    required this.createdAt,
    required this.lastSeenAt,
  });

  final String id;
  final String secretHash;
  final String name;
  final String createdAt;
  String lastSeenAt;

  Map<String, Object?> toJson() => {
    'secretHash': secretHash,
    'name': name,
    'createdAt': createdAt,
    'lastSeenAt': lastSeenAt,
  };

  factory RelayBridgeRecord.fromJson(
    String id,
    Map<String, dynamic> json,
  ) => RelayBridgeRecord(
    id: id,
    secretHash: json['secretHash']?.toString() ?? '',
    name: json['name']?.toString() ?? 'AgentLink bridge',
    createdAt: json['createdAt']?.toString() ?? '',
    lastSeenAt: json['lastSeenAt']?.toString() ?? '',
  );
}

/// Persists bridge registrations so a relay restart does not let anyone who
/// guesses a public bridge id take over an existing route.
final class RelayStore {
  RelayStore({File? file}) : file = file ?? _defaultFile();

  final File file;
  final Map<String, RelayBridgeRecord> _bridges = {};

  Future<void> load() async {
    if (!await file.exists()) return;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return;
    for (final entry in decoded.entries) {
      if (entry.value is Map) {
        final record = RelayBridgeRecord.fromJson(
          entry.key.toString(),
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (record.id.isNotEmpty && record.secretHash.isNotEmpty) {
          _bridges[record.id] = record;
        }
      }
    }
  }

  RelayBridgeRecord? find(String bridgeId) => _bridges[bridgeId];

  /// Returns the record if the bridge is authorized. A new bridge id is
  /// registered on first use; an existing id must present the same secret.
  Future<RelayBridgeRecord?> authorize({
    required String bridgeId,
    required String secret,
    required String name,
    required bool allowRegister,
  }) async {
    final existing = _bridges[bridgeId];
    if (existing != null) {
      if (!_constantTimeEquals(existing.secretHash, _hash(secret))) {
        return null;
      }
      existing.lastSeenAt = DateTime.now().toUtc().toIso8601String();
      await save();
      return existing;
    }
    if (!allowRegister) return null;
    final record = RelayBridgeRecord(
      id: bridgeId,
      secretHash: _hash(secret),
      name: name,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      lastSeenAt: DateTime.now().toUtc().toIso8601String(),
    );
    _bridges[bridgeId] = record;
    await save();
    return record;
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final payload = <String, Object?>{
      for (final entry in _bridges.entries) entry.key: entry.value.toJson(),
    };
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
      flush: true,
    );
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', temp.path]);
      } on ProcessException {
        // Best effort.
      }
    }
    await temp.rename(file.path);
  }

  static File _defaultFile() {
    final override = Platform.environment['AGENTLINK_RELAY_STATE'];
    if (override != null && override.isNotEmpty) return File(override);
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return File('$home/.agentlink/relay.json');
  }
}
