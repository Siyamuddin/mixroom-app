class CognitoConfig {
  const CognitoConfig._();

  static const String region = String.fromEnvironment(
    'COGNITO_REGION',
    defaultValue: 'ap-northeast-2',
  );

  static const String userPoolId = String.fromEnvironment(
    'COGNITO_USER_POOL_ID',
    defaultValue: 'ap-northeast-2_NkxXsFx8Q',
  );

  static const String appClientId = String.fromEnvironment(
    'COGNITO_APP_CLIENT_ID',
    defaultValue: '6c7nkqmrrjvkjibpjurmehpa52',
  );

  static const String domainUrl = String.fromEnvironment(
    'COGNITO_DOMAIN_URL',
    defaultValue:
        'https://ap-northeast-2nkxxsfx8q.auth.ap-northeast-2.amazoncognito.com',
  );

  static const String androidRedirectUri = String.fromEnvironment(
    'COGNITO_REDIRECT_URI_ANDROID',
    defaultValue: 'com.mixroom.mixroomapp://oauthredirect',
  );

  static const String iosRedirectUri = String.fromEnvironment(
    'COGNITO_REDIRECT_URI_IOS',
    defaultValue: 'com.mixroom.mixroom://oauthredirect',
  );

  static const String googleIdentityProviderName = String.fromEnvironment(
    'COGNITO_PROVIDER_GOOGLE',
    defaultValue: 'Google',
  );

  static const String appleIdentityProviderName = String.fromEnvironment(
    'COGNITO_PROVIDER_APPLE',
    defaultValue: 'SignInWithApple',
  );

  static const String kakaoIdentityProviderName = String.fromEnvironment(
    'COGNITO_PROVIDER_KAKAO',
    defaultValue: 'Kakao',
  );

  static const bool enableUseCaseCustomAttribute = bool.fromEnvironment(
    'COGNITO_ENABLE_USE_CASE_ATTRIBUTE',
    defaultValue: false,
  );

  static const String useCaseCustomAttributeName = String.fromEnvironment(
    'COGNITO_USE_CASE_ATTRIBUTE_NAME',
    defaultValue: 'custom:mixroom_use_case',
  );

  static const List<String> scopes = <String>[
    'openid',
    'email',
    'profile',
    'aws.cognito.signin.user.admin',
  ];

  static String get cognitoIdpEndpoint =>
      'https://cognito-idp.$region.amazonaws.com/';
}
