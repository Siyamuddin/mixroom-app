import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/cognito_auth_client.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/helpers/iap_service.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void initTestBindings() {
  TestWidgetsFlutterBinding.ensureInitialized();
}

class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

class FakeSubscriptionApi {
  FakeSubscriptionApi({
    Map<String, dynamic>? initialEntitlement,
  }) : currentEntitlement = initialEntitlement ??
            <String, dynamic>{
              'user_id': 'user-1',
              'plan_code': 'free',
              'status': 'active',
              'effective_at': '2026-03-20T00:00:00Z',
              'expires_at': null,
              'source_provider': 'admin_grant',
              'source_subscription_id': 'free-default',
              'capabilities': <String, bool>{
                'all_plugins': false,
                'advanced_ai_models': false,
                'video_projects': true,
                'web_checkout': true,
                'mobile_iap': true,
              },
              'management_channel': 'free',
              'revision': 0,
            };

  final List<({String method, String path, Map<String, dynamic>? body})>
      requests = [];
  Map<String, dynamic> currentEntitlement;
  Map<String, dynamic> educationOrganization = <String, dynamic>{
    'organization_id': 'edu-1',
    'name': 'Mixroom Academy',
    'plan_code': 'education',
    'plan_label': 'Education',
    'plan_group': 'education',
    'role': 'teacher',
    'status': 'active',
    'membership_status': 'active',
    'seat_limit': 20,
    'seats_used': 1,
    'seats_active': 1,
    'seats_invited': 0,
    'seats_available': 19,
  };
  final List<Map<String, dynamic>> educationMemberships =
      <Map<String, dynamic>>[
    <String, dynamic>{
      'organization_id': 'edu-1',
      'user_id': 'teacher-1',
      'email': 'teacher@example.com',
      'role': 'teacher',
      'status': 'active',
      'seat_consumed': false,
    },
  ];

