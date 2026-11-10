import 'package:dba2/main/addons/addon_controller.dart';
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/main/controllers/split_controller.dart';
import 'package:dba2/ui/translations/controllers/translation_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/ui/translations/services/translation_store.dart';
import 'package:dba2/components/audio/link/reader_audio_link.dart';
import 'package:dba2/ui/votd/votd_controller.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/audio/services/audio_library.dart';
import '../components/audio/controllers/audio_controller.dart';
import '../ui/navigation/bar_gesture_settings.dart';
import '../components/audio/controllers/sleep_timer_controller.dart';

import 'package:dba2/storage/profile/profile.dart';
import 'package:dba2/storage/profile/profile_settings.dart';
import 'package:dba2/ui/controlbox/control_box.dart' show kHighlightColors;
import 'package:dba2/ui/controlbox/verse_selection.dart';

import 'package:dba2/main/history/history_controller.dart';

enum HighlightStyle { box, textBackground, sideLight }

/// App-wide settings that persist between launches.
class AppSettings extends ChangeNotifier {
  AppSettings(this._store)
    : _stickyHeader = _store.getBool(_kSticky) ?? true,
      _navTTexture = _store.getBool(_kNavTTexture) ?? true,
      _bodyTexture = _store.getBool(_kBodyTexture) ?? true,
      _navBTexture = _store.getBool(_kNavBTexture) ?? true,
      _highlightStyle = _parseStyle(_store.getString(_kHlStyle)),
      _userName = _store.getString(_kName) ?? 'David';

  static const _kSticky = 'stickyHeader';
  static const _kNavTTexture = 'navTTexture';
  static const _kBodyTexture = 'bodyTexture';
  static const _kNavBTexture = 'navBTexture';
  static const _kName = 'userName';
  final ProfileSettings _store;

  bool _stickyHeader;
  bool get stickyHeader => _stickyHeader;

  void setStickyHeader(bool value) {
    if (_stickyHeader == value) return;
    _stickyHeader = value;
    notifyListeners();
    _store.setBool(_kSticky, value);
  }

  bool _navTTexture;
  bool get navTTexture => _navTTexture;
  bool _bodyTexture;
  bool get bodyTexture => _bodyTexture;
  bool _navBTexture;
  bool get navBTexture => _navBTexture;

  void setNavTTexture(bool value) {
    if (_navTTexture == value) return;
    _navTTexture = value;
    notifyListeners();
    _store.setBool(_kNavTTexture, value);
  }

  void setBodyTexture(bool value) {
    if (_bodyTexture == value) return;
    _bodyTexture = value;
    notifyListeners();
    _store.setBool(_kBodyTexture, value);
  }

  void setNavBTexture(bool value) {
    if (_navBTexture == value) return;
    _navBTexture = value;
    notifyListeners();
    _store.setBool(_kNavBTexture, value);
  }

  static const _kHlStyle = 'highlightStyle';

  HighlightStyle _highlightStyle;
  HighlightStyle get highlightStyle => _highlightStyle;

  static HighlightStyle _parseStyle(String? s) => HighlightStyle.values
      .firstWhere((e) => e.name == s, orElse: () => HighlightStyle.box);

  void setHighlightStyle(HighlightStyle value) {
    if (_highlightStyle == value) return;
    _highlightStyle = value;
    notifyListeners();
    _store.setString(_kHlStyle, value.name);
  }

  String _userName;
  String get userName => _userName;

  /// "David's Bible App", "James' Bible App", or "Bible App" if blank.
  String get appTitle {
    if (_userName.isEmpty) return 'Bible App';
    final possessive = _userName.toLowerCase().endsWith('s') ? "'" : "'s";
    return '$_userName$possessive Bible App';
  }

  void setUserName(String value) {
    final name = value.trim();
    if (_userName == name) return;
    _userName = name;
    notifyListeners();
    _store.setString(_kName, name);
  }

  /// Re-reads from the DB (used after an import).
  void reload() {
    _stickyHeader = _store.getBool(_kSticky) ?? true;
    _navTTexture = _store.getBool(_kNavTTexture) ?? true;
    _bodyTexture = _store.getBool(_kBodyTexture) ?? true;
    _navBTexture = _store.getBool(_kNavBTexture) ?? true;
    _highlightStyle = _parseStyle(_store.getString(_kHlStyle));
    _userName = _store.getString(_kName) ?? 'David';
    notifyListeners();
  }
}

List<SingleChildWidget> buildProviders({
  required SharedPreferences prefs,
  required List<BookInfo> books,
  required ProfileRepository profile,
  required ProfileSettings settings,
}) => [
  Provider<ProfileRepository>.value(value: profile),
  Provider<ProfileSettings>.value(value: settings),
  ChangeNotifierProvider(
    create: (_) => HighlightStore(
      repo: profile,
      palette: kHighlightColors,
    )..load(),
  ),
  ChangeNotifierProvider(
    create: (_) => AppSettings(settings),
  ), // was AppSettings(prefs)
  ChangeNotifierProvider(create: (_) => ThemeProvider(settings)),
  ChangeNotifierProvider(create: (_) => BarGestureSettings(settings)),
  ChangeNotifierProvider(create: (_) => AudioController(books: books)),
  ChangeNotifierProvider(
    create: (ctx) => SleepTimerController(ctx.read<AudioController>()),
  ),

  Provider(create: (_) => TranslationStore()),

  ChangeNotifierProvider(create: (_) => HistoryController(profile)),

  // BibleController BEFORE TranslationController
  ChangeNotifierProvider(
    create: (ctx) =>
        BibleController(
            prefs,
            ctx.read<TranslationStore>(),
            ctx.read<HighlightStore>(),
          )
          ..onVisit = ctx.read<HistoryController>().log
          ..init(),
  ),

  ChangeNotifierProvider(
    lazy: false,
    create: (ctx) => VotdController(
      prefs,
      ctx.read<BibleController>(),
      ctx.read<TranslationStore>(),
    )..init(),
  ),

  ChangeNotifierProvider(
    create: (ctx) => TranslationController(ctx.read<TranslationStore>())
      ..onInstalled = (ids) {
        final b = ctx.read<BibleController>();
        if (!b.hasTranslation) b.setTranslation(ids.first);
      }
      ..onAddonsImported = ctx.read<AddonController>().refresh,
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
