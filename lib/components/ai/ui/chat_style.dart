import 'package:flutter/material.dart';

/// All chat colours, fonts and sizes in one place. Edit [light] / [dark].
@immutable
class ChatStyle {
  const ChatStyle({
    // Page
    required this.background,
    required this.appBar,
    required this.appBarText,
    required this.drawer,
    // Bubbles
    required this.userBubble,
    required this.userText,
    required this.aiBubble,
    required this.aiText,
    // Input row
    required this.inputFill,
    required this.inputText,
    required this.inputBorder,
    required this.inputHint,
    // Accents
    required this.accent, // Send button, cursor, focused border
    required this.onAccent, // text on the Send button
    required this.actionIcon, // copy / reply icons under a reply
    required this.codeBackground, // code blocks, quotes, tables in replies
    required this.quoteBar,
    // Typography / shape
    this.fontFamily, // null = app default. Must be declared in pubspec.yaml
    this.fontSize = 15,
    this.bubbleRadius = 14,
    this.bubbleWidthFactor = 0.75, // share of screen width, max 640px
    this.progress = const Color(0xFF4CAF50),
  });

  final Color background, appBar, appBarText, drawer;
  final Color userBubble, userText, aiBubble, aiText;
  final Color inputFill, inputText, inputBorder, inputHint;
  final Color accent, onAccent, actionIcon, codeBackground, quoteBar;
  final String? fontFamily;
  final double fontSize, bubbleRadius, bubbleWidthFactor;
  final Color progress;

  static const light = ChatStyle(
    background: Color(0xFFF5F5F5),
    appBar: Color(0xFFE0E0E0),
    appBarText: Color(0xFF212121),
    drawer: Color(0xFFF5F5F5),
    userBubble: Color(0xFF424242),
    userText: Colors.white,
    aiBubble: Colors.white,
    aiText: Color(0xFF212121),
    inputFill: Colors.white,
    inputText: Color(0xFF212121),
    inputBorder: Color(0xFFBDBDBD),
    inputHint: Color(0xFF757575),
    accent: Color(0xFF424242),
    onAccent: Colors.white,
    actionIcon: Color(0xFF616161),
    codeBackground: Color(0xFFEEEEEE),
    quoteBar: Color(0xFF9E9E9E),
  );

  static const dark = ChatStyle(
    background: Color(0xFF1E1E1E),
    appBar: Color(0xFF2A2A2A),
    appBarText: Color(0xFFEEEEEE),
    drawer: Color(0xFF252525),
    userBubble: Color(0xFF4A4A4A),
    userText: Colors.white,
    aiBubble: Color(0xFF2C2C2C),
    aiText: Color(0xFFE6E6E6),
    inputFill: Color(0xFF2A2A2A),
    inputText: Color(0xFFEEEEEE),
    inputBorder: Color(0xFF555555),
    inputHint: Color(0xFF9E9E9E),
    accent: Color(0xFFBDBDBD),
    onAccent: Color(0xFF1E1E1E),
    actionIcon: Color(0xFF9E9E9E),
    codeBackground: Color(0xFF1A1A1A),
    quoteBar: Color(0xFF888888),
  );

  /// Picks light or dark from the app's current theme.
  static ChatStyle of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// Re-colours a whole subtree (dialogs, banners, buttons, fields) from
  /// this style. Wrap a dialog in Theme(data: style.themed(base), ...).
  ThemeData themed(ThemeData base) {
    final s = this;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(s.bubbleRadius - 4),
      borderSide: BorderSide(color: c, width: w),
    );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: s.accent,
        onPrimary: s.onAccent,
        onSurface: s.aiText,
        onSurfaceVariant: s.actionIcon,
        outline: s.inputBorder,
        secondaryContainer: s.codeBackground,
        onSecondaryContainer: s.aiText,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: s.aiText,
        displayColor: s.aiText,
        fontFamily: s.fontFamily,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(s.bubbleRadius + 2),
        ),
        titleTextStyle: TextStyle(
          color: s.aiText,
          fontSize: s.fontSize + 5,
          fontWeight: FontWeight.w600,
          fontFamily: s.fontFamily,
        ),
        contentTextStyle: TextStyle(
          color: s.aiText,
          fontSize: s.fontSize,
          height: 1.35,
          fontFamily: s.fontFamily,
        ),
      ),
      cardTheme: CardThemeData(
        color: s.aiBubble,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(s.bubbleRadius),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: s.codeBackground,
        labelStyle: TextStyle(color: s.aiText, fontSize: s.fontSize - 3),
        side: BorderSide.none,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.inputFill,
        hintStyle: TextStyle(color: s.inputHint),
        border: border(s.inputBorder),
        enabledBorder: border(s.inputBorder),
        focusedBorder: border(s.accent, 2),
      ),
      textSelectionTheme: TextSelectionThemeData(cursorColor: s.accent),
      sliderTheme: SliderThemeData(
        activeTrackColor: s.accent,
        thumbColor: s.accent,
        inactiveTrackColor: s.inputBorder,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: s.progress,
        linearTrackColor: s.inputBorder.withValues(alpha: 0.4),
      ),
      iconTheme: IconThemeData(color: s.actionIcon),
    );
  }
}
