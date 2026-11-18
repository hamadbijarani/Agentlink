import 'package:agentlink_mobile/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips a saved connection profile', () {
    final profile = ConnectionProfile(
      bridgeId: 'bridge-1',
      bridgeName: 'Studio PC',
      desktopName: 'Studio PC',
      deviceToken: 'secret-token',
      relayUrl: 'wss://relay.example.com',
      relayToken: 'relay-token',
      endpoints: const ['http://192.168.1.20:7331'],
      pairedAt: DateTime.utc(2026, 11, 18, 10),
      deviceName: 'Pixel',
    );

    final restored = ConnectionProfile.fromJson(profile.toJson());

    expect(restored.bridgeId, 'bridge-1');
    expect(restored.deviceToken, 'secret-token');
    expect(restored.relayUrl, 'wss://relay.example.com');
    expect(restored.endpoints, ['http://192.168.1.20:7331']);
    expect(restored.usesRelay, isTrue);
    expect(restored.connectionLabel, 'Internet relay');
  });

  test('parses an agentlink pairing URI', () {
    final payload = PairingPayload(
      bridgeId: 'bridge-1',
      name: 'Studio PC',
      secret: '0123456789abcdef0123456789abcdef',
      relayUrl: 'wss://relay.example.com',
      relayToken: 'relay-token',
      endpoints: const [
        'http://192.168.1.20:7331',
        'http://10.0.0.5:7331',
      ],
    );

    final parsed = PairingPayload.tryParse(payload.encode());

    expect(parsed, isNotNull);
    expect(parsed!.bridgeId, 'bridge-1');
    expect(parsed.name, 'Studio PC');
    expect(parsed.secret, payload.secret);
    expect(parsed.relayUrl, 'wss://relay.example.com');
    expect(parsed.endpoints, hasLength(2));
    expect(PairingPayload.tryParse('https://example.com'), isNull);
    expect(PairingPayload.tryParse('agentlink://pair?bridge=x'), isNull);
  });

  test('parses a live session from the bridge', () {
    final session = LiveSession.fromJson({
      'id': 'live-1',
      'provider': 'claude',
      'title': 'Fix the tests',
      'cwd': '/work/app',
      'startedAt': '2026-11-18T10:00:00Z',
      'status': 'running',
      'openOnDesktop': true,
      'columns': 100,
      'rows': 32,
      'outputCursor': 1234,
      'desktopAttached': true,
      'desktopTerminal': 'gnome-terminal',
      'active': true,
    });

    expect(session.id, 'live-1');
    expect(session.provider, AgentProvider.claude);
    expect(session.isActive, isTrue);
    expect(session.desktopTerminal, 'gnome-terminal');
    expect(session.outputCursor, 1234);
  });

  test('parses provider themes served by the desktop', () {
    final provider = ProviderInfo.fromJson({
      'id': 'opencode',
      'label': 'OpenCode',
      'available': true,
      'version': '0.4.2',
      'command': '/usr/bin/opencode',
      'theme': {
        'name': 'OpenCode Graphite',
        'background': '#0B0B0C',
        'foreground': '#EDEDED',
        'accent': '#F5A742',
        'muted': '#8B8B8B',
        'surface': '#161617',
        'border': '#2C2C2E',
      },
      'capabilities': {'resume': true},
    });

    expect(provider.provider, AgentProvider.opencode);
    expect(provider.theme.accent, '#F5A742');
    expect(provider.canResume, isTrue);
    expect(colorValue(provider.theme.accent), 0xFFF5A742);
  });

  test('parses filesystem listings and terminal chunks', () {
    final listing = FsListing.fromJson({
      'path': '/home/user',
      'parent': '/home',
      'truncated': false,
      'entries': [
        {
          'name': 'Projects',
          'path': '/home/user/Projects',
          'isDirectory': true,
          'isHidden': false,
          'isLink': false,
        },
      ],
    });
    expect(listing.parent, '/home');
    expect(listing.entries.single.isDirectory, isTrue);

    final chunk = TerminalChunk.fromJson({
      'output': 'hello\n',
      'cursor': 6,
      'dropped': 0,
      'truncated': false,
      'running': true,
      'status': 'running',
      'hasMore': false,
    });
    expect(chunk.cursor, 6);
    expect(chunk.output, 'hello\n');
    expect(chunk.running, isTrue);
  });
}
