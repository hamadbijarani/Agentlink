import 'dart:io';

import 'package:agentlink_relay/agentlink_relay.dart';

Future<void> main(List<String> arguments) async {
  final options = RelayOptions.parse(arguments);
  if (options.showHelp) {
    stdout.writeln(RelayOptions.usage);
    return;
  }
  SecurityContext? context;
  if (options.certificate != null && options.privateKey != null) {
    context = SecurityContext()
      ..useCertificateChain(options.certificate!)
      ..usePrivateKey(options.privateKey!);
  }
  final server = RelayServer(
    host: options.host,
    port: options.port,
    token: options.token,
    store: RelayStore(file: options.stateFile),
    securityContext: context,
  );
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    exit(0);
  });
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close();
    exit(0);
  });
  await server.start();
  stdout.writeln('');
  stdout.writeln('AgentLink relay ${context == null ? 'ws' : 'wss'} ready.');
  stdout.writeln(
    'Bridge URL: ${context == null ? 'ws' : 'wss'}://<public-host>:${server.boundPort}/v1/connect',
  );
  if (context == null) {
    stdout.writeln(
      'TLS is off. Use a TLS reverse proxy or --cert/--key before exposing this port to the internet.',
    );
  }
  if (options.token.isEmpty) {
    stdout.writeln(
      'No relay token set. Set AGENTLINK_RELAY_TOKEN to require a token for connections.',
    );
  }
  stdout.writeln('State: ${options.stateFile.path}');
  stdout.writeln('Press Ctrl+C to stop.');
}

final class RelayOptions {
  RelayOptions({
    required this.host,
    required this.port,
    required this.token,
    required this.stateFile,
    required this.certificate,
    required this.privateKey,
    required this.showHelp,
  });

  final InternetAddress host;
  final int port;
  final String token;
  final File stateFile;
  final String? certificate;
  final String? privateKey;
  final bool showHelp;

  static RelayOptions parse(List<String> arguments) {
    var host = InternetAddress.anyIPv4;
    var port = 8787;
    var token = Platform.environment['AGENTLINK_RELAY_TOKEN'] ?? '';
    var statePath = Platform.environment['AGENTLINK_RELAY_STATE'] ?? '';
    String? certificate;
    String? privateKey;
    var showHelp = false;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      String requireValue() {
        if (index + 1 >= arguments.length) {
          throw FormatException('Missing value after $argument');
        }
        return arguments[++index];
      }

      switch (argument) {
        case '--host':
          host = InternetAddress(requireValue());
        case '--port':
          port = int.parse(requireValue());
        case '--token':
          token = requireValue();
        case '--state':
          statePath = requireValue();
        case '--cert':
          certificate = requireValue();
        case '--key':
          privateKey = requireValue();
        case '--help':
        case '-h':
          showHelp = true;
        default:
          throw FormatException('Unknown argument: $argument\n\n$usage');
      }
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('Port must be between 1 and 65535.');
    }
    if ((certificate == null) != (privateKey == null)) {
      throw const FormatException('Use --cert and --key together.');
    }
    if (token.isNotEmpty && token.length < 16) {
      throw const FormatException(
        'The relay token must contain at least 16 characters.',
      );
    }
    if (statePath.isEmpty) {
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      statePath = '$home/.agentlink/relay.json';
    }
    return RelayOptions(
      host: host,
      port: port,
      token: token,
      stateFile: File(statePath),
      certificate: certificate,
      privateKey: privateKey,
      showHelp: showHelp,
    );
  }

  static const usage = '''
AgentLink relay

Usage:
  dart run bin/agentlink_relay.dart [options]

Options:
  --host <address>  Bind address (default: 0.0.0.0)
  --port <port>     WebSocket port (default: 8787)
  --token <token>   Require this token for bridge and phone connections
  --state <path>    Bridge registration state file
  --cert <path>     TLS certificate chain (PEM)
  --key <path>      TLS private key (PEM)
  -h, --help        Show help

Environment:
  AGENTLINK_RELAY_TOKEN   Same as --token
  AGENTLINK_RELAY_STATE   Same as --state

Run this on a small VPS or home server. Put it behind TLS before exposing it
to the public internet, then start each desktop bridge with:
  agentlink-bridge serve --relay wss://relay.example.com:8787
''';
}
