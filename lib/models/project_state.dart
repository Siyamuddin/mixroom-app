import 'dart:convert';

import 'package:mixroom/models/models.dart'; // for AutomationPoint

class ProjectState {
  final double bpm;
  final double masterGain0to3;
  final double masterPan0to1;
  final int maxRows;
  final List<RowState> rows;
  final List<EffectState> masterEffects;
  final List<List<int>> overlapMatrix; // row-row overlap (0/1)
  final List<List<double>> overlapRatioMatrix; // row-row overlap amount (0..1)

  ProjectState({
    required this.bpm,
    required this.masterGain0to3,
    this.masterPan0to1 = 0.5,
    required this.maxRows,
    required this.rows,
    this.masterEffects = const [],
    required this.overlapMatrix,
    this.overlapRatioMatrix = const [],
  });

  Map<String, dynamic> toJson() => {
        'bpm': bpm,
        'master_gain_0to3': masterGain0to3,
        'master_pan_0to1': masterPan0to1,
        'max_rows': maxRows,
        'rows': rows.map((r) => r.toJson()).toList(),
        'master_effects': masterEffects.map((e) => e.toJson()).toList(),
        'overlap_matrix': overlapMatrix,
        'overlap_ratio_matrix': overlapRatioMatrix,
      };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class RowState {
  final int rowIndex;
  final List<ClipState> clips;

  /// Lightweight audio features (from waveform)
  final double approxRms; // 0..1
  final double approxCrest; // peak/rms-ish

  /// Classifier output (aggregated across clips)
  final Map<String, double> roleProbs; // vocals/drums/bass/guitar/synth/other

  /// NEW: detect "this row contains multiple different roles across time"
  /// 1.0 = very consistent, 0.0 = totally mixed
  final double roleConsistency;

  /// NEW: for debugging + UI warnings
  final List<String> clipTopRoles;

  /// NEW: extra static analysis for rule-based heuristics
  /// Keys (recommended):
  /// - centroid_hz (0..8000)
  /// - zcr (0..1)
  /// - hf_rms (0..1)
  /// - st_rms_mean (0..1)
  /// - st_rms_p95 (0..1)
  /// - st_rms_std (0..1)
  /// - transient_density (0..1)
  /// - true_peak_dbfs (-inf..0)
  /// - integrated_lufs_est (-inf..0)
  /// - short_lufs_mean (-inf..0)
  /// - short_lufs_p95 (-inf..0)
  /// - lra_est (>=0)
  /// - clip_ratio (0..1)
  /// - spectral_flatness (0..1)
  /// - spectral_rolloff_hz (0..8000)
  /// - spectral_slope (roughly -2..2)
  /// - spectral_flux (0..1)
  /// - spectral_bandwidth_hz (0..8000)
  /// - silence_ratio (0..1)
  /// - activity_ratio (0..1)
  /// - onset_rate_hz (0..~20)
  /// - noise_floor_dbfs (-inf..0)
  /// - phase_corr (-1..1)
  /// - side_ratio (0..~2)
  /// - stereo_imbalance (0..1)
  /// - low (arb)
  /// - lowmid (arb)
  /// - mid (arb)
  /// - high (arb)
  /// - sibilance (0..~1+)
  /// - bassiness (0..~1+)
  final Map<String, double> audioStats;

  /// Current mix state
  final double gain0to3;
  final double pan0To1;

  final List<EffectState> effects;
  final List<AutomationPoint> volumeAutomation;

  final bool hasAudio;

  RowState({
    required this.rowIndex,
    required this.clips,
    required this.approxRms,
    required this.approxCrest,
    required this.roleProbs,
    required this.roleConsistency,
    required this.clipTopRoles,
    required this.audioStats,
    required this.gain0to3,
    required this.pan0To1,
    required this.effects,
    required this.volumeAutomation,
    required this.hasAudio,
  });

  Map<String, dynamic> toJson() => {
        'row': rowIndex,
        'clips': clips.map((c) => c.toJson()).toList(),
        'features': {'approx_rms': approxRms, 'approx_crest': approxCrest},
        'role_probs': roleProbs,
        'role_consistency': roleConsistency,
        'clip_top_roles': clipTopRoles,
        'audio_stats': audioStats,
        'mix': {'gain_0to3': gain0to3, 'pan_0to1': pan0To1},
        'effects': effects.map((e) => e.toJson()).toList(),
        'volumeAutomation': volumeAutomation.map((v) => v.toJson()).toList(),
        'hasAudio': hasAudio,
      };
}

class ClipState {
  final double startMs;
  final double endMs;
  final String? fileName;
  final double gain0to3;
  final double pitchSemitones;

  ClipState(
      {required this.startMs,
      required this.endMs,
      required this.fileName,
      this.gain0to3 = 1.0,
      this.pitchSemitones = 0.0});

  Map<String, dynamic> toJson() => {
        'start_ms': startMs,
        'end_ms': endMs,
        'file_name': fileName,
        'gain_0to3': gain0to3,
        'pitch_semitones': pitchSemitones,
      };
}

class EffectParameterState {
  final String id;
  final String name;
  final String type; // "float" | "bool" | "choice"
  final dynamic value;
  final double? min;
  final double? max;

  const EffectParameterState({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    this.min,
    this.max,
  });

  factory EffectParameterState.fromMap(Map<String, dynamic> m) {
    final type = m['type'] as String;

    dynamic parsedValue;
    switch (type) {
      case 'float':
        parsedValue = (m['value'] as num).toDouble();
        break;
      case 'bool':
        parsedValue = m['value'] as bool;
        break;
      case 'choice':
        parsedValue = m['value'] as String;
        break;
      default:
        parsedValue = m['value'];
    }

    return EffectParameterState(
      id: (m['id'] as String?) ?? '',
      name: m['name'] as String,
      type: type,
      value: parsedValue,
      min: m['min'] is num ? (m['min'] as num).toDouble() : null,
      max: m['max'] is num ? (m['max'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'value': value,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
      };
}

class EffectState {
  final int effectIndex; // Position in chain
  final String name; // Plugin name
  final bool isBypassed;
  final List<EffectParameterState> parameters;

  const EffectState({
    required this.effectIndex,
    required this.name,
    required this.isBypassed,
    required this.parameters,
  });

  factory EffectState.fromMap(Map<String, dynamic> m) {
    return EffectState(
      effectIndex: m['effectIndex'] as int,
      name: m['name'] as String,
      isBypassed: m['isBypassed'] as bool? ?? false,
      parameters: (m['parameters'] as List<dynamic>? ?? [])
          .map(
              (p) => EffectParameterState.fromMap(Map<String, dynamic>.from(p)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'effectIndex': effectIndex,
        'name': name,
        'isBypassed': isBypassed,
        'parameters': parameters.map((p) => p.toJson()).toList(),
      };
}
