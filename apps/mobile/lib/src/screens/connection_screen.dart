import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'qr_scanner_screen.dart';

final class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  var _busy = false;

  Future<void> _scan() async {
    final payload = await Navigator.of(context).push<PairingPayload>(
      MaterialPageRoute<PairingPayload>(
        fullscreenDialog: true,
        builder: (_) => const QrScannerScreen(),
      ),
    );
    if (payload != null && mounted) await _pair(payload);
  }

  Future<void> _pair(PairingPayload payload) async {
    setState(() => _busy = true);
    final ok = await widget.controller.pair(payload);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      final message = widget.controller.error ?? 'Pairing failed.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pasteLink() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste pairing link'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'agentlink://pair?bridge=…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Pair'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    final payload = PairingPayload.tryParse(value);
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That does not look like an AgentLink pairing link. '
            'Copy the full link printed by the bridge.',
          ),
        ),
      );
      return;
    }
    await _pair(payload);
  }

  Future<void> _forget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this PC?'),
        content: const Text(
          'The saved device token will be deleted from this phone. '
          'You will need to scan a new QR code to reconnect.',
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
    if (confirmed == true) await widget.controller.forget();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Brand(theme: controller.theme),
                    const SizedBox(height: 32),
                    if (controller.hasProfile)
                      _SavedProfileCard(
                        controller: controller,
                        busy: _busy,
                        onRetry: () => controller.retry(),
                        onForget: _forget,
                      )
                    else
                      _PairCard(
                        busy: _busy || controller.pairing,
                        onScan: _scan,
                        onPaste: _pasteLink,
                      ),
                    if (controller.error != null) ...[
                      const SizedBox(height: 18),
                      _ErrorBanner(message: controller.error!),
                    ],
                    const SizedBox(height: 28),
                    const _HowItWorks(),
                    const SizedBox(height: 20),
                    Text(
                      'Connections are authenticated with a device token stored '
                      'in Android Keystore. One phone per PC.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _Brand extends StatelessWidget {
  const _Brand({required this.theme});

  final ProviderTheme theme;

  @override
  Widget build(BuildContext context) {
    final accent = Color(colorValue(theme.accent));
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: Color(colorValue(theme.surface)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Color(colorValue(theme.border))),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 28,
              ),
            ],
          ),
          child: Icon(Icons.terminal_rounded, size: 38, color: accent),
        ),
        const SizedBox(height: 18),
        Text(
          'AgentLink',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your coding agents, in your pocket',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

final class _PairCard extends StatelessWidget {
  const _PairCard({
    required this.busy,
    required this.onScan,
    required this.onPaste,
  });

  final bool busy;
  final VoidCallback onScan;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pair your desktop',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Run agentlink-bridge on your PC, then scan the QR code it '
              'prints. Pairing works over LAN or the internet relay.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: busy ? null : onScan,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_scanner),
              label: Text(busy ? 'Pairing…' : 'Scan QR code'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : onPaste,
              icon: const Icon(Icons.content_paste_go),
              label: const Text('Paste pairing link'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SavedProfileCard extends StatelessWidget {
  const _SavedProfileCard({
    required this.controller,
    required this.busy,
    required this.onRetry,
    required this.onForget,
  });

  final AppController controller;
  final bool busy;
  final Future<bool> Function() onRetry;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final profile = controller.profile!;
    final theme = Theme.of(context);
    final connecting =
        controller.status == ConnectionStatus.connecting || busy;
    final waiting = controller.status == ConnectionStatus.waiting;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connecting
                      ? Icons.sync
                      : waiting
                      ? Icons.cloud_off_outlined
                      : Icons.computer_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    profile.bridgeName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Line(
              label: 'Status',
              value: connecting
                  ? 'Connecting…'
                  : waiting
                  ? 'Waiting for the PC'
                  : 'Not connected',
            ),
            _Line(label: 'Route', value: profile.connectionLabel),
            if (profile.endpoints.isNotEmpty)
              _Line(label: 'LAN', value: profile.endpoints.join(', ')),
            if (profile.usesRelay)
              _Line(label: 'Relay', value: profile.relayUrl),
            const SizedBox(height: 16),
            if (connecting)
              const LinearProgressIndicator(minHeight: 3)
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => onRetry(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reconnect'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: onForget,
                    child: const Text('Forget'),
                  ),
                ],
              ),
            if (waiting) ...[
              const SizedBox(height: 12),
              Text(
                'The app keeps retrying automatically. Make sure the bridge '
                'is running on the PC.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

final class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

final class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const steps = [
      ('01', 'Start the bridge', 'agentlink-bridge serve'),
      (
        '02',
        'Scan the QR',
        'The one-time secret pairs only this phone.',
      ),
      (
        '03',
        'Pick a folder and agent',
        'Claude Code, OpenCode, Codex, and Gemini.',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HOW IT WORKS',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    step.$1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.$2,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        step.$3,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
