import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String objectiveCMethod(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature must exist');
  final next = source.indexOf('\n- (', start + signature.length);
  return source.substring(start, next < 0 ? source.length : next);
}

void main() {
  test('iOS route observer applies only the bounded safety action', () {
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
    expect(
      handler,
      contains('AVAudioSessionRouteChangeReasonOldDeviceUnavailable'),
    );
    expect(handler, contains('quiescePlaybackRouteV2ObjC:removed'));
    expect(handler, contains('@"transportWasPlaying"'));
    expect(handler, contains('@"callbackDetached"'));
    expect(handler, contains('@"deviceClosed"'));
    expect(
      handler.indexOf('quiescePlaybackRouteV2ObjC:removed'),
      lessThan(handler.indexOf('self.eventSink(@{')),
    );
    for (final forbidden in <String>[
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

  test('iOS observation subscribes after loading and before native start', () {
    final source = File('lib/screens/audio_editor.dart').readAsStringSync();
    final projectLoad = source.indexOf('await _loadProjectIfAny();');
    final observerSubscription = source.indexOf(
      '.audioRouteObservationEventsV2',
    );
    final observerStart = source.indexOf(
      'await JuceAudioEngine.startIOSAudioRouteObservationV2();',
    );

    expect(projectLoad, isNonNegative);
    expect(observerSubscription, greaterThan(projectLoad));
    expect(observerStart, greaterThan(observerSubscription));
  });

  test('iOS safety invalidates transport and requires editor reopen', () {
    final source = File('lib/screens/audio_editor.dart').readAsStringSync();
    final handlerStart = source.indexOf(
      'void _handleIOSAudioRouteObservationV2(',
    );
    final handlerEnd = source.indexOf(
      'void _handleAudioRouteCoordinatorStateV2(',
      handlerStart,
    );
    expect(handlerStart, isNonNegative);
    expect(handlerEnd, greaterThan(handlerStart));
    final handler = source.substring(handlerStart, handlerEnd);

    expect(handler, contains('_iosAudioRouteReopenRequiredV2 = true'));
    expect(handler, contains('_transportDesiredPlaying = false'));
    expect(handler, contains('++_transportCommandSerial'));
    expect(handler, contains('_transportTicker?.stop()'));
    expect(handler, contains('_stopMeterPolling()'));
    expect(
      source,
      contains('Audio output changed. Reopen the audio editor to continue.'),
    );
    expect(
      source.indexOf('stopIOSAudioRouteObservationV2();'),
      lessThan(source.indexOf('await JuceAudioEngine.shutdown();')),
    );
  });

  test('shared quiesce helper supports iOS without reopening audio', () {
    final source = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    final start = source.indexOf(
      'bool JuceEngine::quiescePlaybackRouteV2(bool closeRemovedDevice)',
    );
    final end = source.indexOf(
      'bool JuceEngine::reconfigurePlaybackRouteV2(',
      start,
    );
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final helper = source.substring(start, end);

    expect(helper, contains('JUCE_IOS'));
    expect(helper, contains('pause();'));
    expect(helper, contains('removeAudioCallback'));
    expect(helper, contains('if (closeRemovedDevice)'));
    expect(helper, contains('closeAudioDevice();'));
    expect(helper, isNot(contains('openPlaybackOutputOnlyV2')));
    expect(helper, isNot(contains('reconfigurePlaybackRouteV2')));
  });
}
