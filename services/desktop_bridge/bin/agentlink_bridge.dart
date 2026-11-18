import 'dart:async';
import 'dart:io';

import 'package:agentlink_desktop_bridge/agentlink_desktop_bridge.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    await _serve(const []);
    return;
  }
  final command = arguments.first;
  final rest = arguments.sublist(1);
  switch (command) {
    case 'serve':
    case 'pair':
      await _serve(rest);
    case 'reset':
      await _reset();
    case 'status':
      await _status();
    case 'config':
      await _config(rest);
    case 'attach':
      await _attach(rest);
    case 'help':
    case '--help':
    case '-h':
      stdout.writeln(_usage);
    case '--version':
      stdout.writeln('AgentLink bridge $appVersion');
    default:
      if (command.startsWith('-')) {
        await _serve(arguments);
      } else {
        stderr.writeln('Unknown command: $command\n\n$_usage');
        exitCode = 64;
      }
  }
}

Future<void> _serve(List<String> arguments) async {
  final options = _ServeOptions.parse(arguments);
  if (options.showHelp) {
    stdout.writeln(_serveUsage);
    return;
  }
  final store = ConfigStore();
  await store.loadOrCreate();
  var config = store.current;
  if (options.name != null) {
    config = await store.configure(name: options.name);
  }
  if (options.clearRelay) {
    config = await store.configure(clearRelay: true);
  } else if (options.relayUrl != null) {
    config = await store.configure(
      relayUrl: options.relayUrl,
      relayToken: options.relayToken ?? config.relayToken,
    );
  } else if (options.relayToken != null) {
    config = await store.configure(relayToken: options.relayToken);
  }
  if (options.httpHost != null || options.httpPort != null) {
    config = await store.configure(
      httpHost: options.httpHost,
      httpPort: options.httpPort,
    );
  }
  if (options.openDesktop != null) {
    config = await store.configure(
      openDesktopByDefault: options.openDesktop,
    );
  }

  final providers = ProviderRegistry();
  final files = FileService();
  final launcher = DesktopLauncher(configStore: store);
  final manager = SessionManager(
    providers: providers,
    desktopOpener: (session) => launcher.open(session),
  );
  late final AgentLinkBridge bridge;
  final router = BridgeRouter(
    configStore: store,
    providers: providers,
    sessions: manager,
    files: files,
    relayStatus: () => bridge.relayStatus,
  );
  bridge = AgentLinkBridge(
    configStore: store,
    router: router,
    sessionManager: manager,
    launcher: launcher,
    enableHttp: !options.noHttp,
    enableRelay: !options.noRelay,
  );

  try {
    await bridge.start();
  } on SocketException catch (error) {
    stderr.writeln(
      'Could not start the bridge on ${config.httpHost}:${config.httpPort}: '
      '${error.osError?.message ?? error.message}',
    );
    exitCode = 1;
    return;
  }

  unawaited(
    providers.ensureReady().catchError((Object error) {
      stderr.writeln('Provider check failed: $error');
      return <ProviderInfo>[];
    }),
  );

  var closing = false;
  Future<void> shutdown() async {
    if (closing) return;
    closing = true;
    stdout.writeln('\nStopping AgentLink bridge…');
    await bridge.close();
    await manager.dispose();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => unawaited(shutdown()));
  ProcessSignal.sigterm.watch().listen((_) => unawaited(shutdown()));

  stdout.writeln('');
  stdout.writeln('AgentLink desktop bridge is ready.');
  stdout.writeln('Name:    ${config.name}');
  stdout.writeln('Bridge:  ${config.bridgeId}');
  stdout.writeln('Config:  ${store.file.path}');
  if (bridge.httpEnabled) {
    final endpoints = await _httpEndpoints(config, bridge.boundPort!);
    if (endpoints.isEmpty) {
      stdout.writeln('HTTP:    http://127.0.0.1:${bridge.boundPort} (local only)');
    } else {
      stdout.writeln('LAN:     ${endpoints.join('  ')}');
    }
  } else {
    stdout.writeln('HTTP:    disabled (relay only; desktop terminal windows are off)');
  }
  if (config.relayUrl.isNotEmpty && !options.noRelay) {
    stdout.writeln('Relay:   ${config.relayUrl} (connecting…)');
  } else {
    stdout.writeln('Relay:   disabled');
  }
  stdout.writeln('');

  if (config.isPaired) {
    final device = config.device!;
    stdout.writeln(
      'Paired with ${device.name} (${device.platform}) since ${device.pairedAt}.',
    );
    stdout.writeln(
      'This PC accepts only this phone. To change phones: stop the bridge, '
      'run "agentlink-bridge reset", then start it again.',
    );
  } else {
    final secret = config.pairingSecret;
    if (secret == null || secret.isEmpty) {
      stderr.writeln('No pairing secret is available. Run "agentlink-bridge reset".');
    } else {
      final lan = await discoverLanAddresses();
      final payload = buildPairingPayload(
        config,
        httpHost: config.httpHost,
        httpPort: bridge.boundPort ?? config.httpPort,
        lanAddresses: lan,
      );
      if (options.noQr) {
        stdout.writeln('Pairing link: ${payload.encode()}');
      } else {
        stdout.writeln(
          pairingSummary(payload, bridgeId: config.bridgeId),
        );
      }
      if (config.relayUrl.isEmpty && payload.endpoints.isEmpty) {
        stdout.writeln(
          'No relay and no LAN address were found. Start with '
          '"--relay wss://your-relay" or bind to a LAN address with --lan.',
        );
      }
    }
  }
  if (!bridge.httpEnabled && config.relayUrl.isEmpty) {
    stderr.writeln(
      'The phone cannot connect: HTTP is disabled and no relay is configured.',
    );
  }
  if (config.relayUrl.startsWith('ws://') && !config.relayUrl.contains('localhost')) {
    stderr.writeln(
      'Warning: the relay uses ws:// without TLS. Use wss:// before exposing it to the internet.',
    );
  }
  stdout.writeln('');
  stdout.writeln('Press Ctrl+C to stop.');
}

