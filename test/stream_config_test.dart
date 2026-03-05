import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bambu_lan/main.dart';

void main() {
  test('hardware accel disabled on linux to avoid blue video', () {
    expect(isAccelSupported(platformOverride: TargetPlatform.linux), isFalse);
  });

  test('hardware accel allowed on other platforms', () {
    expect(isAccelSupported(platformOverride: TargetPlatform.windows), isTrue);
    expect(isAccelSupported(platformOverride: TargetPlatform.android), isTrue);
  });
}
