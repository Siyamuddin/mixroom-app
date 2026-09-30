import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/analytics/analytics_service.dart';
import '../models/goal_vector.dart';
import '../models/mixing_result.dart';
import '../models/project_state.dart';
import 'ai_debug.dart';
import 'magnitude_predictor.dart';

typedef ProxyAuthTokenProvider = Future<String?> Function();

const String _kRemoteMixResolveContractVersion = 'mix_refine_v1';

class RemoteMixingMagnitudePredictor implements MixingMagnitudePredictor {
  RemoteMixingMagnitudePredictor({
    required this.enabled,
    required this.proxyApiBaseUrl,
    required this.proxyPath,
    required this.requestTimeout,
    this.authTokenProvider,
    this.refreshAuthTokenProvider,
    Map<String, String> extraHeaders = const <String, String>{},
    http.Client? httpClient,
  }) : extraHeaders = Map<String, String>.unmodifiable(extraHeaders),
       _httpClient = httpClient ?? http.Client();

  final bool enabled;
  final String proxyApiBaseUrl;
  final String proxyPath;
  final Duration requestTimeout;
  final ProxyAuthTokenProvider? authTokenProvider;
  final ProxyAuthTokenProvider? refreshAuthTokenProvider;
  final Map<String, String> extraHeaders;
  final http.Client _httpClient;

  Map<String, dynamic> _observabilityContext = const <String, dynamic>{
    'mix_magnitude_model_source': 'remote',
  };

  @override
  bool get isEnabled => enabled;

  @override
  bool get isReady => !enabled || proxyApiBaseUrl.trim().isNotEmpty;

  @override
  Map<String, dynamic> get observabilityContext => _observabilityContext;

  @override
  Future<void> startBackgroundRefresh() async {}

  @override
  Future<void> load() async {}

  @override
  Future<void> dispose() async {
    _httpClient.close();
  }

  @override
  Future<MagnitudeRefineResult> refine({
    required ProjectState project,
    required GoalVector goal,
    required List<MixAction> actions,
    required bool strict,
    String? projectId,
  }) async {
    if (actions.isEmpty) {
      return const MagnitudeRefineResult(actions: [], fallbackUsed: false);
    }
    if (!enabled) {
      return MagnitudeRefineResult(
        actions: actions,
        fallbackUsed: true,
        fallbackReason: 'disabled',
      );
    }
    if (proxyApiBaseUrl.trim().isEmpty) {
      return MagnitudeRefineResult(
        actions: actions,
        fallbackUsed: true,
        fallbackReason: 'proxy_unconfigured',
      );
    }
    if (goal.executionProfile == MixExecutionProfile.experimentalExtreme) {
      return MagnitudeRefineResult(
        actions: actions,
        fallbackUsed: true,
        fallbackReason: 'execution_profile_bypass',
      );
    }
    if (goal.referenceTarget != null) {
      return MagnitudeRefineResult(
        actions: actions,
        fallbackUsed: true,
        fallbackReason: 'reference_match_bypass',
      );
    }

    final token = await _resolveProxyAuthToken();
    if (token == null || token.isEmpty) {
      return MagnitudeRefineResult(
        actions: actions,
        fallbackUsed: true,
        fallbackReason: 'missing_proxy_auth',
      );
    }

    final requestBody = <String, dynamic>{
      'project_state': project.toMagnitudeResolverJson(),
      'goal': goal.toJson(),
      'actions': actions.map((action) => action.toJson()).toList(growable: false),
      'strict': strict,
      'mix_feature_contract_version': _kRemoteMixResolveContractVersion,
      if ((projectId ?? '').trim().isNotEmpty) 'project_id': projectId!.trim(),
      ...AnalyticsService.instance.buildRequestContext(),
    };

    var response = await _postResolve(token: token, body: requestBody);
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        refreshAuthTokenProvider != null) {
      final refreshedToken = await _resolveProxyAuthToken(forceRefresh: true);
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        response = await _postResolve(token: refreshedToken, body: requestBody);
      }
    }

    final payload = _decodeJsonObject(response.body);
    if (response.statusCode != 200 || payload == null) {
      aiDebugLog(
        'onnx-mag-remote',
        'resolve failed status=${response.statusCode} body=${response.body}',
      );
      return MagnitudeRefineResult(
        actions: actions,
        fallbackUsed: true,
        fallbackReason: 'remote_refine_failed',
      );
    }

    final rawActions = payload['actions'];
    if (rawActions is! List) {
      return MagnitudeRefineResult(
        actions: actions,
        fallbackUsed: true,
        fallbackReason: 'remote_invalid_payload',
      );
    }

    final resolvedActions = rawActions
        .whereType<Map>()
        .map((raw) => _mixActionFromJson(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
    final rawDebugEntries = payload['debug_entries'];
    final debugEntries = rawDebugEntries is List
        ? rawDebugEntries
            .whereType<Map>()
            .map(
              (entry) =>
                  MagnitudeActionDebugEntry.fromJson(Map<String, dynamic>.from(entry)),
            )
            .toList(growable: false)
        : const <MagnitudeActionDebugEntry>[];

    final rawObservability = payload['observability'];
    _observabilityContext = rawObservability is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawObservability)
        : (rawObservability is Map
            ? Map<String, dynamic>.from(rawObservability)
            : <String, dynamic>{});
    _observabilityContext.putIfAbsent(
      'mix_magnitude_model_source',
      () => 'remote',
    );
    if (payload['request_duration_ms'] is num) {
      _observabilityContext['mix_resolve_request_ms'] =
          (payload['request_duration_ms'] as num).toInt();
    }

    return MagnitudeRefineResult(
      actions: resolvedActions,
      fallbackUsed: payload['fallback_used'] == true,
      fallbackReason: payload['fallback_reason']?.toString(),
      debugEntries: debugEntries,
      observability: _observabilityContext,
    );
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

  Future<http.Response> _postResolve({
    required String token,
    required Map<String, dynamic> body,
  }) {
    final path = proxyPath.trim().isEmpty ? '/v1/mix/resolve' : proxyPath;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('${proxyApiBaseUrl.trim()}$normalizedPath');
    return _httpClient
        .post(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            ...extraHeaders,
          },
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);
  }

  Map<String, dynamic>? _decodeJsonObject(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  MixAction _mixActionFromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return MixAction(
      (json['type'] as String?)?.trim() ?? '',
      rawData is Map<String, dynamic>
          ? rawData
          : (rawData is Map ? Map<String, dynamic>.from(rawData) : const {}),
    );
  }
}
