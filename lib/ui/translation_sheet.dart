import 'package:dba2/controllers/split_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/state/overlay_lock.dart';

import '../controllers/bible_controller.dart';
import '../controllers/translation_controller.dart';
import '../models/translation.dart';

// ---------------------------------------------------------------------------
// TOP SHEET (drops down from the app bar)
// ---------------------------------------------------------------------------

Future<void> showTopSheet(BuildContext context, WidgetBuilder builder) async {
  overlayLocks.value++; // same page-gesture lock as the bottom sheets
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, _, _) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.75;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560, maxHeight: maxH),
            child: Material(
              color: ctx.colorScheme.secondary,
              elevation: 8,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(bottom: false, child: builder(ctx)),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
        child: child,
      ),
    );
  } finally {
    overlayLocks.value--;
  }
}

void openTranslationSheet(BuildContext context) =>
    showTopSheet(context, (_) => const TranslationSheet());

// ---------------------------------------------------------------------------
// RIBBON BUTTON (goes in the reader app bar)
// ---------------------------------------------------------------------------

/// Bookmark ribbon with the 3-4 letter abbreviation.
/// Drop your image at [kRibbonAsset] (and register it in pubspec.yaml);
/// until then a painted gold ribbon is used.
const String kRibbonAsset = 'assets/images/translation_ribbon.webp';

class TranslationRibbon extends StatelessWidget {
  const TranslationRibbon({
    super.key,
    required this.abbr,
    required this.onTap,
    this.width = 28,
    this.height = 26,
  });

  final String abbr;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.onSurface;

    return Tooltip(
      message: 'Translation',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned.fill(
                child: Image.asset(
                  kRibbonAsset,
                  fit: BoxFit.fill,
                  errorBuilder: (_, _, _) => CustomPaint(
                    painter: _RibbonPainter(borderColor: borderColor),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: height * 0.20, bottom: 6.0),
                child: SizedBox(
                  width: width - 8,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      abbr,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color:
                            Colors.white, // White text matching the image style
                        height: 1,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 1.5,
                            color: Colors.black54,
                          ),
                        ],
                      ),
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

class _RibbonPainter extends CustomPainter {
  _RibbonPainter({required this.borderColor});
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size s) {
    // Defines the exact ribbon shape with the bottom upward notch
    final notchHeight = s.height * 0.20; // how high the shoulders rise
    final dipHeight = notchHeight * 0.45; // how far the center V dips back down

    final path = Path()
      ..moveTo(0, 0) // top-left
      ..lineTo(s.width, 0) // top-right
      ..lineTo(s.width, s.height) // bottom-right corner
      ..lineTo(s.width * 0.62, s.height - notchHeight) // right shoulder (up)
      ..lineTo(s.width * 0.50, s.height - dipHeight) // center V (back down)
      ..lineTo(s.width * 0.38, s.height - notchHeight) // left shoulder (up)
      ..lineTo(0, s.height) // bottom-left corner
      ..close();

    // Golden vertical gradient fill
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.fromARGB(255, 216, 182, 59), // Top gold tone
          Color.fromARGB(255, 214, 171, 14), // Bottom shadow/gold tone
        ],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));

    canvas.drawPath(path, fillPaint);

    // Crisp white border outline matching your image
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      // cannot add theme context here???
      // Theme.of(context).colorScheme.onSurface in core.dart
      ..color = borderColor;

    canvas.drawPath(path, borderPaint);
  }

  @override
  // bool shouldRepaint(_) => false;
  bool shouldRepaint(_RibbonPainter old) => old.borderColor != borderColor;
}

// ---------------------------------------------------------------------------
// THE SHEET
// ---------------------------------------------------------------------------

class TranslationSheet extends StatelessWidget {
  const TranslationSheet({
    super.key,
    this.title = 'Translations',
    this.onPick,
    this.currentId,
  });

  final String title;

  /// null = switch the primary translation.
  final Future<void> Function(String id)? onPick;

  /// Which row shows the tick (defaults to the primary).
  final String? currentId;

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TranslationController>();
    final bible = context.watch<BibleController>();

    // Catalog + any imported file that is not in the catalog.
    final all = <Translation>[
      ...kTranslations,
      for (final id in tc.installed)
        if (!kTranslations.any((t) => t.id == id)) translationFor(id),
    ];

