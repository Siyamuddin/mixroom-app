import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mixroom/config/cognito_config.dart';
import 'package:mixroom/config/dev_flags.dart';
import 'package:mixroom/helpers/cognito_auth_client.dart';
import 'package:mixroom/helpers/password_policy.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  static const String _prefsSessionKey = 'mixroom.auth.session.v2';

  AuthService() {
    unawaited(_restoreSession());
  }

  final CognitoAuthClient _cognito = CognitoAuthClient();

  bool _isInitializing = true;
  bool _isBusy = false;
  AuthUserProfile? _currentUser;
  CognitoTokens? _tokens;
  String? _pendingRegistrationUseCase;

  bool get isInitializing => _isInitializing;
  bool get isBusy => _isBusy;
  bool get isSignedIn => _currentUser != null;
  AuthUserProfile? get currentUser => _currentUser;

  Future<String?> getIdTokenOrNull() async {
    final user = _currentUser;
    final tokens = _tokens;
    if (user == null || tokens == null) return null;

    try {
      final refreshed = await _refreshSessionIfNeeded(provider: user.provider);
      if (refreshed != null) {
        _setSession(
          refreshed,
          provider: user.provider,
          createdAt: user.createdAt,
          fallbackUseMixroomFor: user.useMixroomFor,
        );
        await _persistSession();
      }
    } catch (_) {
      return null;
    }

    final idToken = _tokens?.idToken.trim() ?? '';
    return idToken.isEmpty ? null : idToken;
  }

  Future<void> _restoreSession() async {
    try {
      if (isAuthBypassEnabled) {
        _currentUser = _debugUser;
      } else {
        final prefs = await SharedPreferences.getInstance();
        final rawSession = prefs.getString(_prefsSessionKey);
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
          }
        }

        final current = _currentUser;
        final tokens = _tokens;
        if (current != null && tokens != null) {
          try {
            final refreshed = await _refreshSessionIfNeeded(
              provider: current.provider,
            );
            if (refreshed != null) {
              _setSession(
                refreshed,
                provider: current.provider,
                createdAt: current.createdAt,
                fallbackUseMixroomFor: current.useMixroomFor,
              );
              await _persistSession();
            }
          } catch (_) {
            // Keep cached user profile for offline continuity; next auth action
            // will revalidate token state with Cognito.
          }
        }
      }
    } catch (_) {
      _currentUser = null;
      _tokens = null;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final safeEmail = email.trim().toLowerCase();
    if (safeEmail.isEmpty || password.isEmpty) {
      throw StateError('Please enter both email and password.');
    }

    await _runBusyTask(() async {
      try {
        final session = await _cognito.signInWithEmail(
          email: safeEmail,
          password: password,
        );
        _setSession(
          session,
          provider: AuthProviderType.email,
          createdAt: DateTime.now(),
        );
        await _persistSession();
      } on CognitoApiException catch (e) {
        if (e.code == 'UserNotConfirmedException') {
          throw AuthEmailConfirmationRequiredException(
            email: safeEmail,
            message:
                'Please verify your email first. Enter the code sent to $safeEmail.',
          );
        }
        if (e.code == 'NotAuthorizedException' ||
            e.code == 'UserNotFoundException') {
          throw StateError('Incorrect email or password.');
        }
        if (e.code == 'InvalidParameterException') {
          throw StateError(
            'App client auth flow is not enabled yet. Enable USER_PASSWORD_AUTH in Cognito app client.',
          );
        }
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> registerWithEmail({
    required String name,
    required String email,
    required String password,
    required DateTime? birthday,
    required String useMixroomFor,
  }) async {
    final safeName = name.trim();
    final safeEmail = email.trim().toLowerCase();
    final safeUseCase = useMixroomFor.trim();

    if (safeName.isEmpty) {
      throw StateError('Please enter your name.');
    }
    if (safeEmail.isEmpty || password.isEmpty) {
      throw StateError('Please enter email and password.');
    }
    final passwordIssue = PasswordPolicy.validate(password);
    if (passwordIssue != null) {
      throw StateError(passwordIssue);
    }
    if (birthday == null) {
      throw StateError('Please select your birthday.');
    }
    if (safeUseCase.isEmpty) {
      throw StateError('Please tell us what you use Mixroom for.');
    }
    _pendingRegistrationUseCase = safeUseCase;

    await _runBusyTask(() async {
      try {
        final signUp = await _cognito.signUpEmail(
          email: safeEmail,
          password: password,
          name: safeName,
          birthday: birthday,
          useMixroomFor: safeUseCase,
        );
        if (signUp.userConfirmed) {
          final session = await _cognito.signInWithEmail(
            email: safeEmail,
            password: password,
          );
          _setSession(
            session,
            provider: AuthProviderType.email,
            createdAt: DateTime.now(),
            fallbackUseMixroomFor: safeUseCase,
          );
          _pendingRegistrationUseCase = null;
          await _persistSession();
          return;
        }

        throw AuthEmailConfirmationRequiredException(
          email: safeEmail,
          message:
              'Account created. Enter the verification code sent to $safeEmail.',
        );
      } on AuthEmailConfirmationRequiredException {
        rethrow;
      } on CognitoApiException catch (e) {
        _pendingRegistrationUseCase = null;
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
    final safePassword = (passwordToSignIn ?? '').trim();
    if (safeEmail.isEmpty || safeCode.isEmpty) {
      throw StateError('Please provide both email and verification code.');
    }

    await _runBusyTask(() async {
      try {
        await _cognito.confirmSignUp(
          email: safeEmail,
          code: safeCode,
        );
        if (safePassword.isNotEmpty) {
          final session = await _cognito.signInWithEmail(
            email: safeEmail,
            password: safePassword,
          );
          _setSession(
            session,
            provider: AuthProviderType.email,
            createdAt: DateTime.now(),
            fallbackUseMixroomFor: _pendingRegistrationUseCase,
          );
          _pendingRegistrationUseCase = null;
          await _persistSession();
        }
      } on CognitoApiException catch (e) {
        if (e.code == 'CodeMismatchException' ||
            e.code == 'ExpiredCodeException') {
          throw StateError('Invalid or expired verification code.');
        }
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> resendSignUpCode({
    required String email,
  }) async {
    final safeEmail = email.trim().toLowerCase();
    if (safeEmail.isEmpty) {
      throw StateError('Please enter your email address.');
    }

    await _runBusyTask(() async {
      try {
        await _cognito.resendSignUpCode(email: safeEmail);
      } on CognitoApiException catch (e) {
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> signInWithGoogle() async {
    await _signInWithSocial(
      provider: AuthProviderType.google,
      identityProviderName: CognitoConfig.googleIdentityProviderName,
    );
  }

  Future<void> signInWithApple() async {
    await _signInWithSocial(
      provider: AuthProviderType.apple,
      identityProviderName: CognitoConfig.appleIdentityProviderName,
    );
  }

  Future<void> signInWithKakao() async {
    await _signInWithSocial(
      provider: AuthProviderType.kakao,
      identityProviderName: CognitoConfig.kakaoIdentityProviderName,
    );
  }

  Future<void> _signInWithSocial({
    required AuthProviderType provider,
    required String identityProviderName,
  }) async {
    await _runBusyTask(() async {
      try {
        final session = await _cognito.signInWithSocial(
          identityProviderName: identityProviderName,
        );
        _setSession(
          session,
          provider: provider,
          createdAt: DateTime.now(),
          fallbackUseMixroomFor: _currentUser?.useMixroomFor,
        );
        await _persistSession();
      } on CognitoApiException catch (e) {
        throw StateError(_friendlyErrorMessage(e));
      } catch (_) {
        throw StateError('Social sign-in was cancelled.');
      }
    });
  }

  Future<void> requestPasswordReset({
    required String email,
  }) async {
    final safeEmail = email.trim().toLowerCase();
    if (safeEmail.isEmpty) {
      throw StateError('Please enter your email address.');
    }

    await _runBusyTask(() async {
      try {
        await _cognito.requestPasswordReset(email: safeEmail);
      } on CognitoApiException catch (e) {
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
    final passwordIssue = PasswordPolicy.validate(newPassword);
    if (passwordIssue != null) {
      throw StateError(passwordIssue);
    }

    await _runBusyTask(() async {
      try {
        await _cognito.confirmPasswordReset(
          email: safeEmail,
          code: safeCode,
          newPassword: newPassword,
        );
      } on CognitoApiException catch (e) {
        if (e.code == 'CodeMismatchException' ||
            e.code == 'ExpiredCodeException') {
          throw StateError('Invalid or expired verification code.');
        }
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> resendEmailVerification() async {
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
        final accessToken = await _requireAccessToken();
        await _cognito.resendEmailVerification(accessToken: accessToken);
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
          birthday: updated.birthday,
          useMixroomFor: updated.useMixroomFor,
        );

        final refreshed =
            await _cognito.getCurrentUser(accessToken: accessToken);
        _currentUser = _mapUser(
          refreshed,
          provider: existing.provider,
          createdAt: existing.createdAt,
          fallbackUseMixroomFor: updated.useMixroomFor,
        );
        await _persistSession();
      } on CognitoApiException catch (e) {
        throw StateError(_friendlyErrorMessage(e));
      }
    });
  }

  Future<void> signOut() async {
    await _runBusyTask(() async {
      // Temporary local-only logout until backend sign-out is finalized.
      await _clearSession();
    });
  }

  Future<void> deleteAccount() async {
    await _runBusyTask(() async {
      try {
        final accessToken = await _requireAccessToken();
        await _cognito.deleteUser(accessToken: accessToken);
      } on CognitoApiException catch (e) {
        throw StateError(_friendlyErrorMessage(e));
      } finally {
        await _clearSession();
      }
    });
  }

  Future<void> devBypassSignIn() async {
    await _runBusyTask(() async {
      _currentUser = _debugUser;
      _tokens = null;
      _pendingRegistrationUseCase = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsSessionKey,
        jsonEncode({
          'user': _currentUser!.toJson(),
        }),
      );
    });
  }

  Future<void> _persistSession() async {
    final user = _currentUser;
    final tokens = _tokens;
    if (user == null || tokens == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsSessionKey,
      jsonEncode({
        'user': user.toJson(),
        'tokens': tokens.toJson(),
      }),
    );
    notifyListeners();
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
    _pendingRegistrationUseCase = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsSessionKey);
  }

  Future<String> _requireAccessToken() async {
    final tokens = _tokens;
    final user = _currentUser;
    if (tokens == null || user == null) {
      throw StateError('No active account.');
    }

    final refreshed = await _refreshSessionIfNeeded(provider: user.provider);
    if (refreshed != null) {
      _setSession(
        refreshed,
        provider: user.provider,
        createdAt: user.createdAt,
        fallbackUseMixroomFor: user.useMixroomFor,
      );
      await _persistSession();
    }

    final accessToken = _tokens?.accessToken ?? '';
    if (accessToken.isEmpty) {
      throw StateError('Session expired. Please sign in again.');
    }
    return accessToken;
  }

  Future<CognitoSession?> _refreshSessionIfNeeded({
    required AuthProviderType provider,
  }) async {
    final tokens = _tokens;
    if (tokens == null || !tokens.isExpiringSoon) return null;
    if (tokens.refreshToken.trim().isEmpty) {
      throw StateError('Session expired. Please sign in again.');
    }

    final refreshed = await _cognito.refreshSession(
      refreshToken: tokens.refreshToken,
      fallbackIdToken: tokens.idToken,
    );

    // Preserve provider in local profile.
    if (_currentUser != null && _currentUser!.provider != provider) {
      _currentUser = _currentUser!.copyWith(provider: provider);
    }
    return refreshed;
  }

  void _setSession(
    CognitoSession session, {
    required AuthProviderType provider,
    required DateTime createdAt,
    String? fallbackUseMixroomFor,
  }) {
    _tokens = session.tokens;
    _currentUser = _mapUser(
      session.user,
      provider: provider,
      createdAt: createdAt,
      fallbackUseMixroomFor: fallbackUseMixroomFor,
    );
  }

  AuthUserProfile _mapUser(
    CognitoUserAttributes user, {
    required AuthProviderType provider,
    required DateTime createdAt,
    String? fallbackUseMixroomFor,
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
      birthday: user.birthdate,
      useMixroomFor: (user.mixroomUseCase ?? '').trim().isEmpty
          ? ((fallbackUseMixroomFor ?? '').trim().isEmpty
              ? 'Music production'
              : fallbackUseMixroomFor!.trim())
          : user.mixroomUseCase!.trim(),
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
        return 'Incorrect email or password.';
      case 'UserNotConfirmedException':
        return 'Please verify your email first.';
      case 'LimitExceededException':
      case 'TooManyRequestsException':
        return 'Too many attempts. Please try again shortly.';
      case 'NetworkError':
        return 'Network error. Please check your connection and try again.';
      default:
        final msg = error.message.trim();
        if (msg.isEmpty) return 'Authentication failed. Please try again.';
        return msg;
    }
  }

  AuthUserProfile get _debugUser {
    return AuthUserProfile(
      userId: 'debug-user',
      email: 'dev+test@mixroom.app',
      displayName: 'Dev Test User',
      provider: AuthProviderType.email,
      emailVerified: false,
      birthday: DateTime(1999, 6, 24),
      useMixroomFor: 'Testing app builds',
      createdAt: DateTime(2026, 1, 1),
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
