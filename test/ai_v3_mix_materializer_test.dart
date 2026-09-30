import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/local_mixing_model.dart';
import 'package:mixroom/ai/magnitude_predictor.dart';
import 'package:mixroom/ai/one_button_mix_profiles.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_mix_materializer.dart';
import 'package:mixroom/ai/v3/ai_v3_preparer.dart';
import 'package:mixroom/models/goal_vector.dart';
import 'package:mixroom/models/mixing_result.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/models/project_state.dart';

const Set<String> _freeMixEffectIds = <String>{
  'Reverb',
  'EQ 3-Band',
  'EQ Parametric',
  'Delay',
  'Compressor',
  'Limiter',
};

const Set<String> _allMixEffectIds = <String>{
  ..._freeMixEffectIds,
  'Distortion',
  'De-Esser',
  'Clipper',
};

class _Predictor implements MixingMagnitudePredictor {
  const _Predictor(this.transform);

  final List<MixAction> Function(List<MixAction>) transform;

  @override
  bool get isEnabled => true;

  @override
  bool get isReady => true;

  @override
  Map<String, dynamic> get observabilityContext => const <String, dynamic>{
    'source': 'test',
  };

  @override
  Future<void> dispose() async {}

  @override
  Future<void> load() async {}

  @override
  Future<void> startBackgroundRefresh() async {}

  @override
  Future<MagnitudeRefineResult> refine({
    required ProjectState project,
    required GoalVector goal,
    required List<MixAction> actions,
    required bool strict,
    String? projectId,
  }) async => MagnitudeRefineResult(
    actions: transform(actions),
    fallbackUsed: false,
    observability: observabilityContext,
  );
}

class _RecordingMixModel extends LocalMixingModel {
  final seenRoleOverrides = <Map<int, String>>[];

  @override
  MixingResult run({
    required ProjectState project,
    required GoalVector goal,
    required bool strict,
    Map<int, String> roleOverrides = const <int, String>{},
    bool requirePermissionForBigMoves = false,
    MixGenerationScope? generationScope,
  }) {
    seenRoleOverrides.add(Map<int, String>.from(roleOverrides));
    return const MixingResult(
      actions: <MixAction>[],
      summary: 'No changes.',
      isNoOp: true,
    );
  }
}

class _FixedMixModel extends LocalMixingModel {
  _FixedMixModel(this.actions);

  final List<MixAction> actions;

  @override
  MixingResult run({
    required ProjectState project,
    required GoalVector goal,
    required bool strict,
    Map<int, String> roleOverrides = const <int, String>{},
    bool requirePermissionForBigMoves = false,
    MixGenerationScope? generationScope,
  }) => MixingResult(
    actions: actions,
    summary: 'Test mix.',
    isNoOp: actions.isEmpty,
  );
}

class _AsyncPredictor implements MixingMagnitudePredictor {
  const _AsyncPredictor(this.refineResult);

  final Future<MagnitudeRefineResult> Function(List<MixAction>) refineResult;

  @override
  bool get isEnabled => true;

  @override
  bool get isReady => true;

  @override
  Map<String, dynamic> get observabilityContext => const <String, dynamic>{
    'source': 'async-test',
  };

  @override
  Future<void> dispose() async {}

  @override
  Future<void> load() async {}

  @override
  Future<void> startBackgroundRefresh() async {}

  @override
  Future<MagnitudeRefineResult> refine({
    required ProjectState project,
    required GoalVector goal,
    required List<MixAction> actions,
    required bool strict,
    String? projectId,
  }) => refineResult(actions);
}

RowState _row(
  int index,
  int id,
  double rms, {
  String groupId = '',
  String roleOverride = '',
  bool hasAudio = true,
  bool hasClips = true,
}) => RowState(
  rowIndex: index,
  rowId: id,
  rowName: index == 0 ? 'Vocal' : 'Reference',
  roleOverride: roleOverride,
  groupId: groupId,
  clips: hasClips
      ? <ClipState>[
          ClipState(startMs: 0, endMs: 4000, fileName: 'row_$index.wav'),
        ]
      : const <ClipState>[],
  approxRms: rms,
  approxCrest: 1.6,
  roleProbs: const <String, double>{'vocals': 0.8, 'other': 0.2},
  roleConsistency: 0.9,
  clipTopRoles: const <String>['vocals'],
  audioStats: <String, double>{
    'centroid_hz': index == 0 ? 1200 : 2600,
    'spectral_rolloff_hz': index == 0 ? 2400 : 5000,
    'hf_rms': index == 0 ? 0.12 : 0.35,
    'bassiness': index == 0 ? 0.18 : 0.3,
    'side_ratio': index == 0 ? 0.1 : 0.5,
    'phase_corr': index == 0 ? 0.95 : 0.6,
    'integrated_lufs_est': index == 0 ? -18 : -11,
    'true_peak_dbfs': index == 0 ? -6 : -2,
    'lra_est': index == 0 ? 7 : 4,
    'transient_density': 0.4,
    'clip_ratio': 0.01,
    'st_rms_std': 0.1,
  },
  interpretation: RowInterpretationState.empty,
  gain0to3: 1,
  pan0To1: 0.5,
  effects: const <EffectState>[],
  volumeAutomation: const [],
  hasAudio: hasAudio,
);

ProjectState _project({bool grouped = false}) => ProjectState(
  bpm: 120,
  masterGain0to3: 1,
  masterPan0to1: 0.5,
  maxRows: 8,
  rows: <RowState>[
    _row(0, 10, 0.1, groupId: grouped ? 'vocals' : ''),
    _row(1, 20, 0.25, groupId: grouped ? 'vocals' : ''),
  ],
  trackGroups: grouped
      ? const <TrackGroup>[
          TrackGroup(id: 'vocals', name: 'Vocals', rowIds: <int>[10, 20]),
        ]
      : const <TrackGroup>[],
  overlapMatrix: const <List<int>>[
    <int>[0, 0],
    <int>[0, 0],
  ],
  overlapRatioMatrix: const <List<double>>[
    <double>[0, 0],
    <double>[0, 0],
  ],
);

