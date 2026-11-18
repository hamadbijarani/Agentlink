import 'dart:convert';
import 'dart:io';
import 'dart:math';

final class TokenStore {
  TokenStore({File? file}) : file = file ?? _defaultFile();

  final File file;

  Future<String> loadOrCreate() async {
    if (await file.exists()) {
      final existing = (await file.readAsString()).trim();
      if (existing.length >= 16) return existing;
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    await file.parent.create(recursive: true);
    await file.writeAsString('$token\n', flush: true);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } on ProcessException {
        // Best effort; the token never leaves the local configuration directory.
      }
    }
    return token;
  }

  static File _defaultFile() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return File('$home/.agentlink/bridge_token');
  }
}
