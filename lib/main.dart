import 'package:dba2/components/ai/ai_prefs.dart';
import 'package:dba2/components/meme_maker/meme_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:dba2/app.dart';
import 'package:dba2/core.dart';
import 'package:dba2/storage/shared_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dba2/services/windows/window_persistence_service.dart';

import 'components/audio/services/audio_init.dart';
import 'components/audio/services/audio_library.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:dba2/storage/profile/db.dart';
import 'package:dba2/storage/profile/profile.dart';
import 'package:dba2/storage/profile/profile_settings.dart';
import 'package:dba2/main/addons/addon_controller.dart';
import 'package:dba2/main/addons/addon_store.dart';
import 'package:dba2/components/streak/streak_controller.dart';
import 'package:dba2/components/markdown_editor/md_controller.dart';
import 'package:dba2/components/markdown_editor/md_profile_storage.dart';

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

  // ── profile.db ──────────────────────────────────────────────
  final dbPath = p.join(
    (await getApplicationSupportDirectory()).path,
    'profile.db',
  );
  final profileDb = ProfileDatabase(databasePath: dbPath);
  await profileDb.database; // open now, so problems show up immediately
  final profile = ProfileRepository(profileDb);
  final settings = await ProfileSettings.open(profile);
  final mdStorage = ProfileMdStorage(profile);
  await migrateMdFromPrefs(prefs, mdStorage);
  debugPrint('profile.db is at: $dbPath'); // handy for inspecting it
  // ────────────────────────────────────────────────────────────

  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('LICENSE');
    yield LicenseEntryWithLineBreaks(['Davids Bible App'], text);
  });

  final addons = AddonController(AddonStore.instance);
  await addons.refresh();

  // Optional: Ensures it only runs in debug mode
  if (kDebugMode) {
    debugRepaintRainbowEnabled = false;
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AiPrefs>(create: (_) => AiPrefs(prefs)),
        ChangeNotifierProvider<AddonController>.value(value: addons),
        ChangeNotifierProvider<StreakController>(
          lazy: false,
          create: (_) => StreakController(settings)..start(),
        ),

        ChangeNotifierProvider<MarkdownEditorController>(
          create: (_) => MarkdownEditorController(storage: mdStorage),
        ),
        ChangeNotifierProvider<MemeMakerController>(
          create: (_) => MemeMakerController(repo: profile, settings: settings),
        ),

        ...buildProviders(
          prefs: prefs,
          books: kBooks,
          profile: profile,
          settings: settings,
        ),
      ],
      child: const DavidsBibleApp2(),
    ),
  );
}
