import 'package:flutter/material.dart';

/// A custom model used to map a keyword to its specific individual [TextStyle].
class KeywordStyle {
  final String word;
  final TextStyle style;

  const KeywordStyle({required this.word, required this.style});
}

/// Parses [text] and highlights a single [keyword] using a custom [highlightStyle],
/// while applying [baseStyle] to the rest of the text.
///
/// ### Example Usage:
/// ```dart
/// Text.rich(
///   highlightKeyword(
///     text: 'Warning, AudioBibles are 800MB each, Please use Wifi!',
///     keyword: 'Warning',
///     baseStyle: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
///     highlightStyle: TextStyle(fontSize: 11.5, color: Colors.orange, fontWeight: FontWeight.bold),
///   ),
///   textAlign: TextAlign.center,
/// )
/// ```
TextSpan highlightKeyword({
  required String text,
  required String keyword,
  required TextStyle baseStyle,
  required TextStyle highlightStyle,
}) {
  final List<InlineSpan> spans = [];

  text.splitMapJoin(
    RegExp(RegExp.escape(keyword), caseSensitive: false),
    onMatch: (match) {
      spans.add(TextSpan(text: match.group(0), style: highlightStyle));
      return ''; // consumed by splitMapJoin
    },
    onNonMatch: (nonMatch) {
      if (nonMatch.isNotEmpty) {
        spans.add(TextSpan(text: nonMatch, style: baseStyle));
      }
      return '';
    },
  );

  return TextSpan(children: spans);
}

/// Parses [text] and highlights a [List] of [keywords] using the same [highlightStyle],
/// while applying [baseStyle] to the rest of the text.
///
/// ### Example Usage:
/// ```dart
/// Text.rich(
///   highlightKeywords(
///     text: 'Warning, AudioBibles are 800MB each, Please use Wifi,\nUnless you have an unlimited mobile internet package!',
///     keywords: ['Warning', 'Wifi', 'unlimited'],
///     baseStyle: TextStyle(fontSize: 11.5, color: Colors.grey[500], fontWeight: FontWeight.w500),
///     highlightStyle: TextStyle(fontSize: 11.5, color: Colors.orange, fontWeight: FontWeight.bold),
///   ),
///   textAlign: TextAlign.center,
/// )
/// ```
TextSpan highlightKeywords({
  required String text,
  required List<String> keywords,
  required TextStyle baseStyle,
  required TextStyle highlightStyle,
}) {
  if (keywords.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }

  // Escape special regex characters in each keyword and join them with '|'
  final pattern = keywords.map(RegExp.escape).join('|');
  final regExp = RegExp(pattern, caseSensitive: false);

  final List<InlineSpan> spans = [];

  text.splitMapJoin(
    regExp,
    onMatch: (match) {
      spans.add(TextSpan(text: match.group(0), style: highlightStyle));
      return '';
    },
    onNonMatch: (nonMatch) {
      if (nonMatch.isNotEmpty) {
        spans.add(TextSpan(text: nonMatch, style: baseStyle));
      }
      return '';
    },
  );

  return TextSpan(children: spans);
}

/// Parses [text] and maps individual keywords to specific custom colors using a [Map].
///
/// ### Example Usage:
/// ```dart
/// Text.rich(
///   highlightMap(
///     text: 'Warning, AudioBibles are 800MB each, Please use Wifi,\nUnless you have an unlimited mobile internet package!',
///     keywordColors: {
///       'Warning': Colors.red,
///       '800MB': Colors.orange,
///       'Wifi': Colors.blue,
///     },
///     baseStyle: TextStyle(fontSize: 11.5, color: Colors.grey[500], fontWeight: FontWeight.w500),
///   ),
///   textAlign: TextAlign.center,
/// )
/// ```
TextSpan highlightMap({
  required String text,
  required Map<String, Color> keywordColors,
  required TextStyle baseStyle,
}) {
  if (keywordColors.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }

  // Create regex pattern matching all keys in the Map
  final pattern = keywordColors.keys.map(RegExp.escape).join('|');
  final regExp = RegExp(pattern, caseSensitive: false);

  final List<InlineSpan> spans = [];

  text.splitMapJoin(
    regExp,
    onMatch: (match) {
      final matchedText = match.group(0)!;
      // Find matching color (case-insensitive lookup)
      final colorKey = keywordColors.keys.firstWhere(
        (k) => k.toLowerCase() == matchedText.toLowerCase(),
        orElse: () => '',
      );
      final color = keywordColors[colorKey] ?? baseStyle.color;

      spans.add(
        TextSpan(
          text: matchedText,
          style: baseStyle.copyWith(color: color, fontWeight: FontWeight.bold),
        ),
      );
      return '';
    },
    onNonMatch: (nonMatch) {
      if (nonMatch.isNotEmpty) {
        spans.add(TextSpan(text: nonMatch, style: baseStyle));
      }
      return '';
    },
  );

  return TextSpan(children: spans);
}

/// Parses [text] and maps multiple keywords to fully customizable [TextStyle] rules
/// via a list of [KeywordStyle] objects.
///
/// ### Example Usage:
/// ```dart
/// Text.rich(
///   highlightCustomStyles(
///     text: 'Warning, AudioBibles are 800MB each, Please use Wifi!',
///     rules: [
///       KeywordStyle(word: 'Warning', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
///       KeywordStyle(word: 'Wifi', style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
///     ],
///     baseStyle: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
///   ),
///   textAlign: TextAlign.center,
/// )
/// ```
TextSpan highlightCustomStyles({
  required String text,
  required List<KeywordStyle> rules,
  required TextStyle baseStyle,
}) {
  if (rules.isEmpty) return TextSpan(text: text, style: baseStyle);

  final pattern = rules.map((r) => RegExp.escape(r.word)).join('|');
  final regExp = RegExp(pattern, caseSensitive: false);

  final List<InlineSpan> spans = [];

  text.splitMapJoin(
    regExp,
    onMatch: (match) {
      final matchedText = match.group(0)!;
      final matchedRule = rules.firstWhere(
        (r) => r.word.toLowerCase() == matchedText.toLowerCase(),
      );

      spans.add(
        TextSpan(
          text: matchedText,
          style: baseStyle.merge(matchedRule.style),
        ),
      );
      return '';
    },
    onNonMatch: (nonMatch) {
      if (nonMatch.isNotEmpty) {
        spans.add(TextSpan(text: nonMatch, style: baseStyle));
      }
      return '';
    },
  );

  return TextSpan(children: spans);
}
