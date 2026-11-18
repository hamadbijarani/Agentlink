import 'dart:io';

import 'package:agentlink_desktop_bridge/agentlink_desktop_bridge.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late ConfigStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('agentlink-config-');
    store = ConfigStore(file: File('${temp.path}/bridge.json'));
    await store.loadOrCreate();
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('creates stable identifiers and a pending pairing secret', () async {
    final first = store.current;
    expect(first.bridgeId, isNotEmpty);
    expect(first.relaySecret, isNotEmpty);
    expect(first.pairingSecret, isNotEmpty);
    expect(first.isPaired, isFalse);

    final reloaded = ConfigStore(file: store.file);
    final second = await reloaded.loadOrCreate();
    expect(second.bridgeId, first.bridgeId);
    expect(second.pairingSecret, first.pairingSecret);
  });

  test('pairs one device, verifies its hashed token, and revokes it', () async {
    final secret = store.current.pairingSecret!;
    expect(store.verifyPairingSecret(secret), isTrue);
    expect(store.verifyPairingSecret('wrong'), isFalse);

    final grant = await store.pairDevice(
      deviceName: 'Pixel',
      platform: 'android',
    );
    expect(grant.token, isNotEmpty);
    expect(store.verifyDeviceToken(grant.token), isTrue);
    expect(store.verifyDeviceToken('wrong'), isFalse);
    expect(store.current.pairingSecret, isNull);
    expect(store.current.device?.name, 'Pixel');

    final raw = await store.file.readAsString();
    expect(raw, isNot(contains(grant.token)));

    await store.resetDevice();
    expect(store.current.isPaired, isFalse);
    expect(store.current.pairingSecret, isNotEmpty);
    expect(store.verifyDeviceToken(grant.token), isFalse);
  });

  test('rejects a corrupt config instead of overwriting it', () async {
    final file = File('${temp.path}/broken.json');
    await file.writeAsString('{not json');
    final broken = ConfigStore(file: file);
    await expectLater(
      broken.loadOrCreate(),
      throwsA(isA<ConfigException>()),
    );
  });
}
