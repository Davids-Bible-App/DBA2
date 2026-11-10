import 'dart:io';

import 'package:dba2/components/markdown_editor/markdown_editor.dart';
import 'package:dba2/ui/widgets/toast.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import 'md_controller.dart';

// ================================================================ toolbar ===
class MdToolbar extends StatelessWidget {
  const MdToolbar({super.key, required this.controller});
  final MarkdownEditorController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = controller;

    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
    Widget sep() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 22,
        child: VerticalDivider(width: 1, color: cs.outline),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: ScrollConfiguration(
        // lets you drag-scroll the toolbar with a mouse too
        behavior: ScrollConfiguration.of(context)
            .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Row(
              children: [
                btn(Icons.undo, 'Undo (Ctrl+Z)', c.canUndo ? c.undo : null),
                btn(Icons.redo, 'Redo (Ctrl+Y)', c.canRedo ? c.redo : null),
                sep(),
                PopupMenuButton<int>(
                  tooltip: 'Heading',
                  icon: const Icon(Icons.title, size: 22),
                  onSelected: c.setHeader,
                  itemBuilder: (_) => [
                    for (var i = 1; i <= 6; i++)
                      PopupMenuItem(
                        value: i,
                        child: Text(
                          'Heading $i',
                          style: TextStyle(
                            fontSize: 24 - i * 2.0,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const PopupMenuItem(value: 0, child: Text('Normal text')),
                  ],
                ),
                sep(),
                btn(Icons.format_bold, 'Bold (Ctrl+B)', c.bold),
                btn(Icons.format_italic, 'Italic (Ctrl+I)', c.italic),
                btn(Icons.strikethrough_s, 'Strikethrough', c.strike),
                btn(Icons.code, 'Inline code', c.inlineCode),
                sep(),
                btn(Icons.format_quote, 'Quote', c.quote),
                btn(Icons.format_list_bulleted, 'Bullet list', c.bulletList),
                btn(
                  Icons.format_list_numbered,
                  'Numbered list',
                  c.numberedList,
                ),
                btn(Icons.checklist, 'Task list', c.taskList),
                btn(
                  Icons.format_indent_decrease,
                  'Outdent (Shift+Tab)',
                  c.outdent,
                ),
                btn(Icons.format_indent_increase, 'Indent (Tab)', c.indent),
                sep(),
                btn(Icons.link, 'Link (Ctrl+K)', c.insertLink),
                btn(Icons.image_outlined, 'Image', c.insertImageTemplate),
                btn(Icons.table_chart_outlined, 'Table', c.insertTable),
                btn(Icons.data_object, 'Code block', c.insertCodeBlock),
                btn(Icons.horizontal_rule, 'Horizontal rule', c.insertRule),
                sep(),
                btn(
                  Icons.emoji_emotions_outlined,
                  'Emoji',
                  () => showMdEmojiPicker(context, c),
                ),
                btn(Icons.tag, 'Copy link to this header (#id)', () async {
                  final link = c.headerLinkAtCursor();
                  final msg = link == null
                      ? 'Put the cursor on a # header line first'
                      : 'Copied: $link';
                  if (link != null) {
                    await Clipboard.setData(ClipboardData(text: link));
                  }
                  {
                    showToast(msg);
                  }
                }),
                btn(Icons.toc, 'Insert table of contents', c.insertToc),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Appears only when verses are waiting (Manual insertion mode).
class MdPasteButton extends StatelessWidget {
  const MdPasteButton({super.key, required this.controller});
  final MarkdownEditorController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: controller.pendingVerses,
      builder: (_, n, _) => n == 0
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Badge(
                label: Text('$n'),
                child: IconButton(
                  tooltip: '$n verses to paste at the cursor',
                  icon: const Icon(Icons.content_paste_go),
                  onPressed: () {
                    final atCursor = controller.pastePending();
                    if (!atCursor) {
                      showToast(
                        'No cursor set, appending to end. ',
                      );
                    }
                  },
                ),
              ),
            ),
    );
  }
}

// ============================================================== status bar ===
class MdStatusBar extends StatelessWidget {
  const MdStatusBar({super.key, required this.controller});
  final MarkdownEditorController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline)),
      ),
      child: Row(
        children: [
          ValueListenableBuilder<MdSaveState>(
            valueListenable: controller.saveState,
            builder: (_, s, _) => Row(
              children: [
                Icon(
                  s == MdSaveState.saved
                      ? Icons.cloud_done_outlined
                      : Icons.sync,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(switch (s) {
                  MdSaveState.saved => 'Saved',
                  MdSaveState.saving => 'Saving…',
                  MdSaveState.unsaved => 'Unsaved',
                }, style: style),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Cursor position: cheap loop, no allocations.
          ValueListenableBuilder<({int line, int col})>(
            valueListenable: controller.cursor,
            builder: (_, p, _) =>
                Text('Ln ${p.line}, Col ${p.col}', style: style),
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: Listenable.merge([
              controller.wordCount,
              controller.charCount,
            ]),
            builder: (_, _) => Text(
              '${controller.wordCount.value} words · ${controller.charCount.value} chars',
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================= viewer ===
class MdViewer extends StatefulWidget {
  const MdViewer({
    super.key,
    required this.data,
    required this.theme,
    this.scrollController, // 1. Added optional scrollController parameter
  });

  final String data;
  final MdTheme theme;
  final ScrollController? scrollController;

  @override
  State<MdViewer> createState() => _MdViewerState();
}

class _MdViewerState extends State<MdViewer> {
  // 2. Local fallback controller used only when widget.scrollController is null
  ScrollController? _internalScroll;
  final _keys = <String, GlobalKey>{}; // header slug -> key (for #links)

  ScrollController get _activeScroll =>
      widget.scrollController ?? (_internalScroll ??= ScrollController());

  @override
  void dispose() {
    _internalScroll?.dispose(); // Only dispose if we created the internal one
    super.dispose();
  }

  GlobalKey _keyFor(String slug) => _keys.putIfAbsent(slug, GlobalKey.new);

  void _jumpTo(String anchor) {
    String slug;
    try {
      slug = Uri.decodeComponent(anchor).toLowerCase();
    } catch (_) {
      slug = anchor.toLowerCase();
    }
    final ctx = _keys[slug]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.theme;
    final sheet = th.toStyleSheet();
    final maxImgW = (MediaQuery.sizeOf(context).width - th.contentPadding * 2)
        .clamp(80.0, 700.0);

    // GitHub-style de-duplication: "intro", "intro-1", "intro-2" ...
    final seen = <String, int>{};
    final headers = _MdHeaderBuilder(th, (title) {
      var slug = MarkdownEditorController.slugify(title);
      final n = seen[slug] ?? 0;
      seen[slug] = n + 1;
      if (n > 0) slug = '$slug-$n';
      return _keyFor(slug);
    });

    return Container(
      color: th.c(MdColor.background),
      child: SelectionArea(
        child: SingleChildScrollView(
          controller: _activeScroll, // 3. Uses the passed-in or active scroll controller
          padding: EdgeInsets.all(th.contentPadding),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: SizedBox(
                width: double.infinity,
                child: MarkdownBody(
                  data: widget.data,
                  selectable: false,
                  softLineBreak: true,
                  styleSheet: sheet,
                  extensionSet: md.ExtensionSet.gitHubFlavored,
                  builders: {
                    for (final t in const ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'])
                      t: headers,
                  },
                  bulletBuilder: (p) {
                    if (p.style == BulletStyle.orderedList) {
                      return Text(
                        '${p.index + 1}.',
                        textAlign: TextAlign.right,
                        style: sheet.listBullet,
                      );
                    }
                    const glyphs = ['•', '◦', '▪'];
                    return Text(
                      glyphs[p.nestLevel % glyphs.length],
                      textAlign: TextAlign.center,
                      style: sheet.listBullet,
                    );
                  },
                  onTapLink: (text, href, title) async {
                    if (href == null) return;
                    if (href.startsWith('#')) {
                      _jumpTo(href.substring(1));
                      return;
                    }
                    final uri = Uri.tryParse(href);
                    if (uri != null) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  imageBuilder: (uri, title, alt) {
                    Widget broken(BuildContext c, Object e, StackTrace? s) =>
                        Icon(
                          Icons.broken_image_outlined,
                          color: th.c(MdColor.mutedText),
                        );
                    Widget img;
                    if (uri.scheme == 'http' || uri.scheme == 'https') {
                      img = Image.network(
                        uri.toString(),
                        fit: BoxFit.scaleDown,
                        errorBuilder: broken,
                      );
                    } else if (uri.scheme == 'file' || uri.scheme.isEmpty) {
                      final path = uri.scheme == 'file'
                          ? uri.toFilePath()
                          : uri.toString();
                      img = Image.file(
                        File(path),
                        fit: BoxFit.scaleDown,
                        errorBuilder: broken,
                      );
                    } else {
                      img = broken(context, '', null);
                    }
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: maxImgW,
                        maxHeight: 500,
                      ),
                      child: img,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders h1-h6 ourselves so each header gets a GlobalKey to scroll to.
/// Keeps bold / italic / code / strike / link formatting inside headers.
class _MdHeaderBuilder extends MarkdownElementBuilder {
  _MdHeaderBuilder(this.theme, this.keyFor);
  final MdTheme theme;
  final GlobalKey Function(String title) keyFor;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style = preferredStyle ?? parentStyle ?? const TextStyle();
    return Padding(
      key: keyFor(element.textContent),
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(
        TextSpan(
          style: style,
          children: _spans(element.children ?? const <md.Node>[], style),
        ),
      ),
    );
  }

  List<InlineSpan> _spans(List<md.Node> nodes, TextStyle base) => [
    for (final n in nodes) _span(n, base),
  ];

  InlineSpan _span(md.Node n, TextStyle base) {
    if (n is md.Text) return TextSpan(text: n.text);
    if (n is md.Element) {
      final TextStyle? s = switch (n.tag) {
        'strong' => const TextStyle(fontWeight: FontWeight.w800),
        'em' => const TextStyle(fontStyle: FontStyle.italic),
        'del' => const TextStyle(decoration: TextDecoration.lineThrough),
        'code' =>
          theme
              .codeStyle((base.fontSize ?? 16) * 0.9)
              .copyWith(backgroundColor: theme.c(MdColor.codeBackground)),
        'a' => TextStyle(
          color: theme.c(MdColor.link),
          decoration: TextDecoration.underline,
        ),
        _ => null,
      };
      return TextSpan(
        style: s,
        children: _spans(n.children ?? const <md.Node>[], base),
      );
    }
    return const TextSpan();
  }
}

// ============================================================ emoji picker ===
const _emoji = [
  '😀',
  '😃',
  '😄',
  '😁',
  '😆',
  '😅',
  '😂',
  '🤣',
  '🙂',
  '😉',
  '😊',
  '😍',
  '😘',
  '😎',
  '🤔',
  '😐',
  '😴',
  '😢',
  '😭',
  '😡',
  '🤯',
  '😱',
  '🥳',
  '🤗',
  '🙄',
  '😬',
  '🤝',
  '👍',
  '👎',
  '👏',
  '🙌',
  '🙏',
  '💪',
  '👀',
  '❤️',
  '💔',
  '🔥',
  '✨',
  '⭐',
  '🎉',
  '🚀',
  '💡',
  '✅',
  '❌',
  '⚠️',
  '❓',
  '❗',
  '📌',
  '📎',
  '📝',
  '📚',
  '💻',
  '🐛',
  '🔧',
  '🔒',
  '🔑',
  '📦',
  '🌍',
  '☕',
  '🍕',
];

Future<void> showMdEmojiPicker(
  BuildContext context,
  MarkdownEditorController c,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Emoji'),
      content: SizedBox(
        width: 360,
        height: 320,
        child: Column(
          children: [
            Expanded(
              child: GridView.extent(
                maxCrossAxisExtent: 46,
                children: [
                  for (final e in _emoji)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        c.insertEmoji(e);
                        Navigator.pop(ctx);
                      },
                      child: Center(
                        child: Text(e, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: typing :smile: or :rocket: also renders in the preview.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
