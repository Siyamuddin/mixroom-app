import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_preparer.dart';
import 'package:mixroom/helpers/subscription_limits.dart';
import 'package:mixroom/models/models.dart';

Future<AudioTrack> _midiClip() => AudioTrack.create(
  file: File('/tmp/v3-midi.wav'),
  originalFile: File('/tmp/v3-midi.wav'),
  audioDuration: const Duration(seconds: 2),
  trimStart: Duration.zero,
  trimEnd: const Duration(seconds: 2),
  offset: 1,
  rowIndex: 0,
  rowId: 42,
  clipId: 'clip-42',
  label: 'Keys',
  clipKind: ClipKind.midi,
  instrumentId: 'piano',
  instrumentName: 'Piano',
  midiNotes: <MidiNote>[
    MidiNote(id: 'n1', pitch: 60, startBeat: 0, lengthBeats: 1, velocity: 0.8),
  ],
);

Future<AudioTrack> _audioClip() => AudioTrack.create(
  file: File('/tmp/v3-audio.wav'),
  originalFile: File('/tmp/v3-audio.wav'),
  audioDuration: const Duration(seconds: 4),
  trimStart: Duration.zero,
  trimEnd: const Duration(seconds: 4),
  offset: 1,
  rowIndex: 0,
  rowId: 42,
  clipId: 'clip-42',
  label: 'Vocal',
  sourceTempoBpm: 180,
  stretchToProjectTempo: true,
  tempoStretchPreservePitch: false,
  tempoWarpMode: 'repitch',
);

Map<String, dynamic> _validation() => <String, dynamic>{
  'client_state_digest': 'digest-42',
  'project': <String, dynamic>{'tempo_bpm': 120, 'project_key': 'C minor'},
  'rows': <Map<String, dynamic>>[
    <String, dynamic>{
      'row_index': 0,
      'row_id': 42,
      'name': 'Keys',
      'lane_kind': 'instrument',
      'instrument_id': 'piano',
      'role_override': 'synth',
      'gain': 1.0,
      'pan': 0.5,
      'row_color': 0xFF79A8FF,
      'effects': const <Object>[],
      'automation_targets': const <Object>[],
      'top_role': 'synth',
      'source_type': 'midi',
      'audio_analysis': <String, double>{'centroid_hz': 1200},
      'role_hints': <String>['synth'],
      'labels': <String>['Keys'],
      'files': <String>['v3-midi.wav'],
      'has_audio': false,
      'group_id': 'music',
    },
  ],
  'groups': <Map<String, dynamic>>[
    <String, dynamic>{
      'group_id': 'music',
      'name': 'Music',
      'member_row_indices': <int>[0],
      'gain': 2.0,
      'pan': 0.5,
      'muted': false,
      'soloed': false,
      'effects': const <Object>[],
    },
  ],
  'master': <String, dynamic>{
    'gain': 2.0,
    'pan': 0.5,
    'effects': const <Object>[],
  },
  'clips': <Map<String, dynamic>>[
    <String, dynamic>{
      'clip_index': 0,
      'clip_id': 'clip-42',
      'row_id': 42,
      'clip_kind': 'midi',
      'label': 'Keys',
      'file': 'v3-midi.wav',
    },
  ],
  'selection': <String, dynamic>{
    'selected_row_index': 0,
    'selected_clip_indices': <int>[0],
    'primary_selected_clip_index': 0,
  },
};

Map<String, dynamic> _clientContext() => <String, dynamic>{
  'ai_v3_row_state': <Map<String, dynamic>>[
    <String, dynamic>{'row_id': 42, 'muted': false, 'soloed': false},
  ],
  'allowed_instrument_ids': <String>['piano'],
  'ai_v3_instrument_catalog': <Map<String, dynamic>>[
    <String, dynamic>{
      'instrument_id': 'piano',
      'name': 'Piano',
      'playable_pitch_ranges': <Map<String, int>>[
        <String, int>{'low': 21, 'high': 108},
      ],
    },
  ],
  'allowed_builtin_effects': <String>['Reverb'],
  'ai_v3_playhead_ms': 1500,
  'ai_v3_transport': <String, dynamic>{
    'playing': false,
    'recording': false,
    'metronome_enabled': true,
    'loop_enabled': true,
    'loop_start_ms': 1000,
    'loop_end_ms': 5000,
  },
  'ai_v3_tempo_stretch_enabled': false,
  'ai_v3_clip_timeline_lengths_ms': <String, double>{'clip-42': 4000},
  'row_creation_limit': null,
  'current_rows': 1,
  'ai_v3_library_assets': <Map<String, dynamic>>[
    <String, dynamic>{
      'asset_id': 'sample:kick',
      'path': 'Pack/Kick.wav',
      'role': 'kick',
      'bpm': 120,
    },
  ],
};