  Future<http.Response> handle(http.BaseRequest request) async {
    final path = request.url.path;
    final body = request is http.Request && request.body.isNotEmpty
        ? jsonDecode(request.body) as Map<String, dynamic>
        : null;
    requests.add((
      method: request.method,
      path: path,
      body: body,
    ));

    if (request.method == 'GET' && path.endsWith('/v1/entitlements/me')) {
      return http.Response(jsonEncode(currentEntitlement), 200);
    }
    if (request.method == 'GET' && path.endsWith('/v1/billing/catalog')) {
      return http.Response(
        jsonEncode(
          BillingCatalogSnapshot.localDefaults(requestedByUserId: 'user-1')
              .toJson(),
        ),
        200,
      );
    }
    if (request.method == 'GET' && path.endsWith('/v1/organizations/me')) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'organizations': <Map<String, dynamic>>[],
          'memberships': <Map<String, dynamic>>[],
          'summary': <String, dynamic>{},
          'configurable': true,
        }),
        200,
      );
    }
    if (request.method == 'GET' && path.endsWith('/v1/workspaces/me')) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'workspaces': <Map<String, dynamic>>[],
          'summary': <String, dynamic>{},
          'configurable': true,
        }),
        200,
      );
    }
    if (request.method == 'GET' && path.endsWith('/v1/cloud-projects/me')) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'cloud_projects': <Map<String, dynamic>>[],
          'summary': <String, dynamic>{},
          'configurable': true,
          'storage': <String, dynamic>{},
        }),
        200,
      );
    }
    if (request.method == 'GET' && path.endsWith('/v1/education/me')) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'organizations': <Map<String, dynamic>>[educationOrganization],
          'memberships': educationMemberships,
          'student_usage': <Map<String, dynamic>>[
            <String, dynamic>{
              'organization_id': 'edu-1',
              'user_id': 'invite:student',
              'email': 'student@example.com',
              'status': 'pending',
              'seat_consumed': true,
              'project_count': 0,
              'last_active_at': null,
            },
          ],
          'summary': <String, dynamic>{},
          'configurable': true,
        }),
        200,
      );
    }
    if (request.method == 'POST' && path.endsWith('/v1/education/me/invites')) {
      final email = (body?['email'] ?? '').toString();
      final membership = <String, dynamic>{
        'organization_id': body?['organization_id'],
        'user_id': 'invite:student',
        'email': email,
        'role': 'student',
        'status': 'pending',
        'seat_consumed': true,
        'invite_token': 'invite-token',
        'invite_url': 'https://www.mixroom.ai/signup?invite=invite-token',
      };
      educationMemberships.add(membership);
      educationOrganization = <String, dynamic>{
        ...educationOrganization,
        'seats_used': 2,
        'seats_invited': 1,
        'seats_available': 18,
      };
      return http.Response(
        jsonEncode(<String, dynamic>{
          'membership': membership,
          'email_sent': true,
        }),
        200,
      );
    }
    if (request.method == 'POST' &&
        path.endsWith('/v1/education/me/memberships')) {
      final userId = (body?['user_id'] ?? '').toString();
      final status = (body?['status'] ?? '').toString();
      final index = educationMemberships.indexWhere(
        (membership) => membership['user_id'] == userId,
      );
      if (index < 0) return http.Response('not found', 404);
      educationMemberships[index] = <String, dynamic>{
        ...educationMemberships[index],
        'status': status,
        'seat_consumed': status == 'active' || status == 'pending',
      };
      return http.Response(
        jsonEncode(<String, dynamic>{
          'membership': educationMemberships[index],
        }),
        200,
      );
    }
    if (request.method == 'POST' &&
        path.endsWith('/v1/education/invites/invite-token/accept')) {
      final membership = <String, dynamic>{
        'organization_id': 'edu-1',
        'user_id': 'user-1',
        'email': 'student@example.com',
        'role': 'student',
        'status': 'active',
        'seat_consumed': true,
      };
      return http.Response(
        jsonEncode(<String, dynamic>{'membership': membership}),
        200,
      );
    }
    if (request.method == 'GET' && path.endsWith('/v1/billing/portal-url')) {
      return http.Response(
        jsonEncode(<String, dynamic>{'url': 'https://example.com/manage'}),
        200,
      );
    }
    if (request.method == 'GET' && path.endsWith('/v1/billing/me')) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'provider': currentEntitlement['source_provider'] ?? 'unknown',
          'management_channel':
              currentEntitlement['management_channel'] ?? 'free',
          'plan': currentEntitlement['plan_code'] ?? 'free',
          'status': currentEntitlement['status'] ?? 'active',
          'manage_url': 'https://example.com/manage',
        }),
        200,
      );
    }
    if (request.method == 'POST' &&
        path.endsWith('/v1/billing/mobile/apple/verify')) {
      currentEntitlement = _proEntitlement('apple');
      return http.Response(
        jsonEncode(<String, dynamic>{'accepted': true, 'provider': 'apple'}),
        200,
      );
    }
    if (request.method == 'POST' &&
        path.endsWith('/v1/billing/mobile/google/verify')) {
      currentEntitlement = _proEntitlement('google');
      return http.Response(
        jsonEncode(<String, dynamic>{'accepted': true, 'provider': 'google'}),
        200,
      );
    }
    if (request.method == 'POST' && path.endsWith('/v1/billing/restore')) {
      return http.Response(
        jsonEncode(<String, dynamic>{'accepted': true}),
        200,
      );
    }
    if (request.method == 'POST' &&
        path.endsWith('/v1/billing/web/checkout-session')) {
      return http.Response(
        jsonEncode(
          <String, dynamic>{
            'provider': body?['region_code'] == 'KR' ? 'toss' : 'paddle',
            'checkout_url': 'https://example.com/checkout',
          },
        ),
        200,
      );
    }

    return http.Response('not found', 404);
  }

  Map<String, dynamic> _proEntitlement(String provider) {
    return <String, dynamic>{
      'user_id': 'user-1',
      'plan_code': 'producer',
      'status': 'active',
      'effective_at': '2026-03-20T00:00:00Z',
      'expires_at': '2099-04-20T00:00:00Z',
      'source_provider': provider,
      'source_subscription_id': '$provider-sub-1',
      'capabilities': <String, bool>{
        'all_plugins': true,
        'advanced_ai_models': true,
        'video_projects': true,
        'web_checkout': true,
        'mobile_iap': true,
      },
      'management_channel': provider,
      'product_code': 'producer_monthly',
      'revision': 1,
    };
  }
}

