import 'package:dba2/themes/app_theme.dart';
import 'package:dba2/ui/widgets/toast.dart';
import 'package:dba2/ui/settings/settings_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _repoUrl = 'https://github.com/Davids-Bible-App/DBA2';
const _author = 'Aver';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  // Created once, so rebuilds don't re-query the platform.
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showToast('Copied to clipboard');
  }

  Future<void> _openRepo() =>
      launchUrl(Uri.parse(_repoUrl), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.secondary, // matches SettingsPage
      body: FutureBuilder<PackageInfo>(
        future: _info,
        builder: (context, snap) {
          final info = snap.data;
          final version = info?.version ?? '…';
          final build = info?.buildNumber ?? '…';
          final name = info?.appName ?? 'Bible App';

          final sections = <Widget>[
            _AboutHeader(name: name, version: version),
            SettingsSection(
              title: 'App',
              children: [
                SettingsTile(
                  icon: Icons.tag,
                  title: 'Version',
                  subtitle: '$version ($build)',
                  trailing: Icon(
                    Icons.copy_outlined,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  onTap: () => _copy('$version ($build)'),
                ),
              ],
            ),
            SettingsSection(
              title: 'Open source',
              children: [
                SettingsTile(
                  icon: Icons.code,
                  title: 'Source code',
                  subtitle: 'View on GitHub',
                  trailing: Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  onTap: _openRepo,
                ),
                SettingsTile(
                  icon: Icons.gavel_outlined,
                  title: 'Licences',
                  subtitle: 'MIT License and open-source packages',
                  trailing: Icon(
                    Icons.chevron_right,
                    color: cs.onSurfaceVariant,
                  ),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: name,
                    applicationVersion: version,
                    applicationLegalese:
                        '© ${DateTime.now().year} $_author\nLicensed under the MIT License',
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Text(
                '© ${DateTime.now().year} $_author · MIT License',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ];

          return CustomScrollView(
            slivers: [
              const SliverAppBar.large(title: Text('About')),
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
        },
      ),
    );
  }
}

class _AboutHeader extends StatelessWidget {
  const _AboutHeader({required this.name, required this.version});

  final String name;
  final String version;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = context.colorScheme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        spacing: 12,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Image.asset(
              isDark ? 'assets/icon/icon-wt.webp' : 'assets/icon/icon-bt.webp',
            ),
            // child: Icon(
            //   Icons.menu_book_rounded,
            //   size: 44,
            //   color: cs.onPrimaryContainer,
            // ),
          ),
          Text('Book by Bonnie Beach US', textAlign: TextAlign.center),
          Text(name, style: tt.headlineSmall, textAlign: TextAlign.center),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              'Version $version',
              style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
