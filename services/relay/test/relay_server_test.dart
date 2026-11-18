import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agentlink_relay/agentlink_relay.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late RelayServer relay;
  late String base;
  const relayToken = 'relay-token-long-enough';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('agentlink-relay-');
    relay = RelayServer(
      host: InternetAddress.loopbackIPv4,
      port: 0,
      token: relayToken,
      store: RelayStore(file: File('${temp.path}/relay.json')),
    );
    await relay.start();
    base = 'ws://127.0.0.1:${relay.boundPort}/v1/connect';
  });

  tearDown(() async {
    await relay.close();
    await temp.delete(recursive: true);
  });

  Future<({WebSocket socket, StreamIterator<dynamic> iterator})> connect(
    Map<String, String> query,
  ) async {
    final uri = Uri.parse(base).replace(
      queryParameters: {...query, 'token': relayToken},
    );
    final socket = await WebSocket.connect(uri.toString());
    return (socket: socket, iterator: StreamIterator<dynamic>(socket));
  }

  Future<Map<String, dynamic>> next(
    StreamIterator<dynamic> iterator,
  ) async {
    final hasNext = await iterator.moveNext().timeout(
      const Duration(seconds: 5),
    );
    expect(hasNext, isTrue);
    return Map<String, dynamic>.from(
      jsonDecode(iterator.current as String) as Map,
    );
  }

  test('routes a phone request to a bridge and returns the response', () async {
    final bridge = await connect({
      'role': 'bridge',
      'bridgeId': 'bridge-1',
      'secret': 'bridge-secret-with-enough-entropy',
      'name': 'Test PC',
    });
    final bridgeReady = await next(bridge.iterator);
    expect(bridgeReady['t'], 'ready');
    expect(bridgeReady['role'], 'bridge');

    final phone = await connect({'role': 'client', 'bridgeId': 'bridge-1'});
    final phoneReady = await next(phone.iterator);
    expect(phoneReady['t'], 'ready');
    expect(phoneReady['online'], isTrue);
    final status = await next(phone.iterator);
    expect(status['t'], 'bridge');
    expect(status['online'], isTrue);

    phone.socket.add(
      jsonEncode({
        't': 'req',
        'id': 'req-1',
        'method': 'GET',
        'path': '/v1/health',
        'query': <String, String>{},
        'headers': <String, String>{},
      }),
    );
    final forwarded = await next(bridge.iterator);
    expect(forwarded['t'], 'req');
    expect(forwarded['id'], 'req-1');
    expect(forwarded['client'], isNotEmpty);
    bridge.socket.add(
      jsonEncode({
        't': 'res',
        'id': 'req-1',
        'to': forwarded['client'],
        'status': 200,
        'body': {'ok': true},
      }),
    );
    final response = await next(phone.iterator);
    expect(response['t'], 'res');
    expect(response['status'], 200);
    expect((response['body'] as Map)['ok'], isTrue);

    await bridge.socket.close();
    await phone.socket.close();
  });

  test('returns 503 when the desktop bridge is offline', () async {
    final phone = await connect({'role': 'client', 'bridgeId': 'offline'});
    await next(phone.iterator);
    final status = await next(phone.iterator);
    expect(status['online'], isFalse);
    phone.socket.add(
      jsonEncode({
        't': 'req',
        'id': 'req-offline',
        'method': 'GET',
        'path': '/v1/health',
      }),
    );
    final response = await next(phone.iterator);
    expect(response['status'], 503);
    expect(
      ((response['body'] as Map)['error'] as String),
      contains('offline'),
    );
    await phone.socket.close();
  });

  test('rejects a bridge with the wrong secret', () async {
    final first = await connect({
      'role': 'bridge',
      'bridgeId': 'bridge-2',
      'secret': 'first-secret-with-enough-entropy',
    });
    await next(first.iterator);
    final secondUri = Uri.parse(base).replace(
      queryParameters: {
        'role': 'bridge',
        'bridgeId': 'bridge-2',
        'secret': 'wrong-secret-with-enough-entropy',
        'token': relayToken,
      },
    );
    final second = await WebSocket.connect(secondUri.toString());
    final iterator = StreamIterator<dynamic>(second);
    final hasNext = await iterator.moveNext().timeout(
      const Duration(seconds: 5),
    );
    expect(hasNext, isFalse);
    expect(second.closeCode, 4003);
    await first.socket.close();
  });

  test('rejects connections without the relay token', () async {
    final uri = Uri.parse(base).replace(
      queryParameters: {
        'role': 'client',
        'bridgeId': 'bridge-3',
      },
    );
    await expectLater(
      WebSocket.connect(uri.toString()),
      throwsA(isA<WebSocketException>()),
    );
  });
}
