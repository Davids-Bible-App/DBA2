// import '../../main/gallery/models.dart';

import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:dba2/themes/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _cutoutChannel = MethodChannel('app/cutout');

Future<void> _setDrawUnderCutout(bool enable) async {
  if (!Platform.isAndroid) return;
  try {
    await _cutoutChannel.invokeMethod('setDrawUnderCutout', enable);
  } on PlatformException {
    // Non-fatal: worst case the notch padding stays.
  }
}

// Which way the text turns in portrait: 1 = clockwise, 3 = counter-clockwise.
const int _kPortraitTurns = 1;

const double _kMaxFont = 34;
const double _kMinFont = 14;
const double _kLineHeight = 1.3;

/// What the viewer needs, nothing more. Callers convert their own data to this.
@immutable
class UniVerseItem {
  const UniVerseItem({required this.citation, required this.text});
  final String citation; // e.g. "KJV John 3:16"
  final String text;
}

class UniVerse extends StatefulWidget {
  const UniVerse({
    super.key,
    required this.verses,
    required this.onClose,
    this.initialIndex = 0,
  });
  final List<UniVerseItem> verses;
  final VoidCallback onClose;
  final int initialIndex;
  @override
  State<UniVerse> createState() => _UniVerseState();
}

class _UniVerseState extends State<UniVerse> with WidgetsBindingObserver {
  late final _page = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  final _pts = <int, Offset>{};
  double? _startDist;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _setDrawUnderCutout(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setDrawUnderCutout(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _page.dispose();
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    widget.onClose();
    return true;
  }

  double _dist() => (_pts.values.first - _pts.values.last).distance;

  void _up(PointerEvent e) {
    _pts.remove(e.pointer);
    _startDist = null;
  }

  // String _citation(GalleryEntry e) =>
  //     '${e.abbr} ${e.bookName} ${e.chapter}:${e.verseId}';

  @override
  Widget build(BuildContext context) {
    final isDark = context.colorScheme.brightness == Brightness.dark;
    final verses = widget.verses;
    // final last = verses.length - 1;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final chromeH = landscape ? 32.0 : 48.0;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 25),
      child: Column(
        children: [
          SizedBox(
            height: chromeH,
            child: Center(
              child: Opacity(
                opacity: 0.8,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    verses[_index].citation,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: PointerDeviceKind.values.toSet(),
              ),
              child: PageView.builder(
                controller: _page,
                itemCount: verses.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _FitText(verses[i].text),
              ),
            ),
          ),
          _PageIndicator(
            controller: _page,
            count: verses.length,
            fallbackIndex: _index,
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: (isDark ? Colors.black : Colors.white),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _pts[e.pointer] = e.position;
          if (_pts.length == 2) _startDist = _dist();
        },
        onPointerMove: (e) {
          if (!_pts.containsKey(e.pointer)) return;
          _pts[e.pointer] = e.position;
          final s = _startDist;
          if (_pts.length == 2 && s != null && s > 0 && !_closing) {
            if (_dist() / s < 0.7) {
              _closing = true;
              widget.onClose();
            }
          }
        },
        onPointerUp: _up,
        onPointerCancel: _up,
        child: RotatedBox(
          quarterTurns: landscape ? 0 : _kPortraitTurns,
          child: content,
        ),
      ),
    );
  }
}

/// Port of adjustFontSize(): start big, step down until the text fits.
class _FitText extends StatelessWidget {
  const _FitText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final base = DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, c) {
        double heightAt(double size) {
          final tp = TextPainter(
            text: TextSpan(
              text: text,
              style: base.copyWith(fontSize: size, height: _kLineHeight),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            textScaler: scaler,
          )..layout(maxWidth: c.maxWidth);
          final h = tp.height;
          tp.dispose();
          return h;
        }

        var size = math.min(math.min(c.maxWidth, c.maxHeight) * 0.4, _kMaxFont);
        while (size > _kMinFont && heightAt(size) > c.maxHeight) {
          size -= 1;
        }
        debugPrint('fit: size=$size');
        return Center(
          child: SingleChildScrollView(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: size,
                height: _kLineHeight,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.controller,
    required this.count,
    required this.fallbackIndex,
  });
  final PageController controller;
  final int count;
  final int fallbackIndex;

  static const _maxDots = 12;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox(height: 20);
    final color = Theme.of(context).colorScheme.inverseSurface;

    return SizedBox(
      height: 20,
      child: Center(
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, _) {
            final page = controller.positions.length == 1
                ? (controller.page ?? fallbackIndex.toDouble())
                : fallbackIndex.toDouble();
            return count <= _maxDots
                ? FittedBox(fit: BoxFit.scaleDown, child: _dots(page, color))
                : _dash(page, color);
          },
        ),
      ),
    );
  }

  // Small sets: one dot per verse; the active one stretches into a dash.
  Widget _dots(double page, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++)
        Container(
          width: 6 + 14 * (1 - (page - i).abs().clamp(0.0, 1.0)),
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: color.withValues(
              alpha: 0.25 + 0.55 * (1 - (page - i).abs().clamp(0.0, 1.0)),
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ],
  );

  // Large sets: a thin track with a sliding dash.
  Widget _dash(double page, Color color) {
    const trackW = 280.0;
    final thumbW = math.max(trackW / count, 14.0);
    final left = (page / (count - 1)) * (trackW - thumbW);
    return SizedBox(
      width: trackW,
      height: 6,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned(
            left: left,
            width: thumbW,
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
