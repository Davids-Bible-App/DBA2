import 'package:dba2/core.dart'; // gives you Provider / context.read / context.watch
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:dba2/ui/widgets/draggable_snap_sheet.dart';

import 'history_controller.dart';

/// Open from anywhere: showHistorySheet(context);
Future<void> showHistorySheet(BuildContext context) {
  context.read<HistoryController>().load();
  return showModalSnapSheet<void>(
    context: context,
    positions: .two(min: 0.6, max: 0.9, starting: 0.6),
    sheetKey: 'history',
    builder: (_) => HistorySheet(),
  );
}

class HistorySheet extends StatelessWidget {
  const HistorySheet({super.key});

  String _bookName(BibleController bible, String id) {
    for (final b in bible.books) {
      if (b.id == id) return b.englishName;
    }
    return id;
  }

  Future<void> _jump(BuildContext context, HistoryEntry e) async {
    final bible = context.read<BibleController>();
    Navigator.of(context).pop(); // close the sheet first
    if (e.translationId != bible.translationId) {
      await bible.setTranslation(e.translationId);
    }
    bible.goTo(e.bookId, e.chapter, verse: e.verseId); // scrolls + glows
  }

  Future<void> _confirmClear(BuildContext context) async {
    final h = context.read<HistoryController>();
    final ok = await showLockedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text(
          'Are you sure you want to clear all reading history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) await h.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.watch<HistoryController>();
    final bible = context.read<BibleController>();
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);

    return CustomScrollView(
      // must be attached, or the sheet won't drag/scroll
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Text('History', style: theme.textTheme.titleLarge),
                const Spacer(),
                if (h.entries.isNotEmpty)
                  TextButton(
                    onPressed: () => _confirmClear(context),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: const Text('Clear All'),
                  ),
              ],
            ),
          ),
        ),
        if (h.loading && h.entries.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (h.entries.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No reading history yet.')),
          )
        else
          SliverList.separated(
            itemCount: h.entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final e = h.entries[i];
              return Dismissible(
                key: ValueKey(e.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: theme.colorScheme.errorContainer,
                  child: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                onDismissed: (_) => h.delete(e),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ListTile(
                    dense: true,
                    onTap: () => _jump(context, e),
                    title: Text(
                      '${_bookName(bible, e.bookId)} ${e.chapter}:${e.verseId}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.translationId),
                        Text(loc.formatShortDate(e.updatedAt)),
                      ],
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove from history',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => h.delete(e),
                    ),
                  ),
                ),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 50)),
      ],
    );
  }
}
