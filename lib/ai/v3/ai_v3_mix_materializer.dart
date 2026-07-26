import 'dart:async';

import '../../models/goal_vector.dart';
import '../../models/mixing_result.dart';
import '../../models/project_state.dart';
import '../local_mixing_model.dart';
import '../magnitude_predictor.dart';
import 'ai_v3_preparer.dart';

const Set<String> _v3AllowedMixActionTypes = <String>{
  'set_row_gain',
  'set_row_pan',
  'ensure_effect',
  'delete_effect',
  'adjust_effect_param_by_name',
  'hard_reset_row_fx',
  'set_master_gain',
  'set_master_pan',
  'ensure_master_effect',
  'delete_master_effect',
  'adjust_master_effect_param_by_name',
  'hard_reset_master_fx',
};

const Set<String> _v3RowMixActionTypes = <String>{
  'set_row_gain',
  'set_row_pan',
  'ensure_effect',
  'delete_effect',
  'adjust_effect_param_by_name',
  'hard_reset_row_fx',
};

class AiV3MixMaterializationResult {
  const AiV3MixMaterializationResult({
    required this.bundle,
    required this.metadata,
    this.noChangeMessage,
  });

  final AiV3PreparedBundle bundle;
  final Map<String, dynamic> metadata;
  final String? noChangeMessage;

  bool get isNoChange => bundle.actions.isEmpty;
}

class AiV3MixGoalMaterializer {
  const AiV3MixGoalMaterializer({
    required this.mixModel,
    required this.magnitudePredictor,
    this.refinementTimeout = const Duration(seconds: 12),
  });

  final LocalMixingModel mixModel;
  final MixingMagnitudePredictor magnitudePredictor;
  final Duration refinementTimeout;

