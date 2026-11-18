import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/bridge_api.dart';
import 'services/settings_store.dart';

enum ConnectionStatus { disconnected, connecting, connected, waiting }

final class AppController extends ChangeNotifier {
  AppController({required this.settingsStore});

  final SettingsStore settingsStore;

  ConnectionProfile? profile;
  BridgeInfo? info;
  BridgeApi? _api;
  ConnectionStatus status = ConnectionStatus.disconnected;
  String? error;
  List<ProviderInfo> providers = const [];
  List<LiveSession> liveSessions = const [];
  List<AgentSession> history = const [];
  bool providersLoading = false;
  bool liveLoading = false;
  bool historyLoading = false;
  bool pairing = false;
  String themeProviderId = AgentProvider.opencode.id;

  Timer? _pollTimer;
  Timer? _retryTimer;
  StreamSubscription<Map<String, dynamic>>? _events;
  var _pollTicks = 0;
  var _liveFailures = 0;
  var _disposed = false;

  bool get hasProfile => profile != null;
  bool get isConnected => status == ConnectionStatus.connected;

  ProviderTheme get theme {
    for (final provider in providers) {
      if (provider.provider.id == themeProviderId && provider.available) {
        return provider.theme;
      }
    }
    for (final provider in providers) {
      if (provider.available) return provider.theme;
    }
    return ProviderTheme.fallback;
  }

  ProviderInfo? providerInfo(AgentProvider provider) {
    for (final item in providers) {
      if (item.provider == provider) return item;
    }
    return null;
  }

  List<LiveSession> get activeSessions =>
      liveSessions.where((session) => session.isActive).toList();

  List<LiveSession> get endedSessions =>
      liveSessions.where((session) => !session.isActive).toList();

  Future<void> initialize() async {
    final saved = await settingsStore.load();
    if (saved == null) {
      _notify();
      return;
    }
    profile = saved;
    await _connectProfile(saved, persist: false);
  }

  Future<bool> pair(PairingPayload payload) async {
    pairing = true;
    error = null;
    status = ConnectionStatus.connecting;
    _notify();
    try {
      final result = await BridgeApi.claim(
        payload,
        deviceName: _deviceName(),
        platform: Platform.isAndroid ? 'android' : Platform.operatingSystem,
      );
      profile = result.profile;
      providers = result.providers;
      await settingsStore.save(result.profile);
      pairing = false;
      _notify();
      return await _connectProfile(result.profile, persist: false);
    } on BridgeException catch (exception) {
      pairing = false;
      status = ConnectionStatus.disconnected;
      error = exception.message;
      _notify();
      return false;
    } on Object catch (exception) {
      pairing = false;
      status = ConnectionStatus.disconnected;
      error = 'Pairing failed: $exception';
      _notify();
      return false;
    }
  }

  Future<bool> retry() async {
    final current = profile;
    if (current == null) return false;
    return _connectProfile(current, persist: false);
  }

  Future<bool> _connectProfile(
    ConnectionProfile value, {
    required bool persist,
  }) async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _events?.cancel();
    _events = null;
    await _api?.close();
    _api = null;
    profile = value;
    status = ConnectionStatus.connecting;
    error = null;
    _notify();

