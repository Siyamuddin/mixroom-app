import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subscription_test_support.dart';

void main() {
  initTestBindings();

  late InAppPurchasePlatform? originalPlatform;
  late FakeIapPlatform platform;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    try {
      originalPlatform = InAppPurchasePlatform.instance;
    } catch (_) {
      originalPlatform = null;
    }
    platform = FakeIapPlatform();
    InAppPurchasePlatform.instance = platform;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    if (originalPlatform != null) {
      InAppPurchasePlatform.instance = originalPlatform!;
    }
  });

  test(
      'stubbed purchase flow upgrades entitlement without live store or backend',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final api = FakeSubscriptionApi();
    final auth = buildSignedInAuthService();
    final entitlementService = EntitlementService(
      httpClient: FakeHttpClient(api.handle),
    );
    entitlementService.bindAuth(auth);
    await flushAsync();

    platform.availableProducts.add(
      buildProductDetails(
        title: 'Mixroom Pro Monthly',
        description: 'Monthly access to pro features',
      ),
    );
    final iapService = TestIapService();
    iapService.bindEntitlementService(entitlementService);
    await iapService.initialize();

    platform.purchaseController.add(
      <PurchaseDetails>[
        buildIosPurchaseDetails(status: PurchaseStatus.purchased),
      ],
    );
    await flushAsync();

    expect(entitlementService.currentTier, PlanTier.pro);
    expect(entitlementService.isProEntitled, isTrue);
    expect(
      entitlementService.canUseCapability(SubscriptionCapability.proEditor),
      isTrue,
    );
    expect(platform.lastCompletedPurchase, isNotNull);
    expect(
      api.requests.any(
        (request) =>
            request.method == 'POST' &&
            request.path.endsWith('/v1/billing/mobile/apple/verify'),
      ),
      isTrue,
    );
  });
}
