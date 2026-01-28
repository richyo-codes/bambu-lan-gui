import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_lan.dart';

// ==========
// MQTT Client
// ==========

class BambuMqtt {
  final BambuLanConfig config;
  late final MqttServerClient _client =
      MqttServerClient(config.printerIp, _clientId())
        ..port = config.mqttPort
        ..secure = true
        ..keepAlivePeriod = 30
        ..logging(on: false);

  final _reports = StreamController<BambuReportEvent>.broadcast();
  final _commands = StreamController<BambuCommandEvent>.broadcast();
  int _seq = 1;
  String? _activeSerial;

  Stream<BambuReportEvent> get reportStream => _reports.stream;
  Stream<BambuCommandEvent> get commandStream => _commands.stream;
  bool get isConnected =>
      _client.connectionStatus?.state == MqttConnectionState.connected;

  BambuMqtt(this.config);

  Future<void> connect() async {
    // TLS context
    if (config.caCertPem != null && config.caCertPem!.trim().isNotEmpty) {
      const withTrustedRoots = false;
      final ctx = SecurityContext(withTrustedRoots: withTrustedRoots);
      final bytes = Uint8List.fromList(utf8.encode(config.caCertPem!));
      try {
        ctx.setTrustedCertificatesBytes(bytes);
        _client.securityContext = ctx;
      } catch (e) {
        stderr.writeln('Failed to apply custom CA cert: $e');
      }
    }

    if (config.allowBadCerts) {
      // _client.onBadCertificate = (X509Certificate c) {
      //   return true; // accept any certificate
      // };

      _client.onBadCertificate = (Object c) {
        return true; // accept any certificate
      };
    }

    //_client.setProtocolV311();
    _client.resubscribeOnAutoReconnect = true;
    _client.autoReconnect = true;

    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(_clientId())
        .authenticateAs('bblp', config.accessCode)
        .startClean()
        .keepAliveFor(30)
        .withWillQos(MqttQos.atLeastOnce);

    _client.onDisconnected = () {
      stderr.writeln(
        'MQTT disconnected: ${_client.connectionStatus?.disconnectionOrigin}',
      );
    };

    try {
      await _client.connect();
    } on Exception {
      _client.disconnect();
      rethrow;
    }

    // Subscribe to reports (always wildcard; specific serial may differ by case)
    _activeSerial = _normalizeSerial(config.serial);
    _client.subscribe('device/+/report', MqttQos.atLeastOnce);
    if (_activeSerial != null) {
      _client.subscribe('device/${_activeSerial!}/report', MqttQos.atLeastOnce);
    }

    _client.updates?.listen((events) {
      for (final evt in events) {
        final rec = evt.payload as MqttPublishMessage;
        final msg = MqttPublishPayload.bytesToStringAsString(
          rec.payload.message,
        );
        try {
          final jsonMap = json.decode(msg) as Map<String, dynamic>;
          final type = _detectType(jsonMap);
          final ps = _extractPrintStatus(jsonMap);
          final e = BambuReportEvent(
            topic: evt.topic,
            json: jsonMap,
            type: type,
            printStatus: ps,
          );
          // Try to learn serial from the first report if not set
          _maybeInferSerial(evt.topic, jsonMap);

          _reports.add(e);
        } catch (e) {
          final maxLen = msg.length < 200 ? msg.length : 200;
          stderr.writeln(
            'MQTT report parse failed: $e | topic=${evt.topic} | '
            'msg=${msg.substring(0, maxLen)}',
          );
        }
      }
    });
  }

  String _clientId() => 'bambu_dart_${DateTime.now().millisecondsSinceEpoch}';

