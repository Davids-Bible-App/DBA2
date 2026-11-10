import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sentinel "layer id" used when the background is the selected thing.
const kBackgroundId = 'background';

const kPresetImages = <String>[
  'https://images.pexels.com/photos/459037/pexels-photo-459037.jpeg',
  'https://images.pexels.com/photos/326055/pexels-photo-326055.jpeg',
  'https://images.pexels.com/photos/417074/pexels-photo-417074.jpeg',
  'https://images.pexels.com/photos/355465/pexels-photo-355465.jpeg',
  'https://images.pexels.com/photos/1323550/pexels-photo-1323550.jpeg',
  'https://images.pexels.com/photos/12600615/pexels-photo-12600615.jpeg',
  'https://images.pexels.com/photos/9400206/pexels-photo-9400206.jpeg',
  'https://images.pexels.com/photos/2649403/pexels-photo-2649403.jpeg',
];

// ─────────────────────────── fonts ───────────────────────────

class MemeFont {
  const MemeFont(this.label, this.family, {this.google = false});
  final String label;
  final String family; // also the key stored in saved projects
  final bool google; // downloaded + cached by the google_fonts package

  /// Decorative Google fonts have a single weight, so B / I are hidden.
  bool get hasBold => !google;

  /// Starts the (cached) font download without building a widget.
  void preload() {
    if (google) GoogleFonts.getFont(family);
  }

  TextStyle get style => google
      ? GoogleFonts.getFont(family)
      : TextStyle(
          fontFamily: family,
          fontFamilyFallback: const ['Roboto', 'sans-serif'],
        );
}

const kMemeFonts = <MemeFont>[
  MemeFont('Brush Script', 'Brush Script MT'),
  MemeFont('Arial', 'Arial'),
  MemeFont('Verdana', 'Verdana'),
  MemeFont('Georgia', 'Georgia'),
  MemeFont('Times New Roman', 'Times New Roman'),
  MemeFont('Bangers (Comic)', 'Bangers', google: true),
  MemeFont('Marker', 'Permanent Marker', google: true),
  MemeFont('Playball (Script)', 'Playball', google: true),
  MemeFont('Playwrite', 'Playwrite US Trad', google: true),
  MemeFont('Caveat Brush', 'Caveat Brush', google: true),
  MemeFont('Coiny', 'Coiny', google: true),
  MemeFont('DynaPuff', 'DynaPuff', google: true),
  MemeFont('Finger Paint', 'Finger Paint', google: true),
  MemeFont('Gabriela', 'Gabriela', google: true),
  MemeFont('Kablammo', 'Kablammo', google: true),
  MemeFont('Kavoon', 'Kavoon', google: true),
  MemeFont('Mystery Quest', 'Mystery Quest', google: true),
  MemeFont('Ranchers', 'Ranchers', google: true),
];

/// Accepts a plain key ("Arial") or a v1 CSS string ("'Arial', Helvetica, ...").
MemeFont fontByKey(String raw) {
  final first = raw.split(',').first.replaceAll(RegExp('''['"]'''), '').trim();
  for (final f in kMemeFonts) {
    if (f.family.toLowerCase() == first.toLowerCase()) return f;
  }
  return kMemeFonts.first;
}

// ─────────────────────────── enums ───────────────────────────

enum CornerStyle { none, round, bevel, squircle }

enum BgFit {
  cover('cover'),
  contain('contain'),
  stretch('100% 100%'); // same tokens as v1 so old templates still load

  const BgFit(this.key);
  final String key;
  static BgFit parse(String? k) =>
      values.firstWhere((e) => e.key == k, orElse: () => cover);
}

enum MemeAspect {
  square('1 / 1', 1),
  portrait('4 / 5', 0.8),
  wide('16 / 9', 16 / 9),
  original('auto', null); // follows the background image

  const MemeAspect(this.key, this.ratio);
  final String key;
  final double? ratio;
  static MemeAspect parse(String? k) =>
      values.firstWhere((e) => e.key == k, orElse: () => square);
}

