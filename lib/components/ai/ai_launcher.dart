import 'package:dba2/core.dart'; // rootNavigatorKey (adjust if it lives elsewhere)
import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:dba2/ui/widgets/toast.dart';
import 'package:flutter/material.dart';

import 'ai_prefs.dart';
import 'ai_services.dart';
import 'ui/bible_chat_page.dart';

/// Owns the AI engine. Nothing is created until the first [open] call,
/// so the AI add-on costs nothing at app startup.
class AiLauncher {
  AiLauncher(this._prefs) {
    _prefs.addListener(_applyPrefs);
  }
  final AiPrefs _prefs;

  Future<AiServices?>? _future;
  AiServices? _services;
  bool _opening = false;

  /// Pushes the user's switches into the engine.
  void _applyPrefs() {
    final ai = _services;
    if (ai == null) return;
    if (!_prefs.enabled) {
      ai.engine.unload(); // switched off: free the RAM right away
      return;
    }
    ai.engine.idleTimeout = _prefs.idleUnload
        ? Duration(minutes: _prefs.idleMinutes)
        : null;
  }

  Future<void> open() async {
    if (_opening) return; // ignore double taps
    if (!_prefs.enabled) {
      showToast('Bible AI is turned off in Settings');
      return;
    }
    _opening = true;
    try {
      final ai = await (_future ??= AiServices.create());
      if (ai == null) {
        _future = null; // allow a retry later (e.g. after installing)
        showToast("Bible AI isn't included in this build");
        return;
      }
      _services = ai;
      _applyPrefs();
      // Root navigator, so this works even when called from the sidebars,
      // which have their own nested Navigators.
      await rootNavigatorKey.currentState?.push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, _, _) => OverlayLock(
            active: true, // sidebar gestures off while the chat is open
            child: BibleChatPage(ai: ai),
          ),
          transitionsBuilder: (_, animation, _, child) {
            final t = animation.drive(CurveTween(curve: Curves.easeOutCubic));
            return FadeTransition(
              opacity: t,
              child: SlideTransition(
                position: t.drive(
                  Tween(begin: const Offset(0, 0.06), end: Offset.zero),
                ),
                child: child,
              ),
            );
          },
        ),
      );
    } catch (_) {
      _future = null;
      showToast("Couldn't start Bible AI");
    } finally {
      _opening = false;
    }
  }

  /// Stops the llama-server child process. Does nothing if never opened.
  Future<void> dispose() async {
    _prefs.removeListener(_applyPrefs);
    final f = _future;
    if (f == null) return;
    try {
      await (await f)?.dispose();
    } catch (_) {}
  }
}