Future<void> _reset() async {
  final store = ConfigStore();
  await store.loadOrCreate();
  await store.resetDevice();
  stdout.writeln('Pairing reset. The previous phone token is now invalid.');
  stdout.writeln('Start the bridge (or restart it if it is already running)');
  stdout.writeln('to show a new QR code: agentlink-bridge serve');
}

Future<void> _status() async {
  final store = ConfigStore();
  final config = await store.loadOrCreate();
  stdout.writeln('AgentLink desktop bridge $appVersion');
  stdout.writeln('Name:    ${config.name}');
  stdout.writeln('Bridge:  ${config.bridgeId}');
  stdout.writeln('Config:  ${store.file.path}');
  stdout.writeln(
    'HTTP:    ${config.httpHost}:${config.httpPort}',
  );
  stdout.writeln(
    'Relay:   ${config.relayUrl.isEmpty ? 'disabled' : config.relayUrl}',
  );
  if (config.isPaired) {
    final device = config.device!;
    stdout.writeln(
      'Paired:  ${device.name} (${device.platform}), ${device.pairedAt}',
    );
  } else {
    stdout.writeln('Paired:  no (pairing is open while the bridge is running)');
  }
}

Future<void> _config(List<String> arguments) async {
  final store = ConfigStore();
  await store.loadOrCreate();
  String? relayUrl;
  String? relayToken;
  String? name;
  String? host;
  int? port;
  bool? openDesktop;
  var clearRelay = false;
  var showHelp = false;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    String value() {
      if (index + 1 >= arguments.length) {
        throw FormatException('Missing value after $argument');
      }
      return arguments[++index];
    }

    switch (argument) {
      case '--relay':
        relayUrl = value();
      case '--relay-token':
        relayToken = value();
      case '--no-relay':
        clearRelay = true;
      case '--name':
        name = value();
      case '--host':
        host = value();
      case '--port':
        port = int.parse(value());
      case '--open-desktop':
        openDesktop = true;
      case '--no-open-desktop':
        openDesktop = false;
      case '--help':
      case '-h':
        showHelp = true;
      default:
        throw FormatException('Unknown config option: $argument');
    }
  }
  if (showHelp || arguments.isEmpty) {
    stdout.writeln(_configUsage);
    return;
  }
  if (relayUrl != null && !relayUrl.startsWith('ws://') && !relayUrl.startsWith('wss://')) {
    throw const FormatException('The relay URL must start with ws:// or wss://.');
  }
  if (port != null && (port < 1 || port > 65535)) {
    throw const FormatException('Port must be between 1 and 65535.');
  }
  final config = await store.configure(
    name: name,
    relayUrl: relayUrl,
    relayToken: relayToken,
    clearRelay: clearRelay,
    httpHost: host,
    httpPort: port,
    openDesktopByDefault: openDesktop,
  );
  stdout.writeln('Configuration saved to ${store.file.path}.');
  stdout.writeln('Restart the bridge to apply changes.');
  stdout.writeln('Relay: ${config.relayUrl.isEmpty ? 'disabled' : config.relayUrl}');
  stdout.writeln('HTTP:  ${config.httpHost}:${config.httpPort}');
  stdout.writeln('Desktop windows: ${config.openDesktopByDefault}');
}

