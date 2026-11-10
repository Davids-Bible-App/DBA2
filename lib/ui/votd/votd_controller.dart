import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

import '../../main/controllers/bible_controller.dart';
import '../translations/services/translation_catalog.dart';
import '../translations/services/translation_store.dart';

class VotdController extends ChangeNotifier with WidgetsBindingObserver {
  VotdController(this._prefs, this._bible, this._store);

  final SharedPreferences _prefs;
  final BibleController _bible;
  final TranslationStore _store;
  final _random = math.Random();

  static const _kDate = 'votd.date';
  static const _kBook = 'votd.book';
  static const _kChapter = 'votd.chapter';
  static const _kVerse = 'votd.verse';

  String bookId = '';
  int chapter = 0;
  int verse = 0;
  String reference = '';
  String text = '';

  bool get hasPick => bookId.isNotEmpty;

  String _resolvedFor = ''; // translation the text was last read from
  String _pickedKey = ''; // date the current pick belongs to
  int _token = 0; // drops stale async results
  Timer? _midnight;

  void init() {
    WidgetsBinding.instance.addObserver(this);
    _bible.addListener(_onBible);
    _scheduleMidnight();
    _onBible();
  }

  // ---- Triggers -----------------------------------------------------------

  /// Fires when the app returns to the foreground (the "week later" case).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _scheduleMidnight(); // the old timer may never have fired
    if (_todayKey() != _pickedKey) _ensureToday();
  }

  // Only react when a (new) translation has finished loading.
  void _onBible() {
    if (!_bible.hasTranslation || _bible.isLoading || _bible.books.isEmpty) {
      return;
    }
    if (_resolvedFor == _bible.translationId) return;
    _resolvedFor = _bible.translationId;
    _ensureToday();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      _ensureToday();
      _scheduleMidnight();
    });
  }

  // ---- Picking ------------------------------------------------------------

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  void _ensureToday() {
    // Nothing to do until a translation is open.
    if (!_bible.hasTranslation || _bible.isLoading || _bible.books.isEmpty) {
      return;
    }
    final key = _todayKey();
    final storedBook = _prefs.getString(_kBook);
    final fresh =
        _prefs.getString(_kDate) == key &&
        storedBook != null &&
        storedBook.isNotEmpty;

    if (fresh) {
      bookId = storedBook;
      chapter = _prefs.getInt(_kChapter) ?? 1;
      verse = _prefs.getInt(_kVerse) ?? 1;
    } else if (!_generate(key)) {
      return;
    }
    _pickedKey = key;
    unawaited(_resolveText());
  }

  bool _generate(String key) {
    final books = _bible.books.where((b) => b.order <= 66).toList();
    if (books.isEmpty) return false;

    for (var attempt = 0; attempt < 8; attempt++) {
      final book = books[_random.nextInt(books.length)];
      if (book.numberOfChapters < 1) continue;
      final ch = 1 + _random.nextInt(book.numberOfChapters);
      final count = _bible.verseCount(book.id, ch);
      if (count < 1) continue;
      final vs = 1 + _random.nextInt(count);
      if (_bible.passageText(book.id, ch, vs, vs).isEmpty) continue;

      bookId = book.id;
      chapter = ch;
      verse = vs;
      _prefs.setString(_kDate, key);
      _prefs.setString(_kBook, bookId);
      _prefs.setInt(_kChapter, chapter);
      _prefs.setInt(_kVerse, verse);
      return true;
    }
    return false;
  }

  // ---- Text (current translation, then the default as a fallback) ---------

  Future<void> _resolveText() async {
    final token = ++_token;
    final name = _bible.books
        .where((b) => b.id == bookId)
        .map((b) => b.englishName)
        .firstOrNull;
    final base = '${name ?? bookId} $chapter:$verse';

    var body = _bible.passageText(bookId, chapter, verse, verse);
    var label = base;

    if (body.isEmpty) {
      body = await _fallbackText();
      if (body.isNotEmpty) {
        label = '$base (${translationFor(kDefaultTranslationId).abbr})';
      }
    }
    if (token != _token) return; // a newer resolve has started

    reference = label;
    text = body;
    notifyListeners();
  }

  /// Reads one verse straight from the default translation's file.
  Future<String> _fallbackText() async {
    if (_bible.translationId == kDefaultTranslationId) return '';
    sqlite3lib.Database? db;
    try {
      final installed = await _store.installedIds();
      if (!installed.contains(kDefaultTranslationId)) return '';
      final file = await _store.fileFor(kDefaultTranslationId);
      db = sqlite3lib.sqlite3.open(
        file.path,
        mode: sqlite3lib.OpenMode.readOnly,
      );
      final rows = db.select(
        'SELECT text FROM ChapterVerse '
        'WHERE bookId = ? AND chapterNumber = ? AND number = ?',
        [bookId, chapter, verse],
      );
      return rows.isEmpty ? '' : (rows.first['text'] ?? '').toString();
    } catch (e) {
      debugPrint('VOTD fallback failed: $e');
      return '';
    } finally {
      db?.close();
    }
  }

  /// Opens the verse in the reader (scroll + glow via VerseGoto).
  void open() {
    if (hasPick) _bible.goTo(bookId, chapter, verse: verse);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    _bible.removeListener(_onBible);
    super.dispose();
  }
}
