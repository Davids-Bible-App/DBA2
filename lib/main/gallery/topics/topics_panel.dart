import 'package:dba2/ui/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gallery_controller.dart';
import '../models.dart';
import '../common.dart';
import '../grouped_verse_card.dart';
import 'topic_description.dart';

/// Topics tab: topic list (drag to reorder) -> topic detail (grouped verses,
/// drag to reorder, pinch-out for UniVerse).
class TopicsPanel extends StatefulWidget {
  const TopicsPanel({
    super.key,
    required this.controller,
    required this.onJumpTo,
    this.onExportToEditor,
    this.onOpenUniVerse,
  });

  final GalleryController controller;
  final void Function(GalleryEntry verse) onJumpTo;
  final void Function(
    String topic,
    String description,
    List<GalleryEntry> verses,
  )?
  onExportToEditor;
  final void Function(List<GalleryEntry> verses)? onOpenUniVerse;

  @override
  State<TopicsPanel> createState() => _TopicsPanelState();
}

class _TopicsPanelState extends State<TopicsPanel> {
  final _query = TextEditingController();
  GalleryController get c => widget.controller;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String _date(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, _query]),
    builder: (context, _) {
      final inDetail = c.selectedTopic != null;
      final bg = Theme.of(context).colorScheme.secondary;
      return ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220), // tune speed here
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            // the detail view is always the one on top
            children: inDetail
                ? [...previous, ?current]
                : [?current, ...previous],
          ),
          transitionBuilder: (child, animation) {
            final isDetail = child.key == const ValueKey('detail');

            return isDetail
                ? SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: ColoredBox(
                      color: bg,
                      child: child,
                    ), // solid, so it hides the list
                  )
                : SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(
                        -0.3,
                        0,
                      ), // list moves slower than the detail
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(
                      opacity: Tween<double>(
                        begin: 0.4,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  );
          },
          child: inDetail
              ? KeyedSubtree(
                  key: const ValueKey('detail'),
                  child: _detail(context),
                )
              : KeyedSubtree(
                  key: const ValueKey('list'),
                  child: _list(context),
                ),
        ),
      );
    },
  );

  // ── topics list ─────────────────────────────────────────────────────────
  Widget _list(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final items = searching
        ? c.topics.where((m) => m.topic.toLowerCase().contains(q)).toList()
        : c.topics;

    Widget tile(int i) {
      final m = items[i];
      final cs = Theme.of(context).colorScheme;

      final handleBar = Container(
        width: 30,
        color: cs.onInverseSurface,
        child: Center(
          child: Icon(
            Icons.drag_indicator,
            size: 20,
            // color: searching
            //     ? cs.outline.withValues(alpha: 0.4)
            //     : cs.onSurfaceVariant,
          ),
        ),
      );

      return Padding(
        key: ValueKey(m.topic),
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => c.selectTopic(m.topic),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searching
                      ? handleBar
                      : ReorderableDragStartListener(
                          index: i,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: handleBar,
                          ),
                        ),
                  Expanded(
                    child: Container(
                      color: cs.surface,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '🏷️ ${m.topic}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'verses: ${m.count}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                      Text(
                                        _date(m.updated),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            TopicActions(
                              onRename: () => _rename(m.topic),
                              onDelete: () => _deleteTopic(m.topic),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        GallerySearchField(controller: _query, hint: 'Search topics...'),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No Topics Yet'))
              : searching
              ? ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => tile(i),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                  itemCount: items.length,
                  proxyDecorator: (child, _, _) => Material(
                    color: Colors.transparent,
                    elevation: 8,
                    borderRadius: BorderRadius.circular(16),
                    child: child,
                  ),
                  onReorderItem: c.reorderTopics,
                  itemBuilder: (_, i) => tile(i),
                ),
        ),
      ],
    );
  }

  // ── topic detail ────────────────────────────────────────────────────────
  Widget _detail(BuildContext context) {
    final topic = c.selectedTopic!;
    final groups = c.groups;
    final hasVerses = c.topicVerses.isNotEmpty;

    return PinchOutDetector(
      onPinchOut: () {
        if (hasVerses) widget.onOpenUniVerse?.call(c.topicVerses);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () => c.selectTopic(null),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Topics'),
                ),
                TopicActions(
                  onExport: hasVerses && widget.onExportToEditor != null
                      ? () => widget.onExportToEditor!(
                          topic,
                          c.topicDescription,
                          c.topicVerses,
                        )
                      : null,
                  onCopy: hasVerses ? _copy : null,
                  onResetOrder: () => _resetOrder(topic),
                ),
              ],
            ),
          ),
          TopicDescription(
            topic: topic,
            description: c.topicDescription,
            onSave: c.saveDescription,
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
              itemCount: groups.length,
              proxyDecorator: (child, _, _) => Material(
                color: Colors.transparent,
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                child: child,
              ),
              onReorderItem: c.reorderGroups,
              itemBuilder: (_, i) {
                final g = groups[i];
                return Padding(
                  key: ValueKey(g.first.id),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GroupedVerseCard(
                    group: g,
                    onJump: widget.onJumpTo,
                    onDelete: (type, ids) =>
                        deleteWithConfirm(context, c, type, ids),
                    onSaveNote: c.saveNote,
                    onUngroup: c.ungroup,
                    dragHandle: ReorderableDragStartListener(
                      index: i,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Container(
                          width: 30,
                          color: Theme.of(context).colorScheme.onInverseSurface,
                          child: const Center(
                            child: Icon(Icons.drag_indicator, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── actions ─────────────────────────────────────────────────────────────
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: c.exportText));
    if (!mounted) return;
    showToast('Topical Verses - Copied to Clipboard!');
  }

  Future<void> _rename(String topic) async {
    final name = await promptDialog(
      context,
      title: 'Rename topic',
      initial: topic,
    );
    if (name == null || name.trim().isEmpty || name.trim() == topic) return;
    await c.renameTopic(topic, name.trim());
  }

  Future<void> _deleteTopic(String topic) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete Topic',
      message: 'Delete topic "$topic" and all its verses?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) await c.deleteTopic(topic);
  }

  Future<void> _resetOrder(String topic) async {
    final ok = await confirmDialog(
      context,
      title: 'Reset Order',
      message: 'Reset verse order for "$topic" to default (Biblical order)?',
      confirmLabel: 'Reset',
    );
    if (ok) await c.resetTopicOrder(topic);
  }
}
