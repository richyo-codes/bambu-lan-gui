import 'dart:io';

import 'package:flutter/services.dart';

class MonitoringAlerts {
  static const MethodChannel _channel = MethodChannel('app/monitoring_alerts');

  static bool get supportsDesktopSounds =>
      Platform.isLinux || Platform.isWindows;
  static bool get supportsAndroidNotifications => Platform.isAndroid;

  static Future<void> requestAndroidNotificationPermission() async {
    if (!supportsAndroidNotifications) {
      return;
    }
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {
      // Best-effort on Android; continue silently if unavailable.
    }
  }

  static Future<void> playAttentionSound() async {
    if (!supportsDesktopSounds) {
      return;
    }
    try {
      await _channel.invokeMethod('playAttentionTone');
    } catch (_) {
      // Desktop alerts are best-effort.
    }
  }

  static Future<void> playSuccessSound() async {
    if (!supportsDesktopSounds) {
      return;
    }
    try {
      await _channel.invokeMethod('playSuccessTone');
    } catch (_) {
      // Desktop alerts are best-effort.
    }
  }

  static Future<void> showAndroidNotification({
    required String title,
    required String body,
    required bool success,
  }) async {
    if (!supportsAndroidNotifications) {
      return;
    }
    try {
      await _channel.invokeMethod('showMonitoringNotification', {
        'title': title,
        'body': body,
        'success': success,
      });
    } catch (_) {
      // Best-effort on Android; continue silently if unavailable.
    }
  }
}
