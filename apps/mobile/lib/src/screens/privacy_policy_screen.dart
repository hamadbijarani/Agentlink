import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AgentLink Privacy Policy',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Last updated: November 2026',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            _section(theme, 'Data Collection', [
              'AgentLink does not collect, store, or transmit your code, prompts, '
              'or AI responses. All traffic flows directly between your phone and '
              'your PC or self-hosted relay.',
              'The only data stored on your device is the pairing profile (bridge '
              'ID, device token, endpoints) in Android Keystore.',
            ]),
            _section(theme, 'Crash Reporting', [
              'Optional crash reporting collects only device model, OS version, '
              'and stack traces. No personal data or session content is included.',
              'You can disable crash reporting in Settings.',
            ]),
            _section(theme, 'Network', [
              'When using a relay, requests are forwarded over an encrypted '
              'WebSocket connection. The relay does not inspect or store request '
              'bodies.',
              'When using direct HTTPS, traffic is encrypted end-to-end between '
              'your phone and PC.',
            ]),
            _section(theme, 'Third-Party Services', [
              'Tailscale and Cloudflare (if used) have their own privacy policies. '
              'AgentLink does not control these services.',
            ]),
            _section(theme, 'Data Deletion', [
              'Unpairing the phone (Settings \u2192 Forget) removes the device token '
              'from both the phone and the PC.',
              'Uninstalling the app removes all local data.',
            ]),
            _section(theme, 'Contact', [
              'For questions about this policy, contact the developer through the '
              'GitHub repository.',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String title, List<String> paragraphs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final p in paragraphs) ...[
            Text(
              p,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
