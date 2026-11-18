import 'dart:convert';
import 'dart:io';

import 'config_store.dart';
import 'fs_service.dart';
import 'models.dart';
import 'pairing.dart';
import 'provider_registry.dart';
import 'relay_client.dart';
import 'session_adapters.dart';
import 'session_manager.dart';
import 'util.dart';

enum AuthLevel { none, local, device }

final class ApiException implements Exception {
  const ApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

final class BridgeRouter {
  BridgeRouter({
    required this.configStore,
    required this.providers,
    required this.sessions,
    required this.files,
    List<SessionAdapter>? adapters,
    this.relayStatus,
  }) : adapters = adapters ?? defaultSessionAdapters();

  final ConfigStore configStore;
  final ProviderRegistry providers;
  final SessionManager sessions;
  final FileService files;
  final List<SessionAdapter> adapters;
  final RelayStatus Function()? relayStatus;
  final Map<String, List<DateTime>> _rateLimits = {};

  Future<BridgeResponse> handle(BridgeRequest request) async {
    final key = request.remoteAddress?.trim().isNotEmpty == true
        ? request.remoteAddress!.trim()
        : 'local';
    final now = DateTime.now();
    final bucket = _rateLimits.putIfAbsent(key, () => <DateTime>[]);
    bucket.removeWhere(
      (time) => now.difference(time) > const Duration(minutes: 1),
    );
    if (bucket.length >= 240) {
      return BridgeResponse(HttpStatus.tooManyRequests, {
        'error': 'Too many requests. Slow down and try again.',
      });
    }
    bucket.add(now);
    try {
      return await _route(request);
    } on ApiException catch (error) {
      return BridgeResponse(error.status, {'error': error.message});
    } on ConfigException catch (error) {
      final status = error.message.contains('already paired')
          ? HttpStatus.conflict
          : HttpStatus.badRequest;
      return BridgeResponse(status, {'error': error.message});
    } on SessionException catch (error) {
      return BridgeResponse(HttpStatus.badRequest, {'error': error.message});
    } on FsException catch (error) {
      return BridgeResponse(error.status, {'error': error.message});
    } on FormatException catch (error) {
      return BridgeResponse(HttpStatus.badRequest, {
        'error': error.message,
      });
    } on FileSystemException catch (error) {
      return BridgeResponse(HttpStatus.internalServerError, {
        'error': 'Filesystem error: ${error.message}',
      });
    } on Object catch (error, stack) {
      stderr.writeln('Bridge request failed: $error\n$stack');
      return BridgeResponse(HttpStatus.internalServerError, {
        'error': 'Internal bridge error',
      });
    }
  }

  Future<BridgeResponse> _route(BridgeRequest request) async {
    final method = request.method.toUpperCase();
    final path = _normalizePath(request.path);
    final body = request.body;

    if (method == 'GET' && path == '/v1/health') {
      return _ok({
        'status': 'ok',
        'name': 'AgentLink desktop bridge',
        'version': appVersion,
        'build': appBuild,
        'bridgeId': configStore.current.bridgeId,
        'paired': configStore.current.isPaired,
      });
    }

    if (method == 'POST' && path == '/v1/pair/claim') {
      return _pair(body);
    }

    final auth = _authorize(request);
    if (auth == AuthLevel.none) {
      throw const ApiException(
        HttpStatus.unauthorized,
        'Unauthorized. Pair this phone with the desktop bridge first.',
      );
    }

    if (method == 'GET' && path == '/v1/info') {
      return _info();
    }
    if (method == 'GET' && path == '/v1/providers') {
      final list = await providers.ensureReady();
      return _ok({
        'providers': list.map((provider) => provider.toJson()).toList(),
      });
    }
    if (method == 'GET' && path == '/v1/sessions') {
      return _history(request);
    }
    if (method == 'GET' && path == '/v1/session') {
      return _detail(request);
    }
    if (method == 'GET' && path == '/v1/live-sessions') {
      return _ok({
        'sessions': sessions.sessions
            .map((session) => session.toJson())
            .toList(),
      });
    }
    if (method == 'POST' && path == '/v1/live-sessions') {
      return _startSession(body);
    }

    final liveMatch = RegExp(
      r'^/v1/live-sessions/([^/]+)(?:/(terminal|input|resize|attach))?$',
    ).firstMatch(path);
    if (liveMatch != null) {
      final id = Uri.decodeComponent(liveMatch.group(1)!);
      final action = liveMatch.group(2);
      return _liveRoute(method, id, action, request);
    }

    if (method == 'GET' && path == '/v1/fs/roots') {
      return _ok({
        'home': files.home,
        'roots': files.roots().map((root) => root.toJson()).toList(),
      });
    }
    if (method == 'GET' && path == '/v1/fs/list') {
      final listing = await files.list(
        path: request.query['path'] ?? '',
        showHidden: queryBool(request.query, 'showHidden'),
      );
      return _ok(listing.toJson());
    }
    if (method == 'GET' && path == '/v1/fs/read') {
      final value = await files.read(
        path: request.query['path'] ?? '',
        maxBytes: queryInt(request.query, 'max'),
      );
      return _ok(value);
    }
    if (method == 'POST' && path == '/v1/fs/mkdir') {
      final entry = await files.mkdir(bodyString(body, 'path'));
      return BridgeResponse(HttpStatus.created, {
        'entry': entry.toJson(),
      });
    }

    if (const {
      '/v1/sessions',
      '/v1/session',
      '/v1/live-sessions',
      '/v1/providers',
      '/v1/info',
      '/v1/fs/roots',
      '/v1/fs/list',
      '/v1/fs/read',
      '/v1/fs/mkdir',
    }.contains(path)) {
      throw ApiException(
        HttpStatus.methodNotAllowed,
        'Method $method is not allowed for $path.',
      );
    }
    throw const ApiException(HttpStatus.notFound, 'Not found');
  }

