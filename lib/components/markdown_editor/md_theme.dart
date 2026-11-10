import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Every colour slot the editor + viewer use. Add a slot here and it
/// automatically shows up in the theme editor dialog.
enum MdColor {
  background('Background'),
  surface('Toolbar / panels'),
  border('Borders'),
  text('Text'),
  mutedText('Muted text'),
  accent('Accent'),
  onAccent('Text on accent'),
  heading('Headings'),
  link('Links'),
  codeBackground('Code background'),
  codeText('Code text'),
  quoteBar('Quote bar'),
  quoteBackground('Quote background');

  const MdColor(this.label);
  final String label;
}

@immutable
class MdTheme {
  const MdTheme({
    required this.dark,
    required this.colors,
    this.editorFontSize = 15,
    this.previewFontSize = 16,
    this.lineHeight = 1.5,
    this.paragraphSpacing = 12,
    this.contentPadding = 16,
    this.fontFamily,
    this.monoEditor = true,
  });

  final bool dark;
  final Map<MdColor, Color> colors;
  final double editorFontSize;
  final double previewFontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final double contentPadding;
  final String? fontFamily; // null = system default
  final bool monoEditor;

  static const List<String> _monoFallback = ['monospace', 'Courier New'];

  Color c(MdColor k) => colors[k]!;

  // ---------------------------------------------------------------- presets
  factory MdTheme.light() => const MdTheme(
    dark: false,
    colors: {
      MdColor.background: Color(0xFFFFFFFF),
      MdColor.surface: Color(0xFFF6F8FA),
      MdColor.border: Color(0xFFD0D7DE),
      MdColor.text: Color(0xFF1F2328),
      MdColor.mutedText: Color(0xFF656D76),
      MdColor.accent: Color(0xFF0969DA),
      MdColor.onAccent: Color(0xFFFFFFFF),
      MdColor.heading: Color(0xFF1F2328),
      MdColor.link: Color(0xFF0969DA),
      MdColor.codeBackground: Color(0xFFEFF1F3),
      MdColor.codeText: Color(0xFF1F2328),
      MdColor.quoteBar: Color(0xFFD0D7DE),
      MdColor.quoteBackground: Color(0xFFF6F8FA),
    },
  );

  factory MdTheme.dark() => const MdTheme(
    dark: true,
    colors: {
      MdColor.background: Color(0xFF1B1B1B),
      MdColor.surface: Color(0xFF222222),
      MdColor.border: Color(0xFF30363D),
      MdColor.text: Color(0xFFE6EDF3),
      MdColor.mutedText: Color(0xFF8B949E),
      MdColor.accent: Color(0xFF818181),
      MdColor.onAccent: Color(0xFFFFFFFF),
      MdColor.heading: Color(0xFFE6EDF3),
      MdColor.link: Color(0xFF58A6FF),
      MdColor.codeBackground: Color(0xFF1F252D),
      MdColor.codeText: Color(0xFFE6EDF3),
      MdColor.quoteBar: Color(0xFF3D444D),
      MdColor.quoteBackground: Color(0xFF222222),
    },
  );

  /// Switch light <-> dark preset but keep your font/spacing tweaks.
  MdTheme switchedBrightness() =>
      (dark ? MdTheme.light() : MdTheme.dark()).copyWith(
        editorFontSize: editorFontSize,
        previewFontSize: previewFontSize,
        lineHeight: lineHeight,
        paragraphSpacing: paragraphSpacing,
        contentPadding: contentPadding,
        fontFamily: fontFamily,
        clearFontFamily: fontFamily == null,
        monoEditor: monoEditor,
      );

  MdTheme withColor(MdColor k, Color v) => copyWith(colors: {...colors, k: v});

  MdTheme copyWith({
    Map<MdColor, Color>? colors,
    double? editorFontSize,
    double? previewFontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? contentPadding,
    String? fontFamily,
    bool clearFontFamily = false,
    bool? monoEditor,
  }) => MdTheme(
    dark: dark,
    colors: colors ?? this.colors,
    editorFontSize: editorFontSize ?? this.editorFontSize,
    previewFontSize: previewFontSize ?? this.previewFontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    contentPadding: contentPadding ?? this.contentPadding,
    fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
    monoEditor: monoEditor ?? this.monoEditor,
  );

  // ------------------------------------------------------------- persistence
  Map<String, dynamic> toJson() => {
    'dark': dark,
    'colors': {for (final e in colors.entries) e.key.name: e.value.toARGB32()},
    'editorFontSize': editorFontSize,
    'previewFontSize': previewFontSize,
    'lineHeight': lineHeight,
    'paragraphSpacing': paragraphSpacing,
    'contentPadding': contentPadding,
    'fontFamily': fontFamily,
    'monoEditor': monoEditor,
  };

