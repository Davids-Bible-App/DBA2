import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'addon_store.dart';

class AddonController extends ChangeNotifier {
  AddonController(this.store);
  final AddonStore store;

  final Set<String> _installed = {};
  final Map<String, double?> downloading = {};

  String? message;
  bool messageIsError = false;

  // The global switches. Watch these to show/hide UI.
  bool get hasStrongs => _installed.contains(kStrongsDb.id);
  bool get hasCrossRefs => _installed.contains(kCrossRefsDb.id);

  bool isInstalled(AddonDb a) => _installed.contains(a.id);
  bool isDownloading(AddonDb a) => downloading.containsKey(a.id);

  void _say(String? text, {bool error = false}) {
    message = text;
    messageIsError = error;
  }

  Future<void> refresh() async {
    for (final a in kAddons) {
      if (await store.isInstalled(a)) {
        _installed.add(a.id);
      } else {
        _installed.remove(a.id);
      }
    }
    notifyListeners();
  }

  Future<void> download(AddonDb a) async {
    if (isDownloading(a)) return;
    _say(null);
    downloading[a.id] = 0;
    notifyListeners();
    try {
      await store.download(a, (p) {
        downloading[a.id] = p;
        notifyListeners();
      });
      _installed.add(a.id);
    } catch (e) {
      _say('Could not download ${a.name}: $e', error: true);
    } finally {
      downloading.remove(a.id);
      notifyListeners(); // UI shows the buttons immediately
    }
  }

  Future<void> importFile(AddonDb a) async {
    _say(null);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (result.isEmpty) return;
      final path = result.first.path;
      if (path == null) return;

      if (await store.importFrom(a, path)) {
        _installed.add(a.id);
        _say('${a.name} imported.');
      } else {
        _say('That file is not a valid ${a.name} database.', error: true);
      }
    } catch (e) {
      _say('Import failed: $e', error: true);
    }
    notifyListeners();
  }

  Future<void> remove(AddonDb a) async {
    await store.delete(a);
    _installed.remove(a.id);
    notifyListeners();
  }
}
