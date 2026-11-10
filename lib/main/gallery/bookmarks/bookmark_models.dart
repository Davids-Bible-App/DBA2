import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One verse inside a bookmark. Same shape as the old {tr, bk, ch, vs}.
@immutable
class BookmarkVerse {
  const BookmarkVerse({
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.verse,
  });

  final String translationId;
  final String bookId;
  final int chapter;
  final int verse;

  Map<String, dynamic> toJson() => {
    'tr': translationId,
    'bk': bookId,
    'ch': chapter,
    'vs': verse,
  };

  factory BookmarkVerse.fromJson(Map<String, dynamic> j) => BookmarkVerse(
    translationId: '${j['tr'] ?? ''}',
    bookId: '${j['bk']}',
    chapter: int.parse('${j['ch']}'),
    verse: int.parse('${j['vs']}'),
  );
}

@immutable
class Bookmark {
  const Bookmark({
    required this.id,
    required this.title,
    required this.verses,
    required this.updatedAt,
    this.sortOrder = 0,
  });

  final int id;
  final String title;
  final List<BookmarkVerse> verses;
  final int sortOrder;
  final DateTime updatedAt;

  Bookmark copyWith({
    String? title,
    List<BookmarkVerse>? verses,
    int? sortOrder,
    DateTime? updatedAt,
  }) => Bookmark(
    id: id,
    title: title ?? this.title,
    verses: verses ?? this.verses,
    sortOrder: sortOrder ?? this.sortOrder,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  // --- profile.db helpers (verses stay a JSON text column, as before) ---
  String get versesJson => jsonEncode([for (final v in verses) v.toJson()]);

  static List<BookmarkVerse> parseVerses(String? json) {
    try {
      final list = jsonDecode(json ?? '[]') as List;
      return [
        for (final e in list) BookmarkVerse.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  factory Bookmark.fromRow(Map<String, Object?> r) => Bookmark(
    id: r['id'] as int,
    title: r['title'] as String,
    verses: parseVerses(r['verses'] as String?),
    sortOrder: (r['sort_order'] as int?) ?? 0,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      ((r['updated_at'] as int?) ?? 0) * 1000,
    ),
  );
}

/// [1,3,4,5,9,11] -> "1, 3-5, 9, 11"
String compressVerses(Iterable<int> vss) {
  final s = vss.toSet().toList()..sort();
  if (s.isEmpty) return '';
  final out = <String>[];
  var start = s.first, end = s.first;
  void flush() => out.add(start == end ? '$start' : '$start-$end');
  for (final n in s.skip(1)) {
    if (n == end + 1) {
      end = n;
    } else {
      flush();
      start = end = n;
    }
  }
  flush();
  return out.join(', ');
}

/// "KJV  ·  Luke 1:1, 3-5  ·  John 3:16"
String formatVerseRefs(
  List<BookmarkVerse> verses, {
  required String Function(String bookId) bookName,
  String Function(String translationId)? translationLabel,
}) {
  if (verses.isEmpty) return '';
  final groups = <String, List<int>>{}; // insertion-ordered
  final keys = <String, (String, int)>{};
  for (final v in verses) {
    final k = '${v.bookId}|${v.chapter}';
    keys[k] = (v.bookId, v.chapter);
    (groups[k] ??= []).add(v.verse);
  }
  final parts = [
    for (final e in groups.entries)
      '${bookName(keys[e.key]!.$1)} ${keys[e.key]!.$2}:${compressVerses(e.value)}',
  ];
  final tr = verses.first.translationId;
  final label = translationLabel?.call(tr) ?? tr;
  return '$label  ·  ${parts.join('  ·  ')}';
}
