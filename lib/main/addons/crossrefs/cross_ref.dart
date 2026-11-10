import 'package:dba2/main/controllers/split_controller.dart';
import 'package:dba2/ui/widgets/toast.dart';
import 'package:dba2/ui/widgets/draggable_snap_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

import 'package:dba2/main/addons/addon_controller.dart';
import 'package:dba2/main/addons/addon_store.dart';
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/ui/translations/services/translation_catalog.dart';

// ---------------------------------------------------------------------------
// MODEL: "GEN.4.1" or "GEN.4.25-GEN.4.26"
// ---------------------------------------------------------------------------

class CrossRefTarget {
  const CrossRefTarget({
    required this.bookId,
    required this.chapter,
    required this.startVerse,
    required this.endVerse,
  });

  final String bookId;
  final int chapter;
  final int startVerse;
  final int endVerse;

  bool get isRange => endVerse != startVerse;

  static CrossRefTarget? parse(String raw) {
    try {
      final parts = raw.split('-');
      final s = parts.first.split('.');
      final e = parts.length > 1 ? parts[1].split('.') : s;
      return CrossRefTarget(
        bookId: s[0],
        chapter: int.parse(s[1]),
        startVerse: int.parse(s[2]),
        endVerse: int.parse(e[2]), // like your Rust: same chapter assumed
      );
    } catch (_) {
      return null; // malformed row: skip it
    }
  }
}

// ---------------------------------------------------------------------------
// REPOSITORY: read-only access to cross_refs.db.
// Opens and closes per call (cheap), so install/remove just works.
// ---------------------------------------------------------------------------

class CrossRefRepository {
  CrossRefRepository(this._store);
  static final instance = CrossRefRepository(AddonStore.instance);

  final AddonStore _store;

  Future<T?> _withDb<T>(T Function(sqlite3lib.Database db) action) async {
    final file = await _store.fileFor(kCrossRefsDb);
    if (!file.existsSync()) return null; // graceful exit, like your Rust
    sqlite3lib.Database? db;
    try {
      db = sqlite3lib.sqlite3.open(
        file.path,
        mode: sqlite3lib.OpenMode.readOnly,
      );
      return action(db);
    } catch (e) {
      debugPrint('cross_refs.db error: $e');
      return null;
    } finally {
      db?.close();
    }
  }

  /// Verse numbers in this chapter that have cross references.
  Future<Set<int>> versesWithRefs(String bookId, int chapter) async {
    final result = await _withDb((db) {
      final rows = db.select(
        'SELECT DISTINCT source_verse FROM cross_refs '
        'WHERE source_verse LIKE ?',
        ['${bookId.toUpperCase()}.$chapter.%'],
      );
      final out = <int>{};
      for (final r in rows) {
        final n = int.tryParse((r['source_verse'] as String).split('.').last);
        if (n != null) out.add(n);
      }
      return out;
    });
    return result ?? <int>{};
  }

  Future<List<CrossRefTarget>> refsFor(
    String bookId,
    int chapter,
    int verse,
  ) async {
    final key = '${bookId.toUpperCase()}.$chapter.$verse';
    final result = await _withDb((db) {
      final rows = db.select(
        'SELECT target_verse FROM cross_refs WHERE source_verse = ?',
        [key],
      );
      return [
        for (final r in rows)
          ?CrossRefTarget.parse(r['target_verse'] as String),
      ];
    });
    return result ?? <CrossRefTarget>[];
  }
}

/// Reopens the last cross reference lookup. Safe to call from any button.
Future<void> reopenLastCrossRefSheet(BuildContext context) async {
  final last = CrossRefMemory.instance.last;
  if (last == null) {
    showToast('No cross reference lookup yet');
    return;
  }
  final bible = context.read<BibleController>();
  final split = context.read<SplitController>();

  // Use the pane's text if the lookup came from a second pane that is
  // still open; otherwise fall back to the primary translation.
  String Function(String, int, int, int)? textOf;
  String? abbr;
  for (final p in split.panes) {
    if (p.id == last.translationId) {
      textOf = p.passageText;
      abbr = p.info.abbr;
    }
  }

  return showCrossRefSheet(
    context,
    bible: bible,
    bookId: last.bookId,
    chapter: last.chapter,
    verse: last.verse,
    translationId: last.translationId,
    textOf: textOf,
    abbr: abbr,
  );
}

// ---------------------------------------------------------------------------
// LOADER: finds which verses of a chapter have refs, and hands them to
// [builder]. Reloads when the chapter changes or the addon is installed.
// ---------------------------------------------------------------------------

class ChapterCrossRefs extends StatefulWidget {
  const ChapterCrossRefs({
    super.key,
    required this.bookId,
    required this.chapter,
    required this.builder,
  });

  final String bookId;
  final int chapter;
  final Widget Function(BuildContext context, Set<int> verses) builder;

  @override
  State<ChapterCrossRefs> createState() => _ChapterCrossRefsState();
}

