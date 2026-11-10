import 'package:dba2/core.dart'; // rootNavigatorKey
import 'package:dba2/main/gallery/models.dart';
import 'package:dba2/components/markdown_editor/markdown_editor.dart';
import 'package:dba2/components/markdown_editor/verse_markdown.dart';
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/ui/widgets/toast.dart';

import 'search_sheet.dart';

/// THE one way to send verses to the editor, from anywhere.
Future<void> sendToEditor(
  MarkdownEditorController md,
  List<MdVerse> verses, {
  String? heading,
  String? intro,
}) async {
  if (verses.isEmpty) return;
  await md.receiveVerses(verses, heading: heading, intro: intro);
  openEditor(md);
}

/// Only one editor at a time: if it is open, just focus it.
void openEditor(MarkdownEditorController md) {
  if (md.isOpen) {
    md.focus.requestFocus();
    return;
  }
  md.isOpen = true; // set now so a quick second send can't push twice
  rootNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => MarkdownEditorPage(controller: md)),
  );
}

extension GalleryEntryMd on GalleryEntry {
  MdVerse toMdVerse() => (
    tr: translationId.replaceFirst(RegExp(r'\.dba$', caseSensitive: false), ''),
    bookId: bookId,
    bookName: bookName,
    chapter: chapter,
    verse: verseId,
    text: text,
    edition: abbr,
  );
}

/// Opens the search sheet with the Editor button enabled.
void showSearchSheetWithEditor(BuildContext context) {
  final md = context.read<MarkdownEditorController>();
  final bible = context.read<BibleController>();

  showSearchSheet(
    context,
    onSendToEditor: (hits) {
      // Built once per send instead of scanning the book list per verse.
      final names = {for (final b in bible.books) b.id: b.englishName};
      sendToEditor(md, [
        for (final h in hits)
          (
            tr: bible.translationId,
            bookId: h.bookId,
            bookName: names[h.bookId] ?? h.bookId,
            chapter: h.chapter,
            verse: h.verse,
            text: h.plainText,
            edition: bible.edition,
          ),
      ]);
    },
  );
}
