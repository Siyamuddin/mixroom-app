import 'dart:async';

import '../../helpers/effect_parameter_exposure.dart';
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

const Set<String> _v3MasterMixActionTypes = <String>{
  'set_master_gain',
  'set_master_pan',
  'ensure_master_effect',
  'delete_master_effect',
  'adjust_master_effect_param_by_name',
  'hard_reset_master_fx',
};

const Set<String> _v3EffectWritingMixActionTypes = <String>{
  'ensure_effect',
  'adjust_effect_param_by_name',
  'ensure_master_effect',
  'adjust_master_effect_param_by_name',
};

/// Copies validated mix actions into their executor-facing form.
///
/// V3 row scopes always refer to individual ready rows, even when those rows
/// belong to a group. The editor's legacy mix executor otherwise redirects a
/// row action to its group bus. Master actions retain their original data.
List<MixAction> normalizeAiV3MixActionsForExecution(
  Iterable<MixAction> actions,
) => List<MixAction>.unmodifiable(
  actions.map((action) {
    final data = Map<String, dynamic>.from(action.data);
    if (_v3RowMixActionTypes.contains(action.type)) {
      data['force_individual_row'] = true;
    }
    return MixAction(action.type, data);
  }),
);

void validateAiV3MixEffectCapabilities(
  Iterable<MixAction> actions, {
  required Set<String> allowedEffectIds,
}) {
  final canonicalAllowedEffectIds = <String>{
    for (final effectId in allowedEffectIds)
      if (canonicalMixroomBuiltInEffectId(effectId) case final canonical?)
        canonical,
  };
  for (final action in actions) {
    if (!_v3EffectWritingMixActionTypes.contains(action.type)) continue;
    final submittedEffectId =
        action.data['effect_name_contains']?.toString().trim() ?? '';
    final canonicalEffectId = canonicalMixroomBuiltInEffectId(
      submittedEffectId,
    );
    if (canonicalEffectId == null ||
        !canonicalAllowedEffectIds.contains(canonicalEffectId)) {
      throw AiV3PreparationException(
        'v3_effect_id_unknown',
        commandType: 'mix.apply_goal',
        effectId: submittedEffectId,
        reason: canonicalEffectId == null
            ? 'unknown_effect'
            : 'effect_unavailable',
      );
    }
  }
}

Map<int, String> aiV3CurrentRoleOverrides(ProjectState project) =>
    <int, String>{
      for (final row in project.rows)
        if (row.roleOverride.trim().isNotEmpty)
          row.rowIndex: row.roleOverride.trim(),
    };

/// Ordered explicit-effect decisions that later subjective mix goals must
/// respect. This is intentionally not a project-state copy: it records only
/// precedence that cannot be inferred from the current effect chain.
class AiV3OrderedEffectConstraints {
  final Map<int, Set<String>> _unavailableEffectIdsByRowId =
      <int, Set<String>>{};

  void observeAppliedAction(String type, Map<String, dynamic> data) {
    final target = data['target'];
    if (target is! Map) return;
    final rawRowId = target['row_id'];
    final rowId = rawRowId is int
        ? rawRowId
        : rawRowId is num
        ? rawRowId.toInt()
        : null;
    if (rowId == null) return;
    final effectId = canonicalMixroomBuiltInEffectId(
      data['effect_id']?.toString() ?? '',
    );
    if (effectId == null) return;

    if (type == 'v3_effect_instance_edit' && data['operation'] == 'remove') {
      _unavailableEffectIdsByRowId
          .putIfAbsent(rowId, () => <String>{})
          .add(effectId);
      return;
    }
    if (type == 'v3_effect_configure' &&
        data['operation'] == 'ensure_configured') {
      final effects = _unavailableEffectIdsByRowId[rowId];
      effects?.remove(effectId);
      if (effects?.isEmpty ?? false) {
        _unavailableEffectIdsByRowId.remove(rowId);
      }
    }
  }

  Map<int, Set<String>> unavailableByRowIndex(ProjectState project) {
    return Map<int, Set<String>>.unmodifiable(<int, Set<String>>{
      for (final row in project.rows)
        if (_unavailableEffectIdsByRowId[row.rowId]?.isNotEmpty ?? false)
          row.rowIndex: Set<String>.unmodifiable(
            _unavailableEffectIdsByRowId[row.rowId]!,
          ),
    });
  }
}

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

class AiV3SingleMixGoalResult {
  const AiV3SingleMixGoalResult({
    required this.actions,
    required this.metadata,
    this.protectedReferenceRow,
  });

  final List<MixAction> actions;
  final Map<String, dynamic> metadata;
  final int? protectedReferenceRow;

  bool get isNoChange => actions.isEmpty;
}

