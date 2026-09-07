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
  const editorPath = 'lib/screens/audio_editor.dart';

  test('V2 monitoring is available only through verified platform paths', () {
    final editor = File(editorPath).readAsStringSync();
    final routingSheet = _between(
      editor,
      'Future<void> _showAudioRoutingSheet() async {',
      'Widget _buildAudioRoutingLauncher()',
    );

    expect(routingSheet, contains('_v2LiveMonitoringAvailable'));
    expect(
      routingSheet,
      contains('final monitoringEnabled = _isBluetoothV2Session'),
    );
    expect(routingSheet, contains('onChanged: monitoringAvailable'));
    expect(
      routingSheet,
      contains('!monitoringAvailable && !monitoringEnabled'),
    );
    expect(
      routingSheet,
      contains('Monitoring is unavailable for the current audio route.'),
    );
  });

  test('routing sheet meter follows recording or monitored row signal', () {
    final editor = File(editorPath).readAsStringSync();
    final routingSheet = _between(
      editor,
      'Future<void> _showAudioRoutingSheet() async {',
      'Widget _buildAudioRoutingLauncher()',
    );

    expect(routingSheet, contains('JuceAudioEngine.getRowMeterValues('));
    expect(routingSheet, contains('_v2LiveMonitoringTargetRowId'));
    expect(routingSheet, contains('_rowIndexForId('));
    expect(routingSheet, contains('_recordingPeaks.last'));
    expect(routingSheet, contains('StreamBuilder<double>'));
    expect(routingSheet, contains('Stream<void>.periodic('));
    expect(routingSheet, contains('_setNativeMeteringEnabled(true)'));
    expect(
      routingSheet,
      contains('_setNativeMeteringEnabled(_shouldPollMetersDuringPlayback)'),
    );
  });

  test(
    'legacy monitoring action remains wired to the existing engine path',
    () {
      final editor = File(editorPath).readAsStringSync();
      final routingSheet = _between(
        editor,
        'Future<void> _showAudioRoutingSheet() async {',
        'Widget _buildAudioRoutingLauncher()',
      );
      final monitoringAction = _between(
        editor,
        'Future<void> _setRoutingSheetMonitoring(bool enabled) async {',
        'Future<void> _showAudioRoutingSheet() async {',
      );

      expect(routingSheet, contains('_setRoutingSheetMonitoring('));
      expect(
        monitoringAction,
        contains('JuceAudioEngine.setLiveInputMonitoringEnabled(enabled)'),
      );
      expect(monitoringAction, contains('if (_isBluetoothV2Session)'));
      expect(monitoringAction, contains('_setV2LiveMonitoring(enabled)'));
    },
  );

  test('legacy Bluetooth monitor override is hidden in V2 sessions', () {
    final editor = File(editorPath).readAsStringSync();
    final policyCard = _between(
      editor,
      'Widget _buildBluetoothRecordingPolicyCard() {',
      'Widget _buildTempoSelector() {',
    );

    expect(policyCard, contains('if (_isBluetoothV2Session)'));
    expect(policyCard, contains('return const SizedBox.shrink();'));
    expect(policyCard, contains('Advanced: monitor anyway'));
  });

  test(
    'platform monitoring is coordinator owned and Bluetooth fail closed',
    () {
      final editor = File(editorPath).readAsStringSync();
      final action = _between(
        editor,
        'Future<bool> _activateV2LiveMonitoringTarget({',
        'Future<bool> _disableV2MonitoringBeforeRemovingRow(',
      );
      expect(action, contains('AudioRouteIntentV2.monitoring'));
      expect(action, contains('systemSelectedMonitoring'));
      expect(action, contains('AudioRouteKindV2.builtIn'));
      expect(action, contains('AudioRouteKindV2.wired'));
      expect(action, contains('AudioRouteKindV2.external'));
      expect(action, isNot(contains('AudioRouteKindV2.bluetoothMedia')));
    },
  );

  test('monitoring ownership follows stable row identity', () {
    final editor = File(editorPath).readAsStringSync();
    expect(editor, contains('int? _v2LiveMonitoringTargetRowId;'));
    expect(editor, isNot(contains('int? _v2LiveMonitoringTargetRow;')));
    expect(editor, contains('_rowIndexForId(_v2LiveMonitoringTargetRowId!)'));
    expect(editor, contains('_v2LiveMonitoringTargetRowId = rowId;'));

    final deletion = _between(
      editor,
      'Future<bool> _deleteRowImpl(int row) async {',
      'Future<void> _deleteRow(int row) async {',
    );
    expect(
      deletion.indexOf('_disableV2MonitoringBeforeRemovingRow'),
      lessThan(deletion.indexOf('JuceAudioEngine.removeRow')),
    );
  });

  test('iOS monitoring uses one verified non-Bluetooth duplex lifecycle', () {
    final plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    final bridge = File(
      'juce_audio_engine/ios/Classes/JuceBridge.mm',
    ).readAsStringSync();

    expect(plugin, contains('systemSelectedMonitoring'));
    expect(plugin, contains('MixroomIOSMonitoringEndpointIsAllowed'));
    expect(plugin, contains('MixroomIOSSystemSelectedTargetMatchesSource'));
    expect(plugin, contains('iosIntentOperationTargetFingerprintV2'));
    expect(plugin, contains('clockAgreement'));
    expect(plugin, contains('setLiveInputMonitorTargetV2ObjC'));
    expect(plugin, contains('disableLiveInputMonitoringV2ObjC'));
    expect(plugin, contains('finalizeRecordingForMonitoringV2ObjC'));
    expect(plugin, contains('prepareSystemSelectedDuplexSessionV2ObjC'));
    expect(plugin, contains('openPreparedSystemSelectedDuplexRouteV2ObjC'));
    expect(engine, contains('bool JuceEngine::setLiveInputMonitorTargetV2'));
    expect(
      engine,
      contains('if (!v2Recording || !liveInputMonitoringEnabled)'),
    );
    expect(bridge, contains('finalizeRecordingCaptureV2'));
  });

  test('iOS legacy monitoring cannot bypass V2 ownership', () {
    final engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    final legacyStart = engine.indexOf(
      'void JuceEngine::setLiveInputMonitoringEnabled(bool enabled)',
    );
    final v2TargetStart = engine.indexOf(
      'bool JuceEngine::setLiveInputMonitorTargetV2',
      legacyStart,
    );
    final legacy = engine.substring(legacyStart, v2TargetStart);

    expect(legacy, contains('if (isV2PlaybackSession())'));
    expect(legacy, contains('liveInputMonitoringActiveV2.store(false'));
    expect(legacy, contains('liveInputMonitoringEnabled = false'));
  });

  test('macOS independent monitoring bridge is coordinator activated', () {
    final header = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    final plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final bridge = File(
      'juce_audio_engine/ios/Classes/JuceBridge.mm',
    ).readAsStringSync();

    expect(header, contains('#if JUCE_MAC && !JUCE_IOS'));
    expect(header, contains('MacIndependentMonitorBuffer.h'));
    expect(header, contains('class MacIndependentMonitorSourceProcessor'));
    expect(bridge, contains('prepareMacIndependentInputMonitoringV2ObjC'));
    expect(plugin, contains('systemSelectedMonitoring'));
    expect(plugin, contains('MixroomMacMonitoringTransportIsAllowed'));
    expect(plugin, contains('prepareMacIndependentInputMonitoringV2ObjC'));
    expect(plugin, contains('getMacIndependentInputMonitoringFactsV2ObjC'));
    expect(
      File(editorPath).readAsStringSync(),
      isNot(contains('prepareMacIndependentInputMonitoringV2')),
    );
  });

  test('macOS monitoring commits only after exact route and bridge proof', () {
    final plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final intent = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );
    final bridgePrepare = intent.indexOf(
      'prepareMacIndependentInputMonitoringV2ObjC',
    );
    final inputProof = intent.indexOf('inputFactsValid && outputFactsValid');
    final monitoringCommit = intent.indexOf(
      'self.currentAudioRouteIntentV2 = monitoringIntent',
    );

    expect(intent, contains('monitoringTargetRow < 0'));
    expect(intent, contains('MixroomMacMonitoringTransportIsAllowed'));
    expect(intent, contains('self.macIntentSourceFingerprintV2'));
    expect(intent, contains('monitoringClockValid'));
    expect(intent, contains('MixroomMacMonitoringSharesClockDomain'));
    expect(intent, contains('monitoringFacts[@"active"]'));
    expect(intent, contains('monitoringFacts[@"targetRow"]'));
    expect(intent, contains('monitoringFacts[@"channelCount"]'));
    expect(inputProof, greaterThanOrEqualTo(0));
    expect(bridgePrepare, greaterThan(inputProof));
    expect(monitoringCommit, greaterThan(bridgePrepare));
  });

  test('macOS monitoring UI requires verified route and clock facts', () {
    final editor = File(editorPath).readAsStringSync();
    final refresh = _between(
      editor,
      'Future<void> _refreshSystemSelectedRouteInfoV2() async {',
      'Future<void> _refreshAndroidOutputRouteLabel(',
    );
    expect(refresh, contains('Platform.isMacOS'));
    expect(refresh, contains('advertisedInput.clockDomain'));
    expect(refresh, contains('_v2MonitoringClockCompatible'));
    expect(
      editor,
      contains('!Platform.isMacOS || _v2MonitoringClockCompatible'),
    );
  });

  test('first-take channel metadata does not open the input route', () {
    final editor = File(editorPath).readAsStringSync();
    final refresh = _between(
      editor,
      'Future<void> _refreshSystemSelectedRouteInfoV2() async {',
      'Future<void> _refreshAndroidOutputRouteLabel(',
    );
    expect(refresh, contains('JuceAudioEngine.getInputDeviceInfos()'));
    expect(refresh, contains('advertisedInput?.channelCount'));
    expect(refresh, isNot(contains('prepareRecordingInputs')));
    expect(refresh, isNot(contains('transitionIntent')));

    final selector = _between(
      editor,
      'Widget _buildInputChannelRouteSelector() {',
      'Widget _buildDawAudioEngineSettingsControls() {',
    );
    expect(selector, contains('if (!_isBluetoothV2Session'));
  });

  test('macOS monitoring cleanup gates the bridge before route teardown', () {
    final plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final intent = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );
    final playbackCleanup = _between(
      intent,
      '} else if ([intent isEqualToString:@"playbackOnly"] &&',
      '} else if (![intent isEqualToString:@"playbackOnly"])',
    );

    expect(
      playbackCleanup.indexOf('disableMacIndependentInputMonitoringV2ObjC'),
      lessThan(playbackCleanup.indexOf('stopMacInputProbeV2ObjC')),
    );
    expect(plugin, contains('@"monitoringRouteInvalidated"'));
    expect(plugin, contains('const BOOL monitoringProfileStable'));
    expect(plugin, contains('monitoringFacts[@"active"]'));
    expect(plugin, contains('self.macIntentMonitoringTargetRowV2'));
    expect(plugin, contains('self.macIntentRecordingChannelCountV2'));
    expect(plugin, contains('self.macIntentSourceFingerprintV2'));
    expect(plugin, contains('!monitoringProfileStable'));
  });

  test('macOS capture reuses monitoring without changing its target', () {
    final editor = File(editorPath).readAsStringSync();
    final preflight = _between(
      editor,
      'Future<bool> _prepareAudioRecordingStartPreflight() async {',
      'Future<void> _startAudioRecordingJuce() async {',
    );
    final mac = _between(
      preflight,
      'if (Platform.isMacOS || Platform.isAndroid || Platform.isIOS) {',
      '    var v2IntentOperation',
    );
    expect(mac, contains('_preparedRecordingChannelStart ='));
    expect(mac, contains('_v2LiveMonitoringChannelCount'));
    expect(mac, isNot(contains('_suspendMacV2MonitoringForRecording')));
    expect(mac, isNot(contains('_setV2LiveMonitoring(false)')));
    expect(mac, isNot(contains('_v2LiveMonitoringTargetRowId ==')));
    expect(editor, isNot(contains('_macV2MonitoringSuspendedForRecording')));
  });

  test(
    'macOS returns to monitoring before publication, including failed takes',
    () {
      final editor = File(editorPath).readAsStringSync();
      final restore = _between(
        editor,
        'Future<bool> _restoreV2RouteAfterAudioRecording() async {',
        'Future<bool> _ensureMicrophonePermissionForRecording() async {',
      );
      expect(restore, contains('Platform.isMacOS'));
      expect(restore, contains('AudioRouteIntentV2.monitoring'));
      final stop = _between(
        editor,
        'Future<void> _stopAudioRecordingJuce({bool keepPlaying = true}) async {',
        'Future<void> _addAudioTrackFromFile(',
      );
      expect(
        stop.indexOf('_restoreV2RouteAfterAudioRecording()'),
        lessThan(stop.indexOf('if (!captureResult.success)')),
      );
      expect(
        stop,
        isNot(contains('_resumeMacV2MonitoringAfterPublishedRecording')),
      );
    },
  );

  test(
    'native macOS validates retained monitoring for capture and route changes',
    () {
      final plugin = File(
        'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
      ).readAsStringSync();
      final start = _between(
        plugin.substring(
          plugin.indexOf('@implementation JuceAudioEnginePlugin'),
        ),
        '- (BOOL)startMacIndependentInputRecordingV2:(NSString *)path\n',
        '#else\n- (void)signalIOSIntentRouteConditionV2',
      );
      expect(start, contains('monitoringCapture'));
      expect(start, contains('[self isMacMonitoringSessionReusableV2]'));
      expect(plugin, contains('reusesMacMonitoringRoute'));
      final route = _between(
        plugin,
        'const BOOL monitoringWasActive =\n',
        'const BOOL invalidated = expectedInput',
      );
      expect(route, contains('systemSelectedMonitoring'));
    },
  );

  test('cancel-only record taps preserve supported monitor owners', () {
    final editor = File(editorPath).readAsStringSync();
    final handler = _between(
      editor,
      'Future<void> _handleRecordPressed({required bool keepPlayingOnStop}) async {',
      'String _normalizeEffectText(',
    );
    expect(handler, contains('!((Platform.isMacOS || Platform.isAndroid || Platform.isIOS) &&'));
    expect(handler, contains('_v2LiveMonitoringActive)'));
    final plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final abort = _between(
      plugin,
      'else if ([call.method isEqualToString:@"abortRecordingV2"]) {',
      '#else\n        if ([[JuceBridge getAudioRouteImplementationObjC]',
    );
    expect(abort, contains('cancelOnly && self.macIntentOperationActiveV2'));
    expect(
      abort.indexOf('systemSelectedMonitoring'),
      lessThan(abort.indexOf('self.macIntentOperationCancelledV2 = YES')),
    );
  });

  test('macOS monitoring callbacks use a bounded fail-closed transport', () {
    final buffer = File(
      'juce_audio_engine/native/MacIndependentMonitorBuffer.h',
    ).readAsStringSync();
    final push = _between(buffer, 'bool push(', 'void read(');
    final read = _between(buffer, 'void read(', 'bool isActive()');

    expect(buffer, contains('static constexpr int storageFrames'));
    expect(buffer, contains('8 * juce::jmax'));
    expect(buffer, contains('2 * outputBlockFrames'));
    expect(buffer, contains('std::abs(inputSampleRate - outputSampleRate)'));
    expect(buffer, contains('underflows.fetch_add'));
    expect(buffer, contains('overflows.fetch_add'));
    expect(buffer, contains('invalidBlocks.fetch_add'));
    expect(push, contains('active.load(std::memory_order_acquire)'));
    expect(read, contains('output.clear()'));
    for (final callback in <String>[push, read]) {
      expect(callback, isNot(contains('std::lock')));
      expect(callback, isNot(contains('Logger')));
      expect(callback, isNot(contains('sleep')));
      expect(callback, isNot(contains('graph.')));
      expect(callback, isNot(contains('setSize(')));
    }
  });

  test('macOS monitoring disables before disconnecting its graph source', () {
    final engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    final disable = _between(
      engine,
      'void JuceEngine::disableMacIndependentInputMonitoringV2()',
      'juce::NamedValueSet\nJuceEngine::getMacIndependentInputMonitoringFactsV2()',
    );
    final gate = disable.indexOf(
      'macIndependentMonitorBuffer.disableAndClear()',
    );
    final disconnect = disable.indexOf('graph.removeConnection');
    final removeNode = disable.indexOf('graph.removeNode');

    expect(gate, greaterThanOrEqualTo(0));
    expect(disconnect, greaterThan(gate));
    expect(removeNode, greaterThan(disconnect));
  });

  test('macOS monitoring publication stays separate from WAV capture', () {
    final bridge = File(
      'juce_audio_engine/ios/Classes/JuceBridge.mm',
    ).readAsStringSync();
    final render = _between(
      bridge,
      'OSStatus render(AudioUnitRenderActionFlags *flags,',
      'void recordRenderError(OSStatus status) noexcept',
    );
    final publish = render.indexOf('publishMacIndependentInputMonitoringV2');
    final captureGate = render.indexOf(
      'if (captureEnabled.load(std::memory_order_acquire))',
      publish,
    );
    final capture = render.indexOf('captureIndependentInput(', captureGate);

    expect(publish, greaterThanOrEqualTo(0));
    expect(captureGate, greaterThan(publish));
    expect(capture, greaterThan(captureGate));
  });

  test('Android monitoring activation requires atomic graph proof', () {
    final plugin = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/JuceAudioEnginePlugin.kt',
    ).readAsStringSync();
    final engine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.cpp',
    ).readAsStringSync();

    expect(plugin, contains('activateVerifiedMonitorGraphV2('));
    expect(plugin, contains('activateLiveInputMonitoringV2JNI('));
    expect(
      RegExp(
        r'if \(!activateVerifiedMonitorGraphV2\(',
      ).allMatches(plugin).length,
      1,
    );
    final preparation = _between(
      plugin,
      'private fun prepareSystemSelectedDuplexV2(',
      'private fun bluetoothCommunicationCandidatesV2(',
    );
    expect(preparation, contains('if (!activateVerifiedMonitorGraphV2('));
    expect(
      preparation.indexOf('if (!activateVerifiedMonitorGraphV2('),
      lessThan(
        preparation.indexOf(
          'audioRouteIntentV2 = AudioRouteIntentV2.MONITORING',
        ),
      ),
    );
    final verification = _between(
      plugin,
      'private fun verifyMonitoringIntentV2(',
      'private fun restoreRecordingPlaybackV2(',
    );
    expect(verification, isNot(contains('activateVerifiedMonitorGraphV2(')));
    expect(verification, contains('validatePreparedRecordingV2(operation)'));
    expect(plugin, contains('getLiveInputMonitoringFactsV2JNI()'));
    expect(
      plugin,
      contains('facts.intValue("connectionCount") == channelCount'),
    );
    expect(engine, contains('activateLiveInputMonitoringV2('));
    expect(engine, contains('connectionCount == channelCount'));
    expect(engine, contains('facts.set("active", active)'));
    expect(engine, contains('facts.set("targetRow"'));
    expect(engine, contains('facts.set("connectionCount"'));
    expect(engine, isNot(contains('setLiveInputMonitorTargetV2(')));

    final engineHeader = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.h',
    ).readAsStringSync();
    final callback = _between(
      engineHeader,
      'void audioDeviceIOCallbackWithContext(',
      'private:\n    juce::AudioProcessorPlayer &player;',
    );
    expect(callback, contains('engine.shouldRouteLiveInputToGraphV2()'));
    expect(callback, contains('chunkInputPointers[(size_t)ch]'));
    expect(
      callback,
      contains('playerInputChannels > 0 ? chunkInputPointers.data() : nullptr'),
    );
    expect(
      engineHeader,
      contains('std::array<const float *, 64> chunkInputPointers{}'),
    );
    expect(engine, contains('liveInputMonitoringActiveV2.store(true'));
    expect(
      engine,
      contains('liveInputMonitoringActiveV2.load(std::memory_order_acquire)'),
    );
  });

  test(
    'Android recording retains the monitor owner and restores before publication',
    () {
      final editor = File(editorPath).readAsStringSync();
      expect(
        editor,
        isNot(contains('_androidV2MonitoringSuspendedForRecording')),
      );
      expect(
        editor,
        isNot(contains('_suspendAndroidV2MonitoringForRecording')),
      );
      expect(
        editor,
        isNot(contains('_resumeAndroidV2MonitoringAfterPublishedRecording')),
      );
      final stop = _between(
        editor,
        'Future<void> _stopAudioRecordingJuce({bool keepPlaying = true}) async {',
        'Future<void> _addAudioTrackFromFile(',
      );
      expect(
        stop.indexOf('_restoreV2RouteAfterAudioRecording()'),
        lessThan(stop.indexOf('if (!captureResult.success)')),
      );
      final plugin = File(
        'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/JuceAudioEnginePlugin.kt',
      ).readAsStringSync();
      expect(plugin, contains('captureLifecycleV2.start('));
      expect(plugin, contains('captureLifecycleV2.stop(preserveMonitoring)'));
      expect(plugin, contains('AndroidNativeStreamEpochV2.matches('));
      final abort = _between(
        plugin,
        'private fun abortRecordingV2(',
        'private fun prepareV2TeardownV2()',
      );
      expect(
        abort.indexOf('operation.captureCancelRequested.set(true)'),
        lessThan(abort.indexOf('operation?.cancelled?.set(true)')),
      );
      expect(abort, contains('args.boolValue("cancelOnly")'));
    },
  );

  test('Android capture-only JNI operations do not perform route cleanup', () {
    final bridge = File(
      'juce_audio_engine/android/src/main/cpp/JuceBridge.cpp',
    ).readAsStringSync();
    final captureOnly = _between(
      bridge,
      'Java_com_mixroom_juce_1audio_1engine_JuceBridge_finalizeRecordingForMonitoringV2JNI',
      'Java_com_mixroom_juce_1audio_1engine_JuceBridge_getLiveInputMonitoringFactsV2JNI',
    );
    expect(captureOnly, contains('finalizeRecordingCapture()'));
    expect(captureOnly, contains('discardRecordingForMonitoringV2Android()'));
    expect(captureOnly, isNot(contains('completeRecordingStop')));
    final engine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.cpp',
    ).readAsStringSync();
    final discard = _between(
      engine,
      'void JuceEngine::discardRecordingForMonitoringV2Android()',
      'void JuceEngine::discardRecordingCaptureV2Android()',
    );
    expect(discard, contains('wavCapture.stop(true)'));
    expect(discard, isNot(contains('routeLiveInputToRow')));
    final facts = _between(
      engine,
      'juce::NamedValueSet JuceEngine::getLiveInputMonitoringFactsV2()',
      'bool JuceEngine::shouldRouteLiveInputToGraphV2()',
    );
    expect(facts, contains('graph.isConnected(connection)'));
    expect(facts, isNot(contains('syncLiveInputMonitorRoutingLocked')));
  });
  test('iOS captures retain ownership independently of recording intent', () {
    final plugin = File('juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m').readAsStringSync();
    final helper = File('juce_audio_engine/ios/Classes/MixroomIOSCaptureLifecycleV2.m').readAsStringSync();
    final start = _between(plugin, '- (void)startIOSCaptureV2:', '- (void)stopIOSCaptureV2:');
    expect(start, contains('MixroomIOSLifecycleQueue()'));
    expect(start, contains('canDeliverStartWithCurrent:current'));
    expect(start, contains('transition == self.iosLifecycleCompletionTokenV2'));
    final reuse = _between(plugin, '} else if (reusesMonitoringRoute) {', '} else if ([intent isEqualToString:@"preparingRecording"]');
    expect(reuse, isNot(contains('setLiveInputMonitorTargetV2ObjC')));
    expect(reuse, contains('monitorMatches'));
    final owner = _between(plugin, '- (MixroomIOSCaptureLifecycleV2 *)newIOSCaptureV2 {', '- (BOOL)iosCaptureRouteReadyV2');
    expect(owner, contains('preserveMonitoring:[self isIOSMonitorOwnedV2]'));
    expect(owner, isNot(contains('currentAudioRouteIntentV2')));
    expect(plugin, contains('if (cancelOnly && [self isIOSMonitorOwnedV2])'));
    expect(helper, contains('[self.native finalizePreservingMonitor:self.preserve]'));
    expect(helper, contains('self.streamGeneration != 0'));
    final engine = File('juce_audio_engine/ios/Classes/JuceEngine.cpp').readAsStringSync();
    final facts = _between(engine, 'juce::NamedValueSet JuceEngine::getLiveInputMonitoringFactsV2()', 'void JuceEngine::disableLiveInputMonitoringV2()');
    expect(facts, contains('graph.isConnected(connection)'));
    expect(facts, contains('wavCapture.stop(true)'));
    expect(facts, isNot(contains('syncLiveInputMonitorRoutingLocked')));
  });

}
