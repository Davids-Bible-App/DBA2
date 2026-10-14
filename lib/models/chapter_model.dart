// lib/models/chapter_model.dart
//
// Mirrors the data shape your Solid code receives from get_chapter_data:
//   { content: [ {type, number, content: [...parts]} ... ], footnotes: [...] }

// ---------------------------------------------------------------------------
// VERSE / HEADING PARTS
// ---------------------------------------------------------------------------

sealed class VersePart {
  const VersePart();
}

class TextPart extends VersePart {
  const TextPart(this.text);
  final String text;
}

/// {wordsOfJesus: true, text: "..."}
class JesusPart extends VersePart {
  const JesusPart(this.text);
  final String text;
}

/// {text: "..."} with no other flag: italic (translator-added words)
class ItalicPart extends VersePart {
  const ItalicPart(this.text);
  final String text;
}

/// {noteId: 233}
class NotePart extends VersePart {
  const NotePart(this.id);
  final String id;
}

/// {lineBreak: true}
class LineBreakPart extends VersePart {
  const LineBreakPart();
}

/// {poem: "..."}
class PoemPart extends VersePart {
  const PoemPart(this.text);
  final String text;
}

bool _truthy(Object? v) => v != null && v != false && v != 0 && v != '';

// Same precedence as the JSX <Switch> in VerseParts.
VersePart? _parsePart(Object? raw) {
  if (raw is String) return TextPart(raw);
  if (raw is Map) {
    if (_truthy(raw['lineBreak'])) return const LineBreakPart();
    if (_truthy(raw['wordsOfJesus'])) return JesusPart('${raw['text'] ?? ''}');
    if (raw['text'] != null) return ItalicPart('${raw['text']}');
    if (raw['noteId'] != null) return NotePart('${raw['noteId']}');
    if (_truthy(raw['poem'])) return PoemPart('${raw['poem']}');
  }
  return null;
}

List<VersePart> _parseParts(Object? raw) => raw is List
    ? raw.map(_parsePart).whereType<VersePart>().toList(growable: false)
    : const [];

// ---------------------------------------------------------------------------
// CHAPTER ITEMS
// ---------------------------------------------------------------------------

sealed class ChapterItem {
  const ChapterItem();
}

class ErrorItem extends ChapterItem {
  const ErrorItem(this.message);
  final String message;
}

class HeadingItem extends ChapterItem {
  const HeadingItem(this.parts);
  final List<VersePart> parts;
}

class HebrewSubtitleItem extends ChapterItem {
  const HebrewSubtitleItem(this.parts);
  final List<VersePart> parts;
}

class LineBreakItem extends ChapterItem {
  const LineBreakItem();
}

class VerseItem extends ChapterItem {
  const VerseItem({required this.number, required this.parts});
  final int number;
  final List<VersePart> parts;
}

class Footnote {
  const Footnote({required this.id, required this.text});
  final String id;
  final String text;
}

class ChapterData {
  const ChapterData({required this.items, required this.footnotes});

  final List<ChapterItem> items;
  final List<Footnote> footnotes;

  Footnote? footnote(String id) {
    for (final f in footnotes) {
      if (f.id == id) return f;
    }
    return null;
  }

  factory ChapterData.fromJson(Map<String, dynamic> json) {
    final items = <ChapterItem>[];

    for (final raw in (json['content'] as List? ?? const [])) {
      if (raw is! Map) continue;
      switch (raw['type']) {
        case 'error':
          items.add(ErrorItem('${raw['error'] ?? 'Unknown error'}'));
        case 'heading':
          items.add(HeadingItem(_parseParts(raw['content'])));
        case 'hebrew_subtitle':
          items.add(HebrewSubtitleItem(_parseParts(raw['content'])));
        case 'line_break':
          items.add(const LineBreakItem());
        case 'verse':
          final content = raw['content'];
          items.add(
            VerseItem(
              number: (raw['number'] as num?)?.toInt() ?? 0,
              // JSX: no content -> fall back to verse.text
              parts: content is List
                  ? _parseParts(content)
                  : [TextPart('${raw['text'] ?? ''}')],
            ),
          );
        default:
          items.add(const ErrorItem('Unhandled item type'));
      }
    }

    final footnotes = <Footnote>[
      for (final f in (json['footnotes'] as List? ?? const []))
        if (f is Map)
          Footnote(id: '${f['noteId']}', text: '${f['text'] ?? ''}'),
    ];

    return ChapterData(items: items, footnotes: footnotes);
  }
}
