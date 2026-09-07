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
  test(
    'Apple MIDI processors consume bounded panic requests on audio thread',
    () {
      final header = File(
        'juce_audio_engine/ios/Classes/JuceEngine.h',
      ).readAsStringSync();
      final engine = File(
        'juce_audio_engine/ios/Classes/JuceEngine.cpp',
      ).readAsStringSync();

      expect(header, contains('enum class LiveMidiPanicMode'));
      expect(header, contains('liveOnly = 1'));
      expect(header, contains('full = 3'));
      expect(
        RegExp(
          r'requestLiveMidiPanic\(LiveMidiPanicMode mode\)',
        ).allMatches('$header\n$engine'),
        hasLength(2),
      );
      expect(
        RegExp(r'applyPendingLiveMidiPanic\(').allMatches('$header\n$engine'),
        hasLength(4),
      );

      for (final source in <String>[header, engine]) {
        final body = _functionBody(source, 'void applyPendingLiveMidiPanic(');
        expect(body, isNot(contains('std::lock_guard')));
        expect(body, isNot(contains('Logger')));
        expect(body, isNot(contains('juceLogToFlutter')));
        expect(body, isNot(contains('make_unique')));
        expect(body, isNot(contains('make_shared')));
        expect(body, isNot(contains('new ')));
        expect(body, isNot(contains('.resize(')));
        expect(body, isNot(contains('instrument->reset()')));
        expect(body, isNot(contains('processor->reset()')));
        expect(body, contains('dequeueLiveMidiEventLockFree'));
        expect(body, contains('liveMidiPanicRequest.exchange'));
      }
    },
  );

  test(
    'live-only preserves timeline while full panic sends MIDI safety CCs',
    () {
      final engine = File(
        'juce_audio_engine/ios/Classes/JuceEngine.cpp',
      ).readAsStringSync();
      final panic = _functionBody(
        engine,
        'void applyPendingLiveMidiPanic(',
      );

      final fullGuard = panic.indexOf('if ((request & fullMask) != fullMask)');
      final individualNoteOff = panic.indexOf('MidiMessage::noteOff');
      final allNotesOff = panic.indexOf('MidiMessage::allNotesOff');
      final allSoundOff = panic.indexOf('MidiMessage::allSoundOff');
      expect(fullGuard, greaterThanOrEqualTo(0));
      expect(individualNoteOff, greaterThanOrEqualTo(0));
      expect(individualNoteOff, lessThan(fullGuard));
      expect(allNotesOff, greaterThan(fullGuard));
      expect(allSoundOff, greaterThan(allNotesOff));
      expect(
        panic.indexOf('activeTimelineNotes.reset()'),
        greaterThan(fullGuard),
      );
    },
  );

  test(
    'native safety boundaries cover target, pause, shutdown and deactivation',
    () {
      final appDelegate = File(
        'macos/Runner/AppDelegate.swift',
      ).readAsStringSync();
      final swiftPlugin = File(
        'juce_audio_engine/macos/Classes/JuceAudioEnginePlugin.swift',
      ).readAsStringSync();
      final engine = File(
        'juce_audio_engine/ios/Classes/JuceEngine.cpp',
      ).readAsStringSync();
      final dartApi = File(
        'juce_audio_engine/lib/juce_audio_engine.dart',
      ).readAsStringSync();

      expect(engine, contains('previousClipId, LiveMidiPanicMode::liveOnly'));
      expect(
        engine,
        contains('requestLiveMidiPanicForAll(LiveMidiPanicMode::full)'),
      );
      expect(engine, contains('previewProcessorIdentity.lock()'));
      expect(appDelegate, contains('applicationDidResignActive'));
      expect(
        appDelegate,
        contains(
          'JuceAudioEnginePluginSwift.panicLiveMidiNotesForApplicationDeactivation()',
        ),
      );
      expect(
        swiftPlugin,
        contains('panicLiveMidiNotesForApplicationDeactivation'),
      );
      expect(dartApi, isNot(contains('panicLiveMidiNotes')));
    },
  );
}
