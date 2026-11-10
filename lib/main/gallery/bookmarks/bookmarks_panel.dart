import 'package:dba2/main/gallery/common.dart';
import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bookmark_models.dart';
import 'bookmark_store.dart';

class BookmarksPanel extends StatefulWidget {
  const BookmarksPanel({
    super.key,
    required this.store,
    required this.onJumpTo,
  });

  final BookmarkStore store;

  /// Jump the reader to this verse (first verse of the bookmark).
  final void Function(BookmarkVerse verse) onJumpTo;

  @override
  State<BookmarksPanel> createState() => _BookmarksPanelState();
}

class _BookmarksPanelState extends State<BookmarksPanel> {
  // String _query = '';
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(Bookmark bm) async {
    final ok = await showLockedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bookmark?'),
        content: Text(bm.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) widget.store.delete(bm.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        // rebuild on store changes AND on typing/clearing
        listenable: Listenable.merge([widget.store, _query]),
        builder: (context, _) {
          final q = _query.text.trim().toLowerCase();
          final filtering = q.isNotEmpty;
          final all = widget.store.items;
          final shown = filtering
              ? all.where((b) => b.title.toLowerCase().contains(q)).toList()
              : all;

          Widget card(int i, {required bool draggable}) {
            final bm = shown[i];
            return _BookmarkCard(
              key: ValueKey(bm.id),
              bookmark: bm,
              refText: widget.store.refText(bm.verses),
              dragHandle: draggable
                  ? ReorderableDragStartListener(
                      index: i,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Container(
                          width: 30,
                          color: cs.onInverseSurface,
                          child: Center(
                            child: Icon(Icons.drag_indicator, size: 20),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: 8),
              onRename: (t) => widget.store.rename(bm.id, t),
              onDelete: () => _confirmDelete(bm),
              onGo: () {
                if (bm.verses.isNotEmpty) widget.onJumpTo(bm.verses.first);
              },
            );
          }

          Widget body;
          if (widget.store.loading) {
            body = const Center(child: Text('Loading…'));
          } else if (shown.isEmpty) {
            body = Center(
              child: Opacity(
                opacity: 0.6,
                child: Text(
                  filtering ? 'No matches found.' : 'No bookmarks yet.',
                ),
              ),
            );
          } else if (filtering) {
            // Reordering a filtered subset would corrupt indices -> plain list.
            body = ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => card(i, draggable: false),
            );
          } else {
            body = ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
              buildDefaultDragHandles: false,
              itemCount: shown.length,
              proxyDecorator: (child, _, _) => Material(
                color: Colors.transparent,
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                child: child,
              ),
              onReorderItem: (oldIndex, newIndex) {
                // if (newIndex > oldIndex) newIndex -= 1;
                if (oldIndex != newIndex) {
                  widget.store.reorder(oldIndex, newIndex);
                }
              },
              itemBuilder: (_, i) => Padding(
                key: ValueKey(shown[i].id),
                padding: const EdgeInsets.only(bottom: 10),
                child: card(i, draggable: true),
              ),
            );
          }

          return Column(
            children: [
              GallerySearchField(
                controller: _query,
                hint: 'Search bookmarks...',
              ),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }
}

class _BookmarkCard extends StatefulWidget {
  const _BookmarkCard({
    super.key,
    required this.bookmark,
    required this.refText,
    required this.dragHandle,
    required this.onRename,
    required this.onDelete,
    required this.onGo,
  });

  final Bookmark bookmark;
  final String refText;
  final Widget dragHandle;
  final void Function(String title) onRename;
  final VoidCallback onDelete, onGo;

  @override
  State<_BookmarkCard> createState() => _BookmarkCardState();
}

class _BookmarkCardState extends State<_BookmarkCard> {
  bool _editing = false;
  late final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _start() {
    _ctl.text = widget.bookmark.title;
    setState(() => _editing = true);
  }

  void _cancel() => setState(() => _editing = false);

  void _confirm() {
    final t = _ctl.text.trim();
    if (t.isEmpty) return;
    widget.onRename(t);
    setState(() => _editing = false);
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final small = IconButton.styleFrom(
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(32, 32),
      padding: EdgeInsets.zero,
    );

    return Container(
      decoration: BoxDecoration(
        // color: cs.surfaceContainerHigh,
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: cs.surfaceContainerHigh,
              child: widget.dragHandle,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _editing
                              ? Focus(
                                  onKeyEvent: (_, e) {
                                    if (e is KeyDownEvent &&
                                        e.logicalKey ==
                                            LogicalKeyboardKey.escape) {
                                      _cancel();
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: TextField(
                                    controller: _ctl,
                                    autofocus: true,
                                    maxLength: 120,
                                    onSubmitted: (_) => _confirm(),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      counterText: '',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                )
                              : Text(
                                  widget.bookmark.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                        if (_editing) ...[
                          IconButton(
                            style: small,
                            tooltip: 'Save',
                            onPressed: _confirm,
                            icon: const Icon(Icons.check, size: 18),
                          ),
                          IconButton(
                            style: small,
                            tooltip: 'Cancel',
                            onPressed: _cancel,
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ] else ...[
                          IconButton(
                            style: small,
                            tooltip: 'Rename',
                            onPressed: _start,
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            style: small,
                            tooltip: 'Delete',
                            onPressed: widget.onDelete,
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: cs.onInverseSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.refText,
                        style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Opacity(
                          opacity: 0.6,
                          child: Text(
                            _date(widget.bookmark.updatedAt),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        TextButton(
                          onPressed: widget.onGo,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Go to Page ↣'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
