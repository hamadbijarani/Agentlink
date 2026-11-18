import 'dart:convert';
import 'dart:io';

import 'package:agentlink_desktop_bridge/src/models.dart';
import 'package:agentlink_desktop_bridge/src/session_adapters.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('agentlink-test-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('discovers and parses a Claude JSONL session', () async {
    final file = File('${temp.path}/session-1.jsonl');
    await file.writeAsString(
      [
        {
          'type': 'user',
          'sessionId': 'session-1',
          'cwd': '/work/example',
          'timestamp': '2026-11-18T10:00:00Z',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Fix the failing tests'},
            ],
          },
        },
        {
          'type': 'assistant',
          'sessionId': 'session-1',
          'timestamp': '2026-11-18T10:00:01Z',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'I will inspect the test suite.'},
            ],
          },
        },
      ].map(jsonEncode).join('\n'),
    );
    final adapter = FileSessionAdapter(
      provider: AgentProvider.claude,
      roots: [temp],
    );

    final sessions = await adapter.discover();
    final detail = await adapter.detail(sessions.single.ref);

    expect(sessions.single.id, 'session-1');
    expect(sessions.single.title, 'Fix the failing tests');
    expect(sessions.single.messageCount, 2);
    expect(detail?.messages, hasLength(2));
    expect(detail?.messages.last.role, 'assistant');
  });

  test('rejects a session ref outside configured roots', () async {
    final adapter = FileSessionAdapter(
      provider: AgentProvider.claude,
      roots: [temp],
    );

    final detail = await adapter.detail(encodeRef('/etc/passwd'));

    expect(detail, isNull);
  });
}
