import 'dart:async';

import 'package:dba2/services/chapter_reader.dart';
import 'package:dba2/widgets/reader_gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

import '../models/bible_book.dart';
import '../models/chapter_model.dart';
import '../models/translation.dart';
import '../services/translation_store.dart';
import '../ui/verse_selection.dart';

const bool kDebugDbSchema = false;

// ---------------------------------------------------------------------------
// CONTROLLER: the one source of truth for the database and the selection.
// ---------------------------------------------------------------------------

class BibleController extends ChangeNotifier {
  BibleController(this._prefs, this._store);
  final SharedPreferences _prefs;
  final TranslationStore _store;

  static const _kBook = 'readerBook';
  static const _kChapter = 'readerChapter';
  static const _kTranslation = 'readerTranslation';

  final List<BibleBook> books = [];
  ChapterData? chapter;
  bool isLoading = true;
  String? error;
  String selectedBookId = '';
  int selectedChapter = 1;

  /// Currently open translation id ('' = none yet).
  String translationId = '';

  /// True when no .dba is on the device: the reader shows the placeholder.
  bool needsTranslation = false;

  bool get hasTranslation => translationId.isNotEmpty;

  /// 3-4 letter abbreviation (ribbon + VerseRef.ed).
  String get edition =>
      hasTranslation ? translationFor(translationId).abbr : '---';

  final ReaderFontSize fontSize = ReaderFontSize(initialPx: 18.0);
  final ScrollController readerScroll = ScrollController();

  bool _stickyHeader = true;
  bool get stickyHeader => _stickyHeader;

  void setStickyHeader(bool value) {
    if (_stickyHeader == value) return;
    _stickyHeader = value;
    notifyListeners();
  }

  final VerseSelection selection = VerseSelection();
  final HighlightStore highlights = HighlightStore();

  sqlite3lib.Database? _db;

  BibleBook? get currentBook {
    for (final b in books) {
      if (b.id == selectedBookId) return b;
    }
    return books.isEmpty ? null : books.first;
  }

  // ---- Startup ------------------------------------------------------------

  Future<void> init() async {
    try {
      // Remember where the reader was (applied after the db opens).
      selectedBookId = _prefs.getString(_kBook) ?? '';
      selectedChapter = _prefs.getInt(_kChapter) ?? 1;

      final installed = await _store.installedIds();
      final saved = _prefs.getString(_kTranslation);

      final String? id = installed.contains(saved)
          ? saved
          : installed.contains(kDefaultTranslationId)
          ? kDefaultTranslationId
          : (installed.isEmpty ? null : installed.first);

      if (id == null) {
        needsTranslation = true;
        isLoading = false;
        notifyListeners();
        return;
      }
      await setTranslation(id);
    } catch (e) {
      error = 'Unable to load the Bible database: $e';
      isLoading = false;
      notifyListeners();
    }
  }

  // ---- Switching translation ---------------------------------------------

  /// Opens `<id>.dba`, keeps the current book/chapter when the new
  /// translation has it (falls back to the first book otherwise), and
  /// remembers the choice.
  Future<void> setTranslation(String id) async {
    if (id == translationId && _db != null) return;

    isLoading = true;
    error = null;
    notifyListeners();

    sqlite3lib.Database? opened;
    try {
      final file = await _store.fileFor(id);
      if (!file.existsSync()) {
        throw StateError('${file.path} is missing');
      }
      opened = sqlite3lib.sqlite3.open(
        file.path,
        mode: sqlite3lib.OpenMode.readOnly,
      );
      if (kDebugDbSchema) _dumpSchema(opened);

      final rows = opened.select(
        'SELECT id, englishName, name, title, numberOfChapters, "order" '
        'FROM Book ORDER BY "order"',
      );
      final newBooks = rows.map((r) => BibleBook.fromMap(r)).toList();
      if (newBooks.isEmpty) {
        throw StateError('No books found in this translation.');
      }

      // New db is good: swap.
      _db?.close();
      _db = opened;
      opened = null;

      books
        ..clear()
        ..addAll(newBooks);
      translationId = id;
      needsTranslation = false;

      final match = books.where((b) => b.id == selectedBookId);
      if (match.isNotEmpty) {
        selectedChapter = selectedChapter.clamp(
          1,
          match.first.numberOfChapters,
        );
      } else {
        selectedBookId = books.first.id;
        selectedChapter = 1;
      }

      unawaited(_prefs.setString(_kTranslation, id));
      _loadChapter();
    } catch (e) {
      opened?.close();
      // Keep the old translation usable if there was one.
      error = _db == null ? 'Unable to open translation "$id": $e' : null;
      isLoading = false;
      notifyListeners();
    }
  }

