class AppApiConfig {
  const AppApiConfig._();

  static const String _defaultAppApiBaseUrl =
      'https://guepfr96ah.execute-api.ap-northeast-2.amazonaws.com/prod';

  // Legacy env var kept for backward compatibility with older local scripts.
  static const String legacyApiBaseUrl = String.fromEnvironment(
    'SUBSCRIPTION_API_BASE_URL',
    defaultValue: '',
  );

  static const String appApiBaseUrl = String.fromEnvironment(
    'APP_API_BASE_URL',
    defaultValue: '',
  );

  static const bool enforceSubscriptions = bool.fromEnvironment(
    'SUBSCRIPTION_ENFORCE',
    defaultValue: true,
  );
  static const bool hasEnforceSubscriptionsOverride =
      bool.hasEnvironment('SUBSCRIPTION_ENFORCE');

  static const bool accountPlanBillingEnabled = bool.fromEnvironment(
    'ACCOUNT_PLAN_BILLING_ENABLED',
    defaultValue: true,
  );
  static const bool hasAccountPlanBillingOverride =
      bool.hasEnvironment('ACCOUNT_PLAN_BILLING_ENABLED');

  static const bool cloudProjectsEnabled = bool.fromEnvironment(
    'CLOUD_PROJECTS_ENABLED',
    defaultValue: false,
  );
  static const bool hasCloudProjectsOverride =
      bool.hasEnvironment('CLOUD_PROJECTS_ENABLED');

  static const int requestTimeoutSeconds = int.fromEnvironment(
    'SUBSCRIPTION_REQUEST_TIMEOUT_SECONDS',
    defaultValue: 20,
  );

  static const int entitlementCacheTtlMinutes = int.fromEnvironment(
    'SUBSCRIPTION_CACHE_TTL_MINUTES',
    defaultValue: 15,
  );

  static const bool enableProjectSnapshotTelemetry = bool.fromEnvironment(
    'APP_ENABLE_PROJECT_SNAPSHOT_TELEMETRY',
    defaultValue: true,
  );

  static String get apiBaseUrl {
    final preferred = appApiBaseUrl.trim();
    if (preferred.isNotEmpty) return preferred;
    final legacy = legacyApiBaseUrl.trim();
    if (legacy.isNotEmpty) return legacy;
    return _defaultAppApiBaseUrl;
  }

  static bool get hasApiBaseUrl => apiBaseUrl.isNotEmpty;
}
