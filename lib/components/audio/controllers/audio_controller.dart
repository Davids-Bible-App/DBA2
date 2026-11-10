// just_audio owns the queue, looping and media notification, so this is
// mostly "which book/chapter am I on" bookkeeping, plus auto-scroll.
//
// ONE BIG QUEUE (Android / iOS):
// Instead of loading one book at a time, the player is given ONE queue that
// holds every chapter of every book the current author has installed:
// Except, in Loop Mode: Book.
//
//   Genesis 1..50, Exodus 1..40, ... Jude 1, Revelation 1..22
//
// Because the media tray (lock screen / notification) just says "next" and
// "previous" to that queue, it now moves from book to book by itself, and
// one-chapter books (Obadiah, Jude, ...) no longer block skipping.
// _onIndex() works out which book/chapter the player is on and tells the
// reader. "Loop: Book" is done by hand (see _onIndex and _onProcessing).
//
// Windows/Linux (media_kit) can't do playlists, so they still load one
// chapter file at a time ("manual" mode). That code is unchanged.
//
// LAZY PLAYER:
// The AudioPlayer (and so the native media_kit/libmpv player) is only created
// the first time audio is actually needed (first play). Until then everything
// is plain state: author, book, chapter, file list. This avoids the native
// player surviving a hot restart and crashing the app.
//
// AUTO-SCROLL DESIGN (open-loop, constant speed):
//   speed (px/sec) = page height / audio duration
// The speed is calculated once per chapter. Every screen frame we simply move
// the page by  speed * autoScrollFactor * timeSinceLastFrame.
// We never keep "correcting" against the audio clock, which is what caused
// the bouncing/jerking. We only re-align to the audio at discrete events:
// play, seek, chapter change, loop restart.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:filegate/filegate.dart';

import '../services/audio_catalog.dart';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/audio_library.dart';

/// Where playback restarts when the end of the Bible is reached
/// (only used when "Keep playing at the end" is switched on).
enum BibleEndTarget { book, newTestament, oldTestament }

extension BibleEndTargetLabel on BibleEndTarget {
  String get label => switch (this) {
    BibleEndTarget.book => 'Restart Book',
    BibleEndTarget.newTestament => 'Restart NT',
    BibleEndTarget.oldTestament => 'Restart OT',
  };
}

/// A ChangeNotifier has no "vsync", so we provide a tiny TickerProvider that
/// lets us create a Ticker (a callback that fires once per screen frame).
class _FrameTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// One chapter inside the big queue.
class _QItem {
  const _QItem(this.bookIndex, this.chapter, this.path);
  final int bookIndex; // index into AudioController.books
  final int chapter; // 1-based
  final String path;
}

/// Describes the big queue for one author: which files exist, and where each
/// book starts inside the queue.
class _Layout {
  _Layout(this.author, this.files, this.starts, this.queue);
  final String author;
  final Map<int, List<String>> files; // bookIndex -> chapter files
  final Map<int, int> starts; // bookIndex -> queue index of its chapter 1
  final List<_QItem> queue; // every chapter, in Bible order
}

