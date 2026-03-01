import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mixroom/config/iap_config.dart';
import 'package:mixroom/helpers/subscription_service.dart';

class IapService extends ChangeNotifier {
  IapService({
    InAppPurchase? inAppPurchase,
  }) : _iap = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  SubscriptionService? _subscriptionService;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  bool _initializing = false;
  bool _initialized = false;
  bool _storeAvailable = false;
  bool _purchaseInProgress = false;
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

  void bindSubscriptionService(SubscriptionService subscriptionService) {
    _subscriptionService = subscriptionService;
    if (!_initialized && !_initializing) {
      unawaited(initialize());
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
      final purchaseParam = PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      _purchaseInProgress = false;
      _lastError = e.toString().replaceFirst('Bad state: ', '');
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
      await _iap.restorePurchases();
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
        notifyListeners();
      }

      if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        try {
          await _verifyWithBackendIfAvailable(purchaseDetails);
          await _subscriptionService?.refresh(force: true);
          _lastError = null;
        } catch (e) {
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
    final subscription = _subscriptionService;
    if (subscription == null) return;
    if (!purchasesEnabled) return;

    final verificationData =
        purchaseDetails.verificationData.serverVerificationData;
    if (verificationData.trim().isEmpty) {
      throw StateError('Purchase verification payload is empty.');
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        await subscription.verifyApplePurchase(
            transactionJws: verificationData);
        break;
      case TargetPlatform.android:
        await subscription.verifyGooglePurchase(
          purchaseToken: verificationData,
          productId: purchaseDetails.productID,
        );
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    super.dispose();
  }
}