Future<
  ({
    Map<String, dynamic> validation,
    List<AudioTrack> tracks,
    Map<String, dynamic> client,
  })
>
_largeProjectFixture({required int rowCount, required int clipCount}) async {
  final rows = <Map<String, dynamic>>[];
  final clips = <Map<String, dynamic>>[];
  final tracks = <AudioTrack>[];
  final rowState = <Map<String, dynamic>>[];
  final timelineLengths = <String, double>{};
  for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
    final rowId = 1000 + rowIndex;
    final isMidi = rowIndex.isOdd;
    rows.add(<String, dynamic>{
      'row_index': rowIndex,
      'row_id': rowId,
      'name': 'Synthetic row $rowIndex',
      'lane_kind': isMidi ? 'instrument' : 'audio',
      'instrument_id': isMidi ? 'piano' : null,
      'gain': 2.0,
      'pan': 0.5,
      'row_color': 0,
      'effects': const <Object>[],
      'automation_targets': const <Object>[],
      'source_type': isMidi ? 'midi' : 'audio',
      'has_audio': !isMidi,
      'group_id': 'group-${rowIndex ~/ 2}',
    });
    rowState.add(<String, dynamic>{
      'row_id': rowId,
      'muted': false,
      'soloed': false,
    });
  }
  for (var clipIndex = 0; clipIndex < clipCount; clipIndex++) {
    final rowIndex = clipIndex % rowCount;
    final rowId = 1000 + rowIndex;
    final isMidi = rowIndex.isOdd;
    final clipId = 'synthetic-clip-${clipIndex.toString().padLeft(4, '0')}';
    final notes = isMidi && clipIndex == 1
        ? List<MidiNote>.generate(
            512,
            (index) => MidiNote(
              id: 'note-$index',
              pitch: 48 + index % 24,
              startBeat: (index % 32) / 4,
              lengthBeats: 0.25,
              velocity: 0.75,
            ),
          )
        : <MidiNote>[];
    final path = '/tmp/$clipId.wav';
    tracks.add(
      await AudioTrack.create(
        file: File(path),
        originalFile: File(path),
        audioDuration: const Duration(seconds: 4),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 4),
        offset: clipIndex / 10,
        rowIndex: rowIndex,
        rowId: rowId,
        clipId: clipId,
        label: 'Synthetic clip $clipIndex',
        clipKind: isMidi ? ClipKind.midi : ClipKind.audio,
        instrumentId: isMidi ? 'piano' : '',
        instrumentName: isMidi ? 'Piano' : '',
        midiNotes: notes,
      ),
    );
    clips.add(<String, dynamic>{
      'clip_index': clipIndex,
      'clip_id': clipId,
      'row_id': rowId,
      'clip_kind': isMidi ? 'midi' : 'audio',
      'label': 'Synthetic clip $clipIndex',
      'file': '$clipId.wav',
      'instrument_id': isMidi ? 'piano' : null,
    });
    timelineLengths[clipId] = 4000;
  }
  final groups = <Map<String, dynamic>>[
    for (var rowIndex = 0; rowIndex + 1 < rowCount; rowIndex += 2)
      <String, dynamic>{
        'group_id': 'group-${rowIndex ~/ 2}',
        'name': 'Synthetic group ${rowIndex ~/ 2}',
        'member_row_indices': <int>[rowIndex, rowIndex + 1],
        'gain': 2.0,
        'pan': 0.5,
        'muted': false,
        'soloed': false,
        'effects': const <Object>[],
      },
  ];
  final validation = <String, dynamic>{
    'client_state_digest': 'large-$rowCount-$clipCount',
    'project': <String, dynamic>{'tempo_bpm': 120},
    'rows': rows,
    'groups': groups,
    'master': <String, dynamic>{
      'gain': 2.0,
      'pan': 0.5,
      'effects': const <Object>[],
    },
    'clips': clips,
    'selection': <String, dynamic>{},
  };
  final client = _clientContext()
    ..['ai_v3_row_state'] = rowState
    ..['ai_v3_clip_timeline_lengths_ms'] = timelineLengths
    ..['current_rows'] = rowCount
    ..['ai_v3_library_assets'] = <Map<String, dynamic>>[
      for (var index = 0; index < 250; index++)
        <String, dynamic>{
          'asset_id': 'asset-$index',
          'path': 'Synthetic/asset-$index.wav',
          'role': index.isEven ? 'drums' : 'melodic',
        },
    ];
  return (validation: validation, tracks: tracks, client: client);
}

