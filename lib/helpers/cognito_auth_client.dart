import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/config/cognito_config.dart';

class CognitoApiException implements Exception {
  const CognitoApiException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => message;
}

class CognitoTokens {
  const CognitoTokens({
    required this.accessToken,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAtUtc,
  });

  final String accessToken;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAtUtc;

  bool get isExpiringSoon =>
      DateTime.now().toUtc().isAfter(expiresAtUtc.subtract(
            const Duration(minutes: 2),
          ));

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'idToken': idToken,
      'refreshToken': refreshToken,
      'expiresAtUtc': expiresAtUtc.toIso8601String(),
    };
  }

  factory CognitoTokens.fromJson(Map<String, dynamic> json) {
    return CognitoTokens(
      accessToken: (json['accessToken'] ?? '').toString(),
      idToken: (json['idToken'] ?? '').toString(),
      refreshToken: (json['refreshToken'] ?? '').toString(),
      expiresAtUtc:
          DateTime.tryParse((json['expiresAtUtc'] ?? '').toString())?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }
}

class CognitoUserAttributes {
  const CognitoUserAttributes({
    required this.sub,
    required this.email,
    required this.emailVerified,
    this.name,
    this.birthdate,
    this.mixroomUseCase,
  });

  final String sub;
  final String email;
  final bool emailVerified;
  final String? name;
  final DateTime? birthdate;
  final String? mixroomUseCase;
}

class CognitoSession {
  const CognitoSession({
    required this.tokens,
    required this.user,
  });

  final CognitoTokens tokens;
  final CognitoUserAttributes user;
}

class CognitoSignUpResult {
  const CognitoSignUpResult({
    required this.userConfirmed,
  });

  final bool userConfirmed;
}

class CognitoAuthClient {
  CognitoAuthClient({
    http.Client? httpClient,
    FlutterAppAuth? appAuth,
  })  : _httpClient = httpClient ?? http.Client(),
        _appAuth = appAuth ?? const FlutterAppAuth();

  final http.Client _httpClient;
  final FlutterAppAuth _appAuth;

  Future<CognitoSignUpResult> signUpEmail({
    required String email,
    required String password,
    required String name,
    DateTime? birthday,
    String? useMixroomFor,
  }) async {
    final attrs = <Map<String, String>>[
      {'Name': 'email', 'Value': email},
      if (name.trim().isNotEmpty) {'Name': 'name', 'Value': name.trim()},
      if (birthday != null)
        {'Name': 'birthdate', 'Value': _formatBirthdate(birthday)},
      if (CognitoConfig.enableUseCaseCustomAttribute &&
          (useMixroomFor ?? '').trim().isNotEmpty)
        {
          'Name': CognitoConfig.useCaseCustomAttributeName,
          'Value': useMixroomFor!.trim(),
        },
    ];

    Future<Map<String, dynamic>> performSignUp(String username) {
      return _post(
        target: 'SignUp',
        payload: {
          'ClientId': CognitoConfig.appClientId,
          'Username': username,
          'Password': password,
          'UserAttributes': attrs,
        },
      );
    }

    Map<String, dynamic> result;
    try {
      // Works for pools configured with email as the username.
      result = await performSignUp(email);
    } on CognitoApiException catch (e) {
      // For pools configured with email alias, Cognito requires a non-email
      // username while still allowing email sign-in via alias.
      final message = e.message.toLowerCase();
      final needsAliasStyleUsername = e.code == 'InvalidParameterException' &&
          (message.contains('username cannot be of email format') ||
              message.contains('cannot be of email format'));
      if (!needsAliasStyleUsername) rethrow;
      result = await performSignUp(_generatedAliasUsername(email));
    }

    return CognitoSignUpResult(
      userConfirmed: result['UserConfirmed'] == true,
    );
  }

  Future<void> confirmSignUp({
    required String email,
    required String code,
  }) async {
    await _post(
      target: 'ConfirmSignUp',
      payload: {
        'ClientId': CognitoConfig.appClientId,
        'Username': email,
        'ConfirmationCode': code,
      },
    );
  }

  Future<void> resendSignUpCode({
    required String email,
  }) async {
    await _post(
      target: 'ResendConfirmationCode',
      payload: {
        'ClientId': CognitoConfig.appClientId,
        'Username': email,
      },
    );
  }

  Future<CognitoSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final result = await _post(
      target: 'InitiateAuth',
      payload: {
        'AuthFlow': 'USER_PASSWORD_AUTH',
        'ClientId': CognitoConfig.appClientId,
        'AuthParameters': {
          'USERNAME': email,
          'PASSWORD': password,
        },
      },
    );

