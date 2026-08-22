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
  const pluginPath = 'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m';
  const bridgePath = 'juce_audio_engine/ios/Classes/JuceBridge.mm';
  const enginePath = 'juce_audio_engine/ios/Classes/JuceEngine.cpp';
  const editorPath = 'lib/screens/audio_editor.dart';
  const coreAudioPath =
      'juce_audio_engine/android/src/main/cpp/juce/modules/'
      'juce_audio_devices/native/juce_CoreAudio_mac.cpp';

  test('macOS recording and probe share the system-selected intent route', () {
    final editor = File(editorPath).readAsStringSync();
    final support = _between(
      editor,
      'bool get _supportsV2AudioRecording =>',
      'List<String> _inputDevices',
    );
    final probe = _between(
      editor,
      'Future<void> _runMacOSSystemSelectedRouteProbeV2()',
      'Future<void> _runIOSSystemSelectedRouteProbeV2()',
    );

    expect(support, contains('Platform.isMacOS'));
    expect(
      editor,
      contains('AudioRouteIntentOperationV2.systemSelectedRecording'),
    );
    expect(probe, contains('AudioRouteIntentOperationV2.systemSelectedProbe'));
    expect(probe, contains("'macOSIndependentInput'"));
    expect(probe, contains('inputCallbackCount'));
    expect(probe, contains('outputCallbackCount'));
    expect(editor, contains('Run System Recording Route Check'));
  });

  test('macOS V2 input controls cannot open or prewarm a microphone', () {
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
    expect(
      selector,
      contains('System Default (change in macOS Sound settings)'),
    );
    expect(
      selector.indexOf('if (_isBluetoothV2Session && Platform.isMacOS)'),
      lessThan(selector.indexOf('JuceAudioEngine.selectInputDevice(name)')),
    );
  });

  test('macOS probe owns an independent input and output-only JUCE route', () {
    final plugin = File(pluginPath).readAsStringSync();
    final intent = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );

    expect(intent, contains('systemSelectedProbe'));
    expect(intent, contains('startMacInputProbeV2ObjC'));
    expect(intent, contains('waitForMacInputProbeCallbackV2ObjC'));
    expect(intent, contains('beginMacOutputCallbackProofV2ObjC'));
    expect(intent, contains('waitForMacOutputCallbackProofV2ObjC'));
    expect(intent, contains('reconfigureMacPlaybackRouteV2ObjC'));
    expect(intent, contains('sampleRate:[settledOutput[@"sampleRateHz"]'));
    expect(intent, contains('bufferFrames:[settledOutput[@"bufferFrames"]'));
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
    expect(adapter, contains('kAudioUnitScope_Input'));
    expect(adapter, contains('kAudioUnitScope_Output'));
    expect(adapter, contains('scratch.assign(capacityFrames, 0.0f)'));
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
      contains('wavCapture.start(file, inputSampleRate, 1, 0)'),
    );
    expect(
      externalCapture,
      contains('independentInputCaptureMode.store(true'),
    );
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
    expect(bridge, contains('scratch.data(), static_cast<int>(numberFrames)'));
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

  test('restoration proves the exact original output before release', () {
    final plugin = File(pluginPath).readAsStringSync();
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
    expect(restore, contains('sameDefault'));
    expect(restore, contains('self.macIntentSourceFingerprintV2'));
    expect(restore, contains('waitForMacOutputCallbackProofV2ObjC'));
    expect(restore, contains('reconfigureMacPlaybackRouteV2ObjC'));
    expect(
      restore,
      contains('sampleRate:[candidate[@"sampleRateHz"] doubleValue]'),
    );
    expect(
      restore,
      contains('bufferFrames:[candidate[@"bufferFrames"] integerValue]'),
    );
    expect(restore, contains('getMacOutputCallbackProofFramesV2ObjC'));
    expect(restore, contains('callbackShapeValid'));
    expect(restore, contains('const BOOL restorationVerified'));
    expect(restore, contains('if (!restorationVerified)'));
    expect(restore, contains('quiescePlaybackRouteV2ObjC:YES'));
    expect(restore, isNot(contains('exactBufferRestored')));
    expect(restore, contains('outputSnapshotIsValid(snapshot, source)'));
    expect(restore, isNot(contains('while (')));
    expect(restore, isNot(contains('waitUntilDate')));
  });

  test(
    'device removal closes the owned streams without replacement recovery',
    () {
      final plugin = File(pluginPath).readAsStringSync();
      final routeHandler = _between(
        plugin,
        '- (void)handleAudioRoutePropertyChangeV2:(NSString *)cause {',
        '- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:',
      );
      final ownedOperation = _between(
        routeHandler,
        'if (self.macIntentOperationActiveV2) {',
        'NSString *fingerprint = MixroomEffectiveOutputFingerprint();',
      );

      expect(ownedOperation, contains('macIntentOperationCancelledV2 = YES'));
      expect(ownedOperation, contains('quiescePlaybackRouteV2ObjC:YES'));
      expect(ownedOperation, contains('discardMacInputRecordingV2ObjC'));
      expect(ownedOperation, contains('stopMacInputProbeV2ObjC'));
      expect(ownedOperation, isNot(contains('reconfigurePlaybackRouteV2ObjC')));
    },
  );

  test('recording preparation removal uses the explicit reopen boundary', () {
    final editor = File(editorPath).readAsStringSync();
    final preflight = _between(
      editor,
      'Future<bool> _prepareAudioRecordingStartPreflight()',
      'Future<void> _startAudioRecordingJuce()',
    );

    expect(preflight, contains("'physicalRouteInvalidation'"));
    expect(
      preflight,
      contains(
        'The audio device disconnected during recording preparation. '
        'Reopen the audio editor.',
      ),
    );
  });

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
      '#if JUCE_MAC && !JUCE_IOS\nvoid JuceEngine::beginMacOutputCallbackProofV2()',
    );

    expect(startup, contains('initialiseMacPlaybackV2ObjC'));
    expect(startup, contains('target[@"sampleRateHz"]'));
    expect(startup, contains('target[@"bufferFrames"]'));
    expect(apply, contains('reconfigureMacPlaybackRouteV2ObjC'));
    expect(apply, contains('waitForMacOutputCallbackProofV2ObjC'));
    expect(genericReopen, contains('juce::ignoreUnused(outputDeviceName)'));
    expect(genericReopen, contains('return false;'));
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
}
