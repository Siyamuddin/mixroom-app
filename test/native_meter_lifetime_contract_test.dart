import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String meterClass(String source) {
  final start = source.indexOf('class MeterTapProcessor :');
  final end = source.indexOf('// Helper: volume automation', start);
  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  const roots = [
    'juce_audio_engine/ios/Classes', // Also compiled by macOS and Windows.
    'juce_audio_engine/android/src/main/cpp',
  ];

  for (final root in roots) {
    test('meter processor retains immutable targets: $root', () {
      final source = meterClass(File('$root/JuceEngine.h').readAsStringSync());
      expect(source, contains('const std::shared_ptr<void> meterOwner;'));
      expect(source, contains('meterOwner(meter)'));
      for (final channel in ['peakL', 'peakR', 'rmsL', 'rmsR']) {
        expect(source, contains('$channel(&meter->$channel)'));
        expect(source, contains('std::atomic<float> *const $channel;'));
      }
      expect(source, isNot(contains('void setMeterTargets(')));

      final callback = source.substring(
        source.indexOf('void processBlock('),
        source.indexOf('void assertMeterTargets('),
      );
      // The lifetime fix must not add per-block ownership/locking overhead.
      expect(callback, isNot(contains('meterOwner')));
      expect(callback, isNot(contains('shared_ptr')));
      expect(callback, isNot(contains('mutex')));
    });

    test('rows and groups both supply shared meter ownership: $root', () {
      final source = File('$root/JuceEngine.cpp').readAsStringSync();
      final constructors = RegExp(
        r'make_unique<MeterTapProcessor>\(\s*(r|group)\.meter,\s*&rowMetersEnabled\)',
      ).allMatches(source);
      expect(constructors.map((match) => match.group(1)).toSet(), {
        'r',
        'group',
      });
      expect(constructors, hasLength(2));
    });
  }

  test('meter ownership stays aligned across native engines', () {
    List<String> ownershipParts(String source) => [
      source.substring(0, source.indexOf('const juce::String getName()')),
      source.substring(source.indexOf('void assertMeterTargets(')),
    ];
    expect(
      ownershipParts(
        meterClass(File('${roots[0]}/JuceEngine.h').readAsStringSync()),
      ),
      ownershipParts(
        meterClass(File('${roots[1]}/JuceEngine.h').readAsStringSync()),
      ),
    );
  });
}
