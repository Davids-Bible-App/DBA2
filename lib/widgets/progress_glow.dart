import 'dart:math' as math;

import 'package:flutter/material.dart';

class GlowRingPainter extends CustomPainter {
  const GlowRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    this.strokeWidth = 4,
    this.glowSigma = 4,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final double glowSigma;

  @override
  void paint(Canvas canvas, Size size) {
    final arcRect = (Offset.zero & size).deflate(strokeWidth / 2);
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * progress;

    // Track
    canvas.drawArc(
      arcRect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    if (progress <= 0) return;

    // Glow
    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.8)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowSigma),
    );

    // Crisp arc
    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(GlowRingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth ||
      old.glowSigma != glowSigma;
}
