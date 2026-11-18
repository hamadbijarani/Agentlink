import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'screens/connection_screen.dart';
import 'screens/home_screen.dart';

final class AgentLinkApp extends StatelessWidget {
  const AgentLinkApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final theme = _buildTheme(controller.theme);
      return MaterialApp(
        title: 'AgentLink',
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: controller.profile == null
            ? ConnectionScreen(controller: controller)
            : HomeScreen(controller: controller),
      );
    },
  );
}

ThemeData _buildTheme(ProviderTheme theme) {
  final background = Color(colorValue(theme.background));
  final foreground = Color(colorValue(theme.foreground));
  final surface = Color(colorValue(theme.surface));
  final border = Color(colorValue(theme.border));
  final accent = Color(colorValue(theme.accent));
  final muted = Color(colorValue(theme.muted));

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
    onPrimary: background,
    secondary: accent,
    onSecondary: background,
    surface: background,
    onSurface: foreground,
    surfaceContainer: surface,
    surfaceContainerHigh: surface,
    surfaceContainerLow: background,
    outline: border,
    outlineVariant: border,
    error: const Color(0xFFFF6B6B),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    fontFamily: 'monospace',
    dividerColor: border,
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: foreground,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        fontFamily: 'monospace',
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: accent.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontFamily: 'monospace'),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? accent : muted,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent),
      ),
      labelStyle: TextStyle(color: muted),
      hintStyle: TextStyle(color: muted.withValues(alpha: 0.8)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: TextStyle(color: foreground),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: accent.withValues(alpha: 0.18),
      side: BorderSide(color: border),
      labelStyle: TextStyle(color: foreground, fontFamily: 'monospace'),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: background,
    ),
    textTheme: Typography.material2021().white.apply(
      bodyColor: foreground,
      displayColor: foreground,
      fontFamily: 'monospace',
    ),
  );
}
