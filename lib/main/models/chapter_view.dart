import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:dba2/core.dart';
import 'package:dba2/storage/shared_state.dart';
import 'package:dba2/ui/widgets/verse_goto.dart';
import 'package:flutter/gestures.dart';

import 'chapter_model.dart';
import '../../ui/controlbox/verse_selection.dart';
import '../../ui/extras/paper_overlay.dart';

// ---------------------------------------------------------------------------
// LOOK TUNING (the CSS variables and magic numbers live here)
// ---------------------------------------------------------------------------

const double kFontSize = 18;
const double kLineHeight = 1.54; // your CSS: line-height / font-size
const double kContentMaxWidth = 720; // text column never gets wider than this
const double kSidePadding = 44; // left/right margin of the text (Tauri is ~50)
const double kTopPadding = 8;
const double kBottomPadding = 320; // room to scroll past the end

/// true  = chapter title stays pinned at the top while scrolling
/// false = title scrolls away with the text (old behaviour)
const bool kStickyHeader = true;
const double kHeaderHeight = 20; // height of the title bar once pinned
const double kHeaderTopGap = 35; // space above the title at rest
const double kHeaderBottomGap = 35; // space between title and first verse

// Verse selection / highlight look
const double kSelectBleed = 20; // selection bar extends this far past the text
final Color kSelectColor = Colors.grey[500]!.withValues(alpha: 0.4);
const Duration kDoubleClickWindow = Duration(milliseconds: 350);

/// true  = highlights show as a coloured bar on the left edge of the verse
///         (your list.use-sidelights)
/// false = highlights colour the whole verse background (use-highlights)
const bool kSideLights = false;
const double kSideLightWidth = 6;

// const Color kVerseNoColor = Color(0xFFD4A82A); // --verseNo (also the cap)
// const Color kJesusColor = Color(0xFFE57373); // --wordsOfJesus
// const Color kHebrewColor = Color(0xFF6495ED); // CornflowerBlue

// Drop cap
const String kLeafAsset = 'assets/images/leaves.webp';
const double kCapScale = 1.9; // cap font size = line height x this
const double kBaselineFrac =
    0.74; // line 1 baseline, as a fraction of the line box
const double kCapTopRoom = 6; // extra room above the cap for the leaf
const double kCapGap = 4; // space between the cap and the text
const double kLeafScale = 2.2; // leaf width = line height x this
const Offset kLeafOffset = Offset(
  -20,
  -28,
); // leaf position relative to the cap's top-left
const double kCapOutline = 3; // black outline thickness (stroke width)

// CrossRef Symbol
const String kCrossRefSymbol = '※';

// ---------------------------------------------------------------------------
// CHAPTER VIEW
// ---------------------------------------------------------------------------

class ChapterView extends StatelessWidget {
  const ChapterView({
    super.key,
    required this.chapter,
    required this.headerText,
    required this.translationId,
    required this.edition,
    required this.bookId,
    required this.chapterNumber,
    required this.selection,
    required this.highlights,
    required this.scrollController,
    this.headerItalic = false,
    this.fontSize = kFontSize,
    this.stickyHeader = kStickyHeader,
    // this.verseScroll,
    this.verseGoto,
    this.notesListenable,
    this.noteFor,
    this.onEditNote,
    this.crossRefVerses = const {},
    this.onCrossRef,
  });

  final ChapterData chapter;
  final String headerText;
  final bool headerItalic;
  final double fontSize;
  final bool stickyHeader;
  // final VerseScrollRegistry? verseScroll;
  final VerseGoto? verseGoto;

  // What each verse needs to know about itself (your data-* attributes).
  final String translationId; // data-tr
  final String edition; // data-ed
  final String bookId; // data-bk
  final int chapterNumber; // data-ch
  final VerseSelection selection;
  final HighlightStore highlights;
  final ScrollController scrollController;
  final Listenable? notesListenable;
  final String? Function(int verse)? noteFor;
  final void Function(int verse)? onEditNote;
  final Set<int> crossRefVerses;
  final void Function(int verse)? onCrossRef;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style
        .merge(TextStyle(fontSize: fontSize, height: kLineHeight));
    final lineH = fontSize * kLineHeight;
    final firstVerse = chapter.items.indexWhere((i) => i is VerseItem);

    // Same flag behaviour as `wasHeading` in Bible.jsx: set by headings,
    // cleared only by a line_break item.
    var wasHeading = false;
    final blocks = <Widget>[];

