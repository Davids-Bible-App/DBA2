// lib/widgets/settings_page.dart
import 'package:dba2/controllers/bible_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/state/shared_state.dart';
import 'package:dba2/widgets/bar_gesture_settings_section.dart';
import 'package:flutter/cupertino.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final BibleController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context); // listens

    return Scaffold(
      backgroundColor: context.colorScheme.surfaceDim,
      appBar: AppBar(
        title: const Text("S E T T I N G S"),
        backgroundColor: context.colorScheme.onTertiary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(25),
        children: [
          _SettingTile(
            label: 'Use system theme',
            value: theme.followsSystem,
            onChanged: (useSystem) {
              if (useSystem) {
                theme.setThemeMode(ThemeMode.system);
              } else {
                // Pin to whatever is currently showing, so nothing flips.
                theme.setThemeMode(
                  theme.isDark(context) ? ThemeMode.dark : ThemeMode.light,
                );
              }
            },
          ),
          const SizedBox(height: 12),
          _SettingTile(
            label: 'Dark Mode',
            value: theme.isDark(context),
            onChanged: (dark) =>
                theme.setThemeMode(dark ? ThemeMode.dark : ThemeMode.light),
          ),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _SettingTile(
              label: 'Sticky chapter title',
              value: context.watch<AppSettings>().stickyHeader,
              onChanged: context.read<AppSettings>().setStickyHeader,
            ),
          ),

          // Bar gesture mapping (top + bottom bar)
          const BarGestureSettingsSection(),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.tertiary,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
