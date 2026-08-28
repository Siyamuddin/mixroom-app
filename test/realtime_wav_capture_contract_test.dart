import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String capture;
  late String appleEngine;
  late String androidEngine;
  late String appleHeader;
  late String androidHeader;
  late String applePlugin;
  late String androidPlugin;
  late String editor;

  setUpAll(() {
    capture = File(
      'juce_audio_engine/native/RealtimeWavCapture.h',
    ).readAsStringSync();
    appleEngine = File(
      'juce_audio_engine/ios/Classes/JuceEngine.cpp',
    ).readAsStringSync();
    androidEngine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.cpp',
    ).readAsStringSync();
    appleHeader = File(
      'juce_audio_engine/ios/Classes/JuceEngine.h',
    ).readAsStringSync();
    androidHeader = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.h',
    ).readAsStringSync();
    applePlugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
    androidPlugin = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/JuceAudioEnginePlugin.kt',
    ).readAsStringSync();
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  test('Apple and Android use one shared bounded threaded WAV capture', () {
    expect(appleHeader, contains('../../native/RealtimeWavCapture.h'));
    expect(androidHeader, contains('../../../../native/RealtimeWavCapture.h'));
    expect(appleHeader, contains('RealtimeWavCapture wavCapture;'));
    expect(androidHeader, contains('RealtimeWavCapture wavCapture;'));
    expect(capture, contains('AudioFormatWriter::ThreadedWriter'));
    expect(capture, contains('TimeSliceThread'));
    expect(capture, contains('sampleRate * 2.0'));
    expect(capture, contains('(unsigned int)channelCount,\n            24,'));
    expect(capture, contains('channelCount < 1 || channelCount > 2'));
  });

  test('capture callback only validates, meters, and enqueues', () {
    final start = capture.indexOf('void capture(');
    final end = capture.indexOf('\nprivate:', start);
    final callback = capture.substring(start, end);

    expect(callback, contains('std::array<const float *, 2> selected'));
    expect(callback, contains('writer->write(selected.data(), numSamples)'));
    expect(callback, contains('attemptedSamples.fetch_add'));
    expect(callback, contains('acceptedSamples.fetch_add'));
    expect(callback, contains('droppedSamples.fetch_add'));
    expect(callback, contains('invalidBlockCount.fetch_add'));
    expect(callback, contains('publishPeak(peak)'));
    expect(callback, isNot(contains('AudioBuffer<')));
    expect(callback, isNot(contains('AudioFormatWriter::write')));
    expect(callback, isNot(contains('createOutputStream')));
    expect(callback, isNot(contains('deleteFile')));
    expect(callback, isNot(contains('recordLock')));
    expect(callback, isNot(contains('.wait(')));
    expect(callback, isNot(contains('stopThread')));
    expect(callback, isNot(contains('juceLog')));
  });

  test('stop closes admission before one event-based callback drain', () {
    final start = capture.indexOf('StopResult stop(bool discardFile = false)');
    final end = capture.indexOf('\n    bool isActive()', start);
    final stop = capture.substring(start, end);

    final close = stop.indexOf(
      'admissionOpen.store(false, std::memory_order_release)',
    );
    final wait = stop.indexOf('callbacksDrained.wait()');
    final destroy = stop.indexOf('threadedWriter.reset()');
    expect(close, greaterThanOrEqualTo(0));
    expect(wait, greaterThan(close));
    expect(destroy, greaterThan(wait));
    expect(stop, isNot(contains('while (')));
    expect(stop, isNot(contains('sleep')));
    expect(stop, contains('validateFinalizedFile(result.acceptedSamples)'));
  });

  test('both native callbacks have no direct writer or temporary buffer', () {
    for (final engine in <String>[appleEngine, androidEngine]) {
      final inputStart = engine.indexOf('void JuceEngine::captureInput');
      final outputEnd = engine.indexOf(
        '\nvoid JuceEngine::setMasterMeterEnabled',
        inputStart,
      );
      final callbacks = engine.substring(inputStart, outputEnd);
      expect(callbacks, contains('wavCapture.capture'));
      expect(callbacks, isNot(contains('AudioBuffer<float>')));
      expect(callbacks, isNot(contains('recorderWriter')));
      expect(callbacks, isNot(contains('recordLock')));
      expect(callbacks, isNot(contains('writeFromAudioSampleBuffer')));
    }
  });

  test('finalization is off the iOS and Android Flutter UI paths', () {
    final iosStop = applePlugin.indexOf(
      'else if ([call.method isEqualToString:@"stopRecording"])',
    );
    final iosEnd = applePlugin.indexOf(
      'else if ([call.method isEqualToString:@"restoreBluetoothPlaybackAfterRecordingStop"])',
      iosStop,
    );
    final iosBlock = applePlugin.substring(iosStop, iosEnd);
    expect(iosBlock, contains('dispatch_async(MixroomIOSLifecycleQueue()'));
    expect(iosBlock, contains('[JuceBridge stopRecordingObjC]'));

    final androidStop = androidPlugin.indexOf('"stopRecording" -> {');
    final androidEnd = androidPlugin.indexOf(
      '"restoreBluetoothPlaybackAfterRecordingStop" -> {',
      androidStop,
    );
    final androidBlock = androidPlugin.substring(androidStop, androidEnd);
    expect(androidBlock, contains('runHeavyTask("stopRecording", result)'));
    expect(androidBlock, contains('JuceBridge.stopRecordingJNI()'));

    final androidNative = File(
      'juce_audio_engine/android/src/main/cpp/JuceBridge.cpp',
    ).readAsStringSync();
    final nativeStop = androidNative.indexOf(
      'JuceBridge_stopRecordingJNI(JNIEnv *env, jclass)',
    );
    final nativeStopEnd = androidNative.indexOf(
      'JuceBridge_stopRecordingWithoutPlaybackRestoreJNI',
      nativeStop,
    );
    final nativeStopBlock = androidNative.substring(nativeStop, nativeStopEnd);
    expect(
      nativeStopBlock.indexOf('finalizeRecordingCapture()'),
      lessThan(nativeStopBlock.indexOf('callSync')),
    );
  });

  test('unreliable captures cannot be inserted or leave partial files', () {
    expect(editor, contains('if (!captureResult.success)'));
    expect(
      editor,
      contains('Recording could not be saved reliably. Please try again.'),
    );
    final failure = editor.indexOf('if (!captureResult.success)');
    final insert = editor.indexOf('// 2) Insert recorded clip', failure);
    expect(failure, greaterThanOrEqualTo(0));
    expect(insert, greaterThan(failure));
    final rejectedCapture = editor.substring(failure, insert);
    expect(
      rejectedCapture,
      contains('await _discardPendingUnpublishedRecordingFile()'),
    );
    expect(rejectedCapture, contains('return;'));
  });

  test('only the bounded capture diagnostic vocabulary is used', () {
    for (final code in <String>[
      'ok',
      'capture_overrun',
      'capture_shape_invalid',
      'writer_finalize_failed',
    ]) {
      expect(capture, contains('"$code"'));
    }
  });
}