    // Group by language, installed first inside each group.
    final groups = <String, List<Translation>>{};
    for (final t in all) {
      groups.putIfAbsent(t.language, () => []).add(t);
    }
    for (final g in groups.values) {
      g.sort((a, b) {
        final ai = tc.isInstalled(a.id) ? 0 : 1;
        final bi = tc.isInstalled(b.id) ? 0 : 1;
        return ai != bi ? ai - bi : 0;
      });
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title row: title on the left, Export + Import on the right.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: (tc.installed.isEmpty || tc.exporting)
                    ? null
                    : tc.exportAll,
                icon: tc.exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt, size: 20),
                label: const Text('Export'),
              ),
              TextButton.icon(
                onPressed: tc.importFiles,
                icon: const Icon(Icons.upload_file, size: 20),
                label: const Text('Import'),
              ),
            ],
          ),
        ),
        if (tc.message != null && tc.message!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              tc.message!,
              style: TextStyle(
                fontSize: 12,
                color: tc.messageIsError
                    ? context.colorScheme.error
                    : context.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                for (final t in entry.value)
                  _TranslationTile(
                    t: t,
                    isCurrent: (currentId ?? bible.translationId) == t.id,
                    onPick: onPick,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// DELETE (asks about a backup first)
// ---------------------------------------------------------------------------

enum _DeleteChoice { delete, backupThenDelete }

Future<void> _confirmDelete(BuildContext context, Translation t) async {
  final tc = context.read<TranslationController>();
  final split = context.read<SplitController>();
  final canRedownload = kTranslations.any((x) => x.id == t.id);

  final choice = await showDialog<_DeleteChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete ${t.abbr}?'),
      content: Text(
        canRedownload
            ? 'You can download it again later, or save a backup copy first.'
            : 'This file was imported and cannot be downloaded again. '
                  'Save a backup copy first if you want to keep it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, _DeleteChoice.delete),
          child: const Text('Delete'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, _DeleteChoice.backupThenDelete),
          child: const Text('Back up & delete'),
        ),
      ],
    ),
  );
  if (choice == null) return; // cancelled

  if (choice == _DeleteChoice.backupThenDelete) {
    final saved = await tc.backupOne(t);
    if (!saved) return; // save was cancelled or failed: keep the file
  }

  await split.releaseTranslation(t.id); // close db handle first
  await tc.remove(t.id);
}

// ---------------------------------------------------------------------------
// ONE ROW
// ---------------------------------------------------------------------------

class _TranslationTile extends StatelessWidget {
  const _TranslationTile({
    required this.t,
    required this.isCurrent,
    this.onPick,
  });

  final Translation t;
  final bool isCurrent;
  final Future<void> Function(String id)? onPick;

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TranslationController>();
    final bible = context.read<BibleController>();
    final installed = tc.isInstalled(t.id);
    final busy = tc.isDownloading(t.id);
    final scheme = context.colorScheme;
    final split = context.watch<SplitController>();
    final inSplit = split.enabled && split.usesTranslation(t.id);

    Widget trailing;
    if (busy) {
      trailing = SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          value: tc.downloading[t.id], // null = spinning
        ),
      );
    } else if (!installed) {
      trailing = IconButton(
        tooltip: 'Download',
        icon: const Icon(Icons.download_rounded),
        onPressed: () => tc.download(t),
      );
    } else if (isCurrent) {
      trailing = Icon(Icons.check_circle, color: scheme.primary);
    } else if (inSplit) {
      trailing = const Icon(Icons.splitscreen);
    } else {
      trailing = IconButton(
        tooltip: 'Delete from device',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmDelete(context, t),
      );
    }

    return ListTile(
      enabled: installed,
      dense: true,
      selected: isCurrent,
      leading: Container(
        width: 46,
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: installed
              ? const Color(0xFFD4A82A)
              : scheme.onSurface.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          t.abbr,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: installed ? Colors.black87 : scheme.onSurface,
          ),
        ),
      ),
      title: Text(t.name),
      subtitle: Text(
        busy
            ? 'Downloading...'
            : installed
            ? 'On this device'
            : 'Not downloaded',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: trailing,
      onTap: installed
          ? () async {
              final pick = onPick;
              if (pick != null) {
                await pick(t.id);
              } else {
                await bible.setTranslation(t.id);
              }
              if (context.mounted) Navigator.of(context).pop();
            }
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// PLACEHOLDER (first launch, nothing installed)
// ---------------------------------------------------------------------------

class NoTranslationPlaceholder extends StatelessWidget {
  const NoTranslationPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<TranslationController>();
    final def = translationFor(kDefaultTranslationId);
    final busy = tc.isDownloading(def.id);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_rounded, size: 56),
              const SizedBox(height: 16),
              Text(
                'Choose a Bible to begin',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Download a translation, or import a .dba file you already have.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy ? null : () => tc.download(def),
                icon: busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: tc.downloading[def.id],
                        ),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text('Download ${def.abbr}'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => openTranslationSheet(context),
                icon: const Icon(Icons.list_rounded),
                label: const Text('Browse translations'),
              ),
              TextButton.icon(
                onPressed: tc.importFiles,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import from device'),
              ),
              if (tc.message != null && tc.message!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  tc.message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tc.messageIsError
                        ? context.colorScheme.error
                        : context.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
