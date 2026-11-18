import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models.dart';
import '../util/format.dart';
import '../widgets/provider_badge.dart';

final class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    super.key,
    required this.controller,
    required this.initial,
  });

  final AppController controller;
  final LiveSession initial;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _inputFocus = FocusNode();
  late int _cursor;
  var _output = '';
  var _status = 'starting';
  int? _exitCode;
  var _running = true;
  var _fetching = false;
  var _disposed = false;
  var _stickToBottom = true;
  String? _transportError;
  var _endedNotified = false;
  String? _lastSizeSent;
  var _showJump = false;
  final _queueController = TextEditingController();
  final List<String> _queue = [];
  var _autoSendQueue = true;
  var _mainOutputOnly = true;
  Timer? _idleTimer;

  String get _sessionId => widget.initial.id;

  LiveSession get _session {
    for (final session in widget.controller.liveSessions) {
      if (session.id == _sessionId) return session;
    }
    return widget.initial;
  }

  @override
  void initState() {
    super.initState();
    _status = widget.initial.status;
    _running = widget.initial.isRunning;
    _exitCode = widget.initial.exitCode;
    _cursor = max(0, widget.initial.outputCursor - 14000);
    _scroll.addListener(_onScroll);
    unawaited(_pollLoop());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _applySize();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _input.dispose();
    _queueController.dispose();
    _focus.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final distance = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    final stick = distance < 90;
    if (stick != _stickToBottom) {
      setState(() {
        _stickToBottom = stick;
        _showJump = !stick;
      });
    }
  }

  Future<void> _pollLoop() async {
    while (!_disposed) {
      final chunk = await _pollOnce();
      if (_disposed) return;
      if (chunk != null && !chunk.running && !chunk.hasMore) {
        break;
      }
      await Future<void>.delayed(
        const Duration(milliseconds: 420),
      );
    }
  }

  Future<TerminalChunk?> _pollOnce() async {
    if (_fetching || _disposed) return null;
    _fetching = true;
    try {
      final chunk = await widget.controller.terminal(
        _sessionId,
        cursor: _cursor,
        max: 65536,
      );
      if (_disposed) return chunk;
      _cursor = chunk.cursor;
      _applyChunk(chunk);
      if (_transportError != null) {
        setState(() => _transportError = null);
      }
      return chunk;
    } on Object catch (error) {
      if (_disposed) return null;
      setState(() => _transportError = '$error');
      return null;
    } finally {
      _fetching = false;
    }
  }

  void _applyChunk(TerminalChunk chunk) {
    final additions = StringBuffer();
    if (chunk.truncated) {
      additions.writeln(
        '[agentlink] Older output was dropped from the desktop buffer.',
      );
    }
    if (chunk.output.isNotEmpty) additions.write(chunk.output);
    final statusChanged =
        chunk.status != _status || chunk.exitCode != _exitCode;
    _status = chunk.status;
    _exitCode = chunk.exitCode;
    _running = chunk.running;
    if (additions.isEmpty && !statusChanged) return;
    setState(() {
      if (additions.isNotEmpty) {
        _output += additions.toString();
        if (_output.length > 220000) {
          _output = _output.substring(_output.length - 180000);
        }
      }
    });
    _scheduleIdleSend();
    if (_stickToBottom) _jumpToBottom(animated: false);
    if (!_running && !_endedNotified) {
      _endedNotified = true;
      _focus.unfocus();
    }
  }

  void _scheduleIdleSend() {
    _idleTimer?.cancel();
    if (!_autoSendQueue || _queue.isEmpty || !_running) return;
    _idleTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_running || _queue.isEmpty || !_autoSendQueue) return;
      unawaited(_sendNext());
    });
  }

  Future<void> _sendNext() async {
    if (_queue.isEmpty || !_running) return;
    final text = _queue.removeAt(0);
    await _send('$text\r');
    if (mounted) setState(() {});
  }

  void _enqueue() {
    final text = _queueController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _queue.add(text);
      _queueController.clear();
    });
  }

  List<String> _suggestions() {
    final lines = _output.split('\n');
    final tail = lines.length > 24 ? lines.sublist(lines.length - 24) : lines;
    final result = <String>[];
    final seen = <String>{};
    for (final raw in tail) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.contains('[Y/n]') || line.contains('[y/N]')) {
        for (final token in ['y', 'n', 'a']) {
          if (seen.add(token)) result.add(token);
        }
      }
      final optionMatch = RegExp(r'^\s*(\d+)[).]\s*(.+)$').firstMatch(line);
      if (optionMatch != null) {
        final token = optionMatch.group(1)!;
        if (seen.add(token)) result.add(token);
      }
      final lower = line.toLowerCase();
      if (lower.contains('allow') ||
          lower.contains('approve') ||
          lower.contains('proceed') ||
          lower.contains('continue')) {
        for (final token in ['y', 'yes', 'continue']) {
          if (seen.add(token)) result.add(token);
        }
      }
    }
    return result.take(8).toList();
  }

  String _displayOutput() {
    if (!_mainOutputOnly) return _output;
    final lines = _output.split('\n');
    final kept = <String>[];
    var blankRun = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (RegExp(r'^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏\-|/\\. ]+$').hasMatch(trimmed) &&
          trimmed.length < 12) {
        continue;
      }
      if (trimmed.isEmpty) {
        blankRun++;
        if (blankRun > 2) continue;
      } else {
        blankRun = 0;
      }
      kept.add(line);
    }
    return kept.join('\n');
  }

  void _jumpToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
      if (_showJump) setState(() => _showJump = false);
    });
  }

  void _applySize() {
    if (!mounted) return;
    final media = MediaQuery.of(context);
    final columns = (media.size.width / 7.4).floor().clamp(20, 200);
    final rows = ((media.size.height - 280) / 16).floor().clamp(5, 80);
    final key = '$columns x $rows';
    if (_lastSizeSent == key) return;
    _lastSizeSent = key;
    unawaited(
      widget.controller
          .resizeSession(_sessionId, columns, rows)
          .catchError((Object _) {}),
    );
  }

  Future<void> _send(String text) async {
    try {
      await widget.controller.sendInput(_sessionId, text: text);
      unawaited(_pollOnce());
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _sendLine() async {
    final text = _input.text;
    _input.clear();
    await _send('$text\r');
    if (mounted) _inputFocus.requestFocus();
  }

  Future<void> _sendBytes(List<int> bytes) async {
    try {
      await widget.controller.sendInput(_sessionId, bytes: bytes);
      unawaited(_pollOnce());
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _attachDesktop() async {
    try {
      final opened = await widget.controller.attachToDesktop(_sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Opened a terminal window on the desktop.'
                : 'The PC could not open a desktop terminal.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _rename() async {
    final text = TextEditingController(text: _session.title);
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
    if (title == null || title.isEmpty || !mounted) return;
    try {
      await widget.controller.renameSession(_sessionId, title);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _restart() async {
    try {
      final restarted = await widget.controller.restartLiveSession(_session);
      if (!mounted) return;
      widget.controller.selectThemeProvider(restarted.provider);
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => TerminalScreen(
            controller: widget.controller,
            initial: restarted,
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close session?'),
        content: const Text(
          'This stops the real agent process on the PC and closes its '
          'desktop terminal. This cannot be undone.',
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
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.stopSession(_sessionId);
      if (!mounted) return;
      _jumpToBottom();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _copyTranscript() async {
    await Clipboard.setData(ClipboardData(text: _output));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transcript copied to the clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _session;
    final providerTheme = widget.controller.providerInfo(session.provider)?.theme;
    final terminalBackground = providerTheme == null
        ? theme.colorScheme.surfaceContainer
        : Color(colorValue(providerTheme.background));
    final terminalForeground = providerTheme == null
        ? theme.colorScheme.onSurface
        : Color(colorValue(providerTheme.foreground));
    _applySize();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                ProviderBadge(
                  provider: session.provider,
                  theme: providerTheme,
                  compact: true,
                ),
                const SizedBox(width: 8),
                Text(
                  _running ? _status : '$_status${_exitCode == null ? '' : ' · exit $_exitCode'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _running
                        ? const Color(0xFF4ADE80)
                        : theme.colorScheme.outline,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_running)
            IconButton(
              tooltip: 'Open on desktop',
              onPressed: _attachDesktop,
              icon: const Icon(Icons.desktop_windows_outlined),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  _rename();
                case 'copy':
                  _copyTranscript();
                case 'stop':
                  _stop();
                case 'reconnect':
                  unawaited(_pollOnce());
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Rename'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy_all_outlined),
                  title: Text('Copy transcript'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'reconnect',
                child: ListTile(
                  leading: Icon(Icons.sync),
                  title: Text('Refresh output'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_running)
                const PopupMenuItem(
                  value: 'stop',
                  child: ListTile(
                    leading: Icon(Icons.stop_circle_outlined),
                    title: Text('Close session'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_transportError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                color: theme.colorScheme.error.withValues(alpha: 0.12),
                child: Text(
                  'Reconnecting… $_transportError',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                decoration: BoxDecoration(
                  color: terminalBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Stack(
                  children: [
                    Scrollbar(
                      controller: _scroll,
                      interactive: true,
                      thumbVisibility: true,
                      thickness: 6,
                      radius: const Radius.circular(3),
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _displayOutput().isEmpty
                              ? (_running
                                    ? 'Connecting to the session…'
                                    : 'No output in the terminal buffer.')
                              : _displayOutput(),
                          style: TextStyle(
                            color: terminalForeground,
                            fontSize: 11.5,
                            height: 1.35,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                    if (_showJump)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: FloatingActionButton.small(
                          heroTag: 'jump',
                          onPressed: () {
                            setState(() => _stickToBottom = true);
                            _jumpToBottom();
                          },
                          child: const Icon(Icons.arrow_downward),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _QuickKeys(
              enabled: _running,
              onKey: (value) => value.startsWith('bytes:')
                  ? _sendBytes(
                      utf8.encode(
                        value.substring(6).replaceAll(r'\x1b', '\x1b'),
                      ),
                    )
                  : _send(value),
            ),
            if (_running && _suggestions().isNotEmpty)
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _suggestions().length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final token = _suggestions()[index];
                    return OutlinedButton(
                      onPressed: () => _send('$token\r'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      child: Text(token),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queueController,
                      enabled: _running,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Queue a prompt…',
                      ),
                      onSubmitted: (_) => _enqueue(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Queue prompt',
                    onPressed: _running ? _enqueue : null,
                    icon: const Icon(Icons.playlist_add, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Send next queued',
                    onPressed: _running && _queue.isNotEmpty
                        ? () => _sendNext()
                        : null,
                    icon: const Icon(Icons.skip_next, size: 20),
                  ),
                  FilterChip(
                    label: const Text('Auto'),
                    selected: _autoSendQueue,
                    onSelected: (value) =>
                        setState(() => _autoSendQueue = value),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('Main only'),
                    selected: _mainOutputOnly,
                    onSelected: (value) =>
                        setState(() => _mainOutputOnly = value),
                  ),
                ],
              ),
            ),
            if (_queue.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < _queue.length; i++)
                      Chip(
                        label: Text(
                          _queue[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: () =>
                            setState(() => _queue.removeAt(i)),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      enabled: _running,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendLine(),
                      decoration: InputDecoration(
                        hintText: _running
                            ? 'Type to the agent…'
                            : 'Session ended',
                        isDense: true,
                        suffixIcon: _running
                            ? IconButton(
                                tooltip: 'Enter',
                                onPressed: _sendLine,
                                icon: const Icon(
                                  Icons.keyboard_return,
                                  size: 20,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _running ? _sendLine : null,
                    icon: const Icon(Icons.send, size: 18),
                  ),
                ],
              ),
            ),
            if (!_running)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _restart,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Restart this session'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Session $_status${_exitCode == null ? '' : ' · exit code $_exitCode'}'
                      ' · started ${elapsedLabel(session.startedAt, endedAt: session.endedAt)} ago',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _QuickKeys extends StatelessWidget {
  const _QuickKeys({required this.enabled, required this.onKey});

  final bool enabled;
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    final keys = <(String, String)>[
      ('Enter', '\r'),
      ('Esc', 'bytes:\\x1b'),
      ('Tab', '\t'),
      ('↑', 'bytes:\\x1b[A'),
      ('↓', 'bytes:\\x1b[B'),
      ('←', 'bytes:\\x1b[D'),
      ('→', 'bytes:\\x1b[C'),
      ('^C', 'bytes:\\x03'),
      ('^D', 'bytes:\\x04'),
      ('^L', 'bytes:\\x0c'),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: keys.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final key = keys[index];
          return OutlinedButton(
            onPressed: enabled ? () => onKey(key.$2) : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 30),
              textStyle: const TextStyle(fontSize: 11),
            ),
            child: Text(key.$1),
          );
        },
      ),
    );
  }
}
