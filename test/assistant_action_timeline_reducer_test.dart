import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/assistant_action_timeline_reducer.dart';
import 'package:mixroom/models/mixing_result.dart';
import 'package:mixroom/models/models.dart';

TimelineClip _audioClip({
  required String id,
  int row = 0,
  double startMs = 0.0,
  double sourceDurationMs = 4000.0,
  double trimStartMs = 0.0,
  double? trimEndMs,
  double gain = 1.0,
  String label = 'Audio',
  bool tempoFollow = false,
  double? detectedTempoBpm,
}) {
  return TimelineClip(
    id: id,
    isMidi: false,
    rowIndex: row,
    startMs: startMs,
    sourceDurationMs: sourceDurationMs,
    trimStartMs: trimStartMs,
    trimEndMs: trimEndMs ?? sourceDurationMs,
    gain: gain,
    label: label,
    tempoFollow: tempoFollow,
    detectedTempoBpm: detectedTempoBpm,
    midiNotes: const <MidiNote>[],
  );
}

TimelineClip _midiClip({
  required String id,
  int row = 0,
  double startMs = 0.0,
  String label = 'MIDI',
  List<MidiNote>? notes,
}) {
  return TimelineClip(
    id: id,
    isMidi: true,
    rowIndex: row,
    startMs: startMs,
    sourceDurationMs: 4000.0,
    trimStartMs: 0.0,
    trimEndMs: 4000.0,
    gain: 1.0,
    label: label,
    tempoFollow: true,
    detectedTempoBpm: 120.0,
    midiNotes: notes ??
        <MidiNote>[
          MidiNote(
            id: 'n0',
            pitch: 48,
            startBeat: 0.0,
            lengthBeats: 1.0,
            velocity: 0.8,
          ),
        ],
  );
}

