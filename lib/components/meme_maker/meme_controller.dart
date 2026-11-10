import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dba2/storage/profile/profile.dart';
import 'package:dba2/storage/profile/profile_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:google_fonts/google_fonts.dart';

import 'meme_models.dart';
import 'meme_renderer.dart';
import 'meme_storage.dart';

/// All Meme Maker state + logic (replaces the signals in MemeMaker.jsx).
///
/// Two notification channels, for speed:
///  • [canvasRev]  – bumps on EVERY change; only the canvas repaints.
///  • notifyListeners() – panels rebuild; skipped while dragging a layer.
class MemeMakerController extends ChangeNotifier {
  MemeMakerController({required this.repo, required this.settings});

  final ProfileRepository repo;
  final ProfileSettings settings;
  final storage = MemeStorage();
  final textCache = MemeTextCache();
  final canvasRev = ValueNotifier<int>(0);

  static const _kProject = 'meme.project.v2';

  MemeState _state = MemeState.initial();
  List<String> _images = List.of(kPresetImages);
  String? _selectedId;
  ui.Image? _preview;
  String? _previewSrc;
  int _previewToken = 0;
  bool _previewLoading = false;
  List<MemeTemplate> _templates = const [];
  int? _currentTemplateId;
  ExportFormat exportFormat = ExportFormat.png;
  int exportSize = 700; // long edge in px; 0 = original
  bool _showSelection = true;
  bool get showSelection => _showSelection;

  final _undo = <MemeState>[];
  final _redo = <MemeState>[];
  String? _lastKey;
  Timer? _keyTimer, _saveTimer;
  bool _ready = false;

  // ───────── getters ─────────
  bool get ready => _ready;
  MemeState get state => _state;
  List<String> get images => _images;
  String? get selectedId => _selectedId;
  ui.Image? get previewImage => _preview;
  bool get previewLoading => _previewLoading;
  List<MemeTemplate> get templates => _templates;
  int? get currentTemplateId => _currentTemplateId;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get backgroundSelected => _selectedId == kBackgroundId;
  double get aspectValue =>
      _state.aspect.ratio ??
      (_preview != null ? _preview!.width / _preview!.height : 1.0);

