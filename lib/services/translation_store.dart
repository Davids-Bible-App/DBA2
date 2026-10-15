import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

import 'translation_catalog.dart';

/// Owns the folder the `.dba` files live in, and every way a file can get
/// there (download / import) or leave (delete / backup).
///
/// Folder: `<app support dir>/bibles/`
///   Android: /data/data/`<pkg>`/files/bibles/   (persistent, NOT code_cache)
///   Windows: %APPDATA%/`<company>/<app>`/bibles/
class TranslationStore {
  Directory? _dir;

  Future<Directory> directory() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'bibles'));
    await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> fileFor(String id) async =>
      File(p.join((await directory()).path, '$id$kTranslationExt'));

  /// Ids of every `.dba` in the folder.
  Future<Set<String>> installedIds() async {
    final dir = await directory();
    final ids = <String>{};
    await for (final e in dir.list()) {
      if (e is File && p.extension(e.path).toLowerCase() == kTranslationExt) {
        ids.add(p.basenameWithoutExtension(e.path));
      }
    }
    return ids;
  }

  Future<void> delete(String id) async {
    final f = await fileFor(id);
    if (f.existsSync()) await f.delete();
  }

  // ---- Download -----------------------------------------------------------

  /// Streams the file to `<id>.dba.part`, validates it, then renames.
  /// [onProgress] gets 0..1, or null when the server sends no length.
  Future<void> download(
    Translation t,
    void Function(double? progress) onProgress,
  ) async {
    final target = await fileFor(t.id);
    final part = File('${target.path}.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(t.downloadUrl));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Server answered ${res.statusCode}');
      }
      final total = res.contentLength; // -1 when unknown
      var got = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          got += chunk.length;
          onProgress(total > 0 ? got / total : null);
        }
      } finally {
        await sink.close();
      }
      if (!_isValid(part.path)) {
        throw const FormatException('Downloaded file is not a Bible database');
      }
      if (target.existsSync()) await target.delete();
      await part.rename(target.path);
    } catch (_) {
      if (part.existsSync()) await part.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  // ---- Import -------------------------------------------------------------

  /// Imports a picked file. Accepts `.dba`, `.db` (renamed to `.dba`) and
  /// `.zip` (a backup made by [`buildBackupZip`]). Returns the ids that landed.
  Future<List<String>> importPath(String sourcePath) async {
    final ext = p.extension(sourcePath).toLowerCase();
    if (ext == '.zip') return _importZip(sourcePath);
    if (ext != kTranslationExt && ext != '.db') return const [];
    final id = await _importDb(sourcePath);
    return id == null ? const [] : [id];
  }

  String _safeId(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');

  Future<String?> _importDb(String sourcePath) async {
    final id = _safeId(p.basenameWithoutExtension(sourcePath));
    if (id.isEmpty) return null;

    final target = await fileFor(id);
    final part = File('${target.path}.part');
    try {
      await File(sourcePath).copy(part.path);
      if (!_isValid(part.path)) {
        await part.delete();
        return null;
      }
      if (target.existsSync()) await target.delete();
      await part.rename(target.path);
      return id;
    } catch (_) {
      if (part.existsSync()) await part.delete();
      return null;
    }
  }

  Future<List<String>> _importZip(String zipPath) async {
    final ids = <String>[];
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        if (p.extension(entry.name).toLowerCase() != kTranslationExt) continue;
        final id = _safeId(p.basenameWithoutExtension(entry.name));
        if (id.isEmpty) continue;

        final target = await fileFor(id);
        final part = File('${target.path}.part');
        try {
          await part.writeAsBytes(entry.content as List<int>, flush: true);
          if (!_isValid(part.path)) {
            await part.delete();
            continue;
          }
          if (target.existsSync()) await target.delete();
          await part.rename(target.path);
          ids.add(id);
        } catch (_) {
          if (part.existsSync()) await part.delete();
        }
      }
    } catch (_) {
      // not a readable zip: nothing imported
    } finally {
      await input.close();
    }
    return ids;
  }

  // ---- Backup -------------------------------------------------------------

  /// One translation, as raw bytes (for a single-file backup).
  Future<Uint8List> readBytes(String id) async =>
      (await fileFor(id)).readAsBytes();

  /// Zips every installed `.dba` into a temp file (the "bibles" folder).
  Future<File> buildBackupZip() async {
    final tmp = await getTemporaryDirectory();
    final zipFile = File(p.join(tmp.path, 'bibles_backup.zip'));
    if (zipFile.existsSync()) await zipFile.delete();

    final encoder = ZipFileEncoder()..create(zipFile.path);
    try {
      for (final id in await installedIds()) {
        await encoder.addFile(await fileFor(id));
      }
    } finally {
      await encoder.close();
    }
    return zipFile;
  }

  /// A Bible db has a Book table with rows in it.
  bool _isValid(String path) {
    try {
      final db = sqlite3lib.sqlite3.open(
        path,
        mode: sqlite3lib.OpenMode.readOnly,
      );
      try {
        final r = db.select('SELECT COUNT(*) AS c FROM Book');
        return (r.first['c'] as int) > 0;
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }
}
