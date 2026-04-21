abstract final class FeatureFlags {
  static const bool ftpBrowserEnabled = bool.fromEnvironment(
    'BAMBU_ENABLE_FTP',
    defaultValue: true,
  );

  static const bool speedControlEnabled = bool.fromEnvironment(
    'BAMBU_ENABLE_SPEED_CONTROL',
    defaultValue: true,
  );
}
