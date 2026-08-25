import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String policyHeader;
  late String policyPatch;
  late String engine;
  late String plugin;

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
            'systemSelectedRoute &&\n'
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
}
