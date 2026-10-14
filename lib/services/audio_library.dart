// Replaces your Rust commands: get_available_authors, get_book_playlist,
// import_audio_zip, delete_author.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart' show compareNatural;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// All 66 books (id, name, order, chapterCount).
const kBooks = <BookInfo>[
  // Old Testament
  BookInfo('GEN', 'Genesis', 1, 50),
  BookInfo('EXO', 'Exodus', 2, 40),
  BookInfo('LEV', 'Leviticus', 3, 27),
  BookInfo('NUM', 'Numbers', 4, 36),
  BookInfo('DEU', 'Deuteronomy', 5, 34),
  BookInfo('JOS', 'Joshua', 6, 24),
  BookInfo('JDG', 'Judges', 7, 21),
  BookInfo('RUT', 'Ruth', 8, 4),
  BookInfo('1SA', '1 Samuel', 9, 31),
  BookInfo('2SA', '2 Samuel', 10, 24),
  BookInfo('1KI', '1 Kings', 11, 22),
  BookInfo('2KI', '2 Kings', 12, 25),
  BookInfo('1CH', '1 Chronicles', 13, 29),
  BookInfo('2CH', '2 Chronicles', 14, 36),
  BookInfo('EZR', 'Ezra', 15, 10),
  BookInfo('NEH', 'Nehemiah', 16, 13),
  BookInfo('EST', 'Esther', 17, 10),
  BookInfo('JOB', 'Job', 18, 42),
  BookInfo('PSA', 'Psalms', 19, 150),
  BookInfo('PRO', 'Proverbs', 20, 31),
  BookInfo('ECC', 'Ecclesiastes', 21, 12),
  BookInfo('SNG', 'Song of Solomon', 22, 8),
  BookInfo('ISA', 'Isaiah', 23, 66),
  BookInfo('JER', 'Jeremiah', 24, 52),
  BookInfo('LAM', 'Lamentations', 25, 5),
  BookInfo('EZK', 'Ezekiel', 26, 48),
  BookInfo('DAN', 'Daniel', 27, 12),
  BookInfo('HOS', 'Hosea', 28, 14),
  BookInfo('JOL', 'Joel', 29, 3),
  BookInfo('AMO', 'Amos', 30, 9),
  BookInfo('OBA', 'Obadiah', 31, 1),
  BookInfo('JON', 'Jonah', 32, 4),
  BookInfo('MIC', 'Micah', 33, 7),
  BookInfo('NAM', 'Nahum', 34, 3),
  BookInfo('HAB', 'Habakkuk', 35, 3),
  BookInfo('ZEP', 'Zephaniah', 36, 3),
  BookInfo('HAG', 'Haggai', 37, 2),
  BookInfo('ZEC', 'Zechariah', 38, 14),
  BookInfo('MAL', 'Malachi', 39, 4),

  // New Testament
  BookInfo('MAT', 'Matthew', 40, 28),
  BookInfo('MRK', 'Mark', 41, 16),
  BookInfo('LUK', 'Luke', 42, 24),
  BookInfo('JHN', 'John', 43, 21),
  BookInfo('ACT', 'Acts', 44, 28),
  BookInfo('ROM', 'Romans', 45, 16),
  BookInfo('1CO', '1 Corinthians', 46, 16),
  BookInfo('2CO', '2 Corinthians', 47, 13),
  BookInfo('GAL', 'Galatians', 48, 6),
  BookInfo('EPH', 'Ephesians', 49, 6),
  BookInfo('PHP', 'Philippians', 50, 4),
  BookInfo('COL', 'Colossians', 51, 4),
  BookInfo('1TH', '1 Thessalonians', 52, 5),
  BookInfo('2TH', '2 Thessalonians', 53, 3),
  BookInfo('1TI', '1 Timothy', 54, 6),
  BookInfo('2TI', '2 Timothy', 55, 4),
  BookInfo('TIT', 'Titus', 56, 3),
  BookInfo('PHM', 'Philemon', 57, 1),
  BookInfo('HEB', 'Hebrews', 58, 13),
  BookInfo('JAS', 'James', 59, 5),
  BookInfo('1PE', '1 Peter', 60, 5),
  BookInfo('2PE', '2 Peter', 61, 3),
  BookInfo('1JN', '1 John', 62, 5),
  BookInfo('2JN', '2 John', 63, 1),
  BookInfo('3JN', '3 John', 64, 1),
  BookInfo('JUD', 'Jude', 65, 1),
  BookInfo('REV', 'Revelation', 66, 22),
];

class BookInfo {
  const BookInfo(this.id, this.name, this.order, this.chapterCount);
  final String id; // e.g. "GEN"
  final String name; // e.g. "Genesis"
  final int order; // 1-based, used for the "01_Genesis" folder name
  final int chapterCount;

  String get folderName =>
      '${order.toString().padLeft(2, '0')}_${name.replaceAll(RegExp(r'\s+'), '')}';
}

class CancelFlag {
  bool cancelled = false;
}

