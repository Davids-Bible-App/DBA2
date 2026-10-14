import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/translation_store.dart';
import 'bible_controller.dart';
import 'pane_scroll_sync.dart';
import 'translation_pane.dart';

enum SplitMode { auto, stacked, sideBySide }

const double kMinSplitRatio = 0.2;
const double kMaxSplitRatio = 0.8;

/// Everything about the split view. The primary pane stays in
/// BibleController; [panes] are the extra ones (the UI shows the first).
class SplitController extends ChangeNotifier {
  SplitController(this._prefs, this._store, this.bible) {
    enabled = _prefs.getBool(_kEnabled) ?? false;
    mode = SplitMode.values[(_prefs.getInt(_kMode) ?? 0).clamp(0, 2)];
    ratio = (_prefs.getDouble(_kRatio) ?? 0.5).clamp(
      kMinSplitRatio,
      kMaxSplitRatio,
    );
    locked = _prefs.getBool(_kLocked) ?? true;

    sync = PaneScrollSync(bible.readerScroll)..locked = locked;
    bible.externalVerseText = _verseText;
    bible.addListener(_onBible);

    _restorePanes();
    _onBible();
  }

  static const _kEnabled = 'splitEnabled';
  static const _kMode = 'splitMode';
  static const _kRatio = 'splitRatio';
  static const _kLocked = 'splitLocked';
  static const _kPanes = 'splitPanes';

  final SharedPreferences _prefs;
  final TranslationStore _store;
  final BibleController bible;

  late final PaneScrollSync sync;
  final List<TranslationPane> panes = [];

  bool enabled = false;
  SplitMode mode = SplitMode.auto;
  double ratio = 0.5;
  bool locked = true;

  String _key = '';
  bool _disposed = false;

  bool usesTranslation(String id) => panes.any((p) => p.id == id);

  /// auto = landscape side by side, portrait stacked.
  bool isSideBySide(Size size) => switch (mode) {
    SplitMode.auto => size.width > size.height,
    SplitMode.stacked => false,
    SplitMode.sideBySide => true,
  };

  /// True while a finger is down on the divider; the pager ignores swipes.
  bool draggingDivider = false;

  // ---- Panes --------------------------------------------------------------

  Future<void> _restorePanes() async {
    for (final id in _prefs.getStringList(_kPanes) ?? const <String>[]) {
      final pane = await TranslationPane.open(id, _store);
      if (_disposed) {
        pane.dispose();
        return;
      }
      if (enabled) _loadPane(pane);
      panes.add(pane);
    }
    _syncFollowers();
    notifyListeners();
  }

  void _loadPane(TranslationPane pane) {
    if (bible.hasTranslation && bible.selectedBookId.isNotEmpty) {
      pane.load(bible.selectedBookId, bible.selectedChapter);
    }
  }

  void _syncFollowers() {
    sync.followers
      ..clear()
      ..addAll(panes.map((p) => p.scroll));
  }

  /// Sets (or adds) the translation shown in pane [index] and turns split on.
  Future<void> setPaneTranslation(int index, String id) async {
    final pane = await TranslationPane.open(id, _store);
    if (_disposed) {
      pane.dispose();
      return;
    }
    _loadPane(pane);
    if (index < panes.length) {
      final old = panes[index];
      panes[index] = pane;
      _retire(old);
    } else {
      panes.add(pane);
    }
    enabled = true;
    _syncFollowers();
    _save();
    notifyListeners();
  }

  // Dispose after the frame, so no widget still holds the old controller.
  void _retire(TranslationPane old) {
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _reloadPanes() {
    sync.reset();
    for (final p in panes) {
      _loadPane(p);
    }
  }

  bool get hasPane => panes.isNotEmpty;

  /// Drops the pane using [id] (if any) so its db handle is closed and the
  /// file can be deleted. Split turns itself off if no pane is left.
  Future<void> releaseTranslation(String id) async {
    final i = panes.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final pane = panes.removeAt(i);
    if (panes.isEmpty) enabled = false;
    _syncFollowers();
    _save();
    notifyListeners();
    // Wait for a frame so no widget still holds the pane's scroll controller.
    await WidgetsBinding.instance.endOfFrame;
    pane.dispose();
  }

  void _onBible() {
    if (!bible.hasTranslation || bible.isLoading) return;
    final key = '${bible.selectedBookId}|${bible.selectedChapter}';
    if (key == _key) return;
    _key = key;
    sync.reset();
    if (!enabled) return;
    _reloadPanes();
    notifyListeners();
  }

  /// Hook for BibleController.verseText: copying a selection made in a pane.
  String _verseText(String tr, String bk, int ch, int vs) {
    for (final p in panes) {
      if (p.id == tr) return p.verseText(bk, ch, vs);
    }
    return '';
  }

  // ---- Settings -----------------------------------------------------------

  void setEnabled(bool v) {
    if (enabled == v) return;
    enabled = v;
    if (v) _reloadPanes();
    _save();
    notifyListeners();
  }

  void cycleMode() {
    mode = SplitMode.values[(mode.index + 1) % SplitMode.values.length];
    _save();
    notifyListeners();
  }

  void setLocked(bool v) {
    locked = v;
    sync.locked = v;
    _save();
    notifyListeners();
  }

  void setRatio(double v) {
    ratio = v.clamp(kMinSplitRatio, kMaxSplitRatio);
    notifyListeners();
  }

  void commitRatio() => _save();

  void resetRatio() {
    ratio = 0.5;
    _save();
    notifyListeners();
  }

  void _save() {
    _prefs.setBool(_kEnabled, enabled);
    _prefs.setInt(_kMode, mode.index);
    _prefs.setDouble(_kRatio, ratio);
    _prefs.setBool(_kLocked, locked);
    _prefs.setStringList(_kPanes, panes.map((p) => p.id).toList());
  }

  @override
  void dispose() {
    _disposed = true;
    bible.removeListener(_onBible);
    bible.externalVerseText = null;
    sync.dispose();
    for (final p in panes) {
      p.dispose();
    }
    super.dispose();
  }
}
