import 'package:dba2/main/addons/addon_controller.dart';
import 'package:dba2/main/addons/addon_store.dart';
import 'package:dba2/components/ai/ai_launcher.dart';
import 'package:dba2/components/audio/ui/open_audio_sheet.dart';
import 'package:dba2/main/addons/crossrefs/cross_ref.dart';
import 'package:dba2/main/history/history_sheet.dart';
import 'package:dba2/components/markdown_editor/md_controller.dart';
import 'package:dba2/components/meme_maker/meme_maker_page.dart';
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/main/search/send_to_editor.dart';
import 'package:dba2/ui/navigation/bar_gesture_settings.dart';
import 'package:dba2/storage/shared_state.dart';
import 'package:dba2/main/addons/strongs/strongs_lookup_sheet.dart';
import 'package:dba2/ui/translations/ui/translation_sheet.dart';
import 'package:dba2/ui/widgets/ikon_btn.dart';
import 'package:dba2/ui/extras/burn_in_text.dart';
import 'package:dba2/ui/settings/settings_page.dart';

import 'bar_action_runner.dart';
import 'bar_gesture_detector.dart';
import '../widgets/menu_btn.dart';
import '../extras/app_bar_background.dart';

/// Bottom bar for the Bible reader page.
///
/// Use as `Scaffold(bottomNavigationBar: ReaderBottomBar(botStitch: ...))`.
class ReaderBottomBar extends StatelessWidget {
  final double botStitch;
  final BarActionRunner runner;
  final BibleController controller;

  const ReaderBottomBar({
    super.key,
    required this.runner,
    required this.controller,
    this.botStitch = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    final textured = context.select<AppSettings, bool>((s) => s.navBTexture);
    final bar = BottomAppBar(
      height: 48,
      padding: EdgeInsets.zero, // Allows background to stretch edge-to-edge
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: Background
          AppBarBackground(
            stitches: botStitch > 0,
            top: false,
            inset: botStitch,
            textured: textured,
          ),

          // Layer 2: Foreground / Buttons
          Padding(
            padding: const EdgeInsets.only(
              bottom: 6.0,
              top: 0,
              left: 8,
              right: 8,
            ),
            child: Row(
              children: [
                // 1. Left Menu Button with exact edge spacing
                Padding(
                  padding: const EdgeInsets.only(
                    left: 50.0,
                  ), // Adjust exact distance from left edge
                  child: IkonBtn(
                    icon: const Icon(Icons.history),
                    onPressed: () => showHistorySheet(context),
                    tooltip: 'History',
                  ),
                ),

                // 2. Centered Text (Expanded forces it to take the middle, Center keeps the text true-center)
                Expanded(
                  child: Center(
                    child: BurnInText(
                      context.select<AppSettings, String>((s) => s.appTitle),
                    ),
                  ),
                ),
                // 3. Right Menu Button with exact edge spacing
                Padding(
                  padding: const EdgeInsets.only(
                    right: 50.0,
                  ), // Adjust exact distance from right edge
                  child: MenuBtn(
                    flipX: true,
                    icon: const Icon(Icons.grain),
                    startRight: true,
                    actions: [
                      MenuAction(
                        icon: const Icon(Icons.settings_outlined),
                        label: 'Settings',
                        onTap: () {
                          showSettingsSheet(context, controller: controller);
                        },
                      ),
                      MenuAction(
                        icon: const Icon(Icons.book_outlined),
                        label: 'Strongs',
                        onTap: () {
                          if (context.read<AddonController>().hasStrongs) {
                            showStrongsLookupSheet(context);
                          } else {
                            promptAddonDownload(context, kStrongsDb);
                          }
                        },
                      ),
                      MenuAction(
                        icon: const Icon(Icons.list_alt_rounded),
                        label: 'References',
                        onTap: () => reopenLastCrossRefSheet(context),
                      ),
                      MenuAction(
                        icon: const Icon(Icons.graphic_eq),
                        label: 'Audio Bible',
                        onTap: () {
                          openAudioSheet(context);
                        },
                      ),
                      MenuAction(
                        icon: const Icon(Icons.auto_awesome),
                        label: 'Bible Chat',
                        onTap: () => context.read<AiLauncher>().open(),
                      ),
                      MenuAction(
                        icon: const Icon(Icons.graphic_eq),
                        label: 'MD Editor',
                        onTap: () {
                          openEditor(context.read<MarkdownEditorController>());
                        },
                      ),
                      MenuAction(
                        icon: const Icon(Icons.image),
                        label: 'MemeMaker',
                        onTap: () => MemeMakerPage.open(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return BarGestureDetector(
      side: BarSide.bottom,
      runner: runner,
      child: bar,
    );
  }
}
