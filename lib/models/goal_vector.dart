// goal_vector.dart

enum MixExecutionProfile {
  producerSafe('producer_safe'),
  creativeBold('creative_bold'),
  experimentalExtreme('experimental_extreme');

  const MixExecutionProfile(this.wireValue);

  final String wireValue;

  static MixExecutionProfile fromJsonValue(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'creative_bold':
        return MixExecutionProfile.creativeBold;
      case 'experimental_extreme':
        return MixExecutionProfile.experimentalExtreme;
      case 'producer_safe':
      default:
        return MixExecutionProfile.producerSafe;
    }
  }
}

enum MixAudibility {
  subtle('subtle'),
  noticeable('noticeable'),
  obvious('obvious'),
  extreme('extreme');

  const MixAudibility(this.wireValue);

  final String wireValue;

  static MixAudibility fromJsonValue(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'subtle':
        return MixAudibility.subtle;
      case 'obvious':
        return MixAudibility.obvious;
      case 'extreme':
        return MixAudibility.extreme;
      case 'noticeable':
      default:
        return MixAudibility.noticeable;
    }
  }
}

enum MixReferenceMode {
  tone('tone'),
  loudness('loudness'),
  width('width'),
  glue('glue'),
  fullMix('full_mix');

  const MixReferenceMode(this.wireValue);

  final String wireValue;

  static MixReferenceMode fromJsonValue(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'tone':
        return MixReferenceMode.tone;
      case 'loudness':
        return MixReferenceMode.loudness;
      case 'width':
        return MixReferenceMode.width;
      case 'glue':
        return MixReferenceMode.glue;
      case 'full_mix':
      default:
        return MixReferenceMode.fullMix;
    }
  }
}

enum MixReferenceCloseness {
  loose('loose'),
  balanced('balanced'),
  close('close');

  const MixReferenceCloseness(this.wireValue);

  final String wireValue;

  static MixReferenceCloseness fromJsonValue(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'loose':
        return MixReferenceCloseness.loose;
      case 'close':
        return MixReferenceCloseness.close;
      case 'balanced':
      default:
        return MixReferenceCloseness.balanced;
    }
  }
}

class MixReferenceTarget {
  const MixReferenceTarget({
    this.rowIndex,
    this.preferSelected = false,
    this.confidence = 0.5,
  });

  final int? rowIndex;
  final bool preferSelected;
  final double confidence;

  bool get isValid => rowIndex != null || preferSelected;

  Map<String, dynamic> toJson() => {
        if (rowIndex != null) 'row_index': rowIndex,
        if (preferSelected) 'prefer_selected': true,
        'confidence': confidence,
      };

  static MixReferenceTarget? fromJsonValue(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final rawRowIndex = map['row_index'];
    final rowIndex = rawRowIndex is int
        ? rawRowIndex
        : (rawRowIndex is num ? rawRowIndex.toInt() : null);
    final preferSelected = map['prefer_selected'] == true;
    if ((rowIndex == null || rowIndex < 0) && !preferSelected) {
      return null;
    }
    return MixReferenceTarget(
      rowIndex: rowIndex != null && rowIndex >= 0 ? rowIndex : null,
      preferSelected: preferSelected,
      confidence:
          ((map['confidence'] ?? 0.5) as num).toDouble().clamp(0.0, 1.0),
    );
  }
}

class GoalVector {
  final String type; // "mix_request"
  final List<MixIntent> intents;
  final MixTarget target;
  final double intensity; // 0..1
  final MixExecutionProfile executionProfile;
  final MixAudibility audibility;
  final List<String> styleTags;
  final bool destructiveOk;
  final MixReferenceTarget? referenceTarget;
  final MixReferenceMode? referenceMode;
  final MixReferenceCloseness? referenceCloseness;

  final bool resetFx; // for starting from a clean slate

  GoalVector({
    required this.type,
    required this.intents,
    required this.target,
    required this.intensity,
    this.executionProfile = MixExecutionProfile.producerSafe,
    this.audibility = MixAudibility.noticeable,
    this.styleTags = const [],
    this.destructiveOk = false,
    this.referenceTarget,
    this.referenceMode,
    this.referenceCloseness,
    this.resetFx = false,
  });

