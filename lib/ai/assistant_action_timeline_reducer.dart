import 'dart:math' as math;

import 'package:mixroom/ai/assistant_action_utils.dart';
import 'package:mixroom/models/mixing_result.dart';
import 'package:mixroom/models/models.dart';

class TimelineAutomationClip {
  final String id;
  final int rowIndex;
  final String targetId;
  final String patternId;
  final double startMs;
  final double lengthMs;
  final bool muted;
  final List<AutomationPoint> points;

  const TimelineAutomationClip({
    required this.id,
    required this.rowIndex,
    required this.targetId,
    this.patternId = '',
    required this.startMs,
    required this.lengthMs,
    required this.muted,
    required this.points,
  });

  TimelineAutomationClip copyWith({
    String? id,
    int? rowIndex,
    String? targetId,
    String? patternId,
    double? startMs,
    double? lengthMs,
    bool? muted,
    List<AutomationPoint>? points,
  }) {
    return TimelineAutomationClip(
      id: id ?? this.id,
      rowIndex: rowIndex ?? this.rowIndex,
      targetId: targetId ?? this.targetId,
      patternId: patternId ?? this.patternId,
      startMs: startMs ?? this.startMs,
      lengthMs: lengthMs ?? this.lengthMs,
      muted: muted ?? this.muted,
      points: points ??
          this
              .points
              .map((p) => AutomationPoint(x: p.x, volume: p.volume))
              .toList(growable: false),
    );
  }
}

class TimelineClip {
  final String id;
  final bool isMidi;
  final int rowIndex;
  final double startMs;
  final double sourceDurationMs;
  final double trimStartMs;
  final double trimEndMs;
  final double gain;
  final String label;
  final bool tempoFollow;
  final double? detectedTempoBpm;
  final List<MidiNote> midiNotes;

  const TimelineClip({
    required this.id,
    required this.isMidi,
    required this.rowIndex,
    required this.startMs,
    required this.sourceDurationMs,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.gain,
    required this.label,
    required this.tempoFollow,
    required this.detectedTempoBpm,
    required this.midiNotes,
  });

  double get localDurationMs =>
      (trimEndMs - trimStartMs).clamp(0.0, 1.0e12).toDouble();

  double get endMs => startMs + localDurationMs;

  TimelineClip copyWith({
    String? id,
    bool? isMidi,
    int? rowIndex,
    double? startMs,
    double? sourceDurationMs,
    double? trimStartMs,
    double? trimEndMs,
    double? gain,
    String? label,
    bool? tempoFollow,
    double? detectedTempoBpm,
    bool clearDetectedTempoBpm = false,
    List<MidiNote>? midiNotes,
  }) {
    return TimelineClip(
      id: id ?? this.id,
      isMidi: isMidi ?? this.isMidi,
      rowIndex: rowIndex ?? this.rowIndex,
      startMs: startMs ?? this.startMs,
      sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: trimEndMs ?? this.trimEndMs,
      gain: gain ?? this.gain,
      label: label ?? this.label,
      tempoFollow: tempoFollow ?? this.tempoFollow,
      detectedTempoBpm: clearDetectedTempoBpm
          ? null
          : (detectedTempoBpm ?? this.detectedTempoBpm),
      midiNotes: midiNotes ??
          this.midiNotes.map((n) => n.copy()).toList(growable: false),
    );
  }
}

class TimelineActionState {
  final double projectTempoBpm;
  final List<TimelineClip> clips;
  final Map<String, List<AutomationPoint>> automationLanePoints;
  final Map<String, List<TimelineAutomationClip>> automationClips;
  final Map<int, String> roleOverrides;
  final List<int> selectedClipIndices;
  final int primarySelectedClipIndex;
  final int? selectedRowIndex;
  final String? activeTutorialTarget;
  final List<String> tutorialMessages;
  final String? clarifyQuestion;
  final List<String> clarifyOptions;

  const TimelineActionState({
    required this.projectTempoBpm,
    required this.clips,
    required this.automationLanePoints,
    required this.automationClips,
    required this.roleOverrides,
    required this.selectedClipIndices,
    required this.primarySelectedClipIndex,
    required this.selectedRowIndex,
    required this.activeTutorialTarget,
    required this.tutorialMessages,
    required this.clarifyQuestion,
    required this.clarifyOptions,
  });

  factory TimelineActionState.empty({
    double projectTempoBpm = 120.0,
    List<TimelineClip> clips = const <TimelineClip>[],
    List<int> selectedClipIndices = const <int>[],
    int primarySelectedClipIndex = -1,
    int? selectedRowIndex,
  }) {
    return TimelineActionState(
      projectTempoBpm: projectTempoBpm,
      clips: clips,
      automationLanePoints: const <String, List<AutomationPoint>>{},
      automationClips: const <String, List<TimelineAutomationClip>>{},
      roleOverrides: const <int, String>{},
      selectedClipIndices: selectedClipIndices,
      primarySelectedClipIndex: primarySelectedClipIndex,
      selectedRowIndex: selectedRowIndex,
      activeTutorialTarget: null,
      tutorialMessages: const <String>[],
      clarifyQuestion: null,
      clarifyOptions: const <String>[],
    );
  }

  TimelineActionState copyWith({
    double? projectTempoBpm,
    List<TimelineClip>? clips,
    Map<String, List<AutomationPoint>>? automationLanePoints,
    Map<String, List<TimelineAutomationClip>>? automationClips,
    Map<int, String>? roleOverrides,
    List<int>? selectedClipIndices,
    int? primarySelectedClipIndex,
    int? selectedRowIndex,
    bool clearSelectedRow = false,
    String? activeTutorialTarget,
    bool clearTutorialTarget = false,
    List<String>? tutorialMessages,
    String? clarifyQuestion,
    bool clearClarifyQuestion = false,
    List<String>? clarifyOptions,
  }) {
    return TimelineActionState(
      projectTempoBpm: projectTempoBpm ?? this.projectTempoBpm,
      clips: clips ?? this.clips,
      automationLanePoints: automationLanePoints ?? this.automationLanePoints,
      automationClips: automationClips ?? this.automationClips,
      roleOverrides: roleOverrides ?? this.roleOverrides,
      selectedClipIndices: selectedClipIndices ?? this.selectedClipIndices,
      primarySelectedClipIndex:
          primarySelectedClipIndex ?? this.primarySelectedClipIndex,
      selectedRowIndex:
          clearSelectedRow ? null : (selectedRowIndex ?? this.selectedRowIndex),
      activeTutorialTarget: clearTutorialTarget
          ? null
          : (activeTutorialTarget ?? this.activeTutorialTarget),
      tutorialMessages: tutorialMessages ?? this.tutorialMessages,
      clarifyQuestion: clearClarifyQuestion
          ? null
          : (clarifyQuestion ?? this.clarifyQuestion),
      clarifyOptions: clarifyOptions ?? this.clarifyOptions,
    );
  }
}

class AssistantActionTimelineReducer {
  static TimelineActionState applyActions(
    TimelineActionState state,
    List<AssistantAction> actions,
  ) {
    var working = state.copyWith(
      clips: state.clips.map((c) => c.copyWith()).toList(growable: true),
      automationLanePoints: _copyLanePoints(state.automationLanePoints),
      automationClips: _copyAutomationClips(state.automationClips),
      roleOverrides: Map<int, String>.from(state.roleOverrides),
      selectedClipIndices: List<int>.from(state.selectedClipIndices),
      tutorialMessages: List<String>.from(state.tutorialMessages),
      clarifyOptions: List<String>.from(state.clarifyOptions),
    );

    for (final action in actions) {
      final type = action.type.trim().toLowerCase();
      final data = AssistantActionUtils.toActionMap(action.data);
      switch (type) {
        case 'tutorial':
          working = _applyTutorial(working, data);
          break;
        case 'clarify':
          working = _applyClarify(working, data);
          break;
        case 'project_edit':
          working = _applyProjectEdit(working, data);
          break;
        case 'sample_insert':
          working = _applySampleInsert(working, data);
          break;
        case 'clip_edit':
          working = _applyClipEdit(working, data);
          break;
        case 'automation_edit':
          working = _applyAutomationEdit(working, data);
          break;
        case 'midi_compose':
          working = _applyMidiCompose(working, data);
          break;
        case 'stem_separate':
          working = _applyStemSeparate(working, data);
          break;
        case 'role_override':
          working = _applyRoleOverride(working, data);
          break;
        default:
          break;
      }
    }

    return working;
  }

  static TimelineActionState _applyTutorial(
    TimelineActionState state,
    Map<String, dynamic> data,
  ) {
    final messages = List<String>.from(state.tutorialMessages);
    final steps = (data['steps'] as List?) ?? const [];
    if (steps.isNotEmpty) {
      String? lastTarget;
      for (final raw in steps) {
        final m = AssistantActionUtils.toActionMap(raw);
        final text = (m['text'] ?? '').toString().trim();
        if (text.isNotEmpty) messages.add(text);
        final target = AssistantActionUtils.normalizeTutorialTargetId(
          (m['target_id'] ?? '').toString(),
        );
        if (target != null && target.trim().isNotEmpty) {
          lastTarget = target;
        }
      }
      return state.copyWith(
        tutorialMessages: messages,
        activeTutorialTarget: lastTarget,
      );
    }

    final singleText = (data['text'] ?? '').toString().trim();
    if (singleText.isNotEmpty) messages.add(singleText);
    final target = AssistantActionUtils.normalizeTutorialTargetId(
      (data['target_id'] ?? '').toString(),
    );
    return state.copyWith(
      tutorialMessages: messages,
      activeTutorialTarget: target,
    );
  }

