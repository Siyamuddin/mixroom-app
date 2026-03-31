const String kRemoteAnnouncementManifestUrl = String.fromEnvironment(
  'MIXROOM_REMOTE_ANNOUNCEMENT_MANIFEST_URL',
  defaultValue:
      'https://d22u50embnfa6f.cloudfront.net/announcements/manifest.json',
);

const int kRemoteAnnouncementManifestTimeoutSeconds = int.fromEnvironment(
  'MIXROOM_REMOTE_ANNOUNCEMENT_MANIFEST_TIMEOUT_SECONDS',
  defaultValue: 4,
);

const int kRemoteAnnouncementRefreshIntervalHours = int.fromEnvironment(
  'MIXROOM_REMOTE_ANNOUNCEMENT_REFRESH_INTERVAL_HOURS',
  defaultValue: 6,
);
