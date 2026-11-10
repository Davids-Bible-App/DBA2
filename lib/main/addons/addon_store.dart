import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

/// One optional database that is NOT a translation.
class AddonDb {
  const AddonDb({
    required this.id,
    required this.fileName,
    required this.name,
    required this.description,
    required this.downloadUrl,
    required this.requiredTable,
  });

  final String id;
  final String fileName;
  final String name;
  final String description;
  final String downloadUrl;

  /// A file is only accepted if this table exists and has rows.
  final String requiredTable;
}

const kStrongsDb = AddonDb(
  id: 'strongs',
  fileName: 'strongs_kjv.db',
  name: "Strong's Concordance",
  description: "KJV with Strong's numbers and Greek/Hebrew definitions.",
  downloadUrl: 'https://raw.githubusercontent.com/Davids-Bible-App/DavidsBibleApp.github/main/Translations/strongs_kjv.db',
  requiredTable: 'StrongsDefinition',
);

const kCrossRefsDb = AddonDb(
  id: 'crossrefs',
  fileName: 'cross_refs.db',
  name: 'Cross References',
  description: 'Related verses for every verse.',
  downloadUrl: 'https://raw.githubusercontent.com/Davids-Bible-App/DavidsBibleApp.github/main/Translations/cross_refs.db',
  requiredTable: 'cross_refs', // <-- set to a real table name in your db
);

const kAddons = [kStrongsDb, kCrossRefsDb];

/// Returns the addon whose file name matches, or null if it's not an addon.
AddonDb? addonForFileName(String name) {
  final n = name.toLowerCase();
  for (final a in kAddons) {
    if (a.fileName.toLowerCase() == n) return a;
  }
  return null;
}

/// Same folder StrongsRepository used before, so existing installs are kept.
class AddonStore {
  AddonStore._();
  static final AddonStore instance = AddonStore._();

  Directory? _dir;

  Future<Directory> directory() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'addons'));
    await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> fileFor(AddonDb a) async =>
      File(p.join((await directory()).path, a.fileName));

  Future<bool> isInstalled(AddonDb a) async {
    final f = await fileFor(a);
    return f.existsSync() && _isValid(a, f.path);
  }

  Future<void> delete(AddonDb a) async {
    final f = await fileFor(a);
    if (f.existsSync()) await f.delete();
  }

  Future<void> download(
    AddonDb a,
    void Function(double? progress) onProgress,
  ) async {
    final target = await fileFor(a);
    final part = File('${target.path}.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(a.downloadUrl));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Server answered ${res.statusCode}');
      }
      final total = res.contentLength;
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
      await _commit(a, part, target);
    } catch (_) {
      if (part.existsSync()) await part.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Writes bytes (from a zip entry) in. Returns false if not the right db.
  Future<bool> importBytes(AddonDb a, List<int> bytes) async {
    final target = await fileFor(a);
    final part = File('${target.path}.part');
    try {
      await part.writeAsBytes(bytes, flush: true);
      await _commit(a, part, target);
      return true;
    } catch (_) {
      if (part.existsSync()) await part.delete();
      return false;
    }
  }

  /// Copies a picked file in. Returns false if it isn't the right database.
  Future<bool> importFrom(AddonDb a, String sourcePath) async {
    final target = await fileFor(a);
    final part = File('${target.path}.part');
    try {
      await File(sourcePath).copy(part.path);
      await _commit(a, part, target);
      return true;
    } catch (_) {
      if (part.existsSync()) await part.delete();
      return false;
    }
  }

  Future<void> _commit(AddonDb a, File part, File target) async {
    if (!_isValid(a, part.path)) {
      throw FormatException('Not a valid ${a.name} database');
    }
    if (target.existsSync()) await target.delete();
    await part.rename(target.path);
  }

  bool _isValid(AddonDb a, String path) {
    try {
      final db = sqlite3lib.sqlite3.open(
        path,
        mode: sqlite3lib.OpenMode.readOnly,
      );
      try {
        db.select('SELECT 1 FROM "${a.requiredTable}" LIMIT 1').first;
        return true;
      } finally {
        db.close();
      }
    } catch (_) {
      return false; // missing table, no rows, or not sqlite
    }
  }
}
