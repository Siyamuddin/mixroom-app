import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const nativeEffectHeaders = <String>[
    'juce_audio_engine/ios/Classes/NativeEffects.h',
    'juce_audio_engine/android/src/main/cpp/NativeEffects.h',
  ];

  String pitchShiftModule(String source) {
    final start = source.indexOf('class PitchShiftModule');
    final end = source.indexOf('class PitchShiftAudioProcessor', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    return source.substring(start, end);
  }

  String methodBody(String source, String signature, String nextSignature) {
    final start = source.indexOf(signature);
    final end = source.indexOf(nextSignature, start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    return source.substring(start, end);
  }

  int requiredRingSize(double sampleRate) {
    final minDelay = (sampleRate * 0.02).round().clamp(512, 1024).toInt();
    return minDelay + 2;
  }

  test('pitch shift ring follows route sample rate exactly', () {
    expect(requiredRingSize(44100), 884);
    expect(requiredRingSize(48000), 962);
    expect(requiredRingSize(44100), 884);

    for (final path in nativeEffectHeaders) {
      final module = pitchShiftModule(File(path).readAsStringSync());
      expect(module, contains('requiredRingSizeForSampleRate'));
      expect(module, contains('(int)std::lround(rate * 0.02)'));
      expect(module, contains('ringSize != requiredRingSize'));
      expect(module, contains('ring.assign((size_t)ringSize, 0.0f)'));
    }
  });

  test('prepare owns allocation and realtime processing only validates', () {
    for (final path in nativeEffectHeaders) {
      final module = pitchShiftModule(File(path).readAsStringSync());
      final prepare = methodBody(
        module,
        'void prepare(double inputSampleRate, int maxBlockSize)',
        'void reset()',
      );
      final process = methodBody(
        module,
        'void process(juce::AudioBuffer<float> &buffer)',
        'private:',
      );

      expect(prepare, contains('prepareRingBuffersForCurrentSampleRate()'));
      expect(prepare, isNot(contains('mixroomEffectScratchAvailable')));
      expect(process, contains('isPreparedForCurrentSampleRate()'));
      expect(process.indexOf('isPreparedForCurrentSampleRate()'),
          lessThan(process.indexOf('getWritePointer')));
      expect(process, isNot(contains('.assign(')));
      expect(process, isNot(contains('.resize(')));
      expect(process, isNot(contains('setSize(')));
      expect(process, isNot(contains('new ')));
      expect(process, isNot(contains('malloc')));
      expect(process, isNot(contains('mixroomEffectScratchAvailable')));
    }
  });
}
