import 'package:flutter/material.dart';

/// One place for app-wide component styling. Call [apply] from AppTheme.
/// Colours come from the ColorScheme, so light/dark follow automatically
/// (and update live when the theme changes).
abstract final class ComponentThemes {
  static ThemeData apply(ThemeData base) {
    // final dark = base.colorScheme.brightness == Brightness.dark;
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
  static SwitchThemeData _switch(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;

    return SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? (isDark ? Colors.grey[900] : Colors.white)
            : (isDark ? const Color(0xFF2a2a2a) : Colors.white54),
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? (isDark ? Colors.white30 : Colors.grey.shade400)
            : (isDark ? Colors.white24 : Colors.grey.shade400),
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? (isDark ? Colors.white24 : Colors.black26)
            : (isDark ? Colors.grey[700] : Colors.black26),
      ),
      thumbIcon: WidgetStateProperty.resolveWith((s) {
        final on = s.contains(WidgetState.selected);
        return Icon(
          on ? Icons.check : Icons.close,
          color: on
              ? (isDark ? Colors.white70 : Colors.white)
              : (isDark ? Colors.white38 : Colors.white70),
        );
      }),
    );
  }
}
