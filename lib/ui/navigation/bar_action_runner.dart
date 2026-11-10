import 'package:dba2/main/addons/addon_controller.dart';
import 'package:dba2/main/addons/addon_store.dart';
import 'package:dba2/components/ai/ai_launcher.dart';
import 'package:dba2/components/audio/ui/open_audio_sheet.dart';
import 'package:dba2/core.dart';
import 'package:dba2/main/history/history_sheet.dart';
import 'package:dba2/components/markdown_editor/markdown_editor.dart';
import 'package:dba2/components/meme_maker/meme_maker_page.dart';
import 'package:dba2/main/search/send_to_editor.dart';
import 'package:dba2/ui/navigation/bar_gesture_settings.dart';
import 'package:dba2/main/addons/strongs/strongs_lookup_sheet.dart';
import 'package:dba2/ui/translations/ui/translation_sheet.dart';
import 'package:dba2/ui/settings/settings_page.dart';

import '../sidebar_reveal.dart';
import '../../main/controllers/bible_controller.dart';

import 'package:dba2/main/addons/crossrefs/cross_ref.dart';

/// The one place that knows what each [BarAction] actually does.
///
/// Features that don't exist yet are empty `{}` blocks: fill them in later
/// and every gesture assigned to them starts working.
class BarActionRunner {
  BarActionRunner({required this.controller});

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
        openAudioSheet(context);
      case BarAction.previousChapter:
        controller.previous();
      case BarAction.nextChapter:
        controller.next();
      case BarAction.settings:
        showSettingsSheet(context, controller: controller);
      case BarAction.translations:
        openTranslationSheet(context);
      case BarAction.search:
        showSearchSheetWithEditor(context);
      case BarAction.references:
        reopenLastCrossRefSheet(context);
      case BarAction.strongs:
        {
          if (context.read<AddonController>().hasStrongs) {
            showStrongsLookupSheet(context);
          } else {
            promptAddonDownload(context, kStrongsDb);
          }
        }
      case BarAction.history:
        showHistorySheet(context);
      case BarAction.bibleAi:
        context.read<AiLauncher>().open();
      case BarAction.mdEditor:
        openEditor(context.read<MarkdownEditorController>());
      case BarAction.mememaker:
        {
          MemeMakerPage.open();
        }
    }
  }
}
