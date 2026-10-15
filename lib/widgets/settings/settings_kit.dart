// lib/widgets/settings/settings_kit.dart
//
// A tiny Material 3 "settings kit". Add to pubspec first:
//   flutter pub add animations
//
// Usage:
//   SettingsSection(title: 'Reading', children: [
//     SettingsSwitchTile(icon: Icons.push_pin_outlined, title: '...', value: v, onChanged: f),
//     SettingsNavTile(icon: Icons.info_outline, title: 'About', pageBuilder: (_) => const AboutPage()),
//     SettingsButtonTile(title: 'Reset', buttonLabel: 'Reset', onPressed: () {}),
//   ]);

import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Motion: Material 3 Expressive uses springs. "Low stiffness" ≈ 200 (the same
// value as Compose's StiffnessLow). Lower stiffness = slower, softer settle.
// ─────────────────────────────────────────────────────────────────────────────

/// A [Curve] driven by a real spring simulation. May overshoot past 1.0,
/// so use it for scale/position, NOT opacity.
class SpringCurve extends Curve {
  SpringCurve({
    this.stiffness = 200, // low
    this.dampingRatio = 0.8, // <1 = a little bounce, 1 = none
    this.duration = const Duration(milliseconds: 700),
  }) : _sim = SpringSimulation(
         SpringDescription.withDampingRatio(
           mass: 1,
           stiffness: stiffness,
           ratio: dampingRatio,
         ),
         0,
         1,
         0,
       );

  final double stiffness;
  final double dampingRatio;
  final Duration duration;
  final SpringSimulation _sim;

  @override
  double transformInternal(double t) =>
      _sim.x(t * duration.inMilliseconds / 1000);
}

abstract final class Motion {
  /// Spatial spring: movement and size. Gentle bounce.
  static final spatial = SpringCurve(stiffness: 200, dampingRatio: 0.8);

  /// Playful variant for small, delightful things.
  static final bouncy = SpringCurve(stiffness: 200, dampingRatio: 0.55);

  static const duration = Duration(milliseconds: 700);
}

// ─────────────────────────────────────────────────────────────────────────────
// Entrance animation: fade + spring slide, staggered by [index].
// ─────────────────────────────────────────────────────────────────────────────

class SpringIn extends StatefulWidget {
  const SpringIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<SpringIn> createState() => _SpringInState();
}

class _SpringInState extends State<SpringIn> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.06),
      duration: Motion.duration,
      curve: Motion.spatial,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sections and groups
// ─────────────────────────────────────────────────────────────────────────────

/// Header label + a group of tiles. This is the main thing you'll add to.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        SettingsGroup(children: children),
      ],
    );
  }
}

/// Stacks tiles with tiny gaps; outer corners large, inner corners small
/// (the M3 Expressive "connected list" look).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  static const _outer = Radius.circular(24);
  static const _inner = Radius.circular(6);

  BorderRadius _radiusFor(int i, int n) {
    if (n == 1) return const BorderRadius.all(_outer);
    if (i == 0) {
      return const BorderRadius.vertical(top: _outer, bottom: _inner);
    }
    if (i == n - 1) {
      return const BorderRadius.vertical(top: _inner, bottom: _outer);
    }
    return const BorderRadius.all(_inner);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: _GroupPosition(
              radius: _radiusFor(i, children.length),
              child: children[i],
            ),
          ),
      ],
    );
  }
}

class _GroupPosition extends InheritedWidget {
  const _GroupPosition({required this.radius, required super.child});

  final BorderRadius radius;

  static BorderRadius of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GroupPosition>()?.radius ??
      BorderRadius.circular(24);

  @override
  bool updateShouldNotify(_GroupPosition old) => radius != old.radius;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tiles
// ─────────────────────────────────────────────────────────────────────────────

/// Row layout shared by every tile.
class _TileContent extends StatelessWidget {
  const _TileContent({
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: cs.onSurfaceVariant),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tt.titleMedium),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 16),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Base tile: tonal surface, ink ripple, springy press-scale.
class SettingsTile extends StatefulWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: Motion.duration,
      curve: Motion.spatial,
      child: Material(
        color: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: _GroupPosition.of(context)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          child: _TileContent(
            title: widget.title,
            subtitle: widget.subtitle,
            icon: widget.icon,
            trailing: widget.trailing,
          ),
        ),
      ),
    );
  }
}

/// Material 3 switch (with check/close thumb icons). Whole tile is tappable.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.style,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Optional per-tile switch look. When null, the app's ThemeData.switchTheme
  /// is used. NOTE: replaces the theme's switch style for this tile (no merge).
  final SwitchThemeData? style;

  Widget _withStyle(Widget switchWidget) => style == null
      ? switchWidget
      : SwitchTheme(data: style!, child: switchWidget);

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      onTap: () => onChanged(!value),
      trailing: _withStyle(
        Switch(
          value: value,
          onChanged: onChanged,
          // thumbIcon: WidgetStateProperty.resolveWith(
          //   (states) => Icon(
          //     states.contains(WidgetState.selected) ? Icons.check : Icons.close,
          //   ),
          // ),
        ),
      ),
    );
  }
}

/// A tile with a real Material button on the right.
class SettingsButtonTile extends StatelessWidget {
  const SettingsButtonTile({
    super.key,
    required this.title,
    required this.buttonLabel,
    required this.onPressed,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      trailing: FilledButton.tonal(
        onPressed: onPressed,
        child: Text(buttonLabel),
      ),
    );
  }
}

/// Tile that opens a sub-page using a Material **container transform**:
/// the tile itself grows into the new page.
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.title,
    required this.pageBuilder,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final WidgetBuilder pageBuilder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OpenContainer<void>(
      transitionType: ContainerTransitionType.fade,
      transitionDuration: const Duration(milliseconds: 550),
      closedElevation: 0,
      openElevation: 0,
      closedColor: cs.surfaceContainerHigh,
      openColor: cs.surface,
      middleColor: cs.surfaceContainerHigh,
      closedShape: RoundedRectangleBorder(
        borderRadius: _GroupPosition.of(context),
      ),
      closedBuilder: (context, open) => InkWell(
        onTap: open,
        child: _TileContent(
          title: title,
          subtitle: subtitle,
          icon: icon,
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ),
      ),
      openBuilder: (context, _) => pageBuilder(context),
    );
  }
}

/// M3 dropdown: whole tile opens a [MenuAnchor] menu under the current value.
/// Replaces the old-style DropdownButton.
class SettingsDropdownTile<T> extends StatefulWidget {
  const SettingsDropdownTile({
    super.key,
    required this.title,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  State<SettingsDropdownTile<T>> createState() =>
      _SettingsDropdownTileState<T>();
}

class _SettingsDropdownTileState<T> extends State<SettingsDropdownTile<T>> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SettingsTile(
      title: widget.title,
      subtitle: widget.subtitle,
      icon: widget.icon,
      onTap: () => _menu.isOpen ? _menu.close() : _menu.open(),
      trailing: MenuAnchor(
        controller: _menu,
        alignmentOffset: const Offset(0, 4),
        menuChildren: [
          for (final item in widget.items)
            MenuItemButton(
              leadingIcon: Icon(
                item == widget.value ? Icons.check : null,
                size: 20,
              ),
              onPressed: () => widget.onChanged(item),
              child: Text(widget.labelOf(item)),
            ),
        ],
        builder: (context, controller, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.labelOf(widget.value),
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: cs.inversePrimary),
            ),
            Icon(Icons.arrow_drop_down, color: cs.inversePrimary),
          ],
        ),
      ),
    );
  }
}
