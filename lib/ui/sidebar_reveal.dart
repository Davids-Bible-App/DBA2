// lib/ui/sidebar_reveal.dart
import 'package:dba2/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dba2/state/overlay_lock.dart';

enum SidebarSide { left, right }

class SidebarReveal extends StatefulWidget {
  const SidebarReveal({
    super.key,
    required this.child,
    this.leftSidebar,
    this.rightSidebar,
    this.openFraction = 0.85,
    this.dragZoneWidth = 50,
    this.sidebarSpeedFactor = 1 / 3,
    this.showHint = false,
    this.dragZoneTopInset = kToolbarHeight,
    this.dragZoneBottomInset = 0,

    this.fadeIn = false,
    this.fadeStartOpacity = 0.3,
    this.fadeEndOpacity = 1.0,
  });

  final Widget child;
  final Widget? leftSidebar;
  final Widget? rightSidebar;
  final double openFraction;
  final double dragZoneWidth; // clamped to 50
  final double sidebarSpeedFactor;
  final bool showHint;
  final double dragZoneTopInset;
  final double dragZoneBottomInset;

  final bool fadeIn;
  final double fadeStartOpacity; // opacity when the sidebar starts to open
  final double fadeEndOpacity; // opacity when fully open

  static SidebarRevealState of(BuildContext context) {
    final state = context.findAncestorStateOfType<SidebarRevealState>();
    assert(state != null, 'No SidebarReveal found in context');
    return state!;
  }

  @override
  State<SidebarReveal> createState() => SidebarRevealState();
}

