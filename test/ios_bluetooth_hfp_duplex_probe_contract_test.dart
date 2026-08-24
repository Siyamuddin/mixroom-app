import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:mixroom/helpers/bluetooth_route_report_v2.dart';

void main() {
  late String policyPatch;
  late String engine;
  late String engineHeader;
  late String effectsHeader;
  late String bridge;
  late String plugin;
  late String editor;

  setUpAll(() {
    policyPatch = File(
      'tools/ios/juce_vendor/mixroom_ios_audio_session_policy.patch',
    ).readAsStringSync();
    engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    engineHeader = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    effectsHeader = File(
      'juce_audio_engine/ios/Classes/NativeEffects.h',
    ).readAsStringSync();
    bridge = File(
      'juce_audio_engine/ios/Classes/JuceBridge.mm',
    ).readAsStringSync();
    plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  test('JUCE owns one native HFP policy without A2DP recording options', () {
    final configureStart = policyPatch.indexOf(
      '+        bool configureV2Session()',
    );
    final configureEnd = policyPatch.indexOf(
      '+        void deactivateV2Session()',
      configureStart,
    );
    final configure = policyPatch.substring(configureStart, configureEnd);

    expect(configure, contains('v2BluetoothHfpDuplex'));
    expect(
      configure,
      contains('AVAudioSessionCategoryOptionAllowBluetoothHFP'),
    );
    expect(configure, contains('AVAudioSessionPortBluetoothHFP'));
    expect(configure, contains('port.UID.length > 0'));
    expect(configure, contains('setPreferredInput:matchingInputs.firstObject'));
    expect(
      configure.indexOf('[session setActive:YES'),
      lessThan(configure.indexOf('[session setPreferredInput:')),
    );
    expect(
      configure,
      contains(
        'else if (wantsHfpInput)\n'
        '+                options |= '
        'AVAudioSessionCategoryOptionAllowBluetoothHFP;',
      ),
    );
    expect(configure, isNot(contains('sleep')));
    expect(configure, isNot(contains('dispatch_after')));
  });

  test(
    'writer-free engine route hands the open HFP device to the project callback',
    () {
      final start = engine.indexOf(
        'bool JuceEngine::prepareBluetoothDuplexSessionV2()',
      );
      final end = engine.indexOf(
        'bool JuceEngine::validateRecordingRouteV2()',
        start,
      );
      final route = engine.substring(start, end);

      expect(route, contains('mixroomIOSPrepareAudioSessionPolicy()'));
      expect(
        route,
        contains(
          'openPreparedSystemSelectedDuplexRouteV2(timeoutMilliseconds, 1)',
        ),
      );
      expect(route, contains('deviceManager.initialise('));
      expect(route, contains('v2-system-selected-duplex-probe'));
      expect(
        route,
        contains(
          'deviceManager.addAudioCallback('
          'iosBluetoothDuplexProbeCallback.get())',
        ),
      );
      expect(route, contains('detachIOSBluetoothDuplexProbeCallback()'));
      expect(
        route,
        contains('metronomeCallback->beginFirstValidCallbackProof()'),
      );
      expect(
        route,
        contains('deviceManager.addAudioCallback(metronomeCallback.get())'),
      );
      expect(route, contains('metronomeCallback->waitForFirstValidCallback'));
      expect(route, isNot(contains('startRecordingToWav')));
      expect(route, isNot(contains('recordWriter')));
      expect(route, isNot(contains('armOutputSafetyForCurrentRoute')));
      expect(bridge, contains('prepareBluetoothDuplexSessionV2ObjC'));
      expect(bridge, contains('openPreparedBluetoothDuplexRouteV2ObjC'));
      expect(bridge, contains('reconfigureBluetoothDuplexRouteV2ObjC'));
    },
  );

  test('isolated HFP callback can only validate and clear audio', () {
    final start = engineHeader.indexOf(
      'class IOSBluetoothDuplexProbeCallback final',
    );
    final probeCallback = engineHeader.substring(start);
    final io = probeCallback.indexOf('audioDeviceIOCallbackWithContext');
    final clear = probeCallback.indexOf(
      'juce::FloatVectorOperations::clear',
      io,
    );
    final count = probeCallback.indexOf('callbackCount.fetch_add', io);

    expect(start, greaterThanOrEqualTo(0));
    expect(probeCallback, contains('inputChannels == 1'));
    expect(probeCallback, contains('outputChannels > 0'));
    expect(clear, greaterThan(io));
    expect(clear, lessThan(count));
    for (final forbidden in <String>[
      'AudioProcessorPlayer',
      'processBlock',
      'captureInput',
      'advanceTransport',
      'NativeEffects',
      'recordWriter',
      'new ',
    ]) {
      expect(probeCallback, isNot(contains(forbidden)));
    }
  });

  test('plugin owns one bounded source-target operation', () {
    final intentStart = plugin.indexOf(
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:'
      '(NSDictionary *)args {',
    );
    final intentEnd = plugin.indexOf(
      '- (void)updateObservedOutputDeviceV2:',
      intentStart,
    );
    final intent = plugin.substring(intentStart, intentEnd);
    final observerStart = plugin.indexOf(
      '- (void)handleIOSAudioRouteChangeV2:(NSNotification *)notification {',
    );
    final observerEnd = plugin.indexOf(
      '- (NSDictionary<NSString *, id> *)startAudioRouteMonitoringV2',
      observerStart,
    );
    final observer = plugin.substring(observerStart, observerEnd);

    expect(intent, contains('iosIntentOperationSourceFingerprintV2'));
    expect(intent, contains('iosIntentOperationPendingFingerprintV2'));
    expect(intent, contains('iosIntentOperationTargetFingerprintV2'));
    expect(intent, contains('MixroomIOSInputIsBluetoothHFP'));
    expect(intent, contains('MixroomIOSOutputIsBluetoothHFP'));
    expect(intent, contains('MixroomIOSEndpointIdentitiesMatchStrict'));
    expect(intent, contains('v2BluetoothHfpDuplex'));
    expect(
      intent,
      isNot(contains('![categoryOptions containsObject:@"allowBluetoothHFP"]')),
    );
    expect(intent, contains('reconfigurePlaybackRouteV2ObjC:@""'));
    expect(observer, contains('matchesSource || matchesTarget'));
    expect(observer, contains('MixroomIOSRouteIsBluetoothHFPDuplex(route)'));
    expect(observer, contains('audioInterruptionBegan'));
    expect(observer, contains('audioInterruptionEnded'));
    expect(observer, contains('iosIntentOperationCancelledV2 = YES'));
    for (final forbidden in <String>[
      'setCategory:',
      'setMode:',
      'setActive:',
      'setPreferredInput:',
      'sleep(',
    ]) {
      expect(intent, isNot(contains(forbidden)));
      expect(observer, isNot(contains(forbidden)));
    }
    expect('dispatch_after'.allMatches(intent), hasLength(1));
  });

  test('iOS intents run asynchronously on one private lifecycle lane', () {
    expect(plugin, contains('MixroomIOSLifecycleQueue(void)'));
    expect(plugin, contains('DISPATCH_QUEUE_SERIAL'));
    expect(
      plugin,
      contains('[self setAudioRouteIntentV2:args ?: @{} completion:result]'),
    );
    expect(plugin, contains('dispatch_async(MixroomIOSLifecycleQueue(), ^{'));
    expect(plugin, contains('lifecycleTransitionInProgress'));
    expect(plugin, contains('claimIOSIntentCleanupV2'));
    expect(plugin, contains('iosIntentCompletionDeliveredV2'));
  });

  test('duplex verification requires one real callback', () {
    expect(engine, contains('waitForFirstValidCallback('));
    expect(engine, contains('hasCompletedValidCallback()'));
    expect(engine, contains('duplexProbeCallbackCount'));
    expect(engine, contains('isBluetoothDuplexProjectCallbackReadyV2'));
    expect(engineHeader, contains('beginFirstValidCallbackProof()'));
    expect(engineHeader, contains('completeFirstValidCallbackProof('));
    expect(plugin, contains('@"projectCallback"'));
    expect(engine, isNot(contains('while (iosBluetoothDuplexProbe')));
  });

  test('debug probe uses intents but never enters recording', () {
    final start = editor.indexOf(
      'Future<void> _runIOSSystemSelectedRouteProbeV2()',
    );
    final end = editor.indexOf('String _bluetoothImplementationLabel', start);
    final probe = editor.substring(start, end);

    expect(probe, contains('AudioRouteIntentV2.preparingRecording'));
    expect(probe, contains('AudioRouteIntentV2.playbackOnly'));
    expect(probe, contains('if (_iosSystemSelectedRouteProbeRunning) return;'));
    expect(
      probe,
      contains('operation: AudioRouteIntentOperationV2.systemSelectedProbe'),
    );
    expect(probe, isNot(contains('Cancel Bluetooth Input + Output Check')));
    expect(probe, isNot(contains('AudioRouteIntentV2.recording')));
    expect(probe, isNot(contains('startRecording(')));
    expect(probe, isNot(contains('_startAudioRecordingJuce')));
    expect(editor, contains('Run System Recording Route Check'));
    expect(editor, contains('Checking System Recording Route…'));
    expect(
      editor,
      contains(
        'onPressed: _iosSystemSelectedRouteProbeRunning\n'
        '                    ? null',
      ),
    );
  });

  test('iOS callback rejects an unprepared or stale device shape', () {
    final callbackStart = engineHeader.indexOf(
      'class MetronomeAudioCallback : public juce::AudioIODeviceCallback',
    );
    final callback = engineHeader.substring(callbackStart);
    final aboutToStart = callback.indexOf('void audioDeviceAboutToStart');
    final stopped = callback.indexOf('void audioDeviceStopped');
    final ioCallback = callback.indexOf(
      'void audioDeviceIOCallbackWithContext',
    );
    final capture = callback.indexOf('engine.captureInput', ioCallback);
    final graphRender = callback.indexOf(
      'player.audioDeviceIOCallbackWithContext',
      ioCallback,
    );
    final invalidReturn = callback.indexOf(
      'engine.requestAudioDeviceRefreshAsync("unexpected-callback-shape")',
      ioCallback,
    );

    expect(callback, contains('std::atomic<bool> callbackReady{false}'));
    expect(callback, contains('std::atomic<int> expectedBlockCapacity{0}'));
    expect(
      callback.indexOf(
        'callbackReady.store(false, std::memory_order_release)',
        aboutToStart,
      ),
      lessThan(
        callback.indexOf('player.audioDeviceAboutToStart', aboutToStart),
      ),
    );
    expect(
      callback.indexOf(
        'callbackReady.store(false, std::memory_order_release)',
        stopped,
      ),
      lessThan(callback.indexOf('player.audioDeviceStopped()', stopped)),
    );
    expect(callback, contains('numSamples > knownBlockCapacity'));
    expect(callback, contains('numInputChannels != knownInputs'));
    expect(callback, contains('numOutputChannels != knownOutputs'));
    expect(invalidReturn, lessThan(capture));
    expect(invalidReturn, lessThan(graphRender));
    expect(callback, contains('if (!engine.isV2PlaybackSession())'));
    expect(
      effectsHeader,
      contains(
        'static constexpr int kMixroomEffectRealtimeScratchMaxSamples = 8192;',
      ),
    );
  });

  test('physical removal is terminal and never forces probe restoration', () {
    final observerStart = plugin.indexOf(
      '- (void)handleIOSAudioRouteChangeV2:(NSNotification *)notification {',
    );
    final observerEnd = plugin.indexOf(
      '- (NSDictionary<NSString *, id> *)startAudioRouteMonitoringV2',
      observerStart,
    );
    final observer = plugin.substring(observerStart, observerEnd);
    final intentStart = plugin.indexOf(
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:'
      '(NSDictionary *)args {',
    );
    final intentEnd = plugin.indexOf(
      '- (void)updateObservedOutputDeviceV2:',
      intentStart,
    );
    final intent = plugin.substring(intentStart, intentEnd);

    expect(
      observer,
      contains('AVAudioSessionRouteChangeReasonOldDeviceUnavailable'),
    );
    expect(observer, contains('markIOSIntentRouteInvalidatedV2ObjC'));
    expect(
      observer.indexOf('markIOSIntentRouteInvalidatedV2ObjC'),
      lessThan(observer.indexOf('void (^observe)(void)')),
    );
    expect(intent, contains('beginIOSIntentOperationV2ObjC'));
    expect(intent, contains('endIOSIntentOperationV2ObjC'));
    expect(intent, contains('isIOSIntentRouteInvalidatedV2ObjC'));
    expect(intent, contains('@"physicalRouteInvalidation"'));
    expect(
      intent,
      contains(
        'BOOL outputRestored = physicalRouteInvalidation\n'
        '            ? NO : [JuceBridge\n'
        '                reconfigurePlaybackRouteV2ObjC:@""',
      ),
    );
    expect('dispatch_after'.allMatches(intent), hasLength(1));
    expect(intent, isNot(contains('sleep(')));

    final hfpStart = engine.indexOf(
      'bool JuceEngine::openPreparedBluetoothDuplexRouteV2(',
    );
    final hfpEnd = engine.indexOf(
      'bool JuceEngine::validateRecordingRouteV2()',
      hfpStart,
    );
    final hfp = engine.substring(hfpStart, hfpEnd);
    final firstTerminalCheck = hfp.indexOf(
      'if (isIOSIntentRouteInvalidatedV2())',
    );
    final prepare = hfp.indexOf('prepareLiveClipProcessorsForCurrentDevice()');
    final attach = hfp.indexOf('deviceManager.addAudioCallback');
    expect(firstTerminalCheck, greaterThanOrEqualTo(0));
    expect(prepare, -1);
    expect(firstTerminalCheck, lessThan(attach));
    expect(
      hfp.indexOf('if (isIOSIntentRouteInvalidatedV2())', attach),
      greaterThan(attach),
    );
    expect(hfp, contains('detachIOSBluetoothDuplexProbeCallback()'));
    expect(hfp, contains('metronomeCallback->beginFirstValidCallbackProof()'));
    expect(hfp, contains('deviceManager.closeAudioDevice()'));

    final begin = engine.indexOf(
      'void JuceEngine::beginIOSIntentOperationV2()',
    );
    final mark = engine.indexOf(
      'void JuceEngine::markIOSIntentRouteInvalidatedV2()',
    );
    final query = engine.indexOf(
      'bool JuceEngine::isIOSIntentRouteInvalidatedV2()',
    );
    final intentScope = engine.substring(begin, query + 400);
    expect(intentScope, contains('iosIntentOperationActiveV2.store(true'));
    expect(intentScope, contains('iosIntentOperationActiveV2.store(false'));
    expect(
      engine.substring(mark, query),
      contains('if (iosIntentOperationActiveV2.load'),
    );
    expect(
      engine.substring(query, query + 400),
      contains('iosIntentOperationActiveV2.load'),
    );
    expect(
      engineHeader,
      contains('std::unique_ptr<IOSBluetoothDuplexProbeCallback>'),
    );
    expect(engine, contains('detachIOSBluetoothDuplexProbeCallback()'));
    expect(intent, contains('!operationRouteStillPresent'));

    final abortStart = plugin.indexOf(
      'else if ([call.method isEqualToString:@"abortRecordingV2"])',
    );
    final abortEnd = plugin.indexOf(
      'else if ([call.method isEqualToString:@"stopAudioRouteMonitoringV2"])',
      abortStart,
    );
    final abort = plugin.substring(abortStart, abortEnd);
    expect(abort, contains('@"physicalRouteInvalidation"'));
    expect(abort, contains('const BOOL terminal ='));
    expect(abort, contains('if (!terminal)'));
    expect(
      abort.indexOf('if (!terminal)'),
      lessThan(abort.indexOf('reconfigurePlaybackRouteV2ObjC')),
    );
  });

  test('duplex probe diagnostics parse and redact every identity', () {
    Map<String, dynamic> endpoint(String direction, String uid, String type) =>
        <String, dynamic>{
          'direction': direction,
          'uid': uid,
          'name': 'private device name',
          'nativePortType': type,
          'normalizedKind': type == 'BluetoothA2DPOutput'
              ? 'bluetoothMedia'
              : 'bluetoothDuplex',
          'channelCount': direction == 'input' ? 1 : 2,
        };

    final snapshot = AudioRouteSnapshotV2.fromMap(<String, dynamic>{
      'implementation': 'v2',
      'captureConsistency': 'stable',
      'session': <String, dynamic>{
        'categoryOptions': <String>['mixWithOthers', 'futureOption'],
      },
      'juce': <String, dynamic>{},
      'duplexProbe': <String, dynamic>{
        'status': 'restored',
        'diagnosticCode': 'ok',
        'validationStage': 'duplexVerified',
        'phase': 'complete',
        'terminalCause': null,
        'actualCallbackCount': 3,
        'cleanupOutcome': 'restored',
        'categoryOptions': <String>['mixWithOthers', 'allowBluetoothHFP'],
        'operationId': 7,
        'elapsedMs': 35,
        'sourceOutput': endpoint(
          'output',
          'source-secret',
          'BluetoothA2DPOutput',
        ),
        'duplexInput': endpoint('input', 'input-secret', 'BluetoothHFP'),
        'duplexOutput': endpoint('output', 'output-secret', 'BluetoothHFP'),
        'restoredOutput': endpoint(
          'output',
          'source-secret',
          'BluetoothA2DPOutput',
        ),
      },
    });
    final report = BluetoothRouteReportSerializerV2(
      sessionSalt: List<int>.filled(32, 9),
    ).encode(snapshot);

    expect(snapshot.session.categoryOptions, contains('futureOption'));
    expect(snapshot.duplexProbe?.status, 'restored');
    expect(snapshot.duplexProbe?.validationStage, 'duplexVerified');
    expect(snapshot.duplexProbe?.phase, 'complete');
    expect(snapshot.duplexProbe?.actualCallbackCount, 3);
    expect(snapshot.duplexProbe?.cleanupOutcome, 'restored');
    expect(
      snapshot.duplexProbe?.categoryOptions,
      contains('allowBluetoothHFP'),
    );
    expect(report, contains('duplexProbe'));
    expect(report, isNot(contains('source-secret')));
    expect(report, isNot(contains('input-secret')));
    expect(report, isNot(contains('output-secret')));
    expect(report, isNot(contains('private device name')));
  });
}
