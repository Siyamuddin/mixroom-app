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

const Set<String> _diagnosableServerValidationCodes = <String>{
  'v3_capability_context_invalid',
  'v3_capability_context_duplicate',
  'v3_capability_context_limit',
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

class AiV3PlannerDiagnostic {
  const AiV3PlannerDiagnostic({
    required this.stage,
    required this.promptTraceId,
    required this.elapsedMs,
    this.status = 'progress',
    this.errorCode,
    this.fields = const <String, Object?>{},
  });

  final String stage;
  final String promptTraceId;
  final int elapsedMs;
  final String status;
  final String? errorCode;
  final Map<String, Object?> fields;
}

typedef AiV3PlannerDiagnosticCallback = void Function(
  AiV3PlannerDiagnostic diagnostic,
);

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
    this.onDiagnostic,
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
  final AiV3PlannerDiagnosticCallback? onDiagnostic;
  final http.Client _httpClient;

  void _emitDiagnostic(AiV3PlannerDiagnostic diagnostic) {
    try {
      onDiagnostic?.call(diagnostic);
    } catch (_) {
      // Diagnostics must never alter the request path.
    }
  }

  @override
  Future<AiV3PlannerResult> plan({
    required AiV3CoreContext context,
    required String originalRequest,
    String? promptTraceId,
  }) async {
    if (proxyApiBaseUrl.trim().isEmpty || authTokenProvider == null) {
      _emitDiagnostic(
        AiV3PlannerDiagnostic(
          stage: 'configuration',
          promptTraceId: (promptTraceId ?? '').trim(),
          elapsedMs: 0,
          status: 'failed',
          errorCode: 'v3_proxy_configuration_missing',
          fields: <String, Object?>{
            'proxy_base_url_present': proxyApiBaseUrl.trim().isNotEmpty,
            'auth_provider_present': authTokenProvider != null,
          },
        ),
      );
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
    final coreContextBytes = utf8
        .encode(jsonEncode(body['core_context']))
        .length;
    final requestShape = _diagnosticRequestShape(body);
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
    _emitDiagnostic(
      AiV3PlannerDiagnostic(
        stage: 'request_prepared',
        promptTraceId: (promptTraceId ?? '').trim(),
        elapsedMs: 0,
        fields: <String, Object?>{
          'request_body_bytes': requestBodyBytes,
          'core_context_bytes': coreContextBytes,
          'request_body_limit_bytes': maximumRequestBytes,
          'core_context_limit_bytes': maximumCoreContextBytes,
          'dynamic_capacity': usesDynamicCapacity,
          ...requestShape,
          'library_asset_count_total': context.libraryAssetCountTotal,
          'library_asset_count_included': context.libraryAssetCountIncluded,
          'library_asset_count_omitted': context.libraryAssetCountOmitted,
          'library_asset_compacted': context.libraryAssetCountOmitted > 0,
        },
      ),
    );
    if (requestBodyBytes > maximumRequestBytes ||
        coreContextBytes > maximumCoreContextBytes) {
      _emitDiagnostic(
        AiV3PlannerDiagnostic(
          stage: 'request_preflight',
          promptTraceId: (promptTraceId ?? '').trim(),
          elapsedMs: 0,
          status: 'failed',
          errorCode: 'v3_context_request_limit',
          fields: <String, Object?>{
            'request_body_bytes': requestBodyBytes,
            'core_context_bytes': coreContextBytes,
          },
        ),
      );
      throw const AiV3PlannerException('v3_context_request_limit');
    }
    final stopwatch = Stopwatch()..start();
    var requestStage = 'auth';
    try {
      final response = await _postProxy(
        encodedBody,
        onStageChanged: (stage) {
          requestStage = stage;
          _emitDiagnostic(
            AiV3PlannerDiagnostic(
              stage: stage,
              promptTraceId: (promptTraceId ?? '').trim(),
              elapsedMs: stopwatch.elapsedMilliseconds,
            ),
          );
        },
      );
      stopwatch.stop();
      _emitDiagnostic(
        AiV3PlannerDiagnostic(
          stage: 'response_received',
          promptTraceId: (promptTraceId ?? '').trim(),
          elapsedMs: stopwatch.elapsedMilliseconds,
          status: response.statusCode >= 200 && response.statusCode < 300
              ? 'success'
              : 'failed',
          fields: <String, Object?>{
            'http_status': response.statusCode,
            ..._diagnosticResponseMetadata(response),
          },
        ),
      );
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
        _emitDiagnostic(
          AiV3PlannerDiagnostic(
            stage: 'response_parse',
            promptTraceId: (promptTraceId ?? '').trim(),
            elapsedMs: stopwatch.elapsedMilliseconds,
            status: 'failed',
            errorCode: error.code,
            fields: <String, Object?>{
              'http_status': response.statusCode,
              if (error.diagnostic['server_error_code'] != null)
                'server_error_code': error.diagnostic['server_error_code'],
              if (error.diagnostic['server_validation_reason'] != null)
                'server_validation_reason':
                    error.diagnostic['server_validation_reason'],
              if (error.diagnostic['server_request_id'] != null)
                'server_request_id': error.diagnostic['server_request_id'],
              if (error.diagnostic['response_body_bytes'] != null)
                'response_body_bytes': error.diagnostic['response_body_bytes'],
              if (error.diagnostic['response_content_type'] != null)
                'response_content_type':
                    error.diagnostic['response_content_type'],
            },
          ),
        );
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
      _emitDiagnostic(
        AiV3PlannerDiagnostic(
          stage: 'response_parse',
          promptTraceId: (promptTraceId ?? '').trim(),
          elapsedMs: stopwatch.elapsedMilliseconds,
          status: 'success',
          fields: <String, Object?>{
            'plan_outcome': result.plan.outcome,
            'plan_command_count': result.plan.commands.length,
            if (result.meta['trace'] is Map)
              'server_request_id': (result.meta['trace'] as Map)['request_id']
                  ?.toString(),
            if (result.meta['trace'] is Map)
              'server_contract_version':
                  (result.meta['trace'] as Map)['contract_version']?.toString(),
          },
        ),
      );
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
      _emitDiagnostic(
        AiV3PlannerDiagnostic(
          stage: requestStage,
          promptTraceId: (promptTraceId ?? '').trim(),
          elapsedMs: stopwatch.elapsedMilliseconds,
          status: 'failed',
          errorCode: 'v3_planner_timeout',
          fields: <String, Object?>{
            'request_timeout_ms': requestTimeout.inMilliseconds,
            'request_body_bytes': requestBodyBytes,
          },
        ),
      );
      throw AiV3PlannerException('v3_planner_timeout', '', <String, dynamic>{
        'stage': requestStage,
        if ((promptTraceId ?? '').trim().isNotEmpty)
          'prompt_trace_id': promptTraceId!.trim(),
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'request_timeout_ms': requestTimeout.inMilliseconds,
        'request_body_bytes': requestBodyBytes,
      });
    } on AiV3PlannerException catch (error) {
      stopwatch.stop();
      _emitDiagnostic(
        AiV3PlannerDiagnostic(
          stage: requestStage,
          promptTraceId: (promptTraceId ?? '').trim(),
          elapsedMs: stopwatch.elapsedMilliseconds,
          status: 'failed',
          errorCode: error.code,
          fields: <String, Object?>{
            'request_timeout_ms': requestTimeout.inMilliseconds,
            'request_body_bytes': requestBodyBytes,
          },
        ),
      );
      throw AiV3PlannerException(error.code, error.detail, <String, dynamic>{
        ...error.diagnostic,
        'stage': error.diagnostic['stage'] ?? requestStage,
        if ((promptTraceId ?? '').trim().isNotEmpty)
          'prompt_trace_id': promptTraceId!.trim(),
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'request_timeout_ms': requestTimeout.inMilliseconds,
        'request_body_bytes': requestBodyBytes,
      });
    } catch (error) {
      stopwatch.stop();
      _emitDiagnostic(
        AiV3PlannerDiagnostic(
          stage: requestStage,
          promptTraceId: (promptTraceId ?? '').trim(),
          elapsedMs: stopwatch.elapsedMilliseconds,
          status: 'failed',
          errorCode: 'v3_planner_transport_error',
          fields: <String, Object?>{
            'error_type': error.runtimeType.toString(),
            'request_timeout_ms': requestTimeout.inMilliseconds,
            'request_body_bytes': requestBodyBytes,
          },
        ),
      );
      throw AiV3PlannerException(
        'v3_planner_transport_error',
        '',
        <String, dynamic>{
          'stage': requestStage,
          if ((promptTraceId ?? '').trim().isNotEmpty)
            'prompt_trace_id': promptTraceId!.trim(),
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'request_timeout_ms': requestTimeout.inMilliseconds,
          'request_body_bytes': requestBodyBytes,
          'error_type': error.runtimeType.toString(),
        },
      );
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
        <String, dynamic>{
          'http_status': response.statusCode,
          ..._diagnosticResponseMetadata(response),
        },
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawError = decoded['error'];
      final rawCode = rawError is Map ? rawError['code']?.toString() ?? '' : '';
      final safeCode = RegExp(r'^[a-z0-9_]{1,80}$').hasMatch(rawCode)
          ? rawCode
          : 'server_error';
      final validationReason = _safeServerValidationReason(
        code: safeCode,
        rawMessage: rawError is Map ? rawError['message'] : null,
      );
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
          if (validationReason != null)
            'server_validation_reason': validationReason,
          ..._diagnosticResponseMetadata(response),
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

Map<String, Object?> _diagnosticRequestShape(Map<String, dynamic> body) {
  final coreContext = body['core_context'];
  if (coreContext is! Map) {
    return const <String, Object?>{'core_context_is_object': false};
  }
  final rows = coreContext['rows'] is List
      ? coreContext['rows'] as List
      : const <Object>[];
  final clips = coreContext['clips'] is List
      ? coreContext['clips'] as List
      : const <Object>[];
  final groups = coreContext['groups'] is List
      ? coreContext['groups'] as List
      : const <Object>[];
  final effects = coreContext['effects'] is List
      ? coreContext['effects'] as List
      : const <Object>[];
  final instruments = coreContext['instruments'] is List
      ? coreContext['instruments'] as List
      : const <Object>[];
  final instrumentCatalog = coreContext['instrument_catalog'] is List
      ? coreContext['instrument_catalog'] as List
      : const <Object>[];
  final libraryAssets = coreContext['library_assets'] is List
      ? coreContext['library_assets'] as List
      : const <Object>[];
  final conversation = body['conversation'] is List
      ? body['conversation'] as List
      : const <Object>[];
  final supportedCommands = body['supported_command_types'] is List
      ? body['supported_command_types'] as List
      : const <Object>[];
  final project = coreContext['project'];
  final rowCapacity = project is Map ? project['row_capacity'] : null;

  int countKind(List<Object?> values, String key, String expected) => values
      .whereType<Map>()
      .where((value) => value[key]?.toString() == expected)
      .length;
  int nestedListCount(List<Object?> values, String key) =>
      values.whereType<Map>().fold<int>(
        0,
        (total, value) =>
            total + (value[key] is List ? (value[key] as List).length : 0),
      );

  final knownRowKinds =
      countKind(rows, 'lane_kind', 'audio') +
      countKind(rows, 'lane_kind', 'instrument');
  final knownClipKinds =
      countKind(clips, 'kind', 'audio') + countKind(clips, 'kind', 'midi');
  return <String, Object?>{
    'core_context_is_object': true,
    'request_contract': body['request_contract']?.toString() ?? '',
    'plan_schema_version': body['plan_schema_version']?.toString() ?? '',
    'core_context_schema_version':
        coreContext['schema_version']?.toString() ?? '',
    'context_profile': coreContext['profile']?.toString() ?? '',
    'conversation_turn_count': conversation.length,
    'supported_command_type_count': supportedCommands.length,
    'resource_refs_enabled': body['resource_refs_enabled'] == true,
    'row_count': rows.length,
    'audio_row_count': countKind(rows, 'lane_kind', 'audio'),
    'instrument_row_count': countKind(rows, 'lane_kind', 'instrument'),
    'unknown_row_lane_count': rows.length - knownRowKinds,
    'clip_count': clips.length,
    'audio_clip_count': countKind(clips, 'kind', 'audio'),
    'midi_clip_count': countKind(clips, 'kind', 'midi'),
    'unknown_clip_kind_count': clips.length - knownClipKinds,
    'midi_note_count': nestedListCount(clips, 'midi_notes'),
    'group_count': groups.length,
    'group_member_count': nestedListCount(groups, 'member_row_ids'),
    'effect_catalog_count': effects.length,
    'effect_parameter_count': nestedListCount(effects, 'parameters'),
    'row_effect_instance_count': nestedListCount(rows, 'effects'),
    'selectable_instrument_count': instruments.length,
    'instrument_catalog_count': instrumentCatalog.length,
    'library_asset_count_in_request': libraryAssets.length,
    'row_capacity_present': rowCapacity is Map,
    if (rowCapacity is Map) ...<String, Object?>{
      'row_capacity_current_rows': rowCapacity['current_rows'] is num
          ? rowCapacity['current_rows'] as num
          : null,
      'row_capacity_has_creation_limit': rowCapacity.containsKey(
        'creation_limit',
      ),
      'row_capacity_creation_limit_is_null':
          rowCapacity.containsKey('creation_limit') &&
          rowCapacity['creation_limit'] == null,
      'row_capacity_has_max_rows': rowCapacity.containsKey('max_rows'),
      'row_capacity_can_create': rowCapacity['can_create'] is bool
          ? rowCapacity['can_create'] as bool
          : null,
    },
  };
}

Map<String, Object?> _diagnosticResponseMetadata(http.Response response) {
  final contentType = response.headers['content-type']?.trim() ?? '';
  String? requestId;
  for (final header in const <String>[
    'x-request-id',
    'x-amzn-requestid',
    'x-amz-apigw-id',
    'cf-ray',
  ]) {
    final value = response.headers[header]?.trim() ?? '';
    if (RegExp(r'^[A-Za-z0-9._:-]{1,160}$').hasMatch(value)) {
      requestId = value;
      break;
    }
  }
  return <String, Object?>{
    'response_body_bytes': utf8.encode(response.body).length,
    if (contentType.isNotEmpty && contentType.length <= 120)
      'response_content_type': contentType,
    if (requestId != null) 'server_request_id': requestId,
  };
}

String? _safeServerValidationReason({
  required String code,
  required Object? rawMessage,
}) {
  if (!_diagnosableServerValidationCodes.contains(code) ||
      rawMessage is! String) {
    return null;
  }
  final message = rawMessage.trim();
  if (message.isEmpty ||
      message.length > 256 ||
      message.contains('\n') ||
      message.contains('\r') ||
      !RegExp(r"^[A-Za-z0-9_'.,()\[\] -]+$").hasMatch(message)) {
    return null;
  }
  return message;
}
