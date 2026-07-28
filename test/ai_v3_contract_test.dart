import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_preparer.dart';

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
) =>
    <String, dynamic>{
      'command_id': id,
      'type': type,
      'arguments': arguments,
    };

AiV3Plan _allRowsMixPlan() => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
    ]));

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
        'instruments': <String>['piano'],
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

AiV3CoreContext _contextWithSecondAudioClip() {
  final data =
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_context().data)) as Map);
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
  final data =
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_context().data)) as Map);
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
  final data =
      Map<String, dynamic>.from(jsonDecode(jsonEncode(base.data)) as Map);
  data['runtime_capabilities'] = <String>['daw.stem_separate'];
  final clips = (data['clips'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: false);
  clips.singleWhere(
    (clip) => clip['clip_id'] == 'audio-clip',
  )['source_file'] = 'pubspec.yaml';
  data['clips'] = clips;
  return AiV3CoreContext(
    profile: base.profile,
    stateDigest: base.stateDigest,
    data: data,
  );
}

AiV3CoreContext _contextForAudioToMidi() {
  final base = _context();
  final data =
      Map<String, dynamic>.from(jsonDecode(jsonEncode(base.data)) as Map);
  data['runtime_capabilities'] = <String>[
    'daw.midi_compose.audio_to_midi',
  ];
  final clips = (data['clips'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: false);
  clips.singleWhere(
    (clip) => clip['clip_id'] == 'audio-clip',
  )['source_file'] = 'pubspec.yaml';
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
  final data =
      Map<String, dynamic>.from(jsonDecode(jsonEncode(base.data)) as Map);
  data['runtime_capabilities'] =
      includeService ? <String>['daw.audio_enhance'] : <String>[];
  final effects = <Map<String, dynamic>>[
    ...((data['effects'] as List).whereType<Map>().map(
          (effect) => Map<String, dynamic>.from(effect),
        )),
    for (final effectId in aiV3PhoneMicCleanupEffectIds)
      <String, dynamic>{
        'effect_id': effectId,
        'parameters': const <Object>[],
      },
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
  final data =
      Map<String, dynamic>.from(jsonDecode(jsonEncode(base.data)) as Map);
  final clips = (data['clips'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList(growable: false);
  clips.singleWhere(
    (clip) => clip['clip_id'] == 'audio-clip-2',
  )['row_id'] = 200;
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
]) =>
    <String, dynamic>{
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
  final clips = (base.data['clips'] as List).whereType<Map>().map((raw) {
    final clip = Map<String, dynamic>.from(raw);
    if (clip['clip_id'] == 'midi-clip') {
      clip['length_beats'] = lengthBeats;
      clip['midi_notes'] = notes;
    }
    return clip;
  }).toList(growable: false);
  return AiV3CoreContext(
    profile: base.profile,
    stateDigest: base.stateDigest,
    data: <String, dynamic>{...base.data, 'clips': clips},
  );
}

void main() {
  group('V3 execution policy', () {
    test('explicitly covers every current command as auto apply', () {
      expect(
        aiV3ExecutionPolicyByCommandType.keys.toSet(),
        aiV3CommandTypes,
      );
      expect(
        aiV3ExecutionPolicyByCommandType.values,
        everyElement(AiV3ExecutionPolicy.autoApply),
      );
    });

    test('fails closed for missing policy and uses strictest compound policy',
        () {
      expect(
        () => aiV3ExecutionPolicyForCommandTypes(
          const <String>['future.command'],
        ),
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
    });
  });

  test('strict tool describes relative and absolute row mixing distinctly', () {
    final tool = aiV3SubmitPlanTool();
    final properties = (tool['parameters'] as Map)['properties'] as Map;
    final commands = properties['commands'] as Map;
    final variants = ((commands['items'] as Map)['anyOf'] as List).cast<Map>();

    Map argumentsFor(String type) {
      final variant = variants.singleWhere((candidate) {
        final typeSchema = ((candidate['properties'] as Map)['type'] as Map);
        return (typeSchema['enum'] as List).contains(type);
      });
      return (((variant['properties'] as Map)['arguments'] as Map)['properties']
          as Map);
    }

    expect(
      (argumentsFor('row.adjust_gain_db')['delta_db'] as Map)['description'],
      contains('Relative gain change'),
    );
    expect(
      (argumentsFor('row.set_gain_db')['gain_db'] as Map)['description'],
      contains('Absolute final gain'),
    );
    expect(
      (argumentsFor('row.adjust_pan')['delta_signed'] as Map)['description'],
      allOf(contains('Relative pan change'), contains('current position')),
    );
    expect(
      (argumentsFor('row.set_pan')['pan_signed'] as Map)['description'],
      contains('Absolute final pan position'),
    );
  });

  test('strict tool exposes exact row automation point and clear contracts',
      () {
    final tool = aiV3SubmitPlanTool();
    final properties = (tool['parameters'] as Map)['properties'] as Map;
    final variants =
        (((properties['commands'] as Map)['items'] as Map)['anyOf'] as List)
            .cast<Map>();

    Map variantFor(String type) => variants.singleWhere((candidate) {
          final typeSchema = ((candidate['properties'] as Map)['type'] as Map);
          return (typeSchema['enum'] as List).contains(type);
        });

    final setArguments = ((variantFor('automation.set_points')['properties']
        as Map)['arguments'] as Map);
    expect(
      setArguments['required'],
      <String>['row_id', 'automation_target_id', 'points'],
    );
    final pointItems = ((((setArguments['properties'] as Map)['points']
        as Map)['items']) as Map);
    expect(pointItems['required'], <String>['beat', 'value_normalized']);
    expect(
      ((setArguments['properties'] as Map)['points'] as Map)['maxItems'],
      aiV3MaxAutomationPoints,
    );

    final clearArguments = ((variantFor('automation.clear')['properties']
        as Map)['arguments'] as Map);
    expect(clearArguments['required'], <String>[
      'row_id',
      'automation_target_id',
    ]);
  });

  test('strict tool exposes row metadata and final-state mute semantics', () {
    final tool = aiV3SubmitPlanTool();
    final properties = (tool['parameters'] as Map)['properties'] as Map;
    final variants =
        (((properties['commands'] as Map)['items'] as Map)['anyOf'] as List)
            .cast<Map>();

    Map argumentsFor(String type) {
      final variant = variants.singleWhere((candidate) {
        final typeSchema = ((candidate['properties'] as Map)['type'] as Map);
        return (typeSchema['enum'] as List).contains(type);
      });
      return (((variant['properties'] as Map)['arguments'] as Map)['properties']
          as Map);
    }

    expect(
      (argumentsFor('row.set_muted')['muted'] as Map)['description'],
      allOf(contains('Final mute state'), contains('opposite')),
    );
    expect(argumentsFor('row.select').keys, <String>{'row_id'});
    expect(
      ((argumentsFor('row.set_color')['color'] as Map)['enum'] as List),
      <String>[
        'none',
        'red',
        'orange',
        'yellow',
        'green',
        'cyan',
        'blue',
        'purple',
        'magenta',
      ],
    );
    expect(aiV3CommonCommandTypes, isNot(contains('row.select')));
    expect(aiV3CommonCommandTypes, isNot(contains('row.set_color')));
    final roleSchema = argumentsFor('row.set_role_override')['role'] as Map;
    expect(
      ((roleSchema['anyOf'] as List).first as Map)['enum'],
      <String>['vocals', 'drums', 'bass', 'guitar', 'synth', 'other'],
    );
    expect(roleSchema['description'], contains('Use null to clear'));
    expect(aiV3CommonCommandTypes, isNot(contains('row.set_role_override')));
    final cleanupRowSchema =
        argumentsFor('row.apply_phone_mic_cleanup')['row_id'] as Map;
    expect(
      cleanupRowSchema['description'],
      allOf(contains('audio row'), contains('every current audio clip')),
    );
    expect(
      aiV3CommonCommandTypes,
      isNot(contains('row.apply_phone_mic_cleanup')),
    );
  });

  test('strict role override contract accepts canonical roles and null only',
      () {
    for (final role in <Object?>[
      'vocals',
      'drums',
      'bass',
      'guitar',
      'synth',
      'other',
      null,
    ]) {
      expect(
        AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('role-$role', 'row.set_role_override',
              <String, dynamic>{'row_id': 100, 'role': role}),
        ])).commands.single.arguments['role'],
        role,
      );
    }
    expect(
      () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('alias', 'row.set_role_override',
            <String, dynamic>{'row_id': 100, 'role': 'vocal'}),
      ])),
      throwsA(isA<AiV3ContractException>()),
    );
    expect(
      () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('extra', 'row.set_role_override', <String, dynamic>{
          'row_id': 100,
          'role': 'vocals',
          'infer': true,
        }),
      ])),
      throwsA(isA<AiV3ContractException>()),
    );
  });

  test('strict phone cleanup contract accepts only one stable row ID', () {
    final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
      _command(
        'cleanup',
        'row.apply_phone_mic_cleanup',
        <String, dynamic>{'row_id': 100},
      ),
    ]));
    expect(plan.commands.single.arguments, <String, dynamic>{'row_id': 100});
    for (final arguments in <Map<String, dynamic>>[
      <String, dynamic>{'row_id': '100'},
      <String, dynamic>{'row_id': 100, 'mode': 'strong'},
    ]) {
      expect(
        () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command(
            'bad-cleanup',
            'row.apply_phone_mic_cleanup',
            arguments,
          ),
        ])),
        throwsA(isA<AiV3ContractException>()),
      );
    }
  });

  test('strict sample replacement contract is shared and exact', () {
    final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
      _command('replace', 'sample.replace', <String, dynamic>{
        'clip_id': 'audio-clip',
        'asset_id': 'kick-1',
      }),
    ]));
    expect(plan.commands.single.type, 'sample.replace');

    final semanticTool = aiV3SubmitPlanTool(
      includeCommandSemantics: true,
    );
    final variants = (((((semanticTool['parameters'] as Map)['properties']
            as Map)['commands'] as Map)['items'] as Map)['anyOf'] as List)
        .cast<Map>();
    final replaceVariant = variants.singleWhere((candidate) {
      final type = ((candidate['properties'] as Map)['type'] as Map);
      return (type['enum'] as List).contains('sample.replace');
    });
    final arguments = (((replaceVariant['properties'] as Map)['arguments']
        as Map)['properties'] as Map);
    expect(arguments.keys, <String>{'clip_id', 'asset_id'});
    expect(
      (arguments['asset_id'] as Map)['description'],
      allOf(contains('preserves the clip identity'), contains('resets')),
    );

    for (final invalid in <Map<String, dynamic>>[
      <String, dynamic>{'clip_id': 'audio-clip'},
      <String, dynamic>{'asset_id': 'kick-1'},
      <String, dynamic>{
        'clip_id': 'audio-clip',
        'asset_id': 'kick-1',
        'mode': 'stretch',
      },
      <String, dynamic>{'clip_id': '', 'asset_id': 'kick-1'},
    ]) {
      expect(
        () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('bad', 'sample.replace', invalid),
        ])),
        throwsA(isA<AiV3ContractException>()),
      );
    }
  });

  test('strict tool exposes one typed row lifecycle surface', () {
    final tool = aiV3SubmitPlanTool();
    final properties = (tool['parameters'] as Map)['properties'] as Map;
    final variants =
        (((properties['commands'] as Map)['items'] as Map)['anyOf'] as List)
            .cast<Map>();

    Map argumentsFor(String type) {
      final variant = variants.singleWhere((candidate) {
        final typeSchema = ((candidate['properties'] as Map)['type'] as Map);
        return (typeSchema['enum'] as List).contains(type);
      });
      return (((variant['properties'] as Map)['arguments'] as Map)['properties']
          as Map);
    }

    expect(
        argumentsFor('row.create').keys, <String>{'name', 'lane', 'position'});
    expect(argumentsFor('row.delete').keys, <String>{'row_id'});
    expect(
      ((argumentsFor('row.create')['lane'] as Map)['anyOf'] as List),
      hasLength(2),
    );
    expect(
      ((argumentsFor('row.create')['position'] as Map)['anyOf'] as List),
      hasLength(3),
    );
    expect(aiV3CommonCommandTypes, isNot(contains('row.create')));
    expect(aiV3CommonCommandTypes, isNot(contains('row.delete')));
  });

  test('strict tool exposes stable-id final-state grouping commands', () {
    final tool = aiV3SubmitPlanTool();
    final properties = (tool['parameters'] as Map)['properties'] as Map;
    final variants =
        (((properties['commands'] as Map)['items'] as Map)['anyOf'] as List)
            .cast<Map>();

    Map argumentsFor(String type) {
      final variant = variants.singleWhere((candidate) {
        final typeSchema = ((candidate['properties'] as Map)['type'] as Map);
        return (typeSchema['enum'] as List).contains(type);
      });
      return (((variant['properties'] as Map)['arguments'] as Map)['properties']
          as Map);
    }

    expect(argumentsFor('group.create').keys, <String>{'row_ids', 'name'});
    expect(
        argumentsFor('group.remove_row').keys, <String>{'group_id', 'row_id'});
    expect(argumentsFor('group.set_collapsed').keys,
        <String>{'group_id', 'collapsed'});
    expect(
      (argumentsFor('group.set_collapsed')['collapsed'] as Map)['description'],
      allOf(contains('Final collapsed state'), contains('opposite')),
    );
    expect(aiV3CommonCommandTypes, isNot(contains('group.create')));
    expect(aiV3CommonCommandTypes, isNot(contains('group.remove_row')));
    expect(aiV3CommonCommandTypes, isNot(contains('group.set_collapsed')));
  });

  test('grouping contract rejects duplicate, fuzzy, and toggle-shaped input',
      () {
    for (final command in <Map<String, dynamic>>[
      _command('group', 'group.create', <String, dynamic>{
        'row_ids': <int>[100, 100],
        'name': 'Bus',
      }),
      _command('group', 'group.create', <String, dynamic>{
        'row_ids': <int>[100],
        'name': null,
      }),
      _command('remove', 'group.remove_row', <String, dynamic>{
        'group_name': 'Drums',
        'row_id': 100,
      }),
      _command('collapse', 'group.set_collapsed', <String, dynamic>{
        'group_id': 'drums',
        'toggle': true,
      }),
    ]) {
      expect(
        () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[command])),
        throwsA(isA<AiV3ContractException>()),
      );
    }
  });

  test('row lifecycle contract rejects malformed lane and position variants',
      () {
    Map<String, dynamic> lifecyclePlan(Map<String, dynamic> arguments) =>
        _plan(<Map<String, dynamic>>[
          _command('create', 'row.create', arguments),
        ]);

    for (final arguments in <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Audio',
        'lane': <String, dynamic>{
          'kind': 'audio',
          'instrument_id': 'piano',
        },
        'position': <String, dynamic>{'kind': 'end'},
      },
      <String, dynamic>{
        'name': 'MIDI',
        'lane': <String, dynamic>{'kind': 'midi'},
        'position': <String, dynamic>{'kind': 'end'},
      },
      <String, dynamic>{
        'name': 'Audio',
        'lane': <String, dynamic>{'kind': 'audio'},
        'position': <String, dynamic>{'kind': 'before'},
      },
    ]) {
      expect(
        () => AiV3Plan.fromJson(lifecyclePlan(arguments)),
        throwsA(isA<AiV3ContractException>()),
      );
    }
  });

  test('mix reference schema requires factual suitability', () {
    final tool = aiV3SubmitPlanTool(
      commandTypes: const <String>{'mix.apply_goal'},
      includeCommandSemantics: true,
    );
    final properties = (tool['parameters'] as Map)['properties'] as Map;
    final commands = properties['commands'] as Map;
    final variant =
        (((commands['items'] as Map)['anyOf'] as List).single as Map);
    final arguments = ((variant['properties'] as Map)['arguments'] as Map);
    final reference = (arguments['properties'] as Map)['reference'] as Map;

    expect(
      reference['description'],
      allOf(
        contains('usable analyzed audio'),
        contains('Request those facts before planning'),
      ),
    );
  });

  test('pitch command semantics distinguish MIDI from audio clips', () {
    final encoded = jsonEncode(aiV3SubmitPlanTool(
      commandTypes: const <String>{
        'clip.adjust_pitch_semitones',
        'midi.transpose',
      },
      includeCommandSemantics: true,
    ));

    expect(encoded, contains('Never use for MIDI clips; use midi.transpose'));
    expect(
      encoded,
      contains('Never use audio-clip pitch commands for MIDI clips'),
    );
  });

  test('embedded destinations distinguish existing and created rows', () {
    for (final type in <String>['sample.place', 'midi.create_clip']) {
      final encoded = jsonEncode(aiV3SubmitPlanTool(
        commandTypes: <String>{type},
        includeCommandSemantics: true,
      ));
      expect(
        encoded,
        contains(
          'Stable ID of a row that already exists in the supplied project context.',
        ),
      );
      expect(
        encoded,
        contains(
          'Never guess the ID of a row created earlier in this plan',
        ),
      );
      expect(
        encoded,
        contains(
          'It is the sole creator of that destination; do not also issue row.create for the same destination.',
        ),
      );
    }
  });

  test('trim schema defines absolute project-timeline bounds', () {
    final encoded = jsonEncode(aiV3SubmitPlanTool(
      commandTypes: const <String>{'clip.trim_to_range'},
      includeCommandSemantics: true,
    ));
    expect(encoded, contains('Absolute project-timeline beat'));
    expect(encoded, contains('not an offset from the clip start'));
    expect(encoded, contains('not a clip-relative length or offset'));
    expect(encoded, contains('current supplied timeline bounds'));
  });

  group('PlanV3 contract', () {
    test('strict tool schema uses only supported union composition', () {
      final tool = aiV3SubmitPlanTool();
      expect(tool['strict'], isTrue);

      void inspect(Object? value) {
        if (value is List) {
          for (final item in value) {
            inspect(item);
          }
          return;
        }
        if (value is! Map) return;
        expect(value, isNot(contains('oneOf')));
        expect(value, isNot(contains('uniqueItems')));
        for (final item in value.values) {
          inspect(item);
        }
      }

      inspect(tool['parameters']);
      final schema = jsonEncode(tool['parameters']);
      for (final command in const <String>[
        'row.set_gain_db',
        'row.adjust_pan',
        'row.set_soloed',
        'clip.trim_to_range',
        'clip.split_at',
        'clip.duplicate_to',
        'clip.delete',
        'clip.set_pitch_semitones',
        'clip.adjust_pitch_semitones',
        'clip.set_timeline_length_beats',
        'clip.scale_timeline_length',
        'effect.remove',
        'effect.set_bypassed',
        'mix.apply_goal',
      ]) {
        expect(schema, contains(command));
      }
    });

    test('accepts strict subjective and reference mix goals', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));
      expect(plan.commands.single.type, 'mix.apply_goal');
    });

    test('prepares exact effect-instance removal and final bypass state', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('bypass', 'effect.set_bypassed', <String, dynamic>{
          'effect_instance_id': 'fx-comp-1',
          'bypassed': true,
        }),
        _command('remove', 'effect.remove', <String, dynamic>{
          'effect_instance_id': 'fx-reverb-1',
        }),
      ]));

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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('enabled', 'effect.set_bypassed', <String, dynamic>{
          'effect_instance_id': 'fx-comp-1',
          'bypassed': false,
        }),
      ]));
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions, isEmpty);
      expect(prepared.receipts.single['status'], 'already_satisfied');
    });

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
      expect(
        prepared.actions.map((action) => action.type),
        <String>[
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
        ],
      );
      expect(prepared.actions[0].data['tempo_bpm'], 128);
      expect(prepared.actions[1].data['delta_db'], -2);
      expect(prepared.actions[2].data['gain_db'], -6);
      expect(prepared.actions[3].data['delta'], 0.25);
      expect(prepared.actions[4].data['operation'], 'solo');
      expect(prepared.actions[5].data['pan_signed'], 0.2);
      expect(prepared.actions[8].data['delta_ms'], 2000.0);
      expect(prepared.actions[9].data['semitones'], -2);
      expect(prepared.actions[10].data['notes'], hasLength(1));
      expect(
        prepared.actions[11].data['parameters'],
        <String, dynamic>{'Mix': 0.2},
      );
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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));

      expect(plan.commands, hasLength(4));
      expect(plan.commands.map((command) => command.type), <String>[
        'clip.trim_to_range',
        'clip.split_at',
        'clip.duplicate_to',
        'clip.delete',
      ]);
    });

    test('accepts strict audio clip glue and prepares exact stable targets',
        () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('glue', 'clip.glue', <String, dynamic>{
          'clip_ids': <String>['audio-clip-2', 'audio-clip'],
          'label': 'Hook Comp',
        }),
      ]));
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextWithSecondAudioClip(),
      );

      expect(prepared.actions.single.type, 'v3_clip_glue');
      expect(
        prepared.actions.single.data['source_clip_ids'],
        <String>['audio-clip', 'audio-clip-2'],
      );
      expect(prepared.actions.single.data['label'], 'Hook Comp');
      expect(prepared.actions.single.data['start_ms'], 0.0);
      expect(prepared.actions.single.data['duration_ms'], 6000.0);
    });

    test('accepts and prepares strict local two-stem separation', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('stems', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
      ]));
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

    test('stem separation rejects malformed, MIDI, and unavailable requests',
        () {
      expect(
        () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('bad', 'clip.separate_stems', <String, dynamic>{
            'clip_id': 'audio-clip',
            'output': 'vocals',
          }),
        ])),
        throwsA(isA<AiV3ContractException>()),
      );
      final midi = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('midi', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'midi-clip',
        }),
      ]));
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: midi,
          context: _contextForStemSeparation(),
        ),
        throwsA(isA<AiV3PreparationException>()),
      );
      final unavailable = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('stems', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
      ]));
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
      final project = Map<String, dynamic>.from(capacityData['project'] as Map);
      project['row_capacity'] = <String, dynamic>{
        'current_rows': (capacityData['rows'] as List).length,
        'max_rows': (capacityData['rows'] as List).length + 1,
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
    });

    test('stem separation permits a later stable edit but blocks topology work',
        () {
      final allowed = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('stems', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('gain', 'row.adjust_gain_db', <String, dynamic>{
          'row_id': 200,
          'delta_db': -1,
        }),
      ]));
      expect(
        const AiV3CommandPreparer()
            .prepare(plan: allowed, context: _contextForStemSeparation())
            .actions,
        hasLength(2),
      );

      final blocked = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('stems', 'clip.separate_stems', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
        _command('create', 'row.create', <String, dynamic>{
          'name': 'Later',
          'lane': <String, dynamic>{'kind': 'audio'},
          'position': <String, dynamic>{'kind': 'end'},
        }),
      ]));
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: blocked,
          context: _contextForStemSeparation(),
        ),
        throwsA(isA<AiV3PreparationException>()),
      );
    });

    test('accepts and prepares strict local audio-to-MIDI conversion', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('convert', 'clip.convert_to_midi', <String, dynamic>{
          'clip_id': 'audio-clip',
          'instrument_id': 'piano',
        }),
      ]));
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
        () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('bad', 'clip.convert_to_midi', <String, dynamic>{
            'clip_id': 'audio-clip',
          }),
        ])),
        throwsA(isA<AiV3ContractException>()),
      );
      final unavailableInstrument =
          AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('convert', 'clip.convert_to_midi', <String, dynamic>{
          'clip_id': 'audio-clip',
          'instrument_id': 'invented',
        }),
      ]));
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
      final unavailableService = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('convert', 'clip.convert_to_midi', <String, dynamic>{
          'clip_id': 'audio-clip',
          'instrument_id': 'piano',
        }),
      ]));
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
          () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
            _command('glue', 'clip.glue', arguments),
          ])),
          throwsA(isA<AiV3ContractException>()),
        );
      }

      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('glue', 'clip.glue', <String, dynamic>{
          'clip_ids': <String>['audio-clip', 'audio-clip-2'],
          'label': null,
        }),
        _command('delete', 'clip.delete', <String, dynamic>{
          'clip_id': 'audio-clip',
        }),
      ]));
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

    test('glue rejects cross-row, previously mutated, and post-topology clips',
        () {
      AiV3Plan glueAfter(List<Map<String, dynamic>> preceding) =>
          AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
            ...preceding,
            _command('glue', 'clip.glue', <String, dynamic>{
              'clip_ids': <String>['audio-clip', 'audio-clip-2'],
              'label': null,
            }),
          ]));

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: glueAfter(const <Map<String, dynamic>>[]),
          context: _contextWithCrossRowAudioClips(),
        ),
        throwsA(isA<AiV3PreparationException>().having(
          (error) => error.code,
          'code',
          'v3_clip_glue_row_mismatch',
        )),
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
        throwsA(isA<AiV3PreparationException>().having(
          (error) => error.code,
          'code',
          'v3_clip_glue_source_already_mutated',
        )),
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
        throwsA(isA<AiV3PreparationException>().having(
          (error) => error.code,
          'code',
          'v3_clip_id_unknown',
        )),
      );
    });

    test('keeps absolute and relative audio pitch commands distinct', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('set-pitch', 'clip.set_pitch_semitones', <String, dynamic>{
          'clip_id': 'audio-clip',
          'pitch_semitones': 3,
        }),
        _command(
          'adjust-pitch',
          'clip.adjust_pitch_semitones',
          <String, dynamic>{
            'clip_id': 'audio-clip',
            'delta_semitones': -2,
          },
        ),
      ]));

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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command(
            'set-length', 'clip.set_timeline_length_beats', <String, dynamic>{
          'clip_id': 'audio-clip',
          'length_beats': 12,
          'preserve_pitch': true,
        }),
        _command(
            'scale-length', 'clip.scale_timeline_length', <String, dynamic>{
          'clip_id': 'audio-clip',
          'factor': 0.5,
          'preserve_pitch': false,
        }),
      ]));

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
            'missing-mode', 'clip.scale_timeline_length', <String, dynamic>{
          'clip_id': 'audio-clip',
          'factor': 2,
        }),
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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('source', 'clip.set_source_tempo_bpm', <String, dynamic>{
          'clip_id': 'audio-clip',
          'source_tempo_bpm': 92,
        }),
        _command('follow', 'clip.set_tempo_follow_mode', <String, dynamic>{
          'clip_id': 'audio-clip',
          'mode': 'preserve_pitch',
        }),
      ]));

      expect(plan.commands, hasLength(2));
      expect(plan.commands.first.arguments['source_tempo_bpm'], 92);
      expect(plan.commands.last.arguments['mode'], 'preserve_pitch');
    });

    test('accepts automatic clip and project tempo commands', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('align', 'clip.align_tempo_to_project', <String, dynamic>{
          'clip_id': 'audio-clip',
          'mode': 'preserve_pitch',
        }),
        _command('project', 'project.set_tempo_from_clip', <String, dynamic>{
          'clip_id': 'audio-clip',
          'mode': 'repitch',
        }),
      ]));

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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('trim', 'clip.trim_silence', <String, dynamic>{
          'clip_id': 'audio-clip',
          'edges': 'both',
          'padding_ms': 8,
        }),
        _command('align', 'clip.align_first_sound', <String, dynamic>{
          'clip_id': 'audio-clip',
          'destination': <String, dynamic>{
            'kind': 'project_beat',
            'beat': 4,
          },
        }),
        _command('snap', 'clip.align_first_sound', <String, dynamic>{
          'clip_id': 'audio-clip',
          'destination': <String, dynamic>{'kind': 'nearest_bar'},
        }),
      ]));

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
          'destination': <String, dynamic>{
            'kind': 'nearest_beat',
            'beat': 2,
          },
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
        () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('same', 'row.rename', <String, dynamic>{
            'row_id': 100,
            'new_name': 'A',
          }),
          _command('same', 'row.rename', <String, dynamic>{
            'row_id': 100,
            'new_name': 'B',
          }),
        ])),
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

    test('clarification schema reserves app-owned response controls', () {
      final encoded = jsonEncode(aiV3SubmitPlanTool());
      expect(encoded, contains('distinct, concise, meaningful answers'));
      expect(encoded, contains('Never include Cancel, Something else, Other'));
      expect(encoded, contains('do not repeat, number, or bullet'));
    });

    test('round-trips complete plans and rejects undeclared fields', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('mute', 'row.set_muted', <String, dynamic>{
          'row_id': 100,
          'muted': true,
        }),
      ]));
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

    test('prepares a stable-id mix goal without exposing concrete MixActions',
        () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(prepared.actions.single.type, 'v3_mix_goal');
      final target = prepared.actions.single.data['target'] as Map;
      expect(target['row_id'], 100);
      expect(target['row_index'], 0);
      expect(prepared.preview, contains('Mix Audio'));
    });

    test('rejects a reference that is the processing row', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));
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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
            'new_row': <String, dynamic>{
              'name': 'Kick',
            },
          },
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
      ]));

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(
        prepared.actions.map((action) => action.type),
        <String>['row_mute', 'row_rename', 'row_create', 'sample_insert'],
      );
      expect(prepared.stateDigest, 'state-1');
    });

    test('prepares trim bounds as absolute project beats', () {
      final context = _contextWithAudioClipBounds(
        startBeat: 12,
        lengthBeats: 8,
      );
      final prepared = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('trim', 'clip.trim_to_range', <String, dynamic>{
            'clip_id': 'audio-clip',
            'start_beat': 14,
            'end_beat': 18,
          }),
        ])),
        context: context,
      );
      expect(prepared.actions, hasLength(1));
      expect(prepared.actions.single.type, 'clip_edit');
      expect(prepared.actions.single.data['delta_trim_start_ms'], 1000);
      expect(prepared.actions.single.data['delta_trim_end_ms'], -1000);
      expect(prepared.actions.single.data['new_start_ms'], 7000);

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
            _command('relative', 'clip.trim_to_range', <String, dynamic>{
              'clip_id': 'audio-clip',
              'start_beat': 2,
              'end_beat': 6,
            }),
          ])),
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
        plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('effect', 'effect.ensure_configured', <String, dynamic>{
            'row_id': 100,
            'effect_id': 'Reverb',
            'parameters': <Map<String, dynamic>>[
              <String, dynamic>{'parameter_id': 'mix', 'value': 0.25},
            ],
          }),
        ])),
        context: _context(),
      );
      expect(prepared.actions.single.type, 'v3_effect_configure');
      expect(
        prepared.actions.single.data['parameters'],
        <String, dynamic>{'Mix': 0.25},
      );

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
          ])),
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

    test('prepares exact stable sample replacement and rejects dead targets',
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
    });

    test('embedded MIDI destination expands to exactly one row creation', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(
        prepared.actions.map((action) => action.type),
        <String>['row_create', 'midi_compose'],
      );
    });

    test('delete then embedded MIDI destination uses the final row index', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(
        prepared.actions.map((action) => action.type),
        <String>['row_delete', 'row_create', 'midi_compose'],
      );
      expect(
        (prepared.actions.last.data['target'] as Map)['row_index'],
        1,
      );
    });

    test('canonicalizes exact standalone and embedded MIDI row duplication',
        () {
      Map<String, dynamic> createRow(String id) =>
          _command(id, 'row.create', <String, dynamic>{
            'name': 'House Drums',
            'lane': <String, dynamic>{
              'kind': 'midi',
              'instrument_id': 'piano',
            },
            'position': <String, dynamic>{'kind': 'end'},
          });
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
        expect(
          prepared.actions.map((action) => action.type),
          <String>['row_create', 'midi_compose'],
        );
      }
    });

    test('canonicalizes exact standalone and embedded sample row duplication',
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
        expect(
          prepared.actions.map((action) => action.type),
          <String>['row_create', 'sample_insert'],
        );
      }
    });

    test('rejects ambiguous repeated embedded destination rows', () {
      final sample = _command('sample', 'sample.place', <String, dynamic>{
        'destination': <String, dynamic>{
          'new_row': <String, dynamic>{'name': 'Percussion'},
        },
        'placements': <Map<String, dynamic>>[
          <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
        ],
      });
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        sample,
        <String, dynamic>{...sample, 'command_id': 'sample-2'},
      ]));

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

    test('rejects multiple standalone rows matching one embedded destination',
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
    });

    test('allows factually distinct standalone and embedded rows', () {
      final plans = <AiV3Plan>[
        AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
        ])),
        AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('row', 'row.create', <String, dynamic>{
            'name': 'Keys',
            'lane': <String, dynamic>{
              'kind': 'midi',
              'instrument_id': 'piano',
            },
            'position': <String, dynamic>{
              'kind': 'before',
              'row_id': 100,
            },
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
        ])),
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
      final unknown = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('rename', 'row.rename', <String, dynamic>{
          'row_id': 999,
          'new_name': 'Missing',
        }),
      ]));
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: unknown,
          context: _context(),
        ),
        throwsA(isA<AiV3PreparationException>()),
      );
    });

    test('prepares semantic row controls with stable targets', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));

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
      expect(prepared.actions[3].data['operation'], 'solo');
      for (final action in prepared.actions) {
        expect((action.data['target'] as Map)['row_id'], 100);
        expect((action.data['target'] as Map)['row_index'], 0);
      }
    });

    test('prepares row selection, color, and mute final states', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('select', 'row.select', <String, dynamic>{'row_id': 200}),
        _command('color', 'row.set_color', <String, dynamic>{
          'row_id': 100,
          'color': 'magenta',
        }),
        _command('toggle-result', 'row.set_muted', <String, dynamic>{
          'row_id': 200,
          'muted': false,
        }),
      ]));

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(
        prepared.actions.map((action) => action.type),
        <String>['row_select', 'row_color_edit', 'row_mute'],
      );
      for (final action in prepared.actions) {
        final target = action.data['target'] as Map;
        expect(target['row_id'], isIn(<int>[100, 200]));
        expect(target['row_index'], isIn(<int>[0, 1]));
      }
      expect(prepared.actions[1].data['color'], 'magenta');
      expect(prepared.actions[2].data['operation'], 'unmute');
    });

    test('row metadata commands detect already-satisfied state', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('select', 'row.select', <String, dynamic>{'row_id': 100}),
        _command('color', 'row.set_color', <String, dynamic>{
          'row_id': 200,
          'color': 'blue',
        }),
        _command('mute', 'row.set_muted', <String, dynamic>{
          'row_id': 100,
          'muted': false,
        }),
      ]));

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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(
        prepared.actions.map((action) => action.type),
        <String>['v3_row_role_override', 'v3_row_role_override'],
      );
      expect(prepared.actions.first.data['role'], 'drums');
      expect(prepared.actions.last.data['role'], isNull);
      expect(
        prepared.receipts.map((receipt) => receipt['status']),
        <String>[
          'already_satisfied',
          'prepared',
          'already_satisfied',
          'prepared',
        ],
      );
    });

    test('prepares one row-scoped phone cleanup action with exact facts', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command(
          'cleanup',
          'row.apply_phone_mic_cleanup',
          <String, dynamic>{'row_id': 100},
        ),
      ]));

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
      final cleanup = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command(
          'cleanup',
          'row.apply_phone_mic_cleanup',
          <String, dynamic>{'row_id': 100},
        ),
      ]));
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
      final midiRowCleanup = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command(
          'cleanup-midi',
          'row.apply_phone_mic_cleanup',
          <String, dynamic>{'row_id': 200},
        ),
      ]));
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
      final conflict = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command(
          'cleanup',
          'row.apply_phone_mic_cleanup',
          <String, dynamic>{'row_id': 100},
        ),
        _command('effect', 'effect.ensure_configured', <String, dynamic>{
          'row_id': 100,
          'effect_id': 'Compressor',
          'parameters': const <Object>[],
        }),
      ]));
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

      final cleanupThenDelete = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command(
          'cleanup',
          'row.apply_phone_mic_cleanup',
          <String, dynamic>{'row_id': 100},
        ),
        _command(
          'delete',
          'row.delete',
          <String, dynamic>{'row_id': 100},
        ),
      ]));
      final prepared = const AiV3CommandPreparer().prepare(
        plan: cleanupThenDelete,
        context: _contextForPhoneMicCleanup(),
      );
      expect(
        prepared.actions.map((action) => action.type),
        <String>['v3_phone_mic_cleanup', 'row_delete'],
      );

      final deleteThenCleanup = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command(
          'delete',
          'row.delete',
          <String, dynamic>{'row_id': 100},
        ),
        _command(
          'cleanup',
          'row.apply_phone_mic_cleanup',
          <String, dynamic>{'row_id': 100},
        ),
      ]));
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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command(
          'cleanup',
          'row.apply_phone_mic_cleanup',
          <String, dynamic>{'row_id': 100},
        ),
        _command('rename', 'row.rename', <String, dynamic>{
          'row_id': 200,
          'new_name': 'Keys Preserved',
        }),
      ]));
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextForPhoneMicCleanup(),
      );
      expect(
        prepared.actions.map((action) => action.type),
        <String>['v3_phone_mic_cleanup', 'row_rename'],
      );
    });

    test('prepares audio and MIDI row creation plus stable row deletion', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('audio', 'row.create', <String, dynamic>{
          'name': 'Vocal Double',
          'lane': <String, dynamic>{'kind': 'audio'},
          'position': <String, dynamic>{'kind': 'before', 'row_id': 200},
        }),
        _command('midi', 'row.create', <String, dynamic>{
          'name': 'Soft Keys',
          'lane': <String, dynamic>{
            'kind': 'midi',
            'instrument_id': 'piano',
          },
          'position': <String, dynamic>{'kind': 'end'},
        }),
        _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
      ]));

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(
        prepared.actions.map((action) => action.type),
        <String>['row_create', 'row_create', 'row_delete'],
      );
      expect(prepared.actions[0].data['position'], 'above');
      expect((prepared.actions[0].data['target'] as Map)['row_id'], 200);
      expect(prepared.actions[0].data['lane_kind'], 'audio');
      expect(prepared.actions[1].data['position'], 'end');
      expect(prepared.actions[1].data['lane_kind'], 'instrument');
      expect(prepared.actions[1].data['instrument_id'], 'piano');
      expect((prepared.actions[2].data['target'] as Map)['row_id'], 100);
    });

    test('row lifecycle preparation rejects unavailable factual state', () {
      final unknownInstrument = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('midi', 'row.create', <String, dynamic>{
          'name': 'Unknown',
          'lane': <String, dynamic>{
            'kind': 'midi',
            'instrument_id': 'missing',
          },
          'position': <String, dynamic>{'kind': 'end'},
        }),
      ]));
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
      final deleteLast = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
      ]));
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
        plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('rename-deleted', 'row.rename', <String, dynamic>{
            'row_id': 100,
            'new_name': 'Before Delete',
          }),
          _command('delete', 'row.delete', <String, dynamic>{'row_id': 100}),
          _command('rename-alive', 'row.rename', <String, dynamic>{
            'row_id': 200,
            'new_name': 'Still Here',
          }),
        ])),
        context: _context(),
      );

      expect(
        prepared.actions.map((action) => action.type),
        <String>['row_rename', 'row_delete', 'row_rename'],
      );
    });

    test('topology changes block later index-dependent operations', () {
      Map<String, dynamic> createRow() =>
          _command('create', 'row.create', <String, dynamic>{
            'name': 'Extra',
            'lane': <String, dynamic>{'kind': 'audio'},
            'position': <String, dynamic>{'kind': 'end'},
          });

      final laterMix = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: laterMix,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_mix_action_target_invalid',
          ),
        ),
      );

      final laterDuplicate = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        createRow(),
        _command('duplicate', 'clip.duplicate_to', <String, dynamic>{
          'clip_id': 'audio-clip',
          'destination_row_id': 100,
          'start_beat': 12,
        }),
      ]));
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
    });

    test('index-dependent operations remain valid before row deletion', () {
      final prepared = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
        ])),
        context: _context(),
      );

      expect(
        prepared.actions.map((action) => action.type),
        <String>['clip_edit', 'v3_mix_goal', 'row_delete'],
      );
    });

    test('duplicate deletion and group mixing after membership change fail',
        () {
      final duplicateDelete = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('delete-1', 'row.delete', <String, dynamic>{'row_id': 100}),
        _command('delete-2', 'row.delete', <String, dynamic>{'row_id': 100}),
      ]));
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
      final groupThenMix = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('remove', 'group.remove_row', <String, dynamic>{
          'group_id': 'music',
          'row_id': 200,
        }),
        _command('mix', 'mix.apply_goal', <String, dynamic>{
          'target': <String, dynamic>{'scope': 'group', 'group_id': 'music'},
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
      ]));
      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: groupThenMix,
          context: groupedContext,
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_mix_action_target_invalid',
          ),
        ),
      );
    });

    test('prepares grouping from exact stable identities', () {
      final create = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('group', 'group.create', <String, dynamic>{
          'row_ids': <int>[200, 100],
          'name': 'Music',
        }),
      ]));
      final created = const AiV3CommandPreparer().prepare(
        plan: create,
        context: _context(),
      );
      expect(created.actions.single.type, 'v3_group_edit');
      expect(created.actions.single.data['operation'], 'create');
      expect(created.actions.single.data['row_ids'], <int>[100, 200]);
      expect(
          created.actions.single.data['expected_row_order'], <int>[100, 200]);
      expect(created.actions.single.data['group_id'].toString(),
          startsWith('v3_group_'));

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
        plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('remove', 'group.remove_row', <String, dynamic>{
            'group_id': 'music',
            'row_id': 200,
          }),
        ])),
        context: groupedContext,
      );
      expect(remove.actions.single.data['dissolves_group'], isTrue);
      final collapse = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('collapse', 'group.set_collapsed', <String, dynamic>{
            'group_id': 'music',
            'collapsed': true,
          }),
        ])),
        context: groupedContext,
      );
      expect(collapse.actions.single.data['collapsed'], isTrue);
      final noOp = const AiV3CommandPreparer().prepare(
        plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('expanded', 'group.set_collapsed', <String, dynamic>{
            'group_id': 'music',
            'collapsed': false,
          }),
        ])),
        context: groupedContext,
      );
      expect(noOp.actions, isEmpty);
      expect(noOp.receipts.single['status'], 'already_satisfied');
    });

    test('prepares exact core clip edits from stable ids and beats', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );

      expect(prepared.actions, hasLength(4));
      expect(prepared.actions.map((action) => action.data['operation']),
          <String>['trim', 'cut', 'duplicate', 'delete']);
      expect(prepared.actions[0].data['delta_trim_start_ms'], 500.0);
      expect(prepared.actions[0].data['delta_trim_end_ms'], -500.0);
      expect(prepared.actions[0].data['new_start_ms'], 500.0);
      expect(prepared.actions[1].data['cut_ms'], 4000.0);
      expect(prepared.actions[2].data['paste_start_ms'], 6000.0);
      expect(prepared.actions[2].data['row_index'], 0);
      for (final action in prepared.actions) {
        expect((action.data['target'] as Map)['clip_id'], isNotEmpty);
      }
    });

    test('prepares exact absolute and relative audio pitch values', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('adjust', 'clip.adjust_pitch_semitones', <String, dynamic>{
          'clip_id': 'audio-clip',
          'delta_semitones': -2,
        }),
        _command('set', 'clip.set_pitch_semitones', <String, dynamic>{
          'clip_id': 'audio-clip',
          'pitch_semitones': 3,
        }),
      ]));

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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));

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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('source', 'clip.set_source_tempo_bpm', <String, dynamic>{
          'clip_id': 'audio-clip',
          'source_tempo_bpm': 96,
        }),
        _command('follow', 'clip.set_tempo_follow_mode', <String, dynamic>{
          'clip_id': 'audio-clip',
          'mode': 'repitch',
        }),
      ]));

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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('align', 'clip.align_tempo_to_project', <String, dynamic>{
          'clip_id': 'audio-clip',
          'mode': 'preserve_pitch',
        }),
        _command('project', 'project.set_tempo_from_clip', <String, dynamic>{
          'clip_id': 'audio-clip',
          'mode': 'repitch',
        }),
      ]));

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
        detectedTempoByClipId: const <String, double>{
          'audio-clip': 127.6,
        },
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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('align', 'clip.align_tempo_to_project', <String, dynamic>{
          'clip_id': 'audio-clip',
          'mode': 'preserve_pitch',
        }),
      ]));

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        ),
        throwsA(isA<AiV3PreparationException>().having(
          (error) => error.code,
          'code',
          'v3_clip_tempo_detection_unavailable',
        )),
      );
    });

    test('materializes boundary analysis into exact trim and move actions', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('trim', 'clip.trim_silence', <String, dynamic>{
          'clip_id': 'audio-clip',
          'edges': 'both',
          'padding_ms': 10,
        }),
        _command('align', 'clip.align_first_sound', <String, dynamic>{
          'clip_id': 'audio-clip',
          'destination': <String, dynamic>{
            'kind': 'project_beat',
            'beat': 4,
          },
        }),
      ]));

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
      expect(
        prepared.actions[1].data['new_alignment_offset_ms'],
        1790.0,
      );
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
        final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('align', 'clip.align_first_sound', <String, dynamic>{
            'clip_id': 'audio-clip',
            'destination': entry.key,
          }),
        ]));
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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('trim', 'clip.trim_silence', <String, dynamic>{
          'clip_id': 'audio-clip',
          'edges': 'both',
          'padding_ms': 8,
        }),
      ]));

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        ),
        throwsA(isA<AiV3PreparationException>().having(
          (error) => error.code,
          'code',
          'v3_clip_boundary_analysis_unavailable',
        )),
      );
    });

    test('treats exact source tempo and disabled follow as satisfied', () {
      final data =
          jsonDecode(jsonEncode(_context().data)) as Map<String, dynamic>;
      ((data['clips'] as List).first
          as Map<String, dynamic>)['source_tempo_bpm'] = 120.0;
      final context = AiV3CoreContext(
        profile: AiV3ContextProfile.essential,
        stateDigest: 'state-1',
        data: data,
      );
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('source', 'clip.set_source_tempo_bpm', <String, dynamic>{
          'clip_id': 'audio-clip',
          'source_tempo_bpm': 120,
        }),
        _command('off', 'clip.set_tempo_follow_mode', <String, dynamic>{
          'clip_id': 'audio-clip',
          'mode': 'off',
        }),
      ]));

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
          throwsA(isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            item.code,
          )),
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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('noop', 'clip.set_timeline_length_beats', <String, dynamic>{
          'clip_id': 'audio-clip',
          'length_beats': 8,
          'preserve_pitch': true,
        }),
      ]));

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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('stretch', 'clip.scale_timeline_length', <String, dynamic>{
          'clip_id': 'audio-clip',
          'factor': 2,
          'preserve_pitch': true,
        }),
      ]));

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: context,
        ),
        throwsA(isA<AiV3PreparationException>().having(
          (error) => error.code,
          'code',
          'v3_clip_stretch_global_conflict',
        )),
      );
    });

    test('rejects MIDI and out-of-range final audio pitch', () {
      final cases = <({Map<String, dynamic> command, String code})>[
        (
          command: _command(
            'midi',
            'clip.set_pitch_semitones',
            <String, dynamic>{
              'clip_id': 'midi-clip',
              'pitch_semitones': 3,
            },
          ),
          code: 'v3_audio_clip_required',
        ),
        (
          command: _command(
            'overflow',
            'clip.adjust_pitch_semitones',
            <String, dynamic>{
              'clip_id': 'audio-clip',
              'delta_semitones': 11,
            },
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
          throwsA(isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            item.code,
          )),
        );
      }
    });

    test('rejects invalid clip bounds, kinds, and destination lanes', () {
      final cases = <({Map<String, dynamic> command, String code})>[
        (
          command:
              _command('trim-midi', 'clip.trim_to_range', <String, dynamic>{
            'clip_id': 'midi-clip',
            'start_beat': 5,
            'end_beat': 10,
          }),
          code: 'v3_audio_clip_required',
        ),
        (
          command:
              _command('trim-expand', 'clip.trim_to_range', <String, dynamic>{
            'clip_id': 'audio-clip',
            'start_beat': 0,
            'end_beat': 9,
          }),
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
              'duplicate-mismatch', 'clip.duplicate_to', <String, dynamic>{
            'clip_id': 'audio-clip',
            'destination_row_id': 200,
            'start_beat': 8,
          }),
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
          throwsA(isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            item.code,
          )),
        );
      }
    });

    test('converts gain fades into normalized editor multipliers', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('fade', 'automation.gain_fade', <String, dynamic>{
          'row_id': 100,
          'start_beat': 0,
          'end_beat': 4,
          'from_gain_db': -120,
          'to_level': 'current',
        }),
      ]));

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

    test('prepares exact normalized automation points and clear by stable ids',
        () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));

      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _context(),
      );
      expect(
        prepared.actions.map((action) => action.type),
        <String>['v3_automation_points', 'v3_automation_points'],
      );
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
    });

    test('rejects malformed or orphaned exact automation targets and points',
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

      final unknownTarget = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('unknown', 'automation.clear', <String, dynamic>{
          'row_id': 100,
          'automation_target_id': 'missing',
        }),
      ]));
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
    });

    test('limits generated MIDI length without limiting timeline position', () {
      final validLaterClip = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));
      expect(
        const AiV3CommandPreparer()
            .prepare(plan: validLaterClip, context: _context())
            .actions,
        isNotEmpty,
      );

      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('midi', 'midi.create_clip', <String, dynamic>{
          'destination': <String, dynamic>{'row_id': 200},
          'start_beat': 64,
          'length_beats': 33,
          'notes': <Map<String, dynamic>>[
            <String, dynamic>{
              'pitch': 60,
              'start_beat': 0,
              'length_beats': 1,
              'velocity': 0.8,
            },
          ],
        }),
      ]));

      expect(
        () => const AiV3CommandPreparer().prepare(
          plan: plan,
          context: _context(),
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_midi_arrangement_limit',
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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('sample', 'sample.place', <String, dynamic>{
          'destination': <String, dynamic>{
            'new_row': <String, dynamic>{
              'name': 'Kick',
            },
          },
          'placements': <Map<String, dynamic>>[
            <String, dynamic>{'asset_id': 'kick-1', 'start_beat': 0},
          ],
        }),
      ]));

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
  });

  group('V3 transport', () {
    test('accepts only four strict final-state commands', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        _command('play', 'transport.set_playing', <String, dynamic>{
          'playing': true,
        }),
        _command('restart', 'transport.restart', const <String, dynamic>{}),
        _command(
          'metro',
          'transport.set_metronome_enabled',
          <String, dynamic>{'enabled': true},
        ),
        _command(
          'loop',
          'transport.set_loop_enabled',
          <String, dynamic>{'enabled': false},
        ),
      ]));

      expect(
        plan.commands.map((command) => command.type),
        <String>[
          'transport.set_playing',
          'transport.restart',
          'transport.set_metronome_enabled',
          'transport.set_loop_enabled',
        ],
      );
      expect(
        () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('toggle', 'transport.toggle_playing', const {}),
        ])),
        throwsA(isA<AiV3ContractException>()),
      );
      expect(
        () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('alias', 'transport.play', const {}),
        ])),
        throwsA(isA<AiV3ContractException>()),
      );
      expect(
        () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('extra', 'transport.restart', <String, dynamic>{
            'position': 0,
          }),
        ])),
        throwsA(isA<AiV3ContractException>()),
      );
      expect(
        () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          _command('bad', 'transport.set_loop_enabled', <String, dynamic>{
            'enabled': 1,
          }),
        ])),
        throwsA(isA<AiV3ContractException>()),
      );
    });

    test('prepares canonical actions in authoritative order', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));

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
      return _command(
        id,
        type,
        switch (type) {
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
        },
      );
    }

    test('accepts strict replace, append, and nullable-range chop shapes', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));

      expect(plan.commands.map((command) => command.type), <String>[
        'midi.replace_notes',
        'midi.append_notes',
        'midi.chop_notes',
        'midi.chop_notes',
      ]);
      expect(aiV3CommandTypes, hasLength(53));
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
        editCommand(
          'bad-subdivision',
          'midi.chop_notes',
          subdivision: 129,
        ),
        editCommand(
          'bad-range',
          'midi.chop_notes',
          range: <String, dynamic>{'start_beat': 2, 'end_beat': 2},
        ),
        editCommand(
          'bad-decay',
          'midi.chop_notes',
          decay: 1.1,
        ),
      ];

      for (final command in invalid) {
        expect(
          () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[command])),
          throwsA(isA<AiV3ContractException>()),
          reason: command['command_id'].toString(),
        );
      }
    });

    test('256 serialized notes fit conservatively and totals above 256 fail', () {
      final notes = List<Map<String, dynamic>>.generate(
        aiV3MaxGeneratedMidiNotes,
        (index) => _note(
          127,
          index * 0.03125,
          0.03125,
          0.999999,
        ),
      );
      final rawPlan = _plan(<Map<String, dynamic>>[
        editCommand(
          'replace-max',
          'midi.replace_notes',
          notes: notes,
        ),
      ]);
      expect(AiV3Plan.fromJson(rawPlan).commands, hasLength(1));
      expect((jsonEncode(rawPlan).length / 4).ceil(), lessThan(8192));

      final tooMany = List<Map<String, dynamic>>.generate(
        (aiV3MaxGeneratedMidiNotes ~/ 2) + 1,
        (index) => _note(60, index * 0.05, 0.01),
      );
      expect(
        () => AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
          editCommand(
            'replace-129',
            'midi.replace_notes',
            notes: tooMany,
          ),
          editCommand(
            'append-129',
            'midi.append_notes',
            notes: tooMany,
          ),
        ])),
        throwsA(
          isA<AiV3ContractException>().having(
            (error) => error.code,
            'code',
            'v3_generated_midi_limit',
          ),
        ),
      );
    });

    test('simulates replace then append as exact complete note states', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextWithMidiNotes(<Map<String, dynamic>>[
          _note(50, 0, 1),
        ]),
      );

      expect(prepared.actions, hasLength(2));
      expect(prepared.actions.every((action) => action.type == 'midi_compose'),
          isTrue);
      expect(prepared.actions.last.data['operation'], 'replace_notes');
      expect(prepared.actions.last.data['notes'], <Map<String, dynamic>>[
        _note(65, 1, 1),
        _note(60, 8.5, 0.5),
      ]);
      expect(prepared.actions.last.data['final_length_beats'], 9.0);
      expect(prepared.actions.last.data['preserve_clip_state'], isTrue);
    });

    test('repeated appends use each preceding final clip length', () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextWithMidiNotes(
          <Map<String, dynamic>>[_note(48, 0, 1)],
          lengthBeats: 4,
        ),
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

    test('append continues after existing notes beyond a stale visible end',
        () {
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        editCommand(
          'append',
          'midi.append_notes',
          notes: <Map<String, dynamic>>[_note(64, 0.5, 0.5)],
        ),
      ]));
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextWithMidiNotes(
          <Map<String, dynamic>>[
            _note(48, 0, 1),
            _note(55, 4, 3.5),
          ],
          lengthBeats: 2.5,
        ),
      );

      expect(prepared.actions.single.data['notes'], <Map<String, dynamic>>[
        _note(48, 0, 1),
        _note(55, 4, 3.5),
        _note(64, 8, 0.5),
      ]);
      expect(prepared.actions.single.data['final_length_beats'], 8.5);
    });

    test('simulates transpose and append in authoritative planner order', () {
      final transposeThenAppend =
          AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
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
      ]));
      final prepared = const AiV3CommandPreparer().prepare(
        plan: transposeThenAppend,
        context: _contextWithMidiNotes(<Map<String, dynamic>>[
          _note(100, 0, 1),
        ]),
      );
      expect(
        prepared.actions.last.data['notes'],
        <Map<String, dynamic>>[
          _note(79, 0, 1),
          _note(40, 8, 0.5),
        ],
      );

      final appendThenTranspose =
          AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        editCommand(
          'append-first',
          'midi.append_notes',
          notes: <Map<String, dynamic>>[_note(70, 0, 0.5)],
        ),
        _command('transpose-last', 'midi.transpose', <String, dynamic>{
          'clip_id': 'midi-clip',
          'semitones': 2,
        }),
      ]));
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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        editCommand(
          'chop',
          'midi.chop_notes',
          subdivision: 4,
          range: <String, dynamic>{'start_beat': 1, 'end_beat': 3},
          decay: 0.25,
        ),
      ]));
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
      final plan = AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
        editCommand(
          'replace-1',
          'midi.replace_notes',
          notes: notes,
        ),
        editCommand(
          'replace-2',
          'midi.replace_notes',
          notes: notes,
        ),
        editCommand(
          'chop',
          'midi.chop_notes',
          subdivision: 4,
          range: null,
        ),
      ]));
      final prepared = const AiV3CommandPreparer().prepare(
        plan: plan,
        context: _contextWithMidiNotes(<Map<String, dynamic>>[
          _note(50, 0, 1),
        ]),
      );

      expect(prepared.actions, hasLength(1));
      expect(
        prepared.receipts.map((receipt) => receipt['status']),
        <String>['prepared', 'already_satisfied', 'already_satisfied'],
      );
    });

    test('rejects wrong clips, bounds, ranges, empty chop, and 512 overflow',
        () {
      final cases = <({
        AiV3Plan plan,
        AiV3CoreContext context,
        String code,
      })>[
        (
          plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
            editCommand(
              'audio',
              'midi.replace_notes',
              clipId: 'audio-clip',
              notes: <Map<String, dynamic>>[_note(60, 0, 1)],
            ),
          ])),
          context: _context(),
          code: 'v3_midi_clip_required',
        ),
        (
          plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
            editCommand(
              'missing',
              'midi.append_notes',
              clipId: 'missing',
              notes: <Map<String, dynamic>>[_note(60, 0, 1)],
            ),
          ])),
          context: _context(),
          code: 'v3_clip_id_unknown',
        ),
        (
          plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
            editCommand(
              'range',
              'midi.chop_notes',
              range: <String, dynamic>{'start_beat': 7, 'end_beat': 9},
            ),
          ])),
          context: _contextWithMidiNotes(<Map<String, dynamic>>[
            _note(60, 0, 1),
          ]),
          code: 'v3_midi_chop_range_invalid',
        ),
        (
          plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
            editCommand('empty', 'midi.chop_notes'),
          ])),
          context: _contextWithMidiNotes(const <Map<String, dynamic>>[]),
          code: 'v3_midi_notes_missing',
        ),
        (
          plan: AiV3Plan.fromJson(_plan(<Map<String, dynamic>>[
            editCommand(
              'overflow',
              'midi.append_notes',
              notes: List<Map<String, dynamic>>.generate(
                13,
                (index) => _note(80, index * 0.01, 0.005),
              ),
            ),
          ])),
          context: _contextWithMidiNotes(
            List<Map<String, dynamic>>.generate(
              500,
              (index) => _note(60, index * 0.01, 0.005),
            ),
          ),
          code: 'v3_midi_result_limit',
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
