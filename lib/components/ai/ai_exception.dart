/// A user-presentable error. UI code can show [message] directly.
class AiException implements Exception {
  const AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

String errorMessage(Object e, String fallback) => e is AiException ? e.message : fallback;
