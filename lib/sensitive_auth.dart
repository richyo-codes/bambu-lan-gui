import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

class SensitiveAuth {
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> authenticate({required String reason}) async {
    if (!isAndroid) return true;

    final auth = LocalAuthentication();
    try {
      final supported = await auth.isDeviceSupported();
      if (!supported) return false;

      return auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
