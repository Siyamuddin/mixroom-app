import 'dart:math' as math;

import 'ai_debug.dart';
import 'assistant_action_utils.dart';
import 'cloud_llm_service.dart';
import 'project_state_builder.dart';
import 'local_mixing_model.dart';
import 'magnitude_predictor.dart';
import '../models/goal_vector.dart';
import '../models/mixing_result.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/models/project_state.dart';

class ChatPipeline {
  static const int _kMaxConversationMessages = 24;
  static const int _kMaxConversationCharacters = 12000;
  static const int _kMaxMidiSnapshotNotes = 64;

  final CloudLlmService llm;
  final ProjectStateBuilder projectBuilder;
  final LocalMixingModel mixModel;
  final MixingMagnitudePredictor magnitudePredictor;

  /// Optional: UI can hook into this to show a global "thinking..." indicator.
  final void Function(bool isThinking)? onThinkingChanged;

  final List<Map<String, String>> _conversation = [];
  MixingResult? _pendingMix;
  final Map<int, String> _roleOverrides = {};

  ChatPipeline({
    required this.llm,
    required this.projectBuilder,
    required this.mixModel,
    this.onThinkingChanged,
    MixingMagnitudePredictor? magnitudePredictor,
  }) : magnitudePredictor =
            magnitudePredictor ?? const NoopMixingMagnitudePredictor();

  Map<String, dynamic> _mergeObservabilityMeta(
    Map<String, dynamic>? meta,
    Map<String, dynamic> localObservability,
  ) {
    final merged = <String, dynamic>{
      if (meta != null) ...meta,
    };
    final existingObservability = merged['observability'];
    final observability = <String, dynamic>{
      if (existingObservability is Map<String, dynamic>)
        ...existingObservability,
      if (existingObservability is Map)
        ...existingObservability.cast<String, dynamic>(),
      ...localObservability,
    };
    merged['observability'] = observability;
    return merged;
  }

