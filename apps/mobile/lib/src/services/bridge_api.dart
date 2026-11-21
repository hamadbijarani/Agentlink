import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models.dart';

final class BridgeException implements Exception {
  const BridgeException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  bool get isOffline =>
      statusCode == 503 || message.toLowerCase().contains('offline');

  @override
  String toString() => message;
}

final class BridgeConnection {
  const BridgeConnection({
    required this.online,
    this.info,
    this.message,
  });

  final bool online;
  final BridgeInfo? info;
  final String? message;
}

abstract interface class BridgeTransport {
  bool get supportsEvents;
  Stream<Map<String, dynamic>> get events;

  Future<void> connect();

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
  });

  Future<void> close();
}

Future<Map<String, dynamic>> _readJson(HttpClientResponse response) async {
  final text = await response.transform(utf8.decoder).join();
  if (text.trim().isEmpty) return const {};
  final decoded = jsonDecode(text);
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return {'value': decoded};
}

BridgeException _exceptionFor(int status, Map<String, dynamic> json) {
  final raw = json['error']?.toString() ?? 'Bridge request failed ($status)';
  return BridgeException(raw, statusCode: status);
}

final class DirectTransport implements BridgeTransport {
  DirectTransport({
    required List<String> endpoints,
    required this.token,
    this.deviceName = 'AgentLink Android',
  }) : _endpoints = endpoints
           .map(_normalizeEndpoint)
           .where((item) => item.isNotEmpty)
           .toSet()
           .toList();

  final String token;
  final String deviceName;
  final List<String> _endpoints;
  final HttpClient _client = HttpClient();
  int _active = 0;

  @override
  bool get supportsEvents => false;

