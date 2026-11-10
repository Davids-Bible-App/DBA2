// import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import 'strongs_models.dart';

import 'package:dba2/main/addons/addon_store.dart';

class StrongsNotInstalled implements Exception {
  const StrongsNotInstalled();
  @override
  String toString() => "Strong's database is not installed";
}

/// Dart port of `lookup_strongs` and `get_verse_study` from reader.rs.
///
/// Queries run in a short-lived background isolate (`Isolate.run`), so a
/// 2000-row LIKE scan never janks the UI thread.
class StrongsRepository {
  StrongsRepository._();
  static final StrongsRepository instance = StrongsRepository._();

  Future<String> _dbPath() async {
    final f = await AddonStore.instance.fileFor(kStrongsDb);
    if (!f.existsSync()) throw const StrongsNotInstalled();
    return f.path;
  }

  Future<LookupResponse> lookup(String query) async {
    final path = await _dbPath();
    return Isolate.run(() => _lookupSync(path, query));
  }

  /// [bookId] is sanitised like the JSX did ("1 th" -> "1TH").
  Future<List<StrongsWord>> verseStudy(
    String bookId,
    int chapter,
    int verse,
  ) async {
    try {
      final path = await _dbPath();
      final id = bookId.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      return await Isolate.run(() => _verseStudySync(path, id, chapter, verse));
    } catch (_) {
      return const []; // same as the Rust: errors -> empty list
    }
  }
}

// ---------------------------------------------------------------------------
// Everything below runs inside the isolate.
// ---------------------------------------------------------------------------

const _defCols =
    'strongs, lemma, transliteration, pronunciation, kjv_def, definition';

String? _s(Object? v) => v?.toString();

StrongsDef _def(Row r) => StrongsDef(
  strongsId: r.columnAt(0).toString(),
  lemma: _s(r.columnAt(1)),
  transliteration: _s(r.columnAt(2)),
  pronunciation: _s(r.columnAt(3)),
  kjvDef: _s(r.columnAt(4)),
  definition: _s(r.columnAt(5)),
);

int _countVerses(List<VerseUsage> verses) => {
  for (final v in verses) '${v.bookId}|${v.chapter}|${v.verse}',
}.length;

