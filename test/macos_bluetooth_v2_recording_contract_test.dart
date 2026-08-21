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
  final pluginPath =
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m';
  final enginePath = 'juce_audio_engine/ios/Classes/JuceEngine.cpp';
  final editorPath = 'lib/screens/audio_editor.dart';

  test('macOS V2 is explicitly output-only in the editor', () {
    final editor = File(editorPath).readAsStringSync();
    final support = _between(
      editor,
      'bool get _supportsV2AudioRecording =>',
      'List<String> _inputDevices',
    );
    final recordStart = _between(
      editor,
      'Future<void> _startRecordingJuce()',
      'Future<void> _letRecordingVisualStatePaint()',
    );

    expect(support, contains('Platform.isAndroid || Platform.isIOS'));
    expect(support, isNot(contains('Platform.isMacOS')));
    expect(
      recordStart,
      contains(
        'Recording is temporarily unavailable in Bluetooth 2.0 on macOS.',
      ),
    );
    expect(editor, isNot(contains('_runMacOSSystemSelectedRouteProbeV2')));
    expect(editor, isNot(contains('macOSSystemSelected')));
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
      contains(
        'Unavailable in the macOS Bluetooth 2.0 output-only checkpoint',
      ),
    );
    expect(
      selector.indexOf('if (_isBluetoothV2Session && Platform.isMacOS)'),
      lessThan(selector.indexOf('JuceAudioEngine.selectInputDevice(name)')),
    );
  });

  test('macOS input intents fail before any native device mutation', () {
    final plugin = File(pluginPath).readAsStringSync();
    final intentMethod = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );

    final rejection = intentMethod.indexOf(
      'else if (![intent isEqualToString:@"playbackOnly"])',
    );
    final inventoryRead = intentMethod.indexOf(
      'MixroomCoreAudioDeviceInventory()',
    );
    expect(rejection, greaterThanOrEqualTo(0));
    expect(rejection, lessThan(inventoryRead));
    expect(intentMethod, contains('@"recording_route_unsupported"'));
    expect(intentMethod, isNot(contains('reconfigureRecordingRouteV2ObjC')));
    expect(intentMethod, isNot(contains('MixroomUniqueBuiltInInput')));
    expect(intentMethod, isNot(contains('startRecordingObjC')));
    expect(intentMethod, isNot(contains('AudioHardwareCreateAggregateDevice')));
    expect(intentMethod, isNot(contains('AudioHardwareDestroyAggregateDevice')));
  });

  test('macOS playback intent verifies a zero-input live output', () {
    final plugin = File(pluginPath).readAsStringSync();
    final intentMethod = _between(
      plugin,
      '- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {',
      '#else\n    const double startedAtMs = MixroomIOSMonotonicMilliseconds();',
    );

    expect(intentMethod, contains('reconfigurePlaybackRouteV2ObjC'));
    expect(intentMethod, contains('audioCallbackAttached'));
    expect(intentMethod, contains('activeInputChannels'));
    expect(intentMethod, contains('activeOutputChannels'));
    expect(intentMethod, contains('sampleRateHz'));
    expect(intentMethod, contains('bufferFrames'));
    expect(intentMethod, contains('actualOutput[@"uid"]'));
  });

  test('macOS abort cannot close a working output-only device', () {
    final plugin = File(pluginPath).readAsStringSync();
    final abort = _between(
      plugin,
      'else if ([call.method isEqualToString:@"abortRecordingV2"]) {',
      '#else\n        if ([[JuceBridge getAudioRouteImplementationObjC]',
    );

    expect(abort, contains('self.currentAudioRouteIntentV2 = @"playbackOnly"'));
    expect(abort, isNot(contains('discardRecordingCaptureObjC')));
    expect(abort, isNot(contains('quiescePlaybackRouteV2ObjC')));
    expect(abort, isNot(contains('closeAudioDevice')));
  });

  test('macOS startup stays off Flutter UI and avoids the callback-lock deadlock', () {
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
    expect(
      initialise,
      contains('No Mixroom audio\n    // callback is attached until after'),
    );
  });

  test('application Mac code contains no duplex aggregate lifecycle', () {
    final sources = <String>[
      pluginPath,
      'juce_audio_engine/ios/Classes/JuceBridge.h',
      'juce_audio_engine/ios/Classes/JuceBridge.mm',
      enginePath,
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(sources, isNot(contains('AudioHardwareCreateAggregateDevice')));
    expect(sources, isNot(contains('AudioHardwareDestroyAggregateDevice')));
    expect(sources, isNot(contains('beginMacSystemSelectedDuplex')));
    expect(sources, isNot(contains('waitForMacRoutePhaseCallback')));
    expect(sources, isNot(contains('macIntentAggregateDevice')));
  });

  test('macOS editor startup follows the latest process teardown', () {
    final source = File(editorPath).readAsStringSync();
    final startup = source.substring(
      source.indexOf('WidgetsBinding.instance.addPostFrameCallback((_) async {'),
      source.indexOf('_juceEngineEventSubscription ??='),
    );
    final sessionLoaded = startup.indexOf('.loadSession()');
    final teardownWait = startup.indexOf('await priorShutdown');
    final initialization = startup.indexOf(
      'JuceAudioEngine.initialiseForImplementation',
    );

    expect(sessionLoaded, lessThan(teardownWait));
    expect(teardownWait, lessThan(initialization));
    expect(startup, contains('final latestShutdown ='));
    expect(startup, contains('identical(latestShutdown, priorShutdown)'));
  });
}
