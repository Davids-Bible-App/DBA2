import 'package:flutter/foundation.dart';
import 'package:dba2/storage/profile/profile_settings.dart';

/// Which bar a gesture happened on.
enum BarSide { top, bottom }

/// The gestures every bar listens for.
enum BarGesture {
  swipe, // top bar: down, bottom bar: up
  swipeLeft,
  swipeRight,
  longPress,
  doubleTap;

  /// Label for the settings screen. Top bar swipes DOWN, bottom bar swipes UP.
  String label(BarSide side) {
    switch (this) {
      case BarGesture.swipe:
        return side == BarSide.top ? 'Swipe down' : 'Swipe up';
      case BarGesture.swipeLeft:
        return 'Swipe left';
      case BarGesture.swipeRight:
        return 'Swipe right';
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
  bibleAi('BibleChat'),
  mdEditor('Markdown Editor'),
  settings('Settings'),
  strongs('Strongs'),
  search('Search'),
  translations('Translations'),
  mememaker('MemeMaker'),
  references('References');

  const BarAction(this.label);
  final String label;
}

// ═══════════════════════════════════════════════════════════════════════════
// DEFAULT GESTURES: edit this table.
//
// Used when nothing is saved in profile.db for that gesture (fresh install,
// after "Reset gestures", or after "Reset all settings").
// Any gesture you leave out defaults to BarAction.none ("Nothing").
//
// Format:  (BarSide.<top|bottom>, BarGesture.<gesture>): BarAction.<action>,
//
// Sides:    top, bottom
// Gestures: swipe, swipeLeft, swipeRight, longPress, doubleTap.
// Actions:  none, openLeftSidebar, openRightSidebar, audioPlayer,
//           previousChapter, nextChapter, history, settings, strongs,
//           memes, mdEditor, translations
// ═══════════════════════════════════════════════════════════════════════════
final Map<(BarSide, BarGesture), BarAction> kDefaultBarGestures = {
  // Top bar
  (BarSide.top, BarGesture.swipe): BarAction.search,
  (BarSide.top, BarGesture.swipeLeft): BarAction.none,
  (BarSide.top, BarGesture.swipeRight): BarAction.none,
  (BarSide.top, BarGesture.longPress): BarAction.mdEditor,
  (BarSide.top, BarGesture.doubleTap): BarAction.references,

  // Bottom bar
  (BarSide.bottom, BarGesture.swipe): BarAction.audioPlayer,
  (BarSide.bottom, BarGesture.swipeLeft): BarAction.none,
  (BarSide.bottom, BarGesture.swipeRight): BarAction.none,
  (BarSide.bottom, BarGesture.doubleTap): BarAction.mememaker,
  (BarSide.bottom, BarGesture.longPress): BarAction.settings,
};

/// Stores which [BarAction] each gesture triggers, persisted in profile.db.
class BarGestureSettings extends ChangeNotifier {
  BarGestureSettings(this._store) {
    _load();
  }

  final ProfileSettings _store;

  static const _prefix = 'bar_gesture';

  final Map<String, BarAction> _map = {};

  static String _key(BarSide side, BarGesture gesture) =>
      '${side.name}.${gesture.name}';

  void _load() {
    _map.clear();
    for (final side in BarSide.values) {
      for (final g in BarGesture.values) {
        final k = _key(side, g);
        final saved = _store.getString('$_prefix.$k');
        if (saved == null) continue;
        final match = BarAction.values.where((a) => a.name == saved);
        if (match.isNotEmpty) _map[k] = match.first;
      }
    }
  }

  /// Re-reads from the DB (used after an import).
  void reload() {
    _load();
    notifyListeners();
  }

  BarAction actionFor(BarSide side, BarGesture gesture) =>
      _map[_key(side, gesture)] ??
      kDefaultBarGestures[(side, gesture)] ??
      BarAction.none;

  Future<void> setAction(
    BarSide side,
    BarGesture gesture,
    BarAction action,
  ) async {
    final k = _key(side, gesture);
    _map[k] = action;
    notifyListeners();
    await _store.setString('$_prefix.$k', action.name);
  }

  Future<void> resetAll() async {
    _map.clear();
    notifyListeners();
    for (final side in BarSide.values) {
      for (final g in BarGesture.values) {
        await _store.remove('$_prefix.${_key(side, g)}');
      }
    }
  }

  /// Sets every gesture to "Nothing" and saves each one to profile.db.
  /// Saved rows beat [kDefaultBarGestures], so the choice survives restarts.
  Future<void> clearAll() async {
    for (final side in BarSide.values) {
      for (final g in BarGesture.values) {
        _map[_key(side, g)] = BarAction.none;
      }
    }
    notifyListeners(); // dropdowns update instantly
    for (final side in BarSide.values) {
      for (final g in BarGesture.values) {
        await _store.setString(
          '$_prefix.${_key(side, g)}',
          BarAction.none.name,
        );
      }
    }
  }
}
