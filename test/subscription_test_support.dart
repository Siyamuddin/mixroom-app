import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
              'tier': 'free',
              'status': 'active',
              'effective_at': '2026-03-20T00:00:00Z',
              'expires_at': null,
              'source_provider': 'admin_grant',
              'source_subscription_id': 'free-default',
              'capabilities': <String, bool>{
                'pro_editor': false,
                'premium_effects': false,
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
    if (request.method == 'GET' && path.endsWith('/v1/billing/portal-url')) {
      return http.Response(
        jsonEncode(<String, dynamic>{'url': 'https://example.com/manage'}),
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
      'tier': 'pro',
      'status': 'active',
      'effective_at': '2026-03-20T00:00:00Z',
      'expires_at': '2099-04-20T00:00:00Z',
      'source_provider': provider,
      'source_subscription_id': '$provider-sub-1',
      'capabilities': <String, bool>{
        'pro_editor': true,
        'premium_effects': true,
        'video_projects': true,
        'web_checkout': true,
        'mobile_iap': true,
      },
      'management_channel': provider,
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

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => purchaseController.stream;

  @override
  Future<bool> isAvailable() async => storeAvailable;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(
      productDetails: availableProducts
          .where((product) => identifiers.contains(product.id))
          .toList(),
      notFoundIDs: <String>[],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    lastPurchaseParam = purchaseParam;
    return true;
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

  final String accountToken;
  final List<Map<String, dynamic>> appleRequests = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> googleRequests = <Map<String, dynamic>>[];
  int refreshCalls = 0;
  Object? appleFailure;
  Object? googleFailure;

  @override
  String? get storeAccountToken => accountToken;

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
}

class TestIapService extends IapService {
  TestIapService({super.inAppPurchase});

  @override
  bool get purchasesEnabled => true;

  @override
  bool get isMobilePlatformSupported => true;
}

ProductDetails buildProductDetails({
  String id = 'mixroom_pro_monthly',
  String title = 'Mixroom Pro Monthly',
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

SK2PurchaseDetails buildIosPurchaseDetails({
  required PurchaseStatus status,
  String productId = 'mixroom_pro_monthly',
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
  String productId = 'mixroom_pro_monthly',
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