  Future<BridgeResponse> _pair(Object? body) async {
    final secret = bodyString(body, 'secret');
    if (secret.isEmpty) {
      throw const ApiException(HttpStatus.badRequest, 'A pairing secret is required.');
    }
    if (configStore.current.isPaired) {
      throw const ApiException(
        HttpStatus.conflict,
        'This PC is already paired with another phone. '
        'Run "agentlink-bridge reset" on the PC to unpair it.',
      );
    }
    if (!configStore.verifyPairingSecret(secret)) {
      throw const ApiException(
        HttpStatus.forbidden,
        'That pairing secret is invalid or has expired. '
        'Restart the bridge to show a new QR code.',
      );
    }
    final grant = await configStore.pairDevice(
      deviceName: bodyString(body, 'deviceName', fallback: 'Android device'),
      platform: bodyString(body, 'platform', fallback: 'android'),
    );
    final info = await _bridgeConnectionInfo(grant.config);
    return BridgeResponse(HttpStatus.created, {
      'deviceToken': grant.token,
      'device': {
        'id': grant.device.id,
        'name': grant.device.name,
        'platform': grant.device.platform,
        'pairedAt': grant.device.pairedAt,
      },
      'bridge': info,
      'providers': (await providers.ensureReady())
          .map((provider) => provider.toJson())
          .toList(),
    });
  }

  Future<BridgeResponse> _info() async {
    final config = configStore.current;
    final providerList = await providers.ensureReady();
    return _ok({
      'name': 'AgentLink desktop bridge',
      'version': appVersion,
      'build': appBuild,
      'bridgeId': config.bridgeId,
      'desktopName': config.name,
      'platform': Platform.operatingSystem,
      'hostname': hostname(),
      'paired': config.isPaired,
      'device': config.device?.toJson(),
      'pairing': {
        'open': config.canPair,
        if (config.pairingCreatedAt != null)
          'createdAt': config.pairingCreatedAt,
      },
      'relay': relayStatus?.call().toJson() ??
          const {
            'state': 'disabled',
            'url': '',
            'configured': false,
          },
      'http': {
        'host': config.httpHost,
        'port': config.httpPort,
      },
      'desktop': {
        'openByDefault': config.openDesktopByDefault,
        'supported': Platform.isLinux || Platform.isMacOS || Platform.isWindows,
      },
      'endpoints': (await _bridgeConnectionInfo(config))['endpoints'],
      'providers': providerList.map((provider) => provider.toJson()).toList(),
    });
  }

