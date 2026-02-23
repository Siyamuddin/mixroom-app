import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:juce_audio_engine/juce_audio_engine_platform_interface.dart';
import 'package:juce_audio_engine/juce_audio_engine_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('juce_audio_engine');

  final JuceAudioEnginePlatform initialPlatform =
      JuceAudioEnginePlatform.instance;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getPlatformVersion') return '42';
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('$MethodChannelJuceAudioEngine is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelJuceAudioEngine>());
  });

  test('getPlatformVersion', () async {
    JuceAudioEngine juceAudioEnginePlugin = JuceAudioEngine();
    expect(await juceAudioEnginePlugin.getPlatformVersion(), '42');
  });
}
