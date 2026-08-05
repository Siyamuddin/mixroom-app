import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai_model_cost.dart';
import 'ai_v3_compact_core.dart';
import 'ai_v3_contract.dart';
import 'ai_v3_planner_request.dart';
import 'ai_v3_planning_snapshot.dart';
import 'ai_v3_retrieval.dart';
import 'ai_v3_user_facing_text.dart';

const String aiV3AdaptiveArchitecture = 'v3_adaptive_shadow';
const String aiV3AdaptiveSurfaceRevision = 'full_commands_fact_retrieval_v1';

const String aiV3AdaptiveFirstTurnInstructions = '''
You are Mixroom's sole semantic and musical planner.
$aiV3CustomerLanguageInstructions
Preserve the complete original request and its explicit constraints. Treat
supplied project state and stable IDs as factual authority. Use general musical
knowledge for interpretation, but never invent project resources or state.
Return a complete final plan when compact context and common commands are
sufficient. Otherwise request only the enabled domain facts needed to complete
the entire request, including every required domain in the single batch. Use the
capability directory to identify which domain owns missing functionality. Do not
request context for an ordinary common edit.
$aiV3MidiTimingInstructions
Clarify only ambiguity that materially changes the result; never choose an
ambiguous target arbitrarily. The application owns factual preparation and
execution. Never claim unexecuted work was applied. Match the language of the
latest user request.
''';

const String aiV3AdaptiveContinuationInstructions = '''
You are Mixroom's sole semantic and musical planner on the final continuation.
$aiV3CustomerLanguageInstructions
Use the unchanged original request, compact context, exact retrieval request,
and returned immutable facts to produce one complete final plan. No further
context request is available. Treat supplied project state and stable IDs as
factual authority, use only supplied commands, and preserve every explicit
target and constraint. Use general musical knowledge for interpretation, but
never invent project resources or state.
$aiV3MidiTimingInstructions
Clarify only ambiguity that materially changes the result; never choose an
ambiguous target arbitrarily. Never claim unexecuted work was applied. Match the
language of the latest user request.
''';

class AiV3AdaptivePlannerException implements Exception {
  const AiV3AdaptivePlannerException(
    this.code, [
    this.detail = '',
    this.diagnostic = const <String, dynamic>{},
  ]);

  final String code;
  final String detail;
  final Map<String, dynamic> diagnostic;

  @override
  String toString() => detail.isEmpty
      ? 'AiV3AdaptivePlannerException($code)'
      : 'AiV3AdaptivePlannerException($code): $detail';
}

class AiV3AdaptivePlannerResult {
  const AiV3AdaptivePlannerResult({
    required this.plan,
    required this.firstRawResponse,
    required this.secondRawResponse,
    required this.retrievalRequest,
    required this.retrievalResult,
    required this.firstRequestBody,
    required this.secondRequestBody,
    required this.meta,
  });

  final AiV3Plan plan;
  final Map<String, dynamic> firstRawResponse;
  final Map<String, dynamic>? secondRawResponse;
  final AiV3ContextRequest? retrievalRequest;
  final AiV3ContextResult? retrievalResult;
  final Map<String, dynamic> firstRequestBody;
  final Map<String, dynamic>? secondRequestBody;
  final Map<String, dynamic> meta;

  int get callCount => secondRawResponse == null ? 1 : 2;

  Map<String, dynamic> toCaptureJson() => <String, dynamic>{
        'plan': plan.toJson(),
        'first_request_body': firstRequestBody,
        'first_raw_output': firstRawResponse,
        if (retrievalRequest != null)
          'retrieval_request': retrievalRequest!.toJson(),
        if (retrievalResult != null)
          'retrieval_result': retrievalResult!.toJson(),
        if (secondRequestBody != null) 'second_request_body': secondRequestBody,
        if (secondRawResponse != null) 'second_raw_output': secondRawResponse,
        'metrics': meta,
      };
}

abstract interface class AiV3AdaptivePlanner {
  String get model;
  String get reasoningEffort;

  Future<AiV3AdaptivePlannerResult> plan({
    required CompactCoreV3 compactCore,
    required PlanningSnapshotV3 snapshot,
    required String originalRequest,
    String? promptTraceId,
  });
}

