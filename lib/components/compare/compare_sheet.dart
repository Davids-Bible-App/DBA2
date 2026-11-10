import 'package:dba2/components/compare/compare_colors.dart';
import 'package:flutter/material.dart';

import 'package:dba2/ui/translations/services/translation_catalog.dart';
import 'package:dba2/ui/translations/services/translation_store.dart';

import 'compare_controller.dart';

const double _kMinCard = 200; // Tauri: minmax(200px, 350px)
const double _kMaxCard = 350;
const double _kGap = 12;

/// Opens the compare page (full screen). Completes when it is closed.
Future<void> showCompareSheet(
  BuildContext context, {
  required TranslationStore store,
  required String startId,
  required String bookId,
  required int chapter,
  required String bookName,
  required List<int> verses,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true, // gives you the X button + slide-up animation
      builder: (_) => ComparePage(
        store: store,
        startId: startId,
        bookId: bookId,
        chapter: chapter,
        bookName: bookName,
        verses: verses,
      ),
    ),
  );
}

class ComparePage extends StatefulWidget {
  const ComparePage({
    super.key,
    required this.store,
    required this.startId,
    required this.bookId,
    required this.chapter,
    required this.bookName,
    required this.verses,
  });

  final TranslationStore store;
  final String startId;
  final String bookId;
  final int chapter;
  final String bookName;
  final List<int> verses;

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  late final CompareController _ctl = CompareController(
    store: widget.store,
    startId: widget.startId,
    bookId: widget.bookId,
    chapter: widget.chapter,
    bookName: widget.bookName,
    selectedVerses: widget.verses,
  )..init();

  bool _showEditions = false;

  /// Shared with the card list so the swipe code can ask "are we at the top?"
  final ScrollController _scroll = ScrollController();

