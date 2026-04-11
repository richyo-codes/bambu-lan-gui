import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:boomprint/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final rootBoundaryKey = GlobalKey();

  testWidgets('capture marketing screenshots', (tester) async {
    final outputDir = Directory(_outputDirPath());
    await outputDir.create(recursive: true);

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

    await tester.pumpWidget(MyApp(rootBoundaryKey: rootBoundaryKey));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await _capture(tester, rootBoundaryKey, outputDir, 'home');

    await tester.tap(find.text('Configure Stream'));
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
