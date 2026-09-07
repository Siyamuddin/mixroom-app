import 'dart:math' as math;

double visiblePianoRollPlayheadBeat(double clipRelativeBeat) {
  if (!clipRelativeBeat.isFinite) return 0.0;
  return math.max(0.0, clipRelativeBeat);
}

double pianoRollContentEndBeat({
  required double clipSpanBeat,
  required double playheadBeat,
  double minimumBeat = 32.0,
  double trailingBeat = 8.0,
}) {
  final safeClipSpan = clipSpanBeat.isFinite
      ? math.max(0.0, clipSpanBeat)
      : 0.0;
  final safePlayhead = visiblePianoRollPlayheadBeat(playheadBeat);
  return math.max(
    minimumBeat,
    math.max(safeClipSpan + trailingBeat, safePlayhead + trailingBeat),
  );
}
