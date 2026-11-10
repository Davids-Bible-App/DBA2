/// Neutral verse shape. Search hits and gallery entries both convert to this.
typedef MdVerse = ({
  String tr,
  String bookId,
  String bookName,
  int chapter,
  int verse,
  String text,
  String edition, // "KJV"
});

enum MdRefPlacement {
  above, // **ref** above the quote
  start, // ref at the start of the quote
  end, // ref at the end of the quote
}

/// THE one place verses become markdown. Verses stay in the order given;
/// neighbours in the same chapter are grouped into one quote.
String formatVerses(
  List<MdVerse> verses, {
  required bool stacked,
  MdRefPlacement refPlacement = MdRefPlacement.above,
  bool refOwnLine = false,
  String? heading,
  String? intro,
}) {
  final groups = <List<MdVerse>>[];
  for (final v in verses) {
    final g = groups.isEmpty ? null : groups.last;
    if (g != null &&
        g.last.tr == v.tr &&
        g.last.bookId == v.bookId &&
        g.last.chapter == v.chapter &&
        v.verse == g.last.verse + 1) {
      g.add(v);
    } else {
      groups.add([v]);
    }
  }

  final ws = RegExp(r'\s*\n\s*');
  String clean(String s) => s.replaceAll(ws, ' ').trim();

  final out = StringBuffer();
  if (heading != null && heading.trim().isNotEmpty) {
    out.write('## ${heading.trim()}\n\n');
  }
  if (intro != null && intro.trim().isNotEmpty) {
    out.write('${intro.trim()}\n\n');
  }

  for (final g in groups) {
    final f = g.first;
    final range = g.length == 1 ? '${f.verse}' : '${f.verse}-${g.last.verse}';
    final ed = f.edition.isEmpty ? '' : ' (${f.edition})';
    final ref = '**${f.bookName} ${f.chapter}:$range**$ed';

    final List<String> body;
    if (g.length == 1) {
      body = [clean(f.text)];
    } else {
      final parts = [for (final v in g) '**${v.verse}** ${clean(v.text)}'];
      body = stacked ? parts : [parts.join(' ')];
    }

    // Stacked groups always put the reference on its own line.
    final ownLine = refOwnLine || (stacked && g.length > 1);

    if (refPlacement == MdRefPlacement.above) {
      out.write('$ref\n${_quote(body)}');
    } else {
      final lines = switch (refPlacement) {
        MdRefPlacement.start =>
          ownLine ? [ref, ...body] : ['$ref ${body.first}', ...body.skip(1)],
        _ =>
          ownLine
              ? [...body, ref]
              : [...body.take(body.length - 1), '${body.last} — $ref'],
      };
      out.write(_quote(lines));
    }
    out.write('\n\n');
  }
  return out.toString();
}

/// Every line gets "> ", and lines are joined with a hard break
/// (two trailing spaces) so they stay on separate lines in ONE quote.
String _quote(List<String> lines) => lines.map((l) => '> $l').join('  \n');
