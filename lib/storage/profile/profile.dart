import 'dart:convert';

import 'db.dart';

class VerseReference {
  const VerseReference({
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.verseId,
  });

  final String translationId;
  final String bookId;
  final int chapter;
  final int verseId;
}

class ProfileRepository {
  ProfileRepository(this.profileDatabase);

  final ProfileDatabase profileDatabase;

  Future<ProfileSqliteConnection> get _db => profileDatabase.database;

  Future<void> saveNote({
    required String translationId,
    required String bookId,
    required int chapter,
    required int verseId,
    required String note,
  }) async {
    final db = await _db;
    await db.insert('notes', {
      'translation_id': translationId,
      'book_id': bookId,
      'chapter': chapter,
      'verse_id': verseId,
      'note': note,
      'updated_at': _nowSeconds,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Object?>?> getNote(VerseReference verse) async {
    final rows = await (await _db).query(
      'notes',
      where:
          'translation_id = ? AND book_id = ? AND chapter = ? AND verse_id = ?',
      whereArgs: _verseArgs(verse),
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> getNotes() async =>
      (await _db).query('notes', orderBy: 'updated_at DESC, id DESC');

  Future<int> deleteNote(int id) async =>
      (await _db).delete('notes', where: 'id = ?', whereArgs: [id]);

  Future<void> toggleHighlights({
    required String translationId,
    required String bookId,
    required int chapter,
    required Iterable<int> verses,
    required String color,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final verseId in verses) {
        final where =
            'translation_id = ? AND book_id = ? AND chapter = ? AND verse_id = ?';
        final args = [translationId, bookId, chapter, verseId];
        if (color == 'transparent') {
          await txn.delete('highlights', where: where, whereArgs: args);
        } else {
          await txn.insert('highlights', {
            'translation_id': translationId,
            'book_id': bookId,
            'chapter': chapter,
            'verse_id': verseId,
            'color': color,
            'updated_at': _nowSeconds,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<List<Map<String, Object?>>> getHighlights() async =>
      (await _db).query('highlights', orderBy: 'updated_at DESC, id DESC');

  Future<int> deleteHighlight(int id) async =>
      (await _db).delete('highlights', where: 'id = ?', whereArgs: [id]);

  Future<void> saveVersesToTopic({
    required Iterable<VerseReference> verses,
    required String topic,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final result = await txn.rawQuery(
        'SELECT COALESCE(MAX(verse_sort), 0) AS max_sort FROM topics WHERE topic = ?',
        [topic],
      );
      final maxSort = (result.first['max_sort'] as int?) ?? 0;
      var sort = maxSort;
      for (final verse in verses) {
        sort++;
        await txn.insert('topics', {
          'translation_id': verse.translationId,
          'book_id': verse.bookId,
          'chapter': verse.chapter,
          'verse_id': verse.verseId,
          'topic': topic,
          'verse_sort': sort,
          'updated_at': _nowSeconds,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.rawUpdate(
          '''UPDATE topics SET updated_at = ?
             WHERE translation_id = ? AND book_id = ? AND chapter = ?
               AND verse_id = ? AND topic = ?''',
          [
            _nowSeconds,
            verse.translationId,
            verse.bookId,
            verse.chapter,
            verse.verseId,
            topic,
          ],
        );
      }
    });
  }

  Future<List<Map<String, Object?>>> getTopics() async => (await _db).rawQuery(
    '''SELECT topic, COUNT(*) AS count, MAX(updated_at) AS updated
       FROM topics GROUP BY topic
       ORDER BY MIN(topic_sort) ASC, MAX(updated_at) DESC''',
  );

  Future<List<Map<String, Object?>>> getTopicVerses(String topic) async =>
      (await _db).query(
        'topics',
        columns: ['id', 'translation_id', 'book_id', 'chapter', 'verse_id'],
        where: 'topic = ?',
        whereArgs: [topic],
        orderBy: 'verse_sort ASC, id ASC',
      );

  Future<void> renameTopic(String oldTopic, String newTopic) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        'topics',
        {'topic': newTopic, 'updated_at': _nowSeconds},
        where: 'topic = ?',
        whereArgs: [oldTopic],
      );
      await txn.update(
        'topic_metadata',
        {'topic': newTopic, 'updated_at': _nowSeconds},
        where: 'topic = ?',
        whereArgs: [oldTopic],
      );
    });
  }

  Future<void> deleteTopic(String topic) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('topics', where: 'topic = ?', whereArgs: [topic]);
      await txn.delete(
        'topic_metadata',
        where: 'topic = ?',
        whereArgs: [topic],
      );
    });
  }

  Future<void> updateTopicOrder(List<String> orderedTopics) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (var index = 0; index < orderedTopics.length; index++) {
        await txn.update(
          'topics',
          {'topic_sort': index},
          where: 'topic = ?',
          whereArgs: [orderedTopics[index]],
        );
      }
    });
  }

  Future<void> updateVerseOrder(List<int> orderedIds) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (var index = 0; index < orderedIds.length; index++) {
        await txn.update(
          'topics',
          {'verse_sort': index},
          where: 'id = ?',
          whereArgs: [orderedIds[index]],
        );
      }
    });
  }

  Future<void> saveTopicDescription(String topic, String description) async =>
      (await _db).insert('topic_metadata', {
        'topic': topic,
        'description': description,
        'updated_at': _nowSeconds,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<String> getTopicDescription(String topic) async {
    final rows = await (await _db).query(
      'topic_metadata',
      columns: ['description'],
      where: 'topic = ?',
      whereArgs: [topic],
      limit: 1,
    );
    return rows.isEmpty ? '' : (rows.first['description'] as String? ?? '');
  }

  Future<void> logHistoryEntry({
    required VerseReference verse,
    int limit = 100,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('read_history', {
        'translation_id': verse.translationId,
        'book_id': verse.bookId,
        'chapter': verse.chapter,
        'verse_id': verse.verseId,
        'updated_at': _nowSeconds,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.rawDelete(
        '''DELETE FROM read_history WHERE rowid NOT IN
           (SELECT rowid FROM read_history ORDER BY updated_at DESC, id DESC LIMIT ?)''',
        [limit < 0 ? 0 : limit],
      );
    });
  }

  Future<List<Map<String, Object?>>> getReadHistory() async =>
      (await _db).query('read_history', orderBy: 'updated_at DESC, id DESC');

  Future<int> deleteHistoryEntry(int id) async =>
      (await _db).delete('read_history', where: 'id = ?', whereArgs: [id]);

  Future<void> clearReadHistory() async => (await _db).delete('read_history');

  Future<int> saveTemplate({
    int? id,
    required String title,
    String thumbnail = '',
    required String payload,
  }) async {
    final db = await _db;
    final values = {
      'title': title,
      'thumbnail': thumbnail,
      'payload': payload,
      'updated_at': _nowSeconds,
    };
    if (id == null) return db.insert('MemeTemplates', values);
    await db.update('MemeTemplates', values, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<List<Map<String, Object?>>> getTemplates() async =>
      (await _db).query('MemeTemplates', orderBy: 'updated_at DESC, id DESC');

  Future<int> deleteTemplate(int id) async =>
      (await _db).delete('MemeTemplates', where: 'id = ?', whereArgs: [id]);

  Future<void> setConfig(String key, String value) async => (await _db).insert(
    'settings',
    {'key': key, 'value': value, 'updated_at': _nowSeconds},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<String?> getConfig(String key) async {
    final rows = await (await _db).query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<Map<String, String>> getConfigs(Iterable<String> keys) async {
    final result = <String, String>{};
    for (final key in keys) {
      final value = await getConfig(key);
      if (value != null) result[key] = value;
    }
    return result;
  }

  Future<List<Map<String, Object?>>> getSettings() async =>
      (await _db).query('settings', orderBy: 'key');

  /// Deletes every row in the settings table (other tables are untouched).
  Future<int> clearSettings() async => (await _db).delete('settings');

  Future<int> deleteConfig(String key) async =>
      (await _db).delete('settings', where: 'key = ?', whereArgs: [key]);

  Future<int> saveBookmark({
    int? id,
    required String title,
    required List<VerseReference> verses,
    int sortOrder = 0,
  }) async {
    final db = await _db;
    final values = {
      'title': title,
      'verses': jsonEncode(
        verses
            .map(
              (verse) => {
                'tr': verse.translationId,
                'bk': verse.bookId,
                'ch': verse.chapter,
                'vs': verse.verseId,
              },
            )
            .toList(),
      ),
      'sort_order': sortOrder,
      'updated_at': _nowSeconds,
    };
    if (id == null) {
      final existing = await db.query(
        'bookmarks',
        columns: ['id'],
        where: 'title = ?',
        whereArgs: [title],
        limit: 1,
      );
      if (existing.isEmpty) return db.insert('bookmarks', values);
      final existingId = existing.first['id'] as int;
      await db.update(
        'bookmarks',
        values,
        where: 'id = ?',
        whereArgs: [existingId],
      );
      return existingId;
    }
    await db.update('bookmarks', values, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<List<Map<String, Object?>>> getBookmarks() async =>
      (await _db).query('bookmarks', orderBy: 'sort_order, updated_at DESC');

  Future<int> deleteBookmark(int id) async =>
      (await _db).delete('bookmarks', where: 'id = ?', whereArgs: [id]);

  Future<List<Map<String, Object?>>> getGallery({
    String? entryType,
    String? topic,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (entryType != null && entryType != 'All') {
      clauses.add('g.entry_type = ?');
      args.add(entryType);
    }
    if (topic != null && topic.isNotEmpty && topic != 'All') {
      clauses.add('g.topic = ?');
      args.add(topic);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    return (await _db).rawQuery('''
      SELECT g.*, b.englishName AS book_name
      FROM gallery_view_raw g
      LEFT JOIN Book b ON g.book_id = b.id
      $where
      ORDER BY b."order" ASC, g.chapter ASC, g.verse_id ASC
    ''', args);
  }

  Future<List<String>> getActiveFilters(String entryType) async {
    final rows = await (await _db).rawQuery(
      '''SELECT DISTINCT translation_id FROM gallery_view_raw
         WHERE entry_type = ? ORDER BY translation_id''',
      [entryType],
    );
    return rows.map((row) => row['translation_id'] as String).toList();
  }

  Future<void> logQuery(String kind, String query) async {
    final table = _historyTable(kind);
    await (await _db).insert(table, {
      'query': query,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Newest first. Rows saved in the same second are ordered by id.
  Future<List<String>> recentQueries(String kind, {int limit = 20}) async {
    final rows = await (await _db).query(
      _historyTable(kind),
      columns: ['query'],
      orderBy: 'timestamp DESC, id DESC',
      limit: limit,
    );
    return [for (final r in rows) r['query'] as String];
  }

  Future<void> deleteQueryText(String kind, String query) async =>
      (await _db).delete(
        _historyTable(kind),
        where: 'query = ?',
        whereArgs: [query],
      );

  /// Keeps only the newest [keep] rows.
  Future<void> trimQueries(String kind, {int keep = 20}) async {
    final t = _historyTable(kind);
    await (await _db).rawDelete(
      '''DELETE FROM $t WHERE id NOT IN
         (SELECT id FROM $t ORDER BY timestamp DESC, id DESC LIMIT ?)''',
      [keep],
    );
  }

  Future<List<Map<String, Object?>>> getQueries(String kind) async =>
      (await _db).query(_historyTable(kind), orderBy: 'timestamp DESC');

  Future<int> deleteQuery(String kind, int id) async =>
      (await _db).delete(_historyTable(kind), where: 'id = ?', whereArgs: [id]);

  Future<void> clearQueries(String kind) async =>
      (await _db).delete(_historyTable(kind));

  Future<List<Map<String, Object?>>> getBooks() async =>
      (await _db).query('Book', orderBy: '"order"');

  List<Object?> _verseArgs(VerseReference verse) => [
    verse.translationId,
    verse.bookId,
    verse.chapter,
    verse.verseId,
  ];

  String _historyTable(String kind) => switch (kind) {
    'search' => 'search_history',
    'context' => 'context_history',
    _ => throw ArgumentError.value(kind, 'kind', 'Use search or context'),
  };

  // ---- markdown editor storage (md_store table) ----
  Future<String?> mdRead(String key) async {
    final rows = await (await _db).query(
      'md_store',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  /// One single SQL statement = atomic, no transaction needed.
  Future<void> mdWriteAll(Map<String, String> entries) async {
    if (entries.isEmpty) return;
    final slots = List.filled(entries.length, '(?, ?)').join(', ');
    await (await _db).rawUpdate(
      'INSERT OR REPLACE INTO md_store (key, value) VALUES $slots',
      [
        for (final e in entries.entries) ...[e.key, e.value],
      ],
    );
  }

  Future<void> mdRemove(String key) async =>
      (await _db).delete('md_store', where: 'key = ?', whereArgs: [key]);
}

int get _nowSeconds => DateTime.now().millisecondsSinceEpoch ~/ 1000;
