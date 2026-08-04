import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mixroom/ai/v3/ai_v3_adaptive_midi_planner.dart';
import 'package:mixroom/ai/v3/ai_v3_compact_core.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_domain_registry.dart';
import 'package:mixroom/ai/v3/ai_v3_planner_request.dart';
import 'package:mixroom/ai/v3/ai_v3_planning_snapshot.dart';
import 'package:mixroom/ai/v3/ai_v3_retrieval.dart';
import 'package:mixroom/ai/v3/ai_v3_user_facing_text.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/models/project_state.dart';

Future<({PlanningSnapshotV3 snapshot, CompactCoreV3 compact})> _fixture({
  int noteCount = 3,
  List<EffectState> effects = const <EffectState>[],
  List<String> allowedEffects = const <String>[],
  List<String> allowedInstrumentIds = const <String>['piano', 'bass'],
  List<Map<String, dynamic>> libraryAssets = const <Map<String, dynamic>>[],
  List<AutomationPoint> volumeAutomation = const <AutomationPoint>[],
  bool hasAudio = false,
  double approxRms = 0.1,
  Map<String, double> audioStats = const <String, double>{},
  RowInterpretationState interpretation = RowInterpretationState.empty,
  bool grouped = false,
  bool includeAudioClip = false,
  bool includeSecondAudioClip = false,
}) async {
  final notes = List<MidiNote>.generate(
    noteCount,
    (index) => MidiNote(
      id: 'note-$index',
      pitch: 60 + (index % 12),
      startBeat: index * 0.5,
      lengthBeats: 0.5,
      velocity: 0.7,
    ),
  );
  final track = await AudioTrack.create(
    file: File('/tmp/Keys.mid.wav'),
    originalFile: File('/tmp/Keys.mid.wav'),
    audioDuration: const Duration(seconds: 4),
    trimEnd: const Duration(seconds: 4),
    offset: 1,
    rowIndex: 0,
    rowId: 20,
    engineClipId: 200,
    clipId: 'clip-midi',
    label: 'Keys',
    clipKind: ClipKind.midi,
    instrumentId: 'piano',
    instrumentName: 'Piano',
    midiNotes: notes,
  );
  final row = RowState(
    rowIndex: 0,
    rowId: 20,
    rowName: 'Keys',
    laneKind: 'instrument',
    instrumentId: 'piano',
    instrumentName: 'Piano',
    groupId: grouped ? 'group-keys' : '',
    clips: <ClipState>[
      ClipState(startMs: 1000, endMs: 5000, fileName: 'Keys.mid.wav'),
    ],
    approxRms: approxRms,
    approxCrest: 1.8,
    roleProbs: const <String, double>{'synth': 0.8},
    roleConsistency: 1,
    clipTopRoles: const <String>['synth'],
    audioStats: audioStats,
    interpretation: interpretation,
    gain0to3: 1.5,
    pan0To1: 0.5,
    effects: effects,
    volumeAutomation: volumeAutomation,
    hasAudio: hasAudio,
  );
  final tracks = <AudioTrack>[track];
  final rows = <RowState>[row];
  if (includeAudioClip) {
    tracks.add(await AudioTrack.create(
      file: File('/tmp/Vocal.wav'),
      originalFile: File('/tmp/Vocal.wav'),
      audioDuration: const Duration(seconds: 6),
      trimEnd: const Duration(seconds: 6),
      offset: 2,
      rowIndex: 1,
      rowId: 30,
      engineClipId: 300,
      clipId: 'clip-audio',
      label: 'Vocal',
      clipKind: ClipKind.audio,
      pitchSemitones: 2,
    ));
    if (includeSecondAudioClip) {
      tracks.add(await AudioTrack.create(
        file: File('/tmp/Vocal Take 2.wav'),
        originalFile: File('/tmp/Vocal Take 2.wav'),
        audioDuration: const Duration(seconds: 4),
        trimEnd: const Duration(seconds: 4),
        offset: 8,
        rowIndex: 1,
        rowId: 30,
        engineClipId: 301,
        clipId: 'clip-audio-2',
        label: 'Vocal Take 2',
        clipKind: ClipKind.audio,
      ));
    }
    rows.add(RowState(
      rowIndex: 1,
      rowId: 30,
      rowName: 'Vocal',
      laneKind: 'audio',
      clips: <ClipState>[
        ClipState(startMs: 2000, endMs: 8000, fileName: 'Vocal.wav'),
        if (includeSecondAudioClip)
          ClipState(
            startMs: 8000,
            endMs: 12000,
            fileName: 'Vocal Take 2.wav',
          ),
      ],
      approxRms: 0.1,
      approxCrest: 1.5,
      roleProbs: const <String, double>{'vocal': 0.8},
      roleConsistency: 1,
      clipTopRoles: const <String>['vocal'],
      audioStats: const <String, double>{},
      interpretation: RowInterpretationState.empty,
      gain0to3: 1.5,
      pan0To1: 0.5,
      effects: const <EffectState>[],
      volumeAutomation: const <AutomationPoint>[],
      hasAudio: true,
    ));
  }
  final project = ProjectState(
    bpm: 120,
    projectKey: 'C minor',
    estimatedKey: 'C minor',
    estimatedKeyConfidence: 0.9,
    masterGain0to3: 1.5,
    masterPan0to1: 0.5,
    maxRows: 32,
    rows: rows,
    trackGroups: grouped
        ? const <TrackGroup>[
            TrackGroup(
              id: 'group-keys',
              name: 'Keys Group',
              rowIds: <int>[20],
            ),
          ]
        : const <TrackGroup>[],
    masterEffects: const <EffectState>[],
    overlapMatrix: includeAudioClip
        ? const <List<int>>[
            <int>[0, 0],
            <int>[0, 0],
          ]
        : const <List<int>>[
            <int>[0],
          ],
    overlapRatioMatrix: includeAudioClip
        ? const <List<double>>[
            <double>[0, 0],
            <double>[0, 0],
          ]
        : const <List<double>>[
            <double>[0],
          ],
  );
  final snapshot = AiV3PlanningSnapshotBuilder(
    idFactory: () => 'snapshot-1',
    clock: () => DateTime.utc(2026, 7, 20),
  ).build(
    project: project,
    audioTracks: tracks,
    validationState: <String, dynamic>{
      'client_state_digest': 'digest-1',
      'project': <String, dynamic>{'tempo_bpm': 120},
      'rows': <Map<String, dynamic>>[
        <String, dynamic>{
          'row_id': 20,
          'row_index': 0,
          'automation_targets': <Map<String, dynamic>>[
            <String, dynamic>{
              'target_id': 'volume',
              'label': 'Volume',
              'unit': 'normalized',
              'min': 0.0,
              'max': 1.0,
              'current_normalized': 1.0,
              'is_orphan': false,
              'ui_visible': true,
            },
            <String, dynamic>{
              'target_id': 'mix:pan',
              'label': 'Track Pan',
              'unit': '',
              'min': 0.0,
              'max': 1.0,
              'current_normalized': 0.5,
              'is_orphan': false,
              'ui_visible': true,
            },
          ],
        },
        if (includeAudioClip)
          <String, dynamic>{
            'row_id': 30,
            'row_index': 1,
            'automation_targets': const <Object>[],
          },
      ],
      'clips': <Map<String, dynamic>>[
        <String, dynamic>{'clip_id': 'clip-midi'},
        if (includeAudioClip) <String, dynamic>{'clip_id': 'clip-audio'},
        if (includeSecondAudioClip)
          <String, dynamic>{'clip_id': 'clip-audio-2'},
      ],
      'groups': const <Object>[],
      'master': <String, dynamic>{'automation_targets': const <Object>[]},
      'automation_clips': const <Object>[],
      'selection': <String, dynamic>{
        'selected_row_index': 0,
        'selected_clip_indices': <int>[0],
        'primary_selected_clip_index': 0,
      },
    },
    clientContext: <String, dynamic>{
      'ai_v3_row_state': <Map<String, dynamic>>[
        <String, dynamic>{'row_id': 20, 'muted': false, 'soloed': false},
        if (includeAudioClip)
          <String, dynamic>{'row_id': 30, 'muted': false, 'soloed': false},
      ],
      'ai_v3_row_automation_points': <String, dynamic>{
        '20': <String, dynamic>{
          'volume': <Map<String, dynamic>>[
            <String, dynamic>{'time_ms': 0.0, 'value': 0.0},
            <String, dynamic>{'time_ms': 1000.0, 'value': 0.5},
            <String, dynamic>{'time_ms': 2000.0, 'value': 1.0},
          ],
          'mix:pan': <Map<String, dynamic>>[
            <String, dynamic>{'time_ms': 0.0, 'value': 0.25},
            <String, dynamic>{'time_ms': 2000.0, 'value': 0.75},
          ],
        },
      },
      'ai_v3_playhead_ms': 0,
      'ai_v3_transport': <String, dynamic>{
        'playing': false,
        'recording': false,
        'metronome_enabled': false,
        'loop_enabled': false,
        'loop_start_ms': 0,
        'loop_end_ms': 0,
      },
      'ai_v3_tempo_stretch_enabled': false,
      'ai_v3_clip_timeline_lengths_ms': <String, double>{
        for (final clip in tracks)
          clip.clipId:
              (clip.trimEnd - clip.trimStart).inMilliseconds.toDouble(),
      },
      'max_rows': 32,
      'current_rows': rows.length,
      'row_creation_policy': 'Rows may be created up to the app row limit.',
      'allowed_instrument_ids': allowedInstrumentIds,
      'allowed_builtin_effects': allowedEffects,
      'ai_v3_library_assets': libraryAssets,
      'plugin_access': 'none',
      'ai_capabilities': <String>['daw.midi'],
      'ai_v3_prototype_enabled': true,
    },
    beatsPerBar: 4,
    beatUnit: 4,
    projectId: 'project-1',
  );
  final compact = const AiV3CompactCoreBuilder().build(
    snapshot: snapshot,
    conversation: const <Map<String, String>>[],
  );
  return (snapshot: snapshot, compact: compact);
}

Map<String, dynamic> _query({
  List<Object> targets = const <Object>['clip-midi'],
  List<String> fields = const <String>['clip_notes'],
  Object? range,
  int limit = 512,
}) =>
    <String, dynamic>{
      'schema_version': aiV3ContextRequestVersion,
      'requests': <Map<String, dynamic>>[
        <String, dynamic>{
          'request_id': 'midi-1',
          'domain': 'midi',
          'target_ids': targets,
          'time_range': range,
          'query_terms': const <Object>[],
          'requested_fields': fields,
          'limit': limit,
        },
      ],
    };

Map<String, dynamic> _effectsQuery({
  List<int> targets = const <int>[20],
  List<String> fields = const <String>['instances'],
  int limit = 64,
}) =>
    <String, dynamic>{
      'schema_version': aiV3ContextRequestVersion,
      'requests': <Map<String, dynamic>>[
        <String, dynamic>{
          'request_id': 'effects-1',
          'domain': 'effects',
          'target_ids': targets,
          'time_range': null,
          'query_terms': const <Object>[],
          'requested_fields': fields,
          'limit': limit,
        },
      ],
    };

Map<String, dynamic> _clipAdvancedQuery({
  List<Object> targets = const <Object>['clip-audio'],
  List<String> fields = const <String>[
    'clip_details',
    'transform_capabilities',
  ],
  int limit = 64,
}) =>
    <String, dynamic>{
      'schema_version': aiV3ContextRequestVersion,
      'requests': <Map<String, dynamic>>[
        <String, dynamic>{
          'request_id': 'clip-advanced-1',
          'domain': 'clip_advanced',
          'target_ids': targets,
          'time_range': null,
          'query_terms': const <Object>[],
          'requested_fields': fields,
          'limit': limit,
        },
      ],
    };