  void _setPanel(bool open) {
    if (_showEditions != open) setState(() => _showEditions = open);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CompareColors.of(context);
    return Scaffold(
      backgroundColor: c.sheetBg,
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: ListenableBuilder(
          listenable: _ctl,
          builder: (_, _) => Text(_ctl.title),
        ),
        actions: [
          ListenableBuilder(
            listenable: _ctl,
            builder: (_, _) => TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: c.text),
              onPressed: () => setState(() => _showEditions = !_showEditions),
              icon: AnimatedRotation(
                turns: _showEditions ? 0 : 0.5,
                duration: const Duration(milliseconds: 250),
                child: const Icon(Icons.expand_less),
              ),
              label: Text('${_ctl.activeCount}/${_ctl.installed.length}'),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _EditionsPanel(ctl: _ctl, open: _showEditions),
          // Gestures sit BELOW the panel, so scrolling the edition list can
          // never count as a "close" swipe.
          Expanded(
            child: ListenableBuilder(
              listenable: _ctl,
              builder: (context, child) {
                final browsing = _ctl.mode == CompareMode.single;
                return _SwipeGestures(
                  atTop: () => !_scroll.hasClients || _scroll.offset <= 1,
                  onDown: () => _setPanel(true),
                  onUp: () => _setPanel(false),
                  onLeft: browsing ? _ctl.nextVerse : null,
                  onRight: browsing ? _ctl.prevVerse : null,
                  onMulti: () => Navigator.of(context).maybePop(),
                  child: child!, // built once, not on every verse change
                );
              },
              child: Column(
                children: [
                  _ModeBar(ctl: _ctl),
                  Expanded(
                    child: _CardGrid(ctl: _ctl, scroll: _scroll),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edition picker (replaces Editions.jsx)
// ---------------------------------------------------------------------------

class _EditionsPanel extends StatelessWidget {
  const _EditionsPanel({required this.ctl, required this.open});

  final CompareController ctl;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final c = CompareColors.of(context);

    // Material (not Container) so tap ripples are drawn on top of the panel
    // colour instead of being hidden under it.
    final panel = Material(
      color: c.panelBg,
      child: ListenableBuilder(
        listenable: ctl,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: c.text),
                  onPressed: ctl.selectAll,
                  child: const Text('ALL'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: c.text),
                  onPressed: ctl.selectNone,
                  child: const Text('NONE'),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 176),
              child: ListView.builder(
                shrinkWrap: true,
                itemExtent: 44, // fixed height = cheaper to lay out
                itemCount: ctl.installed.length,
                itemBuilder: (context, i) {
                  final id = ctl.installed[i];
                  return CheckboxListTile(
                    dense: true,
                    activeColor: c.control,
                    checkColor: c.onControl,
                    side: BorderSide(color: c.text, width: 2),
                    value: ctl.isActive(id),
                    onChanged: (_) => ctl.toggle(id),
                    title: Text(
                      '${translationFor(id).abbr}  \u00b7  $id',
                      style: TextStyle(color: c.text),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: c.cardBorder),
          ],
        ),
      ),
    );

    // t runs 0 -> 1 on open and 1 -> 0 on close. The panel stays on screen
    // the whole time and is just revealed/hidden by a shrinking window
    // (heightFactor), so closing animates exactly like opening.
    // At t == 0 nothing is built at all, so a closed panel costs nothing.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: open ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: panel, // built once, reused on every animation frame
      builder: (context, t, child) {
        if (t == 0) return const SizedBox(width: double.infinity);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            child: child,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Mode switch + verse pager
// ---------------------------------------------------------------------------

class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.ctl});

  final CompareController ctl;

  @override
  Widget build(BuildContext context) {
    final c = CompareColors.of(context);
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          children: [
            SegmentedButton<CompareMode>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                foregroundColor: c.text,
                selectedForegroundColor: c.onControl,
                selectedBackgroundColor: c.control,
                side: BorderSide(color: c.cardBorder),
              ),
              segments: const [
                ButtonSegment(
                  value: CompareMode.selected,
                  label: Text('Selected'),
                ),
                ButtonSegment(
                  value: CompareMode.single,
                  label: Text('Browse'),
                ),
              ],
              selected: {ctl.mode},
              onSelectionChanged: (s) => ctl.setMode(s.first),
            ),
            if (ctl.mode == CompareMode.single)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    style: IconButton.styleFrom(
                      foregroundColor: c.text,
                      disabledForegroundColor: c.text.withValues(alpha: 0.35),
                    ),
                    onPressed: ctl.canPrev ? ctl.prevVerse : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    'Verse ${ctl.verse} of ${ctl.verseCount}',
                    style: TextStyle(color: c.text),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      foregroundColor: c.text,
                      disabledForegroundColor: c.text.withValues(alpha: 0.35),
                    ),
                    onPressed: ctl.canNext ? ctl.nextVerse : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The cards (replaces the CSS grid)
// ---------------------------------------------------------------------------

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.ctl, required this.scroll});

  final CompareController ctl;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final c = CompareColors.of(context);
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final ids = ctl.activeIds;
        if (ids.isEmpty) {
          return Center(
            child: Text(
              'Pick at least one edition.',
              style: TextStyle(color: c.text),
            ),
          );
        }
        final verses = ctl.mode == CompareMode.single
            ? [ctl.verse]
            : ctl.selectedVerses;
        final reference = ctl.referenceFor(verses); // same for every card

        return LayoutBuilder(
          builder: (context, box) {
            // Same idea as auto-fit: as many columns as fit at min width.
            final cols = ((box.maxWidth - _kGap) / (_kMinCard + _kGap))
                .floor()
                .clamp(1, 6);
            final rows = (ids.length / cols).ceil();

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: cols * _kMaxCard + (cols + 1) * _kGap,
                ),
                // Lazy: only the rows on screen are built.
                child: ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(_kGap),
                  itemCount: rows,
                  itemBuilder: (context, row) {
                    final start = row * cols;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: _kGap),
                      // IntrinsicHeight: cards in a row share one height
                      // (what `subgrid` did in your CSS).
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < cols; i++) ...[
                              if (i > 0) const SizedBox(width: _kGap),
                              Expanded(
                                child: start + i < ids.length
                                    ? _EditionCard(
                                        id: ids[start + i],
                                        data: ctl.dataFor(ids[start + i]),
                                        verses: verses,
                                        reference: reference,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EditionCard extends StatelessWidget {
  const _EditionCard({
    required this.id,
    required this.data,
    required this.verses,
    required this.reference,
  });

  final String id;
  final EditionText? data; // null = still loading
  final List<int> verses;
  final String reference;

  @override
  Widget build(BuildContext context) {
    final c = CompareColors.of(context);
    final titleStyle = Theme.of(context).textTheme.titleSmall;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: version + reference, e.g.  ESV  ·  John 7:3-5
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: translationFor(id).abbr,
                  style: TextStyle(
                    color: c.versionColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: '  ·  $reference',
                  style: TextStyle(color: c.referenceColor),
                ),
              ],
            ),
            style: titleStyle,
          ),
          Divider(height: 16, color: c.cardBorder),
          _body(c),
        ],
      ),
    );
  }

  Widget _body(CompareColors c) {
    final d = data;
    if (d == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.control),
          ),
        ),
      );
    }

    // Some translations skip verses (or lack the book): only show what exists.
    final present = [
      for (final v in verses)
        if (d.verses[v] != null) v,
    ];
    if (present.isEmpty) {
      return Text(
        'Not available in this translation',
        style: TextStyle(fontStyle: FontStyle.italic, color: c.referenceColor),
      );
    }

    final showNumbers = verses.length > 1;
    final numStyle = TextStyle(
      color: c.verseNoColor,
      fontWeight: FontWeight.bold,
      fontSize: 12,
    );

    // One Text.rich for the whole card = one paragraph to lay out.
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < present.length; i++) ...[
            if (showNumbers) TextSpan(text: '${present[i]}. ', style: numStyle),
            TextSpan(text: d.verses[present[i]]),
            if (i < present.length - 1) const TextSpan(text: '\n\n'),
          ],
        ],
      ),
      style: TextStyle(color: c.text, height: 1.4),
    );
  }
}