  @override
  Stream<Map<String, dynamic>> get events =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Future<void> connect() async {
    if (_endpoints.isEmpty) {
      throw const BridgeException(
        'This pairing has no LAN address. Configure a relay on the PC or '
        'pair while the phone and PC are on the same network.',
      );
    }
    Object? lastError;
    for (var index = 0; index < _endpoints.length; index++) {
      try {
        await _requestAt(
          index,
          'GET',
          '/v1/health',
          authenticated: false,
          timeout: const Duration(seconds: 5),
        );
        _active = index;
        return;
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw BridgeException(
      'Cannot reach the desktop bridge. Make sure the PC is online and the '
      'phone can reach it.${lastError == null ? '' : ' ($lastError)'}',
    );
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    Object? lastError;
    for (var offset = 0; offset < _endpoints.length; offset++) {
      final index = (_active + offset) % _endpoints.length;
      try {
        final result = await _requestAt(
          index,
          method,
          path,
          query: query,
          body: body,
          authenticated: authenticated,
        );
        _active = index;
        return result;
      } on BridgeException {
        rethrow;
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw BridgeException(
      'Lost the connection to the desktop bridge'
      '${lastError == null ? '.' : ': $lastError'}',
    );
  }

  Future<Map<String, dynamic>> _requestAt(
    int index,
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final base = Uri.tryParse(_endpoints[index]);
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw BridgeException('Invalid desktop endpoint: ${_endpoints[index]}');
    }
    var uri = base.resolve(path);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    final request = await _client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 8));
    if (authenticated && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(timeout);
    final json = await _readJson(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFor(response.statusCode, json);
    }
    return json;
  }

  @override
  Future<void> close() async {
    _client.close(force: true);
  }

  static String _normalizeEndpoint(String value) {
    var endpoint = value.trim();
    while (endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }
    if (endpoint.isEmpty) return '';
    if (!endpoint.contains('://')) endpoint = 'http://$endpoint';
    return endpoint;
  }
}

final class RelayTransport implements BridgeTransport {
  RelayTransport({
    required this.relayUrl,
    required this.relayToken,
    required this.bridgeId,
    required this.deviceToken,
  });

  final String relayUrl;
  final String relayToken;
  final String bridgeId;
  final String deviceToken;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final _random = Random.secure();

  WebSocket? _socket;
  Timer? _retry;
  Completer<void>? _ready;
  bool _stopped = false;
  int _attempt = 0;
  int _counter = 0;
  bool _online = false;

  bool get online => _online;

  @override
  bool get supportsEvents => true;

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Future<void> connect() async {
    _stopped = false;
    _attempt = 0;
    await _open();
  }

  Future<void> _open() async {
    if (_stopped) return;
    final ready = Completer<void>();
    _ready = ready;
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(
        _connectionUri().toString(),
        headers: const {'User-Agent': 'AgentLink-Android/1.0'},
      ).timeout(const Duration(seconds: 15));
      if (_stopped) {
        await socket.close(1000, 'Closed');
        return;
      }
      socket.pingInterval = const Duration(seconds: 20);
      _socket = socket;
      socket.listen(
        _onMessage,
        onDone: () => _onClosed(socket!, 'The relay closed the connection.'),
        onError: (Object error) => _onClosed(socket!, 'Relay error: $error'),
        cancelOnError: true,
      );
      await ready.future.timeout(const Duration(seconds: 15));
      _attempt = 0;
    } on Object {
      if (!ready.isCompleted) {
        ready.completeError(
          const BridgeException('Could not connect to the relay.'),
        );
      }
      if (_socket == socket) _socket = null;
      try {
        await socket?.close(1000, 'Connection failed');
      } on Object {
        // Ignore.
      }
      rethrow;
    }
  }

  Uri _connectionUri() {
    final base = Uri.tryParse(relayUrl.trim());
    if (base == null || base.host.isEmpty) {
      throw const BridgeException('The relay URL is invalid.');
    }
    final scheme = switch (base.scheme) {
      'wss' || 'https' => 'wss',
      'ws' || 'http' => 'ws',
      _ => 'wss',
    };
    var path = base.path;
    if (path.isEmpty || path == '/') path = '/v1/connect';
    return base.replace(
      scheme: scheme,
      path: path,
      queryParameters: {
        ...base.queryParameters,
        'role': 'client',
        'bridgeId': bridgeId,
        if (relayToken.isNotEmpty) 'token': relayToken,
      },
    );
  }

  void _onMessage(Object? data) {
    if (data is! String) return;
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      message = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return;
    }
    switch (message['t']) {
      case 'ready':
        _online = message['online'] == true;
        final ready = _ready;
        if (ready != null && !ready.isCompleted) ready.complete();
        if (message['role'] == 'client') {
          _events.add({
            'event': 'bridge',
            'online': _online,
          });
        }
        break;
      case 'bridge':
        _online = message['online'] == true;
        _events.add({'event': 'bridge', 'online': _online});
        break;
      case 'event':
        _events.add({
          'event': message['event']?.toString() ?? 'event',
          'body': message['body'],
        });
        break;
      case 'res':
        final id = message['id']?.toString() ?? '';
        final completer = _pending.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(message);
        }
        break;
      case 'ping':
        _send({'t': 'pong'});
        break;
    }
  }

  void _onClosed(WebSocket socket, String reason) {
    if (_socket != socket) return;
    _socket = null;
    _online = false;
    _failPending(reason);
    if (_stopped) return;
    _events.add({'event': 'bridge', 'online': false});
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    _retry?.cancel();
    _attempt++;
    final seconds = switch (_attempt) {
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 15,
      _ => 30,
    };
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      if (_stopped) return;
      unawaited(_reconnect());
    });
  }

  Future<void> _reconnect() async {
    try {
      await _open();
    } on Object {
      _scheduleReconnect();
    }
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw const BridgeException(
        'The relay connection is not ready. Retrying automatically…',
      );
    }
    final id = '${_counter++}-${_random.nextInt(1 << 32)}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send({
      't': 'req',
      'id': id,
      'method': method,
      'path': path,
      'query': query ?? const <String, String>{},
      if (authenticated && deviceToken.isNotEmpty)
        'headers': {'authorization': 'Bearer $deviceToken'},
      'body': body,
    });
    final Map<String, dynamic> response;
    try {
      response = await completer.future.timeout(
        const Duration(seconds: 25),
      );
    } on TimeoutException {
      _pending.remove(id);
      throw const BridgeException(
        'The desktop did not answer in time. It may be busy or offline.',
      );
    } finally {
      _pending.remove(id);
    }
    final status = (response['status'] as num?)?.toInt() ?? 500;
    final rawBody = response['body'];
    final json = rawBody is Map
        ? Map<String, dynamic>.from(rawBody)
        : <String, dynamic>{'value': rawBody};
    if (status < 200 || status >= 300) {
      throw _exceptionFor(status, json);
    }
    return json;
  }

  void _send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    try {
      socket.add(jsonEncode(message));
    } on Object {
      // The close handler takes care of reconnecting.
    }
  }

  void _failPending(String reason) {
    final pending = List<Completer<Map<String, dynamic>>>.from(
      _pending.values,
    );
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(BridgeException(reason));
      }
    }
  }

  @override
  Future<void> close() async {
    _stopped = true;
    _retry?.cancel();
    _retry = null;
    _failPending('Connection closed.');
    await _socket?.close(1000, 'App closed the connection');
    _socket = null;
    await _events.close();
  }
}

