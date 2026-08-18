import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String plugin;
  late String routeFacts;
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
    engine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.cpp',
    ).readAsStringSync();
    oboe = File(
      'juce_audio_engine/android/src/main/cpp/juce/modules/juce_audio_devices/native/juce_Oboe_android.cpp',
    ).readAsStringSync();
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  test('API 31 probe selects one SCO sink without names or addresses', () {
    final start = plugin.indexOf('private fun prepareBluetoothDuplexProbeV2(');
    final end = plugin.indexOf('private fun verifyRecordingIntentV2', start);
    final probe = plugin.substring(start, end);

    expect(probe, contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.S'));
    expect(probe, contains('audioManager.availableCommunicationDevices'));
    expect(probe, contains('AudioDeviceInfo.TYPE_BLUETOOTH_SCO'));
    expect(probe, contains('distinctBy { it.id }'));
    expect(probe, contains('candidates.size != 1'));
    expect(probe, contains('audioManager.setCommunicationDevice(candidate)'));
    expect(probe, isNot(contains('productName')));
    expect(probe, isNot(contains('address')));
  });

  test('selection is event-driven with one bounded operation deadline', () {
    final start = plugin.indexOf('private fun prepareBluetoothDuplexProbeV2(');
    final end = plugin.indexOf('private fun verifyRecordingIntentV2', start);
    final probe = plugin.substring(start, end);

    expect(probe, contains('OnCommunicationDeviceChangedListener'));
    expect(probe, contains('CountDownLatch(1)'));
    expect(probe, contains('TimeUnit.SECONDS.toNanos(5)'));
    expect(probe, contains('waitForV2CallbackReadyJNI(remainingMillis)'));
    expect(probe, isNot(contains('Thread.sleep')));
    expect(probe, isNot(contains('postDelayed')));
    expect(probe, isNot(contains('while (')));
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
      'bool JuceEngine::prepareBluetoothDuplexProbeV2Android()',
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
      contains('restorePlaybackOnlyV2(operation.sourceOutput, operation)'),
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
      observer.indexOf('AndroidIntentRouteObserverV2.classify('),
      lessThan(observer.indexOf('currentEffectiveRouteStateV2()')),
    );
    expect(plugin, contains('operation.routeInvalidated.set(true)'));
    expect(cleanup, isNot(contains('recordingOperationV2 = null')));
    expect(
      cleanup,
      contains('audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY'),
    );
    expect(deliver, contains('recordingOperationV2 = null'));
    expect(plugin, contains('"selectionMode" to "androidCommunicationDevice"'));
    expect(plugin, contains('"duplexProbe" to duplexProbeFactsV2'));
  });
}
