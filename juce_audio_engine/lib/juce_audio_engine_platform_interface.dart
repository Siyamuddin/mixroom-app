import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'juce_audio_engine_method_channel.dart';

abstract class JuceAudioEnginePlatform extends PlatformInterface {
  /// Constructs a JuceAudioEnginePlatform.
  JuceAudioEnginePlatform() : super(token: _token);

  static final Object _token = Object();

  static JuceAudioEnginePlatform _instance = MethodChannelJuceAudioEngine();

  /// The default instance of [JuceAudioEnginePlatform] to use.
  ///
  /// Defaults to [MethodChannelJuceAudioEngine].
  static JuceAudioEnginePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [JuceAudioEnginePlatform] when
  /// they register themselves.
  static set instance(JuceAudioEnginePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