class AiV3AdaptivePlannerService implements AiV3AdaptivePlanner {
  AiV3AdaptivePlannerService({
    required this.apiKey,
    required this.model,
    this.reasoningEffort = 'low',
    this.requestTimeout = const Duration(seconds: 40),
    this.retriever = const AiV3ContextRetriever(),
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const String _apiUrl = 'https://api.openai.com/v1/responses';

  final String apiKey;
  @override
  final String model;
  @override
  final String reasoningEffort;
  final Duration requestTimeout;
  final AiV3ContextRetriever retriever;
  final http.Client _httpClient;

  @override
  Future<AiV3AdaptivePlannerResult> plan({
    required CompactCoreV3 compactCore,
    required PlanningSnapshotV3 snapshot,
    required String originalRequest,
    String? promptTraceId,
  }) async {
    if (apiKey.trim().isEmpty || model.trim().isEmpty) {
      throw const AiV3AdaptivePlannerException(
        'v3_adaptive_openai_configuration_missing',
      );
    }
    if (compactCore.data['snapshot_id'] != snapshot.snapshotId ||
        compactCore.data['state_digest'] != snapshot.stateDigest) {
      throw const AiV3AdaptivePlannerException(
        'v3_adaptive_snapshot_mismatch',
      );
    }
    final totalStopwatch = Stopwatch()..start();
    final firstBody = buildAiV3AdaptiveFirstRequestBody(
      compactCore: compactCore.data,
      originalRequest: originalRequest,
      model: model,
      reasoningEffort: reasoningEffort,
      promptTraceId: promptTraceId,
    );
    final first = await _post(firstBody, stage: 'first');
    final firstCall = _singleFunctionCall(first.response);
    if (firstCall.name == 'submit_plan_v3') {
      final plan = _parsePlan(
        firstCall.arguments,
        allowedCommands: aiV3CommandTypes,
      );
      totalStopwatch.stop();
      return AiV3AdaptivePlannerResult(
        plan: plan,
        firstRawResponse: first.response,
        secondRawResponse: null,
        retrievalRequest: null,
        retrievalResult: null,
        firstRequestBody: firstBody,
        secondRequestBody: null,
        meta: _combinedMeta(
          first: first,
          second: null,
          retrievalElapsedMs: 0,
          totalElapsedMs: totalStopwatch.elapsedMilliseconds,
        ),
      );
    }
    if (firstCall.name != 'get_context_domains') {
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_first_tool_invalid',
        firstCall.name,
      );
    }
    late final AiV3ContextRequest retrievalRequest;
    try {
      retrievalRequest = AiV3ContextRequest.fromJson(firstCall.arguments);
    } on AiV3RetrievalException catch (error) {
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_retrieval_request_invalid',
        error.code,
        <String, dynamic>{
          'first_raw_response': first.response,
          'retrieval_arguments': firstCall.arguments,
        },
      );
    }
    final retrievalStopwatch = Stopwatch()..start();
    late final AiV3ContextResult retrievalResult;
    try {
      retrievalResult = retriever.retrieve(
        snapshot: snapshot,
        request: retrievalRequest,
      );
    } on AiV3RetrievalException catch (error) {
      retrievalStopwatch.stop();
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_retrieval_failed',
        error.code,
        <String, dynamic>{
          'retrieval_request': retrievalRequest.toJson(),
        },
      );
    }
    retrievalStopwatch.stop();
    final secondBody = buildAiV3AdaptiveContinuationRequestBody(
      compactCore: compactCore.data,
      originalRequest: originalRequest,
      retrievalRequest: retrievalRequest.toJson(),
      retrievalResult: retrievalResult.toJson(),
      model: model,
      reasoningEffort: reasoningEffort,
      promptTraceId: promptTraceId,
    );
    final second = await _post(secondBody, stage: 'continuation');
    final secondCall = _singleFunctionCall(second.response);
    if (secondCall.name == 'get_context_domains') {
      throw const AiV3AdaptivePlannerException(
        'adaptive_third_call_forbidden',
      );
    }
    if (secondCall.name != 'submit_plan_v3') {
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_continuation_tool_invalid',
        secondCall.name,
      );
    }
    final plan = _parsePlan(
      secondCall.arguments,
      allowedCommands: aiV3CommandTypes,
    );
    final requestedDomains =
        retrievalRequest.requests.map((query) => query.domain).toSet();
    if (requestedDomains.contains('clip_advanced')) {
      _requireRetrievedAdvancedClipTargets(plan, retrievalResult);
    }
    if (requestedDomains.contains('midi')) {
      _requireRetrievedMidiIdentifiers(plan, retrievalResult);
    }
    if (requestedDomains.contains('effects')) {
      _requireRetrievedEffectFacts(plan, retrievalResult);
    }
    if (requestedDomains.contains('samples')) {
      _requireRetrievedSampleAssets(plan, retrievalResult);
    }
    if (requestedDomains.contains('automation')) {
      _requireRetrievedAutomationTargets(plan, retrievalResult);
    }
    if (requestedDomains.contains('mix')) {
      _requireRetrievedMixReferences(plan, retrievalResult);
    }
    totalStopwatch.stop();
    return AiV3AdaptivePlannerResult(
      plan: plan,
      firstRawResponse: first.response,
      secondRawResponse: second.response,
      retrievalRequest: retrievalRequest,
      retrievalResult: retrievalResult,
      firstRequestBody: firstBody,
      secondRequestBody: secondBody,
      meta: _combinedMeta(
        first: first,
        second: second,
        retrievalElapsedMs: retrievalStopwatch.elapsedMilliseconds,
        totalElapsedMs: totalStopwatch.elapsedMilliseconds,
      ),
    );
  }

  Future<_ProviderCall> _post(
    Map<String, dynamic> body, {
    required String stage,
  }) async {
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
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_planner_timeout',
        stage,
      );
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
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_response_invalid_json',
        '$stage:http_${response.statusCode}',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final code = error is Map ? error['code']?.toString() ?? '' : '';
      final message = error is Map ? error['message']?.toString() ?? '' : '';
      final safeMessage =
          message.replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]+\b'), '[redacted]');
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_http_error',
        '$stage:${response.statusCode}:${code.isEmpty ? 'unknown' : code}',
        <String, dynamic>{
          if (safeMessage.isNotEmpty)
            'message': safeMessage.substring(
              0,
              safeMessage.length > 500 ? 500 : safeMessage.length,
            ),
        },
      );
    }
    final usage = decoded['usage'] is Map
        ? Map<String, dynamic>.from(decoded['usage'] as Map)
        : const <String, dynamic>{};
    final serviceTier = decoded['service_tier']?.toString() ?? '';
    return _ProviderCall(
      response: decoded,
      usage: usage,
      elapsedMs: stopwatch.elapsedMilliseconds,
      cost: estimateOpenAiModelCost(
        model: model,
        usage: usage,
        serviceTier: serviceTier,
      ),
    );
  }

  Map<String, dynamic> _combinedMeta({
    required _ProviderCall first,
    required _ProviderCall? second,
    required int retrievalElapsedMs,
    required int totalElapsedMs,
  }) {
    int token(String key) => (first.usage[key] as num?)?.toInt() ?? 0;
    int secondToken(String key) => (second?.usage[key] as num?)?.toInt() ?? 0;
    final firstCost = (first.cost?['estimated_cost_usd'] as num?)?.toDouble();
    final secondCost =
        (second?.cost?['estimated_cost_usd'] as num?)?.toDouble();
    return <String, dynamic>{
      'architecture': aiV3AdaptiveArchitecture,
      'surface_revision': aiV3AdaptiveSurfaceRevision,
      'model': model,
      'reasoning_effort': reasoningEffort,
      'call_count': second == null ? 1 : 2,
      'first_call_elapsed_ms': first.elapsedMs,
      'retrieval_elapsed_ms': retrievalElapsedMs,
      if (second != null) 'second_call_elapsed_ms': second.elapsedMs,
      'total_elapsed_ms': totalElapsedMs,
      'first_usage': first.usage,
      if (second != null) 'second_usage': second.usage,
      'combined_usage': <String, dynamic>{
        'input_tokens': token('input_tokens') + secondToken('input_tokens'),
        'output_tokens': token('output_tokens') + secondToken('output_tokens'),
        'total_tokens': token('total_tokens') + secondToken('total_tokens'),
      },
      if (first.cost != null) 'first_cost_estimate': first.cost,
      if (second?.cost != null) 'second_cost_estimate': second!.cost,
      if (firstCost != null || secondCost != null)
        'combined_estimated_cost_usd': (firstCost ?? 0.0) + (secondCost ?? 0.0),
    };
  }
}

