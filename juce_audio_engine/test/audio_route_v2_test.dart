import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';

AudioRouteSnapshotV2 snapshot({
  List<AudioRouteEndpointV2> inputs = const <AudioRouteEndpointV2>[],
  List<AudioRouteEndpointV2> outputs = const <AudioRouteEndpointV2>[],
  AudioSessionFactsV2 session = const AudioSessionFactsV2(),
  JuceRouteFactsV2 juce = const JuceRouteFactsV2(),
}) {
  return AudioRouteSnapshotV2(
    capturedAtUtc: DateTime.utc(2026, 8, 8),
    captureDurationMs: 3,
    implementation: BluetoothImplementationV2.legacy,
    generation: null,
    transitionId: null,
    coordinatorManaged: false,
    captureConsistency: AudioRouteCaptureConsistencyV2.stable,
    inputs: inputs,
    outputs: outputs,
    session: session,
    juce: juce,
    unavailableReasons: const <String, String>{},
  );
}

void main() {
  test('parses every endpoint and preserves unknown native port types', () {
    final parsed = AudioRouteSnapshotV2.fromMap(<String, dynamic>{
      'schemaVersion': 1,
      'capturedAtUtc': '2026-08-08T10:00:00Z',
      'captureDurationMs': 7,
      'implementation': 'legacy',
      'generation': null,
      'transitionId': null,
      'coordinatorManaged': false,
      'captureConsistency': 'stable',
      'inputs': <Map<String, dynamic>>[
        <String, dynamic>{
          'direction': 'input',
          'nativePortType': 'BluetoothHFP',
          'normalizedKind': 'bluetoothDuplex',
          'uid': 'input-a',
          'name': 'Headset microphone',
          'channelCount': 1,
        },
        <String, dynamic>{
          'direction': 'input',
          'nativePortType': 'FutureInputPort',
          'normalizedKind': 'unknown',
          'uid': 'input-b',
          'name': 'Future input',
          'channelCount': 0,
        },
      ],
      'outputs': <Map<String, dynamic>>[
        <String, dynamic>{
          'direction': 'output',
          'nativePortType': 'BluetoothA2DPOutput',
          'normalizedKind': 'bluetoothMedia',
          'uid': 'output-a',
          'name': 'Headphones',
          'channelCount': 2,
        },
        <String, dynamic>{
          'direction': 'output',
          'nativePortType': 'FutureOutputPort',
          'normalizedKind': 'unknown',
          'uid': 'output-b',
          'name': 'Future output',
          'channelCount': null,
        },
      ],
      'session': <String, dynamic>{},
      'juce': <String, dynamic>{},
      'unavailableReasons': <String, String>{},
      'futureField': 'ignored',
    });

    expect(parsed.inputs, hasLength(2));
    expect(parsed.outputs, hasLength(2));
    expect(parsed.outputs.last.nativePortType, 'FutureOutputPort');
    expect(parsed.outputs.last.normalizedKind, AudioRouteKindV2.unknown);
    expect(parsed.outputs.last.channelCount, isNull);
    expect(parsed.inputs.last.channelCount, 0);
    expect(parsed.hasBluetoothOutput, isTrue);
  });

  test('keeps missing diagnostic values distinct from legitimate zero', () {
    final parsed = AudioRouteSnapshotV2.fromMap(<String, dynamic>{
      'capturedAtUtc': '2026-08-08T10:00:00Z',
      'captureDurationMs': 0,
      'captureConsistency': 'unavailable',
      'session': <String, dynamic>{
        'inputChannelCount': 0,
        'outputChannelCount': null,
      },
      'juce': <String, dynamic>{
        'activeInputChannels': 0,
        'activeOutputChannels': null,
        'xRunCount': null,
      },
      'unavailableReasons': <String, String>{
        'juce.xRunCount': 'unsupportedByIosBackend',
      },
    });

    expect(parsed.session.inputChannelCount, 0);
    expect(parsed.session.outputChannelCount, isNull);
    expect(parsed.juce.activeInputChannels, 0);
    expect(parsed.juce.activeOutputChannels, isNull);
    expect(parsed.juce.inputOpen, isFalse);
    expect(parsed.juce.xRunCount, isNull);
    expect(
      parsed.unavailableReasons['juce.xRunCount'],
      'unsupportedByIosBackend',
    );
  });

  test('input-open availability remains unknown without a JUCE channel count',
      () {
    const facts = JuceRouteFactsV2(activeInputChannels: null);

    expect(facts.inputOpen, isNull);
    expect(facts.toMap()['inputOpen'], isNull);
  });

  test('preserves AVAudioSession and JUCE disagreement', () {
    final value = snapshot(
      session: const AudioSessionFactsV2(
        sampleRateHz: 48000,
        inputChannelCount: 1,
        outputChannelCount: 2,
      ),
      juce: const JuceRouteFactsV2(
        sampleRateHz: 44100,
        bufferFrames: 512,
        activeInputChannels: 0,
        activeOutputChannels: 2,
      ),
    );
    final reparsed = AudioRouteSnapshotV2.fromMap(value.toRawMap());

    expect(reparsed.session.sampleRateHz, 48000);
    expect(reparsed.juce.sampleRateHz, 44100);
    expect(reparsed.session.inputChannelCount, 1);
    expect(reparsed.juce.activeInputChannels, 0);
    expect(reparsed.juce.inputOpen, isFalse);
  });

  test('playback policy is output-only and Bluetooth stability-oriented', () {
    final configuration = const AudioRoutePolicyV2().resolve(
      snapshot: snapshot(
        outputs: const <AudioRouteEndpointV2>[
          AudioRouteEndpointV2(
            direction: AudioRouteDirectionV2.output,
            nativePortType: 'BluetoothA2DPOutput',
            normalizedKind: AudioRouteKindV2.bluetooth,
            uid: 'output-a',
            name: 'Headphones',
            channelCount: 2,
          ),
        ],
      ),
      intent: AudioRouteIntentV2.playbackOnly,
    );

    expect(configuration.supported, isTrue);
    expect(configuration.desiredInputChannels, 0);
    expect(configuration.requireNonBluetoothInput, isFalse);
    expect(configuration.monitoringAllowed, isFalse);
    expect(
      configuration.hardwareRatePolicy,
      AudioHardwareRatePolicyV2.prefer48000,
    );
    expect(
      configuration.bufferPolicy,
      AudioBufferPolicyV2.conservativeBluetooth,
    );
  });

  test('Bluetooth monitoring is rejected and input must be non-Bluetooth', () {
    final configuration = const AudioRoutePolicyV2().resolve(
      snapshot: snapshot(
        outputs: const <AudioRouteEndpointV2>[
          AudioRouteEndpointV2(
            direction: AudioRouteDirectionV2.output,
            nativePortType: 'BluetoothA2DPOutput',
            normalizedKind: AudioRouteKindV2.bluetoothMedia,
            uid: 'output-a',
            name: 'Headphones',
            channelCount: 2,
          ),
        ],
      ),
      intent: AudioRouteIntentV2.monitoring,
    );

    expect(configuration.supported, isFalse);
    expect(configuration.rejectionCode, 'bluetooth_monitoring_unsupported');
    expect(configuration.desiredInputChannels, 1);
    expect(configuration.requireNonBluetoothInput, isTrue);
    expect(configuration.monitoringAllowed, isFalse);
  });

  test('playback startup result preserves verified snapshot and future fields',
      () {
    final result = AudioPlaybackStartupResultV2.fromMap(<String, dynamic>{
      'success': true,
      'diagnosticCode': 'ok',
      'futureResultField': true,
      'snapshot': snapshot().toRawMap()
        ..['implementation'] = 'v2'
        ..['futureSnapshotField'] = 'ignored',
    });

    expect(result.success, isTrue);
    expect(result.diagnosticCode, 'ok');
    expect(result.snapshot.implementation, BluetoothImplementationV2.v2);
  });

  test('missing playback startup snapshot fails closed', () {
    final result = AudioPlaybackStartupResultV2.fromMap(<String, dynamic>{
      'success': false,
      'diagnosticCode': 'actual_state_unavailable',
    });

    expect(result.success, isFalse);
    expect(
      result.snapshot.captureConsistency,
      AudioRouteCaptureConsistencyV2.unavailable,
    );
  });

  test('route-change event preserves generation and tolerates future fields',
      () {
    final event = AudioRouteChangeEventV2.fromMap(<String, dynamic>{
      'generation': 7,
      'cause': 'defaultOutputChanged',
      'fingerprint': 'output-7',
      'transportWasPlaying': true,
      'snapshot': <String, dynamic>{
        'implementation': 'v2',
        'generation': 7,
        'captureConsistency': 'stable',
      },
      'futureField': <String, Object>{'ignored': true},
    });

    expect(event.generation, 7);
    expect(event.fingerprint, 'output-7');
    expect(event.transportWasPlaying, isTrue);
    expect(event.snapshot.implementation, BluetoothImplementationV2.v2);
  });

  test('transition result parses fallback and fails closed without snapshot',
      () {
    final fallback = AudioRouteTransitionResultV2.fromMap(<String, dynamic>{
      'status': 'fallback',
      'generation': 9,
      'transitionId': 3,
      'diagnosticCode': 'fallback_succeeded',
      'elapsedMs': 24,
      'snapshot': <String, dynamic>{
        'implementation': 'v2',
        'captureConsistency': 'stable',
      },
    });
    final malformed = AudioRouteTransitionResultV2.fromMap(<String, dynamic>{});

    expect(fallback.succeeded, isTrue);
    expect(fallback.status, AudioRouteTransitionStatusV2.fallback);
    expect(malformed.succeeded, isFalse);
    expect(
      malformed.snapshot.captureConsistency,
      AudioRouteCaptureConsistencyV2.unavailable,
    );
  });
}
