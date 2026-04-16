import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WindowChromeController {
  static const MethodChannel _channel = MethodChannel('app/window_style');
  static final ValueNotifier<bool> useLinuxSystemDecorations = ValueNotifier(
    false,
  );

  static bool get supportsLinuxSystemDecorations => Platform.isLinux;
  static bool get useCustomWindowChrome =>
      !(Platform.isLinux && useLinuxSystemDecorations.value);

  static Future<void> setLinuxSystemDecorations(bool enabled) async {
    useLinuxSystemDecorations.value = enabled;
    if (!supportsLinuxSystemDecorations) {
      return;
    }
    try {
      await _channel.invokeMethod('setUseSystemDecorations', {
        'enabled': enabled,
      });
    } catch (_) {
      // Best-effort native toggle; Flutter UI state still updates.
    }
  }
}

enum WindowResizeEdge {
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
  topLeft,
}

class WindowDragController {
  static const MethodChannel _channel = MethodChannel('app/window_drag');
  static final ValueNotifier<bool> isMaximized = ValueNotifier(false);
  static bool _initialWindowStateRequested = false;

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

  static Future<void> startResize(WindowResizeEdge edge) async {
    if (!_supportsDragging) {
      return;
    }
    try {
      await _channel.invokeMethod('startResize', {'edge': edge.name});
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
      await refreshMaximizedState();
    } catch (_) {
      // Ignore failures; window controls are best-effort.
    }
  }

  static Future<void> refreshMaximizedState() async {
    if (!supportsWindowControls) {
      return;
    }
    try {
      final maximized = await _channel.invokeMethod<bool>('isMaximized');
      if (maximized != null) {
        isMaximized.value = maximized;
      }
    } catch (_) {
      // Ignore failures; window controls are best-effort.
    }
  }

  static void ensureWindowStateInitialized() {
    if (!supportsWindowControls || _initialWindowStateRequested) {
      return;
    }
    _initialWindowStateRequested = true;
    unawaited(refreshMaximizedState());
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

class FramelessWindowResizeFrame extends StatelessWidget {
  const FramelessWindowResizeFrame({
    super.key,
    required this.child,
    this.resizeBorderThickness = 6,
    this.resizeCornerSize = 18,
    this.topControlsSafeWidth = 160,
    this.topControlsSafeHeight = kToolbarHeight,
  });

  final Widget child;
  final double resizeBorderThickness;
  final double resizeCornerSize;
  final double topControlsSafeWidth;
  final double topControlsSafeHeight;

  @override
  Widget build(BuildContext context) {
    if (!WindowDragController.supportsWindowControls ||
        !WindowChromeController.useCustomWindowChrome) {
      return child;
    }

    return Stack(
      children: [
        Positioned.fill(child: child),
        ..._buildResizeHandles(),
      ],
    );
  }

  List<Widget> _buildResizeHandles() {
    final border = resizeBorderThickness;
    final corner = resizeCornerSize;
    final topRightSafeWidth = topControlsSafeWidth > corner
        ? topControlsSafeWidth
        : corner;
    final rightTopSafeHeight = topControlsSafeHeight > corner
        ? topControlsSafeHeight
        : corner;

    return [
      Positioned(
        left: corner,
        right: topRightSafeWidth,
        top: 0,
        height: border,
        child: _ResizeHandle(
          edge: WindowResizeEdge.top,
          cursor: SystemMouseCursors.resizeUp,
        ),
      ),
      Positioned(
        right: 0,
        top: rightTopSafeHeight,
        bottom: corner,
        width: border,
        child: _ResizeHandle(
          edge: WindowResizeEdge.right,
          cursor: SystemMouseCursors.resizeRight,
        ),
      ),
      Positioned(
        left: corner,
        right: corner,
        bottom: 0,
        height: border,
        child: _ResizeHandle(
          edge: WindowResizeEdge.bottom,
          cursor: SystemMouseCursors.resizeDown,
        ),
      ),
      Positioned(
        left: 0,
        top: corner,
        bottom: corner,
        width: border,
        child: _ResizeHandle(
          edge: WindowResizeEdge.left,
          cursor: SystemMouseCursors.resizeLeft,
        ),
      ),
      Positioned(
        left: 0,
        top: 0,
        width: corner,
        height: corner,
        child: _ResizeHandle(
          edge: WindowResizeEdge.topLeft,
          cursor: SystemMouseCursors.resizeUpLeft,
        ),
      ),
      Positioned(
        right: 0,
        bottom: 0,
        width: corner,
        height: corner,
        child: _ResizeHandle(
          edge: WindowResizeEdge.bottomRight,
          cursor: SystemMouseCursors.resizeDownRight,
        ),
      ),
      Positioned(
        left: 0,
        bottom: 0,
        width: corner,
        height: corner,
        child: _ResizeHandle(
          edge: WindowResizeEdge.bottomLeft,
          cursor: SystemMouseCursors.resizeDownLeft,
        ),
      ),
    ];
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.edge, required this.cursor});

  final WindowResizeEdge edge;
  final MouseCursor cursor;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => WindowDragController.startResize(edge),
        child: const SizedBox.expand(),
      ),
    );
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
    if (!WindowChromeController.useCustomWindowChrome) {
      return child;
    }
    WindowDragController.ensureWindowStateInitialized();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => WindowDragController.toggleMaximize(),
      onPanStart: (_) => WindowDragController.startDragging(),
      child: child,
    );
  }
}

class WindowChromeHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const WindowChromeHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.actionPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.actionHeight = 52,
  });

  final Widget title;
  final List<Widget> actions;
  final EdgeInsetsGeometry actionPadding;
  final double actionHeight;

  @override
  Size get preferredSize {
    return Size.fromHeight(
      kToolbarHeight + (actions.isEmpty ? 0 : actionHeight),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor =
        theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
    final onSurface =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;

    return Material(
      color: surfaceColor,
      elevation: theme.appBarTheme.elevation ?? 0,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: kToolbarHeight,
              child: Row(
                children: [
                  Expanded(
                    child: WindowDragArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: DefaultTextStyle(
                            style:
                                theme.appBarTheme.titleTextStyle ??
                                theme.textTheme.titleLarge!.copyWith(
                                  color: onSurface,
                                ),
                            child: title,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const WindowControlButtons(),
                ],
              ),
            ),
            if (actions.isNotEmpty)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                padding: actionPadding,
                height: actionHeight,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class WindowControlButtons extends StatelessWidget {
  const WindowControlButtons({super.key});

  @override
  Widget build(BuildContext context) {
    if (!WindowDragController.supportsWindowControls ||
        !WindowChromeController.useCustomWindowChrome) {
      return const SizedBox.shrink();
    }
    WindowDragController.ensureWindowStateInitialized();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Minimize',
          icon: const Icon(Icons.minimize),
          onPressed: () => WindowDragController.minimize(),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: WindowDragController.isMaximized,
          builder: (context, isMaximized, _) {
            return IconButton(
              tooltip: isMaximized ? 'Restore' : 'Maximize',
              icon: Icon(isMaximized ? Icons.filter_none : Icons.crop_square),
              onPressed: () => WindowDragController.toggleMaximize(),
            );
          },
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
