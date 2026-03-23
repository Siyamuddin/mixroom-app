import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:mixroom/config/iap_config.dart';
import 'package:mixroom/core/analytics/analytics_events.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/core/security/sensitive_storage.dart';
import 'package:mixroom/helpers/entitlement_service.dart';

class IapService extends ChangeNotifier {
  static const String _pendingVerificationPrefsKey =
      'mixroom.iap.pending_verifications.v1';

  IapService({
    InAppPurchase? inAppPurchase,
  }) : _iap = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  EntitlementService? _entitlementService;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  bool _initializing = false;
  bool _initialized = false;
  bool _storeAvailable = false;
  bool _purchaseInProgress = false;
  bool _isRetryingPendingVerifications = false;
  List<ProductDetails> _products = const <ProductDetails>[];
  String? _lastError;
  DateTime? _lastSyncedAtUtc;

  bool get isInitializing => _initializing;
  bool get isInitialized => _initialized;
  bool get isStoreAvailable => _storeAvailable;
  bool get isPurchaseInProgress => _purchaseInProgress;
  List<ProductDetails> get products => _products;
  String? get lastError => _lastError;
  DateTime? get lastSyncedAtUtc => _lastSyncedAtUtc;

  bool get isMobilePlatformSupported => IapConfig.isMobileTarget;
  bool get purchasesEnabled => IapConfig.purchasesEnabled;

  void bindEntitlementService(EntitlementService entitlementService) {
    _entitlementService = entitlementService;
    if (_initialized && !_initializing) {
      unawaited(_retryPendingVerifications());
    }
  }

  Future<void> initialize() async {
    if (_initializing || _initialized) return;
    _initializing = true;
    _lastError = null;
    notifyListeners();

    try {
      if (!isMobilePlatformSupported) {
        _storeAvailable = false;
        _products = const <ProductDetails>[];
        _initialized = true;
        return;
      }

      _purchaseSubscription ??=
          _iap.purchaseStream.listen(_handlePurchaseUpdates);

      _storeAvailable = await _iap.isAvailable();
      if (_storeAvailable) {
        await refreshProducts();
      } else {
        _products = const <ProductDetails>[];
      }
      _initialized = true;
      unawaited(_retryPendingVerifications());
    } catch (e) {
      _lastError = e.toString().replaceFirst('Bad state: ', '');
      _initialized = true;
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> refreshProducts() async {
    if (!isMobilePlatformSupported) return;
    try {
      final ids = IapConfig.productIdsForCurrentPlatform();
      if (ids.isEmpty) {
        _products = const <ProductDetails>[];
        _lastSyncedAtUtc = DateTime.now().toUtc();
        notifyListeners();
        return;
      }
      final response = await _iap.queryProductDetails(ids);
      _products = List<ProductDetails>.from(response.productDetails);
      _lastError = response.error?.message;
      _lastSyncedAtUtc = DateTime.now().toUtc();
      notifyListeners();
    } catch (e) {
      _lastError = e.toString().replaceFirst('Bad state: ', '');
      notifyListeners();
    }
  }

  ProductDetails? findProductById(String productId) {
    for (final product in _products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  Future<void> buyProduct(ProductDetails product) async {
    if (!isMobilePlatformSupported) {
      _lastError = 'In-app purchases are only supported on iOS/Android.';
      notifyListeners();
      return;
    }

    if (!_storeAvailable) {
      _lastError = 'Store is not available on this device right now.';
      notifyListeners();
      return;
    }

    if (!purchasesEnabled) {
      _lastError = 'Purchases are disabled in this build (placeholder mode).';
      notifyListeners();
      return;
    }

    _purchaseInProgress = true;
    _lastError = null;
    notifyListeners();

    try {
      final applicationUserName = _applicationUserName();
      if (applicationUserName == null) {
        throw StateError('Sign in is required before starting a purchase.');
      }
      final purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: applicationUserName,
      );
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      _purchaseInProgress = false;
      _lastError = e.toString().replaceFirst('Bad state: ', '');
      unawaited(
        AnalyticsService.instance.track(
          AnalyticsEvents.purchaseFailed(errorCode: _lastError ?? 'unknown'),
        ),
      );
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    if (!isMobilePlatformSupported) {
      _lastError = 'Restore is only supported on iOS/Android.';
      notifyListeners();
      return;
    }
    if (!_storeAvailable) {
      _lastError = 'Store is not available on this device right now.';
      notifyListeners();
      return;
    }
    try {
      await _iap.restorePurchases(
        applicationUserName: _applicationUserName(),
      );
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _lastError = e.toString().replaceFirst('Bad state: ', '');
      notifyListeners();
    }
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _purchaseInProgress = true;
        notifyListeners();
        continue;
      }

      if (purchaseDetails.status == PurchaseStatus.error) {
        _purchaseInProgress = false;
        _lastError = purchaseDetails.error?.message ?? 'Purchase failed.';
        unawaited(
          AnalyticsService.instance.track(
            AnalyticsEvents.purchaseFailed(errorCode: _lastError ?? 'unknown'),
          ),
        );
        notifyListeners();
      }

      if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        try {
          await _verifyWithBackendIfAvailable(purchaseDetails);
          await _removePendingVerification(purchaseDetails);
          await _entitlementService?.refresh(force: true);
          _lastError = null;
        } catch (e) {
          if (_shouldQueueVerificationFailure(e)) {
            await _queuePendingVerification(purchaseDetails);
          }
          _lastError = e.toString().replaceFirst('Bad state: ', '');
        } finally {
          _purchaseInProgress = false;
          notifyListeners();
        }
      }

      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
      }
    }
  }

