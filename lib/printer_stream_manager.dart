import 'package:boomprint/settings_manager.dart';

class PrinterStreamManager {
  /// Gets printer settings from SharedPreferences
  static Future<PrinterSettings> getPrinterSettings() async {
    final settings = await SettingsManager.loadSettings();
    return PrinterSettings(
      printerIp: settings.printerIp,
      accessCode: settings.specialCode,
      serialNumber: settings.serialNumber,
    );
  }

  /// Checks if all required settings are present
  static bool hasValidSettings(PrinterSettings settings) {
    return settings.printerIp.isNotEmpty &&
        settings.accessCode.isNotEmpty &&
        settings.serialNumber.isNotEmpty;
  }

  /// Generates the RTSP stream URL using the Bambu X1C format
  static String generateStreamUrl(PrinterSettings settings) {
    // Using the same format as in printer_url_formats.dart
    return 'rtsps://bblp:${settings.accessCode}@${settings.printerIp}:322/streaming/live/1';
  }

  /// Gets settings and generates URL in one step
  /// Returns null if settings are incomplete
  static Future<String?> getStreamUrl() async {
    final settings = await getPrinterSettings();
    if (hasValidSettings(settings)) {
      return generateStreamUrl(settings);
    }
    return null;
  }
}

class PrinterSettings {
  final String printerIp;
  final String accessCode;
  final String serialNumber;

  PrinterSettings({
    required this.printerIp,
    required this.accessCode,
    required this.serialNumber,
  });

  bool get isValid =>
      printerIp.isNotEmpty && accessCode.isNotEmpty && serialNumber.isNotEmpty;
}
