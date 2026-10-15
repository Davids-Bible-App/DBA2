// lib/ui/ikon_btn.dart
import 'dart:math' as math;

import 'package:dba2/core.dart';

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

  @override
  Widget build(BuildContext context) {
    // 1. Apply transformations exclusively to the icon
    Widget processedIcon = icon;
    if (flipX || flipY || rotate != null) {
      final double angle = rotate != null
          ? ((rotate! % 4) * (math.pi / 2))
          : 0.0;
      processedIcon = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0)
          ..rotateZ(angle),
        child: icon,
      );
    }

    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    // 2. Build the button container using the clean `size` parameter
    Widget buttonWidget = GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: buttonColor ?? (dark ? Colors.grey[800] : Colors.grey[200]),
          // color: buttonColor ?? context.colorScheme.secondary,
          boxShadow: [
            // darker shadow on bottom right
            BoxShadow(
              color: dark ? Colors.black54 : Colors.grey.shade500,
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
            // lighter shadow on top left
            BoxShadow(
              color: dark ? Colors.grey.shade700 : Colors.white,
              blurRadius: 1,
              offset: Offset(-1, -1),
            ),
          ],
          // boxShadow: [
          //   BoxShadow(
          //     color: Colors.black.withValues(alpha: dark ? 0.5 : 0.15),
          //     blurRadius: 6,
          //     offset: const Offset(2, 2),
          //   ),
          // ],
        ),
        child: IconTheme(
          data: IconThemeData(
            color: iconColor ?? (dark ? Colors.grey[400] : Colors.grey[700]),
            // color: iconColor ?? context.colorScheme.inversePrimary,
            size: iconSize,
          ),
          child: processedIcon,
        ),
      ),
    );

    // 3. Wrap with Tooltip if provided
    if (tooltip != null) {
      buttonWidget = Tooltip(message: tooltip!, child: buttonWidget);
    }

    return buttonWidget;
  }
}
