import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/ios_recording_input_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mono = IOSRecordingInputV2(
    channelStart: 0,
    channelCount: 1,
    inputAvailable: true,
    resolvedDeviceName: 'iPhone Microphone',
  );

  AudioRouteSnapshotV2 snapshot({
    int generation = 4,
    String intent = 'monitoring',
    int activeInputs = 1,
    int endpointChannels = 1,
    String inputName = 'Bluetooth Headset',
  }) => AudioRouteSnapshotV2.fromMap({
    'intent': intent,
    'generation': generation,
    'captureConsistency': 'stable',
    'inputs': [
      {
        'uid': 'input-1',
        'name': inputName,
        'direction': 'input',
        'channelCount': endpointChannels,
      },
    ],
    'outputs': [
      {'uid': 'output-1', 'name': 'Output', 'direction': 'output'},
    ],
    'juce': {
      'deviceOpen': true,
      'audioCallbackAttached': true,
      'activeInputChannels': activeInputs,
    },
  });

  test(
    'iOS policy accepts only Input 1 mono and keeps unknown availability',
    () {
      final unknown = IOSRecordingInputV2.fromMap({
        'channelStart': 0,
        'channelCount': 1,
        'inputAvailable': null,
        'resolvedDeviceName': '  Built-in Microphone  ',
        'deviceNameVerified': false,
      });

      expect(unknown, isNotNull);
      expect(unknown!.inputAvailable, isNull);
      expect(unknown.resolvedDeviceName, 'Built-in Microphone');
      expect(unknown.accepts(0, 1), isTrue);
      expect(unknown.accepts(0, 2), isFalse);
      expect(unknown.accepts(1, 1), isFalse);
      expect(IOSRecordingInputV2.fromMap({}), isNull);
      expect(
        IOSRecordingInputV2.fromMap({'channelStart': 0, 'channelCount': 2}),
        isNull,
      );
    },
  );

  test('active verified route upgrades the passive System Default name', () {
    expect(resolvedIOSInputNameV2(mono, snapshot(), 4), 'Bluetooth Headset');
    expect(
      resolvedIOSInputNameV2(mono, snapshot(generation: 3), 4),
      'iPhone Microphone',
    );
    expect(
      resolvedIOSInputNameV2(mono, snapshot(activeInputs: 2), 4),
      'iPhone Microphone',
    );
    expect(
      resolvedIOSInputNameV2(mono, snapshot(endpointChannels: 2), 4),
      'iPhone Microphone',
    );
  });

  test('a stale active-route name is cleared instead of becoming passive', () {
    const active = IOSRecordingInputV2(
      channelStart: 0,
      channelCount: 1,
      inputAvailable: true,
      resolvedDeviceName: 'Former Headset Microphone',
      deviceNameVerified: true,
    );

    expect(resolvedIOSInputNameV2(active, snapshot(), 4), 'Bluetooth Headset');
    expect(resolvedIOSInputNameV2(active, snapshot(generation: 3), 4), isEmpty);
    expect(resolvedIOSInputNameV2(active, null, 4), isEmpty);
  });

  test('read-only status method uses its dedicated native API', () async {
    final calls = <String>[];
    const channel = MethodChannel('juce_audio_engine');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return {
            'channelStart': 0,
            'channelCount': 1,
            'inputAvailable': true,
            'resolvedDeviceName': 'iPhone Microphone',
            'deviceNameVerified': false,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final configuration =
        await JuceAudioEngine.getIOSRecordingInputConfigurationV2();
    expect(configuration!.accepts(0, 1), isTrue);
    expect(configuration.resolvedDeviceName, 'iPhone Microphone');
    expect(calls, ['getIOSRecordingInputConfigurationV2']);
  });

  test('partial refresh failures preserve the successful half', () async {
    final withoutSnapshot = await readIOSRecordingInputRefreshV2(
      readConfiguration: () async => mono,
      readSnapshot: () async => throw StateError('route unavailable'),
    );
    expect(withoutSnapshot.configuration, same(mono));
    expect(withoutSnapshot.snapshot, isNull);

    final route = snapshot();
    final withoutConfiguration = await readIOSRecordingInputRefreshV2(
      readConfiguration: () async => throw StateError('policy unavailable'),
      readSnapshot: () async => route,
    );
    expect(withoutConfiguration.configuration, isNull);
    expect(withoutConfiguration.snapshot, same(route));
  });
}
