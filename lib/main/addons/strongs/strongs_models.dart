// Plain data classes. They only hold Strings/ints/Lists, so they can be sent
// back from a background isolate.

class StrongsDef {
  const StrongsDef({
    required this.strongsId,
    this.lemma,
    this.transliteration,
    this.pronunciation,
    this.kjvDef,
    this.definition,
  });

  final String strongsId;
  final String? lemma;
  final String? transliteration;
  final String? pronunciation;
  final String? kjvDef;
  final String? definition;
}

class VerseUsage {
  const VerseUsage({
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.text,
    required this.strongsIds,
  });

  final String bookId;
  final int chapter;
  final int verse;
  final String text;
  final List<String> strongsIds;
}

class LookupResponse {
  const LookupResponse({
    required this.dictionaries,
    required this.verses,
    required this.searchType, // 'strongs' | 'english'
    required this.occurrenceCount,
    required this.verseCount,
  });

  final List<StrongsDef> dictionaries;
  final List<VerseUsage> verses;
  final String searchType;
  final int occurrenceCount;
  final int verseCount;

  bool get isStrongsSearch => searchType == 'strongs';
  bool get hasResults => dictionaries.isNotEmpty || verses.isNotEmpty;
}

/// One English word of a verse plus the dictionary entries tagged on it
/// (the result of `fetchStudyData` grouping in StrongsVerse.jsx).
class StrongsWord {
  StrongsWord({
    required this.wordOrder,
    required this.englishWord,
    required this.isAdded,
    this.rawStrongs,
  });

  final int wordOrder;
  final String englishWord;
  final bool isAdded;
  final String? rawStrongs;
  final List<StrongsDef> definitions = [];
}
