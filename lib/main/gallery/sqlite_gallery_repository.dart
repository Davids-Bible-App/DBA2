import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:dba2/storage/profile/profile.dart';
import 'package:dba2/ui/translations/services/translation_store.dart';

import 'models.dart';

typedef VerseKey = ({String tr, String bk, int ch, int vs});

/// Reads verse text out of the installed `<id>.dba` files.
/// Opens each translation only for the duration of one lookup.
class VerseTextLookup {
  VerseTextLookup(this._store);
  final TranslationStore _store;

  /// Same order as [refs]; '' when the translation/verse isn't available.
  Future<List<String>> texts(List<VerseKey> refs) async {
    final out = List<String>.filled(refs.length, '');
    final byTr = <String, List<int>>{};
    for (var i = 0; i < refs.length; i++) {
      byTr.putIfAbsent(refs[i].tr, () => []).add(i);
    }
    for (final entry in byTr.entries) {
      if (entry.key.isEmpty) continue;
      sqlite3.Database? db;
      try {
        final file = await _store.fileFor(entry.key);
        if (!file.existsSync()) continue;
        db = sqlite3.sqlite3.open(file.path, mode: sqlite3.OpenMode.readOnly);
        for (final i in entry.value) {
          final r = refs[i];
          final rows = db.select(
            'SELECT text FROM ChapterVerse '
            'WHERE bookId = ? AND chapterNumber = ? AND number = ?',
            [r.bk, r.ch, r.vs],
          );
          if (rows.isNotEmpty) out[i] = (rows.first['text'] ?? '').toString();
        }
      } catch (e) {
        debugPrint('VerseTextLookup(${entry.key}): $e');
      } finally {
        db?.close();
      }
    }
    return out;
  }
}

class SqliteGalleryRepository implements GalleryRepository {
  SqliteGalleryRepository(this._profile, this._verseText);

  final ProfileRepository _profile;
  final VerseTextLookup _verseText;
  Map<String, String>? _bookNames;

  // profile.db keeps translation ids as "eng_kjv.dba" (same as highlights).
  static String _dbTr(String id) =>
      id.toLowerCase().endsWith('.dba') ? id : '$id.dba';

  static int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Future<Map<String, String>> _books() async => _bookNames ??= {
    for (final r in await _profile.getBooks())
      r['id'] as String: (r['englishName'] as String?) ?? r['id'] as String,
  };

  Future<List<GalleryEntry>> _toEntries(
    List<Map<String, Object?>> rows, {
    required String type,
    String? topic,
  }) async {
    final books = await _books();
    final texts = await _verseText.texts([
      for (final r in rows)
        (
          tr: normalizeTranslationId((r['translation_id'] as String?) ?? ''),
          bk: (r['book_id'] as String?) ?? '',
          ch: (r['chapter'] as int?) ?? 0,
          vs: (r['verse_id'] as int?) ?? 0,
        ),
    ]);
    return [
      for (var i = 0; i < rows.length; i++)
        GalleryEntry(
          id: rows[i]['id'] as int,
          entryType: type,
          topic: (rows[i]['topic'] as String?) ?? topic,
          translationId: (rows[i]['translation_id'] as String?) ?? '',
          bookId: (rows[i]['book_id'] as String?) ?? '',
          bookName:
              (rows[i]['book_name'] as String?) ??
              books[rows[i]['book_id']] ??
              (rows[i]['book_id'] as String? ?? ''),
          chapter: (rows[i]['chapter'] as int?) ?? 0,
          verseId: (rows[i]['verse_id'] as int?) ?? 0,
          text: texts[i],
          note: rows[i]['note'] as String?,
        ),
    ];
  }

  // ── reads ────────────────────────────────────────────────────────────────
  @override
  Future<List<TopicMeta>> getTopicsMetadata() async => [
    for (final r in await _profile.getTopics())
      TopicMeta(
        topic: r['topic'] as String,
        count: (r['count'] as int?) ?? 0,
        updated: (r['updated'] as int?) ?? 0,
      ),
  ];

