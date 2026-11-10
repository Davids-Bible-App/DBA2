import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Runs [readGgufLayerCount] on a background isolate so the UI never hitches.
Future<int?> readGgufLayerCountAsync(String path) => Isolate.run(() => readGgufLayerCount(path));

/// Reads `<arch>.block_count` from a GGUF header (replaces `model.n_layer()`).
/// The key sits near the start of the metadata, long before the huge
/// tokenizer arrays, so reading the first 4 MB is plenty.
int? readGgufLayerCount(String path) {
  RandomAccessFile? raf;
  try {
    raf = File(path).openSync();
    final bytes = raf.readSync(4 * 1024 * 1024);
    if (bytes.length < 24 || String.fromCharCodes(bytes, 0, 4) != 'GGUF') return null;
    final d = ByteData.sublistView(bytes);
    var p = 4;
    int u32() {
      final v = d.getUint32(p, Endian.little);
      p += 4;
      return v;
    }

    int u64() {
      final v = d.getUint64(p, Endian.little);
      p += 8;
      return v;
    }

    // GGUF value type -> fixed byte size (8 = string, 9 = array are variable).
    const fixed = <int, int>{0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8};
    void skip(int type) {
      final size = fixed[type];
      if (size != null) {
        p += size;
      } else if (type == 8) {
        p += u64();
      } else if (type == 9) {
        final itemType = u32();
        final count = u64();
        final itemSize = fixed[itemType];
        if (itemSize != null) {
          p += itemSize * count;
        } else {
          for (var i = 0; i < count; i++) {
            skip(itemType);
          }
        }
      } else {
        throw const FormatException('unknown GGUF type');
      }
    }

    u32(); // version
    u64(); // tensor count
    final kvCount = u64();
    for (var i = 0; i < kvCount; i++) {
      final keyLen = u64();
      final key = String.fromCharCodes(bytes, p, p + keyLen);
      p += keyLen;
      final type = u32();
      if (key.endsWith('.block_count')) {
        if (type == 4) return u32();
        if (type == 10) return u64();
        return null;
      }
      skip(type);
    }
  } catch (_) {
    return null; // truncated / unexpected layout
  } finally {
    raf?.closeSync();
  }
  return null;
}
