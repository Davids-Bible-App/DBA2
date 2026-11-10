import 'package:flutter/material.dart';
import 'package:dba2/storage/profile/profile_settings.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeProvider(this._store) : _themeMode = _read(_store);

  final ProfileSettings _store;
  ThemeMode _themeMode;
  ThemeMode get themeMode => _themeMode;

  static ThemeMode _read(ProfileSettings s) => ThemeMode.values.firstWhere(
    (m) => m.name == s.getString(_key),
    orElse: () => ThemeMode.system,
  );

  /// Re-reads from the DB (used after an import).
  void reload() {
    _themeMode = _read(_store);
    notifyListeners();
  }

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
      await _store.setString(_key, mode.name);
    } catch (e) {
      debugPrint('Failed to save theme: $e');
    }
  }
}
