import 'dart:async';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import '../util/format.dart';
import '../widgets/empty_state.dart';
import '../widgets/provider_badge.dart';
import 'session_detail_screen.dart';

final class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();
  AgentProvider? _filter;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<AgentSession> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return widget.controller.history.where((session) {
      if (_filter != null && session.provider != _filter) return false;
      if (query.isEmpty) return true;
      return session.title.toLowerCase().contains(query) ||
          session.projectPath.toLowerCase().contains(query) ||
          session.provider.label.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (controller.historyLoading && controller.history.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      final sessions = _filtered;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (value) {
                setState(() {});
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  widget.controller.refreshHistory(query: value);
                });
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search history by title or folder',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final provider in AgentProvider.values) ...[
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(provider.label),
                    selected: _filter == provider,
                    onSelected: (_) => setState(() => _filter = provider),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: sessions.isEmpty
                ? EmptyState(
                    icon: controller.history.isEmpty
                        ? Icons.history
                        : Icons.search_off,
                    title: controller.history.isEmpty
                        ? 'No session history'
                        : 'No matching sessions',
                    message: controller.history.isEmpty
                        ? 'Past Claude Code, OpenCode, Codex, and Gemini sessions '
                              'found on the PC are listed here.'
                        : 'Try a different search or provider filter.',
                  )
                : RefreshIndicator(
                    onRefresh: controller.refreshHistory,
                    child: Scrollbar(
                      interactive: true,
                      thumbVisibility: false,
                      thickness: 5,
                      radius: const Radius.circular(3),
                      child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        final providerTheme = controller
                            .providerInfo(session.provider)
                            ?.theme;
                        return Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              controller.selectThemeProvider(session.provider);
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => SessionDetailScreen(
                                    controller: controller,
                                    session: session,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
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
                                      const Spacer(),
                                      Text(
                                        relativeTime(session.updatedAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.outline,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    session.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.folder_outlined,
                                        size: 13,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          shortenPath(session.projectPath),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.outline,
                                                fontSize: 11,
                                              ),
                                        ),
                                      ),
                                      if (session.messageCount > 0) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          '${session.messageCount} msgs',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                fontSize: 10,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.outline,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}