  @override
  Future<List<GalleryEntry>> getGallery({
    required String type,
    String topic = 'All',
    bool resetSort = false,
  }) async {
    final isTopic = type == 'topic';
    final specific = isTopic && topic != 'All';
    final rows = specific && !resetSort
        // the user's drag order (verse_sort)
        ? await _profile.getTopicVerses(topic)
        // Biblical order (book order, chapter, verse)
        : await _profile.getGallery(
            entryType: type,
            topic: isTopic ? topic : null,
          );
    return _toEntries(rows, type: type, topic: specific ? topic : null);
  }

  @override
  Future<String> getTopicDescription(String topic) =>
      _profile.getTopicDescription(topic);

  // ── writes ───────────────────────────────────────────────────────────────
  @override
  Future<void> addToTopic(String topic, List<GalleryEntry> verses) =>
      _profile.saveVersesToTopic(
        topic: topic,
        verses: [
          for (final v in verses)
            VerseReference(
              translationId: _dbTr(v.translationId),
              bookId: v.bookId,
              chapter: v.chapter,
              verseId: v.verseId,
            ),
        ],
      );

  @override
  Future<void> addNote(GalleryEntry verse, String note) => _profile.saveNote(
    translationId: _dbTr(verse.translationId),
    bookId: verse.bookId,
    chapter: verse.chapter,
    verseId: verse.verseId,
    note: note,
  );

  @override
  Future<void> saveNoteById(int id, String note) async {
    final db = await _profile.profileDatabase.database;
    await db.update(
      'notes',
      {'note': note, 'updated_at': _now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteEntries(String type, List<int> ids) async {
    if (ids.isEmpty) return;
    final table = switch (type) {
      'topic' || 'topics' => 'topics',
      'note' || 'notes' => 'notes',
      'highlight' || 'highlights' => 'highlights',
      _ => throw ArgumentError.value(type, 'type', 'topic, note or highlight'),
    };
    final db = await _profile.profileDatabase.database;
    await db.rawDelete(
      'DELETE FROM $table WHERE id IN (${List.filled(ids.length, '?').join(',')})',
      ids,
    );
  }

  /// If [newName] already exists the two topics are merged (instead of
  /// crashing on the UNIQUE constraint); the target's description wins.
  @override
  Future<void> renameTopic(String oldName, String newName) async {
    if (oldName == newName) return;
    final db = await _profile.profileDatabase.database;
    await db.transaction((tx) async {
      await tx.rawUpdate(
        'UPDATE OR IGNORE topics SET topic = ?, updated_at = ? WHERE topic = ?',
        [newName, _now, oldName],
      );
      await tx.rawDelete('DELETE FROM topics WHERE topic = ?', [oldName]);
      await tx.rawUpdate(
        'UPDATE OR IGNORE topic_metadata SET topic = ?, updated_at = ? '
        'WHERE topic = ?',
        [newName, _now, oldName],
      );
      await tx.rawDelete(
        'DELETE FROM topic_metadata WHERE topic = ?',
        [oldName],
      );
    });
  }

  @override
  Future<void> deleteTopic(String topic) => _profile.deleteTopic(topic);

  @override
  Future<void> updateTopicsOrder(List<String> ordered) =>
      _profile.updateTopicOrder(ordered);

  @override
  Future<void> updateVersesOrder(List<int> orderedIds) =>
      _profile.updateVerseOrder(orderedIds);

  @override
  Future<void> saveTopicDescription(String topic, String text) =>
      _profile.saveTopicDescription(topic, text);
}

abstract class GalleryRepository {
  Future<List<TopicMeta>> getTopicsMetadata(); // get_topics_metadata
  Future<List<GalleryEntry>> getGallery({
    required String type, // 'topic' | 'note'
    String topic = 'All',
    bool resetSort = false,
  }); // get_global_gallery
  Future<void> deleteEntries(
    String type,
    List<int> ids,
  ); // delete_gallery_entry
  Future<void> saveNoteById(int id, String note); // save_note_by_id
  Future<void> renameTopic(String oldName, String newName); // rename_topic
  Future<void> deleteTopic(String topic); // delete_topic
  Future<void> updateTopicsOrder(List<String> ordered); // update_topics_order
  Future<void> updateVersesOrder(List<int> orderedIds); // update_verses_order
  Future<String> getTopicDescription(String topic); // get_topic_description
  Future<void> saveTopicDescription(
    String topic,
    String text,
  ); // save_topic_description
  Future<void> addToTopic(String topic, List<GalleryEntry> verses);
  Future<void> addNote(GalleryEntry verse, String note);
}