void _requireRetrievedMidiIdentifiers(
  AiV3Plan plan,
  AiV3ContextResult retrievalResult,
) {
  final returnedClipIds = <String>{};
  final returnedRowIds = <int>{};
  final returnedInstrumentIds = <String>{};
  for (final result in retrievalResult.results) {
    if (result is! AiV3MidiRetrievalResult) continue;
    returnedRowIds.addAll(result.matchedRowIds);
    returnedInstrumentIds.addAll(result.instrumentIds);
    for (final clip in result.midiClips) {
      final clipId = clip['clip_id']?.toString().trim() ?? '';
      if (clipId.isNotEmpty) returnedClipIds.add(clipId);
      final instrumentId = clip['instrument_id']?.toString().trim() ?? '';
      if (instrumentId.isNotEmpty) returnedInstrumentIds.add(instrumentId);
    }
  }
  for (final command in plan.commands) {
    if (command.type == 'row.set_instrument') {
      final rowId = command.arguments['row_id'];
      if (rowId is! int || !returnedRowIds.contains(rowId)) {
        throw AiV3AdaptivePlannerException(
          'v3_adaptive_midi_row_not_retrieved',
          rowId.toString(),
        );
      }
      final instrumentId = command.arguments['instrument_id']?.toString() ?? '';
      if (!returnedInstrumentIds.contains(instrumentId)) {
        throw AiV3AdaptivePlannerException(
          'v3_adaptive_midi_instrument_not_retrieved',
          instrumentId,
        );
      }
      continue;
    }
    if (command.type == 'clip.convert_to_midi') {
      final instrumentId = command.arguments['instrument_id']?.toString() ?? '';
      if (!returnedInstrumentIds.contains(instrumentId)) {
        throw AiV3AdaptivePlannerException(
          'v3_adaptive_midi_instrument_not_retrieved',
          instrumentId,
        );
      }
      continue;
    }
    if (const <String>{
      'midi.transpose',
      'midi.replace_notes',
      'midi.append_notes',
      'midi.chop_notes',
    }.contains(command.type)) {
      final clipId = command.arguments['clip_id']?.toString() ?? '';
      if (!returnedClipIds.contains(clipId)) {
        throw AiV3AdaptivePlannerException(
          'v3_adaptive_midi_clip_not_retrieved',
          clipId,
        );
      }
      continue;
    }
    if (command.type != 'midi.create_clip') continue;
    final destination = command.arguments['destination'];
    if (destination is! Map) continue;
    final rowId = destination['row_id'];
    if (rowId is int && !returnedRowIds.contains(rowId)) {
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_midi_row_not_retrieved',
        rowId.toString(),
      );
    }
    final newRow = destination['new_row'];
    if (newRow is! Map) continue;
    final instrumentId = newRow['instrument_id']?.toString() ?? '';
    if (!returnedInstrumentIds.contains(instrumentId)) {
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_midi_instrument_not_retrieved',
        instrumentId,
      );
    }
  }
}

