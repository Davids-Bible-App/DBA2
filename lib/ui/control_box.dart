// lib/ui/control_box.dart
import 'dart:ui';

import 'package:flutter/material.dart';

import 'verse_selection.dart';

const double kControlBoxHeight = 130;
const Color kControlBoxColor = Color(0xF2141414);
const double kActionButtonWidth = 54;
const double kSwatchSize = 34;
const double kSwatchGap = 4;

const List<Color> kHighlightColors = [
  Color(0xFFE57373),
  Color(0xFFE8915A),
  Color(0xFFB5A12A),
  Color(0xFF7FA06A),
  Color(0xFF4FA896),
  Color(0xFF3E91B0),
  Color(0xFF6B9BE8),
  Color(0xFFB57FDE),
];

enum ControlAction { strongs, compare, copy, bookmark, topic, note, picture }

/// Slides up from the bottom while verses are selected.
/// Highlight swatches are handled here; every other button is reported
/// through [onAction] so the page decides what it does.
class ControlBox extends StatelessWidget {
  const ControlBox({
    super.key,
    required this.selection,
    required this.highlights,
    required this.onAction,
    this.showStrongs = false,
  });

  final VerseSelection selection;
  final HighlightStore highlights;
  final void Function(ControlAction action) onAction;
  final bool showStrongs;

  void _setColor(Color? color) {
    highlights.setColor(selection.sorted, color);
    selection.clear(); // your setExpandedCtl(0)
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;

    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final open = selection.isActive;
        return IgnorePointer(
          ignoring: !open,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: open ? kControlBoxHeight + inset : 0),
            duration: const Duration(milliseconds: 400),
            // Overshoot (like your cubic-bezier) only when opening. On close,
            // easeOutBack would dip below 0 and give a negative height.
            curve: open ? Curves.easeOutBack : Curves.easeInCubic,
            // Lets the content keep its size while the box animates.
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: kControlBoxHeight + inset,
              child: Padding(
                padding: EdgeInsets.only(bottom: inset),
                child: _body(context),
              ),
            ),

            builder: (context, height, child) => Container(
              height: height < 0 ? 0 : height,
              // Shadow lives OUTSIDE the clip, so it isn't clipped away.
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color.fromARGB(43, 46, 46, 46), // rgb(0 0 0 / 0.4)
                    offset: Offset(0, 12), // 0 12px
                    blurRadius: 40, // ...40px
                  ),
                ],
              ),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 8,
                    sigmaY: 8,
                  ), // blur(12px)
                  child: Container(
                    color: Colors.transparent, // --glass: transparent
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        // Centred when it fits, scrolls sideways when it doesn't.
        _CenteredScroller(
          height: 48, // room for the hover lift
          children: [
            _Swatch(color: null, onTap: () => _setColor(null)),
            for (final c in kHighlightColors)
              _Swatch(color: c, onTap: () => _setColor(c)),
          ],
        ),
        const Text(
          'Highlight Swatches',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        _CenteredScroller(
          height: 46,
          children: [
            if (showStrongs)
              _ActionButton(
                icon: Icons.manage_search,
                label: 'Strongs',
                onTap: () => onAction(ControlAction.strongs),
              ),
            _ActionButton(
              icon: Icons.compare_arrows,
              label: 'Compare',
              onTap: () => onAction(ControlAction.compare),
            ),
            _ActionButton(
              icon: Icons.copy,
              label: 'Copy',
              onTap: () => onAction(ControlAction.copy),
            ),
            _ActionButton(
              icon: Icons.bookmark_add_outlined,
              label: 'Bookmark',
              onTap: () => onAction(ControlAction.bookmark),
            ),
            _ActionButton(
              icon: Icons.label_outline,
              label: 'Topic',
              onTap: () => onAction(ControlAction.topic),
            ),
            _ActionButton(
              icon: Icons.note_add_outlined,
              label: 'Note',
              onTap: () => onAction(ControlAction.note),
            ),
            _ActionButton(
              icon: Icons.add_photo_alternate_outlined,
              label: 'Picture',
              onTap: () => onAction(ControlAction.picture),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// A row that is centred (items kept together) on wide views and scrolls
// sideways on narrow ones. Mouse drag scrolling is enabled too, since
// desktop scroll views ignore mouse drags by default.
// ---------------------------------------------------------------------------

class _CenteredScroller extends StatelessWidget {
  const _CenteredScroller({required this.height, required this.children});

  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const pad = 8.0;
    return SizedBox(
      height: height,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: PointerDeviceKind.values.toSet(),
          scrollbars: false,
        ),
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: pad),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: (c.maxWidth - pad * 2).clamp(0.0, double.infinity),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SWATCH with a "dock" style hover bounce (ignored on touch screens).
// Uses a slide + scale, so the row never shifts layout.
// ---------------------------------------------------------------------------

class _Swatch extends StatefulWidget {
  const _Swatch({required this.color, required this.onTap});

  /// null = the red "none" swatch
  final Color? color;
  final VoidCallback onTap;

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kSwatchGap),
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            offset: Offset(0, _hover ? -0.10 : 0), // fraction of own height
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              scale: _hover ? 1.10 : 1.0,
              child: Container(
                width: kSwatchSize,
                height: kSwatchSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: color == null
                      ? Border.all(color: Colors.redAccent, width: 2)
                      : null,
                ),
                child: color == null
                    ? const Icon(Icons.close, color: Colors.redAccent, size: 22)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kActionButtonWidth,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        containedInkWell: true,
        mouseCursor: SystemMouseCursors.click,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
