import 'dart:isolate';

import 'package:dba2/main/models/bible_book.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// ---------------------------------------------------------------------------
// MODELS
// ---------------------------------------------------------------------------

class SearchHit {
  const SearchHit({
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  final String bookId;
  final int chapter;
  final int verse;

  /// Raw text. For keyword searches it contains <mark>…</mark> around matches.
  final String text;

  String get key => '$bookId|$chapter|$verse';

  /// Text with every tag removed (clipboard / export).
  String get plainText => stripTags(text);
}

class SearchPage {
  const SearchPage(this.hits, this.total, {this.isReference = false});
  final List<SearchHit> hits;
  final int total;
  final bool isReference;
}

/// One contiguous piece of a reference: whole chapter (from == null) or a
/// verse range inside a chapter.
class RefRange {
  const RefRange(this.bookId, this.chapter, [this.from, this.to]);
  final String bookId;
  final int chapter;
  final int? from;
  final int? to;
}

// ---------------------------------------------------------------------------
// TEXT HELPERS (the <mark> handling that innerHTML did for you in Solid)
// ---------------------------------------------------------------------------

String _decode(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

String stripTags(String s) => _decode(s.replaceAll(RegExp(r'<[^>]*>'), ''));

typedef TextSeg = ({String text, bool marked});

/// Splits "a <mark>b</mark> c" into [a, b(marked), c]. Other tags are dropped.
List<TextSeg> parseSegments(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'<(?!/?mark\b)[^>]*>'), '');
  final out = <TextSeg>[];
  var pos = 0;
  for (final m in RegExp(
    r'<mark>(.*?)</mark>',
    dotAll: true,
  ).allMatches(cleaned)) {
    if (m.start > pos) {
      out.add((text: _decode(cleaned.substring(pos, m.start)), marked: false));
    }
    out.add((text: _decode(m.group(1)!), marked: true));
    pos = m.end;
  }
  if (pos < cleaned.length) {
    out.add((text: _decode(cleaned.substring(pos)), marked: false));
  }
  return out;
}

// ---------------------------------------------------------------------------
// QUERY PREPARATION (ports of looks_like_reference / prepare_fts5_fuzzy_query)
// ---------------------------------------------------------------------------

bool looksLikeReference(String q) =>
    q.contains(':') ||
    q.contains('-') ||
    q.contains(',') ||
    RegExp(r'\.[0-9]').hasMatch(q);

/// "grace mercy" -> '"grace mercy" OR (grace* OR mercy*)'
String prepareFtsQuery(String input) {
  final clean = input.replaceAll(
    RegExp(r'[^\p{L}\p{N}\s]', unicode: true),
    ' ',
  );
  final terms = clean.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (terms.isEmpty) return '';
  if (terms.length == 1) return '${terms.first}*';
  final phrase = terms.join(' ');
  final ors = terms.map((t) => '$t*').join(' OR ');
  return '"$phrase" OR ($ors)';
}

/// Looks up parsed ranges. By default repeated verses are kept (in typed order);
/// pass `dedupe: true` to collapse them into a unique list.
String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
final _startsWithNum = RegExp(r'^[1-3]');

bool _subsequence(String t, String n) {
  if (t[0] != n[0]) return false;
  var i = 0;
  for (var k = 0; k < n.length && i < t.length; k++) {
    if (n[k] == t[i]) i++;
  }
  return i == t.length;
}

BibleBook? _findBook(String token, List<BibleBook> books) {
  final t = _norm(token);
  if (t.isEmpty) return null;

  for (final b in books) {
    if (_norm(b.id) == t) return b;
  }
  for (final b in books) {
    if (_norm(b.englishName) == t) return b;
  }

  final tNum = _startsWithNum.hasMatch(t);
  BibleBook? pick(bool Function(String name) test) {
    BibleBook? best;
    var bestLen = 1 << 30;
    for (final b in books) {
      final n = _norm(b.englishName);
      if (n.isEmpty) continue;
      final nNum = _startsWithNum.hasMatch(n);
      if (tNum != nNum || (tNum && t[0] != n[0])) {
        continue; // "1 john" vs "john"
      }
      if (!test(n)) continue;
      if (n.length < bestLen) {
        best = b;
        bestLen = n.length; // shortest name wins ties: "jn" -> John, not Jonah
      }
    }
    return best;
  }

  return pick((n) => n.startsWith(t)) ?? pick((n) => _subsequence(t, n));
}

// -------------------------------------------------------------------------------------
// REFERENCE PARSER
//
//* Handles: John1:, jhn.1:1,3,4,2-5, jn2-4,5:2,1:1, 1 cor 13:4-7, ps 23, gen 1:31-2:3
//
// Input is split on commas, and each piece is read in turn:
//   - A piece that starts with a book name ("jhn.1:1", "1 cor 13:4-7", "ps 23")
//     begins a NEW reference and resets the current book, chapter and mode.
//   - A piece with no book name continues the previous one ("3", "2-5", "5:2").
//
// Rules:   after a "ch:vs" segment, bare numbers are verses of that chapter;
//          before it, bare numbers are whole chapters.
//          A cross-chapter range ("gen 1:31-2:3") moves the current chapter to
//          the END chapter, so a following ", 5" means 2:5, not 1:5.
//
// Unknown book names are skipped, along with the pieces that follow them,
// until the next piece that starts with a valid book.
//
// DUPLICATES: ranges are returned in the order typed and are NOT deduplicated by
//   default. "jhn.1:1,3,4,2-5" gives 1, 3, 4, 2, 3, 4, 5, so each segment returns
//   everything it asks for. Pass `dedupe: true` to runReferenceSearch() for a
//   clean union (1, 2, 3, 4, 5). Keep this in mind if a ListView keys on
//   SearchHit.key, as repeated verses share the same key. Combine it with the
//   list index, e.g. ValueKey('${hit.key}#$index').
//
//! QUOTES: will break it. Plain comma-separated text is enough.
// -------------------------------------------------------------------------------------
// Hoisted so they're compiled once, not on every keystroke.
final _bookTokenRe = RegExp(
  r'^\s*([1-3]?\s*[A-Za-z][A-Za-z\s.]*?)[\s.]*(\d.*)?$',
);
final _withColonRe = RegExp(
  r'^(\d+)\s*:\s*(\d*)\s*(?:-\s*(\d+)\s*(?::\s*(\d*))?)?$',
);
final _plainRe = RegExp(r'^(\d+)\s*(?:-\s*(\d+))?$');

/// Mutable "where are we" state carried from one comma-piece to the next.
class _Ctx {
  BibleBook? book;
  int? chapter;
  bool verseMode = false;
}

List<RefRange> parseReference(String input, List<BibleBook> books) {
  final out = <RefRange>[];
  final ctx = _Ctx();

  for (final raw in input.split(',')) {
    var seg = raw.trim();
    if (seg.isEmpty) continue;

    // Does this piece START with a book name? ("jhn.1:1", "1 cor 13:4-7")
    // Bare numbers like "3", "2-5", "5:2" have no letters, so they won't match.
    final m = _bookTokenRe.firstMatch(seg);
    if (m != null) {
      ctx
        ..book =
            _findBook(m.group(1)!, books) // null if unknown
        ..chapter = null
        ..verseMode = false;
      seg = (m.group(2) ?? '').trim();
      if (seg.isEmpty) continue;
    }

    final book = ctx.book;
    if (book == null) continue; // unknown book: skip its pieces
    _parseSegment(seg, book, ctx, out);
  }
  return out;
}

void _parseSegment(String seg, BibleBook book, _Ctx ctx, List<RefRange> out) {
  final v = _withColonRe.firstMatch(seg);
  if (v != null) {
    final c1 = int.parse(v[1]!);
    final v1 = v[2]!.isEmpty ? null : int.parse(v[2]!);
    final a = v[3] == null ? null : int.parse(v[3]!);
    final crossChapter = v[4] != null;

    if (crossChapter && a != null) {
      // 1:31-2:3
      final v2 = v[4]!.isEmpty ? null : int.parse(v[4]!);
      if (a >= c1 && a - c1 <= 200) {
        out.add(RefRange(book.id, c1, v1 ?? 1, 9999));
        for (var c = c1 + 1; c < a; c++) {
          out.add(RefRange(book.id, c));
        }
        if (a > c1) out.add(RefRange(book.id, a, 1, v2 ?? 9999));
      }
      ctx.chapter = a; // FIX: we ended in chapter `a`, not `c1`
    } else if (a != null) {
      out.add(RefRange(book.id, c1, v1 ?? 1, a)); // 1:2-5
      ctx.chapter = c1;
    } else if (v1 == null) {
      out.add(RefRange(book.id, c1)); // "1:" -> whole chapter
      ctx.chapter = c1;
    } else {
      out.add(RefRange(book.id, c1, v1, v1));
      ctx.chapter = c1;
    }
    ctx.verseMode = true;
    return;
  }

  final n = _plainRe.firstMatch(seg);
  if (n == null) return;
  final a = int.parse(n[1]!);
  final b = n[2] == null ? a : int.parse(n[2]!);

  if (ctx.verseMode && ctx.chapter != null) {
    out.add(RefRange(book.id, ctx.chapter!, a, b)); // verses of current chapter
  } else if (b >= a && b - a <= 200) {
    for (var c = a; c <= b; c++) {
      out.add(RefRange(book.id, c)); // whole chapters
    }
    ctx.chapter = b;
  }
}

// ---------------------------------------------------------------------------
// DATABASE (runs in a background isolate so big pages never jank the UI)
//
// IMPORTANT: only top-level functions below; closures passed to Isolate.run
// must not capture `this` of a widget/controller.
// ---------------------------------------------------------------------------

Future<SearchPage> runKeywordSearch({
  required String dbPath,
  required String ftsQuery,
  required String? scope,
  required int page,
  required int perPage,
  int? knownTotal, // NEW: pass the old total to skip the slow COUNT
}) => Isolate.run(
  () => _keyword(dbPath, ftsQuery, scope, page, perPage, knownTotal),
);

/// Looks up parsed ranges. By default repeated verses are kept (in typed order);
/// pass `dedupe: true` to collapse them into a unique list.
Future<SearchPage> runReferenceSearch(
  String dbPath,
  List<RefRange> ranges, {
  bool dedupe = false,
}) => Isolate.run(() => _reference(dbPath, ranges, dedupe));

SearchPage _keyword(
  String dbPath,
  String ftsQuery,
  String? scope,
  int page,
  int perPage,
  int? knownTotal,
) {
  final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
  try {
    final scopeFilter = switch (scope) {
      'OT' => 'AND b."order" < 40',
      'NT' => 'AND b."order" >= 40',
      _ => '',
    };

    // COUNT is only run when we don't already know the total.
    final int total;
    if (knownTotal != null) {
      total = knownTotal;
    } else {
      // Without an OT/NT filter the Book table isn't needed, so skip the join.
      final countSql = scopeFilter.isEmpty
          ? 'SELECT COUNT(*) FROM chapterVerse_fts WHERE text MATCH ?'
          : 'SELECT COUNT(*) FROM chapterVerse cv '
                'JOIN chapterVerse_fts fts ON cv.rowid = fts.rowid '
                'JOIN Book b ON cv.bookId = b.id '
                'WHERE fts.text MATCH ? $scopeFilter';
      total = db.select(countSql, [ftsQuery]).first.columnAt(0) as int;
    }

    final offset = page * perPage;
    final rows = db.select(
      'SELECT cv.bookId, cv.chapterNumber, cv.number, '
      "highlight(chapterVerse_fts, 0, '<mark>', '</mark>'), "
      'bm25(chapterVerse_fts) AS score '
      'FROM chapterVerse cv '
      'JOIN chapterVerse_fts fts ON cv.rowid = fts.rowid '
      'JOIN Book b ON cv.bookId = b.id '
      'WHERE fts.text MATCH ? $scopeFilter '
      'ORDER BY score ASC, b."order" ASC, cv.chapterNumber ASC, cv.number ASC '
      'LIMIT $perPage OFFSET $offset',
      [ftsQuery],
    );

    final hits = [
      for (final r in rows)
        SearchHit(
          bookId: r.columnAt(0).toString(),
          chapter: r.columnAt(1) as int,
          verse: r.columnAt(2) as int,
          text: (r.columnAt(3) ?? '').toString(),
        ),
    ];
    return SearchPage(hits, total);
  } finally {
    db.close();
  }
}

SearchPage _reference(String dbPath, List<RefRange> ranges, bool dedupe) {
  final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
  try {
    final chapterStmt = db.prepare(
      'SELECT number, text FROM ChapterVerse '
      'WHERE bookId = ? AND chapterNumber = ? ORDER BY number',
    );
    final rangeStmt = db.prepare(
      'SELECT number, text FROM ChapterVerse '
      'WHERE bookId = ? AND chapterNumber = ? '
      'AND number BETWEEN ? AND ? ORDER BY number',
    );

    final seen = <String>{};
    final hits = <SearchHit>[];

    for (final r in ranges) {
      final rows = r.from == null
          ? chapterStmt.select([r.bookId, r.chapter])
          : rangeStmt.select([r.bookId, r.chapter, r.from, r.to ?? r.from]);

      for (final row in rows) {
        final hit = SearchHit(
          bookId: r.bookId,
          chapter: r.chapter,
          verse: row.columnAt(0) as int,
          text: (row.columnAt(1) ?? '').toString(),
        );
        if (!dedupe || seen.add(hit.key)) hits.add(hit);
      }
    }
    return SearchPage(hits, hits.length, isReference: true);
  } finally {
    db.close();
  }
}
