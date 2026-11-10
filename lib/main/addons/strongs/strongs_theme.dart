import 'package:flutter/material.dart';

/// The Strong's sheets' "CSS variables".
///
/// Every colour in the sheets comes from here (or from the ColorScheme), never
/// hard-coded in a widget. Works with NO setup: if you haven't registered it,
/// [of] derives sensible values from your ColorScheme, so light/dark follow
/// automatically. To override, add it to your ThemeData:
///
///   ThemeData(extensions: [StrongsTheme.fromScheme(cs).copyWith(refColor: ...)])
///
/// CSS -> here:
///   #688fbc (ref / tag text) ......... refColor
///   var(--ThemeBackgrounds1) ......... tagBackground / inputFill / panelBackground
///   var(--text-color-dimmed/er) ...... dimText / dimmerText
///   var(--btn-border) ................ divider
@immutable
class StrongsTheme extends ThemeExtension<StrongsTheme> {
  const StrongsTheme({
    required this.refColor,
    required this.tagBackground,
    required this.dimText,
    required this.dimmerText,
    required this.divider,
    required this.inputFill,
    required this.panelBackground,
    required this.noResultsColor,
    required this.inputRadius,
    this.lemmaFontFamily,
  });

  factory StrongsTheme.fromScheme(ColorScheme cs) => StrongsTheme(
    refColor: const Color(0xFF688FBC),
    tagBackground: cs.surfaceContainerHighest,
    dimText: cs.onSurface.withValues(alpha: 0.75),
    dimmerText: cs.onSurface.withValues(alpha: 0.55),
    divider: cs.outlineVariant,
    inputFill: cs.surfaceContainerHighest,
    panelBackground: cs.surfaceContainerHigh,
    noResultsColor: cs.error,
    inputRadius: 12,
  );

  static StrongsTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<StrongsTheme>() ??
        StrongsTheme.fromScheme(theme.colorScheme);
  }

  final Color refColor;
  final Color tagBackground;
  final Color dimText;
  final Color dimmerText;
  final Color divider;
  final Color inputFill;
  final Color panelBackground;
  final Color noResultsColor;
  final double inputRadius;

  /// Font for Greek/Hebrew lemmas. Android has no "Times New Roman"; bundle a
  /// font with polytonic Greek + Hebrew points (e.g. SBL, Gentium, Noto Serif)
  /// and put its family name here.
  final String? lemmaFontFamily;

  @override
  StrongsTheme copyWith({
    Color? refColor,
    Color? tagBackground,
    Color? dimText,
    Color? dimmerText,
    Color? divider,
    Color? inputFill,
    Color? panelBackground,
    Color? noResultsColor,
    double? inputRadius,
    String? lemmaFontFamily,
  }) => StrongsTheme(
    refColor: refColor ?? this.refColor,
    tagBackground: tagBackground ?? this.tagBackground,
    dimText: dimText ?? this.dimText,
    dimmerText: dimmerText ?? this.dimmerText,
    divider: divider ?? this.divider,
    inputFill: inputFill ?? this.inputFill,
    panelBackground: panelBackground ?? this.panelBackground,
    noResultsColor: noResultsColor ?? this.noResultsColor,
    inputRadius: inputRadius ?? this.inputRadius,
    lemmaFontFamily: lemmaFontFamily ?? this.lemmaFontFamily,
  );

  @override
  StrongsTheme lerp(ThemeExtension<StrongsTheme>? other, double t) {
    if (other is! StrongsTheme) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return StrongsTheme(
      refColor: c(refColor, other.refColor),
      tagBackground: c(tagBackground, other.tagBackground),
      dimText: c(dimText, other.dimText),
      dimmerText: c(dimmerText, other.dimmerText),
      divider: c(divider, other.divider),
      inputFill: c(inputFill, other.inputFill),
      panelBackground: c(panelBackground, other.panelBackground),
      noResultsColor: c(noResultsColor, other.noResultsColor),
      inputRadius: inputRadius + (other.inputRadius - inputRadius) * t,
      lemmaFontFamily: t < 0.5 ? lemmaFontFamily : other.lemmaFontFamily,
    );
  }
}
