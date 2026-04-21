import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:boomprint/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:boomprint/bambu_lan.dart';
import 'package:boomprint/bambu_mqtt.dart';
import 'package:boomprint/feature_flags.dart';
import 'package:boomprint/connection_preflight.dart';
import 'package:boomprint/connection_controller.dart';
import 'package:boomprint/printer_firmware.dart';
import 'package:boomprint/settings_manager.dart';
import 'package:boomprint/monitoring_alerts.dart';
import 'package:boomprint/sensitive_auth.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'settings_page.dart';
import 'mqtt_control_page.dart';
import 'ftp_browser_page.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'window_drag_controller.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final cli = _parseCliArgs(args);
  await SettingsManager.loadSettings(
    overridePath: cli.configPath,
    overridePrinterIp: cli.printerIp,
    overrideSpecialCode: cli.accessCode,
    overrideSerialNumber: cli.serialNumber,
    overrideSelectedFormat: cli.format,
    overrideCustomUrl: cli.customUrl,
    overrideGenericRtspUsername: cli.genericRtspUsername,
    overrideGenericRtspPassword: cli.genericRtspPassword,
    overrideGenericRtspPath: cli.genericRtspPath,
    overrideGenericRtspPort: cli.genericRtspPort,
    overrideGenericRtspSecure: cli.genericRtspSecure,
  ); // Load and cache settings
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class _CliConfig {
  final String? configPath;
  final String? printerIp;
  final String? accessCode;
  final String? serialNumber;
  final String? format;
  final String? customUrl;
  final String? genericRtspUsername;
  final String? genericRtspPassword;
  final String? genericRtspPath;
  final int? genericRtspPort;
  final bool? genericRtspSecure;

  const _CliConfig({
    this.configPath,
    this.printerIp,
    this.accessCode,
    this.serialNumber,
    this.format,
    this.customUrl,
    this.genericRtspUsername,
    this.genericRtspPassword,
    this.genericRtspPath,
    this.genericRtspPort,
    this.genericRtspSecure,
  });
}

_CliConfig _parseCliArgs(List<String> args) {
  String? configPath;
  String? printerIp;
  String? accessCode;
  String? serialNumber;
  String? format;
  String? customUrl;
  String? genericRtspUsername;
  String? genericRtspPassword;
  String? genericRtspPath;
  int? genericRtspPort;
  bool? genericRtspSecure;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String? value;

    if (arg.contains('=')) {
      final parts = arg.split('=');
      if (parts.length >= 2) {
        value = parts.sublist(1).join('=');
      }
    } else if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
      value = args[i + 1];
    }

    switch (arg.split('=').first) {
      case '--config':
        configPath = value;
        if (value != null && !arg.contains('=')) i++;
        break;
      case '--printer-ip':
        printerIp = value;
        if (value != null && !arg.contains('=')) i++;
        break;
      case '--access-code':
        accessCode = value;
        if (value != null && !arg.contains('=')) i++;
        break;
      case '--serial':
        serialNumber = value;
        if (value != null && !arg.contains('=')) i++;
        break;
      case '--format':
        format = value;
        if (value != null && !arg.contains('=')) i++;
        break;
      case '--custom-url':
        customUrl = value;
        if (value != null && !arg.contains('=')) i++;
        break;
      case '--rtsp-username':
        genericRtspUsername = value;
        if (value != null && !arg.contains('=')) i++;
        break;
      case '--rtsp-password':
        genericRtspPassword = value;
        if (value != null && !arg.contains('=')) i++;
        break;
      case '--rtsp-path':
        genericRtspPath = value;
        if (value != null && !arg.contains('=')) i++;
        break;
      case '--rtsp-port':
        if (value != null) {
          genericRtspPort = int.tryParse(value);
        }
        if (value != null && !arg.contains('=')) i++;
        break;
      case '--rtsp-secure':
        genericRtspSecure = value == null
            ? true
            : switch (value.trim().toLowerCase()) {
                '1' || 'true' || 'yes' || 'on' => true,
                '0' || 'false' || 'no' || 'off' => false,
                _ => true,
              };
        if (value != null && !arg.contains('=')) i++;
        break;
      default:
        break;
    }
  }

  return _CliConfig(
    configPath: configPath,
    printerIp: printerIp,
    accessCode: accessCode,
    serialNumber: serialNumber,
    format: format,
    customUrl: customUrl,
    genericRtspUsername: genericRtspUsername,
    genericRtspPassword: genericRtspPassword,
    genericRtspPath: genericRtspPath,
    genericRtspPort: genericRtspPort,
    genericRtspSecure: genericRtspSecure,
  );
}

class MyApp extends StatelessWidget {
  final GlobalKey? rootBoundaryKey;

  const MyApp({super.key, this.rootBoundaryKey});

  @override
  Widget build(BuildContext context) {
    final app = ChangeNotifierProvider(
      create: (_) => ConnectionController(),
      child: MaterialApp(
        title: AppStrings.appDisplayName,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const StreamPage(),
        debugShowCheckedModeBanner: false,
      ),
    );

    if (rootBoundaryKey == null) {
      return app;
    }

    return RepaintBoundary(key: rootBoundaryKey, child: app);
  }
}

