import 'package:flutter/material.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_ftp.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_lan.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_mqtt.dart';
import 'package:rnd_bambu_rtsp_stream/settings_manager.dart';

class FtpBrowserPage extends StatefulWidget {
  const FtpBrowserPage({super.key});

  @override
  State<FtpBrowserPage> createState() => _FtpBrowserPageState();
}

class _FtpBrowserPageState extends State<FtpBrowserPage> {
  late BambuFtp _ftp;
  BambuMqtt? _mqtt;
  String _cwd = '/';
  List<FtpEntry> _entries = const [];
  bool _loading = true;
  String? _selectedFile;
  String _status = '';
  String? _filament; // placeholder for future use

  @override
  void initState() {
    super.initState();
    _initConnections();
  }

  Future<void> _initConnections() async {
    setState(() => _loading = true);
    final s = await SettingsManager.loadSettings();
    final cfg = BambuLanConfig(
      printerIp: s.printerIp,
      accessCode: s.specialCode,
      serial: s.serialNumber,
      allowBadCerts: true,
      mqttPort: 8883,
    );
    _ftp = BambuFtp(cfg);
    try {
      // MQTT optional: only connect when printing
      //final mqtt = BambuMqtt(cfg);
      //await mqtt.connect();
      //_mqtt = mqtt;
    } catch (_) {
      // keep browsing; printing will try to reconnect
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final list = await _ftp.list(_cwd);
      setState(() {
        _entries = list
          ..sort((a, b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name.compareTo(b.name);
          });
      });
    } catch (e) {
      setState(() => _status = 'List failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _enter(FtpEntry e) async {
    if (!e.isDir) {
      setState(() => _selectedFile = e.path);
      return;
    }
    setState(() {
      _cwd = e.path;
      _selectedFile = null;
    });
    await _refresh();
  }

  Future<void> _up() async {
    if (_cwd == '/' || _cwd.isEmpty) return;
    final parts = _cwd.split('/')..removeWhere((p) => p.isEmpty);
    if (parts.isNotEmpty) parts.removeLast();
    final parent = parts.isEmpty ? '/' : '/${parts.join('/')}';
    setState(() {
      _cwd = parent;
      _selectedFile = null;
    });
    await _refresh();
  }

  Future<void> _startPrint() async {
    final file = _selectedFile;
    if (file == null) return;
    try {
      var mqtt = _mqtt;
      if (mqtt == null || !mqtt.isConnected) {
        final s = await SettingsManager.loadSettings();
        final cfg = BambuLanConfig(
          printerIp: s.printerIp,
          accessCode: s.specialCode,
          serial: s.serialNumber,
          allowBadCerts: true,
          mqttPort: 8883,
        );
        mqtt = BambuMqtt(cfg);
        await mqtt.connect();
        _mqtt = mqtt;
      }
      await _mqtt!.startPrintFromSd(file);
      setState(() => _status = 'Print started: ${file.split('/').last}');
    } catch (e) {
      setState(() => _status = 'Start print failed: $e');
    }
  }

  @override
  void dispose() {
    _mqtt?.dispose();
    _ftp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FTP Browser'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ElevatedButton(onPressed: _up, child: const Text('Up')),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _cwd,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _entries.length,
                itemBuilder: (context, i) {
                  final e = _entries[i];
                  final isSel = _selectedFile == e.path;
                  return ListTile(
                    leading: Icon(
                      e.isDir ? Icons.folder : Icons.insert_drive_file,
                    ),
                    title: Text(e.name.isEmpty ? e.path : e.name),
                    dense: true,
                    selected: isSel,
                    onTap: () => _enter(e),
                    trailing:
                        !e.isDir &&
                            (e.name.endsWith('.gcode') ||
                                e.name.endsWith('.3mf'))
                        ? const Text(
                            'printable',
                            style: TextStyle(color: Colors.green),
                          )
                        : null,
                  );
                },
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedFile == null
                            ? 'Select a .gcode/.3mf to print'
                            : 'Selected: ${_selectedFile!.split('/').last}',
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _selectedFile == null ? null : _startPrint,
                      child: const Text('Start Print'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Filament (optional): '),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'e.g., AMS slot A1',
                        ),
                        onChanged: (v) => _filament = v,
                      ),
                    ),
                  ],
                ),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_status, style: const TextStyle(color: Colors.grey)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
