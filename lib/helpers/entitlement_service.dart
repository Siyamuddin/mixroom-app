import 'package:mixroom/config/hackathon_config.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/models/app_feature_flags.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EducationInviteResult {
  const EducationInviteResult({
    required this.membership,
    required this.emailSent,
    required this.emailError,
  });

  final OrganizationMembershipItem? membership;
  final bool emailSent;
  final String emailError;
}

class EntitlementService extends ChangeNotifier {
  EntitlementService({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const String _prefsKeyPrefix = 'mixroom.subscription.entitlement.v1';
  static const String _catalogPrefsKeyPrefix =
      'mixroom.subscription.billing_catalog.v1';
  static const String _featureFlagsPrefsKeyPrefix = 'mixroom.feature_flags.v1';

  final http.Client _httpClient;

  AuthService? _auth;
  VoidCallback? _authListener;

  EntitlementSnapshot? _entitlement;
  BillingAccountSnapshot? _billingAccount;
  BillingCatalogSnapshot? _billingCatalog;
  AppFeatureFlags _appFeatureFlags = AppFeatureFlags.defaults();
  OrganizationAccessSnapshot? _organizationsAccess;
  WorkspaceAccessSnapshot? _workspacesAccess;
  CloudProjectAccessSnapshot? _cloudProjectsAccess;

  bool _isLoading = false;
  bool _isInitialized = false;
  bool _isAccountSurfaceLoading = false;
  bool _isAccountSurfaceInitialized = false;

  String? _lastError;
  String? _accountSurfaceError;

  DateTime? _lastSyncedAtUtc;
  DateTime? _accountSurfaceLastSyncedAtUtc;
  DateTime? _featureFlagsLastSyncedAtUtc;

  String? _boundUserId;
  Future<void>? _refreshInFlight;
  Future<void>? _accountSurfaceRefreshInFlight;

  Map<String, String> _accountSurfaceWarnings = <String, String>{};

  EntitlementSnapshot? get entitlement => _entitlement;
  BillingAccountSnapshot? get billingAccount => _billingAccount;
  BillingCatalogSnapshot? get billingCatalog =>
      _billingCatalog ??
      BillingCatalogSnapshot.localDefaults(
        requestedByUserId: _boundUserId ?? _auth?.signedInUser?.userId ?? '',
      );
  AppFeatureFlags get appFeatureFlags => _appFeatureFlags;
  OrganizationAccessSnapshot? get organizationsAccess => _organizationsAccess;
  WorkspaceAccessSnapshot? get workspacesAccess => _workspacesAccess;
  CloudProjectAccessSnapshot? get cloudProjectsAccess => _cloudProjectsAccess;

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isAccountSurfaceLoading => _isAccountSurfaceLoading;
  bool get isAccountSurfaceInitialized => _isAccountSurfaceInitialized;

  String? get lastError => _lastError;
  String? get accountSurfaceError => _accountSurfaceError;

  DateTime? get lastSyncedAtUtc => _lastSyncedAtUtc;
  DateTime? get accountSurfaceLastSyncedAtUtc => _accountSurfaceLastSyncedAtUtc;

  Map<String, String> get accountSurfaceWarnings =>
      Map<String, String>.unmodifiable(_accountSurfaceWarnings);

  bool get isEnforcementEnabled =>
      _appFeatureFlags.subscriptionEnforcementEnabled;
  bool get isAccountPlanBillingEnabled =>
      _appFeatureFlags.accountPlanBillingEnabled;
  bool get areIapPurchasesEnabled => _appFeatureFlags.iapPurchasesEnabled;
  bool get areCloudProjectsEnabled => _appFeatureFlags.cloudProjectsEnabled;

  String? get storeAccountToken {
    final raw = _auth?.signedInUser?.userId.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  String get currentPlanCode => _entitlement?.planCode ?? 'free';

  BillingSupportInfo get effectiveBillingSupport =>
      _billingCatalog?.support ??
      _entitlement?.billingSupport ??
      BillingSupportInfo.defaults();

  CollaborationAccessSummary get effectiveAccessSummary {
    final entitlementSummary = _entitlement?.workspaceAccessSummary;
    return CollaborationAccessSummary(
      organizationCount: _maxInt(
        entitlementSummary?.organizationCount ?? 0,
        _organizationsAccess?.summary.organizationCount ?? 0,
        _organizationsAccess?.organizations.length ?? 0,
      ),
      workspaceCount: _maxInt(
        entitlementSummary?.workspaceCount ?? 0,
        _workspacesAccess?.summary.workspaceCount ?? 0,
        _workspacesAccess?.workspaces.length ?? 0,
      ),
      cloudProjectCount: _maxInt(
        entitlementSummary?.cloudProjectCount ?? 0,
        _cloudProjectsAccess?.summary.cloudProjectCount ?? 0,
        _cloudProjectsAccess?.cloudProjects.length ?? 0,
      ),
    );
  }

  List<OrganizationAccessItem> get effectiveOrganizations {
    if (_organizationsAccess != null) {
      return _organizationsAccess!.organizations;
    }
    return _entitlement?.organizations ?? const <OrganizationAccessItem>[];
  }

  List<WorkspaceAccessItem> get effectiveWorkspaces =>
      _workspacesAccess?.workspaces ?? const <WorkspaceAccessItem>[];

  List<CloudProjectAccessItem> get effectiveCloudProjects =>
      _cloudProjectsAccess?.cloudProjects ?? const <CloudProjectAccessItem>[];

  List<AccountAccessSource> get effectiveAccessSources =>
      _entitlement?.accessSources ?? const <AccountAccessSource>[];

  bool canUseCapability(String capability) {
    if (!isEnforcementEnabled) return true;
    final current = _entitlement;
    if (current == null || !current.isAccessActive) return false;
    return current.hasCapability(capability);
  }

  void bindAuth(AuthService auth) {
    if (HackathonConfig.enabled) {
      _isInitialized = true;
      return;
    }
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
    final user = auth?.signedInUser;
    if (auth == null || user == null) return;
    if (_isLoading) {
      await (_refreshInFlight ?? Future<void>.value());
      return;
    }
    if (!force && !_isEntitlementStale) return;

    final refreshCompleter = Completer<void>();
    _refreshInFlight = refreshCompleter.future;
    _isLoading = true;
    notifyListeners();

    try {
      if (!AppApiConfig.hasApiBaseUrl) {
        _setFallbackFreeEntitlement(user.userId);
        _lastError = 'App API base URL is not configured.';
        return;
      }

      final response = await _sendAuthedNoExpire(
        (token) => _httpClient.get(
          _buildUri('/v1/entitlements/me'),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ).timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Entitlement request failed (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Entitlement response shape is invalid.');
      }
      final json = decoded.map((key, value) => MapEntry(key.toString(), value));

      _entitlement = EntitlementSnapshot.fromJson(
        json,
        fallbackUserId: user.userId,
      );
      AnalyticsService.instance.setSubscriptionTier(_entitlement?.planCode);
      _lastSyncedAtUtc = DateTime.now().toUtc();
      _lastError = null;
      _isInitialized = true;
      await _writeCachedEntitlement(user.userId, _entitlement!);
    } catch (e) {
      _lastError = _cleanErrorMessage(e);
      _isInitialized = true;
      if (_entitlement == null) {
        _setFallbackFreeEntitlement(user.userId);
      }
    } finally {
      _isLoading = false;
      _refreshInFlight = null;
      if (!refreshCompleter.isCompleted) {
        refreshCompleter.complete();
      }
      notifyListeners();
    }
  }

  Future<void> refreshAccountSurface({
    bool force = false,
  }) async {
    final auth = _auth;
    final user = auth?.signedInUser;
    if (auth == null || user == null) return;

    if (_isAccountSurfaceLoading) {
      await (_accountSurfaceRefreshInFlight ?? Future<void>.value());
      return;
    }
    if (!force && _isAccountSurfaceInitialized && !_isAccountSurfaceStale) {
      return;
    }

    final refreshCompleter = Completer<void>();
    _accountSurfaceRefreshInFlight = refreshCompleter.future;
    _isAccountSurfaceLoading = true;
    notifyListeners();

    try {
      if (!AppApiConfig.hasApiBaseUrl) {
        _accountSurfaceError = 'App API base URL is not configured.';
        _accountSurfaceWarnings = const <String, String>{};
        _isAccountSurfaceInitialized = true;
        return;
      }

      final catalogFuture = _fetchAccountEndpoint(
        endpointKey: 'catalog',
        path: '/v1/billing/catalog',
        parser: (json) => BillingCatalogSnapshot.fromJson(json),
      );
      final billingFuture = _fetchAccountEndpoint(
        endpointKey: 'billing',
        path: '/v1/billing/me',
        parser: (json) => BillingAccountSnapshot.fromJson(json),
      );
      final organizationsFuture = _fetchAccountEndpoint(
        endpointKey: 'organizations',
        path: '/v1/organizations/me',
        parser: (json) => OrganizationAccessSnapshot.fromJson(json),
      );
      final workspacesFuture = _fetchAccountEndpoint(
        endpointKey: 'workspaces',
        path: '/v1/workspaces/me',
        parser: (json) => WorkspaceAccessSnapshot.fromJson(json),
      );
      final cloudProjectsFuture = _fetchAccountEndpoint(
        endpointKey: 'cloud_projects',
        path: '/v1/cloud-projects/me',
        parser: (json) => CloudProjectAccessSnapshot.fromJson(json),
      );

      final catalogResult = await catalogFuture;
      final catalogWarnings = <String, String>{};
      if (catalogResult.error != null && catalogResult.error!.isNotEmpty) {
        catalogWarnings[catalogResult.endpointKey] = catalogResult.error!;
      }
      final catalog = catalogResult.data;
      if (catalog is BillingCatalogSnapshot) {
        _billingCatalog = catalog;
        await _writeCachedBillingCatalog(user.userId, catalog);
      }
      _accountSurfaceWarnings = catalogWarnings;
      _accountSurfaceError = catalogWarnings.isEmpty
          ? null
          : 'Some account details are temporarily unavailable.';
      notifyListeners();

      final remainingResults =
          await Future.wait<_AccountEndpointResult<dynamic>>(
        <Future<_AccountEndpointResult<dynamic>>>[
          organizationsFuture,
          workspacesFuture,
          cloudProjectsFuture,
          billingFuture,
        ],
      );
      final results = <_AccountEndpointResult<dynamic>>[
        catalogResult,
        ...remainingResults,
      ];

      final warnings = <String, String>{};
      for (final result in results) {
        if (result.error != null && result.error!.isNotEmpty) {
          warnings[result.endpointKey] = result.error!;
        }
      }

      final organizationsResult = results[1].data;
      final workspacesResult = results[2].data;
      final cloudProjectsResult = results[3].data;
      final billingResult = results[4].data;

      if (organizationsResult is OrganizationAccessSnapshot) {
        _organizationsAccess = organizationsResult;
      }
      if (workspacesResult is WorkspaceAccessSnapshot) {
        _workspacesAccess = workspacesResult;
      }
      if (cloudProjectsResult is CloudProjectAccessSnapshot) {
        _cloudProjectsAccess = cloudProjectsResult;
      }
      if (billingResult is BillingAccountSnapshot) {
        _billingAccount = billingResult;
      }

      _accountSurfaceWarnings = warnings;
      _accountSurfaceError = warnings.isEmpty
          ? null
          : results.every((result) => result.data == null)
              ? 'Account details are temporarily unavailable.'
              : 'Some account details are temporarily unavailable.';
      _accountSurfaceLastSyncedAtUtc = DateTime.now().toUtc();
      _isAccountSurfaceInitialized = true;
    } catch (e) {
      _accountSurfaceError = _cleanErrorMessage(e);
      _isAccountSurfaceInitialized = true;
    } finally {
      _isAccountSurfaceLoading = false;
      _accountSurfaceRefreshInFlight = null;
      if (!refreshCompleter.isCompleted) {
        refreshCompleter.complete();
      }
      notifyListeners();
    }
  }

  Future<void> refreshFeatureFlags({
    bool force = false,
  }) async {
    final auth = _auth;
    final user = auth?.signedInUser;
    if (auth == null || user == null) return;
    if (!force && !_areFeatureFlagsStale) return;

    try {
      if (!AppApiConfig.hasApiBaseUrl) return;
      final json = await _getAuthed('/v1/feature-flags');
      _appFeatureFlags = AppFeatureFlags.fromJson(
        json,
        fallback: AppFeatureFlags.defaults(),
      );
      _featureFlagsLastSyncedAtUtc = DateTime.now().toUtc();
      await _writeCachedFeatureFlags(user.userId, _appFeatureFlags);
      notifyListeners();
    } catch (_) {
      // Keep cached/local defaults if remote flags are temporarily unavailable.
    }
  }

  Future<Map<String, dynamic>> createWebCheckoutSession({
    required String regionCode,
    String? productCode,
    String? successUrl,
    String? cancelUrl,
  }) async {
    final body = <String, dynamic>{
      'region_code': regionCode,
      if ((productCode ?? '').trim().isNotEmpty) 'product_code': productCode,
      if ((successUrl ?? '').trim().isNotEmpty) 'success_url': successUrl,
      if ((cancelUrl ?? '').trim().isNotEmpty) 'cancel_url': cancelUrl,
    };
    return _postAuthed('/v1/billing/web/checkout-session', body: body);
  }

  Future<Map<String, dynamic>> verifyApplePurchase({
    required String transactionJws,
    String? productId,
    String? appAccountToken,
    double? price,
    String? currencyCode,
    String? billingCycle,
  }) async {
    final result = await _postAuthed(
      '/v1/billing/mobile/apple/verify',
      body: <String, dynamic>{
        'transaction_jws': transactionJws,
        if ((productId ?? '').trim().isNotEmpty) 'product_id': productId,
        if ((appAccountToken ?? '').trim().isNotEmpty)
          'app_account_token': appAccountToken,
        if (price != null) 'price': price,
        if ((currencyCode ?? '').trim().isNotEmpty)
          'currency_code': currencyCode,
        if ((billingCycle ?? '').trim().isNotEmpty)
          'billing_cycle': billingCycle,
      },
    );
    await refresh(force: true);
    await refreshAccountSurface(force: true);
    return result;
  }

  Future<Map<String, dynamic>> verifyGooglePurchase({
    required String purchaseToken,
    required String productId,
    String? packageName,
    String? obfuscatedAccountId,
    double? price,
    String? currencyCode,
    String? billingCycle,
  }) async {
    final result = await _postAuthed(
      '/v1/billing/mobile/google/verify',
      body: <String, dynamic>{
        'purchase_token': purchaseToken,
        'product_id': productId,
        if ((packageName ?? '').trim().isNotEmpty) 'package_name': packageName,
        if ((obfuscatedAccountId ?? '').trim().isNotEmpty)
          'obfuscated_account_id': obfuscatedAccountId,
        if (price != null) 'price': price,
        if ((currencyCode ?? '').trim().isNotEmpty)
          'currency_code': currencyCode,
        if ((billingCycle ?? '').trim().isNotEmpty)
          'billing_cycle': billingCycle,
      },
    );
    await refresh(force: true);
    await refreshAccountSurface(force: true);
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
    await refreshAccountSurface(force: true);
  }

  Future<String?> fetchPortalUrl() async {
    try {
      final billingJson = await _getAuthed('/v1/billing/me');
      final managed = (billingJson['manage_url'] ?? '').toString().trim();
      if (managed.isNotEmpty) return managed;
    } catch (_) {
      // Older deployed APIs may only expose the legacy portal endpoint.
    }
    final portalJson = await _getAuthed('/v1/billing/portal-url');
    final raw = (portalJson['url'] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  Future<EducationAdminSnapshot> fetchEducationAdmin() async {
    final json = await _getAuthed('/v1/education/me');
    return EducationAdminSnapshot.fromJson(json);
  }

  Future<EducationInviteResult> inviteEducationStudent({
    required String organizationId,
    required String email,
  }) async {
    final payload = await _postAuthed(
      '/v1/education/me/invites',
      body: <String, dynamic>{
        'organization_id': organizationId,
        'email': email,
      },
    );
    await refreshAccountSurface(force: true);
    final membership = payload['membership'];
    final emailSent = payload['email_sent'] == true;
    final emailError = (payload['email_error'] ?? '').toString();
    if (membership is Map<String, dynamic>) {
      return EducationInviteResult(
        membership: OrganizationMembershipItem.fromJson(membership),
        emailSent: emailSent,
        emailError: emailError,
      );
    }
    if (membership is Map) {
      return EducationInviteResult(
        membership: OrganizationMembershipItem.fromJson(
          membership.map((key, value) => MapEntry(key.toString(), value)),
        ),
        emailSent: emailSent,
        emailError: emailError,
      );
    }
    return EducationInviteResult(
      membership: null,
      emailSent: emailSent,
      emailError: emailError,
    );
  }

  Future<OrganizationMembershipItem?> updateEducationMembership({
    required String organizationId,
    required String userId,
    required String status,
    String role = 'student',
    String? email,
  }) async {
    final payload = await _postAuthed(
      '/v1/education/me/memberships',
      body: <String, dynamic>{
        'organization_id': organizationId,
        'user_id': userId,
        'status': status,
        'role': role,
        if ((email ?? '').trim().isNotEmpty) 'email': email,
      },
    );
    await refreshAccountSurface(force: true);
    final membership = payload['membership'];
    if (membership is Map<String, dynamic>) {
      return OrganizationMembershipItem.fromJson(membership);
    }
    if (membership is Map) {
      return OrganizationMembershipItem.fromJson(
        membership.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return null;
  }

  Future<Map<String, dynamic>> educationClassLink({
    required String organizationId,
    String action = 'get',
  }) async {
    final payload = await _postAuthed('/v1/education/me/invites', body: {
      'organization_id': organizationId,
      'action': 'class_link_$action',
    });
    final link = payload['class_invite'];
    return link is Map ? Map<String, dynamic>.from(link) : <String, dynamic>{};
  }

  Future<OrganizationMembershipItem?> acceptEducationInvite({
    required String inviteToken,
  }) async {
    final safeToken = Uri.encodeComponent(inviteToken.trim());
    final payload =
        await _postAuthed('/v1/education/invites/$safeToken/accept');
    await refresh(force: true);
    await refreshAccountSurface(force: true);
    final membership = payload['membership'];
    if (membership is Map<String, dynamic>) {
      return OrganizationMembershipItem.fromJson(membership);
    }
    if (membership is Map) {
      return OrganizationMembershipItem.fromJson(
        membership.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return null;
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
    final ttl = Duration(minutes: AppApiConfig.entitlementCacheTtlMinutes);
    return DateTime.now().toUtc().difference(synced) > ttl;
  }

  bool get _isAccountSurfaceStale {
    final synced = _accountSurfaceLastSyncedAtUtc;
    if (synced == null) return true;
    final ttl = Duration(minutes: AppApiConfig.entitlementCacheTtlMinutes);
    return DateTime.now().toUtc().difference(synced) > ttl;
  }

  bool get _areFeatureFlagsStale {
    final synced = _featureFlagsLastSyncedAtUtc;
    if (synced == null) return true;
    final ttl = Duration(minutes: AppApiConfig.entitlementCacheTtlMinutes);
    return DateTime.now().toUtc().difference(synced) > ttl;
  }

  Future<_AccountEndpointResult<T>> _fetchAccountEndpoint<T>({
    required String endpointKey,
    required String path,
    required T Function(Map<String, dynamic> json) parser,
  }) async {
    try {
      final json = await _getAuthed(path);
      return _AccountEndpointResult<T>(
        endpointKey: endpointKey,
        data: parser(json),
      );
    } catch (e) {
      return _AccountEndpointResult<T>(
        endpointKey: endpointKey,
        error: _friendlyEndpointError(endpointKey, e),
      );
    }
  }

  Future<Map<String, dynamic>> _getAuthed(String path) async {
    final response = await _sendAuthedNoExpire(
      (token) => _httpClient.get(
        _buildUri(path),
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
    );
    return _decodeResponse(path: path, response: response);
  }

  Future<Map<String, dynamic>> _postAuthed(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _sendAuthedNoExpire(
      (token) => _httpClient
          .post(
            _buildUri(path),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              ...(body ?? const <String, dynamic>{}),
              ...AnalyticsService.instance.buildRequestContext(),
            }),
          )
          .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
    );
    return _decodeResponse(path: path, response: response);
  }

  Future<http.Response> _sendAuthedNoExpire(
    Future<http.Response> Function(String token) send,
  ) async {
    final auth = _auth;
    final user = auth?.signedInUser;
    if (auth == null || user == null) {
      throw StateError('No authenticated user.');
    }
    if (!AppApiConfig.hasApiBaseUrl) {
      throw StateError('Subscription API base URL is not configured.');
    }

    return auth.authorizedRequest(send);
  }

  Map<String, dynamic> _decodeResponse({
    required String path,
    required http.Response response,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Request $path failed (${response.statusCode}): ${response.body}',
      );
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
    final base = AppApiConfig.apiBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base$path');
  }

  void _handleAuthStateChanged() {
    final auth = _auth;
    final userId = auth?.signedInUser?.userId;
    if (userId == null || userId.trim().isEmpty) {
      if (_boundUserId != null) {
        final previousUserId = _boundUserId!;
        _boundUserId = null;
        _resetStateForSignedOutUser();
        notifyListeners();
        unawaited(_clearCachedEntitlement(previousUserId));
      }
      return;
    }

    if (_boundUserId == userId) {
      if (_areFeatureFlagsStale) {
        unawaited(refreshFeatureFlags());
      }
      if ((_entitlement == null || _isEntitlementStale) && !_isLoading) {
        unawaited(refresh());
      }
      if (_isAccountSurfaceStale && !_isAccountSurfaceLoading) {
        unawaited(refreshAccountSurface());
      }
      return;
    }

    _boundUserId = userId;
    _entitlement = EntitlementSnapshot.free(userId: userId);
    _billingCatalog = null;
    _appFeatureFlags = AppFeatureFlags.defaults();
    _organizationsAccess = null;
    _workspacesAccess = null;
    _cloudProjectsAccess = null;
    AnalyticsService.instance.setSubscriptionTier(_entitlement?.planCode);
    _lastSyncedAtUtc = null;
    _accountSurfaceLastSyncedAtUtc = null;
    _featureFlagsLastSyncedAtUtc = null;
    _lastError = null;
    _accountSurfaceError = null;
    _accountSurfaceWarnings = <String, String>{};
    _isInitialized = true;
    _isAccountSurfaceInitialized = false;
    notifyListeners();

    unawaited(
      _loadCachedEntitlement(userId).then((_) async {
        await _loadCachedFeatureFlags(userId);
        await _loadCachedBillingCatalog(userId);
        await refreshFeatureFlags(force: true);
        await refresh(force: true);
        await refreshAccountSurface(force: true);
      }),
    );
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
      AnalyticsService.instance.setSubscriptionTier(_entitlement?.planCode);
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

  Future<void> _loadCachedBillingCatalog(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_catalogCacheKey(userId));
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final data = decoded.map((key, value) => MapEntry(key.toString(), value));
      _billingCatalog = BillingCatalogSnapshot.fromJson(data);
      notifyListeners();
    } catch (_) {
      // Ignore cache parse failures and fallback to local/default catalog.
    }
  }

  Future<void> _loadCachedFeatureFlags(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_featureFlagsCacheKey(userId));
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final data = decoded.map((key, value) => MapEntry(key.toString(), value));
      _appFeatureFlags = AppFeatureFlags.fromJson(
        data,
        fallback: AppFeatureFlags.defaults(),
      );
      _featureFlagsLastSyncedAtUtc = DateTime.now().toUtc();
      notifyListeners();
    } catch (_) {
      // Ignore cache parse failures and fallback to local/default flags.
    }
  }

  Future<void> _writeCachedBillingCatalog(
    String userId,
    BillingCatalogSnapshot catalog,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _catalogCacheKey(userId),
      jsonEncode(catalog.toJson()),
    );
  }

  Future<void> _writeCachedFeatureFlags(
    String userId,
    AppFeatureFlags flags,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _featureFlagsCacheKey(userId),
      jsonEncode(flags.toJson()),
    );
  }

  Future<void> _clearCachedEntitlement(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey(userId));
  }

  String _cacheKey(String userId) => '$_prefsKeyPrefix.$userId';

  String _catalogCacheKey(String userId) => '$_catalogPrefsKeyPrefix.$userId';

  String _featureFlagsCacheKey(String userId) =>
      '$_featureFlagsPrefsKeyPrefix.$userId';

  void _setFallbackFreeEntitlement(String userId) {
    _entitlement = EntitlementSnapshot.free(userId: userId);
    AnalyticsService.instance.setSubscriptionTier(_entitlement?.planCode);
    _lastSyncedAtUtc = DateTime.now().toUtc();
    _isInitialized = true;
  }

  void _resetStateForSignedOutUser() {
    _entitlement = null;
    _billingCatalog = null;
    _appFeatureFlags = AppFeatureFlags.defaults();
    _organizationsAccess = null;
    _workspacesAccess = null;
    _cloudProjectsAccess = null;
    AnalyticsService.instance.setSubscriptionTier(null);
    _lastSyncedAtUtc = null;
    _accountSurfaceLastSyncedAtUtc = null;
    _featureFlagsLastSyncedAtUtc = null;
    _lastError = null;
    _accountSurfaceError = null;
    _accountSurfaceWarnings = <String, String>{};
    _isInitialized = false;
    _isAccountSurfaceInitialized = false;
  }

  void _detachAuthListener() {
    final auth = _auth;
    final listener = _authListener;
    if (auth != null && listener != null) {
      auth.removeListener(listener);
    }
    _authListener = null;
  }

  String _friendlyEndpointError(String endpointKey, Object error) {
    final message = _cleanErrorMessage(error);
    if (message.contains('(404)')) {
      return '${_endpointLabel(endpointKey)} endpoint is not available.';
    }
    if (message.contains('(401)')) {
      return 'Sign in again to load ${_endpointLabel(endpointKey).toLowerCase()}.';
    }
    if (message.contains('(403)')) {
      return '${_endpointLabel(endpointKey)} is not available for this account.';
    }
    if (message.isEmpty) {
      return '${_endpointLabel(endpointKey)} is temporarily unavailable.';
    }
    return message;
  }

  String _endpointLabel(String endpointKey) {
    switch (endpointKey) {
      case 'catalog':
        return 'Billing catalog';
      case 'organizations':
        return 'Organizations';
      case 'workspaces':
        return 'Workspaces';
      case 'cloud_projects':
        return 'Cloud projects';
      default:
        return 'Account data';
    }
  }

  String _cleanErrorMessage(Object error) {
    return error.toString().replaceFirst('Bad state: ', '').trim();
  }

  int _maxInt(int a, int b, int c) {
    final maxAB = a > b ? a : b;
    return maxAB > c ? maxAB : c;
  }
}

class _AccountEndpointResult<T> {
  const _AccountEndpointResult({
    required this.endpointKey,
    this.data,
    this.error,
  });

  final String endpointKey;
  final T? data;
  final String? error;
}
