import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/config/cognito_config.dart';
import 'package:mixroom/config/dev_flags.dart';
import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/core/analytics/analytics_events.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/core/crash_reporting/crash_reporting_service.dart';
import 'package:mixroom/core/security/sensitive_storage.dart';
import 'package:mixroom/helpers/cognito_auth_client.dart';
import 'package:mixroom/helpers/native_social_sign_in.dart';
import 'package:mixroom/helpers/password_policy.dart';
import 'package:mixroom/models/auth_user_profile.dart';

class AuthService extends ChangeNotifier {
  static const String _prefsSessionKey = 'mixroom.auth.session.v2';

  AuthService({
    CognitoAuthClient? cognitoClient,
    http.Client? httpClient,
    bool restoreSessionOnInit = true,
  })  : _cognito = cognitoClient ?? CognitoAuthClient(),
        _httpClient = httpClient ?? http.Client() {
    if (restoreSessionOnInit) {
      unawaited(_restoreSession());
    } else {
      _isInitializing = false;
    }
  }

  final CognitoAuthClient _cognito;
  final http.Client _httpClient;

  bool _isInitializing = true;
  bool _isBusy = false;
  AuthUserProfile? _currentUser;
  CognitoTokens? _tokens;
  String? _pendingEmailUsername;
  bool _lastSocialSignInRequiresSignupCompletion = false;
  Future<CognitoSession?>? _sessionRefreshInFlight;

  bool get isInitializing => _isInitializing;
  bool get isBusy => _isBusy;
  bool get isSignedIn => signedInUser != null;
  bool get hasActiveSessionTokens => _hasRecoverableSessionTokens(_tokens);
  bool get lastSocialSignInRequiresSignupCompletion =>
      _lastSocialSignInRequiresSignupCompletion;
  AuthUserProfile? get currentUser => _currentUser;
  AuthUserProfile? get signedInUser =>
      _hasAppAccess(user: _currentUser, tokens: _tokens) ? _currentUser : null;
  bool get hasPendingEmailVerification =>
      _currentUser?.provider == AuthProviderType.email &&
      !(_currentUser?.emailVerified ?? true);

  Future<String?> getIdTokenOrNull() async {
    final user = _sessionUserOrNull();
    final tokens = _tokens;
    if (user == null || tokens == null) return null;
    final fallbackIdToken = tokens.idToken.trim();
    final canUseFallbackToken =
        fallbackIdToken.isNotEmpty && _hasUsableAccessTokens(tokens);

    try {
      await _refreshSessionIfNeeded(provider: user.provider);
    } catch (_) {
      if (canUseFallbackToken) {
        return fallbackIdToken;
      }
      return null;
    }

    final idToken = _tokens?.idToken.trim() ?? '';
    return idToken.isEmpty ? null : idToken;
  }

  Future<String?> refreshIdTokenOrNull() async {
    final user = _sessionUserOrNull();
    if (user == null) return null;

    try {
      await _refreshSessionIfNeeded(
        provider: user.provider,
        forceRefresh: true,
      );
    } catch (_) {
      return null;
    }

    final idToken = _tokens?.idToken.trim() ?? '';
    return idToken.isEmpty ? null : idToken;
  }

  Future<List<String>> getRequestTokenCandidates({
    bool forceRefresh = false,
  }) {
    return _collectAuthTokenCandidates(forceRefresh: forceRefresh);
  }

  Future<http.Response> authorizedRequest(
    Future<http.Response> Function(String token) send, {
    bool expireSessionOnAuthFailure = false,
  }) async {
    final initialCandidates = await _collectAuthTokenCandidates();
    if (initialCandidates.isEmpty) {
      if (expireSessionOnAuthFailure) {
        await _expireSessionAndThrow();
      }
      throw StateError('Session expired. Please sign in again.');
    }

    http.Response? lastAuthFailure;
    for (final token in initialCandidates) {
      final response = await send(token);
      if (!_isUnauthorizedResponse(response)) {
        return response;
      }
      lastAuthFailure = response;
    }

    final refreshedCandidates =
        await _collectAuthTokenCandidates(forceRefresh: true);
    if (refreshedCandidates.isEmpty) {
      if (lastAuthFailure != null) {
        if (_isUnauthorizedResponse(lastAuthFailure)) {
          if (expireSessionOnAuthFailure) {
            await _expireSessionAndThrow();
          }
          return lastAuthFailure;
        }
        return lastAuthFailure;
      }
      if (expireSessionOnAuthFailure) {
        await _expireSessionAndThrow();
      }
      throw StateError('Session expired. Please sign in again.');
    }

    for (final token in refreshedCandidates) {
      final response = await send(token);
      if (!_isUnauthorizedResponse(response)) {
        return response;
      }
      lastAuthFailure = response;
    }

    if (lastAuthFailure != null) {
      if (_isUnauthorizedResponse(lastAuthFailure)) {
        if (expireSessionOnAuthFailure) {
          await _expireSessionAndThrow();
        }
        return lastAuthFailure;
      }
      return lastAuthFailure;
    }
    if (expireSessionOnAuthFailure) {
      await _expireSessionAndThrow();
    }
    throw StateError('Session expired. Please sign in again.');
  }

