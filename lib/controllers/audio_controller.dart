// lib/state/audio_controller.dart
// just_audio owns the queue, looping and media notification, so this is
// mostly "which book/chapter am I on" bookkeeping, plus auto-scroll.
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

import '../services/audio_library.dart';

/// A ChangeNotifier has no "vsync", so we provide a tiny TickerProvider that
/// lets us create a Ticker (a callback that fires once per screen frame).
class _FrameTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

class AudioController extends ChangeNotifier {
  AudioController({required this.books, AudioLibrary? library})
    : library = library ?? AudioLibrary() {
    _init();
  }

  final List<BookInfo> books;
  final AudioLibrary library;

  // ---- lazy player ----
  AudioPlayer? _player;

  /// True once the native player has been created.
  bool get hasPlayer => _player != null;

  /// Created on first access. Internal code that must NOT create the player
  /// uses `_player` (nullable) instead.
  AudioPlayer get player {
    final existing = _player;
    if (existing != null) return existing;
    final p = _player = AudioPlayer();
    _wire(p);
    return p;
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
        _pxPerSec = 0;
      }),
    );

    // Apply the loop mode chosen before the player existed.
    p.setLoopMode(
      _manual && loopMode == LoopMode.all ? LoopMode.off : loopMode,
    );
  }

  // ---- state the UI reads ----
  List<String> authors = [];
  String? author;
  int bookIndex = 0; // index into [books]
  int chapter = 1; // 1-based
  bool syncWithReader = true;
  bool autoScroll = false;
  bool hasAudio = false;
  LoopMode loopMode = LoopMode.off; // off | one (chapter) | all (book)

  /// Scroll speed multiplier, adjustable from your settings/backend.
  /// 1.0 = the page reaches the bottom exactly when the audio ends.
  /// 1.1 = 10% faster, 0.9 = 10% slower.
  double autoScrollFactor = 1.0;

  // filePicker in audio_bar,dart
  bool importBusy = false;

  // Windows/Linux backends (media_kit) can't do playlists, so we load one
  // chapter file at a time there.
  bool get _manual => Platform.isWindows || Platform.isLinux;
  List<String> _files = [];

  // ---- hooks to your reader ----
  void Function(int bookIndex, int chapter)? onAudioMoved;
  ScrollController? readerScroll;

  int _count = 0; // chapters in the loaded book
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
  bool _userDragging = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  String get bookName => books[bookIndex].name;
  String get loopLabel => const {
    LoopMode.off: 'Off',
    LoopMode.one: 'Chap',
    LoopMode.all: 'Book',
  }[loopMode]!;

  Future<void> _init() async {
    // No player or subscriptions here any more: see _wire().
    await refreshAuthors();
  }

  // ---------------- authors ----------------
  Future<void> refreshAuthors() async {
    authors = await library.authors();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('audioVersion');
    final resolved = authors.contains(saved)
        ? saved
        : (authors.isNotEmpty ? authors.first : null);
    final changed = resolved != author;
    author = resolved;
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

  /// Rezips [author] and lets the user pick where to save it
  /// (same save-as picker you use for the reader Bibles).
  /// Returns true only if the file was really saved.
  // Future<bool> exportAuthor(String author) async {
  //   final zip = await library.buildAuthorZip(author);
  //   try {
  //     final saved = await FlutterFileDialog.saveFile(
  //       params: SaveFileDialogParams(
  //         sourceFilePath: zip.path, // copied natively, never loaded into memory
  //         fileName: '${author.replaceAll(RegExp(r'[^\w\- ]'), '_')}.zip',
  //       ),
  //     );
  //     return saved != null; // null = cancelled
  //   } finally {
  //     if (zip.existsSync()) await zip.delete();
  //   }
  // }

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
      (_player?.playing ?? false) &&
      syncWithReader &&
      autoScroll &&
      !_userDragging;

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
  }

  void _stopScrolling() {
    final t = _ticker;
    _ticker = null;
    if (t != null) {
      t.stop();
      t.dispose();
    }
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
    final p = _player;
    if (p == null || !_updateSpeed()) {
      _pxPerSec = 0; // try again on a later frame
      return;
    }
    final duration = p.duration!;
    final progress = (p.position.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0);
    readerScroll!.jumpTo(progress * _lastExtent);
  }

  /// Runs once per screen frame while auto-scrolling.
  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    if (!_shouldScroll || !_scrollReady) return;

    // Speed not known yet (e.g. new chapter still loading): align once.
    if (_pxPerSec == 0) {
      _resync();
      return;
    }

    final scroll = readerScroll!;
    final max = scroll.position.maxScrollExtent;

    // Page layout changed (images loaded, etc.): recompute the speed only.
    // No jump, so the text stays steady.
    if ((max - _lastExtent).abs() > 1.0) {
      _updateSpeed();
    }

    final next = (scroll.offset + _pxPerSec * autoScrollFactor * dt).clamp(
      0.0,
      max,
    );
    scroll.jumpTo(next);
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
      chapter = c; // <- add: remember it even if the load bails out
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

    final files = await library.bookFiles(a, books[bookIndex]);
    if (token != _loadToken) return;

    if (files.isEmpty) {
      _loading = false;
      _count = 0;
      hasAudio = false;
      _sourceLoaded = false;
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
    // The player gets created (and this book loaded into it) on first play.
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

    final source = ConcatenatingAudioSource(
      children: [
        for (final f in files)
          AudioSource.file(
            f,
            tag: MediaItem(
              id: f,
              title: f
                  .split(RegExp(r'[\\/]'))
                  .last
                  .replaceAll(RegExp(r'\.(m4a|mp3)$'), ''),
              artist: a,
              album: books[bookIndex].name,
            ),
          ),
      ],
    );

    try {
      await player.setAudioSource(source, initialIndex: this.chapter - 1);
      _sourceLoaded = true;
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
      await player.seek(Duration.zero, index: ch - 1);
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

  /// New chapter: forget the old speed and start from the top.
  void _resetScrollForNewChapter() {
    _pxPerSec = 0;
    final s = readerScroll;
    if (s != null && s.hasClients) s.jumpTo(0);
  }

  // ---------------- player events ----------------
  void _onIndex(int? i) {
    if (_manual) return;
    if (i == null || _loading) return;
    final ch = i + 1;
    if (ch == chapter) return;
    chapter = ch;
    _resetScrollForNewChapter();
    notifyListeners();
    if (syncWithReader) onAudioMoved?.call(bookIndex, chapter);
  }

  Future<void> _onProcessing(ProcessingState s) async {
    if (_manual &&
        s == ProcessingState.completed &&
        !_loading &&
        !_advancing &&
        loopMode != LoopMode.one) {
      // "one" is looped by the player itself
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
    if (s != ProcessingState.completed ||
        loopMode != LoopMode.off ||
        _advancing ||
        _loading) {
      return;
    }
    _advancing = true;
    if (bookIndex + 1 < books.length) {
      await goToBook(bookIndex + 1, play: true);
    } else {
      await _player?.pause();
      await _player?.seek(Duration.zero, index: 0);
    }
    _advancing = false;
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
    } else {
      await goToBook(bookIndex + 1);
    }
  }

  Future<void> previous() async {
    if (chapter > 1) {
      await _seekChapter(chapter - 1);
    } else {
      await goToBook(bookIndex - 1, atLast: true);
    }
  }

  Future<void> seek(Duration d) async {
    await _player?.seek(d);
  }

  Future<void> cycleLoop() async {
    loopMode = switch (loopMode) {
      LoopMode.off => LoopMode.one,
      LoopMode.one => LoopMode.all,
      LoopMode.all => LoopMode.off,
    };
    // If the player doesn't exist yet, _wire() applies this when it's created.
    await _player?.setLoopMode(
      _manual && loopMode == LoopMode.all ? LoopMode.off : loopMode,
    );
    notifyListeners();
  }

  @override
  void dispose() {
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
