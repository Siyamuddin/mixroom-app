import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
    test('exposes local billing catalog before network account surface loads',
        () {
      final service = EntitlementService(
        httpClient: FakeHttpClient(FakeSubscriptionApi().handle),
      );

      final catalog = service.billingCatalog;

      expect(catalog, isNotNull);
      expect(catalog!.enabledProductsForPlatform('ios'), hasLength(4));
      expect(
        catalog
            .bestProviderProductForProduct(
              productCode: 'starter_monthly',
              provider: BillingProvider.apple,
            )
            ?.providerProductId,
        'mixroom_starter_monthly',
      );
      expect(catalog.planByCode('producer')?.limits['ai_prompts_daily'], 1000);
    });

    test(
        'publishes billing catalog before slower account surface endpoints finish',
        () async {
      final slowAccountEndpoints = Completer<void>();
      final api = FakeSubscriptionApi();
      final catalogJson = BillingCatalogSnapshot.localDefaults(
        requestedByUserId: 'user-1',
      ).toJson();
      final products = catalogJson['products'] as List<dynamic>;
      products[0] = <String, dynamic>{
        ...(products[0] as Map<String, dynamic>),
        'label': 'Fast Starter Monthly',
      };
      final service = EntitlementService(
        httpClient: FakeHttpClient((request) async {
          final path = request.url.path;
          if (request.method == 'GET' && path.endsWith('/v1/billing/catalog')) {
            return http.Response(jsonEncode(catalogJson), 200);
          }
          if (request.method == 'GET' &&
              (path.endsWith('/v1/organizations/me') ||
                  path.endsWith('/v1/workspaces/me') ||
                  path.endsWith('/v1/cloud-projects/me'))) {
            await slowAccountEndpoints.future;
          }
          return api.handle(request);
        }),
      );

      service.bindAuth(buildSignedInAuthService());
      await flushAsync();

      expect(service.isAccountSurfaceLoading, isTrue);
      expect(
          service.billingCatalog?.products.first.label, 'Fast Starter Monthly');

      slowAccountEndpoints.complete();
      await flushAsync();

      expect(service.isAccountSurfaceLoading, isFalse);
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(
        'mixroom.subscription.billing_catalog.v1.user-1',
      );
      expect(cached, isNotNull);
      expect(cached, contains('Fast Starter Monthly'));
    });

    test('refresh loads entitlement from API and caches it', () async {
      final api = FakeSubscriptionApi(
        initialEntitlement: <String, dynamic>{
          'user_id': 'user-1',
          'plan_code': 'producer',
          'status': 'active',
          'effective_at': '2026-03-20T00:00:00Z',
          'expires_at': '2099-04-20T00:00:00Z',
          'source_provider': 'google',
          'source_subscription_id': 'google-sub-1',
          'capabilities': <String, bool>{
            'all_plugins': true,
            'advanced_ai_models': true,
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
      expect(service.currentPlanCode, 'producer');
      expect(
          service.canUseCapability(SubscriptionCapability.allPlugins), isTrue);

      final prefs = await SharedPreferences.getInstance();
      final cached = jsonDecode(
        prefs.getString('mixroom.subscription.entitlement.v1.user-1')!,
      ) as Map<String, dynamic>;
      expect(cached['plan_code'], 'producer');
      expect(
        api.requests.any(
          (request) =>
              request.method == 'GET' &&
              request.path.endsWith('/v1/entitlements/me'),
        ),
        isTrue,
      );
    });

    test('refresh failure keeps last known paid entitlement', () async {
      var failEntitlementRefresh = false;
      final api = FakeSubscriptionApi(
        initialEntitlement: <String, dynamic>{
          'user_id': 'user-1',
          'plan_code': 'starter',
          'status': 'active',
          'effective_at': '2026-03-20T00:00:00Z',
          'expires_at': '2099-04-20T00:00:00Z',
          'source_provider': 'apple',
          'source_subscription_id': 'apple-sub-1',
          'capabilities': <String, bool>{
            'all_plugins': true,
            'video_projects': true,
            'web_checkout': true,
            'mobile_iap': true,
            'cloud_projects': true,
          },
          'management_channel': 'apple',
          'revision': 4,
        },
      );
      final auth = buildSignedInAuthService();
      final service = EntitlementService(
        httpClient: FakeHttpClient((request) async {
          if (failEntitlementRefresh &&
              request.method == 'GET' &&
              request.url.path.endsWith('/v1/entitlements/me')) {
            return http.Response(
              jsonEncode(<String, dynamic>{'error': 'Internal server error'}),
              500,
            );
          }
          return api.handle(request);
        }),
      );

      service.bindAuth(auth);
      await service.refresh(force: true);
      expect(service.currentPlanCode, 'starter');

      failEntitlementRefresh = true;
      await service.refresh(force: true);

      expect(service.currentPlanCode, 'starter');
      expect(service.lastError, contains('500'));
      expect(
        service.canUseCapability(SubscriptionCapability.cloudProjects),
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
        productId: 'mixroom_producer_monthly',
        packageName: 'ai.mixroom.test',
        obfuscatedAccountId: 'user-1',
        price: 9.99,
        currencyCode: 'USD',
        billingCycle: 'monthly',
      );

      expect(service.currentPlanCode, 'producer');
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

    test('education admin helpers fetch invite update and accept seats',
        () async {
      final api = FakeSubscriptionApi();
      final auth = buildSignedInAuthService();
      final service = EntitlementService(
        httpClient: FakeHttpClient(api.handle),
      );

      service.bindAuth(auth);
      await flushAsync();

      final snapshot = await service.fetchEducationAdmin();
      final invite = await service.inviteEducationStudent(
        organizationId: 'edu-1',
        email: 'student@example.com',
      );
      final released = await service.updateEducationMembership(
        organizationId: 'edu-1',
        userId: 'invite:student',
        status: 'revoked',
        email: 'student@example.com',
      );
      final accepted = await service.acceptEducationInvite(
        inviteToken: 'invite-token',
      );

      expect(snapshot.organizations.single.planCode, 'education');
      expect(snapshot.studentUsage.single.projectCount, 0);
      expect(invite.emailSent, isTrue);
      expect(invite.membership?.status, 'pending');
      expect(invite.membership?.inviteUrl, contains('invite-token'));
      expect(released?.status, 'revoked');
      expect(accepted?.status, 'active');
      expect(
        api.requests.any(
          (request) =>
              request.method == 'POST' &&
              request.path.endsWith('/v1/education/me/invites'),
        ),
        isTrue,
      );
      expect(
        api.requests.any(
          (request) =>
              request.method == 'POST' &&
              request.path.endsWith('/v1/education/me/memberships'),
        ),
        isTrue,
      );
    });
  });
}
