import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
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
        MidiNote(
          id: 'n1',
          pitch: 60,
          startBeat: 0,
          lengthBeats: 1,
          velocity: 0.8,
        ),
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
      'project': <String, dynamic>{
        'tempo_bpm': 120,
        'project_key': 'C minor',
      },
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
      'ai_v3_clip_timeline_lengths_ms': <String, double>{
        'clip-42': 4000,
      },
      'max_rows': 24,
      'current_rows': 1,
      'row_creation_policy': 'Rows may be created up to the app row limit.',
      'ai_v3_library_assets': <Map<String, dynamic>>[
        <String, dynamic>{
          'asset_id': 'sample:kick',
          'path': 'Pack/Kick.wav',
          'role': 'kick',
          'bpm': 120,
        },
      ],
    };

void main() {
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
    expect(
      ((first.data['selection'] as Map)['selected_row_id']),
      42,
    );
    final notes = ((first.data['clips'] as List).single as Map)['midi_notes'];
    expect(notes, hasLength(1));
    final project = first.data['project'] as Map;
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
    expect((project['row_capacity'] as Map)['max_rows'], 24);
    expect((project['row_capacity'] as Map)['can_create'], isTrue);
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

  test('does not confuse an unknown nonzero row color with cleared color',
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
  });

  test('canonicalizes resource catalogs like the adaptive snapshot', () async {
    final client = _clientContext()
      ..['allowed_instrument_ids'] = <String>[
        'piano',
        ' bass ',
        'piano',
        '',
      ]
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
    expect(
      (context.data['effects'] as List)
          .map((effect) => (effect as Map)['effect_id']),
      <String>['Compressor', 'Reverb'],
    );
  });

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
    expect(essential.canonicalJson.length,
        lessThan(enriched.canonicalJson.length));
    expect(enriched.canonicalJson.length, lessThan(rich.canonicalJson.length));
    final enrichedRow = (enriched.data['rows'] as List).single as Map;
    expect(enrichedRow['source_type'], 'midi');
    expect(enrichedRow['audio_analysis'], isA<Map>());
  });

  test('rejects envelope overflow rather than truncating', () async {
    final clip = await _midiClip();
    const builder = AiV3CoreContextBuilder(maxClips: 0);

    expect(
      () => builder.build(
        profile: AiV3ContextProfile.essential,
        userRequest: 'Edit it.',
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
          'prototype_context_clip_limit',
        ),
      ),
    );
  });

  test('independently enforces row, MIDI-note, and library envelopes',
      () async {
    final clip = await _midiClip();

    for (final entry in <({AiV3CoreContextBuilder builder, String code})>[
      (
        builder: const AiV3CoreContextBuilder(maxRows: 0),
        code: 'prototype_context_row_limit',
      ),
      (
        builder: const AiV3CoreContextBuilder(maxMidiNotes: 0),
        code: 'prototype_context_midi_note_limit',
      ),
      (
        builder: const AiV3CoreContextBuilder(maxLibraryAssets: 0),
        code: 'prototype_context_library_limit',
      ),
    ]) {
      expect(
        () => entry.builder.build(
          profile: AiV3ContextProfile.essential,
          userRequest: 'Edit it.',
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
            entry.code,
          ),
        ),
      );
    }
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

  test('exposes exact row effect-instance IDs and rejects missing IDs',
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
            .single as Map;
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
      throwsA(isA<AiV3ContextException>().having(
        (error) => error.code,
        'code',
        'prototype_context_effect_instance_invalid',
      )),
    );
  });
}
