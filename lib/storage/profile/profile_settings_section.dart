import 'dart:io';

import 'package:dba2/core.dart';
import 'package:dba2/components/markdown_editor/md_controller.dart';
import 'package:dba2/storage/profile/profile.dart';
import 'package:dba2/storage/profile/profile_settings.dart';
import 'package:dba2/storage/profile/profile_transfer.dart';
import 'package:dba2/main/search/search_sheet.dart';
import 'package:dba2/ui/navigation/bar_gesture_settings.dart';
import 'package:dba2/storage/shared_state.dart';
import 'package:dba2/ui/widgets/toast.dart';
import 'package:dba2/ui/controlbox/verse_selection.dart';
import 'package:dba2/ui/settings/settings_kit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dba2/main/gallery/gallery_controller.dart';
import 'package:dba2/main/gallery/bookmarks/bookmark_store.dart';

enum _ImportMode { merge, replace }

/// Settings section: export / import profile.db.
class ProfileBackupSection extends StatelessWidget {
  const ProfileBackupSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          title: 'Reset',
          children: [
            SettingsButtonTile(
              icon: Icons.settings_backup_restore,
              title: 'Reset all settings',
              subtitle:
                  'Back to defaults. Notes, topics, highlights and '
                  'bookmarks are kept.',
              buttonLabel: 'Reset',
              color: cs.errorContainer,
              onPressed: () => _resetSettings(context),
            ),
          ],
        ),
        SettingsSection(
          title: 'Backup',
          children: [
            SettingsButtonTile(
              icon: Icons.upload_file_outlined,
              title: 'Export profile database',
              subtitle: 'Backup all stored data.',
              buttonLabel: 'Export',
              onPressed: () => _export(context),
            ),
            SettingsButtonTile(
              icon: Icons.download_outlined,
              title: 'Import profile database',
              subtitle: 'Restore your data',
              buttonLabel: 'Import',
              onPressed: () => _import(context),
            ),
          ],
        ),
      ],
    );
  }

  static Future<void> _export(BuildContext context) async {
    final transfer = ProfileTransfer(context.read<ProfileRepository>());
    try {
      final bytes = await transfer.exportBytes();
      final d = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final name =
          'profile_${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}.db';

      final target = await FilePicker.saveFile(
        dialogTitle: 'Save profile backup',
        fileName: name,
        bytes: bytes, // required on Android / iOS
      );
      if (target == null) return; // cancelled

      // Android/iOS: the picker already wrote the bytes.
      // Desktop: write them ourselves (harmless if the picker already did).
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File.fromUri(target).writeAsBytes(bytes);
      }
      showToast('Profile exported');
    } catch (e) {
      showToast('Export failed: $e', error: true);
    }
  }

  static Future<void> _import(BuildContext context) async {
    final transfer = ProfileTransfer(context.read<ProfileRepository>());
    // Grab everything we need to refresh BEFORE any await.
    final settings = context.read<ProfileSettings>();
    final app = context.read<AppSettings>();
    final theme = context.read<ThemeProvider>();
    final gestures = context.read<BarGestureSettings>();
    final highlights = context.read<HighlightStore>();
    final gallery = context.read<GalleryController>();
    final bookmarks = context.read<BookmarkStore>();
    final md = context.read<MarkdownEditorController>();

    try {
      final picked = await FilePicker.pickFiles(type: FileType.any);
      final path = picked.single.path;
      if (path == null) return; // cancelled
      if (!context.mounted) return;

      final mode = await showDialog<_ImportMode>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import profile'),
          content: const Text(
            'Merge keeps what you have and adds the file\'s data '
            '(newer wins on conflicts).\n\n'
            'Replace all erases the highlights, notes, topics, bookmarks '
            'and settings on this device first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, _ImportMode.replace),
              child: const Text('Replace all'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _ImportMode.merge),
              child: const Text('Merge'),
            ),
          ],
        ),
      );
      if (mode == null) return;

      await transfer.importFile(path, merge: mode == _ImportMode.merge);

      // Refresh everything that was loaded into memory at startup.
      await settings.reload();
      app.reload();
      theme.reload();
      gestures.reload();
      await highlights.load();
      await gallery.selectTopic(null); // an open topic may no longer exist
      await gallery.refreshAll(); // topics + notes (+ reader note index)
      await bookmarks.load();
      await md.reloadFromStorage();
      await reloadSearchSession();

      showToast('Profile imported');
    } catch (e) {
      showToast('Import failed: $e', error: true);
    }
  }

  static Future<void> _resetSettings(BuildContext context) async {
    // Grab everything we need to refresh BEFORE any await.
    final settings = context.read<ProfileSettings>();
    final app = context.read<AppSettings>();
    final theme = context.read<ThemeProvider>();
    final gestures = context.read<BarGestureSettings>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all settings?'),
        content: const Text(
          'Every setting returns to its default. Your highlights, notes, '
          'topics, bookmarks and history are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await settings.clear();

      // Same refresh list as the import, minus the highlights
      // (highlights live in their own table and weren't touched).
      app.reload();
      theme.reload();
      gestures.reload();

      showToast('Settings reset to defaults');
    } catch (e) {
      showToast('Reset failed: $e', error: true);
    }
  }
}
