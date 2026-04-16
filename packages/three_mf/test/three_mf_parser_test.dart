import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:three_mf/three_mf.dart';

Uint8List _encodeArchive(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

Future<ThreeMfProjectInfo?> _parseCase(Map<String, String> files) {
  return const ThreeMfParser().parseBytes(_encodeArchive(files));
}

void main() {
  group('ThreeMfParser', () {
    test('parses combined project metadata', () async {
      final info = await _parseCase({
        'Metadata/project_settings.config': '''
<?xml version="1.0" encoding="UTF-8"?>
<config>
  <project name="Calibration Cube" printer_profile="Bambu X1C" />
  <filament slot="1" filament_type="PETG" filament_name="Bambu PETG Basic" filament_color="FF0000FF" />
</config>
''',
        'Metadata/plate_1.gcode': '''
; plate_name = Top Plate
; filament_type = PETG
; filament_name = Bambu PETG Basic
; nozzle_diameter = 0.4
; printer_profile = Bambu X1C
G1 X0 Y0
''',
      });

      expect(info, isNotNull);
      expect(info!.projectName, 'Calibration Cube');
      expect(info.printerProfile, 'Bambu X1C');
      expect(info.plates, hasLength(1));
      expect(info.plates.first.index, 1);
      expect(info.plates.first.name, 'Top Plate');
      expect(info.filamentHints, anyElement(contains('Bambu PETG Basic')));
      expect(info.compatibilityWarningFor('AMS 1 / Slot 0 • PETG'), isNull);
      expect(info.compatibilityWarningFor('PLA'), isNotNull);
    });

    test('parses plate comments without project xml', () async {
      final info = await _parseCase({
        'Metadata/plate_1.gcode': '''
; plate_name = Draft Plate
; filament_type = PLA
; filament_name = Generic PLA
; nozzle_diameter = 0.4
G1 X10 Y10
''',
      });

      expect(info, isNotNull);
      expect(info!.projectName, isNull);
      expect(info.plates, hasLength(1));
      expect(info.plates.first.filamentHints, contains('PLA'));
      expect(info.warnings, isEmpty);
    });

    test('returns metadata warnings for incomplete archives', () async {
      final info = await _parseCase({
        'Metadata/project_settings.config': '''
<?xml version="1.0" encoding="UTF-8"?>
<config>
  <project name="Calibration Cube" printer_profile="Bambu X1C" />
  <filament slot="1" filament_type="PETG" filament_name="Bambu PETG Basic" />
</config>
''',
      });

      expect(info, isNotNull);
      expect(info!.projectName, 'Calibration Cube');
      expect(info.plates, isEmpty);
      expect(info.filaments, isNotEmpty);
      expect(
        info.warnings,
        contains('No plate-specific G-code was found in the 3MF archive.'),
      );
    });
  });
}
