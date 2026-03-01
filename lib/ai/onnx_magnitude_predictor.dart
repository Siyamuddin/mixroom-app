import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'ai_debug.dart';
import '../models/goal_vector.dart';
import '../models/mixing_result.dart';
import '../models/project_state.dart';
import 'magnitude_predictor.dart';

class OnnxMixingMagnitudePredictor implements MixingMagnitudePredictor {
  // Must match tools/ai_mixing/* FEATURE_COLUMNS exactly (same order).
  static const List<String> kFeatureColumns = <String>[
    'goal_intensity',
    'strict_execute',
    'project_bpm_norm',
    'rows_with_audio_ratio',
    'median_rms',
    'count_row_gain_ops_norm',
    'count_row_pan_ops_norm',
    'count_fx_ops_norm',
    'count_master_ops_norm',
    'scope_auto',
    'scope_row',
    'scope_master',
    'kind_balance',
    'kind_gain',
    'kind_pan',
    'kind_eq',
    'kind_compressor',
    'kind_limiter',
    'kind_reverb',
    'kind_delay',
    'kind_deesser',
    'kind_distortion',
    'median_crest_norm',
    'rms_iqr',
    'median_centroid_norm',
    'median_zcr',
    'median_sibilance_norm',
    'median_bassiness_norm',
    'median_hf_rms_norm',
    'median_st_rms_mean',
    'median_st_rms_p95',
    'median_st_rms_std',
    'median_transient_density',
    'overlap_density',
    'masking_pair_ratio',
    'centroid_collision_ratio',
    'avg_overlap_centroid_gap_norm',
    'overlap_rms_pressure',
    'role_overlap_ratio',
    'st_dynamic_headroom',
    'median_true_peak_norm',
    'median_integrated_lufs_norm',
    'median_short_lufs_mean_norm',
    'median_short_lufs_p95_norm',
    'median_lra_norm',
    'median_clip_ratio',
    'median_spectral_flatness',
    'median_spectral_rolloff_norm',
    'median_spectral_slope_norm',
    'median_spectral_flux',
    'median_phase_corr_norm',
    'median_side_ratio_norm',
    'median_stereo_imbalance',
    'median_silence_ratio',
    'median_onset_rate_norm',
    'median_noise_floor_norm',
    'median_spectral_bandwidth_norm',
    'overlap_low_collision',
    'overlap_lowmid_collision',
    'overlap_mid_collision',
    'overlap_high_collision',
    'ai_action_magnitude',
    'is_master_action',
    'action_set_row_gain',
    'action_set_row_pan',
    'action_set_master_gain',
    'action_set_master_pan',
    'action_adjust_effect_param_by_name',
    'action_adjust_master_effect_param_by_name',
    'action_ensure_effect',
    'action_ensure_master_effect',
    'action_delete_effect',
    'action_delete_master_effect',
    'action_hard_reset_row_fx',
    'action_hard_reset_master_fx',
    'action_other',
  ];
  static final int kFeatureCount = kFeatureColumns.length;

  final bool enabled;
  final String applyModelAsset;
  final String magnitudeModelAsset;
  final double applyThreshold;

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _applySession;
  OrtSession? _magnitudeSession;

  OnnxMixingMagnitudePredictor({
    required this.enabled,
    required this.applyModelAsset,
    required this.magnitudeModelAsset,
    this.applyThreshold = 0.5,
  });

  @override
  bool get isEnabled => enabled;

  @override
  bool get isReady {
    if (!enabled) return true;
    return _applySession != null && _magnitudeSession != null;
  }

  @override
  Future<void> load() async {
    if (!enabled) return;

    aiDebugLog(
      'onnx-mag',
      'loading assets apply="$applyModelAsset" magnitude="$magnitudeModelAsset"',
    );
    try {
      _applySession = await _ort.createSessionFromAsset(applyModelAsset);
      aiDebugLog('onnx-mag', 'apply model loaded');
    } catch (_) {
      _applySession = null;
      aiDebugLog('onnx-mag', 'apply model load failed');
    }

    try {
      _magnitudeSession =
          await _ort.createSessionFromAsset(magnitudeModelAsset);
      aiDebugLog('onnx-mag', 'magnitude model loaded');
    } catch (_) {
      _magnitudeSession = null;
      aiDebugLog('onnx-mag', 'magnitude model load failed');
    }
  }

