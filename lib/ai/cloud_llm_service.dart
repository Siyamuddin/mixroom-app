import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mixroom/models/mixing_result.dart';

class LlmResult {
  final String? text; // assistant text (optional)
  final String? toolName;
  final Map<String, dynamic>? toolArgs;

  bool get hasToolCall => toolName != null && toolArgs != null;

  const LlmResult({this.text, this.toolName, this.toolArgs});

  factory LlmResult.text(String text, Map<String, dynamic>? toolArgs) =>
      LlmResult(
          text: text, toolName: 'informational_response', toolArgs: toolArgs);

  factory LlmResult.tool(String toolName, Map<String, dynamic> toolArgs,
          {String? text}) =>
      LlmResult(text: text, toolName: toolName, toolArgs: toolArgs);
}

class CloudLlmService {
  static const _apiUrl = 'https://api.openai.com/v1/responses';

  final String apiKey;
  final String model;

  CloudLlmService({
    required this.apiKey,
    // this.model = 'gpt-5-nano',
    this.model = 'gpt-4.1-mini',
  });

  static const String _systemPrompt = '''
You are AI Co-Producer — an intelligent, on-device DAW mixing collaborator.

You DO NOT directly edit audio.
You CAN apply mix changes by calling tools; the app executes them exactly.

Your job is NOT to “give advice”.
Your job is to intelligently decide WHETHER changes help, WHAT changes help,
and WHEN to apply them.

You operate in THREE MODES:

────────────────────────────────
1) INFORMATIONAL (NO MIX CHANGES)
────────────────────────────────
Use when:
- The user asks what you can do
- The user asks for help or explanation
- The user asks how or why something works
- The user is NOT requesting a mix change

Rules:
- You MUST call the tool `informational_response`
- You MUST NOT call `mix_model_request`
- You MUST NOT ask permission
- Respond with natural text
- You MUST NOT describe or imply any mix changes
- Should be relatively concise and formatted nicely
- You MUST NOT output JSON directly

You MUST NOT mention:
- Track roles (unless user asks, then tell them it can automatically detect what instruments/types of sounds are in the user's project)
- Assigning roles
- Setup or preparation steps

Examples:
• “What does a de-esser do?”
• “Why does my mix feel muddy?”
• “What can you do?” → 
  “I can help with balance, clarity, space, and tone. 
   Tell me what you'd like to change.”

────────────────────────────────
2) DIRECT COMMAND (EXECUTE)
────────────────────────────────
Use when:
- User gives an explicit instruction
- User names a track/row
- User gives numeric or directional intent

Rules:
- ALWAYS call the tool
- mode = "execute"
- NEVER ask permission
- NEVER ask questions
- Obey the user unless it would clearly cause clipping or silence
- You are allowed to consult with the user if their command has no clear action, or if no action has been discussed (or proposed mix has been cancelled; aka no PENDING_MIX_PROPOSAL)
- If the user seems to command you to execute a proposed mix that was discussed previously but there is no PENDING_MIX_PROPOSAL existing in the user prompt history, you may ask user for clarification.

Examples:
• “Turn the vocals up”
• “Pan track 3 left”
• “Add reverb to vocals”
• “Cut harshness on the guitar”

────────────────────────────────
3) INTERPRETIVE MIX REQUEST
────────────────────────────────
Use when:
- User expresses a feeling, problem, or goal
- User is vague or exploratory

Rules:
- ALWAYS call the tool
- mode = "execute" if there is a clear set of actions to take
- mode = "propose" ONLY if there's no clear action to execute. otherwise if there is a clear set of actions to execute, set mode = "execute"

When a user describes a spatial or textural quality (e.g. wet, dry, wide, spacey),
you may express that goal using multiple compatible intents
with different confidence levels.

Examples:
• “The vocals don't sit right”
• “The mix feels boxy”
• “Can you make this sound more professional?”

EXCEPTION: if there is a clear set of options to execute, then you may proceed without proposing it. You do not need to ask for permission in this case.
- Do NOT respond to user with yes/no questions. Only propose if there are more than 1 option.

────────────────────────────────
INFORMATIONAL OVERRIDE RULE
────────────────────────────────
If the user asks to:
- describe changes
- explain what was done
- explain technically
- analyze the mix
- summarize previous actions
- explain parameters, frequencies, loudness, or metrics

You MUST:
- Use the tool `informational_response`
- NOT call `mix_model_request`
- NOT propose or execute changes
- NOT ask permission
- Respond purely with explanation

────────────────────────────────
AMBIGUITY RULE (CRITICAL)
────────────────────────────────
If a user gives a clear response and there's a clear action (ONLY ONE OR ONE SET OF ACTIONS), then proceed directly (mode = "execute") to an action without asking more questions.

ONLY if a user request could map to actions that could be conflicting, you may propose all of them and not execute changes yet.
In this case, you can describe the options or ask a brief clarifying question if needed using informational_response.

Example: User: “Put effects on the vocals”
→ Ask which effects they want before making changes.

After they give a clear response, do not ask for permission, simply execute (without using propose, just execute).

Overall you should be concise and succinct, only asking for more clarification when absolutely necessary. 
It's better to execute actions if there's a clear option (be biased towards executing immediately rather than asking first)..

CONFIDENCE DOMINANCE RULE:
If one track has meaningfully higher confidence for a referenced role
than all others (≈0.15 or greater),
treat that track as the intended target unless the user specifies otherwise.
This rule OVERRIDES plural wording unless the user explicitly requests multiple tracks.

MOST IMPORTANT AMBIGUITY RULE:
If the user's prompt is vague on what the targeted row should be:
-If the request describes a MIX QUALITY or GLOBAL FEEL
  (e.g. “make it louder”, “add space”, “clean things up”),
  you may apply changes globally to all tracks containing audio (indicated per track by isEmpty = false).
-If the request references an INSTRUMENT, ROLE, or SOUND SOURCE
  (e.g. “guitar”, “vocals”, “bass”),
  you MUST attempt to resolve a single most plausible target track first.
  -If there is no plausible target track, you may so say to the user via informational_response
-Apply changes to multiple tracks ONLY when:
  - multiple tracks are comparably plausible targets
  - AND the edit is reversible and subtle
-There should be NO INSTANCE in which you output a null "role" or row_index = -1. These are absolutely and completely unacceptable. You must be confident in your output.

────────────────────────────────
MULTI-TRACK EXECUTION RULE (MANDATORY)
────────────────────────────────
When a user request applies to multiple tracks and your engine does not support global targets:
-You MUST emit one mix_model_request with an action per track
-You MUST NOT omit a track that has isEmpty = false

Multi-track execution MUST NOT be triggered solely by shared role labels.

If a project has N tracks with isEmpty = false AND the inferred scope is GLOBAL,
you MUST put N actions in the single mix_model_request call.


This rule OVERRIDES conciseness, repetition, and brevity guidelines.

────────────────────────────────
INTENT SCOPE RESOLUTION (CRITICAL)
────────────────────────────────
When a user references an instrument or role:

Infer the intended scope:
• SINGLE-TRACK
• MULTI-TRACK (CATEGORY)
• GLOBAL

Rules:
• Default to SINGLE-TRACK when one track is clearly dominant
• Allow MULTI-TRACK only when multiple tracks are comparably plausible
• Do NOT infer GLOBAL when an instrument or role is mentioned
• Do NOT base scope solely on singular vs plural wording
• MULTI-TRACK applies only to tracks sharing the referenced role, not to all tracks
• Set target.scope to:
  - "master" for overall/master-bus/finishing requests
  - "row" for explicit track- or role-targeted requests
  - "auto" when scope should be inferred by the local planner

────────────────────────────────
CORE MIXING INTELLIGENCE RULES
────────────────────────────────
You MUST reason like a real mix engineer.

• Loudness is relative — consider masking and overlap
• Vocals should usually dominate midrange clarity
• Bass and kick must not fight — reduce overlap before boosting
• Harshness often lives in upper mids / highs
• Mud often lives in low mids
• If something already sounds balanced, say so
• Sometimes the best move is NO MOVE

You are allowed to:
- Disagree with the user
- Suggest fixing a different element than requested
- Propose no-op if changes would not help
- Consult with user if their request is unclear/vague, or if no action has been discussed (or proposed mix has been cancelled; aka no PENDING_MIX_PROPOSAL)

Perceptual goals often require multiple subtle actions.
For example:
• “Wet” or “spacey” usually involves reverb AND a small amount of delay
• “Dry” usually involves reducing ambience effects
• “Wide” may involve panning AND ambience
• In general, it is good to add a Compressor at the end of the chain if there is high dynamic variance in the track
• Usually, for chain order, it is good to put dynamic effects first (Distortion, Compressor) and then Delay, and then Reverb
• Delay should usually be before reverb, not the other way around
• Drums should generally only have a small amount of Delay, try to put the mix knob low in those cases
• EQ is fine at the front and back (usually not put in the middle of a chain)

────────────────────────────────
TRACK ROLES & CONFIDENCE
────────────────────────────────
Tracks may represent different musical roles over time.

Track roles are given to you as a probability vector which are in order of the top 3 most likely instrument/roles of the track.
The track will likely be the first option, but it has a chance to be inaccurate or incorrect.
Be open to the possibility that a track's role can be just one, a combination of many roles, or none of the roles in the probability vector.
If an entry in the vector contains "other", you don't have to mention it to the user. If the "other" is the most likely role, then you may communicate that the role is likely something else, like the other ones in the vector.

Note that the Project Snapshot will also contain the file names of each audio file in a track.
There is a chance that the file name associated with the audio track is an accurate representation of the role/instrument.
If the user prompts with language that potentially references this file name, you may assume that the user refers to this audio file's track.
An example is: A track has a file name called "synth" but contains maybe drums. Another track has a nondescript file name but likely contains synths. If the user mentions synth, they could be referring to the one with the file name "synth".
Basically, factor in the file name as part of your judgment of what track/row the user intends to change.

Some tracks are consistent.
Some tracks contain different roles in different sections.
Some tracks contain overlapping roles, which may limit how aggressively they can be mixed.

If a track contains overlapping roles:
- Be conservative
- Warn briefly if it limits mix decisions
- Avoid heavy processing unless explicitly commanded

If a role is explicitly clarified by the user:
- Treat it as authoritative for this session

────────────────────────────────
AVAILABLE MIX TOOLS (STRICT)
────────────────────────────────
You may ONLY influence the mix via these concepts:

• Gain (track level)
• Pan (track position)
• Reverb (insert / adjust / delete)
• EQ (insert / adjust / delete)
  - 3 Fixed bands (low | mid | high)
  - Gain-only per band
• Delay (insert / adjust / delete)
• Distortion (insert / adjust / delete)
• De-Esser (insert / adjust / delete)
• Compressor (insert / adjust / delete)
• Limiter (insert / adjust / delete)

DO NOT invent sidechains or automation.

Numeric decisions are handled locally.
You describe INTENT, not numbers.

────────────────────────────────
TOOL OUTPUT FORMAT (MANDATORY)
────────────────────────────────
When calling a tool:
- Output ONLY valid JSON arguments for that tool
- Do NOT output JSON as a normal assistant message

Top-level structure:

{
  "mode": "execute" | "propose",
  "assistant_message": "optional natural language message (in past tense if an execute action is being described)",
  "asks_permission": true | false,
  "goal": { ... }
}

────────────────────────────────
MULTI-ACTION OUTPUT RULE (CRITICAL)
────────────────────────────────
When a user request requires multiple mix actions:

• You MUST emit exactly ONE `mix_model_request`
• That `mix_model_request` MUST contain:
  - ONE `assistant_message`
  - ONE array field called `actions`
• Each item in `actions` represents a single mix goal
• You MUST NOT emit multiple `mix_model_request` tool calls
• You MUST NOT include `assistant_message` inside individual actions

The assistant_message should describe the OVERALL change, not each individual action.
The `assistant_message` is a narration of the combined result.
It must be written once, at the top level, and in the user's language.

────────────────────────────────
PENDING PROPOSAL MODE
────────────────────────────────
If a mix proposal is pending (if there is PENDING_MIX_PROPOSAL, otherwise you can ignore this section of instructions):

• You may explain, clarify, or modify the proposal
• You may cancel it if the user rejects it
• You MUST NOT apply changes unless the user clearly agrees

Approval MUST result in:
- mode = "execute"

If the user asks questions:
- Use informational_response
- Do NOT apply or propose changes

If the user *cancels or rejects* the pending proposal:
- IGNORE the PENDING_MIX_PROPOSAL
- Use informational_response
- Set cancels_pending = true
- Do not propose or execute changes
- You must forget about the proposal after it is cancelled, erase it from your memory
- If a user tries to accept or proceed with proposal after it is cancelled (there is no PENDING_MIX_PROPOSAL) in your history, then do not execute since there is nothing to execute

────────────────────────────────
GOAL FORMAT (MANDATORY)
────────────────────────────────
{
  "type": "mix_request",

  "intents": [
    {
      "kind": "gain | pan | eq | reverb | delay | distortion | deesser | compressor | limiter | balance",
      "direction": "up | down | left | right | center | widen | narrow | remove | null",
      "descriptor": "muddy | boxy | harsh | bright | thin | dull | boomy | sibilant | null",
      "confidence": 0.0 to 1.0
    }
  ],

  "target": {
    "row_index": number | null,
    "role": "vocals | drums | bass | guitar | synth | null",
    "scope": "auto | row | master",
    "confidence": 0.0 to 1.0
  },

  "intensity": 0.0 to 1.0

  "reset_fx": true | false
}

RESET RULE
Set "reset_fx": true ONLY if:
-style preset is requested or,
-one-button mix is requested or,
-user explicitly asks to “reset”, “remix”, or “start fresh”
-it should be done when the user has requested some broad-level changes and it would be better for the fx chain to be started from
scratch because there may be many things on it already.
Never set reset_fx for small mix tweaks

────────────────────────────────
ROW INDEXING RULE (EXTREMELY CRITICAL)
────────────────────────────────
When referring to tracks/rows, assume the user speaks in 1-indexed track numbers (Track 1 = first track).
Any row_index you output must correspond to the user-facing track number.
Internally, rows should be 0-indexed (Track 0 = first track).
Note that the rows in PROJECT_SNAPSHOT are 1-indexed. So "Track 2" should be understood as row_index 1.
When outputting row_index, you MUST 0-index. (Example: action intended for Track 4 in the PROJECT_SNAPSHOT => row_index: 3)

────────────────────────────────
CANONICAL INTENTS (NO ENGLISH)
────────────────────────────────
When using mix_model_request, you MUST express intent using canonical tokens only.

Allowed kinds:
- gain
- pan
- eq
- reverb
- delay
- distortion
- deesser
- compressor
- limiter
- balance

Allowed directions (or null):
- up
- down
- left
- right
- center
- widen
- narrow
- remove
- null

CRITICAL EQ DESCRIPTOR SELECTION RULE

EQ descriptors MUST be selected based on the desired ACTION, not on the sound source, frequency region, or instrument name.

NEVER choose a descriptor because it "matches" a word like bass, highs, lows, boom, or brightness.

If the intent is to ADD or INCREASE something, any *_cut descriptor is likely INVALID.
If the intent is to REDUCE or CONTROL something, any *_boost descriptor is likely INVALID.
If applying the chosen EQ descriptor would move the sound in the opposite direction of the user's stated goal, the descriptor is wrong and MUST be replaced with a compatible one or set to null.

Allowed EQ descriptors (or null):
- mud_cut: Reduce low-mid buildup to create more clarity and separation between overlapping instruments.
- box_cut: Remove hollow or enclosed midrange energy to make the sound feel more open and natural.
- boom_cut: Tighten and control excessive low-frequency energy so the low end feels focused and controlled.
- harsh_cut: Smooth aggressive upper-mid or high-frequency energy to make the sound less fatiguing.
- presence_boost: Push the sound forward in the mix so it cuts through and feels more immediate.
- air_boost: Add high-frequency openness and sheen to make the sound feel brighter and more spacious.
- warmth_boost: Add low-mid body and richness to make the sound feel fuller and more grounded.
- thin_fix: Increase perceived weight and density so the sound feels stronger and less weak.
- dull_fix: Restore clarity and brightness so the sound feels more alive and articulate.
- low_cut: Remove unnecessary low-frequency energy to clean up the mix and improve headroom.
- high_cut: Reduce excessive high-frequency content to soften the tone and reduce distraction.
- null: Make no tonal change; EQ is not needed to achieve the desired outcome.

Allowed non-EQ descriptors:
- null only

IMPORTANT:
- NEVER output descriptive English words as descriptors
- DO NOT invent new descriptors
- If unsure, prefer descriptor=null over guessing

Translate user language into canonical descriptors.

Examples:
- "make guitar brighter" → kind="eq", descriptor="presence_boost"
- "reduce harshness" → kind="eq", descriptor="harsh_cut"
- "muddy" → kind="eq", descriptor="mud_cut"
- "thin" → kind="eq", descriptor="thin_fix"


────────────────────────────────
MIX REQUEST SAFETY
────────────────────────────────
Only call mix_model_request when the user is clearly asking
for a mix change or describing a mix problem.

Greetings, small talk, or general questions MUST NOT
trigger mix_model_request.

────────────────────────────────
IDLE / ACKNOWLEDGEMENT RULE (CRITICAL)
────────────────────────────────
If the user message is a greeting, acknowledgement, filler, or non-intent phrase
(e.g. "hi", "hello", "hey", "ok", "cool", "thanks"):

• You MUST NOT analyze the mix
• You MUST NOT infer mix problems
• You MUST NOT propose or apply changes
• You MUST use informational_response only
• Respond briefly and neutrally

This rule OVERRIDES all other mixing behavior.

────────────────────────────────
IMPORTANT CONSTRAINTS
────────────────────────────────
• NEVER output raw plugin parameters
• NEVER mention internal heuristics
• NEVER hallucinate audio problems
• NEVER contradict yourself mid-response
• NEVER apply changes without a tool call

If no changes will help:
- Say so clearly
- Do NOT call the tool

- Also, you are not expected to be able to "undo" or "redo" actions. The user can do that on the app through the undo/redo buttons on the bottom playbar controls.

You are a professional mixing collaborator — not a chatbot.

────────────────────────────────
RESPONSE STYLE (VERY IMPORTANT)
────────────────────────────────
• Prefer bullet points over paragraphs
• Never exceed ~6 lines unless explicitly asked
• Avoid repeating project analysis verbosely
• Use short, confident sentences
• If nothing can be done, say so briefly

Bad:
“Based on the analysis of your project…”

Good:
“I can assist with:
• Balance
• Clarity
• Space
• Tone”

[EXTREMELY IMPORTANT]
If the user prompts in a language other than English, please respond (assistant_message) in the same language as best you can.
Even when doing a mix_model_request, the assistant_message inside should be in the user's prompted language.
Of course, any fields other than the assistant_message should be in English.

────────────────────────────────
LANGUAGE CONSTRAINTS (CRITICAL)
────────────────────────────────
You are part of the DAW, not an onboarding assistant.

When responding:
- Do NOT explain how the system works
- Do NOT describe prerequisites or setup steps
- Do NOT tell the user to assign roles, label tracks, or prepare anything
- Do NOT mention internal capabilities unless explicitly asked

Never say things like:
- “I automatically understand…”
- “Once you assign roles…”
- “Add clips and assign roles to get started”
- “The system analyzes…”

Instead:
- Speak as if the system is already active
- Focus only on what can be changed or improved
- Use natural, implicit language
- If an action has been executed as part of your response, it is better to use past tense ("Applied...") rather than present tense ("Applying...") when describing the action

FINAL LANGUAGE RULE (ABSOLUTE)
The assistant_message MUST be written in the same language as the User's most recent message (at the very *bottom* of the chat history).
If it is not, the response is INVALID. If unclear what the used language is, then prefer to stick to English.

''';

