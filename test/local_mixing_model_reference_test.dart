import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/local_mixing_model.dart';
import 'package:mixroom/models/goal_vector.dart';
import 'package:mixroom/models/project_state.dart';

RowState _row(
  int index, {
  required double rms,
  required Map<String, double> audioStats,
  double gain0to3 = 1.0,
  double pan0to1 = 0.5,
  List<EffectState> effects = const [],
}) {
  return RowState(
    rowIndex: index,
    clips: [
      ClipState(
        startMs: 0.0,
        endMs: 4000.0,
        fileName: 'track_$index.wav',
      ),
    ],
    approxRms: rms,
    approxCrest: 1.7,
    roleProbs: const {
      'vocals': 0.15,
      'drums': 0.2,
      'bass': 0.2,
      'guitar': 0.15,
      'synth': 0.2,
      'other': 0.1,
    },
    roleConsistency: 0.92,
    clipTopRoles: const ['other'],
    audioStats: audioStats,
    interpretation: RowInterpretationState.empty,
    gain0to3: gain0to3,
    pan0To1: pan0to1,
    effects: effects,
    volumeAutomation: const [],
    hasAudio: true,
  );
}

void main() {
  test('reference-guided mix excludes the reference row and avoids master ops',
      () {
    final project = ProjectState(
      bpm: 124.0,
      masterGain0to3: 1.0,
      masterPan0to1: 0.5,
      maxRows: 3,
      rows: [
        _row(
          0,
          rms: 0.12,
          audioStats: const {
            'centroid_hz': 1100.0,
            'spectral_rolloff_hz': 2200.0,
            'spectral_slope': -0.45,
            'hf_rms': 0.10,
            'bassiness': 0.18,
            'sibilance': 0.08,
            'side_ratio': 0.12,
            'phase_corr': 0.95,
            'stereo_imbalance': 0.03,
            'integrated_lufs_est': -17.0,
            'true_peak_dbfs': -5.0,
            'lra_est': 7.0,
            'transient_density': 0.58,
            'clip_ratio': 0.02,
            'st_rms_std': 0.13,
          },
        ),
        _row(
          1,
          rms: 0.10,
          audioStats: const {
            'centroid_hz': 1250.0,
            'spectral_rolloff_hz': 2400.0,
            'spectral_slope': -0.40,
            'hf_rms': 0.12,
            'bassiness': 0.20,
            'sibilance': 0.09,
            'side_ratio': 0.14,
            'phase_corr': 0.93,
            'stereo_imbalance': 0.05,
            'integrated_lufs_est': -16.4,
            'true_peak_dbfs': -5.5,
            'lra_est': 6.5,
            'transient_density': 0.54,
            'clip_ratio': 0.03,
            'st_rms_std': 0.12,
          },
        ),
        _row(
          2,
          rms: 0.26,
          audioStats: const {
            'centroid_hz': 2800.0,
            'spectral_rolloff_hz': 5400.0,
            'spectral_slope': -0.10,
            'hf_rms': 0.42,
            'bassiness': 0.34,
            'sibilance': 0.10,
            'side_ratio': 0.62,
            'phase_corr': 0.52,
            'stereo_imbalance': 0.02,
            'integrated_lufs_est': -10.2,
            'true_peak_dbfs': -1.5,
            'lra_est': 3.4,
            'transient_density': 0.26,
            'clip_ratio': 0.10,
            'st_rms_std': 0.05,
          },
        ),
      ],
      overlapMatrix: List<List<int>>.generate(3, (_) => List<int>.filled(3, 0)),
      overlapRatioMatrix:
          List<List<double>>.generate(3, (_) => List<double>.filled(3, 0.0)),
    );

    final goal = GoalVector(
      type: 'mix_request',
      intents: [
        MixIntent(kind: 'balance', confidence: 1.0),
      ],
      target: MixTarget(scope: 'auto', confidence: 0.9),
      intensity: 0.65,
      executionProfile: MixExecutionProfile.producerSafe,
      audibility: MixAudibility.obvious,
      referenceTarget: const MixReferenceTarget(
        rowIndex: 2,
        confidence: 0.95,
      ),
      referenceMode: MixReferenceMode.fullMix,
      referenceCloseness: MixReferenceCloseness.balanced,
    );

    final result = LocalMixingModel().run(
      project: project,
      goal: goal,
      strict: true,
    );

    expect(result.actions, isNotEmpty);
    expect(
      result.actions.any((action) =>
          action.type.contains('master') ||
          action.type.startsWith('set_master')),
      isFalse,
    );
    expect(
      result.actions.any((action) => action.data['row'] == 2),
      isFalse,
    );
    expect(
      result.actions.any((action) => action.data['row'] == 0),
      isTrue,
    );
  });

  test('mix execution lanes produce progressively stronger reverb moves', () {
    final project = ProjectState(
      bpm: 124.0,
      masterGain0to3: 1.0,
      masterPan0to1: 0.5,
      maxRows: 1,
      rows: [
        _row(
          0,
          rms: 0.14,
          audioStats: const {
            'centroid_hz': 1500.0,
            'spectral_rolloff_hz': 2800.0,
            'spectral_slope': -0.35,
            'hf_rms': 0.16,
            'bassiness': 0.18,
            'sibilance': 0.06,
            'side_ratio': 0.22,
            'phase_corr': 0.91,
            'stereo_imbalance': 0.02,
            'integrated_lufs_est': -15.5,
            'true_peak_dbfs': -4.5,
            'lra_est': 6.4,
            'transient_density': 0.35,
            'clip_ratio': 0.03,
            'st_rms_std': 0.09,
          },
        ),
      ],
      overlapMatrix: const [
        [0],
      ],
      overlapRatioMatrix: const [
        [0.0],
      ],
    );

    GoalVector goalFor(
      MixExecutionProfile profile,
      MixAudibility audibility,
    ) {
      return GoalVector(
        type: 'mix_request',
        intents: [
          MixIntent(
            kind: 'reverb',
            direction: 'up',
            confidence: 1.0,
          ),
        ],
        target: MixTarget(
          rowIndex: 0,
          scope: 'row',
          confidence: 0.95,
        ),
        intensity: 0.55,
        executionProfile: profile,
        audibility: audibility,
      );
    }

    double maxReverbDelta(GoalVector goal) {
      final result = LocalMixingModel().run(
        project: project,
        goal: goal,
        strict: true,
      );
      return result.actions
          .where((action) =>
              action.type == 'adjust_effect_param_by_name' &&
              action.data['effect_name_contains'] == 'Reverb')
          .map((action) =>
              ((action.data['delta_norm'] as num?) ?? 0).toDouble().abs())
          .fold<double>(0.0, (best, value) => value > best ? value : best);
    }

    final safeDelta = maxReverbDelta(
      goalFor(MixExecutionProfile.producerSafe, MixAudibility.noticeable),
    );
    final boldDelta = maxReverbDelta(
      goalFor(MixExecutionProfile.creativeBold, MixAudibility.obvious),
    );
    final extremeDelta = maxReverbDelta(
      goalFor(
        MixExecutionProfile.experimentalExtreme,
        MixAudibility.extreme,
      ),
    );

    expect(safeDelta, greaterThan(0.0));
    expect(boldDelta, greaterThan(safeDelta));
    expect(extremeDelta, greaterThan(boldDelta));
  });

  test('reset_fx only resets the targeted row for row-scoped requests', () {
    final project = ProjectState(
      bpm: 124.0,
      masterGain0to3: 1.0,
      masterPan0to1: 0.5,
      maxRows: 2,
      rows: [
        _row(
          0,
          rms: 0.14,
          audioStats: const {
            'centroid_hz': 1500.0,
            'spectral_rolloff_hz': 2800.0,
            'spectral_slope': -0.35,
            'hf_rms': 0.16,
            'bassiness': 0.18,
            'sibilance': 0.06,
            'side_ratio': 0.22,
            'phase_corr': 0.91,
            'stereo_imbalance': 0.02,
            'integrated_lufs_est': -15.5,
            'true_peak_dbfs': -4.5,
            'lra_est': 6.4,
            'transient_density': 0.35,
            'clip_ratio': 0.03,
            'st_rms_std': 0.09,
          },
          effects: const [
            EffectState(
              effectIndex: 0,
              name: 'Delay',
              isBypassed: false,
              parameters: [],
            ),
          ],
        ),
        _row(
          1,
          rms: 0.12,
          audioStats: const {
            'centroid_hz': 1300.0,
            'spectral_rolloff_hz': 2600.0,
            'spectral_slope': -0.32,
            'hf_rms': 0.14,
            'bassiness': 0.14,
            'sibilance': 0.05,
            'side_ratio': 0.18,
            'phase_corr': 0.94,
            'stereo_imbalance': 0.01,
            'integrated_lufs_est': -16.2,
            'true_peak_dbfs': -5.0,
            'lra_est': 6.0,
            'transient_density': 0.31,
            'clip_ratio': 0.02,
            'st_rms_std': 0.08,
          },
          effects: const [
            EffectState(
              effectIndex: 0,
              name: 'Reverb',
              isBypassed: false,
              parameters: [],
            ),
          ],
        ),
      ],
      masterEffects: const [
        EffectState(
          effectIndex: 0,
          name: 'Limiter',
          isBypassed: false,
          parameters: [],
        ),
      ],
      overlapMatrix: const [
        [0, 0],
        [0, 0],
      ],
      overlapRatioMatrix: const [
        [0.0, 0.0],
        [0.0, 0.0],
      ],
    );

    final goal = GoalVector(
      type: 'mix_request',
      intents: [
        MixIntent(kind: 'distortion', direction: 'up', confidence: 1.0),
      ],
      target: MixTarget(rowIndex: 1, scope: 'row', confidence: 0.95),
      intensity: 0.8,
      executionProfile: MixExecutionProfile.creativeBold,
      audibility: MixAudibility.obvious,
      resetFx: true,
    );

    final result = LocalMixingModel().run(
      project: project,
      goal: goal,
      strict: true,
    );

    expect(
      result.actions.where((action) => action.type == 'hard_reset_row_fx'),
      hasLength(1),
    );
    expect(
      result.actions.any(
        (action) => action.type == 'hard_reset_row_fx' && action.data['row'] == 1,
      ),
      isTrue,
    );
    expect(
      result.actions.any(
        (action) => action.type == 'hard_reset_row_fx' && action.data['row'] == 0,
      ),
      isFalse,
    );
    expect(
      result.actions.any((action) => action.type == 'hard_reset_master_fx'),
      isFalse,
    );
  });
}
