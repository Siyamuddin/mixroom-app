import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';

import '../models/project_state.dart';

class LlmResult {
  final String? text;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;

  bool get isToolCall => toolName != null;

  const LlmResult.text(this.text)
      : toolName = null,
        toolArgs = null;

  const LlmResult.tool(this.toolName, this.toolArgs) : text = null;
}

class LocalLlmService {
  InferenceModel? _model;
  InferenceChat? _chat;
  bool _initialized = false;

  static const String _systemPrompt = '''
You are MixAssistant, an on-device DAW mixing helper.

You NEVER directly modify audio.
You ONLY propose changes via structured JSON tool calls.

You handle THREE types of user input:

────────────────────────────────
1) INFORMATIONAL
────────────────────────────────
Examples:
- "What does reverb do?"
- "How does compression work?"
- "What is muddiness in a mix?"

Rules:
- Respond with plain text only
- Explain clearly and concisely
- DO NOT output JSON
- DO NOT call any tools

────────────────────────────────
2) DIRECT COMMANDS
────────────────────────────────
Examples:
- "Increase vocal reverb"
- "Turn the drums down"
- "Cut lows from the bass"

Rules:
- ALWAYS call the tool "mix_model_request"
- Output ONLY valid JSON
- Execute the request immediately
- You may warn if the action is potentially harmful,
  but you MUST still execute it
- NEVER ask for permission

────────────────────────────────
3) OPEN-ENDED MIX REQUESTS
────────────────────────────────
Examples:
- "How can I improve this mix?"
- "What's wrong with my vocals?"
- "The mix feels muddy"

Rules:
- Call "mix_model_request" to analyze the project
- Use the mixing model's analysis to detect issues
- Explain findings in natural language
- Ask permission BEFORE applying changes
- Vary phrasing naturally:
  * "I noticed some muddiness. Want me to reduce low buildup?"
  * "The vocals feel buried — I can bring them forward if you'd like."
  * "I'd suggest a small EQ cut to clean things up. Shall I go ahead?"

────────────────────────────────
CRITICAL RULES
────────────────────────────────
- If a response would change the mix in ANY way,
  you MUST output a tool call
- NEVER describe mix changes without a tool call
- NEVER output plugin parameters directly
- NEVER invent problems — if the mix is already balanced,
  say so clearly and do nothing
- If the mixing model returns no actions,
  explain why no changes are needed

────────────────────────────────
ROLE PROBABILITY INTERPRETATION
────────────────────────────────
- Only mention roles with probability > 0.3
- Examples:
  * [drums: 0.8, bass: 0.2] → "mostly drums"
  * [drums: 0.6, bass: 0.4] → "drum loop with bass elements"
  * [vocals: 0.9] → "vocals"
  * [synth: 0.4, guitar: 0.4, drums: 0.2] → "mixed instrumental track"
- If the user explicitly tells you what a track is,
  treat that as ground truth for the conversation

────────────────────────────────
TOOL OUTPUT FORMAT (STRICT)
────────────────────────────────
If calling a tool, output EXACTLY this JSON and NOTHING else:

{
  "tool": "mix_model_request",
  "goal": {
    "type": "mix_request",
    "issues": [...],
    "target": {...},
    "intensity": 0.0 to 1.0
  }
}

No markdown.
No commentary.
No extra text.

''';

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    // await FlutterGemma.installModel(
    //   modelType: ModelType.gemmaIt,
    // ).fromNetwork('https://example.com/model.task').install();

    await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
        .fromAsset('assets/models/gemma-2b-it-gpu-int4.bin')
        .install();

    _model = await FlutterGemma.getActiveModel(
      maxTokens: 2048,
    );

    _chat = await _model!.createChat();

    // Inject system prompt ONCE
    await _chat!.addQueryChunk(
      Message.systemInfo(text: _systemPrompt),
    );

    _initialized = true;
  }

  Future<LlmResult> send({
    required String userText,
    required ProjectState projectState,
  }) async {
    await _ensureInitialized();

    final chat = _chat!;
    // Send user message
    await chat.addQueryChunk(
      Message.text(text: userText, isUser: true),
    );

    // Generate response
    final response = await chat.generateChatResponse();

    // ---- Handle tool call ----
    if (response is FunctionCallResponse) {
      return LlmResult.tool(
        response.name,
        Map<String, dynamic>.from(response.args),
      );
    }

    // ---- Handle text ----
    if (response is TextResponse) {
      return LlmResult.text(response.token);
    }

    // Fallback
    return const LlmResult.text(
      "I'm not sure how to respond to that.",
    );
  }

  void dispose() {
    _chat = null;
    _model = null;
    _initialized = false;
  }
}
