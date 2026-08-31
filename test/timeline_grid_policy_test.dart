import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/timeline_grid_policy.dart';

void main() {
  group('TimelineGridPolicy', () {
    test('selects adaptive divisions at the 30 pixel thresholds', () {
      int resolve(double pixelsPerBar) =>
          TimelineGridPolicy.resolveDivisionsPerBar(
            mode: TimelineGridMode.adaptive,
            fixedDivisionsPerBar: 4,
            pixelsPerBar: pixelsPerBar,
          );

      expect(resolve(239.9), 4);
      expect(resolve(240.0), 8);
      expect(resolve(479.9), 8);
      expect(resolve(480.0), 16);
      expect(resolve(959.9), 16);
      expect(resolve(960.0), 32);
      expect(resolve(100000.0), 32);
    });

    test('fixed mode preserves every positive divisions-per-bar value', () {
      for (final divisions in <int>[1, 2, 3, 4, 5, 6, 7, 8, 16, 32]) {
        expect(
          TimelineGridPolicy.resolveDivisionsPerBar(
            mode: TimelineGridMode.fixed,
            fixedDivisionsPerBar: divisions,
            pixelsPerBar: 100000.0,
          ),
          divisions,
        );
      }
    });

    test('invalid scale and fixed values fall back safely', () {
      for (final pixelsPerBar in <double>[0.0, -1.0, double.nan]) {
        expect(
          TimelineGridPolicy.resolveDivisionsPerBar(
            mode: TimelineGridMode.adaptive,
            fixedDivisionsPerBar: 16,
            pixelsPerBar: pixelsPerBar,
          ),
          TimelineGridPolicy.defaultDivisionsPerBar,
        );
      }
      expect(
        TimelineGridPolicy.resolveDivisionsPerBar(
          mode: TimelineGridMode.fixed,
          fixedDivisionsPerBar: 0,
          pixelsPerBar: 1000.0,
        ),
        TimelineGridPolicy.defaultDivisionsPerBar,
      );
    });

    test('arrangement pixel scale follows tempo and meter', () {
      expect(
        TimelineGridPolicy.arrangementPixelsPerBar(
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          pixelsPerMs: 0.1,
        ),
        closeTo(200.0, 0.0001),
      );
      expect(
        TimelineGridPolicy.arrangementPixelsPerBar(
          bpm: 60,
          beatsPerBar: 3,
          beatUnit: 4,
          pixelsPerMs: 0.1,
        ),
        closeTo(300.0, 0.0001),
      );
      expect(
        TimelineGridPolicy.arrangementPixelsPerBar(
          bpm: 120,
          beatsPerBar: 6,
          beatUnit: 8,
          pixelsPerMs: 0.1,
        ),
        closeTo(150.0, 0.0001),
      );
    });

    test('piano-roll pixel scale uses its own zoom', () {
      expect(
        TimelineGridPolicy.pianoRollPixelsPerBar(
          beatsPerBar: 4,
          beatUnit: 4,
          pixelsPerBeat: 56,
        ),
        224,
      );
      expect(
        TimelineGridPolicy.pianoRollPixelsPerBar(
          beatsPerBar: 4,
          beatUnit: 4,
          pixelsPerBeat: 120,
        ),
        480,
      );
    });
  });
}
