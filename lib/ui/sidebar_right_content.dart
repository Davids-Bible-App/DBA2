import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The sidebar is ONLY the tab shell. Each tab's content is a widget you slot in.
class SidebarRightContent extends StatefulWidget {
  const SidebarRightContent({
    super.key,
    required this.topics,
    required this.notes,
    required this.bookmarks,
    this.onSwipePastFirstTab,
  });
  final Widget topics, notes, bookmarks;
  final VoidCallback?
  onSwipePastFirstTab; // what a right swipe past TOPICS does

  @override
  State<SidebarRightContent> createState() => _SidebarRightContentState();
}

class _SidebarRightContentState extends State<SidebarRightContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _keyboardHidden = false;

  @override
  void initState() {
    super.initState();
    _tabs.animation!.addListener(_onTabMoving);
  }

  double _over = 0;
  bool? _armed; // decided on the first overscroll of each drag

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification || n is ScrollEndNotification) {
      _over = 0;
      _armed = true; // a fresh drag may fire once
    } else if (n is OverscrollNotification &&
        n.dragDetails != null &&
        n.overscroll < 0) {
      if (_armed ?? true) {
        _over += -n.overscroll;
        if (_over > 60) {
          _armed = false; // one action per drag
          widget.onSwipePastFirstTab?.call();
        }
      }
    }
    return false;
  }

  // Fires on every frame the tabs move (finger drag or tab tap).
  void _onTabMoving() {
    final moving = (_tabs.animation!.value - _tabs.index).abs() > 0.001;
    if (moving && !_keyboardHidden) {
      _keyboardHidden = true; // only once per movement
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } else if (!moving) {
      _keyboardHidden = false; // settled, ready for the next swipe
    }
  }

  @override
  void dispose() {
    _tabs.animation!.removeListener(_onTabMoving);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondary,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SafeArea(
          child: Column(
            children: [
              TabBar(
                controller: _tabs,
                labelColor: colors.onPrimaryContainer,
                unselectedLabelColor: colors.onSurfaceVariant,
                // indicator: BoxDecoration(
                //   color: colors.secondaryContainer,
                //   borderRadius: BorderRadius.circular(4),
                // ),
                dividerColor: colors.outlineVariant,
                tabs: const [
                  Tab(text: 'TOPICS'),
                  Tab(text: 'NOTES'),
                  Tab(text: 'BOOKMARKS'),
                ],
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Expanded(
                child: ScrollConfiguration(
                  // Mouse drag swiping (Windows).
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: PointerDeviceKind.values.toSet(),
                  ),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: TabBarView(
                      controller: _tabs,
                      physics: const PageScrollPhysics(),
                      children: [
                        _KeepAlive(child: widget.topics),
                        _KeepAlive(child: widget.notes),
                        _KeepAlive(child: widget.bookmarks),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps each tab's state (search text, selected topic, scroll) when switching.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
