// lib/widgets/paper_overlay.dart
import 'package:dba2/core.dart';

/// Full-size translucent texture laid over the main content, like your
/// paper / leather effect. Use your REAL texture image for a fair test:
/// add it as assets/paper.webp and list it under `assets:` in pubspec.yaml.
class PaperOverlay extends StatelessWidget {
  const PaperOverlay({super.key, this.opacity = 0.35});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? Color(0xFF000000) : Color(0xFFffffff),
          ),
        ),
        Image.asset(
          isDark ? 'assets/images/dark.webp' : 'assets/images/light.webp',
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
          repeat: ImageRepeat.repeat,
        ),
      ],
    );
  }
}

class _ScreenAnchoredPaper extends StatefulWidget {
  const _ScreenAnchoredPaper();

  @override
  State<_ScreenAnchoredPaper> createState() => _ScreenAnchoredPaperState();
}

class _ScreenAnchoredPaperState extends State<_ScreenAnchoredPaper> {
  final _key = GlobalKey();
  Offset _origin = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && mounted) {
        setState(() => _origin = box.localToGlobal(Offset.zero));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ClipRect(
      child: SizedBox.expand(
        key: _key,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: Transform.translate(
            offset: -_origin,
            child: const PaperOverlay(opacity: 1),
          ),
        ),
      ),
    );
  }
}
