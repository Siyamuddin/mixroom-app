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
}

class MagnitudeRefineResult {
  final List<MixAction> actions;
  final bool fallbackUsed;
  final String? fallbackReason;
  final List<MagnitudeActionDebugEntry> debugEntries;

  const MagnitudeRefineResult({
    required this.actions,
    required this.fallbackUsed,
    this.fallbackReason,
    this.debugEntries = const [],
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
  }) async {
    return MagnitudeRefineResult(
      actions: actions,
      fallbackUsed: true,
      fallbackReason: 'disabled',
    );
  }
}
