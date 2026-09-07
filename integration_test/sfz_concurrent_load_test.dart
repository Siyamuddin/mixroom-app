import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

const _instrumentId =
    'sfz_asset:assets/instruments/VSCO-2-CE-1.1.0/UprightPiano.sfz';
const _warmClipId = 90;
const _concurrentClipIds = <int>[91, 92, 93, 94, 95, 96, 97, 98];

Map<String, dynamic> _note(int id) => <String, dynamic>{
  'id': id,
  'pitch': 60,
  'startBeat': 0.0,
  'lengthBeats': 1.0,
  'velocity': 0.8,
};

double _level(List<double> meter) =>
    math.max(math.max(meter[0], meter[1]), math.max(meter[2], meter[3]));

Future<double> _waitForAudible(int rowIndex) async {
  var maximum = 0.0;
  final deadline = DateTime.now().add(const Duration(seconds: 3));
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'concurrent clips own resolved samples from one cached SFZ definition',
    (tester) async {
      final rowIds = <int>[];
      var projectLoadActive = false;

      expect(
        await JuceAudioEngine.initialiseForImplementation(
          BluetoothImplementationV2.legacy,
        ),
        isTrue,
      );

      try {
        await JuceAudioEngine.setRowMetersEnabled(true);
        await JuceAudioEngine.beginProjectClipLoad();
        projectLoadActive = true;

        final warmRowId = await JuceAudioEngine.addRow('SFZ metadata warmup');
        expect(warmRowId, greaterThanOrEqualTo(0));
        rowIds.add(warmRowId);
        expect(
          await JuceAudioEngine.loadMidiClip(
            _warmClipId,
            warmRowId,
            instrumentId: _instrumentId,
            instrumentName: 'Upright Piano',
            notes: const <Map<String, dynamic>>[],
            params: const <String, double>{},
            sourceTempoBpm: 120.0,
            lengthSec: 2.0,
            loadRequestId: 80000,
          ),
          isTrue,
        );
        await JuceAudioEngine.unloadClip(_warmClipId);

        for (final clipId in _concurrentClipIds) {
          final rowId = await JuceAudioEngine.addRow('Concurrent SFZ $clipId');
          expect(rowId, greaterThanOrEqualTo(0));
          rowIds.add(rowId);
        }

        final loaded = await Future.wait<bool>(<Future<bool>>[
          for (var index = 0; index < _concurrentClipIds.length; index++)
            JuceAudioEngine.loadMidiClip(
              _concurrentClipIds[index],
              rowIds[index + 1],
              instrumentId: _instrumentId,
              instrumentName: 'Upright Piano',
              notes: <Map<String, dynamic>>[_note(index)],
              params: const <String, double>{},
              sourceTempoBpm: 120.0,
              startSec: 10.0,
              lengthSec: 2.0,
              loadRequestId: 80001 + index,
            ),
        ]);
        expect(loaded, everyElement(isTrue));

        await JuceAudioEngine.endProjectClipLoad();
        projectLoadActive = false;
        expect(
          await JuceAudioEngine.preparePlaybackRoute(
            reason: 'sfzConcurrentLoadIntegration',
          ),
          isTrue,
        );

        final rows = await JuceAudioEngine.getRows();
        for (final index in <int>[0, _concurrentClipIds.length - 1]) {
          final rowId = rowIds[index + 1];
          final rowIndex = rows.indexWhere((row) => row['rowId'] == rowId);
          expect(rowIndex, greaterThanOrEqualTo(0));
          expect(
            await JuceAudioEngine.updateMidiClipEvents(
              _concurrentClipIds[index],
              instrumentId: _instrumentId,
              instrumentName: 'Upright Piano',
              notes: <Map<String, dynamic>>[_note(index)],
              params: const <String, double>{},
              sourceTempoBpm: 120.0,
            ),
            isTrue,
          );
          expect(
            await JuceAudioEngine.setLiveMidiInputTargetClip(
              _concurrentClipIds[index],
            ),
            isTrue,
          );
          expect(
            await JuceAudioEngine.playPreviewMidiNote(
              _concurrentClipIds[index],
              pitch: 60,
              velocity: 0.9,
              durationMs: 180,
            ),
            isTrue,
          );
          expect(await _waitForAudible(rowIndex), greaterThan(0.002));
          await JuceAudioEngine.pause();
        }
      } finally {
        if (projectLoadActive) {
          await JuceAudioEngine.endProjectClipLoad();
        }
        await JuceAudioEngine.setRowMetersEnabled(false);
        await JuceAudioEngine.unloadClips(<int>[
          _warmClipId,
          ..._concurrentClipIds,
        ]);
        for (final rowId in rowIds.reversed) {
          await JuceAudioEngine.removeRow(rowId);
        }
        await JuceAudioEngine.shutdown();
      }
    },
    skip: !Platform.isMacOS,
  );
}