  Future<Map<String, Object?>> _bridgeConnectionInfo(
    BridgeConfig config,
  ) async {
    final endpoints = <String>[];
    final scheme = config.tlsEnabled ? 'https' : 'http';
    if (config.httpHost == '0.0.0.0' ||
        config.httpHost == '::' ||
        config.httpHost == '[::]') {
      for (final address in await discoverLanAddresses()) {
        endpoints.add('$scheme://$address:${config.httpPort}');
      }
    } else if (config.httpHost != '127.0.0.1' &&
        config.httpHost != 'localhost') {
      final host = config.httpHost.contains(':')
          ? '[${config.httpHost}]'
          : config.httpHost;
      endpoints.add('$scheme://$host:${config.httpPort}');
    }
    return {
      'id': config.bridgeId,
      'name': config.name,
      'relay': config.relayUrl,
      'relayToken': config.relayToken,
      'endpoints': endpoints.take(3).toList(),
    };
  }

  AuthLevel _authorize(BridgeRequest request) {
    final token = _bearer(request);
    if (token.isEmpty) return AuthLevel.none;
    final config = configStore.current;
    if (request.remoteAddress != null &&
        _isLoopback(request.remoteAddress!) &&
        constantTimeEquals(config.localAttachToken, token)) {
      return AuthLevel.local;
    }
    if (configStore.verifyDeviceToken(token)) return AuthLevel.device;
    return AuthLevel.none;
  }

  String _bearer(BridgeRequest request) {
    final header = request.authorization;
    if (header.toLowerCase().startsWith('bearer ')) {
      return header.substring(7).trim();
    }
    final alternate = request.headers['x-agentlink-token'];
    return alternate?.trim() ?? '';
  }

  bool _isLoopback(String address) =>
      address == '127.0.0.1' ||
      address == '::1' ||
      address == '::ffff:127.0.0.1';

  Future<BridgeResponse> _history(BridgeRequest request) async {
    final limit = (queryInt(request.query, 'limit', fallback: 200) ?? 200)
        .clamp(1, 500);
    final results = await Future.wait(
      adapters.map((adapter) async {
        try {
          return await adapter.discover(limit: limit);
        } on Object catch (error) {
          stderr.writeln('${adapter.provider.label} discovery failed: $error');
          return <AgentSession>[];
        }
      }),
    );
    final all = results.expand((items) => items).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _ok({
      'sessions': all.take(limit).map((session) => session.toJson()).toList(),
    });
  }

  Future<BridgeResponse> _detail(BridgeRequest request) async {
    final providerId = request.query['provider'];
    final ref = request.query['ref'];
    final provider = AgentProvider.fromId(providerId);
    if (provider == null || ref == null || ref.isEmpty) {
      throw const ApiException(
        HttpStatus.badRequest,
        'provider and ref are required.',
      );
    }
    SessionAdapter? adapter;
    for (final item in adapters) {
      if (item.provider == provider) {
        adapter = item;
        break;
      }
    }
    final detail = await adapter?.detail(ref);
    if (detail == null) {
      throw const ApiException(HttpStatus.notFound, 'Session not found.');
    }
    return _ok(detail.toJson());
  }

  Future<BridgeResponse> _startSession(Object? body) async {
    final provider = AgentProvider.fromId(bodyString(body, 'provider'));
    if (provider == null) {
      throw const ApiException(
        HttpStatus.badRequest,
        'A valid provider is required.',
      );
    }
    final cwd = bodyString(body, 'cwd').trim();
    if (cwd.isEmpty) {
      throw const ApiException(
        HttpStatus.badRequest,
        'A working directory is required.',
      );
    }
    final prompt = bodyString(body, 'prompt').trim();
    final title = bodyString(body, 'title').trim();
    final resume = bodyString(body, 'resumeSessionId').trim();
    final model = bodyString(body, 'model').trim();
    final rawArgs = body is Map ? body['extraArgs'] : null;
    final extraArgs = rawArgs is List
        ? rawArgs.map((item) => item.toString()).toList()
        : const <String>[];
    final openOnDesktop = bodyBool(
      body,
      'openOnDesktop',
      fallback: configStore.current.openDesktopByDefault,
    );
    final session = await sessions.start(
      provider: provider,
      cwd: cwd,
      prompt: prompt,
      title: title,
      resumeSessionId: resume,
      model: model.isEmpty ? null : model,
      extraArgs: extraArgs,
      openOnDesktop: openOnDesktop,
    );
    return BridgeResponse(HttpStatus.created, {
      'session': session.toJson(),
    });
  }

