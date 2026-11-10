// DraggableSnapSheet
//
// One sheet for the whole app. It can be anchored to the bottom (default) or
// the top (setTop: true), is moved ONLY by its drag handle (so the content
// scrolls normally), and can snap to min / mid / max positions.
//
// Two ways to use it:
//
//   1. Embedded (persistent): put it in a Stack. The page behind stays fully
//      interactive. Control it with a DraggableSnapSheetController.
//
//        Stack(children: [
//          const MyPage(),
//          Positioned.fill(child: DraggableSnapSheet(builder: ...)),
//        ])
//
//   2. Modal: showModalSnapSheet(context: ..., builder: ...). Built on a
//      Flutter PopupRoute (the same mechanism as showModalBottomSheet), with a
//      selectable backdrop: dismissible scrim, blocking scrim, or none.
//
// ---------------------------------------------------------------------------
// SIZES
// ---------------------------------------------------------------------------
// Every position can be given as one of three kinds of size:
//
//   SheetSize.px(180)        exactly 180 logical pixels tall
//   SheetSize.percent(40)    40% of the available height (0 - 100)
//   SheetSize.fraction(0.4)  the same 40%, written as 0.0 - 1.0
//
// "Available height" is the height of the area the sheet is allowed to fill:
//   - Embedded: the height of its parent (e.g. the Positioned.fill in a Stack).
//   - Modal: the screen height, minus the keyboard, and minus the status bar /
//     gesture bar when useSafeArea is true.
//
// Pixels are Flutter LOGICAL pixels, so Windows display scaling (125%, 150%)
// does not change them. Use px when something must be an exact size (a row of
// buttons that must be visible). Use percent / fraction when the sheet should
// scale with the window.
//
// A px size is the height of the CONTENT. The drag handle (32 px) is added on
// top, so SheetSize.px(150) makes a sheet 182 px tall when the handle is
// shown. This is the same everywhere: positions, the pin, animateTo, jumpTo.
//
// Dart cannot parse "0.4%". Write SheetSize.percent(40) instead.
//
// ---------------------------------------------------------------------------
// SnapPositions: the four ways to write them
// ---------------------------------------------------------------------------
// These are the places where the USER can leave the sheet by dragging it.
//
// 1. Fractions only (the original style, still works everywhere):
//
//      const SnapPositions(min: 0.3, mid: 0.6, max: 0.9, starting: 0.6)
//      const SnapPositions.two(min: 0.23, max: 0.4)
//      const SnapPositions.fixed(0.85)
//
//    Defaults: SnapPositions() is min 0.12, mid 0.45, max 0.9. For .two,
//    starting defaults to max.
//
// 2. Any mix of px / percent / fraction, using .sized:
//
//*      // Exact collapsed height, percentage when expanded:
//      const SnapPositions.sized(
//        min: SheetSize.px(180),
//        max: SheetSize.percent(40),
//      )
//
//*      // Three positions, mixed:
//      const SnapPositions.sized(
//        min: SheetSize.px(120),
//        mid: SheetSize.percent(35),
//        max: SheetSize.fraction(0.9),
//      )
//
//*      // One fixed size (min and max equal), opening at a chosen point:
//      const SnapPositions.sized(
//        min: SheetSize.px(300),
//        max: SheetSize.px(300),
//      )
//
//    Leave mid out for two positions. starting defaults to mid, then min.
//    To open at a different size, pass starting: SheetSize.xxx(...).
//
// Rules and clean-up (applied automatically at layout time):
//   - A px size taller than the available height is clamped to full height.
//   - If min ends up larger than max, max is raised to match min.
//   - mid and starting are clamped to lie between min and max.
//   - The asserts that check min <= mid <= max only run for the fraction
//     constructors. .sized relies on the clean-up above instead.
//
// ---------------------------------------------------------------------------
// WINDOW RESIZING (desktop / tablets / rotation)
// ---------------------------------------------------------------------------
// px and percent sizes are converted to fractions every time the sheet is
// laid out. If the available height changes (window resized, device rotated,
// keyboard shown), the sheet keeps its current pixel height, then moves to the
// nearest valid position (or is only clamped, if snapOn is false). A sheet in
// compact mode (see below) stays at its pinned position instead.
//
// ---------------------------------------------------------------------------
// CONTROLLER
// ---------------------------------------------------------------------------
//   controller.snapTo(SnapPoint.min / mid / max / starting)
//   controller.animateTo(SheetSize.px(200))   // px / percent / fraction
//   controller.jumpTo(SheetSize.px(200))      // same, no animation
//   controller.animateToSize(0.5)     // a FRACTION, clamped to min..max
//   controller.jumpToSize(0.5)        // a FRACTION, no animation
//   controller.size                   // current FRACTION (0.0 - 1.0)
//   controller.currentPoint           // named point it is at, or null
//   controller.close()                // modal: pops. Embedded: collapses to min
//
// Note: animateToSize, jumpToSize, size and onSizeChanged use FRACTIONS, not
// pixels. To work in pixels, divide by the available height yourself, or use
// animateTo / jumpTo, which take a SheetSize. Prefer snapTo, which always
// lands on the resolved px / percent positions.
// The controller only works after the sheet has been built (isAttached).
//
// Create the controller in a State (or inside the function that opens the
// sheet), pass it to the sheet, and dispose it in dispose() if you made it
// in a State.
//
// ---------------------------------------------------------------------------
// MODAL OPTIONS (showModalSnapSheet)
// ---------------------------------------------------------------------------
//   backdrop:       SnapSheetBackdrop.dismissible (default), .blocking, .none
//   scrimlessAtMin: START value of the controller's scrimlessAtMin switch
//                   (see COMPACT MODE). Hides the scrim, and lets touches
//                   through, while at min.
//   unlockAtMin:    START value of the controller's unlockAtMin switch.
//                   Releases the overlay lock (the sidebars) while at min.
//   useSafeArea:    keep clear of the status bar / gesture bar
//   sheetKey:       only one sheet per key. Calling again while open CLOSES it
//                   (a toggle). closeModalSnapSheet(key) / isModalSnapSheetOpen(key)
//   setTop:         anchor to the top instead of the bottom
//   snapOn:         false = the sheet stays wherever it is released
//
// ---------------------------------------------------------------------------
// COMPACT MODE (NEW)
// ---------------------------------------------------------------------------
// Sometimes your CODE needs to move the sheet out of the way (for example
// while audio is playing), without changing the places the USER can drag it
// to. Compact mode does this using a "pin".
//
//   The PIN is a temporary position that your code sends the sheet to.
//   It can be outside min..max. When you release it, the sheet goes back
//   to the height it had before. min / mid / max / starting are not touched.
//
// While compact, you can choose (all optional):
//   - lockDrag:   the handle stays visible but cannot be dragged
//   - scrimless:  the scrim is hidden and touches go through to the page
//   - unlock:     the overlay lock is released (sidebars can be opened)
//
// A) By hand, with the controller (works for any sheet):
//
//      controller.enterCompact(
//        size: const SheetSize.px(110),  // null = go to min
//        lockDrag: true,                 // default false
//        unlock: true,                   // default true
//        scrimless: true,                // default true
//      );
//
//      controller.exitCompact();         // back to where it was
//
//      controller.isCompact              // true between enter and exit
//      controller.pinnedFraction         // the pin as a fraction, or null
//
//    The first enterCompact remembers the height. Calling it again while
//    already compact keeps the ORIGINAL height, so exitCompact always
//    returns to where the user had the sheet.
//
//    Without lockDrag the user can drag away from the pin. Because
//    positions are separate, they can only rest on min / mid / max, so the
//    sheet will not come back to the pin. For a "stay put" pin use
//    lockDrag: true.
//
// B) Automatic, from showModalSnapSheet (the easy way):
//
//      showModalSnapSheet<void>(
//        context: context,
//        sheetKey: 'audio',
//        builder: (_) => const AudioBar(),
//        compactListenable: audio,                 // what to watch
//        compactWhen: () => audio.compactMode,     // true = go compact
//        unlockWhen: () => audio.unlockWhileCompact,
//        compactSize: const SheetSize.px(110),     // null = go to min
//        compactLockDrag: true,                    // default true
//        compactScrimless: true,                   // default true
//      );
//
//    compactListenable is any ChangeNotifier (a controller, a
//    ValueNotifier, ...). Each time it notifies, compactWhen is asked:
//      false -> true : the sheet enters compact mode
//      true -> false : the sheet exits compact mode
//      still true    : only unlockWhen is re-checked, the sheet does not move
//    Only compactListenable and compactWhen are required. Leave both out
//    and the sheet works exactly as before.
//
// The switches (ValueNotifier<bool>) live on the controller, so you can also
// flip them at any time, for any sheet:
//
//      controller.unlockAtMin.value = true;
//      controller.scrimlessAtMin.value = false;
//
// "At min" means "at the pin" while a pin is active, otherwise "at min".
// The scrim and unlock switches only affect MODAL sheets. For an embedded
// sheet, enterCompact / exitCompact still move the sheet and lock dragging.
//
// ---------------------------------------------------------------------------
// EXAMPLE: one helper function used from many places (NEW)
// ---------------------------------------------------------------------------
// If a sheet is opened from several places (a menu, an AppBar button, a
// gesture), put the call in ONE function in its own file and call that
// function everywhere:
//
//      void openAudioSheet(BuildContext context) {
//        if (isModalSnapSheetOpen('audio')) {
//          closeModalSnapSheet('audio');
//          return;
//        }
//        final audio = context.read<AudioController>();
//        showModalSnapSheet<void>(
//          context: context,
//          sheetKey: 'audio',
//          positions: const SnapPositions.sized(
//            min: SheetSize.px(350),
//            max: SheetSize.px(350),
//          ),
//          builder: (_) => const AudioBar(),
//          compactListenable: audio,
//          compactWhen: () => audio.compactMode,
//          unlockWhen: () => audio.unlockWhileCompact,
//          compactSize: const SheetSize.px(110),
//        );
//      }
//
//      onPressed: () => openAudioSheet(context)
//
// ---------------------------------------------------------------------------
// OTHER NOTES
// ---------------------------------------------------------------------------
//   - resizeContent: false (default) lays the content out ONCE at the max
//     height and reveals it as the sheet grows (nothing reflows). true gives
//     the content exactly the visible area, which suits ListView / scrolling
//     content. Keep min reasonably large when using true.
//   - Swipe to close: if onClosing is set (modal sheets always have it), pulling
//     the handle about 48dp past min, or flinging it, closes the sheet.
//     While drag is locked (compact mode with lockDrag) swipe-to-close is off
//     too. Close it with the scrim, the toggle, or controller.close().
//   - Because SnapPositions and SheetSize are const classes, after editing them
//     do a hot RESTART, not a hot reload.
//   - In enterCompact the pin is set BEFORE the switches. If the switches
//     were set first, a sheet whose min equals its normal size would look
//     "at min" and release the lock too early. Keep that order if you edit it.