void main() {
  test('MIDI context preserves sub-millisecond clip boundaries', () async {
    final clip = await _midiClip();
    for (final bpm in <double>[84, 108, 120, 137, 240]) {
      for (final beats in <double>[32, 7.375]) {
        clip.trimStart = const Duration(microseconds: 123456);
        clip.trimEnd =
            clip.trimStart +
            Duration(microseconds: (beats * 60000000 / bpm).round());
        final saved = clip.toJson('precision.mid');
        clip.trimStart = clipTrimFromMilliseconds(
          saved['trimStartMs'] as num,
          isMidi: true,
        );
        clip.trimEnd = clipTrimFromMilliseconds(
          saved['trimEndMs'] as num,
          isMidi: true,
        );
        final context = const AiV3CoreContextBuilder().build(
          profile: AiV3ContextProfile.essential,
          userRequest: 'Replace the notes.',
          conversation: const <Map<String, String>>[],
          validationState: _validation(),
          audioTracks: <AudioTrack>[clip],
          clientContext: _clientContext(),
          bpm: bpm,
          beatsPerBar: 4,
          beatUnit: 4,
        );
        final length =
            ((context.data['clips'] as List).single as Map)['length_beats']
                as double;
        expect(length, closeTo(beats, bpm / 120000000 + 1e-12));
        AiV3Plan replacement(double end) => AiV3Plan.fromJson({
          'schema_version': aiV3PlanVersion,
          'outcome': 'plan',
          'user_message': 'Replaced the notes.',
          'question_options': <String>[],
          'commands': [
            {
              'command_id': 'replace',
              'type': 'midi.replace_notes',
              'arguments': {
                'clip_id': 'clip-42',
                'notes': [
                  {
                    'pitch': 66,
                    'start_beat': end - 1,
                    'length_beats': 1.0,
                    'velocity': 0.8,
                  },
                ],
              },
            },
          ],
        });
        const preparer = AiV3CommandPreparer();
        expect(
          preparer.prepare(plan: replacement(length), context: context).actions,
          hasLength(1),
        );
        // Whole-ms truncation can advertise a boundary just below 32 beats.
        if ((bpm == 84 || bpm == 108) && beats == 32) {
          expect(
            preparer.prepare(plan: replacement(32), context: context).actions,
            hasLength(1),
          );
        }
        expect(
          () => preparer.prepare(
            plan: replacement(length + 0.002 * bpm / 60),
            context: context,
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_midi_note_out_of_bounds',
            ),
          ),
        );
      }
    }
  });

  test(
    'duration precision does not round saved MIDI or alter audio context',
    () async {
      for (final midi in <bool>[true, false]) {
        final clip = midi ? await _midiClip() : await _audioClip();
        clip.trimStart = Duration.zero;
        clip.trimEnd = Duration(microseconds: midi ? 22856000 : 22856999);
        final context = const AiV3CoreContextBuilder().build(
          profile: AiV3ContextProfile.essential,
          userRequest: 'Inspect the clip.',
          conversation: const <Map<String, String>>[],
          validationState: _validation(),
          audioTracks: <AudioTrack>[clip],
          clientContext: _clientContext(),
          bpm: 84,
          beatsPerBar: 4,
          beatUnit: 4,
        );
        expect(
          ((context.data['clips'] as List).single as Map)['length_beats'],
          22856 / 1000 * 84 / 60,
        );
      }
    },
  );

  test('builds deterministic complete identity and MIDI context', () async {
    final clip = await _midiClip();
    const builder = AiV3CoreContextBuilder();

    final first = builder.build(
      profile: AiV3ContextProfile.essential,
      userRequest: 'Transpose it.',
      conversation: const <Map<String, String>>[],
      validationState: _validation(),
      audioTracks: <AudioTrack>[clip],
      clientContext: _clientContext(),
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
    );
    final second = builder.build(
      profile: AiV3ContextProfile.essential,
      userRequest: 'Transpose it.',
      conversation: const <Map<String, String>>[],
      validationState: _validation(),
      audioTracks: <AudioTrack>[clip],
      clientContext: _clientContext(),
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
    );

    expect(first.canonicalJson, second.canonicalJson);
    expect(first.stateDigest, 'digest-42');
    expect(((first.data['selection'] as Map)['selected_row_id']), 42);
    final notes = ((first.data['clips'] as List).single as Map)['midi_notes'];
    expect(notes, hasLength(1));
    final project = first.data['project'] as Map;
    expect(project['generated_midi_policy'], aiV3GeneratedMidiPolicy);
    expect(project['plan_command_policy'], aiV3PlanCommandPolicy);
    expect(project['plan_output_policy'], aiV3PlanOutputPolicy);
    expect(project['playhead_ms'], 1500);
    expect(project['playhead_beat'], 3.0);
    final transport = first.data['transport'] as Map;
    expect(transport, <String, dynamic>{
      'playing': false,
      'recording': false,
      'metronome_enabled': true,
      'loop_enabled': true,
      'loop_start_ms': 1000,
      'loop_end_ms': 5000,
    });
    expect(transport, isNot(contains('playhead_ms')));
    expect(project['project_capacity_policy'], aiV3ProjectCapacityPolicy);
    expect((project['row_capacity'] as Map)['creation_limit'], isNull);
    expect((project['row_capacity'] as Map)['can_create'], isTrue);
    expect((project['row_capacity'] as Map).containsKey('policy'), isFalse);
    final row = (first.data['rows'] as List).single as Map;
    expect(row['gain_db'], -30.0);
    expect(row['pan_signed'], 0.0);
    expect(row['color'], 'blue');
    expect(row['role_override'], 'synth');
    expect(row['mix_processing_supported'], isTrue);
    expect(row['has_usable_signal'], isFalse);
    expect(row['analysis_available'], isTrue);
    expect(row['has_analyzable_audio'], isFalse);
    expect(row, isNot(contains('gain_ui')));
    expect(row, isNot(contains('pan_01')));
    expect(first.data['capabilities'], hasLength(aiV3CommandTypes.length));
    final group = (first.data['groups'] as List).single as Map;
    expect(group['group_id'], 'music');
    expect(group['member_row_ids'], <int>[42]);
    expect(group['collapsed'], isFalse);
    expect((first.data['master'] as Map)['gain_db'], 0.0);
  });

  test('capable context preserves rows and clips beyond former caps', () async {
    for (final shape in <(int, int)>[(33, 129), (120, 600)]) {
      final fixture = await _largeProjectFixture(
        rowCount: shape.$1,
        clipCount: shape.$2,
      );
      final context = const AiV3CoreContextBuilder().build(
        profile: AiV3ContextProfile.essential,
        userRequest: 'Inspect the complete synthetic project.',
        conversation: const <Map<String, String>>[],
        validationState: fixture.validation,
        audioTracks: fixture.tracks,
        clientContext: fixture.client,
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      );
      final rows = (context.data['rows'] as List).cast<Map>();
      final clips = (context.data['clips'] as List).cast<Map>();
      expect(rows, hasLength(shape.$1));
      expect(clips, hasLength(shape.$2));
      expect(
        rows.map((row) => row['row_id']).toList(),
        List<int>.generate(shape.$1, (index) => 1000 + index),
      );
      expect(
        clips.map((clip) => clip['clip_id']).toList(),
        List<String>.generate(
          shape.$2,
          (index) => 'synthetic-clip-${index.toString().padLeft(4, '0')}',
        ),
      );
      expect((clips[1]['midi_notes'] as List), hasLength(512));
      expect(utf8.encode(context.canonicalJson).length, lessThan(4000000));
    }
  });

  test('legacy context keeps finite capacity metadata', () async {
    final client = _clientContext()
      ..remove('row_creation_limit')
      ..['max_rows'] = 32;
    final context = const AiV3CoreContextBuilder().build(
      profile: AiV3ContextProfile.essential,
      userRequest: 'Inspect the project.',
      conversation: const <Map<String, String>>[],
      validationState: _validation(),
      audioTracks: <AudioTrack>[await _midiClip()],
      clientContext: client,
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
    );
    final project = context.data['project'] as Map;
    expect(project, isNot(contains('project_capacity_policy')));
    expect(project['row_capacity'], <String, dynamic>{
      'current_rows': 1,
      'max_rows': 32,
      'can_create': true,
    });
  });

  test('capable context rejects overflow instead of truncating', () async {
    final clip = await _midiClip();
    expect(
      () => const AiV3CoreContextBuilder().build(
        profile: AiV3ContextProfile.essential,
        userRequest: '界' * 1400000,
        conversation: const <Map<String, String>>[],
        validationState: _validation(),
        audioTracks: <AudioTrack>[clip],
        clientContext: _clientContext(),
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      ),
      throwsA(
        isA<AiV3ContextException>().having(
          (error) => error.code,
          'code',
          'v3_context_request_limit',
        ),
      ),
    );
  });

  test('preserves all existing notes above the generated-note budget', () async {
    final clip = await _midiClip();
    // Includes the next snapshot after adding 300 notes to a 300-note project.
    for (final count in [300, 512, 513, 600, 1024]) {
      clip.midiNotes = List.generate(
        count,
        (i) => MidiNote(
          id: 'note-$i',
          pitch: 60 + i % 12,
          startBeat: i / count,
          lengthBeats: 0.01,
          velocity: 0.8,
        ),
      );
      final context = const AiV3CoreContextBuilder().build(
        profile: AiV3ContextProfile.essential,
        userRequest: 'Rebalance without changing the notes.',
        conversation: const [],
        validationState: _validation(),
        audioTracks: [clip],
        clientContext: _clientContext(),
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      );
      final notes =
          ((context.data['clips'] as List).single as Map)['midi_notes'] as List;
      expect(notes, hasLength(count));
      for (var i = 0; i < count; i++) {
        expect(notes[i]['pitch'], clip.midiNotes[i].pitch);
        expect(notes[i]['start_beat'], clip.midiNotes[i].startBeat);
        expect(notes[i]['length_beats'], clip.midiNotes[i].lengthBeats);
        expect(notes[i]['velocity'], clip.midiNotes[i].velocity);
      }
    }
  });

  test(
    'does not confuse an unknown nonzero row color with cleared color',
    () async {
      final clip = await _midiClip();
      final validation = _validation();
      ((validation['rows'] as List).single as Map)['row_color'] = 0xFF123456;
      final context = const AiV3CoreContextBuilder().build(
        profile: AiV3ContextProfile.essential,
        userRequest: 'Clear the row color.',
        conversation: const <Map<String, String>>[],
        validationState: validation,
        audioTracks: <AudioTrack>[clip],
        clientContext: _clientContext(),
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      );

      expect(((context.data['rows'] as List).single as Map)['color'], 'custom');
    },
  );

  test('canonicalizes resource catalogs like the adaptive snapshot', () async {
    final client = _clientContext()
      ..['allowed_instrument_ids'] = <String>['piano', ' bass ', 'piano', '']
      ..['allowed_builtin_effects'] = <String>[
        'Reverb',
        ' Compressor ',
        'Reverb',
      ];
    final context = const AiV3CoreContextBuilder().build(
      profile: AiV3ContextProfile.essential,
      userRequest: 'Create a bass row.',
      conversation: const <Map<String, String>>[],
      validationState: _validation(),
      audioTracks: <AudioTrack>[await _midiClip()],
      clientContext: client,
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
    );

    expect(context.data['instruments'], <String>['bass', 'piano']);
    expect(context.data['instrument_catalog'], <Map<String, dynamic>>[
      <String, dynamic>{
        'instrument_id': 'piano',
        'name': 'Piano',
        'playable_pitch_ranges': <Map<String, int>>[
          <String, int>{'low': 21, 'high': 108},
        ],
      },
    ]);
    expect(
      (context.data['effects'] as List).map(
        (effect) => (effect as Map)['effect_id'],
      ),
      <String>['Compressor', 'Reverb'],
    );
  });

  test(
    'preserves every selectable instrument above the former 64 cap',
    () async {
      final instrumentIds = <String>[
        'piano',
        ...List<String>.generate(
          451,
          (index) => 'instrument-${index.toString().padLeft(3, '0')}',
        ),
      ];
      final client = _clientContext()
        ..['allowed_instrument_ids'] = instrumentIds
        ..['ai_v3_instrument_catalog'] = instrumentIds
            .map(
              (instrumentId) => <String, dynamic>{
                'instrument_id': instrumentId,
                'name': 'Instrument $instrumentId',
                'playable_pitch_ranges': <Map<String, int>>[
                  <String, int>{'low': 0, 'high': 127},
                ],
              },
            )
            .toList(growable: false);

      final context = const AiV3CoreContextBuilder().build(
        profile: AiV3ContextProfile.essential,
        userRequest: 'Create an instrument row.',
        conversation: const <Map<String, String>>[],
        validationState: _validation(),
        audioTracks: <AudioTrack>[await _midiClip()],
        clientContext: client,
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      );

      final catalog = (context.data['instrument_catalog'] as List)
          .whereType<Map>()
          .toList(growable: false);
      expect(context.data['instruments'], instrumentIds.toList()..sort());
      expect(catalog, hasLength(452));
      expect(
        catalog.map((entry) => entry['instrument_id']).toSet(),
        instrumentIds.toSet(),
      );
      expect(utf8.encode(context.canonicalJson).length, lessThan(4000000));
    },
  );

  test('preserves Free-tier effects and row capacity exactly', () async {
    final client = _clientContext()
      ..['allowed_builtin_effects'] = SubscriptionLimits.freeBuiltInEffects
          .toList(growable: false)
      ..['allowed_instrument_ids'] = <String>['sfz.vsco.upright_piano']
      ..['ai_v3_instrument_catalog'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'instrument_id': 'sfz.vsco.upright_piano',
          'name': 'Upright Piano',
          'playable_pitch_ranges': <Map<String, int>>[
            <String, int>{'low': 21, 'high': 108},
          ],
        },
      ]
      ..['row_creation_limit'] = SubscriptionLimits.freeRowsPerProject;
    final context = const AiV3CoreContextBuilder().build(
      profile: AiV3ContextProfile.essential,
      userRequest: 'Add a Free-tier effect.',
      conversation: const <Map<String, String>>[],
      validationState: _validation(),
      audioTracks: <AudioTrack>[await _midiClip()],
      clientContext: client,
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
    );

    final advertisedEffects = (context.data['effects'] as List)
        .map((effect) => (effect as Map)['effect_id'].toString())
        .toSet();
    expect(advertisedEffects, SubscriptionLimits.freeBuiltInEffects);
    expect(advertisedEffects, isNot(contains('Distortion')));
    expect(
      (context.data['project'] as Map)['row_capacity'],
      containsPair('creation_limit', SubscriptionLimits.freeRowsPerProject),
    );
    final advertisedInstruments = (context.data['instruments'] as List)
        .map((id) => id.toString())
        .toSet();
    expect(advertisedInstruments, isNotEmpty);
    expect(
      advertisedInstruments.difference(
        SubscriptionLimits.freeBuiltInInstrumentIds,
      ),
      isEmpty,
    );
  });

  test('preserves existing Free-project state outside current creation entitlements', () {
      final validation = _validation();
      final baseRow = Map<String, dynamic>.from(
        (validation['rows'] as List).single as Map,
      );
      validation['rows'] = List<Map<String, dynamic>>.generate(6, (index) {
        final rowId = 100 + index;
        return <String, dynamic>{
          ...baseRow,
          'row_index': index,
          'row_id': rowId,
          'name': index == 0 ? 'Preserved Strings' : 'Audio ${index + 1}',
          'lane_kind': index == 0 ? 'instrument' : 'audio',
          'instrument_id': index == 0 ? 'paid-orchestral-strings' : null,
          'source_type': index == 0 ? 'midi' : 'audio',
          'has_audio': false,
          'group_id': null,
        };
      });
      validation['clips'] = <Map<String, dynamic>>[];
      validation['groups'] = <Map<String, dynamic>>[];
      validation['selection'] = <String, dynamic>{};

      final client = _clientContext();
      client
        ..['ai_v3_clip_timeline_lengths_ms'] = <String, double>{}
        ..['allowed_instrument_ids'] = <String>['sfz.vsco.upright_piano']
        ..['ai_v3_instrument_catalog'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'instrument_id': 'sfz.vsco.upright_piano',
            'name': 'Upright Piano',
            'playable_pitch_ranges': <Map<String, int>>[
              <String, int>{'low': 21, 'high': 108},
            ],
          },
        ]
        ..['row_creation_limit'] = SubscriptionLimits.freeRowsPerProject
        ..['current_rows'] = 6
        ..['ai_v3_row_state'] = <Map<String, dynamic>>[
          for (var index = 0; index < 6; index++)
            <String, dynamic>{
              'row_id': 100 + index,
              'muted': false,
              'soloed': false,
            },
        ];

      final context = const AiV3CoreContextBuilder().build(
        profile: AiV3ContextProfile.essential,
        userRequest: 'Restart playback.',
        conversation: const <Map<String, String>>[],
        validationState: validation,
        audioTracks: const <AudioTrack>[],
        clientContext: client,
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      );

      final rows = (context.data['rows'] as List).whereType<Map>().toList();
      final capacity = (context.data['project'] as Map)['row_capacity'] as Map;
      expect(rows, hasLength(6));
      expect(rows.first['instrument_id'], 'paid-orchestral-strings');
      expect(context.data['instruments'], <String>['sfz.vsco.upright_piano']);
      expect(capacity['current_rows'], 6);
      expect(capacity['creation_limit'], SubscriptionLimits.freeRowsPerProject);
      expect(capacity['can_create'], isFalse);
  });

  test(
    'describes preserved instruments without making them selectable',
    () async {
      final validation = _validation();
      final row = (validation['rows'] as List).single as Map<String, dynamic>;
      row['instrument_id'] = 'paid-marimba';
      final client = _clientContext()
        ..['allowed_instrument_ids'] = <String>['piano']
        ..['ai_v3_instrument_catalog'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'instrument_id': 'piano',
            'name': 'Piano',
            'playable_pitch_ranges': <Map<String, int>>[
              <String, int>{'low': 21, 'high': 108},
            ],
          },
          <String, dynamic>{
            'instrument_id': 'paid-marimba',
            'name': 'Marimba',
            'playable_pitch_ranges': <Map<String, int>>[
              <String, int>{'low': 45, 'high': 96},
            ],
          },
        ];
      final clip = await _midiClip();
      clip.instrumentId = 'paid-marimba';

      final context = const AiV3CoreContextBuilder().build(
        profile: AiV3ContextProfile.essential,
        userRequest: 'Rewrite the marimba rhythm.',
        conversation: const <Map<String, String>>[],
        validationState: validation,
        audioTracks: <AudioTrack>[clip],
        clientContext: client,
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      );

      expect(context.data['instruments'], <String>['piano']);
      expect(
        (context.data['instrument_catalog'] as List)
            .map((entry) => (entry as Map)['instrument_id'])
            .toSet(),
        <String>{'piano', 'paid-marimba'},
      );
    },
  );

  test('includes exact one-shot audio stretch facts', () async {
    final clip = await _audioClip();
    final validation = _validation();
    final row = (validation['rows'] as List).single as Map<String, dynamic>;
    row['name'] = 'Vocal';
    row['lane_kind'] = 'audio';
    row['instrument_id'] = null;
    row['source_type'] = 'audio';
    row['has_audio'] = true;
    final clipState =
        (validation['clips'] as List).single as Map<String, dynamic>;
    clipState['clip_kind'] = 'audio';
    clipState['label'] = 'Vocal';
    final client = _clientContext();
    client['ai_v3_tempo_stretch_enabled'] = true;
    client['ai_v3_clip_timeline_lengths_ms'] = <String, double>{
      'clip-42': 6000,
    };

    final context = const AiV3CoreContextBuilder().build(
      profile: AiV3ContextProfile.essential,
      userRequest: 'Double this clip.',
      conversation: const <Map<String, String>>[],
      validationState: validation,
      audioTracks: <AudioTrack>[clip],
      clientContext: client,
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
    );

    expect((context.data['project'] as Map)['tempo_stretch_enabled'], isTrue);
    final facts = (context.data['clips'] as List).single as Map;
    expect(facts['length_beats'], 8.0);
    expect(facts['timeline_length_beats'], 12.0);
    expect(facts['stretch_to_project_tempo'], isTrue);
    expect(facts['tempo_stretch_preserve_pitch'], isFalse);
    expect(facts['source_tempo_bpm'], 180.0);
  });

  test('profiles are additive without changing identities', () async {
    final clip = await _midiClip();
    const builder = AiV3CoreContextBuilder();
    AiV3CoreContext build(AiV3ContextProfile profile) => builder.build(
      profile: profile,
      userRequest: 'Edit it.',
      conversation: const <Map<String, String>>[],
      validationState: _validation(),
      audioTracks: <AudioTrack>[clip],
      clientContext: _clientContext(),
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
    );

    final essential = build(AiV3ContextProfile.essential);
    final enriched = build(AiV3ContextProfile.enriched);
    final rich = build(AiV3ContextProfile.rich);

    Object? rowId(AiV3CoreContext context) =>
        ((context.data['rows'] as List).single as Map)['row_id'];
    expect(rowId(essential), rowId(enriched));
    expect(rowId(enriched), rowId(rich));
    expect(
      essential.canonicalJson.length,
      lessThan(enriched.canonicalJson.length),
    );
    expect(enriched.canonicalJson.length, lessThan(rich.canonicalJson.length));
    final enrichedRow = (enriched.data['rows'] as List).single as Map;
    expect(enrichedRow['source_type'], 'midi');
    expect(enrichedRow['audio_analysis'], isA<Map>());
  });

  test(
    'supports more than 250 library assets within the byte envelope',
    () async {
    final clip = await _midiClip();
      final client = _clientContext()
        ..['ai_v3_library_assets'] = <Map<String, dynamic>>[
          for (var index = 0; index < 512; index++)
            <String, dynamic>{
              'asset_id': 'sample-$index',
              'path': 'Pack/sample-$index.wav',
              'role': index.isEven ? 'drums' : 'melodic',
            },
        ];
      final context = const AiV3CoreContextBuilder().build(
        profile: AiV3ContextProfile.essential,
        userRequest: 'Edit it.',
        conversation: const <Map<String, String>>[],
        validationState: _validation(),
        audioTracks: <AudioTrack>[clip],
        clientContext: client,
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      );

      expect(context.data['library_assets'], hasLength(512));
      expect(context.libraryAssetCountTotal, 512);
      expect(context.libraryAssetCountIncluded, 512);
      expect(context.libraryAssetCountOmitted, 0);
      expect(
        utf8.encode(context.canonicalJson).length,
        lessThanOrEqualTo(AiV3CoreContextBuilder.maxCanonicalBytes),
      );
    },
  );

  test('compacts an oversized library by request relevance', () async {
    final clip = await _midiClip();
    final client = _clientContext()
      ..['ai_v3_library_assets'] = <Map<String, dynamic>>[
        for (var index = 0; index < 320; index++)
          <String, dynamic>{
            'asset_id': 'sample-${index.toString().padLeft(3, '0')}',
            'path':
                'Pack/${index == 319 ? 'priority-kick' : 'sample-$index'}-${'x' * 16000}.wav',
            'role': index == 319 ? 'kick' : 'other',
          },
      ];
    final context = const AiV3CoreContextBuilder().build(
      profile: AiV3ContextProfile.essential,
      userRequest: 'Add a kick sample.',
      conversation: const <Map<String, String>>[],
      validationState: _validation(),
      audioTracks: <AudioTrack>[clip],
      clientContext: client,
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
    );
    final retained = (context.data['library_assets'] as List)
        .whereType<Map>()
        .toList(growable: false);

    expect(context.libraryAssetCountTotal, 320);
    expect(context.libraryAssetCountIncluded, lessThan(320));
    expect(context.libraryAssetCountOmitted, greaterThan(0));
    expect(retained.any((asset) => asset['asset_id'] == 'sample-319'), isTrue);
    final summary = context.data['library_catalog_summary'] as Map;
    expect(summary['total_asset_count'], 320);
    expect(summary['included_asset_count'], context.libraryAssetCountIncluded);
    expect(summary['omitted_asset_count'], context.libraryAssetCountOmitted);
    expect(summary['role_counts'], isNotEmpty);
    expect(summary['top_level_folder_counts'], isNotEmpty);
    expect(
      utf8.encode(context.canonicalJson).length,
      lessThanOrEqualTo(AiV3CoreContextBuilder.maxCanonicalBytes),
    );
  });

  test('keeps a large library intact while context remains below 4 MB', () async {
    final clip = await _midiClip();
    final client = _clientContext()
      ..['ai_v3_library_assets'] = <Map<String, dynamic>>[
        for (var index = 0; index < 20000; index++)
          <String, dynamic>{
            'asset_id': 'sample:${index.toRadixString(16).padLeft(16, '0')}',
            'path':
                'Pack/${index == 19999 ? 'priority-kick' : 'sample-$index'}.wav',
            'role': index == 19999 ? 'kick' : 'other',
          },
      ];
    final context = const AiV3CoreContextBuilder().build(
      profile: AiV3ContextProfile.essential,
      userRequest: 'Add the priority kick sample.',
      conversation: const <Map<String, String>>[],
      validationState: _validation(),
      audioTracks: <AudioTrack>[clip],
      clientContext: client,
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
    );
    final retained = (context.data['library_assets'] as List)
        .whereType<Map>()
        .toList(growable: false);

    expect(context.libraryAssetCountTotal, 20000);
    expect(context.libraryAssetCountIncluded, 20000);
    expect(context.libraryAssetCountOmitted, 0);
    expect(
      retained.any((asset) => asset['asset_id'] == 'sample:0000000000004e1f'),
      isTrue,
    );
    expect(
      utf8.encode(context.canonicalJson).length,
      lessThanOrEqualTo(AiV3CoreContextBuilder.maxCanonicalBytes),
    );
  });

  test('rejects contradictory stable identity indexes', () async {
    final clip = await _midiClip();
    final invalid = _validation();
    (invalid['rows'] as List).add(
      Map<String, dynamic>.from((invalid['rows'] as List).single as Map),
    );

    expect(
      () => const AiV3CoreContextBuilder().build(
        profile: AiV3ContextProfile.essential,
        userRequest: 'Edit it.',
        conversation: const <Map<String, String>>[],
        validationState: invalid,
        audioTracks: <AudioTrack>[clip],
        clientContext: _clientContext(),
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      ),
      throwsA(
        isA<AiV3ContextException>().having(
          (error) => error.code,
          'code',
          'prototype_context_row_id_duplicate',
        ),
      ),
    );
  });

  test(
    'exposes exact row effect-instance IDs and rejects missing IDs',
    () async {
      final clip = await _midiClip();
      final validation = _validation();
      final row = (validation['rows'] as List).single as Map<String, dynamic>;
      row['effects'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'effect_index': 0,
          'effect_instance_id': 'native-instance-1',
          'effect_id': 'builtin.reverb',
          'name': 'Reverb',
          'bypassed': false,
          'parameters': const <Object>[],
        },
      ];
      final context = const AiV3CoreContextBuilder().build(
        profile: AiV3ContextProfile.essential,
        userRequest: 'Bypass the reverb.',
        conversation: const <Map<String, String>>[],
        validationState: validation,
        audioTracks: <AudioTrack>[clip],
        clientContext: _clientContext(),
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      );
      final effect =
          (((context.data['rows'] as List).single as Map)['effects'] as List)
                  .single
              as Map;
      expect(effect['effect_instance_id'], 'native-instance-1');
      expect(effect['effect_id'], 'builtin.reverb');

      (row['effects'] as List).single.remove('effect_instance_id');
      expect(
        () => const AiV3CoreContextBuilder().build(
          profile: AiV3ContextProfile.essential,
          userRequest: 'Bypass the reverb.',
          conversation: const <Map<String, String>>[],
          validationState: validation,
          audioTracks: <AudioTrack>[clip],
          clientContext: _clientContext(),
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
        ),
        throwsA(
          isA<AiV3ContextException>().having(
            (error) => error.code,
            'code',
            'prototype_context_effect_instance_invalid',
          ),
        ),
      );
    },
  );
}
