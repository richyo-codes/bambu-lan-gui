import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:boomprint/app_strings.dart';
import 'package:boomprint/bambu_lan.dart';
import 'package:boomprint/bambu_mqtt.dart';
import 'package:boomprint/settings_manager.dart';
import 'window_drag_controller.dart';

class MqttControlPage extends StatefulWidget {
  const MqttControlPage({super.key});

  @override
  State<MqttControlPage> createState() => _MqttControlPageState();
}

class _MqttControlPageState extends State<MqttControlPage> {
  BambuMqtt? _mqtt;
  bool _connecting = false;
  bool _homed = false;
  String _status = 'Disconnected';
  double _xyStep = 10.0;
  double _zStep = 1.0;
  int _speedPct = 100;
  BambuSpeedProfile _profile = BambuSpeedProfile.standard;
  bool _controlsArmed = false; // require explicit enable before sending
  String? _gcodeState; // RUNNING / IDLE / etc
  final List<BambuLogEvent> _logEntries = <BambuLogEvent>[];
  static const int _maxLogEntries = 300;
  StreamSubscription<BambuReportEvent>? _reportSub;
  StreamSubscription<BambuLogEvent>? _logSub;
  bool _showDebugLog = true;

  Future<void> _ensureConnected() async {
    if (_mqtt?.isConnected == true) return;
    setState(() => _connecting = true);
    final settings = await SettingsManager.loadSettings();
    final cfg = BambuLanConfig(
      printerIp: settings.printerIp,
      accessCode: settings.specialCode,
      serial: settings.serialNumber,
      allowBadCerts: true,
      mqttPort: 8883,
    );
    final mqtt = BambuMqtt(cfg);
    try {
      await mqtt.connect();
      setState(() {
        _mqtt = mqtt;
        _status = 'Connected';
      });
      _logSub?.cancel();
      _logSub = mqtt.logStream.listen((event) {
        if (!mounted) return;
        setState(() {
          _logEntries.add(event);
          if (_logEntries.length > _maxLogEntries) {
            _logEntries.removeAt(0);
          }
        });
      });
      // Observe printer state, but do not send any commands implicitly.
      _reportSub?.cancel();
      _reportSub = mqtt.reportStream.listen((e) {
        if (!mounted) return;
        if (e.printStatus != null) {
          setState(() => _gcodeState = e.printStatus!.gcodeState);
        }
      });
    } catch (e) {
      setState(() => _status = 'Connect failed: $e');
      await mqtt.dispose();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _doHomeAll() async {
    await _ensureConnected();
    if (_mqtt == null) return;
    try {
      await _mqtt!.home(x: true, y: true, z: true);
      setState(() {
        _homed = true;
        _status = 'Homing command sent';
      });
    } catch (e) {
      setState(() => _status = 'Homing failed: $e');
    }
  }

  Future<void> _move({double? x, double? y, double? z}) async {
    if (!_controlsArmed) {
      setState(() => _status = 'Controls are locked. Enable to send.');
      return;
    }
    if (!_homed && (x != null || y != null)) {
      setState(() => _status = 'Home first (XY)');
      return;
    }
    await _ensureConnected();
    if (_mqtt == null) return;
    try {
      await _mqtt!.moveRelative(x: x, y: y, z: z);
      setState(() => _status = 'Move sent');
    } catch (e) {
      setState(() => _status = 'Move failed: $e');
    }
  }

  Future<void> _pause() async {
    if (!_controlsArmed) {
      setState(() => _status = 'Controls are locked.');
      return;
    }
    final printing = (_gcodeState == 'RUNNING' || _gcodeState == 'PREPARE');
    if (!printing) {
      setState(() => _status = 'No active print to pause.');
      return;
    }
    final ok = await _confirm(context, 'Pause current print?');
    if (!ok) return;
    await _ensureConnected();
    try {
      await _mqtt!.pausePrint();
      setState(() => _status = 'Pause sent');
    } catch (e) {
      setState(() => _status = 'Pause failed: $e');
    }
  }

  Future<void> _resume() async {
    if (!_controlsArmed) {
      setState(() => _status = 'Controls are locked.');
      return;
    }
    final paused = (_gcodeState == 'PAUSED');
    if (!paused) {
      setState(() => _status = 'Not paused.');
      return;
    }
    final ok = await _confirm(context, 'Resume current print?');
    if (!ok) return;
    await _ensureConnected();
    try {
      await _mqtt!.resumePrint();
      setState(() => _status = 'Resume sent');
    } catch (e) {
      setState(() => _status = 'Resume failed: $e');
    }
  }

  Future<void> _cancel() async {
    if (!_controlsArmed) {
      setState(() => _status = 'Controls are locked.');
      return;
    }
    final printing =
        (_gcodeState == 'RUNNING' ||
        _gcodeState == 'PAUSED' ||
        _gcodeState == 'PREPARE');
    if (!printing) {
      setState(() => _status = 'No active print to cancel.');
      return;
    }
    final ok = await _confirm(
      context,
      'Cancel current print? This stops the job.',
    );
    if (!ok) return;
    await _ensureConnected();
    try {
      await _mqtt!.cancelPrint();
      setState(() => _status = 'Cancel sent');
    } catch (e) {
      setState(() => _status = 'Cancel failed: $e');
    }
  }

  @override
  void dispose() {
    _reportSub?.cancel();
    _logSub?.cancel();
    _mqtt?.dispose();
    super.dispose();
  }

  Future<void> _copyLogs() async {
    final text = _logEntries.map(_formatLogEntry).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      setState(() => _status = 'Logs copied to clipboard');
    }
  }

  void _clearLogs() {
    setState(() => _logEntries.clear());
  }

  String _formatLogEntry(BambuLogEvent event) {
    final time = event.timestamp.toIso8601String();
    final level = event.level.name.toUpperCase();
    return '[$time] $level ${event.message}';
  }

  Future<bool> _confirm(BuildContext context, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirm Action'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return FramelessWindowResizeFrame(
      child: Scaffold(
        appBar: WindowChromeHeader(
          title: const Text(AppStrings.appDisplayName),
          subtitle: const Text('MQTT Controls'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _connecting ? null : _ensureConnected,
                    child: Text(_connecting ? 'Connecting…' : 'Connect'),
                  ),
                  const SizedBox(width: 12),
                  Text(_status),
                  const Spacer(),
                  const Text('Armed'),
                  Switch(
                    value: _controlsArmed,
                    onChanged: (v) => setState(() => _controlsArmed = v),
                  ),
                ],
              ),
              if (_gcodeState != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text('State: ${_gcodeState!}'),
                ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Homing'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ElevatedButton(
                            onPressed: _doHomeAll,
                            child: const Text('Home All'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Move (relative)'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('XY step:'),
                          const SizedBox(width: 8),
                          DropdownButton<double>(
                            value: _xyStep,
                            items: const [1, 5, 10, 25, 50]
                                .map(
                                  (e) => DropdownMenuItem<double>(
                                    value: e.toDouble(),
                                    child: Text('${e}mm'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _xyStep = v ?? 10),
                          ),
                          const SizedBox(width: 24),
                          const Text('Z step:'),
                          const SizedBox(width: 8),
                          DropdownButton<double>(
                            value: _zStep,
                            items: const [0.1, 0.2, 0.5, 1, 2]
                                .map(
                                  (e) => DropdownMenuItem<double>(
                                    value: e.toDouble(),
                                    child: Text('${e}mm'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _zStep = v ?? 1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton(
                            onPressed: () => _move(x: -_xyStep),
                            child: const Text('X-'),
                          ),
                          ElevatedButton(
                            onPressed: () => _move(x: _xyStep),
                            child: const Text('X+'),
                          ),
                          ElevatedButton(
                            onPressed: () => _move(y: -_xyStep),
                            child: const Text('Y-'),
                          ),
                          ElevatedButton(
                            onPressed: () => _move(y: _xyStep),
                            child: const Text('Y+'),
                          ),
                          ElevatedButton(
                            onPressed: () => _move(z: -_zStep),
                            child: const Text('Z-'),
                          ),
                          ElevatedButton(
                            onPressed: () => _move(z: _zStep),
                            child: const Text('Z+'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Speed Profile'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          DropdownButton<BambuSpeedProfile>(
                            value: _profile,
                            items: BambuSpeedProfile.values
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (p) =>
                                setState(() => _profile = p ?? _profile),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () async {
                              await _ensureConnected();
                              if (_mqtt == null) return;
                              try {
                                await _mqtt!.setSpeedProfile(_profile);
                                setState(
                                  () => _status =
                                      'Profile set: ${_profile.label}',
                                );
                              } catch (e) {
                                setState(
                                  () => _status = 'Set profile failed: $e',
                                );
                              }
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Speed (%)'),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              min: 10,
                              max: 300,
                              divisions: 290,
                              value: _speedPct.toDouble(),
                              label: '$_speedPct%',
                              onChanged: (v) =>
                                  setState(() => _speedPct = v.round()),
                            ),
                          ),
                          SizedBox(
                            width: 64,
                            child: Text(
                              '$_speedPct%',
                              textAlign: TextAlign.end,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              await _ensureConnected();
                              if (_mqtt == null) return;
                              try {
                                await _mqtt!.setSpeedPercent(_speedPct);
                                setState(
                                  () => _status = 'Speed set to $_speedPct%',
                                );
                              } catch (e) {
                                setState(
                                  () => _status = 'Set speed failed: $e',
                                );
                              }
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: _pause,
                        child: const Text('Pause'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _resume,
                        child: const Text('Resume'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _cancel,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Safe mode: No commands are sent unless Armed. '
                'Opening this screen does not send any commands.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Card(
                child: ExpansionTile(
                  initiallyExpanded: _showDebugLog,
                  onExpansionChanged: (v) => setState(() => _showDebugLog = v),
                  title: Text('MQTT Logs (${_logEntries.length})'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: _logEntries.isEmpty ? null : _copyLogs,
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('Copy'),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _logEntries.isEmpty ? null : _clearLogs,
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('Clear'),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 220,
                      child: ListView.builder(
                        itemCount: _logEntries.length,
                        itemBuilder: (context, i) {
                          final event = _logEntries[i];
                          final level = event.level.name.toUpperCase();
                          final color = switch (event.level) {
                            BambuLogLevel.debug => Colors.grey,
                            BambuLogLevel.info => Colors.white,
                            BambuLogLevel.warning => Colors.orangeAccent,
                            BambuLogLevel.error => Colors.redAccent,
                          };
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: SelectableText(
                              '[${event.timestamp.toIso8601String()}] '
                              '$level ${event.message}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: color,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