final class BridgeApi {
  BridgeApi(this.profile);

  final ConnectionProfile profile;
  BridgeTransport? _transport;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  bool _closed = false;

  Stream<Map<String, dynamic>> get events =>
      _transport?.events ?? const Stream<Map<String, dynamic>>.empty();

  bool get supportsEvents => _transport?.supportsEvents ?? false;

  Future<BridgeConnection> connect() async {
    Object? relayError;
    if (profile.usesRelay) {
      final relay = RelayTransport(
        relayUrl: profile.relayUrl,
        relayToken: profile.relayToken,
        bridgeId: profile.bridgeId,
        deviceToken: profile.deviceToken,
      );
      try {
        await relay.connect();
        _transport = relay;
        try {
          final info = await _fetchInfo(relay);
          return BridgeConnection(online: true, info: info);
        } on BridgeException catch (error) {
          if (error.statusCode == 503 || error.statusCode == null) {
            return BridgeConnection(
              online: false,
              message: error.message,
            );
          }
          rethrow;
        }
      } on BridgeException catch (error) {
        relayError = error;
        await relay.close();
        if (_transport == relay) _transport = null;
      } on Object catch (error) {
        relayError = error;
        await relay.close();
        if (_transport == relay) _transport = null;
      }
    }

    final direct = DirectTransport(
      endpoints: profile.endpoints,
      token: profile.deviceToken,
    );
    try {
      await direct.connect();
      _transport = direct;
      final info = await _fetchInfo(direct);
      return BridgeConnection(online: true, info: info);
    } on Object catch (error) {
      await direct.close();
      if (_transport == direct) _transport = null;
      if (relayError != null) {
        throw BridgeException(
          'Cannot reach the PC through the relay or LAN. '
          '${_short(error)}',
        );
      }
      rethrow;
    }
  }

  Future<BridgeInfo> _fetchInfo(BridgeTransport transport) async {
    final json = await transport.request('GET', '/v1/info');
    return BridgeInfo.fromJson(json);
  }

  Future<BridgeConnection> probe() async {
    final transport = _transport;
    if (transport == null) {
      throw const BridgeException('The bridge connection is not ready.');
    }
    final info = await _fetchInfo(transport);
    return BridgeConnection(online: true, info: info);
  }

  void listenEvents(void Function(Map<String, dynamic> event) handler) {
    _eventSubscription?.cancel();
    _eventSubscription = events.listen(handler);
  }

