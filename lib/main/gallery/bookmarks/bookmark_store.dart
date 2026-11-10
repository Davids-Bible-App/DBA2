import 'package:flutter/foundation.dart';

import 'bookmark_models.dart';

/// Swap the in-memory one for a profile.db implementation later.
abstract class BookmarkRepository {
  Future<List<Bookmark>> load();
  Future<Bookmark> add(String title, List<BookmarkVerse> verses);
  Future<void> overwrite(int id, List<BookmarkVerse> verses);
  Future<void> rename(int id, String title);
  Future<void> delete(int id);
  Future<void> reorder(List<int> ids);
}

class InMemoryBookmarkRepository implements BookmarkRepository {
  final List<Bookmark> _rows = [];
  int _nextId = 1;

  @override
  Future<List<Bookmark>> load() async => List.of(_rows);

  @override
  Future<Bookmark> add(String title, List<BookmarkVerse> verses) async {
    final b = Bookmark(
      id: _nextId++,
      title: title,
      verses: verses,
      updatedAt: DateTime.now(),
    );
    _rows.insert(0, b);
    return b;
  }

  @override
  Future<void> overwrite(int id, List<BookmarkVerse> verses) async {
    final i = _rows.indexWhere((b) => b.id == id);
    if (i >= 0) {
      _rows[i] = _rows[i].copyWith(verses: verses, updatedAt: DateTime.now());
    }
  }

  @override
  Future<void> rename(int id, String title) async {
    final i = _rows.indexWhere((b) => b.id == id);
    if (i >= 0) {
      _rows[i] = _rows[i].copyWith(title: title, updatedAt: DateTime.now());
    }
  }

  @override
  Future<void> delete(int id) async => _rows.removeWhere((b) => b.id == id);

  @override
  Future<void> reorder(List<int> ids) async {
    final map = {for (final b in _rows) b.id: b};
    _rows
      ..clear()
      ..addAll([
        for (final id in ids)
          if (map[id] != null) map[id]!,
      ]);
  }
}

class BookmarkStore extends ChangeNotifier {
  BookmarkStore(
    this._repo, {
    required this.bookName,
    this.translationLabel,
  }) {
    load();
  }

  final BookmarkRepository _repo;
  final String Function(String bookId) bookName;
  final String Function(String translationId)? translationLabel;

  List<Bookmark> _items = [];
  bool _loading = true;

  List<Bookmark> get items => List.unmodifiable(_items);
  bool get loading => _loading;

  String refText(List<BookmarkVerse> v) => formatVerseRefs(
    v,
    bookName: bookName,
    translationLabel: translationLabel,
  );

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _items = await _repo.load();
    _loading = false;
    notifyListeners();
  }

  /// Case-insensitive exact title match -> the dialog overwrites it.
  Bookmark? findByTitle(String title) {
    final t = title.trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final b in _items) {
      if (b.title.toLowerCase() == t) return b;
    }
    return null;
  }

  /// Creates a new bookmark, or overwrites the verses of an exact-title match.
  Future<void> save(String title, List<BookmarkVerse> verses) async {
    final match = findByTitle(title);
    if (match != null) {
      await _repo.overwrite(match.id, verses);
    } else {
      await _repo.add(title.trim(), verses);
    }
    await load();
  }

  Future<void> rename(int id, String title) async {
    await _repo.rename(id, title.trim());
    await load();
  }

  Future<void> delete(int id) async {
    await _repo.delete(id);
    _items.removeWhere((b) => b.id == id);
    notifyListeners();
  }

  /// [newIndex] must already be adjusted (see panel).
  Future<void> reorder(int oldIndex, int newIndex) async {
    final item = _items.removeAt(oldIndex);
    _items.insert(newIndex, item);
    notifyListeners(); // optimistic
    await _repo.reorder([for (final b in _items) b.id]);
  }
}
