import 'package:flutter/material.dart';

import 'meme_controller.dart';
import 'meme_models.dart';
import 'meme_theme.dart';
import 'meme_widgets.dart';

/// Sliver grid: only visible tiles are built.
class MemeTemplatesSliver extends StatelessWidget {
  const MemeTemplatesSliver({super.key, required this.c});
  final MemeMakerController c;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final t = MemeTheme.of(context);
      final cur = c.currentTemplateId;
      final list = c.templates;
      final extra = cur != null ? 2 : 1;
      return SliverPadding(
        padding: EdgeInsets.only(bottom: t.gap * 2),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 130,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.88,
          ),
          itemCount: list.length + extra,
          itemBuilder: (_, i) {
            if (i == 0) {
              return _ActionTile(
                icon: Icons.add,
                label: 'Save as new\ntemplate',
                color: t.textDim,
                dashed: true,
                onTap: () async {
                  final title = await memePrompt(
                    context,
                    title: 'Template title',
                    initial: 'Template',
                  );
                  if (title != null) await c.saveTemplate(title: title);
                },
              );
            }
            if (cur != null && i == 1) {
              return _ActionTile(
                icon: Icons.save,
                label: 'Update current\ntemplate',
                color: t.success,
                onTap: () => c.saveTemplate(existingId: cur),
              );
            }
            final tpl = list[i - extra];
            return _TemplateTile(c: c, tpl: tpl, current: tpl.id == cur);
          },
        ),
      );
    },
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.dashed = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool dashed;
  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radiusM),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(t.radiusM),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: t.label.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.c,
    required this.tpl,
    required this.current,
  });
  final MemeMakerController c;
  final MemeTemplate tpl;
  final bool current;
  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: InkWell(
            onTap: () => c.applyTemplate(tpl),
            borderRadius: BorderRadius.circular(t.radiusM),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.radiusM),
                      border: Border.all(
                        color: current ? t.success : t.border,
                        width: current ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    width: double.infinity,
                    child: tpl.thumbnail.isEmpty
                        ? const Icon(Icons.image_not_supported_outlined)
                        : Image.file(
                            c.storage.file(tpl.thumbnail),
                            fit: BoxFit.contain,
                            cacheWidth: 260,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_outlined),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tpl.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.label,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () async {
              if (await memeConfirm(
                context,
                title: 'Delete template?',
                message: 'Delete "${tpl.title}"?',
                ok: 'Delete',
              )) {
                await c.deleteTemplate(tpl);
              }
            },
            child: CircleAvatar(
              radius: 11,
              backgroundColor: t.danger,
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