Map<String, dynamic> _samplesQuery({
  List<String> targets = const <String>[],
  List<String> terms = const <String>['kick'],
  List<String> fields = const <String>[
    'search_results',
    'asset_metadata',
    'placement_capabilities',
  ],
  int limit = 32,
}) =>
    <String, dynamic>{
      'schema_version': aiV3ContextRequestVersion,
      'requests': <Map<String, dynamic>>[
        <String, dynamic>{
          'request_id': 'samples-1',
          'domain': 'samples',
          'target_ids': targets,
          'time_range': null,
          'query_terms': terms,
          'requested_fields': fields,
          'limit': limit,
        },
      ],
    };

Map<String, dynamic> _automationQuery({
  List<int> targets = const <int>[20],
  List<String> fields = const <String>[
    'gain_points',
    'target_capabilities',
  ],
  int limit = 512,
}) =>
    <String, dynamic>{
      'schema_version': aiV3ContextRequestVersion,
      'requests': <Map<String, dynamic>>[
        <String, dynamic>{
          'request_id': 'automation-1',
          'domain': 'automation',
          'target_ids': targets,
          'time_range': null,
          'query_terms': const <Object>[],
          'requested_fields': fields,
          'limit': limit,
        },
      ],
    };

Map<String, dynamic> _mixQuery({
  List<Object> targets = const <Object>[20],
  List<String> fields = const <String>[
    'row_analysis',
    'reference_analysis',
    'engine_capabilities',
  ],
  int limit = 32,
}) =>
    <String, dynamic>{
      'schema_version': aiV3ContextRequestVersion,
      'requests': <Map<String, dynamic>>[
        <String, dynamic>{
          'request_id': 'mix-1',
          'domain': 'mix',
          'target_ids': targets,
          'time_range': null,
          'query_terms': const <Object>[],
          'requested_fields': fields,
          'limit': limit,
        },
      ],
    };

Map<String, dynamic> _response(String name, Map<String, dynamic> arguments) =>
    <String, dynamic>{
      'id': 'response-1',
      'service_tier': 'default',
      'output': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'function_call',
          'name': name,
          'arguments': jsonEncode(arguments),
        },
      ],
      'usage': <String, dynamic>{
        'input_tokens': 100,
        'output_tokens': 20,
        'total_tokens': 120,
      },
    };

Map<String, dynamic> _respondPlan() => <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'respond',
      'user_message': 'The project is at 120 BPM.',
      'commands': const <Object>[],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _transposePlan() => <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Transpose the Keys clip down two semitones.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'transpose-keys',
          'type': 'midi.transpose',
          'arguments': <String, dynamic>{
            'clip_id': 'clip-midi',
            'semitones': -2,
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _midiEditPlan(
  String type, {
  String clipId = 'clip-midi',
}) =>
    <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Edit the Keys notes.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'edit-keys',
          'type': type,
          'arguments': switch (type) {
            'midi.replace_notes' => <String, dynamic>{
                'clip_id': clipId,
                'notes': const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'pitch': 60,
                    'start_beat': 0.0,
                    'length_beats': 1.0,
                    'velocity': 0.8,
                  },
                ],
              },
            'midi.append_notes' => <String, dynamic>{
                'clip_id': clipId,
                'notes': const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'pitch': 64,
                    'start_beat': 0.0,
                    'length_beats': 0.5,
                    'velocity': 0.7,
                  },
                ],
              },
            'midi.chop_notes' => <String, dynamic>{
                'clip_id': clipId,
                'subdivision': 16,
                'range': null,
                'velocity_decay_per_slice': 0.0,
              },
            _ => throw StateError(type),
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _createMidiPlan({
  int? rowId = 20,
  String? newRowInstrumentId,
}) =>
    <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Create a short MIDI clip.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'create-midi',
          'type': 'midi.create_clip',
          'arguments': <String, dynamic>{
            'destination': rowId != null
                ? <String, dynamic>{'row_id': rowId}
                : <String, dynamic>{
                    'new_row': <String, dynamic>{
                      'name': 'New MIDI',
                      'instrument_id': newRowInstrumentId,
                    },
                  },
            'start_beat': 0.0,
            'length_beats': 1.0,
            'notes': const <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 60,
                'start_beat': 0.0,
                'length_beats': 1.0,
                'velocity': 0.8,
              },
            ],
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _createThreePartMidiPlan() => <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Create a four-bar drum, bass, and piano loop.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'tempo',
          'type': 'project.set_tempo',
          'arguments': <String, dynamic>{
            'bpm': 100.0,
            'time_stretch_audio': false,
            'preserve_pitch': true,
          },
        },
        for (final part in const <(String, String, int)>[
          ('House Drums', 'house-drums', 36),
          ('Reese Bass', 'reese-bass', 36),
          ('Upright Piano', 'upright-piano', 60),
        ])
          <String, dynamic>{
            'command_id': 'create-${part.$2}',
            'type': 'midi.create_clip',
            'arguments': <String, dynamic>{
              'destination': <String, dynamic>{
                'new_row': <String, dynamic>{
                  'name': part.$1,
                  'instrument_id': part.$2,
                },
              },
              'start_beat': 0.0,
              'length_beats': 16.0,
              'notes': <Map<String, dynamic>>[
                <String, dynamic>{
                  'pitch': part.$3,
                  'start_beat': 0.0,
                  'length_beats': 1.0,
                  'velocity': 0.8,
                },
              ],
            },
          },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _ensureEffectPlan({
  int rowId = 20,
  String effectId = 'Reverb',
  String parameterId = 'Mix',
}) =>
    <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Configure Reverb on Keys.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'configure-reverb',
          'type': 'effect.ensure_configured',
          'arguments': <String, dynamic>{
            'row_id': rowId,
            'effect_id': effectId,
            'parameters': <Map<String, dynamic>>[
              <String, dynamic>{
                'parameter_id': parameterId,
                'value': 0.5,
              },
            ],
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _pitchPlan({String clipId = 'clip-audio'}) =>
    <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Lower the Vocal clip by two semitones.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'pitch-vocal',
          'type': 'clip.adjust_pitch_semitones',
          'arguments': <String, dynamic>{
            'clip_id': clipId,
            'delta_semitones': -2,
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _gluePlan({
  List<String> clipIds = const <String>['clip-audio', 'clip-audio-2'],
}) =>
    <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Glue the two Vocal clips.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'glue-vocals',
          'type': 'clip.glue',
          'arguments': <String, dynamic>{
            'clip_ids': clipIds,
            'label': 'Vocal Comp',
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _stemPlan({String clipId = 'clip-audio'}) =>
    <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Separate the Vocal clip into vocals and instrumental.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'separate-vocal',
          'type': 'clip.separate_stems',
          'arguments': <String, dynamic>{'clip_id': clipId},
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _stemPitchRefPlan() => <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Separated the stems and adjusted the generated clip.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'separate-vocal',
          'type': 'clip.separate_stems',
          'arguments': <String, dynamic>{'clip_id': 'clip-audio'},
        },
        <String, dynamic>{
          'command_id': 'pitch-generated',
          'type': 'clip.adjust_pitch_semitones',
          'arguments': <String, dynamic>{
            'clip_ref': <String, dynamic>{
              'command_id': 'separate-vocal',
              'output': 'instrumental_clip',
            },
            'delta_semitones': -1,
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _generatedMidiTransposeRefPlan() => <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Created and transposed the generated MIDI clip.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'create-row',
          'type': 'row.create',
          'arguments': <String, dynamic>{
            'name': 'Chords',
            'lane': <String, dynamic>{
              'kind': 'midi',
              'instrument_id': 'mixroom.basic_synth',
            },
            'position': <String, dynamic>{'kind': 'end'},
          },
        },
        <String, dynamic>{
          'command_id': 'create-clip',
          'type': 'midi.create_clip',
          'arguments': <String, dynamic>{
            'destination': <String, dynamic>{
              'row_ref': <String, dynamic>{
                'command_id': 'create-row',
                'output': 'row',
              },
            },
            'start_beat': 0.0,
            'length_beats': 1.0,
            'notes': const <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 60,
                'start_beat': 0.0,
                'length_beats': 1.0,
                'velocity': 0.8,
              },
            ],
          },
        },
        <String, dynamic>{
          'command_id': 'transpose-clip',
          'type': 'midi.transpose',
          'arguments': <String, dynamic>{
            'clip_ref': <String, dynamic>{
              'command_id': 'create-clip',
              'output': 'midi_clip',
            },
            'semitones': 2,
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _audioToMidiPlan({
  String clipId = 'clip-audio',
  String instrumentId = 'piano',
}) =>
    <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Convert the Vocal clip to piano MIDI.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'convert-vocal',
          'type': 'clip.convert_to_midi',
          'arguments': <String, dynamic>{
            'clip_id': clipId,
            'instrument_id': instrumentId,
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _bypassPlan() => <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Bypass the Reverb on Keys.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'bypass-reverb',
          'type': 'effect.set_bypassed',
          'arguments': <String, dynamic>{
            'effect_instance_id': 'fx-reverb',
            'bypassed': true,
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _midiAndEffectPlan() => <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Transpose Keys and bypass its Reverb.',
      'commands': <Map<String, dynamic>>[
        ...(_transposePlan()['commands'] as List).cast<Map<String, dynamic>>(),
        ...(_bypassPlan()['commands'] as List).cast<Map<String, dynamic>>(),
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _samplePlan() => <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Place the selected kick sample on Keys.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'place-kick',
          'type': 'sample.place',
          'arguments': <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 20},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{
                'asset_id': 'sample:kick',
                'start_beat': 0,
              },
            ],
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _sampleReplacePlan({
  String assetId = 'sample:kick',
}) =>
    <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Replace the selected audio clip.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'replace-sample',
          'type': 'sample.replace',
          'arguments': <String, dynamic>{
            'clip_id': 'clip-audio',
            'asset_id': assetId,
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _automationPlan({int rowId = 20}) => <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Add a gain fade to Keys.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'fade-keys',
          'type': 'automation.gain_fade',
          'arguments': <String, dynamic>{
            'row_id': rowId,
            'start_beat': 0,
            'end_beat': 4,
            'from_gain_db': -120,
            'to_level': 'current',
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _automationPointsPlan({
  int rowId = 20,
  String targetId = 'mix:pan',
}) =>
    <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Set a pan curve on Keys.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'curve-keys',
          'type': 'automation.set_points',
          'arguments': <String, dynamic>{
            'row_id': rowId,
            'automation_target_id': targetId,
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'beat': 0, 'value_normalized': 0.2},
              <String, dynamic>{'beat': 4, 'value_normalized': 0.8},
            ],
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _mixPlan({int? referenceRowId}) => <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Balance the project mix.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'mix-project',
          'type': 'mix.apply_goal',
          'arguments': <String, dynamic>{
            'target': const <String, dynamic>{'scope': 'all_rows'},
            'intents': const <Map<String, dynamic>>[
              <String, dynamic>{
                'kind': 'balance',
                'direction': null,
                'descriptor': null,
              },
            ],
            'intensity': 0.5,
            'execution_profile': 'producer_safe',
            'audibility': 'noticeable',
            'style_tags': const <String>[],
            'reset_fx': false,
            'reference': referenceRowId == null
                ? null
                : <String, dynamic>{
                    'row_id': referenceRowId,
                    'mode': 'full_mix',
                    'closeness': 'balanced',
                  },
          },
        },
      ],
      'question_options': const <Object>[],
    };

Map<String, dynamic> _zeroMovePlan() => <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Transposing the Keys clip.',
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'placeholder',
          'type': 'clip.move_by_beats',
          'arguments': <String, dynamic>{
            'clip_id': 'clip-midi',
            'delta_beats': 0,
          },
        },
      ],
      'question_options': const <Object>[],
    };

