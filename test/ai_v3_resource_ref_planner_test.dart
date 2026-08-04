import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_adaptive_midi_planner.dart';
import 'package:mixroom/ai/v3/ai_v3_planner_request.dart';
import 'package:mixroom/ai/v3/ai_v3_resources.dart';

void main() {
  test(
    'one-shot planner exposes the narrow reference surface only when enabled',
    () {
      final disabled = buildAiV3PlannerRequestBody(
        contextData: const <String, dynamic>{},
        originalRequest: 'Edit the project.',
        model: 'test-model',
        reasoningEffort: 'low',
      );
      final enabled = buildAiV3PlannerRequestBody(
        contextData: const <String, dynamic>{},
        originalRequest: 'Edit the project.',
        model: 'test-model',
        reasoningEffort: 'low',
        resourceRefsEnabled: true,
        promptTraceId: 'resource-ref-test',
      );

      expect(jsonEncode(disabled), isNot(contains('"clip_ref"')));
      expect(
        disabled['instructions'],
        isNot(contains('A later command may target a documented typed output')),
      );
      expect(
        disabled['instructions'],
        contains('Never substitute a pre-existing resource'),
      );
      expect(
        disabled['instructions'],
        contains('only from the unchanged current original request'),
      );
      expect(jsonEncode(enabled), contains('"clip_ref"'));
      expect(enabled['instructions'], contains('documented typed output'));
      expect(jsonEncode(enabled), contains('produces no output'));
      expect(
        enabled['instructions'],
        contains('choose an available producer form'),
      );
      expect(
        enabled['instructions'],
        contains('embedded new_row is not a referenceable output'),
      );
      expect(
        enabled['instructions'],
        contains('reuse that earlier reference for later edits'),
      );
      expect(jsonEncode(enabled), contains('"row_ref"'));
      expect(
        (enabled['metadata'] as Map)['surface_revision'],
        aiV3ResourceRefSurfaceRevision,
      );
    },
  );

  test(
    'adaptive planner stages share the same opt-in reference instruction',
    () {
      final first = buildAiV3AdaptiveFirstRequestBody(
        compactCore: const <String, dynamic>{},
        originalRequest: 'Edit the project.',
        model: 'test-model',
        reasoningEffort: 'low',
        resourceRefsEnabled: true,
        promptTraceId: 'resource-ref-test',
      );
      final continuation = buildAiV3AdaptiveContinuationRequestBody(
        compactCore: const <String, dynamic>{},
        originalRequest: 'Edit the project.',
        retrievalRequest: const <String, dynamic>{},
        retrievalResult: const <String, dynamic>{},
        model: 'test-model',
        reasoningEffort: 'low',
        resourceRefsEnabled: true,
        promptTraceId: 'resource-ref-test',
      );

      for (final request in <Map<String, dynamic>>[first, continuation]) {
        expect(
          request['instructions'],
          contains('Never substitute a pre-existing resource'),
        );
        expect(
          request['instructions'],
          contains('only from the unchanged current original request'),
        );
        expect(request['instructions'], contains('documented typed output'));
        expect(
          request['instructions'],
          contains('choose an available producer form'),
        );
        expect(
          request['instructions'],
          contains('embedded new_row is not a referenceable output'),
        );
        expect(
          request['instructions'],
          contains('reuse that earlier reference for later edits'),
        );
        expect(jsonEncode(request), contains('"clip_ref"'));
        expect(jsonEncode(request), contains('"row_ref"'));
        expect(
          (request['metadata'] as Map)['surface_revision'],
          contains(aiV3ResourceRefSurfaceRevision),
        );
      }
    },
  );

  test('planner schema reinforces lifecycle and visible response language', () {
    final request = buildAiV3PlannerRequestBody(
      contextData: const <String, dynamic>{},
      originalRequest: 'Create a new clip and edit it.',
      model: 'test-model',
      reasoningEffort: 'low',
      resourceRefsEnabled: true,
      promptTraceId: 'planner-fidelity-test',
    );
    final tool = (request['tools'] as List).single as Map;
    final parameters = tool['parameters'] as Map;
    final properties = parameters['properties'] as Map;
    final commands = properties['commands'] as Map;
    final userMessage = properties['user_message'] as Map;
    final questionOptions = properties['question_options'] as Map;

    expect(
      commands['description'],
      contains('preserves explicit create-versus-edit intent'),
    );
    expect(
      commands['description'],
      contains('never substitute a similar pre-existing resource'),
    );
    expect(
      userMessage['description'],
      contains('language of the unchanged current original request'),
    );
    expect(
      questionOptions['description'],
      contains('language of the unchanged current original request'),
    );
  });

  test('flagged schema exposes only compatible registered output ports', () {
    final request = buildAiV3PlannerRequestBody(
      contextData: const <String, dynamic>{},
      originalRequest: 'Edit the project.',
      model: 'test-model',
      reasoningEffort: 'low',
      resourceRefsEnabled: true,
      promptTraceId: 'resource-port-test',
    );
    final tool = (request['tools'] as List).single as Map;
    final parameters = tool['parameters'] as Map;
    final commandVariants =
        ((((parameters['properties'] as Map)['commands'] as Map)['items']
                    as Map)['anyOf']
                as List)
            .cast<Map>();

    List<String> outputPortsFor(String commandType, String referenceField) {
      final variant = commandVariants.singleWhere((candidate) {
        final typeSchema =
            ((candidate['properties'] as Map)['type'] as Map);
        return (typeSchema['enum'] as List).contains(commandType);
      });
      final arguments = (variant['properties'] as Map)['arguments'] as Map;
      final referenceVariant = (arguments['anyOf'] as List)
          .cast<Map>()
          .singleWhere(
            (candidate) =>
                ((candidate['properties'] as Map)[referenceField]) != null,
          );
      final referenceSchema =
          (referenceVariant['properties'] as Map)[referenceField] as Map;
      final outputSchema =
          (referenceSchema['properties'] as Map)['output'] as Map;
      return (outputSchema['enum'] as List).cast<String>();
    }

    expect(
      outputPortsFor('row.rename', 'row_ref'),
      <String>['instrumental_row', 'midi_row', 'row', 'vocals_row'],
    );
    expect(
      outputPortsFor('clip.adjust_pitch_semitones', 'clip_ref'),
      containsAll(<String>[
        'audio_clip',
        'copy_clip',
        'instrumental_clip',
        'left_clip',
        'right_clip',
        'vocals_clip',
      ]),
    );
    expect(
      outputPortsFor('midi.transpose', 'clip_ref'),
      <String>['copy_clip', 'left_clip', 'midi_clip', 'right_clip'],
    );
    expect(
      outputPortsFor('clip.convert_to_midi', 'clip_ref'),
      <String>[
        'audio_clip',
        'copy_clip',
        'glued_clip',
        'instrumental_clip',
        'left_clip',
        'right_clip',
        'vocals_clip',
      ],
    );
  });

  test('typed glue schema is flagged while legacy clip_ids stay unchanged', () {
    Map glueArguments(Map<String, dynamic> request) {
      final tool = (request['tools'] as List).single as Map;
      final parameters = tool['parameters'] as Map;
      final variants = (((((parameters['properties'] as Map)['commands']
                      as Map)['items'] as Map)['anyOf']) as List)
          .cast<Map>();
      final glue = variants.singleWhere((candidate) {
        final type = ((candidate['properties'] as Map)['type'] as Map);
        return (type['enum'] as List).single == 'clip.glue';
      });
      return (glue['properties'] as Map)['arguments'] as Map;
    }

    final disabled = buildAiV3PlannerRequestBody(
      contextData: const <String, dynamic>{},
      originalRequest: 'Glue the clips.',
      model: 'test-model',
      reasoningEffort: 'low',
    );
    final enabled = buildAiV3PlannerRequestBody(
      contextData: const <String, dynamic>{},
      originalRequest: 'Glue the clips.',
      model: 'test-model',
      reasoningEffort: 'low',
      resourceRefsEnabled: true,
    );
    final disabledArguments = glueArguments(disabled);
    final enabledArguments = glueArguments(enabled);
    expect((disabledArguments['properties'] as Map), contains('clip_ids'));
    expect((disabledArguments['properties'] as Map), isNot(contains('sources')));
    expect((enabledArguments['properties'] as Map), contains('sources'));
    expect((enabledArguments['properties'] as Map), isNot(contains('clip_ids')));
  });
}
