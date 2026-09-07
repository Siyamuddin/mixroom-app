import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

Map<String, dynamic> _note(int id, int pitch, {double lengthBeats = 8.0}) =>
    <String, dynamic>{
      'id': id,
      'pitch': pitch,
      'startBeat': 0.0,
      'lengthBeats': lengthBeats,
      'velocity': 0.9,
    };

double _level(List<double> meter) =>
    math.max(math.max(meter[0], meter[1]), math.max(meter[2], meter[3]));

Future<double> _waitForAudible(int rowIndex) async {
  var maximum = 0.0;
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    maximum = math.max(
      maximum,
      _level(await JuceAudioEngine.getRowMeterValues(rowIndex)),
    );
    if (maximum > 0.002) return maximum;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return maximum;
}

Future<double> _waitForQuiet(int rowIndex) async {
  var level = _level(await JuceAudioEngine.getRowMeterValues(rowIndex));
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (level > 0.0005 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    level = _level(await JuceAudioEngine.getRowMeterValues(rowIndex));
  }
  return level;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native panic boundaries silence lost note-offs without cutting timeline',
    (tester) async {
      const firstClip = 0;
      const secondClip = 1;
      final rowIds = <int>[];

      expect(
        await JuceAudioEngine.initialiseForImplementation(
          BluetoothImplementationV2.legacy,
        ),
        isTrue,
      );
      await JuceAudioEngine.setRowMetersEnabled(true);
      try {
        Future<int> loadSynth(int clipId, String name, int pitch) async {
          final rowId = await JuceAudioEngine.addRow(name);
          expect(rowId, greaterThanOrEqualTo(0));
          rowIds.add(rowId);
          final rows = await JuceAudioEngine.getRows();
          final rowIndex = rows.indexWhere((row) => row['rowId'] == rowId);
          expect(rowIndex, greaterThanOrEqualTo(0));
          expect(
            await JuceAudioEngine.loadMidiClip(
              clipId,
              rowId,
              instrumentId: 'mixroom.basic_synth',
              instrumentName: 'Basic Synth',
              notes: <Map<String, dynamic>>[_note(clipId, pitch)],
              params: const <String, double>{'releaseMs': 1200.0},
              sourceTempoBpm: 120.0,
              startSec: 0.0,
              lengthSec: 4.0,
            ),
            isTrue,
          );
          return rowIndex;
        }

        final firstRow = await loadSynth(firstClip, 'Panic A', 60);
        final secondRow = await loadSynth(secondClip, 'Panic B', 67);
        expect(
          await JuceAudioEngine.preparePlaybackRoute(
            reason: 'midiPanicBoundaryIntegration',
          ),
          isTrue,
        );

        // Missing noteOff: changing target must silence only the old live voice.
        expect(
          await JuceAudioEngine.setLiveMidiInputTargetClip(firstClip),
          isTrue,
        );
        expect(
          await JuceAudioEngine.sendLiveMidiInputEvent(
            noteOn: true,
            channel: 1,
            pitch: 72,
            velocity: 0.9,
          ),
          isTrue,
        );
        expect(await _waitForAudible(firstRow), greaterThan(0.002));
        expect(
          await JuceAudioEngine.setLiveMidiInputTargetClip(secondClip),
          isTrue,
        );
        expect(await _waitForQuiet(firstRow), lessThanOrEqualTo(0.0005));

        // A full transport boundary must silence a missing noteOff.
        expect(
          await JuceAudioEngine.sendLiveMidiInputEvent(
            noteOn: true,
            channel: 1,
            pitch: 74,
            velocity: 0.9,
          ),
          isTrue,
        );
        expect(await _waitForAudible(secondRow), greaterThan(0.002));
        await JuceAudioEngine.pause();
        expect(await _waitForQuiet(secondRow), lessThanOrEqualTo(0.0005));

        // A later note must still work after panic state has been consumed.
        expect(
          await JuceAudioEngine.sendLiveMidiInputEvent(
            noteOn: true,
            channel: 1,
            pitch: 76,
            velocity: 0.9,
          ),
          isTrue,
        );
        expect(await _waitForAudible(secondRow), greaterThan(0.002));
        expect(
          await JuceAudioEngine.sendLiveMidiInputEvent(
            noteOn: false,
            channel: 1,
            pitch: 76,
            velocity: 0.0,
          ),
          isTrue,
        );
        await JuceAudioEngine.pause();
        expect(await _waitForQuiet(secondRow), lessThanOrEqualTo(0.0005));

        // Live-only target changes must preserve scheduled timeline playback.
        expect(
          await JuceAudioEngine.setLiveMidiInputTargetClip(firstClip),
          isTrue,
        );
        await JuceAudioEngine.setTransportSeconds(0.0);
        expect(await JuceAudioEngine.play(), isTrue);
        expect(await _waitForAudible(firstRow), greaterThan(0.002));
        expect(
          await JuceAudioEngine.setLiveMidiInputTargetClip(secondClip),
          isTrue,
        );
        expect(
          await _waitForAudible(firstRow),
          greaterThan(0.002),
          reason: 'Live-only panic must not cut timeline notes',
        );
        await JuceAudioEngine.pause();
        expect(await _waitForQuiet(firstRow), lessThanOrEqualTo(0.0005));

        // Replacement and unload must reject stale work and start from silence.
        expect(
          await JuceAudioEngine.setLiveMidiInputTargetClip(firstClip),
          isTrue,
        );
        expect(
          await JuceAudioEngine.sendLiveMidiInputEvent(
            noteOn: true,
            channel: 1,
            pitch: 79,
            velocity: 0.9,
          ),
          isTrue,
        );
        expect(await _waitForAudible(firstRow), greaterThan(0.002));
        expect(
          await JuceAudioEngine.updateMidiClipEvents(
            firstClip,
            instrumentId: 'mixroom.basic_synth',
            instrumentName: 'Basic Synth',
            notes: <Map<String, dynamic>>[_note(99, 60)],
            params: const <String, double>{'releaseMs': 1200.0},
            sourceTempoBpm: 120.0,
          ),
          isTrue,
        );
        expect(await _waitForQuiet(firstRow), lessThanOrEqualTo(0.0005));
        expect(
          await JuceAudioEngine.sendLiveMidiInputEvent(
            noteOn: true,
            channel: 1,
            pitch: 81,
            velocity: 0.9,
          ),
          isTrue,
        );
        expect(await _waitForAudible(firstRow), greaterThan(0.002));
        await JuceAudioEngine.unloadClip(firstClip);
        expect(await _waitForQuiet(firstRow), lessThanOrEqualTo(0.0005));
        expect(
          await JuceAudioEngine.sendLiveMidiInputEvent(
            noteOn: true,
            channel: 1,
            pitch: 81,
            velocity: 0.9,
          ),
          isFalse,
        );
      } finally {
        await JuceAudioEngine.setRowMetersEnabled(false);
        await JuceAudioEngine.unloadClips(const <int>[firstClip, secondClip]);
        for (final rowId in rowIds.reversed) {
          await JuceAudioEngine.removeRow(rowId);
        }
        await JuceAudioEngine.shutdown();
      }
    },
    skip: !Platform.isMacOS,
  );
}
