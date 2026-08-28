import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_compact_core.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_planning_snapshot.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/models/project_state.dart';

const _capturedAt = '2026-07-20T10:00:00.000Z';

Future<_Fixture> _fixture({
  int midiNoteCount = 2,
  int libraryAssetCount = 2,
  int extraAudioClipCount = 0,
}) async {
  final audio = await AudioTrack.create(
    file: File('/tmp/Guide Vocal.wav'),
    originalFile: File('/tmp/Guide Vocal-original.wav'),
    audioDuration: const Duration(seconds: 4),
    trimStart: const Duration(milliseconds: 100),
    trimEnd: const Duration(milliseconds: 3900),
    offset: 0.5,
    rowIndex: 0,
    rowId: 10,
    engineClipId: 100,
    clipId: 'clip-audio',
    label: 'Guide Vocal',
    volumeAutomation: <AutomationPoint>[
      AutomationPoint(x: 0, volume: 0.2),
      AutomationPoint(x: 1000, volume: 0.8),
    ],
    hostedInstrumentStateBase64: 'opaque-state-must-not-be-captured',
  );
  final midi = await AudioTrack.create(
    file: File('/tmp/Keys.mid.wav'),
    originalFile: File('/tmp/Keys-original.mid.wav'),
    audioDuration: const Duration(seconds: 4),
    trimEnd: const Duration(seconds: 4),
    offset: 1,
    rowIndex: 1,
    rowId: 20,
    engineClipId: 200,
    clipId: 'clip-midi',
    label: 'Keys',
    clipKind: ClipKind.midi,
    instrumentId: 'piano',
    instrumentName: 'Piano',
    instrumentParams: <String, double>{'brightness': 0.4},
    midiNotes: List<MidiNote>.generate(
      midiNoteCount,
      (index) => MidiNote(
        id: 'note-$index',
        pitch: 60 + (index % 12),
        startBeat: index * 0.25,
        lengthBeats: 0.25,
        velocity: 0.75,
      ),
    ),
    hostedInstrumentStateBase64: 'opaque-plugin-state',
  );
  final tracks = <AudioTrack>[audio, midi];
  for (var index = 0; index < extraAudioClipCount; index++) {
    tracks.add(await AudioTrack.create(
      file: File('/tmp/extra-$index.wav'),
      originalFile: File('/tmp/extra-$index.wav'),
      audioDuration: const Duration(seconds: 1),
      trimEnd: const Duration(seconds: 1),
      offset: 2 + index.toDouble(),
      rowIndex: 0,
      rowId: 10,
      engineClipId: 300 + index,
      clipId: 'extra-${index.toString().padLeft(3, '0')}',
      label: 'Extra $index',
    ));
  }
  final reverb = EffectState(
    effectIndex: 0,
    instanceId: 'fx-row-10-reverb',
    effectId: 'Reverb',
    name: 'Reverb',
    isBypassed: false,
    parameters: const <EffectParameterState>[
      EffectParameterState(
        id: 'mix',
        name: 'Mix',
        type: 'float',
        value: 0.25,
        min: 0,
        max: 1,
      ),
    ],
  );
  final rows = <RowState>[
    RowState(
      rowIndex: 0,
      rowId: 10,
      rowName: 'Guide Vocal',
      laneKind: 'audio',
      roleOverride: 'vocals',
      groupId: 'vocals',
      clips: <ClipState>[
        ClipState(
          startMs: 500,
          endMs: 4300,
          fileName: 'Guide Vocal.wav',
        ),
      ],
      approxRms: 0.2,
      approxCrest: 2.1,
      roleProbs: const <String, double>{'vocals': 0.92},
      roleConsistency: 0.9,
      clipTopRoles: const <String>['vocals'],
      audioStats: const <String, double>{'centroid_hz': 1350},
      interpretation: RowInterpretationState.empty,
      gain0to3: 1.5,
      pan0To1: 0.45,
      effects: <EffectState>[reverb],
      volumeAutomation: <AutomationPoint>[
        AutomationPoint(x: 0, volume: 0.4),
        AutomationPoint(x: 1000, volume: 0.9),
      ],
      hasAudio: true,
    ),
    RowState(
      rowIndex: 1,
      rowId: 20,
      rowName: 'Keys',
      laneKind: 'instrument',
      instrumentId: 'piano',
      instrumentName: 'Piano',
      clips: <ClipState>[
        ClipState(startMs: 1000, endMs: 5000, fileName: 'Keys.mid.wav'),
      ],
      approxRms: 0.1,
      approxCrest: 1.8,
      roleProbs: const <String, double>{'synth': 0.8},
      roleConsistency: 1,
      clipTopRoles: const <String>['synth'],
      audioStats: const <String, double>{'centroid_hz': 900},
      interpretation: RowInterpretationState.empty,
      gain0to3: 2,
      pan0To1: 0.6,
      effects: const <EffectState>[],
      volumeAutomation: <AutomationPoint>[
        AutomationPoint(x: 0, volume: 1),
      ],
      hasAudio: false,
    ),
  ];
  final project = ProjectState(
    bpm: 120,
    projectKey: 'C minor',
    estimatedKey: 'C minor',
    estimatedKeyConfidence: 0.8,
    masterGain0to3: 2,
    masterPan0to1: 0.5,
    maxRows: 32,
    rows: rows,
    trackGroups: <TrackGroup>[
      TrackGroup(
        id: 'vocals',
        name: 'Vocals',
        rowIds: const <int>[10],
        effects: <EffectSnapshot>[
          EffectSnapshot(
            'Compressor',
            false,
            <String, dynamic>{'threshold': 0.3},
            stateBase64: 'group-state-must-not-be-captured',
          ),
        ],
      ),
    ],
    masterEffects: const <EffectState>[
      EffectState(
        effectIndex: 0,
        instanceId: 'fx-master-limiter',
        effectId: 'Limiter',
        name: 'Limiter',
        isBypassed: false,
        parameters: <EffectParameterState>[],
      ),
    ],
    overlapMatrix: const <List<int>>[
      <int>[0, 1],
      <int>[1, 0],
    ],
    overlapRatioMatrix: const <List<double>>[
      <double>[0, 0.5],
      <double>[0.5, 0],
    ],
  );
  final validation = <String, dynamic>{
    'client_state_digest': 'state-digest-1',
    'project': <String, dynamic>{
      'tempo_bpm': 120,
      'project_key': 'C minor',
      'estimated_key': 'C minor',
    },
    'rows': <Map<String, dynamic>>[
      <String, dynamic>{
        'row_id': 10,
        'row_index': 0,
        'name': 'Guide Vocal',
        'lane_kind': 'audio',
        'gain': 1.5,
        'pan': 0.45,
        'group_id': 'vocals',
        'has_audio': true,
        'approx_rms': 0.2,
        'effects': <Map<String, dynamic>>[
          <String, dynamic>{
            'effect_instance_id': 'fx-row-10-reverb',
            'effect_id': 'Reverb',
            'name': 'Reverb',
            'bypassed': false,
            'parameters': const <Object>[],
          },
        ],
        'automation_targets': <Map<String, dynamic>>[
          <String, dynamic>{
            'target_id': 'row:10:volume',
            'kind': 'gain',
          },
        ],
      },
      <String, dynamic>{
        'row_id': 20,
        'row_index': 1,
        'name': 'Keys',
        'lane_kind': 'instrument',
        'instrument_id': 'piano',
        'gain': 2.0,
        'pan': 0.6,
        'has_audio': false,
        'approx_rms': 0.1,
        'effects': const <Object>[],
        'automation_targets': const <Object>[],
      },
    ],
    'clips': <Map<String, dynamic>>[
      <String, dynamic>{
        'clip_index': 0,
        'clip_id': 'clip-audio',
        'row_id': 10,
        'clip_kind': 'audio',
        'label': 'Guide Vocal',
        'file': 'Guide Vocal.wav',
      },
      <String, dynamic>{
        'clip_index': 1,
        'clip_id': 'clip-midi',
        'row_id': 20,
        'clip_kind': 'midi',
        'label': 'Keys',
        'file': 'Keys.mid.wav',
        'instrument_id': 'piano',
      },
      for (var index = 0; index < extraAudioClipCount; index++)
        <String, dynamic>{
          'clip_index': index + 2,
          'clip_id': 'extra-${index.toString().padLeft(3, '0')}',
          'row_id': 10,
          'clip_kind': 'audio',
          'label': 'Extra $index',
          'file': 'extra-$index.wav',
        },
    ],
    'groups': <Map<String, dynamic>>[
      <String, dynamic>{
        'group_id': 'vocals',
        'name': 'Vocals',
        'member_row_indices': <int>[0],
        'gain': 2.0,
        'pan': 0.5,
        'muted': false,
        'soloed': false,
        'collapsed': false,
        'effects': const <Object>[],
      },
    ],
    'master': <String, dynamic>{
      'gain': 2.0,
      'pan': 0.5,
      'effects': const <Object>[],
      'automation_targets': <Map<String, dynamic>>[
        <String, dynamic>{'target_id': 'master_gain'},
      ],
    },
    'automation_clips': <Map<String, dynamic>>[
      <String, dynamic>{'automation_clip_id': 'auto-1', 'row_id': 10},
    ],
    'selection': <String, dynamic>{
      'selected_row_index': 0,
      'selected_clip_indices': <int>[0, 1],
      'primary_selected_clip_index': 1,
    },
  };
  final client = <String, dynamic>{
    'ai_v3_row_state': <Map<String, dynamic>>[
      <String, dynamic>{'row_id': 10, 'muted': false, 'soloed': true},
      <String, dynamic>{'row_id': 20, 'muted': true, 'soloed': false},
    ],
    'ai_v3_row_automation_points': <String, dynamic>{
      '10': <String, dynamic>{
        'volume': <Map<String, dynamic>>[
          <String, dynamic>{'time_ms': 0.0, 'value': 0.25},
          <String, dynamic>{'time_ms': 2000.0, 'value': 0.75},
        ],
      },
    },
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
      for (final clip in tracks)
        clip.clipId: (clip.trimEnd - clip.trimStart).inMilliseconds.toDouble(),
    },
    'max_rows': 32,
    'current_rows': 2,
    'row_creation_policy': 'Rows may be created up to the app row limit.',
    'allowed_instrument_ids': <String>['piano', 'bass'],
    'ai_v3_instrument_catalog': <Map<String, dynamic>>[
      <String, dynamic>{
        'instrument_id': 'piano',
        'name': 'Piano',
        'playable_pitch_ranges': <Map<String, int>>[
          <String, int>{'low': 21, 'high': 108},
        ],
      },
      <String, dynamic>{'instrument_id': 'bass', 'name': 'Bass'},
    ],
    'allowed_builtin_effects': <String>['Reverb', 'Limiter'],
    'ai_v3_library_assets': List<Map<String, dynamic>>.generate(
      libraryAssetCount,
      (index) => <String, dynamic>{
        'asset_id': 'sample-$index',
        'path': '/library/sample-$index.wav',
        'role': index.isEven ? 'kick' : 'snare',
      },
    ),
    'plugin_access': 'all_plugins',
    'ai_capabilities': <String>['daw.effects', 'daw.midi'],
    'ai_v3_prototype_enabled': true,
    'api_key': 'must-never-be-captured',
    'authorization': 'Bearer must-never-be-captured',
  };
  return _Fixture(
    project: project,
    tracks: tracks,
    validation: validation,
    client: client,
  );
}

