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

    expect(intent, contains('MixroomConfigureIOSRecordingSession'));
    expect(intent, contains('MixroomIOSBuiltInInputs'));
    expect(intent, contains('setPreferredInput:inputPort'));
    expect(intent, contains('reconfigureRecordingRouteV2ObjC:@""'));
    expect(intent, contains('MixroomIOSInputIsBuiltInMicrophone'));
    expect(intent, contains('AVAudioSessionCategoryPlayAndRecord'));
    expect(intent, contains('setPreferredInput:nil'));
    expect(intent, contains('MixroomConfigureIOSPlaybackSession'));
    expect(intent, contains('reconfigurePlaybackRouteV2ObjC:@""'));
    final stopIndex = intent.indexOf('[JuceBridge stopRecordingObjC]');
    final closeIndex = intent.indexOf(
      '[JuceBridge quiescePlaybackRouteV2ObjC:YES]',
      stopIndex,
    );
    final clearInputIndex = intent.indexOf(
      '[session setPreferredInput:nil',
      closeIndex,
    );
    final playbackSessionIndex = intent.indexOf(
      'MixroomConfigureIOSPlaybackSession',
      clearInputIndex,
    );
    final reopenIndex = intent.indexOf(
      'reconfigurePlaybackRouteV2ObjC:@""',
      playbackSessionIndex,
    );
    expect(stopIndex, greaterThanOrEqualTo(0));
    expect(closeIndex, greaterThan(stopIndex));
    expect(clearInputIndex, greaterThan(closeIndex));
    expect(playbackSessionIndex, greaterThan(clearInputIndex));
    expect(reopenIndex, greaterThan(playbackSessionIndex));
    expect(intent, isNot(contains('refreshAudioRouteObjC')));
    expect(intent, isNot(contains('dispatch_after')));
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

    expect(open, contains('deviceManager.initialise(1, 2, nullptr, true)'));
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

  test('iOS V2 abort finalizes recording and closes the device', () {
    final abortStart = plugin.indexOf(
      'else if ([call.method isEqualToString:@"abortRecordingV2"])',
    );
    final abortEnd = plugin.indexOf(
      'else if ([call.method isEqualToString:@"stopAudioRouteMonitoringV2"])',
      abortStart,
    );
    final abort = plugin.substring(abortStart, abortEnd);

    expect(abort, contains('[JuceBridge stopRecordingObjC]'));
    expect(abort, contains('[session setPreferredInput:nil'));
    expect(abort, contains('MixroomConfigureIOSPlaybackSession'));
    expect(abort, contains('[JuceBridge quiescePlaybackRouteV2ObjC:YES]'));
    expect(
      abort.indexOf('[JuceBridge quiescePlaybackRouteV2ObjC:YES]'),
      lessThan(abort.indexOf('[session setPreferredInput:nil')),
    );
  });
}
