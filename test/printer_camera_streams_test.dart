import 'package:boomprint/connection_preflight.dart';
import 'package:boomprint/printer_camera_streams.dart';
import 'package:boomprint/printer_url_formats.dart';
import 'package:boomprint/settings_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds multiple built-in camera streams for X2D', () {
    final settings = AppSettings(
      specialCode: '12345678',
      printerIp: '192.168.1.50',
      serialNumber: '00M000000000000',
      selectedFormat: PrinterUrlType.bambuX2D,
      customUrl: '',
    );

    final streams = buildPrinterCameraStreams(settings);

    expect(streams, hasLength(2));
    expect(streams[0].label, 'Camera 1');
    expect(streams[1].label, 'Camera 2');
    expect(
      streams[0].url,
      'rtsps://bblp:12345678@192.168.1.50:322/streaming/live/1',
    );
    expect(
      streams[1].url,
      'rtsps://bblp:12345678@192.168.1.50:322/streaming/live/2',
    );
  });

  test('Bambu stream URL uses the selected camera index when provided', () {
    final settings = AppSettings(
      specialCode: '12345678',
      printerIp: '192.168.1.50',
      serialNumber: '00M000000000000',
      selectedFormat: PrinterUrlType.bambuX2D,
      customUrl: '',
      selectedCameraIndex: 1,
    );

    expect(
      ConnectionPreflight.buildStreamUrl(settings),
      'rtsps://bblp:12345678@192.168.1.50:322/streaming/live/2',
    );
  });
}
