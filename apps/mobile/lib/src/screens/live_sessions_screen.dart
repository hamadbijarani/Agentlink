import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import '../util/format.dart';
import '../widgets/empty_state.dart';
import '../widgets/provider_badge.dart';
import 'terminal_screen.dart';

final class LiveSessionsScreen extends StatelessWidget {
  const LiveSessionsScreen({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final AppController controller;
  final Future<void> Function(LiveSession session) onOpen;

  @override
  Widget build(BuildContext context) {
    final active = controller.activeSessions;
    final ended = controller.endedSessions;
    if (controller.liveLoading && controller.liveSessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.liveSessions.isEmpty) {
      return const EmptyState(
        icon: Icons.terminal_outlined,
        title: 'No live sessions',
        message:
            'Start an agent on your PC from the button below. '
            'The real CLI opens on the desktop and stays controllable here.',
      );
    }
    return RefreshIndicator(
      onRefresh: controller.refreshLive,
      child: Scrollbar(
        interactive: true,
        thumbVisibility: false,
        thickness: 5,
        radius: const Radius.circular(3),
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
        children: [
          if (active.isNotEmpty) ...[
            const _SectionLabel('RUNNING'),
            ...active.map(
              (session) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SessionCard(
                  controller: controller,
                  session: session,
                  onOpen: () => onOpen(session),
                ),
              ),
            ),
          ],
          if (ended.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _SectionLabel('RECENTLY ENDED'),
            ...ended.map(
              (session) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SessionCard(
                  controller: controller,
                  session: session,
                  onOpen: () => onOpen(session),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

final class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 1.4,
        color: Theme.of(context).colorScheme.outline,
      ),
    ),
  );
}

final class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.controller,
    required this.session,
    required this.onOpen,
  });

  final AppController controller;
  final LiveSession session;
  final VoidCallback onOpen;

  Future<void> _attach(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await controller.attachToDesktop(session.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Opened a desktop terminal for this session.'
                : 'The PC could not open a desktop terminal.',
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _rename(BuildContext context) async {
    final text = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename session'),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    text.dispose();
    if (title == null || title.isEmpty || !context.mounted) return;
    try {
      await controller.renameSession(session.id, title);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _restart(BuildContext context) async {
    try {
      final restarted = await controller.restartLiveSession(session);
      if (!context.mounted) return;
      controller.selectThemeProvider(restarted.provider);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TerminalScreen(
            controller: controller,
            initial: restarted,
          ),
        ),
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _stop(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close session?'),
        content: Text(
          'This stops the real ${session.provider.label} process on the PC '
          'and closes its terminal. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.stopSession(session.id);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerTheme = controller.providerInfo(session.provider)?.theme;
    final outline = Theme.of(context).colorScheme.outline;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProviderBadge(
                    provider: session.provider,
                    theme: providerTheme,
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                  SessionStatusChip(session: session),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: 'Session actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'attach':
                          _attach(context);
                        case 'rename':
                          _rename(context);
                        case 'restart':
                          _restart(context);
                        case 'stop':
                          _stop(context);
                      }
                    },
                    itemBuilder: (context) => [
                      if (session.isActive)
                        const PopupMenuItem(
                          value: 'attach',
                          child: ListTile(
                            leading: Icon(Icons.open_in_new),
                            title: Text('Open on desktop'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (session.isActive)
                        const PopupMenuItem(
                          value: 'rename',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Rename'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (session.isActive)
                        const PopupMenuItem(
                          value: 'stop',
                          child: ListTile(
                            leading: Icon(Icons.stop_circle_outlined),
                            title: Text('Close session'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (!session.isActive)
                        const PopupMenuItem(
                          value: 'restart',
                          child: ListTile(
                            leading: Icon(Icons.restart_alt),
                            title: Text('Restart'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  session.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(Icons.folder_outlined, size: 13, color: outline),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      shortenPath(session.cwd),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: outline,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    elapsedLabel(session.startedAt, endedAt: session.endedAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: outline,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (session.desktopAttached) ...[
                    Icon(Icons.desktop_windows_outlined, size: 13, color: outline),
                    const SizedBox(width: 4),
                    Text(
                      session.desktopTerminal ?? 'desktop',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: outline,
                        fontSize: 10,
                      ),
                    ),
                  ],
                  if (session.exitCode != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      'exit ${session.exitCode}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: session.status == 'failed'
                            ? Theme.of(context).colorScheme.error
                            : outline,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
              if (session.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  session.error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
