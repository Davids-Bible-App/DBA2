import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Finds the llama-server executable.
///  - Android: bundled inside the APK as a native library (see README). Cannot be downloaded:
///    Android 10+ blocks running files from app storage, and Play forbids downloaded executables.
///  - Windows: bundled in `<exe folder>`\engine\ (optional) OR downloaded on first use into app data.
class EngineLocator {
  static const _channel = MethodChannel('bible_ai/engine');

  static bool get canDownload => Platform.isWindows;

  static String get hint => Platform.isAndroid
      ? 'android/app/src/main/jniLibs/arm64-v8a/libllama_server.so (run tools/fetch_llama_android.ps1)'
      : r'<exe folder>\engine\llama-server.exe';

  static Future<Directory> downloadedDir() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'engine'),
  );

  /// Path to llama-server, or null if it isn't there (yet).
  static Future<String?> find() async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<String>('serverPath');
      }
      if (Platform.isWindows) {
        final bundled = p.join(
          p.dirname(Platform.resolvedExecutable),
          'engine',
          'llama-server.exe',
        );
        if (await File(bundled).exists()) return bundled;
        final dir = await downloadedDir();
        if (await dir.exists()) {
          await for (final e in dir.list(recursive: true)) {
            if (e is File &&
                p.basename(e.path).toLowerCase() == 'llama-server.exe') {
              return e.path;
            }
          }
        }
      }
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    return null;
  }

  /// The Android binary links against the lib*.so files next to it.
  static Map<String, String> environmentFor(String exe) =>
      Platform.isAndroid ? {'LD_LIBRARY_PATH': p.dirname(exe)} : const {};

  /// Android: tells the native side which process to stop if the app is
  /// swiped away. Pass 0 when the server stops.
  static Future<void> setServerPid(int pid) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setServerPid', pid);
    } catch (_) {}
  }
}
