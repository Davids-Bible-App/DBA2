import 'package:flutter/material.dart';

final ColorScheme darkScheme =
    ColorScheme.fromSeed(
      seedColor: Colors.amber,
      brightness: Brightness.dark,
    ).copyWith(
      // Accent roles
      primary: Colors.grey.shade600,
      onPrimary: Colors.black,
      primaryContainer: Colors.grey.shade800,
      onPrimaryContainer: Colors.white,
      inversePrimary: Colors.grey.shade400,

      secondary: Colors.grey.shade900,
      onSecondary: Colors.white,
      secondaryContainer: Colors.grey.shade800,
      onSecondaryContainer: Colors.white,

      tertiary: Colors.black26,
      onTertiary: Colors.grey.shade900,
      tertiaryContainer: Colors.amberAccent,
      onTertiaryContainer: Colors.amber.shade100,

      error: Colors.red.shade300,
      onError: Colors.black,
      errorContainer: Colors.red.shade900,
      onErrorContainer: Colors.red.shade100,

      // Main surfaces and text
      surface: Colors.grey.shade800,
      onSurface: Colors.grey.shade200,
      onSurfaceVariant: Colors.grey.shade500,

      surfaceDim: const Color(0xFF3c3c3c),
      surfaceBright: Colors.grey.shade500,
      surfaceContainerLowest: const Color(0xAA000000),
      surfaceContainerLow: Colors.grey.shade500,
      surfaceContainer: Colors.grey.shade900,
      surfaceContainerHigh: Colors.grey.shade700,
      surfaceContainerHighest: Colors.grey.shade500,

      // Borders, overlays, and inverse colors
      outline: Colors.grey.shade500,
      outlineVariant: Colors.grey.shade700,
      inverseSurface: Colors.grey.shade100,
      onInverseSurface: Colors.grey.shade900,
      surfaceTint: Colors.grey.shade900,
      shadow: Colors.black,
      scrim: Colors.black,
      // scaffoldBackgroundColor: Colors.grey.shade800,
    );
