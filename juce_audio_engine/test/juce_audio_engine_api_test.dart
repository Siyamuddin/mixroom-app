import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

Map<String, dynamic> _v2Snapshot({
  String nativePortType = 'Speaker',
  String normalizedKind = 'builtIn',
  String uid = 'output-uid',
  int sessionInputChannels = 0,
}) =>
    <String, dynamic>{
      'schemaVersion': 1,
      'capturedAtUtc': '2026-08-08T12:00:00.000Z',
      'captureDurationMs': 2,
      'implementation': 'v2',
      'coordinatorManaged': false,
      'captureConsistency': 'stable',
      'inputs': <Object>[],
      'outputs': <Map<String, dynamic>>[
        <String, dynamic>{
          'direction': 'output',
          'nativePortType': nativePortType,
          'normalizedKind': normalizedKind,
          'uid': uid,
          'name': 'Built-in Output',
          'channelCount': 2,
        },
      ],
      'session': <String, dynamic>{
        'category': 'AVAudioSessionCategoryPlayback',
        'mode': 'AVAudioSessionModeDefault',
        'sampleRateHz': 48000.0,
        'ioBufferDurationSeconds': 0.01,
        'inputChannelCount': sessionInputChannels,
        'outputChannelCount': 2,
      },
      'juce': <String, dynamic>{
        'deviceOpen': true,
        'audioCallbackAttached': true,
        'sampleRateHz': 48000.0,
        'bufferFrames': 512,
        'activeInputChannels': 0,
        'activeOutputChannels': 2,
      },
      'unavailableReasons': <String, String>{},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('juce_audio_engine');
  final List<MethodCall> calls = <MethodCall>[];

  void useIOSRouteSnapshots({
    required Map<String, dynamic> startup,
    required Map<String, dynamic> current,
    bool startupSuccess = true,
    String diagnosticCode = 'ok',
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      calls.add(methodCall);
      if (methodCall.method == 'initialisePlaybackV2') {
        return <String, dynamic>{
          'success': startupSuccess,
          'diagnosticCode': diagnosticCode,
          'snapshot': startup,
        };
      }
      if (methodCall.method == 'getAudioRouteSnapshotV2') return current;
      return null;
    });
  }

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      calls.add(methodCall);

      switch (methodCall.method) {
        case 'getRows':
          return <Map<String, dynamic>>[
            <String, dynamic>{'rowId': 7, 'name': 'Drums', 'iconId': 1},
          ];
        case 'getEngineCapabilities':
          return <String, dynamic>{
            'externalPluginHosting': true,
            'supportedPluginFormats': <String>['AU', 'VST3'],
            'nativePluginEditor': false,
          };
        case 'scanPlugins':
          return <Map<String, dynamic>>[
            <String, dynamic>{
              'path': '/tmp/SomePlugin.vst3',
              'format': 'VST3',
            },
            <String, dynamic>{
              'id': 'au:com.test:unit',
              'name': 'Test Unit',
              'manufacturer': 'Mixroom',
              'category': 'Effect',
            },
          ];
        case 'getTransportSeconds':
          return 12.5;
        case 'getOutputDevices':
          return <String>['MacBook Pro Speakers', 'WH-1000XM4'];
        case 'selectOutputDevice':
          return true;
        case 'stopRecording':
        case 'stopRecordingWithoutPlaybackRestore':
          return <String, dynamic>{
            'success': true,
            'diagnosticCode': 'ok',
            'attemptedSamples': 24000,
            'acceptedSamples': 24000,
            'droppedSamples': 0,
            'actualSampleRate': 48000.0,
            'channelCount': 1,
          };
        case 'initialisePlaybackV2':
          return <String, dynamic>{
            'success': true,
            'diagnosticCode': 'ok',
            'snapshot': _v2Snapshot(),
          };
        case 'getAudioRouteSnapshotV2':
          return _v2Snapshot();
        case 'validatePlaybackV2':
          return 'ok';
        case 'startAudioRouteMonitoringV2':
          return <String, dynamic>{
            'implementation': 'v2',
            'generation': 0,
            'transitionId': 0,
            'coordinatorManaged': true,
            'captureConsistency': 'stable',
          };
        case 'applyAudioRouteConfigurationV2':
          final arguments =
              Map<String, dynamic>.from(methodCall.arguments as Map);
          final generation = (arguments['generation'] as num).toInt();
          return <String, dynamic>{
            'status': 'success',
            'generation': generation,
            'transitionId': 1,
            'diagnosticCode': 'ok',
            'elapsedMs': 3,
            'transportWasPlaying': false,
            'snapshot': <String, dynamic>{
              'implementation': 'v2',
              'generation': generation,
              'transitionId': 1,
              'coordinatorManaged': true,
              'captureConsistency': 'stable',
            },
          };
        case 'setAudioRouteIntentV2':
          final arguments =
              Map<String, dynamic>.from(methodCall.arguments as Map);
          final generation = (arguments['generation'] as num).toInt();
          final intent = arguments['intent']?.toString() ?? 'playbackOnly';
          final snapshot = _v2Snapshot();
          snapshot['generation'] = generation;
          snapshot['transitionId'] = 2;
          snapshot['coordinatorManaged'] = true;
          snapshot['intent'] = intent;
          if (intent != 'playbackOnly') {
            snapshot['inputs'] = <Map<String, dynamic>>[
              <String, dynamic>{
                'direction': 'input',
                'nativePortType': 'builtIn',
                'normalizedKind': 'builtIn',
                'uid': 'built-in-input',
                'name': 'Built-in Microphone',
                'channelCount': 1,
              },
            ];
            final juce = snapshot['juce']! as Map<String, dynamic>;
            juce['activeInputChannels'] = 1;
            final session = snapshot['session']! as Map<String, dynamic>;
            session['category'] = 'AVAudioSessionCategoryPlayAndRecord';
            session['inputChannelCount'] = 1;
          }
          return <String, dynamic>{
            'status': 'success',
            'generation': generation,
            'transitionId': 2,
            'diagnosticCode': 'ok',
            'elapsedMs': 4,
            'transportWasPlaying': false,
            'snapshot': snapshot,
          };
        case 'stopAudioRouteMonitoringV2':
          return null;
        case 'getInputDeviceInfos':
          return <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'MacBook Pro Microphone',
              'isBluetoothInput': false,
              'isBuiltIn': true,
              'isDefault': true,
              'transport': 'builtIn',
            },
            <String, dynamic>{
              'name': 'AirPods Pro',
              'isBluetoothInput': true,
              'isBuiltIn': false,
              'isDefault': false,
              'transport': 'bluetooth',
            },
          ];
        case 'addRow':
          return 42;
        case 'supportsLiveMidiClipPlayback':
          return true;
        case 'loadMidiClip':
        case 'updateMidiClipEvents':
          return true;
        default:
          return null;
      }
    });
  });

  test('recording stop returns native capture integrity facts', () async {
    final result = await JuceAudioEngine.stopRecording();
    expect(result.success, isTrue);
    expect(result.diagnosticCode, 'ok');
    expect(result.attemptedSamples, 24000);
    expect(result.acceptedSamples, 24000);
    expect(result.droppedSamples, 0);
    expect(result.actualSampleRate, 48000.0);
    expect(result.channelCount, 1);
    expect(calls.single.method, 'stopRecording');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('implementation-aware initialization keeps V2 off Legacy channel',
      () async {
    final legacy = await JuceAudioEngine.initialiseForImplementation(
      BluetoothImplementationV2.legacy,
    );
    expect(legacy, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'initialise');
  });

  test('V2 playback initialization uses only its dedicated native method',
      () async {
    final result = await JuceAudioEngine.initialisePlaybackV2(
      platformOverride: TargetPlatform.macOS,
    );

    expect(result.success, isTrue);
    expect(result.diagnosticCode, 'ok');
    expect(result.snapshot.implementation, BluetoothImplementationV2.v2);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'initialisePlaybackV2');
  });

  test('V2 playback initialization uses its native method on Android',
      () async {
    final result = await JuceAudioEngine.initialisePlaybackV2(
      platformOverride: TargetPlatform.android,
    );

    expect(result.success, isTrue);
    expect(calls.single.method, 'initialisePlaybackV2');
  });

  test('V2 playback initialization uses its native method on iOS', () async {
    final result = await JuceAudioEngine.initialisePlaybackV2(
      platformOverride: TargetPlatform.iOS,
    );

    expect(result.success, isTrue);
    expect(result.diagnosticCode, 'ok');
    expect(calls.single.method, 'initialisePlaybackV2');
  });

  test('iOS V2 readiness verifies the playback-only session and graph',
      () async {
    final startup = await JuceAudioEngine.initialisePlaybackV2(
      platformOverride: TargetPlatform.iOS,
    );
    expect(startup.success, isTrue);
    calls.clear();

    final ready = await JuceAudioEngine.validatePlaybackV2(
      platformOverride: TargetPlatform.iOS,
    );

    expect(ready, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'getAudioRouteSnapshotV2');
  });

  test('iOS V2 readiness rejects a non-playback session', () async {
    final startup = await JuceAudioEngine.initialisePlaybackV2(
      platformOverride: TargetPlatform.iOS,
    );
    expect(startup.success, isTrue);
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      calls.add(methodCall);
      final snapshot = _v2Snapshot();
      final session = snapshot['session']! as Map<String, dynamic>;
      session['category'] = 'AVAudioSessionCategoryPlayAndRecord';
      return snapshot;
    });

    final ready = await JuceAudioEngine.validatePlaybackV2(
      platformOverride: TargetPlatform.iOS,
    );

    expect(ready, isFalse);
    expect(calls.single.method, 'getAudioRouteSnapshotV2');
  });

  for (final route in <({String type, String kind})>[
    (type: 'Speaker', kind: 'builtIn'),
    (type: 'Headphones', kind: 'wired'),
    (type: 'USBAudio', kind: 'external'),
    (type: 'BluetoothA2DPOutput', kind: 'bluetoothMedia'),
    (type: 'BluetoothLE', kind: 'bluetoothLe'),
  ]) {
    test('iOS V2 readiness accepts stable ${route.kind} output', () async {
      final snapshot = _v2Snapshot(
        nativePortType: route.type,
        normalizedKind: route.kind,
      );
      useIOSRouteSnapshots(startup: snapshot, current: snapshot);

      final startup = await JuceAudioEngine.initialisePlaybackV2(
        platformOverride: TargetPlatform.iOS,
      );
      final ready = await JuceAudioEngine.validatePlaybackV2(
        platformOverride: TargetPlatform.iOS,
      );

      expect(startup.success, isTrue);
      expect(ready, isTrue);
    });
  }

  test('iOS V2 startup preserves the duplex rejection code', () async {
    final snapshot = _v2Snapshot(
      nativePortType: 'BluetoothHFP',
      normalizedKind: 'bluetoothDuplex',
    );
    useIOSRouteSnapshots(
      startup: snapshot,
      current: snapshot,
      startupSuccess: false,
      diagnosticCode: 'bluetooth_duplex_forbidden',
    );

    final startup = await JuceAudioEngine.initialisePlaybackV2(
      platformOverride: TargetPlatform.iOS,
    );

    expect(startup.success, isFalse);
    expect(startup.diagnosticCode, 'bluetooth_duplex_forbidden');
  });

  test('iOS V2 readiness rejects duplex output before Play', () async {
    final media = _v2Snapshot(
      nativePortType: 'BluetoothA2DPOutput',
      normalizedKind: 'bluetoothMedia',
    );
    final duplex = _v2Snapshot(
      nativePortType: 'BluetoothHFP',
      normalizedKind: 'bluetoothDuplex',
    );
    useIOSRouteSnapshots(startup: media, current: duplex);

    await JuceAudioEngine.initialisePlaybackV2(
      platformOverride: TargetPlatform.iOS,
    );
    final ready = await JuceAudioEngine.validatePlaybackV2(
      platformOverride: TargetPlatform.iOS,
    );

    expect(ready, isFalse);
  });

  test('iOS V2 readiness rejects every native identity change', () async {
    final startupSnapshot = _v2Snapshot(
      nativePortType: 'BluetoothA2DPOutput',
      normalizedKind: 'bluetoothMedia',
    );
    final changedSnapshots = <Map<String, dynamic>>[
      _v2Snapshot(
        nativePortType: 'BluetoothA2DPOutput',
        normalizedKind: 'bluetoothMedia',
        uid: 'changed-uid',
      ),
      _v2Snapshot(
        nativePortType: 'BluetoothLE',
        normalizedKind: 'bluetoothMedia',
      ),
      _v2Snapshot(
        nativePortType: 'BluetoothA2DPOutput',
        normalizedKind: 'bluetoothLe',
      ),
    ];

    for (final changed in changedSnapshots) {
      calls.clear();
      useIOSRouteSnapshots(startup: startupSnapshot, current: changed);
      await JuceAudioEngine.initialisePlaybackV2(
        platformOverride: TargetPlatform.iOS,
      );

      expect(
        await JuceAudioEngine.validatePlaybackV2(
          platformOverride: TargetPlatform.iOS,
        ),
        isFalse,
      );
    }
  });

  test('iOS V2 readiness rejects missing identity and session input', () async {
    final startupSnapshot = _v2Snapshot(
      nativePortType: 'BluetoothA2DPOutput',
      normalizedKind: 'bluetoothMedia',
    );
    for (final invalid in <Map<String, dynamic>>[
      _v2Snapshot(
        nativePortType: 'BluetoothA2DPOutput',
        normalizedKind: 'bluetoothMedia',
        uid: '',
      ),
      _v2Snapshot(
        nativePortType: 'BluetoothA2DPOutput',
        normalizedKind: 'bluetoothMedia',
        sessionInputChannels: 1,
      ),
    ]) {
      calls.clear();
      useIOSRouteSnapshots(startup: startupSnapshot, current: invalid);
      await JuceAudioEngine.initialisePlaybackV2(
        platformOverride: TargetPlatform.iOS,
      );

      expect(
        await JuceAudioEngine.validatePlaybackV2(
          platformOverride: TargetPlatform.iOS,
        ),
        isFalse,
      );
    }
  });

  test('Android V2 readiness delegates actual-state and route verification',
      () async {
    final ready = await JuceAudioEngine.validatePlaybackV2(
      platformOverride: TargetPlatform.android,
    );

    expect(ready, isTrue);
    expect(calls.single.method, 'validatePlaybackV2');
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    test('V2 route coordinator uses the isolated native contract on $platform',
        () async {
      final initial = await JuceAudioEngine.startAudioRouteMonitoringV2(
        platformOverride: platform,
      );
      final result = await JuceAudioEngine.applyAudioRouteConfigurationV2(
        12,
        platformOverride: platform,
      );
      await JuceAudioEngine.stopAudioRouteMonitoringV2(
        platformOverride: platform,
      );

      expect(initial.coordinatorManaged, isTrue);
      expect(result.generation, 12);
      expect(result.succeeded, isTrue);
      expect(
        calls.map((call) => call.method),
        <String>[
          'startAudioRouteMonitoringV2',
          'applyAudioRouteConfigurationV2',
          'stopAudioRouteMonitoringV2',
        ],
      );
      expect(
        Map<String, dynamic>.from(calls[1].arguments as Map),
        containsPair('desiredInputChannels', 0),
      );
    });
  }

  for (final platform in <TargetPlatform>[
    TargetPlatform.macOS,
    TargetPlatform.iOS,
  ]) {
    test('V2 recording intent uses the isolated native contract on $platform',
        () async {
      final result = await JuceAudioEngine.setAudioRouteIntentV2(
        AudioRouteIntentV2.preparingRecording,
        generation: 7,
        platformOverride: platform,
      );

      expect(result.succeeded, isTrue);
      expect(result.snapshot.intent, AudioRouteIntentV2.preparingRecording);
      expect(result.snapshot.juce.activeInputChannels, 1);
      expect(calls.single.method, 'setAudioRouteIntentV2');
      expect(
        Map<String, dynamic>.from(calls.single.arguments as Map)['intent'],
        'preparingRecording',
      );
    });
  }

  test('recording intent remains native-call-free on Android', () async {
    final result = await JuceAudioEngine.setAudioRouteIntentV2(
      AudioRouteIntentV2.preparingRecording,
      generation: 2,
      platformOverride: TargetPlatform.android,
    );

    expect(result.succeeded, isFalse);
    expect(result.diagnosticCode, 'recording_route_unsupported');
    expect(calls, isEmpty);
  });

  test('iOS V2 readiness accepts its verified mono recording route', () async {
    await JuceAudioEngine.initialisePlaybackV2(
      platformOverride: TargetPlatform.iOS,
    );
    final transition = await JuceAudioEngine.setAudioRouteIntentV2(
      AudioRouteIntentV2.preparingRecording,
      generation: 0,
      platformOverride: TargetPlatform.iOS,
    );
    JuceAudioEngine.acceptVerifiedAudioRouteTransitionV2(transition);
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      calls.add(methodCall);
      final snapshot = _v2Snapshot();
      snapshot['intent'] = 'preparingRecording';
      snapshot['inputs'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'direction': 'input',
          'nativePortType': 'MicrophoneBuiltIn',
          'normalizedKind': 'builtIn',
          'uid': 'built-in-input',
          'name': 'Built-in Microphone',
          'channelCount': 1,
        },
      ];
      final juce = snapshot['juce']! as Map<String, dynamic>;
      juce['activeInputChannels'] = 1;
      final session = snapshot['session']! as Map<String, dynamic>;
      session['category'] = 'AVAudioSessionCategoryPlayAndRecord';
      session['inputChannelCount'] = 1;
      return snapshot;
    });

    final ready = await JuceAudioEngine.validatePlaybackV2(
      platformOverride: TargetPlatform.iOS,
    );

    expect(ready, isTrue);
    expect(calls.single.method, 'getAudioRouteSnapshotV2');
  });

  test('loadClip sends rowId + timeline payload', () async {
    await JuceAudioEngine.loadClip(
      5,
      99,
      '/tmp/clip.wav',
      startSec: 1.25,
      lengthSec: 4.5,
      inFileOffsetSec: 0.4,
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'loadClip');
    expect(
      calls.single.arguments,
      <String, dynamic>{
        'clip': 5,
        'rowId': 99,
        'row': 99,
        'path': '/tmp/clip.wav',
        'startSec': 1.25,
        'lengthSec': 4.5,
        'inFileOffsetSec': 0.4,
      },
    );
  });

  test('clip mutations stay batched across the platform channel', () async {
    await JuceAudioEngine.updateClipTimelineBatch(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'clip': 3,
          'rowId': 9,
          'startSec': 1.0,
          'lengthSec': 2.0,
          'inFileOffsetSec': 0.25,
          'gain': 1.25,
          'extraGainLinear': 0.8,
          'reversed': true,
          'tempoRatio': 1.1,
          'preservePitch': false,
          'pitchSemitones': 2.0,
          'muted': true,
        },
        <String, dynamic>{
          'clip': 4,
          'rowId': 10,
          'startSec': 3.0,
          'lengthSec': 4.0,
          'inFileOffsetSec': 0.5,
        },
      ],
    );
    await JuceAudioEngine.updateClipFadesBatch(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'clip': 3,
          'fadeInSec': 0.1,
          'fadeOutSec': 0.2,
          'fadeCurve': 1,
        },
        <String, dynamic>{
          'clip': 4,
          'fadeInSec': 0.3,
          'fadeOutSec': 0.4,
          'fadeCurve': 2,
        },
      ],
    );
    await JuceAudioEngine.unloadClips(<int>[3, 4, 4, -1]);

    expect(calls.map((call) => call.method), <String>[
      'updateClipTimelineBatch',
      'updateClipFadesBatch',
      'unloadClips',
    ]);
    expect(
      ((calls[0].arguments as Map)['updates'] as List).first,
      containsPair('tempoRatio', 1.1),
    );
    expect(
      ((calls[0].arguments as Map)['updates'] as List).first,
      containsPair('muted', true),
    );
    expect(
      calls[2].arguments,
      <String, dynamic>{
        'clips': <int>[3, 4],
      },
    );
  });

  test('setAutomationTransport routes to setAutomationTransport', () async {
    await JuceAudioEngine.setAutomationTransport(3.0);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setAutomationTransport');
    expect(calls.single.arguments, <String, dynamic>{'timeSeconds': 3.0});
  });

  test('row API payloads and getRows mapping', () async {
    final rowId = await JuceAudioEngine.addRow('Vox', iconId: 3);
    final rows = await JuceAudioEngine.getRows();
    final moved = await JuceAudioEngine.moveRowOrder(2, 0);

    expect(rowId, 42);
    expect(rows, <Map<String, dynamic>>[
      <String, dynamic>{'rowId': 7, 'name': 'Drums', 'iconId': 1}
    ]);
    expect(moved, false);

    expect(calls[0].method, 'addRow');
    expect(calls[0].arguments, <String, dynamic>{'name': 'Vox', 'iconId': 3});
    expect(calls[1].method, 'getRows');
    expect(calls[2].method, 'moveRowOrder');
    expect(calls[2].arguments, <String, dynamic>{'from': 2, 'to': 0});
  });

  test('row restoration forwards an optional preferred stable id', () async {
    final rowId = await JuceAudioEngine.addRow(
      'Restored',
      iconId: 1,
      preferredRowId: 42,
    );

    expect(rowId, 42);
    expect(calls.single.method, 'addRow');
    expect(calls.single.arguments, <String, dynamic>{
      'name': 'Restored',
      'iconId': 1,
      'preferredRowId': 42,
    });
  });

  test('global transport getters/setters', () async {
    await JuceAudioEngine.setTransportSeconds(9.25);
    final now = await JuceAudioEngine.getTransportSeconds();
    await JuceAudioEngine.seekTransport(11.0);

    expect(now, 12.5);
    expect(calls[0].method, 'setTransportSeconds');
    expect(calls[0].arguments, <String, dynamic>{'timeSeconds': 9.25});
    expect(calls[1].method, 'getTransportSeconds');
    expect(calls[2].method, 'seekTransport');
    expect(calls[2].arguments, <String, dynamic>{'timeSeconds': 11.0});
  });

  test('preparePlaybackRoute routes reason payload', () async {
    await JuceAudioEngine.preparePlaybackRoute(reason: 'projectLoad');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'preparePlaybackRoute');
    expect(calls.single.arguments, <String, dynamic>{'reason': 'projectLoad'});
  });

  test('preparePlaybackGraph routes reason payload', () async {
    await JuceAudioEngine.preparePlaybackGraph(reason: 'midiPreview');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'preparePlaybackGraph');
    expect(calls.single.arguments, <String, dynamic>{'reason': 'midiPreview'});
  });

  test('getInputDeviceInfos parses macOS input metadata', () async {
    final infos = await JuceAudioEngine.getInputDeviceInfos();

    expect(infos, hasLength(2));
    expect(infos.first.name, 'MacBook Pro Microphone');
    expect(infos.first.isBluetoothInput, isFalse);
    expect(infos.first.isBuiltIn, isTrue);
    expect(infos.first.isDefault, isTrue);
    expect(infos.first.transport, 'builtIn');
    expect(infos.last.name, 'AirPods Pro');
    expect(infos.last.isBluetoothInput, isTrue);
    expect(infos.last.transport, 'bluetooth');
    expect(calls.single.method, 'getInputDeviceInfos');
  });

  test('getInputDeviceInfos returns empty list when plugin is unavailable',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    final infos = await JuceAudioEngine.getInputDeviceInfos();

    expect(infos, isEmpty);
  });

  test('getOutputDevices returns native output names', () async {
    final outputs = await JuceAudioEngine.getOutputDevices();

    expect(outputs, <String>['MacBook Pro Speakers', 'WH-1000XM4']);
    expect(calls.single.method, 'getOutputDevices');
  });

  test('selectOutputDevice sends selected output name', () async {
    final selected = await JuceAudioEngine.selectOutputDevice('WH-1000XM4');

    expect(selected, isTrue);
    expect(calls.single.method, 'selectOutputDevice');
    expect(calls.single.arguments, <String, dynamic>{'name': 'WH-1000XM4'});
  });

  test('capabilities + plugin scan normalization', () async {
    final caps = await JuceAudioEngine.getEngineCapabilities();
    final plugins = await JuceAudioEngine.scanPlugins();

    expect(caps.externalPluginHosting, isTrue);
    expect(caps.supportedPluginFormats, <String>['AU', 'VST3']);
    expect(caps.nativePluginEditor, isFalse);

    expect(plugins, <Map<String, dynamic>>[
      <String, dynamic>{
        'id': '/tmp/SomePlugin.vst3',
        'name': '/tmp/SomePlugin.vst3',
        'format': 'VST3',
      },
      <String, dynamic>{
        'id': 'au:com.test:unit',
        'name': 'Test Unit',
        'manufacturer': 'Mixroom',
        'category': 'Effect',
      },
    ]);

    expect(calls[0].method, 'getEngineCapabilities');
    expect(calls[1].method, 'scanPlugins');
  });

  test('live midi capability and payloads', () async {
    final supports = await JuceAudioEngine.supportsLiveMidiClipPlayback();
    final loaded = await JuceAudioEngine.loadMidiClip(
      3,
      12,
      instrumentId: 'mixroom.basic_synth',
      instrumentName: 'Basic Synth',
      notes: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'n1',
          'pitch': 60,
          'startBeat': 0.0,
          'lengthBeats': 1.0,
          'velocity': 0.8,
        }
      ],
      params: <String, double>{'cutoffHz': 3200.0},
      sourceTempoBpm: 120.0,
      startSec: 1.0,
      lengthSec: 2.0,
      inFileOffsetSec: 0.25,
    );
    final updated = await JuceAudioEngine.updateMidiClipEvents(
      3,
      instrumentId: 'mixroom.basic_synth',
      instrumentName: 'Basic Synth',
      notes: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'n1',
          'pitch': 62,
          'startBeat': 0.0,
          'lengthBeats': 0.5,
          'velocity': 0.9,
        }
      ],
      params: <String, double>{'drive': 0.1},
      sourceTempoBpm: 128.0,
    );

    expect(supports, isTrue);
    expect(loaded, isTrue);
    expect(updated, isTrue);
    expect(calls[0].method, 'supportsLiveMidiClipPlayback');
    expect(calls[1].method, 'loadMidiClip');
    expect(calls[2].method, 'updateMidiClipEvents');
  });
}
