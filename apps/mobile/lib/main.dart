import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(settingsStore: SettingsStore());
  runApp(AgentLinkApp(controller: controller));
  unawaited(controller.initialize());
}