  Future<ChatPipelineResult> handleUserText({
    required String text,
    required List<AudioTrack> audioTracks,
    required List<double> rowGain,
    required List<double> rowPan,
    required List<List<AutomationPoint>> rowAutomation,
    required double bpmFallback,
    String projectKey = '',
    List<String> rowNames = const [],
    List<TimelineRow> timelineRows = const <TimelineRow>[],
    List<TrackGroup> trackGroups = const <TrackGroup>[],
    String librarySnapshot = '',
    double masterGain0to3 = 1.0,
    double masterPan0to1 = 0.5,
    List<int> selectedClipIndices = const [],
    int primarySelectedClipIndex = -1,
    int? selectedRowIndex,
    String automationClipSnapshot = '',
    String? promptTraceId,
    String? projectId,
    String? aiFeature,
    String? conversationSessionId,
    Map<String, dynamic> clientContext = const <String, dynamic>{},
    bool autoApplyProposals = false,
    bool bypassLearnedMagnitudes = false,
  }) async {
    final userText = text.trim();
    if (userText.isEmpty) {
      return const ChatPipelineResult.message(
        "Let me know what you would like to change, and I'll do my best to help.",
      );
    }

    // If user says "undo", don't call LLM
    // if (_looksLikeUndo(userText)) {
    //   final msg = "Use the Undo button — and let me know what you would like different after.";
    //   _push('user', userText);
    //   _push('assistant', msg);
    //   return ChatPipelineResult.message(msg);
    // }

    onThinkingChanged?.call(true);
    try {
      int projectStatsMs = 0;
      int mixModelHeuristicMs = 0;
      int? mixModelOnnxMs;
      aiDebugLog(
        'pipeline',
        'start text="$userText" autoApplyProposals=$autoApplyProposals selectedRow=$selectedRowIndex primaryClip=$primarySelectedClipIndex clips=${selectedClipIndices.length}',
      );
      // 1) Build project snapshot (local)
      final projectBuildStopwatch = Stopwatch()..start();
      final project = await projectBuilder.build(
        audioTracks: audioTracks,
        bpmFallback: bpmFallback,
        rowGain: rowGain,
        rowPan: rowPan,
        rowAutomation: rowAutomation,
        projectKey: projectKey,
        masterGain0to3: masterGain0to3,
        masterPan0to1: masterPan0to1,
        roleOverrides: _roleOverrides,
        timelineRows: timelineRows,
        trackGroups: trackGroups,
      );
      projectBuildStopwatch.stop();
      projectStatsMs = projectBuildStopwatch.elapsedMilliseconds;

      final snapshot = _projectSnapshot(
        project,
        audioTracks,
        rowNames: rowNames,
      );
      final selectionSnapshot = _selectionSnapshot(
        project: project,
        audioTracks: audioTracks,
        rowNames: rowNames,
        selectedClipIndices: selectedClipIndices,
        primarySelectedClipIndex: primarySelectedClipIndex,
        selectedRowIndex: selectedRowIndex,
        automationClipSnapshot: automationClipSnapshot,
      );

      // final hasAudio = audioTracks.isNotEmpty;
      final hasAudio = project.rows.any((r) => r.hasAudio);
      aiDebugLog(
        'pipeline',
        'project built rows=${project.rows.length} rowsWithAudio=${project.rows.where((r) => r.hasAudio).length} bpm=${project.bpm.toStringAsFixed(1)} hasAudio=$hasAudio',
      );

      // 2) Ask LLM (do NOT push userText yet to avoid duplicating inside request)
      final llmRes = await llm.send(
        conversation: _conversation,
        userText: userText,
        projectSnapshot: snapshot,
        selectionSnapshot: selectionSnapshot,
        librarySnapshot: librarySnapshot,
        promptTraceId: promptTraceId,
        projectId: projectId,
        aiFeature: aiFeature,
        conversationSessionId: conversationSessionId,
        clientContext: clientContext,
        pendingMix: _pendingMix,
      );
      final mixPlanStopwatch = Stopwatch()..start();
      final llmMeta = <String, dynamic>{
        'tool': llmRes.toolName,
        if (llmRes.toolArgs != null) 'tool_args': llmRes.toolArgs,
        if (llmRes.meta != null) ...llmRes.meta!,
      };
      Map<String, dynamic> finalizeMeta(
        Map<String, dynamic>? meta, {
        String? toolName,
      }) {
        return _mergeObservabilityMeta(
          meta,
          <String, dynamic>{
            if ((promptTraceId ?? '').trim().isNotEmpty)
              'prompt_trace_id': promptTraceId!.trim(),
            'project_stats_ms': projectStatsMs,
            'mix_plan_ms': mixPlanStopwatch.elapsedMilliseconds,
            if (mixModelHeuristicMs > 0)
              'mix_model_heuristic_ms': mixModelHeuristicMs,
            if (mixModelOnnxMs != null) 'mix_model_onnx_ms': mixModelOnnxMs,
            if ((toolName ?? '').trim().isNotEmpty) 'tool_name': toolName,
            ...magnitudePredictor.observabilityContext,
          },
        );
      }

      aiDebugLog(
        'pipeline',
        'llm tool=${llmRes.toolName} hasText=${(llmRes.text?.trim().isNotEmpty ?? false)}',
      );

      // 2.1) Informational tool call: always respond, regardless of audio
      if (llmRes.toolName == 'informational_response') {
        final args = llmRes.toolArgs ?? {};
        aiDebugLog('pipeline', 'informational_response');
        if (args['cancels_pending'] == true) {
          aiDebugLog('pipeline', 'pending mix cancelled by informational tool');
          _pendingMix = null;
        }

        final msg = llmRes.text!.trim();
        _push('user', userText);
        _push('assistant', msg);
        return ChatPipelineResult.message(
          msg,
          meta: finalizeMeta(llmMeta, toolName: llmRes.toolName),
        );
      }

      // 2.1b) General DAW editor / tutorial actions (single-chatbar workflow).
      if (llmRes.toolName == 'daw_assistant_actions') {
        final rawArgs = Map<String, dynamic>.from(llmRes.toolArgs ?? const {});
        final List<Map<String, dynamic>> calls = rawArgs['calls'] is List
            ? (rawArgs['calls'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false)
            : <Map<String, dynamic>>[rawArgs];

        String msg = '';
        final List<Map<String, dynamic>> rawActions = <Map<String, dynamic>>[];
        for (final call in calls) {
          if (msg.isEmpty &&
              call['assistant_message']?.toString().trim().isNotEmpty == true) {
            msg = call['assistant_message'].toString().trim();
          }
          final callActions = call['actions'];
          if (callActions is List) {
            rawActions.addAll(
              callActions
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e)),
            );
          }
        }
        if (msg.isEmpty) {
          msg = (llmRes.text?.trim().isNotEmpty == true)
              ? llmRes.text!.trim()
              : '';
        }

        final assistantActions = rawActions
            .map(AssistantAction.fromJson)
            .where((a) => a.type.isNotEmpty)
            .toList(growable: false);

        var conversationAssistantText = msg;
        var shouldPersistAssistantText = !_hasDirectProjectEditAction(
          assistantActions,
        );
        for (final action in assistantActions) {
          final type = action.type.trim().toLowerCase();
          if (type == 'tutorial') {
            shouldPersistAssistantText = true;
          }
          if (type != 'clarify') continue;
          final data = Map<String, dynamic>.from(action.data);
          final question = (data['question'] ?? '').toString().trim();
          if (question.isEmpty) break;
          final options = (data['options'] as List? ?? const [])
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList(growable: false);
          conversationAssistantText = options.isEmpty
              ? question
              : '$question\n\nOptions: ${options.join(' / ')}';
          shouldPersistAssistantText = true;
          break;
        }

        _push('user', userText);
        if (shouldPersistAssistantText &&
            conversationAssistantText.trim().isNotEmpty) {
          _push('assistant', conversationAssistantText);
        }
        return ChatPipelineResult.message(
          msg,
          meta: finalizeMeta(
            <String, dynamic>{
              ...llmMeta,
              'daw_actions': calls.length == 1
                  ? calls.first
                  : <String, dynamic>{'calls': calls},
            },
            toolName: llmRes.toolName,
          ),
          assistantActions: assistantActions,
        );
      }

      if (!hasAudio && llmRes.toolName == 'mix_model_request') {
        final args = Map<String, dynamic>.from(llmRes.toolArgs!);
        final assistantMsg =
            (args['assistant_message']?.toString().trim() ?? '');

        final msg = assistantMsg.isNotEmpty
            ? assistantMsg
            : "I don't see any audio in the project yet. Add a clip and I can help mix it.";

        _push('user', userText);
        _push('assistant', msg);
        return ChatPipelineResult.message(
          msg,
          meta: finalizeMeta(llmMeta, toolName: llmRes.toolName),
        );
      }

      // Normalize tool args into a list of "calls" (supports both single and multi tool outputs)
      // final rawArgs = Map<String, dynamic>.from(llmRes.toolArgs!);
      // final List<Map<String, dynamic>> calls = rawArgs.containsKey('calls')
      //     ? (rawArgs['calls'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
      //     : <Map<String, dynamic>>[rawArgs];

      final rawArgs = Map<String, dynamic>.from(llmRes.toolArgs!);
      final List<Map<String, dynamic>> calls = rawArgs['calls'] is List
          ? (rawArgs['calls'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: false)
          : <Map<String, dynamic>>[rawArgs];

      final List<Map<String, dynamic>> actions = <Map<String, dynamic>>[];
      String assistantMessage = '';
      bool asksPermission = false;
      String rawMode = '';

      for (final call in calls) {
        final callActions = call['actions'];
        if (callActions is List) {
          actions.addAll(
            callActions
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          );
        }
        if (assistantMessage.isEmpty &&
            call['assistant_message']?.toString().trim().isNotEmpty == true) {
          assistantMessage = call['assistant_message'].toString().trim();
        }
        asksPermission = asksPermission || call['asks_permission'] == true;
        if (rawMode.isEmpty && call['mode'] != null) {
          rawMode = call['mode'].toString().toLowerCase();
        }
      }

      if (assistantMessage.isEmpty && llmRes.text?.trim().isNotEmpty == true) {
        assistantMessage = llmRes.text!.trim();
      }
      rawMode = rawMode.isEmpty ? 'propose' : rawMode;

      final bool strict = rawMode == 'execute';
      final learnedMagnitudeEnabled =
          magnitudePredictor.isEnabled && !bypassLearnedMagnitudes;
      final List<Map<String, dynamic>> mixDebugSteps = <Map<String, dynamic>>[];
      final modelMeta = <String, dynamic>{
        ...llmMeta,
        'mode': rawMode,
        'assistant_message': assistantMessage,
        'llm_actions': actions,
        if (calls.length > 1) 'llm_calls': calls,
        'learned_magnitude_enabled': learnedMagnitudeEnabled,
        'learned_magnitude_ready': magnitudePredictor.isReady,
        'learned_magnitude_bypassed': bypassLearnedMagnitudes,
      };

      // Collect a merged mix result across all calls
      final List<MixAction> mergedActions = [];
      final List<String> mergedNotes = [];
      final List<String> noOpSummaries = [];
      bool fallbackUsed = false;
      final Set<String> fallbackReasons = <String>{};

      aiDebugLog(
        'pipeline',
        'mix request mode=$rawMode llmActions=${actions.length} learnedEnabled=$learnedMagnitudeEnabled learnedReady=${magnitudePredictor.isReady} bypassed=$bypassLearnedMagnitudes',
      );

      for (final action in actions) {
        // Safety: each action MUST have a goal
        if (!action.containsKey('goal')) continue;

        GoalVector goal;
        try {
          final goalJson = _resolveReferenceGoalJson(
            Map<String, dynamic>.from(action['goal'] as Map),
            project: project,
            audioTracks: audioTracks,
            selectedRowIndex: selectedRowIndex,
            selectedClipIndices: selectedClipIndices,
            primarySelectedClipIndex: primarySelectedClipIndex,
          );
          goal = GoalVector.fromJson(goalJson);
        } catch (_) {
          continue; // skip malformed action
        }

        aiDebugLog(
          'mix-plan',
          'goal intensity=${goal.intensity.toStringAsFixed(2)} profile=${goal.executionProfile.wireValue} audibility=${goal.audibility.wireValue} scope=${goal.target.scope} ref=${goal.referenceTarget?.rowIndex ?? '-'}:${goal.referenceMode?.wireValue ?? '-'}:${goal.referenceCloseness?.wireValue ?? '-'} intents=${_intentSummary(goal)}',
        );

        final heuristicStopwatch = Stopwatch()..start();
        final mix = mixModel.run(
            project: project,
            goal: goal,
            strict: strict,
            roleOverrides: _roleOverrides);
        heuristicStopwatch.stop();
        mixModelHeuristicMs += heuristicStopwatch.elapsedMilliseconds;

        aiDebugLog(
          'mix-plan',
          'heuristic actions=${mix.actions.length} notes=${mix.notes.length}',
        );
        if (kAiDebugVerbose && mix.actions.isNotEmpty) {
          for (int i = 0; i < mix.actions.length; i++) {
            final a = mix.actions[i];
            aiDebugLog(
              'mix-plan',
              'heuristic[$i] ${a.type} ${aiDebugShortMap(a.data)}',
            );
          }
        }
        if (mix.notes.isNotEmpty) {
          aiDebugLog('mix-plan', 'notes: ${mix.notes.take(4).join(' | ')}');
        }

        final heuristicActionsJson =
            mix.actions.map((a) => a.toJson()).toList(growable: false);
        var resolvedActions = mix.actions;
        MagnitudeRefineResult? refineResult;
        if (resolvedActions.isNotEmpty) {
          if (bypassLearnedMagnitudes) {
            fallbackUsed = true;
            fallbackReasons.add('producer_capture_mode');
            aiDebugLog(
              'mix-plan',
              'magnitude refine bypassed -> using heuristic actions only',
            );
          } else {
            final refineStopwatch = Stopwatch()..start();
            refineResult = await magnitudePredictor.refine(
              project: project,
              goal: goal,
              actions: resolvedActions,
              strict: strict,
              projectId: projectId,
            );
            refineStopwatch.stop();
            mixModelOnnxMs =
                (mixModelOnnxMs ?? 0) + refineStopwatch.elapsedMilliseconds;
            resolvedActions = refineResult.actions;
            if (refineResult.fallbackUsed) {
              fallbackUsed = true;
              if (refineResult.fallbackReason != null &&
                  refineResult.fallbackReason!.isNotEmpty) {
                fallbackReasons.add(refineResult.fallbackReason!);
              }
            }
            aiDebugLog(
              'mix-plan',
              'magnitude refine -> actions=${resolvedActions.length} fallback=${refineResult.fallbackUsed} reason=${refineResult.fallbackReason ?? '-'}',
            );
            if (kAiDebugVerbose && resolvedActions.isNotEmpty) {
              for (int i = 0; i < resolvedActions.length; i++) {
                final a = resolvedActions[i];
                aiDebugLog(
                  'mix-plan',
                  'refined[$i] ${a.type} ${aiDebugShortMap(a.data)}',
                );
              }
            }
          }
        }

        if (kAiDebugLogs) {
          mixDebugSteps.add(<String, dynamic>{
            'goal': <String, dynamic>{
              'scope': goal.target.scope,
              if (goal.target.rowIndex != null)
                'row_index': goal.target.rowIndex,
              if ((goal.target.role ?? '').trim().isNotEmpty)
                'role': goal.target.role,
              'intensity': goal.intensity,
              'execution_profile': goal.executionProfile.wireValue,
              'audibility': goal.audibility.wireValue,
              'style_tags': goal.styleTags,
              'destructive_ok': goal.destructiveOk,
              if (goal.referenceTarget != null)
                'reference_target': <String, dynamic>{
                  if (goal.referenceTarget!.rowIndex != null)
                    'row_index': goal.referenceTarget!.rowIndex,
                  if (goal.referenceTarget!.preferSelected)
                    'prefer_selected': true,
                  'confidence': goal.referenceTarget!.confidence,
                },
              if (goal.referenceMode != null)
                'reference_mode': goal.referenceMode!.wireValue,
              if (goal.referenceCloseness != null)
                'reference_closeness': goal.referenceCloseness!.wireValue,
              'intents': goal.intents
                  .map(
                    (intent) => <String, dynamic>{
                      'kind': intent.kind,
                      if (intent.direction != null)
                        'direction': intent.direction,
                      if (intent.descriptor != null)
                        'descriptor': intent.descriptor,
                      'confidence': intent.confidence,
                    },
                  )
                  .toList(growable: false),
            },
            'heuristic_actions': heuristicActionsJson,
            'refined_actions':
                resolvedActions.map((a) => a.toJson()).toList(growable: false),
            if (refineResult != null)
              'magnitude_debug': refineResult.debugEntries
                  .map((entry) => entry.toJson())
                  .toList(growable: false),
            if (refineResult?.fallbackReason != null)
              'fallback_reason': refineResult!.fallbackReason,
          });
        }

        if (resolvedActions.isEmpty && mix.summary.trim().isNotEmpty) {
          noOpSummaries.add(mix.summary.trim());
        }
        if (resolvedActions.isNotEmpty) {
          mergedActions.addAll(resolvedActions);
        }

        if (mix.notes.isNotEmpty) {
          mergedNotes.addAll(mix.notes);
        }
      }
      modelMeta['learned_magnitude_fallback_used'] = fallbackUsed;
      if (fallbackReasons.isNotEmpty) {
        modelMeta['learned_magnitude_fallback_reasons'] =
            fallbackReasons.toList();
      }
      if (kAiDebugLogs && mixDebugSteps.isNotEmpty) {
        modelMeta['mix_debug_steps'] = mixDebugSteps;
      }
      aiDebugLog(
        'pipeline',
        'mergedActions=${mergedActions.length} fallbackUsed=$fallbackUsed fallbackReasons=${fallbackReasons.join(",")}',
      );
      if (fallbackUsed) {
        aiDebugLog(
          'pipeline',
          bypassLearnedMagnitudes
              ? 'learned magnitudes bypassed for producer capture mode; using heuristic actions'
              : !magnitudePredictor.isEnabled
                  ? 'learned magnitudes disabled; using heuristic actions'
                  : 'learned magnitudes fallback engaged (${fallbackReasons.join(",")})',
        );
      }

      // We only push user once (your original behavior)
      _push('user', userText);

      if (mergedActions.isEmpty) {
        final fallbackSummary =
            noOpSummaries.isNotEmpty ? noOpSummaries.first : '';
        final msg = fallbackSummary.isNotEmpty
            ? fallbackSummary
            : assistantMessage.isNotEmpty
                ? assistantMessage
                : "No mix changes were applied.";

        aiDebugLog('pipeline', 'no-op result');
        _push('assistant', msg);
        return ChatPipelineResult.message(
          msg,
          meta: finalizeMeta(modelMeta, toolName: llmRes.toolName),
        );
      }

      // Build merged mix result
      final mergedMix = MixingResult(
        actions: mergedActions,
        summary: assistantMessage.isNotEmpty
            ? assistantMessage
            : "Applied mix changes.",
        isNoOp: false,
        notes: mergedNotes,
      );

      if (strict) {
        _pendingMix = null;

        final msg =
            assistantMessage.isNotEmpty ? assistantMessage : mergedMix.summary;

        aiDebugLog(
            'pipeline', 'execute result actions=${mergedMix.actions.length}');
        _push('assistant', msg);
        return ChatPipelineResult.mix(
          mergedMix,
          msg,
          meta: finalizeMeta(modelMeta, toolName: llmRes.toolName),
        );
      }

      // Otherwise this is a PROPOSAL (store pending + ask permission)
      if (autoApplyProposals) {
        final msg =
            assistantMessage.isNotEmpty ? assistantMessage : mergedMix.summary;

        aiDebugLog('pipeline',
            'auto-apply proposal actions=${mergedMix.actions.length}');
        _push('assistant', msg);
        return ChatPipelineResult.mix(
          mergedMix,
          msg,
          meta: finalizeMeta(modelMeta, toolName: llmRes.toolName),
        );
      }

      _pendingMix = mergedMix;

      // Centralized proposal phrasing
      String msg =
          assistantMessage.isNotEmpty ? assistantMessage : mergedMix.summary;

      msg = _appendApprovalHint(msg);

      aiDebugLog(
          'pipeline', 'proposal result actions=${mergedMix.actions.length}');
      _push('assistant', msg);
      return ChatPipelineResult.message(
        msg,
        meta: finalizeMeta(modelMeta, toolName: llmRes.toolName),
      );
    } finally {
      onThinkingChanged?.call(false);
    }
  }

