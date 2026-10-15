// lib/ui/reader_app_bar.dart
import 'dart:io';

import 'package:dba2/controllers/bible_controller.dart';
import 'package:dba2/controllers/split_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/state/bar_gesture_settings.dart';
import 'package:dba2/state/overlay_lock.dart';
import 'package:dba2/ui/audio_bar.dart';
import 'package:dba2/ui/book_abbreviations.dart';
import 'package:dba2/ui/ikon_btn.dart';
import 'package:dba2/ui/split_reader.dart';
import 'package:dba2/ui/translation_sheet.dart';

import 'bar_action_runner.dart';
import 'bar_gesture_detector.dart';
import 'sidebar_reveal.dart';
import '../widgets/app_bar_background.dart';

/// Top app bar for the Bible reader page.
///
/// Use as `Scaffold(appBar: ReaderAppBar(title: ..., topStitch: ...))`.
class ReaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final double topStitch;
  final BarActionRunner runner;

  const ReaderAppBar({
    super.key,
    required this.title,
    required this.runner,
    this.topStitch = 4.5,
  });

  static const double _toolbarHeight = 48;

  @override
  Size get preferredSize => const Size.fromHeight(_toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final stitchOffset = Offset(0, topStitch > 0 ? topStitch - 3 : 0.0);

    // TranslationRibbon removed from actions here
    final actions = <Widget>[
      Transform.translate(
        offset: Offset(0, 1),
        child: IkonBtn(
          icon: const Icon(Icons.headset_outlined),
          tooltip: 'Audio player',
          onPressed: () {
            showLockedBottomSheet<void>(
              backgroundColor: context.colorScheme.secondary,
              context: context,
              builder: (_) => AudioBar(),
            );
          },
        ),
      ),
      SizedBox(
        width: 10,
      ),
      Transform.translate(
        offset: Offset(0, 1),
        child: IkonBtn(
          icon: Icon(
            context.select<SplitController, bool>((s) => s.enabled)
                ? Icons.view_agenda
                : Icons.view_agenda_outlined,
          ),
          tooltip: 'Split view',
          onPressed: () => toggleSplit(context),
        ),
      ),
      Transform.translate(
        offset: Offset(0, 2),
        child: IconButton(
          icon: RotatedBox(
            quarterTurns: 4,
            child: Icon(
              Icons.blur_linear,
              size: 25,
              color: Colors.grey[500],
              // color: context.colorScheme.onSurface,
            ),
            // child: Icon(Icons.video_label_rounded, size: 18),
          ),
          tooltip: 'Right sidebar (Ctrl+Shift+B)',
          onPressed: () => SidebarReveal.of(context).toggleRight(),
        ),
      ),
    ];
    final t = title; // local copy so Dart can promote String? to String
    final bar = AppBar(
      toolbarHeight: _toolbarHeight,
      elevation: 0,
      leadingWidth: 110.0, // Expanded width to fit both leading items
      flexibleSpace: Stack(
        fit: StackFit.expand,
        children: [
          AppBarBackground(
            stitches: topStitch > 0,
            top: true,
            inset: Platform.isAndroid ? 0 : topStitch,
            textured: false,
          ),
          // AppBar TopShadow For Android Divide
          if (Platform.isAndroid && isDark)
            Positioned(
              left: 0,
              right: 0,
              top: -20,
              child: RepaintBoundary(
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 20,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              context.colorScheme.tertiary,
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      // Multiple leading buttons handled via Row inside leading
      leading: Transform.translate(
        offset: stitchOffset,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: Offset(0, 2),
              child: IconButton(
                icon: RotatedBox(
                  quarterTurns: 2,
                  child: Icon(
                    Icons.blur_linear,
                    size: 25,
                    color: Colors.grey[500],
                  ),
                  // child: Icon(Icons.video_label_rounded, size: 18),
                ),
                tooltip: 'Left sidebar',
                onPressed: () => SidebarReveal.of(context).toggleLeft(),
              ),
            ),
            Transform.translate(
              offset: Offset(0, 1),
              child: IkonBtn(
                icon: Icon(Icons.search),
                tooltip: 'Search',
                onPressed: () {},
              ),
            ),
            Transform.translate(
              offset: Offset(14, -13),
              child: TranslationRibbon(
                abbr: context.select<BibleController, String>((b) => b.edition),
                onTap: () => openTranslationSheet(context),
              ),
            ),
          ],
        ),
      ),
      title: t == null
          ? null
          : Transform.translate(
              // topStitch - 2 android - 4 Windows
              offset: Offset(0, topStitch > 0 ? topStitch - 2 : 0.0),
              child: _AppBarTitle(t),
            ),
      actions: actions
          .map((a) => Transform.translate(offset: stitchOffset, child: a))
          .toList(),
    );

    return BarGestureDetector(
      side: BarSide.top,
      runner: runner,
      child: bar,
    );
  }
}

/// Full title if it fits, else the abbreviation, else shrink to fit.
class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, c) {
        bool fits(String s) {
          final tp = TextPainter(
            text: TextSpan(text: s, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w <= c.maxWidth;
        }

        final shown = fits(text) ? text : abbreviateTitle(text);
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(shown, maxLines: 1, softWrap: false),
          ),
        );
      },
    );
  }
}
