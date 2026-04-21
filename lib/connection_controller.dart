import 'dart:async';

import 'package:boomprint/bambu_lan.dart';
import 'package:boomprint/bambu_mqtt.dart';
import 'package:boomprint/printer_camera_streams.dart';
import 'package:boomprint/printer_firmware.dart';
import 'package:boomprint/printer_stream_manager.dart';
import 'package:boomprint/settings_manager.dart';
import 'package:flutter/foundation.dart';

class ConnectionController extends ChangeNotifier {
  String? currentStreamUrl;
  List<PrinterCameraStream> cameraStreams = const [];
  int selectedCameraIndex = 0;
  bool isStreaming = false;

  String printerStatus = 'Unknown';
  BambuPrintStatus? lastPrintStatus;
  String? firmwareVersion;
  PrinterFirmwareWarning? firmwareWarning;
  bool? chamberLightOn;
  bool mqttConnected = false;
  String lightNode = 'chamber_light';

  BambuMqtt? _mqttClient;
  StreamSubscription<BambuReportEvent>? _mqttReportSub;
  Timer? _lightConfirmTimer;
  bool? _pendingChamberLightOn;
  DateTime? _pendingLightConfirmationUntil;

  static const Duration lightConfirmDelay = Duration(seconds: 4);

  BambuMqtt? get mqttClient => _mqttClient;

  Future<void> refreshCameraStreamsFromSettings() async {
    final settings = await SettingsManager.loadSettings();
    final nextCameraStreams = buildPrinterCameraStreams(settings);
    final nextCameraIndex = nextCameraStreams.isEmpty
        ? 0
        : settings.selectedCameraIndex.clamp(0, nextCameraStreams.length - 1);

    cameraStreams = nextCameraStreams;
    selectedCameraIndex = nextCameraIndex;

    if (isStreaming && nextCameraStreams.isNotEmpty) {
      currentStreamUrl = nextCameraStreams[nextCameraIndex].url;
    }

    notifyListeners();
  }

  Future<String?> autoConnectUrl() async {
    final settings = await SettingsManager.loadSettings();
    await refreshCameraStreamsFromSettings();
    if (!settings.autoConnect || cameraStreams.isEmpty || isStreaming) {
      return null;
    }
    final selectedIndex = settings.selectedCameraIndex.clamp(
      0,
      cameraStreams.length - 1,
    );
    return cameraStreams[selectedIndex].url;
  }

  Future<void> startStreaming(String url) async {
    final settings = SettingsManager.settings;
    final streams = buildPrinterCameraStreams(settings);
    final selectedIndex = streams.indexWhere((stream) => stream.url == url);
    isStreaming = true;
    currentStreamUrl = url;
    cameraStreams = streams;
    selectedCameraIndex = selectedIndex >= 0 ? selectedIndex : 0;
    notifyListeners();

    unawaited(connectMqttFromSavedSettings(showErrors: false));
  }

  Future<void> stopStreaming() async {
    await _disposeMqtt();
    _clearPendingLightConfirmation();
    isStreaming = false;
    currentStreamUrl = null;
    printerStatus = 'Unknown';
    lastPrintStatus = null;
    firmwareVersion = null;
    firmwareWarning = null;
    chamberLightOn = null;
    mqttConnected = false;
    notifyListeners();
  }

  Future<String?> connectMqttFromSavedSettings({
    bool showErrors = false,
  }) async {
    final printerSettings = await PrinterStreamManager.getPrinterSettings();
    return _connectMqtt(
      printerIp: printerSettings.printerIp,
      accessCode: printerSettings.accessCode,
      serial: printerSettings.serialNumber,
      showErrors: showErrors,
    );
  }

  Future<String?> reconnectMqttIfNeeded() async {
    if (mqttConnected) {
      try {
        await _mqttClient?.requestPushAll();
      } catch (_) {
        // Best-effort refresh.
      }
      return null;
    }
    return connectMqttFromSavedSettings(showErrors: false);
  }