  @override
  Future<MagnitudeRefineResult> refine({
    required ProjectState project,
    required GoalVector goal,
    required List<MixAction> actions,
    required bool strict,
  }) async {
    if (actions.isEmpty) {
      return const MagnitudeRefineResult(actions: [], fallbackUsed: false);
    }
    if (!enabled) {
      aiDebugLog('onnx-mag', 'disabled -> fallback');
      return MagnitudeRefineResult(
        actions: actions,
        fallbackUsed: true,
        fallbackReason: 'disabled',
      );
    }
    if (_applySession == null || _magnitudeSession == null) {
      aiDebugLog('onnx-mag', 'model_not_ready -> fallback');
      return MagnitudeRefineResult(
        actions: actions,
        fallbackUsed: true,
        fallbackReason: 'model_not_ready',
      );
    }

    final contextFeatures = _buildContextFeatures(
      project: project,
      goal: goal,
      actions: actions,
      strict: strict,
    );
    if (contextFeatures.length + _actionFeatureCount != kFeatureCount) {
      aiDebugLog(
        'onnx-mag',
        'feature contract mismatch context=${contextFeatures.length} action=$_actionFeatureCount totalExpected=$kFeatureCount',
      );
      return MagnitudeRefineResult(
        actions: actions,
        fallbackUsed: true,
        fallbackReason: 'feature_contract_mismatch',
      );
    }

    final refined = <MixAction>[];
    for (final action in actions) {
      final features = <double>[
        ...contextFeatures,
        ..._buildActionFeatures(project, action),
      ];
      if (features.length != kFeatureCount) {
        aiDebugLog(
          'onnx-mag',
          'feature contract mismatch built=${features.length} expected=$kFeatureCount',
        );
        return MagnitudeRefineResult(
          actions: actions,
          fallbackUsed: true,
          fallbackReason: 'feature_contract_mismatch',
        );
      }

      final applyScore = await _predictApplyScore(_applySession!, features);
      final rawMagnitude = await _predictScalar(_magnitudeSession!, features);

      if (applyScore == null || rawMagnitude == null) {
        aiDebugLog(
          'onnx-mag',
          'inference failed action=${action.type} applyScore=$applyScore rawMagnitude=$rawMagnitude',
        );
        return MagnitudeRefineResult(
          actions: actions,
          fallbackUsed: true,
          fallbackReason: 'inference_failed',
        );
      }

      // Match training clamp (0..3).
      var predictedScale = rawMagnitude.clamp(0.0, 3.0);
      var decision = 'keep';

      if (applyScore < 0.15) {
        if (!strict) {
          aiDebugLog(
            'onnx-mag',
            'action=${action.type} applyScore=${applyScore.toStringAsFixed(3)} rawScale=${rawMagnitude.toStringAsFixed(3)} decision=drop(strict=false)',
          );
          continue;
        }
        predictedScale = math.min(predictedScale, 0.25);
        decision = 'strong_attenuate';
      }

      if (applyScore < applyThreshold) {
        if (!strict) {
          predictedScale = math.min(predictedScale, 0.35);
          decision = 'attenuate_non_strict';
        } else {
          predictedScale = math.min(predictedScale, 0.65);
          if (decision == 'keep') {
            decision = 'attenuate_strict';
          }
        }
      }

      aiDebugLog(
        'onnx-mag',
        'action=${action.type} applyScore=${applyScore.toStringAsFixed(3)} rawScale=${rawMagnitude.toStringAsFixed(3)} finalScale=${predictedScale.toStringAsFixed(3)} decision=$decision strict=$strict',
      );
      if (kAiDebugVerbose) {
        aiDebugLog(
          'onnx-mag',
          'actionData=${aiDebugShortMap(action.data)}',
        );
      }
      refined.add(_scaleAction(project, action, predictedScale));
    }

    return MagnitudeRefineResult(
      actions: refined,
      fallbackUsed: false,
    );
  }

  static const int _actionFeatureCount = 15;

