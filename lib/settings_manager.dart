import 'dart:convert';

import 'printer_url_formats.dart';
import 'settings_storage.dart'
    if (dart.library.io) 'settings_storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  String specialCode;
  String printerIp;
  String serialNumber;
  PrinterUrlType selectedFormat;
  String customUrl;

  AppSettings({
    required this.specialCode,
    required this.printerIp,
    required this.serialNumber,
    required this.selectedFormat,
    required this.customUrl,
  });

  // JSON serialization
  Map<String, dynamic> toJson() => {
        'specialCode': specialCode,
        'printerIp': printerIp,
        'serialNumber': serialNumber,
        'selectedFormat': selectedFormat.storageKey,
        'customUrl': customUrl,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      specialCode: (json['specialCode'] ?? '') as String,
      printerIp: (json['printerIp'] ?? '') as String,
      serialNumber: (json['serialNumber'] ?? '') as String,
      selectedFormat:
          PrinterUrlTypeX.parse(json['selectedFormat'] as String? ?? 'Bambu X1C'),
      customUrl: (json['customUrl'] ?? '') as String,
    );
  }

  static AppSettings fromPrefs(SharedPreferences prefs) {
    return AppSettings(
      specialCode: prefs.getString('rtsp_specialcode') ?? '',
      printerIp: prefs.getString('rtsp_printerip') ?? '',
      serialNumber: prefs.getString('rtsp_serial_number') ?? '',
      selectedFormat:
          PrinterUrlTypeX.parse(prefs.getString('rtsp_format') ?? 'Bambu X1C'),
      customUrl: prefs.getString('rtsp_custom_url') ?? '',
    );
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rtsp_specialcode', specialCode);
    await prefs.setString('rtsp_printerip', printerIp);
    await prefs.setString('rtsp_serial_number', serialNumber);
    await prefs.setString('rtsp_format', selectedFormat.storageKey);
    await prefs.setString('rtsp_custom_url', customUrl);
  }
}

class SettingsManager {
  static AppSettings? _cachedSettings;

  static const _jsonFileName = 'rtsp_settings.json';

  static Future<void> _saveToJsonFile(AppSettings settings) async {
    try {
      final jsonString =
          const JsonEncoder.withIndent('  ').convert(settings.toJson());
      await writeSettingsFile(_jsonFileName, jsonString);
    } catch (_) {
      // Silently ignore file I/O errors to avoid disrupting app flow.
    }
  }

  static Future<AppSettings?> _loadFromJsonFile() async {
    try {
      final jsonString = await readSettingsFile(_jsonFileName);
      if (jsonString == null) return null;
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      return AppSettings.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static Future<AppSettings> loadSettings() async {
    if (_cachedSettings != null) return _cachedSettings!;

    // Prefer JSON file if present; fall back to SharedPreferences
    final fromFile = await _loadFromJsonFile();
    if (fromFile != null) {
      _cachedSettings = fromFile;
      // Keep SharedPreferences in sync
      await fromFile.saveToPrefs();
      return _cachedSettings!;
    }

    final prefs = await SharedPreferences.getInstance();
    _cachedSettings = AppSettings.fromPrefs(prefs);
    return _cachedSettings!;
  }

  static AppSettings get settings => _cachedSettings!;

  static Future<void> saveSettings(AppSettings settings) async {
    _cachedSettings = settings;
    await settings.saveToPrefs();
    await _saveToJsonFile(settings);
  }

  static void updateSettings(void Function(AppSettings) updater) {
    if (_cachedSettings != null) {
      updater(_cachedSettings!);
    }
  }
}