  Future<LlmResult> send({
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    MixingResult? pendingMix,
  }) async {
    if (apiKey.trim().isEmpty) {
      return LlmResult.text(
        'AI is not configured. Launch with --dart-define=OPENAI_API_KEY=YOUR_KEY.',
        null,
      );
    }

    final body = {
      'model': model,
      'temperature': 0.2,
      'instructions': _systemPrompt,
      'input': [
        ...conversation
            .map((m) => {'role': m['role'], 'content': m['content']}),
        {'role': 'user', 'content': 'PROJECT_SNAPSHOT:\n$projectSnapshot'},
        if (pendingMix != null)
          {
            'role': 'user',
            'content': '''
              PENDING_MIX_PROPOSAL:
              ${jsonEncode(pendingMix.toJson())}

              A mix proposal was previously discussed in the chat at some point.
              You may refer to this if it is relevant to the discussion at this current point.
              If it is not relevant, please ignore this.
              ''',
          },
        {'role': 'user', 'content': userText},
      ],
      // 'tools': [
      //   {
      //     'type': 'function',
      //     'name': 'informational_response',
      //     'parameters': {
      //       'type': 'object',
      //       'properties': {
      //         'message': {'type': 'string', 'description': 'Pure informational response. No mix changes.'}
      //       },
      //       'required': ['message'],
      //     },
      //   },
      //   {
      //     'type': 'function',
      //     'name': 'mix_model_request',
      //     'parameters': {
      //       'type': 'object',
      //       'properties': {
      //         'mode': {
      //           'type': 'string',
      //           'enum': ['execute', 'propose']
      //         },
      //         'assistant_message': {'type': 'string'},
      //         'asks_permission': {'type': 'boolean'},
      //         'goal': {
      //           'type': 'object',
      //           'properties': {
      //             'type': {'type': 'string'},
      //             'intents': {
      //               'type': 'array',
      //               'items': {
      //                 'type': 'object',
      //                 'properties': {
      //                   'kind': {'type': 'string'},
      //                   'direction': {'type': 'string'},
      //                   'descriptor': {'type': 'string'},
      //                   'confidence': {'type': 'number'},
      //                 },
      //                 'required': ['kind', 'confidence'],
      //               }
      //             },
      //             'target': {
      //               'type': 'object',
      //               'properties': {
      //                 'role': {'type': 'string'},
      //                 'row_index': {'type': 'integer'},
      //                 'confidence': {'type': 'number'},
      //               },
      //               'required': ['confidence'],
      //             },
      //             'intensity': {'type': 'number'},
      //           },
      //           'required': ['type', 'intents', 'target', 'intensity'],
      //         },
      //       },
      //       'required': ['mode', 'goal'],
      //     },
      //   },
      // ],
      'tools': [
        {
          'type': 'function',
          'name': 'informational_response',
          'parameters': {
            'type': 'object',
            'properties': {
              'message': {
                'type': 'string',
                'description': 'Pure informational response. No mix changes.'
              },
              'cancels_pending': {
                'type': 'boolean',
                'description': 'Whether a pending mix is canceled or rejected.'
              },
            },
            'required': ['message', 'cancels_pending'],
          },
        },
        /*
        {
          'type': 'function',
          'name': 'mix_model_request',
          'parameters': {
            'type': 'object',
            'properties': {
              'mode': {
                'type': 'string',
                'enum': ['execute', 'propose']
              },
              'assistant_message': {'type': 'string'},
              'asks_permission': {
                'type': 'boolean'
              }, // CONSIDER REMOVING THIS, SHOULD ONLY ASK PERMISSION FOR MULTIPLE OPTION REQUESTS
              'goal': {
                'type': 'object',
                'properties': {
                  'type': {'type': 'string'},
                  'intents': {
                    'type': 'array',
                    'items': {
                      'type': 'object',
                      'properties': {
                        'kind': {
                          'type': 'string',
                          'enum': [
                            'gain',
                            'pan',
                            'eq',
                            'reverb',
                            'delay',
                            'distortion',
                            'deesser',
                            'compressor',
                            'balance'
                          ]
                        },
                        'direction': {
                          'type': 'string',
                          'enum': ['up', 'down', 'left', 'right', 'center', 'widen', 'narrow', 'remove', 'null']
                        },
                        'descriptor': {
                          'type': 'string',
                          'enum': [
                            'mud_cut',
                            'box_cut',
                            'boom_cut',
                            'harsh_cut',
                            'presence_boost',
                            'air_boost',
                            'warmth_boost',
                            'thin_fix',
                            'dull_fix',
                            'low_cut',
                            'high_cut',
                            'null'
                          ]
                        },
                        'confidence': {'type': 'number'},
                      },
                      'required': ['kind', 'confidence'],
                    }
                  },
                  'target': {
                    'type': 'object',
                    'properties': {
                      'role': {'type': 'string'},
                      'row_index': {'type': 'integer'},
                      'confidence': {'type': 'number'},
                    },
                    'required': ['confidence'],
                  },
                  'intensity': {'type': 'number'},
                },
                'required': ['type', 'intents', 'target', 'intensity'],
              },
            },
            'required': ['mode', 'goal'],
          },
        },
        */
        {
          'type': 'function',
          'name': 'mix_model_request',
          'parameters': {
            'type': 'object',
            'properties': {
              'mode': {
                'type': 'string',
                'enum': ['execute', 'propose'],
              },
              'assistant_message': {
                'type': 'string',
                'description':
                    'Single unified message describing the overall mix change',
              },
              'asks_permission': {'type': 'boolean'},
              'actions': {
                'type': 'array',
                'description': 'List of mix actions to apply',
                'items': {
                  'type': 'object',
                  'properties': {
                    'goal': {
                      'type': 'object',
                      'properties': {
                        'type': {'type': 'string'},
                        'intents': {
                          'type': 'array',
                          'items': {
                            'type': 'object',
                            'properties': {
                              'kind': {
                                'type': 'string',
                                'enum': [
                                  'gain',
                                  'pan',
                                  'eq',
                                  'reverb',
                                  'delay',
                                  'distortion',
                                  'deesser',
                                  'compressor',
                                  'limiter',
                                  'balance',
                                ],
                              },
                              'direction': {
                                'type': 'string',
                                'enum': [
                                  'up',
                                  'down',
                                  'left',
                                  'right',
                                  'center',
                                  'widen',
                                  'narrow',
                                  'remove',
                                  'null'
                                ],
                              },
                              'descriptor': {
                                'type': 'string',
                                'enum': [
                                  'mud_cut',
                                  'box_cut',
                                  'boom_cut',
                                  'harsh_cut',
                                  'presence_boost',
                                  'air_boost',
                                  'warmth_boost',
                                  'thin_fix',
                                  'dull_fix',
                                  'low_cut',
                                  'high_cut',
                                  'null',
                                ],
                              },
                              'confidence': {'type': 'number'},
                            },
                            'required': ['kind', 'confidence'],
                          },
                        },
                        'target': {
                          'type': 'object',
                          'properties': {
                            'role': {'type': 'string'},
                            'row_index': {'type': 'integer'},
                            'scope': {
                              'type': 'string',
                              'enum': ['auto', 'row', 'master']
                            },
                            'confidence': {'type': 'number'},
                          },
                          'required': ['confidence'],
                        },
                        'intensity': {'type': 'number'},
                        'reset_fx': {'type': 'boolean'},
                      },
                      'required': ['type', 'intents', 'target', 'intensity'],
                    },
                  },
                  'required': ['goal'],
                },
              },
            },
            'required': ['mode', 'actions'],
          },
        },
      ],

      'tool_choice': 'required',

      // 'tool_choice': {
      //   'type': 'function',
      //   'name': 'mix_model_request',
      // },
    };

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json'
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      // print(response.statusCode);
      // print(response.body);
      // throw Exception('LLM error: ${response.body}');
      // return LlmResult.text('LLM error: ${response.body}');
      return LlmResult.text(
          'There has been an error, please try again in a moment.', null);
    }

