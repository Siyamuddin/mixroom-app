import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/remote_announcement_config.dart';
import '../core/analytics/analytics_events.dart';
import '../core/analytics/analytics_service.dart';

class RemoteAnnouncement {
  const RemoteAnnouncement({
    required this.source,
    required this.announcementVersion,
    required this.presentationMode,
    required this.style,
    required this.title,
    required this.body,
    required this.primaryButtonLabel,
    required this.secondaryButtonLabel,
    required this.primaryActionUrl,
    required this.mediaType,
    required this.mediaReference,
    required this.mediaVersion,
    required this.minAccountCreatedAt,
    required this.maxAccountCreatedAt,
    this.installedAt,
  });

  final String source;
  final String announcementVersion;
  final String presentationMode;
  final String style;
  final String title;
  final String body;
  final String primaryButtonLabel;
  final String secondaryButtonLabel;
  final String primaryActionUrl;
  final String mediaType;
  final String mediaReference;
  final String mediaVersion;
  final DateTime? minAccountCreatedAt;
  final DateTime? maxAccountCreatedAt;
  final String? installedAt;

  bool get hasMedia => mediaReference.trim().isNotEmpty;

  bool get showsBanner =>
      presentationMode == 'banner' || presentationMode == 'both';

  bool get showsModal =>
      presentationMode == 'modal' || presentationMode == 'both';
}

class _RemoteAnnouncementMediaSpec {
  const _RemoteAnnouncementMediaSpec({
    required this.mediaType,
    required this.url,
    required this.sha256Hex,
    required this.fileName,
    required this.version,
  });

  final String mediaType;
  final String url;
  final String sha256Hex;
  final String fileName;
  final String version;
}

class _RemoteAnnouncementManifest {
  const _RemoteAnnouncementManifest({
    required this.announcementVersion,
    required this.enabled,
    required this.rolloutPercent,
    required this.minAppVersion,
    required this.maxAppVersion,
    required this.presentationMode,
    required this.style,
    required this.title,
    required this.body,
    required this.primaryButtonLabel,
    required this.secondaryButtonLabel,
    required this.primaryActionUrl,
    required this.minAccountCreatedAt,
    required this.maxAccountCreatedAt,
    required this.media,
  });

  final String announcementVersion;
  final bool enabled;
  final int rolloutPercent;
  final String minAppVersion;
  final String maxAppVersion;
  final String presentationMode;
  final String style;
  final String title;
  final String body;
  final String primaryButtonLabel;
  final String secondaryButtonLabel;
  final String primaryActionUrl;
  final DateTime? minAccountCreatedAt;
  final DateTime? maxAccountCreatedAt;
  final _RemoteAnnouncementMediaSpec? media;

