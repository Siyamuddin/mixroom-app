import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String plugin;
  late String engine;
  late String editor;

  setUpAll(() {
    plugin = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/JuceAudioEnginePlugin.kt',
    ).readAsStringSync();
    engine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.cpp',
    ).readAsStringSync();
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  test('Android V2 recording uses the existing serialized intent contract', () {
    expect(plugin, contains('"setAudioRouteIntentV2"'));
    expect(plugin, contains('"abortRecordingV2"'));
    expect(plugin, contains('audioLifecycleExecutorV2'));
    expect(plugin, contains('prepareBuiltInRecordingV2('));
    expect(
      plugin,
      contains('prepareSystemSelectedRecordingV2('),
    );
    expect(plugin, contains('"systemSelectedRecording"'));
    expect(plugin, contains('restoreRecordingPlaybackV2(generation)'));
    expect(plugin, contains('recordingCancellationRequestedV2'));
    expect(plugin, contains('cleanupClaimed.compareAndSet(false, true)'));
  });

  test(
    'prepared recording opens once and capture never reopens the device',
    () {
      final prepareStart = engine.indexOf(
        'bool JuceEngine::prepareRecordingV2Android(int inputChannels)',
      );
      final waitStart = engine.indexOf(
        'bool JuceEngine::waitForV2CallbackReady',
        prepareStart,
      );
      final prepare = engine.substring(prepareStart, waitStart);
      final recordStart = engine.indexOf(
        'bool JuceEngine::startRecordingToWav',
      );
      final discardStart = engine.indexOf(
        'void JuceEngine::discardRecordingCaptureV2Android',
        recordStart,
      );
      final start = engine.substring(recordStart, discardStart);

      expect(
        prepare,
        contains('deviceManager.initialise(\n        requestedInputs,\n        2'),
      );
      expect(prepare, contains('liveInputMonitoringEnabled = false'));
      expect(prepare, contains('androidV2CallbackProofPending'));
      expect(
        start,
        contains('const bool v2Recording = androidV2RecordingPrepared'),
      );
      expect(start, contains('channelStart < 0'));
      expect(start, contains('channelCount != 1 && channelCount != 2'));
      expect(
        start,
        contains(
          'requiredInputs != desiredInputOpenChannels.load(std::memory_order_relaxed)',
        ),
      );
      expect(start, contains('else if (!applyPreferredAudioDeviceSetup'));
    },
  );

  test(
    'editor follows every stable Android route before permission and restores on Stop',
    () {
      final preflightStart = editor.indexOf(
        'Future<bool> _prepareAudioRecordingStartPreflight()',
      );
      final recordingStart = editor.indexOf(
        'Future<void> _startAudioRecordingJuce()',
        preflightStart,
      );
      final preflight = editor.substring(preflightStart, recordingStart);
      final stopStart = editor.indexOf('Future<void> _stopAudioRecordingJuce');
      final stopEnd = editor.indexOf('\n  Future<', stopStart + 20);
      final stop = editor.substring(stopStart, stopEnd);

      expect(
        preflight,
        contains('AudioRouteIntentOperationV2.systemSelectedRecording'),
      );
      expect(
        preflight,
        isNot(contains('switch (sourceOutput.normalizedKind)')),
      );
      expect(preflight, isNot(contains('case AudioRouteKindV2.')));
      expect(
        preflight.indexOf('getAudioRouteSnapshotV2()'),
        lessThan(
          preflight.indexOf('_ensureMicrophonePermissionForRecording()'),
        ),
      );
      expect(preflight, contains('AudioRouteIntentV2.preparingRecording'));
      expect(
        preflight,
        contains('recordingChannelStart: _selectedChannelStart'),
      );
      expect(
        preflight,
        contains('recordingChannelCount: _selectedChannelCount'),
      );
      expect(stop, contains('await JuceAudioEngine.stopRecording()'));
      expect(stop, contains('_restoreV2RouteAfterAudioRecording()'));
    },
  );

  test('callback proof is published only by a prepared valid callback', () {
    final header = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.h',
    ).readAsStringSync();
    final callbackStart = header.indexOf(
      'void audioDeviceIOCallbackWithContext(',
      header.indexOf('class MetronomeAudioCallback'),
    );
    final callbackEnd = header.indexOf(
      '\n    void setupClickFilter',
      callbackStart,
    );
    final callback = header.substring(callbackStart, callbackEnd);

    expect(callback, contains('callbackReady.load(std::memory_order_acquire)'));
    expect(callback, contains('numSamples > knownBlockCapacity'));
    expect(callback, contains('numInputChannels != knownInputs'));
    expect(callback, contains('numOutputChannels != knownOutputs'));
    expect(callback, contains('if (unexpectedCallbackShape)'));
    expect(
      callback.indexOf('if (unexpectedCallbackShape)'),
      lessThan(callback.indexOf('engine.captureInput')),
    );
  });

  test('V2 native capture path contains no Legacy input preparation', () {
    final start = plugin.indexOf('private fun startPreparedCaptureV2(');
    final end = plugin.indexOf('private fun stopPreparedCaptureV2(', start);
    final capture = plugin.substring(start, end);
    for (final forbidden in <String>[
      'prepareRecordingInputs',
      'selectInputDevice',
      'applyPreferredAudioDeviceSetup',
      'postDelayed',
      'Thread.sleep',
    ]) {
      expect(capture, isNot(contains(forbidden)));
    }
    expect(capture, contains('captureLifecycleV2.start('));
    expect(
      plugin,
      contains('JuceBridge.startRecordingJNI(path, channelStart, channelCount)'),
    );
    expect(capture, isNot(contains('allowsCapture')));
  });

  test(
    'Bluetooth production uses the verified SCO device without reopening',
    () {
      final prepareStart = plugin.indexOf(
        'private fun prepareBluetoothDuplexV2(',
      );
      final prepareEnd = plugin.indexOf(
        'private fun verifyRecordingIntentV2',
        prepareStart,
      );
      final prepare = plugin.substring(prepareStart, prepareEnd);
      final validateStart = plugin.indexOf(
        'private fun validatePreparedRecordingV2(',
      );
      final validateEnd = plugin.indexOf(
        'private fun audioModeName',
        validateStart,
      );
      final validate = plugin.substring(validateStart, validateEnd);

      expect(prepare, contains('JuceBridge.prepareBluetoothDuplexV2JNI()'));
      expect(prepare, isNot(contains('allowsCapture')));
      expect(prepare, contains('AndroidBluetoothDuplexReadinessV2.validate'));
      expect(
        validate,
        contains('AndroidRecordingRouteAdapterV2.BLUETOOTH_COMMUNICATION'),
      );
      expect(validate, contains('currentBluetoothDuplexFactsV2(operation)'));
      expect(validate, contains('actualInput?.fingerprint'));
      expect(validate, contains('actualOutput?.fingerprint'));
      expect(validate, isNot(contains('prepareBluetoothDuplexV2JNI')));
    },
  );

  test(
    'native SCO loss reports into the lifecycle owner without restarting audio',
    () {
      final oboe = File(
        'juce_audio_engine/android/src/main/cpp/juce/modules/juce_audio_devices/native/juce_Oboe_android.cpp',
      ).readAsStringSync();
      final bridge = File(
        'juce_audio_engine/android/src/main/cpp/JuceLogBridge.cpp',
      ).readAsStringSync();
      final errorStart = oboe.indexOf(
        'void onErrorAfterClose (oboe::AudioStream* stream, oboe::Result error)',
      );
      final errorEnd = oboe.indexOf(
        'std::vector<SampleType> inputStreamNativeBuffer;',
        errorStart,
      );
      final errorCallback = oboe.substring(errorStart, errorEnd);
      final notifyStart = bridge.indexOf(
        'void notifyAndroidBluetoothDuplexDisconnectedV2(',
      );
      final notifyEnd = bridge.indexOf(
        '// Called from Kotlin to initialize',
        notifyStart,
      );
      final notificationBridge = bridge.substring(notifyStart, notifyEnd);

      expect(errorCallback, contains('outputStream->getStreamPolicyV2()'));
      expect(errorCallback, contains('currentOutput.get() != stream'));
      expect(errorCallback, contains('getDisconnectedStreamAction'));
      expect(errorCallback, contains('notifyNativeRouteLossOnceV2'));
      expect(errorCallback, contains('signalMixroomMediaRouteMigrationV2 ('));
      expect(
        errorCallback,
        isNot(contains('isBluetoothCommunicationDuplexPolicyEnabled()')),
      );
      expect(errorCallback, isNot(contains('isBluetoothMediaPolicyEnabled()')));
      expect(notificationBridge, contains('CallVoidMethod'));
      expect(notificationBridge, contains('static_cast<jlong>(streamEpoch)'));
      expect(notificationBridge, contains('"(J)V"'));
      expect(notificationBridge, contains('environmentStatus != JNI_OK'));
      expect(notificationBridge, isNot(contains('reconfigure')));
      expect(notificationBridge, isNot(contains('Thread.sleep')));
    },
  );

  test('Bluetooth quality notice is route-proven and shown once per editor', () {
    final preflightStart = editor.indexOf(
      'Future<bool> _prepareAudioRecordingStartPreflight()',
    );
    final recordingStart = editor.indexOf(
      'Future<void> _startAudioRecordingJuce()',
      preflightStart,
    );
    final preflight = editor.substring(preflightStart, recordingStart);

    expect(preflight, contains('usingBluetoothDuplex'));
    expect(preflight, contains('_bluetoothRecordingQualityNoticeShown'));
    expect(
      preflight,
      contains(
        'Bluetooth microphone in use. Playback quality is reduced while recording.',
      ),
    );
  });

  test('V2 transport accepts only a verified V2-owned active input', () {
    final playStart = engine.indexOf(
      'bool JuceEngine::playPlaybackV2Android()',
    );
    final pauseStart = engine.indexOf('\nvoid JuceEngine::pause()', playStart);
    final play = engine.substring(playStart, pauseStart);

    expect(play, contains('wavCapture.isActive()'));
    expect(play, contains('shouldRouteLiveInputToGraphV2()'));
    expect(play, contains('androidV2RecordingPrepared'));
    expect(
      play,
      contains('desiredInputChannels > 0'),
    );
    expect(
      play,
      contains(
        'activeInputChannels == desiredInputChannels',
      ),
    );
    expect(
      play,
      contains('(activeInputChannels != 0 && !verifiedOwnedInputActive)'),
    );
    expect(play, isNot(contains('applyPreferredAudioDeviceSetup')));
  });

  test('live route apply proves a callback before validating recovery', () {
    final applyStart = plugin.indexOf(
      'private fun applyAudioRouteConfigurationV2(',
    );
    final cleanupStart = plugin.indexOf(
      'private fun cleanupFailedPlaybackV2()',
      applyStart,
    );
    final apply = plugin.substring(applyStart, cleanupStart);

    final callbackWait = apply.indexOf(
      'JuceBridge.waitForV2CallbackReadyJNI(1000)',
    );
    final validatedSnapshot = apply.indexOf(
      'capturePlaybackSnapshotV2(allowLifecycleTransition = true)',
      callbackWait,
    );
    expect(
      apply.indexOf('JuceBridge.reconfigurePlaybackV2JNI()'),
      lessThan(callbackWait),
    );
    expect(callbackWait, lessThan(validatedSnapshot));
    expect(apply, isNot(contains('Thread.sleep')));
    expect(apply, isNot(contains('postDelayed')));
  });

  test(
    'Android background closes capture and defers one reopen until foreground',
    () {
      final lifecycleStart = editor.indexOf(
        'void didChangeAppLifecycleState(AppLifecycleState state)',
      );
      final lifecycleEnd = editor.indexOf(
        'bool get _shouldDeferAndroidRouteRefresh',
        lifecycleStart,
      );
      final lifecycle = editor.substring(lifecycleStart, lifecycleEnd);

      expect(lifecycle, contains('AppLifecycleState.inactive'));
      expect(lifecycle, contains('!_isBluetoothV2Session'));
      expect(lifecycle, contains('_isEditorBackgroundState(state)'));
      expect(lifecycle, contains('_handleAndroidV2EditorBackgrounded()'));
      expect(lifecycle, contains('beginLocalInvalidationEpisode()'));
      expect(lifecycle, contains('_androidV2ForegroundRecoveryPending = true'));
      final backgroundStart = lifecycle.indexOf(
        'Future<void> _handleAndroidV2EditorBackgrounded()',
      );
      final backgroundEnd = lifecycle.indexOf(
        'Future<void> _handleIOSV2EditorBackgrounded()',
        backgroundStart,
      );
      final background = lifecycle.substring(backgroundStart, backgroundEnd);
      expect(
        background.indexOf('_androidV2ForegroundRecoveryPending = true'),
        lessThan(background.indexOf('if (_v2AudioSessionInvalidated) return')),
      );
      expect(background, contains('_cleanupV2InterruptedAudio'));
      expect(background, contains('_trackV2AudioSessionRecovery(cleanup)'));
      expect(
        background,
        isNot(contains('_recoverV2PlaybackAfterAudioSessionInvalidation')),
      );
      expect(
        lifecycle,
        contains('Recording stopped because Mixroom went to the background.'),
      );
      expect(
        lifecycle,
        isNot(
          contains(
            'Monitoring stopped because Mixroom went to the background.',
          ),
        ),
      );
      expect(background, contains('_backgroundRecordingImpactNotice()'));
      expect(background, contains('_androidV2ForegroundImpactNotice'));

      final resumeStart = editor.indexOf(
        'Future<void> _handleAndroidEditorResumed() async',
      );
      final resumeEnd = editor.indexOf('\n  Uri ', resumeStart);
      final resume = editor.substring(resumeStart, resumeEnd);
      expect(resume, contains('_resumeAndroidV2AudioAfterForeground()'));
      expect(resume, contains('_refreshMicrophonePermissionAndInputs()'));
      expect(
        resume,
        contains('_refreshAudioRouteInfo(refreshNativeRoute: false)'),
      );
      expect(resume, contains('final cleanup = _v2AudioSessionRecoveryFuture'));
      expect(resume, contains('if (cleanup != null) await cleanup'));
      expect(
        resume,
        contains(
          'WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed',
        ),
      );
      final claim = resume.indexOf(
        '_androidV2ForegroundRecoveryPending = false',
      );
      final recovery = resume.indexOf(
        '_recoverV2PlaybackAfterAudioSessionInvalidation',
      );
      final foregroundEpisode = resume.indexOf(
        'coordinator.beginLocalInvalidationEpisode()',
      );
      expect(claim, greaterThan(resume.indexOf('await cleanup')));
      expect(claim, lessThan(foregroundEpisode));
      expect(foregroundEpisode, lessThan(recovery));
      expect(resume, contains('_trackV2AudioSessionRecovery(recovery)'));
      expect(resume, contains('successNotice: successNotice'));

      final recoveryStart = editor.indexOf(
        'Future<void> _recoverV2PlaybackAfterAudioSessionInvalidation',
      );
      final recoveryEnd = editor.indexOf(
        '\n  Future<void> _synchronizeIOSRouteSafetyPositionV2',
        recoveryStart,
      );
      final invalidationRecovery = editor.substring(recoveryStart, recoveryEnd);
      expect(
        '_shouldDeferAndroidV2RecoveryUntilForeground'
            .allMatches(invalidationRecovery)
            .length,
        2,
      );
      expect(
        invalidationRecovery.indexOf(
          '_shouldDeferAndroidV2RecoveryUntilForeground',
        ),
        lessThan(
          invalidationRecovery.indexOf(
            'recoverPlaybackAfterIntentInvalidation()',
          ),
        ),
      );
      expect(
        invalidationRecovery.lastIndexOf(
          '_shouldDeferAndroidV2RecoveryUntilForeground',
        ),
        greaterThan(
          invalidationRecovery.indexOf(
            'recoverPlaybackAfterIntentInvalidation()',
          ),
        ),
      );

      final shutdownStart = editor.indexOf(
        'Future<void> _shutdownAudioEngineV2Aware()',
      );
      final shutdownEnd = editor.indexOf(
        '\n  Future<void> _performAudioEngineShutdownV2Aware()',
        shutdownStart,
      );
      expect(
        editor.substring(shutdownStart, shutdownEnd),
        contains('_androidV2ForegroundRecoveryPending = false'),
      );
    },
  );

  test('verified communication route remains observed during recording', () {
    expect(
      plugin,
      contains('private var communicationDeviceCallbackV2: Any? = null'),
    );
    expect(
      plugin,
      contains('if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)'),
    );
    expect(plugin, contains('operation.communicationRouteSelected.get()'));
    expect(plugin, contains('operation.cleanupClaimed.get()'));
    expect(plugin, contains('device?.id == expected.id'));
    expect(plugin, contains('"communicationDeviceChanged"'));
    expect(plugin, contains('operation.communicationRouteSelected.set(true)'));
  });

  test('recording file ownership crosses the publication boundary once', () {
    final safetyStart = editor.indexOf(
      'String? _enterV2AudioSessionSafetyBoundary',
    );
    final safetyEnd = editor.indexOf(
      '\n  void _trackV2AudioSessionRecovery',
      safetyStart,
    );
    final safety = editor.substring(safetyStart, safetyEnd);
    final stopStart = editor.indexOf('Future<void> _stopAudioRecordingJuce');
    final stopEnd = editor.indexOf('\n  Future<', stopStart + 20);
    final stop = editor.substring(stopStart, stopEnd);
    final ownershipGuard = stop.indexOf(
      '_ownsPendingUnpublishedRecordingPath(recordingPath)',
    );
    final publicationSerial = stop.indexOf(
      'final publicationTransportSerial = _transportCommandSerial',
    );
    final publication = stop.indexOf('await _undoManager.execute');
    final guardedResume = stop.indexOf(
      'publicationTransportSerial == _transportCommandSerial',
    );

    expect(safety, contains('_detachPendingUnpublishedRecordingPath()'));
    expect(safety, contains('++_transportCommandSerial'));
    expect(
      stop,
      contains(
        '_v2AudioSessionInvalidated ||\n'
        '          !_ownsPendingUnpublishedRecordingPath(recordingPath)',
      ),
    );
    expect(
      ownershipGuard,
      lessThan(stop.indexOf('_releasePendingRecordingForPublication')),
    );
    expect(
      stop.indexOf('_releasePendingRecordingForPublication(recordingPath)'),
      lessThan(publication),
    );
    expect(stop, contains('if (!recordingPublished)'));
    expect(
      publicationSerial,
      allOf(greaterThan(ownershipGuard), lessThan(publication)),
    );
    expect(
      stop,
      contains(
        'publicationTransportSerial == _transportCommandSerial &&\n'
        '          !_v2AudioSessionInvalidated &&\n'
        '          !_v2AudioSessionRecoveryInProgress',
      ),
    );
    expect(guardedResume, greaterThan(publication));
    expect(
      guardedResume,
      lessThan(
        stop.indexOf(
          'await _togglePlayPauseAudio(_safeAudioEditorStateSetter)',
          guardedResume,
        ),
      ),
    );
    expect(stop, isNot(contains('File(_recordingFilePath!)')));
  });

  test('editor shutdown is joined and disposes only an unpublished take', () {
    final shutdownStart = editor.indexOf(
      'Future<void> _shutdownAudioEngineV2Aware()',
    );
    final shutdownEnd = editor.indexOf(
      '\n  @override\n  void didChangeAppLifecycleState',
      shutdownStart,
    );
    final shutdown = editor.substring(shutdownStart, shutdownEnd);

    expect(shutdown, contains('final existing = _audioEngineShutdownFuture'));
    expect(shutdown, contains('if (existing != null) return existing'));
    expect(shutdown, contains('_audioEngineShutdownFuture = shutdown'));
    expect(shutdown, contains('_processAudioEngineShutdownFuture = shutdown'));
    expect(shutdown, contains('_detachPendingUnpublishedRecordingPath()'));
    expect(shutdown, contains('_deleteUncommittedRecordingFile'));
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
    expect(startup, contains('while (true)'));
    expect(startup, contains('final latestShutdown ='));
    expect(startup, contains('identical(latestShutdown, priorShutdown)'));
  });

  test(
    'Android shutdown and detach touch native state only for the executor-time owner',
    () {
      final shutdownStart = plugin.indexOf('"shutdown" -> {');
      final shutdownEnd = plugin.indexOf('"loadTrack" -> {', shutdownStart);
      final shutdown = plugin.substring(shutdownStart, shutdownEnd);
      final queuedExecutor = shutdown.indexOf(
        'audioLifecycleExecutorV2.execute {',
      );
      final queuedOwnership = shutdown.indexOf(
        'val ownsNativeEngineAtExecution = engineOwnership.ownsNativeEngine',
      );
      final queuedNativeShutdown = shutdown.indexOf(
        'JuceBridge.shutdownEngineSynchronouslyJNI()',
        queuedOwnership,
      );

      expect(queuedOwnership, greaterThanOrEqualTo(0));
      expect(queuedOwnership, greaterThan(queuedExecutor));
      expect(
        shutdown.indexOf('if (ownsNativeEngineAtExecution) {'),
        allOf(greaterThan(queuedOwnership), lessThan(queuedNativeShutdown)),
      );
      expect(shutdown, contains('if (ownsNativeEngineAtCall) {'));

      final detachStart = plugin.indexOf('override fun onDetachedFromEngine(');
      final detachEnd = plugin.indexOf(
        'private fun onNativeBluetoothDuplexDisconnectedV2(',
        detachStart,
      );
      final detach = plugin.substring(detachStart, detachEnd);
      expect(
        detach,
        contains(
          'val requiresEngineTeardown =\n'
          '      engineOwnership.ownsNativeEngine || v2SessionRequested',
        ),
      );
      final detachOwnership = detach.indexOf(
        'val ownsNativeEngineAtExecution = engineOwnership.ownsNativeEngine',
      );
      final detachExecutor = detach.indexOf(
        'audioLifecycleExecutorV2.execute {',
      );
      final detachNativeShutdown = detach.indexOf(
        'JuceBridge.shutdownEngineSynchronouslyJNI()',
        detachOwnership,
      );

      expect(detachOwnership, greaterThanOrEqualTo(0));
      expect(detachOwnership, greaterThan(detachExecutor));
      expect(
        detach.indexOf('if (ownsNativeEngineAtExecution) {'),
        allOf(greaterThan(detachOwnership), lessThan(detachNativeShutdown)),
      );
      expect(
        detach,
        contains('var nativeShutdownCompleted = !ownsNativeEngineAtExecution'),
      );
      expect(detach, contains('processV2TeardownGate.complete(completion)'));
    },
  );

  test('editor owns one cancellable JUCE event subscription', () {
    expect(
      editor,
      contains(
        '_juceEngineEventSubscription ??= JuceAudioEngine.eventsStream.listen(',
      ),
    );
    expect(
      editor,
      isNot(contains('JuceAudioEngine.initialiseEventListeners()')),
    );
  });
}
