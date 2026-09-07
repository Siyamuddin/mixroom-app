import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/timeline_bar_navigation.dart';

void main() {
  group('timelineMsPerBar', () {
    test('matches 4/4 at 120 BPM', () {
      expect(timelineMsPerBar(bpm: 120, beatsPerBar: 4, beatUnit: 4), 2000.0);
    });

    test('scales with BPM', () {
      expect(timelineMsPerBar(bpm: 60, beatsPerBar: 4, beatUnit: 4), 4000.0);
    });

    test('uses 6/8 bar length', () {
      expect(timelineMsPerBar(bpm: 120, beatsPerBar: 6, beatUnit: 8), 1500.0);
    });
  });

  group('timelinePreviousBarMs', () {
    test('stays at zero', () {
      expect(
        timelinePreviousBarMs(0, bpm: 120, beatsPerBar: 4, beatUnit: 4),
        0.0,
      );
    });

    test('from a bar line goes one bar back', () {
      expect(
        timelinePreviousBarMs(2000, bpm: 120, beatsPerBar: 4, beatUnit: 4),
        0.0,
      );
    });

    test('from mid-bar goes to the current bar start', () {
      expect(
        timelinePreviousBarMs(2500, bpm: 120, beatsPerBar: 4, beatUnit: 4),
        2000.0,
      );
    });

    test('treats 1ms of a bar line as on-bar', () {
      expect(
        timelinePreviousBarMs(2000.5, bpm: 120, beatsPerBar: 4, beatUnit: 4),
        0.0,
      );
    });
  });

  group('timelineNextBarMs', () {
    test('from zero goes to the next bar', () {
      expect(
        timelineNextBarMs(0, bpm: 120, beatsPerBar: 4, beatUnit: 4),
        2000.0,
      );
    });

    test('from mid-bar goes to the next bar line', () {
      expect(
        timelineNextBarMs(500, bpm: 120, beatsPerBar: 4, beatUnit: 4),
        2000.0,
      );
    });

    test('from a bar line goes one bar forward', () {
      expect(
        timelineNextBarMs(2000, bpm: 120, beatsPerBar: 4, beatUnit: 4),
        4000.0,
      );
    });
  });
}
