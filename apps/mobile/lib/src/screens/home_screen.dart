import 'dart:async';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'history_screen.dart';
import 'live_sessions_screen.dart';
import 'new_session_sheet.dart';
import 'settings_screen.dart';
import 'terminal_screen.dart';

final class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  var _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.refreshLive());
      unawaited(widget.controller.refreshProviders());
    }
  }

  static const _titles = ['Live sessions', 'History', 'Settings'];

  Future<void> _newSession() async {
    final session = await showModalBottomSheet<LiveSession>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => NewSessionSheet(controller: widget.controller),
    );
    if (session != null && mounted) await _openTerminal(session);
  }

  Future<void> _openTerminal(LiveSession session) async {
    widget.controller.selectThemeProvider(session.provider);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TerminalScreen(
          controller: widget.controller,
          initial: session,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final pages = [
        LiveSessionsScreen(controller: controller, onOpen: _openTerminal),
        HistoryScreen(controller: controller),
        SettingsScreen(controller: controller),
      ];
      return Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _titles[_index],
                style: const TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  _StatusDot(connected: controller.isConnected),
                  const SizedBox(width: 6),
                  Text(
                    controller.profile?.bridgeName ?? 'AgentLink',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: controller.refreshAll,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            if (controller.error != null)
              _ConnectionBanner(
                message: controller.error!,
                onDismiss: controller.clearError,
                onRetry: controller.retry,
              ),
            Expanded(child: pages[_index]),
          ],
        ),
        floatingActionButton: _index == 2
            ? null
            : FloatingActionButton.extended(
                onPressed: _newSession,
                icon: const Icon(Icons.add),
                label: const Text('New session'),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: [
            NavigationDestination(
              icon: controller.activeSessions.isEmpty
                  ? const Icon(Icons.terminal_outlined)
                  : Badge(
                      label: Text('${controller.activeSessions.length}'),
                      child: const Icon(Icons.terminal_outlined),
                    ),
              selectedIcon: const Icon(Icons.terminal),
              label: 'Live',
            ),
            const NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      );
    },
  );
}

final class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: connected ? const Color(0xFF4ADE80) : const Color(0xFFFACC15),
    ),
  );
}

final class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.message,
    required this.onDismiss,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onDismiss;
  final Future<bool> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
    color: const Color(0xFFFACC15).withValues(alpha: 0.1),
    child: Row(
      children: [
        const Icon(Icons.wifi_tethering_error, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(
          onPressed: () => onRetry(),
          child: const Text('Retry'),
        ),
        IconButton(
          onPressed: onDismiss,
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Dismiss',
        ),
      ],
    ),
  );
}
