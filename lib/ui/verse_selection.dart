// lib/ui/verse_selection.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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

/// Highlight colours per verse. In memory for now; when profile.db is ready,
/// load into this store and write through in setColor().
class HighlightStore extends ChangeNotifier {
  final Map<VerseRef, Color> _colors = {};

  Color? colorFor(VerseRef r) => _colors[r];

  /// color == null clears the highlight (the red "none" swatch).
  void setColor(Iterable<VerseRef> refs, Color? color) {
    for (final r in refs) {
      if (color == null) {
        _colors.remove(r);
      } else {
        _colors[r] = color;
      }
    }
    notifyListeners();
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
