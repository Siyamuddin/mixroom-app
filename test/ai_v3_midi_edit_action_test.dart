import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/screens/audio_editor.dart';

Future<AudioTrack> _midiClip() => AudioTrack.create(
      file: File('/tmp/v3-midi.mid'),
      originalFile: File('/tmp/v3-midi.mid'),
      audioDuration: const Duration(seconds: 4),
      trimStart: Duration.zero,
      trimEnd: const Duration(seconds: 4),
      offset: 0,
      rowIndex: 0,
      rowId: 10,
      label: 'MIDI',
      clipKind: ClipKind.midi,
      instrumentId: 'mixroom.basic_synth',
      instrumentName: 'Basic Synth',
      midiNotes: <MidiNote>[
        MidiNote(
          id: 'old',
          pitch: 60,
          startBeat: 0,
          lengthBeats: 1,
          velocity: 0.8,
        ),
      ],
    );

void main() {
  test('guitar IDs, names, parameters, and notes serialize unchanged',
      () async {
    for (final guitar in <Map<String, Object>>[
      <String, Object>{
        'id': 'sfz.guitar.steel_acoustic',
        'name': 'Acoustic Guitar',
        'params': <String, double>{
          'outputGain': 1.0,
          'attackMs': 2.0,
          'releaseMs': 350.0,
        },
      },
      <String, Object>{
        'id': 'sfz.guitar.clean_electric',
        'name': 'Electric Guitar',
        'params': <String, double>{
          'outputGain': 2.0,
          'attackMs': 2.0,
          'releaseMs': 250.0,
        },
      },
    ]) {
      final clip = await _midiClip()
        ..instrumentId = guitar['id']! as String
        ..instrumentName = guitar['name']! as String
        ..instrumentParams = Map<String, double>.from(
          guitar['params']! as Map,
        );
      final json = clip.toJson('guitar.mid');
      expect(json['instrumentId'], guitar['id']);
      expect(json['instrumentName'], guitar['name']);
      expect(json['instrumentParams'], guitar['params']);
      expect((json['midiNotes'] as List).single['pitch'], 60);
    }
  });

  group('instrument-derived MIDI clip labels', () {
    test('empty and default instrument labels follow an instrument swap', () {
      expect(
        shouldMidiClipLabelFollowInstrument(
          label: '',
          instrumentName: 'Upright Piano',
        ),
        isTrue,
      );
      expect(
        shouldMidiClipLabelFollowInstrument(
          label: ' Upright Piano ',
          instrumentName: 'Upright Piano',
        ),
        isTrue,
      );
    });

    test('custom clip labels remain independent from the instrument', () {
      expect(
        shouldMidiClipLabelFollowInstrument(
          label: 'Verse Chords',
          instrumentName: 'Upright Piano',
        ),
        isFalse,
      );
    });

    test('label rename action survives topology changes', () async {
      final clip = await _midiClip()
        ..label = 'Upright Piano';
      final tracks = <AudioTrack>[clip];
      final action = SetClipLabelAction(
        tracks: tracks,
        originalIndex: 0,
        oldLabel: 'Upright Piano',
        newLabel: 'Dream Pad',
        applyToState: (target, label) => target.label = label,
      );

      await action.redo();
      expect(clip.label, 'Dream Pad');

      final precedingClip = await _midiClip()
        ..label = 'Intro';
      tracks.insert(0, precedingClip);

      await action.undo();
      expect(clip.label, 'Upright Piano');
      expect(precedingClip.label, 'Intro');
      await action.redo();
      expect(clip.label, 'Dream Pad');
      expect(precedingClip.label, 'Intro');
    });
  });

  test('MIDI edit persists and restores exact notes and clip bounds', () async {
    final clip = await _midiClip();
    final tracks = <AudioTrack>[clip];
    final oldNotes = clip.midiNotes.map((note) => note.copy()).toList();
    final newNotes = <MidiNote>[
      ...oldNotes.map((note) => note.copy()),
      MidiNote(
        id: 'new',
        pitch: 64,
        startBeat: 8,
        lengthBeats: 2,
        velocity: 0.7,
      ),
    ];
    final action = EditMidiClipAction(
      tracks: tracks,
      originalIndex: 0,
      oldNotes: oldNotes,
      newNotes: newNotes,
      oldInstrumentId: clip.instrumentId,
      oldInstrumentName: clip.instrumentName,
      oldInstrumentParams: const <String, double>{},
      newInstrumentId: clip.instrumentId,
      newInstrumentName: clip.instrumentName,
      newInstrumentParams: const <String, double>{},
      oldTrimEnd: const Duration(seconds: 4),
      newTrimEnd: const Duration(seconds: 5),
      oldAudioDuration: const Duration(seconds: 4),
      newAudioDuration: const Duration(seconds: 5),
      applyToClip: (
        target,
        notes,
        instrumentId,
        instrumentName,
        instrumentParams,
        hostedInstrumentStateBase64,
      ) async {
        target.midiNotes = notes.map((note) => note.copy()).toList();
      },
    );

    await action.redo();
    expect(clip.midiNotes.map((note) => note.pitch), <int>[60, 64]);
    expect(clip.trimEnd, const Duration(seconds: 5));
    expect(clip.audioDuration, const Duration(seconds: 5));

    await action.undo();
    expect(clip.midiNotes.map((note) => note.pitch), <int>[60]);
    expect(clip.trimEnd, const Duration(seconds: 4));
    expect(clip.audioDuration, const Duration(seconds: 4));

    await action.redo();
    expect(clip.midiNotes.map((note) => note.pitch), <int>[60, 64]);
    expect(clip.trimEnd, const Duration(seconds: 5));

    final persisted = action.toPersistedUndoCommand();
    expect(persisted['oldTrimEndMs'], 4000);
    expect(persisted['newTrimEndMs'], 5000);
    expect(persisted['oldAudioDurationMs'], 4000);
    expect(persisted['newAudioDurationMs'], 5000);
  });

  test('failed MIDI edit restores its complete previous state', () async {
    final clip = await _midiClip();
    final oldNotes = clip.midiNotes.map((note) => note.copy()).toList();
    final newNotes = <MidiNote>[
      MidiNote(
        id: 'new',
        pitch: 64,
        startBeat: 8,
        lengthBeats: 1,
        velocity: 0.8,
      ),
    ];
    final action = EditMidiClipAction(
      tracks: <AudioTrack>[clip],
      originalIndex: 0,
      oldNotes: oldNotes,
      newNotes: newNotes,
      oldInstrumentId: clip.instrumentId,
      oldInstrumentName: clip.instrumentName,
      oldInstrumentParams: const <String, double>{},
      newInstrumentId: clip.instrumentId,
      newInstrumentName: clip.instrumentName,
      newInstrumentParams: const <String, double>{},
      oldTrimEnd: const Duration(seconds: 4),
      newTrimEnd: const Duration(seconds: 5),
      oldAudioDuration: const Duration(seconds: 4),
      newAudioDuration: const Duration(seconds: 5),
      applyToClip: (
        target,
        notes,
        instrumentId,
        instrumentName,
        instrumentParams,
        hostedInstrumentStateBase64,
      ) async {
        target.midiNotes = notes.map((note) => note.copy()).toList();
        if (notes.any((note) => note.pitch == 64)) {
          throw StateError('native sync failed');
        }
      },
    );

    await expectLater(action.redo(), throwsStateError);
    expect(clip.midiNotes.map((note) => note.pitch), <int>[60]);
    expect(clip.trimEnd, const Duration(seconds: 4));
    expect(clip.audioDuration, const Duration(seconds: 4));
  });

  test('instrument edit preserves notes, bounds, and tempo state', () async {
    final clip = await _midiClip()
      ..sourceTempoBpm = 117.5
      ..stretchToProjectTempo = false
      ..tempoStretchPreservePitch = false
      ..tempoWarpMode = 'repitch';
    final notes = clip.midiNotes.map((note) => note.copy()).toList();
    final action = EditMidiClipAction(
      tracks: <AudioTrack>[clip],
      originalIndex: 0,
      oldNotes: notes,
      newNotes: notes.map((note) => note.copy()).toList(),
      oldInstrumentId: clip.instrumentId,
      oldInstrumentName: clip.instrumentName,
      oldInstrumentParams: const <String, double>{},
      oldHostedInstrumentStateBase64: 'old-state',
      newInstrumentId: 'sfz.guitar.clean_electric',
      newInstrumentName: 'Electric Guitar',
      newInstrumentParams: const <String, double>{
        'outputGain': 2.0,
        'attackMs': 2.0,
        'releaseMs': 250.0,
      },
      newHostedInstrumentStateBase64: '',
      applyToClip:
          (
            target,
            notes,
            instrumentId,
            instrumentName,
            instrumentParams,
            hostedInstrumentStateBase64,
          ) async {
            target
              ..midiNotes = notes.map((note) => note.copy()).toList()
              ..instrumentId = instrumentId
              ..instrumentName = instrumentName
              ..instrumentParams = Map<String, double>.from(instrumentParams)
              ..hostedInstrumentStateBase64 = hostedInstrumentStateBase64;
          },
    );

    await action.redo();
    expect(clip.instrumentId, 'sfz.guitar.clean_electric');
    expect(clip.instrumentName, 'Electric Guitar');
    expect(clip.instrumentParams, <String, double>{
      'outputGain': 2.0,
      'attackMs': 2.0,
      'releaseMs': 250.0,
    });
    expect(clip.midiNotes.single.id, 'old');
    expect(clip.trimStart, Duration.zero);
    expect(clip.trimEnd, const Duration(seconds: 4));
    expect(clip.audioDuration, const Duration(seconds: 4));
    expect(clip.sourceTempoBpm, 117.5);
    expect(clip.stretchToProjectTempo, isFalse);
    expect(clip.tempoStretchPreservePitch, isFalse);
    expect(clip.tempoWarpMode, 'repitch');

    await action.undo();
    expect(clip.instrumentId, 'mixroom.basic_synth');
    expect(clip.instrumentName, 'Basic Synth');
    expect(clip.midiNotes.single.id, 'old');
    expect(clip.trimEnd, const Duration(seconds: 4));
    expect(clip.sourceTempoBpm, 117.5);
    expect(clip.stretchToProjectTempo, isFalse);
    expect(clip.tempoStretchPreservePitch, isFalse);
    expect(clip.tempoWarpMode, 'repitch');

    await action.redo();
    expect(clip.instrumentId, 'sfz.guitar.clean_electric');
  });

  test('MIDI edit restores all command-owned tempo state exactly', () async {
    final clip = await _midiClip()
      ..sourceTempoBpm = 117.5
      ..stretchToProjectTempo = false
      ..tempoStretchPreservePitch = false
      ..tempoWarpMode = 'repitch';
    final tracks = <AudioTrack>[clip];
    final oldNotes = clip.midiNotes.map((note) => note.copy()).toList();
    final newNotes = <MidiNote>[
      ...oldNotes.map((note) => note.copy()),
      MidiNote(
        id: 'new',
        pitch: 67,
        startBeat: 8,
        lengthBeats: 1,
        velocity: 0.7,
      ),
    ];
    var syncCalls = 0;
    final action = EditMidiClipAction(
      tracks: tracks,
      originalIndex: 0,
      oldNotes: oldNotes,
      newNotes: newNotes,
      oldInstrumentId: clip.instrumentId,
      oldInstrumentName: clip.instrumentName,
      oldInstrumentParams: const <String, double>{},
      newInstrumentId: clip.instrumentId,
      newInstrumentName: clip.instrumentName,
      newInstrumentParams: const <String, double>{},
      oldClipOwnedState: const <String, dynamic>{
        'trim_end_us': 4000000,
        'audio_duration_us': 4000000,
        'source_tempo_bpm': 117.5,
        'stretch_to_project_tempo': false,
        'tempo_stretch_preserve_pitch': false,
        'tempo_warp_mode': 'repitch',
      },
      newClipOwnedState: const <String, dynamic>{
        'trim_end_us': 5000000,
        'audio_duration_us': 5000000,
        'source_tempo_bpm': 117.5,
        'stretch_to_project_tempo': false,
        'tempo_stretch_preserve_pitch': false,
        'tempo_warp_mode': 'repitch',
      },
      syncTiming: (_) async => syncCalls += 1,
      applyToClip: (
        target,
        notes,
        instrumentId,
        instrumentName,
        instrumentParams,
        hostedInstrumentStateBase64,
      ) async {
        target
          ..midiNotes = notes.map((note) => note.copy()).toList()
          ..sourceTempoBpm = 140
          ..stretchToProjectTempo = true
          ..tempoStretchPreservePitch = true
          ..tempoWarpMode = 'complex';
      },
    );

    await action.redo();
    expect(clip.trimEnd, const Duration(seconds: 5));
    expect(clip.audioDuration, const Duration(seconds: 5));
    expect(clip.sourceTempoBpm, 117.5);
    expect(clip.stretchToProjectTempo, isFalse);
    expect(clip.tempoStretchPreservePitch, isFalse);
    expect(clip.tempoWarpMode, 'repitch');

    await action.undo();
    expect(clip.trimEnd, const Duration(seconds: 4));
    expect(clip.audioDuration, const Duration(seconds: 4));
    expect(clip.sourceTempoBpm, 117.5);
    expect(clip.stretchToProjectTempo, isFalse);
    expect(clip.tempoStretchPreservePitch, isFalse);
    expect(clip.tempoWarpMode, 'repitch');
    expect(syncCalls, 2);

    final persisted = action.toPersistedUndoCommand();
    expect(persisted['oldClipOwnedState'], isA<Map>());
    expect(persisted['newClipOwnedState'], isA<Map>());
  });
}
