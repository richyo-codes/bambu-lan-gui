import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_lan.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_mqtt.dart';
import 'package:rnd_bambu_rtsp_stream/settings_manager.dart';
import 'package:rnd_bambu_rtsp_stream/printer_stream_manager.dart';
import 'settings_page.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screenshot/screenshot.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsManager.loadSettings(); // Load and cache settings
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bambu RTSP Streamer',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const StreamPage(),
    );
  }
}

class StreamPage extends StatefulWidget {
  const StreamPage({super.key});

  @override
  State<StreamPage> createState() => _StreamPageState();
}

bool isAccelSupported() {
  // This is a placeholder. Actual hardware acceleration support detection
  // would depend on the platform and the media_kit capabilities.
  // For simplicity, we'll assume it's supported on desktop platforms.
  return !Platform.isLinux;
}

class _StreamPageState extends State<StreamPage> {
  late final Player player;
  late final VideoController controller;
  String? currentStreamUrl;
  bool isStreaming = false;
  final screenshotController = ScreenshotController();

  BambuMqtt? mqttClient;
  String printerStatus = 'Unknown'; // Example field to show printer data
  BambuPrintStatus? _lastPrintStatus; // Detailed metrics for UI

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

  Future<void> _takeScreenshot() async {
    try {
      // Capture screenshot using the screenshot package
      //final screenshotData = await screenshotController.capture();
      final screenshotData = await player.screenshot();

      if (screenshotData != null) {
        // Save to XDG home directory
        final homeDir = Platform.environment['HOME'] ?? '/tmp';
        final screenshotDir = Directory('$homeDir/Pictures/BambuScreenshots');
        await screenshotDir.create(recursive: true);

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filename = 'screenshot_$timestamp.png';
        final filePath = path.join(screenshotDir.path, filename);

        // Save the screenshot data
        final file = File(filePath);
        await file.writeAsBytes(screenshotData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Screenshot saved to $filePath')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to capture screenshot')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Screenshot failed: $e')));
      }
    }
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
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    _bufferingSub?.cancel();
    _bufferPosSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
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
          // Listen for printer reports if connection succeeds
          mqttClient!.reportStream.listen((event) {
            if (!mounted) return;
            setState(() {
              if (event.printStatus != null) {
                final ps = event.printStatus!;
                final pct = ps.percent != null ? '${ps.percent}%' : '';
                final left = ps.remainingMinutes != null
                    ? ' • ${ps.remainingMinutes}m left'
                    : '';
                printerStatus =
                    '${ps.gcodeState}${pct.isNotEmpty ? ' $pct' : ''}$left';
                _lastPrintStatus = ps;
              } else {
                printerStatus = event.type ?? 'Unknown';
                _lastPrintStatus = null;
              }
            });
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
    });
  }

  void _setupPlayerListeners() {
    // Cancel existing subscriptions if any
    _bufferingSub?.cancel();
    _bufferPosSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();

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
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(onConnect: _onConnect),
      ),
    );
  }

  void _onConnect(String url) {
    _startStream(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bambu RTSP Stream'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
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
                          child: Screenshot(
                            controller: screenshotController,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Video(controller: controller),
                                // if (_buffering)
                                //   Container(
                                //     color: Colors.black26,
                                //     child: const Center(
                                //       child: Column(
                                //         mainAxisSize: MainAxisSize.min,
                                //         children: [
                                //           CircularProgressIndicator(),
                                //           SizedBox(height: 12),
                                //           Text(
                                //             'Buffering…',
                                //             style: TextStyle(
                                //               color: Colors.white,
                                //             ),
                                //           ),
                                //         ],
                                //       ),
                                //     ),
                                //   ),
                              ],
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

          // Stream controls
          if (isStreaming) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _stopStream,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Stream'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _takeScreenshot,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Screenshot'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Settings'),
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
    final styleLabel = Theme.of(context).textTheme.labelMedium;
    final styleValue = Theme.of(context).textTheme.bodyMedium;

    Widget tile(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: styleLabel),
        Text(value, style: styleValue),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            tile('Progress', fmtPct(ps.percent)),
            tile(
              'Time Left',
              ps.remainingMinutes != null ? '${ps.remainingMinutes} min' : '-',
            ),
            tile('Wi‑Fi', fmtRssi(ps.wifiSignal)),
            tile(
              'Speed',
              ps.speedLevel != null
                  ? 'L${ps.speedLevel} (${ps.speedMag ?? 0}%)'
                  : (ps.speedMag != null ? '${ps.speedMag}%' : '-'),
            ),
            tile(
              'Nozzle',
              '${fmtTemp(ps.nozzleTemp)} / ${fmtTemp(ps.nozzleTarget)}',
            ),
            tile('Bed', '${fmtTemp(ps.bedTemp)} / ${fmtTemp(ps.bedTarget)}'),
            tile('Chamber', fmtTemp(ps.chamberTemp)),
            tile('Layer', fmtLayer(ps.layer, ps.totalLayers)),
            if (ps.nozzleType != null || ps.nozzleDiameter != null)
              tile(
                'Nozzle Type',
                '${ps.nozzleType ?? ''}${ps.nozzleDiameter != null ? ' • ${ps.nozzleDiameter}' : ''}',
              ),
            if (ps.gcodeFile != null && ps.gcodeFile!.isNotEmpty)
              tile('File', ps.gcodeFile!.split('/').last),
            if (ps.subtaskName != null && ps.subtaskName!.isNotEmpty)
              tile('Job', ps.subtaskName!),
          ],
        ),
      ),
    );
  }
}
