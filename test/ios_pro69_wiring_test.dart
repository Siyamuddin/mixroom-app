import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, isNonNegative, reason: 'Missing start marker: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end marker: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  late String editor;
  late String plugin;
  late String engine;

  setUpAll(() {
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
  });

  test('project loading and buffer edits keep iOS in automatic rate mode', () {
    expect(editor, contains('if (!Platform.isMacOS && !Platform.isIOS)'));
    final apply = between(
      editor,
      'Future<bool> _applyAudioEngineSettingsToNative({',
      'Future<bool> _prepareRecordingInputs({',
    );
    expect(apply, contains('Platform.isIOS ? 0 : requestedSampleRate ?? 0'));
    expect(apply, isNot(contains('Platform.isIOS ? _preferredDawSampleRate')));
  });

  test(
    'iOS sample rate is verified and rendered read-only at any valid rate',
    () {
      final sync = between(
        editor,
        'void _syncDawSampleRateFromRoute(',
        'int _normalizeDawSampleRate(',
      );
      expect(sync, contains('Platform.isMacOS || Platform.isIOS'));
      expect(sync, contains('verifiedDawOutputSampleRate(snapshot)'));
      expect(sync, contains('_hasVerifiedDawSampleRate = false'));

      final controls = between(
        editor,
        'Widget _buildDawAudioEngineSettingsControls()',
        'Widget _buildOutputSelector()',
      );
      expect(controls, contains("Platform.isIOS ? 'ios' : 'macos'"));
      expect(controls, contains("L10n.translate(context, 'Unavailable')"));
      final iosReadOnly = controls.indexOf('if (Platform.isIOS ||');
      final dropdown = controls.indexOf('DropdownButtonFormField<int>');
      expect(iosReadOnly, isNonNegative);
      expect(dropdown, greaterThan(iosReadOnly));
    },
  );

  test(
    'native automatic mode follows the session and observes clock changes',
    () {
      final hardware = between(
        plugin,
        '- (NSDictionary<NSString *, id> *)applyIOSHardwarePreferencesV2:',
        '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:',
      );
      expect(hardware, contains('requestedRate == 0.0'));
      expect(hardware, contains('followOutputSampleRate || bluetoothRoute'));
      expect(hardware, contains('self.preferredPlaybackSampleRateV2 = 0.0'));
      expect(
        hardware,
        isNot(
          contains(
            'self.preferredPlaybackSampleRateV2 = followOutputSampleRate',
          ),
        ),
      );

      final observer = between(
        plugin,
        '- (void)handleIOSAudioRouteChangeV2:(NSNotification *)notification {',
        '\n}\n#endif',
      );
      expect(observer, contains('playbackRateChanged'));
      expect(observer, contains('iosObservedPlaybackSampleRateV2'));
      expect(observer, contains('fabs(sessionRate -'));
      expect(observer, contains('!playbackRateChanged'));
      expect(observer, isNot(contains('dispatch_after')));
    },
  );

  test('input discovery is read-only and emits input-only status changes', () {
    final status = between(
      plugin,
      'static NSDictionary<NSString *, id> *MixroomIOSRecordingInputConfiguration(',
      'static NSString *MixroomIOSObservedRouteCause(',
    );
    expect(status, contains('@"channelStart": @0'));
    expect(status, contains('@"channelCount": @1'));
    expect(status, contains('session.availableInputs'));
    expect(status, contains('session.currentRoute.inputs'));
    expect(status, contains('sessionCanReportInputAvailability'));
    expect(status, contains('AVAudioSessionCategoryPlayAndRecord'));
    expect(status, contains('? [NSNull null]'));
    expect(status, isNot(contains('setPreferredInput')));
    expect(status, isNot(contains('setCategory')));
    expect(status, isNot(contains('setActive')));

    expect(plugin, contains('@"event": @"iosV2InputStatusChanged"'));
    expect(editor, contains("case 'iosV2InputStatusChanged':"));
    expect(editor, contains('_iosInputRefreshFuture ??='));
    expect(editor, contains('revision != _iosInputRefreshRevision'));
  });

  test('iOS native capture rejects rather than normalizes non-mono ranges', () {
    final intent = between(
      plugin,
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
      '- (void)setAudioRouteIntentV2:',
    );
    expect(
      intent,
      contains('recordingChannelStart == 0 && recordingChannelCount == 1'),
    );
    expect(intent, contains('effectiveChannelStart = recordingChannelStart'));
    expect(intent, contains('effectiveChannelCount = recordingChannelCount'));
    expect(intent, isNot(contains('routeForcesMono ? 0')));
    expect(intent, isNot(contains('routeForcesMono ? 1')));

    final writer = between(
      engine,
      'bool JuceEngine::startRecordingToWav',
      'RealtimeWavCapture::StopResult JuceEngine::stopRecording()',
    );
    expect(writer, contains('#if JUCE_IOS'));
    expect(writer, contains('channelStart != 0 || channelCount != 1'));
    expect(writer, contains('if (v2Recording)'));
  });

  test('editor preserves invalid iOS routes until explicit replacement', () {
    final selector = between(
      editor,
      'Widget _buildInputChannelRouteSelector()',
      'Widget _buildDawAudioEngineSettingsControls()',
    );
    expect(selector, contains('Platform.isIOS && _isBluetoothV2Session'));
    expect(selector, contains('SystemDefaultMonoInputChannelSelector'));
    expect(selector, contains('row?.inputChannelStart'));
    expect(selector, contains('row?.inputChannelCount'));
    expect(selector, contains('_scheduleProjectAutosave()'));

    final preflight = between(
      editor,
      'Future<bool> _prepareAudioRecordingStartPreflight()',
      'Future<void> _startAudioRecordingJuce()',
    );
    expect(preflight, contains('_validateIOSRecordingChannels()'));
    expect(
      preflight,
      contains('Platform.isMacOS || Platform.isAndroid || Platform.isIOS'),
    );
    expect(
      editor,
      contains('(Platform.isMacOS || Platform.isAndroid || Platform.isIOS) &&'),
    );
  });
}
