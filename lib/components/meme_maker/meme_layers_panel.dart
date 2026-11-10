import 'package:dba2/components/meme_maker/meme_image_strip.dart';
import 'package:flutter/material.dart';

import 'meme_controller.dart';
import 'meme_models.dart';
import 'meme_theme.dart';
import 'meme_widgets.dart';

/// Layers, front-most at the top (like Photoshop / Canva).
///  • drag the ≡ handle to reorder   • tap a row to select it
///  • 👁 hide  • 🔒 lock (can't be moved by accident)  • ⋮ duplicate / delete
class MemeLayersPanel extends StatelessWidget {
  const MemeLayersPanel({super.key, required this.c});
  final MemeMakerController c;

  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final layers = c.state.layers;
        final n = layers.length;
        return MemePanel(
          title: 'Layers ($n)',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MemeButton(
                'Text Selection Box',
                icon: c.showSelection ? Icons.visibility : Icons.visibility_off,
                active: !c.showSelection,
                onPressed: c.toggleShowSelection,
              ),
              const SizedBox(width: 7),
              MemeButton('Text', icon: Icons.add, onPressed: c.addTextLayer),
              const SizedBox(width: 7),
              MemeButton(
                'Clear',
                onPressed: n == 0
                    ? null
                    : () async {
                        if (await memeConfirm(
                          context,
                          title: 'Remove all text layers?',
                          message: 'You can undo this.',
                          ok: 'Clear',
                        )) {
                          c.clearLayers();
                        }
                      },
              ),
            ],
          ),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: n,
                  onReorderItem: (oldD, newD) {
                    // list is shown reversed (front first)
                    c.moveLayer(n - 1 - oldD, n - 1 - newD);
                  },
                  itemBuilder: (_, i) {
                    final l = layers[n - 1 - i];
                    return _LayerRow(
                      key: ValueKey(l.id),
                      index: i,
                      layer: l,
                      c: c,
                      selected: c.selectedId == l.id,
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              InkWell(
                borderRadius: BorderRadius.circular(t.radiusS),
                onTap: () => c.select(kBackgroundId),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.backgroundSelected ? t.panelAlt : null,
                    borderRadius: BorderRadius.circular(t.radiusS),
                    border: Border.all(
                      color: c.backgroundSelected
                          ? t.accent
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Builder(
                        builder: (_) {
                          final src = c.state.selectedImage;
                          return Container(
                            width: 32,
                            height: 32,
                            clipBehavior: Clip.antiAlias, // clips the image to the rounded corners
                            decoration: BoxDecoration(
                              color: c.state.bgColor, // shows when there's no image (or while it loads)
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: t.border),
                            ),
                            child: src == null
                                ? null
                                : MemeImageStrip.thumb(c, src, width: 64),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      Text('Background', style: t.body),
                      const Spacer(),
                      MemeIconButton(
                        c.state.bgLocked ? Icons.lock : Icons.lock_open,
                        tooltip: c.state.bgLocked
                            ? 'Unlock image'
                            : 'Lock image',
                        active: c.state.bgLocked,
                        onPressed: c.toggleBgLock,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    super.key,
    required this.index,
    required this.layer,
    required this.c,
    required this.selected,
  });
  final int index;
  final MemeLayer layer;
  final MemeMakerController c;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    final text = layer.content.replaceAll('\n', ' ');
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: selected ? t.panelAlt : null,
        borderRadius: BorderRadius.circular(t.radiusS),
        border: Border.all(color: selected ? t.accent : Colors.transparent),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Icon(Icons.drag_indicator, size: 20),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => c.select(layer.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF555555),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'T',
                        style: TextStyle(
                          color: layer.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text.isEmpty ? '(empty)' : text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.body.copyWith(
                          color: layer.visible ? t.text : t.textDim,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          MemeIconButton(
            layer.visible ? Icons.visibility : Icons.visibility_off,
            tooltip: layer.visible ? 'Hide' : 'Show',
            active: !layer.visible,
            onPressed: () =>
                c.updateLayer(layer.id, (l) => l.copyWith(visible: !l.visible)),
          ),
          MemeIconButton(
            layer.locked ? Icons.lock : Icons.lock_open,
            tooltip: layer.locked ? 'Unlock' : 'Lock',
            active: layer.locked,
            onPressed: () =>
                c.updateLayer(layer.id, (l) => l.copyWith(locked: !l.locked)),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_vert, size: 20, color: t.textDim),
            onSelected: (v) => v == 'dup'
                ? c.duplicateLayer(layer.id)
                : c.deleteLayer(layer.id),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dup', child: Text('Duplicate')),
              PopupMenuItem(value: 'del', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
