import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WindowDragController {
  static const MethodChannel _channel = MethodChannel('app/window_drag');

  static bool get supportsWindowControls =>
      Platform.isLinux || Platform.isWindows;
  static bool get _supportsDragging => supportsWindowControls;

  static Future<void> startDragging() async {
    if (!_supportsDragging) {
      return;
    }
    try {
      await _channel.invokeMethod('startDrag');
    } catch (_) {
      // Ignore failures to keep the UI responsive if the channel is unavailable.
    }
  }

  static Future<void> minimize() async {
    if (!supportsWindowControls) {
      return;
    }
    try {
      await _channel.invokeMethod('minimize');
    } catch (_) {
      // Ignore failures; window controls are best-effort.
    }
  }

  static Future<void> toggleMaximize() async {
    if (!supportsWindowControls) {
      return;
    }
    try {
      await _channel.invokeMethod('toggleMaximize');
    } catch (_) {
      // Ignore failures; window controls are best-effort.
    }
  }

  static Future<void> close() async {
    if (!supportsWindowControls) {
      return;
    }
    try {
      await _channel.invokeMethod('close');
    } catch (_) {
      // Ignore failures; window controls are best-effort.
    }
  }
}

class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!WindowDragController._supportsDragging) {
      return child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => WindowDragController.startDragging(),
      child: child,
    );
  }
}

class WindowControlButtons extends StatelessWidget {
  const WindowControlButtons({super.key});

  @override
  Widget build(BuildContext context) {
    if (!WindowDragController.supportsWindowControls) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Minimize',
          icon: const Icon(Icons.minimize),
          onPressed: () => WindowDragController.minimize(),
        ),
        IconButton(
          tooltip: 'Maximize/Restore',
          icon: const Icon(Icons.crop_square),
          onPressed: () => WindowDragController.toggleMaximize(),
        ),
        IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => WindowDragController.close(),
        ),
      ],
    );
  }
}
