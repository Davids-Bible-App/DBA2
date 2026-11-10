import 'package:dba2/core.dart' hide BoxDecoration, BoxShadow;
import 'package:dba2/components/audio/controllers/sleep_timer_controller.dart';
import 'package:dba2/components/audio/ui/add_audio_sheet.dart';
import 'package:dba2/components/audio/ui/sleep_timer_panel.dart';
import 'package:dba2/components/docs/doc_view.dart';
import 'package:dba2/ui/widgets/toast.dart';
import 'package:dba2/ui/extras/progress_glow.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_inset_shadow/flutter_inset_shadow.dart';

import '../controllers/audio_controller.dart';

const _accent = Color(0xFFD93D07);
const _green = Color(0xFF4CAF50);

// ---------- layout (px from the top of the content area) ----------
const _topRowH = 48.0;
const _pillsTopFull = 72.0;
const _pillsTopCompact = 6.0; // where the top row used to be
const _transportTop = 120.0; // prev / play / next (100px tall)
const _seekTopFull = 228.0;
const _seekTopCompact = 44.0; // just under the pills in compact mode
const _fullHeight = 288.0;

const _morphDuration = Duration(milliseconds: 250);
const _morphCurve = Curves.easeOutCubic;

class AudioBar extends StatefulWidget {
  const AudioBar({super.key});

  @override
  State<AudioBar> createState() => _AudioBarState();
}

class _AudioBarState extends State<AudioBar> with WidgetsBindingObserver {
  bool _appForeground = true;

