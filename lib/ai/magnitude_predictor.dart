import 'dart:convert';

import '../models/goal_vector.dart';
import '../models/mixing_result.dart';
import '../models/project_state.dart';

class MagnitudeActionDebugEntry {
  final int actionIndex;
  final String actionType;
  final Map<String, dynamic> before;
  final Map<String, dynamic>? after;
  final double? applyScore;
  final double? rawMagnitude;
  final double? finalScale;
  final String decision;
  final bool dropped;

  const MagnitudeActionDebugEntry({
    required this.actionIndex,
    required this.actionType,
    required this.before,
    required this.after,
    required this.decision,
    required this.dropped,
    this.applyScore,
    this.rawMagnitude,
    this.finalScale,
  });

  Map<String, dynamic> toJson() {
    return {
      'action_index': actionIndex,
      'action_type': actionType,
      'before': before,
      if (after != null) 'after': after,
      if (applyScore != null) 'apply_score': applyScore,
      if (rawMagnitude != null) 'raw_magnitude': rawMagnitude,
      if (finalScale != null) 'final_scale': finalScale,
      'decision': decision,
      'dropped': dropped,
    };
  }

  factory MagnitudeActionDebugEntry.fromJson(Map<String, dynamic> json) {
    final before = json['before'];
    final after = json['after'];
    return MagnitudeActionDebugEntry(
      actionIndex: (json['action_index'] as num?)?.toInt() ?? 0,
      actionType: json['action_type']?.toString() ?? '',
      before: before is Map<String, dynamic>
          ? before
          : (before is Map ? Map<String, dynamic>.from(before) : const {}),
      after: after is Map<String, dynamic>
          ? after
          : (after is Map ? Map<String, dynamic>.from(after) : null),
      applyScore: (json['apply_score'] as num?)?.toDouble(),
      rawMagnitude: (json['raw_magnitude'] as num?)?.toDouble(),
      finalScale: (json['final_scale'] as num?)?.toDouble(),
      decision: json['decision']?.toString() ?? '',
      dropped: json['dropped'] == true,
    );
  }
}

class MagnitudeRefineResult {
  final List<MixAction> actions;
  final bool fallbackUsed;
  final String? fallbackReason;
  final List<MagnitudeActionDebugEntry> debugEntries;
  final Map<String, dynamic> observability;

  const MagnitudeRefineResult({
    required this.actions,
    required this.fallbackUsed,
    this.fallbackReason,
    this.debugEntries = const [],
    this.observability = const {},
  });
}

abstract class MixingMagnitudePredictor {
  bool get isEnabled;
  bool get isReady;
  Map<String, dynamic> get observabilityContext;

  Future<void> startBackgroundRefresh();
  Future<void> load();
  Future<void> dispose();

  Future<MagnitudeRefineResult> refine({
    required ProjectState project,
    required GoalVector goal,
    required List<MixAction> actions,
    required bool strict,
    String? projectId,
  });
}

class NoopMixingMagnitudePredictor implements MixingMagnitudePredictor {
  const NoopMixingMagnitudePredictor();

  @override
  bool get isEnabled => false;

  @override
  bool get isReady => true;

  @override
  Map<String, dynamic> get observabilityContext => const <String, dynamic>{};

  @override
  Future<void> startBackgroundRefresh() async {}

  @override
  Future<void> load() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<MagnitudeRefineResult> refine({
    required ProjectState project,
    required GoalVector goal,
    required List<MixAction> actions,
    required bool strict,
    String? projectId,
  }) async {
    return MagnitudeRefineResult(
      actions: actions,
      fallbackUsed: true,
      fallbackReason: 'disabled',
    );
  }
}

/// Observes inference only while explicitly enabled by producer capture.
/// Never adds capture fields to network requests or analytics.
class CapturingMagnitudePredictor implements MixingMagnitudePredictor {
  CapturingMagnitudePredictor(
    this.delegate, {
    required this.captureEnabled,
    required this.onTrace,
    required this.captureToken,
  });
  final MixingMagnitudePredictor delegate;
  final bool Function() captureEnabled;
  final String Function() captureToken;
  final void Function(Map<String, dynamic>) onTrace;
  @override
  bool get isEnabled => delegate.isEnabled;
  @override
  bool get isReady => delegate.isReady;
  @override
  Map<String, dynamic> get observabilityContext =>
      delegate.observabilityContext;
  @override
  Future<void> load() => delegate.load();
  @override
  Future<void> dispose() => delegate.dispose();
  @override
  Future<void> startBackgroundRefresh() => delegate.startBackgroundRefresh();
  @override
  Future<MagnitudeRefineResult> refine({
    required ProjectState project,
    required GoalVector goal,
    required List<MixAction> actions,
    required bool strict,
    String? projectId,
  }) async {
    final token = captureToken();
    Map<String, dynamic>? trace;
    if (captureEnabled()) {
      try {
        trace =
            jsonDecode(
                  jsonEncode({
                    'mix_feature_contract_version': 'mix_refine_v1',
                    'project_state': project.toMagnitudeResolverJson(),
                    'row_identities': {
                      for (final row in project.rows)
                        row.rowIndex.toString(): row.rowId,
                    },
                    'goal': goal.toJson(),
                    'actions': actions.map((a) => a.toJson()).toList(),
                    'strict': strict,
                  }),
                )
                as Map<String, dynamic>;
      } catch (_) {} // Capture must never interfere with inference.
    }
    final result = await delegate.refine(
      project: project,
      goal: goal,
      actions: actions,
      strict: strict,
      projectId: projectId,
    );
    if (trace != null && captureEnabled() && token == captureToken()) {
      try {
        onTrace({
          ...trace,
          'resolved_actions': result.actions.map((a) => a.toJson()).toList(),
          'debug_entries': result.debugEntries.map((a) => a.toJson()).toList(),
          'fallback_used': result.fallbackUsed,
          'fallback_reason': result.fallbackReason,
          'model_context': result.observability,
        });
      } catch (_) {}
    }
    return result;
  }
}
