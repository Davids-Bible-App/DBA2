import 'dart:math' as math;

import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:dba2/ui/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'meme_canvas.dart';
import 'meme_controller.dart';
import 'meme_controls_panel.dart';
import 'meme_image_strip.dart';
import 'meme_io.dart';
import 'meme_layers_panel.dart';
import 'meme_models.dart';
import 'meme_templates_panel.dart';
import 'meme_theme.dart';
import 'meme_widgets.dart';

class MemeMakerPage extends StatefulWidget {
  const MemeMakerPage({super.key});

  /// Slides up + fades in; reverses on close.
  /// Uses rootNavigatorKey because the sidebars have their own Navigators.
  static Future<void> open() => rootNavigatorKey.currentState!.push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => const MemeMakerPage(),
      transitionsBuilder: (_, anim, _, child) {
        final curve = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
    ),
  );

  @override
  State<MemeMakerPage> createState() => _MemeMakerPageState();
}

class _MemeMakerPageState extends State<MemeMakerPage> {
  late final MemeMakerController c = context.read<MemeMakerController>();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    c.init();
  }

  @override
  void dispose() {
    c.flush();
    super.dispose();
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await c.exportBytes(); // renders from the ORIGINAL image
      final ok = await saveBytesAs(bytes, c.exportFileName);
      if (ok && mounted) {
        showToast('Saved');
      }
    } catch (e) {
      if (mounted) await memeInfo(context, 'Export failed', '$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MemeThemeScope(
      child: Builder(
        builder: (context) {
          final t = MemeTheme.of(context);
          return OverlayLock(
            active: true, // stops sidebar swipe gestures bleeding through
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                    c.undo,
                const SingleActivator(LogicalKeyboardKey.keyY, control: true):
                    c.redo,
                const SingleActivator(
                  LogicalKeyboardKey.keyZ,
                  control: true,
                  shift: true,
                ): c.redo,
              },
              child: Focus(
                autofocus: true,
                child: Scaffold(
                  backgroundColor: t.page,
                  appBar: AppBar(
                    backgroundColor: t.panel,
                    foregroundColor: t.text,
                    title: Text(
                      'Meme Maker',
                      style: t.header.copyWith(fontSize: 18),
                    ),
                    actions: [
                      ListenableBuilder(
                        listenable: c,
                        builder: (_, _) => Row(
                          children: [
                            IconButton(
                              tooltip: 'Undo (Ctrl+Z)',
                              onPressed: c.canUndo ? c.undo : null,
                              icon: const Icon(Icons.undo),
                            ),
                            IconButton(
                              tooltip: 'Redo (Ctrl+Y)',
                              onPressed: c.canRedo ? c.redo : null,
                              icon: const Icon(Icons.redo),
                            ),
                          ],
                        ),
                      ),
                      _ExportButton(c: c, busy: _exporting, onExport: _export),
                      const SizedBox(width: 8),
                    ],
                  ),
                  body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) {
                      if (!c.ready) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return LayoutBuilder(
                        builder: (context, box) {
                          final wide = box.maxWidth > 900;
                          final canvas = MemeCanvas(controller: c);
                          final controls = _Controls(c: c);
                          final pad = EdgeInsets.all(t.gap);
                          if (wide) {
                            return Padding(
                              padding: pad,
                              child: Row(
                                children: [
                                  Expanded(child: canvas),
                                  SizedBox(width: t.gap),
                                  SizedBox(width: 440, child: controls),
                                ],
                              ),
                            );
                          }
                          final h = (box.maxHeight * 0.38).clamp(200.0, 480.0);
                          return Padding(
                            padding: pad,
                            child: Column(
                              children: [
                                SizedBox(
                                  height: math.min(h, box.maxHeight * 0.6),
                                  child: canvas,
                                ),
                                SizedBox(height: t.gap),
                                Expanded(child: controls),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.c});
  final MemeMakerController c;
  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: MemeImageStrip(c: c)),
        SliverToBoxAdapter(child: MemeLayersPanel(c: c)),
        SliverToBoxAdapter(child: MemeControlsPanel(c: c)),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: t.gap),
            child: Align(
              alignment: Alignment.centerLeft,
              child: MemeButton(
                'Reset images',
                danger: true,
                onPressed: () async {
                  if (await memeConfirm(
                    context,
                    title: 'Fresh start?',
                    message: 'Removes uploaded images and restores the preset images. Templates are kept.',
                    ok: 'Reset presets',
                  )) {
                    await c.resetImages();
                  }
                },
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: t.gap),
            child: Text('Templates', style: t.header),
          ),
        ),
        MemeTemplatesSliver(c: c),
      ],
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.c,
    required this.busy,
    required this.onExport,
  });
  final MemeMakerController c;
  final bool busy;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final t = MemeTheme.of(context);
      final size = c.exportSize == 0 ? 'Original' : '${c.exportSize}px';
      final fmt = c.exportFormat == ExportFormat.png ? 'PNG' : 'JPEG';
      return Material(
        color: t.exportBg,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main part: exports
            InkWell(
              onTap: busy ? null : onExport,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    busy
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.exportFg,
                            ),
                          )
                        : Icon(Icons.ios_share, size: 18, color: t.exportFg),
                    const SizedBox(width: 8),
                    Text('$fmt · $size', style: TextStyle(color: t.exportFg)),
                  ],
                ),
              ),
            ),
            // Divider
            Container(
              width: 1,
              height: 24,
              color: t.exportFg.withValues(alpha: 0.35),
            ),
            // Arrow part: options
            PopupMenuButton<Object>(
              tooltip: 'Export options',
              icon: Icon(Icons.arrow_drop_down, color: t.exportFg),
              onSelected: (v) {
                if (v is ExportFormat) c.exportFormat = v;
                if (v is int) c.exportSize = v;
                c.flush();
                c.endGesture(); // just a notify
              },
              itemBuilder: (_) => [
                const PopupMenuItem(enabled: false, child: Text('Format')),
                for (final f in ExportFormat.values)
                  CheckedPopupMenuItem<Object>(
                    value: f,
                    checked: c.exportFormat == f,
                    child: Text(f == ExportFormat.png ? 'PNG' : 'JPEG'),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  enabled: false,
                  child: Text('Size (long edge)'),
                ),
                for (final s in [350, 700, 1200, 2400, 0])
                  CheckedPopupMenuItem<Object>(
                    value: s,
                    checked: c.exportSize == s,
                    child: Text(s == 0 ? 'Original image size' : '$s px'),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
