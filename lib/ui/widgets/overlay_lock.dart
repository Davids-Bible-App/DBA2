import 'dart:async';

import 'package:flutter/material.dart';

import '../extras/overshoot.dart';

/// Which sidebar(s) an overlay locks. Defaults to [both] everywhere,
/// so existing code behaves exactly as before.
enum LockScope { both, leftOnly, rightOnly }

/// >0 while ANY modal sheet or dialog is open (all scopes).
/// Page-level gestures elsewhere keep checking this, unchanged.
final ValueNotifier<int> overlayLocks = ValueNotifier<int>(0);

// How many of those locks only affect one side.
final ValueNotifier<int> _leftOnlyLocks = ValueNotifier<int>(0);
final ValueNotifier<int> _rightOnlyLocks = ValueNotifier<int>(0);

/// Fires whenever any lock count changes. Use it to rebuild lock-aware UI.
final Listenable overlayLockChanges = Listenable.merge([
  overlayLocks,
  _leftOnlyLocks,
  _rightOnlyLocks,
]);

/// Is this sidebar currently locked?
bool isSidebarLocked({required bool left}) {
  final bothLocks =
      overlayLocks.value - _leftOnlyLocks.value - _rightOnlyLocks.value;
  final sideLocks = left ? _leftOnlyLocks.value : _rightOnlyLocks.value;
  return bothLocks > 0 || sideLocks > 0;
}

void lockOverlay([LockScope scope = LockScope.both]) {
  // Side counter first, total second, so listeners never see a
  // half-updated state where the wrong side looks locked.
  switch (scope) {
    case LockScope.leftOnly:
      _leftOnlyLocks.value++;
    case LockScope.rightOnly:
      _rightOnlyLocks.value++;
    case LockScope.both:
      break;
  }
  overlayLocks.value++;
}

void unlockOverlay([LockScope scope = LockScope.both]) {
  // Reverse order of lockOverlay.
  overlayLocks.value--;
  switch (scope) {
    case LockScope.leftOnly:
      _leftOnlyLocks.value--;
    case LockScope.rightOnly:
      _rightOnlyLocks.value--;
    case LockScope.both:
      break;
  }
}

/// Holds an overlay lock while [active] is true and this widget is mounted.
class OverlayLock extends StatefulWidget {
  const OverlayLock({
    super.key,
    this.active = true,
    this.scope = LockScope.both,
    required this.child,
  });
  final bool active;
  final LockScope scope;
  final Widget child;

  @override
  State<OverlayLock> createState() => _OverlayLockState();
}

class _OverlayLockState extends State<OverlayLock> {
  LockScope? _heldScope; // null = not holding a lock

  void _sync() => scheduleMicrotask(() {
    // After dispose, `mounted` is false, so this releases the lock.
    final wanted = (mounted && widget.active) ? widget.scope : null;
    if (wanted == _heldScope) return;
    if (_heldScope != null) unlockOverlay(_heldScope!);
    _heldScope = wanted;
    if (wanted != null) lockOverlay(wanted);
  });

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(OverlayLock old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    super.dispose();
    _sync(); // releases the lock via the microtask
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ==========================================
// BOTTOM SHEET HELPERS
// ==========================================

Future<T?> showLockedBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  double overshootExtent = 48,
  LockScope scope = LockScope.both,
}) async {
  lockOverlay(scope);
  try {
    return await showModalBottomSheet<T>(
      context: context,
      backgroundColor: backgroundColor,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Overshoot(
        edge: OvershootEdge.bottom,
        extent: overshootExtent,
        color: backgroundColor,
        child: builder(sheetContext),
      ),
    );
  } finally {
    unlockOverlay(scope);
  }
}

Future<T?> showDraggableSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController scroll)
  builder,
  double initial = 0.6,
  double min = 0.35,
  double max = 0.95,
  Color? backgroundColor,
  LockScope scope = LockScope.both,
}) {
  return showLockedBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    scope: scope,
    overshootExtent: MediaQuery.sizeOf(context).height * 0.12,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: initial,
      minChildSize: min,
      maxChildSize: max,
      builder: builder,
    ),
  );
}

// ==========================================
// DIALOG HELPERS
// ==========================================

Future<T?> showLockedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  LockScope scope = LockScope.both,
}) async {
  lockOverlay(scope);
  try {
    return await showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  } finally {
    unlockOverlay(scope);
  }
}
