// The player is created lazily by AudioController, so this class must never
// touch `audio.player` directly. It uses audio.play() / audio.pause() instead.
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'audio_controller.dart';

class SleepTimerController extends ChangeNotifier with WidgetsBindingObserver {
  SleepTimerController(this.audio) {
    _appResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  final AudioController audio;
  Timer? _deadlineTimer;
  Timer? _displayTicker;
  StreamSubscription<Duration>? _positionSubscription;
  DateTime? _deadline;
  bool _panelVisible = false;
  bool _appResumed = false;

  // What the user picked (only editable when nothing is loaded).
  int hours = 0;
  int minutes = 0;

  int secondsLeft = 0; // > 0 while running OR paused
  bool isActive = false; // true only while counting down

  int get totalSeconds => hours * 3600 + minutes * 60;
  bool get hasTime => secondsLeft > 0;
  bool get editable => !isActive && !hasTime;

  void setPanelVisible(bool visible) {
    if (_panelVisible == visible) return;
    _panelVisible = visible;
    _updateDisplayTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _updateDisplayTicker();
  }

  void _updateDisplayTicker() {
    _check(notify: _panelVisible && _appResumed);
    final shouldTick = _panelVisible && _appResumed && isActive;
    if (shouldTick && _displayTicker == null) {
      if (!isActive) return;
      _displayTicker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _check(),
      );
    } else if (!shouldTick) {
      _displayTicker?.cancel();
      _displayTicker = null;
    }
  }

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
    _deadlineTimer?.cancel();
    _deadlineTimer = Timer(Duration(seconds: seed), _finish);
    _positionSubscription ??= audio.player.positionStream.listen(
      (_) => _check(notify: _panelVisible && _appResumed),
    );
    _updateDisplayTicker();
    notifyListeners();

    // Loads the chapter first if nothing is loaded yet, then plays.
    await audio.play();
  }

  /// "Stop" button: pause the countdown and the audio, keep the remaining time.
  void pauseTimer() {
    if (!isActive) return;
    _check();
    if (!isActive) return; // it just finished
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _displayTicker?.cancel();
    _displayTicker = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _deadline = null;
    isActive = false;
    audio.pause();
    notifyListeners();
  }

  /// First press clears the countdown (picker shows the set time again),
  /// second press clears the picker.
  void reset() {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _displayTicker?.cancel();
    _displayTicker = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
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

  void _check({bool notify = true}) {
    final d = _deadline;
    if (!isActive || d == null) return;
    final remaining = (d.difference(DateTime.now()).inMilliseconds / 1000)
        .ceil();
    if (remaining <= 0) {
      _finish(notify: notify);
    } else if (remaining != secondsLeft) {
      secondsLeft = remaining;
      if (notify) notifyListeners();
    }
  }

  void _finish({bool notify = true}) {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _displayTicker?.cancel();
    _displayTicker = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _deadline = null;
    secondsLeft = 0;
    isActive = false;
    audio.pause();
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deadlineTimer?.cancel();
    _displayTicker?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
