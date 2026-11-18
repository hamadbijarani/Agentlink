import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config_store.dart';
import 'models.dart';

enum RelayState { disabled, connecting, connected, disconnected }

final class RelayStatus {
  const RelayStatus({
    required this.state,
    required this.url,
    this.error,
    this.connectedAt,
  });

  final RelayState state;
  final String url;
  final String? error;
  final DateTime? connectedAt;

  bool get connected => state == RelayState.connected;

  Map<String, Object?> toJson() => {
    'state': state.name,
    'url': url,
    'configured': url.isNotEmpty,
    'error': error,
    if (connectedAt != null)
      'connectedAt': connectedAt!.toUtc().toIso8601String(),
  };
}

final class RelayClient {
  RelayClient({
    required this.configStore,
    required this.handleRequest,
    required this.onStatus,
  });

  final ConfigStore configStore;
  final Future<BridgeResponse> Function(BridgeRequest request) handleRequest;
  final void Function(RelayStatus status) onStatus;
  final _events = StreamController<Map<String, Object?>>.broadcast();

  WebSocket? _socket;
  Timer? _retryTimer;
  bool _stopped = true;
  int _attempt = 0;
  RelayStatus _status = const RelayStatus(
    state: RelayState.disabled,
    url: '',
  );

  RelayStatus get status => _status;
  Stream<Map<String, Object?>> get events => _events.stream;

  Future<void> start() async {
    _stopped = false;
    await _connect();
  }

  Future<void> stop() async {
    _stopped = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _socket?.close(1000, 'Bridge shutting down');
    _socket = null;
    _setStatus(
      RelayStatus(state: RelayState.disabled, url: configStore.current.relayUrl),
    );
  }

  Future<void> _connect() async {
    if (_stopped) return;
    final config = configStore.current;
    if (config.relayUrl.isEmpty) {
      _setStatus(
        const RelayStatus(state: RelayState.disabled, url: ''),
      );
      return;
    }
    final uri = _connectionUri(config);
    _setStatus(RelayStatus(state: RelayState.connecting, url: config.relayUrl));
    try {
      final socket = await WebSocket.connect(
        uri.toString(),
        headers: const {'User-Agent': 'AgentLink-bridge/1.0'},
      ).timeout(const Duration(seconds: 15));
      if (_stopped) {
        await socket.close(1000, 'Bridge stopped');
        return;
      }
      socket.pingInterval = const Duration(seconds: 20);
      _socket = socket;
      _attempt = 0;
      _setStatus(
        RelayStatus(
          state: RelayState.connected,
          url: config.relayUrl,
          connectedAt: DateTime.now().toUtc(),
        ),
      );
      socket.listen(
        _onMessage,
        onDone: () => _onDisconnected(socket, 'Relay closed the connection'),
        onError: (Object error) =>
            _onDisconnected(socket, 'Relay connection error: $error'),
        cancelOnError: true,
      );
    } on Object catch (error) {
      _onDisconnected(null, _friendlyError(error));
    }
  }

  Uri _connectionUri(BridgeConfig config) {
    final base = Uri.parse(config.relayUrl.trim());
    final scheme = switch (base.scheme) {
      'https' || 'wss' => 'wss',
      'http' || 'ws' => 'ws',
      _ => 'wss',
    };
    var path = base.path;
    if (path.isEmpty || path == '/') path = '/v1/connect';
    final query = <String, String>{
      ...base.queryParameters,
      'role': 'bridge',
      'bridgeId': config.bridgeId,
      'secret': config.relaySecret,
      'name': config.name,
      if (config.relayToken.isNotEmpty) 'token': config.relayToken,
    };
    return base.replace(scheme: scheme, path: path, queryParameters: query);
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
        _setStatus(
          RelayStatus(
            state: RelayState.connected,
            url: configStore.current.relayUrl,
            connectedAt: _status.connectedAt ?? DateTime.now().toUtc(),
          ),
        );
        break;
      case 'req':
        unawaited(_handleRelayRequest(message));
        break;
      case 'ping':
        _send({'t': 'pong'});
        break;
    }
  }

  Future<void> _handleRelayRequest(Map<String, dynamic> message) async {
    final id = message['id']?.toString() ?? '';
    final client = message['client']?.toString() ?? '';
    if (id.isEmpty || client.isEmpty) return;
    BridgeResponse response;
    try {
      response = await handleRequest(
        BridgeRequest(
          method: message['method']?.toString().toUpperCase() ?? 'GET',
          path: message['path']?.toString() ?? '/',
          query: _stringMap(message['query']),
          headers: _stringMap(message['headers']),
          body: message['body'],
          remoteAddress: null,
        ),
      );
    } on Object catch (error) {
      response = BridgeResponse(
        HttpStatus.internalServerError,
        {'error': 'Bridge error: $error'},
      );
    }
    _send({
      't': 'res',
      'id': id,
      'to': client,
      'status': response.status,
      'body': response.body,
      if (response.headers.isNotEmpty) 'headers': response.headers,
    });
  }

  Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const {};
    final result = <String, String>{};
    for (final entry in value.entries) {
      result[entry.key.toString().toLowerCase()] = entry.value.toString();
    }
    return result;
  }

  void sendEvent(String event, Object? body) {
    _send({'t': 'event', 'event': event, 'body': body});
  }

  void _send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    try {
      socket.add(jsonEncode(message));
    } on Object {
      // The close callback schedules a reconnect.
    }
  }

  void _onDisconnected(WebSocket? socket, String reason) {
    if (socket != null && _socket != socket) return;
    if (_socket == socket) _socket = null;
    if (_stopped) return;
    _setStatus(
      RelayStatus(
        state: RelayState.disconnected,
        url: configStore.current.relayUrl,
        error: reason,
      ),
    );
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopped || _retryTimer != null) return;
    _attempt++;
    final seconds = switch (_attempt) {
      1 => 1,
      2 => 2,
      3 => 4,
      4 => 8,
      5 => 15,
      _ => 30,
    };
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      unawaited(_connect());
    });
  }

  String _friendlyError(Object error) {
    if (error is SocketException) {
      return 'Cannot reach the relay: ${error.message}';
    }
    if (error is HandshakeException) {
      return 'TLS handshake with the relay failed.';
    }
    return 'Relay connection failed: $error';
  }

  void _setStatus(RelayStatus value) {
    _status = value;
    onStatus(value);
  }
}
