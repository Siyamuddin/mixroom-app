import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String appleEngine;
  late String androidEngine;

  setUpAll(() {
    appleEngine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    androidEngine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.h',
    ).readAsStringSync();
  });

  test(
    'MIDI scratch capacity follows each clip instead of the global ceiling',
    () {
      for (final source in <String>[appleEngine, androidEngine]) {
        expect(
          source,
          isNot(contains('blockNoteIndices.reserve(kMaxTimelineMidiNotes)')),
        );
        expect(
          source,
          isNot(contains('blockNotePitches.reserve(kMaxTimelineMidiNotes)')),
        );
        expect(
          source,
          isNot(
            contains('blockNoteEndSourceSecs.reserve(kMaxTimelineMidiNotes)'),
          ),
        );
        expect(
          source,
          isNot(contains('timelineRegions.reserve(kMaxTimelineMidiNotes)')),
        );
        expect(
          source,
          isNot(contains('blockNotes.reserve(kMaxTimelineMidiNotes)')),
        );

        const proportionalReservation =
            'const auto realtimeNoteCapacity = next->renderNotes.size();\n'
            '        blockNoteIndices.reserve(realtimeNoteCapacity);\n'
            '        blockNotePitches.reserve(realtimeNoteCapacity);\n'
            '        blockNoteEndSourceSecs.reserve(realtimeNoteCapacity);\n'
            '        timelineRegions.reserve(realtimeNoteCapacity);';
        expect(source, contains(proportionalReservation));

        final reservation = source.indexOf(proportionalReservation);
        final publication = source.indexOf(
          'std::atomic_exchange_explicit(\n'
          '            &publishedState,',
          reservation,
        );
        expect(reservation, greaterThanOrEqualTo(0));
        expect(publication, greaterThan(reservation));
      }
    },
  );

  test('Apple and Android use the same proportional reservation block', () {
    const start = 'const auto realtimeNoteCapacity';
    const end = 'next->instrumentId = instrumentId;';

    String reservationBlock(String source) {
      final startIndex = source.indexOf(start);
      final endIndex = source.indexOf(end, startIndex);
      expect(startIndex, greaterThanOrEqualTo(0));
      expect(endIndex, greaterThan(startIndex));
      return source.substring(startIndex, endIndex);
    }

    expect(reservationBlock(appleEngine), reservationBlock(androidEngine));
  });
}
