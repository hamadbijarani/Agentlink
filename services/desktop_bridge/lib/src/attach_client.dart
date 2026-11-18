import 'dart:async';
import 'dart:convert';
import 'dart:io';

final class AttachClient {
  AttachClient({
    required this.endpoint,
    required this.token,
    required this.sessionId,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final Uri endpoint;
  final String token;
  final String sessionId;
  final HttpClient _client;
  int _cursor = 0;
  bool _first = true;
  bool _closed = false;
  final _input = <int>[];
  Timer? _inputTimer;
  StreamSubscription<List<int>>? _stdinSubscription;
  StreamSubscription<ProcessSignal>? _resizeSubscription;
  StreamSubscription<ProcessSignal>? _intSubscription;
  StreamSubscription<ProcessSignal>? _termSubscription;

  Future<void> run() async {
    _writeTitle();
    stdout.writeln('Connecting to AgentLink session $sessionId…');
    final session = await _waitForSession();
    if (session == null) {
      stdout.writeln('Could not connect to the AgentLink bridge.');
      return;
    }
    await _resizeRemote();
    _setRawMode(true);
    stdout.write('\u001B[2J\u001B[H');
    _stdinSubscription = stdin.listen(
      _onInput,
      onDone: _restoreAndExit,
      onError: (Object _) => _restoreAndExit(),
    );
    _resizeSubscription = ProcessSignal.sigwinch.watch().listen((_) {
      unawaited(_resizeRemote());
    });
    _intSubscription = ProcessSignal.sigint.watch().listen((_) {
      _restoreAndExit();
    });
    _termSubscription = ProcessSignal.sigterm.watch().listen((_) {
      _restoreAndExit();
    });
    unawaited(_pollLoop());
  }

  Future<Map<String, dynamic>?> _waitForSession() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    Object? lastError;
    while (!_closed && DateTime.now().isBefore(deadline)) {
      try {
        final json = await _request(
          'GET',
          '/v1/live-sessions/${Uri.encodeComponent(sessionId)}',
        );
        if (json['session'] is Map) {
          return Map<String, dynamic>.from(json['session'] as Map);
        }
      } on Object catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }
    if (lastError != null) stdout.writeln(lastError);
    return null;
  }

  Future<void> _pollLoop() async {
    var failures = 0;
    while (!_closed) {
      try {
        final json = await _request(
          'GET',
          '/v1/live-sessions/${Uri.encodeComponent(sessionId)}/terminal'
          '?cursor=$_cursor&max=262144',
        );
        failures = 0;
        final output = json['output']?.toString() ?? '';
        final cursor = (json['cursor'] as num?)?.toInt() ?? _cursor;
        if (json['truncated'] == true && _first) {
          stdout.write(
            '\u001B[33m[AgentLink] Older output was dropped from the buffer.\u001B[0m\r\n',
          );
        }
        if (output.isNotEmpty) {
          stdout.write(output);
          await stdout.flush();
        }
        _cursor = cursor;
        _first = false;
        final running = json['running'] == true;
        if (!running) {
          final status = json['status']?.toString() ?? 'ended';
          final exitCode = (json['exitCode'] as num?)?.toInt();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          _restoreAndExit(
            message:
                '\r\n\u001B[2m[AgentLink] Session $status'
                '${exitCode == null ? '' : ' (exit $exitCode)'}.\u001B[0m\r\n',
          );
          return;
        }
      } on Object catch (error) {
        failures++;
        if (failures == 1) {
          stdout.write(
            '\r\n\u001B[31m[AgentLink] Lost the bridge connection; retrying…\u001B[0m\r\n',
          );
        }
        if (failures > 60) {
          _restoreAndExit(
            message:
                '\r\n\u001B[31m[AgentLink] $error\u001B[0m\r\n',
          );
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  void _onInput(List<int> data) {
    if (data.length == 1 && data.first == 0x1d) {
      _restoreAndExit(
        message:
            '\r\n\u001B[2m[AgentLink] Detached. The session keeps running.\u001B[0m\r\n',
      );
      return;
    }
    _input.addAll(data);
    _inputTimer ??= Timer(const Duration(milliseconds: 12), _flushInput);
  }

  void _flushInput() {
    _inputTimer = null;
    if (_input.isEmpty || _closed) return;
    final bytes = List<int>.from(_input);
    _input.clear();
    unawaited(
      _request(
        'POST',
        '/v1/live-sessions/${Uri.encodeComponent(sessionId)}/input',
        body: {'dataBase64': base64Encode(bytes)},
      ).catchError((Object _) => <String, dynamic>{}),
    );
  }

  Future<void> _resizeRemote() async {
    try {
      final columns = stdout.terminalColumns;
      final rows = stdout.terminalLines;
      if (columns <= 0 || rows <= 0) return;
      await _request(
        'POST',
        '/v1/live-sessions/${Uri.encodeComponent(sessionId)}/resize',
        body: {'columns': columns, 'rows': rows},
      );
    } on Object {
      // Resizing is best effort on terminals that do not expose a size.
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final uri = endpoint.resolve(path);
    final request = await _client.openUrl(method, uri).timeout(
      const Duration(seconds: 8),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final text = await response.transform(utf8.decoder).join();
    Map<String, dynamic> json = const {};
    if (text.isNotEmpty) {
      final decoded = jsonDecode(text);
      if (decoded is Map) json = Map<String, dynamic>.from(decoded);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        json['error']?.toString() ??
            'Bridge request failed (${response.statusCode})',
        uri: uri,
      );
    }
    return json;
  }

  void _setRawMode(bool enabled) {
    try {
      stdin.echoMode = !enabled;
      stdin.lineMode = !enabled;
    } on Object {
      // Windows may not support these modes. Line input still works.
    }
  }

  void _writeTitle() {
    try {
      stdout.write('\u001B]0;AgentLink · $sessionId\u0007');
    } on Object {
      // Ignore terminals that do not support a title sequence.
    }
  }

  void _restoreAndExit({String? message}) {
    if (_closed) return;
    _closed = true;
    _inputTimer?.cancel();
    _inputTimer = null;
    _stdinSubscription?.cancel();
    _resizeSubscription?.cancel();
    _intSubscription?.cancel();
    _termSubscription?.cancel();
    _setRawMode(false);
    if (message != null) stdout.write(message);
    try {
      _client.close(force: true);
    } on Object {
      // Ignore.
    }
    unawaited(Future<void>.delayed(const Duration(milliseconds: 120)).then((_) {
      exit(0);
    }));
  }
}
