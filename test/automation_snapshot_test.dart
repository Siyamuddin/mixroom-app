import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/models/models.dart';

void main() {
  group('AutomationClipSnapshot', () {
    test('round trips arbitrary automation targets and deep copies points', () {
      final sourcePoints = <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: 0.25),
        AutomationPoint(x: 480.0, volume: 0.9),
      ];
      final clip = AutomationClipSnapshot(
        id: 'clip_master_threshold',
        targetId:
            'masterfxid:${Uri.encodeComponent('Master Comp#0')}:${Uri.encodeComponent('threshold')}',
        label: 'Threshold',
        patternId: 'pattern_shared_threshold',
        row: 3,
        lane: 2,
        startMs: 1200.0,
        lengthMs: 480.0,
        muted: true,
        points: sourcePoints,
      );

      final clone = clip.copyWith();
      sourcePoints.first.volume = 0.75;
      clip.points.last.volume = 0.1;

      expect(clone.points.first.volume, closeTo(0.25, 0.001));
      expect(clone.points.last.volume, closeTo(0.9, 0.001));

      final restored = AutomationClipSnapshot.fromJson(clip.toJson());
      expect(restored.id, clip.id);
      expect(restored.targetId, clip.targetId);
      expect(restored.label, clip.label);
      expect(restored.patternId, clip.patternId);
      expect(restored.row, clip.row);
      expect(restored.lane, clip.lane);
      expect(restored.startMs, closeTo(1200.0, 0.001));
      expect(restored.lengthMs, closeTo(480.0, 0.001));
      expect(restored.muted, isTrue);
      expect(restored.points, hasLength(2));
      expect(restored.points.first.x, closeTo(0.0, 0.001));
      expect(restored.points.first.volume, closeTo(0.75, 0.001));
      expect(restored.points.last.volume, closeTo(0.1, 0.001));
    });

    test('fromJson applies legacy defaults for missing clip metadata', () {
      final restored = AutomationClipSnapshot.fromJson(<String, dynamic>{
        'startMs': 123.4,
        'points': <Map<String, dynamic>>[
          <String, dynamic>{'x': 0, 'volume': 0.6},
        ],
      });

      expect(restored.id, 'clip_volume_123');
      expect(restored.targetId, 'volume');
      expect(restored.label, isEmpty);
      expect(restored.patternId, isEmpty);
      expect(restored.row, 0);
      expect(restored.lane, 0);
      expect(restored.startMs, closeTo(123.4, 0.001));
      expect(restored.lengthMs, closeTo(1000.0, 0.001));
      expect(restored.muted, isFalse);
      expect(restored.points, hasLength(1));
      expect(restored.points.single.volume, closeTo(0.6, 0.001));
    });
  });

  group('RowStateSnapshot', () {
    test('round trips clip-first automation state for save and load', () {
      final snapshot = RowStateSnapshot(
        row: 2,
        gain: 1.25,
        pan: 0.35,
        volumeAutomation: <AutomationPoint>[
          AutomationPoint(x: 0.0, volume: 1.0),
          AutomationPoint(x: 1000.0, volume: 0.85),
        ],
        automationLanes: <AutomationLaneSnapshot>[
          AutomationLaneSnapshot(
            targetId: 'volume',
            label: 'Volume',
            effectIndex: -1,
            paramId: 'volume',
            type: 'float',
            min: 0.0,
            max: 1.0,
            points: <AutomationPoint>[
              AutomationPoint(x: 0.0, volume: 1.0),
            ],
          ),
        ],
        automationClips: <AutomationClipSnapshot>[
          AutomationClipSnapshot(
            id: 'clip_gain',
            targetId: 'master:gain',
            label: 'Master Gain',
            patternId: 'pattern_gain',
            row: 2,
            startMs: 240.0,
            lengthMs: 360.0,
            muted: false,
            points: <AutomationPoint>[
              AutomationPoint(x: 0.0, volume: 0.4),
              AutomationPoint(x: 360.0, volume: 0.7),
            ],
          ),
          AutomationClipSnapshot(
            id: 'clip_mix',
            targetId:
                'fxid:${Uri.encodeComponent('Group Bus Comp#1')}:${Uri.encodeComponent('mix')}',
            label: 'Mix',
            row: 2,
            lane: 1,
            startMs: 800.0,
            lengthMs: 420.0,
            muted: true,
            points: <AutomationPoint>[
              AutomationPoint(x: 0.0, volume: 0.2),
            ],
          ),
        ],
        selectedAutomationTargetId: 'master:gain',
      );

      final restored = RowStateSnapshot.fromJson(snapshot.toJson());

      expect(restored.row, snapshot.row);
      expect(restored.gain, closeTo(snapshot.gain, 0.001));
      expect(restored.pan, closeTo(snapshot.pan, 0.001));
      expect(restored.volumeAutomation, hasLength(2));
      expect(restored.automationLanes, hasLength(1));
      expect(restored.automationClips, hasLength(2));
      expect(restored.automationClips.first.targetId, 'master:gain');
      expect(restored.automationClips.first.patternId, 'pattern_gain');
      expect(restored.automationClips.last.targetId,
          snapshot.automationClips.last.targetId);
      expect(restored.automationClips.last.lane, 1);
      expect(restored.automationClips.last.muted, isTrue);
      expect(restored.selectedAutomationTargetId, 'master:gain');
    });
  });
}
