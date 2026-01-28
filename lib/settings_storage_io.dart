import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> readSettingsFile(String fileName) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$fileName');
    if (!await file.exists()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

Future<String?> readSettingsFileAtPath(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

Future<void> writeSettingsFile(String fileName, String contents) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$fileName');
    await file.create(recursive: true);
    await file.writeAsString(contents, flush: true);
  } catch (_) {
    // ignore
  }
}

Future<void> writeSettingsFileAtPath(String path, String contents) async {
  try {
    final file = File(path);
    await file.create(recursive: true);
    await file.writeAsString(contents, flush: true);
  } catch (_) {
    // ignore
  }
}