Set<String> _submittedCommandTypes(Map<String, dynamic> requestBody) {
  final tools = (requestBody['tools'] as List).cast<Map>();
  final submit = tools.singleWhere(
    (tool) => tool['name'] == 'submit_plan_v3',
  );
  final parameters = submit['parameters'] as Map;
  final properties = parameters['properties'] as Map;
  final commands = properties['commands'] as Map;
  final items = commands['items'] as Map;
  final variants = (items['anyOf'] as List).cast<Map>();
  return <String>{
    for (final variant in variants)
      ((((variant['properties'] as Map)['type'] as Map)['enum'] as List)
          .single
          .toString()),
  };
}

void main() {
  test('strict adaptive retrieval contract exposes only enabled domains', () {
    final tool = aiV3GetContextDomainsTool();
    final encoded = jsonEncode(tool);
    expect(tool['name'], 'get_context_domains');
    expect(
      tool['description'],
      contains('immutable facts from enabled domains'),
    );
    expect(encoded, contains('clip_notes'));
    expect(encoded, contains('clip_instruments'));
    expect(encoded, contains('edit_capabilities'));
    expect(encoded, contains('effects'));
    expect(encoded, contains('parameter_definitions'));
    expect(encoded, contains('samples'));
    expect(encoded, contains('search_results'));
    expect(encoded, contains('placement_capabilities'));
    expect(encoded, contains('automation'));
    expect(encoded, contains('gain_points'));
    expect(encoded, contains('mix'));
    expect(encoded, contains('row_analysis'));
    expect(encoded, contains('reference_analysis'));
    expect(encoded, contains('engine_capabilities'));
    expect(encoded, isNot(contains('replacement_capabilities')));
    expect(
      encoded,
      contains(
        'Maximum number of MIDI notes returned across all matched clips.',
      ),
    );
    expect(AiV3ContextRequest.fromJson(_query()).requests, hasLength(1));
    expect(
      aiV3AdaptiveFirstTurnInstructions,
      allOf(
        contains('Preserve the complete original request'),
        contains('every required domain in the single batch'),
        contains('capability directory'),
        contains('ambiguity that materially changes the result'),
      ),
    );
    expect(
      aiV3AdaptiveFirstTurnInstructions,
      isNot(contains('merely because its command is absent')),
    );
    expect(
      aiV3AdaptiveFirstTurnInstructions,
      allOf(
        contains('general musical'),
        contains('knowledge for interpretation'),
      ),
    );
    expect(
      aiV3AdaptiveFirstTurnInstructions,
      contains('never invent project resources or state'),
    );
    expect(
      aiV3AdaptiveContinuationInstructions,
      allOf(
        contains('ambiguity that materially'),
        contains('changes the result'),
      ),
    );
    expect(
      aiV3AdaptiveContinuationInstructions,
      allOf(
        contains('general musical'),
        contains('knowledge for interpretation'),
      ),
    );
    final requestsSchema =
        ((tool['parameters'] as Map)['properties'] as Map)['requests'] as Map;
    final variants = (requestsSchema['items'] as Map)['anyOf'] as List;
    final schemaDomains = variants
        .map((variant) => ((((variant as Map)['properties'] as Map)['domain']
                as Map)['enum'] as List)
            .single)
        .toSet();
    expect(
      schemaDomains,
      aiV3RetrievalEnabledDomains.map((definition) => definition.id).toSet(),
    );
    final midiVariant = variants.cast<Map>().singleWhere((variant) =>
        (((variant['properties'] as Map)['domain'] as Map)['enum'] as List)
            .contains('midi'));
    final midiProperties = (midiVariant['properties'] as Map);
    final effectsVariant = variants.cast<Map>().singleWhere((variant) =>
        (((variant['properties'] as Map)['domain'] as Map)['enum'] as List)
            .contains('effects'));
    final effectsProperties = (effectsVariant['properties'] as Map);
    expect(
      ((midiProperties['target_ids'] as Map)['description'] as String),
      allOf(
        contains('every plausible match'),
        contains('creating a new instrument row'),
        contains('exact instrument ID is absent from compact context'),
        contains('edit_capabilities'),
        contains('bounded allowed instrument IDs'),
      ),
    );
    expect(
      ((effectsProperties['limit'] as Map)['description'] as String),
      contains('top-level effect instance and catalog records'),
    );
  });

  test('adaptive prompts are capability-independent', () async {
    final capabilityTerms = <String>{
      for (final definition in aiV3DomainDefinitions) ...<String>{
        definition.id,
        ...definition.capabilities,
        ...definition.requestedFields,
        ...definition.commandTypes,
      },
    };
    for (final term in capabilityTerms) {
      expect(aiV3AdaptiveFirstTurnInstructions, isNot(contains(term)));
      expect(aiV3AdaptiveContinuationInstructions, isNot(contains(term)));
    }

    final fixture = await _fixture();
    final withoutEffects = const AiV3CompactCoreBuilder(
      domainDefinitions: <AiV3DomainDefinition>[
        AiV3DomainDefinition(
          id: 'midi',
          purpose: 'MIDI facts.',
          retrievalEnabled: true,
          capabilities: <String>['transpose_notes'],
          requestedFields: <String>['edit_capabilities'],
          commandTypes: <String>['midi.transpose'],
        ),
      ],
    ).build(snapshot: fixture.snapshot, conversation: const []);
    expect(
      (withoutEffects.data['capability_domains'] as List),
      hasLength(1),
    );
    expect(
      buildAiV3AdaptiveFirstRequestBody(
        compactCore: withoutEffects.data,
        originalRequest: 'Edit the project.',
        model: 'gpt-5.4-mini',
        reasoningEffort: 'low',
      )['instructions'],
      aiV3AdaptiveFirstTurnInstructions.trim(),
    );
  });

  test('all V3 planner stages share exact MIDI timing semantics once', () {
    int occurrences(String source) =>
        source.split(aiV3MidiTimingInstructions).length - 1;

    expect(occurrences(aiV3PlannerInstructions), 1);
    expect(occurrences(aiV3AdaptiveFirstTurnInstructions), 1);
    expect(occurrences(aiV3AdaptiveContinuationInstructions), 1);
    for (final instructions in <String>[
      aiV3PlannerInstructions,
      aiV3AdaptiveFirstTurnInstructions,
      aiV3AdaptiveContinuationInstructions,
    ]) {
      expect(instructions, contains(aiV3CustomerLanguageInstructions));
      expect(instructions, contains('general music creator'));
      expect(instructions, contains('clear, easy-to-understand'));
      expect(instructions, contains('deeper technical detail'));
      expect(instructions, contains('request or conversation clearly shows'));
      expect(instructions, contains('user-visible terms'));
      expect(
        instructions,
        contains('non-user-visible application context'),
      );
      expect(instructions, contains('never reveal or transform them'));
      expect(instructions, contains('one or two brief, past-tense sentences'));
      expect(
        instructions,
        contains('Never copy the request into a successful plan summary'),
      );
      expect(instructions, contains('completed musical result'));
      expect(instructions, contains('under 500 characters'));
      expect(instructions, contains('Always finish naturally'));
    }

    final oneShot = buildAiV3PlannerRequestBody(
      contextData: const <String, dynamic>{},
      originalRequest: 'Create MIDI notes.',
      model: 'gpt-5.4-mini',
      reasoningEffort: 'low',
    );
    final adaptiveFirst = buildAiV3AdaptiveFirstRequestBody(
      compactCore: const <String, dynamic>{},
      originalRequest: 'Create MIDI notes.',
      model: 'gpt-5.4-mini',
      reasoningEffort: 'low',
    );
    final adaptiveContinuation = buildAiV3AdaptiveContinuationRequestBody(
      compactCore: const <String, dynamic>{},
      originalRequest: 'Create MIDI notes.',
      retrievalRequest: const <String, dynamic>{},
      retrievalResult: const <String, dynamic>{},
      model: 'gpt-5.4-mini',
      reasoningEffort: 'low',
    );

    for (final body in <Map<String, dynamic>>[
      oneShot,
      adaptiveFirst,
      adaptiveContinuation,
    ]) {
      expect(occurrences(body['instructions'] as String), 1);
    }
  });

  test('registry owns retrieval capability and command mappings', () {
    for (final definition in aiV3DomainDefinitions) {
      if (definition.retrievalEnabled) {
        expect(definition.capabilities, isNotEmpty, reason: definition.id);
        expect(definition.requestedFields, isNotEmpty, reason: definition.id);
        expect(definition.commandTypes, isNotEmpty, reason: definition.id);
        expect(
          aiV3CommandTypesForDomains(<String>[definition.id]),
          containsAll(definition.commandTypes),
        );
      } else {
        expect(definition.requestedFields, isEmpty, reason: definition.id);
        expect(
          aiV3CommandTypes,
          containsAll(definition.commandTypes),
          reason: definition.id,
        );
      }
    }
    final midi = aiV3DomainDefinitions.singleWhere(
      (definition) => definition.id == 'midi',
    );
    expect(
      midi.capabilities,
      containsAll(<String>['replace_notes', 'append_notes', 'chop_notes']),
    );
    expect(
      midi.commandTypes,
      containsAll(<String>[
        'midi.replace_notes',
        'midi.append_notes',
        'midi.chop_notes',
      ]),
    );
    final externalAudio = aiV3DomainDefinition('external_audio');
    expect(externalAudio.retrievalEnabled, isFalse);
    expect(
      externalAudio.capabilities,
      <String>['apply_phone_mic_cleanup'],
    );
    expect(
      externalAudio.commandTypes,
      <String>['row.apply_phone_mic_cleanup'],
    );
  });

  test('compact directory exposes fact routing without command duplication',
      () async {
    final fixture = await _fixture();
    final core = const AiV3CompactCoreBuilder().build(
      snapshot: fixture.snapshot,
      conversation: const [],
    );
    final domains = (core.data['capability_domains'] as List).cast<Map>();

    for (final definition in aiV3DomainDefinitions) {
      final domain = domains.singleWhere(
        (item) => item['domain'] == definition.id,
      );
      expect(domain['retrieval_enabled'], definition.retrievalEnabled);
      expect(domain.containsKey('command_types'), isFalse);
      expect(domain.containsKey('capabilities'), isFalse);
    }

    final encoded = jsonEncode(core.data['capability_domains']);
    expect(encoded, isNot(contains('clip.set_pitch_semitones')));
    expect(encoded, isNot(contains('mix.apply_goal')));
    expect(encoded, isNot(contains('pitch_semitones":')));
    expect(encoded, isNot(contains('"arguments"')));
  });

  test('domain command semantics remain schema-local', () {
    final defaultTool = aiV3SubmitPlanTool(
      commandTypes: const <String>{'midi.create_clip'},
    );
    final adaptiveTool = aiV3SubmitPlanTool(
      commandTypes: const <String>{'midi.create_clip'},
      includeCommandSemantics: true,
    );
    expect(
        jsonEncode(defaultTool), isNot(contains('relative to the new clip')));
    expect(jsonEncode(adaptiveTool), contains('relative to the new clip'));
    expect(
      aiV3AdaptiveContinuationInstructions,
      isNot(contains('start_beat')),
    );
  });

  test('retrieval contract rejects invalid scope without repair', () {
    expect(
      () => AiV3ContextRequest.fromJson(
        _query(targets: const <Object>[], fields: const <String>['clip_notes']),
      ),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_clip_target_required',
      )),
    );
    final duplicate = _query();
    ((duplicate['requests'] as List).single as Map)['target_ids'] = <String>[
      'clip-midi',
      'clip-midi'
    ];
    expect(
      () => AiV3ContextRequest.fromJson(duplicate),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_target_duplicate',
      )),
    );
    expect(
      () => AiV3ContextRequest.fromJson(
        _query(fields: const <String>['transcription_status']),
      ),
      throwsA(isA<AiV3RetrievalException>()),
    );
    final creationCapabilities = AiV3ContextRequest.fromJson(
      _query(
        targets: const <Object>[],
        fields: const <String>['edit_capabilities', 'clip_instruments'],
      ),
    );
    expect(creationCapabilities.requests.single.targetIds, isEmpty);
  });

  test('advanced clip contract enforces exact audio targets and fields', () {
    final request = AiV3ContextRequest.fromJson(_clipAdvancedQuery());
    expect(request.requests.single, isA<AiV3ClipAdvancedContextQuery>());
    expect(request.requests.single.targetIds, <Object>['clip-audio']);

    expect(
      () => AiV3ContextRequest.fromJson(_clipAdvancedQuery(
        targets: const <Object>[],
        fields: const <String>['clip_details'],
      )),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_clip_target_required',
      )),
    );
    expect(
      AiV3ContextRequest.fromJson(_clipAdvancedQuery(
        targets: const <Object>[],
        fields: const <String>['transform_capabilities'],
      )).requests.single,
      isA<AiV3ClipAdvancedContextQuery>(),
    );
    expect(
      () => AiV3ContextRequest.fromJson(
        _clipAdvancedQuery(targets: const <Object>['x', 'x']),
      ),
      throwsA(isA<AiV3RetrievalException>()),
    );
  });

  test('advanced clip retriever returns immutable transform facts', () async {
    final fixture = await _fixture(includeAudioClip: true);
    final request = AiV3ContextRequest.fromJson(
      _clipAdvancedQuery(targets: const <Object>[30]),
    );
    final result = const AiV3ContextRetriever()
        .retrieve(snapshot: fixture.snapshot, request: request)
        .toJson();
    final item = (result['results'] as List).single as Map;
    final clip = (item['audio_clips'] as List).single as Map;
    expect(item['domain'], 'clip_advanced');
    expect(item['matched_row_ids'], <int>[30]);
    expect(clip['clip_id'], 'clip-audio');
    expect(clip['row_id'], 30);
    expect(clip['pitch_semitones'], 2.0);
    expect(clip['start_beat'], 4.0);
    expect(clip['length_beats'], 12.0);
    expect(clip['timeline_length_beats'], 12.0);
    expect(clip['source_tempo_bpm'], 0.0);
    expect(clip['stretch_to_project_tempo'], isFalse);
    expect(clip['tempo_stretch_preserve_pitch'], isFalse);
    expect(clip['tempo_warp_mode'], 'complex');
    final capabilities = item['transform_capabilities'] as Map;
    expect(
      capabilities['minimum_pitch_semitones'],
      -12.0,
    );
    expect(capabilities['can_set_timeline_length'], isTrue);
    expect(capabilities['can_scale_timeline_length'], isTrue);
    expect(capabilities['minimum_playback_ratio'], 0.05);
    expect(capabilities['maximum_playback_ratio'], 20.0);
    expect(capabilities['can_set_source_tempo'], isTrue);
    expect(capabilities['can_detect_source_tempo'], isTrue);
    expect(capabilities['can_align_tempo_to_project'], isTrue);
    expect(capabilities['can_set_project_tempo_from_clip'], isTrue);
    expect(capabilities['can_trim_detected_edge_silence'], isTrue);
    expect(capabilities['can_align_detected_first_sound'], isTrue);
    expect(
      capabilities['tempo_follow_modes'],
      <String>['off', 'repitch', 'preserve_pitch'],
    );
  });

  test('advanced clip retriever rejects MIDI and unknown targets', () async {
    final fixture = await _fixture(includeAudioClip: true);
    for (final target in const <Object>['clip-midi', 20, 'missing']) {
      final request = AiV3ContextRequest.fromJson(
        _clipAdvancedQuery(targets: <Object>[target]),
      );
      expect(
        () => const AiV3ContextRetriever()
            .retrieve(snapshot: fixture.snapshot, request: request),
        throwsA(isA<AiV3RetrievalException>()),
      );
    }
    final capabilityOnly = AiV3ContextRequest.fromJson(
      _clipAdvancedQuery(
        targets: const <Object>[20],
        fields: const <String>['transform_capabilities'],
      ),
    );
    expect(
      () => const AiV3ContextRetriever()
          .retrieve(snapshot: fixture.snapshot, request: capabilityOnly),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_target_not_audio',
      )),
    );
  });

  test('retriever returns exact immutable notes, instruments, and capabilities',
      () async {
    final fixture = await _fixture();
    final request = AiV3ContextRequest.fromJson(_query(
      targets: const <Object>[20],
      fields: const <String>[
        'clip_notes',
        'clip_instruments',
        'edit_capabilities',
      ],
      range: <String, dynamic>{'start_beat': 0.4, 'end_beat': 1.1},
    ));
    final result = const AiV3MidiContextRetriever().retrieve(
      snapshot: fixture.snapshot,
      request: request,
    );
    final json = result.toJson();
    final item = (json['results'] as List).single as Map;
    final clip = (item['midi_clips'] as List).single as Map;
    final notes = clip['notes'] as List;
    expect(result.snapshotId, 'snapshot-1');
    expect(item['matched_row_ids'], <int>[20]);
    expect(clip['clip_id'], 'clip-midi');
    expect(clip['instrument_id'], 'piano');
    expect(notes.map((note) => (note as Map)['note_id']),
        <String>['note-0', 'note-1', 'note-2']);
    expect(item['instrument_ids'], <String>['bass', 'piano']);
    final capabilities = item['edit_capabilities'] as Map;
    expect(capabilities['can_create'], isTrue);
    expect(capabilities['can_replace'], isTrue);
    expect(capabilities['can_append'], isTrue);
    expect(capabilities['can_chop'], isTrue);
    expect(capabilities['max_generated_notes'], 256);
  });

  test('edit-capability retrieval retains an explicit row without MIDI clips',
      () async {
    final fixture = await _fixture(includeAudioClip: true);
    final request = AiV3ContextRequest.fromJson(_query(
      targets: const <Object>[30],
      fields: const <String>['edit_capabilities'],
    ));
    final result = const AiV3MidiContextRetriever().retrieve(
      snapshot: fixture.snapshot,
      request: request,
    );
    final item = (result.toJson()['results'] as List).single as Map;
    expect(item['matched_row_ids'], <int>[30]);
    expect(item['midi_clips'], isEmpty);
  });

  test('retriever rejects unknown and non-MIDI targets', () async {
    final fixture = await _fixture();
    final request = AiV3ContextRequest.fromJson(
      _query(targets: const <Object>['missing']),
    );
    expect(
      () => const AiV3MidiContextRetriever().retrieve(
        snapshot: fixture.snapshot,
        request: request,
      ),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_target_unknown',
      )),
    );
  });

  test('retriever enforces one combined 512-note batch limit', () async {
    final fixture = await _fixture(noteCount: 520);
    final requestJson = _query(limit: 300);
    (requestJson['requests'] as List).add(<String, dynamic>{
      'request_id': 'midi-2',
      'domain': 'midi',
      'target_ids': const <Object>['clip-midi'],
      'time_range': null,
      'query_terms': const <Object>[],
      'requested_fields': const <String>['clip_notes'],
      'limit': 300,
    });
    final request = AiV3ContextRequest.fromJson(requestJson);
    final result = const AiV3MidiContextRetriever().retrieve(
      snapshot: fixture.snapshot,
      request: request,
    );
    final items = result.toJson()['results'] as List;
    final first = (items.first as Map)['counts'] as Map;
    final second = (items.last as Map)['counts'] as Map;
    expect(first['notes_total'], 520);
    expect(first['notes_returned'], 300);
    expect(second['notes_total'], 520);
    expect(second['notes_returned'], 212);
    expect(second['has_more'], isTrue);
  });

  test('effects contract validates row scope and exact fields', () {
    final request = AiV3ContextRequest.fromJson(_effectsQuery(
      fields: const <String>[
        'instances',
        'catalog',
        'parameter_definitions',
        'target_capabilities',
      ],
    ));
    expect(request.requests.single, isA<AiV3EffectsContextQuery>());
    expect(request.requests.single.targetIds, <int>[20]);
    expect(
      jsonEncode(aiV3GetContextDomainsTool()),
      allOf(
        contains('To add or configure an effect'),
        contains('catalog or parameter_definitions'),
      ),
    );

    expect(
      () => AiV3ContextRequest.fromJson(
        _effectsQuery(
            targets: const <int>[], fields: const <String>['instances']),
      ),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_effect_row_target_required',
      )),
    );
    expect(
      AiV3ContextRequest.fromJson(_effectsQuery(
        targets: const <int>[],
        fields: const <String>['catalog', 'target_capabilities'],
      )).requests.single,
      isA<AiV3EffectsContextQuery>(),
    );
    final invalid = _effectsQuery();
    ((invalid['requests'] as List).single as Map)['target_ids'] =
        const <String>['fx-reverb'];
    expect(
      () => AiV3ContextRequest.fromJson(invalid),
      throwsA(isA<AiV3RetrievalException>()),
    );
  });

  test('effects retriever returns stable built-in facts from the snapshot',
      () async {
    final fixture = await _fixture(
      allowedEffects: const <String>['Limiter', 'Reverb'],
      effects: const <EffectState>[
        EffectState(
          effectIndex: 0,
          instanceId: 'fx-reverb',
          effectId: 'Reverb',
          name: 'Reverb',
          isBypassed: false,
          parameters: <EffectParameterState>[
            EffectParameterState(
              id: 'mix',
              name: 'Mix',
              type: 'float',
              value: 0.25,
              min: 0,
              max: 1,
            ),
            EffectParameterState(
              id: 'roomSize',
              name: 'Room Size',
              type: 'float',
              value: 30,
              min: 0,
              max: 100,
            ),
          ],
        ),
      ],
    );
    final request = AiV3ContextRequest.fromJson(_effectsQuery(
      fields: const <String>[
        'instances',
        'catalog',
        'parameter_definitions',
        'target_capabilities',
      ],
    ));
    final json = const AiV3ContextRetriever()
        .retrieve(snapshot: fixture.snapshot, request: request)
        .toJson();
    final result = (json['results'] as List).single as Map;
    final instance = (result['instances'] as List).single as Map;
    expect(result['domain'], 'effects');
    expect(result['matched_row_ids'], <int>[20]);
    expect(instance['effect_instance_id'], 'fx-reverb');
    expect(instance['row_id'], 20);
    expect(instance['effect_index'], 0);
    expect(instance['bypassed'], isFalse);
    expect(instance['parameters'], <Map<String, dynamic>>[
      <String, dynamic>{'parameter_id': 'Mix', 'value': 0.25},
      <String, dynamic>{'parameter_id': 'Room Size', 'value': 0.3},
    ]);
    expect(
      (result['catalog'] as List).map((value) => (value as Map)['effect_id']),
      <String>['Limiter', 'Reverb'],
    );
    expect((result['parameter_definitions'] as List), isNotEmpty);
    expect(
      (result['target_capabilities'] as Map)['hosted_plugins_supported'],
      isFalse,
    );
  });

  test('effects retrieval discloses deterministic record truncation', () async {
    final fixture = await _fixture(
      allowedEffects: const <String>['Limiter', 'Reverb'],
      effects: const <EffectState>[
        EffectState(
          effectIndex: 0,
          instanceId: 'fx-reverb',
          effectId: 'Reverb',
          name: 'Reverb',
          isBypassed: false,
          parameters: <EffectParameterState>[],
        ),
      ],
    );
    final request = AiV3ContextRequest.fromJson(_effectsQuery(
      fields: const <String>['instances', 'catalog'],
      limit: 1,
    ));
    final result = const AiV3ContextRetriever()
        .retrieve(snapshot: fixture.snapshot, request: request)
        .toJson();
    final counts =
        (((result['results'] as List).single as Map)['counts'] as Map);
    expect(counts['records_total'], 3);
    expect(counts['records_returned'], 1);
    expect(counts['has_more'], isTrue);
  });

  test('samples contract enforces selectors, terms, and strict bounds', () {
    final request = AiV3ContextRequest.fromJson(_samplesQuery());
    expect(request.requests.single, isA<AiV3SamplesContextQuery>());

    expect(
      () => AiV3ContextRequest.fromJson(_samplesQuery(terms: const <String>[])),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_sample_search_terms_required',
      )),
    );
    expect(
      () => AiV3ContextRequest.fromJson(_samplesQuery(
        terms: const <String>[],
        fields: const <String>['asset_metadata'],
      )),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_sample_asset_selector_required',
      )),
    );
    expect(
      AiV3ContextRequest.fromJson(_samplesQuery(
        terms: const <String>[],
        fields: const <String>['placement_capabilities'],
      )).requests.single,
      isA<AiV3SamplesContextQuery>(),
    );
    expect(
      () => AiV3ContextRequest.fromJson(
        _samplesQuery(terms: const <String>['kick', 'KICK']),
      ),
      throwsA(isA<AiV3RetrievalException>()),
    );
    expect(
      () => AiV3ContextRequest.fromJson(_samplesQuery(limit: 33)),
      throwsA(isA<AiV3RetrievalException>()),
    );
  });

  test('samples retriever returns ranked facts without filesystem paths',
      () async {
    final fixture = await _fixture(libraryAssets: const <Map<String, dynamic>>[
      <String, dynamic>{
        'asset_id': 'sample:kick',
        'path': '/private/library/Trap_Kick_120.wav',
        'role': 'kick',
        'bpm': 120,
      },
      <String, dynamic>{
        'asset_id': 'sample:loop',
        'path': '/private/library/Trap_Drum_Loop_120.wav',
        'role': 'drums',
        'bpm': 120,
      },
      <String, dynamic>{
        'asset_id': 'sample:snare',
        'path': '/private/library/Snare.wav',
        'role': 'snare',
      },
    ]);
    final request = AiV3ContextRequest.fromJson(_samplesQuery(
      terms: const <String>['trap', 'kick'],
      limit: 2,
    ));
    final result = const AiV3ContextRetriever()
        .retrieve(snapshot: fixture.snapshot, request: request)
        .toJson();
    final item = (result['results'] as List).single as Map;
    final assets = (item['assets'] as List).cast<Map>();
    expect(assets.map((asset) => asset['asset_id']),
        <String>['sample:kick', 'sample:loop']);
    expect(assets.first['filename'], 'Trap_Kick_120.wav');
    expect(assets.first['match_count'], 2);
    expect(assets.first['rank'], 1);
    expect(jsonEncode(item), isNot(contains('/private/library')));
    expect(jsonEncode(item), isNot(contains('"path"')));
    expect(
      (item['placement_capabilities'] as Map)['max_placements_per_command'],
      128,
    );

    final phrase = const AiV3ContextRetriever()
        .retrieve(
          snapshot: fixture.snapshot,
          request: AiV3ContextRequest.fromJson(
            _samplesQuery(terms: const <String>['kick sample']),
          ),
        )
        .toJson();
    final phraseAssets =
        (((phrase['results'] as List).single as Map)['assets'] as List)
            .cast<Map>();
    expect(phraseAssets.first['asset_id'], 'sample:kick');

    final empty = const AiV3ContextRetriever()
        .retrieve(
          snapshot: fixture.snapshot,
          request: AiV3ContextRequest.fromJson(
            _samplesQuery(terms: const <String>['nonexistent-asset']),
          ),
        )
        .toJson();
    final emptyItem = (empty['results'] as List).single as Map;
    expect(emptyItem['assets'], isEmpty);
    expect((emptyItem['counts'] as Map)['records_total'], 0);
    expect((emptyItem['counts'] as Map)['has_more'], isFalse);
  });

  test('samples retrieval resolves exact IDs and discloses batch truncation',
      () async {
    final assets = List<Map<String, dynamic>>.generate(
      70,
      (index) => <String, dynamic>{
        'asset_id': 'sample:$index',
        'path': '/library/kick_$index.wav',
        'role': 'kick',
      },
    );
    final fixture = await _fixture(libraryAssets: assets);
    final raw = _samplesQuery(limit: 32);
    (raw['requests'] as List).add(
      ((_samplesQuery()['requests'] as List).single as Map<String, dynamic>)
        ..['request_id'] = 'samples-2',
    );
    final result = const AiV3ContextRetriever()
        .retrieve(
          snapshot: fixture.snapshot,
          request: AiV3ContextRequest.fromJson(raw),
        )
        .toJson();
    final items = (result['results'] as List).cast<Map>();
    expect(((items.first['counts'] as Map)['records_returned']), 32);
    expect(((items.last['counts'] as Map)['records_returned']), 32);
    expect(((items.last['counts'] as Map)['has_more']), isTrue);

    final exact = AiV3ContextRequest.fromJson(_samplesQuery(
      targets: const <String>['sample:69'],
      terms: const <String>[],
      fields: const <String>['asset_metadata'],
      limit: 1,
    ));
    final exactResult = const AiV3ContextRetriever()
        .retrieve(snapshot: fixture.snapshot, request: exact)
        .toJson();
    expect(
      ((((exactResult['results'] as List).single as Map)['assets'] as List)
          .single as Map)['asset_id'],
      'sample:69',
    );
  });

  test('samples retriever rejects unknown exact asset IDs', () async {
    final fixture = await _fixture();
    final request = AiV3ContextRequest.fromJson(_samplesQuery(
      targets: const <String>['sample:missing'],
      terms: const <String>[],
      fields: const <String>['asset_metadata'],
    ));
    expect(
      () => const AiV3ContextRetriever()
          .retrieve(snapshot: fixture.snapshot, request: request),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_target_unknown',
      )),
    );
  });

  test('automation contract requires exact rows and supported fields', () {
    expect(
      AiV3ContextRequest.fromJson(_automationQuery()).requests.single,
      isA<AiV3AutomationContextQuery>(),
    );
    expect(
      () => AiV3ContextRequest.fromJson(
        _automationQuery(targets: const <int>[]),
      ),
      throwsA(isA<AiV3RetrievalException>()),
    );
    expect(
      () => AiV3ContextRequest.fromJson(
        _automationQuery(fields: const <String>['clips']),
      ),
      throwsA(isA<AiV3RetrievalException>()),
    );
    expect(
      () => AiV3ContextRequest.fromJson(_automationQuery(limit: 513)),
      throwsA(isA<AiV3RetrievalException>()),
    );
  });

  test('automation retriever returns exact sorted immutable gain points',
      () async {
    final fixture = await _fixture(
      volumeAutomation: <AutomationPoint>[
        AutomationPoint(x: 2000, volume: 1),
        AutomationPoint(x: 0, volume: 0),
        AutomationPoint(x: 1000, volume: 0.5),
      ],
    );
    final result = const AiV3ContextRetriever()
        .retrieve(
          snapshot: fixture.snapshot,
          request: AiV3ContextRequest.fromJson(_automationQuery(limit: 2)),
        )
        .toJson();
    final item = (result['results'] as List).single as Map;
    final row = (item['rows'] as List).single as Map;
    expect(item['matched_row_ids'], <int>[20]);
    expect(row['gain_points'], <Map<String, dynamic>>[
      <String, dynamic>{'time_ms': 0.0, 'value': 0.0},
      <String, dynamic>{'time_ms': 1000.0, 'value': 0.5},
    ]);
    expect((item['counts'] as Map)['points_total'], 3);
    expect((item['counts'] as Map)['points_returned'], 2);
    expect((item['counts'] as Map)['has_more'], isTrue);
    expect((item['target_capabilities'] as Map)['to_current_supported'], true);

    expect(
      () => const AiV3ContextRetriever().retrieve(
        snapshot: fixture.snapshot,
        request: AiV3ContextRequest.fromJson(
          _automationQuery(targets: const <int>[999]),
        ),
      ),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_target_unknown',
      )),
    );
  });

  test('automation retriever returns exact target metadata and point lanes',
      () async {
    final fixture = await _fixture();
    final result = const AiV3ContextRetriever()
        .retrieve(
          snapshot: fixture.snapshot,
          request: AiV3ContextRequest.fromJson(
            _automationQuery(
              fields: const <String>[
                'automation_targets',
                'automation_points',
                'target_capabilities',
              ],
            ),
          ),
        )
        .toJson();
    final item = (result['results'] as List).single as Map;
    final row = (item['rows'] as List).single as Map;
    expect(
      (row['automation_targets'] as List)
          .map((target) => (target as Map)['automation_target_id']),
      <String>['mix:pan', 'volume'],
    );
    expect(
      (row['automation_points'] as Map)['mix:pan'],
      <Map<String, dynamic>>[
        <String, dynamic>{'time_ms': 0.0, 'value': 0.25},
        <String, dynamic>{'time_ms': 2000.0, 'value': 0.75},
      ],
    );
    expect((item['target_capabilities'] as Map)['supports_set_points'], true);
    expect((item['target_capabilities'] as Map)['supports_clear'], true);
  });

  test('common request returns after one call and preserves active builder',
      () async {
    final fixture = await _fixture();
    final sent = <Map<String, dynamic>>[];
    final client = MockClient((http.Request request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      return http.Response(
        jsonEncode(_response('submit_plan_v3', _respondPlan())),
        200,
      );
    });
    final service = AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    );
    final result = await service.plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'What is the BPM?',
    );
    expect(result.callCount, 1);
    expect(sent, hasLength(1));
    expect((sent.single['tools'] as List), hasLength(2));
    expect(_submittedCommandTypes(sent.single), aiV3CommandTypes);
    expect(sent.single['tool_choice'], 'required');
    final activeImplicit = buildAiV3PlannerRequestBody(
      contextData: fixture.compact.data,
      originalRequest: 'What is the BPM?',
      model: 'gpt-5.4-mini',
      reasoningEffort: 'low',
    );
    final activeExplicit = buildAiV3PlannerRequestBody(
      contextData: fixture.compact.data,
      originalRequest: 'What is the BPM?',
      model: 'gpt-5.4-mini',
      reasoningEffort: 'low',
      commandTypes: aiV3CommandTypes,
      architecture: 'v3_one_shot_prototype',
    );
    expect(jsonEncode(activeImplicit), jsonEncode(activeExplicit));
  });

  test('first call directly accepts any canonical command', () async {
    final fixture = await _fixture();
    final sent = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      return http.Response(
        jsonEncode(_response('submit_plan_v3', _transposePlan())),
        200,
      );
    });

    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Transpose Keys down two semitones.',
    );

    expect(result.callCount, 1);
    expect(result.plan.commands.single.type, 'midi.transpose');
    expect(_submittedCommandTypes(sent.single), aiV3CommandTypes);
  });

  test('MIDI request performs one retrieval and one final continuation',
      () async {
    final fixture = await _fixture();
    final sent = <Map<String, dynamic>>[];
    var call = 0;
    final client = MockClient((http.Request request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _query())
            : _response('submit_plan_v3', _transposePlan())),
        200,
      );
    });
    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Transpose Keys down two semitones.',
    );
    expect(result.callCount, 2);
    expect(result.retrievalResult, isNotNull);
    expect(result.plan.commands.single.type, 'midi.transpose');
    expect(sent, hasLength(2));
    expect((sent[1]['tools'] as List), hasLength(1));
    expect((sent[1]['tools'] as List).single['name'], 'submit_plan_v3');
    expect(jsonEncode(sent[1]), contains('TYPED_RETRIEVAL_RESULTS_JSON'));
    expect(jsonEncode(sent[1]), isNot(contains('get_context_domains')));
    expect(_submittedCommandTypes(sent[1]), aiV3CommandTypes);
    expect(result.meta['surface_revision'], aiV3AdaptiveSurfaceRevision);
    expect(result.meta['call_count'], 2);
  });

  test('MIDI continuation rejects a clip absent from retrieved MIDI facts',
      () async {
    final fixture = await _fixture();
    final plan = _transposePlan();
    final command = ((plan['commands'] as List).single as Map);
    (command['arguments'] as Map)['clip_id'] = 'clip-not-returned';
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _query())
            : _response('submit_plan_v3', plan)),
        200,
      );
    });

    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Transpose another MIDI clip.',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_midi_clip_not_retrieved',
      )),
    );
  });

  test('MIDI edit continuations require and accept returned clip IDs',
      () async {
    final fixture = await _fixture();
    for (final type in const <String>[
      'midi.replace_notes',
      'midi.append_notes',
      'midi.chop_notes',
    ]) {
      Future<AiV3AdaptivePlannerResult> run(String clipId) {
        var call = 0;
        final client = MockClient((_) async {
          call++;
          return http.Response(
            jsonEncode(call == 1
                ? _response('get_context_domains', _query())
                : _response(
                    'submit_plan_v3',
                    _midiEditPlan(type, clipId: clipId),
                  )),
            200,
          );
        });
        return AiV3AdaptivePlannerService(
          apiKey: 'test-key',
          model: 'gpt-5.4-mini',
          httpClient: client,
        ).plan(
          compactCore: fixture.compact,
          snapshot: fixture.snapshot,
          originalRequest: 'Edit the Keys notes.',
        );
      }

      expect((await run('clip-midi')).plan.commands.single.type, type);
      await expectLater(
        run('clip-not-returned'),
        throwsA(
          isA<AiV3AdaptivePlannerException>().having(
            (error) => error.code,
            'code',
            'v3_adaptive_midi_clip_not_retrieved',
          ),
        ),
        reason: type,
      );
    }
  });

  test('MIDI continuation accepts a returned existing destination row',
      () async {
    final fixture = await _fixture();
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _query(
                  targets: const <Object>[20],
                  fields: const <String>['edit_capabilities'],
                ),
              )
            : _response('submit_plan_v3', _createMidiPlan())),
        200,
      );
    });

    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Create a short MIDI clip on Keys.',
    );
    expect(result.plan.commands.single.type, 'midi.create_clip');
  });

  test('MIDI continuation rejects an existing row absent from MIDI facts',
      () async {
    final fixture = await _fixture(includeAudioClip: true);
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _query(
                  targets: const <Object>[20],
                  fields: const <String>['edit_capabilities'],
                ),
              )
            : _response(
                'submit_plan_v3',
                _createMidiPlan(rowId: 30),
              )),
        200,
      );
    });

    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Create MIDI on another row.',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_midi_row_not_retrieved',
      )),
    );
  });

  test('MIDI continuation requires a returned new-row instrument', () async {
    final fixture = await _fixture();

    Future<AiV3AdaptivePlannerResult> run(String instrumentId) {
      var call = 0;
      final client = MockClient((_) async {
        call++;
        return http.Response(
          jsonEncode(call == 1
              ? _response(
                  'get_context_domains',
                  _query(
                    fields: const <String>['edit_capabilities'],
                  ),
                )
              : _response(
                  'submit_plan_v3',
                  _createMidiPlan(
                    rowId: null,
                    newRowInstrumentId: instrumentId,
                  ),
                )),
          200,
        );
      });
      return AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Create a new MIDI row and clip.',
      );
    }

    expect((await run('piano')).plan.commands.single.type, 'midi.create_clip');
    await expectLater(
      run('instrument-not-returned'),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_midi_instrument_not_retrieved',
      )),
    );
  });

  test('MIDI continuation may reuse an instrument returned with a source clip',
      () async {
    final fixture = await _fixture();

    Future<AiV3AdaptivePlannerResult> run(String instrumentId) {
      var call = 0;
      final client = MockClient((_) async {
        call++;
        return http.Response(
          jsonEncode(call == 1
              ? _response(
                  'get_context_domains',
                  _query(
                    fields: const <String>[
                      'clip_notes',
                      'clip_instruments',
                    ],
                  ),
                )
              : _response(
                  'submit_plan_v3',
                  _createMidiPlan(
                    rowId: null,
                    newRowInstrumentId: instrumentId,
                  ),
                )),
          200,
        );
      });
      return AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest:
            'Create a variation on a new row using the source instrument.',
      );
    }

    expect((await run('piano')).plan.commands.single.type, 'midi.create_clip');
    await expectLater(
      run('bass'),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_midi_instrument_not_retrieved',
      )),
    );
  });

  test(
      'new-row music generation retrieves allowed instruments and completes once',
      () async {
    final fixture = await _fixture(
      allowedInstrumentIds: const <String>[
        'house-drums',
        'reese-bass',
        'upright-piano',
      ],
    );
    final sent = <Map<String, dynamic>>[];
    var call = 0;
    final client = MockClient((request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      call++;
      return http.Response(
        jsonEncode(
          call == 1
              ? _response(
                  'get_context_domains',
                  _query(
                    targets: const <Object>[],
                    fields: const <String>['edit_capabilities'],
                    limit: 1,
                  ),
                )
              : _response('submit_plan_v3', _createThreePartMidiPlan()),
        ),
        200,
      );
    });

    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest:
          'Create new house drums, Reese bass, and upright piano MIDI rows.',
    );

    expect(result.callCount, 2);
    expect(
      result.plan.commands.map((command) => command.type),
      <String>[
        'project.set_tempo',
        'midi.create_clip',
        'midi.create_clip',
        'midi.create_clip',
      ],
    );
    final midiResult = result.retrievalResult!.results
        .whereType<AiV3MidiRetrievalResult>()
        .single;
    expect(
      midiResult.instrumentIds,
      <String>['house-drums', 'reese-bass', 'upright-piano'],
    );
    expect(
      jsonEncode(sent.first),
      allOf(
        contains('creating a new instrument row'),
        contains('bounded allowed instrument IDs'),
      ),
    );
    expect(
      jsonEncode(sent.last),
      allOf(
        contains('house-drums'),
        contains('reese-bass'),
        contains('upright-piano'),
      ),
    );
  });

  test('MIDI continuation rejects a valid instrument omitted by truncation',
      () async {
    final instruments = List<String>.generate(
      aiV3MaxRetrievedInstrumentIds + 1,
      (index) => 'instrument_${index.toString().padLeft(3, '0')}',
    );
    final fixture = await _fixture(allowedInstrumentIds: instruments);
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _query(fields: const <String>['edit_capabilities']),
              )
            : _response(
                'submit_plan_v3',
                _createMidiPlan(
                  rowId: null,
                  newRowInstrumentId: instruments.last,
                ),
              )),
        200,
      );
    });

    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Create a new MIDI row with the last instrument.',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_midi_instrument_not_retrieved',
      )),
    );
  });

  test('advanced clip pitch uses one retrieval and one continuation', () async {
    final fixture = await _fixture(includeAudioClip: true);
    final sent = <Map<String, dynamic>>[];
    var call = 0;
    final client = MockClient((http.Request request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _clipAdvancedQuery())
            : _response('submit_plan_v3', _pitchPlan())),
        200,
      );
    });
    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Lower the Vocal clip by two semitones.',
    );

    expect(result.callCount, 2);
    expect(result.plan.commands.single.type, 'clip.adjust_pitch_semitones');
    final continuation = jsonEncode(sent[1]['tools']);
    expect(continuation, contains('clip.set_pitch_semitones'));
    expect(continuation, contains('clip.adjust_pitch_semitones'));
    expect(continuation, contains('clip.set_timeline_length_beats'));
    expect(continuation, contains('clip.scale_timeline_length'));
    expect(continuation, contains('clip.set_source_tempo_bpm'));
    expect(continuation, contains('clip.set_tempo_follow_mode'));
    expect(continuation, contains('clip.align_tempo_to_project'));
    expect(continuation, contains('project.set_tempo_from_clip'));
    expect(continuation, contains('midi.transpose'));
  });

  test('advanced clip continuation rejects a clip absent from retrieval',
      () async {
    final fixture = await _fixture(includeAudioClip: true);
    var call = 0;
    final client = MockClient((http.Request request) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _clipAdvancedQuery())
            : _response(
                'submit_plan_v3',
                _pitchPlan(clipId: 'invented-clip'),
              )),
        200,
      );
    });
    expect(
      () => AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Lower the Vocal clip by two semitones.',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_clip_target_not_retrieved',
      )),
    );
  });

  test('advanced clip glue accepts only clips returned by retrieval', () async {
    final fixture = await _fixture(
      includeAudioClip: true,
      includeSecondAudioClip: true,
    );
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _clipAdvancedQuery(
                  targets: const <Object>[
                    'clip-audio',
                    'clip-audio-2',
                  ],
                ),
              )
            : _response('submit_plan_v3', _gluePlan())),
        200,
      );
    });
    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Glue the two Vocal clips.',
    );

    expect(result.callCount, 2);
    expect(result.plan.commands.single.type, 'clip.glue');
  });

  test('advanced clip glue rejects any source omitted from retrieval',
      () async {
    final fixture = await _fixture(
      includeAudioClip: true,
      includeSecondAudioClip: true,
    );
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _clipAdvancedQuery(
                  targets: const <Object>['clip-audio'],
                ),
              )
            : _response('submit_plan_v3', _gluePlan())),
        200,
      );
    });

    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Glue the two Vocal clips.',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_clip_target_not_retrieved',
      )),
    );
  });

  test('advanced stem separation accepts only a returned source clip',
      () async {
    final fixture = await _fixture(includeAudioClip: true);
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _clipAdvancedQuery(
                  targets: const <Object>['clip-audio'],
                ),
              )
            : _response('submit_plan_v3', _stemPlan())),
        200,
      );
    });
    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Separate the Vocal clip.',
    );

    expect(result.callCount, 2);
    expect(result.plan.commands.single.type, 'clip.separate_stems');
  });

  test('adaptive continuation accepts a typed generated clip target', () async {
    final fixture = await _fixture(includeAudioClip: true);
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _clipAdvancedQuery(
                  targets: const <Object>['clip-audio'],
                ),
              )
            : _response('submit_plan_v3', _stemPitchRefPlan())),
        200,
      );
    });

    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      resourceRefsEnabled: true,
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Perform the ordered generated-resource edit.',
    );

    expect(result.callCount, 2);
    expect(result.plan.commands, hasLength(2));
    expect(
      result.plan.commands.last.arguments['clip_ref'],
      <String, dynamic>{
        'command_id': 'separate-vocal',
        'output': 'instrumental_clip',
      },
    );
  });

  test('adaptive MIDI guard accepts a typed generated clip target', () async {
    final fixture = await _fixture();
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _query())
            : _response(
                'submit_plan_v3',
                _generatedMidiTransposeRefPlan(),
              )),
        200,
      );
    });

    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      resourceRefsEnabled: true,
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Create and transpose a generated MIDI clip.',
    );

    expect(result.callCount, 2);
    expect(result.plan.commands, hasLength(3));
    expect(
      result.plan.commands.last.arguments['clip_ref'],
      <String, dynamic>{
        'command_id': 'create-clip',
        'output': 'midi_clip',
      },
    );
  });

  test('advanced stem separation rejects a source omitted from retrieval',
      () async {
    final fixture = await _fixture(
      includeAudioClip: true,
      includeSecondAudioClip: true,
    );
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _clipAdvancedQuery(
                  targets: const <Object>['clip-audio'],
                ),
              )
            : _response(
                'submit_plan_v3',
                _stemPlan(clipId: 'clip-audio-2'),
              )),
        200,
      );
    });

    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Separate the second Vocal clip.',
      ),
      throwsA(
        isA<AiV3AdaptivePlannerException>().having(
          (error) => error.code,
          'code',
          'v3_adaptive_clip_target_not_retrieved',
        ),
      ),
    );
  });

  test('audio-to-MIDI accepts returned clip and instrument facts', () async {
    final fixture = await _fixture(includeAudioClip: true);
    final clipRequest = _clipAdvancedQuery();
    final midiRequest = _query(
      targets: const <Object>[],
      fields: const <String>['edit_capabilities'],
    );
    final combinedRequest = <String, dynamic>{
      'schema_version': aiV3ContextRequestVersion,
      'requests': <Object>[
        ...(clipRequest['requests'] as List),
        ...(midiRequest['requests'] as List),
      ],
    };
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', combinedRequest)
            : _response('submit_plan_v3', _audioToMidiPlan())),
        200,
      );
    });

    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Convert the Vocal clip to piano MIDI.',
    );

    expect(result.callCount, 2);
    expect(result.plan.commands.single.type, 'clip.convert_to_midi');
  });

  test('audio-to-MIDI rejects an instrument omitted from MIDI retrieval',
      () async {
    final fixture = await _fixture(
      includeAudioClip: true,
      allowedInstrumentIds: const <String>['piano'],
    );
    final clipRequest = _clipAdvancedQuery();
    final midiRequest = _query(
      targets: const <Object>[],
      fields: const <String>['edit_capabilities'],
    );
    final combinedRequest = <String, dynamic>{
      'schema_version': aiV3ContextRequestVersion,
      'requests': <Object>[
        ...(clipRequest['requests'] as List),
        ...(midiRequest['requests'] as List),
      ],
    };
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', combinedRequest)
            : _response(
                'submit_plan_v3',
                _audioToMidiPlan(instrumentId: 'bass'),
              )),
        200,
      );
    });

    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Convert the Vocal clip to bass MIDI.',
      ),
      throwsA(
        isA<AiV3AdaptivePlannerException>().having(
          (error) => error.code,
          'code',
          'v3_adaptive_midi_instrument_not_retrieved',
        ),
      ),
    );
  });

  test('effects request retains the complete command surface', () async {
    final fixture = await _fixture(
      allowedEffects: const <String>['Reverb'],
      effects: const <EffectState>[
        EffectState(
          effectIndex: 0,
          instanceId: 'fx-reverb',
          effectId: 'Reverb',
          name: 'Reverb',
          isBypassed: false,
          parameters: <EffectParameterState>[],
        ),
      ],
    );
    final sent = <Map<String, dynamic>>[];
    var call = 0;
    final client = MockClient((http.Request request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _effectsQuery())
            : _response('submit_plan_v3', _bypassPlan())),
        200,
      );
    });
    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Bypass Reverb on Keys.',
    );
    final continuation = jsonEncode(sent.last['tools']);
    expect(result.plan.commands.single.type, 'effect.set_bypassed');
    expect(continuation, contains('effect.ensure_configured'));
    expect(continuation, contains('effect.remove'));
    expect(continuation, contains('effect.set_bypassed'));
    expect(continuation, contains('midi.transpose'));
    expect(_submittedCommandTypes(sent.last), aiV3CommandTypes);
    expect(result.meta['call_count'], 2);
  });

  test('sample request retains the complete command surface', () async {
    final fixture = await _fixture(libraryAssets: const <Map<String, dynamic>>[
      <String, dynamic>{
        'asset_id': 'sample:kick',
        'path': '/library/Trap_Kick.wav',
        'role': 'kick',
      },
    ]);
    final sent = <Map<String, dynamic>>[];
    var call = 0;
    final client = MockClient((http.Request request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _samplesQuery())
            : _response('submit_plan_v3', _samplePlan())),
        200,
      );
    });
    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Place a kick sample at the start.',
    );
    final continuation = jsonEncode(sent.last['tools']);
    expect(result.callCount, 2);
    expect(result.plan.commands.single.type, 'sample.place');
    expect(continuation, contains('sample.place'));
    expect(continuation, contains('midi.transpose'));
    expect(continuation, contains('effect.ensure_configured'));
    expect(continuation, isNot(contains('get_context_domains')));
  });

  test('sample continuation rejects assets absent from retrieval', () async {
    final fixture = await _fixture(libraryAssets: const <Map<String, dynamic>>[
      <String, dynamic>{
        'asset_id': 'sample:kick',
        'path': '/library/Trap_Kick.wav',
        'role': 'kick',
      },
    ]);
    var call = 0;
    final client = MockClient((http.Request request) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _samplesQuery(terms: const <String>['orchestral gong']),
              )
            : _response('submit_plan_v3', _samplePlan())),
        200,
      );
    });

    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Place an orchestral gong sample.',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_sample_asset_not_retrieved',
      )),
    );
  });

  test('sample replacement accepts only a returned asset', () async {
    final fixture = await _fixture(libraryAssets: const <Map<String, dynamic>>[
      <String, dynamic>{
        'asset_id': 'sample:kick',
        'path': '/library/Trap_Kick.wav',
        'role': 'kick',
      },
    ]);

    Future<AiV3AdaptivePlannerResult> run(String assetId) {
      var call = 0;
      final client = MockClient((http.Request request) async {
        call++;
        return http.Response(
          jsonEncode(call == 1
              ? _response('get_context_domains', _samplesQuery())
              : _response(
                  'submit_plan_v3',
                  _sampleReplacePlan(assetId: assetId),
                )),
          200,
        );
      });
      return AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Replace the selected clip with the kick sample.',
      );
    }

    final accepted = await run('sample:kick');
    expect(accepted.plan.commands.single.type, 'sample.replace');
    await expectLater(
      run('sample:invented'),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_sample_asset_not_retrieved',
      )),
    );
  });

  test('retrieval provenance applies only to the requested domain', () async {
    final fixture = await _fixture(libraryAssets: const <Map<String, dynamic>>[
      <String, dynamic>{
        'asset_id': 'sample:kick',
        'path': '/library/Trap_Kick.wav',
        'role': 'kick',
      },
    ]);
    final finalPlan = <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Place the kick and transpose Keys.',
      'commands': <Map<String, dynamic>>[
        ...(_samplePlan()['commands'] as List).cast<Map<String, dynamic>>(),
        ...(_transposePlan()['commands'] as List).cast<Map<String, dynamic>>(),
      ],
      'question_options': const <Object>[],
    };
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _samplesQuery())
            : _response('submit_plan_v3', finalPlan)),
        200,
      );
    });

    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Place the kick and transpose Keys.',
    );

    expect(result.plan.commands.map((command) => command.type),
        <String>['sample.place', 'midi.transpose']);
  });

  test('effects provenance rejects an unreturned instance', () async {
    final fixture = await _fixture(
      allowedEffects: const <String>['Reverb'],
      effects: const <EffectState>[
        EffectState(
          effectIndex: 0,
          instanceId: 'fx-reverb',
          effectId: 'Reverb',
          name: 'Reverb',
          isBypassed: false,
          parameters: <EffectParameterState>[],
        ),
      ],
    );
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _effectsQuery(
                  targets: const <int>[],
                  fields: const <String>['catalog'],
                ),
              )
            : _response('submit_plan_v3', _bypassPlan())),
        200,
      );
    });

    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Bypass Reverb on Keys.',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_effect_instance_not_retrieved',
      )),
    );
  });

  test('effects continuation accepts returned configuration facts', () async {
    final fixture = await _fixture(
      allowedEffects: const <String>['Reverb'],
    );
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _effectsQuery(fields: const <String>['catalog']),
              )
            : _response('submit_plan_v3', _ensureEffectPlan())),
        200,
      );
    });

    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Configure Reverb on Keys.',
    );
    expect(result.plan.commands.single.type, 'effect.ensure_configured');
  });

  test('effects continuation accepts unique canonical parameter casing',
      () async {
    final fixture = await _fixture(
      allowedEffects: const <String>['Reverb'],
    );
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _effectsQuery(
                  fields: const <String>['parameter_definitions'],
                ),
              )
            : _response(
                'submit_plan_v3',
                _ensureEffectPlan(parameterId: 'mix'),
              )),
        200,
      );
    });

    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Set the Reverb mix.',
    );
    expect(result.plan.commands.single.type, 'effect.ensure_configured');
  });

  test('effects continuation rejects configuration facts not returned',
      () async {
    Future<void> expectRejected({
      required ({PlanningSnapshotV3 snapshot, CompactCoreV3 compact}) fixture,
      required Map<String, dynamic> query,
      required Map<String, dynamic> plan,
    }) async {
      var call = 0;
      final client = MockClient((_) async {
        call++;
        return http.Response(
          jsonEncode(call == 1
              ? _response('get_context_domains', query)
              : _response('submit_plan_v3', plan)),
          200,
        );
      });
      await expectLater(
        AiV3AdaptivePlannerService(
          apiKey: 'test-key',
          model: 'gpt-5.4-mini',
          httpClient: client,
        ).plan(
          compactCore: fixture.compact,
          snapshot: fixture.snapshot,
          originalRequest: 'Configure an effect.',
        ),
        throwsA(isA<AiV3AdaptivePlannerException>().having(
          (error) => error.code,
          'code',
          'v3_adaptive_effect_configuration_not_retrieved',
        )),
      );
    }

    final reverbFixture = await _fixture(
      allowedEffects: const <String>['Reverb'],
    );
    await expectRejected(
      fixture: reverbFixture,
      query: _effectsQuery(fields: const <String>['catalog']),
      plan: _ensureEffectPlan(rowId: 999),
    );
    await expectRejected(
      fixture: reverbFixture,
      query: _effectsQuery(fields: const <String>['catalog']),
      plan: _ensureEffectPlan(parameterId: 'Parameter Not Returned'),
    );

    final truncatedFixture = await _fixture(
      allowedEffects: const <String>['Limiter', 'Reverb'],
    );
    await expectRejected(
      fixture: truncatedFixture,
      query: _effectsQuery(
        fields: const <String>['catalog'],
        limit: 1,
      ),
      plan: _ensureEffectPlan(effectId: 'Reverb'),
    );
  });

  test('automation request exposes gain fade on one continuation', () async {
    final fixture = await _fixture();
    final sent = <Map<String, dynamic>>[];
    var call = 0;
    final client = MockClient((http.Request request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _automationQuery())
            : _response('submit_plan_v3', _automationPlan())),
        200,
      );
    });
    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Fade Keys in over the first bar.',
    );
    final continuation = jsonEncode(sent.last['tools']);
    expect(result.callCount, 2);
    expect(result.plan.commands.single.type, 'automation.gain_fade');
    expect(continuation, contains('automation.gain_fade'));
    expect(continuation, contains('sample.place'));
    expect(continuation, isNot(contains('get_context_domains')));
  });

  test('automation continuation rejects an unreturned row target', () async {
    final fixture = await _fixture();
    var call = 0;
    final client = MockClient((http.Request request) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _automationQuery())
            : _response(
                'submit_plan_v3',
                _automationPlan(rowId: 999),
              )),
        200,
      );
    });
    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Fade Keys in over the first bar.',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_automation_target_not_retrieved',
      )),
    );
  });

  test('automation continuation requires returned exact target facts',
      () async {
    Future<Object> runWithPlan(Map<String, dynamic> plan) async {
      final fixture = await _fixture();
      var call = 0;
      final client = MockClient((http.Request request) async {
        call++;
        return http.Response(
          jsonEncode(call == 1
              ? _response(
                  'get_context_domains',
                  _automationQuery(fields: const <String>[
                    'automation_targets',
                    'automation_points',
                  ]),
                )
              : _response('submit_plan_v3', plan)),
          200,
        );
      });
      return AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Set an exact pan automation curve on Keys.',
      );
    }

    final accepted =
        await runWithPlan(_automationPointsPlan()) as AiV3AdaptivePlannerResult;
    expect(accepted.plan.commands.single.type, 'automation.set_points');

    await expectLater(
      runWithPlan(_automationPointsPlan(targetId: 'missing')),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_automation_target_not_retrieved',
      )),
    );
  });

  test('mix contract enforces factual row and group target fields', () {
    expect(
      () => AiV3ContextRequest.fromJson(_mixQuery(
        targets: const <Object>[20],
        fields: const <String>['group_state'],
      )),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_mix_target_fields_invalid',
      )),
    );
    expect(
      () => AiV3ContextRequest.fromJson(_mixQuery(
        targets: const <Object>[],
        fields: const <String>['master_state', 'engine_capabilities'],
      )),
      returnsNormally,
    );
    expect(
      () => AiV3ContextRequest.fromJson(_mixQuery(
        targets: const <Object>[],
        fields: const <String>[
          'master_state',
          'reference_analysis',
          'engine_capabilities',
        ],
      )),
      returnsNormally,
    );
    expect(
      () => AiV3ContextRequest.fromJson(_mixQuery(limit: 33)),
      throwsA(isA<AiV3RetrievalException>().having(
        (error) => error.code,
        'code',
        'v3_retrieval_limit_invalid',
      )),
    );
  });

  test('mix retriever returns bounded planner facts from the snapshot',
      () async {
    final fixture = await _fixture(
      hasAudio: true,
      audioStats: const <String, double>{'centroid_hz': 1200},
      grouped: true,
    );
    final request = AiV3ContextRequest.fromJson(_mixQuery(
      targets: const <Object>[20, 'group-keys'],
      fields: const <String>[
        'row_analysis',
        'group_state',
        'master_state',
        'reference_analysis',
        'engine_capabilities',
      ],
    ));
    final result = const AiV3ContextRetriever().retrieve(
      snapshot: fixture.snapshot,
      request: request,
    );
    final mix = result.results.single as AiV3MixRetrievalResult;
    expect(mix.matchedRowIds, const <int>[20]);
    expect(mix.matchedGroupIds, const <String>['group-keys']);
    expect(mix.rowAnalysis.single['mix_processing_supported'], isTrue);
    expect(mix.rowAnalysis.single['has_usable_signal'], isTrue);
    expect(mix.rowAnalysis.single['analysis_available'], isTrue);
    expect(mix.referenceAnalysis.single['reference_suitable'], isTrue);
    expect(mix.groupState.single['member_row_ids'], const <int>[20]);
    expect(mix.masterState, isNotNull);
    expect(mix.engineCapabilities?['local_heuristic_available'], isTrue);
    final encoded = jsonEncode(mix.toJson());
    expect(encoded, isNot(contains('audio_statistics')));
    expect(encoded, isNot(contains('overlap_matrix')));
    expect(encoded, isNot(contains('MixAction')));
  });

  test('mix retrieval distinguishes silent analyzed audio from a reference',
      () async {
    final fixture = await _fixture(
      hasAudio: true,
      approxRms: 0,
      audioStats: const <String, double>{'centroid_hz': 0},
    );
    final result = const AiV3ContextRetriever().retrieve(
      snapshot: fixture.snapshot,
      request: AiV3ContextRequest.fromJson(_mixQuery()),
    );
    final mix = result.results.single as AiV3MixRetrievalResult;
    expect(mix.rowAnalysis.single['mix_processing_supported'], isTrue);
    expect(mix.rowAnalysis.single['has_usable_signal'], isFalse);
    expect(mix.rowAnalysis.single['analysis_available'], isTrue);
    expect(mix.referenceAnalysis.single['reference_suitable'], isFalse);
  });

  test('mix request retains the complete command surface', () async {
    final fixture = await _fixture(
      hasAudio: true,
      audioStats: const <String, double>{'centroid_hz': 1200},
    );
    final sent = <Map<String, dynamic>>[];
    var call = 0;
    final client = MockClient((http.Request request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _mixQuery())
            : _response('submit_plan_v3', _mixPlan(referenceRowId: 20))),
        200,
      );
    });
    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Balance the mix using Keys as a reference.',
    );
    final continuation = jsonEncode(sent.last['tools']);
    expect(result.callCount, 2);
    expect(result.plan.commands.single.type, 'mix.apply_goal');
    expect(continuation, contains('mix.apply_goal'));
    expect(continuation, contains('midi.transpose'));
    expect(continuation, contains('automation.gain_fade'));
    expect(continuation, isNot(contains('get_context_domains')));
  });

  test('mix continuation rejects an unsuitable retrieved reference', () async {
    final fixture = await _fixture(
      hasAudio: true,
      approxRms: 0,
      audioStats: const <String, double>{'centroid_hz': 0},
    );
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', _mixQuery())
            : _response('submit_plan_v3', _mixPlan(referenceRowId: 20))),
        200,
      );
    });
    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Use Keys as the reference.',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_mix_reference_unsuitable',
      )),
    );
  });

  test('mix continuation rejects a reference absent from reference facts',
      () async {
    final fixture = await _fixture(
      hasAudio: true,
      audioStats: const <String, double>{'centroid_hz': 1200},
    );
    var call = 0;
    final client = MockClient((_) async {
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response(
                'get_context_domains',
                _mixQuery(fields: const <String>['row_analysis']),
              )
            : _response('submit_plan_v3', _mixPlan(referenceRowId: 20))),
        200,
      );
    });
    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Use Keys as the reference.',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_mix_reference_not_retrieved',
      )),
    );
  });

  test('mixed MIDI and effects retrieval uses one continuation schema',
      () async {
    final fixture = await _fixture(
      allowedEffects: const <String>['Reverb'],
      effects: const <EffectState>[
        EffectState(
          effectIndex: 0,
          instanceId: 'fx-reverb',
          effectId: 'Reverb',
          name: 'Reverb',
          isBypassed: false,
          parameters: <EffectParameterState>[],
        ),
      ],
    );
    final mixed = _query();
    (mixed['requests'] as List).add(
      (_effectsQuery()['requests'] as List).single,
    );
    final sent = <Map<String, dynamic>>[];
    var call = 0;
    final client = MockClient((http.Request request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', mixed)
            : _response('submit_plan_v3', _midiAndEffectPlan())),
        200,
      );
    });
    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Transpose Keys and bypass its Reverb.',
    );
    final continuation = jsonEncode(sent.last['tools']);
    expect(result.callCount, 2);
    expect(result.retrievalResult!.results, hasLength(2));
    expect(continuation, contains('midi.transpose'));
    expect(continuation, contains('effect.set_bypassed'));
    expect(continuation, contains('sample.place'));
  });

  test('mixed effects and mix retrieval exposes both domain commands',
      () async {
    final fixture = await _fixture(
      hasAudio: true,
      audioStats: const <String, double>{'centroid_hz': 1200},
      allowedEffects: const <String>['Reverb'],
      effects: const <EffectState>[
        EffectState(
          effectIndex: 0,
          instanceId: 'fx-reverb',
          effectId: 'Reverb',
          name: 'Reverb',
          isBypassed: false,
          parameters: <EffectParameterState>[],
        ),
      ],
    );
    final mixed = _effectsQuery();
    (mixed['requests'] as List).add((_mixQuery()['requests'] as List).single);
    final finalPlan = <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Bypass Reverb and balance the mix.',
      'commands': <Map<String, dynamic>>[
        ...(_bypassPlan()['commands'] as List).cast<Map<String, dynamic>>(),
        ...(_mixPlan()['commands'] as List).cast<Map<String, dynamic>>(),
      ],
      'question_options': const <Object>[],
    };
    final sent = <Map<String, dynamic>>[];
    var call = 0;
    final client = MockClient((http.Request request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', mixed)
            : _response('submit_plan_v3', finalPlan)),
        200,
      );
    });
    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Bypass Reverb and balance the mix.',
    );
    final continuation = jsonEncode(sent.last['tools']);
    expect(result.callCount, 2);
    expect(result.retrievalResult!.results, hasLength(2));
    expect(continuation, contains('effect.set_bypassed'));
    expect(continuation, contains('mix.apply_goal'));
    expect(continuation, contains('midi.transpose'));
  });

  test('mixed MIDI effects and samples use one retrieval continuation',
      () async {
    final fixture = await _fixture(
      allowedEffects: const <String>['Reverb'],
      libraryAssets: const <Map<String, dynamic>>[
        <String, dynamic>{
          'asset_id': 'sample:kick',
          'path': '/library/Trap_Kick.wav',
          'role': 'kick',
        },
      ],
    );
    final mixed = _query();
    (mixed['requests'] as List)
      ..add((_effectsQuery(
        targets: const <int>[],
        fields: const <String>['catalog'],
      )['requests'] as List)
          .single)
      ..add((_samplesQuery()['requests'] as List).single);
    final combinedPlan = <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': 'Transpose Keys and place a kick.',
      'commands': <Map<String, dynamic>>[
        ...(_transposePlan()['commands'] as List).cast<Map<String, dynamic>>(),
        ...(_samplePlan()['commands'] as List).cast<Map<String, dynamic>>(),
      ],
      'question_options': const <Object>[],
    };
    final sent = <Map<String, dynamic>>[];
    var call = 0;
    final client = MockClient((http.Request request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      call++;
      return http.Response(
        jsonEncode(call == 1
            ? _response('get_context_domains', mixed)
            : _response('submit_plan_v3', combinedPlan)),
        200,
      );
    });
    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Transpose Keys and add a kick sample.',
    );
    final continuation = jsonEncode(sent.last);
    expect(result.callCount, 2);
    expect(result.retrievalResult!.results, hasLength(3));
    expect(continuation, contains('midi.transpose'));
    expect(continuation, contains('effect.ensure_configured'));
    expect(continuation, contains('sample.place'));
  });

  test('first call accepts harmless zero-delta placeholder plans', () async {
    final fixture = await _fixture();
    final client = MockClient((_) async => http.Response(
          jsonEncode(_response('submit_plan_v3', _zeroMovePlan())),
          200,
        ));

    final result = await AiV3AdaptivePlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    ).plan(
      compactCore: fixture.compact,
      snapshot: fixture.snapshot,
      originalRequest: 'Transpose Keys up three semitones.',
    );

    expect(result.callCount, 1);
    expect(result.plan.commands.single.type, 'clip.move_by_beats');
    expect(result.plan.commands.single.arguments['delta_beats'], 0);
  });

  test('retrieval failure retains the exact typed request diagnostic',
      () async {
    final fixture = await _fixture();
    final invalid = _query(targets: const <Object>['missing-clip']);
    final client = MockClient((_) async => http.Response(
          jsonEncode(_response('get_context_domains', invalid)),
          200,
        ));

    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Transpose the missing clip.',
      ),
      throwsA(
        isA<AiV3AdaptivePlannerException>()
            .having(
              (error) => error.code,
              'code',
              'v3_adaptive_retrieval_failed',
            )
            .having(
              (error) => error.diagnostic['retrieval_request'],
              'retrieval_request',
              invalid,
            ),
      ),
    );
  });

  test('continuation cannot request a third call', () async {
    final fixture = await _fixture();
    final client = MockClient((_) async => http.Response(
          jsonEncode(_response('get_context_domains', _query())),
          200,
        ));
    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'Transpose Keys.',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'adaptive_third_call_forbidden',
      )),
    );
  });

  test('planner rejects multiple function calls in one response', () async {
    final fixture = await _fixture();
    final response = _response('submit_plan_v3', _respondPlan());
    (response['output'] as List).add(<String, dynamic>{
      'type': 'function_call',
      'name': 'get_context_domains',
      'arguments': jsonEncode(_query()),
    });
    final client = MockClient((_) async => http.Response(
          jsonEncode(response),
          200,
        ));
    await expectLater(
      AiV3AdaptivePlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      ).plan(
        compactCore: fixture.compact,
        snapshot: fixture.snapshot,
        originalRequest: 'What is the BPM?',
      ),
      throwsA(isA<AiV3AdaptivePlannerException>().having(
        (error) => error.code,
        'code',
        'v3_adaptive_tool_call_count_invalid',
      )),
    );
  });
}
