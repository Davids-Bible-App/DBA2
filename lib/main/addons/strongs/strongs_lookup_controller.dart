import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strongs_models.dart';
import 'strongs_repository.dart';

/// All the signals from StrongsLookup.jsx, as one ChangeNotifier.
/// Lives for the whole app run (see strongs_lookup_sheet.dart), so closing the
/// sheet doesn't throw the results away, same as your search sheet.
class StrongsLookupController extends ChangeNotifier {
  StrongsLookupController(this._repo);
  final StrongsRepository _repo;

  static const _kHistory = 'strongsLookupHistory';
  static const _maxHistory = 20;

  /// The text box (was `searchInput`).
  final TextEditingController input = TextEditingController();

  String? activeQuery; // was activeSearch().query
  String? origin; // was activeSearch().origin
  LookupResponse? data;
  bool loading = false;
  String? error;
  List<String> history = [];

  /// Bumped for every new result set, so the sheet can scroll back to top.
  int resultsEpoch = 0;

  int _seq = 0; // ignore answers from superseded searches

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    history = prefs.getStringList(_kHistory) ?? [];
    notifyListeners();
  }

  Future<void> search(String raw, {String? origin}) async {
    final q = raw.trim();
    if (q.isEmpty) return;

    input.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    activeQuery = q;
    this.origin = origin;
    loading = true;
    error = null;
    notifyListeners();

    final id = ++_seq;
    try {
      final r = await _repo.lookup(q);
      if (id != _seq) return;
      data = r;
      resultsEpoch++;
      if (r.hasResults) await _saveToHistory(q);
    } catch (e) {
      if (id != _seq) return;
      data = null;
      error = 'Lookup failed: $e';
    }
    loading = false;
    notifyListeners();
  }

  /// Tapping a code badge inside the results.
  Future<void> jumpToStrongs(String code) =>
      search(code, origin: '"$activeQuery" search results');

  void clear() {
    _seq++; // cancel anything in flight
    input.clear();
    activeQuery = null;
    origin = null;
    data = null;
    error = null;
    loading = false;
    notifyListeners();
  }

  Future<void> _saveToHistory(String q) async {
    history = [q, ...history.where((h) => h != q)].take(_maxHistory).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kHistory, history);
  }

  Future<void> removeFromHistory(String q) async {
    history = history.where((h) => h != q).toList();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kHistory, history);
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }
}
