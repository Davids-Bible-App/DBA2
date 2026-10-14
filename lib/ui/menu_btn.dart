// lib/ui/menu_btn.dart
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

*/

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:dba2/core.dart';

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
    this.toggleSize = 20, // main (⋯) button
    this.itemSize = 20, // popped-out buttons
    this.iconSize = 16,
    this.iconColor, // null = theme onSurface
    this.buttonColor, // null = dark/light default grey
    // ---- Labels (to the left of each item) ----
    this.showLabels = true,
    this.labelStyle, // null = small, iconColor
    this.labelGap = 8, // space between label and button
    // ---- Backdrop (fixed-size glass panel) ----
    this.backdropWidth = 160,
    this.backdropHeight = 270,
    // How far the panel's RIGHT edge sticks out past the button's centre line.
    // Small value = panel extends left of the button (no block on the right).
    // null = panel centred on the button.
    this.backdropRightExtent = 70,
    // Extra nudge. dx > 0 right, dx < 0 left. dy > 0 down, dy < 0 up.
    this.backdropOffset = const Offset(0, -25),
    this.backdropRadius = const BorderRadius.only(
      topLeft: Radius.circular(150),
      topRight: Radius.circular(220),
      bottomLeft: Radius.circular(270),
      bottomRight: Radius.circular(50),
    ),
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
  final double backdropWidth, backdropHeight;
  final double? backdropRightExtent;
  final Offset backdropOffset;
  final BorderRadiusGeometry backdropRadius;
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
  static const _initialDistance = 0.15; // --initial-distance
  static const _itemDuration = 0.3; // seconds per item
  static const _itemDelayStep = 0.05; // seconds between items
  static const _backdropDuration = 0.6; // seconds
  static const _labelWidth = 120.0;

  late final double _totalSeconds = () {
    if (widget.actions.isEmpty) return _backdropDuration;
    final items = (widget.actions.length - 1) * _itemDelayStep + _itemDuration;
    return items > _backdropDuration ? items : _backdropDuration;
  }();

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
          ..scale(widget.flipX ? -1.0 : 1.0, widget.flipY ? -1.0 : 1.0)
          ..rotateZ(angle),
        child: widget.icon,
      );
    }

    final button = _CircleButton(
      size: widget.toggleSize,
      iconSize: widget.iconSize,
      iconColor: widget.iconColor,
      color: widget.buttonColor,
      onTap: _isMenu ? _open : widget.onPressed, // null = disabled
      child: mainIcon,
    );

    final labelled = widget.tooltip == null
        ? button
        : Tooltip(message: widget.tooltip!, child: button);

    // Normal mode: no overlay, no link, just a button.
    if (!_isMenu) return labelled;

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: CompositedTransformTarget(link: _link, child: labelled),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backdropT = CurvedAnimation(
      parent: _c,
      curve: Interval(0, _backdropDuration / _totalSeconds, curve: Curves.ease),
    );

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
                  width: widget.backdropWidth,
                  height: widget.backdropHeight * backdropT.value,
                  radius: widget.backdropRadius,
                  tint: (widget.backdropColor ?? context.colorScheme.surface)
                      .withValues(
                        alpha: widget.backdropOpacity,
                      ),
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
        delay / _totalSeconds,
        (delay + _itemDuration) / _totalSeconds,
        curve: Curves.easeOutQuart,
      ),
    );

    return AnimatedBuilder(
      animation: t,
      builder: (_, child) => CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.center,
        followerAnchor: Alignment.center,
        offset: Offset.lerp(Offset.zero, target, t.value)!,
        child: Opacity(
          opacity: t.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.5 + 0.5 * t.value, child: child),
        ),
      ),
      child: Semantics(
        label: action.label,
        button: true,
        // Stack is only as big as the button; the label overflows to its left
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _CircleButton(
              size: widget.itemSize,
              iconSize: widget.iconSize,
              iconColor: widget.iconColor,
              color: context.colorScheme.secondary,
              onTap: () {
                action.onTap();
                _close(); // menu closes after any item is pressed
              },
              child: action.icon,
            ),
            if (widget.showLabels)
              Positioned(
                right: widget.itemSize + widget.labelGap,
                top: 0,
                bottom: 0,
                width: _labelWidth,
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      action.label,
                      softWrap: false,
                      style:
                          widget.labelStyle ??
                          TextStyle(
                            fontSize: 11,
                            color: context.colorScheme.inversePrimary,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Stand-in for `.neu-button` (round, subtle shadow).
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.size,
    required this.iconSize,
    required this.onTap,
    required this.child,
    this.iconColor,
    this.color,
  });
  final double size, iconSize;
  final Color? iconColor, color;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.colorScheme.secondary,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.5 : 0.15),
              blurRadius: 6,
              offset: const Offset(2, 2),
            ),
          ],
        ),
        // Forces icon colour/size (overlay can lose the app's IconTheme)
        child: IconTheme(
          data: IconThemeData(
            color: iconColor ?? context.colorScheme.inversePrimary,
            size: iconSize,
          ),
          child: child,
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
