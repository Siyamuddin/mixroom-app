import 'dart:math' as math;

import '../models/goal_vector.dart';
import '../models/mixing_result.dart';
import '../models/models.dart';
import '../models/project_state.dart';

class _MixExecutionPolicy {
  const _MixExecutionPolicy({
    required this.executionProfile,
    required this.audibility,
    required this.destructiveOk,
    required this.intensityMultiplier,
    required this.maxIntensity,
    required this.ceilingMultiplier,
  });

  final MixExecutionProfile executionProfile;
  final MixAudibility audibility;
  final bool destructiveOk;
  final double intensityMultiplier;
  final double maxIntensity;
  final double ceilingMultiplier;

  double scaleIntensity(double raw) {
    return (raw.clamp(0.0, 1.0) * intensityMultiplier).clamp(0.0, maxIntensity);
  }

  double blend(
    double raw, {
    double floor = 0.35,
    double ceiling = 1.0,
  }) {
    final boostedCeiling = ceiling * ceilingMultiplier;
    return (floor + ((ceiling - floor) * scaleIntensity(raw))).clamp(
      floor,
      boostedCeiling,
    );
  }

  double audibleFloor({
    required double subtle,
    required double noticeable,
    required double obvious,
    required double extreme,
  }) {
    switch (audibility) {
      case MixAudibility.subtle:
        return subtle;
      case MixAudibility.noticeable:
        return noticeable;
      case MixAudibility.obvious:
        return obvious;
      case MixAudibility.extreme:
        return extreme;
    }
  }

  bool get skipDisagreementGuard =>
      destructiveOk ||
      executionProfile != MixExecutionProfile.producerSafe ||
      audibility.index >= MixAudibility.obvious.index;

  bool get prefersLongDelay =>
      executionProfile != MixExecutionProfile.producerSafe ||
      audibility.index >= MixAudibility.obvious.index;

  static _MixExecutionPolicy fromGoal(GoalVector goal) {
    final effectiveDestructive = goal.effectiveDestructive;
    final profileMultiplier = switch (goal.executionProfile) {
      MixExecutionProfile.producerSafe => 1.0,
      MixExecutionProfile.creativeBold => 1.25,
      MixExecutionProfile.experimentalExtreme =>
        effectiveDestructive ? 1.6 : 1.4,
    };
    final audibilityMultiplier = switch (goal.audibility) {
      MixAudibility.subtle => 0.7,
      MixAudibility.noticeable => 1.0,
      MixAudibility.obvious => 1.25,
      MixAudibility.extreme => effectiveDestructive ? 1.6 : 1.35,
    };
    final ceilingMultiplier = switch (goal.executionProfile) {
      MixExecutionProfile.producerSafe => 1.0,
      MixExecutionProfile.creativeBold => 1.15,
      MixExecutionProfile.experimentalExtreme =>
        effectiveDestructive ? 1.35 : 1.2,
    };
    final maxIntensity = switch (goal.executionProfile) {
      MixExecutionProfile.producerSafe => 1.1,
      MixExecutionProfile.creativeBold => 1.45,
      MixExecutionProfile.experimentalExtreme =>
        effectiveDestructive ? 1.8 : 1.55,
    };
    return _MixExecutionPolicy(
      executionProfile: goal.executionProfile,
      audibility: goal.audibility,
      destructiveOk: effectiveDestructive,
      intensityMultiplier: profileMultiplier * audibilityMultiplier,
      maxIntensity: maxIntensity,
      ceilingMultiplier: ceilingMultiplier,
    );
  }
}

/// LocalMixingModel
/// - Produces MixAction list (gain/pan/fx) from GoalVector + ProjectState
/// - Includes safety rails for UI-exposed FX params only
/// - Includes masking detection, vocal dominance, bass vs kick balance, harshness via HF RMS
/// - Includes pending-permission scaffolding (requires pipeline support)
class LocalMixingModel {
  // -----------------------------
  // FX names / contains
  // -----------------------------
  static const String fxReverb = 'Reverb';
  static const String fxEq = 'EQ 3-Band';
  static const String fxEqParametric = 'EQ Parametric';
  static const String fxDelay = 'Delay';
  static const String fxDeEsserContains = 'De-Esser';
  static const String fxDistortionContains = 'Distortion';
  static const String fxCompressor = 'Compressor';
  static const String fxLimiter = 'Limiter';
  static const String fxClipper = 'Clipper';

  // -----------------------------
  // UI-exposed param safety rail
  // -----------------------------
  static const Map<String, List<String>> exposedFxParams = {
    'Reverb': ['Mix', 'Room Size'],
    'EQ Parametric': [
      'HPF Frequency',
      'Band 1 Frequency',
      'Band 1 Gain',
      'Band 1 Q',
      'Band 2 Frequency',
      'Band 2 Gain',
      'Band 2 Q',
      'Band 3 Frequency',
      'Band 3 Gain',
      'Band 3 Q',
      'Band 4 Frequency',
      'Band 4 Gain',
      'Band 4 Q',
      'LPF Frequency',
    ],
    'EQ 3-Band': ['Low Gain', 'Mid Gain', 'High Gain'],
    'Delay': ['Delay Time', 'Feedback', 'Mix'],
    // In case your distortion UI later exposes more, keep these permissive but still bounded
    'Distortion': [
      'Drive',
      'Gain',
      'Amount',
      'Mix',
      'Volume',
      'LPF Frequency',
      'Distortion Type',
      'Pre Shape',
      'Anger',
    ],
    // substring-based
    'De-Esser': ['Threshold', 'Frequency'],
    'Compressor': ['Threshold', 'Attack', 'Release', 'Ratio', 'Makeup', 'Mix'],
    'Transient Shaper': ['Attack', 'Pump', 'Sustain', 'Speed', 'Clip'],
    'Limiter': ['Threshold', 'Release', 'Ceiling'],
    'Clipper': ['Threshold', 'Ceiling'],
  };

  static const bool preferLoudCleanOverConservative = true;
  static const double _kGainUiMin = 0.0;
  static const double _kGainUiMax = 3.0;
  static const double _kGainUiUnity = 2.0;
  static const double _kGainDbMin = -60.0;
  static const double _kGainDbMax = 6.0;

  bool _isAllowedFxParam(String effectContains, List<String> paramContainsAny) {
    final eff = effectContains.toLowerCase();
    for (final entry in exposedFxParams.entries) {
      final effectKey = entry.key.toLowerCase();

      // We allow either exact-ish or contains matching
      if (!(eff.contains(effectKey) || effectKey.contains(eff))) continue;

      final allowed = entry.value;
      for (final p in paramContainsAny) {
        final pp = p.toLowerCase();
        for (final a in allowed) {
          if (pp.contains(a.toLowerCase())) return true;
        }
      }
    }
    return false;
  }

  // -----------------------------
  // Goal normalization (LLM → stable intents)
  // -----------------------------
  /// If your LLM sometimes outputs weird kinds/directions/descriptors,
  /// this makes GoalVector intents stable before planning.
  // NOTE: From this point on, intents are canonical.
  // No language inference is allowed beyond this boundary.

  GoalVector normalizeGoal(GoalVector goal) {
    if (goal.type != 'mix_request') return goal;

    final allowedKinds = <String>{
      'gain',
      'pan',
      'eq',
      'reverb',
      'delay',
      'distortion',
      'deesser',
      'compressor',
      'limiter',
      'clipper',
      'balance'
    };
    final allowedDirs = <String>{
      'up',
      'down',
      'left',
      'right',
      'center',
      'widen',
      'narrow',
      'remove'
    };
    final allowedEqDesc = <String>{
      'mud_cut',
      'box_cut',
      'boom_cut',
      'harsh_cut',
      'presence_boost',
      'air_boost',
      'warmth_boost',
      'thin_fix',
      'dull_fix',
      'low_cut',
      'high_cut',
    };

    final normIntents = <MixIntent>[];

    for (final it in goal.intents) {
      final kind = it.kind.trim().toLowerCase();
      if (!allowedKinds.contains(kind)) continue;

      final dir = it.direction?.trim().toLowerCase();
      final dirOk = (dir == null) || allowedDirs.contains(dir);

      String? desc = it.descriptor?.trim().toLowerCase();
      if (desc != null && kind != 'eq')
        desc = null; // descriptors only allowed for EQ
      if (desc != null && !allowedEqDesc.contains(desc)) desc = null;

      final conf = it.confidence.clamp(0.0, 1.0);
      if (conf < 0.12) continue;

      normIntents.add(MixIntent(
          kind: kind,
          direction: dirOk ? dir : null,
          descriptor: desc,
          confidence: conf));
    }

    if (normIntents.isEmpty) {
      normIntents.add(MixIntent(kind: 'balance', confidence: 0.6));
    }

    normIntents.sort((a, b) => b.confidence.compareTo(a.confidence));

    return GoalVector(
      type: goal.type,
      intents: normIntents.take(4).toList(),
      target: goal.target,
      intensity: goal.intensity,
      executionProfile: goal.executionProfile,
      audibility: goal.audibility,
      styleTags: goal.styleTags,
      destructiveOk: goal.destructiveOk,
      referenceTarget: goal.referenceTarget,
      referenceMode: goal.referenceMode,
      referenceCloseness: goal.referenceCloseness,
      resetFx: goal.resetFx,
    );
  }