import 'dart:async';
import 'dart:math' as math;

import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

const double _kFlingVelocity = 700.0; // logical pixels per second
const double _kHandleAreaHeight = 32.0;
const double _kSnapEpsilon = 0.002;
const double _kCloseOverdragPixels = 48.0; // pull this far past min to close
const Duration _kPresenceDuration = Duration(milliseconds: 260);
// How far past max (as a fraction of the height) the sheet can be stretched
// while dragging or bouncing. Bigger = a more visible rubber band.
const double _kStretchLimit = 0.06;
const Duration _kRouteEnterDuration = Duration(milliseconds: 300);
const Duration _kRouteExitDuration = Duration(milliseconds: 220);

// ratio < 1.0 = slightly under-damped = a small overshoot then settle.
// 1.0 would be no bounce at all; ~0.5 would be a springy rubber band.
final SpringDescription _kSnapSpring = SpringDescription.withDampingRatio(
  mass: 1.0,
  stiffness: 420.0,
  ratio: 0.6,
);

/// Default for every sheet's `tolerantContent`. Flip to true to apply it
/// app-wide, then set `tolerantContent: false` on any sheet that has
/// Expanded / Spacer / unshrunk ListView directly in a Column.
const bool kTolerantContentDefault = false;

// ---------------------------------------------------------------------------
// Snap positions
// ---------------------------------------------------------------------------

/// Named positions you can send a sheet to with
/// [DraggableSnapSheetController.snapTo].
enum SnapPoint { min, mid, max, starting }

/// A sheet size: exact pixels, a percentage, or a 0-1 fraction of the
/// available height.
@immutable
class SheetSize {
  /// 0.0 - 1.0 of the available height.
  const SheetSize.fraction(double fraction)
    : _value = fraction,
      _isPixels = false,
      assert(fraction >= 0.0 && fraction <= 1.0, 'fraction must be 0..1');

  /// 0 - 100 percent of the available height.
  const SheetSize.percent(double percent)
    : _value = percent / 100.0,
      _isPixels = false,
      assert(percent >= 0.0 && percent <= 100.0, 'percent must be 0..100');

  /// An exact height in logical pixels.
  const SheetSize.px(double pixels)
    : _value = pixels,
      _isPixels = true,
      assert(pixels >= 0.0, 'pixels must be >= 0');

  final double _value;
  final bool _isPixels;

