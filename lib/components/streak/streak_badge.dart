import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'streak_badge_theme.dart';
import 'streak_controller.dart';
import 'streak_data.dart';

/// Button showing the current streak. Tapping it opens a popover whose
/// top-right corner sits under the button.
///
/// Dismiss: tap outside, the close button, Escape (desktop) or Back (Android).
class StreakBadge extends StatefulWidget {
  const StreakBadge({
    super.key,
    required this.controller,
    this.theme,
    this.buttonBuilder,
  });

  final StreakController controller;

  /// Optional per-instance override. Otherwise uses the ThemeData extension,
  /// or defaults derived from the ColorScheme.
  final StreakBadgeTheme? theme;

  /// Supply your own trigger button (e.g. your neumorphic IkonBtn).
  /// [onPressed] must be wired to the button; [label] is the streak number.
  final Widget Function(
    BuildContext context,
    VoidCallback onPressed,
    Widget label,
  )?
  buttonBuilder;

  @override
  State<StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends State<StreakBadge>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _portal = OverlayPortalController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  bool _open = false;

  // Anchor measured once when opening (no follower layers involved).
  double _anchorWidth = 32;
  double _top = 0;
  double _right = 0;

  StreakBadgeTheme _theme(BuildContext context) =>
      widget.theme ?? StreakBadgeTheme.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the OS "reduce motion" setting.
    _anim.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _theme(context).animationDuration;
  }

  // Window resized / rotated: the measured position is stale, so just close.
  @override
  void didChangeMetrics() {
    if (_open) _closePopover();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _anim.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      _closePopover();
      return true;
    }
    return false;
  }

  void _toggle() => _open ? _closePopover() : _openPopover();

  void _openPopover() {
    if (_open) return;

    final box = context.findRenderObject();
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || overlay is! RenderBox) return;

    // Button rect in the overlay's own coordinate space.
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    _anchorWidth = rect.width;
    _top = rect.bottom + _theme(context).anchorGap;
    _right = overlay.size.width - rect.right; // right edges line up

    setState(() => _open = true);
    _portal.show();
    _anim.forward();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  Future<void> _closePopover() async {
    if (!_open) return;
    HardwareKeyboard.instance.removeHandler(_onKey);
    setState(() => _open = false);
    await _anim.reverse();
    // Only remove the overlay if it wasn't re-opened during the animation.
    if (mounted && !_open) _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    final t = _theme(context);

    // Only this tiny Text rebuilds when the streak changes.
    final label = ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Text(
        '${widget.controller.data.currentStreak}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );

    final custom = widget.buttonBuilder;
    final button = custom != null
        ? custom(context, _toggle, label)
        : Material(
            color: t.buttonBackground,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.buttonRadius),
              side: BorderSide(color: t.buttonBorder),
            ),
            child: InkWell(
              onTap: _toggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: t.buttonForeground),
                      child: label,
                    ),
                  ),
                ),
              ),
            ),
          );

    return PopScope(
      // While open, Android Back closes the popover instead of leaving the page.
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closePopover();
      },
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildOverlay,
        child: Semantics(
          button: true,
          label: 'View streak details',
          child: button,
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final t = _theme(context);
    final curved = _anim.drive(CurveTween(curve: t.animationCurve));

    // Arrow points at the horizontal centre of the button.
    final arrowInset = (_anchorWidth / 2 - t.arrowSize).clamp(
      4.0,
      double.infinity,
    );

    return Stack(
      children: [
        // "Light dismiss": any press outside the popover closes it.
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _closePopover(),
          ),
        ),
        Positioned(
          top: _top,
          right: _right,
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: curved.drive(
                Tween(begin: const Offset(0, -0.04), end: Offset.zero),
              ),
              child: ScaleTransition(
                alignment: Alignment.topRight,
                scale: curved.drive(Tween(begin: 0.96, end: 1.0)),
                // Rasterised once; the transitions above just move/fade it.
                child: RepaintBoundary(
                  child: _StreakPopover(
                    controller: widget.controller,
                    theme: t,
                    arrowInset: arrowInset,
                    onClose: _closePopover,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Popover content
// ---------------------------------------------------------------------------

class _StreakPopover extends StatelessWidget {
  const _StreakPopover({
    required this.controller,
    required this.theme,
    required this.arrowInset,
    required this.onClose,
  });

  final StreakController controller;
  final StreakBadgeTheme theme;
  final double arrowInset;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final textTheme = Theme.of(context).textTheme;

    final titleStyle = (textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: t.mutedForeground,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    );

    final card = Container(
      width: t.popoverWidth,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
      decoration: BoxDecoration(
        color: t.popoverBackground,
        borderRadius: BorderRadius.circular(t.popoverRadius),
        border: Border.all(color: t.popoverBorder),
        boxShadow: t.shadows,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('YOUR DAILY STREAK USAGE', style: titleStyle),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close),
                iconSize: 16,
                color: t.mutedForeground,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Rows rebuild only when the streak data changes.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => _Stats(data: controller.data, theme: t),
            ),
          ),
        ],
      ),
    );

    return Material(
      type: MaterialType.transparency, // gives ink + default text style
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(top: t.arrowSize),
            child: card,
          ),
          Positioned(
            top: 0,
            right: arrowInset,
            child: CustomPaint(
              // +1px height so the arrow's base covers the card's top border.
              size: Size(t.arrowSize * 2, t.arrowSize + 1),
              painter: _ArrowPainter(
                fill: t.popoverBackground,
                border: t.popoverBorder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.data, required this.theme});

  final StreakData data;
  final StreakBadgeTheme theme;

  static String _days(int n) => n == 1 ? 'day' : 'days';

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final hasRange =
        data.longestStreakStartDate != null &&
        data.longestStreakEndDate != null;

    Widget divider() => Divider(height: 1, thickness: 1, color: t.divider);

    final children = <Widget>[
      _StatRow(
        theme: t,
        label: 'Current Streak',
        value: data.currentStreak > 0 ? '${data.currentStreak}' : '—',
        unit: data.currentStreak > 0 ? _days(data.currentStreak) : null,
      ),
      _StatRow(
        theme: t,
        label: 'Longest Streak',
        value: data.longestStreak > 0 ? '${data.longestStreak}' : '—',
        unit: data.longestStreak > 0 ? _days(data.longestStreak) : null,
        highlight: true,
      ),
      divider(),
      _StatRow(
        theme: t,
        label: 'First Day',
        value: _formatDate(data.firstDate),
      ),
      _StatRow(theme: t, label: 'Today', value: _formatDate(data.currentDate)),
      if (hasRange) ...[
        divider(),
        _StatRow(
          theme: t,
          label: 'Longest Run',
          value:
              '${_formatDate(data.longestStreakStartDate)}'
              ' → ${_formatDate(data.longestStreakEndDate)}',
          stacked: true, // value goes UNDER the label (long text)
        ),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: t.gap),
          children[i],
        ],
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.theme,
    required this.label,
    required this.value,
    this.unit,
    this.highlight = false,
    this.stacked = false,
  });

  final StreakBadgeTheme theme;
  final String label;
  final String value;
  final String? unit;
  final bool highlight;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final base = Theme.of(context).textTheme.bodySmall ?? const TextStyle();

    final labelStyle = base.copyWith(
      color: highlight ? t.rowHighlightForeground : t.mutedForeground,
      fontWeight: FontWeight.w500,
    );
    final valueStyle = base.copyWith(
      color: highlight ? t.rowHighlightForeground : t.foreground,
      fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
    );

    final valueText = Text.rich(
      TextSpan(
        text: value,
        style: valueStyle,
        children: [
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: valueStyle.copyWith(
                color: highlight ? t.rowHighlightForeground : t.mutedForeground,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      textAlign: stacked ? TextAlign.start : TextAlign.end,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? t.rowHighlightBackground : t.rowBackground,
        borderRadius: BorderRadius.circular(t.rowRadius),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: 4),
                valueText,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(width: 12),
                Expanded(child: valueText),
              ],
            ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.fill, required this.border});

  final Color fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);

    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.fill != fill || old.border != border;
}

// ---------------------------------------------------------------------------
// "YYYY-MM-DD" -> "Jul 3, 2026". Returns "—" for null/invalid.
// ---------------------------------------------------------------------------

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatDate(String? iso) {
  if (iso == null) return '—';
  final parts = iso.split('-');
  if (parts.length != 3) return '—';
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null || m < 1 || m > 12 || d < 1) {
    return '—';
  }
  return '${_months[m - 1]} $d, $y';
}
