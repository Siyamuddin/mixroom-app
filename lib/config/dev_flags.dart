import 'package:flutter/foundation.dart';

/// Set to `true` while developing to skip auth and open Projects directly.
/// Ignored in release builds.
const bool kBypassAuthInDebug = false;

/// Set to `true` while developing to expose a manual dev-login button.
/// Ignored in release builds.
const bool kShowDevLoginButtonInDebug = false;

/// Optional debug-only credentials for one-tap Dev Login.
/// Pass at runtime via:
/// `--dart-define=DEV_LOGIN_EMAIL=you@example.com`
/// `--dart-define=DEV_LOGIN_PASSWORD=your-password`
const String kDevLoginEmail = String.fromEnvironment('DEV_LOGIN_EMAIL');
const String kDevLoginPassword = String.fromEnvironment('DEV_LOGIN_PASSWORD');

/// Set to `true` to stream verbose native JUCE logs into Dart console.
/// Keep this `false` for normal debug runs because high-volume native logs
/// can significantly slow first-use UI interactions on iOS/Xcode.
const bool kEnableNativeJuceLogsInDebug = true;

bool get isAuthBypassEnabled => kDebugMode && kBypassAuthInDebug;
bool get isDevLoginButtonEnabled => kDebugMode && kShowDevLoginButtonInDebug;
bool get hasConfiguredDevLoginCredentials =>
    kDebugMode && kDevLoginEmail.trim().isNotEmpty && kDevLoginPassword.isNotEmpty;
bool get isNativeJuceLoggingEnabled => kDebugMode && kEnableNativeJuceLogsInDebug;
