import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String plugin;
  late String engine;
  late String editor;

  setUpAll(() {
    plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  test('iOS V2 recording uses system selection and an output-only restore', () {
    final intentStart = plugin.indexOf(
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
    );
    final intentEnd = plugin.indexOf(
      '- (void)updateObservedOutputDeviceV2:',
      intentStart,
    );
    final intent = plugin.substring(intentStart, intentEnd);

    expect(intent, contains('systemSelectedRecording'));
    expect(intent, contains('prepareSystemSelectedDuplexSessionV2ObjC'));
    expect(intent, contains('openPreparedSystemSelectedDuplexRouteV2ObjC'));
    expect(intent, contains('getIOSAudioSessionPolicyFactsObjC'));
    expect(intent, contains('v2SystemSelectedDuplex'));
    expect(intent, contains('MixroomIOSSystemSelectedTargetMatchesSource'));
    expect(intent, contains('AVAudioSessionCategoryPlayAndRecord'));
    expect(intent, contains('reconfigurePlaybackRouteV2ObjC:@""'));
    final stopIndex = intent.indexOf('[JuceBridge stopRecordingObjC]');
    final reopenIndex = intent.indexOf(
      'reconfigurePlaybackRouteV2ObjC:@""',
      stopIndex,
    );
    expect(stopIndex, greaterThanOrEqualTo(0));
    expect(reopenIndex, greaterThan(stopIndex));
    expect(intent, contains('if ([JuceBridge isRecordingObjC])'));
    expect(intent, isNot(contains('setPreferredInput:')));
    expect(intent, isNot(contains('setCategory:')));
    expect(intent, isNot(contains('setMode:')));
    expect(intent, isNot(contains('setActive:')));
    expect(intent, isNot(contains('refreshAudioRouteObjC')));
    expect('dispatch_after'.allMatches(intent), hasLength(1));
  });

  test('iOS V2 native writer requires an already prepared mono route', () {
    final openStart = engine.indexOf('bool JuceEngine::openRecordingInputV2');
    final quiesceStart = engine.indexOf(
      'bool JuceEngine::quiescePlaybackRouteV2',
      openStart,
    );
    final open = engine.substring(openStart, quiesceStart);
    final writerStart = engine.indexOf('bool JuceEngine::startRecordingToWav');
    final writerEnd = engine.indexOf(
      'RealtimeWavCapture::StopResult JuceEngine::stopRecording()',
      writerStart,
    );
    final writer = engine.substring(writerStart, writerEnd);

    expect(open, contains('const auto error = deviceManager.initialise('));
    expect(open, contains('bluetoothHfp ? 1 : 2'));
    expect(open, contains('desiredInputOpenChannels.store(1'));
    expect(writer, contains('validateRecordingRouteV2()'));
    expect(writer, contains('channelStart != 0'));
    expect(writer, contains('channelCount != 1'));
    final v2GuardStart = writer.indexOf('if (v2Recording)');
    final v2GuardEnd = writer.indexOf('else\n#endif', v2GuardStart);
    expect(
      writer.substring(v2GuardStart, v2GuardEnd),
      isNot(contains('applyPreferredAudioDeviceSetup(requiredInputs')),
    );
  });

  test('editor shares V2 intents across macOS and iOS without polling', () {
    final preflightStart = editor.indexOf(
      'Future<bool> _prepareAudioRecordingStartPreflight()',
    );
    final permissionStart = editor.indexOf(
      'Future<bool> _ensureMicrophonePermissionForRecording()',
      preflightStart,
    );
    final lifecycle = editor.substring(preflightStart, permissionStart);
    final pollingStart = editor.indexOf(
      'void _startRecordingRoutePolicyPolling()',
    );
    final pollingEnd = editor.indexOf(
      'void _stopRecordingRoutePolicyPolling()',
      pollingStart,
    );

    expect(lifecycle, contains('(Platform.isMacOS || Platform.isIOS)'));
    expect(lifecycle, contains('AudioRouteIntentV2.preparingRecording'));
    expect(lifecycle, contains('AudioRouteIntentV2.recording'));
    expect(lifecycle, contains('AudioRouteIntentV2.playbackOnly'));
    expect(lifecycle, contains('_restoreV2PlaybackOnlyAfterRecording'));
    expect(
      editor.substring(pollingStart, pollingEnd),
      contains('if (_isBluetoothV2Session) return;'),
    );
  });

  test('all iOS V2 recording uses the system-selected intent path', () {
    final preflightStart = editor.indexOf(
      'Future<bool> _prepareAudioRecordingStartPreflight()',
    );
    final permissionIndex = editor.indexOf(
      '_ensureMicrophonePermissionForRecording()',
      preflightStart,
    );
    final intentIndex = editor.indexOf(
      'AudioRouteIntentV2.preparingRecording',
      preflightStart,
    );

    expect(
      editor.substring(preflightStart, permissionIndex),
      isNot(
        contains(
          'Recording is unavailable while Bluetooth is the audio output.',
        ),
      ),
    );
    expect(permissionIndex, lessThan(intentIndex));
    expect(
      editor.substring(preflightStart, intentIndex + 500),
      contains('AudioRouteIntentOperationV2.systemSelectedRecording'),
    );
    expect(
      editor.substring(preflightStart, intentIndex + 2000),
      contains(
        'Bluetooth microphone in use. Playback quality is reduced while recording.',
      ),
    );
    expect(
      editor.substring(preflightStart, intentIndex + 2500),
      contains('Recording is unavailable for the current iOS audio route.'),
    );
    expect(
      editor.substring(preflightStart, intentIndex),
      isNot(contains('getAudioRouteSnapshotV2')),
    );
    expect(
      editor.substring(intentIndex, intentIndex + 2500),
      contains(
        'verifiedInput?.normalizedKind == AudioRouteKindV2.bluetoothDuplex',
      ),
    );
    expect(
      editor.substring(intentIndex, intentIndex + 2500),
      contains(
        'verifiedOutput?.normalizedKind == AudioRouteKindV2.bluetoothDuplex',
      ),
    );
  });

  test('recording accepts only the exact verified system-selected target', () {
    final intentStart = plugin.indexOf(
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
    );
    final intentEnd = plugin.indexOf(
      '- (void)updateObservedOutputDeviceV2:',
      intentStart,
    );
    final intent = plugin.substring(intentStart, intentEnd);

    final iosStart = intent.indexOf(
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds()',
    );
    final recordingStart = intent.indexOf(
      '} else if ([intent isEqualToString:@"recording"]) {',
      iosStart,
    );
    final playbackStart = intent.indexOf('\n    } else {', recordingStart + 10);
    final recording = intent.substring(recordingStart, playbackStart);

    expect(recording, contains('const BOOL lifecycleRecording ='));
    expect(recording, contains('const BOOL systemSelectedRecording ='));
    expect(recording, contains('iosIntentOperationTargetFingerprintV2'));
    expect(recording, contains('iosIntentOperationTargetOutputV2'));
    expect(
      recording,
      contains('MixroomIOSRouteFingerprint(session.currentRoute)'),
    );
    expect(recording, contains('MixroomIOSSystemSelectedTargetMatchesSource'));
    expect(recording, contains('isBluetoothDuplexProjectCallbackReadyV2ObjC'));
    expect(recording, contains('[JuceBridge isRecordingObjC]'));
    expect(recording, isNot(contains('MixroomIOSInputIsBluetoothHFP')));
    expect(recording, isNot(contains('MixroomIOSOutputIsBluetoothHFP')));
    expect(recording, isNot(contains('44.1')));
    expect(recording, isNot(contains('48000')));
  });

  test('HFP input is captured but never monitored through the graph', () {
    final callbackStart = File('juce_audio_engine/ios/Classes/JuceEngine.h')
        .readAsStringSync()
        .indexOf(
          'class MetronomeAudioCallback : public juce::AudioIODeviceCallback',
        );
    final header = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    final callback = header.substring(callbackStart);
    expect(callback, contains('engine.captureInput(inputChannelData'));
    expect(
      callback,
      contains(
        'player.audioDeviceIOCallbackWithContext(\n            nullptr,\n            0,',
      ),
    );

    final routeStart = engine.indexOf('void JuceEngine::routeLiveInputToRow');
    final writerStart = engine.indexOf(
      'bool JuceEngine::startRecordingToWav',
      routeStart,
    );
    final route = engine.substring(routeStart, writerStart);
    final v2Guard = route.indexOf('if (isV2PlaybackSession())');
    expect(v2Guard, greaterThanOrEqualTo(0));
    expect(
      route.indexOf('return;', v2Guard),
      lessThan(route.indexOf('syncLiveInputMonitorRoutingLocked')),
    );
  });

  test(
    'preparation cancellation uses the abort contract without cleanup racing',
    () {
      final handlerStart = editor.indexOf(
        'Future<void> _handleRecordPressed({required bool keepPlayingOnStop})',
      );
      final handlerEnd = editor.indexOf(
        'String _normalizeEffectText',
        handlerStart,
      );
      final handler = editor.substring(handlerStart, handlerEnd);
      expect(handler, contains('abortRecordingV2(cancelOnly: true)'));
      expect(
        handler,
        contains('_showSmallNotice(_v2RecordingInvalidationNotice)'),
      );
      expect(handler, contains('AudioRouteCoordinatorStateV2.preparingInput'));
      final startFlowStart = editor.indexOf(
        'Future<void> _startAudioRecordingJuce()',
      );
      final startFlowEnd = editor.indexOf(
        'Future<bool> _restoreV2PlaybackOnlyAfterRecording()',
        startFlowStart,
      );
      final startFlow = editor.substring(startFlowStart, startFlowEnd);
      final preflightStart = editor.indexOf(
        'Future<bool> _prepareAudioRecordingStartPreflight()',
      );
      final preflightEnd = editor.indexOf(
        'Future<void> _startAudioRecordingJuce()',
        preflightStart,
      );
      final preflight = editor.substring(preflightStart, preflightEnd);
      final preparationResultIndex = preflight.indexOf(
        'final result = await coordinator.transitionIntent(',
      );
      final cancellationResultIndex = preflight.indexOf(
        'if (_recordStartCancelRequested) return false;',
        preparationResultIndex,
      );
      final preparationFailureIndex = preflight.indexOf(
        'if (!result.succeeded)',
        preparationResultIndex,
      );
      expect(preparationResultIndex, greaterThanOrEqualTo(0));
      expect(cancellationResultIndex, greaterThan(preparationResultIndex));
      expect(preparationFailureIndex, greaterThan(cancellationResultIndex));
      final restoreIndex = startFlow.indexOf(
        'await _restoreV2PlaybackOnlyAfterRecording();',
      );
      final transitionCompleteIndex = startFlow.indexOf(
        '_recordTransitionInFlight = false;',
        restoreIndex,
      );
      expect(restoreIndex, greaterThanOrEqualTo(0));
      expect(transitionCompleteIndex, greaterThan(restoreIndex));

      final abortStart = plugin.indexOf(
        'else if ([call.method isEqualToString:@"abortRecordingV2"])',
      );
      final abortEnd = plugin.indexOf(
        'else if ([call.method isEqualToString:@"stopAudioRouteMonitoringV2"])',
        abortStart,
      );
      final abort = plugin.substring(abortStart, abortEnd);
      expect(abort, contains('const BOOL cancelOnly ='));
      expect(
        abort.indexOf('if (cancelOnly)'),
        lessThan(abort.indexOf('dispatch_async(MixroomIOSLifecycleQueue()')),
      );
      expect(
        plugin,
        contains('self.iosIntentOperationActiveV2)) {'),
        reason:
            'an active cancelled preparation must retain the single native cleanup owner',
      );
      expect(plugin, contains('recordingRouteMutationStarted'));
      expect(plugin, contains('if (self.iosIntentOperationCancelledV2) {'));
    },
  );

  test('playback reports the existing reopen boundary after invalidation', () {
    final readinessStart = editor.indexOf(
      'Future<bool> _ensurePlaybackRouteReady({required String reason}) async',
    );
    final readinessEnd = editor.indexOf(
      'Future<void> _requestAndroidRouteRefresh',
      readinessStart,
    );
    final readiness = editor.substring(
      readinessStart,
      readinessEnd < 0 ? readinessStart + 3000 : readinessEnd,
    );
    final invalidationCheck = readiness.indexOf(
      'if (_v2RecordingRouteInvalidated)',
    );
    final nativeValidation = readiness.indexOf('validatePlaybackV2()');

    expect(invalidationCheck, greaterThanOrEqualTo(0));
    expect(invalidationCheck, lessThan(nativeValidation));
    expect(
      readiness.substring(invalidationCheck, nativeValidation),
      contains('_showSmallNotice(_v2RecordingInvalidationNotice)'),
    );
  });

  test('iOS HFP removal attempts one verified system-output recovery', () {
    final abortStart = plugin.indexOf(
      'else if ([call.method isEqualToString:@"abortRecordingV2"])',
    );
    final abortEnd = plugin.indexOf(
      'else if ([call.method isEqualToString:@"stopAudioRouteMonitoringV2"])',
      abortStart,
    );
    final abort = plugin.substring(abortStart, abortEnd);

    expect(abort, contains('[JuceBridge discardRecordingCaptureObjC]'));
    expect(abort, contains('restorePlayback'));
    expect(abort, contains('if (terminal || !restored)'));
    expect(abort, contains('reconfigurePlaybackRouteV2ObjC:@""'));
    expect(abort, contains('[JuceBridge quiescePlaybackRouteV2ObjC:YES]'));
    expect(abort, isNot(contains('setPreferredInput:')));
    expect(abort, isNot(contains('setActive:')));

    final invalidationStart = editor.indexOf(
      'Future<void> _recoverV2PlaybackAfterRecordingRouteChange({',
    );
    final invalidationEnd = editor.indexOf(
      'Future<void> _synchronizeIOSRouteSafetyPositionV2',
      invalidationStart,
    );
    final invalidation = editor.substring(invalidationStart, invalidationEnd);
    expect(invalidation, contains('recoverPlaybackAfterIntentInvalidation()'));
    expect(
      invalidation,
      contains('JuceAudioEngine.acceptVerifiedAudioRouteTransitionV2'),
    );
    expect(invalidation, contains('abortRecordingV2(restorePlayback: false)'));
    expect(invalidation, contains('await coordinator?.dispose()'));
    expect(invalidation, contains('await JuceAudioEngine.shutdown()'));
    final terminalAbort = invalidation.indexOf(
      'await JuceAudioEngine.abortRecordingV2(restorePlayback: false)',
    );
    final terminalDelete = invalidation.indexOf(
      'await _deleteUncommittedRecordingFile(unpublishedRecordingPath)',
      terminalAbort,
    );
    final terminalShutdown = invalidation.indexOf(
      'await JuceAudioEngine.shutdown()',
      terminalAbort,
    );
    expect(terminalAbort, greaterThanOrEqualTo(0));
    expect(terminalShutdown, greaterThan(terminalAbort));
    expect(terminalDelete, greaterThan(terminalShutdown));

    final shutdownStart = editor.indexOf(
      'Future<void> _shutdownAudioEngineV2Aware() async',
    );
    final shutdownEnd = editor.indexOf(
      '@override\n  void didChangeAppLifecycleState',
      shutdownStart,
    );
    final shutdown = editor.substring(shutdownStart, shutdownEnd);
    expect(shutdown, contains('final routeRecovery ='));
    expect(shutdown, contains('await routeRecovery;'));
    expect(
      shutdown.indexOf('await routeRecovery;'),
      lessThan(shutdown.indexOf('await coordinator?.dispose()')),
    );

    final playbackIntentStart = plugin.indexOf(
      'NSDictionary<NSString *, id> *recordingSourceOutput =',
    );
    final playbackIntentEnd = plugin.indexOf(
      '\n    if (success) {\n        self.currentAudioRouteIntentV2 = intent;',
      playbackIntentStart,
    );
    final playbackIntent = plugin.substring(
      playbackIntentStart,
      playbackIntentEnd,
    );
    expect(playbackIntent, contains('recoveringAfterPhysicalInvalidation'));
    expect(
      playbackIntent,
      contains('[JuceBridge discardRecordingCaptureObjC]'),
    );
    expect(playbackIntent, contains('reconfigurePlaybackRouteV2ObjC:@""'));
    expect(playbackIntent, contains('fallback_succeeded'));
    expect(playbackIntent, contains('activeInputChannels'));
    expect(playbackIntent, contains('audioCallbackAttached'));
    expect(playbackIntent, isNot(contains('dispatch_after')));
  });

  test(
    'cancelled built-in preparation cannot turn a duplicate session notification into a route change',
    () {
      final observerStart = plugin.indexOf(
        '- (void)handleIOSAudioRouteChangeV2:(NSNotification *)notification {',
      );
      final observerEnd = plugin.indexOf('\n}\n#endif', observerStart);
      final observer = plugin.substring(observerStart, observerEnd);

      expect(observer, contains('!terminalRouteNotification'));
      expect(observer, contains('!self.iosIntentOperationActiveV2'));
      expect(
        observer,
        contains('[fingerprint isEqualToString:self.audioRouteFingerprintV2]'),
      );
      expect(
        observer,
        isNot(
          contains(
            '!self.iosIntentOperationCancelledV2 &&\n'
            '            [fingerprint isEqualToString:',
          ),
        ),
      );
    },
  );
}
