import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import 'ai_v3_context.dart';
import 'ai_v3_contract.dart';
import 'ai_v3_resources.dart';

const String aiV3ContextRequestContract = 'mixroom_v3_context_v2';
const String aiV3ServerResponseVersion = 'v3_plan_response_server_v1';
const int aiV3MaxSerializedRequestBytes = 4500000;
const int _aiV3LegacyMaxSerializedRequestBytes = 180000;
const int _aiV3LegacyMaxCoreContextBytes = 140000;

const Set<String> _allowedResponseFields = <String>{
  'schema_version',
  'plan',
  'trace',
  'prompt_rate_limit',
};
const Set<String> _allowedTraceFields = <String>{
  'contract_version',
  'contract_fingerprint',
  'prompt_trace_id',
  'request_id',
};

class AiV3PlannerException implements Exception {
  const AiV3PlannerException(
    this.code, [
    this.detail = '',
    this.diagnostic = const <String, dynamic>{},
  ]);

  final String code;
  final String detail;
  final Map<String, dynamic> diagnostic;

  @override
  String toString() => detail.isEmpty
      ? 'AiV3PlannerException($code)'
      : 'AiV3PlannerException($code): $detail';
}

class AiV3PlannerResult {
  const AiV3PlannerResult({required this.plan, required this.meta});

  final AiV3Plan plan;
  final Map<String, dynamic> meta;
}

abstract interface class AiV3Planner {
  Future<AiV3PlannerResult> plan({
    required AiV3CoreContext context,
    required String originalRequest,
    String? promptTraceId,
  });
}

Map<String, dynamic> buildAiV3ContextRequestBody({
  required Map<String, dynamic> contextData,
  required String originalRequest,
  String? promptTraceId,
  Set<String> commandTypes = aiV3CommandTypes,
  bool resourceRefsEnabled = false,
}) {
  final coreContext = Map<String, dynamic>.from(contextData)
    ..remove('original_request')
    ..remove('conversation');
  final rawConversation = contextData['conversation'];
  final conversation = <Map<String, String>>[];
  if (rawConversation is List) {
    for (final rawTurn in rawConversation.whereType<Map>()) {
      final role = rawTurn['role']?.toString().trim() ?? '';
      final content = rawTurn['content']?.toString().trim() ?? '';
      if ((role == 'user' || role == 'assistant') && content.isNotEmpty) {
        conversation.add(<String, String>{'role': role, 'content': content});
      }
    }
  }
  final boundedConversation = conversation.length <= 12
      ? conversation
      : conversation.sublist(conversation.length - 12);
  final project = coreContext['project'];
  final projectId = project is Map
      ? project['project_id']?.toString().trim() ?? ''
      : '';
  final normalizedTraceId = (promptTraceId ?? '').trim();
  final sortedCommandTypes = commandTypes.toList(growable: false)..sort();
  return <String, dynamic>{
    'request_contract': aiV3ContextRequestContract,
    'original_request': originalRequest.trim(),
    'conversation': boundedConversation,
    'core_context': coreContext,
    'plan_schema_version': aiV3PlanVersion,
    'supported_command_types': sortedCommandTypes,
    'resource_refs_enabled': resourceRefsEnabled,
    if (projectId.isNotEmpty) 'project_id': projectId,
    if (normalizedTraceId.isNotEmpty) 'prompt_trace_id': normalizedTraceId,
  };
}

class AiV3PlannerService implements AiV3Planner {
  AiV3PlannerService({
    required this.proxyApiBaseUrl,
    this.proxyPath = '/v1/llm/v3/responses',
    this.authTokenProvider,
    this.refreshAuthTokenProvider,
    this.requestTimeout = const Duration(seconds: 40),
    Set<String> commandTypes = aiV3CommandTypes,
    this.resourceRefsEnabled = false,
    http.Client? httpClient,
  }) : assert(commandTypes.isNotEmpty),
       commandTypes = Set<String>.unmodifiable(commandTypes),
       _httpClient = httpClient ?? http.Client();

  final String proxyApiBaseUrl;
  final String proxyPath;
  final Future<String?> Function()? authTokenProvider;
  final Future<String?> Function()? refreshAuthTokenProvider;
  final Duration requestTimeout;
  final Set<String> commandTypes;
  final bool resourceRefsEnabled;
  final http.Client _httpClient;

