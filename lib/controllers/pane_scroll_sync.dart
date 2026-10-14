import 'package:flutter/widgets.dart';

/// Locked: every movement of the primary is applied to each follower as a
/// delta, from wherever that follower currently sits. Followers never drive
/// anything, so there is no feedback loop and manual nudges are kept.
/// Unlocked: followers are fully independent.
class PaneScrollSync {
  PaneScrollSync(this.primary) {
    primary.addListener(_onPrimary);
  }

  final ScrollController primary;
  final List<ScrollController> followers = [];
  bool locked = true;

  /// Scale deltas by the ratio of scroll lengths, so both panes reach the end
  /// of the chapter together. Set false for raw pixel following.
  bool scaleByLength = true;

  double _last = 0;

  /// Call when the chapter changes (every pane starts again at the top).
  void reset() => _last = 0;

  void _onPrimary() {
    // During a chapter change two positions can briefly exist: skip that.
    if (primary.positions.length != 1) return;
    final pos = primary.position;
    final now = pos.pixels;
    final delta = now - _last;
    _last = now; // always tracked, so re-locking never causes a jump
    if (!locked || delta == 0) return;

    final pMax = pos.maxScrollExtent;
    for (final f in followers) {
      if (f.positions.length != 1) continue; // e.g. "book not available"
      final fp = f.position;
      final fMax = fp.maxScrollExtent;
      final scale = (scaleByLength && pMax > 0) ? fMax / pMax : 1.0;
      f.jumpTo((fp.pixels + delta * scale).clamp(0.0, fMax));
    }
  }

  void dispose() => primary.removeListener(_onPrimary);
}
