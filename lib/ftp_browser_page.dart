import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_ftp.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_lan.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_mqtt.dart';
import 'package:rnd_bambu_rtsp_stream/settings_manager.dart';
import 'window_drag_controller.dart';

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
  FilamentOption? _selectedFilament;
  List<FilamentOption> _filamentOptions = const [];
  final List<String> _printDebugLog = <String>[];
  String? _pendingPrintSeq;
  String? _pendingPrintCommand;
  Timer? _pendingPrintTimer;
  StreamSubscription<BambuReportEvent>? _mqttReportSub;
  StreamSubscription<BambuCommandEvent>? _mqttCommandSub;

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
      // MQTT optional; connect to pull filament info & print status.
      final mqtt = BambuMqtt(cfg);
      await mqtt.connect();
      _mqtt = mqtt;
      _subscribeMqtt(mqtt);
      mqtt.requestPushAll().catchError((_) {});
    } catch (_) {
      // keep browsing; printing will try to reconnect
    }
    await _refresh();
  }

  void _subscribeMqtt(BambuMqtt mqtt) {
    _mqttReportSub?.cancel();
    _mqttCommandSub?.cancel();

    _mqttReportSub = mqtt.reportStream.listen((event) {
      _handleMqttReport(event);
    });

    _mqttCommandSub = mqtt.commandStream.listen((event) {
      final payload = event.payload['print'];
      if (payload is Map && payload['command'] != null) {
        _logPrintDebug(
          'CMD ${payload['command']} seq=${payload['sequence_id']} '
          'topic=${event.topic}',
        );
      }
    });
  }

  void _logPrintDebug(String message) {
    final ts = DateTime.now().toIso8601String();
    setState(() {
      _printDebugLog.insert(0, '$ts $message');
      if (_printDebugLog.length > 8) {
        _printDebugLog.removeRange(8, _printDebugLog.length);
      }
    });
  }

  void _handleMqttReport(BambuReportEvent event) {
    final print = event.json['print'];
    if (print is Map) {
      final options = _extractFilamentOptions(print);
      if (options.isNotEmpty) {
        setState(() {
          _filamentOptions = options;
          _selectedFilament ??= _selectCurrentFilament(print, options);
        });
      }

      final seq = print['sequence_id']?.toString();
      final cmd = print['command']?.toString();
      if (_pendingPrintSeq != null &&
          seq == _pendingPrintSeq &&
          cmd == _pendingPrintCommand) {
        final result = print['result']?.toString() ?? 'unknown';
        final reason = print['reason']?.toString();
        _logPrintDebug(
          'RESP $cmd seq=$seq result=$result'
          '${reason != null && reason.isNotEmpty ? ' reason=$reason' : ''}',
        );
        _pendingPrintSeq = null;
        _pendingPrintCommand = null;
        _pendingPrintTimer?.cancel();
      }
    }
  }

  FilamentOption? _resolveSelectedFilament() {
    final current = _selectedFilament;
    if (current == null) return null;
    for (final opt in _filamentOptions) {
      if (opt.id == current.id) return opt;
    }
    return null;
  }

  int? _trayIndexFromFilament(FilamentOption? filament) {
    if (filament == null) return null;
    if (filament.id == 'external') return null;
    if (!filament.id.startsWith('ams:')) return null;
    final parts = filament.id.split(':');
    if (parts.length != 3) return null;
    final amsId = int.tryParse(parts[1]);
    final trayId = int.tryParse(parts[2]);
    if (amsId == null || trayId == null) return null;
    return (amsId * 4) + trayId;
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
        _status = '';
      });
    } on TimeoutException catch (e) {
      setState(
        () => _status = 'FTP timed out: ${e.message ?? 'request stalled'}',
      );
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
        _subscribeMqtt(mqtt);
        mqtt.requestPushAll().catchError((_) {});
      }
      final isGcode = file.endsWith('.gcode');
      final cmd = isGcode ? 'gcode_file' : 'project_file';
      final selectedFilament = _resolveSelectedFilament();
      final filament = selectedFilament?.label;
      _logPrintDebug(
        'PRINT request: $cmd file=$file'
        '${filament != null ? ' | filament=$filament' : ''}',
      );
      late final String seq;
      if (isGcode) {
        seq = await _mqtt!.printGcodeFile(file);
      } else {
        final trayIndex = _trayIndexFromFilament(selectedFilament);
        final useAms = selectedFilament?.id != 'external';
        final mapping = trayIndex == null ? <int>[] : <int>[trayIndex];
        seq = await _mqtt!.printProjectFile(
          projectPath: file,
          plateIndex: 1,
          amsMapping: mapping,
          useAms: useAms,
        );
      }
      _pendingPrintSeq = seq;
      _pendingPrintCommand = cmd;
      _pendingPrintTimer?.cancel();
      _pendingPrintTimer = Timer(const Duration(seconds: 8), () {
        if (!mounted) return;
        if (_pendingPrintSeq != null) {
          _logPrintDebug('No response for print command after 8s.');
        }
      });
      setState(() => _status = 'Print requested: ${file.split('/').last}');
    } catch (e) {
      setState(() => _status = 'Start print failed: $e');
      _logPrintDebug('ERROR start print: $e');
    }
  }

  @override
  void dispose() {
    _mqtt?.dispose();
    _ftp.dispose();
    _mqttReportSub?.cancel();
    _mqttCommandSub?.cancel();
    _pendingPrintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const WindowDragArea(
          child: SizedBox(
            width: double.infinity,
            child: Text('FTP Browser'),
          ),
        ),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          const WindowControlButtons(),
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
                    Expanded(
                      child: DropdownButtonFormField<FilamentOption>(
                        isExpanded: true,
                        initialValue: _resolveSelectedFilament(),
                        decoration: const InputDecoration(
                          hintText: 'Select filament',
                        ),
                        items: _filamentOptions
                            .map(
                              (f) => DropdownMenuItem<FilamentOption>(
                                value: f,
                                child: Row(
                                  children: [
                                    if (f.color != null)
                                      Container(
                                        width: 12,
                                        height: 12,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: f.color,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.black26,
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        f.label,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedFilament = v),
                      ),
                    ),
                  ],
                ),
                if (_printDebugLog.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Print debug',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ..._printDebugLog.map(
                    (line) => Text(
                      line,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
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

class FilamentOption {
  final String id;
  final String label;
  final Color? color;

  const FilamentOption({required this.id, required this.label, this.color});
}

List<FilamentOption> _extractFilamentOptions(Map print) {
  final options = <FilamentOption>[];
  final amsContainer = print['ams'];
  if (amsContainer is Map) {
    final amsList = amsContainer['ams'];
    if (amsList is List) {
      for (final ams in amsList) {
        if (ams is! Map) continue;
        final amsId = ams['id']?.toString() ?? '?';
        final trayList = ams['tray'];
        if (trayList is List) {
          for (final tray in trayList) {
            if (tray is! Map) continue;
            final trayId = tray['id']?.toString() ?? '';
            if (trayId.isEmpty) continue;
            if (tray.keys.length == 1 && trayId == '0') {
              // Empty tray entry.
              continue;
            }
            final trayType = tray['tray_type']?.toString() ?? '';
            final trayName = tray['tray_id_name']?.toString() ?? '';
            final trayColor = _parseTrayColor(tray['tray_color']?.toString());
            final labelParts = <String>[
              'AMS $amsId / Slot $trayId',
              if (trayType.isNotEmpty) trayType,
              if (trayName.isNotEmpty) trayName,
            ];
            options.add(
              FilamentOption(
                id: 'ams:$amsId:$trayId',
                label: labelParts.join(' • '),
                color: trayColor,
              ),
            );
          }
        }
      }
    }
  }

  final vtTray = print['vt_tray'];
  if (vtTray is Map) {
    options.add(
      const FilamentOption(
        id: 'external',
        label: 'External Spool',
      ),
    );
  }

  return options;
}

Color? _parseTrayColor(String? value) {
  if (value == null) return null;
  final hex = value.trim();
  if (hex.length != 8) return null; // RRGGBBAA
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return null;
  final r = (parsed >> 24) & 0xFF;
  final g = (parsed >> 16) & 0xFF;
  final b = (parsed >> 8) & 0xFF;
  final a = parsed & 0xFF;
  return Color.fromARGB(a, r, g, b);
}

FilamentOption? _selectCurrentFilament(
  Map print,
  List<FilamentOption> options,
) {
  final trayNow = print['tray_now']?.toString();
  if (trayNow == null || trayNow.isEmpty || trayNow == '255') return null;
  final trayNum = int.tryParse(trayNow);
  if (trayNum == null) return null;
  if (trayNum == 254) {
    for (final opt in options) {
      if (opt.id == 'external') return opt;
    }
    return null;
  }
  final amsId = trayNum ~/ 4;
  final trayId = trayNum % 4;
  final id = 'ams:$amsId:$trayId';
  try {
    return options.firstWhere((o) => o.id == id);
  } catch (_) {
    return null;
  }
}
