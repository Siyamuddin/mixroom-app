import 'package:mixroom/models/auth_user_profile.dart';

class AppUserSnapshot {
  static const String signupCompleteState = 'signup_complete';
  static const String welcomeSeenState = 'signup_complete_welcome_seen';

  const AppUserSnapshot({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.emailVerified,
    required this.cognitoUsername,
    required this.authProvider,
    required this.username,
    required this.givenName,
    required this.familyName,
    required this.birthdate,
    required this.musicProfile,
    required this.avatarUrl,
    required this.bio,
    required this.profileStatus,
    required this.onboardingState,
    required this.acceptedTermsVersion,
    required this.acceptedPrivacyVersion,
    required this.acceptedAt,
    required this.newsletterOptIn,
    required this.newsletterOptInAt,
    required this.createdAt,
    required this.updatedAt,
    required this.lastSeenAt,
  });

  final String userId;
  final String email;
  final String displayName;
  final bool emailVerified;
  final String cognitoUsername;
  final String authProvider;
  final String? username;
  final String? givenName;
  final String? familyName;
  final String? birthdate;
  final String? musicProfile;
  final String? avatarUrl;
  final String? bio;
  final String profileStatus;
  final String onboardingState;
  final String? acceptedTermsVersion;
  final String? acceptedPrivacyVersion;
  final DateTime? acceptedAt;
  final bool newsletterOptIn;
  final DateTime? newsletterOptInAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSeenAt;

  bool get isSignupComplete {
    final normalized = onboardingState.trim().toLowerCase();
    return normalized == signupCompleteState ||
        normalized.startsWith('${signupCompleteState}_');
  }

  bool get hasSeenWelcomeOnboarding {
    return onboardingState.trim().toLowerCase() == welcomeSeenState;
  }