AuthService buildSignedInAuthService() {
  final auth = AuthService(restoreSessionOnInit: false);
  final user = AuthUserProfile(
    userId: 'user-1',
    email: 'user@example.com',
    displayName: 'User One',
    provider: AuthProviderType.email,
    emailVerified: true,
    createdAt: DateTime.utc(2026, 3, 20),
  );
  final tokens = CognitoTokens(
    accessToken: 'access-token',
    idToken: 'id-token',
    refreshToken: 'rt_test-session_secret',
    expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );
  auth.debugPrimeSession(user: user, tokens: tokens);
  return auth;
}

class FakeIapPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements InAppPurchasePlatform {
  final StreamController<List<PurchaseDetails>> purchaseController =
      StreamController<List<PurchaseDetails>>.broadcast();
  final List<ProductDetails> availableProducts = <ProductDetails>[];
  PurchaseParam? lastPurchaseParam;
  PurchaseDetails? lastCompletedPurchase;
  String? lastRestoreUserName;
  bool storeAvailable = true;
  bool buyResult = true;
  Object? queryProductFailure;
  Object? buyFailure;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => purchaseController.stream;

  @override
  Future<bool> isAvailable() async => storeAvailable;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    final failure = queryProductFailure;
    if (failure != null) throw failure;
    return ProductDetailsResponse(
      productDetails: availableProducts
          .where((product) => identifiers.contains(product.id))
          .toList(),
      notFoundIDs: <String>[],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    final failure = buyFailure;
    if (failure != null) throw failure;
    lastPurchaseParam = purchaseParam;
    return buyResult;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    lastRestoreUserName = applicationUserName;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    lastCompletedPurchase = purchase;
  }

  @override
  Future<String> countryCode() async => 'US';
}

class FakeEntitlementService extends EntitlementService {
  FakeEntitlementService({
    this.accountToken = 'user-1',
  }) : super();

  String accountToken;
  final List<Map<String, dynamic>> appleRequests = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> googleRequests = <Map<String, dynamic>>[];
  int refreshCalls = 0;
  Object? appleFailure;
  Object? googleFailure;
  EntitlementSnapshot? currentEntitlement;

  @override
  String? get storeAccountToken => accountToken;

  @override
  EntitlementSnapshot? get entitlement => currentEntitlement;

  @override
  Future<Map<String, dynamic>> verifyApplePurchase({
    required String transactionJws,
    String? productId,
    String? appAccountToken,
    double? price,
    String? currencyCode,
    String? billingCycle,
  }) async {
    if (appleFailure != null) throw appleFailure!;
    appleRequests.add(<String, dynamic>{
      'transactionJws': transactionJws,
      'productId': productId,
      'appAccountToken': appAccountToken,
      'price': price,
      'currencyCode': currencyCode,
      'billingCycle': billingCycle,
    });
    return <String, dynamic>{'accepted': true};
  }

  @override
  Future<Map<String, dynamic>> verifyGooglePurchase({
    required String purchaseToken,
    required String productId,
    String? packageName,
    String? obfuscatedAccountId,
    double? price,
    String? currencyCode,
    String? billingCycle,
  }) async {
    if (googleFailure != null) throw googleFailure!;
    googleRequests.add(<String, dynamic>{
      'purchaseToken': purchaseToken,
      'productId': productId,
      'packageName': packageName,
      'obfuscatedAccountId': obfuscatedAccountId,
      'price': price,
      'currencyCode': currencyCode,
      'billingCycle': billingCycle,
    });
    return <String, dynamic>{'accepted': true};
  }

  @override
  Future<void> refresh({bool force = false}) async {
    refreshCalls += 1;
  }

  void debugNotifyChanged() {
    notifyListeners();
  }
}

class TestIapService extends IapService {
  TestIapService({
    super.inAppPurchase,
    this.testPurchaseLaunchWatchdogDuration,
    this.googlePastPurchasesResponse,
    this.restorablePurchasesResponse,
  });

  final Duration? testPurchaseLaunchWatchdogDuration;
  QueryPurchaseDetailsResponse? googlePastPurchasesResponse;
  List<PurchaseDetails>? restorablePurchasesResponse;

  @override
  bool get purchasesEnabled => true;

  @override
  bool get isMobilePlatformSupported => true;

  @override
  Duration? get purchaseLaunchWatchdogDuration =>
      testPurchaseLaunchWatchdogDuration;

