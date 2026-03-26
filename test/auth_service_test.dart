import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/cognito_auth_client.dart';
import 'package:mixroom/models/auth_user_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService session gating', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('keeps pending unverified email accounts out of the app', () {
      final auth = AuthService(restoreSessionOnInit: false);
      final user = AuthUserProfile(
        userId: 'pending-user',
        email: 'pending@example.com',
        displayName: 'Pending User',
        provider: AuthProviderType.email,
        emailVerified: false,
        createdAt: DateTime.utc(2026, 3, 13),
      );

      auth.debugPrimeSession(user: user);

      expect(auth.currentUser, isNotNull);
      expect(auth.hasPendingEmailVerification, isTrue);
      expect(auth.isSignedIn, isFalse);
      expect(auth.signedInUser, isNull);
    });

    test('allows verified email accounts with usable tokens into the app', () {
      final auth = AuthService(restoreSessionOnInit: false);
      final user = AuthUserProfile(
        userId: 'verified-user',
        email: 'verified@example.com',
        displayName: 'Verified User',
        provider: AuthProviderType.email,
        emailVerified: true,
        createdAt: DateTime.utc(2026, 3, 13),
      );
      final tokens = CognitoTokens(
        accessToken: 'access-token',
        idToken: 'id-token',
        refreshToken: 'refresh-token',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      auth.debugPrimeSession(user: user, tokens: tokens);

      expect(auth.hasPendingEmailVerification, isFalse);
      expect(auth.isSignedIn, isTrue);
      expect(auth.signedInUser?.userId, 'verified-user');
    });

    test('allows native social sessions into the app with valid tokens', () {
      final auth = AuthService(restoreSessionOnInit: false);
      final user = AuthUserProfile(
        userId: 'google-user',
        email: 'google@example.com',
        displayName: 'Google User',
        provider: AuthProviderType.google,
        emailVerified: false,
        createdAt: DateTime.utc(2026, 3, 13),
      );
      final tokens = CognitoTokens(
        accessToken: 'access-token',
        idToken: 'id-token',
        refreshToken: 'refresh-token',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      auth.debugPrimeSession(user: user, tokens: tokens);

      expect(auth.isSignedIn, isTrue);
      expect(auth.signedInUser?.provider, AuthProviderType.google);
    });

    test('restores legacy cognito session by upgrading it to a native session',
        () async {
      final fakeClient = _FakeCognitoAuthClient(
        refreshedSession: _session(
          userId: 'legacy-user',
          email: 'legacy@example.com',
          provider: AuthProviderType.email,
          refreshToken: 'rt_session-upgraded_secret',
        ),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mixroom.auth.session.v2': jsonEncode(<String, dynamic>{
          'user': _userJson(
            userId: 'legacy-user',
            email: 'legacy@example.com',
            provider: 'email',
            emailVerified: true,
          ),
          'tokens': <String, dynamic>{
            'accessToken': 'legacy-access',
            'idToken': 'legacy-id',
            'refreshToken': 'legacy-refresh',
            'expiresAtUtc': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        }),
      });

      final auth = AuthService(
        cognitoClient: fakeClient,
        restoreSessionOnInit: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeClient.refreshCallCount, 1);
      expect(auth.isSignedIn, isTrue);
      expect(auth.signedInUser?.userId, 'legacy-user');
      expect(await auth.getIdTokenOrNull(), 'id-token-legacy-user');
    });

    test('clears stale legacy cognito session when upgrade fails', () async {
      final fakeClient = _FakeCognitoAuthClient(
        refreshError: const CognitoApiException(
          code: 'NotAuthorizedException',
          message: 'Session expired.',
        ),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mixroom.auth.session.v2': jsonEncode(<String, dynamic>{
          'user': _userJson(
            userId: 'legacy-user',
            email: 'legacy@example.com',
            provider: 'email',
            emailVerified: true,
          ),
          'tokens': <String, dynamic>{
            'accessToken': 'legacy-access',
            'idToken': 'legacy-id',
            'refreshToken': 'legacy-refresh',
            'expiresAtUtc': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        }),
      });

      final auth = AuthService(
        cognitoClient: fakeClient,
        restoreSessionOnInit: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeClient.refreshCallCount, 1);
      expect(auth.isSignedIn, isFalse);
      expect(auth.currentUser, isNull);
      expect(await auth.getIdTokenOrNull(), isNull);
    });

    test('keeps using a still-valid cached id token when refresh throws',
        () async {
      final fakeClient = _FakeCognitoAuthClient(
        refreshError: const CognitoApiException(
          code: 'ServiceUnavailableException',
          message: 'Temporary refresh failure.',
        ),
      );
      final auth = AuthService(
        cognitoClient: fakeClient,
        restoreSessionOnInit: false,
      );
      final user = AuthUserProfile(
        userId: 'google-user',
        email: 'google@example.com',
        displayName: 'Google User',
        provider: AuthProviderType.google,
        emailVerified: true,
        createdAt: DateTime.utc(2026, 3, 13),
      );
      final tokens = CognitoTokens(
        accessToken: 'access-token',
        idToken: 'cached-id-token',
        refreshToken: 'rt_valid_refresh_secret',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );

      auth.debugPrimeSession(user: user, tokens: tokens);

      expect(await auth.getIdTokenOrNull(), 'cached-id-token');
      expect(fakeClient.refreshCallCount, 1);
      expect(auth.isSignedIn, isTrue);
    });

    test('keeps a refreshable session signed in after access tokens expire',
        () async {
      final fakeClient = _FakeCognitoAuthClient(
        refreshedSession: _session(
          userId: 'google-user',
          email: 'google@example.com',
          provider: AuthProviderType.google,
          refreshToken: 'rt_stable_refresh_secret',
        ),
      );
      final auth = AuthService(
        cognitoClient: fakeClient,
        restoreSessionOnInit: false,
      );
      final user = AuthUserProfile(
        userId: 'google-user',
        email: 'google@example.com',
        displayName: 'Google User',
        provider: AuthProviderType.google,
        emailVerified: true,
        createdAt: DateTime.utc(2026, 3, 13),
      );
      final expiredTokens = CognitoTokens(
        accessToken: 'expired-access-token',
        idToken: 'expired-id-token',
        refreshToken: 'rt_stable_refresh_secret',
        expiresAtUtc:
            DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );

      auth.debugPrimeSession(user: user, tokens: expiredTokens);

      expect(auth.isSignedIn, isTrue);
      expect(await auth.getIdTokenOrNull(), 'id-token-google-user');
      expect(fakeClient.refreshCallCount, 1);
      expect(auth.signedInUser?.userId, 'google-user');
    });

    test('retries authenticated requests once after a 401 response', () async {
      final fakeClient = _FakeCognitoAuthClient(
        refreshedSession: _session(
          userId: 'google-user',
          email: 'google@example.com',
          provider: AuthProviderType.google,
          refreshToken: 'rt_refreshed_secret',
        ),
      );
      final auth = AuthService(
        cognitoClient: fakeClient,
        restoreSessionOnInit: false,
      );
      final user = AuthUserProfile(
        userId: 'google-user',
        email: 'google@example.com',
        displayName: 'Google User',
        provider: AuthProviderType.google,
        emailVerified: true,
        createdAt: DateTime.utc(2026, 3, 13),
      );
      final tokens = CognitoTokens(
        accessToken: 'access-token',
        idToken: 'cached-id-token',
        refreshToken: 'rt_valid_refresh_secret',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      auth.debugPrimeSession(user: user, tokens: tokens);

      final seenTokens = <String>[];
      final response = await auth.authorizedRequest((token) async {
        seenTokens.add(token);
        if (token == 'cached-id-token') {
          return http.Response('unauthorized', 401);
        }
        return http.Response('ok', 200);
      });

      expect(response.statusCode, 200);
      expect(seenTokens, <String>['cached-id-token', 'access-token']);
      expect(fakeClient.refreshCallCount, 0);
    });

    test('shares one refresh request across concurrent authenticated calls',
        () async {
      final fakeClient = _FakeCognitoAuthClient(
        refreshedSession: _session(
          userId: 'google-user',
          email: 'google@example.com',
          provider: AuthProviderType.google,
          refreshToken: 'rt_shared_refresh_secret',
        ),
        refreshDelay: const Duration(milliseconds: 15),
      );
      final auth = AuthService(
        cognitoClient: fakeClient,
        restoreSessionOnInit: false,
      );
      final user = AuthUserProfile(
        userId: 'google-user',
        email: 'google@example.com',
        displayName: 'Google User',
        provider: AuthProviderType.google,
        emailVerified: true,
        createdAt: DateTime.utc(2026, 3, 13),
      );
      final expiringTokens = CognitoTokens(
        accessToken: 'soon-expiring-access-token',
        idToken: 'soon-expiring-id-token',
        refreshToken: 'rt_shared_refresh_secret',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(seconds: 30)),
      );

      auth.debugPrimeSession(user: user, tokens: expiringTokens);

      final seenTokens = <String>[];
      final responses = await Future.wait(<Future<http.Response>>[
        auth.authorizedRequest((token) async {
          seenTokens.add(token);
          return http.Response('ok', 200);
        }),
        auth.authorizedRequest((token) async {
          seenTokens.add(token);
          return http.Response('ok', 200);
        }),
      ]);

      expect(responses.every((response) => response.statusCode == 200), isTrue);
      expect(fakeClient.refreshCallCount, 1);
      expect(
          seenTokens, <String>['id-token-google-user', 'id-token-google-user']);
    });
  });

  group('Auth payload parsing', () {
    test('AuthUserProfile accepts snake_case payloads', () {
      final profile = AuthUserProfile.fromJson(<String, dynamic>{
        'user_id': 'user-123',
        'email': 'User@Example.com',
        'display_name': 'Snake Case User',
        'auth_provider': 'kakao',
        'email_verified': true,
        'created_at': '2026-03-13T12:00:00Z',
      });

      expect(profile.userId, 'user-123');
      expect(profile.email, 'user@example.com');
      expect(profile.displayName, 'Snake Case User');
      expect(profile.provider, AuthProviderType.kakao);
      expect(profile.emailVerified, isTrue);
    });

    test('CognitoTokens accepts snake_case payloads', () {
      final tokens = CognitoTokens.fromJson(<String, dynamic>{
        'access_token': 'access-token',
        'id_token': 'id-token',
        'refresh_token': 'refresh-token',
        'expires_in': 1800,
      });

      expect(tokens.accessToken, 'access-token');
      expect(tokens.idToken, 'id-token');
      expect(tokens.refreshToken, 'refresh-token');
      expect(tokens.expiresAtUtc.isAfter(DateTime.now().toUtc()), isTrue);
    });
  });
}

