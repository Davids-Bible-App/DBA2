import 'package:flutter/material.dart';

/// "eng_kjv.dba" -> "KJV"
String abbreviate(String? v) {
  if (v == null) return '';
  return v
      .replaceFirst(RegExp(r'\.dba$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^[a-z]{3}_', caseSensitive: false), '')
      .toUpperCase();
}

/// "eng_kjv.dba" -> "eng_kjv"
String normalizeTranslationId(String v) =>
    v.replaceFirst(RegExp(r'\.dba$', caseSensitive: false), '');

Color? _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? null : Color(v);
}

/// One row from `get_global_gallery` (topic verse or note).
@immutable
class GalleryEntry {
  const GalleryEntry({
    required this.id,
    required this.entryType,
    required this.translationId,
    required this.bookId,
    required this.bookName,
    required this.chapter,
    required this.verseId,
    required this.text,
    this.topic,
    this.note,
    this.highlight,
  });

  final int id;
  final String entryType; // 'topic' | 'note'
  final String? topic;
  final String translationId;
  final String bookId;
  final String bookName;
  final int chapter;
  final int verseId;
  final String text;
  final String? note;
  final Color? highlight;

  String get abbr => abbreviate(translationId);

  factory GalleryEntry.fromJson(Map<String, dynamic> j) => GalleryEntry(
    id: j['id'] as int,
    entryType: (j['entry_type'] as String?) ?? 'topic',
    topic: j['topic'] as String?,
    translationId: j['translation_id'] as String,
    bookId: j['book_id'] as String,
    bookName: (j['book_name'] as String?) ?? j['book_id'] as String,
    chapter: j['chapter'] as int,
    verseId: j['verse_id'] as int,
    text: j['text'] as String,
    note: j['note'] as String?,
    highlight: _parseColor(j['highlight'] as String?),
  );

  GalleryEntry copyWith({
    int? id,
    String? entryType,
    String? topic,
    String? note,
  }) => GalleryEntry(
    id: id ?? this.id,
    entryType: entryType ?? this.entryType,
    topic: topic ?? this.topic,
    translationId: translationId,
    bookId: bookId,
    bookName: bookName,
    chapter: chapter,
    verseId: verseId,
    text: text,
    note: note ?? this.note,
    highlight: highlight,
  );
}

/// One row from `get_topics_metadata`.
@immutable
class TopicMeta {
  const TopicMeta({
    required this.topic,
    required this.count,
    required this.updated,
  });

  final String topic;
  final int count;
  final int updated; // unix seconds

  factory TopicMeta.fromJson(Map<String, dynamic> j) => TopicMeta(
    topic: j['topic'] as String,
    count: j['count'] as int,
    updated: j['updated'] as int,
  );
}
