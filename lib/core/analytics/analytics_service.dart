import 'package:mixroom/config/hackathon_config.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:mixroom/config/analytics_config.dart';
import 'package:mixroom/core/analytics/analytics_events.dart';
import 'package:mixroom/core/privacy/privacy_preferences.dart';

class AnalyticsService with WidgetsBindingObserver {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  static const String _deviceIdPreferenceKey = 'mixroom.analytics.device_id.v1';
  static const List<String> _aiCapabilities = <String>[
    'daw.project_edit.set_tempo',
    'daw.sample_insert.library',
    'daw.midi_compose.instrument_insert',
    'daw.midi_compose.transpose_notes',
    'daw.midi_compose.audio_to_midi',
    'daw.clip_edit.pitch_shift',
  ];
  static List<String> get aiCapabilities => _aiCapabilities;

  final Posthog _posthog = Posthog();
  final Uuid _uuid = const Uuid();

  SharedPreferences? _prefs;
  PackageInfo? _packageInfo;

  bool _initialized = false;
  bool _postHogReady = false;
  bool _collectionEnabled = !HackathonConfig.enabled;
  String _deviceId = '';
  String? _userId;
  String? _subscriptionTier;
  String? _musicProfile;
  String? _lastPersonPropertiesFingerprint;
  String _sessionId = '';
  DateTime? _sessionStartedAt;
  String? _lastScreenName;

  bool get isCollectionEnabled => _collectionEnabled;
  String get deviceId => _deviceId;
  String get sessionId => _sessionId;
  String? get userId => _userId;
  String get distinctId =>
      _userId?.trim().isNotEmpty == true ? _userId! : _deviceId;
  String get appVersion {
    final info = _packageInfo;
    if (info == null) return '';
    return '${info.version}+${info.buildNumber}';
  }

  String get platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  String get environment => AnalyticsConfig.environment;

  Future<void> initialize() async {
    if (HackathonConfig.enabled) {
      _collectionEnabled = false;
      _initialized = true;
      return;
    }
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _packageInfo = await PackageInfo.fromPlatform();
    _collectionEnabled =
        await PrivacyPreferences.isAnalyticsAndCrashDiagnosticsEnabled();
    _deviceId = _prefs?.getString(_deviceIdPreferenceKey)?.trim() ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = _uuid.v4();
      await _prefs?.setString(_deviceIdPreferenceKey, _deviceId);
    }

    WidgetsBinding.instance.addObserver(this);
    _initialized = true;

    if (_collectionEnabled) {
      await _ensurePostHogReady();
    }

