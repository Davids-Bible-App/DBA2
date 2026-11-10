import 'dart:async';

import 'package:dba2/storage/profile/profile.dart';
import 'package:dba2/storage/profile/profile_settings.dart';
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/ui/translations/services/translation_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_logic.dart';

/// All the createSignal(...) state of SearchRef.jsx lives here.
/// (Named Bible* because Flutter already has a SearchController.)
class BibleSearchController extends ChangeNotifier {
  BibleSearchController({
    required this.bible,
    required this.store,
    required this.profile,
    required this.settings,
  }) {
    unawaited(_load());
  }

  final BibleController bible;
  final TranslationStore store;
  final ProfileRepository profile;
  final ProfileSettings settings;

  /// Owns the text box contents.
  final TextEditingController input = TextEditingController();

  static const _kHistory = 'bibleSearchHistory';
  static const _kHighlight = 'bibleSearchHighlight';
  static const _kHistoryMax = 20;

  // ---- state --------------------------------------------------------------
  List<SearchHit> hits = const [];
  int total = 0;
  bool isReference = false;
  int page = 0;
  int perPage = 50;
  String? scope; // null | 'OT' | 'NT'
  bool highlightOn = true;
  bool loading = false;
  String? error;
  bool noResults = false; // flashes for 2s
  String? flashMessage; // "Verses copied…" flashes for 3s
  List<String> history = [];

  // Remembered between sheet openings.
  double scrollOffset = 0;
  int resultsEpoch = 0; // bumps whenever a NEW result set arrives
  String? _resultTranslation; // translation the current hits belong to
  String? _countKey; // identifies which search the current `total` belongs to

  final Map<String, SearchHit> _selected = {};
  int _token = 0; // ignore stale responses
  Timer? _noResultsTimer;
  Timer? _flashTimer;
  bool _disposed = false;

  int get totalPages => total == 0 ? 0 : (total + perPage - 1) ~/ perPage;
  int get selectedCount => _selected.length;
  bool isSelected(SearchHit h) => _selected.containsKey(h.key);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- storage (profile.db) -----------------------------------------------
  Future<void> _load() async {
    await _migrateOldPrefs();
    await reloadFromProfile();
  }

  /// Also call this after a profile import.
  Future<void> reloadFromProfile() async {
    history = await profile.recentQueries('search', limit: _kHistoryMax);
    highlightOn = settings.getBool(_kHighlight) ?? true;
    _notify();
  }

  /// One-time move from SharedPreferences. Safe to run every launch.
  Future<void> _migrateOldPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final old = prefs.getStringList(_kHistory);
    if (old != null) {
      // Oldest first, so the newest ends up at the top.
      for (final q in old.reversed) {
        await profile.logQuery('search', q);
      }
      await profile.trimQueries('search', keep: _kHistoryMax);
      await prefs.remove(_kHistory);
    }

