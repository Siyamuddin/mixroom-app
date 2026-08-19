import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String plugin;
  late String routeFacts;
  late String legacySco;
  late String engine;
  late String oboe;
  late String editor;

  setUpAll(() {
    plugin = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/JuceAudioEnginePlugin.kt',
    ).readAsStringSync();
    routeFacts = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/AndroidBluetoothDuplexRouteV2.kt',
    ).readAsStringSync();
    legacySco = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/AndroidLegacyScoRouteV2.kt',
    ).readAsStringSync();
    engine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.cpp',
    ).readAsStringSync();
    oboe = File(
      'juce_audio_engine/android/src/main/cpp/juce/modules/juce_audio_devices/native/juce_Oboe_android.cpp',
    ).readAsStringSync();
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  test(
    'API families share one transaction and select SCO only by type and ID',
    () {
      final start = plugin.indexOf('private fun prepareBluetoothDuplexV2(');
      final end = plugin.indexOf('private fun verifyRecordingIntentV2', start);
      final probe = plugin.substring(start, end);

      expect(
        probe,
        contains('AndroidBluetoothRouteSelectionModeV2.forApiLevel'),
      );
      expect(probe, contains('bluetoothCommunicationCandidatesV2('));
      expect(probe, contains('acquireBluetoothRouteV2('));
      expect(probe, contains('candidates.size != 1'));
      expect(probe, isNot(contains('productName')));
      expect(probe, isNot(contains('address')));
      expect(plugin, contains('audioManager.availableCommunicationDevices'));
      expect(plugin, contains('AudioManager.GET_DEVICES_OUTPUTS'));
      expect(plugin, contains('AudioDeviceInfo.TYPE_BLUETOOTH_SCO'));
      expect(plugin, contains('distinctBy { it.id }'));
      expect(
        plugin,
        contains('audioManager.setCommunicationDevice(candidate)'),
      );
      expect(legacySco, contains('COMMUNICATION_DEVICE'));
      expect(legacySco, contains('LEGACY_SCO'));
    },
  );

  test(
    'both selection adapters are event-driven under one bounded deadline',
    () {
      final start = plugin.indexOf('private fun prepareBluetoothDuplexV2(');
      final end = plugin.indexOf('private fun verifyRecordingIntentV2', start);
      final probe = plugin.substring(start, end);

      expect(plugin, contains('OnCommunicationDeviceChangedListener'));
      expect(plugin, contains('ACTION_SCO_AUDIO_STATE_UPDATED'));
      expect(plugin, contains('applicationContext.registerReceiver('));
      expect(plugin, contains('audioManager.startBluetoothSco()'));
      expect(plugin, contains('audioManager.stopBluetoothSco()'));
      expect(probe, contains('TimeUnit.SECONDS.toNanos(5)'));
      expect(probe, contains('waitForV2CallbackReadyJNI(remainingMillis)'));
      expect(probe, isNot(contains('Thread.sleep')));
      expect(probe, isNot(contains('postDelayed')));
      expect(probe, isNot(contains('while (')));
      expect(
        plugin,
        contains('operation.legacyScoState.beginAcquisition(stickyState)'),
      );
      expect(plugin, contains('operation.legacyScoState.claimStopRequest()'));
      final legacyAcquireStart = plugin.indexOf(
        'private fun acquireLegacyScoRouteV2(',
      );
      final legacyAcquireEnd = plugin.indexOf(
        'private fun acquireBluetoothRouteV2(',
        legacyAcquireStart,
      );
      final legacyAcquire = plugin.substring(
        legacyAcquireStart,
        legacyAcquireEnd,
      );
      final legacyReleaseStart = plugin.indexOf(
        'private fun releaseLegacyScoRouteV2(',
      );
      final legacyReleaseEnd = plugin.indexOf(
        'private fun currentBluetoothDuplexFactsV2(',
        legacyReleaseStart,
      );
      final legacyRelease = plugin.substring(
        legacyReleaseStart,
        legacyReleaseEnd,
      );
      expect(legacyAcquire, isNot(contains('unregisterReceiver')));
      expect(legacyAcquire, isNot(contains('Thread.sleep')));
      expect(legacyAcquire, isNot(contains('while (')));
      expect(
        legacyRelease,
        contains('unregisterLegacyScoReceiverV2(operation)'),
      );
      expect(legacyRelease, isNot(contains('Thread.sleep')));
      expect(legacyRelease, isNot(contains('while (')));
    },
  );

  test('legacy route remains probe-only until physical validation', () {
    final start = plugin.indexOf('private fun prepareBluetoothDuplexV2(');
    final end = plugin.indexOf('private fun verifyRecordingIntentV2', start);
    final probe = plugin.substring(start, end);

    expect(
      probe,
      contains(
        'Build.VERSION.SDK_INT < Build.VERSION_CODES.S &&\n'
        '      mode.allowsCapture()',
      ),
    );
    expect(plugin, contains('"physicalValidationPending" to'));
    expect(plugin, contains('AndroidBluetoothRouteSelectionModeV2.LEGACY_SCO'));
  });

  test('communication policy is mono route-native shared voice audio', () {
    expect(oboe, contains('StreamPolicy::bluetoothCommunicationDuplex'));
    expect(oboe, contains('oboe::Usage::VoiceCommunication'));
    expect(oboe, contains('oboe::ContentType::Speech'));
    expect(oboe, contains('oboe::InputPreset::VoiceCommunication'));
    expect(oboe, contains('oboe::SharingMode::Shared'));
    expect(oboe, contains('oboe::PerformanceMode::None'));
    expect(routeFacts, contains('activeInputChannels != 1'));
    expect(routeFacts, contains('activeOutputChannels != 1'));
    expect(
      routeFacts,
      contains('inputStream.sampleRateHz != outputStream.sampleRateHz'),
    );
  });

  test('probe proves the project callback but cannot record', () {
    final start = engine.indexOf(
      'bool JuceEngine::prepareBluetoothDuplexV2Android(bool recordingCapable)',
    );
    final end = engine.indexOf(
      'bool JuceEngine::waitForV2CallbackReady',
      start,
    );
    final probe = engine.substring(start, end);

    expect(probe, contains('deviceManager.initialise(1, 1'));
    expect(probe, contains('liveInputMonitoringEnabled = false'));
    expect(probe, contains('androidV2CallbackProofPending.store(true'));
    expect(
      probe,
      contains('deviceManager.addAudioCallback(metronomeCallback.get())'),
    );
    expect(probe, isNot(contains('startRecordingToWav')));
    expect(probe, contains('androidV2RecordingPrepared = recordingCapable'));
    expect(probe, contains('androidV2DuplexProbePrepared = !recordingCapable'));
    expect(
      engine,
      contains('wavCapture.isActive() || androidV2DuplexProbePrepared'),
    );
  });

  test('debug action uses the existing intent and stays writer-free', () {
    final start = editor.indexOf(
      'Future<void> _runAndroidBluetoothDuplexProbeV2()',
    );
    final end = editor.indexOf('String _bluetoothImplementationLabel', start);
    final probe = editor.substring(start, end);

    expect(probe, contains('AudioRouteIntentV2.preparingRecording'));
    expect(probe, contains('AudioRouteIntentOperationV2.systemSelectedProbe'));
    expect(probe, contains('AudioRouteIntentV2.playbackOnly'));
    expect(probe, isNot(contains('startRecording')));
    expect(probe, isNot(contains('_startAudioRecordingJuce')));
    expect(editor, contains('Run Bluetooth Input + Output Check'));
  });

  test('success restores exact A2DP and invalidation never forces it', () {
    final deliverStart = plugin.indexOf(
      'private fun deliverLifecycleResultV2(',
    );
    final restoreStart = plugin.indexOf('private fun restorePlaybackOnlyV2(');
    final deliver = plugin.substring(deliverStart, restoreStart);
    final cleanupStart = plugin.indexOf(
      'private fun cleanupRecordingOperationV2(',
    );
    final restore = plugin.substring(restoreStart, cleanupStart);
    final cleanupEnd = plugin.indexOf(
      'private fun prepareBuiltInRecordingV2',
      cleanupStart,
    );
    final cleanup = plugin.substring(cleanupStart, cleanupEnd);

    expect(
      cleanup,
      contains('AndroidRecordingCleanupDispositionV2.RESTORE_EXACT ->'),
    );
    expect(cleanup, contains('operation.sourceOutput,'));
    expect(cleanup, contains('cleanupDeadlineNanos,'));
    expect(
      deliver.indexOf('val completedPlaybackRecovery ='),
      greaterThan(deliver.indexOf('deliveredOutcome = IntentOutcomeV2(')),
    );
    expect(deliver, contains('deliveredOutcome.status == "success"'));
    expect(
      restore,
      contains('acceptSystemSelectedReplacement = expectedOutput == null'),
    );
    expect(restore, contains('val recoveringCurrentOutput ='));
    expect(restore, contains('!recoveringCurrentOutput &&'));
    expect(
      restore.indexOf('val recoveringCurrentOutput ='),
      lessThan(restore.indexOf('releaseSignal.first.await(')),
    );
    expect(
      restore,
      contains(
        'expectedPlaybackTransitionV2 = AndroidMediaRouteResolutionV2(actualOutput, "ok")',
      ),
    );
    expect(cleanup, contains('preparePlaybackOnlyModeV2()'));
    expect(cleanup, contains('operation.routeInvalidated.get()'));
    expect(
      restore.indexOf('releaseSignal.first.await('),
      lessThan(restore.indexOf('JuceBridge.reconfigurePlaybackV2JNI()')),
    );
    expect(
      restore.indexOf('addOnCommunicationDeviceChangedListener('),
      lessThan(restore.indexOf('preparePlaybackOnlyModeV2()')),
    );
    expect(
      restore.indexOf('preparePlaybackOnlyModeV2()'),
      lessThan(
        restore.indexOf('audioManager.communicationDevice?.id != target.id'),
      ),
    );
    expect(
      restore.indexOf('audioManager.communicationDevice?.id != target.id'),
      lessThan(restore.indexOf('releaseSignal.first.await(')),
    );
    final playbackCallbackStart = plugin.indexOf(
      'private val audioPlaybackCallbackV2',
    );
    final playbackCallbackEnd = plugin.indexOf(
      'private fun handleCommunicationDeviceChangedV2',
      playbackCallbackStart,
    );
    final playbackCallback = plugin.substring(
      playbackCallbackStart,
      playbackCallbackEnd,
    );
    expect(
      playbackCallback,
      contains('AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY'),
    );
    expect(playbackCallback, isNot(contains('lifecycleSignal')));
    expect(playbackCallback, isNot(contains('sourceOutput.id')));
    expect(
      restore,
      contains('JuceBridge.beginBluetoothMediaRouteMigrationV2JNI()'),
    );
    expect(
      restore,
      contains('expectedRoute.isBluetooth && restorationDeadlineNanos == null'),
    );
    expect(restore, contains('expectedRoute.endpoint?.id'));
    expect(
      plugin,
      contains(
        'restorePlaybackOnlyV2(expectedOutput = null, operation = operation)',
      ),
    );
    expect(
      restore,
      contains('JuceBridge.waitForBluetoothMediaRouteMigrationV2JNI('),
    );
    expect(
      restore,
      contains('JuceBridge.finishBluetoothMediaRouteMigrationV2JNI('),
    );
    expect(
      oboe,
      contains('mixroomMediaRouteMigrationStreamEpochV2 = streamEpoch;'),
    );
    expect(
      oboe,
      isNot(
        contains(
          'mixroomMediaRouteMigrationStreamEpochV2 == 0)\n'
          '            mixroomMediaRouteMigrationStreamEpochV2 = streamEpoch;',
        ),
      ),
    );
    final reopenMatches = 'JuceBridge.reconfigurePlaybackV2JNI()'
        .allMatches(restore)
        .toList();
    final migrationWaitIndex = restore.indexOf(
      'JuceBridge.waitForBluetoothMediaRouteMigrationV2JNI(',
    );
    expect(reopenMatches, hasLength(2));
    expect(reopenMatches.first.start, lessThan(migrationWaitIndex));
    expect(migrationWaitIndex, lessThan(reopenMatches.last.start));
    expect(
      reopenMatches.last.start,
      lessThan(restore.indexOf('AndroidPlaybackReadinessV2.validate(')),
    );
    expect(
      oboe,
      contains('signalMixroomMediaRouteMigrationV2 (disconnectedStreamEpoch)'),
    );
    expect(
      oboe,
      contains(
        'notifyAndroidBluetoothDuplexDisconnectedV2 (disconnectedStreamEpoch)',
      ),
    );
    expect(
      oboe.indexOf(
        'signalMixroomMediaRouteMigrationV2 (disconnectedStreamEpoch)',
      ),
      lessThan(
        oboe.indexOf(
          'notifyAndroidBluetoothDuplexDisconnectedV2 (disconnectedStreamEpoch)',
        ),
      ),
    );
    expect(oboe, contains('waitForBluetoothMediaRouteMigration'));
    expect(
      restore,
      contains(
        'removeOnCommunicationDeviceChangedListener(releaseSignal.second)',
      ),
    );
    expect(restore, contains('callbackRemainingNanos'));
    expect(
      restore,
      contains('waitForV2CallbackReadyJNI(callbackTimeoutMillis)'),
    );
    expect(restore, isNot(contains('expectedPlaybackTransitionV2 = null')));
    expect(deliver, contains('mainHandler.post {'));
    expect(
      deliver.indexOf('mainHandler.post {'),
      lessThan(deliver.indexOf('lifecycleTransitionInProgressV2 = false')),
    );
    expect(deliver, contains('expectedPlaybackTransitionV2 = null'));
    expect(plugin, contains('AndroidIntentRouteObserverV2.classify('));
    expect(
      plugin,
      contains('AndroidIntentRouteDecisionV2.INFORMATIONAL) return'),
    );
    final observerStart = plugin.indexOf(
      'private fun handleAudioRouteSignalV2(',
    );
    final observerEnd = plugin.indexOf(
      'private fun routeTransitionResultV2(',
      observerStart,
    );
    final observer = plugin.substring(observerStart, observerEnd);
    expect(
      observer.indexOf(
        'AndroidIntentRouteObserverV2.isSelfGeneratedPlaybackActivity(',
      ),
      lessThan(observer.indexOf('AndroidIntentRouteObserverV2.classify(')),
    );
    expect(observer, contains('lifecycleTransitionInProgressV2'));
    expect(observer, contains('operation?.cleanupClaimed?.get() == true'));
    expect(
      observer.indexOf('AndroidIntentRouteObserverV2.classify('),
      lessThan(observer.indexOf('currentEffectiveRouteStateV2()')),
    );
    expect(plugin, contains('operation.routeInvalidated.set(true)'));
    expect(
      observer,
      contains('operation.routeInvalidated.compareAndSet(false, true)'),
    );
    expect(
      plugin,
      contains('onNativeBluetoothDuplexDisconnectedV2(streamEpoch: Long)'),
    );
    expect(
      plugin,
      contains('AndroidRouteSignalKindV2.NATIVE_STREAM_DISCONNECTED'),
    );
    expect(cleanup, isNot(contains('recordingOperationV2 = null')));
    expect(
      cleanup,
      contains('audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY'),
    );
    expect(deliver, contains('completed.phase = "playbackCommitted"'));
    expect(deliver, contains('completedPlaybackRecovery'));
    expect(
      deliver,
      contains('completed.routeInvalidated.get() && completedPlaybackRecovery'),
    );
    expect(
      observer,
      contains('AndroidCommittedRecoveryOwnershipV2.ownsLateSignal('),
    );
    expect(
      observer,
      contains('adoptCurrentPlaybackAfterCommittedRecoveryV2()'),
    );
    expect(
      plugin,
      contains('operation.bluetoothSelectionMode?.diagnosticName'),
    );
    expect(plugin, contains('"duplexProbe" to duplexProbeFactsV2'));
  });
}
