import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Every themeable part of the streak badge, in one place
/// (the equivalent of the CSS variables at the top of StreakBadge.css).
///
/// Three ways to use it:
///  1. Do nothing: defaults are derived from your app's ColorScheme.
///  2. Register it app-wide:  ThemeData(extensions: [StreakBadgeTheme.fromTheme(base).copyWith(...)])
///  3. Override per instance: StreakBadge(theme: myTheme, ...)
@immutable
class StreakBadgeTheme extends ThemeExtension<StreakBadgeTheme> {
  const StreakBadgeTheme({
    required this.foreground,
    required this.mutedForeground,
    required this.buttonBackground,
    required this.buttonForeground,
    required this.buttonBorder,
    required this.popoverBackground,
    required this.popoverBorder,
    required this.rowBackground,
    required this.rowHighlightBackground,
    required this.rowHighlightForeground,
    required this.divider,
    required this.shadows,
    this.popoverRadius = 12,
    this.buttonRadius = 8,
    this.rowRadius = 8,
    this.popoverWidth = 260,
    this.gap = 10,
    this.anchorGap = 6,
    this.arrowSize = 8,
    this.animationDuration = const Duration(milliseconds: 160),
    this.animationCurve = Curves.easeOutCubic,
  });

  /// Sensible defaults taken from the app's current Material theme.
  factory StreakBadgeTheme.fromTheme(ThemeData theme) {
    final cs = theme.colorScheme;
    return StreakBadgeTheme(
      foreground: cs.onSurface,
      mutedForeground: cs.onSurfaceVariant,
      buttonBackground: Colors.transparent,
      buttonForeground: cs.onSurface,
      buttonBorder: cs.outlineVariant,
      popoverBackground: cs.surfaceContainerHigh,
      popoverBorder: cs.outlineVariant,
      rowBackground: cs.surfaceContainer,
      rowHighlightBackground: cs.primaryContainer,
      rowHighlightForeground: cs.onPrimaryContainer,
      divider: cs.outlineVariant,
      shadows: [
        BoxShadow(
          color: cs.shadow.withValues(alpha: 0.35),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: cs.shadow.withValues(alpha: 0.25),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// Registered extension if present, otherwise derived from the theme.
  static StreakBadgeTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<StreakBadgeTheme>() ??
        StreakBadgeTheme.fromTheme(theme);
  }

  // Colours
  final Color foreground;
  final Color mutedForeground;
  final Color buttonBackground;
  final Color buttonForeground;
  final Color buttonBorder;
  final Color popoverBackground;
  final Color popoverBorder;
  final Color rowBackground;
  final Color rowHighlightBackground;
  final Color rowHighlightForeground;
  final Color divider;
  final List<BoxShadow> shadows;

  // Dimensions
  final double popoverRadius;
  final double buttonRadius;
  final double rowRadius;
  final double popoverWidth;
  final double gap; // space between rows
  final double anchorGap; // space between button and popover arrow
  final double arrowSize;

  // Motion
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  StreakBadgeTheme copyWith({
    Color? foreground,
    Color? mutedForeground,
    Color? buttonBackground,
    Color? buttonForeground,
    Color? buttonBorder,
    Color? popoverBackground,
    Color? popoverBorder,
    Color? rowBackground,
    Color? rowHighlightBackground,
    Color? rowHighlightForeground,
    Color? divider,
    List<BoxShadow>? shadows,
    double? popoverRadius,
    double? buttonRadius,
    double? rowRadius,
    double? popoverWidth,
    double? gap,
    double? anchorGap,
    double? arrowSize,
    Duration? animationDuration,
    Curve? animationCurve,
  }) {
    return StreakBadgeTheme(
      foreground: foreground ?? this.foreground,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      buttonBackground: buttonBackground ?? this.buttonBackground,
      buttonForeground: buttonForeground ?? this.buttonForeground,
      buttonBorder: buttonBorder ?? this.buttonBorder,
      popoverBackground: popoverBackground ?? this.popoverBackground,
      popoverBorder: popoverBorder ?? this.popoverBorder,
      rowBackground: rowBackground ?? this.rowBackground,
      rowHighlightBackground:
          rowHighlightBackground ?? this.rowHighlightBackground,
      rowHighlightForeground:
          rowHighlightForeground ?? this.rowHighlightForeground,
      divider: divider ?? this.divider,
      shadows: shadows ?? this.shadows,
      popoverRadius: popoverRadius ?? this.popoverRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      rowRadius: rowRadius ?? this.rowRadius,
      popoverWidth: popoverWidth ?? this.popoverWidth,
      gap: gap ?? this.gap,
      anchorGap: anchorGap ?? this.anchorGap,
      arrowSize: arrowSize ?? this.arrowSize,
      animationDuration: animationDuration ?? this.animationDuration,
      animationCurve: animationCurve ?? this.animationCurve,
    );
  }

  @override
  StreakBadgeTheme lerp(ThemeExtension<StreakBadgeTheme>? other, double t) {
    if (other is! StreakBadgeTheme) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => lerpDouble(a, b, t)!;
    return StreakBadgeTheme(
      foreground: c(foreground, other.foreground),
      mutedForeground: c(mutedForeground, other.mutedForeground),
      buttonBackground: c(buttonBackground, other.buttonBackground),
      buttonForeground: c(buttonForeground, other.buttonForeground),
      buttonBorder: c(buttonBorder, other.buttonBorder),
      popoverBackground: c(popoverBackground, other.popoverBackground),
      popoverBorder: c(popoverBorder, other.popoverBorder),
      rowBackground: c(rowBackground, other.rowBackground),
      rowHighlightBackground: c(
        rowHighlightBackground,
        other.rowHighlightBackground,
      ),
      rowHighlightForeground: c(
        rowHighlightForeground,
        other.rowHighlightForeground,
      ),
      divider: c(divider, other.divider),
      shadows: BoxShadow.lerpList(shadows, other.shadows, t)!,
      popoverRadius: d(popoverRadius, other.popoverRadius),
      buttonRadius: d(buttonRadius, other.buttonRadius),
      rowRadius: d(rowRadius, other.rowRadius),
      popoverWidth: d(popoverWidth, other.popoverWidth),
      gap: d(gap, other.gap),
      anchorGap: d(anchorGap, other.anchorGap),
      arrowSize: d(arrowSize, other.arrowSize),
      animationDuration: t < 0.5 ? animationDuration : other.animationDuration,
      animationCurve: t < 0.5 ? animationCurve : other.animationCurve,
    );
  }
}
