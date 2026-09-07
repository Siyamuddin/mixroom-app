import 'dart:math' as math;

/// Treat times this close to a bar line as sitting on that bar.
const double kTimelineBarLineEpsilonMs = 1.0;

/// Bar length in milliseconds, matching the arrange-view grid.
double timelineMsPerBar({
  required double bpm,
  required int beatsPerBar,
  required int beatUnit,
}) {
  final double safeBpm = bpm.isFinite && bpm > 0.0 ? bpm : 120.0;
  final int safeNumerator = math.max(1, beatsPerBar);
  final int safeDenominator = math.max(1, beatUnit);
  return (60000.0 / safeBpm) * safeNumerator * 4.0 / safeDenominator;
}

/// Previous bar line from [currentMs]. Mid-bar goes to this bar's start.
double timelinePreviousBarMs(
  double currentMs, {
  required double bpm,
  required int beatsPerBar,
  required int beatUnit,
}) {
  final double barMs = timelineMsPerBar(
    bpm: bpm,
    beatsPerBar: beatsPerBar,
    beatUnit: beatUnit,
  );
  if (barMs <= 0.0) return 0.0;
  final double safeCurrent = math.max(0.0, currentMs);
  final int nearestIndex = (safeCurrent / barMs).round();
  final double nearestBarMs = nearestIndex * barMs;
  if ((safeCurrent - nearestBarMs).abs() <= kTimelineBarLineEpsilonMs) {
    return math.max(0.0, (nearestIndex - 1) * barMs);
  }
  return math.max(0.0, (safeCurrent / barMs).floor() * barMs);
}

/// Next bar line from [currentMs]. Mid-bar and on-bar both go forward.
double timelineNextBarMs(
  double currentMs, {
  required double bpm,
  required int beatsPerBar,
  required int beatUnit,
}) {
  final double barMs = timelineMsPerBar(
    bpm: bpm,
    beatsPerBar: beatsPerBar,
    beatUnit: beatUnit,
  );
  if (barMs <= 0.0) return math.max(0.0, currentMs);
  final double safeCurrent = math.max(0.0, currentMs);
  final int nearestIndex = (safeCurrent / barMs).round();
  final double nearestBarMs = nearestIndex * barMs;
  if ((safeCurrent - nearestBarMs).abs() <= kTimelineBarLineEpsilonMs) {
    return (nearestIndex + 1) * barMs;
  }
  return (safeCurrent / barMs).ceil() * barMs;
}
