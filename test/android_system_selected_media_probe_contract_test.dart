import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String plugin;
  late String recordingRoute;
  late String engine;
  late String bridge;
  late String editor;

  setUpAll(() {
    plugin = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/JuceAudioEnginePlugin.kt',
    ).readAsStringSync();
    recordingRoute = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/AndroidRecordingRouteV2.kt',
    ).readAsStringSync();
    engine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.cpp',
    ).readAsStringSync();
    bridge = File(
      'juce_audio_engine/android/src/main/java/com/mixroom/juce_audio_engine/JuceBridge.kt',
    ).readAsStringSync();
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  test('probe is a private mode on the existing serialized lifecycle', () {
    expect(plugin, contains('SYSTEM_SELECTED_MEDIA_PROBE'));
    expect(plugin, contains('"systemSelectedMediaProbe" ->'));
    expect(
      plugin,
      contains(
        'prepareSystemSelectedMediaDuplexProbeV2(generation, operationMode)',
      ),
    );
    expect(plugin, contains('audioLifecycleExecutorV2.execute'));
    expect(plugin, contains('TimeUnit.SECONDS.toNanos(5)'));
    expect(editor, contains('Run System Recording Route Check'));
    expect(
      editor,
      contains('AudioRouteIntentOperationV2.systemSelectedMediaProbe'),
    );
  });

  test('media probe never selects communication routing or capture', () {
    final start = plugin.indexOf(
      'private fun prepareSystemSelectedMediaDuplexProbeV2(',
    );
    final end = plugin.indexOf(
      'private fun bluetoothCommunicationCandidatesV2(',
      start,
    );
    final probe = plugin.substring(start, end);

    expect(probe, contains('preparePlaybackOnlyModeV2()'));
    expect(
      probe,
      contains(
        'setAndroidStreamPolicyV2(AndroidStreamPolicyV2.BLUETOOTH_MEDIA)',
      ),
    );
    expect(probe, contains('prepareSystemSelectedMediaDuplexV2JNI()'));
    expect(probe, contains('waitForV2CallbackReadyJNI(callbackTimeoutMillis)'));
    expect(
      probe,
      contains('AndroidSystemSelectedMediaDuplexReadinessV2.validate'),
    );
    for (final forbidden in <String>[
      'setCommunicationDevice',
      'startBluetoothSco',
      'stopBluetoothSco',
      'productName',
      'address',
      'startRecordingJNI',
      'Thread.sleep',
      'postDelayed',
      'while (',
    ]) {
      expect(probe, isNot(contains(forbidden)));
    }
  });

  test(
    'native open uses the normal media policy and is not record capable',
    () {
      expect(bridge, contains('prepareSystemSelectedMediaDuplexV2JNI'));
      expect(engine, contains('return prepareDefaultDuplexV2Android(false);'));
      final start = engine.indexOf(
        'bool JuceEngine::prepareDefaultDuplexV2Android(bool recordingCapable)',
      );
      final end = engine.indexOf(
        'bool JuceEngine::prepareBluetoothDuplexV2Android',
        start,
      );
      final open = engine.substring(start, end);
      expect(
        open,
        contains('deviceManager.initialise(\n        1,\n        2'),
      );
      expect(open, contains('liveInputMonitoringEnabled = false'));
      expect(open, contains('androidV2RecordingPrepared = recordingCapable'));
      expect(
        open,
        contains('androidV2DuplexProbePrepared = !recordingCapable'),
      );
      expect(open, isNot(contains('startRecordingToWav')));
    },
  );

  test('readiness preserves exact A2DP and rejects SCO', () {
    expect(
      recordingRoute,
      contains('object AndroidSystemSelectedMediaDuplexReadinessV2'),
    );
    expect(
      recordingRoute,
      contains('source.kind != AndroidRouteKindV2.BLUETOOTH_MEDIA'),
    );
    expect(
      recordingRoute,
      contains('output.fingerprint != source.fingerprint'),
    );
    expect(
      recordingRoute,
      contains('facts.audioMode != AudioManager.MODE_NORMAL'),
    );
    expect(
      recordingRoute,
      contains('facts.bluetoothCommunicationDeviceSelected'),
    );
    expect(recordingRoute, contains('facts.bluetoothScoActive'));
    expect(recordingRoute, contains('inputStream.routedDeviceId != input.id'));
    expect(
      recordingRoute,
      contains('outputStream.routedDeviceId != output.id'),
    );
    expect(recordingRoute, contains('!facts.callbackAttached'));
  });

  test('debug action restores playback and cannot start a writer', () {
    final start = editor.indexOf(
      'Future<void> _runAndroidSystemSelectedMediaProbeV2()',
    );
    final end = editor.indexOf('String _bluetoothImplementationLabel', start);
    final probe = editor.substring(start, end);
    expect(probe, contains('AudioRouteIntentV2.preparingRecording'));
    expect(probe, contains('AudioRouteIntentV2.playbackOnly'));
    expect(probe, contains('exactSourceOutput'));
    expect(probe, isNot(contains('_startAudioRecordingJuce')));
    expect(probe, isNot(contains('startRecording(')));
  });

  test(
    'diagnostics identify the media-selection proof without schema changes',
    () {
      expect(plugin, contains('"androidSystemSelectedMedia"'));
      expect(plugin, contains('operation.mode.reportsDuplexFacts()'));
      expect(editor, contains('_copyBluetoothReportV2'));
    },
  );
}
