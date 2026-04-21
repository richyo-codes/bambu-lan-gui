import 'package:boomprint/printer_firmware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts firmware version from nested printer report json', () {
    final firmware = extractFirmwareVersion({
      'system': {
        'info': {'firmware_version': '01.07.02.00'},
      },
    });

    expect(firmware, '01.07.02.00');
  });

  test('flags firmware older than the minimum supported baseline', () {
    final warning = evaluateFirmwareWarning('01.07.02.00');

    expect(warning, isNotNull);
    expect(warning!.message, contains('older than the recommended baseline'));
  });

  test('does not warn for newer firmware versions', () {
    final warning = evaluateFirmwareWarning('01.08.00.00');

    expect(warning, isNull);
  });
}
