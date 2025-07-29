import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:ftpconnect/ftpconnect.dart';
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
  int _seq = 1;
  String? _activeSerial;

  Stream<BambuReportEvent> get reportStream => _reports.stream;
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
    } on Exception catch (e) {
      _client.disconnect();
      rethrow;
    }

    // Subscribe to reports
    _activeSerial = config.serial;
    final String topic = _activeSerial != null
        ? 'device/${_activeSerial!}/report'
        : 'device/+/report';

    _client.subscribe(topic, MqttQos.atLeastOnce);

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

          if (type != 'PRINT' && type != 'SYSTEM') {
            // Debug/log other types

            _reports.add(e);
          }
        } catch (_) {
          // Non-JSON message — ignore
        }
      }
    });
  }

  String _clientId() => 'bambu_dart_${DateTime.now().millisecondsSinceEpoch}';

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
      _activeSerial = m.group(1);
    } else {
      // try payload fields often containing serial/dev id (best-effort)
      for (final key in ['sn', 'serial', 'dev_id', 'usn']) {
        final v = j[key];
        if (v is String && v.isNotEmpty) {
          _activeSerial = v;
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
    final sn = _activeSerial ?? config.serial;
    if (sn == null) {
      throw StateError(
        'Printer serial is unknown; provide BambuLanConfig.serial or wait for first report.',
      );
    }
    final topic = 'device/$sn/request';
    final b = MqttClientPayloadBuilder();
    b.addUTF8String(jsonEncode(payload));
    _client.publishMessage(topic, qos, b.payload!);
  }

  /// Convenience: LED control example (chamber light on/off)
  Future<void> setChamberLight(bool on) {
    final payload = {
      'system': {
        'sequence_id': (_seq++).toString(),
        'command': 'ledctrl',
        'led_node': 'chamber_light',
        'led_mode': on ? 'on' : 'off',
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
}
