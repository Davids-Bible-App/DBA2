import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'ai_exception.dart';

const _parallelConnections = 4;
const _minSizeForParallel = 64 * 1024 * 1024; // below this, plain streaming is fine

class DownloadProgress {
  const DownloadProgress(this.downloaded, this.total);
  final int downloaded;
  final int total;
  double? get fraction => total > 0 ? (downloaded / total).clamp(0.0, 1.0) : null;
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// 1-byte ranged GET: reports the true size and whether ranges are supported.
/// More reliable across CDNs than HEAD (same trick your Rust code used).
Future<({int total, bool ranges})> probeRemote(Uri url) async {
  final client = http.Client();
  try {
    final req = http.Request('GET', url)..headers['Range'] = 'bytes=0-0';
    final resp = await client.send(req).timeout(const Duration(seconds: 20));
    await resp.stream.listen((_) {}).cancel(); // never read the body
    final ranges = resp.statusCode == 206;
    final fromRange = int.tryParse((resp.headers['content-range'] ?? '').split('/').last);
    final total = fromRange ?? (ranges ? null : resp.contentLength);
    if (total == null || total <= 0) throw const AiException("Server didn't report a size.");
    return (total: total, ranges: ranges);
  } on AiException {
    rethrow;
  } catch (e) {
    throw AiException("Couldn't reach server: $e");
  } finally {
    client.close();
  }
}

/// One cancellable download. Closing the HTTP client aborts every in-flight
/// request immediately, even ones stalled waiting for data.
class DownloadTask {
  DownloadTask({required this.url, required this.dest, required this.fallbackSize, required this.onProgress});

  final Uri url;
  final File dest;
  final int fallbackSize;
  final void Function(DownloadProgress) onProgress;
  final _client = http.Client();
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close();
  }

  Future<void> run() async {
    var total = fallbackSize;
    var ranges = false;
    try {
      final probe = await probeRemote(url);
      total = probe.total;
      ranges = probe.ranges;
    } catch (_) {/* fall back to the catalog's estimate */}

    final tmp = File('${dest.path}.part');
    try {
      if (ranges && total >= _minSizeForParallel) {
        await _parallel(tmp, total);
      } else {
        await _sequential(tmp, total);
      }
      if (_cancelled) throw const DownloadCancelled();
      await tmp.rename(dest.path);
      onProgress(DownloadProgress(total, total));
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      if (_cancelled || e is DownloadCancelled) throw const DownloadCancelled();
      if (e is AiException) rethrow;
      throw AiException('Download failed: $e');
    } finally {
      _client.close();
    }
  }

  Future<void> _parallel(File tmp, int total) async {
    final raf = await tmp.open(mode: FileMode.write);
    try {
      await raf.truncate(total); // pre-allocate

      // All workers share one file handle; this chain serialises setPosition+write
      // so two workers can never interleave between the two calls.
      Future<void> chain = Future.value();
      Future<void> write(int offset, List<int> data) => chain = chain.then((_) async {
            await raf.setPosition(offset);
            await raf.writeFrom(data);
          });

      var downloaded = 0;
      var failed = false;
      final ticker = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => onProgress(DownloadProgress(downloaded, total)),
      );
      try {
        final chunk = (total / _parallelConnections).ceil();
        final workers = <Future<void>>[];
        for (var i = 0; i < _parallelConnections; i++) {
          final start = i * chunk;
          if (start >= total) break;
          final end = min(start + chunk, total) - 1;
          workers.add(() async {
            try {
              final req = http.Request('GET', url)..headers['Range'] = 'bytes=$start-$end';
              final resp = await _client.send(req);
              if (resp.statusCode != 206) {
                throw AiException('Server returned HTTP ${resp.statusCode} for a range request');
              }
              var pos = start;
              await for (final data in resp.stream) {
                if (_cancelled || failed) throw const DownloadCancelled();
                await write(pos, data);
                pos += data.length;
                downloaded += data.length;
              }
            } catch (_) {
              failed = true; // tell the other workers to stop
              rethrow;
            }
          }());
        }
        await Future.wait(workers);
        await raf.flush();
      } finally {
        ticker.cancel();
      }
    } finally {
      await raf.close(); // must close before the caller renames/deletes (Windows)
    }
  }

  Future<void> _sequential(File tmp, int total) async {
    final resp = await _client.send(http.Request('GET', url));
    if (resp.statusCode != 200) throw AiException('Server returned HTTP ${resp.statusCode}');
    final sink = tmp.openWrite();
    var done = 0;
    final clock = Stopwatch()..start();
    try {
      await for (final chunk in resp.stream) {
        if (_cancelled) throw const DownloadCancelled();
        sink.add(chunk);
        done += chunk.length;
        if (clock.elapsedMilliseconds > 150) {
          onProgress(DownloadProgress(done, total));
          clock.reset();
        }
      }
    } finally {
      await sink.close();
    }
  }
}