  Future<BridgeResponse> _liveRoute(
    String method,
    String id,
    String? action,
    BridgeRequest request,
  ) async {
    final session = sessions.get(id);
    if (session == null) {
      throw const ApiException(HttpStatus.notFound, 'Live session not found.');
    }
    if (action == null) {
      if (method == 'GET') {
        return _ok({'session': session.toJson()});
      }
      if (method == 'DELETE') {
        if (!sessions.stop(id)) {
          throw const ApiException(
            HttpStatus.conflict,
            'This session has already ended.',
          );
        }
        return BridgeResponse(HttpStatus.accepted, {
          'status': 'stopping',
        });
      }
      if (method == 'PATCH') {
        final title = bodyString(request.body, 'title').trim();
        if (title.isEmpty) {
          throw const ApiException(
            HttpStatus.badRequest,
            'A title is required.',
          );
        }
        sessions.rename(id, title);
        return _ok({'session': session.toJson()});
      }
      throw const ApiException(
        HttpStatus.methodNotAllowed,
        'Unsupported live session method.',
      );
    }
    switch (action) {
      case 'terminal':
        if (method != 'GET') {
          throw const ApiException(
            HttpStatus.methodNotAllowed,
            'Use GET for terminal output.',
          );
        }
        final cursor = (queryInt(request.query, 'cursor', fallback: 0) ?? 0)
            .clamp(0, 1 << 50);
        final limit = (queryInt(
                  request.query,
                  'max',
                  fallback: maxChunkChars,
                ) ??
                maxChunkChars)
            .clamp(1024, maxChunkChars);
        final chunk = session.read(
          cursor: cursor,
          limit: limit,
          plain: queryBool(request.query, 'plain'),
        );
        return _ok(chunk.toJson());
      case 'input':
        if (method != 'POST') {
          throw const ApiException(
            HttpStatus.methodNotAllowed,
            'Use POST for terminal input.',
          );
        }
        final body = request.body;
        final base64 = bodyString(body, 'dataBase64');
        final text = bodyString(body, 'data');
        if (base64.isNotEmpty) {
          List<int> bytes;
          try {
            bytes = base64Decode(base64);
          } on FormatException {
            throw const ApiException(
              HttpStatus.badRequest,
              'dataBase64 is not valid base64.',
            );
          }
          if (bytes.length > 65536) {
            throw const ApiException(
              HttpStatus.badRequest,
              'Terminal input is too large.',
            );
          }
          if (!sessions.inputBytes(id, bytes)) {
            throw const ApiException(
              HttpStatus.conflict,
              'This session has already ended.',
            );
          }
        } else {
          if (text.isEmpty) {
            throw const ApiException(
              HttpStatus.badRequest,
              'data or dataBase64 is required.',
            );
          }
          if (text.length > 65536) {
            throw const ApiException(
              HttpStatus.badRequest,
              'Terminal input is too large.',
            );
          }
          if (!sessions.input(id, text)) {
            throw const ApiException(
              HttpStatus.conflict,
              'This session has already ended.',
            );
          }
        }
        return _ok({'ok': true});
      case 'resize':
        if (method != 'POST') {
          throw const ApiException(
            HttpStatus.methodNotAllowed,
            'Use POST for terminal resize.',
          );
        }
        final columns = bodyInt(request.body, 'columns');
        final rows = bodyInt(request.body, 'rows');
        if (columns == null || rows == null) {
          throw const ApiException(
            HttpStatus.badRequest,
            'columns and rows are required.',
          );
        }
        if (!sessions.resize(id, columns, rows)) {
          throw const ApiException(
            HttpStatus.conflict,
            'This session has already ended.',
          );
        }
        return _ok({'ok': true});
      case 'attach':
        if (method != 'POST') {
          throw const ApiException(
            HttpStatus.methodNotAllowed,
            'Use POST to open the desktop terminal.',
          );
        }
        final result = await sessions.attachToDesktop(id);
        return _ok({
          'opened': result.opened,
          if (result.terminal != null) 'terminal': result.terminal,
          if (result.error != null) 'error': result.error,
        });
    }
    throw const ApiException(HttpStatus.notFound, 'Not found.');
  }

  String _normalizePath(String value) {
    var path = value.trim();
    if (path.isEmpty) return '/';
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  BridgeResponse _ok(Object? body) => BridgeResponse(HttpStatus.ok, body);
}