AiV3PreparedBundle _bundle({
  bool reference = false,
  Map<String, dynamic>? target,
  String? intentKind,
  String? direction,
  String? descriptor,
  bool resetFx = false,
}) {
  final plan = AiV3Plan(
    outcome: 'plan',
    userMessage: 'I prepared the mix.',
    commands: <AiV3Command>[
      AiV3Command(
        commandId: 'mix-1',
        type: 'mix.apply_goal',
        arguments: const <String, dynamic>{},
      ),
    ],
  );
  return AiV3PreparedBundle(
    plan: plan,
    stateDigest: 'state',
    actions: <AssistantAction>[
      AssistantAction(
        type: 'v3_mix_goal',
        data: <String, dynamic>{
          'command_id': 'mix-1',
          'target':
              target ??
              (reference
                  ? const <String, dynamic>{'scope': 'all_rows'}
                  : const <String, dynamic>{
                      'scope': 'row',
                      'row_id': 10,
                      'row_index': 0,
                    }),
          'intents': <Map<String, dynamic>>[
            <String, dynamic>{
              'kind': intentKind ?? (reference ? 'balance' : 'reverb'),
              'direction': direction ?? (reference ? null : 'up'),
              'descriptor': descriptor,
            },
          ],
          'intensity': 0.6,
          'execution_profile': 'producer_safe',
          'audibility': 'noticeable',
          'style_tags': const <String>[],
          'reset_fx': resetFx,
          'reference': reference
              ? const <String, dynamic>{
                  'row_id': 20,
                  'row_index': 1,
                  'mode': 'full_mix',
                  'closeness': 'balanced',
                }
              : null,
        },
      ),
    ],
    receipts: const <Map<String, dynamic>>[
      <String, dynamic>{
        'command_id': 'mix-1',
        'type': 'mix.apply_goal',
        'status': 'prepared',
        'expanded_action_count': 1,
        'preview_label': 'Mix Vocal',
      },
    ],
    preview: 'I prepared the mix.\nPlanned changes:\n- Mix Vocal',
  );
}

