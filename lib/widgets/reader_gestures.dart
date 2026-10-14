// lib/widgets/reader_gestures.dart
//
// Reader gestures:
//  - one finger swipe  -> one chapter (right = previous, left = next)
//  - two finger swipe  -> manual multi-paging (distance based, fixed speed)
//  - pinch             -> font size between kMinFontRem and kMaxFontRem
//
// A passive Listener does the tracking and decisions (verse taps, long-press
// selection and scrolling keep working). A horizontal drag recognizer is
// added only to CLAIM sideways drags, so the vertical scroll stops while you
// swipe instead of jumping underneath it.
import 'dart:async';

import 'package:dba2/state/overlay_lock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// PAGING SETTINGS  (changeable at runtime, e.g. from your settings screen)
// ---------------------------------------------------------------------------

class ReaderPagingSettings extends ChangeNotifier {
  bool _haptic = true;

  /// Haptic feedback on every page turn.
  bool get haptic => _haptic;
  set haptic(bool v) {
    if (v == _haptic) return;
    _haptic = v;
    notifyListeners();
  }
}

/// Shared instance. Bind your settings UI to this, e.g.
///   SwitchListTile(value: readerPaging.haptic,
///                  onChanged: (v) => readerPaging.haptic = v, ...)
final ReaderPagingSettings readerPaging = ReaderPagingSettings();

// ---------------------------------------------------------------------------
// TUNING
// ---------------------------------------------------------------------------

// Font size limits, in your settings.fontSize units.
const double kMinFontRem = 1.5;
const double kMaxFontRem = 3.0;

// Your CSS sets font-size = settings.fontSize / 2 rem, and 1rem = 16px.
// (If 1.5 to 3 should be the literal text size in rem, set kFontDivisor to 1.)
const double kFontDivisor = 2;
const double kRemPx = 16;

const double kSwipeDistance = 70; // one finger: minimum horizontal travel
const double kSwipeBias = 1.8; // horizontal travel must beat vertical by this
const double kTwoFingerSlop =
    36; // two fingers: travel before it counts as a swipe
const double kPinchSlop =
    20; // two fingers: spread change before it counts as a pinch

// --- Two-finger manual paging ---
const Duration kManualInterval = Duration(
  milliseconds: 50,
); // the single fixed manual paging speed
const double kManualPxPerPage = 20; // finger travel needed per extra page

/// Drags that START this close to the left/right edge belong to the sidebars.
/// Keep in sync with SidebarReveal.dragZoneWidth.
const double kEdgeIgnore = 50;

/// Let a mouse drag page too (handy when testing on Windows).
const bool kMouseSwipe = true;

// ---------------------------------------------------------------------------
// FONT SIZE STATE
// ---------------------------------------------------------------------------

class ReaderFontSize extends ChangeNotifier {
  ReaderFontSize({required double initialPx})
    : _rem = (initialPx * kFontDivisor / kRemPx).clamp(
        kMinFontRem,
        kMaxFontRem,
      );

  double _rem;

  /// The value in your settings.fontSize units (1.5 .. 3).
  double get rem => _rem;

  /// Logical pixels to give to ChapterView.fontSize.
  double get px => _rem / kFontDivisor * kRemPx;