  Future<String?> setChamberLight(bool on) async {
    final client = _mqttClient;
    if (client == null || !client.isConnected) {
      return 'MQTT not connected yet.';
    }
    try {
      await client.setChamberLight(on, ledNode: lightNode);
      chamberLightOn = on;
      _pendingChamberLightOn = on;
      _pendingLightConfirmationUntil = DateTime.now().add(lightConfirmDelay);
      _lightConfirmTimer?.cancel();
      _lightConfirmTimer = Timer(lightConfirmDelay, () {
        if (_pendingChamberLightOn != on) return;
        _mqttClient?.requestPushAll().catchError((_) {});
      });
      notifyListeners();
      return null;
    } catch (e) {
      _clearPendingLightConfirmation();
      return 'Light command failed: $e';
    }
  }

  Future<String?> toggleChamberLight() {
    final target = !(chamberLightOn ?? false);
    return setChamberLight(target);
  }

  Future<String?> setSpeedPercent(int percent) async {
    final client = _mqttClient;
    if (client == null || !client.isConnected) {
      return 'MQTT not connected yet.';
    }
    try {
      await client.setSpeedPercent(percent);
      return null;
    } catch (e) {
      return 'Speed command failed: $e';
    }
  }

  Future<String?> setSpeedProfile(BambuSpeedProfile profile) async {
    final client = _mqttClient;
    if (client == null || !client.isConnected) {
      return 'MQTT not connected yet.';
    }
    try {
      await client.setSpeedProfile(profile);
      return null;
    } catch (e) {
      return 'Speed command failed: $e';
    }
  }

  String lightStatusLabel() {
    if (chamberLightOn == null) return 'Light Unknown';
    final nodeLabel = lightNode == 'work_light' ? 'Work' : 'Chamber';
    return chamberLightOn! ? '$nodeLabel Light On' : '$nodeLabel Light Off';
  }

  Future<String?> switchCameraSelection(int cameraIndex) async {
    if (cameraIndex < 0 ||
        cameraIndex >= cameraStreams.length ||
        cameraIndex == selectedCameraIndex) {
      return null;
    }
    selectedCameraIndex = cameraIndex;
    currentStreamUrl = cameraStreams[cameraIndex].url;
    SettingsManager.updateSettings((settings) {
      settings.selectedCameraIndex = cameraIndex;
    });
    await SettingsManager.saveSettings(SettingsManager.settings);
    notifyListeners();
    return currentStreamUrl;
  }

  void requestPushAll() {
    _mqttClient?.requestPushAll().catchError((_) {});
  }

  Future<void> disposeController() async {
    _clearPendingLightConfirmation();
    await _disposeMqtt();
  }

  Future<String?> _connectMqtt({
    required String printerIp,
    required String accessCode,
    required String? serial,
    required bool showErrors,
  }) async {
    await _disposeMqtt();

    final config = BambuLanConfig(
      printerIp: printerIp,
      accessCode: accessCode,
      serial: serial,
      mqttPort: 8883,
      allowBadCerts: true,
    );
    final client = BambuMqtt(config);
    _mqttClient = client;

    try {
      await client.connect();
      if (_mqttClient != client) {
        await client.dispose();
        return null;
      }
      mqttConnected = true;
      if (lastPrintStatus == null) {
        printerStatus = 'MQTT Connected';
      }
      _mqttReportSub = client.reportStream.listen(_handleMqttReportEvent);
      notifyListeners();
      client.requestPushAll().catchError((_) {});
      return null;
    } catch (e) {
      if (_mqttClient == client) {
        _mqttClient = null;
      }
      await client.dispose();
      printerStatus = 'MQTT Disconnected';
      mqttConnected = false;
      notifyListeners();
      return showErrors ? 'MQTT connection failed: $e' : null;
    }
  }

  Future<void> _disposeMqtt() async {
    await _mqttReportSub?.cancel();
    _mqttReportSub = null;
    final client = _mqttClient;
    _mqttClient = null;
    if (client != null) {
      await client.dispose();
    }
  }

