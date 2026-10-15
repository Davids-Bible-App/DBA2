// lib/themes/component_themes.dart
import 'package:flutter/material.dart';

/// One place for app-wide component styling. Call [apply] from AppTheme.
/// Colours come from the ColorScheme, so light/dark follow automatically
/// (and update live when the theme changes).
abstract final class ComponentThemes {
  static ThemeData apply(ThemeData base) {
    final cs = base.colorScheme;
    return base.copyWith(
      filledButtonTheme: FilledButtonThemeData(style: _shapeAndSize()),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _elevated(cs)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _outlined(cs)),
      textButtonTheme: TextButtonThemeData(style: _text(cs)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      switchTheme: _switch(cs),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.secondary,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: cs.outline,
      ),
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static WidgetStateProperty<T> _enabledElse<T>(T enabled, T disabled) =>
      WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? disabled : enabled,
      );

  /// Shared by every button: pill shape that morphs to a softer rounded
  /// rectangle while pressed (M3 Expressive feel), roomier size.
  /// NO colours here on purpose, see the note on FilledButton below.
  static ButtonStyle _shapeAndSize() => ButtonStyle(
    animationDuration: const Duration(milliseconds: 350),
    minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 24),
    ),
    shape: WidgetStateProperty.resolveWith<OutlinedBorder?>(
      (s) => s.contains(WidgetState.pressed)
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
          : const StadiumBorder(),
    ),
  );

  // ── buttons ──────────────────────────────────────────────────────────────
  //
  // FilledButton: theme sets shape/size only. FilledButton.tonal shares the
  // same theme object, so setting a colour here would recolour tonal buttons
  // too. Colours come from the scheme instead:
  //   filled → primary / onPrimary
  //   tonal  → secondaryContainer / onSecondaryContainer

  /// Your M3 default would be surfaceContainerLow, which is mid-grey in your
  /// dark scheme, so set it explicitly.
  static ButtonStyle _elevated(ColorScheme cs) => _shapeAndSize().copyWith(
    backgroundColor: _enabledElse<Color?>(
      cs.surfaceContainerHigh,
      cs.onSurface.withValues(alpha: 0.12),
    ),
    foregroundColor: _enabledElse<Color?>(
      cs.onSurface,
      cs.onSurface.withValues(alpha: 0.38),
    ),
  );

  /// Foreground is onSurface rather than primary: your dark `primary` is
  /// mid-grey, which is weak as *text* on a dark surface.
  static ButtonStyle _outlined(ColorScheme cs) => _shapeAndSize().copyWith(
    foregroundColor: _enabledElse<Color?>(
      cs.onSurface,
      cs.onSurface.withValues(alpha: 0.38),
    ),
    side: _enabledElse<BorderSide?>(
      BorderSide(color: cs.outline),
      BorderSide(color: cs.onSurface.withValues(alpha: 0.12)),
    ),
  );

  static ButtonStyle _text(ColorScheme cs) => _shapeAndSize().copyWith(
    foregroundColor: _enabledElse<Color?>(
      cs.onSurface,
      cs.onSurface.withValues(alpha: 0.38),
    ),
  );

  // ── switch ───────────────────────────────────────────────────────────────
  //
  // Picked so it reads in your grey palette:
  //   on : primary track, onPrimary thumb, onSurface icon
  //   off: dark/light inset track with an outline, outline-coloured thumb
  static SwitchThemeData _switch(ColorScheme cs) => SwitchThemeData(
    trackColor: WidgetStateProperty.resolveWith(
      (s) =>
          s.contains(WidgetState.selected) ? cs.primary : cs.surfaceContainer,
    ),
    trackOutlineColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.selected) ? Colors.transparent : cs.outline,
    ),
    thumbColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.selected) ? cs.onPrimary : cs.outline,
    ),
    thumbIcon: WidgetStateProperty.resolveWith((s) {
      final on = s.contains(WidgetState.selected);
      return Icon(
        on ? Icons.check : Icons.close,
        color: on ? cs.onSurface : cs.surfaceContainer,
      );
    }),
  );
}
