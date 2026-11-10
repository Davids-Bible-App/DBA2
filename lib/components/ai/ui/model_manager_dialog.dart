import 'dart:async';
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../ai_exception.dart';
import '../ai_services.dart';
import '../downloader.dart';
import '../gguf.dart';
import '../model_store.dart';
import '../model_backup.dart';
import 'catalog_editor_dialog.dart';
import 'chat_style.dart';
import 'confirm_dialog.dart';
import 'engine_install_banner.dart';

String _gb(num bytes) => '${(bytes / 1e9).toStringAsFixed(1)} GB';

/// Small secondary text (sizes, hints, status lines).
TextStyle _small(ChatStyle s) => TextStyle(
  fontSize: s.fontSize - 3,
  color: s.actionIcon,
  fontFamily: s.fontFamily,
);

class ModelManagerDialog extends StatefulWidget {
  const ModelManagerDialog({super.key, required this.ai});
  final AiServices ai;

  static Future<void> show(BuildContext context, AiServices ai) =>
      showDialog<void>(
        context: context,
        builder: (_) => ModelManagerDialog(ai: ai),
      );

  @override
  State<ModelManagerDialog> createState() => _ModelManagerDialogState();
}

class _ModelManagerDialogState extends State<ModelManagerDialog> {
  AiServices get ai => widget.ai;

  // Style + the themed ThemeData are rebuilt only when the app theme changes.
  late ChatStyle _s;
  late ThemeData _theme;

