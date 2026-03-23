import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/automation_clip_clone_helper.dart';
import 'package:mixroom/models/models.dart';

void main() {
  AutomationClipSnapshot clip({
    required String id,
    required String patternId,
    double startMs = 0,
  }) {
    return AutomationClipSnapshot(
      id: id,
      targetId: 'volume',
      label: 'Volume',
      patternId: patternId,
      row: 0,
      lane: 0,
      startMs: startMs,
      lengthMs: 1000,
      muted: false,
      points: <AutomationPoint>[
        AutomationPoint(x: 0, volume: 0.2),
        AutomationPoint(x: 1000, volume: 0.8),
      ],
    );
  }

  test('first clone creates a linked pattern and updates source clip', () {
    final source = clip(id: 'source', patternId: '');

    final plan = buildAutomationClipClonePlan(
      existingClips: <AutomationClipSnapshot>[source],
      clipboardClip: source,
      row: 0,
      targetId: 'volume',
      startMs: 1200,
      maxDurationMs: 4000,
      createClipId: () => 'clone_1',
      createPatternId: () => 'pattern_1',
    );

    expect(plan.nextClips, hasLength(2));
    expect(plan.nextClips[0].patternId, 'pattern_1');
    expect(plan.clonedClip.patternId, 'pattern_1');
    expect(plan.updatedClipboardClip.patternId, 'pattern_1');
    expect(plan.clonedClip.id, 'clone_1');
    expect(plan.clonedClip.startMs, 1200);
  });

  test('repeated clone reuses established linked pattern', () {
    final source = clip(id: 'source', patternId: 'pattern_existing');
    final clipboard = clip(id: 'source', patternId: 'pattern_existing');

    final plan = buildAutomationClipClonePlan(
      existingClips: <AutomationClipSnapshot>[
        source,
        clip(id: 'clone_1', patternId: 'pattern_existing', startMs: 1200),
      ],
      clipboardClip: clipboard,
      row: 0,
      targetId: 'volume',
      startMs: 2400,
      maxDurationMs: 4000,
      createClipId: () => 'clone_2',
      createPatternId: () => 'pattern_new_should_not_be_used',
    );

    expect(plan.nextClips, hasLength(3));
    expect(plan.nextClips[0].patternId, 'pattern_existing');
    expect(plan.nextClips[1].patternId, 'pattern_existing');
    expect(plan.nextClips[2].patternId, 'pattern_existing');
    expect(plan.updatedClipboardClip.patternId, 'pattern_existing');
  });

  test('clone start is clamped to timeline duration', () {
    final source = clip(id: 'source', patternId: 'pattern_existing');

    final plan = buildAutomationClipClonePlan(
      existingClips: <AutomationClipSnapshot>[source],
      clipboardClip: source,
      row: 0,
      targetId: 'volume',
      startMs: 9000,
      maxDurationMs: 4000,
      createClipId: () => 'clone_1',
      createPatternId: () => 'pattern_new',
    );

    expect(plan.clonedClip.startMs, 4000);
  });
}
