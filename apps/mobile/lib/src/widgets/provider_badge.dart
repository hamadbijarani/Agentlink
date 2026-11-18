import 'package:flutter/material.dart';

import '../models.dart';

final class ProviderBadge extends StatelessWidget {
  const ProviderBadge({
    super.key,
    required this.provider,
    this.theme,
    this.compact = false,
  });

  final AgentProvider provider;
  final ProviderTheme? theme;
  final bool compact;

  Color _color() {
    final value = theme;
    if (value != null) return Color(colorValue(value.accent));
    return switch (provider) {
      AgentProvider.claude => const Color(0xFFD97757),
      AgentProvider.opencode => const Color(0xFFF5A742),
      AgentProvider.codex => const Color(0xFF10A37F),
      AgentProvider.gemini => const Color(0xFF8AB4F8),
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        provider.label,
        style: TextStyle(
          color: color,
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

final class SessionStatusChip extends StatelessWidget {
  const SessionStatusChip({super.key, required this.session});

  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (session.status) {
      'running' => (const Color(0xFF4ADE80), Icons.play_arrow_rounded),
      'starting' => (const Color(0xFFFACC15), Icons.hourglass_top_rounded),
      'stopping' => (const Color(0xFFFB923C), Icons.stop_circle_outlined),
      'failed' => (const Color(0xFFF87171), Icons.error_outline),
      _ => (Theme.of(context).colorScheme.outline, Icons.check_circle_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            session.statusLabel,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
