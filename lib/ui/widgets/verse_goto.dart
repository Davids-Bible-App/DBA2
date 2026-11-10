// Self-contained "go to verse" helper: locate (lazy list) + smooth scroll +
// fade-in/fade-out glow. Used by the reader, but usable from anywhere:
//
//   controller.verseGoto.goToVerse(controller.readerScroll, 16);
//   controller.verseGoto.flash(16);                    // glow only
//   controller.verseGoto.flash(16, color: Colors.amber);
//
// Wiring (once): ChapterView wraps every verse with verseGoto.wrap(...).
import 'package:flutter/material.dart';

const double kGlowBleed = 14; // glow extends this far past the verse text
const Duration kGlowDuration = Duration(milliseconds: 2400);

class _FlashEvent {
  const _FlashEvent(this.verse, this.color);
  final int verse;
  final Color? color;
}

class VerseGoto {
  final Map<int, GlobalKey> _keys = {};
  final Map<int, int> _blockIndex = {};
  int _blockCount = 0;
  int _token = 0;
  final ValueNotifier<_FlashEvent?> _flash = ValueNotifier(null);

  // ---- ChapterView hooks --------------------------------------------------

  /// Wraps one verse: gives it a key, records its list index, adds the glow.
  Widget wrap(int verse, int blockIndex, Widget child) {
    _blockIndex[verse] = blockIndex;
    final key = _keys.putIfAbsent(
      verse,
      () => GlobalKey(debugLabel: 'v$verse'),
    );
    return VerseGlow(key: key, goto: this, verse: verse, child: child);
  }

  void setBlockCount(int n) => _blockCount = n;

  /// Call when a chapter is (re)loaded. Also cancels a running scroll.
  void reset() {
    _token++;
    _keys.clear();
    _blockIndex.clear();
    _blockCount = 0;
  }

  void dispose() => _flash.dispose();

  // ---- Public API ---------------------------------------------------------

  /// Glow one verse (it must be built/visible to be seen).
  void flash(int verse, {Color? color}) =>
      _flash.value = _FlashEvent(verse, color);

  /// Scrolls to [verse] (smoothly if [smooth]) and then glows it.
  Future<void> goToVerse(
    ScrollController controller,
    int verse, {
    bool smooth = true,
    bool glow = true,
    Color? glowColor,
    double alignment = 0.15, // leaves room under the pinned title
  }) async {
    final token = _token;
    bool stale() => token != _token;

    final origin = controller.hasClients ? controller.offset : 0.0;
    if (!await _locate(controller, verse, alignment, token)) return;
    if (stale()) return;

    if (smooth && controller.hasClients) {
      final target = controller.offset;
      final dist = (target - origin).abs();
      if (dist > 24) {
        // Rewind and glide (no frame renders between these two calls).
        controller.jumpTo(origin);
        final ms = (dist / 4).clamp(250.0, 900.0).round();
        try {
          await controller.animateTo(
            target,
            duration: Duration(milliseconds: ms),
            curve: Curves.easeInOutCubic,
          );
        } catch (_) {}
        if (stale()) return;
        // Extent estimates shift while gliding; settle exactly on the verse.
        final ctx = _keys[verse]?.currentContext;
        if (ctx != null && ctx.mounted) {
          await Scrollable.ensureVisible(
            ctx,
            alignment: alignment,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      }
    }
    if (stale()) return;
    if (glow) flash(verse, color: glowColor);
  }

  // ---- Locating a verse in the lazy SliverList ---------------------------

  /// Leaves [verse] built and positioned (instantly). False = gave up.
  Future<bool> _locate(
    ScrollController controller,
    int verse,
    double alignment,
    int token,
  ) async {
    for (var i = 0; i < 30; i++) {
      if (token != _token) return false;

      final ctx = _keys[verse]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: alignment);
        return true;
      }

      final idx = _blockIndex[verse];
      if (idx == null || !controller.hasClients) {
        await WidgetsBinding.instance.endOfFrame; // not built yet
        continue;
      }

      final pos = controller.position;
      double clamp(double v) =>
          v.clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();

      int? lo, hi; // range of verses currently built
      _keys.forEach((vs, key) {
        if (key.currentContext == null) return;
        final bi = _blockIndex[vs];
        if (bi == null) return;
        lo = lo == null ? bi : (bi < lo! ? bi : lo);
        hi = hi == null ? bi : (bi > hi! ? bi : hi);
      });

      if (i == 0 || lo == null || hi == null) {
        final frac = _blockCount <= 1 ? 0.0 : idx / (_blockCount - 1);
        controller.jumpTo(
          clamp(
            pos.minScrollExtent +
                (pos.maxScrollExtent - pos.minScrollExtent) * frac,
          ),
        );
      } else {
        final step = pos.viewportDimension * 0.8;
        final next = hi! < idx
            ? pos.pixels + step
            : (lo! > idx ? pos.pixels - step : pos.pixels + 1);
        controller.jumpTo(clamp(next));
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// GLOW: always the same widget structure (so verse state is never lost);
// the animation controller is only created the first time a verse flashes.
// ---------------------------------------------------------------------------

class VerseGlow extends StatefulWidget {
  const VerseGlow({
    super.key,
    required this.goto,
    required this.verse,
    required this.child,
  });

  final VerseGoto goto;
  final int verse;
  final Widget child;

  @override
  State<VerseGlow> createState() => _VerseGlowState();
}

class _VerseGlowState extends State<VerseGlow>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _t;
  Color? _color;

  @override
  void initState() {
    super.initState();
    widget.goto._flash.addListener(_onFlash);
  }

  @override
  void didUpdateWidget(VerseGlow old) {
    super.didUpdateWidget(old);
    if (old.goto != widget.goto) {
      old.goto._flash.removeListener(_onFlash);
      widget.goto._flash.addListener(_onFlash);
    }
  }

  @override
  void dispose() {
    widget.goto._flash.removeListener(_onFlash);
    _c?.dispose();
    super.dispose();
  }

  void _onFlash() {
    final e = widget.goto._flash.value;
    if (e == null || e.verse != widget.verse) return;
    _color = e.color;
    final c = _c ??= AnimationController(vsync: this, duration: kGlowDuration);
    _t ??= TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 18, // fade in
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 22), // hold
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60, // fade out
      ),
    ]).animate(c);
    setState(() {});
    c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Positioned(
          left: -kGlowBleed,
          right: -kGlowBleed,
          top: -2,
          bottom: -2,
          child: IgnorePointer(
            child: t == null
                ? const SizedBox.shrink()
                : AnimatedBuilder(
                    animation: t,
                    builder: (context, _) {
                      final v = t.value;
                      if (v <= 0.001) return const SizedBox.shrink();
                      final col =
                          _color ?? Theme.of(context).colorScheme.primary;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: col.withValues(alpha: 0.16 * v),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: col.withValues(alpha: 0.55 * v),
                              blurRadius: 22 * v,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
