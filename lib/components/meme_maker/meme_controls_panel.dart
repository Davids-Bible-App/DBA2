import 'package:flutter/material.dart';

import 'meme_controller.dart';
import 'meme_models.dart';
import 'meme_theme.dart';
import 'meme_widgets.dart';

enum _Tab { font, flow, shadow, block }

/// Shows text controls for the selected text layer, or frame / image controls
/// when the background is selected.
class MemeControlsPanel extends StatelessWidget {
  const MemeControlsPanel({super.key, required this.c});
  final MemeMakerController c;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (_, _) {
      final l = c.selectedLayer;
      if (l != null) return _TextControls(c: c, l: l);
      if (c.backgroundSelected) return _BackgroundControls(c: c);
      return const SizedBox.shrink();
    },
  );
}

// ───────────────────────── text ─────────────────────────

class _TextControls extends StatefulWidget {
  const _TextControls({required this.c, required this.l});
  final MemeMakerController c;
  final MemeLayer l;
  @override
  State<_TextControls> createState() => _TextControlsState();
}

class _TextControlsState extends State<_TextControls> {
  _Tab _tab = _Tab.font;
  late final _text = TextEditingController(text: widget.l.content);
  String _id = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, l = widget.l, t = MemeTheme.of(context);
    // keep the text box in sync after layer switch / undo
    if (_text.text != l.content) {
      _text.value = TextEditingValue(
        text: l.content,
        selection: TextSelection.collapsed(
          offset: _id == l.id ? l.content.length : 0,
        ),
      );
    }
    _id = l.id;
    void up(MemeLayer Function(MemeLayer) f, [String? key]) =>
        c.updateLayer(l.id, f, key: key == null ? null : '$key:${l.id}');
    final font = fontByKey(l.fontFamily);

