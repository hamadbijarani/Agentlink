import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'models.dart';

final class ManagedRun {
  ManagedRun({
    required this.id,
    required this.provider,
    required this.cwd,
    required this.prompt,
    required this.startedAt,
    required this.process,
  });

  final String id;
  final AgentProvider provider;
  final String cwd;
  final String prompt;
  final DateTime startedAt;
  final Process process;
  final List<String> _output = [];
  DateTime? endedAt;
  int? exitCode;
  String status = 'running';

  void addOutput(String channel, String line) {
    _output.add('[$channel] $line');
    if (_output.length > 1000) _output.removeRange(0, _output.length - 1000);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'provider': provider.id,
    'providerLabel': provider.label,
    'cwd': cwd,
    'prompt': prompt,
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (endedAt != null) 'endedAt': endedAt!.toUtc().toIso8601String(),
    'status': status,
    if (exitCode != null) 'exitCode': exitCode,
    'output': List.unmodifiable(_output),
  };
}

final class AgentCommand {
  const AgentCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

final class RunManager {
  final Map<String, ManagedRun> _runs = {};
  final Random _random = Random.secure();

  List<ManagedRun> get runs =>
      _runs.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  Future<ManagedRun> start({
    required AgentProvider provider,
    required String cwd,
    required String prompt,
  }) async {
    if (prompt.trim().isEmpty) throw ArgumentError('Prompt cannot be empty.');
    final directory = Directory(cwd);
    if (!await directory.exists()) {
      throw ArgumentError('Working directory does not exist.');
    }
    final command = commandFor(provider, prompt.trim());
    final process = await Process.start(
      command.executable,
      command.arguments,
      workingDirectory: directory.absolute.path,
      runInShell: false,
    );
    final id =
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-'
        '${_random.nextInt(1 << 32).toRadixString(36)}';
    final run = ManagedRun(
      id: id,
      provider: provider,
      cwd: directory.absolute.path,
      prompt: prompt.trim(),
      startedAt: DateTime.now().toUtc(),
      process: process,
    );
    _runs[id] = run;
    _listen(run, process.stdout, 'stdout');
    _listen(run, process.stderr, 'stderr');
    unawaited(
      process.exitCode.then((code) {
        run.exitCode = code;
        run.endedAt = DateTime.now().toUtc();
        if (run.status == 'stopping') {
          run.status = 'stopped';
        } else if (run.status == 'running') {
          run.status = code == 0 ? 'completed' : 'failed';
        }
      }),
    );
    return run;
  }

  bool stop(String id) {
    final run = _runs[id];
    if (run == null || run.status != 'running') return false;
    run.status = 'stopping';
    final stopped = run.process.kill(ProcessSignal.sigterm);
    if (!stopped) run.status = 'running';
    return stopped;
  }

  Future<void> stopAll() async {
    for (final run in _runs.values.where((item) => item.status == 'running')) {
      run.status = 'stopping';
      run.process.kill(ProcessSignal.sigterm);
    }
  }

  AgentCommand commandFor(AgentProvider provider, String prompt) =>
      switch (provider) {
        AgentProvider.claude => AgentCommand('claude', [
          '--print',
          '--verbose',
          '--output-format',
          'stream-json',
          prompt,
        ]),
        AgentProvider.opencode => AgentCommand('opencode', [
          'run',
          '--format',
          'json',
          prompt,
        ]),
        AgentProvider.codex => AgentCommand('codex', [
          'exec',
          '--json',
          '--skip-git-repo-check',
          prompt,
        ]),
        AgentProvider.gemini => AgentCommand('gemini', [
          '--prompt',
          prompt,
          '--output-format',
          'stream-json',
        ]),
      };

  void _listen(ManagedRun run, Stream<List<int>> stream, String channel) {
    stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => run.addOutput(channel, line),
          onError: (Object error) =>
              run.addOutput(channel, 'Stream error: $error'),
        );
  }
}
