import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_automation_targets.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';

void main() {
  test('empty rows still expose volume, mix:gain, and mix:pan', () {
    final targets = aiV3EnsureRowMixAutomationTargets(const <Object>[]);
    expect(targets.map((target) => target['target_id']).toList(), <String>[
      'volume',
      'mix:gain',
      'mix:pan',
    ]);
    expect(targets.map((target) => target['id']).toList(), <String>[
      'volume',
      'mix:gain',
      'mix:pan',
    ]);
    expect(targets.every((target) => target['uiVisible'] == true), isTrue);
    expect(targets.every((target) => target['isOrphan'] == false), isTrue);
  });

  test('keeps existing targets and fills only missing mix ids', () {
    final targets = aiV3EnsureRowMixAutomationTargets(<Object>[
      <String, dynamic>{'id': 'volume', 'kind': 'gain', 'uiVisible': false},
      <String, dynamic>{'target_id': 'fx0:Reverb', 'kind': 'fx'},
    ]);
    expect(targets.map((target) => target['target_id']).toList(), <String>[
      'volume',
      'mix:gain',
      'mix:pan',
      'fx0:Reverb',
    ]);
    expect(targets.first['uiVisible'], isFalse);
  });

  test('detects mix:pan automation in a plan', () {
    const pan = AiV3Command(
      commandId: 'sweep',
      type: 'automation.set_points',
      arguments: <String, dynamic>{
        'row_id': 1,
        'automation_target_id': 'mix:pan',
      },
    );
    const gain = AiV3Command(
      commandId: 'gain',
      type: 'automation.set_points',
      arguments: <String, dynamic>{
        'row_id': 1,
        'automation_target_id': 'mix:gain',
      },
    );
    expect(aiV3PlanWritesMixPanAutomation(<AiV3Command>[pan]), isTrue);
    expect(aiV3PlanWritesMixPanAutomation(<AiV3Command>[gain]), isFalse);
  });

  test('strips pan intents when mix:pan automation is present', () {
    const pan = AiV3Command(
      commandId: 'sweep',
      type: 'automation.set_points',
      arguments: <String, dynamic>{'automation_target_id': 'mix:pan'},
    );
    final intents = <Map<String, dynamic>>[
      <String, dynamic>{'kind': 'pan', 'direction': 'widen'},
      <String, dynamic>{'kind': 'eq', 'descriptor': 'air_boost'},
    ];
    final resolved = aiV3ResolvedMixGoalIntents(
      commands: <AiV3Command>[pan],
      intents: intents,
    );
    expect(resolved, <Map<String, dynamic>>[
      <String, dynamic>{'kind': 'eq', 'descriptor': 'air_boost'},
    ]);
    expect(
      aiV3ResolvedMixGoalIntents(
        commands: const <AiV3Command>[],
        intents: intents,
      ),
      intents,
    );
  });
}
