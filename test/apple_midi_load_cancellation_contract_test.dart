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
}
