import 'dart:math' as math;
import 'dart:async';

import 'package:dba2/core.dart' hide BoxShadow, BoxDecoration;
import 'package:dba2/ui/votd/votd_controller.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_inset_shadow/flutter_inset_shadow.dart';

import '../main/models/bible_book.dart';
import '../main/controllers/bible_controller.dart';
import 'sidebar_reveal.dart';

// ---------------------------------------------------------------------------
// TEST SWITCHES
// ---------------------------------------------------------------------------

/// false = build EVERY row up front (like your DOM). true = only visible rows.
const bool kLazyLists = true;

// Votd Image Animation
const bool kAnimateVotdImage = true;

/// Always-running strip under the banner.
const bool kShowVotdAnimation = false;

// Ken Burns banner controls. Pan offsets are fractions of the image size:
// Offset(-0.05, 0.03) moves 5% left and 3% down. Zoom 1.25 is 25% larger.
// Each cycle zooms in, then out; pan moves continuously to a new destination.
const double kVotdBannerHeight = 135;
const Duration kVotdMotionStartDelay = Duration(milliseconds: 2000);
const double kVotdEaseInSeconds = 4; // time to reach full speed after opening

const double kVotdZoomMin = 1.2;
const double kVotdZoomMax = 1.35;
const double kVotdZoomPeriod = 24; // seconds for one zoom in-and-out

const Offset kVotdPanRadius = Offset(0.05, 0.04); // fraction of image size
const double kVotdPanXPeriod =
    31; // seconds; different periods = no obvious loop
const double kVotdPanYPeriod = 43;

const Alignment kVotdZoomAlignment = Alignment.center;
const Alignment kVotdImageAlignment = Alignment.topCenter;
const double kVotdImageOpacity = 0.9;

const double kRowHeight = 50;

// ---------------------------------------------------------------------------
// MAIN SIDEBAR
// ---------------------------------------------------------------------------

class SidebarLeftContent extends StatefulWidget {
  const SidebarLeftContent({super.key, required this.controller});

  final BibleController controller;

  @override
  State<SidebarLeftContent> createState() => _SidebarLeftContentState();
}

class _SidebarLeftContentState extends State<SidebarLeftContent> {
  bool _isOt = true;
  String? _preBookId; // book whose chapters are listed (like preSelectBook)
  String? _syncedBookId; // last book we copied from the controller
  int? _syncedChapter; // last chapter we copied from the controller
  int _epoch =
      0; // bumped when the reader moves the testament: rebuild without sliding

  // One pair per testament, so the sliding pages never share a controller.
  final _bookScrolls = {true: ScrollController(), false: ScrollController()};
  final _chapterScrolls = {true: ScrollController(), false: ScrollController()};

  ScrollController get _bookScroll => _bookScrolls[_isOt]!;
  ScrollController get _chapterScroll => _chapterScrolls[_isOt]!;

