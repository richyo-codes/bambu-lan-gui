import 'package:flutter/foundation.dart';

/// Dormant compatibility surface for the removed tray integration.
///
/// BoomPrint deliberately does not initialize or import this manager. Keeping
/// this no-op type avoids reviving the native tray/AppIndicator dependency for
/// any downstream experimental code that still references the old API.
@Deprecated('System tray support has been removed from BoomPrint.')
class SystemTrayManager {
  static final SystemTrayManager _instance = SystemTrayManager._internal();
  static SystemTrayManager get instance => _instance;
  SystemTrayManager._internal();

  VoidCallback? onTrayIconDoubleClick;
  VoidCallback? onShowRequested;
  VoidCallback? onExitRequested;

  bool get isTrayIconVisible => false;

  Future<void> initialize() async {}

  Future<void> setTooltip(String tooltip) async {}

  Future<void> showNotification({
    required String title,
    required String body,
    NotificationType type = NotificationType.info,
  }) async {}

  void dispose() {}
}

@Deprecated('System tray support has been removed from BoomPrint.')
enum NotificationType { info, success, warning, error }
