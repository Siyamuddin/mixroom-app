import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/midi_pitch_ranges.dart';

void main() {
  test('compacts exact pitches into stable inclusive ranges', () {
    expect(
      compactMidiPitchRanges(<int>{40, 41, 42, 44, 46, 47, 200, -1}),
      <Map<String, int>>[
        <String, int>{'low': 40, 'high': 42},
        <String, int>{'low': 44, 'high': 44},
        <String, int>{'low': 46, 'high': 47},
      ],
    );
  });

  test('normalizes ranges and rejects overlap or invalid MIDI bounds', () {
    expect(
      normalizeMidiPitchRanges(<Map<String, int>>[
        <String, int>{'low': 44, 'high': 44},
        <String, int>{'low': 40, 'high': 42},
        <String, int>{'low': 43, 'high': 43},
      ]),
      <Map<String, int>>[
        <String, int>{'low': 40, 'high': 44},
      ],
    );
    expect(
      () => normalizeMidiPitchRanges(<Map<String, int>>[
        <String, int>{'low': 40, 'high': 42},
        <String, int>{'low': 42, 'high': 43},
      ]),
      throwsFormatException,
    );
    expect(
      () => normalizeMidiPitchRanges(<Map<String, int>>[
        <String, int>{'low': -1, 'high': 43},
      ]),
      throwsFormatException,
    );
  });

  test('checks and formats sparse ranges', () {
    final ranges = compactMidiPitchRanges(<int>{36, 38, 39, 42});
    expect(formatMidiPitchRanges(ranges), '36,38-39,42');
    expect(midiPitchRangesContain(ranges, 38), isTrue);
    expect(midiPitchRangesContain(ranges, 40), isFalse);
  });
}
