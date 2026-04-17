import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/timeline_tempo_mapping.dart';
import 'package:mixroom/models/models.dart';

void main() {
  test('remaps timeline offsets by old/new BPM ratio', () {
    expect(
      remapTimelineSecondsForTempoChange(
        4.0,
        previousBpm: 120.0,
        nextBpm: 240.0,
      ),
      closeTo(2.0, 0.0001),
    );
    expect(
      remapTimelineMillisecondsForTempoChange(
        4000.0,
        previousBpm: 120.0,
        nextBpm: 60.0,
      ),
      closeTo(8000.0, 0.0001),
    );
  });

  test('remaps automation clips and their relative points', () {
    final clip = AutomationClipSnapshot(
      id: 'clip_1',
      targetId: 'volume',
      label: 'Volume',
      row: 0,
      startMs: 2000.0,
      lengthMs: 1000.0,
      muted: false,
      points: <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: 0.25),
        AutomationPoint(x: 500.0, volume: 0.75),
        AutomationPoint(x: 1000.0, volume: 1.0),
      ],
    );

    final remapped = remapAutomationClipForTempoChange(
      clip,
      previousBpm: 120.0,
      nextBpm: 90.0,
    );

    expect(remapped.startMs, closeTo(2666.6667, 0.001));
    expect(remapped.lengthMs, closeTo(1333.3333, 0.001));
    expect(remapped.points[1].x, closeTo(666.6667, 0.001));
    expect(remapped.points[1].volume, closeTo(0.75, 0.0001));
  });
}
