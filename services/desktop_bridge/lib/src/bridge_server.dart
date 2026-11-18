import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'config_store.dart';
import 'desktop_launcher.dart';
import 'models.dart';
import 'relay_client.dart';
import 'router.dart';
import 'session_manager.dart';

final class AgentLinkBridge {
  AgentLinkBridge({
    required this.configStore,
    required this.router,
    required this.sessionManager,
    required this.launcher,
    this.host,
    this.port,
    this.enableHttp = true,
    this.enableRelay = true,
  });

  final ConfigStore configStore;
  final BridgeRouter router;
  final SessionManager sessionManager;
  final DesktopLauncher launcher;
  final InternetAddress? host;
  final int? port;
  final bool enableHttp;
  final bool enableRelay;
  HttpServer? _server;
  RelayClient? _relay;
  RelayStatus _relayStatus = const RelayStatus(
    state: RelayState.disabled,
    url: '',
  );
  StreamSubscription<void>? _sessionChanges;

  int? get boundPort => _server?.port;
  RelayStatus get relayStatus => _relayStatus;
  bool get httpEnabled => _server != null;

  Future<void> start() async {
    if (enableHttp) {
      final config = configStore.current;
      final bindHost = host ?? _parseHost(config.httpHost);
      final bindPort = port ?? config.httpPort;
      if (config.tlsEnabled) {
        final context = SecurityContext()
          ..useCertificateChain(config.httpsCert)
          ..usePrivateKey(config.httpsKey);
        _server = await HttpServer.bindSecure(
          bindHost,
          bindPort,
          context,
          shared: false,
        );
      } else {
        _server = await HttpServer.bind(bindHost, bindPort, shared: false);
      }
      launcher.setPort(_server!.port);
      _server!.listen(_handle, onError: _logError);
      _log('HTTP listening on ${bindHost.address}:${_server!.port}');
    }

    if (enableRelay && configStore.current.relayEnabled) {
      late final RelayClient relay;
      relay = RelayClient(
        configStore: configStore,
        handleRequest: router.handle,
        onStatus: (status) {
          _relayStatus = status;
          _log('relay ${status.state.name}${status.error == null ? '' : ': ${status.error}'}');
          if (status.state == RelayState.connected) {
            relay.sendEvent('relay', status.toJson());
          }
        },
      );
      _relay = relay;
      unawaited(relay.start());
    } else {
      _relayStatus = const RelayStatus(
        state: RelayState.disabled,
        url: '',
      );
    }

    _sessionChanges = sessionManager.changes.listen((_) {
      final relay = _relay;
      if (relay != null && relay.status.connected) {
        relay.sendEvent('sessions', {
          'sessions': sessionManager.sessions
              .map((session) => session.toJson())
              .toList(),
        });
      }
    });
  }

  Future<void> close() async {
    await _sessionChanges?.cancel();
    _sessionChanges = null;
    await _relay?.stop();
    _relay = null;
    await sessionManager.stopAll();
    await _server?.close(force: true);
    _server = null;
  }

  InternetAddress _parseHost(String value) {
    final clean = value.trim();
    if (clean.isEmpty || clean == '0.0.0.0') {
      return InternetAddress.anyIPv4;
    }
    if (clean == 'localhost') return InternetAddress.loopbackIPv4;
    if (clean == '::' || clean == '[::]') return InternetAddress.anyIPv6;
    try {
      return InternetAddress(clean);
    } on ArgumentError {
      return InternetAddress.loopbackIPv4;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final body = await _readBody(request);
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(',');
      });
      final response = await router.handle(
        BridgeRequest(
          method: request.method,
          path: request.uri.path,
          query: request.uri.queryParameters,
          headers: headers,
          body: body,
          remoteAddress: request.connectionInfo?.remoteAddress.address,
        ),
      );
      _write(request.response, response);
    } on FormatException catch (error) {
      _json(request.response, HttpStatus.badRequest, {
        'error': error.message,
      });
    } on Object catch (error, stack) {
      _logError('request failed: $error\n$stack');
      _json(request.response, HttpStatus.internalServerError, {
        'error': 'Internal bridge error',
      });
    }
  }

  Future<Object?> _readBody(HttpRequest request) async {
    if (request.method != 'POST' &&
        request.method != 'PATCH' &&
        request.method != 'PUT') {
      await request.drain<void>();
      return null;
    }
    var size = 0;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      size += chunk.length;
      if (size > 4 * 1024 * 1024) {
        throw const FormatException('Request body is too large.');
      }
      builder.add(chunk);
    }
    if (size == 0) return null;
    final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void _write(HttpResponse response, BridgeResponse value) {
    response.statusCode = value.status;
    response.headers.contentType = ContentType.json;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    for (final entry in value.headers.entries) {
      response.headers.set(entry.key, entry.value);
    }
    response.write(jsonEncode(value.body ?? const <String, Object?>{}));
    response.close();
  }

  void _json(HttpResponse response, int status, Object body) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set('Cache-Control', 'no-store');
    response.write(jsonEncode(body));
    response.close();
  }

  static void _log(String message) {
    stdout.writeln('[${DateTime.now().toTimeString()}] $message');
  }

  static void _logError(Object error) {
    stderr.writeln('bridge: $error');
  }
}

extension on DateTime {
  String toTimeString() =>
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}:'
      '${second.toString().padLeft(2, '0')}';
}
