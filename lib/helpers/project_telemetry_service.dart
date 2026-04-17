import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/core/privacy/privacy_preferences.dart';
import 'package:mixroom/helpers/auth_service.dart';

class ProjectTelemetryService {
  ProjectTelemetryService._({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static final ProjectTelemetryService instance = ProjectTelemetryService._();

  final http.Client _httpClient;
  final Set<String> _inFlightProjectIds = <String>{};

  Future<void> uploadProjectSnapshot({
    required AuthService auth,
    required String projectId,
    required String projectName,
    required Map<String, dynamic> projectJson,
    required Map<String, dynamic> projectSnapshot,
  }) async {
    if (!AppApiConfig.enableProjectSnapshotTelemetry ||
        !AppApiConfig.hasApiBaseUrl ||
        !auth.isSignedIn) {
      return;
    }

    final normalizedProjectId = projectId.trim();
    if (normalizedProjectId.isEmpty) {
      return;
    }
    if (_inFlightProjectIds.contains(normalizedProjectId)) {
      return;
    }

    _inFlightProjectIds.add(normalizedProjectId);
    try {
      final telemetryEnabled =
          await PrivacyPreferences.isAnalyticsAndCrashDiagnosticsEnabled();
      final sanitizedProjectJson =
          telemetryEnabled ? projectJson : _redactProjectJson(projectJson);
      final requestContext = AnalyticsService.instance.buildRequestContext();
      final body = jsonEncode(<String, dynamic>{
        'source': 'audio_editor_save',
        'uploaded_at': DateTime.now().toUtc().toIso8601String(),
        'telemetry_enabled': telemetryEnabled,
        'client_context': requestContext['client_context'],
        'project_id': normalizedProjectId,
        'project_name': projectName.trim(),
        'project_snapshot': projectSnapshot,
        'project_json': sanitizedProjectJson,
      });

      final uri = _buildUri('/v1/telemetry/project-snapshots');
      final initialCandidates = await auth.getRequestTokenCandidates();
      if (initialCandidates.isEmpty) {
        return;
      }

      var response = await _postSnapshotWithCandidates(
        uri: uri,
        tokenCandidates: initialCandidates,
        body: body,
      );
      if (response == null || !_isUnauthorizedResponse(response.statusCode)) {
        return;
      }

      final refreshedCandidates = await auth.getRequestTokenCandidates(
        forceRefresh: true,
      );
      final retryCandidates = refreshedCandidates
          .where((token) => !initialCandidates.contains(token))
          .toList();
      if (retryCandidates.isEmpty) {
        return;
      }
      await _postSnapshotWithCandidates(
        uri: uri,
        tokenCandidates: retryCandidates,
        body: body,
      );
    } catch (_) {
      // Telemetry delivery must never block normal editor behavior.
    } finally {
      _inFlightProjectIds.remove(normalizedProjectId);
    }
  }

  Future<http.Response?> _postSnapshotWithCandidates({
    required Uri uri,
    required List<String> tokenCandidates,
    required String body,
  }) async {
    http.Response? lastResponse;
    for (final token in tokenCandidates) {
      final response = await _postSnapshot(
        uri: uri,
        token: token,
        body: body,
      );
      if (!_isUnauthorizedResponse(response.statusCode)) {
        return response;
      }
      lastResponse = response;
    }
    return lastResponse;
  }

  Future<http.Response> _postSnapshot({
    required Uri uri,
    required String token,
    required String body,
  }) {
    return _httpClient
        .post(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds));
  }

  bool _isUnauthorizedResponse(int statusCode) {
    return statusCode == 401 || statusCode == 403;
  }

  Uri _buildUri(String path) {
    final base = AppApiConfig.apiBaseUrl.trim();
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Map<String, dynamic> _redactProjectJson(Map<String, dynamic> projectJson) {
    final redacted = Map<String, dynamic>.from(projectJson);
    redacted.remove('assistantChat');
    return redacted;
  }
}