  String? _normalizeSerial(String? serial) {
    final trimmed = serial?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String? _detectType(Map<String, dynamic> j) {
    // Heuristic; schema can vary by firmware
    final p = j['print'];
    if (p is Map<String, dynamic>) {
      // Prefer explicit gcode_state if present (e.g., RUNNING, FINISH, IDLE)
      final gs = p['gcode_state'];
      if (gs is String && gs.isNotEmpty) return gs;
      // Fallback to mc_print_stage numeric mapping
      final stage = p['mc_print_stage'];
      if (stage is String || stage is num) {
        final s = stage.toString();
        switch (s) {
          case '0':
            return 'IDLE';
          case '1':
            return 'PREPARE';
          case '2':
            return 'RUNNING';
          case '3':
            return 'PAUSED';
          case '4':
            return 'FINISH';
          default:
            return 'PRINT';
        }
      }
      return 'PRINT';
    }
    if (j.containsKey('system')) {
      return 'SYSTEM';
    }
    return null;
  }

  BambuPrintStatus? _extractPrintStatus(Map<String, dynamic> j) {
    final p = j['print'];
    if (p is! Map) return null;
    T? pick<T>(String k) {
      final v = p[k];
      if (v == null) return null;
      if (T == int) {
        if (v is int) return v as T;
        if (v is String) return int.tryParse(v) as T?;
        if (v is num) return v.toInt() as T;
      }
      if (T == double) {
        if (v is double) return v as T;
        if (v is int) return v.toDouble() as T;
        if (v is String) return double.tryParse(v) as T?;
      }
      if (T == String) {
        if (v is String) return v as T;
        return v.toString() as T;
      }
      return v as T?;
    }

    final gcodeState = pick<String>('gcode_state') ?? 'PRINT';
    return BambuPrintStatus(
      gcodeState: gcodeState,
      percent: pick<int>('mc_percent'),
      remainingMinutes: pick<int>('mc_remaining_time'),
      gcodeFile: pick<String>('gcode_file'),
      layer: pick<int>('layer_num'),
      totalLayers: pick<int>('total_layer_num'),
      bedTemp: pick<double>('bed_temper'),
      bedTarget: pick<double>('bed_target_temper'),
      nozzleTemp: pick<double>('nozzle_temper'),
      nozzleTarget: pick<double>('nozzle_target_temper'),
      chamberTemp: pick<double>('chamber_temper'),
      nozzleType: pick<String>('nozzle_type'),
      nozzleDiameter: pick<String>('nozzle_diameter'),
      speedLevel: pick<int>('spd_lvl'),
      speedMag: pick<int>('spd_mag'),
      subtaskName: pick<String>('subtask_name'),
      taskId: pick<String>('task_id'),
      jobId: pick<String>('job_id'),
      wifiSignal: pick<String>('wifi_signal'),
    );
  }

  void _maybeInferSerial(String topic, Map<String, dynamic> j) {
    if (_activeSerial != null) {
      return;
    }

    final m = RegExp(r'^device/([^/]+)/report').firstMatch(topic);
    if (m != null) {
      _activeSerial = _normalizeSerial(m.group(1));
    } else {
      // try payload fields often containing serial/dev id (best-effort)
      for (final key in ['sn', 'serial', 'dev_id', 'usn']) {
        final v = j[key];
        if (v is String && v.isNotEmpty) {
          _activeSerial = _normalizeSerial(v);
          break;
        }
      }
    }
  }

  Future<void> dispose() async {
    await _reports.close();
    _client.disconnect();
  }

  /// Publish a raw JSON payload to the printer's request topic.
  Future<void> publishRequest(
    Map<String, dynamic> payload, {
    MqttQos qos = MqttQos.atLeastOnce,
  }) async {
    final sn = _normalizeSerial(_activeSerial) ?? _normalizeSerial(config.serial);
    if (sn == null) {
      throw StateError(
        'Printer serial is unknown; provide BambuLanConfig.serial or wait for first report.',
      );
    }
    final topic = 'device/$sn/request';
    final b = MqttClientPayloadBuilder();
    b.addUTF8String(jsonEncode(payload));
    // Log the outbound command explicitly
    final evt = BambuCommandEvent(
      topic: topic,
      payload: payload,
      qos: qos,
      timestamp: DateTime.now(),
    );
    _commands.add(evt);
    stderr.writeln('[MQTT CMD ${evt.timestamp.toIso8601String()}] ${evt.topic} ${jsonEncode(evt.payload)}');
    _client.publishMessage(topic, qos, b.payload!);
  }

  // ===== Convenience Commands (best-effort; firmware may vary) =====

  Future<void> sendGcode(String line) async {
    final payload = {
      'system': {
        'sequence_id': (_seq++).toString(),
        'command': 'gcode_line',
        'param': line,
      },
    };
    await publishRequest(payload);
  }

  Future<void> home({bool x = true, bool y = true, bool z = true}) async {
    final axes = [if (x) 'X', if (y) 'Y', if (z) 'Z'].join(' ');
    await sendGcode('G28 $axes');
  }

  Future<void> moveRelative({
    double? x,
    double? y,
    double? z,
    int feed = 6000,
  }) async {
    // Relative move: set to relative, move, then back to absolute
    final parts = <String>[];
    if (x != null) parts.add('X${x.toStringAsFixed(2)}');
    if (y != null) parts.add('Y${y.toStringAsFixed(2)}');
    if (z != null) parts.add('Z${z.toStringAsFixed(2)}');
    final cmd = 'G91\nG1 ${parts.join(' ')} F$feed\nG90';
    await sendGcode(cmd);
  }

  Future<void> pausePrint() async {
    final payload = {
      'print': {'sequence_id': (_seq++).toString(), 'command': 'pause'},
    };
    await publishRequest(payload);
  }

  Future<void> resumePrint() async {
    final payload = {
      'print': {'sequence_id': (_seq++).toString(), 'command': 'resume'},
    };
    await publishRequest(payload);
  }

  Future<void> cancelPrint() async {
    final payload = {
      'print': {
        'sequence_id': (_seq++).toString(),
        'command': 'stop', // some firmwares may expect 'cancel'
      },
    };
    await publishRequest(payload);
  }

  /// Set print speed factor using standard G-code (M220 S<percent>).
  /// Common range: 10..300 (%). Values are clamped conservatively.
  Future<void> setSpeedPercent(int percent) async {
    final p = percent.clamp(10, 300);
    await sendGcode('M220 S$p');
  }

  /// Optional: Set flow rate factor via G-code (M221 S<percent>).
  Future<void> setFlowPercent(int percent) async {
    final p = percent.clamp(10, 300);
    await sendGcode('M221 S$p');
  }

  /// Attempt to set a predefined speed profile. If a native profile command
  /// is unsupported on the target firmware, fall back to M220 percentage.
  Future<void> setSpeedProfile(BambuSpeedProfile profile) async {
    // Placeholder for a potential native command; many firmwares expose
    // only percentage control. If you know the exact payload, we can add it
    // here. For now, map to an M220 percent.
    await setSpeedPercent(profile.fallbackPercent);
  }

  /// Convenience: LED control example (chamber light on/off)
  Future<void> setChamberLight(bool on, {String ledNode = 'chamber_light'}) {
    final payload = {
      'system': {
        'sequence_id': (_seq++).toString(),
        'command': 'ledctrl',
        'led_node': ledNode,
        'led_mode': on ? 'on' : 'off',
        'led_on_time': 500,
        'led_off_time': 500,
        'loop_times': 1,
        'interval_time': 1000,
      },
    };
    return publishRequest(payload);
  }

  /// Convenience: request to start a print from a file already on SD.
  /// [sdPath] is a device-visible absolute path to the uploaded .3mf/.gcode.
  /// Note: Different firmware builds expect slightly different keys.
  /// If you receive a verification error, inspect the report and adjust.
  Future<void> startPrintFromSd(String sdPath) async {
    final payload = {
      'print': {
        'sequence_id': (_seq++).toString(),
        'command': 'start',
        // Many firmwares accept one of these forms — try a conservative one:
        'param': {'file': sdPath, 'is_lan': 1},
      },
    };
    await publishRequest(payload);
  }

  /// Request a full status push (use sparingly on some models).
  Future<void> requestPushAll() async {
    final payload = {
      'pushing': {
        'sequence_id': (_seq++).toString(),
        'command': 'pushall',
        'version': 1,
        'push_target': 1,
      },
    };
    await publishRequest(payload);
  }
}

class BambuCommandEvent {
  final String topic;
  final Map<String, dynamic> payload;
  final MqttQos qos;
  final DateTime timestamp;
  const BambuCommandEvent({
    required this.topic,
    required this.payload,
    required this.qos,
    required this.timestamp,
  });
}

/// Speed profile presets commonly seen on Bambu printers.
enum BambuSpeedProfile { silent, standard, sport, ludicrous }

extension BambuSpeedProfileX on BambuSpeedProfile {
  String get label {
    switch (this) {
      case BambuSpeedProfile.silent:
        return 'Silent';
      case BambuSpeedProfile.standard:
        return 'Standard';
      case BambuSpeedProfile.sport:
        return 'Sport';
      case BambuSpeedProfile.ludicrous:
        return 'Ludicrous';
    }
  }

  /// Conservative percent mappings as a fallback if no native profile API.
  int get fallbackPercent {
    switch (this) {
      case BambuSpeedProfile.silent:
        return 70;
      case BambuSpeedProfile.standard:
        return 100;
      case BambuSpeedProfile.sport:
        return 150;
      case BambuSpeedProfile.ludicrous:
        return 200;
    }
  }
}
