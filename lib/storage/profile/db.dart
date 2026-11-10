import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

enum ConflictAlgorithm { abort, ignore, replace }

class ProfileSqliteConnection {
  ProfileSqliteConnection(this._database);

  final sqlite3.Database _database;

  Future<void> execute(String sql, [List<Object?> arguments = const []]) async {
    _database.execute(sql, arguments);
  }

  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?> arguments = const [],
  ]) async => _database.select(sql, arguments).map(_rowToMap).toList();

  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.abort,
  }) async {
    final columns = values.keys.map((key) => '"$key"').join(', ');
    final placeholders = List.filled(values.length, '?').join(', ');
    final conflict = switch (conflictAlgorithm) {
      ConflictAlgorithm.abort => '',
      ConflictAlgorithm.ignore => 'OR IGNORE ',
      ConflictAlgorithm.replace => 'OR REPLACE ',
    };
    _database.execute(
      'INSERT $conflict INTO $table ($columns) VALUES ($placeholders)',
      values.values.toList(),
    );
    return _database.lastInsertRowId;
  }

  Future<List<Map<String, Object?>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final projection = columns == null ? '*' : columns.join(', ');
    final clauses = <String>[
      if (where != null) 'WHERE $where',
      if (orderBy != null) 'ORDER BY $orderBy',
      if (limit != null) 'LIMIT $limit',
    ];
    return rawQuery(
      'SELECT $projection FROM $table ${clauses.join(' ')}',
      whereArgs ?? const [],
    );
  }

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final assignments = values.keys.map((key) => '$key = ?').join(', ');
    _database.execute(
      'UPDATE $table SET $assignments${where == null ? '' : ' WHERE $where'}',
      [...values.values, ...?whereArgs],
    );
    return _database.updatedRows;
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    _database.execute(
      'DELETE FROM $table${where == null ? '' : ' WHERE $where'}',
      whereArgs ?? const [],
    );
    return _database.updatedRows;
  }

  Future<int> rawUpdate(
    String sql, [
    List<Object?> arguments = const [],
  ]) async {
    _database.execute(sql, arguments);
    return _database.updatedRows;
  }

  Future<int> rawDelete(
    String sql, [
    List<Object?> arguments = const [],
  ]) async {
    _database.execute(sql, arguments);
    return _database.updatedRows;
  }

  ProfileSqliteBatch batch() => ProfileSqliteBatch(this);

  Future<T> transaction<T>(
    Future<T> Function(ProfileSqliteConnection transaction) action,
  ) async {
    _database.execute('BEGIN');
    try {
      final result = await action(this);
      _database.execute('COMMIT');
      return result;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> close() async => _database.close();
}

class ProfileSqliteBatch {
  ProfileSqliteBatch(this._connection);

  final ProfileSqliteConnection _connection;
  final List<(String, Map<String, Object?>, ConflictAlgorithm)> _inserts = [];

  void insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.abort,
  }) {
    _inserts.add((table, values, conflictAlgorithm));
  }

  Future<List<Object?>> commit({bool noResult = false}) async =>
      _connection.transaction((transaction) async {
        final results = <Object?>[];
        for (final insert in _inserts) {
          results.add(
            await transaction.insert(
              insert.$1,
              insert.$2,
              conflictAlgorithm: insert.$3,
            ),
          );
        }
        return noResult ? const [] : results;
      });
}

Map<String, Object?> _rowToMap(sqlite3.Row row) => {
  for (final column in row.keys) column: row[column],
};

class ProfileDatabase {
  ProfileDatabase({this.databasePath});

  final String? databasePath;
  ProfileSqliteConnection? _database;
  Future<ProfileSqliteConnection>? _openingDatabase;

  Future<ProfileSqliteConnection> get database async {
    if (_database case final database?) return database;
    final openingDatabase = _openingDatabase;
    if (openingDatabase != null) return openingDatabase;

    final opening = _openDatabase();
    _openingDatabase = opening;
    return opening;
  }