  List<double> _buildContextFeatures({
    required ProjectState project,
    required GoalVector goal,
    required List<MixAction> actions,
    required bool strict,
  }) {
    final rowsWithAudio = project.rows.where((r) => r.hasAudio).toList();
    final rms = rowsWithAudio.map((r) => r.approxRms).toList()..sort();
    final crestNorm = rowsWithAudio
        .map((r) => (r.approxCrest / 20.0).clamp(0.0, 1.0))
        .toList()
      ..sort();
    final centroidNorm = rowsWithAudio
        .map((r) => (_audioStat(r, 'centroid_hz') / 8000.0).clamp(0.0, 1.0))
        .toList()
      ..sort();
    final zcr = rowsWithAudio
        .map((r) => _audioStat(r, 'zcr').clamp(0.0, 1.0))
        .toList()
      ..sort();
    final sibilance = rowsWithAudio
        .map((r) => (_audioStat(r, 'sibilance') / 5.0).clamp(0.0, 1.0))
        .toList()
      ..sort();
    final bassiness = rowsWithAudio
        .map((r) => (_audioStat(r, 'bassiness') / 5.0).clamp(0.0, 1.0))
        .toList()
      ..sort();
    final hfRms = rowsWithAudio
        .map((r) => _audioStat(r, 'hf_rms').clamp(0.0, 1.0))
        .toList()
      ..sort();
    final stRmsMean = rowsWithAudio
        .map((r) => _audioStat(r, 'st_rms_mean').clamp(0.0, 1.0))
        .toList()
      ..sort();
    final stRmsP95 = rowsWithAudio
        .map((r) => _audioStat(r, 'st_rms_p95').clamp(0.0, 1.0))
        .toList()
      ..sort();
    final stRmsStd = rowsWithAudio
        .map((r) => _audioStat(r, 'st_rms_std').clamp(0.0, 1.0))
        .toList()
      ..sort();
    final transientDensity = rowsWithAudio
        .map((r) => _audioStat(r, 'transient_density').clamp(0.0, 1.0))
        .toList()
      ..sort();
    final truePeakNorm = rowsWithAudio
        .map((r) => _normDbfs(_audioStat(r, 'true_peak_dbfs')))
        .toList()
      ..sort();
    final integratedLufsNorm = rowsWithAudio
        .map((r) => _normLufsDb(_audioStat(r, 'integrated_lufs_est')))
        .toList()
      ..sort();
    final shortLufsMeanNorm = rowsWithAudio
        .map((r) => _normLufsDb(_audioStat(r, 'short_lufs_mean')))
        .toList()
      ..sort();
    final shortLufsP95Norm = rowsWithAudio
        .map((r) => _normLufsDb(_audioStat(r, 'short_lufs_p95')))
        .toList()
      ..sort();
    final lraNorm = rowsWithAudio
        .map((r) => (_audioStat(r, 'lra_est') / 40.0).clamp(0.0, 1.0))
        .toList()
      ..sort();
    final clipRatio = rowsWithAudio
        .map((r) => _audioStat(r, 'clip_ratio').clamp(0.0, 1.0))
        .toList()
      ..sort();
    final spectralFlatness = rowsWithAudio
        .map((r) => _audioStat(r, 'spectral_flatness').clamp(0.0, 1.0))
        .toList()
      ..sort();
    final spectralRolloffNorm = rowsWithAudio
        .map((r) =>
            (_audioStat(r, 'spectral_rolloff_hz') / 8000.0).clamp(0.0, 1.0))
        .toList()
      ..sort();
    final spectralSlopeNorm = rowsWithAudio
        .map((r) => _normSlope(_audioStat(r, 'spectral_slope')))
        .toList()
      ..sort();
    final spectralFlux = rowsWithAudio
        .map((r) => _audioStat(r, 'spectral_flux').clamp(0.0, 1.0))
        .toList()
      ..sort();
    final phaseCorrNorm = rowsWithAudio
        .map((r) => _normPhaseCorr(_audioStat(r, 'phase_corr')))
        .toList()
      ..sort();
    final sideRatioNorm = rowsWithAudio
        .map((r) => (_audioStat(r, 'side_ratio') / 2.0).clamp(0.0, 1.0))
        .toList()
      ..sort();
    final stereoImbalance = rowsWithAudio
        .map((r) => _audioStat(r, 'stereo_imbalance').clamp(0.0, 1.0))
        .toList()
      ..sort();
    final silenceRatio = rowsWithAudio
        .map((r) => _audioStat(r, 'silence_ratio').clamp(0.0, 1.0))
        .toList()
      ..sort();
    final onsetRateNorm = rowsWithAudio
        .map((r) => (_audioStat(r, 'onset_rate_hz') / 20.0).clamp(0.0, 1.0))
        .toList()
      ..sort();
    final noiseFloorNorm = rowsWithAudio
        .map((r) => _normDbfs(_audioStat(r, 'noise_floor_dbfs')))
        .toList()
      ..sort();
    final spectralBandwidthNorm = rowsWithAudio
        .map((r) =>
            (_audioStat(r, 'spectral_bandwidth_hz') / 8000.0).clamp(0.0, 1.0))
        .toList()
      ..sort();

    double medianRms = 0.0;
    if (rms.isNotEmpty) {
      final mid = rms.length ~/ 2;
      medianRms = rms.length.isOdd ? rms[mid] : (rms[mid - 1] + rms[mid]) * 0.5;
    }
    final rmsIqr = rms.isEmpty ? 0.0 : (_q(rms, 0.75) - _q(rms, 0.25));
    final medianCrestNorm = crestNorm.isEmpty ? 0.0 : _q(crestNorm, 0.5);
    final medianCentroidNorm =
        centroidNorm.isEmpty ? 0.0 : _q(centroidNorm, 0.5);
    final medianZcr = zcr.isEmpty ? 0.0 : _q(zcr, 0.5);
    final medianSibilanceNorm = sibilance.isEmpty ? 0.0 : _q(sibilance, 0.5);
    final medianBassinessNorm = bassiness.isEmpty ? 0.0 : _q(bassiness, 0.5);
    final medianHfRms = hfRms.isEmpty ? 0.0 : _q(hfRms, 0.5);
    final medianStRmsMean = stRmsMean.isEmpty ? 0.0 : _q(stRmsMean, 0.5);
    final medianStRmsP95 = stRmsP95.isEmpty ? 0.0 : _q(stRmsP95, 0.5);
    final medianStRmsStd = stRmsStd.isEmpty ? 0.0 : _q(stRmsStd, 0.5);
    final medianTransientDensity =
        transientDensity.isEmpty ? 0.0 : _q(transientDensity, 0.5);
    final medianTruePeakNorm =
        truePeakNorm.isEmpty ? 0.0 : _q(truePeakNorm, 0.5);
    final medianIntegratedLufsNorm =
        integratedLufsNorm.isEmpty ? 0.0 : _q(integratedLufsNorm, 0.5);
    final medianShortLufsMeanNorm =
        shortLufsMeanNorm.isEmpty ? 0.0 : _q(shortLufsMeanNorm, 0.5);
    final medianShortLufsP95Norm =
        shortLufsP95Norm.isEmpty ? 0.0 : _q(shortLufsP95Norm, 0.5);
    final medianLraNorm = lraNorm.isEmpty ? 0.0 : _q(lraNorm, 0.5);
    final medianClipRatio = clipRatio.isEmpty ? 0.0 : _q(clipRatio, 0.5);
    final medianSpectralFlatness =
        spectralFlatness.isEmpty ? 0.0 : _q(spectralFlatness, 0.5);
    final medianSpectralRolloffNorm =
        spectralRolloffNorm.isEmpty ? 0.0 : _q(spectralRolloffNorm, 0.5);
    final medianSpectralSlopeNorm =
        spectralSlopeNorm.isEmpty ? 0.0 : _q(spectralSlopeNorm, 0.5);
    final medianSpectralFlux =
        spectralFlux.isEmpty ? 0.0 : _q(spectralFlux, 0.5);
    final medianPhaseCorrNorm =
        phaseCorrNorm.isEmpty ? 0.0 : _q(phaseCorrNorm, 0.5);
    final medianSideRatioNorm =
        sideRatioNorm.isEmpty ? 0.0 : _q(sideRatioNorm, 0.5);
    final medianStereoImbalance =
        stereoImbalance.isEmpty ? 0.0 : _q(stereoImbalance, 0.5);
    final medianSilenceRatio =
        silenceRatio.isEmpty ? 0.0 : _q(silenceRatio, 0.5);
    final medianOnsetRateNorm =
        onsetRateNorm.isEmpty ? 0.0 : _q(onsetRateNorm, 0.5);
    final medianNoiseFloorNorm =
        noiseFloorNorm.isEmpty ? 0.0 : _q(noiseFloorNorm, 0.5);
    final medianSpectralBandwidthNorm =
        spectralBandwidthNorm.isEmpty ? 0.0 : _q(spectralBandwidthNorm, 0.5);

    int rowGainOps = 0;
    int rowPanOps = 0;
    int fxOps = 0;
    int masterOps = 0;

    for (final a in actions) {
      if (a.type == 'set_row_gain') rowGainOps++;
      if (a.type == 'set_row_pan') rowPanOps++;
      if (a.type.contains('master')) masterOps++;
      if (a.type.contains('effect')) fxOps++;
    }

    final scope = goal.target.scope;
    final scopeAuto = scope == 'auto' ? 1.0 : 0.0;
    final scopeRow = scope == 'row' ? 1.0 : 0.0;
    final scopeMaster = scope == 'master' ? 1.0 : 0.0;

    final kind = goal.intents.isNotEmpty
        ? goal.intents.first.kind.toLowerCase()
        : 'balance';

    double kindFlag(String k) => kind == k ? 1.0 : 0.0;

    final overlapMetrics = _overlapMetrics(project, rowsWithAudio);
    final stDynamicHeadroom =
        (medianStRmsP95 - medianStRmsMean).clamp(0.0, 1.0);

    final out = <double>[
      goal.intensity,
      strict ? 1.0 : 0.0,
      (project.bpm / 240.0).clamp(0.0, 1.0),
      (rowsWithAudio.length / math.max(1.0, project.maxRows.toDouble()))
          .clamp(0.0, 1.0),
      medianRms,
      rowGainOps / 12.0,
      rowPanOps / 12.0,
      fxOps / 20.0,
      masterOps / 12.0,
      scopeAuto,
      scopeRow,
      scopeMaster,
      kindFlag('balance'),
      kindFlag('gain'),
      kindFlag('pan'),
      kindFlag('eq'),
      kindFlag('compressor'),
      kindFlag('limiter'),
      kindFlag('reverb'),
      kindFlag('delay'),
      kindFlag('deesser'),
      kindFlag('distortion'),
      medianCrestNorm,
      rmsIqr.clamp(0.0, 1.0),
      medianCentroidNorm,
      medianZcr,
      medianSibilanceNorm,
      medianBassinessNorm,
      medianHfRms,
      medianStRmsMean,
      medianStRmsP95,
      medianStRmsStd,
      medianTransientDensity,
      overlapMetrics.overlapDensity,
      overlapMetrics.maskingPairRatio,
      overlapMetrics.centroidCollisionRatio,
      overlapMetrics.avgOverlapCentroidGapNorm,
      overlapMetrics.overlapRmsPressure,
      overlapMetrics.roleOverlapRatio,
      stDynamicHeadroom,
      medianTruePeakNorm,
      medianIntegratedLufsNorm,
      medianShortLufsMeanNorm,
      medianShortLufsP95Norm,
      medianLraNorm,
      medianClipRatio,
      medianSpectralFlatness,
      medianSpectralRolloffNorm,
      medianSpectralSlopeNorm,
      medianSpectralFlux,
      medianPhaseCorrNorm,
      medianSideRatioNorm,
      medianStereoImbalance,
      medianSilenceRatio,
      medianOnsetRateNorm,
      medianNoiseFloorNorm,
      medianSpectralBandwidthNorm,
      overlapMetrics.lowCollisionRatio,
      overlapMetrics.lowmidCollisionRatio,
      overlapMetrics.midCollisionRatio,
      overlapMetrics.highCollisionRatio,
    ];
    assert(
      out.length == kFeatureCount - _actionFeatureCount,
      'Feature contract mismatch: built context ${out.length}, expected ${kFeatureCount - _actionFeatureCount}',
    );
    return out;
  }

