import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_adaptive_midi_planner.dart';
import 'package:mixroom/ai/v3/ai_v3_planner_request.dart';

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
        isNot(contains('documented typed output')),
      );
      expect(jsonEncode(enabled), contains('"clip_ref"'));
      expect(enabled['instructions'], contains('documented typed output'));
      expect(jsonEncode(enabled), isNot(contains('"row_ref"')));
      expect(
        (enabled['metadata'] as Map)['surface_revision'],
        'stem_pitch_midi_transpose_resource_refs_v1',
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
        expect(request['instructions'], contains('documented typed output'));
        expect(jsonEncode(request), contains('"clip_ref"'));
        expect(jsonEncode(request), isNot(contains('"row_ref"')));
        expect(
          (request['metadata'] as Map)['surface_revision'],
          contains('stem_pitch_midi_transpose_resource_refs_v1'),
        );
      }
    },
  );
}
