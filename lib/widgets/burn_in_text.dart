// lib\widgets\burn_in_text.dart
import 'package:flutter/material.dart';

class BurnInText extends StatefulWidget {
  const BurnInText(
    this.text, {
    super.key,
    this.duration = const Duration(seconds: 6),
  });

  final String text;
  final Duration duration;

  @override
  State<BurnInText> createState() => _BurnInTextState();
}

class _BurnInTextState extends State<BurnInText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward(); // animation: ... forwards (plays once, holds end state)

    // 0% -> 70%: opacity 0 -> 1 (CSS only sets opacity at 0%, so it
    // interpolates to the implicit end value of 1 over the whole animation).
    // To match exactly, fade across the full 6s:
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.linear);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Glow shadows (the 70% keyframe)
  static const _glow = <Shadow>[
    Shadow(color: Color(0xFFFFA500), offset: Offset(0, 1), blurRadius: 2),
    Shadow(color: Color(0xFFFFA500), blurRadius: 7),
    Shadow(color: Color(0xFFFFA500), blurRadius: 10),
    Shadow(color: Color(0xFFFFA500), blurRadius: 20),
    Shadow(color: Color(0xFFFF0000), blurRadius: 30),
    Shadow(color: Color(0xFFFF8D00), blurRadius: 10),
    Shadow(color: Color(0xFFFF0000), blurRadius: 50),
  ];

  // "none" start state: same length, fully transparent, so lerp is smooth
  static final _none = List<Shadow>.generate(
    _glow.length,
    (_) => const Shadow(color: Color(0x00000000), blurRadius: 0),
  );

  TextStyle _style(BuildContext context, double fontSize) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    // 100% keyframe: light-dark(...) resolved from the theme
    final endColor = dark ? const Color(0xFF111111) : const Color(0xFF555555);
    final endShadowColor = dark
        ? const Color(0xFF555555)
        : const Color(0xFFD6D6D6);

    // Pad end shadows to the same length for clean interpolation
    final endShadows = <Shadow>[
      Shadow(color: endShadowColor, offset: const Offset(0, 1), blurRadius: 0),
      ...List.generate(
        _glow.length - 1,
        (_) => const Shadow(color: Color(0x00000000), blurRadius: 0),
      ),
    ];

    final start = TextStyle(
      fontSize: fontSize,
      color: const Color(
        0xFFFFF6A9,
      ), // CSS color isn't set at 0%; start with the glow color
      shadows: _none,
    );
    final mid = TextStyle(
      fontSize: fontSize,
      color: const Color(0xFFFFF6A9),
      shadows: _glow,
    );
    final end = TextStyle(
      fontSize: fontSize,
      color: endColor,
      shadows: endShadows,
    );

    return TweenSequence<TextStyle>([
      TweenSequenceItem(
        tween: _TextStyleTween(start, mid),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: _TextStyleTween(mid, end),
        weight: 30,
      ),
    ]).evaluate(_controller);
  }

  @override
  Widget build(BuildContext context) {
    // clamp(0.8rem, 4vw, 1.2rem) with 1rem = 16px
    final vw = MediaQuery.sizeOf(context).width;
    final fontSize = (vw * 0.04).clamp(12.8, 19.2);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Opacity(
            opacity: _opacity.value,
            child: Text(
              widget.text,
              style: _style(context, fontSize),
            ),
          );
        },
      ),
    );
  }
}

class _TextStyleTween extends Tween<TextStyle> {
  _TextStyleTween(TextStyle begin, TextStyle end)
    : super(begin: begin, end: end);

  @override
  TextStyle lerp(double t) => TextStyle.lerp(begin, end, t)!;
}
