import 'dart:async';
import 'dart:math' as math;

import 'package:dba2/storage/profile/profile.dart';
import 'package:dba2/storage/profile/profile_settings.dart';
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/ui/widgets/draggable_snap_sheet.dart';
import 'package:dba2/ui/translations/services/translation_store.dart';
import 'package:dba2/ui/widgets/uni_verse.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'bible_search_controller.dart';
import 'search_logic.dart';
import 'search_theme.dart';
import 'send_to_topic.dart';

typedef SendVerses = void Function(List<SearchHit> verses);

/// Compact buttons: your global button theme uses 48px-high pills with 24px
/// padding, which is far too big inside a result list.
const _compact = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size.zero),
  padding: WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  ),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.compact,
);

/// The search body never lays out shorter than this. When the sheet is
/// smaller, the bottom is simply clipped instead of overflowing.
const double _kMinBodyHeight = 260;

/// Below this width the labels move above their buttons.
const double _kStackLabelsBelow = 500;

/// true = labels always sit beside their buttons (never stacked), even on
/// small screens. Set to false to bring back the width-based stacking,
/// e.g. if a third button group is added later.
const bool _kForceInlineLabels = true;
const String _kSearchKey = 'search';

/// Fingers must spread to this multiple of their starting distance to open
/// the viewer. 1.3 = 30% further apart. Higher = needs a bigger spread.
const double _kSpreadToOpen = 1.3;

/// Search sheet positions. [top] is the status bar height: it is added to
/// the px min because SheetSafePadding spends it inside the content.
SnapPositions _searchPositions(double top) => SnapPositions.sized(
  min: SheetSize.px(148 + top),
  max: const SheetSize.percent(90),
  starting: const SheetSize.percent(90),
);

// ---------------------------------------------------------------------------
// SESSION: one controller for the whole app run, so closing the sheet does
// NOT throw the results away.
// ---------------------------------------------------------------------------

BibleSearchController? _session;

BibleSearchController _sessionFor(
  BibleController bible,
  TranslationStore store,
  ProfileRepository profile,
  ProfileSettings settings,
) {
  final s = _session;
  if (s != null && identical(s.bible, bible) && identical(s.store, store)) {
    return s;
  }
  s?.dispose();
  return _session = BibleSearchController(
    bible: bible,
    store: store,
    profile: profile,
    settings: settings,
  );
}

/// Wipes the remembered search (query, results, selection).
void resetSearchSession() => _session?.clearSearch();

/// Re-reads history + highlight setting (used after a profile import).
Future<void> reloadSearchSession() async => _session?.reloadFromProfile();

/// Opens the search as a TOP sheet. Call from any button:
///   IconButton(icon: const Icon(Icons.search), onPressed: () => showSearchSheet(context))
///
/// [onSendToEditor]: hidden when null.
/// [onSendToTopic]: null = built-in Topics flow. Do NOT pass an empty stub.
Future<void> showSearchSheet(
  BuildContext context, {
  SendVerses? onSendToEditor,
  SendVerses? onSendToTopic,
}) async {
  final bible = context.read<BibleController>();
  final store = context.read<TranslationStore>();
  final profile = context.read<ProfileRepository>();
  final settings = context.read<ProfileSettings>();
  final controller = _sessionFor(bible, store, profile, settings)
    ..dropStaleResults();
  final top = MediaQuery.paddingOf(context).top; // 0 on Windows

  await showModalSnapSheet<void>(
    context: context,
    sheetKey: _kSearchKey,
    positions: _searchPositions(top),
    scrimlessAtMin: true,
    unlockAtMin: true,
    setTop: true,
    resizeContent: true,
    builder: (_) => SearchSheet(
      controller: controller,
      onSendToTopic: onSendToTopic,
      onSendToEditor: onSendToEditor,
    ),
  );
}

class SearchSheet extends StatefulWidget {
  const SearchSheet({
    super.key,
    required this.controller,
    this.onSendToEditor,
    this.onSendToTopic,
  });

  final BibleSearchController controller;
  final SendVerses? onSendToEditor;
  final SendVerses? onSendToTopic;

  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  BibleSearchController get _c => widget.controller;
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  double _drag = 0;
  late int _lastEpoch;
  Timer? _armTimer;
  bool _armed = false; // false while the sheet is still opening

  // Pinch tracking (same idea as the viewer's pinch-to-close).
  final _pts = <int, Offset>{};
  double? _startDist;
  bool _pinching = false;

  double _dist() => (_pts.values.first - _pts.values.last).distance;

  void _pinchEnd(PointerEvent e) {
    _pts.remove(e.pointer);
    _startDist = null;
    if (_pts.isEmpty) _pinching = false;
  }

