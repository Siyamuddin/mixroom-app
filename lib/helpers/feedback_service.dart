import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/models/feedback_models.dart';

class FeedbackService {
  FeedbackService({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static final FeedbackService instance = FeedbackService();

  final http.Client _httpClient;

  Future<void> submit({
    required AuthService auth,
    required FeedbackSubmissionRequest request,
  }) async {
    if (!AppApiConfig.hasApiBaseUrl) {
      throw StateError('Feedback service is unavailable right now.');
    }

    final body = jsonEncode(
      request.toJson(client: _buildClientContext()),
    );

    final response = await auth.authorizedRequest(
      (token) => _httpClient
          .post(
            _buildUri('/v1/feedback'),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        _extractErrorMessage(
              response.body,
              fallback: 'Feedback submission failed (${response.statusCode}).',
            ) ??
            'Feedback submission failed (${response.statusCode}).',
      );
    }
  }

  Uri _buildUri(String path) {
    final base = AppApiConfig.apiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    return Uri.parse('$base$path');
  }

  Map<String, String> _buildClientContext() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
    final version = AnalyticsService.instance.appVersion.trim();
    return <String, String>{
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'locale': locale,
      if (version.isNotEmpty) 'app_version': version,
    };
  }

  String? _extractErrorMessage(
    String body, {
    String? fallback,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return error.trim();
        }
      }
    } catch (_) {
      // Fall through to the fallback.
    }
    return fallback;
  }
}