    _startSession(launchSource: 'cold_start', trackOpen: true);
  }

  Map<String, dynamic> buildRequestContext() {
    final locale =
        WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
    final clientContext = <String, Object?>{
      'app_version': appVersion,
      'platform': platform,
      'environment': environment,
      'locale': locale,
      'ai_capabilities': _aiCapabilities,
      if (_collectionEnabled) 'device_id': _deviceId,
      if (_collectionEnabled) 'distinct_id': distinctId,
      if (_collectionEnabled) 'session_id': _sessionId,
    };

    return <String, dynamic>{
      'analytics_enabled': _collectionEnabled,
      'client_context': clientContext,
    };
  }

  Future<void> setCollectionEnabled(bool enabled) async {
    if (HackathonConfig.enabled) return;
    await PrivacyPreferences.setAnalyticsAndCrashDiagnosticsEnabled(enabled);
    _collectionEnabled = enabled;
    if (enabled) {
      await _ensurePostHogReady();
      if (_userId != null && _userId!.trim().isNotEmpty) {
        await identifyUser(
          userId: _userId!,
          email: null,
          name: null,
        );
      }
      return;
    }

    if (_postHogReady) {
      try {
        await _posthog.reset();
        _lastPersonPropertiesFingerprint = null;
      } catch (_) {}
    }
  }

  Future<void> identifyUser({
    required String userId,
    String? email,
    String? name,
  }) async {
    final nextUserId = userId.trim().isEmpty ? null : userId.trim();
    if (_userId != nextUserId) {
      _lastPersonPropertiesFingerprint = null;
    }
    _userId = nextUserId;
    if (!_collectionEnabled) return;
    await _ensurePostHogReady();
    if (!_postHogReady || _userId == null) return;

    try {
      await _posthog.identify(
        userId: _userId!,
        userProperties: <String, Object>{
          if ((email ?? '').trim().isNotEmpty) 'email': email!.trim(),
          if ((name ?? '').trim().isNotEmpty) 'name': name!.trim(),
          'platform': platform,
          'app_version': appVersion,
          'environment': environment,
          if ((_subscriptionTier ?? '').trim().isNotEmpty)
            'subscription_tier': _subscriptionTier!,
          if ((_musicProfile ?? '').trim().isNotEmpty)
            'music_profile': _musicProfile!,
          if ((_musicProfile ?? '').trim().isNotEmpty)
            'user_type': _musicProfile!,
        },
      );
    } catch (_) {}
  }

  Future<void> resetUser() async {
    _userId = null;
    _subscriptionTier = null;
    _musicProfile = null;
    _lastPersonPropertiesFingerprint = null;
    if (!_postHogReady) return;
    try {
      await _posthog.reset();
    } catch (_) {}
  }

  void setSubscriptionTier(String? tier) {
    final normalized = (tier ?? '').trim();
    final nextTier = normalized.isEmpty ? null : normalized;
    if (_subscriptionTier == nextTier) return;
    _subscriptionTier = nextTier;
    unawaited(_syncPersonProperties());
  }

  void setMusicProfile(String? musicProfile) {
    final nextMusicProfile = _normalizeMusicProfile(musicProfile);
    if (_musicProfile == nextMusicProfile) return;
    _musicProfile = nextMusicProfile;
    unawaited(_syncPersonProperties());
  }

  Future<void> track(AnalyticsEvent event) async {
    if (!_collectionEnabled) return;
    await _ensurePostHogReady();
    if (!_postHogReady) return;

    try {
      await _posthog.capture(
        eventName: event.name,
        properties: _buildProperties(event.properties),
      );
    } catch (_) {}
  }

  Future<void> trackScreen(
    String screenName, {
    Map<String, Object?> properties = const <String, Object?>{},
    bool allowDuplicates = false,
  }) async {
    final normalized = screenName.trim();
    if (normalized.isEmpty) return;
    if (!allowDuplicates && _lastScreenName == normalized) {
      return;
    }

    _lastScreenName = normalized;
    if (!_collectionEnabled) return;
    await _ensurePostHogReady();
    if (!_postHogReady) return;

    try {
      await _posthog.screen(
        screenName: normalized,
        properties: _buildProperties(<String, Object?>{
          'screen_name': normalized,
          ...properties,
        }),
      );
    } catch (_) {}
  }

  Future<void> trackFirstProjectCreated({
    required String projectId,
  }) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final scope = distinctId.trim().isNotEmpty ? distinctId : _deviceId;
    final key = 'mixroom.analytics.first_project_created.$scope';
    if (prefs.getBool(key) == true) return;
    await track(AnalyticsEvents.firstProjectCreated(projectId: projectId));
    await prefs.setBool(key, true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_sessionStartedAt == null) {
          _startSession(launchSource: 'resume', trackOpen: true);
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _endSession();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _ensurePostHogReady() async {
    if (HackathonConfig.enabled) return;
    if (_postHogReady || !AnalyticsConfig.hasPostHog) return;
    try {
      final config = PostHogConfig(AnalyticsConfig.postHogApiKey)
        ..host = AnalyticsConfig.postHogHost
        ..captureApplicationLifecycleEvents = false
        ..debug = !kReleaseMode;
      await _posthog.setup(config);
      _postHogReady = true;
    } catch (_) {
      _postHogReady = false;
    }
  }

  Map<String, Object> _buildProperties(Map<String, Object?> eventProperties) {
    return Map<String, Object>.fromEntries(
      <MapEntry<String, Object?>>[
        MapEntry<String, Object?>('user_id', _userId),
        MapEntry<String, Object?>('distinct_id', distinctId),
        MapEntry<String, Object?>('device_id', _deviceId),
        MapEntry<String, Object?>('session_id', _sessionId),
        MapEntry<String, Object?>('app_version', appVersion),
        MapEntry<String, Object?>('platform', platform),
        MapEntry<String, Object?>('environment', environment),
        MapEntry<String, Object?>(
          'timestamp',
          DateTime.now().toUtc().toIso8601String(),
        ),
        MapEntry<String, Object?>(
          'locale',
          WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
        ),
        MapEntry<String, Object?>('subscription_tier', _subscriptionTier),
        MapEntry<String, Object?>('music_profile', _musicProfile),
        MapEntry<String, Object?>('user_type', _musicProfile),
        ...eventProperties.entries,
      ].where((entry) {
        final value = entry.value;
        if (value == null) return false;
        if (value is String) return value.trim().isNotEmpty;
        return true;
      }).map(
        (entry) => MapEntry<String, Object>(entry.key, entry.value as Object),
      ),
    );
  }

  void _startSession({
    required String launchSource,
    required bool trackOpen,
  }) {
    _sessionId = _uuid.v4();
    _sessionStartedAt = DateTime.now().toUtc();
    if (!trackOpen) return;
    unawaited(track(AnalyticsEvents.appOpened(
      sessionId: _sessionId,
      launchSource: launchSource,
    )));
    unawaited(track(AnalyticsEvents.sessionStarted(sessionId: _sessionId)));
  }

  void _endSession() {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) return;
    final durationMs =
        DateTime.now().toUtc().difference(startedAt).inMilliseconds;
    _sessionStartedAt = null;
    unawaited(track(AnalyticsEvents.sessionEnded(
      sessionId: _sessionId,
      durationMs: durationMs,
    )));
  }

  String? _normalizeMusicProfile(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _syncPersonProperties() async {
    if (!_collectionEnabled) return;
    await _ensurePostHogReady();
    if (!_postHogReady || _userId == null) return;

    final properties = _buildPersonProperties();
    final fingerprint = _fingerprintPersonProperties(
      userId: _userId!,
      properties: properties,
    );
    if (_lastPersonPropertiesFingerprint == fingerprint) {
      return;
    }

    try {
      await _posthog.setPersonProperties(
        userPropertiesToSet: properties,
      );
      _lastPersonPropertiesFingerprint = fingerprint;
    } catch (_) {}
  }

  Map<String, Object> _buildPersonProperties() {
    return <String, Object>{
      'platform': platform,
      'app_version': appVersion,
      'environment': environment,
      if ((_subscriptionTier ?? '').trim().isNotEmpty)
        'subscription_tier': _subscriptionTier!,
      if ((_musicProfile ?? '').trim().isNotEmpty)
        'music_profile': _musicProfile!,
      if ((_musicProfile ?? '').trim().isNotEmpty) 'user_type': _musicProfile!,
    };
  }

  String _fingerprintPersonProperties({
    required String userId,
    required Map<String, Object> properties,
  }) {
    final keys = properties.keys.toList()..sort();
    final buffer = StringBuffer(userId);
    for (final key in keys) {
      buffer
        ..write('|')
        ..write(key)
        ..write('=')
        ..write(properties[key]);
    }
    return buffer.toString();
  }
}
