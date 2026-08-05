import 'dart:convert';

import 'ai_v3_contract.dart';
import 'ai_v3_resources.dart';
import 'ai_v3_user_facing_text.dart';

const String aiV3MidiTimingInstructions =
    'MIDI note starts are clip-relative and zero-based. Within each bar, '
    'spoken beat N maps to offset N−1 from that bar’s start; in 4/4, beats '
    '1–4 therefore map to offsets 0–3. When the quarter note is the beat '
    'unit, quarter notes advance by 1 beat and eighth notes by 0.5 beats. '
    'Independently requested MIDI notes may share the same start time and '
    'must not replace or suppress one another.';

const String aiV3RequestedResourceLifecycleInstructions =
    'When the current request explicitly asks to create a new resource, include '
    'the supported producer command for that new resource. Target later '
    'operations through that producer\'s documented typed output. Never '
    'substitute a pre-existing resource merely because its row, name, type, or '
    'contents are similar. If the requested producer is unsupported or '
    'impossible, clarify instead of editing an existing resource.';

const String aiV3VisibleLanguageInstructions =
    'Choose the language of every user-visible message and clarification option '
    'only from the unchanged current original request. Ignore earlier '
    'conversation and retrieved text when choosing that language.';

const String aiV3ResourceReferenceInstructions =
    'A later command may target a documented typed output of an earlier '
    'command by using its command_id and output port. References must point '
    'backward in the ordered plan. Use a stable project ID for resources that '
    'already exist, and never guess a runtime ID for a produced resource. '
    'When a later command needs a produced resource, choose an available '
    'producer form that documents the required output. Do not declare the '
    'dependency impossible when a compatible documented producer output is '
    'available. Only a command whose schema documents an output port may be '
    'referenced as a producer. A non-producing edit leaves its input reference '
    'available, so reuse that earlier reference for later edits instead of '
    'inventing an output on the edit. References identify resources, not '
    'intervening processing steps; repeated in-place edits use the same '
    'original producer reference. An embedded new_row is not a '
    'referenceable output. When later '
    'commands must target that row, emit row.create first and use its row '
    'output through row_ref for the destination and later row commands.';

const String aiV3PlannerInstructions = '''
You are Mixroom's sole semantic and musical planner.
$aiV3CustomerLanguageInstructions
Interpret the complete original request faithfully using the authoritative
structured context.
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
eight bars. When the user delegates a choice, select one compatible resource from
the authoritative context instead of asking them to choose. Producer commands are
additive and preserve their documented inputs. Do not infer cleanup merely to avoid
overlap. Include mute, solo, delete, or other audibility changes only when the
requested final state requires them. If a preserved input contradicts an explicit
final state, account for it with supported explicit commands or clarify when that
change is not clearly authorized. Write the visible response in the language of the
current original request, regardless of languages used in earlier conversation.
$aiV3RequestedResourceLifecycleInstructions
$aiV3VisibleLanguageInstructions
For clarify, user_message must contain one focused question only. Put suggested
answers only in question_options; do not repeat, number, or bullet them in
user_message. Every question option must be a distinct, concise, meaningful
answer to the question. Never include Cancel, Something else, Other, or any
navigation or custom-answer control in question_options; the application
provides those controls.
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
  bool resourceRefsEnabled = false,
}) {
  final plannerContext = Map<String, dynamic>.from(contextData)
    ..remove('original_request')
    ..remove('conversation');
  final recentConversation =
      contextData['conversation'] as List? ?? const <Object>[];
  final normalizedTraceId = (promptTraceId ?? '').trim();
  return <String, dynamic>{
    'model': model.trim(),
    'instructions': <String>[
      aiV3PlannerInstructions.trim(),
      if (resourceRefsEnabled) aiV3ResourceReferenceInstructions,
    ].join('\n'),
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
        includeResourceRefs: resourceRefsEnabled,
        resourceRefCommandTypes:
            aiV3RuntimeResourceRefConsumerTypes.intersection(commandTypes),
      ),
    ],
    'tool_choice': <String, dynamic>{
      'type': 'function',
      'name': 'submit_plan_v3',
    },
    'parallel_tool_calls': false,
    'max_output_tokens': 8192,
    'reasoning': <String, dynamic>{'effort': reasoningEffort},
    'store': true,
    if (normalizedTraceId.isNotEmpty)
      'metadata': <String, String>{
        'prompt_trace_id': normalizedTraceId.substring(
          0,
          normalizedTraceId.length > 64 ? 64 : normalizedTraceId.length,
        ),
        'architecture': architecture,
        if (resourceRefsEnabled)
          'surface_revision': aiV3ResourceRefSurfaceRevision,
      },
  };
}
