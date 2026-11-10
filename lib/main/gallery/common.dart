import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:flutter/material.dart';

import 'gallery_controller.dart';

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final cs = Theme.of(context).colorScheme;
  final r = await showLockedDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptDialog(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  return showLockedDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(title: title, initial: initial),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _c = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _c.text),
        child: const Text('Save'),
      ),
    ],
  );
}

/// Shared delete flow for topic verses and notes (was handleDelete).
Future<void> deleteWithConfirm(
  BuildContext context,
  GalleryController c,
  String type,
  List<int> ids,
) async {
  if (ids.isEmpty) return;
  final ok = await confirmDialog(
    context,
    title: 'Confirm Delete',
    message: ids.length > 1
        ? 'Are you sure you want to delete these ${ids.length} items?'
        : 'Are you sure you want to delete this item?',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (ok) await c.deleteEntries(type, ids);
}

// ── Search field ──────────────────────────────────────────────────────────────
class GallerySearchField extends StatelessWidget {
  const GallerySearchField({
    super.key,
    required this.controller,
    required this.hint,
  });
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: SearchBar(
          controller: controller,
          hintText: hint,
          backgroundColor: WidgetStatePropertyAll<Color?>(
            colors.tertiary,
          ),
          // backgroundColor: WidgetStateColor.transparent,
          elevation: const WidgetStatePropertyAll(0),
          constraints: const BoxConstraints(minHeight: 44),
          leading: const Icon(Icons.search, size: 20),
          trailing: [
            ListenableBuilder(
              listenable: controller,
              builder: (_, _) => controller.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: controller.clear,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── ⋮ menu ────────────────────────────────────────────────────────────────────
class TopicActions extends StatelessWidget {
  const TopicActions({
    super.key,
    this.onExport,
    this.onCopy,
    this.onRename,
    this.onResetOrder,
    this.onDelete,
  });
  final VoidCallback? onExport, onCopy, onRename, onResetOrder, onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <(String, VoidCallback, bool)>[
      if (onExport != null) ('Export To Editor', onExport!, false),
      if (onCopy != null) ('Copy To Clipboard', onCopy!, false),
      if (onRename != null) ('Rename Topic', onRename!, false),
      if (onResetOrder != null) ('Reset Order', onResetOrder!, false),
      if (onDelete != null) ('Delete Topic', onDelete!, true),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<VoidCallback>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Actions',
      onSelected: (cb) => cb(),
      itemBuilder: (_) => [
        for (final (label, cb, danger) in items)
          PopupMenuItem(
            value: cb,
            child: Text(
              label,
              style: danger ? TextStyle(color: cs.error) : null,
            ),
          ),
      ],
    );
  }
}

// ── Two-finger pinch-out (replaces the document touch listeners) ──────────────
/// Uses raw pointer events, so it never competes with scrolling/reordering.
class PinchOutDetector extends StatefulWidget {
  const PinchOutDetector({
    super.key,
    required this.child,
    required this.onPinchOut,
    this.threshold = 55,
  });
  final Widget child;
  final VoidCallback onPinchOut;
  final double threshold;
  @override
  State<PinchOutDetector> createState() => _PinchOutDetectorState();
}

class _PinchOutDetectorState extends State<PinchOutDetector> {
  final _pts = <int, Offset>{};
  double? _start;
  bool _fired = false;

  double _dist() => (_pts.values.first - _pts.values.last).distance;

  void _remove(PointerEvent e) {
    _pts.remove(e.pointer);
    _start = null;
    _fired = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (e) {
      _pts[e.pointer] = e.position;
      if (_pts.length == 2) {
        _start = _dist();
        _fired = false;
      }
    },
    onPointerMove: (e) {
      if (!_pts.containsKey(e.pointer)) return;
      _pts[e.pointer] = e.position;
      if (_pts.length == 2 &&
          _start != null &&
          !_fired &&
          _dist() - _start! > widget.threshold) {
        _fired = true;
        widget.onPinchOut();
      }
    },
    onPointerUp: _remove,
    onPointerCancel: _remove,
    child: widget.child,
  );
}
