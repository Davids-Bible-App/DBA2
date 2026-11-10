import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'verse_grouping.dart';

/// Card for a run of consecutive verses. Long-press or double-tap a verse to
/// multi-select; the selection bar offers delete / ungroup / select-all.
class GroupedVerseCard extends StatefulWidget {
  const GroupedVerseCard({
    super.key,
    required this.group,
    required this.onJump,
    required this.onDelete,
    required this.onSaveNote,
    this.dragHandle,
    this.onUngroup,
  });

  final List<GalleryEntry> group;
  final void Function(GalleryEntry first) onJump;
  final Future<void> Function(String type, List<int> ids) onDelete;
  final Future<void> Function(int id, String note) onSaveNote;

  /// Pass a ReorderableDragStartListener to make the card draggable.
  final Widget? dragHandle;
  final Future<void> Function(List<int> ids)? onUngroup;

  @override
  State<GroupedVerseCard> createState() => _GroupedVerseCardState();
}

class _GroupedVerseCardState extends State<GroupedVerseCard> {
  final _selected = <int>{};

  void _toggle(int id) => setState(
    () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
  );

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ids = _selected.toList();
    final type = widget.group.firstWhere((v) => v.id == ids.first).entryType;
    await widget.onDelete(type, ids);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _ungroup() async {
    await widget.onUngroup?.call(_selected.toList());
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final g = widget.group;

    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.dragHandle != null) widget.dragHandle!,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selected.isNotEmpty) _selectionBar(cs),
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: refLabel(g),
                                  style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(
                                  text: '  (${g.first.abbr})',
                                  style: tt.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => widget.onJump(g.first),
                          child: const Text('Go to Verse ↣'),
                        ),
                      ],
                    ),
                    for (final e in g) _verseRow(e, cs, tt),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionBar(ColorScheme cs) {
    final g = widget.group;
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.outlineVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          TextButton.icon(
            onPressed: _deleteSelected,
            style: TextButton.styleFrom(foregroundColor: cs.error),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text('(${_selected.length})'),
          ),
          if (g.length > 1 &&
              widget.onUngroup != null &&
              _selected.length != g.length)
            TextButton.icon(
              onPressed: _ungroup,
              icon: const Icon(Icons.call_split, size: 18),
              label: Text('(${_selected.length})'),
            ),
          if (g.length > 1)
            TextButton.icon(
              onPressed: () =>
                  setState(() => _selected.addAll(g.map((v) => v.id))),
              icon: const Icon(Icons.select_all, size: 18),
              label: const Text('(ALL)'),
            ),
          TextButton(
            onPressed: () => setState(_selected.clear),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _verseRow(GalleryEntry e, ColorScheme cs, TextTheme tt) {
    final selected = _selected.contains(e.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => _toggle(e.id),
            onDoubleTap: () => _toggle(e.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? cs.errorContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: e.highlight == null
                    ? null
                    : Border(left: BorderSide(color: e.highlight!, width: 3)),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${e.verseId}. ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: e.text),
                  ],
                ),
              ),
            ),
          ),
          if (e.note != null && e.note!.isNotEmpty)
            EditableNote(
              note: e.note!,
              onSave: (v) => widget.onSaveNote(e.id, v),
              onDelete: () => widget.onDelete('note', [e.id]),
            ),
        ],
      ),
    );
  }
}

/// Tap to edit inline; saving an empty note deletes it.
class EditableNote extends StatefulWidget {
  const EditableNote({
    super.key,
    required this.note,
    required this.onSave,
    required this.onDelete,
  });
  final String note;
  final Future<void> Function(String) onSave;
  final Future<void> Function() onDelete;

  @override
  State<EditableNote> createState() => _EditableNoteState();
}

class _EditableNoteState extends State<EditableNote> {
  // Whichever note started editing last. Every other note cancels itself.
  static final ValueNotifier<Object?> _active = ValueNotifier(null);

  late final _c = TextEditingController(text: widget.note);
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _active.addListener(_onActiveChanged);
  }

  void _onActiveChanged() {
    if (_editing && _active.value != this) _cancel();
  }

  void _start() {
    _active.value = this;
    setState(() => _editing = true);
  }

  @override
  void didUpdateWidget(covariant EditableNote old) {
    super.didUpdateWidget(old);
    if (!_editing && old.note != widget.note) _c.text = widget.note;
  }

  @override
  void dispose() {
    _active.removeListener(_onActiveChanged);
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _c.text.trim();
    if (v == widget.note) return setState(() => _editing = false);
    if (v.isEmpty) {
      await widget.onDelete();
    } else {
      await widget.onSave(v);
    }
    if (mounted) setState(() => _editing = false);
  }

  void _cancel() => setState(() {
    _c.text = widget.note;
    _editing = false;
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OverlayLock(
      active: _editing, // sidebar gestures off while a note is being edited
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: cs.onInverseSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: _editing
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(
                    controller: _c,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _cancel,
                        child: const Text('Cancel'),
                      ),
                      FilledButton.tonal(
                        onPressed: _save,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              )
            : InkWell(
                onTap: _start,
                child: Text('📝 ${widget.note}'),
              ),
      ),
    );
  }
}
