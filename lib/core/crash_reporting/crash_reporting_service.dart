import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:mixroom/config/analytics_config.dart';
import 'package:mixroom/core/privacy/privacy_preferences.dart';

class CrashReportingService {
  CrashReportingService._();

  static final CrashReportingService instance = CrashReportingService._();

  bool _initialized = false;
  bool _enabled = true;

  Future<void> initialize() async {
    if (_initialized) return;

    _enabled = await PrivacyPreferences.isAnalyticsAndCrashDiagnosticsEnabled();

    if (!AnalyticsConfig.hasSentry) {
      _initialized = true;
      return;
    }

    await SentryFlutter.init(
      (options) {
        options.dsn = AnalyticsConfig.sentryDsn;
        options.environment = AnalyticsConfig.environment;
        options.debug = !kReleaseMode;
        options.tracesSampleRate = 0.0;
        options.beforeSend = (event, hint) {
          if (!_enabled) return null;
          return event;
        };
      },
    );
    _initialized = true;
  }

  Future<void> setCollectionEnabled(bool enabled) async {
    _enabled = enabled;
    await PrivacyPreferences.setAnalyticsAndCrashDiagnosticsEnabled(enabled);
  }

  Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
  }) async {
    if (!_initialized || !_enabled) return;
    try {
      await Sentry.captureException(error, stackTrace: stackTrace);
    } catch (_) {}
  }

  Future<void> captureFlutterError(FlutterErrorDetails details) async {
    if (!_initialized || !_enabled) return;
    try {
      await Sentry.captureException(
        details.exception,
        stackTrace: details.stack,
      );
    } catch (_) {}
  }

  Future<void> setUser({
    required String id,
    String? email,
    String? username,
  }) async {
    if (!_initialized) return;
    await Sentry.configureScope((scope) {
      scope.setUser(
        SentryUser(
          id: id,
          email: email,
          username: username,
        ),
      );
    });
  }

  Future<void> clearUser() async {
    if (!_initialized) return;
    await Sentry.configureScope((scope) {
      scope.setUser(null);
    });
  }
}