  MemeLayer? get selectedLayer {
    final id = _selectedId;
    if (id == null || id == kBackgroundId) return null;
    for (final l in _state.layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  // ───────── init / persistence ─────────
  Future<void>? _initFuture;

  /// Safe to call many times / from anywhere; only runs once.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    await storage.init();
    _loadProject();
    await _reloadTemplates();
    _ready = true;
    _awaitFonts();
    notifyListeners();
    unawaited(_syncPreview());
  }

  void _loadProject() {
    try {
      final raw = settings.getString(_kProject);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _images = List<String>.from(j['images'] ?? kPresetImages);
        _state = MemeState.fromJson(Map<String, dynamic>.from(j['state']));
        exportFormat = ExportFormat.values.firstWhere(
          (e) => e.name == j['exportFormat'],
          orElse: () => ExportFormat.png,
        );
        exportSize = (j['exportSize'] as num?)?.toInt() ?? 700;
      }
    } catch (e) {
      debugPrint('MemeMaker: load failed: $e');
    }
    final ls = _state.layers;
    _selectedId = ls.isNotEmpty ? ls.last.id : kBackgroundId;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), flush);
  }

  /// Writes the project now (the page calls this when it closes).
  Future<void> flush() {
    _saveTimer?.cancel();
    return settings.setString(
      _kProject,
      jsonEncode({
        'images': _images,
        'state': _state.toJson(),
        'exportFormat': exportFormat.name,
        'exportSize': exportSize,
      }),
    );
  }

  void _awaitFonts() {
    // Request only the fonts that the current layers actually use.
    for (final l in _state.layers) {
      fontByKey(l.fontFamily).preload();
    }
    GoogleFonts.pendingFonts().then((_) {
      textCache.clear(); // re-measure text now that the real font is loaded
      _bump();
    });
  }

  // ───────── core edit pipeline + undo ─────────
  void _bump({bool panel = true}) {
    canvasRev.value++;
    if (panel) notifyListeners();
  }

  /// [key] merges rapid edits (slider drags, typing) into ONE undo step.
  void _apply(MemeState next, {String? key, bool panel = true}) {
    if (identical(next, _state)) return;
    if (key == null || key != _lastKey) {
      _undo.add(_state);
      if (_undo.length > 60) _undo.removeAt(0);
      _redo.clear();
    }
    _lastKey = key;
    _keyTimer?.cancel();
    if (key != null) {
      _keyTimer = Timer(
        const Duration(milliseconds: 500),
        () => _lastKey = null,
      );
    }
    _state = next;
    _scheduleSave();
    _syncPreview();
    _bump(panel: panel);
  }

  /// Call when a drag / slider ends so the next edit is a new undo step.
  void endGesture() {
    _lastKey = null;
    _keyTimer?.cancel();
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_state);
    _state = _undo.removeLast();
    _afterJump();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_state);
    _state = _redo.removeLast();
    _afterJump();
  }

  void _afterJump() {
    _lastKey = null;
    if (_selectedId != kBackgroundId &&
        !_state.layers.any((l) => l.id == _selectedId)) {
      _selectedId = _state.layers.isNotEmpty
          ? _state.layers.last.id
          : kBackgroundId;
    }
    _scheduleSave();
    _syncPreview();
    _awaitFonts();
    _bump();
  }

  // ───────── selection + layers ─────────
  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    _bump();
  }

  void toggleShowSelection() {
    _showSelection = !_showSelection;
    _bump(); // repaints the canvas and rebuilds the panels (so the button updates)
  }

  void updateLayer(
    String id,
    MemeLayer Function(MemeLayer) f, {
    String? key,
    bool panel = true,
  }) {
    final ls = _state.layers;
    final i = ls.indexWhere((l) => l.id == id);
    if (i < 0) return;
    final copy = List<MemeLayer>.of(ls)..[i] = f(ls[i]);
    _apply(
      _state.copyWith(layers: copy),
      key: key,
      panel: panel,
    );
  }

  void setFont(String id, String family) {
    updateLayer(id, (l) => l.copyWith(fontFamily: family));
    _awaitFonts();
  }

  void addTextLayer() {
    final l = MemeLayer(id: newId());
    _selectedId = l.id;
    _apply(_state.copyWith(layers: [..._state.layers, l]));
  }

  /// Called from anywhere (e.g. the verse action bar) to drop a verse in.
  Future<void> injectVerse(String text) async {
    await init(); // the controller may not have been opened yet
    final n = text.length;
    final l = MemeLayer(
      id: newId(),
      content: text,
      x: 50,
      y: 50,
      fontFamily: 'Arial',
      textWrap: true,
      wrapWidth: 250,
      bold: false,
      italic: true,
      color: Colors.white,
      strokeColor: Colors.black,
      scale: n <= 30 ? 1 : math.max(0.4, 30 / n),
    );
    _selectedId = l.id;
    _apply(_state.copyWith(layers: [..._state.layers, l]));
  }

  /// Several verses at once: joined with blank lines, citation last.
  Future<void> injectVerses(List<String> verseTexts, {String citation = ''}) =>
      injectVerse(
        [...verseTexts, if (citation.isNotEmpty) citation].join('\n\n'),
      );

  void duplicateLayer(String id) {
    final i = _state.layers.indexWhere((l) => l.id == id);
    if (i < 0) return;
    final src = _state.layers[i];
    final c = src.copyWith(
      id: newId(),
      x: (src.x + 4).clamp(0, 100),
      y: (src.y + 4).clamp(0, 100),
    );
    _selectedId = c.id;
    _apply(_state.copyWith(layers: [..._state.layers]..insert(i + 1, c)));
  }

  void deleteLayer(String id) {
    final ls = _state.layers.where((l) => l.id != id).toList();
    if (_selectedId == id) {
      _selectedId = ls.isNotEmpty ? ls.last.id : kBackgroundId;
    }
    _apply(_state.copyWith(layers: ls));
  }

  void clearLayers() {
    _selectedId = kBackgroundId;
    _apply(_state.copyWith(layers: const []));
  }

  void moveLayer(int from, int to) {
    final ls = List<MemeLayer>.of(_state.layers);
    ls.insert(to, ls.removeAt(from));
    _apply(_state.copyWith(layers: ls));
  }

  /// Drag on canvas. Position only → no panel rebuild.
  void dragLayer(String id, double x, double y) => updateLayer(
    id,
    (l) => l.copyWith(x: x.clamp(0, 100), y: y.clamp(0, 100)),
    key: 'drag:$id',
    panel: false,
  );

  void rotateLayer(String id, double deg, {bool panel = true}) {
    var r = deg % 360; // Dart's % is never negative
    if (r > 180) r -= 360;
    updateLayer(
      id,
      (l) => l.copyWith(rotation: r),
      key: 'rot:$id',
      panel: panel,
    );
  }

  void setBgZoom(double z, {bool panel = true}) {
    if (_state.bgLocked) return;
    _apply(
      _state.copyWith(bgZoom: z.clamp(0.5, 4.0)),
      key: 'bgzoom',
      panel: panel,
    );
  }

  void scaleLayer(String id, double s, {bool panel = true}) => updateLayer(
    id,
    (l) => l.copyWith(scale: s.clamp(0.2, 2.0)),
    key: 'scale:$id',
    panel: panel,
  );

  // ───────── background ─────────
  void toggleBgLock() => _apply(_state.copyWith(bgLocked: !_state.bgLocked));

  void dragBackground(double x, double y) {
    if (_state.bgLocked) return;
    _apply(
      _state.copyWith(bgX: x.clamp(0, 100), bgY: y.clamp(0, 100)),
      key: 'bgdrag',
      panel: false,
    );
  }

  void setFit(BgFit f) => _apply(_state.copyWith(fit: f));
  void setBgColor(ui.Color c) =>
      _apply(_state.copyWith(bgColor: c), key: 'bgcolor');
  void setCornerSize(double v) =>
      _apply(_state.copyWith(cornerSize: v), key: 'corner');
  void setFlipH() => _apply(_state.copyWith(flipH: !_state.flipH));
  void setFlipV() => _apply(_state.copyWith(flipV: !_state.flipV));

  void setCorner(CornerStyle c) => _apply(
    _state.copyWith(
      corner: c,
      aspect: c == CornerStyle.squircle ? MemeAspect.square : null,
    ),
  );

  void setAspect(MemeAspect a) {
    if (a == MemeAspect.original && _state.selectedImage == null) return;
    _apply(
      _state.copyWith(
        aspect: a,
        corner: _state.corner == CornerStyle.squircle && a != MemeAspect.square
            ? CornerStyle.none
            : null,
      ),
    );
  }

  // ───────── images ─────────
  void selectImage(String? src) {
    _apply(
      _state.copyWith(
        selectedImage: src,
        aspect: src == null && _state.aspect == MemeAspect.original
            ? MemeAspect.square
            : null,
      ),
    );
    if (src == null) select(kBackgroundId);
  }

  Future<void> _syncPreview() async {
    final src = _state.selectedImage;
    if (src == _previewSrc) return;
    _previewSrc = src;
    final token = ++_previewToken;
    if (src == null) {
      _preview = null;
      _previewLoading = false;
      _bump();
      return;
    }
    _previewLoading = true;
    notifyListeners();
    try {
      // Screen preview only. Export decodes the original separately.
      final im = await storage.decode(src, maxDim: 1400);
      if (token != _previewToken) return;
      _preview = im;
    } catch (e) {
      if (token != _previewToken) return;
      debugPrint('MemeMaker: preview failed: $e');
      _preview = null;
    }
    _previewLoading = false;
    _bump();
  }

  Future<void> addImagePaths(List<String> paths) async {
    final names = <String>[];
    for (final p in paths) {
      try {
        names.add(await storage.importFile(p));
      } catch (e) {
        debugPrint('MemeMaker: import failed: $e');
      }
    }
    if (names.isEmpty) return;
    _images = [...names, ..._images];
    selectImage(names.first);
  }

  /// Returns an error message, or null on success.
  Future<String?> addImageUrl(String input) async {
    var url = input.trim();
    final pexels = RegExp(
      r'pexels\.com/photo/.*[/-](\d+)/?$',
      caseSensitive: false,
    ).firstMatch(url);
    if (pexels != null) {
      final id = pexels.group(1);
      url = 'https://images.pexels.com/photos/$id/pexels-photo-$id.jpeg';
    }
    final unsplash = RegExp(
      r'unsplash\.com/photos/.*-?([a-zA-Z0-9_-]{11})/?$',
      caseSensitive: false,
    ).firstMatch(url);
    if (unsplash != null) {
      url =
          'https://images.unsplash.com/photo-${unsplash.group(1)}?auto=format&fit=crop&q=80&w=2000';
    }
    if (url.contains('pinterest.com/pin/')) {
      return "Pinterest hides its image addresses. Long-press / right-click the image and choose 'Copy image address' instead.";
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'Please enter a valid HTTP or HTTPS link.';
    }
    try {
      final name = await storage.importUrl(url);
      _images = [name, ..._images];
      selectImage(name);
      return null;
    } catch (e) {
      return 'Could not download that image ($e).';
    }
  }

  bool isImageProtected(String src) => _templateImages().contains(src);

  Set<String> _templateImages() {
    final out = <String>{};
    for (final t in _templates) {
      try {
        final s = (jsonDecode(t.payload) as Map)['selectedImage'];
        if (s is String) out.add(s);
      } catch (_) {}
    }
    return out;
  }

  Future<void> removeImage(String src) async {
    final next = _images.where((i) => i != src).toList();
    _images = next;
    if (_state.selectedImage == src) {
      selectImage(next.isNotEmpty ? next.first : null);
    } else {
      _scheduleSave();
      notifyListeners();
    }
    await storage.delete(src);
  }

  /// Removes orphaned uploads and restores the presets. Templates survive.
  Future<void> resetImages() async {
    final keep = _templateImages();
    for (final f in _images.where(
      (i) => i.startsWith('upload_') && !keep.contains(i),
    )) {
      await storage.delete(f);
    }
    _images = {...kPresetImages, ...keep}.toList();
    _undo.clear();
    _redo.clear();
    _currentTemplateId = null;
    _state = _state.copyWith(
      selectedImage: null,
      aspect: _state.aspect == MemeAspect.original ? MemeAspect.square : null,
    );
    _selectedId = kBackgroundId;
    _scheduleSave();
    await _syncPreview();
    _bump();
  }

  // ───────── templates ─────────
  Future<void> _reloadTemplates() async {
    try {
      _templates = [
        for (final r in await repo.getTemplates()) MemeTemplate.fromRow(r),
      ];
    } catch (e) {
      debugPrint('MemeMaker: templates failed: $e');
    }
  }

  String uniqueTitle(String wanted) {
    bool taken(String t) => _templates.any((x) => x.title == t);
    if (!taken(wanted)) return wanted;
    var n = 1;
    while (taken('$wanted-$n')) {
      n++;
    }
    return '$wanted-$n';
  }

  Future<void> saveTemplate({
    int? existingId,
    String title = 'Template',
  }) async {
    MemeTemplate? old;
    if (existingId != null) {
      old = _templates.where((t) => t.id == existingId).firstOrNull;
      if (old != null) title = old.title;
    } else {
      title = uniqueTitle(title.trim().isEmpty ? 'Template' : title.trim());
    }
    try {
      final png = await MemeExporter.render(
        _state,
        storage,
        maxDim: 300,
        format: ExportFormat.png,
      );
      final thumb = await storage.saveBytes(
        'template_${DateTime.now().millisecondsSinceEpoch}.png',
        png,
      );
      _currentTemplateId = await repo.saveTemplate(
        id: existingId,
        title: title,
        thumbnail: thumb,
        payload: jsonEncode(_state.toJson()),
      );
      if (old != null) await storage.delete(old.thumbnail);
      await _reloadTemplates();
      notifyListeners();
    } catch (e) {
      debugPrint('MemeMaker: save template failed: $e');
    }
  }

  void applyTemplate(MemeTemplate t) {
    try {
      final next = MemeState.fromJson(
        Map<String, dynamic>.from(jsonDecode(t.payload) as Map),
      );
      _currentTemplateId = t.id;
      _selectedId = next.layers.isNotEmpty
          ? next.layers.last.id
          : kBackgroundId;
      if (next.selectedImage != null && !_images.contains(next.selectedImage)) {
        _images = [next.selectedImage!, ..._images];
      }
      _apply(next);
      _awaitFonts();
    } catch (e) {
      debugPrint('MemeMaker: apply template failed: $e');
    }
  }

  Future<void> deleteTemplate(MemeTemplate t) async {
    await repo.deleteTemplate(t.id);
    await storage.delete(t.thumbnail);
    if (_currentTemplateId == t.id) _currentTemplateId = null;
    await _reloadTemplates();
    notifyListeners();
  }

  // ───────── export ─────────
  Future<Uint8List> exportBytes() => MemeExporter.render(
    _state,
    storage,
    maxDim: exportSize,
    format: exportFormat,
  );

  String get exportFileName =>
      'meme-${DateTime.now().millisecondsSinceEpoch}.${exportFormat == ExportFormat.png ? 'png' : 'jpg'}';

  @override
  void dispose() {
    _keyTimer?.cancel();
    flush();
    textCache.clear();
    canvasRev.dispose();
    super.dispose();
  }
}
