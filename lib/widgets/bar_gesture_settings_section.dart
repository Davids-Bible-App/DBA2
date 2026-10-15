// lib/widgets/bar_gesture_settings_section.dart
import 'package:dba2/core.dart';
import 'package:dba2/state/bar_gesture_settings.dart';
import 'package:dba2/widgets/settings/settings_kit.dart';

/// Drop-in section for the settings page: one dropdown per bar gesture.
class BarGestureSettingsSection extends StatelessWidget {
  const BarGestureSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<BarGestureSettings>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final side in BarSide.values)
          SettingsSection(
            title: side == BarSide.top
                ? 'Top bar gestures'
                : 'Bottom bar gestures',
            children: [
              for (final g in BarGesture.values)
                SettingsDropdownTile<BarAction>(
                  title: g.label(side),
                  value: settings.actionFor(side, g),
                  items: BarAction.values,
                  labelOf: (a) => a.label,
                  onChanged: (a) => settings.setAction(side, g, a),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SettingsSection(
            children: [
              SettingsButtonTile(
                icon: Icons.restart_alt,
                title: 'Reset gestures',
                buttonLabel: 'Reset',
                onPressed: settings.resetAll,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
