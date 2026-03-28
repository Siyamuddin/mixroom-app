import '../models/goal_vector.dart';
import '../models/mixing_result.dart';
import '../models/project_state.dart';

class MagnitudeRefineResult {
  final List<MixAction> actions;
  final bool fallbackUsed;
  final String? fallbackReason;

  const MagnitudeRefineResult({
    required this.actions,
    required this.fallbackUsed,
    this.fallbackReason,
  });
}

abstract class MixingMagnitudePredictor {
  bool get isEnabled;
  bool get isReady;

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
