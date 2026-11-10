import 'dart:math' as math;

import 'package:dba2/core.dart';

/// Neumorphic circular icon button.
///
/// Optical centering: the neumorphic shadows are asymmetric, so the *visible*
/// silhouette is not the same as the geometric circle.
///  - Dark mode : the light highlight (top-left) is the visible edge, so the
///                shape looks shifted up-left  -> nudge the icon up-left.
///  - Light mode: the dark shadow (bottom-right) is the visible edge, so the
///                shape looks shifted down-right -> nudge the icon down-right.
/// Tweak [_NeuLook.iconNudge] below if you want it more or less.
class IkonBtn extends StatelessWidget {
  const IkonBtn({
    super.key,
    this.onPressed,
    required this.icon,
    this.tooltip,
    // ---- Icon Transformations ----
    this.flipX = false,
    this.flipY = false,
    this.rotate, // 1 = 90°, 2 = 180°, 3 = 270°, 4 = 360°
    // ---- Sizing & Styling ----
    this.size = 25.0, // Directly controls width and height
    this.iconSize = 16.0,
    this.iconColor,
    this.buttonColor,
    this.iconOffset = Offset.zero, // per-button extra nudge (e.g. a number)
  }) : assert(
         rotate == null || (rotate >= 1 && rotate <= 4),
         'rotate must be a value between 1 and 4.',
       );

  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;

  // Transformation properties
  final bool flipX;
  final bool flipY;
  final int? rotate;

  // Styling properties
  final double size;
  final double iconSize;
  final Color? iconColor;
  final Color? buttonColor;

  /// Extra optical nudge for this one button, added on top of the
  /// light/dark default. Positive x = right, positive y = down.
  final Offset iconOffset;

  // ── Look per mode: tweak these, nothing else needs touching ──────────────
  static final _dark = _NeuLook(
    fill: Colors.grey.shade800,
    icon: Colors.grey.shade400,
    shadow: Colors.black54, // dark edge, bottom-right (barely visible on dark)
    highlight: Colors.grey.shade700, // light edge, top-left (the visible one)
    shadowOffset: const Offset(1, 1),
    shadowBlur: 2,
    highlightBlur: 1,
    iconNudge: const Offset(-1.0, -0.5),
  );

  static final _light = _NeuLook(
    fill: Colors.grey.shade200,
    icon: Colors.grey.shade700,
    shadow: Colors.grey.shade500, // dark edge, bottom-right (the visible one)
    highlight: Colors.white, // light edge, top-left (invisible on light)
    shadowOffset: const Offset(1, 1),
    shadowBlur: 2,
    highlightBlur: 1,
    iconNudge: const Offset(-1.0, 0),
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final look = dark ? _dark : _light;

    // 1. Apply transformations exclusively to the icon
    Widget processedIcon = icon;
    if (flipX || flipY || rotate != null) {
      final double angle = rotate != null
          ? ((rotate! % 4) * (math.pi / 2))
          : 0.0;
      processedIcon = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scaleByDouble(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0, 1.0, 1.0)
          ..rotateZ(angle),
        child: icon,
      );
    }

    // 2. Optical centering (paint-only, doesn't affect layout)
    processedIcon = Transform.translate(
      offset: look.iconNudge + iconOffset,
      child: processedIcon,
    );

    // 3. Build the button container
    Widget buttonWidget = GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: buttonColor ?? look.fill,
          boxShadow: [
            // bottom-right edge
            BoxShadow(
              color: look.shadow,
              blurRadius: look.shadowBlur,
              offset: look.shadowOffset,
            ),
            // top-left edge (mirror of the above)
            BoxShadow(
              color: look.highlight,
              blurRadius: look.highlightBlur,
              offset: -look.shadowOffset,
            ),
          ],
        ),
        child: IconTheme(
          data: IconThemeData(color: iconColor ?? look.icon, size: iconSize),
          child: processedIcon,
        ),
      ),
    );

    // 4. Wrap with Tooltip if provided
    if (tooltip != null) {
      buttonWidget = Tooltip(message: tooltip!, child: buttonWidget);
    }

    return buttonWidget;
  }
}

@immutable
class _NeuLook {
  const _NeuLook({
    required this.fill,
    required this.icon,
    required this.shadow,
    required this.highlight,
    required this.shadowOffset,
    required this.shadowBlur,
    required this.highlightBlur,
    required this.iconNudge,
  });

  final Color fill;
  final Color icon;
  final Color shadow;
  final Color highlight;
  final Offset shadowOffset;
  final double shadowBlur;
  final double highlightBlur;
  final Offset iconNudge;
}
