import 'dart:convert';

import 'package:mixroom/models/models.dart'; // for AutomationPoint

const List<String> kProjectKeyRoots = <String>[
  'C',
  'C#',
  'D',
  'Eb',
  'E',
  'F',
  'F#',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

const List<String> kProjectKeyModes = <String>['major', 'minor'];

String normalizeProjectKey(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '';
  final lower = value
      .toLowerCase()
      .replaceAll('♯', '#')
      .replaceAll('♭', 'b')
      .replaceAll('_', ' ')
      .replaceAll('-', ' ');
  if (lower == 'none' || lower == 'unknown' || lower == 'no key') return '';

  final match = RegExp(
    r'\b([a-g])\s*(#|b)?\s*(major|maj|min(?:or)?|m)?\b',
  ).firstMatch(lower);
  if (match == null) return '';

  final rootToken = '${match.group(1)}${match.group(2) ?? ''}';
  final root = _canonicalProjectKeyRoot(rootToken);
  if (root == null) return '';
  final modeToken = (match.group(3) ?? '').trim();
  final mode =
      modeToken.startsWith('min') || modeToken == 'm' ? 'minor' : 'major';
  return '$root $mode';
}

String projectKeyDisplayLabel(String? raw) {
  final normalized = normalizeProjectKey(raw);
  if (normalized.isEmpty) return 'No key';
  final parts = normalized.split(' ');
  if (parts.length < 2) return normalized;
  final mode = parts[1] == 'minor' ? 'Minor' : 'Major';
  return '${parts[0]} $mode';
}

String projectKeyShortLabel(String? raw) {
  final normalized = normalizeProjectKey(raw);
  if (normalized.isEmpty) return 'Key --';
  final parts = normalized.split(' ');
  if (parts.length < 2) return normalized;
  return '${parts[0]} ${parts[1] == 'minor' ? 'Min' : 'Maj'}';
}

String? _canonicalProjectKeyRoot(String root) {
  switch (root.trim().toLowerCase()) {
    case 'c':
    case 'b#':
      return 'C';
    case 'c#':
    case 'db':
      return 'C#';
    case 'd':
      return 'D';
    case 'd#':
    case 'eb':
      return 'Eb';
    case 'e':
    case 'fb':
      return 'E';
    case 'f':
    case 'e#':
      return 'F';
    case 'f#':
    case 'gb':
      return 'F#';
    case 'g':
      return 'G';
    case 'g#':
    case 'ab':
      return 'Ab';
    case 'a':
      return 'A';
    case 'a#':
    case 'bb':
      return 'Bb';
    case 'b':
    case 'cb':
      return 'B';
  }
  return null;
}

class ProjectState {
  final double bpm;
  final String projectKey;
  final String estimatedKey;
  final double estimatedKeyConfidence;
  final double masterGain0to3;
  final double masterPan0to1;
  final int maxRows;
  final List<RowState> rows;
  final List<EffectState> masterEffects;
  final List<List<int>> overlapMatrix; // row-row overlap (0/1)
  final List<List<double>> overlapRatioMatrix; // row-row overlap amount (0..1)

  ProjectState({
    required this.bpm,
    this.projectKey = '',
    this.estimatedKey = '',
    this.estimatedKeyConfidence = 0.0,
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
        'project_key': projectKey,
        'estimated_key': estimatedKey,
        'estimated_key_confidence': estimatedKeyConfidence,
        'master_gain_0to3': masterGain0to3,
        'master_pan_0to1': masterPan0to1,
        'max_rows': maxRows,
        'rows': rows.map((r) => r.toJson()).toList(),
        'master_effects': masterEffects.map((e) => e.toJson()).toList(),
        'overlap_matrix': overlapMatrix,
        'overlap_ratio_matrix': overlapRatioMatrix,
      };

  Map<String, dynamic> toMagnitudeResolverJson() => {
        'bpm': bpm,
        'project_key': projectKey,
        'estimated_key': estimatedKey,
        'estimated_key_confidence': estimatedKeyConfidence,
        'master_gain_0to3': masterGain0to3,
        'master_pan_0to1': masterPan0to1,
        'max_rows': maxRows,
        'rows': rows.map((r) => r.toMagnitudeResolverJson()).toList(),
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

  /// Additive interpretation layer derived from role probs + audio stats.
  final RowInterpretationState interpretation;

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
    required this.interpretation,
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
        'interpretation': interpretation.toJson(),
        'mix': {'gain_0to3': gain0to3, 'pan_0to1': pan0To1},
        'effects': effects.map((e) => e.toJson()).toList(),
        'volumeAutomation': volumeAutomation.map((v) => v.toJson()).toList(),
        'hasAudio': hasAudio,
      };

  Map<String, dynamic> toMagnitudeResolverJson() => {
        'row': rowIndex,
        'features': {'approx_rms': approxRms, 'approx_crest': approxCrest},
        'role_probs': roleProbs,
        'audio_stats': audioStats,
        'mix': {'gain_0to3': gain0to3, 'pan_0to1': pan0To1},
        'effects': effects.map((e) => e.toJson()).toList(),
        'hasAudio': hasAudio,
      };
}

class RowInterpretationState {
  static const RowInterpretationState empty = RowInterpretationState(
    topRole: 'other',
    sourceType: 'single_source',
    transientProfile: 'mixed',
    spectralProfile: 'mid_focused',
    stereoProfile: 'moderate',
    editRisk: 'low',
    roleEntropy: 0.0,
    topRoleMargin: 0.0,
    classificationConfidence: 0.0,
    clipsRoleDisagreement: 0.0,
    overlapDensity: 0.0,
    singleSourceLikely: false,
    multiRoleLikely: false,
    compositeStemLikely: false,
    fullMixLikely: false,
    loopLikely: false,
    oneShotLikely: false,
    fxOrTextureLikely: false,
    busLikeLikely: false,
    lowEndAnchorLikely: false,
    highFreqPresenceLikely: false,
    percussiveLikely: false,
    tonalHarmonicLikely: false,
    noiseLikeLikely: false,
    wideStereoLikely: false,
    monoCenterLikely: false,
    broadbandProcessingRisk: false,
    stemSpecificProcessingRisk: false,
    overprocessingRisk: false,
    alreadyLoudLikely: false,
    alreadyCompressedLikely: false,
    notes: <String>[],
  );

  const RowInterpretationState({
    required this.topRole,
    required this.sourceType,
    required this.transientProfile,
    required this.spectralProfile,
    required this.stereoProfile,
    required this.editRisk,
    required this.roleEntropy,
    required this.topRoleMargin,
    required this.classificationConfidence,
    required this.clipsRoleDisagreement,
    required this.overlapDensity,
    required this.singleSourceLikely,
    required this.multiRoleLikely,
    required this.compositeStemLikely,
    required this.fullMixLikely,
    required this.loopLikely,
    required this.oneShotLikely,
    required this.fxOrTextureLikely,
    required this.busLikeLikely,
    required this.lowEndAnchorLikely,
    required this.highFreqPresenceLikely,
    required this.percussiveLikely,
    required this.tonalHarmonicLikely,
    required this.noiseLikeLikely,
    required this.wideStereoLikely,
    required this.monoCenterLikely,
    required this.broadbandProcessingRisk,
    required this.stemSpecificProcessingRisk,
    required this.overprocessingRisk,
    required this.alreadyLoudLikely,
    required this.alreadyCompressedLikely,
    required this.notes,
  });

  final String topRole;
  final String sourceType;
  final String transientProfile;
  final String spectralProfile;
  final String stereoProfile;
  final String editRisk;
  final double roleEntropy;
  final double topRoleMargin;
  final double classificationConfidence;
  final double clipsRoleDisagreement;
  final double overlapDensity;
  final bool singleSourceLikely;
  final bool multiRoleLikely;
  final bool compositeStemLikely;
  final bool fullMixLikely;
  final bool loopLikely;
  final bool oneShotLikely;
  final bool fxOrTextureLikely;
  final bool busLikeLikely;
  final bool lowEndAnchorLikely;
  final bool highFreqPresenceLikely;
  final bool percussiveLikely;
  final bool tonalHarmonicLikely;
  final bool noiseLikeLikely;
  final bool wideStereoLikely;
  final bool monoCenterLikely;
  final bool broadbandProcessingRisk;
  final bool stemSpecificProcessingRisk;
  final bool overprocessingRisk;
  final bool alreadyLoudLikely;
  final bool alreadyCompressedLikely;
  final List<String> notes;

  List<String> get flags {
    final out = <String>[];
    if (singleSourceLikely) out.add('single_source');
    if (multiRoleLikely) out.add('multi_role');
    if (compositeStemLikely) out.add('composite_stem');
    if (fullMixLikely) out.add('full_mix');
    if (loopLikely) out.add('loop');
    if (oneShotLikely) out.add('one_shot');
    if (fxOrTextureLikely) out.add('fx_texture');
    if (busLikeLikely) out.add('bus_like');
    if (lowEndAnchorLikely) out.add('low_end_anchor');
    if (highFreqPresenceLikely) out.add('high_freq_presence');
    if (percussiveLikely) out.add('percussive');
    if (tonalHarmonicLikely) out.add('tonal_harmonic');
    if (noiseLikeLikely) out.add('noise_like');
    if (wideStereoLikely) out.add('wide_stereo');
    if (monoCenterLikely) out.add('mono_center');
    if (alreadyLoudLikely) out.add('already_loud');
    if (alreadyCompressedLikely) out.add('already_compressed');
    if (broadbandProcessingRisk) out.add('broadband_processing_risk');
    if (stemSpecificProcessingRisk) out.add('stem_specific_processing_risk');
    if (overprocessingRisk) out.add('overprocessing_risk');
    return out;
  }

  Map<String, dynamic> toJson() => {
        'top_role': topRole,
        'source_type': sourceType,
        'transient_profile': transientProfile,
        'spectral_profile': spectralProfile,
        'stereo_profile': stereoProfile,
        'edit_risk': editRisk,
        'role_entropy': roleEntropy,
        'top_role_margin': topRoleMargin,
        'classification_confidence': classificationConfidence,
        'clips_role_disagreement': clipsRoleDisagreement,
        'overlap_density': overlapDensity,
        'flags': flags,
        'notes': notes,
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
