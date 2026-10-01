/// Compares one exact committed transaction, never an arbitrary latest undo.
class VoiceComparison<T extends Object> {
  VoiceComparison({
    required this.action,
    required this.beforeDigest,
    required this.afterDigest,
  });
  final T action;
  final String beforeDigest;
  final String afterDigest;
  bool before = false;
  bool switching = false;

  Future<bool> switchTo(
    bool targetBefore, {
    required T? Function() undoHead,
    required T? Function() redoHead,
    required String Function() fingerprint,
    required Future<T?> Function() undo,
    required Future<T?> Function() redo,
    required Future<void> Function() refresh,
  }) async {
    if (switching) return false;
    final expected = before ? beforeDigest : afterDigest;
    if (!identical(before ? redoHead() : undoHead(), action) ||
        fingerprint() != expected)
      return false;
    if (before == targetBefore) return true;
    switching = true;
    before = true;
    try {
      final changed = targetBefore ? await undo() : await redo();
      if (!identical(changed, action))
        throw StateError('comparison_history_changed');
      await refresh();
      if (fingerprint() != (targetBefore ? beforeDigest : afterDigest))
        throw StateError('comparison_readback_failed');
      before = targetBefore;
      return true;
    } catch (_) {
      try {
        if (identical(redoHead(), action)) await redo();
        await refresh();
        if (identical(undoHead(), action) && fingerprint() == afterDigest)
          before = false;
      } catch (_) {}
      return false;
    } finally {
      switching = false;
    }
  }
}
