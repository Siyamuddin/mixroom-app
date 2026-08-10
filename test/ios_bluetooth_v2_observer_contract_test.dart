import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String objectiveCMethod(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature must exist');
  final next = source.indexOf('\n- (', start + signature.length);
  return source.substring(start, next < 0 ? source.length : next);
}

void main() {
  test('iOS route observer is read-only and separately dispatched', () {
    final source = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final start = objectiveCMethod(
      source,
      '- (BOOL)startIOSAudioRouteObservationV2 {',
    );
    final handler = objectiveCMethod(
      source,
      '- (void)handleIOSObservedRouteChangeV2:(NSNotification *)notification {',
    );
    final combined = '$start\n$handler';

    expect(start, contains('AVAudioSessionRouteChangeNotification'));
    expect(handler, contains('audioRouteObservedV2'));
    for (final forbidden in <String>[
      'quiescePlaybackRouteV2',
      'reconfigurePlaybackRouteV2',
      'shutdownEngine',
      'setCategory:',
      'setMode:',
      'setActive:',
      'setPreferredInput:',
      'overrideOutputAudioPort:',
    ]) {
      expect(combined, isNot(contains(forbidden)));
    }

    expect(
      source,
      contains(
        'else if ([call.method isEqualToString:'
        '@"startAudioRouteObservationV2"])',
      ),
    );
    expect(
      source,
      contains(
        'else if ([call.method isEqualToString:'
        '@"stopAudioRouteObservationV2"])',
      ),
    );
  });

  test('iOS observation starts only after project loading completes', () {
    final source = File('lib/screens/audio_editor.dart').readAsStringSync();
    final projectLoad = source.indexOf('await _loadProjectIfAny();');
    final observerStart = source.indexOf(
      'await JuceAudioEngine.startIOSAudioRouteObservationV2();',
    );

    expect(projectLoad, isNonNegative);
    expect(observerStart, greaterThan(projectLoad));
  });
}
