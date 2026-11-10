import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'ai_exception.dart';
import 'chat_repository.dart' show ChatTurn;
import 'engine_locator.dart';
import 'model_store.dart' show defaultSystemPrompt;
import 'windows_job.dart';

// Android only: runs the server under a tiny watchdog. If the app process
// vanishes (swipe-away, crash, force-stop) the server is killed within ~1s.
const _guardScript = r'''
APP=$PPID
"$@" &
SRV=$!
trap 'kill $SRV 2>/dev/null; wait $SRV 2>/dev/null; exit 77' TERM INT HUP
while kill -0 $SRV 2>/dev/null; do
  kill -0 $APP 2>/dev/null || { kill -9 $SRV; exit 77; }
  sleep 1
done
wait $SRV
''';

enum EngineStatus { unloaded, loading, ready, error }

/// Owns the llama-server child process and talks to it over localhost.
///
/// Replaces the Rust `bible_llm.rs`: model loading, GPU->CPU fallback, prompt
/// templating, stop sequences, sampling, and cancellation are now handled by
/// llama-server itself. We just start/stop it and stream its SSE output.
class LlmEngine extends ChangeNotifier {
  LlmEngine(this.serverExe);

  /// Path to llama-server, or null if the engine isn't installed yet (Windows first run).
  String? serverExe;
  bool get installed => serverExe != null;

  void setServerExe(String path) {
    serverExe = path;
    notifyListeners();
  }

  // Phones have far less RAM; the KV cache scales with context size.
  static final int _nCtx = Platform.isAndroid ? 4096 : 8192;
  static const _maxNewTokens = 2048;
  // Safety net for models whose GGUF doesn't flag end-of-turn correctly.
  static const _stopStrings = [
    '<end_of_turn>',
    '<start_of_turn>',
    '<|im_start|>',
    '<|im_end|>',
  ];
  static final _bufferRe = RegExp(
    r'(\w+)\s+model buffer size\s*=\s*([\d.]+)\s*MiB',
  );
  static final _vramRe = RegExp(r'\((\d+)\s*MiB,\s*\d+\s*MiB free\)');

  EngineStatus status = EngineStatus.unloaded;
  String? activeFilename;
  String? lastError;
  String? gpuNotice;
  String systemPrompt = defaultSystemPrompt;

  static const _deliberateExit =
      77; // the guard script stopped the server on purpose

  /// Last model that was loaded, kept after an automatic unload (swipe-away,
  /// idle timeout) so the chat page can offer "Reload". Cleared when the user unloads.
  String? resumeFilename;

  Duration? _idleTimeout; // null = never unload automatically
  Timer? _idleTimer;
  int _activeChats = 0;

  set idleTimeout(Duration? d) {
    _idleTimeout = d;
    _touch();
  }

  /// backend name -> MiB, parsed from llama-server's log (same regex as your Rust layer).
  final Map<String, double> bufferMib = {};

  /// filename -> measured GPU MiB for N layers; makes the slider's estimate accurate.
  final Map<String, ({int layers, double mib})> calibration = {};

  Process? _proc;
  int _port = 0;
  int _generation =
      0; // bumped on every load/unload so stale loads can bail out
  final List<String> _log = [];

  // ── Lifecycle ─────────────────────────────────────────────────────────