    return MemePanel(
      title: 'Text',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Your text',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.radiusS),
              ),
            ),
            onChanged: (v) => up((x) => x.copyWith(content: v), 'text'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (tab, name) in [
                (_Tab.font, 'FONT'),
                (_Tab.flow, 'FLOW'),
                (_Tab.shadow, 'SHADOW'),
                (_Tab.block, 'BLOCK'),
              ])
                MemeButton(
                  name,
                  active: _tab == tab,
                  onPressed: () => setState(() => _tab = tab),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_tab == _Tab.font) ...[
            Row(
              children: [
                Expanded(
                  // Menu items are only built (and their fonts downloaded) when
                  // the menu is opened.
                  child: PopupMenuButton<String>(
                    tooltip: 'Choose font',
                    onSelected: (v) => c.setFont(l.id, v),
                    itemBuilder: (_) => [
                      for (final f in kMemeFonts)
                        PopupMenuItem(
                          value: f.family,
                          child: Text(
                            f.label,
                            style: f.style.copyWith(fontSize: 16),
                          ),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: t.border),
                        borderRadius: BorderRadius.circular(t.radiusS),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              font.label,
                              overflow: TextOverflow.ellipsis,
                              style: font.style.copyWith(
                                fontSize: 16,
                                color: t.text,
                              ),
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: t.textDim),
                        ],
                      ),
                    ),
                  ),
                ),
                if (font.hasBold) ...[
                  MemeButton(
                    'B',
                    active: l.bold,
                    onPressed: () => up((x) => x.copyWith(bold: !x.bold)),
                  ),
                  const SizedBox(width: 6),
                  MemeButton(
                    'I',
                    active: l.italic,
                    onPressed: () => up((x) => x.copyWith(italic: !x.italic)),
                  ),
                ],
              ],
            ),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MemeColorSwatch(
                  label: 'Fill',
                  color: l.color,
                  onChanged: (v) => up((x) => x.copyWith(color: v), 'fill'),
                ),
                MemeIconButton(
                  Icons.swap_horiz,
                  tooltip: 'Swap fill & outline',
                  onPressed: () => up(
                    (x) =>
                        x.copyWith(color: x.strokeColor, strokeColor: x.color),
                  ),
                ),
                MemeColorSwatch(
                  label: 'Outline',
                  color: l.strokeColor,
                  onChanged: (v) =>
                      up((x) => x.copyWith(strokeColor: v), 'stroke'),
                ),
              ],
            ),
            MemeSliderRow(
              label: 'Size',
              value: l.scale,
              min: 0.2,
              max: 2,
              decimals: 2,
              onChanged: (v) => c.scaleLayer(l.id, v),
              onChangeEnd: c.endGesture,
            ),
            MemeSliderRow(
              label: 'Outline width',
              unit: 'px',
              value: l.strokeWidth,
              min: 0,
              max: 3,
              decimals: 2,
              onChanged: (v) => up((x) => x.copyWith(strokeWidth: v), 'sw'),
              onChangeEnd: c.endGesture,
            ),
          ],
          if (_tab == _Tab.flow) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MemeButton(
                  'Text wrap',
                  active: l.textWrap,
                  onPressed: () => up((x) => x.copyWith(textWrap: !x.textWrap)),
                ),
                MemeButton(
                  'Centre X',
                  icon: Icons.align_horizontal_center,
                  onPressed: () => up((x) => x.copyWith(x: 50)),
                ),
                MemeButton(
                  'Centre Y',
                  icon: Icons.align_vertical_center,
                  onPressed: () => up((x) => x.copyWith(y: 50)),
                ),
              ],
            ),
            MemeSliderRow(
              label: 'Rotation',
              unit: '°',
              decimals: 0,
              value: l.rotation,
              min: -180,
              max: 180,
              onReset: () => c.rotateLayer(l.id, 0),
              onChanged: (v) => c.rotateLayer(l.id, v),
              onChangeEnd: c.endGesture,
            ),
            if (l.textWrap)
              MemeSliderRow(
                label: 'Wrap width',
                unit: 'px',
                decimals: 0,
                value: l.wrapWidth,
                min: 100,
                max: 600,
                onChanged: (v) => up((x) => x.copyWith(wrapWidth: v), 'ww'),
                onChangeEnd: c.endGesture,
              ),
            MemeSliderRow(
              label: 'Line height',
              decimals: 2,
              value: l.lineHeight,
              min: 0.8,
              max: 2,
              onReset: () => up((x) => x.copyWith(lineHeight: 1.2)),
              onChanged: (v) => up((x) => x.copyWith(lineHeight: v), 'lh'),
              onChangeEnd: c.endGesture,
            ),
            MemeSliderRow(
              label: 'Letter spacing',
              unit: 'px',
              value: l.letterSpacing,
              min: -2,
              max: 8,
              onReset: () => up((x) => x.copyWith(letterSpacing: 0)),
              onChanged: (v) => up((x) => x.copyWith(letterSpacing: v), 'ls'),
              onChangeEnd: c.endGesture,
            ),
          ],
          if (_tab == _Tab.shadow) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: MemeButton(
                'Text shadow',
                active: l.shadow,
                onPressed: () => up((x) => x.copyWith(shadow: !x.shadow)),
              ),
            ),
            if (l.shadow) ...[
              MemeSliderRow(
                label: 'Shadow X',
                unit: 'px',
                decimals: 0,
                value: l.shadowX,
                min: -20,
                max: 20,
                onChanged: (v) => up((x) => x.copyWith(shadowX: v), 'sx'),
                onChangeEnd: c.endGesture,
              ),
              MemeSliderRow(
                label: 'Shadow Y',
                unit: 'px',
                decimals: 0,
                value: l.shadowY,
                min: -20,
                max: 20,
                onChanged: (v) => up((x) => x.copyWith(shadowY: v), 'sy'),
                onChangeEnd: c.endGesture,
              ),
              MemeSliderRow(
                label: 'Blur',
                unit: 'px',
                value: l.shadowBlur,
                min: 0,
                max: 12,
                onChanged: (v) => up((x) => x.copyWith(shadowBlur: v), 'sb'),
                onChangeEnd: c.endGesture,
              ),
              MemeSliderRow(
                label: 'Intensity',
                decimals: 2,
                value: l.shadowIntensity,
                min: 0,
                max: 1,
                onChanged: (v) =>
                    up((x) => x.copyWith(shadowIntensity: v), 'si'),
                onChangeEnd: c.endGesture,
              ),
            ],
          ],
          if (_tab == _Tab.block) ...[
            Text(
              'A dark box behind the text, for readability.',
              style: t.label,
            ),
            MemeSliderRow(
              label: 'Darkness',
              decimals: 2,
              value: l.textBlockIntensity,
              min: 0,
              max: 1,
              onChanged: (v) =>
                  up((x) => x.copyWith(textBlockIntensity: v), 'bi'),
              onChangeEnd: c.endGesture,
            ),
            MemeSliderRow(
              label: 'Extra width',
              unit: 'px',
              decimals: 0,
              value: l.textBlockWidth,
              min: 0,
              max: 120,
              onChanged: (v) => up((x) => x.copyWith(textBlockWidth: v), 'bw'),
              onChangeEnd: c.endGesture,
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── background ─────────────────────────

class _BackgroundControls extends StatelessWidget {
  const _BackgroundControls({required this.c});
  final MemeMakerController c;

  @override
  Widget build(BuildContext context) {
    final s = c.state, t = MemeTheme.of(context);
    Widget group(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.header),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
    return MemePanel(
      title: 'Background',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MemeColorSwatch(
                label: 'Background colour',
                color: s.bgColor,
                onChanged: c.setBgColor,
              ),
              MemeButton(
                s.bgLocked ? 'Image locked' : 'Lock image',
                icon: s.bgLocked ? Icons.lock : Icons.lock_open,
                active: s.bgLocked,
                onPressed: c.toggleBgLock,
              ),
            ],
          ),
          const SizedBox(height: 10),
          group(
            'Image display',
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MemeButton(
                  'Contain (show all)',
                  active: s.fit == BgFit.contain,
                  onPressed: () => c.setFit(BgFit.contain),
                ),
                MemeButton(
                  'Cover (fill)',
                  active: s.fit == BgFit.cover,
                  onPressed: () => c.setFit(BgFit.cover),
                ),
                MemeButton(
                  'Stretch',
                  active: s.fit == BgFit.stretch,
                  onPressed: () => c.setFit(BgFit.stretch),
                ),
              ],
            ),
          ),
          if (s.selectedImage != null)
            group(
              'Zoom',
              MemeSliderRow(
                label: 'Image zoom',
                unit: '×',
                decimals: 2,
                value: s.bgZoom,
                min: 0.5,
                max: 4,
                onReset: s.bgLocked ? null : () => c.setBgZoom(1),
                onChanged: s.bgLocked ? null : (v) => c.setBgZoom(v),
                onChangeEnd: c.endGesture,
              ),
            ),
          group(
            'Frame edge',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (v, n) in [
                      (CornerStyle.none, 'Square'),
                      (CornerStyle.round, 'Round'),
                      (CornerStyle.bevel, 'Bevel'),
                      (CornerStyle.squircle, 'Squircle'),
                    ])
                      MemeButton(
                        n,
                        active: s.corner == v,
                        onPressed: () => c.setCorner(v),
                      ),
                  ],
                ),
                if (s.corner == CornerStyle.round ||
                    s.corner == CornerStyle.bevel)
                  MemeSliderRow(
                    label: 'Corner size',
                    unit: 'px',
                    decimals: 0,
                    value: s.cornerSize,
                    min: 0,
                    max: 100,
                    onChanged: c.setCornerSize,
                    onChangeEnd: c.endGesture,
                  ),
              ],
            ),
          ),
          group(
            'Canvas format',
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (v, n) in [
                  (MemeAspect.square, '1:1 Square'),
                  (MemeAspect.portrait, '4:5 Insta'),
                  (MemeAspect.wide, '16:9 X/YT'),
                  (MemeAspect.original, 'Original'),
                ])
                  MemeButton(
                    n,
                    active: s.aspect == v,
                    onPressed:
                        (v == MemeAspect.original && s.selectedImage == null)
                        ? null
                        : () => c.setAspect(v),
                  ),
              ],
            ),
          ),
          group(
            'Flip image',
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MemeButton(
                  'Horizontal ↔',
                  active: s.flipH,
                  onPressed: s.selectedImage == null ? null : c.setFlipH,
                ),
                MemeButton(
                  'Vertical ↕',
                  active: s.flipV,
                  onPressed: s.selectedImage == null ? null : c.setFlipV,
                ),
              ],
            ),
          ),
          Text(
            'Tip: drag the canvas to move the image; pinch to zoom. Lock it to stop accidents.',
            style: t.label,
          ),
        ],
      ),
    );
  }
}
