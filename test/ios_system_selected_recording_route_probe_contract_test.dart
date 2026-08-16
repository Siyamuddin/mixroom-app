import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:mixroom/helpers/bluetooth_route_report_v2.dart';

void main() {
  late String policyHeader;
  late String policyPatch;
  late String engine;
  late String plugin;
  late String editor;

  setUpAll(() {
    policyHeader = File(
      'juce_audio_engine/ios/Classes/MixroomIOSAudioSessionPolicy.h',
    ).readAsStringSync();
    policyPatch = File(
      'tools/ios/juce_vendor/mixroom_ios_audio_session_policy.patch',
    ).readAsStringSync();
    engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  test('system-selected policy permits routes without selecting an input', () {
    expect(policyHeader, contains('v2SystemSelectedDuplex = 4'));
    expect(policyPatch, contains('wantsSystemSelectedInput'));
    expect(
      policyPatch,
      contains('AVAudioSessionCategoryOptionAllowBluetoothA2DP |'),
    );
    expect(
      policyPatch,
      contains('AVAudioSessionCategoryOptionAllowBluetoothHFP |'),
    );
    expect(
      policyPatch,
      contains('AVAudioSessionCategoryOptionDefaultToSpeaker;'),
    );
    expect(policyPatch, contains('if (wantsBuiltInInput || wantsHfpInput)'));
    expect(
      policyPatch,
      contains(
        'if (wantsSystemSelectedInput)\n'
        '+            return finish(MixroomIOSAudioSessionPolicyStatus::ok);',
      ),
    );
  });

  test(
    'probe accepts only a stable source-preserving or A2DP-to-HFP route',
    () {
      expect(plugin, contains('MixroomIOSRouteHasSingleObservableDuplex'));
      expect(plugin, contains('MixroomIOSSystemSelectedTargetMatchesSource'));
      expect(
        plugin,
        contains(
          'MixroomIOSEndpointIdentitiesMatchStrict(sourceOutput, targetOutput)',
        ),
      );
      expect(
        plugin,
        contains('MixroomIOSOutputIsBluetoothMedia(sourceOutput)'),
      );
      expect(plugin, contains('MixroomIOSInputIsBluetoothHFP(targetInput)'));
      expect(plugin, contains('MixroomIOSOutputIsBluetoothHFP(targetOutput)'));
      expect(plugin, contains('systemRouteAcquisition'));
      expect(plugin, contains('physicalRouteInvalidation'));
      expect(
        plugin,
        isNot(
          contains(
            'systemSelectedProbe &&\n'
            '                           (![categoryOptions containsObject:',
          ),
        ),
      );
    },
  );

  test(
    'probe opens the settled channel shape and proves the project callback',
    () {
      final start = engine.indexOf(
        'bool JuceEngine::openPreparedSystemSelectedDuplexRouteV2(',
      );
      final end = engine.indexOf(
        'bool JuceEngine::reconfigureBluetoothDuplexRouteV2()',
        start,
      );
      final probe = engine.substring(start, end);

      expect(probe, contains('deviceManager.initialise('));
      expect(probe, contains('juce::jlimit(1, 2, outputChannels)'));
      expect(probe, contains('waitForFirstValidCallback('));
      expect(
        probe,
        contains('metronomeCallback->beginFirstValidCallbackProof()'),
      );
      expect(probe, contains('metronomeCallback->waitForFirstValidCallback'));
      expect(probe, isNot(contains('startRecordingToWav')));
      expect(probe, isNot(contains('recordWriter')));
      expect(probe, isNot(contains('liveInputMonitoringEnabled = true')));
    },
  );

  test(
    'debug action is writer-free and uses the existing serialized intent',
    () {
      final start = editor.indexOf(
        'Future<void> _runIOSSystemSelectedRouteProbeV2()',
      );
      final end = editor.indexOf('String _bluetoothImplementationLabel', start);
      final probe = editor.substring(start, end);

      expect(probe, contains('AudioRouteIntentV2.preparingRecording'));
      expect(probe, contains('systemSelectedProbe: true'));
      expect(probe, contains('AudioRouteIntentV2.playbackOnly'));
      expect(probe, isNot(contains('AudioRouteIntentV2.recording')));
      expect(probe, isNot(contains('_startAudioRecordingJuce')));
      expect(editor, contains('Run System Recording Route Check'));
    },
  );

  test('probe diagnostics retain selection mode without raw identities', () {
    const endpoint = AudioRouteEndpointV2(
      direction: AudioRouteDirectionV2.input,
      nativePortType: 'MicrophoneBuiltIn',
      normalizedKind: AudioRouteKindV2.builtIn,
      uid: 'private-input-uid',
      name: 'Private Input Name',
      channelCount: 1,
    );
    final probe = AudioRouteDuplexProbeFactsV2.fromMap(<String, dynamic>{
      'status': 'restored',
      'diagnosticCode': 'ok',
      'validationStage': 'duplexVerified',
      'categoryOptions': <String>[
        'mixWithOthers',
        'allowBluetoothA2DP',
        'allowBluetoothHFP',
      ],
      'selectionMode': 'systemSelected',
      'operationId': 4,
      'elapsedMs': 300,
      'duplexInput': endpoint.toRawMap(),
    });
    final snapshot = AudioRouteSnapshotV2(
      capturedAtUtc: DateTime.utc(2026, 8, 16),
      captureDurationMs: 1,
      implementation: BluetoothImplementationV2.v2,
      generation: 0,
      transitionId: 1,
      coordinatorManaged: true,
      captureConsistency: AudioRouteCaptureConsistencyV2.stable,
      inputs: const <AudioRouteEndpointV2>[],
      outputs: const <AudioRouteEndpointV2>[],
      session: const AudioSessionFactsV2(),
      juce: const JuceRouteFactsV2(),
      unavailableReasons: const <String, String>{},
      duplexProbe: probe,
    );
    final report = BluetoothRouteReportSerializerV2(
      sessionSalt: List<int>.filled(32, 5),
    ).encode(snapshot);

    expect(probe.selectionMode, 'systemSelected');
    expect(report, contains('"selectionMode":"systemSelected"'));
    expect(report, isNot(contains('private-input-uid')));
    expect(report, isNot(contains('Private Input Name')));
  });
}
