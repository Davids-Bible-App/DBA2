import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Replaces the Rust commands (save_meme_image / delete_meme_image).
/// Originals are stored untouched; screen previews are decoded smaller in
/// memory only. Nothing "tiny" is ever written to disk or exported.
class MemeStorage {
  late final Directory dir;
  late final Directory _cache;
  late final Directory _thumbs;

  Future<void> init() async {
    final base = (await getApplicationSupportDirectory()).path;
    dir = await Directory(p.join(base, 'memes')).create(recursive: true);
    _cache = await Directory(p.join(dir.path, 'cache')).create();
    _thumbs = await Directory(p.join(_cache.path, 'thumbs')).create();
  }

  static bool isRemote(String s) => s.startsWith('http');
  File file(String name) => File(p.join(dir.path, name));

  String _stamp() =>
      '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(99999)}';

  Future<String> importFile(String srcPath) async {
    final ext = p.extension(srcPath).toLowerCase();
    final name = 'upload_${_stamp()}${ext.isEmpty ? '.jpg' : ext}';
    await File(srcPath).copy(file(name).path);
    return name;
  }

  static String fullUrl(String url) => url.contains('images.pexels.com')
      ? '${url.split('?').first}?auto=compress&cs=tinysrgb&fit=max&w=2000'
      : url;

  Future<String> importUrl(String url) async {
    final res = await http
        .get(Uri.parse(fullUrl(url)))
        .timeout(const Duration(seconds: 30));
    final type = res.headers['content-type'] ?? '';
    if (res.statusCode != 200 || !type.startsWith('image/')) {
      throw const HttpException('That link is not a direct image.');
    }
    final ext = type.contains('png')
        ? '.png'
        : type.contains('webp')
        ? '.webp'
        : type.contains('gif')
        ? '.gif'
        : '.jpg';
    final name = 'upload_${_stamp()}$ext';
    await file(name).writeAsBytes(res.bodyBytes, flush: true);
    return name;
  }

  Future<String> saveBytes(String name, List<int> bytes) async {
    await file(name).writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<void> delete(String name) async {
    if (name.isEmpty || name.startsWith('data:') || isRemote(name)) return;
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    // also removes v1-style "_thumb" / "_preview" siblings if they exist
    for (final n in [name, '${base}_thumb$ext', '${base}_preview$ext']) {
      final f = file(n);
      if (await f.exists()) await f.delete();
    }
  }

  static String _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  /// Local file for a source. Remote presets are downloaded once (large
  /// version) and cached, so previews AND exports use the same sharp file.
  Future<File> resolve(String src) async {
    if (!isRemote(src)) return file(src);
    final f = File(p.join(_cache.path, '${_fnv(src)}.img'));
    if (await f.exists() && await f.length() > 0) return f;
    final res = await http
        .get(Uri.parse(fullUrl(src)))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(res.bodyBytes, flush: true);
    return tmp.rename(f.path);
  }

  /// Small thumbnail for a remote image, downloaded ONCE and kept on disk.
  /// Returns null if it can't be fetched (e.g. offline).
  Future<File?> thumbFile(String src) async {
    final f = File(p.join(_thumbs.path, '${_fnv(src)}.jpg'));
    if (await f.exists() && await f.length() > 0) return f;
    try {
      final url = src.contains('images.pexels.com')
          ? '${src.split('?').first}?auto=compress&cs=tinysrgb&fit=crop&h=140&w=200'
          : src;
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(res.bodyBytes, flush: true);
      return await tmp.rename(f.path);
    } catch (_) {
      return null;
    }
  }

  /// Decodes at most [maxDim] px on the long edge (never upscales).
  Future<ui.Image> decode(String src, {required int maxDim}) async {
    final bytes = await (await resolve(src)).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    int? tw, th;
    if (math.max(desc.width, desc.height) > maxDim) {
      if (desc.width >= desc.height) {
        tw = maxDim;
      } else {
        th = maxDim;
      }
    }
    final codec = await desc.instantiateCodec(
      targetWidth: tw,
      targetHeight: th,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    desc.dispose();
    buffer.dispose();
    return frame.image;
  }
}
