import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _functionBody(String source, String signature) {
  final signatureStart = source.indexOf(signature);
  expect(signatureStart, greaterThanOrEqualTo(0));
  final bodyStart = source.indexOf('{', signatureStart);
  expect(bodyStart, greaterThan(signatureStart));

  var depth = 0;
  for (var index = bodyStart; index < source.length; index += 1) {
    if (source[index] == '{') depth += 1;
    if (source[index] != '}') continue;
    depth -= 1;
    if (depth == 0) return source.substring(bodyStart + 1, index);
  }
  fail('Unterminated function body for $signature');
}

void main() {
  test('Android MIDI loads prepare concurrently and reject stale work', () {
    final plugin = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/JuceAudioEnginePlugin.kt',
    ).readAsStringSync();
    final bridgeApi = File(
      'juce_audio_engine/android/src/main/java/com/mixroom/juce_audio_engine/JuceBridge.kt',
    ).readAsStringSync();
    final bridge = File(
      'juce_audio_engine/android/src/main/cpp/JuceBridge.cpp',
    ).readAsStringSync();
    final engine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.cpp',
    ).readAsStringSync();

    expect(plugin, contains('Executors.newFixedThreadPool(2)'));
    expect(plugin, contains('runMidiPreparationTask("loadMidiClip"'));
    expect(plugin, contains('args.longValue("loadRequestId")'));
    expect(plugin, contains('"cancelMidiClipLoad"'));
    expect(bridgeApi, contains('cancelMidiClipLoadJNI'));
    expect(bridge, contains('prepareBuiltInMidiClipLoad('));
    expect(bridge, contains('installPreparedMidiClipLoad(prepared)'));
    expect(engine, contains('isMidiClipLoadRequestCancelled('));
    expect(engine, contains('engineLifecycleGeneration'));
    expect(engine, contains('clip.midiLoadRequestId != loadRequestId'));

    final prepare = bridge.indexOf('prepareBuiltInMidiClipLoad(');
    final callSync = bridge.indexOf('mm->callSync(installMidiClip)', prepare);
    final install = bridge.indexOf('installPreparedMidiClipLoad(prepared)');
    expect(prepare, greaterThanOrEqualTo(0));
    expect(install, greaterThan(prepare));
    expect(callSync, greaterThan(install));
  });

  test('Android sampled definitions are immutable after publication', () {
    final header = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.h',
    ).readAsStringSync();

    expect(
      header,
      isNot(contains('mutable std::shared_ptr<const DecodedSamplePcm> sample')),
    );
    expect(header, isNot(contains('ensureSampledRegionLoaded(')));
    expect(header, contains('prepareSampledDefinitionForNotes('));
    expect(header, contains('std::make_shared<SampledDefinition>(*metadata)'));
    expect(header, contains('region.sample = std::move(sample)'));
  });

  test('Android panic boundaries cover replacement, pause, and shutdown', () {
    final header = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.h',
    ).readAsStringSync();
    final engine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.cpp',
    ).readAsStringSync();

    expect(header, contains('enum class LiveMidiPanicMode'));
    expect(header, contains('liveMidiPanicRequest.exchange('));
    expect(header, contains('dequeueLiveMidiEventLockFree'));
    expect(engine, contains('previousClipId, LiveMidiPanicMode::liveOnly'));
    expect(engine, contains('processor->requestLiveMidiPanic('));
    expect(
      engine,
      contains('requestLiveMidiPanicForAll(LiveMidiPanicMode::full)'),
    );
    expect(engine, contains('previewProcessorIdentity.lock()'));

    final panic = _functionBody(header, 'void applyPendingLiveMidiPanic(');
    expect(panic, isNot(contains('std::lock_guard')));
    expect(panic, isNot(contains('Logger')));
    expect(panic, isNot(contains('make_unique')));
    expect(panic, isNot(contains('make_shared')));
    expect(panic, isNot(contains('new ')));
    expect(panic, isNot(contains('.resize(')));
    expect(panic, isNot(contains('processor->reset()')));
  });

}