Future<void> _attach(List<String> arguments) async {
  String? sessionId;
  String? endpointValue;
  String? token;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    String value() {
      if (index + 1 >= arguments.length) {
        throw FormatException('Missing value after $argument');
      }
      return arguments[++index];
    }

    switch (argument) {
      case '--session':
        sessionId = value();
      case '--endpoint':
        endpointValue = value();
      case '--token':
        token = value();
      case '--help':
      case '-h':
        stdout.writeln(_attachUsage);
        return;
      default:
        if (argument.startsWith('-')) {
          throw FormatException('Unknown attach option: $argument');
        }
        sessionId ??= argument;
    }
  }
  sessionId ??= Platform.environment['AGENTLINK_SESSION_ID'];
  if (sessionId == null || sessionId.isEmpty) {
    stderr.writeln('A session id is required.\n\n$_attachUsage');
    exitCode = 64;
    return;
  }
  final store = ConfigStore();
  await store.loadOrCreate();
  final config = store.current;
  endpointValue ??= Platform.environment['AGENTLINK_ENDPOINT'];
  token ??= Platform.environment['AGENTLINK_ATTACH_TOKEN'];
  endpointValue ??= 'http://127.0.0.1:${config.httpPort}';
  token ??= config.localAttachToken;
  final uri = Uri.tryParse(endpointValue);
  if (uri == null || !uri.hasScheme) {
    stderr.writeln('Invalid endpoint: $endpointValue');
    exitCode = 64;
    return;
  }
  await AttachClient(
    endpoint: uri,
    token: token,
    sessionId: sessionId,
  ).run();
}

Future<List<String>> _httpEndpoints(BridgeConfig config, int port) async {
  if (config.httpHost == '0.0.0.0' ||
      config.httpHost == '::' ||
      config.httpHost == '[::]') {
    final lan = await discoverLanAddresses();
    return lan.map((address) => 'http://$address:$port').toList();
  }
  if (config.httpHost == '127.0.0.1' || config.httpHost == 'localhost') {
    return const [];
  }
  final host = config.httpHost.contains(':')
      ? '[${config.httpHost}]'
      : config.httpHost;
  return ['http://$host:$port'];
}

final class _ServeOptions {
  _ServeOptions({
    required this.relayUrl,
    required this.relayToken,
    required this.clearRelay,
    required this.name,
    required this.httpHost,
    required this.httpPort,
    required this.openDesktop,
    required this.noQr,
    required this.noHttp,
    required this.noRelay,
    required this.showHelp,
  });

  final String? relayUrl;
  final String? relayToken;
  final bool clearRelay;
  final String? name;
  final String? httpHost;
  final int? httpPort;
  final bool? openDesktop;
  final bool noQr;
  final bool noHttp;
  final bool noRelay;
  final bool showHelp;

