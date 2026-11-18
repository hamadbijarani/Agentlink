import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentlink_desktop_bridge/agentlink_desktop_bridge.dart';
import 'package:agentlink_relay/agentlink_relay.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late File fakeAgent;
  late ConfigStore store;
  late SessionManager sessions;
  late AgentLinkBridge bridge;
  late RelayServer relay;
  late _Phone phone;
  late String relayToken;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('agentlink-e2e-');
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

    relayToken = 'relay-token-with-enough-length';
    final relayState = File('${temp.path}/relay-state.json');
    relay = RelayServer(
      host: InternetAddress.loopbackIPv4,
      port: 0,
      token: relayToken,
      store: RelayStore(file: relayState),
    );
    await relay.start();

    store = ConfigStore(file: File('${temp.path}/bridge.json'));
    await store.loadOrCreate();
    await store.configure(
      name: 'Test PC',
      relayUrl: 'ws://127.0.0.1:${relay.boundPort}/v1/connect',
      relayToken: relayToken,
      httpHost: '127.0.0.1',
      httpPort: 0,
    );

    final providers = ProviderRegistry(
      executableOverrides: {'claude': fakeAgent.path},
    );
    sessions = SessionManager(
      providers: providers,
      desktopOpener: (session) async =>
          const DesktopAttachResult(opened: false),
    );
    final router = BridgeRouter(
      configStore: store,
      providers: providers,
      sessions: sessions,
      files: FileService(home: temp.path),
      adapters: const [],
    );
    bridge = AgentLinkBridge(
      configStore: store,
      router: router,
      sessionManager: sessions,
      launcher: DesktopLauncher(configStore: store),
      enableHttp: false,
      enableRelay: true,
    );
    await bridge.start();
    await providers.ensureReady();

    phone = await _Phone.connect(
      relayPort: relay.boundPort!,
      relayToken: relayToken,
      bridgeId: store.current.bridgeId,
    );
    await phone.waitForBridgeOnline();
  });

  tearDown(() async {
    await phone.close();
    await bridge.close();
    await sessions.dispose();
    await relay.close();
    await temp.delete(recursive: true);
  });

  test('pairs and controls a real PTY session through the relay', () async {
    final claim = await phone.request(
      'POST',
      '/v1/pair/claim',
      body: {
        'secret': store.current.pairingSecret,
        'deviceName': 'Test phone',
        'platform': 'android',
      },
    );
    expect(claim['status'], HttpStatus.created);
    final body = claim['body'] as Map;
    final token = body['deviceToken'] as String;
    expect(token, isNotEmpty);

    final info = await phone.request('GET', '/v1/info', token: token);
    expect(info['status'], HttpStatus.ok);
    expect((info['body'] as Map)['paired'], isTrue);

    final started = await phone.request(
      'POST',
      '/v1/live-sessions',
      token: token,
      body: {
        'provider': 'claude',
        'cwd': temp.path,
        'openOnDesktop': false,
      },
    );
    expect(started['status'], HttpStatus.created);
    final sessionId =
        ((started['body'] as Map)['session'] as Map)['id'] as String;

    var cursor = 0;
    final output = StringBuffer();
    final readyDeadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(readyDeadline)) {
      final chunk = await phone.request(
        'GET',
        '/v1/live-sessions/$sessionId/terminal?plain=1&cursor=$cursor',
        token: token,
      );
      expect(chunk['status'], HttpStatus.ok);
      final chunkBody = chunk['body'] as Map;
      output.write(chunkBody['output']);
      cursor = (chunkBody['cursor'] as num).toInt();
      if (output.toString().contains('FAKE READY')) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(output.toString(), contains('FAKE READY'));

    final input = await phone.request(
      'POST',
      '/v1/live-sessions/$sessionId/input',
      token: token,
      body: {'data': 'hello over relay\n'},
    );
    expect(input['status'], HttpStatus.ok);

    final gotDeadline = DateTime.now().add(const Duration(seconds: 8));
    var got = false;
    while (DateTime.now().isBefore(gotDeadline)) {
      final chunk = await phone.request(
        'GET',
        '/v1/live-sessions/$sessionId/terminal?plain=1&cursor=$cursor',
        token: token,
      );
      final chunkBody = chunk['body'] as Map;
      output.write(chunkBody['output']);
      cursor = (chunkBody['cursor'] as num).toInt();
      if (output.toString().contains('FAKE GOT:hello over relay')) {
        got = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(got, isTrue);

    final live = await phone.request(
      'GET',
      '/v1/live-sessions',
      token: token,
    );
    expect((live['body'] as Map)['sessions'], hasLength(1));

    final fs = await phone.request('GET', '/v1/fs/roots', token: token);
    expect(fs['status'], HttpStatus.ok);

    final stopped = await phone.request(
      'DELETE',
      '/v1/live-sessions/$sessionId',
      token: token,
    );
    expect(stopped['status'], HttpStatus.accepted);

    final endedDeadline = DateTime.now().add(const Duration(seconds: 8));
    var ended = false;
    while (DateTime.now().isBefore(endedDeadline)) {
      final detail = await phone.request(
        'GET',
        '/v1/live-sessions/$sessionId',
        token: token,
      );
      final session = (detail['body'] as Map)['session'] as Map;
      if (session['active'] == false && session['status'] != 'stopping') {
        ended = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(ended, isTrue);
  });
}

final class _Phone {
  _Phone({
    required this.socket,
    required this.iterator,
  });

  final WebSocket socket;
  final StreamIterator<dynamic> iterator;
  var _counter = 0;

  static Future<_Phone> connect({
    required int relayPort,
    required String relayToken,
    required String bridgeId,
  }) async {
    final uri = Uri.parse(
      'ws://127.0.0.1:$relayPort/v1/connect',
    ).replace(
      queryParameters: {
        'role': 'client',
        'bridgeId': bridgeId,
        'token': relayToken,
      },
    );
    final socket = await WebSocket.connect(uri.toString());
    return _Phone(
      socket: socket,
      iterator: StreamIterator<dynamic>(socket),
    );
  }

  Future<Map<String, dynamic>> _next() async {
    final hasNext = await iterator.moveNext().timeout(
      const Duration(seconds: 15),
    );
    if (!hasNext) {
      throw StateError('Relay closed the phone connection.');
    }
    return Map<String, dynamic>.from(
      jsonDecode(iterator.current as String) as Map,
    );
  }

  Future<void> waitForBridgeOnline() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      final message = await _next();
      if ((message['t'] == 'ready' || message['t'] == 'bridge') &&
          message['online'] == true) {
        return;
      }
    }
    throw StateError('The bridge never came online on the relay.');
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
  }) async {
    final id = 'phone-${++_counter}';
    final split = path.split('?');
    final query = split.length > 1
        ? Uri.splitQueryString(split.sublist(1).join('?'))
        : const <String, String>{};
    socket.add(
      jsonEncode({
        't': 'req',
        'id': id,
        'method': method,
        'path': split.first,
        'query': query,
        'headers': {
          if (token != null) 'authorization': 'Bearer $token',
        },
        'body': body,
      }),
    );
    while (true) {
      final message = await _next();
      if (message['t'] == 'res' && message['id'] == id) {
        return message;
      }
    }
  }

  Future<void> close() async {
    await iterator.cancel();
    await socket.close();
  }
}