  void setRem(double value) {
    final next = value.clamp(kMinFontRem, kMaxFontRem);
    if (next == _rem) return;
    _rem = next;
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// DRAG CLAIMER
// ---------------------------------------------------------------------------

/// Horizontal drag recognizer whose only job is to win the gesture arena
/// against the vertical scroll once the finger has moved sideways. It can
/// refuse pointers (sidebar edges, active selection).
class _SidewaysClaim extends HorizontalDragGestureRecognizer {
  _SidewaysClaim({required this.allow});

  final bool Function(PointerEvent) allow;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      allow(event) && super.isPointerAllowed(event);
}

// ---------------------------------------------------------------------------
// GESTURE WRAPPER
// ---------------------------------------------------------------------------

enum _Two { undecided, pinch, swipe }

class ReaderGestures extends StatefulWidget {
  const ReaderGestures({
    super.key,
    required this.child,
    required this.fontSize,
    required this.onPrevious,
    required this.onNext,
    this.isBlocked,
  });

  final Widget child;
  final ReaderFontSize fontSize;

  /// Return false when there is nowhere to go (start / end of the Bible).
  final bool Function() onPrevious;
  final bool Function() onNext;

  /// Checked at event time, e.g. () => selection.isActive.
  final bool Function()? isBlocked;

  @override
  State<ReaderGestures> createState() => _ReaderGesturesState();
}

class _ReaderGesturesState extends State<ReaderGestures> {
  final Map<int, Offset> _pos = {}; // tracked fingers
  final Set<int> _ignored = {}; // fingers we deliberately don't track

  Offset _singleStart = Offset.zero;
  bool _multi = false; // a second finger joined: no single-finger swipe
  _Two _two = _Two.undecided;
  double _baseDist = 0;
  Offset _baseCentroid = Offset.zero;
  double _baseRem = 0;
  double _padBaseRem = 0; // trackpad pinch

  // Two-finger paging state
  Timer? _repeat;
  int _paged = 0; // net pages turned in this gesture (+ next, - previous)
  int _bias = 0; // shifts the target after hitting the start/end of the Bible

  bool get _blocked =>
      overlayLocks.value > 0 || (widget.isBlocked?.call() ?? false);

  @override
  void dispose() {
    _stopPaging();
    super.dispose();
  }

  double _distance() {
    final p = _pos.values.toList();
    return (p[0] - p[1]).distance;
  }

  Offset _centroid() {
    final p = _pos.values.toList();
    return (p[0] + p[1]) / 2;
  }

  /// Horizontal travel of the two fingers from where the gesture began.
  /// Positive = toward next (fingers moved left), negative = toward previous.
  double _signedTravel() {
    if (_pos.length != 2) return 0;
    return -(_centroid().dx - _baseCentroid.dx);
  }

  /// Net pages the finger travel has earned: 0 inside the slop, then one page
  /// at the slop and one more per kManualPxPerPage, in either direction.
  int _rawTarget(double travel) {
    final a = travel.abs();
    if (a < kTwoFingerSlop) return 0;
    final n = 1 + ((a - kTwoFingerSlop) / kManualPxPerPage).floor();
    return travel > 0 ? n : -n;
  }

  // ---- paging ----

  bool _step({required bool forward}) {
    final moved = forward ? widget.onNext() : widget.onPrevious();
    if (moved && readerPaging.haptic) HapticFeedback.selectionClick();
    return moved;
  }

  void _startPaging() {
    _stopPaging();
    _paged = 0;
    _bias = 0;
    _pageTick();
    _repeat = Timer.periodic(kManualInterval, (_) => _pageTick());
  }

  /// One paging step toward where the fingers are. Fingers still = no step.
  /// Fingers moved back = steps in reverse, at the same fixed speed.
  void _pageTick() {
    if (_pos.length < 2) {
      _stopPaging();
      return;
    }
    final raw = _rawTarget(_signedTravel());
    final target = raw - _bias;
    if (_paged == target) return;

    final forward = target > _paged;
    if (_step(forward: forward)) {
      _paged += forward ? 1 : -1;
    } else {
      // Start/end of the Bible: treat this finger position as the edge, so
      // pulling back reverses immediately instead of after a dead zone.
      _bias = raw - _paged;
    }
  }

  void _stopPaging() {
    _repeat?.cancel();
    _repeat = null;
  }

  // ---- drag claimer filter ----

  bool _allowClaim(PointerEvent e) {
    if (_blocked) return false;
    if (e.kind == PointerDeviceKind.mouse &&
        !(kMouseSwipe && (e.buttons & kPrimaryMouseButton) != 0)) {
      return false;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final x = box.globalToLocal(e.position).dx;
    return x >= kEdgeIgnore && x <= box.size.width - kEdgeIgnore;
  }

  // ---- pointer events ----

  void _down(PointerDownEvent e) {
    final width = context.size?.width ?? 0;
    final x = e.localPosition.dx;

    // Once a finger was refused, refuse the rest until everything is lifted.
    if (_ignored.isNotEmpty || _pos.length >= 2) {
      _ignored.add(e.pointer);
      return;
    }

    final mouseOk =
        e.kind != PointerDeviceKind.mouse ||
        (kMouseSwipe && (e.buttons & kPrimaryMouseButton) != 0);
    // Only the FIRST finger is checked against the sidebar edges, so a pinch
    // may still use a thumb near the edge.
    final inEdge = _pos.isEmpty && (x < kEdgeIgnore || x > width - kEdgeIgnore);

    if (_blocked || !mouseOk || inEdge) {
      _ignored.add(e.pointer);
      return;
    }

    _pos[e.pointer] = e.localPosition;

    if (_pos.length == 1) {
      _singleStart = e.localPosition;
      _multi = false;
    } else {
      _multi = true;
      _two = _Two.undecided;
      _baseDist = _distance();
      _baseCentroid = _centroid();
      _baseRem = widget.fontSize.rem;
      _stopPaging();
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pos.containsKey(e.pointer)) return;
    _pos[e.pointer] = e.localPosition;
    if (_pos.length != 2) return;

    final d = _distance();
    final c = _centroid();
    final spread = d - _baseDist;
    final shift = c - _baseCentroid;

    if (_two == _Two.undecided) {
      if (spread.abs() > kPinchSlop && spread.abs() > shift.dx.abs()) {
        _two = _Two.pinch;
        _baseDist = d; // start from here so the text doesn't jump
        _baseRem = widget.fontSize.rem;
      } else if (shift.dx.abs() > kTwoFingerSlop &&
          shift.dx.abs() > shift.dy.abs() * kSwipeBias &&
          spread.abs() < kPinchSlop) {
        _two = _Two.swipe;
        _startPaging(); // fingers move left = next, back = reverse
      }
    } else if (_two == _Two.pinch && _baseDist > 0) {
      widget.fontSize.setRem(_baseRem * d / _baseDist);
    }
  }

  void _up(PointerEvent e) {
    if (_ignored.remove(e.pointer)) return;
    if (!_pos.containsKey(e.pointer)) return;

    // One-finger swipe: decided on release, so dragging back cancels it.
    if (e is PointerUpEvent && _pos.length == 1 && !_multi && !_blocked) {
      final d = e.localPosition - _singleStart;
      if (d.dx.abs() >= kSwipeDistance &&
          d.dx.abs() > d.dy.abs() * kSwipeBias) {
        _step(forward: d.dx < 0); // finger moves left = next chapter
      }
    }

    _pos.remove(e.pointer);
    if (_pos.length < 2) _stopPaging(); // lifting either finger stops paging
    if (_pos.isEmpty) {
      _multi = false;
      _two = _Two.undecided;
    }
  }

  // ---- desktop zoom: trackpad pinch and Ctrl + mouse wheel ----

  void _padStart(PointerPanZoomStartEvent e) =>
      _padBaseRem = widget.fontSize.rem;

  void _padUpdate(PointerPanZoomUpdateEvent e) {
    if (_blocked) return;
    if ((e.scale - 1).abs() > 0.02) {
      widget.fontSize.setRem(_padBaseRem * e.scale);
    }
  }

  void _signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed &&
        !_blocked) {
      widget.fontSize.setRem(
        widget.fontSize.rem + (e.scrollDelta.dy < 0 ? 0.1 : -0.1),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      onPointerPanZoomStart: _padStart,
      onPointerPanZoomUpdate: _padUpdate,
      onPointerSignal: _signal,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          _SidewaysClaim: GestureRecognizerFactoryWithHandlers<_SidewaysClaim>(
            () => _SidewaysClaim(allow: _allowClaim),
            // Claims sideways drags only; the Listener above decides.
            (r) => r.onUpdate = (_) {},
          ),
        },
        child: widget.child,
      ),
    );
  }
}
