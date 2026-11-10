import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ai_exception.dart';
import 'downloader.dart';
import 'settings_store.dart';

const defaultSystemPrompt =
    'You are a helpful Bible study assistant. If uncertain, say so rather than fabricating information.';

enum PromptSource { override, file, builtIn }

class LocalModel {
  const LocalModel({
    required this.filename,
    required this.displayName,
    required this.sizeBytes,
    required this.promptSource,
  });
  final String filename;
  final String displayName;
  final int sizeBytes;
  final PromptSource promptSource;
}

class EffectivePrompt {
  const EffectivePrompt(this.prompt, this.source);
  final String prompt;
  final PromptSource source;
}

class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    required this.filename,
    required this.url,
    required this.sizeBytes,
    this.description = '',
    this.downloaded = false,
  });
  final String id, name, filename, url, description;
  final int sizeBytes;
  final bool downloaded;

  // Same JSON shape as your existing llm_catalog.json.
  factory CatalogEntry.fromJson(Map<String, dynamic> j) => CatalogEntry(
    id: j['id'] as String,
    name: j['name'] as String,
    filename: j['filename'] as String,
    url: j['url'] as String,
    sizeBytes: (j['size_bytes'] as num).toInt(),
    description: (j['description'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'filename': filename,
    'url': url,
    'size_bytes': sizeBytes,
    'description': description,
  };

  CatalogEntry withDownloaded(bool v) => CatalogEntry(
    id: id,
    name: name,
    filename: filename,
    url: url,
    sizeBytes: sizeBytes,
    description: description,
    downloaded: v,
  );
}

class ActiveDownload {
  ActiveDownload(this.task, this.progress);
  final DownloadTask task;
  final ValueNotifier<DownloadProgress>
  progress; // only the progress bar listens to this
}

/// Everything about model *files*: listing, import, rename, delete, prompts,
/// GPU-layer settings, the catalog, and downloads. Notifies listeners on change.
class ModelStore extends ChangeNotifier {
  ModelStore(this.llmsDir, this.settings);
  final Directory llmsDir;
  final SettingsStore settings;
  final Map<String, ActiveDownload> downloads = {};
  List<CatalogEntry>? _bundled;

  static const _ovr = 'catalog_override:';
  static const _del = 'catalog_deleted:';

  File fileOf(String filename) => File(p.join(llmsDir.path, _safe(filename)));

  String _safe(String name) {
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('..')) {
      throw const AiException('Invalid filename.');
    }
    return name;
  }

  String _promptFilePath(String filename) => p.join(
    llmsDir.path,
    '${p.basenameWithoutExtension(filename)}.prompt.txt',
  );

  // ── Local models ──────────────────────────────────────────────────────

  Future<List<LocalModel>> listLocal() async {
    final catalogNames = {
      for (final c in await _mergedCatalog()) c.filename: c.name,
    };
    final out = <LocalModel>[];
    await for (final e in llmsDir.list()) {
      if (e is! File || p.extension(e.path).toLowerCase() != '.gguf') continue;
      final filename = p.basename(e.path);
      out.add(
        LocalModel(
          filename: filename,
          // override > catalog name > raw filename
          displayName:
              settings.get('display_name:$filename') ??
              catalogNames[filename] ??
              filename,
          sizeBytes: await e.length(),
          promptSource: settings.get('prompt_override:$filename') != null
              ? PromptSource.override
              : File(_promptFilePath(filename)).existsSync()
              ? PromptSource.file
              : PromptSource.builtIn,
        ),
      );
    }
    out.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return out;
  }

  Future<void> setDisplayName(String filename, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const AiException('Please enter a name.');
    if (!await fileOf(filename).exists()) {
      throw AiException("$filename isn't in your models folder.");
    }
    settings.set('display_name:$filename', clean);
    notifyListeners();
  }

  Future<void> deleteLocal(String filename) async {
    await fileOf(filename).delete();
    settings.remove('display_name:$filename');
    settings.remove('gpu_layers:$filename');
    notifyListeners();
  }

  Future<String> importModel(
    String sourcePath, {
    void Function(double)? onProgress,
  }) async {
    if (p.extension(sourcePath).toLowerCase() != '.gguf') {
      throw const AiException('Please choose a .gguf file.');
    }
    final src = File(sourcePath);
    final raf = await src.open();
    try {
      // Sanity-check the magic bytes before committing to a multi-GB copy.
      if (String.fromCharCodes(await raf.read(4)) != 'GGUF') {
        throw const AiException(
          "That file doesn't look like a valid GGUF model.",
        );
      }
    } finally {
      await raf.close();
    }
    final filename = _safe(p.basename(sourcePath));
    final dest = fileOf(filename);
    // On Android, file_picker already copied the file into the app's cache dir.
    // Moving it is instant; copying would double the disk use and time.
    final cache = (await getTemporaryDirectory()).path;
    if (p.isWithin(cache, sourcePath)) {
      try {
        await src.rename(dest.path);
      } on FileSystemException {
        await _copyWithProgress(src, dest, onProgress);
        await src.delete();
      }
    } else {
      await _copyWithProgress(src, dest, onProgress);
    }
    notifyListeners();
    return filename;
  }

  /// Chunked copy so we can report real progress (and never buffer a whole model in RAM).
  Future<void> _copyWithProgress(
    File src,
    File dest,
    void Function(double)? onProgress,
  ) async {
    final total = await src.length();
    final input = await src.open();
    final output = await dest.open(mode: FileMode.write);
    var done = 0;
    try {
      while (true) {
        final chunk = await input.read(4 * 1024 * 1024);
        if (chunk.isEmpty) break;
        await output.writeFrom(chunk);
        done += chunk.length;
        if (total > 0) onProgress?.call(done / total);
      }
    } catch (_) {
      await output.close();
      try {
        await dest.delete(); // don't leave a half-written model behind
      } catch (_) {}
      rethrow;
    } finally {
      await input.close();
    }
    await output.close();
  }

  // ── Prompts: settings override > sibling .prompt.txt > built-in ─────────

  Future<EffectivePrompt> effectivePrompt(String filename) async {
    final override = settings.get('prompt_override:$filename');
    if (override != null) {
      return EffectivePrompt(override, PromptSource.override);
    }
    final f = File(_promptFilePath(filename));
    if (await f.exists()) {
      return EffectivePrompt(await f.readAsString(), PromptSource.file);
    }
    return const EffectivePrompt(defaultSystemPrompt, PromptSource.builtIn);
  }

  void setPromptOverride(String filename, String prompt) {
    settings.set('prompt_override:$filename', prompt);
    notifyListeners();
  }

  void deletePromptOverride(String filename) {
    settings.remove('prompt_override:$filename');
    notifyListeners();
  }

  // ── GPU layers ────────────────────────────────────────────────────────

  int? gpuLayers(String filename) =>
      int.tryParse(settings.get('gpu_layers:$filename') ?? '');

  void setGpuLayers(String filename, int? layers) {
    layers == null
        ? settings.remove('gpu_layers:$filename')
        : settings.set('gpu_layers:$filename', '$layers');
  }

  // ── Catalog: bundled asset merged with user edits ───────────────────────

  Future<List<CatalogEntry>> catalog() async {
    final merged = await _mergedCatalog();
    return [
      for (final e in merged)
        e.withDownloaded(await fileOf(e.filename).exists()),
    ];
  }

  Future<List<CatalogEntry>> _mergedCatalog() async {
    _bundled ??= [
      for (final j
          in (jsonDecode(await rootBundle.loadString('assets/llm_catalog.json'))
                  as Map)['models']
              as List)
        CatalogEntry.fromJson(j as Map<String, dynamic>),
    ];
    final overrides = <String, CatalogEntry>{};
    for (final e in settings.withPrefix(_ovr)) {
      try {
        overrides[e.key.substring(_ovr.length)] = CatalogEntry.fromJson(
          jsonDecode(e.value) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    final deleted = {
      for (final e in settings.withPrefix(_del)) e.key.substring(_del.length),
    };

    final merged = <CatalogEntry>[];
    final seen = <String>{};
    for (final b in _bundled!) {
      if (deleted.contains(b.id)) continue;
      final entry = overrides[b.id] ?? b;
      seen.add(entry.id);
      merged.add(entry);
    }
    // Override ids that aren't in the bundled file are user-added models.
    for (final e in overrides.entries) {
      if (!seen.contains(e.key) && !deleted.contains(e.key)) {
        merged.add(e.value);
      }
    }
    return merged;
  }

  Future<void> upsertCatalogEntry({
    String? id,
    required String name,
    required String filename,
    required String url,
    required int sizeBytes,
    String description = '',
  }) async {
    name = name.trim();
    filename = filename.trim();
    url = url.trim();
    if (name.isEmpty) throw const AiException('Please enter a name.');
    if (filename.isEmpty || !filename.endsWith('.gguf')) {
      throw const AiException(
        'Filename must be a non-empty name ending in .gguf.',
      );
    }
    _safe(filename);
    if (!(url.startsWith('http://') || url.startsWith('https://'))) {
      throw const AiException('Please enter a valid http(s) URL.');
    }
    if (sizeBytes <= 0) throw const AiException('Size must be greater than 0.');

    var entryId = id?.trim() ?? '';
    if (entryId.isEmpty) {
      final existing = await _mergedCatalog();
      var base = name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      if (base.isEmpty) base = 'custom-model';
      entryId = base;
      for (var n = 2; existing.any((m) => m.id == entryId); n++) {
        entryId = '$base-$n';
      }
    }
    final record = CatalogEntry(
      id: entryId,
      name: name,
      filename: filename,
      url: url,
      sizeBytes: sizeBytes,
      description: description.trim(),
    );
    settings.set('$_ovr$entryId', jsonEncode(record.toJson()));
    settings.remove('$_del$entryId'); // un-delete if previously removed
    notifyListeners();
  }

  void deleteCatalogEntry(String id) {
    settings.set('$_del$id', '1');
    settings.remove('$_ovr$id');
    notifyListeners();
  }

  // ── Downloads ─────────────────────────────────────────────────────────

  /// Throws [DownloadCancelled] or [AiException]. Safe to call from a widget
  /// that is later closed: the download lives here, not in the widget.
  Future<void> download(CatalogEntry entry) async {
    if (downloads.containsKey(entry.id)) return;
    final progress = ValueNotifier(DownloadProgress(0, entry.sizeBytes));
    final task = DownloadTask(
      url: Uri.parse(entry.url),
      dest: fileOf(entry.filename),
      fallbackSize: entry.sizeBytes,
      onProgress: (v) => progress.value = v,
    );
    downloads[entry.id] = ActiveDownload(task, progress);
    notifyListeners();
    try {
      await task.run();
    } finally {
      downloads.remove(entry.id);
      notifyListeners();
    }
  }

  void cancelDownload(String id) => downloads[id]?.task.cancel();
}