  Future<List<ProviderInfo>> providers() async {
    final json = await _request('GET', '/v1/providers');
    return (json['providers'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ProviderInfo.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<LiveSession>> liveSessions() async {
    final json = await _request('GET', '/v1/live-sessions');
    return (json['sessions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => LiveSession.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<LiveSession> startSession({
    required AgentProvider provider,
    required String cwd,
    String prompt = '',
    String title = '',
    String resumeSessionId = '',
    String model = '',
    List<String> extraArgs = const [],
    required bool openOnDesktop,
  }) async {
    final json = await _request(
      'POST',
      '/v1/live-sessions',
      body: {
        'provider': provider.id,
        'cwd': cwd,
        'prompt': prompt,
        'title': title,
        'resumeSessionId': resumeSessionId,
        'model': model,
        'extraArgs': extraArgs,
        'openOnDesktop': openOnDesktop,
      },
    );
    return LiveSession.fromJson(Map<String, dynamic>.from(json['session'] as Map));
  }

  Future<void> stopSession(String id) async {
    await _request('DELETE', '/v1/live-sessions/${Uri.encodeComponent(id)}');
  }

  Future<LiveSession> renameSession(String id, String title) async {
    final json = await _request(
      'PATCH',
      '/v1/live-sessions/${Uri.encodeComponent(id)}',
      body: {'title': title},
    );
    return LiveSession.fromJson(Map<String, dynamic>.from(json['session'] as Map));
  }

  Future<TerminalChunk> terminal(
    String id, {
    required int cursor,
    bool plain = true,
    int max = 32768,
  }) async {
    final json = await _request(
      'GET',
      '/v1/live-sessions/${Uri.encodeComponent(id)}/terminal',
      query: {
        'cursor': '$cursor',
        'plain': plain ? '1' : '0',
        'max': '$max',
      },
    );
    return TerminalChunk.fromJson(json);
  }

  Future<void> sendInput(String id, {String? text, List<int>? bytes}) async {
    await _request(
      'POST',
      '/v1/live-sessions/${Uri.encodeComponent(id)}/input',
      body: bytes != null
          ? {'dataBase64': base64Encode(bytes)}
          : {'data': text ?? ''},
    );
  }

  Future<void> resizeSession(String id, int columns, int rows) async {
    await _request(
      'POST',
      '/v1/live-sessions/${Uri.encodeComponent(id)}/resize',
      body: {'columns': columns, 'rows': rows},
    );
  }

  Future<bool> attachToDesktop(String id) async {
    final json = await _request(
      'POST',
      '/v1/live-sessions/${Uri.encodeComponent(id)}/attach',
    );
    return json['opened'] == true;
  }

  Future<List<FsRoot>> fsRoots() async {
    final json = await _request('GET', '/v1/fs/roots');
    return (json['roots'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => FsRoot.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<FsListing> fsList(String path, {bool showHidden = false}) async {
    final json = await _request(
      'GET',
      '/v1/fs/list',
      query: {'path': path, 'showHidden': showHidden ? '1' : '0'},
    );
    return FsListing.fromJson(json);
  }

  Future<FsEntry> fsMkdir(String path) async {
    final json = await _request(
      'POST',
      '/v1/fs/mkdir',
      body: {'path': path},
    );
    return FsEntry.fromJson(Map<String, dynamic>.from(json['entry'] as Map));
  }

  Future<Map<String, dynamic>> fsWrite(String path, List<int> bytes) async {
    return _request(
      'POST',
      '/v1/fs/write',
      body: {'path': path, 'dataBase64': base64Encode(bytes)},
    );
  }

  Future<List<AgentSession>> history({int limit = 200, String query = ''}) async {
    final json = await _request(
      'GET',
      '/v1/sessions',
      query: {
        'limit': '$limit',
        if (query.trim().isNotEmpty) 'query': query.trim(),
      },
    );
    return (json['sessions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => AgentSession.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<SessionDetail> historyDetail(AgentSession session) async {
    final json = await _request(
      'GET',
      '/v1/session',
      query: {'provider': session.provider.id, 'ref': session.ref},
    );
    return SessionDetail.fromJson(json);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final transport = _transport;
    if (transport == null) {
      throw const BridgeException('Not connected to the desktop bridge.');
    }
    return transport.request(method, path, query: query, body: body);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _transport?.close();
    _transport = null;
  }

  static Future<PairingResult> claim(
    PairingPayload payload, {
    required String deviceName,
    String platform = 'android',
  }) async {
    Object? lastError;
    BridgeException? meaningful;
    for (final endpoint in payload.endpoints) {
      try {
        final result = await _claimDirect(endpoint, payload, deviceName, platform);
        return result;
      } on BridgeException catch (error) {
        lastError = error;
        if (error.statusCode != null &&
            error.statusCode! >= 400 &&
            error.statusCode! < 500 &&
            error.statusCode != 426) {
          meaningful = error;
          break;
        }
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (meaningful != null) throw meaningful;

    if (payload.relayUrl.isNotEmpty) {
      final relay = RelayTransport(
        relayUrl: payload.relayUrl,
        relayToken: payload.relayToken,
        bridgeId: payload.bridgeId,
        deviceToken: '',
      );
      try {
        await relay.connect();
        final json = await relay.request(
          'POST',
          '/v1/pair/claim',
          authenticated: false,
          body: {
            'secret': payload.secret,
            'deviceName': deviceName,
            'platform': platform,
          },
        );
        return _pairingResult(json, payload);
      } on BridgeException catch (error) {
        meaningful = error;
        lastError = error;
      } on Object catch (error) {
        lastError = error;
      } finally {
        await relay.close();
      }
    }
    if (meaningful != null) throw meaningful;
    final detail = lastError == null ? '' : ' $lastError';
    throw BridgeException(
      'Could not reach the PC to complete pairing.$detail '
      'Start the bridge on the PC, keep the QR screen open, and retry.',
    );
  }

  static Future<PairingResult> _claimDirect(
    String endpoint,
    PairingPayload payload,
    String deviceName,
    String platform,
  ) async {
    var base = endpoint.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.contains('://')) base = 'http://$base';
    final uri = Uri.tryParse(base);
    if (uri == null || uri.host.isEmpty) {
      throw const BridgeException('The QR code contains an invalid LAN URL.');
    }
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(uri.resolve('/v1/pair/claim'))
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'secret': payload.secret,
          'deviceName': deviceName,
          'platform': platform,
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final json = await _readJson(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _exceptionFor(response.statusCode, json);
      }
      return _pairingResult(json, payload);
    } finally {
      client.close(force: true);
    }
  }

  static PairingResult _pairingResult(
    Map<String, dynamic> json,
    PairingPayload payload,
  ) {
    final token = json['deviceToken']?.toString() ?? '';
    if (token.isEmpty) {
      throw const BridgeException(
        'The PC did not return a device token. Restart the bridge and pair again.',
      );
    }
    final bridge = json['bridge'] is Map
        ? Map<String, dynamic>.from(json['bridge'] as Map)
        : const <String, dynamic>{};
    final endpoints = (bridge['endpoints'] as List? ?? payload.endpoints)
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final profile = ConnectionProfile(
      bridgeId: bridge['id']?.toString() ?? payload.bridgeId,
      bridgeName: bridge['name']?.toString() ?? payload.name,
      desktopName: bridge['name']?.toString() ?? payload.name,
      deviceToken: token,
      relayUrl: bridge['relay']?.toString() ?? payload.relayUrl,
      relayToken: bridge['relayToken']?.toString() ?? payload.relayToken,
      endpoints: endpoints,
      pairedAt: DateTime.now(),
      deviceName: 'Android device',
    );
    final providers = (json['providers'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ProviderInfo.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return PairingResult(profile: profile, providers: providers);
  }

  static String _short(Object error) {
    if (error is BridgeException) return error.message;
    return '$error';
  }
}