  Future<AiV3MixMaterializationResult> materialize({
    required AiV3PreparedBundle bundle,
    required ProjectState project,
    required Map<int, String> roleOverrides,
    required bool bypassLearnedMagnitudes,
    String? projectId,
  }) async {
    if (!bundle.actions.any((action) => action.type == 'v3_mix_goal')) {
      return AiV3MixMaterializationResult(
        bundle: bundle,
        metadata: const <String, dynamic>{},
      );
    }

    final actions = <AssistantAction>[];
    final effectiveRoleOverrides = Map<int, String>.from(roleOverrides);
    final receipts = bundle.receipts
        .map((receipt) => Map<String, dynamic>.from(receipt))
        .toList(growable: false);
    final debugSteps = <Map<String, dynamic>>[];
    String? noChangeMessage;
    final directlyTargetedEffectRows = bundle.actions
        .where((action) => action.type == 'v3_effect_instance_edit')
        .map((action) {
          final target = action.data['target'];
          if (target is! Map) return -1;
          final row = target['row_index'];
          return row is int ? row : (row is num ? row.toInt() : -1);
        })
        .where((row) => row >= 0)
        .toSet();

    for (final action in bundle.actions) {
      if (action.type != 'v3_mix_goal') {
        if (action.type == 'v3_row_role_override') {
          final target = action.data['target'];
          final rowIndex =
              target is Map ? (target['row_index'] as num?)?.toInt() : null;
          if (rowIndex != null) {
            final role = action.data['role']?.toString().trim() ?? '';
            if (role.isEmpty) {
              effectiveRoleOverrides.remove(rowIndex);
            } else {
              effectiveRoleOverrides[rowIndex] = role;
            }
          }
        }
        actions.add(action);
        continue;
      }
      final commandId = action.data['command_id']?.toString() ?? '';
      final goal = _goalFromPreparedAction(action.data);
      final protectedReferenceRow = goal.referenceTarget?.rowIndex;

      final heuristicStopwatch = Stopwatch()..start();
      final heuristic = mixModel.run(
        project: project,
        goal: goal,
        strict: true,
        roleOverrides: effectiveRoleOverrides,
      );
      heuristicStopwatch.stop();
      var resolved = heuristic.actions
          .where((candidate) => candidate.type != 'noop')
          .toList(growable: false);
      MagnitudeRefineResult? refinement;
      final refinementStopwatch = Stopwatch();
      if (resolved.isNotEmpty && !bypassLearnedMagnitudes) {
        refinementStopwatch.start();
        try {
          refinement = await magnitudePredictor
              .refine(
                project: project,
                goal: goal,
                actions: resolved,
                strict: true,
                projectId: projectId,
              )
              .timeout(refinementTimeout);
        } on TimeoutException {
          refinement = MagnitudeRefineResult(
            actions: resolved,
            fallbackUsed: true,
            fallbackReason: 'refinement_timeout',
          );
        } catch (_) {
          refinement = MagnitudeRefineResult(
            actions: resolved,
            fallbackUsed: true,
            fallbackReason: 'refinement_failed',
          );
        }
        refinementStopwatch.stop();
        resolved = refinement.actions
            .where((candidate) => candidate.type != 'noop')
            .toList(growable: false);
      }
      _validateResolvedMixActions(
        resolved,
        project: project,
        protectedReferenceRow: protectedReferenceRow,
      );
      for (final candidate in resolved) {
        if (candidate.type != 'delete_effect' &&
            candidate.type != 'hard_reset_row_fx') {
          continue;
        }
        final target = candidate.data['target'];
        final targetMap = target is Map
            ? Map<String, dynamic>.from(target)
            : const <String, dynamic>{};
        final rawRow = candidate.data['row'] ??
            candidate.data['row_index'] ??
            targetMap['row'] ??
            targetMap['row_index'];
        final row =
            rawRow is int ? rawRow : (rawRow is num ? rawRow.toInt() : -1);
        if (directlyTargetedEffectRows.contains(row)) {
          throw const AiV3PreparationException(
            'v3_effect_instance_mix_conflict',
          );
        }
      }

      final receiptIndex = receipts.indexWhere(
        (receipt) => receipt['command_id'] == commandId,
      );
      if (receiptIndex < 0) {
        throw const AiV3PreparationException('v3_mix_receipt_missing');
      }
      final metadata = <String, dynamic>{
        'goal': goal.toJson(),
        'heuristic_actions':
            heuristic.actions.map((candidate) => candidate.toJson()).toList(),
        'refined_actions':
            resolved.map((candidate) => candidate.toJson()).toList(),
        'heuristic_elapsed_ms': heuristicStopwatch.elapsedMilliseconds,
        'refinement_elapsed_ms': refinementStopwatch.elapsedMilliseconds,
        'refinement_enabled': magnitudePredictor.isEnabled,
        'refinement_ready': magnitudePredictor.isReady,
        'refinement_bypassed': bypassLearnedMagnitudes,
        'refinement_context': magnitudePredictor.observabilityContext,
        if (refinement != null) ...<String, dynamic>{
          'refinement_fallback_used': refinement.fallbackUsed,
          if (refinement.fallbackReason != null)
            'refinement_fallback_reason': refinement.fallbackReason,
          'refinement_observability': refinement.observability,
          'refinement_debug': refinement.debugEntries
              .map((entry) => entry.toJson())
              .toList(growable: false),
        },
      };
      debugSteps.add(<String, dynamic>{
        'command_id': commandId,
        ...metadata,
      });

      if (resolved.isEmpty) {
        receipts[receiptIndex] = <String, dynamic>{
          ...receipts[receiptIndex],
          'status': 'already_satisfied',
          'expanded_action_count': 0,
          'mix_materialization': metadata,
        };
        noChangeMessage ??= 'No mix changes were needed.';
        continue;
      }

      actions.add(AssistantAction(
        type: 'v3_mix_actions',
        data: <String, dynamic>{
          'command_id': commandId,
          'actions': resolved.map((candidate) => candidate.toJson()).toList(),
          if (protectedReferenceRow != null)
            'protected_reference_row_index': protectedReferenceRow,
        },
      ));
      receipts[receiptIndex] = <String, dynamic>{
        ...receipts[receiptIndex],
        'status': 'prepared',
        'expanded_action_count': resolved.length,
        'mix_materialization': metadata,
      };
    }

    final visibleLabels = receipts
        .where((receipt) => receipt['status'] == 'prepared')
        .map((receipt) => receipt['preview_label']?.toString().trim() ?? '')
        .where((label) => label.isNotEmpty)
        .map((label) => '- $label')
        .toList(growable: false);
    final materializedBundle = AiV3PreparedBundle(
      plan: bundle.plan,
      stateDigest: bundle.stateDigest,
      actions: List<AssistantAction>.unmodifiable(actions),
      receipts: List<Map<String, dynamic>>.unmodifiable(receipts),
      executionPolicy: bundle.executionPolicy,
      preview: visibleLabels.isEmpty
          ? bundle.plan.userMessage
          : <String>[
              bundle.plan.userMessage,
              'Planned changes:',
              ...visibleLabels,
            ].join('\n'),
    );
    return AiV3MixMaterializationResult(
      bundle: materializedBundle,
      noChangeMessage: noChangeMessage ?? 'No mix changes were needed.',
      metadata: <String, dynamic>{'mix_materialization_steps': debugSteps},
    );
  }
}

