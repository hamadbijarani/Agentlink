import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import '../util/format.dart';
import '../widgets/provider_badge.dart';
import 'new_session_sheet.dart';
import 'terminal_screen.dart';

final class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.controller,
    required this.session,
  });

  final AppController controller;
  final AgentSession session;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late Future<SessionDetail> _detail = widget.controller.historyDetail(
    widget.session,
  );

  Future<void> _resume() async {
    final result = await showModalBottomSheet<LiveSession>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => NewSessionSheet(
        controller: widget.controller,
        initialProvider: widget.session.provider,
        initialCwd: widget.session.projectPath,
        initialResumeId: widget.session.id,
      ),
    );
    if (result == null || !mounted) return;
    widget.controller.selectThemeProvider(result.provider);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TerminalScreen(
          controller: widget.controller,
          initial: result,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providerTheme = widget.controller
        .providerInfo(widget.session.provider)
        ?.theme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.session.provider.label} · '
              '${relativeTime(widget.session.updatedAt)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 10,
              ),
            ),
          ],
        ),
        actions: [
          if (widget.session.projectPath.isNotEmpty)
            IconButton(
              tooltip: 'Resume on the PC',
              onPressed: _resume,
              icon: const Icon(Icons.play_circle_outline),
            ),
        ],
      ),
      body: FutureBuilder<SessionDetail>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() {
                        _detail = widget.controller.historyDetail(
                          widget.session,
                        );
                      }),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final detail = snapshot.data!;
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  border: Border(
                    bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    ProviderBadge(
                      provider: widget.session.provider,
                      theme: providerTheme,
                      compact: true,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        shortenPath(widget.session.projectPath, maxLength: 60),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    Text(
                      '${detail.messages.length} messages',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: detail.messages.isEmpty
                    ? const Center(child: Text('No messages recorded.'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                        itemCount: detail.messages.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, index) =>
                            _MessageBubble(message: detail.messages[index]),
                      ),
              ),
              if (widget.session.projectPath.isNotEmpty)
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _resume,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        'Resume ${widget.session.provider.label} in this folder',
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

final class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final SessionMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == 'user';
    final accent = isUser
        ? theme.colorScheme.primary
        : const Color(0xFF4ADE80);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Text(
                isUser ? 'YOU' : message.role.toUpperCase(),
                style: TextStyle(
                  color: accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            if (message.timestamp != null) ...[
              const SizedBox(width: 8),
              Text(
                fileTimestamp(message.timestamp),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: SelectableText(
            message.text,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ),
      ],
    );
  }
}
