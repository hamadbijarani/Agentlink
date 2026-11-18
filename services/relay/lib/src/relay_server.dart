import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'relay_store.dart';

const relayVersion = '1.0.0';
const _maxMessageBytes = 8 * 1024 * 1024;
const _maxClientRequests = 64;

final class RelayServer {
  RelayServer({
    required this.host,
    required this.port,
    this.token = '',
    this.name = 'AgentLink relay',
    RelayStore? store,
    SecurityContext? securityContext,
  }) : store = store ?? RelayStore(),
       _securityContext = securityContext;

  final InternetAddress host;
  final int port;
  final String token;
  final String name;
  final RelayStore store;
  final SecurityContext? _securityContext;
  final Map<String, _BridgePeer> _bridges = {};
  final Map<String, Set<_ClientPeer>> _clients = {};
  final DateTime _startedAt = DateTime.now();
  HttpServer? _server;

  int? get boundPort => _server?.port;
  int get bridgeCount => _bridges.length;
  int get clientCount =>
      _clients.values.fold(0, (total, items) => total + items.length);

  Future<void> start() async {
    await store.load();
    final context = _securityContext;
    _server = context == null
        ? await HttpServer.bind(host, port, shared: false)
        : await HttpServer.bindSecure(host, port, context, shared: false);
    _server!.listen(_handle, onError: _logError);
    _log(
      'relay listening on ${context == null ? 'ws' : 'wss'}://'
      '${host.address}:${_server!.port}',
    );
  }

