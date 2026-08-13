import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String policyHeader;
  late String vendorPatch;
  late String rebuildTool;
  late String engine;
  late String plugin;

  setUpAll(() {
    policyHeader = File(
      'juce_audio_engine/ios/Classes/MixroomIOSAudioSessionPolicy.h',
    ).readAsStringSync();
    vendorPatch = File(
      'tools/ios/juce_vendor/mixroom_ios_audio_session_policy.patch',
    ).readAsStringSync();
    rebuildTool = File(
      'tools/ios/rebuild_juce_vendor_libraries.sh',
    ).readAsStringSync();
    engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
  });

  test('private policy seam has only the three accepted ownership modes', () {
    expect(policyHeader, contains('legacyManaged = 0'));
    expect(policyHeader, contains('v2PlaybackOnly = 1'));
    expect(policyHeader, contains('v2BuiltInDuplex = 2'));
    expect(policyHeader, contains('activationCount'));
    expect(policyHeader, contains('mutationElapsedMilliseconds'));
    expect(policyHeader, isNot(contains('FlutterMethodChannel')));
  });

  test('JUCE policy configures category and mode before one activation', () {
    final policy = vendorPatch.substring(
      vendorPatch.indexOf('+        bool configureV2Session()'),
      vendorPatch.indexOf('+        void deactivateV2Session()'),
    );
    final category = policy.indexOf('[session setCategory:category');
    final mode = policy.indexOf('[session setMode:AVAudioSessionModeDefault');
    final activation = policy.indexOf('[session setActive:YES');
    final preferred = policy.indexOf('[session setPreferredInput:');

    expect(category, greaterThanOrEqualTo(0));
    expect(mode, greaterThan(category));
    expect(activation, greaterThan(mode));
    expect(preferred, greaterThan(activation));
    expect(policy, contains('AVAudioSessionCategoryOptionMixWithOthers'));
    expect(policy, contains('AVAudioSessionCategoryOptionDefaultToSpeaker'));
    expect(
      policy,
      isNot(contains('AVAudioSessionCategoryOptionAllowBluetooth')),
    );
  });

  test('engine closes old policy before installing every new V2 policy', () {
    final playback = engine.substring(
      engine.indexOf('bool JuceEngine::openPlaybackOutputOnlyV2'),
      engine.indexOf('bool JuceEngine::openRecordingInputV2'),
    );
    final duplex = engine.substring(
      engine.indexOf('bool JuceEngine::openRecordingInputV2'),
      engine.indexOf('bool JuceEngine::quiescePlaybackRouteV2'),
    );
    for (final section in <String>[playback, duplex]) {
      expect(
        section.indexOf('deviceManager.closeAudioDevice()'),
        lessThan(section.indexOf('mixroomIOSSetAudioSessionPolicy')),
      );
    }
    expect(playback, contains('v2PlaybackOnly'));
    expect(duplex, contains('v2BuiltInDuplex'));
  });

  test('accepted V2 plugin transitions contain no session setters', () {
    final intentStart = plugin.indexOf(
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:',
    );
    final intentEnd = plugin.indexOf(
      '- (void)updateObservedOutputDeviceV2:',
      intentStart,
    );
    final applyStart = plugin.indexOf(
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:(NSDictionary *)args {',
    );
    final applyEnd = plugin.indexOf(
      '- (void)stopAudioRouteMonitoringV2',
      applyStart,
    );
    final transitions =
        '${plugin.substring(intentStart, intentEnd)}\n${plugin.substring(applyStart, applyEnd)}';
    for (final setter in <String>[
      'setCategory:',
      'setMode:',
      'setActive:',
      'setPreferredInput:',
    ]) {
      expect(transitions, isNot(contains(setter)));
    }
  });

  test('ordinary iOS route recovery does not install a session policy', () {
    final handlerStart = plugin.indexOf(
      '- (void)handleIOSAudioRouteChangeV2:(NSNotification *)notification {',
    );
    final handlerEnd = plugin.indexOf(
      '\n- (NSDictionary<NSString *, id> *)startAudioRouteMonitoringV2',
      handlerStart,
    );
    final applyStart = plugin.indexOf(
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:'
      '(NSDictionary *)args {',
    );
    final applyEnd = plugin.indexOf(
      '\n- (void)stopAudioRouteMonitoringV2',
      applyStart,
    );
    final apply = plugin.substring(applyStart, applyEnd);
    final iosApplyStart = apply.indexOf(
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds()',
    );
    final ordinaryRecovery =
        '${plugin.substring(handlerStart, handlerEnd)}\n${apply.substring(iosApplyStart)}';

    expect(ordinaryRecovery, contains('pausePlaybackForRouteChangeV2ObjC'));
    expect(ordinaryRecovery, isNot(contains('reconfigurePlaybackRouteV2ObjC')));
    expect(ordinaryRecovery, isNot(contains('quiescePlaybackRouteV2ObjC')));
    expect(
      ordinaryRecovery,
      isNot(contains('mixroomIOSSetAudioSessionPolicy')),
    );
  });

  test('vendor rebuild is revision-checked and patches temporary trees', () {
    expect(rebuildTool, contains('EXPECTED_IOS_AUDIO_SOURCE_SHA'));
    expect(
      rebuildTool,
      contains('Device and simulator JUCE iOS sources differ'),
    );
    expect(rebuildTool, contains('prepare_header_tree'));
    expect(rebuildTool, contains('patch -d "\$destination_root" -p1'));
    expect(rebuildTool, contains('DEVICE_PATCHED_HEADERS'));
    expect(rebuildTool, contains('SIM_PATCHED_HEADERS'));
  });
}
