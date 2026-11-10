import 'package:flutter/material.dart';

import 'md_controller.dart';
import 'md_theme.dart';

/// Live theme tweaker: changes apply instantly to the editor behind it
/// and are saved through the controller's storage.
Future<void> showMdThemeEditor(
  BuildContext context,
  MarkdownEditorController c,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: ValueListenableBuilder<MdTheme>(
          valueListenable: c.theme,
          builder: (ctx, th, _) => _ThemePanel(controller: c, theme: th),
        ),
      ),
    ),
  );
}

const _fonts = <String, String?>{
  'System default': null,
  'Segoe UI': 'Segoe UI',
  'Arial': 'Arial',
  'Georgia': 'Georgia',
  'Times New Roman': 'Times New Roman',
  'Consolas': 'Consolas',
};

class _ThemePanel extends StatelessWidget {
  const _ThemePanel({required this.controller, required this.theme});
  final MarkdownEditorController controller;
  final MdTheme theme;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    void set(MdTheme t) => c.updateTheme(t);

    Widget slider(
      String label,
      double v,
      double min,
      double max,
      ValueChanged<double> on,
    ) => Row(
      children: [
        SizedBox(width: 130, child: Text(label)),
        Expanded(
          child: Slider(
            value: v.clamp(min, max),
            min: min,
            max: max,
            onChanged: on,
          ),
        ),
        SizedBox(width: 40, child: Text(v.toStringAsFixed(v < 5 ? 2 : 0))),
      ],
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(
            children: [
              Text('Theme', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.light_mode_outlined),
                    label: const Text('Light preset'),
                    onPressed: () => set(MdTheme.light()),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.dark_mode_outlined),
                    label: const Text('Dark preset'),
                    onPressed: () => set(MdTheme.dark()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              slider(
                'Editor font',
                theme.editorFontSize,
                10,
                28,
                (v) => set(theme.copyWith(editorFontSize: v.roundToDouble())),
              ),
              slider(
                'Preview font',
                theme.previewFontSize,
                12,
                28,
                (v) => set(theme.copyWith(previewFontSize: v.roundToDouble())),
              ),
              slider(
                'Line height',
                theme.lineHeight,
                1.0,
                2.2,
                (v) => set(theme.copyWith(lineHeight: v)),
              ),
              slider(
                'Paragraph gap',
                theme.paragraphSpacing,
                0,
                32,
                (v) => set(theme.copyWith(paragraphSpacing: v.roundToDouble())),
              ),
              slider(
                'Padding',
                theme.contentPadding,
                0,
                48,
                (v) => set(theme.copyWith(contentPadding: v.roundToDouble())),
              ),
              Row(
                children: [
                  const SizedBox(width: 130, child: Text('Font')),
                  DropdownButton<String>(
                    value: _fonts.entries
                        .firstWhere(
                          (e) => e.value == theme.fontFamily,
                          orElse: () => _fonts.entries.first,
                        )
                        .key,
                    items: [
                      for (final k in _fonts.keys)
                        DropdownMenuItem(value: k, child: Text(k)),
                    ],
                    onChanged: (k) => set(
                      k == null || _fonts[k] == null
                          ? theme.copyWith(clearFontFamily: true)
                          : theme.copyWith(fontFamily: _fonts[k]),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                // dense: true,
                title: const Text('Monospace editor'),
                value: theme.monoEditor,
                onChanged: (v) => set(theme.copyWith(monoEditor: v)),
              ),
              const Divider(),
              for (final slot in MdColor.values)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(slot.label),
                  trailing: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: theme.c(slot),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  onTap: () => showDialog<void>(
                    context: context,
                    barrierColor: Colors.black12,
                    builder: (_) => _ColorDialog(
                      title: slot.label,
                      initial: theme.c(slot),
                      onChanged: (col) =>
                          set(controller.theme.value.withColor(slot, col)),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({
    required this.title,
    required this.initial,
    required this.onChanged,
  });
  final String title;
  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late int r = (widget.initial.r * 255).round();
  late int g = (widget.initial.g * 255).round();
  late int b = (widget.initial.b * 255).round();
  late final TextEditingController hex = TextEditingController(text: _hex);

  String get _hex =>
      '${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  void _emit({bool updateHex = true}) {
    if (updateHex) hex.text = _hex;
    widget.onChanged(Color.fromARGB(255, r, g, b));
    setState(() {});
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget ch(String label, int v, Color active, ValueChanged<int> on) => Row(
      children: [
        SizedBox(width: 16, child: Text(label)),
        Expanded(
          child: Slider(
            value: v.toDouble(),
            min: 0,
            max: 255,
            activeColor: active,
            onChanged: (x) {
              on(x.round());
              _emit();
            },
          ),
        ),
        SizedBox(width: 32, child: Text('$v')),
      ],
    );

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: Color.fromARGB(255, r, g, b),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ch('R', r, Colors.red, (v) => r = v),
            ch('G', g, Colors.green, (v) => g = v),
            ch('B', b, Colors.blue, (v) => b = v),
            TextField(
              controller: hex,
              maxLength: 6,
              decoration: const InputDecoration(
                prefixText: '#',
                labelText: 'Hex',
                counterText: '',
              ),
              onChanged: (s) {
                final v = int.tryParse(s, radix: 16);
                if (s.length == 6 && v != null) {
                  r = (v >> 16) & 255;
                  g = (v >> 8) & 255;
                  b = v & 255;
                  _emit(updateHex: false);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
