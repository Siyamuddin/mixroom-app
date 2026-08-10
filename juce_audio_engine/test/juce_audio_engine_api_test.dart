import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('juce_audio_engine');
  final List<MethodCall> calls = <MethodCall>[];

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
        case 'initialisePlaybackV2':
          return <String, dynamic>{
            'success': true,
            'diagnosticCode': 'ok',
            'snapshot': <String, dynamic>{
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
                  'nativePortType': '0x626c746e',
                  'normalizedKind': 'builtIn',
                  'uid': 'output-uid',
                  'name': 'MacBook Pro Speakers',
                  'channelCount': 2,
                },
              ],
              'session': <String, dynamic>{},
              'juce': <String, dynamic>{
                'deviceOpen': true,
                'sampleRateHz': 48000.0,
                'bufferFrames': 512,
                'activeInputChannels': 0,
                'activeOutputChannels': 2,
              },
              'unavailableReasons': <String, String>{},
            },
          };
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

  test('V2 playback startup stays native-call-free on iOS', () async {
    final result = await JuceAudioEngine.initialisePlaybackV2(
      platformOverride: TargetPlatform.iOS,
    );

    expect(result.success, isFalse);
    expect(result.diagnosticCode, 'actual_state_unavailable');
    expect(calls, isEmpty);
  });

  test('Android V2 readiness uses native engine facts without route matching',
      () async {
    final ready = await JuceAudioEngine.validatePlaybackV2(
      platformOverride: TargetPlatform.android,
    );

    expect(ready, isTrue);
    expect(calls.single.method, 'validatePlaybackV2');
  });

  test('V2 route coordinator methods use the isolated native contract',
      () async {
    final initial = await JuceAudioEngine.startAudioRouteMonitoringV2(
      platformOverride: TargetPlatform.macOS,
    );
    final result = await JuceAudioEngine.applyAudioRouteConfigurationV2(
      12,
      platformOverride: TargetPlatform.macOS,
    );
    await JuceAudioEngine.stopAudioRouteMonitoringV2(
      platformOverride: TargetPlatform.macOS,
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

  test('V2 route coordinator methods stay native-call-free off macOS',
      () async {
    final initial = await JuceAudioEngine.startAudioRouteMonitoringV2(
      platformOverride: TargetPlatform.iOS,
    );
    final result = await JuceAudioEngine.applyAudioRouteConfigurationV2(
      4,
      platformOverride: TargetPlatform.android,
    );
    await JuceAudioEngine.stopAudioRouteMonitoringV2(
      platformOverride: TargetPlatform.iOS,
    );

    expect(
      initial.captureConsistency,
      AudioRouteCaptureConsistencyV2.unavailable,
    );
    expect(result.succeeded, isFalse);
    expect(calls, isEmpty);
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
