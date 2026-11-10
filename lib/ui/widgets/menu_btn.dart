/* USAGE:

Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    MenuBtn(
      icon: const Icon(Icons.share),
      onPressed: _share,
      tooltip: 'Share',
      flipX: true,
      rotate: 1, // 1 = 90°, 2 = 180°, 3 = 270°, 4 = 360°
    ),
    const SizedBox(width: 8),
    MenuBtn(
      icon: const Icon(Icons.more_horiz),
      actions: [
        MenuAction(icon: const Icon(Icons.edit), label: 'Edit', onTap: _edit),
        MenuAction(icon: const Icon(Icons.delete), label: 'Delete', onTap: _delete),
      ],
    ),
  ],
)

The glass panel now sizes itself from the number of actions and the width of
the labels. To force a fixed size, pass backdropWidth / backdropHeight.

*/

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:dba2/core.dart';
import 'package:dba2/ui/widgets/ikon_btn.dart';

/// One entry in the menu (replaces each <li class="MenuBtn-item">).
class MenuAction {
  const MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final Widget icon; // Icon(...) or SvgPicture.asset(...) via flutter_svg
  final String label;
  final VoidCallback onTap;
}

class MenuBtn extends StatefulWidget {
  const MenuBtn({
    super.key,
    this.onPressed,
    this.icon = const Icon(Icons.more_horiz),
    this.tooltip,
    this.actions = const [],
    this.startRight = true, // stagger start position
    this.horizontalOffset = 20.0,
    // ---- Main Button Transformations ----
    this.flipX = false,
    this.flipY = false,
    this.rotate, // 1 to 4 quarter turns
    // ---- Buttons ----
    this.toggleSize = 25, // main (⋯) button
    this.itemSize = 25, // popped-out buttons
    this.iconSize = 16,
    this.iconColor, // null = IkonBtn default for the current mode
    this.buttonColor, // null = IkonBtn default for the current mode
    // ---- Labels (to the left of each item) ----
    this.showLabels = true,
    this.labelStyle, // null = small, iconColor
    this.labelGap = 8, // space between label and button
    // ---- Backdrop (glass panel) ----
    // null = automatic (fits the number of buttons / the widest label).
    this.backdropWidth,
    this.backdropHeight,
    // Auto-size tuning (only used when the size above is null):
    this.backdropTopPadding = 35, // empty space above the top button
    this.backdropSidePadding = 70, // extra width on top of label + button
    // How far the panel's RIGHT edge sticks out past the button's centre line.
    // Small value = panel extends left of the button (no block on the right).
    // null = panel centred on the button.
    this.backdropRightExtent = 70,
    // Extra nudge. dx > 0 right, dx < 0 left. dy > 0 down, dy < 0 up.
    this.backdropOffset = const Offset(0, -25),
    // null = automatic: the original rounded shape, scaled to the panel height.
    this.backdropRadius,
    this.backdropColor, // tint. null = theme scrim (black)
    this.backdropOpacity = 0.3, // tint strength 0.0 - 1.0 (lower = more glass)
    this.blur = 8, // glass blur sigma, 0 = off
    // ---- Soft edge shadow (tapers the hard edge) ----
    this.edgeShadowBlur = 20, // 0 = off; bigger = softer/wider
    this.edgeShadowOpacity = 0.7,
    this.edgeShadowColor, // null = black
  }) : assert(
         actions.length == 0 || onPressed == null,
         'Use either actions (menu mode) or onPressed (normal mode), not both.',
       ),
       assert(
         rotate == null || (rotate >= 1 && rotate <= 4),
         'rotate must be a value between 1 and 4.',
       );

  final VoidCallback? onPressed; // normal mode
  final Widget icon; // main button icon, either mode
  final String? tooltip;

  final bool startRight;
  final double horizontalOffset;

  // New transformation properties for the main button icon
  final bool flipX;
  final bool flipY;
  final int? rotate;

  final List<MenuAction> actions;
  final double toggleSize, itemSize, iconSize;
  final Color? iconColor, buttonColor;
  final bool showLabels;
  final TextStyle? labelStyle;
  final double labelGap;
  final double? backdropWidth, backdropHeight;
  final double backdropTopPadding, backdropSidePadding;
  final double? backdropRightExtent;
  final Offset backdropOffset;
  final BorderRadiusGeometry? backdropRadius;
  final Color? backdropColor;
  final double backdropOpacity, blur;
  final double edgeShadowBlur, edgeShadowOpacity;
  final Color? edgeShadowColor;

  @override
  State<MenuBtn> createState() => _MenuBtnState();
}

