import 'package:flutter/material.dart';

// ─── Settings ────────────────────────────────────────────────────────────
/// How far the hidden extension reaches past the edge (logical px).
/// 48 = 3rem at the usual 16px base.
const double kOvershootExtent = 48;

/// Which edge of the child gets the extension.
const OvershootEdge kOvershootEdge = OvershootEdge.bottom;
// ─────────────────────────────────────────────────────────────────────────

enum OvershootEdge { top, bottom, left, right }

/// Paints a hidden slab of [color] just outside one edge of [child], so
/// overshoot/elastic animations reveal background instead of a gap.
/// It adds no layout size; [child] is sized exactly as before.
class Overshoot extends StatelessWidget {
  const Overshoot({
    super.key,
    required this.child,
    this.color,
    this.extent = kOvershootExtent,
    this.edge = kOvershootEdge,
  });

  final Widget child;

  /// Defaults to the theme's bottom sheet color.
  final Color? color;
  final double extent;
  final OvershootEdge edge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill =
        color ??
        theme.bottomSheetTheme.backgroundColor ??
        theme.colorScheme.surfaceContainerLow;

    final slab = switch (edge) {
      OvershootEdge.bottom => Positioned(
        left: 0,
        right: 0,
        bottom: -extent,
        height: extent,
        child: ColoredBox(color: fill),
      ),
      OvershootEdge.top => Positioned(
        left: 0,
        right: 0,
        top: -extent,
        height: extent,
        child: ColoredBox(color: fill),
      ),
      OvershootEdge.left => Positioned(
        top: 0,
        bottom: 0,
        left: -extent,
        width: extent,
        child: ColoredBox(color: fill),
      ),
      OvershootEdge.right => Positioned(
        top: 0,
        bottom: 0,
        right: -extent,
        width: extent,
        child: ColoredBox(color: fill),
      ),
    };

    return Stack(
      clipBehavior: Clip.none,
      children: [slab, child],
    );
  }
}
