import 'dart:async';

import 'package:dba2/components/ai/ai_prefs.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'package:dba2/ui/widgets/toast.dart';
import 'package:dba2/storage/profile/profile.dart';
import 'package:dba2/core.dart';
import 'package:dba2/components/audio/link/reader_audio_link.dart';
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/main/ui/bible_reader_page.dart';
import 'package:dba2/ui/sidebar_left_content.dart';
import 'package:dba2/ui/sidebar_reveal.dart';
import 'package:dba2/ui/sidebar_right_content.dart';
import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:dba2/ui/translations/services/translation_store.dart';
import 'package:dba2/ui/translations/services/translation_catalog.dart';

import 'main/gallery/gallery_controller.dart';
import 'main/gallery/models.dart';
import 'main/gallery/notes/notes_panel.dart';
import 'main/gallery/topics/topics_panel.dart';
import 'main/gallery/bookmarks/bookmark_store.dart';
import 'main/gallery/bookmarks/bookmarks_panel.dart';
import 'main/gallery/bookmarks/sqlite_bookmark_repository.dart';
import 'main/gallery/sqlite_gallery_repository.dart';
import 'ui/widgets/uni_verse.dart';

import 'package:dba2/main/search/send_to_editor.dart';
import 'package:dba2/components/markdown_editor/md_controller.dart';

import 'dart:ui' show AppExitResponse;

import 'package:dba2/components/ai/ai_launcher.dart';

class DavidsBibleApp2 extends StatefulWidget {
  const DavidsBibleApp2({super.key});

  @override
  State<DavidsBibleApp2> createState() => _DavidsBibleApp2State();
}

extension GalleryEntryUni on GalleryEntry {
  UniVerseItem toUniVerse() =>
      UniVerseItem(citation: '$abbr $bookName $chapter:$verseId', text: text);
}

class _DavidsBibleApp2State extends State<DavidsBibleApp2> {
  // Created once. null result == add-on not installed.
  // late final Future<AiServices?> _ai = AiServices.create();
  late final _ai = AiLauncher(context.read<AiPrefs>());
  late final AppLifecycleListener _lifecycle;

