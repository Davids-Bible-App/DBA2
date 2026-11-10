import 'dart:io';

import 'package:dba2/components/ai/ai_launcher.dart';
import 'package:dba2/components/ai/ai_prefs.dart';
import 'package:dba2/components/audio/ui/open_audio_sheet.dart';
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/main/controllers/split_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/main/search/send_to_editor.dart';
import 'package:dba2/ui/navigation/bar_gesture_settings.dart';
import 'package:dba2/main/ui/book_abbreviations.dart';
import 'package:dba2/storage/shared_state.dart';
import 'package:dba2/components/streak/streak_badge.dart';
import 'package:dba2/components/streak/streak_controller.dart';
import 'package:dba2/ui/widgets/ikon_btn.dart';
import 'package:dba2/main/ui/split_reader.dart';
import 'package:dba2/ui/translations/ui/translation_sheet.dart';

import 'bar_action_runner.dart';
import 'bar_gesture_detector.dart';
import '../sidebar_reveal.dart';
import '../extras/app_bar_background.dart';

/// Below this width (logical pixels) there's room for only one of the
/// AI / Audio buttons. Typical phones are 360-430, tablets 600+.
const double _kWideBar = 600;

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
    final textured = context.select<AppSettings, bool>((s) => s.navTTexture);
    final isDark = context.isDark;
    final stitchOffset = Offset(0, topStitch > 0 ? topStitch - 3 : 0.0);
    final aiOn = context.select<AiPrefs, bool>((p) => p.visible);
    final wide = MediaQuery.sizeOf(context).width >= _kWideBar;
    final actions = <Widget>[
      StreakBadge(
        controller: context.read<StreakController>(),
        buttonBuilder: (context, onPressed, label) => Transform.translate(
          offset: const Offset(0, 1),
          child: IkonBtn(
            tooltip: 'Daily streak',
            onPressed: onPressed,
            icon: Builder(
              builder: (c) => SizedBox(
                width: 19, // usable width inside the 25px circle
                child: FittedBox(
                  fit: BoxFit.scaleDown, // only shrinks, never enlarges
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: IconTheme.of(c)
                          .color, // same grey as your other icons
                      fontSize: 13,
                      height: 1,
                    ),
                    // Text Label Position Adjusment, For Icons goto: IkonBtn
                    child: Transform.translate(
                      offset: isDark
                          ? Offset(0, -0.5)
                          : Offset(0, -1), // tweak this
                      child: label,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      if (aiOn)
        Transform.translate(
          offset: const Offset(0, 1),
          child: IkonBtn(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Bible AI',
            onPressed: () => context.read<AiLauncher>().open(),
          ),
        ),
      if (aiOn && wide) const SizedBox(width: 10),
      // Audio: always when AI is off; also alongside AI on wide screens.
      if (!aiOn || wide)
        Transform.translate(
          offset: const Offset(0, 1),
          child: IkonBtn(
            icon: const Icon(Icons.headset_outlined),
            tooltip: 'Audio player',
            onPressed: () => openAudioSheet(context),
          ),
        ),
      const SizedBox(width: 10),
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
            textured: textured,
          ),
          // AppBar TopShadow For Android Divide
          if (Platform.isAndroid && isDark)
            Positioned(
              left: 0,
              right: 0,
              top: -5,
              child: RepaintBoundary(
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: -20,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black26,
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
                onPressed: () => showSearchSheetWithEditor(context),
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
