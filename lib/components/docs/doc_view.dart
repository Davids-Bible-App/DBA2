import 'package:dba2/components/markdown_editor/md_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Add a new doc type here (and its folder + pubspec entries) and it just works.
enum DocKind {
  help('help', 'Help'),
  info('info', 'Info');

  const DocKind(this.folder, this.label);
  final String folder; // assets/docs/<folder>/
  final String label; // appended to the title: "Audio Help"
}

/// A reference to one doc. Nothing is loaded until [open] is called.
///
///   DocView.help('Audio').open(context);
class DocView {
  const DocView(this.kind, this.name, {this.theme});
  const DocView.help(String name, {MdTheme? theme})
    : this(DocKind.help, name, theme: theme);
  const DocView.info(String name, {MdTheme? theme})
    : this(DocKind.info, name, theme: theme);

  final DocKind kind;
  final String name; // file name without ".md"
  final MdTheme? theme; // null = light/dark preset matching the app

  String get assetPath => 'assets/docs/${kind.folder}/$name.md';
  String get title =>
      '${name[0].toUpperCase()}${name.substring(1)} ${kind.label}';

  Future<void> open(BuildContext context) {
    final t =
        theme ??
        (Theme.of(context).brightness == Brightness.dark
            ? MdTheme.dark()
            : MdTheme.light());

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true, // tap outside to close
      barrierLabel: 'Close $title',
      barrierColor: Colors.black26, // the scrim: change to taste
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => _DocDialog(doc: this, theme: t),
      transitionBuilder: (_, anim, _, child) {
        final curved = CurveTween(curve: Curves.easeOutCubic).animate(anim);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

/// Drop-in "?" button (or text button if you give it a [label]).
///
///   const DocButton(DocView.help('Audio'))
///   const DocButton(DocView.info('Maps'), label: 'About maps')
class DocButton extends StatelessWidget {
  const DocButton(
    this.doc, {
    super.key,
    this.icon = Icons.help_outline,
    this.label,
    this.tooltip,
  });

  final DocView doc;
  final IconData icon;
  final String? label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    void open() => doc.open(context);
    if (label == null) {
      return IconButton(
        icon: Icon(icon),
        tooltip: tooltip ?? doc.title,
        onPressed: open,
      );
    }
    return TextButton.icon(
      icon: Icon(icon),
      label: Text(label!),
      onPressed: open,
    );
  }
}

// ───────────────────────────────────────────────────────────── dialog body

class _DocDialog extends StatefulWidget {
  const _DocDialog({required this.doc, required this.theme});
  final DocView doc;
  final MdTheme theme;

  @override
  State<_DocDialog> createState() => _DocDialogState();
}

class _DocDialogState extends State<_DocDialog> {
  // Created ONCE (not in build), so rebuilds never re-read the file.
  // cache: false => the text isn't kept in memory after the dialog closes.
  late final Future<String> _text = rootBundle.loadString(
    widget.doc.assetPath,
    cache: false,
  );
  late final MarkdownStyleSheet _style = widget.theme.toStyleSheet();

  Widget _image(Uri uri, String? title, String? alt) {
    Widget broken(BuildContext c, Object e, StackTrace? s) => Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        '[image not found: ${alt ?? uri.path}]',
        style: TextStyle(color: widget.theme.c(MdColor.mutedText)),
      ),
    );

    final Widget img;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      img = Image.network(uri.toString(), errorBuilder: broken);
    } else {
      final rel = Uri.decodeComponent(uri.path)
          .replaceFirst(RegExp(r'^(\./|/)+'), '');
      img = Image.asset(
        'assets/docs/${widget.doc.kind.folder}/$rel',
        fit: BoxFit.contain,
        cacheWidth:
            1200, // decode at a sensible size, saves memory (never upscales)
        errorBuilder: broken,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: img),
    );
  }

  Future<void> _onLink(String text, String? href, String title) async {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 760, maxHeight: maxH),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Theme(
                  data: t.toMaterial(), // scoped theme, app theme untouched
                  child: Material(
                    color: t.c(MdColor.background),
                    elevation: 8,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: t.c(MdColor.border)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Header(title: widget.doc.title, theme: t),
                        Divider(height: 1, color: t.c(MdColor.border)),
                        Flexible(
                          child: FutureBuilder<String>(
                            future: _text,
                            builder: (context, snap) {
                              if (snap.hasError) {
                                return SizedBox(
                                  height: 160,
                                  child: Center(
                                    child: Text(
                                      'Could not load ${widget.doc.assetPath}',
                                      style: TextStyle(
                                        color: t.c(MdColor.mutedText),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              if (!snap.hasData) {
                                return const SizedBox(
                                  height: 160,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              return Markdown(
                                data: snap.data!,
                                styleSheet: _style,
                                padding: EdgeInsets.all(t.contentPadding),
                                shrinkWrap: true,
                                imageBuilder: _image,
                                onTapLink: _onLink,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.theme});
  final String title;
  final MdTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.c(MdColor.surface),
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.c(MdColor.heading),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
