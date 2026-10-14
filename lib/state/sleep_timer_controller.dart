// lib/state/sleep_timer_controller.dart

// The player is created lazily by AudioController, so this class must never
// touch `audio.player` directly. It uses audio.play() / audio.pause() instead.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controllers/audio_controller.dart';

class SleepTimerController extends ChangeNotifier {
  SleepTimerController(this.audio);

  final AudioController audio;
  StreamSubscription<Duration>? _posSub;
  Timer? _ticker;
  DateTime? _deadline;

  // What the user picked (only editable when nothing is loaded).
  int hours = 0;
  int minutes = 0;

  int secondsLeft = 0; // > 0 while running OR paused
  bool isActive = false; // true only while counting down

  int get totalSeconds => hours * 3600 + minutes * 60;
  bool get hasTime => secondsLeft > 0;
  bool get editable => !isActive && !hasTime;

  // What the wheels display.
  int get dispH => hasTime ? secondsLeft ~/ 3600 : hours;
  int get dispM => hasTime ? (secondsLeft % 3600) ~/ 60 : minutes;
  int get dispS => hasTime ? secondsLeft % 60 : 0;

  void setHours(int v) {
    if (!editable || v == hours) return;
    hours = v;
    notifyListeners();
  }

  void setMinutes(int v) {
    if (!editable || v == minutes) return;
    minutes = v;
    notifyListeners();
  }

  /// Start / Resume. Also starts the audio if it isn't playing.
  Future<void> begin() async {
    if (isActive) return;
    final seed = secondsLeft == 0 ? totalSeconds : secondsLeft;
    if (seed <= 0) return;

    _deadline = DateTime.now().add(Duration(seconds: seed));
    secondsLeft = seed;
    isActive = true;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _check());
    notifyListeners();

    // Loads the chapter first if nothing is loaded yet, then plays.
    await audio.play();

    // The player exists now: also check the deadline on every position update.
    _posSub ??= audio.player.positionStream.listen((_) => _check());
  }

  /// "Stop" button: pause the countdown and the audio, keep the remaining time.
  void pauseTimer() {
    if (!isActive) return;
    _check();
    if (!isActive) return; // it just finished
    _ticker?.cancel();
    _deadline = null;
    isActive = false;
    audio.pause();
    notifyListeners();
  }

  /// First press clears the countdown (picker shows the set time again),
  /// second press clears the picker.
  void reset() {
    _ticker?.cancel();
    _deadline = null;
    isActive = false;
    if (secondsLeft == 0) {
      hours = 0;
      minutes = 0;
    } else {
      secondsLeft = 0;
    }
    notifyListeners();
  }

  void _check() {
    final d = _deadline;
    if (!isActive || d == null) return;
    final remaining = (d.difference(DateTime.now()).inMilliseconds / 1000)
        .ceil();
    if (remaining <= 0) {
      _finish();
    } else if (remaining != secondsLeft) {
      secondsLeft = remaining;
      notifyListeners();
    }
  }

  void _finish() {
    _ticker?.cancel();
    _deadline = null;
    secondsLeft = 0;
    isActive = false;
    audio.pause();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _posSub?.cancel();
    super.dispose();
  }
}
