import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/screens/audio_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('juce_audio_engine');
  final effects = <Map<String, dynamic>>[];
  var nextId = 10;

  setUp(() {
    effects
      ..clear()
      ..addAll(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Reverb',
          'effectId': 'builtin.reverb',
          'instanceId': 'instance-a',
          'bypassed': false,
          'params': <String, dynamic>{'Mix': 0.2},
          'state': '',
        },
        <String, dynamic>{
          'name': 'Reverb',
          'effectId': 'builtin.reverb',
          'instanceId': 'instance-b',
          'bypassed': false,
          'params': <String, dynamic>{'Mix': 0.7},
          'state': '',
        },
      ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args =
          Map<String, dynamic>.from(call.arguments as Map? ?? const {});
      final index = (args['effect'] as num?)?.toInt() ?? -1;
      switch (call.method) {
        case 'getTrackEffectsForRow':
          return effects.map((effect) => effect['name']).toList();
        case 'getTrackEffectIdsForRow':
          return effects.map((effect) => effect['effectId']).toList();
        case 'getTrackEffectInstanceIdsForRow':
          return effects.map((effect) => effect['instanceId']).toList();
        case 'getRowEffectBypassState':
          return effects[index]['bypassed'];
        case 'bypassRowEffect':
          effects[index]['bypassed'] = args['bypass'];
          return null;
        case 'removeTrackEffect':
          effects.removeAt(index);
          return null;
        case 'insertTrackEffect':
          effects.add(<String, dynamic>{
            'name': 'Reverb',
            'effectId': args['path'],
            'instanceId': 'restored-${nextId++}',
            'bypassed': false,
            'params': <String, dynamic>{},
            'state': '',
          });
          return true;
        case 'reorderTrackEffects':
          final from = (args['from'] as num).toInt();
          final to = (args['to'] as num).toInt();
          effects.insert(to, effects.removeAt(from));
          return null;
        case 'setTrackEffect':
          (effects[index]['params'] as Map<String, dynamic>)[args['paramId']] =
              args['value'];
          return null;
        case 'setTrackEffectState':
          effects[index]['state'] = args['stateBase64'];
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('bypass action targets the exact duplicate instance', () async {
    final action = BypassEffectInstanceAction(
      row: 0,
      effectInstanceId: 'instance-b',
      effectId: 'builtin.reverb',
      effectOccurrence: 1,
      oldState: false,
      newState: true,
      onChange: () {},
    );

    await action.redo();
    expect(effects[0]['bypassed'], isFalse);
    expect(effects[1]['bypassed'], isTrue);
    await action.undo();
    expect(effects[1]['bypassed'], isFalse);
  });

  test('remove action restores exact state and remains redoable', () async {
    String? remappedFrom;
    String? remappedTo;
    final action = RemoveEffectInstanceAction(
      row: 0,
      effectIndex: 1,
      effectInstanceId: 'instance-b',
      effectOccurrence: 1,
      removedEffect: EffectSnapshot(
        'builtin.reverb',
        true,
        <String, dynamic>{'Mix': 0.7},
        displayName: 'Reverb',
      ),
      onChange: () {},
      onInstanceRestored: (oldInstanceId, newInstanceId) async {
        remappedFrom = oldInstanceId;
        remappedTo = newInstanceId;
      },
    );

    await action.redo();
    expect(effects, hasLength(1));
    expect(effects.single['instanceId'], 'instance-a');

    await action.undo();
    expect(effects, hasLength(2));
    expect(effects[1]['effectId'], 'builtin.reverb');
    expect(effects[1]['params'], <String, dynamic>{'Mix': 0.7});
    expect(effects[1]['bypassed'], isTrue);
    expect(remappedFrom, 'instance-b');
    expect(remappedTo, effects[1]['instanceId']);

    await action.redo();
    expect(effects, hasLength(1));
    expect(effects.single['instanceId'], 'instance-a');
  });
}
