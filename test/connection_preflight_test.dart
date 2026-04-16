import 'dart:io';

import 'package:boomprint/connection_preflight.dart';
import 'package:boomprint/printer_url_formats.dart';
import 'package:boomprint/settings_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preflight marks required ports reachable and FTP optional', () async {
    final mqttServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      8883,
    );
    final streamServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      322,
    );
    addTearDown(() async {
      await mqttServer.close();
      await streamServer.close();
    });

    final settings = AppSettings(
      specialCode: '12345678',
      printerIp: '127.0.0.1',
      serialNumber: '00M000000000000',
      selectedFormat: PrinterUrlType.bambuX1C,
      customUrl: '',
    );

    final summary = await ConnectionPreflight.run(
      settings: settings,
      streamUrl: ConnectionPreflight.buildStreamUrl(settings),
      timeout: const Duration(seconds: 1),
    );

    expect(summary.hasRequiredFailures, isFalse);
    expect(summary.results.length, 3);
    expect(summary.requiredFailures, isEmpty);
    expect(summary.optionalFailures, hasLength(1));

    final stream = summary.results.firstWhere((r) => r.label == 'Stream');
    final mqtt = summary.results.firstWhere((r) => r.label == 'MQTT');
    final ftp = summary.results.firstWhere((r) => r.label == 'FTP/FTPS');

    expect(stream.isReachable, isTrue);
    expect(mqtt.isReachable, isTrue);
    expect(ftp.isReachable, isFalse);
    expect(ftp.required, isFalse);
  });
}
