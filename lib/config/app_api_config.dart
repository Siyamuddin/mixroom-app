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
    defaultValue: _defaultAppApiBaseUrl,
  );

  static const bool enforceSubscriptions = bool.fromEnvironment(
    'SUBSCRIPTION_ENFORCE',
    defaultValue: false,
  );

  static const bool subscriptionShadowMode = bool.fromEnvironment(
    'SUBSCRIPTION_SHADOW_MODE',
    defaultValue: true,
  );

  static const bool allowStudioTier = bool.fromEnvironment(
    'SUBSCRIPTION_ALLOW_STUDIO',
    defaultValue: false,
  );

  static const int requestTimeoutSeconds = int.fromEnvironment(
    'SUBSCRIPTION_REQUEST_TIMEOUT_SECONDS',
    defaultValue: 20,
  );

  static const int entitlementCacheTtlMinutes = int.fromEnvironment(
    'SUBSCRIPTION_CACHE_TTL_MINUTES',
    defaultValue: 15,
  );

  static String get apiBaseUrl {
    final preferred = appApiBaseUrl.trim();
    if (preferred.isNotEmpty) return preferred;
    final legacy = legacyApiBaseUrl.trim();
    if (legacy.isNotEmpty) return legacy;
    return '';
  }

  static bool get hasApiBaseUrl => apiBaseUrl.isNotEmpty;
}