  // -----------------------------
  // Main entry
  // -----------------------------
  MixingResult run({
    required ProjectState project,
    required GoalVector goal,
    required bool strict,
    Map<int, String> roleOverrides = const {},
    bool requirePermissionForBigMoves = false,
  }) {
    // Normalize intents (LLM → stable)
    var normGoal = normalizeGoal(goal);

    if (normGoal.type != 'mix_request') {
      return const MixingResult(
          actions: [], summary: 'No mix changes requested.', isNoOp: true);
    }

    final intents = [...normGoal.intents]
      ..removeWhere((i) => i.confidence < 0.20)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final resolvedIntents = intents.isEmpty
        ? [MixIntent(kind: 'balance', confidence: 0.6)]
        : intents;

    final ref = _mixReference(project);

    // Normalize "null" strings coming from LLM
    String? role = normGoal.target.role;
    if (role != null && role.toLowerCase().trim() == 'null') {
      role = null;
    }

    int? rowIndex = normGoal.target.rowIndex;
    // if (rowIndex != null) {
    //   // LLM row_index is ALWAYS UI-based (1-indexed)
    //   rowIndex = rowIndex - 1;

    //   if (rowIndex < 0 || rowIndex >= project.maxRows) {
    //     rowIndex = null;
    //   }
    // }

    // Rebuild target with normalized values
    normGoal = GoalVector(
      type: normGoal.type,
      intents: normGoal.intents,
      target: MixTarget(
        role: role,
        rowIndex: rowIndex,
        groupId: normGoal.target.groupId,
        groupName: normGoal.target.groupName,
        scope: normGoal.target.scope,
        confidence: normGoal.target.confidence,
      ),
      intensity: normGoal.intensity,
      executionProfile: normGoal.executionProfile,
      audibility: normGoal.audibility,
      destructiveOk: normGoal.destructiveOk,
      referenceTarget: normGoal.referenceTarget,
      referenceMode: normGoal.referenceMode,
      referenceCloseness: normGoal.referenceCloseness,
      resetFx: normGoal.resetFx,
    );

    // NOW resolve targets
    final targets = _resolveTargets(project, normGoal.target, roleOverrides);
    final referenceRow =
        _resolveReferenceRow(project, normGoal.referenceTarget);
    final effectiveTargets = _excludeReferenceRow(targets, referenceRow);

    if (normGoal.referenceTarget != null && referenceRow == null) {
      return const MixingResult(
        actions: [],
        summary:
            "I couldn't find the reference track. Select it or point me to a valid row and try again.",
        isNoOp: true,
      );
    }

    if (normGoal.referenceTarget != null && _isMasterTarget(normGoal.target)) {
      return const MixingResult(
        actions: [],
        summary:
            "I can't reference-match on the master bus while the reference lives in this project. Target the other rows instead.",
        isNoOp: true,
      );
    }

    final referenceScopeRows = referenceRow == null
        ? const <RowState>[]
        : _rowsForReferenceMatch(
            project: project,
            resolvedTargets: effectiveTargets,
            target: normGoal.target,
            referenceRow: referenceRow,
          );

    // 1.5) If user targets a role (vocals/guitar/etc) and multiple rows match:
    if (!_isMasterTarget(normGoal.target) &&
        normGoal.target.role != null &&
        normGoal.target.rowIndex == null &&
        effectiveTargets.length >= 2) {
      final overlaps = _anyOverlap(project, effectiveTargets);

      // Interpretive: ask which one if they overlap (avoid making lead/backing wrong)
      if (!strict && overlaps) {
        final roleName = normGoal.target.role!;
        final rowsStr =
            effectiveTargets.map((r) => 'Track ${r.rowIndex + 1}').join(', ');
        return MixingResult(
          actions: const [],
          summary:
              "I found multiple $roleName tracks ($rowsStr) that overlap. Which one is the *main* $roleName?",
          isNoOp: true,
          notes: const [
            'Tip: name the main part and backing part by track number.'
          ],
        );
      }

      // Direct command: apply to all role tracks, but be gentle if they overlap.
      // Non-overlapping → safe to apply to all normally.
      // Overlapping → reduce intensity slightly to avoid blowing up stacked parts.
      if (strict && overlaps) {
        // reduce intensity by 25% for multi-overlapping role stacks
        normGoal = GoalVector(
          type: normGoal.type,
          intents: normGoal.intents,
          target: normGoal.target,
          intensity: (normGoal.intensity * 0.75).clamp(0.0, 1.0),
          executionProfile: normGoal.executionProfile,
          audibility: normGoal.audibility,
          destructiveOk: normGoal.destructiveOk,
          referenceTarget: normGoal.referenceTarget,
          referenceMode: normGoal.referenceMode,
          referenceCloseness: normGoal.referenceCloseness,
          resetFx: normGoal.resetFx,
        );
      }
    }

    final policy = _MixExecutionPolicy.fromGoal(normGoal);

    if (normGoal.referenceTarget != null && referenceScopeRows.isEmpty) {
      return const MixingResult(
        actions: [],
        summary:
            "I don't adjust the reference row itself. Target the rest of the project or a different row.",
        isNoOp: true,
      );
    }

    // 2) If role is known but confidence is low, ask to clarify (prevents wrong-row edits).
    if (!_isMasterTarget(normGoal.target) &&
        normGoal.target.role != null &&
        normGoal.target.rowIndex == null &&
        normGoal.target.confidence < 0.40) {
      return const MixingResult(
        actions: [],
        summary:
            "I'm not confident which track you mean. Tell me the track number and role.",
        isNoOp: true,
      );
    }

    // 3) If explicit target and we can't resolve, don't guess.
    if (_isExplicitTarget(normGoal.target) &&
        !_isMasterTarget(normGoal.target) &&
        effectiveTargets.isEmpty) {
      return const MixingResult(
        actions: [],
        summary:
            "I couldn't find that target. Tell me the track number and what role it should have.",
        isNoOp: true,
      );
    }

    final actions = <MixAction>[];
    var referencePlanApplied = false;

    // FX RESET PHASE (authoritative)
    if (normGoal.resetFx) {
      actions.addAll(
        _planHardReset(
          project,
          target: normGoal.target,
          resolvedTargets: effectiveTargets,
        ),
      );
    }

    final notes = <String>[];

    // Diagnostics: mixed-role rows (warn)
    for (final r in project.rows) {
      if (r.approxRms <= 0.001) continue;
      if (r.roleConsistency < 0.65 &&
          r.clipTopRoles.length >= 2 &&
          _hasOverlappingMixedRoles(project, r.rowIndex)) {
        notes.add(
          "Track ${r.rowIndex + 1} looks mixed (${r.clipTopRoles.toSet().join(', ')} at different times). "
          "For best results, consider moving clips so each track is one role.",
        );
      }
    }
    // 0) Headroom safety (always ok)
    final safetyPool = referenceRow == null
        ? project.rows
        : project.rows
            .where((r) => r.rowIndex != referenceRow.rowIndex)
            .toList(growable: false);
    final safetyRows = strict
        ? (effectiveTargets.isNotEmpty ? effectiveTargets : safetyPool)
        : safetyPool;

    // If user intent is to bring something forward, do NOT pre-attenuate it
    final wantsUpFront = resolvedIntents.any((i) =>
        (i.kind == 'gain' || i.kind == 'balance') && i.direction == 'up');

    final safetyLimit = wantsUpFront && effectiveTargets.isNotEmpty
        ? safetyPool.where((r) => !effectiveTargets.contains(r)).toList()
        : safetyRows;
    if (!_isMasterTarget(normGoal.target)) {
      actions.addAll(_planHeadroomSafety(project,
          intensity: policy.scaleIntensity(normGoal.intensity).clamp(0.0, 1.0),
          limitTo: safetyLimit));
    }

    final onlyBalanceIntents =
        resolvedIntents.every((intent) => intent.kind == 'balance');
    if (referenceRow != null) {
      final referencePlan = _planReferenceGuidedMix(
        project: project,
        referenceRow: referenceRow,
        subjectRows: referenceScopeRows,
        goal: normGoal,
        roleOverrides: roleOverrides,
        strict: strict,
        policy: policy,
      );
      if (referencePlan.actions.isNotEmpty) {
        actions.addAll(referencePlan.actions);
        notes.addAll(referencePlan.notes);
        referencePlanApplied = true;
      } else if (referencePlan.noOpSummary != null && onlyBalanceIntents) {
        return MixingResult(
          actions: const [],
          summary: referencePlan.noOpSummary!,
          isNoOp: true,
          notes: referencePlan.notes,
        );
      } else if (referencePlan.noOpSummary != null) {
        notes.add(referencePlan.noOpSummary!);
      }
    }

    // 1) Apply intents
    for (final it in resolvedIntents) {
      final kind = it.kind.toLowerCase();
      final dir = it.direction?.toLowerCase();
      final desc = it.descriptor?.toLowerCase();
      final shouldPlanMaster = _shouldPlanMasterForIntent(
        target: normGoal.target,
        kind: kind,
        strict: strict,
        referenceActive: referenceRow != null,
      );

      final rows = _rowsForIntent(
        project: project,
        resolvedTargets: effectiveTargets,
        target: normGoal.target,
      )
          .where((row) =>
              referenceRow == null || row.rowIndex != referenceRow.rowIndex)
          .toList(growable: false);

      if (kind == 'gain') {
        final up = dir == 'up';
        final down = dir == 'down';

        if (!up && !down) continue;

        for (final r in rows) {
          actions.addAll(_planSmartGain(project, r, ref,
              intensity: normGoal.intensity,
              up: up,
              strict: strict,
              policy: policy));
        }
        if (shouldPlanMaster) {
          actions.addAll(
            _planMasterGain(
              up: up,
              intensity: normGoal.intensity,
              policy: policy,
            ),
          );
        }
        continue;
      }

      if (kind == 'pan') {
        actions.addAll(
          _planPan(project, rows, dir ?? 'widen',
              intensity: normGoal.intensity,
              roleOverrides: roleOverrides,
              policy: policy),
        );
        if (shouldPlanMaster) {
          actions.addAll(_planMasterPan(
            dir ?? 'center',
            intensity: normGoal.intensity,
            policy: policy,
          ));
        }
        continue;
      }

      if (kind == 'reverb') {
        actions.addAll(
          _planReverb(
            rows,
            dir ?? 'up',
            intensity: normGoal.intensity,
            policy: policy,
          ),
        );
        if (shouldPlanMaster) {
          actions.addAll(_planMasterReverb(
            dir ?? 'up',
            intensity: normGoal.intensity,
            policy: policy,
          ));
        }
        continue;
      }

      if (kind == 'delay') {
        actions.addAll(_planDelay(
          project,
          rows,
          dir ?? 'up',
          intensity: normGoal.intensity,
          policy: policy,
        ));
        if (shouldPlanMaster) {
          actions.addAll(_planMasterDelay(
            project,
            dir ?? 'up',
            intensity: normGoal.intensity,
            policy: policy,
          ));
        }
        continue;
      }

      if (kind == 'eq' || kind == 'tone') {
        actions.addAll(
          _planEq(
            project,
            rows,
            desc,
            intensity: normGoal.intensity,
            roleOverrides: roleOverrides,
            strict: strict,
            notesOut: notes,
            policy: policy,
          ),
        );
        if (shouldPlanMaster) {
          actions.addAll(
            _planMasterEq(
              desc,
              intensity: normGoal.intensity,
              policy: policy,
            ),
          );
        }
        continue;
      }

      if (kind == 'deesser' || kind == 'de-esser') {
        actions.addAll(_planDeEsser(
          project,
          rows,
          dir ?? 'up',
          intensity: normGoal.intensity,
          notesOut: notes,
          policy: policy,
        ));
        if (shouldPlanMaster) {
          actions.addAll(_planMasterDeEsser(
            dir ?? 'up',
            intensity: normGoal.intensity,
            policy: policy,
          ));
        }
        continue;
      }

      if (kind == 'distortion') {
        actions.addAll(_planDistortion(
          rows,
          dir ?? 'up',
          intensity: normGoal.intensity,
          policy: policy,
        ));
        if (shouldPlanMaster) {
          actions.addAll(_planMasterDistortion(
            dir ?? 'up',
            intensity: normGoal.intensity,
            policy: policy,
          ));
        }
        continue;
      }

      if (kind == 'compressor') {
        actions.addAll(
          _planCompressor(
            project,
            rows,
            intensity: normGoal.intensity,
            roleOverrides: roleOverrides,
            strict: strict,
            notesOut: notes,
            policy: policy,
          ),
        );
        if (shouldPlanMaster) {
          actions.addAll(_planMasterCompressor(
              intensity: normGoal.intensity, strict: strict, policy: policy));
        }
        continue;
      }

      if (kind == 'limiter') {
        actions.addAll(_planLimiter(
          rows,
          dir ?? 'up',
          intensity: normGoal.intensity,
          policy: policy,
        ));
        if (shouldPlanMaster) {
          actions.addAll(_planMasterLimiter(
            dir ?? 'up',
            intensity: normGoal.intensity,
            policy: policy,
          ));
        }
        continue;
      }

      if (kind == 'clipper') {
        actions.addAll(_planClipper(
          rows,
          dir ?? 'up',
          intensity: normGoal.intensity,
          policy: policy,
        ));
        if (shouldPlanMaster) {
          actions.addAll(_planMasterClipper(
            dir ?? 'up',
            intensity: normGoal.intensity,
            policy: policy,
          ));
        }
        continue;
      }

      if (kind == 'balance') {
        if (referencePlanApplied) {
          continue;
        }
        if (!_isMasterTarget(normGoal.target)) {
          actions.addAll(_planBalance(
            project,
            ref,
            intensity: normGoal.intensity,
            policy: policy,
          ));
        }

        // interpretive extras
        if (!strict) {
          if (!_isMasterTarget(normGoal.target)) {
            actions.addAll(_planGlueCompression(project,
                intensity: policy.scaleIntensity(normGoal.intensity),
                roleOverrides: roleOverrides,
                policy: policy));
            actions.addAll(_planMaskingFixes(project,
                intensity: policy.scaleIntensity(normGoal.intensity),
                roleOverrides: roleOverrides));
            actions.addAll(_planVocalDominance(project,
                intensity: policy.scaleIntensity(normGoal.intensity),
                roleOverrides: roleOverrides));
            actions.addAll(_planBassVsKick(project,
                intensity: policy.scaleIntensity(normGoal.intensity),
                roleOverrides: roleOverrides));
            actions.addAll(_planHarshnessFixes(project,
                intensity: policy.scaleIntensity(normGoal.intensity),
                roleOverrides: roleOverrides));
          }
        }

        if (shouldPlanMaster) {
          actions.addAll(_planMasterFinishing(
              intensity: normGoal.intensity, strict: strict, policy: policy));
        }
        continue;
      }
    }

    if (!strict &&
        !policy.skipDisagreementGuard &&
        !_isMasterTarget(normGoal.target)) {
      for (final intent in resolvedIntents) {
        final targets = _excludeReferenceRow(
            _resolveTargets(project, normGoal.target, roleOverrides),
            referenceRow);
        final reason = _detectDisagreement(
            project: project, intent: intent, targets: targets, ref: ref);

        if (reason != null) {
          final label = _targetLabel(normGoal.target);

          return MixingResult(
            actions: const [],
            isNoOp: true,
            summary: disagreementMessage(reason, intent, label),
            // notes: const ["If you still want to push it stylistically, say so and I'll do it."],
          );
        }
      }
    }

    // if (merged.isEmpty) {
    //   return MixingResult(
    //     actions: const [],
    //     summary: "I don't think changing anything will help — it already looks balanced enough.",
    //     isNoOp: true,
    //     notes: notes,
    //   );
    // }
    final isGlobal = _isGlobalTarget(normGoal.target);

    final summary = isGlobal ? _summarizeGlobal(actions) : _summarize(actions);

    return MixingResult(
        actions: actions,
        summary: summary,
        isNoOp: actions.isEmpty,
        notes: notes);
  }

  // NOT USED YET (need to think about more later)
  MixingResult runStylePreset({
    required ProjectState project,
    required String style,
    List<Map<String, dynamic>>? targets,
  }) {
    switch (style) {
      case 'electronic':
        return _applyElectronicPreset(project, targets);
      case 'pop_rock_blues':
        return _applyPopRockBluesPreset(project, targets);
      case 'jazz':
        return _applyJazzPreset(project, targets);
      case 'indie_rock':
        return _applyIndieRockPreset(project, targets);
      default:
        return const MixingResult(
          actions: [],
          summary: 'Internal Error: Style not detected properly.',
          isNoOp: true,
        );
    }
  }

  List<MixAction> _applyEffectsToRow(
    int rowIndex,
    List<Map<String, dynamic>> effects,
  ) {
    final actions = <MixAction>[];

    for (final fx in effects) {
      final effectId = fx['effectId'] as String;
      final params = Map<String, dynamic>.from(fx['params'] as Map);

      // Ensure effect exists
      actions.add(
        MixAction('ensure_effect', {
          'row': rowIndex,
          'effect_name_contains': effectId,
        }),
      );

      // Set parameters (authoritative, non-delta)
      for (final entry in params.entries) {
        actions.add(
          MixAction('adjust_effect_param_by_name', {
            'row': rowIndex,
            'effect_name_contains': effectId,
            'param_name_contains_any': [entry.key],
            'mode': 'set',
            'value': entry.value,
            'skip_if_missing_effect': false,
          }),
        );
      }
    }

    return actions;
  }