void _requireRetrievedEffectFacts(
  AiV3Plan plan,
  AiV3ContextResult retrievalResult,
) {
  final returnedRowIds = <int>{};
  final returnedInstanceIds = <String>{
    for (final result in retrievalResult.results)
      if (result is AiV3EffectsRetrievalResult)
        for (final instance in result.instances)
          if ((instance['effect_instance_id']?.toString() ?? '').isNotEmpty)
            instance['effect_instance_id'].toString(),
  };
  final returnedParametersByEffectId = <String, Set<String>>{};
  for (final result in retrievalResult.results) {
    if (result is! AiV3EffectsRetrievalResult) continue;
    returnedRowIds.addAll(result.matchedRowIds);
    for (final effect in result.catalog) {
      final effectId = effect['effect_id']?.toString().trim() ?? '';
      if (effectId.isEmpty) continue;
      final parameters = returnedParametersByEffectId.putIfAbsent(
        effectId,
        () => <String>{},
      );
      parameters.addAll(
        (effect['parameter_ids'] as List? ?? const <Object>[])
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty),
      );
    }
    for (final definition in result.parameterDefinitions) {
      final effectId = definition['effect_id']?.toString().trim() ?? '';
      final parameterId = definition['parameter_id']?.toString().trim() ?? '';
      if (effectId.isEmpty || parameterId.isEmpty) continue;
      returnedParametersByEffectId
          .putIfAbsent(effectId, () => <String>{})
          .add(parameterId);
    }
  }
  for (final command in plan.commands) {
    if (command.type == 'effect.ensure_configured') {
      final rowId = command.arguments['row_id'];
      final effectId = command.arguments['effect_id']?.toString() ?? '';
      final returnedParameters = returnedParametersByEffectId[effectId];
      final rawParameters = command.arguments['parameters'];
      final parameterIds = rawParameters is List
          ? rawParameters
              .whereType<Map>()
              .map((parameter) => parameter['parameter_id']?.toString() ?? '')
          : const Iterable<String>.empty();
      final resolvedParameterIds = returnedParameters == null
          ? const <String?>[]
          : parameterIds
              .map(
                (parameterId) => _canonicalRetrievedEffectParameterId(
                  parameterId,
                  returnedParameters,
                ),
              )
              .toList(growable: false);
      if (rowId is! int ||
          !returnedRowIds.contains(rowId) ||
          returnedParameters == null ||
          resolvedParameterIds.any((parameterId) => parameterId == null) ||
          resolvedParameterIds.whereType<String>().toSet().length !=
              resolvedParameterIds.length) {
        throw AiV3AdaptivePlannerException(
          'v3_adaptive_effect_configuration_not_retrieved',
          '$rowId:$effectId',
        );
      }
      continue;
    }
    if (command.type != 'effect.remove' &&
        command.type != 'effect.set_bypassed') {
      continue;
    }
    final instanceId =
        command.arguments['effect_instance_id']?.toString() ?? '';
    if (!returnedInstanceIds.contains(instanceId)) {
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_effect_instance_not_retrieved',
        instanceId,
      );
    }
  }
}

