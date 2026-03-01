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
    required this.useMixroomFor,
    required this.createdAt,
    this.birthday,
  });

  final String userId;
  final String email;
  final String displayName;
  final AuthProviderType provider;
  final bool emailVerified;
  final DateTime? birthday;
  final String useMixroomFor;
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
      'birthday': birthday?.toIso8601String(),
      'useMixroomFor': useMixroomFor,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AuthUserProfile.fromJson(Map<String, dynamic> json) {
    final provider =
        AuthProviderTypeX.fromValue((json['provider'] ?? '').toString());
    return AuthUserProfile(
      userId: (json['userId'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      provider: provider,
      emailVerified: json['emailVerified'] is bool
          ? json['emailVerified'] as bool
          : provider != AuthProviderType.email,
      birthday: json['birthday'] == null
          ? null
          : DateTime.tryParse(json['birthday'].toString()),
      useMixroomFor: (json['useMixroomFor'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  AuthUserProfile copyWith({
    String? userId,
    String? email,
    String? displayName,
    AuthProviderType? provider,
    bool? emailVerified,
    DateTime? birthday,
    bool clearBirthday = false,
    String? useMixroomFor,
    DateTime? createdAt,
  }) {
    return AuthUserProfile(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      provider: provider ?? this.provider,
      emailVerified: emailVerified ?? this.emailVerified,
      birthday: clearBirthday ? null : (birthday ?? this.birthday),
      useMixroomFor: useMixroomFor ?? this.useMixroomFor,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