class AudioController extends ChangeNotifier with WidgetsBindingObserver {
  AudioController({required this.books, AudioLibrary? library})
    : library = library ?? AudioLibrary() {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  final List<BookInfo> books;
  final AudioLibrary library;

  // ---- lazy player ----
  AudioPlayer? _player;

  /// True once the native player has been created.
  bool get hasPlayer => _player != null;

  /// Safe accessors for the UI: they never create the player.
  /// Streams are null until the player exists.
  Stream<bool>? get playingStream => _player?.playingStream;
  Stream<Duration>? get positionStream => _player?.positionStream;
  Duration? get duration => _player?.duration;
  Duration get position => _player?.position ?? Duration.zero;
  bool get isPlaying => _player?.playing ?? false;

  /// Created on first access. Internal code that must NOT create the player
  /// uses `_player` (nullable) instead.
  AudioPlayer get player {
    final existing = _player;
    if (existing != null) return existing;
    final p = _player = AudioPlayer();
    _wire(p);
    return p;
  }

  // Player loop mode: now passes "all" straight through (single-book queue).
  LoopMode get _playerLoopMode => _manual ? LoopMode.off : loopMode;

  int? _liveBookOnly; // bookIndex if the loaded queue is single-book, else null

  _Layout _singleBook(_Layout full, int b) {
    final f = full.files[b]!;
    return _Layout(
      full.author,
      {b: f},
      {b: 0},
      [for (var c = 0; c < f.length; c++) _QItem(b, c + 1, f[c])],
    );
  }

  void _wire(AudioPlayer p) {
    _subs.add(p.currentIndexStream.listen(_onIndex));
    _subs.add(p.processingStateStream.listen(_onProcessing));
    _subs.add(p.playingStream.listen(_onPlayingChanged));

    // Seek, loop restart or automatic chapter change: re-align once.
    _subs.add(p.positionDiscontinuityStream.listen((_) => _resync()));

    // New chapter duration known: recalculate the speed on the next frame.
    _subs.add(
      p.durationStream.listen((_) {
        // New duration: only the speed changes. Never jump the page here.
        if (!_updateSpeed()) _pxPerSec = 0;
      }),
    );

    // Apply the loop mode chosen before the player existed.
    p.setLoopMode(_playerLoopMode);
  }

  // ---- state the UI reads ----
  List<String> authors = [];
  String? author;
  int bookIndex = 0; // index into [books]
  int chapter = 1; // 1-based
  bool syncWithReader = true;
  bool autoScroll = false;

  /// Sheet should sit at its compact position.
  bool get compactMode => !syncWithReader || autoScroll;

  /// Only DeSync releases the sidebars. Auto-scroll keeps them locked.
  bool get unlockWhileCompact => !syncWithReader;

  /// In compact mode, the seek bar only shows while synced with the reader.
  bool get compactShowsSeek => syncWithReader;

  bool hasAudio = false;
  LoopMode loopMode = LoopMode.off; // off | one (chapter) | all (book)

  /// Scroll speed multiplier, adjustable from your settings/backend.
  /// 1.0 = the page reaches the bottom exactly when the audio ends.
  /// 1.1 = 10% faster, 0.9 = 10% slower.
  double autoScrollFactor = 1.0;

  // filePicker in audio_bar,dart
  bool importBusy = false;

  // ---- "On Bible end" setting (saved between launches) ----
  bool bibleEndContinue = false; // false = stop, true = keep playing
  BibleEndTarget bibleEndTarget = BibleEndTarget.newTestament;

  /// Book indexes (into [books]) that the current author actually has audio
  /// for, in Bible order. Filled in by _layoutFor().
  List<int> installedBooks = [];

  /// The restart choices that make sense for the current author's audio.
  /// "Beginning of Old Testament" only appears if at least one OT book is
  /// installed, and the same for the New Testament.
  List<BibleEndTarget> get availableEndTargets => [
    BibleEndTarget.book,
    if (_firstInstalledBook(newTestament: true) != null)
      BibleEndTarget.newTestament,
    if (_firstInstalledBook(newTestament: false) != null)
      BibleEndTarget.oldTestament,
  ];

  /// The saved choice, or a safe fallback if that choice isn't available
  /// for this author (e.g. saved "Old Testament" but the pack is NT-only).
  BibleEndTarget get effectiveEndTarget =>
      availableEndTargets.contains(bibleEndTarget)
      ? bibleEndTarget
      : availableEndTargets.first;

  Future<void> setBibleEndContinue(bool v) async {
    bibleEndContinue = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('bibleEndContinue', v);
  }

  Future<void> setBibleEndTarget(BibleEndTarget t) async {
    bibleEndTarget = t;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString(
      'bibleEndTarget',
      t.name,
    );
  }

  // Old Testament = book indexes 0..38, New Testament = 39..65.
  int? _firstInstalledBook({required bool newTestament}) {
    for (final b in installedBooks) {
      if ((b >= 39) == newTestament) return b;
    }
    return null;
  }

  int? _nextInstalledBook(int after) {
    for (final b in installedBooks) {
      if (b > after) return b;
    }
    return null;
  }

  // Windows/Linux backends (media_kit) can't do playlists, so we load one
  // chapter file at a time there.
  bool get _manual => Platform.isWindows || Platform.isLinux;
  List<String> _files = []; // chapter files of the current book

  // ---- the big queue ----
  _Layout? _layout; // cached scan of the author's folders
  _Layout? _live; // the layout currently loaded INTO the player

  // ---- hooks to your reader ----
  void Function(int bookIndex, int chapter)? onAudioMoved;
  ScrollController? readerScroll;

  int _count = 0; // chapters in the current book
  bool _loading = false;
  bool _sourceLoaded = false; // has any audio been loaded into the player?
  bool _advancing = false;
  int _loadToken = 0;

  // ---- auto-scroll internals ----
  final _tickerProvider = _FrameTickerProvider();
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  double _pxPerSec = 0; // 0 = "not calculated yet"
  double _lastExtent = 0;
  bool _alignPending = false; // "snap to the audio once, as soon as possible"
  /// Only snap the reader to the audio when it's meant to follow the audio.
  bool get _canAlign =>
      _appResumed && syncWithReader && autoScroll && !_userDragging;

  /// How far (in lines) the reader may sit above/below the audio position
  /// while auto-scrolling. 0 = no limit.
  double driftLines = 5;

  /// Approximate height of one line of text in pixels.
  /// Tune this to match your reader's font size and line spacing.
  double lineHeightPx = 28;

  /// How quickly the page eases back inside the limit, per frame.
  /// 0.05 = slow and gentle, 0.3 = quick.
  double driftEase = 0.15;

  double get _maxDriftPx => driftLines * lineHeightPx;

  void setDriftLines(double lines) {
    driftLines = lines.clamp(0.0, 50.0);
    notifyListeners();
  }

  bool _userDragging = false;
  bool _appResumed = true;
  bool _screenAwakeRequested = false;
  Future<void> _screenAwakeOperation = Future<void>.value();

  final List<StreamSubscription<dynamic>> _subs = [];

  String get bookName => books[bookIndex].name;
  String get loopLabel => const {
    LoopMode.off: 'Off',
    LoopMode.one: 'Chap',
    LoopMode.all: 'Book',
  }[loopMode]!;

  Future<void> _init() async {
    // No player or subscriptions here any more: see _wire().
    final prefs = await SharedPreferences.getInstance();
    bibleEndContinue = prefs.getBool('bibleEndContinue') ?? false;
    final savedTarget = prefs.getString('bibleEndTarget');
    bibleEndTarget = BibleEndTarget.values.firstWhere(
      (t) => t.name == savedTarget,
      orElse: () => BibleEndTarget.newTestament,
    );
    await refreshAuthors();
  }

  // ---------------- the big queue helpers ----------------
  /// Scans the author's folders (all 66 books) and builds the queue layout.
  /// Cached until refreshAuthors() clears it.
  Future<_Layout> _layoutFor(String a) async {
    final cached = _layout;
    if (cached != null && cached.author == a) return cached;

    final files = <int, List<String>>{};
    final starts = <int, int>{};
    final queue = <_QItem>[];
    for (var b = 0; b < books.length; b++) {
      final f = await library.bookFiles(a, books[b]);
      if (f.isEmpty) continue; // book not installed: skipped in the queue
      files[b] = f;
      starts[b] = queue.length;
      for (var c = 0; c < f.length; c++) {
        queue.add(_QItem(b, c + 1, f[c]));
      }
    }
    installedBooks = files.keys.toList();
    return _layout = _Layout(a, files, starts, queue);
  }

  AudioSource _child(_Layout layout, _QItem q) => AudioSource.file(
    q.path,
    tag: MediaItem(
      id: q.path,
      title: '${books[q.bookIndex].name} ${q.chapter}',
      artist: layout.author,
      album: books[q.bookIndex].name,
    ),
  );

  List<AudioSource> _buildSources(_Layout layout) => [
    for (final q in layout.queue) _child(layout, q),
  ];

  // ---------------- authors ----------------
  Future<void> refreshAuthors() async {
    _layout = null; // files may have changed: rescan next time
    authors = await library.authors();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('audioVersion');
    final resolved = authors.contains(saved)
        ? saved
        : (authors.isNotEmpty ? authors.first : null);
    final changed = resolved != author;
    author = resolved;
    if (resolved != null) {
      await _layoutFor(resolved); // also refreshes installedBooks
    } else {
      installedBooks = [];
    }
    notifyListeners();
    if (changed) await _loadBook(chapter: chapter, moveReader: false);
  }

  Future<void> setAuthor(String? a) async {
    if (a == null || a == author) return;
    author = a;
    (await SharedPreferences.getInstance()).setString('audioVersion', a);
    notifyListeners();
    await _loadBook(chapter: chapter, moveReader: false);
  }

  /// phase: 'zip' -> 'save' (dialog open) -> 'write' (pct 0..100).
  Future<bool> exportAuthor(
    String author, {
    void Function(String phase, double pct)? onPhase,
  }) async {
    onPhase?.call('zip', 0);
    final zip = await library.buildAuthorZip(author);
    try {
      const fg = Filegate();

      onPhase?.call('save', 0);
      final saved = await fg.saveFile(
        Uint8List(0),
        suggestedName: '${author.replaceAll(RegExp(r'[^\w\- ]'), '_')}.zip',
        allowedExtensions: ['zip'],
        mimeType: 'application/zip',
      );
      if (saved == null) return false; // cancelled

      final total = await zip.length();
      var lastPct = -1;
      onPhase?.call('write', 0);
      await fg.writeStream(
        saved.path,
        zip.openRead(),
        totalBytes: total,
        onProgress: (p) {
          // Only report whole-percent changes, not every 64 KB chunk.
          final pct = total > 0 ? (p.bytesWritten * 100 / total).floor() : 0;
          if (pct != lastPct) {
            lastPct = pct;
            onPhase?.call('write', pct.toDouble());
          }
        },
      );
      return true;
    } finally {
      if (zip.existsSync()) await zip.delete();
    }
  }

  Future<String> importZip(
    String path,
    void Function(double) onProgress,
  ) async {
    final a = await library.importZip(path, onProgress);
    await refreshAuthors();
    return a;
  }

  /// phase: 'download' or 'extract'; pct: 0..100 (0 = unknown/indeterminate).
  Future<String> downloadPack(
    AudioPack pack,
    void Function(String phase, double pct) onProgress,
    CancelFlag cancel,
  ) async {
    final safe = pack.name.replaceAll(RegExp(r'[^\w\- ]'), '_');
    final path = await library.downloadZip(
      pack.url,
      '$safe.zip',
      (v) => onProgress('download', v),
      cancel,
    );
    try {
      final a = await library.importZip(
        path,
        (v) => onProgress('extract', v),
        authorName: pack.name,
      );
      await refreshAuthors();
      return a;
    } finally {
      final f = File(path);
      if (await f.exists()) await f.delete(); // free the space
    }
  }

  Future<void> deleteCurrentAuthor() async {
    final a = author;
    if (a == null) return;
    await _player?.stop();
    await library.deleteAuthor(a);
    author = null;
    hasAudio = false;
    _sourceLoaded = false;
    _live = null;
    _layout = null;
    _liveBookOnly = null;
    await refreshAuthors();
  }

  // ---------------- reader <-> audio ----------------
  /// Call this from your reader whenever its book/chapter changes.
  void readerMoved(int newBook, int newChapter) {
    if (!syncWithReader) return;
    _jumpTo(newBook, newChapter);
  }

  void toggleSync() {
    syncWithReader = !syncWithReader;
    if (!syncWithReader) {
      autoScroll = false;
      _stopScrolling();
    }
    notifyListeners();
    // Re-syncing: reader follows wherever audio currently is.
    if (syncWithReader) onAudioMoved?.call(bookIndex, chapter);
  }

  void toggleAutoScroll() {
    if (!syncWithReader) return;
    autoScroll = !autoScroll;
    if (autoScroll) {
      _startScrolling(resync: true);
    } else {
      _stopScrolling();
    }
    notifyListeners();
  }

  /// Change the speed multiplier (e.g. from a settings slider).
  void setAutoScrollFactor(double factor) {
    autoScrollFactor = factor.clamp(0.25, 4.0);
    notifyListeners();
  }

  // ---------------- auto-scroll ----------------
  /// Call when the user starts dragging the reader, so we don't fight
  /// their finger. See the reader snippet at the bottom of this file.
  void onUserScrollStart() {
    _userDragging = true;
    _stopScrolling();
  }

  /// Call when the user lets go. Scrolling continues from where they left it.
  void onUserScrollEnd() {
    _userDragging = false;
    _startScrolling(resync: false);
  }

  void _onPlayingChanged(bool isPlaying) {
    if (isPlaying) {
      _startScrolling(resync: true);
    } else {
      _stopScrolling();
    }
    notifyListeners();
  }

  bool get _shouldScroll =>
      _appResumed &&
      (_player?.playing ?? false) &&
      syncWithReader &&
      autoScroll &&
      !_userDragging;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (_appResumed == resumed) return;
    _appResumed = resumed;
    if (!resumed) {
      autoScroll = false;
      _stopScrolling();
      notifyListeners();
    }
  }

