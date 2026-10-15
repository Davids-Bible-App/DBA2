// lib/state/overlay_lock.dart
import 'package:flutter/material.dart';

import '../widgets/overshoot.dart';

import 'dart:async';

/// Holds an overlay lock while [active] is true and this widget is mounted.
class OverlayLock extends StatefulWidget {
  const OverlayLock({super.key, this.active = true, required this.child});
  final bool active;
  final Widget child;

  @override
  State<OverlayLock> createState() => _OverlayLockState();
}

class _OverlayLockState extends State<OverlayLock> {
  bool _held = false;

  // Deferred: changing the notifier mid-build makes listeners call setState
  // during build, which throws.
  void _sync() => scheduleMicrotask(() {
    if (widget.active && !_held) {
      _held = true;
      overlayLocks.value++;
    } else if (!widget.active && _held) {
      _held = false;
      overlayLocks.value--;
    }
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
    if (_held) {
      _held = false;
      scheduleMicrotask(() => overlayLocks.value--);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// >0 while a modal sheet is open. Page-level gestures check this.
final ValueNotifier<int> overlayLocks = ValueNotifier<int>(0);

Future<T?> showLockedBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  double overshootExtent = 48,
}) async {
  overlayLocks.value++;
  try {
    return await showModalBottomSheet<T>(
      context: context,
      backgroundColor: backgroundColor,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 450),
        reverseDuration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
      ),
      builder: (sheetContext) => Overshoot(
        edge: OvershootEdge.bottom,
        extent: overshootExtent,
        color: backgroundColor,
        child: builder(sheetContext),
      ),
    );
  } finally {
    overlayLocks.value--;
  }
}
