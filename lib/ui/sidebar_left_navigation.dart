// lib\ui\sidebar_left_navigation.dart

import 'dart:math' as math;

import 'package:dba2/core.dart' hide BoxShadow, BoxDecoration;
import 'package:flutter_inset_shadow/flutter_inset_shadow.dart';

import '../models/bible_book.dart';
import '../controllers/bible_controller.dart';
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
const Duration kVotdMotionDuration = Duration(seconds: 18);
const Duration kVotdMotionStartDelay = Duration(seconds: 1);
const Curve kVotdMotionCurve = Curves.linear;
const double kVotdZoomInFraction = 0.65;
const bool kVotdRandomizePan = true;
const double kVotdZoomStart = 1.2;
const double kVotdZoomEnd = 1.35;
const Offset kVotdPanStart = Offset(-0.05, 0.04);
const Offset kVotdPanEnd = Offset(0.05, -0.04);
const List<Offset> kVotdPanDestinations = [
  Offset(-0.04, -0.03),
  Offset(-0.04, 0.03),
  Offset(0.04, -0.03),
  Offset(0.04, 0.03),
];
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

  final ScrollController _bookScroll = ScrollController();
  final ScrollController _chapterScroll = ScrollController();

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
    _bookScroll.dispose();
    _chapterScroll.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final before = _syncedBookId;
    setState(_applyBook);
    // If the book changed, the lists were rebuilt from the top, so jump
    // instead of animating across the whole list.
    _centerActive(animate: before == _syncedBookId);
  }

  // When the app's current book changes (database loaded, Next/Previous,
  // or a chapter picked here), follow it.
  void _applyBook() {
    final book = _c.currentBook;
    if (book == null || book.id == _syncedBookId) return;
    _syncedBookId = book.id;
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
      final first = _c.books.where((b) => b.isOldTestament == ot);
      if (first.isNotEmpty) _preBookId = first.first.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colorScheme.secondary,
      child: SafeArea(
        child: Column(
          children: [
            const _VotdBanner(),
            if (kShowVotdAnimation) const _VotdStrip(),
            const SizedBox(
              height: 5.0,
            ),
            Expanded(
              child: Stack(
                children: [
                  Row(
                    children: [
                      Expanded(child: _bookList()),
                      Container(
                        width: 2,
                        color: context.colorScheme.primary,
                      ),
                      SizedBox(width: 70, child: _chapterList()),
                    ],
                  ),
                ],
              ),
            ),
            _testamentBar(),
          ],
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
  final math.Random _random = math.Random();
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: kVotdMotionDuration,
  );
  late Animation<double> _scale;
  late Animation<Offset> _pan;
  Offset _panStart = kVotdPanStart;
  Offset _panEnd = kVotdPanEnd;

  void _configureMotion() {
    _scale = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: kVotdZoomStart,
          end: kVotdZoomEnd,
        ).chain(CurveTween(curve: kVotdMotionCurve)),
        weight: kVotdZoomInFraction,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: kVotdZoomEnd,
          end: kVotdZoomStart,
        ).chain(CurveTween(curve: kVotdMotionCurve)),
        weight: 1 - kVotdZoomInFraction,
      ),
    ]).animate(_c);
    _pan = Tween<Offset>(
      begin: _panStart,
      end: _panEnd,
    ).chain(CurveTween(curve: kVotdMotionCurve)).animate(_c);
  }

  void _onMotionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;

    _panStart = _panEnd;
    if (kVotdRandomizePan) {
      final destinations = kVotdPanDestinations
          .where((destination) => destination != _panStart)
          .toList(growable: false);
      if (destinations.isNotEmpty) {
        _panEnd = destinations[_random.nextInt(destinations.length)];
      }
    } else {
      _panEnd = _panEnd == kVotdPanEnd ? kVotdPanStart : kVotdPanEnd;
    }

    _configureMotion();
    _c.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _configureMotion();
    _c.addStatusListener(_onMotionStatus);
    if (kAnimateVotdImage) {
      Future.delayed(kVotdMotionStartDelay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB5651D), Color(0xFFF0C890)],
        ),
      ),
    );

    return SizedBox(
      height: kVotdBannerHeight,
      width: double.infinity,
      child: SizedBox(
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _c,
                child: RepaintBoundary(
                  child: Image.asset(
                    'assets/images/votd.webp',
                    fit: BoxFit.cover,
                    alignment: kVotdImageAlignment,
                    opacity: AlwaysStoppedAnimation(kVotdImageOpacity),
                    errorBuilder: (_, _, _) => fallback,
                  ),
                ),
                builder: (context, child) => Transform.scale(
                  scale: _scale.value,
                  alignment: kVotdZoomAlignment,
                  child: FractionalTranslation(
                    translation: _pan.value,
                    child: child,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 360,
                    child: Text(
                      'Wherefore laying aside all malice, and all guile, and '
                      'hypocrisies, and envies, and all evil speakings, '
                      '1 Peter 2:1',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF444444),
                        shadows: [
                          Shadow(
                            color: Colors.white70,
                            blurRadius: 3,
                            offset: Offset(-1, 1),
                          ),
                          Shadow(
                            color: Colors.white70,
                            blurRadius: 3,
                            offset: Offset(1, -1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF555555), width: 4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OPTIONAL ALWAYS-RUNNING ANIMATION UNDER THE BANNER
// ---------------------------------------------------------------------------

class _VotdStrip extends StatefulWidget {
  const _VotdStrip();

  @override
  State<_VotdStrip> createState() => _VotdStripState();
}

class _VotdStripState extends State<_VotdStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final center = _c.value * 1.4 - 0.2;
        double s(double v) => v.clamp(0.0, 1.0);
        return Container(
          height: 6,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0),
                color,
                color.withValues(alpha: 0),
              ],
              stops: [s(center - 0.25), s(center), s(center + 0.25)],
            ),
          ),
        );
      },
    );
  }
}
