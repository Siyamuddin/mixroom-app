class AiV3TransactionSuccess<T, O> {
  const AiV3TransactionSuccess({
    required this.captured,
    required this.observed,
  });

  final List<T> captured;
  final List<O> observed;
}

class AiV3TransactionFailure<O> implements Exception {
  const AiV3TransactionFailure({
    required this.cause,
    required this.observed,
    required this.rollbackIncomplete,
  });

  final Object cause;
  final List<O> observed;
  final bool rollbackIncomplete;

  @override
  String toString() =>
      'AiV3TransactionFailure(rollbackIncomplete=$rollbackIncomplete, cause=${cause.runtimeType})';
}

/// Marks a failure whose inner execution layer could not completely restore
/// state. The transaction coordinator preserves this fact even when no action
/// list was returned to it.
abstract interface class AiV3RollbackIncompleteFailure {}

/// Runs an already-prepared local V3 bundle as one transaction.
///
/// [executeAndCapture] owns rollback for failures raised before it returns.
/// Once it returns, this coordinator owns reverse-order rollback for readback,
/// verification, and undo-history commit failures.
class AiV3LocalTransaction<T, O> {
  const AiV3LocalTransaction();

  Future<AiV3TransactionSuccess<T, O>> run({
    required Future<List<T>> Function() executeAndCapture,
    required Future<bool> Function() verify,
    required Future<List<O>> Function() observe,
    required Future<void> Function(T action) rollback,
    required Future<void> Function(List<T> actions) commit,
  }) async {
    var captured = <T>[];
    var observed = <O>[];
    try {
      captured = await executeAndCapture();
      // An exact state-setting command may already be satisfied. In that
      // case the editor correctly captures no undo action, but factual
      // readback can still prove success. Requiring a mutation here would
      // turn harmless idempotent requests into false execution failures.
      final verified = await verify();
      observed = await observe();
      if (!verified) throw StateError('v3_readback_mismatch');
      if (captured.isNotEmpty) {
        await commit(List<T>.unmodifiable(captured));
      }
      return AiV3TransactionSuccess<T, O>(
        captured: List<T>.unmodifiable(captured),
        observed: List<O>.unmodifiable(observed),
      );
    } catch (error) {
      var rollbackIncomplete = error is AiV3RollbackIncompleteFailure;
      for (final action in captured.reversed) {
        try {
          await rollback(action);
        } catch (_) {
          rollbackIncomplete = true;
        }
      }
      throw AiV3TransactionFailure<O>(
        cause: error,
        observed: List<O>.unmodifiable(observed),
        rollbackIncomplete: rollbackIncomplete,
      );
    }
  }
}
