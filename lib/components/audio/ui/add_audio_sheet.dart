import 'package:dba2/ui/helpers/word_color.dart';
import 'package:dba2/ui/widgets/draggable_snap_sheet.dart';
import 'package:flutter/material.dart';

import '../controllers/audio_controller.dart';
import '../services/audio_catalog.dart';
import '../services/audio_library.dart';

import 'package:dba2/themes/app_theme.dart'; // for context.colorScheme

const _green = Color(0xFF4CAF50);

Future<void> showAddAudio(
  BuildContext context,
  AudioController c, {
  required VoidCallback onUpload,
}) {
  return showModalSnapSheet(
    context: context,
    positions: const SnapPositions.sized(
      min: SheetSize.px(170),
      max: SheetSize.px(480),
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AddAudioSheet(c: c, onUpload: onUpload),
  );
}

class _AddAudioSheet extends StatefulWidget {
  const _AddAudioSheet({required this.c, required this.onUpload});
  final AudioController c;
  final VoidCallback onUpload;

  @override
  State<_AddAudioSheet> createState() => _AddAudioSheetState();
}

class _AddAudioSheetState extends State<_AddAudioSheet> {
  late final Future<List<AudioPack>> _catalog = loadCatalog();
  String? _busyName;
  String _phase = '';
  String? _note;
  double _pct = 0;
  CancelFlag? _cancel;

  Future<void> _save(AudioPack pack, String author) async {
    setState(() {
      _busyName = pack.name;
      _phase = 'zip';
      _pct = 0;
      _note = null;
    });
    String? msg;
    try {
      final ok = await widget.c.exportAuthor(
        author,
        onPhase: (phase, pct) {
          if (!mounted) return;
          setState(() {
            _phase = phase;
            _pct = pct;
          });
        },
      );
      msg = ok ? 'Saved "$author" zip' : null; // null = cancelled
    } catch (e, st) {
      debugPrint('Save failed: $e\n$st');
      msg = 'Save failed: $e';
    }
    if (mounted) {
      setState(() {
        _busyName = null;
        _note = msg;
      });
    }
  }

  Future<void> _download(AudioPack pack) async {
    final cancel = _cancel = CancelFlag();
    setState(() {
      _busyName = pack.name;
      _phase = 'download';
      _pct = 0;
      _note = null;
    });
    String msg;
    try {
      await widget.c.downloadPack(pack, (phase, pct) {
        if (!mounted) return;
        setState(() {
          _phase = phase;
          _pct = pct;
        });
      }, cancel);
      msg = '${pack.name} installed!';
    } catch (e, st) {
      debugPrint('Download failed: $e\n$st');
      msg = cancel.cancelled ? 'Download cancelled' : 'Download failed: $e';
    }
    if (mounted) {
      setState(() {
        _busyName = null;
        _note = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busyName != null;
    return PopScope(
      canPop: !busy, // can't dismiss mid-download (use the cancel button)
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: ListenableBuilder(
          listenable: widget.c,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                'Add Audio',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 15),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  tileColor: Theme.of(context).colorScheme.tertiary,
                  leading: const Icon(Icons.folder_zip_outlined),
                  title: const Text('Local Audio Upload'),
                  subtitle: const Text(
                    'Have an AudioBible Backup? Import it',
                  ),
                  enabled: !busy,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onUpload();
                  },
                  trailing: const Icon(Icons.upload_rounded),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Text.rich(
                  highlightMap(
                    text: 'Warning, AudioBibles are 800MB each, Please use Wifi,\nUnless you have an unlimited mobile internet package!',
                    keywordColors: {
                      'Warning': Colors.orangeAccent,
                      '800MB': Colors.orangeAccent,
                      'Wifi': Colors.green,
                      'unlimited mobile internet': Colors.green,
                    },
                    baseStyle: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Flexible(
                child: FutureBuilder<List<AudioPack>>(
                  future: _catalog,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      );
                    }
                    final packs = snap.data!;
                    return ListView.builder(
                      // top defaults 0 if not declared.
                      padding: EdgeInsets.only(left: 15),
                      itemCount: packs.length,
                      itemBuilder: (_, i) => _row(packs[i], busy),
                    );
                  },
                ),
              ),
              if (_note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    _note!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _note!.contains('failed')
                          ? context.colorScheme.error
                          : _green,
                    ),
                  ),
                ),
              const SizedBox(height: 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(AudioPack pack, bool busy) {
    final installedAs = pack.installedAs(widget.c.authors);
    final thisBusy = _busyName == pack.name;
    final size = pack.sizeMb != null ? ' • ${pack.sizeMb} MB' : '';

    Widget trailing;
    if (thisBusy) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _green,
              value:
                  (_phase == 'download' ||
                          _phase == 'extract' ||
                          _phase == 'write') &&
                      _pct > 0
                  ? _pct / 100
                  : null,
            ),
          ),
          IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: _phase == 'download'
                ? () => _cancel?.cancelled = true
                : null,
          ),
        ],
      );
    } else if (installedAs != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Save a copy (.zip)',
            icon: const Icon(Icons.save_alt_rounded),
            onPressed: busy ? null : () => _save(pack, installedAs),
          ),
          const Icon(Icons.check_circle, color: _green),
          const SizedBox(width: 8),
        ],
      );
    } else {
      trailing = IconButton(
        tooltip: 'Download',
        icon: const Icon(Icons.download_rounded),
        onPressed: busy ? null : () => _download(pack),
      );
    }

    final subtitle = thisBusy
        ? switch (_phase) {
            'download' => 'Downloading… ${_pct.round()}%',
            'extract' => 'Extracting… ${_pct.round()}%',
            'save' => 'Choose where to save…',
            'write' => 'Writing to disk… ${_pct.round()}%',
            _ => 'Preparing zip…',
          }
        : installedAs != null
        ? 'Installed'
        : '${pack.description}$size'.trim();

    return ListTile(
      title: Text(
        pack.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
  }
}