enum ExportFormat { png, jpeg }

// ─────────────────────────── helpers ───────────────────────────

final _rnd = math.Random();
String newId([String p = 'l_']) =>
    '$p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${_rnd.nextInt(1 << 20).toRadixString(36)}';

Color _hex(Object? v, Color fallback) {
  if (v is String && v.length == 7 && v.startsWith('#')) {
    final n = int.tryParse(v.substring(1), radix: 16);
    if (n != null) return Color(0xFF000000 | n);
  }
  return fallback;
}

String _toHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

double _d(Object? v, double fallback) => (v as num?)?.toDouble() ?? fallback;

// ─────────────────────────── layer ───────────────────────────

/// One text layer. Immutable: every edit creates a new object, which is what
/// makes undo/redo nearly free (history just keeps references).
@immutable
class MemeLayer {
  const MemeLayer({
    required this.id,
    this.content = 'New text',
    this.x = 50,
    this.y = 20,
    this.fontFamily = 'Brush Script MT',
    this.textWrap = false,
    this.wrapWidth = 100,
    this.bold = true,
    this.italic = false,
    this.color = const Color(0xFFEB8875),
    this.strokeColor = const Color(0xFF005876),
    this.strokeWidth = 0.3,
    this.shadow = false,
    this.shadowX = 4,
    this.shadowY = 6,
    this.shadowBlur = 4,
    this.shadowIntensity = 0.7,
    this.textBlockIntensity = 0,
    this.textBlockWidth = 0,
    this.scale = 1,
    this.lineHeight = 1.2,
    this.letterSpacing = 0,
    this.rotation = 0,
    this.visible = true,
    this.locked = false,
  });

  final String id, content, fontFamily;
  final double x, y; // % of the canvas, centre of the text
  final bool textWrap, bold, italic, shadow, visible, locked;
  final double wrapWidth, strokeWidth, shadowX, shadowY, shadowBlur;
  final double shadowIntensity, textBlockIntensity, textBlockWidth;
  final double scale, lineHeight, letterSpacing;
  final double rotation; // degrees, -180..180
  final Color color, strokeColor;

  MemeLayer copyWith({
    String? content,
    double? x,
    double? y,
    String? fontFamily,
    bool? textWrap,
    double? wrapWidth,
    bool? bold,
    bool? italic,
    Color? color,
    Color? strokeColor,
    double? strokeWidth,
    bool? shadow,
    double? shadowX,
    double? shadowY,
    double? shadowBlur,
    double? shadowIntensity,
    double? textBlockIntensity,
    double? textBlockWidth,
    double? scale,
    double? lineHeight,
    double? letterSpacing,
    double? rotation,
    bool? visible,
    bool? locked,
    String? id,
  }) => MemeLayer(
    id: id ?? this.id,
    content: content ?? this.content,
    x: x ?? this.x,
    y: y ?? this.y,
    fontFamily: fontFamily ?? this.fontFamily,
    textWrap: textWrap ?? this.textWrap,
    wrapWidth: wrapWidth ?? this.wrapWidth,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    color: color ?? this.color,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    shadow: shadow ?? this.shadow,
    shadowX: shadowX ?? this.shadowX,
    shadowY: shadowY ?? this.shadowY,
    shadowBlur: shadowBlur ?? this.shadowBlur,
    shadowIntensity: shadowIntensity ?? this.shadowIntensity,
    textBlockIntensity: textBlockIntensity ?? this.textBlockIntensity,
    textBlockWidth: textBlockWidth ?? this.textBlockWidth,
    scale: scale ?? this.scale,
    lineHeight: lineHeight ?? this.lineHeight,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    rotation: rotation ?? this.rotation,
    visible: visible ?? this.visible,
    locked: locked ?? this.locked,
  );

