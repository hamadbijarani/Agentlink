import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';

final class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  Future<void> _reconnect(BuildContext context) async {
    final ok = await controller.retry();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Connected to the PC.' : 'Could not connect yet; retrying.',
        ),
      ),
    );
  }

  Future<void> _forget(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this PC?'),
        content: const Text(
          'This deletes the saved device token from the phone. To pair again '
          'you need a new QR code from the PC.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.forget();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = controller.profile;
    final info = controller.info;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        _SectionCard(
          title: 'DESKTOP',
          icon: Icons.computer_outlined,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: controller.isConnected
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFFACC15),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    profile?.bridgeName ?? 'Not paired',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  controller.isConnected ? 'ONLINE' : 'WAITING',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: controller.isConnected
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFFACC15),
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Row(label: 'Route', value: profile?.connectionLabel ?? '—'),
            if (profile != null)
              _Row(label: 'Bridge ID', value: profile.bridgeId),
            if (info != null) ...[
              _Row(label: 'Version', value: info.version),
              _Row(
                label: 'Host',
                value: [
                  if (info.hostname.isNotEmpty) info.hostname,
                  if (info.platform.isNotEmpty) info.platform,
                ].join(' · '),
              ),
              if (info.httpPort != 0)
                _Row(
                  label: 'HTTP',
                  value: '${info.httpHost}:${info.httpPort}',
                ),
            ],
            if (profile?.endpoints.isNotEmpty ?? false)
              _Row(label: 'LAN', value: profile!.endpoints.join(', ')),
            if (profile?.usesRelay ?? false)
              _Row(label: 'Relay', value: profile!.relayUrl),
            if (info?.device != null)
              _Row(
                label: 'Paired',
                value:
                    '${info!.device!.name} · '
                    '${info.device!.platform} · '
                    '${info.device!.pairedAt == null ? '' : info.device!.pairedAt!.toLocal().toString().split('.').first}',
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reconnect(context),
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Reconnect'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _forget(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Forget'),
                ),
              ],
            ),
          ],
        ),
        if (info != null && info.relay.configured) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'INTERNET RELAY',
            icon: Icons.public,
            children: [
              _Row(
                label: 'State',
                value: info.relay.state.toUpperCase(),
                valueColor: info.relay.connected
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFFACC15),
              ),
              _Row(label: 'URL', value: info.relay.url),
              if (info.relay.error != null)
                _Row(
                  label: 'Last error',
                  value: info.relay.error!,
                  valueColor: theme.colorScheme.error,
                ),
              const SizedBox(height: 4),
              Text(
                'The relay only forwards authenticated requests. Agent '
                'credentials and session files stay on the PC.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _SectionCard(
          title: 'PROVIDERS',
          icon: Icons.memory,
          trailing: IconButton(
            tooltip: 'Refresh providers',
            onPressed: controller.providersLoading
                ? null
                : controller.refreshProviders,
            icon: controller.providersLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
          ),
          children: [
            if (controller.providers.isEmpty)
              Text(
                'Provider information is not available yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else
              for (final provider in controller.providers) ...[
                _ProviderRow(provider: provider),
                if (provider != controller.providers.last)
                  Divider(color: theme.colorScheme.outlineVariant, height: 18),
              ],
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'SECURITY',
          icon: Icons.shield_outlined,
          children: [
            Text(
              '• This phone holds one device token in Android Keystore.\n'
              '• The PC accepts only one paired phone at a time.\n'
              '• Pairing uses a one-time secret from the QR code.\n'
              '• Closing a session from the app stops the real CLI process.\n'
              '• To pair a different phone, run "agentlink-bridge reset" on '
              'the PC.',
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.55,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'APPEARANCE',
          icon: Icons.palette_outlined,
          children: [
            Text(
              'The palette follows the active agent provider. Themes are '
              'served by the desktop CLI bridge, so they stay in sync with '
              'the PC.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    controller.theme.name,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                _Swatches(theme: controller.theme),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'AgentLink · terminal-native remote',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }
}

final class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.3,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

final class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.provider});

  final ProviderInfo provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Color(colorValue(provider.theme.accent));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Icon(Icons.terminal, size: 15, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      provider.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    provider.available ? 'READY' : 'NOT INSTALLED',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: provider.available
                          ? const Color(0xFF4ADE80)
                          : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                provider.available
                    ? '${provider.version ?? 'installed'} · ${provider.theme.name}'
                    : 'Install ${provider.command} on the PC to use it',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _Swatches extends StatelessWidget {
  const _Swatches({required this.theme});

  final ProviderTheme theme;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final color in [
        theme.background,
        theme.surface,
        theme.foreground,
        theme.accent,
        theme.border,
      ])
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: Color(colorValue(color)),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
    ],
  );
}
