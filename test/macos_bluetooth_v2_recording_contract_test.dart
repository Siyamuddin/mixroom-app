import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('macOS monitoring requires a proven shared CoreAudio clock', () {
    final plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();

    expect(plugin, contains('kAudioDevicePropertyClockDomain'));
    expect(plugin, contains('MixroomMacMonitoringSharesClockDomain'));
    expect(plugin, contains('@"clockDomain"'));
    expect(
      plugin,
      contains(
        'MixroomMacMonitoringSharesClockDomain(\n                     settledInput, settledOutput)',
      ),
    );
  });

  const pluginPath = 'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m';
  const bridgePath = 'juce_audio_engine/ios/Classes/JuceBridge.mm';
  const enginePath = 'juce_audio_engine/ios/Classes/JuceEngine.cpp';
  const editorPath = 'lib/screens/audio_editor.dart';
  const coreAudioPath =
      'juce_audio_engine/android/src/main/cpp/juce/modules/'
      'juce_audio_devices/native/juce_CoreAudio_mac.cpp';

  test('macOS recording uses the system-selected production intent route', () {
    final editor = File(editorPath).readAsStringSync();
    final support = _between(
      editor,
      'bool get _supportsV2AudioRecording =>',
      'List<String> _inputDevices',
    );
    expect(support, contains('Platform.isMacOS'));
    expect(
      editor,
      contains('AudioRouteIntentOperationV2.systemSelectedRecording'),
    );
    expect(editor, isNot(contains('systemSelectedProbe')));
    expect(editor, isNot(contains('Run System Recording Route Check')));
  });

  test('macOS V2 input selector stores preference without opening input', () {
    final editor = File(editorPath).readAsStringSync();
    final selector = _between(
      editor,
      'Widget _buildInputSelector()',
      'Widget _buildInputChannelRouteSelector()',
    );

    expect(
      selector,
      contains('if (_isBluetoothV2Session && Platform.isMacOS)'),
    );
    expect(selector, contains("L10n.translate(context, 'System Default')"));
    expect(selector, contains('_selectMacV2InputDevice'));
    expect(selector, contains('DropdownButtonFormField<String>'));
    expect(
      selector.indexOf('if (_isBluetoothV2Session && Platform.isMacOS)'),
      lessThan(selector.indexOf('JuceAudioEngine.selectInputDevice(name)')),
    );
    expect(selector, contains('devicesByUID'));
    expect(selector, contains('displayLabelsByUid'));
    expect(selector, contains('_macInputDeviceUID'));
    final v2Selection = _between(
      editor,
      'Future<void> _selectMacV2InputDevice(AudioInputDeviceInfo? device) async {',
      'List<_InputChannelRouteOption> _buildInputChannelRouteOptions',
    );
    expect(v2Selection, contains('coordinator.selectRecordingInput'));
    expect(v2Selection, contains('inputDeviceUID:'));
    expect(v2Selection, contains('[MacV2InputSelection]'));
    expect(v2Selection, contains('result.diagnosticCode'));
    expect(
      v2Selection.indexOf('if (!result.succeeded)'),
      lessThan(v2Selection.indexOf('_macInputDeviceUID =')),
    );
    expect(v2Selection, isNot(contains('selectInputDevice')));
    expect(v2Selection, isNot(contains('prepareRecordingInputs')));
    expect(v2Selection, isNot(contains('requestMicrophone')));
  });

  test('macOS recording owns an independent input and output-only JUCE route', () {
    final plugin = File(pluginPath).readAsStringSync();
    final intent = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );

    expect(intent, contains('systemSelectedRecording'));
    expect(intent, isNot(contains('systemSelectedProbe')));
    expect(intent, contains('startMacInputProbeV2ObjC'));
    expect(intent, contains('waitForMacInputProbeCallbackV2ObjC'));
    expect(intent, contains('beginMacOutputCallbackProofV2ObjC'));
    expect(intent, contains('waitForMacOutputCallbackProofV2ObjC'));
    expect(intent, contains('reconfigureMacPlaybackRouteV2ObjC'));
    expect(intent, contains('MixroomMacPlaybackOpenPlan'));
    expect(intent, contains('sampleRate:[settledOutputPlan[@"sampleRateHz"]'));
    expect(
      intent,
      contains('bufferFrames:[settledOutputPlan[@"bufferFrames"]'),
    );
    expect(intent, contains('@"selectionMode": @"macOSIndependentInput"'));
    expect(intent, isNot(contains('reconfigureRecordingRouteV2ObjC')));
    expect(intent, isNot(contains('startRecordingObjC')));
    expect(intent, isNot(contains('AudioHardwareCreateAggregateDevice')));
    expect(intent, isNot(contains('AudioHardwareDestroyAggregateDevice')));
  });

  test('AUHAL adapter is input-only, preallocated, and callback-proven', () {
    final bridge = File(bridgePath).readAsStringSync();
    final adapter = _between(
      bridge,
      'class MixroomMacInputProbe final',
      'MixroomMacInputProbe &mixroomMacInputProbeV2()',
    );

    expect(adapter, contains('kAudioUnitSubType_HALOutput'));
    expect(adapter, contains('kAudioOutputUnitProperty_CurrentDevice'));
    expect(adapter, contains('kAudioOutputUnitProperty_ChannelMap'));
    expect(adapter, contains('kAudioUnitScope_Input'));
    expect(adapter, contains('kAudioUnitScope_Output'));
    expect(
      adapter,
      contains(
        'scratch[static_cast<size_t>(channel)].assign(capacityFrames, 0.0f)',
      ),
    );
    expect(adapter, contains('AudioUnitRender(unit'));
    expect(adapter, contains('numberFrames > capacityFrames'));
    expect(adapter, contains('callbackReady.store(true'));
    expect(adapter, contains('startIndependentInputRecordingToWav'));
    expect(adapter, contains('captureIndependentInput'));
    expect(
      adapter,
      contains('captureIndependentInput(\n                    nullptr'),
    );
    expect(adapter, contains('captureEnabled.load'));
    expect(adapter, isNot(contains('push_back')));
    expect(adapter, isNot(contains('resize(')));
  });

  test('production capture uses AUHAL native rate without reopening JUCE', () {
    final plugin = File(pluginPath).readAsStringSync();
    final bridge = File(bridgePath).readAsStringSync();
    final engine = File(enginePath).readAsStringSync();
    final start = _between(
      plugin,
      '- (BOOL)startMacIndependentInputRecordingV2:',
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:',
    );
    final externalCapture = _between(
      engine,
      'bool JuceEngine::startIndependentInputRecordingToWav(',
      'RealtimeWavCapture::StopResult JuceEngine::stopRecording()',
    );

    expect(start, contains('systemSelectedRecording'));
    expect(start, contains('getMacInputProbeFactsV2ObjC'));
    expect(start, contains('startMacInputRecordingV2ObjC:path'));
    expect(start, isNot(contains('reconfigureMacPlaybackRouteV2ObjC')));
    expect(start, isNot(contains('reconfigureRecordingRouteV2ObjC')));
    expect(
      externalCapture,
      contains('wavCapture.start(file, inputSampleRate, channelCount, 0)'),
    );
    expect(externalCapture, contains('independentInputCaptureMode.store(true'));
    expect(
      engine,
      contains(
        'if (independentInputCaptureMode.load(std::memory_order_acquire))\n'
        '        return;\n'
        '    wavCapture.capture(input, numInputChannels, numSamples);',
      ),
    );
    expect(
      externalCapture,
      contains('getActiveInputChannels().countNumberOfSetBits() != 0'),
    );
    expect(
      bridge,
      contains(
        'captureChannels,\n'
        '                    activeChannels,\n'
        '                    static_cast<int>(numberFrames)',
      ),
    );
    expect(bridge, isNot(contains('AudioHardwareCreateAggregateDevice')));
  });

  test('recording stop finalizes capture before output-only restoration', () {
    final plugin = File(pluginPath).readAsStringSync();
    final handler = _between(
      plugin,
      'else if ([call.method isEqualToString:@"stopRecording"])',
      'else if ([call.method isEqualToString:@"restoreBluetoothPlaybackAfterRecordingStop"])',
    );
    final intent = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );
    final restore = _between(
      intent,
      'else if ([intent isEqualToString:@"playbackOnly"] &&',
      'else if (![intent isEqualToString:@"playbackOnly"])',
    );

    expect(handler, contains('stopMacInputRecordingV2ObjC'));
    expect(handler, contains('MixroomMacPlaybackStartupQueue()'));
    expect(restore, contains('discardMacInputRecordingV2ObjC'));
    expect(restore, contains('stopMacInputProbeV2ObjC'));
    expect(restore, contains('restoreSourceOutput()'));
    expect(
      restore.indexOf('stopMacInputProbeV2ObjC'),
      lessThan(restore.indexOf('restoreSourceOutput()')),
    );
  });

  test('independent input and output clocks remain intentionally separate', () {
    final plugin = File(pluginPath).readAsStringSync();
    final engine = File(enginePath).readAsStringSync();
    final start = _between(
      plugin,
      '- (BOOL)startMacIndependentInputRecordingV2:',
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:',
    );
    final capture = _between(
      engine,
      'bool JuceEngine::startIndependentInputRecordingToWav(',
      'RealtimeWavCapture::StopResult JuceEngine::stopRecording()',
    );

    expect(start, contains('inputFacts[@"sampleRateHz"]'));
    expect(start, contains('expectedOutput[@"sampleRateHz"]'));
    expect(capture, contains('inputSampleRate'));
    expect(capture, isNot(contains('hostSampleRateAtomic')));
    expect(capture, isNot(contains('resampl')));
  });

  test(
    'verified independent-input recording does not revalidate JUCE input',
    () {
      final editor = File(editorPath).readAsStringSync();
      final readiness = _between(
        editor,
        'Future<bool> _ensurePlaybackRouteReady(',
        'void _handleAudioRouteIntentInvalidatedV2(',
      );

      expect(readiness, contains('macIndependentInputRecording'));
      expect(
        readiness,
        contains('coordinator?.intent == AudioRouteIntentV2.recording'),
      );
      expect(
        readiness,
        contains(
          'macIndependentInputRecording ||\n'
          '          await JuceAudioEngine.validatePlaybackV2()',
        ),
      );
    },
  );

  test('probe never duplicates the permanent output observer listeners', () {
    final plugin = File(pluginPath).readAsStringSync();
    final install = _between(
      plugin,
      '- (BOOL)installMacIntentDeviceListenersV2 {',
      '- (void)removeMacIntentDeviceListenersV2 {',
    );
    final remove = _between(
      plugin,
      '- (void)removeMacIntentDeviceListenersV2 {',
      '#else\n- (void)signalIOSIntentRouteConditionV2',
    );

    expect(install, contains('if (input != output)'));
    expect(remove, contains('if (input != output)'));
    expect(install, isNot(contains('AudioObjectAddPropertyListener(output')));
    expect(remove, isNot(contains('AudioObjectRemovePropertyListener(output')));
  });

  test('dormant macOS JUCE input and combiner path is unreachable', () {
    final engine = File(enginePath).readAsStringSync();
    final inputOpen = _between(
      engine,
      'bool JuceEngine::openRecordingInputV2(',
      'bool JuceEngine::quiescePlaybackRouteV2(',
    );
    final recordRoute = _between(
      engine,
      'bool JuceEngine::reconfigureRecordingRouteV2(',
      'bool JuceEngine::prepareBluetoothDuplexSessionV2()',
    );

    expect(inputOpen, contains('#if JUCE_IOS'));
    expect(inputOpen, isNot(contains('JUCE_MAC && !JUCE_IOS')));
    expect(recordRoute, contains('#if JUCE_IOS'));
    expect(recordRoute, isNot(contains('JUCE_MAC && !JUCE_IOS')));

    final appSources = <String>[
      pluginPath,
      bridgePath,
      enginePath,
    ].map((path) => File(path).readAsStringSync()).join('\n');
    expect(appSources, isNot(contains('AudioHardwareCreateAggregateDevice')));
    expect(appSources, isNot(contains('AudioHardwareDestroyAggregateDevice')));
  });

  test('operation cancellation signals one lifecycle owner only', () {
    final plugin = File(pluginPath).readAsStringSync();
    final abort = _between(
      plugin,
      'else if ([call.method isEqualToString:@"abortRecordingV2"]) {',
      '#else\n        if ([[JuceBridge getAudioRouteImplementationObjC]',
    );
    final routeHandler = _between(
      plugin,
      '- (void)handleAudioRoutePropertyChangeV2:(NSString *)cause {',
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:',
    );

    expect(abort, contains('macIntentOperationCancelledV2 = YES'));
    expect(abort, contains('cancelMacInputProbeWaitV2ObjC'));
    expect(abort, isNot(contains('stopMacInputProbeV2ObjC')));
    expect(abort, isNot(contains('reconfigurePlaybackRouteV2ObjC')));
    expect(routeHandler, contains('claimMacIntentCleanupV2'));
    expect(routeHandler, contains('stopMacInputProbeV2ObjC'));
    expect(routeHandler, contains('return;'));
  });

  test('worker response remains owned through Flutter result encoding', () {
    final plugin = File(pluginPath).readAsStringSync();
    final asyncIntent = _between(
      plugin,
      '- (void)setAudioRouteIntentV2:(NSDictionary *)args',
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:',
    );

    expect(
      asyncIntent,
      contains('NSDictionary<NSString *, id> *response = [rawResponse copy]'),
    );
    expect(asyncIntent, contains('completion(response)'));
    expect(asyncIntent, contains('[response release]'));
    expect(
      asyncIntent.indexOf('completion(response)'),
      lessThan(asyncIntent.indexOf('[response release]')),
    );
  });

  test('restoration proves the canonical saved source profile', () {
    final plugin = File(pluginPath).readAsStringSync();
    final fingerprint = _between(
      plugin,
      'static NSString *MixroomOutputFingerprint(',
      'static NSString *MixroomEffectiveOutputFingerprint',
    );
    final intent = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );
    final restore = _between(
      intent,
      'BOOL (^restoreSourceOutput)(void) = ^BOOL {',
      'if (!self.audioRouteMonitoringV2',
    );

    expect(restore, contains('MixroomOutputForUID(inventory, source[@"uid"])'));
    expect(restore, contains('samePolicyOutput'));
    expect(restore, contains('self.macIntentSourceFingerprintV2'));
    expect(fingerprint, contains('device[@"rawTransport"]'));
    expect(fingerprint, contains('device[@"outputChannels"]'));
    expect(fingerprint, contains('device[@"sampleRateHz"]'));
    expect(fingerprint, contains('device[@"bufferFrames"]'));
    expect(fingerprint, contains('MixroomCoreAudioDeviceIsAlive(deviceID)'));
    expect(restore, contains('waitForMacOutputCallbackProofV2ObjC'));
    expect(restore, contains('reconfigureMacPlaybackRouteV2ObjC'));
    expect(
      restore,
      contains('sampleRate:[source[@"sampleRateHz"] doubleValue]'),
    );
    expect(
      restore,
      contains('bufferFrames:[source[@"bufferFrames"] integerValue]'),
    );
    expect(restore, contains('getMacOutputCallbackProofFramesV2ObjC'));
    expect(restore, contains('callbackShapeValid'));
    expect(restore, contains('const BOOL restorationVerified'));
    expect(restore, contains('if (!restorationVerified)'));
    expect(restore, contains('quiescePlaybackRouteV2ObjC:YES'));
    expect(restore, isNot(contains('exactBufferRestored')));
    expect(
      restore,
      contains('outputSnapshotIsValid(snapshot, restoredOutput ?: candidate)'),
    );
    expect(restore, contains('MixroomMonotonicMilliseconds() + 2000.0'));
    expect(restore, contains('NSMutableSet<NSString *> *attemptedFingerprints'));
    expect(restore, contains('macIntentRouteConditionSignalledV2'));
    expect(restore, contains('[condition waitUntilDate:'));
    expect(restore, contains('remainingMilliseconds(restoreDeadline)'));
    expect(
      restore,
      contains(
        'self.macIntentOperationGenerationV2 ==\n'
        '                   self.audioRouteGenerationV2',
      ),
    );
    expect(
      restore,
      contains('[attemptedFingerprints containsObject:observedFingerprint]'),
    );
    expect(restore, contains('[JuceBridge cancelMacOutputCallbackProofV2ObjC]'));
    expect(restore, contains('sourceProfileRestored'));
    expect(
      restore,
      contains('snapshotValid && sourceProfileRestored && generationValid'),
    );
    expect(restore, isNot(contains('MixroomOutputFingerprint(candidatePlan)')));
    expect(restore, isNot(contains('currentProfileValid')));
    expect(restore, contains('macIntentSourceFingerprintV2'));
    expect(restore, isNot(contains('sleep')));
    expect(restore, isNot(contains('dispatch_after')));
  });

  test('device removal closes owned streams before one coordinator recovery', () {
    final plugin = File(pluginPath).readAsStringSync();
    final editor = File(editorPath).readAsStringSync();
    final routeHandler = _between(
      plugin,
      '- (void)handleAudioRoutePropertyChangeV2:(NSString *)cause {',
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:',
    );
    final ownedOperation = _between(
      routeHandler,
      'if (self.macIntentOperationActiveV2) {',
      'if (self.macIntentRecoveryPendingV2) {',
    );
    final intent = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );
    final eventEmitter = _between(
      plugin,
      '- (void)emitMacIntentRouteInvalidationEventV2:(BOOL)recordingWasActive\n'
          '                           monitoringWasActive:(BOOL)monitoringWasActive {',
      '- (BOOL)startMacIndependentInputRecordingV2:',
    );

    expect(ownedOperation, contains('macIntentOperationCancelledV2 = YES'));
    expect(ownedOperation, contains('quiescePlaybackRouteV2ObjC:YES'));
    expect(ownedOperation, contains('discardMacInputRecordingV2ObjC'));
    expect(ownedOperation, contains('stopMacInputProbeV2ObjC'));
    expect('claimMacIntentCleanupV2'.allMatches(ownedOperation), hasLength(1));
    expect(
      ownedOperation.indexOf('[self claimMacIntentCleanupV2]'),
      lessThan(
        ownedOperation.indexOf(
          'dispatch_async(MixroomMacPlaybackStartupQueue()',
        ),
      ),
    );
    expect(ownedOperation, isNot(contains('reconfigurePlaybackRouteV2ObjC')));
    expect(ownedOperation, contains('emitMacIntentRouteInvalidationEventV2:'));
    expect(intent, contains('const BOOL physicalRouteInvalidation'));
    expect(intent, contains('releaseOperation();'));
    expect(intent, contains('emitMacIntentRouteInvalidationEventV2:NO'));
    expect(eventEmitter, contains('dispatch_get_main_queue()'));
    expect(eventEmitter, contains('audioRouteGenerationV2 += 1'));
    expect(eventEmitter, contains('currentMacPlaybackOutputV2:inventory'));
    expect(eventEmitter, isNot(contains('reconfigureMacPlaybackRouteV2ObjC')));
    expect(ownedOperation, contains('macIntentRecoveryPendingV2 = YES'));
    expect(routeHandler, contains('if (self.macIntentRecoveryPendingV2)'));
    expect(routeHandler, contains('self.macLifecycleReconcilePendingV2 = YES'));
    expect(
      editor,
      contains('Platform.isIOS || Platform.isAndroid || Platform.isMacOS'),
    );
    expect(editor, contains('recoverPlaybackAfterIntentInvalidation()'));
    expect(
      editor,
      contains('recoveryResult.snapshot.juce.outputDeviceName?.trim()'),
    );
    expect(editor, contains('_macOutputDeviceName = recoveredOutputName'));
    expect(editor, contains('unawaited(_loadMacV2AudioDevices())'));
    expect(
      editor,
      contains('cleanupBeforeRecovery: interruption || Platform.isAndroid'),
    );
  });

  test('recording preparation removal defers its notice to recovery', () {
    final editor = File(editorPath).readAsStringSync();
    final preflight = _between(
      editor,
      'Future<bool> _prepareAudioRecordingStartPreflight()',
      'Future<void> _startAudioRecordingJuce()',
    );

    expect(preflight, contains("'physicalRouteInvalidation'"));
    expect(preflight, contains('if (!macRouteRemoved)'));
    expect(
      preflight,
      isNot(
        contains(
          'The audio device disconnected during recording preparation. '
          'Reopen the audio editor.',
        ),
      ),
    );
  });

  test('macOS invalidation reports one route-specific recovery outcome', () {
    final plugin = File(pluginPath).readAsStringSync();
    final editor = File(editorPath).readAsStringSync();
    final intent = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );

    expect(intent, contains('@"status"] = @"failedRestored"'));
    expect(intent, contains('@"cleanupOutcome"] = @"restored"'));
    expect(intent, contains('@"restoredOutput"] ='));
    expect(
      editor,
      contains(
        'Recording stopped because the audio device changed. Press Play to continue.',
      ),
    );
    expect(editor, contains('Audio output changed. Press Play to continue.'));
  });

  test(
    'explicit output selection does not produce a redundant success toast',
    () {
      final editor = File(editorPath).readAsStringSync();
      final selection = _between(
        editor,
        'Future<void> _selectMacOutputDevice(String name) async {',
        'Future<void> _selectMacV2InputDevice(',
      );
      final transition = _between(
        editor,
        'void _handleAudioRouteTransitionV2(',
        'Future<void> _flushDeferredAndroidRouteRefreshIfNeeded()',
      );

      expect(selection, contains('_macV2OutputSelectionInFlight = true'));
      expect(selection, contains('finally'));
      expect(selection, contains('_macV2OutputSelectionInFlight = false'));
      expect(
        transition,
        contains(
          'if (Platform.isMacOS && _macV2OutputSelectionInFlight) return',
        ),
      );
      expect(
        transition.indexOf('AudioRouteTransitionStatusV2.fallback'),
        lessThan(transition.indexOf('_macV2OutputSelectionInFlight)')),
        reason: 'a real fallback must remain visible',
      );
      expect(transition, contains('sameVisibleOutput'));
      expect(
        transition.indexOf('AudioRouteTransitionStatusV2.fallback'),
        lessThan(transition.indexOf('if (sameVisibleOutput) return')),
        reason: 'Bluetooth fallback must not be hidden by identity coalescing',
      );
    },
  );

  test('Bluetooth profile changes retain one user-visible device identity', () {
    final editor = File(editorPath).readAsStringSync();
    final identity = _between(
      editor,
      'String? _userVisibleOutputIdentityV2(',
      'void _handleAudioRouteCoordinatorStateV2(',
    );

    expect(identity, contains('AudioRouteKindV2.bluetoothMedia'));
    expect(identity, contains('AudioRouteKindV2.bluetoothDuplex'));
    expect(identity, contains("return 'bluetooth:\$name'"));
    expect(identity, contains("return 'uid:\$uid'"));
    expect(
      RegExp(
        r'_v2UserVisibleOutputIdentity = _userVisibleOutputIdentityV2\(\s*initialRoute',
      ).allMatches(editor).length,
      2,
      reason: 'both desktop/mobile coordinator startup paths seed identity',
    );
  });

  test(
    'current-output recovery waits once for authoritative route evidence',
    () {
      final plugin = File(pluginPath).readAsStringSync();
      final recovery = _between(
        plugin,
        'const double recoveryDeadlineMs = startedAtMs + 2000.0;',
        'if (success && [intent isEqualToString:@"playbackOnly"])',
      );
      final routeObserver = _between(
        plugin,
        '- (void)handleAudioRoutePropertyChangeV2:(NSString *)cause {',
        '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:',
      );

      expect(recovery, contains('currentMacPlaybackOutputV2:'));
      expect(recovery, contains('[condition waitUntilDate:'));
      expect(recovery, contains('recoveryDeadlineMs -'));
      expect(
        recovery,
        contains('waitForMacOutputCallbackProofV2ObjC:remainingMs'),
      );
      expect(
        'reconfigureMacPlaybackRouteV2ObjC'.allMatches(recovery),
        hasLength(1),
      );
      expect(recovery, isNot(contains('while (')));
      expect(recovery, isNot(contains('sleep')));
      expect(recovery, isNot(contains('dispatch_after')));
      expect(routeObserver, contains('currentMacPlaybackOutputV2:'));
    },
  );

  test(
    'invalidation owns notifications until a non-stale recovery completes',
    () {
      final plugin = File(pluginPath).readAsStringSync();
      final asyncIntent = _between(
        plugin,
        '- (void)setAudioRouteIntentV2:(NSDictionary *)args\n'
            '                   completion:(void (^)(NSDictionary<NSString *, id> *))completion {',
        '#else\n    self.iosIntentCompletionDeliveredV2 = NO;',
      );

      expect(asyncIntent, contains('beginsInvalidationRecovery'));
      expect(asyncIntent, contains('macIntentRecoveryPendingV2'));
      expect(
        asyncIntent,
        contains('[immutableArgs[@"intent"] isEqualToString:@"playbackOnly"]'),
      );
      expect(asyncIntent, contains('macLifecycleTransitionActiveV2 = YES'));
      expect(asyncIntent, contains('stalePreflight'));
      expect(
        asyncIntent,
        contains('[diagnosticCode isEqualToString:@"stale_generation"]'),
      );
      expect(asyncIntent, contains('if (!stalePreflight)'));
      expect(
        asyncIntent,
        contains('[MacV2Recovery] result attempted=%llu snapshot=%llu'),
      );
      expect(
        asyncIntent.indexOf('NSDictionary<NSString *, id> *response ='),
        lessThan(asyncIntent.indexOf('macIntentRecoveryPendingV2 = NO')),
      );
    },
  );

  test(
    'macOS startup remains off Flutter UI and avoids callback-lock deadlock',
    () {
      final plugin = File(pluginPath).readAsStringSync();
      final engine = File(enginePath).readAsStringSync();
      final handler = _between(
        plugin,
        'else if ([call.method isEqualToString:@"initialisePlaybackV2"]) {',
        'else if ([call.method isEqualToString:@"startAudioRouteMonitoringV2"])',
      );
      final initialise = _between(
        engine,
        'void JuceEngine::initialiseEngine(',
        'bool JuceEngine::initialisePlaybackV2(',
      );

      expect(handler, contains('MixroomMacPlaybackStartupQueue()'));
      expect(handler, contains('dispatch_async(dispatch_get_main_queue()'));
      final openStart = initialise.indexOf(
        'if (deviceManager.getCurrentAudioDevice() == nullptr)',
      );
      final renderLock = initialise.indexOf('GraphMutationScope renderLock(');
      expect(openStart, greaterThanOrEqualTo(0));
      expect(renderLock, greaterThan(openStart));
    },
  );

  test(
    'post-start macOS JUCE route mutations are serialized on its message thread',
    () {
      final bridge = File(bridgePath).readAsStringSync();
      final quiesce = _between(
        bridge,
        '+ (BOOL)quiescePlaybackRouteV2ObjC:',
        '+ (BOOL)reconfigurePlaybackRouteV2ObjC:',
      );
      final reopen = _between(
        bridge,
        '+ (BOOL)reconfigurePlaybackRouteV2ObjC:',
        '#if TARGET_OS_OSX\n+ (BOOL)reconfigureMacPlaybackRouteV2ObjC:',
      );
      final exactReopen = _between(
        bridge,
        '+ (BOOL)reconfigureMacPlaybackRouteV2ObjC:',
        '+ (void)beginMacOutputCallbackProofV2ObjC',
      );

      for (final mutation in <String>[quiesce, reopen, exactReopen]) {
        expect(mutation, contains('isThisTheMessageThread()'));
        expect(mutation, contains('messageManager->callSync(mutation)'));
      }
    },
  );

  test('CoreAudio conflicting route readback fails before callbacks', () {
    final coreAudio = File(coreAudioPath).readAsStringSync();
    final reopen = _between(
      coreAudio,
      'String reopen (const BigInteger& ins, const BigInteger& outs,',
      'bool start (AudioIODeviceCallback* callbackToNotify)',
    );

    expect(reopen, contains('std::abs (sampleRate - newSampleRate) >= 1.0'));
    expect(reopen, contains('bufferSize != bufferSizeSamples'));
    expect(reopen, contains('route settings changed during reopen'));
    expect(reopen, isNot(contains('sampleRate = newSampleRate')));
    expect(reopen, isNot(contains('bufferSize = bufferSizeSamples')));
    expect(reopen, isNot(contains('allocateTempBuffers();')));
  });

  test('Mac output proof requires native device graph and callback clocks', () {
    final plugin = File(pluginPath).readAsStringSync();
    final intent = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );
    final validator = _between(
      intent,
      'BOOL (^outputSnapshotIsValid)',
      'void (^releaseOperation)',
    );

    expect(
      validator,
      contains('[expectedOutput[@"bufferFrames"] integerValue] > 0'),
    );
    expect(
      validator,
      contains(
        '[juce[@"bufferFrames"] integerValue] ==\n'
        '                    [expectedOutput[@"bufferFrames"] integerValue]',
      ),
    );
    expect(validator, contains('projectGraphSampleRateHz'));
    expect(validator, contains('projectGraphBufferFrames'));
    expect(intent, contains('outputCallbackFrames =='));
    expect(intent, contains('outputCallbackRate'));
    expect(intent, contains('[duplexJuce[@"bufferFrames"] integerValue]'));
  });

  test('all macOS V2 output opens use immutable CoreAudio settings', () {
    final plugin = File(pluginPath).readAsStringSync();
    final engine = File(enginePath).readAsStringSync();
    final startup = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)initialisePlaybackV2 {',
      '#else\n    self.currentAudioRouteIntentV2 = @"playbackOnly";',
    );
    final apply = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );
    final genericReopen = _between(
      engine,
      'bool JuceEngine::reconfigurePlaybackRouteV2(',
      'void JuceEngine::beginMacOutputCallbackProofV2()',
    );
    final exactOutputOpen = _between(
      engine,
      'bool JuceEngine::openPlaybackOutputOnlyV2(',
      'bool JuceEngine::reconfigureMacPlaybackRouteV2(',
    );

    expect(startup, contains('initialiseMacPlaybackV2ObjC'));
    expect(startup, contains('target[@"sampleRateHz"]'));
    expect(startup, contains('target[@"bufferFrames"]'));
    expect(apply, contains('reconfigureMacPlaybackRouteV2ObjC'));
    expect(apply, contains('waitForMacOutputCallbackProofV2ObjC'));
    expect(genericReopen, contains('juce::ignoreUnused(outputDeviceName)'));
    expect(genericReopen, contains('return false;'));
    expect(exactOutputOpen, contains('type->scanForDevices()'));
    expect(
      exactOutputOpen,
      contains('candidate.trim() == normalizedOutputDeviceName'),
    );
    expect(exactOutputOpen, contains('outputNameMatchCount != 1'));
    expect(
      exactOutputOpen,
      contains('setup.outputDeviceName = resolvedOutputDeviceName'),
    );
  });

  test(
    'route apply waits on lifecycle worker and self notifications reconcile once',
    () {
      final plugin = File(pluginPath).readAsStringSync();
      final handler = _between(
        plugin,
        'else if ([call.method isEqualToString:@"applyAudioRouteConfigurationV2"])',
        'else if ([call.method isEqualToString:@"setAudioRouteIntentV2"])',
      );
      final routeObserver = _between(
        plugin,
        '- (void)handleAudioRoutePropertyChangeV2:(NSString *)cause {',
        '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:',
      );

      expect(handler, contains('MixroomMacPlaybackStartupQueue()'));
      expect(handler, contains('dispatch_async(dispatch_get_main_queue()'));
      expect(
        routeObserver,
        contains('if (self.macLifecycleTransitionActiveV2)'),
      );
      expect(routeObserver, contains('macLifecycleReconcilePendingV2 = YES'));
      final observedOutput = _between(
        plugin,
        '- (void)updateObservedOutputDeviceV2:(uint32_t)deviceID {',
        '- (BOOL)startIOSAudioRouteMonitoringV2',
      );
      expect(observedOutput, contains('kAudioDevicePropertyNominalSampleRate'));
      expect(observedOutput, contains('kAudioDevicePropertyBufferFrameSize'));
      expect(
        observedOutput,
        contains('kAudioDevicePropertyStreamConfiguration'),
      );
    },
  );

  test('audioDeviceAboutToStart owns graph and transport clock', () {
    final header = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    final callbackStart = _between(
      header,
      'void audioDeviceAboutToStart(juce::AudioIODevice *device) override',
      'void audioDeviceStopped() override',
    );
    final engine = File(enginePath).readAsStringSync();
    final initialise = _between(
      engine,
      'void JuceEngine::initialiseEngine(',
      'bool JuceEngine::initialisePlaybackV2(',
    );

    expect(
      callbackStart,
      contains('engine.beginAudioDeviceClockV2(sampleRate)'),
    );
    expect(callbackStart, contains('player.audioDeviceAboutToStart(device)'));
    expect(callbackStart, contains('engine.completeGraphClockV2'));
    expect(initialise, isNot(contains('graph.prepareToPlay(hostRate')));
  });

  test(
    'communication-quality playback is capability detected and never forced',
    () {
      final plugin = File(pluginPath).readAsStringSync();
      final editor = File(editorPath).readAsStringSync();
      final startup = _between(
        plugin,
        '- (NSDictionary<NSString *, id> *)initialisePlaybackV2 {',
        '#if TARGET_OS_OSX\n- (void)signalMacIntentRouteConditionV2',
      );
      final apply = _between(
        plugin,
        '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:',
        '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
      );

      expect(plugin, contains('bluetoothCommunicationQualityReduced'));
      expect(plugin, contains('kAudioDeviceTransportTypeBluetooth'));
      expect(plugin, contains('[target[@"outputChannels"] integerValue] == 1'));
      expect(
        editor,
        contains(
          'Bluetooth microphone selected. Playback quality is reduced. Select another microphone for stereo audio.',
        ),
      );
      expect(startup, isNot(contains('setPreferredInput')));
      expect(apply, isNot(contains('setPreferredInput')));
    },
  );

  test(
    'macOS V2 output selector uses the coordinator and never Legacy setup',
    () {
      final editor = File(editorPath).readAsStringSync();
      final selector = _between(
        editor,
        'Future<void> _selectMacOutputDevice(String name) async {',
        'List<_InputChannelRouteOption> _buildInputChannelRouteOptions',
      );
      final v2Refresh = _between(
        editor,
        'Future<void> _loadMacV2AudioDevices() async {',
        'Widget _buildMicrophonePermissionNotice()',
      );

      expect(selector, contains('coordinator.selectPlaybackOutput(trimmed)'));
      expect(selector, contains('_macV2OutputSelectionEnabled'));
      expect(
        selector.indexOf('coordinator.selectPlaybackOutput(trimmed)'),
        lessThan(selector.lastIndexOf('JuceAudioEngine.selectOutputDevice')),
      );
      expect(v2Refresh, contains('JuceAudioEngine.getOutputDevices()'));
      expect(v2Refresh, contains('JuceAudioEngine.getInputDeviceInfos()'));
      expect(v2Refresh, contains('getCurrentOutputDeviceName()'));
      expect(v2Refresh, contains('final name = rawName.trim()'));
      expect(v2Refresh, contains('!outputDevices.contains(name)'));
      expect(v2Refresh, isNot(contains('getInputDevices')));
      expect(v2Refresh, isNot(contains('selectInputDevice')));
      expect(v2Refresh, isNot(contains('requestMicrophone')));
    },
  );

  test('explicit input selection prefers UID without audio mutation', () {
    final plugin = File(pluginPath).readAsStringSync();
    final apply = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );
    final selection = _between(
      apply,
      'if (updateInputPreference) {',
      'const BOOL explicitSelection = requestedName.length > 0;',
    );

    expect(apply, contains('args[@"inputDeviceUID"]'));
    expect(selection, contains('const BOOL explicitInputUID'));
    expect(
      selection,
      contains('MixroomInputForUID(inventory, requestedInputUID)'),
    );
    expect(selection, contains('!explicitInputUID && explicitInputName'));
    expect(
      selection,
      contains('MixroomExactDeviceMatches(inventory, requestedInputName, YES)'),
    );
    expect(selection, contains('inputMatches.count != 1'));
    expect(selection, contains('MixroomMacInputIsUsable'));
    expect(selection, contains('self.macSelectedInputUIDV2'));
    expect(selection, contains('followSystemInput'));
    expect(selection, isNot(contains('startMacInputProbeV2ObjC')));
    expect(selection, isNot(contains('reconfigureMacPlaybackRouteV2ObjC')));
    expect(selection, isNot(contains('waitForMacOutputCallbackProofV2ObjC')));
    expect(selection, isNot(contains('selectInputDeviceObjC')));
    expect(selection, isNot(contains('requestMicrophone')));
  });

  test('UID enumeration retains duplicate names and exact identity', () {
    final plugin = File(pluginPath).readAsStringSync();
    final enumeration = _between(
      plugin,
      'MixroomMacV2InputDeviceInfos(void) {',
      '- (NSDictionary<NSString *, id> *)currentMacPlaybackOutputV2:',
    );

    expect(enumeration, contains('@"uid": device[@"uid"] ?: @""'));
    expect(enumeration, isNot(contains('MixroomInputNameIsUnique')));
    expect(plugin, isNot(contains('static BOOL MixroomInputNameIsUnique(')));
  });

  test('macOS V2 refresh preserves and deduplicates inputs by UID', () {
    final editor = File(editorPath).readAsStringSync();
    final refresh = _between(
      editor,
      'Future<void> _loadMacV2AudioDevices() async {',
      'Widget _buildMicrophonePermissionNotice()',
    );

    expect(refresh, contains('inputDevicesByUID.putIfAbsent(uid'));
    expect(refresh, contains('containsKey(_macInputDeviceUID)'));
    expect(refresh, isNot(contains('inputDevices.contains(name)')));
  });

  test(
    'input enumeration rejects unavailable CoreAudio facts without messaging NSNull',
    () {
      final plugin = File(pluginPath).readAsStringSync();
      final validator = _between(
        plugin,
        'static BOOL MixroomMacInputIsUsable(',
        'static NSArray<NSDictionary<NSString *, id> *> *\n'
            'MixroomMacV2InputDeviceInfos(void)',
      );

      expect(
        validator,
        contains('[input[@"inputChannels"] isKindOfClass:[NSNumber class]]'),
      );
      expect(
        validator,
        contains('[input[@"sampleRateHz"] isKindOfClass:[NSNumber class]]'),
      );
      expect(
        validator,
        contains('[input[@"bufferFrames"] isKindOfClass:[NSNumber class]]'),
      );
      expect(
        validator,
        contains('[input[@"deviceID"] isKindOfClass:[NSNumber class]]'),
      );
    },
  );

  test('recording resolves the committed input UID through AUHAL', () {
    final plugin = File(pluginPath).readAsStringSync();
    final resolver = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)currentMacRecordingInputV2:\n'
          '    (NSArray<NSDictionary<NSString *, id> *> *)inventory {',
      '- (NSString *)currentMacPlaybackOutputFingerprintV2',
    );
    final intent = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );

    expect(resolver, contains('self.macSelectedInputUIDV2'));
    expect(resolver, contains('MixroomInputForUID'));
    expect(resolver, contains('MixroomDefaultCoreAudioInputDevice'));
    expect(intent, contains('[self currentMacRecordingInputV2:inventory]'));
    expect(intent, contains('startMacInputProbeV2ObjC:inputDeviceID'));
    expect(intent, isNot(contains('selectInputDeviceObjC')));
  });

  test('explicit output selection commits one verified CoreAudio UID', () {
    final plugin = File(pluginPath).readAsStringSync();
    final apply = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );

    expect(apply, contains('args[@"outputDeviceName"]'));
    expect(
      apply,
      contains('MixroomExactDeviceMatches(inventory, requestedName, NO)'),
    );
    expect(apply, contains('requestedMatches.count == 1'));
    expect(apply, contains('MixroomMacOutputIsUsable(inventory, target)'));

    final exactMatches = _between(
      plugin,
      'static NSArray<NSDictionary<NSString *, id> *> *MixroomExactDeviceMatches(',
      'static NSString *MixroomNormalizedMacRouteKind(',
    );
    expect(
      exactMatches,
      contains('stringByTrimmingCharactersInSet:'),
      reason:
          'CoreAudio device names may contain surrounding whitespace while '
          'JUCE/Flutter display a trimmed name; matching must normalize both '
          'sides while retaining the raw CoreAudio name as the JUCE open key.',
    );
    expect(exactMatches, contains('candidateName'));
    expect(exactMatches, contains('normalizedName'));
    expect(apply, contains('MixroomMacPlaybackSnapshotMatchesPlan'));
    expect(apply, contains('self.macSelectedOutputUIDV2 = target[@"uid"]'));
    expect(
      apply.indexOf('const BOOL opened'),
      lessThan(apply.indexOf('self.macSelectedOutputUIDV2 = target[@"uid"]')),
    );
    expect(
      apply,
      contains('reconfigureMacPlaybackRouteV2ObjC:restorableSource[@"name"]'),
    );
    expect(apply, contains('if (!success && targetUsable'));
    expect(apply, isNot(contains('if (!success && opened')));
    expect(
      apply,
      contains('MixroomOutputForUID(restoreInventory, source[@"uid"])'),
    );
    expect(apply, isNot(contains('selectOutputDeviceObjC')));
    expect(apply, isNot(contains('while (')));
    expect(apply, isNot(contains('sleep')));
  });

  test('recording and recovery resolve the committed output policy', () {
    final plugin = File(pluginPath).readAsStringSync();
    final intent = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );
    final recordingAdmission = _between(
      plugin,
      '- (BOOL)startMacIndependentInputRecordingV2:(NSString *)path\n'
          '                                channelStart:(NSInteger)channelStart\n'
          '                                channelCount:(NSInteger)channelCount {',
      '#else\n- (void)signalIOSIntentRouteConditionV2',
    );
    final observer = _between(
      plugin,
      '- (void)handleAudioRoutePropertyChangeV2:(NSString *)cause {',
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:',
    );

    expect(
      RegExp('currentMacPlaybackOutputV2').allMatches(intent).length,
      greaterThanOrEqualTo(4),
    );
    expect(recordingAdmission, contains('currentMacPlaybackOutputV2'));
    expect(observer, contains('currentMacPlaybackOutputV2'));
    expect(observer, contains('self.macSelectedOutputUIDV2 = nil'));
    expect(observer, contains('MixroomOutputFingerprint(policyOutput)'));
  });

  test('a live explicit output ignores unrelated system-default changes', () {
    final plugin = File(pluginPath).readAsStringSync();
    final resolver = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)currentMacPlaybackOutputV2:\n'
          '    (NSArray<NSDictionary<NSString *, id> *> *)inventory {',
      'static BOOL MixroomMacPlaybackSnapshotMatchesPlan',
    );
    final observer = _between(
      plugin,
      '- (void)handleAudioRoutePropertyChangeV2:(NSString *)cause {',
      '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:',
    );

    expect(resolver, contains('self.macSelectedOutputUIDV2'));
    expect(resolver, contains('MixroomOutputForUID(devices, selectedUID)'));
    expect(
      resolver.indexOf('MixroomOutputForUID(devices, selectedUID)'),
      lessThan(resolver.indexOf('MixroomDefaultCoreAudioOutputDevice()')),
    );
    expect(observer, contains('if ([fingerprint isEqualToString:'));
    expect(observer, contains('self.audioRouteFingerprintV2'));
    expect(observer, contains('MixroomMacOutputIdentityIsUsable'));
    expect(
      observer,
      contains('else if (!MixroomMacOutputIsUsable(inventory, selected))'),
    );
  });

  test('native play reports admission and Mac performs one owned recovery', () {
    final plugin = File(pluginPath).readAsStringSync();
    final bridge = File(bridgePath).readAsStringSync();
    final bridgeHeader = File(
      'juce_audio_engine/ios/Classes/JuceBridge.h',
    ).readAsStringSync();
    final engine = File(enginePath).readAsStringSync();
    final engineHeader = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    final api = File(
      'juce_audio_engine/lib/juce_audio_engine.dart',
    ).readAsStringSync();
    final editor = File(editorPath).readAsStringSync();
    final resume = _between(
      editor,
      'Future<void> _resumeAudio(',
      'Future<void> _pauseAudio(',
    );

    expect(engineHeader, contains('bool play();'));
    expect(engine, contains('bool JuceEngine::play()'));
    expect(
      engine,
      contains('V2 play blocked while output route is unavailable'),
    );
    expect(engine, contains('return false;'));
    expect(engine, contains('return true;'));
    expect(bridgeHeader, contains('+ (BOOL)playObjC;'));
    expect(bridge, contains('started = JuceEngine::get().play()'));
    expect(bridge, contains('messageManager->callSync(play)'));
    expect(plugin, contains('result(@([JuceBridge playObjC]))'));
    expect(api, contains('return res ?? false;'));
    expect(resume, contains('var playStarted = await JuceAudioEngine.play()'));
    expect(resume, contains('Platform.isMacOS'));
    expect(resume, contains('AudioRouteIntentV2.playbackOnly'));
    expect(resume, contains('acceptVerifiedAudioRouteTransitionV2'));
    expect(
      RegExp(
        r'playStarted = await JuceAudioEngine\.play\(\)',
      ).allMatches(resume).length,
      2,
    );
  });
}