  /// Everything that changes how the text is *laid out* (not where it is).
  /// The text-layout cache uses this, so dragging never re-lays-out text.
  int get layoutSig => Object.hashAll([
    content,
    fontFamily,
    textWrap,
    wrapWidth,
    bold,
    italic,
    color,
    strokeColor,
    strokeWidth,
    shadow,
    shadowX,
    shadowY,
    shadowBlur,
    shadowIntensity,
    textBlockWidth,
    scale,
    lineHeight,
    letterSpacing,
  ]);

  Map<String, Object?> toJson() => {
    'id': id,
    'type': 'text',
    'content': content,
    'x': x,
    'y': y,
    'fontFamily': fontFamily,
    'textWrap': textWrap,
    'wrapWidth': wrapWidth,
    'bold': bold,
    'italic': italic,
    'color': _toHex(color),
    'strokeColor': _toHex(strokeColor),
    'strokeWidth': strokeWidth,
    'shadow': shadow,
    'shadowX': shadowX,
    'shadowY': shadowY,
    'shadowBlur': shadowBlur,
    'shadowIntensity': shadowIntensity,
    'textBlockIntensity': textBlockIntensity,
    'textBlockWidth': textBlockWidth,
    'scale': scale,
    'lineHeight': lineHeight,
    'letterSpacing': letterSpacing,
    'rotation': rotation,
    'visible': visible,
    'locked': locked,
  };

  /// Reads both v2 and v1 (Tauri) layer JSON.
  factory MemeLayer.fromJson(Map<String, dynamic> j) {
    const d = MemeLayer(id: '');
    return MemeLayer(
      id: (j['id'] as String?) ?? newId(),
      content: (j['content'] as String?) ?? d.content,
      x: _d(j['x'], d.x),
      y: _d(j['y'], d.y),
      fontFamily: fontByKey((j['fontFamily'] as String?) ?? '').family,
      textWrap: (j['textWrap'] as bool?) ?? d.textWrap,
      wrapWidth: _d(j['wrapWidth'], d.wrapWidth),
      bold: (j['bold'] as bool?) ?? d.bold,
      italic: (j['italic'] as bool?) ?? d.italic,
      color: _hex(j['color'], d.color),
      strokeColor: _hex(j['strokeColor'], d.strokeColor),
      strokeWidth: _d(j['strokeWidth'], d.strokeWidth),
      shadow: (j['shadow'] as bool?) ?? d.shadow,
      shadowX: _d(j['shadowX'], d.shadowX),
      shadowY: _d(j['shadowY'], d.shadowY),
      shadowBlur: _d(j['shadowBlur'], d.shadowBlur),
      shadowIntensity: _d(j['shadowIntensity'], d.shadowIntensity),
      textBlockIntensity: _d(j['textBlockIntensity'], 0),
      textBlockWidth: math.min(120, _d(j['textBlockWidth'], 0)),
      scale: _d(j['scale'], d.scale),
      lineHeight: _d(j['lineHeight'], d.lineHeight),
      letterSpacing: _d(j['letterSpacing'], d.letterSpacing),
      rotation: _d(j['rotation'], 0),
      visible: (j['visible'] as bool?) ?? true,
      locked: (j['locked'] as bool?) ?? false,
    );
  }
}

// ─────────────────────────── whole design ───────────────────────────

const _unset = Object();

/// Everything that is undoable and saved in a template.
@immutable
class MemeState {
  const MemeState({
    this.selectedImage,
    required this.layers,
    this.fit = BgFit.cover,
    this.bgColor = const Color(0xFF7E3E3E),
    this.bgX = 50,
    this.bgY = 50,
    this.corner = CornerStyle.squircle,
    this.cornerSize = 24,
    this.flipH = false,
    this.flipV = false,
    this.aspect = MemeAspect.square,
    this.bgZoom = 1,
    this.bgLocked = false,
  });

  factory MemeState.initial() => MemeState(
    selectedImage: kPresetImages.first,
    layers: [
      MemeLayer(
        id: newId(),
        content: 'Your verse text',
        shadow: true,
      ),
    ],
  );

