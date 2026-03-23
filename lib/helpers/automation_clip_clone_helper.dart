import 'package:mixroom/models/models.dart';

class AutomationClipClonePlan {
  const AutomationClipClonePlan({
    required this.nextClips,
    required this.updatedClipboardClip,
    required this.clonedClip,
  });

  final List<AutomationClipSnapshot> nextClips;
  final AutomationClipSnapshot updatedClipboardClip;
  final AutomationClipSnapshot clonedClip;
}

AutomationClipClonePlan buildAutomationClipClonePlan({
  required List<AutomationClipSnapshot> existingClips,
  required AutomationClipSnapshot clipboardClip,
  required int row,
  required String targetId,
  required double startMs,
  required double maxDurationMs,
  required String Function() createClipId,
  required String Function() createPatternId,
}) {
  final next = existingClips.map((clip) => clip.copyWith()).toList();
  String clonedPatternId = clipboardClip.patternId.trim();
  final sourceIndex = next.indexWhere((clip) => clip.id == clipboardClip.id);
  if (sourceIndex >= 0) {
    final sourcePatternId = next[sourceIndex].patternId.trim();
    if (sourcePatternId.isNotEmpty) {
      clonedPatternId = sourcePatternId;
    } else if (clonedPatternId.isEmpty) {
      clonedPatternId = createPatternId();
      next[sourceIndex] =
          next[sourceIndex].copyWith(patternId: clonedPatternId);
    }
  }

  final updatedClipboardClip = clonedPatternId.isEmpty
      ? clipboardClip.copyWith()
      : clipboardClip.copyWith(patternId: clonedPatternId);
  final clonedClip = updatedClipboardClip.copyWith(
    id: createClipId(),
    row: row,
    targetId: targetId,
    startMs: startMs.clamp(0.0, maxDurationMs).toDouble(),
  );
  next.add(clonedClip);
  return AutomationClipClonePlan(
    nextClips: next,
    updatedClipboardClip: updatedClipboardClip,
    clonedClip: clonedClip,
  );
}
