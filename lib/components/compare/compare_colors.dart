import 'package:flutter/material.dart';

/// Every colour used by the compare page, in one place.
///
/// Works with or without registering it in AppTheme: [of] falls back to the
/// [light]/[dark] defaults below. Register it (see app_theme.dart) when you
/// want to change colours from the theme files.
@immutable
class CompareColors extends ThemeExtension<CompareColors> {
  const CompareColors({
    required this.sheetBg,
    required this.appBarBg,
    required this.panelBg,
    required this.cardBg,
    required this.cardBorder,
    required this.text,
    required this.versionColor,
    required this.referenceColor,
    required this.verseNoColor,
    required this.control,
    required this.onControl,
  });

  final Color sheetBg; //        page background
  final Color appBarBg; //       top bar
  final Color panelBg; //        edition picker drop-down
  final Color cardBg; //         each edition card
  final Color cardBorder; //     card + segmented button outline
  final Color text; //           verse text, titles, icons
  final Color versionColor; //   "ESV" label on each card
  final Color referenceColor; // "John 7:3-5" label on each card
  final Color verseNoColor; //   the "3." numbers inside the card
  final Color control; //        checkboxes + selected segment
  final Color onControl; //      tick / text drawn on [control]

  static const light = CompareColors(
    sheetBg: Color(0xFFF5F5F5), //       grey.shade100
    appBarBg: Color(0xFFF5F5F5),
    panelBg: Color(0xFFEEEEEE), //       grey.shade200
    cardBg: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFBDBDBD), //    grey.shade400
    text: Color(0xFF212121), //          grey.shade900
    versionColor: Color(0xFF884E0C), //  same as kVerseNoColor (light)
    referenceColor: Color(0xFF616161), // grey.shade700
    verseNoColor: Color(0xFF884E0C),
    control: Color(0xFF424242), //       grey.shade800
    onControl: Color(0xFFFFFFFF),
  );

  static const dark = CompareColors(
    sheetBg: Color(0xFF303030), //       grey.shade850 (your dark surface)
    appBarBg: Color(0xFF424242), //      grey.shade800
    panelBg: Color(0xFF212121), //       grey.shade900
    cardBg: Color(0xFF212121), //        grey.shade900
    cardBorder: Color(0xFF616161), //    grey.shade700
    text: Color(0xFFEEEEEE), //          grey.shade200
    versionColor: Color(0xFFECBD3A), //  same as kVerseNoColor (dark)
    referenceColor: Color(0xFFBDBDBD), // grey.shade400
    verseNoColor: Color(0xFFECBD3A),
    control: Color(0xFF9E9E9E), //       grey.shade500
    onControl: Color(0xFF212121),
  );

  /// Registered extension if there is one, otherwise the matching default.
  static CompareColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<CompareColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  CompareColors copyWith({
    Color? sheetBg,
    Color? appBarBg,
    Color? panelBg,
    Color? cardBg,
    Color? cardBorder,
    Color? text,
    Color? versionColor,
    Color? referenceColor,
    Color? verseNoColor,
    Color? control,
    Color? onControl,
  }) {
    return CompareColors(
      sheetBg: sheetBg ?? this.sheetBg,
      appBarBg: appBarBg ?? this.appBarBg,
      panelBg: panelBg ?? this.panelBg,
      cardBg: cardBg ?? this.cardBg,
      cardBorder: cardBorder ?? this.cardBorder,
      text: text ?? this.text,
      versionColor: versionColor ?? this.versionColor,
      referenceColor: referenceColor ?? this.referenceColor,
      verseNoColor: verseNoColor ?? this.verseNoColor,
      control: control ?? this.control,
      onControl: onControl ?? this.onControl,
    );
  }

  @override
  CompareColors lerp(ThemeExtension<CompareColors>? other, double t) {
    if (other is! CompareColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return CompareColors(
      sheetBg: l(sheetBg, other.sheetBg),
      appBarBg: l(appBarBg, other.appBarBg),
      panelBg: l(panelBg, other.panelBg),
      cardBg: l(cardBg, other.cardBg),
      cardBorder: l(cardBorder, other.cardBorder),
      text: l(text, other.text),
      versionColor: l(versionColor, other.versionColor),
      referenceColor: l(referenceColor, other.referenceColor),
      verseNoColor: l(verseNoColor, other.verseNoColor),
      control: l(control, other.control),
      onControl: l(onControl, other.onControl),
    );
  }
}