GoalVector _goalFromPreparedAction(Map<String, dynamic> data) {
  final target = Map<String, dynamic>.from(data['target'] as Map);
  final scope = target['scope'] as String;
  final goalTarget = switch (scope) {
    'row' => <String, dynamic>{
        'scope': 'row',
        'row_index': target['row_index'],
        'confidence': 1.0,
      },
    'group' => <String, dynamic>{
        'scope': 'group',
        'group_id': target['group_id'],
        'confidence': 1.0,
      },
    'master' => const <String, dynamic>{
        'scope': 'master',
        'confidence': 1.0,
      },
    _ => const <String, dynamic>{
        'scope': 'auto',
        'confidence': 1.0,
      },
  };
  final reference = data['reference'];
  return GoalVector.fromJson(<String, dynamic>{
    'type': 'mix_request',
    'target': goalTarget,
    'intents': (data['intents'] as List)
        .whereType<Map>()
        .map((intent) => <String, dynamic>{
              ...Map<String, dynamic>.from(intent),
              'confidence': 1.0,
            })
        .toList(growable: false),
    'intensity': data['intensity'],
    'execution_profile': data['execution_profile'],
    'audibility': data['audibility'],
    'style_tags': data['style_tags'],
    'destructive_ok': data['execution_profile'] == 'experimental_extreme',
    'reset_fx': data['reset_fx'],
    if (reference is Map) ...<String, dynamic>{
      'reference_target': <String, dynamic>{
        'row_index': reference['row_index'],
        'confidence': 1.0,
      },
      'reference_mode': reference['mode'],
      'reference_closeness': reference['closeness'],
    },
  });
}

void _validateResolvedMixActions(
  List<MixAction> actions, {
  required ProjectState project,
  required int? protectedReferenceRow,
}) {
  for (final action in actions) {
    if (!_v3AllowedMixActionTypes.contains(action.type)) {
      throw const AiV3PreparationException('v3_mix_action_unsupported');
    }
    if (!_v3RowMixActionTypes.contains(action.type)) continue;
    final target = action.data['target'];
    final targetMap = target is Map
        ? Map<String, dynamic>.from(target)
        : const <String, dynamic>{};
    final rawRow = action.data['row'] ??
        action.data['row_index'] ??
        targetMap['row'] ??
        targetMap['row_index'];
    final row = rawRow is int ? rawRow : (rawRow is num ? rawRow.toInt() : -1);
    if (row < 0 || row >= project.rows.length) {
      throw const AiV3PreparationException('v3_mix_action_target_invalid');
    }
    if (protectedReferenceRow != null && row == protectedReferenceRow) {
      throw const AiV3PreparationException(
        'v3_mix_action_targets_reference',
      );
    }
  }
}
