// Replaces CountdownTimer.jsx's markup + CountdownTimer.css.
import 'package:dba2/core.dart';

import '../state/sleep_timer_controller.dart';

const _green = Color(0xFF4ADE80);
const _orange = Color(0xFFFB923C);

/// Opens the timer in a bottom sheet.
void showSleepTimer(BuildContext context) {
  showModalBottomSheet(
    backgroundColor: context.colorScheme.secondary,
    context: context,
    isScrollControlled: true,
    builder: (_) => const SafeArea(
      child: Padding(padding: EdgeInsets.all(24), child: SleepTimerPanel()),
    ),
  );
}

class SleepTimerPanel extends StatelessWidget {
  const SleepTimerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SleepTimerController>();
    final fg = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,

      children: [
        const Text(
          'Stop Audio After:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WheelColumn(
              label: 'HH',
              min: 0,
              max: 5,
              value: t.dispH,
              enabled: t.editable,
              onChanged: t.setHours,
            ),
            const _Sep(),
            _WheelColumn(
              label: 'MM',
              min: 0,
              max: 59,
              value: t.dispM,
              enabled: t.editable,
              onChanged: t.setMinutes,
            ),
            const _Sep(),
            // Seconds are always read-only: they just show the live countdown.
            _WheelColumn(
              label: 'SS',
              min: 0,
              max: 59,
              value: t.dispS,
              enabled: false,
              onChanged: (_) {},
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            t.isActive
                ? _TimerButton(
                    label: 'Stop',
                    color: _orange,
                    onTap: t.pauseTimer,
                  )
                : _TimerButton(
                    label: t.hasTime ? 'Resume' : 'Start',
                    color: _green,
                    onTap: t.begin,
                  ),
            const SizedBox(width: 14),
            _TimerButton(label: 'Reset', color: fg, onTap: t.reset),
          ],
        ),
      ],
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SizedBox(
        height: 240,
        child: Center(
          child: Text(
            ':',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
          ),
        ),
      ),
      SizedBox(height: 22), // matches the label height under the wheels
    ],
  );
}

// ---------- one drum-roll column (like ScrollColumn) ----------
class _WheelColumn extends StatefulWidget {
  const _WheelColumn({
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final String label;
  final int min, max, value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<_WheelColumn> {
  late final FixedExtentScrollController _ctrl;
  late int _sel;
  bool _programmatic = false; // true while WE move the wheel (not the user)

  @override
  void initState() {
    super.initState();
    _sel = widget.value;
    _ctrl = FixedExtentScrollController(initialItem: widget.value - widget.min);
  }

  @override
  void didUpdateWidget(_WheelColumn old) {
    super.didUpdateWidget(old);
    // The countdown (or a reset) changed the value: move the wheel to match.
    final target = widget.value - widget.min;
    if (!_ctrl.hasClients || _ctrl.selectedItem == target) return;
    _sel = widget.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ctrl.hasClients || _ctrl.selectedItem == target) return;
      _programmatic = true;
      if ((_ctrl.selectedItem - target).abs() == 1) {
        _ctrl
            .animateToItem(
              target,
              duration: const Duration(milliseconds: 140),
              curve: Curves.linear,
            )
            .whenComplete(() => _programmatic = false);
      } else {
        _ctrl.jumpToItem(target);
        _programmatic = false;
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(int index) {
    final v = index + widget.min;
    if (_sel != v) setState(() => _sel = v);
    if (!_programmatic && widget.enabled && v != widget.value) {
      widget.onChanged(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 76,
          height: 240, // 5 rows x 48
          child: Stack(
            children: [
              IgnorePointer(
                ignoring: !widget.enabled,
                child: ListWheelScrollView.useDelegate(
                  controller: _ctrl,
                  itemExtent: 48,
                  diameterRatio: 50, // large = looks flat, like your CSS list
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: _onChanged,
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: widget.max - widget.min + 1,
                    builder: (_, i) {
                      final d = (i - (_sel - widget.min)).abs();
                      return Center(
                        child: Opacity(
                          opacity: d == 0
                              ? 1
                              : d == 1
                              ? .55
                              : d == 2
                              ? .22
                              : 0,
                          child: Text(
                            '${i + widget.min}'.padLeft(2, '0'),
                            style: TextStyle(
                              fontSize: 24,
                              letterSpacing: 1.5,
                              fontWeight: d == 0
                                  ? FontWeight.w900
                                  : d == 1
                                  ? FontWeight.w500
                                  : FontWeight.w100,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // centre-row highlight band
              Center(
                child: IgnorePointer(
                  child: Container(
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.label,
          style: const TextStyle(fontSize: 10, letterSpacing: 1.4),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

// ---------- neumorphic button ----------
class _TimerButton extends StatelessWidget {
  const _TimerButton({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: BoxDecoration(
          color: context.colorScheme.secondary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
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
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
          ),
        ),
      ),
    );
  }
}
