import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/instrument_classifier.dart';
import 'package:mixroom/ai/project_state_builder.dart';
import 'package:mixroom/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('juce_audio_engine');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final individual = (call.arguments as Map?)?['forceIndividualRow'] == true;
          switch (call.method) {
            case 'getTrackEffectsForRow':
              return <String>[individual ? 'Row EQ' : 'Group Reverb'];
            case 'getTrackEffectIdsForRow':
              return <String>[individual ? 'builtin.row-eq' : 'builtin.group-reverb'];
            case 'getTrackEffectInstanceIdsForRow':
              return <String>[individual ? 'row-effect-instance' : 'group-effect-instance'];
            case 'getTrackPluginParameters':
              return <Map<String, dynamic>>[];
            case 'getRowEffectBypassState':
              return false;
            case 'getMasterEffects':
              return <String>[];
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('group lead state keeps individual and group bus effect chains separate', () async {
    final state =
        await ProjectStateBuilder(
          classifier: InstrumentClassifier(enabled: false),
          maxRows: 1,
        ).build(
          audioTracks: const <AudioTrack>[],
          bpmFallback: 120,
          rowGain: const <double>[1],
          rowPan: const <double>[0.5],
          rowAutomation: <List<AutomationPoint>>[
            <AutomationPoint>[AutomationPoint(x: 0, volume: 1)],
          ],
          timelineRows: <TimelineRow>[
            TimelineRow(rowId: 42, name: 'Lead', iconId: 0, groupId: 'group-1'),
          ],
          trackGroups: <TrackGroup>[
            TrackGroup(
              id: 'group-1',
              name: 'Group',
              rowIds: const <int>[42, 43],
              effects: <EffectSnapshot>[
                EffectSnapshot('builtin.group-reverb', false, const {}),
              ],
            ),
          ],
        );

    expect(state.rows.single.effects.single.effectId, 'builtin.row-eq');
    expect(
      state.trackGroups.single.effects.single.effectId,
      'builtin.group-reverb',
    );

    final rowEffectCalls = calls.where(
      (call) => <String>{
        'getTrackEffectsForRow',
        'getTrackEffectIdsForRow',
        'getTrackEffectInstanceIdsForRow',
        'getTrackPluginParameters',
        'getRowEffectBypassState',
      }.contains(call.method),
    );
    expect(rowEffectCalls, isNotEmpty);
    expect(rowEffectCalls.any((call) => (call.arguments as Map)['forceIndividualRow'] == true), isTrue);
    expect(rowEffectCalls.any((call) => (call.arguments as Map)['forceIndividualRow'] != true), isTrue);
    expect(state.groupBuses.single['effects'][0]['effectId'], 'builtin.group-reverb');
    expect(state.groupBuses.single['effects'][0]['instanceId'], 'group-effect-instance');
    expect(state.toMagnitudeResolverJson()['group_buses'], state.groupBuses);

  });

  test('runtime project roles follow the current row order', () async {
    final state = await ProjectStateBuilder(
      classifier: InstrumentClassifier(enabled: false),
      maxRows: 3,
    ).build(
      audioTracks: const <AudioTrack>[],
      bpmFallback: 120,
      rowGain: const <double>[1, 1, 1],
      rowPan: const <double>[0.5, 0.5, 0.5],
      rowAutomation: const <List<AutomationPoint>>[
        <AutomationPoint>[],
        <AutomationPoint>[],
        <AutomationPoint>[],
      ],
      timelineRows: <TimelineRow>[
        TimelineRow(
          rowId: 20,
          name: 'Bass',
          iconId: 0,
          roleOverride: 'bass',
        ),
        TimelineRow(
          rowId: 10,
          name: 'Vocal',
          iconId: 0,
          roleOverride: 'vocals',
        ),
        TimelineRow(rowId: 30, name: 'Other', iconId: 0),
      ],
    );

    expect(
      state.rows
          .map((row) => <Object>[row.rowIndex, row.rowId, row.roleOverride])
          .toList(),
      const <List<Object>>[
        <Object>[0, 20, 'bass'],
        <Object>[1, 10, 'vocals'],
        <Object>[2, 30, ''],
      ],
    );
  });
}