  String get effectiveUsername {
    final raw = (username ?? '').trim();
    if (raw.isNotEmpty) return raw;
    return displayName;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'user_id': userId,
      'email': email,
      'display_name': displayName,
      'email_verified': emailVerified,
      'cognito_username': cognitoUsername,
      'auth_provider': authProvider,
      'username': username,
      'given_name': givenName,
      'family_name': familyName,
      'birthdate': birthdate,
      'music_profile': musicProfile,
      'avatar_url': avatarUrl,
      'bio': bio,
      'profile_status': profileStatus,
      'onboarding_state': onboardingState,
      'accepted_terms_version': acceptedTermsVersion,
      'accepted_privacy_version': acceptedPrivacyVersion,
      'accepted_at': acceptedAt?.toIso8601String(),
      'newsletter_opt_in': newsletterOptIn,
      'newsletter_opt_in_at': newsletterOptInAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_seen_at': lastSeenAt?.toIso8601String(),
    };
  }

  factory AppUserSnapshot.fromJson(
    Map<String, dynamic> json, {
    AuthUserProfile? fallbackAuthUser,
  }) {
    final fallback = fallbackAuthUser == null
        ? null
        : AppUserSnapshot.fromAuthUser(fallbackAuthUser);

    DateTime? parseOptionalDate(Object? value) {
      final raw = (value ?? '').toString().trim();
      if (raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toUtc();
    }

    final fallbackCreatedAt = fallback?.createdAt ?? DateTime.now().toUtc();
    final fallbackUpdatedAt = fallback?.updatedAt ?? fallbackCreatedAt;
    final rawUsername = json['username'] ?? fallback?.username;

    return AppUserSnapshot(
      userId: (json['user_id'] ?? fallback?.userId ?? '').toString(),
      email: (json['email'] ?? fallback?.email ?? '').toString(),
      displayName:
          (json['display_name'] ?? fallback?.displayName ?? 'Mixroom User')
              .toString(),
      emailVerified: json['email_verified'] is bool
          ? json['email_verified'] as bool
          : (fallback?.emailVerified ?? false),
      cognitoUsername:
          (json['cognito_username'] ?? fallback?.cognitoUsername ?? '')
              .toString(),
      authProvider: (json['auth_provider'] ?? fallback?.authProvider ?? 'email')
          .toString(),
      username: (rawUsername as String?)?.trim().isEmpty == true
          ? null
          : rawUsername?.toString(),
      givenName: ((json['given_name'] ?? fallback?.givenName) as String?)
                  ?.trim()
                  .isEmpty ==
              true
          ? null
          : (json['given_name'] ?? fallback?.givenName)?.toString(),
      familyName: ((json['family_name'] ?? fallback?.familyName) as String?)
                  ?.trim()
                  .isEmpty ==
              true
          ? null
          : (json['family_name'] ?? fallback?.familyName)?.toString(),
      birthdate: ((json['birthdate'] ?? fallback?.birthdate) as String?)
                  ?.trim()
                  .isEmpty ==
              true
          ? null
          : (json['birthdate'] ?? fallback?.birthdate)?.toString(),
      musicProfile:
          ((json['music_profile'] ?? fallback?.musicProfile) as String?)
                      ?.trim()
                      .isEmpty ==
                  true
              ? null
              : (json['music_profile'] ?? fallback?.musicProfile)?.toString(),
      avatarUrl: ((json['avatar_url'] ?? fallback?.avatarUrl) as String?)
                  ?.trim()
                  .isEmpty ==
              true
          ? null
          : (json['avatar_url'] ?? fallback?.avatarUrl)?.toString(),
      bio: ((json['bio'] ?? fallback?.bio) as String?)?.trim().isEmpty == true
          ? null
          : (json['bio'] ?? fallback?.bio)?.toString(),
      profileStatus:
          (json['profile_status'] ?? fallback?.profileStatus ?? 'active')
              .toString(),
      onboardingState: (json['onboarding_state'] ??
              fallback?.onboardingState ??
              'bootstrap_only')
          .toString(),
      acceptedTermsVersion: ((json['accepted_terms_version'] ??
                      fallback?.acceptedTermsVersion) as String?)
                  ?.trim()
                  .isEmpty ==
              true
          ? null
          : (json['accepted_terms_version'] ?? fallback?.acceptedTermsVersion)
              ?.toString(),
      acceptedPrivacyVersion: ((json['accepted_privacy_version'] ??
                      fallback?.acceptedPrivacyVersion) as String?)
                  ?.trim()
                  .isEmpty ==
              true
          ? null
          : (json['accepted_privacy_version'] ??
                  fallback?.acceptedPrivacyVersion)
              ?.toString(),
      acceptedAt:
          parseOptionalDate(json['accepted_at']) ?? fallback?.acceptedAt,
      newsletterOptIn: json['newsletter_opt_in'] is bool
          ? json['newsletter_opt_in'] as bool
          : (fallback?.newsletterOptIn ?? false),
      newsletterOptInAt: parseOptionalDate(json['newsletter_opt_in_at']) ??
          fallback?.newsletterOptInAt,
      createdAt: parseOptionalDate(json['created_at']) ?? fallbackCreatedAt,
      updatedAt: parseOptionalDate(json['updated_at']) ?? fallbackUpdatedAt,
      lastSeenAt:
          parseOptionalDate(json['last_seen_at']) ?? fallback?.lastSeenAt,
    );
  }

  factory AppUserSnapshot.fromAuthUser(AuthUserProfile user) {
    return AppUserSnapshot(
      userId: user.userId,
      email: user.email,
      displayName: user.displayName,
      emailVerified: user.emailVerified,
      cognitoUsername: user.email,
      authProvider: user.provider.value,
      username: null,
      givenName: null,
      familyName: null,
      birthdate: null,
      musicProfile: null,
      avatarUrl: null,
      bio: null,
      profileStatus: 'active',
      onboardingState: 'bootstrap_only',
      acceptedTermsVersion: null,
      acceptedPrivacyVersion: null,
      acceptedAt: null,
      newsletterOptIn: false,
      newsletterOptInAt: null,
      createdAt: user.createdAt.toUtc(),
      updatedAt: DateTime.now().toUtc(),
      lastSeenAt: null,
    );
  }
}
