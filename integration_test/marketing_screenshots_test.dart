import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:boomprint/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;

import '../test/demo_connection_controller.dart';
import 'package:boomprint/screenshot_storage.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final rootBoundaryKey = GlobalKey();
  MediaKit.ensureInitialized();

  testWidgets('capture marketing screenshots', (tester) async {
    final connectionController = DemoConnectionController();
    addTearDown(connectionController.disposeController);

    final outputDir = Directory(_outputDirPath());
    await outputDir.create(recursive: true);
    await _seedGalleryScreenshots();

    final view = tester.view;
    final oldPhysicalSize = view.physicalSize;
    final oldDevicePixelRatio = view.devicePixelRatio;
    view
      ..physicalSize = const Size(1728, 1117)
      ..devicePixelRatio = 1.0;
    addTearDown(() {
      view
        ..physicalSize = oldPhysicalSize
        ..devicePixelRatio = oldDevicePixelRatio;
    });

    await tester.pumpWidget(
      MyApp(
        rootBoundaryKey: rootBoundaryKey,
        connectionController: connectionController,
        demoVideoSurface: true,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await _capture(tester, rootBoundaryKey, outputDir, 'home');

    await tester.tap(find.byIcon(Icons.settings).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _capture(tester, rootBoundaryKey, outputDir, 'settings');

    await tester.dragUntilVisible(
      find.text('Enable hardware video acceleration'),
      find.byType(Scrollable).first,
      const Offset(0, -250),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _capture(tester, rootBoundaryKey, outputDir, 'settings_advanced');

    await _goBack(tester);
    await tester.tap(find.byTooltip('FTP Browser'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _capture(tester, rootBoundaryKey, outputDir, 'ftp_browser');

    await _goBack(tester);
    await tester.tap(find.byTooltip('Screenshots'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _capture(tester, rootBoundaryKey, outputDir, 'screenshots');

    await binding.idle();
  });
}

String _outputDirPath() {
  const override = String.fromEnvironment('MARKETING_SCREENSHOT_DIR');
  if (override.isNotEmpty) {
    return override;
  }
  return 'build/marketing_screenshots';
}

Future<void> _goBack(WidgetTester tester) async {
  final back = find.byTooltip('Back');
  if (back.evaluate().isNotEmpty) {
    await tester.tap(back.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    return;
  }

  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).maybePop();
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Directory outputDir,
  String name,
) async {
  await tester.pumpAndSettle(const Duration(seconds: 2));
  final boundary = boundaryKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    throw StateError('Root repaint boundary not available for $name');
  }

  final image = await boundary.toImage(pixelRatio: 2.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) {
    throw StateError('Failed to encode screenshot for $name');
  }

  final file = File('${outputDir.path}/$name.png');
  await file.writeAsBytes(_toPngBytes(bytes));
}

Uint8List _toPngBytes(ByteData data) {
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

const _demoScreenshotPrefix = 'marketing_demo_';

Future<void> _seedGalleryScreenshots() async {
  final dirs = await ScreenshotStorage.galleryDirectories();
  final assets = [
    _DemoGalleryAsset(
      fileName:
          '$_demoScreenshotPrefix'
          'stream.png',
      accent: Color(0xFF3B82F6),
      glow: Color(0xFF93C5FD),
      plate: Color(0xFFBFC6D1),
      titleSeed: 'Stream',
      subtitleSeed: 'Camera',
    ),
    _DemoGalleryAsset(
      fileName:
          '$_demoScreenshotPrefix'
          'layer.png',
      accent: Color(0xFFF97316),
      glow: Color(0xFFFCD34D),
      plate: Color(0xFFE2E8F0),
      titleSeed: 'Layer',
      subtitleSeed: '325 / 325',
    ),
    _DemoGalleryAsset(
      fileName:
          '$_demoScreenshotPrefix'
          'status.png',
      accent: Color(0xFF10B981),
      glow: Color(0xFF6EE7B7),
      plate: Color(0xFFD1FAE5),
      titleSeed: 'Finish',
      subtitleSeed: 'Ready',
    ),
  ];

  for (final dir in dirs) {
    await dir.create(recursive: true);
    final existing = await dir.list().toList();
    for (final entity in existing) {
      final basename = path.basename(entity.path);
      if (basename.startsWith(_demoScreenshotPrefix)) {
        try {
          await entity.delete();
        } catch (_) {
          // Ignore cleanup errors in test seeding.
        }
      }
    }

    for (final asset in assets) {
      final bytes = await _renderDemoGalleryAsset(asset);
      await File(path.join(dir.path, asset.fileName)).writeAsBytes(bytes);
    }
  }
}

Future<Uint8List> _renderDemoGalleryAsset(_DemoGalleryAsset asset) async {
  const width = 1920;
  const height = 1080;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  final background = Paint()
    ..shader = ui.Gradient.linear(
      rect.topLeft,
      rect.bottomRight,
      [
        const Color(0xFF0D1117),
        asset.accent.withOpacity(0.88),
        const Color(0xFF050608),
      ],
      const [0.0, 0.46, 1.0],
    );
  canvas.drawRect(rect, background);

  final framePaint = Paint()
    ..color = Colors.black.withOpacity(0.45)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 20;
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect.deflate(40), const Radius.circular(28)),
    framePaint,
  );

  final bedPaint = Paint()..color = asset.plate.withOpacity(0.9);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(width * 0.5, height * 0.74),
        width: width * 0.68,
        height: height * 0.2,
      ),
      const Radius.circular(20),
    ),
    bedPaint,
  );

  final glowPaint = Paint()
    ..color = asset.glow.withOpacity(0.32)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
  canvas.drawCircle(Offset(width * 0.66, height * 0.30), 190, glowPaint);

  final carriagePaint = Paint()..color = const Color(0xFFF7FAFC);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(width * 0.34, height * 0.34),
        width: width * 0.16,
        height: height * 0.15,
      ),
      const Radius.circular(16),
    ),
    carriagePaint,
  );
  canvas.drawCircle(
    Offset(width * 0.34, height * 0.34),
    48,
    Paint()..color = const Color(0xFF121212),
  );

  final nozzlePaint = Paint()
    ..color = asset.accent.withOpacity(0.9)
    ..strokeWidth = 18
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(
    Offset(width * 0.28, height * 0.53),
    Offset(width * 0.72, height * 0.53),
    nozzlePaint,
  );
  canvas.drawLine(
    Offset(width * 0.30, height * 0.60),
    Offset(width * 0.68, height * 0.60),
    nozzlePaint..color = asset.glow.withOpacity(0.8),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('Failed to encode demo gallery asset ${asset.fileName}');
  }
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

class _DemoGalleryAsset {
  final String fileName;
  final Color accent;
  final Color glow;
  final Color plate;
  final String titleSeed;
  final String subtitleSeed;

  const _DemoGalleryAsset({
    required this.fileName,
    required this.accent,
    required this.glow,
    required this.plate,
    required this.titleSeed,
    required this.subtitleSeed,
  });
}