    final json = jsonDecode(response.body);
    final outputs = (json['output'] as List<dynamic>? ?? const []);

    print("LLM output: $outputs");

    // LlmResult? toolResult;
    final List<LlmResult> toolResults = [];
    String? assistantText;

    for (final o in outputs) {
      final type = o['type'];

      if (type == 'function_call') {
        final name = o['name'] as String?;
        if (name == null) continue;

        final argsRaw = o['arguments'];
        final Map<String, dynamic> args = argsRaw is String
            ? jsonDecode(argsRaw)
            : Map<String, dynamic>.from(argsRaw);

        if (name == 'informational_response') {
          return LlmResult.text(args['message']?.toString() ?? '', args);
        }

        if (name == 'mix_model_request') {
          return LlmResult.tool(name, args, text: args['assistant_message']);
        }
      }

      // 2️⃣ Message outputs
      if (type == 'message') {
        final content = o['content'];
        if (content is! List) continue;

        for (final c in content) {
          if (c is! Map || c['type'] != 'output_text') continue;

          final text = c['text'];

          // ✅ CRITICAL FIX:
          // If the model emitted a structured object, treat it as a tool call
          if (text is Map<String, dynamic>) {
            toolResults.add(LlmResult.tool(
                'mix_model_request', Map<String, dynamic>.from(text)));
            continue;
          }

          // Normal assistant text
          if (text is String &&
              text.trim().isNotEmpty &&
              assistantText == null) {
            assistantText = text.trim();
          }
        }
      }
    }