    final hl = prefs.getBool(_kHighlight);
    if (hl != null) {
      await settings.setBool(_kHighlight, hl);
      await prefs.remove(_kHighlight);
    }
  }

  Future<void> _saveHistory(String q) async {
    history = [q, ...history.where((h) => h != q)].take(_kHistoryMax).toList();
    _notify();
    await profile.logQuery(
      'search',
      q,
    ); // replaces the row, so it becomes newest
    await profile.trimQueries('search', keep: _kHistoryMax);
  }

  Future<void> removeFromHistory(String q) async {
    history = history.where((h) => h != q).toList();
    _notify();
    await profile.deleteQueryText('search', q);
  }

  // ---- options ------------------------------------------------------------
  void setScope(String? v) {
    scope = v;
    _notify();
    if (input.text.trim().isNotEmpty && hits.isNotEmpty) search();
  }

  void setPerPage(int n) {
    perPage = n;
    _notify();
    if (input.text.trim().isNotEmpty) search();
  }

  Future<void> setHighlight(bool v) async {
    highlightOn = v;
    _notify();
    await settings.setBool(_kHighlight, v);
  }

  // ---- searching ----------------------------------------------------------
  Future<void> search({int page = 0}) async {
    final q = input.text.trim();
    if (q.isEmpty || !bible.hasTranslation) return;

    final token = ++_token;
    loading = true;
    error = null;
    _notify();

    try {
      final path = (await store.fileFor(bible.translationId)).path;

      SearchPage? result;
      if (looksLikeReference(q)) {
        final ranges = parseReference(q, bible.books);
        if (ranges.isNotEmpty) {
          final r = await runReferenceSearch(path, ranges);
          if (r.hits.isNotEmpty) result = r;
        }
      }
      String? countKey;
      if (result == null) {
        final fts = prepareFtsQuery(q);
        if (fts.isEmpty) {
          result = const SearchPage([], 0);
        } else {
          countKey = '${bible.translationId}|$fts|$scope';
          result = await runKeywordSearch(
            dbPath: path,
            ftsQuery: fts,
            scope: scope,
            page: page,
            perPage: perPage,
            // Reuse the total only when paging through the SAME search.
            knownTotal: (page > 0 && countKey == _countKey) ? total : null,
          );
        }
      }
      if (token != _token) return;
      _countKey = result.isReference ? null : countKey;

      hits = result.hits;
      total = result.total;
      isReference = result.isReference;
      this.page = result.isReference ? 0 : page;
      _resultTranslation = bible.translationId;
      scrollOffset = 0;
      resultsEpoch++;

      _noResultsTimer?.cancel();
      if (total == 0) {
        noResults = true;
        _noResultsTimer = Timer(const Duration(seconds: 2), () {
          noResults = false;
          _notify();
        });
      } else {
        noResults = false;
        unawaited(_saveHistory(q));
      }
    } catch (e) {
      if (token != _token) return;
      _countKey = null;
      error = 'Search failed: $e';
      hits = const [];
      total = 0;
    } finally {
      if (token == _token) {
        loading = false;
        _notify();
      }
    }
  }

  void gotoPage(int p) {
    if (p != page && p >= 0 && p < totalPages) search(page: p);
  }

  void prevPage() => gotoPage(page - 1);
  void nextPage() => gotoPage(page + 1);

  void clearSearch() {
    _token++;
    input.clear();
    hits = const [];
    total = 0;
    isReference = false;
    page = 0;
    loading = false;
    scrollOffset = 0;
    resultsEpoch++;
    _selected.clear();
    _notify();
  }

  /// Call when the sheet opens: results from another translation are stale.
  void dropStaleResults() {
    if (hits.isNotEmpty && _resultTranslation != bible.translationId) {
      hits = const [];
      total = 0;
      isReference = false;
      page = 0;
      scrollOffset = 0;
      resultsEpoch++;
      _selected.clear();
    }
  }

  // ---- selection ----------------------------------------------------------
  void toggle(SearchHit h) {
    if (_selected.remove(h.key) == null) _selected[h.key] = h;
    _notify();
  }

  void clearSelection() {
    _selected.clear();
    _notify();
  }

  /// Selected verses in Bible order.
  List<SearchHit> get selectedSorted {
    final order = {
      for (var i = 0; i < bible.books.length; i++) bible.books[i].id: i,
    };
    return _selected.values.toList()..sort((a, b) {
      var c = (order[a.bookId] ?? 0).compareTo(order[b.bookId] ?? 0);
      if (c != 0) return c;
      c = a.chapter.compareTo(b.chapter);
      return c != 0 ? c : a.verse.compareTo(b.verse);
    });
  }

  String bookName(String id) {
    for (final b in bible.books) {
      if (b.id == id) return b.englishName;
    }
    return id;
  }

  /// "John 3:16-17  (KJV)\n16. … 17. …"  (groupConsecutiveVerses + stripMarkTags)
  String selectionAsText() {
    final groups = <List<SearchHit>>[];
    for (final h in selectedSorted) {
      final g = groups.isEmpty ? null : groups.last;
      if (g != null &&
          g.last.bookId == h.bookId &&
          g.last.chapter == h.chapter &&
          h.verse == g.last.verse + 1) {
        g.add(h);
      } else {
        groups.add([h]);
      }
    }
    return groups
        .map((g) {
          final range = g.length == 1
              ? '${g.first.verse}'
              : '${g.first.verse}-${g.last.verse}';
          final body = g
              .map(
                (h) =>
                    g.length == 1 ? h.plainText : '${h.verse}. ${h.plainText}',
              )
              .join(' ');
          return '${bookName(g.first.bookId)} ${g.first.chapter}:$range  '
              '(${bible.edition})\n$body';
        })
        .join('\n\n');
  }

  Future<void> copySelection() async {
    if (_selected.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selectionAsText()));
    _selected.clear();
    flash('Verses copied to clipboard!');
  }

  void flash(String message) {
    flashMessage = message;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 3), () {
      flashMessage = null;
      _notify();
    });
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _noResultsTimer?.cancel();
    _flashTimer?.cancel();
    input.dispose();
    super.dispose();
  }
}
