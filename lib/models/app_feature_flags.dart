import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/config/iap_config.dart';

class AppFeatureFlagKeys {
  const AppFeatureFlagKeys._();

  static const String accountPlanBillingEnabled =
      'account_plan_billing_enabled';
  static const String subscriptionEnforcementEnabled =
      'subscription_enforcement_enabled';
  static const String iapPurchasesEnabled = 'iap_purchases_enabled';
}

class AppFeatureFlags {
  const AppFeatureFlags({
    required this.flags,
    required this.updatedAt,
    required this.source,
  });

  factory AppFeatureFlags.defaults() {
    return const AppFeatureFlags(
      flags: <String, bool>{
        AppFeatureFlagKeys.accountPlanBillingEnabled:
            AppApiConfig.accountPlanBillingEnabled,
        AppFeatureFlagKeys.subscriptionEnforcementEnabled:
            AppApiConfig.enforceSubscriptions,
        AppFeatureFlagKeys.iapPurchasesEnabled: IapConfig.purchasesEnabled,
      },
      updatedAt: null,
      source: 'local',
    );
  }

  factory AppFeatureFlags.fromJson(
    Map<String, dynamic> json, {
    AppFeatureFlags? fallback,
  }) {
    final base = fallback ?? AppFeatureFlags.defaults();
    final rawFlags = json['flags'];
    final nextFlags = <String, bool>{...base.flags};
    if (rawFlags is Map) {
      for (final entry in rawFlags.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is bool) {
          nextFlags[key] = value;
        }
      }
    }
    return AppFeatureFlags(
      flags: Map<String, bool>.unmodifiable(nextFlags),
      updatedAt: (json['updated_at'] ?? '').toString().trim().isEmpty
          ? null
          : (json['updated_at'] ?? '').toString(),
      source: (json['source'] ?? 'remote').toString(),
    );
  }

  final Map<String, bool> flags;
  final String? updatedAt;
  final String source;

  bool get accountPlanBillingEnabled =>
      flags[AppFeatureFlagKeys.accountPlanBillingEnabled] ??
      AppApiConfig.accountPlanBillingEnabled;

  bool get subscriptionEnforcementEnabled =>
      flags[AppFeatureFlagKeys.subscriptionEnforcementEnabled] ??
      AppApiConfig.enforceSubscriptions;

  bool get iapPurchasesEnabled =>
      flags[AppFeatureFlagKeys.iapPurchasesEnabled] ??
      IapConfig.purchasesEnabled;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'flags': flags,
      if (updatedAt != null) 'updated_at': updatedAt,
      'source': source,
    };
  }
}