  String _intentSummary(GoalVector goal) {
    if (goal.intents.isEmpty) return '(none)';
    return goal.intents
        .map((i) =>
            '${i.kind}:${(i.confidence * 100.0).toStringAsFixed(0)}${i.direction != null ? "/${i.direction}" : ""}${i.descriptor != null ? "/${i.descriptor}" : ""}')
        .join(', ');
  }

  Map<String, dynamic> _resolveReferenceGoalJson(
    Map<String, dynamic> goalJson, {
    required ProjectState project,
    required List<AudioTrack> audioTracks,
    required int? selectedRowIndex,
    required List<int> selectedClipIndices,
    required int primarySelectedClipIndex,
  }) {
    final rawReferenceTarget = goalJson['reference_target'];
    if (rawReferenceTarget is! Map) return goalJson;

    final referenceTarget = Map<String, dynamic>.from(rawReferenceTarget);
    int? resolvedRowIndex;
    final rawRowIndex = referenceTarget['row_index'];
    if (rawRowIndex is num) {
      resolvedRowIndex = rawRowIndex.toInt();
    } else if (referenceTarget['prefer_selected'] == true) {
      resolvedRowIndex = _selectedReferenceRowIndex(
        project: project,
        audioTracks: audioTracks,
        selectedRowIndex: selectedRowIndex,
        selectedClipIndices: selectedClipIndices,
        primarySelectedClipIndex: primarySelectedClipIndex,
      );
    }

    if (resolvedRowIndex == null ||
        resolvedRowIndex < 0 ||
        resolvedRowIndex >= project.rows.length) {
      goalJson.remove('reference_target');
      goalJson.remove('reference_mode');
      goalJson.remove('reference_closeness');
      return goalJson;
    }

    referenceTarget
      ..remove('prefer_selected')
      ..['row_index'] = resolvedRowIndex
      ..['confidence'] =
          ((referenceTarget['confidence'] ?? 0.5) as num).toDouble().clamp(
                0.0,
                1.0,
              );
    goalJson['reference_target'] = referenceTarget;
    return goalJson;
  }

