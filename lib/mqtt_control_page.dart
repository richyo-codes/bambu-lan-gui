import 'package:flutter/material.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_lan.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_mqtt.dart';
import 'package:rnd_bambu_rtsp_stream/settings_manager.dart';

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
    await _ensureConnected();
    try {
      await _mqtt!.pausePrint();
      setState(() => _status = 'Pause sent');
    } catch (e) {
      setState(() => _status = 'Pause failed: $e');
    }
  }

  Future<void> _resume() async {
    await _ensureConnected();
    try {
      await _mqtt!.resumePrint();
      setState(() => _status = 'Resume sent');
    } catch (e) {
      setState(() => _status = 'Resume failed: $e');
    }
  }

  Future<void> _cancel() async {
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
    _mqtt?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MQTT Controls')),
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
              ],
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
                                () =>
                                    _status = 'Profile set: ${_profile.label}',
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
                          child: Text('$_speedPct%', textAlign: TextAlign.end),
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
                              setState(() => _status = 'Set speed failed: $e');
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
            const Text(
              'Note: Commands are best‑effort and may vary by firmware.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
