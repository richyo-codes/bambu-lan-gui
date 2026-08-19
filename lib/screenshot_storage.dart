import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Centralizes screenshot storage paths so capture and gallery stay in sync.
class ScreenshotStorage {
  static const String _folderName = 'BoomPrint';
  static const String _subfolderName = 'Screenshots';

  /// Preferred persistent location for new screenshots.
  ///
  /// On desktop and Flatpak, use application documents so screenshots survive
  /// restarts and do not depend on portal or Downloads access.
  static Future<Directory> primaryDirectory() async {
    if (Platform.isAndroid) {
      final base = await getExternalStorageDirectory();
      final root = base ?? await getApplicationDocumentsDirectory();
      return Directory(path.join(root.path, 'Pictures', _folderName, _subfolderName));
    }

    if (Platform.isIOS) {
      final base = await getApplicationDocumentsDirectory();
      return Directory(path.join(base.path, _folderName, _subfolderName));
    }

    final base = await getApplicationDocumentsDirectory();
    return Directory(path.join(base.path, _folderName, _subfolderName));
  }

  /// Legacy locations that may still contain screenshots created by older
  /// builds. The gallery can read from these so existing screenshots do not
  /// disappear after the storage path change.
  static Future<List<Directory>> legacyDirectories() async {
    final dirs = <Directory>[];

    if (Platform.isAndroid) {
      final base = await getExternalStorageDirectory();
      final root = base ?? await getApplicationDocumentsDirectory();
      final documents = await getApplicationDocumentsDirectory();
      dirs.addAll([
        Directory(path.join(root.path, 'Pictures', _folderName, _subfolderName)),
        Directory(path.join(root.path, _folderName, _subfolderName)),
        Directory(path.join(documents.path, _folderName, _subfolderName)),
      ]);
      return _dedupeDirectories(dirs);
    }

    if (Platform.isIOS) {
      final base = await getApplicationDocumentsDirectory();
      dirs.add(Directory(path.join(base.path, _folderName, _subfolderName)));
      return dirs;
    }

    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      dirs.add(Directory(path.join(downloads.path, _folderName, _subfolderName)));
    }
    return dirs;
  }

  /// Returns all directories the gallery should scan, with the preferred
  /// directory first.
  static Future<List<Directory>> galleryDirectories() async {
    final primary = await primaryDirectory();
    final legacy = await legacyDirectories();
    return _dedupeDirectories([primary, ...legacy]);
  }

  static List<Directory> _dedupeDirectories(List<Directory> dirs) {
    final seen = <String>{};
    final result = <Directory>[];
    for (final dir in dirs) {
      final key = path.normalize(dir.path);
      if (seen.add(key)) {
        result.add(dir);
      }
    }
    return result;
  }
}
