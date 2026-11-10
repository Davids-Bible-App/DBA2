import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine_locator.dart';

/// User switches for Bible AI. Lives outside the engine so Settings can
/// change them before the engine has ever been created.
class AiPrefs extends ChangeNotifier {
  AiPrefs(this._p);
  final SharedPreferences _p;

  static const idleChoices = [5, 10, 20]; // minutes

  bool get enabled => _p.getBool('ai_enabled') ?? false;
  bool get idleUnload => _p.getBool('ai_idle_unload') ?? false;
  int get idleMinutes {
    final v = _p.getInt('ai_idle_minutes') ?? 10;
    return idleChoices.contains(v) ? v : 10;
  }

  bool _available = false;

  /// True when this device/build has a usable engine (Windows can download one).
  bool get available => _available;

  /// What menus and settings should check.
  bool get visible => enabled && _available;

  Future<void> detectAvailability() async {
    final ok = EngineLocator.canDownload || await EngineLocator.find() != null;
    if (ok != _available) {
      _available = ok;
      notifyListeners();
    }
  }

  void setEnabled(bool v) {
    _p.setBool('ai_enabled', v);
    notifyListeners();
  }

  void setIdleUnload(bool v) {
    _p.setBool('ai_idle_unload', v);
    notifyListeners();
  }

  void setIdleMinutes(int v) {
    _p.setInt('ai_idle_minutes', v);
    notifyListeners();
  }
}
