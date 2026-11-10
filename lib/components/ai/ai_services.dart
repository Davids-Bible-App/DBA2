import 'dart:io';

import 'package:dba2/components/ai/memory_check.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ai_exception.dart';
import 'chat_repository.dart';
import 'engine_installer.dart';
import 'engine_locator.dart';
import 'llm_engine.dart';
import 'model_store.dart';
import 'settings_store.dart';

/// The single object the host app creates.
/// Returns null when AI can't work in this build (e.g. an Android "lite" build
/// without the bundled engine), which is how the feature stays hidden.
class AiServices {
  AiServices._(this.engine, this.models, this.chats, this.installer);
  final LlmEngine engine;
  final ModelStore models;
  final ChatRepository chats;
  final EngineInstaller? installer; // Windows only

  static Future<AiServices?> create() async {
    final exe = await EngineLocator.find();
    if (exe == null && !EngineLocator.canDownload) return null;

    final support = await getApplicationSupportDirectory();
    final settings = await SettingsStore.open(support);
    final llms = await Directory(p.join(support.path, 'llms'))
        .create(recursive: true);
    final engine = LlmEngine(exe);
    return AiServices._(
      engine,
      ModelStore(llms, settings),
      await ChatRepository.open(support),
      EngineLocator.canDownload
          ? EngineInstaller(engine.setServerExe, settings)
          : null,
    );
  }

  /// Load [filename] into memory (starts llama-server).
  Future<void> useModel(String filename) async {
    final file = models.fileOf(filename);
    if (!await file.exists()) {
      throw AiException("$filename isn't in your models folder.");
    }
    // Android: refuse early with a clear message instead of letting the
    // system's low-memory killer take the app down mid-load.
    final mem = await readMemInfo();
    if (mem != null) {
      final modelMb = await file.length() / 1048576;
      // The model we're replacing is freed first, so count it as available.
      final active = engine.activeFilename;
      final heldMb = active == null
          ? 0
          : await models.fileOf(active).length() / 1048576;
      final needMb = modelMb * 1.1 + 400; // weights + context cache + overhead
      final freeMb = mem.availableMb + heldMb;
      if (needMb > freeMb) {
        throw AiException(
          'Not enough free memory for this model: it needs about '
          '${(needMb / 1024).toStringAsFixed(1)} GB and only '
          '${(freeMb / 1024).toStringAsFixed(1)} GB is free. '
          'Close other apps or choose a smaller model.',
        );
      }
    }
    final prompt = (await models.effectivePrompt(filename)).prompt;
    await engine.load(
      file,
      gpuLayers: models.gpuLayers(filename) ?? 0,
      systemPrompt: prompt,
    );
  }

  /// Saved prompts apply immediately to the loaded model, no reload needed.
  void setPrompt(String filename, String prompt) {
    models.setPromptOverride(filename, prompt);
    if (engine.activeFilename == filename) engine.systemPrompt = prompt;
  }

  Future<void> resetPrompt(String filename) async {
    models.deletePromptOverride(filename);
    if (engine.activeFilename == filename) {
      engine.systemPrompt = (await models.effectivePrompt(filename)).prompt;
    }
  }

  Future<void> dispose() async {
    await engine.unload();
    await models.settings.flush();
  }
}
