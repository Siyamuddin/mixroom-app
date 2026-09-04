import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String editor;
  late String appleEngine;
  late String androidEngine;
  late String dormantAndroidTimeline;
  late String appleRenderer;
  late String androidRenderer;
  late String appleBridge;
  late String androidBridge;

  setUpAll(() {
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    appleEngine =
        File('juce_audio_engine/ios/Classes/JuceEngine.h').readAsStringSync();
    androidEngine = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.h',
    ).readAsStringSync();
    dormantAndroidTimeline = File(
      'juce_audio_engine/android/src/main/cpp/TimelineMidiClipProcessor.h',
    ).readAsStringSync();
    appleRenderer = File(
      'juce_audio_engine/ios/Classes/InstrumentRenderers.cpp',
    ).readAsStringSync();
    androidRenderer = File(
      'juce_audio_engine/android/src/main/cpp/InstrumentRenderers.cpp',
    ).readAsStringSync();
    appleBridge =
        File('juce_audio_engine/ios/Classes/JuceEngine.cpp').readAsStringSync();
    androidBridge = File(
      'juce_audio_engine/android/src/main/cpp/JuceEngine.cpp',
    ).readAsStringSync();
  });

  String methodBody(String signature, String nextSignature) {
    final start = editor.indexOf(signature);
    final end = editor.indexOf(nextSignature, start + signature.length);
    expect(start, greaterThanOrEqualTo(0), reason: 'Missing $signature');
    expect(end, greaterThan(start), reason: 'Missing boundary $nextSignature');
    return editor.substring(start, end);
  }

  test('Granularizer offline envelope uses stored decay and sustain', () {
    final body = methodBody(
      'Future<bool> _renderInstrumentClipWithGranularizer({',
      'Future<bool> _renderInstrumentClipWithSfz({',
    );

    expect(body, contains("params['decayMs'] ?? 80.0"));
    expect(body, contains("params['sustainLevel'] ?? 0.92"));
    expect(body, contains('decaySec: decaySec'));
    expect(body, contains('sustainLevel: sustainLevel'));
    expect(body, isNot(contains('decaySec: 0.08')));
    expect(body, isNot(contains('sustainLevel: 0.92')));
  });

  test('SFZ offline envelope preserves an explicit zero attack', () {
    final body = methodBody(
      'Future<bool> _renderInstrumentClipWithSfz({',
      'Future<void> _renderInstrumentClipWithDartSynth({',
    );

    expect(body, contains("final attackOverrideMs = params['attackMs'];"));
    expect(
      body,
      contains('attackOverrideMs != null && attackOverrideMs.isFinite'),
    );
    expect(body, contains('attackOverrideSec ??'));
    expect(body, isNot(contains('attackOverrideSec > 0')));
  });

  test('Dart renderers preserve exact zero-time envelope stages', () {
    expect(editor, contains('if (safeAttack > 0.0 && ageSec < safeAttack)'));
    expect(editor, contains('if (safeDecay > 0.0 && decayAge < safeDecay)'));
    expect(editor, contains('safeSustain = sustainLevel.clamp(0.0, 1.0)'));
    expect(editor, contains('if (safeRelease <= 0.0) return 0.0;'));
    expect(editor, contains("final releaseOverrideMs = params['releaseMs'];"));
    expect(editor, contains('releaseOverrideSec ??'));
    expect(editor, contains('releaseSamples = math.max(0,'));
    expect(editor, isNot(contains('safeRelease = math.max(0.02')));
    expect(editor, isNot(contains('releaseOverrideSec > 0')));
  });

  test('native timeline engines preserve exact zero-time stages', () {
    for (final source in <String>[
      appleEngine,
      androidEngine,
      dormantAndroidTimeline,
    ]) {
      expect(source, contains('if (attackSec > 0.0 && ageSec < attackSec)'));
      expect(source, contains('if (decaySec > 0.0 && decayAge < decaySec)'));
      expect(source, contains('juce::jlimit(0.0, 1.0, sustainLevel)'));
      expect(source, contains('if (releaseSec <= 0.0)'));
      expect(source, contains('if (voiceReleaseSec > 0.0)'));
      expect(source, contains('juce::jlimit(0.0, 2400.0'));
      expect(source, isNot(contains('juce::jlimit(20.0, 2400.0')));
      expect(
        source,
        isNot(contains('juce::jmax(0.02, voice.sampledReleaseSec)')),
      );
    }
  });

  test('offline native renderers and tail estimates accept zero release', () {
    for (final source in <String>[appleRenderer, androidRenderer]) {
      expect(source, contains('if (releaseSec <= 0.0)'));
      expect(source, contains('juce::jlimit(0.0, 1.0, sustainLevel)'));
      expect(source, contains('juce::jlimit(0.0, 2400.0'));
      expect(source, contains('releaseSamples = juce::jmax(0,'));
      expect(source, isNot(contains('juce::jlimit(20.0, 2400.0')));
    }
    for (final source in <String>[appleBridge, androidBridge]) {
      expect(source, contains('releaseMs = juce::jlimit(0.0, 4000.0'));
      expect(source, isNot(contains('releaseMs = juce::jlimit(10.0, 4000.0')));
    }
  });
}
