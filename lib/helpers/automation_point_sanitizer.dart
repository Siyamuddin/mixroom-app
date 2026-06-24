import 'dart:math' as math;

import 'package:mixroom/models/models.dart';

double sanitizeAutomationTimeMs(double rawMs) {
  if (!rawMs.isFinite) return 0.0;
  return math.max(0.0, rawMs).toDouble();
}

double sanitizeAutomationLengthMs(
  double rawMs, {
  double minMs = 50.0,
}) {
  final safeMin = minMs.isFinite ? math.max(0.0, minMs) : 50.0;
  if (!rawMs.isFinite) return safeMin.toDouble();
  return math.max(safeMin, rawMs).toDouble();
}

List<AutomationPoint> sanitizeAutomationPointsPreservingFutureTimes(
  List<AutomationPoint> points,
) {
  return points
      .map(
        (point) => AutomationPoint(
          x: sanitizeAutomationTimeMs(point.x),
          volume: (point.volume.isFinite ? point.volume : 0.0)
              .clamp(0.0, 1.0)
              .toDouble(),
        ),
      )
      .toList(growable: false)
    ..sort((a, b) => a.x.compareTo(b.x));
}