  @override
  void initState() {
    super.initState();
    _appForeground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_appForeground == foreground) return;
    setState(() => _appForeground = foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AudioController>(); // rebuilds on notifyListeners()
    final compact = c.compactMode;
    final updatesEnabled =
        _appForeground && TickerMode.valuesOf(context).enabled;
    final showSeek = !compact || c.compactShowsSeek;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 4, 12),
        child: SizedBox(
          height: _fullHeight,
          child: Stack(
            children: [
              // 1) Top row: fades/slides away in compact mode
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: _topRowH,
                child: _Fade(
                  visible: !compact,
                  hiddenOffset: const Offset(0, -0.4),
                  child: _buildTopRow(context, c),
                ),
              ),

              // 2) Pills: the SAME widgets, they glide up into the top row's place
              AnimatedPositioned(
                duration: _morphDuration,
                curve: _morphCurve,
                top: compact ? _pillsTopCompact : _pillsTopFull,
                left: 0,
                right: 12,
                child: _buildPills(c),
              ),

              // 3) Transport: fades out in compact mode
              Positioned(
                top: _transportTop,
                left: 0,
                right: 12,
                height: 100,
                child: _Fade(
                  visible: !compact,
                  hiddenOffset: const Offset(0, 0.3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Neu(
                        size: 50,
                        onTap: c.previous,
                        child: const Icon(Icons.skip_previous),
                      ),
                      const SizedBox(width: 32),
                      // no position updates while hidden = less work
                      _PlayButton(
                        c: c,
                        updatesEnabled: updatesEnabled && !compact,
                      ),
                      const SizedBox(width: 32),
                      _Neu(
                        size: 50,
                        onTap: c.next,
                        child: const Icon(Icons.skip_next),
                      ),
                    ],
                  ),
                ),
              ),

              // 4) Seek bar: moves up in compact mode (or hides, per the flag)
              AnimatedPositioned(
                duration: _morphDuration,
                curve: _morphCurve,
                top: compact ? _seekTopCompact : _seekTopFull,
                left: 0,
                right: 12,
                child: _Fade(
                  visible: showSeek,
                  hiddenOffset: Offset.zero,
                  child: RepaintBoundary(
                    child: _SeekBar(
                      c: c,
                      updatesEnabled: updatesEnabled && showSeek,
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

  // --- author select + 3-dot menu (+ sleep timer) ---
  Widget _buildTopRow(BuildContext context, AudioController c) {
    final fg = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Consumer<SleepTimerController>(
          builder: (_, t, _) => IconButton(
            tooltip: 'Sleep timer',
            icon: Icon(
              t.isActive ? Icons.av_timer_rounded : Icons.av_timer_outlined,
              color: t.isActive ? _accent : null,
            ),
            onPressed: () => showSleepTimer(context),
          ),
        ),
        Expanded(
          child: Center(
            child: c.authors.isEmpty
                ? Text(
                    'No Audio Bible  ✕',
                    style: TextStyle(color: fg.withValues(alpha: .7)),
                  )
                : DropdownButton<String>(
                    value: c.author,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(16),
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    items: [
                      for (final a in c.authors)
                        DropdownMenuItem(
                          value: a,
                          child: Center(
                            child: Text(
                              a,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.amberAccent
                                    : const Color(0xFF632D04),
                              ),
                            ),
                          ),
                        ),
                    ],
                    onChanged: c.setAuthor,
                  ),
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'add':
                showAddAudio(context, c, onUpload: () => _import(context, c));
              case 'delete':
                _delete(context, c);
              case 'help':
                DocView.help('Audio').open(context);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'add', child: Text('Add Audio')),
            PopupMenuItem(
              value: 'delete',
              enabled: c.author != null,
              child: const Text('Delete Author'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'help',
              child: Row(
                children: [
                  Icon(Icons.help_outline, size: 20),
                  SizedBox(width: 12),
                  Text('Audio Help'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- Scroll / Sync / Loop ---
  Widget _buildPills(AudioController c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _Pill(
          label: 'Scroll',
          icon: Icons.mouse_outlined,
          active: c.syncWithReader && c.autoScroll,
          onTap: c.toggleAutoScroll,
        ),
        _Pill(
          label: c.syncWithReader ? "Sync'd" : "DeSync'd",
          icon: Icons.sync,
          active: !c.syncWithReader,
          onTap: c.toggleSync,
        ),
        _Pill(
          label: c.loopLabel,
          icon: Icons.repeat,
          active: c.loopLabel != 'Off',
          onTap: c.cycleLoop,
        ),
      ],
    );
  }

  Future<void> _import(BuildContext context, AudioController c) async {
    if (c.importBusy) return; // ignore impatient taps
    c.importBusy = true;

    final progress = ValueNotifier<double>(0);
    var dialogOpen = false;

    void openDialog() {
      if (dialogOpen || !context.mounted) return;
      dialogOpen = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ImportDialog(progress),
      );
    }

    void closeDialog() {
      if (!dialogOpen || !context.mounted) return;
      dialogOpen = false;
      Navigator.of(context).pop();
    }

    String? msg;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        // Fires while Android copies the zip into the cache: show the dialog now.
        onFileLoading: (status) {
          if (status == FilePickerStatus.picking) openDialog();
        },
      );
      final path = file?.path;
      if (path == null) return; // cancelled (finally still cleans up)

      openDialog(); // no-op if already open
      try {
        final a = await c.importZip(path, (v) => progress.value = v);
        msg = '$a audio extracted successfully!';
      } catch (e) {
        msg = 'Import failed: $e';
      }
    } finally {
      closeDialog();
      c.importBusy = false;
      progress.dispose();
    }

    if (msg != '' && context.mounted) {
      showToast(msg);
    }
  }

  Future<void> _delete(BuildContext context, AudioController c) async {
    final a = c.author;
    if (a == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.colorScheme.secondary,
        title: const Text('Confirm Delete'),
        content: Text(
          'Delete all audio for :\n\t\t\t\t\t"$a"?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await c.deleteCurrentAuthor();
  }
}

// ---------- fade + slide helper ----------
/// Fades + slides a child in/out, and blocks taps while hidden.
class _Fade extends StatelessWidget {
  const _Fade({
    required this.visible,
    required this.child,
    required this.hiddenOffset,
  });
  final bool visible;
  final Widget child;
  final Offset hiddenOffset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible, // invisible buttons must not be tappable
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: _morphDuration,
        curve: _morphCurve,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : hiddenOffset,
          duration: _morphDuration,
          curve: _morphCurve,
          child: child,
        ),
      ),
    );
  }
}

// ---------- play button with progress ring ----------
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.c, required this.updatesEnabled});
  final AudioController c;
  final bool updatesEnabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          StreamBuilder<bool>(
            stream: c.playingStream,
            initialData: false,
            builder: (_, snap) {
              final playing = snap.data ?? false;
              return _Neu(
                size: 60,
                pressed: playing,
                onTap: c.togglePlay,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                        return ScaleTransition(scale: animation, child: child);
                      },
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    key: ValueKey<bool>(playing),
                    size: 30,
                  ),
                ),
              );
            },
          ),
          // Repaints many times a second: isolate it from the rest of the bar.
          RepaintBoundary(
            child: IgnorePointer(
              child: StreamBuilder<Duration>(
                stream: updatesEnabled ? c.positionStream : null,
                initialData: c.position,
                builder: (_, snap) {
                  final total = c.duration?.inMilliseconds ?? 0;
                  final value = total == 0
                      ? 0.0
                      : (snap.data?.inMilliseconds ?? 0) / total;
                  return CustomPaint(
                    size: const Size(71, 71),
                    painter: GlowRingPainter(
                      progress: value.clamp(0.0, 1.0),
                      color: _green,
                      trackColor: context.colorScheme.secondary,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- seek bar ----------
class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.c, required this.updatesEnabled});
  final AudioController c;
  final bool updatesEnabled;

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: updatesEnabled ? c.positionStream : null,
      initialData: c.position,
      builder: (_, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = c.duration ?? Duration.zero;
        final max = dur.inMilliseconds.toDouble();
        final value = pos.inMilliseconds.toDouble().clamp(
          0.0,
          max == 0 ? 1.0 : max,
        );
        return Row(
          children: [
            Text(
              _fmt(pos),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 1,
                  thumbColor: c.isPlaying ? _accent : null,
                  activeTrackColor: _accent,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 9,
                  ),
                ),
                child: Slider(
                  min: 0,
                  max: max == 0 ? 1 : max,
                  value: value,
                  onChanged: max == 0
                      ? null
                      : (v) => c.seek(Duration(milliseconds: v.toInt())),
                ),
              ),
            ),
            Text(
              _fmt(dur),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        );
      },
    );
  }
}