class StreamPage extends StatefulWidget {
  const StreamPage({super.key});

  @override
  State<StreamPage> createState() => _StreamPageState();
}

bool isAccelSupported({TargetPlatform? platformOverride}) {
  return true;
}

class _StreamPageState extends State<StreamPage> with WidgetsBindingObserver {
  late final Player player;
  late VideoController controller;
  //final screenshotController = ScreenshotController();
  bool _autoLightWhilePrinting = false;
  bool _wasPrinting = false;
  bool _speedCommandBusy = false;
  bool _mqttControlsEnabled = false;
  bool _hardwareAccelerationEnabled = true;

  // Stall detection & reconnect
  Timer? _stallTimer;
  Duration _lastPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.now();
  bool _reconnecting = false;
  int _reconnectAttempts = 0;
  static const Duration _stallTimeout = Duration(seconds: 8);
  static const int _maxReconnectAttempts = 6;

  // Buffering / progress & error subscriptions
  bool _buffering = false;
  Duration _bufferPosition = Duration.zero;
  Duration _mediaDuration = Duration.zero;
  double? _bufferFraction; // null = indeterminate
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration>? _bufferPosSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<String>? _errorSub;
  DateTime? _lastErrorToastAt;
  StreamSubscription<bool>? _playingSub;
  bool _showVideoControls = false;
  bool _isPlaying = false;
  Timer? _controlsHideTimer;
  Timer? _autoplayKickTimer;
  Timer? _resumeProbeTimer;
  ConnectionController? _listeningController;
  BambuPrintStatus? _lastObservedPrintStatus;

  ConnectionController get _connection => context.read<ConnectionController>();

  Future<Directory> _resolveScreenshotDir() async {
    try {
      if (Platform.isAndroid) {
        // Use app-specific external storage (no special permissions required)
        final base = await getExternalStorageDirectory();
        final root = base ?? await getApplicationDocumentsDirectory();
        return Directory(path.join(root.path, 'Pictures', 'BambuScreenshots'));
      }
      if (Platform.isIOS) {
        final base = await getApplicationDocumentsDirectory();
        return Directory(path.join(base.path, 'BambuScreenshots'));
      }
      // Desktop/web fallbacks
      final downloads = await getDownloadsDirectory();
      final base = downloads ?? await getApplicationDocumentsDirectory();
      return Directory(path.join(base.path, 'BambuScreenshots'));
    } catch (_) {
      // Last-resort: app documents
      final base = await getApplicationDocumentsDirectory();
      return Directory(path.join(base.path, 'BambuScreenshots'));
    }
  }

