import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/config/subscription_config.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/models/subscription_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionService extends ChangeNotifier {
  SubscriptionService({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const String _prefsKeyPrefix = 'mixroom.subscription.entitlement.v1';

  final http.Client _httpClient;

  AuthService? _auth;
  VoidCallback? _authListener;

  EntitlementSnapshot? _entitlement;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _lastError;
  DateTime? _lastSyncedAtUtc;
  String? _boundUserId;

  EntitlementSnapshot? get entitlement => _entitlement;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get lastError => _lastError;
  DateTime? get lastSyncedAtUtc => _lastSyncedAtUtc;

  bool get isEnforcementEnabled => SubscriptionConfig.enforceSubscriptions;

  bool get isShadowModeEnabled => SubscriptionConfig.subscriptionShadowMode;

  PlanTier get currentTier => _entitlement?.tier ?? PlanTier.free;

  bool get isProEntitled =>
      currentTier == PlanTier.pro || currentTier == PlanTier.studio;

  bool canUseCapability(String capability) {
    if (!isEnforcementEnabled) return true;
    if (isShadowModeEnabled) return true;
    final current = _entitlement;
    if (current == null) return false;
    return current.hasCapability(capability);
  }

  void bindAuth(AuthService auth) {
    if (identical(_auth, auth)) return;
    _detachAuthListener();
    _auth = auth;
    _authListener = _handleAuthStateChanged;
    auth.addListener(_authListener!);
    _handleAuthStateChanged();
  }

  Future<void> refresh({
    bool force = false,
  }) async {
    final auth = _auth;
    final user = auth?.currentUser;
    if (auth == null || user == null) return;
    if (_isLoading) return;
    if (!force && !_isEntitlementStale) return;

    _isLoading = true;
    notifyListeners();

    try {
      if (!SubscriptionConfig.hasApiBaseUrl) {
        _setFallbackFreeEntitlement(user.userId);
        _lastError = 'Subscription API base URL is not configured.';
        return;
      }

      final token = await auth.getIdTokenOrNull();
      if (token == null || token.trim().isEmpty) {
        _setFallbackFreeEntitlement(user.userId);
        _lastError = 'Session token unavailable.';
        return;
      }

      final response = await _httpClient
          .get(
            _buildUri('/v1/entitlements/me'),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(Duration(seconds: SubscriptionConfig.requestTimeoutSeconds));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
            'Entitlement request failed (${response.statusCode}).');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Entitlement response shape is invalid.');
      }
      final json = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );

      _entitlement = EntitlementSnapshot.fromJson(
        json,
        fallbackUserId: user.userId,
      );
      _lastSyncedAtUtc = DateTime.now().toUtc();
      _lastError = null;
      _isInitialized = true;
      await _writeCachedEntitlement(user.userId, _entitlement!);
    } catch (e) {
      _lastError = e.toString().replaceFirst('Bad state: ', '');
      _isInitialized = true;
      if (_entitlement == null) {
        _setFallbackFreeEntitlement(user.userId);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createWebCheckoutSession({
    required String regionCode,
    String? successUrl,
    String? cancelUrl,
  }) async {
    final body = <String, dynamic>{
      'region_code': regionCode,
      if ((successUrl ?? '').trim().isNotEmpty) 'success_url': successUrl,
      if ((cancelUrl ?? '').trim().isNotEmpty) 'cancel_url': cancelUrl,
    };
    return _postAuthed('/v1/billing/web/checkout-session', body: body);
  }

  Future<Map<String, dynamic>> verifyApplePurchase({
    required String transactionJws,
  }) async {
    final result = await _postAuthed(
      '/v1/billing/mobile/apple/verify',
      body: <String, dynamic>{
        'transaction_jws': transactionJws,
      },
    );
    await refresh(force: true);
    return result;
  }

  Future<Map<String, dynamic>> verifyGooglePurchase({
    required String purchaseToken,
    required String productId,
    String? packageName,
  }) async {
    final result = await _postAuthed(
      '/v1/billing/mobile/google/verify',
      body: <String, dynamic>{
        'purchase_token': purchaseToken,
        'product_id': productId,
        if ((packageName ?? '').trim().isNotEmpty) 'package_name': packageName,
      },
    );
    await refresh(force: true);
    return result;
  }

  Future<void> restorePurchases({
    required BillingProvider provider,
  }) async {
    await _postAuthed(
      '/v1/billing/restore',
      body: <String, dynamic>{
        'provider': provider.value,
      },
    );
    await refresh(force: true);
  }

  Future<String?> fetchPortalUrl() async {
    final json = await _getAuthed('/v1/billing/portal-url');
    final raw = (json['url'] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  @override
  void dispose() {
    _detachAuthListener();
    _httpClient.close();
    super.dispose();
  }

  bool get _isEntitlementStale {
    final synced = _lastSyncedAtUtc;
    if (synced == null) return true;
    final ttl = Duration(minutes: SubscriptionConfig.entitlementCacheTtlMinutes);
    return DateTime.now().toUtc().difference(synced) > ttl;
  }

  Future<Map<String, dynamic>> _getAuthed(String path) async {
    final auth = _auth;
    final user = auth?.currentUser;
    if (auth == null || user == null) {
      throw StateError('No authenticated user.');
    }
    final token = await auth.getIdTokenOrNull();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Session token unavailable.');
    }
    if (!SubscriptionConfig.hasApiBaseUrl) {
      throw StateError('Subscription API base URL is not configured.');
    }

    final response = await _httpClient
        .get(
          _buildUri(path),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(Duration(seconds: SubscriptionConfig.requestTimeoutSeconds));
    return _decodeResponse(path: path, response: response);
  }

  Future<Map<String, dynamic>> _postAuthed(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final auth = _auth;
    final user = auth?.currentUser;
    if (auth == null || user == null) {
      throw StateError('No authenticated user.');
    }
    final token = await auth.getIdTokenOrNull();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Session token unavailable.');
    }
    if (!SubscriptionConfig.hasApiBaseUrl) {
      throw StateError('Subscription API base URL is not configured.');
    }

    final response = await _httpClient
        .post(
          _buildUri(path),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body ?? const <String, dynamic>{}),
        )
        .timeout(Duration(seconds: SubscriptionConfig.requestTimeoutSeconds));
    return _decodeResponse(path: path, response: response);
  }

  Map<String, dynamic> _decodeResponse({
    required String path,
    required http.Response response,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Request $path failed (${response.statusCode}): ${response.body}');
    }
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw StateError('Request $path returned invalid response payload.');
  }

  Uri _buildUri(String path) {
    final base = SubscriptionConfig.apiBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base$path');
  }

  void _handleAuthStateChanged() {
    final auth = _auth;
    final userId = auth?.currentUser?.userId;
    if (userId == null || userId.trim().isEmpty) {
      if (_boundUserId != null) {
        _boundUserId = null;
        _entitlement = null;
        _lastSyncedAtUtc = null;
        _lastError = null;
        _isInitialized = false;
        notifyListeners();
      }
      return;
    }

    if (_boundUserId == userId) {
      if ((_entitlement == null || _isEntitlementStale) && !_isLoading) {
        unawaited(refresh());
      }
      return;
    }

    _boundUserId = userId;
    _entitlement = EntitlementSnapshot.free(userId: userId);
    _lastSyncedAtUtc = null;
    _lastError = null;
    _isInitialized = true;
    notifyListeners();

    unawaited(_loadCachedEntitlement(userId).then((_) => refresh(force: true)));
  }

  Future<void> _loadCachedEntitlement(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(userId));
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final data = decoded.map((key, value) => MapEntry(key.toString(), value));
      _entitlement = EntitlementSnapshot.fromJson(
        data,
        fallbackUserId: userId,
      );
      _lastSyncedAtUtc = DateTime.now().toUtc();
      _isInitialized = true;
      notifyListeners();
    } catch (_) {
      // Ignore cache parse failures and fallback to server/default values.
    }
  }

  Future<void> _writeCachedEntitlement(
    String userId,
    EntitlementSnapshot entitlement,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey(userId),
      jsonEncode(entitlement.toJson()),
    );
  }

  String _cacheKey(String userId) => '$_prefsKeyPrefix.$userId';

  void _setFallbackFreeEntitlement(String userId) {
    _entitlement ??= EntitlementSnapshot.free(userId: userId);
    _lastSyncedAtUtc = DateTime.now().toUtc();
    _isInitialized = true;
  }

  void _detachAuthListener() {
    final auth = _auth;
    final listener = _authListener;
    if (auth != null && listener != null) {
      auth.removeListener(listener);
    }
    _authListener = null;
  }
}
