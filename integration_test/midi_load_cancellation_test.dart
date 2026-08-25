import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:mixroom/helpers/timed_native_operation.dart';

const _channel = MethodChannel('juce_audio_engine');
const _clipId = 27;
const _stalledRequestId = 91001;
const _retryRequestId = 91002;

Map<String, dynamic> _note(int id, int pitch) => <String, dynamic>{
  'id': id,
  'pitch': pitch,
  'startBeat': 0.0,
  'lengthBeats': 1.0,
  'velocity': 0.8,
};

Future<Map<Object?, Object?>> _stallState() async {
  return await _channel.invokeMethod<Map<Object?, Object?>>(
        'debugGetMidiClipLoadStallState',
      ) ??
      <Object?, Object?>{};
}

Future<void> _waitUntilNativeLoadIsStalled() async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final state = await _stallState();
    if (state['requestId'] == _stalledRequestId && state['waiting'] == true) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Native MIDI load did not reach the test stall');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'timed-out native MIDI load cannot replace or remove its retry',
    (tester) async {
      var rowId = -1;
      var stallReleased = false;
      final cancellationResult = Completer<bool>();

      expect(
        await JuceAudioEngine.initialiseForImplementation(
          BluetoothImplementationV2.legacy,
        ),
        isTrue,
      );

      try {
        rowId = await JuceAudioEngine.addRow('MIDI cancellation test');
        expect(rowId, greaterThanOrEqualTo(0));
        expect(
          await _channel.invokeMethod<bool>(
            'debugConfigureMidiClipLoadStall',
            <String, Object>{'loadRequestId': _stalledRequestId},
          ),
          isTrue,
        );

        final firstNativeLoad = JuceAudioEngine.loadMidiClip(
          _clipId,
          rowId,
          instrumentId: 'mixroom.basic_synth',
          instrumentName: 'Basic Synth',
          notes: <Map<String, dynamic>>[_note(1, 60)],
          params: const <String, double>{},
          sourceTempoBpm: 120.0,
          startSec: 0.0,
          lengthSec: 2.0,
          loadRequestId: _stalledRequestId,
        );
        final timedLoad = runTimedNativeOperation<bool>(
          'fault-injected MIDI load',
          () => firstNativeLoad,
          timeout: const Duration(milliseconds: 250),
          logger: (_) {},
          onTimeout: () {
            unawaited(
              JuceAudioEngine.cancelMidiClipLoad(
                clipIndex: _clipId,
                loadRequestId: _stalledRequestId,
              ).then(cancellationResult.complete),
            );
          },
        );

        await _waitUntilNativeLoadIsStalled();
        expect(await timedLoad, isNull);
        expect(await cancellationResult.future, isTrue);

        var retryCompleted = false;
        final retryLoad =
            JuceAudioEngine.loadMidiClip(
              _clipId,
              rowId,
              instrumentId: 'mixroom.basic_synth',
              instrumentName: 'Basic Synth',
              notes: <Map<String, dynamic>>[_note(2, 72)],
              params: const <String, double>{},
              sourceTempoBpm: 120.0,
              startSec: 0.0,
              lengthSec: 2.0,
              loadRequestId: _retryRequestId,
            ).then((loaded) {
              retryCompleted = true;
              return loaded;
            });
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          retryCompleted,
          isFalse,
          reason:
              'Retry must remain queued behind the deliberately stalled load',
        );

        expect(
          await _channel.invokeMethod<bool>(
            'debugReleaseMidiClipLoadStall',
            <String, Object>{'loadRequestId': _stalledRequestId},
          ),
          isTrue,
        );
        stallReleased = true;

        expect(await firstNativeLoad, isFalse);
        expect(await retryLoad, isTrue);

        expect(
          await JuceAudioEngine.cancelMidiClipLoad(
            clipIndex: _clipId,
            loadRequestId: _stalledRequestId,
          ),
          isTrue,
        );
        expect(
          await JuceAudioEngine.updateMidiClipEvents(
            _clipId,
            instrumentId: 'mixroom.basic_synth',
            instrumentName: 'Basic Synth',
            notes: <Map<String, dynamic>>[_note(3, 74)],
            params: const <String, double>{},
            sourceTempoBpm: 120.0,
          ),
          isTrue,
          reason:
              'Cancelling the old request must preserve the installed retry',
        );
      } finally {
        if (!stallReleased) {
          await _channel.invokeMethod<bool>(
            'debugReleaseMidiClipLoadStall',
            <String, Object>{'loadRequestId': _stalledRequestId},
          );
        }
        await JuceAudioEngine.unloadClip(_clipId);
        if (rowId >= 0) await JuceAudioEngine.removeRow(rowId);
        await JuceAudioEngine.shutdown();
      }
    },
    skip: !Platform.isMacOS,
  );
}