  Future<void> _takeScreenshot() async {
    try {
      // Capture screenshot using the screenshot package
      //final screenshotData = await screenshotController.capture();
      final screenshotData = await player.screenshot();

      if (screenshotData != null) {
        // Resolve a platform-appropriate, writable directory
        final screenshotDir = await _resolveScreenshotDir();
        await screenshotDir.create(recursive: true);

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filename = 'screenshot_$timestamp.png';
        final filePath = path.join(screenshotDir.path, filename);

        // Save the screenshot data
        final file = File(filePath);
        await file.writeAsBytes(screenshotData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Screenshot saved to $filePath'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 72),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to capture screenshot'),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.fromLTRB(16, 0, 16, 72),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Screenshot failed: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 72),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _setChamberLight(bool on, {bool showErrors = true}) async {
    final error = await _connection.setChamberLight(on);
    if (error != null && showErrors && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _toggleChamberLight() {
    final target = !(_connection.chamberLightOn ?? false);
    _setChamberLight(target);
  }

  bool _isPrintingState(String state) {
    switch (state.toUpperCase()) {
      case 'RUNNING':
      case 'PREPARE':
      case 'PAUSED':
        return true;
      default:
        return false;
    }
  }

  void _handleAutoLight(BambuPrintStatus ps, {bool force = false}) {
    final printing = _isPrintingState(ps.gcodeState);
    final shouldEnable =
        _autoLightWhilePrinting && printing && (force || !_wasPrinting);
    _wasPrinting = printing;
    if (shouldEnable && _connection.chamberLightOn != true) {
      _setChamberLight(true, showErrors: false);
    }
  }

  String _lightStatusLabel() {
    return _connection.lightStatusLabel();
  }

  int _currentSpeedPercent(BambuPrintStatus? ps) {
    final mag = ps?.speedMag;
    if (mag != null && mag > 0) {
      return mag;
    }
    return 100;
  }

  BambuSpeedProfile _currentSpeedProfile(BambuPrintStatus? ps) {
    final level = ps?.speedLevel;
    switch (level) {
      case 1:
        return BambuSpeedProfile.silent;
      case 2:
        return BambuSpeedProfile.standard;
      case 3:
        return BambuSpeedProfile.sport;
      case 4:
        return BambuSpeedProfile.ludicrous;
    }

    final percent = _currentSpeedPercent(ps);
    if (percent <= 80) return BambuSpeedProfile.silent;
    if (percent >= 180) return BambuSpeedProfile.ludicrous;
    if (percent >= 130) return BambuSpeedProfile.sport;
    return BambuSpeedProfile.standard;
  }

  Future<void> _setSpeedProfile(BambuSpeedProfile profile) async {
    if (_speedCommandBusy) return;
    setState(() => _speedCommandBusy = true);
    try {
      final error = await _connection.setSpeedProfile(profile);
      if (error != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      } else {
        _connection.requestPushAll();
      }
    } finally {
      if (mounted) {
        setState(() => _speedCommandBusy = false);
      }
    }
  }

  Widget _buildSpeedControls({
    required BuildContext context,
    required BambuPrintStatus? printStatus,
    required bool compactLayout,
  }) {
    final currentProfile = _currentSpeedProfile(printStatus);
    final currentPercent = _currentSpeedPercent(printStatus);
    final enabled = _connection.mqttConnected && !_speedCommandBusy;
    final button = IgnorePointer(
      child: OutlinedButton.icon(
        onPressed: enabled ? () {} : null,
        icon: _speedCommandBusy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.speed),
        label: Text('${currentProfile.label} $currentPercent%'),
        style: compactLayout
            ? OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              )
            : null,
      ),
    );

    if (!enabled) {
      return button;
    }

    return PopupMenuButton<BambuSpeedProfile>(
      tooltip: 'Change print speed',
      onSelected: _setSpeedProfile,
      itemBuilder: (context) => BambuSpeedProfile.values
          .map(
            (profile) => PopupMenuItem<BambuSpeedProfile>(
              value: profile,
              child: Row(
                children: [
                  Icon(
                    profile == currentProfile
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${profile.label} ${profile.fallbackPercent}%'),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: button,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    PlayerConfiguration config = PlayerConfiguration(
      logLevel: MPVLogLevel.debug,
    );

    player = Player(configuration: config);
    _listeningController = _connection;
    _listeningController!.addListener(_handleConnectionStateChanged);
    _rebuildVideoController();
    _setupPlayerListeners();
    unawaited(_loadUiSettings());
    unawaited(_attemptAutoConnect());
    unawaited(MonitoringAlerts.requestAndroidNotificationPermission());
  }

  void _rebuildVideoController() {
    final enabled = _hardwareAccelerationEnabled && isAccelSupported();
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: enabled,
        hwdec: enabled ? 'auto' : 'no',
      ),
    );
  }

  Future<void> _loadUiSettings() async {
    final connection = _connection;
    final settings = await SettingsManager.loadSettings();
    final prevHw = _hardwareAccelerationEnabled;
    final nextHw = settings.hardwareAccelerationEnabled;
    await connection.refreshCameraStreamsFromSettings();
    await WindowChromeController.setLinuxSystemDecorations(
      settings.linuxUseSystemWindowDecorations,
    );
    if (!mounted) return;
    if (prevHw != nextHw) {
      _hardwareAccelerationEnabled = nextHw;
      _rebuildVideoController();
      if (connection.isStreaming && connection.currentStreamUrl != null) {
        try {
          await _openMediaAndEnsurePlaying(connection.currentStreamUrl!);
        } catch (_) {
          // Keep current stream state; existing error handling will surface issues.
        }
      }
    }
    final nextCameraUrl = connection.cameraStreams.isEmpty
        ? null
        : connection.cameraStreams[connection.selectedCameraIndex].url;
    setState(() {
      _mqttControlsEnabled = settings.mqttControlsEnabled;
      _hardwareAccelerationEnabled = nextHw;
    });

    if (connection.isStreaming &&
        nextCameraUrl != null &&
        connection.currentStreamUrl != nextCameraUrl) {
      try {
        await _openMediaAndEnsurePlaying(nextCameraUrl);
      } catch (_) {
        // Keep current stream state; existing error handling will surface issues.
      }
    }
  }

  Future<void> _attemptAutoConnect() async {
    final url = await _connection.autoConnectUrl();
    if (!mounted || url == null) return;
    _onConnect(url);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stallTimer?.cancel();
    _bufferingSub?.cancel();
    _bufferPosSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    _playingSub?.cancel();
    _controlsHideTimer?.cancel();
    _autoplayKickTimer?.cancel();
    _resumeProbeTimer?.cancel();
    _listeningController?.removeListener(_handleConnectionStateChanged);
    player.dispose();
    unawaited(_connection.disposeController());
    super.dispose();
  }

  void _handleConnectionStateChanged() {
    final current = _connection.lastPrintStatus;
    if (current != null && current != _lastObservedPrintStatus) {
      _notifyForPrintStateTransition(_lastObservedPrintStatus, current);
      _handleAutoLight(current);
      _lastObservedPrintStatus = current;
    } else if (current == null) {
      _lastObservedPrintStatus = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _handleAppBackgrounded();
        break;
    }
  }

  Future<void> _startStream(String url) async {
    final connection = _connection;
    await connection.startStreaming(url);
    _resetStallMonitor();

    // Start video stream first (independent of MQTT)
    try {
      await _openMediaAndEnsurePlaying(url);
      _startStallMonitor();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start stream: $e')));
        await connection.stopStreaming();
      }
      return;
    }
  }

  Future<void> _stopStream() async {
    await player.stop();
    _resumeProbeTimer?.cancel();
    await _connection.stopStreaming();
    _stallTimer?.cancel();
    setState(() {
      _wasPrinting = false;
    });
  }

  void _handleAppBackgrounded() {
    _resumeProbeTimer?.cancel();
    _autoplayKickTimer?.cancel();
    _stallTimer?.cancel();
    _lastPosition = player.state.position;
    _lastProgressAt = DateTime.now();
  }

  Future<void> _handleAppResumed() async {
    final connection = _connection;
    if (!connection.isStreaming || connection.currentStreamUrl == null) {
      return;
    }

    final url = connection.currentStreamUrl!;
    _lastPosition = player.state.position;
    _lastProgressAt = DateTime.now();

    try {
      await player.play();
    } catch (_) {
      // Resume probing below will force a reconnect if playback is still stale.
    }

    _startAutoplayKick(url);
    _startStallMonitor();
    _scheduleResumeProbe(url);

    unawaited(connection.reconnectMqttIfNeeded());
  }

  void _scheduleResumeProbe(String url) {
    _resumeProbeTimer?.cancel();
    final probePosition = player.state.position;
    _resumeProbeTimer = Timer(const Duration(seconds: 2), () {
      final connection = _connection;
      if (!mounted ||
          !connection.isStreaming ||
          connection.currentStreamUrl != url) {
        return;
      }
      final state = player.state;
      final advanced = state.position > probePosition;
      if (state.playing && advanced) {
        return;
      }
      _attemptReconnect(
        reason: 'resume recovery',
        immediate: true,
        resetAttempts: true,
      );
    });
  }

  void _notifyForPrintStateTransition(
    BambuPrintStatus? previous,
    BambuPrintStatus current,
  ) {
    if (previous == null) {
      return;
    }

    final previousState = previous.gcodeState.trim().toUpperCase();
    final currentState = current.gcodeState.trim().toUpperCase();
    if (currentState.isEmpty || previousState == currentState) {
      return;
    }

    if (currentState == 'PAUSED') {
      _emitMonitoringAttention(
        title: 'Print paused',
        body: _monitoringBody(
          current,
          fallback: 'The current print is paused.',
        ),
      );
      return;
    }

    if (_isErrorPrintState(currentState)) {
      _emitMonitoringAttention(
        title: 'Printer needs attention',
        body: _monitoringBody(
          current,
          fallback: 'Printer reported state $currentState.',
        ),
      );
      return;
    }

    if (_isSuccessPrintState(currentState) &&
        _isActivePrintState(previousState)) {
      _emitMonitoringSuccess(
        title: 'Print finished',
        body: _monitoringBody(
          current,
          fallback: 'The monitored print completed successfully.',
        ),
      );
    }
  }

  bool _isActivePrintState(String state) {
    switch (state) {
      case 'RUNNING':
      case 'PREPARE':
      case 'PAUSED':
        return true;
      default:
        return false;
    }
  }

  bool _isSuccessPrintState(String state) {
    switch (state) {
      case 'FINISH':
      case 'FINISHED':
      case 'COMPLETE':
      case 'COMPLETED':
      case 'SUCCESS':
        return true;
      default:
        return false;
    }
  }

  bool _isErrorPrintState(String state) {
    switch (state) {
      case 'FAILED':
      case 'FAIL':
      case 'ERROR':
      case 'EXCEPTION':
      case 'CANCELED':
      case 'CANCELLED':
      case 'ABORTED':
      case 'STOPPED':
      case 'ALARM':
        return true;
      default:
        return state.contains('ERROR') ||
            state.contains('FAIL') ||
            state.contains('EXCEPTION');
    }
  }

  String _monitoringBody(BambuPrintStatus status, {required String fallback}) {
    final name = status.subtaskName ?? status.gcodeFile;
    if (name != null && name.trim().isNotEmpty) {
      return name.trim();
    }
    return fallback;
  }

  void _emitMonitoringAttention({required String title, required String body}) {
    if (Platform.isAndroid) {
      unawaited(
        MonitoringAlerts.showAndroidNotification(
          title: title,
          body: body,
          success: false,
        ),
      );
      return;
    }
    unawaited(MonitoringAlerts.playAttentionSound());
  }

  void _emitMonitoringSuccess({required String title, required String body}) {
    if (Platform.isAndroid) {
      unawaited(
        MonitoringAlerts.showAndroidNotification(
          title: title,
          body: body,
          success: true,
        ),
      );
      return;
    }
    unawaited(MonitoringAlerts.playSuccessSound());
  }

  void _setupPlayerListeners() {
    // Cancel existing subscriptions if any
    _bufferingSub?.cancel();
    _bufferPosSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    _playingSub?.cancel();

    _bufferingSub = player.stream.buffering.listen((b) {
      if (!mounted) return;
      setState(() {
        _buffering = b;
      });
    });
    _bufferPosSub = player.stream.buffer.listen((d) {
      _bufferPosition = d;
      _recomputeBufferFraction();
    });
    _durationSub = player.stream.duration.listen((d) {
      _mediaDuration = d;
      _recomputeBufferFraction();
    });
    _errorSub = player.stream.error.listen((msg) {
      // Throttle error toasts to avoid spam
      final now = DateTime.now();
      if (_lastErrorToastAt == null ||
          now.difference(_lastErrorToastAt!) > const Duration(seconds: 5)) {
        _lastErrorToastAt = now;
        if (mounted) {
          final userMsg = _friendlyError(msg);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(userMsg)));
        }
      }
      _attemptReconnect(reason: 'error: $msg');
    });
    _playingSub = player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() {
        _isPlaying = playing;
      });
    });
  }

  void _showControlsTemporarily() {
    if (!mounted) return;
    setState(() {
      _showVideoControls = true;
    });
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _showVideoControls = false;
      });
    });
  }

  void _recomputeBufferFraction() {
    if (!mounted) return;
    if (_mediaDuration.inMilliseconds > 0) {
      final f = _bufferPosition.inMilliseconds / _mediaDuration.inMilliseconds;
      setState(() {
        _bufferFraction = f.clamp(0.0, 1.0);
      });
    } else {
      setState(() {
        _bufferFraction = null; // indeterminate
      });
    }
  }

  String _friendlyError(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('401') || m.contains('unauthorized')) {
      return 'Stream error: Unauthorized (check special code / credentials).';
    }
    if (m.contains('403') || m.contains('forbidden')) {
      return 'Stream error: Access forbidden (printer or network blocked).';
    }
    if (m.contains('timed out') || m.contains('timeout')) {
      return 'Stream error: Connection timed out (printer offline or unreachable).';
    }
    if (m.contains('host') && m.contains('not') && m.contains('resolve')) {
      return 'Stream error: Host not found (check printer IP).';
    }
    if (m.contains('connection refused') || m.contains('refused')) {
      return 'Stream error: Connection refused (service not available).';
    }
    if (m.contains('tls') || m.contains('ssl') || m.contains('certificate')) {
      return 'Stream error: TLS/SSL problem (certificate or protocol).';
    }
    return 'Stream error: $raw';
  }

  void _resetStallMonitor() {
    _lastPosition = Duration.zero;
    _lastProgressAt = DateTime.now();
    _reconnecting = false;
    _reconnectAttempts = 0;
  }

  void _startStallMonitor() {
    _stallTimer?.cancel();
    _stallTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final connection = _connection;
      if (!connection.isStreaming || connection.currentStreamUrl == null) {
        return;
      }
      final state = player.state;
      // Only consider stalls while playing & not buffering.
      if (!state.playing || state.buffering) return;

      final position = state.position;
      // Detect forward progress.
      if (position > _lastPosition) {
        _lastPosition = position;
        _lastProgressAt = DateTime.now();
        return;
      }

      // No progress for too long -> reconnect
      final stalledFor = DateTime.now().difference(_lastProgressAt);
      if (stalledFor >= _stallTimeout) {
        _attemptReconnect(reason: 'stalled ${stalledFor.inSeconds}s');
      }
    });

    // Error events are handled in _setupPlayerListeners.
  }

  void _attemptReconnect({
    required String reason,
    bool immediate = false,
    bool resetAttempts = false,
  }) {
    final connection = _connection;
    if (_reconnecting || connection.currentStreamUrl == null) return;
    if (resetAttempts) {
      _reconnectAttempts = 0;
    }
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      // Give up for now.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stream lost ($reason). Giving up.')),
        );
      }
      return;
    }
    _reconnecting = true;
    final attempt = _reconnectAttempts + 1;
    // Exponential backoff: 2, 4, 8, 16... seconds (capped at 30s)
    final delaySeconds = immediate
        ? 0
        : (2 << (_reconnectAttempts)).clamp(2, 30);

    if (mounted && !immediate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reconnecting (attempt $attempt) in ${delaySeconds}s...',
          ),
        ),
      );
    }

    Future.delayed(Duration(seconds: delaySeconds), () async {
      if (!connection.isStreaming || connection.currentStreamUrl == null) {
        _reconnecting = false;
        return;
      }
      try {
        await _openMediaAndEnsurePlaying(connection.currentStreamUrl!);
        _reconnectAttempts = 0;
        _reconnecting = false;
        _lastPosition = Duration.zero;
        _lastProgressAt = DateTime.now();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reconnected to stream.')),
          );
        }
      } catch (e) {
        _reconnectAttempts++;
        _reconnecting = false;
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Reconnect failed: $e')));
        }
      }
    });
  }

  Future<void> _openMediaAndEnsurePlaying(String url) async {
    await player.open(Media(url), play: true);
    await player.play();
    _startAutoplayKick(url);
  }

  Future<void> _switchCamera(int cameraIndex) async {
    final connection = _connection;
    if (!connection.isStreaming ||
        cameraIndex < 0 ||
        cameraIndex >= connection.cameraStreams.length ||
        cameraIndex == connection.selectedCameraIndex) {
      return;
    }
    final nextStream = await connection.switchCameraSelection(cameraIndex);
    if (nextStream == null) return;
    _resetStallMonitor();
    try {
      await _openMediaAndEnsurePlaying(nextStream);
      _startStallMonitor();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Camera switch failed: $e')));
      }
    }
  }

  void _startAutoplayKick(String url) {
    _autoplayKickTimer?.cancel();
    final startedAt = DateTime.now();
    _autoplayKickTimer = Timer.periodic(const Duration(milliseconds: 350), (
      timer,
    ) async {
      final connection = _connection;
      if (!mounted ||
          !connection.isStreaming ||
          connection.currentStreamUrl != url) {
        timer.cancel();
        return;
      }
      final state = player.state;
      final elapsed = DateTime.now().difference(startedAt);

      // Stop once playback is really moving.
      if (state.playing && state.position > Duration.zero) {
        timer.cancel();
        return;
      }

      // Give up after a short window to avoid endless retries.
      if (elapsed > const Duration(seconds: 8)) {
        timer.cancel();
        return;
      }

      // GTK4 can transiently report paused right after output rebind.
      // Keep nudging play during startup until frames advance.
      if (!state.playing && !state.buffering) {
        await player.play();
      }
    });
  }

  Future<void> _openSettings() async {
    if (SensitiveAuth.isAndroid) {
      final authenticated = await SensitiveAuth.authenticate(
        reason: 'Authenticate to open printer settings.',
      );
      if (!authenticated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Settings access was not approved.')),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(onConnect: _onConnect),
      ),
    );
    await _loadUiSettings();
  }

  void _onConnect(String url) {
    _startStream(url);
  }

  bool _isMobileLandscape(BuildContext context) {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return false;
    }
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  Widget _buildVideoSurface({required bool compactLayout}) {
    final connection = context.watch<ConnectionController>();
    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _showVideoControls = true;
        });
        _controlsHideTimer?.cancel();
      },
      onExit: (_) {
        setState(() {
          _showVideoControls = false;
        });
        _controlsHideTimer?.cancel();
      },
      child: GestureDetector(
        onTap: _showControlsTemporarily,
        child: Stack(
          children: [
            Positioned.fill(child: Video(controller: controller)),
            if (connection.lastPrintStatus != null)
              Positioned(
                left: 12,
                top: 12,
                child: _PrintOverlayStatus(status: connection.lastPrintStatus),
              ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_showVideoControls,
                child: AnimatedOpacity(
                  opacity: _showVideoControls ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    color: Colors.black.withOpacity(0.2),
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(48),
                        ),
                        child: IconButton(
                          iconSize: compactLayout ? 44 : 56,
                          color: Colors.white,
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                          onPressed: () {
                            if (_isPlaying) {
                              player.pause();
                            } else {
                              player.play();
                            }
                            _showControlsTemporarily();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamActions({required bool compactLayout}) {
    final connection = context.watch<ConnectionController>();
    final hasMultipleCameras = connection.cameraStreams.length > 1;
    final printStatus = connection.lastPrintStatus;
    final lightButton = OutlinedButton.icon(
      onPressed: (connection.mqttConnected || connection.chamberLightOn != null)
          ? _toggleChamberLight
          : null,
      icon: Icon(
        connection.chamberLightOn == true
            ? Icons.lightbulb
            : Icons.lightbulb_outline,
      ),
      label: Text(_lightStatusLabel()),
    );
    final autoLightToggle = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withOpacity(compactLayout ? 0.35 : 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compactLayout ? 10 : 12,
          vertical: compactLayout ? 4 : 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              compactLayout ? 'Auto light' : 'Auto light while printing',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(width: 8),
            Switch(
              value: _autoLightWhilePrinting,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (value) {
                setState(() => _autoLightWhilePrinting = value);
                final ps = connection.lastPrintStatus;
                if (value && ps != null) {
                  _handleAutoLight(ps, force: true);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (compactLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasMultipleCameras) ...[
            Row(
              children: [
                const Text('Camera'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<int>(
                    value: connection.selectedCameraIndex,
                    isExpanded: true,
                    items: connection.cameraStreams
                        .map(
                          (stream) => DropdownMenuItem<int>(
                            value: stream.index,
                            child: Text(stream.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      _switchCamera(value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          ElevatedButton.icon(
            onPressed: _stopStream,
            icon: const Icon(Icons.stop),
            label: const Text('Disconnect'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _takeScreenshot,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Screenshot'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
            label: const Text('Settings'),
          ),
          const SizedBox(height: 8),
          lightButton,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: autoLightToggle),
          const SizedBox(height: 8),
          _buildSpeedControls(
            context: context,
            printStatus: printStatus,
            compactLayout: compactLayout,
          ),
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasMultipleCameras)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withOpacity(0.22),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Camera'),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: connection.selectedCameraIndex,
                    underline: const SizedBox.shrink(),
                    items: connection.cameraStreams
                        .map(
                          (stream) => DropdownMenuItem<int>(
                            value: stream.index,
                            child: Text(stream.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      _switchCamera(value);
                    },
                  ),
                ],
              ),
            ),
          ),
        ElevatedButton.icon(
          onPressed: _stopStream,
          icon: const Icon(Icons.stop),
          label: const Text('Disconnect'),
        ),
        OutlinedButton.icon(
          onPressed: _takeScreenshot,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Screenshot'),
        ),
        OutlinedButton.icon(
          onPressed: _openSettings,
          icon: const Icon(Icons.settings),
          label: const Text('Settings'),
        ),
        lightButton,
        autoLightToggle,
        _buildSpeedControls(
          context: context,
          printStatus: printStatus,
          compactLayout: compactLayout,
        ),
      ],
    );
  }

  Widget _buildStreamingBody(
    BuildContext context, {
    required bool compactLayout,
  }) {
    final connection = context.watch<ConnectionController>();
    final firmwareBanner = connection.firmwareWarning == null
        ? null
        : _buildFirmwareWarningBanner(context, connection.firmwareWarning!);
    final videoPane = Column(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compactLayout ? 8 : 0,
              compactLayout ? 8 : 0,
              compactLayout ? 4 : 0,
              compactLayout ? 8 : 0,
            ),
            child: _buildVideoSurface(compactLayout: compactLayout),
          ),
        ),
        if (_bufferFraction != null || _buffering)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compactLayout ? 8 : 8),
            child: LinearProgressIndicator(
              value: _bufferFraction,
              minHeight: 4,
            ),
          ),
        if (!compactLayout && connection.lastPrintStatus != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: _MetricsPanel(ps: connection.lastPrintStatus!),
          ),
      ],
    );

    if (compactLayout) {
      return Column(
        children: [
          if (firmwareBanner != null) firmwareBanner,
          Expanded(
            child: Row(
              children: [
                Expanded(child: videoPane),
                SizedBox(
                  width: 248,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (connection.lastPrintStatus != null)
                              _MetricsPanel(ps: connection.lastPrintStatus!),
                            if (connection.lastPrintStatus != null)
                              const SizedBox(height: 12),
                            _buildStreamActions(compactLayout: true),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (firmwareBanner != null) firmwareBanner,
        Expanded(child: videoPane),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: _buildStreamActions(compactLayout: false),
        ),
      ],
    );
  }

  Widget _buildFirmwareWarningBanner(
    BuildContext context,
    PrinterFirmwareWarning warning,
  ) {
    final helpUrl = warning.helpEntry.links.isNotEmpty
        ? warning.helpEntry.links.first.url
        : null;
    return MaterialBanner(
      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
      leading: Icon(
        Icons.warning_amber_rounded,
        color: Theme.of(context).colorScheme.onTertiaryContainer,
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Firmware may be too old',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            warning.message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
          ),
          if (warning.firmwareVersion.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Detected firmware: ${warning.firmwareVersion}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onTertiaryContainer,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (helpUrl != null)
          TextButton(
            onPressed: () => _openExternalUrl(helpUrl),
            child: const Text('Firmware updates'),
          ),
      ],
    );
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open link: $url')));
    }
  }

  Widget _buildDisconnectedBody() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No active stream',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _openSettings,
            child: const Text('Configure Stream'),
          ),
          ElevatedButton(
            onPressed: () async {
              final settings = SettingsManager.settings;
              final streamUrl = ConnectionPreflight.buildStreamUrl(settings);
              if (streamUrl.trim().isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please configure printer settings first'),
                    ),
                  );
                }
                return;
              }

              final summary = await ConnectionPreflight.run(
                settings: settings,
                streamUrl: streamUrl,
              );
              if (!mounted) return;

              if (summary.hasRequiredFailures) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(summary.summaryLine)));
                return;
              }

              final optionalFailures = summary.optionalFailures.toList();
              if (optionalFailures.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Printer stream is reachable. ${optionalFailures.map((r) => r.label).join(', ')} unavailable, but optional.',
                    ),
                  ),
                );
              }

              _onConnect(streamUrl);
            },
            child: const Text('Connect to Printer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionController>();
    final titleSummary = _buildTitleSummary(connection.lastPrintStatus);
    final compactLandscape = _isMobileLandscape(context);

    return FramelessWindowResizeFrame(
      child: Scaffold(
        appBar: WindowChromeHeader(
          title: const Text(AppStrings.appDisplayName),
          subtitle: titleSummary == null
              ? null
              : Text(
                  titleSummary,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
          actions: [
            if (_mqttControlsEnabled)
              IconButton(
                tooltip: 'MQTT Controls',
                icon: const Icon(Icons.tune),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MqttControlPage()),
                  );
                },
              ),
            if (FeatureFlags.ftpBrowserEnabled)
              IconButton(
                tooltip: 'FTP Browser',
                icon: const Icon(Icons.folder_open),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FtpBrowserPage()),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _openSettings,
            ),
          ],
        ),
        body: connection.isStreaming
            ? _buildStreamingBody(context, compactLayout: compactLandscape)
            : _buildDisconnectedBody(),
      ),
    );
  }
}