  factory _RemoteAnnouncementManifest.fromJson(Map<String, dynamic> json) {
    final announcementVersion = '${json['announcement_version'] ?? ''}'.trim();
    if (announcementVersion.isEmpty) {
      throw const FormatException(
        'Remote announcement manifest is missing announcement_version.',
      );
    }
    final presentationMode =
        '${json['presentation_mode'] ?? 'banner'}'.trim().toLowerCase();
    if (presentationMode != 'banner' &&
        presentationMode != 'modal' &&
        presentationMode != 'both') {
      throw const FormatException(
        'Remote announcement manifest has invalid presentation_mode.',
      );
    }
    final style = '${json['style'] ?? 'info'}'.trim().toLowerCase();
    if (style != 'info' &&
        style != 'success' &&
        style != 'warning' &&
        style != 'critical') {
      throw const FormatException(
        'Remote announcement manifest has invalid style.',
      );
    }

    DateTime? parseOptionalDate(Object? value) {
      final raw = '${value ?? ''}'.trim();
      if (raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toUtc();
    }

    final enabled = json['enabled'] != false;
    final rawMedia = (json['media'] as Map?)?.cast<String, dynamic>();
    _RemoteAnnouncementMediaSpec? media;
    if (rawMedia != null && rawMedia.isNotEmpty) {
      final mediaType = '${rawMedia['media_type'] ?? ''}'.trim().toLowerCase();
      final url = '${rawMedia['url'] ?? ''}'.trim();
      final sha256Hex = '${rawMedia['sha256'] ?? ''}'.trim().toLowerCase();
      final fileName = '${rawMedia['file_name'] ?? ''}'.trim();
      final version =
          '${rawMedia['version'] ?? _basenameWithoutExtension(fileName)}'
              .trim();
      if (mediaType.isEmpty ||
          mediaType != 'image' ||
          url.isEmpty ||
          sha256Hex.isEmpty ||
          fileName.isEmpty ||
          version.isEmpty) {
        throw const FormatException(
          'Remote announcement manifest has invalid media fields.',
        );
      }
      media = _RemoteAnnouncementMediaSpec(
        mediaType: mediaType,
        url: url,
        sha256Hex: sha256Hex,
        fileName: fileName,
        version: version,
      );
    }

    return _RemoteAnnouncementManifest(
      announcementVersion: announcementVersion,
      enabled: enabled,
      rolloutPercent:
          _safeInt(json['rollout_percent'], fallback: 100).clamp(0, 100),
      minAppVersion: '${json['min_app_version'] ?? ''}'.trim(),
      maxAppVersion: '${json['max_app_version'] ?? ''}'.trim(),
      presentationMode: presentationMode,
      style: style,
      title: '${json['title'] ?? 'Mixroom update'}'.trim(),
      body: '${json['body'] ?? ''}'.trim(),
      primaryButtonLabel:
          '${json['primary_button_label'] ?? 'Learn more'}'.trim(),
      secondaryButtonLabel:
          '${json['secondary_button_label'] ?? 'Dismiss'}'.trim(),
      primaryActionUrl: '${json['primary_action_url'] ?? ''}'.trim(),
      minAccountCreatedAt: parseOptionalDate(json['min_account_created_at']),
      maxAccountCreatedAt: parseOptionalDate(json['max_account_created_at']),
      media: media,
    );
  }
}

class RemoteAnnouncementManager {
  RemoteAnnouncementManager({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const String _prefsKeyLastCheckedAt =
      'mixroom.remote_announcement.last_checked_at';
  static const String _prefsKeyBadAnnouncementVersion =
      'mixroom.remote_announcement.bad_announcement_version';
  static const String _prefsKeyDismissedAnnouncementVersion =
      'mixroom.remote_announcement.dismissed_version';
  static const String _prefsKeyModalSeenAnnouncementVersion =
      'mixroom.remote_announcement.modal_seen_version';

  final http.Client _httpClient;

  Future<void>? _refreshFuture;
  RemoteAnnouncement? _cachedAnnouncement;

  Future<void> refreshInBackground() async {
    if (kRemoteAnnouncementManifestUrl.trim().isEmpty) return;
    final inFlight = _refreshFuture;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _refreshRemoteAnnouncement();
    _refreshFuture = future;
    try {
      await future;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<RemoteAnnouncement?> installedAnnouncement() async {
    final cached = _cachedAnnouncement;
    if (cached != null) return cached;
    final metadata = await _readInstalledMetadata();
    if (metadata == null) return null;
    final announcement = await _announcementFromMetadata(metadata);
    _cachedAnnouncement = announcement;
    return announcement;
  }

  bool isEligibleForUser({
    required RemoteAnnouncement announcement,
    required DateTime accountCreatedAtUtc,
  }) {
    if (announcement.minAccountCreatedAt != null &&
        accountCreatedAtUtc.isBefore(announcement.minAccountCreatedAt!)) {
      return false;
    }
    if (announcement.maxAccountCreatedAt != null &&
        accountCreatedAtUtc.isAfter(announcement.maxAccountCreatedAt!)) {
      return false;
    }
    return true;
  }

  Future<bool> isDismissed(String announcementVersion) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_prefsKeyDismissedAnnouncementVersion)?.trim() ??
            '') ==
        announcementVersion.trim();
  }

  Future<void> markDismissed({
    required RemoteAnnouncement announcement,
    required String action,
    String? errorCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyDismissedAnnouncementVersion,
      announcement.announcementVersion,
    );
    _trackInteractionEvent(
      announcement: announcement,
      action: action,
      errorCode: errorCode,
    );
  }

  Future<bool> shouldShowBanner(RemoteAnnouncement announcement) async {
    if (!announcement.showsBanner) return false;
    return !(await isDismissed(announcement.announcementVersion));
  }

  Future<bool> shouldShowModal(RemoteAnnouncement announcement) async {
    if (!announcement.showsModal) return false;
    final prefs = await SharedPreferences.getInstance();
    final dismissed =
        (prefs.getString(_prefsKeyDismissedAnnouncementVersion)?.trim() ??
                '') ==
            announcement.announcementVersion;
    if (dismissed) return false;
    final seen =
        (prefs.getString(_prefsKeyModalSeenAnnouncementVersion)?.trim() ??
                '') ==
            announcement.announcementVersion;
    return !seen;
  }

  Future<void> markModalSeen(RemoteAnnouncement announcement) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyModalSeenAnnouncementVersion,
      announcement.announcementVersion,
    );
  }