  @override
  Future<AiV3PlannerResult> plan({
    required AiV3CoreContext context,
    required String originalRequest,
    String? promptTraceId,
  }) async {
    if (proxyApiBaseUrl.trim().isEmpty || authTokenProvider == null) {
      throw const AiV3PlannerException('v3_proxy_configuration_missing');
    }
    final body = buildAiV3ContextRequestBody(
      contextData: context.data,
      originalRequest: originalRequest,
      promptTraceId: promptTraceId,
      commandTypes: commandTypes,
      resourceRefsEnabled: resourceRefsEnabled,
    );
    final encodedBody = jsonEncode(body);
    final requestBodyBytes = utf8.encode(encodedBody).length;
    final project = context.data['project'];
    final usesDynamicCapacity =
        project is Map &&
        project['project_capacity_policy'] == aiV3ProjectCapacityPolicy;
    final maximumRequestBytes = usesDynamicCapacity
        ? aiV3MaxSerializedRequestBytes
        : _aiV3LegacyMaxSerializedRequestBytes;
    final maximumCoreContextBytes = usesDynamicCapacity
        ? AiV3CoreContextBuilder.maxCanonicalBytes
        : _aiV3LegacyMaxCoreContextBytes;
    // Match contract-6 byte envelopes before authentication or network access.
    // Existing notes are sent completely; never trim a project to fit.
    if (requestBodyBytes > maximumRequestBytes ||
        utf8.encode(jsonEncode(body['core_context'])).length >
            maximumCoreContextBytes) {
      throw const AiV3PlannerException('v3_context_request_limit');
    }
    final stopwatch = Stopwatch()..start();
    var requestStage = 'auth';
    try {
      final response = await _postProxy(
        encodedBody,
        onStageChanged: (stage) => requestStage = stage,
      );
      stopwatch.stop();
      late final AiV3PlannerResult result;
      try {
        result = _parseResponse(response);
      } on AiV3PlannerException catch (error) {
        // Explicit local debugging only; never include response text or IDs.
        if (kDebugMode &&
            const bool.fromEnvironment('AI_V3_LOCAL_VALIDATION_DIAGNOSTICS')) {
          final detail =
              error.code == 'v3_planner_contract_invalid' &&
                  RegExp(r'^v3_[a-zA-Z0-9_.]{1,140}$').hasMatch(error.detail)
              ? error.detail
              : null;
          debugPrint(
            '[AI.v3-validation] ${jsonEncode(<String, dynamic>{'code': error.code, if (detail != null) 'contract_error_code': detail, 'http_status': response.statusCode, 'elapsed_ms': stopwatch.elapsedMilliseconds, 'request_timeout_ms': requestTimeout.inMilliseconds})}',
          );
        }
        throw AiV3PlannerException(error.code, error.detail, <String, dynamic>{
          ...error.diagnostic,
          'stage': 'proxy_response',
          if ((promptTraceId ?? '').trim().isNotEmpty)
            'prompt_trace_id': promptTraceId!.trim(),
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'request_timeout_ms': requestTimeout.inMilliseconds,
          'request_body_bytes': requestBodyBytes,
        });
      }
      return AiV3PlannerResult(
        plan: result.plan,
        meta: <String, dynamic>{
          ...result.meta,
          'v3_planner_request_ms': stopwatch.elapsedMilliseconds,
          'v3_request_body_bytes': requestBodyBytes,
        },
      );
    } on TimeoutException {
      stopwatch.stop();
      throw AiV3PlannerException('v3_planner_timeout', '', <String, dynamic>{
        'stage': requestStage,
        if ((promptTraceId ?? '').trim().isNotEmpty)
          'prompt_trace_id': promptTraceId!.trim(),
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'request_timeout_ms': requestTimeout.inMilliseconds,
        'request_body_bytes': requestBodyBytes,
      });
    }
  }