String? _formatNozzleInfo(BambuPrintStatus? ps) {
  if (ps == null) return null;
  final type = ps.nozzleType?.trim() ?? '';
  final diameter = ps.nozzleDiameter?.trim() ?? '';
  if (type.isEmpty && diameter.isEmpty) return null;
  if (type.isNotEmpty && diameter.isNotEmpty) return '$type • $diameter';
  return type.isNotEmpty ? type : diameter;
}

String? _formatJobIds(BambuPrintStatus? ps) {
  if (ps == null) return null;
  final job = ps.jobId?.trim() ?? '';
  final task = ps.taskId?.trim() ?? '';
  if (job.isEmpty && task.isEmpty) return null;
  if (job.isNotEmpty && task.isNotEmpty) {
    return 'Job ID: $job • Task ID: $task';
  }
  return job.isNotEmpty ? 'Job ID: $job' : 'Task ID: $task';
}

String? _formatPrintFileTitle(BambuPrintStatus? ps) {
  if (ps == null) return null;
  final subtask = ps.subtaskName?.trim();
  if (subtask != null && subtask.isNotEmpty) {
    return subtask;
  }
  final gcodeFile = ps.gcodeFile?.trim();
  if (gcodeFile == null || gcodeFile.isEmpty) {
    return null;
  }
  return path.basename(gcodeFile);
}

