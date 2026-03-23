import 'dart:async';

import 'package:flutter/foundation.dart';
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

  static bool _googleInitialized = false;
  static bool _kakaoInitialized = false;

  static Future<NativeSocialSignInPayload> signInWithGoogle() async {
    if (!NativeSocialAuthConfig.hasGoogleServerClientId) {
      throw const _NativeSocialSignInException(
        'Google sign-in is not configured in this build.',
      );
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
    }
  }

  static Future<NativeSocialSignInPayload> signInWithApple() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      throw const _NativeSocialSignInException(
        'Apple sign-in is only supported on iPhone and iPad in this build.',
      );
    }

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
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
    await _ensureKakaoInitialized();

    try {
      final hasKakaoTalk = await isKakaoTalkInstalled();
      var token = hasKakaoTalk
          ? await UserApi.instance.loginWithKakaoTalk()
          : await UserApi.instance.loginWithKakaoAccount();
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
    } on KakaoException catch (e) {
      final message =
          (e is KakaoClientException ? e.msg : (e.message ?? '')).trim();
      if (message.toLowerCase().contains('cancel')) {
        throw const _NativeSocialSignInException(
            'Social sign-in was cancelled.');
      }
      throw _NativeSocialSignInException(
        message.isEmpty ? 'Kakao sign-in could not be completed.' : message,
      );
    }
  }

  static Future<void> signOut(AuthProviderType provider) async {
    try {
      switch (provider) {
        case AuthProviderType.google:
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
      serverClientId: NativeSocialAuthConfig.hasGoogleServerClientId
          ? NativeSocialAuthConfig.effectiveGoogleServerClientId
          : null,
    );
    _googleInitialized = true;
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
}

class _NativeSocialSignInException implements Exception {
  const _NativeSocialSignInException(this.message);

  final String message;

  @override
  String toString() => message;
}
