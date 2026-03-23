import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/automation_clip_overlap.dart';
import 'package:mixroom/models/models.dart';

AutomationClipSnapshot _clip({
  required String id,
  required int lane,
  required double startMs,
  required double lengthMs,
  bool muted = false,
}) {
  return AutomationClipSnapshot(
    id: id,
    targetId: 'volume',
    label: 'Volume',
    row: 0,
    lane: lane,
    startMs: startMs,
    lengthMs: lengthMs,
    muted: muted,
    points: <AutomationPoint>[
      AutomationPoint(x: 0.0, volume: 0.2),
      AutomationPoint(x: 100.0, volume: 0.8),
    ],
  );
}

void main() {
  group('activeAutomationClipAtTime', () {
    test('prefers higher lanes when clips overlap', () {
      final active = activeAutomationClipAtTime(
        <AutomationClipSnapshot>[
          _clip(id: 'lane0', lane: 0, startMs: 0, lengthMs: 600),
          _clip(id: 'lane2', lane: 2, startMs: 0, lengthMs: 600),
        ],
        250,
      );

      expect(active, isNotNull);
      expect(active!.id, 'lane2');
    });

    test('prefers later-starting clip on the same lane', () {
      final active = activeAutomationClipAtTime(
        <AutomationClipSnapshot>[
          _clip(id: 'first', lane: 0, startMs: 0, lengthMs: 700),
          _clip(id: 'later', lane: 0, startMs: 200, lengthMs: 500),
        ],
        300,
      );

      expect(active, isNotNull);
      expect(active!.id, 'later');
    });

    test('ignores muted clips', () {
      final active = activeAutomationClipAtTime(
        <AutomationClipSnapshot>[
          _clip(
              id: 'muted_top', lane: 3, startMs: 0, lengthMs: 800, muted: true),
          _clip(id: 'audible', lane: 1, startMs: 0, lengthMs: 800),
        ],
        400,
      );

      expect(active, isNotNull);
      expect(active!.id, 'audible');
    });
  });
}