  int? _selectedReferenceRowIndex({
    required ProjectState project,
    required List<AudioTrack> audioTracks,
    required int? selectedRowIndex,
    required List<int> selectedClipIndices,
    required int primarySelectedClipIndex,
  }) {
    if (selectedRowIndex != null &&
        selectedRowIndex >= 0 &&
        selectedRowIndex < project.rows.length) {
      return selectedRowIndex;
    }

    final orderedClipIndices = <int>[
      if (primarySelectedClipIndex >= 0) primarySelectedClipIndex,
      ...selectedClipIndices
          .where((index) => index != primarySelectedClipIndex),
    ];
    for (final clipIndex in orderedClipIndices) {
      if (clipIndex < 0 || clipIndex >= audioTracks.length) continue;
      final rowIndex = audioTracks[clipIndex].rowIndex;
      if (rowIndex >= 0 && rowIndex < project.rows.length) {
        return rowIndex;
      }
    }
    return null;
  }

  /// Call this AFTER your UI successfully applies a mix,
  /// so the assistant remembers what it changed.
  void recordAppliedMix(
    MixingResult mix, {
    String? visibleAssistantText,
  }) {
    if (mix.isNoOp || mix.actions.isEmpty) return;
    final msg = (visibleAssistantText?.trim().isNotEmpty == true)
        ? visibleAssistantText!.trim()
        : mix.summary.trim();
    if (msg.isEmpty) return;
    final last = _conversation.isNotEmpty ? _conversation.last : null;
    if (last != null &&
        last['role'] == 'assistant' &&
        last['content']?.trim() == msg) {
      return;
    }
    _push('assistant', msg);
  }

  static const Set<String> _supportedRoleOverrideValues = <String>{
    'vocals',
    'drums',
    'bass',
    'guitar',
    'synth',
    'other',
  };

  String? _normalizeRoleOverrideValue(String rawRole) {
    final role = rawRole.trim().toLowerCase();
    if (role.isEmpty) return null;
    switch (role) {
      case 'vocal':
      case 'vox':
      case 'lead_vocal':
      case 'lead vocals':
        return 'vocals';
      case 'drum':
      case 'percussion':
        return 'drums';
      case 'keys':
      case 'piano':
      case 'keyboard':
        return 'synth';
      default:
        return _supportedRoleOverrideValues.contains(role) ? role : null;
    }
  }

  bool setRoleOverride({
    required int rowIndex,
    required String role,
  }) {
    final normalizedRole = _normalizeRoleOverrideValue(role);
    if (normalizedRole == null || rowIndex < 0) return false;
    _roleOverrides[rowIndex] = normalizedRole;
    return true;
  }

  bool clearRoleOverride(int rowIndex) {
    if (rowIndex < 0) return false;
    return _roleOverrides.remove(rowIndex) != null;
  }

  void replaceConversation(List<Map<String, String>> conversation) {
    _conversation
      ..clear()
      ..addAll(_trimConversationEntries(conversation));
  }

  void clearConversation() {
    _conversation.clear();
    _pendingMix = null;
  }

  void _push(String role, String content) {
    final nextEntries = _trimConversationEntries([
      ..._conversation,
      {'role': role, 'content': content},
    ]);
    _conversation
      ..clear()
      ..addAll(nextEntries);
  }

  List<Map<String, String>> _trimConversationEntries(
    List<Map<String, String>> entries,
  ) {
    final normalized = entries
        .map((entry) {
          final role = (entry['role'] ?? '').trim().toLowerCase();
          final content = (entry['content'] ?? '').trim();
          if ((role != 'user' && role != 'assistant') || content.isEmpty) {
            return null;
          }
          return <String, String>{
            'role': role,
            'content': content,
          };
        })
        .whereType<Map<String, String>>()
        .toList(growable: false);

    final afterCountLimit = normalized.length > _kMaxConversationMessages
        ? normalized.sublist(normalized.length - _kMaxConversationMessages)
        : normalized;

    final kept = <Map<String, String>>[];
    int totalCharacters = 0;

    for (final entry in afterCountLimit.reversed) {
      final content = entry['content'] ?? '';
      final remaining = _kMaxConversationCharacters - totalCharacters;
      if (remaining <= 0) break;
      if (content.length > remaining) {
        if (kept.isEmpty) {
          kept.add({
            'role': entry['role'] ?? 'user',
            'content': _truncateText(content, remaining),
          });
        }
        break;
      }
      kept.add(entry);
      totalCharacters += content.length;
    }

    return kept.reversed.toList(growable: false);
  }

  String _truncateText(String text, int maxCharacters) {
    if (maxCharacters <= 0) return '';
    if (text.length <= maxCharacters) return text;
    if (maxCharacters == 1) return text.substring(0, 1);
    return '${text.substring(0, maxCharacters - 1)}…';
  }

  String _appendApprovalHint(String base) {
    final trimmed = base.trim();
    if (trimmed.isEmpty) {
      return 'Reply "yes" to apply or "no" to cancel.';
    }

    final lower = trimmed.toLowerCase();
    if (lower.contains('reply "yes"') ||
        lower.contains("reply 'yes'") ||
        lower.contains('reply yes') ||
        lower.contains('yes / no') ||
        lower.contains('apply these changes?')) {
      return trimmed;
    }

    return '$trimmed\n\nReply "yes" to apply or "no" to cancel.';
  }

  bool _hasDirectProjectEditAction(List<AssistantAction> actions) {
    for (final action in actions) {
      switch (action.type.trim().toLowerCase()) {
        case 'project_edit':
        case 'sample_insert':
        case 'clip_edit':
        case 'effect_edit':
        case 'automation_edit':
        case 'midi_compose':
        case 'stem_separate':
        case 'role_override':
          return true;
      }
    }
    return false;
  }

  String _automationTargetsSnapshotForEffects(
    List<EffectState> effects, {
    List<String> mixTargets = const <String>[],
    int maxFx = 6,
    int maxParamsPerFx = 4,
  }) {
    final chunks = <String>[
      for (final target in mixTargets)
        if (target.trim().isNotEmpty) target.trim(),
    ];
    for (final fx in effects.take(maxFx)) {
      final floatParams = fx.parameters
          .where((p) => p.type.trim().toLowerCase() == 'float')
          .take(maxParamsPerFx)
          .toList(growable: false);
      if (floatParams.isEmpty) continue;
      final params = floatParams
          .map((p) {
            final pname = p.name.trim();
            final pid = p.id.trim();
            return pname.isNotEmpty ? pname : pid;
          })
          .where((s) => s.trim().isNotEmpty)
          .join(', ');
      if (params.isEmpty) continue;
      chunks.add('fx${fx.effectIndex}:${fx.name}{$params}');
    }
    return chunks.join(' | ');
  }