  Future<void> _verifyWithBackendIfAvailable(
    PurchaseDetails purchaseDetails,
  ) async {
    final entitlementService = _entitlementService;
    if (entitlementService == null) return;
    if (!purchasesEnabled) return;

    final verificationData =
        purchaseDetails.verificationData.serverVerificationData;
    if (verificationData.trim().isEmpty) {
      throw StateError('Purchase verification payload is empty.');
    }

    final product = findProductById(purchaseDetails.productID);
    final billingCycle = _inferBillingCycle(
      productId: purchaseDetails.productID,
      title: product?.title,
      description: product?.description,
    );

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        final appAccountToken = purchaseDetails is SK2PurchaseDetails
            ? purchaseDetails.appAccountToken
            : null;
        await entitlementService.verifyApplePurchase(
          transactionJws: verificationData,
          productId: purchaseDetails.productID,
          appAccountToken: appAccountToken,
          price: product?.rawPrice,
          currencyCode: product?.currencyCode,
          billingCycle: billingCycle,
        );
        break;
      case TargetPlatform.android:
        final playDetails = purchaseDetails is GooglePlayPurchaseDetails
            ? purchaseDetails.billingClientPurchase
            : null;
        await entitlementService.verifyGooglePurchase(
          purchaseToken: verificationData,
          productId: purchaseDetails.productID,
          packageName: playDetails?.packageName,
          obfuscatedAccountId: playDetails?.obfuscatedAccountId,
          price: product?.rawPrice,
          currencyCode: product?.currencyCode,
          billingCycle: billingCycle,
        );
        break;
      default:
        break;
    }
  }

  String? _applicationUserName() {
    final raw = _entitlementService?.storeAccountToken?.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  String? _inferBillingCycle({
    required String productId,
    String? title,
    String? description,
  }) {
    final haystack =
        '$productId ${title ?? ''} ${description ?? ''}'.toLowerCase();
    if (haystack.contains('year')) return 'yearly';
    if (haystack.contains('annual')) return 'yearly';
    if (haystack.contains('month')) return 'monthly';
    if (haystack.contains('week')) return 'weekly';
    return null;
  }

  Future<void> _queuePendingVerification(
    PurchaseDetails purchaseDetails,
  ) async {
    final record = _buildPendingVerificationRecord(purchaseDetails);
    if (record == null) return;

    final queue = await _readPendingVerificationQueue();
    final recordId = record['id']?.toString() ?? '';
    queue.removeWhere((item) => item['id']?.toString() == recordId);
    queue.add(record);
    await _writePendingVerificationQueue(queue);
  }

  Future<void> _removePendingVerification(
    PurchaseDetails purchaseDetails,
  ) async {
    final recordId = _pendingVerificationIdForPurchase(purchaseDetails);
    if (recordId.isEmpty) return;

    final queue = await _readPendingVerificationQueue();
    final updated =
        queue.where((item) => item['id']?.toString() != recordId).toList();
    if (updated.length == queue.length) return;
    await _writePendingVerificationQueue(updated);
  }

  Future<void> _retryPendingVerifications() async {
    if (_isRetryingPendingVerifications) return;
    final entitlementService = _entitlementService;
    if (entitlementService == null || !purchasesEnabled) return;

    final userId = entitlementService.storeAccountToken?.trim() ?? '';
    if (userId.isEmpty) return;

    _isRetryingPendingVerifications = true;
    try {
      final queue = await _readPendingVerificationQueue();
      if (queue.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];
      var verifiedAny = false;

      for (final record in queue) {
        final recordUserId = (record['user_id'] ?? '').toString().trim();
        if (recordUserId.isNotEmpty && recordUserId != userId) {
          remaining.add(record);
          continue;
        }

        try {
          await _submitPendingVerification(record, entitlementService);
          verifiedAny = true;
        } catch (e) {
          if (_shouldQueueVerificationFailure(e)) {
            remaining.add(record);
          }
        }
      }

      await _writePendingVerificationQueue(remaining);
      if (verifiedAny) {
        await entitlementService.refresh(force: true);
      }
    } finally {
      _isRetryingPendingVerifications = false;
    }
  }

  Future<void> _submitPendingVerification(
    Map<String, dynamic> record,
    EntitlementService entitlementService,
  ) async {
    final provider = (record['provider'] ?? '').toString().trim();
    if (provider == 'apple') {
      final transactionJws =
          (record['transaction_jws'] ?? '').toString().trim();
      if (transactionJws.isEmpty) {
        throw StateError(
            'Queued Apple verification is missing transaction JWS.');
      }
      await entitlementService.verifyApplePurchase(
        transactionJws: transactionJws,
        productId: (record['product_id'] ?? '').toString().trim(),
        appAccountToken: (record['app_account_token'] ?? '').toString().trim(),
      );
      return;
    }

    if (provider == 'google') {
      final purchaseToken = (record['purchase_token'] ?? '').toString().trim();
      final productId = (record['product_id'] ?? '').toString().trim();
      if (purchaseToken.isEmpty || productId.isEmpty) {
        throw StateError(
            'Queued Google verification is missing purchase data.');
      }
      await entitlementService.verifyGooglePurchase(
        purchaseToken: purchaseToken,
        productId: productId,
        packageName: (record['package_name'] ?? '').toString().trim(),
        obfuscatedAccountId:
            (record['obfuscated_account_id'] ?? '').toString().trim(),
      );
      return;
    }

    throw StateError('Unsupported queued billing provider: $provider');
  }

  Map<String, dynamic>? _buildPendingVerificationRecord(
    PurchaseDetails purchaseDetails,
  ) {
    final verificationData =
        purchaseDetails.verificationData.serverVerificationData.trim();
    if (verificationData.isEmpty) return null;

    final userId = _entitlementService?.storeAccountToken?.trim() ?? '';
    if (userId.isEmpty) return null;

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        final appAccountToken = purchaseDetails is SK2PurchaseDetails
            ? purchaseDetails.appAccountToken
            : null;
        return <String, dynamic>{
          'id': _pendingVerificationIdForPurchase(purchaseDetails),
          'provider': 'apple',
          'user_id': userId,
          'product_id': purchaseDetails.productID,
          'transaction_jws': verificationData,
          if ((appAccountToken ?? '').trim().isNotEmpty)
            'app_account_token': appAccountToken,
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        };
      case TargetPlatform.android:
        final playDetails = purchaseDetails is GooglePlayPurchaseDetails
            ? purchaseDetails.billingClientPurchase
            : null;
        return <String, dynamic>{
          'id': _pendingVerificationIdForPurchase(purchaseDetails),
          'provider': 'google',
          'user_id': userId,
          'product_id': purchaseDetails.productID,
          'purchase_token': verificationData,
          if ((playDetails?.packageName ?? '').trim().isNotEmpty)
            'package_name': playDetails?.packageName,
          if ((playDetails?.obfuscatedAccountId ?? '').trim().isNotEmpty)
            'obfuscated_account_id': playDetails?.obfuscatedAccountId,
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        };
      default:
        return null;
    }
  }

  String _pendingVerificationIdForPurchase(PurchaseDetails purchaseDetails) {
    final verificationData =
        purchaseDetails.verificationData.serverVerificationData.trim();
    if (verificationData.isEmpty) return '';

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'apple:$verificationData';
      case TargetPlatform.android:
        return 'google:$verificationData';
      default:
        return '';
    }
  }

  bool _shouldQueueVerificationFailure(Object error) {
    final message = error.toString().toLowerCase();
    final statusMatch = RegExp(r'failed \((\d{3})\)').firstMatch(message);
    if (statusMatch != null) {
      final statusCode = int.tryParse(statusMatch.group(1) ?? '');
      if (statusCode != null &&
          statusCode >= 400 &&
          statusCode < 500 &&
          statusCode != 408 &&
          statusCode != 429) {
        return false;
      }
    }

    if (message.contains('different mixroom account') ||
        message.contains('already linked to another mixroom account') ||
        message.contains('missing purchase data') ||
        message.contains('unsupported queued billing provider')) {
      return false;
    }

    return true;
  }

  Future<List<Map<String, dynamic>>> _readPendingVerificationQueue() async {
    final raw = await SensitiveStorage.instance.readWithMigration(
      _pendingVerificationPrefsKey,
    );
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => item.map(
                (key, value) => MapEntry(key.toString(), value),
              ))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _writePendingVerificationQueue(
    List<Map<String, dynamic>> queue,
  ) async {
    if (queue.isEmpty) {
      await SensitiveStorage.instance.delete(_pendingVerificationPrefsKey);
      return;
    }
    await SensitiveStorage.instance.write(
      _pendingVerificationPrefsKey,
      jsonEncode(queue),
    );
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    super.dispose();
  }
}