  /// Turns this into a 0..1 fraction of [available] (a height in pixels).
  /// px sizes are the content area, so [handleHeight] is added on top.
  double resolve(double available, {double handleHeight = 0.0}) {
    if (_isPixels) {
      if (available <= 0.0) {
        return 0.0;
      }
      return clampDouble((_value + handleHeight) / available, 0.0, 1.0);
    }
    return clampDouble(_value, 0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is SheetSize &&
      other._value == _value &&
      other._isPixels == _isPixels;

  @override
  int get hashCode => Object.hash(_value, _isPixels);
}

/// The resting positions of a sheet, described in any mix of px / % /
/// fractions.
///
///   SnapPositions(min: 0.3, mid: 0.6, max: 0.9)             // fractions
///   SnapPositions.two(min: 0.4, max: 0.9)                   // fractions
///   SnapPositions.fixed(0.85)                               // one fraction
///   SnapPositions.sized(                                    // anything
///     min: SheetSize.px(180),
///     max: SheetSize.percent(40),
///   )
@immutable
class SnapPositions {
  /// Up to three positions (fractions). Pass `mid: null` for only two.
  const SnapPositions({
    double min = 0.12,
    double? mid = 0.45,
    double max = 0.9,
    double? starting,
  }) : _min = min,
       _mid = mid,
       _max = max,
       _starting = starting ?? mid ?? min,
       _sized = null,
       assert(min >= 0.0, 'min must be >= 0'),
       assert(max <= 1.0, 'max must be <= 1'),
       assert(min <= max, 'min must be <= max'),
       assert(
         mid == null || (mid >= min && mid <= max),
         'mid must be between min and max',
       ),
       assert(
         starting == null || (starting >= min && starting <= max),
         'starting must be between min and max',
       );

  /// Two positions only (fractions). [starting] defaults to [max].
  const SnapPositions.two({
    required double min,
    required double max,
    double? starting,
  }) : _min = min,
       _mid = null,
       _max = max,
       _starting = starting ?? max,
       _sized = null,
       assert(min >= 0.0, 'min must be >= 0'),
       assert(max <= 1.0, 'max must be <= 1'),
       assert(min <= max, 'min must be <= max'),
       assert(
         starting == null || (starting >= min && starting <= max),
         'starting must be between min and max',
       );

  /// One fixed size (fraction).
  const SnapPositions.fixed(double size)
    : _min = size,
      _mid = null,
      _max = size,
      _starting = size,
      _sized = null,
      assert(size >= 0.0 && size <= 1.0, 'size must be between 0 and 1');

  /// Any mix of px / percent / fraction. Leave [mid] out for two positions,
  /// make [min] and [max] equal for one. [starting] defaults to [mid], then
  /// [min].
  const SnapPositions.sized({
    required SheetSize min,
    SheetSize? mid,
    required SheetSize max,
    SheetSize? starting,
  }) : _min = 0.0,
       _mid = null,
       _max = 0.0,
       _starting = 0.0,
       _sized = (
         min: min,
         mid: mid,
         max: max,
         starting: starting,
       );

  // Plain fractions, used by the first three constructors.
  final double _min;
  final double? _mid;
  final double _max;
  final double _starting;

  // Used only by SnapPositions.sized. Null for the others.
  final ({SheetSize min, SheetSize? mid, SheetSize max, SheetSize? starting})?
  _sized;

  SheetSize get min => _sized?.min ?? SheetSize.fraction(_min);
  SheetSize? get mid {
    final s = _sized;
    if (s != null) {
      return s.mid;
    }
    final double? m = _mid;
    return m == null ? null : SheetSize.fraction(m);
  }

  SheetSize get max => _sized?.max ?? SheetSize.fraction(_max);
  SheetSize get starting {
    final s = _sized;
    if (s != null) {
      return s.starting ?? s.mid ?? s.min;
    }
    return SheetSize.fraction(_starting);
  }

  /// True if the sheet opens at its min position.
  bool get startsAtMin => starting == min;

  /// Converts to plain fractions for a given available height in pixels.
  /// Always returns a sane result: min <= mid <= max, starting inside.
  ResolvedSnapPositions resolve(double available, {double handleHeight = 0.0}) {
    final double lo = min.resolve(available, handleHeight: handleHeight);
    final double hi = math.max(
      lo,
      max.resolve(available, handleHeight: handleHeight),
    );
    final SheetSize? midSize = mid;
    final double? m = midSize == null
        ? null
        : clampDouble(
            midSize.resolve(available, handleHeight: handleHeight),
            lo,
            hi,
          );
    final double s = clampDouble(
      starting.resolve(available, handleHeight: handleHeight),
      lo,
      hi,
    );
    return ResolvedSnapPositions._(lo, m, hi, s);
  }

  @override
  bool operator ==(Object other) =>
      other is SnapPositions &&
      other.min == min &&
      other.mid == mid &&
      other.max == max &&
      other.starting == starting;

  @override
  int get hashCode => Object.hash(min, mid, max, starting);
}

/// [SnapPositions] after conversion to fractions for one specific height.
/// This is what the sheet uses internally while dragging and animating.
@immutable
class ResolvedSnapPositions {
  const ResolvedSnapPositions._(this.min, this.mid, this.max, this.starting);

  final double min;
  final double? mid;
  final double max;
  final double starting;

  /// The snap targets in ascending order.
  List<double> get points {
    final double? m = mid;
    return <double>[min, ?m, max];
  }

  double sizeOf(SnapPoint point) {
    switch (point) {
      case SnapPoint.min:
        return min;
      case SnapPoint.mid:
        return mid ?? (min + max) / 2;
      case SnapPoint.max:
        return max;
      case SnapPoint.starting:
        return starting;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ResolvedSnapPositions &&
      other.min == min &&
      other.mid == mid &&
      other.max == max &&
      other.starting == starting;

  @override
  int get hashCode => Object.hash(min, mid, max, starting);
}

/// One-size-fits-all for every top sheet, until each gets its own.
const SnapPositions kTopSheetPositions = SnapPositions.fixed(0.85);

/// Padding for the content of a TOP sheet. The sheet is drawn right up to
/// the top of the screen, so this keeps the content below the status bar.
class SheetSafePadding extends StatelessWidget {
  const SheetSafePadding({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      12,
      MediaQuery.paddingOf(context).top + 8,
      12,
      0,
    ),
    child: child,
  );
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Lets any button or piece of logic move a [DraggableSnapSheet].
///
/// Create it in a State, pass it to the sheet, dispose it in `dispose()`.
/// Methods can only be used once the sheet has been built.
class DraggableSnapSheetController extends ChangeNotifier {
  _DraggableSnapSheetState? _state;

  /// Runtime switches. The modal route listens to these, so you can flip
  /// them at any time while the sheet is open.
  final ValueNotifier<bool> unlockAtMin = ValueNotifier<bool>(false);
  final ValueNotifier<bool> scrimlessAtMin = ValueNotifier<bool>(false);

  double? _sizeBeforeCompact;

  /// True between enterCompact() and exitCompact().
  bool get isCompact => _sizeBeforeCompact != null;

  /// The pinned position as a fraction, or null if not pinned.
  double? get pinnedFraction => _state?._pinFraction;

  /// Remembers the current height, then goes to [size] (a px / percent /
  /// fraction, may be outside min..max). With no [size] it goes to min.
  /// [lockDrag]: the handle stays visible but can't be dragged.
  void enterCompact({
    SheetSize? size,
    bool lockDrag = false,
    bool unlock = true,
    bool scrimless = true,
    bool hideHandle = false, // NEW
  }) {
    _assertAttached();
    _sizeBeforeCompact ??= this.size; // only remember the FIRST height
    _state!._setPin(size, lockDrag, hideHandle: hideHandle); // CHANGED
    unlockAtMin.value = unlock;
    scrimlessAtMin.value = scrimless;
  }

  /// Turns the switches off, unlocks dragging, returns to the old height.
  void exitCompact() {
    _assertAttached();
    unlockAtMin.value = false;
    scrimlessAtMin.value = false;
    final double? back = _sizeBeforeCompact;
    _sizeBeforeCompact = null;
    _state!._releasePin(back);
  }

  /// While compact, moves the pin to a new size (animated).
  /// Does nothing if the sheet is not compact.
  void resizeCompact(SheetSize? size) {
    _assertAttached();
    if (!isCompact) return;
    _state!._setPin(size, _state!._dragLocked); // keep the current drag lock
  }

  bool get isAttached => _state != null;

  /// Current size as a fraction of the available height.
  double get size {
    _assertAttached();
    return _state!._size;
  }

  /// The named point the sheet is currently sitting at, or null if it is
  /// somewhere in between.
  SnapPoint? get currentPoint {
    _assertAttached();
    final ResolvedSnapPositions p = _state!._pos;
    for (final SnapPoint point in <SnapPoint>[
      SnapPoint.min,
      if (p.mid != null) SnapPoint.mid,
      SnapPoint.max,
    ]) {
      if ((p.sizeOf(point) - size).abs() < 0.01) {
        return point;
      }
    }
    return null;
  }

  /// Animates to a named position.
  Future<void> snapTo(
    SnapPoint point, {
    Duration? duration,
    Curve curve = Curves.easeOutCubic,
  }) {
    _assertAttached();
    return _state!._animateToSize(
      _state!._pos.sizeOf(point),
      duration,
      curve,
    );
  }

  /// Animates to any fraction (clamped to the sheet's min..max).
  Future<void> animateToSize(
    double size, {
    Duration? duration,
    Curve curve = Curves.easeOutCubic,
  }) {
    _assertAttached();
    return _state!._animateToSize(size, duration, curve);
  }

  /// Animates to a px / percent / fraction size (clamped to min..max).
  Future<void> animateTo(
    SheetSize size, {
    Duration? duration,
    Curve curve = Curves.easeOutCubic,
  }) {
    _assertAttached();
    return _state!._animateToSize(_state!._resolveSize(size), duration, curve);
  }

  /// Moves instantly to a px / percent / fraction size.
  void jumpTo(SheetSize size) {
    _assertAttached();
    _state!._jumpToSize(_state!._resolveSize(size));
  }

  /// Moves instantly, no animation.
  void jumpToSize(double size) {
    _assertAttached();
    _state!._jumpToSize(size);
  }

  /// Modal sheets: closes (pops) the route. Embedded sheets: collapses to min.
  void close() {
    _assertAttached();
    _state!._requestClose();
  }

  void _assertAttached() {
    assert(
      isAttached,
      'DraggableSnapSheetController is not attached to a sheet yet. Pass it '
      'to a DraggableSnapSheet and wait until that sheet has been built.',
    );
  }

  void _attach(_DraggableSnapSheetState state) {
    // If Flutter reuses a State for a different sheet during a rebuild, the
    // previous owner may not have been disposed yet. Just take over; the old
    // state's _detach() is a no-op because it is no longer the owner.
    _state = state;
  }

  void _detach(_DraggableSnapSheetState state) {
    if (_state == state) {
      _state = null;
    }
  }

  void _sizeChanged() => notifyListeners();
}

// ---------------------------------------------------------------------------
// The sheet widget
// ---------------------------------------------------------------------------

class DraggableSnapSheet extends StatefulWidget {
  const DraggableSnapSheet({
    super.key,
    required this.builder,
    this.positions = const SnapPositions(),
    this.snapOn = true,
    this.setTop = false,
    this.backgroundColor,
    this.dragHandleColor,
    this.dragHandleSize = const Size(32, 4),
    this.showDragHandle = true,
    this.resizeContent = false,
    this.tolerantContent = kTolerantContentDefault,
    this.controller,
    this.onSizeChanged,
    this.onClosing,
    this.animatePresence = true,

    this.bounceOnOpen = false,
    this.shape,
    this.elevation = 1.0,
    this.shadowColor,
    this.maxWidth = 640,
    this.handleSemanticLabel = 'Resize sheet',
  });

  /// Builds the sheet's content. The content is laid out at the sheet's
  /// MAXIMUM height and revealed progressively (top-aligned), so it is not
  /// squashed when the sheet is small.
  final WidgetBuilder builder;

  /// min / mid / max / starting, as fractions of the available height.
  final SnapPositions positions;

  /// When true, releasing the handle glides to the nearest snap position (or
  /// the next one in the direction of a fast fling). When false the sheet
  /// stays exactly where it was released.
  final bool snapOn;

  /// false (default): anchored to the bottom, handle on its top edge.
  /// true: anchored to the top, handle on its bottom edge.
  final bool setTop;

  /// Sheet background. Falls back to the theme's bottom sheet colour, then to
  /// `ColorScheme.surfaceContainerLow`.
  final Color? backgroundColor;

  /// Handle colour. Falls back to the theme, then `onSurfaceVariant`.
  final Color? dragHandleColor;
  final Size dragHandleSize;

  /// If false there is no handle, so the sheet can only be moved through the
  /// [controller].
  final bool showDragHandle;

  /// How the content reacts as the sheet changes size.
  ///
  /// false (default, "reveal"): the content is laid out once at the sheet's
  /// maximum height and uncovered as the sheet grows. Nothing reflows, so
  /// fixed layouts (a player bar, a form) can't overflow when the sheet is
  /// small. A long scrollable list will have its lower part hidden until the
  /// sheet is at max, though.
  ///
  /// true ("resize"): the content is given exactly the visible area and
  /// re-laid out as the sheet moves. Use this for scrollable content (a
  /// ListView / CustomScrollView) so the scroll viewport always matches what
  /// the user can see. The content must cope with the smaller heights, so
  /// keep `min` reasonably large.
  final bool resizeContent;

  /// When true (reveal mode only), the content may be taller than the sheet's
  /// max without an overflow error. It is laid out at its natural height and
  /// clipped, never scrolled by touch. Content must not contain Expanded /
  /// Spacer / Flexible directly in a Column, or a ListView without shrinkWrap.
  final bool tolerantContent;

  final DraggableSnapSheetController? controller;

  /// Called whenever the size (fraction) changes.
  final ValueChanged<double>? onSizeChanged;

  /// Swipe-to-close. Called when, at min, the user pulls the handle about
  /// 48dp further towards the edge and releases, or flings it. Also called by
  /// [DraggableSnapSheetController.close]. The modal route uses it to pop
  /// itself. For an embedded sheet, use it to remove the sheet (e.g.
  /// `setState(() => _open = false)`). If null, the sheet just stops at min.
  final VoidCallback? onClosing;

  /// When true (default) the sheet glides in from its edge when it first
  /// appears, and glides back out before [onClosing] is called. The modal
  /// route turns this off because the route has its own slide transition.
  final bool animatePresence;

  /// When true, the sheet springs in when it first appears even if
  /// [animatePresence] is false. The modal route uses this: it springs the
  /// sheet in itself, but leaves closing to the route's own slide-out.
  final bool bounceOnOpen;

  /// Defaults to 28dp rounded corners on the free edge.
  final ShapeBorder? shape;
  final double elevation;
  final Color? shadowColor;

  /// Maximum width (centred on wide screens). Use `double.infinity` to
  /// disable.
  final double maxWidth;

  final String handleSemanticLabel;

  @override
  State<DraggableSnapSheet> createState() => _DraggableSnapSheetState();
}

class _DraggableSnapSheetState extends State<DraggableSnapSheet>
    with TickerProviderStateMixin {
  late final AnimationController _anim;

  // 0 = fully off-screen, 1 = fully present. Drives the glide in/out.
  late final AnimationController _presence;
  bool _closeRequested = false;
  // The pin: a temporary position outside the normal min/mid/max.
  SheetSize? _pin;
  bool _dragLocked = false;
  bool _handleHidden = false;
  int _pinToken = 0;

  double? get _pinFraction => _pin == null ? null : _resolveSize(_pin!);

  // The reachable range: min..max, widened to include the pin.
  double get _lo {
    final double? p = _pinFraction;
    return p == null ? _pos.min : math.min(_pos.min, p);
  }

  double get _hi {
    final double? p = _pinFraction;
    return p == null ? _pos.max : math.max(_pos.max, p);
  }

  double _available = 0.0;

  bool get _handleVisible => widget.showDragHandle && !_handleHidden;

  double get _handleHeight => _handleVisible ? _kHandleAreaHeight : 0.0;

  double _resolveSize(SheetSize size) =>
      size.resolve(_available, handleHeight: _handleHeight);

  // The positions converted to fractions for the CURRENT height. Updated on
  // every layout, so px sizes stay exact when the window changes.
  late ResolvedSnapPositions _pos;
  bool _laidOut = false;
  bool _silent = false; // true while setting the starting size during build

  // The finger's unclamped position during a drag. It can go below min, which
  // is how "pull past min to close" is detected.
  double _dragRaw = 0.0;

  double _clamp(double v) => clampDouble(v, _lo, _hi);

  double get _size => _clamp(_anim.value);

  double get _displaySize {
    final double lower = widget.onClosing != null
        ? 0.0
        : math.max(0.0, _lo - _kStretchLimit);
    return clampDouble(
      _anim.value,
      lower,
      math.min(1.0, _hi + _kStretchLimit),
    );
  }

  @override
  void initState() {
    super.initState();
    _pos = widget.positions.resolve(0.0); // placeholder until first layout
    _anim = AnimationController(vsync: this, value: 0.0)..addListener(_onTick);
    widget.controller?._attach(this);
    final bool animateIn = widget.animatePresence || widget.bounceOnOpen;
    // upperBound > 1 lets the appear-spring overshoot slightly (see build()).
    _presence = AnimationController(
      vsync: this,
      upperBound: 1.1,
      value: animateIn ? 0.0 : 1.0,
    );
    if (animateIn) {
      _presentIn();
    }
  }

  /// Slides the sheet in from its edge with the same small-bounce spring used
  /// for snapping.
  void _presentIn() {
    _presence.animateWith(
      SpringSimulation(_kSnapSpring, _presence.value, 1.0, 0.0),
    );
  }

  @override
  void didUpdateWidget(DraggableSnapSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _presence.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _onTick() {
    if (_silent) {
      return;
    }
    widget.controller?._sizeChanged();
    widget.onSizeChanged?.call(_size);
  }

  /// Called from build with the real height. Converts px/% to fractions.
  void _syncLayout(double available) {
    final ResolvedSnapPositions next = widget.positions.resolve(available);

    // First real layout: place the sheet at its starting position.
    if (!_laidOut) {
      _available = available;
      _pos = next;
      if (available > 0) {
        _laidOut = true;
        _silent = true; // don't notify listeners in the middle of a build
        _anim.value = next.starting;
        _silent = false;
      }
      return;
    }

    if (available == _available && next == _pos) {
      return;
    }

    // The window was resized (or the positions changed). Keep the sheet at the
    // same pixel height, then move it to the nearest valid position.
    final double heightPx = _anim.value * _available;
    _available = available;
    _pos = next;
    if (available <= 0) {
      return;
    }
    final double keep = heightPx / available;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || _anim.isAnimating) {
        return;
      }
      _anim.value =
          _pinFraction ??
          (widget.snapOn ? _pickTarget(keep, 0.0) : _clamp(keep));
    });
  }

  // -- programmatic movement ------------------------------------------------

  /// With no [duration], uses the same small-bounce spring as a drag release.
  /// With a [duration], plays a plain timed animation with [curve].
  Future<void> _animateToSize(
    double target,
    Duration? duration,
    Curve curve,
  ) async {
    final double to = _clamp(target);
    try {
      if (duration == null) {
        if ((to - _anim.value).abs() < 0.0005) {
          _anim.value = to;
          return;
        }
        await _anim
            .animateWith(SpringSimulation(_kSnapSpring, _anim.value, to, 0.0))
            .orCancel;
      } else {
        await _anim.animateTo(to, duration: duration, curve: curve).orCancel;
      }
    } on TickerCanceled {
      // Interrupted (e.g. the user grabbed the handle). Nothing to do.
    }
  }

  /// Closes the sheet. Embedded sheets glide off their edge first, then call
  /// [DraggableSnapSheet.onClosing]. Without an onClosing, collapses to min.
  Future<void> _requestClose() async {
    if (_closeRequested) {
      return;
    }
    final VoidCallback? onClosing = widget.onClosing;
    if (onClosing == null) {
      await _animateToSize(_pos.min, null, Curves.easeOutCubic);
      return;
    }
    if (!widget.animatePresence) {
      onClosing();
      return;
    }
    _closeRequested = true;
    try {
      await _presence
          .animateTo(
            0.0,
            duration: _kPresenceDuration,
            curve: Curves.easeInCubic,
          )
          .orCancel;
    } on TickerCanceled {
      _closeRequested = false;
      return;
    }
    if (!mounted) {
      return;
    }
    onClosing();
    // If the parent chose NOT to remove the sheet, bring it back.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        _closeRequested = false;
        _presentIn();
      }
    });
  }