  BibleController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onControllerChanged);
    _applyBook();
    _centerActive(animate: false);
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChanged);
    for (final c in [..._bookScrolls.values, ..._chapterScrolls.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final beforeBook = _syncedBookId;
    final beforeOt = _isOt;
    setState(() {
      _applyBook();
      if (_isOt != beforeOt) _epoch++; // reader moved us: no slide
    });
    // jump (don't animate) when the book or testament page changed
    _centerActive(animate: beforeBook == _syncedBookId && beforeOt == _isOt);
  }

  // When the app's current book changes (database loaded, Next/Previous,
  // or a chapter picked here), follow it.
  void _applyBook() {
    final book = _c.currentBook;
    if (book == null) return;
    if (book.id == _syncedBookId && _c.selectedChapter == _syncedChapter) {
      return;
    }
    _syncedBookId = book.id;
    _syncedChapter = _c.selectedChapter;
    _preBookId = book.id;
    _isOt = book.isOldTestament;
  }

  void _selectBook(String id) => setState(() => _preBookId = id);

  void _selectChapter(int n) {
    final id = _preBookId;
    if (id == null) return;
    _c.goTo(id, n);
    SidebarReveal.of(context).close(); // delete this line to keep it open
  }

  void _setTestament(bool ot) {
    if (_isOt == ot) return;
    setState(() {
      _isOt = ot;
      _preBookId = _c.currentBook?.id; // your optional line, if you kept it
    });
    _centerActive(animate: false);
  }

  void _swipeLeft() {
    if (_isOt) {
      _setTestament(false); // OT -> NT
    } else {
      SidebarReveal.of(context).close(); // NT -> close
    }
  }

  void _swipeRight() {
    if (!_isOt) _setTestament(true); // NT -> OT
  }

  static const _ntKey = ValueKey('nt');
  static const _otKey = ValueKey('ot');

  @override
  Widget build(BuildContext context) {
    final bg = context.colorScheme.secondary;
    return Material(
      color: bg,
      child: SafeArea(
        child: _SwipeDetector(
          threshold: 60,
          onSwipeLeft: _swipeLeft,
          onSwipeRight: _swipeRight,
          child: Column(
            children: [
              const _VotdBanner(),
              const SizedBox(height: 5.0),
              Expanded(
                child: ClipRect(
                  child: AnimatedSwitcher(
                    key: ValueKey(
                      _epoch,
                    ), // new epoch = fresh switcher, no slide
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      // NT is always the page on top (the last child is drawn last)
                      children: _isOt
                          ? [?current, ...previous]
                          : [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) {
                      final isNt = child.key == _ntKey;
                      return isNt
                          ? SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(1, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: ColoredBox(color: bg, child: child),
                            )
                          : SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(-0.3, 0), // parallax amount
                                end: Offset.zero,
                              ).animate(animation),
                              child: FadeTransition(
                                opacity: Tween<double>(
                                  begin: 0.4,
                                  end: 1,
                                ).animate(animation), // dim amount
                                child: child,
                              ),
                            );
                    },
                    child: KeyedSubtree(
                      key: _isOt ? _otKey : _ntKey,
                      child: Row(
                        children: [
                          Expanded(child: _bookList()),
                          Container(
                            width: 2,
                            color: context.colorScheme.primary,
                          ),
                          SizedBox(width: 70, child: _chapterList()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _testamentBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Books (left column) ----
  Widget _bookList() {
    final books = _c.books
        .where((b) => b.isOldTestament == _isOt)
        .toList(growable: false);

    Widget item(int i) => _SbButton(
      label: books[i].englishName,
      active: books[i].id == _preBookId,
      alignment: Alignment.centerLeft,
      onTap: () => _selectBook(books[i].id),
    );

    if (kLazyLists) {
      return ListView.builder(
        controller: _bookScroll,
        key: ValueKey('books-$_isOt'),
        itemExtent: kRowHeight,
        itemCount: books.length,
        itemBuilder: (_, i) => item(i),
      );
    }
    return SingleChildScrollView(
      controller: _bookScroll,
      key: ValueKey('books-$_isOt'),
      child: Column(
        children: [
          for (var i = 0; i < books.length; i++)
            SizedBox(height: kRowHeight, child: item(i)),
        ],
      ),
    );
  }

  // ---- Chapters (right column) ----
  Widget _chapterList() {
    BibleBook? pre;
    for (final b in _c.books) {
      if (b.id == _preBookId) pre = b;
    }
    final count = pre?.numberOfChapters ?? 0;
    final isCurrentBook = _preBookId == _c.selectedBookId;

    Widget item(int n) => _SbButton(
      label: '$n',
      active: isCurrentBook && n == _c.selectedChapter,
      alignment: Alignment.center,
      onTap: () => _selectChapter(n),
    );

    if (kLazyLists) {
      return ListView.builder(
        controller: _chapterScroll,
        key: ValueKey('chapters-$_preBookId'),
        itemExtent: kRowHeight,
        itemCount: count,
        itemBuilder: (_, i) => item(i + 1),
      );
    }
    return SingleChildScrollView(
      controller: _chapterScroll,
      key: ValueKey('chapters-$_preBookId'),
      child: Column(
        children: [
          for (var n = 1; n <= count; n++)
            SizedBox(height: kRowHeight, child: item(n)),
        ],
      ),
    );
  }

  // ---- Testament buttons ----
  Widget _testamentBar() {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Expanded(
            child: _SbButton(
              label: 'OLD TESTAMENT',
              active: _isOt,
              alignment: Alignment.center,
              small: true,
              onTap: () => _setTestament(true),
            ),
          ),
          Expanded(
            child: _SbButton(
              label: 'NEW TESTAMENT',
              active: !_isOt,
              alignment: Alignment.center,
              small: true,
              onTap: () => _setTestament(false),
            ),
          ),
        ],
      ),
    );
  }

  void _center(ScrollController c, int index, {required bool animate}) {
    if (index < 0 || !c.hasClients) return;
    final pos = c.position;
    if (!pos.hasContentDimensions) return;

    final target =
        (index * kRowHeight - (pos.viewportDimension - kRowHeight) / 2).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );

    if (animate) {
      c.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      c.jumpTo(target);
    }
  }

  /// Scrolls the highlighted book and chapter to the middle of their columns.
  /// Runs after the frame so the lists have been rebuilt first.
  void _centerActive({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final books = _c.books.where((b) => b.isOldTestament == _isOt).toList();
      _center(
        _bookScroll,
        books.indexWhere((b) => b.id == _preBookId),
        animate: animate,
      );

      if (_preBookId == _c.selectedBookId) {
        _center(_chapterScroll, _c.selectedChapter - 1, animate: animate);
      }
    });
  }
}

// ---------------------------------------------------------------------------
// BUTTON (books, chapters, testaments)
// ---------------------------------------------------------------------------

class _SbButton extends StatelessWidget {
  const _SbButton({
    required this.label,
    required this.active,
    required this.onTap,
    required this.alignment,
    this.small = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Alignment alignment;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        // ACTIVE BUTTONS
        decoration: active
            ? BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    context.colorScheme.surfaceTint,
                    context.colorScheme.surfaceBright,
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: context.colorScheme.surfaceContainerLow,
                ),

                // innerButton shadow
                boxShadow: [
                  isDark
                      ? BoxShadow(
                          color: Colors.black54,
                          blurRadius: 10,
                          offset: const Offset(8, 0),
                          inset: true,
                        )
                      : BoxShadow(
                          color: Colors.black26,
                          blurRadius: 5,
                          offset: const Offset(4, 4),
                          inset: true,
                        ),
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 5,
                    offset: const Offset(0, -4),
                    inset: true,
                  ),
                ],
              )
            : null,

        child: InkWell(
          onTap: onTap,
          child: Container(
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: small ? 12 : 17,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
                color: active
                    ? Colors.white
                    : context.colorScheme.onSurfaceVariant,
                shadows: [
                  Shadow(
                    color: context.colorScheme.shadow,
                    blurRadius: 2,
                    offset: Offset(1, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VOTD BANNER
// ---------------------------------------------------------------------------

class _VotdBanner extends StatefulWidget {
  const _VotdBanner();

  @override
  State<_VotdBanner> createState() => _VotdBannerState();
}

class _VotdBannerState extends State<_VotdBanner>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  /// Motion time in seconds. It advances slower than real time while easing in.
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);

  Duration _last = Duration.zero;
  Timer? _startTimer;
  bool _motionEnabled = false;

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6)
        .clamp(0.0, 0.1)
        .toDouble();
    _last = elapsed;
    final ramp = (elapsed.inMicroseconds / 1e6 / kVotdEaseInSeconds)
        .clamp(0.0, 1.0)
        .toDouble();
    _seconds.value += dt * Curves.easeInOut.transform(ramp);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = kAnimateVotdImage && TickerMode.valuesOf(context).enabled;
    if (enabled == _motionEnabled) return;

    _motionEnabled = enabled;
    _startTimer?.cancel();
    if (!enabled) {
      _ticker.stop(); // _seconds keeps its value, so motion resumes in place
      return;
    }
    // Wait out the sidebar-open animation, then ease in from standstill.
    _startTimer = Timer(kVotdMotionStartDelay, () {
      if (!mounted || !_motionEnabled) return;
      _last = Duration.zero;
      if (!_ticker.isActive) _ticker.start();
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  Widget _motion(BuildContext context, Widget? child) {
    const tau = 2 * math.pi;
    final t = _seconds.value;
    final zoomMid = (kVotdZoomMin + kVotdZoomMax) / 2;
    final zoomAmp = (kVotdZoomMax - kVotdZoomMin) / 2;

    // At t = 0: minimum zoom, centered. Every curve turns around smoothly.
    final scale = zoomMid - zoomAmp * math.cos(tau * t / kVotdZoomPeriod);
    final pan = Offset(
      kVotdPanRadius.dx * math.sin(tau * t / kVotdPanXPeriod),
      kVotdPanRadius.dy * math.sin(tau * t / kVotdPanYPeriod),
    );

    return Transform.scale(
      scale: scale,
      alignment: kVotdZoomAlignment,
      child: FractionalTranslation(translation: pan, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final votd = context.watch<VotdController>();
    const fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB5651D), Color(0xFFF0C890)],
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        context.read<VotdController>().open();
        SidebarReveal.of(context).close();
      },
      // Keeps the banner's per-frame repaints from dirtying the whole sidebar.
      child: RepaintBoundary(
        child: SizedBox(
          height: kVotdBannerHeight,
          width: double.infinity,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedBuilder(
                  animation: _seconds,
                  builder: _motion,
                  child: RepaintBoundary(
                    child: Image.asset(
                      'assets/images/votd.webp',
                      fit: BoxFit.cover,
                      alignment: kVotdImageAlignment,
                      opacity: AlwaysStoppedAnimation(kVotdImageOpacity),
                      errorBuilder: (_, _, _) => fallback,
                    ),
                  ),
                ),
                // Own layer, so the text isn't re-rasterized every frame.
                RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: 360,
                        child: !votd.hasPick
                            ? const SizedBox.shrink()
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    votd.text,
                                    textAlign: TextAlign.center,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: _votdStyle,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    votd.reference,
                                    textAlign: TextAlign.center,
                                    style: _votdStyle.copyWith(fontSize: 15),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF555555), width: 4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _votdStyle = TextStyle(
  fontSize: 18,
  fontStyle: FontStyle.italic,
  fontWeight: FontWeight.w700,
  color: Color(0xFF444444),
  shadows: [
    Shadow(color: Colors.white70, blurRadius: 3, offset: Offset(-1, 1)),
    Shadow(color: Colors.white70, blurRadius: 3, offset: Offset(1, -1)),
  ],
);

// ---------------------------------------------------------------------------
// SWIPE DETECTOR (raw pointers, never competes with scrolling)
// ---------------------------------------------------------------------------

class _SwipeDetector extends StatefulWidget {
  const _SwipeDetector({
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.threshold = 60,
  });
  final Widget child;
  final VoidCallback? onSwipeLeft, onSwipeRight;
  final double threshold;

  @override
  State<_SwipeDetector> createState() => _SwipeDetectorState();
}

class _SwipeDetectorState extends State<_SwipeDetector> {
  final _pointers = <int>{};
  Offset? _start;
  bool _fired = false;

  void _end(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) _start = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (e) {
      _pointers.add(e.pointer);
      if (_pointers.length == 1) {
        _start = e.position;
        _fired = false;
      } else {
        _start = null;
      }
    },
    onPointerMove: (e) {
      if (_pointers.length != 1 || _start == null || _fired) return;
      final d = e.position - _start!;
      if (d.dx.abs() < widget.threshold || d.dx.abs() < d.dy.abs() * 2) return;
      _fired = true; // one action per drag
      (d.dx < 0 ? widget.onSwipeLeft : widget.onSwipeRight)?.call();
    },
    onPointerUp: _end,
    onPointerCancel: _end,
    child: widget.child,
  );
}
