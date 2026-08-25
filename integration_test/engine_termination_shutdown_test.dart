import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

const _channel = MethodChannel('juce_audio_engine');

Future<Map<String, dynamic>> _diagnostics() async {
  final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
    'getEngineDiagnostics',
  );
  return Map<String, dynamic>.from(raw ?? <Object?, Object?>{});
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'application termination detaches an active CoreAudio callback exactly once',
    (tester) async {
      var terminationBoundaryRan = false;
      expect(
        await JuceAudioEngine.initialiseForImplementation(
          BluetoothImplementationV2.legacy,
        ),
        isTrue,
      );

      try {
        final rowId = await JuceAudioEngine.addRow('Termination test');
        expect(rowId, greaterThanOrEqualTo(0));
        expect(
          await JuceAudioEngine.loadMidiClip(
            29,
            rowId,
            instrumentId: 'mixroom.basic_synth',
            instrumentName: 'Basic Synth',
            notes: const <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 1,
                'pitch': 60,
                'startBeat': 0.0,
                'lengthBeats': 4.0,
                'velocity': 0.8,
              },
            ],
            params: const <String, double>{},
            sourceTempoBpm: 120.0,
            startSec: 0.0,
            lengthSec: 2.0,
            loadRequestId: 92001,
          ),
          isTrue,
        );
        expect(await JuceAudioEngine.play(), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 150));

        final before = await _diagnostics();
        expect(before['deviceOpen'], isTrue);
        expect(before['audioCallbackAttached'], isTrue);
        expect((before['realtimeCallbackCount'] as num?) ?? 0, greaterThan(0));

        await _channel.invokeMethod<void>(
          'debugShutdownForApplicationTermination',
        );
        terminationBoundaryRan = true;

        final after = await _diagnostics();
        expect(after['deviceOpen'], isFalse);
        expect(after['audioCallbackAttached'], isFalse);
        expect(after['rowCount'], 0);
        expect(after['clipCount'], 0);

        await _channel.invokeMethod<void>(
          'debugShutdownForApplicationTermination',
        );
        final repeated = await _diagnostics();
        expect(repeated['deviceOpen'], isFalse);
        expect(repeated['audioCallbackAttached'], isFalse);
      } finally {
        if (!terminationBoundaryRan) await JuceAudioEngine.shutdown();
      }
    },
    skip: !Platform.isMacOS,
  );
}
