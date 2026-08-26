import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_adaptive_midi_planner.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_planner_request.dart';
import 'package:mixroom/ai/v3/ai_v3_style_compiler.dart';

AiV3Plan _plan({
  required String outcome,
  required List<AiV3Command> commands,
  AiV3GoalKind goalKind = AiV3GoalKind.namedEdit,
}) => AiV3Plan(
  outcome: outcome,
  goalKind: goalKind,
  userMessage: 'Prepared.',
  commands: commands,
);

AiV3Command _align() => const AiV3Command(
  commandId: 'align',
  type: 'clip.align_tempo_to_project',
  arguments: <String, dynamic>{'clip_id': 'clip-1', 'mode': 'preserve_pitch'},
);

AiV3Command _pitch() => const AiV3Command(
  commandId: 'pitch',
  type: 'clip.adjust_pitch_semitones',
  arguments: <String, dynamic>{'clip_id': 'clip-1', 'delta_semitones': 3},
);

void main() {
  group('aiV3MusicalDimensionCompilerInstructions', () {
    test('teaches method without genre recipes or hardcoded numbers', () {
      const compiler = aiV3MusicalDimensionCompilerInstructions;
      expect(compiler, contains('Implied steps of a goal are related'));
      expect(compiler, contains('preserve_pitch true'));
      expect(
        compiler,
        contains('Do not substitute clip.align_tempo_to_project'),
      );
      expect(compiler, contains('Questions do not mutate'));
      expect(compiler, contains('Named single edits remain single edits'));
      expect(compiler, contains('squeaky'));
      expect(compiler, contains('ORIGINAL_REQUEST_VERBATIM only'));
      expect(compiler, contains('not a request to repeat'));
      expect(compiler, contains('speeding the'));
      expect(compiler, contains('vocal-character metaphor alone is not'));
      expect(compiler, contains('Pitch-only metaphors stay moderate'));
      expect(compiler, isNot(contains('chipmunk')));
      expect(compiler, contains('not a full octave'));
      expect(compiler, contains('even when library assets exist'));
      expect(compiler, contains('mix.apply_goal pan intent'));
      expect(
        compiler,
        contains('Named single edits, questions, and refusals'),
      );
      expect(compiler, contains('fill skipped'));
      expect(compiler, contains('generated_drums'));
      expect(compiler, contains('leave skipped empty'));
      expect(
        compiler,
        isNot(contains('user_message must name what will change and which')),
      );
      expect(compiler, contains('names both speed and pitch'));
      expect(
        compiler,
        contains('Set goal_kind from ORIGINAL_REQUEST_VERBATIM only'),
      );
      expect(compiler, contains('production_goal'));
      expect(compiler, contains('named_edit'));
      expect(compiler, isNot(contains('nightcore')));
      expect(compiler, isNot(contains('hyperpop')));
      expect(compiler, isNot(contains('Recognized style')));
      expect(compiler, isNot(contains('delta_semitones 3')));
      expect(compiler, isNot(contains('1.25')));
    });

    test('retry reminder has no style names', () {
      expect(
        aiV3AlignTempoCollapseRetryReminder,
        contains('Keep goal_kind production_goal'),
      );
      expect(aiV3AlignTempoCollapseRetryReminder, isNot(contains('nightcore')));
      expect(aiV3AlignTempoCollapseRetryReminder, isNot(contains('8D')));
      expect(aiV3AlignTempoCollapseRetryReminder, isNot(contains('8d')));
    });
  });

  group('planner instructions are request-independent', () {
    test('nightcore, phonk, and set-tempo share identical instructions', () {
      String instructions(String request) =>
          buildAiV3PlannerRequestBody(
                contextData: const <String, dynamic>{},
                originalRequest: request,
                model: 'test-model',
                reasoningEffort: 'low',
              )['instructions']
              as String;

      final nightcore = instructions('make this a nightcore remix');
      final phonk = instructions('make this a phonk remix');
      final tempo = instructions('set tempo to 140');
      final question = instructions('what is nightcore?');
      final pitch = instructions('pitch the vocal +3');
      final vaporwave = instructions('as a vaporwave version please');
      final chipmunk = instructions('chipmunk this');
      final orbit = instructions('orbit in headphones');
      final garage = instructions('make this a garage remix');
      expect(nightcore, phonk);
      expect(nightcore, tempo);
      expect(nightcore, question);
      expect(nightcore, pitch);
      expect(nightcore, vaporwave);
      expect(nightcore, chipmunk);
      expect(nightcore, orbit);
      expect(nightcore, garage);
      expect(
        nightcore,
        contains(aiV3MusicalDimensionCompilerInstructions.trim()),
      );
      expect(nightcore, isNot(contains('Recognized style')));
      expect(nightcore, isNot(contains('delta_semitones 3')));
    });

    test('difference lives in ORIGINAL_REQUEST_VERBATIM', () {
      Map<String, dynamic> body(String request) => buildAiV3PlannerRequestBody(
        contextData: const <String, dynamic>{
          'project': <String, dynamic>{'bpm': 180.0},
        },
        originalRequest: request,
        model: 'test-model',
        reasoningEffort: 'low',
      );

      final nightcore = body('make this a nightcore remix');
      final phonk = body('make this a phonk remix');
      expect(nightcore['instructions'], phonk['instructions']);
      expect(jsonEncode(nightcore['input']), contains('nightcore'));
      expect(jsonEncode(phonk['input']), contains('phonk'));
      expect(jsonEncode(nightcore['input']), contains('180.0'));
      expect(jsonEncode(phonk['input']), isNot(contains('nightcore')));
    });

    test('adaptive first and continuation join the same compiler', () {
      const request = 'make this a nightcore remix';
      final first = buildAiV3AdaptiveFirstRequestBody(
        compactCore: const <String, dynamic>{},
        originalRequest: request,
        model: 'test-model',
        reasoningEffort: 'low',
      );
      final continuation = buildAiV3AdaptiveContinuationRequestBody(
        compactCore: const <String, dynamic>{},
        originalRequest: request,
        retrievalRequest: const <String, dynamic>{},
        retrievalResult: const <String, dynamic>{},
        model: 'test-model',
        reasoningEffort: 'low',
      );
      final oneShot = buildAiV3PlannerRequestBody(
        contextData: const <String, dynamic>{},
        originalRequest: request,
        model: 'test-model',
        reasoningEffort: 'low',
      );
      expect(
        first['instructions'],
        contains(aiV3MusicalDimensionCompilerInstructions.trim()),
      );
      expect(
        continuation['instructions'],
        contains(aiV3MusicalDimensionCompilerInstructions.trim()),
      );
      expect(
        oneShot['instructions'],
        contains(aiV3MusicalDimensionCompilerInstructions.trim()),
      );
    });

    test('proxy payload omits owned instructions and sends flags', () {
      final body = buildAiV3PlannerRequestBody(
        contextData: const <String, dynamic>{},
        originalRequest: 'make this a nightcore remix',
        model: 'test-model',
        reasoningEffort: 'low',
        includeOwnedInstructions: false,
        alignTempoCollapseRetry: true,
        resourceRefsEnabled: true,
      );
      expect(body.containsKey('instructions'), isFalse);
      expect(jsonEncode(body), isNot(contains('You are Mixroom')));
      expect(
        jsonEncode(body),
        isNot(contains(aiV3MusicalDimensionCompilerInstructions.trim())),
      );
      expect(
        jsonEncode(body['input']),
        contains('ORIGINAL_REQUEST_VERBATIM'),
      );
      expect((body['metadata'] as Map)['v3_align_tempo_retry'], '1');
      expect((body['metadata'] as Map)['v3_resource_refs'], '1');
    });

    test('llm_proxy mirrors planner and compiler instructions', () {
      final serverText = File(
        'backend/llm_proxy/src/common/ai_v3_planner_contract.py',
      ).readAsStringSync();
      expect(
        serverText,
        contains(aiV3MusicalDimensionCompilerInstructions.trim()),
      );
      expect(
        serverText,
        contains(aiV3AlignTempoCollapseRetryReminder.trim()),
      );
      expect(
        serverText,
        contains("You are Mixroom's sole semantic and musical planner."),
      );
      expect(serverText, contains('Never invent a group.'));
      expect(
        serverText,
        contains('Set goal_kind from ORIGINAL_REQUEST_VERBATIM only'),
      );
    });
  });

  group('shouldRetryAiV3AlignTempoCollapse', () {
    test('retries a production_goal align-only plan', () {
      expect(
        shouldRetryAiV3AlignTempoCollapse(
          _plan(
            outcome: 'plan',
            goalKind: AiV3GoalKind.productionGoal,
            commands: <AiV3Command>[_align()],
          ),
        ),
        isTrue,
      );
    });

    test('does not retry a named_edit align-only plan', () {
      expect(
        shouldRetryAiV3AlignTempoCollapse(
          _plan(outcome: 'plan', commands: <AiV3Command>[_align()]),
        ),
        isFalse,
      );
    });

    test('does not retry questions or named pitch edits', () {
      expect(
        shouldRetryAiV3AlignTempoCollapse(
          _plan(
            outcome: 'respond',
            goalKind: AiV3GoalKind.question,
            commands: const <AiV3Command>[],
          ),
        ),
        isFalse,
      );
      expect(
        shouldRetryAiV3AlignTempoCollapse(
          _plan(outcome: 'plan', commands: <AiV3Command>[_pitch()]),
        ),
        isFalse,
      );
    });

    test('does not retry a multi-family production plan', () {
      expect(
        shouldRetryAiV3AlignTempoCollapse(
          _plan(
            outcome: 'plan',
            goalKind: AiV3GoalKind.productionGoal,
            commands: <AiV3Command>[_align(), _pitch()],
          ),
        ),
        isFalse,
      );
    });
  });
}
