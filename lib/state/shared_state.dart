// lib/state/shared_state.dart
import 'package:dba2/controllers/bible_controller.dart';
import 'package:dba2/controllers/split_controller.dart';
import 'package:dba2/controllers/translation_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/services/translation_store.dart';
import 'package:dba2/state/reader_audio_link.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/audio_library.dart';
import '../controllers/audio_controller.dart';
import '../state/bar_gesture_settings.dart';
import '../state/sleep_timer_controller.dart';

/// App-wide settings that persist between launches.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs) : _stickyHeader = _prefs.getBool(_kSticky) ?? true;

  static const _kSticky = 'stickyHeader';
  final SharedPreferences _prefs;

  bool _stickyHeader;
  bool get stickyHeader => _stickyHeader;

  void setStickyHeader(bool value) {
    if (_stickyHeader == value) return;
    _stickyHeader = value;
    notifyListeners();
    _prefs.setBool(_kSticky, value);
  }
}

List<SingleChildWidget> buildProviders({
  required SharedPreferences prefs,
  required List<BookInfo> books,
}) => [
  ChangeNotifierProvider(create: (_) => AppSettings(prefs)),
  ChangeNotifierProvider(create: (_) => ThemeProvider(prefs)),
  ChangeNotifierProvider(create: (_) => BarGestureSettings(prefs)),
  ChangeNotifierProvider(create: (_) => AudioController(books: books)),
  ChangeNotifierProvider(
    create: (ctx) => SleepTimerController(ctx.read<AudioController>()),
  ),

  Provider(create: (_) => TranslationStore()),

  // BibleController BEFORE TranslationController
  ChangeNotifierProvider(
    create: (ctx) =>
        BibleController(prefs, ctx.read<TranslationStore>())..init(),
  ),

  ChangeNotifierProvider(
    create: (ctx) =>
        TranslationController(ctx.read<TranslationStore>())
          ..onInstalled = (ids) {
            final b = ctx.read<BibleController>();
            if (!b.hasTranslation) b.setTranslation(ids.first);
          },
  ),

  ChangeNotifierProvider(
    lazy: false,
    create: (ctx) => SplitController(
      prefs,
      ctx.read<TranslationStore>(),
      ctx.read<BibleController>(),
    ),
  ),

  // The glue. Must come AFTER AudioController and BibleController.
  Provider<ReaderAudioLink>(
    create: (ctx) => ReaderAudioLink(
      bible: ctx.read<BibleController>(),
      audio: ctx.read<AudioController>(),
    ),
    dispose: (_, link) => link.dispose(),
  ),
];
