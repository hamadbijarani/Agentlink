import 'dart:async';
import 'dart:io';

import 'models.dart';
import 'util.dart';

final class ProviderRegistry {
  ProviderRegistry({Map<String, String?>? executableOverrides})
    : _executableOverrides = executableOverrides ?? const {};

  final Map<String, String?> _executableOverrides;
  final Map<String, ProviderInfo> _cache = {};
  Future<void>? _probe;

  ProviderInfo get(AgentProvider provider) =>
      _cache[provider.id] ?? _unavailable(provider);

  List<ProviderInfo> get all =>
      AgentProvider.values.map(get).toList(growable: false);

  Future<List<ProviderInfo>> ensureReady() async {
    _probe ??= _runProbe();
    await _probe;
    return all;
  }

  Future<void> refresh() async {
    _cache.clear();
    _probe = null;
    await ensureReady();
  }

  Future<void> _runProbe() async {
    await Future.wait(
      AgentProvider.values.map((provider) async {
        final path = _executableOverrides.containsKey(provider.id)
            ? _executableOverrides[provider.id]
            : findExecutable(provider.command);
        if (path == null || path.isEmpty) {
          _cache[provider.id] = _unavailable(provider);
          return;
        }
        final version = await _version(path);
        _cache[provider.id] = ProviderInfo(
          provider: provider,
          available: true,
          version: version,
          theme: themeForProvider(provider),
          command: path,
          capabilities: {
            'interactive': true,
            'terminal': true,
            'resume': provider.canResume,
            'desktopWindow': true,
          },
        );
      }),
    );
  }

  ProviderInfo _unavailable(AgentProvider provider) => ProviderInfo(
    provider: provider,
    available: false,
    version: null,
    theme: themeForProvider(provider),
    command: provider.command,
    capabilities: {
      'interactive': true,
      'terminal': true,
      'resume': provider.canResume,
      'desktopWindow': true,
    },
  );

  Future<String?> _version(String executable) async {
    try {
      final result = await Process.run(
        executable,
        ['--version'],
        environment: {
          ...Platform.environment,
          'PATH': enrichedPath(),
        },
      ).timeout(const Duration(seconds: 4));
      final text = '${result.stdout}'.trim();
      if (text.isEmpty) return null;
      final first = text.split('\n').first.trim();
      return first.length <= 90 ? first : first.substring(0, 87);
    } on Object {
      return null;
    }
  }
}
