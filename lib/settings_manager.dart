import 'dart:convert';

import 'printer_url_formats.dart';
import 'settings_storage.dart' if (dart.library.io) 'settings_storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  String specialCode;
  String printerIp;
  String serialNumber;
  PrinterUrlType selectedFormat;
  String customUrl;
  bool autoConnect;
  bool mqttControlsEnabled;
  bool lightControlsEnabled;
  bool hardwareAccelerationEnabled;
  bool linuxUseSystemWindowDecorations;

  AppSettings({
    required this.specialCode,
    required this.printerIp,
    required this.serialNumber,
    required this.selectedFormat,
    required this.customUrl,
    this.autoConnect = false,
    this.mqttControlsEnabled = false,
    this.lightControlsEnabled = false,
    this.hardwareAccelerationEnabled = true,
    this.linuxUseSystemWindowDecorations = false,
  });

  // JSON serialization
  Map<String, dynamic> toJson() => {
    'specialCode': specialCode,
    'printerIp': printerIp,
    'serialNumber': serialNumber,
    'selectedFormat': selectedFormat.storageKey,
    'customUrl': customUrl,
    'autoConnect': autoConnect,
    'mqttControlsEnabled': mqttControlsEnabled,
    'lightControlsEnabled': lightControlsEnabled,
    'hardwareAccelerationEnabled': hardwareAccelerationEnabled,
    'linuxUseSystemWindowDecorations': linuxUseSystemWindowDecorations,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      specialCode: (json['specialCode'] ?? '') as String,
      printerIp: (json['printerIp'] ?? '') as String,
      serialNumber: (json['serialNumber'] ?? '') as String,
      selectedFormat: PrinterUrlTypeX.parse(
        json['selectedFormat'] as String? ?? 'Bambu X1C',
      ),
      customUrl: (json['customUrl'] ?? '') as String,
      autoConnect: (json['autoConnect'] ?? false) as bool,
      mqttControlsEnabled: (json['mqttControlsEnabled'] ?? false) as bool,
      lightControlsEnabled: (json['lightControlsEnabled'] ?? false) as bool,
      hardwareAccelerationEnabled:
          (json['hardwareAccelerationEnabled'] ?? true) as bool,
      linuxUseSystemWindowDecorations:
          (json['linuxUseSystemWindowDecorations'] ?? false) as bool,
    );
  }

  static AppSettings fromPrefs(SharedPreferences prefs) {
    return AppSettings(
      specialCode: prefs.getString('rtsp_specialcode') ?? '',
      printerIp: prefs.getString('rtsp_printerip') ?? '',
      serialNumber: prefs.getString('rtsp_serial_number') ?? '',
      selectedFormat: PrinterUrlTypeX.parse(
        prefs.getString('rtsp_format') ?? 'Bambu X1C',
      ),
      customUrl: prefs.getString('rtsp_custom_url') ?? '',
      autoConnect: prefs.getBool('rtsp_auto_connect') ?? false,
      mqttControlsEnabled: prefs.getBool('rtsp_mqtt_controls_enabled') ?? false,
      lightControlsEnabled:
          prefs.getBool('rtsp_light_controls_enabled') ?? false,
      hardwareAccelerationEnabled:
          prefs.getBool('rtsp_hardware_acceleration_enabled') ?? true,
      linuxUseSystemWindowDecorations:
          prefs.getBool('rtsp_linux_use_system_window_decorations') ?? false,
    );
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rtsp_specialcode', specialCode);
    await prefs.setString('rtsp_printerip', printerIp);
    await prefs.setString('rtsp_serial_number', serialNumber);
    await prefs.setString('rtsp_format', selectedFormat.storageKey);
    await prefs.setString('rtsp_custom_url', customUrl);
    await prefs.setBool('rtsp_auto_connect', autoConnect);
    await prefs.setBool('rtsp_mqtt_controls_enabled', mqttControlsEnabled);
    await prefs.setBool('rtsp_light_controls_enabled', lightControlsEnabled);
    await prefs.setBool(
      'rtsp_hardware_acceleration_enabled',
      hardwareAccelerationEnabled,
    );
    await prefs.setBool(
      'rtsp_linux_use_system_window_decorations',
      linuxUseSystemWindowDecorations,
    );
  }
}

class SettingsManager {
  static AppSettings? _cachedSettings;

  static const _jsonFileName = 'bambu_lan_settings.json';
  static const _legacyJsonFileName = 'rtsp_settings.json';

  static Future<void> _saveToJsonFile(AppSettings settings) async {
    try {
      final jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(settings.toJson());
      await writeSettingsFile(_jsonFileName, jsonString);
    } catch (_) {
      // Silently ignore file I/O errors to avoid disrupting app flow.
    }
  }

  static Future<AppSettings?> _loadFromJsonFile() async {
    try {
      var jsonString = await readSettingsFile(_jsonFileName);
      if (jsonString == null) {
        // Backward-compatible fallback for old app versions.
        jsonString = await readSettingsFile(_legacyJsonFileName);
        if (jsonString == null) return null;
      }
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final settings = AppSettings.fromJson(data);
      // Ensure legacy reads migrate to the new file name.
      await _saveToJsonFile(settings);
      return settings;
    } catch (_) {
      return null;
    }
  }

