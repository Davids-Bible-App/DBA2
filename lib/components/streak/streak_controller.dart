import 'dart:async';
import 'dart:convert';

import 'package:dba2/storage/profile/profile_settings.dart';
import 'package:flutter/widgets.dart';

import 'streak_data.dart';

/// Counts one "open" per local day. Stored in profile.db via [ProfileSettings].
///
/// - Loaded synchronously in the constructor, so the first frame is correct.
/// - Only writes when the record actually changed.
/// - Re-checks at local midnight AND when the app returns to the foreground
///   (timers don't reliably fire while an Android app is backgrounded).
class StreakController extends ChangeNotifier with WidgetsBindingObserver {
  StreakController(
    this._store, {
    this._clock = DateTime.now,
  }) : _data = _read(_store);

  static const _key = 'streak_data';

  final ProfileSettings _store;
  final DateTime Function() _clock;

  StreakData _data;
  StreakData get data => _data;

  bool _disposed = false;
  Timer? _midnightTimer;
  Future<void> _queue = Future.value(); // serialises checks

  static StreakData _read(ProfileSettings s) {
    try {
      final raw = s.getString(_key);
      if (raw == null || raw.isEmpty) return StreakData.empty;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return StreakData.empty;
      return StreakData.fromJson(decoded);
    } catch (e) {
      debugPrint('StreakController read failed: $e');
      return StreakData.empty;
    }
  }

  /// Call once, right after creating the controller.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    // Count today immediately (no listeners yet, so no notify needed).
    final next = computeUpdated(_data, _clock());
    if (next != _data) {
      _data = next;
      unawaited(_save(next));
    }
    _scheduleMidnight();
  }

  /// Count today (no-op if already counted).
  Future<void> check() => _queue = _queue.then((_) => _check());

  Future<void> _check() async {
    if (_disposed) return;
    final next = computeUpdated(_data, _clock());
    if (next == _data) return;
    _data = next;
    notifyListeners();
    await _save(next);
  }

  /// Re-read from the DB (call after a profile import, like ThemeProvider.reload).
  void reload() {
    _data = _read(_store);
    notifyListeners();
    check();
  }

  Future<void> _save(StreakData d) async {
    try {
      await _store.setString(_key, jsonEncode(d.toJson()));
    } catch (e) {
      debugPrint('StreakController save failed: $e');
    }
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = _clock();
    final wait =
        DateTime(now.year, now.month, now.day + 1).difference(now) +
        const Duration(milliseconds: 500);
    _midnightTimer = Timer(wait, () {
      check();
      _scheduleMidnight();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      check();
      _scheduleMidnight(); // timers can drift after sleep/suspend
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
