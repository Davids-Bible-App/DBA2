import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai_exception.dart';
import '../downloader.dart';
import '../model_store.dart';
import 'chat_style.dart';
import 'confirm_dialog.dart';

/// Add a custom model (entry == null) or edit / remove a catalog entry.
class CatalogEditorDialog extends StatefulWidget {
  const CatalogEditorDialog({super.key, required this.models, this.entry});
  final ModelStore models;
  final CatalogEntry? entry;

  static Future<void> show(
    BuildContext context,
    ModelStore models, {
    CatalogEntry? entry,
  }) => showDialog<void>(
    context: context,
    builder: (_) => CatalogEditorDialog(models: models, entry: entry),
  );

  @override
  State<CatalogEditorDialog> createState() => _CatalogEditorDialogState();
}

class _CatalogEditorDialogState extends State<CatalogEditorDialog> {
  late final _name = TextEditingController(text: widget.entry?.name ?? '');
  late final _filename = TextEditingController(
    text: widget.entry?.filename ?? '',
  );
  late final _url = TextEditingController(text: widget.entry?.url ?? '');
  late final _size = TextEditingController(
    text: widget.entry == null
        ? ''
        : (widget.entry!.sizeBytes / 1e9).toString(),
  );
  late final _desc = TextEditingController(
    text: widget.entry?.description ?? '',
  );
  bool _busy = false;
  String? _error;

  // Built once per app-theme change, not on every setState.
  late ThemeData _theme;

  static const _gap = SizedBox(height: 10);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _theme = ChatStyle.of(context).themed(Theme.of(context));
  }

  @override
  void dispose() {
    for (final c in [_name, _filename, _url, _size, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _probeSize() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final probe = await probeRemote(Uri.parse(url));
      _size.text = ((probe.total / 1e9 * 100).round() / 100)
          .toString(); // 2 dp, rounded
    } catch (e) {
      _error = errorMessage(e, "Couldn't fetch that URL's size.");
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    final bytes = ((double.tryParse(_size.text) ?? 0) * 1e9).round();
    if (bytes <= 0) {
      setState(() => _error = 'Enter a valid size in GB.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.models.upsertCatalogEntry(
        id: widget.entry?.id,
        name: _name.text,
        filename: _filename.text,
        url: _url.text,
        sizeBytes: bytes,
        description: _desc.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e, "Couldn't save that model.");
        });
      }
    }
  }

  Future<void> _remove() async {
    final sure = await confirmDialog(
      context,
      title: 'Remove model',
      message: 'Remove this model from the catalog?',
      confirmLabel: 'Remove',
    );
    if (!sure) return;
    widget.models.deleteCatalogEntry(widget.entry!.id);
    if (mounted) Navigator.pop(context);
  }

  // Borders and fill now come from the theme, so only the label is set here.
  InputDecoration _dec(String label) =>
      InputDecoration(labelText: label, isDense: true);

  @override
  Widget build(BuildContext context) {
    final errorColor = _theme.colorScheme.error;
    return Theme(
      data: _theme,
      child: AlertDialog(
        title: Text(widget.entry == null ? 'Add custom model' : 'Edit model'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_error!, style: TextStyle(color: errorColor)),
                  ),
                TextField(controller: _name, decoration: _dec('Name')),
                _gap,
                TextField(
                  controller: _filename,
                  decoration: _dec('Filename (.gguf)'),
                ),
                _gap,
                TextField(controller: _url, decoration: _dec('Download URL')),
                _gap,
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _size,
                        decoration: _dec('Size (GB)'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : _probeSize,
                      child: Text(_busy ? '…' : 'Get size'),
                    ),
                  ],
                ),
                _gap,
                TextField(
                  controller: _desc,
                  decoration: _dec('Description'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (widget.entry != null)
            TextButton(
              onPressed: _busy ? null : _remove,
              style: TextButton.styleFrom(foregroundColor: errorColor),
              child: const Text('Remove'),
            ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
