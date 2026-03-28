import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mixroom/config/app_api_config.dart';

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
    final expiresAtRaw = (json['expiresAtUtc'] ??
            json['expires_at_utc'] ??
            json['expiresAt'] ??
            json['expires_at'] ??
            '')
        .toString();
    final expiresInRaw = json['expiresIn'] ?? json['expires_in'];
    final expiresInSec = expiresInRaw is num ? expiresInRaw.toInt() : null;
    return CognitoTokens(
      accessToken:
          (json['accessToken'] ?? json['access_token'] ?? '').toString(),
      idToken: (json['idToken'] ?? json['id_token'] ?? '').toString(),
      refreshToken:
          (json['refreshToken'] ?? json['refresh_token'] ?? '').toString(),
      expiresAtUtc: DateTime.tryParse(expiresAtRaw)?.toUtc() ??
          DateTime.now().toUtc().add(Duration(seconds: expiresInSec ?? 3600)),
    );
  }
}

class CognitoUserAttributes {
  const CognitoUserAttributes({
    required this.sub,
    required this.email,
    required this.emailVerified,
    this.name,
  });

  final String sub;
  final String email;
  final bool emailVerified;
  final String? name;
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
    required this.username,
  });

  final bool userConfirmed;
  final String username;
}

class CognitoAuthClient {
  CognitoAuthClient({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<CognitoSignUpResult> signUpEmail({
    required String email,
    required String password,
    String? name,
    String? givenName,
    String? familyName,
    String? birthdate,
    String? locale,
  }) async {
    final result = await _post(
      path: '/v1/auth/sign-up',
      body: {
        'email': email,
        'password': password,
        'name': name,
        'given_name': givenName,
        'family_name': familyName,
        'birthdate': birthdate,
        if ((locale ?? '').trim().isNotEmpty) 'locale': locale!.trim(),
      },
    );
    final user = _asMap(result['user']);
    return CognitoSignUpResult(
      userConfirmed: false,
      username: (user['email'] ?? email).toString().trim(),
    );
  }

  Future<CognitoSession> confirmSignUp({
    required String username,
    required String code,
    String? password,
  }) async {
    final result = await _post(
      path: '/v1/auth/confirm-sign-up',
      body: {
        'email': username,
        'code': code,
        if ((password ?? '').trim().isNotEmpty) 'password': password!.trim(),
      },
    );
    return _sessionFromPayload(result);
  }

  Future<void> resendSignUpCode({
    required String username,
    String? locale,
  }) async {
    await _post(
      path: '/v1/auth/resend-sign-up-code',
      body: {
        'email': username,
        if ((locale ?? '').trim().isNotEmpty) 'locale': locale!.trim(),
      },
    );
  }

  Future<CognitoSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final result = await _post(
      path: '/v1/auth/sign-in',
      body: {
        'identifier': email,
        'password': password,
      },
    );
    return _sessionFromPayload(result);
  }

  Future<CognitoSession> refreshSession({
    required String refreshToken,
    required String fallbackIdToken,
  }) async {
    final result = await _post(
      path: '/v1/auth/refresh',
      body: {
        'refresh_token': refreshToken,
        if (fallbackIdToken.trim().isNotEmpty)
          'fallback_id_token': fallbackIdToken.trim(),
      },
    );
    return _sessionFromPayload(result);
  }

  Future<void> requestPasswordReset({
    required String email,
    String? locale,
  }) async {
    await _post(
      path: '/v1/auth/password-reset/request',
      body: {
        'email': email,
        if ((locale ?? '').trim().isNotEmpty) 'locale': locale!.trim(),
      },
    );
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _post(
      path: '/v1/auth/password-reset/confirm',
      body: {
        'email': email,
        'code': code,
        'new_password': newPassword,
      },
    );
  }

  Future<void> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _post(
      path: '/v1/auth/change-password',
      authToken: accessToken,
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }

  Future<void> resendEmailVerification({
    required String accessToken,
    String? locale,
  }) async {
    await _post(
      path: '/v1/auth/resend-email-verification',
      authToken: accessToken,
      body: <String, dynamic>{
        if ((locale ?? '').trim().isNotEmpty) 'locale': locale!.trim(),
      },
    );
  }

  Future<void> updateUserAttributes({
    required String accessToken,
    required String displayName,
  }) async {
    await _patch(
      path: '/v1/users/me',
      authToken: accessToken,
      body: {
        'display_name': displayName,
      },
    );
  }

  Future<void> signOut({
    required String accessToken,
  }) async {
    await _post(
      path: '/v1/auth/sign-out',
      authToken: accessToken,
      body: const <String, dynamic>{},
    );
  }

  Future<void> deleteUser({
    required String accessToken,
    required String confirmationText,
    String? currentPassword,
    Map<String, dynamic>? socialReauthPayload,
  }) async {
    await _delete(
      path: '/v1/users/me',
      authToken: accessToken,
      body: <String, dynamic>{
        'confirmation_text': confirmationText,
        if ((currentPassword ?? '').isNotEmpty)
          'current_password': currentPassword,
        if (socialReauthPayload != null && socialReauthPayload.isNotEmpty)
          'social_reauth': socialReauthPayload,
      },
    );
  }

  Future<CognitoUserAttributes> getCurrentUser({
    required String accessToken,
  }) async {
    final result = await _get(
      path: '/v1/users/me',
      authToken: accessToken,
    );
    return CognitoUserAttributes(
      sub: (result['user_id'] ?? result['userId'] ?? '').toString().trim(),
      email: (result['email'] ?? '').toString().trim().toLowerCase(),
      emailVerified:
          result['email_verified'] == true || result['emailVerified'] == true,
      name: _nullIfBlank((result['display_name'] ?? result['displayName'] ?? '')
          .toString()
          .trim()),
    );
  }

  Future<Map<String, dynamic>> _get({
    required String path,
    required String authToken,
  }) {
    return _request(
      method: 'GET',
      path: path,
      authToken: authToken,
    );
  }

  Future<Map<String, dynamic>> _post({
    required String path,
    required Map<String, dynamic> body,
    String? authToken,
  }) {
    return _request(
      method: 'POST',
      path: path,
      body: body,
      authToken: authToken,
    );
  }

  Future<Map<String, dynamic>> _patch({
    required String path,
    required String authToken,
    required Map<String, dynamic> body,
  }) {
    return _request(
      method: 'PATCH',
      path: path,
      body: body,
      authToken: authToken,
    );
  }

  Future<Map<String, dynamic>> _delete({
    required String path,
    required String authToken,
    Map<String, dynamic>? body,
  }) {
    return _request(
      method: 'DELETE',
      path: path,
      body: body,
      authToken: authToken,
    );
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    String? authToken,
  }) async {
    if (!AppApiConfig.hasApiBaseUrl) {
      throw const CognitoApiException(
        code: 'BackendNotConfigured',
        message: 'APP_API_BASE_URL is not configured for authentication.',
      );
    }

    final uri = _uri(path);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if ((authToken ?? '').trim().isNotEmpty)
        'Authorization': 'Bearer ${authToken!.trim()}',
    };

