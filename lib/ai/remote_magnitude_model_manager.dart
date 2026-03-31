import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_debug.dart';
import '../core/analytics/analytics_events.dart';
import '../core/analytics/analytics_service.dart';
import 'magnitude_predictor_flags.dart';

class MagnitudeModelSelection {
  const MagnitudeModelSelection({
    required this.source,
    required this.bundleVersion,
    required this.applyModelReference,
    required this.magnitudeModelReference,
    required this.applyModelVersion,
    required this.magnitudeModelVersion,
    this.installedAt,
  });

  final String source;
  final String bundleVersion;
  final String applyModelReference;
  final String magnitudeModelReference;
  final String applyModelVersion;
  final String magnitudeModelVersion;
  final String? installedAt;

  bool get isRemote => source == 'remote';

  Map<String, dynamic> toObservabilityContext() {
    return <String, dynamic>{
      'mix_magnitude_model_source': source,
      'mix_magnitude_model_bundle_version': bundleVersion,
      'mix_apply_model_version': applyModelVersion,
      'mix_magnitude_regressor_version': magnitudeModelVersion,
    };
  }
}

class _RemoteModelAssetSpec {
  const _RemoteModelAssetSpec({
    required this.version,
    required this.url,
    required this.sha256Hex,
    required this.fileName,
  });

  final String version;
  final String url;
  final String sha256Hex;
  final String fileName;
}

class _RemoteBundleManifest {
  const _RemoteBundleManifest({
    required this.bundleVersion,
    required this.applyModel,
    required this.magnitudeModel,
    required this.enabled,
    required this.rolloutPercent,
    required this.minAppVersion,
    required this.maxAppVersion,
  });

  final String bundleVersion;
  final _RemoteModelAssetSpec applyModel;
  final _RemoteModelAssetSpec magnitudeModel;
  final bool enabled;
  final int rolloutPercent;
  final String minAppVersion;
  final String maxAppVersion;

  factory _RemoteBundleManifest.fromJson(Map<String, dynamic> json) {
    _RemoteModelAssetSpec parseAsset(
      Map<String, dynamic>? raw,
      String defaultFileName,
    ) {
      final map = raw ?? const <String, dynamic>{};
      final version = '${map['version'] ?? ''}'.trim();
      final url = '${map['url'] ?? ''}'.trim();
      final sha256Hex = '${map['sha256'] ?? ''}'.trim().toLowerCase();
      final fileName = '${map['file_name'] ?? defaultFileName}'.trim();
      if (version.isEmpty ||
          url.isEmpty ||
          sha256Hex.isEmpty ||
          fileName.isEmpty) {
        throw const FormatException(
            'Remote model manifest is missing asset fields.');
      }
      return _RemoteModelAssetSpec(
        version: version,
        url: url,
        sha256Hex: sha256Hex,
        fileName: fileName,
      );
    }

    final bundleVersion = '${json['bundle_version'] ?? ''}'.trim();
    if (bundleVersion.isEmpty) {
      throw const FormatException(
          'Remote model manifest is missing bundle_version.');
    }
    return _RemoteBundleManifest(
      bundleVersion: bundleVersion,
      applyModel: parseAsset(
        (json['apply_model'] as Map?)?.cast<String, dynamic>(),
        'mix_apply_classifier.onnx',
      ),
      magnitudeModel: parseAsset(
        (json['magnitude_model'] as Map?)?.cast<String, dynamic>(),
        'mix_magnitude_regressor.onnx',
      ),
      enabled: json['enabled'] != false,
      rolloutPercent:
          _safeInt(json['rollout_percent'], fallback: 100).clamp(0, 100),
      minAppVersion: '${json['min_app_version'] ?? ''}'.trim(),
      maxAppVersion: '${json['max_app_version'] ?? ''}'.trim(),
    );
  }
}