class SidebarRevealState extends State<SidebarReveal>
    with SingleTickerProviderStateMixin {
  // progress: 0 = closed, 1 = fully open. _side says which sidebar.
  late final AnimationController _controller;
  SidebarSide _side = SidebarSide.left;
  SidebarSide? _dragSide;
  double _openWidth = 0;
  int _request = 0; // invalidates stale async sequences

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, value: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _dir(SidebarSide s) => s == SidebarSide.left ? 1.0 : -1.0;

  // ---- Public API ----
  void openLeft() => _open(SidebarSide.left);
  void openRight() => _open(SidebarSide.right);
  void close() {
    _request++;
    _animateTo(0);
  }

  void toggleLeft() => _toggle(SidebarSide.left);
  void toggleRight() => _toggle(SidebarSide.right);

  bool _isOpenOrOpening(SidebarSide s) =>
      _side == s && (_controller.value > 0.01) && _targetIsOpen;

  bool _targetIsOpen = false;

  void _toggle(SidebarSide s) {
    if (_isOpenOrOpening(s)) {
      close();
    } else {
      _open(s);
    }
  }

  Future<void> _open(SidebarSide s) async {
    if (overlayLocks.value > 0) return;
    final request = ++_request;
    if (_side != s && _controller.value > 0.001) {
      // Other sidebar is showing: glide back to center first.
      await _animateTo(0);
      if (request != _request || !mounted) return;
    }
    if (_side != s) setState(() => _side = s);
    await _animateTo(1);
  }

  TickerFuture _animateTo(double target) {
    _targetIsOpen = target == 1;
    final remaining = (target - _controller.value).abs();
    if (remaining < 0.001) {
      _controller.value = target;
      return TickerFuture.complete();
    }
    return _controller.animateTo(
      target,
      duration: Duration(
        milliseconds: (320 * remaining).clamp(120.0, 320.0).round(),
      ),
      curve: Curves.easeOutCubic,
    );
  }

  // ---- Shared drag logic ----
  void _onDragStart(SidebarSide s) {
    if (overlayLocks.value > 0) return;
    // Ignore a grab on the far strip while the other sidebar is open.
    if (_controller.value > 0.01 && _side != s) {
      _dragSide = null;
      return;
    }
    _request++;
    _controller.stop();
    _dragSide = s;
    if (_side != s) setState(() => _side = s);
  }

  void _onDragUpdate(SidebarSide s, DragUpdateDetails d) {
    if (_dragSide != s || _openWidth == 0) return;
    _controller.value = (_controller.value + d.delta.dx * _dir(s) / _openWidth)
        .clamp(0.0, 1.0);
  }

  void _onDragEnd(SidebarSide s, DragEndDetails d) {
    if (_dragSide != s) return;
    _dragSide = null;
    final velocity = (d.primaryVelocity ?? 0) * _dir(s); // + = opening
    final open = velocity.abs() > 300 ? velocity > 0 : _controller.value > 0.5;
    _animateTo(open ? 1 : 0);
  }

  void _onDragCancel(SidebarSide s) {
    if (_dragSide != s) return;
    _dragSide = null;
    _animateTo(_controller.value > 0.5 ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyB, control: true):
              toggleLeft,
          const SingleActivator(
            LogicalKeyboardKey.keyB,
            control: true,
            shift: true,
          ): toggleRight,
          const SingleActivator(LogicalKeyboardKey.escape): close,
        },
        child: LayoutBuilder(builder: _buildLayers),
      ),
    );
  }

  Widget _buildLayers(BuildContext context, BoxConstraints constraints) {
    _openWidth = constraints.maxWidth * widget.openFraction;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    return ColoredBox(
      color: isWindows ? Colors.black : Colors.transparent,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final p = _controller.value; // 0..1
          final dir = _dir(_side);
          final appOffset = p * _openWidth * dir;
          final isOpen = p > 0.01;

          // Parallax: sidebars travel at sidebarSpeedFactor of the app's speed
          // and end flush at 0 when fully open.
          final slack = (1 - p) * _openWidth * widget.sidebarSpeedFactor;
          final leftOffset = -slack;
          final rightOffset = slack;

          final sidebarOpacity = widget.fadeIn
              ? (widget.fadeStartOpacity +
                        (widget.fadeEndOpacity - widget.fadeStartOpacity) * p)
                    .clamp(0.0, 1.0)
              : 1.0;

          final showLeft = _side == SidebarSide.left && p > 0;
          final showRight = _side == SidebarSide.right && p > 0;

          return Stack(
            children: [
              if (widget.leftSidebar != null)
                Positioned(
                  key: const ValueKey('left-sidebar'),
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _openWidth, // only the revealed area
                  child: TickerMode(
                    enabled: showLeft,
                    child: Offstage(
                      offstage: !showLeft,
                      child: Transform.translate(
                        offset: Offset(leftOffset, 0),
                        child: Opacity(
                          opacity: sidebarOpacity,
                          child: widget.leftSidebar,
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.rightSidebar != null)
                Positioned(
                  key: const ValueKey('right-sidebar'),
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: _openWidth, // only the revealed area
                  child: Offstage(
                    offstage: !showRight,
                    child: Transform.translate(
                      offset: Offset(rightOffset, 0),
                      child: Opacity(
                        opacity: sidebarOpacity,
                        child: widget.rightSidebar,
                      ),
                    ),
                  ),
                ),

              Transform.translate(
                offset: Offset(appOffset, 0),
                child: RepaintBoundary(
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 16,
                            spreadRadius: 2,
                            offset: Offset(-4 * dir, 0),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: AbsorbPointer(
                              absorbing: isOpen,
                              child: widget.child,
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: !isOpen,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: close,
                              ),
                            ),
                          ),
                          if (widget.leftSidebar != null)
                            _edgeStrip(SidebarSide.left),
                          if (widget.rightSidebar != null)
                            _edgeStrip(SidebarSide.right),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _edgeStrip(SidebarSide side) {
    final width = widget.dragZoneWidth.clamp(0.0, 50.0);
    return Positioned(
      key: ValueKey('strip-$side'),
      left: side == SidebarSide.left ? 0 : null,
      right: side == SidebarSide.right ? 0 : null,
      top: widget.dragZoneTopInset,
      bottom: widget.dragZoneBottomInset,
      width: width,
      child: ValueListenableBuilder<int>(
        valueListenable: overlayLocks,
        builder: (_, locks, child) =>
            IgnorePointer(ignoring: locks > 0, child: child),
        child: MouseRegion(
          cursor: SystemMouseCursors.basic,
          opaque: false,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _onDragStart(side),
            onHorizontalDragUpdate: (d) => _onDragUpdate(side, d),
            onHorizontalDragEnd: (d) => _onDragEnd(side, d),
            onHorizontalDragCancel: () => _onDragCancel(side),
            child: widget.showHint
                ? const _DragHint()
                : const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _DragHint extends StatelessWidget {
  const _DragHint();

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.onSurface.withValues(alpha: 0.35);

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: kToolbarHeight + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz, size: 28, color: color),
              const SizedBox(height: 8),
              for (final letter in 'DRAG'.split(''))
                Text(
                  letter,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    letterSpacing: 1,
                    color: color,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
