enum PrinterUrlType { bambuX1C, bambuP1S, genericRtsp, custom }

extension PrinterUrlTypeX on PrinterUrlType {
  String get displayName => switch (this) {
    PrinterUrlType.bambuX1C => 'Bambu X1C',
    PrinterUrlType.bambuP1S => 'Bambu P1S',
    PrinterUrlType.genericRtsp => 'Generic RTSP',
    PrinterUrlType.custom => 'Custom',
  };

  // Stable key used for persistence
  String get storageKey => switch (this) {
    PrinterUrlType.bambuX1C => 'bambu_x1c',
    PrinterUrlType.bambuP1S => 'bambu_p1s',
    PrinterUrlType.genericRtsp => 'generic_rtsp',
    PrinterUrlType.custom => 'custom',
  };

  String get template => switch (this) {
    PrinterUrlType.bambuX1C =>
      'rtsps://bblp:\${specialcode}@\${printerip}:322/streaming/live/1',
    PrinterUrlType.bambuP1S =>
      'rtsps://bblp:\${specialcode}@\${printerip}:322/streaming/live/1',
    PrinterUrlType.genericRtsp => 'rtsp://\${printerip}:554/stream',
    PrinterUrlType.custom => '',
  };

  static PrinterUrlType parse(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'bambu x1c':
      case 'bambu_x1c':
        return PrinterUrlType.bambuX1C;
      case 'bambu p1s':
      case 'bambu_p1s':
        return PrinterUrlType.bambuP1S;
      case 'generic rtsp':
      case 'generic_rtsp':
        return PrinterUrlType.genericRtsp;
      case 'custom':
      default:
        return PrinterUrlType.custom;
    }
  }
}
