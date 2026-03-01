import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
