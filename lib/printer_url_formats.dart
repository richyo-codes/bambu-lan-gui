enum PrinterUrlType {
  bambuX1C,
  genericRtsp,
  custom,
}

extension PrinterUrlTypeX on PrinterUrlType {
  String get displayName => switch (this) {
        PrinterUrlType.bambuX1C => 'Bambu X1C',
        PrinterUrlType.genericRtsp => 'Generic RTSP',
        PrinterUrlType.custom => 'Custom',
      };

  // Stable key used for persistence
  String get storageKey => switch (this) {
        PrinterUrlType.bambuX1C => 'bambu_x1c',
        PrinterUrlType.genericRtsp => 'generic_rtsp',
        PrinterUrlType.custom => 'custom',
      };

  String get template => switch (this) {
        PrinterUrlType.bambuX1C =>
            'rtsps://bblp:\${specialcode}@\${printerip}:322/streaming/live/1',
        PrinterUrlType.genericRtsp => 'rtsp://\${printerip}:554/stream',
        PrinterUrlType.custom => '',
      };

  static PrinterUrlType parse(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'bambu x1c':
      case 'bambu_x1c':
        return PrinterUrlType.bambuX1C;
      case 'generic rtsp':
      case 'generic_rtsp':
        return PrinterUrlType.genericRtsp;
      case 'custom':
      default:
        return PrinterUrlType.custom;
    }
  }
}
