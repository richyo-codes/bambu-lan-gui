import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_lan.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_mqtt.dart';
import 'package:rnd_bambu_rtsp_stream/printer_url_formats.dart';
import 'package:rnd_bambu_rtsp_stream/settings_manager.dart';
import 'package:rnd_bambu_rtsp_stream/printer_stream_manager.dart';
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

  const _CliConfig({
    this.configPath,
    this.printerIp,
    this.accessCode,
    this.serialNumber,
    this.format,
    this.customUrl,
  });
}

_CliConfig _parseCliArgs(List<String> args) {
  String? configPath;
  String? printerIp;
  String? accessCode;
  String? serialNumber;
  String? format;
  String? customUrl;

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
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bambu RTSP Streamer',
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
    );
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

class _StreamPageState extends State<StreamPage> {
  late final Player player;
  late final VideoController controller;
  String? currentStreamUrl;
  bool isStreaming = false;
  //final screenshotController = ScreenshotController();

  BambuMqtt? mqttClient;
  String printerStatus = 'Unknown'; // Example field to show printer data
  BambuPrintStatus? _lastPrintStatus; // Detailed metrics for UI
  bool? _chamberLightOn;
  bool _autoLightWhilePrinting = false;
  bool _wasPrinting = false;
  bool _mqttConnected = false;
  String _lightNode = 'chamber_light';
  bool _mqttControlsEnabled = false;

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
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
    final client = mqttClient;
    if (client == null || !client.isConnected) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MQTT not connected yet.')),
        );
      }
      return;
    }
    try {
      await client.setChamberLight(on, ledNode: _lightNode);
      if (mounted) {
        setState(() => _chamberLightOn = on);
      }
    } catch (e) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Light command failed: $e')),
        );
      }
    }
  }

  void _toggleChamberLight() {
    final target = !(_chamberLightOn ?? false);
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
    if (shouldEnable && _chamberLightOn != true) {
      _setChamberLight(true, showErrors: false);
    }
  }

  String _lightStatusLabel() {
    if (_chamberLightOn == null) return 'Light Unknown';
    final nodeLabel = _lightNode == 'work_light' ? 'Work' : 'Chamber';
    return _chamberLightOn! ? '$nodeLabel Light On' : '$nodeLabel Light Off';
  }

  @override
  void initState() {
    super.initState();

    PlayerConfiguration config = PlayerConfiguration(
      logLevel: MPVLogLevel.debug,
    );

    VideoControllerConfiguration vConfig = VideoControllerConfiguration(
      enableHardwareAcceleration: isAccelSupported(),
      hwdec: "auto",
    );

    player = Player(configuration: config);
    controller = VideoController(player, configuration: vConfig);
    _setupPlayerListeners();
    _loadUiSettings();
    _attemptAutoConnect();
  }

  Future<void> _loadUiSettings() async {
    final settings = await SettingsManager.loadSettings();
    if (!mounted) return;
    setState(() {
      _mqttControlsEnabled = settings.mqttControlsEnabled;
    });
  }

  Future<void> _attemptAutoConnect() async {
    final settings = await SettingsManager.loadSettings();
    if (!settings.autoConnect) return;
    final url = _buildStreamUrl(settings);
    if (url == null || url.isEmpty) return;
    if (!mounted || isStreaming) return;
    _onConnect(url);
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    _bufferingSub?.cancel();
    _bufferPosSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    _playingSub?.cancel();
    _controlsHideTimer?.cancel();
    player.dispose();
    mqttClient?.dispose();
    super.dispose();
  }

  Future<void> _startStream(String url) async {
    setState(() {
      isStreaming = true;
      currentStreamUrl = url;
    });
    _resetStallMonitor();
    // Load printer config from SharedPreferences using abstraction
    final printerSettings = await PrinterStreamManager.getPrinterSettings();
    final printerIp = printerSettings.printerIp;
    final accessCode = printerSettings.accessCode;
    final serial = printerSettings.serialNumber;

    // Start video stream first (independent of MQTT)
    try {
      final media = Media(url);
      await player.open(media);
      _startStallMonitor();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start stream: $e')));
        setState(() {
          isStreaming = false;
        });
      }
      return;
    }

    // Create and connect MQTT client (don't await, let it connect in background)
    mqttClient?.dispose();
    final config = BambuLanConfig(
      printerIp: printerIp,
      accessCode: accessCode,
      serial: serial,
      mqttPort: 8883,
      allowBadCerts: true,
    );
    mqttClient = BambuMqtt(config);

    // Attempt MQTT connection but don't let it block video streaming
    mqttClient!
        .connect()
        .then((_) {
          if (mounted) {
            setState(() {
              _mqttConnected = true;
              printerStatus = 'MQTT Connected';
            });
          }
          mqttClient!.requestPushAll().catchError((_) {});
          // Listen for printer reports if connection succeeds
          mqttClient!.reportStream.listen((event) {
            if (!mounted) return;
            final detectedNode = _detectLightNode(event.json);
            if (detectedNode != null) {
              _lightNode = detectedNode;
            }
            final lightState =
                _extractLightStateForNode(event.json, _lightNode);
            setState(() {
              if (event.printStatus != null) {
                final merged = _mergePrintStatus(
                  event.printStatus!,
                  _lastPrintStatus,
                );
                final pct = merged.percent != null ? '${merged.percent}%' : '';
                final left = merged.remainingMinutes != null
                    ? ' • ${merged.remainingMinutes}m left'
                    : '';
                printerStatus =
                    '${merged.gcodeState}${pct.isNotEmpty ? ' $pct' : ''}$left';
                _lastPrintStatus = merged;
              } else if (event.type != null && event.type != 'SYSTEM') {
                printerStatus = event.type!;
              }
              if (lightState != null) {
                _chamberLightOn = lightState;
              }
            });
            if (event.printStatus != null) {
              _handleAutoLight(_lastPrintStatus!);
            }
            if (!_mqttConnected) {
              setState(() => _mqttConnected = true);
            }
          });
        })
        .catchError((e) {
          // Handle MQTT connection failure without affecting video stream
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('MQTT connection failed: $e')),
            );
            setState(() {
              printerStatus = 'MQTT Disconnected';
              _mqttConnected = false;
            });
          }
        });
  }

  Future<void> _stopStream() async {
    await player.stop();
    mqttClient?.dispose();
    _stallTimer?.cancel();
    setState(() {
      isStreaming = false;
      currentStreamUrl = null;
      printerStatus = 'Unknown';
      _lastPrintStatus = null;
      _chamberLightOn = null;
      _wasPrinting = false;
      _mqttConnected = false;
    });
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
      if (!isStreaming || currentStreamUrl == null) return;
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

  void _attemptReconnect({required String reason}) {
    if (_reconnecting || currentStreamUrl == null) return;
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
    final delaySeconds = (2 << (_reconnectAttempts)).clamp(2, 30);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reconnecting (attempt $attempt) in ${delaySeconds}s...',
          ),
        ),
      );
    }

    Future.delayed(Duration(seconds: delaySeconds), () async {
      if (!isStreaming || currentStreamUrl == null) {
        _reconnecting = false;
        return;
      }
      try {
        await player.open(Media(currentStreamUrl!));
        _reconnectAttempts = 0;
        _reconnecting = false;
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

  Future<void> _openSettings() async {
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

  @override
  Widget build(BuildContext context) {
    final titleLines = _buildTitleLines(_lastPrintStatus);
    final double? toolbarHeight = titleLines.isEmpty
        ? null
        : kToolbarHeight + (18.0 * titleLines.length);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: toolbarHeight,
        title: WindowDragArea(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bambu RTSP Stream'),
                if (titleLines.isNotEmpty)
                  ...titleLines.map(
                    (line) => Text(
                      line,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
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
          IconButton(
            tooltip: 'FTP Browser',
            icon: const Icon(Icons.folder_open),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const FtpBrowserPage()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
          const WindowControlButtons(),
        ],
      ),
      body: Column(
        children: [
          // Video player
          Expanded(
            child: Center(
              child: isStreaming
                  ? Column(
                      children: [
                        Expanded(
                          child: MouseRegion(
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
                                  Positioned.fill(
                                    child: Video(
                                      controller: controller,
                                      //controls: NoVideoControls,
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: _PrintOverlayStatus(
                                      status: _lastPrintStatus,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: !_showVideoControls,
                                      child: AnimatedOpacity(
                                        opacity: _showVideoControls ? 1 : 0,
                                        duration:
                                            const Duration(milliseconds: 150),
                                        child: Container(
                                          color: Colors.black.withOpacity(0.2),
                                          child: Center(
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(
                                                  0.55,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(48),
                                              ),
                                              child: IconButton(
                                                iconSize: 56,
                                                color: Colors.white,
                                                icon: Icon(
                                                  _isPlaying
                                                      ? Icons.pause
                                                      : Icons.play_arrow,
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
                          ),
                        ),
                        if (_bufferFraction != null || _buffering)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: LinearProgressIndicator(
                              value: _bufferFraction, // null => indeterminate
                              minHeight: 4,
                            ),
                          ),
                        if (_lastPrintStatus != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: _MetricsPanel(ps: _lastPrintStatus!),
                          ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.videocam_off,
                          size: 64,
                          color: Colors.grey,
                        ),
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
                            final streamUrl =
                                await PrinterStreamManager.getStreamUrl();
                            if (streamUrl != null) {
                              _onConnect(streamUrl);
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please configure printer settings first',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Connect to Printer'),
                        ),
                      ],
                    ),
            ),
          ),
          // MQTT status line intentionally hidden for now.

          // Stream controls
          if (isStreaming) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _stopStream,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _takeScreenshot,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text(''),
                      ),
                      ElevatedButton.icon(
                        onPressed: _openSettings,
                        icon: const Icon(Icons.settings),
                        label: const Text('Settings'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _toggleChamberLight,
                        icon: Icon(
                          _chamberLightOn == true
                              ? Icons.lightbulb
                              : Icons.lightbulb_outline,
                        ),
                        label: Text(_lightStatusLabel()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Auto light while printing'),
                      Switch(
                        value: _autoLightWhilePrinting,
                        onChanged: (value) {
                          setState(() => _autoLightWhilePrinting = value);
                          final ps = _lastPrintStatus;
                          if (value && ps != null) {
                            _handleAutoLight(ps, force: true);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
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

List<String> _buildTitleLines(BambuPrintStatus? ps) {
  final lines = <String>[];
  final nozzleInfo = _formatNozzleInfo(ps);
  if (nozzleInfo != null) {
    lines.add('Nozzle: $nozzleInfo');
  }
  final ids = _formatJobIds(ps);
  if (ids != null) {
    lines.add(ids);
  }
  return lines;
}

String? _buildStreamUrl(AppSettings settings) {
  if (settings.selectedFormat == PrinterUrlType.custom) {
    return settings.customUrl.trim().isEmpty ? null : settings.customUrl.trim();
  }
  final template = settings.selectedFormat.template;
  if (template.isEmpty) return null;
  return template
      .replaceAll('\${specialcode}', settings.specialCode)
      .replaceAll('\${printerip}', settings.printerIp);
}

BambuPrintStatus _mergePrintStatus(
  BambuPrintStatus incoming,
  BambuPrintStatus? previous,
) {
  if (previous == null) return incoming;
  String pickString(String? next, String? prev) =>
      (next != null && next.isNotEmpty) ? next : (prev ?? '');
  int? pickInt(int? next, int? prev) => next ?? prev;
  double? pickDouble(double? next, double? prev) => next ?? prev;

  return BambuPrintStatus(
    gcodeState: pickString(incoming.gcodeState, previous.gcodeState),
    percent: pickInt(incoming.percent, previous.percent),
    remainingMinutes: pickInt(
      incoming.remainingMinutes,
      previous.remainingMinutes,
    ),
    gcodeFile: pickString(incoming.gcodeFile, previous.gcodeFile),
    layer: pickInt(incoming.layer, previous.layer),
    totalLayers: pickInt(incoming.totalLayers, previous.totalLayers),
    bedTemp: pickDouble(incoming.bedTemp, previous.bedTemp),
    bedTarget: pickDouble(incoming.bedTarget, previous.bedTarget),
    nozzleTemp: pickDouble(incoming.nozzleTemp, previous.nozzleTemp),
    nozzleTarget: pickDouble(incoming.nozzleTarget, previous.nozzleTarget),
    chamberTemp: pickDouble(incoming.chamberTemp, previous.chamberTemp),
    nozzleType: pickString(incoming.nozzleType, previous.nozzleType),
    nozzleDiameter: pickString(incoming.nozzleDiameter, previous.nozzleDiameter),
    speedLevel: pickInt(incoming.speedLevel, previous.speedLevel),
    speedMag: pickInt(incoming.speedMag, previous.speedMag),
    subtaskName: pickString(incoming.subtaskName, previous.subtaskName),
    taskId: pickString(incoming.taskId, previous.taskId),
    jobId: pickString(incoming.jobId, previous.jobId),
    wifiSignal: pickString(incoming.wifiSignal, previous.wifiSignal),
  );
}

bool? _parseBoolish(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return null;
    if (['on', 'true', '1', 'yes', 'enabled'].contains(v)) return true;
    if (['off', 'false', '0', 'no', 'disabled'].contains(v)) return false;
  }
  return null;
}

Map<String, dynamic> _stringKeyMap(Map map) {
  final out = <String, dynamic>{};
  map.forEach((key, value) {
    if (key is String) {
      out[key] = value;
    }
  });
  return out;
}

List<Map<String, dynamic>> _extractLightsReport(Map<String, dynamic> map) {
  final lightsReport = map['lights_report'];
  if (lightsReport is List) {
    return lightsReport
        .whereType<Map>()
        .map((e) => _stringKeyMap(e))
        .toList();
  }
  return const [];
}

String? _detectLightNode(Map<String, dynamic> json) {
  final candidates = <Map<String, dynamic>>[];
  final system = json['system'];
  if (system is Map) {
    candidates.add(_stringKeyMap(system));
  }
  final print = json['print'];
  if (print is Map) {
    candidates.add(_stringKeyMap(print));
  }
  candidates.add(json);

  for (final candidate in candidates) {
    final lights = _extractLightsReport(candidate);
    if (lights.isEmpty) continue;
    for (final entry in lights) {
      final node = entry['node'];
      if (node == 'chamber_light') return 'chamber_light';
    }
    for (final entry in lights) {
      final node = entry['node'];
      if (node == 'work_light') return 'work_light';
    }
  }
  return null;
}

bool? _extractLightStateForNode(
  Map<String, dynamic> json,
  String node,
) {
  final candidates = <Map<String, dynamic>>[];
  final system = json['system'];
  if (system is Map) {
    candidates.add(_stringKeyMap(system));
  }
  final print = json['print'];
  if (print is Map) {
    candidates.add(_stringKeyMap(print));
  }
  candidates.add(json);

  for (final candidate in candidates) {
    final lights = _extractLightsReport(candidate);
    if (lights.isEmpty) continue;
    for (final entry in lights) {
      if (entry['node'] == node) {
        final mode = entry['mode'];
        final v = _parseBoolish(mode);
        if (v != null) return v;
        if (mode is String && mode.toLowerCase() == 'flashing') return true;
      }
    }
  }
  return null;
}

bool? _extractLightFromMap(Map<String, dynamic> map) {
  const directKeys = [
    'chamber_light',
    'chamber_light_state',
    'chamber_light_on',
    'light',
    'light_state',
    'light_on',
  ];
  for (final key in directKeys) {
    if (map.containsKey(key)) {
      final v = _parseBoolish(map[key]);
      if (v != null) return v;
    }
  }

  final ledMode = map['led_mode'];
  if (ledMode != null) {
    final node = map['led_node'];
    if (node == null || (node is String && node.contains('chamber'))) {
      final v = _parseBoolish(ledMode);
      if (v != null) return v;
    }
  }

  final led = map['led'];
  if (led is Map) {
    final nested = _extractLightFromMap(_stringKeyMap(led));
    if (nested != null) return nested;
  }

  return null;
}

bool? _extractChamberLightState(Map<String, dynamic> json) {
  final candidates = <Map<String, dynamic>>[];
  final system = json['system'];
  if (system is Map) {
    candidates.add(_stringKeyMap(system));
  }
  final print = json['print'];
  if (print is Map) {
    candidates.add(_stringKeyMap(print));
  }
  candidates.add(json);

  for (final candidate in candidates) {
    final v = _extractLightFromMap(candidate);
    if (v != null) return v;
  }
  return null;
}

class _MetricsPanel extends StatelessWidget {
  final BambuPrintStatus ps;
  const _MetricsPanel({required this.ps});

  @override
  Widget build(BuildContext context) {
    String fmtTemp(double? t) => t == null ? '-' : '${t.toStringAsFixed(0)}°C';
    String fmtPct(int? p) => p == null ? '-' : '$p%';
    String fmtRssi(String? s) => s == null || s.isEmpty ? '-' : s;
    String fmtLayer(int? l, int? t) =>
        (l == null && t == null) ? '-' : '${l ?? '?'} / ${t ?? '?'}';
    String fmtSpeed(int? level, int? mag) {
      if (level == null && mag == null) return '-';
      if (level != null && mag != null) return 'L$level ($mag%)';
      if (level != null) return 'L$level';
      return '$mag%';
    }

    final styleLabel = Theme.of(context).textTheme.labelMedium;
    final styleValue = Theme.of(context).textTheme.bodyMedium;
    final styleSection = Theme.of(context).textTheme.titleSmall;

    Widget tile(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: styleLabel),
        Text(value, style: styleValue),
      ],
    );

    Widget? section(String title, List<_MetricItem> items) {
      final visible = items.where((item) => item.show).toList();
      if (visible.isEmpty) return null;
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 180),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: styleSection),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children:
                  visible.map((item) => tile(item.label, item.value)).toList(),
            ),
          ],
        ),
      );
    }

    final statusItems = [
      _MetricItem('State', ps.gcodeState, show: ps.gcodeState.isNotEmpty),
      _MetricItem('Progress', fmtPct(ps.percent), show: ps.percent != null),
      _MetricItem(
        'Time Left',
        ps.remainingMinutes != null ? '${ps.remainingMinutes} min' : '-',
        show: ps.remainingMinutes != null,
      ),
      _MetricItem(
        'Layer',
        fmtLayer(ps.layer, ps.totalLayers),
        show: ps.layer != null || ps.totalLayers != null,
      ),
    ];

    final tempItems = [
      _MetricItem(
        'Nozzle',
        '${fmtTemp(ps.nozzleTemp)} / ${fmtTemp(ps.nozzleTarget)}',
        show: ps.nozzleTemp != null || ps.nozzleTarget != null,
      ),
      _MetricItem(
        'Bed',
        '${fmtTemp(ps.bedTemp)} / ${fmtTemp(ps.bedTarget)}',
        show: ps.bedTemp != null || ps.bedTarget != null,
      ),
      _MetricItem(
        'Chamber',
        fmtTemp(ps.chamberTemp),
        show: ps.chamberTemp != null,
      ),
    ];

    final motionItems = [
      _MetricItem(
        'Speed',
        fmtSpeed(ps.speedLevel, ps.speedMag),
        show: ps.speedLevel != null || ps.speedMag != null,
      ),
      _MetricItem(
        'Wi-Fi',
        fmtRssi(ps.wifiSignal),
        show: ps.wifiSignal != null && ps.wifiSignal!.isNotEmpty,
      ),
    ];

    final jobItems = [
      if (ps.gcodeFile != null && ps.gcodeFile!.isNotEmpty)
        _MetricItem('File', ps.gcodeFile!.split('/').last),
      if (ps.subtaskName != null && ps.subtaskName!.isNotEmpty)
        _MetricItem('Job', ps.subtaskName!),
    ];

    final sections = [
      section('Status', statusItems),
      section('Temps', tempItems),
      section('Motion', motionItems),
      section('Job', jobItems),
    ].whereType<Widget>().toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 20,
          runSpacing: 12,
          children: sections,
        ),
      ),
    );
  }
}

class _MetricItem {
  final String label;
  final String value;
  final bool show;

  const _MetricItem(this.label, this.value, {this.show = true});
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
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}
