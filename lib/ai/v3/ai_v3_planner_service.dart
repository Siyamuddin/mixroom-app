import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai_model_cost.dart';
import 'ai_v3_context.dart';
import 'ai_v3_contract.dart';
import 'ai_v3_planner_request.dart';
import 'ai_v3_resources.dart';
import 'ai_v3_style_compiler.dart';

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
  const AiV3PlannerResult({
    required this.plan,
    required this.rawResponse,
    required this.meta,
    this.requestBody = const <String, dynamic>{},
  });

  final AiV3Plan plan;
  final Map<String, dynamic> rawResponse;
  final Map<String, dynamic> meta;
  final Map<String, dynamic> requestBody;
}

abstract interface class AiV3Planner {
  String get model;
  String get reasoningEffort;

  Future<AiV3PlannerResult> plan({
    required AiV3CoreContext context,
    required String originalRequest,
    String? promptTraceId,
  });
}

class AiV3PlannerService implements AiV3Planner {
  AiV3PlannerService({
    this.apiKey = '',
    required this.model,
    this.reasoningEffort = 'low',
    this.requestTimeout = const Duration(seconds: 40),
    Set<String> commandTypes = aiV3CommandTypes,
    this.architecture = 'v3_one_shot_prototype',
    this.proxyApiBaseUrl = '',
    this.proxyPath = '/v1/llm/v3/responses',
    this.authTokenProvider,
    this.refreshAuthTokenProvider,
    this.resourceRefsEnabled = false,
    http.Client? httpClient,
  }) : assert(commandTypes.isNotEmpty),
       commandTypes = Set<String>.unmodifiable(commandTypes),
       _httpClient = httpClient ?? http.Client();

  static const String _apiUrl = 'https://api.openai.com/v1/responses';

  final String apiKey;
  @override
  final String model;
  @override
  final String reasoningEffort;
  final Duration requestTimeout;
  final Set<String> commandTypes;
  final String architecture;
  final String proxyApiBaseUrl;
  final String proxyPath;
  final Future<String?> Function()? authTokenProvider;
  final Future<String?> Function()? refreshAuthTokenProvider;
  final bool resourceRefsEnabled;
  final http.Client _httpClient;

  bool get _usesProxy => proxyApiBaseUrl.trim().isNotEmpty;

  @override
  Future<AiV3PlannerResult> plan({
    required AiV3CoreContext context,
    required String originalRequest,
    String? promptTraceId,
  }) async {
    if (model.trim().isEmpty ||
        (!_usesProxy && apiKey.trim().isEmpty) ||
        (_usesProxy && authTokenProvider == null)) {
      throw const AiV3PlannerException('v3_openai_configuration_missing');
    }
    final stopwatch = Stopwatch()..start();
    try {
      final first = await _complete(
        buildAiV3PlannerRequestBody(
          contextData: context.data,
          originalRequest: originalRequest,
          model: model,
          reasoningEffort: reasoningEffort,
          promptTraceId: promptTraceId,
          commandTypes: commandTypes,
          architecture: architecture,
          resourceRefsEnabled: resourceRefsEnabled,
          includeOwnedInstructions: !_usesProxy,
        ),
        context: context,
        promptTraceId: promptTraceId,
        elapsedMs: () => stopwatch.elapsedMilliseconds,
      );
      if (!shouldRetryAiV3AlignTempoCollapse(first.plan)) {
        return first;
      }
      try {
        final retried = await _complete(
          buildAiV3PlannerRequestBody(
            contextData: context.data,
            originalRequest: originalRequest,
            model: model,
            reasoningEffort: reasoningEffort,
            promptTraceId: promptTraceId,
            commandTypes: commandTypes,
            architecture: architecture,
            resourceRefsEnabled: resourceRefsEnabled,
            alignTempoCollapseRetry: true,
            includeOwnedInstructions: !_usesProxy,
          ),
          context: context,
          promptTraceId: promptTraceId,
          elapsedMs: () => stopwatch.elapsedMilliseconds,
        );
        return AiV3PlannerResult(
          plan: retried.plan,
          rawResponse: retried.rawResponse,
          meta: <String, dynamic>{
            ...retried.meta,
            'align_tempo_collapse_retried': true,
          },
          requestBody: retried.requestBody,
        );
      } on AiV3PlannerException {
        return AiV3PlannerResult(
          plan: first.plan,
          rawResponse: first.rawResponse,
          meta: <String, dynamic>{
            ...first.meta,
            'align_tempo_collapse_retried': false,
            'align_tempo_collapse_retry_failed': true,
          },
          requestBody: first.requestBody,
        );
      }
    } finally {
      stopwatch.stop();
    }
  }

