import 'dart:io';

import 'package:flutter/services.dart';

enum AppHapticImpact { light, medium, heavy }

class AppHaptics {
  AppHaptics._();

  static const MethodChannel _channel = MethodChannel('mixroom/haptics');

  static Future<void> impact(AppHapticImpact impact) async {
    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod<void>('impact', {'style': impact.name});
        return;
      } catch (_) {
        // Fallback to Flutter's platform haptics if native channel isn't ready.
      }
    }

    switch (impact) {
      case AppHapticImpact.light:
        await HapticFeedback.lightImpact();
      case AppHapticImpact.medium:
        await HapticFeedback.mediumImpact();
      case AppHapticImpact.heavy:
        await HapticFeedback.heavyImpact();
    }
  }
}
