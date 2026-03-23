import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/config/legal_config.dart';
import 'package:mixroom/core/privacy/privacy_preferences.dart';
import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/models/app_user_models.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppUserService extends ChangeNotifier {
  AppUserService({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const String _prefsKeyPrefix = 'mixroom.app_user.profile.v1';
  static const String _pendingSignupConsentKeyPrefix =
      'mixroom.app_user.signup_legal_consent.v1';
  static const String _welcomeSeenKeyPrefix =
      'mixroom.app_user.welcome_seen.v1';

  final http.Client _httpClient;

  AuthService? _auth;
  VoidCallback? _authListener;

  AppUserSnapshot? _current;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _lastError;
  DateTime? _lastSyncedAtUtc;
  String? _boundUserId;
  String? _boundSignature;
  bool _isSyncingPendingConsent = false;
  bool _hasPendingSignupProfileSync = false;
  bool _isResolvingPostSignIn = false;
  Future<void>? _refreshInFlight;

  AppUserSnapshot? get current => _current;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get lastError => _lastError;
  DateTime? get lastSyncedAtUtc => _lastSyncedAtUtc;
  bool get supportsRemoteProfileEdits => AppApiConfig.hasApiBaseUrl;
  bool get hasPendingSignupProfileSync => _hasPendingSignupProfileSync;
  bool get isResolvingPostSignIn => _isResolvingPostSignIn;

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
    final user = auth?.signedInUser;
    if (auth == null || user == null) return;
    if (_isLoading) {
      await (_refreshInFlight ?? Future<void>.value());
      return;
    }
    if (!force && !_isProfileStale) return;

    final refreshCompleter = Completer<void>();
    _refreshInFlight = refreshCompleter.future;
    _isLoading = true;
    notifyListeners();

    try {
      if (!AppApiConfig.hasApiBaseUrl) {
        _setFallbackFromAuth(user, notify: false);
        _lastError = null;
        _isInitialized = true;
        return;
      }

      final response = await auth.authorizedRequest(
        (token) => _httpClient.get(
          _buildUri('/v1/users/me'),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ).timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          _extractErrorMessage(
                response.body,
                fallback:
                    'User bootstrap request failed (${response.statusCode}).',
              ) ??
              'User bootstrap request failed (${response.statusCode}).',
        );
      }

      var nextProfile =
          _parseProfileResponse(response.body, fallbackUser: user);
      final consentSyncedProfile = await _syncPendingSignupConsent(
        user: user,
        currentProfile: nextProfile,
      );
      if (consentSyncedProfile != null) {
        nextProfile = consentSyncedProfile;
      }

      _current = nextProfile;
      _lastSyncedAtUtc = DateTime.now().toUtc();
      _lastError = null;
      _isInitialized = true;
      await _writeCachedProfile(user.userId, _current!);
    } catch (e) {
      _lastError = e.toString().replaceFirst('Bad state: ', '');
      _isInitialized = true;
      if (_current == null) {
        _setFallbackFromAuth(user, notify: false);
      }
    } finally {
      _isLoading = false;
      final inFlight = refreshCompleter;
      _refreshInFlight = null;
      if (!inFlight.isCompleted) {
        inFlight.complete();
      }
      notifyListeners();
    }
  }

  Future<void> updateProfile({
    required String displayName,
    required String username,
    required String bio,
    String? avatarUrl,
  }) async {
    final auth = _auth;
    final user = auth?.signedInUser;
    if (auth == null || user == null) {
      throw StateError('No active account.');
    }
    if (!supportsRemoteProfileEdits) {
      throw StateError('App profile backend is not configured yet.');
    }
    if (_isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      final body = <String, dynamic>{
        'display_name': displayName.trim(),
        'username': username.trim(),
        'bio': bio.trim(),
      };
      if (avatarUrl != null) {
        body['avatar_url'] = avatarUrl.trim();
      }

      final response = await auth.authorizedRequest(
        (token) => _httpClient
            .patch(
              _buildUri('/v1/users/me'),
              headers: <String, String>{
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body),
            )
            .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          _extractErrorMessage(
                response.body,
                fallback: 'Profile update failed (${response.statusCode}).',
              ) ??
              'Profile update failed (${response.statusCode}).',
        );
      }

      _current = _parseProfileResponse(
        response.body,
        fallbackUser: auth.signedInUser ?? user,
      );
      _lastSyncedAtUtc = DateTime.now().toUtc();
      _lastError = null;
      _isInitialized = true;
      await _writeCachedProfile(user.userId, _current!);
    } catch (e) {
      _lastError = e.toString().replaceFirst('Bad state: ', '');
      _isInitialized = true;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> markWelcomeOnboardingSeen() async {
    await stageWelcomeOnboardingSeen();
    await syncWelcomeOnboardingSeen();
  }

  Future<bool> hasSeenWelcomeOnboardingLocally(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_welcomeSeenKey(userId)) ?? false;
  }

  Future<void> stageWelcomeOnboardingSeen() async {
    final auth = _auth;
    final user = auth?.signedInUser;
    final current = _current;
    if (auth == null || user == null || current == null) {
      return;
    }
    if (current.hasSeenWelcomeOnboarding) {
      return;
    }

    final nextProfile = AppUserSnapshot.fromJson(
      <String, dynamic>{
        ...current.toJson(),
        'onboarding_state': AppUserSnapshot.welcomeSeenState,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      fallbackAuthUser: user,
    );

    _current = nextProfile;
    _lastSyncedAtUtc = DateTime.now().toUtc();
    _lastError = null;
    _isInitialized = true;
    notifyListeners();
    await _writeCachedProfile(user.userId, nextProfile);
    await _writeWelcomeSeenFlag(user.userId, true);
  }

  Future<void> syncWelcomeOnboardingSeen() async {
    final auth = _auth;
    final user = auth?.signedInUser;
    final current = _current;
    if (auth == null || user == null || current == null) {
      return;
    }

    if (!supportsRemoteProfileEdits) {
      return;
    }

    final response = await auth.authorizedRequest(
      (token) => _httpClient
          .patch(
            _buildUri('/v1/users/me'),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'onboarding_state': AppUserSnapshot.welcomeSeenState,
            }),
          )
          .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        _extractErrorMessage(
              response.body,
              fallback: 'Failed to save welcome state.',
            ) ??
            'Failed to save welcome state.',
      );
    }

    _current = _parseProfileResponse(response.body, fallbackUser: user);
    _lastSyncedAtUtc = DateTime.now().toUtc();
    _lastError = null;
    _isInitialized = true;
    notifyListeners();
    await _writeCachedProfile(user.userId, _current!);
  }

  Future<void> stageSignupConsents({
    required String email,
    String? username,
    String? displayName,
    String? givenName,
    String? familyName,
    String? birthdate,
    required bool newsletterOptIn,
  }) async {
    final safeEmail = email.trim().toLowerCase();
    if (safeEmail.isEmpty) return;
    final safeUsername = (username ?? '').trim().toLowerCase();
    final safeDisplayName = (displayName ?? '').trim();
    final safeGivenName = (givenName ?? '').trim();
    final safeFamilyName = (familyName ?? '').trim();
    final safeBirthdate = (birthdate ?? '').trim();

    final acceptedAt = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'email': safeEmail,
      'username': safeUsername.isEmpty ? null : safeUsername,
      'display_name': safeDisplayName.isEmpty ? null : safeDisplayName,
      'given_name': safeGivenName.isEmpty ? null : safeGivenName,
      'family_name': safeFamilyName.isEmpty ? null : safeFamilyName,
      'birthdate': safeBirthdate.isEmpty ? null : safeBirthdate,
      'accepted_terms_version': LegalConfig.termsVersion,
      'accepted_privacy_version': LegalConfig.privacyVersion,
      'accepted_at': acceptedAt.toIso8601String(),
      'newsletter_opt_in': newsletterOptIn,
      'newsletter_opt_in_at':
          newsletterOptIn ? acceptedAt.toIso8601String() : null,
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingSignupConsentKey(safeEmail),
      jsonEncode(payload),
    );
    await PrivacyPreferences.setProductEmailsEnabled(newsletterOptIn);
    _hasPendingSignupProfileSync = true;
    notifyListeners();

    final auth = _auth;
    final currentUser = auth?.signedInUser;
    if (auth != null &&
        currentUser != null &&
        auth.hasActiveSessionTokens &&
        currentUser.email.trim().toLowerCase() == safeEmail) {
      unawaited(refresh(force: true));
    }
  }

  void beginPostSignInResolution() {
    if (_isResolvingPostSignIn) return;
    _isResolvingPostSignIn = true;
    notifyListeners();
  }

  void completePostSignInResolution() {
    if (!_isResolvingPostSignIn) return;
    _isResolvingPostSignIn = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _detachAuthListener();
    _httpClient.close();
    super.dispose();
  }

  bool get _isProfileStale {
    final synced = _lastSyncedAtUtc;
    if (synced == null) return true;
    final ttl = Duration(minutes: AppApiConfig.entitlementCacheTtlMinutes);
    return DateTime.now().toUtc().difference(synced) > ttl;
  }

  Uri _buildUri(String path) {
    final base = AppApiConfig.apiBaseUrl.trim();
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  AppUserSnapshot _parseProfileResponse(
    String rawBody, {
    required AuthUserProfile fallbackUser,
  }) {
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) {
      throw const FormatException('User profile response shape is invalid.');
    }
    final json = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    return AppUserSnapshot.fromJson(
      json,
      fallbackAuthUser: fallbackUser,
    );
  }

  String? _extractErrorMessage(
    String rawBody, {
    String? fallback,
  }) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map) {
        final message = decoded['error']?.toString().trim() ?? '';
        if (message.isNotEmpty) return message;
      }
    } catch (_) {
      // Ignore parse failures and use fallback.
    }
    return fallback;
  }

  void _handleAuthStateChanged() {
    final auth = _auth;
    final user = auth?.signedInUser;
    if (user == null) {
      if (_boundUserId != null) {
        final previousUserId = _boundUserId!;
        _boundUserId = null;
        _boundSignature = null;
        _current = null;
        _lastSyncedAtUtc = null;
        _lastError = null;
        _isInitialized = false;
        _hasPendingSignupProfileSync = false;
        _isResolvingPostSignIn = false;
        notifyListeners();
        unawaited(_clearCachedProfile(previousUserId));
      }
      return;
    }

    final signature = _signatureForUser(user);
    if (_boundUserId != user.userId) {
      _boundUserId = user.userId;
      _boundSignature = signature;
      _setFallbackFromAuth(user, notify: false);
      _lastSyncedAtUtc = null;
      _lastError = null;
      _isInitialized = false;
      notifyListeners();
      unawaited(
        _loadPendingSignupProfileSyncFlag(user.email)
            .then((_) => refresh(force: true)),
      );
      return;
    }

    if (_boundSignature != signature) {
      _boundSignature = signature;
      _setFallbackFromAuth(user, notify: false);
      notifyListeners();
      unawaited(refresh(force: true));
      return;
    }

    if ((_current == null || _isProfileStale) && !_isLoading) {
      unawaited(refresh());
    }
  }

  Future<void> _writeCachedProfile(
    String userId,
    AppUserSnapshot profile,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey(userId),
      jsonEncode(profile.toJson()),
    );
  }

  Future<void> _clearCachedProfile(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey(userId));
  }

  Future<void> _writeWelcomeSeenFlag(String userId, bool seen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_welcomeSeenKey(userId), seen);
  }

  void _setFallbackFromAuth(
    AuthUserProfile user, {
    required bool notify,
  }) {
    _current = AppUserSnapshot.fromAuthUser(user);
    _lastSyncedAtUtc = DateTime.now().toUtc();
    if (notify) {
      notifyListeners();
    }
  }

  String _signatureForUser(AuthUserProfile user) {
    return <String>[
      user.userId,
      user.email,
      user.displayName,
      user.provider.value,
      user.emailVerified.toString(),
    ].join('|');
  }

  String _cacheKey(String userId) => '$_prefsKeyPrefix.$userId';

  String _welcomeSeenKey(String userId) => '$_welcomeSeenKeyPrefix.$userId';

  String _pendingSignupConsentKey(String email) =>
      '$_pendingSignupConsentKeyPrefix.${email.trim().toLowerCase()}';

  Future<void> _loadPendingSignupProfileSyncFlag(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _pendingSignupConsentKey(email);
    final raw = prefs.getString(key);
    final hasPending = raw != null && raw.trim().isNotEmpty;
    if (_hasPendingSignupProfileSync == hasPending) return;
    _hasPendingSignupProfileSync = hasPending;
    notifyListeners();
  }

  Future<AppUserSnapshot?> _syncPendingSignupConsent({
    required AuthUserProfile user,
    required AppUserSnapshot currentProfile,
  }) async {
    if (!supportsRemoteProfileEdits || _isSyncingPendingConsent) {
      return null;
    }
    final auth = _auth;
    if (auth == null || auth.signedInUser == null) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final key = _pendingSignupConsentKey(user.email);
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      if (_hasPendingSignupProfileSync) {
        _hasPendingSignupProfileSync = false;
        notifyListeners();
      }
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final payload = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final safeEmail =
          (payload['email'] ?? '').toString().trim().toLowerCase();
      if (safeEmail != user.email.trim().toLowerCase()) {
        return null;
      }

      final acceptedTermsVersion =
          (payload['accepted_terms_version'] ?? '').toString().trim();
      final acceptedPrivacyVersion =
          (payload['accepted_privacy_version'] ?? '').toString().trim();
      final acceptedAt = (payload['accepted_at'] ?? '').toString().trim();
      final displayName = (payload['display_name'] ?? '').toString().trim();
      final givenName = (payload['given_name'] ?? '').toString().trim();
      final familyName = (payload['family_name'] ?? '').toString().trim();
      final birthdate = (payload['birthdate'] ?? '').toString().trim();
      final username = (payload['username'] ?? '').toString().trim().toLowerCase();
      final newsletterOptIn = payload['newsletter_opt_in'] == true;
      final newsletterOptInAt =
          (payload['newsletter_opt_in_at'] ?? '').toString().trim();

      final alreadySynced = currentProfile.acceptedTermsVersion ==
              acceptedTermsVersion &&
          ((currentProfile.displayName).trim() == displayName ||
              displayName.isEmpty) &&
          ((currentProfile.username ?? '').trim().toLowerCase() == username ||
              username.isEmpty) &&
          ((currentProfile.givenName ?? '').trim() == givenName ||
              givenName.isEmpty) &&
          ((currentProfile.familyName ?? '').trim() == familyName ||
              familyName.isEmpty) &&
          ((currentProfile.birthdate ?? '').trim() == birthdate ||
              birthdate.isEmpty) &&
          currentProfile.acceptedPrivacyVersion == acceptedPrivacyVersion &&
          (currentProfile.acceptedAt?.toIso8601String() ?? '') == acceptedAt &&
          currentProfile.newsletterOptIn == newsletterOptIn &&
          (currentProfile.newsletterOptInAt?.toIso8601String() ?? '') ==
              newsletterOptInAt;
      if (alreadySynced) {
        await prefs.remove(key);
        _hasPendingSignupProfileSync = false;
        notifyListeners();
        return null;
      }

      _isSyncingPendingConsent = true;
      final response = await auth.authorizedRequest(
        (authedToken) => _httpClient
            .patch(
              _buildUri('/v1/users/me'),
              headers: <String, String>{
                'Authorization': 'Bearer $authedToken',
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(<String, dynamic>{
                if (displayName.isNotEmpty) 'display_name': displayName,
                if (username.isNotEmpty) 'username': username,
                if (givenName.isNotEmpty) 'given_name': givenName,
                if (familyName.isNotEmpty) 'family_name': familyName,
                if (birthdate.isNotEmpty) 'birthdate': birthdate,
                'accepted_terms_version': acceptedTermsVersion,
                'accepted_privacy_version': acceptedPrivacyVersion,
                'accepted_at': acceptedAt,
                'newsletter_opt_in': newsletterOptIn,
                'newsletter_opt_in_at':
                    newsletterOptIn ? newsletterOptInAt : null,
              }),
            )
            .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _lastError = _extractErrorMessage(
              response.body,
              fallback: 'Failed to finish creating your account.',
            ) ??
            'Failed to finish creating your account.';
        return null;
      }

      await prefs.remove(key);
      _hasPendingSignupProfileSync = false;
      _lastError = null;
      notifyListeners();
      return _parseProfileResponse(response.body, fallbackUser: user);
    } catch (_) {
      _hasPendingSignupProfileSync = true;
      return null;
    } finally {
      _isSyncingPendingConsent = false;
    }
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
