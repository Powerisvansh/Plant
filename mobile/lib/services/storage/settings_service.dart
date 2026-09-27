import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';

/// User-adjustable app settings.
class AppSettings {
  const AppSettings({
    required this.showDisclaimers,
    required this.scienceFairMode,
  });

  final bool showDisclaimers;
  final bool scienceFairMode;

  AppSettings copyWith({bool? showDisclaimers, bool? scienceFairMode}) =>
      AppSettings(
        showDisclaimers: showDisclaimers ?? this.showDisclaimers,
        scienceFairMode: scienceFairMode ?? this.scienceFairMode,
      );
}

/// Persists settings with [SharedPreferences]. No account or cloud state.
class SettingsService {
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      showDisclaimers: prefs.getBool(StorageKeys.showDisclaimers) ?? true,
      scienceFairMode: prefs.getBool(StorageKeys.scienceFairMode) ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.showDisclaimers, settings.showDisclaimers);
    await prefs.setBool(StorageKeys.scienceFairMode, settings.scienceFairMode);
  }
}