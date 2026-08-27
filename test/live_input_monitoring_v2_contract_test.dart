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

  test('V2 monitoring is available only through verified mobile paths', () {
    final editor = File(editorPath).readAsStringSync();
    final routingSheet = _between(
      editor,
      'Future<void> _showAudioRoutingSheet() async {',
      'Widget _buildAudioRoutingLauncher()',
    );

    expect(routingSheet, contains('_mobileV2LiveMonitoringAvailable'));
    expect(
      routingSheet,
      contains('final monitoringEnabled = _isBluetoothV2Session'),
    );
    expect(routingSheet, contains('onChanged: monitoringAvailable'));
    expect(
      routingSheet,
      contains('Monitoring is unavailable for the current audio route.'),
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
      expect(
        monitoringAction,
        contains('_setMobileV2LiveMonitoring(enabled)'),
      );
    },
  );

  test('mobile monitoring is coordinator owned and Bluetooth fail closed', () {
    final editor = File(editorPath).readAsStringSync();
    final action = _between(
      editor,
      'Future<void> _setMobileV2LiveMonitoring(bool enabled) async {',
      'Future<void> _showAudioRoutingSheet() async {',
    );
    expect(action, contains('AudioRouteIntentV2.monitoring'));
    expect(action, contains('systemSelectedMonitoring'));
    expect(action, contains('AudioRouteKindV2.builtIn'));
    expect(action, contains('AudioRouteKindV2.wired'));
    expect(action, contains('AudioRouteKindV2.external'));
    expect(action, isNot(contains('AudioRouteKindV2.bluetoothMedia')));
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
    expect(
      plugin,
      contains('prepareSystemSelectedDuplexSessionV2ObjC'),
    );
    expect(
      plugin,
      contains('openPreparedSystemSelectedDuplexRouteV2ObjC'),
    );
    expect(engine, contains('bool JuceEngine::setLiveInputMonitorTargetV2'));
    expect(engine, contains('if (!v2Recording || !liveInputMonitoringEnabled)'));
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

  test('macOS independent monitoring bridge remains production inactive', () {
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
    expect(header, contains('class MacIndependentMonitorBuffer'));
    expect(header, contains('class MacIndependentMonitorSourceProcessor'));
    expect(
      bridge,
      contains('prepareMacIndependentInputMonitoringV2ObjC'),
    );
    expect(
      plugin,
      isNot(contains('prepareMacIndependentInputMonitoringV2ObjC')),
    );
    expect(
      File(editorPath).readAsStringSync(),
      isNot(contains('prepareMacIndependentInputMonitoringV2')),
    );
  });

  test('macOS monitoring callbacks use a bounded fail-closed transport', () {
    final header = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    final buffer = _between(
      header,
      'class MacIndependentMonitorBuffer',
      'class MacIndependentMonitorSourceProcessor',
    );
    final push = _between(
      buffer,
      'bool push(',
      'void read(',
    );
    final read = _between(
      buffer,
      'void read(',
      'bool isActive()',
    );

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
    final publish = render.indexOf(
      'publishMacIndependentInputMonitoringV2',
    );
    final captureGate = render.indexOf(
      'if (captureEnabled.load(std::memory_order_acquire))',
      publish,
    );
    final capture = render.indexOf('captureIndependentInput(', captureGate);

    expect(publish, greaterThanOrEqualTo(0));
    expect(captureGate, greaterThan(publish));
    expect(capture, greaterThan(captureGate));
  });

  test('Android recording reuses and returns to the monitoring route', () {
    final editor = File(editorPath).readAsStringSync();
    final plugin = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/JuceAudioEnginePlugin.kt',
    ).readAsStringSync();
    final engine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.cpp',
    ).readAsStringSync();

    expect(editor, contains('_restoreV2RouteAfterAudioRecording()'));
    expect(editor, contains('AudioRouteIntentV2.monitoring'));
    expect(plugin, contains('stopRecordingForMonitoringV2JNI()'));
    expect(plugin, contains('verifyMonitoringIntentV2(generation)'));
    expect(
      engine,
      contains('if (!v2Recording || !liveInputMonitoringEnabled)'),
    );
  });
}
