// Opt-in offline readback of synthetic evaluation output; no provider/app calls.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_preparer.dart';
import 'package:mixroom/ai/v3/ai_v3_resources.dart';

void main() {
  final input = Platform.environment['PRO4_REBUILD_RESULTS'];
  test(
    'synthetic live plans agree with client preparation',
    () {
      final records = File(input!)
          .readAsLinesSync()
          .where((line) => line.trim().isNotEmpty)
          .map((line) => Map<String, dynamic>.from(jsonDecode(line) as Map));
      var checked = 0;
      for (final record in records) {
        if (record['backend_valid'] != true || record['outcome'] != 'plan') {
          continue;
        }
        final context = AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'synthetic-rebuild',
          data: {
            ...Map<String, dynamic>.from(record['context'] as Map),
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
        final plan = AiV3Plan.fromJson(
          Map<String, dynamic>.from(record['plan'] as Map),
          allowResourceRefs: true,
          resourceRefCommandTypes: aiV3RuntimeResourceRefConsumerTypes,
        );
        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: context,
        );
        expect(
          prepared.actions,
          isNotEmpty,
          reason: '${record['case']}/${record['repeat']}/${record['variant']}',
        );
        checked++;
      }
      expect(checked, greaterThan(0));
      // This opt-in evaluator intentionally emits its aggregate result.
      // ignore: avoid_print
      print('REBUILD_CLIENT_PLANS_CHECKED=$checked');
    },
    skip: input == null
        ? 'Set PRO4_REBUILD_RESULTS to a synthetic export'
        : false,
  );
}
