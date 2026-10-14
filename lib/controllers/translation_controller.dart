import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/translation.dart';
import '../services/translation_store.dart';

/// Which translations are on the device, and what is downloading right now.
/// (WHICH translation is being read lives in BibleController, which owns the db.)
class TranslationController extends ChangeNotifier {
  TranslationController(this.store) {
    refresh();
  }

  final TranslationStore store;

  Set<String> installed = {};

  /// id -> progress 0..1 (null = unknown length). Present = downloading.
  final Map<String, double?> downloading = {};

  /// True while the whole-folder export is being zipped/saved.
  bool exporting = false;

  /// Last info / error line, shown inside the sheet.
  String? message;
  bool messageIsError = false;

  /// Called ONCE per download/import action with the ids that just landed.
  /// Wired in shared_state.dart; it only auto-opens when nothing is open yet.
  void Function(List<String> ids)? onInstalled;

  bool isInstalled(String id) => installed.contains(id);
  bool isDownloading(String id) => downloading.containsKey(id);

  void _say(String? text, {bool error = false}) {
    message = text;
    messageIsError = error;
  }

  Future<void> refresh() async {
    installed = await store.installedIds();
    notifyListeners();
  }

  void _announce(List<String> ids) {
    if (ids.isEmpty) return;
    try {
      onInstalled?.call(ids);
    } catch (e) {
      debugPrint('onInstalled failed: $e');
    }
  }

  // ---- Download -----------------------------------------------------------

  Future<void> download(Translation t) async {
    if (isDownloading(t.id)) return;
    _say(null);
    downloading[t.id] = 0;
    notifyListeners();
    var landed = false;
    try {
      await store.download(t, (p) {
        downloading[t.id] = p;
        notifyListeners();
      });
      installed.add(t.id);
      landed = true;
    } catch (e) {
      _say('Could not download ${t.abbr}: $e', error: true);
    } finally {
      downloading.remove(t.id);
      notifyListeners();
    }
    if (landed) _announce([t.id]);
  }

  // ---- Import (.dba, .db, or a .zip backup) -------------------------------

  Future<void> importFiles() async {
    _say(null);
    final landed = <String>[];
    final bad = <String>[];

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'dba', 'zip'],
      );
      if (result.isEmpty) return;

      for (final f in result) {
        final path = f.path;
        if (path == null) continue;
        final ids = await store.importPath(path);
        if (ids.isEmpty) {
          bad.add(f.name);
        } else {
          landed.addAll(ids);
          installed.addAll(ids);
          notifyListeners(); // each file shows up in the sheet as it lands
        }
      }
    } catch (e) {
      _say('Import failed: $e', error: true);
    } finally {
      final parts = [
        if (landed.isNotEmpty)
          'Imported ${landed.length} translation${landed.length == 1 ? '' : 's'}.',
        if (bad.isNotEmpty) 'Skipped (not a Bible .dba): ${bad.join(', ')}',
      ];
      if (parts.isNotEmpty) _say(parts.join(' '), error: bad.isNotEmpty);
      installed = await store.installedIds();
      notifyListeners();
    }
    _announce(landed);
  }

  // ---- Backup / export ----------------------------------------------------

  /// Lets the user choose where to save [bytes] (Android: system "save as"
  /// picker, no storage permission needed; Windows: save dialog).
  Future<bool> _saveOut(String fileName, Uint8List bytes, String title) async {
    final path = await FilePicker.saveFile(
      dialogTitle: title,
      fileName: fileName,
      bytes: bytes,
    );
    if (path == null) return false; // cancelled

    return true;
  }

  /// Single translation backup (used by the delete prompt).
  /// Returns true only if the file was really saved.
  Future<bool> backupOne(Translation t) async {
    try {
      final bytes = await store.readBytes(t.id);
      final ok = await _saveOut(t.fileName, bytes, 'Back up ${t.name}');
      _say(ok ? 'Saved a backup of ${t.abbr}.' : null);
      notifyListeners();
      return ok;
    } catch (e) {
      _say('Backup failed: $e', error: true);
      notifyListeners();
      return false;
    }
  }

  /// Whole "bibles" folder as one zip (restore with Import).
  Future<void> exportAll() async {
    if (exporting) return;
    if (installed.isEmpty) {
      _say('Nothing to export yet.', error: true);
      notifyListeners();
      return;
    }
    _say(null);
    exporting = true;
    notifyListeners();
    File? zip;
    try {
      zip = await store.buildBackupZip();
      final ok = await _saveOut(
        'bibles_backup.zip',
        await zip.readAsBytes(),
        'Export Bible folder',
      );
      if (ok) _say('Exported ${installed.length} translations.');
    } catch (e) {
      _say('Export failed: $e', error: true);
    } finally {
      if (zip != null && zip.existsSync()) await zip.delete();
      exporting = false;
      notifyListeners();
    }
  }

  // ---- Delete -------------------------------------------------------------

  Future<void> remove(String id) async {
    await store.delete(id);
    installed.remove(id);
    notifyListeners();
  }
}
