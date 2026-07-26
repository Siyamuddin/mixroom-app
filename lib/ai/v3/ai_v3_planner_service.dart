import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai_model_cost.dart';
import 'ai_v3_context.dart';
import 'ai_v3_contract.dart';
import 'ai_v3_planner_request.dart';

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
    required this.apiKey,
    required this.model,
    this.reasoningEffort = 'low',
    this.requestTimeout = const Duration(seconds: 40),
    Set<String> commandTypes = aiV3CommandTypes,
    this.architecture = 'v3_one_shot_prototype',
    http.Client? httpClient,
  })  : assert(commandTypes.isNotEmpty),
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
  final http.Client _httpClient;

  @override
  Future<AiV3PlannerResult> plan({
    required AiV3CoreContext context,
    required String originalRequest,
    String? promptTraceId,
  }) async {
    if (apiKey.trim().isEmpty || model.trim().isEmpty) {
      throw const AiV3PlannerException('v3_openai_configuration_missing');
    }
    final body = buildAiV3PlannerRequestBody(
      contextData: context.data,
      originalRequest: originalRequest,
      model: model,
      reasoningEffort: reasoningEffort,
      promptTraceId: promptTraceId,
      commandTypes: commandTypes,
      architecture: architecture,
    );
    final stopwatch = Stopwatch()..start();
    late http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(_apiUrl),
            headers: <String, String>{
              'Authorization': 'Bearer ${apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const AiV3PlannerException('v3_planner_timeout');
    } finally {
      stopwatch.stop();
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
      final errorCode =
          error is Map ? error['code']?.toString().trim() ?? '' : '';
      final errorParam =
          error is Map ? error['param']?.toString().trim() ?? '' : '';
      final errorMessage =
          error is Map ? error['message']?.toString().trim() ?? '' : '';
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
      plan = AiV3Plan.fromJson(arguments);
      if (plan.commands
          .any((command) => !commandTypes.contains(command.type))) {
        throw const AiV3ContractException(
          'v3_planner_command_outside_surface',
        );
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
      throw AiV3PlannerException(
        error.code,
        error.detail,
        <String, dynamic>{
          'raw_response': decoded,
          'usage': usage,
        },
      );
    }
    final serviceTier = decoded['service_tier']?.toString() ?? '';
    return AiV3PlannerResult(
      plan: plan,
      rawResponse: decoded,
      meta: <String, dynamic>{
        'architecture': architecture,
        'model': model,
        'reasoning_effort': reasoningEffort,
        'context_profile': context.profileName,
        'context_approximate_tokens': context.approximateTokens,
        'model_call_elapsed_ms': stopwatch.elapsedMilliseconds,
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
