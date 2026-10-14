// lib/ui/bible_reader_page.dart
import 'package:dba2/controllers/split_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/state/overlay_lock.dart';
import 'package:dba2/state/shared_state.dart';
import 'package:dba2/ui/split_reader.dart';
import 'package:dba2/ui/translation_sheet.dart';
import 'package:flutter/services.dart';

import 'bar_action_runner.dart';
import 'control_box.dart';
import 'reader_app_bar.dart';
import 'reader_bottom_bar.dart';
import '../controllers/bible_controller.dart';
import '../models/chapter_view.dart';
import '../widgets/paper_overlay.dart';
import '../widgets/reader_gestures.dart';

const Color? kReaderTextColor = null;

// ---------------------------------------------------------------------------
// READER PAGE
// ---------------------------------------------------------------------------

class BibleReaderPage extends StatelessWidget {
  final BibleController controller;
  final ScrollController readerScroll;
  final double topStitch;
  final double botStitch;

  const BibleReaderPage({
    super.key,
    required this.controller,
    required this.readerScroll,
    this.topStitch = 4.5,
    this.botStitch = 4.0,
  });

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
                    const Positioned.fill(
                      child: RepaintBoundary(
                        child: PaperOverlay(opacity: 1),
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
                    onAction: (a) => _onAction(context, a),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onAction(BuildContext context, ControlAction action) async {
    if (!controller.selection.isActive) return;
    final messenger = ScaffoldMessenger.of(context);

    if (action == ControlAction.copy) {
      await Clipboard.setData(
        ClipboardData(text: controller.selectionAsText()),
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Copied ${controller.selectionLabel()}')),
      );
      controller.selection.clear();
      return;
    }

    // Not wired yet: shows what each button will receive.
    final label = controller.selectionLabel();
    debugPrint('${action.name}: $label');
    messenger.showSnackBar(
      SnackBar(content: Text('${action.name}: $label (not wired yet)')),
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
              return ChapterView(
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