  void _dumpSchema(sqlite3lib.Database db) {
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    for (final t in tables) {
      final name = t['name'] as String;
      final cols = db
          .select('PRAGMA table_info("$name")')
          .map((c) => '${c['name']} ${c['type']}')
          .join(', ');
      debugPrint('DB TABLE $name: $cols');
    }
  }

  // ---- Navigation ---------------------------------------------------------

  void goTo(String bookId, int chapterNumber) {
    if (_db == null) return;
    selectedBookId = bookId;
    selectedChapter = chapterNumber;
    _loadChapter();
  }

  bool previous() {
    final i = books.indexWhere((b) => b.id == selectedBookId);
    if (i == -1) return false;

    if (selectedChapter > 1) {
      selectedChapter--;
    } else {
      if (i == 0) return false;
      final prev = books[i - 1];
      selectedBookId = prev.id;
      selectedChapter = prev.numberOfChapters;
    }
    _loadChapter();
    return true;
  }

  bool next() {
    final i = books.indexWhere((b) => b.id == selectedBookId);
    if (i == -1) return false;

    if (selectedChapter < books[i].numberOfChapters) {
      selectedChapter++;
    } else {
      if (i == books.length - 1) return false;
      final nextBook = books[i + 1];
      selectedBookId = nextBook.id;
      selectedChapter = 1;
    }
    _loadChapter();
    return true;
  }

  void _loadChapter() {
    selection.clear();
    chapter = _readChapter();

    isLoading = false;
    notifyListeners();

    unawaited(_persistReaderPosition());
  }

  Future<void> _persistReaderPosition() async {
    try {
      await _prefs.setString(_kBook, selectedBookId);
      await _prefs.setInt(_kChapter, selectedChapter);
    } catch (e) {
      debugPrint('Unable to save reader position: $e');
    }
  }

  ChapterData _readChapter() =>
      ChapterReader.read(_db!, selectedBookId, selectedChapter);

  // ---- Selection helpers --------------------------------------------------

  /// Set by SplitController: reads verses from the other panes' databases.
  String Function(String tr, String bk, int ch, int vs)? externalVerseText;

  String verseText(VerseRef r) {
    if (r.tr != translationId && externalVerseText != null) {
      return externalVerseText!(r.tr, r.bk, r.ch, r.vs);
    }
    final rows = _db!.select(
      'SELECT text FROM ChapterVerse '
      'WHERE bookId = ? AND chapterNumber = ? AND number = ?',
      [r.bk, r.ch, r.vs],
    );
    return rows.isEmpty ? '' : (rows.first['text'] ?? '').toString();
  }

  String _groupLabel(List<VerseRef> g) {
    final name = books
        .firstWhere((b) => b.id == g.first.bk, orElse: () => books.first)
        .englishName;
    final range = g.length == 1
        ? '${g.first.vs}'
        : '${g.first.vs}-${g.last.vs}';
    return '$name ${g.first.ch}:$range';
  }

  String selectionLabel() =>
      groupVerses(selection.sorted).map(_groupLabel).join(', ');

  String selectionAsText({bool wrap = true}) {
    final groups = groupVerses(selection.sorted).map((g) {
      final single = g.length == 1;
      final body = g
          .map((r) => single ? verseText(r) : '${r.vs}. ${verseText(r)}')
          .join(wrap ? ' ' : '\n');
      return '${_groupLabel(g)}  (${g.first.ed})\n$body';
    });
    return groups.join('\n\n');
  }

  @override
  void dispose() {
    fontSize.dispose();
    readerScroll.dispose();
    selection.dispose();
    highlights.dispose();
    _db?.close();
    super.dispose();
  }
}