class _MenuBtnState extends State<MenuBtn> with SingleTickerProviderStateMixin {
  // CSS constants from MenuItems.css
  static const _gap = 80.0; // --gap
  static const _stagger = 10.0; // --stagger (1rem)
  static const _initialDistance = 0.2; // --initial-distance
  static const _itemDuration = 0.3; // seconds per item
  static const _itemDelayStep = 0.05; // seconds between items
  static const _backdropDuration = 0.6; // seconds
  static const _labelWidth = 120.0;

  // The panel shape was originally tuned for a 270px tall panel.
  static const _referenceHeight = 270.0;

  double get _totalSeconds {
    if (widget.actions.isEmpty) return _backdropDuration;
    final items = (widget.actions.length - 1) * _itemDelayStep + _itemDuration;
    return items > _backdropDuration ? items : _backdropDuration;
  }

  /// Panel height: fixed if the caller gave one, otherwise just tall enough
  /// to reach past the top-most button.
  double get _backdropHeight {
    if (widget.backdropHeight != null) return widget.backdropHeight!;
    final n = widget.actions.length;
    if (n == 0) return 0;

    // Distance from the toggle's centre up to the top button's centre.
    final topItemY = (_initialDistance + 0.5 + (n - 1) * 0.5) * _gap;

    // The panel's bottom edge sits at the toggle's bottom edge, moved by
    // backdropOffset.dy (negative dy = moves up).
    return topItemY +
        widget.itemSize / 2 +
        widget.toggleSize / 2 +
        widget.backdropOffset.dy +
        widget.backdropTopPadding;
  }