String? _canonicalRetrievedEffectParameterId(
  String submittedId,
  Set<String> returnedIds,
) {
  if (returnedIds.contains(submittedId)) return submittedId;
  final folded = submittedId.toLowerCase();
  final matches = returnedIds
      .where((candidate) => candidate.toLowerCase() == folded)
      .toList(growable: false);
  return matches.length == 1 ? matches.single : null;
}

void _requireRetrievedAdvancedClipTargets(
  AiV3Plan plan,
  AiV3ContextResult retrievalResult,
) {
  final returnedClipIds = <String>{
    for (final result in retrievalResult.results)
      if (result is AiV3ClipAdvancedRetrievalResult)
        for (final clip in result.audioClips)
          if ((clip['clip_id']?.toString() ?? '').isNotEmpty)
            clip['clip_id'].toString(),
  };
  for (final command in plan.commands) {
    if (!aiV3ClipAdvancedCommandTypes.contains(command.type)) continue;
    if (command.type == 'clip.glue') {
      final clipIds = (command.arguments['clip_ids'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false);
      final missing =
          clipIds.where((clipId) => !returnedClipIds.contains(clipId));
      if (missing.isNotEmpty) {
        throw AiV3AdaptivePlannerException(
          'v3_adaptive_clip_target_not_retrieved',
          missing.first,
        );
      }
      continue;
    }
    final clipId = command.arguments['clip_id']?.toString() ?? '';
    if (!returnedClipIds.contains(clipId)) {
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_clip_target_not_retrieved',
        clipId,
      );
    }
  }
}

void _requireRetrievedSampleAssets(
  AiV3Plan plan,
  AiV3ContextResult retrievalResult,
) {
  final returnedAssetIds = <String>{
    for (final result in retrievalResult.results)
      if (result is AiV3SamplesRetrievalResult)
        for (final asset in result.assets)
          if ((asset['asset_id']?.toString() ?? '').isNotEmpty)
            asset['asset_id'].toString(),
  };
  for (final command in plan.commands) {
    if (command.type == 'sample.replace') {
      final assetId = command.arguments['asset_id']?.toString() ?? '';
      if (!returnedAssetIds.contains(assetId)) {
        throw AiV3AdaptivePlannerException(
          'v3_adaptive_sample_asset_not_retrieved',
          assetId,
        );
      }
      continue;
    }
    if (command.type != 'sample.place') continue;
    final placements = command.arguments['placements'];
    if (placements is! List) continue;
    for (final placement in placements) {
      if (placement is! Map) continue;
      final assetId = placement['asset_id']?.toString() ?? '';
      if (!returnedAssetIds.contains(assetId)) {
        throw AiV3AdaptivePlannerException(
          'v3_adaptive_sample_asset_not_retrieved',
          assetId,
        );
      }
    }
  }
}