  void _handleMqttReportEvent(BambuReportEvent event) {
    final detectedNode = _detectLightNode(event.json);
    if (detectedNode != null) {
      lightNode = detectedNode;
    }
    if (event.firmwareVersion != null &&
        event.firmwareVersion!.trim().isNotEmpty) {
      firmwareVersion = event.firmwareVersion!.trim();
    }
    firmwareWarning = evaluateFirmwareWarning(firmwareVersion);

    final lightState = _extractLightStateForNode(event.json, lightNode);
    final pendingLight = _pendingChamberLightOn;
    final confirmUntil = _pendingLightConfirmationUntil;
    final now = DateTime.now();

    if (event.printStatus != null) {
      final previous = lastPrintStatus;
      final merged = _mergePrintStatus(event.printStatus!, previous);
      final pct = merged.percent != null ? '${merged.percent}%' : '';
      final left = merged.remainingMinutes != null
          ? ' • ${merged.remainingMinutes}m left'
          : '';
      printerStatus =
          '${merged.gcodeState}${pct.isNotEmpty ? ' $pct' : ''}$left';
      lastPrintStatus = merged;
    } else if (event.type != null && event.type != 'SYSTEM') {
      printerStatus = event.type!;
    }

    if (lightState != null) {
      final waitingForConfirm =
          pendingLight != null &&
          lightState != pendingLight &&
          confirmUntil != null &&
          now.isBefore(confirmUntil);
      if (!waitingForConfirm) {
        chamberLightOn = lightState;
        if (pendingLight != null && lightState == pendingLight) {
          _clearPendingLightConfirmation();
        } else if (confirmUntil == null || now.isAfter(confirmUntil)) {
          _clearPendingLightConfirmation();
        }
      }
    }
    if (!mqttConnected) {
      mqttConnected = true;
    }
    notifyListeners();
  }

  void _clearPendingLightConfirmation() {
    _lightConfirmTimer?.cancel();
    _lightConfirmTimer = null;
    _pendingChamberLightOn = null;
    _pendingLightConfirmationUntil = null;
  }
}

String? _detectLightNode(Map<String, dynamic> json) {
  final print = json['print'];
  if (print is Map) {
    for (final key in ['work_light', 'worklight', 'chamber_light']) {
      if (print.containsKey(key)) {
        return key == 'worklight' ? 'work_light' : key;
      }
    }
  }
  final system = json['system'];
  if (system is Map) {
    for (final key in ['work_light', 'worklight', 'chamber_light']) {
      if (system.containsKey(key)) {
        return key == 'worklight' ? 'work_light' : key;
      }
    }
  }
  return null;
}

bool? _extractLightStateForNode(Map<String, dynamic> json, String node) {
  dynamic v;
  final print = json['print'];
  if (print is Map) {
    v = print[node];
    if (v == null && node == 'work_light') v = print['worklight'];
  }
  v ??= json[node];
  if (v == null && node == 'work_light') v = json['worklight'];
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (['1', 'on', 'true', 'enabled'].contains(s)) return true;
    if (['0', 'off', 'false', 'disabled'].contains(s)) return false;
  }
  return null;
}

BambuPrintStatus _mergePrintStatus(
  BambuPrintStatus next,
  BambuPrintStatus? prev,
) {
  if (prev == null) return next;
  T? keep<T>(T? a, T? b) => a ?? b;
  final state = next.gcodeState.trim().isNotEmpty
      ? next.gcodeState
      : prev.gcodeState;
  return BambuPrintStatus(
    gcodeState: state,
    percent: keep(next.percent, prev.percent),
    remainingMinutes: keep(next.remainingMinutes, prev.remainingMinutes),
    gcodeFile: keep(next.gcodeFile, prev.gcodeFile),
    layer: keep(next.layer, prev.layer),
    totalLayers: keep(next.totalLayers, prev.totalLayers),
    bedTemp: keep(next.bedTemp, prev.bedTemp),
    bedTarget: keep(next.bedTarget, prev.bedTarget),
    nozzleTemp: keep(next.nozzleTemp, prev.nozzleTemp),
    nozzleTarget: keep(next.nozzleTarget, prev.nozzleTarget),
    chamberTemp: keep(next.chamberTemp, prev.chamberTemp),
    nozzleType: keep(next.nozzleType, prev.nozzleType),
    nozzleDiameter: keep(next.nozzleDiameter, prev.nozzleDiameter),
    speedLevel: keep(next.speedLevel, prev.speedLevel),
    speedMag: keep(next.speedMag, prev.speedMag),
    subtaskName: keep(next.subtaskName, prev.subtaskName),
    taskId: keep(next.taskId, prev.taskId),
    jobId: keep(next.jobId, prev.jobId),
    wifiSignal: keep(next.wifiSignal, prev.wifiSignal),
  );
}