    late final http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _httpClient
              .get(uri, headers: headers)
              .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds));
          break;
        case 'PATCH':
          response = await _httpClient
              .patch(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds));
          break;
        case 'DELETE':
          response = await _httpClient
              .delete(
                uri,
                headers: headers,
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds));
          break;
        default:
          response = await _httpClient
              .post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds));
      }
    } on TimeoutException {
      throw const CognitoApiException(
        code: 'NetworkError',
        message: 'Network error. Please check your connection and try again.',
      );
    } on SocketException {
      throw const CognitoApiException(
        code: 'NetworkError',
        message: 'Network error. Please check your connection and try again.',
      );
    } on http.ClientException {
      throw const CognitoApiException(
        code: 'NetworkError',
        message: 'Network error. Please check your connection and try again.',
      );
    }

    final map = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return map;
    }

    final code = _extractErrorCode(map);
    final message = _extractErrorMessage(map, fallbackCode: code);
    throw CognitoApiException(code: code, message: message);
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  String _extractErrorCode(Map<String, dynamic> payload) {
    final raw = (payload['code'] ?? payload['Code'] ?? payload['__type'] ?? '')
        .toString();
    if (raw.isEmpty) return 'UnknownException';
    final hashIndex = raw.lastIndexOf('#');
    return hashIndex >= 0 ? raw.substring(hashIndex + 1) : raw;
  }

  String _extractErrorMessage(
    Map<String, dynamic> payload, {
    required String fallbackCode,
  }) {
    final message =
        (payload['error'] ?? payload['message'] ?? payload['Message'] ?? '')
            .toString()
            .trim();
    if (message.isNotEmpty) return message;
    return fallbackCode;
  }

  CognitoSession _sessionFromPayload(Map<String, dynamic> payload) {
    final tokens = CognitoTokens.fromJson(_asMap(payload['tokens']));
    final userPayload = _asMap(payload['user']);
    final user = CognitoUserAttributes(
      sub: (userPayload['userId'] ?? userPayload['user_id'] ?? '').toString(),
      email: (userPayload['email'] ?? '').toString().trim().toLowerCase(),
      emailVerified: userPayload['emailVerified'] == true ||
          userPayload['email_verified'] == true,
      name: _nullIfBlank(
          (userPayload['displayName'] ?? userPayload['display_name'] ?? '')
              .toString()
              .trim()),
    );
    return CognitoSession(tokens: tokens, user: user);
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

  String? _nullIfBlank(String? value) {
    final safe = value?.trim() ?? '';
    return safe.isEmpty ? null : safe;
  }

  Uri _uri(String path) {
    final base = AppApiConfig.apiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }
}