void _requireRetrievedAutomationTargets(
  AiV3Plan plan,
  AiV3ContextResult retrievalResult,
) {
  final returnedRowIds = <int>{
    for (final result in retrievalResult.results)
      if (result is AiV3AutomationRetrievalResult) ...result.matchedRowIds,
  };
  final returnedTargetIdsByRow = <int, Set<String>>{};
  for (final result in retrievalResult.results) {
    if (result is! AiV3AutomationRetrievalResult) continue;
    for (final row in result.rows) {
      final rowId = row['row_id'];
      if (rowId is! int) continue;
      final targets = returnedTargetIdsByRow.putIfAbsent(
        rowId,
        () => <String>{},
      );
      for (final raw
          in (row['automation_targets'] as List? ?? const <Object>[])) {
        if (raw is! Map) continue;
        final targetId = raw['automation_target_id']?.toString().trim() ?? '';
        if (targetId.isNotEmpty) targets.add(targetId);
      }
    }
  }
  for (final command in plan.commands) {
    final rowId = command.arguments['row_id'];
    if (!const <String>{
      'automation.gain_fade',
      'automation.set_points',
      'automation.clear',
    }.contains(command.type)) {
      continue;
    }
    if (rowId is! int || !returnedRowIds.contains(rowId)) {
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_automation_target_not_retrieved',
        rowId?.toString() ?? '',
      );
    }
    if (command.type == 'automation.gain_fade') continue;
    final targetId =
        command.arguments['automation_target_id']?.toString().trim() ?? '';
    if (!(returnedTargetIdsByRow[rowId]?.contains(targetId) ?? false)) {
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_automation_target_not_retrieved',
        targetId,
      );
    }
  }
}

void _requireRetrievedMixReferences(
  AiV3Plan plan,
  AiV3ContextResult retrievalResult,
) {
  final referenceSuitabilityByRow = <int, bool>{
    for (final result in retrievalResult.results)
      if (result is AiV3MixRetrievalResult)
        for (final row in result.referenceAnalysis)
          if (row['row_id'] is int)
            row['row_id'] as int: row['reference_suitable'] == true,
  };
  for (final command in plan.commands) {
    if (command.type != 'mix.apply_goal') continue;
    final reference = command.arguments['reference'];
    if (reference is! Map) continue;
    final rowId = reference['row_id'];
    if (rowId is! int || !referenceSuitabilityByRow.containsKey(rowId)) {
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_mix_reference_not_retrieved',
        rowId?.toString() ?? '',
      );
    }
    if (referenceSuitabilityByRow[rowId] != true) {
      throw AiV3AdaptivePlannerException(
        'v3_adaptive_mix_reference_unsuitable',
        rowId.toString(),
      );
    }
  }
}

Map<String, dynamic> buildAiV3AdaptiveFirstRequestBody({
  required Map<String, dynamic> compactCore,
  required String originalRequest,
  required String model,
  required String reasoningEffort,
  String? promptTraceId,
}) =>
    _baseRequest(
      instructions: aiV3AdaptiveFirstTurnInstructions,
      content: <Map<String, dynamic>>[
        _inputText('ORIGINAL_REQUEST_VERBATIM', originalRequest),
        _inputJson('COMPACT_CORE_V3_JSON', compactCore),
      ],
      tools: <Map<String, dynamic>>[
        aiV3SubmitPlanTool(
          commandTypes: aiV3CommandTypes,
          includeCommandSemantics: true,
        ),
        aiV3GetContextDomainsTool(),
      ],
      forcedSubmit: false,
      model: model,
      reasoningEffort: reasoningEffort,
      promptTraceId: promptTraceId,
      stage: 'first',
    );

