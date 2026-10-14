// lib\widgets\neu_box.dart
import 'package:dba2/core.dart';

class NeuBox extends StatelessWidget {
  final Widget? child;

  const NeuBox({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // is dark mode
    final isDark = context.isDark;

    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          // darker shadow on bottom right
          BoxShadow(
            color: isDark ? Colors.black : Colors.green.shade500,
            blurRadius: 15,
            offset: const Offset(4, 4),
          ),
          // lighter shadow on top left
          BoxShadow(
            color: isDark ? Colors.grey.shade800 : Colors.white,
            blurRadius: 15,
            offset: const Offset(-4, -4),
          ),
        ],
      ),
      padding: EdgeInsets.all(12),
      child: child,
    );
  }
}
