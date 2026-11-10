import 'package:flutter/material.dart';

class TopicDescription extends StatefulWidget {
  const TopicDescription({
    super.key,
    required this.topic,
    required this.description,
    required this.onSave,
  });
  final String topic;
  final String description;
  final Future<void> Function(String) onSave;

  @override
  State<TopicDescription> createState() => _TopicDescriptionState();
}

class _TopicDescriptionState extends State<TopicDescription> {
  final _c = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() => setState(() {
    _expanded = !_expanded;
    if (_expanded) _c.text = widget.description;
  });

  Future<void> _save() async {
    await widget.onSave(_c.text);
    if (mounted) setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final described = widget.description.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  label: Text('🏷️ ${widget.topic}'),
                  visualDensity: VisualDensity.compact,
                ),
                Row(
                  children: [
                    Icon(_expanded ? Icons.arrow_drop_down : Icons.arrow_right),
                    Text(
                      described ? 'Described' : 'Describe',
                      style: TextStyle(color: described ? cs.primary : null),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _c,
              minLines: 4,
              maxLines: 10,

              decoration: InputDecoration(
                hintText: 'Describe the purpose of this topic...',
                filled: true,
                fillColor: isDark ? Colors.grey[850] : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _toggle, child: const Text('Cancel')),
                FilledButton.tonal(
                  onPressed: _save,
                  child: const Text('Save Description'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
