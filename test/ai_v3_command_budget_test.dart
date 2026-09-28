import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_preparer.dart';
import 'package:mixroom/ai/v3/ai_v3_resources.dart';

void main() {
  final fixture = jsonDecode(
    File('backend/llm_proxy/tests/fixtures/plan_command_budget_v1.json')
        .readAsStringSync(),
  ) as Map;
  final rebuild = jsonDecode(
    File('backend/llm_proxy/tests/fixtures/row_rebuild_v1.json')
        .readAsStringSync(),
  ) as Map;
  test('advertised command policy matches shared server fixture', () {
    expect(aiV3PlanCommandPolicy, fixture['policy']);
    expect(aiV3PlanOutputPolicy, 'serialized_plan_64000_bytes_v1');
    expect(aiV3MaxSerializedPlanBytes, 64000);
  });
  for (final rowCount in [6, 8]) {
    test('complete $rowCount-row rebuild prepares above 16 commands', () {
      final context = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(rebuild['cases'][0]['context'])) as Map,
      );
      final row = Map<String, dynamic>.from(
        (context['rows'] as List).first as Map,
      );
      context['rows'] = [
        for (var i = 0; i < rowCount; i++)
          {...row, 'row_id': 100 + i, 'display_index': i},
      ];
      context['clips'] = [];
      (context['project'] as Map)['row_capacity'] = {
        'current_rows': rowCount,
        'max_rows': rowCount,
        'can_create': false,
      };
      (context['project'] as Map)['plan_command_policy'] =
          aiV3PlanCommandPolicy;
      context['transport'] = {
        'playing': false,
        'recording': false,
        'loop_enabled': false,
      };
      Map<String, dynamic> command(
        String id,
        String type,
        Map<String, dynamic> args,
      ) => {'command_id': id, 'type': type, 'arguments': args};
      final deletes = [
        for (var i = 0; i < rowCount; i++)
          command('d$i', 'row.delete', {'row_id': 100 + i}),
      ];
      final creates = [
        for (var i = 0; i < rowCount; i++)
          command('r$i', 'row.create', {
            'name': 'Part $i',
            'lane': {'kind': 'midi', 'instrument_id': 'free-piano'},
            'position': {'kind': 'end'},
          }),
      ];
      final commands = [
        ...deletes.take(rowCount - 1),
        creates.first,
        deletes.last,
        ...creates.skip(1),
        for (var i = 0; i < rowCount; i++)
          command('c$i', 'midi.create_clip', {
            'destination': {
              'row_ref': {'command_id': 'r$i', 'output': 'row'},
            },
            'start_beat': 0,
            'length_beats': 32,
            'notes': [
              {
                'pitch': 60,
                'start_beat': 0,
                'length_beats': 1,
                'velocity': 0.7,
              },
            ],
          }),
      ];
      final plan = AiV3Plan.fromJson(
        {
          'schema_version': aiV3PlanVersion,
          'outcome': 'plan',
          'user_message': 'Rebuilt the rows.',
          'commands': commands,
          'question_options': [],
        },
        allowResourceRefs: true,
        resourceRefCommandTypes: aiV3RuntimeResourceRefConsumerTypes,
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'synthetic-rebuild',
          data: context,
        ),
      );
      expect(prepared.receipts.length, rowCount * 3);
      expect(prepared.actions, isNotEmpty);
    });
  }
  for (final count in fixture['counts'] as List) {
    test('$count commands: parsing and preparation agree', () {
      final raw = <String, dynamic>{
        'schema_version': aiV3PlanVersion,
        'outcome': 'plan',
        'user_message': 'Renamed the row.',
        'question_options': [],
        'commands': [
          for (var i = 0; i < count; i++)
            {
              'command_id': 'edit-$i',
              'type': 'row.rename',
              'arguments': {
                'row_id': fixture['row_id'],
                'new_name': '${fixture['name_prefix']}$i',
              },
            },
        ],
      };
      final context = Map<String, dynamic>.from(
        rebuild['cases'][0]['context'] as Map,
      );
      (context['project'] as Map)['plan_command_policy'] =
          aiV3PlanCommandPolicy;
      context['transport'] = {
        'playing': false,
        'recording': false,
        'loop_enabled': false,
      };
      final prepared = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(raw),
        context: AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'synthetic-commands',
          data: context,
        ),
      );
      expect(prepared.receipts.length, count);
      expect(prepared.actions.length, count);
    });
  }
}
