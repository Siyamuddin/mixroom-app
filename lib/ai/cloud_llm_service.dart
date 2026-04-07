import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/models/mixing_result.dart';

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

  factory LlmResult.tool(String toolName, Map<String, dynamic> toolArgs, {String? text, Map<String, dynamic>? meta}) =>
      LlmResult(
        text: text,
        toolName: toolName,
        toolArgs: toolArgs,
        meta: meta,
      );
}

class CloudLlmService {
  static const _apiUrl = 'https://api.openai.com/v1/responses';
  static const _promptCacheVersion = 'mixroom-daw-v20260316';
  static const _defaultPromptCacheRetention = 'in_memory';
  static const _recoverableAuthMessage = "I couldn't reach the AI service just now. Please try again in a moment.";
  static const _temporaryFailureMessage = "I couldn't complete that request just now. Please try again in a moment.";
  static const Set<String> _extendedPromptCacheRetentionModels = {
    'gpt-4.1',
    'gpt-5',
    'gpt-5-codex',
    'gpt-5.1',
    'gpt-5.1-codex',
    'gpt-5.1-codex-mini',
    'gpt-5.1-chat-latest',
    'gpt-5.2',
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
  Map<String, dynamic>? get _defaultReasoning =>
      _supportsTemperature ? null : const <String, dynamic>{'effort': 'minimal'};
  String _promptCacheKeyForFeature(String aiFeature) =>
      '$_promptCacheVersion:${aiFeature.trim().isEmpty ? 'ai_chat' : aiFeature.trim()}';
  String get _promptCacheRetention =>
      _extendedPromptCacheRetentionModels.contains(model.trim().toLowerCase()) ? '24h' : _defaultPromptCacheRetention;
  bool get _canUseDirectOpenAi => apiKey.trim().isNotEmpty && model.trim().isNotEmpty;
  bool get _isProxyEnabled => proxyApiBaseUrl.trim().isNotEmpty;
  bool get _isUsingDebugSystemPrompt => kDebugMode && kDebugSystemPrompt.trim().isNotEmpty;
  String get _llmRouteLabel => _isProxyEnabled ? 'llm_proxy' : (_canUseDirectOpenAi ? 'direct_openai' : 'unconfigured');
  String get _promptSourceLabel {
    if (_isProxyEnabled) {
      return 'llm_proxy_system_prompt';
    }
    if (_isUsingDebugSystemPrompt) {
      return 'kDebugSystemPrompt2';
    }
    return 'missing_direct_openai_prompt';
  }

  String get _effectiveSystemPrompt {
    final debugPrompt = kDebugMode ? kDebugSystemPrompt.trim() : '';
    return debugPrompt;
  }

  List<Map<String, dynamic>> _buildInputMessages({
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    required String selectionSnapshot,
    MixingResult? pendingMix,
  }) {
    return [
      {'role': 'user', 'content': 'PROJECT_SNAPSHOT:\n$projectSnapshot'},
      if (selectionSnapshot.trim().isNotEmpty)
        {
          'role': 'user',
          'content': 'SELECTION_SNAPSHOT:\n$selectionSnapshot',
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

  Map<String, dynamic> _buildOpenAiRequestBody({
    required List<Map<String, dynamic>> inputMessages,
    String? aiFeature,
  }) {
    final normalizedAiFeature = _normalizeAiFeatureForProxy(aiFeature);
    final body = <String, dynamic>{
      'model': model,
      'instructions': _effectiveSystemPrompt,
      'prompt_cache_key': _promptCacheKeyForFeature(normalizedAiFeature),
      'prompt_cache_retention': _promptCacheRetention,
      'input': inputMessages,
      'tools': [
        {
          'type': 'function',
          'name': 'informational_response',
          'parameters': {
            'type': 'object',
            'properties': {
              'message': {'type': 'string', 'description': 'Pure informational response. No mix changes.'},
              'cancels_pending': {'type': 'boolean', 'description': 'Whether a pending mix is canceled or rejected.'},
            },
            'required': ['message', 'cancels_pending'],
          },
        },
        {
          'type': 'function',
          'name': 'daw_assistant_actions',
          'parameters': {
            'type': 'object',
            'properties': {
              'assistant_message': {
                'type': 'string',
                'description':
                    'Required short response shown to the user in their language; must be specific and non-placeholder.',
              },
              'actions': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': [
                        'tutorial',
                        'clarify',
                        'clip_edit',
                        'effect_edit',
                        'automation_edit',
                        'midi_compose',
                        'stem_separate',
                        'role_override',
                      ],
                    },
                    'data': {
                      'type': 'object',
                    },
                  },
                  'required': ['type', 'data'],
                },
              },
            },
            'required': ['assistant_message', 'actions'],
          },
        },
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
                    'Required single unified message describing the overall mix change; must be specific and non-placeholder.',
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
                                  'clipper',
                                  'balance',
                                ],
                              },
                              'direction': {
                                'type': 'string',
                                'enum': ['up', 'down', 'left', 'right', 'center', 'widen', 'narrow', 'remove', 'null'],
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
                                'scope': {
                                  'type': 'string',
                                  'enum': ['auto', 'row']
                                },
                                'confidence': {'type': 'number'},
                              },
                              'required': ['scope', 'confidence'],
                              'additionalProperties': false,
                            },
                          ],
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
            'required': ['mode', 'assistant_message', 'actions'],
          },
        },
      ],
      'tool_choice': 'required',
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
    String? promptTraceId,
    String? projectId,
    String? aiFeature,
    MixingResult? pendingMix,
  }) {
    final normalizedAiFeature = _normalizeAiFeatureForProxy(aiFeature);
    return {
      'conversation': conversation
          .map((m) => {
                'role': m['role'],
                'content': m['content'],
              })
          .toList(),
      'user_text': userText,
      'project_snapshot': projectSnapshot,
      if (selectionSnapshot.trim().isNotEmpty) 'selection_snapshot': selectionSnapshot,
      if ((promptTraceId ?? '').trim().isNotEmpty) 'prompt_trace_id': promptTraceId!.trim(),
      if ((projectId ?? '').trim().isNotEmpty) 'project_id': projectId,
      if (normalizedAiFeature.isNotEmpty) 'ai_feature': normalizedAiFeature,
      if (pendingMix != null) 'pending_mix': pendingMix.toJson(),
      ...AnalyticsService.instance.buildRequestContext(),
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
    final path = (pathOverride ?? proxyPath).trim().isEmpty ? '/v1/llm/responses' : (pathOverride ?? proxyPath);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }

  Future<String?> _resolveProxyAuthToken({bool forceRefresh = false}) async {
    final primaryProvider = forceRefresh ? refreshAuthTokenProvider : authTokenProvider;
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
    required String? promptTraceId,
    required String? projectId,
    required String? aiFeature,
    required MixingResult? pendingMix,
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
        promptTraceId: promptTraceId,
        projectId: projectId,
        aiFeature: aiFeature,
        pendingMix: pendingMix,
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
  }) {
    return _httpClient
        .post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);
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
        if (meta['observability'] is Map<String, dynamic>) ...(meta['observability'] as Map<String, dynamic>),
        if (meta['observability'] is Map) ...(meta['observability'] as Map).cast<String, dynamic>(),
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
      if (existingObservability is Map<String, dynamic>) ...existingObservability,
      if (existingObservability is Map) ...existingObservability.cast<String, dynamic>(),
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
      return hours > 0 ? '${remaining.inDays}d ${hours}h' : '${remaining.inDays}d';
    }
    if (remaining.inHours >= 1) {
      final minutes = remaining.inMinutes.remainder(60);
      return minutes > 0 ? '${remaining.inHours}h ${minutes}m' : '${remaining.inHours}h';
    }
    if (remaining.inMinutes >= 1) {
      return '${remaining.inMinutes}m';
    }
    return '${remaining.inSeconds}s';
  }

  String _rateLimitMessage(AiPromptRateLimitStatus? status, String fallback) {
    if (status == null) return fallback;
    final limitLabel = status.blockedBy == 'weekly_prompts' ? 'weekly' : 'daily';
    final wait = _formatResetCountdown(status.blockedResetAt);
    if (wait.isEmpty) {
      return 'You have reached the $limitLabel prompt limit. Please try again later.';
    }
    return 'You have reached the $limitLabel prompt limit. Try again in $wait.';
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
    if (lowered.contains('mix_model_request') ||
        lowered.contains('daw_assistant_actions') ||
        lowered.contains('informational_response') ||
        lowered.contains('"assistant_message"') ||
        lowered.contains('"row_index"') ||
        raw.startsWith('{') ||
        raw.startsWith('[')) {
      return allowFallback ? fallback : '';
    }

    return raw;
  }

  static const Set<String> _dawAssistantActionTypes = <String>{
    'tutorial',
    'clarify',
    'clip_edit',
    'effect_edit',
    'automation_edit',
    'midi_compose',
    'stem_separate',
    'role_override',
  };

  int? _parseActionInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
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
  ) {
    final data = Map<String, dynamic>.from(rawData);
    final rawTarget = data['target'];
    final target = rawTarget is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawTarget)
        : (rawTarget is Map ? Map<String, dynamic>.from(rawTarget) : <String, dynamic>{});

    final scopeValue = (data['scope'] ?? target['scope'])?.toString().trim().toLowerCase();
    if (scopeValue != null && scopeValue.isNotEmpty) {
      data['scope'] = scopeValue;
      target['scope'] = scopeValue;
    }

    final rowIndex = _extractNormalizedRowIndex(data, target);
    final isMasterScope =
        (target['scope']?.toString().trim().toLowerCase() ?? data['scope']?.toString().trim().toLowerCase()) ==
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

    if (actionType == 'role_override') {
      final role = (data['role']?.toString().trim().toLowerCase() ?? '');
      if (role.isNotEmpty) {
        data['role'] = role;
      }
    }

    data['target'] = target;
    return data;
  }

  List<Map<String, dynamic>> _normalizeDawAssistantActions(List rawActions) {
    final out = <Map<String, dynamic>>[];
    for (final rawAction in rawActions) {
      if (rawAction is! Map) continue;
      final action = Map<String, dynamic>.from(rawAction);
      final type = (action['type']?.toString().trim().toLowerCase() ?? '');
      if (!_dawAssistantActionTypes.contains(type)) continue;
      final rawData = action['data'];
      final data = rawData is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawData)
          : (rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{});
      out.add({
        'type': type,
        'data': _normalizeDawActionData(type, data),
      });
    }
    return out;
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
      final normalizedActions = _normalizeDawAssistantActions(actions);
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
        final target = goal['target'];
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
        goal['target'] = normalizedTarget;

        final intents = goal['intents'];
        if (intents is! List || intents.isEmpty) return null;
        for (final intent in intents) {
          if (intent is! Map) return null;
        }
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
    String? promptTraceId,
    String? projectId,
    String? aiFeature,
    MixingResult? pendingMix,
  }) async {
    final requestStopwatch = Stopwatch();
    final parseStopwatch = Stopwatch();
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
          promptTraceId: promptTraceId,
          projectId: projectId,
          aiFeature: aiFeature,
          pendingMix: pendingMix,
        );
        requestStopwatch.stop();
      } else if (_canUseDirectOpenAi) {
        if (!_isUsingDebugSystemPrompt) {
          return LlmResult.text(
            'Direct OpenAI debug mode requires a non-empty kDebugSystemPrompt in lib/ai/debug_system_prompt.dart.',
            null,
          );
        }
        final inputMessages = _buildInputMessages(
          conversation: conversation,
          userText: userText,
          projectSnapshot: projectSnapshot,
          selectionSnapshot: selectionSnapshot,
          pendingMix: pendingMix,
        );

        requestStopwatch.start();
        response = await _postJson(
          uri: Uri.parse(_apiUrl),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: _buildOpenAiRequestBody(
            inputMessages: inputMessages,
            aiFeature: aiFeature,
          ),
        );
        requestStopwatch.stop();
      } else {
        return LlmResult.text(
          'AI is not configured. Launch with --dart-define=LLM_PROXY_API_BASE_URL=... or --dart-define=OPENAI_API_KEY=... --dart-define=OPENAI_MODEL=...',
          null,
        );
      }
    } catch (_) {
      return _recoverableTextResult(
        _temporaryFailureMessage,
        softErrorCode: 'request_failed',
      );
    }

    parseStopwatch.start();
    var payload = _decodeJsonObject(response.body);
    var responseMeta = _buildResponseMeta(payload);
    responseMeta = _mergeMetaObservability(responseMeta, <String, dynamic>{
      if ((promptTraceId ?? '').trim().isNotEmpty) 'prompt_trace_id': promptTraceId!.trim(),
      'proxy_roundtrip_ms': requestStopwatch.elapsedMilliseconds,
      'http_status_code': response.statusCode,
      'llm_route': _llmRouteLabel,
      'prompt_source': _promptSourceLabel,
      if (!_isProxyEnabled && _canUseDirectOpenAi) ...<String, dynamic>{
        'provider': 'openai',
        'effective_model': model.trim(),
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

    if (response.statusCode != 200) {
      if (response.statusCode == 429) {
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
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        if (_isProxyEnabled && refreshAuthTokenProvider != null) {
          try {
            final refreshedToken = await _resolveProxyAuthToken(forceRefresh: true);
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
                promptTraceId: promptTraceId,
                projectId: projectId,
                aiFeature: aiFeature,
                pendingMix: pendingMix,
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
                  if ((promptTraceId ?? '').trim().isNotEmpty) 'prompt_trace_id': promptTraceId!.trim(),
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
              } else if (response.statusCode == 429) {
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
              } else if (response.statusCode == 401 || response.statusCode == 403) {
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
          return LlmResult.text(
            _fallbackAssistantText('informational_response'),
            null,
            meta: responseMeta,
          );
        }
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
              return LlmResult.text(
                _fallbackAssistantText('informational_response'),
                null,
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
          if (text is String && text.trim().isNotEmpty && assistantText == null) {
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
      final informationalResults = toolResults.where((t) => t.toolName == 'informational_response');
      final nonInformationalResults = toolResults.where((t) => t.toolName != 'informational_response');

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
        return LlmResult.text(
          _fallbackAssistantText('informational_response'),
          {
            'message': _fallbackAssistantText('informational_response'),
            'cancels_pending': false,
          },
          meta: responseMeta,
        );
      }

      final callArgs =
          nonInformationalResults.map((t) => t.toolArgs).whereType<Map<String, dynamic>>().toList(growable: false);
      final userFacingText = assistantText ??
          nonInformationalResults.map((t) => t.text?.trim() ?? '').firstWhere((t) => t.isNotEmpty, orElse: () => '');

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
    if (assistantText != null && assistantText != _fallbackAssistantText('informational_response')) {
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
