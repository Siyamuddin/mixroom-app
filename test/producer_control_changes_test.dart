import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/producer_control_changes.dart';

void main() {
  Map<String, dynamic> snapshot() => {
    'project_state': {
      'rows': [],
      'master_effects': [
        {
          'instanceId': 'a',
          'effectId': 'EQ',
          'name': 'EQ',
          'isBypassed': false,
          'parameters': [
            {
              'id': 'gain',
              'name': 'Gain',
              'type': 'float',
              'value': 0.0,
              'unit': 'dB',
            },
          ],
        },
        {
          'instanceId': 'b',
          'effectId': 'Compressor',
          'name': 'Compressor',
          'isBypassed': false,
          'parameters': [],
        },
      ],
    },
  };
  test(
    'parameter, bypass and reorder changes retain plugin instance identities',
    () {
      final before = snapshot();
      final after = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
      final effects = after['project_state']['master_effects'] as List;
      effects[0]['parameters'][0]['value'] = -3.0;
      effects[1]['isBypassed'] = true;
      effects.insert(0, effects.removeLast());
      final changes = producerControlChanges(before, after);
      final parameter = changes.singleWhere(
        (c) => c['kind'] == 'plugin_parameter',
      );
      expect(parameter['instance_id'], 'a');
      expect(parameter['before'], 0.0);
      expect(parameter['after'], -3.0);
      expect(
        changes.singleWhere((c) => c['kind'] == 'plugin_bypass')['instance_id'],
        'b',
      );
      expect(changes.where((c) => c['kind'] == 'plugin_reorder'), hasLength(2));
    },
  );
  test('insertion does not invent reorders of surviving instances', () {
    final before = snapshot();
    final after = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
    (after['project_state']['master_effects'] as List).insert(0, {
      'instanceId': 'new',
      'effectId': 'Reverb',
      'name': 'Reverb',
      'parameters': [],
    });
    final changes = producerControlChanges(before, after);
    expect(changes, hasLength(1));
    expect(changes.single['kind'], 'plugin_insert');
    expect(changes.single['after']['name'], 'Reverb');
  });
  test('display text changes alone are not producer edits', () {
    final before = snapshot();
    final after = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
    after['project_state']['master_effects'][0]['parameters'][0]['displayValue'] =
        '0.00 dB';
    expect(producerControlChanges(before, after), isEmpty);
  });
}