  String _automationTargetsSnapshotForRow(
    RowState row, {
    int maxFx = 6,
    int maxParamsPerFx = 8,
  }) {
    return _automationTargetsSnapshotForEffects(
      row.effects,
      mixTargets: const <String>['volume'],
      maxFx: maxFx,
      maxParamsPerFx: maxParamsPerFx,
    );
  }

  String _automationTargetsSnapshotForMaster(
    ProjectState project, {
    int maxFx = 6,
    int maxParamsPerFx = 8,
  }) {
    return _automationTargetsSnapshotForEffects(
      project.masterEffects,
      mixTargets: const <String>['gain', 'pan'],
      maxFx: maxFx,
      maxParamsPerFx: maxParamsPerFx,
    );
  }

  String _effectChainSnapshot(
    List<EffectState> effects, {
    int maxFx = 4,
    int maxParamsPerFx = 2,
  }) {
    if (effects.isEmpty) return 'none';
    final chunks = <String>[];
    for (final fx in effects.take(maxFx)) {
      final paramChunks = <String>[];
      for (final param in fx.parameters.take(maxParamsPerFx)) {
        final name =
            param.name.trim().isNotEmpty ? param.name.trim() : param.id;
        if (name.trim().isEmpty) continue;
        paramChunks.add('$name=${_effectParamValueSnapshot(param)}');
      }
      final state = fx.isBypassed ? 'byp' : 'on';
      if (paramChunks.isEmpty) {
        chunks.add('fx${fx.effectIndex}:${fx.name}($state)');
      } else {
        final omittedParamCount =
            math.max(0, fx.parameters.length - maxParamsPerFx);
        final paramsSummary = omittedParamCount > 0
            ? '${paramChunks.join(', ')}, +$omittedParamCount more'
            : paramChunks.join(', ');
        chunks.add(
          'fx${fx.effectIndex}:${fx.name}($state){$paramsSummary}',
        );
      }
    }
    final omittedFxCount = math.max(0, effects.length - maxFx);
    if (omittedFxCount > 0) {
      chunks.add('+$omittedFxCount more_fx');
    }
    return chunks.join(' | ');
  }

  String _effectParamValueSnapshot(EffectParameterState param) {
    final value = param.value;
    if (value is num) {
      final asDouble = value.toDouble();
      if (!asDouble.isFinite) return '0';
      if (asDouble.abs() >= 10) return asDouble.toStringAsFixed(1);
      return asDouble.toStringAsFixed(2);
    }
    if (value is bool) {
      return value ? 'on' : 'off';
    }
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '—' : text;
  }

  String _projectSnapshot(
    ProjectState p,
    List<AudioTrack> audioTracks, {
    List<String> rowNames = const [],
  }) {
    final b = StringBuffer();
    b.writeln('bpm=${p.bpm.toStringAsFixed(2)}');
    b.writeln(
      'project_key=${p.projectKey.isEmpty ? "unset" : p.projectKey} '
      'estimated_key=${p.estimatedKey.isEmpty ? "unknown" : p.estimatedKey} '
      'estimated_key_confidence=${p.estimatedKeyConfidence.toStringAsFixed(2)}',
    );
    final tracksByRow = <int, List<AudioTrack>>{};
    for (final track in audioTracks) {
      final rowIndex = track.rowIndex;
      if (rowIndex < 0) continue;
      tracksByRow.putIfAbsent(rowIndex, () => <AudioTrack>[]).add(track);
    }
    for (final rowTracks in tracksByRow.values) {
      rowTracks.sort((a, b) {
        final byOffset = a.offset.compareTo(b.offset);
        if (byOffset != 0) return byOffset;
        return a.label.compareTo(b.label);
      });
    }
    final occupiedRows = tracksByRow.keys.toList()..sort();
    b.writeln(
      'occupied_tracks=${occupiedRows.isEmpty ? "none" : occupiedRows.map((row) => row + 1).join(",")}',
    );
    if (occupiedRows.isNotEmpty) {
      b.writeln(
        'top_occupied_track=${occupiedRows.first + 1} bottom_occupied_track=${occupiedRows.last + 1}',
      );
    }
    if (p.trackGroups.isNotEmpty) {
      final rowById = <int, RowState>{
        for (final row in p.rows)
          if (row.rowId >= 0) row.rowId: row,
      };
      for (final group in p.trackGroups) {
        final groupName = group.name.trim().isEmpty
            ? 'Group'
            : group.name.trim().replaceAll('"', "'");
        final memberRows = group.rowIds
            .map((rowId) => rowById[rowId])
            .whereType<RowState>()
            .map((row) => row.rowIndex + 1)
            .toList(growable: false);
        final activeFxCount =
            group.effects.where((effect) => !effect.bypassed).length;
        b.writeln(
          'Group "$groupName": '
          'group_id=${group.id} '
          'member_tracks=${memberRows.isEmpty ? "none" : memberRows.join(",")} '
          'collapsed=${group.collapsed} '
          'gain=${group.gain.toStringAsFixed(2)} '
          'pan=${group.pan.toStringAsFixed(2)} '
          'muted=${group.muted} soloed=${group.soloed} '
          'color=${group.color == 0 ? "unset" : group.color.toRadixString(16)} '
          'fx_count=${group.effects.length} active_fx_count=$activeFxCount '
          'fx_chain=[${group.effects.map((effect) => effect.displayName.trim().isNotEmpty ? effect.displayName.trim() : effect.effectId).join(" > ")}]',
        );
      }
    }

    for (final r in p.rows) {
      final rowTracks = tracksByRow[r.rowIndex] ?? const <AudioTrack>[];
      final detailRowTracks = _rowTracksForSnapshotDetail(rowTracks);
      final omittedDetailClipCount =
          math.max(0, rowTracks.length - detailRowTracks.length);
      final roles = r.roleProbs.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = roles
          .take(3)
          .map((e) => '${e.key}:${(e.value * 100).round()}%')
          .join(', ');
      final activeFxCount = r.effects.where((e) => !e.isBypassed).length;
      final fxChain = _effectChainSnapshot(r.effects);
      final automationTargets = _automationTargetsSnapshotForRow(r);

      final overlaps = <String>[];
      for (int j = 0; j < p.maxRows; j++) {
        if (j == r.rowIndex) continue;
        if (p.overlapMatrix[r.rowIndex][j] != 1) continue;
        double ratio = 1.0;
        if (r.rowIndex < p.overlapRatioMatrix.length &&
            j < p.overlapRatioMatrix[r.rowIndex].length) {
          ratio = p.overlapRatioMatrix[r.rowIndex][j].clamp(0.0, 1.0);
        }
        overlaps.add('${j + 1}(${ratio.toStringAsFixed(2)})');
      }

      final centroid = (r.audioStats['centroid_hz'] ?? 0).toStringAsFixed(0);
      final sibil = (r.audioStats['sibilance'] ?? 0).toStringAsFixed(2);
      final bassy = (r.audioStats['bassiness'] ?? 0).toStringAsFixed(2);
      final zcr = (r.audioStats['zcr'] ?? 0).toStringAsFixed(3);
      final hfRms = (r.audioStats['hf_rms'] ?? 0).toStringAsFixed(3);
      final stRmsP95 = (r.audioStats['st_rms_p95'] ?? 0).toStringAsFixed(3);
      final transientDensity =
          (r.audioStats['transient_density'] ?? 0).toStringAsFixed(3);
      final interpretation = r.interpretation;
      final interpretationFlags = interpretation.flags.take(8).join(', ');
      final interpretationNotes = interpretation.notes.take(2).join(' | ');
      final clipKinds = _rowClipKindSummary(rowTracks);
      final rowLabels = _rowLabelSummary(detailRowTracks);
      final fileHints = _rowFileSummary(detailRowTracks);
      final instrumentHints = _rowInstrumentSummary(detailRowTracks);
      final sampleHints = _rowSampleHintSummary(detailRowTracks);
      final arrangementSketch = _rowArrangementSketch(detailRowTracks, p.bpm);
      final midiState = _rowMidiStateSummary(detailRowTracks);
      final coverageSummary = _rowCoverageSummary(rowTracks);
      final referenceHints = _rowReferenceHintSummary(
          interpretation: interpretation, rowTracks: rowTracks);
      final rowPosition = _rowPositionSummary(r.rowIndex, p.rows.length);
      final rowName = r.rowName.trim().isNotEmpty
          ? r.rowName.trim().replaceAll('"', "'")
          : _rowNameForSnapshot(r.rowIndex, rowNames);
      final laneSummary = r.laneKind == 'instrument'
          ? 'lane_kind=instrument lane_instrument_id=${r.instrumentId.isEmpty ? 'unset' : r.instrumentId} lane_instrument_name="${r.instrumentName.isEmpty ? 'Instrument' : r.instrumentName.replaceAll('"', "'")}" '
          : 'lane_kind=audio ';

      b.writeln(
        'Track ${r.rowIndex + 1}: '
        '${rowName.isEmpty ? '' : 'row_name="$rowName" '}'
        '${r.groupId.trim().isEmpty ? '' : 'group_id=${r.groupId.trim()} '}'
        'row_color=${r.rowColor == 0 ? "unset" : r.rowColor.toRadixString(16)} '
        'row_position=$rowPosition '
        'occupied_row_position=${_occupiedRowPositionSummary(r.rowIndex, occupiedRows)} '
        '$laneSummary'
        'clip_count=${rowTracks.length} '
        '${omittedDetailClipCount > 0 ? 'detail_clips_sampled=${detailRowTracks.length} omitted_detail_clips=$omittedDetailClipCount ' : ''}'
        'has_audio=${r.hasAudio} '
        'clip_kinds=[$clipKinds] '
        'labels=[$rowLabels] '
        'files=[$fileHints] '
        'instruments=[$instrumentHints] '
        'sample_hints=[$sampleHints] '
        'arrangement={$arrangementSketch} '
        'midi_state={$midiState} '
        'coverage{$coverageSummary} '
        'rms=${r.approxRms.toStringAsFixed(3)} crest=${r.approxCrest.toStringAsFixed(2)} '
        'gain=${r.gain0to3.toStringAsFixed(2)} pan=${r.pan0To1.toStringAsFixed(2)} '
        'roles=[$top] role_consistency=${r.roleConsistency.toStringAsFixed(2)} '
        'spectral{centroid_hz=$centroid zcr=$zcr hf_rms=$hfRms sibil=$sibil bassy=$bassy} '
        'dynamics{st_rms_p95=$stRmsP95 transient_density=$transientDensity} '
        'interpretation{'
        'top_role=${interpretation.topRole} '
        'source_type=${interpretation.sourceType} '
        'transient_profile=${interpretation.transientProfile} '
        'spectral_profile=${interpretation.spectralProfile} '
        'stereo_profile=${interpretation.stereoProfile} '
        'edit_risk=${interpretation.editRisk} '
        'role_entropy=${interpretation.roleEntropy.toStringAsFixed(2)} '
        'top_role_margin=${interpretation.topRoleMargin.toStringAsFixed(2)} '
        'classification_confidence=${interpretation.classificationConfidence.toStringAsFixed(2)} '
        'clip_role_disagreement=${interpretation.clipsRoleDisagreement.toStringAsFixed(2)} '
        'overlap_density=${interpretation.overlapDensity.toStringAsFixed(2)} '
        'flags=[${interpretationFlags.isEmpty ? 'none' : interpretationFlags}]'
        '} '
        '${interpretationNotes.isEmpty ? '' : 'notes="$interpretationNotes" '}'
        'reference_hints=[$referenceHints] '
        'overlaps=${overlaps.isEmpty ? "none" : overlaps.join(",")} '
        'fx_count=${r.effects.length} active_fx_count=$activeFxCount '
        'fx_chain=[$fxChain] '
        'automation_targets=[$automationTargets]',
      );
    }

    final activeMasterFxCount =
        p.masterEffects.where((e) => !e.isBypassed).length;
    final masterFxChain = _effectChainSnapshot(p.masterEffects);
    final masterAutomationTargets = _automationTargetsSnapshotForMaster(p);
    b.writeln(
      'Master: '
      'gain=${p.masterGain0to3.toStringAsFixed(2)} '
      'pan=${p.masterPan0to1.toStringAsFixed(2)} '
      'fx_count=${p.masterEffects.length} active_fx_count=$activeMasterFxCount '
      'fx_chain=[$masterFxChain] '
      'automation_targets=[$masterAutomationTargets]',
    );

    return b.toString().trim();
  }

