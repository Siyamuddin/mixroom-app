import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JUCE graph builder indexes final consumers with a debug oracle', () {
    final source = File(
      'juce_audio_engine/android/src/main/cpp/juce/modules/'
      'juce_audio_processors/processors/juce_AudioProcessorGraph.cpp',
    ).readAsStringSync();

    expect(source, contains('buildLastConsumerIndices (c);'));
    expect(source, contains('lastConsumerIndices'));
    expect(source, contains('lastConsumerIndex >= stepIndex'));
    expect(source, contains('isBufferNeededLaterSlow'));
    expect(source, contains('MIXROOM_VERIFY_GRAPH_LIVENESS'));
    expect(source, isNot(contains('PRO17_GRAPH_REBUILD_PROFILE')));
  });

  test('iOS vendor rebuild includes the canonical audio-processors module', () {
    final script = File(
      'tools/ios/rebuild_juce_vendor_libraries.sh',
    ).readAsStringSync();
    final wrapper = File(
      'tools/ios/juce_vendor/include_juce_audio_processors.mm',
    ).readAsStringSync();

    expect(wrapper, contains('juce_audio_processors.cpp'));
    expect(script, contains('DEVICE_DEBUG_PROCESSORS_O'));
    expect(script, contains('DEVICE_RELEASE_PROCESSORS_O'));
    expect(script, contains('SIM_ARM64_PROCESSORS_O'));
    expect(script, contains('SIM_X64_PROCESSORS_O'));
    expect(script, contains('JuceModule_juce_audio_processors.o'));
  });
}
