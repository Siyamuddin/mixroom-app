import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

const _uprightPiano =
    'sfz_asset:assets/instruments/VSCO-2-CE-1.1.0/UprightPiano.sfz';
const _tubaStaccato =
    'sfz_asset:assets/instruments/VSCO-2-CE-1.1.0/TubaStac.sfz';

Map<String, dynamic> _note(int id, int pitch) => <String, dynamic>{
  'id': id,
  'pitch': pitch,
  'startBeat': 0.0,
  'lengthBeats': 1.0,
  'velocity': 0.8,
};

double _peak(List<double> meter) => math.max(meter[0], meter[1]);
double _rms(List<double> meter) => math.max(meter[2], meter[3]);

Future<List<double>> _waitForQuiet(int rowIndex) async {
  var meter = await JuceAudioEngine.getRowMeterValues(rowIndex);
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while ((_peak(meter) > 0.0001 || _rms(meter) > 0.0001) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    meter = await JuceAudioEngine.getRowMeterValues(rowIndex);
  }
  return meter;
}

Future<Map<String, dynamic>> _measureStrike({
  required String label,
  required int rowIndex,
  required Future<bool> Function() strike,
}) async {
  final baseline = await _waitForQuiet(rowIndex);
  final accepted = await strike();
  var maxPeak = 0.0;
  var maxRms = 0.0;
  final deadline = DateTime.now().add(const Duration(milliseconds: 650));
  while (DateTime.now().isBefore(deadline)) {
    final meter = await JuceAudioEngine.getRowMeterValues(rowIndex);
    maxPeak = math.max(maxPeak, _peak(meter));
    maxRms = math.max(maxRms, _rms(meter));
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  final baselinePeak = _peak(baseline);
  final floor = math.max(0.0005, baselinePeak + 0.0002);
  final result = <String, dynamic>{
    'label': label,
    'accepted': accepted,
    'baselinePeak': baselinePeak,
    'peak': maxPeak,
    'rms': maxRms,
    'floor': floor,
  };
  expect(accepted, isTrue, reason: '$label was rejected by the native API');
  expect(maxPeak, greaterThan(floor), reason: '$label produced no meter peak');
  return result;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'sampled and synth live notes produce real row-meter output',
    (tester) async {
      final results = <Map<String, dynamic>>[];
      final rowIds = <int>[];
      final clipIds = <int>[0, 1, 2, 3];

      await JuceAudioEngine.initialise();
      try {
        await JuceAudioEngine.setRowMetersEnabled(true);

        Future<int> loadClip({
          required int clipId,
          required String rowName,
          required String instrumentId,
          required String instrumentName,
          required int existingPitch,
          Map<String, double> params = const <String, double>{},
          bool asProjectLoad = false,
        }) async {
          final rowId = await JuceAudioEngine.addRow(rowName);
          expect(rowId, greaterThanOrEqualTo(0));
          rowIds.add(rowId);
          final nativeRows = await JuceAudioEngine.getRows();
          final rowIndex = nativeRows.indexWhere(
            (row) => row['rowId'] == rowId,
          );
          expect(rowIndex, greaterThanOrEqualTo(0));
          if (asProjectLoad) await JuceAudioEngine.beginProjectClipLoad();
          var loaded = false;
          try {
            loaded = await JuceAudioEngine.loadMidiClip(
              clipId,
              rowId,
              instrumentId: instrumentId,
              instrumentName: instrumentName,
              notes: <Map<String, dynamic>>[_note(clipId, existingPitch)],
              params: params,
              sourceTempoBpm: 120.0,
              startSec: 10.0,
              lengthSec: 2.0,
            );
          } finally {
            if (asProjectLoad) await JuceAudioEngine.endProjectClipLoad();
          }
          expect(loaded, isTrue);
          expect(
            await JuceAudioEngine.preparePlaybackRoute(
              reason: asProjectLoad
                  ? 'midiPreviewColdProjectLoad'
                  : 'midiPreviewIntegration',
            ),
            isTrue,
          );
          final updated = await JuceAudioEngine.updateMidiClipEvents(
            clipId,
            instrumentId: instrumentId,
            instrumentName: instrumentName,
            notes: <Map<String, dynamic>>[_note(clipId, existingPitch)],
            params: params,
            sourceTempoBpm: 120.0,
          );
          expect(updated, isTrue);
          expect(
            await JuceAudioEngine.setLiveMidiInputTargetClip(clipId),
            isTrue,
          );
          return rowIndex;
        }

        final pianoRow = await loadClip(
          clipId: clipIds[0],
          rowName: 'Preview Piano 1',
          instrumentId: _uprightPiano,
          instrumentName: 'Upright Piano',
          existingPitch: 60,
          asProjectLoad: true,
          params: const <String, double>{
            'outputGain': 0.78,
            'attackMs': 4.0,
            'releaseMs': 900.0,
          },
        );
        results.add(
          await _measureStrike(
            label: 'upright-timeline-playback',
            rowIndex: pianoRow,
            strike: () async {
              expect(
                await JuceAudioEngine.setLiveMidiInputTargetClip(-1),
                isTrue,
              );
              await JuceAudioEngine.setTransportSeconds(10.0);
              return JuceAudioEngine.play();
            },
          ),
        );
        await JuceAudioEngine.pause();
        expect(
          await JuceAudioEngine.setLiveMidiInputTargetClip(clipIds[0]),
          isTrue,
        );
        results.add(
          await _measureStrike(
            label: 'upright-absent-pitch-preview',
            rowIndex: pianoRow,
            strike: () => JuceAudioEngine.playPreviewMidiNote(
              clipIds[0],
              pitch: 64,
              velocity: 0.8,
              durationMs: 180,
            ),
          ),
        );

        final secondPianoRow = await loadClip(
          clipId: clipIds[1],
          rowName: 'Preview Piano 2',
          instrumentId: _uprightPiano,
          instrumentName: 'Upright Piano',
          existingPitch: 67,
          params: const <String, double>{
            'outputGain': 0.78,
            'attackMs': 4.0,
            'releaseMs': 900.0,
          },
        );
        results.add(
          await _measureStrike(
            label: 'upright-second-row-absent-pitch',
            rowIndex: secondPianoRow,
            strike: () => JuceAudioEngine.playPreviewMidiNote(
              clipIds[1],
              pitch: 71,
              velocity: 0.8,
              durationMs: 180,
            ),
          ),
        );

        final synthRow = await loadClip(
          clipId: clipIds[2],
          rowName: 'Preview Synth',
          instrumentId: 'mixroom.basic_synth',
          instrumentName: 'Basic Synth',
          existingPitch: 60,
        );
        for (final pitch in <int>[48, 61, 76]) {
          results.add(
            await _measureStrike(
              label: 'basic-synth-$pitch',
              rowIndex: synthRow,
              strike: () => JuceAudioEngine.playPreviewMidiNote(
                clipIds[2],
                pitch: pitch,
                velocity: 0.8,
                durationMs: 160,
              ),
            ),
          );
        }

        final tubaRow = await loadClip(
          clipId: clipIds[3],
          rowName: 'Preview Tuba',
          instrumentId: _tubaStaccato,
          instrumentName: 'Tuba Staccato',
          existingPitch: 46,
          params: const <String, double>{
            'outputGain': 0.7,
            'attackMs': 6.0,
            'releaseMs': 260.0,
          },
        );
        for (var strike = 0; strike < 8; strike++) {
          results.add(
            await _measureStrike(
              label: 'tuba-round-robin-$strike',
              rowIndex: tubaRow,
              strike: () => JuceAudioEngine.playPreviewMidiNote(
                clipIds[3],
                pitch: 46,
                velocity: 0.8,
                durationMs: 140,
              ),
            ),
          );
        }

        expect(
          await JuceAudioEngine.setLiveMidiInputTargetClip(clipIds[0]),
          isTrue,
        );
        results.add(
          await _measureStrike(
            label: 'upright-live-midi-input',
            rowIndex: pianoRow,
            strike: () async {
              final sent = await JuceAudioEngine.sendLiveMidiInputEvent(
                noteOn: true,
                channel: 1,
                pitch: 69,
                velocity: 0.8,
              );
              await Future<void>.delayed(const Duration(milliseconds: 180));
              final stopped = await JuceAudioEngine.sendLiveMidiInputEvent(
                noteOn: false,
                channel: 1,
                pitch: 69,
                velocity: 0.0,
              );
              return sent && stopped;
            },
          ),
        );

        // Keep this line stable so local/CI logs can scrape audible evidence.
        // ignore: avoid_print
        print(
          'MIXROOM_MIDI_PREVIEW ${jsonEncode(<String, dynamic>{'passed': true, 'strikes': results})}',
        );
      } finally {
        await JuceAudioEngine.setRowMetersEnabled(false);
        await JuceAudioEngine.unloadClips(clipIds);
        for (final rowId in rowIds.reversed) {
          await JuceAudioEngine.removeRow(rowId);
        }
        await JuceAudioEngine.shutdown();
      }
    },
    skip: !(Platform.isMacOS || Platform.isAndroid || Platform.isIOS),
  );
}