    for (var i = 0; i < chapter.items.length; i++) {
      switch (chapter.items[i]) {
        case ErrorItem(:final message):
          blocks.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  message,
                  style: base.merge(const TextStyle(color: Colors.redAccent)),
                ),
              ),
            ),
          );
        case HeadingItem(:final parts):
          blocks.add(
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 20),
              child: _ParagraphBlock(
                kind: _Kind.heading,
                parts: parts,
                chapter: chapter,
                base: base,
              ),
            ),
          );
          wasHeading = true;
        case HebrewSubtitleItem(:final parts):
          blocks.add(
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 20),
              child: _ParagraphBlock(
                kind: _Kind.hebrew,
                parts: parts,
                chapter: chapter,
                base: base,
              ),
            ),
          );
          wasHeading = true;
        case LineBreakItem():
          blocks.add(SizedBox(height: wasHeading ? 0 : lineH));
          wasHeading = false;
        case VerseItem(:final number, :final parts):
          final frame = _VerseFrame(
            verseRef: (
              ed: edition,
              tr: translationId,
              bk: bookId,
              ch: chapterNumber,
              vs: number,
            ),
            selection: selection,
            highlights: highlights,
            child: _ParagraphBlock(
              kind: _Kind.verse,
              parts: parts,
              chapter: chapter,
              base: base,
              number: number,
              dropCap: i == firstVerse,
              onCrossRef: onCrossRef != null && crossRefVerses.contains(number)
                  ? () => onCrossRef!(number)
                  : null,
            ),
          );
          final framed = verseGoto?.wrap(number, blocks.length, frame) ?? frame;
          final nl = notesListenable;
          final nf = noteFor;
          blocks.add(
            nl == null || nf == null
                ? framed
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      framed,
                      _VerseNote(
                        listenable: nl,
                        noteFor: nf,
                        verse: number,
                        base: base,
                        onEdit: () => onEditNote?.call(number),
                      ),
                    ],
                  ),
          );
      }
      verseGoto?.setBlockCount(blocks.length);
    }

    return LayoutBuilder(
      builder: (context, c) {
        final paneW = c.maxWidth; // the real width of THIS pane
        final scaler = MediaQuery.textScalerOf(context);

        final headerFont = (paneW * 0.03).clamp(12.0, 15.0);
        const headerLineHeight = 1.2;
        const headerVPad = 4.0;
        const headerHPad = 16.0;

        final headerStyle = base.merge(
          TextStyle(
            fontSize: headerFont,
            height: headerLineHeight,
            fontWeight: FontWeight.w700,
            fontStyle: headerItalic ? FontStyle.italic : FontStyle.normal,
            color: context.colorScheme.onSurface,
          ),
        );

        final contentW = paneW < kContentMaxWidth ? paneW : kContentMaxWidth;
        final tp = TextPainter(
          text: TextSpan(text: headerText, style: headerStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          textScaler: scaler,
        )..layout(maxWidth: contentW - headerHPad * 2);
        final measured = tp.height + headerVPad * 2;
        tp.dispose();
        final headerHeight = measured < kHeaderHeight
            ? kHeaderHeight
            : measured;

        final headerText_ = Padding(
          padding: const EdgeInsets.symmetric(horizontal: headerHPad),
          child: Text(
            headerText,
            textAlign: TextAlign.center,
            style: headerStyle,
          ),
        );

        final textured = context.select<AppSettings, bool>(
          (s) => s.bodyTexture,
        );
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                if (stickyHeader) ...[
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _HeaderDelegate(
                      height: headerHeight,
                      topGap: kHeaderTopGap,
                      pinnedBackground: textured
                          ? const PaperOverlay(opacity: 1)
                          : ColoredBox(color: context.colorScheme.secondary),
                      child: headerText_,
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: kHeaderBottomGap),
                  ),
                ] else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: kHeaderTopGap,
                        bottom: kHeaderBottomGap,
                      ),
                      child: headerText_,
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    kSidePadding,
                    kTopPadding,
                    kSidePadding,
                    kBottomPadding,
                  ),
                  sliver: SliverList.builder(
                    itemCount: blocks.length,
                    itemBuilder: (context, index) => blocks[index],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// PARAGRAPH (verse / heading / hebrew subtitle) with tap-to-open footnotes
// ---------------------------------------------------------------------------

enum _Kind { verse, heading, hebrew }

class _Run {
  _Run(this.text, this.style, [this.onTap]);
  String text;
  final TextStyle? style;
  final VoidCallback? onTap;
}

class _ParagraphBlock extends StatefulWidget {
  const _ParagraphBlock({
    required this.kind,
    required this.parts,
    required this.chapter,
    required this.base,
    this.number,
    this.dropCap = false,
    this.onCrossRef,
  });

  final _Kind kind;
  final List<VersePart> parts;
  final ChapterData chapter;
  final TextStyle base;
  final int? number;
  final bool dropCap;
  final VoidCallback? onCrossRef;

  @override
  State<_ParagraphBlock> createState() => _ParagraphBlockState();
}

class _ParagraphBlockState extends State<_ParagraphBlock> {
  String? _activeNote;
  bool _capItalic = false;

  @override
  void dispose() {
    super.dispose();
  }

  void _toggleNote(String id) =>
      setState(() => _activeNote = _activeNote == id ? null : id);

  Color get _dim => (widget.base.color ?? Colors.white).withValues(alpha: 0.6);

  // Style applied to the whole paragraph, per kind.
  TextStyle get _style {
    final fs = widget.base.fontSize!;
    switch (widget.kind) {
      case _Kind.verse:
        return widget.base;
      case _Kind.heading: // .Bible-headings: italic, smaller, 50% colour
        return widget.base.merge(
          TextStyle(
            fontSize: fs * 0.85,
            fontStyle: FontStyle.italic,
            color: (widget.base.color ?? Colors.white).withValues(alpha: 0.5),
          ),
        );
      case _Kind.hebrew: // h6, CornflowerBlue, centred
        return widget.base.merge(
          TextStyle(
            fontSize: fs * 0.85,
            fontWeight: FontWeight.w700,
            color: context.customColors.kHebrewColor,
          ),
        );
    }
  }

  List<_Run> _buildRuns() {
    final fs = widget.base.fontSize!;
    final isVerse = widget.kind == _Kind.verse;
    final tail = isVerse ? '\u00A0' : '';
    final runs = <_Run>[];

    // The JS `wasHeading` flag: a leading lineBreak inside a verse is skipped.
    var skipBreak = isVerse;

    // Verse number (hidden for the first verse: the drop cap replaces it).
    if (isVerse && widget.number != null && !widget.dropCap) {
      runs.add(
        _Run(
          '${widget.number}. ',
          TextStyle(
            fontSize: fs * 0.7,
            fontWeight: FontWeight(500),
            color: context.customColors.kVerseNoColor,
          ),
        ),
      );
    }

    for (final part in widget.parts) {
      switch (part) {
        case TextPart(:final text):
          runs.add(_Run('$text$tail', null));
        case JesusPart(:final text):
          runs.add(
            _Run(
              '$text$tail',
              TextStyle(
                color: context.customColors.kJesusColor,
              ),
            ),
          );
        case ItalicPart(:final text):
          runs.add(
            _Run(' $text ', const TextStyle(fontStyle: FontStyle.italic)),
          );
        case NotePart(:final id):
          runs.add(
            _Run(
              '$id\u00A0',
              TextStyle(
                fontSize: fs * 0.62,
                fontStyle: FontStyle.italic,
                color: _dim,
              ),
              () => _toggleNote(id),
            ),
          );
        case LineBreakPart():
          if (!skipBreak) runs.add(_Run('\n', null));
          skipBreak = false;
        case PoemPart(:final text):
          runs.add(
            _Run(
              ' Poem: $text ',
              const TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.pinkAccent,
              ),
            ),
          );
      }
    }
    if (isVerse && widget.onCrossRef != null) {
      runs.add(
        _Run(
          '\u00A0\u00A0$kCrossRefSymbol\u00A0\u00A0',
          TextStyle(
            fontSize: fs * 0.8,
            color: context.customColors.kVerseNoColor,
          ),
          widget.onCrossRef,
        ),
      );
    }
    return runs;
  }

  TextSpan _span(List<_Run> runs, TextStyle style) => TextSpan(
    style: style,
    children: [
      for (final r in runs) TextSpan(text: r.text, style: r.style),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final runs = _buildRuns();
    final style = _style;
    final scaler = MediaQuery.textScalerOf(context);

    Widget paragraph;
    if (widget.dropCap && widget.kind == _Kind.verse) {
      final capText = _takeCapText(runs);
      paragraph = capText == null
          ? _rich(runs, style, scaler)
          : LayoutBuilder(
              builder: (context, c) =>
                  _dropCap(c.maxWidth, capText, runs, style, scaler),
            );
    } else {
      paragraph = SizedBox(
        width: double.infinity,
        child: _rich(
          runs,
          style,
          scaler,
          align: widget.kind == _Kind.hebrew
              ? TextAlign.center
              : TextAlign.start,
        ),
      );
    }

    final note = _activeNote == null
        ? null
        : widget.chapter.footnote(_activeNote!);
    // FOOTNOTE:
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        paragraph,
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          alignment: Alignment.topCenter,
          child: _activeNote == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8, bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    // color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    note?.text ?? 'Footnote $_activeNote',
                    style: widget.base.merge(
                      TextStyle(
                        fontSize: widget.base.fontSize! * 0.75,
                        fontWeight: FontWeight(400),
                        color: _dim,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // ---- Drop cap -----------------------------------------------------------

  /// Removes the first letter and remembers whether its text was italic.
  String? _takeCapText(List<_Run> runs) {
    final letter = RegExp(r'\p{L}', unicode: true);
    for (final r in runs) {
      if (r.style?.fontSize != null) continue; // skip number / note runs
      final m = letter.firstMatch(r.text);
      if (m == null) continue;
      final cap = r.text.substring(0, m.end);
      r.text = r.text.substring(m.end);
      _capItalic = r.style?.fontStyle == FontStyle.italic;
      return cap;
    }
    return null;
  }

  Widget _rich(
    List<_Run> runs,
    TextStyle style,
    TextScaler scaler, {
    TextAlign align = TextAlign.start,
  }) => _TappableRich(
    runs: runs,
    span: _span(runs, style),
    align: align,
    scaler: scaler,
  );

  Widget _dropCap(
    double maxWidth,
    String capText,
    List<_Run> runs,
    TextStyle style,
    TextScaler scaler,
  ) {
    final k = scaler.scale(1.0);
    final lineH = style.fontSize! * (style.height ?? 1) * k;
    final capFont = lineH * kCapScale;

    final italic = _capItalic || style.fontStyle == FontStyle.italic;

    final capStyle = TextStyle(
      fontFamily: 'Georgia',
      fontFamilyFallback: const ['serif'],
      fontWeight: FontWeight.w700,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontSize: capFont,
      height: 1.0,
    );

    final capPainter = TextPainter(
      text: TextSpan(text: capText, style: capStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final capW = capPainter.width + kCapGap;
    capPainter.dispose();

    // Raised cap (CSS `initial-letter: 2 1`): the letter's baseline sits on
    // line 1's baseline and it rises above the paragraph. Only line 1 is
    // beside it; line 2 onwards runs the full width.
    final baseline = lineH * kBaselineFrac;
    // With height 1.0: baseline is ~0.849em below the glyph box top and a
    // capital is ~0.692em tall (Georgia metrics).
    final glyphTop = baseline - 0.849 * capFont;
    final capVisualTop = baseline - 0.692 * capFont;
    final rise = (-capVisualTop).clamp(0.0, double.infinity) + kCapTopRoom;

    final capBox = RepaintBoundary(
      child: SizedBox(
        width: capW,
        height: lineH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Leaf behind the letter (background-image in your CSS)
            Positioned(
              left: kLeafOffset.dx,
              top: capVisualTop + kLeafOffset.dy,
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: Image.asset(
                    kLeafAsset,
                    width: lineH * kLeafScale,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
            // Letter: black outline underneath, gold fill on top
            Positioned(
              left: 0,
              top: glyphTop,
              child: Stack(
                children: [
                  Text(
                    capText,
                    textScaler: TextScaler.noScaling,
                    style: capStyle.copyWith(
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = kCapOutline
                        ..strokeJoin = StrokeJoin.round
                        ..color = Colors.black,
                    ),
                  ),
                  Text(
                    capText,
                    textScaler: TextScaler.noScaling,
                    style: capStyle.copyWith(
                      color: context.customColors.kFirstLetter,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    Widget firstRow(Widget text) => Padding(
      padding: EdgeInsets.only(top: rise),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          capBox,
          Expanded(child: text),
        ],
      ),
    );

    // Measure the text beside the cap to find where line 1 ends.
    final textW = (maxWidth - capW).clamp(0.0, double.infinity);
    final tp = TextPainter(
      text: _span(runs, style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: textW);
    final lines = tp.computeLineMetrics();

    if (lines.length <= 1) {
      tp.dispose();
      return firstRow(_rich(runs, style, scaler));
    }

    final y = lines[0].height / 2;
    final end = tp.getLineBoundary(tp.getPositionForOffset(Offset(1, y))).end;
    tp.dispose();

    final (head, tail) = _split(runs, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        firstRow(_rich(head, style, scaler)),
        _rich(tail, style, scaler),
      ],
    );
  }

  (List<_Run>, List<_Run>) _split(List<_Run> runs, int at) {
    final head = <_Run>[];
    final tail = <_Run>[];
    var pos = 0;

    for (final r in runs) {
      final len = r.text.length;
      if (pos + len <= at) {
        head.add(r);
      } else if (pos >= at) {
        tail.add(r);
      } else {
        final cut = at - pos;
        head.add(_Run(r.text.substring(0, cut), r.style, r.onTap));
        tail.add(_Run(r.text.substring(cut), r.style, r.onTap));
      }
      pos += len;
    }

    // Drop leading whitespace at the start of the continuation.
    while (tail.isNotEmpty) {
      final trimmed = tail.first.text.trimLeft();
      if (trimmed.isEmpty) {
        tail.removeAt(0);
      } else {
        tail[0] = _Run(trimmed, tail.first.style, tail.first.onTap);
        break;
      }
    }
    return (head, tail);
  }
}

// ---------------------------------------------------------------------------
// VERSE FRAME: selection gestures + selection / highlight backgrounds.
// Only the background layer listens to the selection, so the paragraph (and
// its drop-cap measuring) is NOT rebuilt when verses are selected.
// ---------------------------------------------------------------------------

class _VerseFrame extends StatefulWidget {
  const _VerseFrame({
    required this.verseRef,
    required this.selection,
    required this.highlights,
    required this.child,
  });

  final VerseRef verseRef;
  final VerseSelection selection;
  final HighlightStore highlights;
  final Widget child;

  @override
  State<_VerseFrame> createState() => _VerseFrameState();
}

class _VerseFrameState extends State<_VerseFrame> {
  DateTime? _lastTap;

  // Your onClick / onDblClick:
  //  - selecting already: a single tap toggles this verse
  //  - not selecting: a double-click starts the selection
  // (done by hand instead of onDoubleTap, which would delay every tap)
  void _onTap() {
    final sel = widget.selection;
    if (sel.isActive) {
      sel.toggle(widget.verseRef);
      return;
    }
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < kDoubleClickWindow) {
      _lastTap = null;
      sel.toggle(widget.verseRef);
    } else {
      _lastTap = now;
    }
  }

  // Your pager-long-press: starts a selection.
  void _onLongPress() {
    if (!widget.selection.isActive) widget.selection.toggle(widget.verseRef);
  }

  @override
  Widget build(BuildContext context) {
    final style = context.select<AppSettings, HighlightStyle>(
      (s) => s.highlightStyle,
    );

    return ListenableBuilder(
      listenable: Listenable.merge([widget.selection, widget.highlights]),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _onTap,
        onLongPress: _onLongPress,
        child: widget.child,
      ),
      builder: (context, gesture) {
        final highlight = widget.highlights.colorFor(widget.verseRef);
        final selected = widget.selection.contains(widget.verseRef);

        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            Positioned(
              left: -kSelectBleed,
              right: -kSelectBleed,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    // 1. Containing box
                    if (style == HighlightStyle.box)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(
                          horizontal: kSelectBleed - 6,
                        ),
                        decoration: BoxDecoration(
                          color: highlight?.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    // 3. Curved side light, at the edge of the selection bar
                    if (style == HighlightStyle.sideLight && highlight != null)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 14,
                        child: CustomPaint(
                          painter: _SideLightPainter(highlight),
                        ),
                      ),
                    // Selection bar (unchanged)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: selected ? kSelectColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 2. Text background paints behind the text, above the selection bar
            VerseHighlight(
              color: style == HighlightStyle.textBackground
                  ? highlight?.withValues(alpha: 0.45)
                  : null,
              child: gesture,
            ),
          ],
        );
      },
    );
  }
}

// ---- Sticky Title -------------------------------------------------------

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({
    required this.height,
    required this.topGap,
    required this.pinnedBackground,
    required this.child,
  });

  final double height;
  final double topGap;
  final Widget pinnedBackground;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height + topGap;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Background only appears once the title has reached the top (stuck).
    final stuck = shrinkOffset >= topGap;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Texture only appears once the title has reached the top.
        if (stuck) pinnedBackground,
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: height,
            child: Center(child: child),
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(_HeaderDelegate old) =>
      old.height != height ||
      old.topGap != topGap ||
      old.pinnedBackground != pinnedBackground ||
      old.child != child;
}

// ---------------------------------------------------------------------------
// VERSE NOTE: icon + one-line note under the verse.
//   tap                    -> expand / collapse
//   double-tap / long-press -> edit
// Listens to the gallery itself, so verses don't rebuild when notes change.
// ---------------------------------------------------------------------------

class _VerseNote extends StatefulWidget {
  const _VerseNote({
    required this.listenable,
    required this.noteFor,
    required this.verse,
    required this.base,
    required this.onEdit,
  });

  final Listenable listenable;
  final String? Function(int verse) noteFor;
  final int verse;
  final TextStyle base;
  final VoidCallback onEdit;

  @override
  State<_VerseNote> createState() => _VerseNoteState();
}

class _VerseNoteState extends State<_VerseNote> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.listenable,
    builder: (context, _) {
      final note = widget.noteFor(widget.verse);
      if (note == null || note.trim().isEmpty) return const SizedBox.shrink();

      final fs = widget.base.fontSize! * 0.72;
      final dim = (widget.base.color ?? context.colorScheme.onSurface)
          .withValues(alpha: 0.6);

      return Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          onDoubleTap: widget.onEdit,
          onLongPress: widget.onEdit,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _open ? double.infinity : 180,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: _open
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: fs * 1.6,
                      color: Colors.amber.shade600,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        note,
                        maxLines: _open ? null : 1,
                        overflow: _open
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(fontSize: fs, color: dim),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// TEXT-BACKGROUND HIGHLIGHT
// HighlightTarget marks the verse's text. RenderVerseHighlight finds those
// marked paragraphs, asks each for its per-line boxes, and paints rounded
// shapes BEHIND the text. It paints only; it never re-lays out the text.
// ---------------------------------------------------------------------------

class HighlightTarget extends SingleChildRenderObjectWidget {
  const HighlightTarget({super.key, super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderHighlightTarget();
}

class RenderHighlightTarget extends RenderProxyBox {}

class VerseHighlight extends SingleChildRenderObjectWidget {
  const VerseHighlight({super.key, required this.color, super.child});
  final Color? color; // null = nothing to draw

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderVerseHighlight(color);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderVerseHighlight renderObject,
  ) => renderObject.color = color;
}

class RenderVerseHighlight extends RenderProxyBox {
  RenderVerseHighlight(this._color);

  Color? _color;
  set color(Color? v) {
    if (_color == v) return;
    _color = v;
    markNeedsPaint(); // repaint only, no layout
  }

  static const _radius = Radius.circular(8);

  @override
  void paint(PaintingContext context, Offset offset) {
    final color = _color;
    if (color != null) {
      final lines = <Rect>[];
      _collectLines(this, lines);
      final paint = Paint()..color = color;
      for (var i = 0; i < lines.length; i++) {
        final first = i == 0;
        final last = i == lines.length - 1;
        final single = first && last;
        final r = lines[i];
        final rect = Rect.fromLTRB(
          r.left - 6,
          r.top,
          r.right + 4,
          r.bottom,
        ).shift(offset);
        context.canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: first ? _radius : Radius.zero,
            bottomLeft: single ? _radius : Radius.zero,
            topRight: single ? _radius : Radius.zero,
            bottomRight: last ? _radius : Radius.zero,
          ),
          paint,
        );
      }
    }
    super.paint(context, offset); // the text goes on top
  }

  /// One Rect per visual line, in this object's coordinates.
  void _collectLines(RenderObject node, List<Rect> out) {
    if (node is RenderHighlightTarget) {
      final p = node.child;
      if (p is RenderParagraph) {
        final len = p.text.toPlainText(includeSemanticsLabels: false).length;
        final boxes = p.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: len),
          boxHeightStyle: ui.BoxHeightStyle.max, // full line height
        );
        final m = p.getTransformTo(this);
        Rect? cur;
        for (final b in boxes) {
          final rect = MatrixUtils.transformRect(m, b.toRect());
          if (cur != null && (rect.top - cur.top).abs() < 1) {
            cur = cur.expandToInclude(rect); // same line: merge
          } else {
            if (cur != null) out.add(cur);
            cur = rect;
          }
        }
        if (cur != null) out.add(cur);
      }
      return;
    }
    node.visitChildren((c) => _collectLines(c, out));
  }
}

// ---------------------------------------------------------------------------
// CURVED SIDE LIGHT: same shape as CSS  border-left + border-radius
// Outer rounded shape minus an inner, squashed one = a crescent at each end
// that tapers to a point.
// ---------------------------------------------------------------------------

class _SideLightPainter extends CustomPainter {
  const _SideLightPainter(this.color);
  final Color color;

  static const double _width = 4; // border thickness (your CSS: 3px)
  static const double _radius = 8; // must match the selection bar's radius

  @override
  void paint(Canvas canvas, Size size) {
    // Outer shape: only the LEFT corners are rounded.
    final outer = Path()
      ..addRRect(
        RRect.fromLTRBAndCorners(
          0,
          0,
          size.width,
          size.height,
          topLeft: const Radius.circular(_radius),
          bottomLeft: const Radius.circular(_radius),
        ),
      );

    // Inner shape: starts _width further right. Its left corners are
    // squashed ellipses (narrower than they are tall), exactly like CSS.
    // It runs past the right edge so nothing of it is left on that side.
    const squashed = Radius.elliptical(_radius - _width, _radius);
    final inner = Path()
      ..addRRect(
        RRect.fromLTRBAndCorners(
          _width,
          0,
          size.width + _radius,
          size.height,
          topLeft: squashed,
          bottomLeft: squashed,
        ),
      );

    final shape = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(shape, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SideLightPainter old) => old.color != color;
}

/// Extra touch area around tappable runs (footnote numbers, ※).
const double kNoteHitSlop = 5;

class _TappableRich extends StatefulWidget {
  const _TappableRich({
    required this.runs,
    required this.span,
    required this.align,
    required this.scaler,
  });

  final List<_Run> runs;
  final TextSpan span;
  final TextAlign align;
  final TextScaler scaler;

  @override
  State<_TappableRich> createState() => _TappableRichState();
}

class _TappableRichState extends State<_TappableRich> {
  final _paragraphKey = GlobalKey();
  bool _overNote = false;

  /// Returns the callback of the tappable run near [global], or null.
  VoidCallback? _hit(Offset global) {
    final ro = _paragraphKey.currentContext?.findRenderObject();
    if (ro is! RenderParagraph) return null;
    final local = ro.globalToLocal(global);

    var pos = 0;
    for (final r in widget.runs) {
      final start = pos;
      pos += r.text.length;
      final cb = r.onTap;
      if (cb == null || r.text.isEmpty) continue;

      final boxes = ro.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: pos),
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
      for (final b in boxes) {
        if (b.toRect().inflate(kNoteHitSlop).contains(local)) return cb;
      }
    }
    return null;
  }

  void _onHover(PointerHoverEvent e) {
    final over = _hit(e.position) != null;
    if (over != _overNote) setState(() => _overNote = over);
  }

  void _onExit(PointerExitEvent e) {
    if (_overNote) setState(() => _overNote = false);
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _NoteTapRecognizer:
            GestureRecognizerFactoryWithHandlers<_NoteTapRecognizer>(
              () => _NoteTapRecognizer(),
              (r) {
                r.canStart = (g) => _hit(g) != null;
                r.onTapUp = (d) => _hit(d.globalPosition)?.call();
              },
            ),
      },
      child: MouseRegion(
        opaque: false,
        cursor: _overNote ? SystemMouseCursors.click : MouseCursor.defer,
        onHover: _onHover,
        onExit: _onExit,
        // HighlightTarget must stay directly above the RichText.
        child: HighlightTarget(
          child: RichText(
            key: _paragraphKey,
            text: widget.span,
            textAlign: widget.align,
            textScaler: widget.scaler,
          ),
        ),
      ),
    );
  }
}

/// A tap recognizer that only enters the gesture arena when the touch is on
/// (or within the slop of) a tappable run. Everything else falls through to
/// the verse's own tap / long-press handling.
class _NoteTapRecognizer extends TapGestureRecognizer {
  bool Function(Offset global)? canStart;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      (canStart?.call(event.position) ?? false) &&
      super.isPointerAllowed(event);
}
