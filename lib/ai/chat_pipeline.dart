import 'dart:math' as math;

import 'cloud_llm_service.dart';
import 'project_state_builder.dart';
import 'local_mixing_model.dart';
import 'magnitude_predictor.dart';
import '../models/goal_vector.dart';
import '../models/mixing_result.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/models/project_state.dart';

class ChatPipeline {
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
    bool autoApplyProposals = false,
  }) async {
    final userText = text.trim();
    if (userText.isEmpty) {
      return const ChatPipelineResult.message(
        "Let me know what you would like to change, and I'll do my best to help.",
      );
    }

    // Quick local: role labeling
    final override = _parseRoleOverride(userText);
    if (override != null) {
      _roleOverrides[override.rowIndex] = override.role;
      final msg =
          "Got it — I'll treat Track ${override.rowIndex + 1} as **${override.role}**.";
      _push('user', userText);
      _push('assistant', msg);
      return ChatPipelineResult.message(msg);
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
      print("building project");
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

      // final hasAudio = audioTracks.isNotEmpty;
      final hasAudio = project.rows.any((r) => r.hasAudio);
      print("sending to LLM");

      // 2) Ask LLM (do NOT push userText yet to avoid duplicating inside request)
      final llmRes = await llm.send(
        conversation: _conversation,
        userText: userText,
        projectSnapshot: snapshot,
        pendingMix: _pendingMix,
      );
      final llmMeta = <String, dynamic>{
        'tool': llmRes.toolName,
        if (llmRes.toolArgs != null) 'tool_args': llmRes.toolArgs,
      };

      print("LLM done");

      // 2.1) Informational tool call: always respond, regardless of audio
      if (llmRes.toolName == 'informational_response') {
        final args = llmRes.toolArgs ?? {};
        print("info");
        if (args['cancels_pending'] == true) {
          print("canceled pending mix");
          _pendingMix = null;
        }

        final msg = llmRes.text!.trim();
        _push('user', userText);
        _push('assistant', msg);
        return ChatPipelineResult.message(msg, meta: llmMeta);
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

      final args = Map<String, dynamic>.from(llmRes.toolArgs!);

      final List<Map<String, dynamic>> actions = (args['actions'] is List)
          ? (args['actions'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : const [];

      final String assistantMessage =
          (args['assistant_message']?.toString().trim().isNotEmpty == true)
              ? args['assistant_message'].toString().trim()
              : '';

      final bool asksPermission = args['asks_permission'] == true;

      final String rawMode =
          (args['mode'] ?? 'propose').toString().toLowerCase();
      final bool strict = rawMode == 'execute';
      final modelMeta = <String, dynamic>{
        ...llmMeta,
        'mode': rawMode,
        'assistant_message': assistantMessage,
        'llm_actions': actions,
        'learned_magnitude_enabled': magnitudePredictor.isEnabled,
        'learned_magnitude_ready': magnitudePredictor.isReady,
      };

      // Collect a merged mix result across all calls
      final List<MixAction> mergedActions = [];
      final List<String> mergedNotes = [];
      bool fallbackUsed = false;
      final Set<String> fallbackReasons = <String>{};

      for (final action in actions) {
        // Safety: each action MUST have a goal
        if (!action.containsKey('goal')) continue;

        GoalVector goal;
        try {
          final goalJson = Map<String, dynamic>.from(action['goal'] as Map);
          goal = GoalVector.fromJson(goalJson, userText: userText);
        } catch (_) {
          continue; // skip malformed action
        }

        final mix = mixModel.run(
            project: project,
            goal: goal,
            strict: strict,
            roleOverrides: _roleOverrides);

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
      if (fallbackUsed) {
        if (!magnitudePredictor.isEnabled) {
          mergedNotes
              .add('Using heuristic magnitudes (learned model disabled).');
        } else {
          mergedNotes.add(
              'Using heuristic magnitudes fallback for this request (${fallbackReasons.join(', ')}).');
        }
      }

      // We only push user once (your original behavior)
      _push('user', userText);

      if (mergedActions.isEmpty) {
        final msg = assistantMessage.isNotEmpty
            ? _appendNotes(assistantMessage, mergedNotes)
            : "No mix changes were applied.";

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

        _push('assistant', msg);
        return ChatPipelineResult.mix(mergedMix, msg, meta: modelMeta);
      }

      // Otherwise this is a PROPOSAL (store pending + ask permission)
      if (autoApplyProposals) {
        final msg = _appendNotes(
            assistantMessage.isNotEmpty ? assistantMessage : mergedMix.summary,
            mergedMix.notes);

        _push('assistant', msg);
        return ChatPipelineResult.mix(mergedMix, msg, meta: modelMeta);
      }

      _pendingMix = mergedMix;

      // Centralized proposal phrasing
      String msg =
          assistantMessage.isNotEmpty ? assistantMessage : mergedMix.summary;

      msg = _appendNotes(msg, mergedMix.notes);

      if (!asksPermission) {
        msg = "$msg\n\nApply these changes? (yes / no)";
      }

      _push('assistant', msg);
      return ChatPipelineResult.message(msg, meta: modelMeta);
    } finally {
      onThinkingChanged?.call(false);
    }
  }

  /// Call this AFTER your UI successfully applies a mix,
  /// so the assistant remembers what it changed.
  void recordAppliedMix(MixingResult mix) {
    if (mix.isNoOp || mix.actions.isEmpty) return;
    final msg = "Applied: ${mix.summary}";
    _push('assistant', msg);
  }

  void _push(String role, String content) {
    _conversation.add({'role': role, 'content': content});
    const max = 8;
    if (_conversation.length > max) {
      _conversation.removeRange(0, _conversation.length - max);
    }
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

  bool _looksLikeUndo(String t) {
    final s = t.toLowerCase();
    return s.contains('undo') || s.contains('revert') || s.contains('go back');
  }

  _RoleOverride? _parseRoleOverride(String text) {
    final m =
        RegExp(r'(track|row)\s*(\d+)\s*(is|=|:)\s*(.+)$', caseSensitive: false)
            .firstMatch(text);
    if (m == null) return null;
    final n = int.tryParse(m.group(2) ?? '');
    if (n == null || n <= 0) return null;

    final rhs = (m.group(4) ?? '').toLowerCase();
    String? role;

    if (rhs.contains('vocal') || rhs.contains('lead') || rhs.contains('vox'))
      role = 'vocals';
    else if (rhs.contains('drum') ||
        rhs.contains('kick') ||
        rhs.contains('snare') ||
        rhs.contains('hat'))
      role = 'drums';
    else if (rhs.contains('bass'))
      role = 'bass';
    else if (rhs.contains('guitar'))
      role = 'guitar';
    else if (rhs.contains('synth') ||
        rhs.contains('keys') ||
        rhs.contains('piano')) role = 'synth';

    if (role == null) return null;
    return _RoleOverride(rowIndex: n - 1, role: role);
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
        'fx=[$fx]', // TODO: paste all parameters within each fx rather than just name
      );
    }

    return b.toString().trim();
  }
}

class _RoleOverride {
  final int rowIndex;
  final String role;
  _RoleOverride({required this.rowIndex, required this.role});
}