LookupResponse _lookupSync(String path, String rawQuery) {
  final query = rawQuery.trim();
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final isStrongs = RegExp(r'^[GHgh]\d{1,4}$').hasMatch(query);
    final dictionaries = <StrongsDef>[];
    final verses = <VerseUsage>[];

    if (isStrongs) {
      final code = query.toUpperCase();

      for (final r in db.select(
        'SELECT $_defCols FROM StrongsDefinition WHERE strongs = ? LIMIT 1',
        [code],
      )) {
        dictionaries.add(_def(r));
      }

      for (final r in db.select(
        'SELECT cv.bookId, cv.chapterNumber, cv.verseNumber, cv.text '
        'FROM VerseWord vw JOIN ChapterVerse cv ON vw.verseId = cv.id '
        'WHERE vw.strongs LIKE ? LIMIT 200',
        ['%$code%'],
      )) {
        verses.add(
          VerseUsage(
            bookId: r.columnAt(0).toString(),
            chapter: r.columnAt(1) as int,
            verse: r.columnAt(2) as int,
            text: r.columnAt(3).toString(),
            strongsIds: [code],
          ),
        );
      }

      return LookupResponse(
        dictionaries: dictionaries,
        verses: verses,
        searchType: 'strongs',
        occurrenceCount: verses.length,
        verseCount: _countVerses(verses),
      );
    }

    // ---- ENGLISH WORD SEARCH ----------------------------------------------
    final like = '%$query%';
    final wordRegex = RegExp(
      '\\b${RegExp.escape(query)}\\b',
      caseSensitive: false,
    );
    final codeRegex = RegExp(r'[GH]\d+');
    final matchedCodes = <String>{};

    // 1. The tagged word(s) matching the query + the code tagged on THAT word.
    for (final r in db.select(
      'SELECT cv.bookId, cv.chapterNumber, cv.verseNumber, cv.text, '
      'vw.text, vw.strongs '
      'FROM VerseWord vw JOIN ChapterVerse cv ON vw.verseId = cv.id '
      'WHERE vw.text LIKE ? LIMIT 2000',
      [like],
    )) {
      final token = r.columnAt(4).toString();
      if (!wordRegex.hasMatch(token)) continue;

      final raw = _s(r.columnAt(5));
      final codes = raw == null
          ? <String>[]
          : [
              for (final m in codeRegex.allMatches(raw))
                m.group(0)!.toUpperCase(),
            ];
      matchedCodes.addAll(codes);

      if (verses.length < 200) {
        verses.add(
          VerseUsage(
            bookId: r.columnAt(0).toString(),
            chapter: r.columnAt(1) as int,
            verse: r.columnAt(2) as int,
            text: r.columnAt(3).toString(),
            strongsIds: codes,
          ),
        );
      }
    }

    // 2a. Dictionary entries actually tagged on the matched words.
    if (matchedCodes.isNotEmpty) {
      final marks = List.filled(matchedCodes.length, '?').join(',');
      for (final r in db.select(
        'SELECT $_defCols FROM StrongsDefinition '
        'WHERE strongs IN ($marks) ORDER BY strongs',
        matchedCodes.toList(),
      )) {
        dictionaries.add(_def(r));
      }
    }

    // 2b. Entries whose gloss literally contains the query (skip dupes).
    for (final r in db.select(
      'SELECT $_defCols FROM StrongsDefinition '
      'WHERE (kjv_def LIKE ? OR definition LIKE ?) '
      'ORDER BY strongs LIMIT 100',
      [like, like],
    )) {
      final d = _def(r);
      if (!matchedCodes.contains(d.strongsId)) dictionaries.add(d);
    }

    return LookupResponse(
      dictionaries: dictionaries,
      verses: verses,
      searchType: 'english',
      occurrenceCount: verses.length,
      verseCount: _countVerses(verses),
    );
  } finally {
    db.close();
  }
}

List<StrongsWord> _verseStudySync(
  String path,
  String bookId,
  int chapter,
  int verse,
) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final rows = db.select(
      'SELECT vw.wordOrder, vw.text, vw.isAdded, vw.strongs, '
      'sd.strongs, sd.lemma, sd.transliteration, sd.pronunciation, '
      'sd.kjv_def, sd.definition '
      'FROM VerseWord vw '
      'LEFT JOIN StrongsDefinition sd ON '
      "' ' || vw.strongs || ' ' LIKE '% ' || sd.strongs || ' %' "
      'WHERE vw.bookId = ? AND vw.chapter = ? AND vw.verse = ? '
      'ORDER BY vw.wordOrder ASC, sd.strongs ASC',
      [bookId, chapter, verse],
    );

    final hasLetter = RegExp(r'[a-zA-Z]');
    final words = <StrongsWord>[];
    StrongsWord? current;

    for (final r in rows) {
      final english = r.columnAt(1).toString();
      if (!hasLetter.hasMatch(english)) continue;

      final order = r.columnAt(0) as int;
      if (current == null || current.wordOrder != order) {
        if (current != null) words.add(current);
        current = StrongsWord(
          wordOrder: order,
          englishWord: english,
          isAdded: r.columnAt(2) == 1,
          rawStrongs: _s(r.columnAt(3)),
        );
      }

      final id = _s(r.columnAt(4));
      if (id != null && id.isNotEmpty) {
        current.definitions.add(
          StrongsDef(
            strongsId: id,
            lemma: _s(r.columnAt(5)),
            transliteration: _s(r.columnAt(6)),
            pronunciation: _s(r.columnAt(7)),
            kjvDef: _s(r.columnAt(8)),
            definition: _s(r.columnAt(9)),
          ),
        );
      }
    }
    if (current != null) words.add(current);
    return words;
  } finally {
    db.close();
  }
}
