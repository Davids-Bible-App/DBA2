import 'package:dba2/storage/profile/profile.dart';

import 'bookmark_models.dart';
import 'bookmark_store.dart';

class SqliteBookmarkRepository implements BookmarkRepository {
  SqliteBookmarkRepository(this._profile);

  final ProfileRepository _profile;

  static final _dba = RegExp(r'\.dba$', caseSensitive: false);

  // The app (e.g. setTranslation on jump) wants ids without ".dba",
  // but rows imported from v1 might have it.
  Bookmark _clean(Bookmark b) => b.copyWith(
    verses: [
      for (final v in b.verses)
        BookmarkVerse(
          translationId: v.translationId.replaceFirst(_dba, ''),
          bookId: v.bookId,
          chapter: v.chapter,
          verse: v.verse,
        ),
    ],
  );

  List<VerseReference> _refs(List<BookmarkVerse> verses) => [
    for (final v in verses)
      VerseReference(
        translationId: v.translationId,
        bookId: v.bookId,
        chapter: v.chapter,
        verseId: v.verse,
      ),
  ];

  Future<List<Bookmark>> _all() async => [
    for (final r in await _profile.getBookmarks()) _clean(Bookmark.fromRow(r)),
  ];

  Future<Bookmark?> _find(int id) async {
    for (final b in await _all()) {
      if (b.id == id) return b;
    }
    return null;
  }

  @override
  Future<List<Bookmark>> load() => _all();

  @override
  Future<Bookmark> add(String title, List<BookmarkVerse> verses) async {
    // New bookmarks go to the top: sort_order one below the current minimum.
    final rows = await _profile.getBookmarks();
    final minOrder = rows.fold<int>(0, (m, r) {
      final o = (r['sort_order'] as int?) ?? 0;
      return o < m ? o : m;
    });
    final id = await _profile.saveBookmark(
      title: title,
      verses: _refs(verses),
      sortOrder: minOrder - 1,
    );
    return (await _find(id))!;
  }

  @override
  Future<void> overwrite(int id, List<BookmarkVerse> verses) async {
    final b = await _find(id);
    if (b == null) return;
    await _profile.saveBookmark(
      id: id,
      title: b.title,
      verses: _refs(verses),
      sortOrder: b.sortOrder,
    );
  }

  @override
  Future<void> rename(int id, String title) async {
    final b = await _find(id);
    if (b == null) return;
    await _profile.saveBookmark(
      id: id,
      title: title,
      verses: _refs(b.verses),
      sortOrder: b.sortOrder,
    );
  }

  @override
  Future<void> delete(int id) async {
    await _profile.deleteBookmark(id);
  }

  @override
  Future<void> reorder(List<int> ids) async {
    final db = await _profile.profileDatabase.database;
    await db.transaction((tx) async {
      for (var i = 0; i < ids.length; i++) {
        // sort_order only: updated_at is left alone so nothing jumps around.
        await tx.update(
          'bookmarks',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [ids[i]],
        );
      }
    });
  }
}
