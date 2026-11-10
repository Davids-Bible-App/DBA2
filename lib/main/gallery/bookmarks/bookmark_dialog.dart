import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:flutter/material.dart';

import 'bookmark_models.dart';
import 'bookmark_store.dart';

/// Returns true if a bookmark was saved/updated.
Future<bool?> showBookmarkDialog(
  BuildContext context, {
  required BookmarkStore store,
  required List<BookmarkVerse> verses,
}) => showLockedDialog<bool>(
  context: context,
  builder: (_) => _BookmarkDialog(store: store, verses: verses),
);

class _BookmarkDialog extends StatefulWidget {
  const _BookmarkDialog({required this.store, required this.verses});
  final BookmarkStore store;
  final List<BookmarkVerse> verses;

  @override
  State<_BookmarkDialog> createState() => _BookmarkDialogState();
}

class _BookmarkDialogState extends State<_BookmarkDialog> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  String _error = '';
  bool _saving = false;
  bool _listOpen = true; // suggestions visible (not tied to focus)

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Bookmark? get _match => widget.store.findByTitle(_ctl.text);

  List<Bookmark> get _suggestions {
    final t = _ctl.text.trim().toLowerCase();
    final all = widget.store.items;
    if (t.isEmpty) return all;
    return all.where((b) {
      final l = b.title.toLowerCase();
      return l.contains(t) && l != t;
    }).toList();
  }

  Future<void> _save() async {
    final t = _ctl.text.trim();
    if (t.isEmpty) return setState(() => _error = 'Please enter a title.');
    if (widget.verses.isEmpty) {
      return setState(() => _error = 'No verses selected.');
    }
    setState(() => _saving = true);
    try {
      await widget.store.save(t, widget.verses);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final match = _match;
    final sugg = _suggestions;
    final showSugg = _listOpen && match == null && sugg.isNotEmpty;

    return AlertDialog(
      // backgroundColor: Colors.red,
      title: Row(
        children: [
          const Icon(Icons.bookmark_add_outlined),
          const SizedBox(width: 8),
          Text(match != null ? 'Update Bookmark' : 'Add Bookmark'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.black12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.store.refText(widget.verses),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctl,
                focusNode: _focus,
                autofocus: true,
                maxLength: 120,
                onSubmitted: (_) => _save(),
                onChanged: (_) => setState(() {
                  _error = '';
                  _listOpen = true;
                }),
                onTap: () => setState(() => _listOpen = true),
                decoration: const InputDecoration(
                  hintText: 'Title / Reason…',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              if (showSugg)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 5 * 48),
                  child: Card(
                    margin: const EdgeInsets.only(top: 4),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final b in sugg)
                          ListTile(
                            dense: true,
                            tileColor: cs.outlineVariant,
                            title: Text(
                              b.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: b.verses.isEmpty
                                ? null
                                : Text(
                                    '${widget.store.bookName(b.verses.first.bookId)} '
                                    '${b.verses.first.chapter}:${b.verses.first.verse}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                            onTap: () {
                              // Use the picked name exactly -> "Update" path.
                              _ctl.value = TextEditingValue(
                                text: b.title,
                                selection: TextSelection.collapsed(
                                  offset: b.title.length,
                                ),
                              );
                              setState(() {
                                _listOpen = false;
                                _error = '';
                              });
                              _focus.requestFocus();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              if (_ctl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 10,
                  ),
                  decoration: BoxDecoration(
                    color: match != null
                        ? cs.errorContainer
                        : cs.outlineVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    match != null
                        ? '⚠ Verses will be updated on this bookmark'
                        : '✦ New bookmark will be created',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error,
                    style: TextStyle(color: cs.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving ? 'Saving…' : (match != null ? 'Update' : 'Save'),
          ),
        ),
      ],
    );
  }
}
