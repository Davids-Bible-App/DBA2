import 'package:dba2/ui/translations/ui/translation_sheet.dart';
import 'package:flutter/services.dart';

import 'package:dba2/main/addons/addon_controller.dart';
import 'package:dba2/main/addons/addon_store.dart';
import 'package:dba2/components/compare/compare_sheet.dart';
import 'package:dba2/core.dart';
import 'package:dba2/main/gallery/bookmarks/bookmark_dialog.dart';
import 'package:dba2/main/gallery/bookmarks/bookmark_models.dart';
import 'package:dba2/main/gallery/bookmarks/bookmark_store.dart';
import 'package:dba2/main/gallery/gallery_controller.dart';
import 'package:dba2/main/gallery/gallery_dialogs.dart';
import 'package:dba2/main/gallery/models.dart';
import 'package:dba2/components/markdown_editor/md_controller.dart';
import 'package:dba2/components/meme_maker/meme_controller.dart';
import 'package:dba2/components/meme_maker/meme_maker_page.dart';
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/main/search/send_to_editor.dart';
import 'package:dba2/main/addons/strongs/strongs_verse_sheet.dart';
import 'package:dba2/ui/translations/services/translation_store.dart';
import 'package:dba2/ui/widgets/toast.dart';

import 'control_box.dart'; // ControlAction
import 'verse_selection.dart'; // groupVerses

/// Everything that happens when a ControlBox button is pressed.
/// Kept next to control_box.dart and verse_selection.dart because it
/// works directly on the verse selection.
class ControlActionHandler {
  const ControlActionHandler({
    required this.controller,
    required this.bookmarks,
    required this.gallery,
  });

  final BibleController controller;
  final BookmarkStore bookmarks;
  final GalleryController gallery;

  /// Call this from ControlBox's onAction.
  Future<void> handle(BuildContext context, ControlAction action) async {
    if (!controller.selection.isActive) return;

    switch (action) {
      case ControlAction.copy:
        await Clipboard.setData(
          ClipboardData(text: controller.selectionAsText()),
        );
        showToast('Copied ${controller.selectionLabel()}');
        controller.selection.clear();

      case ControlAction.strongs:
        if (!context.read<AddonController>().hasStrongs) {
          promptAddonDownload(context, kStrongsDb);
          return;
        }
        final sel = controller.selection.sorted;
        if (sel.isNotEmpty) {
          final r = sel.first;
          showStrongsVerseSheet(
            context,
            bookId: r.bk,
            chapter: r.ch,
            verse: r.vs,
          );
        }

      case ControlAction.compare:
        final sel = controller.selection.sorted;
        if (sel.isEmpty) return;
        await showCompareSheet(
          context,
          store: context.read<TranslationStore>(),
          startId: sel.first.tr,
          bookId: sel.first.bk,
          chapter: sel.first.ch,
          bookName: _bookName(sel.first.bk),
          verses: [for (final r in sel) r.vs],
        );
        controller.selection.clear();

      case ControlAction.bookmark:
        final saved = await showBookmarkDialog(
          context,
          store: bookmarks,
          verses: _selectedVerses(),
        );
        if (saved == true) {
          controller.selection.clear();
          showToast('Bookmark saved');
        }

      case ControlAction.topic:
        final drafts = _draftEntries('topic');
        final name = await showTopicDialog(
          context,
          existing: [for (final t in gallery.topics) t.topic],
          refText: controller.selectionLabel(),
        );
        if (name == null || name.trim().isEmpty) return;
        final used = await gallery.addToTopic(name, drafts);
        controller.selection.clear();
        showToast('Added to "$used"');

      case ControlAction.note:
        // One note per verse: it goes on the first selected verse only.
        final first = _draftEntries('note', firstOnly: true).first;
        final extra = controller.selection.sorted.length - 1;
        final ref = '${first.bookName} ${first.chapter}:${first.verseId}';
        final existing =
            gallery.noteFor(
              first.translationId,
              first.bookId,
              first.chapter,
              first.verseId,
            ) ??
            '';
        final text = await showNoteDialog(
          context,
          refText: extra > 0
              ? '$ref  (note goes on the first of ${extra + 1})'
              : ref,
          initial: existing,
        );
        if (text == null || text.trim().isEmpty) return;
        await gallery.addNote(first, text);
        controller.selection.clear();
        showToast('Note saved');

      case ControlAction.editor:
        final md = context.read<MarkdownEditorController>();
        final entries = _draftEntries('topic');
        controller.selection.clear();
        await sendToEditor(md, [for (final e in entries) e.toMdVerse()]);

      case ControlAction.picture:
        final sel = controller.selection.sorted;
        // One block of text per run of consecutive verses.
        final texts = [
          for (final g in groupVerses(sel))
            g
                .map(
                  (r) => g.length == 1
                      ? controller.verseText(r)
                      : '${r.vs}. ${controller.verseText(r)}',
                )
                .join(' '),
        ];
        final citation = '${controller.selectionLabel()} (${sel.first.ed})';
        final meme = context.read<MemeMakerController>(); // read before await
        controller.selection.clear();
        await meme.injectVerses(texts, citation: citation);
        MemeMakerPage.open();
    }
  }

  /// Opens the note dialog for one verse (prefilled if it already has a note).
  /// Returns true if saved. Used by the reader's per-verse note icon.
  Future<bool> editNote(
    BuildContext context, {
    required String tr,
    required String bk,
    required int ch,
    required int vs,
    int extra = 0,
  }) async {
    final text = controller.verseText((
      ed: controller.edition,
      tr: tr,
      bk: bk,
      ch: ch,
      vs: vs,
    ));
    final verse = GalleryEntry(
      id: 0,
      entryType: 'note',
      translationId: tr,
      bookId: bk,
      bookName: _bookName(bk),
      chapter: ch,
      verseId: vs,
      text: text,
    );
    final ref = '${verse.bookName} $ch:$vs';

    final result = await showNoteDialog(
      context,
      refText: extra > 0
          ? '$ref  (note goes on the first of ${extra + 1})'
          : ref,
      initial: gallery.noteFor(tr, bk, ch, vs) ?? '',
    );
    if (result == null || result.trim().isEmpty) return false;

    await gallery.addNote(verse, result);
    showToast('Note saved');
    return true;
  }

  String _bookName(String id) {
    for (final b in controller.books) {
      if (b.id == id) return b.englishName;
    }
    return id;
  }

  // Selection -> gallery entries (id 0 = the repository assigns the real id).
  List<GalleryEntry> _draftEntries(String type, {bool firstOnly = false}) => [
    for (final r in controller.selection.sorted.take(
      firstOnly ? 1 : controller.selection.sorted.length,
    ))
      GalleryEntry(
        id: 0,
        entryType: type,
        translationId: r.tr,
        bookId: r.bk,
        bookName: _bookName(r.bk),
        chapter: r.ch,
        verseId: r.vs,
        text: controller.verseText(r),
      ),
  ];

  // Selection -> bookmark verses.
  List<BookmarkVerse> _selectedVerses() => [
    for (final r in controller.selection.sorted)
      BookmarkVerse(
        translationId: r.tr,
        bookId: r.bk,
        chapter: r.ch,
        verse: r.vs,
      ),
  ];
}
