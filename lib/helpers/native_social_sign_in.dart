import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:mixroom/config/native_social_auth_config.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class NativeSocialSignInPayload {
  const NativeSocialSignInPayload({
    required this.provider,
    required this.body,
  });

  final AuthProviderType provider;
  final Map<String, dynamic> body;
}

class NativeSocialSignInClient {
  NativeSocialSignInClient._();

  static const FlutterAppAuth _appAuth = FlutterAppAuth();
  static bool _googleInitialized = false;
  static bool _kakaoInitialized = false;
  static const MethodChannel _macosNativeSocialChannel =
      MethodChannel('mixroom/native_social');

  static Future<NativeSocialSignInPayload> signInWithGoogle() async {
    if (!NativeSocialAuthConfig.hasGoogleServerClientId) {
      throw const _NativeSocialSignInException(
        'Google sign-in is not configured in this build.',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _signInWithGoogleMacOS();
    }
    await _ensureGoogleInitialized();

    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken?.trim() ?? '';
      if (idToken.isEmpty) {
        throw const _NativeSocialSignInException(
          'Google sign-in did not return an ID token.',
        );
      }

      return NativeSocialSignInPayload(
        provider: AuthProviderType.google,
        body: <String, dynamic>{
          'provider': AuthProviderType.google.value,
          'id_token': idToken,
          'email': account.email,
          'display_name': (account.displayName ?? '').trim(),
        },
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const _NativeSocialSignInException(
            'Social sign-in was cancelled.');
      }
      throw _NativeSocialSignInException(
        e.description?.trim().isNotEmpty == true
            ? e.description!.trim()
            : 'Google sign-in could not be completed.',
      );
    } on PlatformException catch (e) {
      if (defaultTargetPlatform != TargetPlatform.macOS) {
        rethrow;
      }
      throw _NativeSocialSignInException(
        _friendlyGooglePlatformErrorMessage(e),
      );
    }
  }

  static Future<NativeSocialSignInPayload> signInWithApple() async {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      throw const _NativeSocialSignInException(
        'Apple sign-in is only supported on Apple platforms in this build.',
      );
    }

    try {
      final nonce = generateNonce();
      final state = generateNonce(length: 16);
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
        state: state,
      );
      if ((credential.state ?? '').trim() != state) {
        throw const _NativeSocialSignInException(
          'Apple sign-in state validation failed. Please try again.',
        );
      }
      final identityToken = credential.identityToken?.trim() ?? '';
      if (identityToken.isEmpty) {
        throw const _NativeSocialSignInException(
          'Apple sign-in did not return an identity token.',
        );
      }

      final displayName = <String>[
        (credential.givenName ?? '').trim(),
        (credential.familyName ?? '').trim(),
      ].where((value) => value.isNotEmpty).join(' ');