    if (toolResults.isNotEmpty) {
      return LlmResult.tool(
        toolResults.first.toolName!,
        {'calls': toolResults.map((t) => t.toolArgs).toList()},
        text: assistantText, // may be null — that's OK
      );
    }

    // Only reach here if NO tool-like structure existed
    if (assistantText != null) {
      return LlmResult.text(assistantText, null);
    }

    return LlmResult.text("I'm not sure how to respond.", null);
  }
}

// import 'dart:convert';
// import 'package:http/http.dart' as http;

// import '../models/project_state.dart';

// class LlmResult {
//   final String? text; // assistant text (optional)
//   final String? toolName;
//   final Map<String, dynamic>? toolArgs;

//   bool get hasToolCall => toolName != null && toolArgs != null;

//   const LlmResult({this.text, this.toolName, this.toolArgs});

//   factory LlmResult.text(String text) => LlmResult(text: text);

//   factory LlmResult.tool(String toolName, Map<String, dynamic> toolArgs, {String? text}) =>
//       LlmResult(text: text, toolName: toolName, toolArgs: toolArgs);
// }

// class CloudLlmService {
//   static const _apiUrl = 'https://api.openai.com/v1/responses';
//   static const _model = 'gpt-4.1-mini';

//   /// 🔐 DO NOT hardcode in production
//   // static const String _apiKey = String.fromEnvironment(
//   //     '<set-via-dart-define>');

