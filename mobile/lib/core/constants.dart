/// Global constants used across the PlantDoctor application.
class AppConstants {
  AppConstants._();

  static const String appName = 'PlantDoctor';
  static const String tagline = 'Understand your plants. Protect their health.';
  static const String version = '1.0.0';

  /// Maximum number of photos that can be analysed per scan.
  static const int maxScanImages = 4;

  /// Minimum number of photos required to start an analysis.
  static const int minScanImages = 1;

  /// Downscaled working image size to keep analysis fast on phones.
  static const int analysisMaxDimension = 640;

  /// Confidence below which plant identification is reported as uncertain.
  static const double identificationUncertaintyThreshold = 0.45;
}

/// Keys used for precious storage (SharedPreferences + SQLite metadata).
class StorageKeys {
  StorageKeys._();

  static const String settingsBox = 'plantdoctor_settings';
  static const String showDisclaimers = 'show_disclaimers';
  static const String scienceFairMode = 'science_fair_mode';
  static const String dbName = 'plantdoctor.db';
  static const int dbVersion = 1;
}