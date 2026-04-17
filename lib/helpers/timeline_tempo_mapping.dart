import 'dart:math' as math;

import 'package:mixroom/models/models.dart';

double timelineTempoScale({
  required double previousBpm,
  required double nextBpm,
}) {
  final safePrevious =
      previousBpm.isFinite && previousBpm > 0.0 ? previousBpm : 120.0;
  final safeNext = nextBpm.isFinite && nextBpm > 0.0 ? nextBpm : safePrevious;
  return safePrevious / safeNext;
}

double remapTimelineMillisecondsForTempoChange(
  double milliseconds, {
  required double previousBpm,
  required double nextBpm,
}) {
  final scale = timelineTempoScale(
    previousBpm: previousBpm,
    nextBpm: nextBpm,
  );
  return math.max(0.0, milliseconds * scale);
}

double remapTimelineSecondsForTempoChange(
  double seconds, {
  required double previousBpm,
  required double nextBpm,
}) {
  final scale = timelineTempoScale(
    previousBpm: previousBpm,
    nextBpm: nextBpm,
  );
  return math.max(0.0, seconds * scale);
}

List<AutomationPoint> remapAutomationPointsForTempoChange(
  List<AutomationPoint> points, {
  required double previousBpm,
  required double nextBpm,
}) {
  return points
      .map(
        (point) => AutomationPoint(
          x: remapTimelineMillisecondsForTempoChange(
            point.x,
            previousBpm: previousBpm,
            nextBpm: nextBpm,
          ),
          volume: point.volume,
        ),
      )
      .toList(growable: false);
}

AutomationClipSnapshot remapAutomationClipForTempoChange(
  AutomationClipSnapshot clip, {
  required double previousBpm,
  required double nextBpm,
}) {
  return clip.copyWith(
    startMs: remapTimelineMillisecondsForTempoChange(
      clip.startMs,
      previousBpm: previousBpm,
      nextBpm: nextBpm,
    ),
    lengthMs: remapTimelineMillisecondsForTempoChange(
      clip.lengthMs,
      previousBpm: previousBpm,
      nextBpm: nextBpm,
    ),
    points: remapAutomationPointsForTempoChange(
      clip.points,
      previousBpm: previousBpm,
      nextBpm: nextBpm,
    ),
  );
}