  void _openUniVerse() {
    if (_c.selectedCount == 0) return;
    final items = [
      for (final h in _c.selectedSorted)
        UniVerseItem(
          citation:
              '${_c.bookName(h.bookId)} ${h.chapter}:${h.verse} '
              '(${_c.bible.edition})',
          text: h.plainText, // plainText: no <mark> tags
        ),
    ];
    context.read<ValueNotifier<List<UniVerseItem>?>>().value = items;
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _lastEpoch = _c.resultsEpoch;
    // Focus changes during the opening animation (autofocus) are ignored.
    _armTimer = Timer(const Duration(milliseconds: 400), () => _armed = true);
    // Restore where the user left off.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(
        math.min(_c.scrollOffset, _scroll.position.maxScrollExtent),
      );
    });
  }

  void _onFocus() {
    setState(() {}); // show / hide the history dropdown
    if (_focus.hasFocus) _expandIfMin();
  }

  void _expandIfMin() {
    if (!_armed) return;
    if (snapSheetPosition(_kSearchKey) == SnapPoint.min) {
      snapSheetTo(_kSearchKey, SnapPoint.max);
    }
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _scroll.dispose();
    // NOTE: the controller is NOT disposed here: it lives in _session.
    super.dispose();
  }

  Future<void> _run([int page = 0]) async {
    await _c.search(page: page);
    if (!mounted) return;
    // Close the keyboard on results; keep it (and the dropdown) on "no results".
    if (_c.total > 0) {
      _focus.unfocus();
    } else {
      _focus.requestFocus();
    }
  }

  void _close() => Navigator.of(context).pop();

  void _goTo(SearchHit h) {
    _focus.unfocus();
    final bible = _c.bible;
    _close();
    bible.goTo(h.bookId, h.chapter, verse: h.verse);
  }

  void _send(SendVerses? cb) {
    if (cb == null || _c.selectedCount == 0) return;
    final verses = _c.selectedSorted;
    _c.clearSelection();
    _close();
    cb(verses);
  }

  /// Built-in Topics flow. The dialog opens ON TOP of this sheet using the
  /// sheet's own (definitely mounted) context; the sheet closes only after a
  /// successful save. Cancel keeps the selection.
  Future<void> _sendToTopic() async {
    if (_c.selectedCount == 0) return;
    final verses = _c.selectedSorted;
    _focus.unfocus();
    try {
      final saved = await sendHitsToTopic(context, verses);
      if (!mounted || !saved) return;
      _c.clearSelection();
      _close();
    } catch (e, st) {
      debugPrint('Send to topic failed: $e\n$st');
      if (mounted) _c.flash('Could not add to topic: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = SearchRefTheme.of(context);
    return SheetSafePadding(
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final body = _body(theme, t); // built once per notification
          return LayoutBuilder(
            builder: (context, box) {
              final h = math.max(box.maxHeight, _kMinBodyHeight);
              return ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: h,
                  maxHeight: h,
                  child: body,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _body(ThemeData theme, SearchRefTheme t) {
    // New result set arrived -> start at the top.
    if (_lastEpoch != _c.resultsEpoch) {
      _lastEpoch = _c.resultsEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }

    final showHistory =
        _focus.hasFocus && (_c.history.isNotEmpty || _c.noResults);
    final showPaging = !_c.isReference && _c.total > 5;

    return Column(
      children: [
        _controls(theme, t),
        const SizedBox(height: 8),
        _inputField(t),
        SizedBox(
          height: 3,
          child: _c.loading
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
        _status(theme, t),
        Expanded(
          child: Stack(
            children: [
              _results(t),
              if (showHistory)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _historyPanel(t),
                ),
            ],
          ),
        ),
        if (showPaging) _paging(theme, t),
      ],
    );
  }

  // ---- scope + highlight --------------------------------------------------

  Widget _controls(ThemeData theme, SearchRefTheme t) {
    final label = theme.textTheme.labelSmall?.copyWith(
      color: t.mutedText,
      fontSize: 10,
    );

    const segStyle = ButtonStyle(
      visualDensity: VisualDensity(horizontal: -4, vertical: -4),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: WidgetStatePropertyAll(Size(0, 26)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
      textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
    );

    // One label + its buttons, side by side or stacked.
    Widget group(String text, Widget buttons, bool stacked) {
      final lbl = Text(text, style: label);
      return stacked
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [lbl, const SizedBox(height: 2), buttons],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [lbl, const SizedBox(width: 6), buttons],
            );
    }

    return LayoutBuilder(
      builder: (context, box) {
        final stacked =
            !_kForceInlineLabels && box.maxWidth < _kStackLabelsBelow;
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: stacked ? 12 : 16,
          runSpacing: 6,
          children: [
            group(
              'Scope:',
              SegmentedButton<String>(
                style: segStyle,
                showSelectedIcon: false,
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: 'OT', label: Text('OT')),
                  ButtonSegment(value: 'NT', label: Text('NT')),
                ],
                selected: {if (_c.scope != null) _c.scope!},
                onSelectionChanged: (s) =>
                    _c.setScope(s.isEmpty ? null : s.first),
              ),
              stacked,
            ),
            group(
              'Highlight:',
              SegmentedButton<bool>(
                style: segStyle,
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('On')),
                  ButtonSegment(value: false, label: Text('Off')),
                ],
                selected: {_c.highlightOn},
                onSelectionChanged: (s) => _c.setHighlight(s.first),
              ),
              stacked,
            ),
          ],
        );
      },
    );
  }

  // ---- text box -----------------------------------------------------------
  Widget _inputField(SearchRefTheme t) {
    return TextField(
      controller: _c.input,
      focusNode: _focus,
      // Only pop the keyboard when there is nothing to come back to.
      autofocus: _c.hits.isEmpty,
      onTap: _expandIfMin,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _run(),
      onTapOutside: (_) => _focus.unfocus(),
      decoration: InputDecoration(
        hintText: 'e.g. John1:, jhn.1:1,3,4,2-5, jn2-4,5:2,1:1',
        hintStyle: TextStyle(color: t.mutedText, fontSize: 13),
        filled: true,
        fillColor: t.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide.none,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _c.input,
          builder: (context, v, _) => v.text.isEmpty
              ? const SizedBox.shrink()
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _c.clearSearch();
                        _focus.requestFocus();
                      },
                    ),
                    IconButton(
                      tooltip: 'Search',
                      icon: const Icon(Icons.keyboard_return, size: 18),
                      onPressed: () => _run(),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ---- total + "send to" bar ---------------------------------------------
  Widget _status(ThemeData theme, SearchRefTheme t) {
    final small = theme.textTheme.bodySmall?.copyWith(color: t.mutedText);
    final n = _c.selectedCount;

    return Column(
      children: [
        if (_c.error != null)
          Text(_c.error!, style: small?.copyWith(color: t.noResultsColor)),
        if (_c.total > 0) Text('Total Results: | ${_c.total} |', style: small),
        if (_c.flashMessage != null)
          Text(
            _c.flashMessage!,
            style: small?.copyWith(color: theme.colorScheme.primary),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: n == 0
              ? const SizedBox(width: double.infinity)
              : Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Text('Send $n verses to:', style: small),
                    if (widget.onSendToEditor != null)
                      TextButton(
                        style: _compact,
                        onPressed: () => _send(widget.onSendToEditor),
                        child: const Text('Editor'),
                      ),
                    TextButton(
                      style: _compact,
                      onPressed: widget.onSendToTopic != null
                          ? () => _send(widget.onSendToTopic)
                          : _sendToTopic,
                      child: const Text('Topic'),
                    ),
                    TextButton(
                      style: _compact,
                      onPressed: _c.copySelection,
                      child: const Text('Clipboard'),
                    ),
                    // TextButton(
                    //   style: _compact,
                    //   onPressed: _openUniVerse,
                    //   child: const Text('Viewer'),
                    // ),
                  ],
                ),
        ),
      ],
    );
  }

  // ---- history dropdown ---------------------------------------------------
  Widget _historyPanel(SearchRefTheme t) {
    // TextFieldTapRegion: taps in here are NOT "outside" the text field,
    // so the field keeps focus and the dropdown doesn't vanish mid-tap.
    return TextFieldTapRegion(
      child: Material(
        color: t.panelBackground,
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 190),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              if (_c.noResults)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: Text(
                      'Sorry, no results found',
                      style: TextStyle(color: t.noResultsColor),
                    ),
                  ),
                ),
              for (final item in _c.history)
                InkWell(
                  onTap: () {
                    _c.input.text = item;
                    _run();
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 10,
                          ),
                          child: Text(
                            item,
                            style: TextStyle(color: t.mutedText),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove from history',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => _c.removeFromHistory(item),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- results (swipe left/right = next/prev page) ------------------------
  Widget _results(SearchRefTheme t) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _pts[e.pointer] = e.position;
        if (_pts.length == 2) {
          _startDist = _dist();
          _pinching = true;
        }
      },
      onPointerMove: (e) {
        if (!_pts.containsKey(e.pointer)) return;
        _pts[e.pointer] = e.position;
        final s = _startDist;
        if (_pts.length == 2 &&
            s != null &&
            s > 0 &&
            _dist() / s > _kSpreadToOpen) {
          _startDist = null; // fire once per gesture
          _openUniVerse();
        }
      },
      onPointerUp: _pinchEnd,
      onPointerCancel: _pinchEnd,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _drag = 0,
        onHorizontalDragUpdate: (d) => _drag += d.delta.dx,
        onHorizontalDragCancel: () => _drag = 0,
        onHorizontalDragEnd: (_) {
          if (!_pinching && !_c.isReference) {
            if (_drag > 50) _c.prevPage();
            if (_drag < -50) _c.nextPage();
          }
          _drag = 0;
        },
        // Remember the scroll position so reopening resumes here.
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.depth == 0) _c.scrollOffset = n.metrics.pixels;
            return false;
          },
          child: ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.only(top: 8),
            itemCount: _c.hits.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, thickness: 1, color: t.dividerColor),
            itemBuilder: (context, i) {
              final hit = _c.hits[i];
              return _ResultTile(
                hit: hit,
                label:
                    '${_c.bookName(hit.bookId)} ${hit.chapter}:${hit.verse} '
                    '(${_c.bible.edition})',
                selected: _c.isSelected(hit),
                highlightOn: _c.highlightOn,
                onTap: () => _c.toggle(hit),
                onGo: () => _goTo(hit),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---- pagination ---------------------------------------------------------
  Widget _paging(ThemeData theme, SearchRefTheme t) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.pagingBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          TextButton(
            style: _compact,
            onPressed: _c.page > 0 ? _c.prevPage : null,
            child: const Text('Prev'),
          ),
          _PageIndicator(
            page: _c.page,
            totalPages: _c.totalPages,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            onGo: _c.gotoPage,
          ),
          TextButton(
            style: _compact,
            onPressed: _c.page < _c.totalPages - 1 ? _c.nextPage : null,
            child: const Text('Next'),
          ),
          DropdownButton<int>(
            value: _c.perPage,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            items: [
              for (final n in const [50, 100, 200, 2000])
                DropdownMenuItem(value: n, child: Text('$n per page')),
            ],
            onChanged: (v) {
              if (v != null) _c.setPerPage(v);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ONE RESULT
// ---------------------------------------------------------------------------

class _ResultTile extends StatefulWidget {
  const _ResultTile({
    required this.hit,
    required this.label,
    required this.selected,
    required this.highlightOn,
    required this.onTap,
    required this.onGo,
  });

  final SearchHit hit;
  final String label;
  final bool selected;
  final bool highlightOn;
  final VoidCallback onTap;
  final VoidCallback onGo;

  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile> {
  // Parsed once, and again only if the verse text changes.
  late var _segments = parseSegments(widget.hit.text);

  @override
  void didUpdateWidget(_ResultTile old) {
    super.didUpdateWidget(old);
    if (old.hit.text != widget.hit.text) {
      _segments = parseSegments(widget.hit.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SearchRefTheme.of(context);

    return Material(
      color: widget.selected ? t.selectedTint : Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(widget.label, style: t.refStyle)),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: _compact,
                    onPressed: widget.onGo,
                    child: const Text('Go to Verse ↣'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _verseText(t),
            ],
          ),
        ),
      ),
    );
  }

  /// <mark> chips: rounded gold background, like your CSS `mark` rule.
  Widget _verseText(SearchRefTheme t) {
    return Text.rich(
      TextSpan(
        style: t.verseStyle,
        children: [
          for (final s in _segments)
            if (s.marked && widget.highlightOn)
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: t.markBackground,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    s.text,
                    style: t.verseStyle.copyWith(color: t.markForeground),
                  ),
                ),
              )
            else
              TextSpan(text: s.text),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "[ Page 1 of 260 ]" — tap to type a page number
// ---------------------------------------------------------------------------

class _PageIndicator extends StatefulWidget {
  const _PageIndicator({
    required this.page,
    required this.totalPages,
    required this.onGo,
    this.style,
  });

  final int page;
  final int totalPages;
  final TextStyle? style;
  final void Function(int zeroBasedPage) onGo;

  @override
  State<_PageIndicator> createState() => _PageIndicatorState();
}

class _PageIndicatorState extends State<_PageIndicator> {
  bool _editing = false;
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _start() {
    _text.text = '${widget.page + 1}';
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
    setState(() => _editing = true);
  }

  void _submit() {
    if (!_editing) return; // onSubmitted + onTapOutside can both fire
    setState(() => _editing = false);
    final n = int.tryParse(_text.text);
    if (n != null && n > 0) {
      widget.onGo(math.min(n, widget.totalPages) - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return InkWell(
        onTap: _start,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            '[ Page ${widget.page + 1} of ${widget.totalPages} ]',
            style: widget.style,
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('[ Page ', style: widget.style),
        SizedBox(
          width: 48,
          child: TextField(
            controller: _text,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: widget.style,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 4),
            ),
            onSubmitted: (_) => _submit(),
            onTapOutside: (_) => _submit(),
          ),
        ),
        Text(' of ${widget.totalPages} ]', style: widget.style),
      ],
    );
  }
}
