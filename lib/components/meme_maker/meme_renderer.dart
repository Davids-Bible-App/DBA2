import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

import 'meme_models.dart';
import 'meme_storage.dart';

/// Text that has been measured once. Reused every frame until it changes.
class LaidText {
  LaidText(this.fill, this.stroke, this.box);
  final TextPainter fill;
  final TextPainter? stroke;
  final Size box; // text + block padding
  void dispose() {
    fill.dispose();
    stroke?.dispose();
  }
}

class MemeTextCache {
  final _m = <String, (int, double, LaidText)>{};

  LaidText get(MemeLayer l, double k) {
    final e = _m[l.id];
    final sig = l.layoutSig;
    if (e != null && e.$1 == sig && e.$2 == k) return e.$3;
    e?.$3.dispose();
    final laid = MemeRenderer.layout(l, k);
    _m[l.id] = (sig, k, laid);
    return laid;
  }

  void clear() {
    for (final e in _m.values) {
      e.$3.dispose();
    }
    _m.clear();
  }
}

/// One drawing routine used for the on-screen canvas AND for export, so what
/// you see is exactly what you get. Everything is in "design units" (a canvas
/// 400 wide) multiplied by k, so it scales to any export resolution.
class MemeRenderer {
  static const designWidth = 400.0;

  static LaidText layout(MemeLayer l, double k) {
    final font = fontByKey(l.fontFamily);
    final fancy = font.hasBold;
    final base = font.style.copyWith(
      fontSize: math.max(5, 28 * l.scale) * k,
      fontWeight: l.bold && fancy ? FontWeight.w700 : FontWeight.w400,
      fontStyle: l.italic && fancy ? FontStyle.italic : FontStyle.normal,
      height: l.lineHeight,
      letterSpacing: l.letterSpacing * k,
    );

    TextPainter make(TextStyle s) {
      final tp = TextPainter(
        text: TextSpan(text: l.content.isEmpty ? ' ' : l.content, style: s),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      if (l.textWrap) {
        final w = l.wrapWidth * k;
        tp.layout(minWidth: w, maxWidth: w);
      } else {
        tp.layout();
      }
      return tp;
    }

    final fill = make(
      base.copyWith(
        color: l.color,
        shadows: l.shadow
            ? [
                Shadow(
                  color: Colors.black.withValues(alpha: l.shadowIntensity),
                  offset: Offset(l.shadowX * k, l.shadowY * k),
                  blurRadius: l.shadowBlur * k,
                ),
              ]
            : null,
      ),
    );
    final stroke = l.strokeWidth > 0
        ? make(
            base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = l.strokeWidth * k
                ..strokeJoin = StrokeJoin.round
                ..color = l.strokeColor,
            ),
          )
        : null;
    final padX = l.textBlockWidth * k, padY = 10 * k;
    return LaidText(
      fill,
      stroke,
      Size(fill.width + 2 * padX, fill.height + 2 * padY),
    );
  }

  static Path framePath(Size s, CornerStyle c, double cornerPx) {
    final r = Offset.zero & s;
    final cs = math.min(cornerPx, s.shortestSide / 2);
    switch (c) {
      case CornerStyle.none:
        return Path()..addRect(r);
      case CornerStyle.round:
        return Path()..addRRect(RRect.fromRectXY(r, cs, cs));
      case CornerStyle.bevel:
        return Path()
          ..moveTo(cs, 0)
          ..lineTo(s.width - cs, 0)
          ..lineTo(s.width, cs)
          ..lineTo(s.width, s.height - cs)
          ..lineTo(s.width - cs, s.height)
          ..lineTo(cs, s.height)
          ..lineTo(0, s.height - cs)
          ..lineTo(0, cs)
          ..close();
      case CornerStyle.squircle:
        final w = s.width / 200, h = s.height / 200; // same curve as v1's SVG
        return Path()
          ..moveTo(0, 100 * h)
          ..cubicTo(0, 15 * h, 15 * w, 0, 100 * w, 0)
          ..cubicTo(185 * w, 0, 200 * w, 15 * h, 200 * w, 100 * h)
          ..cubicTo(200 * w, 185 * h, 185 * w, 200 * h, 100 * w, 200 * h)
          ..cubicTo(15 * w, 200 * h, 0, 185 * h, 0, 100 * h)
          ..close();
    }
  }