  void _startScrolling({required bool resync}) {
    _stopScrolling();
    if (!_shouldScroll) return;

    if (resync) {
      _resync();
    } else {
      _updateSpeed();
    }
    _lastElapsed = Duration.zero;
    _ticker = _tickerProvider.createTicker(_onTick)..start();
    _setScreenAwake(true);
  }

  void _stopScrolling() {
    final t = _ticker;
    _ticker = null;
    if (t != null) {
      t.stop();
      t.dispose();
    }
    _setScreenAwake(false);
  }

  void _setScreenAwake(bool enabled) {
    if (_screenAwakeRequested == enabled) return;
    _screenAwakeRequested = enabled;
    _screenAwakeOperation = _screenAwakeOperation
        .then((_) => WakelockPlus.toggle(enable: enabled))
        .catchError((Object error) {
          debugPrint('Failed to update screen wake lock: $error');
        });
  }

  /// Is the scroll view ready to be measured/moved?
  bool get _scrollReady {
    final s = readerScroll;
    return s != null && s.hasClients && s.position.hasContentDimensions;
  }

  /// Calculates speed = page height / audio duration. Does NOT move the page.
  /// Returns false if duration/extent aren't known yet.
  bool _updateSpeed() {
    final duration = _player?.duration;
    if (!_scrollReady || duration == null || duration.inMilliseconds <= 0) {
      return false;
    }
    final extent = readerScroll!.position.maxScrollExtent;
    _lastExtent = extent;
    _pxPerSec = extent / (duration.inMilliseconds / 1000.0);
    return true;
  }

