enum AppUpdatePromptType {
  none,
  soft,
  force,
}

class AppPlatformUpdatePolicy {
  const AppPlatformUpdatePolicy({
    required this.latestVersion,
    required this.minSupportedVersion,
    required this.storeUrl,
    required this.promptCadenceHours,
  });

  final String latestVersion;
  final String minSupportedVersion;
  final String storeUrl;
  final int promptCadenceHours;

  bool get isConfigured => latestVersion.trim().isNotEmpty;

  factory AppPlatformUpdatePolicy.fromJson(Map<String, dynamic> json) {
    return AppPlatformUpdatePolicy(
      latestVersion: '${json['latestVersion'] ?? ''}'.trim(),
      minSupportedVersion: '${json['minSupportedVersion'] ?? ''}'.trim(),
      storeUrl: '${json['storeUrl'] ?? ''}'.trim(),
      promptCadenceHours: _parsePromptCadenceHours(json['promptCadenceHours']),
    );
  }

  static int _parsePromptCadenceHours(Object? value) {
    final parsed = switch (value) {
      int n => n,
      String s => int.tryParse(s) ?? 24,
      _ => 24,
    };
    return parsed < 1 ? 1 : parsed;
  }
}

class AppUpdatePolicySet {
  const AppUpdatePolicySet({
    this.ios,
    this.android,
    this.macos,
  });

  final AppPlatformUpdatePolicy? ios;
  final AppPlatformUpdatePolicy? android;
  final AppPlatformUpdatePolicy? macos;

  factory AppUpdatePolicySet.fromJson(Map<String, dynamic> json) {
    AppPlatformUpdatePolicy? readPlatform(String key) {
      final raw = json[key];
      if (raw is! Map) return null;
      final policy = AppPlatformUpdatePolicy.fromJson(
        raw.cast<String, dynamic>(),
      );
      return policy.isConfigured ? policy : null;
    }

    return AppUpdatePolicySet(
      ios: readPlatform('ios'),
      android: readPlatform('android'),
      macos: readPlatform('macos'),
    );
  }
}

class AppUpdateDecision {
  const AppUpdateDecision({
    required this.type,
    required this.currentVersion,
    required this.latestVersion,
    required this.minSupportedVersion,
    required this.storeUrl,
    required this.promptCadenceHours,
  });

  final AppUpdatePromptType type;
  final String currentVersion;
  final String latestVersion;
  final String minSupportedVersion;
  final String storeUrl;
  final int promptCadenceHours;

  bool get isUpdateAvailable => type != AppUpdatePromptType.none;
}

class AppVersionStatus {
  const AppVersionStatus({
    required this.currentVersion,
    required this.latestVersion,
    required this.storeUrl,
    required this.isUpdateAvailable,
  });

  final String currentVersion;
  final String latestVersion;
  final String storeUrl;
  final bool isUpdateAvailable;

  bool get hasLatestVersion => latestVersion.trim().isNotEmpty;
  bool get hasStoreUrl => storeUrl.trim().isNotEmpty;
}
