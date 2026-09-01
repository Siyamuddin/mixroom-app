import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';

import '../config/app_update_config.dart';

/// Owns the native self-update lifecycle for direct-download desktop builds.
///
/// On macOS, auto_updater delegates download, signature verification, app
/// replacement, and relaunch to Sparkle. It never writes user projects or
/// application-support data.
class DesktopAutoUpdateService with UpdaterListener {
  DesktopAutoUpdateService._() {
    if (isSupported) {
      autoUpdater.addListener(this);
    }
  }

  static final DesktopAutoUpdateService instance = DesktopAutoUpdateService._();

  Future<bool>? _configuration;
  final ValueNotifier<bool> updateAvailable = ValueNotifier<bool>(false);

  bool get isSupported => !kIsWeb && Platform.isMacOS;

  bool get isConfigured =>
      isSupported && AppUpdateConfig.macosAppcastUrl.trim().isNotEmpty;

  /// Configures scheduled checks and performs one quiet startup check.
  Future<void> initialize() async {
    if (!await _ensureConfigured()) return;
    try {
      await autoUpdater.checkForUpdates(inBackground: true);
    } catch (error, stackTrace) {
      _reportFailure('background update check', error, stackTrace);
    }
  }

  /// Opens Sparkle's native check/update UI, including restart-to-install.
  Future<bool> checkForUpdates() async {
    if (!await _ensureConfigured()) return false;
    try {
      await autoUpdater.checkForUpdates(inBackground: false);
      return true;
    } catch (error, stackTrace) {
      _reportFailure('manual update check', error, stackTrace);
      return false;
    }
  }

  Future<bool> _ensureConfigured() {
    return _configuration ??= _configure();
  }

  Future<bool> _configure() async {
    if (!isConfigured) return false;

    final feedUrl = AppUpdateConfig.macosAppcastUrl.trim();
    final parsed = Uri.tryParse(feedUrl);
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      debugPrint('Desktop updater disabled: invalid HTTPS appcast URL.');
      return false;
    }

    try {
      await autoUpdater.setFeedURL(feedUrl);
      final configuredInterval =
          AppUpdateConfig.desktopUpdateCheckIntervalSeconds;
      final safeInterval = configuredInterval == 0
          ? 0
          : configuredInterval.clamp(3600, 604800);
      await autoUpdater.setScheduledCheckInterval(safeInterval);
      return true;
    } catch (error, stackTrace) {
      _reportFailure('configuration', error, stackTrace);
      return false;
    }
  }

  void _reportFailure(String operation, Object error, StackTrace stackTrace) {
    debugPrint('Desktop updater $operation failed: $error');
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'mixroom.desktop_updater',
        context: ErrorDescription('while running $operation'),
      ),
    );
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    updateAvailable.value = true;
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    updateAvailable.value = false;
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    updateAvailable.value = true;
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {}

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {}

  @override
  void onUpdaterError(UpdaterError? error) {}
}
