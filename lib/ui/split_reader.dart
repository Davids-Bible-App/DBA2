import 'dart:math' as math;

import 'package:dba2/core.dart';

import '../controllers/bible_controller.dart';
import '../controllers/split_controller.dart';
import '../controllers/translation_pane.dart';
import '../models/chapter_view.dart';
import '../state/shared_state.dart';
import 'translation_sheet.dart';

/// Thickness of the divider strip (holds the controls).
const double kDividerThickness = 30;

/// Wraps the primary reader. With split off it just returns the primary;
/// with split on it lays out primary + divider + second pane.
class SplitReader extends StatefulWidget {
  const SplitReader({super.key, required this.primary});
  final Widget primary;

  @override
  State<SplitReader> createState() => _SplitReaderState();
}

class _SplitReaderState extends State<SplitReader> {
  // Keeps the primary's state (scroll position!) when split is toggled.
  final _primaryKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final split = context.watch<SplitController>();
    final hasPrimary = context.select<BibleController, bool>(
      (b) => b.hasTranslation,
    );
    final primary = KeyedSubtree(key: _primaryKey, child: widget.primary);

    if (!split.enabled || split.panes.isEmpty || !hasPrimary) return primary;

    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        final sideBySide = split.isSideBySide(size);
        final total = sideBySide ? size.width : size.height;
        final usable = math.max(0.0, total - kDividerThickness);
        final firstExtent = usable * split.ratio;
        final secondExtent = usable - firstExtent;

        Widget sized(double extent, Widget child) => SizedBox(
          width: sideBySide ? extent : size.width,
          height: sideBySide ? size.height : extent,
          child: ClipRect(child: child),
        );

        return SizedBox(
          width: size.width,
          height: size.height,
          child: Flex(
            direction: sideBySide ? Axis.horizontal : Axis.vertical,
            children: [
              sized(firstExtent, primary),
              _SplitDivider(
                stacked: !sideBySide,
                usable: usable,
                crossExtent: sideBySide ? size.height : size.width,
              ),
              sized(secondExtent, _PaneView(pane: split.panes.first)),
            ],
          ),
        );
      },
    );
  }
}

/// App bar split button: off -> on (asks for a translation the first time).
Future<void> toggleSplit(BuildContext context) async {
  final split = context.read<SplitController>();
  if (split.enabled) {
    split.setEnabled(false);
    return;
  }
  if (split.panes.isNotEmpty) {
    split.setEnabled(true);
    return;
  }
  await showTopSheet(
    context,
    (_) => TranslationSheet(
      title: 'Second translation',
      onPick: (id) => split.setPaneTranslation(0, id),
    ),
  );
}

// ---------------------------------------------------------------------------
// DIVIDER: drag to resize, double-tap to reset, controls on top.
// ---------------------------------------------------------------------------

class _SplitDivider extends StatelessWidget {
  const _SplitDivider({
    required this.stacked,
    required this.usable,
    required this.crossExtent,
  });

  final bool stacked;
  final double usable;
  final double crossExtent;

  @override
  Widget build(BuildContext context) {
    final split = context.read<SplitController>();
    return SizedBox(
      width: stacked ? crossExtent : kDividerThickness,
      height: stacked ? kDividerThickness : crossExtent,
      child: Listener(
        onPointerDown: (_) => split.draggingDivider = true,
        onPointerUp: (_) => _release(split),
        onPointerCancel: (_) => _release(split),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) {
            if (usable <= 0) return;
            final delta = stacked ? d.delta.dy : d.delta.dx;
            split.setRatio(split.ratio + delta / usable);
          },
          onPanEnd: (_) => split.commitRatio(),
          onDoubleTap: split.resetRatio,
          child: _DividerControls(stacked: stacked),
        ),
      ),
    );
  }
}

// Clear after the frame, so the pager's own pointer-up has already
// seen the flag and ignored the swipe.
void _release(SplitController split) {
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => split.draggingDivider = false,
  );
}

class _DividerControls extends StatelessWidget {
  const _DividerControls({required this.stacked});
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final split = context.watch<SplitController>();
    final bible = context.watch<BibleController>();
    final onSurface = context.colorScheme.onSurface;
    final dir = stacked ? Axis.horizontal : Axis.vertical;
    final lineColor = onSurface.withValues(alpha: 0.35);

    Widget dash({double? length}) {
      final line = CustomPaint(painter: _DashPainter(dir, lineColor));
      if (length == null) return Expanded(child: line);
      return SizedBox(
        width: stacked ? length : null,
        height: stacked ? null : length,
        child: line,
      );
    }

    final secondAbbr = split.panes.isEmpty
        ? '---'
        : split.panes.first.info.abbr;