  AiV3PlannerResult _parseResponse(http.Response response) {
    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(response.body);
      decoded = value is Map
          ? Map<String, dynamic>.from(value)
          : const <String, dynamic>{};
    } catch (_) {
      throw AiV3PlannerException(
        'v3_planner_response_invalid_json',
        'http_${response.statusCode}',
        <String, dynamic>{'http_status': response.statusCode},
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawError = decoded['error'];
      final rawCode = rawError is Map ? rawError['code']?.toString() ?? '' : '';
      final safeCode = RegExp(r'^[a-z0-9_]{1,80}$').hasMatch(rawCode)
          ? rawCode
          : 'server_error';
      final isTimeout =
          response.statusCode == 504 || safeCode == 'v3_upstream_timeout';
      throw AiV3PlannerException(
        isTimeout
            ? 'v3_planner_timeout'
            : safeCode == 'v3_context_request_limit'
            ? 'v3_context_request_limit'
            : 'v3_planner_http_error',
        'http_${response.statusCode}:$safeCode',
        <String, dynamic>{
          'http_status': response.statusCode,
          'server_error_code': safeCode,
        },
      );
    }
    if (decoded['schema_version'] != aiV3ServerResponseVersion ||
        decoded.keys.any((key) => !_allowedResponseFields.contains(key))) {
      throw const AiV3PlannerException('v3_server_response_contract_invalid');
    }
    final rawTrace = decoded['trace'];
    if (rawTrace is! Map ||
        rawTrace.keys.any((key) => !_allowedTraceFields.contains(key))) {
      throw const AiV3PlannerException('v3_server_response_contract_invalid');
    }
    final trace = <String, String>{};
    for (final key in _allowedTraceFields) {
      final value = rawTrace[key];
      if (value is String && value.trim().isNotEmpty) {
        trace[key] = value.trim();
      }
    }
    if ((trace['contract_version'] ?? '').isEmpty ||
        (trace['contract_fingerprint'] ?? '').isEmpty) {
      throw const AiV3PlannerException('v3_server_response_contract_invalid');
    }
    final rawPlan = decoded['plan'];
    if (rawPlan is! Map) {
      throw const AiV3PlannerException('v3_server_response_contract_invalid');
    }
    late final AiV3Plan plan;
    try {
      plan = AiV3Plan.fromJson(
        Map<String, dynamic>.from(rawPlan),
        allowResourceRefs: resourceRefsEnabled,
        resourceRefCommandTypes: aiV3RuntimeResourceRefConsumerTypes,
      );
      if (plan.commands.any(
        (command) => !commandTypes.contains(command.type),
      )) {
        throw const AiV3ContractException('v3_planner_command_outside_surface');
      }
    } on AiV3ContractException catch (error) {
      throw AiV3PlannerException('v3_planner_contract_invalid', error.code);
    }
    final rateLimit = _sanitizePromptRateLimit(decoded['prompt_rate_limit']);
    return AiV3PlannerResult(
      plan: plan,
      meta: <String, dynamic>{
        'trace': trace,
        if (rateLimit.isNotEmpty) 'prompt_rate_limit': rateLimit,
      },
    );
  }

  Map<String, dynamic> _sanitizePromptRateLimit(Object? raw) {
    if (raw is! Map) return const <String, dynamic>{};
    Map<String, dynamic> window(Object? value) {
      if (value is! Map) return const <String, dynamic>{};
      return <String, dynamic>{
        for (final key in const <String>['used', 'limit', 'remaining'])
          if (value[key] is num) key: value[key],
        if (value['resets_at'] is String)
          'resets_at': (value['resets_at'] as String).trim(),
      };
    }

    final extra = raw['extra_prompt_bank'];
    return <String, dynamic>{
      if (window(raw['daily']).isNotEmpty) 'daily': window(raw['daily']),
      if (window(raw['weekly']).isNotEmpty) 'weekly': window(raw['weekly']),
      if (raw['can_submit'] is bool) 'can_submit': raw['can_submit'],
      if (raw['blocked_by'] is String)
        'blocked_by': (raw['blocked_by'] as String).trim(),
      if (extra is Map)
        'extra_prompt_bank': <String, dynamic>{
          if (extra['remaining'] is num) 'remaining': extra['remaining'],
          if (extra['consumed_first'] is bool)
            'consumed_first': extra['consumed_first'],
        },
    };
  }

  Future<http.Response> _postProxy(
    String encodedBody, {
    void Function(String stage)? onStageChanged,
  }) async {
    onStageChanged?.call('auth');
    var token = await _resolveProxyAuthToken(authTokenProvider);
    var refreshUsed = false;
    if (token == null && refreshAuthTokenProvider != null) {
      refreshUsed = true;
      onStageChanged?.call('auth_refresh');
      token = await _resolveProxyAuthToken(refreshAuthTokenProvider);
    }
    if (token == null) {
      throw const AiV3PlannerException('v3_proxy_auth_token_missing');
    }
    onStageChanged?.call('proxy_roundtrip');
    var response = await _postProxyWithToken(encodedBody, token: token);
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        !refreshUsed &&
        refreshAuthTokenProvider != null) {
      refreshUsed = true;
      onStageChanged?.call('auth_refresh');
      token = await _resolveProxyAuthToken(refreshAuthTokenProvider);
      if (token == null) {
        throw const AiV3PlannerException('v3_proxy_auth_token_missing');
      }
      onStageChanged?.call('proxy_roundtrip');
      response = await _postProxyWithToken(encodedBody, token: token);
    }
    return response;
  }

  Future<http.Response> _postProxyWithToken(
    String encodedBody, {
    required String token,
  }) => _httpClient
      .post(
        _proxyUri(),
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: encodedBody,
      )
      .timeout(requestTimeout);

  Future<String?> _resolveProxyAuthToken(
    Future<String?> Function()? provider,
  ) async {
    final token = (await provider?.call())?.trim() ?? '';
    if (token.isNotEmpty) return token;
    return null;
  }

  Uri _proxyUri() {
    final base = proxyApiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    final configuredPath = proxyPath.trim();
    final path = configuredPath.isEmpty
        ? '/v1/llm/v3/responses'
        : (configuredPath.startsWith('/')
              ? configuredPath
              : '/$configuredPath');
    return Uri.parse('$base$path');
  }
}
