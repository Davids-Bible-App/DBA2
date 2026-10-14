// lib/widgets/app_bar_background.dart
import 'package:dba2/core.dart';
import 'package:dba2/widgets/stitch_painter.dart';

class AppBarBackground extends StatelessWidget {
  final bool stitches;
  final bool top;
  final double inset;
  final bool textured;

  const AppBarBackground({
    super.key,
    this.stitches = true,
    this.top = true,
    this.inset = 40,
    this.textured = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: isDark
                  ? textured
                        ? const [Color(0xFF000000), Color(0xFF111111)]
                        : const [Color(0xFF232323), Color(0xFF444444)]
                  : textured
                  ? const [Color(0xFFffffff), Color(0xFFeeeeee)]
                  : const [Color(0xFFdddddd), Color(0xFFffffff)],
            ),
          ),
        ),
        if (textured)
          Image.asset(
            isDark ? 'assets/images/dark.webp' : 'assets/images/light.webp',
            fit: BoxFit.none,
            repeat: ImageRepeat.repeat,
          ),
        if (stitches)
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: StitchPainter(
                    color: context.colorScheme.tertiaryContainer,
                    fromBottom: !top,
                    inset: inset.toDouble(),
                    isDarkMode: isDark,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
