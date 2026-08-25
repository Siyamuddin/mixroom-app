import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _delayClass(String source) {
  final start = source.indexOf('class Delay\n');
  final end = source.indexOf('class DelayAudioProcessor', start);
  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

String _prepareBody(String delayClass) {
  final start = delayClass.indexOf(
    'void prepare(double inputSampleRate, int maxBlockSize)',
  );
  final end = delayClass.indexOf(
    'void process(juce::AudioBuffer<float> &inputBuffer)',
    start,
  );
  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  return delayClass.substring(start, end);
}

void main() {
  const nativeEffectsPaths = <String>[
    'juce_audio_engine/ios/Classes/NativeEffects.h',
    'juce_audio_engine/android/src/main/cpp/NativeEffects.h',
  ];

  for (final path in nativeEffectsPaths) {
    test('Delay resets its circular cursor after route reprepare: $path', () {
      final source = File(path).readAsStringSync();
      final prepare = _prepareBody(_delayClass(source));
      final resize = prepare.indexOf('delayBuffer.setSize(');
      final cursorReset = prepare.indexOf('writePosition = 0;', resize);

      expect(resize, greaterThanOrEqualTo(0));
      expect(cursorReset, greaterThan(resize));
    });
  }

  test('shared iOS/macOS Delay clears the prior callback shape', () {
    final source = File(
      'juce_audio_engine/ios/Classes/NativeEffects.h',
    ).readAsStringSync();
    final prepare = _prepareBody(_delayClass(source));
    final resize = prepare.indexOf('delayBuffer.setSize(');
    final blockReset = prepare.indexOf('currentBlockSize = 0;', resize);

    expect(resize, greaterThanOrEqualTo(0));
    expect(blockReset, greaterThan(resize));
  });
}
