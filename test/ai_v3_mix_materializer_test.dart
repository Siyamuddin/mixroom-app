import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/local_mixing_model.dart';
import 'package:mixroom/ai/magnitude_predictor.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_mix_materializer.dart';
import 'package:mixroom/ai/v3/ai_v3_preparer.dart';
import 'package:mixroom/models/goal_vector.dart';
import 'package:mixroom/models/mixing_result.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/models/project_state.dart';

class _Predictor implements MixingMagnitudePredictor {
  const _Predictor(this.transform);

  final List<MixAction> Function(List<MixAction>) transform;

  @override
  bool get isEnabled => true;

  @override
  bool get isReady => true;

  @override
  Map<String, dynamic> get observabilityContext =>
      const <String, dynamic>{'source': 'test'};

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
  }) async =>
      MagnitudeRefineResult(
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
  }) {
    seenRoleOverrides.add(Map<int, String>.from(roleOverrides));
    return const MixingResult(
      actions: <MixAction>[],
      summary: 'No changes.',
      isNoOp: true,
    );
  }
}

RowState _row(int index, int id, double rms, {String groupId = ''}) => RowState(
      rowIndex: index,
      rowId: id,
      rowName: index == 0 ? 'Vocal' : 'Reference',
      groupId: groupId,
      clips: <ClipState>[
        ClipState(startMs: 0, endMs: 4000, fileName: 'row_$index.wav'),
      ],
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
      hasAudio: true,
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
              TrackGroup(
                id: 'vocals',
                name: 'Vocals',
                rowIds: <int>[10, 20],
              ),
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
          'target': target ??
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
              'descriptor': null,
            },
          ],
          'intensity': 0.6,
          'execution_profile': 'producer_safe',
          'audibility': 'noticeable',
          'style_tags': const <String>[],
          'reset_fx': false,
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
      );
      return model.seenRoleOverrides.single;
    }

    expect(await rolesSeen(roleFirst: true), <int, String>{0: 'drums'});
    expect(await rolesSeen(roleFirst: false), <int, String>{0: 'vocals'});
  });

  test('materializes a subjective goal into existing concrete MixActions',
      () async {
    final result = await AiV3MixGoalMaterializer(
      mixModel: LocalMixingModel(),
      magnitudePredictor: _Predictor((actions) => actions),
    ).materialize(
      bundle: _bundle(),
      project: _project(),
      roleOverrides: const <int, String>{},
      bypassLearnedMagnitudes: false,
    );

    expect(result.bundle.actions.single.type, 'v3_mix_actions');
    final raw = result.bundle.actions.single.data['actions'] as List;
    expect(raw, isNotEmpty);
    expect(raw.any((action) => (action as Map)['type'] == 'ensure_effect'),
        isTrue);
    expect(result.metadata, contains('mix_materialization_steps'));
  });

  test('reference materialization never emits an action for the reference row',
      () async {
    final result = await AiV3MixGoalMaterializer(
      mixModel: LocalMixingModel(),
      magnitudePredictor: _Predictor((actions) => actions),
    ).materialize(
      bundle: _bundle(reference: true),
      project: _project(),
      roleOverrides: const <int, String>{},
      bypassLearnedMagnitudes: false,
    );

    expect(result.bundle.actions.single.type, 'v3_mix_actions');
    final wrapper = result.bundle.actions.single.data;
    expect(wrapper['protected_reference_row_index'], 1);
    final actions = (wrapper['actions'] as List).cast<Map>();
    expect(actions.any((action) => (action['data'] as Map)['row'] == 1), false);
  });

  test('materializes a stable group target through the existing mix engine',
      () async {
    final result = await AiV3MixGoalMaterializer(
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
  });

  test('materializes a master target through the existing mix engine',
      () async {
    final result = await AiV3MixGoalMaterializer(
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
    );

    final raw = (result.bundle.actions.single.data['actions'] as List)
        .cast<Map<String, dynamic>>();
    expect(raw, isNotEmpty);
    expect(
        raw.any((action) => action['type'] == 'ensure_master_effect'), isTrue);
  });

  test('empty refinement is a non-blocking already-satisfied result', () async {
    final result = await AiV3MixGoalMaterializer(
      mixModel: LocalMixingModel(),
      magnitudePredictor: _Predictor((_) => const <MixAction>[]),
    ).materialize(
      bundle: _bundle(),
      project: _project(),
      roleOverrides: const <int, String>{},
      bypassLearnedMagnitudes: false,
    );

    expect(result.isNoChange, isTrue);
    expect(result.bundle.receipts.single['status'], 'already_satisfied');
  });

  test('rejects an unsupported action emitted by refinement', () async {
    expect(
      () => AiV3MixGoalMaterializer(
        mixModel: LocalMixingModel(),
        magnitudePredictor: _Predictor(
          (_) => <MixAction>[MixAction('invent_plugin', const {})],
        ),
      ).materialize(
        bundle: _bundle(),
        project: _project(),
        roleOverrides: const <int, String>{},
        bypassLearnedMagnitudes: false,
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

  test('rejects destructive mix writes to a directly targeted effect row',
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
      () => AiV3MixGoalMaterializer(
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
      ),
      throwsA(isA<AiV3PreparationException>().having(
        (error) => error.code,
        'code',
        'v3_effect_instance_mix_conflict',
      )),
    );
  });
}
