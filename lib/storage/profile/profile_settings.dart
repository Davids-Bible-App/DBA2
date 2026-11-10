import 'package:flutter/foundation.dart';

import 'profile.dart';

/// Key/value settings stored in profile.db's `settings` table.
/// Reads are instant (from memory); writes go to the DB in the background.
class ProfileSettings {
  ProfileSettings._(this._repo, this._cache);

  final ProfileRepository _repo;
  final Map<String, String> _cache;

  static Future<ProfileSettings> open(ProfileRepository repo) async {
    final rows = await repo.getSettings();
    return ProfileSettings._(repo, {
      for (final r in rows) r['key'] as String: (r['value'] as String?) ?? '',
    });
  }

  /// Re-reads everything from the DB (used after an import).
  Future<void> reload() async {
    final rows = await _repo.getSettings();
    _cache
      ..clear()
      ..addAll({
        for (final r in rows) r['key'] as String: (r['value'] as String?) ?? '',
      });
  }

  String? getString(String key) => _cache[key];

  bool? getBool(String key) {
    final v = _cache[key];
    if (v == null) return null;
    return v == 'true' || v == '1';
  }

  int? getInt(String key) => int.tryParse(_cache[key] ?? '');
  double? getDouble(String key) => double.tryParse(_cache[key] ?? '');

  Future<void> setString(String key, String value) async {
    _cache[key] = value;
    try {
      await _repo.setConfig(key, value);
    } catch (e) {
      debugPrint('ProfileSettings: could not save $key: $e');
    }
  }

  Future<void> setBool(String key, bool value) => setString(key, '$value');
  Future<void> setInt(String key, int value) => setString(key, '$value');
  Future<void> setDouble(String key, double value) => setString(key, '$value');

  Future<void> remove(String key) async {
    _cache.remove(key);
    try {
      await _repo.deleteConfig(key);
    } catch (e) {
      debugPrint('ProfileSettings: could not remove $key: $e');
    }
  }

  /// Wipes all settings (DB first, then the in-memory cache).
  /// Throws if the DB write fails, so the UI can report it.
  Future<void> clear() async {
    await _repo.clearSettings();
    _cache.clear();
  }
}