  Future<void> load(
    File model, {
    required int gpuLayers,
    required String systemPrompt,
  }) async {
    if (serverExe == null) {
      throw const AiException('The AI engine is not installed yet.');
    }
    final gen = ++_generation;
    await _stop();
    final name = p.basename(model.path);
    status = EngineStatus.loading;
    activeFilename = name;
    lastError = null;
    gpuNotice = null;
    bufferMib.clear();
    notifyListeners();

    try {
      var used = gpuLayers;
      var ok = false;
      if (gpuLayers > 0) {
        ok = await _start(model, gpuLayers, gen);
        if (gen != _generation) return;
        if (!ok) {
          // Same behaviour as before: retry once on CPU and tell the user.
          await _stop();
          used = 0;
          gpuNotice = 'Not enough GPU memory; running on CPU instead.';
          notifyListeners();
        }
      } else {
        used = 0;
      }
      if (!ok) ok = await _start(model, 0, gen);
      if (gen != _generation) return;
      if (!ok) {
        throw AiException(
          'Failed to load $name: ${_log.reversed.take(3).toList().reversed.join(' | ')}',
        );
      }

      final gpu = bufferMib.entries.where(
        (e) =>
            !e.key.toUpperCase().startsWith('CPU') && !e.key.contains('Host'),
      );
      if (used > 0 && gpu.isNotEmpty) {
        calibration[name] = (layers: used, mib: gpu.first.value);
      }

      this.systemPrompt = systemPrompt;
      resumeFilename = name;
      status = EngineStatus.ready;
      notifyListeners();
      _touch(); // start the idle countdown
    } catch (e) {
      final msg = e is AiException
          ? e.message
          : 'Failed to start the model server: $e';
      if (gen == _generation) {
        await _stop();
        status = EngineStatus.error;
        activeFilename = null;
        lastError = msg;
        notifyListeners();
      }
      throw AiException(msg);
    }
  }

  Future<void> unload({bool keepForResume = false}) async {
    _generation++;
    await _stop();
    if (!keepForResume) resumeFilename = null;
    _resetToUnloaded();
  }

