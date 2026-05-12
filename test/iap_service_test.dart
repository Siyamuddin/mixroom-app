import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:mixroom/config/iap_config.dart';
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

  group('IapService', () {
    test('launch IAP product set includes starter and producer only', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(IapConfig.productIdsForCurrentPlatform(), <String>{
        'mixroom_starter_monthly',
        'mixroom_starter_yearly',
        'mixroom_producer_monthly',
        'mixroom_producer_yearly',
      });

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(IapConfig.productIdsForCurrentPlatform(), <String>{
        'mixroom_starter_monthly',
        'mixroom_starter_yearly',
        'mixroom_producer_monthly',
        'mixroom_producer_yearly',
      });
    });

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
      expect(service.isPurchaseInProgress, isFalse);
      expect(service.lastMessage, 'Complete the purchase in the store sheet.');
    });

    test('plan change does not keep buttons blocked after store launch',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final service = TestIapService();
      service.bindEntitlementService(FakeEntitlementService());

      await service.initialize();
      await service.buyProduct(
        service.products.single,
        storePlanChangeMayBeDeferred: true,
      );

      expect(service.isPurchaseInProgress, isFalse);
      expect(
        service.lastMessage,
        'Complete the purchase in the store sheet.',
      );
    });

    test('idle purchase stream errors stay quiet', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final service = TestIapService();
      service.bindEntitlementService(FakeEntitlementService());

      await service.initialize();
      platform.purchaseController.addError(
        StateError('in_app_purchase_storekit.PigeonError'),
        StackTrace.current,
      );
      await flushAsync();

      expect(service.isPurchaseInProgress, isFalse);
      expect(service.isStoreSheetOpening, isFalse);
      expect(service.lastError, isNull);
      expect(service.lastMessage, isNull);
    });

    test('storekit platform exceptions use user friendly purchase copy',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      platform.buyFailure = PlatformException(
        code: 'unknown',
        message: 'StoreKitError',
        details: 'Stacktrace: Runner.debug.dylib in_app_purchase_storekit',
      );
      final service = TestIapService();
      service.bindEntitlementService(FakeEntitlementService());

      await service.initialize();
      await service.buyProduct(service.products.single);

      expect(
        service.lastError,
        'The App Store could not complete that request. Please try again.',
      );
      expect(service.lastError, isNot(contains('PlatformException')));
      expect(service.lastError, isNot(contains('Stacktrace')));
    });

    test('deferred plan change purchase uses clear synced copy', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService();
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      await service.buyProduct(
        service.products.single,
        storePlanChangeMayBeDeferred: true,
      );
      platform.purchaseController.add(
        <PurchaseDetails>[
          buildIosPurchaseDetails(status: PurchaseStatus.purchased),
        ],
      );
      await flushAsync();

      expect(service.isPurchaseInProgress, isFalse);
      expect(
        service.lastMessage,
        'Plan change synced. Downgrades and billing-cycle changes may take effect at renewal.',
      );
      expect(
          service.lastCompletedPurchaseProductId, 'mixroom_producer_monthly');
      expect(service.lastCompletedPurchaseAtUtc, isNotNull);
      expect(service.lastCompletedPurchaseMayBeDeferred, isTrue);
    });

    test('buy clears progress when store launch is rejected', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      platform.buyResult = false;
      final service = TestIapService();
      service.bindEntitlementService(FakeEntitlementService());

      await service.initialize();
      await service.buyProduct(service.products.single);

      expect(service.isPurchaseInProgress, isFalse);
      expect(service.lastError, 'Purchase could not be started.');
      expect(service.lastMessage, isNull);
    });

    test('canceled purchase clears progress without backend verification',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService();
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      await service.buyProduct(service.products.single);
      platform.purchaseController.add(
        <PurchaseDetails>[
          buildIosPurchaseDetails(status: PurchaseStatus.canceled),
        ],
      );
      await flushAsync();

      expect(service.isPurchaseInProgress, isFalse);
      expect(entitlement.appleRequests, isEmpty);
      expect(service.lastError, isNull);
      expect(service.lastMessage, contains('Purchase canceled'));
    });

    test('store launch handoff clears progress without terminal update',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final service = TestIapService();
      service.bindEntitlementService(FakeEntitlementService());

      await service.initialize();
      await service.buyProduct(service.products.single);

      expect(service.isPurchaseInProgress, isFalse);
      expect(service.lastError, isNull);
      expect(service.lastMessage, 'Complete the purchase in the store sheet.');
    });

    test(
        'purchased ios updates verify with backend, refreshes, and completes purchase',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(
        buildProductDetails(
          title: 'Mixroom Producer Monthly',
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
      expect(service.lastCompletedPurchaseAtUtc, isNull);
    });

    test('ios verification falls back to signed-in account token', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService(accountToken: 'user-1');
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      platform.purchaseController.add(
        <PurchaseDetails>[
          buildIosPurchaseDetails(
            status: PurchaseStatus.purchased,
            appAccountToken: null,
          ),
        ],
      );
      await flushAsync();

      expect(entitlement.appleRequests, hasLength(1));
      expect(entitlement.appleRequests.single['appAccountToken'], 'user-1');
    });

    test('empty verification payload refreshes quietly without snackbar error',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService();
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      platform.purchaseController.add(
        <PurchaseDetails>[
          buildIosPurchaseDetails(
            status: PurchaseStatus.restored,
            verificationData: '',
          ),
        ],
      );
      await flushAsync();

      expect(entitlement.appleRequests, isEmpty);
      expect(entitlement.refreshCalls, 1);
      expect(service.isPurchaseInProgress, isFalse);
      expect(service.lastError, isNull);
      expect(service.lastMessage, isNull);
    });

    test('replayed purchase updates are verified once per app session',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService();
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      final purchase = buildIosPurchaseDetails(
        status: PurchaseStatus.restored,
        verificationData: 'same-signed-transaction',
      );
      platform.purchaseController.add(<PurchaseDetails>[purchase]);
      await flushAsync();
      platform.purchaseController.add(<PurchaseDetails>[purchase]);
      await flushAsync();

      expect(entitlement.appleRequests, hasLength(1));
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

    test('replayed auth failure queues quietly without snackbar error',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService()
        ..appleFailure = StateError(
          'Request /v1/billing/mobile/apple/verify failed (401): unauthorized',
        );
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      platform.purchaseController.add(
        <PurchaseDetails>[
          buildIosPurchaseDetails(status: PurchaseStatus.restored),
        ],
      );
      await flushAsync();

      final prefs = await SharedPreferences.getInstance();
      final queued = jsonDecode(
        prefs.getString('mixroom.iap.pending_verifications.v1')!,
      ) as List<dynamic>;
      expect(queued, hasLength(1));
      expect(service.lastError, isNull);
      expect(service.lastMessage, isNull);
    });

    test('replayed purchase waits quietly until account token is ready',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService(accountToken: '');
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      platform.purchaseController.add(
        <PurchaseDetails>[
          buildIosPurchaseDetails(status: PurchaseStatus.restored),
        ],
      );
      await flushAsync();

      final prefs = await SharedPreferences.getInstance();
      expect(entitlement.appleRequests, isEmpty);
      expect(
        prefs.getString('mixroom.iap.pending_verifications.v1'),
        isNull,
      );
      expect(service.lastError, isNull);
      expect(service.lastMessage, isNull);

      entitlement.accountToken = 'user-1';
      entitlement.debugNotifyChanged();
      await flushAsync();

      expect(entitlement.appleRequests, hasLength(1));
      expect(entitlement.appleRequests.single['transactionJws'],
          'signed-transaction');
    });

    test('replayed cross-account apple transaction is quiet after active sync',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService()
        ..currentEntitlement = EntitlementSnapshot(
          userId: 'user-1',
          status: SubscriptionStatus.active,
          effectiveAt: DateTime.now().toUtc(),
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          sourceProvider: BillingProvider.apple,
          sourceSubscriptionId: 'apple-sub-1',
          capabilities: defaultCapabilitiesForPlanCode('producer'),
          managementChannel: 'apple',
          revision: 1,
          planCode: 'producer',
          planLabel: 'Producer',
          planGroup: 'individual',
          productCode: 'producer_monthly',
          limits: defaultLimitsForPlanCode('producer'),
          accessSources: const <AccountAccessSource>[],
          workspaceAccessSummary: const CollaborationAccessSummary(
            organizationCount: 0,
            workspaceCount: 0,
            cloudProjectCount: 0,
          ),
          organizations: const <OrganizationAccessItem>[],
          billingSupport: BillingSupportInfo.defaults(),
        )
        ..appleFailure = StateError(
          'Request /v1/billing/mobile/apple/verify failed (409): Apple purchase belongs to a different Mixroom account.',
        );
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      platform.purchaseController.add(
        <PurchaseDetails>[
          buildIosPurchaseDetails(status: PurchaseStatus.restored),
        ],
      );
      await flushAsync();

      expect(entitlement.refreshCalls, 1);
      expect(service.lastError, isNull);
      expect(service.lastMessage, isNull);
    });

    test('mismatched apple replay is sent to backend for reclaim decision',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService(accountToken: 'current-user');
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      platform.purchaseController.add(
        <PurchaseDetails>[
          buildIosPurchaseDetails(
            status: PurchaseStatus.purchased,
            appAccountToken: 'other-user',
          ),
        ],
      );
      await flushAsync();

      expect(entitlement.appleRequests, hasLength(1));
      expect(
          entitlement.appleRequests.single['appAccountToken'], 'current-user');
      expect(service.isPurchaseInProgress, isFalse);
      expect(service.lastError, isNull);
      expect(service.lastMessage, 'Purchase synced.');
    });

    test('cross-account store failure is not queued and uses friendly copy',
        () async {
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
      expect(
        service.lastError,
        'This App Store or Google Play subscription is already linked to another Mixroom account. Sign in to that account, or manage the subscription in the store before subscribing here.',
      );
    });

    test('cross-account conflict blocks immediate checkout retry', () async {
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

      await service.buyProduct(service.products.single);

      expect(platform.lastPurchaseParam, isNull);
      expect(
        service.lastError,
        'This App Store or Google Play subscription is already linked to another Mixroom account. Sign in to that account, or manage the subscription in the store before subscribing here.',
      );
    });

    test('active web subscription blocks mobile store checkout', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.availableProducts.add(buildProductDetails());
      final entitlement = FakeEntitlementService()
        ..currentEntitlement = buildPaidEntitlement(
          sourceProvider: BillingProvider.paddle,
          managementChannel: 'web',
        );
      final service = TestIapService();
      service.bindEntitlementService(entitlement);

      await service.initialize();
      await service.buyProduct(service.products.single);

      expect(platform.lastPurchaseParam, isNull);
      expect(
        service.lastError,
        'You already have an active subscription. Manage or cancel it before subscribing again.',
      );
    });

    test('android upgrade uses old purchase token with prorated replacement',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      platform.availableProducts.add(
        buildProductDetails(
          id: 'mixroom_producer_monthly',
          title: 'Mixroom Producer Monthly',
        ),
      );
      final service = TestIapService(
        googlePastPurchasesResponse: QueryPurchaseDetailsResponse(
          pastPurchases: <GooglePlayPurchaseDetails>[
            buildAndroidPurchaseDetails(
              status: PurchaseStatus.purchased,
              productId: 'mixroom_starter_monthly',
              purchaseToken: 'starter-token',
              obfuscatedAccountId: 'user-1',
            ),
          ],
        ),
      );
      service.bindEntitlementService(FakeEntitlementService());

      await service.initialize();
      await service.buyProduct(
        service.products.single,
        requiresAndroidSubscriptionChange: true,
      );

      final purchaseParam =
          platform.lastPurchaseParam! as GooglePlayPurchaseParam;
      final changeParam = purchaseParam.changeSubscriptionParam!;
      expect(
          changeParam.oldPurchaseDetails.productID, 'mixroom_starter_monthly');
      expect(
        changeParam.oldPurchaseDetails.verificationData.serverVerificationData,
        'starter-token',
      );
      expect(changeParam.replacementMode, ReplacementMode.chargeProratedPrice);
    });

    test('android downgrade uses old purchase token with deferred replacement',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      platform.availableProducts.add(
        buildProductDetails(
          id: 'mixroom_starter_monthly',
          title: 'Mixroom Starter Monthly',
        ),
      );
      final service = TestIapService(
        googlePastPurchasesResponse: QueryPurchaseDetailsResponse(
          pastPurchases: <GooglePlayPurchaseDetails>[
            buildAndroidPurchaseDetails(
              status: PurchaseStatus.purchased,
              productId: 'mixroom_producer_monthly',
              purchaseToken: 'producer-token',
              obfuscatedAccountId: 'user-1',
            ),
          ],
        ),
      );
      service.bindEntitlementService(FakeEntitlementService());

      await service.initialize();
      await service.buyProduct(
        service.products.single,
        requiresAndroidSubscriptionChange: true,
      );

      final purchaseParam =
          platform.lastPurchaseParam! as GooglePlayPurchaseParam;
      final changeParam = purchaseParam.changeSubscriptionParam!;
      expect(
          changeParam.oldPurchaseDetails.productID, 'mixroom_producer_monthly');
      expect(
        changeParam.oldPurchaseDetails.verificationData.serverVerificationData,
        'producer-token',
      );
      expect(changeParam.replacementMode, ReplacementMode.deferred);
    });

    test('android plan change ignores old purchases for other Mixroom accounts',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      platform.availableProducts.add(
        buildProductDetails(
          id: 'mixroom_producer_monthly',
          title: 'Mixroom Producer Monthly',
        ),
      );
      final service = TestIapService(
        googlePastPurchasesResponse: QueryPurchaseDetailsResponse(
          pastPurchases: <GooglePlayPurchaseDetails>[
            buildAndroidPurchaseDetails(
              status: PurchaseStatus.purchased,
              productId: 'mixroom_starter_monthly',
              purchaseToken: 'other-user-token',
              obfuscatedAccountId: 'user-2',
            ),
          ],
        ),
      );
      service.bindEntitlementService(FakeEntitlementService());

      await service.initialize();
      await service.buyProduct(
        service.products.single,
        requiresAndroidSubscriptionChange: true,
      );

      expect(platform.lastPurchaseParam, isNull);
      expect(
        service.lastError,
        'Could not find your current Google Play subscription. Open Manage plan to change subscriptions safely.',
      );
    });

    test('restore purchases passes application user name to store', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = TestIapService();
      service.bindEntitlementService(FakeEntitlementService());

      await service.initialize();
      await service.restorePurchases();

      expect(platform.lastRestoreUserName, 'user-1');
    });

    test('restore verifies queried android purchases immediately', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final entitlement = FakeEntitlementService();
      final service = TestIapService(
        googlePastPurchasesResponse: QueryPurchaseDetailsResponse(
          pastPurchases: <GooglePlayPurchaseDetails>[
            buildAndroidPurchaseDetails(
              status: PurchaseStatus.purchased,
              purchaseToken: 'active-token',
              obfuscatedAccountId: 'user-1',
            ),
          ],
        ),
      );
      service.bindEntitlementService(entitlement);

      await service.initialize();
      await service.restorePurchases();

      expect(entitlement.googleRequests, hasLength(1));
      expect(
          entitlement.googleRequests.single['purchaseToken'], 'active-token');
      expect(entitlement.refreshCalls, 1);
      expect(service.lastError, isNull);
      expect(service.lastMessage, 'Purchase restored.');
    });

    test('restore reports no active purchase when query is empty', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final entitlement = FakeEntitlementService();
      final service = TestIapService(
        googlePastPurchasesResponse: QueryPurchaseDetailsResponse(
          pastPurchases: const <GooglePlayPurchaseDetails>[],
        ),
      );
      service.bindEntitlementService(entitlement);

      await service.initialize();
      await service.restorePurchases();

      expect(entitlement.googleRequests, isEmpty);
      expect(entitlement.refreshCalls, 0);
      expect(service.lastError, isNull);
      expect(service.lastMessage, 'No active purchase found.');
    });

    test('restore blocks queried purchase for another Mixroom account',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final entitlement = FakeEntitlementService();
      final service = TestIapService(
        googlePastPurchasesResponse: QueryPurchaseDetailsResponse(
          pastPurchases: <GooglePlayPurchaseDetails>[
            buildAndroidPurchaseDetails(
              status: PurchaseStatus.purchased,
              purchaseToken: 'other-account-token',
              obfuscatedAccountId: 'user-2',
            ),
          ],
        ),
      );
      service.bindEntitlementService(entitlement);

      await service.initialize();
      await service.restorePurchases();

      expect(entitlement.googleRequests, isEmpty);
      expect(service.lastMessage, isNull);
      expect(
        service.lastError,
        'This App Store or Google Play subscription is already linked to another Mixroom account. Sign in to that account, or manage the subscription in the store before subscribing here.',
      );
    });
  });
}
