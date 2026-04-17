import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_update_config.dart';
import '../models/app_update_policy.dart';

class AppUpdatePromptService {
  AppUpdatePromptService({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const String _prefsKeyLastPromptedAt =
      'mixroom.app_update.last_prompted_at';
  static const String _prefsKeyLastPromptedVersion =
      'mixroom.app_update.last_prompted_version';
  static const String _prefsKeyCachedPolicyJson =
      'mixroom.app_update.cached_policy_json';
  static const String _prefsKeyCachedPolicyFetchedAt =
      'mixroom.app_update.cached_policy_fetched_at';

  final http.Client _httpClient;

  Future<AppUpdateDecision?> evaluate() async {
    if (kIsWeb) return null;

    final policy = await _loadCurrentPlatformPolicy();
    if (policy == null || !policy.isConfigured) {
      return null;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();
    if (currentVersion.isEmpty) {
      return null;
    }

    if (_compareVersions(currentVersion, policy.latestVersion) >= 0) {
      await clearPromptState();
      return AppUpdateDecision(
        type: AppUpdatePromptType.none,
        currentVersion: currentVersion,
        latestVersion: policy.latestVersion,
        minSupportedVersion: policy.minSupportedVersion,
        storeUrl: policy.storeUrl,
        promptCadenceHours: policy.promptCadenceHours,
      );
    }

    final promptType = policy.minSupportedVersion.isNotEmpty &&
            _compareVersions(currentVersion, policy.minSupportedVersion) < 0
        ? AppUpdatePromptType.force
        : AppUpdatePromptType.soft;

    if (promptType == AppUpdatePromptType.soft &&
        !(await shouldShowSoftPrompt(
          policy.latestVersion,
          policy.promptCadenceHours,
        ))) {
      return null;
    }

    return AppUpdateDecision(
      type: promptType,
      currentVersion: currentVersion,
      latestVersion: policy.latestVersion,
      minSupportedVersion: policy.minSupportedVersion,
      storeUrl: policy.storeUrl,
      promptCadenceHours: policy.promptCadenceHours,
    );
  }

  Future<AppVersionStatus?> getVersionStatus() async {
    if (kIsWeb) return null;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();
    if (currentVersion.isEmpty) {
      return null;
    }

    final policy = await _loadCurrentPlatformPolicy();
    final latestVersion = policy?.latestVersion.trim() ?? '';
    return AppVersionStatus(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      storeUrl: policy?.storeUrl.trim() ?? '',
      isUpdateAvailable: latestVersion.isNotEmpty &&
          _compareVersions(currentVersion, latestVersion) < 0,
    );
  }

  Future<bool> shouldShowSoftPrompt(
    String latestVersion,
    int promptCadenceHours,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final lastVersion =
        prefs.getString(_prefsKeyLastPromptedVersion)?.trim() ?? '';
    if (lastVersion != latestVersion.trim()) {
      return true;
    }

    final lastPromptedAtRaw =
        prefs.getString(_prefsKeyLastPromptedAt)?.trim() ?? '';
    if (lastPromptedAtRaw.isEmpty) {
      return true;
    }

    final lastPromptedAt = DateTime.tryParse(lastPromptedAtRaw)?.toUtc();
    if (lastPromptedAt == null) {
      return true;
    }

    final nextPromptAt = lastPromptedAt.add(
      Duration(hours: promptCadenceHours < 1 ? 1 : promptCadenceHours),
    );
    return DateTime.now().toUtc().isAfter(nextPromptAt);
  }

  Future<void> markPromptShown(AppUpdateDecision decision) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyLastPromptedAt,
      DateTime.now().toUtc().toIso8601String(),
    );
    await prefs.setString(
      _prefsKeyLastPromptedVersion,
      decision.latestVersion,
    );
  }

  Future<void> clearPromptState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyLastPromptedAt);
    await prefs.remove(_prefsKeyLastPromptedVersion);
  }

  Future<AppPlatformUpdatePolicy?> _loadCurrentPlatformPolicy() async {
    final remote = await _loadRemotePolicy();
    final platformPolicy = _selectCurrentPlatformPolicy(remote);
    if (platformPolicy != null && platformPolicy.isConfigured) {
      return _withConfigStoreFallback(platformPolicy);
    }

    final local = _loadConfigPolicy();
    if (local == null || !local.isConfigured) {
      return null;
    }
    return local;
  }

  Future<AppUpdatePolicySet?> _loadRemotePolicy() async {
    final cached = await _readFreshCachedPolicy();
    if (cached != null) {
      return cached;
    }

    final rawUrl = AppUpdateConfig.policyUrl.trim();
    if (rawUrl.isEmpty) {
      return _readCachedPolicy();
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return _readCachedPolicy();
    }

    try {
      final response = await _httpClient
          .get(uri)
          .timeout(Duration(seconds: AppUpdateConfig.policyTimeoutSeconds));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return _readCachedPolicy();
      }
      await _writeCachedPolicy(response.body);
      return AppUpdatePolicySet.fromJson(decoded.cast<String, dynamic>());
    } on TimeoutException {
      return _readCachedPolicy();
    } catch (_) {
      return _readCachedPolicy();
    }
  }

  Future<AppUpdatePolicySet?> _readFreshCachedPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    final fetchedAtRaw =
        prefs.getString(_prefsKeyCachedPolicyFetchedAt)?.trim() ?? '';
    if (fetchedAtRaw.isEmpty) {
      return null;
    }

    final fetchedAt = DateTime.tryParse(fetchedAtRaw)?.toUtc();
    if (fetchedAt == null) {
      return null;
    }

    final expiresAt = fetchedAt.add(
      Duration(
          hours: AppUpdateConfig.policyRefreshIntervalHours < 1
              ? 1
              : AppUpdateConfig.policyRefreshIntervalHours),
    );
    if (DateTime.now().toUtc().isAfter(expiresAt)) {
      return null;
    }

    return _readCachedPolicy();
  }

  Future<AppUpdatePolicySet?> _readCachedPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyCachedPolicyJson)?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return AppUpdatePolicySet.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedPolicy(String rawJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyCachedPolicyJson, rawJson);
    await prefs.setString(
      _prefsKeyCachedPolicyFetchedAt,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  AppPlatformUpdatePolicy? _selectCurrentPlatformPolicy(
    AppUpdatePolicySet? set,
  ) {
    if (set == null) return null;
    if (Platform.isIOS) return set.ios;
    if (Platform.isAndroid) return set.android;
    return null;
  }

  AppPlatformUpdatePolicy? _loadConfigPolicy() {
    if (Platform.isIOS) {
      final policy = AppPlatformUpdatePolicy(
        latestVersion: AppUpdateConfig.iosLatestVersion,
        minSupportedVersion: AppUpdateConfig.iosMinSupportedVersion,
        storeUrl: AppUpdateConfig.iosStoreUrl,
        promptCadenceHours: AppUpdateConfig.defaultPromptCadenceHours,
      );
      return policy.isConfigured ? policy : null;
    }
    if (Platform.isAndroid) {
      final policy = AppPlatformUpdatePolicy(
        latestVersion: AppUpdateConfig.androidLatestVersion,
        minSupportedVersion: AppUpdateConfig.androidMinSupportedVersion,
        storeUrl: AppUpdateConfig.androidStoreUrl,
        promptCadenceHours: AppUpdateConfig.defaultPromptCadenceHours,
      );
      return policy.isConfigured ? policy : null;
    }
    return null;
  }

  AppPlatformUpdatePolicy _withConfigStoreFallback(
    AppPlatformUpdatePolicy policy,
  ) {
    if (policy.storeUrl.trim().isNotEmpty) {
      return policy;
    }

    final fallbackStoreUrl = Platform.isIOS
        ? AppUpdateConfig.iosStoreUrl.trim()
        : AppUpdateConfig.androidStoreUrl.trim();
    if (fallbackStoreUrl.isEmpty) {
      return policy;
    }

    return AppPlatformUpdatePolicy(
      latestVersion: policy.latestVersion,
      minSupportedVersion: policy.minSupportedVersion,
      storeUrl: fallbackStoreUrl,
      promptCadenceHours: policy.promptCadenceHours,
    );
  }

  int _compareVersions(String left, String right) {
    final leftParts = _parseVersion(left);
    final rightParts = _parseVersion(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var i = 0; i < maxLength; i++) {
      final a = i < leftParts.length ? leftParts[i] : 0;
      final b = i < rightParts.length ? rightParts[i] : 0;
      if (a != b) {
        return a.compareTo(b);
      }
    }
    return 0;
  }

  List<int> _parseVersion(String version) {
    final normalized = version.split('+').first.trim();
    if (normalized.isEmpty) {
      return const <int>[0];
    }
    return normalized
        .split('.')
        .map(
          (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .toList(growable: false);
  }
}
