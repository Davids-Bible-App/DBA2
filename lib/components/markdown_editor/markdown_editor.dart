/// Single import for the whole component:
///   import 'markdown_editor/markdown_editor.dart';
library;

import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:dba2/ui/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'md_controller.dart';
import 'md_theme.dart';
import 'md_theme_editor.dart';
import 'md_widgets.dart';

import 'verse_markdown.dart';

export 'md_controller.dart'
    show MarkdownEditorController, MdStorage, PrefsMdStorage;
export 'md_theme.dart' show MdTheme, MdColor;
export 'verse_markdown.dart' show MdRefPlacement;

// Try each placement, then delete the one you don't want.
const _pasteAfterArrow = false;
const _pasteBeforeMenu = true;

enum MdViewMode { edit, split, preview }

class MarkdownEditorPage extends StatefulWidget {
  const MarkdownEditorPage({
    super.key,
    this.controller,
    this.title = 'Markdown',
  });

  /// Pass your own controller if you want to send text/images into the editor
  /// from the rest of your app. If null, the page makes (and disposes) its own.
  final MarkdownEditorController? controller;
  final String title;

  @override
  State<MarkdownEditorPage> createState() => _MarkdownEditorPageState();
}

class _MarkdownEditorPageState extends State<MarkdownEditorPage>
    with WidgetsBindingObserver {
  late final MarkdownEditorController _c;
  late final bool _owns;
  late final Future<void> _ready;
  MdViewMode? _mode; // null = automatic (split on wide screens)
  MdViewMode? _shownMode; // detects *any* mode change, not just button taps

  // 1. Add persistent scroll controllers
  late final ScrollController _editorScrollController;
  late final ScrollController _previewScrollController;

  // Guard flag to prevent infinite re-entrancy loops between controllers
  bool _isSyncing = false;

  // Track scroll progress (0.0 to 1.0) so it persists across mode switches
  double _lastScrollProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? MarkdownEditorController();
    _c.isOpen = true; // NEW (and delete the widget.controller.isOpen line)
    _c.cursorPlaced = false; // stale selection from last time is invisible
    _ready = _c.init();

    // Initialize controllers
    _editorScrollController = ScrollController();
    _previewScrollController = ScrollController();

    _setupScrollSync();
    _c.documentReplaced.addListener(_resetScroll);

    WidgetsBinding.instance.addObserver(this);
  }

  bool _attached(ScrollController c) => c.hasClients && c.positions.length == 1;

  void _setupScrollSync() {
    _editorScrollController.addListener(
      () => _onScroll(_editorScrollController, _previewScrollController),
    );
    _previewScrollController.addListener(
      () => _onScroll(_previewScrollController, _editorScrollController),
    );
  }

  /// Records progress of [from] and mirrors it onto [to].
  void _onScroll(ScrollController from, ScrollController to) {
    if (_isSyncing || !_attached(from)) return;
    final src = from.position;
    if (src.maxScrollExtent <= 0) return;

    final progress = (src.pixels / src.maxScrollExtent)
        .clamp(0.0, 1.0)
        .toDouble();
    _lastScrollProgress = progress;

    if (!_attached(to)) return;
    final dst = to.position;
    final target = progress * dst.maxScrollExtent;
    if ((dst.pixels - target).abs() <= 1.0) return;

    _isSyncing = true;
    try {
      to.jumpTo(target);
    } finally {
      _isSyncing = false;
    }
  }

  /// Re-applies [_lastScrollProgress] after a remount. Retries a few frames
  /// in case the new view (usually the preview) hasn't laid out its content yet.
  void _restoreScrollProgress([int retries = 3]) {
    if (!mounted) return;
    final target = _lastScrollProgress;
    var pending = false;
    _isSyncing = true;
    try {
      for (final c in [_editorScrollController, _previewScrollController]) {
        if (!_attached(c)) continue;
        final max = c.position.maxScrollExtent;
        if (max > 0) {
          c.jumpTo((target * max).clamp(0.0, max).toDouble());
        } else if (target > 0) {
          pending = true;
        }
      }
    } finally {
      _isSyncing = false;
    }
    if (pending && retries > 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _restoreScrollProgress(retries - 1),
      );
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  /// New document: forget the old position and go to the top everywhere.
  void _resetScroll() {
    _lastScrollProgress = 0.0;
    void toTop() {
      if (!mounted) return;
      _isSyncing = true;
      try {
        for (final c in [_editorScrollController, _previewScrollController]) {
          if (_attached(c) && c.position.pixels != 0) c.jumpTo(0);
        }
      } finally {
        _isSyncing = false;
      }
    }

    toTop(); // now
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => toTop(),
    ); // after relayout
  }

  @override
  void dispose() {
    _c.isOpen = false;
    WidgetsBinding.instance.removeObserver(this);
    _editorScrollController.dispose();
    _previewScrollController.dispose();
    _c.saveNow();
    _c.documentReplaced.removeListener(_resetScroll);
    if (_owns) _c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On Android the OS can kill a backgrounded app without calling dispose.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _c.saveNow();
    }
  }

  void _toast(String msg) => showToast(msg);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _c.markdown));
    if (mounted) _toast('Page copied to clipboard');
  }

  Future<void> _saveAs() async {
    try {
      final path = await _c.saveAs();
      if (path != null && mounted) _toast('Saved to $path');
    } catch (e) {
      if (mounted) _toast('Save failed: $e');
    }
  }

  Future<void> _open() async {
    try {
      final name = await _c.openMarkdownFile();
      if (name != null && mounted) {
        _toast('Opened $name (Undo brings back your previous text)');
      }
    } catch (e) {
      if (mounted) _toast('Open failed: $e');
    }
  }

  Future<void> _export() async {
    try {
      final path = await _c.exportToDownloads();
      if (mounted) _toast('Saved to $path');
    } catch (e) {
      if (mounted) _toast('Export failed: $e');
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear editor?'),
        content: const Text('You can still bring it back with Undo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) _c.clear();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return ValueListenableBuilder<MdTheme>(
          valueListenable: _c.theme,
          builder: (context, th, _) => Theme(
            data: th.toMaterial(),
            child: Builder(builder: (context) => _scaffold(context, th)),
          ),
        );
      },
    );
  }

  Widget _scaffold(BuildContext context, MdTheme th) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    var mode = _mode ?? (wide ? MdViewMode.split : MdViewMode.edit);
    if (!wide && mode == MdViewMode.split) mode = MdViewMode.edit;

    if (_shownMode != null && _shownMode != mode) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _restoreScrollProgress(),
      );
    }
    _shownMode = mode;

    final editor = _EditorPane(
      controller: _c,
      theme: th,
      scrollController: _editorScrollController,
    );
    final preview = ValueListenableBuilder<String>(
      valueListenable: _c.previewText,
      builder: (_, text, _) => MdViewer(
        data: text,
        theme: th,
        scrollController: _previewScrollController,
      ),
    );

    return OverlayLock(
      scope: LockScope.leftOnly,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pasteAfterArrow) MdPasteButton(controller: _c),
              Flexible(
                child: Text(widget.title, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          actions: [
            SegmentedButton<MdViewMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                const ButtonSegment(
                  value: MdViewMode.edit,
                  icon: Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Editor',
                ),
                if (wide)
                  const ButtonSegment(
                    value: MdViewMode.split,
                    icon: Icon(Icons.vertical_split_outlined, size: 18),
                    tooltip: 'Split',
                  ),
                const ButtonSegment(
                  value: MdViewMode.preview,
                  icon: Icon(Icons.visibility_outlined, size: 18),
                  tooltip: 'Preview',
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            IconButton(
              tooltip: th.dark ? 'Light theme' : 'Dark theme',
              icon: Icon(
                th.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              ),
              onPressed: _c.toggleBrightness,
            ),
            IconButton(
              tooltip: 'Copy page',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _copy,
            ),
            if (_pasteBeforeMenu) MdPasteButton(controller: _c),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'theme':
                    showMdThemeEditor(context, _c);
                  case 'verseopts':
                    showMdVerseOptions(context, _c);
                  case 'open':
                    _open();
                  case 'saveas':
                    _saveAs();
                  case 'export':
                    _export();
                  case 'clear':
                    _clear();
                }
              },
              itemBuilder: (_) => const [
                // PopupMenuItem(
                //   value: 'theme',
                //   child: ListTile(
                //     leading: Icon(Icons.palette_outlined),
                //     title: Text('Customize theme'),
                //   ),
                // ),
                PopupMenuItem(
                  value: 'verseopts',
                  child: ListTile(
                    leading: Icon(Icons.format_quote_outlined),
                    title: Text('Paste formatting options…'),
                  ),
                ),
                PopupMenuItem(
                  value: 'open',
                  child: ListTile(
                    leading: Icon(Icons.folder_open_outlined),
                    title: Text('Open .md file…'),
                  ),
                ),
                PopupMenuItem(
                  value: 'saveas',
                  child: ListTile(
                    leading: Icon(Icons.save_as_outlined),
                    title: Text('Save as…'),
                  ),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.download_outlined),
                    title: Text('Quick export to Downloads'),
                  ),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading: Icon(Icons.delete_sweep_outlined),
                    title: Text('Clear editor'),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            if (mode != MdViewMode.preview) MdToolbar(controller: _c),
            Expanded(
              child: switch (mode) {
                MdViewMode.edit => editor,
                MdViewMode.preview => preview,
                MdViewMode.split => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: editor),
                    VerticalDivider(width: 1, color: th.c(MdColor.border)),
                    Expanded(child: preview),
                  ],
                ),
              },
            ),
            MdStatusBar(controller: _c),
          ],
        ),
      ),
    );
  }
}

