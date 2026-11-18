import 'dart:convert';
import 'dart:io';

import 'package:agentlink_desktop_bridge/agentlink_desktop_bridge.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late ConfigStore store;
  late BridgeConfig config;
  late SessionManager sessions;
  late AgentLinkBridge bridge;
  late HttpClient client;
  late String token;
  late String baseUrl;
  late File fakeAgent;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('agentlink-test-');
    fakeAgent = File('${temp.path}/fake-agent.sh');
    await fakeAgent.writeAsString('''#!/bin/sh
if [ "\$1" = "--version" ]; then
  echo "fake-agent 1.0.0"
  exit 0
fi
echo "FAKE READY"
while IFS= read -r line; do
  echo "FAKE GOT:\$line"
  if [ "\$line" = "exit" ]; then
    exit 0
  fi
done
''');
    await Process.run('chmod', ['755', fakeAgent.path]);

    store = ConfigStore(file: File('${temp.path}/bridge.json'));
    config = await store.loadOrCreate();
    config = await store.configure(httpHost: '127.0.0.1', httpPort: 1);

    final providers = ProviderRegistry(
      executableOverrides: {'claude': fakeAgent.path},
    );
    sessions = SessionManager(
      providers: providers,
      desktopOpener: (session) async => const DesktopAttachResult(
        opened: false,
        error: 'disabled in tests',
      ),
    );
    final files = FileService(home: temp.path);
    late final AgentLinkBridge created;
    final router = BridgeRouter(
      configStore: store,
      providers: providers,
      sessions: sessions,
      files: files,
      adapters: const [],
      relayStatus: () => created.relayStatus,
    );
    created = AgentLinkBridge(
      configStore: store,
      router: router,
      sessionManager: sessions,
      launcher: DesktopLauncher(configStore: store),
      host: InternetAddress.loopbackIPv4,
      port: 0,
      enableRelay: false,
    );
    bridge = created;
    await bridge.start();
    client = HttpClient();
    baseUrl = 'http://127.0.0.1:${bridge.boundPort}';
  });

  tearDown(() async {
    client.close(force: true);
    await bridge.close();
    await sessions.dispose();
    await temp.delete(recursive: true);
  });

  Future<_Response> request(
    String method,
    String path, {
    String? bearer,
    Object? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final req = await client.openUrl(method, uri);
    if (bearer != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    req.headers.contentType = ContentType.json;
    if (body != null) req.write(jsonEncode(body));
    final response = await req.close();
    final text = await response.transform(utf8.decoder).join();
    final json = text.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(text) as Map);
    return _Response(response.statusCode, json);
  }

  Future<void> pair() async {
    final response = await request(
      'POST',
      '/v1/pair/claim',
      body: {
        'secret': store.current.pairingSecret,
        'deviceName': 'Test phone',
        'platform': 'android',
      },
    );
    expect(response.status, HttpStatus.created);
    token = response.json['deviceToken'] as String;
  }

  test('health is public and reports pairing state', () async {
    final response = await request('GET', '/v1/health');
    expect(response.status, HttpStatus.ok);
    expect(response.json['status'], 'ok');
    expect(response.json['paired'], isFalse);
  });

  test('pairing returns a device token and enforces one phone', () async {
    await pair();
    expect(token, isNotEmpty);
    expect(store.current.isPaired, isTrue);
    expect(store.current.pairingSecret, isNull);

    final second = await request(
      'POST',
      '/v1/pair/claim',
      body: {
        'secret': config.pairingSecret,
        'deviceName': 'Other phone',
      },
    );
    expect(second.status, HttpStatus.conflict);

    final unauthorized = await request('GET', '/v1/info');
    expect(unauthorized.status, HttpStatus.unauthorized);

    final info = await request('GET', '/v1/info', bearer: token);
    expect(info.status, HttpStatus.ok);
    expect(info.json['bridgeId'], store.current.bridgeId);
    expect(info.json['paired'], isTrue);
  });

  test('filesystem browsing lists directories', () async {
    await pair();
    final response = await request(
      'GET',
      '/v1/fs/list?path=${Uri.encodeQueryComponent(temp.path)}',
      bearer: token,
    );
    expect(response.status, HttpStatus.ok);
    final entries = response.json['entries'] as List;
    expect(
      entries.any((entry) => (entry as Map)['name'] == 'fake-agent.sh'),
      isTrue,
    );
  });

  test('starts, mirrors, controls, and closes a PTY session', () async {
    await pair();
    final started = await request(
      'POST',
      '/v1/live-sessions',
      bearer: token,
      body: {
        'provider': 'claude',
        'cwd': temp.path,
        'openOnDesktop': false,
      },
    );
    expect(started.status, HttpStatus.created);
    final sessionId =
        (started.json['session'] as Map)['id'] as String;

    var cursor = 0;
    final output = StringBuffer();
    final readyDeadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(readyDeadline)) {
      final chunk = await request(
        'GET',
        '/v1/live-sessions/$sessionId/terminal?plain=1&cursor=$cursor',
        bearer: token,
      );
      expect(chunk.status, HttpStatus.ok);
      output.write(chunk.json['output']);
      cursor = (chunk.json['cursor'] as num).toInt();
      if (output.toString().contains('FAKE READY')) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(output.toString(), contains('FAKE READY'));

    final input = await request(
      'POST',
      '/v1/live-sessions/$sessionId/input',
      bearer: token,
      body: {'data': 'hello from phone\n'},
    );
    expect(input.status, HttpStatus.ok);

    final gotDeadline = DateTime.now().add(const Duration(seconds: 8));
    var got = false;
    while (DateTime.now().isBefore(gotDeadline)) {
      final chunk = await request(
        'GET',
        '/v1/live-sessions/$sessionId/terminal?plain=1&cursor=$cursor',
        bearer: token,
      );
      output.write(chunk.json['output']);
      cursor = (chunk.json['cursor'] as num).toInt();
      if (output.toString().contains('FAKE GOT:hello from phone')) {
        got = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(got, isTrue);

    final renamed = await request(
      'PATCH',
      '/v1/live-sessions/$sessionId',
      bearer: token,
      body: {'title': 'Renamed session'},
    );
    expect(renamed.status, HttpStatus.ok);
    expect(
      (renamed.json['session'] as Map)['title'],
      'Renamed session',
    );

    final stopped = await request(
      'DELETE',
      '/v1/live-sessions/$sessionId',
      bearer: token,
    );
    expect(stopped.status, HttpStatus.accepted);

    final endedDeadline = DateTime.now().add(const Duration(seconds: 8));
    var ended = false;
    while (DateTime.now().isBefore(endedDeadline)) {
      final detail = await request(
        'GET',
        '/v1/live-sessions/$sessionId',
        bearer: token,
      );
      final session = detail.json['session'] as Map;
      if (session['active'] == false && session['status'] != 'stopping') {
        ended = true;
        expect(session['status'], 'stopped');
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(ended, isTrue);
  });
}

final class _Response {
  const _Response(this.status, this.json);

  final int status;
  final Map<String, dynamic> json;
}
