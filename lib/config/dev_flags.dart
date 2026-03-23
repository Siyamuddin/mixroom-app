import 'package:flutter/foundation.dart';

/// Set to `true` while developing to skip auth and open Projects directly.
/// Ignored in release builds.
const bool kBypassAuthInDebug = false;

/// Set to `true` while developing to expose a manual dev-login button.
/// Ignored in release builds.
const bool kShowDevLoginButtonInDebug = false;

/// Set to `true` to stream verbose native JUCE logs into Dart console.
/// Keep this `false` for normal debug runs because high-volume native logs
/// can significantly slow first-use UI interactions on iOS/Xcode.
const bool kEnableNativeJuceLogsInDebug = false;

bool get isAuthBypassEnabled => kDebugMode && kBypassAuthInDebug;
bool get isDevLoginButtonEnabled => kDebugMode && kShowDevLoginButtonInDebug;
bool get isNativeJuceLoggingEnabled => kDebugMode && kEnableNativeJuceLogsInDebug;
