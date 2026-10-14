// lib/ui/sidebars.dart
//
// Single import point for the sidebars, so main.dart stays clean.
// The left sidebar lives in sidebar_left_content.dart; future right-sidebar
// content can grow here (or move to its own file and be exported the same way).
import 'package:flutter/material.dart';

export 'sidebar_left_navigation.dart';

/// Placeholder right sidebar.
class SidebarPanel extends StatelessWidget {
  const SidebarPanel({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade800,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const ListTile(title: Text('Item one')),
            const ListTile(title: Text('Item two')),
            const ListTile(title: Text('Item three')),
          ],
        ),
      ),
    );
  }
}
