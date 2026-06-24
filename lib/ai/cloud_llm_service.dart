import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/models/mixing_result.dart';

import 'package:mixroom/ai/ai_debug.dart';
import 'package:mixroom/ai/assistant_action_utils.dart';
import 'package:mixroom/ai/debug_system_prompt.dart';

class AiPromptRateLimitWindow {
  final int used;
  final int limit;
  final int remaining;
  final DateTime? resetsAt;

  const AiPromptRateLimitWindow({
    required this.used,
    required this.limit,
    required this.remaining,
    required this.resetsAt,
  });

  double get remainingFraction {
    if (limit <= 0) return remaining > 0 ? 1.0 : 0.0;
    return (remaining / limit).clamp(0.0, 1.0).toDouble();
  }

  int get remainingPercent => (remainingFraction * 100).round();

  factory AiPromptRateLimitWindow.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    final resetsAtRaw = data['resets_at']?.toString().trim() ?? '';
    return AiPromptRateLimitWindow(
      used: (data['used'] as num?)?.toInt() ?? 0,
      limit: (data['limit'] as num?)?.toInt() ?? 0,
      remaining: (data['remaining'] as num?)?.toInt() ?? 0,
      resetsAt: resetsAtRaw.isEmpty ? null : DateTime.tryParse(resetsAtRaw),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'used': used,
      'limit': limit,
      'remaining': remaining,
      if (resetsAt != null) 'resets_at': resetsAt!.toIso8601String(),
    };
  }
}

class AiPromptBankStatus {
  final int remaining;
  final bool consumedFirst;

  const AiPromptBankStatus({
    required this.remaining,
    required this.consumedFirst,
  });

  bool get available => remaining > 0;

  factory AiPromptBankStatus.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return AiPromptBankStatus(
      remaining: (data['remaining'] as num?)?.toInt() ?? 0,
      consumedFirst: data['consumed_first'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'remaining': remaining,
      'consumed_first': consumedFirst,
    };
  }
}

class AiPromptRateLimitStatus {
  final AiPromptRateLimitWindow daily;
  final AiPromptRateLimitWindow weekly;
  final AiPromptBankStatus extraPromptBank;
  final bool canSubmit;
  final String blockedBy;

  const AiPromptRateLimitStatus({
    required this.daily,
    required this.weekly,
    required this.extraPromptBank,
    required this.canSubmit,
    required this.blockedBy,
  });

  bool get isBlocked => !canSubmit;

  DateTime? get blockedResetAt {
    switch (blockedBy) {
      case 'weekly_prompts':
        return weekly.resetsAt;
      case 'daily_prompts':
        return daily.resetsAt;
      default:
        return null;
    }
  }

  factory AiPromptRateLimitStatus.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return AiPromptRateLimitStatus(
      daily: AiPromptRateLimitWindow.fromJson(
        (data['daily'] as Map?)?.cast<String, dynamic>(),
      ),
      weekly: AiPromptRateLimitWindow.fromJson(
        (data['weekly'] as Map?)?.cast<String, dynamic>(),
      ),
      extraPromptBank: AiPromptBankStatus.fromJson(
        (data['extra_prompt_bank'] as Map?)?.cast<String, dynamic>(),
      ),
      canSubmit: data['can_submit'] != false,
      blockedBy: data['blocked_by']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'daily': daily.toJson(),
      'weekly': weekly.toJson(),
      'extra_prompt_bank': extraPromptBank.toJson(),
      'can_submit': canSubmit,
      'blocked_by': blockedBy,
    };
  }
}

class LlmResult {
  final String? text; // assistant text (optional)
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
  final Map<String, dynamic>? meta;

  bool get hasToolCall => toolName != null && toolArgs != null;

  const LlmResult({this.text, this.toolName, this.toolArgs, this.meta});

  factory LlmResult.text(
    String text,
    Map<String, dynamic>? toolArgs, {
    Map<String, dynamic>? meta,
  }) =>
      LlmResult(
        text: text,
        toolName: 'informational_response',
        toolArgs: toolArgs,
        meta: meta,
      );

  factory LlmResult.tool(String toolName, Map<String, dynamic> toolArgs,
          {String? text, Map<String, dynamic>? meta}) =>
      LlmResult(
        text: text,
        toolName: toolName,
        toolArgs: toolArgs,
        meta: meta,
      );
}

class CloudLlmService {
  static const _apiUrl = 'https://api.openai.com/v1/responses';
  static const _promptCacheVersion = 'mixroom-daw-v20260422a';
  static const _directOpenAiMaxOutputTokens = 8192;
  static const _defaultPromptCacheRetention = 'in_memory';
  static const _recoverableAuthMessage =
      "I couldn't reach the AI service just now. Please try again in a moment.";
  static const _temporaryFailureMessage =
      "I couldn't complete that request just now. Please try again in a moment.";
  static const Set<String> _extendedPromptCacheRetentionModels = {
    'gpt-4.1',
    'gpt-5',
    'gpt-5-codex',
    'gpt-5.1',
    'gpt-5.1-codex',
    'gpt-5.1-codex-mini',
    'gpt-5.1-chat-latest',
    'gpt-5.2',
    'gpt-5.4-mini',
  };

  final String apiKey;
  final String model;
  final String proxyApiBaseUrl;
  final String proxyPath;
  final Future<String?> Function()? authTokenProvider;
  final Future<String?> Function()? refreshAuthTokenProvider;
  final Duration requestTimeout;
  final http.Client _httpClient;

