import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'meme_controller.dart';
import 'meme_models.dart';
import 'meme_renderer.dart';
import 'meme_theme.dart';

/// Repaints ONLY when the controller's canvasRev changes.
class _MemePainter extends CustomPainter {
  _MemePainter(this.c) : super(repaint: c.canvasRev);
  final MemeMakerController c;

  @override
  void paint(Canvas canvas, Size size) => MemeRenderer.paint(
    canvas,
    size,
    c.state,
    bg: c.previewImage,
    cache: c.textCache,
    selectedId: c.showSelection ? c.selectedId : null,
  );

  @override
  bool shouldRepaint(_MemePainter old) => old.c != c;
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter(this.a, this.b);
  final Color a, b;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = a);
    final p = Paint()..color = b;
    const s = 16.0;
    for (var y = 0; y * s < size.height; y++) {
      for (var x = (y % 2); x * s < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * s, y * s, s, s), p);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter o) => o.a != a || o.b != b;
}

/// Gestures:  drag text = move · pinch / mouse-wheel on selected text = resize
///            drag empty area = pan the background image
class MemeCanvas extends StatefulWidget {
  const MemeCanvas({super.key, required this.controller});
  final MemeMakerController controller;
  @override
  State<MemeCanvas> createState() => _MemeCanvasState();
}

class _MemeCanvasState extends State<MemeCanvas> {
  MemeMakerController get c => widget.controller;
  Size _size = Size.zero;
  String? _target; // layer id, or kBackgroundId
  Offset _startFocal = Offset.zero;
  double _startX = 0,
      _startY = 0,
      _startScale = 1,
      _startRot = 0,
      _startZoom = 1;

  void _onStart(ScaleStartDetails d) {
    final hit = MemeRenderer.hitTest(
      d.localFocalPoint,
      _size,
      c.state,
      c.textCache,
    );
    final locked = c.state.bgLocked;
    _target = hit ?? (locked ? null : kBackgroundId); // locked: nothing to drag
    c.select(hit ?? kBackgroundId);
    _startFocal = d.localFocalPoint;
    if (hit != null) {
      final l = c.selectedLayer!;
      _startX = l.x;
      _startY = l.y;
      _startScale = l.scale;
      _startRot = l.rotation;
    } else if (!locked) {
      _startX = c.state.bgX;
      _startY = c.state.bgY;
      _startZoom = c.state.bgZoom;
    }
  }

  void _onUpdate(ScaleUpdateDetails d) {
    final t = _target;
    if (t == null || _size.isEmpty) return;
    var dx = (d.localFocalPoint.dx - _startFocal.dx) / _size.width * 100;
    var dy = (d.localFocalPoint.dy - _startFocal.dy) / _size.height * 100;
    if (t == kBackgroundId) {
      final s = c.state;
      if (s.fit == BgFit.cover) {
        dx = -dx;
        dy = -dy;
      } // image follows finger
      if (s.flipH) dx = -dx;
      if (s.flipV) dy = -dy;
      dx /= s.bgZoom; // so the image keeps following the finger when zoomed
      dy /= s.bgZoom;
      c.dragBackground(_startX + dx, _startY + dy);
      if (d.pointerCount >= 2) c.setBgZoom(_startZoom * d.scale, panel: false);
    } else {
      c.dragLayer(t, _startX + dx, _startY + dy);
      if (d.pointerCount >= 2) {
        c.scaleLayer(t, _startScale * d.scale, panel: false);
        c.rotateLayer(t, _startRot + d.rotation * 180 / math.pi, panel: false);
      }
    }
  }

  void _onWheel(PointerSignalEvent e) {
    final l = c.selectedLayer;
    if (e is! PointerScrollEvent) return;
    final f = e.scrollDelta.dy < 0 ? 1.06 : 0.94;
    if (l != null && !l.locked) {
      c.scaleLayer(l.id, l.scale * f);
    } else if (c.backgroundSelected && !c.state.bgLocked) {
      c.setBgZoom(c.state.bgZoom * f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.radiusM),
        color: t.panel,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _CheckerPainter(t.checkerA, t.checkerB),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Center(
              // Rebuilds only when aspect ratio changes
              child: ListenableBuilder(
                listenable: c,
                builder: (_, _) => AspectRatio(
                  aspectRatio: c.aspectValue,
                  child: LayoutBuilder(
                    builder: (_, box) {
                      _size = box.biggest;
                      return Listener(
                        onPointerSignal: _onWheel,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: _onStart,
                          onScaleUpdate: _onUpdate,
                          onScaleEnd: (_) => c.endGesture(),
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _MemePainter(c),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: c,
            builder: (_, _) => c.previewLoading
                ? const Positioned(
                    top: 8,
                    right: 8,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
