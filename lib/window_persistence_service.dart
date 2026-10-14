// lib\window_persistence_service.dart
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class WindowPersistenceService with WindowListener {
  static final WindowPersistenceService _instance =
      WindowPersistenceService._internal();
  factory WindowPersistenceService() => _instance;
  WindowPersistenceService._internal();

  /// Initialize and restore window geometry and state
  static Future<void> initialize({
    required Size defaultSize,
    bool defaultCenter = true,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final double? width = prefs.getDouble('window_width');
    final double? height = prefs.getDouble('window_height');
    final double? x = prefs.getDouble('window_x');
    final double? y = prefs.getDouble('window_y');
    final bool isMaximized = prefs.getBool('window_is_maximized') ?? false;

    // Fetch version info from the single source of truth (pubspec.yaml)
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    // String appName = packageInfo.appName; // Reads name from pubspec.yaml
    String version = packageInfo.version; // Reads 1.2.0
    String buildNumber = packageInfo.buildNumber; // Reads 4

    WindowOptions windowOptions = WindowOptions(
      size: Size(width ?? defaultSize.width, height ?? defaultSize.height),
      center: (x == null || y == null) && defaultCenter,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'David\'s Bible App v$version ($buildNumber)',
      // title: '$appName David\'s Bible App v$version ($buildNumber)',
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }

      // Restore maximized state if it was saved as maximized
      if (isMaximized) {
        await windowManager.maximize();
      }

      await windowManager.show();
      await windowManager.focus();
    });

    // Start listening to window changes to save state
    windowManager.addListener(_instance);
  }

  // --- WindowListener Callbacks ---

  @override
  void onWindowResize() async {
    if (await windowManager.isMaximized()) return;
    final size = await windowManager.getSize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_width', size.width);
    await prefs.setDouble('window_height', size.height);
  }

  @override
  void onWindowMove() async {
    if (await windowManager.isMaximized()) return;
    final position = await windowManager.getPosition();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_x', position.dx);
    await prefs.setDouble('window_y', position.dy);
  }

  @override
  void onWindowMaximize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('window_is_maximized', true);
  }

  @override
  void onWindowUnmaximize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('window_is_maximized', false);
  }
}
