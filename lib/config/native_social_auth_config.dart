class NativeSocialAuthConfig {
  const NativeSocialAuthConfig._();

  static const String _defaultGoogleServerClientId =
      '105509343723-lufnthv351v328td07s89j53mf242pl5.apps.googleusercontent.com';
  static const String _defaultGoogleClientId =
      '105509343723-eatcl74aibc5pdqrnuvrc52n3f4m3mt3.apps.googleusercontent.com';
  static const String _defaultKakaoNativeAppKey =
      'a70f53b706f3290cd916615b82b3feea';

  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static const String kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
    defaultValue: '',
  );

  static String get effectiveGoogleServerClientId {
    final configured = googleServerClientId.trim();
    if (configured.isNotEmpty) return configured;
    return _defaultGoogleServerClientId;
  }

  static String get effectiveGoogleClientId {
    final configured = googleClientId.trim();
    if (configured.isNotEmpty) return configured;
    return _defaultGoogleClientId;
  }

  static String get effectiveKakaoNativeAppKey {
    final configured = kakaoNativeAppKey.trim();
    if (configured.isNotEmpty) return configured;
    return _defaultKakaoNativeAppKey;
  }

  static bool get hasGoogleServerClientId =>
      effectiveGoogleServerClientId.isNotEmpty;

  static bool get hasGoogleClientId => effectiveGoogleClientId.isNotEmpty;

  static bool get hasKakaoNativeAppKey => effectiveKakaoNativeAppKey.isNotEmpty;
}
