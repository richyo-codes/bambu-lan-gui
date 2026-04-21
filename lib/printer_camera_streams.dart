import 'printer_profile.dart';
import 'settings_manager.dart';

class PrinterCameraStream {
  final int index;
  final String label;
  final String url;

  const PrinterCameraStream({
    required this.index,
    required this.label,
    required this.url,
  });
}

List<PrinterCameraStream> buildPrinterCameraStreams(AppSettings settings) {
  final profile = PrinterProfile.fromLocalPrinterFields(
    id: 'active',
    displayName: 'Active printer',
    printerType: settings.selectedFormat,
    printerIp: settings.printerIp,
    serialNumber: settings.serialNumber,
    accessCode: settings.specialCode,
    customUrl: settings.customUrl,
    cameraStreamCount: settings.cameraStreamCount,
    selectedCameraIndex: settings.selectedCameraIndex,
    genericRtspUsername: settings.genericRtspUsername,
    genericRtspPassword: settings.genericRtspPassword,
    genericRtspPath: settings.genericRtspPath,
    genericRtspPort: settings.genericRtspPort,
    genericRtspSecure: settings.genericRtspSecure,
  );

  final cameraUrls = profile.cameraUrls;
  return cameraUrls
      .asMap()
      .entries
      .map((entry) {
        final record = entry.value;
        return PrinterCameraStream(
          index: entry.key,
          label: record.label,
          url: record.url,
        );
      })
      .toList(growable: false);
}
