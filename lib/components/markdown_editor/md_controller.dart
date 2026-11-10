import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dba2/components/markdown_editor/verse_markdown.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'md_theme.dart';

// ============================================================== storage ====
abstract class MdStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);

  /// Default: one by one. Database storage overrides this with a single write.
  Future<void> writeAll(Map<String, String> entries) async {
    for (final e in entries.entries) {
      await write(e.key, e.value);
    }
  }
}

class PrefsMdStorage extends MdStorage {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
  @override
  Future<void> remove(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}

enum MdSaveState { saved, saving, unsaved }

class _Snap {
  _Snap(this.text, this.start, this.end);
  final String text;
  final int start, end;
  Map<String, dynamic> toJson() => {'t': text, 's': start, 'e': end};
  factory _Snap.fromJson(Map<String, dynamic> j) =>
      _Snap(j['t'] as String, j['s'] as int, j['e'] as int);
}

// ======================================================= smart list input ==
/// Handles "Enter" inside lists and "Backspace" on an empty marker.
/// Works as a TextInputFormatter so it behaves the same with a hardware
/// keyboard (Windows) and the Android soft keyboard.
class MdSmartListFormatter extends TextInputFormatter {
  static final _marker = RegExp(r'^(\s*)([-*+] \[[ xX]\] |[-*+] |\d+\. |> )');

  static RegExpMatch? matchMarker(String line) => _marker.firstMatch(line);

  /// "1. " -> "2. ", "- [x] " -> "- [ ] ", anything else stays the same.
  static String nextMarker(String mk) {
    final num = RegExp(r'^(\d+)\. ').firstMatch(mk);
    if (num != null) return '${int.parse(num.group(1)!) + 1}. ';
    if (mk.contains('[')) return mk.replaceFirst(RegExp(r'\[[xX]\]'), '[ ]');
    return mk;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final os = oldValue.selection, ns = newValue.selection;
    if (!os.isValid || !os.isCollapsed || !ns.isValid || !ns.isCollapsed) {
      return newValue;
    }
    final o = oldValue.text, n = newValue.text;

    // ---- Enter pressed
    if (n.length == o.length + 1) {
      final pos = ns.baseOffset;
      final c = pos - 1; // cursor position in the old text
      if (c < 0 || n[c] != '\n' || os.baseOffset != c) return newValue;
      if (n.substring(0, c) + n.substring(pos) != o) return newValue;
      final ls = c == 0 ? 0 : o.lastIndexOf('\n', c - 1) + 1;
      final line = o.substring(ls, c);
      final m = _marker.firstMatch(line);
      if (m == null) return newValue;
      final indent = m.group(1)!;
      final mk = m.group(2)!;
      final rest = line.substring(m[0]!.length);
      if (rest.trim().isEmpty) {
        // Empty item + Enter = leave the list (marker removed).
        return TextEditingValue(
          text: o.substring(0, ls) + o.substring(c),
          selection: TextSelection.collapsed(offset: ls),
        );
      }
      final ins = '\n$indent${nextMarker(mk)}';
      return TextEditingValue(
        text: o.replaceRange(c, c, ins),
        selection: TextSelection.collapsed(offset: c + ins.length),
      );
    }

    // ---- Backspace pressed right after an auto-inserted marker
    if (n.length == o.length - 1) {
      final c = os.baseOffset;
      if (c < 1 || ns.baseOffset != c - 1) return newValue;
      if (o.substring(0, c - 1) + o.substring(c) != n) return newValue;
      final ls = o.lastIndexOf('\n', c - 1) + 1;
      final line = o.substring(ls, c);
      final m = _marker.firstMatch(line);
      if (m == null || m[0]!.length != line.length) return newValue;
      return TextEditingValue(
        text: o.substring(0, ls) + o.substring(c),
        selection: TextSelection.collapsed(offset: ls),
      );
    }
    return newValue;
  }
}

// ============================================================ controller ===
class MarkdownEditorController extends ChangeNotifier {
  MarkdownEditorController({
    MdStorage? storage,
    this.storageKey = 'md_editor',
    this.maxUndo = 20,
    this.initialText = '',
    MdTheme? initialTheme,
  }) : storage = storage ?? PrefsMdStorage(),
       theme = ValueNotifier(initialTheme ?? MdTheme.light()) {
    focus.addListener(() {
      if (focus.hasFocus) cursorPlaced = true;
    });
  }

