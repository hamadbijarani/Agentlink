import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

const appVersion = '1.0.0';
const appBuild = '2026.11';

final Random _random = Random.secure();

String randomToken([int bytes = 32]) {
  final data = List<int>.generate(bytes, (_) => _random.nextInt(256));
  return base64Url.encode(data).replaceAll('=', '');
}

String randomId([int bytes = 9]) {
  const alphabet = '0123456789abcdefghjkmnpqrstvwxyz';
  final data = List<int>.generate(bytes, (_) => _random.nextInt(256));
  final buffer = StringBuffer();
  for (var index = 0; index < data.length; index++) {
    buffer.write(alphabet[data[index] % alphabet.length]);
  }
  return buffer.toString();
}

String sha256Hex(String value) =>
    sha256.convert(utf8.encode(value)).toString();

bool constantTimeEquals(String? left, String? right) {
  if (left == null || right == null) return false;
  final a = utf8.encode(left);
  final b = utf8.encode(right);
  var diff = a.length ^ b.length;
  final max = a.length > b.length ? a.length : b.length;
  for (var index = 0; index < max; index++) {
    final av = index < a.length ? a[index] : 0;
    final bv = index < b.length ? b[index] : 0;
    diff |= av ^ bv;
  }
  return diff == 0;
}

String nowIso() => DateTime.now().toUtc().toIso8601String();

String hostname() {
  try {
    return Platform.localHostname;
  } on Object {
    return 'desktop';
  }
}

String homeDirectory() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null && home.isNotEmpty) return home;
  return Directory.current.path;
}

/// Extra directories frequently used by Node, Python, Bun, Cargo and local
/// agent installers. A bridge started from a desktop launcher often has a much
/// smaller PATH than the user's login shell.
String enrichedPath([String? existing]) {
  final current = existing ?? Platform.environment['PATH'] ?? '';
  final home = homeDirectory();
  final separator = Platform.isWindows ? ';' : ':';
  final extras = <String>[
    if (Platform.isWindows) ...[
      '$home\\AppData\\Roaming\\npm',
      '$home\\AppData\\Local\\Programs',
    ] else ...[
      '$home/.local/bin',
      '$home/.npm-global/bin',
      '$home/.bun/bin',
      '$home/.cargo/bin',
      '$home/.deno/bin',
      '$home/.local/share/pnpm',
      '/usr/local/bin',
      '/opt/homebrew/bin',
    ],
  ];
  final entries = <String>[
    ...current.split(separator).where((value) => value.isNotEmpty),
    ...extras,
  ];
  final seen = <String>{};
  return entries.where((entry) => seen.add(entry)).join(separator);
}

String? findExecutable(String command, {String? path}) {
  if (command.contains('/') || command.contains('\\')) {
    final file = File(command);
    return file.existsSync() ? file.path : null;
  }
  final searchPath = path ?? enrichedPath();
  final separator = Platform.isWindows ? ';' : ':';
  final extensions = Platform.isWindows
      ? (Platform.environment['PATHEXT'] ?? '.EXE;.CMD;.BAT')
            .split(';')
            .where((value) => value.isNotEmpty)
            .toList()
      : const <String>[''];
  for (final directory in searchPath.split(separator)) {
    if (directory.isEmpty) continue;
    for (final extension in extensions) {
      final candidate = File(
        '$directory${Platform.pathSeparator}$command$extension',
      );
      if (candidate.existsSync()) return candidate.path;
    }
  }
  return null;
}

String? executableVersion(String executable) {
  try {
    final result = Process.runSync(executable, [
      '--version',
    ], environment: {'PATH': enrichedPath()}).stdout.toString().trim();
    if (result.isEmpty) return null;
    final firstLine = result.split('\n').first.trim();
    return firstLine.length <= 80 ? firstLine : firstLine.substring(0, 77);
  } on Object {
    return null;
  }
}

bool isSafeSessionToken(String value) =>
    RegExp(r'^[A-Za-z0-9_.:-]{1,200}$').hasMatch(value);

int? queryInt(Map<String, String> query, String key, {int? fallback}) {
  final value = query[key];
  if (value == null) return fallback;
  return int.tryParse(value) ?? fallback;
}

bool queryBool(Map<String, String> query, String key, {bool fallback = false}) {
  final value = query[key]?.toLowerCase();
  if (value == null) return fallback;
  return value == '1' || value == 'true' || value == 'yes';
}

String bodyString(Object? body, String key, {String fallback = ''}) {
  if (body is Map) {
    final value = body[key];
    if (value == null) return fallback;
    return value.toString();
  }
  return fallback;
}

bool bodyBool(Object? body, String key, {bool fallback = false}) {
  if (body is Map) {
    final value = body[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      return value == '1' || value.toLowerCase() == 'true';
    }
  }
  return fallback;
}

int? bodyInt(Object? body, String key) {
  if (body is Map) {
    final value = body[key];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
  }
  return null;
}

String clampText(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);

String relativePathLabel(String path, String home) {
  if (path == home) return '~';
  final prefix = home.endsWith(Platform.pathSeparator)
      ? home
      : '$home${Platform.pathSeparator}';
  if (path.startsWith(prefix)) return '~${path.substring(home.length)}';
  return path;
}