class AiV3MixContainment {
  const AiV3MixContainment({
    required this.requiredTargetRow,
    required this.allowedTargetRowIds,
    required this.masterOnly,
  });

  final int? requiredTargetRow;
  final Set<int>? allowedTargetRowIds;
  final bool masterOnly;
}

AiV3MixContainment resolveAiV3MixContainment(
  Map<String, dynamic> data,
  ProjectState project,
) {
  final rawTarget = data['target'];
  if (rawTarget is! Map) {
    throw const AiV3PreparationException('v3_mix_action_target_invalid');
  }
  final target = Map<String, dynamic>.from(rawTarget);
  switch (target['scope']) {
    case 'row':
      final rawRow = target['row_index'];
      final rowIndex = rawRow is int
          ? rawRow
          : rawRow is num
          ? rawRow.toInt()
          : -1;
      final rawRowId = target['row_id'];
      final rowId = rawRowId is int
          ? rawRowId
          : rawRowId is num
          ? rawRowId.toInt()
          : null;
      final projectRow = project.rows
          .where(
            (candidate) =>
                candidate.rowIndex == rowIndex &&
                (rowId == null || candidate.rowId == rowId),
          )
          .firstOrNull;
      if (projectRow == null) {
        throw const AiV3PreparationException('v3_mix_action_target_invalid');
      }
      if (!projectRow.hasAudio) {
        throw const AiV3PreparationException('v3_mix_audio_missing');
      }
      return AiV3MixContainment(
        requiredTargetRow: rowIndex,
        allowedTargetRowIds: <int>{projectRow.rowId},
        masterOnly: false,
      );
    case 'group':
      final groupId = target['group_id']?.toString().trim() ?? '';
      final group = project.trackGroups
          .where((candidate) => candidate.id == groupId)
          .firstOrNull;
      if (group == null || group.rowIds.length < 2) {
        throw const AiV3PreparationException('v3_mix_action_target_invalid');
      }
      final liveRowIds = project.rows.map((row) => row.rowId).toSet();
      final memberRowIds = group.rowIds.toSet();
      if (memberRowIds.length != group.rowIds.length ||
          !liveRowIds.containsAll(memberRowIds)) {
        throw const AiV3PreparationException('v3_mix_action_target_invalid');
      }
      final readyMemberRowIds = project.rows
          .where((row) => memberRowIds.contains(row.rowId) && row.hasAudio)
          .map((row) => row.rowId)
          .toSet();
      if (readyMemberRowIds.isEmpty) {
        throw const AiV3PreparationException('v3_mix_audio_missing');
      }
      return AiV3MixContainment(
        requiredTargetRow: null,
        allowedTargetRowIds: readyMemberRowIds,
        masterOnly: false,
      );
    case 'all_rows':
      final readyRowIds = project.rows
          .where((row) => row.hasAudio)
          .map((row) => row.rowId)
          .toSet();
      if (readyRowIds.isEmpty) {
        throw const AiV3PreparationException('v3_mix_audio_missing');
      }
      return AiV3MixContainment(
        requiredTargetRow: null,
        allowedTargetRowIds: readyRowIds,
        masterOnly: false,
      );
    case 'master':
      if (!project.rows.any((row) => row.hasAudio)) {
        throw const AiV3PreparationException('v3_mix_audio_missing');
      }
      return const AiV3MixContainment(
        requiredTargetRow: null,
        allowedTargetRowIds: null,
        masterOnly: true,
      );
    default:
      throw const AiV3PreparationException('v3_mix_action_target_invalid');
  }
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

  Future<AiV3SingleMixGoalResult> materializeSingleGoal({
    required Map<String, dynamic> data,
    required ProjectState project,
    required Map<int, String> roleOverrides,
    required bool bypassLearnedMagnitudes,
    required Set<String> allowedEffectIds,
    int? requiredTargetRow,
    Set<int>? allowedTargetRowIds,
    AiV3OrderedEffectConstraints? effectConstraints,
    String? projectId,
  }) async {
    final goal = _goalFromPreparedAction(data);
    final inferredContainment = resolveAiV3MixContainment(data, project);
    final masterOnly = inferredContainment.masterOnly;
    final protectedReferenceRow = goal.referenceTarget?.rowIndex;
    final effectiveRequiredTargetRow =
        requiredTargetRow ?? inferredContainment.requiredTargetRow;
    if (effectiveRequiredTargetRow != null &&
        goal.target.rowIndex != effectiveRequiredTargetRow) {
      throw const AiV3PreparationException('v3_mix_action_target_invalid');
    }
    final effectiveAllowedRowIds =
        allowedTargetRowIds ??
        inferredContainment.allowedTargetRowIds ??
        (effectiveRequiredTargetRow == null
            ? null
            : <int>{
                project.rows
                    .firstWhere(
                      (row) => row.rowIndex == effectiveRequiredTargetRow,
                    )
                    .rowId,
              });
    final inferredAllowedRowIds = inferredContainment.allowedTargetRowIds;
    if (effectiveAllowedRowIds != null &&
        inferredAllowedRowIds != null &&
        !inferredAllowedRowIds.containsAll(effectiveAllowedRowIds)) {
      throw const AiV3PreparationException('v3_mix_action_target_invalid');
    }
    final unavailableEffectIdsByRow =
        effectConstraints?.unavailableByRowIndex(project) ??
        const <int, Set<String>>{};
    final generationScope = masterOnly
        ? const MixGenerationScope.master()
        : effectiveAllowedRowIds == null
        ? null
        : MixGenerationScope.rows(<int>{
            for (final row in project.rows)
              if (effectiveAllowedRowIds.contains(row.rowId)) row.rowIndex,
          }, unavailableEffectIdsByRow: unavailableEffectIdsByRow);

    final heuristicStopwatch = Stopwatch()..start();
    final heuristic = mixModel.run(
      project: project,
      goal: goal,
      strict: true,
      roleOverrides: roleOverrides,
      generationScope: generationScope,
    );
    heuristicStopwatch.stop();
    // Inference and capture must see the same row-vs-bus target as execution.
    var resolved = normalizeAiV3MixActionsForExecution(
      heuristic.actions.where((candidate) => candidate.type != 'noop'),
    );
    validateAiV3MixEffectCapabilities(
      resolved,
      allowedEffectIds: allowedEffectIds,
    );
    _validateResolvedMixActions(
      resolved,
      project: project,
      protectedReferenceRow: protectedReferenceRow,
      requiredTargetRow: effectiveRequiredTargetRow,
      allowedTargetRowIds: effectiveAllowedRowIds,
      masterOnly: masterOnly,
      unavailableEffectIdsByRow: unavailableEffectIdsByRow,
    );
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
    validateAiV3MixEffectCapabilities(
      resolved,
      allowedEffectIds: allowedEffectIds,
    );
    _validateResolvedMixActions(
      resolved,
      project: project,
      protectedReferenceRow: protectedReferenceRow,
      requiredTargetRow: effectiveRequiredTargetRow,
      allowedTargetRowIds: effectiveAllowedRowIds,
      masterOnly: masterOnly,
      unavailableEffectIdsByRow: unavailableEffectIdsByRow,
    );
    return AiV3SingleMixGoalResult(
      actions: resolved,
      protectedReferenceRow: protectedReferenceRow,
      metadata: <String, dynamic>{
        'goal': goal.toJson(),
        'heuristic_actions': heuristic.actions
            .map((candidate) => candidate.toJson())
            .toList(),
        'refined_actions': resolved
            .map((candidate) => candidate.toJson())
            .toList(),
        'heuristic_elapsed_ms': heuristicStopwatch.elapsedMilliseconds,
        'refinement_elapsed_ms': refinementStopwatch.elapsedMilliseconds,
        'refinement_enabled': magnitudePredictor.isEnabled,
        'refinement_ready': magnitudePredictor.isReady,
        'refinement_bypassed': bypassLearnedMagnitudes,
        'refinement_context': magnitudePredictor.observabilityContext,
        if (effectiveAllowedRowIds != null)
          'allowed_target_row_ids': effectiveAllowedRowIds.toList()..sort(),
        if (masterOnly) 'master_only': true,
        if (refinement != null) ...<String, dynamic>{
          'refinement_fallback_used': refinement.fallbackUsed,
          if (refinement.fallbackReason != null)
            'refinement_fallback_reason': refinement.fallbackReason,
          'refinement_observability': refinement.observability,
          'refinement_debug': refinement.debugEntries
              .map((entry) => entry.toJson())
              .toList(growable: false),
        },
      },
    );
  }

  Future<AiV3MixMaterializationResult> materialize({
    required AiV3PreparedBundle bundle,
    required ProjectState project,
    required Map<int, String> roleOverrides,
    required bool bypassLearnedMagnitudes,
    required Set<String> allowedEffectIds,
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
    final effectConstraints = AiV3OrderedEffectConstraints();
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
          final rowIndex = target is Map
              ? (target['row_index'] as num?)?.toInt()
              : null;
          if (rowIndex != null) {
            final role = action.data['role']?.toString().trim() ?? '';
            if (role.isEmpty) {
              effectiveRoleOverrides.remove(rowIndex);
            } else {
              effectiveRoleOverrides[rowIndex] = role;
            }
          }
        }
        effectConstraints.observeAppliedAction(action.type, action.data);
        actions.add(action);
        continue;
      }
      final commandId = action.data['command_id']?.toString() ?? '';
      final materializedGoal = await materializeSingleGoal(
        data: action.data,
        project: project,
        roleOverrides: effectiveRoleOverrides,
        bypassLearnedMagnitudes: bypassLearnedMagnitudes,
        allowedEffectIds: allowedEffectIds,
        effectConstraints: effectConstraints,
        projectId: projectId,
      );
      final resolved = materializedGoal.actions;
      final protectedReferenceRow = materializedGoal.protectedReferenceRow;
      for (final candidate in resolved) {
        if (candidate.type != 'delete_effect' &&
            candidate.type != 'hard_reset_row_fx') {
          continue;
        }
        final target = candidate.data['target'];
        final targetMap = target is Map
            ? Map<String, dynamic>.from(target)
            : const <String, dynamic>{};
        final rawRow =
            candidate.data['row'] ??
            candidate.data['row_index'] ??
            targetMap['row'] ??
            targetMap['row_index'];
        final row = rawRow is int
            ? rawRow
            : (rawRow is num ? rawRow.toInt() : -1);
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
      final metadata = materializedGoal.metadata;
      debugSteps.add(<String, dynamic>{'command_id': commandId, ...metadata});

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

      final executionActions = normalizeAiV3MixActionsForExecution(resolved);

      actions.add(
        AssistantAction(
          type: 'v3_mix_actions',
          data: <String, dynamic>{
            'command_id': commandId,
            'actions': executionActions
                .map((candidate) => candidate.toJson())
                .toList(),
            if (protectedReferenceRow != null)
              'protected_reference_row_index': protectedReferenceRow,
          },
        ),
      );
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
    'master' => const <String, dynamic>{'scope': 'master', 'confidence': 1.0},
    _ => const <String, dynamic>{'scope': 'auto', 'confidence': 1.0},
  };
  final reference = data['reference'];
  return GoalVector.fromJson(<String, dynamic>{
    'type': 'mix_request',
    'target': goalTarget,
    'intents': (data['intents'] as List)
        .whereType<Map>()
        .map(
          (intent) => <String, dynamic>{
            ...Map<String, dynamic>.from(intent),
            'confidence': 1.0,
          },
        )
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
  int? requiredTargetRow,
  Set<int>? allowedTargetRowIds,
  bool masterOnly = false,
  Map<int, Set<String>> unavailableEffectIdsByRow = const {},
}) {
  for (final action in actions) {
    if (!_v3AllowedMixActionTypes.contains(action.type)) {
      throw const AiV3PreparationException('v3_mix_action_unsupported');
    }
    if (masterOnly && !_v3MasterMixActionTypes.contains(action.type)) {
      throw const AiV3PreparationException('v3_mix_action_target_invalid');
    }
    if (!_v3RowMixActionTypes.contains(action.type)) {
      if (requiredTargetRow != null || allowedTargetRowIds != null) {
        throw const AiV3PreparationException('v3_mix_action_target_invalid');
      }
      continue;
    }
    final target = action.data['target'];
    final targetMap = target is Map
        ? Map<String, dynamic>.from(target)
        : const <String, dynamic>{};
    final rawRow =
        action.data['row'] ??
        action.data['row_index'] ??
        targetMap['row'] ??
        targetMap['row_index'];
    final row = rawRow is int ? rawRow : (rawRow is num ? rawRow.toInt() : -1);
    if (row < 0 || row >= project.rows.length) {
      throw const AiV3PreparationException('v3_mix_action_target_invalid');
    }
    if (requiredTargetRow != null && row != requiredTargetRow) {
      throw const AiV3PreparationException('v3_mix_action_target_invalid');
    }
    if (allowedTargetRowIds != null) {
      final projectRow = project.rows
          .where((candidate) => candidate.rowIndex == row)
          .firstOrNull;
      if (projectRow == null ||
          !allowedTargetRowIds.contains(projectRow.rowId)) {
        throw const AiV3PreparationException('v3_mix_action_target_invalid');
      }
    }
    if (protectedReferenceRow != null && row == protectedReferenceRow) {
      throw const AiV3PreparationException('v3_mix_action_targets_reference');
    }
    if (action.type == 'ensure_effect' ||
        action.type == 'adjust_effect_param_by_name') {
      final effectId = canonicalMixroomBuiltInEffectId(
        action.data['effect_name_contains']?.toString() ?? '',
      );
      if (effectId != null &&
          (unavailableEffectIdsByRow[row] ?? const <String>{}).contains(
            effectId,
          )) {
        throw const AiV3PreparationException(
          'v3_mix_effect_constraint_violation',
        );
      }
    }
  }
}
