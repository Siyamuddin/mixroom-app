import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/piano_roll_playhead.dart';

void main() {
  test('playhead continues beyond the MIDI clip boundary', () {
    expect(visiblePianoRollPlayheadBeat(12.0), 12.0);
  });

  test('playhead remains at zero before the MIDI clip starts', () {
    expect(visiblePianoRollPlayheadBeat(-2.0), 0.0);
  });

  test('roll content extends beyond both the clip and transport', () {
    expect(
      pianoRollContentEndBeat(clipSpanBeat: 4.0, playheadBeat: 40.0),
      48.0,
    );
    expect(
      pianoRollContentEndBeat(clipSpanBeat: 44.0, playheadBeat: 2.0),
      52.0,
    );
  });
}