    return Padding(
      padding: stacked
          ? const EdgeInsets.symmetric(horizontal: 6)
          : const EdgeInsets.symmetric(vertical: 6),
      child: Flex(
        direction: dir,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Lock: ON = other panes follow the primary.
          _IconBtn(
            icon: split.locked
                ? const Icon(Icons.lock_outline_rounded)
                : const Icon(Icons.lock_open_rounded),
            color: split.locked
                ? Colors.lightBlue[700]!
                : onSurface.withValues(alpha: 0.6),
            tooltip: split.locked
                ? 'Panes follow the top/left pane'
                : 'Panes scroll independently',
            onTap: () => split.setLocked(!split.locked),
          ),
          dash(),
          _VerLabel(
            abbr: bible.edition,
            icon: Icons.keyboard_arrow_up,
            rotate: !stacked,
            onTap: () => openTranslationSheet(context),
          ),
          dash(length: 24),
          _VerLabel(
            abbr: secondAbbr,
            icon: Icons.keyboard_arrow_down,
            rotate: !stacked,
            onTap: () => showTopSheet(
              context,
              (_) => TranslationSheet(
                title: stacked ? 'Bottom pane' : 'Right pane',
                currentId: split.panes.isEmpty ? null : split.panes.first.id,
                onPick: (id) => split.setPaneTranslation(0, id),
              ),
            ),
          ),
          dash(),
          _IconBtn(
            icon: switch (split.mode) {
              SplitMode.auto => const Icon(Icons.screen_rotation),
              SplitMode.stacked => const Icon(Icons.splitscreen),
              SplitMode.sideBySide => const RotatedBox(
                quarterTurns: 1,
                child: Icon(Icons.splitscreen),
              ),
            },
            color: Colors.deepOrange[500]!,
            tooltip: 'Layout: ${split.mode.name}',
            onTap: split.cycleMode, // Uses onTap since _IconBtn is defined with onTap[cite: 3]
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon, // Changed from IconData to Widget
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final Widget icon; // Changed type
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 28,
        height: 28,
        child: InkResponse(
          onTap: onTap,
          radius: 16,
          // Directly display the widget, applying color if it's an Icon
          child: Center(
            child: IconTheme(
              data: IconThemeData(
                color: color,
                size: 16,
              ), // Applies color (and default size) to all child icons
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}

class _VerLabel extends StatelessWidget {
  const _VerLabel({
    required this.abbr,
    required this.icon,
    required this.rotate,
    required this.onTap,
  });

  final String abbr;
  final IconData icon;
  final bool rotate; // true in the vertical strip (side by side)
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            abbr,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Icon(icon, size: 14),
        ],
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Center(
        child: rotate ? RotatedBox(quarterTurns: 3, child: label) : label,
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.axis, this.color);
  final Axis axis;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    if (axis == Axis.horizontal) {
      final y = s.height / 2;
      for (var x = 0.0; x < s.width; x += dash + gap) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + dash, s.width), y),
          paint,
        );
      }
    } else {
      final x = s.width / 2;
      for (var y = 0.0; y < s.height; y += dash + gap) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, math.min(y + dash, s.height)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) =>
      old.axis != axis || old.color != color;
}

// ---------------------------------------------------------------------------
// SECOND PANE CONTENT
// ---------------------------------------------------------------------------

class _PaneView extends StatelessWidget {
  const _PaneView({required this.pane});
  final TranslationPane pane;

  @override
  Widget build(BuildContext context) {
    final bible = context.read<BibleController>();
    final sticky = context.watch<AppSettings>().stickyHeader;
    final requested = bible.currentBook?.englishName ?? '';

    switch (pane.status) {
      case PaneStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case PaneStatus.error:
        return _PaneNotice([
          'Unable to open',
          '(${pane.info.name})',
          pane.message ?? '',
        ]);
      case PaneStatus.missingBook:
        return _PaneNotice([
          'This Translation',
          '(${pane.info.name})',
          'Does not contain the requested Book ($requested).',
        ]);
      case PaneStatus.missingChapter:
        return _PaneNotice([
          'This Translation',
          '(${pane.info.name})',
          'Does not contain chapter ${pane.chapterNumber} of $requested.',
        ]);
      case PaneStatus.ready:
        break;
    }

    final book = pane.book!;
    final chapterNo = pane.chapterNumber;
    final isFirst = chapterNo == 1;
    final header = isFirst
        ? (book.title.isNotEmpty
              ? book.title
              : (book.name.isNotEmpty ? book.name : book.englishName))
        : '${book.englishName} - chapter $chapterNo';

    return ListenableBuilder(
      listenable: bible.fontSize,
      builder: (context, _) => ChapterView(
        key: ValueKey('${pane.id}-${book.id}-$chapterNo'),
        fontSize: bible.fontSize.px,
        stickyHeader: sticky,
        chapter: pane.data!,
        headerText: header,
        headerItalic: isFirst,
        translationId: pane.id,
        edition: pane.info.abbr,
        bookId: book.id,
        chapterNumber: chapterNo,
        selection: bible.selection,
        highlights: bible.highlights,
        scrollController: pane.scroll,
      ),
    );
  }
}

class _PaneNotice extends StatelessWidget {
  const _PaneNotice(this.lines);
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < lines.length; i++)
              if (lines[i].isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    lines[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFFFF6347),
                      fontWeight: FontWeight.w700,
                      fontSize: i == lines.length - 1 ? 16 : 18,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
