import 'package:dba2/components/ai/ai_prefs.dart';
import 'package:dba2/components/audio/controllers/audio_controller.dart';
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:dba2/storage/shared_state.dart';
import 'package:dba2/ui/navigation/bar_gesture_settings_section.dart';
import 'package:dba2/ui/settings/about_page.dart';
import 'package:dba2/ui/settings/settings_kit.dart';
import 'package:dba2/storage/profile/profile_settings_section.dart';

/// Full-screen settings (pushed as a route).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final BibleController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.secondary,
      body: SettingsBody(
        controller: controller,
        header: const SliverAppBar.large(title: Text('Settings')),
      ),
    );
  }
}

/// Settings as a *locked* bottom sheet (sidebar gestures disabled while open).
/// This opens the sheet itself: just call it, don't wrap it in another sheet.
Future<void> showSettingsSheet(
  BuildContext context, {
  required BibleController controller,
}) {
  return showLockedBottomSheet<void>(
    context: context,
    overshootExtent: MediaQuery.sizeOf(context).height * 0.12,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => SettingsBody(
        controller: controller,
        scrollController: scrollController, // lets the sheet drag + scroll
        header: SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Settings',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The actual content. No Scaffold, so it works in a page OR a sheet.
/// Add new sections to the list below.
class SettingsBody extends StatelessWidget {
  const SettingsBody({
    super.key,
    required this.controller,
    required this.header,
    this.scrollController,
  });

  final BibleController controller;
  final Widget header; // a sliver
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context); // listens
    final audio = context.watch<AudioController>(); // listens
    final app = context.watch<AppSettings>();
    final ai = context.watch<AiPrefs>();

    final sections = <Widget>[
      SettingsSection(
        title: 'Personalization',
        children: [
          SettingsTextTile(
            icon: Icons.person_outline,
            title: 'Your name',
            subtitle: 'Shown in the bottom bar',
            hint: 'e.g. David',
            value: app.userName,
            onChanged: app.setUserName,
          ),
        ],
      ),

      SettingsSection(
        title: 'Appearance',
        children: [
          SettingsSwitchTile(
            icon: Icons.brightness_auto_outlined,
            title: 'Use system theme',
            value: theme.followsSystem,
            onChanged: (useSystem) {
              if (useSystem) {
                theme.setThemeMode(ThemeMode.system);
              } else {
                theme.setThemeMode(
                  theme.isDark(context) ? ThemeMode.dark : ThemeMode.light,
                );
              }
            },
          ),
          SettingsSwitchTile(
            icon: Icons.dark_mode_outlined,
            title: 'Dark mode',
            value: theme.isDark(context),
            onChanged: (dark) =>
                theme.setThemeMode(dark ? ThemeMode.dark : ThemeMode.light),
          ),
          SettingsSwitchTile(
            icon: Icons.texture_rounded,
            title: 'Top NavBar Texture',
            value: app.navTTexture,
            onChanged: app.setNavTTexture,
          ),
          SettingsSwitchTile(
            icon: Icons.texture_rounded,
            title: 'Body Texture',
            value: app.bodyTexture,
            onChanged: app.setBodyTexture,
          ),
          SettingsSwitchTile(
            icon: Icons.texture_rounded,
            title: 'Bottom NavBar Texture',
            value: app.navBTexture,
            onChanged: app.setNavBTexture,
          ),
        ],
      ),
      SettingsSection(
        title: 'Reading',
        children: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => SettingsSwitchTile(
              icon: Icons.push_pin_outlined,
              title: 'Sticky chapter title',
              subtitle: 'Alternate Title placement',
              value: context.watch<AppSettings>().stickyHeader,
              onChanged: context.read<AppSettings>().setStickyHeader,
            ),
          ),
          SettingsDropdownTile<HighlightStyle>(
            icon: Icons.format_color_fill_outlined,
            title: 'Highlight style',
            subtitle: 'How highlighted verses are drawn',
            value: app.highlightStyle,
            items: HighlightStyle.values,
            labelOf: (s) => switch (s) {
              HighlightStyle.box => 'Containing box',
              HighlightStyle.textBackground => 'Text background',
              HighlightStyle.sideLight => 'Curved side light',
            },
            onChanged: app.setHighlightStyle,
          ),
        ],
      ),

      // Only shown when an audio Bible is installed. The restart choices
      // are limited to the books that audio actually contains.
      if (audio.author != null)
        SettingsSection(
          title: 'Audio',
          children: [
            SettingsSwitchTile(
              icon: Icons.all_inclusive,
              title: 'On Bible End - keep playing?',
              subtitle: audio.bibleEndContinue
                  ? 'Restarts after last chapter ends.'
                  : 'Playback stops on bible end.',
              value: audio.bibleEndContinue,
              onChanged: audio.setBibleEndContinue,
            ),
            if (audio.bibleEndContinue)
              SettingsDropdownTile<BibleEndTarget>(
                icon: Icons.restart_alt,
                title: 'Continue from',
                value: audio.effectiveEndTarget,
                items: audio.availableEndTargets,
                labelOf: (t) => t.label,
                onChanged: audio.setBibleEndTarget,
              ),
          ],
        ),
      if (ai.available)
        SettingsSection(
          title: 'Bible AI',
          children: [
            SettingsSwitchTile(
              icon: Icons.auto_awesome,
              title: 'Use AI Bible Chat',
              subtitle: ai.enabled
                  ? 'Runs fully on this device'
                  : 'Hidden from menus, model unloaded',
              value: ai.enabled,
              onChanged: ai.setEnabled,
            ),
            if (ai.enabled)
              SettingsSwitchTile(
                icon: Icons.timer_outlined,
                title: 'Unload model when idle',
                subtitle: 'Frees memory after a period of inactivity',
                value: ai.idleUnload,
                onChanged: ai.setIdleUnload,
              ),
            if (ai.enabled && ai.idleUnload)
              SettingsDropdownTile<int>(
                icon: Icons.hourglass_bottom,
                title: 'Unload after',
                value: ai.idleMinutes,
                items: AiPrefs.idleChoices,
                labelOf: (m) => '$m min',
                onChanged: ai.setIdleMinutes,
              ),
          ],
        ),

      const BarGestureSettingsSection(),
      const ProfileBackupSection(),

      SettingsSection(
        title: 'About',
        children: [
          SettingsNavTile(
            icon: Icons.info_outline,
            title: 'About this app',
            subtitle: 'Version, licences',
            pageBuilder: (_) => const AboutPage(),
          ),
        ],
      ),
    ];

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        header,
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList.list(
            children: [
              for (final (i, s) in sections.indexed)
                SpringIn(index: i, child: s),
            ],
          ),
        ),
      ],
    );
  }
}