  String _selectionSnapshot({
    required ProjectState project,
    required List<AudioTrack> audioTracks,
    List<String> rowNames = const [],
    required List<int> selectedClipIndices,
    required int primarySelectedClipIndex,
    required int? selectedRowIndex,
    String automationClipSnapshot = '',
  }) {
    final out = StringBuffer();
    final validClipIndices =
        selectedClipIndices.where((i) => i >= 0).toSet().toList()..sort();
    final tracksByRow = <int, List<AudioTrack>>{};
    for (final track in audioTracks) {
      final rowIndex = track.rowIndex;
      if (rowIndex < 0) continue;
      tracksByRow.putIfAbsent(rowIndex, () => <AudioTrack>[]).add(track);
    }
    final occupiedRows = tracksByRow.keys.toList()..sort();

    out.writeln('selected_row_index=${selectedRowIndex ?? -1}');
    out.writeln('selected_clip_indices=${validClipIndices.join(",")}');
    out.writeln('primary_selected_clip_index=$primarySelectedClipIndex');
    out.writeln(
      'occupied_tracks=${occupiedRows.isEmpty ? "none" : occupiedRows.map((row) => row + 1).join(",")}',
    );
    if (occupiedRows.isNotEmpty) {
      out.writeln(
        'top_occupied_track=${occupiedRows.first + 1} bottom_occupied_track=${occupiedRows.last + 1}',
      );
    }
    out.writeln(
      'master_automation_targets=${_automationTargetsSnapshotForMaster(project)}',
    );
    final masterActiveFxCount =
        project.masterEffects.where((e) => !e.isBypassed).length;
    final masterFxChain = _effectChainSnapshot(project.masterEffects);
    out.writeln(
      'master_context{gain=${project.masterGain0to3.toStringAsFixed(2)},pan=${project.masterPan0to1.toStringAsFixed(2)},fx_count=${project.masterEffects.length},active_fx_count=$masterActiveFxCount,fx_chain=[$masterFxChain]}',
    );
    if (selectedRowIndex != null &&
        selectedRowIndex >= 0 &&
        selectedRowIndex < project.rows.length) {
      final row = project.rows[selectedRowIndex];
      final rowTracks = tracksByRow[selectedRowIndex] ?? const <AudioTrack>[];
      final selectedFxChain = _effectChainSnapshot(row.effects);
      final selectedActiveFxCount =
          row.effects.where((e) => !e.isBypassed).length;
      final flags = row.interpretation.flags.take(6).join(', ');
      final coverageSummary = _rowCoverageSummary(rowTracks);
      final arrangementSketch = _rowArrangementSketch(rowTracks, project.bpm);
      final referenceHints = _rowReferenceHintSummary(
        interpretation: row.interpretation,
        rowTracks: rowTracks,
      );
      final rowName = row.rowName.trim().isNotEmpty
          ? row.rowName.trim().replaceAll('"', "'")
          : _rowNameForSnapshot(selectedRowIndex, rowNames);
      final laneSummary = row.laneKind == 'instrument'
          ? 'lane_kind=instrument,instrument_id=${row.instrumentId.isEmpty ? 'unset' : row.instrumentId},instrument_name="${row.instrumentName.isEmpty ? 'Instrument' : row.instrumentName.replaceAll('"', "'")}",'
          : 'lane_kind=audio,';
      out.writeln(
        'selected_row_context{row_index=$selectedRowIndex,track_number=${selectedRowIndex + 1},${rowName.isEmpty ? '' : 'row_name="$rowName",'}row_position=${_rowPositionSummary(selectedRowIndex, project.rows.length)},occupied_row_position=${_occupiedRowPositionSummary(selectedRowIndex, occupiedRows)},clip_count=${rowTracks.length},clip_kinds=[${_rowClipKindSummary(rowTracks)}],${laneSummary}labels=[${_rowLabelSummary(rowTracks)}],files=[${_rowFileSummary(rowTracks)}],instruments=[${_rowInstrumentSummary(rowTracks)}],sample_hints=[${_rowSampleHintSummary(rowTracks)}],arrangement={$arrangementSketch},midi_state={${_rowMidiStateSummary(rowTracks)}},coverage={$coverageSummary},reference_hints=[$referenceHints],fx_count=${row.effects.length},active_fx_count=$selectedActiveFxCount,fx_chain=[$selectedFxChain],top_role=${row.interpretation.topRole},source_type=${row.interpretation.sourceType},flags=[${flags.isEmpty ? 'none' : flags}]}',
      );
      out.writeln(
          'selected_row_automation_targets=${_automationTargetsSnapshotForRow(row)}');
    }
    final trimmedAutomationClipSnapshot = automationClipSnapshot.trim();
    if (trimmedAutomationClipSnapshot.isNotEmpty) {
      out.writeln(trimmedAutomationClipSnapshot);
    }

    final Set<int> requested = {
      ...validClipIndices,
      if (primarySelectedClipIndex >= 0) primarySelectedClipIndex,
    };
    final requestedSorted = requested.toList()..sort();
    for (final clipIndex in requestedSorted) {
      if (clipIndex < 0 || clipIndex >= audioTracks.length) continue;
      final clip = audioTracks[clipIndex];
      final rawStartMs = clip.offset * 1000.0;
      final rawEndMs = rawStartMs +
          (clip.trimEnd - clip.trimStart).inMilliseconds.toDouble();
      final fileName = clip.file.path.split('/').last;
      out.writeln(
        'selected_clip[$clipIndex]{row_index=${clip.rowIndex},track_number=${clip.rowIndex + 1},row_position=${_rowPositionSummary(clip.rowIndex, project.rows.length)},occupied_row_position=${_occupiedRowPositionSummary(clip.rowIndex, occupiedRows)},clip_kind=${clip.clipKind.wireName},start_ms=${rawStartMs.toStringAsFixed(1)},end_ms=${rawEndMs.toStringAsFixed(1)},duration_ms=${(rawEndMs - rawStartMs).toStringAsFixed(1)},file=$fileName,label=${clip.label},instrument_id=${clip.instrumentId.isEmpty ? '—' : clip.instrumentId},instrument_name=${clip.instrumentName.isEmpty ? '—' : clip.instrumentName},sample_hints=[${_clipSampleHintSummary(clip)}]}',
      );
      final midiSnapshot = _selectedMidiClipSnapshot(clipIndex, clip);
      if (midiSnapshot.isNotEmpty) {
        out.writeln(midiSnapshot);
      }
    }

    return out.toString().trim();
  }

