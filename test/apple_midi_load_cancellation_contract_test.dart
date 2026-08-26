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
    expect(engine, contains('isMidiClipLoadRequestCancelled('));
    expect(engine, contains('clip.midiLoadRequestId != loadRequestId'));
    expect(engine, contains('return unloadClip(clipId);'));
  });

  test('built-in MIDI preparation stays off the Apple message thread', () {
    final plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final bridge = File(
      'juce_audio_engine/ios/Classes/JuceBridge.mm',
    ).readAsStringSync();
    final engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();

    expect(plugin, contains('DISPATCH_QUEUE_CONCURRENT'));
    expect(plugin, contains('MixroomBuiltInMidiClipPreparationQueue()'));

    expect(engine, contains('id.startsWith("mixroom.")'));
    expect(engine, contains('id.startsWith("sfz.")'));
    expect(engine, contains('id.startsWith("sfz_asset:")'));
    expect(engine, contains('prepareBuiltInMidiClipLoad('));
    expect(
      engine,
      contains('graphBufferFramesAtomic.load(std::memory_order_acquire)'),
    );

    expect(bridge, contains('prepareBuiltInMidiClipLoad('));
    expect(bridge, contains('installPreparedMidiClipLoad('));
    expect(bridge, contains('mm->callSync(installPreparedMidiClip)'));
  });

  test('external and unknown MIDI identifiers retain the legacy load path', () {
    final plugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    final engine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    final bridge = File(
      'juce_audio_engine/ios/Classes/JuceBridge.mm',
    ).readAsStringSync();

    final classifierStart = engine.indexOf(
      'bool JuceEngine::isBuiltInMidiInstrumentIdentifier(',
    );
    final classifierEnd = engine.indexOf('\n}', classifierStart);
    expect(classifierStart, greaterThanOrEqualTo(0));
    expect(classifierEnd, greaterThan(classifierStart));
    final classifier = engine.substring(classifierStart, classifierEnd);
    expect(classifier, isNot(contains('audiounit')));
    expect(classifier, isNot(contains('.vst3')));

    expect(plugin, contains('MixroomMidiClipLoadQueue()'));
    expect(bridge, contains('mm->callSync(installMidiClip)'));
    expect(bridge, contains('JuceEngine::get().loadMidiClip('));
  });

  test('cached SFZ definitions remain immutable across concurrent loads', () {
    final engineHeader = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();

    expect(
      engineHeader,
      isNot(
        contains(
          'mutable std::shared_ptr<const DecodedSamplePcm> sample',
        ),
      ),
    );
    expect(engineHeader, isNot(contains('ensureSampledRegionLoaded(')));
    expect(engineHeader, contains('prepareSampledDefinitionForNotes('));
    expect(
      engineHeader,
      contains('std::make_shared<SampledDefinition>(*metadata)'),
    );
    expect(
      engineHeader,
      contains('region.sample = std::move(sample)'),
    );
  });

}
