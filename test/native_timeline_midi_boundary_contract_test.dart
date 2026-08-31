import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

double _admissionSourceStart({
  required double blockStart,
  required double blockEnd,
  required double clipStart,
  required double roundedSourceStart,
  required double inFileOffset,
}) {
  final entersClip = blockStart <= clipStart && blockEnd > clipStart;
  return entersClip ? inFileOffset : roundedSourceStart;
}

void main() {
  final sharedBoundary = File(
    'juce_audio_engine/native/TimelineMidiBoundary.h',
  ).readAsStringSync();
  final appleHeader = File(
    'juce_audio_engine/ios/Classes/JuceEngine.h',
  ).readAsStringSync();
  final appleEngine = File(
    'juce_audio_engine/ios/Classes/JuceEngine.cpp',
  ).readAsStringSync();
  final androidHeader = File(
    'juce_audio_engine/android/src/main/cpp/JuceEngine.h',
  ).readAsStringSync();

  test('clip-entry admission removes only the sample-rounding gap', () {
    expect(
      _admissionSourceStart(
        blockStart: 1.99,
        blockEnd: 2.01,
        clipStart: 2.0,
        roundedSourceStart: 1 / 44100,
        inFileOffset: 0.0,
      ),
      0.0,
    );
    expect(
      _admissionSourceStart(
        blockStart: 2.001,
        blockEnd: 2.011,
        clipStart: 2.0,
        roundedSourceStart: 0.001,
        inFileOffset: 0.0,
      ),
      0.001,
    );
    expect(
      _admissionSourceStart(
        blockStart: 1.99,
        blockEnd: 2.01,
        clipStart: 2.0,
        roundedSourceStart: 0.75001,
        inFileOffset: 0.75,
      ),
      0.75,
    );
  });

  test('every active native MIDI renderer uses the shared boundary rule', () {
    expect(sharedBoundary, contains('timelineMidiBlockEntersClip'));
    expect(sharedBoundary, contains('timelineMidiAdmissionSourceStartSec'));
    expect(sharedBoundary, contains('Starting inside a clip must not chase'));
    expect(sharedBoundary, contains('first block of a trimmed clip'));

    for (final header in <String>[appleHeader, androidHeader]) {
      expect(header, contains('TimelineMidiBoundary.h'));
      expect(
        'timelineMidiAdmissionSourceStartSec'.allMatches(header),
        hasLength(1),
      );
    }

    expect(
      'timelineMidiAdmissionSourceStartSec'.allMatches(appleEngine),
      hasLength(1),
    );
  });
}