class RemoteMagnitudeModelManager {
  RemoteMagnitudeModelManager({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const String _prefsKeyLastCheckedAt =
      'mixroom.ai.magnitude_models.last_checked_at';
  static const String _prefsKeyBadRemoteBundleVersion =
      'mixroom.ai.magnitude_models.bad_bundle_version';

  final http.Client _httpClient;

  Future<void>? _refreshFuture;
  MagnitudeModelSelection? _cachedSelection;

  MagnitudeModelSelection bundledSelection({
    required String applyModelAsset,
    required String magnitudeModelAsset,
  }) {
    return MagnitudeModelSelection(
      source: 'bundled',
      bundleVersion: 'bundled-default',
      applyModelReference: applyModelAsset,
      magnitudeModelReference: magnitudeModelAsset,
      applyModelVersion: _basenameWithoutExtension(applyModelAsset),
      magnitudeModelVersion: _basenameWithoutExtension(magnitudeModelAsset),
    );
  }

  Future<void> refreshInBackground() async {
    if (kMixMagnitudeModelManifestUrl.trim().isEmpty) return;
    final inFlight = _refreshFuture;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _refreshRemoteBundle();
    _refreshFuture = future;
    try {
      await future;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<MagnitudeModelSelection?> installedSelection() async {
    final cached = _cachedSelection;
    if (cached != null) return cached;
    final metadata = await _readInstalledMetadata();
    if (metadata == null) return null;
    final selection = await _selectionFromMetadata(metadata);
    _cachedSelection = selection;
    return selection;
  }

  Future<void> markActivationFailed(
    MagnitudeModelSelection selection,
    Object error,
  ) async {
    if (!selection.isRemote) return;
    aiDebugLog(
      'onnx-mag-update',
      'remote activation failed bundle=${selection.bundleVersion} error=$error',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyBadRemoteBundleVersion,
      selection.bundleVersion,
    );
    await _deleteRemoteBundle(selection.bundleVersion);
    _cachedSelection = null;
    _trackUpdateEvent(
      status: 'activation_failed',
      bundleVersion: selection.bundleVersion,
      source: selection.source,
      applyModelVersion: selection.applyModelVersion,
      magnitudeModelVersion: selection.magnitudeModelVersion,
      errorCode: error.runtimeType.toString(),
    );
  }

  Future<void> dispose() async {
    // Background refresh is best-effort; don't tear down the HTTP client while a
    // non-blocking download may still be in flight during editor disposal.
  }

  Future<void> _refreshRemoteBundle() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_shouldRefreshNow(prefs)) {
      return;
    }
    await prefs.setString(
      _prefsKeyLastCheckedAt,
      DateTime.now().toUtc().toIso8601String(),
    );

    final manifestUri = Uri.tryParse(kMixMagnitudeModelManifestUrl.trim());
    if (manifestUri == null) {
      _trackUpdateEvent(
        status: 'manifest_invalid',
        errorCode: 'invalid_manifest_url',
      );
      return;
    }

    try {
      final response = await _httpClient
          .get(manifestUri)
          .timeout(Duration(seconds: kMixMagnitudeModelManifestTimeoutSeconds));
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
      final manifest = _RemoteBundleManifest.fromJson(
        decoded.cast<String, dynamic>(),
      );
      final current = await installedSelection();
      if (!manifest.enabled) {
        await _revertInstalledRemoteBundleIfNeeded(current);
        _trackUpdateEvent(
          status: 'manifest_disabled',
          bundleVersion: manifest.bundleVersion,
        );
        return;
      }
      final appVersion = await _currentAppVersion();
      if (!_isCompatibleWithAppVersion(manifest, appVersion)) {
        await _revertInstalledRemoteBundleIfNeeded(current);
        _trackUpdateEvent(
          status: 'app_version_incompatible',
          bundleVersion: manifest.bundleVersion,
        );
        return;
      }
      if (!_isEligibleForRollout(
        rolloutPercent: manifest.rolloutPercent,
        deviceId: AnalyticsService.instance.deviceId,
      )) {
        await _revertInstalledRemoteBundleIfNeeded(current);
        _trackUpdateEvent(
          status: 'rollout_skipped',
          bundleVersion: manifest.bundleVersion,
        );
        return;
      }
      final badBundleVersion =
          prefs.getString(_prefsKeyBadRemoteBundleVersion)?.trim() ?? '';
      if (badBundleVersion == manifest.bundleVersion) {
        await _revertInstalledRemoteBundleIfNeeded(current);
        aiDebugLog(
          'onnx-mag-update',
          'skipping known bad bundle ${manifest.bundleVersion}',
        );
        return;
      }
      if (current != null && current.bundleVersion == manifest.bundleVersion) {
        _trackUpdateEvent(
          status: 'up_to_date',
          bundleVersion: manifest.bundleVersion,
          source: current.source,
          applyModelVersion: current.applyModelVersion,
          magnitudeModelVersion: current.magnitudeModelVersion,
        );
        return;
      }

      await _installBundle(manifestUri, manifest);
      _cachedSelection = null;
      final installed = await installedSelection();
      _trackUpdateEvent(
        status: 'downloaded',
        bundleVersion: manifest.bundleVersion,
        source: installed?.source ?? 'remote',
        applyModelVersion:
            installed?.applyModelVersion ?? manifest.applyModel.version,
        magnitudeModelVersion:
            installed?.magnitudeModelVersion ?? manifest.magnitudeModel.version,
      );
    } on TimeoutException {
      _trackUpdateEvent(
          status: 'download_failed', errorCode: 'manifest_timeout');
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

  Future<void> _installBundle(
    Uri manifestUri,
    _RemoteBundleManifest manifest,
  ) async {
    final rootDir = await _rootDir();
    final versionDir = Directory(
      p.join(rootDir.path, _bundleDirectoryName(manifest.bundleVersion)),
    );
    final applyTarget =
        File(p.join(versionDir.path, manifest.applyModel.fileName));
    final magnitudeTarget =
        File(p.join(versionDir.path, manifest.magnitudeModel.fileName));

    await _downloadAndVerify(
      manifestUri: manifestUri,
      url: manifest.applyModel.url,
      expectedSha256: manifest.applyModel.sha256Hex,
      outputFile: applyTarget,
    );
    await _downloadAndVerify(
      manifestUri: manifestUri,
      url: manifest.magnitudeModel.url,
      expectedSha256: manifest.magnitudeModel.sha256Hex,
      outputFile: magnitudeTarget,
    );

    final metadata = <String, dynamic>{
      'bundle_version': manifest.bundleVersion,
      'installed_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'remote',
      'apply_model': <String, dynamic>{
        'version': manifest.applyModel.version,
        'path': applyTarget.path,
      },
      'magnitude_model': <String, dynamic>{
        'version': manifest.magnitudeModel.version,
        'path': magnitudeTarget.path,
      },
    };
    final metadataFile = File(p.join(rootDir.path, 'installed_bundle.json'));
    final tempFile = File('${metadataFile.path}.tmp');
    await tempFile.writeAsString(jsonEncode(metadata), flush: true);
    if (metadataFile.existsSync()) {
      await metadataFile.delete();
    }
    await tempFile.rename(metadataFile.path);
    await _pruneBundles(keepBundleVersion: manifest.bundleVersion);
  }

  Future<void> _downloadAndVerify({
    required Uri manifestUri,
    required String url,
    required String expectedSha256,
    required File outputFile,
  }) async {
    final uri = Uri.parse(url);
    if (!_isTrustedRemoteUri(manifestUri, uri)) {
      throw const FormatException('Model URL is outside the trusted origin.');
    }
    final request = http.Request('GET', uri);
    final response = await _httpClient.send(request).timeout(
          Duration(seconds: kMixMagnitudeModelManifestTimeoutSeconds * 2),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Model download failed (HTTP ${response.statusCode}).',
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
      throw const FormatException('Model checksum mismatch.');
    }
    if (outputFile.existsSync()) {
      await outputFile.delete();
    }
    await tempFile.rename(outputFile.path);
  }

  Future<Directory> _rootDir() async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory(p.join(supportDir.path, 'ai_models', 'magnitude'))
      ..createSync(recursive: true);
  }

  Future<Map<String, dynamic>?> _readInstalledMetadata() async {
    final rootDir = await _rootDir();
    final metadataFile = File(p.join(rootDir.path, 'installed_bundle.json'));
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

  Future<MagnitudeModelSelection?> _selectionFromMetadata(
    Map<String, dynamic> metadata,
  ) async {
    final bundleVersion = '${metadata['bundle_version'] ?? ''}'.trim();
    final source = '${metadata['source'] ?? 'remote'}'.trim();
    final applyModel =
        (metadata['apply_model'] as Map?)?.cast<String, dynamic>();
    final magnitudeModel =
        (metadata['magnitude_model'] as Map?)?.cast<String, dynamic>();
    final applyPath = '${applyModel?['path'] ?? ''}'.trim();
    final magnitudePath = '${magnitudeModel?['path'] ?? ''}'.trim();
    if (bundleVersion.isEmpty ||
        applyPath.isEmpty ||
        magnitudePath.isEmpty ||
        !File(applyPath).existsSync() ||
        !File(magnitudePath).existsSync()) {
      return null;
    }
    return MagnitudeModelSelection(
      source: source.isEmpty ? 'remote' : source,
      bundleVersion: bundleVersion,
      applyModelReference: applyPath,
      magnitudeModelReference: magnitudePath,
      applyModelVersion:
          '${applyModel?['version'] ?? _basenameWithoutExtension(applyPath)}'
              .trim(),
      magnitudeModelVersion:
          '${magnitudeModel?['version'] ?? _basenameWithoutExtension(magnitudePath)}'
              .trim(),
      installedAt: '${metadata['installed_at'] ?? ''}'.trim(),
    );
  }

  Future<void> _deleteRemoteBundle(String bundleVersion) async {
    if (bundleVersion.trim().isEmpty) return;
    final rootDir = await _rootDir();
    final versionDir = Directory(
      p.join(rootDir.path, _bundleDirectoryName(bundleVersion)),
    );
    if (versionDir.existsSync()) {
      await versionDir.delete(recursive: true);
    }
    final metadataFile = File(p.join(rootDir.path, 'installed_bundle.json'));
    if (metadataFile.existsSync()) {
      try {
        final metadata = jsonDecode(await metadataFile.readAsString());
        if (metadata is Map &&
            '${metadata['bundle_version'] ?? ''}'.trim() ==
                bundleVersion.trim()) {
          await metadataFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _pruneBundles({required String keepBundleVersion}) async {
    final rootDir = await _rootDir();
    if (!rootDir.existsSync()) return;
    final keepDirectoryName = _bundleDirectoryName(keepBundleVersion);
    await for (final entity in rootDir.list()) {
      if (entity is! Directory) continue;
      if (p.basename(entity.path) == keepDirectoryName) continue;
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _revertInstalledRemoteBundleIfNeeded(
    MagnitudeModelSelection? current,
  ) async {
    if (current == null || !current.isRemote) return;
    await _deleteRemoteBundle(current.bundleVersion);
    _cachedSelection = null;
  }

  bool _shouldRefreshNow(SharedPreferences prefs) {
    final lastCheckedRaw =
        prefs.getString(_prefsKeyLastCheckedAt)?.trim() ?? '';
    if (lastCheckedRaw.isEmpty) return true;
    final lastChecked = DateTime.tryParse(lastCheckedRaw);
    if (lastChecked == null) return true;
    return DateTime.now().toUtc().difference(lastChecked) >=
        Duration(hours: kMixMagnitudeModelRefreshIntervalHours);
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
    _RemoteBundleManifest manifest,
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
    final candidateScheme = candidateUri.scheme.toLowerCase();
    if (candidateScheme != 'https') return false;
    return candidateUri.host.toLowerCase() == manifestUri.host.toLowerCase() &&
        candidateUri.port == manifestUri.port;
  }

  void _trackUpdateEvent({
    required String status,
    String? bundleVersion,
    String? source,
    String? applyModelVersion,
    String? magnitudeModelVersion,
    String? errorCode,
  }) {
    final event = AnalyticsEvents.aiMagnitudeModelUpdate(
      status: status,
      mixMagnitudeModelBundleVersion: bundleVersion,
      mixMagnitudeModelSource: source,
      mixApplyModelVersion: applyModelVersion,
      mixMagnitudeRegressorVersion: magnitudeModelVersion,
      errorCode: errorCode,
    );
    unawaited(AnalyticsService.instance.track(event));
  }
}

String _bundleDirectoryName(String bundleVersion) {
  final normalized = bundleVersion.trim();
  if (normalized.isEmpty) return 'bundle';
  return normalized.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

int _safeInt(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim()) ?? fallback;
}

String _basenameWithoutExtension(String path) {
  final basename = p.basename(path.trim());
  if (basename.isEmpty) return '';
  final dotIndex = basename.lastIndexOf('.');
  if (dotIndex <= 0) return basename;
  return basename.substring(0, dotIndex);
}

int _compareVersions(String left, String right) {
  final a = _versionParts(left);
  final b = _versionParts(right);
  final maxLength = a.length > b.length ? a.length : b.length;
  for (int index = 0; index < maxLength; index++) {
    final av = index < a.length ? a[index] : 0;
    final bv = index < b.length ? b[index] : 0;
    if (av != bv) {
      return av.compareTo(bv);
    }
  }
  return 0;
}

List<int> _versionParts(String value) {
  final matches = RegExp(r'\d+').allMatches(value);
  return matches
      .map((match) => int.tryParse(match.group(0) ?? '') ?? 0)
      .toList(growable: false);
}
