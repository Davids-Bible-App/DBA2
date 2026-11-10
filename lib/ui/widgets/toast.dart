import 'dart:async';

import 'package:flutter/material.dart';

/// Give this to MaterialApp(navigatorKey: rootNavigatorKey).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

OverlayEntry? _entry;
Timer? _timer;

/// Topmost message: shows above sheets, dialogs and the control box.
/// No BuildContext needed, so it is safe to call after an `await`.
void showToast(
  String message, {
  bool error = false,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = rootNavigatorKey.currentState?.overlay;
  final ctx = rootNavigatorKey.currentContext;
  if (overlay == null || ctx == null) return;

  _timer?.cancel();
  _entry?.remove(); // a new toast replaces the old one

  final theme = Theme.of(ctx);
  final top = MediaQuery.paddingOf(ctx).top;
  final bg = error
      ? theme.colorScheme.errorContainer
      : theme.colorScheme.surface;
  final fg = error
      ? theme.colorScheme.onErrorContainer
      : theme.colorScheme.onSurface;

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      top: top,
      left: 16,
      right: 16,
      child: IgnorePointer(
        // taps pass through to the app underneath
        child: Align(
          alignment: Alignment.topCenter,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 200),
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * -12),
                child: child,
              ),
            ),
            child: Material(
              color: bg,
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: theme.colorScheme.onSurface,
                  width: 1.0,
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  _entry = entry;
  overlay.insert(entry);
  _timer = Timer(duration, () {
    if (_entry == entry) {
      entry.remove();
      _entry = null;
    }
  });
}
