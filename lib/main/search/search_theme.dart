import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Every colour / size / text style the search UI uses lives here.
/// Think of it as the `:root { --something: ... }` block of SearchRef.css.
///
/// Nothing needs registering: [SearchRefTheme.of] falls back to values derived
/// from your ColorScheme, so light/dark follow automatically. To override,
/// register it in your ThemeData (see ComponentThemes notes in the answer).
@immutable
class SearchRefTheme extends ThemeExtension<SearchRefTheme> {
  const SearchRefTheme({
    required this.inputFill,
    required this.inputRadius,
    required this.refStyle,
    required this.verseStyle,
    required this.mutedText,
    required this.markBackground,
    required this.markForeground,
    required this.selectedTint,
    required this.dividerColor,
    required this.panelBackground,
    required this.noResultsColor,
    required this.pagingBackground,
  });

  /// .SearchRef-Input background
  final Color inputFill;
  final double inputRadius;

  /// "1 Corinthians 10:12 (KJV)"
  final TextStyle refStyle;

  /// The verse text itself
  final TextStyle verseStyle;

  /// "Total Results", hints, etc. (--text-color-tone)
  final Color mutedText;

  /// <mark> chip (--verseNo background / --text-color-inverted text)
  final Color markBackground;
  final Color markForeground;

  /// .SearchRef-selected-verse
  final Color selectedTint;

  /// Line between results (--btn-border)
  final Color dividerColor;

  /// History dropdown
  final Color panelBackground;
  final Color noResultsColor;

  /// .SearchRef-paging bar
  final Color pagingBackground;

  /// Defaults derived from the current ThemeData.
  factory SearchRefTheme.fallback(ThemeData theme) {
    final cs = theme.colorScheme;
    final text = theme.textTheme;
    // Same gold as your kVerseNoColor. Swap for context.customColors if you like.
    const gold = Color(0xFFD4A82A);

    return SearchRefTheme(
      inputFill: cs.onSurface.withValues(alpha: 0.08),
      inputRadius: 12,
      refStyle: (text.bodyMedium ?? const TextStyle()).copyWith(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w600,
        color: cs.onSurface.withValues(alpha: 0.6),
      ),
      verseStyle: (text.bodyLarge ?? const TextStyle()).copyWith(height: 1.4),
      mutedText: cs.onSurface.withValues(alpha: 0.6),
      markBackground: gold,
      markForeground:
          ThemeData.estimateBrightnessForColor(gold) == Brightness.light
          ? Colors.black
          : Colors.white,
      selectedTint: cs.onSurface.withValues(alpha: 0.12),
      dividerColor: cs.outlineVariant,
      panelBackground: cs.surfaceContainerHigh,
      noResultsColor: cs.error,
      pagingBackground: cs.onSurface.withValues(alpha: 0.06),
    );
  }

  /// Use this inside widgets: `final t = SearchRefTheme.of(context);`
  static SearchRefTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SearchRefTheme>() ?? SearchRefTheme.fallback(theme);
  }

  @override
  SearchRefTheme copyWith({
    Color? inputFill,
    double? inputRadius,
    TextStyle? refStyle,
    TextStyle? verseStyle,
    Color? mutedText,
    Color? markBackground,
    Color? markForeground,
    Color? selectedTint,
    Color? dividerColor,
    Color? panelBackground,
    Color? noResultsColor,
    Color? pagingBackground,
  }) => SearchRefTheme(
    inputFill: inputFill ?? this.inputFill,
    inputRadius: inputRadius ?? this.inputRadius,
    refStyle: refStyle ?? this.refStyle,
    verseStyle: verseStyle ?? this.verseStyle,
    mutedText: mutedText ?? this.mutedText,
    markBackground: markBackground ?? this.markBackground,
    markForeground: markForeground ?? this.markForeground,
    selectedTint: selectedTint ?? this.selectedTint,
    dividerColor: dividerColor ?? this.dividerColor,
    panelBackground: panelBackground ?? this.panelBackground,
    noResultsColor: noResultsColor ?? this.noResultsColor,
    pagingBackground: pagingBackground ?? this.pagingBackground,
  );

  @override
  SearchRefTheme lerp(ThemeExtension<SearchRefTheme>? other, double t) {
    if (other is! SearchRefTheme) return this;
    return SearchRefTheme(
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      inputRadius: lerpDouble(inputRadius, other.inputRadius, t)!,
      refStyle: TextStyle.lerp(refStyle, other.refStyle, t)!,
      verseStyle: TextStyle.lerp(verseStyle, other.verseStyle, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      markBackground: Color.lerp(markBackground, other.markBackground, t)!,
      markForeground: Color.lerp(markForeground, other.markForeground, t)!,
      selectedTint: Color.lerp(selectedTint, other.selectedTint, t)!,
      dividerColor: Color.lerp(dividerColor, other.dividerColor, t)!,
      panelBackground: Color.lerp(panelBackground, other.panelBackground, t)!,
      noResultsColor: Color.lerp(noResultsColor, other.noResultsColor, t)!,
      pagingBackground: Color.lerp(
        pagingBackground,
        other.pagingBackground,
        t,
      )!,
    );
  }
}
