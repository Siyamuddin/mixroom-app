import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:mixroom/config/iap_config.dart';
import 'package:mixroom/core/analytics/analytics_events.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/core/security/sensitive_storage.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/models/entitlement_models.dart';

class IapService extends ChangeNotifier {
  static const String _pendingVerificationPrefsKey =
      'mixroom.iap.pending_verifications.v1';

  IapService({
    InAppPurchase? inAppPurchase,
  }) : _iap = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  EntitlementService? _entitlementService;
  VoidCallback? _entitlementListener;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  bool _initializing = false;
  bool _initialized = false;
  bool _storeAvailable = false;
  bool _purchaseInProgress = false;
  bool _storeSheetOpening = false;
  bool _awaitingUserInitiatedPurchaseUpdate = false;
  bool _isRetryingPendingVerifications = false;
  bool _isRetryingDeferredAuthPurchaseUpdates = false;
  Timer? _purchaseLaunchWatchdog;
  bool _activePurchaseMayBeDeferred = false;
  List<ProductDetails> _products = const <ProductDetails>[];
  final Set<String> _verifiedPurchaseIdsThisSession = <String>{};
  final Map<String, PurchaseDetails> _purchaseUpdatesDeferredUntilAuth =
      <String, PurchaseDetails>{};
  String? _storeLinkConflictAccountToken;
  bool _restoreInProgress = false;
  String? _lastError;
  String? _lastMessage;
  DateTime? _lastSyncedAtUtc;
  DateTime? _lastCompletedPurchaseAtUtc;
  String? _lastCompletedPurchaseProductId;
  bool _lastCompletedPurchaseMayBeDeferred = false;

  bool get isInitializing => _initializing;
  bool get isInitialized => _initialized;
  bool get isStoreAvailable => _storeAvailable;
  bool get isPurchaseInProgress => _purchaseInProgress;
  bool get isStoreSheetOpening => _storeSheetOpening;
  List<ProductDetails> get products => _products;
  String? get lastError => _lastError;
  String? get lastMessage => _lastMessage;
  DateTime? get lastSyncedAtUtc => _lastSyncedAtUtc;
  DateTime? get lastCompletedPurchaseAtUtc => _lastCompletedPurchaseAtUtc;
  String? get lastCompletedPurchaseProductId => _lastCompletedPurchaseProductId;
  bool get lastCompletedPurchaseMayBeDeferred =>
      _lastCompletedPurchaseMayBeDeferred;

  bool get isMobilePlatformSupported => IapConfig.isMobileTarget;
  bool get purchasesEnabled =>
      _entitlementService?.areIapPurchasesEnabled ?? IapConfig.purchasesEnabled;

  @visibleForTesting
  Duration? get purchaseLaunchWatchdogDuration => const Duration(seconds: 6);

  void bindEntitlementService(EntitlementService entitlementService) {
    if (!identical(_entitlementService, entitlementService)) {
      final listener = _entitlementListener;
      if (listener != null) {
        _entitlementService?.removeListener(listener);
      }
      _entitlementListener = _handleEntitlementServiceChanged;
      entitlementService.addListener(_entitlementListener!);
      _entitlementService = entitlementService;
    }
    if (_initialized && !_initializing) {
      unawaited(_retryPendingVerifications());
      unawaited(_retryDeferredAuthPurchaseUpdates());
    }
  }

  void _handleEntitlementServiceChanged() {
    final accountToken = _applicationUserName();
    if (accountToken == null) return;
    if (_storeLinkConflictAccountToken != null &&
        _storeLinkConflictAccountToken != accountToken) {
      _storeLinkConflictAccountToken = null;
    }
    unawaited(_retryPendingVerifications());
    unawaited(_retryDeferredAuthPurchaseUpdates());
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

      _purchaseSubscription ??= _iap.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: _handlePurchaseStreamError,
      );