// ---------------------------------------------------------------------------
// Swipe gestures
//
// Uses a Listener (raw pointer events) instead of GestureDetector. A Listener
// never joins the gesture arena, so it cannot steal touches from the card
// list, buttons or the segmented control: scrolling and taps behave exactly
// as before, we just watch where fingers travel.
// ---------------------------------------------------------------------------

class _SwipeGestures extends StatefulWidget {
  const _SwipeGestures({
    required this.child,
    this.atTop,
    this.onDown,
    this.onUp,
    this.onLeft,
    this.onRight,
    this.onMulti,
  });

  final Widget child;

  /// Is the card list scrolled to the top? Swipe-down only opens the panel
  /// then, so scrolling back up through long cards never pops it open.
  final bool Function()? atTop;

  /// null = that swipe is ignored (e.g. left/right outside Browse mode).
  final VoidCallback? onDown, onUp, onLeft, onRight, onMulti;

  @override
  State<_SwipeGestures> createState() => _SwipeGesturesState();
}

class _SwipeGesturesState extends State<_SwipeGestures> {
  static const double _horizontalDist = 64; // px before a sideways swipe counts
  static const double _verticalDist = 56;
  static const double _multiDist = 56; // every finger must travel this far
  static const double _axisBias = 1.5; // mostly-straight swipes only

  final Map<int, Offset> _start = {};
  final Map<int, Offset> _now = {};
  int _maxFingers = 0;
  bool _fired = false;
  bool _startedAtTop = true;

  void _down(PointerDownEvent e) {
    if (_start.isEmpty) {
      // A fresh gesture begins.
      _fired = false;
      _maxFingers = 0;
      _startedAtTop = widget.atTop?.call() ?? true;
    }
    _start[e.pointer] = e.position;
    _now[e.pointer] = e.position;
    if (_start.length > _maxFingers) _maxFingers = _start.length;
  }

  void _move(PointerMoveEvent e) {
    if (_fired || !_now.containsKey(e.pointer)) return;
    _now[e.pointer] = e.position;

    if (_maxFingers >= 2) {
      _checkMultiFinger();
      return;
    }

    final d = e.position - _start[e.pointer]!;
    final ax = d.dx.abs();
    final ay = d.dy.abs();

    if (ax >= _horizontalDist && ax > ay * _axisBias) {
      _fire(d.dx < 0 ? widget.onLeft : widget.onRight);
    } else if (ay >= _verticalDist && ay > ax * _axisBias) {
      _fire(d.dy > 0 ? (_startedAtTop ? widget.onDown : null) : widget.onUp);
    }
  }

  /// All fingers must travel far, and in the same direction
  /// (so a pinch or spread is not mistaken for a swipe).
  void _checkMultiFinger() {
    if (_now.length < 2) return;
    final deltas = [for (final id in _now.keys) _now[id]! - _start[id]!];
    final first = deltas.first;
    for (final d in deltas) {
      if (d.distance < _multiDist) return;
      if (d.dx * first.dx + d.dy * first.dy <= 0) return;
    }
    _fire(widget.onMulti);
  }

  void _fire(VoidCallback? action) {
    if (action == null) return;
    _fired = true; // once per gesture
    action();
  }

  void _up(PointerEvent e) {
    _start.remove(e.pointer);
    _now.remove(e.pointer);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent, // also catch empty space
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: widget.child,
    );
  }
}
