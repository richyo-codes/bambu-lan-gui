import 'package:boomprint/help_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog includes a firmware help entry', () {
    final entries = HelpCatalog.findByText('firmware update');

    expect(entries, isNotEmpty);
    expect(entries.first.id, 'firmware-release-notes');
    expect(entries.first.links, isNotEmpty);
  });

  test('catalog resolves unauthorized MQTT help by code and text', () {
    final byCode = HelpCatalog.firstMatch(code: '401');
    final byText = HelpCatalog.firstMatch(
      text: 'check special code / credentials',
    );

    expect(byCode?.id, 'mqtt-unauthorized');
    expect(byText?.id, 'mqtt-unauthorized');
  });

  test('catalog resolves connection troubleshooting by error text', () {
    final entry = HelpCatalog.firstMatch(
      text:
          'Stream error: Connection timed out (printer offline or unreachable).',
    );

    expect(entry?.id, 'stream-timeout');
  });
}
