import 'dart:io';

/// Android only: free memory from /proc/meminfo. Null elsewhere or on failure.
Future<({int totalMb, int availableMb})?> readMemInfo() async {
  if (!Platform.isAndroid) return null;
  try {
    final text = await File('/proc/meminfo').readAsString();
    int mb(String key) {
      final m = RegExp('$key:\\s+(\\d+)').firstMatch(text);
      return m == null ? 0 : int.parse(m[1]!) ~/ 1024; // kB -> MB
    }

    final total = mb('MemTotal');
    final avail = mb('MemAvailable');
    return total > 0 ? (totalMb: total, availableMb: avail) : null;
  } catch (_) {
    return null;
  }
}