  MdTheme? _lightTheme, _darkTheme;

  MdTheme? _decodeTheme(String? s) {
    if (s == null) return null;
    try {
      return MdTheme.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
    } catch (_) {
      return null;
    }
  }

  void _remember(MdTheme t) {
    if (t.dark) {
      _darkTheme = t;
    } else {
      _lightTheme = t;
    }
  }

  /// Sun/moon button: go to the other mode, restoring its saved tweaks.
  void toggleBrightness() {
    final cur = theme.value;
    final other = cur.dark ? _lightTheme : _darkTheme;
    updateTheme(other ?? cur.switchedBrightness());
  } // each mode remembers its own tweaks

  final MdStorage storage;
  final String storageKey;
  final int maxUndo;
  final String initialText;

  final TextEditingController text = TextEditingController();
  final FocusNode focus = FocusNode();
  final ValueNotifier<MdTheme> theme;
  final ValueNotifier<String> previewText = ValueNotifier('');
  final ValueNotifier<MdSaveState> saveState = ValueNotifier(MdSaveState.saved);
  final ValueNotifier<int> documentReplaced = ValueNotifier(0);

  /// Grouped verse arrangement: false = Inline, true = Stacked.
  final ValueNotifier<bool> stacked = ValueNotifier(false);

  final ValueNotifier<MdRefPlacement> refPlacement = ValueNotifier(
    MdRefPlacement.above,
  );

  final ValueNotifier<bool> refOwnLine = ValueNotifier(false);

  void setRefOwnLine(bool v) {
    refOwnLine.value = v;
    storage.write('$storageKey.refline', v ? '1' : '0');
  }

  void setRefPlacement(MdRefPlacement v) {
    refPlacement.value = v;
    storage.write('$storageKey.ref', v.name);
  }

  /// Verse insertion: false = Manual (queued, paste at cursor),
  /// true = Automatic (appended at the end).
  final ValueNotifier<bool> autoInsert = ValueNotifier(false);

  /// Manual mode queue: markdown chunks waiting + how many verses they hold.
  final ValueNotifier<int> pendingVerses = ValueNotifier(0);
  final List<String> _pending = [];

  /// True while a MarkdownEditorPage is on screen (one editor at a time).
  bool isOpen = false;

  /// True once the user has actually focused the editor this session.
  /// Until then the stored selection is stale and invisible.
  bool cursorPlaced = false;

  // Remembers the last paste so Undo can bring the Paste button back.
  List<String> _lastPasted = const [];
  int _lastPastedCount = 0;
  String? _beforePaste, _afterPaste;
  bool _pasteRestored = false;

  final List<_Snap> _history = [];
  int _index = -1;
  String _lastText = '';
  Timer? _snapTimer, _saveTimer, _previewTimer;
  Timer? _historyTimer;
  bool _historyDirty = false;

  /// Word count is only recomputed when the preview timer fires (not per key).
  final ValueNotifier<int> wordCount = ValueNotifier(0);

  /// Cursor position and length, updated in one place instead of in the widget.
  final ValueNotifier<({int line, int col})> cursor = ValueNotifier((
    line: 1,
    col: 1,
  ));
  final ValueNotifier<int> charCount = ValueNotifier(0);

  void _updateCursor() {
    final t = text.text;
    final sel = text.selection;
    final off = sel.isValid ? sel.baseOffset.clamp(0, t.length).toInt() : 0;
    var line = 1, lastNl = -1;
    for (var i = 0; i < off; i++) {
      if (t.codeUnitAt(i) == 10) {
        line++;
        lastNl = i;
      }
    }
    cursor.value = (line: line, col: off - lastNl);
    charCount.value = t.length;
  }

  Future<void>? _initFuture;
  bool _disposed = false;

  bool get canUndo => _index > 0;
  bool get canRedo => _index >= 0 && _index < _history.length - 1;
  String get markdown => text.text;

  // ---------------------------------------------------------------- init ---
  static int countWords(String s) {
    var n = 0;
    var inWord = false;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      final space = c == 32 || c == 10 || c == 9 || c == 13 || c == 0xA0;
      if (space) {
        inWord = false;
      } else if (!inWord) {
        inWord = true;
        n++;
      }
    }
    return n;
  }

  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    final saved = await storage.read('$storageKey.text');
    final hist = await storage.read('$storageKey.history');
    final idx = await storage.read('$storageKey.index');
    final th = await storage.read('$storageKey.theme');