  Future<AiV3PlannerResult> _complete(
    Map<String, dynamic> body, {
    required AiV3CoreContext context,
    required String? promptTraceId,
    required int Function() elapsedMs,
  }) async {
    late http.Response response;
    try {
      response = _usesProxy
          ? await _postProxy(body, promptTraceId: promptTraceId)
          : await _postDirect(body);
    } on TimeoutException {
      throw const AiV3PlannerException('v3_planner_timeout');
    }
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
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final errorCode = error is Map
          ? error['code']?.toString().trim() ?? ''
          : '';
      final errorParam = error is Map
          ? error['param']?.toString().trim() ?? ''
          : '';
      final errorMessage = error is Map
          ? error['message']?.toString().trim() ?? ''
          : '';
      final safeMessage = errorMessage
          .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]+\b'), '[redacted]')
          .replaceAll(RegExp(r'\s+'), ' ');
      throw AiV3PlannerException(
        'v3_planner_http_error',
        <String>[
          response.statusCode.toString(),
          errorCode.isEmpty ? 'unknown' : errorCode,
          if (errorParam.isNotEmpty) 'param=$errorParam',
          if (safeMessage.isNotEmpty)
            'message=${safeMessage.substring(0, safeMessage.length > 500 ? 500 : safeMessage.length)}',
        ].join(':'),
      );
    }
    final usage = decoded['usage'] is Map
        ? Map<String, dynamic>.from(decoded['usage'] as Map)
        : const <String, dynamic>{};
    late final Map<String, dynamic> arguments;
    late final AiV3Plan plan;
    try {
      arguments = _functionArguments(decoded);
      plan = AiV3Plan.fromJson(
        arguments,
        allowResourceRefs: resourceRefsEnabled,
        resourceRefCommandTypes: aiV3RuntimeResourceRefConsumerTypes,
      );
      if (plan.commands.any(
        (command) => !commandTypes.contains(command.type),
      )) {
        throw const AiV3ContractException('v3_planner_command_outside_surface');
      }
    } on AiV3ContractException catch (error) {
      throw AiV3PlannerException(
        'v3_planner_contract_invalid',
        error.code,
        <String, dynamic>{
          'raw_response': decoded,
          'tool_arguments': arguments,
          'usage': usage,
        },
      );
    } on AiV3PlannerException catch (error) {
      throw AiV3PlannerException(error.code, error.detail, <String, dynamic>{
        'raw_response': decoded,
        'usage': usage,
      });
    }
    final serviceTier = decoded['service_tier']?.toString() ?? '';
    return AiV3PlannerResult(
      plan: plan,
      rawResponse: decoded,
      meta: <String, dynamic>{
        'architecture': architecture,
        'model': decoded['model']?.toString().trim().isNotEmpty == true
            ? decoded['model'].toString().trim()
            : model,
        'reasoning_effort': reasoningEffort,
        'llm_route': _usesProxy ? 'authenticated_proxy' : 'direct_openai_debug',
        'context_profile': context.profileName,
        'context_approximate_tokens': context.approximateTokens,
        'model_call_elapsed_ms': elapsedMs(),
        'usage': usage,
        if (estimateOpenAiModelCost(
              model: model,
              usage: usage,
              serviceTier: serviceTier,
            )
            case final cost?)
          'cost_estimate': cost,
        'provider_response_id': decoded['id'],
      },
      requestBody: body,
    );
  }

  Future<http.Response> _postDirect(Map<String, dynamic> body) {
    return _httpClient
        .post(
          Uri.parse(_apiUrl),
          headers: <String, String>{
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);
  }

  Future<http.Response> _postProxy(
    Map<String, dynamic> body, {
    String? promptTraceId,
  }) async {
    var token = await _resolveProxyAuthToken();
    if (token == null) {
      throw const AiV3PlannerException('v3_proxy_auth_token_missing');
    }
    var response = await _postProxyWithToken(
      body,
      token: token,
      promptTraceId: promptTraceId,
    );
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        refreshAuthTokenProvider != null) {
      token = await _resolveProxyAuthToken(forceRefresh: true);
      if (token == null) {
        throw const AiV3PlannerException('v3_proxy_auth_token_missing');
      }
      response = await _postProxyWithToken(
        body,
        token: token,
        promptTraceId: promptTraceId,
      );
    }
    return response;
  }

  Future<http.Response> _postProxyWithToken(
    Map<String, dynamic> body, {
    required String token,
    String? promptTraceId,
  }) {
    final normalizedTraceId = (promptTraceId ?? '').trim();
    final proxyBody = <String, dynamic>{
      ...body,
      'ai_feature': 'ai_chat_v3',
      'client_context': <String, dynamic>{'ai_architecture': architecture},
      if (normalizedTraceId.isNotEmpty) 'prompt_trace_id': normalizedTraceId,
    };
    return _httpClient
        .post(
          _proxyUri(),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(proxyBody),
        )
        .timeout(requestTimeout);
  }

  Future<String?> _resolveProxyAuthToken({bool forceRefresh = false}) async {
    final provider = forceRefresh
        ? refreshAuthTokenProvider
        : authTokenProvider;
    final token = (await provider?.call())?.trim() ?? '';
    if (token.isNotEmpty) return token;
    if (!forceRefresh && refreshAuthTokenProvider != null) {
      final refreshed = (await refreshAuthTokenProvider!.call())?.trim() ?? '';
      if (refreshed.isNotEmpty) return refreshed;
    }
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

Map<String, dynamic> _functionArguments(Map<String, dynamic> response) {
  final output = response['output'];
  if (output is! List) {
    throw const AiV3PlannerException('v3_planner_tool_call_missing');
  }
  final calls = output
      .whereType<Map>()
      .where((value) => value['type'] == 'function_call')
      .toList(growable: false);
  if (calls.isEmpty) {
    throw const AiV3PlannerException('v3_planner_tool_call_missing');
  }
  if (calls.length != 1) {
    throw const AiV3PlannerException('v3_planner_tool_call_count_invalid');
  }
  final call = calls.single;
  if (call['name'] != 'submit_plan_v3') {
    throw const AiV3PlannerException('v3_planner_tool_call_invalid');
  }
  final rawArguments = call['arguments'];
  if (rawArguments is Map) {
    return Map<String, dynamic>.from(rawArguments);
  }
  if (rawArguments is String) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const AiV3PlannerException('v3_planner_arguments_invalid_json');
    }
  }
  throw const AiV3PlannerException('v3_planner_arguments_invalid_json');
}