  List<LocalModel> _locals = const [];
  List<CatalogEntry> _catalog = const [];
  String? _busy; // filename | '__unload__' | '__upload__'
  String? _error;
  String? _info;
  String? _importNote; // what the import is doing right now
  double? _importFraction; // null = unknown, shows the sliding animation
  String? _backingUp; // filename currently being backed up
  String? _expandedPrompt;
  String? _expandedGpu;
  String? _renaming;
  final _renameCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    ai.models.addListener(_reload); // ModelStore notifies after every change
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _s = ChatStyle.of(context);
    _theme = _s.themed(Theme.of(context));
  }

  @override
  void dispose() {
    ai.models.removeListener(_reload);
    _renameCtl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final locals = await ai.models.listLocal();
      final catalog = await ai.models.catalog();
      if (!mounted) return;
      setState(() {
        _locals = locals;
        _catalog = catalog;
      });
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load model list.");
    }
  }

  /// Runs [action] with a busy marker and unified error handling.
  Future<void> _run(
    String key,
    Future<void> Function() action,
    String fallback,
  ) async {
    setState(() {
      _busy = key;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, fallback));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _delete(LocalModel m) async {
    final sure = await confirmDialog(
      context,
      title: 'Delete model',
      message: "Delete ${m.filename}? This can't be undone.",
    );
    if (!sure) return;
    await _run(
      m.filename,
      () => ai.models.deleteLocal(m.filename),
      "Couldn't delete that model.",
    );
  }

  Future<void> _backup(LocalModel m) async {
    setState(() {
      _info = null;
      _backingUp = m.filename;
    });
    await _run(m.filename, () async {
      final saved = await ModelBackup.export(
        ai.models.fileOf(m.filename),
        m.filename,
      );
      if (saved && mounted) {
        setState(
          () => _info =
              'Backup saved. To restore it later, use "+ Upload from device".',
        );
      }
    }, "Couldn't save the backup.");
    if (mounted) setState(() => _backingUp = null);
  }

  Future<void> _upload() async {
    setState(() {
      _busy = '__upload__';
      _error = null;
      _info = null;
      _importNote = null;
      _importFraction = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gguf'],
        // Fires once you've chosen a file and Android starts copying it.
        onFileLoading: (status) {
          if (status == FilePickerStatus.picking && mounted) {
            setState(
              () => _importNote = 'Copying file from your device… large files can take several minutes.',
            );
          }
        },
      );
      final path = result.firstOrNull?.path;
      if (path == null) return; // cancelled; `finally` resets the state
      if (mounted) setState(() => _importNote = 'Finishing import…');
      await ai.models.importModel(
        path,
        onProgress: (f) {
          if (mounted) setState(() => _importFraction = f);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorMessage(e, "Couldn't import that file."));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _importNote = null;
          _importFraction = null;
        });
      }
    }
  }

  Future<void> _download(CatalogEntry e) async {
    setState(() => _error = null);
    try {
      await ai.models.download(e);
    } on DownloadCancelled {
      // user pressed Cancel: nothing to report
    } catch (err) {
      if (mounted) {
        setState(() => _error = errorMessage(err, 'Download failed.'));
      }
    }
  }

  void _startRename(LocalModel m) {
    _renameCtl.text = m.displayName;
    _renameCtl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _renameCtl.text.length,
    );
    setState(() {
      _renaming = m.filename;
      _error = null;
    });
  }

  Future<void> _confirmRename(LocalModel m) async {
    final name = _renameCtl.text.trim();
    setState(() => _renaming = null);
    if (name.isEmpty || name == m.displayName) return;
    await _run(
      m.filename,
      () => ai.models.setDisplayName(m.filename, name),
      "Couldn't rename that model.",
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Theme(
      data: _theme,
      child: Dialog(
        backgroundColor: s.background,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(s.bubbleRadius + 2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
          // Rebuild when the engine (active model, buffers) or the store (downloads) changes.
          child: ListenableBuilder(
            listenable: Listenable.merge([ai.engine, ai.models]),
            builder: (context, _) {
              final notice = ai.engine.gpuNotice;
              return Column(
                children: [
                  Container(
                    color: s.appBar,
                    padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                    child: Row(
                      children: [
                        Text(
                          'Models',
                          style: TextStyle(
                            color: s.appBarText,
                            fontSize: s.fontSize + 5,
                            fontWeight: FontWeight.w600,
                            fontFamily: s.fontFamily,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          color: s.appBarText,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      children: [
                        if (ai.installer != null)
                          EngineInstallBanner(
                            engine: ai.engine,
                            installer: ai.installer!,
                          ),
                        if (_error != null) _Banner(_error!, error: true),
                        if (_info != null) _Banner(_info!),
                        if (notice != null) _Banner(notice),
                        const _SectionTitle('Your models'),
                        if (_locals.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No models downloaded yet.',
                              style: _small(s),
                            ),
                          ),
                        for (final m in _locals) ...[
                          _localTile(m),
                          if (_expandedPrompt == m.filename)
                            _PromptEditor(
                              key: ValueKey('p-${m.filename}'),
                              ai: ai,
                              filename: m.filename,
                            ),
                          if (_expandedGpu == m.filename)
                            _GpuEditor(
                              key: ValueKey('g-${m.filename}'),
                              ai: ai,
                              model: m,
                            ),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton(
                                onPressed: _busy == null ? _upload : null,
                                child: Text(
                                  _busy == '__upload__'
                                      ? 'Importing…'
                                      : '+ Upload from device',
                                ),
                              ),
                              if (_busy == '__upload__' &&
                                  _importNote != null) ...[
                                const SizedBox(height: 8),
                                LinearProgressIndicator(value: _importFraction),
                                const SizedBox(height: 4),
                                Text(
                                  _importFraction == null
                                      ? _importNote!
                                      : 'Copying… ${(_importFraction! * 100).round()}%',
                                  style: _small(s),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const _SectionTitle('Available to download'),
                        if (Platform.isAndroid)
                          const _Banner(
                            'Models are several GB. Use Wi-Fi to download them unless '
                            'you have an unlimited mobile data plan.',
                          ),
                        if (_catalog.every((e) => e.downloaded))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Nothing else in the catalog.',
                              style: _small(s),
                            ),
                          ),
                        for (final e in _catalog.where((e) => !e.downloaded))
                          _catalogTile(e),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton(
                            onPressed: () =>
                                CatalogEditorDialog.show(context, ai.models),
                            child: const Text('+ Add custom model'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback? onPressed, {bool danger = false}) {
    final color = danger ? _theme.colorScheme.error : _s.aiText;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 37),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: TextStyle(fontSize: _s.fontSize - 2),
        foregroundColor: color,
        side: BorderSide(
          color: danger
              ? _theme.colorScheme.error.withValues(alpha: 0.6)
              : _s.inputBorder,
        ),
      ),
      child: Text(label),
    );
  }

  Widget _localTile(LocalModel m) {
    final s = _s;
    final active = ai.engine.activeFilename == m.filename;
    final working = _busy == m.filename;
    final badge = switch (m.promptSource) {
      PromptSource.override => 'Custom prompt',
      PromptSource.file => 'File prompt',
      PromptSource.builtIn => 'Default prompt',
    };
    final nameStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: s.fontSize,
      color: s.aiText,
      fontFamily: s.fontFamily,
    );
    return Card(
      // Active model gets a soft accent wash over the normal card colour.
      color: active ? s.aiBubble : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _renaming == m.filename
                      ? TextField(
                          controller: _renameCtl,
                          autofocus: true,
                          style: TextStyle(color: s.inputText),
                          decoration: InputDecoration(
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.check),
                              onPressed: () => _confirmRename(m),
                            ),
                          ),
                          onSubmitted: (_) => _confirmRename(m),
                          onTapOutside: (_) => setState(() => _renaming = null),
                        )
                      : Tooltip(
                          message: 'Tap to rename · file: ${m.filename}',
                          child: InkWell(
                            onTap: _busy == null ? () => _startRename(m) : null,
                            child: Text(
                              '${active ? '✓ ' : ''}${m.displayName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nameStyle,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Text(_gb(m.sizeBytes), style: _small(s)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  label: Text(badge),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                if (!active)
                  _btn(
                    working ? '…' : 'Use',
                    _busy == null
                        ? () => _run(
                            m.filename,
                            () => ai.useModel(m.filename),
                            "Couldn't switch models.",
                          )
                        : null,
                  )
                else
                  _btn(
                    _busy == '__unload__' ? '…' : 'Unload',
                    _busy == null
                        ? () {
                            _expandedGpu = null;
                            _run(
                              '__unload__',
                              ai.engine.unload,
                              "Couldn't unload the model.",
                            );
                          }
                        : null,
                  ),
                _btn(
                  _expandedPrompt == m.filename ? 'Hide prompt' : 'Prompt',
                  () => setState(
                    () => _expandedPrompt = _expandedPrompt == m.filename
                        ? null
                        : m.filename,
                  ),
                ),
                if (active && !Platform.isAndroid) // Android build is CPU-only
                  _btn(
                    _expandedGpu == m.filename ? 'Hide GPU' : 'GPU',
                    () => setState(
                      () => _expandedGpu = _expandedGpu == m.filename
                          ? null
                          : m.filename,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // Backup on the left, Delete on the right.
            Row(
              children: [
                if (ModelBackup.supported)
                  Tooltip(
                    message: 'Local save, to avoid re-download',
                    child: _btn(
                      'Backup',
                      _busy == null ? () => _backup(m) : null,
                    ),
                  ),
                const Spacer(),
                _btn(
                  'Delete',
                  active || _busy != null ? null : () => _delete(m),
                  danger: true,
                ),
              ],
            ),
            if (working)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_backingUp == m.filename)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Saving… keep the app open until this finishes.',
                  style: _small(s),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _catalogTile(CatalogEntry e) {
    final s = _s;
    final dl = ai.models.downloads[e.id];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: e.description.isEmpty ? e.name : e.description,
                    child: Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: s.fontSize,
                        color: s.aiText,
                        fontFamily: s.fontFamily,
                      ),
                    ),
                  ),
                ),
                Text(_gb(e.sizeBytes), style: _small(s)),
              ],
            ),
            if (dl != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                // Only this bar rebuilds ~7x/second while downloading.
                child: ValueListenableBuilder<DownloadProgress>(
                  valueListenable: dl.progress,
                  builder: (context, p, _) =>
                      LinearProgressIndicator(value: p.fraction),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 6,
                  children: [
                    if (dl == null) ...[
                      _btn('Download', () => _download(e)),
                      _btn(
                        'Edit',
                        () => CatalogEditorDialog.show(
                          context,
                          ai.models,
                          entry: e,
                        ),
                      ),
                    ] else
                      _btn(
                        'Cancel',
                        () => ai.models.cancelDownload(e.id),
                        danger: true,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final s = ChatStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: s.fontSize - 2,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: s.actionIcon,
          fontFamily: s.fontFamily,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, {this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final s = ChatStyle.of(context);
    final cs = Theme.of(context).colorScheme;
    final fg = error ? cs.onErrorContainer : s.aiText;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: error ? cs.errorContainer : s.codeBackground,
        borderRadius: BorderRadius.circular(s.bubbleRadius - 4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: s.fontSize - 2,
          fontFamily: s.fontFamily,
        ),
      ),
    );
  }
}

// ── Prompt editor ────────────────────────────────────────────────────────
// Its own widget so typing here never rebuilds the model list.
class _PromptEditor extends StatefulWidget {
  const _PromptEditor({super.key, required this.ai, required this.filename});
  final AiServices ai;
  final String filename;
  @override
  State<_PromptEditor> createState() => _PromptEditorState();
}

class _PromptEditorState extends State<_PromptEditor> {
  final _ctl = TextEditingController();
  PromptSource? _source;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final eff = await widget.ai.models.effectivePrompt(widget.filename);
    if (!mounted) return;
    setState(() {
      _ctl.text = eff.prompt;
      _source = eff.source;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ChatStyle.of(context);
    final label = switch (_source) {
      PromptSource.override => 'Custom (saved)',
      PromptSource.file => "Using the model's default prompt file",
      PromptSource.builtIn => 'Using built-in default',
      null => 'Loading…',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _small(s)),
          const SizedBox(height: 6),
          TextField(
            controller: _ctl,
            minLines: 4,
            maxLines: 8,
            style: TextStyle(
              color: s.inputText,
              fontSize: s.fontSize - 1,
              fontFamily: s.fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton(
                onPressed: () {
                  widget.ai.setPrompt(widget.filename, _ctl.text);
                  setState(() => _source = PromptSource.override);
                },
                child: const Text('Save'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: _source == PromptSource.override
                    ? () async {
                        await widget.ai.resetPrompt(widget.filename);
                        await _load();
                      }
                    : null,
                child: const Text('Reset to file/default'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── GPU editor ───────────────────────────────────────────────────────────
class _GpuEditor extends StatefulWidget {
  const _GpuEditor({super.key, required this.ai, required this.model});
  final AiServices ai;
  final LocalModel model;
  @override
  State<_GpuEditor> createState() => _GpuEditorState();
}

class _GpuEditorState extends State<_GpuEditor> {
  int? _layers; // total layers in the model
  int? _vramMib;
  late int _gpuLayers = widget.ai.models.gpuLayers(widget.model.filename) ?? 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = widget.ai.models.fileOf(widget.model.filename).path;
    final results = await Future.wait([
      readGgufLayerCountAsync(path),
      widget.ai.engine.queryVramMib(),
    ]);
    if (!mounted) return;
    setState(() {
      _layers = results[0];
      _vramMib = results[1];
      _loading = false;
    });
  }

  int? _estimateMib() {
    final cal = widget.ai.engine.calibration[widget.model.filename];
    if (cal != null && cal.layers > 0) {
      return (cal.mib / cal.layers * _gpuLayers)
          .round(); // scaled from a real measurement
    }
    final total = _layers;
    if (total == null) return null;
    return (widget.model.sizeBytes / 1e6 * (_gpuLayers / (total + 1))).round();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      widget.ai.models.setGpuLayers(widget.model.filename, _gpuLayers);
      await widget.ai.useModel(
        widget.model.filename,
      ); // takes effect on next load, so reload now
    } catch (e) {
      _error = errorMessage(e, "Couldn't save GPU layers.");
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ChatStyle.of(context);
    final small = _small(s);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      );
    }
    final total = _layers;
    final est = _estimateMib();
    final cal = widget.ai.engine.calibration[widget.model.filename];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${total ?? '?'} layers total${_vramMib != null ? ' · ~${(_vramMib! / 1024).toStringAsFixed(1)} GB VRAM detected' : ''}',
            style: small,
          ),
          if (total == null || total == 0)
            Text("Couldn't read the layer count from this file.", style: small)
          else ...[
            Slider(
              value: _gpuLayers.clamp(0, total).toDouble(),
              min: 0,
              max: total.toDouble(),
              divisions: total,
              label: '$_gpuLayers',
              onChanged: (v) => setState(() => _gpuLayers = v.round()),
            ),
            Text(
              '$_gpuLayers / $total layers on GPU${_gpuLayers == 0 ? ' (CPU only)' : ''}'
              '${est != null ? ' · ~${(est / 1024).toStringAsFixed(1)} GB estimated${cal != null ? ' (calibrated)' : ' (rough)'}' : ''}',
              style: small,
            ),
            for (final e in widget.ai.engine.bufferMib.entries)
              Text(
                '${e.key.toUpperCase().startsWith('CPU') ? 'CPU' : 'GPU Actual'}: ${(e.value / 1024).toStringAsFixed(2)} GB',
                style: small,
              ),
          ],
          if (_error != null)
            Text(
              _error!,
              style: small.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 6),
          OutlinedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Reloading…' : 'Save & reload'),
          ),
        ],
      ),
    );
  }
}
