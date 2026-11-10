import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

import 'package:dba2/ui/translations/services/translation_store.dart';

/// selected = show only the verses the user picked (Tauri "Verses" tab)
/// single   = page through the chapter one verse at a time (Tauri "Verse" tab)
enum CompareMode { selected, single }

/// One edition's text for ONE chapter, keyed by verse number.
class EditionText {
  const EditionText({this.verses = const {}});
  final Map<int, String> verses;
}

/// State for the compare page.
///
/// Performance idea: the Tauri version opened a database and ran a query on
/// every Next/Prev tap. Here each edition is read ONCE (the whole chapter in a
/// single query), the db is closed straight away, and everything after that
/// (paging, switching mode) is just a Map lookup in memory.
class CompareController extends ChangeNotifier {
  CompareController({
    required this._store,
    required this.startId,
    required this.bookId,
    required this.chapter,
    required this.bookName,
    required List<int> selectedVerses,
  }) : selectedVerses = List.unmodifiable(
         selectedVerses.toSet().toList()..sort(),
       ),
       _verse = selectedVerses.reduce((a, b) => a < b ? a : b),
       _verseCount = selectedVerses.reduce((a, b) => a > b ? a : b),
       _active = {startId},
       installed = [startId];

  final TranslationStore _store;
  final String startId;
  final String bookId;
  final int chapter;
  final String bookName;
  final List<int> selectedVerses;

  /// Every installed edition id (without ".dba").
  final List<String> installed;

  final Set<String> _active;
  final Map<String, EditionText> _cache = {};
  final Set<String> _loading = {};

  CompareMode _mode = CompareMode.selected;
  int _verse;
  int _verseCount;
  bool _disposed = false;

  // ---- Read-only state for the UI ----------------------------------------

  CompareMode get mode => _mode;
  int get verse => _verse;
  int get verseCount => _verseCount;
  bool get canPrev => _verse > 1;
  bool get canNext => _verse < _verseCount;

  int get activeCount => _active.length;
  bool isActive(String id) => _active.contains(id);

  /// Active editions in the same order as the picker list.
  List<String> get activeIds => [
    for (final id in installed)
      if (_active.contains(id)) id,
  ];

  /// null = still loading.
  EditionText? dataFor(String id) => _cache[id];

  String get title => _mode == CompareMode.selected
      ? '$bookName Chapter $chapter'
      : '$bookName $chapter:$_verse';

  /// "John 7:3-5, 8" from a sorted, non-empty list of verse numbers.
  String referenceFor(List<int> verses) {
    final runs = <String>[];
    var start = verses.first;
    var prev = verses.first;
    for (final v in verses.skip(1)) {
      if (v == prev + 1) {
        prev = v;
        continue;
      }
      runs.add(start == prev ? '$start' : '$start-$prev');
      start = v;
      prev = v;
    }
    runs.add(start == prev ? '$start' : '$start-$prev');
    return '$bookName $chapter:${runs.join(', ')}';
  }

  // ---- Actions ------------------------------------------------------------

  Future<void> init() async {
    unawaited(_load(startId)); // show the first card as fast as possible
    try {
      final ids = (await _store.installedIds()).toList()..sort();
      if (!ids.contains(startId)) ids.insert(0, startId);
      installed
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (e) {
      debugPrint('CompareController.init failed: $e');
    }
  }

  void setMode(CompareMode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }

  void prevVerse() {
    if (!canPrev) return;
    _verse--;
    notifyListeners();
  }

  void nextVerse() {
    if (!canNext) return;
    _verse++;
    notifyListeners();
  }

  void toggle(String id) {
    if (!_active.remove(id)) {
      _active.add(id);
      unawaited(_load(id));
    }
    notifyListeners();
  }

  void selectAll() {
    _active.addAll(installed);
    notifyListeners();
    for (final id in installed) {
      unawaited(_load(id));
    }
  }

  void selectNone() {
    if (_active.isEmpty) return;
    _active.clear();
    notifyListeners();
  }

  // ---- Loading ------------------------------------------------------------

  /// Reads the whole chapter for one edition (once; later calls are no-ops).
  Future<void> _load(String id) async {
    if (_cache.containsKey(id) || !_loading.add(id)) return;

    EditionText result = const EditionText();
    try {
      final file = await _store.fileFor(id);
      final db = sqlite3lib.sqlite3.open(
        file.path,
        mode: sqlite3lib.OpenMode.readOnly,
      );
      try {
        final rows = db.select(
          'SELECT number, text FROM ChapterVerse '
          'WHERE bookId = ? AND chapterNumber = ?',
          [bookId, chapter],
        );
        result = EditionText(
          verses: {
            for (final r in rows)
              r['number'] as int: (r['text'] ?? '').toString(),
          },
        );
      } finally {
        db.close(); // nothing stays open, so nothing to leak
      }
    } catch (e) {
      debugPrint('Compare: could not read $id: $e');
    }

    _cache[id] = result;
    _loading.remove(id);

    // The edition you started from decides how far "Next" can go.
    if (id == startId && result.verses.isNotEmpty) {
      _verseCount = result.verses.keys.reduce((a, b) => a > b ? a : b);
    }
    notifyListeners();
  }

  // Loading is async, so the page may be gone before a load finishes.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
