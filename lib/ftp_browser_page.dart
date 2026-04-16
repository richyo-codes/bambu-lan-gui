import 'dart:async';
import 'dart:io';

import 'package:boomprint/feature_flags.dart';
import 'package:boomprint/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:boomprint/bambu_ftp.dart';
import 'package:boomprint/bambu_lan.dart';
import 'package:boomprint/bambu_mqtt.dart';
import 'package:boomprint/settings_manager.dart';
import 'package:three_mf/three_mf.dart';
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
  ThreeMfProjectInfo? _selectedThreeMfInfo;
  bool _loadingThreeMfInfo = false;
  String? _selectedThreeMfPath;
  String? _currentNozzleDiameter;
  String? _currentNozzleType;
  final Map<int, FilamentOption?> _threeMfFilamentSelections =
      <int, FilamentOption?>{};
  final List<String> _printDebugLog = <String>[];
  String? _pendingPrintSeq;
  int _pendingReportCount = 0;
  Timer? _pendingPrintTimer;
  StreamSubscription<BambuReportEvent>? _mqttReportSub;
  StreamSubscription<BambuCommandEvent>? _mqttCommandSub;

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    if (!FeatureFlags.ftpBrowserEnabled) {
      _loading = false;
      _status = 'FTP Browser is disabled by feature flag.';
      return;
    }
    _initConnections();
  }

  Future<void> _initConnections() async {
    _setStateIfMounted(() => _loading = true);
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
      final payload = _asStringDynamicMap(event.payload['print']);
      if (payload != null && payload['command'] != null) {
        final cmd = payload['command']?.toString() ?? '?';
        final seq = payload['sequence_id']?.toString() ?? '?';
        final param = payload['param']?.toString();
        final url = payload['url']?.toString();
        final useAms = payload['use_ams'];
        final ams = payload['ams_mapping'];
        _logPrintDebug('CMD $cmd seq=$seq topic=${event.topic}');
        if (param != null && param.isNotEmpty) {
          _logPrintDebug('  param=$param');
        }
        if (url != null && url.isNotEmpty) {
          _logPrintDebug('  url=$url');
        }
        if (useAms != null) {
          _logPrintDebug('  use_ams=$useAms');
        }
        if (ams is List && ams.isNotEmpty) {
          _logPrintDebug('  ams_mapping=$ams');
        }
      }
    });
  }

  void _logPrintDebug(String message) {
    final ts = DateTime.now().toIso8601String();
    debugPrint('[FTP PRINT $ts] $message');
    _setStateIfMounted(() {
      _printDebugLog.insert(0, '$ts $message');
      if (_printDebugLog.length > 8) {
        _printDebugLog.removeRange(8, _printDebugLog.length);
      }
    });
  }

  Future<void> _inspectSelectedThreeMf(String remotePath) async {
    _setStateIfMounted(() {
      _loadingThreeMfInfo = true;
      _selectedThreeMfPath = remotePath;
      _selectedThreeMfInfo = null;
      _threeMfFilamentSelections.clear();
    });

    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('boomprint_3mf_');
      final basename = remotePath.split('/').last;
      final localFile = File(
        '${tempDir.path}${Platform.pathSeparator}$basename',
      );
      final downloaded = await _ftp.downloadFile(remotePath, localFile);
      if (!downloaded) {
        throw StateError('FTP download failed');
      }

      final parser = ThreeMfParser();
      final info = await parser.parseBytes(await localFile.readAsBytes());
      if (!mounted || _selectedThreeMfPath != remotePath) return;

      _setStateIfMounted(() {
        _selectedThreeMfInfo = info;
        _loadingThreeMfInfo = false;
        if (info != null) {
          final matched = _matchFilamentOption(info);
          if (matched != null && info.orderedFilaments.length <= 1) {
            _selectedFilament = matched;
          }
          for (var i = 0; i < info.orderedFilaments.length; i++) {
            final filament = info.orderedFilaments[i];
            final key = _threeMfFilamentKey(filament, i);
            _threeMfFilamentSelections[key] = _matchFilamentOptionForFilament(
              filament,
            );
          }
        }
      });
    } catch (e) {
      if (!mounted || _selectedThreeMfPath != remotePath) return;
      _setStateIfMounted(() {
        _selectedThreeMfInfo = null;
        _loadingThreeMfInfo = false;
      });
      _logPrintDebug('3MF inspect failed for $remotePath: $e');
    } finally {
      try {
        await tempDir?.delete(recursive: true);
      } catch (_) {}
    }
  }

  FilamentOption? _matchFilamentOption(ThreeMfProjectInfo info) {
    final hints =
        [
              ...info.filamentHints,
              ...info.plates.expand((plate) => plate.filamentHints),
            ]
            .map((value) => value.toLowerCase())
            .where((value) => value.isNotEmpty)
            .toList();
    if (hints.isEmpty) return null;

    for (final option in _filamentOptions) {
      final label = option.label.toLowerCase();
      if (hints.any((hint) => label.contains(hint.toLowerCase()))) {
        return option;
      }
    }
    return null;
  }

  FilamentOption? _matchFilamentOptionForFilament(
    ThreeMfFilamentInfo filament,
  ) {
    final hints = <String>[
      ...filament.compatibilityTokens,
      filament.summary,
      if (filament.fields.values.isNotEmpty)
        ...filament.fields.values.where((value) => value.trim().isNotEmpty),
    ];
    return _matchFilamentOptionByHints(hints);
  }

  FilamentOption? _matchFilamentOptionByHints(Iterable<String> hints) {
    final normalizedHints = hints
        .map((value) => value.toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList();
    if (normalizedHints.isEmpty) return null;

    for (final option in _filamentOptions) {
      final label = option.label.toLowerCase();
      if (normalizedHints.any((hint) => label.contains(hint))) {
        return option;
      }
    }
    return null;
  }

  int _threeMfFilamentKey(ThreeMfFilamentInfo filament, int index) {
    return filament.slot ?? index;
  }

  List<int> _buildThreeMfAmsMapping(List<int> trays) {
    const totalSlots = 5;
    final mapping = List<int>.filled(totalSlots, -1);
    if (trays.isEmpty) return mapping;
    final start = totalSlots - trays.length;
    for (var i = 0; i < trays.length && start + i < totalSlots; i++) {
      mapping[start + i] = trays[i];
    }
    return mapping;
  }

  _ThreeMfPrintSelection? _resolveThreeMfPrintSelection(
    ThreeMfProjectInfo info,
  ) {
    final orderedFilaments = info.orderedFilaments;
    if (orderedFilaments.isEmpty) return null;

    final selectedOptions = <FilamentOption>[];
    for (var i = 0; i < orderedFilaments.length; i++) {
      final filament = orderedFilaments[i];
      final key = _threeMfFilamentKey(filament, i);
      final selection =
          _threeMfFilamentSelections[key] ??
          _matchFilamentOptionForFilament(filament);
      if (selection == null) {
        return _ThreeMfPrintSelection(
          error:
              'Select a filament for ${filament.summary.isNotEmpty ? filament.summary : 'filament ${i + 1}'}.',
        );
      }
      if (selection.id == 'external' && orderedFilaments.length > 1) {
        return const _ThreeMfPrintSelection(
          error: 'Multi-filament 3MF jobs must use AMS filament selections.',
        );
      }
      selectedOptions.add(selection);
    }

    final selectedLabels = selectedOptions.map((opt) => opt.label).toList();
    final amsTrays = selectedOptions
        .where((opt) => opt.trayIndex != null)
        .map((opt) => opt.trayIndex!)
        .toList();
    if (amsTrays.length != selectedOptions.length) {
      return const _ThreeMfPrintSelection(
        error: 'Selected filament mapping is missing AMS tray indices.',
      );
    }

    return _ThreeMfPrintSelection(
      amsMapping: _buildThreeMfAmsMapping(amsTrays),
      useAms: true,
      selectedLabels: selectedLabels,
    );
  }

  void _handleMqttReport(BambuReportEvent event) {
    final print = _asStringDynamicMap(event.json['print']);
    if (print != null) {
      final options = _extractFilamentOptions(print);
      if (options.isNotEmpty) {
        _setStateIfMounted(() {
          _filamentOptions = options;
          _selectedFilament ??= _selectCurrentFilament(print, options);
          if (_selectedFilament == null && _selectedThreeMfInfo != null) {
            _selectedFilament = _matchFilamentOption(_selectedThreeMfInfo!);
          }
        });
      }

      final printStatus = event.printStatus;
      if (printStatus != null) {
        _setStateIfMounted(() {
          _currentNozzleDiameter = printStatus.nozzleDiameter;
          _currentNozzleType = printStatus.nozzleType;
        });
      }
    }

    if (_pendingPrintSeq != null && _pendingReportCount < 12) {
      _pendingReportCount += 1;
      _logPrintDebug(
        'RPT #$_pendingReportCount topic=${event.topic} '
        '${_summarizeReportEnvelope(event.json)}',
      );
    }

    final ack = _extractAckEnvelope(event.json);
    if (_pendingPrintSeq == null || ack == null) {
      return;
    }
    if (ack.sequenceId != _pendingPrintSeq) {
      return;
    }

    final cmd = ack.payload['command']?.toString() ?? ack.envelope;
    final result = ack.payload['result']?.toString();
    final reason = ack.payload['reason']?.toString();
    final errCode = ack.payload['error_code']?.toString();
    _logPrintDebug(
      'ACK $cmd seq=${ack.sequenceId} '
      '${result != null ? 'result=$result ' : ''}'
      '${reason != null && reason.isNotEmpty ? 'reason=$reason ' : ''}'
      '${errCode != null && errCode.isNotEmpty ? 'error_code=$errCode' : ''}'
      '(env=${ack.envelope})',
    );

    final hasErrorCode =
        errCode != null && errCode.isNotEmpty && errCode.trim() != '0';
    final failed =
        _isFailureSignal(result) || _isFailureSignal(reason) || hasErrorCode;
    if (failed) {
      final msg =
          reason ??
          result ??
          (errCode != null && errCode.isNotEmpty
              ? 'error_code=$errCode'
              : 'printer rejected command');
      _setStateIfMounted(() => _status = 'Print rejected: $msg');
    } else {
      _setStateIfMounted(() => _status = 'Print command acknowledged.');
    }
    _clearPendingPrint();
  }

  void _clearPendingPrint() {
    _pendingPrintSeq = null;
    _pendingReportCount = 0;
    _pendingPrintTimer?.cancel();
    _pendingPrintTimer = null;
  }

  bool _isPrintablePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.gcode') || lower.endsWith('.3mf');
  }

  Map<String, dynamic>? _asStringDynamicMap(Object? value) {
    if (value is! Map) return null;
    final out = <String, dynamic>{};
    for (final entry in value.entries) {
      out[entry.key.toString()] = entry.value;
    }
    return out;
  }

  _MqttEnvelopeAck? _extractAckEnvelope(Map<String, dynamic> json) {
    for (final envelope in ['print', 'system', 'info', 'pushing']) {
      final payload = _asStringDynamicMap(json[envelope]);
      if (payload == null) continue;
      final seq = payload['sequence_id']?.toString();
      if (seq != null && seq.isNotEmpty) {
        return _MqttEnvelopeAck(
          envelope: envelope,
          sequenceId: seq,
          payload: payload,
        );
      }
    }
    return null;
  }

  String _summarizeReportEnvelope(Map<String, dynamic> json) {
    final topKeys = json.keys.take(6).join(',');
    final print = _asStringDynamicMap(json['print']);
    if (print == null) {
      return 'top=[$topKeys]';
    }
    final cmd = print['command']?.toString();
    final seq = print['sequence_id']?.toString();
    final state = print['gcode_state']?.toString();
    final pct = print['mc_percent']?.toString();
    final result = print['result']?.toString();
    final reason = print['reason']?.toString();
    final details = <String>[
      if (cmd != null && cmd.isNotEmpty) 'cmd=$cmd',
      if (seq != null && seq.isNotEmpty) 'seq=$seq',
      if (state != null && state.isNotEmpty) 'state=$state',
      if (pct != null && pct.isNotEmpty) 'pct=$pct',
      if (result != null && result.isNotEmpty) 'result=$result',
      if (reason != null && reason.isNotEmpty) 'reason=$reason',
    ];
    return 'top=[$topKeys] ${details.join(' ')}';
  }

  bool _isFailureSignal(String? value) {
    if (value == null) return false;
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return false;
    return v == 'fail' ||
        v == 'failed' ||
        v == 'error' ||
        v == 'reject' ||
        v == 'rejected' ||
        v == 'denied' ||
        v == 'invalid' ||
        v == 'forbidden' ||
        v == 'timeout' ||
        v == 'busy';
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
    return filament.trayIndex;
  }

  List<int> _singleColorAmsMapping(int trayIndex) {
    // project_file expects a fixed-width mapping array; right-most entry is
    // consumed first for single-color jobs.
    return <int>[-1, -1, -1, -1, trayIndex];
  }

  Future<void> _refresh() async {
    _setStateIfMounted(() => _loading = true);
    try {
      final list = await _ftp.list(_cwd);
      _setStateIfMounted(() {
        _entries = list
          ..sort((a, b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name.compareTo(b.name);
          });
        _status = '';
      });
    } on TimeoutException catch (e) {
      _setStateIfMounted(
        () => _status = 'FTP timed out: ${e.message ?? 'request stalled'}',
      );
    } catch (e) {
      _setStateIfMounted(() => _status = 'List failed: $e');
    } finally {
      _setStateIfMounted(() => _loading = false);
    }
  }

  Future<void> _enter(FtpEntry e) async {
    if (!e.isDir) {
      _setStateIfMounted(() => _selectedFile = e.path);
      if (_isPrintablePath(e.path) && e.path.toLowerCase().endsWith('.3mf')) {
        await _inspectSelectedThreeMf(e.path);
      } else {
        _setStateIfMounted(() {
          _selectedThreeMfInfo = null;
          _loadingThreeMfInfo = false;
          _selectedThreeMfPath = null;
        });
      }
      return;
    }
    _setStateIfMounted(() {
      _cwd = e.path;
      _selectedFile = null;
      _selectedThreeMfInfo = null;
      _loadingThreeMfInfo = false;
      _selectedThreeMfPath = null;
    });
    await _refresh();
  }

  Future<void> _up() async {
    if (_cwd == '/' || _cwd.isEmpty) return;
    final parts = _cwd.split('/')..removeWhere((p) => p.isEmpty);
    if (parts.isNotEmpty) parts.removeLast();
    final parent = parts.isEmpty ? '/' : '/${parts.join('/')}';
    _setStateIfMounted(() {
      _cwd = parent;
      _selectedFile = null;
      _selectedThreeMfInfo = null;
      _loadingThreeMfInfo = false;
      _selectedThreeMfPath = null;
    });
    await _refresh();
  }

  Future<void> _startPrint() async {
    final file = _selectedFile;
    if (file == null) return;
    if (!_isPrintablePath(file)) {
      _setStateIfMounted(() => _status = 'Select a .gcode or .3mf file.');
      return;
    }
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
      final lowerFile = file.toLowerCase();
      final isGcode = lowerFile.endsWith('.gcode');
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
        final info = _selectedThreeMfInfo;
        final resolved = info != null && info.orderedFilaments.isNotEmpty
            ? _resolveThreeMfPrintSelection(info)
            : null;
        List<int> mapping;
        bool useAms;

        if (resolved != null) {
          if (resolved.error != null) {
            _setStateIfMounted(() => _status = resolved.error!);
            _logPrintDebug('PRINT blocked: ${resolved.error}');
            return;
          }
          mapping = resolved.amsMapping;
          useAms = resolved.useAms;
          _logPrintDebug(
            '3MF filament mapping: ${resolved.selectedLabels.join(' | ')}',
          );
        } else {
          if (selectedFilament == null) {
            _setStateIfMounted(
              () => _status =
                  'Select a filament option before starting a .3mf print.',
            );
            _logPrintDebug(
              'PRINT blocked: no filament selected for project_file.',
            );
            return;
          }
          final trayIndex = _trayIndexFromFilament(selectedFilament);
          useAms = selectedFilament.id != 'external';
          if (useAms && trayIndex == null) {
            _setStateIfMounted(
              () => _status = 'Selected filament is invalid for AMS mapping.',
            );
            _logPrintDebug(
              'PRINT blocked: invalid AMS mapping for ${selectedFilament.id}.',
            );
            return;
          }
          mapping = useAms ? _singleColorAmsMapping(trayIndex!) : <int>[];
        }
        seq = await _mqtt!.printProjectFile(
          projectPath: file,
          plateIndex: 1,
          amsMapping: mapping,
          useAms: useAms,
        );
      }
      _pendingPrintSeq = seq;
      _pendingReportCount = 0;
      _pendingPrintTimer?.cancel();
      _pendingPrintTimer = Timer(const Duration(seconds: 15), () {
        if (!mounted) return;
        if (_pendingPrintSeq != null) {
          final pendingSeq = _pendingPrintSeq;
          _logPrintDebug('No matching print ACK after 15s (seq=$pendingSeq).');
          _setStateIfMounted(
            () => _status = 'No MQTT ACK for print command (seq=$pendingSeq).',
          );
          _clearPendingPrint();
        }
      });
      _setStateIfMounted(
        () => _status =
            'Print requested: ${file.split('/').last} (waiting for ACK)',
      );
    } catch (e) {
      _setStateIfMounted(() => _status = 'Start print failed: $e');
      _logPrintDebug('ERROR start print: $e');
    }
  }

  Widget _buildThreeMfMetadataPanel() {
    final selectedFile = _selectedFile;
    if (selectedFile == null || !selectedFile.toLowerCase().endsWith('.3mf')) {
      return const SizedBox.shrink();
    }

    final info = _selectedThreeMfInfo;
    if (_loadingThreeMfInfo || _selectedThreeMfPath != selectedFile) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (info == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'No embedded 3MF metadata was extracted from this project.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final isMultiFilament = info.orderedFilaments.length > 1;
    final currentNozzle = _currentNozzleLabel;
    final projectNozzles = info.nozzleSummary;
    final nozzleMismatchWarning = _buildNozzleMismatchWarning(info);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Embedded 3MF metadata',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              if (info.projectName != null && info.projectName!.isNotEmpty)
                Text('Project: ${info.projectName}'),
              if (info.printerProfile != null &&
                  info.printerProfile!.isNotEmpty)
                Text('Printer profile: ${info.printerProfile}'),
              if (info.plateSummaries.isNotEmpty)
                Text('Plates: ${info.plateSummaries.join(' | ')}'),
              if (info.filamentHints.isNotEmpty)
                Text('Filament hints: ${info.filamentHints.join(' | ')}'),
              if (projectNozzles != null)
                Text('Slicer nozzle: $projectNozzles mm'),
              if (currentNozzle != null) Text('Printer nozzle: $currentNozzle'),
              if (nozzleMismatchWarning != null) ...[
                const SizedBox(height: 6),
                Text(
                  nozzleMismatchWarning,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (!isMultiFilament) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Filament (optional): '),
                    const SizedBox(width: 8),
                    Expanded(child: _buildSingleFilamentSelector(info)),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 12),
                const Text(
                  'Filament mapping',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < info.orderedFilaments.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildThreeMfFilamentRow(info, i),
                  ),
              ],
              for (final warning in info.warnings) ...[
                const SizedBox(height: 4),
                Text(warning, style: const TextStyle(color: Colors.grey)),
              ],
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  info.notes.join(' • '),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSingleFilamentSelector(ThreeMfProjectInfo info) {
    final selectedLabel = _selectedFilament?.label;
    final compatibilityWarning = selectedLabel == null
        ? null
        : info.compatibilityWarningFor(selectedLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<FilamentOption>(
          isExpanded: true,
          initialValue: _resolveSelectedFilament(),
          decoration: const InputDecoration(hintText: 'Select filament'),
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
                            border: Border.all(color: Colors.black26),
                          ),
                        ),
                      Expanded(
                        child: Text(f.label, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedFilament = v),
        ),
        if (compatibilityWarning != null) ...[
          const SizedBox(height: 6),
          Text(
            compatibilityWarning,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  String? get _currentNozzleLabel {
    final diameter = _currentNozzleDiameter?.trim() ?? '';
    final type = _currentNozzleType?.trim() ?? '';
    if (diameter.isEmpty && type.isEmpty) return null;
    if (diameter.isNotEmpty && type.isNotEmpty) {
      return '$type $diameter mm';
    }
    return diameter.isNotEmpty ? '$diameter mm' : type;
  }

  String? _buildNozzleMismatchWarning(ThreeMfProjectInfo info) {
    final projectNozzles = info.nozzleHints;
    final current = _currentNozzleDiameter?.trim() ?? '';
    if (projectNozzles.isEmpty || current.isEmpty) return null;

    final normalizedCurrent = _normalizeNozzleText(current);
    if (normalizedCurrent.isEmpty) return null;

    for (final projectNozzle in projectNozzles) {
      if (_normalizeNozzleText(projectNozzle) == normalizedCurrent) {
        return null;
      }
    }

    return 'Slicer nozzle ${projectNozzles.join(', ')} mm does not match the printer nozzle $current mm.';
  }

  String _normalizeNozzleText(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(normalized);
    return match?.group(1) ?? normalized.replaceAll(RegExp(r'[^a-z0-9.]+'), '');
  }

  Widget _buildThreeMfFilamentRow(ThreeMfProjectInfo info, int index) {
    final filament = info.orderedFilaments[index];
    final key = _threeMfFilamentKey(filament, index);
    final selected =
        _threeMfFilamentSelections[key] ??
        _matchFilamentOptionForFilament(filament);
    final warning = selected == null
        ? null
        : info.compatibilityWarningFor(selected.label);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          filament.summary.isNotEmpty
              ? filament.summary
              : 'Filament ${index + 1}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<FilamentOption>(
          key: ValueKey('three-mf-filament-$key-${selected?.id ?? 'none'}'),
          isExpanded: true,
          initialValue: selected,
          decoration: const InputDecoration(
            hintText: 'Select printer filament',
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
                            border: Border.all(color: Colors.black26),
                          ),
                        ),
                      Expanded(
                        child: Text(f.label, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            setState(() {
              _threeMfFilamentSelections[key] = v;
            });
          },
        ),
        if (warning != null) ...[
          const SizedBox(height: 4),
          Text(
            warning,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
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
    if (!FeatureFlags.ftpBrowserEnabled) {
      return FramelessWindowResizeFrame(
        child: Scaffold(
          appBar: WindowChromeHeader(
            title: const Text(AppStrings.appDisplayName),
            subtitle: const Text('FTP Browser'),
            leading: IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          body: const Center(
            child: Text('FTP Browser is disabled for this build.'),
          ),
        ),
      );
    }

    final selected = _selectedFile;
    final selectedPrintable = selected != null && _isPrintablePath(selected);

    return FramelessWindowResizeFrame(
      child: Scaffold(
        appBar: WindowChromeHeader(
          title: const Text(AppStrings.appDisplayName),
          subtitle: const Text('FTP Browser'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
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
                      trailing: !e.isDir && _isPrintablePath(e.name)
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
                              : selectedPrintable
                              ? 'Selected: ${_selectedFile!.split('/').last}'
                              : 'Selected (not printable): ${_selectedFile!.split('/').last}',
                        ),
                      ),
                      ElevatedButton(
                        onPressed: selectedPrintable ? _startPrint : null,
                        child: const Text('Start Print'),
                      ),
                    ],
                  ),
                  _buildThreeMfMetadataPanel(),
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
                                          margin: const EdgeInsets.only(
                                            right: 8,
                                          ),
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
                          onChanged: (v) =>
                              setState(() => _selectedFilament = v),
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
      ),
    );
  }
}

class FilamentOption {
  final String id;
  final String label;
  final Color? color;
  final int? trayIndex;

  const FilamentOption({
    required this.id,
    required this.label,
    this.color,
    this.trayIndex,
  });
}

class _MqttEnvelopeAck {
  final String envelope;
  final String sequenceId;
  final Map<String, dynamic> payload;

  const _MqttEnvelopeAck({
    required this.envelope,
    required this.sequenceId,
    required this.payload,
  });
}

class _ThreeMfPrintSelection {
  final List<int> amsMapping;
  final bool useAms;
  final List<String> selectedLabels;
  final String? error;

  const _ThreeMfPrintSelection({
    this.amsMapping = const [],
    this.useAms = true,
    this.selectedLabels = const [],
    this.error,
  });
}

List<FilamentOption> _extractFilamentOptions(Map print) {
  final options = <FilamentOption>[];
  final amsContainer = print['ams'];
  if (amsContainer is Map) {
    final amsList = amsContainer['ams'];
    if (amsList is List) {
      for (var amsIndex = 0; amsIndex < amsList.length; amsIndex++) {
        final ams = amsList[amsIndex];
        if (ams is! Map) continue;
        final trayList = ams['tray'];
        if (trayList is List) {
          for (final tray in trayList) {
            if (tray is! Map) continue;
            final trayId = tray['id']?.toString() ?? '';
            if (trayId.isEmpty) continue;
            final trayIdNum = int.tryParse(trayId);
            if (trayIdNum == null) continue;
            if (tray.keys.length == 1 && trayId == '0') {
              // Empty tray entry.
              continue;
            }
            final trayType = tray['tray_type']?.toString() ?? '';
            final trayName = tray['tray_id_name']?.toString() ?? '';
            final trayColor = _parseTrayColor(tray['tray_color']?.toString());
            final trayIndex = (amsIndex * 4) + trayIdNum;
            final labelParts = <String>[
              'AMS ${amsIndex + 1} / Slot $trayId',
              if (trayType.isNotEmpty) trayType,
              if (trayName.isNotEmpty) trayName,
            ];
            options.add(
              FilamentOption(
                id: 'ams:$amsIndex:$trayId',
                label: labelParts.join(' • '),
                color: trayColor,
                trayIndex: trayIndex,
              ),
            );
          }
        }
      }
    }
  }

  final vtTray = print['vt_tray'];
  if (vtTray is Map) {
    options.add(const FilamentOption(id: 'external', label: 'External Spool'));
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
  try {
    return options.firstWhere((o) => o.trayIndex == trayNum);
  } catch (_) {
    return null;
  }
}
