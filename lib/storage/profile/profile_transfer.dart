import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'profile.dart';

/// Export / import of the whole profile.db.
class ProfileTransfer {
  ProfileTransfer(this.repo);
  final ProfileRepository repo;

  static const _wipeOrder = [
    'highlights',
    'notes',
    'topics',
    'topic_metadata',
    'bookmarks',
    'settings',
    'read_history',
    'search_history',
    'context_history',
    'MemeTemplates',
    'md_store',
  ];

  static String _quote(String s) => "'${s.replaceAll("'", "''")}'";

  /// A clean single-file copy of the current database.
  Future<Uint8List> exportBytes() async {
    final db = await repo.profileDatabase.database;
    final tmp = await getTemporaryDirectory();
    final out = File(p.join(tmp.path, 'profile_export.db'));
    if (out.existsSync()) out.deleteSync();
    await db.execute('VACUUM INTO ${_quote(out.path)}');
    final bytes = await out.readAsBytes();
    await out.delete();
    return bytes;
  }

  /// Copies data from the SQLite file at [sourcePath] into profile.db.
  /// merge = true : keep current data, newer updated_at wins on conflicts.
  /// merge = false: erase current data first, then copy everything.
  Future<void> importFile(String sourcePath, {required bool merge}) async {
    // 1. Is it really a SQLite file?
    final raf = await File(sourcePath).open();
    final header = await raf.read(16);
    await raf.close();
    if (String.fromCharCodes(header) != 'SQLite format 3\u0000') {
      throw const FormatException('That is not a SQLite database file.');
    }

    // 2. Work on a private copy (picked files can be odd paths on Android).
    final tmpDir = await getTemporaryDirectory();
    final copy = await File(sourcePath)
        .copy(p.join(tmpDir.path, 'profile_import.db'));

    final db = await repo.profileDatabase.database;
    await db.execute('ATTACH DATABASE ${_quote(copy.path)} AS imp');
    try {
      final tables = (await db.rawQuery(
        "SELECT name FROM imp.sqlite_master WHERE type = 'table'",
      )).map((r) => r['name'] as String).toSet();

      final topicCols = tables.contains('topics')
          ? (await db.rawQuery('PRAGMA imp.table_info(topics)'))
                .map((r) => r['name'] as String)
                .toSet()
          : <String>{};
      String col(String name) => topicCols.contains(name) ? 'i.$name' : '0';

      await db.transaction((tx) async {
        if (!merge) {
          for (final t in _wipeOrder) {
            await tx.execute('DELETE FROM $t');
          }
        }

        Future<void> copyTable(String table, String sql) async {
          if (tables.contains(table)) await tx.execute(sql);
        }

        // NOTE: "WHERE 1" is required by SQLite before ON CONFLICT.
        await copyTable('highlights', '''
          INSERT INTO highlights
            (translation_id, book_id, chapter, verse_id, color, updated_at)
          SELECT i.translation_id, i.book_id, i.chapter, i.verse_id, i.color,
                 COALESCE(i.updated_at, strftime('%s','now'))
          FROM imp.highlights i WHERE 1
          ON CONFLICT(translation_id, book_id, chapter, verse_id) DO UPDATE
            SET color = excluded.color, updated_at = excluded.updated_at
            WHERE excluded.updated_at > highlights.updated_at
        ''');

        await copyTable('notes', '''
          INSERT INTO notes
            (translation_id, book_id, chapter, verse_id, note, updated_at)
          SELECT i.translation_id, i.book_id, i.chapter, i.verse_id, i.note,
                 COALESCE(i.updated_at, strftime('%s','now'))
          FROM imp.notes i WHERE 1
          ON CONFLICT(translation_id, book_id, chapter, verse_id) DO UPDATE
            SET note = excluded.note, updated_at = excluded.updated_at
            WHERE excluded.updated_at > notes.updated_at
        ''');

        await copyTable('topics', '''
          INSERT OR IGNORE INTO topics
            (translation_id, book_id, chapter, verse_id, topic,
             topic_sort, verse_sort, updated_at)
          SELECT i.translation_id, i.book_id, i.chapter, i.verse_id, i.topic,
                 ${col('topic_sort')}, ${col('verse_sort')},
                 COALESCE(i.updated_at, strftime('%s','now'))
          FROM imp.topics i
        ''');

        await copyTable('topic_metadata', '''
          INSERT INTO topic_metadata (topic, description, updated_at)
          SELECT i.topic, i.description,
                 COALESCE(i.updated_at, strftime('%s','now'))
          FROM imp.topic_metadata i WHERE 1
          ON CONFLICT(topic) DO UPDATE
            SET description = excluded.description,
                updated_at = excluded.updated_at
            WHERE excluded.updated_at > topic_metadata.updated_at
        ''');

        await copyTable('bookmarks', '''
          INSERT INTO bookmarks (title, verses, sort_order, updated_at)
          SELECT i.title, i.verses, COALESCE(i.sort_order, 0),
                 COALESCE(i.updated_at, strftime('%s','now'))
          FROM imp.bookmarks i WHERE 1
          ON CONFLICT(title) DO UPDATE
            SET verses = excluded.verses, sort_order = excluded.sort_order,
                updated_at = excluded.updated_at
            WHERE excluded.updated_at > bookmarks.updated_at
        ''');

        await copyTable('settings', '''
          INSERT INTO settings (key, value, updated_at)
          SELECT i.key, i.value, COALESCE(i.updated_at, strftime('%s','now'))
          FROM imp.settings i WHERE 1
          ON CONFLICT(key) DO UPDATE
            SET value = excluded.value, updated_at = excluded.updated_at
            WHERE excluded.updated_at > settings.updated_at
        ''');

        await copyTable('read_history', '''
          INSERT INTO read_history
            (translation_id, book_id, chapter, verse_id, updated_at)
          SELECT i.translation_id, i.book_id, i.chapter, i.verse_id,
                 COALESCE(i.updated_at, strftime('%s','now'))
          FROM imp.read_history i WHERE 1
          ON CONFLICT(translation_id, book_id, chapter, verse_id) DO UPDATE
            SET updated_at = excluded.updated_at
            WHERE excluded.updated_at > read_history.updated_at
        ''');

        for (final t in ['search_history', 'context_history']) {
          await copyTable(t, '''
            INSERT OR IGNORE INTO $t (query, timestamp)
            SELECT i.query, i.timestamp FROM imp.$t i
          ''');
        }

        await copyTable('MemeTemplates', '''
          INSERT INTO MemeTemplates (title, thumbnail, payload, updated_at)
          SELECT i.title, i.thumbnail, i.payload,
                 COALESCE(i.updated_at, strftime('%s','now'))
          FROM imp.MemeTemplates i
          WHERE NOT EXISTS (
            SELECT 1 FROM MemeTemplates m
            WHERE m.title = i.title AND m.payload = i.payload)
        ''');

        // Editor: theme + toggles always come across. The text only comes
        // across if this device's editor is empty (never overwrite a document
        // the user is working on). Undo history is deliberately not copied.
        await copyTable('md_store', '''
          INSERT OR REPLACE INTO md_store (key, value)
          SELECT i.key, i.value FROM imp.md_store i
          WHERE i.key IN ('md_editor.theme', 'md_editor.stacked', 'md_editor.auto')
             OR (i.key = 'md_editor.text'
                 AND COALESCE(
                   (SELECT value FROM md_store WHERE key = 'md_editor.text'),
                   '') = '')
        ''');
      });
    } finally {
      await db.execute('DETACH DATABASE imp');
      if (copy.existsSync()) await copy.delete();
    }
  }
}
