import 'package:flutter/widgets.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

import '../models/bible_book.dart';
import '../models/chapter_model.dart';
import '../services/translation_catalog.dart';
import '../services/chapter_reader.dart';
import '../services/translation_store.dart';

enum PaneStatus { loading, ready, missingBook, missingChapter, error }

/// One extra reading pane (everything except the primary, which stays in
/// BibleController). Has its own read-only db handle and scroll controller.
class TranslationPane {
  TranslationPane._(this.id);

  final String id;
  final ScrollController scroll = ScrollController();

  sqlite3lib.Database? _db;

  PaneStatus status = PaneStatus.loading;
  String? message;

  /// This translation's own Book row (its own language/title).
  BibleBook? book;
  ChapterData? data;
  int chapterNumber = 0;

  Translation get info => translationFor(id);

  static Future<TranslationPane> open(String id, TranslationStore store) async {
    final pane = TranslationPane._(id);
    try {
      final file = await store.fileFor(id);
      if (!file.existsSync()) throw StateError('File not found');
      pane._db = sqlite3lib.sqlite3.open(
        file.path,
        mode: sqlite3lib.OpenMode.readOnly,
      );
    } catch (e) {
      pane.status = PaneStatus.error;
      pane.message = '$e';
    }
    return pane;
  }

  /// Loads book + chapter, or records why this translation can't show it.
  void load(String bookId, int chapter) {
    final db = _db;
    if (db == null) return;
    chapterNumber = chapter;
    try {
      final rows = db.select(
        'SELECT id, englishName, name, title, numberOfChapters, "order" '
        'FROM Book WHERE id = ?',
        [bookId],
      );
      if (rows.isEmpty) {
        book = null;
        data = null;
        status = PaneStatus.missingBook;
        return;
      }
      book = BibleBook.fromMap(rows.first);
      if (chapter < 1 || chapter > book!.numberOfChapters) {
        data = null;
        status = PaneStatus.missingChapter;
        return;
      }
      data = ChapterReader.read(db, bookId, chapter);
      status = PaneStatus.ready;
    } catch (e) {
      status = PaneStatus.error;
      message = '$e';
    }
  }

  /// Clean verse text (used when copying a selection made in this pane).
  String verseText(String bk, int ch, int vs) {
    final db = _db;
    if (db == null) return '';
    final rows = db.select(
      'SELECT text FROM ChapterVerse '
      'WHERE bookId = ? AND chapterNumber = ? AND number = ?',
      [bk, ch, vs],
    );
    return rows.isEmpty ? '' : (rows.first['text'] ?? '').toString();
  }

  void dispose() {
    _db?.close();
    _db = null;
    scroll.dispose();
  }
}
