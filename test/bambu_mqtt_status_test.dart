import 'package:boomprint/bambu_lan.dart';
import 'package:boomprint/bambu_mqtt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mqtt = BambuMqtt(
    const BambuLanConfig(
      printerIp: '192.168.1.50',
      accessCode: '12345678',
      serial: '00M000000000000',
    ),
  );

  test('parses print faults, HMS events, and AMS trays', () {
    final status = mqtt.parsePrintStatus({
      'print': {
        'gcode_state': 'PAUSE',
        'stg_cur': 6,
        'print_error': 12,
        'reason': 'Filament ran out',
        'hms': [
          {'code': 0x03000900, 'attr': 0x00020002},
        ],
        'ams': {
          'tray_now': '1',
          'tray_tar': '2',
          'ams': [
            {
              'tray': [
                {
                  'id': '0',
                  'tray_type': 'PLA Basic',
                  'tray_color': 'FF0000FF',
                  'remain': 83,
                },
                {
                  'id': '1',
                  'tray_type': 'PETG',
                  'tray_id_name': 'Blue PETG',
                  'tray_color': '0000FFFF',
                  'remain': 42,
                },
              ],
            },
          ],
        },
      },
    });

    expect(status, isNotNull);
    expect(status!.hasPrinterFault, isTrue);
    expect(status.printError, 12);
    expect(status.printerMessage, 'Filament ran out');
    expect(status.hms.single.displayCode, '0300-0900-0002-0002');
    expect(status.hms.single.wikiUrl, contains('0300_0900_0002_0002'));
    expect(status.filamentTrays, hasLength(2));
    expect(status.activeFilament?.type, 'PETG');
    expect(status.targetTrayIndex, 2);
  });

  test('recognizes an explicit empty HMS list as no active fault', () {
    final status = mqtt.parsePrintStatus({
      'print': {'gcode_state': 'RUNNING', 'hms': [], 'print_error': 0},
    });

    expect(status, isNotNull);
    expect(status!.hasHmsReport, isTrue);
    expect(status.hms, isEmpty);
    expect(status.hasPrinterFault, isFalse);
  });

  test('accepts only valid filament remaining percentages', () {
    final status = mqtt.parsePrintStatus({
      'print': {
        'ams': {
          'ams': [
            {
              'tray': [
                {'id': '0', 'remain': '-1'},
                {'id': '1', 'remain': 255},
                {'id': '2', 'remain': '45.5'},
              ],
            },
          ],
        },
      },
    });

    expect(status, isNotNull);
    expect(status!.filamentTrays.map((tray) => tray.remainingPercent), [
      isNull,
      isNull,
      46,
    ]);
  });
}
