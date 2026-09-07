import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final appleEngine = File(
    'juce_audio_engine/ios/Classes/JuceEngine.h',
  ).readAsStringSync();
  final androidEngine = File(
    'juce_audio_engine/android/src/main/cpp/JuceEngine.h',
  ).readAsStringSync();
  final dormantAndroidParser = File(
    'juce_audio_engine/android/src/main/cpp/TimelineMidiClipProcessor.h',
  ).readAsStringSync();
  final pitchSemantics = File(
    'juce_audio_engine/native/SampledPitchSemantics.h',
  ).readAsStringSync();

  test('Apple and Android preserve SFZ roots through shared semantics', () {
    for (final engine in <String>[appleEngine, androidEngine]) {
      expect(engine, contains('SampledPitchSemantics.h'));
      expect(
        engine,
        contains(
          'mixroom::effectiveSampleKeyCenter(\n'
          '            source.keyCenter, preset.rootNote)',
        ),
      );
      expect(
        engine,
        isNot(
          contains(
            'region.keyCenter = juce::jlimit(0, 127, '
            '(int)std::round(preset.rootNote))',
          ),
        ),
      );
    }

    expect(pitchSemantics, contains('constexpr int neutralRootNote = 60'));
    expect(
      pitchSemantics,
      contains('sourceKeyCenter + roundedPresetRootNote - neutralRootNote'),
    );
    expect(
      pitchSemantics,
      contains('effectiveSampleKeyCenterForRoundedRoot(21, 60) == 21'),
    );
    expect(
      pitchSemantics,
      contains('effectiveSampleKeyCenterForRoundedRoot(60, 62) == 62'),
    );
  });

  test('all native SFZ parsers apply key as a bounded single-note region', () {
    for (final parser in <String>[
      appleEngine,
      androidEngine,
      dormantAndroidParser,
    ]) {
      expect(
        parser,
        contains('r, "key", std::numeric_limits<double>::quiet_NaN()'),
      );
      expect(
        parser,
        contains('const double defaultLoKey = std::isfinite(key) ? key : 0.0'),
      );
      expect(
        parser,
        contains(
          'const double defaultHiKey = std::isfinite(key) ? key : 127.0',
        ),
      );
      expect(parser, contains('readSfzNumeric(r, "lokey", defaultLoKey)'));
      expect(parser, contains('readSfzNumeric(r, "hikey", defaultHiKey)'));
      expect(parser, contains('regionDef.loKey,\n                127'));
      expect(parser, contains('keyCenter = std::isfinite(key)'));
    }
  });
}
