import 'package:flutter/foundation.dart';

class IapConfig {
  const IapConfig._();

  static const bool purchasesEnabled = bool.fromEnvironment(
    'IAP_ENABLE_PURCHASES',
    defaultValue: false,
  );

  static const String appleProMonthlyProductId = String.fromEnvironment(
    'IAP_APPLE_PRO_MONTHLY_PRODUCT_ID',
    defaultValue: 'mixroom_pro_monthly',
  );

  static const String googleProMonthlyProductId = String.fromEnvironment(
    'IAP_GOOGLE_PRO_MONTHLY_PRODUCT_ID',
    defaultValue: 'mixroom_pro_monthly',
  );

  static const bool includeStudioTier = bool.fromEnvironment(
    'IAP_INCLUDE_STUDIO_TIER',
    defaultValue: false,
  );

  static const String appleStudioMonthlyProductId = String.fromEnvironment(
    'IAP_APPLE_STUDIO_MONTHLY_PRODUCT_ID',
    defaultValue: 'mixroom_studio_monthly',
  );

  static const String googleStudioMonthlyProductId = String.fromEnvironment(
    'IAP_GOOGLE_STUDIO_MONTHLY_PRODUCT_ID',
    defaultValue: 'mixroom_studio_monthly',
  );

  static bool get isMobileTarget =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  static Set<String> productIdsForCurrentPlatform() {
    final ids = <String>{};
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        ids.add(appleProMonthlyProductId);
        if (includeStudioTier) ids.add(appleStudioMonthlyProductId);
        break;
      case TargetPlatform.android:
        ids.add(googleProMonthlyProductId);
        if (includeStudioTier) ids.add(googleStudioMonthlyProductId);
        break;
      default:
        break;
    }
    return ids;
  }

  static String primaryProductIdForCurrentPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return appleProMonthlyProductId;
      case TargetPlatform.android:
        return googleProMonthlyProductId;
      default:
        return '';
    }
  }
}
