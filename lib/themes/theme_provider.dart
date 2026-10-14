import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeProvider(this._prefs)
    : _themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == _prefs.getString(_key),
        orElse: () => ThemeMode.system,
      );

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  ThemeMode get themeMode => _themeMode;

  bool get followsSystem => _themeMode == ThemeMode.system;

  /// Resolves "system" to the device's actual brightness.
  bool isDark(BuildContext context) {
    switch (_themeMode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      await _prefs.setString(_key, mode.name);
    } catch (e) {
      debugPrint('Failed to save theme: $e');
    }
  }
}
