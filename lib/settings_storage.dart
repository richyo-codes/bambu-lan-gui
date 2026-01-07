// Stub used for non-IO platforms (e.g., web). No-ops by design.

Future<String?> readSettingsFile(String fileName) async {
  return null;
}

Future<void> writeSettingsFile(String fileName, String contents) async {}