PlanningSnapshotV3 _build(_Fixture fixture) => AiV3PlanningSnapshotBuilder(
      idFactory: () => 'snapshot-fixed',
      clock: () => DateTime.parse(_capturedAt),
    ).build(
      project: fixture.project,
      audioTracks: fixture.tracks,
      validationState: fixture.validation,
      clientContext: fixture.client,
      beatsPerBar: 4,
      beatUnit: 4,
      projectId: 'project-1',
      pendingPlan: <String, dynamic>{'outcome': 'plan'},
      pendingPlanId: 'plan-fixed',
      requestMode: 'modify_pending_plan',
    );

void main() {
  test('captures complete planning facts and exposes stable indexes', () async {
    final snapshot = _build(await _fixture());

    expect(snapshot.stateDigest, 'state-digest-1');
    expect(snapshot.rowById.keys, <int>[10, 20]);
    expect(snapshot.clipById.keys, <String>['clip-audio', 'clip-midi']);
    expect(snapshot.groupById.keys, <String>['vocals']);
    expect(
      snapshot.effectInstanceById.keys,
      <String>['fx-row-10-reverb', 'fx-master-limiter'],
    );
    expect(snapshot.libraryAssetById, hasLength(2));
    expect(
      ((snapshot.rowById[10]!['automation_targets'] as List).single
          as Map)['target_id'],
      'volume',
    );
    expect(
      ((snapshot.data['selection'] as Map)['primary_selected_clip_id']),
      'clip-midi',
    );
    expect(
      ((snapshot.data['request_state'] as Map)['pending_plan_id']),
      'plan-fixed',
    );
    expect(
      (snapshot.clipById['clip-midi']!['midi_notes'] as List),
      hasLength(2),
    );
    expect(snapshot.data['project']['tempo_stretch_enabled'], isFalse);
    expect(snapshot.clipById['clip-audio']!['timeline_duration_ms'], 3800.0);
    expect(
        snapshot.clipById['clip-audio']!['stretch_to_project_tempo'], isFalse);
    expect(snapshot.clipById['clip-audio']!['tempo_stretch_preserve_pitch'],
        isFalse);
    expect(
      (((snapshot.rowById[10]!['effects'] as List).single as Map)['parameters']
          as List),
      hasLength(1),
    );
    expect(snapshot.rowById[10]!['volume_automation'], hasLength(2));
    expect(
      (snapshot.rowById[10]!['automation_points'] as Map)['volume'],
      <Map<String, dynamic>>[
        <String, dynamic>{'time_ms': 0.0, 'value': 0.25},
        <String, dynamic>{'time_ms': 2000.0, 'value': 0.75},
      ],
    );
    expect(snapshot.data['automation_clips'], hasLength(1));
    expect(
      ((snapshot.data['request_state'] as Map)['pending_plan']
          as Map)['outcome'],
      'plan',
    );
    expect((snapshot.safeMetadata['counts'] as Map)['midi_notes'], 2);
  });

  test('one-shot context and adaptive snapshot agree on authoritative facts',
      () async {
    final fixture = await _fixture();
    final snapshot = _build(fixture);
    final oneShot = const AiV3CoreContextBuilder().build(
      profile: AiV3ContextProfile.essential,
      userRequest: 'Edit the project.',
      conversation: const <Map<String, String>>[],
      validationState: fixture.validation,
      audioTracks: fixture.tracks,
      clientContext: fixture.client,
      bpm: fixture.project.bpm,
      beatsPerBar: 4,
      beatUnit: 4,
      projectId: 'project-1',
    );

    expect(oneShot.stateDigest, snapshot.stateDigest);
    expect(
      (oneShot.data['project'] as Map)['bpm'],
      (snapshot.data['project'] as Map)['bpm'],
    );
    expect(
      (oneShot.data['project'] as Map)['row_capacity'],
      (snapshot.data['project'] as Map)['row_capacity'],
    );
    expect(oneShot.data['transport'], snapshot.data['transport']);
    expect(oneShot.data['transport'] as Map, isNot(contains('playhead_ms')));
    expect(snapshot.data['transport'] as Map, isNot(contains('playhead_ms')));
    expect((oneShot.data['project'] as Map)['playhead_ms'], 1500);
    expect((snapshot.data['project'] as Map)['playhead_ms'], 1500);
    final oneShotSelection = oneShot.data['selection'] as Map;
    final snapshotSelection = snapshot.data['selection'] as Map;
    expect(
      oneShotSelection,
      <String, dynamic>{
        'selected_row_id': snapshotSelection['selected_row_id'],
        'selected_clip_ids': snapshotSelection['selected_clip_ids'],
        'primary_selected_clip_id':
            snapshotSelection['primary_selected_clip_id'],
      },
    );
    expect(
      oneShot.data['instruments'],
      (snapshot.data['catalogs'] as Map)['instrument_ids'],
    );
    expect(
      oneShot.data['instrument_catalog'],
      (snapshot.data['catalogs'] as Map)['instrument_catalog'],
    );

    final oneShotRows = <int, Map>{
      for (final row in (oneShot.data['rows'] as List).cast<Map>())
        row['row_id'] as int: row,
    };
    for (final entry in snapshot.rowById.entries) {
      final expected = entry.value;
      final actual = oneShotRows[entry.key]!;
      expect(actual['display_index'], expected['display_index']);
      expect(actual['name'], expected['name']);
      expect(actual['lane_kind'], expected['lane_kind']);
      expect(actual['instrument_id'], expected['instrument_id']);
      expect(actual['group_id'], expected['group_id']);
      expect(
        actual['muted'],
        (expected['mixer'] as Map)['muted'],
      );
      expect(
        actual['soloed'],
        (expected['mixer'] as Map)['soloed'],
      );
      expect(actual['clip_ids'], expected['clip_ids']);
      expect(
        (actual['effects'] as List)
            .cast<Map>()
            .map((effect) => effect['effect_instance_id']),
        (expected['effects'] as List)
            .cast<Map>()
            .map((effect) => effect['effect_instance_id']),
      );
    }

    final oneShotClips = <String, Map>{
      for (final clip in (oneShot.data['clips'] as List).cast<Map>())
        clip['clip_id'].toString(): clip,
    };
    final bpm = fixture.project.bpm;
    for (final entry in snapshot.clipById.entries) {
      final expected = entry.value;
      final actual = oneShotClips[entry.key]!;
      expect(actual['row_id'], expected['row_id']);
      expect(actual['kind'], expected['kind']);
      expect(actual['instrument_id'], expected['instrument_id']);
      expect(
        actual['start_beat'],
        closeTo((expected['start_seconds'] as num) * bpm / 60, 1e-9),
      );
      expect(
        actual['length_beats'],
        closeTo(
          ((expected['trim_end_ms'] as num) -
                  (expected['trim_start_ms'] as num)) *
              bpm /
              60000,
          1e-9,
        ),
      );
    }

    final oneShotGroups = <String, Map>{
      for (final group in (oneShot.data['groups'] as List).cast<Map>())
        group['group_id'].toString(): group,
    };
    for (final entry in snapshot.groupById.entries) {
      expect(
        oneShotGroups[entry.key]!['member_row_ids'],
        entry.value['member_row_ids'],
      );
      expect(
        oneShotGroups[entry.key]!['collapsed'],
        entry.value['collapsed'],
      );
    }
  });

  test('deep copies sources and deep-freezes every exposed collection',
      () async {
    final fixture = await _fixture();
    final snapshot = _build(fixture);

    fixture.tracks[1].midiNotes.first.pitch = 12;
    fixture.tracks[0].volumeAutomation.first.volume = 1;
    ((fixture.validation['automation_clips'] as List).single as Map)['row_id'] =
        999;
    ((fixture.client['ai_v3_library_assets'] as List).first as Map)['path'] =
        '/changed.wav';
    fixture.project.rows.first.volumeAutomation.first.volume = 0;

    expect(
      (((snapshot.clipById['clip-midi']!['midi_notes'] as List).first
          as Map)['pitch']),
      60,
    );
    expect(
      (((snapshot.clipById['clip-audio']!['volume_automation'] as List).first
          as Map)['value']),
      0.2,
    );
    expect(
      ((snapshot.data['automation_clips'] as List).single as Map)['row_id'],
      10,
    );
    expect(snapshot.libraryAssetById['sample-0']!['path'],
        '/library/sample-0.wav');

    expect(
      () => snapshot.data['new'] = true,
      throwsUnsupportedError,
    );
    expect(
      () => (snapshot.data['rows'] as List).add('new'),
      throwsUnsupportedError,
    );
    expect(
      () => ((snapshot.data['project'] as Map)['row_capacity']
          as Map)['max_rows'] = 1,
      throwsUnsupportedError,
    );
  });

  test('canonical output and content hash are deterministic', () async {
    final firstFixture = await _fixture();
    final secondFixture = await _fixture();
    secondFixture.client = <String, dynamic>{
      for (final key in secondFixture.client.keys.toList().reversed)
        key: secondFixture.client[key],
    };

    final first = _build(firstFixture);
    final second = _build(secondFixture);

    expect(second.canonicalJson, first.canonicalJson);
    expect(second.contentDigest, first.contentDigest);
  });

  test('full snapshot does not apply current prompt context envelopes',
      () async {
    final snapshot = _build(await _fixture(
      midiNoteCount: 600,
      libraryAssetCount: 300,
    ));

    expect(
      (snapshot.clipById['clip-midi']!['midi_notes'] as List),
      hasLength(600),
    );
    expect(snapshot.libraryAssetById, hasLength(300));
  });

  test('rejects duplicate and contradictory stable identities', () async {
    final duplicate = await _fixture();
    duplicate.tracks.add(duplicate.tracks.first);
    expect(
      () => _build(duplicate),
      throwsA(isA<AiV3PlanningSnapshotException>().having(
        (error) => error.code,
        'code',
        'planning_snapshot_clip_id_duplicate',
      )),
    );

    final contradiction = await _fixture();
    ((contradiction.validation['rows'] as List).first as Map)['row_index'] = 1;
    expect(
      () => _build(contradiction),
      throwsA(isA<AiV3PlanningSnapshotException>().having(
        (error) => error.code,
        'code',
        'planning_snapshot_row_index_incomplete',
      )),
    );
  });

  test('serialization and capture metadata exclude secrets and opaque state',
      () async {
    final snapshot = _build(await _fixture());
    final serialized = snapshot.canonicalJson;
    final metadata = snapshot.safeMetadata.toString();

    expect(serialized, isNot(contains('must-never-be-captured')));
    expect(serialized, isNot(contains('opaque-plugin-state')));
    expect(serialized, isNot(contains('group-state-must-not-be-captured')));
    expect(serialized, isNot(contains('hostedInstrumentStateBase64')));
    expect(serialized, isNot(contains('normWaveformData')));
    expect(metadata, isNot(contains('/library/')));
    expect(metadata, isNot(contains('/tmp/')));
  });

  group('CompactCoreV3 shadow projection', () {
    test('projects ordinary-edit facts and bounded conversation', () async {
      final snapshot = _build(await _fixture());
      final conversation = List<Map<String, String>>.generate(
        10,
        (index) => <String, String>{
          'role': index.isEven ? 'user' : 'assistant',
          'content': 'turn-$index',
        },
      )..insert(0, <String, String>{'role': 'system', 'content': 'ignored'});
      final core = const AiV3CompactCoreBuilder().build(
        snapshot: snapshot,
        conversation: conversation,
      );

      expect(core.data['schema_version'], aiV3CompactCoreSchemaVersion);
      expect(core.data['snapshot_id'], 'snapshot-fixed');
      expect(core.data['state_digest'], 'state-digest-1');
      expect(core.data['transport'], snapshot.data['transport']);
      expect(core.data['transport'] as Map, isNot(contains('playhead_ms')));
      expect((core.data['rows'] as List), hasLength(2));
      final groups = (core.data['groups'] as List).cast<Map>();
      expect(groups, hasLength(1));
      expect(groups.single['group_id'], 'vocals');
      expect(groups.single['collapsed'], isFalse);
      final firstRow = (core.data['rows'] as List).first as Map;
      expect(firstRow['row_id'], 10);
      expect(firstRow['role_override'], 'vocals');
      expect(firstRow['gain_db'], isA<double>());
      expect(firstRow['pan_signed'], closeTo(-0.1, 1e-9));
      expect(firstRow['has_audio_content'], isTrue);
      expect(firstRow['analysis_available'], isTrue);
      final clips = core.data['clips'] as Map;
      expect(clips['total_count'], 2);
      expect(clips['returned_count'], 2);
      expect(clips['has_more'], isFalse);
      expect(((clips['items'] as List).first as Map)['clip_id'], 'clip-midi');
      expect(
        (core.data['request_state'] as Map),
        <String, dynamic>{
          'mode': 'modify_pending_plan',
          'pending_plan_id': 'plan-fixed',
        },
      );
      expect(
        core.data['selection'],
        <String, dynamic>{
          'selected_row_id': 10,
          'selected_clip_ids': <String>['clip-audio', 'clip-midi'],
          'primary_selected_clip_id': 'clip-midi',
        },
      );
      expect(
        (core.data['conversation'] as List)
            .map((turn) => (turn as Map)['content']),
        <String>[
          'turn-2',
          'turn-3',
          'turn-4',
          'turn-5',
          'turn-6',
          'turn-7',
          'turn-8',
          'turn-9',
        ],
      );
      expect((core.data['capability_domains'] as List), hasLength(11));
      final domains = (core.data['capability_domains'] as List)
          .cast<Map>()
          .toList(growable: false);
      final midiDomain =
          domains.singleWhere((domain) => domain['domain'] == 'midi');
      expect(midiDomain['retrieval_enabled'], isTrue);
      expect(midiDomain.containsKey('capabilities'), isFalse);
      expect(midiDomain.containsKey('command_types'), isFalse);
      final samplesDomain =
          domains.singleWhere((domain) => domain['domain'] == 'samples');
      expect(samplesDomain['retrieval_enabled'], isTrue);
      expect(samplesDomain.containsKey('capabilities'), isFalse);
      expect(samplesDomain.containsKey('command_types'), isFalse);
      final mixDomain =
          domains.singleWhere((domain) => domain['domain'] == 'mix');
      expect(mixDomain['retrieval_enabled'], isTrue);
      expect(mixDomain.containsKey('capabilities'), isFalse);
      expect(mixDomain.containsKey('command_types'), isFalse);
      final automationResources =
          (core.data['resources'] as Map)['automation_targets'] as Map;
      expect(automationResources['identities'], contains('volume'));
      expect(
        automationResources['identities'],
        isNot(contains('row:10:volume')),
      );
      expect(core.serializedBytes, greaterThan(0));
      expect(core.approximateTokens, greaterThan(0));
    });

    test('prioritizes selection and discloses clip truncation', () async {
      final core = const AiV3CompactCoreBuilder(maxClipSummaries: 1).build(
        snapshot: _build(await _fixture()),
        conversation: const <Map<String, String>>[],
      );
      final clips = core.data['clips'] as Map;

      expect(clips['total_count'], 2);
      expect(clips['returned_count'], 1);
      expect(clips['has_more'], isTrue);
      expect(((clips['items'] as List).single as Map)['clip_id'], 'clip-midi');
    });

    test('default clip envelope returns 64 of 65 without hiding truncation',
        () async {
      final core = const AiV3CompactCoreBuilder().build(
        snapshot: _build(await _fixture(extraAudioClipCount: 63)),
        conversation: const <Map<String, String>>[],
      );
      final clips = core.data['clips'] as Map;
      final returnedIds = (clips['items'] as List)
          .whereType<Map>()
          .map((clip) => clip['clip_id'])
          .toSet();

      expect(clips['total_count'], 65);
      expect(clips['returned_count'], 64);
      expect(clips['has_more'], isTrue);
      expect(returnedIds, contains('clip-midi'));
      expect(returnedIds, isNot(contains('extra-062')));
    });

    test('bounds resource identities while retaining known totals', () async {
      final core = const AiV3CompactCoreBuilder(
        maxResourceIdentities: 1,
      ).build(
        snapshot: _build(await _fixture()),
        conversation: const <Map<String, String>>[],
      );
      final effects = (core.data['resources'] as Map)['effects'] as Map;

      expect(effects['total_count'], 3);
      expect(effects['returned_count'], 1);
      expect(effects['has_more'], isTrue);
    });

    test('is deterministic, immutable, and excludes detailed domains',
        () async {
      final first = const AiV3CompactCoreBuilder().build(
        snapshot: _build(await _fixture()),
        conversation: const <Map<String, String>>[],
      );
      final second = const AiV3CompactCoreBuilder().build(
        snapshot: _build(await _fixture()),
        conversation: const <Map<String, String>>[],
      );
      final serialized = first.canonicalJson;

      expect(second.canonicalJson, first.canonicalJson);
      expect(() => first.data['x'] = true, throwsUnsupportedError);
      expect(
          () => (first.data['rows'] as List).add('x'), throwsUnsupportedError);
      final keys = _recursiveKeys(first.data);
      expect(keys, isNot(contains('midi_notes')));
      expect(keys, isNot(contains('parameters')));
      expect(keys, isNot(contains('automation_points')));
      expect(keys, isNot(contains('pending_plan')));
      expect(serialized, isNot(contains('/tmp/')));
      expect(serialized, isNot(contains('/library/')));
      expect(serialized, isNot(contains('centroid_hz')));
      expect(keys, isNot(contains('command_schema')));
    });

    test('reports row limits instead of hiding identities', () async {
      final snapshot = _build(await _fixture());
      expect(
        () => const AiV3CompactCoreBuilder(maxRows: 1).build(
          snapshot: snapshot,
          conversation: const <Map<String, String>>[],
        ),
        throwsA(isA<AiV3CompactCoreException>().having(
          (error) => error.code,
          'code',
          'compact_core_row_limit',
        )),
      );
    });
  });
}

Set<String> _recursiveKeys(Object? value) {
  final keys = <String>{};
  void visit(Object? item) {
    if (item is Map) {
      for (final entry in item.entries) {
        keys.add(entry.key.toString());
        visit(entry.value);
      }
    } else if (item is Iterable) {
      for (final child in item) {
        visit(child);
      }
    }
  }

  visit(value);
  return keys;
}

class _Fixture {
  _Fixture({
    required this.project,
    required this.tracks,
    required this.validation,
    required this.client,
  });

  final ProjectState project;
  final List<AudioTrack> tracks;
  final Map<String, dynamic> validation;
  Map<String, dynamic> client;
}
