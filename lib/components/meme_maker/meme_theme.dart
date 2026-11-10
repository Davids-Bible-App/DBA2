import 'package:flutter/material.dart';

/// ALL Meme Maker styling lives here. Tweak a value, hot-reload, done.
/// Light and dark are two const instances at the bottom of the class.
@immutable
class MemeTheme extends ThemeExtension<MemeTheme> {
  const MemeTheme({
    required this.page,
    required this.panel,
    required this.panelAlt,
    required this.border,
    required this.text,
    required this.textDim,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.success,
    required this.buttonBg,
    required this.buttonBgActive,
    required this.buttonFg,
    required this.checkerA,
    required this.checkerB,
    required this.selection,
    required this.exportBg,
    required this.exportFg,
    this.radiusS = 6,
    this.radiusM = 10,
    this.radiusL = 14,
    this.gap = 10,
    this.labelSize = 12.5,
    this.headerSize = 14,
  });

  // Backgrounds
  final Color page; // behind everything
  final Color panel; // main panels (layers, controls, templates)
  final Color panelAlt; // rows inside panels / active row
  final Color border;
  // Text
  final Color text, textDim;
  // Accents
  final Color accent, onAccent, danger, success;
  // Buttons
  final Color buttonBg, buttonBgActive, buttonFg;
  // Canvas workspace checkerboard + selection outline
  final Color checkerA, checkerB, selection;
  // Export button in the app bar
  final Color exportBg, exportFg;
  // Shape / spacing / type sizes
  final double radiusS, radiusM, radiusL, gap, labelSize, headerSize;

  TextStyle get label => TextStyle(fontSize: labelSize, color: textDim);
  TextStyle get header => TextStyle(
    fontSize: headerSize,
    fontWeight: FontWeight.w600,
    color: text,
  );
  TextStyle get body => TextStyle(fontSize: 14, color: text);

  static const light = MemeTheme(
    page: Color(0xFFF4F4F6),
    panel: Color(0xFFFFFFFF),
    panelAlt: Color(0xFFEDEDF1),
    border: Color(0xFFD0D0D8),
    text: Color(0xFF1B1B1F),
    textDim: Color(0xFF666670),
    accent: Color(0xFF2F6FEB),
    onAccent: Colors.white,
    danger: Color(0xFFD93025),
    success: Color(0xFF1E9E55),
    buttonBg: Color(0xFFE6E6EC),
    buttonBgActive: Color(0xFFC9D8FA),
    buttonFg: Color(0xFF1B1B1F),
    checkerA: Color(0xFFFFFFFF),
    checkerB: Color(0xFFEAEAEA),
    selection: Color(0xFF2F6FEB),
    exportBg: Color(0xFFD6E2FB),
    exportFg: Color(0xFF14315F),
  );

  static const dark = MemeTheme(
    page: Color(0xFF121214),
    panel: Color(0xFF1E1E22),
    panelAlt: Color(0xFF2A2A30),
    border: Color(0xFF3A3A42),
    text: Color(0xFFECECF1),
    textDim: Color(0xFF9A9AA6),
    accent: Color(0xFF6C9BFF),
    onAccent: Color(0xFF0B1B3F),
    danger: Color(0xFFFF6B63),
    success: Color(0xFF4ADE80),
    buttonBg: Color(0xFF33333B),
    buttonBgActive: Color(0xFF3F5A99),
    buttonFg: Color(0xFFECECF1),
    checkerA: Color(0xFF333333),
    checkerB: Color(0xFF252525),
    selection: Color(0xFF6C9BFF),
    exportBg: Color(0xFF3F5A99),
    exportFg: Color(0xFFECECF1),
  );

  static MemeTheme of(BuildContext context) =>
      Theme.of(context).extension<MemeTheme>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  MemeTheme copyWith({Color? accent, Color? panel}) => MemeTheme(
    page: page,
    panel: panel ?? this.panel,
    panelAlt: panelAlt,
    border: border,
    text: text,
    textDim: textDim,
    accent: accent ?? this.accent,
    onAccent: onAccent,
    danger: danger,
    success: success,
    buttonBg: buttonBg,
    buttonBgActive: buttonBgActive,
    buttonFg: buttonFg,
    checkerA: checkerA,
    checkerB: checkerB,
    selection: selection,
    exportBg: exportBg,
    exportFg: exportFg,
    radiusS: radiusS,
    radiusM: radiusM,
    radiusL: radiusL,
    gap: gap,
    labelSize: labelSize,
    headerSize: headerSize,
  );

  @override
  MemeTheme lerp(ThemeExtension<MemeTheme>? other, double t) =>
      other is MemeTheme && t >= 0.5 ? other : this;
}

/// Wrap the page in this: it picks light/dark from the app theme.
class MemeThemeScope extends StatelessWidget {
  const MemeThemeScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final mt = base.brightness == Brightness.dark
        ? MemeTheme.dark
        : MemeTheme.light;
    return Theme(
      data: base.copyWith(
        extensions: [...base.extensions.values, mt],
        scaffoldBackgroundColor: mt.page,
      ),
      child: child,
    );
  }
}
