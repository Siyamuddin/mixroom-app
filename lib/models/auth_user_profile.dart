import 'package:flutter/foundation.dart';

enum AuthProviderType { email, google, apple, kakao }

extension AuthProviderTypeX on AuthProviderType {
  String get value {
    switch (this) {
      case AuthProviderType.email:
        return 'email';
      case AuthProviderType.google:
        return 'google';
      case AuthProviderType.apple:
        return 'apple';
      case AuthProviderType.kakao:
        return 'kakao';
    }
  }

  String get label {
    switch (this) {
      case AuthProviderType.email:
        return 'Email';
      case AuthProviderType.google:
        return 'Google';
      case AuthProviderType.apple:
        return 'Apple';
      case AuthProviderType.kakao:
        return 'KakaoTalk';
    }
  }

  static AuthProviderType fromValue(String value) {
    return AuthProviderType.values.firstWhere(
      (provider) => provider.value == value,
      orElse: () => AuthProviderType.email,
    );
  }
}

@immutable
class AuthUserProfile {
  const AuthUserProfile({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.provider,
    required this.emailVerified,
    required this.createdAt,
  });

  final String userId;
  final String email;
  final String displayName;
  final AuthProviderType provider;
  final bool emailVerified;
  final DateTime createdAt;

  String get initials {
    final parts = displayName
        .split(' ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'M';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'email': email,
      'displayName': displayName,
      'provider': provider.value,
      'emailVerified': emailVerified,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AuthUserProfile.fromJson(Map<String, dynamic> json) {
    final rawProvider =
        (json['provider'] ?? json['auth_provider'] ?? '').toString().trim();
    final provider = rawProvider.isEmpty
        ? AuthProviderType.email
        : AuthProviderTypeX.fromValue(rawProvider);
    final rawEmail =
        (json['email'] ?? json['email_address'] ?? '').toString().trim();
    return AuthUserProfile(
      userId: (json['userId'] ?? json['user_id'] ?? '').toString(),
      email: rawEmail.toLowerCase(),
      displayName:
          (json['displayName'] ?? json['display_name'] ?? '').toString(),
      provider: provider,
      emailVerified: json['emailVerified'] is bool
          ? json['emailVerified'] as bool
          : json['email_verified'] is bool
              ? json['email_verified'] as bool
              : provider != AuthProviderType.email,
      createdAt: DateTime.tryParse(
              (json['createdAt'] ?? json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  AuthUserProfile copyWith({
    String? userId,
    String? email,
    String? displayName,
    AuthProviderType? provider,
    bool? emailVerified,
    DateTime? createdAt,
  }) {
    return AuthUserProfile(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      provider: provider ?? this.provider,
      emailVerified: emailVerified ?? this.emailVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