  factory MdTheme.fromJson(Map<String, dynamic> j) {
    final base = j['dark'] == true ? MdTheme.dark() : MdTheme.light();
    final map = Map<MdColor, Color>.of(base.colors);
    (j['colors'] as Map?)?.forEach((k, v) {
      final slot = MdColor.values.where((e) => e.name == k).firstOrNull;
      if (slot != null && v is int) map[slot] = Color(v);
    });
    return base.copyWith(
      colors: map,
      editorFontSize: (j['editorFontSize'] as num?)?.toDouble(),
      previewFontSize: (j['previewFontSize'] as num?)?.toDouble(),
      lineHeight: (j['lineHeight'] as num?)?.toDouble(),
      paragraphSpacing: (j['paragraphSpacing'] as num?)?.toDouble(),
      contentPadding: (j['contentPadding'] as num?)?.toDouble(),
      fontFamily: j['fontFamily'] as String?,
      monoEditor: j['monoEditor'] as bool?,
    );
  }

  // ------------------------------------------------------------------ styles
  TextStyle codeStyle(double size) => TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: _monoFallback,
    fontSize: size,
    color: c(MdColor.codeText),
  );

  TextStyle get editorStyle => monoEditor
      ? codeStyle(editorFontSize)
            .copyWith(color: c(MdColor.text), height: lineHeight)
      : TextStyle(
          fontFamily: fontFamily,
          fontSize: editorFontSize,
          height: lineHeight,
          color: c(MdColor.text),
        );

  /// Scoped Material theme: the editor never touches your app's theme.
  ThemeData toMaterial() {
    final scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: c(MdColor.accent),
      onPrimary: c(MdColor.onAccent),
      secondary: c(MdColor.accent),
      onSecondary: c(MdColor.onAccent),
      secondaryContainer: c(MdColor.accent).withValues(alpha: 0.2),
      onSecondaryContainer: c(MdColor.text),
      error: const Color(0xFFCF222E),
      onError: Colors.white,
      surface: c(MdColor.surface),
      onSurface: c(MdColor.text),
      onSurfaceVariant: c(MdColor.mutedText),
      outline: c(MdColor.border),
      outlineVariant: c(MdColor.border),
      surfaceContainerLowest: c(MdColor.background),
      surfaceContainerLow: c(MdColor.surface),
      surfaceContainer: c(MdColor.surface),
      surfaceContainerHigh: c(MdColor.surface),
      surfaceContainerHighest: c(MdColor.surface),
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: c(MdColor.background),
      canvasColor: c(MdColor.surface),
      dividerColor: c(MdColor.border),
      dividerTheme: DividerThemeData(
        color: c(MdColor.border),
        space: 1,
        thickness: 1,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: c(MdColor.text),
        displayColor: c(MdColor.text),
        fontFamily: fontFamily,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c(MdColor.surface),
        foregroundColor: c(MdColor.text),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c(MdColor.accent),
        selectionColor: c(MdColor.accent).withValues(alpha: 0.3),
        selectionHandleColor: c(MdColor.accent),
      ),
    );
  }

  MarkdownStyleSheet toStyleSheet() {
    final fs = previewFontSize;
    // MarkdownStyleSheet.fromTheme asserts that bodyMedium has a fontSize,
    // which our scoped theme's text styles may not carry, so set it explicitly.
    final m = toMaterial();
    final safe = m.copyWith(
      textTheme: m.textTheme.copyWith(
        bodyMedium: (m.textTheme.bodyMedium ?? const TextStyle()).copyWith(
          fontSize: fs,
        ),
      ),
    );
    final base = MarkdownStyleSheet.fromTheme(safe);
    TextStyle h(double mult, {Color? color}) => TextStyle(
      fontFamily: fontFamily,
      fontSize: fs * mult,
      fontWeight: FontWeight.w700,
      height: 1.25,
      color: color ?? c(MdColor.heading),
    );
    final body = TextStyle(
      fontFamily: fontFamily,
      fontSize: fs,
      height: lineHeight,
      color: c(MdColor.text),
    );
    return base.copyWith(
      p: body,
      h1: h(2.0),
      h2: h(1.6),
      h3: h(1.3),
      h4: h(1.15),
      h5: h(1.0),
      h6: h(0.9, color: c(MdColor.mutedText)),
      a: TextStyle(
        color: c(MdColor.link),
        decoration: TextDecoration.underline,
      ),
      code: codeStyle(fs * 0.88)
          .copyWith(backgroundColor: c(MdColor.codeBackground)),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: c(MdColor.codeBackground),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c(MdColor.border)),
      ),
      blockquote: body.copyWith(color: c(MdColor.mutedText)),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      blockquoteDecoration: BoxDecoration(
        color: c(MdColor.quoteBackground),
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: c(MdColor.quoteBar), width: 4)),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c(MdColor.border), width: 2)),
      ),
      tableBorder: TableBorder.all(color: c(MdColor.border)),
      tableHead: body.copyWith(fontWeight: FontWeight.w600),
      tableBody: body,
      tableCellsPadding: const EdgeInsets.all(8),
      blockSpacing: paragraphSpacing,
      listBullet: body,
    );
  }
}