// ================================================================ editor ====
class _EditorPane extends StatelessWidget {
  const _EditorPane({
    required this.controller,
    required this.theme,
    required this.scrollController,
  });
  final MarkdownEditorController controller;
  final MdTheme theme;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      color: theme.c(MdColor.background),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.tab): c.indent,
          const SingleActivator(LogicalKeyboardKey.tab, shift: true): c.outdent,
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              c.jumpToNextLine,
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): c.bold,
          const SingleActivator(LogicalKeyboardKey.keyI, control: true):
              c.italic,
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              c.insertLink,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): c.redo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): c.redo,
        },
        child: TextField(
          controller: c.text,
          focusNode: c.focus,
          scrollController: scrollController,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          inputFormatters: [MdSmartListFormatter()],
          style: theme.editorStyle,
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            hintText: 'Start writing Markdown…',
            hintStyle: theme.editorStyle.copyWith(
              color: theme.c(MdColor.mutedText),
            ),
            contentPadding: EdgeInsets.all(theme.contentPadding),
          ),
        ),
      ),
    );
  }
}

Future<void> showMdVerseOptions(
  BuildContext context,
  MarkdownEditorController c,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Paste formatting options'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Options scroll; the preview below stays visible.
            Flexible(
              child: SingleChildScrollView(
                child: MdVerseOptions(controller: c),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text('Preview', style: Theme.of(ctx).textTheme.titleSmall),
            const SizedBox(height: 6),
            MdVerseSample(controller: c),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class MdVerseOptions extends StatelessWidget {
  const MdVerseOptions({super.key, required this.controller});
  final MarkdownEditorController controller;

  Widget _section(
    BuildContext context, {
    required String title,
    required String hint,
    required Widget control,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: control),
          const SizedBox(height: 6),
          Text(
            hint,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'These settings apply to verses sent to the editor from now on. '
            'Text already in the document is not changed.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        // Grouped verse arrangement
        _section(
          context,
          title: 'Grouped verses',
          hint: 'How consecutive verses from one chapter are laid out.',
          control: ValueListenableBuilder<bool>(
            valueListenable: controller.stacked,
            builder: (_, stacked, _) => SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.wrap_text, size: 18),
                  label: Text('Inline'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.view_headline, size: 18),
                  label: Text('Stacked'),
                ),
              ],
              selected: {stacked},
              onSelectionChanged: (s) => controller.setStacked(s.first),
            ),
          ),
        ),

        // Verse insertion
        _section(
          context,
          title: 'Insertion',
          hint:
              'Manual: verses wait for the Paste button and go in at the '
              'cursor. Automatic: they are added at the end of the document.',
          control: ValueListenableBuilder<bool>(
            valueListenable: controller.autoInsert,
            builder: (_, auto, _) => SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.touch_app_outlined, size: 18),
                  label: Text('Manual'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.vertical_align_bottom, size: 18),
                  label: Text('Automatic'),
                ),
              ],
              selected: {auto},
              onSelectionChanged: (s) => controller.setAutoInsert(s.first),
            ),
          ),
        ),

        // Reference placement
        _section(
          context,
          title: 'Reference',
          hint:
              'Above: outside the quote. Start / End: inside the quote. '
              'At the end, a single-line quote gets a dash before the reference.',
          control: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<MdRefPlacement>(
                valueListenable: controller.refPlacement,
                builder: (_, placement, _) => SegmentedButton<MdRefPlacement>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: MdRefPlacement.above,
                      icon: Icon(Icons.vertical_align_top, size: 18),
                      label: Text('Above'),
                    ),
                    ButtonSegment(
                      value: MdRefPlacement.start,
                      icon: Icon(Icons.border_top, size: 18),
                      label: Text('Start'),
                    ),
                    ButtonSegment(
                      value: MdRefPlacement.end,
                      icon: Icon(Icons.border_bottom, size: 18),
                      label: Text('End'),
                    ),
                  ],
                  selected: {placement},
                  onSelectionChanged: (s) =>
                      controller.setRefPlacement(s.first),
                ),
              ),
              ListenableBuilder(
                listenable: Listenable.merge([
                  controller.refPlacement,
                  controller.refOwnLine,
                ]),
                builder: (_, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Reference on its own line'),
                  subtitle: const Text(
                    'Always on for stacked verses.',
                  ),
                  value: controller.refOwnLine.value,
                  onChanged:
                      controller.refPlacement.value == MdRefPlacement.above
                      ? null // not relevant when the reference is above the quote
                      : controller.setRefOwnLine,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Live example of the current paste settings (one single verse, one range).
class MdVerseSample extends StatelessWidget {
  const MdVerseSample({super.key, required this.controller});
  final MarkdownEditorController controller;

  static const _verses = <MdVerse>[
    (
      tr: 'kjv',
      bookId: 'JHN',
      bookName: 'John',
      chapter: 11,
      verse: 35,
      text: 'Jesus wept.',
      edition: 'KJV',
    ),
    (
      tr: 'kjv',
      bookId: 'JHN',
      bookName: 'John',
      chapter: 1,
      verse: 1,
      text:
          'In the beginning was the Word, and the Word was with God, '
          'and the Word was God.',
      edition: 'KJV',
    ),
    (
      tr: 'kjv',
      bookId: 'JHN',
      bookName: 'John',
      chapter: 1,
      verse: 2,
      text: 'The same was in the beginning with God.',
      edition: 'KJV',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.stacked,
        controller.refPlacement,
        controller.refOwnLine,
        controller.theme,
      ]),
      builder: (_, _) {
        final md = formatVerses(
          _verses,
          stacked: controller.stacked.value,
          refPlacement: controller.refPlacement.value,
          refOwnLine: controller.refOwnLine.value,
        );
        return Container(
          height: 170,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: cs.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: MdViewer(data: md, theme: controller.theme.value),
        );
      },
    );
  }
}
