import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/assistant_action_utils.dart';
import 'package:mixroom/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssistantActionUtils primitive parsing', () {
    test('toActionMap converts dynamic maps safely', () {
      expect(
        AssistantActionUtils.toActionMap({'a': 1}),
        equals({'a': 1}),
      );
      expect(
        AssistantActionUtils.toActionMap(<Object?, Object?>{'b': 2}),
        equals({'b': 2}),
      );
      expect(
        AssistantActionUtils.toActionMap('bad'),
        isEmpty,
      );
    });

    test('toActionDouble and toActionInt parse numerics', () {
      expect(AssistantActionUtils.toActionDouble(12), 12.0);
      expect(AssistantActionUtils.toActionDouble('12.5'), 12.5);
      expect(AssistantActionUtils.toActionDouble('abc'), isNull);

      expect(AssistantActionUtils.toActionInt(12.2), 12);
      expect(AssistantActionUtils.toActionInt('12.8'), 13);
      expect(AssistantActionUtils.toActionInt('abc'), isNull);
      expect(AssistantActionUtils.toActionInt(double.infinity), isNull);
    });

    test('toActionBool supports bool/num/string forms', () {
      expect(AssistantActionUtils.toActionBool(true), isTrue);
      expect(AssistantActionUtils.toActionBool(1), isTrue);
      expect(AssistantActionUtils.toActionBool(0), isFalse);
      expect(AssistantActionUtils.toActionBool('yes'), isTrue);
      expect(AssistantActionUtils.toActionBool('no'), isFalse);
      expect(AssistantActionUtils.toActionBool('1'), isTrue);
      expect(AssistantActionUtils.toActionBool('0'), isFalse);
      expect(
          AssistantActionUtils.toActionBool('unknown', fallback: true), isTrue);
    });
  });

  group('AssistantActionUtils normalization', () {
    test('normalizeTutorialTargetId maps aliases and catch-all keys', () {
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('play'),
        'tutorial:transport:play',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('project settings'),
        'tutorial:project_settings',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('mute button'),
        'tutorial:mute',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('solo track'),
        'tutorial:solo',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('toolbar'),
        'tutorial:toolbar',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('track_area'),
        'tutorial:timeline',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('clip'),
        'tutorial:timeline',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('clip_edge'),
        'tutorial:timeline',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('piano_roll'),
        'tutorial:piano_roll',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('note_properties'),
        'tutorial:piano_roll',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('My Custom Button'),
        'tutorial:my_custom_button',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('  play!!!  '),
        'tutorial:transport:play',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId('row:3'),
        'row:3',
      );
      expect(
        AssistantActionUtils.normalizeTutorialTargetId(''),
        isNull,
      );
    });

    test('compactTutorialPlaybackTargets keeps bridge plus final target', () {
      expect(
        AssistantActionUtils.compactTutorialPlaybackTargets(const <String>[
          'row:0',
          'row:0:effects_tab',
          'row:0:fx_list',
          'row:0:fx_contains:reverb',
          'row:0:fx_contains:reverb:param:mix',
        ]),
        equals(const <String>[
          'row:0',
          'row:0:effects_tab',
          'row:0:fx_contains:reverb:param:mix',
        ]),
      );

      expect(
        AssistantActionUtils.compactTutorialPlaybackTargets(const <String>[
          'tutorial:toolbar',
          'tutorial:export',
        ]),
        equals(const <String>[
          'tutorial:toolbar',
          'tutorial:export',
        ]),
      );
    });

    test('tutorial playback timing favors quick previews and longer final hold',
        () {
      expect(AssistantActionUtils.tutorialPreviewDurationMs(3200), 1024);
      expect(AssistantActionUtils.tutorialPreviewPauseMs(1024), 563);
      expect(AssistantActionUtils.tutorialFinalDurationMs(3200), 3200);

      expect(AssistantActionUtils.tutorialPreviewDurationMs(1200), 900);
      expect(AssistantActionUtils.tutorialFinalDurationMs(1200), 2800);

      expect(AssistantActionUtils.tutorialPreviewDurationMs(8000), 1400);
      expect(AssistantActionUtils.tutorialFinalDurationMs(8000), 5200);
    });

    test('normalizeClipEditOperation maps synonyms', () {
      expect(
        AssistantActionUtils.normalizeClipEditOperation('remove_coughs'),
        'dialog_cleanup',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('remove_phrase'),
        'dialog_remove_range',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('shorten_pauses'),
        'dialog_tighten_pauses',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('boost_quiet'),
        'dialog_lift_quiet',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('trim_start'),
        'trim',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('split_clip'),
        'cut',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('splice_clip'),
        'cut',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('time_stretch'),
        'stretch',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('shift_clip'),
        'move',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('copy_clip'),
        'duplicate',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('trim_silence'),
        'auto_trim',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('bpm_align'),
        'auto_bpm_align',
      );
      expect(
        AssistantActionUtils.normalizeClipEditOperation('move'),
        'move',
      );
    });

    test('normalizeMidiComposeOperation maps synonyms', () {
      expect(
        AssistantActionUtils.normalizeMidiComposeOperation('write_bassline'),
        'compose_bassline',
      );
      expect(
        AssistantActionUtils.normalizeMidiComposeOperation('generate_pattern'),
        'compose_pattern',
      );
      expect(
        AssistantActionUtils.normalizeMidiComposeOperation('set_notes'),
        'replace_notes',
      );
      expect(
        AssistantActionUtils.normalizeMidiComposeOperation('append'),
        'append_notes',
      );
      expect(
        AssistantActionUtils.normalizeMidiComposeOperation('splice_notes'),
        'chop_notes',
      );
      expect(
        AssistantActionUtils.normalizeMidiComposeOperation('ratchet'),
        'chop_notes',
      );
    });

    test('resolves musical clip move positions from measures and beats', () {
      final startMs = AssistantActionUtils.resolveMoveMusicalStartMs(
        data: const {'new_start_measure': 3},
        target: const {},
        bpm: 120,
      );
      final deltaMs = AssistantActionUtils.resolveMoveMusicalDeltaMs(
        data: const {'delta_measures': 4},
        target: const {},
        bpm: 120,
      );
      final beatMs = AssistantActionUtils.resolveMoveMusicalStartMs(
        data: const {'new_start_beat': 5},
        target: const {},
        bpm: 120,
      );

      expect(startMs, 4000.0);
      expect(deltaMs, 8000.0);
      expect(beatMs, 2000.0);
    });

    test('supports non-4-4 musical clip move timing when specified', () {
      final startMs = AssistantActionUtils.resolveMoveMusicalStartMs(
        data: const {
          'new_start_measure': 3,
          'beats_per_bar': 3,
        },
        target: const {},
        bpm: 120,
      );

      expect(startMs, 3000.0);
    });
  });

  group('AssistantActionUtils clip analysis', () {
    test('estimateAutoTrimBoundsMs finds active region and applies padding',
        () {
      final waveform = <double>[0, 0, 0.01, 0.2, 0.6, 0.5, 0.2, 0.01, 0, 0];
      final bounds = AssistantActionUtils.estimateAutoTrimBoundsMs(
        waveform: waveform,
        fullMs: 1000,
        trimStartMs: 0,
        trimEndMs: 1000,
        thresholdFloor: 0.02,
        thresholdRatio: 0.1,
        paddingMs: 10,
      );

      expect(bounds, isNotNull);
      // first active ~ index 3 => ~300ms, with padding => ~290ms
      expect(bounds!.key, inInclusiveRange(285.0, 295.0));
      // last active ~ index 6 => end at 7/10 => 700ms, +padding => ~710ms
      expect(bounds.value, inInclusiveRange(705.0, 715.0));
    });

    test('estimateAutoTrimBoundsMs returns null for silent or invalid input',
        () {
      expect(
        AssistantActionUtils.estimateAutoTrimBoundsMs(
          waveform: const [],
          fullMs: 1000,
          trimStartMs: 0,
          trimEndMs: 1000,
        ),
        isNull,
      );
      expect(
        AssistantActionUtils.estimateAutoTrimBoundsMs(
          waveform: List<double>.filled(12, 0.0),
          fullMs: 1000,
          trimStartMs: 0,
          trimEndMs: 1000,
        ),
        isNull,
      );
      expect(
        AssistantActionUtils.estimateAutoTrimBoundsMs(
          waveform: const [0.0, 0.0, 0.1],
          fullMs: 1.0,
          trimStartMs: 0,
          trimEndMs: 1.0,
        ),
        isNull,
      );
    });
  });

  group('AssistantActionUtils MIDI parsing', () {
    test('pitchClassFromToken handles sharps and flats', () {
      expect(AssistantActionUtils.pitchClassFromToken('C'), 0);
      expect(AssistantActionUtils.pitchClassFromToken('C#'), 1);
      expect(AssistantActionUtils.pitchClassFromToken('Db'), 1);
      expect(AssistantActionUtils.pitchClassFromToken('Bb'), 10);
      expect(AssistantActionUtils.pitchClassFromToken('invalid'), isNull);
    });

    test('midiPitchFromRaw parses ints and note names', () {
      expect(AssistantActionUtils.midiPitchFromRaw(60), 60);
      expect(AssistantActionUtils.midiPitchFromRaw('60'), 60);
      expect(AssistantActionUtils.midiPitchFromRaw('C3'), 48);
      expect(AssistantActionUtils.midiPitchFromRaw('Db4'), 61);
      expect(
        AssistantActionUtils.midiPitchFromRaw('G#', fallbackOctave: 2),
        44,
      );
      expect(AssistantActionUtils.midiPitchFromRaw('200'), 127);
      expect(AssistantActionUtils.midiPitchFromRaw('-10'), 0);
      expect(AssistantActionUtils.midiPitchFromRaw('nope'), isNull);
    });

    test('rootMidiFromChordToken creates usable bass roots', () {
      expect(
          AssistantActionUtils.rootMidiFromChordToken('Cmaj7', octave: 2), 36);
      expect(AssistantActionUtils.rootMidiFromChordToken('D', octave: 2), 38);
      expect(AssistantActionUtils.rootMidiFromChordToken('G7', octave: 2), 43);
      expect(AssistantActionUtils.rootMidiFromChordToken('Bb', octave: 2), 46);
    });

    test('progression tokenization works for list and string', () {
      expect(
        AssistantActionUtils.progressionTokensFromRaw('C-D-G-C'),
        equals(const ['C', 'D', 'G', 'C']),
      );
      expect(
        AssistantActionUtils.progressionTokensFromRaw([' C ', 'Dm', '', 'G']),
        equals(const ['C', 'Dm', 'G']),
      );
    });

    test('fallbackMidiNotesFromProgression generates deterministic bassline',
        () {
      final notes = AssistantActionUtils.fallbackMidiNotesFromProgression(
        progressionRaw: const ['C', 'D', 'G', 'C'],
        beatsPerChord: 4,
        notesPerChord: 4,
        octave: 2,
        velocity: 0.8,
        noteIdPrefix: 't',
        nowMicros: 123,
      );

      expect(notes.length, 16);
      expect(notes.first.pitch, 36); // C2
      expect(notes.first.startBeat, 0.0);
      expect(notes[1].startBeat, 1.0);
      expect(notes[4].startBeat, 4.0); // next chord
      expect(notes[4].pitch, 38); // D2
      expect(notes[8].pitch, 43); // G2
      expect(notes.first.velocity, greaterThan(notes[1].velocity));
      expect(notes.first.id, startsWith('t_123_'));
    });

    test('fallbackMidiNotesFromProgression handles empty/invalid progression',
        () {
      expect(
        AssistantActionUtils.fallbackMidiNotesFromProgression(
          progressionRaw: '',
        ),
        isEmpty,
      );
      expect(
        AssistantActionUtils.fallbackMidiNotesFromProgression(
          progressionRaw: const ['???', ''],
        ),
        isEmpty,
      );
    });

    test('chopMidiNotes splits notes into requested subdivision', () {
      final chopped = AssistantActionUtils.chopMidiNotes(
        notes: <MidiNote>[
          MidiNote(
            id: 'n1',
            pitch: 60,
            startBeat: 0.0,
            lengthBeats: 1.0,
            velocity: 0.8,
          ),
        ],
        subdivision: 16,
        nowMicros: 42,
      );

      expect(chopped.length, 4);
      expect(chopped[0].startBeat, closeTo(0.0, 0.0001));
      expect(chopped[1].startBeat, closeTo(0.25, 0.0001));
      expect(chopped[2].startBeat, closeTo(0.5, 0.0001));
      expect(chopped[3].startBeat, closeTo(0.75, 0.0001));
      for (final note in chopped) {
        expect(note.lengthBeats, closeTo(0.25, 0.0001));
        expect(note.id, startsWith('ai_chop_42_'));
      }
    });

    test('chopMidiNotes respects range and leaves outer segments intact', () {
      final chopped = AssistantActionUtils.chopMidiNotes(
        notes: <MidiNote>[
          MidiNote(
            id: 'n1',
            pitch: 48,
            startBeat: 0.0,
            lengthBeats: 1.0,
            velocity: 0.9,
          ),
        ],
        subdivision: 16,
        fromBeat: 0.25,
        toBeat: 0.75,
        nowMicros: 99,
      );

      expect(chopped.length, 4);
      expect(chopped[0].startBeat, closeTo(0.0, 0.0001));
      expect(chopped[0].lengthBeats, closeTo(0.25, 0.0001));
      expect(chopped[1].startBeat, closeTo(0.25, 0.0001));
      expect(chopped[1].lengthBeats, closeTo(0.25, 0.0001));
      expect(chopped[2].startBeat, closeTo(0.5, 0.0001));
      expect(chopped[2].lengthBeats, closeTo(0.25, 0.0001));
      expect(chopped[3].startBeat, closeTo(0.75, 0.0001));
      expect(chopped[3].lengthBeats, closeTo(0.25, 0.0001));
    });

    test('chopMidiNotes supports velocity decay per slice', () {
      final chopped = AssistantActionUtils.chopMidiNotes(
        notes: <MidiNote>[
          MidiNote(
            id: 'n1',
            pitch: 60,
            startBeat: 0.0,
            lengthBeats: 1.0,
            velocity: 1.0,
          ),
        ],
        subdivision: 16,
        velocityDecayPerSlice: 0.1,
        velocityFloor: 0.0,
        nowMicros: 7,
      );

      expect(chopped.length, 4);
      expect(chopped[0].velocity, closeTo(1.0, 0.0001));
      expect(chopped[1].velocity, closeTo(0.9, 0.0001));
      expect(chopped[2].velocity, closeTo(0.8, 0.0001));
      expect(chopped[3].velocity, closeTo(0.7, 0.0001));
    });
  });
}