//   static const String _apiKey =
//       '<set-via-dart-define>';
//   static const String _systemPrompt = r'''
// You are MixAssistant, an on-device DAW mixing helper.

// You do NOT edit audio files directly or generate any new content.
// You CAN apply mix changes inside the app via the app's mix engine.

// AVAILABLE CONTROLS (FULL TOOLBOX):
// - Track gain
// - Track pan
// - Insert/adjust/delete Mixroom Reverb on a track (params: Room Size, Mix)
// - Insert/adjust/delete Mixroom EQ on a track (params: HPF Frequency, Band 1 Gain, Band 2 Gain, Band 3 Gain, Band 4 Gain, LPF Frequency)
// - Insert/adjust/delete Mixroom Delay on a track (params: Delay Time, Feedback, Mix)
// - Insert/adjust/delete De-Esser on a track (params include: Threshold, Frequency, Attack, Release, Stereo, Wide Band)
// - Insert/adjust/delete Distortion on a track (if present)

// No compressor is available.

// You handle 3 input types:

// 1) INFORMATIONAL:
// - reply in plain text only
// - DO NOT call tools

// 2) DIRECT COMMANDS:
// Examples: "Turn Track 2 up", "Pan guitar left", "Remove reverb from vocals"
// - Call tool "mix_model_request"
// - mode="execute"
// - do NOT ask permission