void main() {
  for (final profile in <({String? id, double expectedDelta})>[
    (id: null, expectedDelta: 0.1),
    (id: OneButtonMixProfiles.producerId, expectedDelta: 0.1),
    (id: OneButtonMixProfiles.warmSpaciousId, expectedDelta: 0.11),
    (id: OneButtonMixProfiles.punchyEnergeticId, expectedDelta: 0.092),
  ]) {
    test(
      'one-button profile ${profile.id} tunes the learned result before execution',
      () async {
        final modelAction = MixAction('set_row_pan', <String, dynamic>{
          'row': 0,
          'mode': 'delta',
          'delta': 0.05,
        });
        final materializer = AiV3MixGoalMaterializer(
          mixModel: _FixedMixModel(<MixAction>[modelAction]),
          magnitudePredictor: _Predictor((actions) {
            expect(actions.single.data['delta'], 0.05);
            return <MixAction>[
              MixAction(actions.single.type, <String, dynamic>{
                ...actions.single.data,
                'delta': 0.1,
              }),
            ];
          }),
        );

        final result = await materializer.materialize(
          bundle: _bundle(intentKind: 'pan', direction: 'right'),
          project: _project(),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: false,
          allowedEffectIds: _allMixEffectIds,
          oneButtonMixProfileId: profile.id,
        );

        final action =
            (result.bundle.actions.single.data['actions'] as List).single
                as Map;
        expect(
          (action['data'] as Map)['delta'],
          closeTo(profile.expectedDelta, 0.000001),
        );
        expect((action['data'] as Map)['force_individual_row'], isTrue);
        expect(modelAction.data['delta'], 0.05);
        final steps = result.metadata['mix_materialization_steps'] as List;
        expect((steps.single as Map)['one_button_mix_profile_id'], profile.id);
      },
    );
  }

  test('deferred one-button mix retains its profile until runtime', () async {
    final base = _bundle(intentKind: 'pan', direction: 'right');
    final deferred = AssistantAction(
      type: 'v3_deferred_mix_goal',
      data: Map<String, dynamic>.from(base.actions.single.data),
    );
    final materializer = AiV3MixGoalMaterializer(
      mixModel: _FixedMixModel(<MixAction>[
        MixAction('set_row_pan', <String, dynamic>{
          'row': 0,
          'mode': 'delta',
          'delta': 0.1,
        }),
      ]),
      magnitudePredictor: _Predictor((_) => fail('Refinement was bypassed.')),
    );

    final prepared = await materializer.materialize(
      bundle: AiV3PreparedBundle(
        plan: base.plan,
        stateDigest: base.stateDigest,
        actions: <AssistantAction>[deferred],
        receipts: base.receipts,
        preview: base.preview,
        executionPolicy: base.executionPolicy,
      ),
      project: _project(),
      roleOverrides: const <int, String>{},
      bypassLearnedMagnitudes: true,
      allowedEffectIds: _allMixEffectIds,
      oneButtonMixProfileId: OneButtonMixProfiles.warmSpaciousId,
    );
    final preparedAction = prepared.bundle.actions.single;
    expect(preparedAction.type, 'v3_deferred_mix_goal');
    expect(
      preparedAction.data['one_button_mix_profile_id'],
      OneButtonMixProfiles.warmSpaciousId,
    );
    expect(deferred.data.containsKey('one_button_mix_profile_id'), isFalse);

    final runtime = await materializer.materializeSingleGoal(
      data: preparedAction.data,
      project: _project(),
      roleOverrides: const <int, String>{},
      bypassLearnedMagnitudes: true,
      allowedEffectIds: _allMixEffectIds,
    );
    expect(runtime.actions.single.data['delta'], closeTo(0.11, 0.000001));
    expect(
      runtime.metadata['one_button_mix_profile_id'],
      OneButtonMixProfiles.warmSpaciousId,
    );
  });

  test(
    'capture observer preserves normal refinement and its exact inputs',
    () async {
      final traces = <Map<String, dynamic>>[];
      var enabled = false;
      final project = _project();
      final goal = GoalVector.fromJson({
        'intensity': 0.7,
        'execution_profile': 'creative_bold',
      });
      final actions = <MixAction>[
        MixAction('set_row_gain', {'row': 0, 'mode': 'set', 'value': 1.4}),
      ];
      final predictor = CapturingMagnitudePredictor(
        _Predictor((a) => a),
        captureEnabled: () => enabled,
        captureToken: () => 'session:request',
        onTrace: traces.add,
      );
      final first = await predictor.refine(
        project: project,
        goal: goal,
        actions: actions,
        strict: true,
      );
      expect(first.actions, actions);
      expect(traces, isEmpty);
      enabled = true;
      final second = await predictor.refine(
        project: project,
        goal: goal,
        actions: actions,
        strict: true,
      );
      expect(second.actions, actions);
      expect(traces.single['project_state'], project.toMagnitudeResolverJson());
      expect(traces.single['goal'], goal.toJson());
      expect(traces.single['actions'], actions.map((a) => a.toJson()).toList());
      expect(traces.single['strict'], true);
    },
  );

  test(
    'late refinement cannot attach to a different capture request',
    () async {
      var token = 'first';
      final completion = Completer<MagnitudeRefineResult>();
      final traces = <Map<String, dynamic>>[];
      final actions = [
        MixAction('set_row_gain', {'row': 0, 'mode': 'set', 'value': 1.2}),
      ];
      final predictor = CapturingMagnitudePredictor(
        _AsyncPredictor((_) => completion.future),
        captureEnabled: () => true,
        captureToken: () => token,
        onTrace: traces.add,
      );
      final pending = predictor.refine(
        project: _project(),
        goal: GoalVector.fromJson({}),
        actions: actions,
        strict: false,
      );
      token = 'second';
      completion.complete(
        MagnitudeRefineResult(actions: actions, fallbackUsed: false),
      );
      expect((await pending).actions, actions);
      expect(traces, isEmpty);
    },
  );

  test('runtime role overrides follow current project row indexes', () {
    final project = ProjectState(
      bpm: 120,
      masterGain0to3: 1,
      maxRows: 8,
      rows: <RowState>[
        _row(0, 20, 0.25, roleOverride: 'bass'),
        _row(1, 10, 0.1, roleOverride: 'vocals'),
        _row(2, 30, 0.2),
      ],
      overlapMatrix: const <List<int>>[
        <int>[0, 0, 0],
        <int>[0, 0, 0],
        <int>[0, 0, 0],
      ],
    );

    expect(aiV3CurrentRoleOverrides(project), const <int, String>{
      0: 'bass',
      1: 'vocals',
    });
  });

  test('role overrides affect only later mix goals in planner order', () async {
    Future<Map<int, String>> rolesSeen({required bool roleFirst}) async {
      final base = _bundle();
      final role = AssistantAction(
        type: 'v3_row_role_override',
        data: const <String, dynamic>{
          'role': 'drums',
          'target': <String, dynamic>{
            'scope': 'row',
            'row_id': 10,
            'row_index': 0,
          },
        },
      );
      final model = _RecordingMixModel();
      await AiV3MixGoalMaterializer(
        mixModel: model,
        magnitudePredictor: _Predictor((actions) => actions),
      ).materialize(
        bundle: AiV3PreparedBundle(
          plan: base.plan,
          stateDigest: base.stateDigest,
          actions: roleFirst
              ? <AssistantAction>[role, ...base.actions]
              : <AssistantAction>[...base.actions, role],
          receipts: base.receipts,
          preview: base.preview,
        ),
        project: _project(),
        roleOverrides: const <int, String>{0: 'vocals'},
        bypassLearnedMagnitudes: true,
        allowedEffectIds: _allMixEffectIds,
      );
      return model.seenRoleOverrides.single;
    }

    expect(await rolesSeen(roleFirst: true), <int, String>{0: 'drums'});
    expect(await rolesSeen(roleFirst: false), <int, String>{0: 'vocals'});
  });

  test(
    'materializes a subjective goal into existing concrete MixActions',
    () async {
      final result =
          await AiV3MixGoalMaterializer(
            mixModel: LocalMixingModel(),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materialize(
            bundle: _bundle(),
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: false,
            allowedEffectIds: _freeMixEffectIds,
          );

      expect(result.bundle.actions.single.type, 'v3_mix_actions');
      final raw = result.bundle.actions.single.data['actions'] as List;
      expect(raw, isNotEmpty);
      expect(
        raw.any((action) => (action as Map)['type'] == 'ensure_effect'),
        isTrue,
      );
      expect(result.metadata, contains('mix_materialization_steps'));
    },
  );

  test('free reverb mixing materializes only available effects', () async {
    final result =
        await AiV3MixGoalMaterializer(
          mixModel: LocalMixingModel(),
          magnitudePredictor: _Predictor((actions) => actions),
        ).materialize(
          bundle: _bundle(intentKind: 'reverb', descriptor: 'concert hall'),
          project: _project(),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: true,
          allowedEffectIds: _freeMixEffectIds,
        );

    final rawActions = result.bundle.actions.single.data['actions'] as List;
    final effectIds = rawActions
        .whereType<Map>()
        .map((action) => action['data'])
        .whereType<Map>()
        .map((data) => data['effect_name_contains']?.toString())
        .whereType<String>()
        .toSet();
    expect(effectIds, isNotEmpty);
    expect(_freeMixEffectIds.containsAll(effectIds), isTrue);
  });

  test('free paid-only intents fail before magnitude refinement', () async {
    for (final intentKind in <String>['distortion', 'deesser', 'clipper']) {
      var refinementCalls = 0;
      final materializer = AiV3MixGoalMaterializer(
        mixModel: LocalMixingModel(),
        magnitudePredictor: _AsyncPredictor((actions) async {
          refinementCalls += 1;
          return MagnitudeRefineResult(actions: actions, fallbackUsed: false);
        }),
      );

      await expectLater(
        materializer.materialize(
          bundle: _bundle(intentKind: intentKind),
          project: _project(),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: false,
          allowedEffectIds: _freeMixEffectIds,
        ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_effect_id_unknown',
          ),
        ),
        reason: intentKind,
      );
      expect(refinementCalls, 0, reason: intentKind);
    }
  });

  test('a mixed safe and unavailable action set fails atomically', () async {
    final materializer = AiV3MixGoalMaterializer(
      mixModel: _FixedMixModel(<MixAction>[
        MixAction('ensure_effect', <String, dynamic>{
          'row': 0,
          'effect_name_contains': 'Reverb',
        }),
        MixAction('ensure_effect', <String, dynamic>{
          'row': 0,
          'effect_name_contains': 'Distortion',
        }),
      ]),
      magnitudePredictor: _Predictor((actions) => actions),
    );

    await expectLater(
      materializer.materialize(
        bundle: _bundle(),
        project: _project(),
        roleOverrides: const <int, String>{},
        bypassLearnedMagnitudes: true,
        allowedEffectIds: _freeMixEffectIds,
      ),
      throwsA(
        isA<AiV3PreparationException>().having(
          (error) => error.code,
          'code',
          'v3_effect_id_unknown',
        ),
      ),
    );
  });

  test('refinement cannot introduce an unavailable effect', () async {
    final materializer = AiV3MixGoalMaterializer(
      mixModel: _FixedMixModel(<MixAction>[
        MixAction('ensure_effect', <String, dynamic>{
          'row': 0,
          'effect_name_contains': 'Reverb',
        }),
      ]),
      magnitudePredictor: _Predictor(
        (_) => <MixAction>[
          MixAction('ensure_effect', <String, dynamic>{
            'row': 0,
            'effect_name_contains': 'Clipper',
          }),
        ],
      ),
    );

    await expectLater(
      materializer.materialize(
        bundle: _bundle(),
        project: _project(),
        roleOverrides: const <int, String>{},
        bypassLearnedMagnitudes: false,
        allowedEffectIds: _freeMixEffectIds,
      ),
      throwsA(
        isA<AiV3PreparationException>().having(
          (error) => error.code,
          'code',
          'v3_effect_id_unknown',
        ),
      ),
    );
  });

  test(
    'row and master ensure or adjust actions enforce effect access',
    () async {
      final cases = <({MixAction action, Map<String, dynamic> target})>[
        (
          action: MixAction('adjust_effect_param_by_name', <String, dynamic>{
            'row': 0,
            'effect_name_contains': 'Distortion',
            'param_name_contains': 'Drive',
            'norm_value': 0.5,
          }),
          target: const <String, dynamic>{
            'scope': 'row',
            'row_id': 10,
            'row_index': 0,
          },
        ),
        (
          action: MixAction('ensure_master_effect', <String, dynamic>{
            'effect_name_contains': 'Clipper',
          }),
          target: const <String, dynamic>{'scope': 'master'},
        ),
        (
          action:
              MixAction('adjust_master_effect_param_by_name', <String, dynamic>{
                'effect_name_contains': 'De-Esser',
                'param_name_contains': 'Amount',
                'norm_value': 0.5,
              }),
          target: const <String, dynamic>{'scope': 'master'},
        ),
      ];

      for (final testCase in cases) {
        await expectLater(
          AiV3MixGoalMaterializer(
            mixModel: _FixedMixModel(<MixAction>[testCase.action]),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materialize(
            bundle: _bundle(target: testCase.target),
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: true,
            allowedEffectIds: _freeMixEffectIds,
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_effect_id_unknown',
            ),
          ),
          reason: testCase.action.type,
        );
      }
    },
  );

  test(
    'deleting or resetting preserved effects remains allowed on Free',
    () async {
      final result =
          await AiV3MixGoalMaterializer(
            mixModel: _FixedMixModel(<MixAction>[
              MixAction('delete_effect', <String, dynamic>{
                'row': 0,
                'effect_name_contains': 'Distortion',
              }),
              MixAction('hard_reset_row_fx', <String, dynamic>{'row': 0}),
            ]),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materialize(
            bundle: _bundle(),
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: true,
            allowedEffectIds: _freeMixEffectIds,
          );

      final rawActions = result.bundle.actions.single.data['actions'] as List;
      expect(
        rawActions.whereType<Map>().map((action) => action['type']).toSet(),
        <String>{'delete_effect', 'hard_reset_row_fx'},
      );
    },
  );

  test('paid effect surface keeps paid-only mixing available', () async {
    final result =
        await AiV3MixGoalMaterializer(
          mixModel: LocalMixingModel(),
          magnitudePredictor: _Predictor((actions) => actions),
        ).materialize(
          bundle: _bundle(intentKind: 'distortion'),
          project: _project(),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: true,
          allowedEffectIds: _allMixEffectIds,
        );

    expect(result.bundle.actions, isNotEmpty);
  });

  test('explicit removal constrains a later subjective effect goal', () async {
    final base = _bundle();
    final result =
        await AiV3MixGoalMaterializer(
          mixModel: LocalMixingModel(),
          magnitudePredictor: _Predictor((actions) => actions),
        ).materialize(
          bundle: AiV3PreparedBundle(
            plan: base.plan,
            stateDigest: base.stateDigest,
            actions: <AssistantAction>[
              AssistantAction(
                type: 'v3_effect_instance_edit',
                data: const <String, dynamic>{
                  'operation': 'remove',
                  'effect_instance_id': 'reverb-1',
                  'effect_id': 'Reverb',
                  'target': <String, dynamic>{
                    'scope': 'row',
                    'row_id': 10,
                    'row_index': 0,
                  },
                },
              ),
              ...base.actions,
            ],
            receipts: base.receipts,
            preview: base.preview,
          ),
          project: _project(),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: true,
          allowedEffectIds: _allMixEffectIds,
        );

    expect(result.bundle.actions, hasLength(1));
    expect(result.bundle.actions.single.type, 'v3_effect_instance_edit');
    expect(result.bundle.receipts.single['status'], 'already_satisfied');
  });

  test('later explicit ensure clears an earlier removal constraint', () async {
    final base = _bundle();
    final result =
        await AiV3MixGoalMaterializer(
          mixModel: LocalMixingModel(),
          magnitudePredictor: _Predictor((actions) => actions),
        ).materialize(
          bundle: AiV3PreparedBundle(
            plan: base.plan,
            stateDigest: base.stateDigest,
            actions: <AssistantAction>[
              AssistantAction(
                type: 'v3_effect_instance_edit',
                data: const <String, dynamic>{
                  'operation': 'remove',
                  'effect_instance_id': 'reverb-1',
                  'effect_id': 'Reverb',
                  'target': <String, dynamic>{
                    'scope': 'row',
                    'row_id': 10,
                    'row_index': 0,
                  },
                },
              ),
              AssistantAction(
                type: 'v3_effect_configure',
                data: const <String, dynamic>{
                  'operation': 'ensure_configured',
                  'effect_id': 'Reverb',
                  'parameters': <String, dynamic>{},
                  'target': <String, dynamic>{
                    'scope': 'row',
                    'row_id': 10,
                    'row_index': 0,
                  },
                },
              ),
              ...base.actions,
            ],
            receipts: base.receipts,
            preview: base.preview,
          ),
          project: _project(),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: true,
          allowedEffectIds: _allMixEffectIds,
        );

    final mix = result.bundle.actions.singleWhere(
      (action) => action.type == 'v3_mix_actions',
    );
    expect(
      (mix.data['actions'] as List).whereType<Map>().any(
        (action) =>
            action['type'] == 'ensure_effect' &&
            (action['data'] as Map)['effect_name_contains'] == 'Reverb',
      ),
      isTrue,
    );
  });

  test('an effect removal constrains only its stable row', () async {
    final constraints = AiV3OrderedEffectConstraints()
      ..observeAppliedAction('v3_effect_instance_edit', const {
        'operation': 'remove',
        'effect_id': 'Reverb',
        'target': <String, dynamic>{'row_id': 10},
      });
    final result =
        await AiV3MixGoalMaterializer(
          mixModel: LocalMixingModel(),
          magnitudePredictor: _Predictor((actions) => actions),
        ).materializeSingleGoal(
          data: _bundle(
            target: const <String, dynamic>{
              'scope': 'row',
              'row_id': 20,
              'row_index': 1,
            },
          ).actions.single.data,
          project: _project(),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: true,
          allowedEffectIds: _allMixEffectIds,
          effectConstraints: constraints,
        );

    expect(
      result.actions.any(
        (action) =>
            action.type == 'ensure_effect' &&
            action.data['effect_name_contains'] == 'Reverb',
      ),
      isTrue,
    );
  });

  test('repeating an explicit removal is idempotent', () {
    final constraints = AiV3OrderedEffectConstraints();
    const removal = <String, dynamic>{
      'operation': 'remove',
      'effect_id': 'reverb',
      'target': <String, dynamic>{'row_id': 10},
    };
    constraints
      ..observeAppliedAction('v3_effect_instance_edit', removal)
      ..observeAppliedAction('v3_effect_instance_edit', removal);

    expect(constraints.unavailableByRowIndex(_project()), const {
      0: <String>{'Reverb'},
    });
  });

  test('refinement cannot reintroduce an explicitly removed effect', () {
    final base = _bundle();
    final bundle = AiV3PreparedBundle(
      plan: base.plan,
      stateDigest: base.stateDigest,
      actions: <AssistantAction>[
        AssistantAction(
          type: 'v3_effect_instance_edit',
          data: const <String, dynamic>{
            'operation': 'remove',
            'effect_instance_id': 'reverb-1',
            'effect_id': 'Reverb',
            'target': <String, dynamic>{
              'scope': 'row',
              'row_id': 10,
              'row_index': 0,
            },
          },
        ),
        ...base.actions,
      ],
      receipts: base.receipts,
      preview: base.preview,
    );

    expect(
      () =>
          AiV3MixGoalMaterializer(
            mixModel: _FixedMixModel(<MixAction>[
              MixAction('set_row_gain', const <String, dynamic>{
                'row': 0,
                'value': 1.1,
              }),
            ]),
            magnitudePredictor: _Predictor(
              (_) => <MixAction>[
                MixAction('ensure_effect', const <String, dynamic>{
                  'row': 0,
                  'effect_name_contains': 'Reverb',
                }),
              ],
            ),
          ).materialize(
            bundle: bundle,
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: false,
            allowedEffectIds: _allMixEffectIds,
          ),
      throwsA(
        isA<AiV3PreparationException>().having(
          (error) => error.code,
          'code',
          'v3_mix_effect_constraint_violation',
        ),
      ),
    );
  });

  test('single-goal materialization stays inside its required row', () async {
    final materializer = AiV3MixGoalMaterializer(
      mixModel: LocalMixingModel(),
      magnitudePredictor: _Predictor((actions) => actions),
    );
    final result = await materializer.materializeSingleGoal(
      data: _bundle().actions.single.data,
      project: _project(),
      roleOverrides: const <int, String>{},
      bypassLearnedMagnitudes: true,
      allowedEffectIds: _allMixEffectIds,
      requiredTargetRow: 0,
    );
    expect(result.actions, isNotEmpty);
    expect(result.actions.every((action) => action.data['row'] == 0), isTrue);
  });

  test(
    'single-goal materialization rejects actions escaping its row',
    () async {
      expect(
        () =>
            AiV3MixGoalMaterializer(
              mixModel: LocalMixingModel(),
              magnitudePredictor: _Predictor(
                (_) => <MixAction>[
                  MixAction('set_row_gain', const <String, dynamic>{
                    'row': 1,
                    'value': 1.0,
                  }),
                ],
              ),
            ).materializeSingleGoal(
              data: _bundle().actions.single.data,
              project: _project(),
              roleOverrides: const <int, String>{},
              bypassLearnedMagnitudes: false,
              allowedEffectIds: _allMixEffectIds,
              requiredTargetRow: 0,
            ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_mix_action_target_invalid',
          ),
        ),
      );
    },
  );

  test(
    'bundle materialization contains a stable row goal automatically',
    () async {
      expect(
        () =>
            AiV3MixGoalMaterializer(
              mixModel: LocalMixingModel(),
              magnitudePredictor: _Predictor(
                (_) => <MixAction>[
                  MixAction('set_row_gain', const <String, dynamic>{
                    'row': 1,
                    'value': 1.0,
                  }),
                ],
              ),
            ).materialize(
              bundle: _bundle(),
              project: _project(),
              roleOverrides: const <int, String>{},
              bypassLearnedMagnitudes: false,
              allowedEffectIds: _allMixEffectIds,
            ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_mix_action_target_invalid',
          ),
        ),
      );
    },
  );

  test(
    'heuristic scope escape rejects the complete command atomically',
    () async {
      for (final testCase
          in <({Map<String, dynamic> target, List<MixAction> actions})>[
            (
              target: const <String, dynamic>{
                'scope': 'row',
                'row_id': 10,
                'row_index': 0,
              },
              actions: <MixAction>[
                MixAction('set_row_gain', const <String, dynamic>{
                  'row': 0,
                  'value': 1.1,
                }),
                MixAction('set_master_gain', const <String, dynamic>{
                  'value': 1.1,
                }),
              ],
            ),
            (
              target: const <String, dynamic>{'scope': 'master'},
              actions: <MixAction>[
                MixAction('set_master_gain', const <String, dynamic>{
                  'value': 1.1,
                }),
                MixAction('set_row_gain', const <String, dynamic>{
                  'row': 0,
                  'value': 1.1,
                }),
              ],
            ),
          ]) {
        var refinementCalls = 0;
        await expectLater(
          AiV3MixGoalMaterializer(
            mixModel: _FixedMixModel(testCase.actions),
            magnitudePredictor: _AsyncPredictor((actions) async {
              refinementCalls += 1;
              return MagnitudeRefineResult(
                actions: actions,
                fallbackUsed: false,
              );
            }),
          ).materialize(
            bundle: _bundle(target: testCase.target),
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: false,
            allowedEffectIds: _allMixEffectIds,
          ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_mix_action_target_invalid',
            ),
          ),
        );
        expect(refinementCalls, 0);
      }
    },
  );

  test('row materialization requires current playable material', () async {
    final project = ProjectState(
      bpm: 120,
      masterGain0to3: 1,
      maxRows: 8,
      rows: <RowState>[_row(0, 10, 0, hasAudio: false, hasClips: false)],
      overlapMatrix: const <List<int>>[
        <int>[0],
      ],
    );

    expect(
      () =>
          AiV3MixGoalMaterializer(
            mixModel: LocalMixingModel(),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materialize(
            bundle: _bundle(),
            project: project,
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: false,
            allowedEffectIds: _allMixEffectIds,
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

  test('group materialization targets only ready members', () async {
    final project = ProjectState(
      bpm: 120,
      masterGain0to3: 1,
      maxRows: 8,
      rows: <RowState>[
        _row(0, 10, 0.1, groupId: 'vocals'),
        _row(1, 20, 0, groupId: 'vocals', hasAudio: false, hasClips: false),
      ],
      trackGroups: const <TrackGroup>[
        TrackGroup(id: 'vocals', name: 'Vocals', rowIds: <int>[10, 20]),
      ],
      overlapMatrix: const <List<int>>[
        <int>[0, 0],
        <int>[0, 0],
      ],
      overlapRatioMatrix: const <List<double>>[
        <double>[0, 0],
        <double>[0, 0],
      ],
    );
    final result =
        await AiV3MixGoalMaterializer(
          mixModel: LocalMixingModel(),
          magnitudePredictor: _Predictor((actions) => actions),
        ).materialize(
          bundle: _bundle(
            target: const <String, dynamic>{
              'scope': 'group',
              'group_id': 'vocals',
              'group_name': 'Vocals',
            },
            intentKind: 'reverb',
            direction: 'up',
          ),
          project: project,
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: false,
          allowedEffectIds: _allMixEffectIds,
        );

    final raw = (result.bundle.actions.single.data['actions'] as List)
        .cast<Map<String, dynamic>>();
    expect(raw, isNotEmpty);
    expect(raw.every((action) => (action['data'] as Map)['row'] == 0), isTrue);
    expect(
      raw.every(
        (action) => (action['data'] as Map)['force_individual_row'] == true,
      ),
      isTrue,
    );
  });

  test(
    'eager grouped-row mixing normalizes every row action without mutating model output',
    () async {
      final modelActions = <MixAction>[
        MixAction('set_row_gain', <String, dynamic>{
          'row': 0,
          'mode': 'delta',
          'delta': 0.1,
        }),
        MixAction('set_row_pan', <String, dynamic>{
          'row': 0,
          'mode': 'delta',
          'delta': -0.1,
        }),
        MixAction('ensure_effect', <String, dynamic>{
          'row': 0,
          'effect_name_contains': 'Reverb',
        }),
        MixAction('delete_effect', <String, dynamic>{
          'row': 0,
          'effect_name_contains': 'Reverb',
        }),
        MixAction('adjust_effect_param_by_name', <String, dynamic>{
          'row': 0,
          'effect_name_contains': 'Reverb',
          'param_name_contains_any': <String>['Mix'],
          'mode': 'delta',
          'delta_norm': 0.1,
        }),
        MixAction('hard_reset_row_fx', <String, dynamic>{'row': 0}),
      ];
      final originalData = modelActions
          .map((action) => Map<String, dynamic>.from(action.data))
          .toList(growable: false);

      final result =
          await AiV3MixGoalMaterializer(
            mixModel: _FixedMixModel(modelActions),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materialize(
            bundle: _bundle(),
            project: _project(grouped: true),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: true,
            allowedEffectIds: _allMixEffectIds,
          );

      final raw = (result.bundle.actions.single.data['actions'] as List)
          .cast<Map<String, dynamic>>();
      expect(raw, hasLength(modelActions.length));
      for (var index = 0; index < raw.length; index++) {
        final outputData = Map<String, dynamic>.from(raw[index]['data'] as Map);
        expect(outputData.remove('force_individual_row'), isTrue);
        expect(outputData, originalData[index]);
        expect(modelActions[index].data, originalData[index]);
        expect(
          modelActions[index].data.containsKey('force_individual_row'),
          isFalse,
        );
      }
    },
  );

  test('refined eager row actions receive execution normalization', () async {
    List<MixAction>? inferenceActions;
    final result =
        await AiV3MixGoalMaterializer(
          mixModel: _FixedMixModel(<MixAction>[
            MixAction('set_row_gain', const <String, dynamic>{
              'row': 0,
              'mode': 'delta',
              'delta': 0.1,
            }),
          ]),
          magnitudePredictor: _Predictor(
            (actions) {
              inferenceActions = actions;
              return <MixAction>[
              MixAction('set_row_pan', const <String, dynamic>{
                'row': 0,
                'mode': 'delta',
                'delta': 0.1,
              }),
            ];
            },
          ),
        ).materialize(
          bundle: _bundle(),
          project: _project(grouped: true),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: false,
          allowedEffectIds: _allMixEffectIds,
        );

    final raw = (result.bundle.actions.single.data['actions'] as List)
        .cast<Map<String, dynamic>>();
    expect(inferenceActions!.single.data['force_individual_row'], isTrue);
    expect(raw, hasLength(1));
    expect(raw.single['type'], 'set_row_pan');
    expect((raw.single['data'] as Map)['force_individual_row'], isTrue);
  });

  test(
    'master mix actions never receive the row-only execution flag',
    () async {
      final result =
          await AiV3MixGoalMaterializer(
            mixModel: _FixedMixModel(<MixAction>[
              MixAction('set_master_gain', const <String, dynamic>{
                'mode': 'delta',
                'delta': 0.1,
              }),
              MixAction('set_master_pan', const <String, dynamic>{
                'mode': 'delta',
                'delta': -0.1,
              }),
              MixAction('ensure_master_effect', const <String, dynamic>{
                'effect_name_contains': 'Reverb',
              }),
              MixAction('delete_master_effect', const <String, dynamic>{
                'effect_name_contains': 'Reverb',
              }),
              MixAction(
                'adjust_master_effect_param_by_name',
                const <String, dynamic>{
                  'effect_name_contains': 'Reverb',
                  'param_name_contains_any': <String>['Mix'],
                  'mode': 'delta',
                  'delta_norm': 0.1,
                },
              ),
              MixAction('hard_reset_master_fx', const <String, dynamic>{}),
            ]),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materialize(
            bundle: _bundle(
              target: const <String, dynamic>{'scope': 'master'},
              intentKind: 'reverb',
            ),
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: true,
            allowedEffectIds: _allMixEffectIds,
          );

      final raw = (result.bundle.actions.single.data['actions'] as List)
          .cast<Map<String, dynamic>>();
      expect(raw, hasLength(6));
      expect(
        raw.every(
          (action) =>
              !(action['data'] as Map).containsKey('force_individual_row'),
        ),
        isTrue,
      );
    },
  );

  test('master readiness uses current playable state, not stale clips', () {
    final project = ProjectState(
      bpm: 120,
      masterGain0to3: 1,
      maxRows: 8,
      rows: <RowState>[_row(0, 10, 0, hasAudio: false)],
      overlapMatrix: const <List<int>>[
        <int>[0],
      ],
    );

    expect(
      () =>
          AiV3MixGoalMaterializer(
            mixModel: LocalMixingModel(),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materialize(
            bundle: _bundle(
              target: const <String, dynamic>{'scope': 'master'},
              intentKind: 'reverb',
              direction: 'up',
            ),
            project: project,
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: false,
            allowedEffectIds: _allMixEffectIds,
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

  test('bundle materialization rejects escaping heuristic actions', () async {
    expect(
      () =>
          AiV3MixGoalMaterializer(
            mixModel: _FixedMixModel(<MixAction>[
              MixAction('set_master_gain', const <String, dynamic>{
                'value': 1.0,
              }),
            ]),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materialize(
            bundle: _bundle(),
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: true,
            allowedEffectIds: _allMixEffectIds,
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

  test(
    'row-set materialization permits every row in the resolved set',
    () async {
      final result =
          await AiV3MixGoalMaterializer(
            mixModel: LocalMixingModel(),
            magnitudePredictor: _Predictor(
              (_) => <MixAction>[
                MixAction('set_row_gain', const <String, dynamic>{
                  'row': 0,
                  'value': 0.9,
                }),
                MixAction('set_row_pan', const <String, dynamic>{
                  'row': 1,
                  'value': 0.6,
                }),
              ],
            ),
          ).materializeSingleGoal(
            data: _bundle(
              target: const <String, dynamic>{'scope': 'all_rows'},
              intentKind: 'balance',
            ).actions.single.data,
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: false,
            allowedEffectIds: _allMixEffectIds,
            allowedTargetRowIds: const <int>{10, 20},
          );

      expect(result.actions, hasLength(2));
      expect(result.metadata['allowed_target_row_ids'], <int>[10, 20]);
    },
  );

  test(
    'all-row generation plans only inside current content-row scope',
    () async {
      final result =
          await AiV3MixGoalMaterializer(
            mixModel: LocalMixingModel(),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materializeSingleGoal(
            data: _bundle(
              target: const <String, dynamic>{'scope': 'all_rows'},
              intentKind: 'gain',
              direction: 'up',
            ).actions.single.data,
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: true,
            allowedEffectIds: _allMixEffectIds,
            allowedTargetRowIds: const <int>{10},
          );

      expect(result.actions, isNotEmpty);
      expect(result.actions.every((action) => action.data['row'] == 0), isTrue);
    },
  );

  test(
    'all-row FX reset respects the resolved row scope without touching master',
    () async {
      for (final allowedRows in <Set<int>>[
        {10},
        {10, 20},
      ]) {
        final result =
            await AiV3MixGoalMaterializer(
              mixModel: LocalMixingModel(),
              magnitudePredictor: _Predictor((actions) => actions),
            ).materializeSingleGoal(
              data: _bundle(
                target: {'scope': 'all_rows'},
                intentKind: 'balance',
                resetFx: true,
              ).actions.single.data,
              project: _project(),
              roleOverrides: const {},
              bypassLearnedMagnitudes: true,
              allowedEffectIds: _allMixEffectIds,
              allowedTargetRowIds: allowedRows,
            );
        final expectedIndexes = {
          if (allowedRows.contains(10)) 0,
          if (allowedRows.contains(20)) 1,
        };
        expect(
          result.actions
              .where((a) => a.type == 'hard_reset_row_fx')
              .map((a) => a.data['row'])
              .toSet(),
          expectedIndexes,
        );
        expect(
          result.actions.every((a) => expectedIndexes.contains(a.data['row'])),
          isTrue,
        );
      }
    },
  );

  test('FX reset preserves explicit row, group and master targets', () async {
    for (final target in <Map<String, dynamic>>[
      {'scope': 'row', 'row_id': 10, 'row_index': 0},
      {'scope': 'group', 'group_id': 'vocals'},
      {'scope': 'master'},
    ]) {
      final result =
          await AiV3MixGoalMaterializer(
            mixModel: LocalMixingModel(),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materializeSingleGoal(
            data: _bundle(
              target: target,
              intentKind: 'balance',
              resetFx: true,
            ).actions.single.data,
            project: _project(grouped: true),
            roleOverrides: const {},
            bypassLearnedMagnitudes: true,
            allowedEffectIds: _allMixEffectIds,
          );
      final resetRows = result.actions
          .where((a) => a.type == 'hard_reset_row_fx')
          .map((a) => a.data['row'])
          .toSet();
      expect(
        resetRows,
        target['scope'] == 'master'
            ? <int>{}
            : target['scope'] == 'row'
            ? {0}
            : {0, 1},
      );
      expect(
        result.actions.any((a) => a.type == 'hard_reset_master_fx'),
        target['scope'] == 'master',
      );
    }
  });

  test('legacy unscoped global FX reset still resets master and all rows', () {
    final result = LocalMixingModel().run(
      project: _project(),
      goal: GoalVector.fromJson({
        'type': 'mix_request',
        'target': {'scope': 'auto', 'confidence': 1.0},
        'intents': [
          {'kind': 'balance', 'confidence': 1.0},
        ],
        'reset_fx': true,
        'intensity': 0.6,
      }),
      strict: true,
    );
    expect(
      result.actions
          .where((a) => a.type == 'hard_reset_row_fx')
          .map((a) => a.data['row'])
          .toSet(),
      {0, 1},
    );
    expect(
      result.actions.where((a) => a.type == 'hard_reset_master_fx'),
      hasLength(1),
    );
    expect(result.actions.any((a) => a.type == 'set_master_gain'), isTrue);
    expect(result.actions.any((a) => a.type == 'set_master_pan'), isTrue);
  });

  test(
    'row-set materialization rejects unrelated rows and master actions',
    () async {
      for (final escaped in <MixAction>[
        MixAction('set_row_gain', const <String, dynamic>{
          'row': 1,
          'value': 1.0,
        }),
        MixAction('set_master_gain', const <String, dynamic>{'value': 1.0}),
      ]) {
        expect(
          () =>
              AiV3MixGoalMaterializer(
                mixModel: LocalMixingModel(),
                magnitudePredictor: _Predictor((_) => <MixAction>[escaped]),
              ).materializeSingleGoal(
                data: _bundle(
                  target: const <String, dynamic>{'scope': 'all_rows'},
                  intentKind: 'balance',
                ).actions.single.data,
                project: _project(),
                roleOverrides: const <int, String>{},
                bypassLearnedMagnitudes: false,
                allowedEffectIds: _allMixEffectIds,
                allowedTargetRowIds: const <int>{10},
              ),
          throwsA(
            isA<AiV3PreparationException>().having(
              (error) => error.code,
              'code',
              'v3_mix_action_target_invalid',
            ),
          ),
        );
      }
    },
  );

  test(
    'reference materialization never emits an action for the reference row',
    () async {
      final result =
          await AiV3MixGoalMaterializer(
            mixModel: LocalMixingModel(),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materialize(
            bundle: _bundle(reference: true),
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: false,
            allowedEffectIds: _allMixEffectIds,
          );

      expect(result.bundle.actions.single.type, 'v3_mix_actions');
      final wrapper = result.bundle.actions.single.data;
      expect(wrapper['protected_reference_row_index'], 1);
      final actions = (wrapper['actions'] as List).cast<Map>();
      expect(
        actions.any((action) => (action['data'] as Map)['row'] == 1),
        false,
      );
    },
  );

  test(
    'materializes a stable group target through the existing mix engine',
    () async {
      final result =
          await AiV3MixGoalMaterializer(
            mixModel: LocalMixingModel(),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materialize(
            bundle: _bundle(
              target: const <String, dynamic>{
                'scope': 'group',
                'group_id': 'vocals',
                'group_name': 'Vocals',
              },
              intentKind: 'reverb',
              direction: 'up',
            ),
            project: _project(grouped: true),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: false,
            allowedEffectIds: _allMixEffectIds,
          );

      final raw = (result.bundle.actions.single.data['actions'] as List)
          .cast<Map<String, dynamic>>();
      expect(raw, isNotEmpty);
      expect(
        raw.every((action) {
          final row = (action['data'] as Map)['row'];
          return row == null || row == 0 || row == 1;
        }),
        isTrue,
      );
    },
  );

  test(
    'bundle materialization contains group goals to current members',
    () async {
      expect(
        () =>
            AiV3MixGoalMaterializer(
              mixModel: LocalMixingModel(),
              magnitudePredictor: _Predictor(
                (_) => <MixAction>[
                  MixAction('set_master_gain', const <String, dynamic>{
                    'value': 1.0,
                  }),
                ],
              ),
            ).materialize(
              bundle: _bundle(
                target: const <String, dynamic>{
                  'scope': 'group',
                  'group_id': 'vocals',
                  'group_name': 'Vocals',
                },
                intentKind: 'balance',
              ),
              project: _project(grouped: true),
              roleOverrides: const <int, String>{},
              bypassLearnedMagnitudes: false,
              allowedEffectIds: _allMixEffectIds,
            ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_mix_action_target_invalid',
          ),
        ),
      );
    },
  );

  test(
    'materializes a master target through the existing mix engine',
    () async {
      final result =
          await AiV3MixGoalMaterializer(
            mixModel: LocalMixingModel(),
            magnitudePredictor: _Predictor((actions) => actions),
          ).materialize(
            bundle: _bundle(
              target: const <String, dynamic>{'scope': 'master'},
              intentKind: 'reverb',
              direction: 'up',
            ),
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: false,
            allowedEffectIds: _allMixEffectIds,
          );

      final raw = (result.bundle.actions.single.data['actions'] as List)
          .cast<Map<String, dynamic>>();
      expect(raw, isNotEmpty);
      expect(
        raw.any((action) => action['type'] == 'ensure_master_effect'),
        isTrue,
      );
    },
  );

  test('master materialization permits only master actions', () async {
    final result =
        await AiV3MixGoalMaterializer(
          mixModel: LocalMixingModel(),
          magnitudePredictor: _Predictor(
            (_) => <MixAction>[
              MixAction('set_master_gain', const <String, dynamic>{
                'mode': 'set',
                'value': 1.1,
              }),
            ],
          ),
        ).materializeSingleGoal(
          data: _bundle(
            target: const <String, dynamic>{'scope': 'master'},
            intentKind: 'reverb',
            direction: 'up',
          ).actions.single.data,
          project: _project(),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: false,
          allowedEffectIds: _allMixEffectIds,
        );

    expect(result.actions.single.type, 'set_master_gain');
    expect(result.metadata['master_only'], isTrue);
  });

  test('master materialization rejects row actions', () async {
    expect(
      () =>
          AiV3MixGoalMaterializer(
            mixModel: LocalMixingModel(),
            magnitudePredictor: _Predictor(
              (_) => <MixAction>[
                MixAction('set_row_gain', const <String, dynamic>{
                  'row': 0,
                  'mode': 'set',
                  'value': 1.0,
                }),
              ],
            ),
          ).materializeSingleGoal(
            data: _bundle(
              target: const <String, dynamic>{'scope': 'master'},
              intentKind: 'reverb',
              direction: 'up',
            ).actions.single.data,
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: false,
            allowedEffectIds: _allMixEffectIds,
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

  test('empty refinement is a non-blocking already-satisfied result', () async {
    final result =
        await AiV3MixGoalMaterializer(
          mixModel: LocalMixingModel(),
          magnitudePredictor: _Predictor((_) => const <MixAction>[]),
        ).materialize(
          bundle: _bundle(),
          project: _project(),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: false,
          allowedEffectIds: _allMixEffectIds,
        );

    expect(result.isNoChange, isTrue);
    expect(result.bundle.receipts.single['status'], 'already_satisfied');
  });

  test('refinement timeout falls back to the factual local mix', () async {
    final result =
        await AiV3MixGoalMaterializer(
          mixModel: LocalMixingModel(),
          magnitudePredictor: _AsyncPredictor(
            (_) => Completer<MagnitudeRefineResult>().future,
          ),
          refinementTimeout: const Duration(milliseconds: 10),
        ).materialize(
          bundle: _bundle(),
          project: _project(),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: false,
          allowedEffectIds: _allMixEffectIds,
        );

    expect(result.bundle.actions.single.type, 'v3_mix_actions');
    final steps = (result.metadata['mix_materialization_steps'] as List)
        .cast<Map>();
    expect(steps.single['refinement_fallback_used'], isTrue);
    expect(steps.single['refinement_fallback_reason'], 'refinement_timeout');
  });

  test('refinement failure falls back to the factual local mix', () async {
    final result =
        await AiV3MixGoalMaterializer(
          mixModel: LocalMixingModel(),
          magnitudePredictor: _AsyncPredictor(
            (_) => Future<MagnitudeRefineResult>.error(
              StateError('refinement unavailable'),
            ),
          ),
        ).materialize(
          bundle: _bundle(),
          project: _project(),
          roleOverrides: const <int, String>{},
          bypassLearnedMagnitudes: false,
          allowedEffectIds: _allMixEffectIds,
        );

    expect(result.bundle.actions.single.type, 'v3_mix_actions');
    final steps = (result.metadata['mix_materialization_steps'] as List)
        .cast<Map>();
    expect(steps.single['refinement_fallback_used'], isTrue);
    expect(steps.single['refinement_fallback_reason'], 'refinement_failed');
  });

  test('rejects an unsupported action emitted by refinement', () async {
    expect(
      () =>
          AiV3MixGoalMaterializer(
            mixModel: LocalMixingModel(),
            magnitudePredictor: _Predictor(
              (_) => <MixAction>[MixAction('invent_plugin', const {})],
            ),
          ).materialize(
            bundle: _bundle(),
            project: _project(),
            roleOverrides: const <int, String>{},
            bypassLearnedMagnitudes: false,
            allowedEffectIds: _allMixEffectIds,
          ),
      throwsA(
        isA<AiV3PreparationException>().having(
          (error) => error.code,
          'code',
          'v3_mix_action_unsupported',
        ),
      ),
    );
  });

  test(
    'rejects destructive mix writes to a directly targeted effect row',
    () async {
      final base = _bundle();
      final bundle = AiV3PreparedBundle(
        plan: base.plan,
        stateDigest: base.stateDigest,
        actions: <AssistantAction>[
          AssistantAction(
            type: 'v3_effect_instance_edit',
            data: const <String, dynamic>{
              'operation': 'set_bypassed',
              'effect_instance_id': 'instance-1',
              'effect_id': 'builtin.reverb',
              'bypassed': true,
              'target': <String, dynamic>{
                'scope': 'row',
                'row_id': 10,
                'row_index': 0,
              },
            },
          ),
          ...base.actions,
        ],
        receipts: base.receipts,
        preview: base.preview,
      );
      expect(
        () =>
            AiV3MixGoalMaterializer(
              mixModel: LocalMixingModel(),
              magnitudePredictor: _Predictor(
                (_) => <MixAction>[
                  MixAction('delete_effect', const <String, dynamic>{'row': 0}),
                ],
              ),
            ).materialize(
              bundle: bundle,
              project: _project(),
              roleOverrides: const <int, String>{},
              bypassLearnedMagnitudes: false,
              allowedEffectIds: _allMixEffectIds,
            ),
        throwsA(
          isA<AiV3PreparationException>().having(
            (error) => error.code,
            'code',
            'v3_effect_instance_mix_conflict',
          ),
        ),
      );
    },
  );
}