  static TimelineActionState _applyClarify(
    TimelineActionState state,
    Map<String, dynamic> data,
  ) {
    final q = (data['question'] ?? '').toString().trim();
    final optionsRaw = (data['options'] as List?) ?? const [];
    final options = optionsRaw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    return state.copyWith(
      clarifyQuestion: q.isEmpty ? null : q,
      clarifyOptions: options,
    );
  }

  static TimelineActionState _applyProjectEdit(
    TimelineActionState state,
    Map<String, dynamic> data,
  ) {
    final target = AssistantActionUtils.toActionMap(data['target']);
    final operation = (data['operation'] ?? '').toString().trim().toLowerCase();
    if (operation != 'set_tempo') return state;
    final tempo = AssistantActionUtils.toActionDouble(
      data['tempo_bpm'] ?? target['tempo_bpm'] ?? data['bpm'] ?? target['bpm'],
    );
    if (tempo == null || !tempo.isFinite || tempo <= 0.0) return state;
    return state.copyWith(
      projectTempoBpm: tempo.clamp(20.0, 999.0).toDouble(),
    );
  }

  static TimelineActionState _applySampleInsert(
    TimelineActionState state,
    Map<String, dynamic> data,
  ) {
    final operation = (data['operation'] ?? '').toString().trim().toLowerCase();
    if (operation != 'insert_audio_clips' &&
        operation != 'insert_audio_clip' &&
        operation != 'replace_audio_clips') {
      return state;
    }
    final rawItems = data['items'];
    final items = <Map<String, dynamic>>[];
    if (rawItems is List && rawItems.isNotEmpty) {
      for (final raw in rawItems) {
        final item = AssistantActionUtils.toActionMap(raw);
        if (item.isNotEmpty) items.add(item);
      }
    } else {
      items.add(data);
    }
    if (items.isEmpty) return state;

    final nextClips = List<TimelineClip>.from(state.clips);
    final nextSelected = List<int>.from(state.selectedClipIndices);
    var nextPrimary = state.primarySelectedClipIndex;
    final nextRow = state.selectedRowIndex ?? 0;

    List<int> resolveTargetIndices(Map<String, dynamic> item) {
      final target = AssistantActionUtils.toActionMap(item['target']);
      final out = <int>{};

      void addIndex(int? idx) {
        if (idx != null && idx >= 0 && idx < nextClips.length) {
          final clip = nextClips[idx];
          if (!clip.isMidi) out.add(idx);
        }
      }

      final directListRaw =
          (item['clip_indices'] as List?) ?? (target['clip_indices'] as List?);
      if (directListRaw != null) {
        for (final raw in directListRaw) {
          addIndex(AssistantActionUtils.toActionInt(raw));
        }
      }

      final directIndex = AssistantActionUtils.toActionInt(
            item['clip_index'] ?? target['clip_index'],
          ) ??
          AssistantActionUtils.toActionInt(
            item['clip'] ?? target['clip'],
          );
      addIndex(directIndex);

      final scope = (target['scope'] ?? item['scope'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (scope == 'selected' || scope == 'selection') {
        for (final idx in state.selectedClipIndices) {
          addIndex(idx);
        }
        addIndex(state.primarySelectedClipIndex);
      } else if (scope == 'all' || scope == 'all_audio') {
        for (int i = 0; i < nextClips.length; i++) {
          addIndex(i);
        }
      }

      final rowIndex = AssistantActionUtils.toActionInt(
        item['row_index'] ?? target['row_index'],
      );
      final fileContains =
          (item['file_name_contains'] ?? target['file_name_contains'])
              ?.toString()
              .trim()
              .toLowerCase();
      final labelContains = (item['label_contains'] ?? target['label_contains'])
          ?.toString()
          .trim()
          .toLowerCase();
      if (rowIndex != null ||
          (fileContains?.isNotEmpty ?? false) ||
          (labelContains?.isNotEmpty ?? false)) {
        for (int i = 0; i < nextClips.length; i++) {
          final clip = nextClips[i];
          if (clip.isMidi) continue;
          if (rowIndex != null && clip.rowIndex != rowIndex) continue;
          if (fileContains != null &&
              fileContains.isNotEmpty &&
              !clip.label.toLowerCase().contains(fileContains)) {
            continue;
          }
          if (labelContains != null &&
              labelContains.isNotEmpty &&
              !clip.label.toLowerCase().contains(labelContains)) {
            continue;
          }
          out.add(i);
        }
      }

      if (out.isEmpty) {
        for (final idx in state.selectedClipIndices) {
          addIndex(idx);
        }
        addIndex(state.primarySelectedClipIndex);
      }

      final sorted = out.toList()..sort();
      return sorted;
    }

    for (final item in items) {
      final target = AssistantActionUtils.toActionMap(item['target']);
      final libraryPath = (item['library_path'] ??
              target['library_path'] ??
              item['asset_path'] ??
              target['asset_path'])
          .toString()
          .trim();
      final label =
          libraryPath.isEmpty ? 'Library Sample' : libraryPath.split('/').last;

      if (operation == 'replace_audio_clips') {
        final targetIndices = resolveTargetIndices(item);
        if (targetIndices.isEmpty) continue;
        for (final idx in targetIndices) {
          final clip = nextClips[idx];
          nextClips[idx] = clip.copyWith(
            label: label,
          );
        }
        nextSelected
          ..clear()
          ..addAll(targetIndices);
        nextPrimary = targetIndices.isEmpty ? nextPrimary : targetIndices.last;
        continue;
      }

      final row = AssistantActionUtils.toActionInt(
            item['row_index'] ?? target['row_index'],
          ) ??
          nextRow;
      final repeatCountHint = AssistantActionUtils.toActionInt(
            item['repeat_count'] ??
                target['repeat_count'] ??
                item['copies'] ??
                target['copies'] ??
                item['count'] ??
                target['count'],
          ) ??
          1;
      final startMs = AssistantActionUtils.resolveMoveMusicalStartMs(
            data: item,
            target: target,
            bpm: state.projectTempoBpm,
          ) ??
          AssistantActionUtils.toActionDouble(
            item['start_ms'] ?? target['start_ms'],
          ) ??
          AssistantActionUtils.defaultSampleInsertStartMs(
            libraryPath,
            bpm: state.projectTempoBpm,
          ) ??
          0.0;
      final stepMs = AssistantActionUtils.resolveMoveMusicalDeltaMs(
            data: item,
            target: target,
            bpm: state.projectTempoBpm,
          ) ??
          AssistantActionUtils.toActionDouble(
            item['step_ms'] ??
                target['step_ms'] ??
                item['spacing_ms'] ??
                target['spacing_ms'],
          ) ??
          AssistantActionUtils.defaultSampleInsertStepMs(
            libraryPath,
            bpm: state.projectTempoBpm,
            repeatCount: repeatCountHint,
          ) ??
          1000.0;
      final repeatCount = AssistantActionUtils.resolvePlacementRepeatCount(
        data: item,
        target: target,
        bpm: state.projectTempoBpm,
        startMs: startMs,
        stepMs: stepMs,
        preferSpanCoverageOverExplicitCount: true,
      );
      final rowStep = AssistantActionUtils.toActionInt(
            item['delta_rows'] ??
                target['delta_rows'] ??
                item['row_delta'] ??
                target['row_delta'] ??
                item['step_rows'] ??
                target['step_rows'],
          ) ??
          0;
      for (int copyIndex = 0; copyIndex < repeatCount; copyIndex++) {
        final clipStartMs = math.max(0.0, startMs + (stepMs * copyIndex));
        final clipRow = (row + (rowStep * copyIndex)).clamp(0, 1024);
        final clip = TimelineClip(
          id: 'sample_${nextClips.length}_${clipRow}_${clipStartMs.round()}_$copyIndex',
          isMidi: false,
          rowIndex: clipRow,
          startMs: clipStartMs,
          sourceDurationMs: 1000.0,
          trimStartMs: 0.0,
          trimEndMs: 1000.0,
          gain: 1.0,
          label: label,
          tempoFollow: false,
          detectedTempoBpm: null,
          midiNotes: const <MidiNote>[],
        );
        nextClips.add(clip);
        final clipIndex = nextClips.length - 1;
        nextSelected
          ..clear()
          ..add(clipIndex);
        nextPrimary = clipIndex;
      }
    }

    return state.copyWith(
      clips: nextClips,
      selectedClipIndices: nextSelected,
      primarySelectedClipIndex: nextPrimary,
      selectedRowIndex: nextPrimary >= 0 && nextPrimary < nextClips.length
          ? nextClips[nextPrimary].rowIndex
          : state.selectedRowIndex,
    );
  }

  static TimelineActionState _applyClipEdit(
    TimelineActionState state,
    Map<String, dynamic> data,
  ) {
    final rawOperation = (data['operation'] ?? '').toString();
    final operation = AssistantActionUtils.normalizeClipEditOperation(
      rawOperation.trim().toLowerCase(),
    );
    if (operation.isEmpty) return state;

    switch (operation) {
      case 'trim':
      case 'auto_trim':
      case 'cut':
      case 'stretch':
      case 'move':
      case 'tempo_follow':
      case 'auto_bpm_align':
      case 'align_first_sound':
      case 'tempo_detect_set_project':
      case 'duplicate':
      case 'glue':
      case 'delete':
      case 'dialog_cleanup':
      case 'dialog_remove_range':
      case 'dialog_tighten_pauses':
      case 'dialog_lift_quiet':
        return _applyClipOperation(state, data, operation);
      default:
        return state;
    }
  }

  static TimelineActionState _applyClipOperation(
    TimelineActionState state,
    Map<String, dynamic> data,
    String operation,
  ) {
    final target = AssistantActionUtils.toActionMap(data['target']);
    final clips = List<TimelineClip>.from(state.clips);

    bool isAudioAt(int i) => i >= 0 && i < clips.length && !clips[i].isMidi;

    List<int> resolveTargetClipIndices({
      bool requireAudio = false,
      bool requireMidi = false,
    }) {
      final out = <int>[];
      bool valid(int idx) {
        if (idx < 0 || idx >= clips.length) return false;
        if (requireAudio && clips[idx].isMidi) return false;
        if (requireMidi && !clips[idx].isMidi) return false;
        return true;
      }

      void add(int? idx) {
        if (idx != null && valid(idx) && !out.contains(idx)) out.add(idx);
      }

      final explicitList =
          (data['clip_indices'] as List?) ?? (target['clip_indices'] as List?);
      if (explicitList != null) {
        for (final raw in explicitList) {
          add(AssistantActionUtils.toActionInt(raw));
        }
      }

      add(AssistantActionUtils.toActionInt(data['clip_index']) ??
          AssistantActionUtils.toActionInt(target['clip_index']));

      final scope = (target['scope'] ?? data['scope'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (scope == 'selected' || scope == 'selection') {
        for (final idx in state.selectedClipIndices) {
          add(idx);
        }
        add(state.primarySelectedClipIndex);
      } else if (scope == 'all' || scope == 'all_audio') {
        for (int i = 0; i < clips.length; i++) {
          add(i);
        }
      }

      final row = AssistantActionUtils.toActionInt(
        data['row_index'] ?? target['row_index'],
      );
      if (row != null) {
        for (int i = 0; i < clips.length; i++) {
          if (clips[i].rowIndex == row) add(i);
        }
      }

      if (out.isEmpty) {
        for (final idx in state.selectedClipIndices) {
          add(idx);
        }
        add(state.primarySelectedClipIndex);
      }

      if (out.isEmpty && clips.isNotEmpty) {
        for (int i = 0; i < clips.length; i++) {
          if (valid(i)) {
            out.add(i);
            break;
          }
        }
      }
      out.sort();
      return out;
    }

    int? resolveSingleClipIndex({
      bool requireAudio = false,
      bool requireMidi = false,
    }) {
      final list = resolveTargetClipIndices(
        requireAudio: requireAudio,
        requireMidi: requireMidi,
      );
      return list.isEmpty ? null : list.first;
    }

    TimelineClip clampTrim(
        TimelineClip clip, double nextStart, double nextEnd) {
      final max = clip.sourceDurationMs.clamp(1.0, 1e12).toDouble();
      final minGap = math.min(50.0, max);
      final safeStart =
          nextStart.clamp(0.0, math.max(0.0, max - minGap)).toDouble();
      final safeEnd = nextEnd.clamp(safeStart + minGap, max).toDouble();
      return clip.copyWith(trimStartMs: safeStart, trimEndMs: safeEnd);
    }

    if (operation == 'trim' || operation == 'auto_trim') {
      final indices = resolveTargetClipIndices(requireAudio: true);
      if (indices.isEmpty) return state.copyWith(clips: clips);
      final sideHint = (data['trim_side'] ??
              target['trim_side'] ??
              data['side'] ??
              target['side'] ??
              '')
          .toString()
          .toLowerCase();
      final trimStartOnly =
          sideHint.contains('start') || sideHint.contains('left');
      final trimEndOnly =
          sideHint.contains('end') || sideHint.contains('right');

      for (final idx in indices) {
        if (!isAudioAt(idx)) continue;
        final clip = clips[idx];
        final oldStart = clip.trimStartMs;
        final oldEnd = clip.trimEndMs;

        double nextStart = oldStart;
        double nextEnd = oldEnd;
        if (operation == 'trim') {
          final explicitStart = AssistantActionUtils.toActionDouble(
              data['trim_start_ms'] ?? target['trim_start_ms']);
          final explicitEnd = AssistantActionUtils.toActionDouble(
              data['trim_end_ms'] ?? target['trim_end_ms']);
          final deltaStart = AssistantActionUtils.toActionDouble(
            data['delta_trim_start_ms'] ?? target['delta_trim_start_ms'],
          );
          final deltaEnd = AssistantActionUtils.toActionDouble(
            data['delta_trim_end_ms'] ?? target['delta_trim_end_ms'],
          );
          if (explicitStart != null) {
            nextStart = explicitStart;
          } else if (deltaStart != null) {
            nextStart += deltaStart;
          } else if (!trimEndOnly) {
            nextStart += 120.0;
          }
          if (explicitEnd != null) {
            nextEnd = explicitEnd;
          } else if (deltaEnd != null) {
            nextEnd += deltaEnd;
          } else if (trimEndOnly ||
              (!trimStartOnly && oldEnd - oldStart > 800.0)) {
            nextEnd -= 120.0;
          }
        } else {
          final pad = AssistantActionUtils.toActionDouble(
                data['padding_ms'] ?? target['padding_ms'],
              ) ??
              50.0;
          nextStart = oldStart + pad;
          nextEnd = oldEnd - pad;
        }

        final clamped = clampTrim(clip, nextStart, nextEnd);
        final preserve = AssistantActionUtils.toActionBool(
          data['preserve_content_position'] ??
              target['preserve_content_position'],
          fallback: true,
        );
        if (preserve) {
          final deltaStartMs = clamped.trimStartMs - oldStart;
          clips[idx] = clamped.copyWith(
              startMs: math.max(0.0, clip.startMs + deltaStartMs));
        } else {
          clips[idx] = clamped;
        }
      }
      return state.copyWith(clips: clips);
    }

    if (operation == 'cut') {
      final idx = resolveSingleClipIndex();
      if (idx == null || idx < 0 || idx >= clips.length) {
        return state.copyWith(clips: clips);
      }
      final clip = clips[idx];
      final cutMs = AssistantActionUtils.toActionDouble(
              data['cut_ms'] ?? data['time_ms']) ??
          (clip.startMs + clip.endMs) * 0.5;
      if (cutMs <= clip.startMs + 1.0 || cutMs >= clip.endMs - 1.0) {
        return state.copyWith(clips: clips);
      }
      final ratio = ((cutMs - clip.startMs) / (clip.endMs - clip.startMs))
          .clamp(0.0, 1.0);
      final cutTrim =
          clip.trimStartMs + (clip.trimEndMs - clip.trimStartMs) * ratio;
      final left = clip.copyWith(trimEndMs: cutTrim);
      final right = clip.copyWith(
        id: '${clip.id}:cut:${cutMs.round()}',
        startMs: cutMs,
        trimStartMs: cutTrim,
      );
      clips[idx] = left;
      clips.insert(idx + 1, right);
      return state.copyWith(clips: clips);
    }

    if (operation == 'stretch') {
      final idx = resolveSingleClipIndex();
      if (idx == null || idx < 0 || idx >= clips.length) {
        return state.copyWith(clips: clips);
      }
      final clip = clips[idx];
      final oldDur = math.max(1.0, clip.localDurationMs);
      final explicit = AssistantActionUtils.toActionDouble(
        data['timeline_duration_ms'] ??
            data['duration_ms'] ??
            target['timeline_duration_ms'] ??
            target['duration_ms'],
      );
      final delta = AssistantActionUtils.toActionDouble(
        data['delta_duration_ms'] ?? target['delta_duration_ms'],
      );
      final factor = AssistantActionUtils.toActionDouble(
          data['factor'] ?? target['factor']);
      final nextDur = explicit ??
          ((delta != null)
              ? oldDur + delta
              : ((factor != null) ? oldDur * factor : oldDur));
      final safeDur = nextDur.clamp(60.0, clip.sourceDurationMs).toDouble();
      final nextTrimEnd = clip.trimStartMs + safeDur;
      clips[idx] = clampTrim(clip, clip.trimStartMs, nextTrimEnd);
      return state.copyWith(clips: clips);
    }

    if (operation == 'move') {
      final indices = resolveTargetClipIndices();
      if (indices.isEmpty) return state.copyWith(clips: clips);
      final explicitStart = AssistantActionUtils.resolveMoveMusicalStartMs(
            data: data,
            target: target,
            bpm: state.projectTempoBpm,
          ) ??
          AssistantActionUtils.toActionDouble(
            data['new_start_ms'] ??
                target['new_start_ms'] ??
                data['start_ms'] ??
                target['start_ms'],
          );
      final deltaMs = AssistantActionUtils.resolveMoveMusicalDeltaMs(
            data: data,
            target: target,
            bpm: state.projectTempoBpm,
          ) ??
          AssistantActionUtils.toActionDouble(
            data['delta_ms'] ??
                target['delta_ms'] ??
                data['offset_ms'] ??
                target['offset_ms'] ??
                data['shift_ms'] ??
                target['shift_ms'],
          );
      final direction = (data['direction'] ?? target['direction'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final rowDest = AssistantActionUtils.toActionInt(
        data['new_row_index'] ?? target['new_row_index'],
      );
      final rowDelta = AssistantActionUtils.toActionInt(
            data['delta_rows'] ?? target['delta_rows'],
          ) ??
          0;
      final stepMs = AssistantActionUtils.toActionDouble(
            data['step_ms'] ?? target['step_ms'],
          ) ??
          (60000.0 / state.projectTempoBpm.clamp(1.0, 320.0));

      double directionalDeltaMs = 0.0;
      int directionalRowDelta = 0;
      if (direction == 'left' ||
          direction == 'earlier' ||
          direction == 'back') {
        directionalDeltaMs = -stepMs.abs();
      } else if (direction == 'right' ||
          direction == 'later' ||
          direction == 'forward') {
        directionalDeltaMs = stepMs.abs();
      } else if (direction == 'up') {
        directionalRowDelta = -1;
      } else if (direction == 'down') {
        directionalRowDelta = 1;
      } else if (direction == 'start' || direction == 'beginning') {
        directionalDeltaMs = -1e15;
      }

      for (final idx in indices) {
        final clip = clips[idx];
        double nextStart = clip.startMs;
        if (explicitStart != null) {
          nextStart = explicitStart;
        } else if (deltaMs != null) {
          nextStart += deltaMs;
        } else {
          nextStart += directionalDeltaMs;
        }
        if (directionalDeltaMs <= -1e14) nextStart = 0.0;

        int nextRow = clip.rowIndex;
        if (rowDest != null) {
          nextRow = rowDest;
        } else if (rowDelta != 0) {
          nextRow += rowDelta;
        } else if (directionalRowDelta != 0) {
          nextRow += directionalRowDelta;
        }
        nextRow = math.max(0, nextRow);
        clips[idx] =
            clip.copyWith(startMs: math.max(0.0, nextStart), rowIndex: nextRow);
      }
      return state.copyWith(clips: clips);
    }

    if (operation == 'tempo_follow' || operation == 'auto_bpm_align') {
      final indices = resolveTargetClipIndices(requireAudio: true);
      for (final idx in indices) {
        if (!isAudioAt(idx)) continue;
        clips[idx] = clips[idx].copyWith(tempoFollow: true);
      }
      var nextTempo = state.projectTempoBpm;
      final explicitTempo = AssistantActionUtils.toActionDouble(
        data['project_tempo_bpm'] ?? target['project_tempo_bpm'],
      );
      if (explicitTempo != null && explicitTempo.isFinite) {
        nextTempo = explicitTempo.clamp(40.0, 240.0).toDouble();
      }
      return state.copyWith(
        clips: clips,
        projectTempoBpm: nextTempo,
      );
    }

    if (operation == 'tempo_detect_set_project') {
      final idx = resolveSingleClipIndex(requireAudio: true);
      if (idx == null || !isAudioAt(idx)) return state.copyWith(clips: clips);
      final clip = clips[idx];
      final detected =
          (clip.detectedTempoBpm ?? 120.0).clamp(40.0, 240.0).toDouble();
      clips[idx] = clip.copyWith(tempoFollow: true, detectedTempoBpm: detected);
      return state.copyWith(
        clips: clips,
        projectTempoBpm: detected,
      );
    }

    if (operation == 'duplicate') {
      final idx = resolveSingleClipIndex();
      if (idx == null || idx < 0 || idx >= clips.length) {
        return state.copyWith(clips: clips);
      }
      final clip = clips[idx];
      final firstPasteStart = AssistantActionUtils.resolveMoveMusicalStartMs(
            data: data,
            target: target,
            bpm: state.projectTempoBpm,
          ) ??
          AssistantActionUtils.toActionDouble(
            data['paste_start_ms'] ??
                target['paste_start_ms'] ??
                data['start_ms'] ??
                target['start_ms'],
          ) ??
          (clip.startMs + clip.localDurationMs);
      final stepMs = AssistantActionUtils.resolveMoveMusicalDeltaMs(
            data: data,
            target: target,
            bpm: state.projectTempoBpm,
          ) ??
          AssistantActionUtils.toActionDouble(
            data['step_ms'] ??
                target['step_ms'] ??
                data['spacing_ms'] ??
                target['spacing_ms'],
          ) ??
          clip.localDurationMs;
      final repeatCount = AssistantActionUtils.resolvePlacementRepeatCount(
        data: data,
        target: target,
        bpm: state.projectTempoBpm,
        startMs: firstPasteStart,
        stepMs: stepMs,
      );
      final baseRow = AssistantActionUtils.toActionInt(
            data['row_index'] ??
                target['row_index'] ??
                data['new_row_index'] ??
                target['new_row_index'],
          ) ??
          clip.rowIndex;
      final rowStep = AssistantActionUtils.toActionInt(
            data['delta_rows'] ??
                target['delta_rows'] ??
                data['row_delta'] ??
                target['row_delta'] ??
                data['step_rows'] ??
                target['step_rows'],
          ) ??
          0;
      for (int copyIndex = 0; copyIndex < repeatCount; copyIndex++) {
        final pasteStart = math.max(
          0.0,
          firstPasteStart + (stepMs * copyIndex),
        );
        final pasteRow = math.max(0, baseRow + (rowStep * copyIndex));
        clips.insert(
          idx + 1 + copyIndex,
          clip.copyWith(
            id: '${clip.id}:dup:${pasteStart.round()}:$copyIndex',
            rowIndex: pasteRow,
            startMs: pasteStart,
          ),
        );
      }
      return state.copyWith(clips: clips);
    }

    if (operation == 'glue') {
      final indices = resolveTargetClipIndices(requireAudio: true);
      if (indices.length < 2) return state.copyWith(clips: clips);
      final selected = indices.where(isAudioAt).toList(growable: false);
      if (selected.length < 2) return state.copyWith(clips: clips);
      final row = clips[selected.first].rowIndex;
      if (selected.any((idx) => clips[idx].rowIndex != row)) {
        return state.copyWith(clips: clips);
      }
      final ordered = List<int>.from(selected)
        ..sort((a, b) => clips[a].startMs.compareTo(clips[b].startMs));
      final startMs = ordered.map((idx) => clips[idx].startMs).reduce(math.min);
      final endMs = ordered.map((idx) => clips[idx].endMs).reduce(math.max);
      final gain =
          ordered.map((idx) => clips[idx].gain).reduce((a, b) => a + b) /
              ordered.length;
      final label =
          (data['label'] ?? target['label'] ?? 'Glued Clip').toString().trim();
      final glued = clips[ordered.first].copyWith(
        id: 'glued_${ordered.map((idx) => clips[idx].id).join("_")}',
        startMs: startMs,
        sourceDurationMs: math.max(50.0, endMs - startMs),
        trimStartMs: 0.0,
        trimEndMs: math.max(50.0, endMs - startMs),
        gain: gain,
        label: label.isEmpty ? 'Glued Clip' : label,
        tempoFollow: false,
        clearDetectedTempoBpm: true,
      );
      for (final idx in ordered.reversed) {
        clips.removeAt(idx);
      }
      final insertAt = ordered.first.clamp(0, clips.length).toInt();
      clips.insert(insertAt, glued);
      return state.copyWith(
        clips: clips,
        selectedClipIndices: <int>[insertAt],
        primarySelectedClipIndex: insertAt,
        selectedRowIndex: row,
      );
    }

    if (operation == 'delete') {
      final indices = resolveTargetClipIndices();
      if (indices.isEmpty) return state.copyWith(clips: clips);
      final descending = indices.toSet().toList()
        ..sort((a, b) => b.compareTo(a));
      for (final idx in descending) {
        if (idx >= 0 && idx < clips.length) {
          clips.removeAt(idx);
        }
      }
      return state.copyWith(clips: clips);
    }

    if (operation == 'dialog_cleanup' ||
        operation == 'dialog_remove_range' ||
        operation == 'dialog_tighten_pauses' ||
        operation == 'dialog_lift_quiet') {
      final indices = resolveTargetClipIndices(requireAudio: true);
      if (indices.isEmpty) return state.copyWith(clips: clips);
      final desc = indices.toSet().toList()..sort((a, b) => b.compareTo(a));
      for (final idx in desc) {
        if (!isAudioAt(idx)) continue;
        final clip = clips[idx];
        if (operation == 'dialog_lift_quiet') {
          final boostDb = AssistantActionUtils.toActionDouble(
                data['boost_db'] ?? target['boost_db'] ?? data['gain_db'],
              ) ??
              4.0;
          final mult = math.pow(10.0, boostDb / 20.0).toDouble();
          final maxGain = (AssistantActionUtils.toActionDouble(
                    data['max_gain'] ?? target['max_gain'],
                  ) ??
                  3.0)
              .clamp(0.0, 3.0)
              .toDouble();
          clips[idx] = clip.copyWith(
              gain: (clip.gain * mult).clamp(0.0, maxGain).toDouble());
          continue;
        }

        var ranges = _extractRangesMs(data, clip);
        if (ranges.isEmpty && operation == 'dialog_cleanup') {
          final center = (clip.startMs + clip.endMs) * 0.5;
          ranges = <MapEntry<double, double>>[
            MapEntry(center - 60.0, center + 60.0),
          ];
        }
        if (ranges.isEmpty && operation == 'dialog_tighten_pauses') {
          final minPause = AssistantActionUtils.toActionDouble(
                data['min_pause_ms'] ?? target['min_pause_ms'],
              ) ??
              260.0;
          if (clip.localDurationMs > minPause * 1.8) {
            final mid = (clip.startMs + clip.endMs) * 0.5;
            ranges = <MapEntry<double, double>>[
              MapEntry(mid - 80.0, mid + 80.0),
            ];
          }
        }
        if (ranges.isEmpty) continue;

        final replacement = _clipAfterRemovingRanges(clip, ranges);
        clips.removeAt(idx);
        clips.insertAll(idx, replacement);
      }
      return state.copyWith(clips: clips);
    }

    return state.copyWith(clips: clips);
  }

  static List<MapEntry<double, double>> _extractRangesMs(
    Map<String, dynamic> data,
    TimelineClip clip,
  ) {
    final target = AssistantActionUtils.toActionMap(data['target']);
    final out = <MapEntry<double, double>>[];
    final clipStart = clip.startMs;
    final clipEnd = clip.endMs;

    bool clipRelativeFrom(Map<String, dynamic> map) {
      final explicit = AssistantActionUtils.toActionBool(
        map['clip_relative'] ??
            map['local_ms'] ??
            map['relative_to_clip'] ??
            map['clip_time'],
        fallback: false,
      );
      if (explicit) return true;
      final domain =
          (map['time_domain'] ?? map['range_domain'] ?? map['domain'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
      return domain == 'clip' ||
          domain == 'local' ||
          domain == 'clip_local' ||
          domain == 'clip_relative';
    }

    void parseFromMap(Map<String, dynamic> map) {
      double? from = AssistantActionUtils.toActionDouble(
        map['from_ms'] ?? map['start_ms'] ?? map['begin_ms'],
      );
      double? to = AssistantActionUtils.toActionDouble(
        map['to_ms'] ?? map['end_ms'],
      );
      final len = AssistantActionUtils.toActionDouble(
          map['length_ms'] ?? map['duration_ms']);
      final at =
          AssistantActionUtils.toActionDouble(map['at_ms'] ?? map['time_ms']);

      if (from == null && at != null && len != null) {
        from = at;
        to = at + len;
      } else if (from != null && to == null && len != null) {
        to = from + len;
      }
      if (from == null || to == null) return;
      if (clipRelativeFrom(map)) {
        from += clipStart;
        to += clipStart;
      }
      if (!from.isFinite || !to.isFinite) return;
      if (to < from) {
        final t = from;
        from = to;
        to = t;
      }
      from = from.clamp(clipStart, clipEnd).toDouble();
      to = to.clamp(clipStart, clipEnd).toDouble();
      if (to - from < 5.0) return;
      out.add(MapEntry(from, to));
    }

    for (final key in const ['ranges', 'regions', 'segments']) {
      final rawList = (data[key] as List?) ?? (target[key] as List?);
      if (rawList == null) continue;
      for (final raw in rawList) {
        parseFromMap(AssistantActionUtils.toActionMap(raw));
      }
    }
    parseFromMap(<String, dynamic>{...target, ...data});
    if (out.isEmpty) return const <MapEntry<double, double>>[];
    out.sort((a, b) => a.key.compareTo(b.key));
    final merged = <MapEntry<double, double>>[];
    double s = out.first.key;
    double e = out.first.value;
    for (int i = 1; i < out.length; i++) {
      final r = out[i];
      if (r.key <= e + 5.0) {
        e = math.max(e, r.value);
      } else {
        merged.add(MapEntry(s, e));
        s = r.key;
        e = r.value;
      }
    }
    merged.add(MapEntry(s, e));
    return merged;
  }

  static List<TimelineClip> _clipAfterRemovingRanges(
    TimelineClip clip,
    List<MapEntry<double, double>> ranges,
  ) {
    if (ranges.isEmpty) return <TimelineClip>[clip];
    final inRanges = ranges
        .map((r) {
          var s = r.key;
          var e = r.value;
          if (s > e) {
            final t = s;
            s = e;
            e = t;
          }
          return MapEntry(
            s.clamp(clip.startMs, clip.endMs).toDouble(),
            e.clamp(clip.startMs, clip.endMs).toDouble(),
          );
        })
        .where((r) => r.value - r.key > 5.0)
        .toList(growable: true);
    if (inRanges.isEmpty) return <TimelineClip>[clip];
    inRanges.sort((a, b) => a.key.compareTo(b.key));

    final merged = <MapEntry<double, double>>[];
    double ms = inRanges.first.key;
    double me = inRanges.first.value;
    for (int i = 1; i < inRanges.length; i++) {
      final r = inRanges[i];
      if (r.key <= me + 5.0) {
        me = math.max(me, r.value);
      } else {
        merged.add(MapEntry(ms, me));
        ms = r.key;
        me = r.value;
      }
    }
    merged.add(MapEntry(ms, me));

    final keepSegments = <MapEntry<double, double>>[];
    double cursor = clip.startMs;
    for (final r in merged) {
      if (r.key > cursor + 5.0) {
        keepSegments.add(MapEntry(cursor, r.key));
      }
      cursor = math.max(cursor, r.value);
    }
    if (cursor < clip.endMs - 5.0) {
      keepSegments.add(MapEntry(cursor, clip.endMs));
    }
    if (keepSegments.isEmpty) return const <TimelineClip>[];

    final out = <TimelineClip>[];
    for (int i = 0; i < keepSegments.length; i++) {
      final seg = keepSegments[i];
      final localStart = clip.trimStartMs + (seg.key - clip.startMs);
      final localEnd = clip.trimStartMs + (seg.value - clip.startMs);
      out.add(
        clip.copyWith(
          id: keepSegments.length > 1 ? '${clip.id}:seg:$i' : clip.id,
          startMs: seg.key,
          trimStartMs: localStart,
          trimEndMs: localEnd,
        ),
      );
    }
    return out;
  }

  static TimelineActionState _applyAutomationEdit(
    TimelineActionState state,
    Map<String, dynamic> data,
  ) {
    final target = AssistantActionUtils.toActionMap(data['target']);
    String operation =
        (data['operation'] ?? '').toString().trim().toLowerCase();
    switch (operation) {
      case 'clone':
      case 'clone_clip':
        operation = 'duplicate_clip';
        break;
    }
    if (operation.isEmpty) return state;

    final row = (AssistantActionUtils.toActionInt(data['row_index']) ??
            AssistantActionUtils.toActionInt(target['row_index']) ??
            state.selectedRowIndex ??
            0)
        .clamp(0, 1024);
    final targetId = (data['automation_target_id'] ??
            data['target_id'] ??
            data['lane_id'] ??
            target['automation_target_id'] ??
            target['target_id'] ??
            target['lane_id'] ??
            'volume')
        .toString()
        .trim();
    final laneKey = '$row::$targetId';

    final lanePoints = _copyLanePoints(state.automationLanePoints);
    final clipMap = _copyAutomationClips(state.automationClips);

    List<AutomationPoint> sanitizePoints(List<AutomationPoint> points) {
      final out = points
          .map((p) => AutomationPoint(
                x: math.max(0.0, p.x),
                volume: p.volume.clamp(0.0, 1.0),
              ))
          .toList(growable: true)
        ..sort((a, b) => a.x.compareTo(b.x));
      if (out.isEmpty) {
        return <AutomationPoint>[AutomationPoint(x: 0.0, volume: 1.0)];
      }
      return out;
    }

    List<AutomationPoint> parsePoints(
      dynamic raw,
      List<AutomationPoint> fallback,
    ) {
      final list = raw is List ? raw : const [];
      final out = <AutomationPoint>[];
      for (final e in list) {
        final m = AssistantActionUtils.toActionMap(e);
        final x = AssistantActionUtils.toActionDouble(
          m['x_ms'] ?? m['x'] ?? m['time_ms'],
        );
        final v = AssistantActionUtils.toActionDouble(
          m['value'] ?? m['volume'] ?? m['normalized'],
        );
        if (x == null || v == null) continue;
        out.add(AutomationPoint(x: x, volume: v.clamp(0.0, 1.0)));
      }
      if (out.isEmpty) return fallback;
      return sanitizePoints(out);
    }

    List<TimelineAutomationClip> clipsForLane() =>
        List<TimelineAutomationClip>.from(
            clipMap[laneKey] ?? const <TimelineAutomationClip>[]);

    String newPatternId() =>
        'pat_${row}_${targetId}_${DateTime.now().microsecondsSinceEpoch}_${clipMap.length}';

    void applySharedPointsToLane(
      List<TimelineAutomationClip> laneClips,
      int sourceIndex,
      List<AutomationPoint> points,
    ) {
      final source = laneClips[sourceIndex];
      final patternId = source.patternId.trim();
      if (patternId.isEmpty) {
        laneClips[sourceIndex] = source.copyWith(points: points);
        return;
      }
      for (int i = 0; i < laneClips.length; i++) {
        final clip = laneClips[i];
        if (clip.patternId.trim() != patternId) continue;
        laneClips[i] = clip.copyWith(points: points);
      }
    }

    int? resolveClipIndex(List<TimelineAutomationClip> clips) {
      final explicit = AssistantActionUtils.toActionInt(
        data['clip_index'] ??
            target['clip_index'] ??
            data['automation_clip_index'] ??
            target['automation_clip_index'],
      );
      if (explicit != null && explicit >= 0 && explicit < clips.length) {
        return explicit;
      }
      final id = (data['clip_id'] ?? target['clip_id'] ?? '').toString().trim();
      if (id.isNotEmpty) {
        final idx = clips.indexWhere((c) => c.id == id);
        if (idx >= 0) return idx;
      }
      final patternId = (data['pattern_id'] ??
              target['pattern_id'] ??
              data['automation_pattern_id'] ??
              target['automation_pattern_id'] ??
              '')
          .toString()
          .trim();
      if (patternId.isNotEmpty) {
        final idx = clips.indexWhere((c) => c.patternId.trim() == patternId);
        if (idx >= 0) return idx;
      }
      final atMs = AssistantActionUtils.toActionDouble(
        data['at_ms'] ??
            target['at_ms'] ??
            data['time_ms'] ??
            target['time_ms'] ??
            data['start_ms'] ??
            target['start_ms'],
      );
      if (atMs != null && atMs.isFinite) {
        for (int i = 0; i < clips.length; i++) {
          final clip = clips[i];
          final endMs = clip.startMs + clip.lengthMs;
          if (atMs >= clip.startMs && atMs <= endMs) {
            return i;
          }
        }
        int nearest = 0;
        double nearestDist = (clips.first.startMs - atMs).abs();
        for (int i = 1; i < clips.length; i++) {
          final dist = (clips[i].startMs - atMs).abs();
          if (dist < nearestDist) {
            nearest = i;
            nearestDist = dist;
          }
        }
        return nearest;
      }
      return clips.isEmpty ? null : clips.length - 1;
    }

    List<AutomationPoint> templatePoints(
      String template,
      double lengthMs, {
      String direction = 'left',
    }) {
      final t = template.trim().toLowerCase();
      final safeLen = lengthMs.clamp(40.0, 1e9).toDouble();
      if (t == 'sidechain' || t == 'sidechain_pump' || t == 'pump') {
        return <AutomationPoint>[
          AutomationPoint(x: 0.0, volume: 1.0),
          AutomationPoint(x: safeLen * 0.08, volume: 0.12),
          AutomationPoint(x: safeLen * 0.35, volume: 0.75),
          AutomationPoint(x: safeLen, volume: 1.0),
        ];
      }
      if (t == 'reverb_tail') {
        return <AutomationPoint>[
          AutomationPoint(x: 0.0, volume: 0.05),
          AutomationPoint(x: safeLen * 0.15, volume: 1.0),
          AutomationPoint(x: safeLen * 0.6, volume: 0.45),
          AutomationPoint(x: safeLen, volume: 0.1),
        ];
      }
      if (t == 'filter_sweep') {
        return <AutomationPoint>[
          AutomationPoint(x: 0.0, volume: 0.0),
          AutomationPoint(x: safeLen, volume: 1.0),
        ];
      }
      if (t == 'auto_pan' ||
          t == 'autopan' ||
          t == 'stereo_motion' ||
          t == 'stereo_direction' ||
          t == 'pan_motion' ||
          t == 'left_right_motion') {
        final startsRight = direction.trim().toLowerCase() == 'right';
        final nearStartSide = startsRight ? 0.84 : 0.16;
        final nearOppositeSide = startsRight ? 0.16 : 0.84;
        final settleSide = startsRight ? 0.74 : 0.26;
        return <AutomationPoint>[
          AutomationPoint(x: 0.0, volume: 0.5),
          AutomationPoint(x: safeLen * 0.16, volume: nearStartSide),
          AutomationPoint(x: safeLen * 0.34, volume: 0.5),
          AutomationPoint(x: safeLen * 0.56, volume: nearOppositeSide),
          AutomationPoint(x: safeLen * 0.78, volume: settleSide),
          AutomationPoint(x: safeLen, volume: 0.5),
        ];
      }
      return <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: 0.5),
        AutomationPoint(x: safeLen, volume: 0.75),
      ];
    }

    if (operation == 'clear') {
      lanePoints[laneKey] = <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: 1.0),
      ];
      return state.copyWith(
          automationLanePoints: lanePoints, automationClips: clipMap);
    }

    if (operation == 'set_points') {
      final fallback = <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: 1.0),
      ];
      final parsed = parsePoints(data['points'], fallback);
      lanePoints[laneKey] = parsed;
      return state.copyWith(
          automationLanePoints: lanePoints, automationClips: clipMap);
    }

    if (operation == 'add_ramp') {
      final existing = List<AutomationPoint>.from(
          lanePoints[laneKey] ?? const <AutomationPoint>[]);
      final from = AssistantActionUtils.toActionDouble(
            data['from_ms'] ?? target['from_ms'] ?? data['start_ms'],
          ) ??
          0.0;
      final to = AssistantActionUtils.toActionDouble(
            data['to_ms'] ?? target['to_ms'] ?? data['end_ms'],
          ) ??
          (from + 1000.0);
      final startV = (AssistantActionUtils.toActionDouble(
                data['start_value'] ?? data['from_value'] ?? data['value'],
              ) ??
              0.75)
          .clamp(0.0, 1.0)
          .toDouble();
      final endV = (AssistantActionUtils.toActionDouble(
                data['end_value'] ?? data['to_value'],
              ) ??
              0.3)
          .clamp(0.0, 1.0)
          .toDouble();
      existing.add(AutomationPoint(x: from, volume: startV));
      existing.add(AutomationPoint(x: math.max(from + 20.0, to), volume: endV));
      lanePoints[laneKey] = sanitizePoints(existing);
      return state.copyWith(
          automationLanePoints: lanePoints, automationClips: clipMap);
    }

    if (operation == 'create_clip' || operation == 'apply_template') {
      final laneClips = clipsForLane();
      final start = AssistantActionUtils.toActionDouble(
            data['start_ms'] ?? target['start_ms'] ?? data['at_ms'],
          ) ??
          0.0;
      final len = (AssistantActionUtils.toActionDouble(
                data['length_ms'] ?? target['length_ms'] ?? data['duration_ms'],
              ) ??
              1000.0)
          .clamp(40.0, 1e9)
          .toDouble();
      final template =
          (data['template'] ?? target['template'] ?? '').toString();
      final direction =
          (data['direction'] ?? target['direction'] ?? 'left').toString();
      final points = parsePoints(
        data['points'],
        templatePoints(template, len, direction: direction),
      );
      if (operation == 'apply_template' &&
          template.trim().toLowerCase() == 'sidechain_from_kick') {
        final sourceIdx = AssistantActionUtils.toActionInt(
          data['source_clip_index'] ?? target['source_clip_index'],
        );
        final source = (sourceIdx != null &&
                sourceIdx >= 0 &&
                sourceIdx < state.clips.length)
            ? state.clips[sourceIdx]
            : null;
        final eventSpacing = (AssistantActionUtils.toActionDouble(
                  data['min_spacing_ms'] ?? target['min_spacing_ms'],
                ) ??
                500.0)
            .clamp(80.0, 2000.0)
            .toDouble();
        final eventCount = (AssistantActionUtils.toActionInt(
                  data['max_events'] ?? target['max_events'],
                ) ??
                4)
            .clamp(1, 64);
        final sourceStart = source?.startMs ?? start;
        final sourceEnd =
            source?.endMs ?? (sourceStart + eventSpacing * eventCount);
        var cursor = sourceStart;
        int created = 0;
        while (cursor < sourceEnd && created < eventCount) {
          laneClips.add(
            TimelineAutomationClip(
              id: 'ac_${row}_${targetId}_${laneClips.length}_${created}_kick',
              rowIndex: row,
              targetId: targetId,
              patternId: '',
              startMs: cursor,
              lengthMs: len,
              muted: false,
              points: templatePoints('sidechain_pump', len),
            ),
          );
          created++;
          cursor += eventSpacing;
        }
      } else {
        laneClips.add(
          TimelineAutomationClip(
            id: 'ac_${row}_${targetId}_${laneClips.length}',
            rowIndex: row,
            targetId: targetId,
            patternId: (data['pattern_id'] ?? target['pattern_id'] ?? '')
                .toString()
                .trim(),
            startMs: math.max(0.0, start),
            lengthMs: len,
            muted: AssistantActionUtils.toActionBool(
              data['muted'] ?? target['muted'],
              fallback: false,
            ),
            points: points,
          ),
        );
      }
      clipMap[laneKey] = laneClips;
      return state.copyWith(
          automationLanePoints: lanePoints, automationClips: clipMap);
    }

    if (operation == 'duplicate_clip') {
      final laneClips = clipsForLane();
      final idx = resolveClipIndex(laneClips);
      if (idx == null) {
        return state.copyWith(
            automationLanePoints: lanePoints, automationClips: clipMap);
      }
      final src = laneClips[idx];
      final copyMode = (data['copy_mode'] ??
              data['clone_mode'] ??
              target['copy_mode'] ??
              target['clone_mode'] ??
              data['duplicate_mode'] ??
              target['duplicate_mode'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      final sharedCopy = copyMode.isEmpty ||
          copyMode == 'shared' ||
          copyMode == 'linked' ||
          copyMode == 'shallow' ||
          copyMode == 'clone';
      final patternId = sharedCopy
          ? (src.patternId.trim().isNotEmpty
              ? src.patternId.trim()
              : newPatternId())
          : '';
      if (sharedCopy && src.patternId.trim().isEmpty) {
        laneClips[idx] = src.copyWith(patternId: patternId);
      }
      final start = AssistantActionUtils.toActionDouble(
            data['start_ms'] ?? target['start_ms'] ?? data['paste_start_ms'],
          ) ??
          (src.startMs + src.lengthMs);
      laneClips.add(
        laneClips[idx].copyWith(
          id: '${src.id}_dup_${laneClips.length}',
          patternId: patternId,
          startMs: math.max(0.0, start),
        ),
      );
      clipMap[laneKey] = laneClips;
      return state.copyWith(
          automationLanePoints: lanePoints, automationClips: clipMap);
    }

    if (operation == 'move_clip' ||
        operation == 'delete_clip' ||
        operation == 'mute_clip' ||
        operation == 'unmute_clip' ||
        operation == 'toggle_clip_mute' ||
        operation == 'set_clip_points' ||
        operation == 'make_unique_clip' ||
        operation == 'make_unique') {
      final laneClips = clipsForLane();
      final idx = resolveClipIndex(laneClips);
      if (idx == null) {
        return state.copyWith(
            automationLanePoints: lanePoints, automationClips: clipMap);
      }
      final current = laneClips[idx];
      if (operation == 'delete_clip') {
        laneClips.removeAt(idx);
      } else if (operation == 'move_clip') {
        final start = AssistantActionUtils.toActionDouble(
              data['start_ms'] ?? target['start_ms'] ?? data['new_start_ms'],
            ) ??
            (current.startMs +
                (AssistantActionUtils.toActionDouble(
                        data['delta_ms'] ?? target['delta_ms']) ??
                    0.0));
        final len = AssistantActionUtils.toActionDouble(
              data['length_ms'] ?? target['length_ms'] ?? data['duration_ms'],
            ) ??
            current.lengthMs;
        laneClips[idx] = current.copyWith(
          startMs: math.max(0.0, start),
          lengthMs: math.max(40.0, len),
        );
      } else if (operation == 'mute_clip') {
        laneClips[idx] = current.copyWith(muted: true);
      } else if (operation == 'unmute_clip') {
        laneClips[idx] = current.copyWith(muted: false);
      } else if (operation == 'toggle_clip_mute') {
        laneClips[idx] = current.copyWith(muted: !current.muted);
      } else if (operation == 'make_unique_clip' ||
          operation == 'make_unique') {
        if (current.patternId.trim().isNotEmpty) {
          laneClips[idx] = current.copyWith(patternId: '');
        }
      } else if (operation == 'set_clip_points') {
        applySharedPointsToLane(
          laneClips,
          idx,
          parsePoints(data['points'], current.points),
        );
      }
      clipMap[laneKey] = laneClips;
      return state.copyWith(
          automationLanePoints: lanePoints, automationClips: clipMap);
    }

    if (operation == 'clear_clips') {
      clipMap[laneKey] = <TimelineAutomationClip>[];
      return state.copyWith(
          automationLanePoints: lanePoints, automationClips: clipMap);
    }

    return state;
  }

  static TimelineActionState _applyMidiCompose(
    TimelineActionState state,
    Map<String, dynamic> data,
  ) {
    final target = AssistantActionUtils.toActionMap(data['target']);
    final op = AssistantActionUtils.normalizeMidiComposeOperation(
      (data['operation'] ?? '').toString().trim().toLowerCase(),
    );
    if (op.isEmpty) return state;

    final clips = List<TimelineClip>.from(state.clips);
    final forceCreateNewClip = op == 'create_clip' ||
        AssistantActionUtils.toActionBool(
          data['create_new_clip'] ?? target['create_new_clip'],
        ) ||
        AssistantActionUtils.toActionBool(
          data['prefer_new_clip'] ?? target['prefer_new_clip'],
        );

    int? findMidiClipIndex() {
      if (forceCreateNewClip) return null;
      final explicit = AssistantActionUtils.toActionInt(
          data['clip_index'] ?? target['clip_index']);
      if (explicit != null &&
          explicit >= 0 &&
          explicit < clips.length &&
          clips[explicit].isMidi) {
        return explicit;
      }
      for (final idx in state.selectedClipIndices) {
        if (idx >= 0 && idx < clips.length && clips[idx].isMidi) return idx;
      }
      if (state.primarySelectedClipIndex >= 0 &&
          state.primarySelectedClipIndex < clips.length &&
          clips[state.primarySelectedClipIndex].isMidi) {
        return state.primarySelectedClipIndex;
      }
      final row = AssistantActionUtils.toActionInt(
        data['row_index'] ?? target['row_index'] ?? state.selectedRowIndex,
      );
      final hasExplicitRowHint = AssistantActionUtils.toActionInt(
            data['row_index'] ?? target['row_index'],
          ) !=
          null;
      if (row != null) {
        for (int i = 0; i < clips.length; i++) {
          final c = clips[i];
          if (c.isMidi && c.rowIndex == row) return i;
        }
        if (hasExplicitRowHint) {
          // If caller asked for a specific row and there is no MIDI clip there,
          // we should create one instead of re-targeting a different row.
          return null;
        }
      }
      for (int i = 0; i < clips.length; i++) {
        if (clips[i].isMidi) return i;
      }
      return null;
    }

    int? findAudioClipIndex() {
      final explicit = AssistantActionUtils.toActionInt(
        data['clip_index'] ?? target['clip_index'],
      );
      if (explicit != null &&
          explicit >= 0 &&
          explicit < clips.length &&
          !clips[explicit].isMidi) {
        return explicit;
      }
      for (final idx in state.selectedClipIndices) {
        if (idx >= 0 && idx < clips.length && !clips[idx].isMidi) return idx;
      }
      if (state.primarySelectedClipIndex >= 0 &&
          state.primarySelectedClipIndex < clips.length &&
          !clips[state.primarySelectedClipIndex].isMidi) {
        return state.primarySelectedClipIndex;
      }
      final row = AssistantActionUtils.toActionInt(
        data['row_index'] ?? target['row_index'] ?? state.selectedRowIndex,
      );
      if (row != null) {
        for (int i = 0; i < clips.length; i++) {
          final clip = clips[i];
          if (!clip.isMidi && clip.rowIndex == row) return i;
        }
      }
      for (int i = 0; i < clips.length; i++) {
        if (!clips[i].isMidi) return i;
      }
      return null;
    }

    List<MidiNote> parseNotes(dynamic raw) {
      final out = <MidiNote>[];
      if (raw is! List) return out;
      int i = 0;
      for (final e in raw) {
        final m = AssistantActionUtils.toActionMap(e);
        final pitch = AssistantActionUtils.midiPitchFromRaw(
          m['pitch'] ?? m['midi'] ?? m['note'] ?? m['note_name'],
        );
        final start = AssistantActionUtils.resolveMidiNoteStartBeat(m);
        final len = AssistantActionUtils.resolveMidiNoteLengthBeats(m);
        final vel =
            AssistantActionUtils.normalizeMidiVelocity(m['velocity']) ?? 0.8;
        if (pitch == null || start == null || len == null) continue;
        out.add(
          MidiNote(
            id: 'm_${i++}',
            pitch: pitch.clamp(0, 127),
            startBeat: math.max(0.0, start),
            lengthBeats: math.max(0.0625, len),
            velocity: vel.clamp(0.0, 1.0),
          ),
        );
      }
      return out;
    }

    double? resolveTargetLengthBeats() {
      return AssistantActionUtils.resolveMidiTargetLengthBeatsFromAction(
        data,
        target: target,
        bpm: state.projectTempoBpm,
      );
    }

    List<MidiNote> resizeNotesToTargetLength(
      List<MidiNote> sourceNotes,
      double targetBeats,
    ) {
      if (sourceNotes.isEmpty || !targetBeats.isFinite || targetBeats <= 0.0) {
        return const <MidiNote>[];
      }
      final sorted = sourceNotes.map((n) => n.copy()).toList(growable: false)
        ..sort((a, b) {
          final byStart = a.startBeat.compareTo(b.startBeat);
          if (byStart != 0) return byStart;
          return a.pitch.compareTo(b.pitch);
        });
      final cycleBeats = sorted
          .map((n) => n.startBeat + n.lengthBeats)
          .fold<double>(0.0, math.max);
      if (!cycleBeats.isFinite || cycleBeats <= 0.0) {
        return const <MidiNote>[];
      }
      final out = <MidiNote>[];
      final repeats = math.max(1, (targetBeats / cycleBeats).ceil());
      const epsilon = 1e-6;
      for (int repeat = 0; repeat < repeats; repeat++) {
        final beatOffset = repeat * cycleBeats;
        for (int i = 0; i < sorted.length; i++) {
          final note = sorted[i];
          final startBeat = note.startBeat + beatOffset;
          if (startBeat >= targetBeats - epsilon) continue;
          final remaining = targetBeats - startBeat;
          if (remaining <= epsilon) continue;
          out.add(
            MidiNote(
              id: 'resize_${repeat}_$i',
              pitch: note.pitch,
              startBeat: startBeat,
              lengthBeats: math.min(note.lengthBeats, remaining),
              velocity: note.velocity,
            ),
          );
        }
      }
      return out;
    }

    List<MidiNote> resolveNotes() {
      final explicit = parseNotes(data['notes']);
      if (explicit.isNotEmpty) return explicit;
      final operation =
          (data['operation'] ?? '').toString().trim().toLowerCase();
      final notesPerChord = (AssistantActionUtils.toActionInt(
                data['notes_per_chord'] ?? target['notes_per_chord'],
              ) ??
              4)
          .clamp(1, 8);
      final isBassline = operation == 'compose_bassline';
      return AssistantActionUtils.fallbackMidiNotesFromProgression(
        progressionRaw: AssistantActionUtils.progressionTokensFromRaw(
          data['progression'] ??
              target['progression'] ??
              data['chords'] ??
              target['chords'],
        ),
        beatsPerChord: AssistantActionUtils.toActionDouble(
              data['beats_per_chord'] ??
                  target['beats_per_chord'] ??
                  data['chord_length_beats'] ??
                  target['chord_length_beats'],
            ) ??
            4.0,
        notesPerChord: notesPerChord,
        octave: (AssistantActionUtils.toActionInt(
                  data['octave'] ?? target['octave'],
                ) ??
                (isBassline ? 2 : 3))
            .clamp(-1, 8),
        velocity: (AssistantActionUtils.toActionDouble(
                  data['velocity'] ?? target['velocity'],
                ) ??
                0.78)
            .clamp(0.2, 1.0),
        mode: isBassline ? 'bass' : 'chords',
      );
    }

    if (op == 'convert_audio_to_midi') {
      final sourceIndex = findAudioClipIndex();
      if (sourceIndex == null ||
          sourceIndex < 0 ||
          sourceIndex >= clips.length) {
        return state;
      }
      final source = clips[sourceIndex];
      if (source.isMidi) return state;
      clips.add(
        TimelineClip(
          id: 'midi_audio_${clips.length}',
          isMidi: true,
          rowIndex: math.max(0, source.rowIndex + 1),
          startMs: source.startMs,
          sourceDurationMs: math.max(500.0, source.localDurationMs),
          trimStartMs: 0.0,
          trimEndMs: math.max(500.0, source.localDurationMs),
          gain: 1.0,
          label: source.label.trim().isEmpty
              ? 'Audio to MIDI'
              : '${source.label} MIDI',
          tempoFollow: true,
          detectedTempoBpm: state.projectTempoBpm,
          midiNotes: const <MidiNote>[],
        ),
      );
      return state.copyWith(clips: clips);
    }

    List<MidiNote> maybeExtendGeneratedNotes(List<MidiNote> source) {
      if (source.isEmpty) return source;
      final targetBeats = resolveTargetLengthBeats();
      if (targetBeats == null || !targetBeats.isFinite || targetBeats <= 0.0) {
        return source;
      }
      final currentSpan = source
          .map((n) => n.startBeat + n.lengthBeats)
          .fold<double>(0.0, math.max);
      if (currentSpan <= 0.0 || currentSpan >= targetBeats - 1e-6) {
        return source;
      }
      return resizeNotesToTargetLength(source, targetBeats);
    }

    final preserveExistingNotes = AssistantActionUtils.toActionBool(
      data['preserve_existing_notes'] ?? target['preserve_existing_notes'],
    );
    var notes = maybeExtendGeneratedNotes(resolveNotes());
    final idx = findMidiClipIndex();
    if (idx == null) {
      if (notes.isEmpty) return state;
      final row = AssistantActionUtils.toActionInt(
            data['row_index'] ?? target['row_index'] ?? state.selectedRowIndex,
          ) ??
          0;
      final startMs = AssistantActionUtils.toActionDouble(
            data['start_ms'] ?? target['start_ms'],
          ) ??
          0.0;
      final maxBeat = notes
          .map((n) => n.startBeat + n.lengthBeats)
          .fold<double>(1.0, (a, b) => math.max(a, b));
      final dur = maxBeat * (60000.0 / state.projectTempoBpm.clamp(1.0, 320.0));
      clips.add(
        TimelineClip(
          id: 'midi_${clips.length}',
          isMidi: true,
          rowIndex: math.max(0, row),
          startMs: math.max(0.0, startMs),
          sourceDurationMs: math.max(500.0, dur),
          trimStartMs: 0.0,
          trimEndMs: math.max(500.0, dur),
          gain: 1.0,
          label: (data['label'] ?? target['label'] ?? 'MIDI Clip').toString(),
          tempoFollow: true,
          detectedTempoBpm: state.projectTempoBpm,
          midiNotes: notes,
        ),
      );
      return state.copyWith(clips: clips);
    }

    if (idx < 0 || idx >= clips.length || !clips[idx].isMidi) return state;
    final clip = clips[idx];
    if (notes.isEmpty &&
        clip.midiNotes.isNotEmpty &&
        AssistantActionUtils.hasStyleDrivenMidiGenerationDirectives(
          data,
          target: target,
        )) {
      notes = AssistantActionUtils.generateStyledMidiNotesFromSource(
        sourceNotes: clip.midiNotes,
        data: data,
        target: target,
        noteIdPrefix: 'ai_style',
        bpm: state.projectTempoBpm,
      );
      notes = maybeExtendGeneratedNotes(notes);
    }

    if (op == 'chop_notes') {
      final subdivision = AssistantActionUtils.toActionInt(
            data['subdivision'] ??
                data['subdivision_divisor'] ??
                target['subdivision'] ??
                target['subdivision_divisor'],
          ) ??
          16;
      final chopped = AssistantActionUtils.chopMidiNotes(
        notes: clip.midiNotes,
        subdivision: subdivision,
        velocityDecayPerSlice: AssistantActionUtils.toActionDouble(
                data['velocity_decay_per_slice']) ??
            0.0,
        velocityJitter:
            AssistantActionUtils.toActionDouble(data['velocity_jitter']) ?? 0.0,
        velocityFloor:
            AssistantActionUtils.toActionDouble(data['velocity_floor']) ?? 0.05,
      );
      clips[idx] = clip.copyWith(midiNotes: chopped);
      return state.copyWith(clips: clips);
    }

    if (op == 'transpose_notes') {
      final semitones =
          (AssistantActionUtils.toActionDouble(data['semitones']) ?? 0.0) +
              ((AssistantActionUtils.toActionDouble(data['octaves']) ?? 0.0) *
                  12.0);
      final delta = semitones.round();
      if (delta == 0 || clip.midiNotes.isEmpty) return state;
      final next = clip.midiNotes
          .map(
            (n) => MidiNote(
              id: n.id,
              pitch: (n.pitch + delta).clamp(0, 127),
              startBeat: n.startBeat,
              lengthBeats: n.lengthBeats,
              velocity: n.velocity,
            ),
          )
          .toList(growable: false);
      clips[idx] = clip.copyWith(midiNotes: next);
      return state.copyWith(clips: clips);
    }

    if (op == 'append_notes') {
      final add = notes;
      if (add.isEmpty && preserveExistingNotes) {
        final targetBeats = resolveTargetLengthBeats();
        if (targetBeats == null || clip.midiNotes.isEmpty) return state;
        final next = resizeNotesToTargetLength(clip.midiNotes, targetBeats);
        if (next.isEmpty) return state;
        clips[idx] = clip.copyWith(midiNotes: next);
        return state.copyWith(clips: clips);
      }
      if (add.isEmpty) return state;
      final explicitAppendStartBeat =
          AssistantActionUtils.toActionDouble(data['append_start_beat']);
      double offset = explicitAppendStartBeat ?? 0.0;
      final appendAtEnd = AssistantActionUtils.toActionBool(
        data['append_at_end'],
        fallback: !preserveExistingNotes,
      );
      if (appendAtEnd && clip.midiNotes.isNotEmpty) {
        offset = clip.midiNotes
            .map((n) => n.startBeat + n.lengthBeats)
            .fold<double>(0.0, math.max);
      } else if (explicitAppendStartBeat == null && preserveExistingNotes) {
        offset = 0.0;
      }
      final next = <MidiNote>[
        ...clip.midiNotes.map((n) => n.copy()),
        ...add.map(
          (n) => MidiNote(
            id: 'a_${n.id}',
            pitch: n.pitch,
            startBeat: n.startBeat + offset,
            lengthBeats: n.lengthBeats,
            velocity: n.velocity,
          ),
        ),
      ];
      clips[idx] = clip.copyWith(midiNotes: next);
      return state.copyWith(clips: clips);
    }

    if (notes.isEmpty && preserveExistingNotes) {
      final targetBeats = resolveTargetLengthBeats();
      if (targetBeats == null || clip.midiNotes.isEmpty) return state;
      final next = resizeNotesToTargetLength(clip.midiNotes, targetBeats);
      if (next.isEmpty) return state;
      clips[idx] = clip.copyWith(midiNotes: next);
      return state.copyWith(clips: clips);
    }

    if (notes.isEmpty) return state;
    clips[idx] = clip.copyWith(midiNotes: notes);
    return state.copyWith(clips: clips);
  }

  static TimelineActionState _applyStemSeparate(
    TimelineActionState state,
    Map<String, dynamic> data,
  ) {
    final target = AssistantActionUtils.toActionMap(data['target']);
    final clips = List<TimelineClip>.from(state.clips);
    final indices = <int>[];
    final explicitList =
        (data['clip_indices'] as List?) ?? (target['clip_indices'] as List?);
    if (explicitList != null) {
      for (final raw in explicitList) {
        final idx = AssistantActionUtils.toActionInt(raw);
        if (idx != null) indices.add(idx);
      }
    }
    final explicit = AssistantActionUtils.toActionInt(
      data['clip_index'] ?? target['clip_index'],
    );
    if (explicit != null) indices.add(explicit);
    if (indices.isEmpty) {
      indices.addAll(state.selectedClipIndices);
      if (state.primarySelectedClipIndex >= 0) {
        indices.add(state.primarySelectedClipIndex);
      }
    }
    if (indices.isEmpty) {
      for (int i = 0; i < clips.length; i++) {
        if (!clips[i].isMidi) {
          indices.add(i);
          break;
        }
      }
    }
    final unique = indices.toSet().toList()..sort();
    for (final idx in unique) {
      if (idx < 0 || idx >= clips.length) continue;
      final src = clips[idx];
      if (src.isMidi) continue;
      clips.add(
        src.copyWith(
          id: '${src.id}:vocals',
          label: '${src.label} Vocals',
        ),
      );
      clips.add(
        src.copyWith(
          id: '${src.id}:instrumental',
          label: '${src.label} Instrumental',
        ),
      );
    }
    return state.copyWith(clips: clips);
  }

  static TimelineActionState _applyRoleOverride(
    TimelineActionState state,
    Map<String, dynamic> data,
  ) {
    final target = AssistantActionUtils.toActionMap(data['target']);
    final row = AssistantActionUtils.toActionInt(
      data['row_index'] ?? target['row_index'] ?? state.selectedRowIndex,
    );
    if (row == null || row < 0) return state;
    final op = (data['operation'] ?? 'set').toString().trim().toLowerCase();
    final next = Map<int, String>.from(state.roleOverrides);
    if (op == 'clear' || op == 'remove' || op == 'unset' || op == 'delete') {
      next.remove(row);
    } else {
      final role = (data['role'] ?? target['role'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (role.isNotEmpty) next[row] = role;
    }
    return state.copyWith(roleOverrides: next);
  }

  static Map<String, List<AutomationPoint>> _copyLanePoints(
    Map<String, List<AutomationPoint>> input,
  ) {
    final out = <String, List<AutomationPoint>>{};
    input.forEach((k, v) {
      out[k] = v
          .map((p) => AutomationPoint(x: p.x, volume: p.volume))
          .toList(growable: false);
    });
    return out;
  }

  static Map<String, List<TimelineAutomationClip>> _copyAutomationClips(
    Map<String, List<TimelineAutomationClip>> input,
  ) {
    final out = <String, List<TimelineAutomationClip>>{};
    input.forEach((k, v) {
      out[k] = v.map((c) => c.copyWith()).toList(growable: false);
    });
    return out;
  }
}