// 3) OPEN-ENDED / INTERPRETIVE:
// Examples: "Make it more professional", "Clean up the mix"
// - Call tool "mix_model_request"
// - mode="propose"
// - include assistant_message asking permission

// INTENTS:
// Each intent includes: kind, direction, descriptor (optional), confidence

// SUPPORTED kind:
// gain, pan, reverb, eq, delay, distortion, deesser, balance, tone

// SUPPORTED direction:
// up, down, left, right, center, widen, narrow, add, remove

// TARGET:
// If user mentions "Track N" or "Row N", set target.row_index (0-based).
// Otherwise set target.role if you can.

// TOOL OUTPUT:
// Return ONLY a function call to mix_model_request with:
// {
//   "mode": "execute" | "propose",
//   "assistant_message": "optional",
//   "goal": {
//     "type": "mix_request",
//     "intents": [...],
//     "target": { "role": "...", "row_index": 0, "confidence": 0..1 },
//     "intensity": 0..1
//   }
// }
// ''';

//   Future<LlmResult> send({
//     required List<Map<String, String>> conversation,
//     required String userText,
//     required String projectSnapshot,
//   }) async {
//     final body = {
//       'model': _model,
//       'temperature': 0.2,
//       'instructions': _systemPrompt,
//       'input': [
//         ...conversation.map((m) => {
//               'role': m['role'],
//               'content': m['content'],
//             }),
//         {
//           'role': 'user',
//           'content': 'PROJECT_SNAPSHOT:\n$projectSnapshot',
//         },
//         {'role': 'user', 'content': userText},
//       ],
//       'tools': [
//         {
//           'type': 'function',
//           'name': 'mix_model_request',
//           'parameters': {
//             'type': 'object',
//             'properties': {
//               'mode': {
//                 'type': 'string',
//                 'enum': ['execute', 'propose']
//               },
//               'assistant_message': {'type': 'string'},
//               'goal': {
//                 'type': 'object',
//                 'properties': {
//                   'type': {'type': 'string'},
//                   'intents': {
//                     'type': 'array',
//                     'items': {
//                       'type': 'object',
//                       'properties': {
//                         'kind': {'type': 'string'},
//                         'direction': {'type': 'string'},
//                         'descriptor': {'type': 'string'},
//                         'confidence': {'type': 'number'},
//                       },
//                       'required': ['kind', 'confidence'],
//                     }
//                   },
//                   'target': {
//                     'type': 'object',
//                     'properties': {
//                       'role': {'type': 'string'},
//                       'row_index': {'type': 'integer'},
//                       'confidence': {'type': 'number'},
//                     },
//                     'required': ['confidence'],
//                   },
//                   'intensity': {'type': 'number'},
//                 },
//                 'required': ['type', 'intents', 'target', 'intensity'],
//               },
//             },
//             'required': ['mode', 'goal'],
//           },
//         },
//       ],
//     };

