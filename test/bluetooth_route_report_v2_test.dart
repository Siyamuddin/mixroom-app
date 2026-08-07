import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:mixroom/helpers/bluetooth_route_report_v2.dart';

AudioRouteSnapshotV2 snapshot() {
  return AudioRouteSnapshotV2(
    capturedAtUtc: DateTime.utc(2026, 8, 8, 10),
    captureDurationMs: 4,
    implementation: BluetoothImplementationV2.legacy,
    generation: null,
    transitionId: null,
    coordinatorManaged: false,
    captureConsistency: AudioRouteCaptureConsistencyV2.stable,
    inputs: const <AudioRouteEndpointV2>[
      AudioRouteEndpointV2(
        direction: AudioRouteDirectionV2.input,
        nativePortType: 'BuiltInMic',
        normalizedKind: AudioRouteKindV2.builtIn,
        uid: 'private-input-uid',
        name: "Alex's iPhone Microphone",
        channelCount: 1,
      ),
    ],
    outputs: const <AudioRouteEndpointV2>[
      AudioRouteEndpointV2(
        direction: AudioRouteDirectionV2.output,
        nativePortType: 'BluetoothA2DPOutput',
        normalizedKind: AudioRouteKindV2.bluetoothMedia,
        uid: 'private-output-uid',
        name: "Alex's Headphones",
        channelCount: 2,
      ),
    ],
    session: const AudioSessionFactsV2(
      category: 'AVAudioSessionCategoryPlayback',
      mode: 'AVAudioSessionModeDefault',
      sampleRateHz: 48000,
      ioBufferDurationSeconds: 0.02,
      inputChannelCount: 1,
      outputChannelCount: 2,
    ),
    juce: const JuceRouteFactsV2(
      deviceOpen: true,
      sampleRateHz: 48000,
      bufferFrames: 1024,
      activeInputChannels: 0,
      activeOutputChannels: 2,
      inputDeviceName: "Alex's iPhone Microphone",
      outputDeviceName: "Alex's Headphones",
      xRunCount: null,
    ),
    unavailableReasons: const <String, String>{
      'juce.xRunCount': 'unsupportedByIosBackend',
    },
  );
}

void main() {
  test('copied report removes raw endpoint and JUCE device identifiers', () {
    final serializer = BluetoothRouteReportSerializerV2(
      sessionSalt: List<int>.filled(32, 7),
    );
    final encoded = serializer.encode(snapshot());
    final report = jsonDecode(encoded) as Map<String, dynamic>;

    expect(encoded, isNot(contains('Alex')));
    expect(encoded, isNot(contains('private-input-uid')));
    expect(encoded, isNot(contains('private-output-uid')));
    expect(encoded, isNot(contains('inputDeviceName')));
    expect(encoded, isNot(contains('outputDeviceName')));
    expect((report['inputs'] as List).single, isNot(contains('uid')));
    expect((report['outputs'] as List).single, isNot(contains('name')));
  });

  test('endpoint tokens are stable only for the same session salt', () {
    final firstSession = BluetoothRouteReportSerializerV2(
      sessionSalt: List<int>.filled(32, 1),
    );
    final secondSession = BluetoothRouteReportSerializerV2(
      sessionSalt: List<int>.filled(32, 2),
    );

    String outputToken(BluetoothRouteReportSerializerV2 serializer) {
      final outputs = serializer.toMap(snapshot())['outputs'] as List;
      return (outputs.single as Map)['endpointToken'] as String;
    }

    expect(outputToken(firstSession), outputToken(firstSession));
    expect(outputToken(firstSession), isNot(outputToken(secondSession)));
    expect(outputToken(firstSession), startsWith('output-'));
  });

  test('report retains explicit unavailable reasons and null values', () {
    final report = BluetoothRouteReportSerializerV2(
      sessionSalt: List<int>.filled(32, 3),
    ).toMap(snapshot());
    final juce = report['juce'] as Map<String, dynamic>;

    expect(juce['xRunCount'], isNull);
    expect(
      (report['unavailableReasons'] as Map)['juce.xRunCount'],
      'unsupportedByIosBackend',
    );
  });
}
