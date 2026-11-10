import 'package:dba2/ui/widgets/overlay_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'meme_theme.dart';

/// Text / toggle button. [active] gives the "pressed" look.
class MemeButton extends StatelessWidget {
  const MemeButton(
    this.label, {
    super.key,
    this.onPressed,
    this.active = false,
    this.danger = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool active, danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    final bg = danger
        ? t.danger.withValues(alpha: 0.18)
        : (active ? t.buttonBgActive : t.buttonBg);
    final fg = danger ? t.danger : t.buttonFg;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(0, 38), // comfortable touch target
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusS),
          side: BorderSide(color: active ? t.accent : t.border),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17),
            if (label.isNotEmpty) const SizedBox(width: 6),
          ],
          if (label.isNotEmpty)
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class MemeIconButton extends StatelessWidget {
  const MemeIconButton(
    this.icon, {
    super.key,
    this.onPressed,
    this.tooltip,
    this.active = false,
    this.size = 20,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: size,
      visualDensity: VisualDensity.compact,
      color: active ? t.accent : t.textDim,
      icon: Icon(icon),
    );
  }
}

class MemePanel extends StatelessWidget {
  const MemePanel({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: t.gap),
      padding: padding,
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(t.radiusM),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(title!, style: t.header)),
                  ?trailing,
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Label + current value + slider in one tidy block.
class MemeSliderRow extends StatelessWidget {
  const MemeSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.unit = '',
    this.decimals = 1,
    this.onReset,
  });
  final String label, unit;
  final double value, min, max;
  final int decimals;
  final ValueChanged<double>? onChanged; // null = disabled (greyed out)
  final VoidCallback? onChangeEnd, onReset;

  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label  ${value.toStringAsFixed(decimals)}$unit',
                style: t.label,
              ),
            ),
            if (onReset != null)
              InkWell(
                onTap: onReset,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    'reset',
                    style: t.label.copyWith(color: t.accent),
                  ),
                ),
              ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: t.accent,
            thumbColor: t.accent,
            inactiveTrackColor: t.border,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            // Only dragging the round thumb changes the value, so a finger
            // brushing the track while scrolling does nothing.
            allowedInteraction: SliderInteraction.slideThumb,
            onChanged: onChanged,
            onChangeEnd: (_) => onChangeEnd?.call(),
          ),
        ),
      ],
    );
  }
}

/// Tap to open a colour picker dialog (live updates while you drag).
class MemeColorSwatch extends StatelessWidget {
  const MemeColorSwatch({
    super.key,
    required this.label,
    required this.color,
    required this.onChanged,
  });
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(t.radiusS),
      onTap: () => showLockedDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(label),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: color,
              onColorChanged: onChanged,
              enableAlpha: false,
              hexInputBar: true,
              pickerAreaHeightPercent: 0.7,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(t.radiusS),
                border: Border.all(color: t.border, width: 1.5),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: t.label),
          ],
        ),
      ),
    );
  }
}

// ───────── dialogs (use the overlay lock so sidebars can't be dragged) ─────────

Future<bool> memeConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String ok = 'OK',
}) async {
  final r = await showLockedDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

Future<void> memeInfo(BuildContext context, String title, String message) =>
    showLockedDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );

Future<String?> memePrompt(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
}) {
  final ctl = TextEditingController(text: initial);
  return showLockedDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctl.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
