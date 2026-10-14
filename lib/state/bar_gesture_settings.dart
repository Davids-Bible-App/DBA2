// lib/state/bar_gesture_settings.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which bar a gesture happened on.
enum BarSide { top, bottom }

/// The gestures every bar listens for.
enum BarGesture {
  swipe,
  twoFingerSwipe,
  longPress,
  doubleTap;

  /// Label for the settings screen. Top bar swipes DOWN, bottom bar swipes UP.
  String label(BarSide side) {
    final dir = side == BarSide.top ? 'down' : 'up';
    switch (this) {
      case BarGesture.swipe:
        return '1-finger swipe $dir';
      case BarGesture.twoFingerSwipe:
        return '2-finger swipe $dir';
      case BarGesture.longPress:
        return 'Long press';
      case BarGesture.doubleTap:
        return 'Double tap';
    }
  }
}

/// Everything a gesture can be assigned to. Add new features here, then
/// handle them in `BarActionRunner.run` (lib/ui/bar_action_runner.dart).
enum BarAction {
  none('Nothing'),
  openLeftSidebar('Left sidebar'),
  openRightSidebar('Right sidebar'),
  audioPlayer('Audio player'),
  previousChapter('Previous chapter'),
  nextChapter('Next chapter'),
  history('History'),
  settings('Settings'),
  strongs('Strongs'),
  memes('Memes'),
  mdEditor('MDEditor'),
  audio('Audio'),
  refresh('Refresh');

  const BarAction(this.label);
  final String label;
}

/// Stores which [BarAction] each gesture triggers, persisted in
/// SharedPreferences.
class BarGestureSettings extends ChangeNotifier {
  BarGestureSettings(this._prefs) {
    for (final side in BarSide.values) {
      for (final g in BarGesture.values) {
        final k = _key(side, g);
        final saved = _prefs.getString('$_prefix.$k');
        if (saved == null) continue;
        _map[k] = BarAction.values.firstWhere(
          (a) => a.name == saved,
          orElse: () => BarAction.none,
        );
      }
    }
  }

  final SharedPreferences _prefs;

  static const _prefix = 'bar_gesture';
  static const Map<String, BarAction> defaults = {};

  final Map<String, BarAction> _map = {};

  static String _key(BarSide side, BarGesture gesture) =>
      '${side.name}.${gesture.name}';

  BarAction actionFor(BarSide side, BarGesture gesture) {
    final k = _key(side, gesture);
    return _map[k] ?? defaults[k] ?? BarAction.none;
  }

  Future<void> setAction(
    BarSide side,
    BarGesture gesture,
    BarAction action,
  ) async {
    final k = _key(side, gesture);
    _map[k] = action;
    notifyListeners();
    try {
      await _prefs.setString('$_prefix.$k', action.name);
    } catch (e) {
      debugPrint('BarGestureSettings.setAction failed: $e');
    }
  }

  Future<void> resetAll() async {
    _map.clear();
    notifyListeners();
    try {
      for (final side in BarSide.values) {
        for (final g in BarGesture.values) {
          await _prefs.remove('$_prefix.${_key(side, g)}');
        }
      }
    } catch (e) {
      debugPrint('BarGestureSettings.resetAll failed: $e');
    }
  }
}
