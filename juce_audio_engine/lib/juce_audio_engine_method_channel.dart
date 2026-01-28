import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'juce_audio_engine_platform_interface.dart';

/// An implementation of [JuceAudioEnginePlatform] that uses method channels.
class MethodChannelJuceAudioEngine extends JuceAudioEnginePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('juce_audio_engine');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