  MixingResult _applyElectronicPreset(
    ProjectState project,
    List<Map<String, dynamic>>? targets,
  ) {
    final actions = <MixAction>[];

    for (final row in project.rows) {
      final target = targets?.firstWhere(
        (t) => t['row_index'] == row.rowIndex,
        orElse: () => {},
      );

      final role = target?['role'] ?? _topRole(row);

      if (role == 'drums') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -21.5,
              'Attack': 0.5,
              'Release': 15.0,
              'Ratio': 12.0,
              'Makeup': 2.9,
              'Mix': 100.0,
            }
          },
          {
            'effectId': 'Distortion',
            'params': {
              'Drive': 36.0,
              'Volume': -1.5,
              'Mix': 17.0,
              'Anger': 0.60,
              'HPF Frequency': 20.0,
              'LPF Frequency': 12476.0,
            }
          },
          {
            'effectId': 'EQ 3-Band',
            'params': {
              'Low Gain': 0.0,
              'Mid Gain': 0.0,
              'High Gain': -2.25,
            }
          }
        ]));
      }

      if (role == 'synth') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -15.0,
              'Attack': 5.5,
              'Release': 75.0,
              'Ratio': 4.0,
              'Mix': 100.0,
            }
          },
          {
            'effectId': 'EQ 3-Band',
            'params': {
              'Low Gain': -2.0,
              'Mid Gain': 0.0,
              'High Gain': -0.75,
            }
          }
        ]));
      }

      if (role == 'bass') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -17.0,
              'Attack': 17.4,
              'Release': 124.0,
              'Ratio': 8.0,
              'Mix': 100.0,
            }
          },
          {
            'effectId': 'Distortion',
            'params': {
              'Drive': 75.0,
              'Volume': -3.0,
              'Mix': 28.0,
              'Anger': 0.60,
              'HPF Frequency': 120.0,
              'LPF Frequency': 20000.0,
            }
          }
        ]));
      }
    }

    return MixingResult(
      actions: actions,
      summary: 'Applied Electronic style.',
      isNoOp: actions.isEmpty,
    );
  }

  MixingResult _applyPopRockBluesPreset(
    ProjectState project,
    List<Map<String, dynamic>>? targets,
  ) {
    final actions = <MixAction>[];

    for (final row in project.rows) {
      final target = targets?.firstWhere(
        (t) => t['row_index'] == row.rowIndex,
        orElse: () => {},
      );

      final role = target?['role'] ?? _topRole(row);

      if (role == 'drums') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -22.0,
              'Attack': 8.0,
              'Release': 110.0,
              'Ratio': 4.0,
              'Mix': 100.0,
            }
          }
        ]));
      }

      if (role == 'bass') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -20.0,
              'Attack': 18.0,
              'Release': 160.0,
              'Ratio': 3.5,
              'Mix': 100.0,
            }
          }
        ]));
      }

      if (role == 'guitar' || role == 'synth') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'EQ 3-Band',
            'params': {
              'Low Gain': -1.0,
              'Mid Gain': 1.5,
              'High Gain': 0.5,
            }
          }
        ]));
      }

      if (role == 'vocals') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -17.0,
              'Attack': 10.0,
              'Release': 120.0,
              'Ratio': 3.0,
              'Mix': 100.0,
            }
          }
        ]));
      }
    }

    return MixingResult(
      actions: actions,
      summary: 'Applied Pop Rock / Blues style.',
      isNoOp: actions.isEmpty,
    );
  }

  MixingResult _applyJazzPreset(
    ProjectState project,
    List<Map<String, dynamic>>? targets,
  ) {
    final actions = <MixAction>[];

    for (final row in project.rows) {
      final target = targets?.firstWhere(
        (t) => t['row_index'] == row.rowIndex,
        orElse: () => {},
      );

      final role = target?['role'] ?? _topRole(row);

      if (role == 'drums') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -27.0,
              'Attack': 20.0,
              'Release': 250.0,
              'Ratio': 3.0,
              'Mix': 100.0,
            }
          },
          {
            "effectId": "EQ 3-Band",
            "params": {"Low Gain": 1.0, "Mid Gain": -3.75, "High Gain": -4.5}
          }
        ]));
      }

      if (role == 'bass') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -22.0,
              'Attack': 30.0,
              'Release': 300.0,
              'Ratio': 2.5,
              'Mix': 100.0,
            }
          }
        ]));
      }

      if (role == 'vocals' || role == 'sax' || role == 'trumpet') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'EQ 3-Band',
            'params': {
              'Low Gain': -0.5,
              'Mid Gain': 1.0,
              'High Gain': 0.5,
            }
          }
        ]));
      }
    }

    return MixingResult(
      actions: actions,
      summary: 'Applied Jazz style.',
      isNoOp: actions.isEmpty,
    );
  }

  MixingResult _applyIndieRockPreset(
    ProjectState project,
    List<Map<String, dynamic>>? targets,
  ) {
    final actions = <MixAction>[];

    for (final row in project.rows) {
      final target = targets?.firstWhere(
        (t) => t['row_index'] == row.rowIndex,
        orElse: () => {},
      );

      final role = target?['role'] ?? _topRole(row);

      // DRUMS — punchy but not crushed
      if (role == 'drums') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -18.0,
              'Attack': 6.0,
              'Release': 90.0,
              'Ratio': 4.0,
              'Mix': 100.0,
            }
          },
          {
            'effectId': 'EQ 3-Band',
            'params': {
              'Low Gain': 1.5,
              'Mid Gain': 0.0,
              'High Gain': -1.5,
            }
          }
        ]));
      }

      // BASS — tight, slightly compressed
      if (role == 'bass') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -20.0,
              'Attack': 12.0,
              'Release': 140.0,
              'Ratio': 4.0,
              'Mix': 100.0,
            }
          },
          {
            'effectId': 'EQ 3-Band',
            'params': {
              'Low Gain': 1.0,
              'Mid Gain': -1.0,
              'High Gain': -2.0,
            }
          }
        ]));
      }

      // GUITARS — forward mids, controlled highs
      if (role == 'guitar') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -16.0,
              'Attack': 8.0,
              'Release': 120.0,
              'Ratio': 3.0,
              'Mix': 100.0,
            }
          },
          {
            'effectId': 'EQ 3-Band',
            'params': {
              'Low Gain': -1.5,
              'Mid Gain': 2.0,
              'High Gain': -1.0,
            }
          }
        ]));
      }

      // VOCALS / MAIN — natural but present
      if (role == 'vocals') {
        actions.addAll(_applyEffectsToRow(row.rowIndex, [
          {
            'effectId': 'Compressor',
            'params': {
              'Threshold': -15.0,
              'Attack': 5.0,
              'Release': 100.0,
              'Ratio': 3.5,
              'Mix': 100.0,
            }
          },
          {
            'effectId': 'EQ 3-Band',
            'params': {
              'Low Gain': -1.0,
              'Mid Gain': 1.5,
              'High Gain': 0.5,
            }
          }
        ]));
      }
    }

    return MixingResult(
      actions: actions,
      summary: 'Applied Indie Rock style.',
      isNoOp: actions.isEmpty,
    );
  }

  String _summarizeGlobal(List<MixAction> actions) {
    if (actions.isEmpty) return 'No global changes needed.';

    final kinds = actions.map((a) => a.type).toSet();

    if (kinds.length == 1 && kinds.contains('set_row_gain')) {
      return 'Adjusted overall levels for the mix.';
    }
    if (kinds.any(
        (k) => k.startsWith('set_master_') || k.contains('master_effect'))) {
      return 'Applied global mix and master-bus refinements.';
    }

    return 'Applied global mix adjustments.';
  }

  bool _isMasterTarget(MixTarget t) => t.scope == 'master';

  bool _isGlobalTarget(MixTarget t) {
    if (t.scope == 'master') return false;
    if (t.scope == 'row') return false;

    final role = t.role;
    final row = t.rowIndex;

    final roleUnset = role == null || role.trim().isEmpty || role == 'null';
    final rowUnset = row == null || row < 0;

    return roleUnset && rowUnset;
  }

  bool _shouldPlanMasterForIntent({
    required MixTarget target,
    required String kind,
    required bool strict,
    required bool referenceActive,
  }) {
    if (referenceActive) return false;
    if (target.scope == 'master') return true;
    if (target.scope == 'row') return false;
    if (!strict && kind == 'balance') return true;
    return false;
  }

  List<RowState> _rowsForIntent({
    required ProjectState project,
    required List<RowState> resolvedTargets,
    required MixTarget target,
  }) {
    if (_isMasterTarget(target)) {
      return const [];
    }

    if (resolvedTargets.isNotEmpty) {
      return resolvedTargets;
    }

    // ✅ GLOBAL FALLBACK
    if (_isGlobalTarget(target)) {
      return project.rows.where((r) => r.hasAudio).toList();
    }

    // ❌ Explicit but unresolved → handled elsewhere as no-op / clarification
    return const [];
  }

  RowState? _resolveReferenceRow(
    ProjectState project,
    MixReferenceTarget? referenceTarget,
  ) {
    final rowIndex = referenceTarget?.rowIndex;
    if (rowIndex == null || rowIndex < 0 || rowIndex >= project.rows.length) {
      return null;
    }
    return project.rows[rowIndex];
  }

  List<RowState> _excludeReferenceRow(
    List<RowState> rows,
    RowState? referenceRow,
  ) {
    if (referenceRow == null) return rows;
    return rows
        .where((row) => row.rowIndex != referenceRow.rowIndex)
        .toList(growable: false);
  }

  List<RowState> _rowsForReferenceMatch({
    required ProjectState project,
    required List<RowState> resolvedTargets,
    required MixTarget target,
    required RowState referenceRow,
  }) {
    final rows = _rowsForIntent(
      project: project,
      resolvedTargets: resolvedTargets,
      target: target,
    );
    return rows
        .where(
            (row) => row.rowIndex != referenceRow.rowIndex && _rowUsable(row))
        .toList(growable: false);
  }

  // -----------------------------
  // Targeting
  // -----------------------------
  bool _isExplicitTarget(MixTarget t) {
    if (t.scope == 'master' || t.scope == 'row' || t.scope == 'group') {
      return true;
    }
    final role = t.role;
    if (t.rowIndex != null) return true;
    if (role != null &&
        role.isNotEmpty &&
        role != 'null' &&
        t.confidence >= 0.45) {
      return true;
    }
    return false;
  }

  String _canonicalTargetRole(String raw) {
    final role =
        raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    switch (role) {
      case 'vocal':
      case 'voice':
      case 'lead_vocal':
      case 'lead_vocals':
      case 'singer':
      case 'rap':
        return 'vocals';
      case 'drum':
      case 'kit':
      case 'percussion':
      case 'perc':
      case 'beat':
        return 'drums';
      case 'sub':
      case 'sub_bass':
      case '808':
        return 'bass';
      case 'gtr':
      case 'acoustic_guitar':
      case 'electric_guitar':
        return 'guitar';
      case 'keys':
      case 'keyboard':
      case 'piano':
      case 'pad':
      case 'lead':
      case 'arp':
        return 'synth';
      default:
        return role.replaceAll('_', ' ');
    }
  }

  List<String> _roleTextAliases(String role) {
    switch (_canonicalTargetRole(role)) {
      case 'vocals':
        return const [
          'vocal',
          'vocals',
          'vox',
          'lead vocal',
          'voice',
          'singer',
          'singing',
          'rap',
          'rapper',
        ];
      case 'drums':
        return const [
          'drum',
          'drums',
          'kit',
          'kick',
          'snare',
          'hat',
          'hihat',
          'hi hat',
          'percussion',
          'perc',
          'beat',
        ];
      case 'bass':
        return const ['bass', 'sub', 'sub bass', '808'];
      case 'guitar':
        return const [
          'guitar',
          'gtr',
          'acoustic',
          'electric guitar',
          'strum',
        ];
      case 'synth':
        return const [
          'synth',
          'pad',
          'lead',
          'keys',
          'keyboard',
          'piano',
          'organ',
          'pluck',
          'arp',
        ];
      default:
        return <String>[_canonicalTargetRole(role)];
    }
  }

  String _normalizedTargetText(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _targetTextContainsAlias(String haystack, String alias) {
    final normalizedAlias = _normalizedTargetText(alias);
    if (normalizedAlias.isEmpty || haystack.isEmpty) return false;
    final pattern = '(^| )${RegExp.escape(normalizedAlias)}( |${r'$'})';
    return RegExp(pattern).hasMatch(haystack);
  }

  int _rowTextRoleScore(RowState row, String role) {
    final canonicalRole = _canonicalTargetRole(role);
    if (row.roleOverride == canonicalRole) return 1000;

    final aliases = _roleTextAliases(canonicalRole);
    final rowText = _normalizedTargetText(
      '${row.rowName} ${row.instrumentName} ${row.instrumentId}',
    );
    final clipText = _normalizedTargetText(
      row.clips
          .map((clip) => clip.fileName ?? '')
          .where((name) => name.trim().isNotEmpty)
          .join(' '),
    );

    var score = 0;
    for (final alias in aliases) {
      if (_targetTextContainsAlias(rowText, alias)) score += 8;
      if (_targetTextContainsAlias(clipText, alias)) score += 4;
    }
    return score;
  }

  bool _rowClassifierMatchesRole(RowState row, String role) {
    if (!_rowUsable(row)) return false;
    if (row.roleConsistency < 0.65) return false;
    final canonicalRole = _canonicalTargetRole(role);
    final probability = row.roleProbs[canonicalRole] ?? 0.0;
    final topRole = _canonicalTargetRole(_topRole(row));
    final interpretationTop = _canonicalTargetRole(row.interpretation.topRole);
    final classifierConfidence = row.interpretation.classificationConfidence;
    final margin = row.interpretation.topRoleMargin;

    if (probability >= 0.45) return true;
    return probability >= 0.30 &&
        topRole == canonicalRole &&
        interpretationTop == canonicalRole &&
        classifierConfidence >= 0.35 &&
        margin >= 0.08;
  }

  List<RowState> _resolveTargets(
      ProjectState p, MixTarget target, Map<int, String> roleOverrides) {
    if (target.scope == 'group') {
      final tokenId = (target.groupId ?? '').trim().toLowerCase();
      final tokenName =
          (target.groupName ?? target.role ?? '').trim().toLowerCase();
      TrackGroup? matchedGroup;
      for (final group in p.trackGroups) {
        final id = group.id.trim().toLowerCase();
        final name = group.name.trim().toLowerCase();
        if ((tokenId.isNotEmpty && id == tokenId) ||
            (tokenName.isNotEmpty &&
                (name == tokenName ||
                    name.contains(tokenName) ||
                    (name.isNotEmpty && tokenName.contains(name))))) {
          matchedGroup = group;
          break;
        }
      }
      if (matchedGroup == null && target.rowIndex != null) {
        final rowIndex = target.rowIndex!;
        if (rowIndex >= 0 && rowIndex < p.rows.length) {
          final rowGroupId = p.rows[rowIndex].groupId.trim();
          for (final group in p.trackGroups) {
            if (group.id == rowGroupId) {
              matchedGroup = group;
              break;
            }
          }
        }
      }
      if (matchedGroup != null) {
        final memberIds = matchedGroup.rowIds.toSet();
        return p.rows
            .where((row) =>
                memberIds.contains(row.rowId) ||
                row.groupId == matchedGroup!.id)
            .toList(growable: false);
      }
    }

    if (target.role == null && target.rowIndex == null) {
      return const [];
    }

    if (target.rowIndex != null) {
      final i = target.rowIndex!;
      if (i >= 0 && i < p.rows.length) return [p.rows[i]];
    }

    final role = target.role == null
        ? null
        : _canonicalTargetRole(target.role!.toLowerCase());
    if (role != null && role.isNotEmpty) {
      final overrideRows = p.rows.where((r) {
        final ov = roleOverrides[r.rowIndex];
        return ov != null && _canonicalTargetRole(ov) == role;
      }).toList();
      if (overrideRows.isNotEmpty) return overrideRows;

      final scoredTextRows = <({RowState row, int score})>[];
      for (final row in p.rows) {
        if (!_rowUsable(row)) continue;
        final score = _rowTextRoleScore(row, role);
        if (score > 0) scoredTextRows.add((row: row, score: score));
      }
      if (scoredTextRows.isNotEmpty) {
        scoredTextRows.sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          if (byScore != 0) return byScore;
          return a.row.rowIndex.compareTo(b.row.rowIndex);
        });
        final topScore = scoredTextRows.first.score;
        return scoredTextRows
            .where((entry) => entry.score == topScore)
            .map((entry) => entry.row)
            .toList(growable: false);
      }

      final rows = p.rows
          .where((r) => _rowClassifierMatchesRole(r, role))
          .toList(growable: false);
      if (rows.isNotEmpty) return rows;
    }

    return const [];
  }

  List<RowState> _rowsForRole(
      ProjectState p, String role, Map<int, String> roleOverrides) {
    final canonicalRole = _canonicalTargetRole(role);
    final overrideRows = p.rows.where((r) {
      if (!_rowUsable(r)) return false;
      final ov = roleOverrides[r.rowIndex];
      return ov != null && _canonicalTargetRole(ov) == canonicalRole;
    }).toList(growable: false);
    if (overrideRows.isNotEmpty) return overrideRows;

    final textRows = p.rows.where((r) {
      if (!_rowUsable(r)) return false;
      return _rowTextRoleScore(r, canonicalRole) > 0;
    }).toList(growable: false);
    if (textRows.isNotEmpty) return textRows;

    return p.rows.where((r) {
      return _rowClassifierMatchesRole(r, canonicalRole);
    }).toList(growable: false);
  }

  // -----------------------------
  // Mix reference + effective loudness
  // -----------------------------
  _MixRef _mixReference(ProjectState p) {
    final eff = <double>[];
    for (final r in p.rows) {
      if (r.approxRms <= 0.001) continue;
      if (!_rowUsable(r)) continue;
      eff.add(_effRms(r));
    }
    eff.sort();
    if (eff.isEmpty) return const _MixRef(medianEffRms: 0.1);
    final mid = eff.length ~/ 2;
    final median =
        eff.length.isOdd ? eff[mid] : (eff[mid - 1] + eff[mid]) * 0.5;
    return _MixRef(medianEffRms: median.clamp(0.02, 10.0));
  }

  double _gainLin(RowState r) {
    final db = _sliderToDb(r.gain0to3);
    return math.pow(10.0, db / 20.0).toDouble();
  }

  double _effRms(RowState r) => r.approxRms * _gainLin(r);
  double _effPeak(RowState r) => (r.approxRms * r.approxCrest) * _gainLin(r);

  // -----------------------------
  // Safety: headroom protection
  // -----------------------------
  List<MixAction> _planHeadroomSafety(ProjectState p,
      {required double intensity, required List<RowState> limitTo}) {
    final out = <MixAction>[];
    for (final r in limitTo) {
      final pk = _effPeak(r);
      if (pk <= 0.98) continue;

      // bring peak down toward ~0.90
      final ratio = 0.90 / (pk + 1e-6);
      final db = 20.0 * (math.log(ratio) / math.log(10)); // negative
      final dbDelta = (db * (0.8 + 0.2 * intensity)).clamp(-4.0, -1.2);
      out.addAll(_gainDbDelta(r, dbDelta));
    }
    return out;
  }

  // -----------------------------
  // Gain planning (masking-aware)
  // -----------------------------
  List<MixAction> _planSmartGain(
    ProjectState p,
    RowState target,
    _MixRef ref, {
    required double intensity,
    required bool up,
    required bool strict,
    required _MixExecutionPolicy policy,
  }) {
    final out = <MixAction>[];
    final effectiveIntensity = policy.scaleIntensity(intensity);
    final median = ref.medianEffRms;
    final eff = _effRms(target);
    final alreadyForward = eff > median * 1.35;
    final nearClip = _effPeak(target) > 0.98;

    if (!strict && up && (alreadyForward || nearClip)) {
      // Interpretive: reduce overlapping competitors first, then small lift
      final comps = _topOverlapCompetitors(p, target.rowIndex, maxCount: 2);
      int cut = 0;
      for (final c in comps) {
        if (cut >= 2) break;
        if (_effRms(c) > median * 1.10) {
          out.addAll(
              _gainDbDelta(c, (-2.5 * effectiveIntensity).clamp(-5.5, -1.2)));
          cut++;
        }
      }
      final targetFloor = policy.audibleFloor(
        subtle: 0.8,
        noticeable: 1.4,
        obvious: 2.1,
        extreme: 3.0,
      );
      out.addAll(_gainDbDelta(
          target, (1.6 * effectiveIntensity).clamp(targetFloor, 4.6)));
      return out;
    }

    // Direct: more obvious moves
    final sev = _severityMultiplier(target, ref);
    final rawDb = 6.8 * effectiveIntensity * sev;
    final upFloor = policy.audibleFloor(
      subtle: 1.0,
      noticeable: 1.5,
      obvious: 2.4,
      extreme: 3.4,
    );
    final downFloor = policy.audibleFloor(
      subtle: -1.0,
      noticeable: -1.5,
      obvious: -2.4,
      extreme: -3.4,
    );
    final maxUp =
        policy.executionProfile == MixExecutionProfile.experimentalExtreme
            ? 6.0
            : (policy.executionProfile == MixExecutionProfile.creativeBold
                ? 4.8
                : 4.0);
    final maxDown =
        policy.executionProfile == MixExecutionProfile.experimentalExtreme
            ? -6.0
            : (policy.executionProfile == MixExecutionProfile.creativeBold
                ? -4.8
                : -4.0);

    final dbDelta =
        up ? rawDb.clamp(upFloor, maxUp) : (-rawDb).clamp(maxDown, downFloor);
    out.addAll(_gainDbDelta(target, dbDelta));
    return out;
  }

  double _severityMultiplier(RowState r, _MixRef ref) {
    final eff = _effRms(r);
    final median = ref.medianEffRms;

    if (eff < median * 0.45) return 1.6; // very quiet
    if (eff < median * 0.65) return 1.3;
    if (eff < median * 0.85) return 1.15;

    if (eff > median * 2.0) return 1.3; // very loud
    if (eff > median * 1.5) return 1.15;

    return 1.0;
  }

  List<RowState> _topOverlapCompetitors(ProjectState p, int rowIndex,
      {required int maxCount}) {
    final out = <RowState>[];
    for (final r in p.rows) {
      if (r.rowIndex == rowIndex) continue;
      if (p.overlapMatrix[rowIndex][r.rowIndex] == 1 && r.approxRms > 0.001)
        out.add(r);
    }
    out.sort((a, b) => _effRms(b).compareTo(_effRms(a)));
    return out.take(maxCount).toList();
  }

  // List<MixAction> _gainDbDelta(RowState r, double dbDelta) {
  //   final oldSlider = r.gain0to3.clamp(0.0, 3.0);
  //   final oldDb = _sliderToDb(oldSlider);
  //   final baseDb = oldDb.isFinite ? oldDb : -36.0;

  //   final newDb = (baseDb + dbDelta).clamp(-36.0, 18.0);
  //   final newSlider = _dbToSlider(newDb);
  //   final deltaSlider = newSlider - oldSlider;
  //   if (deltaSlider.abs() < 0.01) return const [];

  //   return [
  //     MixAction('set_row_gain', {'row': r.rowIndex, 'delta': deltaSlider}),
  //   ];
  // }

  List<MixAction> _gainDbDelta(RowState r, double dbDelta) {
    final oldSlider = r.gain0to3.clamp(0.0, 3.0);
    final oldDb = _sliderToDb(oldSlider);

    final baseDb = oldDb.isFinite ? oldDb : _kGainDbMin;

    // Target db after delta
    final targetDb = (baseDb + dbDelta).clamp(
      _kGainDbMin,
      _kGainDbMax,
    );

    // HARD STOP: no more movement possible
    if ((targetDb - baseDb).abs() < 0.25) {
      return const [];
    }

    final newSlider = _dbToSlider(targetDb);
    final deltaSlider = newSlider - oldSlider;

    // Prevent micro-noise & runaway
    if (!deltaSlider.isFinite || deltaSlider.abs() < 0.01) {
      return const [];
    }

    return [
      MixAction('set_row_gain', {
        'row': r.rowIndex,
        'delta': deltaSlider,
      }),
    ];
  }

  double _sliderToDb(double s) {
    final clamped = s.clamp(_kGainUiMin, _kGainUiMax).toDouble();
    if (clamped <= _kGainUiUnity) {
      final t = ((clamped - _kGainUiMin) / (_kGainUiUnity - _kGainUiMin))
          .clamp(0.0, 1.0);
      return _kGainDbMin + ((0.0 - _kGainDbMin) * t);
    }
    final t = ((clamped - _kGainUiUnity) / (_kGainUiMax - _kGainUiUnity))
        .clamp(0.0, 1.0);
    return _kGainDbMax * t;
  }

  double _dbToSlider(double db) {
    if (!db.isFinite) return _kGainUiMin;
    final clampedDb = db.clamp(_kGainDbMin, _kGainDbMax).toDouble();
    if (clampedDb <= 0.0) {
      final t =
          ((clampedDb - _kGainDbMin) / (0.0 - _kGainDbMin)).clamp(0.0, 1.0);
      return _kGainUiMin + ((_kGainUiUnity - _kGainUiMin) * t);
    }
    final t = (clampedDb / _kGainDbMax).clamp(0.0, 1.0);
    return _kGainUiUnity + ((_kGainUiMax - _kGainUiUnity) * t);
  }

  // -----------------------------
  // Pan planning (delta only)
  // -----------------------------
  List<MixAction> _planPan(
    ProjectState p,
    List<RowState> rows,
    String direction, {
    required double intensity,
    required Map<int, String> roleOverrides,
    required _MixExecutionPolicy policy,
  }) {
    final out = <MixAction>[];
    final effectiveIntensity = policy.scaleIntensity(intensity);

    bool isAnchor(RowState r) {
      final role = roleOverrides[r.rowIndex] ?? _topRole(r);
      return role == 'vocals' || role == 'bass' || role == 'drums';
    }

    double targetForDirection(RowState r) {
      final amt = (0.18 * (0.5 + 0.5 * effectiveIntensity)).clamp(
        policy.audibleFloor(
          subtle: 0.06,
          noticeable: 0.10,
          obvious: 0.16,
          extreme: 0.22,
        ),
        policy.executionProfile == MixExecutionProfile.experimentalExtreme
            ? 0.36
            : (policy.executionProfile == MixExecutionProfile.creativeBold
                ? 0.28
                : 0.20),
      );

      if (direction == 'center') return r.pan0To1 * 0.2;
      if (direction == 'left') return -amt;
      if (direction == 'right') return amt;
      return 0.0;
    }

    if (direction == 'left' || direction == 'right' || direction == 'center') {
      for (final r in rows) {
        if (isAnchor(r)) continue;
        final current = r.pan0To1.clamp(0.0, 1.0);
        final target = targetForDirection(r);
        final delta = target - current;
        if (delta.abs() <
            policy.audibleFloor(
              subtle: 0.04,
              noticeable: 0.05,
              obvious: 0.08,
              extreme: 0.12,
            )) {
          continue;
        }
        out.add(MixAction('set_row_pan',
            {'row': r.rowIndex, 'delta': delta.clamp(-0.22, 0.22)}));
      }
      return out;
    }

    if (direction == 'narrow') {
      for (final r in rows) {
        final current = r.pan0To1.clamp(0, 1.0);
        final target = current *
            (0.5 -
                (0.35 * effectiveIntensity).clamp(
                  policy.audibleFloor(
                    subtle: 0.06,
                    noticeable: 0.10,
                    obvious: 0.16,
                    extreme: 0.24,
                  ),
                  0.28,
                ));

        final delta = target - current;
        if (delta.abs() < 0.03) continue;
        out.add(MixAction('set_row_pan', {'row': r.rowIndex, 'delta': delta}));
      }
      return out;
    }

    // widen: spread up to 2 loud non-anchor rows
    final widenPool = rows.isNotEmpty ? rows : p.rows;
    final candidates = widenPool
        .where((r) => !isAnchor(r) && r.approxRms > 0.001)
        .toList()
      ..sort((a, b) => _effRms(b).compareTo(_effRms(a)));
    final chosen = candidates.take(2).toList();
    if (chosen.isEmpty) return out;
    final amt = (0.28 * (0.5 + 0.5 * effectiveIntensity)).clamp(
      policy.audibleFloor(
        subtle: 0.12,
        noticeable: 0.16,
        obvious: 0.24,
        extreme: 0.32,
      ),
      policy.executionProfile == MixExecutionProfile.experimentalExtreme
          ? 0.44
          : 0.32,
    );

    if (chosen.length == 1) {
      final r = chosen[0];
      final delta = (-amt) - r.pan0To1;
      out.add(MixAction('set_row_pan', {'row': r.rowIndex, 'delta': delta}));
    } else {
      final a = chosen[0];
      final b = chosen[1];
      out.add(MixAction(
          'set_row_pan', {'row': a.rowIndex, 'delta': (-amt) - a.pan0To1}));
      out.add(MixAction(
          'set_row_pan', {'row': b.rowIndex, 'delta': (amt) - b.pan0To1}));
    }
    return out;
  }

  // -----------------------------
  // FX planning (UI-bounded param matching)
  // -----------------------------
  List<MixAction> _planReverb(List<RowState> rows, String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final out = <MixAction>[];
    final dir = direction.toLowerCase();
    final effectiveIntensity = policy.scaleIntensity(intensity);

    if (dir == 'remove' || dir == 'down') {
      if (dir == 'remove') {
        for (final r in rows) {
          out.add(MixAction('delete_effect',
              {'row': r.rowIndex, 'effect_name_contains': fxReverb}));
        }
        return out;
      }
    }

    for (final r in rows) {
      out.add(MixAction('ensure_effect',
          {'row': r.rowIndex, 'effect_name_contains': fxReverb}));
      final sign = (dir == 'down') ? -1.0 : 1.0;

      // Mix
      final pMix = ['Mix'];
      if (_isAllowedFxParam(fxReverb, pMix)) {
        out.add(
          MixAction('adjust_effect_param_by_name', {
            'row': r.rowIndex,
            'effect_name_contains': fxReverb,
            'param_name_contains_any': pMix,
            'mode': 'delta',
            'delta_norm': sign *
                (0.10 * effectiveIntensity).clamp(
                  policy.audibleFloor(
                    subtle: 0.03,
                    noticeable: 0.05,
                    obvious: 0.10,
                    extreme: 0.16,
                  ),
                  policy.executionProfile ==
                          MixExecutionProfile.experimentalExtreme
                      ? 0.30
                      : (policy.executionProfile ==
                              MixExecutionProfile.creativeBold
                          ? 0.22
                          : 0.18),
                ),
            'clamp_0_1': true,
          }),
        );
      }

      // Room size
      final pRoom = ['Room Size', 'Room', 'Size'];
      if (_isAllowedFxParam(fxReverb, pRoom)) {
        out.add(
          MixAction('adjust_effect_param_by_name', {
            'row': r.rowIndex,
            'effect_name_contains': fxReverb,
            'param_name_contains_any': pRoom,
            'mode': 'delta',
            'delta_norm': sign *
                (0.07 * effectiveIntensity).clamp(
                  policy.audibleFloor(
                    subtle: 0.02,
                    noticeable: 0.04,
                    obvious: 0.07,
                    extreme: 0.12,
                  ),
                  policy.executionProfile ==
                          MixExecutionProfile.experimentalExtreme
                      ? 0.20
                      : (policy.executionProfile ==
                              MixExecutionProfile.creativeBold
                          ? 0.15
                          : 0.12),
                ),
            'clamp_0_1': true,
            'skip_if_missing_effect': false,
          }),
        );
      }
    }
    return out;
  }

  List<MixAction> _planDelay(
      ProjectState p, List<RowState> rows, String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final out = <MixAction>[];
    final dir = direction.toLowerCase();
    final effectiveIntensity = policy.scaleIntensity(intensity);

    if (dir == 'remove') {
      for (final r in rows) {
        out.add(MixAction('delete_effect',
            {'row': r.rowIndex, 'effect_name_contains': fxDelay}));
      }
      return out;
    }

    final sign = (dir == 'down') ? -1.0 : 1.0;

    final bpm = p.bpm <= 1 ? 120.0 : p.bpm;
    final eighthMs = 60000.0 / bpm / 2.0;
    final quarterMs = 60000.0 / bpm;
    final timeMs = policy.prefersLongDelay ? quarterMs : eighthMs;

    for (final r in rows) {
      out.add(MixAction('ensure_effect',
          {'row': r.rowIndex, 'effect_name_contains': fxDelay}));

      final pMix = ['Mix'];
      if (_isAllowedFxParam(fxDelay, pMix)) {
        out.add(
          MixAction('adjust_effect_param_by_name', {
            'row': r.rowIndex,
            'effect_name_contains': fxDelay,
            'param_name_contains_any': pMix,
            'mode': 'delta',
            'delta_norm': sign *
                (0.08 * effectiveIntensity).clamp(
                  policy.audibleFloor(
                    subtle: 0.02,
                    noticeable: 0.04,
                    obvious: 0.08,
                    extreme: 0.12,
                  ),
                  0.14,
                ),
            'clamp_0_1': true,
          }),
        );
      }

      final pFb = ['Feedback'];
      if (_isAllowedFxParam(fxDelay, pFb)) {
        out.add(
          MixAction('adjust_effect_param_by_name', {
            'row': r.rowIndex,
            'effect_name_contains': fxDelay,
            'param_name_contains_any': pFb,
            'mode': 'delta',
            'delta_norm': sign *
                (0.06 * effectiveIntensity).clamp(
                  policy.audibleFloor(
                    subtle: 0.02,
                    noticeable: 0.03,
                    obvious: 0.06,
                    extreme: 0.10,
                  ),
                  0.14,
                ),
            'clamp_0_1': true,
          }),
        );
      }

      final pTime = ['Delay Time', 'Time'];
      if (_isAllowedFxParam(fxDelay, pTime)) {
        out.add(
          MixAction('adjust_effect_param_by_name', {
            'row': r.rowIndex,
            'effect_name_contains': fxDelay,
            'param_name_contains_any': pTime,
            'mode': 'set',
            'value': timeMs,
            'skip_if_missing_effect': false,
          }),
        );
      }
    }

    return out;
  }

  List<MixAction> _planLimiter(List<RowState> rows, String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final out = <MixAction>[];
    final dir = direction.toLowerCase();

    if (dir == 'remove') {
      for (final r in rows) {
        out.add(MixAction('delete_effect',
            {'row': r.rowIndex, 'effect_name_contains': fxLimiter}));
      }
      return out;
    }

    final scale = policy.blend(intensity, floor: 0.35, ceiling: 1.0);
    final thresholdDelta =
        ((dir == 'down') ? 1.0 : -1.0) * (6.0 * scale).clamp(1.4, 7.5);
    final releaseMs = (dir == 'down')
        ? _lerp(90.0, 170.0, intensity)
        : _lerp(100.0, 35.0, intensity);
    final ceilingDb = (dir == 'down')
        ? -0.2
        : (-0.8 - 0.6 * policy.scaleIntensity(intensity));

    for (final r in rows) {
      out.add(MixAction('ensure_effect',
          {'row': r.rowIndex, 'effect_name_contains': fxLimiter}));

      if (_isAllowedFxParam(fxLimiter, const ['Threshold'])) {
        out.add(MixAction('adjust_effect_param_by_name', {
          'row': r.rowIndex,
          'effect_name_contains': fxLimiter,
          'param_name_contains_any': const ['Threshold'],
          'mode': 'delta',
          'delta': thresholdDelta,
          'clamp_min': -40.0,
          'clamp_max': 0.0,
          'skip_if_missing_effect': false,
        }));
      }

      if (_isAllowedFxParam(fxLimiter, const ['Release'])) {
        out.add(MixAction('adjust_effect_param_by_name', {
          'row': r.rowIndex,
          'effect_name_contains': fxLimiter,
          'param_name_contains_any': const ['Release'],
          'mode': 'set',
          'value': releaseMs.clamp(0.1, 200.0),
          'skip_if_missing_effect': false,
        }));
      }

      if (_isAllowedFxParam(fxLimiter, const ['Ceiling'])) {
        out.add(MixAction('adjust_effect_param_by_name', {
          'row': r.rowIndex,
          'effect_name_contains': fxLimiter,
          'param_name_contains_any': const ['Ceiling'],
          'mode': 'set',
          'value': ceilingDb.clamp(-40.0, 0.0),
          'skip_if_missing_effect': false,
        }));
      }
    }

    return out;
  }

  List<MixAction> _planClipper(List<RowState> rows, String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final out = <MixAction>[];
    final dir = direction.toLowerCase();

    if (dir == 'remove') {
      for (final r in rows) {
        out.add(MixAction('delete_effect',
            {'row': r.rowIndex, 'effect_name_contains': fxClipper}));
      }
      return out;
    }

    final scale = policy.blend(intensity, floor: 0.35, ceiling: 1.0);
    final thresholdDelta =
        ((dir == 'down') ? 1.0 : -1.0) * (5.0 * scale).clamp(1.2, 6.8);
    final ceilingDb = (dir == 'down')
        ? -0.1
        : (-0.6 - 0.8 * policy.scaleIntensity(intensity));

    for (final r in rows) {
      out.add(MixAction('ensure_effect',
          {'row': r.rowIndex, 'effect_name_contains': fxClipper}));

      if (_isAllowedFxParam(fxClipper, const ['Threshold'])) {
        out.add(MixAction('adjust_effect_param_by_name', {
          'row': r.rowIndex,
          'effect_name_contains': fxClipper,
          'param_name_contains_any': const ['Threshold'],
          'mode': 'delta',
          'delta': thresholdDelta,
          'clamp_min': -40.0,
          'clamp_max': 0.0,
          'skip_if_missing_effect': true,
        }));
      }

      if (_isAllowedFxParam(fxClipper, const ['Ceiling'])) {
        out.add(MixAction('adjust_effect_param_by_name', {
          'row': r.rowIndex,
          'effect_name_contains': fxClipper,
          'param_name_contains_any': const ['Ceiling'],
          'mode': 'set',
          'value': ceilingDb.clamp(-40.0, 0.0),
          'skip_if_missing_effect': true,
        }));
      }
    }

    return out;
  }

  List<MixAction> _planMasterGain(
      {required bool up,
      required double intensity,
      required _MixExecutionPolicy policy}) {
    final effectiveIntensity = policy.scaleIntensity(intensity);
    final mag = (0.04 + 0.10 * effectiveIntensity).clamp(
      policy.audibleFloor(
        subtle: 0.02,
        noticeable: 0.04,
        obvious: 0.08,
        extreme: 0.12,
      ),
      policy.executionProfile == MixExecutionProfile.experimentalExtreme
          ? 0.24
          : 0.16,
    );
    return [
      MixAction('set_master_gain', {
        'mode': 'delta',
        'delta': up ? mag : -mag,
      }),
    ];
  }

  List<MixAction> _planMasterPan(String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final dir = direction.toLowerCase();
    if (dir == 'center') {
      return [
        MixAction('set_master_pan', {'mode': 'set', 'value': 0.5}),
      ];
    }
    if (dir == 'left' || dir == 'right') {
      final mag = (0.03 + 0.06 * policy.scaleIntensity(intensity)).clamp(
        policy.audibleFloor(
          subtle: 0.02,
          noticeable: 0.03,
          obvious: 0.06,
          extreme: 0.10,
        ),
        policy.executionProfile == MixExecutionProfile.experimentalExtreme
            ? 0.16
            : 0.10,
      );
      return [
        MixAction('set_master_pan',
            {'mode': 'delta', 'delta': dir == 'left' ? -mag : mag}),
      ];
    }
    return const [];
  }

  List<MixAction> _planMasterReverb(String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final out = <MixAction>[];
    final dir = direction.toLowerCase();
    final effectiveIntensity = policy.scaleIntensity(intensity);
    if (dir == 'remove') {
      return [
        MixAction('delete_master_effect', {'effect_name_contains': fxReverb})
      ];
    }

    final sign = (dir == 'down') ? -1.0 : 1.0;
    out.add(
        MixAction('ensure_master_effect', {'effect_name_contains': fxReverb}));

    out.add(MixAction('adjust_master_effect_param_by_name', {
      'effect_name_contains': fxReverb,
      'param_name_contains_any': const ['Mix'],
      'mode': 'delta',
      'delta_norm': sign *
          (0.04 * effectiveIntensity).clamp(
            policy.audibleFloor(
              subtle: 0.01,
              noticeable: 0.02,
              obvious: 0.05,
              extreme: 0.08,
            ),
            0.10,
          ),
      'clamp_0_1': true,
      'skip_if_missing_effect': false,
    }));
    out.add(MixAction('adjust_master_effect_param_by_name', {
      'effect_name_contains': fxReverb,
      'param_name_contains_any': const ['Room Size', 'Room', 'Size'],
      'mode': 'delta',
      'delta_norm': sign *
          (0.02 * effectiveIntensity).clamp(
            policy.audibleFloor(
              subtle: 0.005,
              noticeable: 0.01,
              obvious: 0.025,
              extreme: 0.04,
            ),
            0.06,
          ),
      'clamp_0_1': true,
      'skip_if_missing_effect': true,
    }));
    return out;
  }

  List<MixAction> _planMasterDelay(ProjectState p, String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final out = <MixAction>[];
    final dir = direction.toLowerCase();
    final effectiveIntensity = policy.scaleIntensity(intensity);
    if (dir == 'remove') {
      return [
        MixAction('delete_master_effect', {'effect_name_contains': fxDelay})
      ];
    }

    final sign = (dir == 'down') ? -1.0 : 1.0;
    final bpm = p.bpm <= 1 ? 120.0 : p.bpm;
    final eighthMs = 60000.0 / bpm / 2.0;
    final quarterMs = 60000.0 / bpm;
    final timeMs = policy.prefersLongDelay ? quarterMs : eighthMs;

    out.add(
        MixAction('ensure_master_effect', {'effect_name_contains': fxDelay}));
    out.add(MixAction('adjust_master_effect_param_by_name', {
      'effect_name_contains': fxDelay,
      'param_name_contains_any': const ['Mix'],
      'mode': 'delta',
      'delta_norm': sign *
          (0.03 * effectiveIntensity).clamp(
            policy.audibleFloor(
              subtle: 0.01,
              noticeable: 0.02,
              obvious: 0.04,
              extreme: 0.07,
            ),
            0.09,
          ),
      'clamp_0_1': true,
      'skip_if_missing_effect': true,
    }));
    out.add(MixAction('adjust_master_effect_param_by_name', {
      'effect_name_contains': fxDelay,
      'param_name_contains_any': const ['Feedback'],
      'mode': 'delta',
      'delta_norm': sign *
          (0.02 * effectiveIntensity).clamp(
            policy.audibleFloor(
              subtle: 0.005,
              noticeable: 0.01,
              obvious: 0.02,
              extreme: 0.04,
            ),
            0.06,
          ),
      'clamp_0_1': true,
      'skip_if_missing_effect': true,
    }));
    out.add(MixAction('adjust_master_effect_param_by_name', {
      'effect_name_contains': fxDelay,
      'param_name_contains_any': const ['Delay Time', 'Time'],
      'mode': 'set',
      'value': timeMs,
      'skip_if_missing_effect': true,
    }));
    return out;
  }

  List<MixAction> _planMasterEq(String? descriptor,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final out = <MixAction>[];
    final d = descriptor?.toLowerCase().trim();

    out.add(MixAction(
        'ensure_master_effect', {'effect_name_contains': fxEqParametric}));

    void addMasterEq(List<String> paramAny,
        {required String mode,
        double? delta,
        double? deltaNorm,
        double? value}) {
      out.add(MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxEqParametric,
        'param_name_contains_any': paramAny,
        'mode': mode,
        if (delta != null) 'delta': delta,
        if (deltaNorm != null) 'delta_norm': deltaNorm,
        if (value != null) 'value': value,
        'skip_if_missing_effect': true,
      }));
    }

    final amt = policy.blend(intensity, floor: 0.35, ceiling: 1.0);

    switch (d) {
      case 'mud_cut':
      case 'box_cut':
        addMasterEq(const ['Band 2 Gain'],
            mode: 'delta', delta: (-2.2 * amt).clamp(-3.5, -0.8));
        addMasterEq(const ['Band 2 Frequency'], mode: 'set', value: 350.0);
        addMasterEq(const ['Band 2 Q'], mode: 'set', value: 1.2);
        break;
      case 'boom_cut':
        addMasterEq(const ['Band 1 Gain'],
            mode: 'delta', delta: (-2.0 * amt).clamp(-3.2, -0.8));
        addMasterEq(const ['Band 1 Frequency'], mode: 'set', value: 120.0);
        addMasterEq(const ['Band 1 Q'], mode: 'set', value: 1.3);
        break;
      case 'harsh_cut':
        addMasterEq(const ['Band 3 Gain'],
            mode: 'delta', delta: (-1.8 * amt).clamp(-3.0, -0.6));
        addMasterEq(const ['Band 4 Gain'],
            mode: 'delta', delta: (-1.2 * amt).clamp(-2.2, -0.4));
        addMasterEq(const ['Band 3 Frequency'], mode: 'set', value: 3500.0);
        addMasterEq(const ['Band 3 Q'], mode: 'set', value: 1.0);
        break;
      case 'presence_boost':
        addMasterEq(const ['Band 3 Gain'],
            mode: 'delta', delta: (1.6 * amt).clamp(0.5, 2.5));
        addMasterEq(const ['Band 3 Frequency'], mode: 'set', value: 2600.0);
        addMasterEq(const ['Band 3 Q'], mode: 'set', value: 1.0);
        break;
      case 'air_boost':
        addMasterEq(const ['Band 4 Gain'],
            mode: 'delta', delta: (1.6 * amt).clamp(0.5, 2.5));
        addMasterEq(const ['Band 4 Frequency'], mode: 'set', value: 9500.0);
        addMasterEq(const ['Band 4 Q'], mode: 'set', value: 0.8);
        break;
      case 'warmth_boost':
      case 'thin_fix':
        addMasterEq(const ['Band 1 Gain'],
            mode: 'delta', delta: (1.5 * amt).clamp(0.4, 2.5));
        addMasterEq(const ['Band 2 Gain'],
            mode: 'delta', delta: (0.9 * amt).clamp(0.2, 1.8));
        break;
      case 'dull_fix':
        addMasterEq(const ['Band 4 Gain'],
            mode: 'delta', delta: (1.4 * amt).clamp(0.4, 2.4));
        break;
      case 'low_cut':
        addMasterEq(
          const ['HPF Frequency', 'HPF', 'High Pass', 'Low Cut'],
          mode: 'delta_norm',
          deltaNorm:
              (0.04 * policy.scaleIntensity(intensity)).clamp(0.01, 0.10),
        );
        break;
      case 'high_cut':
        addMasterEq(
          const ['LPF Frequency', 'LPF', 'Low Pass', 'High Cut'],
          mode: 'delta_norm',
          deltaNorm:
              -(0.05 * policy.scaleIntensity(intensity)).clamp(0.01, 0.12),
        );
        break;
      default:
        break;
    }

    return out;
  }

  List<MixAction> _planMasterDeEsser(String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final dir = direction.toLowerCase();
    if (dir == 'remove') {
      return [
        MixAction(
            'delete_master_effect', {'effect_name_contains': fxDeEsserContains})
      ];
    }

    final more = dir != 'down';
    final thresholdDelta = (more ? -4.0 : 4.0) *
        policy.blend(intensity, floor: 0.35, ceiling: 1.0);
    return [
      MixAction(
          'ensure_master_effect', {'effect_name_contains': fxDeEsserContains}),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxDeEsserContains,
        'param_name_contains_any': const ['Threshold'],
        'mode': 'delta',
        'delta': thresholdDelta,
        'skip_if_missing_effect': true,
      }),
    ];
  }

  List<MixAction> _planMasterDistortion(String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final dir = direction.toLowerCase();
    if (dir == 'remove') {
      return [
        MixAction('delete_master_effect',
            {'effect_name_contains': fxDistortionContains})
      ];
    }

    final sign = (dir == 'down') ? -1.0 : 1.0;
    final effectiveIntensity = policy.scaleIntensity(intensity);
    return [
      MixAction('ensure_master_effect',
          {'effect_name_contains': fxDistortionContains}),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxDistortionContains,
        'param_name_contains_any': const ['Drive'],
        'mode': 'delta_norm',
        'delta_norm': sign *
            (0.08 * effectiveIntensity).clamp(
              policy.audibleFloor(
                subtle: 0.02,
                noticeable: 0.05,
                obvious: 0.10,
                extreme: 0.16,
              ),
              policy.executionProfile == MixExecutionProfile.experimentalExtreme
                  ? 0.24
                  : 0.16,
            ),
        'clamp_min': 2.0,
        'clamp_max': 45.0,
        'skip_if_missing_effect': true,
      }),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxDistortionContains,
        'param_name_contains_any': const ['Mix'],
        'mode': 'set',
        'value': _lerp(
          4.0,
          policy.executionProfile == MixExecutionProfile.experimentalExtreme
              ? 28.0
              : (policy.executionProfile == MixExecutionProfile.creativeBold
                  ? 20.0
                  : 16.0),
          effectiveIntensity.clamp(0.0, 1.0),
        ),
        'skip_if_missing_effect': true,
      }),
    ];
  }

  List<MixAction> _planMasterCompressor(
      {required double intensity,
      required bool strict,
      required _MixExecutionPolicy policy}) {
    final effectiveIntensity = policy.scaleIntensity(intensity).clamp(0.0, 1.0);
    final ratioMax =
        policy.executionProfile == MixExecutionProfile.experimentalExtreme
            ? 4.2
            : (policy.executionProfile == MixExecutionProfile.creativeBold
                ? 3.4
                : 2.8);
    final mixMax =
        policy.executionProfile == MixExecutionProfile.experimentalExtreme
            ? 90.0
            : (policy.executionProfile == MixExecutionProfile.creativeBold
                ? 82.0
                : 75.0);
    final thresholdDb =
        strict ? -10.0 : _lerp(-10.0, -18.0, effectiveIntensity);
    final ratio = strict ? 1.8 : _lerp(1.8, ratioMax, effectiveIntensity);
    final attackMs = _lerp(20.0, 8.0, effectiveIntensity);
    final releaseMs = _lerp(180.0, 70.0, effectiveIntensity);
    final mixPct = strict ? 45.0 : _lerp(55.0, mixMax, effectiveIntensity);

    return [
      MixAction('ensure_master_effect', {'effect_name_contains': fxCompressor}),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxCompressor,
        'param_name_contains_any': const ['Threshold'],
        'mode': 'set',
        'value': thresholdDb,
        'skip_if_missing_effect': true,
      }),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxCompressor,
        'param_name_contains_any': const ['Ratio'],
        'mode': 'set',
        'value': ratio,
        'skip_if_missing_effect': true,
      }),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxCompressor,
        'param_name_contains_any': const ['Attack'],
        'mode': 'set',
        'value': attackMs,
        'skip_if_missing_effect': true,
      }),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxCompressor,
        'param_name_contains_any': const ['Release'],
        'mode': 'set',
        'value': releaseMs,
        'skip_if_missing_effect': true,
      }),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxCompressor,
        'param_name_contains_any': const ['Mix'],
        'mode': 'set',
        'value': mixPct,
        'skip_if_missing_effect': true,
      }),
    ];
  }

  List<MixAction> _planMasterLimiter(String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final dir = direction.toLowerCase();
    if (dir == 'remove') {
      return [
        MixAction('delete_master_effect', {'effect_name_contains': fxLimiter})
      ];
    }

    final scale = policy.blend(intensity, floor: 0.35, ceiling: 1.0);
    final thresholdDelta =
        ((dir == 'down') ? 1.0 : -1.0) * (4.0 * scale).clamp(1.0, 5.5);
    final releaseMs = (dir == 'down')
        ? _lerp(120.0, 180.0, intensity)
        : _lerp(90.0, 45.0, intensity);
    final ceilingDb = (dir == 'down')
        ? -0.2
        : (-0.9 - 0.6 * policy.scaleIntensity(intensity));

    return [
      MixAction('ensure_master_effect', {'effect_name_contains': fxLimiter}),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxLimiter,
        'param_name_contains_any': const ['Threshold'],
        'mode': 'delta',
        'delta': thresholdDelta,
        'clamp_min': -40.0,
        'clamp_max': 0.0,
        'skip_if_missing_effect': false,
      }),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxLimiter,
        'param_name_contains_any': const ['Release'],
        'mode': 'set',
        'value': releaseMs.clamp(0.1, 200.0),
        'skip_if_missing_effect': true,
      }),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxLimiter,
        'param_name_contains_any': const ['Ceiling'],
        'mode': 'set',
        'value': ceilingDb.clamp(-40.0, 0.0),
        'skip_if_missing_effect': true,
      }),
    ];
  }

  List<MixAction> _planMasterClipper(String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final dir = direction.toLowerCase();
    if (dir == 'remove') {
      return [
        MixAction('delete_master_effect', {'effect_name_contains': fxClipper})
      ];
    }

    final scale = policy.blend(intensity, floor: 0.35, ceiling: 1.0);
    final thresholdDelta =
        ((dir == 'down') ? 1.0 : -1.0) * (4.0 * scale).clamp(1.0, 5.5);
    final ceilingDb = (dir == 'down')
        ? -0.1
        : (-0.7 - 0.8 * policy.scaleIntensity(intensity));

    return [
      MixAction('ensure_master_effect', {'effect_name_contains': fxClipper}),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxClipper,
        'param_name_contains_any': const ['Threshold'],
        'mode': 'delta',
        'delta': thresholdDelta,
        'clamp_min': -40.0,
        'clamp_max': 0.0,
        'skip_if_missing_effect': true,
      }),
      MixAction('adjust_master_effect_param_by_name', {
        'effect_name_contains': fxClipper,
        'param_name_contains_any': const ['Ceiling'],
        'mode': 'set',
        'value': ceilingDb.clamp(-40.0, 0.0),
        'skip_if_missing_effect': true,
      }),
    ];
  }

  List<MixAction> _planMasterFinishing(
      {required double intensity,
      required bool strict,
      required _MixExecutionPolicy policy}) {
    final out = <MixAction>[];
    out.addAll(_planMasterCompressor(
      intensity: intensity,
      strict: strict,
      policy: policy,
    ));
    out.addAll(_planMasterLimiter(
      'up',
      intensity: intensity,
      policy: policy,
    ));

    final gainDelta = strict
        ? 0.0
        : (0.02 + 0.05 * policy.scaleIntensity(intensity)).clamp(
            0.0,
            policy.executionProfile == MixExecutionProfile.experimentalExtreme
                ? 0.12
                : 0.08,
          );
    if (gainDelta.abs() > 0.001) {
      out.add(
          MixAction('set_master_gain', {'mode': 'delta', 'delta': gainDelta}));
    }
    return out;
  }

  List<MixAction> _planEq(
    ProjectState p,
    List<RowState> rows,
    String? descriptor, {
    required double intensity,
    required Map<int, String> roleOverrides,
    required bool strict,
    required List<String> notesOut,
    required _MixExecutionPolicy policy,
  }) {
    final out = <MixAction>[];
    final d = descriptor
        ?.toLowerCase()
        .trim(); // TODO: allow there to be multiple descriptors ("warmth_boost + air_boost") and execute all as long as they don't clash

    for (final r in rows) {
      out.add(MixAction(
          'ensure_effect', {'row': r.rowIndex, 'effect_name_contains': fxEq}));

      final amt = policy.blend(intensity, floor: 0.35, ceiling: 1.0);
      switch (d) {
        case 'mud_cut':
        case 'box_cut':
          // Low-mid is the real problem — but don’t over-carve
          out.add(_eqMidDelta(r, db: (-7.2 * amt).clamp(-10.5, -4.5)));

          // Low band trim should be subtle — just de-cloud
          out.add(_eqLowDelta(r, db: (-3.2 * amt).clamp(-6.0, -1.5)));
          break;

        case 'boom_cut':
          out.add(_eqLowDelta(r, db: (-10.0 * amt).clamp(-12.0, -4.0)));

          // Secondary mid trim to remove resonance bloom
          out.add(_eqMidDelta(r, db: (-4.5 * amt).clamp(-8.0, -2.5)));
          break;

        case 'harsh_cut':
          // Main harshness lives in upper band — keep this firm but sane
          out.add(_eqHighDelta(
            r,
            db: (-4.5 * amt).clamp(-5.5, -1.0),
          ));

          // Mid cut should be supportive only
          out.add(_eqMidDelta(
            r,
            db: (-2.8 * amt).clamp(-4.8, -1.5),
          ));
          break;

        case 'presence_boost':
          // Core presence lives in mids — keep this strong but controlled
          out.add(_eqMidDelta(
            r,
            db: (6.0 * amt).clamp(3.5, 7.0),
          ));

          // High lift should be subtle — just enough for projection
          out.add(_eqHighDelta(
            r,
            db: (1.6 * amt).clamp(0.8, 3.6),
          ));
          break;

        case 'air_boost':
          // Air lives in highs — strong but not extreme
          out.add(_eqHighDelta(
            r,
            db: (5.0 * amt).clamp(2.0, 6.0),
          ));

          // Mid support should be minimal — avoid nasal/edge buildup
          out.add(_eqMidDelta(
            r,
            db: (1.2 * amt).clamp(0.5, 2.4),
          ));
          break;

        case 'warmth_boost':
          out.add(_eqLowDelta(
            r,
            db: (9.0 * amt).clamp(5.0, 11.0),
          ));

          out.add(_eqMidDelta(
            r,
            db: (5.0 * amt).clamp(2.5, 6.0),
          ));
          break;

        case 'thin_fix':
          out.add(_eqLowDelta(
            r,
            db: (10.0 * amt).clamp(5.0, 11.5),
          ));

          out.add(_eqMidDelta(
            r,
            db: (5.5 * amt).clamp(3.0, 6.5),
          ));
          break;

        case 'dull_fix':
          out.add(_eqHighDelta(
            r,
            db: (5.0 * amt).clamp(2.5, 6.0),
          ));

          out.add(_eqMidDelta(
            r,
            db: (3.0 * amt).clamp(1.2, 3.6),
          ));
          break;

        case 'low_cut':
          // no HPF available on 3-band; simulate by reducing low shelf
          out.add(_eqLowDelta(r, db: (-2.4 * amt).clamp(-7.0, -0.8)));
          break;

        case 'high_cut':
          // no LPF available; simulate by reducing high shelf
          out.add(_eqHighDelta(r, db: (-2.4 * amt).clamp(-7.0, -0.8)));
          break;

        default:
          break;
      }
    }

    return out;
  }

  MixAction _eqLowDelta(RowState r, {required double db}) {
    return MixAction('adjust_effect_param_by_name', {
      'row': r.rowIndex,
      'effect_name_contains': fxEq,
      'param_name_contains_any': const ['Low Gain', 'Low'],
      'mode': 'delta',
      'delta': db,
      'skip_if_missing_effect': false,
    });
  }

  MixAction _eqMidDelta(RowState r, {required double db}) {
    return MixAction('adjust_effect_param_by_name', {
      'row': r.rowIndex,
      'effect_name_contains': fxEq,
      'param_name_contains_any': const ['Mid Gain', 'Mid'],
      'mode': 'delta',
      'delta': db,
      'skip_if_missing_effect': false,
    });
  }

  MixAction _eqHighDelta(RowState r, {required double db}) {
    return MixAction('adjust_effect_param_by_name', {
      'row': r.rowIndex,
      'effect_name_contains': fxEq,
      'param_name_contains_any': const ['High Gain', 'High'],
      'mode': 'delta',
      'delta': db,
      'skip_if_missing_effect': false,
    });
  }

  List<MixAction> _planDeEsser(
    ProjectState p,
    List<RowState> rows,
    String direction, {
    required double intensity,
    required List<String> notesOut,
    required _MixExecutionPolicy policy,
  }) {
    final out = <MixAction>[];
    final dir = direction.toLowerCase();

    if (dir == 'remove') {
      for (final r in rows) {
        out.add(MixAction('delete_effect',
            {'row': r.rowIndex, 'effect_name_contains': fxDeEsserContains}));
      }
      return out;
    }

    final more = dir != 'down';
    final thresholdDelta = (more ? -7.0 : 7.0) *
        policy.blend(intensity, floor: 0.35, ceiling: 1.0);

    for (final r in rows) {
      out.add(MixAction('ensure_effect',
          {'row': r.rowIndex, 'effect_name_contains': fxDeEsserContains}));

      final pThr = ['Threshold'];
      if (_isAllowedFxParam(fxDeEsserContains, pThr)) {
        out.add(
          MixAction('adjust_effect_param_by_name', {
            'row': r.rowIndex,
            'effect_name_contains': fxDeEsserContains,
            'param_name_contains_any': pThr,
            'mode': 'delta',
            'delta': thresholdDelta,
          }),
        );
      }

      if (more) {
        final pFreq = ['Frequency'];
        if (_isAllowedFxParam(fxDeEsserContains, pFreq)) {
          out.add(
            MixAction('adjust_effect_param_by_name', {
              'row': r.rowIndex,
              'effect_name_contains': fxDeEsserContains,
              'param_name_contains_any': pFreq,
              'mode': 'set',
              'value': 5500.0,
              'skip_if_missing_effect': true,
            }),
          );
        } else {
          // fallback note if freq isn't exposed
          notesOut.add(
              "I can reduce sibilance (threshold), but frequency isn't exposed in UI for this de-esser.");
        }
      }
    }

    return out;
  }

  List<MixAction> _planDistortion(List<RowState> rows, String direction,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final out = <MixAction>[];
    final dir = direction.toLowerCase();
    final effectiveIntensity = policy.scaleIntensity(intensity);

    if (dir == 'remove') {
      for (final r in rows) {
        out.add(MixAction('delete_effect',
            {'row': r.rowIndex, 'effect_name_contains': fxDistortionContains}));
      }
      return out;
    }

    for (final r in rows) {
      out.add(MixAction('ensure_effect',
          {'row': r.rowIndex, 'effect_name_contains': fxDistortionContains}));

      final driveParams = ['Drive'];

      if (_isAllowedFxParam(fxDistortionContains, driveParams)) {
        final delta = ((dir == 'down') ? -1.0 : 1.0) *
            (0.25 + 0.45 * effectiveIntensity).clamp(
              policy.audibleFloor(
                subtle: 0.12,
                noticeable: 0.18,
                obvious: 0.28,
                extreme: 0.40,
              ),
              policy.executionProfile == MixExecutionProfile.experimentalExtreme
                  ? 0.55
                  : 0.40,
            );

        out.add(
          MixAction('adjust_effect_param_by_name', {
            'row': r.rowIndex,
            'effect_name_contains': fxDistortionContains,
            'param_name_contains_any': driveParams,
            'mode': 'delta_norm',

            // HARD SAFETY
            'clamp_min': 2.0,
            'clamp_max': 50.0,

            'delta_norm': delta,
            'skip_if_missing_effect': true,
          }),
        );
      }

      final angerParam = ['Anger'];
      if (_isAllowedFxParam(fxDistortionContains, angerParam)) {
        out.add(
          MixAction('adjust_effect_param_by_name', {
            'row': r.rowIndex,
            'effect_name_contains': fxDistortionContains,
            'param_name_contains_any': angerParam,
            'mode': 'delta_norm',
            'delta_norm': ((dir == 'down') ? -1.0 : 1.0) *
                (0.10 + 0.45 * effectiveIntensity).clamp(
                  policy.audibleFloor(
                    subtle: 0.08,
                    noticeable: 0.12,
                    obvious: 0.22,
                    extreme: 0.34,
                  ),
                  policy.executionProfile ==
                          MixExecutionProfile.experimentalExtreme
                      ? 0.45
                      : 0.34,
                ),
            'clamp_0_1': true,
            'skip_if_missing_effect': true,
          }),
        );
      }
    }
    return out;
  }

  // -----------------------------
  // Balance core
  // -----------------------------
  List<MixAction> _planBalance(ProjectState p, _MixRef ref,
      {required double intensity, required _MixExecutionPolicy policy}) {
    final out = <MixAction>[];
    final median = ref.medianEffRms;
    final effectiveIntensity = policy.scaleIntensity(intensity);

    for (final r in p.rows) {
      if (r.approxRms <= 0.001) continue;
      if (!_rowUsable(r)) continue;
      final eff = _effRms(r);
      final ratio = eff / (median + 1e-6);
      if (ratio > 1.7)
        out.addAll(
            _gainDbDelta(r, (-3.5 * effectiveIntensity).clamp(-7.0, -1.4)));
      if (ratio < 0.55 && _effPeak(r) < 0.98)
        out.addAll(_gainDbDelta(r, (3.5 * effectiveIntensity).clamp(1.4, 7.0)));
    }

    return out;
  }

  _ReferencePlanResult _planReferenceGuidedMix({
    required ProjectState project,
    required RowState referenceRow,
    required List<RowState> subjectRows,
    required GoalVector goal,
    required Map<int, String> roleOverrides,
    required bool strict,
    required _MixExecutionPolicy policy,
  }) {
    if (subjectRows.isEmpty) {
      return const _ReferencePlanResult(
        actions: [],
        noOpSummary:
            "I don't adjust the reference row itself. Target the rest of the project or a different row.",
      );
    }

    final notes = <String>[];
    final out = <MixAction>[];
    final referenceMode = goal.referenceMode ?? MixReferenceMode.fullMix;
    final closeness = goal.referenceCloseness ?? MixReferenceCloseness.balanced;
    final adjustedIntensity =
        _referenceAdjustedIntensity(goal.intensity, closeness: closeness);

    final referenceLooksLikeMix = referenceRow.interpretation.fullMixLikely ||
        referenceRow.interpretation.busLikeLikely;
    final modes = <MixReferenceMode>[
      if (referenceMode == MixReferenceMode.fullMix &&
          referenceLooksLikeMix) ...[
        MixReferenceMode.tone,
        MixReferenceMode.loudness,
        MixReferenceMode.width,
        MixReferenceMode.glue,
      ] else if (referenceMode == MixReferenceMode.fullMix) ...[
        MixReferenceMode.tone,
        MixReferenceMode.width,
      ] else
        referenceMode,
    ];
    if (referenceMode == MixReferenceMode.fullMix && !referenceLooksLikeMix) {
      notes.add(
        "The reference looks more like a single element than a full mix, so I matched tone and stereo character more than overall bus glue.",
      );
    }

    final referenceProfile = _referenceProfileForRows([referenceRow]);
    final subjectProfile = _referenceProfileForRows(subjectRows);
    final focusRows = _selectReferenceFocusRows(subjectRows, maxCount: 4);
    final compressionRows = _selectReferenceFocusRows(subjectRows, maxCount: 3);

    if (modes.contains(MixReferenceMode.loudness)) {
      final loudnessGapDb =
          _referenceLoudnessGapDb(referenceProfile, subjectProfile);
      final loudnessThreshold = switch (closeness) {
        MixReferenceCloseness.loose => 2.2,
        MixReferenceCloseness.balanced => 1.4,
        MixReferenceCloseness.close => 0.9,
      };
      if (loudnessGapDb.abs() >= loudnessThreshold) {
        final dbDelta = (loudnessGapDb *
                (closeness == MixReferenceCloseness.close ? 0.65 : 0.52))
            .clamp(-3.6, 3.6);
        for (final row in subjectRows) {
          out.addAll(_gainDbDelta(row, dbDelta));
        }
      }
    }

    if (modes.contains(MixReferenceMode.tone) && focusRows.isNotEmpty) {
      final brightnessGap = _referenceBrightnessScore(referenceProfile) -
          _referenceBrightnessScore(subjectProfile);
      final lowGap = subjectProfile.bassiness - referenceProfile.bassiness;
      final thinGap = referenceProfile.bassiness - subjectProfile.bassiness;
      final harshGap = subjectProfile.sibilance - referenceProfile.sibilance;

      if (brightnessGap > 0.10) {
        final descriptor =
            brightnessGap > 0.22 ? 'air_boost' : 'presence_boost';
        out.addAll(_planEq(
          project,
          focusRows,
          descriptor,
          intensity: adjustedIntensity,
          roleOverrides: roleOverrides,
          strict: strict,
          notesOut: notes,
          policy: policy,
        ));
      } else if (brightnessGap < -0.10 || harshGap > 0.10) {
        final descriptor =
            harshGap > 0.14 || brightnessGap < -0.20 ? 'harsh_cut' : 'high_cut';
        out.addAll(_planEq(
          project,
          focusRows,
          descriptor,
          intensity: adjustedIntensity,
          roleOverrides: roleOverrides,
          strict: strict,
          notesOut: notes,
          policy: policy,
        ));
      }

      if (lowGap > 0.10) {
        out.addAll(_planEq(
          project,
          focusRows,
          lowGap > 0.22 ? 'boom_cut' : 'mud_cut',
          intensity: adjustedIntensity,
          roleOverrides: roleOverrides,
          strict: strict,
          notesOut: notes,
          policy: policy,
        ));
      } else if (thinGap > 0.10) {
        out.addAll(_planEq(
          project,
          focusRows,
          thinGap > 0.20 ? 'thin_fix' : 'warmth_boost',
          intensity: adjustedIntensity,
          roleOverrides: roleOverrides,
          strict: strict,
          notesOut: notes,
          policy: policy,
        ));
      }
    }

    if (modes.contains(MixReferenceMode.width)) {
      final widthGap = _referenceWidthScore(referenceProfile) -
          _referenceWidthScore(subjectProfile);
      final widthThreshold = switch (closeness) {
        MixReferenceCloseness.loose => 0.14,
        MixReferenceCloseness.balanced => 0.10,
        MixReferenceCloseness.close => 0.07,
      };
      if (widthGap.abs() >= widthThreshold) {
        out.addAll(_planPan(
          project,
          subjectRows,
          widthGap > 0 ? 'widen' : 'narrow',
          intensity: adjustedIntensity,
          roleOverrides: roleOverrides,
          policy: policy,
        ));
      }
    }

    if (modes.contains(MixReferenceMode.glue) && compressionRows.isNotEmpty) {
      final glueGap = _referenceGlueScore(referenceProfile) -
          _referenceGlueScore(subjectProfile);
      final glueThreshold = switch (closeness) {
        MixReferenceCloseness.loose => 0.18,
        MixReferenceCloseness.balanced => 0.12,
        MixReferenceCloseness.close => 0.08,
      };
      if (glueGap >= glueThreshold) {
        out.addAll(_planCompressor(
          project,
          compressionRows,
          intensity: adjustedIntensity,
          roleOverrides: roleOverrides,
          strict: strict,
          notesOut: notes,
          policy: policy,
        ));
      }
    }

    if (out.isEmpty) {
      return _ReferencePlanResult(
        actions: const [],
        notes: notes,
        noOpSummary: referenceMode == MixReferenceMode.fullMix
            ? "The project already sits fairly close to that reference."
            : "That target already sits fairly close to the selected reference on the requested dimensions.",
      );
    }

    return _ReferencePlanResult(actions: out, notes: notes);
  }

  double _referenceAdjustedIntensity(
    double base, {
    required MixReferenceCloseness closeness,
  }) {
    final multiplier = switch (closeness) {
      MixReferenceCloseness.loose => 0.85,
      MixReferenceCloseness.balanced => 1.0,
      MixReferenceCloseness.close => 1.18,
    };
    return (base * multiplier).clamp(0.12, 1.0);
  }

  _ReferenceProfile _referenceProfileForRows(List<RowState> rows) {
    return _ReferenceProfile(
      medianEffRms: rows.isEmpty
          ? 0.0
          : rows.map(_effRms).reduce((a, b) => a + b) / rows.length,
      centroidHz: _aggregateRowStat(rows, 'centroid_hz'),
      rolloffHz: _aggregateRowStat(rows, 'spectral_rolloff_hz'),
      spectralSlope: _aggregateRowStat(rows, 'spectral_slope'),
      hfRms: _aggregateRowStat(rows, 'hf_rms'),
      bassiness: _aggregateRowStat(rows, 'bassiness'),
      sibilance: _aggregateRowStat(rows, 'sibilance'),
      sideRatio: _aggregateRowStat(rows, 'side_ratio'),
      phaseCorr: _aggregateRowStat(rows, 'phase_corr', fallback: 1.0),
      stereoImbalance: _aggregateRowStat(rows, 'stereo_imbalance'),
      integratedLufs:
          _aggregateRowStat(rows, 'integrated_lufs_est', fallback: -24.0),
      truePeakDbfs: _aggregateRowStat(rows, 'true_peak_dbfs', fallback: -12.0),
      lraEst: _aggregateRowStat(rows, 'lra_est'),
      transientDensity: _aggregateRowStat(rows, 'transient_density'),
      clipRatio: _aggregateRowStat(rows, 'clip_ratio'),
      stRmsStd: _aggregateRowStat(rows, 'st_rms_std'),
    );
  }

  double _aggregateRowStat(
    List<RowState> rows,
    String key, {
    double fallback = 0.0,
  }) {
    if (rows.isEmpty) return fallback;
    var totalWeight = 0.0;
    var weightedValue = 0.0;
    for (final row in rows) {
      final weight = math.max(0.05, math.min(1.25, _effRms(row)));
      final statValue = row.audioStats[key];
      final value = statValue is num ? (statValue as num).toDouble() : fallback;
      weightedValue += value * weight;
      totalWeight += weight;
    }
    if (totalWeight <= 1e-6) return fallback;
    return weightedValue / totalWeight;
  }

  List<RowState> _selectReferenceFocusRows(
    List<RowState> rows, {
    required int maxCount,
  }) {
    final candidates = rows.where(_rowUsable).toList(growable: false)
      ..sort((a, b) => _effRms(b).compareTo(_effRms(a)));
    return candidates.take(maxCount).toList(growable: false);
  }

  double _referenceBrightnessScore(_ReferenceProfile profile) {
    final centroid = ((profile.centroidHz - 900.0) / 3200.0).clamp(0.0, 1.0);
    final rolloff = ((profile.rolloffHz - 1800.0) / 5200.0).clamp(0.0, 1.0);
    final hf = (profile.hfRms / 0.9).clamp(0.0, 1.0);
    return (0.38 * centroid + 0.34 * rolloff + 0.28 * hf).clamp(0.0, 1.0);
  }

  double _referenceWidthScore(_ReferenceProfile profile) {
    final side = (profile.sideRatio / 0.9).clamp(0.0, 1.0);
    final phase = ((1.0 - profile.phaseCorr) / 1.2).clamp(0.0, 1.0);
    final imbalancePenalty =
        (profile.stereoImbalance / 0.5).clamp(0.0, 1.0) * 0.25;
    return (0.65 * side + 0.35 * phase - imbalancePenalty).clamp(0.0, 1.0);
  }

  double _referenceGlueScore(_ReferenceProfile profile) {
    final lra = (1.0 - (profile.lraEst / 10.0).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    final transients = (1.0 - (profile.transientDensity / 1.0).clamp(0.0, 1.0))
        .clamp(0.0, 1.0);
    final clipRatio = (profile.clipRatio / 0.25).clamp(0.0, 1.0);
    final dynamicsTightness =
        (1.0 - (profile.stRmsStd / 0.18).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    return (0.30 * lra +
            0.25 * transients +
            0.25 * clipRatio +
            0.20 * dynamicsTightness)
        .clamp(0.0, 1.0);
  }

  double _referenceLoudnessGapDb(
    _ReferenceProfile reference,
    _ReferenceProfile subject,
  ) {
    if (reference.integratedLufs > -80.0 && subject.integratedLufs > -80.0) {
      return (reference.integratedLufs - subject.integratedLufs)
          .clamp(-9.0, 9.0);
    }
    final ratio =
        (reference.medianEffRms + 1e-6) / (subject.medianEffRms + 1e-6);
    final db = 20.0 * (math.log(ratio) / math.log(10));
    return db.clamp(-9.0, 9.0);
  }

  // -----------------------------
  // Masking detection (overlap-aware)
  // -----------------------------
  List<MixAction> _planMaskingFixes(
    ProjectState p, {
    required double intensity,
    required Map<int, String> roleOverrides,
  }) {
    final out = <MixAction>[];

    // For each row: if it is masked by louder overlapping competitor(s), nudge competitors down slightly.
    for (final r in p.rows) {
      if (r.approxRms <= 0.001) continue;
      if (r.roleConsistency < 0.65) continue;
      if (!_rowUsable(r)) continue;

      final role = roleOverrides[r.rowIndex] ?? _topRole(r);
      // prioritize vocals/guitar/synth (more “presence-critical”)
      final presenceCritical =
          (role == 'vocals' || role == 'guitar' || role == 'synth');
      if (!presenceCritical) continue;

      final comps = _topOverlapCompetitors(p, r.rowIndex, maxCount: 2);
      if (comps.isEmpty) continue;

      final myEff = _effRms(r);
      int cuts = 0;
      for (final c in comps) {
        if (cuts >= 2) break;
        final cEff = _effRms(c);

        // if competitor is much louder, consider a small cut
        final ref = _mixReference(p);
        final median = ref.medianEffRms;

        if (cEff > myEff * 1.35 && cEff > median * 1.05) {
          out.addAll(_gainDbDelta(c, (-3.2 * intensity).clamp(-5.0, -2.0)));
          cuts++;
        }
      }
    }

    return out;
  }

  // -----------------------------
  // Vocal dominance
  // -----------------------------
  List<MixAction> _planVocalDominance(
    ProjectState p, {
    required double intensity,
    required Map<int, String> roleOverrides,
  }) {
    final vocalRows = p.rows.where((r) {
      if (!_rowUsable(r)) return false;
      final v = r.roleProbs['vocals'] ?? 0.0;
      return v >= 0.5;
    }).toList();

    if (vocalRows.isEmpty) return const [];

    final out = <MixAction>[];

    final vocals = _rowsForRole(p, 'vocals', roleOverrides)
        .where((r) => r.approxRms > 0.001)
        .toList();
    if (vocals.isEmpty) return out;

    final overlaps = _anyOverlap(p, vocals);

    final ref = _mixReference(p);
    final median = ref.medianEffRms;

    // If vocals do NOT overlap, treat each as “lead during its section”
    // → only lift buried vocals, never cut a “dominant” one.
    if (!overlaps) {
      for (final v in vocals) {
        final vEff = _effRms(v);
        if (vEff < median * 0.80 && _effPeak(v) < 0.98) {
          out.addAll(_gainDbDelta(v, (2.0 * intensity).clamp(0.8, 3.5)));
        }
      }
      return out;
    }

    // If vocals overlap, pick strongest as lead and enforce dominance gently
    vocals.sort((a, b) => _effRms(b).compareTo(_effRms(a)));
    final lead = vocals.first;
    final leadEff = _effRms(lead);

    if (leadEff < median * 0.90 && _effPeak(lead) < 0.98) {
      out.addAll(_gainDbDelta(lead, (2.5 * intensity).clamp(0.8, 4.0)));
    }
    if (leadEff > median * 2.2) {
      out.addAll(_gainDbDelta(lead, (-2.2 * intensity).clamp(-4.0, -1.0)));
    }

    return out;
  }

  // -----------------------------
  // Bass vs kick balance
  // -----------------------------
  List<MixAction> _planBassVsKick(
    ProjectState p, {
    required double intensity,
    required Map<int, String> roleOverrides,
  }) {
    final out = <MixAction>[];

    final bassRows = _rowsForRole(p, 'bass', roleOverrides)
        .where((r) => r.approxRms > 0.001)
        .toList();
    final drumRows = _rowsForRole(p, 'drums', roleOverrides)
        .where((r) => r.approxRms > 0.001)
        .toList();
    if (bassRows.isEmpty || drumRows.isEmpty) return out;

    // Best candidate bass
    bassRows.sort((a, b) => _effRms(b).compareTo(_effRms(a)));
    final bass = bassRows.first;

    // Best candidate kick-like row: choose drums row with highest “transient/crest” + low centroid
    drumRows.sort((a, b) {
      final aKick = _kickiness(a);
      final bKick = _kickiness(b);
      return bKick.compareTo(aKick);
    });
    final kick = drumRows.first;

    // Compare low-end energy (bassiness)
    final bassBassiness = _stat(bass.audioStats, 'bassiness');
    final kickBassiness = _stat(kick.audioStats, 'bassiness');

    // If bass dominates a lot, reduce bass slightly or boost kick slightly
    final bassEff = _effRms(bass);
    final kickEff = _effRms(kick);

    // If both overlap heavily and bass is masking kick
    final overlaps = p.overlapMatrix[bass.rowIndex][kick.rowIndex] == 1 ||
        p.overlapMatrix[kick.rowIndex][bass.rowIndex] == 1;

    if (overlaps && bassEff > kickEff * 1.6 && bassBassiness > 0.75) {
      out.addAll(_gainDbDelta(bass, (-2.0 * intensity).clamp(-3.5, -0.8)));
      if (_effPeak(kick) < 0.98) {
        out.addAll(_gainDbDelta(kick, (1.2 * intensity).clamp(0.6, 2.0)));
      }
    }

    // If kick is way too loud compared to bass
    if (kickEff > bassEff * 1.9 && kickBassiness > 0.65) {
      out.addAll(_gainDbDelta(kick, (-2.2 * intensity).clamp(-4.0, -0.8)));
    }

    return out;
  }

  double _kickiness(RowState r) {
    final crest = r.approxCrest.isFinite ? r.approxCrest : 1.0;
    final centroid = _stat(r.audioStats, 'centroid_hz');
    final bassiness = _stat(r.audioStats, 'bassiness');
    // Kick tends to have: high crest, low-ish centroid, high bassiness
    final lowCentroidScore =
        (1.0 - ((centroid - 500.0) / 2500.0).clamp(0.0, 1.0));
    final crestScore = ((crest - 1.2) / 2.2).clamp(0.0, 1.0);
    return (0.45 * bassiness + 0.35 * crestScore + 0.20 * lowCentroidScore)
        .clamp(0.0, 1.0);
  }

  // -----------------------------
  // Harshness detection via HF RMS (+ fallback)
  // -----------------------------
  List<MixAction> _planHarshnessFixes(
    ProjectState p, {
    required double intensity,
    required Map<int, String> roleOverrides,
  }) {
    final out = <MixAction>[];

    for (final r in p.rows) {
      if (r.approxRms <= 0.001) continue;
      if (r.roleConsistency < 0.65) continue;
      if (!_rowUsable(r)) continue;

      final role = roleOverrides[r.rowIndex] ?? _topRole(r);
      // Most annoying harshness usually: vocals/guitar/synth
      if (!(role == 'vocals' || role == 'guitar' || role == 'synth')) continue;

      final hf = _hfRms(r.audioStats);
      final sib = _stat(r.audioStats, 'sibilance');
      final centroid = _stat(r.audioStats, 'centroid_hz');

      // Harsh threshold
      final harsh = (hf > 0.62) || (centroid > 4200 && sib > 0.45);
      if (!harsh) continue;

      // Plan: ensure EQ and cut high band slightly
      out.add(MixAction(
          'ensure_effect', {'row': r.rowIndex, 'effect_name_contains': fxEq}));
      // out.add(_eqBandDelta(r, band: 4, db: (-2.0 * intensity).clamp(-4.0, -0.8))); // THIS ONLY WORKED FOR PARAMETRIC EQ
      out.add(_eqHighDelta(r, db: (-6.5 * intensity).clamp(-8.0, -4.5)));
      out.add(_eqMidDelta(r, db: (-2.5 * intensity).clamp(-4.0, -1.5)));
    }

    return out;
  }

  double _hfRms(Map<String, dynamic> stats) {
    // preferred: hf_rms_norm in 0..1
    final v = _stat(stats, 'hf_rms');
    if (v > 0.0) return v.clamp(0.0, 1.0);

    // fallback: approximate from centroid + sibilance
    final centroid = _stat(stats, 'centroid_hz'); // 0..?
    final sib = _stat(stats, 'sibilance');
    final centroidScore = ((centroid - 2400.0) / 3200.0).clamp(0.0, 1.0);
    return (0.65 * centroidScore + 0.35 * sib).clamp(0.0, 1.0);
  }

  List<MixAction> _planGlueCompression(
    ProjectState p, {
    required double intensity,
    required Map<int, String> roleOverrides,
    required _MixExecutionPolicy policy,
  }) {
    // A gentle “make it sound like a record” pass:
    // - Only touch rows that are active and either peaky (crest) or close to clipping
    // - Keeps it clean; doesn’t smash everything
    final out = <MixAction>[];

    for (final r in p.rows) {
      if (!_rowUsable(r)) continue;

      final role = roleOverrides[r.rowIndex] ?? _topRole(r);
      final crest = r.approxCrest.isFinite ? r.approxCrest : 1.0;
      final pk = _effPeak(r);

      final peaky = crest > 2.1;
      final nearClip = pk > 0.93;

      // Don’t compress everything: focus on vocals/drums + anything peaky/near clip
      final important = (role == 'vocals' || role == 'drums');
      if (!(important || peaky || nearClip)) continue;

      out.addAll(_planCompressor(
        p,
        [r],
        intensity: intensity,
        roleOverrides: roleOverrides,
        strict: false,
        notesOut: const [],
        policy: policy,
      ));
    }

    return out;
  }

  List<MixAction> _planCompressor(
    ProjectState p,
    List<RowState> rows, {
    required double intensity,
    required Map<int, String> roleOverrides,
    required bool strict,
    required List<String> notesOut,
    required _MixExecutionPolicy policy,
  }) {
    final out = <MixAction>[];
    final effectiveIntensity = policy.scaleIntensity(intensity).clamp(0.0, 1.0);

    for (final r in rows) {
      out.add(MixAction('ensure_effect',
          {'row': r.rowIndex, 'effect_name_contains': fxCompressor}));

      final role = roleOverrides[r.rowIndex] ?? _topRole(r);
      final crest = r.approxCrest.isFinite ? r.approxCrest : 1.0;
      final pk = _effPeak(r);

      // --- Targets (professional “loud clean” defaults) ---
      // We use SET for predictable results (vs delta), because compressor params are not uniform across presets.
      double thresholdDb;
      double ratio;
      double attackMs;
      double releaseMs;
      double makeupDb;
      double mix01;

      // Base by role
      if (role == 'vocals') {
        ratio = 3.0;
        attackMs = 18.0;
        releaseMs = 120.0;
        mix01 = 0.75;
        thresholdDb = -18.0;
        makeupDb = 2.5;
      } else if (role == 'drums') {
        ratio = 4.0;
        attackMs = 12.0; // let transient through a bit
        releaseMs = 90.0;
        mix01 = 0.70;
        thresholdDb = -20.0;
        makeupDb = 2.0;
      } else if (role == 'bass') {
        ratio = 2.8;
        attackMs = 25.0;
        releaseMs = 140.0;
        mix01 = 0.70;
        thresholdDb = -19.0;
        makeupDb = 2.0;
      } else {
        // guitars/synth/other
        ratio = 2.4;
        attackMs = 22.0;
        releaseMs = 130.0;
        mix01 = 0.65;
        thresholdDb = -18.0;
        makeupDb = 1.5;
      }

      // Scale by “how much we need it”
      // More peaky / closer to clip → lower threshold a bit (more compression), slightly more makeup
      final peaky = ((crest - 1.6) / 1.8).clamp(0.0, 1.0);
      final clipRisk = ((pk - 0.90) / 0.10).clamp(0.0, 1.0);
      final need = (0.55 * peaky + 0.45 * clipRisk).clamp(0.0, 1.0);

      final amt = policy.blend(intensity, floor: 0.35, ceiling: 1.0);
      thresholdDb += (-8.0 * need * amt); // push threshold down up to ~8 dB
      makeupDb += (1.5 * need * amt); // add up to ~1.5 dB more makeup
      mix01 = (mix01 + 0.10 * need * amt).clamp(0.55, 0.90);

      if (!strict &&
          policy.executionProfile != MixExecutionProfile.producerSafe) {
        final ratioMax =
            policy.executionProfile == MixExecutionProfile.experimentalExtreme
                ? 5.0
                : 4.0;
        ratio = _lerp(ratio, ratioMax, effectiveIntensity).clamp(1.0, ratioMax);
        mix01 =
            _lerp(mix01, policy.destructiveOk ? 0.95 : 0.88, effectiveIntensity)
                .clamp(0.55, 0.95);
      }

      // In strict mode, back off slightly (safer)
      if (strict) {
        thresholdDb += 2.5;
        makeupDb = (makeupDb - 0.8).clamp(0.0, 6.0);
        mix01 = (mix01 - 0.08).clamp(0.45, 0.85);
      }

      // --- Apply (guarded by UI param allowlist) ---
      void setIfAllowed(List<String> paramAny, Object value) {
        if (!_isAllowedFxParam(fxCompressor, paramAny)) return;
        out.add(MixAction('adjust_effect_param_by_name', {
          'row': r.rowIndex,
          'effect_name_contains': fxCompressor,
          'param_name_contains_any': paramAny,
          'mode': 'set',
          'value': value,
          'skip_if_missing_effect': false,
        }));
      }

      setIfAllowed(const ['Threshold'], thresholdDb);
      setIfAllowed(const ['Ratio'], ratio);
      setIfAllowed(const ['Attack'], attackMs);
      setIfAllowed(const ['Release'], releaseMs);
      setIfAllowed(const ['Makeup', 'Make Up', 'Gain'], makeupDb);
      setIfAllowed(const ['Mix'], 100.0 * mix01);
    }

    return out;
  }

  // -----------------------------
  // Disagreement logic (“already good”)
  // -----------------------------
  // -----------------------------
  // Utilities
  // -----------------------------
  double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

  double _stat(Map<String, dynamic> stats, String key) {
    final v = stats[key];
    if (v is num) return v.toDouble();
    return 0.0;
  }

  String _topRole(RowState r) {
    if (r.roleProbs.isEmpty) return 'other';
    final e = r.roleProbs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return e.first.key;
  }

  String _summarize(List<MixAction> actions) {
    final gainRows = <int>{};
    final panRows = <int>{};
    final fxAddByRow = <int, Set<String>>{};
    final fxRemoveByRow = <int, Set<String>>{};
    var masterGain = false;
    var masterPan = false;
    final masterFxAdd = <String>{};
    final masterFxRemove = <String>{};

    for (final a in actions) {
      switch (a.type) {
        case 'set_row_gain':
          gainRows.add(a.data['row'] as int);
          break;

        case 'set_master_gain':
          masterGain = true;
          break;

        case 'set_row_pan':
          panRows.add(a.data['row'] as int);
          break;

        case 'set_master_pan':
          masterPan = true;
          break;

        case 'ensure_effect':
          {
            final row = a.data['row'] as int;
            final fx = (a.data['effect_name_contains'] as String?) ?? 'FX';
            fxAddByRow.putIfAbsent(row, () => <String>{}).add(fx);
            break;
          }

        case 'ensure_master_effect':
          masterFxAdd.add((a.data['effect_name_contains'] as String?) ?? 'FX');
          break;

        case 'delete_effect':
          {
            final row = a.data['row'] as int;
            final fx = (a.data['effect_name_contains'] as String?) ?? 'FX';
            fxRemoveByRow.putIfAbsent(row, () => <String>{}).add(fx);
            break;
          }

        case 'delete_master_effect':
          masterFxRemove
              .add((a.data['effect_name_contains'] as String?) ?? 'FX');
          break;

        case 'adjust_effect_param_by_name':
          {
            final row = a.data['row'] as int;
            final fx = (a.data['effect_name_contains'] as String?) ?? 'FX';
            fxAddByRow.putIfAbsent(row, () => <String>{}).add(fx);
            break;
          }

        case 'adjust_master_effect_param_by_name':
          masterFxAdd.add((a.data['effect_name_contains'] as String?) ?? 'FX');
          break;
      }
    }

    final parts = <String>[];

    // ---- Gain ----
    if (gainRows.isNotEmpty) {
      if (gainRows.length == 1) {
        parts.add('Adjusted the level of Track ${gainRows.first + 1}');
      } else {
        parts.add('Balanced the levels of ${gainRows.length} tracks');
      }
    }
    if (masterGain) {
      parts.add('Adjusted the master level');
    }

    // ---- Pan ----
    if (panRows.isNotEmpty) {
      if (panRows.length == 1) {
        parts.add('Refined the stereo position of Track ${panRows.first + 1}');
      } else {
        parts.add('Improved stereo placement across the mix');
      }
    }
    if (masterPan) {
      parts.add('Adjusted master panning');
    }

    // ---- FX ----
    final anyAddFx = fxAddByRow.isNotEmpty;
    final anyRemoveFx = fxRemoveByRow.isNotEmpty;

    if (anyAddFx || anyRemoveFx) {
      // pick a descriptor based on what FX types are involved
      final fxNames = {
        ...fxAddByRow.values.expand((e) => e),
        ...fxRemoveByRow.values.expand((e) => e)
      }.toSet();

      String fxKind;
      if (fxNames.any((f) => f.toLowerCase().contains('eq'))) {
        fxKind = 'EQ';
      } else if (fxNames.any((f) => f.toLowerCase().contains('reverb'))) {
        fxKind = 'reverb';
      } else if (fxNames.any((f) => f.toLowerCase().contains('delay'))) {
        fxKind = 'delay';
      } else if (fxNames.any((f) => f.toLowerCase().contains('de'))) {
        fxKind = 'de-essing';
      } else {
        fxKind = 'effects';
      }

      if (anyRemoveFx && !anyAddFx) {
        // pure removals
        if (fxRemoveByRow.length == 1) {
          parts.add('Removed $fxKind on Track ${fxRemoveByRow.keys.first + 1}');
        } else {
          parts.add('Removed $fxKind across the mix');
        }
      } else {
        // additions/adjustments (or mixed add+remove)
        if (fxAddByRow.length == 1) {
          parts.add('Adjusted $fxKind on Track ${fxAddByRow.keys.first + 1}');
        } else {
          parts.add('Adjusted $fxKind across the mix');
        }
      }
    }

    final anyAddMasterFx = masterFxAdd.isNotEmpty;
    final anyRemoveMasterFx = masterFxRemove.isNotEmpty;
    if (anyAddMasterFx || anyRemoveMasterFx) {
      if (anyRemoveMasterFx && !anyAddMasterFx) {
        parts.add('Removed effects on the master bus');
      } else {
        parts.add('Adjusted master-bus effects');
      }
    }

    if (parts.isEmpty) {
      return 'Made small refinements to the mix.';
    }

    // Natural join
    if (parts.length == 1) return '${parts.first}.';
    if (parts.length == 2) return '${parts[0]} and ${parts[1]}.';

    return '${parts.sublist(0, parts.length - 1).join(', ')}, and ${parts.last}.';
  }

  bool _anyOverlap(ProjectState p, List<RowState> rows) {
    for (int i = 0; i < rows.length; i++) {
      for (int j = i + 1; j < rows.length; j++) {
        final a = rows[i].rowIndex;
        final b = rows[j].rowIndex;
        if (p.overlapMatrix[a][b] == 1 || p.overlapMatrix[b][a] == 1)
          return true;
      }
    }
    return false;
  }

  bool _rowUsable(RowState r) {
    return r.hasAudio && r.approxRms > 0.0001;
  }

  bool _hasOverlappingMixedRoles(ProjectState p, int row) {
    for (int j = 0; j < p.maxRows; j++) {
      if (j == row) continue;
      if (p.overlapMatrix[row][j] == 1) return true;
    }
    return false;
  }

  DisagreementReason? _detectDisagreement({
    required ProjectState project,
    required MixIntent intent,
    required List<RowState> targets,
    required _MixRef ref,
  }) {
    switch (intent.kind) {
      case 'gain':
        for (final r in targets) {
          if (_effRms(r) > ref.medianEffRms * 1.35 && intent.confidence < 0.7) {
            return DisagreementReason.alreadyLoudEnough;
          }
        }
        break;

      case 'eq':
        if (intent.descriptor == 'presence_boost' ||
            intent.descriptor == 'air_boost') {
          for (final r in targets) {
            final hf = _hfRms(r.audioStats);
            if (hf < 0.55) return null; // actually dull
            return DisagreementReason.alreadyBrightEnough;
          }
        }
        break;

      // case 'pan':
      //   for (final r in targets) {
      //     if (r.pan0To1.abs() > 0.45) {
      //       return DisagreementReason.alreadyCenteredEnough;
      //     }
      //   }
      //   break;

      case 'balance':
        return DisagreementReason.alreadyBalanced;
    }

    return null;
  }

  String disagreementMessage(
      DisagreementReason reason, MixIntent intent, String targetLabel) {
    switch (reason) {
      case DisagreementReason.alreadyLoudEnough:
        return "$targetLabel is already sitting forward in level relative to the mix.";

      case DisagreementReason.alreadyBrightEnough:
        return "$targetLabel already has sufficient upper-mid / high-frequency energy.";

      case DisagreementReason.alreadyCenteredEnough:
        return "$targetLabel is already well-positioned in the stereo field.";

      case DisagreementReason.alreadyBalanced:
        return "The mix is already well balanced overall.";

      case DisagreementReason.headroomRisk:
        return "Pushing this further would compromise headroom.";
    }
  }

  String _targetLabel(MixTarget t) {
    if (t.scope == 'master') {
      return 'the master bus';
    }

    if (t.rowIndex != null) {
      return 'Track ${t.rowIndex! + 1}';
    }

    if (t.role != null && t.role!.isNotEmpty) {
      // Natural article handling
      final role = t.role!.toLowerCase();
      if (role == 'vocals') return 'the vocals';
      return 'the $role';
    }

    return 'this part';
  }

  List<MixAction> _planHardReset(
    ProjectState project, {
    required MixTarget target,
    required List<RowState> resolvedTargets,
  }) {
    final out = <MixAction>[];

    final resetMaster = _isMasterTarget(target) || _isGlobalTarget(target);
    if (resetMaster) {
      out.add(MixAction('hard_reset_master_fx', const {}));
      out.add(MixAction('set_master_gain', {
        'mode': 'set',
        'value': 1.0,
      }));
      out.add(MixAction('set_master_pan', {
        'mode': 'set',
        'value': 0.5,
      }));
    }

    final rowResetTargets = _isGlobalTarget(target)
        ? project.rows.where(_rowUsable).toList(growable: false)
        : resolvedTargets.where(_rowUsable).toList(growable: false);

    for (final r in rowResetTargets) {
      if (!_rowUsable(r)) continue;

      // FX reset (authoritative)
      out.add(MixAction('hard_reset_row_fx', {
        'row': r.rowIndex,
      }));

      // Gain reset
      out.add(MixAction('set_row_gain', {
        'row': r.rowIndex,
        'mode': 'set',
        'value': 1.0,
      }));

      // Pan reset (0.5 = center)
      out.add(MixAction('set_row_pan', {
        'row': r.rowIndex,
        'value': 0.5,
      }));
    }

    return out;
  }
}

class _MixRef {
  final double medianEffRms;
  const _MixRef({required this.medianEffRms});
}

class _ReferenceProfile {
  const _ReferenceProfile({
    required this.medianEffRms,
    required this.centroidHz,
    required this.rolloffHz,
    required this.spectralSlope,
    required this.hfRms,
    required this.bassiness,
    required this.sibilance,
    required this.sideRatio,
    required this.phaseCorr,
    required this.stereoImbalance,
    required this.integratedLufs,
    required this.truePeakDbfs,
    required this.lraEst,
    required this.transientDensity,
    required this.clipRatio,
    required this.stRmsStd,
  });

  final double medianEffRms;
  final double centroidHz;
  final double rolloffHz;
  final double spectralSlope;
  final double hfRms;
  final double bassiness;
  final double sibilance;
  final double sideRatio;
  final double phaseCorr;
  final double stereoImbalance;
  final double integratedLufs;
  final double truePeakDbfs;
  final double lraEst;
  final double transientDensity;
  final double clipRatio;
  final double stRmsStd;
}

class _ReferencePlanResult {
  const _ReferencePlanResult({
    required this.actions,
    this.notes = const [],
    this.noOpSummary,
  });

  final List<MixAction> actions;
  final List<String> notes;
  final String? noOpSummary;
}

enum DisagreementReason {
  alreadyLoudEnough,
  alreadyBrightEnough,
  alreadyCenteredEnough,
  alreadyBalanced,
  headroomRisk
}

const Map<String, List<String>> fxResetGroups = {
  'eq': ['EQ'],
  'dynamics': ['Compressor', 'Transient Shaper', 'De-Esser'],
  'time': ['Reverb', 'Delay'],
  'distortion': ['Distortion', 'Saturation', 'Drive'],
};
