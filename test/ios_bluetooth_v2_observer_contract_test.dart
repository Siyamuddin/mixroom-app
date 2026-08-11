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
      expect(handler, contains('quiescePlaybackRouteV2ObjC:removed'));
      expect(handler, contains('self.audioRouteGenerationV2 += 1'));
      expect(
        handler.indexOf('quiescePlaybackRouteV2ObjC:removed'),
        lessThan(handler.indexOf('self.eventSink(@{')),
      );
      for (final forbidden in <String>[
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
        'Bluetooth disconnected. Using built-in speaker. Press Play to continue.',
      ),
    );
    expect(transitionHandler, isNot(contains('_playAudio(')));
  });

  test('shared output-only reconfigure helper supports iOS', () {
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

  test('iOS atomic apply validates one route and has no recovery chain', () {
    final source = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final apply = objectiveCMethod(
      source,
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:(NSDictionary *)args {',
    );

    expect(apply, contains('MixroomConfigureIOSPlaybackSession'));
    expect(apply, contains('MixroomIOSSingleOutputEndpoint'));
    expect(apply, contains('MixroomIOSOutputIdentitiesMatch'));
    expect(apply, contains('bluetooth_duplex_forbidden'));
    expect(apply, contains('juce_reopen_failed'));
    expect(apply, contains('fallback_succeeded'));
    expect(apply, contains('reconfigurePlaybackRouteV2ObjC:@""'));
    for (final forbidden in <String>[
      'preparePlaybackRouteObjC',
      'refreshAudioRouteObjC',
      'setPreferredInput:',
      'overrideOutputAudioPort:',
      'dispatch_after',
      'performSelector:afterDelay:',
    ]) {
      expect(apply, isNot(contains(forbidden)));
    }
  });
}
