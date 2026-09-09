/// Mirrored by common/midi_boundary.py and checked with shared fixtures.
const aiV3MidiBoundaryPolicy = 'extend_1ms_v1';

double aiV3ExtendedMidiLength({
  required double original,
  required double current,
  required double end,
  required double bpm,
}) {
  if ([original, current, end, bpm].any((v) => !v.isFinite || v <= 0) ||
      end <= current) return current;
  final scale = 60000000.0 / bpm;
  final values = [original * scale, current * scale, end * scale];
  if (values.any((v) => !v.isFinite || v > 9007199254740991)) return current;
  final baseline = (values[0] + 0.5).floor();
  final required = values[2].ceil();
  if (required - baseline > 1000) return current;
  final result = required / scale;
  return result > current ? result : current;
}

bool aiV3MidiBoundaryExecutionMatches({
  required double original,
  required double expected,
  required double current,
  required double end,
  required double finalLength,
  required double bpm,
  required double currentBpm,
}) {
  if ([original, expected, current, end, finalLength, bpm, currentBpm]
      .any((v) => !v.isFinite || v <= 0) || bpm != currentBpm) return false;
  final scale = 60000000.0 / bpm;
  if (((expected - current) * scale).abs() > 1) return false;
  final normalized = aiV3ExtendedMidiLength(
    original: original, current: expected, end: end, bpm: bpm);
  return normalized > expected &&
      ((normalized - finalLength) * scale).abs() < 0.000001;
}
