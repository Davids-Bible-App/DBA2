import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Tiny persistent key/value store. Replaces the Rust `settings` SQLite table.
/// Reads are served from memory; writes are debounced and atomic (tmp + rename).
class SettingsStore {
  SettingsStore._(this._file, this._data);
  final File _file;
  final Map<String, String> _data;
  Timer? _flushTimer;

  static Future<SettingsStore> open(Directory dir) async {
    final file = File(p.join(dir.path, 'ai_settings.json'));
    var data = <String, String>{};
    if (await file.exists()) {
      try {
        data = (jsonDecode(await file.readAsString()) as Map).cast<String, String>();
      } catch (_) {/* corrupt file: start fresh */}
    }
    return SettingsStore._(file, data);
  }

  String? get(String key) => _data[key];

  Iterable<MapEntry<String, String>> withPrefix(String prefix) =>
      _data.entries.where((e) => e.key.startsWith(prefix));

  void set(String key, String value) {
    _data[key] = value;
    _scheduleFlush();
  }

  void remove(String key) {
    if (_data.remove(key) != null) _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 300), flush);
  }

  Future<void> flush() async {
    _flushTimer?.cancel();
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_data), flush: true);
    await tmp.rename(_file.path);
  }
}