  void _jumpToSize(double target) {
    _anim.stop();
    _anim.value = _clamp(target);
  }

  /// Goes to [size] (or min if null) and optionally locks dragging.
  /// [hideHandle]: true/false sets it, null leaves it as it is.
  void _setPin(SheetSize? size, bool lockDrag, {bool? hideHandle}) {
    _pinToken++;
    if (hideHandle != null && hideHandle != _handleHidden && mounted) {
      setState(() => _handleHidden = hideHandle); // BEFORE resolving the size
    }
    _pin = size;
    _dragLocked = lockDrag;
    _animateToSize(
      size == null ? _pos.min : _resolveSize(size),
      null,
      Curves.easeOutCubic,
    );
  }

  /// Unlocks dragging, goes back to [back], then forgets the pin.
  Future<void> _releasePin(double? back) async {
    final int token = ++_pinToken;
    _dragLocked = false;
    if (_handleHidden && mounted) {
      setState(() => _handleHidden = false); // NEW
    }
    if (back != null) {
      await _animateToSize(back, null, Curves.easeOutCubic);
    }
    if (token == _pinToken) {
      _pin = null; // not re-pinned in the meantime
    }
  }

  // -- dragging -------------------------------------------------------------

  void _onDragStart(DragStartDetails details) {
    if (_closeRequested || _dragLocked) {
      return;
    }
    _anim.stop();
    _dragRaw = _anim.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_available <= 0 || _closeRequested || _dragLocked) {
      return;
    }
    final double dy = details.primaryDelta ?? 0.0;
    // Bottom sheet: dragging UP grows it. Top sheet: dragging DOWN grows it.
    final double growPixels = widget.setTop ? dy : -dy;
    _dragRaw += growPixels / _available;
    _anim.value = _rubberBand(_dragRaw);
  }

  void _onDragEnd(DragEndDetails details) {
    final double vy = details.primaryVelocity ?? 0.0;
    _finishDrag(widget.setTop ? vy : -vy); // positive = growing
  }

  void _finishDrag(double growVelocity) {
    if (_closeRequested || _dragLocked) {
      return;
    }
    // "Swipe to close": at min, either pull the handle well past min and
    // release, or fling it towards the edge.
    final bool atMin = _anim.value <= _pos.min + 0.01;
    final bool pulledPastMin =
        _available > 0 &&
        (_pos.min - _dragRaw) * _available > _kCloseOverdragPixels;
    final bool flungClosed = growVelocity < -_kFlingVelocity;
    if (widget.onClosing != null && atMin && (pulledPastMin || flungClosed)) {
      _requestClose();
      return;
    }
    _dragRaw = _anim.value;
    if (!widget.snapOn) {
      // Stay where the finger left it, unless it was stretched out of range.
      final double inRange = _clamp(_anim.value);
      if ((inRange - _anim.value).abs() > 0.0005) {
        _settle(inRange, growVelocity);
      }
      return;
    }
    _settle(_pickTarget(_anim.value, growVelocity), growVelocity);
  }

  /// Turns the finger position into the sheet position. Inside min..max it is
  /// 1:1. Past max it gets harder and harder to pull (rubber band). Past min
  /// a closable sheet simply follows the finger, so it feels like dismissing.
  double _rubberBand(double raw) {
    final ResolvedSnapPositions p = _pos;
    if (raw > p.max) {
      return p.max + _resist(raw - p.max);
    }
    if (raw < p.min) {
      if (widget.onClosing != null) {
        return raw;
      }
      return p.min - _resist(p.min - raw);
    }
    return raw;
  }

  /// Starts at half the finger movement and levels off at _kStretchLimit.
  double _resist(double overshoot) =>
      _kStretchLimit * (1.0 - math.exp(-overshoot / (2.0 * _kStretchLimit)));

  double _pickTarget(double current, double growVelocity) {
    final List<double> pts = _pos.points;
    if (growVelocity.abs() > _kFlingVelocity) {
      if (growVelocity > 0) {
        return pts.firstWhere(
          (double p) => p > current + _kSnapEpsilon,
          orElse: () => pts.last,
        );
      }
      return pts.lastWhere(
        (double p) => p < current - _kSnapEpsilon,
        orElse: () => pts.first,
      );
    }
    double best = pts.first;
    for (final double p in pts) {
      if ((p - current).abs() < (best - current).abs()) {
        best = p;
      }
    }
    return best;
  }

  void _settle(double target, double growVelocityPx) {
    final double distance = target - _anim.value;
    if (distance.abs() < 0.0005) {
      _anim.value = target;
      return;
    }
    double v = growVelocityPx / _available; // fractions per second
    if (v * distance < 0) {
      v = 0; // finger was moving away from the target; don't fight it
    }
    v = clampDouble(v, -3.0, 3.0);
    _anim.animateWith(SpringSimulation(_kSnapSpring, _anim.value, target, v));
  }

  /// Screen-reader tap on the handle: step to the next snap position.
  void _cycleSnapPoint() {
    final List<double> pts = _pos.points;
    final double next = pts.firstWhere(
      (double p) => p > _size + _kSnapEpsilon,
      orElse: () => pts.first,
    );
    _animateToSize(next, null, Curves.easeOutCubic);
  }

  // -- build ----------------------------------------------------------------

  Widget _buildHandle(Color color) {
    final Size s = widget.dragHandleSize;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onVerticalDragCancel: () => _finishDrag(0.0),
      child: Semantics(
        container: true,
        button: true,
        label: widget.handleSemanticLabel,
        onTap: _dragLocked ? null : _cycleSnapPoint,
        child: SizedBox(
          height: _kHandleAreaHeight,
          width: double.infinity,
          child: Center(
            child: Container(
              width: s.width,
              height: s.height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(s.height / 2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BottomSheetThemeData sheetTheme = theme.bottomSheetTheme;
    final ColorScheme colors = theme.colorScheme;

    final Color background =
        widget.backgroundColor ??
        sheetTheme.backgroundColor ??
        colors.surfaceContainerLow;
    final Color handleColor =
        widget.dragHandleColor ??
        sheetTheme.dragHandleColor ??
        colors.onSurfaceVariant;
    final ShapeBorder shape =
        widget.shape ??
        RoundedRectangleBorder(
          borderRadius: widget.setTop
              ? const BorderRadius.vertical(bottom: Radius.circular(28))
              : const BorderRadius.vertical(top: Radius.circular(28)),
        );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        assert(
          constraints.hasBoundedHeight,
          'DraggableSnapSheet needs a bounded height. Put it in a Stack '
          '(ideally inside Positioned.fill) or another bounded parent.',
        );
        _syncLayout(constraints.maxHeight);

        final double handleHeight = _handleHeight;

        // The content is always laid out at the sheet's maximum height.
        final double fullContentHeight = math.max(
          0.0,
          _pos.max * _available - handleHeight,
        );

        Widget revealed = Builder(builder: widget.builder);
        if (widget.tolerantContent) {
          revealed = SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: fullContentHeight),
              child: revealed,
            ),
          );
        }

        final Widget content = Expanded(
          child: ClipRect(
            child: widget.resizeContent
                ? Builder(builder: widget.builder)
                : OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: fullContentHeight,
                    maxHeight: fullContentHeight,
                    child: revealed,
                  ),
          ),
        );

        final Widget? handle = _handleVisible
            ? _buildHandle(handleColor)
            : null;

        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_anim, _presence]),
          builder: (BuildContext context, Widget? _) {
            final double baseHeight = math.max(
              _displaySize * _available,
              handleHeight,
            );
            final double presence = _presence.value;
            // While appearing, the spring overshoots (presence > 1). That is
            // drawn as the sheet growing a few px taller from its edge, then
            // settling back, so it never pulls away from the screen edge.
            final double height =
                baseHeight +
                math.max(0.0, presence - 1.0) * (baseHeight + 16.0);
            final Widget sheet = Align(
              alignment: widget.setTop
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.maxWidth),
                child: SizedBox(
                  width: double.infinity,
                  height: height,
                  child: Material(
                    color: background,
                    elevation: widget.elevation,
                    shadowColor: widget.shadowColor,
                    surfaceTintColor: Colors.transparent,
                    shape: shape,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: <Widget>[
                        // Handle sits on the free edge of the sheet.
                        if (!widget.setTop && handle != null) handle,
                        content,
                        if (widget.setTop && handle != null) handle,
                      ],
                    ),
                  ),
                ),
              ),
            );
            // Glide in/out along the sheet's own edge.
            final double slide =
                (1.0 - math.min(presence, 1.0)) *
                (baseHeight + 16.0) *
                (widget.setTop ? -1.0 : 1.0);
            return Transform.translate(
              offset: Offset(0.0, slide),
              child: sheet,
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Modal version
// ---------------------------------------------------------------------------

/// What sits behind a modal sheet (think CSS `backdrop`).
enum SnapSheetBackdrop {
  /// Shaded scrim; tapping it closes the sheet. (default)
  dismissible,

  /// Shaded scrim; tapping it does nothing. The page is blocked.
  blocking,

  /// No scrim, no shading. The page behind stays fully interactive.
  none,
}

/// A modal route for [DraggableSnapSheet]. Prefer [showModalSnapSheet].
class ModalSnapSheetRoute<T> extends PopupRoute<T> {
  ModalSnapSheetRoute({
    required this.builder,
    this.positions = const SnapPositions(),
    this.snapOn = true,
    this.setTop = false,
    this.backdrop = SnapSheetBackdrop.dismissible,
    this.scrimlessAtMin = false,
    this.unlockAtMin = false,
    this.scrimColor,
    this.backgroundColor,
    this.dragHandleColor,
    this.dragHandleSize = const Size(32, 4),
    this.showDragHandle = true,
    this.resizeContent = false,
    this.useSafeArea = false,
    this.shape,
    this.elevation = 1.0,
    this.maxWidth = 640,
    this.sheetController,
    this.onSizeChanged,
    this.tolerantContent = kTolerantContentDefault,
    this.capturedThemes,
    this.barrierLabel,
    super.settings,
  });

  final WidgetBuilder builder;
  final SnapPositions positions;
  final bool snapOn;
  final bool setTop;
  final SnapSheetBackdrop backdrop;

  /// Scrim is hidden (and the page behind is touchable) while the sheet sits
  /// at its min position. Above min the normal [backdrop] applies.
  final bool scrimlessAtMin;

  /// Releases the overlay lock while the sheet sits at min, and re-takes it
  /// when the sheet grows. Pair with [scrimlessAtMin] for a quick-access min.
  final bool unlockAtMin;
  final Color? scrimColor;
  final Color? backgroundColor;
  final Color? dragHandleColor;
  final Size dragHandleSize;
  final bool showDragHandle;
  final bool resizeContent;
  final bool tolerantContent;

  /// Keeps the sheet clear of the system UI on the side it grows from (the
  /// status bar for a bottom sheet, the gesture bar for a top sheet) and the
  /// left/right edges. Like showModalBottomSheet's `useSafeArea`.
  final bool useSafeArea;
  final ShapeBorder? shape;
  final double elevation;
  final double maxWidth;

  /// Named `sheetController` because [TransitionRoute] already has a
  /// `controller` member (its animation controller).
  final DraggableSnapSheetController? sheetController;
  final ValueChanged<double>? onSizeChanged;
  final CapturedThemes? capturedThemes;

  @override
  final String? barrierLabel;

  bool _lockHeld = false;

  // Use the caller's controller, or make our own so the switches always exist.
  late final DraggableSnapSheetController _ctrl =
      sheetController ?? DraggableSnapSheetController();

  double _resolvedMin = 0.0;

  late final ValueNotifier<bool> _atMin = ValueNotifier<bool>(
    positions.startsAtMin,
  );

  bool _isAtMin(double size) {
    final double? pin = _ctrl.isAttached ? _ctrl.pinnedFraction : null;
    if (pin != null) {
      return (size - pin).abs() < 0.01;
    }
    return size <= _resolvedMin + 0.01;
  }

  @override
  void install() {
    super.install();
    // Parameters give the STARTING value only.
    if (unlockAtMin) _ctrl.unlockAtMin.value = true;
    if (scrimlessAtMin) _ctrl.scrimlessAtMin.value = true;
    _ctrl.unlockAtMin.addListener(_onUnlockSwitched);

    final bool startUnlocked = _ctrl.unlockAtMin.value && positions.startsAtMin;
    if (!startUnlocked) {
      _lockHeld = true;
      scheduleMicrotask(() => overlayLocks.value++);
    }
  }

  void _setLock(bool wantLock) {
    if (wantLock == _lockHeld) {
      return;
    }
    _lockHeld = wantLock;
    scheduleMicrotask(() => overlayLocks.value += wantLock ? 1 : -1);
  }

  /// Lock is released only if the switch is on AND the sheet is at min.
  void _applyLock(bool atMin) => _setLock(!(_ctrl.unlockAtMin.value && atMin));

  // The switch was flipped while the sheet is sitting still.
  void _onUnlockSwitched() {
    final bool atMin = _ctrl.isAttached
        ? _isAtMin(_ctrl.size)
        : positions.startsAtMin;
    _applyLock(atMin);
  }

  void _handleSizeChanged(double size) {
    final bool atMin = _isAtMin(size);
    _atMin.value = atMin;
    _applyLock(atMin);
    onSizeChanged?.call(size);
  }

  @override
  void dispose() {
    _ctrl.unlockAtMin.removeListener(_onUnlockSwitched);
    if (_lockHeld) {
      _lockHeld = false;
      scheduleMicrotask(() => overlayLocks.value--);
    }
    super.dispose();
    _atMin.dispose();
  }

  @override
  Duration get transitionDuration => _kRouteEnterDuration;

  @override
  Duration get reverseTransitionDuration => _kRouteExitDuration;

  @override
  bool get barrierDismissible => backdrop == SnapSheetBackdrop.dismissible;

  @override
  Color? get barrierColor => backdrop == SnapSheetBackdrop.none
      ? Colors.transparent
      : (scrimColor ?? Colors.black54);

  @override
  Widget buildModalBarrier() {
    if (backdrop == SnapSheetBackdrop.none) {
      return const SizedBox.shrink();
    }
    final Widget barrier = super.buildModalBarrier();
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_atMin, _ctrl.scrimlessAtMin]),
      child: barrier,
      builder: (BuildContext context, Widget? child) {
        final bool hide = _ctrl.scrimlessAtMin.value && _atMin.value;
        return IgnorePointer(
          ignoring: hide, // touches fall through to the page
          child: AnimatedOpacity(
            opacity: hide ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: child,
          ),
        );
      },
    );
  }

  void _handleClosing() {
    if (isCurrent) {
      navigator?.pop();
    }
  }

  /// Closes this sheet from outside (used by the keyed toggle). Pops if it is
  /// the top route, otherwise removes it from wherever it sits in the stack.
  void closeRoute() {
    if (isCurrent) {
      navigator?.pop();
    } else {
      navigator?.removeRoute(this);
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    Widget sheet = Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: DraggableSnapSheet(
        builder: builder,
        positions: positions,
        snapOn: snapOn,
        setTop: setTop,
        backgroundColor: backgroundColor,
        dragHandleColor: dragHandleColor,
        dragHandleSize: dragHandleSize,
        showDragHandle: showDragHandle,
        resizeContent: resizeContent,
        shape: shape,
        elevation: elevation,
        maxWidth: maxWidth,
        controller: _ctrl,
        onSizeChanged: _handleSizeChanged,
        tolerantContent: tolerantContent,
        onClosing: _handleClosing,
        animatePresence: false,
        bounceOnOpen: true,
      ),
    );
    // Shrink the available area by the keyboard height, so the sheet never
    // ends up hidden behind it.
    Widget page = Builder(
      builder: (BuildContext context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            _resolvedMin = positions
                .resolve(
                  constraints.maxHeight,
                  handleHeight: showDragHandle ? _kHandleAreaHeight : 0.0,
                )
                .min;
            return sheet;
          },
        ),
      ),
    );
    if (useSafeArea) {
      page = SafeArea(top: !setTop, bottom: setTop, child: page);
    }
    return capturedThemes?.wrap(page) ?? page;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<Offset> slideOut = animation.drive(
      Tween<Offset>(
        begin: Offset(0, setTop ? -1 : 1),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (BuildContext context, Widget? child) {
        // Opening: the sheet springs in by itself, so no slide here.
        // Closing: slide out along the sheet's own edge.
        final bool opening =
            animation.status == AnimationStatus.forward ||
            animation.status == AnimationStatus.completed;
        return FractionalTranslation(
          translation: opening ? Offset.zero : slideOut.value,
          child: child,
        );
      },
    );
  }
}

