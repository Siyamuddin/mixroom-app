import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:juce_audio_engine/juce_audio_engine_platform_interface.dart';
import 'package:juce_audio_engine/juce_audio_engine_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockJuceAudioEnginePlatform
    with MockPlatformInterfaceMixin
    implements JuceAudioEnginePlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final JuceAudioEnginePlatform initialPlatform = JuceAudioEnginePlatform.instance;

  test('$MethodChannelJuceAudioEngine is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelJuceAudioEngine>());
  });

  test('getPlatformVersion', () async {
    JuceAudioEngine juceAudioEnginePlugin = JuceAudioEngine();
    MockJuceAudioEnginePlatform fakePlatform = MockJuceAudioEnginePlatform();
    JuceAudioEnginePlatform.instance = fakePlatform;

    expect(await juceAudioEnginePlugin.getPlatformVersion(), '42');
  });
}
