import 'dart:convert';
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
  test('512-note edits preserve exact data through undo redo and serialization', () async {
    final clip = await _midiClip();
    final oldNotes = clip.midiNotes.map((note) => note.copy()).toList();
    final notes = List.generate(512, (i) => MidiNote(
      id: 'budget-$i', pitch: 48 + i % 24, startBeat: i / 128,
      lengthBeats: 0.03125, velocity: 0.75,
    ));
    final expected = notes.map((note) => note.toJson()).toList();
    var failSync = false;
    final action = EditMidiClipAction(
      tracks: [clip], originalIndex: 0, oldNotes: oldNotes, newNotes: notes,
      oldInstrumentId: clip.instrumentId, newInstrumentId: clip.instrumentId,
      oldInstrumentName: clip.instrumentName, newInstrumentName: clip.instrumentName,
      oldInstrumentParams: const {}, newInstrumentParams: const {},
      oldTrimEnd: clip.trimEnd, newTrimEnd: clip.trimEnd,
      oldAudioDuration: clip.audioDuration, newAudioDuration: clip.audioDuration,
      applyToClip: (target, values, id, name, params, state) async {
        target.midiNotes = values.map((note) => note.copy()).toList();
        if (failSync && values.length == 512) throw StateError('synthetic sync failure');
      },
    );
    await action.redo();
    expect(clip.midiNotes.map((note) => note.toJson()).toList(), expected);
    expect(clip.toJson('budget.mid')['midiNotes'], expected);
    await action.undo();
    expect(clip.midiNotes.map((note) => note.toJson()).toList(),
        oldNotes.map((note) => note.toJson()).toList());
    await action.redo();
    expect(clip.midiNotes.map((note) => note.toJson()).toList(), expected);
    expect(action.toPersistedUndoCommand()['newNotes'], expected);
    final directory = await Directory.systemTemp.createTemp('pro4-note-budget-');
    try {
      final file = File('${directory.path}/clip.json');
      await file.writeAsString(jsonEncode(clip.toJson('budget.mid')));
      final saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final reopened = (saved['midiNotes'] as List)
          .map((note) => MidiNote.fromJson(Map<String, dynamic>.from(note as Map)))
          .map((note) => note.toJson()).toList();
      expect(reopened, expected);
    } finally {
      await directory.delete(recursive: true);
    }
    await action.undo();
    failSync = true;
    await expectLater(action.redo(), throwsStateError);
    expect(clip.midiNotes.map((note) => note.toJson()).toList(),
        oldNotes.map((note) => note.toJson()).toList());
  });

  test('MIDI undo persistence retains fractional millisecond bounds', () async {
    final clip = await _midiClip();
    const before = Duration(microseconds: 17777778);
    const after = Duration(microseconds: 22857143);
    final action = EditMidiClipAction(
      tracks: [clip], originalIndex: 0,
      oldNotes: clip.midiNotes, newNotes: clip.midiNotes,
      oldInstrumentId: clip.instrumentId, newInstrumentId: clip.instrumentId,
      oldInstrumentName: clip.instrumentName, newInstrumentName: clip.instrumentName,
      oldInstrumentParams: const {}, newInstrumentParams: const {},
      oldTrimEnd: before, newTrimEnd: after,
      oldAudioDuration: before, newAudioDuration: after,
      applyToClip: (target, notes, id, name, params, state) async {},
    );
    final persisted = action.toPersistedUndoCommand();
    for (final field in ['oldTrimEndMs', 'oldAudioDurationMs']) {
      expect(clipTrimFromMilliseconds(persisted[field] as num, isMidi: true), before);
    }
    for (final field in ['newTrimEndMs', 'newAudioDurationMs']) {
      expect(clipTrimFromMilliseconds(persisted[field] as num, isMidi: true), after);
    }
    await action.redo();
    expect(clip.trimEnd, after);
    await action.undo();
    expect(clip.trimEnd, before);
  });

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
      ..tempoWarpMode = 'repitch'
      ..instrumentParams = <String, double>{
        'attackMs': 18.0,
        'decayMs': 120.0,
        'sustainLevel': 0.86,
        'releaseMs': 180.0,
      };
    final notes = clip.midiNotes.map((note) => note.copy()).toList();
    final action = EditMidiClipAction(
      tracks: <AudioTrack>[clip],
      originalIndex: 0,
      oldNotes: notes,
      newNotes: notes.map((note) => note.copy()).toList(),
      oldInstrumentId: clip.instrumentId,
      oldInstrumentName: clip.instrumentName,
      oldInstrumentParams: const <String, double>{
        'attackMs': 18.0,
        'decayMs': 120.0,
        'sustainLevel': 0.86,
        'releaseMs': 180.0,
      },
      oldHostedInstrumentStateBase64: 'old-state',
      newInstrumentId: 'sfz.guitar.clean_electric',
      newInstrumentName: 'Electric Guitar',
      newInstrumentParams: const <String, double>{
        'outputGain': 2.0,
        'attackMs': 0.0,
        'decayMs': 0.0,
        'sustainLevel': 0.65,
        'releaseMs': 0.0,
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
      'attackMs': 0.0,
      'decayMs': 0.0,
      'sustainLevel': 0.65,
      'releaseMs': 0.0,
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
    expect(clip.instrumentParams, <String, double>{
      'attackMs': 18.0,
      'decayMs': 120.0,
      'sustainLevel': 0.86,
      'releaseMs': 180.0,
    });
    expect(clip.midiNotes.single.id, 'old');
    expect(clip.trimEnd, const Duration(seconds: 4));
    expect(clip.sourceTempoBpm, 117.5);
    expect(clip.stretchToProjectTempo, isFalse);
    expect(clip.tempoStretchPreservePitch, isFalse);
    expect(clip.tempoWarpMode, 'repitch');

    await action.redo();
    expect(clip.instrumentId, 'sfz.guitar.clean_electric');
    expect(clip.instrumentParams['releaseMs'], 0.0);
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
