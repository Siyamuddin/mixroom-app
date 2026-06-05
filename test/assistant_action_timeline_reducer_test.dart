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

    test('glue consolidates selected audio clips on the same row', () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _audioClip(id: 'a0', startMs: 500.0, sourceDurationMs: 1000.0),
          _audioClip(id: 'a1', startMs: 1750.0, sourceDurationMs: 1250.0),
          _audioClip(id: 'b0', row: 1, startMs: 0.0),
        ],
        selectedClipIndices: const <int>[0, 1],
        primarySelectedClipIndex: 0,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('clip_edit', <String, dynamic>{
            'operation': 'glue',
            'label': 'Hook Comp',
            'target': <String, dynamic>{'prefer_selected': true},
          }),
        ],
      );

      expect(next.clips.length, 2);
      expect(next.clips.first.id, 'glued_a0_a1');
      expect(next.clips.first.label, 'Hook Comp');
      expect(next.clips.first.startMs, closeTo(500.0, 0.001));
      expect(next.clips.first.trimEndMs, closeTo(2500.0, 0.001));
      expect(next.clips.first.tempoFollow, isFalse);
      expect(next.selectedClipIndices, const <int>[0]);
      expect(next.clips[1].id, 'b0');
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

    test('duplicate supports repeat_count with musical spacing', () {
      final initial = TimelineActionState.empty(
        projectTempoBpm: 120.0,
        clips: <TimelineClip>[_audioClip(id: 'kick', sourceDurationMs: 1000.0)],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('clip_edit', <String, dynamic>{
            'operation': 'duplicate',
            'target': <String, dynamic>{'clip_index': 0},
            'paste_start_measure': 2,
            'repeat_count': 4,
            'step_measures': 1,
          }),
        ],
      );

      expect(next.clips.length, 5);
      expect(
        next.clips.skip(1).map((c) => c.startMs).toList(),
        <double>[2000.0, 4000.0, 6000.0, 8000.0],
      );
    });

    test('sample_insert supports repeat_count with beat spacing', () {
      final initial = TimelineActionState.empty(projectTempoBpm: 120.0);

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('sample_insert', <String, dynamic>{
            'operation': 'insert_audio_clips',
            'items': [
              {
                'library_path': 'Starter Kit v1/Processed Drums/Kick-01.mp3',
                'row_index': 0,
                'start_measure': 1,
                'repeat_count': 4,
                'step_beats': 1,
              },
            ],
          }),
        ],
      );

      expect(next.clips.length, 4);
      expect(
        next.clips.map((c) => c.startMs).toList(),
        <double>[0.0, 500.0, 1000.0, 1500.0],
      );
    });

    test('sample_insert infers sane drum spacing when repeat_count has no step',
        () {
      final initial = TimelineActionState.empty(projectTempoBpm: 120.0);

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('sample_insert', <String, dynamic>{
            'operation': 'insert_audio_clips',
            'items': [
              {
                'library_path': 'Starter Kit v1/Processed Drums/Kick-01.mp3',
                'row_index': 0,
                'repeat_count': 4,
              },
              {
                'library_path': 'Starter Kit v1/Processed Drums/Snare-01.mp3',
                'row_index': 1,
                'repeat_count': 4,
              },
              {
                'library_path': 'Starter Kit v1/Processed Drums/Crash-01.mp3',
                'row_index': 2,
                'repeat_count': 3,
              },
            ],
          }),
        ],
      );

      final kickStarts = next.clips
          .where((c) => c.rowIndex == 0)
          .map((c) => c.startMs)
          .toList();
      final snareStarts = next.clips
          .where((c) => c.rowIndex == 1)
          .map((c) => c.startMs)
          .toList();
      final crashStarts = next.clips
          .where((c) => c.rowIndex == 2)
          .map((c) => c.startMs)
          .toList();

      expect(kickStarts, <double>[0.0, 500.0, 1000.0, 1500.0]);
      expect(snareStarts, <double>[500.0, 1500.0, 2500.0, 3500.0]);
      expect(crashStarts, <double>[0.0, 4000.0, 8000.0]);
    });

    test('sample_insert derives section length from musical span fields', () {
      final initial = TimelineActionState.empty(projectTempoBpm: 120.0);

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('sample_insert', <String, dynamic>{
            'operation': 'insert_audio_clips',
            'items': [
              {
                'library_path': 'Starter Kit v1/Processed Drums/Hat-01.mp3',
                'row_index': 0,
                'start_measure': 1,
                'length_measures': 2,
                'step_beats': 1,
              },
            ],
          }),
        ],
      );

      expect(next.clips.length, 8);
      expect(next.clips.first.startMs, 0.0);
      expect(next.clips.last.startMs, 3500.0);
    });

    test(
        'sample_insert keeps repeated drum layers spanning the declared section',
        () {
      final initial = TimelineActionState.empty(projectTempoBpm: 120.0);

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('sample_insert', <String, dynamic>{
            'operation': 'insert_audio_clips',
            'items': [
              {
                'library_path': 'Starter Kit v1/Processed Drums/Kick-01.mp3',
                'row_index': 0,
                'start_measure': 1,
                'repeat_count': 8,
                'step_beats': 1,
                'length_measures': 8,
              },
              {
                'library_path': 'Starter Kit v1/Processed Drums/Snare-01.mp3',
                'row_index': 1,
                'start_measure': 1,
                'repeat_count': 8,
                'step_beats': 2,
                'length_measures': 8,
              },
              {
                'library_path': 'Starter Kit v1/Processed Drums/Hi-Hat-01.mp3',
                'row_index': 2,
                'start_measure': 1,
                'repeat_count': 8,
                'step_beats': 0.5,
                'length_measures': 8,
              },
            ],
          }),
        ],
      );

      expect(next.clips.where((c) => c.rowIndex == 0), hasLength(32));
      expect(next.clips.where((c) => c.rowIndex == 1), hasLength(16));
      expect(next.clips.where((c) => c.rowIndex == 2), hasLength(64));
    });

    test(
        'sample_insert replace_audio_clips preserves timing while swapping labels',
        () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _audioClip(id: 'k0', row: 0, startMs: 0.0, label: 'Kick-01.mp3'),
          _audioClip(id: 's0', row: 1, startMs: 500.0, label: 'Snare-01.mp3'),
          _audioClip(id: 's1', row: 1, startMs: 1500.0, label: 'Snare-01.mp3'),
        ],
        selectedClipIndices: const <int>[1, 2],
        primarySelectedClipIndex: 1,
        selectedRowIndex: 1,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('sample_insert', <String, dynamic>{
            'operation': 'replace_audio_clips',
            'items': [
              {
                'library_path': 'Starter Kit v1/Processed Drums/Snare-02.mp3',
                'target': <String, dynamic>{
                  'row_index': 1,
                  'label_contains': 'snare',
                },
              },
            ],
          }),
        ],
      );

      expect(next.clips.length, 3);
      expect(next.clips[0].label, 'Kick-01.mp3');
      expect(next.clips[1].label, 'Snare-02.mp3');
      expect(next.clips[2].label, 'Snare-02.mp3');
      expect(next.clips[1].startMs, closeTo(500.0, 0.001));
      expect(next.clips[2].startMs, closeTo(1500.0, 0.001));
    });

    test('clip duplicate derives repeat count from until_measure', () {
      final initial = TimelineActionState.empty(
        projectTempoBpm: 120.0,
        clips: <TimelineClip>[
          _audioClip(
            id: 'loop0',
            row: 0,
            startMs: 0.0,
            sourceDurationMs: 1000.0,
          ),
        ],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('clip_edit', <String, dynamic>{
            'operation': 'duplicate',
            'target': <String, dynamic>{'clip_index': 0},
            'paste_start_measure': 2,
            'step_measures': 1,
            'until_measure': 5,
          }),
        ],
      );

      expect(next.clips.length, 5);
      expect(
        next.clips.map((c) => c.startMs).toList(),
        <double>[0.0, 2000.0, 4000.0, 6000.0, 8000.0],
      );
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
          _action('automation_edit', <String, dynamic>{
            'operation': 'apply_template',
            'template': 'auto_pan',
            'direction': 'right',
            'target': <String, dynamic>{'row_index': 3, 'target_id': 'pan'},
            'start_ms': 200,
            'length_ms': 800,
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

      final autoPanLane = next.automationClips['3::pan']!;
      expect(autoPanLane.length, 1);
      expect(autoPanLane.first.points.length, 6);
      expect(autoPanLane.first.points.first.volume, closeTo(0.5, 0.001));
      expect(autoPanLane.first.points[1].volume, greaterThan(0.8));
      expect(autoPanLane.first.points[3].volume, lessThan(0.2));
      expect(autoPanLane.first.points.last.volume, closeTo(0.5, 0.001));
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

    test('convert_audio_to_midi adds a midi clip below the source audio row',
        () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _audioClip(
            id: 'vox',
            row: 2,
            startMs: 2400.0,
            sourceDurationMs: 3200.0,
            label: 'Lead Vox',
          ),
        ],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
        selectedRowIndex: 2,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('midi_compose', <String, dynamic>{
            'operation': 'audio_to_midi',
            'target': <String, dynamic>{'prefer_selected': true},
          }),
        ],
      );

      final midiClips =
          next.clips.where((clip) => clip.isMidi).toList(growable: false);
      expect(midiClips, hasLength(1));
      expect(midiClips.single.rowIndex, 3);
      expect(midiClips.single.startMs, 2400.0);
      expect(midiClips.single.label, 'Lead Vox MIDI');
    });

    test('create_clip adds a fresh midi clip instead of reusing selection', () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _midiClip(
            id: 'm0',
            row: 1,
            notes: <MidiNote>[
              MidiNote(
                id: 'n0',
                pitch: 48,
                startBeat: 0.0,
                lengthBeats: 4.0,
                velocity: 0.8,
              ),
            ],
          ),
        ],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
        selectedRowIndex: 1,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('midi_compose', <String, dynamic>{
            'operation': 'create_clip',
            'target': <String, dynamic>{'prefer_selected': true},
            'create_new_clip': true,
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 60,
                'start_beat': 0.0,
                'length_beats': 4.0,
                'velocity': 0.8,
              },
            ],
          }),
        ],
      );

      final midiClips =
          next.clips.where((clip) => clip.isMidi).toList(growable: false);
      expect(midiClips, hasLength(2));
      expect(midiClips.first.midiNotes.first.pitch, 48);
      expect(midiClips.last.midiNotes.first.pitch, 60);
    });

    test('fresh generated midi clips stretch to requested/default section span',
        () {
      final initial = TimelineActionState.empty(
        selectedRowIndex: 1,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('midi_compose', <String, dynamic>{
            'operation': 'create_clip',
            'target': <String, dynamic>{'row_index': 1},
            'create_new_clip': true,
            'length_measures': 8,
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 60,
                'start_beat': 0.0,
                'length_beats': 4.0,
                'velocity': 0.8,
              },
            ],
          }),
        ],
      );

      final midiClip = next.clips.singleWhere((clip) => clip.isMidi);
      final lastEnd = midiClip.midiNotes
          .map((n) => n.startBeat + n.lengthBeats)
          .fold<double>(0.0, math.max);
      expect(lastEnd, closeTo(32.0, 1e-6));
      expect(midiClip.midiNotes.length, 8);
    });

    test('create_clip honors note measure plus beat positions', () {
      final initial = TimelineActionState.empty(
        selectedRowIndex: 1,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('midi_compose', <String, dynamic>{
            'operation': 'create_clip',
            'target': <String, dynamic>{'row_index': 1},
            'create_new_clip': true,
            'length_measures': 8,
            'notes': <Map<String, dynamic>>[
              <String, dynamic>{
                'pitch': 50,
                'measure': 1,
                'beat': 1,
                'duration_beats': 4,
                'velocity': 72,
              },
              <String, dynamic>{
                'pitch': 43,
                'measure': 2,
                'beat': 1,
                'duration_beats': 4,
                'velocity': 72,
              },
              <String, dynamic>{
                'pitch': 45,
                'measure': 3,
                'beat': 3,
                'duration_beats': 2,
                'velocity': 72,
              },
            ],
          }),
        ],
      );

      final midiClip = next.clips.singleWhere((clip) => clip.isMidi);
      expect(midiClip.midiNotes[0].startBeat, closeTo(0.0, 1e-6));
      expect(midiClip.midiNotes[1].startBeat, closeTo(4.0, 1e-6));
      expect(midiClip.midiNotes[2].startBeat, closeTo(10.0, 1e-6));
      expect(midiClip.midiNotes[0].velocity, closeTo(72 / 127, 1e-6));
    });

    test('length-only preserve_existing_notes repeats midi phrase to target',
        () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _midiClip(
            id: 'm0',
            row: 1,
            notes: <MidiNote>[
              MidiNote(
                id: 'n0',
                pitch: 60,
                startBeat: 0.0,
                lengthBeats: 4.0,
                velocity: 0.8,
              ),
            ],
          ),
        ],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
        selectedRowIndex: 1,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('midi_compose', <String, dynamic>{
            'operation': 'replace_notes',
            'target': <String, dynamic>{'prefer_selected': true},
            'preserve_existing_notes': true,
            'length_measures': 8,
          }),
        ],
      );

      final midiClip = next.clips.singleWhere((clip) => clip.isMidi);
      expect(midiClip.midiNotes.length, 8);
      final lastEnd = midiClip.midiNotes
          .map((n) => n.startBeat + n.lengthBeats)
          .fold<double>(0.0, math.max);
      expect(lastEnd, closeTo(32.0, 1e-6));
    });

    test(
        'duration_seconds preserve_existing_notes repeats midi phrase to target',
        () {
      final initial = TimelineActionState.empty(
        projectTempoBpm: 120,
        clips: <TimelineClip>[
          _midiClip(
            id: 'm0',
            row: 1,
            notes: <MidiNote>[
              MidiNote(
                id: 'n0',
                pitch: 60,
                startBeat: 0.0,
                lengthBeats: 4.0,
                velocity: 0.8,
              ),
            ],
          ),
        ],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
        selectedRowIndex: 1,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('midi_compose', <String, dynamic>{
            'operation': 'replace_notes',
            'target': <String, dynamic>{'prefer_selected': true},
            'preserve_existing_notes': true,
            'duration_seconds': 60,
          }),
        ],
      );

      final midiClip = next.clips.singleWhere((clip) => clip.isMidi);
      final lastEnd = midiClip.midiNotes
          .map((n) => n.startBeat + n.lengthBeats)
          .fold<double>(0.0, math.max);
      expect(lastEnd, closeTo(120.0, 1e-6));
      expect(midiClip.midiNotes.length, 30);
    });

    test('style-driven append_notes can add a topline over the same clip span',
        () {
      final initial = TimelineActionState.empty(
        clips: <TimelineClip>[
          _midiClip(
            id: 'm0',
            row: 1,
            notes: <MidiNote>[
              MidiNote(
                id: 'c0',
                pitch: 48,
                startBeat: 0.0,
                lengthBeats: 4.0,
                velocity: 0.8,
              ),
              MidiNote(
                id: 'e0',
                pitch: 52,
                startBeat: 0.0,
                lengthBeats: 4.0,
                velocity: 0.8,
              ),
              MidiNote(
                id: 'g0',
                pitch: 55,
                startBeat: 0.0,
                lengthBeats: 4.0,
                velocity: 0.8,
              ),
              MidiNote(
                id: 'a1',
                pitch: 45,
                startBeat: 4.0,
                lengthBeats: 4.0,
                velocity: 0.8,
              ),
              MidiNote(
                id: 'c1',
                pitch: 48,
                startBeat: 4.0,
                lengthBeats: 4.0,
                velocity: 0.8,
              ),
              MidiNote(
                id: 'e1',
                pitch: 52,
                startBeat: 4.0,
                lengthBeats: 4.0,
                velocity: 0.8,
              ),
            ],
          ),
        ],
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
        selectedRowIndex: 1,
      );

      final next = AssistantActionTimelineReducer.applyActions(
        initial,
        <AssistantAction>[
          _action('midi_compose', <String, dynamic>{
            'operation': 'append_notes',
            'target': <String, dynamic>{'prefer_selected': true},
            'length_measures': 2,
            'preserve_existing_notes': true,
            'style': 'running topline',
            'register': 'upper',
            'density': 'medium',
            'direction': 'mostly_stepwise',
          }),
        ],
      );

      final midiClip = next.clips.singleWhere((clip) => clip.isMidi);
      expect(
        midiClip.midiNotes.length,
        greaterThan(initial.clips.first.midiNotes.length),
      );
      final generated = midiClip.midiNotes
          .where((note) => note.startBeat > 0.0 && note.startBeat < 8.0)
          .toList(growable: false);
      expect(generated, isNotEmpty);
      final lastGeneratedEnd = generated
          .map((n) => n.startBeat + n.lengthBeats)
          .fold<double>(0.0, math.max);
      expect(lastGeneratedEnd, closeTo(8.0, 1e-6));
      expect(midiClip.midiNotes.any((note) => note.pitch > 60), isTrue);
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
