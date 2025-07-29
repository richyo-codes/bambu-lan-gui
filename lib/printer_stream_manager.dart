import 'package:shared_preferences/shared_preferences.dart';

class PrinterStreamManager {
  /// Gets printer settings from SharedPreferences
  static Future<PrinterSettings> getPrinterSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return PrinterSettings(
      printerIp: prefs.getString('rtsp_printerip') ?? '',
      accessCode: prefs.getString('rtsp_specialcode') ?? '',
      serialNumber: prefs.getString('rtsp_serial_number') ?? '',
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