class _ChapterCrossRefsState extends State<ChapterCrossRefs> {
  Set<int> _verses = const {};
  bool? _has;
  int _token = 0; // ignores answers from an older chapter

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final has = Provider.of<AddonController>(context).hasCrossRefs;
    if (has != _has) {
      _has = has;
      _refresh();
    }
  }

  @override
  void didUpdateWidget(ChapterCrossRefs old) {
    super.didUpdateWidget(old);
    if (old.bookId != widget.bookId || old.chapter != widget.chapter) {
      _refresh();
    }
  }

  void _refresh() {
    final token = ++_token;
    _verses = const {}; // no stale symbols (build runs right after this)
    if (_has != true) return;
    CrossRefRepository.instance
        .versesWithRefs(widget.bookId, widget.chapter)
        .then((v) {
          if (!mounted || token != _token) return;
          setState(() => _verses = v);
        });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _verses);
}

// ---------------------------------------------------------------------------
// SHEET
// ---------------------------------------------------------------------------
class CrossRefLookup {
  const CrossRefLookup({
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.translationId,
  });
  final String bookId;
  final int chapter;
  final int verse;
  final String translationId; // which pane/translation it came from
}

class CrossRefMemory {
  CrossRefMemory._();
  static final instance = CrossRefMemory._();
  CrossRefLookup? last;
}

Future<void> showCrossRefSheet(
  BuildContext context, {
  required BibleController bible,
  required String bookId,
  required int chapter,
  required int verse,
  String Function(String bk, int ch, int start, int end)? textOf,
  String? abbr,
  String? translationId,
}) {
  CrossRefMemory.instance.last = CrossRefLookup(
    bookId: bookId,
    chapter: chapter,
    verse: verse,
    translationId: translationId ?? bible.translationId,
  );
  return showModalSnapSheet<void>(
    context: context,
    positions: .two(min: 0.5, max: 0.9, starting: 0.5),
    sheetKey: 'crossRef',
    builder: (_) => CrossRefSheet(
      bible: bible,
      bookId: bookId,
      chapter: chapter,
      verse: verse,
      textOf: textOf,
      abbr: abbr,
    ),
  );
}

class CrossRefSheet extends StatefulWidget {
  const CrossRefSheet({
    super.key,
    required this.bible,
    required this.bookId,
    required this.chapter,
    required this.verse,
    this.textOf,
    this.abbr,
  });

  final BibleController bible;
  final String bookId;
  final int chapter;
  final int verse;
  final String Function(String bk, int ch, int start, int end)? textOf;
  final String? abbr;

  @override
  State<CrossRefSheet> createState() => _CrossRefSheetState();
}

class _CrossRefSheetState extends State<CrossRefSheet> {
  // Created ONCE, so rebuilds don't re-query the database.
  late final Future<List<CrossRefTarget>> _refs = CrossRefRepository.instance
      .refsFor(widget.bookId, widget.chapter, widget.verse);

  String _bookName(String id) {
    for (final b in widget.bible.books) {
      if (b.id.toUpperCase() == id.toUpperCase()) return b.englishName;
    }
    return id;
  }

  void _jump(CrossRefTarget t) {
    // Use the id exactly as the controller knows it.
    final book = widget.bible.books.where(
      (b) => b.id.toUpperCase() == t.bookId.toUpperCase(),
    );
    if (book.isEmpty) return;
    Navigator.of(context).pop(); // close the sheet first
    widget.bible.goTo(book.first.id, t.chapter, verse: t.startVerse);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bible = widget.bible;
    final abbr =
        widget.abbr ??
        (bible.hasTranslation ? translationFor(bible.translationId).abbr : '');

    return FutureBuilder<List<CrossRefTarget>>(
      future: _refs,
      builder: (context, snap) {
        final done = snap.connectionState == ConnectionState.done;
        final refs = snap.data ?? const <CrossRefTarget>[];
        final n = refs.length;

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  '($n) ${n == 1 ? 'Cross Reference' : 'Cross References'} '
                  '· ${_bookName(widget.bookId)} ${widget.chapter}:${widget.verse}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Divider(height: 10, color: Colors.grey.shade500),
            ),
            if (!done)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (refs.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No cross references.')),
                ),
              )
            else
              SliverList.separated(
                itemCount: refs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, i) {
                  final t = refs[i];
                  final range = t.isRange ? '–${t.endVerse}' : '';
                  final label =
                      '${_bookName(t.bookId)} '
                      '${t.chapter}:${t.startVerse}$range'
                      '${abbr.isEmpty ? '' : ' ($abbr)'}';
                  final text = (widget.textOf ?? bible.passageText)(
                    t.bookId,
                    t.chapter,
                    t.startVerse,
                    t.endVerse,
                  );
                  return InkWell(
                    onTap: () => _jump(t),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            text.isEmpty ? 'Text not available.' : text,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