  List<double> _buildActionFeatures(ProjectState project, MixAction action) {
    final t = action.type;
    final aiMag = _actionMagnitude(project, action);
    final isMaster = t.contains('master') ? 1.0 : 0.0;

    double flag(String type) => t == type ? 1.0 : 0.0;
    final known = <String>{
      'set_row_gain',
      'set_row_pan',
      'set_master_gain',
      'set_master_pan',
      'adjust_effect_param_by_name',
      'adjust_master_effect_param_by_name',
      'ensure_effect',
      'ensure_master_effect',
      'delete_effect',
      'delete_master_effect',
      'hard_reset_row_fx',
      'hard_reset_master_fx',
    };

    return <double>[
      aiMag.clamp(0.0, 3.0),
      isMaster,
      flag('set_row_gain'),
      flag('set_row_pan'),
      flag('set_master_gain'),
      flag('set_master_pan'),
      flag('adjust_effect_param_by_name'),
      flag('adjust_master_effect_param_by_name'),
      flag('ensure_effect'),
      flag('ensure_master_effect'),
      flag('delete_effect'),
      flag('delete_master_effect'),
      flag('hard_reset_row_fx'),
      flag('hard_reset_master_fx'),
      known.contains(t) ? 0.0 : 1.0,
    ];
  }

