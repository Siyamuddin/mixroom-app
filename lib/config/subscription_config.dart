class SubscriptionConfig {
  const SubscriptionConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'SUBSCRIPTION_API_BASE_URL',
    defaultValue: '',
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
    defaultValue: 8,
  );

  static const int entitlementCacheTtlMinutes = int.fromEnvironment(
    'SUBSCRIPTION_CACHE_TTL_MINUTES',
    defaultValue: 15,
  );

  static bool get hasApiBaseUrl => apiBaseUrl.trim().isNotEmpty;
}