      _storeAvailable = await _iap.isAvailable();
      if (_storeAvailable) {
        await refreshProducts();
      } else {
        _products = const <ProductDetails>[];
      }
      _initialized = true;
      unawaited(_retryPendingVerifications());
    } catch (e) {
      _lastError = _cleanPurchaseError(e);
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
      _lastError = response.error == null
          ? null
          : _cleanPurchaseError(response.error!.message);
      _lastSyncedAtUtc = DateTime.now().toUtc();
      notifyListeners();
    } catch (e) {
      _lastError = _cleanPurchaseError(e);
      notifyListeners();
    }
  }

  ProductDetails? findProductById(String productId) {
    for (final product in _products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  Future<void> buyProduct(
    ProductDetails product, {
    bool requiresAndroidSubscriptionChange = false,
    bool storePlanChangeMayBeDeferred = false,
  }) async {
    if (!isMobilePlatformSupported) {
      _lastError = 'In-app purchases are only supported on iOS/Android.';
      _lastMessage = null;
      notifyListeners();
      return;
    }

    if (!_storeAvailable) {
      _lastError = 'Store is not available on this device right now.';
      _lastMessage = null;
      notifyListeners();
      return;
    }

    if (!purchasesEnabled) {
      _lastError = 'Purchases are disabled in this build (placeholder mode).';
      _lastMessage = null;
      notifyListeners();
      return;
    }

    try {
      final applicationUserName = _applicationUserName();
      if (applicationUserName == null) {
        throw StateError('Sign in is required before starting a purchase.');
      }
      if (_hasConflictingActiveSubscriptionForCheckout()) {
        _lastError = _activeSubscriptionConflictMessage;
        _lastMessage = null;
        notifyListeners();
        return;
      }
      if (_storeLinkConflictAccountToken == applicationUserName) {
        _lastError = _crossAccountStoreLinkMessage;
        _lastMessage = null;
        notifyListeners();
        return;
      }
      _activePurchaseMayBeDeferred = storePlanChangeMayBeDeferred;
      _purchaseLaunchWatchdog?.cancel();
      _purchaseInProgress = true;
      _storeSheetOpening = true;
      _awaitingUserInitiatedPurchaseUpdate = false;
      _lastError = null;
      _lastMessage = 'Opening secure checkout...';
      notifyListeners();

      final purchaseParam = await _purchaseParamForProduct(
        product,
        applicationUserName: applicationUserName,
        requiresAndroidSubscriptionChange: requiresAndroidSubscriptionChange,
      );
      final launched =
          await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      _storeSheetOpening = false;
      if (!launched) {
        _purchaseInProgress = false;
        _awaitingUserInitiatedPurchaseUpdate = false;
        _lastError = 'Purchase could not be started.';
        _lastMessage = null;
        notifyListeners();
        return;
      }
      _awaitingUserInitiatedPurchaseUpdate = true;
      _lastMessage = 'Complete the purchase in the store sheet.';
      notifyListeners();
      _purchaseInProgress = false;
      notifyListeners();
    } catch (e) {
      _purchaseLaunchWatchdog?.cancel();
      _purchaseInProgress = false;
      _storeSheetOpening = false;
      _awaitingUserInitiatedPurchaseUpdate = false;
      _lastError = _cleanPurchaseError(e);
      _lastMessage = null;
      unawaited(
        AnalyticsService.instance.track(
          AnalyticsEvents.purchaseFailed(errorCode: _lastError ?? 'unknown'),
        ),
      );
      notifyListeners();
    }
  }

  Future<PurchaseParam> _purchaseParamForProduct(
    ProductDetails product, {
    required String applicationUserName,
    required bool requiresAndroidSubscriptionChange,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return PurchaseParam(
        productDetails: product,
        applicationUserName: applicationUserName,
      );
    }

    final changeSubscriptionParam =
        await _googleChangeSubscriptionParamForProduct(
      product,
      applicationUserName: applicationUserName,
      required: requiresAndroidSubscriptionChange,
    );
    return GooglePlayPurchaseParam(
      productDetails: product,
      applicationUserName: applicationUserName,
      changeSubscriptionParam: changeSubscriptionParam,
    );
  }

  Future<ChangeSubscriptionParam?> _googleChangeSubscriptionParamForProduct(
    ProductDetails product, {
    required String applicationUserName,
    required bool required,
  }) async {
    if (!_isMixroomSubscriptionProduct(product.id)) {
      return null;
    }
    final pastPurchases = await queryPastGooglePurchasesForSubscriptionChange(
        applicationUserName);
    if (pastPurchases.error != null) {
      if (required) {
        throw StateError(
          'Could not confirm your current Google Play subscription. Open Manage plan to change subscriptions safely.',
        );
      }
      return null;
    }

    GooglePlayPurchaseDetails? oldPurchase;
    for (final purchase in pastPurchases.pastPurchases) {
      if (purchase.productID == product.id) {
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      if (!_isMixroomSubscriptionProduct(purchase.productID)) {
        continue;
      }
      final purchaseAccountId =
          purchase.billingClientPurchase.obfuscatedAccountId;
      if (purchaseAccountId != null &&
          purchaseAccountId.isNotEmpty &&
          purchaseAccountId != applicationUserName) {
        continue;
      }
      if (oldPurchase == null ||
          _subscriptionProductRank(purchase.productID) >
              _subscriptionProductRank(oldPurchase.productID)) {
        oldPurchase = purchase;
      }
    }
    if (oldPurchase == null) {
      if (required) {
        throw StateError(
          'Could not find your current Google Play subscription. Open Manage plan to change subscriptions safely.',
        );
      }
      return null;
    }

    final newRank = _subscriptionProductRank(product.id);
    final oldRank = _subscriptionProductRank(oldPurchase.productID);
    return ChangeSubscriptionParam(
      oldPurchaseDetails: oldPurchase,
      replacementMode: newRank > oldRank
          ? ReplacementMode.chargeProratedPrice
          : ReplacementMode.deferred,
    );
  }

  @visibleForTesting
  Future<QueryPurchaseDetailsResponse>
      queryPastGooglePurchasesForSubscriptionChange(
    String applicationUserName,
  ) {
    final addition =
        _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    return addition.queryPastPurchases(
      applicationUserName: applicationUserName,
    );
  }

  Future<void> restorePurchases() async {
    if (!isMobilePlatformSupported) {
      _lastError = 'Restore is only supported on iOS/Android.';
      _lastMessage = null;
      notifyListeners();
      return;
    }
    if (!_storeAvailable) {
      _lastError = 'Store is not available on this device right now.';
      _lastMessage = null;
      notifyListeners();
      return;
    }
    try {
      final applicationUserName = _applicationUserName();
      if (applicationUserName == null) {
        throw StateError('Sign in is required before restoring purchases.');
      }
      _lastError = null;
      _lastMessage = 'Checking purchases...';
      _restoreInProgress = true;
      notifyListeners();
      final restoredCount =
          await _verifyRestorablePurchases(applicationUserName);
      await _iap.restorePurchases(
        applicationUserName: applicationUserName,
      );
      _lastError = null;
      _lastMessage = restoredCount > 0
          ? 'Purchase restored.'
          : 'No active purchase found.';
      notifyListeners();
    } catch (e) {
      _lastError = _cleanPurchaseError(e);
      _lastMessage = null;
      notifyListeners();
    } finally {
      _restoreInProgress = false;
    }
  }

  Future<int> _verifyRestorablePurchases(String applicationUserName) async {
    final purchases = await queryRestorablePurchases(applicationUserName);
    var restoredCount = 0;

    for (final purchase in purchases) {
      if (!_isRestorablePurchase(purchase)) {
        continue;
      }
      if (_hasMismatchedGoogleAccountId(purchase, applicationUserName)) {
        _markCrossAccountStoreLinkConflict();
        throw StateError(_crossAccountStoreLinkMessage);
      }

      await _verifyWithBackendIfAvailable(purchase);
      final verificationId = _verificationIdForPurchase(purchase);
      if (verificationId.isNotEmpty) {
        _verifiedPurchaseIdsThisSession.add(verificationId);
      }
      await _removePendingVerification(purchase);
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      restoredCount += 1;
    }

    if (restoredCount > 0) {
      await _entitlementService?.refresh(force: true);
    }
    return restoredCount;
  }

  @visibleForTesting
  Future<List<PurchaseDetails>> queryRestorablePurchases(
    String applicationUserName,
  ) async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        final transactions = await SK2Transaction.transactions();
        return transactions
            .where(_isActiveMixroomStoreKitTransaction)
            .map(_purchaseDetailsForStoreKitTransaction)
            .toList();
      case TargetPlatform.android:
        final response = await queryPastGooglePurchasesForSubscriptionChange(
          applicationUserName,
        );
        if (response.error != null) {
          throw StateError(
            response.error!.message.isNotEmpty
                ? response.error!.message
                : 'Could not query Google Play purchases.',
          );
        }
        return List<PurchaseDetails>.from(response.pastPurchases);
      default:
        return const <PurchaseDetails>[];
    }
  }

  bool _isActiveMixroomStoreKitTransaction(SK2Transaction transaction) {
    if (!_isMixroomSubscriptionProduct(transaction.productId)) {
      return false;
    }
    if ((transaction.receiptData ?? '').trim().isEmpty) {
      return false;
    }
    final expiration = _parseStoreDate(transaction.expirationDate);
    return expiration == null || expiration.isAfter(DateTime.now().toUtc());
  }

  PurchaseDetails _purchaseDetailsForStoreKitTransaction(
    SK2Transaction transaction,
  ) {
    return SK2PurchaseDetails(
      productID: transaction.productId,
      purchaseID: transaction.id,
      transactionDate: transaction.purchaseDate,
      status: PurchaseStatus.restored,
      verificationData: PurchaseVerificationData(
        localVerificationData: transaction.jsonRepresentation ?? '',
        serverVerificationData: transaction.receiptData ?? '',
        source: 'app_store',
      ),
      appAccountToken: transaction.appAccountToken,
    );
  }

  bool _isRestorablePurchase(PurchaseDetails purchase) {
    if (!_isMixroomSubscriptionProduct(purchase.productID)) {
      return false;
    }
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return false;
    }
    return purchase.verificationData.serverVerificationData.trim().isNotEmpty;
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _purchaseLaunchWatchdog?.cancel();
        _purchaseInProgress = true;
        _storeSheetOpening = false;
        _lastError = null;
        _lastMessage = 'Purchase pending.';
        notifyListeners();
        continue;
      }

      if (purchaseDetails.status == PurchaseStatus.error) {
        _purchaseLaunchWatchdog?.cancel();
        _purchaseInProgress = false;
        _storeSheetOpening = false;
        _awaitingUserInitiatedPurchaseUpdate = false;
        _lastError = _cleanPurchaseError(
          purchaseDetails.error?.message ?? 'Purchase failed.',
        );
        _lastMessage = null;
        unawaited(
          AnalyticsService.instance.track(
            AnalyticsEvents.purchaseFailed(errorCode: _lastError ?? 'unknown'),
          ),
        );
        notifyListeners();
      }

      if (purchaseDetails.status == PurchaseStatus.canceled) {
        _purchaseLaunchWatchdog?.cancel();
        _purchaseInProgress = false;
        _storeSheetOpening = false;
        _awaitingUserInitiatedPurchaseUpdate = false;
        _lastError = null;
        _lastMessage = 'Purchase canceled. Your plan was not changed.';
        notifyListeners();
      }

      if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        _purchaseLaunchWatchdog?.cancel();
        final userInitiatedPurchase =
            _purchaseInProgress || _awaitingUserInitiatedPurchaseUpdate;
        _storeSheetOpening = false;
        final verificationId = _verificationIdForPurchase(purchaseDetails);
        if (!userInitiatedPurchase &&
            !_restoreInProgress &&
            verificationId.isNotEmpty &&
            _verifiedPurchaseIdsThisSession.contains(verificationId)) {
          if (purchaseDetails.pendingCompletePurchase) {
            await _iap.completePurchase(purchaseDetails);
          }
          continue;
        }
        if (!userInitiatedPurchase &&
            !_restoreInProgress &&
            _applicationUserName() == null) {
          _deferPurchaseUpdateUntilAuth(purchaseDetails);
          _purchaseInProgress = false;
          _awaitingUserInitiatedPurchaseUpdate = false;
          _lastError = null;
          _lastMessage = null;
          notifyListeners();
          if (purchaseDetails.pendingCompletePurchase) {
            await _iap.completePurchase(purchaseDetails);
          }
          continue;
        }
        _lastError = null;
        _lastMessage = 'Syncing purchase...';
        notifyListeners();
        try {
          await _verifyWithBackendIfAvailable(purchaseDetails);
          _storeLinkConflictAccountToken = null;
          if (verificationId.isNotEmpty) {
            _verifiedPurchaseIdsThisSession.add(verificationId);
          }
          await _removePendingVerification(purchaseDetails);
          await _entitlementService?.refresh(force: true);
          _lastError = null;
          _lastMessage = _activePurchaseMayBeDeferred
              ? 'Plan change synced. Downgrades and billing-cycle changes may take effect at renewal.'
              : 'Purchase synced.';
          if (userInitiatedPurchase) {
            _lastCompletedPurchaseAtUtc = DateTime.now().toUtc();
            _lastCompletedPurchaseProductId = purchaseDetails.productID;
            _lastCompletedPurchaseMayBeDeferred = _activePurchaseMayBeDeferred;
          }
        } catch (e) {
          if (_isEmptyVerificationPayloadError(e)) {
            await _entitlementService?.refresh(force: true);
            _lastError = null;
            _lastMessage = null;
          } else if (_shouldQueueVerificationFailure(e)) {
            await _queuePendingVerification(purchaseDetails);
            _lastError = userInitiatedPurchase ? _cleanPurchaseError(e) : null;
            _lastMessage = null;
          } else if (!userInitiatedPurchase &&
              !_restoreInProgress &&
              _isCrossAccountStoreLinkError(e)) {
            _markCrossAccountStoreLinkConflict();
            await _entitlementService?.refresh(force: true);
            _lastError = _hasActiveCurrentPlatformStoreEntitlement()
                ? null
                : _cleanPurchaseError(e);
            _lastMessage = null;
          } else if (!userInitiatedPurchase &&
              _isTransientVerificationFailure(e)) {
            await _queuePendingVerification(purchaseDetails);
            _lastError = null;
            _lastMessage = null;
          } else {
            if (_isCrossAccountStoreLinkError(e)) {
              _markCrossAccountStoreLinkConflict();
            }
            _lastError = _cleanPurchaseError(e);
            _lastMessage = null;
          }
        } finally {
          _purchaseInProgress = false;
          _storeSheetOpening = false;
          _awaitingUserInitiatedPurchaseUpdate = false;
          notifyListeners();
        }
      }

      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
      }
    }
  }

  void _handlePurchaseStreamError(Object error, StackTrace stackTrace) {
    final wasUserVisible =
        _purchaseInProgress || _storeSheetOpening || _restoreInProgress;
    _purchaseLaunchWatchdog?.cancel();
    _purchaseInProgress = false;
    _storeSheetOpening = false;

    if (wasUserVisible) {
      _lastError = _cleanPurchaseError(error);
      _lastMessage = null;
      notifyListeners();
    }

    debugPrint('IAP purchase stream error: ${_cleanPurchaseError(error)}');
  }

  void _deferPurchaseUpdateUntilAuth(PurchaseDetails purchaseDetails) {
    final verificationId = _verificationIdForPurchase(purchaseDetails);
    if (verificationId.isEmpty) return;
    _purchaseUpdatesDeferredUntilAuth[verificationId] = purchaseDetails;
  }

  Future<void> _retryDeferredAuthPurchaseUpdates() async {
    if (_isRetryingDeferredAuthPurchaseUpdates ||
        _purchaseUpdatesDeferredUntilAuth.isEmpty ||
        _applicationUserName() == null) {
      return;
    }

    _isRetryingDeferredAuthPurchaseUpdates = true;
    try {
      final pending =
          List<PurchaseDetails>.from(_purchaseUpdatesDeferredUntilAuth.values);
      for (final purchaseDetails in pending) {
        final verificationId = _verificationIdForPurchase(purchaseDetails);
        if (verificationId.isEmpty ||
            !_purchaseUpdatesDeferredUntilAuth.containsKey(verificationId)) {
          continue;
        }
        try {
          await _verifyWithBackendIfAvailable(purchaseDetails);
          _verifiedPurchaseIdsThisSession.add(verificationId);
          _purchaseUpdatesDeferredUntilAuth.remove(verificationId);
          await _removePendingVerification(purchaseDetails);
          await _entitlementService?.refresh(force: true);
        } catch (e) {
          if (_isEmptyVerificationPayloadError(e) ||
              _isCrossAccountStoreLinkError(e) ||
              !_shouldQueueVerificationFailure(e)) {
            _purchaseUpdatesDeferredUntilAuth.remove(verificationId);
          } else {
            await _queuePendingVerification(purchaseDetails);
            _purchaseUpdatesDeferredUntilAuth.remove(verificationId);
          }
        }
      }
    } finally {
      _isRetryingDeferredAuthPurchaseUpdates = false;
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
        final appAccountToken = _applicationUserName();
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

  bool _isMixroomSubscriptionProduct(String productId) {
    final normalized = productId.trim().toLowerCase();
    return normalized == 'mixroom_starter_monthly' ||
        normalized == 'mixroom_starter_yearly' ||
        normalized == 'mixroom_producer_monthly' ||
        normalized == 'mixroom_producer_yearly';
  }

  int _subscriptionProductRank(String productId) {
    final normalized = productId.trim().toLowerCase();
    if (normalized.contains('producer')) return 20;
    if (normalized.contains('starter')) return 10;
    return 0;
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
    final recordId = _verificationIdForPurchase(purchaseDetails);
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
        final storeAccountToken = purchaseDetails is SK2PurchaseDetails
            ? purchaseDetails.appAccountToken
            : null;
        final appAccountToken = (storeAccountToken ?? '').trim().isNotEmpty
            ? storeAccountToken
            : userId;
        return <String, dynamic>{
          'id': _verificationIdForPurchase(purchaseDetails),
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
          'id': _verificationIdForPurchase(purchaseDetails),
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

  String _verificationIdForPurchase(PurchaseDetails purchaseDetails) {
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

  bool _isCrossAccountStoreLinkError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('different mixroom account') ||
        message.contains('already linked to another mixroom account');
  }

  bool _hasActiveCurrentPlatformStoreEntitlement() {
    final entitlement = _entitlementService?.entitlement;
    if (entitlement == null ||
        !entitlement.isAccessActive ||
        !entitlement.isPaidPlan) {
      return false;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return entitlement.sourceProvider == BillingProvider.apple;
      case TargetPlatform.android:
        return entitlement.sourceProvider == BillingProvider.google;
      default:
        return false;
    }
  }

  bool _hasConflictingActiveSubscriptionForCheckout() {
    final entitlement = _entitlementService?.entitlement;
    if (entitlement == null ||
        !entitlement.isAccessActive ||
        !entitlement.isPaidPlan) {
      return false;
    }
    final currentProvider = _currentStoreProvider();
    if (currentProvider == null) return false;
    return entitlement.sourceProvider != currentProvider;
  }

  BillingProvider? _currentStoreProvider() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return BillingProvider.apple;
      case TargetPlatform.android:
        return BillingProvider.google;
      default:
        return null;
    }
  }

  bool _hasMismatchedGoogleAccountId(
    PurchaseDetails purchaseDetails,
    String applicationUserName,
  ) {
    if (defaultTargetPlatform != TargetPlatform.android ||
        purchaseDetails is! GooglePlayPurchaseDetails) {
      return false;
    }
    final purchaseAccountId =
        (purchaseDetails.billingClientPurchase.obfuscatedAccountId ?? '')
            .trim();
    return purchaseAccountId.isNotEmpty &&
        applicationUserName.trim().isNotEmpty &&
        purchaseAccountId != applicationUserName.trim();
  }

  bool _isTransientVerificationFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('failed (401)') ||
        message.contains('failed (500)') ||
        message.contains('internal server error') ||
        message.contains('no authenticated user');
  }

  bool _isEmptyVerificationPayloadError(Object error) {
    return error
        .toString()
        .toLowerCase()
        .contains('purchase verification payload is empty');
  }

  void _markCrossAccountStoreLinkConflict() {
    _storeLinkConflictAccountToken = _applicationUserName();
  }

  static const String _crossAccountStoreLinkMessage =
      'This App Store or Google Play subscription is already linked to another Mixroom account. Sign in to that account, or manage the subscription in the store before subscribing here.';

  static const String _activeSubscriptionConflictMessage =
      'You already have an active subscription. Manage or cancel it before subscribing again.';

  String _cleanPurchaseError(Object error) {
    var raw = error.toString().trim();
    if (error is PlatformException) {
      raw = <String>[
        error.code,
        if ((error.message ?? '').trim().isNotEmpty) error.message!,
        if ((error.details ?? '').toString().trim().isNotEmpty)
          error.details.toString(),
      ].join(' ');
    }
    raw = raw
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
    final normalized = raw.toLowerCase();
    if (normalized.contains('different mixroom account') ||
        normalized.contains('already linked to another mixroom account')) {
      return _crossAccountStoreLinkMessage;
    }
    if (_looksLikeStoreTechnicalError(normalized)) {
      if (_looksLikeAppleStoreError(normalized)) {
        return 'The App Store could not complete that request. Please try again.';
      }
      if (_looksLikeGooglePlayError(normalized)) {
        return 'Google Play could not complete that request. Please try again.';
      }
      return 'The store could not complete that request. Please try again.';
    }
    if (raw.isEmpty) {
      return 'Something went wrong. Please try again.';
    }
    return raw;
  }

  bool _looksLikeStoreTechnicalError(String normalized) {
    return normalized.contains('platformexception') ||
        normalized.contains('storekiterror') ||
        normalized.contains('pigeonerror') ||
        normalized.contains('stacktrace') ||
        normalized.contains('runner.debug.dylib') ||
        normalized.contains('in_app_purchase') ||
        normalized.contains('billingclient') ||
        normalized.contains('billingresponse') ||
        normalized.contains('fluttererror');
  }

  bool _looksLikeAppleStoreError(String normalized) {
    return normalized.contains('storekit') ||
        normalized.contains('app store') ||
        normalized.contains('runner.debug.dylib') ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool _looksLikeGooglePlayError(String normalized) {
    return normalized.contains('google') ||
        normalized.contains('play') ||
        normalized.contains('billingclient') ||
        normalized.contains('billingresponse') ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  DateTime? _parseStoreDate(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(raw)) {
      final number = int.tryParse(raw);
      if (number == null) return null;
      final millis = number > 9999999999 ? number : number * 1000;
      return DateTime.fromMillisecondsSinceEpoch(
        millis,
        isUtc: true,
      );
    }
    return DateTime.tryParse(raw)?.toUtc();
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
    _purchaseLaunchWatchdog?.cancel();
    _purchaseSubscription?.cancel();
    final listener = _entitlementListener;
    if (listener != null) {
      _entitlementService?.removeListener(listener);
    }
    _purchaseSubscription = null;
    _entitlementListener = null;
    super.dispose();
  }
}