  Future<ProfileSqliteConnection> _openDatabase() async {
    final resolvedPath =
        databasePath ??
        path.join((await getApplicationSupportDirectory()).path, 'profile.db');
    try {
      await Directory(path.dirname(resolvedPath)).create(recursive: true);
      final opened = ProfileSqliteConnection(
        sqlite3.sqlite3.open(resolvedPath),
      );
      await opened.execute('PRAGMA foreign_keys = ON');
      var version =
          (await opened.rawQuery('PRAGMA user_version')).first['user_version']
              as int;
      if (version < 1) {
        await _createSchema(opened, 1);
        version = 1;
      }
      if (version < 2) {
        await _upgradeToV2(opened);
        version = 2;
      }
      await opened.execute('PRAGMA user_version = $version');
      _database = opened;
      return opened;
    } catch (_) {
      _openingDatabase = null;
      rethrow;
    }
  }

  Future<void> close() async {
    final opened = _database ?? await _openingDatabase;
    _database = null;
    _openingDatabase = null;
    if (opened != null) await opened.close();
  }

  Future<void> _createSchema(ProfileSqliteConnection db, int version) async {
    await db.execute('''
      CREATE TABLE highlights (
        id INTEGER PRIMARY KEY,
        translation_id TEXT,
        book_id TEXT,
        chapter INTEGER,
        verse_id INTEGER,
        color TEXT,
        updated_at INTEGER DEFAULT (strftime('%s','now')),
        UNIQUE(translation_id, book_id, chapter, verse_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY,
        translation_id TEXT,
        book_id TEXT,
        chapter INTEGER,
        verse_id INTEGER,
        note TEXT,
        updated_at INTEGER DEFAULT (strftime('%s','now')),
        UNIQUE(translation_id, book_id, chapter, verse_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE topics (
        id INTEGER PRIMARY KEY,
        translation_id TEXT,
        book_id TEXT,
        chapter INTEGER,
        verse_id INTEGER,
        topic TEXT,
        topic_sort INTEGER DEFAULT 0,
        verse_sort INTEGER DEFAULT 0,
        updated_at INTEGER DEFAULT (strftime('%s','now')),
        UNIQUE(translation_id, book_id, chapter, verse_id, topic)
      )
    ''');
    await db.execute('''
      CREATE TABLE search_history (
        id INTEGER PRIMARY KEY,
        query TEXT UNIQUE,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE context_history (
        id INTEGER PRIMARY KEY,
        query TEXT UNIQUE,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE topic_metadata (
        topic TEXT PRIMARY KEY,
        description TEXT,
        updated_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE Book (
        id TEXT PRIMARY KEY,
        englishName TEXT,
        "order" INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE MemeTemplates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        thumbnail TEXT,
        payload TEXT NOT NULL,
        updated_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE read_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        translation_id TEXT,
        book_id TEXT,
        chapter INTEGER,
        verse_id INTEGER,
        updated_at INTEGER DEFAULT (strftime('%s','now')),
        UNIQUE(translation_id, book_id, chapter, verse_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL UNIQUE,
        verses TEXT NOT NULL,
        sort_order INTEGER DEFAULT 0,
        updated_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE bible_chat_conversations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT 'New conversation',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE bible_chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id INTEGER NOT NULL
          REFERENCES bible_chat_conversations(id) ON DELETE CASCADE,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_hi ON highlights(translation_id, book_id, chapter)',
    );
    await db.execute(
      'CREATE INDEX idx_nt ON notes(translation_id, book_id, chapter)',
    );
    await db.execute(
      'CREATE INDEX idx_tp ON topics(translation_id, book_id, chapter)',
    );
    await db.execute('CREATE INDEX idx_tm ON topic_metadata(topic)');
    await db.execute(
      'CREATE INDEX idx_history_time ON read_history(updated_at DESC)',
    );
    await db.execute('CREATE INDEX idx_bm_time ON bookmarks(updated_at DESC)');
    await db.execute(
      'CREATE INDEX idx_bcm_conv ON bible_chat_messages(conversation_id)',
    );

    final bookBatch = db.batch();
    for (final book in _books) {
      bookBatch.insert('Book', {
        'id': book.$1,
        'englishName': book.$2,
        'order': book.$3,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await bookBatch.commit(noResult: true);
    await db.execute('''
      CREATE VIEW gallery_view_raw AS
      SELECT 'note' AS entry_type, id, translation_id, book_id, chapter,
             verse_id, note, NULL AS topic, NULL AS highlight,
             0 AS topic_sort, 0 AS verse_sort
      FROM notes
      UNION ALL
      SELECT 'highlight', id, translation_id, book_id, chapter, verse_id,
             NULL, NULL, color, 0, 0
      FROM highlights
      UNION ALL
      SELECT 'topic', id, translation_id, book_id, chapter, verse_id,
             NULL, topic, NULL, topic_sort, verse_sort
      FROM topics
    ''');
    await db.execute('''
      CREATE VIEW reader_view AS
      SELECT translation_id, book_id, chapter, verse_id,
             GROUP_CONCAT(topic, ', ') AS topic_list,
             MAX(note) AS note,
             MAX(highlight) AS highlight
      FROM gallery_view_raw
      GROUP BY translation_id, book_id, chapter, verse_id
    ''');
  }

  /// v2: key/value storage for the markdown editor (text, history, theme...).
  Future<void> _upgradeToV2(ProfileSqliteConnection db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS md_store (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }
}

const _books = <(String, String, int)>[
  ('1CH', '1 Chronicles', 13),
  ('1CO', '1 Corinthians', 46),
  ('1JN', '1 John', 62),
  ('1KI', '1 Kings', 11),
  ('1MA', '1 Maccabees', 77),
  ('1PE', '1 Peter', 60),
  ('1SA', '1 Samuel', 9),
  ('1TH', '1 Thessalonians', 52),
  ('1TI', '1 Timothy', 54),
  ('2CH', '2 Chronicles', 14),
  ('2CO', '2 Corinthians', 47),
  ('2JN', '2 John', 63),
  ('2KI', '2 Kings', 12),
  ('2MA', '2 Maccabees', 78),
  ('2PE', '2 Peter', 61),
  ('2SA', '2 Samuel', 10),
  ('2TH', '2 Thessalonians', 53),
  ('2TI', '2 Timothy', 55),
  ('3JN', '3 John', 64),
  ('ACT', 'Acts', 44),
  ('AMO', 'Amos', 30),
  ('BAR', 'Baruch', 72),
  ('COL', 'Colossians', 51),
  ('DAN', 'Daniel', 27),
  ('DEU', 'Deuteronomy', 5),
  ('ECC', 'Ecclesiastes', 21),
  ('EPH', 'Ephesians', 49),
  ('EST', 'Esther', 17),
  ('EXO', 'Exodus', 2),
  ('EZK', 'Ezekiel', 26),
  ('EZR', 'Ezra', 15),
  ('GAL', 'Galatians', 48),
  ('GEN', 'Genesis', 1),
  ('HAB', 'Habakkuk', 35),
  ('HAG', 'Haggai', 37),
  ('HEB', 'Hebrews', 58),
  ('HOS', 'Hosea', 28),
  ('ISA', 'Isaiah', 23),
  ('JAS', 'James', 59),
  ('JDG', 'Judges', 7),
  ('JDT', 'Judith', 68),
  ('JER', 'Jeremiah', 24),
  ('JHN', 'John', 43),
  ('JOB', 'Job', 18),
  ('JOL', 'Joel', 29),
  ('JON', 'Jonah', 32),
  ('JOS', 'Joshua', 6),
  ('JUD', 'Jude', 65),
  ('LAM', 'Lamentations', 25),
  ('LEV', 'Leviticus', 3),
  ('LUK', 'Luke', 42),
  ('MAL', 'Malachi', 39),
  ('MAT', 'Matthew', 40),
  ('MIC', 'Micah', 33),
  ('MRK', 'Mark', 41),
  ('NAM', 'Nahum', 34),
  ('NEH', 'Nehemiah', 16),
  ('NUM', 'Numbers', 4),
  ('OBA', 'Obadiah', 31),
  ('PHM', 'Philemon', 57),
  ('PHP', 'Philippians', 50),
  ('PRO', 'Proverbs', 20),
  ('PSA', 'Psalms', 19),
  ('REV', 'Revelation', 66),
  ('ROM', 'Romans', 45),
  ('RUT', 'Ruth', 8),
  ('SIR', 'Sirach', 71),
  ('SNG', 'Song of Solomon', 22),
  ('TIT', 'Titus', 56),
  ('TOB', 'Tobit', 67),
  ('WIS', 'Wisdom of Solomon', 70),
  ('ZEC', 'Zechariah', 38),
  ('ZEP', 'Zephaniah', 36),
];
