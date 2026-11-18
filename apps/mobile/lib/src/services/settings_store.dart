import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models.dart';

final class SettingsStore {
  SettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _profileKey = 'agentlink.profile.v2';
  final FlutterSecureStorage _storage;

  Future<ConnectionProfile?> load() async {
    final raw = await _storage.read(key: _profileKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final profile = ConnectionProfile.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (profile.bridgeId.isEmpty || profile.deviceToken.isEmpty) return null;
      return profile;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(ConnectionProfile profile) => _storage.write(
    key: _profileKey,
    value: jsonEncode(profile.toJson()),
  );

  Future<void> clear() => _storage.delete(key: _profileKey);
}
