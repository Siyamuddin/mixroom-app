import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String plugin;
  late String engine;
  late String editor;

  setUpAll(() {
    plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  test('iOS V2 recording uses built-in input and an output-only restore', () {
    final intentStart = plugin.indexOf(
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
    );
    final intentEnd = plugin.indexOf(
      '- (void)updateObservedOutputDeviceV2:',
      intentStart,
    );
    final intent = plugin.substring(intentStart, intentEnd);

    expect(intent, contains('reconfigureRecordingRouteV2ObjC:@""'));
    expect(intent, contains('getIOSAudioSessionPolicyFactsObjC'));
    expect(intent, contains('v2BuiltInDuplex'));
    expect(intent, contains('MixroomIOSInputIsBuiltInMicrophone'));
    expect(intent, contains('AVAudioSessionCategoryPlayAndRecord'));
    expect(intent, contains('reconfigurePlaybackRouteV2ObjC:@""'));
    final stopIndex = intent.indexOf('[JuceBridge stopRecordingObjC]');
    final reopenIndex = intent.indexOf(
      'reconfigurePlaybackRouteV2ObjC:@""',
      stopIndex,
    );
    expect(stopIndex, greaterThanOrEqualTo(0));
    expect(reopenIndex, greaterThan(stopIndex));
    expect(intent, isNot(contains('setPreferredInput:')));
    expect(intent, isNot(contains('setCategory:')));
    expect(intent, isNot(contains('setMode:')));
    expect(intent, isNot(contains('setActive:')));
    expect(intent, isNot(contains('refreshAudioRouteObjC')));
    expect('dispatch_after'.allMatches(intent), hasLength(1));
  });

  test('iOS V2 native writer requires an already prepared mono route', () {
    final openStart = engine.indexOf('bool JuceEngine::openRecordingInputV2');
    final quiesceStart = engine.indexOf(
      'bool JuceEngine::quiescePlaybackRouteV2',
      openStart,
    );
    final open = engine.substring(openStart, quiesceStart);
    final writerStart = engine.indexOf('bool JuceEngine::startRecordingToWav');
    final writerEnd = engine.indexOf(
      'void JuceEngine::stopRecording()',
      writerStart,
    );
    final writer = engine.substring(writerStart, writerEnd);

    expect(open, contains('const auto error = deviceManager.initialise('));
    expect(open, contains('bluetoothHfp ? 1 : 2'));
    expect(open, contains('desiredInputOpenChannels.store(1'));
    expect(writer, contains('validateRecordingRouteV2()'));
    expect(writer, contains('channelStart != 0'));
    expect(writer, contains('channelCount != 1'));
    final v2GuardStart = writer.indexOf('if (v2Recording)');
    final v2GuardEnd = writer.indexOf('else\n#endif', v2GuardStart);
    expect(
      writer.substring(v2GuardStart, v2GuardEnd),
      isNot(contains('applyPreferredAudioDeviceSetup(requiredInputs')),
    );
  });

  test('editor shares V2 intents across macOS and iOS without polling', () {
    final preflightStart = editor.indexOf(
      'Future<bool> _prepareAudioRecordingStartPreflight()',
    );
    final permissionStart = editor.indexOf(
      'Future<bool> _ensureMicrophonePermissionForRecording()',
      preflightStart,
    );
    final lifecycle = editor.substring(preflightStart, permissionStart);
    final pollingStart = editor.indexOf(
      'void _startRecordingRoutePolicyPolling()',
    );
    final pollingEnd = editor.indexOf(
      'void _stopRecordingRoutePolicyPolling()',
      pollingStart,
    );

    expect(lifecycle, contains('(Platform.isMacOS || Platform.isIOS)'));
    expect(lifecycle, contains('AudioRouteIntentV2.preparingRecording'));
    expect(lifecycle, contains('AudioRouteIntentV2.recording'));
    expect(lifecycle, contains('AudioRouteIntentV2.playbackOnly'));
    expect(lifecycle, contains('_restoreV2PlaybackOnlyAfterRecording'));
    expect(
      editor.substring(pollingStart, pollingEnd),
      contains('if (_isBluetoothV2Session) return;'),
    );
  });

  test('iOS A2DP recording rejects before permission or route mutation', () {
    final preflightStart = editor.indexOf(
      'Future<bool> _prepareAudioRecordingStartPreflight()',
    );
    final permissionIndex = editor.indexOf(
      '_ensureMicrophonePermissionForRecording()',
      preflightStart,
    );
    final snapshotIndex = editor.indexOf(
      'JuceAudioEngine.getAudioRouteSnapshotV2()',
      preflightStart,
    );
    final rejectionIndex = editor.indexOf(
      'Recording is unavailable while Bluetooth is the audio output.',
      preflightStart,
    );
    final intentIndex = editor.indexOf(
      'AudioRouteIntentV2.preparingRecording',
      preflightStart,
    );

    expect(snapshotIndex, greaterThan(preflightStart));
    expect(rejectionIndex, greaterThan(snapshotIndex));
    expect(rejectionIndex, lessThan(permissionIndex));
    expect(permissionIndex, lessThan(intentIndex));
  });

  test('iOS V2 route invalidation performs terminal cleanup', () {
    final abortStart = plugin.indexOf(
      'else if ([call.method isEqualToString:@"abortRecordingV2"])',
    );
    final abortEnd = plugin.indexOf(
      'else if ([call.method isEqualToString:@"stopAudioRouteMonitoringV2"])',
      abortStart,
    );
    final abort = plugin.substring(abortStart, abortEnd);

    expect(abort, contains('[JuceBridge stopRecordingObjC]'));
    expect(abort, contains('restorePlayback'));
    expect(abort, contains('if (terminal || !restored)'));
    expect(abort, contains('reconfigurePlaybackRouteV2ObjC:@""'));
    expect(abort, contains('[JuceBridge quiescePlaybackRouteV2ObjC:YES]'));
    expect(abort, isNot(contains('setPreferredInput:')));
    expect(abort, isNot(contains('setActive:')));

    final invalidationStart = editor.indexOf(
      'Future<void> _abortRecordingV2AfterRouteChange()',
    );
    final invalidationEnd = editor.indexOf(
      'Future<void> _synchronizeIOSRouteSafetyPositionV2',
      invalidationStart,
    );
    final invalidation = editor.substring(invalidationStart, invalidationEnd);
    expect(invalidation, contains('abortRecordingV2(restorePlayback: false)'));
    expect(invalidation, contains('await coordinator?.dispose()'));
    expect(invalidation, contains('await JuceAudioEngine.shutdown()'));
  });
}
