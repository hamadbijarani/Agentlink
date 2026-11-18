import 'dart:async';

import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/services/settings_store.dart';
import 'src/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  final controller = AppController(settingsStore: SettingsStore());
  runApp(AgentLinkApp(controller: controller));
  unawaited(controller.initialize());
}
