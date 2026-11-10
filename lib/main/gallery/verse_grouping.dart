import 'models.dart';

/// Port of `groupConsecutiveVerses(..., returnAsArray: true)`.
/// Keep [sort] false for user-ordered (drag & drop) lists.
List<List<GalleryEntry>> groupConsecutive(
  List<GalleryEntry> entries, {
  bool sort = false,
}) {
  if (entries.isEmpty) return const [];
  final list = [...entries];
  if (sort) {
    list.sort((a, b) {
      var c = a.translationId.compareTo(b.translationId);
      if (c != 0) return c;
      c = a.bookName.compareTo(b.bookName);
      if (c != 0) return c;
      c = a.chapter.compareTo(b.chapter);
      if (c != 0) return c;
      return a.verseId.compareTo(b.verseId);
    });
  }
  final groups = <List<GalleryEntry>>[
    [list.first],
  ];
  for (var i = 1; i < list.length; i++) {
    final p = list[i - 1], c = list[i];
    final consecutive =
        p.translationId == c.translationId &&
        p.bookId == c.bookId &&
        p.chapter == c.chapter &&
        c.verseId == p.verseId + 1;
    consecutive ? groups.last.add(c) : groups.add([c]);
  }
  return groups;
}

/// "John 3:16-17"
String refLabel(List<GalleryEntry> g) {
  final f = g.first, l = g.last;
  final base = '${f.bookName} ${f.chapter}:${f.verseId}';
  return f.verseId == l.verseId ? base : '$base-${l.verseId}';
}

/// Port of the plain-text formatter (used for clipboard export).
String formatGroups(List<GalleryEntry> entries, {bool wrap = false}) {
  return groupConsecutive(entries, sort: true)
      .map((g) {
        final header = '${refLabel(g)}  (${g.first.abbr})';
        final body = g
            .map((v) => g.length == 1 ? v.text : '${v.verseId}. ${v.text}')
            .join(wrap ? ' ' : '\n');
        return '$header\n$body';
      })
      .join('\n\n');
}
