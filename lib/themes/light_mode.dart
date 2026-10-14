// lib/themes/light_mode.dart
import 'package:flutter/material.dart';

final ColorScheme lightScheme =
    ColorScheme.fromSeed(
      seedColor: Colors.amber,
      brightness: Brightness.light,
    ).copyWith(
      // Accent roles
      primary: Colors.grey.shade800,
      onPrimary: Colors.white,
      primaryContainer: Colors.grey.shade200,
      onPrimaryContainer: Colors.black,
      inversePrimary: Colors.grey.shade600,

      secondary: Colors.grey.shade200,
      onSecondary: Colors.white,
      secondaryContainer: Colors.grey.shade500,
      onSecondaryContainer: Colors.grey.shade900,

      tertiary: Colors.black12,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFF632D04),
      onTertiaryContainer: Colors.amber.shade900,

      error: Colors.red.shade700,
      onError: Colors.white,
      errorContainer: Colors.red.shade100,
      onErrorContainer: Colors.red.shade900,

      // Main surfaces and text
      surface: Colors.grey.shade100,
      onSurface: Colors.grey.shade900,
      onSurfaceVariant: Colors.grey.shade800,

      surfaceDim: Colors.grey.shade200,
      surfaceBright: Colors.white,
      surfaceContainerLowest: Colors.grey.shade200,
      surfaceContainerLow: Colors.grey.shade400,
      surfaceContainer: Colors.grey.shade200,
      surfaceContainerHigh: Colors.grey.shade300,
      surfaceContainerHighest: Colors.grey.shade400,

      // Borders, overlays, and inverse colors
      outline: Colors.grey.shade700,
      outlineVariant: Colors.grey.shade300,
      inverseSurface: Colors.grey.shade900,
      onInverseSurface: Colors.grey.shade100,
      surfaceTint: Colors.grey.shade800,
      shadow: Colors.black12,
      scrim: Colors.white70,
    );
