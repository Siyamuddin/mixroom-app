import 'dart:math' as math;

import 'ai_debug.dart';
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

  Future<ChatPipelineResult> handleUserText({
    required String text,
    required List<AudioTrack> audioTracks,
    required List<double> rowGain,
    required List<double> rowPan,
    required List<List<AutomationPoint>> rowAutomation,
    required double bpmFallback,
    double masterGain0to3 = 1.0,
    double masterPan0to1 = 0.5,
    List<int> selectedClipIndices = const [],
    int primarySelectedClipIndex = -1,
    int? selectedRowIndex,
    String automationClipSnapshot = '',
    String? projectId,
    String? aiFeature,
    bool autoApplyProposals = false,
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
      aiDebugLog(
        'pipeline',
        'start text="$userText" autoApplyProposals=$autoApplyProposals selectedRow=$selectedRowIndex primaryClip=$primarySelectedClipIndex clips=${selectedClipIndices.length}',
      );
      // 1) Build project snapshot (local)
      final project = await projectBuilder.build(
        audioTracks: audioTracks,
        bpmFallback: bpmFallback,
        rowGain: rowGain,
        rowPan: rowPan,
        rowAutomation: rowAutomation,
        masterGain0to3: masterGain0to3,
        masterPan0to1: masterPan0to1,
        roleOverrides: _roleOverrides,
      );

      final snapshot = _projectSnapshot(project);
      final selectionSnapshot = _selectionSnapshot(
        project: project,
        audioTracks: audioTracks,
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
        projectId: projectId,
        aiFeature: aiFeature,
        pendingMix: _pendingMix,
      );
      final llmMeta = <String, dynamic>{
        'tool': llmRes.toolName,
        if (llmRes.toolArgs != null) 'tool_args': llmRes.toolArgs,
        if (llmRes.meta != null) ...llmRes.meta!,
      };

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
        return ChatPipelineResult.message(msg, meta: llmMeta);
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
              : "Done.";
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
          meta: <String, dynamic>{
            ...llmMeta,
            'daw_actions':
                calls.length == 1 ? calls.first : <String, dynamic>{'calls': calls},
          },
          assistantActions: assistantActions,
        );
      }

      // 2.2) Style preset request (bypass mix logic entirely)
      /*
      if (llmRes.toolName == 'style_request') {
        final args = Map<String, dynamic>.from(llmRes.toolArgs ?? {});
        final style = args['style']?.toString();

        // Defensive guard: malformed style request → ignore and fall back
        if (style == null || style.isEmpty) {
          // Do NOT apply anything, just continue into normal mix handling
        } else {
          _push('user', userText);

          final targets = (args['targets'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList();

          final mix = mixModel.runStylePreset(
            project: project,
            style: style,
            targets: targets,
          );

          final msg = "${_prettyStyle(style)} style has been applied across the project.";

          _pendingMix = null;
          _push('assistant', msg);
          return ChatPipelineResult.mix(mix, msg);
        }
      }
      */

      if (!hasAudio && llmRes.toolName == 'mix_model_request') {
        final args = Map<String, dynamic>.from(llmRes.toolArgs!);
        final assistantMsg =
            (args['assistant_message']?.toString().trim() ?? '');

        final msg = assistantMsg.isNotEmpty
            ? assistantMsg
            : "I don't see any audio in the project yet. Add a clip and I can help mix it.";

        _push('user', userText);
        _push('assistant', msg);
        return ChatPipelineResult.message(msg, meta: llmMeta);
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
      final modelMeta = <String, dynamic>{
        ...llmMeta,
        'mode': rawMode,
        'assistant_message': assistantMessage,
        'llm_actions': actions,
        if (calls.length > 1) 'llm_calls': calls,
        'learned_magnitude_enabled': magnitudePredictor.isEnabled,
        'learned_magnitude_ready': magnitudePredictor.isReady,
      };

      // Collect a merged mix result across all calls
      final List<MixAction> mergedActions = [];
      final List<String> mergedNotes = [];
      bool fallbackUsed = false;
      final Set<String> fallbackReasons = <String>{};

      aiDebugLog(
        'pipeline',
        'mix request mode=$rawMode llmActions=${actions.length} learnedEnabled=${magnitudePredictor.isEnabled} learnedReady=${magnitudePredictor.isReady}',
      );

      for (final action in actions) {
        // Safety: each action MUST have a goal
        if (!action.containsKey('goal')) continue;

        GoalVector goal;
        try {
          final goalJson = Map<String, dynamic>.from(action['goal'] as Map);
          goal = GoalVector.fromJson(goalJson);
        } catch (_) {
          continue; // skip malformed action
        }

        aiDebugLog(
          'mix-plan',
          'goal intensity=${goal.intensity.toStringAsFixed(2)} scope=${goal.target.scope} intents=${_intentSummary(goal)}',
        );

        final mix = mixModel.run(
            project: project,
            goal: goal,
            strict: strict,
            roleOverrides: _roleOverrides);

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

        var resolvedActions = mix.actions;
        if (resolvedActions.isNotEmpty) {
          final refineResult = await magnitudePredictor.refine(
            project: project,
            goal: goal,
            actions: resolvedActions,
            strict: strict,
          );
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
      aiDebugLog(
        'pipeline',
        'mergedActions=${mergedActions.length} fallbackUsed=$fallbackUsed fallbackReasons=${fallbackReasons.join(",")}',
      );
      if (fallbackUsed) {
        aiDebugLog(
          'pipeline',
          !magnitudePredictor.isEnabled
              ? 'learned magnitudes disabled; using heuristic actions'
              : 'learned magnitudes fallback engaged (${fallbackReasons.join(",")})',
        );
      }

      // We only push user once (your original behavior)
      _push('user', userText);

      if (mergedActions.isEmpty) {
        final msg = assistantMessage.isNotEmpty
            ? _appendNotes(assistantMessage, mergedNotes)
            : "No mix changes were applied.";

        aiDebugLog('pipeline', 'no-op result');
        _push('assistant', msg);
        return ChatPipelineResult.message(msg, meta: modelMeta);
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

        final msg = assistantMessage.isNotEmpty
            ? _appendNotes(assistantMessage, mergedMix.notes)
            : mergedMix.summary;

        aiDebugLog(
            'pipeline', 'execute result actions=${mergedMix.actions.length}');
        _push('assistant', msg);
        return ChatPipelineResult.mix(mergedMix, msg, meta: modelMeta);
      }

      // Otherwise this is a PROPOSAL (store pending + ask permission)
      if (autoApplyProposals) {
        final msg = _appendNotes(
            assistantMessage.isNotEmpty ? assistantMessage : mergedMix.summary,
            mergedMix.notes);

        aiDebugLog('pipeline',
            'auto-apply proposal actions=${mergedMix.actions.length}');
        _push('assistant', msg);
        return ChatPipelineResult.mix(mergedMix, msg, meta: modelMeta);
      }

      _pendingMix = mergedMix;

      // Centralized proposal phrasing
      String msg =
          assistantMessage.isNotEmpty ? assistantMessage : mergedMix.summary;

      msg = _appendNotes(msg, mergedMix.notes);

      msg = _appendApprovalHint(msg);

      aiDebugLog(
          'pipeline', 'proposal result actions=${mergedMix.actions.length}');
      _push('assistant', msg);
      return ChatPipelineResult.message(msg, meta: modelMeta);
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

  bool _isEmptyToolGoal(Map<String, dynamic> args) {
    final goal = args['goal'];
    if (goal is! Map) return true;

    final intensity = (goal['intensity'] is num)
        ? (goal['intensity'] as num).toDouble()
        : 0.0;

    double bestConf = 0.0;
    final intents = goal['intents'];
    if (intents is List) {
      for (final it in intents) {
        if (it is Map && it['confidence'] is num) {
          bestConf = math.max(bestConf, (it['confidence'] as num).toDouble());
        }
      }
    }

    return intensity < 0.05 && bestConf < 0.20;
  }

  String _appendNotes(String base, List<String> notes) {
    if (notes.isEmpty) return base;
    final b = StringBuffer()
      ..writeln(base.trim())
      ..writeln('\n—');
    for (final n in notes.take(3)) {
      b.writeln('• $n');
    }
    return b.toString().trim();
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

  String _prettyStyle(String s) {
    switch (s) {
      case 'electronic':
        return 'Electronic';
      case 'indie_rock':
        return 'Indie Rock';
      case 'pop_rock_blues':
        return 'Pop Rock / Blues';
      case 'jazz':
        return 'Jazz';
      default:
        return s;
    }
  }

  String _appendAssistantMessage(String base, String newMsg) {
    if (newMsg.isEmpty) return base;
    final b = StringBuffer()
      ..writeln(base.trim())
      ..writeln('──────────────');
    b.writeln('$newMsg');
    return b.toString().trim();
  }

  String _automationTargetsSnapshotForEffects(
    List<EffectState> effects, {
    List<String> mixTargets = const <String>[],
    int maxFx = 6,
    int maxParamsPerFx = 8,
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
            final pid = p.id.trim().isEmpty ? p.name.trim() : p.id.trim();
            final pname = p.name.trim().isEmpty ? pid : p.name.trim();
            return '$pname[$pid]';
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

  String _projectSnapshot(ProjectState p) {
    final b = StringBuffer();
    b.writeln('bpm=${p.bpm.toStringAsFixed(2)}');

    for (final r in p.rows) {
      final roles = r.roleProbs.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = roles
          .take(3)
          .map((e) => '${e.key}:${(e.value * 100).round()}%')
          .join(', ');
      final fx = r.effects.map((e) => e.name).join(', ');
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

      b.writeln(
        'Track ${r.rowIndex + 1}: '
        'isEmpty = ${r.clips.isEmpty} '
        'fileName(s)=${r.clips.isEmpty ? '—' : r.clips.map((c) => c.fileName).join(', ')} '
        'rms=${r.approxRms.toStringAsFixed(3)} crest=${r.approxCrest.toStringAsFixed(2)} '
        'gain=${r.gain0to3.toStringAsFixed(2)} pan=${r.pan0To1.toStringAsFixed(2)} '
        'roles=[$top] role_consistency=${r.roleConsistency.toStringAsFixed(2)} '
        'spectral{centroid_hz=$centroid zcr=$zcr hf_rms=$hfRms sibil=$sibil bassy=$bassy} '
        'dynamics{st_rms_p95=$stRmsP95 transient_density=$transientDensity} '
        'overlaps=${overlaps.isEmpty ? "none" : overlaps.join(",")} '
        'fx=[$fx] '
        'automation_targets=[$automationTargets]',
      );
    }

    final masterFx = p.masterEffects.map((e) => e.name).join(', ');
    final masterAutomationTargets = _automationTargetsSnapshotForMaster(p);
    b.writeln(
      'Master: '
      'gain=${p.masterGain0to3.toStringAsFixed(2)} '
      'pan=${p.masterPan0to1.toStringAsFixed(2)} '
      'fx=[${masterFx.isEmpty ? '—' : masterFx}] '
      'automation_targets=[$masterAutomationTargets]',
    );

    return b.toString().trim();
  }

  String _selectionSnapshot({
    required ProjectState project,
    required List<AudioTrack> audioTracks,
    required List<int> selectedClipIndices,
    required int primarySelectedClipIndex,
    required int? selectedRowIndex,
    String automationClipSnapshot = '',
  }) {
    final out = StringBuffer();
    final validClipIndices =
        selectedClipIndices.where((i) => i >= 0).toSet().toList()..sort();

    out.writeln('selected_row_index=${selectedRowIndex ?? -1}');
    out.writeln('selected_clip_indices=${validClipIndices.join(",")}');
    out.writeln('primary_selected_clip_index=$primarySelectedClipIndex');
    out.writeln(
      'master_automation_targets=${_automationTargetsSnapshotForMaster(project)}',
    );
    if (selectedRowIndex != null &&
        selectedRowIndex >= 0 &&
        selectedRowIndex < project.rows.length) {
      final row = project.rows[selectedRowIndex];
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
        'selected_clip[$clipIndex]{row=${clip.rowIndex},clip_kind=${clip.clipKind.wireName},start_ms=${rawStartMs.toStringAsFixed(1)},end_ms=${rawEndMs.toStringAsFixed(1)},file=$fileName,label=${clip.label}}',
      );
    }

    return out.toString().trim();
  }
}
