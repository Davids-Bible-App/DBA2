// lib/ui/bar_action_runner.dart
import 'package:dba2/core.dart';
import 'package:dba2/state/bar_gesture_settings.dart';
import 'package:dba2/state/overlay_lock.dart';
import 'package:dba2/ui/audio_bar.dart';
import 'package:dba2/ui/translation_sheet.dart';
import 'package:dba2/widgets/settings/settings_page.dart';

import 'sidebar_reveal.dart';
import '../controllers/bible_controller.dart';

/// The one place that knows what each [BarAction] actually does.
///
/// Features that don't exist yet are empty `{}` blocks: fill them in later
/// and every gesture assigned to them starts working.
class BarActionRunner {
  const BarActionRunner({required this.controller});

  final BibleController controller;

  void run(BuildContext context, BarAction action) {
    switch (action) {
      case BarAction.none:
        break;

      // ---- Already available ------------------------------------------
      case BarAction.openLeftSidebar:
        SidebarReveal.of(context).toggleLeft();
      case BarAction.openRightSidebar:
        SidebarReveal.of(context).toggleRight();
      case BarAction.audioPlayer:
        showLockedBottomSheet<void>(
          context: context,
          builder: (_) => AudioBar(),
        );
      case BarAction.previousChapter:
        controller.previous();
      case BarAction.nextChapter:
        controller.next();

      // ---- Not built yet: fill in later -------------------------------
      case BarAction.history:
        {}
      case BarAction.settings:
        showSettingsSheet(context, controller: controller);

      case BarAction.strongs:
        {}
      case BarAction.memes:
        {}
      case BarAction.mdEditor:
        {}
      case BarAction.translations:
        {
          openTranslationSheet(context);
        }
    }
  }
}
