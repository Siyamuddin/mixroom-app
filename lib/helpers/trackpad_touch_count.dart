import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cached macOS trackpad finger count for desktop marquee gestures.
///
/// AppKit reports the count on mouse events when Three Finger Drag is on.
/// Tests override [debugTouchCount] so widget tests stay synchronous.
class TrackpadTouchCount {
  static const MethodChannel _channel = MethodChannel(
    'mixroom/trackpad_touches',
  );

  static int _cachedCount = 0;
  static bool _listening = false;

  /// When set, [current] returns this value instead of the native cache.
  @visibleForTesting
  static int? debugTouchCount;

  static int get current => debugTouchCount ?? _cachedCount;

  /// Starts listening for native touch-count updates.
  static void ensureListening() {
    if (_listening || kIsWeb) return;
    _listening = true;
    _channel.setMethodCallHandler(_handleNativeCall);
    if (Platform.isMacOS) {
      unawaited(_refreshFromNative());
    }
  }

  static Future<void> _refreshFromNative() async {
    try {
      final int? count = await _channel.invokeMethod<int>('getTouchCount');
      if (count != null) {
        _cachedCount = count;
      }
    } catch (_) {
      // Channel is absent in tests and on incomplete macOS embeds.
    }
  }

  static Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'touchCountChanged') return null;
    final Object? raw = call.arguments;
    if (raw is int) {
      _cachedCount = raw;
    } else if (raw is num) {
      _cachedCount = raw.toInt();
    }
    return null;
  }

  @visibleForTesting
  static void debugReset() {
    debugTouchCount = null;
    _cachedCount = 0;
  }
}
