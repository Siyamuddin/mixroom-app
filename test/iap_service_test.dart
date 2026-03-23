import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
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

  group('IapService', () {
    test(
        'initialize loads products and buy uses signed-in application user name',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(
        buildProductDetails(
          description: 'Monthly plan',
        ),
      );
      final entitlement = FakeEntitlementService();
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      await service.buyProduct(service.products.single);

      expect(service.isInitialized, isTrue);
      expect(service.products, hasLength(1));
      expect(platform.lastPurchaseParam, isNotNull);
      expect(platform.lastPurchaseParam!.applicationUserName, 'user-1');
    });

    test(
        'purchased ios updates verify with backend, refreshes, and completes purchase',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(
        buildProductDetails(
          title: 'Mixroom Pro Monthly',
          description: 'Unlock monthly access',
        ),
      );
      final entitlement = FakeEntitlementService();
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      platform.purchaseController.add(
        <PurchaseDetails>[
          buildIosPurchaseDetails(status: PurchaseStatus.purchased),
        ],
      );
      await flushAsync();

      expect(entitlement.appleRequests, hasLength(1));
      expect(entitlement.appleRequests.single['billingCycle'], 'monthly');
      expect(entitlement.refreshCalls, 1);
      expect(platform.lastCompletedPurchase, isNotNull);
      expect(service.lastError, isNull);
    });

    test('transient verification failure queues purchase and retries later',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService()
        ..appleFailure = StateError(
            'Request /v1/billing/mobile/apple/verify failed (503): retry later');
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      platform.purchaseController.add(
        <PurchaseDetails>[
          buildIosPurchaseDetails(status: PurchaseStatus.purchased),
        ],
      );
      await flushAsync();

      final prefs = await SharedPreferences.getInstance();
      final queued = jsonDecode(
        prefs.getString('mixroom.iap.pending_verifications.v1')!,
      ) as List<dynamic>;
      expect(queued, hasLength(1));

      entitlement.appleFailure = null;
      service.bindEntitlementService(entitlement);
      await flushAsync();

      expect(entitlement.appleRequests, hasLength(1));
      expect(entitlement.refreshCalls, greaterThanOrEqualTo(1));
      expect(
        prefs.getString('mixroom.iap.pending_verifications.v1'),
        isNull,
      );
    });

    test('cross-account google failure is not queued', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService()
        ..googleFailure = StateError(
          'Request /v1/billing/mobile/google/verify failed (409): purchase belongs to a different Mixroom account.',
        );
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      platform.purchaseController.add(
        <PurchaseDetails>[
          buildAndroidPurchaseDetails(status: PurchaseStatus.purchased),
        ],
      );
      await flushAsync();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('mixroom.iap.pending_verifications.v1'),
        isNull,
      );
      expect(service.lastError, contains('different Mixroom account'));
    });

    test('restore purchases passes application user name to store', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = TestIapService();
      service.bindEntitlementService(FakeEntitlementService());

      await service.initialize();
      await service.restorePurchases();

      expect(platform.lastRestoreUserName, 'user-1');
    });
  });
}