  final _uniVerse = ValueNotifier<List<UniVerseItem>?>(null);
  bool? _windowIconIsDark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ReaderAudioLink>().attach();
      if (mounted) context.read<AiPrefs>().detectAvailability();
    });
    // Stop the llama-server child process when the user closes the app window.
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await _ai.dispose();
        return AppExitResponse.exit;
      },
    );
  }

  late final bookmarks = BookmarkStore(
    SqliteBookmarkRepository(context.read<ProfileRepository>()),
    bookName: (id) {
      final books = context.read<BibleController>().books;
      for (final b in books) {
        if (b.id == id) return b.englishName;
      }
      return id;
    },
    translationLabel: (id) => translationFor(id).abbr,
  );

  late final gallery = GalleryController(
    SqliteGalleryRepository(
      context.read<ProfileRepository>(),
      VerseTextLookup(context.read<TranslationStore>()),
    ),
  );

  @override
  void dispose() {
    _uniVerse.dispose();
    gallery.dispose();
    bookmarks.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

  /// Topics + Notes "Go to Verse". Gallery rows may carry "eng_kjv.dba";
  /// the controller's ids have no extension.
  Future<void> _jumpToEntry(BuildContext sidebarCtx, GalleryEntry v) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final bible = context.read<BibleController>();
    final reveal = SidebarReveal.of(sidebarCtx); // grab before any await
    final tr = v.translationId.replaceFirst(
      RegExp(r'\.dba$', caseSensitive: false),
      '',
    );
    if (tr.isNotEmpty && tr != bible.translationId) {
      await bible.setTranslation(tr);
    }
    bible.goTo(v.bookId, v.chapter, verse: v.verseId);
    reveal.close();
  }

  Future<void> _updateWindowIcon(bool isDark) async {
    final icon = isDark
        // ? 'assets/icon/titlebar_dark_fill.ico'
        ? 'assets/icon/titlebar_light_fill.ico'
        : 'assets/icon/titlebar_light_fill.ico';
    try {
      await windowManager.setIcon(icon);
    } catch (error) {
      debugPrint('Failed to update window icon: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bible = context.read<BibleController>();

    return MultiProvider(
      providers: [
        Provider<AiLauncher>.value(value: _ai),
        ListenableProvider<ValueNotifier<List<UniVerseItem>?>>.value(
          value: _uniVerse,
        ),
        ChangeNotifierProvider<GalleryController>.value(value: gallery),
        ChangeNotifierProvider<BookmarkStore>.value(value: bookmarks),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        title: "David's Bible App v2",
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: context.watch<ThemeProvider>().themeMode,
        home: _BackCloseSidebar(
          child: BibleReaderPage(
            controller: bible,
            readerScroll: bible.readerScroll,
            bookmarks: bookmarks,
            gallery: gallery,
          ),
        ),
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          if (defaultTargetPlatform == TargetPlatform.windows &&
              _windowIconIsDark != isDark) {
            _windowIconIsDark = isDark;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_updateWindowIcon(isDark));
            });
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              SidebarReveal(
                dragZoneTopInset: kToolbarHeight,
                dragZoneBottomInset: 88,
                openFraction: 0.92,
                fadeIn: true,
                fadeStartOpacity: 0.3,
                fadeEndOpacity: 1.0,
                leftSidebar: HeroControllerScope.none(
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => SidebarLeftContent(controller: bible),
                    ),
                  ),
                ),
                rightSidebar: HeroControllerScope.none(
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (sidebarCtx) => SidebarRightContent(
                        onSwipePastFirstTab: () {
                          if (gallery.selectedTopic != null) {
                            gallery.selectTopic(
                              null,
                            ); // inside a topic: back to the titles
                          } else {
                            SidebarReveal.of(sidebarCtx)
                                .close(); // on the titles: close sidebar
                          }
                        },
                        topics: Material(
                          type: MaterialType.transparency,
                          child: TopicsPanel(
                            controller: gallery,
                            onJumpTo: (v) => _jumpToEntry(sidebarCtx, v),
                            onExportToEditor: (topic, desc, verses) {
                              final md = context
                                  .read<MarkdownEditorController>();
                              SidebarReveal.of(sidebarCtx).close();
                              sendToEditor(
                                md,
                                [for (final v in verses) v.toMdVerse()],
                                heading: topic,
                                intro: desc,
                              );
                            },
                            onOpenUniVerse: (verses) {
                              if (verses.isEmpty) return;
                              _uniVerse.value = [
                                for (final v in verses) v.toUniVerse(),
                              ];
                            },
                          ),
                        ),
                        notes: Material(
                          type: MaterialType.transparency,
                          child: NotesPanel(
                            controller: gallery,
                            onJumpTo: (v) => _jumpToEntry(sidebarCtx, v),
                          ),
                        ),
                        bookmarks: BookmarksPanel(
                          store: bookmarks,
                          onJumpTo: (v) async {
                            final reveal = SidebarReveal.of(sidebarCtx);
                            if (v.translationId.isNotEmpty &&
                                v.translationId != bible.translationId) {
                              await bible.setTranslation(v.translationId);
                            }
                            bible.goTo(v.bookId, v.chapter, verse: v.verse);
                            reveal.close();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                child: child!,
              ),
              ValueListenableBuilder<List<UniVerseItem>?>(
                valueListenable: _uniVerse,
                builder: (_, verses, _) => verses == null
                    ? const SizedBox.shrink()
                    : OverlayLock(
                        active: true,
                        child: UniVerse(
                          verses: verses,
                          onClose: () => _uniVerse.value = null,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Android back button: closes an open sidebar instead of exiting the app.
class _BackCloseSidebar extends StatelessWidget {
  const _BackCloseSidebar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reveal = SidebarReveal.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: reveal.isOpen,
      builder: (_, open, child) => PopScope(
        canPop: !open, // sidebar open -> block the pop
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) reveal.close(); // close it instead
        },
        child: child!,
      ),
      child: child,
    );
  }
}