  Future<void> _restoreSession() async {
    try {
      if (isAuthBypassEnabled) {
        _currentUser = _debugUser;
      } else {
        final rawSession = await SensitiveStorage.instance
            .readWithMigration(_prefsSessionKey)
            .timeout(
              const Duration(seconds: 4),
              onTimeout: () => null,
            );
        if (rawSession != null && rawSession.isNotEmpty) {
          final decoded = jsonDecode(rawSession);
          final map = _asStringDynamicMap(decoded);
          if (map.isNotEmpty) {
            final userMap = _asStringDynamicMap(map['user']);
            final legacyUserMap = map.containsKey('userId') ? map : null;
            final tokenMap = _asStringDynamicMap(map['tokens']);

            if (userMap.isNotEmpty) {
              _currentUser = AuthUserProfile.fromJson(userMap);
            } else if (legacyUserMap != null) {
              _currentUser = AuthUserProfile.fromJson(legacyUserMap);
            }
            if (tokenMap.isNotEmpty) {
              _tokens = CognitoTokens.fromJson(tokenMap);
            }
            final pendingEmailUsername =
                (map['pendingEmailUsername'] ?? '').toString().trim();
            _pendingEmailUsername =
                pendingEmailUsername.isEmpty ? null : pendingEmailUsername;
          }
        }

        final current = _currentUser;
        final tokens = _tokens;
        if (current != null && tokens != null) {
          try {
            await _refreshSessionIfNeeded(
              provider: current.provider,
            ).timeout(
              const Duration(seconds: 5),
              onTimeout: () => null,
            );
            if (_needsNativeSessionUpgrade(tokens) &&
                !_isNativeRefreshToken(_tokens?.refreshToken ?? '')) {
              await _clearSession();
            }
          } catch (_) {
            if (_needsNativeSessionUpgrade(tokens)) {
              await _clearSession();
            }
          }
        }
      }
    } catch (_) {
      _currentUser = null;
      _tokens = null;
    } finally {
      unawaited(_syncObservabilityUser());
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final rawIdentifier = email.trim();
    final normalizedIdentifier = _normalizeLoginIdentifier(rawIdentifier);
    if (normalizedIdentifier.isEmpty || password.isEmpty) {
      throw StateError('Please enter both email/username and password.');
    }

    await _runBusyTask(() async {
      if (AppApiConfig.hasApiBaseUrl) {
        await _signInWithBackendIdentifier(
          identifier: normalizedIdentifier,
          password: password,
        );
        return;
      }
      try {
        final session = await _cognito.signInWithEmail(
          email: normalizedIdentifier,
          password: password,
        );
        _setSession(
          session,
          provider: AuthProviderType.email,
          createdAt: DateTime.now(),
        );
        await _persistSession();
        await _syncObservabilityUser();
        unawaited(
          AnalyticsService.instance.track(
            AnalyticsEvents.userLoggedIn(
                loginMethod: AuthProviderType.email.value),
          ),
        );
      } on CognitoApiException catch (e) {
        if (e.code == 'UserNotConfirmedException') {
          _setPendingEmailSession(
            email: normalizedIdentifier.toLowerCase(),
            displayName: _nameFromEmail(normalizedIdentifier.toLowerCase()),
            pendingUsername: normalizedIdentifier,
          );
          await _persistSession();
          await _syncObservabilityUser();
          throw AuthEmailConfirmationRequiredException(
            email: normalizedIdentifier.toLowerCase(),
            message:
                'Email not verified yet. Verify your email to finish signing in.',
          );
        }
        if (e.code == 'NotAuthorizedException' ||
            e.code == 'UserNotFoundException') {
          throw StateError('Incorrect email or password.');
        }
        if (e.code == 'InvalidParameterException') {
          throw StateError(
            'Authentication is not configured correctly yet. Please try again later.',
          );
        }
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> _signInWithBackendIdentifier({
    required String identifier,
    required String password,
  }) async {
    final uri = _subscriptionApiUri('/v1/auth/sign-in');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final body = jsonEncode(<String, dynamic>{
      'identifier': identifier,
      'password': password,
    });

    final response = await _postWithAuthResilience(
      uri: uri,
      headers: headers,
      body: body,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final backendDetails = _extractBackendErrorDetails(response.body);
      final backendCode = _extractBackendErrorCode(response.body);
      final backendMessage = _extractBackendError(
            response.body,
            fallback:
                'Sign-in failed (${response.statusCode}). Please try again.',
          ) ??
          'Sign-in failed (${response.statusCode}). Please try again.';

      if (backendCode == 'EMAIL_CONFIRMATION_REQUIRED') {
        final pendingEmail =
            (backendDetails['email'] ?? '').toString().trim().toLowerCase();
        final pendingUsername =
            (backendDetails['pending_username'] ?? '').toString().trim();
        final fallbackEmail = _looksLikeEmail(identifier)
            ? identifier.toLowerCase()
            : pendingEmail;
        _setPendingEmailSession(
          email: fallbackEmail,
          displayName: _nameFromEmail(fallbackEmail),
          pendingUsername:
              pendingUsername.isNotEmpty ? pendingUsername : fallbackEmail,
        );
        await _persistSession();
        await _syncObservabilityUser();
        throw AuthEmailConfirmationRequiredException(
          email: fallbackEmail,
          message: backendMessage,
        );
      }
      if (backendCode == 'INVALID_CREDENTIALS') {
        throw StateError('Incorrect email, username, or password.');
      }
      if (backendCode == 'AUTH_FLOW_NOT_ENABLED') {
        throw StateError(
          'Authentication is not configured correctly yet. Please try again later.',
        );
      }
      throw StateError(backendMessage);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Sign-in response shape is invalid.');
    }
    final payloadJson = _asStringDynamicMap(decoded);
    final session = _parseSocialSignInPayload(
      payloadJson,
      fallbackProvider: AuthProviderType.email,
    );
    if (session == null) {
      throw const FormatException('Sign-in response is incomplete.');
    }

    _tokens = session.tokens;
    _currentUser = session.user;
    _lastSocialSignInRequiresSignupCompletion = false;
    await _persistSession();
    await _syncObservabilityUser();
    unawaited(
      AnalyticsService.instance.track(
        AnalyticsEvents.userLoggedIn(loginMethod: AuthProviderType.email.value),
      ),
    );
  }

  Future<http.Response> _postWithAuthResilience({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    final timeoutSeconds = AppApiConfig.requestTimeoutSeconds < 20
        ? 20
        : AppApiConfig.requestTimeoutSeconds;
    const maxAttempts = 2;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _httpClient
            .post(
              uri,
              headers: headers,
              body: body,
            )
            .timeout(Duration(seconds: timeoutSeconds));
      } on TimeoutException {
        if (attempt >= maxAttempts) {
          throw StateError(
            'Connection is slow right now. Please try again in a moment.',
          );
        }
      } on http.ClientException {
        if (attempt >= maxAttempts) {
          throw StateError(
            'Network error. Please check your connection and try again.',
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    throw StateError('Sign-in failed. Please try again.');
  }

  Future<void> registerWithEmail({
    String? name,
    String? givenName,
    String? familyName,
    String? birthdate,
    required String email,
    required String password,
    String? localeCode,
  }) async {
    final safeName = (name ?? '').trim();
    final safeGivenName = (givenName ?? '').trim();
    final safeFamilyName = (familyName ?? '').trim();
    final safeBirthdate = (birthdate ?? '').trim();
    final safeEmail = email.trim().toLowerCase();

    if (safeEmail.isEmpty || password.isEmpty) {
      throw StateError('Please enter email and password.');
    }
    final passwordIssues = PasswordPolicy.validateIssues(password);
    if (passwordIssues.isNotEmpty) {
      throw StateError(passwordIssues.join('\n'));
    }

    await _runBusyTask(() async {
      try {
        final signUp = await _cognito.signUpEmail(
          email: safeEmail,
          password: password,
          name: safeName,
          givenName: safeGivenName,
          familyName: safeFamilyName,
          birthdate: safeBirthdate,
          locale: localeCode,
        );
        if (signUp.userConfirmed) {
          final session = await _cognito.signInWithEmail(
            email: safeEmail,
            password: password,
          );
          if (session.user.emailVerified) {
            _setSession(
              session,
              provider: AuthProviderType.email,
              createdAt: DateTime.now(),
            );
            await _persistSession();
            await _syncObservabilityUser();
            unawaited(
              AnalyticsService.instance.track(
                AnalyticsEvents.userSignedUp(
                  signupMethod: AuthProviderType.email.value,
                ),
              ),
            );
            unawaited(
              AnalyticsService.instance.track(
                AnalyticsEvents.userLoggedIn(
                  loginMethod: AuthProviderType.email.value,
                ),
              ),
            );
            return;
          }
        }

        unawaited(
          AnalyticsService.instance.track(
            AnalyticsEvents.userSignedUp(
              signupMethod: AuthProviderType.email.value,
            ),
          ),
        );
        _setPendingEmailSession(
          email: safeEmail,
          displayName: safeName,
          pendingUsername: signUp.username,
        );
        await _persistSession();
        await _syncObservabilityUser();
        throw AuthEmailConfirmationRequiredException(
          email: safeEmail,
          message:
              'Account created. Verify your email before you can use Mixroom.',
        );
      } on AuthEmailConfirmationRequiredException {
        rethrow;
      } on CognitoApiException catch (e) {
        if (e.code == 'UsernameExistsException') {
          throw StateError('An account with this email already exists.');
        }
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> confirmEmailSignUp({
    required String email,
    required String code,
    String? passwordToSignIn,
  }) async {
    final safeEmail = email.trim().toLowerCase();
    final safeCode = code.trim();
    if (safeEmail.isEmpty || safeCode.isEmpty) {
      throw StateError('Please provide both email and verification code.');
    }

    await _runBusyTask(() async {
      try {
        final session = await _cognito.confirmSignUp(
          username: _resolvePendingEmailUsername(safeEmail),
          code: safeCode,
          password: (passwordToSignIn ?? '').trim(),
        );
        _setSession(
          session,
          provider: AuthProviderType.email,
          createdAt: DateTime.now(),
        );
        await _persistSession();
        await _syncObservabilityUser();
        unawaited(
          AnalyticsService.instance.track(
            AnalyticsEvents.userLoggedIn(
                loginMethod: AuthProviderType.email.value),
          ),
        );
      } on CognitoApiException catch (e) {
        if (e.code == 'INVALID_VERIFICATION_CODE') {
          throw StateError('Invalid or expired verification code.');
        }
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> resendSignUpCode({
    required String email,
    String? localeCode,
  }) async {
    final safeEmail = email.trim().toLowerCase();
    if (safeEmail.isEmpty) {
      throw StateError('Please enter your email address.');
    }

    await _runBusyTask(() async {
      try {
        await _cognito.resendSignUpCode(
          username: _resolvePendingEmailUsername(safeEmail),
          locale: localeCode,
        );
      } on CognitoApiException catch (e) {
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> signInWithGoogle() async {
    if (!CognitoConfig.enableGoogleSignIn) {
      throw StateError('Google sign-in is not enabled in this build.');
    }
    await _signInWithNativeSocial(NativeSocialSignInClient.signInWithGoogle);
  }

  Future<void> signInWithApple() async {
    if (!CognitoConfig.enableAppleSignIn) {
      throw StateError('Apple sign-in is not enabled in this build.');
    }
    await _signInWithNativeSocial(NativeSocialSignInClient.signInWithApple);
  }

  Future<void> signInWithKakao() async {
    if (!CognitoConfig.enableKakaoSignIn) {
      throw StateError('Kakao sign-in is not enabled in this build.');
    }
    await _signInWithNativeSocial(NativeSocialSignInClient.signInWithKakao);
  }

  Future<NativeSocialSignInPayload> beginDeleteAccountSocialReauth() async {
    final user = _currentUser;
    if (user == null) {
      throw StateError('No active account.');
    }

    switch (user.provider) {
      case AuthProviderType.email:
        throw StateError(
          'Enter your current password to delete this account.',
        );
      case AuthProviderType.google:
        if (!CognitoConfig.enableGoogleSignIn) {
          throw StateError('Google sign-in is not enabled in this build.');
        }
        return NativeSocialSignInClient.signInWithGoogle();
      case AuthProviderType.apple:
        if (!CognitoConfig.enableAppleSignIn) {
          throw StateError('Apple sign-in is not enabled in this build.');
        }
        return NativeSocialSignInClient.signInWithApple();
      case AuthProviderType.kakao:
        if (!CognitoConfig.enableKakaoSignIn) {
          throw StateError('Kakao sign-in is not enabled in this build.');
        }
        return NativeSocialSignInClient.signInWithKakao();
    }
  }

  Future<void> _signInWithNativeSocial(
    Future<NativeSocialSignInPayload> Function() beginSignIn,
  ) async {
    if (!AppApiConfig.hasApiBaseUrl) {
      final platformLabel = switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'iOS',
        TargetPlatform.android => 'Android',
        _ => 'this',
      };
      throw StateError(
        'Social sign-in backend is not configured in this $platformLabel build. '
        'Rebuild with APP_API_BASE_URL before testing Google, Apple, or Kakao sign-in.',
      );
    }
    _lastSocialSignInRequiresSignupCompletion = false;
    await _runBusyTask(() async {
      try {
        final payload = await beginSignIn();
        final response = await _httpClient
            .post(
              _subscriptionApiUri('/v1/auth/social/sign-in'),
              headers: <String, String>{
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(payload.body),
            )
            .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final backendDetails = _extractBackendErrorDetails(response.body);
          final backendCode = _extractBackendErrorCode(response.body);
          final backendMessage = _extractBackendError(
                response.body,
                fallback:
                    'Social sign-in failed (${response.statusCode}). Please try again.',
              ) ??
              'Social sign-in failed (${response.statusCode}). Please try again.';
          if (backendCode == 'AUTH_METHOD_CONFLICT') {
            final backendEmail =
                (backendDetails['email'] ?? '').toString().trim().toLowerCase();
            throw AuthSocialAccountConflictException(
              email: backendEmail.isNotEmpty
                  ? backendEmail
                  : (payload.body['email'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase(),
              provider: payload.provider,
              message: backendMessage,
              existingProvider: _extractBackendProvider(
                backendDetails['existing_provider'],
              ),
              existingProviderLabel:
                  (backendDetails['existing_provider_label'] ?? '')
                      .toString()
                      .trim(),
              verificationRequired:
                  backendDetails['verification_required'] == true,
              passwordResetAvailable:
                  backendDetails['password_reset_available'] == true,
              suggestedAction:
                  (backendDetails['suggested_action'] ?? '').toString().trim(),
            );
          }
          throw StateError(backendMessage);
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const FormatException(
              'Social sign-in response shape is invalid.');
        }
        final payloadJson = _asStringDynamicMap(decoded);
        final socialSession = _parseSocialSignInPayload(
          payloadJson,
          fallbackProvider: payload.provider,
        );
        if (socialSession == null) {
          throw const FormatException('Social sign-in response is incomplete.');
        }

        _tokens = socialSession.tokens;
        _currentUser = socialSession.user;
        _lastSocialSignInRequiresSignupCompletion =
            socialSession.requiresSignupCompletion;
        await _persistSession();
        await _syncObservabilityUser();
        unawaited(
          AnalyticsService.instance.track(
            AnalyticsEvents.userLoggedIn(loginMethod: payload.provider.value),
          ),
        );
      } catch (_) {
        rethrow;
      }
    });
  }

  Future<void> requestPasswordReset({
    required String email,
    String? localeCode,
  }) async {
    final safeEmail = email.trim().toLowerCase();
    if (safeEmail.isEmpty) {
      throw StateError('Please enter your email address.');
    }

    await _runBusyTask(() async {
      try {
        await _cognito.requestPasswordReset(
          email: safeEmail,
          locale: localeCode,
        );
      } on CognitoApiException catch (e) {
        if (e.code == 'PASSWORD_RESET_UNAVAILABLE' ||
            _looksLikeSocialPasswordFlowError(e)) {
          throw StateError(
            'Password reset is not available for this account. Try signing in with Google, Apple, or Kakao instead.',
          );
        }
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final safeEmail = email.trim().toLowerCase();
    final safeCode = code.trim();
    if (safeEmail.isEmpty) {
      throw StateError('Please enter your email address.');
    }
    if (safeCode.isEmpty) {
      throw StateError('Please enter the verification code.');
    }
    final passwordIssues = PasswordPolicy.validateIssues(newPassword);
    if (passwordIssues.isNotEmpty) {
      throw StateError(passwordIssues.join('\n'));
    }

    await _runBusyTask(() async {
      try {
        await _cognito.confirmPasswordReset(
          email: safeEmail,
          code: safeCode,
          newPassword: newPassword,
        );
      } on CognitoApiException catch (e) {
        if (e.code == 'INVALID_RESET_CODE') {
          throw StateError('Invalid or expired verification code.');
        }
        if (e.code == 'PASSWORD_RESET_UNAVAILABLE' ||
            _looksLikeSocialPasswordFlowError(e)) {
          throw StateError(
            'Password reset is not available for this account. Try signing in with Google, Apple, or Kakao instead.',
          );
        }
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _currentUser;
    if (user == null) {
      throw StateError('No active account.');
    }
    if (user.provider != AuthProviderType.email) {
      throw StateError(
        'This account uses ${user.provider.label} sign-in. Password login is not available for it yet.',
      );
    }

    final safeCurrentPassword = currentPassword.trim();
    if (safeCurrentPassword.isEmpty) {
      throw StateError('Please enter your current password.');
    }
    final passwordIssues = PasswordPolicy.validateIssues(newPassword);
    if (passwordIssues.isNotEmpty) {
      throw StateError(passwordIssues.join('\n'));
    }

    await _runBusyTask(() async {
      try {
        final accessToken = await _requireAccessToken();
        await _cognito.changePassword(
          accessToken: accessToken,
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
      } on CognitoApiException catch (e) {
        if (e.code == 'NotAuthorizedException') {
          throw StateError('Current password is incorrect.');
        }
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> resendEmailVerification({String? localeCode}) async {
    final user = _currentUser;
    if (user == null) {
      throw StateError('No active account.');
    }
    if (user.provider != AuthProviderType.email) {
      return;
    }
    if (user.emailVerified) {
      return;
    }

    await _runBusyTask(() async {
      try {
        if (_tokens == null) {
          await _cognito.resendSignUpCode(
            username: _resolvePendingEmailUsername(user.email),
            locale: localeCode,
          );
          return;
        }
        final accessToken = await _requireAccessToken();
        await _cognito.resendEmailVerification(
          accessToken: accessToken,
          locale: localeCode,
        );
      } on CognitoApiException catch (e) {
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> updateProfile(AuthUserProfile updated) async {
    await _runBusyTask(() async {
      try {
        final existing = _currentUser;
        if (existing == null) throw StateError('No active account.');
        final accessToken = await _requireAccessToken();
        await _cognito.updateUserAttributes(
          accessToken: accessToken,
          displayName: updated.displayName,
        );

        final refreshed =
            await _cognito.getCurrentUser(accessToken: accessToken);
        _currentUser = _mapUser(
          refreshed,
          provider: existing.provider,
          createdAt: existing.createdAt,
        );
        await _persistSession();
      } on CognitoApiException catch (e) {
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> signOut() async {
    await _runBusyTask(() async {
      final previousUser = _currentUser;
      try {
        final user = _currentUser;
        final tokens = _tokens;
        if (user != null && tokens != null) {
          try {
            await _refreshSessionIfNeeded(
              provider: user.provider,
            );
          } catch (_) {
            // Continue with best-effort sign-out using existing tokens.
          }

          final accessToken = _tokens?.accessToken.trim() ?? '';
          if (accessToken.isNotEmpty) {
            try {
              await _cognito.signOut(accessToken: accessToken);
            } on CognitoApiException {
              // Clear local state even if remote sign-out cannot complete.
            }
          }
        }
      } finally {
        if (previousUser != null) {
          unawaited(
            AnalyticsService.instance.track(AnalyticsEvents.userLoggedOut()),
          );
        }
        if (previousUser != null) {
          await NativeSocialSignInClient.signOut(previousUser.provider);
        }
        await _clearSession();
        await _syncObservabilityUser();
      }
    });
  }

  Future<void> deleteAccount({
    required String confirmationText,
    String? currentPassword,
    NativeSocialSignInPayload? socialReauth,
  }) async {
    await _runBusyTask(() async {
      final previousUser = _currentUser;
      try {
        final accessToken = await _requireAccessToken();
        await _cognito.deleteUser(
          accessToken: accessToken,
          confirmationText: confirmationText.trim(),
          currentPassword: currentPassword,
          socialReauthPayload: socialReauth?.body,
        );
        if (previousUser != null) {
          await NativeSocialSignInClient.signOut(previousUser.provider);
        }
        await _clearSession();
        await _syncObservabilityUser();
      } on CognitoApiException catch (e) {
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> devBypassSignIn() async {
    await _runBusyTask(() async {
      _currentUser = _debugUser;
      _tokens = null;
      _lastSocialSignInRequiresSignupCompletion = false;

      await SensitiveStorage.instance.write(
        _prefsSessionKey,
        jsonEncode({
          'user': _currentUser!.toJson(),
        }),
      );
      await _syncObservabilityUser();
    });
  }

  Future<void> _persistSession() async {
    final user = _currentUser;
    final tokens = _tokens;
    if (user == null) return;

    final payload = <String, dynamic>{
      'user': user.toJson(),
    };
    if (tokens != null) {
      payload['tokens'] = tokens.toJson();
    }
    final pendingEmailUsername = _pendingEmailUsername?.trim() ?? '';
    if (pendingEmailUsername.isNotEmpty) {
      payload['pendingEmailUsername'] = pendingEmailUsername;
    }

    await SensitiveStorage.instance.write(
      _prefsSessionKey,
      jsonEncode(payload),
    );
    notifyListeners();
  }

  Uri _subscriptionApiUri(String path) {
    final base = AppApiConfig.apiBaseUrl.trim();
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  String? _extractBackendError(
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

  String? _extractBackendErrorCode(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map) {
        final code = decoded['code']?.toString().trim() ?? '';
        if (code.isNotEmpty) return code;
      }
    } catch (_) {
      // Ignore parse failures and use generic handling.
    }
    return null;
  }

  Map<String, dynamic> _extractBackendErrorDetails(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map) {
        return _asStringDynamicMap(decoded['details']);
      }
    } catch (_) {
      // Ignore parse failures and use generic handling.
    }
    return <String, dynamic>{};
  }

  AuthProviderType? _extractBackendProvider(Object? rawValue) {
    final value = rawValue?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    switch (value) {
      case 'email':
        return AuthProviderType.email;
      case 'google':
        return AuthProviderType.google;
      case 'apple':
        return AuthProviderType.apple;
      case 'kakao':
        return AuthProviderType.kakao;
      default:
        return null;
    }
  }

  Future<void> _runBusyTask(Future<void> Function() action) async {
    _isBusy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  String _nameFromEmail(String email) {
    final left = email.split('@').first.trim();
    if (left.isEmpty) return 'Mixroom User';
    final spaced = left
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (spaced.isEmpty) return 'Mixroom User';
    return spaced
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ')
        .trim();
  }

  Future<void> _clearSession() async {
    _currentUser = null;
    _tokens = null;
    _pendingEmailUsername = null;
    _lastSocialSignInRequiresSignupCompletion = false;
    await SensitiveStorage.instance.delete(_prefsSessionKey);
  }

  Future<String> _requireAccessToken() async {
    final tokens = _tokens;
    final user = _sessionUserOrNull();
    if (tokens == null || user == null) {
      throw StateError('No active account.');
    }
    final fallbackAccessToken = tokens.accessToken.trim();
    final canUseFallbackToken =
        fallbackAccessToken.isNotEmpty && _hasUsableAccessTokens(tokens);

    try {
      await _refreshSessionIfNeeded(provider: user.provider);
    } catch (_) {
      if (canUseFallbackToken) {
        return fallbackAccessToken;
      }
      rethrow;
    }

    final accessToken = _tokens?.accessToken ?? '';
    if (accessToken.isEmpty) {
      throw StateError('Session expired. Please sign in again.');
    }
    return accessToken;
  }

  Future<CognitoSession?> _refreshSessionIfNeeded({
    required AuthProviderType provider,
    bool forceRefresh = false,
  }) async {
    final tokens = _tokens;
    final user = _sessionUserOrNull();
    if (tokens == null || user == null) return null;
    final requiresNativeUpgrade = _needsNativeSessionUpgrade(tokens);
    final accessTokensExpired = !_hasUsableAccessTokens(tokens);
    if (!forceRefresh &&
        !requiresNativeUpgrade &&
        !tokens.isExpiringSoon &&
        !accessTokensExpired) {
      return null;
    }
    if (tokens.refreshToken.trim().isEmpty) {
      throw StateError('Session expired. Please sign in again.');
    }

    final inFlight = _sessionRefreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final expectedUserId = user.userId;
    final expectedRefreshToken = tokens.refreshToken;
    final expectedCreatedAt = user.createdAt;
    final refreshFuture = _performSessionRefresh(
      provider: provider,
      expectedUserId: expectedUserId,
      expectedRefreshToken: expectedRefreshToken,
      expectedCreatedAt: expectedCreatedAt,
      fallbackIdToken: tokens.idToken,
    );
    _sessionRefreshInFlight = refreshFuture;
    try {
      return await refreshFuture;
    } finally {
      if (identical(_sessionRefreshInFlight, refreshFuture)) {
        _sessionRefreshInFlight = null;
      }
    }
  }

  Future<CognitoSession?> _performSessionRefresh({
    required AuthProviderType provider,
    required String expectedUserId,
    required String expectedRefreshToken,
    required DateTime expectedCreatedAt,
    required String fallbackIdToken,
  }) async {
    final refreshed = await _cognito.refreshSession(
      refreshToken: expectedRefreshToken,
      fallbackIdToken: fallbackIdToken,
    );

    final currentUser = _currentUser;
    final currentTokens = _tokens;
    if (currentUser == null || currentTokens == null) {
      return null;
    }
    final stillRefreshingSameSession = currentUser.userId == expectedUserId &&
        currentTokens.refreshToken == expectedRefreshToken;
    if (!stillRefreshingSameSession) {
      return null;
    }

    _setSession(
      refreshed,
      provider: provider,
      createdAt: expectedCreatedAt,
    );
    await _persistSession();
    return refreshed;
  }

  void _setSession(
    CognitoSession session, {
    required AuthProviderType provider,
    required DateTime createdAt,
  }) {
    _pendingEmailUsername = null;
    _lastSocialSignInRequiresSignupCompletion = false;
    _tokens = session.tokens;
    _currentUser = _mapUser(
      session.user,
      provider: provider,
      createdAt: createdAt,
    );
  }

  void _setPendingEmailSession({
    required String email,
    required String displayName,
    required String pendingUsername,
  }) {
    _tokens = null;
    _lastSocialSignInRequiresSignupCompletion = false;
    _pendingEmailUsername = pendingUsername.trim().isEmpty
        ? email.trim().toLowerCase()
        : pendingUsername.trim();
    _currentUser = AuthUserProfile(
      userId:
          _currentUser?.userId ?? 'pending-email:${email.trim().toLowerCase()}',
      email: email.trim().toLowerCase(),
      displayName: displayName.trim().isEmpty
          ? _nameFromEmail(email)
          : displayName.trim(),
      provider: AuthProviderType.email,
      emailVerified: false,
      createdAt: _currentUser?.createdAt ?? DateTime.now(),
    );
  }

  String _resolvePendingEmailUsername(String email) {
    final safeEmail = email.trim().toLowerCase();
    final currentUserEmail = _currentUser?.email.trim().toLowerCase() ?? '';
    if (currentUserEmail == safeEmail) {
      final pending = _pendingEmailUsername?.trim() ?? '';
      if (pending.isNotEmpty) return pending;
    }
    return safeEmail;
  }

  Future<void> _syncObservabilityUser() async {
    final user = _currentUser;
    if (user == null) {
      await AnalyticsService.instance.resetUser();
      await CrashReportingService.instance.clearUser();
      return;
    }

    AnalyticsService.instance.setSubscriptionTier(null);
    AnalyticsService.instance.setMusicProfile(null);
    await AnalyticsService.instance.identifyUser(
      userId: user.userId,
      email: user.email,
      name: user.displayName,
    );
    await CrashReportingService.instance.setUser(
      id: user.userId,
      email: user.email,
      username: user.displayName,
    );
  }

  AuthUserProfile _mapUser(
    CognitoUserAttributes user, {
    required AuthProviderType provider,
    required DateTime createdAt,
  }) {
    final safeEmail = user.email.trim().toLowerCase();
    return AuthUserProfile(
      userId: user.sub.trim().isEmpty ? 'unknown-user' : user.sub.trim(),
      email: safeEmail,
      displayName: (user.name ?? '').trim().isEmpty
          ? _nameFromEmail(safeEmail)
          : user.name!.trim(),
      provider: provider,
      emailVerified: user.emailVerified || provider != AuthProviderType.email,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> _asStringDynamicMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key.toString(), val),
      );
    }
    return <String, dynamic>{};
  }

  String _friendlyErrorMessage(CognitoApiException error) {
    switch (error.code) {
      case 'UserNotFoundException':
      case 'NotAuthorizedException':
      case 'INVALID_CREDENTIALS':
        return 'Incorrect email or password.';
      case 'UserNotConfirmedException':
      case 'EMAIL_CONFIRMATION_REQUIRED':
        return 'Please verify your email first.';
      case 'ACCOUNT_ALREADY_VERIFIED':
        return 'This email is already verified. Sign in instead.';
      case 'DELETE_CONFIRMATION_REQUIRED':
        return 'Type DELETE to confirm account deletion.';
      case 'DELETE_PASSWORD_REQUIRED':
        return 'Enter your current password to delete this account.';
      case 'SOCIAL_REAUTH_REQUIRED':
        return 'Re-authenticate with your social provider to delete this account.';
      case 'SOCIAL_REAUTH_MISMATCH':
        return 'That re-authentication did not match your Mixroom account. Please try again.';
      case 'EMAIL_DELIVERY_UNAVAILABLE':
        return 'Email delivery is not configured yet. Please try again later.';
      case 'EMAIL_SUPPRESSED':
        return 'That email address cannot receive verification emails right now. Try another email or contact support.';
      case 'PASSWORD_RESET_UNAVAILABLE':
        return 'Password reset is not available for this account.';
      case 'INVALID_VERIFICATION_CODE':
      case 'INVALID_RESET_CODE':
        return 'Invalid or expired verification code.';
      case 'SESSION_INVALID':
      case 'SESSION_EXPIRED':
        return 'Session expired. Please sign in again.';
      case 'LimitExceededException':
      case 'TooManyRequestsException':
        return 'Too many attempts. Please try again shortly.';
      case 'UnsupportedPlatform':
        return 'Social sign-in is only supported on iOS and Android.';
      case 'UserCancelledException':
        return 'Social sign-in was cancelled.';
      case 'AuthorizationFailed':
        return 'Social sign-in did not complete. Please try again.';
      case 'NetworkError':
        return 'Network error. Please check your connection and try again.';
      default:
        final msg = error.message.trim();
        if (msg.isEmpty) return 'Authentication failed. Please try again.';
        return msg;
    }
  }

  bool _looksLikeSocialPasswordFlowError(CognitoApiException error) {
    if (error.code != 'InvalidParameterException' &&
        error.code != 'NotAuthorizedException') {
      return false;
    }
    final message = error.message.toLowerCase();
    return message.contains('cannot reset password') ||
        message.contains('password reset is not supported') ||
        message.contains('no registered/verified email') ||
        message.contains('external provider') ||
        message.contains('federated');
  }

  AuthUserProfile get _debugUser {
    return AuthUserProfile(
      userId: 'debug-user',
      email: 'dev+test@mixroom.app',
      displayName: 'Dev Test User',
      provider: AuthProviderType.email,
      emailVerified: false,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  @visibleForTesting
  void debugPrimeSession({
    AuthUserProfile? user,
    CognitoTokens? tokens,
    String? pendingEmailUsername,
  }) {
    _currentUser = user;
    _tokens = tokens;
    _pendingEmailUsername = pendingEmailUsername;
    _isInitializing = false;
    notifyListeners();
  }

  bool _hasAppAccess({
    required AuthUserProfile? user,
    required CognitoTokens? tokens,
  }) {
    if (!_hasSessionUserAccess(user)) {
      return false;
    }
    if (user!.userId == _debugUser.userId) {
      return true;
    }
    if (!_hasRecoverableSessionTokens(tokens)) {
      return false;
    }
    return true;
  }

  bool _hasUsableSessionTokens(CognitoTokens? tokens) {
    if (tokens == null) return false;
    return tokens.accessToken.trim().isNotEmpty &&
        tokens.idToken.trim().isNotEmpty &&
        tokens.expiresAtUtc.isAfter(DateTime.now().toUtc());
  }

  bool _hasRecoverableSessionTokens(CognitoTokens? tokens) {
    if (tokens == null) return false;
    final hasAccessPayload = tokens.accessToken.trim().isNotEmpty;
    final hasIdPayload = tokens.idToken.trim().isNotEmpty;
    if (!hasAccessPayload || !hasIdPayload) {
      return false;
    }
    return _hasUsableAccessTokens(tokens) ||
        tokens.refreshToken.trim().isNotEmpty;
  }

  bool _hasUsableAccessTokens(CognitoTokens? tokens) {
    if (tokens == null) return false;
    return tokens.expiresAtUtc.isAfter(DateTime.now().toUtc());
  }

  bool _needsNativeSessionUpgrade(CognitoTokens tokens) {
    return !_isNativeRefreshToken(tokens.refreshToken);
  }

  bool _isNativeRefreshToken(String value) {
    return value.trim().startsWith('rt_');
  }

  bool _looksLikeEmail(String value) {
    final safe = value.trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(safe);
  }

  String _normalizeLoginIdentifier(String value) {
    final safe = value.trim();
    if (_looksLikeEmail(safe)) {
      return safe.toLowerCase();
    }
    return safe.startsWith('@') ? safe.substring(1).trim() : safe;
  }

  bool _isUnauthorizedResponse(http.Response response) {
    return response.statusCode == 401;
  }

  Future<List<String>> _collectAuthTokenCandidates({
    bool forceRefresh = false,
  }) async {
    final user = _sessionUserOrNull();
    final existingTokens = _tokens;
    if (user == null || existingTokens == null) {
      return const <String>[];
    }

    var activeTokens = existingTokens;
    try {
      await _refreshSessionIfNeeded(
        provider: user.provider,
        forceRefresh: forceRefresh,
      );
      activeTokens = _tokens ?? existingTokens;
    } catch (_) {
      if (forceRefresh) {
        return _tokenCandidates(existingTokens);
      }
    }

    return _tokenCandidates(activeTokens);
  }

  List<String> _tokenCandidates(CognitoTokens tokens) {
    if (!_hasUsableAccessTokens(tokens)) {
      return const <String>[];
    }
    final idToken = tokens.idToken.trim();
    final accessToken = tokens.accessToken.trim();
    final candidates = <String>[];
    if (accessToken.isNotEmpty) {
      candidates.add(accessToken);
    }
    if (idToken.isNotEmpty && idToken != accessToken) {
      candidates.add(idToken);
    }
    return candidates;
  }

  Future<Never> _expireSessionAndThrow() async {
    await _clearSession();
    await _syncObservabilityUser();
    notifyListeners();
    throw StateError('Session expired. Please sign in again.');
  }

  AuthUserProfile? _sessionUserOrNull() {
    final user = _currentUser;
    if (!_hasSessionUserAccess(user)) {
      return null;
    }
    return user;
  }

  bool _hasSessionUserAccess(AuthUserProfile? user) {
    if (user == null) {
      return false;
    }
    if (user.userId == _debugUser.userId) {
      return true;
    }
    if (user.provider == AuthProviderType.email && !user.emailVerified) {
      return false;
    }
    return true;
  }

  _ParsedSocialSignInPayload? _parseSocialSignInPayload(
    Map<String, dynamic> payload, {
    required AuthProviderType fallbackProvider,
  }) {
    final nestedTokens = _asStringDynamicMap(payload['tokens']);
    final nestedUser = _asStringDynamicMap(payload['user']);
    final tokensJson = nestedTokens.isNotEmpty ? nestedTokens : payload;
    final userJson = nestedUser.isNotEmpty ? nestedUser : payload;

    final tokens = CognitoTokens.fromJson(tokensJson);
    final user = AuthUserProfile.fromJson(userJson);
    if (!_hasUsableSessionTokens(tokens)) {
      return null;
    }

    final resolvedProvider = user.provider == AuthProviderType.email
        ? fallbackProvider
        : user.provider;
    final safeEmail = user.email.trim().toLowerCase();
    final resolvedName = user.displayName.trim().isEmpty
        ? _nameFromEmail(safeEmail)
        : user.displayName.trim();
    final normalizedUser = user.copyWith(
      email: safeEmail,
      displayName: resolvedName,
      provider: resolvedProvider,
      emailVerified:
          user.emailVerified || resolvedProvider != AuthProviderType.email,
      createdAt: user.createdAt.toUtc(),
    );
    final requiresSignupCompletion =
        payload['requiresSignupCompletion'] == true ||
            payload['requires_signup_completion'] == true;
    return _ParsedSocialSignInPayload(
      tokens: tokens,
      user: normalizedUser,
      requiresSignupCompletion: requiresSignupCompletion,
    );
  }
}

class AuthEmailConfirmationRequiredException implements Exception {
  const AuthEmailConfirmationRequiredException({
    required this.email,
    required this.message,
  });

  final String email;
  final String message;

  @override
  String toString() => message;
}

class AuthSocialAccountConflictException implements Exception {
  const AuthSocialAccountConflictException({
    required this.email,
    required this.provider,
    required this.message,
    this.existingProvider,
    this.existingProviderLabel,
    this.verificationRequired = false,
    this.passwordResetAvailable = false,
    this.suggestedAction = '',
  });

  final String email;
  final AuthProviderType provider;
  final String message;
  final AuthProviderType? existingProvider;
  final String? existingProviderLabel;
  final bool verificationRequired;
  final bool passwordResetAvailable;
  final String suggestedAction;

  @override
  String toString() => message;
}

class _ParsedSocialSignInPayload {
  const _ParsedSocialSignInPayload({
    required this.tokens,
    required this.user,
    required this.requiresSignupCompletion,
  });

  final CognitoTokens tokens;
  final AuthUserProfile user;
  final bool requiresSignupCompletion;
}