class _FakeCognitoAuthClient extends CognitoAuthClient {
  _FakeCognitoAuthClient({
    this.refreshedSession,
    this.refreshError,
    this.refreshDelay = Duration.zero,
  });

  final CognitoSession? refreshedSession;
  final CognitoApiException? refreshError;
  final Duration refreshDelay;
  int refreshCallCount = 0;

  @override
  Future<CognitoSession> refreshSession({
    required String refreshToken,
    required String fallbackIdToken,
  }) async {
    refreshCallCount += 1;
    if (refreshDelay > Duration.zero) {
      await Future<void>.delayed(refreshDelay);
    }
    if (refreshError != null) {
      throw refreshError!;
    }
    return refreshedSession!;
  }
}

CognitoSession _session({
  required String userId,
  required String email,
  required AuthProviderType provider,
  required String refreshToken,
}) {
  return CognitoSession(
    tokens: CognitoTokens(
      accessToken: 'access-token-$userId',
      idToken: 'id-token-$userId',
      refreshToken: refreshToken,
      expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ),
    user: CognitoUserAttributes(
      sub: userId,
      email: email,
      emailVerified: true,
      name: 'Legacy User',
    ),
  );
}

Map<String, dynamic> _userJson({
  required String userId,
  required String email,
  required String provider,
  required bool emailVerified,
}) {
  return <String, dynamic>{
    'userId': userId,
    'email': email,
    'displayName': 'Legacy User',
    'provider': provider,
    'emailVerified': emailVerified,
    'createdAt': DateTime.utc(2026, 3, 13).toIso8601String(),
  };
}
