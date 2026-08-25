import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple MIDI loads propagate identity and reject cancelled installs', () {
    final plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final bridgeHeader = File(
      'juce_audio_engine/ios/Classes/JuceBridge.h',
    ).readAsStringSync();
    final bridge = File(
      'juce_audio_engine/ios/Classes/JuceBridge.mm',
    ).readAsStringSync();
    final engineHeader = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    final engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();

    expect(plugin, contains('@"cancelMidiClipLoad"'));
    expect(plugin, contains('loadRequestId:loadRequestId'));
    expect(bridgeHeader, contains('cancelMidiClipLoadObjC'));
    expect(bridge, contains('cancelMidiClipLoad('));
    expect(engineHeader, contains('midiLoadRequestId'));
    expect(engine, contains('requestWasCancelled()'));
    expect(engine, contains('clip.midiLoadRequestId != loadRequestId'));
    expect(engine, contains('return unloadClip(clipId);'));
  });

  test('native MIDI stall controls compile only in debug configurations', () {
    final plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final macPodspec = File(
      'juce_audio_engine/macos/juce_audio_engine.podspec',
    ).readAsStringSync();
    final iosPodspec = File(
      'juce_audio_engine/ios/juce_audio_engine.podspec',
    ).readAsStringSync();

    expect(
      plugin,
      contains(
        '#if MIXROOM_ENABLE_TEST_HOOKS\n'
        'static NSCondition *MixroomMidiClipLoadTestCondition',
      ),
    );
    expect(plugin, contains('@"debugConfigureMidiClipLoadStall"'));
    expect(
      macPodspec,
      contains(
        "'GCC_PREPROCESSOR_DEFINITIONS[config=Debug]' => "
        "'\$(inherited) MIXROOM_ENABLE_TEST_HOOKS=1'",
      ),
    );
    expect(
      iosPodspec,
      contains(
        "'GCC_PREPROCESSOR_DEFINITIONS[config=Debug]'   => "
        "'\$(inherited) JUCE_PLUGINHOST_AU=1 JUCE_IOS=1 "
        "JUCE_IOS_AUDIO_EXPLICIT_SAMPLERATES=44100 "
        "MIXROOM_ENABLE_TEST_HOOKS=1'",
      ),
    );
    expect(
      macPodspec,
      isNot(
        contains(
          "'GCC_PREPROCESSOR_DEFINITIONS[config=Release]' => "
          "'\$(inherited) MIXROOM_ENABLE_TEST_HOOKS=1'",
        ),
      ),
    );
  });
}