  static void paint(
    Canvas canvas,
    Size size,
    MemeState s, {
    ui.Image? bg,
    MemeTextCache? cache,
    String? selectedId, // on-screen only; never passed when exporting
    Color? backdrop, // for formats without transparency (JPEG)
    FilterQuality quality = FilterQuality.medium,
  }) {
    final k = size.width / designWidth;
    final temp = cache == null ? MemeTextCache() : null;
    final tc = cache ?? temp!;
    final rect = Offset.zero & size;

    if (backdrop != null) canvas.drawRect(rect, Paint()..color = backdrop);
    canvas.save();
    canvas.clipPath(
      framePath(size, s.corner, s.cornerSize * k),
      doAntiAlias: true,
    );
    canvas.drawRect(rect, Paint()..color = s.bgColor);

    if (bg != null) {
      canvas.save();
      canvas.translate(size.width / 2, size.height / 2);
      canvas.scale(s.flipH ? -1 : 1, s.flipV ? -1 : 1);
      canvas.scale(s.bgZoom);
      canvas.translate(-size.width / 2, -size.height / 2);
      paintImage(
        canvas: canvas,
        rect: rect,
        image: bg,
        fit: switch (s.fit) {
          BgFit.cover => BoxFit.cover,
          BgFit.contain => BoxFit.contain,
          BgFit.stretch => BoxFit.fill,
        },
        alignment: Alignment(s.bgX / 50 - 1, s.bgY / 50 - 1),
        filterQuality: quality,
      );
      canvas.restore();
    }

    for (final l in s.layers) {
      if (!l.visible) continue;
      final laid = tc.get(l, k);
      canvas.save();
      canvas.translate(l.x / 100 * size.width, l.y / 100 * size.height);
      canvas.rotate(l.rotation * math.pi / 180);
      if (l.textBlockIntensity > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: laid.box.width,
              height: laid.box.height,
            ),
            Radius.circular(8 * k),
          ),
          Paint()..color = Colors.black.withValues(alpha: l.textBlockIntensity),
        );
      }
      final off = Offset(-laid.fill.width / 2, -laid.fill.height / 2);
      laid.fill.paint(canvas, off);
      laid.stroke?.paint(canvas, off);
      canvas.restore();
    }
    canvas.restore();

    if (selectedId != null && selectedId != kBackgroundId) {
      for (final l in s.layers) {
        if (l.id != selectedId || !l.visible) continue;
        final laid = tc.get(l, k);
        canvas.save();
        canvas.translate(l.x / 100 * size.width, l.y / 100 * size.height);
        canvas.rotate(l.rotation * math.pi / 180);
        final r = Rect.fromCenter(
          center: Offset.zero,
          width: laid.box.width,
          height: laid.box.height,
        ).inflate(3);
        canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Colors.black54,
        );
        canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.white,
        );
        canvas.restore();
      }
    }
    temp?.clear();
  }

  /// Topmost visible, unlocked layer under [p]. null = background.
  static String? hitTest(
    Offset p,
    Size size,
    MemeState s,
    MemeTextCache cache,
  ) {
    final k = size.width / designWidth;
    for (var i = s.layers.length - 1; i >= 0; i--) {
      final l = s.layers[i];
      if (!l.visible || l.locked) continue;
      final laid = cache.get(l, k);
      final centre = Offset(l.x / 100 * size.width, l.y / 100 * size.height);
      final a = -l.rotation * math.pi / 180; // undo the layer's rotation
      final d = p - centre;
      final local = Offset(
        d.dx * math.cos(a) - d.dy * math.sin(a),
        d.dx * math.sin(a) + d.dy * math.cos(a),
      );
      final r = Rect.fromCenter(
        center: Offset.zero,
        width: laid.box.width,
        height: laid.box.height,
      ).inflate(6);
      if (r.contains(local)) return l.id;
    }
    return null;
  }
}

/// Renders the design at any resolution from the ORIGINAL image file.
class MemeExporter {
  /// [maxDim] = long edge in px. 0 = "Original" (image's own size, max 4096).
  static Future<Uint8List> render(
    MemeState s,
    MemeStorage storage, {
    required int maxDim,
    required ExportFormat format,
  }) async {
    await GoogleFonts.pendingFonts(); // make sure web fonts are ready
    final src = s.selectedImage;
    ui.Image? bg;
    if (src != null) {
      bg = await storage.decode(
        src,
        maxDim: maxDim == 0 ? 4096 : math.min(4096, maxDim * 2),
      );
    }
    final ratio = s.aspect.ratio ?? (bg != null ? bg.width / bg.height : 1.0);
    final long = maxDim > 0
        ? maxDim
        : (bg != null ? math.max(bg.width, bg.height) : 1200);
    final w = (ratio >= 1 ? long : long * ratio).round();
    final h = (ratio >= 1 ? long / ratio : long).round();

    final rec = ui.PictureRecorder();
    MemeRenderer.paint(
      Canvas(rec),
      Size(w.toDouble(), h.toDouble()),
      s,
      bg: bg,
      quality: FilterQuality.high,
      backdrop: format == ExportFormat.jpeg ? Colors.white : null,
    );
    final pic = rec.endRecording();
    final image = await pic.toImage(w, h);
    pic.dispose();
    bg?.dispose();

    try {
      if (format == ExportFormat.png) {
        final d = await image.toByteData(format: ui.ImageByteFormat.png);
        return d!.buffer.asUint8List();
      }
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final handoff = TransferableTypedData.fromList([
        raw!.buffer.asUint8List(),
      ]);
      // JPEG encoding is slow: do it off the UI thread.
      return await Isolate.run(() {
        final bytes = handoff.materialize().asUint8List();
        final im = img.Image.fromBytes(
          width: w,
          height: h,
          bytes: bytes.buffer,
          numChannels: 4,
        );
        return Uint8List.fromList(img.encodeJpg(im, quality: 95));
      });
    } finally {
      image.dispose();
    }
  }
}