  /// One-time alignment: calculate the speed AND snap to the audio position.
  /// Used on play, seek, chapter change and loop restart. Never every frame.
  void _resync() {
    if (!_canAlign) {
      _pxPerSec = 0; // DeSync'd or auto-scroll off: leave the reader alone
      return;
    }
    final p = _player;
    if (p == null || !_updateSpeed()) {
      _pxPerSec = 0;
      _alignPending = true; // duration not known yet: align once it is
      return;
    }
    _alignPending = false;
    final duration = p.duration!;
    final progress = (p.position.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0);
    readerScroll!.jumpTo(progress * _lastExtent);
  }

  /// Runs once per screen frame while auto-scrolling.
  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed; // still updated, so no catch-up jump afterwards

    if (!_shouldScroll || !_scrollReady) return;

    final scroll = readerScroll!;

    // A finger drag or fling is moving the page: don't fight it.
    // (Our own jumpTo() never sets this flag, so auto-scroll is unaffected.)
    if (scroll.position.isScrollingNotifier.value) return;

    // Speed not known yet: align only if a real event asked for it,
    // otherwise just calculate the speed (no jump).
    if (_pxPerSec == 0) {
      if (_alignPending) {
        _resync();
      } else {
        _updateSpeed();
      }
      return;
    }

