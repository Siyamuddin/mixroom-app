import 'package:flutter/foundation.dart';

class AnalyticsConfig {
  const AnalyticsConfig._();

  static const String postHogApiKey = String.fromEnvironment(
    'POSTHOG_API_KEY',
    defaultValue: 'phc_t3pSmXe8NYEv8jrpk3dfMnxU6iud4EySnHzAAwFL28g',
  );

  static const String postHogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
  );

  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue:
        'https://5e8e9f0b08714d2c26591bce7b3e057f@o4511009749729280.ingest.us.sentry.io/4511012111712256',
  );

  static const String appEnvironment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: '',
  );

  static bool get hasPostHog =>
      postHogApiKey.trim().isNotEmpty && postHogHost.trim().isNotEmpty;

  static bool get hasSentry => sentryDsn.trim().isNotEmpty;

  static String get environment {
    final explicit = appEnvironment.trim();
    if (explicit.isNotEmpty) return explicit;
    return kReleaseMode ? 'prod' : 'dev';
  }
}
