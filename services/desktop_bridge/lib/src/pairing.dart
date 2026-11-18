import 'dart:io';

import 'package:qr/qr.dart';

import 'config_store.dart';

final class PairingPayload {
  PairingPayload({
    required this.bridgeId,
    required this.name,
    required this.secret,
    this.relayUrl = '',
    this.relayToken = '',
    this.endpoints = const [],
  });

  final String bridgeId;
  final String name;
  final String secret;
  final String relayUrl;
  final String relayToken;
  final List<String> endpoints;

  Uri toUri() => Uri(
    scheme: 'agentlink',
    host: 'pair',
    queryParameters: {
      'v': '1',
      'bridge': bridgeId,
      'name': name,
      'secret': secret,
      if (relayUrl.isNotEmpty) 'relay': relayUrl,
      if (relayToken.isNotEmpty) 'relayToken': relayToken,
      if (endpoints.isNotEmpty) 'endpoints': endpoints.join(','),
    },
  );

  String encode() => toUri().toString();

  static PairingPayload? parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'agentlink') return null;
    if (uri.host != 'pair' && uri.path != '/pair') return null;
    final params = uri.queryParameters;
    final bridgeId = params['bridge'] ?? '';
    final secret = params['secret'] ?? '';
    if (bridgeId.isEmpty || secret.isEmpty) return null;
    final endpoints = (params['endpoints'] ?? '')
        .split(',')
        .where((value) => value.trim().isNotEmpty)
        .map((value) => value.trim())
        .toList();
    return PairingPayload(
      bridgeId: bridgeId,
      name: params['name'] ?? 'AgentLink desktop',
      secret: secret,
      relayUrl: params['relay'] ?? '',
      relayToken: params['relayToken'] ?? '',
      endpoints: endpoints,
    );
  }
}

PairingPayload buildPairingPayload(
  BridgeConfig config, {
  required String httpHost,
  required int httpPort,
  List<String>? lanAddresses,
}) {
  final endpoints = <String>[];
  if (httpHost == '0.0.0.0' || httpHost == '::' || httpHost == '[::]') {
    for (final address in lanAddresses ?? const <String>[]) {
      endpoints.add('http://$address:$httpPort');
    }
  } else if (httpHost != '127.0.0.1' && httpHost != 'localhost') {
    final host = httpHost.contains(':') ? '[$httpHost]' : httpHost;
    endpoints.add('http://$host:$httpPort');
  }
  return PairingPayload(
    bridgeId: config.bridgeId,
    name: config.name,
    secret: config.pairingSecret ?? '',
    relayUrl: config.relayUrl,
    relayToken: config.relayToken,
    endpoints: endpoints.take(3).toList(),
  );
}

Future<List<String>> discoverLanAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final addresses = <String>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.address.startsWith('169.254.')) continue;
        if (address.isLoopback) continue;
        addresses.add(address.address);
      }
    }
    addresses.sort((a, b) {
      final aPrivate = _isPrivate(a);
      final bPrivate = _isPrivate(b);
      if (aPrivate != bPrivate) return aPrivate ? -1 : 1;
      return a.compareTo(b);
    });
    return addresses;
  } on SocketException {
    return const [];
  }
}

bool _isPrivate(String address) =>
    address.startsWith('10.') ||
    address.startsWith('192.168.') ||
    RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(address);

String renderQr(String data, {bool ansi = true}) {
  final qr = QrCode(
    payload: QrPayload.fromString(data),
    errorCorrectLevel: QrErrorCorrectLevel.medium,
  );
  final image = QrImage(qr);
  const border = 2;
  final size = image.moduleCount + border * 2;
  final buffer = StringBuffer();
  if (ansi) {
    const fgBlack = '\u001B[38;5;0m';
    const fgWhite = '\u001B[38;5;15m';
    const bgBlack = '\u001B[48;5;0m';
    const bgWhite = '\u001B[48;5;15m';
    const reset = '\u001B[0m';
    for (var y = 0; y < size; y += 2) {
      for (var x = 0; x < size; x++) {
        final top = _dark(image, x - border, y - border);
        final bottom = _dark(image, x - border, y + 1 - border);
        buffer
          ..write(top ? fgBlack : fgWhite)
          ..write(bottom ? bgBlack : bgWhite)
          ..write('▀');
      }
      buffer.writeln(reset);
    }
    buffer.writeln(reset);
  } else {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        buffer.write(_dark(image, x - border, y - border) ? '██' : '  ');
      }
      buffer.writeln();
    }
  }
  return buffer.toString();
}

bool _dark(QrImage image, int row, int col) {
  if (row < 0 ||
      col < 0 ||
      row >= image.moduleCount ||
      col >= image.moduleCount) {
    return false;
  }
  return image.isDark(row, col);
}

String pairingSummary(
  PairingPayload payload, {
  required String bridgeId,
}) {
  final buffer = StringBuffer();
  buffer.writeln('Pair this PC with the AgentLink Android app.');
  buffer.writeln('');
  buffer.writeln(renderQr(payload.encode()));
  buffer.writeln('Bridge:  ${payload.name} (${payload.bridgeId})');
  if (payload.relayUrl.isNotEmpty) {
    buffer.writeln('Relay:   ${payload.relayUrl}');
  } else {
    buffer.writeln('Relay:   not configured (LAN direct only)');
  }
  if (payload.endpoints.isNotEmpty) {
    buffer.writeln('LAN:     ${payload.endpoints.join(', ')}');
  }
  buffer.writeln('');
  buffer.writeln('Pairing link (tap to copy):');
  buffer.writeln(payload.encode());
  buffer.writeln('');
  buffer.writeln(
    'The link contains a one-time pairing secret. Do not share it. '
    'After pairing, this PC accepts only that phone until you run:',
  );
  buffer.writeln('  agentlink-bridge reset');
  return buffer.toString();
}

String pairingLinkText(PairingPayload payload) => payload.encode();

String defaultPairingEndpoint(BridgeConfig config) =>
    'http://127.0.0.1:${config.httpPort}';