String? _buildTitleSummary(BambuPrintStatus? ps) {
  final lines = <String>[];
  final printFile = _formatPrintFileTitle(ps);
  if (printFile != null) {
    lines.add('Print: $printFile');
  }
  final nozzleInfo = _formatNozzleInfo(ps);
  if (nozzleInfo != null) {
    lines.add('Nozzle: $nozzleInfo');
  }
  final ids = _formatJobIds(ps);
  if (ids != null) {
    lines.add(ids);
  }
  if (lines.isEmpty) return null;
  return lines.join(' • ');
}

class _MetricsPanel extends StatelessWidget {
  final BambuPrintStatus ps;
  const _MetricsPanel({required this.ps});

  @override
  Widget build(BuildContext context) {
    String fmtTemp(double? t) => t == null ? '-' : '${t.toStringAsFixed(0)}°C';
    String fmtRssi(String? s) => s == null || s.isEmpty ? '-' : s;
    String fmtLayer(int? l, int? t) =>
        (l == null && t == null) ? '-' : '${l ?? '?'} / ${t ?? '?'}';
    String fmtSpeed(int? level, int? mag) {
      if (level == null && mag == null) return '-';
      if (level != null && mag != null) return 'L$level ($mag%)';
      if (level != null) return 'L$level';
      return '$mag%';
    }

    final styleValue = Theme.of(context).textTheme.bodySmall;

    Widget item(IconData icon, String value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(value, style: styleValue),
      ],
    );