  factory GoalVector.fromJson(Map<String, dynamic> j) {
    final intentsJson =
        (j['intents'] is List) ? (j['intents'] as List) : const [];
    final targetJson = j['target'] is Map
        ? Map<String, dynamic>.from(j['target'] as Map)
        : <String, dynamic>{};
    final referenceTarget = MixReferenceTarget.fromJsonValue(
      j['reference_target'],
    );

    return GoalVector(
      type: (j['type'] ?? 'mix_request').toString(),
      intents: intentsJson
          .whereType<Map>()
          .map((m) => MixIntent.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      target: MixTarget.fromJson(targetJson),
      intensity: ((j['intensity'] ?? 0.5) as num).toDouble().clamp(0.0, 1.0),
      executionProfile:
          MixExecutionProfile.fromJsonValue(j['execution_profile']),
      audibility: MixAudibility.fromJsonValue(j['audibility']),
      styleTags: _normalizeMixStyleTags(j['style_tags']),
      destructiveOk: j['destructive_ok'] == true,
      referenceTarget: referenceTarget,
      referenceMode: referenceTarget == null
          ? null
          : MixReferenceMode.fromJsonValue(j['reference_mode']),
      referenceCloseness: referenceTarget == null
          ? null
          : MixReferenceCloseness.fromJsonValue(j['reference_closeness']),
      resetFx: j['reset_fx'] == true,
    );
  }

  bool get effectiveDestructive =>
      destructiveOk ||
      executionProfile == MixExecutionProfile.experimentalExtreme;

  Map<String, dynamic> toJson() => {
        'type': type,
        'intents': intents.map((intent) => intent.toJson()).toList(),
        'target': target.toJson(),
        'intensity': intensity,
        'execution_profile': executionProfile.wireValue,
        'audibility': audibility.wireValue,
        if (styleTags.isNotEmpty) 'style_tags': styleTags,
        if (destructiveOk) 'destructive_ok': true,
        if (referenceTarget != null) 'reference_target': referenceTarget!.toJson(),
        if (referenceMode != null) 'reference_mode': referenceMode!.wireValue,
        if (referenceCloseness != null)
          'reference_closeness': referenceCloseness!.wireValue,
        if (resetFx) 'reset_fx': true,
      };
}

List<String> _normalizeMixStyleTags(Object? raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  final seen = <String>{};
  for (final item in raw) {
    final normalized = item?.toString().trim().toLowerCase() ?? '';
    if (normalized.isEmpty || normalized == 'null') continue;
    final canonical = normalized.replaceAll(RegExp(r'\s+'), '_');
    if (canonical.isEmpty || canonical.length > 40) continue;
    if (seen.add(canonical)) {
      out.add(canonical);
    }
    if (out.length >= 8) break;
  }
  return out;
}

class MixIntent {
  final String kind; // gain/pan/reverb/eq/delay/distortion/deesser/balance/tone
  final String? direction;
  final String? descriptor;
  final double confidence;

  MixIntent({
    required this.kind,
    this.direction,
    this.descriptor,
    required this.confidence,
  });

  // factory MixIntent.fromJson(Map<String, dynamic> j) => MixIntent(
  //       kind: (j['kind'] ?? 'balance').toString(),
  //       direction: j['direction']?.toString(),
  //       descriptor: j['descriptor']?.toString(),
  //       confidence: ((j['confidence'] ?? 0.5) as num).toDouble().clamp(0.0, 1.0),
  //     );

  factory MixIntent.fromJson(Map<String, dynamic> j) {
    String? norm(String? s) {
      if (s == null) return null;
      final t = s.trim().toLowerCase();
      if (t.isEmpty || t == 'null') return null;
      return t;
    }

    return MixIntent(
      kind: (j['kind'] ?? 'balance').toString().trim().toLowerCase(),
      direction: norm(j['direction']?.toString()),
      descriptor: norm(j['descriptor']?.toString()),
      confidence: ((j['confidence'] ?? 0.5) as num).toDouble().clamp(0.0, 1.0),
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (direction != null) 'direction': direction,
        if (descriptor != null) 'descriptor': descriptor,
        'confidence': confidence,
      };
}

class MixTarget {
  final String? role;
  final int? rowIndex; // 0-based
  final String scope; // auto | row | master
  final double confidence;

  MixTarget({
    this.role,
    this.rowIndex,
    this.scope = 'auto',
    required this.confidence,
  });

  factory MixTarget.fromJson(Map<String, dynamic> j) {
    final rawScope = j['scope']?.toString().trim().toLowerCase();
    final scope =
        (rawScope == 'row' || rawScope == 'master' || rawScope == 'auto')
            ? rawScope!
            : 'auto';
    final rawRowIndex = j['row_index'] is int
        ? j['row_index'] as int
        : (j['row_index'] is num ? (j['row_index'] as num).toInt() : null);
    final rowIndex =
        (scope == 'master' || (rawRowIndex != null && rawRowIndex < 0))
            ? null
            : rawRowIndex;

    return MixTarget(
      role: j['role']?.toString(),
      rowIndex: rowIndex,
      scope: scope,
      confidence: ((j['confidence'] ?? 0.5) as num).toDouble().clamp(0.0, 1.0),
    );
  }

  Map<String, dynamic> toJson() => {
        if (role != null) 'role': role,
        if (rowIndex != null) 'row_index': rowIndex,
        'scope': scope,
        'confidence': confidence,
      };
}
