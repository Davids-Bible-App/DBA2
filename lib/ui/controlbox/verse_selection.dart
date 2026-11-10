import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:dba2/storage/profile/profile.dart';

/// The Flutter replacement for your data-ed / data-tr / data-bk / data-ch /
/// data-vs attributes. Records compare by value, so two VerseRefs with the
/// same fields are equal and can be used in Sets and as Map keys.
typedef VerseRef = ({String ed, String tr, String bk, int ch, int vs});

/// Which verses are selected. "Popup open" == isActive (your expandedCtl > 0).
class VerseSelection extends ChangeNotifier {
  final Set<VerseRef> _items = {};

  bool get isActive => _items.isNotEmpty;
  int get count => _items.length;
  bool contains(VerseRef r) => _items.contains(r);

  /// Selected verses in reading order (selection never spans chapters,
  /// it is cleared whenever a chapter loads).
  List<VerseRef> get sorted =>
      (_items.toList()..sort((a, b) => a.vs.compareTo(b.vs)));

  void toggle(VerseRef r) {
    if (!_items.remove(r)) _items.add(r);
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}

// Highlights are matched on translation/book/chapter/verse only (not `ed`),
// so rows loaded from the DB match the verses the reader asks about.
typedef _Key = ({String tr, String bk, int ch, int vs});

/// Highlight colours per verse, saved to profile.db.
class HighlightStore extends ChangeNotifier {
  HighlightStore({required this.repo, required this.palette});

  final ProfileRepository repo;

  /// Index 0 = Tauri's var(--hlClr1), index 1 = var(--hlClr2), ...
  final List<Color> palette;

  final Map<_Key, Color> _colors = {};

  static final _dba = RegExp(r'\.dba$', caseSensitive: false);
  static String _appTr(String id) => id.replaceFirst(_dba, '');
  static String _dbTr(String id) => _dba.hasMatch(id) ? id : '$id.dba';

  _Key _keyOf(VerseRef r) => (tr: _appTr(r.tr), bk: r.bk, ch: r.ch, vs: r.vs);

  Color? colorFor(VerseRef r) => _colors[_keyOf(r)];

  /// Reads every saved highlight from profile.db.
  Future<void> load() async {
    try {
      final rows = await repo.getHighlights();
      _colors.clear();
      for (final row in rows) {
        final color = _decode(row['color'] as String?);
        if (color == null) continue;
        _colors[(
              tr: _appTr((row['translation_id'] as String?) ?? ''),
              bk: (row['book_id'] as String?) ?? '',
              ch: (row['chapter'] as int?) ?? 0,
              vs: (row['verse_id'] as int?) ?? 0,
            )] =
            color;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('HighlightStore.load failed: $e');
    }
  }

  /// color == null clears the highlight (the red "none" swatch).
  void setColor(Iterable<VerseRef> refs, Color? color) {
    final list = refs.toList();
    for (final r in list) {
      final k = _keyOf(r);
      if (color == null) {
        _colors.remove(k);
      } else {
        _colors[k] = color;
      }
    }
    notifyListeners(); // the screen updates instantly...
    _save(list, color); // ...and the DB catches up in the background
  }

  Future<void> _save(List<VerseRef> refs, Color? color) async {
    final groups = <(String, String, int), List<int>>{};
    for (final r in refs) {
      groups.putIfAbsent((_dbTr(r.tr), r.bk, r.ch), () => []).add(r.vs);
    }
    final code = color == null ? 'transparent' : _encode(color);
    try {
      for (final g in groups.entries) {
        await repo.toggleHighlights(
          translationId: g.key.$1,
          bookId: g.key.$2,
          chapter: g.key.$3,
          verses: g.value,
          color: code,
        );
      }
    } catch (e) {
      debugPrint('HighlightStore save failed: $e');
    }
  }

  // App colour -> text stored in the DB. Palette colours are written the way
  // your Tauri app wrote them, so v1 can still read them after an export.
  String _encode(Color c) {
    final i = palette.indexOf(c);
    if (i >= 0) return 'var(--hlClr${i + 1})';
    final rgb = c.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  // Text from the DB -> app colour. Returns null if it can't be understood.
  Color? _decode(String? s) {
    if (s == null) return null;
    final m = RegExp(r'hlClr(\d+)').firstMatch(s);
    if (m != null) {
      final i = int.parse(m.group(1)!) - 1;
      return (i >= 0 && i < palette.length) ? palette[i] : null;
    }
    final hex = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(s.trim());
    if (hex != null) {
      return (Color(
        0xFF000000 |
            int.parse(
              hex.group(1)!,
              radix: 16,
            ),
      ));
    }
    return null;
  }
}

/// Splits a sorted list into runs of consecutive verses: 1,2,3,5 -> [1-3],[5]
List<List<VerseRef>> groupVerses(List<VerseRef> sorted) {
  final groups = <List<VerseRef>>[];
  for (final r in sorted) {
    final prev = groups.isEmpty ? null : groups.last.last;
    final sameRef =
        prev != null && prev.tr == r.tr && prev.bk == r.bk && prev.ch == r.ch;
    if (sameRef && prev.vs + 1 == r.vs) {
      groups.last.add(r);
    } else {
      groups.add([r]);
    }
  }
  return groups;
}
