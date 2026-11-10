import 'package:shared_preferences/shared_preferences.dart';

import 'package:dba2/storage/profile/profile.dart';

import 'md_controller.dart';

/// Stores the editor's data in profile.db (md_store table).
class ProfileMdStorage extends MdStorage {
  ProfileMdStorage(this._repo);
  final ProfileRepository _repo;

  @override
  Future<String?> read(String key) => _repo.mdRead(key);

  @override
  Future<void> write(String key, String value) =>
      _repo.mdWriteAll({key: value});

  @override
  Future<void> writeAll(Map<String, String> entries) =>
      _repo.mdWriteAll(entries);

  @override
  Future<void> remove(String key) => _repo.mdRemove(key);
}

/// One-time move of the old SharedPreferences data into the database.
/// Safe to call on every launch: it does nothing once the old keys are gone.
Future<void> migrateMdFromPrefs(
  SharedPreferences prefs,
  MdStorage to, {
  String key = 'md_editor',
}) async {
  const keep = ['text', 'theme', 'stacked', 'auto'];
  const drop = ['history', 'index'];
  final data = <String, String>{};
  for (final s in keep) {
    final v = prefs.getString('$key.$s');
    if (v != null) data['$key.$s'] = v;
  }
  if (data.isEmpty) return;
  if (await to.read('$key.text') == null) await to.writeAll(data);
  for (final s in [...keep, ...drop]) {
    await prefs.remove('$key.$s');
  }
}
