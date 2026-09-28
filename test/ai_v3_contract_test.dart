import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_preparer.dart';
import 'package:mixroom/ai/v3/ai_v3_resources.dart';
import 'package:mixroom/helpers/midi_pitch_ranges.dart';
import 'package:mixroom/helpers/sfz_definition_loader.dart';

Map<String, dynamic> _plan(List<Map<String, dynamic>> commands) =>
    <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': commands.isEmpty ? 'respond' : 'plan',
      'user_message': commands.isEmpty ? 'The BPM is 120.' : 'I prepared it.',
      'commands': commands,
      'question_options': const <String>[],
    };

Map<String, dynamic> _command(
  String id,
  String type,
  Map<String, dynamic> arguments,
) => <String, dynamic>{'command_id': id, 'type': type, 'arguments': arguments};

AiV3Plan _allRowsMixPlan() => AiV3Plan.fromJson(
  _plan(<Map<String, dynamic>>[
    _command('mix-all', 'mix.apply_goal', <String, dynamic>{
      'target': <String, dynamic>{'scope': 'all_rows'},
      'intents': <Map<String, dynamic>>[
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
      'reference': null,
    }),
  ]),
);

AiV3Plan _mixPlanForTarget(Map<String, dynamic> target) => AiV3Plan.fromJson(
  _plan(<Map<String, dynamic>>[
    _command('mix-target', 'mix.apply_goal', <String, dynamic>{
      'target': target,
      'intents': <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'reverb',
          'direction': 'up',
          'descriptor': null,
        },
      ],
      'intensity': 0.5,
      'execution_profile': 'producer_safe',
      'audibility': 'noticeable',
      'style_tags': const <String>[],
      'reset_fx': false,
      'reference': null,
    }),
  ]),
);

AiV3CoreContext _context() => AiV3CoreContext(
  profile: AiV3ContextProfile.essential,
  stateDigest: 'state-1',
  data: <String, dynamic>{
    'project': <String, dynamic>{
      'bpm': 120.0,
      'beats_per_bar': 4,
      'playhead_beat': 6.0,
      'tempo_stretch_enabled': false,
      'row_capacity': <String, dynamic>{
        'current_rows': 2,
        'max_rows': 32,
        'can_create': true,
      },
    },
    'transport': <String, dynamic>{
      'playing': false,
      'recording': false,
      'metronome_enabled': false,
      'loop_enabled': false,
      'loop_start_ms': 0,
      'loop_end_ms': 0,
    },
    'selection': <String, dynamic>{
      'selected_row_id': 100,
      'selected_clip_ids': const <String>[],
    },
    'rows': <Map<String, dynamic>>[
      <String, dynamic>{
        'row_id': 100,
        'display_index': 0,
        'name': 'Audio',
        'lane_kind': 'audio',
        'role_override': 'vocals',
        'gain_db': -30.0,
        'pan_signed': 0.0,
        'muted': false,
        'soloed': false,
        'color': 'none',
        'mix_processing_supported': true,
        'has_analyzable_audio': true,
        'automation_targets': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'volume',
            'label': 'Volume',
            'unit': 'normalized',
            'min': 0.0,
            'max': 1.0,
            'initialNormalized': 1.0,
            'isOrphan': false,
            'uiVisible': true,
          },
          <String, dynamic>{
            'id': 'mix:pan',
            'label': 'Track Pan',
            'unit': '',
            'min': 0.0,
            'max': 1.0,
            'initialNormalized': 0.5,
            'isOrphan': false,
            'uiVisible': true,
          },
          <String, dynamic>{
            'id': 'fx:reverb:mix',
            'label': 'Reverb Mix',
            'unit': '%',
            'min': 0.0,
            'max': 1.0,
            'initialNormalized': 0.2,
            'isOrphan': false,
            'uiVisible': true,
          },
        ],
        'effects': <Map<String, dynamic>>[
          <String, dynamic>{
            'effect_instance_id': 'fx-comp-1',
            'effect_id': 'Compressor',
            'display_name': 'Compressor',
            'bypassed': false,
            'parameters': const <Object>[],
          },
          <String, dynamic>{
            'effect_instance_id': 'fx-reverb-1',
            'effect_id': 'Reverb',
            'display_name': 'Reverb',
            'bypassed': false,
            'parameters': const <Object>[],
          },
        ],
      },
      <String, dynamic>{
        'row_id': 200,
        'display_index': 1,
        'name': 'Keys',
        'lane_kind': 'instrument',
        'instrument_id': 'piano',
        'gain_db': -30.0,
        'pan_signed': 0.0,
        'muted': true,
        'soloed': false,
        'color': 'blue',
        'mix_processing_supported': true,
        'has_analyzable_audio': false,
        'automation_targets': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'volume',
            'label': 'Volume',
            'unit': 'normalized',
            'min': 0.0,
            'max': 1.0,
            'initialNormalized': 1.0,
            'isOrphan': false,
            'uiVisible': true,
          },
        ],
      },
    ],
    'groups': const <Map<String, dynamic>>[],
    'master': <String, dynamic>{
      'gain_db': 0.0,
      'pan_signed': 0.0,
      'effects': const <Object>[],
    },
    'clips': <Map<String, dynamic>>[
      <String, dynamic>{
        'clip_id': 'audio-clip',
        'row_id': 100,
        'display_index': 0,
        'kind': 'audio',
        'name': 'Audio clip',
        'start_beat': 0.0,
        'length_beats': 8.0,
        'timeline_length_beats': 8.0,
        'pitch_semitones': 2.0,
        'stretch_to_project_tempo': false,
        'tempo_stretch_preserve_pitch': true,
        'source_tempo_bpm': 0.0,
        'tempo_warp_mode': 'complex',
        'trim_start_ms': 0.0,
        'trim_end_ms': 4000.0,
        'alignment_offset_ms': 0.0,
        'source_file': 'Project/Audio.wav',
      },
      <String, dynamic>{
        'clip_id': 'midi-clip',
        'row_id': 200,
        'display_index': 1,
        'kind': 'midi',
        'name': 'MIDI clip',
        'start_beat': 4.0,
        'length_beats': 8.0,
      },
    ],
    'instruments': <String>['piano', 'bass'],
    'effects': <Map<String, dynamic>>[
      <String, dynamic>{
        'effect_id': 'Reverb',
        'parameters': <Map<String, dynamic>>[
          <String, dynamic>{'parameter_id': 'Mix'},
        ],
      },
    ],
    'library_assets': <Map<String, dynamic>>[
      <String, dynamic>{
        'asset_id': 'kick-1',
        'path': 'Pack/Kick.wav',
        'role': 'kick',
      },
    ],
  },
);

AiV3CoreContext _contextWithEffects(
  Map<String, List<String>> effectParameters,
) {
  final data = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(_context().data)) as Map,
  );
  data['effects'] = effectParameters.entries
      .map(
        (entry) => <String, dynamic>{
          'effect_id': entry.key,
          'parameters': entry.value
              .map((parameter) => <String, dynamic>{'parameter_id': parameter})
              .toList(growable: false),
        },
      )
      .toList(growable: false);
  return AiV3CoreContext(
    profile: _context().profile,
    stateDigest: _context().stateDigest,
    data: data,
  );
}

AiV3CoreContext _contextWithSecondAudioClip() {
  final data = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(_context().data)) as Map,
  );
  final clips = (data['clips'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: true);
  clips.add(<String, dynamic>{
    'clip_id': 'audio-clip-2',
    'row_id': 100,
    'display_index': 2,
    'kind': 'audio',
    'name': 'Audio clip 2',
    'start_beat': 9.0,
    'length_beats': 3.0,
    'timeline_length_beats': 3.0,
    'pitch_semitones': 0.0,
    'stretch_to_project_tempo': false,
    'tempo_stretch_preserve_pitch': false,
    'source_tempo_bpm': 0.0,
    'tempo_warp_mode': 'complex',
    'trim_start_ms': 0.0,
    'trim_end_ms': 1500.0,
    'alignment_offset_ms': 0.0,
    'source_file': 'Project/Audio2.wav',
  });
  data['clips'] = clips;
  return AiV3CoreContext(
    profile: AiV3ContextProfile.essential,
    stateDigest: 'state-2',
    data: data,
  );
}

AiV3CoreContext _contextWithAudioClipBounds({
  required double startBeat,
  required double lengthBeats,
}) {
  final data = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(_context().data)) as Map,
  );
  final clips = (data['clips'] as List).cast<Map<String, dynamic>>();
  clips.first['start_beat'] = startBeat;
  clips.first['length_beats'] = lengthBeats;
  clips.first['timeline_length_beats'] = lengthBeats;
  return AiV3CoreContext(
    profile: AiV3ContextProfile.essential,
    stateDigest: 'state-1',
    data: data,
  );
}

AiV3CoreContext _contextForStemSeparation() {
  final base = _context();
  final data = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(base.data)) as Map,
  );
  data['runtime_capabilities'] = <String>['daw.stem_separate'];
  final clips = (data['clips'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: false);
  clips.singleWhere((clip) => clip['clip_id'] == 'audio-clip')['source_file'] =
      'pubspec.yaml';
  data['clips'] = clips;
  return AiV3CoreContext(
    profile: base.profile,
    stateDigest: base.stateDigest,
    data: data,
  );
}

AiV3CoreContext _contextForAudioToMidi() {
  final base = _context();
  final data = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(base.data)) as Map,
  );
  data['runtime_capabilities'] = <String>['daw.midi_compose.audio_to_midi'];
  final clips = (data['clips'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: false);
  clips.singleWhere((clip) => clip['clip_id'] == 'audio-clip')['source_file'] =
      'pubspec.yaml';
  data['clips'] = clips;
  return AiV3CoreContext(
    profile: base.profile,
    stateDigest: base.stateDigest,
    data: data,
  );
}

AiV3CoreContext _contextForPhoneMicCleanup({
  bool includeService = true,
  bool includeAllEffects = true,
  bool secondAudioClip = false,
}) {
  final base = secondAudioClip ? _contextWithSecondAudioClip() : _context();
  final data = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(base.data)) as Map,
  );
  data['runtime_capabilities'] = includeService
      ? <String>['daw.audio_enhance']
      : <String>[];
  final effects = <Map<String, dynamic>>[
    ...((data['effects'] as List).whereType<Map>().map(
      (effect) => Map<String, dynamic>.from(effect),
    )),
    for (final effectId in aiV3PhoneMicCleanupEffectIds)
      <String, dynamic>{'effect_id': effectId, 'parameters': const <Object>[]},
  ];
  if (!includeAllEffects) {
    effects.removeWhere((effect) => effect['effect_id'] == 'Limiter');
  }
  data['effects'] = effects;
  return AiV3CoreContext(
    profile: base.profile,
    stateDigest: base.stateDigest,
    data: data,
  );
}

AiV3CoreContext _contextWithCrossRowAudioClips() {
  final base = _contextWithSecondAudioClip();
  final data = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(base.data)) as Map,
  );
  final clips = (data['clips'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: false);
  clips.singleWhere((clip) => clip['clip_id'] == 'audio-clip-2')['row_id'] =
      200;
  data['clips'] = clips;
  return AiV3CoreContext(
    profile: base.profile,
    stateDigest: base.stateDigest,
    data: data,
  );
}

Map<String, dynamic> _note(
  int pitch,
  double start,
  double length, [
  double velocity = 0.8,
]) => <String, dynamic>{
  'pitch': pitch,
  'start_beat': start,
  'length_beats': length,
  'velocity': velocity,
};

AiV3CoreContext _contextWithMidiNotes(
  List<Map<String, dynamic>> notes, {
  double lengthBeats = 8.0,
}) {
  final base = _context();
  final clips = (base.data['clips'] as List)
      .whereType<Map>()
      .map((raw) {
        final clip = Map<String, dynamic>.from(raw);
        if (clip['clip_id'] == 'midi-clip') {
          clip['length_beats'] = lengthBeats;
          clip['midi_notes'] = notes;
        }
        return clip;
      })
      .toList(growable: false);
  return AiV3CoreContext(
    profile: base.profile,
    stateDigest: base.stateDigest,
    data: <String, dynamic>{...base.data, 'clips': clips},
  );
}

