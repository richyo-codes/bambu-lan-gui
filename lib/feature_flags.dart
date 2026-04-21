abstract final class FeatureFlags {
  static const bool ftpBrowserEnabled = bool.fromEnvironment(
    'BOOMPRINT_ENABLE_FTP',
    defaultValue: true,
  );

  static const bool speedControlEnabled = bool.fromEnvironment(
    'BOOMPRINT_ENABLE_SPEED_CONTROL',
    defaultValue: true,
  );

  static const bool minMaxButtonsEnabled = bool.fromEnvironment(
    'BOOMPRINT_ENABLE_MIN_MAX_BUTTONS',
    defaultValue: true,
  );

  static const bool autoHideMinMaxOnTilingWm = bool.fromEnvironment(
    'BOOMPRINT_AUTO_HIDE_MIN_MAX_ON_TILING_WM',
    defaultValue: true,
  );
}
