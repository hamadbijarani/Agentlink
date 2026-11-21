import 'dart:convert';
import 'dart:io';


class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  static const _repo = 'hamadbijarani/Agentlink';
  static const _apiUrl = 'https://api.github.com/repos/$_repo/releases/latest';

  Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(_apiUrl));
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(systemEncoding.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tagName = json['tag_name']?.toString() ?? '';
      final latestVersion = tagName.replaceFirst('v', '');
      final downloadUrl = json['assets'] is List
          ? (json['assets'] as List)
              .whereType<Map>()
              .map((a) => a['browser_download_url']?.toString())
              .firstWhere((u) => u != null && u.endsWith('.apk'), orElse: () => null)
          : null;
      final releaseNotes = json['body']?.toString() ?? '';
      if (_isNewer(latestVersion, currentVersion)) {
        return UpdateInfo(
          version: latestVersion,
          downloadUrl: downloadUrl,
          releaseNotes: releaseNotes,
        );
      }
      return null;
    } on Exception {
      return null;
    }
  }

  bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }
}

class UpdateInfo {
  UpdateInfo({
    required this.version,
    this.downloadUrl,
    this.releaseNotes = '',
  });

  final String version;
  final String? downloadUrl;
  final String releaseNotes;
}
