import 'package:flutter/material.dart';

import 'light_mode.dart';
import 'dark_mode.dart';

import 'component_themes.dart';

import 'package:dba2/components/streak/streak_badge_theme.dart';

class AppTheme {
  static final ThemeData light = _build(lightScheme, CustomColors.light);
  static final ThemeData dark = _build(darkScheme, CustomColors.dark);

  static ThemeData _build(ColorScheme scheme, CustomColors custom) =>
      ComponentThemes.apply(
        ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          extensions: <ThemeExtension<dynamic>>[custom, _streak(scheme)],
        ),
      );

  static StreakBadgeTheme _streak(ColorScheme cs) {
    final dark = cs.brightness == Brightness.dark;
    return StreakBadgeTheme.fromTheme(ThemeData(colorScheme: cs)).copyWith(
      popoverBackground: dark ? Colors.grey.shade800 : Colors.white,
      popoverBorder: cs.outlineVariant,
      rowBackground: dark ? Colors.grey.shade900 : Colors.grey.shade100,
      rowHighlightBackground: dark
          ? Colors.grey.shade700
          : Colors.grey.shade300,
      rowHighlightForeground: dark ? Colors.white : Colors.black,
      buttonBorder: cs.outline,
      // popoverRadius: 16,
      // animationDuration: const Duration(milliseconds: 220),
    );
  }
}

/// Custom colors outside standard Material ColorScheme (e.g. verse highlights, reader notes)
@immutable
class CustomColors extends ThemeExtension<CustomColors> {
  const CustomColors({
    required this.kVerseNoColor,
    required this.kFirstLetter,
    required this.kJesusColor,
    required this.kHebrewColor,
  });

  final Color? kVerseNoColor;
  final Color? kFirstLetter;
  final Color? kJesusColor;
  final Color? kHebrewColor;

  static const light = CustomColors(
    kVerseNoColor: Color(0xFF884E0C), // --verseNo (also the cap)
    kFirstLetter: Color(0xFFD4852A), // --verseNo (also the cap)
    kJesusColor: Color(0xFFB44444), // --wordsOfJesus
    kHebrewColor: Color(0xFF2557B3), // CornflowerBlue
  );

  static const dark = CustomColors(
    kVerseNoColor: Color(0xFFECBD3A), // --verseNo (also the cap)
    kFirstLetter: Color(0xFFD4A82A), // --verseNo (also the cap)
    kJesusColor: Color(0xFFFF9307), // --wordsOfJesus
    kHebrewColor: Color(0xFF6495ED), // CornflowerBlue
  );

  @override
  CustomColors copyWith({
    Color? kVerseNoColor,
    Color? kFirstLetter,
    Color? kJesusColor,
    Color? kHebrewColor,
  }) {
    return CustomColors(
      kVerseNoColor: kVerseNoColor ?? this.kVerseNoColor,
      kFirstLetter: kFirstLetter ?? this.kFirstLetter,
      kJesusColor: kJesusColor ?? this.kJesusColor,
      kHebrewColor: kHebrewColor ?? this.kHebrewColor,
    );
  }

  @override
  CustomColors lerp(ThemeExtension<CustomColors>? other, double t) {
    if (other is! CustomColors) return this;
    return CustomColors(
      kVerseNoColor: Color.lerp(kVerseNoColor, other.kVerseNoColor, t),
      kFirstLetter: Color.lerp(kFirstLetter, other.kFirstLetter, t),
      kJesusColor: Color.lerp(kJesusColor, other.kJesusColor, t),
      kHebrewColor: Color.lerp(kHebrewColor, other.kHebrewColor, t),
    );
  }
}

// HELPER: To shorten ColorTheme Vars
extension ThemeContextX on BuildContext {
  // USAGE: color: context.colorScheme.surface
  // Without Ext: color: Theme.of(context).colorScheme.surface
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  // USAGE: TextStyle(color: context.customColors.kJesusColor)
  // Without Ext: Theme.of(context).extension<CustomColors>()?.kJesusColor
  CustomColors get customColors => Theme.of(this).extension<CustomColors>()!;

  // True when the *resolved* theme is dark (works for system/light/dark)
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
