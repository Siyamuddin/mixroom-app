import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/basic_pitch_transcriber.dart';

void main() {
  group('BasicPitchTranscriber.decodeOutputToNoteEvents', () {
    test('extracts a simple monophonic note from model activations', () {
      const frames = 172;
      const noteBins = 88;
      const contourBins = 264;
      const pitchMidi = 60;
      final pitchIndex = pitchMidi - 21;

      final note = List<Float32List>.generate(
        frames,
        (_) => Float32List(noteBins),
        growable: false,
      );
      final onset = List<Float32List>.generate(
        frames,
        (_) => Float32List(noteBins),
        growable: false,
      );
      final contour = List<Float32List>.generate(
        frames,
        (_) => Float32List(contourBins),
        growable: false,
      );

      for (int t = 20; t <= 52; t++) {
        note[t][pitchIndex] = 0.92;
        contour[t][pitchIndex * 3 + 1] = 0.85;
      }
      onset[20][pitchIndex] = 0.98;
      onset[19][pitchIndex] = 0.1;
      onset[21][pitchIndex] = 0.2;

      final events = BasicPitchTranscriber.instance.decodeOutputToNoteEvents(
        BasicPitchModelOutput(
          note: note,
          onset: onset,
          contour: contour,
        ),
      );

      expect(events, isNotEmpty);
      expect(events.first.pitchMidi, pitchMidi);
      expect(events.first.endSeconds, greaterThan(events.first.startSeconds));
      expect(events.first.amplitude, greaterThan(0.5));
    });
  });
}
