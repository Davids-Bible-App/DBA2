import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dba2/storage/profile/profile.dart';

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.verseId,
    required this.updatedAt,
  });

  final int id;
  final String translationId;
  final String bookId;
  final int chapter;
  final int verseId;
  final DateTime updatedAt;

  factory HistoryEntry.fromMap(Map<String, Object?> m) => HistoryEntry(
    id: m['id'] as int,
    translationId: m['translation_id'] as String,
    bookId: m['book_id'] as String,
    chapter: m['chapter'] as int,
    verseId: m['verse_id'] as int,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (m['updated_at'] as int) * 1000,
    ),
  );
}

class HistoryController extends ChangeNotifier {
  HistoryController(this._profile);
  final ProfileRepository _profile;

  static const _limit = 50;
  static const _debounce = Duration(seconds: 1);

  List<HistoryEntry> entries = const [];
  bool loading = false;
  Timer? _timer;

  /// Debounced, like logHistoryEntry in historyStore.js.
  void log(String tr, String bk, int ch, int vs) {
    _timer?.cancel();
    _timer = Timer(_debounce, () async {
      try {
        await _profile.logHistoryEntry(
          verse: VerseReference(
            translationId: tr,
            bookId: bk,
            chapter: ch,
            verseId: vs,
          ),
          limit: _limit,
        );
      } catch (e) {
        debugPrint('Failed to log history: $e');
      }
    });
  }

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final rows = await _profile.getReadHistory();
      entries = rows.map(HistoryEntry.fromMap).toList();
    } catch (e) {
      debugPrint('Failed to load history: $e');
    }
    loading = false;
    notifyListeners();
  }

  Future<void> delete(HistoryEntry e) async {
    entries = entries.where((x) => x.id != e.id).toList();
    notifyListeners();
    try {
      await _profile.deleteHistoryEntry(e.id);
    } catch (err) {
      debugPrint('Failed to delete history entry: $err');
      await load();
    }
  }

  Future<void> clearAll() async {
    entries = const [];
    notifyListeners();
    try {
      await _profile.clearReadHistory();
    } catch (e) {
      debugPrint('Failed to clear history: $e');
      await load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
