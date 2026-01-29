// Stub used for non-IO platforms (e.g., web). No-ops by design.

Future<String?> readSettingsFile(String fileName) async {
  return null;
}

Future<String?> readSettingsFileAtPath(String path) async {
  return null;
}

Future<void> writeSettingsFile(String fileName, String contents) async {}

Future<void> writeSettingsFileAtPath(String path, String contents) async {}
