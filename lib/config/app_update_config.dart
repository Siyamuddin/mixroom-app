class AppUpdateConfig {
  const AppUpdateConfig._();

  static const String policyUrl = String.fromEnvironment(
    'MIXROOM_APP_UPDATE_POLICY_URL',
    defaultValue:
        'https://d22u50embnfa6f.cloudfront.net/app-update/version-policy.json',
  );

  static const int policyTimeoutSeconds = int.fromEnvironment(
    'MIXROOM_APP_UPDATE_POLICY_TIMEOUT_SECONDS',
    defaultValue: 4,
  );

  static const int policyRefreshIntervalHours = int.fromEnvironment(
    'MIXROOM_APP_UPDATE_POLICY_REFRESH_INTERVAL_HOURS',
    defaultValue: 6,
  );

  static const int defaultPromptCadenceHours = int.fromEnvironment(
    'MIXROOM_SOFT_UPDATE_PROMPT_CADENCE_HOURS',
    defaultValue: 24,
  );

  /// Sparkle appcast used by the direct-download macOS build.
  ///
  /// The appcast and update archives are separate from the website DMG. The
  /// DMG is only the installer for first-time downloads; Sparkle consumes the
  /// signed archives referenced by this feed.
  static const String macosAppcastUrl = String.fromEnvironment(
    'MIXROOM_MACOS_APPCAST_URL',
    defaultValue: 'https://www.mixroom.ai/downloads/appcast.xml',
  );

  static const int desktopUpdateCheckIntervalSeconds = int.fromEnvironment(
    'MIXROOM_DESKTOP_UPDATE_CHECK_INTERVAL_SECONDS',
    defaultValue: 21600,
  );

  static const String macosLatestVersion = String.fromEnvironment(
    'MIXROOM_MACOS_LATEST_VERSION',
    defaultValue: '',
  );

  static const String macosMinSupportedVersion = String.fromEnvironment(
    'MIXROOM_MACOS_MIN_SUPPORTED_VERSION',
    defaultValue: '',
  );

  static const String iosLatestVersion = String.fromEnvironment(
    'MIXROOM_IOS_LATEST_VERSION',
    defaultValue: '',
  );

  static const String iosMinSupportedVersion = String.fromEnvironment(
    'MIXROOM_IOS_MIN_SUPPORTED_VERSION',
    defaultValue: '',
  );

  static const String iosStoreUrl = String.fromEnvironment(
    'MIXROOM_IOS_STORE_URL',
    defaultValue:
        'https://apps.apple.com/us/app/mixroom-ai-co-producer/id6759779450',
  );

  static const String androidLatestVersion = String.fromEnvironment(
    'MIXROOM_ANDROID_LATEST_VERSION',
    defaultValue: '',
  );

  static const String androidMinSupportedVersion = String.fromEnvironment(
    'MIXROOM_ANDROID_MIN_SUPPORTED_VERSION',
    defaultValue: '',
  );

  static const String androidStoreUrl = String.fromEnvironment(
    'MIXROOM_ANDROID_STORE_URL',
    defaultValue:
        'https://play.google.com/store/apps/details?id=com.mixroom.mixroomapp',
  );
}
