import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'util.dart';

final class FsException implements Exception {
  const FsException(this.message, {this.status = 400});

  final String message;
  final int status;

  @override
  String toString() => message;
}

final class FileService {
  FileService({String? home}) : home = home ?? homeDirectory();

  final String home;
  static const int maxEntries = 3000;
  static const int maxReadBytes = 512 * 1024;

  List<FsRoot> roots() {
    final roots = <FsRoot>[
      FsRoot(label: 'Home', path: home, kind: 'home'),
    ];
    if (Platform.isWindows) {
      for (final drive in _windowsDrives()) {
        roots.add(FsRoot(label: drive, path: drive, kind: 'drive'));
      }
      return roots;
    }
    final candidates = <(String, String, String)>[
      ('Desktop', '$home/Desktop', 'desktop'),
      ('Documents', '$home/Documents', 'documents'),
      ('Downloads', '$home/Downloads', 'downloads'),
      ('Projects', '$home/Projects', 'projects'),
      ('Code', '$home/code', 'projects'),
      ('Workspace', '$home/workspace', 'projects'),
    ];
    for (final candidate in candidates) {
      if (Directory(candidate.$2).existsSync()) {
        roots.add(
          FsRoot(label: candidate.$1, path: candidate.$2, kind: candidate.$3),
        );
      }
    }
    roots.add(
      const FsRoot(label: 'Filesystem', path: '/', kind: 'filesystem'),
    );
    return roots;
  }

  Future<FsListing> list({
    required String path,
    required bool showHidden,
  }) async {
    final directory = _resolveDirectory(path);
    if (!await directory.exists()) {
      throw const FsException('Directory not found.', status: 404);
    }
    final entries = <FsEntry>[];
    var truncated = false;
    try {
      await for (final entity in directory.list(followLinks: false)) {
        final name = _basename(entity.path);
        if (!showHidden && name.startsWith('.')) continue;
        if (name.isEmpty) continue;
        var isLink = false;
        var isDirectory = entity is Directory;
        if (entity is Link) {
          isLink = true;
          try {
            isDirectory =
                await FileSystemEntity.isDirectory(entity.path);
          } on FileSystemException {
            isDirectory = false;
          }
        }
        int? size;
        DateTime? modifiedAt;
        try {
          final stat = await entity.stat();
          modifiedAt = stat.modified;
          if (!isDirectory) size = stat.size;
        } on FileSystemException {
          // Keep the entry even if its metadata is temporarily unreadable.
        }
        entries.add(
          FsEntry(
            name: name,
            path: entity.path,
            isDirectory: isDirectory,
            isHidden: name.startsWith('.'),
            isLink: isLink,
            size: size,
            modifiedAt: modifiedAt,
          ),
        );
        if (entries.length >= maxEntries) {
          truncated = true;
          break;
        }
      }
    } on FileSystemException catch (error) {
      throw FsException(
        'Could not read this directory: ${error.osError?.message ?? error.message}',
        status: 403,
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    final parent = directory.parent.path == directory.path
        ? null
        : directory.parent.path;
    return FsListing(
      path: directory.path,
      parent: parent,
      entries: entries,
      truncated: truncated,
    );
  }

  Future<Map<String, Object?>> read({
    required String path,
    int? maxBytes,
  }) async {
    final file = File(_absolute(path));
    if (!await file.exists()) {
      throw const FsException('File not found.', status: 404);
    }
    final limit = (maxBytes ?? maxReadBytes).clamp(1024, maxReadBytes);
    final stat = await file.stat();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, limit + 1)) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final truncated = bytes.length > limit;
    final data = truncated ? bytes.sublist(0, limit) : bytes;
    final binary = data.take(4096).any((byte) => byte == 0);
    if (binary) {
      return {
        'path': file.absolute.path,
        'size': stat.size,
        'binary': true,
        'truncated': truncated,
        'content': '',
      };
    }
    return {
      'path': file.absolute.path,
      'size': stat.size,
      'binary': false,
      'truncated': truncated,
      'content': utf8.decode(data, allowMalformed: true),
    };
  }

  Future<FsEntry> mkdir(String path) async {
    final clean = path.trim();
    if (clean.isEmpty) {
      throw const FsException('A directory path is required.');
    }
    final directory = Directory(_absolute(clean));
    if (await directory.exists()) {
      throw const FsException('That directory already exists.', status: 409);
    }
    try {
      await directory.create(recursive: false);
      final stat = await directory.stat();
      return FsEntry(
        name: _basename(directory.path),
        path: directory.path,
        isDirectory: true,
        isHidden: _basename(directory.path).startsWith('.'),
        modifiedAt: stat.modified,
      );
    } on FileSystemException catch (error) {
      throw FsException(
        'Could not create the directory: ${error.osError?.message ?? error.message}',
        status: 403,
      );
    }
  }

  Directory _resolveDirectory(String path) {
    final clean = path.trim();
    if (clean.isEmpty) return Directory(home);
    final directory = Directory(_absolute(clean));
    return directory;
  }

  String _absolute(String path) {
    if (path == '~') return home;
    if (path.startsWith('~/') || path.startsWith('~\\')) {
      return '$home${path.substring(1)}';
    }
    return Directory(path).absolute.path;
  }

  String _basename(String path) {
    final normalized = path.endsWith(Platform.pathSeparator)
        ? path.substring(0, path.length - 1)
        : path;
    final index = normalized.lastIndexOf(Platform.pathSeparator);
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  Iterable<String> _windowsDrives() sync* {
    for (var code = 65; code <= 90; code++) {
      final letter = String.fromCharCode(code);
      final path = '$letter:\\';
      if (Directory(path).existsSync()) yield path;
    }
  }
}