  Future<void> close() async {
    final bridges = _bridges.values.toList();
    final clients = _clients.values.expand((items) => items).toList();
    _bridges.clear();
    _clients.clear();
    for (final bridge in bridges) {
      await bridge.socket.close(1001, 'Relay shutting down');
    }
    for (final client in clients) {
      await client.socket.close(1001, 'Relay shutting down');
    }
    await _server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/v1/health') {
        _json(request.response, HttpStatus.ok, {
          'status': 'ok',
          'name': name,
          'version': relayVersion,
          'bridges': _bridges.length,
          'clients': clientCount,
          'uptimeSeconds': DateTime.now().difference(_startedAt).inSeconds,
        });
        return;
      }
      if (request.uri.path != '/v1/connect') {
        _json(request.response, HttpStatus.notFound, {
          'error': 'Not found',
        });
        return;
      }
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        _json(request.response, HttpStatus.badRequest, {
          'error': 'Expected a WebSocket upgrade',
        });
        return;
      }
      final query = request.uri.queryParameters;
      if (!_relayTokenValid(query['token'])) {
        _json(request.response, HttpStatus.unauthorized, {
          'error': 'Invalid relay token',
        });
        return;
      }
      final role = query['role'] ?? '';
      final bridgeId = query['bridgeId'] ?? '';
      if (bridgeId.isEmpty ||
          !RegExp(r'^[A-Za-z0-9_-]{4,80}$').hasMatch(bridgeId)) {
        _json(request.response, HttpStatus.badRequest, {
          'error': 'bridgeId is required',
        });
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socket.pingInterval = const Duration(seconds: 20);
      if (role == 'bridge') {
        await _acceptBridge(socket, bridgeId, query);
      } else if (role == 'client') {
        await _acceptClient(socket, bridgeId);
      } else {
        await socket.close(4000, 'Unknown role');
      }
    } on Object catch (error, stack) {
      _log('connection error: $error\n$stack');
      try {
        _json(request.response, HttpStatus.internalServerError, {
          'error': 'Relay error',
        });
      } on Object {
        // The response may already be upgraded.
      }
    }
  }

  bool _relayTokenValid(String? value) {
    if (token.isEmpty) return true;
    return _constantTimeEquals(token, value ?? '');
  }

  Future<void> _acceptBridge(
    WebSocket socket,
    String bridgeId,
    Map<String, String> query,
  ) async {
    final secret = query['secret'] ?? '';
    if (secret.length < 16) {
      await socket.close(4003, 'Invalid bridge secret');
      return;
    }
    final record = await store.authorize(
      bridgeId: bridgeId,
      secret: secret,
      name: query['name'] ?? 'AgentLink bridge',
      allowRegister: true,
    );
    if (record == null) {
      await socket.close(4003, 'Bridge authentication failed');
      return;
    }
    final existing = _bridges[bridgeId];
    if (existing != null) {
      await existing.socket.close(4001, 'Replaced by a newer bridge connection');
    }
    final peer = _BridgePeer(
      id: bridgeId,
      name: record.name,
      socket: socket,
    );
    _bridges[bridgeId] = peer;
    _log('bridge connected: ${record.name} ($bridgeId)');
    _send(socket, {
      't': 'ready',
      'role': 'bridge',
      'bridgeId': bridgeId,
      'name': record.name,
      'version': relayVersion,
    });
    _broadcastBridgeStatus(bridgeId, true);

    socket.listen(
      (data) => _onBridgeMessage(peer, data),
      onDone: () => _removeBridge(peer),
      onError: (Object error) {
        _log('bridge socket error ($bridgeId): $error');
        _removeBridge(peer);
      },
      cancelOnError: true,
    );
  }

  Future<void> _acceptClient(WebSocket socket, String bridgeId) async {
    final client = _ClientPeer(
      id: _randomId(),
      bridgeId: bridgeId,
      socket: socket,
    );
    _clients.putIfAbsent(bridgeId, () => <_ClientPeer>{}).add(client);
    _log('phone connected: ${client.id} -> $bridgeId');
    final online = _bridges.containsKey(bridgeId);
    _send(socket, {
      't': 'ready',
      'role': 'client',
      'clientId': client.id,
      'bridgeId': bridgeId,
      'online': online,
      'version': relayVersion,
    });
    _send(socket, {'t': 'bridge', 'online': online});

    socket.listen(
      (data) => _onClientMessage(client, data),
      onDone: () => _removeClient(client),
      onError: (Object error) {
        _log('phone socket error (${client.id}): $error');
        _removeClient(client);
      },
      cancelOnError: true,
    );
  }

  void _onBridgeMessage(_BridgePeer peer, Object? data) {
    if (data is! String || data.length > _maxMessageBytes) return;
    final message = _decode(data);
    if (message == null) return;
    switch (message['t']) {
      case 'res':
        final to = message['to']?.toString() ?? '';
        final client = _findClient(peer.id, to);
        if (client != null) {
          client.inFlight.remove(message['id']?.toString());
          _send(client.socket, {
            't': 'res',
            'id': message['id'],
            'status': message['status'],
            'body': message['body'],
            if (message['headers'] is Map) 'headers': message['headers'],
          });
        }
        break;
      case 'event':
        for (final client in _clients[peer.id] ?? const <_ClientPeer>{}) {
          _send(client.socket, {
            't': 'event',
            'event': message['event'],
            'body': message['body'],
          });
        }
        break;
      case 'ping':
        _send(peer.socket, {'t': 'pong'});
        break;
    }
  }

  void _onClientMessage(_ClientPeer client, Object? data) {
    if (data is! String || data.length > _maxMessageBytes) return;
    final message = _decode(data);
    if (message == null) return;
    switch (message['t']) {
      case 'req':
        _forwardRequest(client, message);
        break;
      case 'ping':
        _send(client.socket, {'t': 'pong'});
        break;
    }
  }

  void _forwardRequest(_ClientPeer client, Map<String, dynamic> message) {
    final id = message['id']?.toString() ?? '';
    final method = message['method']?.toString().toUpperCase() ?? '';
    final path = message['path']?.toString() ?? '';
    if (id.isEmpty || id.length > 100) return;
    if (!const {'GET', 'POST', 'PATCH', 'DELETE'}.contains(method)) {
      _sendResponse(client, id, HttpStatus.badRequest, {
        'error': 'Unsupported method',
      });
      return;
    }
    if (!path.startsWith('/v1/')) {
      _sendResponse(client, id, HttpStatus.badRequest, {
        'error': 'Unsupported path',
      });
      return;
    }
    if (client.inFlight.length >= _maxClientRequests) {
      _sendResponse(client, id, HttpStatus.tooManyRequests, {
        'error': 'Too many requests in flight',
      });
      return;
    }
    final bridge = _bridges[client.bridgeId];
    if (bridge == null) {
      _sendResponse(client, id, HttpStatus.serviceUnavailable, {
        'error': 'The desktop bridge is offline. Start it on your PC and retry.',
      });
      return;
    }
    client.inFlight.add(id);
    _send(bridge.socket, {
      't': 'req',
      'id': id,
      'client': client.id,
      'method': method,
      'path': path,
      'query': message['query'] is Map ? message['query'] : const {},
      'headers': message['headers'] is Map ? message['headers'] : const {},
      'body': message['body'],
    });
  }

  void _sendResponse(
    _ClientPeer client,
    String id,
    int status,
    Object? body,
  ) {
    _send(client.socket, {
      't': 'res',
      'id': id,
      'status': status,
      'body': body,
    });
  }

  _ClientPeer? _findClient(String bridgeId, String clientId) {
    for (final client in _clients[bridgeId] ?? const <_ClientPeer>{}) {
      if (client.id == clientId) return client;
    }
    return null;
  }

  void _removeBridge(_BridgePeer peer) {
    if (_bridges[peer.id] != peer) return;
    _bridges.remove(peer.id);
    _log('bridge disconnected: ${peer.name} (${peer.id})');
    _broadcastBridgeStatus(peer.id, false);
  }

  void _removeClient(_ClientPeer client) {
    final set = _clients[client.bridgeId];
    if (set == null) return;
    set.remove(client);
    if (set.isEmpty) _clients.remove(client.bridgeId);
    _log('phone disconnected: ${client.id}');
  }

  void _broadcastBridgeStatus(String bridgeId, bool online) {
    for (final client in _clients[bridgeId] ?? const <_ClientPeer>{}) {
      _send(client.socket, {'t': 'bridge', 'online': online});
    }
  }

  Map<String, dynamic>? _decode(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
    return null;
  }

  void _send(WebSocket socket, Map<String, Object?> message) {
    try {
      socket.add(jsonEncode(message));
    } on Object {
      // A closed socket is handled by its onDone/onError callback.
    }
  }

  void _json(HttpResponse response, int status, Object body) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set('Cache-Control', 'no-store');
    response.write(jsonEncode(body));
    response.close();
  }

  static String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static bool _constantTimeEquals(String left, String right) {
    final a = utf8.encode(left);
    final b = utf8.encode(right);
    var diff = a.length ^ b.length;
    final max = a.length > b.length ? a.length : b.length;
    for (var index = 0; index < max; index++) {
      final av = index < a.length ? a[index] : 0;
      final bv = index < b.length ? b[index] : 0;
      diff |= av ^ bv;
    }
    return diff == 0;
  }

  static void _log(String message) {
    stdout.writeln('[${DateTime.now().toIso8601String()}] $message');
  }

  static void _logError(Object error) {
    stderr.writeln('relay error: $error');
  }
}

final class _BridgePeer {
  _BridgePeer({required this.id, required this.name, required this.socket});

  final String id;
  final String name;
  final WebSocket socket;
}

final class _ClientPeer {
  _ClientPeer({required this.id, required this.bridgeId, required this.socket});

  final String id;
  final String bridgeId;
  final WebSocket socket;
  final Set<String> inFlight = {};
}
