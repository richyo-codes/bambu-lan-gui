import 'connection_preflight.dart';
import 'printer_url_formats.dart';
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
  final count = settings.selectedFormat.isBambuFamily
      ? (settings.cameraStreamCount < settings.selectedFormat.defaultCameraCount
            ? settings.selectedFormat.defaultCameraCount
            : settings.cameraStreamCount)
      : 1;

  return List.generate(count, (i) {
    final cameraNumber = i + 1;
    final label = count == 1 ? 'Camera' : 'Camera $cameraNumber';
    return PrinterCameraStream(
      index: i,
      label: label,
      url: ConnectionPreflight.buildStreamUrl(
        settings,
        cameraIndex: cameraNumber,
      ),
    );
  });
}