// ---------- import progress dialog ----------
class _ImportDialog extends StatelessWidget {
  const _ImportDialog(this.progress);
  final ValueNotifier<double> progress;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: context.colorScheme.secondary,
        title: const Text('Importing Audio Bible'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                v == 0
                    ? 'Copying zipfile, into the app,\n\n\t\t\t\tOne moment please...'
                    : 'Now extracting audio files...',
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: v > 0
                      ? v / 100
                      : null, // null = animated, shows "working"
                  minHeight: 12,
                  color: _green,
                ),
              ),
              const SizedBox(height: 8),
              if (v > 0)
                Text(
                  '${v.round()}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- neumorphic helpers ----------
class _Neu extends StatelessWidget {
  const _Neu({
    required this.child,
    required this.onTap,
    this.size = 50,
    this.pressed = false,
  });
  final Widget child;
  final VoidCallback onTap;
  final double size;
  final bool pressed;

  // PLAY/PAUSE PREV/NEXT STYLES
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = context.colorScheme.secondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // 45-degree gradient for both active and unpressed states
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: pressed
                  ? const [
                      Color(0xFFAF2900), // Darker burnt orange (top-left)
                      Color(
                        0xFFD64F00,
                      ), // Lighter vibrant orange (bottom-right)
                    ]
                  : [base, base],
            ),
            boxShadow: pressed
                ? [
                    BoxShadow(
                      color: Colors.black54,
                      offset: const Offset(4, 4),
                      inset: true,
                      blurRadius: 8,
                    ),
                    BoxShadow(
                      color: const Color(0xFFFF9900),
                      offset: const Offset(-0.1, -0.1),
                      inset: true,
                      blurRadius: 3,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: dark ? Colors.black54 : const Color(0xFFB8BEC9),
                      offset: const Offset(3, 3),
                      blurRadius: 6,
                    ),
                    BoxShadow(
                      color: dark ? Colors.white10 : Colors.white,
                      offset: const Offset(-3, -3),
                      blurRadius: 6,
                    ),
                  ],
          ),
          child: IconTheme(
            data: IconThemeData(
              color: pressed
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  // SCROLL SYNC LOOP BUTTONS
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = context.colorScheme.secondary;

    final color = active
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 94,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            // 45-degree gradient for both active and unpressed states
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: active
                  ? const [
                      Color(0xFFAF2900), // Darker orange (top-left)
                      Color(0xFFD64F00), // Lighter orange (bottom-right)
                    ]
                  : [base, base],
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black45,
                      offset: const Offset(2, 2),
                      inset: true,
                      blurRadius: 5,
                    ),
                    BoxShadow(
                      color: const Color(0xFFFF9900),
                      offset: const Offset(-0.1, -0.1),
                      inset: true,
                      blurRadius: 3,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: dark ? Colors.black54 : const Color(0xFFB8BEC9),
                      offset: const Offset(3, 3),
                      blurRadius: 6,
                    ),
                    BoxShadow(
                      color: dark ? Colors.white10 : Colors.white,
                      offset: const Offset(-3, -3),
                      blurRadius: 6,
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
