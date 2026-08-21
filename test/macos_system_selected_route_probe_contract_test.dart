import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final plugin = File(
    'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
  ).readAsStringSync();
  final engine = File(
    'juce_audio_engine/ios/Classes/JuceEngine.cpp',
  ).readAsStringSync();
  final bridge = File(
    'juce_audio_engine/ios/Classes/JuceBridge.mm',
  ).readAsStringSync();
  final coreAudioBackend = File(
    'juce_audio_engine/android/src/main/cpp/juce/modules/'
    'juce_audio_devices/native/juce_CoreAudio_mac.cpp',
  ).readAsStringSync();
  final editor = File('lib/screens/audio_editor.dart').readAsStringSync();

  test('macOS probe uses CoreAudio defaults without choosing an input', () {
    expect(
      plugin,
      contains(
        '[args[@"intentOperation"] isKindOfClass:[NSString class]]',
      ),
    );
    expect(plugin, isNot(contains('args[@"operation"]')));
    final start = plugin.indexOf(
      'if ([intent isEqualToString:@"preparingRecording"] &&\n'
      '        [intentOperation isEqualToString:@"systemSelectedProbe"])',
    );
    final end = plugin.indexOf(
      'if ([intent isEqualToString:@"playbackOnly"] &&',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final probe = plugin.substring(start, end);

    expect(probe, contains('MixroomDefaultCoreAudioInputDevice()'));
    expect(probe, contains('MixroomDefaultCoreAudioOutputDevice()'));
    expect(probe, contains('MixroomInputForDeviceID'));
    expect(probe, contains('MixroomOutputForDeviceID'));
    expect(probe, contains('MixroomCoreAudioEndpointIsMechanicallyOpenable'));
    expect(probe, isNot(contains('MixroomUniqueBuiltInInput')));
    expect(probe, isNot(contains('MixroomOutputSupportsV2Recording')));
    expect(probe, isNot(contains('MixroomAudioDeviceNameLooksBluetooth')));
    expect(probe, isNot(contains('startRecordingObjC')));
    expect(probe, isNot(contains('setPreferred')));
  });

  test('macOS split defaults bypass the unsafe JUCE 8 device combiner', () {
    final start = plugin.indexOf(
      'if ([intent isEqualToString:@"preparingRecording"] &&\n'
      '        [intentOperation isEqualToString:@"systemSelectedProbe"])',
    );
    final end = plugin.indexOf(
      'if ([intent isEqualToString:@"playbackOnly"] &&',
      start,
    );
    final probe = plugin.substring(start, end);

    expect(plugin, contains('MixroomCreatePrivateAggregateDevice('));
    expect(plugin, contains('kAudioAggregateDeviceIsPrivateKey'));
    expect(plugin, contains('kAudioAggregateDeviceClockDeviceKey'));
    expect(plugin, contains('kAudioSubDeviceDriftCompensationKey'));
    expect(plugin, contains('waitForMacAggregateDeviceV2Until'));
    expect(plugin, contains('macIntentRouteConditionV2'));
    expect(probe, contains('defaultInputID != defaultOutputID'));
    expect(probe, contains('aggregate[@"name"]'));
    expect(probe, contains('inputName:duplexInputName'));
    expect(probe, contains('duplexOutputName'));
    expect(
      probe,
      isNot(
        contains(
          '// JUCE 8 opens distinct CoreAudio defaults through\n'
          '            // AudioIODeviceCombiner',
        ),
      ),
    );

    final restoreStart = plugin.lastIndexOf(
      '- (BOOL)openMacPlaybackTargetV2:',
    );
    final restoreEnd = plugin.indexOf(
      '- (BOOL)claimMacIntentCleanupV2',
      restoreStart,
    );
    final restore = plugin.substring(restoreStart, restoreEnd);
    expect(restore, contains('closeMacRoutePhaseV2ObjC'));
    expect(restore, contains('destroyMacIntentAggregateDeviceV2'));
    expect(
      restore.indexOf('closeMacRoutePhaseV2ObjC'),
      lessThan(restore.indexOf('destroyMacIntentAggregateDeviceV2')),
    );
    expect(
      restore.indexOf('destroyMacIntentAggregateDeviceV2'),
      lessThan(restore.indexOf('beginMacPlaybackRoutePhaseV2ObjC')),
    );
    final aggregateWaitStart = plugin.lastIndexOf(
      '- (BOOL)waitForMacAggregateDeviceV2Until:',
    );
    final aggregateWaitEnd = plugin.indexOf(
      '- (BOOL)destroyMacIntentAggregateDeviceV2',
      aggregateWaitStart,
    );
    final aggregateWait = plugin.substring(
      aggregateWaitStart,
      aggregateWaitEnd,
    );
    expect(aggregateWait, contains('[condition waitUntilDate:'));
    expect(aggregateWait, contains('macIntentOperationCancelledV2'));
    expect(aggregateWait, isNot(contains('sleep')));
    expect(aggregateWait, isNot(contains('dispatch_after')));
  });

  test('macOS probe separates message-thread mutation from worker wait', () {
    final beginStart = engine.indexOf(
      'bool JuceEngine::beginMacSystemSelectedDuplexPhaseV2(',
    );
    final beginEnd = engine.indexOf(
      'bool JuceEngine::waitForMacRoutePhaseCallbackV2(',
      beginStart,
    );
    final begin = engine.substring(beginStart, beginEnd);
    final waitEnd = engine.indexOf(
      'juce::NamedValueSet JuceEngine::getMacRoutePhaseFactsV2()',
      beginEnd,
    );
    final wait = engine.substring(beginEnd, waitEnd);

    expect(begin, contains('deviceManager.initialise('));
    expect(begin, contains('deviceType->scanForDevices()'));
    expect(
      begin,
      contains('metronomeCallback->beginFirstValidCallbackProof()'),
    );
    expect(begin, contains('liveInputMonitoringEnabled = false'));
    expect(begin, contains('isThisTheMessageThread()'));
    expect(begin, isNot(contains('waitForFirstValidCallback')));
    expect(wait, contains('waitForFirstValidCallback(timeoutMilliseconds)'));
    expect(wait, contains('!juce::MessageManager::getInstance()'));
    expect(wait, isNot(contains('deviceManager.')));
    expect(begin, isNot(contains('startRecording')));
    expect(begin, isNot(contains('ThreadedWriter')));
    expect(begin, isNot(contains('sleep')));
  });

  test('callback proof survives an owned CoreAudio stop-start cycle', () {
    final header = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    final callbackStart = header.lastIndexOf('class MetronomeAudioCallback');
    final callbackEnd = header.indexOf(
      'class IOSBluetoothDuplexProbeCallback',
      callbackStart,
    );
    final callback = header.substring(callbackStart, callbackEnd);
    final stoppedStart = callback.indexOf('void audioDeviceStopped() override');
    final stoppedEnd = callback.indexOf(
      'void audioDeviceIOCallbackWithContext(',
      stoppedStart,
    );
    final stopped = callback.substring(stoppedStart, stoppedEnd);

    expect(
      stopped,
      isNot(contains('firstValidCallbackRequested.store(false')),
    );
    expect(stopped, contains('firstValidCallbackCompleted.store(false'));
    expect(callback, contains('while (firstValidCallbackRequested.load'));
    expect(callback, contains('remainingMs'));
    expect(callback, contains('cancelFirstValidCallbackProofWait'));
    expect(callback, isNot(contains('sleep')));
  });

  test('macOS phase bridge serializes mutation and facts on JUCE message thread', () {
    expect(bridge, contains('MixroomCallBoolOnJuceMessageThreadSync'));
    expect(bridge, contains('MixroomCallVoidOnJuceMessageThreadSync'));
    expect(bridge, contains('beginMacSystemSelectedDuplexPhaseV2ObjC'));
    expect(bridge, contains('beginMacPlaybackRoutePhaseV2ObjC'));
    expect(bridge, contains('macRoutePhaseFactsV2ObjC'));
    expect(bridge, contains('closeMacRoutePhaseV2ObjC'));
    expect(
      bridge,
      isNot(contains('reconfigureSystemSelectedRecordingProbeV2ObjC')),
    );
    expect(
      bridge,
      isNot(contains('reconfigurePlaybackRouteWithCallbackProofV2ObjC')),
    );
  });

  test('macOS CoreAudio reopen republishes the requested callback capacity', () {
    final reopenStart = coreAudioBackend.indexOf('String reopen (');
    final reopenEnd = coreAudioBackend.indexOf(
      'bool start (AudioIODeviceCallback* callbackToNotify)',
      reopenStart,
    );
    final reopen = coreAudioBackend.substring(reopenStart, reopenEnd);
    final requestedShape = reopen.indexOf(
      'bufferSize = bufferSizeSamples;',
    );
    final reallocate = reopen.indexOf('allocateTempBuffers();', requestedShape);

    expect(reopenStart, greaterThanOrEqualTo(0));
    expect(requestedShape, greaterThanOrEqualTo(0));
    expect(reallocate, greaterThan(requestedShape));
    expect(reopen, contains('const ScopedLock sl (callbackLock);'));
  });

  test('explicit macOS restoration requests the preserved media rate', () {
    final openStart = engine.indexOf(
      'bool JuceEngine::openPlaybackOutputOnlyV2(',
    );
    final openEnd = engine.indexOf(
      'bool JuceEngine::openRecordingInputV2(',
      openStart,
    );
    final open = engine.substring(openStart, openEnd);
    expect(open, contains('double preferredSampleRateHz'));
    expect(
      open,
      contains(
        'setup.sampleRate = preferredSampleRateHz > 1000.0\n'
        '        ? preferredSampleRateHz\n'
        '        : 0.0;',
      ),
    );

    final helperStart = plugin.lastIndexOf('- (BOOL)openMacPlaybackTargetV2:');
    final helperEnd = plugin.indexOf(
      '- (BOOL)claimMacIntentCleanupV2',
      helperStart,
    );
    final helper = plugin.substring(helperStart, helperEnd);
    expect(helper, contains('beginMacPlaybackRoutePhaseV2ObjC:'));
    expect(
      helper,
      contains('target[@"sampleRateHz"]'),
    );
    expect(plugin, contains('const BOOL sampleRateMatches ='));
    expect(plugin, contains('actualSampleRate > 1000.0 && sampleRateMatches'));
  });

  test('post-restore removal recovers once to the current system output', () {
    final restorationStart = plugin.indexOf(
      'if ([intent isEqualToString:@"playbackOnly"] &&\n'
      '        self.macIntentOperationActiveV2)',
    );
    final restorationEnd = plugin.indexOf(
      'if (!self.audioRouteMonitoringV2 ||',
      restorationStart,
    );
    final restoration = plugin.substring(restorationStart, restorationEnd);

    expect(restoration, contains('const BOOL sourceUnavailable ='));
    expect(restoration, contains('outputChangedDuringRestoration'));
    expect(restoration, contains('requireReplacement:YES'));
    expect(restoration, contains('MixroomDefaultCoreAudioOutputDevice()'));
    expect(restoration, contains('const double operationDeadlineMs ='));
    expect(restoration, isNot(contains('dispatch_after')));
    expect(restoration, isNot(contains('sleep')));
    expect(restoration, isNot(contains('retry')));
  });

  test('engine startup opens CoreAudio before taking the graph callback lock', () {
    final start = engine.indexOf(
      'void JuceEngine::initialiseEngine(const juce::String &v2OutputDeviceName)',
    );
    final end = engine.indexOf(
      'bool JuceEngine::initialisePlaybackV2(',
      start,
    );
    final initialise = engine.substring(start, end);
    final open = initialise.indexOf('openPlaybackOutputOnlyV2(');
    final graphLock = initialise.indexOf('GraphMutationScope renderLock(');
    final attach = initialise.indexOf(
      'deviceManager.addAudioCallback(metronomeCallback.get())',
    );

    expect(open, greaterThanOrEqualTo(0));
    expect(graphLock, greaterThan(open));
    expect(attach, greaterThan(graphLock));
    expect(
      initialise,
      contains(
        'if (!isV2PlaybackSession())\n'
        '    {\n'
        '        deviceManager.removeChangeListener(this);\n'
        '        deviceManager.addChangeListener(this);',
      ),
    );
  });

  test('macOS V2 startup runs on the existing lifecycle executor', () {
    final methodStart = plugin.indexOf(
      'else if ([call.method isEqualToString:@"initialisePlaybackV2"])',
    );
    final methodEnd = plugin.indexOf(
      'else if ([call.method isEqualToString:@"startAudioRouteMonitoringV2"])',
      methodStart,
    );
    final method = plugin.substring(methodStart, methodEnd);

    expect(method, contains('dispatch_async(MixroomMacLifecycleQueue()'));
    expect(method, contains('[self initialisePlaybackV2]'));
    expect(method, contains('dispatch_async(dispatch_get_main_queue()'));
    expect(method, contains('result(response)'));
  });

  test('macOS explicit lifecycle is serialized and observer-owned', () {
    expect(plugin, contains('MixroomMacLifecycleQueue()'));
    expect(plugin, contains('macLifecycleTransitionActiveV2'));
    expect(plugin, contains('macIntentOperationActiveV2'));
    expect(plugin, contains('claimMacIntentCleanupV2'));
    expect(plugin, contains('macPublishedLifecycleFactsV2'));
    expect(plugin, contains('finishMacIntentOperationOnMainV2'));
    expect(plugin, contains('defaultInputChanged'));
    expect(plugin, contains('handleMacAudioRoutePropertyChangeV2'));
    expect(plugin, contains('@"snapshot"] = @"lifecycleTransitionInProgress"'));
    final lifecycleStart = plugin.indexOf(
      '- (void)setAudioRouteIntentV2:(NSDictionary *)args',
    );
    final lifecycleEnd = plugin.indexOf(
      '- (void)updateObservedOutputDeviceV2:',
      lifecycleStart,
    );
    expect(
      plugin.substring(lifecycleStart, lifecycleEnd),
      isNot(contains('dispatch_after')),
    );
  });

  test('macOS removal recovery waits for the system replacement output once', () {
    final macLifecycleStart = plugin.lastIndexOf(
      '- (void)signalMacIntentRouteConditionV2:',
    );
    final macLifecycle = plugin.substring(
      macLifecycleStart,
      plugin.indexOf(
        '#else\n- (void)signalIOSIntentRouteConditionV2',
        macLifecycleStart,
      ),
    );
    expect(macLifecycle, contains('macIntentRouteConditionV2'));
    expect(macLifecycle, contains('signalMacIntentRouteConditionV2'));
    expect(macLifecycle, contains('waitForMacCurrentOutputV2Until'));
    expect(macLifecycle, contains('MixroomDefaultCoreAudioOutputDevice()'));
    expect(
      plugin,
      contains('[JuceBridge quiescePlaybackRouteV2ObjC:YES]'),
    );
    expect(plugin, contains('startedAtMs + 2000.0'));
    expect(macLifecycle, isNot(contains('dispatch_after')));
    expect(macLifecycle, isNot(contains('sleepForMilliseconds')));
  });

  test('late macOS removal uses the shared single output-recovery owner', () {
    expect(
      editor,
      contains(
        '(Platform.isIOS || Platform.isAndroid || Platform.isMacOS) &&',
      ),
    );
    expect(editor, contains('recoverPlaybackAfterIntentInvalidation()'));
  });

  test('macOS route notifications invalidate from readback after callback return', () {
    final listenerStart = plugin.indexOf(
      'static OSStatus MixroomAudioRoutePropertyListenerV2(',
    );
    final listenerEnd = plugin.indexOf(
      '\n#endif\n\n@implementation JuceAudioEnginePlugin',
      listenerStart,
    );
    final listener = plugin.substring(listenerStart, listenerEnd);
    expect(listener, contains('dispatch_async(dispatch_get_main_queue()'));
    expect(listener, isNot(contains('signalMacIntentRouteConditionV2:cause')));

    final classifierStart = plugin.lastIndexOf(
      '- (BOOL)macIntentRouteInvalidatedV2ForCause:',
    );
    final classifierEnd = plugin.indexOf(
      '- (void)signalMacIntentRouteConditionV2:',
      classifierStart,
    );
    final classifier = plugin.substring(classifierStart, classifierEnd);
    expect(classifier, contains('MixroomDefaultCoreAudioInputDevice()'));
    expect(classifier, contains('MixroomDefaultCoreAudioOutputDevice()'));
    expect(classifier, contains('MixroomCoreAudioPhysicalIdentitiesMatch'));
    expect(classifier, contains('MixroomCoreAudioDeviceIsAlive'));
    expect(
      classifier,
      isNot(
        contains(
          '[cause isEqualToString:@"defaultOutputChanged"] ||',
        ),
      ),
    );
    expect(plugin, contains('[self.macIntentRouteConditionV2 retain]'));
  });

  test('macOS explicit operation publishes immutable post-phase facts', () {
    final snapshotStart = plugin.lastIndexOf(
      '- (NSDictionary<NSString *, id> *)buildAudioRouteSnapshotV2',
    );
    final snapshotEnd = plugin.indexOf(
      '- (NSDictionary<NSString *, id> *)initialisePlaybackV2',
      snapshotStart,
    );
    final snapshot = plugin.substring(snapshotStart, snapshotEnd);
    expect(snapshot, contains('usePublishedLifecycleFacts'));
    expect(snapshot, contains('macPublishedLifecycleFactsV2'));

    final operationStart = plugin.indexOf(
      'if ([intent isEqualToString:@"preparingRecording"] &&\n'
      '        [intentOperation isEqualToString:@"systemSelectedProbe"])',
    );
    final operationEnd = plugin.indexOf(
      'if ([intent isEqualToString:@"playbackOnly"] &&',
      operationStart,
    );
    final operation = plugin.substring(operationStart, operationEnd);
    expect(operation, contains('beginMacSystemSelectedDuplexPhaseV2ObjC'));
    expect(operation, contains('waitForMacRoutePhaseCallbackV2ObjC'));
    expect(operation, contains('macRoutePhaseFactsV2ObjC'));
    expect(operation, isNot(contains('dispatch_after')));
    expect(operation, isNot(contains('sleep')));
  });

  test('macOS diagnostics and desktop action expose the proof', () {
    expect(plugin, contains('@"selectionMode": @"macOSSystemSelected"'));
    expect(plugin, contains('@"actualCallbackCount"'));
    expect(plugin, contains('@"cleanupOutcome"'));
    expect(plugin, contains('@"restoredOutput"'));
    expect(editor, contains('_runMacOSSystemSelectedRouteProbeV2'));
    expect(editor, contains('Run System Recording Route Check'));
    expect(
      editor,
      contains("duplexProbe?.selectionMode == 'macOSSystemSelected'"),
    );
  });

  test('production macOS recording policy remains separate', () {
    expect(plugin, contains('MixroomOutputSupportsV2Recording'));
    expect(plugin, contains('MixroomUniqueBuiltInInput'));
    expect(plugin, contains('MixroomSnapshotMatchesRecordingRoute'));
  });
}