    final auth = _asMap(result['AuthenticationResult']);
    final tokens = _tokensFromAuthResult(auth);
    final user = await getCurrentUser(accessToken: tokens.accessToken);
    return CognitoSession(tokens: tokens, user: user);
  }

  Future<CognitoSession> refreshSession({
    required String refreshToken,
    required String fallbackIdToken,
  }) async {
    final result = await _post(
      target: 'InitiateAuth',
      payload: {
        'AuthFlow': 'REFRESH_TOKEN_AUTH',
        'ClientId': CognitoConfig.appClientId,
        'AuthParameters': {
          'REFRESH_TOKEN': refreshToken,
        },
      },
    );

    final auth = _asMap(result['AuthenticationResult']);
    final tokens = _tokensFromAuthResult(
      auth,
      fallbackRefreshToken: refreshToken,
      fallbackIdToken: fallbackIdToken,
    );
    final user = await getCurrentUser(accessToken: tokens.accessToken);
    return CognitoSession(tokens: tokens, user: user);
  }

  Future<CognitoSession> signInWithSocial({
    required String identityProviderName,
  }) async {
    if (kIsWeb) {
      throw const CognitoApiException(
        code: 'UnsupportedPlatform',
        message: 'Social sign-in is only supported on iOS/Android.',
      );
    }

    final redirectUri = switch (defaultTargetPlatform) {
      TargetPlatform.android => CognitoConfig.androidRedirectUri,
      TargetPlatform.iOS => CognitoConfig.iosRedirectUri,
      _ => throw const CognitoApiException(
          code: 'UnsupportedPlatform',
          message: 'Social sign-in is only supported on iOS/Android.',
        ),
    };

    final response = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        CognitoConfig.appClientId,
        redirectUri,
        scopes: CognitoConfig.scopes,
        serviceConfiguration: AuthorizationServiceConfiguration(
          authorizationEndpoint: '${CognitoConfig.domainUrl}/oauth2/authorize',
          tokenEndpoint: '${CognitoConfig.domainUrl}/oauth2/token',
        ),
        additionalParameters: {
          'identity_provider': identityProviderName,
        },
      ),
    );

    if ((response.accessToken ?? '').isEmpty) {
      throw const CognitoApiException(
        code: 'AuthorizationFailed',
        message: 'Sign-in was cancelled or did not return a token.',
      );
    }

    final tokens = _tokensFromAppAuth(response);
    final user = await getCurrentUser(accessToken: tokens.accessToken);
    return CognitoSession(tokens: tokens, user: user);
  }

  Future<void> requestPasswordReset({
    required String email,
  }) async {
    await _post(
      target: 'ForgotPassword',
      payload: {
        'ClientId': CognitoConfig.appClientId,
        'Username': email,
      },
    );
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _post(
      target: 'ConfirmForgotPassword',
      payload: {
        'ClientId': CognitoConfig.appClientId,
        'Username': email,
        'ConfirmationCode': code,
        'Password': newPassword,
      },
    );
  }

  Future<void> resendEmailVerification({
    required String accessToken,
  }) async {
    await _post(
      target: 'GetUserAttributeVerificationCode',
      payload: {
        'AccessToken': accessToken,
        'AttributeName': 'email',
      },
    );
  }

  Future<void> updateUserAttributes({
    required String accessToken,
    required String displayName,
    DateTime? birthday,
    required String useMixroomFor,
  }) async {
    final attrs = <Map<String, String>>[
      if (displayName.trim().isNotEmpty)
        {'Name': 'name', 'Value': displayName.trim()},
      if (birthday != null)
        {'Name': 'birthdate', 'Value': _formatBirthdate(birthday)},
      if (CognitoConfig.enableUseCaseCustomAttribute &&
          useMixroomFor.trim().isNotEmpty)
        {
          'Name': CognitoConfig.useCaseCustomAttributeName,
          'Value': useMixroomFor.trim(),
        },
    ];
    if (attrs.isEmpty) return;

    await _post(
      target: 'UpdateUserAttributes',
      payload: {
        'AccessToken': accessToken,
        'UserAttributes': attrs,
      },
    );
  }

  Future<void> signOut({
    required String accessToken,
  }) async {
    await _post(
      target: 'GlobalSignOut',
      payload: {
        'AccessToken': accessToken,
      },
    );
  }

  Future<void> deleteUser({
    required String accessToken,
  }) async {
    await _post(
      target: 'DeleteUser',
      payload: {
        'AccessToken': accessToken,
      },
    );
  }

  Future<CognitoUserAttributes> getCurrentUser({
    required String accessToken,
  }) async {
    final result = await _post(
      target: 'GetUser',
      payload: {
        'AccessToken': accessToken,
      },
    );

    final attrs = _parseAttributes(result['UserAttributes']);
    return CognitoUserAttributes(
      sub: attrs['sub'] ?? '',
      email: attrs['email'] ?? '',
      emailVerified: (attrs['email_verified'] ?? '').toLowerCase() == 'true',
      name: _nullIfBlank(attrs['name']),
      birthdate: DateTime.tryParse(attrs['birthdate'] ?? ''),
      mixroomUseCase:
          _nullIfBlank(attrs[CognitoConfig.useCaseCustomAttributeName]),
    );
  }

  Future<Map<String, dynamic>> _post({
    required String target,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _httpClient.post(
      Uri.parse(CognitoConfig.cognitoIdpEndpoint),
      headers: {
        'Content-Type': 'application/x-amz-json-1.1',
        'X-Amz-Target': 'AWSCognitoIdentityProviderService.$target',
      },
      body: jsonEncode(payload),
    );

    final body = response.body;
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    final map = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'message': 'Unexpected response format.'};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return map;
    }

    final code = _extractErrorCode(map);
    final message = _extractErrorMessage(map, fallbackCode: code);
    throw CognitoApiException(code: code, message: message);
  }

  String _extractErrorCode(Map<String, dynamic> payload) {
    final raw = (payload['__type'] ?? payload['code'] ?? payload['Code'] ?? '')
        .toString();
    if (raw.isEmpty) return 'UnknownException';
    final hashIndex = raw.lastIndexOf('#');
    return hashIndex >= 0 ? raw.substring(hashIndex + 1) : raw;
  }

  String _extractErrorMessage(
    Map<String, dynamic> payload, {
    required String fallbackCode,
  }) {
    final message = (payload['message'] ?? payload['Message'] ?? '')
        .toString()
        .trim();
    if (message.isNotEmpty) return message;
    return fallbackCode;
  }

  CognitoTokens _tokensFromAuthResult(
    Map<String, dynamic> authResult, {
    String? fallbackRefreshToken,
    String? fallbackIdToken,
  }) {
    final accessToken = (authResult['AccessToken'] ?? '').toString();
    if (accessToken.isEmpty) {
      throw const CognitoApiException(
        code: 'TokenMissing',
        message: 'Authentication succeeded but access token was missing.',
      );
    }

    final idToken = (authResult['IdToken'] ?? fallbackIdToken ?? '').toString();
    final refreshToken =
        (authResult['RefreshToken'] ?? fallbackRefreshToken ?? '').toString();
    final expiresInSec = (authResult['ExpiresIn'] as num?)?.toInt() ?? 3600;
    final expiresAtUtc =
        DateTime.now().toUtc().add(Duration(seconds: expiresInSec));

    return CognitoTokens(
      accessToken: accessToken,
      idToken: idToken,
      refreshToken: refreshToken,
      expiresAtUtc: expiresAtUtc,
    );
  }

  CognitoTokens _tokensFromAppAuth(TokenResponse response) {
    final accessToken = (response.accessToken ?? '').trim();
    if (accessToken.isEmpty) {
      throw const CognitoApiException(
        code: 'TokenMissing',
        message: 'Authentication succeeded but access token was missing.',
      );
    }

    return CognitoTokens(
      accessToken: accessToken,
      idToken: (response.idToken ?? '').trim(),
      refreshToken: (response.refreshToken ?? '').trim(),
      expiresAtUtc:
          response.accessTokenExpirationDateTime?.toUtc() ??
              DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key.toString(), val),
      );
    }
    return <String, dynamic>{};
  }

  Map<String, String> _parseAttributes(Object? value) {
    if (value is! List) return <String, String>{};

    final out = <String, String>{};
    for (final item in value) {
      if (item is! Map) continue;
      final name = item['Name']?.toString() ?? '';
      if (name.isEmpty) continue;
      out[name] = item['Value']?.toString() ?? '';
    }
    return out;
  }

  String _formatBirthdate(DateTime date) {
    final d = date.toUtc();
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  String? _nullIfBlank(String? value) {
    final safe = value?.trim() ?? '';
    return safe.isEmpty ? null : safe;
  }

  String _generatedAliasUsername(String email) {
    final local = email.split('@').first;
    final seed = local.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
    final prefix = seed.isEmpty ? 'mixroom' : seed.toLowerCase();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${prefix}_$ts';
  }
}