  String _selectedMidiClipSnapshot(int clipIndex, AudioTrack clip) {
    if (!clip.isMidi || clip.midiNotes.isEmpty) return '';
    final notes = clip.midiNotes.map((n) => n.copy()).toList(growable: false)
      ..sort((a, b) {
        final byStart = a.startBeat.compareTo(b.startBeat);
        if (byStart != 0) return byStart;
        return a.pitch.compareTo(b.pitch);
      });
    final minPitch = notes.map((n) => n.pitch).reduce(math.min);
    final maxPitch = notes.map((n) => n.pitch).reduce(math.max);
    final spanBeats = notes
        .map((n) => n.startBeat + n.lengthBeats)
        .fold<double>(0.0, math.max);
    final polyphonic = <int, int>{};
    var hasPolyphony = false;
    for (final note in notes) {
      final bucket = (note.startBeat * 1000.0).round();
      final nextCount = (polyphonic[bucket] ?? 0) + 1;
      polyphonic[bucket] = nextCount;
      if (nextCount >= 2) {
        hasPolyphony = true;
      }
    }
    final dominantLengthBeats = _dominantMidiLengthBeats(notes);
    final preview = notes.take(_kMaxMidiSnapshotNotes).map((n) {
      final pitch = _midiPitchLabel(n.pitch);
      final start = n.startBeat.toStringAsFixed(2);
      final len = n.lengthBeats.toStringAsFixed(2);
      return '$pitch@$start+$len';
    }).join('|');
    final truncated =
        notes.length > _kMaxMidiSnapshotNotes ? ',truncated=true' : '';
    return 'selected_clip_midi[$clipIndex]{note_count=${notes.length},span_beats=${spanBeats.toStringAsFixed(2)},pitch_range=${_midiPitchLabel(minPitch)}..${_midiPitchLabel(maxPitch)},polyphonic=$hasPolyphony,dominant_length_beats=${dominantLengthBeats.toStringAsFixed(2)},notes_preview=$preview$truncated}';
  }