    final r = await storage.read('$storageKey.ref');
    refPlacement.value =
        MdRefPlacement.values.asNameMap()[r] ?? MdRefPlacement.above;
    refOwnLine.value = await storage.read('$storageKey.refline') == '1';

    _lightTheme = _decodeTheme(await storage.read('$storageKey.theme.light'));
    _darkTheme = _decodeTheme(await storage.read('$storageKey.theme.dark'));
    final active = _decodeTheme(th);
    if (active != null) {
      theme.value = active;
      _remember(active); // also covers users who saved before this change
    }
    final t = saved ?? initialText;
    text.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );

    try {
      final h = hist == null
          ? null
          : (jsonDecode(hist) as List)
                .map((e) => _Snap.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList();
      final i = int.tryParse(idx ?? '');
      if (h != null && i != null && i >= 0 && i < h.length && h[i].text == t) {
        _history
          ..clear()
          ..addAll(h);
        _index = i;
      }
    } catch (_) {}
    if (_history.isEmpty) {
      _history.add(_Snap(t, t.length, t.length));
      _index = 0;
    }
    _lastText = t;
    previewText.value = t;
    stacked.value = await storage.read('$storageKey.stacked') == '1';
    autoInsert.value = await storage.read('$storageKey.auto') == '1';
    wordCount.value = countWords(t);
    text.addListener(_onTextChanged);
    text.addListener(_updateCursor);
    _updateCursor();
    notifyListeners();
  }

  // ------------------------------------------------------ change tracking ---
  void _onTextChanged() {
    if (text.text == _lastText) return; // selection-only change
    _lastText = text.text;
    saveState.value = MdSaveState.unsaved;
    _snapTimer?.cancel();
    _snapTimer = Timer(const Duration(milliseconds: 700), _commit);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _persist);
    // History is the big blob, so save it less often.
    _historyTimer?.cancel();
    _historyTimer = Timer(
      const Duration(seconds: 3),
      () => _persist(flushHistory: true),
    );
    // Big documents get a longer preview delay.
    final len = text.text.length;
    final previewMs = len > 50000 ? 600 : (len > 20000 ? 300 : 150);
    _previewTimer?.cancel();
    _previewTimer = Timer(Duration(milliseconds: previewMs), () {
      if (_disposed) return;
      previewText.value = text.text;
      wordCount.value = countWords(text.text);
    });
  }

  void _commit() {
    _snapTimer?.cancel();
    final v = text.value;
    if (_index >= 0 && _history[_index].text == v.text) return;
    if (_index < _history.length - 1) {
      _history.removeRange(_index + 1, _history.length);
    }
    final s = _sel;
    _history.add(_Snap(v.text, s.start, s.end));
    while (_history.length > maxUndo + 1) {
      _history.removeAt(0);
    }
    _index = _history.length - 1;
    _historyDirty = true;
    notifyListeners();
  }

  /// Call when leaving the page / app goes to background.
  Future<void> saveNow() {
    _commit();
    return _persist(flushHistory: true);
  }

  Future<void> _persist({bool flushHistory = false}) async {
    _saveTimer?.cancel();
    // Capture everything synchronously so it is safe even if we get disposed.
    final t = text.text;
    final data = <String, String>{'$storageKey.text': t};
    if (flushHistory && _historyDirty) {
      _historyTimer?.cancel();
      data['$storageKey.history'] = jsonEncode(
        _history.map((e) => e.toJson()).toList(),
      );
      data['$storageKey.index'] = _index.toString();
      _historyDirty = false;
    }
    if (!_disposed) saveState.value = MdSaveState.saving;
    await storage.writeAll(data); // ONE database write
    if (!_disposed && text.text == t) saveState.value = MdSaveState.saved;
  }

  void updateTheme(MdTheme t) {
    theme.value = t;
    _remember(t);
    final json = jsonEncode(t.toJson());
    storage.writeAll({
      '$storageKey.theme': json, // the active theme (as before)
      '$storageKey.theme.${t.dark ? 'dark' : 'light'}':
          json, // this mode's copy
    });
  }

  // ------------------------------------------------------------ undo/redo ---
  void undo() {
    _commit();
    if (!canUndo) return;
    _index--;
    _historyDirty = true;
    _restore(_history[_index]);
    _syncPasteQueue();
  }

  void redo() {
    _commit();
    if (!canRedo) return;
    _index++;
    _historyDirty = true;
    _restore(_history[_index]);
    _syncPasteQueue();
  }

  void _restore(_Snap s) {
    final len = s.text.length;
    int cl(int v) => v < 0 ? 0 : (v > len ? len : v);
    text.value = TextEditingValue(
      text: s.text,
      selection: TextSelection(
        baseOffset: cl(s.start),
        extentOffset: cl(s.end),
      ),
    );
    notifyListeners();
    focus.requestFocus();
  }

  // ------------------------------------------------------- edit primitives --
  TextSelection get _sel {
    final s = text.selection;
    final len = text.text.length;
    if (!s.isValid) return TextSelection.collapsed(offset: len);
    int cl(int v) => v < 0 ? 0 : (v > len ? len : v);
    return TextSelection(baseOffset: cl(s.start), extentOffset: cl(s.end));
  }

  void _apply(String newText, TextSelection sel) {
    _commit(); // snapshot "before"
    text.value = TextEditingValue(text: newText, selection: sel);
    _commit(); // snapshot "after"
    focus.requestFocus();
  }

  ({int start, int end, String text}) _lineBlock() {
    final t = text.text;
    final s = _sel;
    final a = s.start;
    var b = s.end;
    if (b > a && b > 0 && t[b - 1] == '\n') b--;
    final ls = a == 0 ? 0 : t.lastIndexOf('\n', a - 1) + 1;
    var le = t.indexOf('\n', b);
    if (le < 0) le = t.length;
    return (start: ls, end: le, text: t.substring(ls, le));
  }

  void _applyBlock(
    ({int start, int end, String text}) r,
    List<String> before,
    List<String> after,
  ) {
    final s = _sel;
    final nb = after.join('\n');
    final out = text.text.replaceRange(r.start, r.end, nb);
    TextSelection ns;
    if (s.isCollapsed && before.length == 1) {
      final d = nb.length - r.text.length;
      final off = (s.start + d).clamp(r.start, r.start + nb.length).toInt();
      ns = TextSelection.collapsed(offset: off);
    } else {
      ns = TextSelection(
        baseOffset: r.start,
        extentOffset: r.start + nb.length,
      );
    }
    _apply(out, ns);
  }

  // --------------------------------------------------------- public: input --
  /// Insert text at the cursor (replacing any selection). Safe to call
  /// before the editor page has ever been opened.
  Future<void> insertText(String s) async {
    await init();
    final t = text.text;
    final sel = _sel;
    _apply(
      t.replaceRange(sel.start, sel.end, s),
      TextSelection.collapsed(offset: sel.start + s.length),
    );
  }

  /// Insert an image (local file path or http(s) URL) at the cursor.
  Future<void> insertImage(String pathOrUrl, {String alt = 'image'}) async {
    await init();
    final isWeb =
        pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://');
    final uri = isWeb ? pathOrUrl : Uri.file(pathOrUrl).toString();
    _insertBlock('![$alt]($uri)');
  }

  Future<void> setText(String s, {bool cursorAtStart = false}) async {
    await init();
    _apply(s, TextSelection.collapsed(offset: cursorAtStart ? 0 : s.length));
    documentReplaced.value++;
  }

  void clear() {
    _apply('', const TextSelection.collapsed(offset: 0));
    documentReplaced.value++;
  }

  // ------------------------------------------------------- verse delivery ---
  void setStacked(bool v) {
    stacked.value = v;
    storage.write('$storageKey.stacked', v ? '1' : '0');
  }

  void setAutoInsert(bool v) {
    autoInsert.value = v;
    storage.write('$storageKey.auto', v ? '1' : '0');
  }

  /// Called by sendToEditor(). Formats with the current settings, then
  /// either appends (Automatic) or queues (Manual).
  Future<void> receiveVerses(
    List<MdVerse> verses, {
    String? heading,
    String? intro,
  }) async {
    await init(); // settings are loaded by now
    final md = formatVerses(
      verses,
      stacked: stacked.value,
      refPlacement: refPlacement.value,
      refOwnLine: refOwnLine.value,
      heading: heading,
      intro: intro,
    );
    if (autoInsert.value) {
      _appendAtEnd(md);
    } else {
      _pending.add(md);
      pendingVerses.value += verses.length;
    }
  }

  void _appendAtEnd(String s) {
    final t = text.text;
    final sep = t.isEmpty || t.endsWith('\n\n')
        ? ''
        : (t.endsWith('\n') ? '\n' : '\n\n');
    final out = '$t$sep$s';
    _apply(out, TextSelection.collapsed(offset: out.length));
  }

  /// Toolbar "Paste" button (Manual mode).
  /// Returns true if pasted at the cursor, false if appended at the end
  /// because no cursor position is known.
  bool pastePending() {
    if (_pending.isEmpty) return true;
    final chunks = List<String>.of(_pending);
    final count = pendingVerses.value;
    final all = chunks.join().trimRight();
    _pending.clear();
    pendingVerses.value = 0;

    final before = text.text;
    final atCursor = cursorPlaced;
    if (atCursor) {
      _insertBlock(all); // adds blank lines around it if the cursor is mid-line
    } else {
      _appendAtEnd(all);
    }

    // Remember it, so Undo can restore the queue.
    _lastPasted = chunks;
    _lastPastedCount = count;
    _beforePaste = before;
    _afterPaste = text.text;
    _pasteRestored = false;
    return atCursor;
  }

  /// Called after undo/redo: if the text is back to "before the paste",
  /// the verses are waiting again; if it is redone, they are consumed again.
  void _syncPasteQueue() {
    final b = _beforePaste, a = _afterPaste;
    if (b == null || a == null || b == a) return;
    final t = text.text;
    if (t == b && !_pasteRestored) {
      _pending.insertAll(0, _lastPasted);
      pendingVerses.value += _lastPastedCount;
      _pasteRestored = true;
    } else if (t == a && _pasteRestored) {
      _pending.removeRange(0, _lastPasted.length);
      pendingVerses.value -= _lastPastedCount;
      _pasteRestored = false;
    }
  }

  // ------------------------------------------------------ public: formatting --
  static final _wordChar = RegExp(r'[\p{L}\p{M}\p{N}]', unicode: true);
  static bool _isWordChar(String ch) => _wordChar.hasMatch(ch);

  /// Bold/italic/strike/code. Toggles off if already wrapped.
  /// With no selection, it wraps the word under the cursor.
  void wrap(String left, String right, {String placeholder = ''}) {
    final t = text.text;
    final s = _sel;
    var a = s.start, b = s.end;
    if (a == b) {
      var ws = a, we = b;
      while (ws > 0 && _isWordChar(t[ws - 1])) {
        ws--;
      }
      while (we < t.length && _isWordChar(t[we])) {
        we++;
      }
      a = ws;
      b = we;
    }
    final sel = t.substring(a, b);
    String out;
    TextSelection ns;
    if (a >= left.length &&
        b + right.length <= t.length &&
        t.substring(a - left.length, a) == left &&
        t.substring(b, b + right.length) == right) {
      out =
          t.substring(0, a - left.length) + sel + t.substring(b + right.length);
      ns = TextSelection(
        baseOffset: a - left.length,
        extentOffset: b - left.length,
      );
    } else if (sel.length >= left.length + right.length &&
        sel.startsWith(left) &&
        sel.endsWith(right)) {
      final inner = sel.substring(left.length, sel.length - right.length);
      out = t.substring(0, a) + inner + t.substring(b);
      ns = TextSelection(baseOffset: a, extentOffset: a + inner.length);
    } else {
      final inner = sel.isEmpty ? placeholder : sel;
      out = t.substring(0, a) + left + inner + right + t.substring(b);
      ns = TextSelection(
        baseOffset: a + left.length,
        extentOffset: a + left.length + inner.length,
      );
    }
    _apply(out, ns);
  }

  void bold() => wrap('**', '**');
  void italic() => wrap('_', '_');
  void strike() => wrap('~~', '~~');
  void inlineCode() => wrap('`', '`');

  /// level 1-6, or 0 to remove. Works on every line touched by the selection.
  void setHeader(int level) {
    final r = _lineBlock();
    final lines = r.text.split('\n');
    final hdr = RegExp(r'^(#{1,6})\s+');
    final filled = lines.where((l) => l.trim().isNotEmpty).toList();
    final allSame =
        level > 0 &&
        filled.isNotEmpty &&
        filled.every((l) {
          final m = hdr.firstMatch(l);
          return m != null && m.group(1)!.length == level;
        });
    final out = lines.map((l) {
      if (l.trim().isEmpty && lines.length > 1) return l;
      final stripped = l.replaceFirst(hdr, '');
      if (level == 0 || allSame) return stripped;
      return '${'#' * level} $stripped';
    }).toList();
    _applyBlock(r, lines, out);
  }

  static final _anyMarker = RegExp(r'^(?:[-*+] \[[ xX]\] |[-*+] |\d+\. |> ?)');
  static final _bulletRe = RegExp(r'^[-*+] (?!\[[ xX]\] )');
  static final _taskRe = RegExp(r'^[-*+] \[[ xX]\] ');
  static final _orderedRe = RegExp(r'^\d+\. ');
  static final _quoteRe = RegExp(r'^> ?');

  void toggleLinePrefix(String Function(int i) prefixFor, RegExp marker) {
    final r = _lineBlock();
    final lines = r.text.split('\n');
    final filled = lines.where((l) => l.trim().isNotEmpty);
    final remove =
        filled.isNotEmpty && filled.every((l) => marker.hasMatch(l.trimLeft()));
    var n = 0;
    final out = lines.map((l) {
      if (l.trim().isEmpty && lines.length > 1) return l;
      final body = l.trimLeft();
      final indent = l.substring(0, l.length - body.length);
      if (remove) return indent + body.replaceFirst(marker, '');
      return '$indent${prefixFor(n++)}${body.replaceFirst(_anyMarker, '')}';
    }).toList();
    _applyBlock(r, lines, out);
  }

  void bulletList() => toggleLinePrefix((_) => '- ', _bulletRe);
  void numberedList() => toggleLinePrefix((i) => '${i + 1}. ', _orderedRe);
  void taskList() => toggleLinePrefix((_) => '- [ ] ', _taskRe);
  void quote() => toggleLinePrefix((_) => '> ', _quoteRe);

  void insertLink() {
    final t = text.text;
    final s = _sel;
    final label = s.isCollapsed ? 'link text' : t.substring(s.start, s.end);
    final md = '[$label](url)';
    final urlStart = s.start + label.length + 3;
    _apply(
      t.replaceRange(s.start, s.end, md),
      TextSelection(baseOffset: urlStart, extentOffset: urlStart + 3),
    );
  }

  void insertImageTemplate() {
    final t = text.text;
    final s = _sel;
    final alt = s.isCollapsed ? 'alt text' : t.substring(s.start, s.end);
    final md = '![$alt](https://)';
    final urlStart = s.start + alt.length + 4;
    _apply(
      t.replaceRange(s.start, s.end, md),
      TextSelection(baseOffset: urlStart, extentOffset: urlStart + 8),
    );
  }

  void insertEmoji(String e) {
    final t = text.text;
    final s = _sel;
    _apply(
      t.replaceRange(s.start, s.end, e),
      TextSelection.collapsed(offset: s.start + e.length),
    );
  }

  void insertCodeBlock() {
    final t = text.text;
    final s = _sel;
    if (s.isCollapsed) {
      _insertBlock('```\ncode\n```', selOffset: 4, selLength: 4);
    } else {
      _insertBlock(
        '```\n${t.substring(s.start, s.end)}\n```',
        replaceSelection: true,
      );
    }
  }

  void insertTable() => _insertBlock(
    '| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n|  |  |  |',
    selOffset: 2,
    selLength: 8,
  );

  void insertRule() => _insertBlock('---');

  /// Inserts text as its own block (blank line before, newline after).
  void _insertBlock(
    String body, {
    int? selOffset,
    int selLength = 0,
    bool replaceSelection = false,
  }) {
    final t = text.text;
    final s = _sel;
    final a = s.start;
    final b = s.end;
    var lead = '';
    if (a > 0) {
      if (t[a - 1] != '\n') {
        lead = '\n\n';
      } else if (a >= 2 && t[a - 2] != '\n') {
        lead = '\n';
      }
    }
    final trail = (b < t.length && t[b] == '\n') ? '' : '\n';
    final out = t.replaceRange(a, b, '$lead$body$trail');
    final base = a + lead.length;
    final ns = selOffset != null
        ? TextSelection(
            baseOffset: base + selOffset,
            extentOffset: base + selOffset + selLength,
          )
        : TextSelection.collapsed(offset: base + body.length + trail.length);
    _apply(out, ns);
  }

  /// Ctrl+Enter: jump to the end of the current line and start a new one,
  /// no matter where the cursor is in it. On a list/quote line the new line
  /// gets the next marker; on an empty list item it leaves the list.
  void jumpToNextLine() {
    final t = text.text;
    final s = _sel;
    final ls = s.end == 0 ? 0 : t.lastIndexOf('\n', s.end - 1) + 1;
    var le = t.indexOf('\n', s.end);
    if (le < 0) le = t.length;
    final line = t.substring(ls, le);
    final m = MdSmartListFormatter.matchMarker(line);
    if (m != null) {
      final rest = line.substring(m[0]!.length);
      if (rest.trim().isEmpty) {
        // empty item: remove the marker (same as pressing Enter on it)
        _apply(t.replaceRange(ls, le, ''), TextSelection.collapsed(offset: ls));
        return;
      }
      final ins =
          '\n${m.group(1)}${MdSmartListFormatter.nextMarker(m.group(2)!)}';
      _apply(
        t.replaceRange(le, le, ins),
        TextSelection.collapsed(offset: le + ins.length),
      );
      return;
    }
    _apply(
      t.replaceRange(le, le, '\n'),
      TextSelection.collapsed(offset: le + 1),
    );
  }

  static const _indentUnit = '  '; // 4 spaces

  /// Tab. On a list line or a multi-line selection: indent the lines.
  /// On a plain line with just a cursor: insert spaces at the cursor.
  void indent() {
    final s = _sel;
    final r = _lineBlock();
    final lines = r.text.split('\n');
    final onList = MdSmartListFormatter.matchMarker(lines.first) != null;
    if (s.isCollapsed && !onList) {
      _apply(
        text.text.replaceRange(s.start, s.end, _indentUnit),
        TextSelection.collapsed(offset: s.start + _indentUnit.length),
      );
      return;
    }
    final out = [
      for (final l in lines) l.trim().isEmpty ? l : '$_indentUnit$l',
    ];
    _applyBlock(r, lines, out);
  }

  /// Shift+Tab: remove up to one indent unit (or a tab) from each line.
  void outdent() {
    final r = _lineBlock();
    final lines = r.text.split('\n');
    final lead = RegExp('^(?: {1,${_indentUnit.length}}|\\t)');
    final out = [for (final l in lines) l.replaceFirst(lead, '')];
    if (out.join('\n') == r.text) return; // nothing to remove
    _applyBlock(r, lines, out);
  }

  // ------------------------------------------------------- header ids / toc --
  static final _slugStrip = RegExp(r'[^\p{L}\p{M}\p{N}_\- ]', unicode: true);

  static String slugify(String s) =>
      s.toLowerCase().trim().replaceAll(_slugStrip, '').replaceAll(' ', '-');

  static final _headerRe = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');

  /// If the cursor line is a header, returns `[Title](#slug)` (GitHub style id).
  String? headerLinkAtCursor() {
    final m = _headerRe.firstMatch(_lineBlock().text);
    if (m == null) return null;
    return '[${m.group(2)}](#${slugify(m.group(2)!)})';
  }

  void insertToc() {
    final seen = <String, int>{};
    final buf = StringBuffer();
    var inCode = false;
    for (final line in text.text.split('\n')) {
      if (line.trimLeft().startsWith('```')) inCode = !inCode;
      if (inCode) continue;
      final m = _headerRe.firstMatch(line);
      if (m == null) continue;
      final title = m.group(2)!;
      var slug = slugify(title);
      final n = seen[slug] ?? 0;
      seen[slug] = n + 1;
      if (n > 0) slug = '$slug-$n'; // GitHub de-duplicates like this
      buf.writeln('${'  ' * (m.group(1)!.length - 1)}- [$title](#$slug)');
    }
    final toc = buf.toString().trimRight();
    if (toc.isEmpty) return;
    _insertBlock(toc);
  }

  // ------------------------------------------------------- save as / open --
  String _defaultName() {
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(RegExp(r'[:T]'), '-');
    return 'markdown_$stamp.md';
  }

  /// "Save as" dialog (file_picker). Returns where it was saved, or null if cancelled.
  Future<String?> saveAs() async {
    final bytes = Uint8List.fromList(utf8.encode(text.text));
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save Markdown',
      fileName: _defaultName(),
      bytes: bytes,
    );
    if (uri == null) return null;
    if (uri.scheme == 'file') {
      // Some desktop versions only return the chosen path: make sure it is written.
      final f = File(uri.toFilePath());
      if (!await f.exists() || await f.length() != bytes.length) {
        await f.writeAsBytes(bytes);
      }
      return f.path;
    }
    return uri.toString(); // Android returns a content:// uri
  }

  /// Opens a .md file and loads it into the editor (undoable). Returns the file name.
  Future<String?> openMarkdownFile() async {
    final file = await FilePicker.pickFile(
      // Some Android devices grey out .md files in a filtered picker.
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid
          ? null
          : const ['md', 'markdown', 'txt'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    await setText(
      utf8.decode(bytes, allowMalformed: true),
      cursorAtStart: true,
    );
    return file.name;
  }

  /// Re-reads everything from storage (used after a profile import).
  Future<void> reloadFromStorage() async {
    if (_initFuture == null) return; // never opened yet: init() will read fresh
    await _initFuture;
    _snapTimer?.cancel();
    _saveTimer?.cancel();
    _historyTimer?.cancel();
    _previewTimer?.cancel();

    _lightTheme = _decodeTheme(await storage.read('$storageKey.theme.light'));
    _darkTheme = _decodeTheme(await storage.read('$storageKey.theme.dark'));
    final active = _decodeTheme(await storage.read('$storageKey.theme'));
    theme.value = active ?? MdTheme.light();
    _remember(theme.value);

    stacked.value = await storage.read('$storageKey.stacked') == '1';
    autoInsert.value = await storage.read('$storageKey.auto') == '1';

    final r = await storage.read('$storageKey.ref');
    refPlacement.value =
        MdRefPlacement.values.asNameMap()[r] ?? MdRefPlacement.above;
    refOwnLine.value = await storage.read('$storageKey.refline') == '1';

    final t = await storage.read('$storageKey.text') ?? '';
    _lastText = t; // set first so the text listener ignores the change below
    text.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
    previewText.value = t;
    wordCount.value = countWords(t);
    _history
      ..clear()
      ..add(_Snap(t, t.length, t.length));
    _index = 0;
    _historyDirty = false;
    saveState.value = MdSaveState.saved;
    documentReplaced.value++;
    notifyListeners();
  }

  // ---------------------------------------------------------------- export --
  /// Saves a .md file to Downloads. Returns the full path written.
  Future<String> exportToDownloads() async {
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(RegExp(r'[:T]'), '-');
    final name = 'markdown_$stamp.md';
    final candidates = <Future<Directory?>>[
      if (Platform.isAndroid)
        Future.value(Directory('/storage/emulated/0/Download')),
      if (!Platform.isAndroid) getDownloadsDirectory(),
      if (Platform.isAndroid)
        getExternalStorageDirectory(), // app-specific fallback
      getApplicationDocumentsDirectory(),
    ];
    Object? lastError;
    for (final f in candidates) {
      try {
        final dir = await f;
        if (dir == null) continue;
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File('${dir.path}${Platform.pathSeparator}$name');
        await file.writeAsString(text.text);
        return file.path;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('No writable folder found');
  }

  @override
  void dispose() {
    _disposed = true;
    _snapTimer?.cancel();
    _saveTimer?.cancel();
    _previewTimer?.cancel();
    _historyTimer?.cancel();
    text.removeListener(_onTextChanged);
    text.removeListener(_updateCursor);
    cursor.dispose();
    charCount.dispose();
    text.dispose();
    focus.dispose();
    theme.dispose();
    previewText.dispose();
    saveState.dispose();
    documentReplaced.dispose();
    stacked.dispose();
    refPlacement.dispose();
    refOwnLine.dispose();
    autoInsert.dispose();
    pendingVerses.dispose();
    wordCount.dispose();
    super.dispose();
  }
}
