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
    expect(plugin, contains('prepareBuiltInRecordingV2(generation)'));
    expect(plugin, contains('restoreRecordingPlaybackV2(generation)'));
    expect(plugin, contains('recordingCancellationRequestedV2'));
    expect(plugin, contains('cleanupClaimed.compareAndSet(false, true)'));
  });

  test(
    'prepared recording opens once and capture never reopens the device',
    () {
      final prepareStart = engine.indexOf(
        'bool JuceEngine::prepareRecordingV2Android()',
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
        contains('deviceManager.initialise(\n        1,\n        2'),
      );
      expect(prepare, contains('liveInputMonitoringEnabled = false'));
      expect(prepare, contains('androidV2CallbackProofPending'));
      expect(
        start,
        contains('const bool v2Recording = androidV2RecordingPrepared'),
      );
      expect(start, contains('if (channelStart != 0 || channelCount != 1)'));
      expect(start, contains('else if (!applyPreferredAudioDeviceSetup'));
    },
  );

  test(
    'editor validates built-in source before permission and restores on Stop',
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
        contains('sourceOutput?.normalizedKind != AudioRouteKindV2.builtIn'),
      );
      expect(
        preflight.indexOf('getAudioRouteSnapshotV2()'),
        lessThan(
          preflight.indexOf('_ensureMicrophonePermissionForRecording()'),
        ),
      );
      expect(preflight, contains('AudioRouteIntentV2.preparingRecording'));
      expect(stop, contains('await JuceAudioEngine.stopRecording()'));
      expect(stop, contains('_restoreV2PlaybackOnlyAfterRecording()'));
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
    expect(capture, contains('JuceBridge.startRecordingJNI'));
  });

  test('V2 transport accepts only the verified active recording input', () {
    final playStart = engine.indexOf(
      'bool JuceEngine::playPlaybackV2Android()',
    );
    final pauseStart = engine.indexOf('\nvoid JuceEngine::pause()', playStart);
    final play = engine.substring(playStart, pauseStart);

    expect(play, contains('wavCapture.isActive()'));
    expect(play, contains('androidV2RecordingPrepared'));
    expect(
      play,
      contains('desiredInputOpenChannels.load(std::memory_order_relaxed) == 1'),
    );
    expect(
      play,
      contains('(activeInputChannels != 0 && !verifiedRecordingInputActive)'),
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

    expect(
      apply.indexOf('JuceBridge.reconfigurePlaybackV2JNI()'),
      lessThan(apply.indexOf('JuceBridge.waitForV2CallbackReadyJNI(1000)')),
    );
    expect(
      apply.indexOf('JuceBridge.waitForV2CallbackReadyJNI(1000)'),
      lessThan(apply.indexOf('capturePlaybackSnapshotV2()')),
    );
    expect(apply, isNot(contains('Thread.sleep')));
    expect(apply, isNot(contains('postDelayed')));
  });

  test(
    'Android lifecycle keeps transient overlays out of recording cleanup',
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
      expect(lifecycle, contains('cleanupBeforeRecovery: true'));
      expect(
        lifecycle,
        contains('Recording stopped because Mixroom went to the background.'),
      );

      final resumeStart = editor.indexOf(
        'Future<void> _handleAndroidEditorResumed() async',
      );
      final resumeEnd = editor.indexOf('\n  Uri ', resumeStart);
      final resume = editor.substring(resumeStart, resumeEnd);
      expect(
        resume,
        contains('final recovery = _v2AudioSessionRecoveryFuture'),
      );
      expect(resume, contains('await recovery;'));
    },
  );
}
