import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'ai_exception.dart';

/// Copies a model file out to a location the user picks (Downloads, SD card,
/// external drive…). Android uses a native channel; Windows picks a folder
/// and streams the copy.
class ModelBackup {
  static const _channel = MethodChannel('bible_ai/backup');

  static bool get supported => Platform.isAndroid || Platform.isWindows;

  /// Returns true if saved, false if the user cancelled the picker.
  static Future<bool> export(File model, String filename) => Platform.isWindows
      ? _exportDesktop(model, filename)
      : _exportAndroid(model, filename);

  static Future<bool> _exportAndroid(File model, String filename) async {
    try {
      return await _channel.invokeMethod<bool>('exportFile', {
            'path': model.path,
            'name': filename,
          }) ??
          false;
    } on PlatformException catch (e) {
      throw AiException('Backup failed: ${e.message}');
    } on MissingPluginException {
      throw const AiException('Backup is not available in this build.');
    }
  }

  static Future<bool> _exportDesktop(File model, String filename) async {
    final String? folder = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a folder for the model backup',
    );
    if (folder == null) return false; // cancelled

    final destPath = p.join(folder, filename);

    // Never copy a file onto itself: that would wipe the model.
    if (p.equals(p.absolute(destPath), p.absolute(model.path))) {
      throw const AiException(
        "Choose a different folder: that's where the model already is.",
      );
    }

    final dest = File(destPath);
    if (await dest.exists()) {
      throw AiException(
        'A file named $filename already exists in that folder. '
        'Choose another folder, or rename or delete the old one first.',
      );
    }

    try {
      // Streams in chunks, so a 16 GB model never sits in RAM
      // and the UI stays responsive.
      await model.openRead().pipe(dest.openWrite());
      return true;
    } catch (e) {
      try {
        if (await dest.exists()) await dest.delete(); // no half-written file
      } catch (_) {}
      throw AiException('Backup failed: $e');
    }
  }
}
