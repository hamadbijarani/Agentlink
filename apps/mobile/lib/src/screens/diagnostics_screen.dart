import 'package:flutter/material.dart';

import '../services/diagnostics_service.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = DiagnosticsService.instance.entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: () {
              DiagnosticsService.instance.clear();
              setState(() {});
            },
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Copy',
            onPressed: () {
              // Copy to clipboard
            },
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Text(
                'No diagnostic entries yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final e = entries[index];
                final color = switch (e.level) {
                  'ERROR' => theme.colorScheme.error,
                  'WARN' => Colors.orange,
                  'DEBUG' => theme.colorScheme.outline,
                  _ => theme.colorScheme.onSurface,
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    e.toString(),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: color,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