    final items = <Widget>[
      if (ps.nozzleTemp != null || ps.nozzleTarget != null)
        item(
          Icons.local_fire_department,
          '${fmtTemp(ps.nozzleTemp)} / ${fmtTemp(ps.nozzleTarget)}',
        ),
      if (ps.bedTemp != null || ps.bedTarget != null)
        item(
          Icons.grid_on,
          '${fmtTemp(ps.bedTemp)} / ${fmtTemp(ps.bedTarget)}',
        ),
      if (ps.chamberTemp != null)
        item(Icons.crop_square, fmtTemp(ps.chamberTemp)),
      if (ps.speedLevel != null || ps.speedMag != null)
        item(Icons.speed, fmtSpeed(ps.speedLevel, ps.speedMag)),
      if (ps.wifiSignal != null && ps.wifiSignal!.isNotEmpty)
        item(Icons.wifi, fmtRssi(ps.wifiSignal)),
      if (ps.layer != null || ps.totalLayers != null)
        item(Icons.layers, fmtLayer(ps.layer, ps.totalLayers)),
      if (ps.percent != null) item(Icons.percent, '${ps.percent}%'),
      if (ps.remainingMinutes != null)
        item(Icons.timelapse, '${ps.remainingMinutes}m'),
    ];

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Wrap(spacing: 12, runSpacing: 6, children: items),
      ),
    );
  }
}

class _MetricItem {
  final String label;
  final String value;
  final bool show;
  final IconData? icon;

  const _MetricItem(this.label, this.value, {this.show = true, this.icon});
}

class _PrintOverlayStatus extends StatelessWidget {
  final BambuPrintStatus? status;
  const _PrintOverlayStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            'Waiting for MQTT status…',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    }

    final parts = <String>[];
    if (status!.gcodeState.isNotEmpty) {
      parts.add(status!.gcodeState);
    }
    if (status!.percent != null) {
      parts.add('${status!.percent}%');
    }
    if (status!.remainingMinutes != null) {
      parts.add('${status!.remainingMinutes}m left');
    }
    if (status!.layer != null || status!.totalLayers != null) {
      final layer = status!.layer?.toString() ?? '?';
      final total = status!.totalLayers?.toString() ?? '?';
      parts.add('Layer $layer / $total');
    }
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          parts.join(' • '),
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}