// Modal sheets that are currently open, by the `sheetKey` they were opened
// with.
final Map<Object, ModalSnapSheetRoute<dynamic>> _openSnapSheets =
    <Object, ModalSnapSheetRoute<dynamic>>{};

/// Whether a modal sheet opened with [sheetKey] is currently open.
bool isModalSnapSheetOpen(Object sheetKey) =>
    _openSnapSheets[sheetKey]?.isActive ?? false;

/// Closes the modal sheet opened with [sheetKey], if there is one.
void closeModalSnapSheet(Object sheetKey) =>
    _openSnapSheets[sheetKey]?.closeRoute();

/// The controller of the open sheet with this key, or null if it isn't open
/// (or hasn't attached yet).
DraggableSnapSheetController? _controllerFor(Object sheetKey) {
  final route = _openSnapSheets[sheetKey];
  if (route == null || !route.isActive) return null;
  final c = route._ctrl;
  return c.isAttached ? c : null;
}

/// Where the keyed sheet is resting: SnapPoint.min / mid / max, or null if
/// it is between positions or not open.
SnapPoint? snapSheetPosition(Object sheetKey) =>
    _controllerFor(sheetKey)?.currentPoint;

/// Moves the keyed sheet. Does nothing if it isn't open.
Future<void> snapSheetTo(Object sheetKey, SnapPoint point) =>
    _controllerFor(sheetKey)?.snapTo(point) ?? Future<void>.value();