class AudioLibrary {
  Future<Directory> _root() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'audio'));
  }

  /// Streams a zip to the temp folder. [onProgress] gets 0..100
  /// (only if the server reports a size). Returns the temp file path.
  Future<String> downloadZip(
    String url,
    String fileName,
    void Function(double) onProgress,
    CancelFlag cancel,
  ) async {
    final tmp = await getTemporaryDirectory();
    final file = File(p.join(tmp.path, fileName));
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw 'Server returned ${res.statusCode}';
      final total = res.contentLength; // -1 if unknown
      sink = file.openWrite();
      var got = 0, lastPct = -1;
      await for (final chunk in res) {
        if (cancel.cancelled) throw 'Download cancelled';
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          final pct = (got / total * 100).floor();
          if (pct != lastPct) {
            lastPct = pct;
            onProgress(pct.toDouble());
          }
        }
      }
      await sink.close();
      sink = null;
      return file.path;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<String>> authors() async {
    final root = await _root();
    if (!await root.exists()) return [];
    final dirs = await root.list().where((e) => e is Directory).toList();
    return dirs.map((d) => p.basename(d.path)).toList()..sort();
  }

  /// All chapter files for a book, naturally sorted (2 before 10).
  Future<List<String>> bookFiles(String author, BookInfo book) async {
    final root = await _root();
    final dir = Directory(p.join(root.path, author, book.folderName));
    if (!await dir.exists()) return [];
    final files = await dir
        .list()
        .where(
          (e) =>
              e is File && (e.path.endsWith('.m4a') || e.path.endsWith('.mp3')),
        )
        .map((e) => e.path)
        .toList();
    files.sort(compareNatural);
    return files;
  }

  Future<void> deleteAuthor(String author) async {
    final root = await _root();
    final dir = Directory(p.join(root.path, author));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Extracts a zip in a background isolate so the UI never freezes.
  /// [onProgress] gets 0..100. Returns the author name.
  Future<String> importZip(
    String zipPath,
    void Function(double) onProgress, {
    String? authorName, // forces the author folder name (used by downloads)
  }) async {
    final root = await _root();
    final port = ReceivePort();
    await Isolate.spawn(
      _extract,
      _Job(zipPath, root.path, port.sendPort, authorName),
    );

    await for (final msg in port) {
      final m = msg as List;
      if (m[0] == 'progress') {
        onProgress(m[1] as double);
      } else if (m[0] == 'done') {
        port.close();
        return m[1] as String;
      } else {
        port.close();
        throw Exception(m[1]);
      }
    }
    throw Exception('Import ended unexpectedly');
  }

  /// Zips one author's folder into a temp file, in a background isolate.
  /// The zip has the same layout Import Zip expects, plus a _meta.txt,
  /// so it can be re-imported later.
  Future<File> buildAuthorZip(String author) async {
    final root = await _root();
    final dirPath = p.join(root.path, author);
    final dir = Directory(dirPath);
    if (!await dir.exists()) throw 'Audio folder not found';

    // _meta.txt lives inside the author folder, so it's zipped along with
    // the audio. The importer skips it when extracting, so it's harmless.
    await File(p.join(dirPath, '_meta.txt')).writeAsString(author);

    final tmp = await getTemporaryDirectory();
    final safe = author.replaceAll(RegExp(r'[^\w\- ]'), '_');
    final outPath = p.join(tmp.path, '$safe.zip');
    final out = File(outPath);
    if (await out.exists()) await out.delete();

    // Same call as the usual archive_io folder-zip helper.
    // Level 0 = store only (audio is already compressed). If your version
    // rejects `level`, just remove that argument.
    final encoder = ZipFileEncoder();
    await encoder.zipDirectory(dir, filename: outPath, level: 0);

    // Never report success on an empty archive (a bare zip is 22 bytes).
    if (!await out.exists() || await out.length() < 1024) {
      if (await out.exists()) await out.delete();
      throw 'Zip came out empty, nothing to save';
    }
    return out;
  }
}

class _Job {
  _Job(this.zipPath, this.rootPath, this.port, this.authorName);
  final String zipPath, rootPath;
  final SendPort port;
  final String? authorName;
}

// Runs inside the isolate (must be a top-level function).
Future<void> _extract(_Job job) async {
  InputFileStream? input;
  try {
    job.port.send(['progress', 0.0]);
    input = InputFileStream(job.zipPath); // streams from disk, no full read
    final archive = ZipDecoder().decodeStream(input);

    // Author comes from _meta.txt, else the zip's file name.
    final meta = archive.findFile('_meta.txt');
    var author =
        job.authorName ??
        (meta != null
            ? utf8.decode(meta.content as List<int>).trim()
            : p.basenameWithoutExtension(job.zipPath));
    author = author.replaceAll(RegExp(r'\.zip$'), '').trim();
    if (author.isEmpty) {
      throw 'Author name is empty. Add a _meta.txt to your zip.';
    }

    final target = p.join(job.rootPath, author);
    final total = archive.length;
    var lastSent = -1;

    for (var i = 0; i < total; i++) {
      final f = archive[i];
      if (f.name == '_meta.txt') continue;

      final out = p.normalize(p.join(target, f.name));
      if (!p.isWithin(target, out)) continue; // blocks "../" zip-slip paths

      if (f.isFile) {
        Directory(p.dirname(out)).createSync(recursive: true);
        final output = OutputFileStream(out); // writes straight to disk
        f.writeContent(output);
        await output.close();
      } else {
        Directory(out).createSync(recursive: true);
      }

      final pct = (5.0 + (i / total) * 95.0).floor(); // limit message traffic
      if (pct != lastSent) {
        lastSent = pct;
        job.port.send(['progress', pct.toDouble()]);
      }
    }
    job.port.send(['progress', 100.0]);
    job.port.send(['done', author]);
  } catch (e) {
    job.port.send(['error', e.toString()]);
  } finally {
    await input?.close();
  }
}
