// lib/main.dart
import 'package:dba2/app.dart';
import 'package:dba2/core.dart';
import 'package:dba2/state/shared_state.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dba2/window_persistence_service.dart';

import 'services/audio_init.dart';
import 'services/audio_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initAudioBackground();

  if (defaultTargetPlatform == TargetPlatform.windows) {
    // Initialize window manager for desktop
    await windowManager.ensureInitialized();
    await WindowPersistenceService.initialize(
      defaultSize: const Size(500, 700),
    );
  }

  final prefs = await SharedPreferences.getInstance();

  runApp(
    MultiProvider(
      providers: buildProviders(prefs: prefs, books: kBooks),
      child: const DavidsBibleApp2(),
    ),
  );
}