  double _dominantMidiLengthBeats(List<MidiNote> notes) {
    final counts = <int, int>{};
    for (final note in notes) {
      final bucket = (note.lengthBeats * 100.0).round();
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    final ordered = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    if (ordered.isEmpty) return 0.0;
    return ordered.first.key / 100.0;
  }

  String _rowNameForSnapshot(int rowIndex, List<String> rowNames) {
    if (rowIndex < 0 || rowIndex >= rowNames.length) return '';
    return rowNames[rowIndex].trim().replaceAll('"', "'");
  }

  String _rowPositionSummary(int rowIndex, int totalRows) {
    if (rowIndex < 0 || totalRows <= 0) return 'unknown';
    if (rowIndex == 0) return 'top-most';
    if (rowIndex == totalRows - 1) return 'bottom-most';
    return 'middle';
  }

  String _occupiedRowPositionSummary(int rowIndex, List<int> occupiedRows) {
    if (rowIndex < 0) return 'unknown';
    if (!occupiedRows.contains(rowIndex)) return 'not_occupied';
    if (occupiedRows.isEmpty) return 'unknown';
    if (rowIndex == occupiedRows.first) return 'top-most-occupied';
    if (rowIndex == occupiedRows.last) return 'bottom-most-occupied';
    return 'middle-occupied';
  }

  String _rowClipKindSummary(List<AudioTrack> rowTracks) {
    if (rowTracks.isEmpty) return 'none';
    final audioCount = rowTracks.where((t) => !t.isMidi).length;
    final midiCount = rowTracks.where((t) => t.isMidi).length;
    final out = <String>[];
    if (audioCount > 0) out.add('audio:$audioCount');
    if (midiCount > 0) out.add('midi:$midiCount');
    return out.join(', ');
  }

  List<AudioTrack> _rowTracksForSnapshotDetail(List<AudioTrack> rowTracks) {
    const maxDetailedClips = 64;
    if (rowTracks.length <= maxDetailedClips) return rowTracks;
    final ordered = List<AudioTrack>.from(rowTracks)
      ..sort((a, b) {
        final byOffset = a.offset.compareTo(b.offset);
        if (byOffset != 0) return byOffset;
        return a.label.compareTo(b.label);
      });
    const edgeCount = maxDetailedClips ~/ 2;
    return <AudioTrack>[
      ...ordered.take(edgeCount),
      ...ordered.skip(math.max(edgeCount, ordered.length - edgeCount)),
    ];
  }

  String _clipSampleHintSummary(AudioTrack clip) {
    final hints = <String>{};
    if (!clip.isMidi) {
      hints.addAll(
        AssistantActionUtils.sampleRoleHintsFromText(
          '${clip.file.path.split('/').last} ${clip.label}',
        ),
      );
    }
    return hints.isEmpty ? 'none' : hints.join(',');
  }

  String _rowSampleHintSummary(List<AudioTrack> rowTracks) {
    if (rowTracks.isEmpty) return 'none';
    final counts = <String, int>{};
    for (final clip in rowTracks) {
      final summary = _clipSampleHintSummary(clip);
      if (summary == 'none') continue;
      for (final hint in summary
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)) {
        counts[hint] = (counts[hint] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return 'none';
    final ordered = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return ordered.map((entry) => '${entry.key}:${entry.value}').join(', ');
  }

  String _rowLabelSummary(List<AudioTrack> rowTracks) {
    final labels = rowTracks
        .map((t) => t.label.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .take(4)
        .toList(growable: false);
    return labels.isEmpty ? '—' : labels.join(', ');
  }

  String _rowFileSummary(List<AudioTrack> rowTracks) {
    final fileNames = rowTracks
        .map((t) => t.file.path.split('/').last.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .take(4)
        .toList(growable: false);
    return fileNames.isEmpty ? '—' : fileNames.join(', ');
  }

  String _rowInstrumentSummary(List<AudioTrack> rowTracks) {
    final instrumentHints = rowTracks
        .where((t) => t.isMidi)
        .map((t) {
          final name = t.instrumentName.trim();
          final id = t.instrumentId.trim();
          if (name.isNotEmpty && id.isNotEmpty) return '$name<$id>';
          if (name.isNotEmpty) return name;
          if (id.isNotEmpty) return id;
          return '';
        })
        .where((s) => s.isNotEmpty)
        .toSet()
        .take(4)
        .toList(growable: false);
    return instrumentHints.isEmpty ? '—' : instrumentHints.join(', ');
  }

  String _rowMidiStateSummary(List<AudioTrack> rowTracks) {
    final midiTracks = rowTracks
        .where((track) => track.isMidi && track.midiNotes.isNotEmpty)
        .toList(growable: false);
    if (midiTracks.isEmpty) return 'none';
    final notes = <MidiNote>[
      for (final track in midiTracks) ...track.midiNotes.map((n) => n.copy()),
    ]..sort((a, b) {
        final byStart = a.startBeat.compareTo(b.startBeat);
        if (byStart != 0) return byStart;
        return a.pitch.compareTo(b.pitch);
      });
    final minPitch = notes.map((n) => n.pitch).reduce(math.min);
    final maxPitch = notes.map((n) => n.pitch).reduce(math.max);
    final spanBeats = notes
        .map((n) => n.startBeat + n.lengthBeats)
        .fold<double>(0.0, math.max);
    final polyphonicCounts = <int, int>{};
    var polyphonic = false;
    for (final note in notes) {
      final bucket = (note.startBeat * 1000.0).round();
      final nextCount = (polyphonicCounts[bucket] ?? 0) + 1;
      polyphonicCounts[bucket] = nextCount;
      if (nextCount >= 2) polyphonic = true;
    }
    final dominantLengthBeats = _dominantMidiLengthBeats(notes);
    final preview = notes.take(6).map((n) {
      final pitch = _midiPitchLabel(n.pitch);
      final start = n.startBeat.toStringAsFixed(2);
      final len = n.lengthBeats.toStringAsFixed(2);
      return '$pitch@$start+$len';
    }).join('|');
    final previewSuffix = notes.length > 6 ? ',preview_truncated=true' : '';
    return 'clips=${midiTracks.length},note_count=${notes.length},span_beats=${spanBeats.toStringAsFixed(2)},pitch_range=${_midiPitchLabel(minPitch)}..${_midiPitchLabel(maxPitch)},polyphonic=$polyphonic,dominant_length_beats=${dominantLengthBeats.toStringAsFixed(2)},preview=$preview$previewSuffix';
  }

  String _rowCoverageSummary(List<AudioTrack> rowTracks) {
    if (rowTracks.isEmpty) return 'start_ms=— end_ms=— longest_ms=0';
    double minStartMs = double.infinity;
    double maxEndMs = 0.0;
    double longestMs = 0.0;
    for (final track in rowTracks) {
      final startMs = track.offset * 1000.0;
      final durationMs =
          (track.trimEnd - track.trimStart).inMilliseconds.toDouble();
      final endMs = startMs + durationMs;
      if (startMs < minStartMs) minStartMs = startMs;
      if (endMs > maxEndMs) maxEndMs = endMs;
      if (durationMs > longestMs) longestMs = durationMs;
    }
    return 'start_ms=${minStartMs.toStringAsFixed(1)} end_ms=${maxEndMs.toStringAsFixed(1)} longest_ms=${longestMs.toStringAsFixed(1)}';
  }

  String _rowArrangementSketch(List<AudioTrack> rowTracks, double bpm) {
    final audioTracks = rowTracks.where((track) => !track.isMidi).toList()
      ..sort((a, b) {
        final byOffset = a.offset.compareTo(b.offset);
        if (byOffset != 0) return byOffset;
        return a.label.compareTo(b.label);
      });
    if (audioTracks.isEmpty) return 'none';
    final preview = audioTracks.take(8).map((clip) {
      final startBeat = (clip.offset * bpm) / 60.0;
      return _timelineBeatLabel(startBeat);
    }).join('|');
    final maxStartBeat =
        audioTracks.map((clip) => (clip.offset * bpm) / 60.0).fold<double>(
              0.0,
              math.max,
            );
    final estimatedBars = math.max(1, (maxStartBeat / 4.0).ceil());
    final truncated = audioTracks.length > 8 ? ',truncated=true' : '';
    return 'audio_hits=${audioTracks.length},bars≈$estimatedBars,onsets=$preview$truncated';
  }

  String _rowReferenceHintSummary({
    required RowInterpretationState interpretation,
    required List<AudioTrack> rowTracks,
  }) {
    if (rowTracks.isEmpty) return 'none';
    final hints = <String>[];
    final nonMidiTracks =
        rowTracks.where((t) => !t.isMidi).toList(growable: false);
    final singleLongClip = nonMidiTracks.length == 1 &&
        (nonMidiTracks.first.trimEnd - nonMidiTracks.first.trimStart)
                .inMilliseconds >=
            45000;
    final longFormAudio = nonMidiTracks.any(
      (t) => (t.trimEnd - t.trimStart).inMilliseconds >= 45000,
    );
    if (singleLongClip) hints.add('single_long_clip');
    if (longFormAudio) hints.add('long_form_audio');
    if (interpretation.fullMixLikely) hints.add('full_mix_like');
    if (interpretation.busLikeLikely) hints.add('bus_like');
    if (interpretation.wideStereoLikely) hints.add('wide_stereo');
    if (interpretation.alreadyLoudLikely) hints.add('already_loud');
    return hints.isEmpty ? 'none' : hints.join(', ');
  }

  String _midiPitchLabel(int midi) {
    const names = <String>[
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final safe = midi.clamp(0, 127);
    final name = names[safe % 12];
    final octave = (safe ~/ 12) - 1;
    return '$name$octave';
  }

  String _timelineBeatLabel(double startBeat) {
    if (!startBeat.isFinite || startBeat < 0) return 'm1:b1.00';
    final measure = (startBeat ~/ 4) + 1;
    final beatInMeasure = (startBeat % 4.0) + 1.0;
    return 'm$measure:b${beatInMeasure.toStringAsFixed(2)}';
  }
}
