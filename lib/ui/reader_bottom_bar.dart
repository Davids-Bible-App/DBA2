// lib/ui/reader_bottom_bar.dart
import 'package:dba2/state/bar_gesture_settings.dart';
import 'package:dba2/widgets/burn_in_text.dart';
import 'package:flutter/material.dart';

import 'bar_action_runner.dart';
import 'bar_gesture_detector.dart';
import 'menu_btn.dart';
import '../widgets/app_bar_background.dart';

/// Bottom bar for the Bible reader page.
///
/// Use as `Scaffold(bottomNavigationBar: ReaderBottomBar(botStitch: ...))`.
class ReaderBottomBar extends StatelessWidget {
  final double botStitch;
  final BarActionRunner runner;

  const ReaderBottomBar({
    super.key,
    required this.runner,
    this.botStitch = 4.0,
  });

  @override
  Widget build(BuildContext context) {
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
            textured: false,
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
                  child: MenuBtn(
                    icon: const Icon(Icons.history),
                    onPressed: () {},
                    tooltip: 'History',
                  ),
                ),

                // 2. Centered Text (Expanded forces it to take the middle, Center keeps the text true-center)
                const Expanded(
                  child: Center(
                    child: BurnInText("David's Bible App"),
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
                        onTap: () {},
                      ),
                      MenuAction(
                        icon: const Icon(Icons.menu_book_outlined),
                        label: 'Strongs',
                        onTap: () {},
                      ),
                      MenuAction(
                        icon: const Icon(Icons.image_outlined),
                        label: 'Memes',
                        onTap: () {},
                      ),
                      MenuAction(
                        icon: const Icon(Icons.edit_note),
                        label: 'MDEditor',
                        onTap: () {},
                      ),
                      MenuAction(
                        icon: const Icon(Icons.graphic_eq),
                        label: 'Audio',
                        onTap: () {},
                      ),
                      MenuAction(
                        icon: const Icon(Icons.refresh),
                        label: 'Refresh',
                        onTap: () {},
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
