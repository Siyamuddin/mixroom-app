import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/midi_recording_generation.dart';

void main() {
  test('invalidation rejects work captured by an older recording', () {
    final generation = MidiRecordingGeneration();
    final captured = generation.current;

    expect(generation.isCurrent(captured), isTrue);

    generation.invalidate();

    expect(generation.isCurrent(captured), isFalse);
    expect(generation.isCurrent(generation.current), isTrue);
  });

  test('an asynchronous result is ignored after invalidation', () async {
    final generation = MidiRecordingGeneration();
    final captured = generation.current;
    final nativeResult = Completer<int>();
    var applied = false;

    final drain = () async {
      await nativeResult.future;
      if (!generation.isCurrent(captured)) return;
      applied = true;
    }();

    generation.invalidate();
    nativeResult.complete(1);
    await drain;

    expect(applied, isFalse);
  });

  group('editor MIDI drain generation contract', () {
    late String editor;

    setUpAll(() {
      editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    });

    String methodBody(String start, String end) {
      final startIndex = editor.indexOf(start);
      final endIndex = editor.indexOf(end, startIndex);
      expect(startIndex, greaterThanOrEqualTo(0));
      expect(endIndex, greaterThan(startIndex));
      return editor.substring(startIndex, endIndex);
    }

    test('drain rejects stale results after the native await', () {
      final drain = methodBody(
        'Future<void> _drainMidiInputEventsForRecording({',
        'Future<bool> _armLiveMidiInputTargetForRecording(',
      );
      final capture = drain.indexOf(
        'final recordingGeneration = _midiRecordingGeneration.current;',
      );
      final consume = drain.indexOf(
        'await JuceAudioEngine.consumeLiveMidiInputEvents()',
      );
      final reject = drain.indexOf(
        '!_midiRecordingGeneration.isCurrent(recordingGeneration)',
      );
      final apply = drain.indexOf('for (final event in events)');

      expect(capture, greaterThanOrEqualTo(0));
      expect(consume, greaterThan(capture));
      expect(reject, greaterThan(consume));
      expect(apply, greaterThan(reject));
    });

    test('stop invalidates old drains before its first await', () {
      final stop = methodBody(
        'Future<bool> _stopMidiClipRecordingImpl',
        'Future<void> _startRecordingJuce()',
      );
      final invalidate = stop.indexOf('_midiRecordingGeneration.invalidate()');
      final firstAwait = stop.indexOf('await ');

      expect(invalidate, greaterThanOrEqualTo(0));
      expect(firstAwait, greaterThan(invalidate));
    });

    test(
      'runtime clear invalidates drains at cancellation and V2 boundaries',
      () {
        final clear = methodBody(
          'void _clearMidiRecordingRuntimeState()',
          'Future<void> _startMidiRecordingTransaction({',
        );
        final boundary = methodBody(
          'bool _endMidiRecordingForV2SafetyBoundary()',
          'Future<void> _restoreInterruptedMidiClipAfterV2Recovery()',
        );

        expect(clear, contains('_midiRecordingGeneration.invalidate()'));
        expect(boundary, contains('_clearMidiRecordingRuntimeState()'));
      },
    );
  });
}
