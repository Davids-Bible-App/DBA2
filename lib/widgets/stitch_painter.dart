// lib/painters/stitch_painter.dart

/*
Because your CSS tiles are 10px wide with no gap, 
the spacing between stitches comes entirely from the fade. 
The ellipse fades to transparent at 83% of its radius, 
which leaves a visible gap between neighbours. 

If you want more or less gap, 
adjust fadeStop: lower it for a wider gap, 
raise it toward 1.0 for a continuous soft line.

Core length: coreStop controls how long the bright part of each stitch is. 0.2 
matches your CSS, and raising it to around 0.4 makes each stitch look more solid.
Origin offset: your CSS centres the gradient at 75% 75% of the tile, 
so the stitch sits slightly right and low. offset: Offset(2.5, 0.75) 
reproduces that. Leave it at zero if you’d rather have them centred.
Colour: the CSS applies opacity: 0.5 to the whole layer, 
which is what opacity does here. If the Flutter version still looks flatter, 
check that --stitches resolves to the same amber as your color.
Crease: your CSS doesn’t have a separate crease line. 
The indented look comes from the dark --background-color ends of each gradient, 
so you can skip my earlier solid shadow line. 
If you still want one, 
draw a 1px black line at about 0.2 alpha just below the stitches.

If you want the layered idea per dash, draw each stitch twice: a wide, 
dim halo (about 12×4px at 0.3 of the alpha) and a short, 
bright core (about 5×1.5px). 
It’s more work than the single gradient 
and I’d only try it if the gradient version looks too soft.

*/

import 'package:dba2/core.dart';

class StitchPainter extends CustomPainter {
  final bool fromBottom;
  final double inset, opacity, dash, thickness, coreStop, fadeStop;
  final Color color;
  final Offset offset;
  final bool isDarkMode;
  final double shadowOpacity;
  final double shadowBlur;
  final double shadowDy;

  const StitchPainter({
    this.fromBottom = false,
    this.inset = 0,
    this.color = const Color(0xFFFFFD00),
    this.opacity = 0.5,
    this.dash = 10.0,
    this.thickness = 3.0,
    this.coreStop = 0.2,
    this.fadeStop = 0.83,
    this.offset = Offset.zero,
    required this.isDarkMode,
    double? shadowOpacity,
    this.shadowBlur = 1.2,
    this.shadowDy = 0.0,
  }) : shadowOpacity = shadowOpacity ?? (isDarkMode ? 0.2 : 0);

  @override
  void paint(Canvas canvas, Size size) {
    final cy = fromBottom
        ? size.height - inset - thickness / 2
        : inset + thickness / 2;

    if (shadowOpacity > 0) {
      final sy = cy + (fromBottom ? -shadowDy : shadowDy);
      canvas.drawLine(
        Offset(0, sy),
        Offset(size.width, sy),
        Paint()
          ..strokeWidth = thickness
          ..color = Colors.black.withValues(alpha: shadowOpacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur),
      );
    }

    // One shader in unit-circle space, reused for every dash.
    final paint = Paint()
      ..isAntiAlias = true
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: opacity),
          color.withValues(alpha: opacity),
          color.withValues(alpha: 0),
        ],
        stops: [0.0, coreStop, fadeStop],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));

    for (double x = 0; x < size.width; x += dash) {
      canvas
        ..save()
        ..translate(x + dash / 2 + offset.dx, cy + offset.dy)
        ..scale(
          dash / 2,
          thickness / 2,
        ) // unit circle -> dash x thickness ellipse
        ..drawCircle(Offset.zero, 1, paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(covariant StitchPainter old) =>
      old.fromBottom != fromBottom ||
      old.inset != inset ||
      old.color != color ||
      old.opacity != opacity ||
      old.dash != dash ||
      old.thickness != thickness ||
      old.coreStop != coreStop ||
      old.fadeStop != fadeStop ||
      old.offset != offset ||
      old.isDarkMode != isDarkMode ||
      old.shadowOpacity != shadowOpacity ||
      old.shadowBlur != shadowBlur ||
      old.shadowDy != shadowDy;
}
