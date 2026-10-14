// lib/widgets/bar_gesture_settings_section.dart
import 'package:dba2/core.dart';
import 'package:dba2/state/bar_gesture_settings.dart';

/// Drop-in section for the settings page: one dropdown per bar gesture.
class BarGestureSettingsSection extends StatelessWidget {
  const BarGestureSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<BarGestureSettings>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const _GroupHeader('Top bar gestures'),
        for (final g in BarGesture.values)
          _GestureRow(side: BarSide.top, gesture: g, settings: settings),
        const SizedBox(height: 12),
        const _GroupHeader('Bottom bar gestures'),
        for (final g in BarGesture.values)
          _GestureRow(side: BarSide.bottom, gesture: g, settings: settings),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: settings.resetAll,
            child: const Text('Reset gestures'),
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
    ),
  );
}

class _GestureRow extends StatelessWidget {
  const _GestureRow({
    required this.side,
    required this.gesture,
    required this.settings,
  });

  final BarSide side;
  final BarGesture gesture;
  final BarGestureSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: context.colorScheme.tertiary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              gesture.label(side),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          DropdownButton<BarAction>(
            value: settings.actionFor(side, gesture),
            underline: const SizedBox.shrink(),
            isDense: true,
            items: [
              for (final a in BarAction.values)
                DropdownMenuItem(value: a, child: Text(a.label)),
            ],
            onChanged: (a) {
              if (a != null) settings.setAction(side, gesture, a);
            },
          ),
        ],
      ),
    );
  }
}
