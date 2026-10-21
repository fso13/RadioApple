import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { system, light, dark }

final themeService = ThemeService();

class ThemeService extends ChangeNotifier {
  static const _prefsKey = 'theme_preference';

  AppThemePreference _preference = AppThemePreference.system;
  bool _loaded = false;

  AppThemePreference get preference => _preference;
  bool get isLoaded => _loaded;

  ThemeMode get themeMode {
    switch (_preference) {
      case AppThemePreference.system:
        return ThemeMode.system;
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _preference = switch (raw) {
      'light' => AppThemePreference.light,
      'dark' => AppThemePreference.dark,
      _ => AppThemePreference.system,
    };
    _loaded = true;
    notifyListeners();
  }

  Future<void> setPreference(AppThemePreference preference) async {
    if (_preference == preference) return;
    _preference = preference;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      switch (preference) {
        AppThemePreference.system => 'system',
        AppThemePreference.light => 'light',
        AppThemePreference.dark => 'dark',
      },
    );
  }
}