    final api = BridgeApi(value);
    try {
      final connection = await api.connect();
      _api = api;
      if (!connection.online) {
        status = ConnectionStatus.waiting;
        error =
            connection.message ??
            'The desktop is offline. AgentLink will reconnect automatically.';
        _scheduleRetry();
        _notify();
        return false;
      }
      info = connection.info;
      status = ConnectionStatus.connected;
      _liveFailures = 0;
      error = null;
      if (persist) await settingsStore.save(value);
      _listen(api);
      await _loadInitialData();
      _startPolling();
      _notify();
      return true;
    } on BridgeException catch (exception) {
      await api.close();
      _api = null;
      if (exception.isUnauthorized) {
        status = ConnectionStatus.disconnected;
        error =
            'This phone is no longer paired with the PC. '
            'Run "agentlink-bridge reset" on the desktop, then pair again.';
        _notify();
        return false;
      }
      status = ConnectionStatus.waiting;
      error = exception.message;
      _scheduleRetry();
      _notify();
      return false;
    } on Object catch (exception) {
      await api.close();
      _api = null;
      status = ConnectionStatus.waiting;
      error = 'Could not connect to the PC: $exception';
      _scheduleRetry();
      _notify();
      return false;
    }
  }

  Future<void> _loadInitialData() async {
    await Future.wait([refreshProviders(), refreshLive(), refreshHistory()]);
    final available = providers.where((item) => item.available).toList();
    if (available.isNotEmpty &&
        !available.any((item) => item.provider.id == themeProviderId)) {
      themeProviderId = available.first.provider.id;
    }
  }

  void _listen(BridgeApi api) {
    _events = api.events.listen((event) {
      if (_disposed) return;
      switch (event['event']) {
        case 'sessions':
          final body = event['body'];
          if (body is Map && body['sessions'] is List) {
            liveSessions = (body['sessions'] as List)
                .whereType<Map>()
                .map(
                  (item) => LiveSession.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList();
            _notify();
          }
          break;
        case 'bridge':
          final online = event['online'] == true;
          if (online && status == ConnectionStatus.waiting) {
            unawaited(_probe());
          } else if (!online && status == ConnectionStatus.connected) {
            status = ConnectionStatus.waiting;
            error = 'The desktop went offline. Waiting for it to come back…';
            _scheduleRetry();
            _notify();
          }
          break;
      }
    });
  }

  Future<bool> _probe() async {
    final api = _api;
    if (api == null) return false;
    try {
      final connection = await api.probe();
      info = connection.info;
      status = ConnectionStatus.connected;
      error = null;
      _liveFailures = 0;
      await _loadInitialData();
      _startPolling();
      _notify();
      return true;
    } on Object {
      _scheduleRetry();
      return false;
    }
  }

  Future<void> refreshProviders() async {
    final api = _api;
    if (api == null || providersLoading) return;
    providersLoading = true;
    _notify();
    try {
      providers = await api.providers();
      error = null;
    } on BridgeException catch (exception) {
      error = exception.message;
    } finally {
      providersLoading = false;
      _notify();
    }
  }

  Future<void> refreshLive() async {
    final api = _api;
    if (api == null || liveLoading) return;
    liveLoading = true;
    _notify();
    try {
      liveSessions = await api.liveSessions();
      _liveFailures = 0;
      if (status == ConnectionStatus.waiting) {
        status = ConnectionStatus.connected;
        error = null;
      }
    } on BridgeException catch (exception) {
      _liveFailures++;
      if (exception.isOffline || _liveFailures >= 2) {
        status = ConnectionStatus.waiting;
        error = exception.message;
        _scheduleRetry();
      }
    } finally {
      liveLoading = false;
      _notify();
    }
  }

  Future<void> refreshHistory() async {
    final api = _api;
    if (api == null || historyLoading) return;
    historyLoading = true;
    _notify();
    try {
      history = await api.history();
    } on BridgeException catch (exception) {
      error = exception.message;
    } finally {
      historyLoading = false;
      _notify();
    }
  }

  Future<void> refreshAll() async {
    await Future.wait([
      refreshProviders(),
      refreshLive(),
      refreshHistory(),
    ]);
  }

  Future<LiveSession> startSession({
    required AgentProvider provider,
    required String cwd,
    String prompt = '',
    String title = '',
    String resumeSessionId = '',
    required bool openOnDesktop,
  }) async {
    final api = _requireApi();
    final session = await api.startSession(
      provider: provider,
      cwd: cwd,
      prompt: prompt,
      title: title,
      resumeSessionId: resumeSessionId,
      openOnDesktop: openOnDesktop,
    );
    liveSessions = [
      session,
      ...liveSessions.where((item) => item.id != session.id),
    ];
    themeProviderId = provider.id;
    _notify();
    return session;
  }

  Future<void> stopSession(String id) async {
    final api = _requireApi();
    await api.stopSession(id);
    liveSessions = liveSessions
        .map(
          (session) => session.id == id
              ? LiveSession(
                  id: session.id,
                  provider: session.provider,
                  title: session.title,
                  cwd: session.cwd,
                  startedAt: session.startedAt,
                  status: 'stopping',
                  openOnDesktop: session.openOnDesktop,
                  columns: session.columns,
                  rows: session.rows,
                  outputCursor: session.outputCursor,
                  initialPrompt: session.initialPrompt,
                  resumeSessionId: session.resumeSessionId,
                  desktopAttached: session.desktopAttached,
                  desktopTerminal: session.desktopTerminal,
                )
              : session,
        )
        .toList();
    _notify();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 700)).then((_) {
        if (!_disposed) unawaited(refreshLive());
      }),
    );
  }

  Future<LiveSession> restartLiveSession(LiveSession session) async {
    return startSession(
      provider: session.provider,
      cwd: session.cwd,
      prompt: session.initialPrompt ?? '',
      title: session.title,
      resumeSessionId: '',
      openOnDesktop: session.openOnDesktop,
    );
  }

  Future<LiveSession> restartHistorySession(AgentSession session) async {
    return startSession(
      provider: session.provider,
      cwd: session.projectPath,
      prompt: '',
      title: session.title,
      resumeSessionId: '',
      openOnDesktop: info?.openDesktopByDefault ?? true,
    );
  }

  Future<void> renameSession(String id, String title) async {
    final api = _requireApi();
    final updated = await api.renameSession(id, title);
    liveSessions = liveSessions
        .map((session) => session.id == id ? updated : session)
        .toList();
    _notify();
  }

  Future<bool> attachToDesktop(String id) async {
    final api = _requireApi();
    final opened = await api.attachToDesktop(id);
    unawaited(refreshLive());
    return opened;
  }

  Future<TerminalChunk> terminal(
    String id, {
    required int cursor,
    int max = 32768,
  }) async {
    final api = _requireApi();
    return api.terminal(id, cursor: cursor, max: max);
  }

  Future<void> sendInput(String id, {String? text, List<int>? bytes}) async {
    final api = _requireApi();
    await api.sendInput(id, text: text, bytes: bytes);
  }

  Future<void> resizeSession(String id, int columns, int rows) async {
    final api = _requireApi();
    await api.resizeSession(id, columns, rows);
  }

  Future<List<FsRoot>> fsRoots() async => _requireApi().fsRoots();

  Future<FsListing> fsList(String path, {bool showHidden = false}) async =>
      _requireApi().fsList(path, showHidden: showHidden);

  Future<FsEntry> fsMkdir(String path) async => _requireApi().fsMkdir(path);

  Future<SessionDetail> historyDetail(AgentSession session) async =>
      _requireApi().historyDetail(session);

  void selectThemeProvider(AgentProvider provider) {
    if (themeProviderId == provider.id) return;
    themeProviderId = provider.id;
    _notify();
  }

  Future<void> forget() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _events?.cancel();
    _events = null;
    await _api?.close();
    _api = null;
    await settingsStore.clear();
    profile = null;
    info = null;
    providers = const [];
    liveSessions = const [];
    history = const [];
    status = ConnectionStatus.disconnected;
    error = null;
    _notify();
  }

  void clearError() {
    error = null;
    _notify();
  }

  void _scheduleRetry() {
    if (_retryTimer != null || _disposed) return;
    _retryTimer = Timer(const Duration(seconds: 7), () {
      _retryTimer = null;
      if (_disposed || status != ConnectionStatus.waiting) return;
      unawaited(retry());
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTicks = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!isConnected) return;
      _pollTicks++;
      unawaited(refreshLive());
      if (_pollTicks % 10 == 0) unawaited(refreshHistory());
    });
  }

  BridgeApi _requireApi() {
    final api = _api;
    if (api == null || !isConnected) {
      throw const BridgeException(
        'The desktop bridge is not connected right now.',
      );
    }
    return api;
  }

  String _deviceName() {
    try {
      final name = Platform.localHostname.trim();
      if (name.isNotEmpty && name != 'localhost') return name;
    } on Object {
      // Fall through.
    }
    return 'Android device';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _pollTimer?.cancel();
    unawaited(_events?.cancel());
    unawaited(_api?.close());
    super.dispose();
  }
}
