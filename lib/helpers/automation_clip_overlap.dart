import 'package:mixroom/models/models.dart';

AutomationClipSnapshot? activeAutomationClipAtTime(
  List<AutomationClipSnapshot> clips,
  double timeMs,
) {
  AutomationClipSnapshot? active;
  for (final clip in clips) {
    if (clip.muted) continue;
    final start = clip.startMs;
    final end = clip.startMs + clip.lengthMs;
    if (timeMs + 1e-6 < start || timeMs - 1e-6 > end) continue;
    if (_automationClipWins(clip, active)) {
      active = clip;
    }
  }
  return active;
}

bool _automationClipWins(
  AutomationClipSnapshot candidate,
  AutomationClipSnapshot? current,
) {
  if (current == null) return true;
  final candidateLane = candidate.lane;
  final currentLane = current.lane;
  if (candidateLane != currentLane) {
    return candidateLane > currentLane;
  }
  final candidateStart = candidate.startMs;
  final currentStart = current.startMs;
  if ((candidateStart - currentStart).abs() > 1e-6) {
    return candidateStart > currentStart;
  }
  if (candidate.row != current.row) {
    return candidate.row > current.row;
  }
  return candidate.id.compareTo(current.id) > 0;
}
