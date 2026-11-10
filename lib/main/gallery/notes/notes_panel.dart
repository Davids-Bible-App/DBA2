import 'package:flutter/material.dart';

import '../gallery_controller.dart';
import '../models.dart';
import '../verse_grouping.dart';
import '../common.dart';
import '../grouped_verse_card.dart';

/// Notes tab: searchable, grouped verse cards (no drag reordering).
class NotesPanel extends StatefulWidget {
  const NotesPanel({
    super.key,
    required this.controller,
    required this.onJumpTo,
  });
  final GalleryController controller;
  final void Function(GalleryEntry verse) onJumpTo;

  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  final _query = TextEditingController();
  GalleryController get c => widget.controller;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, _query]),
    builder: (context, _) {
      final q = _query.text.trim().toLowerCase();
      final filtered = c.notes
          .where((e) => (e.note ?? '').toLowerCase().contains(q))
          .toList();
      final groups = groupConsecutive(filtered);

      return Column(
        children: [
          GallerySearchField(controller: _query, hint: 'Search notes...'),
          Expanded(
            child: groups.isEmpty
                ? const Center(child: Text('No Notes Yet'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => GroupedVerseCard(
                      key: ValueKey(groups[i].first.id),
                      group: groups[i],
                      onJump: widget.onJumpTo,
                      onDelete: (type, ids) =>
                          deleteWithConfirm(context, c, type, ids),
                      onSaveNote: c.saveNote,
                    ),
                  ),
          ),
        ],
      );
    },
  );
}
