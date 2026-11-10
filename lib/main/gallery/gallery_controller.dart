import 'package:dba2/main/gallery/sqlite_gallery_repository.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'verse_grouping.dart';

/// Replaces: selectedTopic / topicVerses / topicMetadata / notes resources,
/// the handle* functions in GalleryManager, and triggerRefetch(...).
/// Call [refreshAll] from anywhere (e.g. after TopicModal saves verses).
class GalleryController extends ChangeNotifier {
  GalleryController(this._repo) {
    refreshAll();
  }

  final GalleryRepository _repo;

  List<TopicMeta> topics = const [];
  List<GalleryEntry> topicVerses = const [];
  List<GalleryEntry> notes = const [];
  String? selectedTopic;
  String topicDescription = '';

  List<List<GalleryEntry>> get groups => groupConsecutive(topicVerses);

  // ── loading ────────────────────────────────────────────────────────────
  Future<void> refreshAll() =>
      Future.wait([loadTopics(), loadNotes(), _loadDetail()]);

  Future<void> loadTopics() async {
    topics = await _repo.getTopicsMetadata();
    notifyListeners();
  }

  Future<void> loadNotes() async {
    final all = await _repo.getGallery(type: 'note');
    notes = all.where((e) => (e.note ?? '').trim().isNotEmpty).toList();
    _noteIndex
      ..clear()
      ..addAll({
        for (final e in notes)
          _noteKey(e.translationId, e.bookId, e.chapter, e.verseId): e.note!,
      });
    notifyListeners();
  }

  Future<void> _loadDetail() async {
    final name = selectedTopic;
    if (name == null) {
      topicVerses = const [];
      topicDescription = '';
    } else {
      final verses = await _repo.getGallery(type: 'topic', topic: name);
      final desc = await _repo.getTopicDescription(name);
      if (selectedTopic != name) return; // user navigated away meanwhile
      topicVerses = verses;
      topicDescription = desc;
    }
    notifyListeners();
  }

  Future<void> selectTopic(String? name) async {
    selectedTopic = name;
    topicVerses = const [];
    topicDescription = '';
    notifyListeners();
    await _loadDetail();
  }

  // ── mutations ──────────────────────────────────────────────────────────
  /// Returns the topic name actually used (matches existing names ignoring case).
  Future<String> addToTopic(String topic, List<GalleryEntry> verses) async {
    final wanted = topic.trim();
    final name = topics
        .map((t) => t.topic)
        .firstWhere(
          (t) => t.toLowerCase() == wanted.toLowerCase(),
          orElse: () => wanted,
        );
    await _repo.addToTopic(name, verses);
    await refreshAll();
    return name;
  }

  final _noteIndex = <String, String>{};

  static String _noteKey(String tr, String bk, int ch, int vs) =>
      '${normalizeTranslationId(tr)}|$bk|$ch|$vs';

  /// The note on this verse, or null. Used by the reader.
  String? noteFor(String tr, String bk, int ch, int vs) =>
      _noteIndex[_noteKey(tr, bk, ch, vs)];

  Future<void> addNote(GalleryEntry verse, String note) async {
    await _repo.addNote(verse, note.trim());
    await refreshAll();
  }

  Future<void> deleteEntries(String type, List<int> ids) async {
    await _repo.deleteEntries(type, ids);
    await refreshAll();
  }

  Future<void> saveNote(int id, String note) async {
    await _repo.saveNoteById(id, note);
    await refreshAll();
  }

  Future<void> renameTopic(String oldName, String newName) async {
    await _repo.renameTopic(oldName, newName);
    if (selectedTopic == oldName) selectedTopic = newName;
    await refreshAll();
  }

  Future<void> deleteTopic(String topic) async {
    await _repo.deleteTopic(topic);
    if (selectedTopic == topic) selectedTopic = null;
    await refreshAll();
  }

  Future<void> resetTopicOrder(String topic) async {
    final ordered = await _repo.getGallery(
      type: 'topic',
      topic: topic,
      resetSort: true,
    );
    await _repo.updateVersesOrder(ordered.map((v) => v.id).toList());
    await refreshAll();
  }

  Future<void> saveDescription(String text) async {
    final t = selectedTopic;
    if (t == null) return;
    await _repo.saveTopicDescription(t, text);
    topicDescription = text;
    notifyListeners();
  }

  // Optimistic reorders (update UI first, persist in background).
  void reorderTopics(int oldIndex, int newIndex) {
    final l = [...topics];
    l.insert(newIndex, l.removeAt(oldIndex));
    topics = l;
    notifyListeners();
    _repo.updateTopicsOrder(l.map((t) => t.topic).toList());
  }

  void reorderGroups(int oldIndex, int newIndex) {
    final g = [...groups];
    g.insert(newIndex, g.removeAt(oldIndex));
    topicVerses = g.expand((x) => x).toList();
    notifyListeners();
    _repo.updateVersesOrder(topicVerses.map((v) => v.id).toList());
  }

  /// "Ungroup": push selected verses to the end so they stop being consecutive.
  Future<void> ungroup(List<int> ids) async {
    final remaining = topicVerses.where((v) => !ids.contains(v.id));
    final moved = topicVerses.where((v) => ids.contains(v.id));
    await _repo.updateVersesOrder(
      [...remaining, ...moved].map((v) => v.id).toList(),
    );
    await _loadDetail();
  }

  // ── export ─────────────────────────────────────────────────────────────
  String get exportText {
    final desc = (topicDescription.isEmpty ? 'Not Available' : topicDescription)
        .replaceAll(RegExp(r'[ \t]+$', multiLine: true), '')
        .trim();
    return 'Topic: ${selectedTopic ?? ''}\n'
        'Description: $desc\n'
        '----------------------------\n\n'
        '${formatGroups(topicVerses, wrap: true)}';
  }
}
