// lib/widgets/settings_page.dart
import 'package:dba2/controllers/bible_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/state/overlay_lock.dart';
import 'package:dba2/state/shared_state.dart';
import 'package:dba2/widgets/bar_gesture_settings_section.dart';
import 'package:dba2/widgets/settings/settings_kit.dart';

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

    final sections = <Widget>[
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
              subtitle: 'Keep the chapter title visible while scrolling',
              value: context.watch<AppSettings>().stickyHeader,
              onChanged: context.read<AppSettings>().setStickyHeader,
            ),
          ),
        ],
      ),
      const BarGestureSettingsSection(),
      SettingsSection(
        title: 'About',
        children: [
          SettingsNavTile(
            icon: Icons.info_outline,
            title: 'About this app',
            subtitle: 'Version, licences',
            pageBuilder: (_) => const _AboutPage(),
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

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Center(child: Text('Put your about content here')),
    );
  }
}
