// lib/ui/bar_gesture_detector.dart
import 'package:dba2/state/bar_gesture_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'bar_action_runner.dart';

/// Wraps a bar and turns swipes / long press / double tap into
/// [BarAction]s, using whatever the user chose in [BarGestureSettings].
///
/// Swipes are tracked with a raw [Listener] (it never competes in the gesture
/// arena), so buttons inside the bar keep working and 2-finger swipes are
/// detected reliably. Long press and double tap use a normal GestureDetector;
/// buttons inside the bar still win their own taps.
class BarGestureDetector extends StatefulWidget {
  const BarGestureDetector({
    super.key,
    required this.side,
    required this.runner,
    required this.child,
  });

  final BarSide side;
  final BarActionRunner runner;
  final Widget child;

  @override
  State<BarGestureDetector> createState() => _BarGestureDetectorState();
}

class _BarGestureDetectorState extends State<BarGestureDetector> {
  static const double _minSwipe =
      40; // logical px travelled in the right direction
  static const Duration _maxSwipeTime = Duration(milliseconds: 700);

  final Map<int, Offset> _start = {};
  final Map<int, Offset> _last = {};
  final Set<int> _active = {};
  final Stopwatch _clock = Stopwatch();
  int _maxPointers = 0;

  void _fire(BarGesture gesture) {
    final action = context.read<BarGestureSettings>().actionFor(
      widget.side,
      gesture,
    );
    if (action == BarAction.none) return;
    HapticFeedback.selectionClick();
    widget.runner.run(context, action);
  }

  void _reset() {
    _start.clear();
    _last.clear();
    _active.clear();
    _clock
      ..stop()
      ..reset();
    _maxPointers = 0;
  }

  void _onDown(PointerDownEvent e) {
    if (_active.isEmpty) {
      _reset();
      _clock.start();
    }
    _active.add(e.pointer);
    _start[e.pointer] = e.position;
    _last[e.pointer] = e.position;
    if (_active.length > _maxPointers) _maxPointers = _active.length;
  }

  void _onMove(PointerMoveEvent e) {
    if (_last.containsKey(e.pointer)) _last[e.pointer] = e.position;
  }

  void _onUp(PointerUpEvent e) {
    if (!_last.containsKey(e.pointer)) return;
    _last[e.pointer] = e.position;
    _active.remove(e.pointer);
    if (_active.isEmpty) {
      _evaluate();
      _reset();
    }
  }

  void _onCancel(PointerCancelEvent e) {
    _active.remove(e.pointer);
    if (_active.isEmpty) _reset();
  }

  void _evaluate() {
    if (_maxPointers < 1 || _maxPointers > 2) return;
    if (_clock.elapsed > _maxSwipeTime) return;

    // Top bar swipes down (+dy), bottom bar swipes up (-dy).
    final sign = widget.side == BarSide.top ? 1.0 : -1.0;

    for (final id in _start.keys) {
      final d = _last[id]! - _start[id]!;
      final along = d.dy * sign;
      if (along < _minSwipe) return; // too short / wrong direction
      if (d.dx.abs() > along) return; // more sideways than vertical
    }

    _fire(
      _maxPointers == 1 ? BarGesture.swipe : BarGesture.twoFingerSwipe,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: () => _fire(BarGesture.doubleTap),
        onLongPress: () => _fire(BarGesture.longPress),
        child: widget.child,
      ),
    );
  }
}