  CloudLlmService({
    this.apiKey = '',
    this.model = '',
    this.proxyApiBaseUrl = '',
    this.proxyPath = '/v1/llm/responses',
    this.authTokenProvider,
    this.refreshAuthTokenProvider,
    this.requestTimeout = const Duration(seconds: 25),
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  bool get _supportsTemperature => !model.toLowerCase().startsWith('gpt-5');
  Map<String, dynamic>? get _defaultReasoning {
    final effort = _defaultReasoningEffort(model);
    return effort.isEmpty ? null : <String, dynamic>{'effort': effort};
  }

  String _promptCacheKeyForFeature(
    String aiFeature, {
    String? capabilitySignature,
  }) {
    final normalizedFeature =
        aiFeature.trim().isEmpty ? 'ai_chat' : aiFeature.trim();
    final normalizedCapabilities = (capabilitySignature ?? '').trim().isEmpty
        ? 'legacy'
        : capabilitySignature!.trim();
    final capabilityHash = crypto.sha256
        .convert(utf8.encode(normalizedCapabilities))
        .toString()
        .substring(0, 12);
    return '$_promptCacheVersion:$normalizedFeature:$capabilityHash';
  }

  String get _promptCacheRetention =>
      _extendedPromptCacheRetentionModels.contains(model.trim().toLowerCase())
          ? '24h'
          : _defaultPromptCacheRetention;
  bool get _canUseDirectOpenAi =>
      apiKey.trim().isNotEmpty && model.trim().isNotEmpty;
  bool get _isProxyEnabled => proxyApiBaseUrl.trim().isNotEmpty;
  bool get _isUsingDebugSystemPrompt =>
      kDebugMode && kDebugSystemPrompt.trim().isNotEmpty;
  String get _llmRouteLabel => _isProxyEnabled
      ? 'llm_proxy'
      : (_canUseDirectOpenAi ? 'direct_openai' : 'unconfigured');
  String get _promptSourceLabel {
    if (_isProxyEnabled) {
      return 'llm_proxy_system_prompt';
    }
    if (_isUsingDebugSystemPrompt) {
      return 'kDebugSystemPrompt_plus_client_overrides';
    }
    return 'missing_direct_openai_prompt';
  }

  String get _effectiveSystemPrompt {
    final debugPrompt = kDebugMode ? kDebugSystemPrompt.trim() : '';
    return debugPrompt;
  }

  static const Set<String> _knownClientCapabilities = <String>{
    'daw.project_edit.set_tempo',
    'daw.sample_insert.library',
    'daw.midi_compose.instrument_insert',
    'daw.midi_compose.transpose_notes',
    'daw.midi_compose.audio_to_midi',
  };

  Map<String, dynamic> _mergedAnalyticsClientContext(
    Map<String, dynamic> clientContext,
  ) {
    final requestContext = AnalyticsService.instance.buildRequestContext();
    final analyticsClientContext =
        (requestContext['client_context'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    return <String, dynamic>{
      ...analyticsClientContext,
      ...clientContext,
    };
  }

  Set<String> _readClientCapabilities(Map<String, dynamic> clientContext) {
    final rawCapabilities = clientContext['ai_capabilities'];
    if (rawCapabilities is! List) return <String>{};
    return rawCapabilities
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) =>
            value.isNotEmpty && _knownClientCapabilities.contains(value))
        .toSet();
  }

  List<String> _readStringList(dynamic value, {int maxItems = 80}) {
    if (value is! List) return const <String>[];
    final normalized = <String>[];
    final seen = <String>{};
    for (final raw in value) {
      if (raw is! String) continue;
      final item = raw.trim();
      if (item.isEmpty || !seen.add(item)) continue;
      normalized.add(item);
      if (normalized.length >= maxItems) break;
    }
    return normalized;
  }

  int? _readNonNegativeInt(dynamic value) {
    if (value is bool) return null;
    if (value is int) return value >= 0 ? value : null;
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      return parsed != null && parsed >= 0 ? parsed : null;
    }
    return null;
  }

  Map<String, dynamic> _readClientPolicy(Map<String, dynamic> clientContext) {
    final policy = <String, dynamic>{};
    for (final key in <String>[
      'subscription_plan',
      'plugin_access',
      'row_creation_policy',
    ]) {
      final value = clientContext[key];
      if (value is String && value.trim().isNotEmpty) {
        final trimmed = value.trim();
        policy[key] =
            trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed;
      }
    }

    for (final key in <String>['max_rows', 'current_rows']) {
      final parsed = _readNonNegativeInt(clientContext[key]);
      if (parsed != null) policy[key] = parsed;
    }

    final allowedEffects =
        _readStringList(clientContext['allowed_builtin_effects']);
    if (allowedEffects.isNotEmpty) {
      policy['allowed_builtin_effects'] = allowedEffects;
    }

    final allowedInstruments =
        _readStringList(clientContext['allowed_instrument_ids']);
    if (allowedInstruments.isNotEmpty) {
      policy['allowed_instrument_ids'] = allowedInstruments;
    }

    return policy;
  }

  List<String> _clientPolicyPromptLines(Map<String, dynamic> clientPolicy) {
    if (clientPolicy.isEmpty) return const <String>[];
    final lines = <String>['', 'CLIENT ENTITLEMENT POLICY'];
    final subscriptionPlan =
        clientPolicy['subscription_plan']?.toString().trim() ?? '';
    final pluginAccess = clientPolicy['plugin_access']?.toString().trim() ?? '';
    final rowCreationPolicy =
        clientPolicy['row_creation_policy']?.toString().trim() ?? '';
    final maxRows = clientPolicy['max_rows'];
    final currentRows = clientPolicy['current_rows'];
    final allowedEffects = clientPolicy['allowed_builtin_effects'];
    final allowedInstruments = clientPolicy['allowed_instrument_ids'];

    if (subscriptionPlan.isNotEmpty) {
      lines.add('- Current subscription plan: $subscriptionPlan.');
    }
    if (maxRows is int) {
      var rowLine =
          '- Maximum project row_index is ${maxRows - 1}; do not emit actions targeting row_index >= $maxRows.';
      if (currentRows is int) {
        rowLine += ' Current row count is $currentRows.';
      }
      lines.add(rowLine);
    }
    if (rowCreationPolicy.isNotEmpty) {
      lines.add('- Row creation policy: $rowCreationPolicy');
    }
    if (pluginAccess.isNotEmpty) {
      lines.add('- Plugin access: $pluginAccess.');
    }
    if (allowedEffects is List && allowedEffects.isNotEmpty) {
      lines.add(
        '- Effect/plugin actions may only add or target these built-in effects unless the client explicitly allows all plugins: ${allowedEffects.join(', ')}.',
      );
    }
    if (allowedInstruments is List && allowedInstruments.isNotEmpty) {
      lines.add(
        '- New MIDI/instrument actions may only use instrument_id values present in LIBRARY_SNAPSHOT and in this allowed list: ${allowedInstruments.join(', ')}.',
      );
    }
    return lines;
  }

  String _buildDirectSystemPrompt(
    Set<String> clientCapabilities,
    Map<String, dynamic> clientPolicy,
  ) {
    final lines = <String>[
      _effectiveSystemPrompt,
      '',
      'CLIENT CAPABILITY OVERRIDES',
      '- LIBRARY_SNAPSHOT lists the packaged instrument IDs and packaged sample-library paths this client may use.',
      '- LIBRARY_SNAPSHOT may be compact: instruments may be grouped by category, and sample folders may appear as `Folder: [fileA, fileB]`. In that case the exact library_path is `Folder/fileName`.',
      '- LIBRARY_SNAPSHOT may include library_role_hints such as kick, snare, hat, clap, loop, bass, or fx. Use those semantic groups first when choosing packaged drum samples.',
      '- If a request can be satisfied using a packaged instrument ID or packaged sample path from LIBRARY_SNAPSHOT, do not treat it as unsupported generation.',
      ..._clientPolicyPromptLines(clientPolicy),
    ];
    if (clientCapabilities.contains('daw.project_edit.set_tempo')) {
      lines.add(
        '- This client supports project_edit set_tempo for direct BPM/project tempo changes. For requests like "make the song faster/slower", include time_stretch_audio=true and preserve_pitch=true so existing audio follows the new tempo. For grid/metronome-only BPM edits, omit or set time_stretch_audio=false.',
      );
    } else {
      lines.add('- This client does not support project_edit set_tempo.');
    }
    if (clientCapabilities.contains('daw.sample_insert.library')) {
      lines.add(
        '- This client supports sample_insert using exact library_path values or role aliases like role:kick from LIBRARY_SNAPSHOT.',
      );
    } else {
      lines.add(
        '- This client does not support AI sample/library insertion; do not emit sample_insert.',
      );
    }
    if (clientCapabilities.contains('daw.midi_compose.instrument_insert')) {
      lines.add(
        '- This client supports creating a new MIDI clip on a packaged built-in instrument by using midi_compose with instrument_id from LIBRARY_SNAPSHOT plus valid notes/progression.',
      );
    } else {
      lines.add(
        '- This client may only use midi_compose on an existing editable MIDI/instrument target.',
      );
    }
    if (clientCapabilities.contains('daw.midi_compose.transpose_notes')) {
      lines.add('- This client supports midi_compose transpose_notes.');
    } else {
      lines.add('- This client does not support midi_compose transpose_notes.');
    }
    if (clientCapabilities.contains('daw.midi_compose.audio_to_midi')) {
      lines.add(
        '- This client supports midi_compose convert_audio_to_midi for transcribing an existing project audio clip into a new MIDI clip below it.',
      );
    } else {
      lines.add(
        '- This client does not support audio-to-MIDI transcription; do not emit midi_compose convert_audio_to_midi.',
      );
    }
    return lines.join('\n').trim();
  }

  String _clientCapabilitySignature(Set<String> capabilities) {
    if (capabilities.isEmpty) return 'legacy';
    final sorted = capabilities.toList()..sort();
    return sorted.join(',');
  }

  String _stableJsonEncode(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_stableJsonEncode(value[key])}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_stableJsonEncode).join(',')}]';
    }
    return jsonEncode(value);
  }

  String _clientPolicySignature(Map<String, dynamic> policy) {
    if (policy.isEmpty) return 'default_policy';
    return _stableJsonEncode(policy);
  }

  String _defaultReasoningEffort(String modelName) {
    final normalized = modelName.trim().toLowerCase();
    if (normalized.startsWith('gpt-5.4-mini')) {
      return 'low';
    }
    if (normalized.startsWith('gpt-5-pro') ||
        normalized.startsWith('gpt-5.2-pro') ||
        normalized.startsWith('gpt-5.4-pro')) {
      return 'high';
    }
    if (normalized.startsWith('gpt-5.4') ||
        normalized.startsWith('gpt-5.2') ||
        normalized.startsWith('gpt-5.1')) {
      return 'none';
    }
    if (normalized.startsWith('gpt-5')) {
      return 'minimal';
    }
    return '';
  }

  List<Map<String, dynamic>> _buildInputMessages({
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    required String selectionSnapshot,
    required String librarySnapshot,
    MixingResult? pendingMix,
  }) {
    return [
      {'role': 'user', 'content': 'PROJECT_SNAPSHOT:\n$projectSnapshot'},
      if (selectionSnapshot.trim().isNotEmpty)
        {
          'role': 'user',
          'content': 'SELECTION_SNAPSHOT:\n$selectionSnapshot',
        },
      if (librarySnapshot.trim().isNotEmpty)
        {
          'role': 'user',
          'content': 'LIBRARY_SNAPSHOT:\n$librarySnapshot',
        },
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
      ...conversation.map((m) => {'role': m['role'], 'content': m['content']}),
      {'role': 'user', 'content': userText},
    ];
  }

  Map<String, dynamic> _dawTargetSchema({
    bool allowMasterScope = false,
  }) {
    final scopeValues = <String>[
      'selected',
      'all_audio',
      'all',
      'group',
      if (allowMasterScope) 'master',
    ];
    return <String, dynamic>{
      'type': 'object',
      'description':
          'Target reference for the DAW action. Use existing project context and selection to fill what you already know. Resolve relative references like top/bottom/first/last row or line into an explicit row_index when the intended row is clear, preferring occupied-row context over empty rows. Resolve natural identity references using labels, filenames, instrument names or IDs, clip kind, and row/source cues from the snapshots. Use prefer_selected only for explicit selection references such as "this one", "that one", "here", or "selected".',
      'properties': <String, dynamic>{
        'clip_index': {
          'type': 'integer',
          'minimum': 0,
        },
        'clip_indices': {
          'type': 'array',
          'items': {
            'type': 'integer',
            'minimum': 0,
          },
          'minItems': 1,
        },
        'row_index': {
          'type': 'integer',
          'minimum': 0,
        },
        'scope': {
          'type': 'string',
          'enum': scopeValues,
        },
        'group_id': {'type': 'string'},
        'group_name': {'type': 'string'},
        'prefer_selected': {
          'type': 'boolean',
          'description':
              'Use when the user refers to the current selection with phrases like "this one", "that one", or "here".',
        },
        'automation_target_id': {'type': 'string'},
        'target_id': {'type': 'string'},
        'lane_id': {'type': 'string'},
        'effect_index': {
          'type': 'integer',
          'minimum': 0,
        },
        'effect_name': {'type': 'string'},
        'plugin_name': {'type': 'string'},
        'effect_name_contains': {'type': 'string'},
        'param_id': {'type': 'string'},
        'param_name': {'type': 'string'},
      },
      'additionalProperties': true,
    };
  }

  Map<String, dynamic> _midiNoteSchema() => <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'pitch': {
            'type': 'integer',
            'minimum': 0,
            'maximum': 127,
            'description':
                'MIDI note number, for example 60 for middle C. Do not use note names like C4.',
          },
          'start_beat': {
            'type': 'number',
            'description':
                'Zero-based start beat in the clip. Measure 1 beat 1 is start_beat 0.',
          },
          'length_beats': {
            'type': 'number',
            'exclusiveMinimum': 0,
            'description': 'Note length in beats.',
          },
          'velocity': {
            'type': 'number',
            'minimum': 0,
            'maximum': 1,
            'description':
                'Normalized velocity from 0 to 1. Do not use 1 to 127 velocity values.',
          },
        },
        'required': ['pitch', 'start_beat', 'length_beats'],
        'additionalProperties': true,
      };

  List<Map<String, dynamic>> _directOpenAiToolSchemas() =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'function',
          'name': 'informational_response',
          'strict': false,
          'description':
              'Use for explanations, summaries, unsupported or unimplemented requests, empty-project replies, and any case where no valid executable action can be formed. Also use this when the user\'s main request depends on unsupported features and a nearby supported tool would be misleading.',
          'parameters': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'message': {
                'type': 'string',
                'description':
                    'Short user-facing response. Also use this for unsupported or not-yet-implemented features.',
              },
              'cancels_pending': {
                'type': 'boolean',
                'description':
                    'True only when the user clearly cancels or rejects a pending mix proposal.',
              },
            },
            'required': ['message', 'cancels_pending'],
            'additionalProperties': false,
          },
        },
        <String, dynamic>{
          'type': 'function',
          'name': 'daw_assistant_actions',
          'strict': false,
          'description':
              'Use for tutorials, project edits like BPM changes, row-group creation/folding, row color changes, library sample insertion or replacement, clip arrangement/editing, plugin CRUD, automation edits such as sidechain-like ducking, auto-pan, stereo movement, or filter sweeps, MIDI composition/editing, stem separation, and role override. For group bus plugin or mix requests, target the existing group with scope=group plus group_id or group_name so the app edits the group bus, not each child row. Use row_group_edit only for creating, removing from, or folding/unfolding row groups. Use clip_edit glue for merge/consolidate/bounce-clip requests. For autotune, auto-tune, pitch correction, or Melodyne-style vocal tuning, add the built-in Pitch Corrector effect. For drum or beat-building requests using packaged samples, prefer action over explanation: choose semantically matching library files or advertised role aliases like role:kick, arrange them with musical spacing, and keep core roles like kick/snare/hats on separate rows when helpful. For 8+ bar starter grooves or build-ups, prefer a workable scaffold with repetition plus light variation or fills instead of one identical bar copied forever. If the user wants a placed sample swapped out, prefer replacing the targeted clips while preserving timing. Inspect existing plugin chains and selected MIDI note state when available: prefer modifying, unbypassing, extending, or reshaping what is already there when it is close, and remove conflicting effects or rewrite notes only when the current state clearly fights the user goal. Never use for pure sonic mix changes. Only emit actions the app can actually execute.',
          'parameters': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'assistant_message': {
                'type': 'string',
                'description':
                    'Short user-facing message in the user language. Must match the emitted action type, must not be a placeholder, and must not switch languages unless the user did.',
              },
              'actions': {
                'type': 'array',
                'minItems': 1,
                'items': {
                  'oneOf': [
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['project_edit'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': ['set_tempo'],
                            },
                            'tempo_bpm': {
                              'type': 'number',
                              'minimum': 20,
                              'maximum': 999,
                            },
                            'bpm': {
                              'type': 'number',
                              'minimum': 20,
                              'maximum': 999,
                            },
                            'time_stretch_audio': {
                              'type': 'boolean',
                              'description':
                                  'True when the user asks to make the song/audio faster or slower. False for grid/metronome-only BPM edits.',
                            },
                            'preserve_pitch': {
                              'type': 'boolean',
                              'description':
                                  'Use true by default for song-speed changes so pitch stays stable.',
                            },
                          },
                          'required': ['operation'],
                          'anyOf': [
                            {
                              'required': ['tempo_bpm'],
                            },
                            {
                              'required': ['bpm'],
                            },
                          ],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['row_color_edit'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': ['set', 'clear'],
                            },
                            'target': _dawTargetSchema(),
                            'row_indices': {
                              'type': 'array',
                              'items': {
                                'type': 'integer',
                                'minimum': 0,
                              },
                              'minItems': 1,
                            },
                            'track_indices': {
                              'type': 'array',
                              'items': {
                                'type': 'integer',
                                'minimum': 0,
                              },
                              'minItems': 1,
                            },
                            'color': {
                              'type': 'integer',
                              'minimum': 0,
                            },
                            'argb': {
                              'type': 'integer',
                              'minimum': 0,
                            },
                            'color_name': {'type': 'string'},
                            'group_id': {'type': 'string'},
                            'group_name': {'type': 'string'},
                          },
                          'required': ['operation'],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['row_group_edit'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': [
                                'create',
                                'remove_row',
                                'toggle_collapsed',
                              ],
                            },
                            'target': _dawTargetSchema(),
                            'row_indices': {
                              'type': 'array',
                              'items': {
                                'type': 'integer',
                                'minimum': 0,
                              },
                              'minItems': 1,
                            },
                            'track_indices': {
                              'type': 'array',
                              'items': {
                                'type': 'integer',
                                'minimum': 0,
                              },
                              'minItems': 1,
                            },
                            'rows': {
                              'type': 'array',
                              'items': {
                                'type': 'integer',
                                'minimum': 0,
                              },
                              'minItems': 1,
                            },
                            'group_id': {'type': 'string'},
                            'group_name': {'type': 'string'},
                            'name': {'type': 'string'},
                            'color': {
                              'type': 'integer',
                              'minimum': 0,
                            },
                          },
                          'required': ['operation'],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['audio_enhance'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': ['phone_mic_cleanup'],
                            },
                            'target': _dawTargetSchema(),
                          },
                          'required': ['operation', 'target'],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['sample_insert'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': [
                                'insert_audio_clips',
                                'replace_audio_clips',
                              ],
                            },
                            'items': {
                              'type': 'array',
                              'minItems': 1,
                              'items': {
                                'type': 'object',
                                'properties': {
                                  'library_path': {'type': 'string'},
                                  'target': _dawTargetSchema(),
                                  'row_index': {
                                    'type': 'integer',
                                    'minimum': 0,
                                  },
                                  'start_ms': {'type': 'number'},
                                  'start_measure': {'type': 'number'},
                                  'start_beat': {'type': 'number'},
                                  'repeat_count': {
                                    'type': 'integer',
                                    'minimum': 1,
                                  },
                                  'length_ms': {'type': 'number'},
                                  'length_measures': {'type': 'number'},
                                  'length_beats': {'type': 'number'},
                                  'until_ms': {'type': 'number'},
                                  'until_measure': {'type': 'number'},
                                  'until_beat': {'type': 'number'},
                                  'step_ms': {'type': 'number'},
                                  'step_measures': {'type': 'number'},
                                  'step_beats': {'type': 'number'},
                                  'delta_rows': {
                                    'type': 'integer',
                                  },
                                },
                                'required': ['library_path'],
                                'additionalProperties': true,
                              },
                            },
                          },
                          'required': ['operation', 'items'],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['tutorial'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'topic': {'type': 'string'},
                            'steps': {
                              'type': 'array',
                              'minItems': 1,
                              'items': {
                                'type': 'object',
                                'properties': {
                                  'text': {'type': 'string'},
                                  'target_id': {'type': 'string'},
                                },
                                'required': ['text'],
                                'additionalProperties': true,
                              },
                            },
                          },
                          'anyOf': [
                            {
                              'required': ['topic'],
                            },
                            {
                              'required': ['steps'],
                            },
                          ],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['clarify'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'question': {'type': 'string'},
                            'options': {
                              'type': 'array',
                              'items': {'type': 'string'},
                              'minItems': 2,
                            },
                          },
                          'required': ['question', 'options'],
                          'additionalProperties': false,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['clip_edit'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': [
                                'trim',
                                'auto_trim',
                                'cut',
                                'stretch',
                                'pitch_shift',
                                'glue',
                                'move',
                                'tempo_follow',
                                'auto_bpm_align',
                                'align_first_sound',
                                'tempo_detect_set_project',
                                'duplicate',
                                'delete',
                                'dialog_cleanup',
                                'dialog_remove_range',
                                'dialog_tighten_pauses',
                                'dialog_lift_quiet',
                              ],
                            },
                            'target': _dawTargetSchema(),
                            'trim_side': {
                              'type': 'string',
                              'enum': ['start', 'end'],
                            },
                            'new_start_ms': {'type': 'number'},
                            'target_ms': {'type': 'number'},
                            'align_to_ms': {'type': 'number'},
                            'first_sound_target_ms': {'type': 'number'},
                            'align_to': {
                              'type': 'string',
                              'enum': [
                                'playhead',
                                'nearest_beat',
                                'nearest_bar',
                                'bar',
                                'beat',
                                'project_start',
                                'clip_start',
                              ],
                            },
                            'bar_index': {'type': 'number'},
                            'beat_index': {'type': 'number'},
                            'paste_start_ms': {'type': 'number'},
                            'delta_ms': {'type': 'number'},
                            'new_start_measure': {'type': 'number'},
                            'paste_start_measure': {'type': 'number'},
                            'delta_measures': {'type': 'number'},
                            'step_ms': {'type': 'number'},
                            'step_measures': {'type': 'number'},
                            'step_beats': {'type': 'number'},
                            'repeat_count': {
                              'type': 'integer',
                              'minimum': 1,
                            },
                            'length_ms': {'type': 'number'},
                            'length_measures': {'type': 'number'},
                            'length_beats': {'type': 'number'},
                            'semitones': {'type': 'number'},
                            'delta_semitones': {'type': 'number'},
                            'pitch_semitones': {'type': 'number'},
                            'new_pitch_semitones': {'type': 'number'},
                            'mode': {
                              'type': 'string',
                              'enum': ['set', 'delta'],
                            },
                            'until_ms': {'type': 'number'},
                            'until_measure': {'type': 'number'},
                            'until_beat': {'type': 'number'},
                            'direction': {
                              'type': 'string',
                              'enum': ['left', 'right', 'up', 'down'],
                            },
                            'new_row_index': {
                              'type': 'integer',
                              'minimum': 0,
                            },
                            'timeline_duration_ms': {'type': 'number'},
                            'duration_ms': {'type': 'number'},
                            'beats_per_bar': {'type': 'number'},
                            'from_ms': {'type': 'number'},
                            'to_ms': {'type': 'number'},
                            'ranges': {
                              'type': 'array',
                              'items': {
                                'type': 'object',
                                'properties': {
                                  'from_ms': {'type': 'number'},
                                  'to_ms': {'type': 'number'},
                                },
                                'required': ['from_ms', 'to_ms'],
                                'additionalProperties': false,
                              },
                            },
                            'max_edits': {
                              'type': 'integer',
                              'minimum': 1,
                            },
                            'boost_db': {'type': 'number'},
                            'max_gain': {'type': 'number'},
                            'min_quiet_ms': {'type': 'number'},
                            'min_pause_ms': {'type': 'number'},
                            'keep_pause_ms': {'type': 'number'},
                          },
                          'required': ['operation', 'target'],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['effect_edit'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': [
                                'add',
                                'remove',
                                'bypass',
                                'unbypass',
                                'toggle_bypass',
                              ],
                            },
                            'target': _dawTargetSchema(allowMasterScope: true),
                          },
                          'required': ['operation', 'target'],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['automation_edit'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': [
                                'set_points',
                                'add_ramp',
                                'clear',
                                'apply_template',
                              ],
                            },
                            'target': _dawTargetSchema(),
                            'template': {'type': 'string'},
                            'points': {
                              'type': 'array',
                              'minItems': 1,
                              'items': {
                                'type': 'object',
                                'properties': {
                                  'time_ms': {'type': 'number'},
                                  'value': {'type': 'number'},
                                },
                                'required': ['time_ms', 'value'],
                                'additionalProperties': true,
                              },
                            },
                            'start_ms': {'type': 'number'},
                            'length_ms': {'type': 'number'},
                            'delta_ms': {'type': 'number'},
                            'source_clip_index': {
                              'type': 'integer',
                              'minimum': 0,
                            },
                            'source_row_index': {
                              'type': 'integer',
                              'minimum': 0,
                            },
                            'source_role': {'type': 'string'},
                            'min_spacing_ms': {'type': 'number'},
                            'duck_value': {'type': 'number'},
                            'recover_value': {'type': 'number'},
                            'direction': {
                              'type': 'string',
                              'enum': ['left', 'right'],
                            },
                            'from_ms': {'type': 'number'},
                            'to_ms': {'type': 'number'},
                            'start_value': {'type': 'number'},
                            'end_value': {'type': 'number'},
                            'value_mode': {
                              'type': 'string',
                              'enum': ['normalized', 'real'],
                            },
                          },
                          'required': ['operation', 'target'],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['midi_compose'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': [
                                'create_clip',
                                'compose_bassline',
                                'compose_pattern',
                                'replace_notes',
                                'append_notes',
                                'transpose_notes',
                                'convert_audio_to_midi',
                              ],
                            },
                            'target': _dawTargetSchema(),
                            'notes': {
                              'type': 'array',
                              'minItems': 1,
                              'items': _midiNoteSchema(),
                            },
                            'progression': {
                              'oneOf': [
                                {
                                  'type': 'array',
                                  'items': {'type': 'string'},
                                  'minItems': 1,
                                },
                                {
                                  'type': 'string',
                                },
                              ],
                            },
                            'beats_per_chord': {'type': 'number'},
                            'notes_per_chord': {
                              'type': 'integer',
                              'minimum': 1
                            },
                            'octave': {'type': 'integer'},
                            'semitones': {'type': 'number'},
                            'octaves': {'type': 'number'},
                            'instrument_id': {
                              'type': 'string',
                              'description':
                                  'Built-in instrument id from LIBRARY_SNAPSHOT, for example mixroom.sub_bass or mixroom.air_pluck. Use this when creating a new MIDI clip on a packaged instrument. For generic harmony, chord, or piano MIDI requests with no specified instrument, prefer sfz.vsco.upright_piano when it is available in LIBRARY_SNAPSHOT.',
                            },
                            'instrument_name': {'type': 'string'},
                            'start_ms': {'type': 'number'},
                            'create_new_clip': {'type': 'boolean'},
                            'preserve_existing_notes': {'type': 'boolean'},
                          },
                          'required': ['operation', 'target'],
                          'anyOf': [
                            {
                              'required': ['notes'],
                            },
                            {
                              'required': ['progression'],
                            },
                            {
                              'properties': {
                                'operation': {'const': 'transpose_notes'},
                              },
                              'required': ['semitones'],
                            },
                            {
                              'properties': {
                                'operation': {'const': 'transpose_notes'},
                              },
                              'required': ['octaves'],
                            },
                            {
                              'properties': {
                                'operation': {
                                  'const': 'convert_audio_to_midi',
                                },
                              },
                            },
                            {
                              'properties': {
                                'operation': {
                                  'enum': ['replace_notes', 'append_notes'],
                                },
                                'preserve_existing_notes': {'const': true},
                              },
                              'anyOf': [
                                {
                                  'required': ['length_measures'],
                                },
                                {
                                  'required': ['length_beats'],
                                },
                              ],
                            },
                          ],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['midi_compose'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': ['chop_notes'],
                            },
                            'target': _dawTargetSchema(),
                            'subdivision': {
                              'type': 'integer',
                              'minimum': 1,
                            },
                            'velocity_decay_per_slice': {
                              'type': 'number',
                            },
                            'velocity_jitter': {
                              'type': 'number',
                            },
                            'velocity_floor': {
                              'type': 'number',
                            },
                          },
                          'required': ['operation', 'target', 'subdivision'],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['stem_separate'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': ['vocal_instrumental'],
                            },
                            'target': _dawTargetSchema(),
                          },
                          'required': ['operation', 'target'],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['role_override'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': ['set'],
                            },
                            'target': _dawTargetSchema(),
                            'role': {
                              'type': 'string',
                              'enum': [
                                'vocals',
                                'drums',
                                'bass',
                                'guitar',
                                'synth',
                                'other',
                              ],
                            },
                          },
                          'required': ['operation', 'target', 'role'],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['role_override'],
                        },
                        'data': {
                          'type': 'object',
                          'properties': {
                            'operation': {
                              'type': 'string',
                              'enum': ['clear'],
                            },
                            'target': _dawTargetSchema(),
                          },
                          'required': ['operation', 'target'],
                          'additionalProperties': true,
                        },
                      },
                      'required': ['type', 'data'],
                      'additionalProperties': false,
                    },
                  ],
                },
              },
            },
            'required': ['assistant_message', 'actions'],
            'additionalProperties': false,
          },
        },
        <String, dynamic>{
          'type': 'function',
          'name': 'mix_model_request',
          'strict': false,
          'description':
              'Use only for sonic mix changes on existing project material. Never use for clip movement, plugin CRUD, automation edits, MIDI writing, tutorials, stem separation, or unsupported features. Use reset_fx only for true reset/remix cases or when the current chain clearly conflicts with the requested broad vibe.',
          'parameters': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'mode': {
                'type': 'string',
                'enum': ['execute', 'propose'],
                'description':
                    'Use execute for clear actionable mix changes. Use propose only for alternative approaches that need approval.',
              },
              'assistant_message': {
                'type': 'string',
                'description':
                    'Single short user-facing message describing the overall mix action in the user language.',
              },
              'asks_permission': {
                'type': 'boolean',
              },
              'actions': {
                'type': 'array',
                'minItems': 1,
                'description': 'One or more mix actions to apply.',
                'items': {
                  'type': 'object',
                  'properties': {
                    'goal': {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['mix_request'],
                          'description':
                              'Always mix_request. Put the sonic intent in intents[].kind.',
                        },
                        'intents': {
                          'type': 'array',
                          'minItems': 1,
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
                                  'clipper',
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
                          'oneOf': [
                            {
                              'properties': {
                                'scope': {
                                  'type': 'string',
                                  'enum': ['master']
                                },
                                'confidence': {'type': 'number'},
                              },
                              'required': ['scope', 'confidence'],
                              'additionalProperties': false,
                            },
                            {
                              'properties': {
                                'role': {'type': 'string'},
                                'row_index': {
                                  'type': 'integer',
                                  'minimum': 0,
                                },
                                'group_id': {'type': 'string'},
                                'group_name': {'type': 'string'},
                                'scope': {
                                  'type': 'string',
                                  'enum': ['auto', 'row', 'group']
                                },
                                'confidence': {'type': 'number'},
                              },
                              'required': ['scope', 'confidence'],
                              'additionalProperties': false,
                            },
                          ],
                        },
                        'intensity': {'type': 'number'},
                        'execution_profile': {
                          'type': 'string',
                          'enum': [
                            'producer_safe',
                            'creative_bold',
                            'experimental_extreme',
                          ],
                          'description':
                              'How conservative or stylized the mix lane should be. producer_safe = tasteful standard mix decisions, creative_bold = obvious/stylized but still musical, experimental_extreme = intentionally exaggerated or destructive.',
                        },
                        'audibility': {
                          'type': 'string',
                          'enum': [
                            'subtle',
                            'noticeable',
                            'obvious',
                            'extreme',
                          ],
                          'description':
                              'How audible the result should feel to the user, independent of the intent kind.',
                        },
                        'reference_target': {
                          'type': 'object',
                          'oneOf': [
                            {
                              'properties': {
                                'row_index': {
                                  'type': 'integer',
                                  'minimum': 0,
                                },
                                'confidence': {'type': 'number'},
                              },
                              'required': ['row_index', 'confidence'],
                              'additionalProperties': false,
                            },
                            {
                              'properties': {
                                'prefer_selected': {
                                  'type': 'boolean',
                                  'enum': [true]
                                },
                                'confidence': {'type': 'number'},
                              },
                              'required': ['prefer_selected', 'confidence'],
                              'additionalProperties': false,
                            },
                          ],
                          'description':
                              'Optional in-project reference row for mix matching. Use row_index when clear from PROJECT_SNAPSHOT, especially when labels, filenames, coverage, source_type, or reference cues make one row obviously reference-like. Use prefer_selected when the reference track is currently selected.',
                        },
                        'reference_mode': {
                          'type': 'string',
                          'enum': [
                            'tone',
                            'loudness',
                            'width',
                            'glue',
                            'full_mix',
                          ],
                          'description':
                              'Which dimensions of the in-project reference to match. full_mix means broad tone+loudness+width+glue matching.',
                        },
                        'reference_closeness': {
                          'type': 'string',
                          'enum': ['loose', 'balanced', 'close'],
                          'description':
                              'How tightly to chase the in-project reference profile.',
                        },
                        'reset_fx': {
                          'type': 'boolean',
                          'description':
                              'Set true only when a reset/remix or clean rebuild is clearly preferable to tweaking the current chain. Leave false for ordinary incremental mix moves.',
                        },
                      },
                      'required': [
                        'type',
                        'intents',
                        'target',
                        'intensity',
                        'execution_profile',
                        'audibility',
                      ],
                    },
                  },
                  'required': ['goal'],
                },
              },
            },
            'required': ['mode', 'assistant_message', 'actions'],
            'additionalProperties': false,
          },
        },
      ];

  void _filterDirectToolSchemas(
    List<Map<String, dynamic>> tools,
    Set<String> clientCapabilities,
  ) {
    final allowedActionTypes = <String>{
      'tutorial',
      'clarify',
      'clip_edit',
      'effect_edit',
      'row_group_edit',
      'row_color_edit',
      'automation_edit',
      'midi_compose',
      'stem_separate',
      'role_override',
      'audio_enhance',
      if (clientCapabilities.contains('daw.project_edit.set_tempo'))
        'project_edit',
      if (clientCapabilities.contains('daw.sample_insert.library'))
        'sample_insert',
    };

    for (final tool in tools) {
      if (tool['name'] != 'daw_assistant_actions') continue;
      final parameters = tool['parameters'];
      if (parameters is! Map) continue;
      final properties = parameters['properties'];
      if (properties is! Map) continue;
      final actions = properties['actions'];
      if (actions is! Map) continue;
      final items = actions['items'];
      if (items is! Map) continue;

      final itemProperties = items['properties'];
      if (itemProperties is Map) {
        final typeSchema = itemProperties['type'];
        if (typeSchema is Map) {
          typeSchema['enum'] = allowedActionTypes.toList(growable: false);
          return;
        }
      }

      final variants = items['oneOf'];
      if (variants is! List) continue;
      final removedVariants = <dynamic>[];
      for (final variant in variants) {
        if (variant is! Map) {
          removedVariants.add(variant);
          continue;
        }
        final variantProperties = variant['properties'];
        if (variantProperties is! Map) {
          removedVariants.add(variant);
          continue;
        }
        final typeSchema = variantProperties['type'];
        if (typeSchema is! Map) {
          removedVariants.add(variant);
          continue;
        }
        final allowedValues = <String>{};
        final rawEnum = typeSchema['enum'];
        if (rawEnum is List) {
          allowedValues.addAll(
            rawEnum
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty),
          );
        }
        final rawConst = typeSchema['const'];
        if (rawConst != null) {
          final normalizedConst = rawConst.toString().trim();
          if (normalizedConst.isNotEmpty) allowedValues.add(normalizedConst);
        }
        if (!allowedValues.any(allowedActionTypes.contains)) {
          removedVariants.add(variant);
        }
      }
      for (final variant in removedVariants) {
        variants.remove(variant);
      }
      return;
    }
  }

  Map<String, dynamic> _buildOpenAiRequestBody({
    required List<Map<String, dynamic>> inputMessages,
    String? aiFeature,
    Map<String, dynamic> clientContext = const <String, dynamic>{},
  }) {
    final normalizedAiFeature = _normalizeAiFeatureForProxy(aiFeature);
    final clientCapabilities = _readClientCapabilities(clientContext);
    final clientPolicy = _readClientPolicy(clientContext);
    var capabilitySignature = _clientCapabilitySignature(clientCapabilities);
    if (clientPolicy.isNotEmpty) {
      capabilitySignature = [
        capabilitySignature,
        _clientPolicySignature(clientPolicy),
      ].join('|');
    }
    final toolSchemas = _directOpenAiToolSchemas();
    _filterDirectToolSchemas(toolSchemas, clientCapabilities);
    final body = <String, dynamic>{
      'model': model,
      'instructions': _buildDirectSystemPrompt(
        clientCapabilities,
        clientPolicy,
      ),
      'prompt_cache_key': _promptCacheKeyForFeature(
        normalizedAiFeature,
        capabilitySignature: capabilitySignature,
      ),
      'prompt_cache_retention': _promptCacheRetention,
      'input': inputMessages,
      'tools': toolSchemas,
      'tool_choice': 'required',
      'parallel_tool_calls': true,
      'max_output_tokens': _directOpenAiMaxOutputTokens,
    };
    if (_supportsTemperature) {
      body['temperature'] = 0.2;
    }
    final reasoning = _defaultReasoning;
    if (reasoning != null) {
      body['reasoning'] = reasoning;
    }
    return body;
  }

  Map<String, dynamic> _buildProxyRequestBody({
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    required String selectionSnapshot,
    required String librarySnapshot,
    String? promptTraceId,
    String? projectId,
    String? aiFeature,
    MixingResult? pendingMix,
    Map<String, dynamic> clientContext = const <String, dynamic>{},
  }) {
    final normalizedAiFeature = _normalizeAiFeatureForProxy(aiFeature);
    final requestContext = AnalyticsService.instance.buildRequestContext();
    final analyticsClientContext =
        (requestContext['client_context'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    requestContext['client_context'] = <String, dynamic>{
      ...analyticsClientContext,
      ...clientContext,
    };
    return {
      'conversation': conversation
          .map((m) => {
                'role': m['role'],
                'content': m['content'],
              })
          .toList(),
      'user_text': userText,
      'project_snapshot': projectSnapshot,
      if (selectionSnapshot.trim().isNotEmpty)
        'selection_snapshot': selectionSnapshot,
      if (librarySnapshot.trim().isNotEmpty)
        'library_snapshot': librarySnapshot,
      if ((promptTraceId ?? '').trim().isNotEmpty)
        'prompt_trace_id': promptTraceId!.trim(),
      if ((projectId ?? '').trim().isNotEmpty) 'project_id': projectId,
      if (normalizedAiFeature.isNotEmpty) 'ai_feature': normalizedAiFeature,
      if (pendingMix != null) 'pending_mix': pendingMix.toJson(),
      ...requestContext,
    };
  }

  String _normalizeAiFeatureForProxy(String? aiFeature) {
    final value = (aiFeature ?? '').trim();
    if (value.isEmpty) return 'ai_chat';

    switch (value) {
      case 'assistant_chat':
      case 'one_button_mix':
      case 'ai_chat':
        return 'ai_chat';
      default:
        return value;
    }
  }

  Uri _resolveProxyUri({String? pathOverride}) {
    final base = proxyApiBaseUrl.trim();
    final path = (pathOverride ?? proxyPath).trim().isEmpty
        ? '/v1/llm/responses'
        : (pathOverride ?? proxyPath);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }

  Future<String?> _resolveProxyAuthToken({bool forceRefresh = false}) async {
    final primaryProvider =
        forceRefresh ? refreshAuthTokenProvider : authTokenProvider;
    final primaryToken = await primaryProvider?.call();
    final safePrimaryToken = primaryToken?.trim() ?? '';
    if (safePrimaryToken.isNotEmpty) return safePrimaryToken;

    if (!forceRefresh && refreshAuthTokenProvider != null) {
      final refreshedToken = await refreshAuthTokenProvider!.call();
      final safeRefreshedToken = refreshedToken?.trim() ?? '';
      if (safeRefreshedToken.isNotEmpty) return safeRefreshedToken;
    }
    return null;
  }

  Future<http.Response> _postProxyJson({
    required String token,
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    required String selectionSnapshot,
    required String librarySnapshot,
    required String? promptTraceId,
    required String? projectId,
    required String? aiFeature,
    required MixingResult? pendingMix,
    required Map<String, dynamic> clientContext,
  }) {
    return _postJson(
      uri: _resolveProxyUri(),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: _buildProxyRequestBody(
        conversation: conversation,
        userText: userText,
        projectSnapshot: projectSnapshot,
        selectionSnapshot: selectionSnapshot,
        librarySnapshot: librarySnapshot,
        promptTraceId: promptTraceId,
        projectId: projectId,
        aiFeature: aiFeature,
        pendingMix: pendingMix,
        clientContext: clientContext,
      ),
    );
  }

  String _limitsProxyPath() {
    final path = proxyPath.trim().isEmpty ? '/v1/llm/responses' : proxyPath;
    if (path.endsWith('/responses')) {
      return '${path.substring(0, path.length - '/responses'.length)}/limits';
    }
    return '${path.replaceFirst(RegExp(r'/$'), '')}/limits';
  }

  Future<http.Response> _postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    Duration? timeoutOverride,
  }) {
    return _httpClient
        .post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(timeoutOverride ?? requestTimeout);
  }

  void _debugDumpJson(
    String scope,
    String label,
    Object? value, {
    int maxChars = 12000,
  }) {
    if (!kAiDebugLogs || !kAiDebugVerbose) return;
    String encoded;
    try {
      encoded = const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      encoded = value.toString();
    }
    if (encoded.length > maxChars) {
      encoded = '${encoded.substring(0, maxChars)}\n... <truncated>';
    }
    aiDebugBlock(scope, label, encoded);
  }

  void _debugDumpRawBody(
    String scope,
    String label,
    String body, {
    int maxChars = 12000,
  }) {
    if (!kAiDebugLogs || !kAiDebugVerbose) return;
    final trimmed = body.length > maxChars
        ? '${body.substring(0, maxChars)}\n... <truncated>'
        : body;
    aiDebugBlock(scope, label, trimmed);
  }

  Future<http.Response> _getJson({
    required Uri uri,
    required Map<String, String> headers,
  }) {
    return _httpClient.get(uri, headers: headers).timeout(requestTimeout);
  }

  Map<String, dynamic>? _decodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  AiPromptRateLimitStatus? _parsePromptRateLimitStatus(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return AiPromptRateLimitStatus.fromJson(raw);
    }
    if (raw is Map) {
      return AiPromptRateLimitStatus.fromJson(raw.cast<String, dynamic>());
    }
    return null;
  }

  Map<String, dynamic> _buildResponseMeta(
    Map<String, dynamic>? payload,
  ) {
    if (payload == null) return const <String, dynamic>{};
    final status = _parsePromptRateLimitStatus(payload['prompt_rate_limit']);
    final meta = <String, dynamic>{};
    if (status != null) {
      meta['prompt_rate_limit'] = status.toJson();
    }
    final softError = payload['soft_error'];
    if (softError is Map<String, dynamic>) {
      meta['soft_error'] = softError;
    } else if (softError is Map) {
      meta['soft_error'] = softError.cast<String, dynamic>();
    }
    final usage = payload['usage'];
    if (usage is Map<String, dynamic>) {
      meta['usage'] = usage;
      final cachedPromptTokens = _cachedPromptTokensFromUsage(usage);
      if (cachedPromptTokens > 0) {
        meta['cached_prompt_tokens'] = cachedPromptTokens;
      }
    } else if (usage is Map) {
      final normalizedUsage = usage.cast<String, dynamic>();
      meta['usage'] = normalizedUsage;
      final cachedPromptTokens = _cachedPromptTokensFromUsage(normalizedUsage);
      if (cachedPromptTokens > 0) {
        meta['cached_prompt_tokens'] = cachedPromptTokens;
      }
    }
    final observability = payload['observability'];
    if (observability is Map<String, dynamic>) {
      meta['observability'] = observability;
    } else if (observability is Map) {
      meta['observability'] = observability.cast<String, dynamic>();
    }
    final responseId = payload['id']?.toString().trim() ?? '';
    final responseModel = payload['model']?.toString().trim() ?? '';
    if (responseId.isNotEmpty || responseModel.isNotEmpty) {
      meta['observability'] = <String, dynamic>{
        if (meta['observability'] is Map<String, dynamic>)
          ...(meta['observability'] as Map<String, dynamic>),
        if (meta['observability'] is Map)
          ...(meta['observability'] as Map).cast<String, dynamic>(),
        if (responseId.isNotEmpty) 'provider_response_id': responseId,
        if (responseModel.isNotEmpty) 'effective_model': responseModel,
      };
    }
    return meta;
  }

  Map<String, dynamic> _mergeMetaObservability(
    Map<String, dynamic>? meta,
    Map<String, dynamic> localObservability,
  ) {
    final merged = <String, dynamic>{
      if (meta != null) ...meta,
    };
    final existingObservability = merged['observability'];
    final observability = <String, dynamic>{
      if (existingObservability is Map<String, dynamic>)
        ...existingObservability,
      if (existingObservability is Map)
        ...existingObservability.cast<String, dynamic>(),
      ...localObservability,
    };
    merged['observability'] = observability;
    return merged;
  }

  int _cachedPromptTokensFromUsage(Map<String, dynamic> usage) {
    for (final key in const ['input_tokens_details', 'prompt_tokens_details']) {
      final details = usage[key];
      if (details is Map<String, dynamic>) {
        return (details['cached_tokens'] as num?)?.toInt() ?? 0;
      }
      if (details is Map) {
        return (details['cached_tokens'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  String _formatResetCountdown(DateTime? resetsAt) {
    if (resetsAt == null) return '';
    final remaining = resetsAt.toLocal().difference(DateTime.now());
    if (remaining.inSeconds <= 0) return 'a moment';
    if (remaining.inDays >= 1) {
      final hours = remaining.inHours.remainder(24);
      return hours > 0
          ? '${remaining.inDays}d ${hours}h'
          : '${remaining.inDays}d';
    }
    if (remaining.inHours >= 1) {
      final minutes = remaining.inMinutes.remainder(60);
      return minutes > 0
          ? '${remaining.inHours}h ${minutes}m'
          : '${remaining.inHours}h';
    }
    if (remaining.inMinutes >= 1) {
      return '${remaining.inMinutes}m';
    }
    return '${remaining.inSeconds}s';
  }

  String _rateLimitMessage(AiPromptRateLimitStatus? status, String fallback) {
    if (status == null) return fallback;
    final limitLabel =
        status.blockedBy == 'weekly_prompts' ? 'weekly' : 'daily';
    final wait = _formatResetCountdown(status.blockedResetAt);
    if (wait.isEmpty) {
      return 'You have reached the $limitLabel prompt limit. Please try again later.';
    }
    return 'You have reached the $limitLabel prompt limit. Try again in $wait.';
  }

  bool _isPromptRateLimitResponse(
    int statusCode,
    Map<String, dynamic>? payload,
    AiPromptRateLimitStatus? status,
  ) {
    if (statusCode != 429) return false;
    if (status?.isBlocked == true) return true;
    return payload?['error'] == 'prompt_rate_limit_hit';
  }

  LlmResult _recoverableTextResult(
    String message, {
    String? softErrorCode,
    Map<String, dynamic>? meta,
  }) {
    final mergedMeta = <String, dynamic>{
      if (meta != null) ...meta,
      if ((softErrorCode ?? '').trim().isNotEmpty)
        'soft_error': <String, dynamic>{
          'code': softErrorCode!.trim(),
          'usage_refunded': true,
        },
    };
    return LlmResult.text(
      message,
      {
        'message': message,
        'cancels_pending': false,
      },
      meta: mergedMeta,
    );
  }

  Future<AiPromptRateLimitStatus?> fetchPromptRateLimitStatus() async {
    if (!_isProxyEnabled) return null;
    final token = await authTokenProvider?.call();
    if (token == null || token.trim().isEmpty) {
      return null;
    }

    try {
      final response = await _getJson(
        uri: _resolveProxyUri(pathOverride: _limitsProxyPath()),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode != 200) return null;
      final payload = _decodeJsonObject(response.body);
      return _parsePromptRateLimitStatus(payload?['prompt_rate_limit']);
    } catch (_) {
      return null;
    }
  }

  String _fallbackAssistantText(String toolName) {
    switch (toolName) {
      case 'mix_model_request':
        return '';
      case 'daw_assistant_actions':
        return '';
      default:
        return "I couldn't complete that request just now. Please try again.";
    }
  }

  String _invalidToolCallFallbackText(
    String toolName,
    dynamic rawArgs, {
    required String userText,
  }) {
    final decoded = _decodeToolArgs(rawArgs);
    final candidate = decoded == null
        ? ''
        : _sanitizeUserFacingText(
            decoded['assistant_message'] ?? decoded['message'],
            toolName: toolName,
            userText: userText,
            allowFallback: false,
          );
    if (candidate.isNotEmpty) {
      return '$candidate\n\nI understood the intent, but the action payload was incomplete or invalid, so nothing changed.';
    }
    return "I understood the intent, but the action payload was incomplete or invalid, so nothing changed.";
  }

  String _sanitizeUserFacingText(
    Object? value, {
    required String toolName,
    required String userText,
    bool allowFallback = true,
  }) {
    final raw = (value?.toString() ?? '').trim();
    final fallback = _fallbackAssistantText(toolName);
    if (raw.isEmpty) return allowFallback ? fallback : '';

    final lowered = raw.toLowerCase();
    if (_toolTextLeakMarkers.any(lowered.contains) ||
        RegExp(r'\bisempty\s*=\s*(true|false)\b').hasMatch(lowered) ||
        raw.startsWith('{') ||
        raw.startsWith('[')) {
      return allowFallback ? fallback : '';
    }

    return raw;
  }

  static const Set<String> _toolTextLeakMarkers = <String>{
    'mix_model_request',
    'daw_assistant_actions',
    'informational_response',
    '"assistant_message"',
    '"row_index"',
    '"target_id"',
    'project snapshot',
    'selection snapshot',
    'project_snapshot',
    'selection_snapshot',
    'pending_mix_proposal',
    'isempty = true',
    'isempty = false',
    'isempty=true',
    'isempty=false',
    'clip_index',
    'clip_indices',
    'row_index:',
  };

  static const Set<String> _dawAssistantActionTypes = <String>{
    'tutorial',
    'clarify',
    'project_edit',
    'sample_insert',
    'clip_edit',
    'effect_edit',
    'row_group_edit',
    'row_color_edit',
    'automation_edit',
    'midi_compose',
    'stem_separate',
    'role_override',
    'audio_enhance',
  };

  static const Set<String> _allowedClipEditOperations = <String>{
    'trim',
    'auto_trim',
    'cut',
    'stretch',
    'pitch_shift',
    'glue',
    'move',
    'tempo_follow',
    'auto_bpm_align',
    'align_first_sound',
    'tempo_detect_set_project',
    'duplicate',
    'delete',
    'dialog_cleanup',
    'dialog_remove_range',
    'dialog_tighten_pauses',
    'dialog_lift_quiet',
  };

  static const Set<String> _allowedEffectEditOperations = <String>{
    'add',
    'remove',
    'bypass',
    'unbypass',
    'toggle_bypass',
  };

  static const Set<String> _allowedAutomationEditOperations = <String>{
    'set_points',
    'add_ramp',
    'clear',
    'apply_template',
  };

  static const Set<String> _allowedMidiComposeOperations = <String>{
    'create_clip',
    'compose_bassline',
    'compose_pattern',
    'replace_notes',
    'append_notes',
    'chop_notes',
    'transpose_notes',
    'convert_audio_to_midi',
  };

  static const Set<String> _allowedStemSeparateOperations = <String>{
    'vocal_instrumental',
  };

  static const Set<String> _allowedProjectEditOperations = <String>{
    'set_tempo',
  };

  static const Set<String> _allowedSampleInsertOperations = <String>{
    'insert_audio_clips',
    'replace_audio_clips',
  };

  static const Set<String> _allowedRowGroupEditOperations = <String>{
    'create',
    'remove_row',
    'toggle_collapsed',
  };

  static const Set<String> _allowedRowColorEditOperations = <String>{
    'set',
    'clear',
  };

  static const Set<String> _allowedRoleOverrideOperations = <String>{
    'set',
    'clear',
  };

  String _normalizeActionToken(Object? raw) {
    return raw
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _normalizeClipEditOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'split': 'cut',
      'split_clip': 'cut',
      'cut_clip': 'cut',
      'resize': 'stretch',
      'resize_clip': 'stretch',
      'pitch': 'pitch_shift',
      'pitch_clip': 'pitch_shift',
      'pitch_shift_clip': 'pitch_shift',
      'shift_pitch': 'pitch_shift',
      'transpose_audio': 'pitch_shift',
      'transpose_clip': 'pitch_shift',
      'glue_clips': 'glue',
      'merge': 'glue',
      'merge_clip': 'glue',
      'merge_clips': 'glue',
      'consolidate': 'glue',
      'consolidate_clip': 'glue',
      'consolidate_clips': 'glue',
      'bounce_clip': 'glue',
      'bounce_clips': 'glue',
      'move_clip': 'move',
      'reposition': 'move',
      'shift': 'move',
      'nudge': 'move',
      'copy': 'duplicate',
      'copy_clip': 'duplicate',
      'remove': 'delete',
      'remove_clip': 'delete',
      'delete_clip': 'delete',
      'tempo_follow_project': 'tempo_follow',
      'align_tempo': 'auto_bpm_align',
      'align_to_project_tempo': 'auto_bpm_align',
      'align_onset': 'align_first_sound',
      'onset_align': 'align_first_sound',
      'first_sound_align': 'align_first_sound',
      'align_volume_start': 'align_first_sound',
      'align_audio_start': 'align_first_sound',
      'align_to_first_sound': 'align_first_sound',
      'detect_tempo_set_project': 'tempo_detect_set_project',
    };
    return aliases[token] ?? token;
  }

  String _normalizeEffectEditOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'delete': 'remove',
      'delete_effect': 'remove',
      'remove_effect': 'remove',
      'take_out': 'remove',
      'insert': 'add',
      'ensure': 'add',
      'ensure_effect': 'add',
      'add_effect': 'add',
      'insert_effect': 'add',
      'disable': 'bypass',
      'mute': 'bypass',
      'enable': 'unbypass',
      'unmute': 'unbypass',
      'toggle': 'toggle_bypass',
    };
    return aliases[token] ?? token;
  }

  String _normalizeAutomationEditOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'create': 'set_points',
      'create_clip': 'set_points',
      'new_clip': 'set_points',
      'add_clip': 'set_points',
      'insert_clip': 'set_points',
      'set_clip_points': 'set_points',
      'clear_clips': 'clear',
      'delete_clip': 'clear',
      'remove_clip': 'clear',
    };
    return aliases[token] ?? token;
  }

  String _normalizeProjectEditOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'set_bpm': 'set_tempo',
      'change_bpm': 'set_tempo',
      'set_project_bpm': 'set_tempo',
      'change_project_bpm': 'set_tempo',
      'set_project_tempo': 'set_tempo',
      'change_tempo': 'set_tempo',
    };
    return aliases[token] ?? token;
  }

  String _normalizeSampleInsertOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'insert_audio_clip': 'insert_audio_clips',
      'insert_sample': 'insert_audio_clips',
      'insert_samples': 'insert_audio_clips',
      'add_sample': 'insert_audio_clips',
      'add_samples': 'insert_audio_clips',
      'insert_library_audio': 'insert_audio_clips',
      'replace_audio_clip': 'replace_audio_clips',
      'replace_sample': 'replace_audio_clips',
      'replace_samples': 'replace_audio_clips',
      'swap_sample': 'replace_audio_clips',
      'swap_samples': 'replace_audio_clips',
      'swap_audio_clips': 'replace_audio_clips',
      'change_sample': 'replace_audio_clips',
    };
    return aliases[token] ?? token;
  }

  String _normalizeMidiComposeOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'compose': 'compose_pattern',
      'create': 'create_clip',
      'create_clip': 'create_clip',
      'new_clip': 'create_clip',
      'new_midi_clip': 'create_clip',
      'compose_notes': 'compose_pattern',
      'write_pattern': 'compose_pattern',
      'generate_pattern': 'compose_pattern',
      'make_pattern': 'compose_pattern',
      'compose_bass': 'compose_bassline',
      'write_bassline': 'compose_bassline',
      'generate_bassline': 'compose_bassline',
      'make_bassline': 'compose_bassline',
      'replace': 'replace_notes',
      'overwrite_notes': 'replace_notes',
      'set_notes': 'replace_notes',
      'append': 'append_notes',
      'add_notes': 'append_notes',
      'extend_notes': 'append_notes',
      'transpose': 'transpose_notes',
      'transpose_note': 'transpose_notes',
      'transpose_notes': 'transpose_notes',
      'shift_pitch': 'transpose_notes',
      'pitch_shift': 'transpose_notes',
      'octave_up': 'transpose_notes',
      'octave_down': 'transpose_notes',
      'audio_to_midi': 'convert_audio_to_midi',
      'convert_to_midi': 'convert_audio_to_midi',
      'transcribe_audio': 'convert_audio_to_midi',
      'extract_midi': 'convert_audio_to_midi',
      'chop': 'chop_notes',
      'chop_note': 'chop_notes',
      'note_chop': 'chop_notes',
      'note_chopper': 'chop_notes',
      'splice_notes': 'chop_notes',
      'slice_notes': 'chop_notes',
      'split_notes': 'chop_notes',
      'grid_chop': 'chop_notes',
      'ratchet': 'chop_notes',
      'stutter': 'chop_notes',
    };
    return aliases[token] ?? token;
  }

  String _normalizeRoleOverrideOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    if (token == 'remove' || token == 'unset' || token == 'delete') {
      return 'clear';
    }
    return token;
  }

  String _normalizeRowGroupEditOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'group': 'create',
      'group_rows': 'create',
      'create_group': 'create',
      'create_row_group': 'create',
      'make_group': 'create',
      'make_row_group': 'create',
      'ungroup_row': 'remove_row',
      'remove_from_group': 'remove_row',
      'remove_row_from_group': 'remove_row',
      'toggle': 'toggle_collapsed',
      'fold': 'toggle_collapsed',
      'unfold': 'toggle_collapsed',
      'collapse': 'toggle_collapsed',
      'expand': 'toggle_collapsed',
      'toggle_group': 'toggle_collapsed',
      'toggle_row_group': 'toggle_collapsed',
    };
    return aliases[token] ?? token;
  }

  bool _isKnownAutomationTemplate(String templateRaw) {
    final template = templateRaw.trim().toLowerCase();
    return template == 'sidechain' ||
        template == 'sidechain_pump' ||
        template == 'pump' ||
        template == 'sidechain_from_kick' ||
        template == 'kick_sidechain' ||
        template == 'duck_to_kick' ||
        template == 'kick_duck' ||
        template == 'reverb_tail' ||
        template == 'tail' ||
        template == 'decay' ||
        template == 'filter_sweep' ||
        template == 'sweep' ||
        template == 'lowpass_sweep' ||
        template == 'highpass_sweep' ||
        template == 'auto_pan' ||
        template == 'autopan' ||
        template == 'stereo_motion' ||
        template == 'stereo_direction' ||
        template == 'pan_motion' ||
        template == 'left_right_motion';
  }

  Map<String, dynamic> _actionTargetMap(Map<String, dynamic> data) {
    final rawTarget = data['target'];
    if (rawTarget is Map<String, dynamic>) {
      return Map<String, dynamic>.from(rawTarget);
    }
    if (rawTarget is Map) {
      return Map<String, dynamic>.from(rawTarget);
    }
    return <String, dynamic>{};
  }

  bool _hasExplicitDialogRangePayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    final fromMs = _parseActionDouble(data['from_ms'] ?? target['from_ms']);
    final toMs = _parseActionDouble(data['to_ms'] ?? target['to_ms']);
    if (fromMs != null && toMs != null) return true;
    final rawRanges = data['ranges'] ?? target['ranges'];
    if (rawRanges is! List) return false;
    for (final raw in rawRanges) {
      if (raw is! Map) continue;
      final range = Map<String, dynamic>.from(raw);
      final rangeFrom = _parseActionDouble(range['from_ms']);
      final rangeTo = _parseActionDouble(range['to_ms']);
      if (rangeFrom != null && rangeTo != null) return true;
    }
    return false;
  }

  bool _hasExplicitDialogAnchorPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    return _parseActionDouble(data['at_ms'] ?? target['at_ms']) != null ||
        _parseActionDouble(data['time_ms'] ?? target['time_ms']) != null;
  }

  bool _hasCompleteDialogRemoveRangePayload(Map<String, dynamic> data) {
    return _hasExplicitDialogRangePayload(data) ||
        _hasExplicitDialogAnchorPayload(data);
  }

  bool _hasAnyExplicitActionValue(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    final target = _actionTargetMap(data);
    for (final key in keys) {
      final value = data.containsKey(key) ? data[key] : target[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      if (value is List && value.isEmpty) continue;
      return true;
    }
    return false;
  }

  bool _hasMeaningfulMovePayload(Map<String, dynamic> data) {
    if (_hasAnyExplicitActionValue(data, const <String>[
      'new_start_ms',
      'start_ms',
      'paste_start_ms',
      'start_measure',
      'new_start_measure',
      'paste_start_measure',
      'start_bar',
      'new_start_bar',
      'paste_start_bar',
      'start_beat',
      'new_start_beat',
      'paste_start_beat',
    ])) {
      return true;
    }

    if (_hasAnyExplicitActionValue(data, const <String>[
      'direction',
      'move_to',
      'align_to',
    ])) {
      return true;
    }

    final numericKeys = <String>[
      'delta_ms',
      'move_ms',
      'shift_ms',
      'delta_beats',
      'move_beats',
      'shift_beats',
      'delta_measures',
      'move_measures',
      'shift_measures',
      'delta_bars',
      'move_bars',
      'shift_bars',
    ];
    for (final key in numericKeys) {
      final value =
          _parseActionDouble(data[key] ?? _actionTargetMap(data)[key]);
      if (value != null && value.abs() > 1e-9) return true;
    }

    final integerKeys = <String>[
      'row_index',
      'target_row_index',
      'dest_row_index',
      'new_row_index',
      'row',
      'target_row',
      'row_delta',
      'delta_rows',
      'step_rows',
    ];
    for (final key in integerKeys) {
      final value = _parseActionInt(data[key] ?? _actionTargetMap(data)[key]);
      if (value != null) {
        if (key.contains('delta') || key.contains('step')) {
          if (value != 0) return true;
        } else {
          return true;
        }
      }
    }

    return false;
  }

  bool _hasSupportedCutPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    final scope = (target['scope'] ?? data['scope'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (scope == 'all' ||
        scope == 'all_audio' ||
        scope == 'all_selected_audio') {
      return false;
    }
    if (_hasExplicitDialogRangePayload(data)) {
      return false;
    }
    final clipIndices =
        (data['clip_indices'] as List?) ?? (target['clip_indices'] as List?);
    if (clipIndices != null && clipIndices.length > 1) {
      return false;
    }
    return true;
  }

  bool _hasMidiLengthPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    final lengthMeasures = _parseActionDouble(
        data['length_measures'] ?? target['length_measures']);
    if (lengthMeasures != null &&
        lengthMeasures.isFinite &&
        lengthMeasures > 0.0) {
      return true;
    }
    final lengthBeats =
        _parseActionDouble(data['length_beats'] ?? target['length_beats']);
    return lengthBeats != null && lengthBeats.isFinite && lengthBeats > 0.0;
  }

  bool _parseActionBool(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final token = raw.trim().toLowerCase();
      return token == 'true' || token == '1' || token == 'yes';
    }
    return false;
  }

  bool _hasPreserveExistingMidiPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    final preserve = _parseActionBool(
      data['preserve_existing_notes'] ?? target['preserve_existing_notes'],
    );
    if (!preserve) return false;
    final operation = data['operation']?.toString().trim().toLowerCase() ?? '';
    if (operation != 'replace_notes' && operation != 'append_notes') {
      return false;
    }
    if (!_hasMidiLengthPayload(data) || _hasMidiPayload(data)) {
      return false;
    }
    if (AssistantActionUtils.hasStyleDrivenMidiGenerationDirectives(
      data,
      target: target,
    )) {
      return false;
    }
    return true;
  }

  bool _looksLikePackagedLibraryReference(String libraryPath) {
    final normalized = libraryPath.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized.startsWith('role:')) return true;
    return normalized.contains('/') || normalized.contains('\\');
  }

  bool _looksLikeLoopLibraryReference(String libraryPath) {
    final normalized = libraryPath.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('/loops/') ||
        normalized.contains('\\loops\\') ||
        RegExp(r'(^|[/\\])loops?([/\\]|$)').hasMatch(normalized) ||
        RegExp(r'\bloop\b').hasMatch(normalized);
  }

  bool _hasMusicalSpanPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    for (final key in const <String>[
      'length_ms',
      'length_measures',
      'length_beats',
      'until_ms',
      'until_measure',
      'until_beat',
    ]) {
      final value = _parseActionDouble(data[key] ?? target[key]);
      if (value != null && value.isFinite && value > 0.0) {
        return true;
      }
    }
    return false;
  }

  bool _hasRepeatingPlacementPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    final repeatCount = _parseActionInt(
      data['repeat_count'] ??
          target['repeat_count'] ??
          data['copies'] ??
          target['copies'] ??
          data['count'] ??
          target['count'],
    );
    if (repeatCount != null && repeatCount > 1) {
      return true;
    }
    for (final key in const <String>[
      'step_ms',
      'step_measures',
      'step_beats',
      'spacing_ms',
      'spacing_measures',
      'spacing_beats',
    ]) {
      final value = _parseActionDouble(data[key] ?? target[key]);
      if (value != null && value.isFinite && value > 0.0) {
        return true;
      }
    }
    return false;
  }

  bool _isValidSampleInsertItem(
    Map<String, dynamic> item, {
    required String operation,
  }) {
    final rawTarget = item['target'];
    final target = rawTarget is Map<String, dynamic>
        ? rawTarget
        : (rawTarget is Map
            ? Map<String, dynamic>.from(rawTarget)
            : const <String, dynamic>{});
    final libraryPath =
        (item['library_path'] ?? target['library_path'])?.toString().trim() ??
            '';
    if (!_looksLikePackagedLibraryReference(libraryPath)) {
      return false;
    }
    if (operation == 'replace_audio_clips') {
      return target.isNotEmpty ||
          item.containsKey('clip_index') ||
          item.containsKey('clip_indices') ||
          item.containsKey('row_index');
    }
    if (_hasMusicalSpanPayload(item) &&
        !_looksLikeLoopLibraryReference(libraryPath) &&
        !_hasRepeatingPlacementPayload(item)) {
      return false;
    }
    return true;
  }

  String _normalizeTutorialTargetId(Object? raw) {
    final targetId = raw?.toString().trim() ?? '';
    final match = RegExp(r'^(row:\d+:)fx_index:([^:]+)(:param:.+)?$')
        .firstMatch(targetId);
    if (match == null) return targetId;
    final effectRef = (match.group(2) ?? '').trim();
    if (RegExp(r'^\d+$').hasMatch(effectRef)) return targetId;
    final suffix = match.group(3) ?? '';
    return '${match.group(1)}fx_contains:$effectRef$suffix';
  }

  int? _parseActionInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  double? _parseActionDouble(dynamic raw) {
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  Map<String, dynamic> _normalizeMidiNotePayload(Map<String, dynamic> rawNote) {
    final note = Map<String, dynamic>.from(rawNote);
    final pitch = AssistantActionUtils.midiPitchFromRaw(
      note['pitch'] ?? note['midi'] ?? note['note'] ?? note['note_name'],
      fallbackOctave: 3,
    );
    if (pitch != null) {
      note['pitch'] = pitch.clamp(0, 127).toInt();
    }

    final startBeat = AssistantActionUtils.resolveMidiNoteStartBeat(note);
    if (startBeat != null) {
      note['start_beat'] = startBeat;
    }

    final lengthBeats = AssistantActionUtils.resolveMidiNoteLengthBeats(note);
    if (lengthBeats != null) {
      note['length_beats'] = lengthBeats;
    }

    final velocity =
        AssistantActionUtils.normalizeMidiVelocity(note['velocity']);
    if (velocity != null) {
      note['velocity'] = velocity;
    }

    return note;
  }

  List<Map<String, dynamic>> _normalizeMidiNotesPayload(dynamic rawNotes) {
    if (rawNotes is! List) return const <Map<String, dynamic>>[];
    final normalized = <Map<String, dynamic>>[];
    for (final raw in rawNotes) {
      if (raw is! Map) continue;
      normalized.add(_normalizeMidiNotePayload(Map<String, dynamic>.from(raw)));
    }
    if (_looksLikeOneBasedBeatGrid(normalized)) {
      for (final note in normalized) {
        final startBeat = _parseActionDouble(note['start_beat']);
        if (startBeat == null) continue;
        note['start_beat'] = math.max(0.0, startBeat - 1.0);
      }
    }
    return normalized;
  }

  bool _looksLikeOneBasedBeatGrid(List<Map<String, dynamic>> notes) {
    if (notes.isEmpty) return false;
    double? minStartBeat;
    var sawExactOne = false;
    for (final note in notes) {
      final startBeat = _parseActionDouble(note['start_beat']);
      if (startBeat == null || !startBeat.isFinite || startBeat <= 0.0) {
        return false;
      }
      minStartBeat =
          minStartBeat == null ? startBeat : math.min(minStartBeat, startBeat);
      if ((startBeat - 1.0).abs() < 1e-6) {
        sawExactOne = true;
      }
    }
    return sawExactOne &&
        minStartBeat != null &&
        (minStartBeat - 1.0).abs() < 1e-6;
  }

  int? _parseRowAlias(dynamic raw, {required bool oneBased}) {
    final v = _parseActionInt(raw);
    if (v == null) return null;
    if (oneBased) {
      if (v == 0) return 0;
      return v > 0 ? v - 1 : null;
    }
    return v >= 0 ? v : null;
  }

  int? _extractNormalizedRowIndex(
    Map<String, dynamic> data,
    Map<String, dynamic> target,
  ) {
    int? pick(List<String> keys, {required bool oneBased}) {
      for (final key in keys) {
        final fromData = _parseRowAlias(data[key], oneBased: oneBased);
        if (fromData != null) return fromData;
        final fromTarget = _parseRowAlias(target[key], oneBased: oneBased);
        if (fromTarget != null) return fromTarget;
      }
      return null;
    }

    return pick(
          const ['row_index', 'track_index', 'target_row_index'],
          oneBased: false,
        ) ??
        pick(const ['row', 'target_row'], oneBased: true) ??
        pick(const ['row_number', 'track_number', 'track'], oneBased: true);
  }

  Map<String, dynamic> _normalizeSampleInsertItem(
    Map<String, dynamic> rawItem,
  ) {
    final item = Map<String, dynamic>.from(rawItem);
    final rawTarget = item['target'];
    final target = rawTarget is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawTarget)
        : (rawTarget is Map
            ? Map<String, dynamic>.from(rawTarget)
            : <String, dynamic>{});
    final rowIndex = _extractNormalizedRowIndex(item, target);
    if (rowIndex != null) {
      item['row_index'] = rowIndex;
      target['row_index'] = rowIndex;
    }
    item['target'] = target;
    return item;
  }

  List<Map<String, dynamic>> _postProcessNormalizedActions(
    List<Map<String, dynamic>> actions,
  ) {
    final normalized = actions
        .map((action) => <String, dynamic>{
              'type': action['type'],
              'data': Map<String, dynamic>.from(
                action['data'] as Map<String, dynamic>,
              ),
            })
        .toList(growable: false);
    final tempoBpm = _normalizedProjectTempoBpm(normalized);
    for (final action in normalized) {
      final type = action['type']?.toString().trim().toLowerCase() ?? '';
      if (type != 'sample_insert') continue;
      _repairBackbeatSampleInsert(
        action['data'] as Map<String, dynamic>,
        tempoBpm: tempoBpm,
      );
    }
    return normalized;
  }

  double? _normalizedProjectTempoBpm(List<Map<String, dynamic>> actions) {
    for (final action in actions) {
      final type = action['type']?.toString().trim().toLowerCase() ?? '';
      if (type != 'project_edit') continue;
      final data = action['data'] as Map<String, dynamic>? ?? const {};
      final operation =
          data['operation']?.toString().trim().toLowerCase() ?? '';
      if (operation != 'set_tempo') continue;
      final tempo = _parseActionDouble(data['tempo_bpm'] ?? data['bpm']);
      if (tempo != null) return tempo;
    }
    return null;
  }

  double? _sampleInsertItemStartBeat(Map<String, dynamic> item) {
    final target = _actionTargetMap(item);
    return _parseActionDouble(
      item['new_start_beat'] ??
          item['paste_start_beat'] ??
          item['start_beat'] ??
          item['at_beat'] ??
          target['new_start_beat'] ??
          target['paste_start_beat'] ??
          target['start_beat'] ??
          target['at_beat'] ??
          item['beat'] ??
          target['beat'] ??
          item['beat_index'] ??
          target['beat_index'],
    );
  }

  double? _sampleInsertItemStepBeats(Map<String, dynamic> item) {
    final target = _actionTargetMap(item);
    return _parseActionDouble(
      item['step_beats'] ??
          target['step_beats'] ??
          item['spacing_beats'] ??
          target['spacing_beats'],
    );
  }

  bool _isRepeatedSampleScaffold(Map<String, dynamic> item) {
    final target = _actionTargetMap(item);
    final repeatCount = _parseActionInt(
          item['repeat_count'] ??
              target['repeat_count'] ??
              item['copies'] ??
              target['copies'] ??
              item['count'] ??
              target['count'],
        ) ??
        1;
    return repeatCount > 1 ||
        _hasRepeatingPlacementPayload(item) ||
        _hasMusicalSpanPayload(item);
  }

  bool _sampleInsertItemsShareBeatGrid(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    final firstStart = _sampleInsertItemStartBeat(first) ?? 1.0;
    final secondStart = _sampleInsertItemStartBeat(second) ?? 1.0;
    if ((firstStart - secondStart).abs() > 1e-6) return false;

    final firstStep = _sampleInsertItemStepBeats(first);
    final secondStep = _sampleInsertItemStepBeats(second);
    if (firstStep == null || secondStep == null) {
      return true;
    }
    return (firstStep - secondStep).abs() < 1e-6;
  }

  void _repairBackbeatSampleInsert(
    Map<String, dynamic> data, {
    required double? tempoBpm,
  }) {
    final operation = data['operation']?.toString().trim().toLowerCase() ?? '';
    if (operation != 'insert_audio_clips' && operation != 'insert_audio_clip') {
      return;
    }
    final rawItems = data['items'];
    if (rawItems is! List || rawItems.isEmpty) return;

    final grouped = <String, List<Map<String, dynamic>>>{};
    final kickItems = <Map<String, dynamic>>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = rawItem is Map<String, dynamic>
          ? rawItem
          : Map<String, dynamic>.from(rawItem);
      final target = _actionTargetMap(item);
      final libraryPath =
          (item['library_path'] ?? target['library_path'])?.toString().trim() ??
              '';
      final role = AssistantActionUtils.primarySampleRoleFromText(libraryPath);
      if (role == 'kick') {
        kickItems.add(item);
      }
      if (role != 'snare' && role != 'clap') continue;
      grouped.putIfAbsent(role!, () => <Map<String, dynamic>>[]).add(item);
    }

    for (final roleItems in grouped.values) {
      final repeated = roleItems.where(_isRepeatedSampleScaffold).toList();
      if (repeated.length != 1) continue;

      final item = repeated.single;
      final startBeat = _sampleInsertItemStartBeat(item);
      if (startBeat != null && (startBeat - 1.0).abs() > 1e-6) {
        continue;
      }
      if (_parseActionDouble(
            item['start_ms'] ?? _actionTargetMap(item)['start_ms'],
          ) !=
          null) {
        continue;
      }

      final target = _actionTargetMap(item);
      final explicitStepBeats = _parseActionDouble(
        item['step_beats'] ??
            target['step_beats'] ??
            item['spacing_beats'] ??
            target['spacing_beats'],
      );
      final hasMeasureStep = _parseActionDouble(
            item['step_measures'] ??
                target['step_measures'] ??
                item['spacing_measures'] ??
                target['spacing_measures'] ??
                item['step_bars'] ??
                target['step_bars'] ??
                item['spacing_bars'] ??
                target['spacing_bars'],
          ) !=
          null;
      if (hasMeasureStep) {
        continue;
      }

      final collidingKickItems = kickItems
          .where(_isRepeatedSampleScaffold)
          .where((kick) => _sampleInsertItemsShareBeatGrid(item, kick))
          .toList(growable: false);
      if (collidingKickItems.isEmpty) {
        continue;
      }

      final wantsHalfTimeBackbeat = tempoBpm != null && tempoBpm >= 135.0 ||
          kickItems.any((kick) {
            final kickStart = _sampleInsertItemStartBeat(kick);
            return kickStart != null && (kickStart - 3.0).abs() < 1e-6;
          });
      item['start_beat'] = wantsHalfTimeBackbeat ? 3 : 2;

      if (explicitStepBeats == null ||
          (explicitStepBeats - 2.0).abs() < 1e-6 ||
          (explicitStepBeats - 4.0).abs() < 1e-6) {
        item['step_beats'] = wantsHalfTimeBackbeat ? 4 : 2;
      }
    }
  }

  String? _extractEffectToken(
    Map<String, dynamic> data,
    Map<String, dynamic> target,
  ) {
    const keys = <String>[
      'effect_name',
      'plugin_name',
      'effect_name_contains',
      'plugin',
      'effect',
      'fx',
      'name',
      'kind',
    ];
    for (final key in keys) {
      final fromData = data[key]?.toString().trim() ?? '';
      if (fromData.isNotEmpty) return fromData;
      final fromTarget = target[key]?.toString().trim() ?? '';
      if (fromTarget.isNotEmpty) return fromTarget;
    }
    return null;
  }

  Map<String, dynamic> _normalizeDawActionData(
    String actionType,
    Map<String, dynamic> rawData,
    String userText,
  ) {
    final data = Map<String, dynamic>.from(rawData);
    final target = _actionTargetMap(data);

    final scopeValue =
        (data['scope'] ?? target['scope'])?.toString().trim().toLowerCase();
    if (scopeValue != null && scopeValue.isNotEmpty) {
      data['scope'] = scopeValue;
      target['scope'] = scopeValue;
    }

    final rowIndex = _extractNormalizedRowIndex(data, target);
    final isMasterScope = (target['scope']?.toString().trim().toLowerCase() ??
            data['scope']?.toString().trim().toLowerCase()) ==
        'master';
    if (!isMasterScope && rowIndex != null) {
      data['row_index'] = rowIndex;
      target['row_index'] = rowIndex;
    }

    if (actionType == 'effect_edit') {
      final effectToken = _extractEffectToken(data, target);
      if (effectToken != null) {
        target.putIfAbsent('effect_name', () => effectToken);
        target.putIfAbsent('plugin_name', () => effectToken);
        target.putIfAbsent('effect_name_contains', () => effectToken);
        data.putIfAbsent('effect_name', () => effectToken);
      }
    }

    if (actionType == 'tutorial') {
      final steps = data['steps'];
      if (steps is List) {
        data['steps'] = steps.map((step) {
          if (step is! Map) return step;
          final repaired = Map<String, dynamic>.from(step);
          repaired['target_id'] = _normalizeTutorialTargetId(
            repaired['target_id'],
          );
          return repaired;
        }).toList(growable: false);
      }
    }

    if (actionType == 'project_edit') {
      data['operation'] = _normalizeProjectEditOperation(data['operation']);
      final tempo = _parseActionDouble(data['tempo_bpm'] ?? data['bpm']);
      if (tempo != null) {
        data['tempo_bpm'] = tempo;
      }
    }

    if (actionType == 'sample_insert') {
      data['operation'] = _normalizeSampleInsertOperation(data['operation']);
      final rawItems = data['items'];
      if (rawItems is List && rawItems.isNotEmpty) {
        data['items'] = rawItems
            .whereType<Map>()
            .map((raw) => _normalizeSampleInsertItem(
                  Map<String, dynamic>.from(raw),
                ))
            .toList(growable: false);
      } else if ((data['library_path']?.toString().trim().isNotEmpty ??
              false) ||
          (target['library_path']?.toString().trim().isNotEmpty ?? false)) {
        data['items'] = <Map<String, dynamic>>[
          _normalizeSampleInsertItem(data),
        ];
      }
    }

    if (actionType == 'clip_edit') {
      final operation =
          data['operation']?.toString().trim().toLowerCase() ?? '';
      if (operation == 'dialog_remove_range' &&
          !_hasCompleteDialogRemoveRangePayload(data)) {
        data['operation'] = 'dialog_remove_range';
      }
    }

    if (actionType == 'role_override') {
      final role = (data['role']?.toString().trim().toLowerCase() ?? '');
      if (role.isNotEmpty) {
        data['role'] = role;
      }
    }

    if (actionType == 'row_group_edit') {
      data['operation'] = _normalizeRowGroupEditOperation(data['operation']);
    }

    if (actionType == 'midi_compose' && data['notes'] is List) {
      data['notes'] = _normalizeMidiNotesPayload(data['notes']);
    }

    if (actionType == 'midi_compose') {
      final operation =
          data['operation']?.toString().trim().toLowerCase() ?? '';
      if (operation == 'replace_notes' &&
          !_hasMidiPayload(data) &&
          _hasMidiLengthPayload(data) &&
          !AssistantActionUtils.hasStyleDrivenMidiGenerationDirectives(
            data,
            target: target,
          )) {
        data['preserve_existing_notes'] = true;
      }
    }

    data['target'] = target;
    return data;
  }

  bool _hasMidiPayload(Map<String, dynamic> data) {
    final notes = data['notes'];
    final progression = data['progression'];
    final hasNotes = notes is List && notes.isNotEmpty;
    final hasProgression = (progression is List && progression.isNotEmpty) ||
        (progression is String && progression.trim().isNotEmpty);
    return hasNotes || hasProgression;
  }

  bool _isValidDawActionData(
    String type,
    Map<String, dynamic> data, {
    required String userText,
  }) {
    switch (type) {
      case 'tutorial':
        final topic = data['topic']?.toString().trim() ?? '';
        final steps = data['steps'];
        return topic.isNotEmpty || (steps is List && steps.isNotEmpty);
      case 'clarify':
        final question = data['question']?.toString().trim() ?? '';
        return question.isNotEmpty;
      case 'project_edit':
        return _allowedProjectEditOperations.contains(data['operation']) &&
            _parseActionDouble(data['tempo_bpm'] ?? data['bpm']) != null;
      case 'sample_insert':
        if (!_allowedSampleInsertOperations.contains(data['operation'])) {
          return false;
        }
        final items = data['items'];
        return items is List &&
            items.isNotEmpty &&
            items.whereType<Map>().every((raw) {
              final item = Map<String, dynamic>.from(raw);
              return _isValidSampleInsertItem(
                item,
                operation:
                    data['operation']?.toString().trim().toLowerCase() ?? '',
              );
            });
      case 'clip_edit':
        final operation = data['operation']?.toString().trim().toLowerCase();
        if (!_allowedClipEditOperations.contains(operation)) return false;
        if (operation == 'dialog_remove_range') {
          return _hasCompleteDialogRemoveRangePayload(data);
        }
        if (operation == 'move') {
          return _hasMeaningfulMovePayload(data);
        }
        if (operation == 'cut') {
          return _hasSupportedCutPayload(data);
        }
        if (operation == 'pitch_shift') {
          final target = _actionTargetMap(data);
          return _parseActionDouble(data['semitones'] ??
                  target['semitones'] ??
                  data['delta_semitones'] ??
                  target['delta_semitones'] ??
                  data['pitch_semitones'] ??
                  target['pitch_semitones'] ??
                  data['new_pitch_semitones'] ??
                  target['new_pitch_semitones']) !=
              null;
        }
        return true;
      case 'effect_edit':
        return _allowedEffectEditOperations.contains(data['operation']);
      case 'row_group_edit':
        return _allowedRowGroupEditOperations.contains(data['operation']);
      case 'row_color_edit':
        return _allowedRowColorEditOperations.contains(data['operation']);
      case 'automation_edit':
        if (!_allowedAutomationEditOperations.contains(data['operation'])) {
          return false;
        }
        final operation = data['operation']?.toString().trim().toLowerCase();
        final target = _actionTargetMap(data);
        if (operation == 'apply_template') {
          final template = (data['template'] ??
                  target['template'] ??
                  data['pattern'] ??
                  target['pattern'] ??
                  '')
              .toString();
          if (!_isKnownAutomationTemplate(template)) {
            return false;
          }
        }
        return true;
      case 'midi_compose':
        final operation = data['operation'];
        if (!_allowedMidiComposeOperations.contains(operation)) return false;
        if (operation == 'chop_notes') return true;
        if (operation == 'transpose_notes') {
          return _parseActionDouble(data['semitones']) != null ||
              _parseActionDouble(data['octaves']) != null;
        }
        if (operation == 'convert_audio_to_midi') return true;
        return _hasMidiPayload(data) || _hasPreserveExistingMidiPayload(data);
      case 'stem_separate':
        return _allowedStemSeparateOperations.contains(data['operation']);
      case 'role_override':
        return _allowedRoleOverrideOperations.contains(data['operation']);
      case 'audio_enhance':
        return data['operation'] == 'phone_mic_cleanup';
    }
    return false;
  }

  void _logDroppedDawAction(
    String reason,
    String type,
    Map<String, dynamic> data, {
    required String userText,
  }) {
    final operation = data['operation']?.toString().trim() ?? '';
    aiDebugLog(
      'llm-normalize',
      'dropped daw action reason=$reason type=${type.isEmpty ? "-" : type}'
          ' operation=${operation.isEmpty ? "-" : operation}'
          ' prompt="${userText.trim()}" data=${aiDebugShortMap(data)}',
    );
  }

  List<Map<String, dynamic>> _normalizeDawAssistantActions(
    List rawActions, {
    required String userText,
  }) {
    final out = <Map<String, dynamic>>[];
    var droppedInvalid = false;
    for (final rawAction in rawActions) {
      if (rawAction is! Map) {
        droppedInvalid = true;
        aiDebugLog(
          'llm-normalize',
          'dropped daw action reason=not_map prompt="${userText.trim()}"',
        );
        continue;
      }
      final action = Map<String, dynamic>.from(rawAction);
      final type = (action['type']?.toString().trim().toLowerCase() ?? '');
      if (!_dawAssistantActionTypes.contains(type)) {
        droppedInvalid = true;
        _logDroppedDawAction(
          'unknown_type',
          type,
          Map<String, dynamic>.from(
            action['data'] is Map ? action['data'] as Map : const {},
          ),
          userText: userText,
        );
        continue;
      }
      final rawData = action['data'];
      final data = rawData is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawData)
          : (rawData is Map
              ? Map<String, dynamic>.from(rawData)
              : <String, dynamic>{});
      if (type == 'project_edit') {
        data['operation'] = _normalizeProjectEditOperation(data['operation']);
      } else if (type == 'sample_insert') {
        data['operation'] = _normalizeSampleInsertOperation(data['operation']);
      } else if (type == 'clip_edit') {
        data['operation'] = _normalizeClipEditOperation(data['operation']);
      } else if (type == 'effect_edit') {
        data['operation'] = _normalizeEffectEditOperation(data['operation']);
      } else if (type == 'row_group_edit') {
        data['operation'] = _normalizeRowGroupEditOperation(data['operation']);
      } else if (type == 'row_color_edit') {
        data['operation'] = _normalizeActionToken(data['operation'] ?? 'set');
      } else if (type == 'automation_edit') {
        data['operation'] =
            _normalizeAutomationEditOperation(data['operation']);
      } else if (type == 'midi_compose') {
        data['operation'] = _normalizeMidiComposeOperation(data['operation']);
      } else if (type == 'stem_separate') {
        data['operation'] = _normalizeActionToken(data['operation']);
      } else if (type == 'role_override') {
        data['operation'] = _normalizeRoleOverrideOperation(
          data['operation'] ?? 'set',
        );
      }
      final normalizedData = _normalizeDawActionData(type, data, userText);
      if (!_isValidDawActionData(type, normalizedData, userText: userText)) {
        droppedInvalid = true;
        _logDroppedDawAction(
          'invalid_payload',
          type,
          normalizedData,
          userText: userText,
        );
        continue;
      }
      out.add({
        'type': type,
        'data': normalizedData,
      });
    }
    final normalized = _postProcessNormalizedActions(out);
    if (droppedInvalid &&
        normalized.isNotEmpty &&
        normalized.every(
          (action) =>
              action['type']?.toString().trim().toLowerCase() == 'project_edit',
        )) {
      return const <Map<String, dynamic>>[];
    }
    return normalized;
  }

  Map<String, dynamic>? _decodeToolArgs(dynamic raw) {
    dynamic current = raw;
    for (var i = 0; i < 4; i++) {
      if (current is Map) {
        final map = Map<String, dynamic>.from(current);
        if (map.length == 1 && map.containsKey('value')) {
          current = map['value'];
          continue;
        }
        return map;
      }
      if (current is String) {
        final trimmed = current.trim();
        if (trimmed.isEmpty) return null;
        try {
          current = jsonDecode(trimmed);
        } catch (_) {
          return null;
        }
        continue;
      }
      return null;
    }
    return current is Map ? Map<String, dynamic>.from(current) : null;
  }

  String _normalizeMixExecutionProfile(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case 'creative_bold':
      case 'experimental_extreme':
        return value;
      case 'producer_safe':
      default:
        return 'producer_safe';
    }
  }

  String _normalizeMixAudibility(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case 'subtle':
      case 'obvious':
      case 'extreme':
        return value;
      case 'noticeable':
      default:
        return 'noticeable';
    }
  }

  List<String> _normalizeMixStyleTags(dynamic raw) {
    final values =
        raw is List ? raw : (raw is String ? <String>[raw] : const <String>[]);
    final out = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = value?.toString().trim().toLowerCase() ?? '';
      if (normalized.isEmpty || normalized == 'null') continue;
      final canonical = normalized.replaceAll(RegExp(r'\s+'), '_');
      if (canonical.isEmpty || canonical.length > 40) continue;
      if (seen.add(canonical)) {
        out.add(canonical);
      }
      if (out.length >= 8) break;
    }
    return out;
  }

  String _normalizeMixReferenceMode(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case 'tone':
      case 'loudness':
      case 'width':
      case 'glue':
        return value;
      case 'full_mix':
      default:
        return 'full_mix';
    }
  }

  String _normalizeMixReferenceCloseness(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case 'loose':
      case 'close':
        return value;
      case 'balanced':
      default:
        return 'balanced';
    }
  }

  Map<String, dynamic>? _normalizeMixReferenceTarget(dynamic raw) {
    if (raw is! Map) return null;
    final normalized = Map<String, dynamic>.from(raw);
    final rowIndex = normalized['row_index'];
    if (rowIndex is num) {
      final canonicalRow = rowIndex.toInt();
      if (canonicalRow < 0) return null;
      normalized
        ..['row_index'] = canonicalRow
        ..remove('prefer_selected');
    } else if (normalized['prefer_selected'] == true) {
      normalized
        ..['prefer_selected'] = true
        ..remove('row_index');
    } else {
      return null;
    }
    normalized['confidence'] =
        ((normalized['confidence'] ?? 0.5) as num).toDouble().clamp(0.0, 1.0);
    return normalized;
  }

  Map<String, dynamic>? _normalizeToolArgs(
    String toolName,
    dynamic rawArgs, {
    required String userText,
  }) {
    final args = _decodeToolArgs(rawArgs);
    if (args == null) return null;

    if (toolName == 'informational_response') {
      args['message'] = _sanitizeUserFacingText(
        args['message'],
        toolName: toolName,
        userText: userText,
      );
      args['cancels_pending'] = args['cancels_pending'] == true;
      return args;
    }

    if (toolName == 'daw_assistant_actions') {
      final actions = args['actions'];
      if (actions is! List || actions.isEmpty) return null;
      final normalizedActions = _normalizeDawAssistantActions(
        actions,
        userText: userText,
      );
      if (normalizedActions.isEmpty) return null;
      final assistantMessage = _sanitizeUserFacingText(
        args['assistant_message'],
        toolName: toolName,
        userText: userText,
        allowFallback: false,
      );
      args['actions'] = normalizedActions;
      args['assistant_message'] = assistantMessage;
      return args;
    }

    if (toolName == 'mix_model_request') {
      final actions = args['actions'];
      final mode = (args['mode']?.toString() ?? '').trim();
      if (actions is! List || actions.isEmpty) return null;
      if (mode != 'execute' && mode != 'propose') return null;

      for (final action in actions) {
        if (action is! Map) return null;
        final goal = action['goal'];
        if (goal is! Map) return null;
        final normalizedGoal = Map<String, dynamic>.from(goal);
        normalizedGoal['type'] = 'mix_request';
        normalizedGoal['execution_profile'] = _normalizeMixExecutionProfile(
          normalizedGoal['execution_profile'],
        );
        normalizedGoal['audibility'] = _normalizeMixAudibility(
          normalizedGoal['audibility'],
        );
        normalizedGoal['style_tags'] = _normalizeMixStyleTags(
          normalizedGoal['style_tags'],
        );
        normalizedGoal['destructive_ok'] =
            normalizedGoal['destructive_ok'] == true;
        final normalizedReferenceTarget = _normalizeMixReferenceTarget(
          normalizedGoal['reference_target'],
        );
        if (normalizedReferenceTarget != null) {
          normalizedGoal['reference_target'] = normalizedReferenceTarget;
          normalizedGoal['reference_mode'] = _normalizeMixReferenceMode(
            normalizedGoal['reference_mode'],
          );
          normalizedGoal['reference_closeness'] =
              _normalizeMixReferenceCloseness(
            normalizedGoal['reference_closeness'],
          );
        } else {
          normalizedGoal.remove('reference_target');
          normalizedGoal.remove('reference_mode');
          normalizedGoal.remove('reference_closeness');
        }
        final target = normalizedGoal['target'];
        if (target is! Map) return null;

        final normalizedTarget = Map<String, dynamic>.from(target);
        final scope = (normalizedTarget['scope']?.toString() ?? '').trim();
        if (scope == 'master') {
          normalizedTarget.remove('row_index');
          normalizedTarget.remove('role');
        } else {
          final rowIndex = normalizedTarget['row_index'];
          if (rowIndex is num) {
            final normalizedRow = rowIndex.toInt();
            if (normalizedRow < 0) return null;
            normalizedTarget['row_index'] = normalizedRow;
          } else if (rowIndex != null) {
            return null;
          }
        }
        normalizedGoal['target'] = normalizedTarget;

        final intents = normalizedGoal['intents'];
        if (intents is! List || intents.isEmpty) return null;
        for (final intent in intents) {
          if (intent is! Map) return null;
        }
        action['goal'] = normalizedGoal;
      }

      final assistantMessage = _sanitizeUserFacingText(
        args['assistant_message'],
        toolName: toolName,
        userText: userText,
        allowFallback: false,
      );
      args['assistant_message'] = assistantMessage;
      return args;
    }

    return args;
  }

  Future<LlmResult> send({
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    String selectionSnapshot = '',
    String librarySnapshot = '',
    String? promptTraceId,
    String? projectId,
    String? aiFeature,
    MixingResult? pendingMix,
    Map<String, dynamic> clientContext = const <String, dynamic>{},
  }) async {
    final requestStopwatch = Stopwatch();
    final parseStopwatch = Stopwatch();
    var directRetriedWithoutPendingMix = false;
    late http.Response response;
    try {
      if (_isProxyEnabled) {
        final token = await _resolveProxyAuthToken();
        if (token == null || token.isEmpty) {
          return _recoverableTextResult(
            _recoverableAuthMessage,
            softErrorCode: 'auth_unavailable',
          );
        }

        requestStopwatch.start();
        response = await _postProxyJson(
          token: token,
          conversation: conversation,
          userText: userText,
          projectSnapshot: projectSnapshot,
          selectionSnapshot: selectionSnapshot,
          librarySnapshot: librarySnapshot,
          promptTraceId: promptTraceId,
          projectId: projectId,
          aiFeature: aiFeature,
          pendingMix: pendingMix,
          clientContext: clientContext,
        );
        requestStopwatch.stop();
      } else if (_canUseDirectOpenAi) {
        if (!_isUsingDebugSystemPrompt) {
          return LlmResult.text(
            'Direct OpenAI debug mode requires a non-empty kDebugSystemPrompt in lib/ai/debug_system_prompt.dart.',
            null,
          );
        }
        final effectiveClientContext = _mergedAnalyticsClientContext(
          clientContext,
        );
        final inputMessages = _buildInputMessages(
          conversation: conversation,
          userText: userText,
          projectSnapshot: projectSnapshot,
          selectionSnapshot: selectionSnapshot,
          librarySnapshot: librarySnapshot,
          pendingMix: pendingMix,
        );

        final requestBody = _buildOpenAiRequestBody(
          inputMessages: inputMessages,
          aiFeature: aiFeature,
          clientContext: effectiveClientContext,
        );
        aiDebugLog(
          'direct-openai',
          'request route=$_llmRouteLabel model=${model.trim()} '
              'reasoning=${requestBody['reasoning']} '
              'tool_choice=${requestBody['tool_choice']} '
              'tool_count=${(requestBody['tools'] as List?)?.length ?? 0} '
              'prompt_cache_key=${requestBody['prompt_cache_key']} '
              'prompt_cache_retention=${requestBody['prompt_cache_retention']}',
        );
        _debugDumpJson('direct-openai', 'request body', requestBody);

        final hasLibrarySnapshot = librarySnapshot.trim().isNotEmpty;
        final hasRetryDroppableContext = pendingMix != null;
        final initialTimeout = hasRetryDroppableContext
            ? Duration(
                milliseconds: math.min(
                  requestTimeout.inMilliseconds,
                  12000,
                ),
              )
            : requestTimeout;

        requestStopwatch.start();
        try {
          response = await _postJson(
            uri: Uri.parse(_apiUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: requestBody,
            timeoutOverride: initialTimeout,
          );
          requestStopwatch.stop();
        } on TimeoutException {
          requestStopwatch.stop();
          final canRetryWithoutHeavyContext = hasRetryDroppableContext &&
              initialTimeout.inMilliseconds < requestTimeout.inMilliseconds;
          if (!canRetryWithoutHeavyContext) rethrow;

          directRetriedWithoutPendingMix = true;
          final remainingTimeout = Duration(
            milliseconds: math.max(
              4000,
              requestTimeout.inMilliseconds - initialTimeout.inMilliseconds,
            ),
          );
          aiDebugLog(
            'direct-openai',
            'request timeout -> retrying without pending mix '
                '(library_retained=$hasLibrarySnapshot, '
                'retry_timeout_ms=${remainingTimeout.inMilliseconds})',
          );
          final retryInputMessages = _buildInputMessages(
            conversation: conversation,
            userText: userText,
            projectSnapshot: projectSnapshot,
            selectionSnapshot: selectionSnapshot,
            librarySnapshot: librarySnapshot,
            pendingMix: null,
          );
          final retryRequestBody = _buildOpenAiRequestBody(
            inputMessages: retryInputMessages,
            aiFeature: aiFeature,
            clientContext: effectiveClientContext,
          );
          _debugDumpJson(
            'direct-openai',
            'retry request body',
            retryRequestBody,
          );
          requestStopwatch
            ..reset()
            ..start();
          response = await _postJson(
            uri: Uri.parse(_apiUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: retryRequestBody,
            timeoutOverride: remainingTimeout,
          );
          requestStopwatch.stop();
        }
      } else {
        return LlmResult.text(
          'AI is not configured. Launch with --dart-define=LLM_PROXY_API_BASE_URL=... or --dart-define=OPENAI_API_KEY=... --dart-define=OPENAI_MODEL=...',
          null,
        );
      }
    } catch (error, stackTrace) {
      aiDebugLog(
        'llm-request',
        'request failed before parse: $error\n$stackTrace',
      );
      return _recoverableTextResult(
        _temporaryFailureMessage,
        softErrorCode: 'request_failed',
      );
    }

    parseStopwatch.start();
    var payload = _decodeJsonObject(response.body);
    var responseMeta = _buildResponseMeta(payload);
    responseMeta = _mergeMetaObservability(responseMeta, <String, dynamic>{
      if ((promptTraceId ?? '').trim().isNotEmpty)
        'prompt_trace_id': promptTraceId!.trim(),
      'proxy_roundtrip_ms': requestStopwatch.elapsedMilliseconds,
      'http_status_code': response.statusCode,
      'llm_route': _llmRouteLabel,
      'prompt_source': _promptSourceLabel,
      if (!_isProxyEnabled && _canUseDirectOpenAi) ...<String, dynamic>{
        'provider': 'openai',
        'effective_model': model.trim(),
        if (directRetriedWithoutPendingMix)
          'direct_retry_without_pending_mix': true,
      },
    });
    var promptRateLimit = _parsePromptRateLimitStatus(
      payload?['prompt_rate_limit'],
    );
    parseStopwatch.stop();
    responseMeta = _mergeMetaObservability(
      responseMeta,
      <String, dynamic>{
        'response_parse_ms': parseStopwatch.elapsedMilliseconds,
      },
    );

    if (!_isProxyEnabled && response.statusCode != 200) {
      aiDebugLog(
        'direct-openai',
        'error status=${response.statusCode} body=${payload ?? response.body}',
      );
    }
    if (!_isProxyEnabled && kAiDebugLogs) {
      aiDebugLog(
        'direct-openai',
        'response status=${response.statusCode} '
            'output_count=${(payload?['output'] as List?)?.length ?? 0}',
      );
      _debugDumpRawBody('direct-openai', 'response body', response.body);
    }

    if (response.statusCode != 200) {
      if (_isPromptRateLimitResponse(
        response.statusCode,
        payload,
        promptRateLimit,
      )) {
        final message = _rateLimitMessage(
          promptRateLimit,
          payload?['message']?.toString().trim().isNotEmpty == true
              ? payload!['message'].toString().trim()
              : 'You have reached the prompt limit. Please try again later.',
        );
        final rateLimitMeta = <String, dynamic>{
          ...responseMeta,
          if (promptRateLimit != null)
            'prompt_rate_limit': promptRateLimit.toJson(),
          'prompt_rate_limit_hit': true,
        };
        return LlmResult.text(
          message,
          {
            'message': message,
            'cancels_pending': false,
          },
          meta: rateLimitMeta,
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        if (_isProxyEnabled && refreshAuthTokenProvider != null) {
          try {
            final refreshedToken =
                await _resolveProxyAuthToken(forceRefresh: true);
            if (refreshedToken != null && refreshedToken.isNotEmpty) {
              requestStopwatch
                ..reset()
                ..start();
              response = await _postProxyJson(
                token: refreshedToken,
                conversation: conversation,
                userText: userText,
                projectSnapshot: projectSnapshot,
                selectionSnapshot: selectionSnapshot,
                librarySnapshot: librarySnapshot,
                promptTraceId: promptTraceId,
                projectId: projectId,
                aiFeature: aiFeature,
                pendingMix: pendingMix,
                clientContext: clientContext,
              );
              requestStopwatch.stop();
              parseStopwatch
                ..reset()
                ..start();
              payload = _decodeJsonObject(response.body);
              responseMeta = _buildResponseMeta(payload);
              responseMeta = _mergeMetaObservability(
                responseMeta,
                <String, dynamic>{
                  if ((promptTraceId ?? '').trim().isNotEmpty)
                    'prompt_trace_id': promptTraceId!.trim(),
                  'proxy_roundtrip_ms': requestStopwatch.elapsedMilliseconds,
                  'http_status_code': response.statusCode,
                  'llm_route': _llmRouteLabel,
                  'prompt_source': _promptSourceLabel,
                },
              );
              promptRateLimit = _parsePromptRateLimitStatus(
                payload?['prompt_rate_limit'],
              );
              parseStopwatch.stop();
              responseMeta = _mergeMetaObservability(
                responseMeta,
                <String, dynamic>{
                  'response_parse_ms': parseStopwatch.elapsedMilliseconds,
                },
              );
              if (response.statusCode == 200) {
                // Continue into the normal response parsing below.
              } else if (_isPromptRateLimitResponse(
                response.statusCode,
                payload,
                promptRateLimit,
              )) {
                final message = _rateLimitMessage(
                  promptRateLimit,
                  payload?['message']?.toString().trim().isNotEmpty == true
                      ? payload!['message'].toString().trim()
                      : 'You have reached the prompt limit. Please try again later.',
                );
                return LlmResult.text(
                  message,
                  {
                    'message': message,
                    'cancels_pending': false,
                  },
                  meta: responseMeta,
                );
              } else if (response.statusCode == 401 ||
                  response.statusCode == 403) {
                return _recoverableTextResult(
                  _recoverableAuthMessage,
                  softErrorCode: 'auth_rejected',
                  meta: responseMeta,
                );
              } else {
                return _recoverableTextResult(
                  _temporaryFailureMessage,
                  softErrorCode: 'request_failed',
                  meta: responseMeta,
                );
              }
            }
          } catch (_) {
            // Fall through to the recoverable auth message below.
          }
        }
        if (response.statusCode == 401 || response.statusCode == 403) {
          return _recoverableTextResult(
            _recoverableAuthMessage,
            softErrorCode: 'auth_rejected',
            meta: responseMeta,
          );
        }
      }
      if (response.statusCode != 200) {
        return _recoverableTextResult(
          _temporaryFailureMessage,
          softErrorCode: 'request_failed',
          meta: responseMeta,
        );
      }
    }
    final json = payload ?? const <String, dynamic>{};
    final outputs = (json['output'] as List<dynamic>? ?? const []);

    final List<LlmResult> toolResults = [];
    String? assistantText;

    for (final o in outputs) {
      final type = o['type'];

      if (type == 'function_call') {
        final name = o['name'] as String?;
        if (name == null) continue;

        final args = _normalizeToolArgs(
          name,
          o['arguments'],
          userText: userText,
        );
        if (args == null) {
          aiDebugLog(
            'llm-parse',
            'invalid function_call name=$name raw_args=${o['arguments']}',
          );
          final fallbackText = _invalidToolCallFallbackText(
            name,
            o['arguments'],
            userText: userText,
          );
          return LlmResult.text(
            fallbackText,
            <String, dynamic>{'message': fallbackText},
            meta: responseMeta,
          );
        }
        aiDebugLog(
          'llm-parse',
          'function_call name=$name args=${aiDebugShortMap(args)}',
        );
        _debugDumpJson('llm-parse', 'normalized args for $name', args);
        toolResults.add(
          name == 'informational_response'
              ? LlmResult.text(
                  args['message']?.toString() ?? '',
                  args,
                  meta: responseMeta,
                )
              : LlmResult.tool(
                  name,
                  args,
                  text: args['assistant_message'],
                  meta: responseMeta,
                ),
        );
        continue;
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
            final args = _normalizeToolArgs(
              'mix_model_request',
              text,
              userText: userText,
            );
            if (args == null) {
              final fallbackText = _invalidToolCallFallbackText(
                'mix_model_request',
                text,
                userText: userText,
              );
              return LlmResult.text(
                fallbackText,
                <String, dynamic>{'message': fallbackText},
                meta: responseMeta,
              );
            }
            toolResults.add(
              LlmResult.tool(
                'mix_model_request',
                args,
                meta: responseMeta,
              ),
            );
            continue;
          }

          // Normal assistant text
          if (text is String &&
              text.trim().isNotEmpty &&
              assistantText == null) {
            assistantText = _sanitizeUserFacingText(
              text,
              toolName: 'informational_response',
              userText: userText,
            );
          }
        }
      }
    }

    if (toolResults.isNotEmpty) {
      final informationalResults =
          toolResults.where((t) => t.toolName == 'informational_response');
      final nonInformationalResults =
          toolResults.where((t) => t.toolName != 'informational_response');

      if (nonInformationalResults.isEmpty) {
        final firstInfo = informationalResults.first;
        return LlmResult.text(
          firstInfo.text ?? '',
          firstInfo.toolArgs,
          meta: responseMeta,
        );
      }

      final firstTool = nonInformationalResults.first;
      final sameToolType = nonInformationalResults.every(
        (t) => t.toolName == firstTool.toolName,
      );
      if (!sameToolType) {
        final dawResults = nonInformationalResults
            .where((t) => t.toolName == 'daw_assistant_actions')
            .toList(growable: false);
        final mixResults = nonInformationalResults
            .where((t) => t.toolName == 'mix_model_request')
            .toList(growable: false);
        final preferredResults =
            dawResults.isNotEmpty ? dawResults : mixResults;
        if (preferredResults.isNotEmpty) {
          final preferredTool = preferredResults.first.toolName!;
          final preferredArgs = preferredResults
              .map((t) => t.toolArgs)
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          final userFacingText = assistantText ??
              preferredResults
                  .map((t) => t.text?.trim() ?? '')
                  .firstWhere((t) => t.isNotEmpty, orElse: () => '');
          final mixedMeta = <String, dynamic>{
            ...responseMeta,
            'mixed_tool_fallback': true,
            'mixed_tool_names': nonInformationalResults
                .map((t) => t.toolName)
                .whereType<String>()
                .toList(growable: false),
          };
          return LlmResult.tool(
            preferredTool,
            preferredArgs.length == 1
                ? preferredArgs.first
                : <String, dynamic>{'calls': preferredArgs},
            text: userFacingText.isEmpty ? null : userFacingText,
            meta: mixedMeta,
          );
        }
        return LlmResult.text(
          _fallbackAssistantText('informational_response'),
          {
            'message': _fallbackAssistantText('informational_response'),
            'cancels_pending': false,
          },
          meta: responseMeta,
        );
      }

      final callArgs = nonInformationalResults
          .map((t) => t.toolArgs)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      final userFacingText = assistantText ??
          nonInformationalResults
              .map((t) => t.text?.trim() ?? '')
              .firstWhere((t) => t.isNotEmpty, orElse: () => '');

      if (callArgs.length == 1) {
        return LlmResult.tool(
          firstTool.toolName!,
          callArgs.first,
          text: userFacingText.isEmpty ? null : userFacingText,
          meta: responseMeta,
        );
      }

      return LlmResult.tool(
        firstTool.toolName!,
        {'calls': callArgs},
        text: userFacingText.isEmpty ? null : userFacingText,
        meta: responseMeta,
      );
    }

    // Only reach here if NO tool-like structure existed
    if (assistantText != null &&
        assistantText != _fallbackAssistantText('informational_response')) {
      return LlmResult.text(assistantText, null, meta: responseMeta);
    }

    return LlmResult.text(
      _fallbackAssistantText('informational_response'),
      {
        'message': _fallbackAssistantText('informational_response'),
        'cancels_pending': false,
      },
      meta: responseMeta,
    );
  }
}