  @override
  Future<QueryPurchaseDetailsResponse>
      queryPastGooglePurchasesForSubscriptionChange(
    String applicationUserName,
  ) async {
    final response = googlePastPurchasesResponse;
    if (response != null) {
      return response;
    }
    return QueryPurchaseDetailsResponse(
      pastPurchases: const <GooglePlayPurchaseDetails>[],
    );
  }

  @override
  Future<List<PurchaseDetails>> queryRestorablePurchases(
    String applicationUserName,
  ) async {
    final response = restorablePurchasesResponse;
    if (response != null) {
      return response;
    }
    return super.queryRestorablePurchases(applicationUserName);
  }
}

ProductDetails buildProductDetails({
  String id = 'mixroom_producer_monthly',
  String title = 'Mixroom Producer Monthly',
  String description = 'Monthly plan',
  double rawPrice = 9.99,
  String currencyCode = 'USD',
}) {
  return ProductDetails(
    id: id,
    title: title,
    description: description,
    price: '\$${rawPrice.toStringAsFixed(2)}',
    rawPrice: rawPrice,
    currencyCode: currencyCode,
  );
}

EntitlementSnapshot buildPaidEntitlement({
  BillingProvider sourceProvider = BillingProvider.apple,
  String managementChannel = 'apple',
  String planCode = 'producer',
  String productCode = 'producer_monthly',
}) {
  return EntitlementSnapshot(
    userId: 'user-1',
    status: SubscriptionStatus.active,
    effectiveAt: DateTime.now().toUtc(),
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    sourceProvider: sourceProvider,
    sourceSubscriptionId: '${sourceProvider.name}-sub-1',
    capabilities: defaultCapabilitiesForPlanCode(planCode),
    managementChannel: managementChannel,
    revision: 1,
    planCode: planCode,
    planLabel: defaultPlanLabelForCode(planCode),
    planGroup: 'individual',
    productCode: productCode,
    nextBilledAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    seatCount: null,
    extraStorageTb: 0,
    paddleSubscriptionId: sourceProvider == BillingProvider.paddle
        ? '${sourceProvider.name}-sub-1'
        : '',
    limits: defaultLimitsForPlanCode(planCode),
    accessSources: const <AccountAccessSource>[],
    workspaceAccessSummary: const CollaborationAccessSummary(
      organizationCount: 0,
      workspaceCount: 0,
      cloudProjectCount: 0,
    ),
    organizations: const <OrganizationAccessItem>[],
    billingSupport: BillingSupportInfo.defaults(),
  );
}

SK2PurchaseDetails buildIosPurchaseDetails({
  required PurchaseStatus status,
  String productId = 'mixroom_producer_monthly',
  String verificationData = 'signed-transaction',
  String? appAccountToken = 'user-1',
}) {
  return SK2PurchaseDetails(
    productID: productId,
    purchaseID: 'ios-purchase-1',
    verificationData: PurchaseVerificationData(
      localVerificationData: verificationData,
      serverVerificationData: verificationData,
      source: 'app_store',
    ),
    transactionDate: '1710892800000',
    status: status,
    appAccountToken: appAccountToken,
  );
}

GooglePlayPurchaseDetails buildAndroidPurchaseDetails({
  required PurchaseStatus status,
  String productId = 'mixroom_producer_monthly',
  String purchaseToken = 'purchase-token',
  bool isAcknowledged = false,
  String? obfuscatedAccountId = 'user-1',
}) {
  final purchase = PurchaseWrapper(
    orderId: 'order-1',
    packageName: 'ai.mixroom.test',
    purchaseTime: 1710892800000,
    purchaseToken: purchaseToken,
    signature: 'sig',
    products: <String>[productId],
    isAutoRenewing: true,
    originalJson: '{}',
    isAcknowledged: isAcknowledged,
    purchaseState: PurchaseStateWrapper.purchased,
    obfuscatedAccountId: obfuscatedAccountId,
  );
  return GooglePlayPurchaseDetails(
    purchaseID: 'android-purchase-1',
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: purchaseToken,
      serverVerificationData: purchaseToken,
      source: 'google_play',
    ),
    transactionDate: '1710892800000',
    billingClientPurchase: purchase,
    status: status,
  );
}

Future<void> flushAsync() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
