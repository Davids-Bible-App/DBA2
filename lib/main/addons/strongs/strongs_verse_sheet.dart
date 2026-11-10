import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'strongs_lookup_sheet.dart';
import 'strongs_models.dart';
import 'strongs_repository.dart';
import 'strongs_theme.dart';

import 'package:dba2/ui/widgets/draggable_snap_sheet.dart';

import 'strongs_widgets.dart';

/// Opens the word-by-word Strong's study of ONE verse as a TOP sheet.
///
/// Pass the verse explicitly. (The JSX "latched" the last selection because
/// the selection signal gets cleared; here you capture it at tap time.)
///
///   final r = bible.selection.sorted.first;
///   showStrongsVerseSheet(context, bookId: r.bk, chapter: r.ch, verse: r.vs);
Future<void> showStrongsVerseSheet(
  BuildContext context, {
  required String bookId,
  required int chapter,
  required int verse,
}) {
  final bible = context.read<BibleController>();
  return showModalSnapSheet<void>(
    context: context,
    positions: kTopSheetPositions,
    setTop: true,
    resizeContent: true, // the list scrolls, so it must match the visible area
    builder: (_) => StrongsVerseSheet(
      bible: bible,
      bookId: bookId,
      chapter: chapter,
      verse: verse,
    ),
  );
}

class StrongsVerseSheet extends StatefulWidget {
  const StrongsVerseSheet({
    super.key,
    required this.bible,
    required this.bookId,
    required this.chapter,
    required this.verse,
  });

  final BibleController bible;
  final String bookId;
  final int chapter;
  final int verse;

  @override
  State<StrongsVerseSheet> createState() => _StrongsVerseSheetState();
}

class _StrongsVerseSheetState extends State<StrongsVerseSheet> {
  // Created once, so rebuilds (keyboard, rotation) never re-query the db.
  late final Future<List<StrongsWord>> _future = StrongsRepository.instance
      .verseStudy(widget.bookId, widget.chapter, widget.verse);

  String get _bookName {
    for (final b in widget.bible.books) {
      if (b.id == widget.bookId) return b.englishName;
    }
    return widget.bookId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = StrongsTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SheetSafePadding(
      child: Column(
        children: [
          const SheetTitle('Strongs Dictionary'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.black12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$_bookName ${widget.chapter}:${widget.verse} (KJV)',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<StrongsWord>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Center(
                    child: Text(
                      'Loading original texts...',
                      style: TextStyle(
                        color: t.dimmerText,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                }
                final words = snap.data ?? const <StrongsWord>[];
                if (words.isEmpty) {
                  return Center(
                    child: Text(
                      "No Strong's data found for this verse.",
                      style: TextStyle(
                        color: t.dimmerText,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: words.length,
                  separatorBuilder: (_, _) => Divider(
                    color: t.divider.withValues(alpha: 0.4),
                    height: 1,
                  ),
                  itemBuilder: (_, i) =>
                      _WordCard(word: words[i], bible: widget.bible),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ONE ENGLISH WORD + its original-language entries
// ---------------------------------------------------------------------------

class _WordCard extends StatelessWidget {
  const _WordCard({required this.word, required this.bible});

  final StrongsWord word;
  final BibleController bible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = StrongsTheme.of(context);

    final english = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          word.englishWord,
          style: theme.textTheme.titleMedium?.copyWith(
            color: t.dimText,
            fontWeight: word.isAdded ? FontWeight.normal : FontWeight.w600,
            fontStyle: word.isAdded ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        if (word.isAdded)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'WAS ADDED FOR LANGUAGE FLOW.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: t.dimmerText,
                letterSpacing: 0.8,
              ),
            ),
          ),
      ],
    );

    final defs = Column(
      children: [
        for (final d in word.definitions)
          StrongsEntry(
            def: d,
            onTagTap: () => showStrongsLookupSheet(
              context,
              query: d.strongsId,
              origin: word.englishWord,
              bible: bible,
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: LayoutBuilder(
        builder: (context, c) {
          // CSS: @media (min-width: 768px) -> side by side.
          if (c.maxWidth >= 560) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: c.maxWidth * 0.3, child: english),
                const SizedBox(width: 12),
                Expanded(child: defs),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              english,
              if (word.definitions.isNotEmpty) ...[
                const SizedBox(height: 8),
                defs,
              ],
            ],
          );
        },
      ),
    );
  }
}
