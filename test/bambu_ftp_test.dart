import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_ftp.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_lan.dart';

class _FakeFtpConnect extends FTPConnect {
  final String response;
  String? lastCmd;
  _FakeFtpConnect(this.response) : super('fake');

  @override
  Future<FTPReply> sendCustomCommand(String command) async {
    lastCmd = command;
    return FTPReply(200, response);
  }

  @override
  Future<bool> disconnect() async => true;
}

void main() {
  const sampleLs = '''
-rw-r--r--    1 1000     1000       956162 Aug 06 01:30 3.5inch_Dell_harddiver_bracket_storage_.gcode.3mf
-rw-r--r--    1 1000     1000       416806 Jul 19 03:45 3M_Command_Strip_-_Honeycomb_Storage_Wall_Mount.gcode.3mf
''';

  test('parseLsResponse parses unix ls lines', () {
    final entries = BambuFtp.parseLsResponse(sampleLs, currentPath: '/');
    expect(entries.length, 2);
    expect(entries.first.name, startsWith('3.5inch_Dell'));
    expect(entries.first.isDir, isFalse);
    expect(
      entries.first.path,
      '/3.5inch_Dell_harddiver_bracket_storage_.gcode.3mf',
    );
  });

  test('list issues ls <path> and parses entries', () async {
    final fake = _FakeFtpConnect(sampleLs);
    final cfg = BambuLanConfig(
      printerIp: '0.0.0.0',
      accessCode: 'x',
      serial: 's',
    );
    final client = BambuFtp(cfg, client: fake);

    final entries = await client.list('/');
    expect(fake.lastCmd, 'ls /');
    expect(entries.length, 2);
  });
}
