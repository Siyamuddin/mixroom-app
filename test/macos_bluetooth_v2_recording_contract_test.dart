import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS V2 recording accepts only built-in or classic Bluetooth output', () {
    final source = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final policyStart = source.indexOf(
      'static BOOL MixroomOutputSupportsV2Recording(',
    );
    final fingerprintStart = source.indexOf(
      'static NSString *MixroomEffectiveOutputFingerprint',
      policyStart,
    );
    final policy = source.substring(policyStart, fingerprintStart);
    final intentStart = source.indexOf(
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
    );
    final observerStart = source.indexOf(
      '- (void)updateObservedOutputDeviceV2:',
      intentStart,
    );
    final intent = source.substring(intentStart, observerStart);

    expect(policy, contains('kAudioDeviceTransportTypeBuiltIn'));
    expect(policy, contains('kAudioDeviceTransportTypeBluetooth'));
    expect(policy, contains('channels.integerValue >= 2'));
    expect(policy, isNot(contains('kAudioDeviceTransportTypeBluetoothLE')));
    expect(policy, contains('MixroomCoreAudioDeviceIsAlive'));
    expect(intent, contains('MixroomOutputSupportsV2Recording'));
    expect(intent, contains('MixroomUniqueBuiltInInput'));
    expect(intent, contains('MixroomSnapshotMatchesRecordingRoute'));
    expect(intent, contains('MixroomEffectiveOutputFingerprint'));
  });

  test('macOS V2 verifies both recording endpoints without profile guessing', () {
    final source = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final matchStart = source.indexOf(
      'static BOOL MixroomEndpointMatchesCoreAudioDevice(',
    );
    final snapshotStart = source.indexOf(
      'static BOOL MixroomSnapshotMatchesRecordingRoute(',
      matchStart,
    );
    final snapshotEnd = source.indexOf(
      'static NSString *MixroomFlutterAssetRootPath',
      snapshotStart,
    );
    final endpointMatch = source.substring(matchStart, snapshotStart);
    final snapshotMatch = source.substring(snapshotStart, snapshotEnd);

    expect(endpointMatch, contains('endpoint[@"uid"]'));
    expect(endpointMatch, contains('endpoint[@"nativePortType"]'));
    expect(endpointMatch, contains('endpoint[@"normalizedKind"]'));
    expect(snapshotMatch, contains('actualInput[@"normalizedKind"]'));
    expect(snapshotMatch, contains('@"builtIn"'));
    expect(snapshotMatch, contains('@"bluetoothDuplex"'));
    expect(snapshotMatch, contains('activeInputChannels'));
    expect(snapshotMatch, contains('activeOutputChannels'));
  });

  test('macOS V2 Play accepts only its active mono recording input', () {
    final source = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    final playStart = source.indexOf('void JuceEngine::play()');
    final playEnd = source.indexOf('\nvoid JuceEngine::pause()', playStart);
    final play = source.substring(playStart, playEnd);
    final v2End = play.indexOf('else if (missingOutputRoute)');
    final v2Guard = play.substring(0, v2End);

    expect(play, contains('verifiedRecordingInputActive'));
    expect(play, contains('recordingActive'));
    expect(
      play,
      contains('desiredInputOpenChannels.load(std::memory_order_relaxed) == 1'),
    );
    expect(play, contains('activeInputChannels == 1'));
    expect(
      play,
      contains('(activeInputChannels != 0 && !verifiedRecordingInputActive)'),
    );
    expect(v2Guard, isNot(contains('applyPreferredAudioDeviceSetup(')));
  });

  test('macOS V2 recording serializes playback and failure cleanup', () {
    final source = File('lib/screens/audio_editor.dart').readAsStringSync();
    final preflightStart = source.indexOf(
      'Future<bool> _prepareAudioRecordingStartPreflight()',
    );
    final recordingStart = source.indexOf(
      'Future<void> _startAudioRecordingJuce()',
      preflightStart,
    );
    final restoreStart = source.indexOf(
      'Future<bool> _restoreMacV2PlaybackOnlyAfterRecording()',
      recordingStart,
    );
    final permissionStart = source.indexOf(
      'Future<bool> _ensureMicrophonePermissionForRecording()',
      restoreStart,
    );
    final preflight = source.substring(preflightStart, recordingStart);
    final start = source.substring(recordingStart, restoreStart);
    final restore = source.substring(restoreStart, permissionStart);

    expect(preflight, contains('if (_isPlaying)'));
    expect(preflight, contains('await _pausePlayback()'));
    expect(
      preflight.indexOf('await _pausePlayback()'),
      lessThan(preflight.indexOf('AudioRouteIntentV2.preparingRecording')),
    );
    expect(start, contains('if (startPlaybackAfterRecorder && !_isPlaying)'));
    expect(
      start,
      contains('Recording stopped because playback could not start.'),
    );
    expect(restore, contains('await JuceAudioEngine.abortRecordingV2()'));
  });
}
