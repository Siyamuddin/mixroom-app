import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

const _channel = MethodChannel('juce_audio_engine');
const _activeClipId = 28;
const _stalledClipId = 29;
const _stalledRequestId = 92001;

Map<String, dynamic> _note(int id, int pitch) => <String, dynamic>{
  'id': id,
  'pitch': pitch,
  'startBeat': 0.0,
  'lengthBeats': 4.0,
  'velocity': 0.8,
};

Future<Map<String, dynamic>> _diagnostics() async {
  final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
    'getEngineDiagnostics',
  );
  return Map<String, dynamic>.from(raw ?? <Object?, Object?>{});
}

Future<void> _waitUntilNativeLoadIsStalled() async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'debugGetMidiClipLoadStallState',
    );
    final state = raw ?? <Object?, Object?>{};
    if (state['requestId'] == _stalledRequestId && state['waiting'] == true) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Native MIDI load did not reach the termination-race test stall');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'termination detaches audio and rejects late or restarted work',
    (tester) async {
      expect(
        await JuceAudioEngine.initialiseForImplementation(
          BluetoothImplementationV2.legacy,
        ),
        isTrue,
      );

      final rowId = await JuceAudioEngine.addRow('Termination test');
      expect(rowId, greaterThanOrEqualTo(0));
      expect(
        await JuceAudioEngine.loadMidiClip(
          _activeClipId,
          rowId,
          instrumentId: 'mixroom.basic_synth',
          instrumentName: 'Basic Synth',
          notes: <Map<String, dynamic>>[_note(1, 60)],
          params: const <String, double>{},
          sourceTempoBpm: 120.0,
          startSec: 0.0,
          lengthSec: 2.0,
          loadRequestId: 92000,
        ),
        isTrue,
      );
      expect(await JuceAudioEngine.play(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final before = await _diagnostics();
      expect(before['deviceOpen'], isTrue);
      expect(before['audioCallbackAttached'], isTrue);
      expect((before['realtimeCallbackCount'] as num?) ?? 0, greaterThan(0));

      expect(
        await _channel.invokeMethod<bool>(
          'debugConfigureMidiClipLoadStall',
          <String, Object>{'loadRequestId': _stalledRequestId},
        ),
        isTrue,
      );
      final stalledLoad = JuceAudioEngine.loadMidiClip(
        _stalledClipId,
        rowId,
        instrumentId: 'mixroom.basic_synth',
        instrumentName: 'Basic Synth',
        notes: <Map<String, dynamic>>[_note(2, 72)],
        params: const <String, double>{},
        sourceTempoBpm: 120.0,
        startSec: 0.0,
        lengthSec: 2.0,
        loadRequestId: _stalledRequestId,
      );
      await _waitUntilNativeLoadIsStalled();

      await _channel.invokeMethod<void>(
        'debugShutdownForApplicationTermination',
      );
      final after = await _diagnostics();
      expect(after['deviceOpen'], isFalse);
      expect(after['audioCallbackAttached'], isFalse);
      expect(after['rowCount'], 0);
      expect(after['clipCount'], 0);

      expect(
        await _channel.invokeMethod<bool>(
          'debugReleaseMidiClipLoadStall',
          <String, Object>{'loadRequestId': _stalledRequestId},
        ),
        isTrue,
      );
      expect(await stalledLoad, isFalse);

      await _channel.invokeMethod<void>(
        'debugShutdownForApplicationTermination',
      );
      await expectLater(
        _channel.invokeMethod<void>('initialise'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'application_terminating',
          ),
        ),
      );

      final finalState = await _diagnostics();
      expect(finalState['deviceOpen'], isFalse);
      expect(finalState['audioCallbackAttached'], isFalse);
      expect(finalState['clipCount'], 0);
    },
    skip: !Platform.isMacOS,
  );
}