AssistantAction _action(String type, Map<String, dynamic> data) =>
    AssistantAction(type: type, data: data);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssistantActionTimelineReducer clip_edit', () {
    test('trim updates trim values and preserves content position', () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[_audioClip(id: 'a0')],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('clip_edit', <String, dynamic>{
            'operation': 'trim',
            'trim_start_ms': 250,
            'trim_end_ms': 3300,
            'target': <String, dynamic>{'clip_index': 0},
          }),
        ],
      );

      expect(next.clips.length, 1);
      expect(next.clips.first.trimStartMs, closeTo(250.0, 0.001));
      expect(next.clips.first.trimEndMs, closeTo(3300.0, 0.001));
      expect(next.clips.first.startMs, closeTo(250.0, 0.001));
    });

    test('cut splits clip into two timeline clips', () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[_audioClip(id: 'a0', sourceDurationMs: 6000.0)],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('clip_edit', <String, dynamic>{
            'operation': 'cut',
            'cut_ms': 2000,
            'target': <String, dynamic>{'clip_index': 0},
          }),
        ],
      );

      expect(next.clips.length, 2);
      expect(next.clips[0].startMs, 0.0);
      expect(next.clips[1].startMs, closeTo(2000.0, 0.001));
      expect(next.clips[0].endMs, closeTo(2000.0, 0.001));
      expect(next.clips[1].endMs, closeTo(6000.0, 0.001));
    });

    test('stretch/move/duplicate/delete operate in sequence', () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[_audioClip(id: 'a0', sourceDurationMs: 8000.0)],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('clip_edit', <String, dynamic>{
            'operation': 'stretch',
            'timeline_duration_ms': 3000,
            'target': <String, dynamic>{'clip_index': 0},
          }),
          _action('clip_edit', <String, dynamic>{
            'operation': 'move',
            'delta_ms': 1200,
            'direction': 'down',
            'target': <String, dynamic>{'clip_index': 0},
          }),
          _action('clip_edit', <String, dynamic>{
            'operation': 'duplicate',
            'target': <String, dynamic>{'clip_index': 0},
          }),
          _action('clip_edit', <String, dynamic>{
            'operation': 'delete',
            'target': <String, dynamic>{'clip_index': 0},
          }),
        ],
      );

      expect(next.clips.length, 1);
      expect(next.clips.first.startMs, closeTo(4200.0, 0.001));
      expect(next.clips.first.rowIndex, 1);
      expect(next.clips.first.localDurationMs, closeTo(3000.0, 0.001));
    });

    test('tempo_follow and tempo_detect_set_project update tempo state', () {
      final initial = TimelineActionState.empty(
        projectTempoBpm: 120.0,
        clips: <TimelineClip>[
          _audioClip(id: 'a0', detectedTempoBpm: 98.0),
          _audioClip(id: 'a1', startMs: 1000.0),
        ],
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('clip_edit', <String, dynamic>{
            'operation': 'tempo_follow',
            'target': <String, dynamic>{'clip_index': 1},
          }),
          _action('clip_edit', <String, dynamic>{
            'operation': 'tempo_detect_set_project',
            'target': <String, dynamic>{'clip_index': 0},
          }),
        ],
      );

      expect(next.clips[1].tempoFollow, isTrue);
      expect(next.projectTempoBpm, closeTo(98.0, 0.001));
    });

    test('auto_trim and auto_bpm_align apply deterministic defaults', () {
      final initial = TimelineActionState.empty(
        projectTempoBpm: 120.0,
        clips: <TimelineClip>[
          _audioClip(id: 'vox', sourceDurationMs: 5000.0),
        ],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('clip_edit', <String, dynamic>{
            'operation': 'auto_trim',
            'target': <String, dynamic>{'clip_index': 0},
            'padding_ms': 80,
          }),
          _action('clip_edit', <String, dynamic>{
            'operation': 'auto_bpm_align',
            'target': <String, dynamic>{'clip_index': 0},
            'project_tempo_bpm': 132,
          }),
        ],
      );

      expect(next.clips.first.trimStartMs, closeTo(80.0, 0.001));
      expect(next.clips.first.trimEndMs, closeTo(4920.0, 0.001));
      expect(next.clips.first.startMs, closeTo(80.0, 0.001));
      expect(next.clips.first.tempoFollow, isTrue);
      expect(next.projectTempoBpm, closeTo(132.0, 0.001));
    });

    test('dialog operations remove and lift without prompts', () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _audioClip(id: 'vox', sourceDurationMs: 7000.0, label: 'Podcast Vox'),
        ],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('clip_edit', <String, dynamic>{
            'operation': 'dialog_cleanup',
            'target': <String, dynamic>{'clip_index': 0},
            'ranges': <Map<String, dynamic>>[
              <String, dynamic>{'from_ms': 1000, 'to_ms': 1200},
            ],
          }),
          _action('clip_edit', <String, dynamic>{
            'operation': 'dialog_remove_range',
            'target': <String, dynamic>{'clip_index': 0},
            'from_ms': 2500,
            'to_ms': 2700,
          }),
          _action('clip_edit', <String, dynamic>{
            'operation': 'dialog_tighten_pauses',
            'target': <String, dynamic>{'clip_index': 0},
            'from_ms': 3500,
            'to_ms': 3600,
          }),
          _action('clip_edit', <String, dynamic>{
            'operation': 'dialog_lift_quiet',
            'boost_db': 6,
            'target': <String, dynamic>{'clip_index': 0},
          }),
        ],
      );

      expect(next.clips.isNotEmpty, isTrue);
      expect(next.clips.length, greaterThan(1));
      expect(next.clips.first.gain, greaterThanOrEqualTo(1.0));
      final totalDuration =
          next.clips.fold<double>(0.0, (sum, c) => sum + c.localDurationMs);
      expect(totalDuration, lessThan(7000.0));
    });
  });

  group('AssistantActionTimelineReducer automation_edit', () {
    test('lane operations set/add/clear points', () {
      final initial = TimelineActionState.empty();
      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('automation_edit', <String, dynamic>{
            'operation': 'set_points',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x_ms': 0, 'value': 1.0},
              <String, dynamic>{'x_ms': 1000, 'value': 0.5},
            ],
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'add_ramp',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'from_ms': 1200,
            'to_ms': 1600,
            'start_value': 0.5,
            'end_value': 0.9,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'clear',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
          }),
        ],
      );

      final lane = next.automationLanePoints['0::volume'];
      expect(lane, isNotNull);
      expect(lane!.length, 1);
      expect(lane.first.volume, closeTo(1.0, 0.001));
    });

    test('clip automation lifecycle and sidechain template', () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _audioClip(
              id: 'kick', row: 0, startMs: 0.0, sourceDurationMs: 4000.0),
          _audioClip(id: 'pad', row: 1, startMs: 0.0, sourceDurationMs: 4000.0),
        ],
      );
      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('automation_edit', <String, dynamic>{
            'operation': 'create_clip',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
            'start_ms': 100,
            'length_ms': 500,
            'template': 'reverb_tail',
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'duplicate_clip',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
            'clip_index': 0,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'move_clip',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
            'clip_index': 1,
            'delta_ms': 200,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'toggle_clip_mute',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
            'clip_index': 1,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'set_clip_points',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
            'clip_index': 1,
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x_ms': 0, 'value': 1.0},
              <String, dynamic>{'x_ms': 500, 'value': 0.2},
            ],
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'apply_template',
            'template': 'sidechain_from_kick',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
            'source_clip_index': 0,
            'length_ms': 260,
            'min_spacing_ms': 220,
            'max_events': 5,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'delete_clip',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
            'clip_index': 0,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'clear_clips',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
          }),
        ],
      );

      final laneKey = '1::volume';
      final clips = next.automationClips[laneKey];
      expect(clips, isNotNull);
      expect(clips, isEmpty);
    });

    test('mute/unmute clip and non-kick templates produce expected shapes', () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _audioClip(id: 'pad', row: 1, startMs: 0.0, sourceDurationMs: 3000.0),
        ],
      );
      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('automation_edit', <String, dynamic>{
            'operation': 'create_clip',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
            'start_ms': 0,
            'length_ms': 400,
            'template': 'sidechain_pump',
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'mute_clip',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
            'clip_index': 0,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'unmute_clip',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
            'clip_index': 0,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'apply_template',
            'template': 'filter_sweep',
            'target': <String, dynamic>{'row_index': 2, 'target_id': 'cutoff'},
            'start_ms': 100,
            'length_ms': 600,
          }),
        ],
      );

      final pumpLane = next.automationClips['1::volume']!;
      expect(pumpLane.length, 1);
      expect(pumpLane.first.muted, isFalse);
      expect(pumpLane.first.points.length, greaterThanOrEqualTo(4));
      expect(
        pumpLane.first.points.map((p) => p.volume).reduce(math.min),
        lessThan(0.2),
      );

      final sweepLane = next.automationClips['2::cutoff']!;
      expect(sweepLane.length, 1);
      expect(sweepLane.first.points.length, 2);
      expect(sweepLane.first.points.first.volume, closeTo(0.0, 0.001));
      expect(sweepLane.first.points.last.volume, closeTo(1.0, 0.001));
    });

    test('shared duplicate propagates point edits across linked clips only',
        () {
      final initial = TimelineActionState.empty();

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('automation_edit', <String, dynamic>{
            'operation': 'create_clip',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'start_ms': 0,
            'length_ms': 300,
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x_ms': 0, 'value': 0.2},
              <String, dynamic>{'x_ms': 300, 'value': 0.8},
            ],
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'duplicate_clip',
            'copy_mode': 'shared',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'clip_index': 0,
            'start_ms': 500,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'duplicate_clip',
            'copy_mode': 'deep',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'clip_index': 0,
            'start_ms': 900,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'set_clip_points',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'clip_index': 1,
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x_ms': 0, 'value': 1.0},
              <String, dynamic>{'x_ms': 300, 'value': 0.1},
            ],
          }),
        ],
      );

      final lane = next.automationClips['0::volume'];
      expect(lane, isNotNull);
      expect(lane!, hasLength(3));
      expect(lane[0].patternId, isNotEmpty);
      expect(lane[1].patternId, lane[0].patternId);
      expect(lane[2].patternId, isEmpty);
      expect(lane[0].points.last.volume, closeTo(0.1, 0.001));
      expect(lane[1].points.last.volume, closeTo(0.1, 0.001));
      expect(lane[2].points.last.volume, closeTo(0.8, 0.001));
    });

    test('clone_clip defaults to linked clone semantics and pattern targeting',
        () {
      final initial = TimelineActionState.empty();

      final cloned = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('automation_edit', <String, dynamic>{
            'operation': 'create_clip',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'start_ms': 0,
            'length_ms': 300,
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x_ms': 0, 'value': 0.2},
              <String, dynamic>{'x_ms': 300, 'value': 0.8},
            ],
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'clone_clip',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'clip_index': 0,
            'start_ms': 500,
          }),
        ],
      );

      final clonedLane = cloned.automationClips['0::volume'];
      expect(clonedLane, isNotNull);
      expect(clonedLane!, hasLength(2));
      expect(clonedLane[0].patternId, isNotEmpty);
      expect(clonedLane[1].patternId, clonedLane[0].patternId);

      final next = AssistantActionTimelineReducer.applyActions(
        cloned,
        <AssistantAction>[
          _action('automation_edit', <String, dynamic>{
            'operation': 'set_clip_points',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'pattern_id': clonedLane[0].patternId,
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x_ms': 0, 'value': 1.0},
              <String, dynamic>{'x_ms': 300, 'value': 0.05},
            ],
          }),
        ],
      );

      final updatedLane = next.automationClips['0::volume'];
      expect(updatedLane, isNotNull);
      expect(updatedLane!, hasLength(2));
      expect(updatedLane[0].points.last.volume, closeTo(0.05, 0.001));
      expect(updatedLane[1].points.last.volume, closeTo(0.05, 0.001));
    });

    test('make_unique detaches a shared automation clip from future edits', () {
      final initial = TimelineActionState.empty();

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('automation_edit', <String, dynamic>{
            'operation': 'create_clip',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'start_ms': 0,
            'length_ms': 300,
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x_ms': 0, 'value': 0.2},
              <String, dynamic>{'x_ms': 300, 'value': 0.8},
            ],
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'duplicate_clip',
            'copy_mode': 'shared',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'clip_index': 0,
            'start_ms': 500,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'make_unique_clip',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'clip_index': 1,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'set_clip_points',
            'target': <String, dynamic>{'row_index': 0, 'target_id': 'volume'},
            'clip_index': 1,
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x_ms': 0, 'value': 1.0},
              <String, dynamic>{'x_ms': 300, 'value': 0.1},
            ],
          }),
        ],
      );

      final lane = next.automationClips['0::volume'];
      expect(lane, isNotNull);
      expect(lane!, hasLength(2));
      expect(lane[0].patternId, isNotEmpty);
      expect(lane[1].patternId, isEmpty);
      expect(lane[0].points.last.volume, closeTo(0.8, 0.001));
      expect(lane[1].points.last.volume, closeTo(0.1, 0.001));
    });

    test('clip lifecycle supports master and encoded plugin target ids', () {
      final masterFxTarget =
          'masterfxid:${Uri.encodeComponent('Master Comp#0')}:${Uri.encodeComponent('threshold')}';
      final rowFxTarget =
          'fxid:${Uri.encodeComponent('Group Bus Comp#1')}:${Uri.encodeComponent('mix')}';
      final initial = TimelineActionState.empty(selectedRowIndex: 0);

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('automation_edit', <String, dynamic>{
            'operation': 'create_clip',
            'target': <String, dynamic>{
              'row_index': 0,
              'target_id': 'master:gain',
            },
            'start_ms': 40,
            'length_ms': 240,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'duplicate_clip',
            'target': <String, dynamic>{
              'row_index': 0,
              'target_id': 'master:gain',
            },
            'clip_index': 0,
            'start_ms': 500,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'move_clip',
            'target': <String, dynamic>{
              'row_index': 0,
              'target_id': 'master:gain',
            },
            'clip_index': 1,
            'delta_ms': 80,
            'length_ms': 360,
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'set_clip_points',
            'target': <String, dynamic>{
              'row_index': 0,
              'target_id': 'master:gain',
            },
            'clip_index': 1,
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x_ms': 360, 'value': 0.1},
              <String, dynamic>{'x_ms': -50, 'value': 1.2},
            ],
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'create_clip',
            'target': <String, dynamic>{
              'row_index': 0,
              'target_id': masterFxTarget,
            },
            'start_ms': 120,
            'length_ms': 480,
            'template': 'filter_sweep',
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'create_clip',
            'target': <String, dynamic>{
              'row_index': 1,
              'target_id': rowFxTarget,
            },
            'start_ms': 200,
            'length_ms': 500,
            'template': 'reverb_tail',
          }),
        ],
      );

      final masterMixLane = next.automationClips['0::master:gain'];
      expect(masterMixLane, isNotNull);
      expect(masterMixLane!, hasLength(2));
      expect(masterMixLane[0].targetId, 'master:gain');
      expect(masterMixLane[1].startMs, closeTo(580.0, 0.001));
      expect(masterMixLane[1].lengthMs, closeTo(360.0, 0.001));
      expect(masterMixLane[1].points, hasLength(2));
      expect(masterMixLane[1].points.first.x, closeTo(0.0, 0.001));
      expect(masterMixLane[1].points.first.volume, closeTo(1.0, 0.001));
      expect(masterMixLane[1].points.last.x, closeTo(360.0, 0.001));
      expect(masterMixLane[1].points.last.volume, closeTo(0.1, 0.001));

      final masterFxLane = next.automationClips['0::$masterFxTarget'];
      expect(masterFxLane, isNotNull);
      expect(masterFxLane!, hasLength(1));
      expect(masterFxLane.single.targetId, masterFxTarget);
      expect(masterFxLane.single.points, hasLength(2));
      expect(masterFxLane.single.points.first.volume, closeTo(0.0, 0.001));
      expect(masterFxLane.single.points.last.volume, closeTo(1.0, 0.001));

      final rowFxLane = next.automationClips['1::$rowFxTarget'];
      expect(rowFxLane, isNotNull);
      expect(rowFxLane!, hasLength(1));
      expect(rowFxLane.single.rowIndex, 1);
      expect(rowFxLane.single.targetId, rowFxTarget);

      expect(next.automationClips.containsKey('0::volume'), isFalse);
    });

    test('clear_clips only clears the targeted automation lane', () {
      final masterTarget = 'master:gain';
      final pluginTarget =
          'fxid:${Uri.encodeComponent('Bus FX#0')}:${Uri.encodeComponent('feedback')}';
      final initial = TimelineActionState.empty().copyWith(
        automationClips: <String, List<TimelineAutomationClip>>{
          '0::$masterTarget': <TimelineAutomationClip>[
            TimelineAutomationClip(
              id: 'master_clip',
              rowIndex: 0,
              targetId: masterTarget,
              startMs: 0.0,
              lengthMs: 400.0,
              muted: false,
              points: <AutomationPoint>[
                AutomationPoint(x: 0.0, volume: 0.5),
              ],
            ),
          ],
          '0::$pluginTarget': <TimelineAutomationClip>[
            TimelineAutomationClip(
              id: 'plugin_clip',
              rowIndex: 0,
              targetId: pluginTarget,
              startMs: 250.0,
              lengthMs: 300.0,
              muted: false,
              points: <AutomationPoint>[
                AutomationPoint(x: 0.0, volume: 0.25),
                AutomationPoint(x: 300.0, volume: 0.9),
              ],
            ),
          ],
        },
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('automation_edit', <String, dynamic>{
            'operation': 'clear_clips',
            'target': <String, dynamic>{
              'row_index': 0,
              'target_id': masterTarget,
            },
          }),
        ],
      );

      expect(next.automationClips['0::$masterTarget'], isEmpty);
      final pluginLane = next.automationClips['0::$pluginTarget'];
      expect(pluginLane, isNotNull);
      expect(pluginLane!, hasLength(1));
      expect(pluginLane.single.id, 'plugin_clip');
      expect(pluginLane.single.points, hasLength(2));
    });
  });

  group('AssistantActionTimelineReducer midi_compose', () {
    test('replace/append/chop and auto-create midi clips', () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _midiClip(
            id: 'm0',
            row: 2,
            notes: <MidiNote>[
              MidiNote(
                id: 'n0',
                pitch: 36,
                startBeat: 0.0,
                lengthBeats: 2.0,
                velocity: 0.8,
              ),
            ],
          ),
        ],
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('midi_compose', <String, dynamic>{
            'operation': 'replace_notes',
            'target': <String, dynamic>{'clip_index': 0},
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 48,
                'start_beat': 0.0,
                'length_beats': 1.0,
                'velocity': 0.8
              },
              <String, dynamic>{
                'pitch': 50,
                'start_beat': 1.0,
                'length_beats': 1.0,
                'velocity': 0.75
              },
            ],
          }),
          _action('midi_compose', <String, dynamic>{
            'operation': 'append_notes',
            'target': <String, dynamic>{'clip_index': 0},
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 52,
                'start_beat': 0.0,
                'length_beats': 1.0,
                'velocity': 0.7
              },
            ],
          }),
          _action('midi_compose', <String, dynamic>{
            'operation': 'chop_notes',
            'target': <String, dynamic>{'clip_index': 0},
            'subdivision': 16,
            'velocity_decay_per_slice': 0.05,
          }),
          _action('midi_compose', <String, dynamic>{
            'operation': 'compose_bassline',
            'target': <String, dynamic>{'row_index': 4},
            'progression': <String>['C', 'D', 'G', 'C'],
          }),
        ],
      );

      final midiClips =
          next.clips.where((c) => c.isMidi).toList(growable: false);
      expect(midiClips.length, 2);
      expect(midiClips.first.midiNotes.length, greaterThan(2));
      expect(midiClips.last.rowIndex, 4);
      expect(midiClips.last.midiNotes, isNotEmpty);
    });

    test('compose_pattern and stutter controls apply on midi notes', () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _midiClip(
            id: 'm0',
            row: 2,
            notes: <MidiNote>[
              MidiNote(
                id: 'n0',
                pitch: 48,
                startBeat: 0.0,
                lengthBeats: 1.0,
                velocity: 1.0,
              ),
            ],
          ),
        ],
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('midi_compose', <String, dynamic>{
            'operation': 'compose_pattern',
            'target': <String, dynamic>{'row_index': 5},
            'progression': <String>['C', 'Am', 'F', 'G'],
            'label': 'Arp Pattern',
          }),
          _action('midi_compose', <String, dynamic>{
            'operation': 'chop_notes',
            'target': <String, dynamic>{'clip_index': 0},
            'subdivision': 16,
            'velocity_decay_per_slice': 0.2,
            'velocity_jitter': 0.1,
            'velocity_floor': 0.35,
          }),
        ],
      );

      final chopped = next.clips.first.midiNotes;
      expect(chopped.length, greaterThan(1));
      expect(chopped.every((n) => n.velocity >= 0.35), isTrue);
      expect(chopped.map((n) => n.velocity).toSet().length, greaterThan(1));

      final patternClip =
          next.clips.where((c) => c.isMidi && c.rowIndex == 5).toList();
      expect(patternClip, isNotEmpty);
      expect(patternClip.first.label, 'Arp Pattern');
      expect(patternClip.first.midiNotes, isNotEmpty);
    });
  });

  group('AssistantActionTimelineReducer stem/role/tutorial/clarify', () {
    test('stem separation adds vocal+instrumental and role override set/clear',
        () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _audioClip(id: 'vox', row: 1, label: 'Lead Vox'),
          _audioClip(id: 'drums', row: 0, label: 'Drums'),
        ],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
        selectedRowIndex: 1,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('stem_separate', <String, dynamic>{
            'operation': 'vocal_instrumental',
            'target': <String, dynamic>{'clip_index': 0},
          }),
          _action('role_override', <String, dynamic>{
            'operation': 'set',
            'target': <String, dynamic>{'row_index': 1},
            'role': 'vocals',
          }),
          _action('tutorial', <String, dynamic>{
            'topic': 'Mute Track',
            'steps': <Map<String, dynamic>>[
              <String, dynamic>{
                'text': 'Tap mute on track header',
                'target_id': 'mute'
              },
            ],
          }),
          _action('clarify', <String, dynamic>{
            'question': 'Which clip should I edit?',
            'options': <String>['selected clip', 'all selected clips'],
          }),
          _action('role_override', <String, dynamic>{
            'operation': 'clear',
            'target': <String, dynamic>{'row_index': 1},
          }),
        ],
      );

      expect(next.clips.length, 4);
      final labels = next.clips.map((c) => c.label).toList(growable: false);
      expect(labels.any((s) => s.contains('Vocals')), isTrue);
      expect(labels.any((s) => s.contains('Instrumental')), isTrue);
      expect(next.roleOverrides.containsKey(1), isFalse);
      expect(next.activeTutorialTarget, 'tutorial:mute');
      expect(next.tutorialMessages, contains('Tap mute on track header'));
      expect(next.clarifyQuestion, 'Which clip should I edit?');
      expect(next.clarifyOptions.length, 2);
    });
  });

  group('AssistantActionTimelineReducer integration', () {
    test('multi-family action chain produces coherent timeline state', () {
      final initial = TimelineActionState.empty(
        projectTempoBpm: 128.0,
        clips: <TimelineClip>[
          _audioClip(id: 'kick', row: 0, label: 'Kick Loop'),
          _audioClip(
              id: 'vox',
              row: 1,
              label: 'Podcast Vox',
              sourceDurationMs: 8000.0),
          _midiClip(id: 'bass', row: 2, label: 'Bass MIDI'),
        ],
        selectedClipIndices: const <int>[1],
        primarySelectedClipIndex: 1,
        selectedRowIndex: 1,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('clip_edit', <String, dynamic>{
            'operation': 'dialog_cleanup',
            'target': <String, dynamic>{'clip_index': 1},
            'ranges': <Map<String, dynamic>>[
              <String, dynamic>{'from_ms': 900, 'to_ms': 1100},
            ],
          }),
          _action('automation_edit', <String, dynamic>{
            'operation': 'apply_template',
            'template': 'sidechain_from_kick',
            'target': <String, dynamic>{'row_index': 1, 'target_id': 'volume'},
            'source_clip_index': 0,
            'max_events': 3,
          }),
          _action('midi_compose', <String, dynamic>{
            'operation': 'chop_notes',
            'target': <String, dynamic>{'clip_index': 2},
            'subdivision': 16,
          }),
          _action('stem_separate', <String, dynamic>{
            'operation': 'vocal_instrumental',
            'target': <String, dynamic>{'clip_index': 1},
          }),
          _action('role_override', <String, dynamic>{
            'operation': 'set',
            'target': <String, dynamic>{'row_index': 1},
            'role': 'vocals',
          }),
        ],
      );

      expect(next.clips.length, greaterThanOrEqualTo(5));
      expect(next.clips.where((c) => c.isMidi).first.midiNotes.length,
          greaterThan(1));
      expect(next.automationClips['1::volume'], isNotNull);
      expect(next.automationClips['1::volume']!.isNotEmpty, isTrue);
      expect(next.roleOverrides[1], 'vocals');
    });
  });
}
