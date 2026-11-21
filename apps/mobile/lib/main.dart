import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/screens/onboarding_screen.dart';
import 'src/services/notification_service.dart';
import 'src/services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();

  final prefs = await SharedPreferences.getInstance();
  final onboarded = prefs.getBool('onboarded') ?? false;

  final controller = AppController(settingsStore: SettingsStore());
  runApp(
    _AppRoot(
      controller: controller,
      onboarded: onboarded,
      onOnboardComplete: () async {
        await prefs.setBool('onboarded', true);
      },
    ),
  );
  unawaited(controller.initialize());
}

class _AppRoot extends StatefulWidget {
  const _AppRoot({
    required this.controller,
    required this.onboarded,
    required this.onOnboardComplete,
  });

  final AppController controller;
  final bool onboarded;
  final Future<void> Function() onOnboardComplete;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  late bool _onboarded = widget.onboarded;

  @override
  Widget build(BuildContext context) {
    if (!_onboarded) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: OnboardingScreen(
          onComplete: () async {
            await widget.onOnboardComplete();
            setState(() => _onboarded = true);
          },
        ),
      );
    }
    return AgentLinkApp(controller: widget.controller);
  }
}