  Future<double?> _predictApplyScore(
      OrtSession session, List<double> features) async {
    try {
      final inputName = session.inputNames.first;
      final input = await OrtValue.fromList(
        Float32List.fromList(features),
        [1, features.length],
      );

      final outputs = await session.run({inputName: input});
      double? score;

      // First pass: if a probability-like output exists, prefer it.
      for (final entry in outputs.entries) {
        final name = entry.key.toLowerCase();
        final raw = await entry.value.asList();
        if (name.contains('prob')) {
          score = _positiveClassScore(raw);
          if (score != null) break;
        }
      }

      // Second pass: infer from any output payload.
      score ??= await _extractApplyScoreFromAnyOutput(outputs);

      await input.dispose();
      for (final value in outputs.values) {
        await value.dispose();
      }

      if (score == null) return null;
      return score.clamp(0.0, 1.0);
    } catch (_) {
      return null;
    }
  }

  Future<double?> _predictScalar(
      OrtSession session, List<double> features) async {
    try {
      final inputName = session.inputNames.first;
      final input = await OrtValue.fromList(
        Float32List.fromList(features),
        [1, features.length],
      );

      final outputs = await session.run({inputName: input});
      double? scalar;

      for (final value in outputs.values) {
        final raw = await value.asList();
        scalar = _firstScalar(raw);
        if (scalar != null) break;
      }

      await input.dispose();
      for (final value in outputs.values) {
        await value.dispose();
      }

      return scalar;
    } catch (_) {
      return null;
    }
  }

  Future<double?> _extractApplyScoreFromAnyOutput(
      Map<String, OrtValue> outputs) async {
    // NOTE: this intentionally probes all outputs so ONNX export differences
    // (label+proba tensors, zipmap, plain scalar) still work without retrain.
    final raws = <dynamic>[];
    for (final value in outputs.values) {
      final raw = await value.asList();
      raws.add(raw);
    }

    // Prefer non-scalar probability-like outputs first (avoid label fallback).
    for (final raw in raws) {
      if (_isScalarLike(raw)) continue;
      final score = _positiveClassScore(raw);
      if (score != null) return score;
    }

    // Fallback: allow scalar-style outputs if nothing else is present.
    for (final raw in raws) {
      final score = _positiveClassScore(raw);
      if (score != null) return score;
    }

    return null;
  }