//     final response = await http.post(
//       Uri.parse(_apiUrl),
//       headers: {
//         'Authorization': 'Bearer $_apiKey',
//         'Content-Type': 'application/json',
//       },
//       body: jsonEncode(body),
//     );

//     if (response.statusCode != 200) {
//       throw Exception('LLM error: ${response.body}');
//     }
//     final json = jsonDecode(response.body);
//     final outputs = json['output'] as List<dynamic>;
//     print(outputs);

//     LlmResult? toolResult;
//     String? userMessage;

//     for (final o in outputs) {
//       final type = o['type'];

//       // ✅ Case 1: REAL structured function call
//       if (type == 'function_call') {
//         final name = o['name'] as String?;
//         final argsRaw = o['arguments'];

//         final Map<String, dynamic> args = argsRaw is String
//             ? (jsonDecode(argsRaw) as Map<String, dynamic>)
//             : Map<String, dynamic>.from(argsRaw as Map);

//         toolResult = LlmResult.tool(name!, args);
//         continue;
//       }

//       // ✅ Case 2: normal assistant message (may contain JSON tool payload as text)
//       if (type == 'message') {
//         final content = o['content'];
//         if (content is! List) continue;

//         for (final c in content) {
//           if (c is! Map) continue;

//           final cType = c['type'];
//           if (cType != 'output_text') continue;

//           final text = c['text'];
//           if (text is! String) continue;

//           // Try parse embedded tool JSON
//           final embeddedTool = _tryParseEmbeddedToolJson(text);
//           if (embeddedTool != null) {
//             toolResult = embeddedTool;
//           } else {
//             // Keep the last human-facing message (often comes after tool call)
//             userMessage = text;
//           }
//         }
//       }
//     }

// // Prefer tool call if present (your pipeline expects this)
//     if (toolResult != null) return toolResult;

// // Otherwise show message text
//     if (userMessage != null) return LlmResult.text(userMessage);

//     return LlmResult.text("I'm not sure how to respond.");
//   }
// }

// LlmResult? _tryParseEmbeddedToolJson(String text) {
//   try {
//     final decoded = jsonDecode(text);
//     if (decoded is Map && decoded['tool'] is String && decoded['goal'] is Map) {
//       // Return toolName + toolArgs in the same shape your pipeline expects
//       return LlmResult.tool(
//         decoded['tool'] as String,
//         Map<String, dynamic>.from(decoded),
//       );
//     }
//   } catch (_) {}
//   return null;
// }
