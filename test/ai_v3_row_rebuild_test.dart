import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_preparer.dart';
import 'package:mixroom/ai/v3/ai_v3_resources.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'backend/llm_proxy/tests/fixtures/row_rebuild_v1.json',
            ).readAsStringSync(),
          )
          as Map;
  for (final raw in fixture['cases'] as List) {
    final c = Map<String, dynamic>.from(raw as Map);
    test('shared row rebuild: ${c['name']}', () {
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'synthetic-rebuild',
        data: {
          ...Map<String, dynamic>.from(c['context'] as Map),
          'transport': {
            'playing': false,
            'recording': false,
            'metronome_enabled': false,
            'loop_enabled': false,
            'loop_start_ms': 0,
            'loop_end_ms': 0,
          },
        },
      );
      prepare() {
        final plan = AiV3Plan.fromJson(
          Map<String, dynamic>.from(c['plan'] as Map),
          allowResourceRefs: true,
          resourceRefCommandTypes: aiV3RuntimeResourceRefConsumerTypes,
        );
        return const AiV3CommandPreparer().prepare(
          plan: plan,
          context: context,
        );
      }

      if (c['client_error'] != null) {
        expect(
          prepare,
          throwsA(
            predicate(
              (e) =>
                  (e is AiV3PreparationException &&
                      e.code == c['client_error']) ||
                  (e is AiV3ContractException && e.code == c['client_error']),
            ),
          ),
        );
      } else {
        final prepared = prepare();
        expect(prepared.actions, isNotEmpty);
        expect(
          prepared.receipts.length,
          (c['plan']['commands'] as List).length,
        );
      }
    });
  }
}
