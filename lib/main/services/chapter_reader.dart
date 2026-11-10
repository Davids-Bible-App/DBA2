import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

import '../models/chapter_model.dart';

/// Reads one chapter from any Bible database.
/// Shared by BibleController (primary pane) and TranslationPane (the others),
/// so every pane parses chapters identically.
class ChapterReader {
  const ChapterReader._();

  static ChapterData read(
    sqlite3lib.Database db,
    String bookId,
    int chapter,
  ) {
    // A) Pre-compiled chapter JSON
    try {
      final rows = db.select(
        'SELECT json FROM Chapter WHERE bookId = ? AND number = ?',
        [bookId, chapter],
      );
      if (rows.isNotEmpty) {
        return ChapterData.fromJson(
          jsonDecode(rows.first['json'] as String) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      debugPrint('Chapter JSON unavailable, using ChapterVerse: $e');
    }

    // B) Fallback: build from ChapterVerse
    final rows = db.select(
      'SELECT number, text FROM ChapterVerse '
      'WHERE bookId = ? AND chapterNumber = ? ORDER BY number ASC',
      [bookId, chapter],
    );

    if (rows.isEmpty) {
      return ChapterData(
        items: [ErrorItem('Chapter $chapter not found in any table.')],
        footnotes: const [],
      );
    }

    return ChapterData(
      items: [
        for (final row in rows)
          VerseItem(
            number: row['number'] as int,
            parts: [TextPart((row['text'] ?? '').toString())],
          ),
      ],
      footnotes: const [],
    );
  }
}