  double? _positiveClassScore(dynamic raw) {
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is num && key.toInt() == 1 && value is num) {
          return value.toDouble();
        }
        if (value is num) {
          final ks = key.toString().trim();
          if (ks == '1' || ks == '1.0') {
            return value.toDouble();
          }
        }
      }
      return null;
    }

    if (raw is List) {
      if (raw.isEmpty) return null;
      final first = raw.first;

      if (raw.length >= 2 && raw[0] is num && raw[1] is num) {
        return (raw[1] as num).toDouble();
      }

      if (first is List &&
          first.length >= 2 &&
          first[0] is num &&
          first[1] is num) {
        return (first[1] as num).toDouble();
      }

      if (first is Map) {
        return _positiveClassScore(first);
      }

      return _positiveClassScore(first);
    }

    if (raw is num) {
      return raw.toDouble();
    }
    return null;
  }

  bool _isScalarLike(dynamic raw) {
    if (raw is num) return true;
    if (raw is List && raw.length == 1) {
      final first = raw.first;
      if (first is num) return true;
      if (first is List && first.length == 1 && first.first is num) return true;
    }
    return false;
  }

  double? _firstScalar(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is Map) {
      final p1 = _positiveClassScore(raw);
      if (p1 != null) return p1;
      return null;
    }
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      return _firstScalar(first);
    }
    return null;
  }

  double _actionMagnitude(ProjectState project, MixAction action) {
    final data = action.data;
    final mode = (data['mode']?.toString() ?? 'delta').toLowerCase();
    if (mode == 'set') {
      switch (action.type) {
        case 'set_row_gain':
          final row = data['row'];
          final target = data['value'];
          if (row is int &&
              target is num &&
              row >= 0 &&
              row < project.rows.length) {
            return (target.toDouble() - project.rows[row].gain0to3).abs();
          }
          break;
        case 'set_row_pan':
          final row = data['row'];
          final target = data['value'];
          if (row is int &&
              target is num &&
              row >= 0 &&
              row < project.rows.length) {
            return (target.toDouble() - project.rows[row].pan0To1).abs();
          }
          break;
        case 'set_master_gain':
          final target = data['value'];
          if (target is num) {
            return (target.toDouble() - project.masterGain0to3).abs();
          }
          break;
        case 'set_master_pan':
          final target = data['value'];
          if (target is num) {
            return (target.toDouble() - project.masterPan0to1).abs();
          }
          break;
        case 'adjust_effect_param_by_name':
          final lookup = _lookupRowEffectParam(project, data);
          final target = data['value'];
          if (lookup != null && target is num) {
            return (target.toDouble() - lookup.current).abs();
          }
          break;
        case 'adjust_master_effect_param_by_name':
          final lookup = _lookupMasterEffectParam(project, data);
          final target = data['value'];
          if (lookup != null && target is num) {
            return (target.toDouble() - lookup.current).abs();
          }
          break;
      }
      return 1.0;
    }
    final d = data['delta'];
    if (d is num) return d.toDouble().abs();
    final dn = data['delta_norm'];
    if (dn is num) return dn.toDouble().abs();
    return 1.0;
  }

  double _audioStat(RowState row, String key, [double fallback = 0.0]) {
    final v = row.audioStats[key];
    if (v != null) return v;
    return fallback;
  }

  double _q(List<double> sorted, double q) {
    if (sorted.isEmpty) return 0.0;
    if (sorted.length == 1) return sorted.first;
    final qq = q.clamp(0.0, 1.0);
    final pos = qq * (sorted.length - 1);
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) return sorted[lo];
    final t = pos - lo;
    return sorted[lo] * (1.0 - t) + sorted[hi] * t;
  }

  String _topRole(RowState row) {
    if (row.roleProbs.isEmpty) return 'other';
    var bestKey = 'other';
    var bestVal = double.negativeInfinity;
    row.roleProbs.forEach((k, v) {
      if (v > bestVal) {
        bestKey = k;
        bestVal = v;
      }
    });
    return bestKey.isEmpty ? 'other' : bestKey.toLowerCase();
  }

  _OverlapMetrics _overlapMetrics(
      ProjectState project, List<RowState> rowsWithAudio) {
    if (rowsWithAudio.length < 2) {
      return const _OverlapMetrics();
    }

    final n = rowsWithAudio.length;
    final pairCount = n * (n - 1) / 2.0;
    double overlapStrengthSum = 0.0;
    double maskingStrengthSum = 0.0;
    double centroidCollisionStrengthSum = 0.0;
    double roleOverlapStrengthSum = 0.0;
    double sumGapNorm = 0.0;
    double sumRmsPressure = 0.0;
    double lowCollisionSum = 0.0;
    double lowmidCollisionSum = 0.0;
    double midCollisionSum = 0.0;
    double highCollisionSum = 0.0;

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        final a = rowsWithAudio[i];
        final b = rowsWithAudio[j];
        final ai = a.rowIndex;
        final bj = b.rowIndex;
        final overlapStrength = _overlapRatio(project, ai, bj);
        if (overlapStrength <= 1e-6) continue;
        overlapStrengthSum += overlapStrength;

        final cA = _audioStat(a, 'centroid_hz');
        final cB = _audioStat(b, 'centroid_hz');
        final gapNorm = ((cA - cB).abs() / 8000.0).clamp(0.0, 1.0);
        sumGapNorm += gapNorm * overlapStrength;
        if (gapNorm < 0.12) {
          centroidCollisionStrengthSum += overlapStrength;
        }

        final rA = math.max(1e-6, a.approxRms);
        final rB = math.max(1e-6, b.approxRms);
        final ratio = math.max(rA, rB) / math.min(rA, rB);
        final pressure = ((ratio - 1.0) / 3.0).clamp(0.0, 1.0);
        sumRmsPressure += pressure * overlapStrength;
        if (ratio > 1.4 && gapNorm < 0.20) {
          maskingStrengthSum += overlapStrength;
        }

        final roleA = _topRole(a);
        final roleB = _topRole(b);
        if (roleA != roleB && roleA != 'other' && roleB != 'other') {
          roleOverlapStrengthSum += overlapStrength;
        }

        lowCollisionSum += _bandCollisionScore(a, b, 'low') * overlapStrength;
        lowmidCollisionSum +=
            _bandCollisionScore(a, b, 'lowmid') * overlapStrength;
        midCollisionSum += _bandCollisionScore(a, b, 'mid') * overlapStrength;
        highCollisionSum += _bandCollisionScore(a, b, 'high') * overlapStrength;
      }
    }

    if (overlapStrengthSum <= 1e-6) {
      return _OverlapMetrics(overlapDensity: 0.0);
    }

    final overlapDensity = (overlapStrengthSum / pairCount).clamp(0.0, 1.0);
    return _OverlapMetrics(
      overlapDensity: overlapDensity,
      maskingPairRatio:
          (maskingStrengthSum / overlapStrengthSum).clamp(0.0, 1.0),
      centroidCollisionRatio:
          (centroidCollisionStrengthSum / overlapStrengthSum).clamp(0.0, 1.0),
      avgOverlapCentroidGapNorm:
          (sumGapNorm / overlapStrengthSum).clamp(0.0, 1.0),
      overlapRmsPressure: (sumRmsPressure / overlapStrengthSum).clamp(0.0, 1.0),
      roleOverlapRatio:
          (roleOverlapStrengthSum / overlapStrengthSum).clamp(0.0, 1.0),
      lowCollisionRatio: (lowCollisionSum / overlapStrengthSum).clamp(0.0, 1.0),
      lowmidCollisionRatio:
          (lowmidCollisionSum / overlapStrengthSum).clamp(0.0, 1.0),
      midCollisionRatio: (midCollisionSum / overlapStrengthSum).clamp(0.0, 1.0),
      highCollisionRatio:
          (highCollisionSum / overlapStrengthSum).clamp(0.0, 1.0),
    );
  }

  double _overlapRatio(ProjectState project, int a, int b) {
    double ratio = 0.0;
    if (a >= 0 &&
        a < project.overlapRatioMatrix.length &&
        b >= 0 &&
        b < project.overlapRatioMatrix[a].length) {
      ratio = math.max(ratio, project.overlapRatioMatrix[a][b]);
    }
    if (b >= 0 &&
        b < project.overlapRatioMatrix.length &&
        a >= 0 &&
        a < project.overlapRatioMatrix[b].length) {
      ratio = math.max(ratio, project.overlapRatioMatrix[b][a]);
    }
    if (ratio > 0.0) return ratio.clamp(0.0, 1.0);

    final bool ab = a >= 0 &&
        a < project.overlapMatrix.length &&
        b >= 0 &&
        b < project.overlapMatrix[a].length &&
        project.overlapMatrix[a][b] == 1;
    final bool ba = b >= 0 &&
        b < project.overlapMatrix.length &&
        a >= 0 &&
        a < project.overlapMatrix[b].length &&
        project.overlapMatrix[b][a] == 1;
    final bool overlapsBinary = ab || ba;
    return overlapsBinary ? 1.0 : 0.0;
  }

  double _normDbfs(double db) => ((db + 80.0) / 80.0).clamp(0.0, 1.0);
  double _normLufsDb(double lufs) => ((lufs + 80.0) / 80.0).clamp(0.0, 1.0);
  double _normSlope(double slope) => ((slope + 2.0) / 4.0).clamp(0.0, 1.0);
  double _normPhaseCorr(double corr) => ((corr + 1.0) / 2.0).clamp(0.0, 1.0);

  double _bandShare(RowState r, String key) {
    final low = _audioStat(r, 'low').clamp(0.0, double.infinity);
    final lowmid = _audioStat(r, 'lowmid').clamp(0.0, double.infinity);
    final mid = _audioStat(r, 'mid').clamp(0.0, double.infinity);
    final high = _audioStat(r, 'high').clamp(0.0, double.infinity);
    final total = (low + lowmid + mid + high).clamp(1e-9, double.infinity);
    final v = _audioStat(r, key).clamp(0.0, double.infinity);
    return (v / total).clamp(0.0, 1.0);
  }

  double _bandCollisionScore(RowState a, RowState b, String key) {
    final sa = _bandShare(a, key);
    final sb = _bandShare(b, key);
    final similarity = (1.0 - (sa - sb).abs()).clamp(0.0, 1.0);
    final bothPresent = (2.0 * math.min(sa, sb)).clamp(0.0, 1.0);
    return (similarity * bothPresent).clamp(0.0, 1.0);
  }

  MixAction _scaleAction(ProjectState project, MixAction action, double scale) {
    if ((scale - 1.0).abs() < 0.03) return action;

    final data = Map<String, dynamic>.from(action.data);
    final mode = (data['mode']?.toString() ?? 'delta').toLowerCase();

    void scaleKey(String key) {
      final v = data[key];
      if (v is num) {
        data[key] = v.toDouble() * scale;
      }
    }

    switch (action.type) {
      case 'set_row_gain':
        if (mode == 'set' && data['value'] is num) {
          final row = data['row'];
          if (row is int &&
              row >= 0 &&
              row < project.rows.length &&
              project.rows[row].hasAudio) {
            final current = project.rows[row].gain0to3;
            final target = (data['value'] as num).toDouble();
            data['value'] =
                (current + (target - current) * scale).clamp(0.0, 3.0);
          }
        } else {
          scaleKey('delta');
        }
        break;

      case 'set_row_pan':
        if (mode == 'set' && data['value'] is num) {
          final row = data['row'];
          if (row is int &&
              row >= 0 &&
              row < project.rows.length &&
              project.rows[row].hasAudio) {
            final current = project.rows[row].pan0To1;
            final target = (data['value'] as num).toDouble();
            data['value'] =
                (current + (target - current) * scale).clamp(0.0, 1.0);
          }
        } else {
          scaleKey('delta');
        }
        break;

      case 'set_master_gain':
        if (mode == 'set' && data['value'] is num) {
          final current = project.masterGain0to3;
          final target = (data['value'] as num).toDouble();
          data['value'] =
              (current + (target - current) * scale).clamp(0.0, 3.0);
        } else {
          scaleKey('delta');
        }
        break;

      case 'set_master_pan':
        if (mode == 'set' && data['value'] is num) {
          final current = project.masterPan0to1;
          final target = (data['value'] as num).toDouble();
          data['value'] =
              (current + (target - current) * scale).clamp(0.0, 1.0);
        } else {
          scaleKey('delta');
        }
        break;

      case 'adjust_effect_param_by_name':
        if (mode == 'set') {
          _scaleEffectSetAction(
            data: data,
            scale: scale,
            lookup: _lookupRowEffectParam(project, data),
          );
        } else {
          scaleKey('delta');
          scaleKey('delta_norm');
        }
        break;

      case 'adjust_master_effect_param_by_name':
        if (mode == 'set') {
          _scaleEffectSetAction(
            data: data,
            scale: scale,
            lookup: _lookupMasterEffectParam(project, data),
          );
        } else {
          scaleKey('delta');
          scaleKey('delta_norm');
        }
        break;
    }

    return MixAction(action.type, data);
  }

  void _scaleEffectSetAction({
    required Map<String, dynamic> data,
    required double scale,
    required _ParamLookup? lookup,
  }) {
    if (lookup == null) return;

    if (data['value'] is num) {
      final current = lookup.current;
      final target = (data['value'] as num).toDouble();
      var next = current + (target - current) * scale;
      if (lookup.min != null && lookup.max != null) {
        next = next.clamp(lookup.min!, lookup.max!);
      } else if (data['clamp_0_1'] == true) {
        next = next.clamp(0.0, 1.0);
      }
      data['value'] = next;
      data.remove('value_norm');
      return;
    }

    if (data['value_norm'] is num && lookup.min != null && lookup.max != null) {
      final vn = (data['value_norm'] as num).toDouble().clamp(0.0, 1.0);
      final target = lookup.min! + (lookup.max! - lookup.min!) * vn;
      final next = (lookup.current + (target - lookup.current) * scale)
          .clamp(lookup.min!, lookup.max!);
      data['value'] = next;
      data.remove('value_norm');
    }
  }

  _ParamLookup? _lookupRowEffectParam(
      ProjectState project, Map<String, dynamic> data) {
    final row = data['row'];
    if (row is! int || row < 0 || row >= project.rows.length) return null;
    final rowState = project.rows[row];
    final effectContains =
        data['effect_name_contains']?.toString().toLowerCase();
    if (effectContains == null || effectContains.isEmpty) return null;
    for (final effect in rowState.effects) {
      if (effect.name.toLowerCase().contains(effectContains)) {
        return _lookupParamInEffect(effect, data);
      }
    }
    return null;
  }

  _ParamLookup? _lookupMasterEffectParam(
      ProjectState project, Map<String, dynamic> data) {
    final effectContains =
        data['effect_name_contains']?.toString().toLowerCase();
    if (effectContains == null || effectContains.isEmpty) return null;
    for (final effect in project.masterEffects) {
      if (effect.name.toLowerCase().contains(effectContains)) {
        return _lookupParamInEffect(effect, data);
      }
    }
    return null;
  }

  _ParamLookup? _lookupParamInEffect(
      EffectState effect, Map<String, dynamic> data) {
    final exact = data['param_name']?.toString().toLowerCase();
    final containsAny = (data['param_name_contains_any'] as List?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        const <String>[];

    for (final p in effect.parameters) {
      final name = p.name.toLowerCase();
      final exactMatch = exact != null && exact.isNotEmpty && name == exact;
      final fuzzyMatch = containsAny.isNotEmpty &&
          containsAny.any((token) => name.contains(token));
      if (!exactMatch && !fuzzyMatch) continue;

      final value = p.value;
      if (value is! num) return null;
      final min = p.min;
      final max = p.max;
      return _ParamLookup(current: value.toDouble(), min: min, max: max);
    }
    return null;
  }
}

class _ParamLookup {
  final double current;
  final double? min;
  final double? max;

  const _ParamLookup({
    required this.current,
    required this.min,
    required this.max,
  });
}

class _OverlapMetrics {
  final double overlapDensity;
  final double maskingPairRatio;
  final double centroidCollisionRatio;
  final double avgOverlapCentroidGapNorm;
  final double overlapRmsPressure;
  final double roleOverlapRatio;
  final double lowCollisionRatio;
  final double lowmidCollisionRatio;
  final double midCollisionRatio;
  final double highCollisionRatio;

  const _OverlapMetrics({
    this.overlapDensity = 0.0,
    this.maskingPairRatio = 0.0,
    this.centroidCollisionRatio = 0.0,
    this.avgOverlapCentroidGapNorm = 0.0,
    this.overlapRmsPressure = 0.0,
    this.roleOverlapRatio = 0.0,
    this.lowCollisionRatio = 0.0,
    this.lowmidCollisionRatio = 0.0,
    this.midCollisionRatio = 0.0,
    this.highCollisionRatio = 0.0,
  });
}