    final max = scroll.position.maxScrollExtent;
    if ((max - _lastExtent).abs() > 1.0) _updateSpeed();

    var next = scroll.offset + _pxPerSec * autoScrollFactor * dt;

    // Keep the page within +/- driftLines of where the audio is.
    final p = _player;
    final dur = p?.duration;
    if (driftLines > 0 && p != null && dur != null && dur.inMilliseconds > 0) {
      final progress = (p.position.inMilliseconds / dur.inMilliseconds).clamp(
        0.0,
        1.0,
      );
      final ideal = progress * _lastExtent;
      final low = ideal - _maxDriftPx;
      final high = ideal + _maxDriftPx;

      // Ease back toward the limit instead of snapping.
      if (next < low) {
        next += (low - next) * driftEase;
      } else if (next > high) {
        next -= (next - high) * driftEase;
      }
    }

    scroll.jumpTo(next.clamp(0.0, max));
  }

  // ---------------- jumping / loading ----------------
  Future<void> _jumpTo(int b, int c) async {
    if (b == bookIndex) {
      if (c == chapter || c < 1 || (_count > 0 && c > _count)) return;
      chapter = c;
      notifyListeners();
      await _seekChapter(c);
    } else {
      bookIndex = b;
      chapter = c; // remember it even if the load bails out
      await _loadBook(chapter: c);
    }
  }

  Future<void> _loadBook({
    int chapter = 1,
    bool atLast = false,
    bool play = false,
    bool moveReader = true,
  }) async {
    final a = author;
    if (a == null) return;
    final token =
        ++_loadToken; // if the user taps fast, only the latest load wins
    _loading = true;
    final wasPlaying = _player?.playing ?? false;

    final layout = await _layoutFor(a);
    if (token != _loadToken) return;

    final files = layout.files[bookIndex] ?? const <String>[];

    if (files.isEmpty) {
      _loading = false;
      _count = 0;
      hasAudio = false;
      _sourceLoaded = false;
      _live = null;
      _stopScrolling();
      await _player?.stop();
      notifyListeners();
      return;
    }

    _count = files.length;
    hasAudio = true;
    this.chapter = atLast ? files.length : chapter.clamp(1, files.length);

    _files = files;

    // No player yet and not asked to play: just remember where we are.
    // The player gets created (and the queue loaded into it) on first play.
    if (!_sourceLoaded && !play) {
      _loading = false;
      _resetScrollForNewChapter();
      notifyListeners();
      if (moveReader && syncWithReader) {
        onAudioMoved?.call(bookIndex, this.chapter);
      }
      return;
    }

    if (_manual) {
      await _openChapter(this.chapter, play: play || wasPlaying);
      return;
    }

    // ---- Android / iOS ----
    final bookLoop = loopMode == LoopMode.all;
    final queueLayout = bookLoop ? _singleBook(layout, bookIndex) : layout;
    final target = queueLayout.starts[bookIndex]! + this.chapter - 1;
    final reuse =
        _sourceLoaded &&
        (bookLoop
            ? _liveBookOnly == bookIndex
            : (_liveBookOnly == null && identical(_live, layout)));
    try {
      if (reuse) {
        await player.seek(Duration.zero, index: target);
      } else {
        await player.setAudioSources(
          _buildSources(queueLayout),
          initialIndex: target,
        );
        _live = queueLayout;
        _liveBookOnly = bookLoop ? bookIndex : null;
        _sourceLoaded = true;
      }
    } catch (e) {
      debugPrint('Failed to load book: $e');
    }

    if (token != _loadToken) return;

    _loading = false;
    _resetScrollForNewChapter();
    notifyListeners();
    if (moveReader && syncWithReader) {
      onAudioMoved?.call(bookIndex, this.chapter);
    }
    if (play || wasPlaying) {
      player.play(); // don't await: it finishes when playback stops
    }
  }

  /// Manual mode only: load a single chapter file.
  Future<void> _openChapter(int ch, {bool play = false}) async {
    if (ch < 1 || ch > _files.length) return;
    final token = ++_loadToken;
    chapter = ch;
    final shouldPlay = play || (_player?.playing ?? false);
    _loading = true;
    try {
      await player.setAudioSource(AudioSource.file(_files[ch - 1]));
      _sourceLoaded = true;
    } catch (e) {
      debugPrint('Failed to load chapter: $e');
    }
    if (token != _loadToken) return;
    _loading = false;
    _resetScrollForNewChapter();
    notifyListeners();
    if (syncWithReader) onAudioMoved?.call(bookIndex, chapter);
    if (shouldPlay) player.play();
  }

  Future<void> _seekChapter(int ch) async {
    // No player yet: just move the bookmark. It loads on first play.
    if (!_sourceLoaded) {
      if (ch < 1 || ch > _count) return;
      chapter = ch;
      _resetScrollForNewChapter();
      notifyListeners();
      if (syncWithReader) onAudioMoved?.call(bookIndex, chapter);
      return;
    }
    if (_manual) {
      await _openChapter(ch);
    } else {
      final start = _live?.starts[bookIndex];
      if (start == null) return;
      await player.seek(Duration.zero, index: start + ch - 1);
    }
  }

  Future<void> goToBook(
    int newIndex, {
    bool atLast = false,
    bool play = false,
  }) async {
    if (newIndex < 0 || newIndex >= books.length) return;
    bookIndex = newIndex;
    await _loadBook(chapter: 1, atLast: atLast, play: play);
  }

  /// New chapter: forget the old speed. Only move the reader to the top
  /// if it is following the audio.
  void _resetScrollForNewChapter() {
    _pxPerSec = 0;
    if (!syncWithReader) return; // DeSync'd: leave the reader alone
    final s = readerScroll;
    if (s != null && s.hasClients) s.jumpTo(0);
  }

  // ---------------- player events ----------------
  /// The player moved to a new queue position (tray next/prev, automatic
  /// advance, or our own seek). Work out which book/chapter that is.
  void _onIndex(int? i) {
    if (_manual) return;
    if (i == null || _loading) return;
    final live = _live;
    if (live == null || i < 0 || i >= live.queue.length) return;
    final item = live.queue[i];

    // "Loop: Book" - the queue crossed into another book, so bounce back:
    // forward past the last chapter -> first chapter of THIS book,
    // backward before the first chapter -> last chapter of THIS book.
    // if (loopMode == LoopMode.all && item.bookIndex != bookIndex) {
    //   final start = live.starts[bookIndex];
    //   if (start == null) return;
    //   final forward = item.bookIndex > bookIndex;
    //   _player?.seek(Duration.zero, index: forward ? start : start + _count - 1);
    //   return;
    // }

    if (item.bookIndex == bookIndex && item.chapter == chapter) return;

    bookIndex = item.bookIndex;
    chapter = item.chapter;
    _files = live.files[bookIndex] ?? const <String>[];
    _count = _files.length;
    hasAudio = true;
    _resetScrollForNewChapter();
    notifyListeners();
    if (syncWithReader) onAudioMoved?.call(bookIndex, chapter);
  }

  Future<void> _onProcessing(ProcessingState s) async {
    if (s != ProcessingState.completed || _loading || _advancing) return;

    // ---- Android / iOS: "completed" means the END of the whole queue ----
    if (!_manual) {
      _advancing = true;
      try {
        final start = _live?.starts[bookIndex];
        if (loopMode == LoopMode.all && start != null) {
          // Looping this book, and it was the last installed book.
          await _player?.seek(Duration.zero, index: start);
          _player?.play();
        } else if (loopMode == LoopMode.one) {
          // Normally the player loops the chapter itself and never gets
          // here. If it ever stops anyway, restart the chapter by hand.
          final base = _live?.starts[bookIndex];
          if (base != null) {
            await _player?.seek(Duration.zero, index: base + chapter - 1);
            _player?.play();
          }
        } else if (loopMode == LoopMode.off) {
          await _handleBibleEnd();
        }
      } finally {
        _advancing = false;
      }
      return;
    }

    // ---- Windows/Linux (manual mode) ----
    // Loop "Chap": the player is NOT asked to loop (see _playerLoopMode),
    // so reload and replay the same chapter ourselves.
    if (loopMode == LoopMode.one) {
      _advancing = true;
      await _openChapter(chapter, play: true);
      _advancing = false;
      return;
    }
    {
      if (chapter < _count) {
        _advancing = true;
        await _openChapter(chapter + 1, play: true);
        _advancing = false;
        return;
      }
      if (loopMode == LoopMode.all) {
        _advancing = true;
        await _openChapter(1, play: true);
        _advancing = false;
        return;
      }
    }
    // Whole book finished with loop off -> roll into the next book.
    if (loopMode != LoopMode.off) return;
    _advancing = true;
    final nextBook = _nextInstalledBook(bookIndex);
    if (nextBook != null) {
      await goToBook(nextBook, play: true);
    } else {
      await _handleBibleEnd();
    }
    _advancing = false;
  }

  /// The last installed chapter has finished (loop is Off).
  /// Applies the "On Bible end" setting: stop, or keep playing from
  /// the chosen place.
  Future<void> _handleBibleEnd() async {
    if (bibleEndContinue) {
      final book = switch (effectiveEndTarget) {
        // "Beginning of Book": chapter 1 of the book that just finished
        // (e.g. Revelation 22 ends -> Revelation 1).
        BibleEndTarget.book => bookIndex,
        BibleEndTarget.newTestament => _firstInstalledBook(newTestament: true),
        BibleEndTarget.oldTestament => _firstInstalledBook(newTestament: false),
      };
      await goToBook(book ?? bookIndex, play: true);
      return;
    }

    // Stop: just stop. We stay on the last chapter (e.g. Revelation 22),
    // rewound to 0:00 so pressing Play replays it instead of doing nothing.
    await _player?.pause();
    await _player?.seek(Duration.zero);
  }

  // ---------------- transport ----------------
  /// Starts playback, loading the current chapter first if nothing is loaded.
  Future<void> play() async {
    final p = _player;
    if (p == null || !_sourceLoaded) {
      await _loadBook(chapter: chapter, play: true);
      return;
    }
    if (!p.playing) p.play(); // don't await: it finishes when playback stops
  }

  void pause() {
    _player?.pause();
  }

  Future<void> togglePlay() async {
    if (_player?.playing ?? false) {
      pause();
    } else {
      await play();
    }
  }

  Future<void> next() async {
    if (chapter < _count) {
      await _seekChapter(chapter + 1);
    } else if (loopMode == LoopMode.all && _count > 0) {
      await _seekChapter(1); // loop Book: wrap to the first chapter
    } else {
      await goToBook(bookIndex + 1);
    }
  }

  Future<void> previous() async {
    if (chapter > 1) {
      await _seekChapter(chapter - 1);
    } else if (loopMode == LoopMode.all && _count > 0) {
      await _seekChapter(_count); // loop Book: wrap to the last chapter
    } else {
      await goToBook(bookIndex - 1, atLast: true);
    }
  }

  Future<void> seek(Duration d) async {
    await _player?.seek(d);
  }

  /// Entering Book loop: drop every chapter outside the current book.
  Future<void> _narrowToBook() async {
    final full = _live;
    final p = _player;
    if (full == null || p == null) return;
    final start = full.starts[bookIndex];
    final len = full.files[bookIndex]?.length;
    if (start == null || len == null) return;
    final end = start + len;

    _loading = true;
    try {
      // Tail first, so the head's indexes don't move underneath us.
      if (end < full.queue.length) {
        await p.removeAudioSourceRange(end, full.queue.length);
      }
      if (start > 0) await p.removeAudioSourceRange(0, start);
      _live = _singleBook(full, bookIndex);
      _liveBookOnly = bookIndex;
    } finally {
      _loading = false;
    }
  }

  /// Leaving Book loop: put the other books back around the current one.
  Future<void> _widenToAll() async {
    final a = author;
    final p = _player;
    if (a == null || p == null) return;
    final full = await _layoutFor(a);
    final start = full.starts[bookIndex];
    final len = full.files[bookIndex]?.length;
    if (start == null || len == null) return;
    final end = start + len;

    _loading = true;
    try {
      await p.addAudioSources([
        for (final q in full.queue.sublist(end)) _child(full, q),
      ]);
      await p.insertAudioSources(0, [
        for (final q in full.queue.sublist(0, start)) _child(full, q),
      ]);
      _live = full;
      _liveBookOnly = null;
    } finally {
      _loading = false;
    }
  }

  Future<void> cycleLoop() async {
    final was = loopMode;
    loopMode = switch (loopMode) {
      LoopMode.off => LoopMode.one,
      LoopMode.one => LoopMode.all,
      LoopMode.all => LoopMode.off,
    };
    await _player?.setLoopMode(_playerLoopMode);

    // Entering/leaving Book loop changes which queue should be loaded.
    final queueKindChanged =
        (was == LoopMode.all) != (loopMode == LoopMode.all);
    if (!_manual && _sourceLoaded && queueKindChanged) {
      if (_live == null || _player == null) {
        final pos = _player!.position;
        final wasPlaying = _player!.playing;
        await _loadBook(chapter: chapter, play: wasPlaying, moveReader: false);
        await _player?.seek(pos);
      } else if (loopMode == LoopMode.all) {
        await _narrowToBook();
      } else {
        await _widenToAll();
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopScrolling();
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// READER SNIPPET (put this in your reader page, not in this file).
// It stops auto-scroll while the user drags, so the page doesn't fight
// their finger:
//
// NotificationListener<UserScrollNotification>(
//   onNotification: (n) {
//     if (n.direction != ScrollDirection.idle) {
//       controller.onUserScrollStart();
//     } else {
//       controller.onUserScrollEnd();
//     }
//     return false;
//   },
//   child: SingleChildScrollView(
//     controller: controller.readerScroll,
//     child: YourChapterText(),
//   ),
// )
//
// (ScrollDirection comes from: import 'package:flutter/rendering.dart';)
//
// Also: don't let anything call setState / rebuild the reader on every scroll
// change, and prefer a SingleChildScrollView (or fixed-height items) so the
// page height stays stable.
// ---------------------------------------------------------------------------
