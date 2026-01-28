// goal_vector.dart

class GoalVector {
  final String type; // "mix_request"
  final String userText;
  final List<MixIntent> intents;
  final MixTarget target;
  final double intensity; // 0..1

  final bool resetFx; // for starting from a clean slate

  GoalVector({
    required this.type,
    required this.userText,
    required this.intents,
    required this.target,
    required this.intensity,
    this.resetFx = false,
  });

  factory GoalVector.fromJson(Map<String, dynamic> j, {required String userText}) {
    final intentsJson = (j['intents'] is List) ? (j['intents'] as List) : const [];
    final targetJson = j['target'] is Map ? Map<String, dynamic>.from(j['target'] as Map) : <String, dynamic>{};

    return GoalVector(
      type: (j['type'] ?? 'mix_request').toString(),
      userText: userText,
      intents: intentsJson.whereType<Map>().map((m) => MixIntent.fromJson(Map<String, dynamic>.from(m))).toList(),
      target: MixTarget.fromJson(targetJson),
      intensity: ((j['intensity'] ?? 0.5) as num).toDouble().clamp(0.0, 1.0),
      resetFx: j['reset_fx'] == true,
    );
  }
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
}

class MixTarget {
  final String? role;
  final int? rowIndex; // 0-based
  final double confidence;

  MixTarget({
    this.role,
    this.rowIndex,
    required this.confidence,
  });

  factory MixTarget.fromJson(Map<String, dynamic> j) => MixTarget(
        role: j['role']?.toString(),
        rowIndex: j['row_index'] is int
            ? j['row_index'] as int
            : (j['row_index'] is num ? (j['row_index'] as num).toInt() : null),
        confidence: ((j['confidence'] ?? 0.5) as num).toDouble().clamp(0.0, 1.0),
      );
}
