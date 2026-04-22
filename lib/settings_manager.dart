import 'dart:convert';

import 'printer_url_formats.dart';
import 'settings_storage.dart' if (dart.library.io) 'settings_storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_secure_storage.dart';

class AppSettings {
  String specialCode;
  String printerIp;
  String serialNumber;
  PrinterUrlType selectedFormat;
  String customUrl;
  int cameraStreamCount;
  int selectedCameraIndex;
  String genericRtspUsername;
  String genericRtspPassword;
  String genericRtspPath;
  int genericRtspPort;
  bool genericRtspSecure;
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
    this.cameraStreamCount = 1,
    this.selectedCameraIndex = 0,
    this.genericRtspUsername = '',
    this.genericRtspPassword = '',
    this.genericRtspPath = '/stream',
    this.genericRtspPort = 554,
    this.genericRtspSecure = false,
    this.autoConnect = false,
    this.mqttControlsEnabled = false,
    this.lightControlsEnabled = false,
    this.hardwareAccelerationEnabled = true,
    this.linuxUseSystemWindowDecorations = false,
  });

  static AppSettings normalizeCameraFields(AppSettings settings) {
    if (!settings.selectedFormat.isBambuFamily) {
      settings.cameraStreamCount = 1;
      settings.selectedCameraIndex = 0;
      return settings;
    }

    final count =
        settings.cameraStreamCount < settings.selectedFormat.defaultCameraCount
        ? settings.selectedFormat.defaultCameraCount
        : settings.cameraStreamCount;
    settings.cameraStreamCount = count;
    if (settings.selectedCameraIndex < 0) {
      settings.selectedCameraIndex = 0;
    }
    if (settings.selectedCameraIndex >= count) {
      settings.selectedCameraIndex = count - 1;
    }
    return settings;
  }

  // JSON serialization
  Map<String, dynamic> toJson() => {
    'specialCode': specialCode,
    'printerIp': printerIp,
    'serialNumber': serialNumber,
    'selectedFormat': selectedFormat.storageKey,
    'customUrl': customUrl,
    'cameraStreamCount': cameraStreamCount,
    'selectedCameraIndex': selectedCameraIndex,
    'genericRtspUsername': genericRtspUsername,
    'genericRtspPassword': genericRtspPassword,
    'genericRtspPath': genericRtspPath,
    'genericRtspPort': genericRtspPort,
    'genericRtspSecure': genericRtspSecure,
    'autoConnect': autoConnect,
    'mqttControlsEnabled': mqttControlsEnabled,
    'lightControlsEnabled': lightControlsEnabled,
    'hardwareAccelerationEnabled': hardwareAccelerationEnabled,
    'linuxUseSystemWindowDecorations': linuxUseSystemWindowDecorations,
  };

  Map<String, dynamic> toPersistentJson() => {
    'specialCode': '',
    'printerIp': printerIp,
    'serialNumber': serialNumber,
    'selectedFormat': selectedFormat.storageKey,
    'customUrl': '',
    'cameraStreamCount': cameraStreamCount,
    'selectedCameraIndex': selectedCameraIndex,
    'genericRtspUsername': genericRtspUsername,
    'genericRtspPassword': '',
    'genericRtspPath': genericRtspPath,
    'genericRtspPort': genericRtspPort,
    'genericRtspSecure': genericRtspSecure,
    'autoConnect': autoConnect,
    'mqttControlsEnabled': mqttControlsEnabled,
    'lightControlsEnabled': lightControlsEnabled,
    'hardwareAccelerationEnabled': hardwareAccelerationEnabled,
    'linuxUseSystemWindowDecorations': linuxUseSystemWindowDecorations,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return normalizeCameraFields(
      AppSettings(
        specialCode: (json['specialCode'] ?? '') as String,
        printerIp: (json['printerIp'] ?? '') as String,
        serialNumber: (json['serialNumber'] ?? '') as String,
        selectedFormat: PrinterUrlTypeX.parse(
          json['selectedFormat'] as String? ?? 'Bambu X1C',
        ),
        customUrl: (json['customUrl'] ?? '') as String,
        cameraStreamCount: (json['cameraStreamCount'] is int)
            ? json['cameraStreamCount'] as int
            : int.tryParse('${json['cameraStreamCount'] ?? ''}') ?? 1,
        selectedCameraIndex: (json['selectedCameraIndex'] is int)
            ? json['selectedCameraIndex'] as int
            : int.tryParse('${json['selectedCameraIndex'] ?? ''}') ?? 0,
        genericRtspUsername: (json['genericRtspUsername'] ?? '') as String,
        genericRtspPassword: (json['genericRtspPassword'] ?? '') as String,
        genericRtspPath: (json['genericRtspPath'] ?? '/stream') as String,
        genericRtspPort: (json['genericRtspPort'] is int)
            ? json['genericRtspPort'] as int
            : int.tryParse('${json['genericRtspPort'] ?? ''}') ?? 554,
        genericRtspSecure: (json['genericRtspSecure'] ?? false) as bool,
        autoConnect: (json['autoConnect'] ?? false) as bool,
        mqttControlsEnabled: (json['mqttControlsEnabled'] ?? false) as bool,
        lightControlsEnabled: (json['lightControlsEnabled'] ?? false) as bool,
        hardwareAccelerationEnabled:
            (json['hardwareAccelerationEnabled'] ?? true) as bool,
        linuxUseSystemWindowDecorations:
            (json['linuxUseSystemWindowDecorations'] ?? false) as bool,
      ),
    );
  }

  static AppSettings fromPrefs(SharedPreferences prefs) {
    return normalizeCameraFields(
      AppSettings(
        specialCode: prefs.getString('rtsp_specialcode') ?? '',
        printerIp: prefs.getString('rtsp_printerip') ?? '',
        serialNumber: prefs.getString('rtsp_serial_number') ?? '',
        selectedFormat: PrinterUrlTypeX.parse(
          prefs.getString('rtsp_format') ?? 'Bambu X1C',
        ),
        customUrl: prefs.getString('rtsp_custom_url') ?? '',
        cameraStreamCount: prefs.getInt('rtsp_camera_stream_count') ?? 1,
        selectedCameraIndex: prefs.getInt('rtsp_selected_camera_index') ?? 0,
        genericRtspUsername: prefs.getString('rtsp_generic_username') ?? '',
        genericRtspPassword: prefs.getString('rtsp_generic_password') ?? '',
        genericRtspPath: prefs.getString('rtsp_generic_path') ?? '/stream',
        genericRtspPort: prefs.getInt('rtsp_generic_port') ?? 554,
        genericRtspSecure: prefs.getBool('rtsp_generic_secure') ?? false,
        autoConnect: prefs.getBool('rtsp_auto_connect') ?? false,
        mqttControlsEnabled:
            prefs.getBool('rtsp_mqtt_controls_enabled') ?? false,
        lightControlsEnabled:
            prefs.getBool('rtsp_light_controls_enabled') ?? false,
        hardwareAccelerationEnabled:
            prefs.getBool('rtsp_hardware_acceleration_enabled') ?? true,
        linuxUseSystemWindowDecorations:
            prefs.getBool('rtsp_linux_use_system_window_decorations') ?? false,
      ),
    );
  }

  Future<void> saveToPrefs({bool scrubSensitiveValues = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (scrubSensitiveValues) {
      await prefs.remove('rtsp_specialcode');
    } else {
      await prefs.setString('rtsp_specialcode', specialCode);
    }
    await prefs.setString('rtsp_printerip', printerIp);
    await prefs.setString('rtsp_serial_number', serialNumber);
    await prefs.setString('rtsp_format', selectedFormat.storageKey);
    if (scrubSensitiveValues) {
      await prefs.remove('rtsp_custom_url');
    } else {
      await prefs.setString('rtsp_custom_url', customUrl);
    }
    await prefs.setInt('rtsp_camera_stream_count', cameraStreamCount);
    await prefs.setInt('rtsp_selected_camera_index', selectedCameraIndex);
    await prefs.setString('rtsp_generic_username', genericRtspUsername);
    if (scrubSensitiveValues) {
      await prefs.remove('rtsp_generic_password');
    } else {
      await prefs.setString('rtsp_generic_password', genericRtspPassword);
    }
    await prefs.setString('rtsp_generic_path', genericRtspPath);
    await prefs.setInt('rtsp_generic_port', genericRtspPort);
    await prefs.setBool('rtsp_generic_secure', genericRtspSecure);
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

  static const _jsonFileName = 'boomprint_settings.json';
  static const _legacyJsonFileName = 'rtsp_settings.json';

  static Future<void> _saveToJsonFile(
    AppSettings settings, {
    bool scrubSensitiveValues = true,
  }) async {
    try {
      final jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(
        scrubSensitiveValues ? settings.toPersistentJson() : settings.toJson(),
      );
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
      await _saveToJsonFile(settings, scrubSensitiveValues: false);
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

  static Future<AppSettings> _hydrateSensitiveFields(
    AppSettings base, {
    SharedPreferences? prefs,
  }) async {
    final secure = await SettingsSecureStorage.readSnapshot();
    final legacyPrefs = prefs ?? await SharedPreferences.getInstance();

    final specialCode = secure.specialCode?.isNotEmpty == true
        ? secure.specialCode!
        : base.specialCode.isNotEmpty
        ? base.specialCode
        : (legacyPrefs.getString('rtsp_specialcode') ?? '');
    final genericRtspPassword = secure.genericRtspPassword?.isNotEmpty == true
        ? secure.genericRtspPassword!
        : base.genericRtspPassword.isNotEmpty
        ? base.genericRtspPassword
        : (legacyPrefs.getString('rtsp_generic_password') ?? '');
    final customUrl = secure.customUrl?.isNotEmpty == true
        ? secure.customUrl!
        : base.customUrl.isNotEmpty
        ? base.customUrl
        : (legacyPrefs.getString('rtsp_custom_url') ?? '');

    await SettingsSecureStorage.writeSnapshot(
      specialCode: specialCode,
      genericRtspPassword: genericRtspPassword,
      customUrl: customUrl,
    );

    return AppSettings.normalizeCameraFields(
      AppSettings(
        specialCode: specialCode,
        printerIp: base.printerIp,
        serialNumber: base.serialNumber,
        selectedFormat: base.selectedFormat,
        customUrl: customUrl,
        cameraStreamCount: base.cameraStreamCount,
        selectedCameraIndex: base.selectedCameraIndex,
        genericRtspUsername: base.genericRtspUsername,
        genericRtspPassword: genericRtspPassword,
        genericRtspPath: base.genericRtspPath,
        genericRtspPort: base.genericRtspPort,
        genericRtspSecure: base.genericRtspSecure,
        autoConnect: base.autoConnect,
        mqttControlsEnabled: base.mqttControlsEnabled,
        lightControlsEnabled: base.lightControlsEnabled,
        hardwareAccelerationEnabled: base.hardwareAccelerationEnabled,
        linuxUseSystemWindowDecorations: base.linuxUseSystemWindowDecorations,
      ),
    );
  }

  static AppSettings _applyOverrides(
    AppSettings base, {
    String? specialCode,
    String? printerIp,
    String? serialNumber,
    String? selectedFormat,
    String? customUrl,
    int? cameraStreamCount,
    int? selectedCameraIndex,
    String? genericRtspUsername,
    String? genericRtspPassword,
    String? genericRtspPath,
    int? genericRtspPort,
    bool? genericRtspSecure,
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
      cameraStreamCount: cameraStreamCount ?? base.cameraStreamCount,
      selectedCameraIndex: selectedCameraIndex ?? base.selectedCameraIndex,
      genericRtspUsername: genericRtspUsername?.isNotEmpty == true
          ? genericRtspUsername!
          : base.genericRtspUsername,
      genericRtspPassword: genericRtspPassword?.isNotEmpty == true
          ? genericRtspPassword!
          : base.genericRtspPassword,
      genericRtspPath: genericRtspPath?.isNotEmpty == true
          ? genericRtspPath!
          : base.genericRtspPath,
      genericRtspPort: genericRtspPort ?? base.genericRtspPort,
      genericRtspSecure: genericRtspSecure ?? base.genericRtspSecure,
      autoConnect: autoConnect ?? base.autoConnect,
      mqttControlsEnabled: mqttControlsEnabled ?? base.mqttControlsEnabled,
      lightControlsEnabled: lightControlsEnabled ?? base.lightControlsEnabled,
      hardwareAccelerationEnabled:
          hardwareAccelerationEnabled ?? base.hardwareAccelerationEnabled,
      linuxUseSystemWindowDecorations:
          linuxUseSystemWindowDecorations ??
          base.linuxUseSystemWindowDecorations,
    );
    AppSettings.normalizeCameraFields(next);
    if (customUrl != null && customUrl.trim().isNotEmpty) {
      return AppSettings.normalizeCameraFields(
        AppSettings(
          specialCode: next.specialCode,
          printerIp: next.printerIp,
          serialNumber: next.serialNumber,
          selectedFormat: PrinterUrlType.custom,
          customUrl: next.customUrl,
          cameraStreamCount: next.cameraStreamCount,
          selectedCameraIndex: next.selectedCameraIndex,
          genericRtspUsername: next.genericRtspUsername,
          genericRtspPassword: next.genericRtspPassword,
          genericRtspPath: next.genericRtspPath,
          genericRtspPort: next.genericRtspPort,
          genericRtspSecure: next.genericRtspSecure,
          autoConnect: next.autoConnect,
          mqttControlsEnabled: next.mqttControlsEnabled,
          lightControlsEnabled: next.lightControlsEnabled,
          hardwareAccelerationEnabled: next.hardwareAccelerationEnabled,
          linuxUseSystemWindowDecorations: next.linuxUseSystemWindowDecorations,
        ),
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
    int? overrideCameraStreamCount,
    int? overrideSelectedCameraIndex,
    String? overrideGenericRtspUsername,
    String? overrideGenericRtspPassword,
    String? overrideGenericRtspPath,
    int? overrideGenericRtspPort,
    bool? overrideGenericRtspSecure,
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
      final hydrated = await _hydrateSensitiveFields(fromFile);
      _cachedSettings = _applyOverrides(
        hydrated,
        specialCode: overrideSpecialCode,
        printerIp: overridePrinterIp,
        serialNumber: overrideSerialNumber,
        selectedFormat: overrideSelectedFormat,
        customUrl: overrideCustomUrl,
        cameraStreamCount: overrideCameraStreamCount,
        selectedCameraIndex: overrideSelectedCameraIndex,
        genericRtspUsername: overrideGenericRtspUsername,
        genericRtspPassword: overrideGenericRtspPassword,
        genericRtspPath: overrideGenericRtspPath,
        genericRtspPort: overrideGenericRtspPort,
        genericRtspSecure: overrideGenericRtspSecure,
        autoConnect: overrideAutoConnect,
        mqttControlsEnabled: overrideMqttControlsEnabled,
        lightControlsEnabled: overrideLightControlsEnabled,
        hardwareAccelerationEnabled: overrideHardwareAccelerationEnabled,
        linuxUseSystemWindowDecorations:
            overrideLinuxUseSystemWindowDecorations,
      );
      final secureWriteSucceeded = await SettingsSecureStorage.writeSnapshot(
        specialCode: _cachedSettings!.specialCode,
        genericRtspPassword: _cachedSettings!.genericRtspPassword,
        customUrl: _cachedSettings!.customUrl,
      );
      await _cachedSettings!.saveToPrefs(
        scrubSensitiveValues: secureWriteSucceeded,
      );
      await _saveToJsonFile(
        _cachedSettings!,
        scrubSensitiveValues: secureWriteSucceeded,
      );
      return _cachedSettings!;
    }

    final prefs = await SharedPreferences.getInstance();
    final hydratedPrefs = await _hydrateSensitiveFields(
      AppSettings.fromPrefs(prefs),
      prefs: prefs,
    );
    _cachedSettings = _applyOverrides(
      hydratedPrefs,
      specialCode: overrideSpecialCode,
      printerIp: overridePrinterIp,
      serialNumber: overrideSerialNumber,
      selectedFormat: overrideSelectedFormat,
      customUrl: overrideCustomUrl,
      cameraStreamCount: overrideCameraStreamCount,
      selectedCameraIndex: overrideSelectedCameraIndex,
      genericRtspUsername: overrideGenericRtspUsername,
      genericRtspPassword: overrideGenericRtspPassword,
      genericRtspPath: overrideGenericRtspPath,
      genericRtspPort: overrideGenericRtspPort,
      genericRtspSecure: overrideGenericRtspSecure,
      autoConnect: overrideAutoConnect,
      mqttControlsEnabled: overrideMqttControlsEnabled,
      lightControlsEnabled: overrideLightControlsEnabled,
      hardwareAccelerationEnabled: overrideHardwareAccelerationEnabled,
      linuxUseSystemWindowDecorations: overrideLinuxUseSystemWindowDecorations,
    );
    return _cachedSettings!;
  }

  static AppSettings get settings => _cachedSettings!;

  static Future<void> saveSettings(AppSettings settings) async {
    _cachedSettings = settings;
    final secureWriteSucceeded = await SettingsSecureStorage.writeSnapshot(
      specialCode: settings.specialCode,
      genericRtspPassword: settings.genericRtspPassword,
      customUrl: settings.customUrl,
    );
    await settings.saveToPrefs(scrubSensitiveValues: secureWriteSucceeded);
    await _saveToJsonFile(
      settings,
      scrubSensitiveValues: secureWriteSucceeded,
    );
  }

  static void updateSettings(void Function(AppSettings) updater) {
    if (_cachedSettings != null) {
      updater(_cachedSettings!);
    }
  }
}