  Future<bool> _start(File model, int ngl, int gen) async {
    _log.clear();
    _port = await _freePort();
    final exe = serverExe!;
    final args = [
      '-m', model.path,
      '-c', '$_nCtx',
      '-ngl', '$ngl',
      '-np', '1', // one slot: otherwise the context may be split between parallel slots
      '--host', '127.0.0.1',
      '--port', '$_port',
      '--jinja', // use the chat template embedded in the GGUF (works for any model family)
    ];
    final proc = Platform.isAndroid
        ? await Process.start(
            '/system/bin/sh',
            ['-c', _guardScript, 'sh', exe, ...args],
            workingDirectory: p.dirname(exe),
            environment: EngineLocator.environmentFor(exe),
          )
        : await Process.start(
            exe,
            args,
            workingDirectory: p.dirname(exe),
            environment: EngineLocator.environmentFor(exe),
          );

    if (gen != _generation) {
      proc.kill();
      return false;
    }
    _proc = proc;
    WindowsJob.adopt(proc.pid); // Windows: server dies with the app, always
    unawaited(EngineLocator.setServerPid(proc.pid));

    var dead = false;
    proc.exitCode.then((code) {
      dead = true;
      if (identical(_proc, proc) && status == EngineStatus.ready) {
        _proc = null;
        if (Platform.isAndroid && code == _deliberateExit) {
          // App was swiped away (audio keeps the Dart side alive): not an error.
          _resetToUnloaded();
        } else {
          status = EngineStatus.error;
          activeFilename = null;
          lastError = 'The model server stopped unexpectedly (code $code).';
          notifyListeners();
        }
      }
    });
    _watch(proc.stdout);
    _watch(
      proc.stderr,
    ); // must be drained or the child can block on a full pipe

    final client = http.Client();
    final health = Uri.parse('http://127.0.0.1:$_port/health');
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    try {
      while (!dead && gen == _generation && DateTime.now().isBefore(deadline)) {
        try {
          final r = await client
              .get(health)
              .timeout(const Duration(seconds: 2));
          if (r.statusCode == 200) {
            return true; // 503 while the model is still loading
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      client.close();
    }
    return false;
  }

  void _watch(Stream<List<int>> s) {
    s
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          _log.add(line);
          if (_log.length > 30) _log.removeAt(0);
          final m = _bufferRe.firstMatch(line);
          if (m != null) {
            bufferMib[m[1]!] = double.parse(m[2]!);
            notifyListeners();
          }
        }, onError: (_) {});
  }

  /// (Re)starts the inactivity countdown. Does nothing while a reply is streaming.
  void _touch() {
    _idleTimer?.cancel();
    _idleTimer = null;
    final d = _idleTimeout;
    if (d == null || status != EngineStatus.ready || _activeChats > 0) return;
    _idleTimer = Timer(d, () {
      if (status == EngineStatus.ready && _activeChats == 0) {
        unload(keepForResume: true);
      }
    });
  }

  void _resetToUnloaded() {
    _idleTimer?.cancel();
    _idleTimer = null;
    status = EngineStatus.unloaded;
    activeFilename = null;
    lastError = null;
    gpuNotice = null;
    bufferMib.clear();
    systemPrompt = defaultSystemPrompt;
    notifyListeners();
  }

  Future<void> _stop() async {
    final proc = _proc;
    _proc = null; // set first so the exit handler knows this was intentional
    unawaited(EngineLocator.setServerPid(0));

    if (proc == null) return;
    proc.kill();
    await proc.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }

  // ── Chat ──────────────────────────────────────────────────────────────

  /// Streams reply text. Cancel the subscription to stop generation instantly:
  /// that closes the HTTP connection and llama-server aborts the request.
  Stream<String> chat(String prompt, List<ChatTurn> history) {
    final client = http.Client();
    final out = StreamController<String>();
    var cancelled = false;
    out.onCancel = () {
      cancelled = true;
      client.close();
    };

    Future<void> pump() async {
      try {
        _activeChats++;
        _idleTimer?.cancel();
        if (status != EngineStatus.ready) {
          throw const AiException("Model isn't loaded yet.");
        }
        final request =
            http.Request(
                'POST',
                Uri.parse('http://127.0.0.1:$_port/v1/chat/completions'),
              )
              ..headers['Content-Type'] = 'application/json'
              ..body = jsonEncode({
                'messages': [
                  {'role': 'system', 'content': systemPrompt},
                  for (final t in history) t.toJson(),
                  {'role': 'user', 'content': prompt},
                ],
                'stream': true,
                'temperature': 0, // greedy, as before
                'max_tokens': _maxNewTokens,
                'repeat_penalty': 1.15,
                'repeat_last_n': 64,
                'stop': _stopStrings,
              });
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw AiException(_errorText(await response.stream.bytesToString()));
        }
        final lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          if (cancelled) break;
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data == '[DONE]') break;
          final choices =
              (jsonDecode(data) as Map<String, dynamic>)['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = ((choices.first as Map)['delta'] as Map?)?['content'];
          if (delta is String && delta.isNotEmpty) out.add(delta);
        }
      } catch (e) {
        if (!cancelled) {
          out.addError(
            e is AiException
                ? e
                : AiException('Lost connection to the model: $e'),
          );
        }
      } finally {
        _activeChats--;
        _touch();
        client.close();
        if (!cancelled) await out.close();
      }
    }

    unawaited(pump());
    return out.stream;
  }

  String _errorText(String body) {
    try {
      final err = (jsonDecode(body) as Map)['error'];
      if (err is Map && err['message'] is String) {
        return err['message'] as String;
      }
    } catch (_) {}
    return 'The model server returned an error.';
  }

  // ── GPU info ──────────────────────────────────────────────────────────

  /// Best-effort total VRAM via `llama-server --list-devices` (replaces the `ash` Vulkan query).
  Future<int?> queryVramMib() async {
    try {
      final exe = serverExe;
      if (exe == null || Platform.isAndroid) {
        return null; // the Android build is CPU-only
      }
      final r = await Process.run(
        exe,
        ['--list-devices'],
        workingDirectory: p.dirname(exe),
        environment: EngineLocator.environmentFor(exe),
      ).timeout(const Duration(seconds: 15));
      int? best;
      for (final m in _vramRe.allMatches('${r.stdout}\n${r.stderr}')) {
        final v = int.parse(m[1]!);
        if (best == null || v > best) best = v;
      }
      return best;
    } catch (_) {
      return null;
    }
  }
}
