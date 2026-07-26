import 'dart:convert';

import 'ai_v3_contract.dart';

const String aiV3MidiTimingInstructions =
    'MIDI note starts are clip-relative and zero-based. Within each bar, '
    'spoken beat N maps to offset N−1 from that bar’s start; in 4/4, beats '
    '1–4 therefore map to offsets 0–3. When the quarter note is the beat '
    'unit, quarter notes advance by 1 beat and eighth notes by 0.5 beats. '
    'Independently requested MIDI notes may share the same start time and '
    'must not replace or suppress one another.';

const String aiV3PlannerInstructions = '''
You are Mixroom's sole semantic and musical planner.
Use the original request exactly as written and the authoritative structured context.
Return one submit_plan_v3 call. Use only stable IDs present in context.
Respect explicit do-not-change constraints by selecting only commands whose
typed targets and operation-specific effects satisfy them. Each command changes
only the state named by its type; do not add unrelated commands.
Never invent a group. Use a group_id only when it exists in context.groups.
For multiple named ungrouped rows, emit one ordered row-targeted command per
row. Use all_rows only when the request genuinely targets every row.
When request_mode is modify_pending_plan, apply modification_request to the
pending_plan and return a complete replacement PlanV3, never a partial patch.
Prefer a valid executable plan when the request and target are sufficiently clear.
Clarify only genuine ambiguity that changes the result. Never invent a row, clip,
instrument, effect, parameter, or library asset. For composition, provide exact
musical notes and timing rather than vague directions. Keep generated material to
eight bars. Match the language of the user's latest request.
$aiV3MidiTimingInstructions
The application will perform factual checks and execution; do not describe changes
as already applied.
If commands is non-empty, outcome must be plan. If outcome is respond, clarify,
or unsupported, commands must be empty.
''';

/// Builds the exact payload sent to OpenAI by the V3 planner.
///
/// This is intentionally dependency-light and pure so diagnostic tooling can
/// measure the production payload without loading Flutter or native audio code.
Map<String, dynamic> buildAiV3PlannerRequestBody({
  required Map<String, dynamic> contextData,
  required String originalRequest,
  required String model,
  required String reasoningEffort,
  String? promptTraceId,
  Set<String> commandTypes = aiV3CommandTypes,
  String architecture = 'v3_one_shot_prototype',
}) {
  final plannerContext = Map<String, dynamic>.from(contextData)
    ..remove('original_request')
    ..remove('conversation');
  final recentConversation =
      contextData['conversation'] as List? ?? const <Object>[];
  final normalizedTraceId = (promptTraceId ?? '').trim();
  return <String, dynamic>{
    'model': model.trim(),
    'instructions': aiV3PlannerInstructions.trim(),
    'input': <Map<String, dynamic>>[
      <String, dynamic>{
        'role': 'user',
        'content': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'input_text',
            'text': 'ORIGINAL_REQUEST_VERBATIM:\n$originalRequest',
          },
          <String, dynamic>{
            'type': 'input_text',
            'text':
                'RECENT_CONVERSATION_JSON:\n${jsonEncode(recentConversation)}',
          },
          <String, dynamic>{
            'type': 'input_text',
            'text': 'CORE_CONTEXT_V3_JSON:\n${jsonEncode(plannerContext)}',
          },
        ],
      },
    ],
    'tools': <Map<String, dynamic>>[
      aiV3SubmitPlanTool(
        commandTypes: commandTypes,
        includeCommandSemantics: true,
      ),
    ],
    'tool_choice': <String, dynamic>{
      'type': 'function',
      'name': 'submit_plan_v3',
    },
    'parallel_tool_calls': false,
    'max_output_tokens': 4096,
    'reasoning': <String, dynamic>{'effort': reasoningEffort},
    'store': true,
    if (normalizedTraceId.isNotEmpty)
      'metadata': <String, String>{
        'prompt_trace_id': normalizedTraceId.substring(
          0,
          normalizedTraceId.length > 64 ? 64 : normalizedTraceId.length,
        ),
        'architecture': architecture,
      },
  };
}
