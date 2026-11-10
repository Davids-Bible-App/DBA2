import 'package:dba2/main/gallery/bookmarks/bookmark_store.dart';
import 'package:dba2/main/controllers/split_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:dba2/storage/shared_state.dart';
import 'package:dba2/main/ui/split_reader.dart';
import 'package:dba2/ui/translations/ui/translation_sheet.dart';

import 'package:dba2/main/gallery/gallery_controller.dart';
import 'package:dba2/ui/controlbox/control_actions.dart';

import '../../ui/navigation/bar_action_runner.dart';
import '../../ui/controlbox/control_box.dart';
import '../../ui/navigation/reader_app_bar.dart';
import '../../ui/navigation/reader_bottom_bar.dart';
import '../controllers/bible_controller.dart';
import '../models/chapter_view.dart';
import '../../ui/extras/paper_overlay.dart';
import '../reader_gestures.dart';

import 'package:dba2/main/addons/crossrefs/cross_ref.dart';

const Color? kReaderTextColor = null;

// ---------------------------------------------------------------------------
// READER PAGE
// ---------------------------------------------------------------------------

class BibleReaderPage extends StatelessWidget {
  final BibleController controller;
  final ScrollController readerScroll;
  final BookmarkStore bookmarks;
  final double topStitch;
  final double botStitch;
  final GalleryController gallery;

  const BibleReaderPage({
    super.key,
    required this.controller,
    required this.readerScroll,
    required this.bookmarks,
    required this.gallery,
    this.topStitch = 4.5,
    this.botStitch = 4.0,
  });

  ControlActionHandler get _actions => ControlActionHandler(
    controller: controller,
    bookmarks: bookmarks,
    gallery: gallery,
  );

  @override
  Widget build(BuildContext context) {
    final runner = BarActionRunner(controller: controller);

    Widget buildFloatingNavBtn(IconData icon, VoidCallback onPressed) {
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: context.colorScheme.surface,
          foregroundColor: Theme.of(context).colorScheme.inverseSurface,
          padding: const EdgeInsets.all(8),
          side: const BorderSide(
            width: 1,
            color: Color.fromARGB(255, 99, 99, 99),
          ),
          elevation: 4,
        ),
        child: Icon(icon, size: 24),
      );
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sticky = context.watch<AppSettings>().stickyHeader;
        final textured = context.select<AppSettings, bool>(
          (s) => s.bodyTexture,
        );
        final book = controller.currentBook;
        // Instead of evaluating by null, by stickyHeader false?
        final String? title = sticky
            ? null
            : (book == null
                  ? "David's Bible App"
                  : '${book.englishName} ${controller.selectedChapter}');

        final bottomInset = MediaQuery.paddingOf(context).bottom;

        return Stack(
          children: [
            Scaffold(
              appBar: ReaderAppBar(
                title: title,
                topStitch: topStitch,
                runner: runner,
              ),
              bottomNavigationBar: ReaderBottomBar(
                controller: controller,
                botStitch: botStitch,
                runner: runner,
              ),
              body: ReaderGestures(
                fontSize: controller.fontSize,
                onPrevious: controller.previous,
                onNext: controller.next,
                isBlocked: () =>
                    controller.selection.isActive ||
                    context.read<SplitController>().draggingDivider,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: textured
                            ? PaperOverlay(opacity: 1)
                            : ColoredBox(color: context.colorScheme.secondary),
                      ),
                    ),

                    SplitReader(primary: _content(context)),

                    // AppBar BottomShadow For Lift
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 10,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.15),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Paging buttons: fade out while verses are selected, so they never
            // overlap the control box.
            ListenableBuilder(
              listenable: controller.selection,
              builder: (context, _) {
                final hide = controller.selection.isActive;
                return Positioned.fill(
                  child: IgnorePointer(
                    ignoring: hide,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: hide ? 0 : 1,
                      child: Stack(
                        children: [
                          Positioned(
                            left: -3,
                            bottom: 35.0 + bottomInset,
                            child: buildFloatingNavBtn(
                              Icons.navigate_before_rounded,
                              controller.previous,
                            ),
                          ),
                          Positioned(
                            right: -3,
                            bottom: 35.0 + bottomInset,
                            child: buildFloatingNavBtn(
                              Icons.navigate_next_rounded,
                              controller.next,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Control box: last child, so it covers the bottom nav bar.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                type: MaterialType.transparency,
                child: ListenableBuilder(
                  listenable: controller.selection,
                  builder: (_, child) => OverlayLock(
                    active: controller.selection.isActive,
                    child: child!,
                  ),
                  child: ControlBox(
                    selection: controller.selection,
                    highlights: controller.highlights,
                    onAction: (a) => _actions.handle(context, a),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _content(BuildContext context) {
    if (controller.needsTranslation) return const NoTranslationPlaceholder();

    final data = controller.chapter;

    if (controller.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(controller.error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (controller.isLoading || data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final book = controller.currentBook;
    final isFirstChapter = controller.selectedChapter == 1;

    // .Bible-header: chapter 1 shows the book title in italics.
    final header = book == null
        ? ''
        : isFirstChapter
        ? (book.title.isNotEmpty
              ? book.title
              : (book.name.isNotEmpty ? book.name : book.englishName))
        : '${book.englishName} - chapter ${controller.selectedChapter}';

    Widget content = Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: controller.fontSize,
            builder: (context, _) {
              return ChapterCrossRefs(
                bookId: controller.selectedBookId,
                chapter: controller.selectedChapter,
                builder: (context, refVerses) => ChapterView(
                  key: ValueKey(
                    '${controller.translationId}-${controller.selectedBookId}-${controller.selectedChapter}',
                  ),
                  fontSize: controller.fontSize.px,
                  stickyHeader: context.watch<AppSettings>().stickyHeader,
                  chapter: data,
                  headerText: header,
                  headerItalic: isFirstChapter,
                  translationId: controller.translationId,
                  edition: controller.edition,
                  bookId: controller.selectedBookId,
                  chapterNumber: controller.selectedChapter,
                  selection: controller.selection,
                  highlights: controller.highlights,
                  scrollController: readerScroll,
                  verseGoto: controller.verseGoto,
                  notesListenable: gallery,
                  noteFor: (vs) => gallery.noteFor(
                    controller.translationId,
                    controller.selectedBookId,
                    controller.selectedChapter,
                    vs,
                  ),
                  onEditNote: (vs) => _actions.editNote(
                    context,
                    tr: controller.translationId,
                    bk: controller.selectedBookId,
                    ch: controller.selectedChapter,
                    vs: vs,
                  ),
                  crossRefVerses: refVerses,
                  onCrossRef: (vs) => showCrossRefSheet(
                    context,
                    bible: controller,
                    bookId: controller.selectedBookId,
                    chapter: controller.selectedChapter,
                    verse: vs,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );

    if (kReaderTextColor != null) {
      content = DefaultTextStyle.merge(
        style: TextStyle(color: kReaderTextColor),
        child: content,
      );
    }
    return content;
  }
}
