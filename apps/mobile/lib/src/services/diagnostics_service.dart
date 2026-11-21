import 'dart:collection';

/// Simple in-memory diagnostic log for the mobile app.
class DiagnosticsService {
  DiagnosticsService._();
  static final instance = DiagnosticsService._();

  static const int _maxEntries = 500;
  final _entries = Queue<DiagnosticEntry>();

  List<DiagnosticEntry> get entries => _entries.toList();

  void log(String level, String message, {String? tag}) {
    _entries.addLast(DiagnosticEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      tag: tag,
    ));
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
  }

  void info(String message, {String? tag}) => log('INFO', message, tag: tag);
  void warn(String message, {String? tag}) => log('WARN', message, tag: tag);
  void error(String message, {String? tag}) => log('ERROR', message, tag: tag);
  void debug(String message, {String? tag}) => log('DEBUG', message, tag: tag);

  void clear() => _entries.clear();

  String export() => _entries.map((e) => e.toString()).join('\n');
}

class DiagnosticEntry {
  DiagnosticEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.tag,
  });

  final DateTime timestamp;
  final String level;
  final String message;
  final String? tag;

  @override
  String toString() =>
      '[${timestamp.toIso8601String()}] [$level] ${tag != null ? '[$tag] ' : ''}$message';
}