/// Watches [listenable] and moves [ctrl] in and out of compact mode.
/// Returns a function that stops watching.
VoidCallback _wireCompact({
  required DraggableSnapSheetController ctrl,
  required Listenable listenable,
  required bool Function() compactWhen,
  required bool Function() unlockWhen,
  required SheetSize? size,
  required SheetSize? Function()? sizeOf, // NEW: dynamic pin size
  required bool lockDrag,
  required bool scrimless,
  required bool hideHandle,
}) {
  bool wasCompact = false;
  bool wasUnlock = false;
  bool disposed = false;
  SheetSize? lastSize; // the pin size we last sent to the sheet

  SheetSize? currentSize() => sizeOf != null ? sizeOf() : size;

  void sync() {
    if (disposed || !ctrl.isAttached) return;
    final bool compact = compactWhen();
    final bool unlock = unlockWhen();

    if (compact && !wasCompact) {
      lastSize = currentSize();
      ctrl.enterCompact(
        size: lastSize,
        lockDrag: lockDrag,
        unlock: unlock,
        scrimless: scrimless,
        hideHandle: hideHandle,
      );
    } else if (!compact && wasCompact) {
      ctrl.exitCompact();
    } else if (compact) {
      // still compact: re-check the switches AND the size
      if (unlock != wasUnlock) ctrl.unlockAtMin.value = unlock;
      final SheetSize? next = currentSize();
      if (next != lastSize) {
        lastSize = next;
        ctrl.resizeCompact(next);
      }
    }
    wasCompact = compact;
    wasUnlock = unlock;
  }

  listenable.addListener(sync);

  // The sheet attaches its controller a few frames after push().
  void applyWhenAttached(int triesLeft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (disposed) return;
      if (ctrl.isAttached) {
        sync();
      } else if (triesLeft > 0) {
        applyWhenAttached(triesLeft - 1);
      }
    });
  }

  applyWhenAttached(10);

  return () {
    disposed = true;
    listenable.removeListener(sync);
  };
}

