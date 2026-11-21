import 'dart:convert';

import '../app_controller.dart';
import '../models.dart';

class BackupService {
  BackupService._();
  static final instance = BackupService._();

  Future<String> exportBackup(AppController controller) async {
    final profile = controller.profile;
    if (profile == null) return '';
    final data = {
      'version': 1,
      'timestamp': DateTime.now().toIso8601String(),
      'profile': profile.toJson(),
    };
    return jsonEncode(data);
  }

  Future<bool> importBackup(String json, AppController controller) async {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final profileJson = data['profile'] as Map<String, dynamic>?;
      if (profileJson == null) return false;
      final profile = ConnectionProfile.fromJson(profileJson);
      await controller.settingsStore.save(profile);
      await controller.retry();
      return true;
    } on Exception {
      return false;
    }
  }
}
