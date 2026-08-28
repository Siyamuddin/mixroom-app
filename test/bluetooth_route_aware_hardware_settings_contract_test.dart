import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, isNonNegative, reason: 'Missing start marker: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end marker: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  late String editor;
  late String coordinator;
  late String api;
  late String applePlugin;
  late String appleEngine;
  late String androidEngine;
  late String androidJuce;

  setUpAll(() {
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    coordinator = File(
      'juce_audio_engine/lib/audio_route_coordinator_v2.dart',
    ).readAsStringSync();
    api = File(
      'juce_audio_engine/lib/juce_audio_engine.dart',
    ).readAsStringSync();
    applePlugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    appleEngine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    androidEngine = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/'
      'juce_audio_engine/JuceAudioEnginePlugin.kt',
    ).readAsStringSync();
    androidJuce = File(
      'juce_audio_engine/android/src/main/cpp/juce/modules/'
      'juce_audio_devices/native/juce_Oboe_android.cpp',
    ).readAsStringSync();
  });

  test('macOS and iOS retain the main hardware-settings controls', () {
    expect(
      editor,
      contains(
        'bool get _supportsDawAudioEngineDeviceSettings =>\n'
        '      Platform.isMacOS || Platform.isIOS;',
      ),
    );
    expect(
      editor,
      contains("labelText: L10n.translate(context, 'Sample Rate')"),
    );
    expect(
      editor,
      contains("labelText: L10n.translate(context, 'Sample Buffer Size')"),
    );
    expect(editor, contains('static const List<int> _dawSampleRateOptions'));
    expect(editor, contains('static const List<int> _dawBufferSizeOptions'));
    expect(
      editor,
      isNot(
        contains(
          'Hardware settings are managed by Bluetooth 2.0 in this checkpoint.',
        ),
      ),
    );
    expect(editor, isNot(contains('Bluetooth Safe Mode')));
  });

  test('V2 settings are serialized without a new channel or state', () {
    expect(coordinator, contains('configurePlaybackHardware'));
    expect(coordinator, contains('updateHardwarePreferences: true'));
    expect(api, contains("'updateHardwarePreferences': true"));
    expect(api, contains("'preferredSampleRateHz': preferredSampleRateHz"));
    expect(api, contains("'preferredBufferFrames': preferredBufferFrames"));
    expect(applePlugin, contains('self.iosLifecycleTransitionActiveV2 = YES;'));
    expect(
      applePlugin,
      contains('dispatch_async(MixroomIOSLifecycleQueue(), ^{'),
    );
    expect(
      api.split("'applyAudioRouteConfigurationV2'").length,
      greaterThan(1),
    );
    expect(
      coordinator,
      isNot(contains('AudioRouteCoordinatorStateV2.hardwareSettings')),
    );
  });

  test('Apple policy is metadata-based and keeps Bluetooth native', () {
    expect(applePlugin, contains('MixroomIOSOutputIsBluetooth(output)'));
    expect(applePlugin, contains('MixroomTransportIsBluetooth'));
    expect(applePlugin, contains('MixroomMacPlaybackOpenPlan'));
    expect(applePlugin, contains('? session.sampleRate : preferredRate'));
    expect(applePlugin, contains('? nativeBuffer : preferredBuffer'));
    expect(
      applePlugin,
      contains('self.preferredPlaybackSampleRateV2 = bluetoothRoute'),
    );
    expect(
      applePlugin,
      contains('self.preferredPlaybackBufferFramesV2 = bluetoothRoute'),
    );
    expect(applePlugin, isNot(contains('Bluetooth connected — switched')));
    expect(appleEngine, contains('setup.sampleRate = preferredSampleRate'));
    expect(appleEngine, contains('setup.bufferSize = preferredBufferFrames'));
  });

  test(
    'macOS settles supported CoreAudio settings before strict JUCE open',
    () {
      final macSettings = _between(
        applePlugin,
        '- (NSDictionary<NSString *, id> *)applyMacHardwarePreferencesV2:',
        '- (NSDictionary<NSString *, id> *)applyIOSHardwarePreferencesV2:',
      );
      final quiesce = macSettings.indexOf(
        '[JuceBridge quiescePlaybackRouteV2ObjC:YES]',
      );
      final settle = macSettings.indexOf(
        'settleMacOutputHardwareSettingsV2:target',
      );
      final reopen = macSettings.indexOf(
        'reconfigureMacPlaybackRouteV2ObjC:target[@"name"]',
      );

      expect(
        applePlugin,
        contains('kAudioDevicePropertyAvailableNominalSampleRates'),
      );
      expect(applePlugin, contains('kAudioDevicePropertyBufferFrameSizeRange'));
      expect(applePlugin, contains('signalMacHardwareSettingsConditionV2'));
      expect(applePlugin, contains('hardware_settings_settle_timeout'));
      expect(quiesce, isNonNegative);
      expect(settle, greaterThan(quiesce));
      expect(reopen, greaterThan(settle));
      expect(macSettings, isNot(contains('sleep(')));
      expect(macSettings, isNot(contains('usleep(')));
    },
  );

  test('Android Bluetooth policy remains route-native and stability-first', () {
    expect(androidEngine, contains('AndroidStreamPolicyV2.BLUETOOTH_MEDIA'));
    expect(androidJuce, contains('oboe::kUnspecified'));
    expect(androidJuce, contains('oboe::PerformanceMode::None'));
    expect(androidJuce, contains('oboe::SharingMode::Shared'));
    expect(androidJuce, contains('getFramesPerBurst'));
    expect(androidJuce, contains('getBufferCapacityInFrames'));
  });

  test('playback preferences do not define the recording writer clock', () {
    expect(applePlugin, contains('startMacInputRecordingV2ObjC'));
    expect(
      applePlugin,
      isNot(
        contains(
          'startMacInputRecordingV2ObjC:self.preferredPlaybackSampleRateV2',
        ),
      ),
    );
  });

  test(
    'Apple transport resumes only after route and callback verification',
    () {
      final macSettings = _between(
        applePlugin,
        '- (NSDictionary<NSString *, id> *)applyMacHardwarePreferencesV2:',
        '- (NSDictionary<NSString *, id> *)applyIOSHardwarePreferencesV2:',
      );
      final iosSettings = _between(
        applePlugin,
        '- (NSDictionary<NSString *, id> *)applyIOSHardwarePreferencesV2:',
        '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:',
      );

      for (final settings in <String>[macSettings, iosSettings]) {
        final reopen = settings.indexOf('routeReconfigured = opened');
        final resume = settings.indexOf('[JuceBridge playObjC]');
        final verification = settings.lastIndexOf('SnapshotMatches', resume);
        expect(reopen, isNonNegative);
        expect(verification, greaterThan(reopen));
        expect(resume, greaterThan(verification));
        expect(settings, contains('success && routeReconfigured'));
        expect(settings, isNot(contains('preserveTransportState')));
      }
      expect(appleEngine, isNot(contains('preserveTransportState')));
    },
  );
}