  Future<void> markPresentationFailed(
    RemoteAnnouncement announcement,
    Object error,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyBadAnnouncementVersion,
      announcement.announcementVersion,
    );
    await _deleteInstalledAnnouncement(announcement.announcementVersion);
    _cachedAnnouncement = null;
    _trackUpdateEvent(
      status: 'presentation_failed',
      announcementVersion: announcement.announcementVersion,
      presentationMode: announcement.presentationMode,
      style: announcement.style,
      mediaType: announcement.mediaType,
      mediaVersion: announcement.mediaVersion,
      errorCode: error.runtimeType.toString(),
    );
  }

  void trackShown({
    required RemoteAnnouncement announcement,
    required String presentationMode,
  }) {
    unawaited(
      AnalyticsService.instance.track(
        AnalyticsEvents.remoteAnnouncementShown(
          announcementVersion: announcement.announcementVersion,
          presentationMode: presentationMode,
          style: announcement.style,
          mediaType: announcement.mediaType,
          mediaVersion: announcement.mediaVersion,
        ),
      ),
    );
  }

  Future<void> _refreshRemoteAnnouncement() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_shouldRefreshNow(prefs)) {
      return;
    }
    await prefs.setString(
      _prefsKeyLastCheckedAt,
      DateTime.now().toUtc().toIso8601String(),
    );

    final manifestUri = Uri.tryParse(kRemoteAnnouncementManifestUrl.trim());
    if (manifestUri == null) {
      _trackUpdateEvent(
        status: 'manifest_invalid',
        errorCode: 'invalid_manifest_url',
      );
      return;
    }

    try {
      final response = await _httpClient.get(manifestUri).timeout(
          Duration(seconds: kRemoteAnnouncementManifestTimeoutSeconds));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _trackUpdateEvent(
          status: 'download_failed',
          errorCode: 'manifest_http_${response.statusCode}',
        );
        return;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Manifest root must be an object.');
      }
      final manifest =
          _RemoteAnnouncementManifest.fromJson(decoded.cast<String, dynamic>());
      final current = await installedAnnouncement();

      if (!manifest.enabled) {
        await _revertInstalledAnnouncementIfNeeded(current);
        _trackUpdateEvent(
          status: 'manifest_disabled',
          announcementVersion: manifest.announcementVersion,
        );
        return;
      }

      final appVersion = await _currentAppVersion();
      if (!_isCompatibleWithAppVersion(manifest, appVersion)) {
        await _revertInstalledAnnouncementIfNeeded(current);
        _trackUpdateEvent(
          status: 'app_version_incompatible',
          announcementVersion: manifest.announcementVersion,
          presentationMode: manifest.presentationMode,
          style: manifest.style,
        );
        return;
      }

      if (!_isEligibleForRollout(
        rolloutPercent: manifest.rolloutPercent,
        deviceId: AnalyticsService.instance.deviceId,
      )) {
        await _revertInstalledAnnouncementIfNeeded(current);
        _trackUpdateEvent(
          status: 'rollout_skipped',
          announcementVersion: manifest.announcementVersion,
          presentationMode: manifest.presentationMode,
          style: manifest.style,
        );
        return;
      }

      final badAnnouncementVersion =
          prefs.getString(_prefsKeyBadAnnouncementVersion)?.trim() ?? '';
      if (badAnnouncementVersion == manifest.announcementVersion) {
        await _revertInstalledAnnouncementIfNeeded(current);
        return;
      }

      if (current != null &&
          current.announcementVersion == manifest.announcementVersion) {
        _trackUpdateEvent(
          status: 'up_to_date',
          announcementVersion: current.announcementVersion,
          presentationMode: current.presentationMode,
          style: current.style,
          mediaType: current.mediaType,
          mediaVersion: current.mediaVersion,
        );
        return;
      }

      await _installAnnouncement(manifestUri, manifest);
      _cachedAnnouncement = null;
      final installed = await installedAnnouncement();
      _trackUpdateEvent(
        status: 'downloaded',
        announcementVersion: manifest.announcementVersion,
        presentationMode:
            installed?.presentationMode ?? manifest.presentationMode,
        style: installed?.style ?? manifest.style,
        mediaType: installed?.mediaType ?? manifest.media?.mediaType,
        mediaVersion: installed?.mediaVersion ?? manifest.media?.version,
      );
    } on TimeoutException {
      _trackUpdateEvent(
        status: 'download_failed',
        errorCode: 'manifest_timeout',
      );
    } on FormatException catch (error) {
      _trackUpdateEvent(
        status: 'manifest_invalid',
        errorCode: error.message,
      );
    } catch (error) {
      _trackUpdateEvent(
        status: 'download_failed',
        errorCode: error.runtimeType.toString(),
      );
    }
  }

  Future<void> _installAnnouncement(
    Uri manifestUri,
    _RemoteAnnouncementManifest manifest,
  ) async {
    final rootDir = await _rootDir();
    final versionDir = Directory(
      p.join(rootDir.path,
          _announcementDirectoryName(manifest.announcementVersion)),
    );

    String mediaPath = '';
    String mediaType = '';
    String mediaVersion = '';
    final media = manifest.media;
    if (media != null) {
      final mediaTarget = File(p.join(versionDir.path, media.fileName));
      await _downloadAndVerify(
        manifestUri: manifestUri,
        url: media.url,
        expectedSha256: media.sha256Hex,
        outputFile: mediaTarget,
      );
      mediaPath = mediaTarget.path;
      mediaType = media.mediaType;
      mediaVersion = media.version;
    }

    final metadata = <String, dynamic>{
      'announcement_version': manifest.announcementVersion,
      'installed_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'remote',
      'presentation_mode': manifest.presentationMode,
      'style': manifest.style,
      'title': manifest.title,
      'body': manifest.body,
      'primary_button_label': manifest.primaryButtonLabel,
      'secondary_button_label': manifest.secondaryButtonLabel,
      'primary_action_url': manifest.primaryActionUrl,
      'min_account_created_at':
          manifest.minAccountCreatedAt?.toIso8601String() ?? '',
      'max_account_created_at':
          manifest.maxAccountCreatedAt?.toIso8601String() ?? '',
      'media': <String, dynamic>{
        'type': mediaType,
        'version': mediaVersion,
        'path': mediaPath,
      },
    };

    final metadataFile =
        File(p.join(rootDir.path, 'installed_announcement.json'));
    final tempFile = File('${metadataFile.path}.tmp');
    await tempFile.writeAsString(jsonEncode(metadata), flush: true);
    if (metadataFile.existsSync()) {
      await metadataFile.delete();
    }
    await tempFile.rename(metadataFile.path);
    await _pruneAnnouncements(
        keepAnnouncementVersion: manifest.announcementVersion);
  }

  Future<void> _downloadAndVerify({
    required Uri manifestUri,
    required String url,
    required String expectedSha256,
    required File outputFile,
  }) async {
    final uri = Uri.parse(url);
    if (!_isTrustedRemoteUri(manifestUri, uri)) {
      throw const FormatException(
        'Announcement asset URL is outside the trusted origin.',
      );
    }
    final request = http.Request('GET', uri);
    final response = await _httpClient.send(request).timeout(
          Duration(seconds: kRemoteAnnouncementManifestTimeoutSeconds * 2),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Announcement asset download failed (HTTP ${response.statusCode}).',
        uri: uri,
      );
    }
    final tempFile = File('${outputFile.path}.download');
    if (tempFile.existsSync()) {
      await tempFile.delete();
    }
    await tempFile.parent.create(recursive: true);
    final sink = tempFile.openWrite();
    try {
      await response.stream.pipe(sink);
    } finally {
      await sink.flush();
      await sink.close();
    }
    final digest = await _sha256ForFile(tempFile);
    if (digest != expectedSha256.toLowerCase()) {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
      throw const FormatException('Announcement asset checksum mismatch.');
    }
    if (outputFile.existsSync()) {
      await outputFile.delete();
    }
    await tempFile.rename(outputFile.path);
  }

  Future<Directory> _rootDir() async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory(p.join(supportDir.path, 'remote_announcements'))
      ..createSync(recursive: true);
  }

  Future<Map<String, dynamic>?> _readInstalledMetadata() async {
    final rootDir = await _rootDir();
    final metadataFile =
        File(p.join(rootDir.path, 'installed_announcement.json'));
    if (!metadataFile.existsSync()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await metadataFile.readAsString());
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  Future<RemoteAnnouncement?> _announcementFromMetadata(
    Map<String, dynamic> metadata,
  ) async {
    final announcementVersion =
        '${metadata['announcement_version'] ?? ''}'.trim();
    if (announcementVersion.isEmpty) {
      return null;
    }
    final media = (metadata['media'] as Map?)?.cast<String, dynamic>();
    final mediaType = '${media?['type'] ?? ''}'.trim().toLowerCase();
    final mediaPath = '${media?['path'] ?? ''}'.trim();
    final mediaVersion = '${media?['version'] ?? ''}'.trim();

    DateTime? parseDate(Object? value) {
      final raw = '${value ?? ''}'.trim();
      if (raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toUtc();
    }

    if (mediaPath.isNotEmpty && !File(mediaPath).existsSync()) {
      return null;
    }

    return RemoteAnnouncement(
      source: '${metadata['source'] ?? 'remote'}'.trim(),
      announcementVersion: announcementVersion,
      presentationMode:
          '${metadata['presentation_mode'] ?? 'banner'}'.trim().toLowerCase(),
      style: '${metadata['style'] ?? 'info'}'.trim().toLowerCase(),
      title: '${metadata['title'] ?? 'Mixroom update'}'.trim(),
      body: '${metadata['body'] ?? ''}'.trim(),
      primaryButtonLabel:
          '${metadata['primary_button_label'] ?? 'Learn more'}'.trim(),
      secondaryButtonLabel:
          '${metadata['secondary_button_label'] ?? 'Dismiss'}'.trim(),
      primaryActionUrl: '${metadata['primary_action_url'] ?? ''}'.trim(),
      mediaType: mediaType,
      mediaReference: mediaPath,
      mediaVersion: mediaVersion,
      minAccountCreatedAt: parseDate(metadata['min_account_created_at']),
      maxAccountCreatedAt: parseDate(metadata['max_account_created_at']),
      installedAt: '${metadata['installed_at'] ?? ''}'.trim(),
    );
  }

  Future<void> _deleteInstalledAnnouncement(String announcementVersion) async {
    final rootDir = await _rootDir();
    final versionDir = Directory(
      p.join(rootDir.path, _announcementDirectoryName(announcementVersion)),
    );
    if (versionDir.existsSync()) {
      await versionDir.delete(recursive: true);
    }
    final metadataFile =
        File(p.join(rootDir.path, 'installed_announcement.json'));
    if (metadataFile.existsSync()) {
      try {
        final metadata = jsonDecode(await metadataFile.readAsString());
        if (metadata is Map &&
            '${metadata['announcement_version'] ?? ''}'.trim() ==
                announcementVersion.trim()) {
          await metadataFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _pruneAnnouncements({
    required String keepAnnouncementVersion,
  }) async {
    final rootDir = await _rootDir();
    if (!rootDir.existsSync()) return;
    final keepDirectoryName =
        _announcementDirectoryName(keepAnnouncementVersion);
    await for (final entity in rootDir.list()) {
      if (entity is! Directory) continue;
      if (p.basename(entity.path) == keepDirectoryName) continue;
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _revertInstalledAnnouncementIfNeeded(
    RemoteAnnouncement? current,
  ) async {
    if (current == null) return;
    await _deleteInstalledAnnouncement(current.announcementVersion);
    _cachedAnnouncement = null;
  }

  bool _shouldRefreshNow(SharedPreferences prefs) {
    final lastCheckedRaw =
        prefs.getString(_prefsKeyLastCheckedAt)?.trim() ?? '';
    if (lastCheckedRaw.isEmpty) return true;
    final lastChecked = DateTime.tryParse(lastCheckedRaw);
    if (lastChecked == null) return true;
    return DateTime.now().toUtc().difference(lastChecked) >=
        Duration(hours: kRemoteAnnouncementRefreshIntervalHours);
  }

  Future<String> _currentAppVersion() async {
    final analyticsVersion = AnalyticsService.instance.appVersion.trim();
    if (analyticsVersion.isNotEmpty) {
      return analyticsVersion;
    }
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    final buildNumber = info.buildNumber.trim();
    if (version.isEmpty) return buildNumber;
    return buildNumber.isEmpty ? version : '$version+$buildNumber';
  }

  bool _isCompatibleWithAppVersion(
    _RemoteAnnouncementManifest manifest,
    String appVersion,
  ) {
    if (manifest.minAppVersion.isNotEmpty &&
        _compareVersions(appVersion, manifest.minAppVersion) < 0) {
      return false;
    }
    if (manifest.maxAppVersion.isNotEmpty &&
        _compareVersions(appVersion, manifest.maxAppVersion) > 0) {
      return false;
    }
    return true;
  }

  bool _isEligibleForRollout({
    required int rolloutPercent,
    required String deviceId,
  }) {
    if (rolloutPercent >= 100) return true;
    if (rolloutPercent <= 0) return false;
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) return true;
    final digest = sha256.convert(utf8.encode(normalizedDeviceId)).bytes;
    final bucket = digest.first % 100;
    return bucket < rolloutPercent;
  }

  Future<String> _sha256ForFile(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  bool _isTrustedRemoteUri(Uri manifestUri, Uri candidateUri) {
    if (candidateUri.scheme.toLowerCase() != 'https') {
      return false;
    }
    return candidateUri.host.toLowerCase() == manifestUri.host.toLowerCase() &&
        candidateUri.port == manifestUri.port;
  }

  void _trackUpdateEvent({
    required String status,
    String? announcementVersion,
    String? presentationMode,
    String? style,
    String? mediaType,
    String? mediaVersion,
    String? errorCode,
  }) {
    unawaited(
      AnalyticsService.instance.track(
        AnalyticsEvents.remoteAnnouncementUpdate(
          status: status,
          announcementVersion: announcementVersion,
          presentationMode: presentationMode,
          style: style,
          mediaType: mediaType,
          mediaVersion: mediaVersion,
          errorCode: errorCode,
        ),
      ),
    );
  }

  void _trackInteractionEvent({
    required RemoteAnnouncement announcement,
    required String action,
    String? errorCode,
  }) {
    unawaited(
      AnalyticsService.instance.track(
        AnalyticsEvents.remoteAnnouncementInteracted(
          announcementVersion: announcement.announcementVersion,
          presentationMode: announcement.presentationMode,
          style: announcement.style,
          action: action,
          mediaType: announcement.mediaType,
          mediaVersion: announcement.mediaVersion,
          actionUrl: announcement.primaryActionUrl,
          errorCode: errorCode,
        ),
      ),
    );
  }
}

int _safeInt(Object? value, {required int fallback}) {
  if (value is int) return value;
  return int.tryParse('${value ?? ''}'.trim()) ?? fallback;
}

String _basenameWithoutExtension(String fileName) {
  final trimmed = fileName.trim();
  if (trimmed.isEmpty) return '';
  final basename = p.basename(trimmed);
  final dotIndex = basename.lastIndexOf('.');
  if (dotIndex <= 0) return basename;
  return basename.substring(0, dotIndex);
}

int _compareVersions(String left, String right) {
  List<int> parseVersion(String raw) {
    final sanitized = raw.trim();
    if (sanitized.isEmpty) return const <int>[0];
    return sanitized
        .split(RegExp(r'[^0-9]+'))
        .where((segment) => segment.isNotEmpty)
        .map((segment) => int.tryParse(segment) ?? 0)
        .toList(growable: false);
  }

  final leftParts = parseVersion(left);
  final rightParts = parseVersion(right);
  final maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < maxLength; index++) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) {
      return leftValue.compareTo(rightValue);
    }
  }
  return 0;
}

String _announcementDirectoryName(String announcementVersion) {
  final sanitized =
      announcementVersion.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  return sanitized.isEmpty ? 'announcement' : sanitized;
}
