import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String objectiveCMethod(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature must exist');
  final next = source.indexOf('\n- (', start + signature.length);
  return source.substring(start, next < 0 ? source.length : next);
}

void main() {
  test(
    'iOS uses one event-driven route observer for the shared coordinator',
    () {
      final source = File(
        'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
      ).readAsStringSync();
      final start = objectiveCMethod(
        source,
        '- (BOOL)startIOSAudioRouteMonitoringV2 {',
      );
      final handler = objectiveCMethod(
        source,
        '- (void)handleIOSAudioRouteChangeV2:(NSNotification *)notification {',
      );

      expect(start, contains('AVAudioSessionRouteChangeNotification'));
      expect(start, contains('UIApplicationDidBecomeActiveNotification'));
      expect(handler, contains('audioRouteChangedV2'));
      expect(handler, contains('pausePlaybackForRouteChangeV2ObjC'));
      expect(handler, contains('self.audioRouteGenerationV2 += 1'));
      expect(
        handler.indexOf('pausePlaybackForRouteChangeV2ObjC'),
        lessThan(handler.indexOf('self.eventSink(@{')),
      );
      for (final forbidden in <String>[
        'quiescePlaybackRouteV2',
        'reconfigurePlaybackRouteV2',
        'setCategory:',
        'setMode:',
        'setPreferredInput:',
        'overrideOutputAudioPort:',
        'dispatch_after',
      ]) {
        expect(handler, isNot(contains(forbidden)));
      }
      expect(source, isNot(contains('audioRouteObservedV2')));
      expect(source, isNot(contains('startAudioRouteObservationV2')));
    },
  );

  test('iOS coordinator starts after project loading', () {
    final source = File('lib/screens/audio_editor.dart').readAsStringSync();
    final projectLoad = source.indexOf('await _loadProjectIfAny();');
    final iosCoordinator = source.indexOf(
      'if (_isBluetoothV2Session && Platform.isIOS)',
      projectLoad,
    );
    final coordinatorStart = source.indexOf(
      'final initialRoute = await coordinator.start();',
      iosCoordinator,
    );

    expect(projectLoad, isNonNegative);
    expect(iosCoordinator, greaterThan(projectLoad));
    expect(coordinatorStart, greaterThan(iosCoordinator));
    expect(source, isNot(contains('_iosAudioRouteReopenRequiredV2')));
    expect(source, isNot(contains('audioRouteObservationEventsV2')));
    expect(source, contains('coordinator != null &&'));
    expect(
      source,
      isNot(
        contains(
          '_audioRouteCoordinatorV2?.state !=\n'
          '              AudioRouteCoordinatorStateV2.stable',
        ),
      ),
    );
  });

  test('iOS transition pauses UI and keeps manual resume policy', () {
    final source = File('lib/screens/audio_editor.dart').readAsStringSync();
    final stateStart = source.indexOf(
      'void _handleAudioRouteCoordinatorStateV2(',
    );
    final transitionStart = source.indexOf(
      'void _handleAudioRouteTransitionV2(',
      stateStart,
    );
    final nextMethod = source.indexOf('\n  Future<', transitionStart);
    final stateHandler = source.substring(stateStart, transitionStart);
    final transitionHandler = source.substring(transitionStart, nextMethod);

    expect(stateHandler, contains('_transportDesiredPlaying = false'));
    expect(stateHandler, contains('++_transportCommandSerial'));
    expect(stateHandler, contains('_transportTicker?.stop()'));
    expect(stateHandler, contains('_stopMeterPolling()'));
    expect(stateHandler, contains('_synchronizeIOSRouteSafetyPositionV2'));
    expect(
      transitionHandler,
      contains('Audio output changed. Press Play to continue.'),
    );
    expect(
      transitionHandler,
      contains(
        'Bluetooth disconnected. Audio output changed. Press Play to continue.',
      ),
    );
    expect(transitionHandler, isNot(contains('_playAudio(')));
  });

  test('explicit output-only reconfigure helper remains available for iOS', () {
    final source = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    final start = source.indexOf(
      'bool JuceEngine::reconfigurePlaybackRouteV2(',
    );
    final end = source.indexOf(
      'juce::String JuceEngine::getAudioRouteImplementationName()',
      start,
    );
    final helper = source.substring(start, end);

    expect(helper, contains('JUCE_IOS'));
    expect(helper, contains('quiescePlaybackRouteV2(false)'));
    expect(helper, contains('openPlaybackOutputOnlyV2(outputDeviceName)'));
    expect(helper, contains('prepareLiveClipProcessorsForCurrentDevice()'));
    expect(helper, contains('addAudioCallback'));
    expect(helper, isNot(contains('applyPreferredAudioDeviceSetup')));
  });

  test('iOS coordinator apply only verifies the settled JUCE route', () {
    final source = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final apply = objectiveCMethod(
      source,
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:(NSDictionary *)args {',
    );
    final iosStart = apply.indexOf(
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds()',
    );
    expect(iosStart, isNonNegative);
    final iosApply = apply.substring(iosStart);

    expect(iosApply, contains('getIOSAudioSessionPolicyFactsObjC'));
    expect(iosApply, contains('v2PlaybackOnly'));
    expect(iosApply, contains('MixroomIOSSingleOutputEndpoint'));
    expect(iosApply, contains('MixroomIOSOutputIdentitiesMatch'));
    expect(iosApply, contains('eventFingerprint'));
    expect(iosApply, contains('bluetooth_duplex_forbidden'));
    expect(iosApply, contains('fallback_succeeded'));
    for (final forbidden in <String>[
      'reconfigurePlaybackRouteV2ObjC',
      'quiescePlaybackRouteV2ObjC',
      'preparePlaybackRouteObjC',
      'refreshAudioRouteObjC',
      'setPreferredInput:',
      'overrideOutputAudioPort:',
      'dispatch_after',
      'performSelector:afterDelay:',
    ]) {
      expect(iosApply, isNot(contains(forbidden)));
    }
  });

  test('failed callback workaround and effect stack logging are absent', () {
    final header = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    final effects = File(
      'juce_audio_engine/android/src/main/cpp/NativeEffects.h',
    ).readAsStringSync();

    expect(header, isNot(contains('deviceCallbackActive')));
    expect(effects, isNot(contains('Mixroom effect scratch overflow')));
    expect(effects, isNot(contains('getStackBacktrace')));
  });
}
