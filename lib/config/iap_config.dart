import 'package:flutter/foundation.dart';

class IapConfig {
  const IapConfig._();

  static const bool purchasesEnabled = bool.fromEnvironment(
    'IAP_ENABLE_PURCHASES',
    defaultValue: false,
  );
  static const bool hasPurchasesEnabledOverride =
      bool.hasEnvironment('IAP_ENABLE_PURCHASES');

  static const String appleStarterMonthlyProductId = String.fromEnvironment(
    'IAP_APPLE_STARTER_MONTHLY_PRODUCT_ID',
    defaultValue: 'mixroom_starter_monthly',
  );

  static const String appleStarterYearlyProductId = String.fromEnvironment(
    'IAP_APPLE_STARTER_YEARLY_PRODUCT_ID',
    defaultValue: 'mixroom_starter_yearly',
  );

  static const String googleStarterMonthlyProductId = String.fromEnvironment(
    'IAP_GOOGLE_STARTER_MONTHLY_PRODUCT_ID',
    defaultValue: 'mixroom_starter_monthly',
  );

  static const String googleStarterYearlyProductId = String.fromEnvironment(
    'IAP_GOOGLE_STARTER_YEARLY_PRODUCT_ID',
    defaultValue: 'mixroom_starter_yearly',
  );

  static const String appleProducerMonthlyProductId = String.fromEnvironment(
    'IAP_APPLE_PRODUCER_MONTHLY_PRODUCT_ID',
    defaultValue: 'mixroom_producer_monthly',
  );

  static const String appleProducerYearlyProductId = String.fromEnvironment(
    'IAP_APPLE_PRODUCER_YEARLY_PRODUCT_ID',
    defaultValue: 'mixroom_producer_yearly',
  );

  static const String googleProducerMonthlyProductId = String.fromEnvironment(
    'IAP_GOOGLE_PRODUCER_MONTHLY_PRODUCT_ID',
    defaultValue: 'mixroom_producer_monthly',
  );

  static const String googleProducerYearlyProductId = String.fromEnvironment(
    'IAP_GOOGLE_PRODUCER_YEARLY_PRODUCT_ID',
    defaultValue: 'mixroom_producer_yearly',
  );

  static bool get isMobileTarget =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  static Set<String> productIdsForCurrentPlatform() {
    final ids = <String>{};
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        ids.addAll({
          appleStarterMonthlyProductId,
          appleStarterYearlyProductId,
          appleProducerMonthlyProductId,
          appleProducerYearlyProductId,
        });
        break;
      case TargetPlatform.android:
        ids.addAll({
          googleStarterMonthlyProductId,
          googleStarterYearlyProductId,
          googleProducerMonthlyProductId,
          googleProducerYearlyProductId,
        });
        break;
      default:
        break;
    }
    return ids;
  }

  static String primaryProductIdForCurrentPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return appleProducerMonthlyProductId;
      case TargetPlatform.android:
        return googleProducerMonthlyProductId;
      default:
        return '';
    }
  }
}
