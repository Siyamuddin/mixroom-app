import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String plugin;
  late String recordingRoute;
  late String engine;
  late String bridge;

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
  });

  test('system-selected recording uses the existing serialized lifecycle', () {
    expect(plugin, isNot(contains('SYSTEM_SELECTED_MEDIA_PROBE')));
    expect(plugin, isNot(contains('systemSelectedMediaProbe')));
    expect(
      plugin,
      contains('prepareSystemSelectedDuplexV2(generation, mode, sourceOutput)'),
    );
    expect(plugin, contains('audioLifecycleExecutorV2.execute'));
    expect(plugin, contains('TimeUnit.SECONDS.toNanos(5)'));
  });

  test('generic recording never selects communication routing', () {
    final start = plugin.indexOf('private fun prepareSystemSelectedDuplexV2(');
    final end = plugin.indexOf(
      'private fun bluetoothCommunicationCandidatesV2(',
      start,
    );
    final preparation = plugin.substring(start, end);

    expect(preparation, contains('preparePlaybackOnlyModeV2()'));
    expect(
      preparation,
      contains('currentOutput.fingerprint != sourceOutput.fingerprint'),
    );
    expect(
      preparation,
      contains('sourceOutput.kind == AndroidRouteKindV2.BLUETOOTH_MEDIA'),
    );
    expect(preparation, contains('AndroidStreamPolicyV2.BLUETOOTH_MEDIA'));
    expect(preparation, contains('AndroidStreamPolicyV2.NORMAL'));
    expect(preparation, contains('prepareSystemSelectedMediaDuplexV2JNI()'));
    expect(
      preparation,
      contains('waitForV2CallbackReadyJNI(callbackTimeoutMillis)'),
    );
    expect(
      preparation,
      contains('AndroidSystemSelectedDuplexReadinessV2.validate'),
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
      expect(preparation, isNot(contains(forbidden)));
    }
  });

  test('native open uses the normal media policy and is capture capable', () {
    expect(bridge, contains('prepareSystemSelectedMediaDuplexV2JNI'));
    expect(engine, contains('return prepareDefaultDuplexV2Android();'));
    final start = engine.indexOf(
      'bool JuceEngine::prepareDefaultDuplexV2Android()',
    );
    final end = engine.indexOf(
      'bool JuceEngine::prepareBluetoothDuplexV2Android',
      start,
    );
    final open = engine.substring(start, end);
    expect(open, contains('deviceManager.initialise(\n        1,\n        2'));
    expect(open, contains('liveInputMonitoringEnabled = false'));
    expect(open, contains('androidV2RecordingPrepared = true'));
    expect(open, isNot(contains('androidV2DuplexProbePrepared')));
    expect(open, isNot(contains('startRecordingToWav')));
  });

  test('readiness preserves exact output without a route-kind allowlist', () {
    expect(
      recordingRoute,
      contains('object AndroidSystemSelectedDuplexReadinessV2'),
    );
    expect(
      recordingRoute,
      isNot(contains('source.kind != AndroidRouteKindV2.BLUETOOTH_MEDIA')),
    );
    expect(recordingRoute, isNot(contains('input.kind !in setOf(')));
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

  test(
    'production resolves one adapter and makes the shared open capture capable',
    () {
      final resolverStart = plugin.indexOf(
        'private fun prepareSystemSelectedRecordingV2(',
      );
      final resolverEnd = plugin.indexOf(
        'private fun prepareBluetoothDuplexV2(',
        resolverStart,
      );
      final resolver = plugin.substring(resolverStart, resolverEnd);
      final validationStart = plugin.indexOf(
        'private fun validatePreparedRecordingV2(',
      );
      final validationEnd = plugin.indexOf(
        'private fun audioModeName(',
        validationStart,
      );
      final validation = plugin.substring(validationStart, validationEnd);

      expect(
        recordingRoute,
        contains('object AndroidSystemRecordingRouteResolverV2'),
      );
      expect(
        recordingRoute,
        contains('apiLevel >= 29 && communicationCandidateCount == 1'),
      );
      expect(resolver, contains('bluetoothCommunicationCandidatesV2'));
      expect(
        resolver,
        contains('AndroidSystemRecordingRouteResolverV2.resolve('),
      );
      expect(resolver, contains('sourceKind = sourceOutput.kind'));
      expect(
        resolver,
        contains(
          'prepareSystemSelectedDuplexV2(generation, mode, sourceOutput)',
        ),
      );
      expect(resolver, contains('prepareBluetoothDuplexV2('));
      expect(resolver, contains('communicationCandidates.single()'));
      for (final forbidden in <String>[
        'Thread.sleep',
        'postDelayed',
        'while (',
        'productName',
        'address',
      ]) {
        expect(resolver, isNot(contains(forbidden)));
      }
      expect(
        validation,
        contains('AndroidRecordingRouteAdapterV2.SYSTEM_SELECTED'),
      );
      expect(
        validation,
        contains('AndroidSystemSelectedDuplexReadinessV2.validate'),
      );
      expect(engine, contains('return prepareDefaultDuplexV2Android();'));
      expect(plugin, contains('prepareSystemSelectedMediaDuplexV2JNI()'));
    },
  );

  test('diagnostics retain the system-selected route schema', () {
    expect(plugin, contains('"androidSystemSelectedMedia"'));
    expect(plugin, contains('operation.mode.reportsDuplexFacts()'));
  });
}