  /// Panel width: fixed if the caller gave one, otherwise fits the widest label.
  double get _backdropWidth {
    if (widget.backdropWidth != null) return widget.backdropWidth!;

    double widest = 0;
    if (widget.showLabels) {
      final style = widget.labelStyle ?? const TextStyle(fontSize: 11);
      for (final a in widget.actions) {
        final tp = TextPainter(
          text: TextSpan(text: a.label, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        if (tp.width > widest) widest = tp.width;
      }
      widest += widget.labelGap;
    }
    return widest + widget.itemSize + widget.backdropSidePadding;
  }

  /// Panel corners: fixed if the caller gave one, otherwise the original
  /// shape scaled down for short panels so it keeps a similar look.
  BorderRadiusGeometry get _backdropRadius {
    if (widget.backdropRadius != null) return widget.backdropRadius!;
    final k = (_backdropHeight / _referenceHeight).clamp(0.4, 1.0);
    return BorderRadius.only(
      topLeft: Radius.circular(220 * k),
      topRight: Radius.circular(220 * k),
      bottomLeft: Radius.circular(270 * k),
      bottomRight: Radius.circular(50 * k),
    );
  }

  final _portal = OverlayPortalController();
  final _link = LayerLink(); // == anchor-name / position-anchor
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_totalSeconds * 1000).round()),
  );

  void _open() {
    _portal.show();
    _c.forward();
  }

  Future<void> _close() async {
    if (_c.status == AnimationStatus.reverse) return;
    await _c.reverse();
    if (mounted) _portal.hide();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _isMenu => widget.actions.isNotEmpty;

  @override
  void didUpdateWidget(MenuBtn old) {
    super.didUpdateWidget(old);
    if (old.actions.length != widget.actions.length) {
      _c.duration = Duration(milliseconds: (_totalSeconds * 1000).round());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apply transformations (flipX, flipY, rotate) exclusively to the main button's icon
    Widget mainIcon = widget.icon;
    if (widget.flipX || widget.flipY || widget.rotate != null) {
      final double angle = widget.rotate != null
          ? ((widget.rotate! % 4) * (math.pi / 2))
          : 0.0;
      mainIcon = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scaleByDouble(
            widget.flipX ? -1.0 : 1.0,
            widget.flipY ? -1.0 : 1.0,
            1.0,
            1.0,
          )
          ..rotateZ(angle),
        child: widget.icon,
      );
    }

    // IkonBtn supplies the neumorphic look + optical centering, and shows
    // the tooltip itself.
    final button = IkonBtn(
      size: widget.toggleSize,
      iconSize: widget.iconSize,
      iconColor: widget.iconColor,
      buttonColor: widget.buttonColor,
      tooltip: widget.tooltip,
      onPressed: _isMenu ? _open : widget.onPressed, // null = disabled
      icon: mainIcon,
    );

    // Normal mode: no overlay, no link, just a button.
    if (!_isMenu) return button;

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: CompositedTransformTarget(link: _link, child: button),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backdropT = CurvedAnimation(
      parent: _c,
      curve: Interval(0, _backdropDuration / _totalSeconds, curve: Curves.ease),
    );

    // Work these out once per build (not on every animation frame).
    final panelWidth = _backdropWidth;
    final panelHeight = _backdropHeight;
    final panelRadius = _backdropRadius;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Full-screen tap catcher (tap anywhere to dismiss)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
            ),
          ),
          // Glass backdrop panel, grows upward from the button
          IgnorePointer(
            child: CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomCenter,
              followerAnchor: widget.backdropRightExtent == null
                  ? Alignment.bottomCenter
                  : Alignment.bottomRight,
              offset:
                  widget.backdropOffset +
                  Offset(widget.backdropRightExtent ?? 0, 0),
              child: AnimatedBuilder(
                animation: backdropT,
                builder: (_, _) => _GlassPanel(
                  width: panelWidth,
                  height: panelHeight * backdropT.value,
                  radius: panelRadius,
                  tint: (widget.backdropColor ?? context.colorScheme.surface)
                      .withValues(alpha: widget.backdropOpacity),
                  blur: widget.blur,
                  shadowBlur: widget.edgeShadowBlur,
                  shadowColor:
                      (widget.edgeShadowColor ?? context.colorScheme.surface)
                          .withValues(alpha: widget.edgeShadowOpacity),
                ),
              ),
            ),
          ),
          for (var i = 0; i < widget.actions.length; i++) _buildItem(i, scheme),
        ],
      ),
    );
  }

  Widget _buildItem(int index, ColorScheme scheme) {
    final action = widget.actions[index];

    // CSS: --i = 0.5, 1, 1.5 ...; --delay = 0.1s * index
    final i = 0.5 + index * 0.5;
    final delay = index * _itemDelayStep;

    // Check our new switch to flip the starting side
    final flipMultiplier = widget.startRight ? -1.0 : 1.0;
    final s = (index.isEven ? 1.0 : -1.0) * flipMultiplier;

    // direction = 90deg (north): x = zigzag offset, y = distance upward
    final target = Offset(
      (-s * _stagger) + widget.horizontalOffset,
      -(_initialDistance + i) * _gap,
    );

    final t = CurvedAnimation(
      parent: _c,
      curve: Interval(
        (delay / _totalSeconds).clamp(0.0, 1.0),
        ((delay + _itemDuration) / _totalSeconds).clamp(0.0, 1.0),
        curve: Curves.linear, // we shape x, y and fade ourselves below
      ),
    );

    return AnimatedBuilder(
      animation: t,
      builder: (_, child) {
        final p = t.value;
        final x = Curves.easeOutCubic.transform(
          p,
        ); // sideways: fast, settles early
        final y = Curves.easeOutBack.transform(
          p,
        ); // upward: overshoots, then settles
        final fade = (p * 6).clamp(0.0, 1.0); // visible almost immediately

        return CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.center,
          followerAnchor: Alignment.centerRight,
          offset:
              Offset(target.dx * x, target.dy * y) +
              Offset(widget.itemSize / 2, 0),
          child: Opacity(
            opacity: fade,
            child: Transform.scale(
              scale: 0.5 + 0.5 * Curves.easeOut.transform(p),
              alignment: Alignment.centerRight,
              child: child,
            ),
          ),
        );
      },
      child: Semantics(
        label: action.label,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            action.onTap();
            _close();
          },
          child: SizedBox(
            width: widget.showLabels
                ? _labelWidth + widget.labelGap + widget.itemSize
                : widget.itemSize,
            height: widget.itemSize,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.showLabels) ...[
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        action.label,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style:
                            widget.labelStyle ??
                            TextStyle(
                              fontSize: 11,
                              color: context.colorScheme.inversePrimary,
                            ),
                      ),
                    ),
                  ),
                  SizedBox(width: widget.labelGap),
                ],
                // Visual only: the GestureDetector above handles the tap.
                IkonBtn(
                  size: widget.itemSize,
                  iconSize: widget.iconSize,
                  iconColor: widget.iconColor,
                  icon: action.icon,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted-glass panel: blur + tint, with a soft shadow painted only OUTSIDE
/// the shape so it tapers the edge without muddying the glass.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.width,
    required this.height,
    required this.radius,
    required this.tint,
    required this.blur,
    required this.shadowBlur,
    required this.shadowColor,
  });
  final double width, height, blur, shadowBlur;
  final BorderRadiusGeometry radius;
  final Color tint, shadowColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (shadowBlur > 0)
            Positioned.fill(
              child: ClipPath(
                clipper: _OutsideClipper(radius, shadowBlur * 3),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: [
                      BoxShadow(color: shadowColor, blurRadius: shadowBlur),
                    ],
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: ColoredBox(color: tint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clips to everything EXCEPT the panel shape (so the shadow only shows outside).
class _OutsideClipper extends CustomClipper<Path> {
  _OutsideClipper(this.radius, this.margin);
  final BorderRadiusGeometry radius;
  final double margin;

  @override
  Path getClip(Size size) {
    final rect = Offset.zero & size;
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(margin))
      ..addRRect(radius.resolve(TextDirection.ltr).toRRect(rect));
  }

  @override
  bool shouldReclip(_OutsideClipper old) => true;
}
