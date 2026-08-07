import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_snapshot_provider_v2.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';

Map<String, dynamic> nativeSnapshot({
  String consistency = 'stable',
  Map<String, String> unavailableReasons = const <String, String>{},
}) {
  return <String, dynamic>{
    'schemaVersion': 1,
    'capturedAtUtc': '2026-08-08T12:00:00.000Z',
    'captureDurationMs': 2,
    'implementation': 'legacy',
    'generation': null,
    'transitionId': null,
    'coordinatorManaged': false,
    'captureConsistency': consistency,
    'inputs': <Map<String, dynamic>>[
      <String, dynamic>{
        'direction': 'input',
        'nativePortType': '0x626c746e',
        'normalizedKind': 'builtIn',
        'uid': 'input-uid',
        'name': 'MacBook Pro Microphone',
        'channelCount': 1,
      },
    ],
    'outputs': <Map<String, dynamic>>[
      <String, dynamic>{
        'direction': 'output',
        'nativePortType': '0x626c746e',
        'normalizedKind': 'builtIn',
        'uid': 'output-uid',
        'name': 'MacBook Pro Speakers',
        'channelCount': 2,
      },
    ],
    'session': <String, dynamic>{
      'sampleRateHz': 48000.0,
      'ioBufferDurationSeconds': 0.010666,
      'inputChannelCount': 1,
      'outputChannelCount': 2,
    },
    'juce': <String, dynamic>{
      'deviceOpen': true,
      'sampleRateHz': 44100.0,
      'bufferFrames': 512,
      'activeInputChannels': 0,
      'activeOutputChannels': 2,
      'xRunCount': null,
    },
    'unavailableReasons': unavailableReasons,
    'futureNativeField': <String, dynamic>{'ignored': true},
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('audio_route_snapshot_provider_v2_test');
  var calls = 0;

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('macOS provider parses stable native facts without merging provenance',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      expect(call.method, 'getAudioRouteSnapshotV2');
      return nativeSnapshot();
    });
    final provider = MethodChannelAudioRouteSnapshotProviderV2(
      channel: channel,
      platformOverride: TargetPlatform.macOS,
    );

    final snapshot = await provider.readSnapshot();

    expect(calls, 1);
    expect(snapshot.captureConsistency, AudioRouteCaptureConsistencyV2.stable);
    expect(snapshot.inputs, hasLength(1));
    expect(snapshot.outputs, hasLength(1));
    expect(snapshot.session.sampleRateHz, 48000.0);
    expect(snapshot.juce.sampleRateHz, 44100.0);
    expect(snapshot.juce.inputOpen, isFalse);
  });

  test('route changes and ambiguity remain explicit', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      return nativeSnapshot(
        consistency: 'routeChangedDuringCapture',
        unavailableReasons: const <String, String>{
          'route.outputEndpoint': 'selectedJuceDeviceNameIsAmbiguous',
        },
      );
    });
    final provider = MethodChannelAudioRouteSnapshotProviderV2(
      channel: channel,
      platformOverride: TargetPlatform.macOS,
    );

    final snapshot = await provider.readSnapshot();

    expect(
      snapshot.captureConsistency,
      AudioRouteCaptureConsistencyV2.routeChangedDuringCapture,
    );
    expect(
      snapshot.unavailableReasons['route.outputEndpoint'],
      'selectedJuceDeviceNameIsAmbiguous',
    );
  });

  test('unsupported platforms return unavailable without a method call',
      () async {
    calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      calls++;
      return nativeSnapshot();
    });
    final provider = MethodChannelAudioRouteSnapshotProviderV2(
      channel: channel,
      platformOverride: TargetPlatform.android,
    );

    final snapshot = await provider.readSnapshot();

    expect(calls, 0);
    expect(
      snapshot.captureConsistency,
      AudioRouteCaptureConsistencyV2.unavailable,
    );
    expect(snapshot.unavailableReasons['platform'], 'macOSOnlyCheckpoint');
  });

  test('missing native method returns a controlled unavailable snapshot',
      () async {
    final provider = MethodChannelAudioRouteSnapshotProviderV2(
      channel: channel,
      platformOverride: TargetPlatform.macOS,
    );

    final snapshot = await provider.readSnapshot();

    expect(
      snapshot.captureConsistency,
      AudioRouteCaptureConsistencyV2.unavailable,
    );
    expect(
      snapshot.unavailableReasons['nativeSnapshot'],
      'nativeMethodUnavailable',
    );
  });

  test('malformed native response returns controlled unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'not-a-snapshot');
    final provider = MethodChannelAudioRouteSnapshotProviderV2(
      channel: channel,
      platformOverride: TargetPlatform.macOS,
    );

    final snapshot = await provider.readSnapshot();

    expect(
      snapshot.captureConsistency,
      AudioRouteCaptureConsistencyV2.unavailable,
    );
    expect(
      snapshot.unavailableReasons['nativeSnapshot'],
      'invalidNativeResponse',
    );
  });
}
