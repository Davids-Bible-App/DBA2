// lib/models/bible_book.dart

// const String kTranslationId = 'eng_kjv';
// const String kEdition = 'KJV';

class BibleBook {
  const BibleBook({
    required this.id,
    required this.englishName,
    required this.name,
    this.title = '',
    required this.numberOfChapters,
    required this.order,
  });

  factory BibleBook.fromMap(dynamic row) {
    final values = row as Map<String, Object?>;
    return BibleBook(
      id: (values['id'] ?? '').toString(),
      englishName: (values['englishName'] ?? '').toString(),
      name: (values['name'] ?? '').toString(),
      title: (values['title'] ?? '').toString(),
      numberOfChapters:
          int.tryParse((values['numberOfChapters'] ?? '0').toString()) ?? 0,
      order: int.tryParse((values['order'] ?? '0').toString()) ?? 0,
    );
  }

  final String id;
  final String englishName;
  final String name;
  final String title;
  final int numberOfChapters;
  final int order;

  bool get isOldTestament => order <= 39;
}
