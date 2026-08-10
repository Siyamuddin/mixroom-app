import 'package:flutter/foundation.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BluetoothImplementationSessionV2 {
  const BluetoothImplementationSessionV2({
    required this.active,
    required this.nextSession,
    required this.selectionEnabled,
  });

  final BluetoothImplementationV2 active;
  final BluetoothImplementationV2 nextSession;
  final bool selectionEnabled;

  BluetoothImplementationSessionV2 withNextSession(
    BluetoothImplementationV2 implementation,
  ) {
    if (!selectionEnabled) return this;
    return BluetoothImplementationSessionV2(
      active: active,
      nextSession: implementation,
      selectionEnabled: true,
    );
  }
}

class BluetoothImplementationPreferencesV2 {
  const BluetoothImplementationPreferencesV2();

  static const String preferenceKey = 'internal.bluetooth_implementation_v2';

  Future<BluetoothImplementationSessionV2> loadSession({
    bool? debugOverride,
    TargetPlatform? platformOverride,
  }) async {
    final enabled = _selectionEnabled(
      debugOverride: debugOverride,
      platformOverride: platformOverride,
    );
    if (!enabled) {
      return const BluetoothImplementationSessionV2(
        active: BluetoothImplementationV2.legacy,
        nextSession: BluetoothImplementationV2.legacy,
        selectionEnabled: false,
      );
    }

    final preferences = await SharedPreferences.getInstance();
    final selected = _parse(preferences.getString(preferenceKey));
    return BluetoothImplementationSessionV2(
      active: selected,
      nextSession: selected,
      selectionEnabled: true,
    );
  }

  Future<bool> saveNextSession(
    BluetoothImplementationV2 implementation, {
    bool? debugOverride,
    TargetPlatform? platformOverride,
  }) async {
    if (!_selectionEnabled(
      debugOverride: debugOverride,
      platformOverride: platformOverride,
    )) {
      return false;
    }
    final preferences = await SharedPreferences.getInstance();
    return preferences.setString(preferenceKey, implementation.name);
  }

  bool _selectionEnabled({
    bool? debugOverride,
    TargetPlatform? platformOverride,
  }) {
    final platform = platformOverride ?? defaultTargetPlatform;
    return !kIsWeb &&
        (debugOverride ?? kDebugMode) &&
        (platform == TargetPlatform.macOS ||
            platform == TargetPlatform.android ||
            platform == TargetPlatform.iOS);
  }

  BluetoothImplementationV2 _parse(String? value) {
    return value == BluetoothImplementationV2.v2.name
        ? BluetoothImplementationV2.v2
        : BluetoothImplementationV2.legacy;
  }
}
