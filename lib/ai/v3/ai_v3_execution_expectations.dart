Map<String, dynamic> aiV3RowInstrumentExpectationForFinalState(
  Iterable<Map<String, dynamic>> expectations,
  Map<String, dynamic> runtimeExpectation,
) {
  final reconciled = Map<String, dynamic>.from(runtimeExpectation);
  final rowId = runtimeExpectation['row_id'];
  if (rowId is! int) return reconciled;

  for (final expectation in expectations.toList(growable: false).reversed) {
    if (expectation['kind'] != 'row_name' || expectation['row_id'] != rowId) {
      continue;
    }
    final finalName = expectation['value']?.toString();
    if (finalName != null) reconciled['row_name'] = finalName;
    break;
  }
  return reconciled;
}

/// Returns whether an expectation belongs to the stable row being deleted.
///
/// A generated row has only a predicted index until its producer executes.
/// That index can overlap an existing row deleted later in the same plan, so
/// it must not be treated as stable row identity.
bool aiV3ExpectationMatchesDeletedStableRow(
  Map<String, dynamic> expectation, {
  required int rowId,
  required int rowIndex,
}) {
  if (expectation['destination_row_ref'] is Map) return false;
  return expectation['row_id'] == rowId ||
      (expectation['row_id'] is! int && expectation['row'] == rowIndex);
}

List<Map<String, dynamic>> aiV3EffectObservationWithNativeFallback({
  required List<Map<String, dynamic>> snapshotEffects,
  required Iterable<String> nativeEffectNames,
  required String requiredNeedle,
}) {
  if (snapshotEffects.isNotEmpty) {
    return snapshotEffects
        .map((effect) => Map<String, dynamic>.from(effect))
        .toList(growable: false);
  }

  final needle = requiredNeedle.trim().toLowerCase();
  final matches = nativeEffectNames
      .where((name) => name.toLowerCase().contains(needle))
      .toList(growable: false);
  if (needle.isEmpty || matches.isEmpty) {
    throw StateError('v3_effect_observation_missing');
  }
  return matches
      .map((name) => <String, dynamic>{'display_name': name})
      .toList(growable: false);
}
