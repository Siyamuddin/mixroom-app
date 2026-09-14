import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const nativeRoots = <String>[
    'juce_audio_engine/ios/Classes',
    'juce_audio_engine/android/src/main/cpp',
  ];

  for (final root in nativeRoots) {
    test(
      'native storage is dynamic and former capacities are hints: $root',
      () {
        final header = File('$root/JuceEngine.h').readAsStringSync();
        final source = File('$root/JuceEngine.cpp').readAsStringSync();

        expect(header, contains('std::vector<RowState> rows;'));
        expect(header, contains('std::vector<ClipState> clips;'));
        expect(header, contains('kInitialRowReserve = 100'));
        expect(header, contains('kInitialClipReserve = 500'));
        expect(header, isNot(contains('kMaxRows')));
        expect(header, isNot(contains('kMaxClips')));
        expect(source, isNot(contains('clipId >= kMaxClips')));
        expect(source, isNot(contains('rows.size() >= kMaxRows')));
        expect(source, contains('clips.resize((size_t)clipId + 1)'));
      },
    );

    test('native publication uses immutable routed snapshots: $root', () {
      final header = File('$root/JuceEngine.h').readAsStringSync();
      expect(header, contains('std::shared_ptr<const RoutedClipSchedules>'));
      expect(header, contains('std::atomic<const RoutedClipItemsSnapshot *>'));
      expect(header, contains('retiredRoutedClipScheduleSnapshots'));
      expect(header, contains('retiredRoutedClipItemSnapshots'));
    });

    test('native admission exposes fail-closed detailed results: $root', () {
      final header = File('$root/JuceEngine.h').readAsStringSync();
      final source = File('$root/JuceEngine.cpp').readAsStringSync();
      for (final result in <String>[
        'success',
        'invalidInput',
        'missingMedia',
        'resourceExhausted',
        'internalFailure',
      ]) {
        expect(header, contains(result));
      }
      expect(header, contains('loadClipDetailed('));
      expect(
        'c = std::move(previousClip)'.allMatches(source).length,
        greaterThanOrEqualTo(2),
        reason:
            'Audio and MIDI replacement admissions must restore the prior clip '
            'when routed snapshot publication fails.',
      );
      expect(
        source,
        isNot(contains('routedPublicationFailed && freshAdmission')),
      );
    });

    test('batched clip removal is preflighted and acknowledged: $root', () {
      final source = File('$root/JuceEngine.cpp').readAsStringSync();
      final start = source.indexOf(
        'int JuceEngine::unloadClips(const juce::Array<int> &clipIds)',
      );
      final end = source.indexOf(
        'std::shared_ptr<juce::AudioProcessor> JuceEngine::clearClipGraphNodes',
        start,
      );

      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final unload = source.substring(start, end);
      expect(unload, contains('uniqueClipIds.addIfNotAlreadyThere(clipId)'));
      expect(unload, contains('!clips[(size_t)clipId].alive'));
      expect(
        unload.indexOf('!clips[(size_t)clipId].alive'),
        lessThan(unload.indexOf('clearClipGraphNodes(')),
      );
      expect(
        unload,
        contains(
          'routedPublicationSucceeded = '
          'endRoutedClipScheduleMutationLocked();',
        ),
      );
      expect(
        unload,
        contains('return routedPublicationSucceeded ? removed : -1;'),
      );
    });
  }

  test('every platform bridge exposes detailed project-load admission', () {
    final bridgeSources = <String>[
      File(
        'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
      ).readAsStringSync(),
      File(
        'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/JuceAudioEnginePlugin.kt',
      ).readAsStringSync(),
      File(
        'juce_audio_engine/windows/juce_audio_engine_plugin.cpp',
      ).readAsStringSync(),
    ];

    for (final source in bridgeSources) {
      expect(source, contains('loadClipDetailed'));
      expect(source, contains('endProjectClipLoadDetailed'));
    }
  });

  test('Dart treats missing and malformed detailed results as failure', () {
    final source = File(
      'juce_audio_engine/lib/juce_audio_engine.dart',
    ).readAsStringSync();
    expect(source, contains('enum JuceMutationResult'));
    expect(source, contains('return JuceMutationResult.internalFailure;'));
    expect(source, contains("invokeMethod<Object?>('loadClipDetailed'"));
    expect(
      source,
      contains("invokeMethod<Object?>('endProjectClipLoadDetailed'"),
    );
  });

  test(
    'Apple project-load diagnostics expose publication lifecycle counts',
    () {
      final source = File(
        'juce_audio_engine/ios/Classes/JuceEngine.cpp',
      ).readAsStringSync();
      expect(source, contains('callbackDetachCount='));
      expect(source, contains('graphPublicationCount='));
      expect(source, contains('callbackAttachCount='));
    },
  );
}
