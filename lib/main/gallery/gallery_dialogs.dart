import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:flutter/material.dart';

/// Returns the topic name to add to (existing or new), or null if cancelled.
Future<String?> showTopicDialog(
  BuildContext context, {
  required List<String> existing,
  required String refText,
}) => showLockedDialog<String>(
  context: context,
  builder: (_) => _TopicDialog(existing: existing, refText: refText),
);

/// Returns the note text, or null if cancelled.
Future<String?> showNoteDialog(
  BuildContext context, {
  required String refText,
  String initial = '',
}) => showLockedDialog<String>(
  context: context,
  builder: (_) => _NoteDialog(refText: refText, initial: initial),
);

Widget _refBox(BuildContext context, String text) {
  // final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: isDark ? Colors.black26 : Colors.black12,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
    ),
  );
}

// ── Topic ───────────────────────────────────────────────────────────────────
class _TopicDialog extends StatefulWidget {
  const _TopicDialog({required this.existing, required this.refText});
  final List<String> existing;
  final String refText;
  @override
  State<_TopicDialog> createState() => _TopicDialogState();
}

class _TopicDialogState extends State<_TopicDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _c.text.trim();
    if (t.isNotEmpty) Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = _c.text.trim();
    final lower = t.toLowerCase();
    final exact = widget.existing.any((e) => e.toLowerCase() == lower);
    final suggestions = widget.existing
        .where((e) => lower.isEmpty || e.toLowerCase().contains(lower))
        .toList();

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.label_outline),
          SizedBox(width: 8),
          Text('Add to Topic'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _refBox(context, widget.refText),
              const SizedBox(height: 12),
              TextField(
                controller: _c,
                autofocus: true,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: 'Topic name…',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 0,
                      children: [
                        for (final s in suggestions)
                          ActionChip(
                            label: Text('🏷️ $s'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              _c.value = TextEditingValue(
                                text: s,
                                selection: TextSelection.collapsed(
                                  offset: s.length,
                                ),
                              );
                              setState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (t.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 10,
                  ),
                  decoration: BoxDecoration(
                    color: exact
                        ? cs.errorContainer
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    exact
                        ? '⚠ Verses will be added to this topic'
                        : '✦ New topic will be created',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: t.isEmpty ? null : _submit,
          child: Text(exact ? 'Add' : 'Create'),
        ),
      ],
    );
  }
}

// ── Note ────────────────────────────────────────────────────────────────────
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.refText, required this.initial});
  final String refText, initial;
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.note_add_outlined),
          SizedBox(width: 8),
          Text(widget.initial.isEmpty ? 'Add Note' : 'Edit Note'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _refBox(context, widget.refText),
              const SizedBox(height: 12),
              TextField(
                controller: _c,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Write your note…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _c.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _c.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