Map<String, dynamic> buildAiV3AdaptiveContinuationRequestBody({
  required Map<String, dynamic> compactCore,
  required String originalRequest,
  required Map<String, dynamic> retrievalRequest,
  required Map<String, dynamic> retrievalResult,
  required String model,
  required String reasoningEffort,
  String? promptTraceId,
}) =>
    _baseRequest(
      instructions: aiV3AdaptiveContinuationInstructions,
      content: <Map<String, dynamic>>[
        _inputText('ORIGINAL_REQUEST_VERBATIM', originalRequest),
        _inputJson('COMPACT_CORE_V3_JSON', compactCore),
        _inputJson('TYPED_RETRIEVAL_REQUEST_JSON', retrievalRequest),
        _inputJson('TYPED_RETRIEVAL_RESULTS_JSON', retrievalResult),
      ],
      tools: <Map<String, dynamic>>[
        aiV3SubmitPlanTool(
          commandTypes: aiV3CommandTypes,
          includeCommandSemantics: true,
        ),
      ],
      forcedSubmit: true,
      model: model,
      reasoningEffort: reasoningEffort,
      promptTraceId: promptTraceId,
      stage: 'continuation',
    );

Map<String, dynamic> _baseRequest({
  required String instructions,
  required List<Map<String, dynamic>> content,
  required List<Map<String, dynamic>> tools,
  required bool forcedSubmit,
  required String model,
  required String reasoningEffort,
  required String? promptTraceId,
  required String stage,
}) {
  final trace = (promptTraceId ?? '').trim();
  return <String, dynamic>{
    'model': model.trim(),
    'instructions': instructions.trim(),
    'input': <Map<String, dynamic>>[
      <String, dynamic>{'role': 'user', 'content': content},
    ],
    'tools': tools,
    'tool_choice': forcedSubmit
        ? <String, dynamic>{'type': 'function', 'name': 'submit_plan_v3'}
        : 'required',
    'parallel_tool_calls': false,
    'max_output_tokens': 8192,
    'reasoning': <String, dynamic>{'effort': reasoningEffort},
    'store': false,
    if (trace.isNotEmpty)
      'metadata': <String, String>{
        'prompt_trace_id':
            trace.substring(0, trace.length > 64 ? 64 : trace.length),
        'architecture': aiV3AdaptiveArchitecture,
        'surface_revision': aiV3AdaptiveSurfaceRevision,
        'stage': stage,
      },
  };
}

Map<String, dynamic> _inputText(String label, String value) =>
    <String, dynamic>{'type': 'input_text', 'text': '$label:\n$value'};

Map<String, dynamic> _inputJson(String label, Map<String, dynamic> value) =>
    _inputText(label, jsonEncode(value));

AiV3Plan _parsePlan(
  Map<String, dynamic> arguments, {
  required Set<String> allowedCommands,
}) {
  try {
    final plan = AiV3Plan.fromJson(arguments);
    if (plan.commands
        .any((command) => !allowedCommands.contains(command.type))) {
      throw const AiV3ContractException(
        'v3_planner_command_outside_surface',
      );
    }
    return plan;
  } on AiV3ContractException catch (error) {
    throw AiV3AdaptivePlannerException(
      'v3_adaptive_plan_invalid',
      error.code,
      <String, dynamic>{'tool_arguments': arguments},
    );
  }
}

_FunctionCall _singleFunctionCall(Map<String, dynamic> response) {
  final output = response['output'];
  if (output is! List) {
    throw const AiV3AdaptivePlannerException(
      'v3_adaptive_tool_call_missing',
    );
  }
  final calls = output
      .whereType<Map>()
      .where((value) => value['type'] == 'function_call')
      .toList(growable: false);
  if (calls.length != 1) {
    throw const AiV3AdaptivePlannerException(
      'v3_adaptive_tool_call_count_invalid',
    );
  }
  final call = calls.single;
  final name = call['name']?.toString().trim() ?? '';
  final raw = call['arguments'];
  Map<String, dynamic> arguments;
  if (raw is Map) {
    arguments = Map<String, dynamic>.from(raw);
  } else if (raw is String) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      arguments = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const AiV3AdaptivePlannerException(
        'v3_adaptive_arguments_invalid_json',
      );
    }
  } else {
    throw const AiV3AdaptivePlannerException(
      'v3_adaptive_arguments_invalid',
    );
  }
  return _FunctionCall(name: name, arguments: arguments);
}

class _FunctionCall {
  const _FunctionCall({required this.name, required this.arguments});
  final String name;
  final Map<String, dynamic> arguments;
}

class _ProviderCall {
  const _ProviderCall({
    required this.response,
    required this.usage,
    required this.elapsedMs,
    required this.cost,
  });
  final Map<String, dynamic> response;
  final Map<String, dynamic> usage;
  final int elapsedMs;
  final Map<String, dynamic>? cost;
}
