import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/android_recording_input_v2.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mono = AndroidRecordingInputV2(channelStart: 0, channelCount: 1);
  AudioRouteSnapshotV2 snapshot({
    String intent = 'monitoring',
    int generation = 3,
    bool deviceOpen = true,
    bool callback = true,
    int channels = 1,
    String consistency = 'stable',
    List<Map<String, dynamic>>? inputs,
  }) => AudioRouteSnapshotV2.fromMap({
    'intent': intent,
    'generation': generation,
    'captureConsistency': consistency,
    'inputs':
        inputs ??
        [
          {
            'name': 'Verified microphone',
            'uid': '12',
            'direction': 'input',
            'channelCount': 1,
          },
        ],
    'outputs': [
      {'name': 'Bluetooth headphones', 'direction': 'output'},
    ],
    'juce': {
      'deviceOpen': deviceOpen,
      'audioCallbackAttached': callback,
      'activeInputChannels': channels,
    },
  });
  test('only a current active capture supplies input identity', () {
    for (final intent in ['preparingRecording', 'recording', 'monitoring']) {
      expect(
        verifiedAndroidInputNameV2(mono, snapshot(intent: intent), 3),
        'Verified microphone',
      );
    }
    for (final state in [
      snapshot(intent: 'playbackOnly'),
      snapshot(generation: 2),
      snapshot(deviceOpen: false),
      snapshot(callback: false),
      snapshot(channels: 2),
      snapshot(consistency: 'unavailable'),
      snapshot(inputs: []),
    ]) {
      expect(verifiedAndroidInputNameV2(mono, state, 3), isEmpty);
    }
    expect(verifiedAndroidInputNameV2(null, snapshot(), 3), isEmpty);
    expect(verifiedAndroidInputNameV2(mono, snapshot(), null), isEmpty);
  });
  test(
    'stream end and device removal clear the name; a newly verified route restores it',
    () {
      expect(verifiedAndroidInputNameV2(mono, snapshot(), 3), isNotEmpty);
      expect(
        verifiedAndroidInputNameV2(mono, snapshot(intent: 'playbackOnly'), 3),
        isEmpty,
      );
      expect(
        verifiedAndroidInputNameV2(mono, snapshot(inputs: []), 3),
        isEmpty,
      );
      expect(
        verifiedAndroidInputNameV2(mono, snapshot(generation: 4), 4),
        isNotEmpty,
      );
    },
  );
  test(
    'capability discovery only invokes the read-only configuration method',
    () async {
      final calls = <String>[];
      const channel = MethodChannel('juce_audio_engine');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return {
              'channelStart': 0,
              'channelCount': 1,
              'inputAvailable': null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final config =
          await JuceAudioEngine.getAndroidRecordingInputConfigurationV2();
      expect(config!.accepts(0, 1), isTrue);
      expect(config.inputAvailable, isNull);
      expect(calls, ['getAndroidRecordingInputConfigurationV2']);
    },
  );

  test(
    'snapshot failure preserves a successfully read recording policy',
    () async {
      final refresh = await readAndroidRecordingInputRefreshV2(
        readConfiguration: () async => mono,
        readSnapshot: () async => throw StateError('route unavailable'),
      );

      expect(refresh.configuration, same(mono));
      expect(refresh.snapshot, isNull);
      expect(refresh.configuration!.accepts(0, 1), isTrue);
    },
  );

  test(
    'configuration failure does not discard available route metadata',
    () async {
      final route = snapshot();
      final refresh = await readAndroidRecordingInputRefreshV2(
        readConfiguration: () async => throw StateError('policy unavailable'),
        readSnapshot: () async => route,
      );

      expect(refresh.configuration, isNull);
      expect(refresh.snapshot, same(route));
    },
  );
}