      return NativeSocialSignInPayload(
        provider: AuthProviderType.apple,
        body: <String, dynamic>{
          'provider': AuthProviderType.apple.value,
          'id_token': identityToken,
          'nonce': nonce,
          'email': (credential.email ?? '').trim().toLowerCase(),
          'display_name': displayName,
        },
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const _NativeSocialSignInException(
            'Social sign-in was cancelled.');
      }
      throw _NativeSocialSignInException(
        e.message.trim().isEmpty
            ? 'Apple sign-in could not be completed.'
            : e.message.trim(),
      );
    }
  }

  static Future<NativeSocialSignInPayload> signInWithKakao() async {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _signInWithKakaoMacOS();
    }
    await _ensureKakaoInitialized();

    try {
      var token = await _startKakaoSignIn();
      var user = await UserApi.instance.me();
      var kakaoAccount = user.kakaoAccount;
      if (((kakaoAccount?.email ?? '').trim().isEmpty ||
              !(kakaoAccount?.isEmailVerified ?? false)) &&
          kakaoAccount?.emailNeedsAgreement == true) {
        token = await UserApi.instance.loginWithNewScopes(
          const <String>['account_email'],
        );
        user = await UserApi.instance.me();
        kakaoAccount = user.kakaoAccount;
      }
      final profile = kakaoAccount?.profile;

      return NativeSocialSignInPayload(
        provider: AuthProviderType.kakao,
        body: <String, dynamic>{
          'provider': AuthProviderType.kakao.value,
          'access_token': token.accessToken,
          'email': (kakaoAccount?.email ?? '').trim().toLowerCase(),
          'display_name': (profile?.nickname ?? '').trim(),
        },
      );
    } catch (e) {
      final message = _extractKakaoErrorMessage(e);
      if (_isKakaoCancelledError(e, message)) {
        throw const _NativeSocialSignInException(
            'Social sign-in was cancelled.');
      }
      throw _NativeSocialSignInException(
        _friendlyKakaoErrorMessage(e, rawMessage: message),
      );
    }
  }

  static Future<void> signOut(AuthProviderType provider) async {
    try {
      switch (provider) {
        case AuthProviderType.google:
          if (defaultTargetPlatform == TargetPlatform.macOS) {
            return;
          }
          await _ensureGoogleInitialized();
          await GoogleSignIn.instance.signOut();
          return;
        case AuthProviderType.kakao:
          if (_kakaoInitialized) {
            await UserApi.instance.logout();
          }
          return;
        case AuthProviderType.apple:
        case AuthProviderType.email:
          return;
      }
    } catch (_) {
      // Provider sign-out is best-effort; local session cleanup still happens.
    }
  }

  static Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: NativeSocialAuthConfig.hasGoogleClientId
          ? NativeSocialAuthConfig.effectiveGoogleClientId
          : null,
      serverClientId: NativeSocialAuthConfig.hasGoogleServerClientId
          ? NativeSocialAuthConfig.effectiveGoogleServerClientId
          : null,
    );
    _googleInitialized = true;
  }

  static Future<NativeSocialSignInPayload> _signInWithGoogleMacOS() async {
    if (!NativeSocialAuthConfig.hasGoogleClientId) {
      throw const _NativeSocialSignInException(
        'Google sign-in is not configured in this desktop build.',
      );
    }

    final clientId = NativeSocialAuthConfig.effectiveGoogleClientId;
    final redirectScheme = _googleRedirectScheme(clientId);
    final redirectUri = '$redirectScheme:/oauth2redirect';

    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirectUri,
          issuer: 'https://accounts.google.com',
          scopes: const <String>['openid', 'email', 'profile'],
          promptValues: const <String>['select_account'],
        ),
      );

      final idToken = result.idToken?.trim() ?? '';
      if (idToken.isEmpty) {
        throw const _NativeSocialSignInException(
          'Google sign-in did not return an ID token.',
        );
      }

      final claims = _decodeJwtPayload(idToken);
      return NativeSocialSignInPayload(
        provider: AuthProviderType.google,
        body: <String, dynamic>{
          'provider': AuthProviderType.google.value,
          'id_token': idToken,
          'email': (claims['email'] ?? '').toString().trim().toLowerCase(),
          'display_name': (claims['name'] ?? '').toString().trim(),
        },
      );
    } on FlutterAppAuthUserCancelledException {
      throw const _NativeSocialSignInException('Social sign-in was cancelled.');
    } on FlutterAppAuthPlatformException catch (e) {
      throw _NativeSocialSignInException(
        _friendlyGoogleAppAuthErrorMessage(e),
      );
    } on PlatformException catch (e) {
      throw _NativeSocialSignInException(
        _friendlyGooglePlatformErrorMessage(e),
      );
    }
  }

  static String _googleRedirectScheme(String clientId) {
    final trimmed = clientId.trim();
    if (!trimmed.endsWith('.apps.googleusercontent.com')) {
      return trimmed;
    }
    final appId = trimmed.substring(
      0,
      trimmed.length - '.apps.googleusercontent.com'.length,
    );
    return 'com.googleusercontent.apps.$appId';
  }

  static Map<String, dynamic> _decodeJwtPayload(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) {
      return const <String, dynamic>{};
    }
    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return const <String, dynamic>{};
    }
    return const <String, dynamic>{};
  }

  static Future<void> _ensureKakaoInitialized() async {
    if (_kakaoInitialized) return;
    if (!NativeSocialAuthConfig.hasKakaoNativeAppKey) {
      throw const _NativeSocialSignInException(
        'Kakao sign-in is not configured in this build.',
      );
    }
    KakaoSdk.init(
      nativeAppKey: NativeSocialAuthConfig.effectiveKakaoNativeAppKey,
      customScheme: 'kakao${NativeSocialAuthConfig.effectiveKakaoNativeAppKey}',
    );
    _kakaoInitialized = true;
  }

  static Future<OAuthToken> _startKakaoSignIn() async {
    final hasKakaoTalk = await isKakaoTalkInstalled();
    if (!hasKakaoTalk) {
      return UserApi.instance.loginWithKakaoAccount();
    }
    try {
      return await UserApi.instance.loginWithKakaoTalk();
    } catch (e) {
      if (_shouldFallbackToKakaoAccountLogin(e)) {
        return UserApi.instance.loginWithKakaoAccount();
      }
      rethrow;
    }
  }

  static Future<NativeSocialSignInPayload> _signInWithKakaoMacOS() async {
    if (!NativeSocialAuthConfig.hasKakaoNativeAppKey) {
      throw const _NativeSocialSignInException(
        'Kakao sign-in is not configured in this build.',
      );
    }
    if (!NativeSocialAuthConfig.hasKakaoRestApiKey) {
      throw const _NativeSocialSignInException(
        'Kakao REST API key is not configured for this desktop build.',
      );
    }
    try {
      final payload = await _macosNativeSocialChannel
          .invokeMapMethod<String, dynamic>(
              'signInWithKakao', <String, dynamic>{
        'nativeAppKey': NativeSocialAuthConfig.effectiveKakaoNativeAppKey,
        'restApiKey': NativeSocialAuthConfig.effectiveKakaoRestApiKey,
      });
      final accessToken = (payload?['access_token'] ?? '').toString().trim();
      if (accessToken.isEmpty) {
        throw const _NativeSocialSignInException(
          'Kakao sign-in did not return an access token.',
        );
      }
      return NativeSocialSignInPayload(
        provider: AuthProviderType.kakao,
        body: <String, dynamic>{
          'provider': AuthProviderType.kakao.value,
          'access_token': accessToken,
        },
      );
    } on PlatformException catch (e) {
      final message = (e.message ?? '').trim();
      if (e.code == 'USER_CANCELLED' || message.contains('cancelled')) {
        throw const _NativeSocialSignInException(
          'Social sign-in was cancelled.',
        );
      }
      throw _NativeSocialSignInException(
        message.isEmpty ? 'Kakao sign-in could not be completed.' : message,
      );
    } on MissingPluginException {
      throw const _NativeSocialSignInException(
        'Kakao sign-in is not available in this desktop build.',
      );
    }
  }

  static bool _shouldFallbackToKakaoAccountLogin(Object error) {
    final code = _extractKakaoErrorCode(error).toLowerCase();
    final message = _extractKakaoErrorMessage(error).toLowerCase();
    final combined = '$code $message';
    return combined.contains('not connected to kakao account') ||
        combined.contains('kakaotalk is installed but not connected') ||
        combined.contains('notsupporterror');
  }

  static bool _isKakaoCancelledError(Object error, String message) {
    final code = _extractKakaoErrorCode(error).toLowerCase();
    final normalizedMessage = message.toLowerCase();
    return code.contains('cancel') || normalizedMessage.contains('cancel');
  }

  static String _friendlyKakaoErrorMessage(
    Object error, {
    required String rawMessage,
  }) {
    if (_shouldFallbackToKakaoAccountLogin(error)) {
      return 'KakaoTalk is installed but no Kakao account is signed in on this device. '
          'Sign in to KakaoTalk and try again, or continue with Kakao account sign-in.';
    }
    if (rawMessage.isEmpty) {
      return 'Kakao sign-in could not be completed.';
    }
    return rawMessage;
  }

  static String _friendlyGooglePlatformErrorMessage(PlatformException error) {
    final combined = <String>[
      error.code,
      error.message ?? '',
      error.details?.toString() ?? '',
    ].join(' ').toLowerCase();

    if (combined.contains('cancel')) {
      return 'Social sign-in was cancelled.';
    }
    if (combined.contains('oauth2.googleapis.com/token') ||
        combined.contains('nsurlerrordomain') ||
        combined.contains('kcferrordomaincfnetwork') ||
        combined.contains('network connection was lost') ||
        combined.contains('-1005')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Google sign-in could not be completed. Please try again.';
  }

  static String _friendlyGoogleAppAuthErrorMessage(
    FlutterAppAuthPlatformException error,
  ) {
    final combined = <String>[
      error.code,
      error.message ?? '',
      error.details?.toString() ?? '',
    ].join(' ').toLowerCase();

    if (combined.contains('cancel')) {
      return 'Social sign-in was cancelled.';
    }
    if (combined.contains('oauth2.googleapis.com/token') ||
        combined.contains('nsurlerrordomain') ||
        combined.contains('kcferrordomaincfnetwork') ||
        combined.contains('network connection was lost') ||
        combined.contains('-1005')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (combined.contains('redirect') || combined.contains('invalid_request')) {
      return 'Google sign-in is not configured correctly for this desktop build.';
    }
    return 'Google sign-in could not be completed. Please try again.';
  }

  static String _extractKakaoErrorCode(Object error) {
    if (error is PlatformException) {
      return error.code.trim();
    }
    return '';
  }

  static String _extractKakaoErrorMessage(Object error) {
    if (error is KakaoClientException) {
      return error.msg.trim();
    }
    if (error is KakaoException) {
      return (error.message ?? '').trim();
    }
    if (error is PlatformException) {
      final parts = <String>[
        error.message?.trim() ?? '',
        error.details?.toString().trim() ?? '',
      ].where((part) => part.isNotEmpty).toList();
      return parts.join(' ').trim();
    }
    return '';
  }
}

class _NativeSocialSignInException implements Exception {
  const _NativeSocialSignInException(this.message);

  final String message;

  @override
  String toString() => message;
}
