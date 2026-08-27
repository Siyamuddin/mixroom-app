import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('iOS advertises passive input capacity without route activation', () {
    final plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final metadata = _between(
      plugin,
      'else if ([call.method isEqualToString:@"getInputDeviceInfos"])',
      'else if ([call.method isEqualToString:@"selectInputDevice"])',
    );

    expect(metadata, contains('session.availableInputs'));
    expect(metadata, contains('input.channels.count'));
    expect(metadata, contains('session.preferredInput'));
    expect(metadata, isNot(contains('setCategory')));
    expect(metadata, isNot(contains('setActive')));
  });

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

  test('iOS V2 native writer captures the callback-proven selected range', () {
    final openStart = engine.indexOf(
      'bool JuceEngine::openPreparedSystemSelectedDuplexRouteV2(',
    );
    final validateStart = engine.indexOf(
      'bool JuceEngine::validateRecordingRouteV2',
      openStart,
    );
    final open = engine.substring(openStart, validateStart);
    final writerStart = engine.indexOf('bool JuceEngine::startRecordingToWav');
    final writerEnd = engine.indexOf(
      'RealtimeWavCapture::StopResult JuceEngine::stopRecording()',
      writerStart,
    );
    final writer = engine.substring(writerStart, writerEnd);

    expect(open, contains('const auto error = deviceManager.initialise('));
    expect(open, contains('inputChannels,'));
    expect(open, contains('desiredInputOpenChannels.store(inputChannels'));
    expect(writer, contains('validateRecordingRouteV2()'));
    expect(writer, contains('channelStart < 0'));
    expect(writer, contains('channelCount != 1 && channelCount != 2'));
    expect(
      writer,
      contains(
        'requiredInputs != desiredInputOpenChannels.load(std::memory_order_relaxed)',
      ),
    );
    final v2GuardStart = writer.indexOf('if (v2Recording)');
    final v2GuardEnd = writer.indexOf('else\n#endif', v2GuardStart);
    expect(
      writer.substring(v2GuardStart, v2GuardEnd),
      isNot(contains('applyPreferredAudioDeviceSetup(requiredInputs')),
    );
    expect(plugin, contains('session.maximumInputNumberOfChannels'));
    expect(
      plugin,
      contains('MixroomIOSRouteIsBluetoothHFPDuplex(session.currentRoute)'),
    );
  });

  test(
    'editor shares V2 intents across supported platforms without polling',
    () {
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

      expect(lifecycle, contains('_supportsV2AudioRecording'));
      expect(lifecycle, contains('AudioRouteIntentV2.preparingRecording'));
      expect(lifecycle, contains('AudioRouteIntentV2.recording'));
      expect(lifecycle, contains('AudioRouteIntentV2.playbackOnly'));
      expect(lifecycle, contains('_restoreV2PlaybackOnlyAfterRecording'));
      expect(
        editor.substring(pollingStart, pollingEnd),
        contains('if (_isBluetoothV2Session) return;'),
      );
    },
  );

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
    final preflightEnd = editor.indexOf(
      'Future<void> _startAudioRecordingJuce()',
      preflightStart,
    );
    final preflight = editor.substring(preflightStart, preflightEnd);

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
      preflight,
      contains('AudioRouteIntentOperationV2.systemSelectedRecording'),
    );
    expect(
      preflight,
      contains(
        'Bluetooth microphone in use. Playback quality is reduced while recording.',
      ),
    );
    expect(
      preflight,
      contains('Recording is unavailable for the current iOS audio route.'),
    );
    final androidSourceGuard = editor.substring(
      preflightStart,
      permissionIndex,
    );
    expect(androidSourceGuard, contains('Platform.isAndroid'));
    expect(androidSourceGuard, contains('getAudioRouteSnapshotV2'));
    expect(
      preflight,
      contains(
        'verifiedInput?.normalizedKind == AudioRouteKindV2.bluetoothDuplex',
      ),
    );
    expect(
      preflight,
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

  test('only verified V2 monitoring routes input through the graph', () {
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
    expect(callback, contains('engine.shouldRouteLiveInputToGraphV2()'));
    expect(
      callback,
      contains('routeVerifiedInput ? inputChannelData : nullptr'),
    );
    expect(callback, contains('routeVerifiedInput ? numInputChannels : 0'));
    expect(engine, contains('liveInputMonitoringActiveV2.store(false'));
    expect(engine, contains('liveInputMonitoringActiveV2.store(true'));

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
      expect(handler, contains('AudioRouteCoordinatorStateV2.preparingInput'));
      expect(handler, isNot(contains('_supportsV2AudioRecording')));
      expect(handler, isNot(contains('_v2AudioSessionInvalidated')));
      final recordResolverStart = editor.indexOf(
        'Future<void> _startRecordingJuce() async {',
      );
      final recordResolverEnd = editor.indexOf(
        'Future<void> _letRecordingVisualStatePaint()',
        recordResolverStart,
      );
      final recordResolver = editor.substring(
        recordResolverStart,
        recordResolverEnd,
      );
      expect(
        recordResolver,
        contains('_showSmallNotice(_v2AudioSessionInvalidationNotice)'),
      );
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
        abort,
        allOf(
          contains('const BOOL activeProbe = self.iosIntentOperationActiveV2;'),
          contains('if (activeProbe && ![self claimIOSIntentCleanupV2])'),
        ),
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
      'if (_v2AudioSessionInvalidated)',
    );
    final nativeValidation = readiness.indexOf('validatePlaybackV2()');

    expect(invalidationCheck, greaterThanOrEqualTo(0));
    expect(invalidationCheck, lessThan(nativeValidation));
    expect(
      readiness.substring(invalidationCheck, nativeValidation),
      contains('_showSmallNotice(_v2AudioSessionInvalidationNotice)'),
    );
  });

  test('iOS recording route changes attempt one verified output recovery', () {
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
      'Future<void> _recoverV2PlaybackAfterAudioSessionInvalidation({',
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

    final handlerStart = editor.indexOf(
      'void _handleAudioRouteIntentInvalidatedV2(',
    );
    final handlerEnd = editor.indexOf(
      'Future<void> _recoverV2PlaybackAfterAudioSessionInvalidation({',
      handlerStart,
    );
    final handler = editor.substring(handlerStart, handlerEnd);
    expect(handler, contains("event.cause == 'audioInterruptionBegan'"));
    expect(handler, contains("event.cause == 'audioInterruptionEnded'"));
    expect(handler, contains("event.cause != 'shutdown'"));
    expect(handler, isNot(contains("event.cause == 'oldDeviceUnavailable'")));
    expect(handler, contains('if (_v2AudioSessionInvalidated)'));
    expect(handler, contains('foregroundRecoveryEvent'));
    expect(
      handler.indexOf('if (_v2AudioSessionInvalidated)'),
      lessThan(
        handler.indexOf('_recoverV2PlaybackAfterAudioSessionInvalidation'),
      ),
    );

    final shutdownStart = editor.indexOf(
      'Future<void> _shutdownAudioEngineV2Aware()',
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

    final startup = editor.substring(
      editor.indexOf(
        'WidgetsBinding.instance.addPostFrameCallback((_) async {',
      ),
      editor.indexOf('_juceEngineEventSubscription ??='),
    );
    final sessionLoaded = startup.indexOf('.loadSession()');
    final teardownWait = startup.indexOf('await priorShutdown');
    final initialization = startup.indexOf(
      'JuceAudioEngine.initialiseForImplementation',
    );
    expect(
      sessionLoaded,
      allOf(greaterThanOrEqualTo(0), lessThan(teardownWait)),
    );
    expect(teardownWait, lessThan(initialization));
    expect(startup, contains('final latestShutdown ='));
    expect(startup, contains('identical(latestShutdown, priorShutdown)'));

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
    final discard = playbackIntent.indexOf(
      '[JuceBridge discardRecordingCaptureObjC]',
    );
    final endOwnership = playbackIntent.indexOf(
      '[JuceBridge endIOSIntentOperationV2ObjC]',
      discard,
    );
    final captureReplacement = playbackIntent.indexOf(
      'MixroomIOSSingleOutputEndpoint(session.currentRoute)',
      endOwnership,
    );
    final reopen = playbackIntent.indexOf(
      'reconfigurePlaybackRouteV2ObjC:@""',
      captureReplacement,
    );
    expect(discard, greaterThanOrEqualTo(0));
    expect(endOwnership, greaterThan(discard));
    expect(captureReplacement, greaterThan(endOwnership));
    expect(reopen, greaterThan(captureReplacement));
    expect(
      RegExp('reconfigurePlaybackRouteV2ObjC').allMatches(playbackIntent),
      hasLength(1),
    );
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

  test('async recording UI work is guarded after native awaits', () {
    final startBegin = editor.indexOf(
      'Future<void> _startAudioRecordingJuce() async',
    );
    final startEnd = editor.indexOf(
      'Future<bool> _restoreV2PlaybackOnlyAfterRecording()',
      startBegin,
    );
    final start = editor.substring(startBegin, startEnd);
    expect(
      start,
      contains(
        'if (!mounted) {\n        await JuceAudioEngine.stopRecording();',
      ),
    );
    expect(start, contains('_startRecordingPeakPolling();'));
    expect(
      start,
      contains('if (mounted &&\n          _isBluetoothV2Session &&'),
    );

    final peakBegin = editor.indexOf('void _startRecordingPeakPolling()');
    final peakEnd = editor.indexOf(
      'Future<bool> _prepareAudioRecordingStartPreflight()',
      peakBegin,
    );
    final peakPolling = editor.substring(peakBegin, peakEnd);
    expect(
      peakPolling,
      contains(
        'final peak = await JuceAudioEngine.getRecordingPeak();\n'
        '        if (!mounted ||\n'
        '            !_isRecording ||\n'
        '            peakGeneration != _recordingPeakGeneration) {\n'
        '          return;\n'
        '        }',
      ),
    );

    final stopBegin = editor.indexOf(
      'Future<void> _stopAudioRecordingJuce({bool keepPlaying = true}) async',
    );
    final stopEnd = editor.indexOf(
      'Future<void> _addAudioTrackFromFile(',
      stopBegin,
    );
    final stop = editor.substring(stopBegin, stopEnd);
    expect(
      stop,
      contains(
        'final recordingLatencyMs =\n'
        '          await JuceAudioEngine.getEstimatedRecordingLatencyMs();',
      ),
    );
    expect(
      stop,
      contains(
        'if (!mounted) {\n'
        '        await _discardPendingUnpublishedRecordingFile(',
      ),
    );
    expect(stop, contains('expectedPath: recordingPath'));
    expect(
      stop,
      contains("if (mounted) {\n          ScaffoldMessenger.of(context)"),
    );
  });
}