  static Future<AppSettings?> _loadFromJsonFilePath(String path) async {
    try {
      final jsonString = await readSettingsFileAtPath(path);
      if (jsonString == null) return null;
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      return AppSettings.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static AppSettings _applyOverrides(
    AppSettings base, {
    String? specialCode,
    String? printerIp,
    String? serialNumber,
    String? selectedFormat,
    String? customUrl,
    bool? autoConnect,
    bool? mqttControlsEnabled,
    bool? lightControlsEnabled,
    bool? hardwareAccelerationEnabled,
    bool? linuxUseSystemWindowDecorations,
  }) {
    final next = AppSettings(
      specialCode: specialCode?.isNotEmpty == true
          ? specialCode!
          : base.specialCode,
      printerIp: printerIp?.isNotEmpty == true ? printerIp! : base.printerIp,
      serialNumber: serialNumber?.isNotEmpty == true
          ? serialNumber!
          : base.serialNumber,
      selectedFormat: selectedFormat != null && selectedFormat.trim().isNotEmpty
          ? PrinterUrlTypeX.parse(selectedFormat)
          : base.selectedFormat,
      customUrl: customUrl?.isNotEmpty == true ? customUrl! : base.customUrl,
      autoConnect: autoConnect ?? base.autoConnect,
      mqttControlsEnabled: mqttControlsEnabled ?? base.mqttControlsEnabled,
      lightControlsEnabled: lightControlsEnabled ?? base.lightControlsEnabled,
      hardwareAccelerationEnabled:
          hardwareAccelerationEnabled ?? base.hardwareAccelerationEnabled,
      linuxUseSystemWindowDecorations:
          linuxUseSystemWindowDecorations ??
          base.linuxUseSystemWindowDecorations,
    );
    if (customUrl != null && customUrl.trim().isNotEmpty) {
      return AppSettings(
        specialCode: next.specialCode,
        printerIp: next.printerIp,
        serialNumber: next.serialNumber,
        selectedFormat: PrinterUrlType.custom,
        customUrl: next.customUrl,
        autoConnect: next.autoConnect,
        mqttControlsEnabled: next.mqttControlsEnabled,
        lightControlsEnabled: next.lightControlsEnabled,
        hardwareAccelerationEnabled: next.hardwareAccelerationEnabled,
        linuxUseSystemWindowDecorations:
            next.linuxUseSystemWindowDecorations,
      );
    }
    return next;
  }

  static Future<AppSettings> loadSettings({
    String? overridePath,
    String? overrideSpecialCode,
    String? overridePrinterIp,
    String? overrideSerialNumber,
    String? overrideSelectedFormat,
    String? overrideCustomUrl,
    bool? overrideAutoConnect,
    bool? overrideMqttControlsEnabled,
    bool? overrideLightControlsEnabled,
    bool? overrideHardwareAccelerationEnabled,
    bool? overrideLinuxUseSystemWindowDecorations,
  }) async {
    if (_cachedSettings != null) return _cachedSettings!;

    // Prefer explicit file if provided; else use app-managed file.
    final fromFile = overridePath != null && overridePath.trim().isNotEmpty
        ? await _loadFromJsonFilePath(overridePath.trim())
        : await _loadFromJsonFile();
    if (fromFile != null) {
      _cachedSettings = _applyOverrides(
        fromFile,
        specialCode: overrideSpecialCode,
        printerIp: overridePrinterIp,
        serialNumber: overrideSerialNumber,
        selectedFormat: overrideSelectedFormat,
        customUrl: overrideCustomUrl,
        autoConnect: overrideAutoConnect,
        mqttControlsEnabled: overrideMqttControlsEnabled,
        lightControlsEnabled: overrideLightControlsEnabled,
        hardwareAccelerationEnabled: overrideHardwareAccelerationEnabled,
        linuxUseSystemWindowDecorations:
            overrideLinuxUseSystemWindowDecorations,
      );
      // Keep SharedPreferences in sync
      await _cachedSettings!.saveToPrefs();
      return _cachedSettings!;
    }

    final prefs = await SharedPreferences.getInstance();
    _cachedSettings = _applyOverrides(
      AppSettings.fromPrefs(prefs),
      specialCode: overrideSpecialCode,
      printerIp: overridePrinterIp,
      serialNumber: overrideSerialNumber,
      selectedFormat: overrideSelectedFormat,
      customUrl: overrideCustomUrl,
      autoConnect: overrideAutoConnect,
      mqttControlsEnabled: overrideMqttControlsEnabled,
      lightControlsEnabled: overrideLightControlsEnabled,
      hardwareAccelerationEnabled: overrideHardwareAccelerationEnabled,
      linuxUseSystemWindowDecorations:
          overrideLinuxUseSystemWindowDecorations,
    );
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