  final String? selectedImage; // file name in /memes, or an http(s) URL
  final List<MemeLayer> layers; // index 0 = back, last = front
  final BgFit fit;
  final Color bgColor;
  final double bgX, bgY; // 0..100, same meaning as CSS background-position
  final CornerStyle corner;
  final double cornerSize;
  final bool flipH, flipV;
  final MemeAspect aspect;
  final double bgZoom; // 0.5..4, 1 = no zoom
  final bool bgLocked; // image can't be moved / zoomed by accident

  MemeState copyWith({
    Object? selectedImage = _unset,
    List<MemeLayer>? layers,
    BgFit? fit,
    Color? bgColor,
    double? bgX,
    double? bgY,
    CornerStyle? corner,
    double? cornerSize,
    bool? flipH,
    bool? flipV,
    MemeAspect? aspect,
    double? bgZoom,
    bool? bgLocked,
  }) => MemeState(
    selectedImage: identical(selectedImage, _unset)
        ? this.selectedImage
        : selectedImage as String?,
    layers: layers ?? this.layers,
    fit: fit ?? this.fit,
    bgColor: bgColor ?? this.bgColor,
    bgX: bgX ?? this.bgX,
    bgY: bgY ?? this.bgY,
    corner: corner ?? this.corner,
    cornerSize: cornerSize ?? this.cornerSize,
    flipH: flipH ?? this.flipH,
    flipV: flipV ?? this.flipV,
    aspect: aspect ?? this.aspect,
    bgZoom: bgZoom ?? this.bgZoom,
    bgLocked: bgLocked ?? this.bgLocked,
  );

  Map<String, Object?> toJson() => {
    'selectedImage': selectedImage,
    'layers': [for (final l in layers) l.toJson()],
    'bgSize': fit.key,
    'bgPos': {'x': bgX, 'y': bgY},
    'bgColor': _toHex(bgColor),
    'cornerStyle': corner.name,
    'cornerSize': cornerSize,
    'flipH': flipH,
    'flipV': flipV,
    'aspectRatio': aspect.key,
    'bgZoom': bgZoom,
    'bgLocked': bgLocked,
  };

  /// Reads both v2 and v1 (Tauri) payloads.
  factory MemeState.fromJson(Map<String, dynamic> j) {
    final pos = (j['bgPos'] as Map?) ?? const {};
    return MemeState(
      selectedImage: j['selectedImage'] as String?,
      layers: [
        for (final l in (j['layers'] as List? ?? const []))
          MemeLayer.fromJson(Map<String, dynamic>.from(l as Map)),
      ],
      fit: BgFit.parse(j['bgSize'] as String?),
      bgColor: _hex(j['bgColor'], const Color(0xFF7E3E3E)),
      bgX: _d(pos['x'], 50),
      bgY: _d(pos['y'], 50),
      corner: CornerStyle.values.firstWhere(
        (c) => c.name == j['cornerStyle'],
        orElse: () => CornerStyle.squircle,
      ),
      cornerSize: _d(j['cornerSize'], 24),
      flipH: (j['flipH'] as bool?) ?? false,
      flipV: (j['flipV'] as bool?) ?? false,
      aspect: MemeAspect.parse(j['aspectRatio'] as String?),
      bgZoom: _d(j['bgZoom'], 1),
      bgLocked: (j['bgLocked'] as bool?) ?? false,
    );
  }
}

class MemeTemplate {
  const MemeTemplate(this.id, this.title, this.thumbnail, this.payload);
  final int id;
  final String title, thumbnail, payload;

  factory MemeTemplate.fromRow(Map<String, Object?> r) => MemeTemplate(
    r['id'] as int,
    (r['title'] as String?) ?? '',
    (r['thumbnail'] as String?) ?? '',
    (r['payload'] as String?) ?? '{}',
  );
}
