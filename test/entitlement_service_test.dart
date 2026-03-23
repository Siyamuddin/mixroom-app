import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subscription_test_support.dart';

void main() {
  initTestBindings();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('EntitlementService', () {
    test('refresh loads entitlement from API and caches it', () async {
      final api = FakeSubscriptionApi(
        initialEntitlement: <String, dynamic>{
          'user_id': 'user-1',
          'tier': 'pro',
          'status': 'active',
          'effective_at': '2026-03-20T00:00:00Z',
          'expires_at': '2099-04-20T00:00:00Z',
          'source_provider': 'google',
          'source_subscription_id': 'google-sub-1',
          'capabilities': <String, bool>{
            'pro_editor': true,
            'premium_effects': true,
            'video_projects': true,
            'web_checkout': true,
            'mobile_iap': true,
          },
          'management_channel': 'google',
          'revision': 3,
        },
      );
      final auth = buildSignedInAuthService();
      final service = EntitlementService(
        httpClient: FakeHttpClient(api.handle),
      );

      service.bindAuth(auth);
      await service.refresh(force: true);

      expect(service.isInitialized, isTrue);
      expect(service.currentTier, PlanTier.pro);
      expect(service.isProEntitled, isTrue);
      expect(
          service.canUseCapability(SubscriptionCapability.proEditor), isTrue);

      final prefs = await SharedPreferences.getInstance();
      final cached = jsonDecode(
        prefs.getString('mixroom.subscription.entitlement.v1.user-1')!,
      ) as Map<String, dynamic>;
      expect(cached['tier'], 'pro');
      expect(
        api.requests.any(
          (request) =>
              request.method == 'GET' &&
              request.path.endsWith('/v1/entitlements/me'),
        ),
        isTrue,
      );
    });

    test('verify google purchase posts billing payload and refreshes tier',
        () async {
      final api = FakeSubscriptionApi();
      final auth = buildSignedInAuthService();
      final service = EntitlementService(
        httpClient: FakeHttpClient(api.handle),
      );

      service.bindAuth(auth);
      await flushAsync();
      await service.verifyGooglePurchase(
        purchaseToken: 'purchase-token',
        productId: 'mixroom_pro_monthly',
        packageName: 'ai.mixroom.test',
        obfuscatedAccountId: 'user-1',
        price: 9.99,
        currencyCode: 'USD',
        billingCycle: 'monthly',
      );

      expect(service.currentTier, PlanTier.pro);
      final verifyCall = api.requests.firstWhere(
        (request) =>
            request.method == 'POST' &&
            request.path.endsWith('/v1/billing/mobile/google/verify'),
      );
      expect(verifyCall.body?['purchase_token'], 'purchase-token');
      expect(verifyCall.body?['obfuscated_account_id'], 'user-1');
      expect(verifyCall.body?['billing_cycle'], 'monthly');
      expect(
        api.requests
            .where(
              (request) =>
                  request.method == 'GET' &&
                  request.path.endsWith('/v1/entitlements/me'),
            )
            .length,
        greaterThanOrEqualTo(2),
      );
    });

    test('checkout restore and portal helpers use authenticated API', () async {
      final api = FakeSubscriptionApi();
      final auth = buildSignedInAuthService();
      final service = EntitlementService(
        httpClient: FakeHttpClient(api.handle),
      );

      service.bindAuth(auth);
      await flushAsync();

      final checkout = await service.createWebCheckoutSession(
        regionCode: 'KR',
        successUrl: 'https://example.com/success',
        cancelUrl: 'https://example.com/cancel',
      );
      await service.restorePurchases(provider: BillingProvider.apple);
      final portalUrl = await service.fetchPortalUrl();

      expect(checkout['provider'], 'toss');
      expect(portalUrl, 'https://example.com/manage');
      expect(
        api.requests.any(
          (request) =>
              request.method == 'POST' &&
              request.path.endsWith('/v1/billing/restore') &&
              request.body?['provider'] == 'apple',
        ),
        isTrue,
      );
    });
  });
}