/// Shows a [DraggableSnapSheet] as a modal route.
///
/// Returns a Future that completes with the value passed to [Navigator.pop].
///
/// [sheetKey] guards against duplicates: only one sheet per key can be open.
/// Calling this again with the same key while that sheet is open CLOSES it
/// instead (a toggle), so a button can't stack up copies. Leave it null for
/// no guard.
Future<T?> showModalSnapSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  SnapPositions positions = const SnapPositions(),
  bool snapOn = true,
  bool setTop = false,
  SnapSheetBackdrop backdrop = SnapSheetBackdrop.dismissible,
  bool scrimlessAtMin = false,
  bool unlockAtMin = false,
  Color? scrimColor,
  Color? backgroundColor,
  Color? dragHandleColor,
  Size dragHandleSize = const Size(32, 4),
  bool showDragHandle = true,
  bool resizeContent = false,
  bool useSafeArea = false,
  ShapeBorder? shape,
  double elevation = 1.0,
  double maxWidth = 640,
  DraggableSnapSheetController? controller,
  ValueChanged<double>? onSizeChanged,
  bool tolerantContent = kTolerantContentDefault,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
  Object? sheetKey,
  Listenable? compactListenable, // what to watch (e.g. a controller)
  bool Function()? compactWhen, // true = go compact
  bool Function()? unlockWhen, // true = release the overlay lock
  SheetSize? compactSize, // the pin position (null = min)
  SheetSize? Function()? compactSizeOf,
  bool compactLockDrag = false,
  bool compactScrimless = true,
  bool compactHideHandle = false,
}) {
  assert(debugCheckHasMaterialLocalizations(context));
  final NavigatorState navigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  );
  if (sheetKey != null) {
    final ModalSnapSheetRoute<dynamic>? existing = _openSnapSheets[sheetKey];
    if (existing != null && existing.isActive) {
      existing.closeRoute();
      return existing.popped.then<T?>((Object? _) => null);
    }
  }
  final bool useCompact = compactListenable != null && compactWhen != null;
  final DraggableSnapSheetController? sheetCtrl = useCompact
      ? (controller ?? DraggableSnapSheetController())
      : controller;
  final ModalSnapSheetRoute<T> route = ModalSnapSheetRoute<T>(
    builder: builder,
    positions: positions,
    snapOn: snapOn,
    setTop: setTop,
    backdrop: backdrop,
    scrimlessAtMin: scrimlessAtMin,
    unlockAtMin: unlockAtMin,
    scrimColor: scrimColor,
    backgroundColor: backgroundColor,
    dragHandleColor: dragHandleColor,
    dragHandleSize: dragHandleSize,
    showDragHandle: showDragHandle,
    resizeContent: resizeContent,
    useSafeArea: useSafeArea,
    shape: shape,
    elevation: elevation,
    maxWidth: maxWidth,
    sheetController: sheetCtrl,
    onSizeChanged: onSizeChanged,
    tolerantContent: tolerantContent,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: MaterialLocalizations.of(context).scrimLabel,
    settings: routeSettings,
  );
  final Future<T?> result = navigator.push(route);
  if (useCompact) {
    final VoidCallback stop = _wireCompact(
      ctrl: sheetCtrl!,
      listenable: compactListenable,
      compactWhen: compactWhen,
      unlockWhen: unlockWhen ?? () => true,
      size: compactSize,
      sizeOf: compactSizeOf,
      lockDrag: compactLockDrag,
      scrimless: compactScrimless,
      hideHandle: compactHideHandle,
    );
    result.whenComplete(stop);
  }
  if (sheetKey != null) {
    _openSnapSheets[sheetKey] = route;
    result.whenComplete(() {
      if (identical(_openSnapSheets[sheetKey], route)) {
        _openSnapSheets.remove(sheetKey);
      }
    });
  }

  return result;
}
