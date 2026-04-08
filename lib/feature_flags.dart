abstract final class FeatureFlags {
  static const bool ftpBrowserEnabled = bool.fromEnvironment(
    'BAMBU_ENABLE_FTP',
    defaultValue: true,
  );
}