void main() {
  test(
    'gated MIDI boundary extension uses original budget and preserves notes',
    () {
      final notes = <Map<String, dynamic>>[_note(60, 31, 1)];
      final context = _contextWithMidiNotes(notes, lengthBeats: 31.9986);
      (context.data['project'] as Map)
        ..['bpm'] = 108
        ..['midi_boundary_policy'] = 'extend_1ms_v1';
      Map<String, dynamic> replace(String id, double end) =>
          _command(id, 'midi.replace_notes', {
            'clip_id': 'midi-clip',
            'notes': [_note(60, end - 1, 1)],
          });
      final prepared = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(_plan([replace('one', 32)])),
        context: context,
      );
      expect(prepared.actions, hasLength(1));
      expect(prepared.actions.single.data['notes'], notes);
      expect(
        prepared.actions.single.data['final_length_beats'],
        greaterThanOrEqualTo(32),
      );
      final appended = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(
          _plan([
            replace('one', 32),
            _command('append', 'midi.append_notes', {
              'clip_id': 'midi-clip',
              'notes': [_note(60, 0, 1)],
            }),
          ]),
        ),
        context: context,
      );
      expect(
        appended.actions.last.data['final_length_beats'],
        greaterThanOrEqualTo(33),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: AiV3Plan.fromJson(
            _plan([replace('one', 32), replace('two', 32.001)]),
          ),
          context: context,
        ),
        throwsA(isA<AiV3PreparationException>()),
      );
      for (final policy in [null, 'unknown']) {
        (context.data['project'] as Map)['midi_boundary_policy'] = policy;
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: AiV3Plan.fromJson(_plan([replace('one', 32)])),
            context: context,
          ),
          throwsA(isA<AiV3PreparationException>()),
        );
      }
    },
  );

  group('V3 typed resource references', () {
    Map<String, dynamic> ref(String commandId, String output) =>
        <String, dynamic>{'command_id': commandId, 'output': output};
    AiV3Plan parse(
      List<Map<String, dynamic>> commands, {
      Set<String>? consumers,
    }) => AiV3Plan.fromJson(
      _plan(commands),
      allowResourceRefs: true,
      resourceRefCommandTypes: consumers,
    );
    Map<String, dynamic> row(String id, String kind) =>
        _command(id, 'row.create', <String, dynamic>{
          'name': kind == 'midi' ? 'Synth' : 'Audio',
          'lane': kind == 'midi'
              ? <String, dynamic>{
                  'kind': 'midi',
                  'instrument_id': 'mixroom.basic_synth',
                }
              : <String, dynamic>{'kind': 'audio'},
          'position': <String, dynamic>{'kind': 'end'},
        });
    Map<String, dynamic> mixRow(String id, Map<String, dynamic> target) =>
        _command(id, 'mix.apply_goal', <String, dynamic>{
          'target': target,
          'intents': <Map<String, dynamic>>[
            <String, dynamic>{
              'kind': 'eq',
              'direction': null,
              'descriptor': 'warmth_boost',
            },
          ],
          'intensity': 0.5,
          'execution_profile': 'producer_safe',
          'audibility': 'noticeable',
          'style_tags': <String>['warm'],
          'reset_fx': false,
          'reference': null,
        });

    test('resource refs and producer ports are strict and typed', () {
      final value = AiV3ResourceRef.fromJson(ref('producer', 'row'));
      expect(value.toJson(), ref('producer', 'row'));
      expect(
        () => AiV3ResourceRef.fromJson(<String, dynamic>{
          ...ref('producer', 'row'),
          'extra': true,
        }),
        throwsFormatException,
      );
      expect(
        aiV3ProducedResources(
          commandType: 'row.create',
          arguments: row('audio', 'audio')['arguments'] as Map<String, dynamic>,
        )['row'],
        AiV3ResourceKind.audioRow,
      );
      expect(
        aiV3ProducedResources(
          commandType: 'row.create',
          arguments: row('midi', 'midi')['arguments'] as Map<String, dynamic>,
        )['row'],
        AiV3ResourceKind.midiRow,
      );
      expect(
        aiV3ProducedResources(
          commandType: 'clip.separate_stems',
          arguments: const <String, dynamic>{'clip_id': 'source'},
        )['instrumental_clip'],
        AiV3ResourceKind.audioClip,
      );
      expect(
        aiV3ProducedResources(
          commandType: 'sample.place',
          arguments: <String, dynamic>{
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          },
        )['audio_clip'],
        AiV3ResourceKind.audioClip,
      );
      expect(
        aiV3ProducedResources(
          commandType: 'sample.place',
          arguments: <String, dynamic>{
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 1},
            ],
          },
        ),
        isEmpty,
      );
      expect(
        aiV3ProducedResources(
          commandType: 'clip.convert_to_midi',
          arguments: const <String, dynamic>{
            'clip_id': 'audio-clip',
            'instrument_id': 'piano',
          },
        ),
        const <String, AiV3ResourceKind>{
          'midi_clip': AiV3ResourceKind.midiClip,
          'midi_row': AiV3ResourceKind.midiRow,
        },
      );
    });

    test('types audio-to-MIDI input and both generated outputs', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('separate', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('convert', 'clip.convert_to_midi', <String, dynamic>{
          'clip_ref': ref('separate', 'instrumental_clip'),
          'instrument_id': 'piano',
        }),
        _command('transpose', 'midi.transpose', <String, dynamic>{
          'clip_ref': ref('convert', 'midi_clip'),
          'semitones': 2,
        }),
        _command('rename', 'row.rename', <String, dynamic>{
          'row_ref': ref('convert', 'midi_row'),
          'new_name': 'Transcribed melody',
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      expect(plan.commands, hasLength(4));
      expect(
        plan.commands[1].arguments['clip_ref'],
        ref('separate', 'instrumental_clip'),
      );
      expect(
        plan.commands[2].arguments['clip_ref'],
        ref('convert', 'midi_clip'),
      );
      expect(plan.commands[3].arguments['row_ref'], ref('convert', 'midi_row'));

      expect(
        () => parse(<Map<String, dynamic>>[
          row('midi-row', 'midi'),
          _command('bad', 'clip.convert_to_midi', <String, dynamic>{
            'clip_ref': ref('midi-row', 'row'),
            'instrument_id': 'piano',
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        throwsA(isA<AiV3ContractException>()),
      );
    });

    test(
      'producer output catalog is registry-derived and pairings stay strict',
      () {
        final catalog = aiV3ProducerOutputPortCatalog(
          AiV3ResourceKind.values.toSet(),
        );
        for (final producer in aiV3PossibleProducerOutputKinds.entries) {
          for (final output in producer.value.keys) {
            expect(catalog, contains('${producer.key} ->'));
            expect(catalog, contains(output));
          }
        }
        expect(catalog, contains('row.create -> row'));
        expect(
          catalog,
          contains('clip.convert_to_midi -> midi_clip, midi_row'),
        );
        expect(
          () => parse(<Map<String, dynamic>>[
            row('create-midi-row', 'midi'),
            _command('mute', 'row.set_muted', <String, dynamic>{
              'row_ref': ref('create-midi-row', 'midi_row'),
              'muted': true,
            }),
          ], consumers: aiV3RuntimeResourceRefConsumerTypes),
          throwsA(
            isA<AiV3ContractException>().having(
              (error) => error.code,
              'code',
              'v3_resource_ref_unavailable',
            ),
          ),
        );
      },
    );

    test('prepares typed audio glue as a consuming many-to-one producer', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 100},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
        _command('copy', 'clip.duplicate_to', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'destination_row_id': null,
          'start_beat': 4,
        }),
        _command('glue', 'clip.glue', <String, dynamic>{
          'sources': <Map<String, dynamic>>[
            <String, dynamic>{'clip_ref': ref('place', 'audio_clip')},
            <String, dynamic>{'clip_ref': ref('copy', 'copy_clip')},
          ],
          'label': 'Combined loop',
        }),
        _command('pitch', 'clip.adjust_pitch_semitones', <String, dynamic>{
          'clip_ref': ref('glue', 'glued_clip'),
          'delta_semitones': 2,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'sample_insert',
        'clip_edit',
        'v3_clip_glue',
        'clip_edit',
      ]);
      expect(prepared.actions[2].data['sources'], <Map<String, dynamic>>[
        <String, dynamic>{'resource_ref': ref('place', 'audio_clip')},
        <String, dynamic>{'resource_ref': ref('copy', 'copy_clip')},
      ]);
      expect(
        (prepared.actions.last.data['target'] as Map)['resource_ref'],
        ref('glue', 'glued_clip'),
      );
    });

    test('generated rows support deferred mix goals and later row actions', () {
      final plan = parse(<Map<String, dynamic>>[
        row('created', 'audio'),
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_ref': ref('created', 'row')},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
        mixRow('mix', <String, dynamic>{
          'scope': 'row',
          'row_ref': ref('created', 'row'),
        }),
        _command('pan', 'row.set_pan', <String, dynamic>{
          'row_ref': ref('created', 'row'),
          'pan_signed': 0.25,
        }),
      ]);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'row_create',
        'sample_insert',
        'v3_deferred_mix_goal',
        'row_mix',
      ]);
      final deferred = prepared.actions[2].data;
      expect(deferred['resource_consumer_type'], 'mix.apply_goal');
      expect(deferred['operation'], 'apply_goal');
      expect(
        ((deferred['target'] as Map)['resource_ref'] as Map)['command_id'],
        'created',
      );
    });

    test(
      'generated groups support deferred mix goals and later group actions',
      () {
        final plan = parse(<Map<String, dynamic>>[
          row('drums', 'audio'),
          row('bass', 'audio'),
          _command('place-drums', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{'row_ref': ref('drums', 'row')},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          }),
          _command('place-bass', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{'row_ref': ref('bass', 'row')},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          }),
          _command('group', 'group.create', <String, dynamic>{
            'members': <Map<String, dynamic>>[
              <String, dynamic>{'row_ref': ref('drums', 'row')},
              <String, dynamic>{'row_ref': ref('bass', 'row')},
            ],
            'name': 'Rhythm',
          }),
          mixRow('mix', <String, dynamic>{
            'scope': 'group',
            'group_ref': ref('group', 'group'),
          }),
          _command('collapse', 'group.set_collapsed', <String, dynamic>{
            'group_ref': ref('group', 'group'),
            'collapsed': true,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);

        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        );
        expect(prepared.actions.map((action) => action.type), <String>[
          'row_create',
          'row_create',
          'sample_insert',
          'sample_insert',
          'v3_group_edit',
          'v3_deferred_mix_goal',
          'v3_group_edit',
        ]);
        expect(
          (prepared.actions[5].data['target'] as Map)['group_resource_ref'],
          ref('group', 'group'),
        );
      },
    );

    test('generated rows defer all-rows mixing after topology changes', () {
      final plan = parse(<Map<String, dynamic>>[
        row('audio', 'audio'),
        row('second-audio', 'audio'),
        mixRow('mix', const <String, dynamic>{'scope': 'all_rows'}),
      ]);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'row_create',
        'row_create',
        'v3_deferred_mix_goal',
      ]);
      expect(prepared.actions.last.data['target'], const <String, dynamic>{
        'scope': 'all_rows',
      });
    });

    test('master mixing defers after prior changes and remains chainable', () {
      final plan = parse(<Map<String, dynamic>>[
        row('audio', 'audio'),
        mixRow('master', const <String, dynamic>{'scope': 'master'}),
        _command('mute', 'row.set_muted', <String, dynamic>{
          'row_ref': ref('audio', 'row'),
          'muted': true,
        }),
      ]);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'row_create',
        'v3_deferred_mix_goal',
        'row_mute',
      ]);
      expect(prepared.actions[1].data['target'], const <String, dynamic>{
        'scope': 'master',
      });
    });

    test(
      'stem row mixing can continue through master mixing and row edits',
      () {
        final plan = parse(<Map<String, dynamic>>[
          _command('stems', 'clip.separate_stems', <String, dynamic>{
            'clip_id': 'audio-clip',
          }),
          mixRow('widen', <String, dynamic>{
            'scope': 'row',
            'row_ref': ref('stems', 'instrumental_row'),
          }),
          mixRow('master', const <String, dynamic>{'scope': 'master'}),
          _command('mute', 'row.set_muted', <String, dynamic>{
            'row_ref': ref('stems', 'vocals_row'),
            'muted': true,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);

        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _contextForStemSeparation(),
        );
        expect(prepared.actions.map((action) => action.type), <String>[
          'v3_clip_separate_stems',
          'v3_deferred_mix_goal',
          'v3_deferred_mix_goal',
          'row_mute',
        ]);
      },
    );

    test('only later sequential master goals are deferred', () {
      final plan = parse(<Map<String, dynamic>>[
        mixRow('first', const <String, dynamic>{'scope': 'master'}),
        mixRow('second', const <String, dynamic>{'scope': 'master'}),
      ]);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'v3_mix_goal',
        'v3_deferred_mix_goal',
      ]);
    });

    test('any earlier executable mutation defers later mix goals', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('gain', 'row.adjust_gain_db', <String, dynamic>{
          'row_id': 100,
          'delta_db': -2,
        }),
        mixRow('row-mix', const <String, dynamic>{
          'scope': 'row',
          'row_id': 100,
        }),
        mixRow('all-mix', const <String, dynamic>{'scope': 'all_rows'}),
      ]);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'row_mix',
        'v3_deferred_mix_goal',
        'v3_deferred_mix_goal',
      ]);
    });

    test('deferred mix goals reject wrong-kind and flag-off references', () {
      final commands = <Map<String, dynamic>>[
        row('first', 'audio'),
        row('second', 'audio'),
        _command('group', 'group.create', <String, dynamic>{
          'name': 'Pair',
          'members': <Map<String, dynamic>>[
            <String, dynamic>{'row_ref': ref('first', 'row')},
            <String, dynamic>{'row_ref': ref('second', 'row')},
          ],
        }),
        mixRow('mix', <String, dynamic>{
          'scope': 'row',
          'row_ref': ref('group', 'group'),
        }),
      ];
      expect(() => parse(commands), throwsA(isA<AiV3ContractException>()));
      expect(
        () => AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            row('created', 'audio'),
            mixRow('mix', <String, dynamic>{
              'scope': 'row',
              'row_ref': ref('created', 'row'),
            }),
          ]),
        ),
        throwsA(isA<AiV3ContractException>()),
      );
    });

    test('typed glue canonicalizes aliases and retires every input', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 100},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
        _command('move', 'clip.move_by_beats', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'delta_beats': 1,
        }),
        _command('copy', 'clip.duplicate_to', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'destination_row_id': null,
          'start_beat': 4,
        }),
        _command('glue', 'clip.glue', <String, dynamic>{
          'sources': <Map<String, dynamic>>[
            <String, dynamic>{'clip_ref': ref('move', 'audio_clip')},
            <String, dynamic>{'clip_ref': ref('copy', 'copy_clip')},
          ],
          'label': null,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);
      final sources = plan.commands.last.arguments['sources'] as List;
      expect((sources.first as Map)['clip_ref'], ref('place', 'audio_clip'));

      for (final unavailable in <Map<String, dynamic>>[
        _command('move-source', 'clip.move_by_beats', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'delta_beats': 1,
        }),
        _command('move-copy', 'clip.move_by_beats', <String, dynamic>{
          'clip_ref': ref('copy', 'copy_clip'),
          'delta_beats': 1,
        }),
      ]) {
        expect(
          () => parse(<Map<String, dynamic>>[
            ...plan.commands.map((command) => command.toJson()),
            unavailable,
          ], consumers: aiV3RuntimeResourceRefConsumerTypes),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('typed glue rejects malformed, duplicate, and wrong-kind sources', () {
      final invalidSources = <List<Map<String, dynamic>>>[
        <Map<String, dynamic>>[
          <String, dynamic>{'clip_ref': ref('place', 'audio_clip')},
        ],
        <Map<String, dynamic>>[
          <String, dynamic>{'clip_ref': ref('place', 'audio_clip')},
          <String, dynamic>{'clip_ref': ref('place', 'audio_clip')},
        ],
        <Map<String, dynamic>>[
          <String, dynamic>{'clip_ref': ref('midi', 'midi_clip')},
          <String, dynamic>{'clip_id': 'audio-clip'},
        ],
      ];
      for (final sources in invalidSources) {
        expect(
          () => parse(<Map<String, dynamic>>[
            _command('place', 'sample.place', <String, dynamic>{
              'destination': <String, dynamic>{'row_id': 100},
              'placements': <Map<String, dynamic>>[
                <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
              ],
            }),
            _command('midi', 'midi.create_clip', <String, dynamic>{
              'destination': <String, dynamic>{'row_id': 200},
              'instrument_id': 'piano',
              'start_beat': 0,
              'length_beats': 4,
              'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
            }),
            _command('glue', 'clip.glue', <String, dynamic>{
              'sources': sources,
              'label': null,
            }),
          ], consumers: aiV3RuntimeResourceRefConsumerTypes),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('prepares generated audio conversion with deferred MIDI notes', () {
      final contextData = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(_contextForStemSeparation().data)) as Map,
      );
      contextData['runtime_capabilities'] = <String>[
        'daw.stem_separate',
        'daw.midi_compose.audio_to_midi',
      ];
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'state-1',
        data: contextData,
      );
      final plan = parse(<Map<String, dynamic>>[
        _command('separate', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('convert', 'clip.convert_to_midi', <String, dynamic>{
          'clip_ref': ref('separate', 'instrumental_clip'),
          'instrument_id': 'piano',
        }),
        _command('transpose', 'midi.transpose', <String, dynamic>{
          'clip_ref': ref('convert', 'midi_clip'),
          'semitones': 2,
        }),
        _command('append', 'midi.append_notes', <String, dynamic>{
          'clip_ref': ref('convert', 'midi_clip'),
          'notes': <Map<String, dynamic>>[_note(72, 0, 0.5)],
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: context,
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'v3_clip_separate_stems',
        'v3_clip_convert_to_midi',
        'midi_compose',
        'midi_compose',
      ]);
      expect(
        (prepared.actions[1].data['target'] as Map)['resource_ref'],
        ref('separate', 'instrumental_clip'),
      );
      expect(prepared.actions[2].data['runtime_authoritative_midi'], isTrue);
      expect(prepared.actions[2].data.containsKey('expected_notes'), isFalse);
      expect(prepared.actions[3].data['runtime_authoritative_midi'], isTrue);
      expect(
        prepared.actions[3].data['deferred_midi_command'],
        'midi.append_notes',
      );
      expect(prepared.actions[3].data.containsKey('notes'), isFalse);
    });

    test('prepares generated audio follow-ups through the shared registry', () {
      final contextData = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(_contextForStemSeparation().data)) as Map,
      );
      contextData['runtime_capabilities'] = <String>['daw.stem_separate'];
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'state-1',
        data: contextData,
      );
      final plan = parse(<Map<String, dynamic>>[
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 100},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
        _command('replace', 'sample.replace', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'asset_id': 'kick-1',
        }),
        _command('trim', 'clip.trim_silence', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'edges': 'both',
          'padding_ms': 8,
        }),
        _command('align', 'clip.align_first_sound', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'destination': <String, dynamic>{'kind': 'nearest_beat'},
        }),
        _command('tempo', 'clip.align_tempo_to_project', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'mode': 'preserve_pitch',
        }),
        _command('separate', 'clip.separate_stems', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
        }),
        _command('pitch', 'clip.adjust_pitch_semitones', <String, dynamic>{
          'clip_ref': ref('separate', 'instrumental_clip'),
          'delta_semitones': 1,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: context,
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'sample_insert',
        'v3_sample_replace',
        'v3_clip_audio_analysis',
        'v3_clip_audio_analysis',
        'v3_clip_audio_analysis',
        'v3_clip_separate_stems',
        'clip_edit',
      ]);
      for (final index in <int>[1, 2, 3, 4, 5]) {
        final action = prepared.actions[index];
        expect(
          (action.data['target'] as Map)['resource_ref'],
          ref('place', 'audio_clip'),
        );
        expect(
          action.data['resource_consumer_type'],
          plan.commands[index].type,
        );
      }
    });

    test('referenced project-tempo detection is terminal and audio-only', () {
      final terminalPlan = parse(<Map<String, dynamic>>[
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 100},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
        _command('tempo', 'project.set_tempo_from_clip', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'mode': 'repitch',
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);
      final prepared = const AiV3CommandPreparer().prepare(
        plan: terminalPlan,
        context: _context(),
      );
      expect(prepared.actions.last.type, 'v3_clip_audio_analysis');
      expect(prepared.actions.last.data['operation'], 'set_tempo_from_clip');

      expect(
        () => parse(<Map<String, dynamic>>[
          ...terminalPlan.commands.map((command) => command.toJson()),
          _command('late', 'project.set_tempo', <String, dynamic>{
            'bpm': 128,
            'time_stretch_audio': false,
            'preserve_pitch': true,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        throwsA(
          isA<AiV3ContractException>().having(
            (error) => error.code,
            'code',
            'v3_runtime_tempo_command_must_be_final',
          ),
        ),
      );
      expect(
        () => parse(<Map<String, dynamic>>[
          _command('midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 200},
            'instrument_id': 'piano',
            'start_beat': 0,
            'length_beats': 4,
            'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
          }),
          _command('bad', 'clip.trim_silence', <String, dynamic>{
            'clip_ref': ref('midi', 'midi_clip'),
            'edges': 'both',
            'padding_ms': 0,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        throwsA(isA<AiV3ContractException>()),
      );
    });

    test('composes conversion through duplicate and split producers', () {
      final contextData = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(_contextForStemSeparation().data)) as Map,
      );
      contextData['runtime_capabilities'] = <String>[
        'daw.stem_separate',
        'daw.midi_compose.audio_to_midi',
      ];
      final plan = parse(<Map<String, dynamic>>[
        _command('separate', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('convert', 'clip.convert_to_midi', <String, dynamic>{
          'clip_ref': ref('separate', 'instrumental_clip'),
          'instrument_id': 'piano',
        }),
        _command('duplicate', 'clip.duplicate_to', <String, dynamic>{
          'clip_ref': ref('convert', 'midi_clip'),
          'destination_row_id': null,
          'start_beat': 8,
        }),
        _command('split', 'clip.split_at', <String, dynamic>{
          'clip_ref': ref('duplicate', 'copy_clip'),
          'at_beat': 10,
        }),
        _command('transpose', 'midi.transpose', <String, dynamic>{
          'clip_ref': ref('split', 'right_clip'),
          'semitones': 12,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'state-1',
          data: contextData,
        ),
      );
      expect(prepared.actions, hasLength(5));
      expect(
        (prepared.actions[4].data['target'] as Map)['resource_ref'],
        ref('split', 'right_clip'),
      );
      expect(prepared.actions[4].data['runtime_authoritative_midi'], isTrue);
      expect(prepared.actions[4].data.containsKey('expected_notes'), isFalse);
    });

    test('carries unknown sample and edited MIDI bounds to runtime', () {
      final contextData = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(_context().data)) as Map,
      );
      contextData['runtime_capabilities'] = <String>[
        'daw.midi_compose.audio_to_midi',
      ];
      final plan = parse(<Map<String, dynamic>>[
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 100},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
        _command('convert', 'clip.convert_to_midi', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'instrument_id': 'piano',
        }),
        _command('append', 'midi.append_notes', <String, dynamic>{
          'clip_ref': ref('convert', 'midi_clip'),
          'notes': <Map<String, dynamic>>[_note(72, 0, 1)],
        }),
        _command('duplicate', 'clip.duplicate_to', <String, dynamic>{
          'clip_ref': ref('convert', 'midi_clip'),
          'destination_row_id': null,
          'start_beat': 8,
        }),
        _command('split', 'clip.split_at', <String, dynamic>{
          'clip_ref': ref('duplicate', 'copy_clip'),
          'at_beat': 10,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'state-1',
          data: contextData,
        ),
      );

      expect(prepared.actions, hasLength(5));
      expect(prepared.actions[1].data.containsKey('duration_ms'), isFalse);
      expect(prepared.actions[2].data['runtime_authoritative_midi'], isTrue);
      expect(
        prepared.actions[2].data['deferred_midi_command'],
        'midi.append_notes',
      );
      expect(
        prepared.actions[3].data.containsKey('predicted_input_end_ms'),
        isFalse,
      );
      expect(
        prepared.actions[4].data.containsKey('predicted_input_end_ms'),
        isFalse,
      );
    });

    test('deleting converted MIDI row retires its generated clip', () {
      expect(
        () => parse(<Map<String, dynamic>>[
          _command('convert', 'clip.convert_to_midi', <String, dynamic>{
            'clip_id': 'audio-clip',
            'instrument_id': 'piano',
          }),
          _command('delete-row', 'row.delete', <String, dynamic>{
            'row_ref': ref('convert', 'midi_row'),
          }),
          _command('transpose', 'midi.transpose', <String, dynamic>{
            'clip_ref': ref('convert', 'midi_clip'),
            'semitones': 2,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        throwsA(isA<AiV3ContractException>()),
      );
    });

    test('accepts audio, MIDI, row, and independent dependency chains', () {
      final stems = parse(<Map<String, dynamic>>[
        _command('tempo', 'project.set_tempo', <String, dynamic>{
          'bpm': 110,
          'time_stretch_audio': false,
          'preserve_pitch': true,
        }),
        _command('separate', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'source',
        }),
        _command('pitch', 'clip.adjust_pitch_semitones', <String, dynamic>{
          'clip_ref': ref('separate', 'instrumental_clip'),
          'delta_semitones': -1,
        }),
      ]);
      final midi = parse(<Map<String, dynamic>>[
        row('create-row', 'midi'),
        _command('create-clip', 'midi.create_clip', <String, dynamic>{
          'destination': <String, dynamic>{'row_ref': ref('create-row', 'row')},
          'start_beat': 0,
          'length_beats': 4,
          'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
        }),
        _command('transpose', 'midi.transpose', <String, dynamic>{
          'clip_ref': ref('create-clip', 'midi_clip'),
          'semitones': 1,
        }),
      ]);
      final sample = parse(<Map<String, dynamic>>[
        row('audio-row', 'audio'),
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_ref': ref('audio-row', 'row')},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick', 'start_beat': 0},
          ],
        }),
      ]);
      expect(stems.commands, hasLength(3));
      expect(midi.commands, hasLength(3));
      expect(sample.commands, hasLength(2));
    });

    test(
      'canonicalizes safe aliases through identity-preserving consumers',
      () {
        final audio = parse(<Map<String, dynamic>>[
          row('audio-row', 'audio'),
          _command('place', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{
              'row_ref': ref('audio-row', 'row'),
            },
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'loop', 'start_beat': 0},
            ],
          }),
          _command('move', 'clip.move_by_beats', <String, dynamic>{
            'clip_ref': ref('place', 'audio_clip'),
            'delta_beats': 2,
          }),
          _command('trim', 'clip.trim_to_range', <String, dynamic>{
            'clip_ref': ref('move', 'audio_clip'),
            'start_beat': 2,
            'end_beat': 6,
          }),
          _command('pitch', 'clip.adjust_pitch_semitones', <String, dynamic>{
            'clip_ref': ref('trim', 'audio_clip'),
            'delta_semitones': -1,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);
        expect(
          audio.commands[3].arguments['clip_ref'],
          ref('place', 'audio_clip'),
        );
        expect(
          audio.commands[4].arguments['clip_ref'],
          ref('place', 'audio_clip'),
        );

        final generatedRow = parse(<Map<String, dynamic>>[
          row('create-row', 'audio'),
          _command('rename', 'row.rename', <String, dynamic>{
            'row_ref': ref('create-row', 'row'),
            'new_name': 'Percussion',
          }),
          _command('mute', 'row.set_muted', <String, dynamic>{
            'row_ref': ref('rename', 'row'),
            'muted': true,
          }),
          _command('place', 'sample.place', <String, dynamic>{
            'destination': const <String, dynamic>{
              'row_ref': <String, dynamic>{
                'command_id': 'rename',
                'output': 'row',
              },
            },
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick', 'start_beat': 0},
            ],
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);
        expect(
          generatedRow.commands[2].arguments['row_ref'],
          ref('create-row', 'row'),
        );
        expect(
          (generatedRow.commands.last.arguments['destination']
              as Map)['row_ref'],
          ref('create-row', 'row'),
        );

        final midi = parse(<Map<String, dynamic>>[
          row('midi-row', 'midi'),
          _command('create-midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{'row_ref': ref('midi-row', 'row')},
            'start_beat': 0,
            'length_beats': 4,
            'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
          }),
          _command('transpose', 'midi.transpose', <String, dynamic>{
            'clip_ref': ref('create-midi', 'midi_clip'),
            'semitones': 2,
          }),
          _command('append', 'midi.append_notes', <String, dynamic>{
            'clip_ref': ref('transpose', 'midi_clip'),
            'notes': <Map<String, dynamic>>[_note(64, 0, 1)],
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);
        expect(
          midi.commands.last.arguments['clip_ref'],
          ref('create-midi', 'midi_clip'),
        );
      },
    );

    test('does not canonicalize unsafe or ambiguous resource aliases', () {
      final invalidPlans = <List<Map<String, dynamic>>>[
        <Map<String, dynamic>>[
          _command('move-stable', 'clip.move_by_beats', <String, dynamic>{
            'clip_id': 'audio-clip',
            'delta_beats': 1,
          }),
          _command('pitch', 'clip.adjust_pitch_semitones', <String, dynamic>{
            'clip_ref': ref('move-stable', 'audio_clip'),
            'delta_semitones': 1,
          }),
        ],
        <Map<String, dynamic>>[
          _command('place', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 100},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'loop', 'start_beat': 0},
            ],
          }),
          _command('move', 'clip.move_by_beats', <String, dynamic>{
            'clip_ref': ref('place', 'audio_clip'),
            'delta_beats': 1,
          }),
          _command('pitch', 'clip.adjust_pitch_semitones', <String, dynamic>{
            'clip_ref': ref('move', 'wrong_output'),
            'delta_semitones': 1,
          }),
        ],
        <Map<String, dynamic>>[
          _command('place', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 100},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'loop', 'start_beat': 0},
            ],
          }),
          _command('delete', 'clip.delete', <String, dynamic>{
            'clip_ref': ref('place', 'audio_clip'),
          }),
          _command('move', 'clip.move_by_beats', <String, dynamic>{
            'clip_ref': ref('delete', 'audio_clip'),
            'delta_beats': 1,
          }),
        ],
      ];
      for (final commands in invalidPlans) {
        expect(
          () => parse(commands, consumers: aiV3RuntimeResourceRefConsumerTypes),
          throwsA(
            isA<AiV3ContractException>().having(
              (error) => error.code,
              'code',
              'v3_resource_ref_unavailable',
            ),
          ),
        );
      }
    });

    test('canonical MIDI ordering is semantic and preserves duplicates', () {
      final ordered = aiV3CanonicalMidiNotes(<Map<String, dynamic>>[
        _note(67, 2, 1),
        _note(64, 0, 2),
        _note(60, 0, 1),
        _note(60, 0, 1),
      ]);
      expect(ordered.map((note) => note['pitch']), <int>[60, 60, 64, 67]);
      expect(ordered, hasLength(4));
    });

    test(
      'prepares a generated audio row through configuration and placement',
      () {
        final plan = parse(<Map<String, dynamic>>[
          row('create-row', 'audio'),
          _command('rename', 'row.rename', <String, dynamic>{
            'row_ref': ref('create-row', 'row'),
            'new_name': 'Percussion',
          }),
          _command('gain', 'row.adjust_gain_db', <String, dynamic>{
            'row_ref': ref('create-row', 'row'),
            'delta_db': -3,
          }),
          _command('pan', 'row.set_pan', <String, dynamic>{
            'row_ref': ref('create-row', 'row'),
            'pan_signed': 0.25,
          }),
          _command('mute', 'row.set_muted', <String, dynamic>{
            'row_ref': ref('create-row', 'row'),
            'muted': true,
          }),
          _command('solo', 'row.set_soloed', <String, dynamic>{
            'row_ref': ref('create-row', 'row'),
            'soloed': true,
          }),
          _command('place', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{
              'row_ref': ref('create-row', 'row'),
            },
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 4},
            ],
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);

        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        );
        expect(prepared.actions.map((action) => action.type), <String>[
          'row_create',
          'row_rename',
          'row_mix',
          'row_mix',
          'row_mute',
          'row_solo',
          'sample_insert',
        ]);
        expect(prepared.actions.first.data['command_id'], 'create-row');
        expect(prepared.actions[2].data['expected_gain_db'], -3.0);
        expect(prepared.actions[3].data['expected_pan_signed'], 0.25);
        expect(
          (prepared.actions.last.data['target'] as Map)['resource_ref'],
          ref('create-row', 'row'),
        );
        expect(
          jsonEncode(prepared.actions),
          isNot(anyOf(contains('label_contains'), contains('row_index":null'))),
        );
      },
    );

    test('prepared references conform to the consumer registry', () {
      final plan = parse(<Map<String, dynamic>>[
        row('create-row', 'audio'),
        _command('mute', 'row.set_muted', <String, dynamic>{
          'row_ref': ref('create-row', 'row'),
          'muted': true,
        }),
        _command('unmute', 'row.set_muted', <String, dynamic>{
          'row_ref': ref('create-row', 'row'),
          'muted': false,
        }),
        _command('solo', 'row.set_soloed', <String, dynamic>{
          'row_ref': ref('create-row', 'row'),
          'soloed': true,
        }),
        _command('unsolo', 'row.set_soloed', <String, dynamic>{
          'row_ref': ref('create-row', 'row'),
          'soloed': false,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      final referencedActions = prepared.actions
          .where((action) => action.data['resource_consumer_type'] is String)
          .toList(growable: false);
      expect(referencedActions, hasLength(4));
      for (final action in referencedActions) {
        final consumerType = action.data['resource_consumer_type'] as String;
        final spec = aiV3ResourceConsumerSpecs[consumerType];
        expect(spec, isNotNull);
        expect(action.type, spec!.actionType);
        expect(action.data['operation'], spec.operation);
      }
      expect(
        referencedActions.map((action) => action.data['muted']),
        containsAll(<bool>[true, false]),
      );
      expect(
        referencedActions.map((action) => action.data['soloed']),
        containsAll(<bool>[true, false]),
      );
    });

    test('generated rows support effects and built-in automation targets', () {
      final plan = parse(<Map<String, dynamic>>[
        row('create-row', 'audio'),
        _command('tempo', 'project.set_tempo', <String, dynamic>{
          'bpm': 60,
          'time_stretch_audio': false,
          'preserve_pitch': true,
        }),
        _command('effect', 'effect.ensure_configured', <String, dynamic>{
          'row_ref': ref('create-row', 'row'),
          'effect_id': 'Reverb',
          'parameters': const <Map<String, dynamic>>[],
        }),
        _command('fade', 'automation.gain_fade', <String, dynamic>{
          'row_ref': ref('create-row', 'row'),
          'start_beat': 0,
          'end_beat': 4,
          'from_gain_db': -12,
          'to_level': 'current',
        }),
        _command('pan', 'automation.set_points', <String, dynamic>{
          'row_ref': ref('create-row', 'row'),
          'automation_target_id': 'mix:pan',
          'points': <Map<String, dynamic>>[
            <String, dynamic>{'beat': 0, 'value_normalized': 0.25},
            <String, dynamic>{'beat': 2, 'value_normalized': 0.75},
          ],
        }),
        _command('clear', 'automation.clear', <String, dynamic>{
          'row_ref': ref('create-row', 'row'),
          'automation_target_id': 'mix:gain',
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      final referenced = prepared.actions
          .where((action) => action.data['resource_consumer_type'] != null)
          .toList(growable: false);
      expect(
        referenced.map((action) => action.data['resource_consumer_type']),
        <String>[
          'effect.ensure_configured',
          'automation.gain_fade',
          'automation.set_points',
          'automation.clear',
        ],
      );
      for (final action in referenced) {
        final consumer = action.data['resource_consumer_type'] as String;
        final spec = aiV3ResourceConsumerSpecs[consumer]!;
        expect(action.type, spec.actionType);
        expect(action.data['operation'], spec.operation);
        expect(
          (action.data['target'] as Map)['resource_ref'],
          ref('create-row', 'row'),
        );
      }
      expect(referenced[1].data['points'], <Map<String, dynamic>>[
        <String, dynamic>{
          'time_ms': 0.0,
          'value': closeTo(0.251188643150958, 0.0000001),
        },
        <String, dynamic>{'time_ms': 4000.0, 'value': 1.0},
      ]);
      expect(referenced[2].data['points'], <Map<String, dynamic>>[
        <String, dynamic>{'time_ms': 0.0, 'value': 0.25},
        <String, dynamic>{'time_ms': 2000.0, 'value': 0.75},
      ]);
      expect(
        prepared.receipts.map((receipt) => receipt['verified_label']),
        <String>[
          'Created audio row Audio',
          'Set project tempo to 60 BPM',
          'Set up Reverb on Audio',
          'Added gain fade on Audio',
          'Set 2 automation points on Audio',
          'Cleared automation on Audio',
        ],
      );
      expect(
        prepared.receipts.map((receipt) => receipt['verified_l10n_key']),
        <String>[
          'Created audio row {name}.',
          'Set project tempo to {value} BPM.',
          'Set up {effect} on {target}.',
          'Added a gain fade on {target}.',
          'Set {count} automation points on {target}.',
          'Cleared automation on {target}.',
        ],
      );
      expect(prepared.receipts[2]['verified_l10n_args'], <String, String>{
        'effect': 'Reverb',
        'target': 'Audio',
      });
    });

    test('generated rows form a typed group that can be collapsed', () {
      final plan = parse(<Map<String, dynamic>>[
        row('audio-row', 'audio'),
        _command('midi-row', 'row.create', <String, dynamic>{
          'name': 'Synth',
          'lane': <String, dynamic>{'kind': 'midi', 'instrument_id': 'piano'},
          'position': <String, dynamic>{'kind': 'end'},
        }),
        _command('group', 'group.create', <String, dynamic>{
          'members': <Map<String, dynamic>>[
            <String, dynamic>{'row_ref': ref('audio-row', 'row')},
            <String, dynamic>{'row_ref': ref('midi-row', 'row')},
          ],
          'name': 'Band',
        }),
        _command('collapse', 'group.set_collapsed', <String, dynamic>{
          'group_ref': ref('group', 'group'),
          'collapsed': true,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'row_create',
        'row_create',
        'v3_group_edit',
        'v3_group_edit',
      ]);
      expect(prepared.actions[0].data['command_id'], 'audio-row');
      expect(prepared.actions[1].data['command_id'], 'midi-row');
      final create = prepared.actions[2].data;
      expect(create['command_id'], 'group');
      expect(create['member_targets'], hasLength(2));
      expect(create['row_ids'], isNull);
      final collapse = prepared.actions[3].data;
      expect(collapse['resource_consumer_type'], 'group.set_collapsed');
      expect(
        (collapse['target'] as Map)['resource_ref'],
        ref('group', 'group'),
      );
    });

    test('group-only row references retain every producer command id', () {
      final plan = parse(<Map<String, dynamic>>[
        row('first', 'audio'),
        row('second', 'audio'),
        row('third', 'audio'),
        _command('group', 'group.create', <String, dynamic>{
          'members': <Map<String, dynamic>>[
            <String, dynamic>{'row_ref': ref('first', 'row')},
            <String, dynamic>{'row_ref': ref('second', 'row')},
            <String, dynamic>{'row_ref': ref('third', 'row')},
          ],
          'name': 'Layers',
        }),
        _command('remove', 'group.remove_row', <String, dynamic>{
          'group_ref': ref('group', 'group'),
          'row_ref': ref('second', 'row'),
        }),
        _command('collapse', 'group.set_collapsed', <String, dynamic>{
          'group_ref': ref('group', 'group'),
          'collapsed': true,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(
        prepared.actions.take(3).map((action) => action.data['command_id']),
        <String>['first', 'second', 'third'],
      );
    });

    test('stable and generated rows can form one typed group', () {
      final plan = parse(<Map<String, dynamic>>[
        row('generated-row', 'audio'),
        _command('group', 'group.create', <String, dynamic>{
          'members': <Map<String, dynamic>>[
            <String, dynamic>{'row_id': 100},
            <String, dynamic>{'row_ref': ref('generated-row', 'row')},
          ],
          'name': 'Mixed',
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      final create = prepared.actions.last.data;
      final targets = (create['member_targets'] as List).cast<Map>();
      expect(targets, hasLength(2));
      expect(targets.first['row_id'], 100);
      expect(targets.last['resource_ref'], ref('generated-row', 'row'));
    });

    test('dissolved generated groups become unavailable', () {
      expect(
        () => parse(<Map<String, dynamic>>[
          row('first', 'audio'),
          row('second', 'audio'),
          _command('group', 'group.create', <String, dynamic>{
            'members': <Map<String, dynamic>>[
              <String, dynamic>{'row_ref': ref('first', 'row')},
              <String, dynamic>{'row_ref': ref('second', 'row')},
            ],
            'name': 'Pair',
          }),
          _command('remove', 'group.remove_row', <String, dynamic>{
            'group_ref': ref('group', 'group'),
            'row_ref': ref('first', 'row'),
          }),
          _command('collapse', 'group.set_collapsed', <String, dynamic>{
            'group_ref': ref('group', 'group'),
            'collapsed': true,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        throwsA(
          isA<AiV3ContractException>().having(
            (error) => error.code,
            'code',
            'v3_resource_ref_unavailable',
          ),
        ),
      );
    });

    test('deleting a member retires a two-row generated group', () {
      expect(
        () => parse(<Map<String, dynamic>>[
          row('first', 'audio'),
          row('second', 'audio'),
          _command('group', 'group.create', <String, dynamic>{
            'members': <Map<String, dynamic>>[
              <String, dynamic>{'row_ref': ref('first', 'row')},
              <String, dynamic>{'row_ref': ref('second', 'row')},
            ],
            'name': 'Pair',
          }),
          _command('delete', 'row.delete', <String, dynamic>{
            'row_ref': ref('first', 'row'),
          }),
          _command('collapse', 'group.set_collapsed', <String, dynamic>{
            'group_ref': ref('group', 'group'),
            'collapsed': true,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        throwsA(
          isA<AiV3ContractException>().having(
            (error) => error.code,
            'code',
            'v3_resource_ref_unavailable',
          ),
        ),
      );
    });

    test('generated rows reject non-built-in automation targets', () {
      final plan = parse(<Map<String, dynamic>>[
        row('create-row', 'audio'),
        _command('effect-lane', 'automation.set_points', <String, dynamic>{
          'row_ref': ref('create-row', 'row'),
          'automation_target_id': 'fx:reverb:mix',
          'points': <Map<String, dynamic>>[
            <String, dynamic>{'beat': 0, 'value_normalized': 0.5},
          ],
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_automation_target_unknown',
          ),
        ),
      );
    });

    test('generated stem rows use the same compatible row consumer path', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('stems', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('rename', 'row.rename', <String, dynamic>{
          'row_ref': ref('stems', 'vocals_row'),
          'new_name': 'Lead Vocal',
        }),
        _command('gain', 'row.set_gain_db', <String, dynamic>{
          'row_ref': ref('stems', 'instrumental_row'),
          'gain_db': -2,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextForStemSeparation(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'v3_clip_separate_stems',
        'row_rename',
        'row_mix',
      ]);
      expect(
        (prepared.actions[1].data['target'] as Map)['resource_ref'],
        ref('stems', 'vocals_row'),
      );
      expect(prepared.actions[2].data['expected_gain_db'], -2.0);
    });

    test('generated stem rows can form a typed group', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('stems', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('group', 'group.create', <String, dynamic>{
          'members': <Map<String, dynamic>>[
            <String, dynamic>{'row_ref': ref('stems', 'vocals_row')},
            <String, dynamic>{'row_ref': ref('stems', 'instrumental_row')},
          ],
          'name': 'Stems',
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextForStemSeparation(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'v3_clip_separate_stems',
        'v3_group_edit',
      ]);
      expect(prepared.actions.last.data['member_targets'], hasLength(2));
    });

    test('converted MIDI rows enter the generated row order for grouping', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('convert', 'clip.convert_to_midi', <String, dynamic>{
          'clip_id': 'audio-clip',
          'instrument_id': 'piano',
        }),
        _command('group', 'group.create', <String, dynamic>{
          'members': <Map<String, dynamic>>[
            <String, dynamic>{'row_id': 100},
            <String, dynamic>{'row_ref': ref('convert', 'midi_row')},
          ],
          'name': 'Audio and MIDI',
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextForAudioToMidi(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'v3_clip_convert_to_midi',
        'v3_group_edit',
      ]);
      expect(prepared.actions.last.data['member_targets'], hasLength(2));
    });

    test('generated stem row deletion bypasses only the typed target', () {
      final typedPlan = parse(<Map<String, dynamic>>[
        _command('stems', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('delete-vocals', 'row.delete', <String, dynamic>{
          'row_ref': ref('stems', 'vocals_row'),
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);
      final prepared = const AiV3CommandPreparer().prepare(
        plan: typedPlan,
        context: _contextForStemSeparation(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'v3_clip_separate_stems',
        'row_delete',
      ]);
      expect(
        (prepared.actions.last.data['target'] as Map)['resource_ref'],
        ref('stems', 'vocals_row'),
      );

      final stablePlan = parse(<Map<String, dynamic>>[
        _command('stems', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('delete-existing', 'row.delete', <String, dynamic>{
          'row_id': 10,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: stablePlan,
          context: _contextForStemSeparation(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_row_id_unknown',
          ),
        ),
      );
    });

    test('row deletion retires the row and every generated child resource', () {
      final prefix = <Map<String, dynamic>>[
        row('create-row', 'audio'),
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_ref': ref('create-row', 'row')},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
        _command('delete-row', 'row.delete', <String, dynamic>{
          'row_ref': ref('create-row', 'row'),
        }),
      ];
      for (final later in <Map<String, dynamic>>[
        _command('rename-late', 'row.rename', <String, dynamic>{
          'row_ref': ref('create-row', 'row'),
          'new_name': 'Unavailable',
        }),
        _command('move-child', 'clip.move_by_beats', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'delta_beats': 1,
        }),
      ]) {
        expect(
          () => parse(<Map<String, dynamic>>[
            ...prefix,
            later,
          ], consumers: aiV3RuntimeResourceRefConsumerTypes),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('stable row deletion retires generated clips placed on that row', () {
      expect(
        () => parse(<Map<String, dynamic>>[
          _command('place', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 100},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          }),
          _command('delete-row', 'row.delete', <String, dynamic>{
            'row_id': 100,
          }),
          _command('move-child', 'clip.move_by_beats', <String, dynamic>{
            'clip_ref': ref('place', 'audio_clip'),
            'delta_beats': 1,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        throwsA(
          isA<AiV3ContractException>().having(
            (error) => error.code,
            'code',
            'v3_resource_ref_unavailable',
          ),
        ),
      );
    });

    test(
      'copy on another row survives deletion of its generated source row',
      () {
        final plan = parse(<Map<String, dynamic>>[
          row('temporary-row', 'audio'),
          _command('place', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{
              'row_ref': ref('temporary-row', 'row'),
            },
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          }),
          _command('copy-away', 'clip.duplicate_to', <String, dynamic>{
            'clip_ref': ref('place', 'audio_clip'),
            'destination_row_id': 100,
            'start_beat': 4,
          }),
          _command('delete-source-row', 'row.delete', <String, dynamic>{
            'row_ref': ref('temporary-row', 'row'),
          }),
          _command(
            'pitch-copy',
            'clip.adjust_pitch_semitones',
            <String, dynamic>{
              'clip_ref': ref('copy-away', 'copy_clip'),
              'delta_semitones': 2,
            },
          ),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);

        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        );
        expect(prepared.actions.map((action) => action.type), <String>[
          'row_create',
          'sample_insert',
          'clip_edit',
          'row_delete',
          'clip_edit',
        ]);
      },
    );

    test(
      'stable row deletion retires copies explicitly placed on that row',
      () {
        expect(
          () => parse(<Map<String, dynamic>>[
            _command('copy', 'clip.duplicate_to', <String, dynamic>{
              'clip_id': 'audio-clip',
              'destination_row_id': 100,
              'start_beat': 10,
            }),
            _command('delete-row', 'row.delete', <String, dynamic>{
              'row_id': 100,
            }),
            _command('move-copy', 'clip.move_by_beats', <String, dynamic>{
              'clip_ref': ref('copy', 'copy_clip'),
              'delta_beats': 1,
            }),
          ], consumers: aiV3RuntimeResourceRefConsumerTypes),
          throwsA(
            isA<AiV3ContractException>().having(
              (error) => error.code,
              'code',
              'v3_resource_ref_unavailable',
            ),
          ),
        );
      },
    );

    test('rejects invalid ordering, ports, types, and dual targets', () {
      final invalidPlans = <List<Map<String, dynamic>>>[
        <Map<String, dynamic>>[
          _command('pitch', 'clip.set_pitch_semitones', <String, dynamic>{
            'clip_ref': ref('separate', 'instrumental_clip'),
            'pitch_semitones': -1,
          }),
          _command('separate', 'clip.separate_stems', <String, dynamic>{
            'clip_id': 'source',
          }),
        ],
        <Map<String, dynamic>>[
          _command('separate', 'clip.separate_stems', <String, dynamic>{
            'clip_id': 'source',
          }),
          _command('pitch', 'clip.set_pitch_semitones', <String, dynamic>{
            'clip_ref': ref('separate', 'unknown'),
            'pitch_semitones': -1,
          }),
        ],
        <Map<String, dynamic>>[
          row('audio-row', 'audio'),
          _command('clip', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{
              'row_ref': ref('audio-row', 'row'),
            },
            'start_beat': 0,
            'length_beats': 4,
            'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
          }),
        ],
        <Map<String, dynamic>>[
          _command('separate', 'clip.separate_stems', <String, dynamic>{
            'clip_id': 'source',
          }),
          _command('pitch', 'clip.set_pitch_semitones', <String, dynamic>{
            'clip_id': 'existing',
            'clip_ref': ref('separate', 'instrumental_clip'),
            'pitch_semitones': -1,
          }),
        ],
      ];
      for (final commands in invalidPlans) {
        expect(() => parse(commands), throwsA(isA<AiV3ContractException>()));
      }
      expect(
        () => parse(<Map<String, dynamic>>[
          row('same', 'audio'),
          row('same', 'midi'),
        ]),
        throwsA(isA<AiV3ContractException>()),
      );
    });

    test(
      'references are opt-in and runtime schema exposes supported consumers',
      () {
        final raw = _plan(<Map<String, dynamic>>[
          _command('separate', 'clip.separate_stems', <String, dynamic>{
            'clip_id': 'source',
          }),
          _command('pitch', 'clip.set_pitch_semitones', <String, dynamic>{
            'clip_ref': ref('separate', 'instrumental_clip'),
            'pitch_semitones': -1,
          }),
        ]);
        expect(
          () => AiV3Plan.fromJson(raw),
          throwsA(isA<AiV3ContractException>()),
        );
        expect(
          parse(<Map<String, dynamic>>[
            _command('separate', 'clip.separate_stems', <String, dynamic>{
              'clip_id': 'source',
            }),
            _command('delete', 'clip.delete', <String, dynamic>{
              'clip_ref': ref('separate', 'vocals_clip'),
            }),
          ], consumers: aiV3RuntimeResourceRefConsumerTypes).commands,
          hasLength(2),
        );
      },
    );

    test('supports generated clip move and terminal delete lifecycles', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 100},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 1},
          ],
        }),
        _command('pitch', 'clip.adjust_pitch_semitones', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'delta_semitones': 2,
        }),
        _command('move', 'clip.move_by_beats', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'delta_beats': 2,
        }),
        _command('delete', 'clip.delete', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'sample_insert',
        'clip_edit',
        'clip_edit',
        'clip_edit',
      ]);
      expect(prepared.actions.first.data['command_id'], 'place');
      expect(prepared.actions[2].data['predicted_start_ms'], 1500.0);
      expect(
        (prepared.actions[2].data['target'] as Map)['resource_ref'],
        ref('place', 'audio_clip'),
      );
      expect(
        jsonEncode(prepared.actions),
        isNot(anyOf(contains('label_contains'), contains('clip_index'))),
      );
    });

    test('composes generated audio timing before later producers', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 100},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
        _command('source-tempo', 'clip.set_source_tempo_bpm', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'source_tempo_bpm': 100,
        }),
        _command('follow', 'clip.set_tempo_follow_mode', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'mode': 'preserve_pitch',
        }),
        _command(
          'set-length',
          'clip.set_timeline_length_beats',
          <String, dynamic>{
            'clip_ref': ref('place', 'audio_clip'),
            'length_beats': 4,
            'preserve_pitch': true,
          },
        ),
        _command('scale', 'clip.scale_timeline_length', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'factor': 0.5,
          'preserve_pitch': false,
        }),
        _command('copy', 'clip.duplicate_to', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'destination_row_id': null,
          'start_beat': 8,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions, hasLength(6));
      for (final action in prepared.actions.skip(1).take(4)) {
        expect(action.data['runtime_authoritative_audio_timing'], isTrue);
        expect(
          (action.data['target'] as Map)['resource_ref'],
          ref('place', 'audio_clip'),
        );
      }
      expect(prepared.actions[3].data['requested_length_beats'], 4.0);
      expect(prepared.actions[4].data['requested_length_factor'], 0.5);
      expect(prepared.actions.last.data['command_id'], 'copy');
      expect(
        prepared.actions.last.data['resource_consumer_type'],
        'clip.duplicate_to',
      );
    });

    test(
      'supports derived audio split outputs through independent lifecycles',
      () {
        final plan = parse(<Map<String, dynamic>>[
          _command('place', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 100},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          }),
          _command('split', 'clip.split_at', <String, dynamic>{
            'clip_ref': ref('place', 'audio_clip'),
            'at_beat': 2,
          }),
          _command(
            'pitch-left',
            'clip.adjust_pitch_semitones',
            <String, dynamic>{
              'clip_ref': ref('split', 'left_clip'),
              'delta_semitones': 2,
            },
          ),
          _command('move-right', 'clip.move_by_beats', <String, dynamic>{
            'clip_ref': ref('split', 'right_clip'),
            'delta_beats': 1,
          }),
          _command('delete-right', 'clip.delete', <String, dynamic>{
            'clip_ref': ref('split', 'right_clip'),
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);

        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        );
        expect(prepared.actions.map((action) => action.type), <String>[
          'sample_insert',
          'clip_edit',
          'clip_edit',
          'clip_edit',
          'clip_edit',
        ]);
        expect(prepared.actions[1].data['command_id'], 'split');
        expect(prepared.actions[1].data['cut_ms'], 1000.0);
        expect(
          (prepared.actions[1].data['target'] as Map)['resource_ref'],
          ref('place', 'audio_clip'),
        );
        expect(prepared.actions[3].data['predicted_start_ms'], 1500.0);
        expect(
          jsonEncode(prepared.actions),
          isNot(anyOf(contains('label_contains'), contains('clip_index'))),
        );
      },
    );

    test('predicts exact MIDI split outputs and dependent edits', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('midi', 'midi.create_clip', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 200},
          'start_beat': 0,
          'length_beats': 4,
          'notes': <Map<String, dynamic>>[_note(60, 0, 1), _note(64, 2, 1)],
        }),
        _command('split', 'clip.split_at', <String, dynamic>{
          'clip_ref': ref('midi', 'midi_clip'),
          'at_beat': 2,
        }),
        _command('transpose-right', 'midi.transpose', <String, dynamic>{
          'clip_ref': ref('split', 'right_clip'),
          'semitones': 2,
        }),
        _command('move-left', 'clip.move_by_beats', <String, dynamic>{
          'clip_ref': ref('split', 'left_clip'),
          'delta_beats': 1,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'midi_compose',
        'clip_edit',
        'midi_compose',
        'clip_edit',
      ]);
      expect(prepared.actions[1].data['predicted_input_start_ms'], 0.0);
      expect(prepared.actions[1].data['predicted_input_end_ms'], 2000.0);
      expect(prepared.actions[3].data['predicted_start_ms'], 500.0);
      final notes = (prepared.actions[2].data['expected_notes'] as List)
          .cast<Map>();
      expect(notes.map((note) => note['pitch']), <int>[62, 66]);
    });

    test('composes tempo changes before and after a generated MIDI split', () {
      Map<String, dynamic> createMidi() =>
          _command('midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 200},
            'start_beat': 0,
            'length_beats': 4,
            'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
          });
      Map<String, dynamic> splitMidi() => _command(
        'split',
        'clip.split_at',
        <String, dynamic>{'clip_ref': ref('midi', 'midi_clip'), 'at_beat': 2},
      );
      final tempo = _command('tempo', 'project.set_tempo', <String, dynamic>{
        'bpm': 100,
        'time_stretch_audio': false,
        'preserve_pitch': true,
      });

      final tempoFirst = const AiV3CommandPreparer().prepare(
        plan: parse(<Map<String, dynamic>>[
          tempo,
          createMidi(),
          splitMidi(),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        context: _context(),
      );
      expect(tempoFirst.actions[2].data['cut_ms'], 1200.0);
      expect(tempoFirst.actions[2].data['predicted_input_end_ms'], 2400.0);

      final tempoAfter = const AiV3CommandPreparer().prepare(
        plan: parse(<Map<String, dynamic>>[
          createMidi(),
          splitMidi(),
          tempo,
          _command('move-right', 'clip.move_by_beats', <String, dynamic>{
            'clip_ref': ref('split', 'right_clip'),
            'delta_beats': 1,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        context: _context(),
      );
      expect(tempoAfter.actions[1].data['cut_ms'], 1000.0);
      expect(tempoAfter.actions[3].data['predicted_start_ms'], 1800.0);
    });

    test('prepares generated audio duplicate, trim, and independent edits', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 100},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
        _command('copy', 'clip.duplicate_to', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'destination_row_id': null,
          'start_beat': 4,
        }),
        _command('pitch-copy', 'clip.adjust_pitch_semitones', <String, dynamic>{
          'clip_ref': ref('copy', 'copy_clip'),
          'delta_semitones': -2,
        }),
        _command('trim-copy', 'clip.trim_to_range', <String, dynamic>{
          'clip_ref': ref('copy', 'copy_clip'),
          'start_beat': 4.5,
          'end_beat': 6,
        }),
        _command('move-original', 'clip.move_by_beats', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'delta_beats': 1,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'sample_insert',
        'clip_edit',
        'clip_edit',
        'clip_edit',
        'clip_edit',
      ]);
      expect(prepared.actions[1].data['command_id'], 'copy');
      expect(prepared.actions[1].data.containsKey('row_index'), isFalse);
      expect(prepared.actions[3].data['requested_start_ms'], 2250.0);
      expect(prepared.actions[3].data['requested_end_ms'], 3000.0);
      expect(prepared.actions[4].data['predicted_start_ms'], 500.0);
      expect(
        jsonEncode(prepared.actions),
        isNot(anyOf(contains('label_contains'), contains('clip_index'))),
      );
    });

    test('prepares generated MIDI duplicate, split, and terminal edit', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('midi', 'midi.create_clip', <String, dynamic>{
          'destination': <String, dynamic>{
            'new_row': <String, dynamic>{
              'name': 'Synth',
              'instrument_id': 'piano',
            },
          },
          'start_beat': 0,
          'length_beats': 4,
          'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
        }),
        _command('copy', 'clip.duplicate_to', <String, dynamic>{
          'clip_ref': ref('midi', 'midi_clip'),
          'destination_row_id': null,
          'start_beat': 4,
        }),
        _command('transpose', 'midi.transpose', <String, dynamic>{
          'clip_ref': ref('copy', 'copy_clip'),
          'semitones': 2,
        }),
        _command('split', 'clip.split_at', <String, dynamic>{
          'clip_ref': ref('copy', 'copy_clip'),
          'at_beat': 6,
        }),
        _command('delete-right', 'clip.delete', <String, dynamic>{
          'clip_ref': ref('split', 'right_clip'),
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'row_create',
        'midi_compose',
        'clip_edit',
        'midi_compose',
        'clip_edit',
        'clip_edit',
      ]);
      expect(prepared.actions[2].data['paste_start_ms'], 2000.0);
      expect(prepared.actions[4].data['predicted_input_start_ms'], 2000.0);
      expect(prepared.actions[4].data['predicted_input_end_ms'], 4000.0);
    });

    test('edits generated MIDI copies and split outputs independently', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('midi', 'midi.create_clip', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 200},
          'start_beat': 0,
          'length_beats': 4,
          'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
        }),
        _command('copy', 'clip.duplicate_to', <String, dynamic>{
          'clip_ref': ref('midi', 'midi_clip'),
          'destination_row_id': null,
          'start_beat': 4,
        }),
        _command('replace-copy', 'midi.replace_notes', <String, dynamic>{
          'clip_ref': ref('copy', 'copy_clip'),
          'notes': <Map<String, dynamic>>[_note(70, 0, 1)],
        }),
        _command('split-copy', 'clip.split_at', <String, dynamic>{
          'clip_ref': ref('copy', 'copy_clip'),
          'at_beat': 6,
        }),
        _command('append-right', 'midi.append_notes', <String, dynamic>{
          'clip_ref': ref('split-copy', 'right_clip'),
          'notes': <Map<String, dynamic>>[_note(72, 0, 0.5)],
        }),
        _command('chop-left', 'midi.chop_notes', <String, dynamic>{
          'clip_ref': ref('split-copy', 'left_clip'),
          'subdivision': 8,
          'range': null,
          'velocity_decay_per_slice': 0,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions, hasLength(6));
      expect(
        prepared.actions[4].data['resource_consumer_type'],
        'midi.append_notes',
      );
      expect(prepared.actions[4].data['final_length_beats'], 2.5);
      expect(
        (prepared.actions[4].data['target'] as Map)['resource_ref'],
        ref('split-copy', 'right_clip'),
      );
      expect(
        (prepared.actions[5].data['notes'] as List).map(
          (raw) => (raw as Map)['start_beat'],
        ),
        <double>[0.0, 0.5],
      );
      expect(
        (prepared.actions[5].data['target'] as Map)['resource_ref'],
        ref('split-copy', 'left_clip'),
      );
    });

    test('duplicate preserves its input and supports repeated duplication', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('place', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 100},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
        _command('copy-one', 'clip.duplicate_to', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'destination_row_id': null,
          'start_beat': 2,
        }),
        _command('copy-two', 'clip.duplicate_to', <String, dynamic>{
          'clip_ref': ref('copy-one', 'copy_clip'),
          'destination_row_id': 100,
          'start_beat': 4,
        }),
        _command('move-input', 'clip.move_by_beats', <String, dynamic>{
          'clip_ref': ref('place', 'audio_clip'),
          'delta_beats': 1,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      expect(plan.commands, hasLength(4));
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions[2].data['paste_start_ms'], 2000.0);
      expect(prepared.actions.last.data['predicted_start_ms'], 500.0);
    });

    test(
      'preserves deferred generated stem bounds through duplicate and split',
      () {
        final plan = parse(<Map<String, dynamic>>[
          _command('place', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 100},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          }),
          _command('stems', 'clip.separate_stems', <String, dynamic>{
            'clip_ref': ref('place', 'audio_clip'),
          }),
          _command('copy', 'clip.duplicate_to', <String, dynamic>{
            'clip_ref': ref('stems', 'instrumental_clip'),
            'destination_row_id': null,
            'start_beat': 8,
          }),
          _command('split', 'clip.split_at', <String, dynamic>{
            'clip_ref': ref('copy', 'copy_clip'),
            'at_beat': 10,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);

        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _contextForStemSeparation(),
        );

        expect(prepared.actions, hasLength(4));
        expect(prepared.actions[2].data['predicted_input_end_ms'], isNull);
        expect(prepared.actions[3].data['predicted_input_end_ms'], isNull);
        expect(
          (prepared.actions[3].data['target'] as Map)['resource_ref'],
          ref('copy', 'copy_clip'),
        );
      },
    );

    test('composes tempo before and after generated duplicate trim', () {
      Map<String, dynamic> place() =>
          _command('place', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 100},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          });
      Map<String, dynamic> duplicate() =>
          _command('copy', 'clip.duplicate_to', <String, dynamic>{
            'clip_ref': ref('place', 'audio_clip'),
            'destination_row_id': null,
            'start_beat': 4,
          });
      Map<String, dynamic> trim() =>
          _command('trim', 'clip.trim_to_range', <String, dynamic>{
            'clip_ref': ref('copy', 'copy_clip'),
            'start_beat': 4.5,
            'end_beat': 6,
          });
      final tempo = _command('tempo', 'project.set_tempo', <String, dynamic>{
        'bpm': 100,
        'time_stretch_audio': false,
        'preserve_pitch': true,
      });
      Map<String, dynamic> move() =>
          _command('move', 'clip.move_by_beats', <String, dynamic>{
            'clip_ref': ref('copy', 'copy_clip'),
            'delta_beats': 1,
          });

      final tempoFirst = const AiV3CommandPreparer().prepare(
        plan: parse(<Map<String, dynamic>>[
          tempo,
          place(),
          duplicate(),
          trim(),
          move(),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        context: _context(),
      );
      expect(tempoFirst.actions[2].data['paste_start_ms'], 2400.0);
      expect(tempoFirst.actions[3].data['requested_start_ms'], 2700.0);
      expect(tempoFirst.actions[4].data['predicted_start_ms'], 3300.0);

      final tempoAfter = const AiV3CommandPreparer().prepare(
        plan: parse(<Map<String, dynamic>>[
          place(),
          duplicate(),
          trim(),
          tempo,
          move(),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        context: _context(),
      );
      expect(tempoAfter.actions[1].data['paste_start_ms'], 2000.0);
      expect(tempoAfter.actions[2].data['requested_start_ms'], 2250.0);
      expect(tempoAfter.actions[4].data['predicted_start_ms'], 3300.0);
    });

    test('rejects invalid duplicate and generated trim targets', () {
      expect(
        () => parse(<Map<String, dynamic>>[
          _command('midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 200},
            'start_beat': 0,
            'length_beats': 4,
            'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
          }),
          _command('trim', 'clip.trim_to_range', <String, dynamic>{
            'clip_ref': ref('midi', 'midi_clip'),
            'start_beat': 0,
            'end_beat': 2,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        throwsA(isA<AiV3ContractException>()),
      );
      expect(
        () => parse(<Map<String, dynamic>>[
          _command('copy', 'clip.duplicate_to', <String, dynamic>{
            'clip_id': 'audio-clip',
            'destination_row_id': null,
            'start_beat': 1,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes),
        throwsA(isA<AiV3ContractException>()),
      );
      final wrongLane = parse(<Map<String, dynamic>>[
        _command('midi', 'midi.create_clip', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 200},
          'start_beat': 0,
          'length_beats': 4,
          'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
        }),
        _command('copy', 'clip.duplicate_to', <String, dynamic>{
          'clip_ref': ref('midi', 'midi_clip'),
          'destination_row_id': 100,
          'start_beat': 4,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: wrongLane,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_clip_destination_lane_mismatch',
          ),
        ),
      );
    });

    test(
      'retires split inputs and enforces exact output kind in preparation',
      () {
        expect(
          () => parse(<Map<String, dynamic>>[
            _command('place', 'sample.place', <String, dynamic>{
              'destination': <String, dynamic>{'row_id': 100},
              'placements': <Map<String, dynamic>>[
                <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
              ],
            }),
            _command('split', 'clip.split_at', <String, dynamic>{
              'clip_ref': ref('place', 'audio_clip'),
              'at_beat': 1,
            }),
            _command('reuse-old', 'clip.move_by_beats', <String, dynamic>{
              'clip_ref': ref('place', 'audio_clip'),
              'delta_beats': 1,
            }),
          ], consumers: aiV3RuntimeResourceRefConsumerTypes),
          throwsA(isA<AiV3ContractException>()),
        );

        final stableAudioPlan = parse(<Map<String, dynamic>>[
          _command('split', 'clip.split_at', <String, dynamic>{
            'clip_id': 'audio-clip',
            'at_beat': 4,
          }),
          _command('transpose', 'midi.transpose', <String, dynamic>{
            'clip_ref': ref('split', 'right_clip'),
            'semitones': 1,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: stableAudioPlan,
            context: _context(),
          ),
          throwsA(isA<AiV3PreparationException>()),
        );

        final stableAudioEdit = parse(<Map<String, dynamic>>[
          _command('split', 'clip.split_at', <String, dynamic>{
            'clip_id': 'audio-clip',
            'at_beat': 4,
          }),
          _command('pitch-left', 'clip.set_pitch_semitones', <String, dynamic>{
            'clip_ref': ref('split', 'left_clip'),
            'pitch_semitones': -2,
          }),
          _command('move-right', 'clip.move_by_beats', <String, dynamic>{
            'clip_ref': ref('split', 'right_clip'),
            'delta_beats': 1,
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);
        final prepared = const AiV3CommandPreparer().prepare(
          plan: stableAudioEdit,
          context: _context(),
        );
        expect(prepared.actions, hasLength(3));
        expect(prepared.actions.first.data['predicted_input_end_ms'], 4000.0);
        expect(prepared.actions.last.data['predicted_start_ms'], 2500.0);
      },
    );

    test('rejects ambiguous sample output and use after delete', () {
      final invalidPlans = <List<Map<String, dynamic>>>[
        <Map<String, dynamic>>[
          _command('place', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 100},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 1},
            ],
          }),
          _command('move', 'clip.move_by_beats', <String, dynamic>{
            'clip_ref': ref('place', 'audio_clip'),
            'delta_beats': 1,
          }),
        ],
        <Map<String, dynamic>>[
          _command('midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 200},
            'start_beat': 0,
            'length_beats': 4,
            'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
          }),
          _command('delete', 'clip.delete', <String, dynamic>{
            'clip_ref': ref('midi', 'midi_clip'),
          }),
          _command('move', 'clip.move_by_beats', <String, dynamic>{
            'clip_ref': ref('midi', 'midi_clip'),
            'delta_beats': 1,
          }),
        ],
      ];
      for (final commands in invalidPlans) {
        expect(
          () => parse(commands, consumers: aiV3RuntimeResourceRefConsumerTypes),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('prepares generated MIDI clip transpose from symbolic notes', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('create-midi', 'midi.create_clip', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 200},
          'start_beat': 0,
          'length_beats': 4,
          'notes': <Map<String, dynamic>>[
            _note(0, 0, 1),
            _note(60, 1, 1),
            _note(127, 2, 1),
          ],
        }),
        _command('transpose', 'midi.transpose', <String, dynamic>{
          'clip_ref': ref('create-midi', 'midi_clip'),
          'semitones': 2,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions.map((action) => action.type), <String>[
        'midi_compose',
        'midi_compose',
      ]);
      expect(prepared.actions.first.data['command_id'], 'create-midi');
      expect(
        (prepared.actions.last.data['target'] as Map)['resource_ref'],
        ref('create-midi', 'midi_clip'),
      );
      expect(
        (prepared.actions.last.data['expected_notes'] as List).map(
          (note) => (note as Map)['pitch'],
        ),
        <int>[2, 62, 127],
      );
      expect(
        jsonEncode(prepared.actions.last.data),
        isNot(anyOf(contains('label_contains'), contains('clip_index'))),
      );
    });

    test('prepares complete generated MIDI note editing in order', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('create-midi', 'midi.create_clip', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 200},
          'start_beat': 0,
          'length_beats': 4,
          'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
        }),
        _command('replace', 'midi.replace_notes', <String, dynamic>{
          'clip_ref': ref('create-midi', 'midi_clip'),
          'notes': <Map<String, dynamic>>[_note(65, 0, 1), _note(67, 2, 1)],
        }),
        _command('append', 'midi.append_notes', <String, dynamic>{
          'clip_ref': ref('create-midi', 'midi_clip'),
          'notes': <Map<String, dynamic>>[_note(72, 0, 0.5)],
        }),
        _command('chop', 'midi.chop_notes', <String, dynamic>{
          'clip_ref': ref('create-midi', 'midi_clip'),
          'subdivision': 8,
          'range': null,
          'velocity_decay_per_slice': 0,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions, hasLength(4));
      expect(
        prepared.actions.map((action) => action.data['operation']),
        <String>[
          'create_clip',
          'replace_notes',
          'replace_notes',
          'replace_notes',
        ],
      );
      expect(
        prepared.actions
            .skip(1)
            .map((action) => action.data['resource_consumer_type']),
        <String>['midi.replace_notes', 'midi.append_notes', 'midi.chop_notes'],
      );
      expect(prepared.actions[2].data['final_length_beats'], 4.5);
      expect(
        (prepared.actions.last.data['notes'] as List).map((raw) {
          final note = raw as Map;
          return <Object?>[
            note['pitch'],
            note['start_beat'],
            note['length_beats'],
          ];
        }),
        <List<Object?>>[
          <Object?>[65, 0.0, 0.5],
          <Object?>[65, 0.5, 0.5],
          <Object?>[67, 2.0, 0.5],
          <Object?>[67, 2.5, 0.5],
          <Object?>[72, 4.0, 0.5],
        ],
      );
      for (final action in prepared.actions.skip(1)) {
        expect(
          (action.data['target'] as Map)['resource_ref'],
          ref('create-midi', 'midi_clip'),
        );
      }
      expect(
        prepared.receipts.skip(1).map((receipt) => receipt['verified_label']),
        <String>[
          'Replaced notes in Keys',
          'Appended notes to Keys',
          'Chopped notes in Keys',
        ],
      );
      final displayText = prepared.receipts
          .skip(1)
          .expand(
            (receipt) => <Object?>[
              receipt['preview_label'],
              receipt['verified_label'],
              receipt['verified_l10n_args'],
            ],
          )
          .join(' ');
      expect(displayText, isNot(contains('create-midi.midi_clip')));
    });

    test(
      'non-producing MIDI edit aliases resolve to the original reference',
      () {
        final plan = parse(<Map<String, dynamic>>[
          _command('create-midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 200},
            'start_beat': 0,
            'length_beats': 4,
            'notes': <Map<String, dynamic>>[_note(60, 0, 1)],
          }),
          _command('replace', 'midi.replace_notes', <String, dynamic>{
            'clip_ref': ref('create-midi', 'midi_clip'),
            'notes': <Map<String, dynamic>>[_note(65, 0, 1)],
          }),
          _command('append', 'midi.append_notes', <String, dynamic>{
            'clip_ref': ref('replace', 'midi_clip'),
            'notes': <Map<String, dynamic>>[_note(67, 0, 0.5)],
          }),
        ], consumers: aiV3RuntimeResourceRefConsumerTypes);
        expect(
          plan.commands.last.arguments['clip_ref'],
          ref('create-midi', 'midi_clip'),
        );
      },
    );

    test('prepares a symbolic stem pitch chain from predicted pitch zero', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('tempo', 'project.set_tempo', <String, dynamic>{
          'bpm': 110,
          'time_stretch_audio': false,
          'preserve_pitch': true,
        }),
        _command('separate', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('lower', 'clip.adjust_pitch_semitones', <String, dynamic>{
          'clip_ref': ref('separate', 'instrumental_clip'),
          'delta_semitones': -1,
        }),
        _command('raise', 'clip.adjust_pitch_semitones', <String, dynamic>{
          'clip_ref': ref('separate', 'instrumental_clip'),
          'delta_semitones': 2,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextForStemSeparation(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'project_edit',
        'v3_clip_separate_stems',
        'clip_edit',
        'clip_edit',
      ]);
      expect(prepared.actions[1].data['command_id'], 'separate');
      expect(prepared.actions[2].data['new_pitch_semitones'], -1.0);
      expect(prepared.actions[3].data['new_pitch_semitones'], 1.0);
      expect(
        (prepared.actions[2].data['target'] as Map)['resource_ref'],
        ref('separate', 'instrumental_clip'),
      );
      expect(
        jsonEncode(prepared.actions[2].data),
        isNot(anyOf(contains('label_contains'), contains('clip_index'))),
      );
      expect(
        prepared.receipts.map((receipt) => receipt['verified_label']),
        <String>[
          'Set project tempo to 110 BPM',
          'Separated vocals and instrumental',
          'Set instrumental stem pitch to -1.0 semitones',
          'Set instrumental stem pitch to 1.0 semitones',
        ],
      );
      expect(
        jsonEncode(
          prepared.receipts
              .map((receipt) => receipt['verified_label'])
              .toList(growable: false),
        ),
        isNot(contains('separate.instrumental_clip')),
      );
    });

    test('rejects generated pitch outside editor limits', () {
      final plan = parse(<Map<String, dynamic>>[
        _command('separate', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('pitch', 'clip.adjust_pitch_semitones', <String, dynamic>{
          'clip_ref': ref('separate', 'instrumental_clip'),
          'delta_semitones': 13,
        }),
      ], consumers: aiV3RuntimeResourceRefConsumerTypes);
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _contextForStemSeparation(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_clip_pitch_out_of_range',
          ),
        ),
      );
    });
  });

  group('V3 execution policy', () {
    test('explicitly covers every current command as auto apply', () {
      expect(aiV3ExecutionPolicyByCommandType.keys.toSet(), aiV3CommandTypes);
      expect(
        aiV3ExecutionPolicyByCommandType.values,
        everyElement(AiV3ExecutionPolicy.autoApply),
      );
    });

    test(
      'fails closed for missing policy and uses strictest compound policy',
      () {
        expect(
          () => aiV3ExecutionPolicyForCommandTypes(const <String>[
            'future.command',
          ]),
          throwsA(
            isA<AiV3ContractException>().having(
              (error) => error.code,
              'code',
              'v3_execution_policy_missing',
            ),
          ),
        );
        expect(
          aiV3ExecutionPolicyForCommandTypes(
            const <String>['safe', 'future_external'],
            policies: const <String, AiV3ExecutionPolicy>{
              'safe': AiV3ExecutionPolicy.autoApply,
              'future_external': AiV3ExecutionPolicy.confirm,
            },
          ),
          AiV3ExecutionPolicy.confirm,
        );
      },
    );
  });

  group('PlanV3 contract', () {
    test('accepts strict subjective and reference mix goals', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('mix', 'mix.apply_goal', <String, dynamic>{
            'target': <String, dynamic>{'scope': 'row', 'row_id': 100},
            'intents': <Map<String, dynamic>>[
              <String, dynamic>{
                'kind': 'eq',
                'direction': null,
                'descriptor': 'warmth_boost',
              },
            ],
            'intensity': 0.55,
            'execution_profile': 'producer_safe',
            'audibility': 'noticeable',
            'style_tags': <String>['warm'],
            'reset_fx': false,
            'reference': <String, dynamic>{
              'row_id': 100,
              'mode': 'tone',
              'closeness': 'balanced',
            },
          }),
        ]),
      );
      expect(plan.commands.single.type, 'mix.apply_goal');
    });

    test('accepts only strict row instrument commands', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('instrument', 'row.set_instrument', <String, dynamic>{
            'row_id': 200,
            'instrument_id': 'bass',
          }),
        ]),
      );
      expect(plan.commands.single.type, 'row.set_instrument');

      for (final arguments in <Map<String, dynamic>>[
        <String, dynamic>{'row_id': 200},
        <String, dynamic>{'row_id': -1, 'instrument_id': 'bass'},
        <String, dynamic>{'row_id': 200, 'instrument_id': ''},
        <String, dynamic>{
          'row_id': 200,
          'instrument_id': 'bass',
          'extra': true,
        },
      ]) {
        expect(
          () => AiV3Plan.fromJson(
            _plan(<Map<String, dynamic>>[
              _command('invalid', 'row.set_instrument', arguments),
            ]),
          ),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('prepares exact effect-instance removal and final bypass state', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('bypass', 'effect.set_bypassed', <String, dynamic>{
            'effect_instance_id': 'fx-comp-1',
            'bypassed': true,
          }),
          _command('remove', 'effect.remove', <String, dynamic>{
            'effect_instance_id': 'fx-reverb-1',
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions, hasLength(2));
      expect(
        prepared.actions.map((action) => action.type),
        everyElement('v3_effect_instance_edit'),
      );
      expect(prepared.actions.first.data['effect_index'], 0);
      expect(prepared.actions.last.data['effect_index'], 1);
      expect(prepared.actions.first.data['bypassed'], isTrue);
    });

    test('effect bypass no-op is already satisfied without an action', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('enabled', 'effect.set_bypassed', <String, dynamic>{
            'effect_instance_id': 'fx-comp-1',
            'bypassed': false,
          }),
        ]),
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions, isEmpty);
      expect(prepared.receipts.single['status'], 'already_satisfied');
    });

    test(
      'prepares remove and recreate effect ordering as one ordered chain',
      () {
        final base = _contextWithEffects(<String, List<String>>{
          'Compressor': <String>['Mix'],
          'EQ 3-Band': <String>['Low Gain'],
        });
        final data = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(base.data)) as Map,
        );
        final rows = (data['rows'] as List)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList(growable: false);
        rows.first['effects'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'effect_instance_id': 'fx-comp-1',
            'effect_id': 'Compressor',
            'display_name': 'Compressor',
            'bypassed': true,
            'parameters': const <Object>[],
          },
          <String, dynamic>{
            'effect_instance_id': 'fx-eq-1',
            'effect_id': 'EQ 3-Band',
            'display_name': 'EQ 3-Band',
            'bypassed': false,
            'parameters': const <Object>[],
          },
        ];
        data['rows'] = rows;
        final context = AiV3CoreContext(
          profile: base.profile,
          stateDigest: base.stateDigest,
          data: data,
        );
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('remove-comp', 'effect.remove', <String, dynamic>{
              'effect_instance_id': 'fx-comp-1',
            }),
            _command('remove-eq', 'effect.remove', <String, dynamic>{
              'effect_instance_id': 'fx-eq-1',
            }),
            _command('add-eq', 'effect.ensure_configured', <String, dynamic>{
              'row_id': 100,
              'effect_id': 'EQ 3-Band',
              'parameters': const <Map<String, dynamic>>[],
            }),
            _command('add-comp', 'effect.ensure_configured', <String, dynamic>{
              'row_id': 100,
              'effect_id': 'Compressor',
              'parameters': const <Map<String, dynamic>>[],
            }),
          ]),
        );

        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: context,
        );
        expect(prepared.actions.map((action) => action.type), <String>[
          'v3_effect_instance_edit',
          'v3_effect_instance_edit',
          'v3_effect_configure',
          'v3_effect_configure',
        ]);
        expect(prepared.receipts, hasLength(4));
        expect(prepared.actions[0].data['effect_index'], 0);
        expect(prepared.actions[1].data['effect_index'], 0);
        expect(prepared.actions[2].data['effect_id'], 'EQ 3-Band');
        expect(prepared.actions[3].data['effect_id'], 'Compressor');
      },
    );

    test('rejects malformed mix enums and extra target fields', () {
      Map<String, dynamic> arguments() => <String, dynamic>{
        'target': <String, dynamic>{'scope': 'all_rows'},
        'intents': <Map<String, dynamic>>[
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
        'reference': null,
      };
      final badKind = arguments();
      ((badKind['intents'] as List).single as Map)['kind'] = 'magic';
      expect(
        () => AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('bad-kind', 'mix.apply_goal', badKind),
          ]),
        ),
        throwsA(isA<AiV3ContractException>()),
      );
      final badTarget = arguments();
      (badTarget['target'] as Map)['row_id'] = 100;
      expect(
        () => AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('bad-target', 'mix.apply_goal', badTarget),
          ]),
        ),
        throwsA(isA<AiV3ContractException>()),
      );
    });

    test('accepts the original fourteen prototype command variants', () {
      final commands = <Map<String, dynamic>>[
        _command('1', 'project.set_tempo', <String, dynamic>{
          'bpm': 128,
          'time_stretch_audio': true,
          'preserve_pitch': true,
        }),
        _command('2', 'row.adjust_gain_db', <String, dynamic>{
          'row_id': 100,
          'delta_db': -2,
        }),
        _command('3', 'row.set_gain_db', <String, dynamic>{
          'row_id': 100,
          'gain_db': -6,
        }),
        _command('4', 'row.adjust_pan', <String, dynamic>{
          'row_id': 100,
          'delta_signed': 0.25,
        }),
        _command('5', 'row.set_soloed', <String, dynamic>{
          'row_id': 100,
          'soloed': true,
        }),
        _command('6', 'row.set_pan', <String, dynamic>{
          'row_id': 100,
          'pan_signed': 0.2,
        }),
        _command('7', 'row.set_muted', <String, dynamic>{
          'row_id': 100,
          'muted': true,
        }),
        _command('8', 'row.rename', <String, dynamic>{
          'row_id': 100,
          'new_name': 'Drums',
        }),
        _command('9', 'clip.move_by_beats', <String, dynamic>{
          'clip_id': 'audio-clip',
          'delta_beats': 4,
        }),
        _command('10', 'midi.transpose', <String, dynamic>{
          'clip_id': 'midi-clip',
          'semitones': -2,
        }),
        _command('11', 'midi.create_clip', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 200},
          'start_beat': 0,
          'length_beats': 4,
          'notes': <Map<String, dynamic>>[
            <String, dynamic>{
              'pitch': 60,
              'start_beat': 0,
              'length_beats': 1,
              'velocity': 0.8,
            },
          ],
        }),
        _command('12', 'effect.ensure_configured', <String, dynamic>{
          'row_id': 100,
          'effect_id': 'Reverb',
          'parameters': <Map<String, dynamic>>[
            <String, dynamic>{'parameter_id': 'Mix', 'value': 0.2},
          ],
        }),
        _command('13', 'automation.gain_fade', <String, dynamic>{
          'row_id': 100,
          'start_beat': 0,
          'end_beat': 4,
          'from_gain_db': -120,
          'to_level': 'current',
        }),
        _command('14', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 100},
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
      ];

      final plan = AiV3Plan.fromJson(_plan(commands));

      expect(plan.commands, hasLength(14));
      expect(plan.isMutating, isTrue);

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'project_edit',
        'row_mix',
        'row_mix',
        'row_mix',
        'row_solo',
        'row_mix',
        'row_mute',
        'row_rename',
        'clip_edit',
        'midi_compose',
        'midi_compose',
        'v3_effect_configure',
        'automation_edit',
        'sample_insert',
      ]);
      expect(prepared.actions[0].data['tempo_bpm'], 128);
      expect(prepared.actions[1].data['delta_db'], -2);
      expect(prepared.actions[2].data['gain_db'], -6);
      expect(prepared.actions[3].data['delta'], 0.25);
      expect(prepared.actions[4].data['operation'], 'set_soloed');
      expect(prepared.actions[4].data['soloed'], isTrue);
      expect(prepared.actions[5].data['pan_signed'], 0.2);
      expect(prepared.actions[8].data['delta_ms'], 2000.0);
      expect(prepared.actions[9].data['semitones'], -2);
      expect(prepared.actions[10].data['notes'], hasLength(1));
      expect(prepared.actions[11].data['parameters'], <String, dynamic>{
        'Mix': 0.2,
      });
      expect(prepared.actions[13].data['items'], hasLength(1));
      expect(prepared.receipts, hasLength(14));
    });

    test('enforces exact row-control fields and semantic bounds', () {
      for (final invalid in <Map<String, dynamic>>[
        _command('gain-low', 'row.set_gain_db', <String, dynamic>{
          'row_id': 100,
          'gain_db': -60.1,
        }),
        _command('gain-high', 'row.set_gain_db', <String, dynamic>{
          'row_id': 100,
          'gain_db': 6.1,
        }),
        _command('pan', 'row.adjust_pan', <String, dynamic>{
          'row_id': 100,
          'delta_signed': 2.1,
        }),
        _command('solo', 'row.set_soloed', <String, dynamic>{
          'row_id': 100,
          'soloed': 1,
        }),
      ]) {
        expect(
          () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[invalid])),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('accepts exact core clip command variants', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('trim', 'clip.trim_to_range', <String, dynamic>{
            'clip_id': 'audio-clip',
            'start_beat': 1,
            'end_beat': 7,
          }),
          _command('split', 'clip.split_at', <String, dynamic>{
            'clip_id': 'midi-clip',
            'at_beat': 8,
          }),
          _command('duplicate', 'clip.duplicate_to', <String, dynamic>{
            'clip_id': 'audio-clip',
            'destination_row_id': 100,
            'start_beat': 12,
          }),
          _command('delete', 'clip.delete', <String, dynamic>{
            'clip_id': 'midi-clip',
          }),
        ]),
      );

      expect(plan.commands, hasLength(4));
      expect(plan.commands.map((command) => command.type), <String>[
        'clip.trim_to_range',
        'clip.split_at',
        'clip.duplicate_to',
        'clip.delete',
      ]);
    });

    test(
      'accepts strict audio clip glue and prepares exact stable targets',
      () {
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('glue', 'clip.glue', <String, dynamic>{
              'clip_ids': <String>['audio-clip-2', 'audio-clip'],
              'label': 'Hook Comp',
            }),
          ]),
        );
        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _contextWithSecondAudioClip(),
        );

        expect(prepared.actions.single.type, 'v3_clip_glue');
        expect(prepared.actions.single.data['source_clip_ids'], <String>[
          'audio-clip',
          'audio-clip-2',
        ]);
        expect(prepared.actions.single.data['label'], 'Hook Comp');
        expect(prepared.actions.single.data['start_ms'], 0.0);
        expect(prepared.actions.single.data['duration_ms'], 6000.0);
      },
    );

    test('accepts and prepares strict local two-stem separation', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('stems', 'clip.separate_stems', <String, dynamic>{
            'clip_id': 'audio-clip',
          }),
        ]),
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextForStemSeparation(),
      );

      expect(prepared.actions.single.type, 'v3_clip_separate_stems');
      expect(prepared.actions.single.data['source_clip_id'], 'audio-clip');
      expect(prepared.actions.single.data['source_row_id'], 100);
      expect(prepared.actions.single.data['start_ms'], 0.0);
      expect(prepared.actions.single.data['duration_ms'], 4000.0);
      expect(prepared.actions.single.data['vocals_label'], 'Audio clip Vocals');
      expect(
        prepared.actions.single.data['instrumental_label'],
        'Audio clip Instrumental',
      );
    });

    test(
      'stem separation rejects malformed, MIDI, and unavailable requests',
      () {
        expect(
          () => AiV3Plan.fromJson(
            _plan(<Map<String, dynamic>>[
              _command('bad', 'clip.separate_stems', <String, dynamic>{
                'clip_id': 'audio-clip',
                'output': 'vocals',
              }),
            ]),
          ),
          throwsA(isA<AiV3ContractException>()),
        );
        final midi = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('midi', 'clip.separate_stems', <String, dynamic>{
              'clip_id': 'midi-clip',
            }),
          ]),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: midi,
            context: _contextForStemSeparation(),
          ),
          throwsA(isA<AiV3PreparationException>()),
        );
        final unavailable = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('stems', 'clip.separate_stems', <String, dynamic>{
              'clip_id': 'audio-clip',
            }),
          ]),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: unavailable,
            context: _context(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_stem_separation_unavailable',
            ),
          ),
        );
        final capacityData = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(_contextForStemSeparation().data)) as Map,
        );
        final project = Map<String, dynamic>.from(
          capacityData['project'] as Map,
        );
        project['row_capacity'] = <String, dynamic>{
          'current_rows': (capacityData['rows'] as List).length,
          'max_rows': (capacityData['rows'] as List).length + 1,
          'can_create': true,
        };
        capacityData['project'] = project;
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: unavailable,
            context: AiV3CoreContext(
              profile: AiV3ContextProfile.essential,
              stateDigest: 'capacity',
              data: capacityData,
            ),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_row_capacity_exceeded',
            ),
          ),
        );
        final unreadableData = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(_contextForStemSeparation().data)) as Map,
        );
        final unreadableClips = (unreadableData['clips'] as List)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList(growable: false);
        unreadableClips.singleWhere(
          (clip) => clip['clip_id'] == 'audio-clip',
        )['source_available'] = false;
        unreadableData['clips'] = unreadableClips;
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: unavailable,
            context: AiV3CoreContext(
              profile: AiV3ContextProfile.essential,
              stateDigest: 'unreadable',
              data: unreadableData,
            ),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_stem_source_unreadable',
            ),
          ),
        );
      },
    );

    test(
      'stem separation permits a later stable edit but blocks topology work',
      () {
        final allowed = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('stems', 'clip.separate_stems', <String, dynamic>{
              'clip_id': 'audio-clip',
            }),
            _command('gain', 'row.adjust_gain_db', <String, dynamic>{
              'row_id': 200,
              'delta_db': -1,
            }),
          ]),
        );
        expect(
          const AiV3CommandPreparer()
              .prepare(plan: allowed, context: _contextForStemSeparation())
              .actions,
          hasLength(2),
        );

        final blocked = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('stems', 'clip.separate_stems', <String, dynamic>{
              'clip_id': 'audio-clip',
            }),
            _command('create', 'row.create', <String, dynamic>{
              'name': 'Later',
              'lane': <String, dynamic>{'kind': 'audio'},
              'position': <String, dynamic>{'kind': 'end'},
            }),
          ]),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: blocked,
            context: _contextForStemSeparation(),
          ),
          throwsA(isA<AiV3PreparationException>()),
        );
      },
    );

    test('accepts and prepares strict local audio-to-MIDI conversion', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('convert', 'clip.convert_to_midi', <String, dynamic>{
            'clip_id': 'audio-clip',
            'instrument_id': 'piano',
          }),
        ]),
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextForAudioToMidi(),
      );

      expect(prepared.actions.single.type, 'v3_clip_convert_to_midi');
      expect(prepared.actions.single.data['source_clip_id'], 'audio-clip');
      expect(prepared.actions.single.data['source_row_id'], 100);
      expect(prepared.actions.single.data['instrument_id'], 'piano');
      expect(prepared.actions.single.data['start_ms'], 0.0);
      expect(prepared.actions.single.data['duration_ms'], 4000.0);
      expect(prepared.actions.single.data['output_label'], 'Audio clip MIDI');
    });

    test('audio-to-MIDI rejects malformed and unavailable requests', () {
      expect(
        () => AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('bad', 'clip.convert_to_midi', <String, dynamic>{
              'clip_id': 'audio-clip',
            }),
          ]),
        ),
        throwsA(isA<AiV3ContractException>()),
      );
      final unavailableInstrument = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('convert', 'clip.convert_to_midi', <String, dynamic>{
            'clip_id': 'audio-clip',
            'instrument_id': 'invented',
          }),
        ]),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: unavailableInstrument,
          context: _contextForAudioToMidi(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_instrument_id_unknown',
          ),
        ),
      );
      final unavailableService = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('convert', 'clip.convert_to_midi', <String, dynamic>{
            'clip_id': 'audio-clip',
            'instrument_id': 'piano',
          }),
        ]),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: unavailableService,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_audio_to_midi_unavailable',
          ),
        ),
      );
    });

    test('rejects malformed glue and later use of a consumed source', () {
      for (final arguments in <Map<String, dynamic>>[
        <String, dynamic>{
          'clip_ids': <String>['audio-clip'],
          'label': null,
        },
        <String, dynamic>{
          'clip_ids': <String>['audio-clip', 'audio-clip'],
          'label': null,
        },
        <String, dynamic>{
          'clip_ids': <String>['audio-clip', 'audio-clip-2'],
          'label': '',
        },
      ]) {
        expect(
          () => AiV3Plan.fromJson(
            _plan(<Map<String, dynamic>>[
              _command('glue', 'clip.glue', arguments),
            ]),
          ),
          throwsA(isA<AiV3ContractException>()),
        );
      }

      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('glue', 'clip.glue', <String, dynamic>{
            'clip_ids': <String>['audio-clip', 'audio-clip-2'],
            'label': null,
          }),
          _command('delete', 'clip.delete', <String, dynamic>{
            'clip_id': 'audio-clip',
          }),
        ]),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _contextWithSecondAudioClip(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_clip_id_unknown',
          ),
        ),
      );
    });

    test(
      'glue rejects cross-row, previously mutated, and post-topology clips',
      () {
        AiV3Plan glueAfter(List<Map<String, dynamic>> preceding) =>
            AiV3Plan.fromJson(
              _plan(<Map<String, dynamic>>[
                ...preceding,
                _command('glue', 'clip.glue', <String, dynamic>{
                  'clip_ids': <String>['audio-clip', 'audio-clip-2'],
                  'label': null,
                }),
              ]),
            );

        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: glueAfter(const <Map<String, dynamic>>[]),
            context: _contextWithCrossRowAudioClips(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_clip_glue_row_mismatch',
            ),
          ),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: glueAfter(<Map<String, dynamic>>[
              _command('move', 'clip.move_by_beats', <String, dynamic>{
                'clip_id': 'audio-clip',
                'delta_beats': 1,
              }),
            ]),
            context: _contextWithSecondAudioClip(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_clip_glue_source_already_mutated',
            ),
          ),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: glueAfter(<Map<String, dynamic>>[
              _command('create-row', 'row.create', <String, dynamic>{
                'name': 'New Audio',
                'lane': const <String, dynamic>{'kind': 'audio'},
                'position': const <String, dynamic>{'kind': 'end'},
              }),
            ]),
            context: _contextWithSecondAudioClip(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_clip_id_unknown',
            ),
          ),
        );
      },
    );

    test('keeps absolute and relative audio pitch commands distinct', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('set-pitch', 'clip.set_pitch_semitones', <String, dynamic>{
            'clip_id': 'audio-clip',
            'pitch_semitones': 3,
          }),
          _command(
            'adjust-pitch',
            'clip.adjust_pitch_semitones',
            <String, dynamic>{'clip_id': 'audio-clip', 'delta_semitones': -2},
          ),
        ]),
      );

      expect(plan.commands, hasLength(2));
      expect(plan.commands.first.arguments, contains('pitch_semitones'));
      expect(plan.commands.last.arguments, contains('delta_semitones'));
    });

    test('rejects malformed audio pitch command values', () {
      for (final invalid in <Map<String, dynamic>>[
        _command('set', 'clip.set_pitch_semitones', <String, dynamic>{
          'clip_id': 'audio-clip',
          'pitch_semitones': 13,
        }),
        _command('adjust', 'clip.adjust_pitch_semitones', <String, dynamic>{
          'clip_id': 'audio-clip',
          'delta_semitones': -25,
        }),
        _command('extra', 'clip.set_pitch_semitones', <String, dynamic>{
          'clip_id': 'audio-clip',
          'pitch_semitones': 3,
          'mode': 'set',
        }),
      ]) {
        expect(
          () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[invalid])),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('keeps absolute and relative audio stretch commands distinct', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command(
            'set-length',
            'clip.set_timeline_length_beats',
            <String, dynamic>{
              'clip_id': 'audio-clip',
              'length_beats': 12,
              'preserve_pitch': true,
            },
          ),
          _command(
            'scale-length',
            'clip.scale_timeline_length',
            <String, dynamic>{
              'clip_id': 'audio-clip',
              'factor': 0.5,
              'preserve_pitch': false,
            },
          ),
        ]),
      );

      expect(plan.commands, hasLength(2));
      expect(plan.commands.first.arguments, contains('length_beats'));
      expect(plan.commands.last.arguments, contains('factor'));
      expect(plan.commands.first.arguments['preserve_pitch'], isTrue);
      expect(plan.commands.last.arguments['preserve_pitch'], isFalse);
    });

    test('rejects malformed audio stretch command values', () {
      for (final invalid in <Map<String, dynamic>>[
        _command('zero', 'clip.set_timeline_length_beats', <String, dynamic>{
          'clip_id': 'audio-clip',
          'length_beats': 0,
          'preserve_pitch': true,
        }),
        _command('negative', 'clip.scale_timeline_length', <String, dynamic>{
          'clip_id': 'audio-clip',
          'factor': -1,
          'preserve_pitch': false,
        }),
        _command(
          'missing-mode',
          'clip.scale_timeline_length',
          <String, dynamic>{'clip_id': 'audio-clip', 'factor': 2},
        ),
        _command('extra', 'clip.set_timeline_length_beats', <String, dynamic>{
          'clip_id': 'audio-clip',
          'length_beats': 8,
          'preserve_pitch': true,
          'mode': 'stretch',
        }),
      ]) {
        expect(
          () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[invalid])),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('accepts explicit source tempo and tempo-follow mode commands', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('source', 'clip.set_source_tempo_bpm', <String, dynamic>{
            'clip_id': 'audio-clip',
            'source_tempo_bpm': 92,
          }),
          _command('follow', 'clip.set_tempo_follow_mode', <String, dynamic>{
            'clip_id': 'audio-clip',
            'mode': 'preserve_pitch',
          }),
        ]),
      );

      expect(plan.commands, hasLength(2));
      expect(plan.commands.first.arguments['source_tempo_bpm'], 92);
      expect(plan.commands.last.arguments['mode'], 'preserve_pitch');
    });

    test('accepts automatic clip and project tempo commands', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('align', 'clip.align_tempo_to_project', <String, dynamic>{
            'clip_id': 'audio-clip',
            'mode': 'preserve_pitch',
          }),
          _command('project', 'project.set_tempo_from_clip', <String, dynamic>{
            'clip_id': 'audio-clip',
            'mode': 'repitch',
          }),
        ]),
      );

      expect(plan.commands, hasLength(2));
      expect(plan.commands.first.arguments['mode'], 'preserve_pitch');
      expect(plan.commands.last.arguments['mode'], 'repitch');
    });

    test('rejects malformed automatic tempo commands', () {
      for (final invalid in <Map<String, dynamic>>[
        _command('mode', 'clip.align_tempo_to_project', <String, dynamic>{
          'clip_id': 'audio-clip',
          'mode': 'automatic',
        }),
        _command('missing', 'project.set_tempo_from_clip', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('extra', 'project.set_tempo_from_clip', <String, dynamic>{
          'clip_id': 'audio-clip',
          'mode': 'repitch',
          'bpm': 120,
        }),
      ]) {
        expect(
          () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[invalid])),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('accepts silence trim and first-sound destination variants', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('trim', 'clip.trim_silence', <String, dynamic>{
            'clip_id': 'audio-clip',
            'edges': 'both',
            'padding_ms': 8,
          }),
          _command('align', 'clip.align_first_sound', <String, dynamic>{
            'clip_id': 'audio-clip',
            'destination': <String, dynamic>{'kind': 'project_beat', 'beat': 4},
          }),
          _command('snap', 'clip.align_first_sound', <String, dynamic>{
            'clip_id': 'audio-clip',
            'destination': <String, dynamic>{'kind': 'nearest_bar'},
          }),
        ]),
      );

      expect(plan.commands, hasLength(3));
      expect(plan.commands.first.arguments['edges'], 'both');
    });

    test('rejects malformed silence and first-sound commands', () {
      for (final invalid in <Map<String, dynamic>>[
        _command('edge', 'clip.trim_silence', <String, dynamic>{
          'clip_id': 'audio-clip',
          'edges': 'middle',
          'padding_ms': 8,
        }),
        _command('padding', 'clip.trim_silence', <String, dynamic>{
          'clip_id': 'audio-clip',
          'edges': 'both',
          'padding_ms': 501,
        }),
        _command('kind', 'clip.align_first_sound', <String, dynamic>{
          'clip_id': 'audio-clip',
          'destination': <String, dynamic>{'kind': 'nearest_grid'},
        }),
        _command('extra', 'clip.align_first_sound', <String, dynamic>{
          'clip_id': 'audio-clip',
          'destination': <String, dynamic>{'kind': 'nearest_beat', 'beat': 2},
        }),
      ]) {
        expect(
          () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[invalid])),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('rejects invalid source tempo and tempo-follow mode commands', () {
      for (final invalid in <Map<String, dynamic>>[
        _command('tempo', 'clip.set_source_tempo_bpm', <String, dynamic>{
          'clip_id': 'audio-clip',
          'source_tempo_bpm': 10,
        }),
        _command('mode', 'clip.set_tempo_follow_mode', <String, dynamic>{
          'clip_id': 'audio-clip',
          'mode': 'automatic',
        }),
      ]) {
        expect(
          () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[invalid])),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('rejects malformed core clip command fields', () {
      for (final invalid in <Map<String, dynamic>>[
        _command('trim', 'clip.trim_to_range', <String, dynamic>{
          'clip_id': 'audio-clip',
          'start_beat': -1,
          'end_beat': 4,
        }),
        _command('split', 'clip.split_at', <String, dynamic>{
          'clip_id': 'audio-clip',
          'at_beat': -1,
        }),
        _command('duplicate', 'clip.duplicate_to', <String, dynamic>{
          'clip_id': 'audio-clip',
          'destination_row_id': 100,
          'start_beat': 2,
          'repeat_count': 2,
        }),
        _command('delete', 'clip.delete', <String, dynamic>{}),
      ]) {
        expect(
          () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[invalid])),
          throwsA(isA<AiV3ContractException>()),
        );
      }
    });

    test('rejects duplicate command ids and outcome mismatches', () {
      expect(
        () => AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('same', 'row.rename', <String, dynamic>{
              'row_id': 100,
              'new_name': 'A',
            }),
            _command('same', 'row.rename', <String, dynamic>{
              'row_id': 100,
              'new_name': 'B',
            }),
          ]),
        ),
        throwsA(isA<AiV3ContractException>()),
      );
      final invalid = _plan(const <Map<String, dynamic>>[])
        ..['outcome'] = 'plan';
      expect(
        () => AiV3Plan.fromJson(invalid),
        throwsA(isA<AiV3ContractException>()),
      );
    });

    test('accepts respond, clarify, and unsupported terminal outcomes', () {
      for (final outcome in const <String>['respond', 'unsupported']) {
        final raw = _plan(const <Map<String, dynamic>>[])
          ..['outcome'] = outcome;
        expect(AiV3Plan.fromJson(raw).outcome, outcome);
      }
      final clarify = _plan(const <Map<String, dynamic>>[])
        ..['outcome'] = 'clarify'
        ..['user_message'] = 'Which vocal row?'
        ..['question_options'] = <String>['Lead vocal', 'Backing vocal'];
      expect(AiV3Plan.fromJson(clarify).outcome, 'clarify');

      final openClarify = _plan(const <Map<String, dynamic>>[])
        ..['outcome'] = 'clarify'
        ..['user_message'] = 'Which part should I change?';
      expect(AiV3Plan.fromJson(openClarify).questionOptions, isEmpty);
    });

    test('accepts long user messages and clarification options', () {
      final longMessage = _plan(const <Map<String, dynamic>>[])
        ..['user_message'] = List<String>.filled(2000, 'a').join();
      expect(AiV3Plan.fromJson(longMessage).userMessage, hasLength(2000));

      final longOption = _plan(const <Map<String, dynamic>>[])
        ..['outcome'] = 'clarify'
        ..['user_message'] = 'Which option?'
        ..['question_options'] = <String>[
          List<String>.filled(1000, 'a').join(),
        ];
      expect(
        AiV3Plan.fromJson(longOption).questionOptions.single,
        hasLength(1000),
      );
    });

    test('round-trips complete plans and rejects undeclared fields', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('mute', 'row.set_muted', <String, dynamic>{
            'row_id': 100,
            'muted': true,
          }),
        ]),
      );
      expect(AiV3Plan.fromJson(plan.toJson()).commands, hasLength(1));

      final extraRoot = _plan(const <Map<String, dynamic>>[])
        ..['unexpected'] = true;
      expect(
        () => AiV3Plan.fromJson(extraRoot),
        throwsA(isA<AiV3ContractException>()),
      );
      final extraArgument = _plan(<Map<String, dynamic>>[
        _command('mute', 'row.set_muted', <String, dynamic>{
          'row_id': 100,
          'muted': true,
          'unexpected': true,
        }),
      ]);
      expect(
        () => AiV3Plan.fromJson(extraArgument),
        throwsA(isA<AiV3ContractException>()),
      );
    });
  });

  group('V3 factual preparation', () {
    test('production guitars are range-aware AI instruments', () async {
      final catalog = jsonDecode(
        File('assets/instruments/index.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final guitarEntries = (catalog['presets'] as List<dynamic>)
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .where((entry) => entry['category'] == 'Guitars')
          .toList(growable: false);
      expect(guitarEntries, hasLength(2));

      final guitarIds = guitarEntries
          .map((entry) => entry['id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      expect(
        guitarIds,
        containsAll(<String>[
          'sfz.guitar.steel_acoustic',
          'sfz.guitar.clean_electric',
        ]),
      );

      final data = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(_context().data)) as Map,
      );
      data['instruments'] = guitarIds;
      final loader = SfzDefinitionLoader();
      final rangesById = <String, List<Map<String, int>>>{};
      for (final entry in guitarEntries) {
        final sfzPath =
            'assets/instruments/${entry['pack']}/${entry['preset']}';
        final definition = await loader.load(sfzPath);
        expect(definition, isNotNull, reason: sfzPath);
        rangesById[entry['id'].toString()] = compactMidiPitchRanges(
          definition!.playableInputPitches(remapPitch: (pitch) => pitch),
        );
      }
      expect(rangesById['sfz.guitar.steel_acoustic'], <Map<String, int>>[
        <String, int>{'low': 40, 'high': 84},
      ]);
      expect(rangesById['sfz.guitar.clean_electric'], <Map<String, int>>[
        <String, int>{'low': 40, 'high': 86},
      ]);

      for (final guitarId in guitarIds) {
        final guitarData = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(data)) as Map,
        );
        guitarData['instrument_catalog'] = guitarEntries
            .map(
              (entry) => <String, dynamic>{
                'instrument_id': entry['id'],
                'name': entry['name'],
                'playable_pitch_ranges': rangesById[entry['id']],
              },
            )
            .toList(growable: false);
        final rows = (guitarData['rows'] as List).whereType<Map>().toList();
        rows.singleWhere((row) => row['row_id'] == 200)['instrument_id'] =
            guitarId;
        final clips = (guitarData['clips'] as List).whereType<Map>().toList();
        clips.singleWhere(
          (clip) => clip['clip_id'] == 'midi-clip',
        )['instrument_id'] = guitarId;
        final context = AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'production-$guitarId',
          data: guitarData,
        );
        final prepared = const AiV3CommandPreparer().prepare(
          plan: AiV3Plan.fromJson(
            _plan(<Map<String, dynamic>>[
              _command('compose', 'midi.create_clip', <String, dynamic>{
                'destination': <String, dynamic>{'row_id': 200},
                'start_beat': 0.0,
                'length_beats': 1.0,
                'notes': <Map<String, dynamic>>[_note(52, 0.0, 1.0)],
              }),
            ]),
          ),
          context: context,
        );

        expect(prepared.actions, hasLength(1));
        expect(prepared.actions.single.type, 'midi_compose');
        expect(prepared.actions.single.data['instrument_id'], guitarId);

        final unavailablePitch = rangesById[guitarId]!.first['low']! - 1;
        for (final commandType in <String>[
          'midi.create_clip',
          'midi.replace_notes',
          'midi.append_notes',
        ]) {
          final arguments = commandType == 'midi.create_clip'
              ? <String, dynamic>{
                  'destination': <String, dynamic>{'row_id': 200},
                  'start_beat': 0.0,
                  'length_beats': 1.0,
                  'notes': <Map<String, dynamic>>[
                    _note(unavailablePitch, 0.0, 1.0),
                  ],
                }
              : <String, dynamic>{
                  'clip_id': 'midi-clip',
                  'notes': <Map<String, dynamic>>[
                    _note(unavailablePitch, 0.0, 1.0),
                  ],
                };
          expect(
            () => const AiV3CommandPreparer().prepare(
              plan: AiV3Plan.fromJson(
                _plan(<Map<String, dynamic>>[
                  _command('invalid', commandType, arguments),
                ]),
              ),
              context: context,
            ),
            throwsA(
              isA<AiV3PreparationException>().having(
                (error) => error.code,
                'code',
                'v3_midi_instrument_pitch_unavailable',
              ),
            ),
          );
        }
      }
    });

    test(
      'prepares exact row instrument swaps and simulates later commands',
      () {
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('instrument', 'row.set_instrument', <String, dynamic>{
              'row_id': 200,
              'instrument_id': 'bass',
            }),
            _command('create', 'midi.create_clip', <String, dynamic>{
              'destination': <String, dynamic>{'row_id': 200},
              'start_beat': 0.0,
              'length_beats': 1.0,
              'notes': <Map<String, dynamic>>[_note(48, 0.0, 1.0)],
            }),
          ]),
        );
        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        );

        expect(prepared.actions, hasLength(2));
        expect(prepared.actions.first.type, 'v3_row_set_instrument');
        expect(prepared.actions.first.data['instrument_id'], 'bass');
        expect((prepared.actions.first.data['target'] as Map)['row_id'], 200);
        expect(prepared.actions.last.type, 'midi_compose');
        expect(prepared.actions.last.data['instrument_id'], 'bass');
        expect(
          prepared.receipts.first['verified_label'],
          'Changed Keys instrument to another instrument',
        );
        expect(
          prepared.receipts.first['verified_l10n_key'],
          'Changed {row} instrument to {instrument}',
        );
        expect(prepared.receipts.first['verified_l10n_args'], <String, String>{
          'row': 'Keys',
          'instrument': 'another instrument',
        });
      },
    );

    test(
      'rewrites a preserved instrument without allowing it to be selected',
      () {
        final data = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(_context().data)) as Map,
        );
        final row = (data['rows'] as List).whereType<Map>().singleWhere(
          (value) => value['row_id'] == 200,
        );
        row['instrument_id'] = 'paid-marimba';
        final clip = (data['clips'] as List).whereType<Map>().singleWhere(
          (value) => value['clip_id'] == 'midi-clip',
        );
        clip['instrument_id'] = 'paid-marimba';
        data['instruments'] = <String>['piano', 'bass'];
        data['instrument_catalog'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'instrument_id': 'piano',
            'name': 'Piano',
            'playable_pitch_ranges': <Map<String, int>>[
              <String, int>{'low': 21, 'high': 108},
            ],
          },
          <String, dynamic>{
            'instrument_id': 'bass',
            'name': 'Bass',
            'playable_pitch_ranges': <Map<String, int>>[
              <String, int>{'low': 28, 'high': 72},
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
        final context = AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'preserved-marimba',
          data: data,
        );

        final prepared = const AiV3CommandPreparer().prepare(
          plan: AiV3Plan.fromJson(
            _plan(<Map<String, dynamic>>[
              _command('rewrite', 'midi.replace_notes', <String, dynamic>{
                'clip_id': 'midi-clip',
                'notes': <Map<String, dynamic>>[_note(60, 0.0, 1.0)],
              }),
            ]),
          ),
          context: context,
        );

        expect(prepared.actions, hasLength(1));
        expect(prepared.actions.single.type, 'midi_compose');
        expect(prepared.actions.single.data['operation'], 'replace_notes');
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: AiV3Plan.fromJson(
              _plan(<Map<String, dynamic>>[
                _command('select', 'row.set_instrument', <String, dynamic>{
                  'row_id': 200,
                  'instrument_id': 'paid-marimba',
                }),
              ]),
            ),
            context: context,
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_instrument_id_unknown',
            ),
          ),
        );
      },
    );

    test(
      'propagates an instrument swap to existing MIDI before rewrite and mix',
      () {
        final data = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(_context().data)) as Map,
        );
        final clips = (data['clips'] as List).whereType<Map>().toList();
        clips.singleWhere(
          (clip) => clip['clip_id'] == 'midi-clip',
        )['instrument_id'] = 'piano';
        data['instrument_catalog'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'instrument_id': 'piano',
            'name': 'Piano',
            'playable_pitch_ranges': <Map<String, int>>[
              <String, int>{'low': 36, 'high': 36},
            ],
          },
          <String, dynamic>{
            'instrument_id': 'bass',
            'name': 'Replacement instrument',
            'playable_pitch_ranges': <Map<String, int>>[
              <String, int>{'low': 60, 'high': 72},
            ],
          },
        ];
        final context = AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'instrument-rewrite-state',
          data: data,
        );
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('instrument', 'row.set_instrument', <String, dynamic>{
              'row_id': 200,
              'instrument_id': 'bass',
            }),
            _command('rewrite', 'midi.replace_notes', <String, dynamic>{
              'clip_id': 'midi-clip',
              'notes': <Map<String, dynamic>>[_note(60, 0.0, 1.0)],
            }),
            _command('balance', 'mix.apply_goal', <String, dynamic>{
              'target': <String, dynamic>{'scope': 'all_rows'},
              'intents': <Map<String, dynamic>>[
                <String, dynamic>{
                  'kind': 'balance',
                  'direction': null,
                  'descriptor': null,
                },
              ],
              'intensity': 0.5,
              'execution_profile': 'producer_safe',
              'audibility': 'noticeable',
              'style_tags': <String>['orchestral'],
              'reset_fx': false,
              'reference': null,
            }),
          ]),
        );

        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: context,
        );

        expect(
          prepared.receipts.first['verified_label'],
          'Changed Keys instrument to Replacement instrument',
        );
        expect(prepared.receipts.first['verified_l10n_args'], <String, String>{
          'row': 'Keys',
          'instrument': 'Replacement instrument',
        });
        expect(prepared.actions.map((action) => action.type), <String>[
          'v3_row_set_instrument',
          'midi_compose',
          'v3_deferred_mix_goal',
        ]);
        expect(prepared.receipts, hasLength(3));
        expect(
          prepared.receipts[1]['verified_label'],
          'Replaced notes in Keys',
        );
        expect(prepared.receipts[1]['verified_l10n_args'], <String, String>{
          'target': 'Keys',
        });
      },
    );

    test('instrument receipts never expose internal catalog ids', () {
      const internalId = 'sfz.vsco_2_ce_1_1_0_tubularbells';
      final data = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(_context().data)) as Map,
      );
      data['instruments'] = <String>['piano', internalId];
      data['instrument_catalog'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'instrument_id': internalId,
          'name': 'Tubular Bells',
          'playable_pitch_ranges': <Map<String, int>>[
            <String, int>{'low': 48, 'high': 84},
          ],
        },
      ];
      final prepared = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('instrument', 'row.set_instrument', <String, dynamic>{
              'row_id': 200,
              'instrument_id': internalId,
            }),
          ]),
        ),
        context: AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'private-instrument-receipt',
          data: data,
        ),
      );

      expect(
        prepared.receipts.single['verified_label'],
        'Changed Keys instrument to Tubular Bells',
      );
      expect(prepared.receipts.single['verified_l10n_args'], <String, String>{
        'row': 'Keys',
        'instrument': 'Tubular Bells',
      });
      expect(jsonEncode(prepared.receipts), isNot(contains(internalId)));
    });

    test('receipt display fields never fall back to row or clip ids', () {
      final data = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(_context().data)) as Map,
      );
      for (final row in (data['rows'] as List).whereType<Map>()) {
        row['name'] = '';
      }
      for (final clip in (data['clips'] as List).whereType<Map>()) {
        clip['name'] = '';
      }
      final prepared = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('unmute', 'row.set_muted', <String, dynamic>{
              'row_id': 200,
              'muted': false,
            }),
            _command('move', 'clip.move_by_beats', <String, dynamic>{
              'clip_id': 'audio-clip',
              'delta_beats': 1.0,
            }),
          ]),
        ),
        context: AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'private-resource-receipts',
          data: data,
        ),
      );

      final displayText = prepared.receipts
          .expand(
            (receipt) => <Object?>[
              receipt['preview_label'],
              receipt['verified_label'],
              receipt['verified_l10n_args'],
            ],
          )
          .join(' ');
      expect(displayText, contains('that row'));
      expect(displayText, contains('that clip'));
      expect(displayText, isNot(contains('200')));
      expect(displayText, isNot(contains('audio-clip')));
    });

    test('matches shared state-contract fixtures', () {
      final fixture = jsonDecode(
        File('test/fixtures/ai_v3_state_contract_cases.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'shared-state-contract',
        data: Map<String, dynamic>.from(fixture['context'] as Map),
      );

      for (final rawCase in (fixture['cases'] as List).whereType<Map>()) {
        final fixtureCase = Map<String, dynamic>.from(rawCase);
        final commands = (fixtureCase['commands'] as List)
            .whereType<Map>()
            .map((command) => Map<String, dynamic>.from(command))
            .toList(growable: false);
        final plan = AiV3Plan.fromJson(_plan(commands));
        if (fixtureCase['accepted'] == true) {
          final prepared = const AiV3CommandPreparer().prepare(
            plan: plan,
            context: context,
          );
          expect(prepared.receipts, hasLength(commands.length));
          expect(
            prepared.actions.first.data['instrument_id'],
            fixtureCase['final_instrument_id'],
            reason: fixtureCase['id'].toString(),
          );
        } else {
          expect(
            () => const AiV3CommandPreparer().prepare(
              plan: plan,
              context: context,
            ),
            throwsA(
              isA<AiV3PreparationException>().having(
                (error) => error.code,
                'code',
                fixtureCase['client_error'],
              ),
            ),
            reason: fixtureCase['id'].toString(),
          );
        }
      }
    });

    test(
      'row instrument preparation is idempotent and rejects bad targets',
      () {
        final already = const AiV3CommandPreparer().prepare(
          plan: AiV3Plan.fromJson(
            _plan(<Map<String, dynamic>>[
              _command('same', 'row.set_instrument', <String, dynamic>{
                'row_id': 200,
                'instrument_id': 'piano',
              }),
            ]),
          ),
          context: _context(),
        );
        expect(already.actions, isEmpty);
        expect(already.receipts.single['status'], 'already_satisfied');

        for (final value in <({int rowId, String instrumentId, String code})>[
          (rowId: 999, instrumentId: 'bass', code: 'v3_row_id_unknown'),
          (
            rowId: 100,
            instrumentId: 'bass',
            code: 'v3_instrument_row_required',
          ),
          (
            rowId: 200,
            instrumentId: 'missing',
            code: 'v3_instrument_id_unknown',
          ),
        ]) {
          expect(
            () => const AiV3CommandPreparer().prepare(
              plan: AiV3Plan.fromJson(
                _plan(<Map<String, dynamic>>[
                  _command('bad', 'row.set_instrument', <String, dynamic>{
                    'row_id': value.rowId,
                    'instrument_id': value.instrumentId,
                  }),
                ]),
              ),
              context: _context(),
            ),
            throwsA(
              isA<AiV3PreparationException>().having(
                (error) => error.code,
                'code',
                value.code,
              ),
            ),
          );
        }
      },
    );

    test('allows all-row mixing for playable MIDI without analyzed audio', () {
      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      final rows = (data['rows'] as List).cast<Map>();
      rows[0]['mix_processing_supported'] = false;
      rows[0]['has_usable_signal'] = false;
      rows[1]['mix_processing_supported'] = true;
      rows[1]['has_usable_signal'] = false;
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'midi-only-mix',
        data: data,
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: _allRowsMixPlan(),
        context: context,
      );

      expect(prepared.actions.single.type, 'v3_mix_goal');
      expect(prepared.actions.single.data['target'], <String, dynamic>{
        'scope': 'all_rows',
      });
    });

    test('rejects all-row mixing when no row can produce playback', () {
      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      final rows = (data['rows'] as List).cast<Map>();
      for (final row in rows) {
        row['mix_processing_supported'] = false;
      }
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'empty-mix',
        data: data,
      );

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: _allRowsMixPlan(),
          context: context,
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_mix_audio_missing',
          ),
        ),
      );
    });

    test('rejects row, group, and master mixing without playable material', () {
      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      final rows = (data['rows'] as List).cast<Map>();
      for (final row in rows) {
        row['mix_processing_supported'] = false;
      }
      data['groups'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'group_id': 'empty-group',
          'name': 'Empty group',
          'member_row_ids': <int>[100, 200],
        },
      ];
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'unready-mix-targets',
        data: data,
      );

      for (final target in <Map<String, dynamic>>[
        <String, dynamic>{'scope': 'row', 'row_id': 100},
        <String, dynamic>{'scope': 'group', 'group_id': 'empty-group'},
        <String, dynamic>{'scope': 'master'},
      ]) {
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: _mixPlanForTarget(target),
            context: context,
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_mix_audio_missing',
            ),
          ),
          reason: target.toString(),
        );
      }
    });

    test('deleting the last clip makes a later row mix unavailable', () {
      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      data['rows'] = <Map<String, dynamic>>[
        Map<String, dynamic>.from((data['rows'] as List).first as Map),
      ];
      data['clips'] = <Map<String, dynamic>>[
        Map<String, dynamic>.from((data['clips'] as List).first as Map),
      ];
      data['project'] = <String, dynamic>{
        ...Map<String, dynamic>.from(data['project'] as Map),
        'row_capacity': <String, dynamic>{
          'current_rows': 1,
          'max_rows': 32,
          'can_create': true,
        },
      };
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'delete-last-clip-before-mix',
        data: data,
      );
      final mix = _mixPlanForTarget(<String, dynamic>{
        'scope': 'row',
        'row_id': 100,
      }).commands.single;
      final plan = AiV3Plan(
        outcome: 'plan',
        userMessage: 'Delete and mix.',
        commands: <AiV3Command>[
          const AiV3Command(
            commandId: 'delete',
            type: 'clip.delete',
            arguments: <String, dynamic>{'clip_id': 'audio-clip'},
          ),
          mix,
        ],
      );

      expect(
        () => const AiV3CommandPreparer().prepare(plan: plan, context: context),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_mix_audio_missing',
          ),
        ),
      );
    });

    test('generated row must be populated before a deferred row mix', () {
      Map<String, dynamic> ref(String commandId, String output) =>
          <String, dynamic>{'command_id': commandId, 'output': output};
      Map<String, dynamic> create = _command(
        'created',
        'row.create',
        <String, dynamic>{
          'name': 'Generated drums',
          'lane': <String, dynamic>{'kind': 'audio'},
          'position': <String, dynamic>{'kind': 'end'},
        },
      );
      final mix = _command('mix', 'mix.apply_goal', <String, dynamic>{
        'target': <String, dynamic>{
          'scope': 'row',
          'row_ref': ref('created', 'row'),
        },
        'intents': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 'reverb',
            'direction': 'up',
            'descriptor': null,
          },
        ],
        'intensity': 0.5,
        'execution_profile': 'producer_safe',
        'audibility': 'noticeable',
        'style_tags': const <String>[],
        'reset_fx': false,
        'reference': null,
      });

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: AiV3Plan.fromJson(
            _plan(<Map<String, dynamic>>[create, mix]),
            allowResourceRefs: true,
          ),
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_mix_audio_missing',
          ),
        ),
      );

      final populated = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            create,
            _command('place', 'sample.place', <String, dynamic>{
              'destination': <String, dynamic>{
                'row_ref': ref('created', 'row'),
              },
              'placements': <Map<String, dynamic>>[
                <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
              ],
            }),
            mix,
          ]),
          allowResourceRefs: true,
        ),
        context: _context(),
      );
      expect(populated.actions.last.type, 'v3_deferred_mix_goal');
    });

    test('deleting a populated generated row removes later mix readiness', () {
      Map<String, dynamic> ref(String commandId, String output) =>
          <String, dynamic>{'command_id': commandId, 'output': output};
      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      for (final row in (data['rows'] as List).whereType<Map>()) {
        row['mix_processing_supported'] = false;
      }
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'delete-generated-row-before-mix',
        data: data,
      );
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('created', 'row.create', <String, dynamic>{
            'name': 'Temporary audio',
            'lane': <String, dynamic>{'kind': 'audio'},
            'position': <String, dynamic>{'kind': 'end'},
          }),
          _command('place', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{'row_ref': ref('created', 'row')},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          }),
          _command('delete-row', 'row.delete', <String, dynamic>{
            'row_ref': ref('created', 'row'),
          }),
          _mixPlanForTarget(<String, dynamic>{'scope': 'master'})
              .commands
              .single
              .toJson(),
        ]),
        allowResourceRefs: true,
      );

      expect(
        () => const AiV3CommandPreparer().prepare(plan: plan, context: context),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_mix_audio_missing',
          ),
        ),
      );
    });

    test('duplicating into an empty row makes that row mixable', () {
      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      final rows = (data['rows'] as List).whereType<Map>().toList();
      rows[1]
        ..['lane_kind'] = 'audio'
        ..['instrument_id'] = null
        ..['mix_processing_supported'] = false;
      data['clips'] = (data['clips'] as List)
          .whereType<Map>()
          .where((clip) => clip['row_id'] != 200)
          .toList(growable: false);
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'duplicate-then-mix-empty-row',
        data: data,
      );
      final mix = _mixPlanForTarget(<String, dynamic>{
        'scope': 'row',
        'row_id': 200,
      }).commands.single;
      final plan = AiV3Plan(
        outcome: 'plan',
        userMessage: 'Duplicate and mix.',
        commands: <AiV3Command>[
          const AiV3Command(
            commandId: 'duplicate',
            type: 'clip.duplicate_to',
            arguments: <String, dynamic>{
              'clip_id': 'audio-clip',
              'destination_row_id': 200,
              'start_beat': 8,
            },
          ),
          mix,
        ],
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: context,
      );
      expect(prepared.actions.last.type, 'v3_deferred_mix_goal');
    });

    test('deleting both split outputs removes source-row mix readiness', () {
      Map<String, dynamic> ref(String output) => <String, dynamic>{
        'command_id': 'split',
        'output': output,
      };
      final mix = _mixPlanForTarget(<String, dynamic>{
        'scope': 'row',
        'row_id': 100,
      }).commands.single.toJson();
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('split', 'clip.split_at', <String, dynamic>{
            'clip_id': 'audio-clip',
            'at_beat': 4,
          }),
          _command('delete-left', 'clip.delete', <String, dynamic>{
            'clip_ref': ref('left_clip'),
          }),
          _command('delete-right', 'clip.delete', <String, dynamic>{
            'clip_ref': ref('right_clip'),
          }),
          mix,
        ]),
        allowResourceRefs: true,
      );

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_mix_audio_missing',
          ),
        ),
      );
    });

    test(
      'prepares a stable-id mix goal without exposing concrete MixActions',
      () {
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('mix', 'mix.apply_goal', <String, dynamic>{
              'target': <String, dynamic>{'scope': 'row', 'row_id': 100},
              'intents': <Map<String, dynamic>>[
                <String, dynamic>{
                  'kind': 'reverb',
                  'direction': 'up',
                  'descriptor': null,
                },
              ],
              'intensity': 0.4,
              'execution_profile': 'producer_safe',
              'audibility': 'subtle',
              'style_tags': const <String>[],
              'reset_fx': false,
              'reference': null,
            }),
          ]),
        );
        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        );
        expect(prepared.actions.single.type, 'v3_mix_goal');
        final target = prepared.actions.single.data['target'] as Map;
        expect(target['row_id'], 100);
        expect(target['row_index'], 0);
        expect(prepared.preview, contains('Mix Audio'));
      },
    );

    test('rejects a reference that is the processing row', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('mix', 'mix.apply_goal', <String, dynamic>{
            'target': <String, dynamic>{'scope': 'row', 'row_id': 100},
            'intents': <Map<String, dynamic>>[
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
            'reference': <String, dynamic>{
              'row_id': 100,
              'mode': 'full_mix',
              'closeness': 'balanced',
            },
          }),
        ]),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_mix_reference_equals_target',
          ),
        ),
      );
    });

    test('resolves stable ids and expands compound commands', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('mute', 'row.set_muted', <String, dynamic>{
            'row_id': 100,
            'muted': true,
          }),
          _command('rename', 'row.rename', <String, dynamic>{
            'row_id': 200,
            'new_name': 'Soft Keys',
          }),
          _command('sample', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{
              'new_row': <String, dynamic>{'name': 'Kick'},
            },
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions.map((action) => action.type), <String>[
        'row_mute',
        'row_rename',
        'row_create',
        'sample_insert',
      ]);
      expect(prepared.stateDigest, 'state-1');
    });

    test('prepares trim bounds as absolute project beats', () {
      final context = _contextWithAudioClipBounds(
        startBeat: 12,
        lengthBeats: 8,
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('trim', 'clip.trim_to_range', <String, dynamic>{
              'clip_id': 'audio-clip',
              'start_beat': 14,
              'end_beat': 18,
            }),
          ]),
        ),
        context: context,
      );
      expect(prepared.actions, hasLength(1));
      expect(prepared.actions.single.type, 'clip_edit');
      expect(prepared.actions.single.data['delta_trim_start_ms'], 1000);
      expect(prepared.actions.single.data['delta_trim_end_ms'], -1000);
      expect(prepared.actions.single.data['new_start_ms'], 7000);

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: AiV3Plan.fromJson(
            _plan(<Map<String, dynamic>>[
              _command('relative', 'clip.trim_to_range', <String, dynamic>{
                'clip_id': 'audio-clip',
                'start_beat': 2,
                'end_beat': 6,
              }),
            ]),
          ),
          context: context,
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_clip_trim_bounds_invalid',
          ),
        ),
      );
    });

    test('canonicalizes only unique effect parameter casing', () {
      final prepared = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('effect', 'effect.ensure_configured', <String, dynamic>{
              'row_id': 100,
              'effect_id': 'Reverb',
              'parameters': <Map<String, dynamic>>[
                <String, dynamic>{'parameter_id': 'mix', 'value': 0.25},
              ],
            }),
          ]),
        ),
        context: _context(),
      );
      expect(prepared.actions.single.type, 'v3_effect_configure');
      expect(prepared.actions.single.data['parameters'], <String, dynamic>{
        'Mix': 0.25,
      });

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: AiV3Plan.fromJson(
            _plan(<Map<String, dynamic>>[
              _command('effect', 'effect.ensure_configured', <String, dynamic>{
                'row_id': 100,
                'effect_id': 'Reverb',
                'parameters': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'parameter_id': 'not-a-parameter',
                    'value': 0.25,
                  },
                ],
              }),
            ]),
          ),
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_effect_parameter_unknown',
          ),
        ),
      );
    });

    test(
      'repairs verified aliases and rejects conflicting duplicates safely',
      () {
        final context = _contextWithEffects(<String, List<String>>{
          'Distortion': <String>['Drive', 'DC Offset', 'Pre Shape'],
        });
        final prepared = const AiV3CommandPreparer().prepare(
          plan: AiV3Plan.fromJson(
            _plan(<Map<String, dynamic>>[
              _command('effect', 'effect.ensure_configured', <String, dynamic>{
                'row_id': 100,
                'effect_id': 'Distortion',
                'parameters': <Map<String, dynamic>>[
                  <String, dynamic>{'parameter_id': 'drive', 'value': 0.7},
                  <String, dynamic>{'parameter_id': 'Offset', 'value': 0.2},
                  <String, dynamic>{'parameter_id': 'drive', 'value': 0.7},
                ],
              }),
            ]),
          ),
          context: context,
        );
        expect(prepared.actions.single.data['parameters'], <String, dynamic>{
          'Drive': 0.7,
          'DC Offset': 0.2,
        });

        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: AiV3Plan.fromJson(
              _plan(<Map<String, dynamic>>[
                _command(
                  'effect',
                  'effect.ensure_configured',
                  <String, dynamic>{
                    'row_id': 100,
                    'effect_id': 'Distortion',
                    'parameters': <Map<String, dynamic>>[
                      <String, dynamic>{'parameter_id': 'Drive', 'value': 0.4},
                      <String, dynamic>{'parameter_id': 'drive', 'value': 0.8},
                    ],
                  },
                ),
              ]),
            ),
            context: context,
          ),
          throwsA(
            isA<AiV3PreparationException>()
                .having(
                  (error) => error.code,
                  'code',
                  'v3_effect_parameter_duplicate',
                )
                .having(
                  (error) => error.diagnostic,
                  'diagnostic',
                  containsPair('effect_id', 'Distortion'),
                )
                .having(
                  (error) => error.diagnostic,
                  'diagnostic',
                  containsPair('command_index', 0),
                ),
          ),
        );
      },
    );

    test(
      'prepares the reproduced MIDI, effects, and mix plan without drops',
      () {
        final context = _contextWithEffects(<String, List<String>>{
          'Distortion': <String>['Drive', 'Mix'],
          'EQ 3-Band': <String>['Low Gain', 'Mid Gain', 'High Gain'],
          'Compressor': <String>['Threshold', 'Ratio', 'Mix'],
        });
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('rewrite', 'midi.replace_notes', <String, dynamic>{
              'clip_id': 'midi-clip',
              'notes': <Map<String, dynamic>>[
                _note(52, 0, 1),
                _note(55, 0, 1),
                _note(59, 0, 1),
              ],
            }),
            _command(
              'distortion',
              'effect.ensure_configured',
              <String, dynamic>{
                'row_id': 200,
                'effect_id': 'Distortion',
                'parameters': <Map<String, dynamic>>[
                  <String, dynamic>{'parameter_id': 'Drive', 'value': 0.7},
                  <String, dynamic>{'parameter_id': 'Mix', 'value': 0.8},
                ],
              },
            ),
            _command('eq', 'effect.ensure_configured', <String, dynamic>{
              'row_id': 200,
              'effect_id': 'EQ 3-Band',
              'parameters': <Map<String, dynamic>>[
                <String, dynamic>{'parameter_id': 'Mid Gain', 'value': 0.6},
              ],
            }),
            _command(
              'compressor',
              'effect.ensure_configured',
              <String, dynamic>{
                'row_id': 200,
                'effect_id': 'Compressor',
                'parameters': <Map<String, dynamic>>[
                  <String, dynamic>{'parameter_id': 'Mix', 'value': 0.65},
                ],
              },
            ),
            _command('balance', 'mix.apply_goal', <String, dynamic>{
              'target': <String, dynamic>{'scope': 'all_rows'},
              'intents': <Map<String, dynamic>>[
                <String, dynamic>{
                  'kind': 'balance',
                  'direction': null,
                  'descriptor': null,
                },
              ],
              'intensity': 0.6,
              'execution_profile': 'producer_safe',
              'audibility': 'noticeable',
              'style_tags': <String>['rock'],
              'reset_fx': false,
              'reference': null,
            }),
          ]),
        );

        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: context,
        );
        expect(prepared.receipts, hasLength(5));
        expect(
          prepared.receipts.map((receipt) => receipt['command_id']),
          <String>['rewrite', 'distortion', 'eq', 'compressor', 'balance'],
        );
        expect(prepared.actions, hasLength(5));
        expect(prepared.actions.map((action) => action.type), <String>[
          'midi_compose',
          'v3_effect_configure',
          'v3_effect_configure',
          'v3_effect_configure',
          'v3_deferred_mix_goal',
        ]);
      },
    );

    test(
      'prepares exact stable sample replacement and rejects dead targets',
      () {
        final replace = _command('replace', 'sample.replace', <String, dynamic>{
          'clip_id': 'audio-clip',
          'asset_id': 'kick-1',
        });
        final prepared = const AiV3CommandPreparer().prepare(
          plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[replace])),
          context: _context(),
        );
        expect(prepared.actions, hasLength(1));
        expect(prepared.actions.single.type, 'v3_sample_replace');
        expect(prepared.actions.single.data['asset_id'], 'kick-1');
        expect(prepared.actions.single.data['library_path'], 'Pack/Kick.wav');
        expect(
          (prepared.actions.single.data['target'] as Map)['clip_id'],
          'audio-clip',
        );

        final deleteThenReplace = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
            replace,
          ]),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: deleteThenReplace,
            context: _context(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_clip_id_unknown',
            ),
          ),
        );
      },
    );

    test('embedded MIDI destination expands to exactly one row creation', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{
              'new_row': <String, dynamic>{
                'name': 'Dark Keys',
                'instrument_id': 'piano',
              },
            },
            'start_beat': 0,
            'length_beats': 4,
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 60,
                'start_beat': 0,
                'length_beats': 4,
                'velocity': 0.8,
              },
            ],
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions.map((action) => action.type), <String>[
        'row_create',
        'midi_compose',
      ]);
    });

    test('delete then embedded MIDI destination uses the final row index', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('delete-keys', 'row.delete', <String, dynamic>{
            'row_id': 200,
          }),
          _command('replacement', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{
              'new_row': <String, dynamic>{
                'name': 'Replacement Keys',
                'instrument_id': 'piano',
              },
            },
            'start_beat': 0,
            'length_beats': 4,
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 60,
                'start_beat': 0,
                'length_beats': 4,
                'velocity': 0.8,
              },
            ],
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions.map((action) => action.type), <String>[
        'row_delete',
        'row_create',
        'midi_compose',
      ]);
      expect((prepared.actions.last.data['target'] as Map)['row_index'], 1);
    });

    test(
      'canonicalizes exact standalone and embedded MIDI row duplication',
      () {
        Map<String, dynamic> createRow(String id) => _command(
          id,
          'row.create',
          <String, dynamic>{
            'name': 'House Drums',
            'lane': <String, dynamic>{'kind': 'midi', 'instrument_id': 'piano'},
            'position': <String, dynamic>{'kind': 'end'},
          },
        );
        Map<String, dynamic> createClip(String id) =>
            _command(id, 'midi.create_clip', <String, dynamic>{
              'destination': <String, dynamic>{
                'new_row': <String, dynamic>{
                  'name': 'House Drums',
                  'instrument_id': 'piano',
                },
              },
              'start_beat': 0,
              'length_beats': 4,
              'notes': <Map<String, dynamic>>[
                <String, dynamic>{
                  'pitch': 36,
                  'start_beat': 0,
                  'length_beats': 1,
                  'velocity': 0.8,
                },
              ],
            });

        for (final commands in <List<Map<String, dynamic>>>[
          <Map<String, dynamic>>[createRow('row'), createClip('clip')],
          <Map<String, dynamic>>[createClip('clip'), createRow('row')],
        ]) {
          final plan = AiV3Plan.fromJson(_plan(commands));
          final prepared = const AiV3CommandPreparer().prepare(
            plan: plan,
            context: _context(),
          );
          expect(
            prepared.plan.commands.map((command) => command.commandId),
            <String>['clip'],
          );
          expect(prepared.actions.map((action) => action.type), <String>[
            'row_create',
            'midi_compose',
          ]);
        }
      },
    );

    test(
      'canonicalizes exact standalone and embedded sample row duplication',
      () {
        final sample = _command('sample', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{
            'new_row': <String, dynamic>{'name': 'Percussion'},
          },
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        });
        final row = _command('row', 'row.create', <String, dynamic>{
          'name': 'Percussion',
          'lane': <String, dynamic>{'kind': 'audio'},
          'position': <String, dynamic>{'kind': 'end'},
        });

        for (final commands in <List<Map<String, dynamic>>>[
          <Map<String, dynamic>>[row, sample],
          <Map<String, dynamic>>[sample, row],
        ]) {
          final plan = AiV3Plan.fromJson(_plan(commands));
          final prepared = const AiV3CommandPreparer().prepare(
            plan: plan,
            context: _context(),
          );
          expect(
            prepared.plan.commands.map((command) => command.commandId),
            <String>['sample'],
          );
          expect(prepared.actions.map((action) => action.type), <String>[
            'row_create',
            'sample_insert',
          ]);
        }
      },
    );

    test('rejects ambiguous repeated embedded destination rows', () {
      final sample = _command('sample', 'sample.place', <String, dynamic>{
        'destination': <String, dynamic>{
          'new_row': <String, dynamic>{'name': 'Percussion'},
        },
        'placements': <Map<String, dynamic>>[
          <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
        ],
      });
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          sample,
          <String, dynamic>{...sample, 'command_id': 'sample-2'},
        ]),
      );

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_embedded_destination_row_conflict',
          ),
        ),
      );
    });

    test(
      'rejects multiple standalone rows matching one embedded destination',
      () {
        Map<String, dynamic> row(String id) =>
            _command(id, 'row.create', <String, dynamic>{
              'name': 'Percussion',
              'lane': <String, dynamic>{'kind': 'audio'},
              'position': <String, dynamic>{'kind': 'end'},
            });
        final sample = _command('sample', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{
            'new_row': <String, dynamic>{'name': 'Percussion'},
          },
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        });
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[row('row-1'), row('row-2'), sample]),
        );

        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: plan,
            context: _context(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_embedded_destination_row_conflict',
            ),
          ),
        );
      },
    );

    test('allows factually distinct standalone and embedded rows', () {
      final plans = <AiV3Plan>[
        AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('row', 'row.create', <String, dynamic>{
              'name': 'Percussion',
              'lane': <String, dynamic>{'kind': 'audio'},
              'position': <String, dynamic>{'kind': 'end'},
            }),
            _command('sample', 'sample.place', <String, dynamic>{
              'destination': <String, dynamic>{
                'new_row': <String, dynamic>{'name': 'Percussion 2'},
              },
              'placements': <Map<String, dynamic>>[
                <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
              ],
            }),
          ]),
        ),
        AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('row', 'row.create', <String, dynamic>{
              'name': 'Keys',
              'lane': <String, dynamic>{
                'kind': 'midi',
                'instrument_id': 'piano',
              },
              'position': <String, dynamic>{'kind': 'before', 'row_id': 100},
            }),
            _command('midi', 'midi.create_clip', <String, dynamic>{
              'destination': <String, dynamic>{
                'new_row': <String, dynamic>{
                  'name': 'Keys',
                  'instrument_id': 'piano',
                },
              },
              'start_beat': 0,
              'length_beats': 4,
              'notes': <Map<String, dynamic>>[
                <String, dynamic>{
                  'pitch': 60,
                  'start_beat': 0,
                  'length_beats': 1,
                  'velocity': 0.8,
                },
              ],
            }),
          ]),
        ),
      ];

      for (final plan in plans) {
        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        );
        expect(
          prepared.actions.where((action) => action.type == 'row_create'),
          hasLength(2),
        );
      }
    });

    test('rejects unknown targets', () {
      final unknown = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('rename', 'row.rename', <String, dynamic>{
            'row_id': 999,
            'new_name': 'Missing',
          }),
        ]),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: unknown,
          context: _context(),
        ),
        throwsA(isA<AiV3PreparationException>()),
      );
    });

    test('prepares semantic row controls with stable targets', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('adjust-gain', 'row.adjust_gain_db', <String, dynamic>{
            'row_id': 100,
            'delta_db': -2,
          }),
          _command('gain', 'row.set_gain_db', <String, dynamic>{
            'row_id': 100,
            'gain_db': -6,
          }),
          _command('pan', 'row.adjust_pan', <String, dynamic>{
            'row_id': 100,
            'delta_signed': -2,
          }),
          _command('solo', 'row.set_soloed', <String, dynamic>{
            'row_id': 100,
            'soloed': true,
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions[0].data['operation'], 'adjust_gain');
      expect(prepared.actions[0].data['delta_db'], -2);
      expect(prepared.actions[1].data['operation'], 'set_gain');
      expect(prepared.actions[1].data['gain_db'], -6);
      expect(prepared.actions[2].data['operation'], 'adjust_pan');
      expect(prepared.actions[2].data['delta'], -2);
      expect(prepared.actions[3].data['operation'], 'set_soloed');
      expect(prepared.actions[3].data['soloed'], isTrue);
      for (final action in prepared.actions) {
        expect((action.data['target'] as Map)['row_id'], 100);
        expect((action.data['target'] as Map)['row_index'], 0);
      }
    });

    test('prepares row selection, color, and mute final states', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('select', 'row.select', <String, dynamic>{'row_id': 200}),
          _command('color', 'row.set_color', <String, dynamic>{
            'row_id': 100,
            'color': 'magenta',
          }),
          _command('toggle-result', 'row.set_muted', <String, dynamic>{
            'row_id': 200,
            'muted': false,
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions.map((action) => action.type), <String>[
        'row_select',
        'row_color_edit',
        'row_mute',
      ]);
      for (final action in prepared.actions) {
        final target = action.data['target'] as Map;
        expect(target['row_id'], isIn(<int>[100, 200]));
        expect(target['row_index'], isIn(<int>[0, 1]));
      }
      expect(prepared.actions[1].data['color'], 'magenta');
      expect(prepared.actions[2].data['operation'], 'set_muted');
      expect(prepared.actions[2].data['muted'], isFalse);
    });

    test('row metadata commands detect already-satisfied state', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('select', 'row.select', <String, dynamic>{'row_id': 100}),
          _command('color', 'row.set_color', <String, dynamic>{
            'row_id': 200,
            'color': 'blue',
          }),
          _command('mute', 'row.set_muted', <String, dynamic>{
            'row_id': 100,
            'muted': false,
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions, isEmpty);
      expect(
        prepared.receipts.map((receipt) => receipt['status']),
        everyElement('already_satisfied'),
      );
    });

    test('prepares ordered row role overrides and skips satisfied setters', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('same', 'row.set_role_override', <String, dynamic>{
            'row_id': 100,
            'role': 'vocals',
          }),
          _command('set', 'row.set_role_override', <String, dynamic>{
            'row_id': 100,
            'role': 'drums',
          }),
          _command('same-again', 'row.set_role_override', <String, dynamic>{
            'row_id': 100,
            'role': 'drums',
          }),
          _command('clear', 'row.set_role_override', <String, dynamic>{
            'row_id': 100,
            'role': null,
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions.map((action) => action.type), <String>[
        'v3_row_role_override',
        'v3_row_role_override',
      ]);
      expect(prepared.actions.first.data['role'], 'drums');
      expect(prepared.actions.last.data['role'], isNull);
      expect(prepared.receipts.map((receipt) => receipt['status']), <String>[
        'already_satisfied',
        'prepared',
        'already_satisfied',
        'prepared',
      ]);
    });

    test('prepares one row-scoped phone cleanup action with exact facts', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('cleanup', 'row.apply_phone_mic_cleanup', <String, dynamic>{
            'row_id': 100,
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextForPhoneMicCleanup(secondAudioClip: true),
      );

      expect(prepared.actions, hasLength(1));
      final action = prepared.actions.single;
      expect(action.type, 'v3_phone_mic_cleanup');
      expect((action.data['target'] as Map)['row_id'], 100);
      expect((action.data['target'] as Map)['row_index'], 0);
      expect(action.data['effect_ids'], aiV3PhoneMicCleanupEffectIds);
      expect(action.data['audio_clip_ids'], <String>[
        'audio-clip',
        'audio-clip-2',
      ]);
      expect(action.data['preset'], aiV3PhoneMicCleanupPreset);
      expect(prepared.preview, contains('all 2 audio clips'));
    });

    test('phone cleanup rejects unavailable service, effects, and audio', () {
      final cleanup = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('cleanup', 'row.apply_phone_mic_cleanup', <String, dynamic>{
            'row_id': 100,
          }),
        ]),
      );
      for (final context in <AiV3CoreContext>[
        _contextForPhoneMicCleanup(includeService: false),
        _contextForPhoneMicCleanup(includeAllEffects: false),
      ]) {
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: cleanup,
            context: context,
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_phone_cleanup_unavailable',
            ),
          ),
        );
      }
      final midiRowCleanup = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command(
            'cleanup-midi',
            'row.apply_phone_mic_cleanup',
            <String, dynamic>{'row_id': 200},
          ),
        ]),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: midiRowCleanup,
          context: _contextForPhoneMicCleanup(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_phone_cleanup_audio_missing',
          ),
        ),
      );
    });

    test('phone cleanup enforces ordering and same-row sound conflicts', () {
      final conflict = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('cleanup', 'row.apply_phone_mic_cleanup', <String, dynamic>{
            'row_id': 100,
          }),
          _command('effect', 'effect.ensure_configured', <String, dynamic>{
            'row_id': 100,
            'effect_id': 'Compressor',
            'parameters': const <Object>[],
          }),
        ]),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: conflict,
          context: _contextForPhoneMicCleanup(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_phone_cleanup_effect_conflict',
          ),
        ),
      );

      final cleanupThenDelete = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('cleanup', 'row.apply_phone_mic_cleanup', <String, dynamic>{
            'row_id': 100,
          }),
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
        ]),
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: cleanupThenDelete,
        context: _contextForPhoneMicCleanup(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'v3_phone_mic_cleanup',
        'row_delete',
      ]);

      final deleteThenCleanup = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
          _command('cleanup', 'row.apply_phone_mic_cleanup', <String, dynamic>{
            'row_id': 100,
          }),
        ]),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: deleteThenCleanup,
          context: _contextForPhoneMicCleanup(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_row_id_unknown',
          ),
        ),
      );
    });

    test('phone cleanup allows an independent surviving row edit', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('cleanup', 'row.apply_phone_mic_cleanup', <String, dynamic>{
            'row_id': 100,
          }),
          _command('rename', 'row.rename', <String, dynamic>{
            'row_id': 200,
            'new_name': 'Keys Preserved',
          }),
        ]),
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextForPhoneMicCleanup(),
      );
      expect(prepared.actions.map((action) => action.type), <String>[
        'v3_phone_mic_cleanup',
        'row_rename',
      ]);
    });

    test('prepares audio and MIDI row creation plus stable row deletion', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('audio', 'row.create', <String, dynamic>{
            'name': 'Vocal Double',
            'lane': <String, dynamic>{'kind': 'audio'},
            'position': <String, dynamic>{'kind': 'before', 'row_id': 200},
          }),
          _command('midi', 'row.create', <String, dynamic>{
            'name': 'Soft Keys',
            'lane': <String, dynamic>{'kind': 'midi', 'instrument_id': 'piano'},
            'position': <String, dynamic>{'kind': 'end'},
          }),
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions.map((action) => action.type), <String>[
        'row_create',
        'row_create',
        'row_delete',
      ]);
      expect(prepared.actions[0].data['position'], 'above');
      expect((prepared.actions[0].data['target'] as Map)['row_id'], 200);
      expect(prepared.actions[0].data['lane_kind'], 'audio');
      expect(prepared.actions[1].data['position'], 'end');
      expect(prepared.actions[1].data['lane_kind'], 'instrument');
      expect(prepared.actions[1].data['instrument_id'], 'piano');
      expect((prepared.actions[2].data['target'] as Map)['row_id'], 100);
    });

    test('row lifecycle preparation rejects unavailable factual state', () {
      final unknownInstrument = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('midi', 'row.create', <String, dynamic>{
            'name': 'Unknown',
            'lane': <String, dynamic>{
              'kind': 'midi',
              'instrument_id': 'missing',
            },
            'position': <String, dynamic>{'kind': 'end'},
          }),
        ]),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: unknownInstrument,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_instrument_id_unknown',
          ),
        ),
      );

      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      data['rows'] = <Map<String, dynamic>>[
        Map<String, dynamic>.from((data['rows'] as List).first as Map),
      ];
      (data['project'] as Map)['row_capacity'] = <String, dynamic>{
        'current_rows': 1,
        'max_rows': 32,
        'can_create': true,
      };
      final deleteLast = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
        ]),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: deleteLast,
          context: AiV3CoreContext(
            profile: AiV3ContextProfile.essential,
            stateDigest: 'single',
            data: data,
          ),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_row_delete_last_remaining',
          ),
        ),
      );
    });

    test('ordered row deletion makes later row-owned targets unavailable', () {
      final cases = <List<Map<String, dynamic>>>[
        <Map<String, dynamic>>[
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
          _command('rename', 'row.rename', <String, dynamic>{
            'row_id': 100,
            'new_name': 'Gone',
          }),
        ],
        <Map<String, dynamic>>[
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
          _command('role', 'row.set_role_override', <String, dynamic>{
            'row_id': 100,
            'role': 'drums',
          }),
        ],
        <Map<String, dynamic>>[
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
          _command('effect', 'effect.ensure_configured', <String, dynamic>{
            'row_id': 100,
            'effect_id': 'Reverb',
            'parameters': <Map<String, dynamic>>[
              <String, dynamic>{'parameter_id': 'Mix', 'value': 0.2},
            ],
          }),
        ],
        <Map<String, dynamic>>[
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
          _command('fade', 'automation.gain_fade', <String, dynamic>{
            'row_id': 100,
            'start_beat': 0,
            'end_beat': 4,
            'from_gain_db': -120,
            'to_level': 'current',
          }),
        ],
        <Map<String, dynamic>>[
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
          _command('move', 'clip.move_by_beats', <String, dynamic>{
            'clip_id': 'audio-clip',
            'delta_beats': 1,
          }),
        ],
        <Map<String, dynamic>>[
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
          _command('sample', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 100},
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          }),
        ],
        <Map<String, dynamic>>[
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 200}),
          _command('midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 200},
            'start_beat': 0,
            'length_beats': 4,
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 60,
                'start_beat': 0,
                'length_beats': 1,
                'velocity': 0.8,
              },
            ],
          }),
        ],
      ];

      for (final commands in cases) {
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: AiV3Plan.fromJson(_plan(commands)),
            context: _context(),
          ),
          throwsA(isA<AiV3PreparationException>()),
        );
      }
    });

    test('ordered deletion preserves reverse and unrelated operations', () {
      final prepared = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('rename-deleted', 'row.rename', <String, dynamic>{
              'row_id': 100,
              'new_name': 'Before Delete',
            }),
            _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
            _command('rename-alive', 'row.rename', <String, dynamic>{
              'row_id': 200,
              'new_name': 'Still Here',
            }),
          ]),
        ),
        context: _context(),
      );

      expect(prepared.actions.map((action) => action.type), <String>[
        'row_rename',
        'row_delete',
        'row_rename',
      ]);
    });

    test(
      'topology changes defer mixing but block stale topology operations',
      () {
        Map<String, dynamic> createRow() =>
            _command('create', 'row.create', <String, dynamic>{
              'name': 'Extra',
              'lane': <String, dynamic>{'kind': 'audio'},
              'position': <String, dynamic>{'kind': 'end'},
            });

        final laterMix = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            createRow(),
            _command('mix', 'mix.apply_goal', <String, dynamic>{
              'target': <String, dynamic>{'scope': 'row', 'row_id': 100},
              'intents': <Map<String, dynamic>>[
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
              'reference': null,
            }),
          ]),
        );
        final preparedMix = const AiV3CommandPreparer().prepare(
          plan: laterMix,
          context: _context(),
        );
        expect(preparedMix.actions.map((action) => action.type), <String>[
          'row_create',
          'v3_deferred_mix_goal',
        ]);
        expect(preparedMix.actions.last.data['target'], <String, dynamic>{
          'scope': 'row',
          'row_id': 100,
        });

        final laterDuplicate = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            createRow(),
            _command('duplicate', 'clip.duplicate_to', <String, dynamic>{
              'clip_id': 'audio-clip',
              'destination_row_id': 100,
              'start_beat': 12,
            }),
          ]),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: laterDuplicate,
            context: _context(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_row_id_unknown',
            ),
          ),
        );
      },
    );

    test('index-dependent operations remain valid before row deletion', () {
      final prepared = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('duplicate', 'clip.duplicate_to', <String, dynamic>{
              'clip_id': 'audio-clip',
              'destination_row_id': 100,
              'start_beat': 12,
            }),
            _command('mix', 'mix.apply_goal', <String, dynamic>{
              'target': <String, dynamic>{'scope': 'row', 'row_id': 100},
              'intents': <Map<String, dynamic>>[
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
              'reference': null,
            }),
            _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
          ]),
        ),
        context: _context(),
      );

      expect(prepared.actions.map((action) => action.type), <String>[
        'clip_edit',
        'v3_deferred_mix_goal',
        'row_delete',
      ]);
    });

    test(
      'duplicate deletion and group mixing after membership change fail',
      () {
        final duplicateDelete = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('delete-1', 'row.delete', <String, dynamic>{
              'row_id': 100,
            }),
            _command('delete-2', 'row.delete', <String, dynamic>{
              'row_id': 100,
            }),
          ]),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: duplicateDelete,
            context: _context(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_row_id_unknown',
            ),
          ),
        );

        final groupedData =
            jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
        final groupedRows = (groupedData['rows'] as List).cast<Map>();
        groupedRows[0]['group_id'] = 'music';
        groupedRows[1]['group_id'] = 'music';
        groupedData['groups'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'group_id': 'music',
            'name': 'Music',
            'member_row_ids': <int>[100, 200],
            'collapsed': false,
            'effects': const <Object>[],
          },
        ];
        final groupedContext = AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'grouped-ordering',
          data: groupedData,
        );
        final groupThenMix = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('remove', 'group.remove_row', <String, dynamic>{
              'group_id': 'music',
              'row_id': 200,
            }),
            _command('mix', 'mix.apply_goal', <String, dynamic>{
              'target': <String, dynamic>{
                'scope': 'group',
                'group_id': 'music',
              },
              'intents': <Map<String, dynamic>>[
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
              'reference': null,
            }),
          ]),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: groupThenMix,
            context: groupedContext,
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_group_id_unknown',
            ),
          ),
        );
      },
    );

    test('prepares grouping from exact stable identities', () {
      final create = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('group', 'group.create', <String, dynamic>{
            'row_ids': <int>[200, 100],
            'name': 'Music',
          }),
        ]),
      );
      final created = const AiV3CommandPreparer().prepare(
        plan: create,
        context: _context(),
      );
      expect(created.actions.single.type, 'v3_group_edit');
      expect(created.actions.single.data['operation'], 'create');
      expect(created.actions.single.data['row_ids'], <int>[100, 200]);
      expect(created.actions.single.data['expected_row_order'], <int>[
        100,
        200,
      ]);
      expect(
        created.actions.single.data['group_id'].toString(),
        startsWith('v3_group_'),
      );

      final groupedData =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      final groupedRows = (groupedData['rows'] as List).cast<Map>();
      groupedRows[0]['group_id'] = 'music';
      groupedRows[1]['group_id'] = 'music';
      groupedData['groups'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'group_id': 'music',
          'name': 'Music',
          'member_row_ids': <int>[100, 200],
          'collapsed': false,
          'effects': const <Object>[],
        },
      ];
      final groupedContext = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'grouped',
        data: groupedData,
      );
      final remove = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('remove', 'group.remove_row', <String, dynamic>{
              'group_id': 'music',
              'row_id': 200,
            }),
          ]),
        ),
        context: groupedContext,
      );
      expect(remove.actions.single.data['dissolves_group'], isTrue);
      final collapse = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('collapse', 'group.set_collapsed', <String, dynamic>{
              'group_id': 'music',
              'collapsed': true,
            }),
          ]),
        ),
        context: groupedContext,
      );
      expect(collapse.actions.single.data['collapsed'], isTrue);
      final noOp = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('expanded', 'group.set_collapsed', <String, dynamic>{
              'group_id': 'music',
              'collapsed': false,
            }),
          ]),
        ),
        context: groupedContext,
      );
      expect(noOp.actions, isEmpty);
      expect(noOp.receipts.single['status'], 'already_satisfied');
    });

    test('prepares exact core clip edits from stable ids and beats', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('trim', 'clip.trim_to_range', <String, dynamic>{
            'clip_id': 'audio-clip',
            'start_beat': 1,
            'end_beat': 7,
          }),
          _command('split', 'clip.split_at', <String, dynamic>{
            'clip_id': 'midi-clip',
            'at_beat': 8,
          }),
          _command('duplicate', 'clip.duplicate_to', <String, dynamic>{
            'clip_id': 'audio-clip',
            'destination_row_id': 100,
            'start_beat': 12,
          }),
          _command('delete', 'clip.delete', <String, dynamic>{
            'clip_ref': <String, dynamic>{
              'command_id': 'split',
              'output': 'right_clip',
            },
          }),
        ]),
        allowResourceRefs: true,
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions, hasLength(4));
      expect(
        prepared.actions.map((action) => action.data['operation']),
        <String>['trim', 'cut', 'duplicate', 'delete'],
      );
      expect(prepared.actions[0].data['delta_trim_start_ms'], 500.0);
      expect(prepared.actions[0].data['delta_trim_end_ms'], -500.0);
      expect(prepared.actions[0].data['new_start_ms'], 500.0);
      expect(prepared.actions[1].data['cut_ms'], 4000.0);
      expect(prepared.actions[2].data['paste_start_ms'], 6000.0);
      expect(prepared.actions[2].data['row_index'], 0);
      for (final action in prepared.actions) {
        final target = action.data['target'] as Map;
        expect(target['clip_id'] ?? target['resource_ref'], isNotEmpty);
      }
    });

    test('prepares exact absolute and relative audio pitch values', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('adjust', 'clip.adjust_pitch_semitones', <String, dynamic>{
            'clip_id': 'audio-clip',
            'delta_semitones': -2,
          }),
          _command('set', 'clip.set_pitch_semitones', <String, dynamic>{
            'clip_id': 'audio-clip',
            'pitch_semitones': 3,
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions, hasLength(2));
      expect(prepared.actions[0].data['operation'], 'pitch_shift');
      expect(prepared.actions[0].data['mode'], 'set');
      expect(prepared.actions[0].data['new_pitch_semitones'], 0.0);
      expect(prepared.actions[1].data['new_pitch_semitones'], 3.0);
      for (final action in prepared.actions) {
        expect((action.data['target'] as Map)['clip_id'], 'audio-clip');
      }
    });

    test('prepares absolute and relative visible audio lengths', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('set', 'clip.set_timeline_length_beats', <String, dynamic>{
            'clip_id': 'audio-clip',
            'length_beats': 12,
            'preserve_pitch': true,
          }),
          _command('scale', 'clip.scale_timeline_length', <String, dynamic>{
            'clip_id': 'audio-clip',
            'factor': 0.5,
            'preserve_pitch': false,
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions, hasLength(2));
      expect(prepared.actions[0].data['operation'], 'stretch');
      expect(prepared.actions[0].data['timeline_duration_ms'], 6000.0);
      expect(prepared.actions[0].data['preserve_pitch'], isTrue);
      expect(prepared.actions[1].data['timeline_duration_ms'], 2000.0);
      expect(prepared.actions[1].data['preserve_pitch'], isFalse);
      for (final action in prepared.actions) {
        expect((action.data['target'] as Map)['clip_id'], 'audio-clip');
      }
    });

    test('prepares source tempo and explicit tempo-follow mode', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('source', 'clip.set_source_tempo_bpm', <String, dynamic>{
            'clip_id': 'audio-clip',
            'source_tempo_bpm': 96,
          }),
          _command('follow', 'clip.set_tempo_follow_mode', <String, dynamic>{
            'clip_id': 'audio-clip',
            'mode': 'repitch',
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions, hasLength(2));
      expect(prepared.actions[0].data['operation'], 'set_source_tempo');
      expect(prepared.actions[0].data['source_tempo_bpm'], 96.0);
      expect(prepared.actions[1].data['operation'], 'tempo_follow');
      expect(prepared.actions[1].data['mode'], 'repitch');
      for (final action in prepared.actions) {
        expect((action.data['target'] as Map)['clip_id'], 'audio-clip');
      }
    });

    test('materializes detected tempo into exact existing actions', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('align', 'clip.align_tempo_to_project', <String, dynamic>{
            'clip_id': 'audio-clip',
            'mode': 'preserve_pitch',
          }),
          _command('project', 'project.set_tempo_from_clip', <String, dynamic>{
            'clip_id': 'audio-clip',
            'mode': 'repitch',
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
        detectedTempoByClipId: const <String, double>{'audio-clip': 127.6},
      );

      expect(
        prepared.actions.map((action) => action.data['operation']),
        <Object?>[
          'set_source_tempo',
          'tempo_follow',
          'set_source_tempo',
          'set_tempo',
          'tempo_follow',
        ],
      );
      expect(prepared.actions[0].data['source_tempo_bpm'], 127.6);
      expect(prepared.actions[1].data['mode'], 'preserve_pitch');
      expect(prepared.actions[3].data['tempo_bpm'], 128);
      expect(prepared.actions[3].data['time_stretch_audio'], isFalse);
      expect(prepared.actions[4].data['mode'], 'repitch');
      expect(prepared.preview, contains('127.6 BPM'));
    });

    test('requires a successful local tempo detection before preparation', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('align', 'clip.align_tempo_to_project', <String, dynamic>{
            'clip_id': 'audio-clip',
            'mode': 'preserve_pitch',
          }),
        ]),
      );

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_clip_tempo_detection_unavailable',
          ),
        ),
      );
    });

    test('materializes boundary analysis into exact trim and move actions', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('trim', 'clip.trim_silence', <String, dynamic>{
            'clip_id': 'audio-clip',
            'edges': 'both',
            'padding_ms': 10,
          }),
          _command('align', 'clip.align_first_sound', <String, dynamic>{
            'clip_id': 'audio-clip',
            'destination': <String, dynamic>{'kind': 'project_beat', 'beat': 4},
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
        boundaryAnalysisByClipId: const <String, AiV3ClipBoundaryAnalysis>{
          'audio-clip': AiV3ClipBoundaryAnalysis(
            audibleStartMs: 210,
            audibleEndMs: 3810,
            firstSoundOffsetMs: 210,
          ),
        },
      );

      expect(prepared.actions, hasLength(2));
      expect(prepared.actions[0].data['operation'], 'trim');
      expect(prepared.actions[0].data['delta_trim_start_ms'], 200.0);
      expect(prepared.actions[0].data['delta_trim_end_ms'], -180.0);
      expect(prepared.actions[0].data['new_start_ms'], 200.0);
      expect(prepared.actions[1].data['operation'], 'move');
      expect(prepared.actions[1].data['delta_ms'], 1790.0);
      expect(prepared.actions[1].data['new_alignment_offset_ms'], 1790.0);
    });

    test('prepares nearest grid and playhead first-sound destinations', () {
      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      ((data['clips'] as List).first as Map<String, dynamic>)['start_beat'] =
          2.0;
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'state-1',
        data: data,
      );
      for (final entry in <MapEntry<Map<String, dynamic>, double>>[
        const MapEntry(<String, dynamic>{'kind': 'nearest_beat'}, -210.0),
        const MapEntry(<String, dynamic>{'kind': 'nearest_bar'}, 790.0),
        const MapEntry(<String, dynamic>{'kind': 'playhead'}, 1790.0),
      ]) {
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('align', 'clip.align_first_sound', <String, dynamic>{
              'clip_id': 'audio-clip',
              'destination': entry.key,
            }),
          ]),
        );
        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: context,
          boundaryAnalysisByClipId: const <String, AiV3ClipBoundaryAnalysis>{
            'audio-clip': AiV3ClipBoundaryAnalysis(
              audibleStartMs: 210,
              audibleEndMs: 3810,
              firstSoundOffsetMs: 210,
            ),
          },
        );
        expect(prepared.actions.single.data['delta_ms'], entry.value);
      }
    });

    test('requires usable boundary analysis before preparation', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('trim', 'clip.trim_silence', <String, dynamic>{
            'clip_id': 'audio-clip',
            'edges': 'both',
            'padding_ms': 8,
          }),
        ]),
      );

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_clip_boundary_analysis_unavailable',
          ),
        ),
      );
    });

    test('treats exact source tempo and disabled follow as satisfied', () {
      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      ((data['clips'] as List).first
              as Map<String, dynamic>)['source_tempo_bpm'] =
          120.0;
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'state-1',
        data: data,
      );
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('source', 'clip.set_source_tempo_bpm', <String, dynamic>{
            'clip_id': 'audio-clip',
            'source_tempo_bpm': 120,
          }),
          _command('off', 'clip.set_tempo_follow_mode', <String, dynamic>{
            'clip_id': 'audio-clip',
            'mode': 'off',
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: context,
      );
      expect(prepared.actions, isEmpty);
      expect(
        prepared.receipts.map((receipt) => receipt['status']),
        everyElement('already_satisfied'),
      );
    });

    test('rejects MIDI and stretch values that require engine clamping', () {
      final cases = <({Map<String, dynamic> command, String code})>[
        (
          command: _command(
            'midi',
            'clip.set_timeline_length_beats',
            <String, dynamic>{
              'clip_id': 'midi-clip',
              'length_beats': 8,
              'preserve_pitch': true,
            },
          ),
          code: 'v3_audio_clip_required',
        ),
        (
          command: _command(
            'extreme',
            'clip.scale_timeline_length',
            <String, dynamic>{
              'clip_id': 'audio-clip',
              'factor': 100,
              'preserve_pitch': true,
            },
          ),
          code: 'v3_clip_stretch_out_of_range',
        ),
      ];
      for (final item in cases) {
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[item.command]),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: plan,
            context: _context(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              item.code,
            ),
          ),
        );
      }
    });

    test('treats an exact active stretch as already satisfied', () {
      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      (data['project'] as Map<String, dynamic>)['tempo_stretch_enabled'] = true;
      final clip = ((data['clips'] as List).first as Map<String, dynamic>);
      clip['stretch_to_project_tempo'] = true;
      clip['tempo_stretch_preserve_pitch'] = true;
      clip['source_tempo_bpm'] = 120.0;
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'state-1',
        data: data,
      );
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('noop', 'clip.set_timeline_length_beats', <String, dynamic>{
            'clip_id': 'audio-clip',
            'length_beats': 8,
            'preserve_pitch': true,
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: context,
      );
      expect(prepared.actions, isEmpty);
      expect(prepared.receipts.single['status'], 'already_satisfied');
    });

    test('rejects enabling global stretch when another clip would move', () {
      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      (data['clips'] as List).add(<String, dynamic>{
        'clip_id': 'other-audio-clip',
        'row_id': 100,
        'display_index': 2,
        'kind': 'audio',
        'name': 'Other audio clip',
        'start_beat': 16.0,
        'length_beats': 4.0,
        'timeline_length_beats': 4.0,
        'pitch_semitones': 0.0,
        'stretch_to_project_tempo': true,
        'tempo_stretch_preserve_pitch': true,
        'source_tempo_bpm': 240.0,
        'tempo_warp_mode': 'complex',
      });
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'state-1',
        data: data,
      );
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('stretch', 'clip.scale_timeline_length', <String, dynamic>{
            'clip_id': 'audio-clip',
            'factor': 2,
            'preserve_pitch': true,
          }),
        ]),
      );

      expect(
        () => const AiV3CommandPreparer().prepare(plan: plan, context: context),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_clip_stretch_global_conflict',
          ),
        ),
      );
    });

    test('rejects MIDI and out-of-range final audio pitch', () {
      final cases = <({Map<String, dynamic> command, String code})>[
        (
          command: _command(
            'midi',
            'clip.set_pitch_semitones',
            <String, dynamic>{'clip_id': 'midi-clip', 'pitch_semitones': 3},
          ),
          code: 'v3_audio_clip_required',
        ),
        (
          command: _command(
            'overflow',
            'clip.adjust_pitch_semitones',
            <String, dynamic>{'clip_id': 'audio-clip', 'delta_semitones': 11},
          ),
          code: 'v3_clip_pitch_out_of_range',
        ),
      ];
      for (final item in cases) {
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[item.command]),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: plan,
            context: _context(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              item.code,
            ),
          ),
        );
      }
    });

    test('rejects invalid clip bounds, kinds, and destination lanes', () {
      final cases = <({Map<String, dynamic> command, String code})>[
        (
          command: _command(
            'trim-midi',
            'clip.trim_to_range',
            <String, dynamic>{
              'clip_id': 'midi-clip',
              'start_beat': 5,
              'end_beat': 10,
            },
          ),
          code: 'v3_audio_clip_required',
        ),
        (
          command: _command(
            'trim-expand',
            'clip.trim_to_range',
            <String, dynamic>{
              'clip_id': 'audio-clip',
              'start_beat': 0,
              'end_beat': 9,
            },
          ),
          code: 'v3_clip_trim_bounds_invalid',
        ),
        (
          command: _command('split-edge', 'clip.split_at', <String, dynamic>{
            'clip_id': 'audio-clip',
            'at_beat': 0,
          }),
          code: 'v3_clip_split_point_invalid',
        ),
        (
          command: _command(
            'duplicate-mismatch',
            'clip.duplicate_to',
            <String, dynamic>{
              'clip_id': 'audio-clip',
              'destination_row_id': 200,
              'start_beat': 8,
            },
          ),
          code: 'v3_clip_destination_lane_mismatch',
        ),
      ];

      for (final item in cases) {
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[item.command]),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: plan,
            context: _context(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              item.code,
            ),
          ),
        );
      }
    });

    test('converts gain fades into normalized editor multipliers', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('fade', 'automation.gain_fade', <String, dynamic>{
            'row_id': 100,
            'start_beat': 0,
            'end_beat': 4,
            'from_gain_db': -120,
            'to_level': 'current',
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      final action = prepared.actions.single;
      final points = action.data['points'] as List;

      expect(action.type, 'automation_edit');
      expect(action.data['value_mode'], 'normalized');
      expect(points.first['value'], 0.0);
      expect(points.last['value'], 1.0);
    });

    test(
      'prepares exact normalized automation points and clear by stable ids',
      () {
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('curve', 'automation.set_points', <String, dynamic>{
              'row_id': 100,
              'automation_target_id': 'row:100:mix:pan',
              'points': <Map<String, dynamic>>[
                <String, dynamic>{'beat': 0, 'value_normalized': 0},
                <String, dynamic>{'beat': 2, 'value_normalized': 0.5},
                <String, dynamic>{'beat': 4, 'value_normalized': 1},
              ],
            }),
            _command('clear', 'automation.clear', <String, dynamic>{
              'row_id': 100,
              'automation_target_id': 'fx:reverb:mix',
            }),
          ]),
        );

        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        );
        expect(prepared.actions.map((action) => action.type), <String>[
          'v3_automation_points',
          'v3_automation_points',
        ]);
        expect(prepared.actions.first.data['target'], <String, dynamic>{
          'scope': 'row',
          'row_id': 100,
          'row_index': 0,
          'automation_target_id': 'mix:pan',
        });
        expect(prepared.actions.first.data['points'], <Map<String, dynamic>>[
          <String, dynamic>{'time_ms': 0.0, 'value': 0.0},
          <String, dynamic>{'time_ms': 1000.0, 'value': 0.5},
          <String, dynamic>{'time_ms': 2000.0, 'value': 1.0},
        ]);
        expect(prepared.actions.last.data['operation'], 'clear');
      },
    );

    test(
      'rejects malformed or orphaned exact automation targets and points',
      () {
        final malformed = <Map<String, dynamic>>[
          _command('duplicate', 'automation.set_points', <String, dynamic>{
            'row_id': 100,
            'automation_target_id': 'volume',
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'beat': 1, 'value_normalized': 0.2},
              <String, dynamic>{'beat': 1, 'value_normalized': 0.8},
            ],
          }),
          _command('range', 'automation.set_points', <String, dynamic>{
            'row_id': 100,
            'automation_target_id': 'volume',
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'beat': 0, 'value_normalized': 1.1},
            ],
          }),
        ];
        for (final command in malformed) {
          expect(
            () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[command])),
            throwsA(isA<AiV3ContractException>()),
          );
        }

        final unknownTarget = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('unknown', 'automation.clear', <String, dynamic>{
              'row_id': 100,
              'automation_target_id': 'missing',
            }),
          ]),
        );
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: unknownTarget,
            context: _context(),
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_automation_target_unknown',
            ),
          ),
        );
      },
    );

    test('allows long generated MIDI while keeping note bounds strict', () {
      final validLaterClip = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('later-midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 200},
            'start_beat': 64,
            'length_beats': 16,
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 60,
                'start_beat': 0,
                'length_beats': 1,
                'velocity': 0.8,
              },
            ],
          }),
        ]),
      );
      expect(
        const AiV3CommandPreparer()
            .prepare(plan: validLaterClip, context: _context())
            .actions,
        isNotEmpty,
      );

      final longPlan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 200},
            'start_beat': 64,
            'length_beats': 128,
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 60,
                'start_beat': 127,
                'length_beats': 1,
                'velocity': 0.8,
              },
            ],
          }),
        ]),
      );

      expect(
        const AiV3CommandPreparer()
            .prepare(plan: longPlan, context: _context())
            .actions,
        isNotEmpty,
      );

      final outOfBounds = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 200},
            'start_beat': 64,
            'length_beats': 128,
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 60,
                'start_beat': 127,
                'length_beats': 2,
                'velocity': 0.8,
              },
            ],
          }),
        ]),
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: outOfBounds,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_midi_note_out_of_bounds',
          ),
        ),
      );
    });

    test('rejects new rows when the deterministic capacity is exhausted', () {
      final fullContext = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'state-full',
        data: <String, dynamic>{
          ..._context().data,
          'project': <String, dynamic>{
            ...(_context().data['project'] as Map).cast<String, dynamic>(),
            'row_capacity': <String, dynamic>{
              'current_rows': 2,
              'max_rows': 2,
              'can_create': false,
            },
          },
        },
      );
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('sample', 'sample.place', <String, dynamic>{
            'destination': <String, dynamic>{
              'new_row': <String, dynamic>{'name': 'Kick'},
            },
            'placements': <Map<String, dynamic>>[
              <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
            ],
          }),
        ]),
      );

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: fullContext,
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_row_capacity_exceeded',
          ),
        ),
      );
    });

    test('recognized paid capacity has no product-defined row ceiling', () {
      final data = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(_context().data)) as Map,
      );
      final project = Map<String, dynamic>.from(data['project'] as Map)
        ..['project_capacity_policy'] = aiV3ProjectCapacityPolicy
        ..['row_capacity'] = <String, dynamic>{
          'current_rows': 2,
          'creation_limit': null,
          'can_create': true,
        };
      data['project'] = project;
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('row', 'row.create', <String, dynamic>{
            'name': 'New paid row',
            'lane': <String, dynamic>{'kind': 'audio'},
            'position': <String, dynamic>{'kind': 'end'},
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'dynamic-paid',
          data: data,
        ),
      );
      expect(prepared.actions.single.type, 'row_create');
    });

    test('clip creation is not limited by existing project clip count', () {
      final data = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(_context().data)) as Map,
      );
      final originalAudio = Map<String, dynamic>.from(
        (data['clips'] as List).first as Map,
      );
      data['clips'] = <Map<String, dynamic>>[
        for (var index = 0; index < 599; index++)
          <String, dynamic>{
            ...originalAudio,
            'clip_id': 'existing-audio-$index',
            'display_index': index,
          },
        Map<String, dynamic>.from((data['clips'] as List).last as Map)
          ..['display_index'] = 599,
      ];
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('midi', 'midi.create_clip', <String, dynamic>{
            'destination': <String, dynamic>{'row_id': 200},
            'start_beat': 0,
            'length_beats': 4,
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 60,
                'start_beat': 0,
                'length_beats': 1,
                'velocity': 0.8,
              },
            ],
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'six-hundred-clips',
          data: data,
        ),
      );
      expect(prepared.actions.single.type, 'midi_compose');
    });
  });

  group('V3 transport', () {
    test('accepts only four strict final-state commands', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('play', 'transport.set_playing', <String, dynamic>{
            'playing': true,
          }),
          _command('restart', 'transport.restart', const <String, dynamic>{}),
          _command(
            'metro',
            'transport.set_metronome_enabled',
            <String, dynamic>{'enabled': true},
          ),
          _command('loop', 'transport.set_loop_enabled', <String, dynamic>{
            'enabled': false,
          }),
        ]),
      );

      expect(plan.commands.map((command) => command.type), <String>[
        'transport.set_playing',
        'transport.restart',
        'transport.set_metronome_enabled',
        'transport.set_loop_enabled',
      ]);
      expect(
        () => AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('toggle', 'transport.toggle_playing', const {}),
          ]),
        ),
        throwsA(isA<AiV3ContractException>()),
      );
      expect(
        () => AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('alias', 'transport.play', const {}),
          ]),
        ),
        throwsA(isA<AiV3ContractException>()),
      );
      expect(
        () => AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('extra', 'transport.restart', <String, dynamic>{
              'position': 0,
            }),
          ]),
        ),
        throwsA(isA<AiV3ContractException>()),
      );
      expect(
        () => AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            _command('bad', 'transport.set_loop_enabled', <String, dynamic>{
              'enabled': 1,
            }),
          ]),
        ),
        throwsA(isA<AiV3ContractException>()),
      );
    });

    test('prepares canonical actions in authoritative order', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('loop-on', 'transport.set_loop_enabled', <String, dynamic>{
            'enabled': true,
          }),
          _command('restart', 'transport.restart', const <String, dynamic>{}),
          _command('pause', 'transport.set_playing', <String, dynamic>{
            'playing': false,
          }),
          _command('play', 'transport.set_playing', <String, dynamic>{
            'playing': true,
          }),
        ]),
      );

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(
        prepared.actions.map((action) => action.data['operation']),
        <String>['set_loop_enabled', 'restart', 'set_playing', 'set_playing'],
      );
      expect(
        prepared.actions.map((action) => action.type),
        everyElement('v3_transport'),
      );
      expect(prepared.receipts, hasLength(4));
    });

    test('rejects playback and restart while recording', () {
      final base = _context();
      final recordingContext = AiV3CoreContext(
        profile: base.profile,
        stateDigest: base.stateDigest,
        data: <String, dynamic>{
          ...base.data,
          'transport': <String, dynamic>{
            ...(base.data['transport'] as Map).cast<String, dynamic>(),
            'recording': true,
          },
        },
      );
      for (final command in <Map<String, dynamic>>[
        _command('play', 'transport.set_playing', <String, dynamic>{
          'playing': true,
        }),
        _command('restart', 'transport.restart', const <String, dynamic>{}),
      ]) {
        expect(
          () => const AiV3CommandPreparer().prepare(
            plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[command])),
            context: recordingContext,
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_transport_recording_active',
            ),
          ),
        );
      }
    });
  });

  group('V3 MIDI editing', () {
    Map<String, dynamic> editCommand(
      String id,
      String type, {
      String clipId = 'midi-clip',
      List<Map<String, dynamic>>? notes,
      int subdivision = 16,
      Object? range,
      double decay = 0,
    }) {
      return _command(id, type, switch (type) {
        'midi.replace_notes' => <String, dynamic>{
          'clip_id': clipId,
          'notes': notes,
        },
        'midi.append_notes' => <String, dynamic>{
          'clip_id': clipId,
          'notes': notes,
        },
        'midi.chop_notes' => <String, dynamic>{
          'clip_id': clipId,
          'subdivision': subdivision,
          'range': range,
          'velocity_decay_per_slice': decay,
        },
        _ => throw StateError(type),
      });
    }

    test('accepts strict replace, append, and nullable-range chop shapes', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          editCommand(
            'replace',
            'midi.replace_notes',
            notes: <Map<String, dynamic>>[_note(60, 0, 1)],
          ),
          editCommand(
            'append',
            'midi.append_notes',
            notes: <Map<String, dynamic>>[_note(64, 0.5, 0.5)],
          ),
          editCommand(
            'chop-all',
            'midi.chop_notes',
            subdivision: 32,
            range: null,
            decay: 0.1,
          ),
          editCommand(
            'chop-range',
            'midi.chop_notes',
            subdivision: 8,
            range: <String, dynamic>{'start_beat': 1, 'end_beat': 3},
          ),
        ]),
      );

      expect(plan.commands.map((command) => command.type), <String>[
        'midi.replace_notes',
        'midi.append_notes',
        'midi.chop_notes',
        'midi.chop_notes',
      ]);
      expect(aiV3CommandTypes, hasLength(54));
    });

    test('rejects malformed MIDI edit fields and numeric bounds', () {
      final invalid = <Map<String, dynamic>>[
        editCommand(
          'extra',
          'midi.replace_notes',
          notes: <Map<String, dynamic>>[_note(60, 0, 1)],
        )..['arguments']['extra'] = true,
        editCommand(
          'old-at',
          'midi.append_notes',
          notes: <Map<String, dynamic>>[_note(60, 0, 1)],
        )..['arguments']['at_beat'] = 0,
        editCommand(
          'bad-note',
          'midi.replace_notes',
          notes: <Map<String, dynamic>>[_note(128, 0, 1)],
        ),
        editCommand('bad-subdivision', 'midi.chop_notes', subdivision: 129),
        editCommand(
          'bad-range',
          'midi.chop_notes',
          range: <String, dynamic>{'start_beat': 2, 'end_beat': 2},
        ),
        editCommand('bad-decay', 'midi.chop_notes', decay: 1.1),
      ];

      for (final command in invalid) {
        expect(
          () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[command])),
          throwsA(isA<AiV3ContractException>()),
          reason: command['command_id'].toString(),
        );
      }
    });

    test('serialized plan byte budget replaces generated-note counts', () {
      final notes = List<Map<String, dynamic>>.generate(
        513,
        (index) => _note(127, index * 0.03125, 0.03125, 0.999999),
      );
      final rawPlan = _plan(<Map<String, dynamic>>[
        editCommand('replace-max', 'midi.replace_notes', notes: notes),
      ]);
      expect(AiV3Plan.fromJson(rawPlan).commands, hasLength(1));
      expect(
        utf8.encode(jsonEncode(rawPlan)).length,
        lessThan(aiV3MaxSerializedPlanBytes),
      );

      final oversized = _plan(<Map<String, dynamic>>[
        editCommand('replace', 'midi.replace_notes', notes: notes),
      ])..['padding'] = 'x' * aiV3MaxSerializedPlanBytes;
      expect(
        () => AiV3Plan.fromJson(oversized),
        throwsA(
          isA<AiV3ContractException>().having(
            (error) => error.code,
            'code',
            'v3_provider_plan_too_large',
          ),
        ),
      );
    });

    test('former workload collection counts are byte-budgeted', () {
      final commands = <Map<String, dynamic>>[
        for (var i = 0; i < 40; i++)
          _command('rename-$i', 'row.rename', <String, dynamic>{
            'row_id': 100,
            'new_name': 'Part $i',
          }),
        _command('group', 'group.create', <String, dynamic>{
          'row_ids': <int>[for (var i = 0; i < 33; i++) i + 1],
          'name': 'Large group',
        }),
        _command('glue', 'clip.glue', <String, dynamic>{
          'clip_ids': <String>[for (var i = 0; i < 33; i++) 'clip-$i'],
          'label': 'Combined',
        }),
        _command('effect', 'effect.ensure_configured', <String, dynamic>{
          'row_id': 100,
          'effect_id': 'Large effect',
          'parameters': <Map<String, dynamic>>[
            for (var i = 0; i < 17; i++)
              <String, dynamic>{'parameter_id': 'parameter-$i', 'value': 0.5},
          ],
        }),
        _command('automation', 'automation.set_points', <String, dynamic>{
          'row_id': 100,
          'automation_target_id': 'volume',
          'points': <Map<String, dynamic>>[
            for (var i = 0; i < 129; i++)
              <String, dynamic>{'beat': i.toDouble(), 'value_normalized': 0.5},
          ],
        }),
        _command('samples', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 100},
          'placements': <Map<String, dynamic>>[
            for (var i = 0; i < 129; i++)
              <String, dynamic>{
                'asset_id': 'sample-$i',
                'start_beat': i.toDouble(),
              },
          ],
        }),
      ];
      final rawPlan = _plan(commands);
      expect(
        utf8.encode(jsonEncode(rawPlan)).length,
        lessThan(aiV3MaxSerializedPlanBytes),
      );
      expect(AiV3Plan.fromJson(rawPlan).commands, hasLength(commands.length));
    });

    test('runtime MIDI state uses a byte ceiling instead of a note count', () {
      final oversizedNotes = List<Map<String, dynamic>>.generate(
        70000,
        (_) => _note(60, 0, 1),
        growable: false,
      );
      expect(
        utf8.encode(jsonEncode(oversizedNotes)).length,
        greaterThan(aiV3MaxRuntimeMidiStateBytes),
      );
      final directPlan = AiV3Plan(
        outcome: 'plan',
        userMessage: 'Updated the notes.',
        commands: <AiV3Command>[
          AiV3Command(
            commandId: 'oversized-midi-state',
            type: 'midi.replace_notes',
            arguments: <String, dynamic>{
              'clip_id': 'midi-clip',
              'notes': oversizedNotes,
            },
          ),
        ],
      );
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: directPlan,
          context: _contextWithMidiNotes(<Map<String, dynamic>>[
            _note(60, 0, 1),
          ]),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_midi_result_limit',
          ),
        ),
      );
    });

    test('shared generated-note fixtures pass parsing and preparation', () {
      final fixture = jsonDecode(
        File('backend/llm_proxy/tests/fixtures/generated_midi_budget_v1.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(aiV3GeneratedMidiPolicy, fixture['policy']);
      for (final count in (fixture['counts'] as List).cast<int>()) {
        for (final split in [false, true]) {
          final sizes = split ? [count ~/ 2, count - count ~/ 2] : [count];
          final commands = <Map<String, dynamic>>[
            for (var i = 0; i < sizes.length; i++)
              editCommand(
                'budget-$i',
                'midi.replace_notes',
                notes: [
                  for (var n = 0; n < sizes[i]; n++)
                    Map<String, dynamic>.from(fixture['note'] as Map),
                ],
              ),
          ];
            final plan = AiV3Plan.fromJson(_plan(commands));
            final prepared = const AiV3CommandPreparer().prepare(
              plan: plan,
              context: _contextWithMidiNotes([_note(50, 0, 1)]),
            );
            expect(prepared.actions, isNotEmpty);
          }
        }
    });

    test('simulates replace then append as exact complete note states', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          editCommand(
            'replace',
            'midi.replace_notes',
            notes: <Map<String, dynamic>>[_note(65, 1, 1)],
          ),
          editCommand(
            'append',
            'midi.append_notes',
            notes: <Map<String, dynamic>>[_note(60, 0.5, 0.5)],
          ),
        ]),
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextWithMidiNotes(<Map<String, dynamic>>[_note(50, 0, 1)]),
      );

      expect(prepared.actions, hasLength(2));
      expect(
        prepared.actions.every((action) => action.type == 'midi_compose'),
        isTrue,
      );
      expect(prepared.actions.last.data['operation'], 'replace_notes');
      expect(prepared.actions.last.data['notes'], <Map<String, dynamic>>[
        _note(65, 1, 1),
        _note(60, 8.5, 0.5),
      ]);
      expect(prepared.actions.last.data['final_length_beats'], 9.0);
      expect(prepared.actions.last.data['preserve_clip_state'], isTrue);
    });

    test('repeated appends use each preceding final clip length', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          editCommand(
            'append-one',
            'midi.append_notes',
            notes: <Map<String, dynamic>>[_note(60, 0, 1)],
          ),
          editCommand(
            'append-two',
            'midi.append_notes',
            notes: <Map<String, dynamic>>[_note(64, 0.5, 0.5)],
          ),
        ]),
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextWithMidiNotes(<Map<String, dynamic>>[
          _note(48, 0, 1),
        ], lengthBeats: 4),
      );

      expect(prepared.actions[0].data['notes'], <Map<String, dynamic>>[
        _note(48, 0, 1),
        _note(60, 4, 1),
      ]);
      expect(prepared.actions[0].data['final_length_beats'], 5.0);
      expect(prepared.actions[1].data['notes'], <Map<String, dynamic>>[
        _note(48, 0, 1),
        _note(60, 4, 1),
        _note(64, 5.5, 0.5),
      ]);
      expect(prepared.actions[1].data['final_length_beats'], 6.0);
    });

    test(
      'append continues after existing notes beyond a stale visible end',
      () {
        final plan = AiV3Plan.fromJson(
          _plan(<Map<String, dynamic>>[
            editCommand(
              'append',
              'midi.append_notes',
              notes: <Map<String, dynamic>>[_note(64, 0.5, 0.5)],
            ),
          ]),
        );
        final prepared = const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _contextWithMidiNotes(<Map<String, dynamic>>[
            _note(48, 0, 1),
            _note(55, 4, 3.5),
          ], lengthBeats: 2.5),
        );

        expect(prepared.actions.single.data['notes'], <Map<String, dynamic>>[
          _note(48, 0, 1),
          _note(55, 4, 3.5),
          _note(64, 8, 0.5),
        ]);
        expect(prepared.actions.single.data['final_length_beats'], 8.5);
      },
    );

    test('simulates transpose and append in authoritative planner order', () {
      final transposeThenAppend = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          _command('up', 'midi.transpose', <String, dynamic>{
            'clip_id': 'midi-clip',
            'semitones': 48,
          }),
          _command('down', 'midi.transpose', <String, dynamic>{
            'clip_id': 'midi-clip',
            'semitones': -48,
          }),
          editCommand(
            'append',
            'midi.append_notes',
            notes: <Map<String, dynamic>>[_note(40, 0, 0.5)],
          ),
        ]),
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: transposeThenAppend,
        context: _contextWithMidiNotes(<Map<String, dynamic>>[
          _note(100, 0, 1),
        ]),
      );
      expect(prepared.actions.last.data['notes'], <Map<String, dynamic>>[
        _note(79, 0, 1),
        _note(40, 8, 0.5),
      ]);

      final appendThenTranspose = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          editCommand(
            'append-first',
            'midi.append_notes',
            notes: <Map<String, dynamic>>[_note(70, 0, 0.5)],
          ),
          _command('transpose-last', 'midi.transpose', <String, dynamic>{
            'clip_id': 'midi-clip',
            'semitones': 2,
          }),
        ]),
      );
      final reverse = const AiV3CommandPreparer().prepare(
        plan: appendThenTranspose,
        context: _contextWithMidiNotes(<Map<String, dynamic>>[
          _note(60, 0, 0.5),
        ]),
      );
      expect(
        reverse.actions.map((action) => action.data['operation']),
        <String>['replace_notes', 'transpose_notes'],
      );
    });

    test('chops only the range with deterministic decay and sorting', () {
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          editCommand(
            'chop',
            'midi.chop_notes',
            subdivision: 4,
            range: <String, dynamic>{'start_beat': 1, 'end_beat': 3},
            decay: 0.25,
          ),
        ]),
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextWithMidiNotes(<Map<String, dynamic>>[
          _note(60, 0, 4, 0.5),
        ]),
      );

      expect(prepared.actions.single.data['notes'], <Map<String, dynamic>>[
        _note(60, 0, 1, 0.5),
        _note(60, 1, 1, 0.5),
        _note(60, 2, 1, 0.25),
        _note(60, 3, 1, 0.5),
      ]);
    });

    test('coalesces satisfied replacements and chops during preparation', () {
      final notes = <Map<String, dynamic>>[_note(60, 0, 0.5)];
      final plan = AiV3Plan.fromJson(
        _plan(<Map<String, dynamic>>[
          editCommand('replace-1', 'midi.replace_notes', notes: notes),
          editCommand('replace-2', 'midi.replace_notes', notes: notes),
          editCommand('chop', 'midi.chop_notes', subdivision: 4, range: null),
        ]),
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextWithMidiNotes(<Map<String, dynamic>>[_note(50, 0, 1)]),
      );

      expect(prepared.actions, hasLength(1));
      expect(prepared.receipts.map((receipt) => receipt['status']), <String>[
        'prepared',
        'already_satisfied',
        'already_satisfied',
      ]);
    });

    test('rejects wrong clips, bounds, ranges, and empty chop', () {
        final cases = <({AiV3Plan plan, AiV3CoreContext context, String code})>[
          (
            plan: AiV3Plan.fromJson(
              _plan(<Map<String, dynamic>>[
                editCommand(
                  'audio',
                  'midi.replace_notes',
                  clipId: 'audio-clip',
                  notes: <Map<String, dynamic>>[_note(60, 0, 1)],
                ),
              ]),
            ),
            context: _context(),
            code: 'v3_midi_clip_required',
          ),
          (
            plan: AiV3Plan.fromJson(
              _plan(<Map<String, dynamic>>[
                editCommand(
                  'missing',
                  'midi.append_notes',
                  clipId: 'missing',
                  notes: <Map<String, dynamic>>[_note(60, 0, 1)],
                ),
              ]),
            ),
            context: _context(),
            code: 'v3_clip_id_unknown',
          ),
          (
            plan: AiV3Plan.fromJson(
              _plan(<Map<String, dynamic>>[
                editCommand(
                  'range',
                  'midi.chop_notes',
                  range: <String, dynamic>{'start_beat': 7, 'end_beat': 9},
                ),
              ]),
            ),
            context: _contextWithMidiNotes(<Map<String, dynamic>>[
              _note(60, 0, 1),
            ]),
            code: 'v3_midi_chop_range_invalid',
          ),
          (
            plan: AiV3Plan.fromJson(
              _plan(<Map<String, dynamic>>[
                editCommand('empty', 'midi.chop_notes'),
              ]),
            ),
            context: _contextWithMidiNotes(const <Map<String, dynamic>>[]),
            code: 'v3_midi_notes_missing',
          ),
        ];

        for (final value in cases) {
          expect(
            () => const AiV3CommandPreparer().prepare(
              plan: value.plan,
              context: value.context,
            ),
            throwsA(
              isA<AiV3PreparationException>().having(
                (error) => error.code,
                'code',
                value.code,
              ),
            ),
            reason: value.code,
          );
        }
    });
  });
}
