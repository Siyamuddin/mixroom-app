import 'package:flutter/foundation.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';

class BluetoothImplementationSessionV2 {
  const BluetoothImplementationSessionV2({required this.active});

  final BluetoothImplementationV2 active;

  bool get allowsLegacyInputLifecycle =>
      active == BluetoothImplementationV2.legacy;
}

class BluetoothImplementationSessionResolverV2 {
  const BluetoothImplementationSessionResolverV2();

  Future<BluetoothImplementationSessionV2> loadSession({
    TargetPlatform? platformOverride,
  }) async {
    final platform = platformOverride ?? defaultTargetPlatform;
    if (!_isSupportedPlatform(platform)) {
      return const BluetoothImplementationSessionV2(
        active: BluetoothImplementationV2.legacy,
      );
    }

    return const BluetoothImplementationSessionV2(
      active: BluetoothImplementationV2.v2,
    );
  }

  bool _isSupportedPlatform(TargetPlatform platform) =>
      !kIsWeb &&
      (platform == TargetPlatform.macOS ||
          platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS);
}
