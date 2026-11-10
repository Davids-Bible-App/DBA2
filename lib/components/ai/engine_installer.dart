import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'ai_exception.dart';
import 'downloader.dart';
import 'engine_locator.dart';
import 'settings_store.dart';

/// Leave empty to search the recent llama.cpp releases for the newest one that
/// has a Windows Vulkan zip. To pin a build you have tested, use a tag like 'b11669'.
const _pinnedTag = '';

const _urlKey = 'engine_url:windows';

enum InstallState { idle, working, failed }

/// Windows only: downloads the official llama.cpp Vulkan build on first use.
class EngineInstaller extends ChangeNotifier {
  EngineInstaller(this.onInstalled, this._settings);
  final void Function(String exePath) onInstalled;
  final SettingsStore _settings;

  /// Optional user-supplied direct link to a Windows .zip. Empty = auto-discover.
  String get customUrl => _settings.get(_urlKey) ?? '';
  set customUrl(String v) {
    final t = v.trim();
    t.isEmpty ? _settings.remove(_urlKey) : _settings.set(_urlKey, t);
  }

  InstallState state = InstallState.idle;
  String stage = '';
  String? error;
  final progress = ValueNotifier<DownloadProgress?>(null);
  DownloadTask? _task;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _task?.cancel();
  }

  Future<void> install() async {
    if (state == InstallState.working) return;
    _cancelled = false;
    state = InstallState.working;
    error = null;
    stage = customUrl.isNotEmpty
        ? 'Preparing download…'
        : 'Finding the latest engine…';
    progress.value = null;
    notifyListeners();
    try {
      final asset = customUrl.isNotEmpty
          ? _assetFromUrl(customUrl)
          : await _findAsset();
      if (_cancelled) throw const DownloadCancelled();
      final dir = await EngineLocator.downloadedDir();
      await dir.create(recursive: true);
      final zip = File(p.join(dir.path, asset.name));

      stage = 'Downloading ${asset.name}…';
      notifyListeners();
      _task = DownloadTask(
        url: Uri.parse(asset.url),
        dest: zip,
        fallbackSize: asset.size,
        onProgress: (v) => progress.value = v,
      );
      await _task!.run();

      stage = 'Unpacking…';
      progress.value = null; // indeterminate bar
      notifyListeners();
      await _extractInBackground(zip.path, dir.path);
      await zip.delete();

      final exe = await EngineLocator.find();
      if (exe == null) {
        throw const AiException(
          'The download did not contain llama-server.exe.',
        );
      }
      state = InstallState.idle;
      stage = '';
      notifyListeners();
      onInstalled(exe);
    } on DownloadCancelled {
      state = InstallState.idle;
      stage = '';
      notifyListeners();
    } catch (e) {
      state = InstallState.failed;
      error = errorMessage(e, 'Engine install failed: $e');
      notifyListeners();
    }
  }

  ({String name, String url, int size}) _assetFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const AiException('That download link is not a valid http(s) URL.');
    }
    final name = p.basename(uri.path);
    if (!name.toLowerCase().endsWith('.zip')) {
      throw const AiException('The link must point to a .zip file.');
    }
    return (
      name: name,
      url: url,
      size: 0,
    ); // size 0: the downloader probes the real size
  }

  Future<({String name, String url, int size})> _findAsset() async {
    // /releases/latest is NOT used any more: llama.cpp's "latest" release now
    // only carries a text file, and the binaries live on the bNNNN pre-releases.
    final api = _pinnedTag.isEmpty
        ? 'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=15'
        : 'https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$_pinnedTag';
    final http.Response r;
    try {
      r = await http.get(
        Uri.parse(api),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'BibleApp/1.0',
        },
      );
    } catch (e) {
      throw AiException("Couldn't reach GitHub: $e");
    }
    if (r.statusCode == 403) {
      throw const AiException(
        'GitHub refused the request (rate limit?). Wait a while, or paste a direct download link below.',
      );
    }
    if (r.statusCode != 200) {
      throw AiException('GitHub returned HTTP ${r.statusCode}.');
    }

    final decoded = jsonDecode(r.body);
    final releases = decoded is List
        ? decoded
        : [decoded]; // list, or a single release when pinned
    for (final rel in releases) {
      if ((rel as Map<String, dynamic>)['draft'] == true) continue;
      for (final a in (rel['assets'] as List? ?? const [])) {
        final name = a['name'] as String;
        if (name.endsWith('bin-win-vulkan-x64.zip')) {
          return (
            name: name,
            url: a['browser_download_url'] as String,
            size: (a['size'] as num).toInt(),
          );
        }
      }
    }
    throw const AiException(
      'No Windows Vulkan build found in recent llama.cpp releases. Paste a direct download link below.',
    );
  }
}

// Top-level so the isolate closure captures only two strings (never `this`).
Future<void> _extractInBackground(String zipPath, String outDir) =>
    Isolate.run(() => extractFileToDisk(zipPath, outDir));