  static _ServeOptions parse(List<String> arguments) {
    String? relayUrl;
    String? relayToken;
    var clearRelay = false;
    String? name;
    String? httpHost;
    int? httpPort;
    bool? openDesktop;
    var noQr = false;
    var noHttp = false;
    var noRelay = false;
    var showHelp = false;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      String value() {
        if (index + 1 >= arguments.length) {
          throw FormatException('Missing value after $argument');
        }
        return arguments[++index];
      }

      switch (argument) {
        case '--relay':
          relayUrl = value();
        case '--relay-token':
          relayToken = value();
        case '--no-relay':
          clearRelay = true;
        case '--name':
          name = value();
        case '--host':
          httpHost = value();
        case '--port':
          httpPort = int.parse(value());
        case '--lan':
          httpHost = '0.0.0.0';
        case '--local':
          httpHost = '127.0.0.1';
        case '--desktop':
          openDesktop = true;
        case '--no-desktop':
          openDesktop = false;
        case '--no-qr':
          noQr = true;
        case '--no-http':
          noHttp = true;
        case '--no-relay-connect':
          noRelay = true;
        case '--help':
        case '-h':
          showHelp = true;
        default:
          throw FormatException('Unknown option: $argument\n\n$_serveUsage');
      }
    }
    if (httpPort != null && (httpPort < 1 || httpPort > 65535)) {
      throw const FormatException('Port must be between 1 and 65535.');
    }
    if (relayUrl != null &&
        !relayUrl.startsWith('ws://') &&
        !relayUrl.startsWith('wss://')) {
      throw const FormatException(
        'The relay URL must start with ws:// or wss://.',
      );
    }
    return _ServeOptions(
      relayUrl: relayUrl,
      relayToken: relayToken,
      clearRelay: clearRelay,
      name: name,
      httpHost: httpHost,
      httpPort: httpPort,
      openDesktop: openDesktop,
      noQr: noQr,
      noHttp: noHttp,
      noRelay: noRelay,
      showHelp: showHelp,
    );
  }
}

const _usage = '''
AgentLink desktop bridge

Usage:
  agentlink-bridge serve [options]    Start the bridge and, if needed, a pairing QR
  agentlink-bridge pair [options]     Same as serve
  agentlink-bridge status             Show pairing and relay configuration
  agentlink-bridge reset              Forget the paired phone and open pairing
  agentlink-bridge config [options]   Update relay/HTTP/desktop settings
  agentlink-bridge attach [id]        Attach a desktop terminal to a live session
  agentlink-bridge --help             Show this help

Quick start:
  1. On a server, run agentlink-relay (behind TLS).
  2. On the PC, run:
       agentlink-bridge serve --relay wss://relay.example.com
  3. Scan the QR code with the Android app.
  4. The app can browse directories, start agent CLIs, and control them.

The bridge keeps agent processes, credentials, and session files on this PC.
Only one phone can be paired at a time. Run "agentlink-bridge reset" to unpair.
''';

const _serveUsage = '''
AgentLink bridge serve options

  --relay <wss://url>     Relay WebSocket URL (saved to config)
  --relay-token <token>   Relay access token (saved to config)
  --no-relay              Clear the saved relay
  --no-relay-connect      Do not connect to the relay this run
  --host <address>        HTTP bind address (default: 0.0.0.0)
  --lan                   Bind HTTP to 0.0.0.0 (LAN direct access)
  --local                 Bind HTTP to 127.0.0.1 only
  --port <port>           HTTP port (default: 7331)
  --no-http               Relay-only mode (disables desktop terminal windows)
  --name <name>           Friendly PC name shown in the app
  --no-desktop            Do not open a desktop terminal for new sessions
  --desktop               Open a desktop terminal for new sessions
  --no-qr                 Print the pairing link instead of the QR
  -h, --help              Show this help

The first start without a paired phone prints a QR code. It contains a
one-time pairing secret and never contains your agent credentials.
''';

const _configUsage = '''
AgentLink bridge config options

  --relay <wss://url>     Set the relay URL
  --relay-token <token>   Set the relay access token
  --no-relay              Disable the relay
  --name <name>           Friendly PC name
  --host <address>        HTTP bind address
  --port <port>           HTTP port
  --open-desktop          Open a desktop terminal for new sessions
  --no-open-desktop       Do not open desktop terminal windows
''';

const _attachUsage = '''
AgentLink desktop attach

Usage:
  agentlink-bridge attach <session-id> [--endpoint http://127.0.0.1:7331]
  agentlink-bridge attach --session <id> [--token <local-token>]

Normally the bridge opens this automatically in a desktop terminal. Press
Ctrl+] to detach without stopping the agent; the session keeps running and
the phone remains in control.
''';
