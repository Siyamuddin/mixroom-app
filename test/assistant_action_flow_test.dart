import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/chat_pipeline.dart';
import 'package:mixroom/ai/cloud_llm_service.dart';
import 'package:mixroom/ai/instrument_classifier.dart';
import 'package:mixroom/ai/local_mixing_model.dart';
import 'package:mixroom/ai/project_state_builder.dart';
import 'package:mixroom/models/mixing_result.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/models/project_state.dart';

class _FakeCloudLlmService extends CloudLlmService {
  _FakeCloudLlmService(this._next) : super(apiKey: 'test-key', model: 'test');

  final LlmResult _next;
  String? seenSelectionSnapshot;
  String? seenProjectSnapshot;
  String? seenUserText;

  @override
  Future<LlmResult> send({
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    String selectionSnapshot = '',
    String librarySnapshot = '',
    String? projectId,
    String? aiFeature,
    String? promptTraceId,
    MixingResult? pendingMix,
  }) async {
    seenUserText = userText;
    seenProjectSnapshot = projectSnapshot;
    seenSelectionSnapshot = selectionSnapshot;
    return _next;
  }
}

class _QueuedFakeCloudLlmService extends CloudLlmService {
  _QueuedFakeCloudLlmService(this._results)
      : super(apiKey: 'test-key', model: 'test');

  final List<LlmResult> _results;
  final List<List<Map<String, String>>> seenConversations =
      <List<Map<String, String>>>[];

  @override
  Future<LlmResult> send({
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    String selectionSnapshot = '',
    String librarySnapshot = '',
    String? projectId,
    String? aiFeature,
    String? promptTraceId,
    MixingResult? pendingMix,
  }) async {
    seenConversations.add(
      conversation
          .map((entry) => Map<String, String>.from(entry))
          .toList(growable: false),
    );
    if (_results.isEmpty) {
      throw StateError('No queued LLM results remaining.');
    }
    return _results.removeAt(0);
  }
}

class _FakeProjectStateBuilder extends ProjectStateBuilder {
  _FakeProjectStateBuilder({
    this.rows = 5,
    this.masterEffects = const <EffectState>[],
    this.rowEffects = const <int, List<EffectState>>{},
    this.rowAudioStats = const <int, Map<String, double>>{},
    this.rowInterpretations = const <int, RowInterpretationState>{},
    this.rowApproxRms = const <int, double>{},
    this.rowApproxCrest = const <int, double>{},
  }) : super(classifier: InstrumentClassifier(), maxRows: rows);

  final int rows;
  final List<EffectState> masterEffects;
  final Map<int, List<EffectState>> rowEffects;
  final Map<int, Map<String, double>> rowAudioStats;
  final Map<int, RowInterpretationState> rowInterpretations;
  final Map<int, double> rowApproxRms;
  final Map<int, double> rowApproxCrest;

  @override
  Future<ProjectState> build({
    required List<AudioTrack> audioTracks,
    required double bpmFallback,
    required List<double> rowGain,
    required List<double> rowPan,
    required List<List<AutomationPoint>> rowAutomation,
    double masterGain0to3 = 1.0,
    double masterPan0to1 = 0.5,
    Map<int, String> roleOverrides = const {},
  }) async {
    final rowStates = List<RowState>.generate(rows, (row) {
      final rowTracks = audioTracks.where((t) => t.rowIndex == row).toList();
      final clips = rowTracks
          .map(
            (t) => ClipState(
              startMs: t.offset * 1000.0,
              endMs: t.offset * 1000.0 +
                  (t.trimEnd - t.trimStart).inMilliseconds.toDouble(),
              fileName: t.file.path.split('/').last,
              gain0to3: t.gain,
              pitchSemitones: t.pitchSemitones,
            ),
          )
          .toList();

      return RowState(
        rowIndex: row,
        clips: clips,
        approxRms: rowTracks.isEmpty ? 0.0 : (rowApproxRms[row] ?? 0.2),
        approxCrest: rowTracks.isEmpty ? 0.0 : (rowApproxCrest[row] ?? 1.5),
        roleProbs: const {
          'vocals': 0.1,
          'drums': 0.2,
          'bass': 0.2,
          'guitar': 0.2,
          'synth': 0.2,
          'other': 0.1,
        },
        roleConsistency: 1.0,
        clipTopRoles: const ['other'],
        audioStats: rowAudioStats[row] ??
            const {
              'centroid_hz': 1200.0,
              'zcr': 0.1,
              'hf_rms': 0.1,
              'sibilance': 0.1,
              'bassiness': 0.1,
            },
        interpretation: rowInterpretations[row] ?? RowInterpretationState.empty,
        gain0to3: row < rowGain.length ? rowGain[row] : 1.0,
        pan0To1: row < rowPan.length ? rowPan[row] : 0.5,
        effects: rowEffects[row] ?? const <EffectState>[],
        volumeAutomation: row < rowAutomation.length
            ? rowAutomation[row]
            : const <AutomationPoint>[],
        hasAudio: rowTracks.isNotEmpty,
      );
    });

    final overlapMatrix =
        List<List<int>>.generate(rows, (_) => List<int>.filled(rows, 0));
    final overlapRatioMatrix =
        List<List<double>>.generate(rows, (_) => List<double>.filled(rows, 0));

    return ProjectState(
      bpm: bpmFallback,
      masterGain0to3: masterGain0to3,
      masterPan0to1: masterPan0to1,
      maxRows: rows,
      rows: rowStates,
      masterEffects: masterEffects,
      overlapMatrix: overlapMatrix,
      overlapRatioMatrix: overlapRatioMatrix,
    );
  }
}

Future<AudioTrack> _makeAudioTrack({
  required String path,
  required int row,
  String label = 'Audio Clip',
}) async {
  return AudioTrack.create(
    file: File(path),
    originalFile: File(path),
    audioDuration: const Duration(seconds: 4),
    trimStart: Duration.zero,
    trimEnd: const Duration(seconds: 4),
    offset: 0.0,
    rowIndex: row,
    rowId: row,
    label: label,
    clipKind: ClipKind.audio,
  );
}

Future<AudioTrack> _makeMidiTrack({
  required String path,
  required int row,
  String label = 'MIDI Clip',
}) async {
  return AudioTrack.create(
    file: File(path),
    originalFile: File(path),
    audioDuration: const Duration(seconds: 4),
    trimStart: Duration.zero,
    trimEnd: const Duration(seconds: 4),
    offset: 0.0,
    rowIndex: row,
    rowId: row,
    label: label,
    clipKind: ClipKind.midi,
    instrumentId: 'mixroom.sub_bass',
    instrumentName: 'Sub Bass',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Assistant Action Pipeline Smoke', () {
    test('forwards all added assistant action types via daw_assistant_actions',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'daw_assistant_actions',
          {
            'assistant_message': 'Stubbed assistant response.',
            'actions': [
              {
                'type': 'project_edit',
                'data': {
                  'operation': 'set_tempo',
                  'tempo_bpm': 156,
                },
              },
              {
                'type': 'sample_insert',
                'data': {
                  'operation': 'insert_audio_clips',
                  'items': [
                    {
                      'library_path':
                          'Starter Kit v1/Processed Drums/Kick-01.flac',
                      'row_index': 0,
                      'start_measure': 1,
                    },
                  ],
                },
              },
              {
                'type': 'tutorial',
                'data': {
                  'topic': 'recording',
                  'steps': [
                    {
                      'text': 'Tap record',
                      'target_id': 'tutorial:transport:record',
                    }
                  ]
                },
              },
              {
                'type': 'clarify',
                'data': {
                  'question': 'Which clip?',
                  'options': ['selected clip', 'all selected clips'],
                },
              },
              {
                'type': 'clip_edit',
                'data': {
                  'operation': 'auto_trim',
                  'target': {'scope': 'selected'}
                },
              },
              {
                'type': 'effect_edit',
                'data': {
                  'operation': 'remove',
                  'target': {
                    'row_index': 0,
                    'effect_name': 'Gain',
                  }
                },
              },
              {
                'type': 'automation_edit',
                'data': {
                  'operation': 'set_points',
                  'target': {'row_index': 0},
                  'points': [
                    {'x_ms': 0, 'value': 1.0},
                    {'x_ms': 1000, 'value': 0.8},
                  ],
                },
              },
              {
                'type': 'midi_compose',
                'data': {
                  'operation': 'compose_bassline',
                  'target': {'row_index': 1},
                  'notes': [
                    {
                      'pitch': 48,
                      'start_beat': 0,
                      'length_beats': 1,
                      'velocity': 0.8
                    },
                  ],
                },
              },
              {
                'type': 'stem_separate',
                'data': {
                  'operation': 'vocal_instrumental',
                  'target': {'clip_index': 0},
                },
              },
              {
                'type': 'role_override',
                'data': {
                  'operation': 'set',
                  'target': {'row_index': 0},
                  'role': 'vocals',
                },
              },
            ],
          },
          text: 'Stubbed assistant response.',
        ),
      );

      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 5),
        mixModel: LocalMixingModel(),
      );

      final audio = await _makeAudioTrack(path: '/tmp/test_audio.wav', row: 0);
      final midi = await _makeMidiTrack(path: '/tmp/test_midi.mid', row: 1);
      final tracks = <AudioTrack>[audio, midi];

      final result = await pipeline.handleUserText(
        text: 'Do tutorial + edit actions',
        audioTracks: tracks,
        rowGain: const [1.0, 1.0, 1.0, 1.0, 1.0],
        rowPan: const [0.5, 0.5, 0.5, 0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          5,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1.0),
            AutomationPoint(x: 1000, volume: 1.0),
          ],
        ),
        bpmFallback: 120.0,
        selectedClipIndices: const [0],
        primarySelectedClipIndex: 0,
        selectedRowIndex: 0,
      );

      expect(result.hasAssistantActions, isTrue);
      expect(result.assistantActions.length, 10);
      expect(
        result.assistantActions.map((a) => a.type).toSet(),
        equals(const {
          'project_edit',
          'sample_insert',
          'tutorial',
          'clarify',
          'clip_edit',
          'effect_edit',
          'automation_edit',
          'midi_compose',
          'stem_separate',
          'role_override',
        }),
      );

      expect(fakeLlm.seenSelectionSnapshot, isNotNull);
      expect(fakeLlm.seenSelectionSnapshot, contains('selected_row_index=0'));
      expect(
          fakeLlm.seenSelectionSnapshot, contains('selected_clip_indices=0'));
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains('primary_selected_clip_index=0'),
      );
      expect(fakeLlm.seenSelectionSnapshot, contains('selected_clip[0]'));
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains('selected_row_automation_targets='),
      );
    });

    test(
        'selection snapshot forwards automation clip metadata for AI targeting',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'informational_response',
          {'message': 'Captured.'},
          text: 'Captured.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 2),
        mixModel: LocalMixingModel(),
      );

      await pipeline.handleUserText(
        text: 'Tweak that automation clip.',
        audioTracks: const <AudioTrack>[],
        rowGain: const [1.0, 1.0],
        rowPan: const [0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          2,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1.0),
          ],
        ),
        bpmFallback: 120.0,
        selectedRowIndex: 0,
        automationClipSnapshot:
            'selected_row_automation_clips=Volume[volume]=#0{clip_id=ac_1,start_ms=0.0,length_ms=500.0,lane=0,muted=false,pattern_id=pat_shared}',
      );

      expect(
        fakeLlm.seenSelectionSnapshot,
        contains('selected_row_automation_clips='),
      );
      expect(fakeLlm.seenSelectionSnapshot, contains('clip_id=ac_1'));
      expect(fakeLlm.seenSelectionSnapshot, contains('pattern_id=pat_shared'));
    });

    test('accepts full operation surface in a single stubbed action payload',
        () async {
      final actions = <Map<String, dynamic>>[
        for (final op in const [
          'trim',
          'auto_trim',
          'cut',
          'stretch',
          'move',
          'tempo_follow',
          'auto_bpm_align',
          'tempo_detect_set_project',
          'duplicate',
          'delete',
          'dialog_cleanup',
          'dialog_remove_range',
          'dialog_tighten_pauses',
          'dialog_lift_quiet',
        ])
          {
            'type': 'clip_edit',
            'data': {
              'operation': op,
              'target': {'clip_index': 0}
            }
          },
        for (final op in const [
          'add',
          'remove',
          'bypass',
          'unbypass',
          'toggle_bypass',
        ])
          {
            'type': 'effect_edit',
            'data': {
              'operation': op,
              'target': {'row_index': 0, 'effect_name': 'Gain'}
            }
          },
        for (final op in const [
          'set_points',
          'add_ramp',
          'clear',
          'create_clip',
          'duplicate_clip',
          'move_clip',
          'delete_clip',
          'clear_clips',
          'mute_clip',
          'unmute_clip',
          'toggle_clip_mute',
          'set_clip_points',
          'apply_template',
        ])
          {
            'type': 'automation_edit',
            'data': {
              'operation': op,
              'target': {'row_index': 0}
            }
          },
        for (final op in const [
          'compose_bassline',
          'compose_pattern',
          'replace_notes',
          'append_notes',
          'chop_notes',
        ])
          {
            'type': 'midi_compose',
            'data': {
              'operation': op,
              'target': {'row_index': 1},
              'notes': [
                {
                  'pitch': 48,
                  'start_beat': 0,
                  'length_beats': 1,
                  'velocity': 0.8,
                }
              ]
            }
          },
        {
          'type': 'stem_separate',
          'data': {
            'operation': 'vocal_instrumental',
            'target': {'clip_index': 0}
          }
        },
        {
          'type': 'role_override',
          'data': {
            'operation': 'set',
            'target': {'row_index': 0},
            'role': 'drums',
          }
        },
      ];

      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'daw_assistant_actions',
          {
            'assistant_message': 'Surface test.',
            'actions': actions,
          },
          text: 'Surface test.',
        ),
      );

      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 5),
        mixModel: LocalMixingModel(),
      );

      final audio =
          await _makeAudioTrack(path: '/tmp/test_audio_2.wav', row: 0);
      final midi = await _makeMidiTrack(path: '/tmp/test_midi_2.mid', row: 1);

      final result = await pipeline.handleUserText(
        text: 'Run surface operation payload',
        audioTracks: <AudioTrack>[audio, midi],
        rowGain: const [1, 1, 1, 1, 1],
        rowPan: const [0.5, 0.5, 0.5, 0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          5,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1),
            AutomationPoint(x: 1000, volume: 1),
          ],
        ),
        bpmFallback: 120,
        selectedClipIndices: const [0],
        primarySelectedClipIndex: 0,
        selectedRowIndex: 0,
      );

      expect(result.hasAssistantActions, isTrue);
      expect(result.assistantActions.length, actions.length);
      expect(
        result.assistantActions
            .where((a) => a.type == 'clip_edit')
            .map((a) => (a.data['operation'] ?? '').toString())
            .toSet(),
        equals(const {
          'trim',
          'auto_trim',
          'cut',
          'stretch',
          'move',
          'tempo_follow',
          'auto_bpm_align',
          'tempo_detect_set_project',
          'duplicate',
          'delete',
          'dialog_cleanup',
          'dialog_remove_range',
          'dialog_tighten_pauses',
          'dialog_lift_quiet',
        }),
      );
      expect(
        result.assistantActions
            .where((a) => a.type == 'automation_edit')
            .map((a) => (a.data['operation'] ?? '').toString())
            .toSet(),
        equals(const {
          'set_points',
          'add_ramp',
          'clear',
          'create_clip',
          'duplicate_clip',
          'move_clip',
          'delete_clip',
          'clear_clips',
          'mute_clip',
          'unmute_clip',
          'toggle_clip_mute',
          'set_clip_points',
          'apply_template',
        }),
      );
      expect(
        result.assistantActions
            .where((a) => a.type == 'midi_compose')
            .map((a) => (a.data['operation'] ?? '').toString())
            .toSet(),
        equals(const {
          'compose_bassline',
          'compose_pattern',
          'replace_notes',
          'append_notes',
          'chop_notes',
        }),
      );
    });

    test('delegates broad move-to-beginning clip commands to the LLM',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'daw_assistant_actions',
          {
            'assistant_message': 'Moved all clips to the beginning.',
            'actions': [
              {
                'type': 'clip_edit',
                'data': {
                  'operation': 'move',
                  'target': {'scope': 'all'},
                  'snap_to': 'start',
                },
              },
            ],
          },
          text: 'Moved all clips to the beginning.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 2),
        mixModel: LocalMixingModel(),
      );

      final audio = await _makeAudioTrack(path: '/tmp/test_audio.wav', row: 0);
      final result = await pipeline.handleUserText(
        text: 'move all clips to beginning',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1.0, 1.0],
        rowPan: const [0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          2,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1.0),
          ],
        ),
        bpmFallback: 120.0,
      );

      expect(fakeLlm.seenUserText, 'move all clips to beginning');
      expect(result.message, 'Moved all clips to the beginning.');
      expect(result.hasAssistantActions, isTrue);
      expect(result.assistantActions, hasLength(1));
      expect(result.assistantActions.first.type, 'clip_edit');
      expect(result.assistantActions.first.data['operation'], 'move');
      expect(result.assistantActions.first.data['snap_to'], 'start');
      expect(
        (result.assistantActions.first.data['target'] as Map)['scope'],
        'all',
      );
      expect(result.meta?['tool'], 'daw_assistant_actions');
    });

    test('delegates broad move-to-measure clip commands to the LLM', () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'daw_assistant_actions',
          {
            'assistant_message': 'Moved all clips to measure 3.',
            'actions': [
              {
                'type': 'clip_edit',
                'data': {
                  'operation': 'move',
                  'target': {'scope': 'all'},
                  'new_start_measure': 3,
                },
              },
            ],
          },
          text: 'Moved all clips to measure 3.',
        ),
      );

      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 4),
        mixModel: LocalMixingModel(),
      );

      final result = await pipeline.handleUserText(
        text: 'move all clips to measure 3',
        audioTracks: const <AudioTrack>[],
        rowGain: const [1, 1, 1, 1],
        rowPan: const [0.5, 0.5, 0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          4,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1),
            AutomationPoint(x: 1000, volume: 1),
          ],
        ),
        bpmFallback: 120,
      );

      expect(result.hasAssistantActions, isTrue);
      expect(result.assistantActions.single.type, 'clip_edit');
      expect(
        result.assistantActions.single.data['target'],
        <String, dynamic>{'scope': 'all'},
      );
      expect(result.assistantActions.single.data['new_start_measure'], 3);
      expect(result.message, 'Moved all clips to measure 3.');
      expect(result.meta?['tool'], 'daw_assistant_actions');
      expect(fakeLlm.seenUserText, 'move all clips to measure 3');
    });

    test('routes informational_response without mix execution', () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'informational_response',
          {'cancels_pending': false},
          text:
              'A compressor attack controls how quickly gain reduction starts.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 5),
        mixModel: LocalMixingModel(),
      );

      final audio =
          await _makeAudioTrack(path: '/tmp/test_audio_info.wav', row: 0);
      final result = await pipeline.handleUserText(
        text: 'What does compressor attack do?',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1, 1, 1, 1, 1],
        rowPan: const [0.5, 0.5, 0.5, 0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          5,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1),
            AutomationPoint(x: 1000, volume: 1),
          ],
        ),
        bpmFallback: 120,
      );

      expect(result.message, contains('attack controls'));
      expect(result.mixing, isNull);
      expect(result.hasAssistantActions, isFalse);
      expect(result.meta?['tool'], 'informational_response');
    });

    test('stores clarify text in conversation instead of hidden assistant copy',
        () async {
      final fakeLlm = _QueuedFakeCloudLlmService(<LlmResult>[
        LlmResult.tool(
          'daw_assistant_actions',
          {
            'assistant_message': 'Done.',
            'actions': [
              {
                'type': 'clarify',
                'data': {
                  'question': 'Which clip should I move?',
                  'options': ['selected clip', 'all clips'],
                },
              },
            ],
          },
          text: 'Done.',
        ),
        LlmResult.tool(
          'informational_response',
          {'cancels_pending': false},
          text: 'Captured.',
        ),
      ]);
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 2),
        mixModel: LocalMixingModel(),
      );

      final audio =
          await _makeAudioTrack(path: '/tmp/test_audio_clarify.wav', row: 0);
      final rowAutomation = List<List<AutomationPoint>>.generate(
        2,
        (_) => <AutomationPoint>[AutomationPoint(x: 0, volume: 1)],
      );

      await pipeline.handleUserText(
        text: 'move it',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1, 1],
        rowPan: const [0.5, 0.5],
        rowAutomation: rowAutomation,
        bpmFallback: 120,
      );

      await pipeline.handleUserText(
        text: 'selected clip',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1, 1],
        rowPan: const [0.5, 0.5],
        rowAutomation: rowAutomation,
        bpmFallback: 120,
      );

      final secondConversation = fakeLlm.seenConversations[1];
      expect(
        secondConversation.any(
          (entry) =>
              entry['role'] == 'assistant' &&
              entry['content'] ==
                  'Which clip should I move?\n\nOptions: selected clip / all clips',
        ),
        isTrue,
      );
      expect(
        secondConversation.any(
          (entry) =>
              entry['role'] == 'assistant' && entry['content'] == 'Done.',
        ),
        isFalse,
      );
    });

    test('does not persist guessed assistant copy for direct effect edits',
        () async {
      final fakeLlm = _QueuedFakeCloudLlmService(<LlmResult>[
        LlmResult.tool(
          'daw_assistant_actions',
          {
            'assistant_message': 'Removed the Clipper plugin from track 1.',
            'actions': [
              {
                'type': 'effect_edit',
                'data': {
                  'operation': 'remove',
                  'target': {
                    'row_index': 0,
                    'effect_name': 'Gain',
                  },
                },
              },
            ],
          },
          text: 'Removed the Clipper plugin from track 1.',
        ),
        LlmResult.tool(
          'informational_response',
          {'cancels_pending': false},
          text: 'Captured.',
        ),
      ]);
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 2),
        mixModel: LocalMixingModel(),
      );

      final audio = await _makeAudioTrack(
          path: '/tmp/test_audio_effect_edit.wav', row: 0);
      final rowAutomation = List<List<AutomationPoint>>.generate(
        2,
        (_) => <AutomationPoint>[AutomationPoint(x: 0, volume: 1)],
      );

      await pipeline.handleUserText(
        text: 'Take out the plugin on the first track',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1, 1],
        rowPan: const [0.5, 0.5],
        rowAutomation: rowAutomation,
        bpmFallback: 120,
      );

      await pipeline.handleUserText(
        text: 'what happened?',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1, 1],
        rowPan: const [0.5, 0.5],
        rowAutomation: rowAutomation,
        bpmFallback: 120,
      );

      final secondConversation = fakeLlm.seenConversations[1];
      expect(
        secondConversation.any(
          (entry) =>
              entry['role'] == 'assistant' &&
              entry['content'] == 'Removed the Clipper plugin from track 1.',
        ),
        isFalse,
      );
    });

    test('merges wrapped daw_assistant_actions calls into one action list',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'daw_assistant_actions',
          {
            'calls': [
              {
                'assistant_message': 'Showing you in the UI.',
                'actions': [
                  {
                    'type': 'tutorial',
                    'data': {
                      'topic': 'reverb path',
                      'steps': [
                        {
                          'text': 'Open the drums effects tab.',
                          'target_id': 'row:0:effects_tab',
                        }
                      ],
                    },
                  }
                ],
              },
              {
                'actions': [
                  {
                    'type': 'tutorial',
                    'data': {
                      'topic': 'reverb mix control',
                      'steps': [
                        {
                          'text': 'Open the reverb mix control.',
                          'target_id': 'row:0:fx_contains:reverb:param:mix',
                        }
                      ],
                    },
                  }
                ],
              },
            ],
          },
          text: 'Showing you in the UI.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 2),
        mixModel: LocalMixingModel(),
      );

      final result = await pipeline.handleUserText(
        text: 'show me where the drum reverb mix is',
        audioTracks: const <AudioTrack>[],
        rowGain: const [1, 1],
        rowPan: const [0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          2,
          (_) => <AutomationPoint>[AutomationPoint(x: 0, volume: 1)],
        ),
        bpmFallback: 120,
        selectedRowIndex: 0,
      );

      expect(result.hasAssistantActions, isTrue);
      expect(result.message, 'Showing you in the UI.');
      expect(result.assistantActions, hasLength(2));
      final stepTargetIds = result.assistantActions
          .expand((a) => ((a.data['steps'] as List?) ?? const <dynamic>[]))
          .whereType<Map>()
          .map((step) => step['target_id'])
          .toList(growable: false);
      expect(
        stepTargetIds,
        containsAll(<String>[
          'row:0:effects_tab',
          'row:0:fx_contains:reverb:param:mix',
        ]),
      );
    });

    test('routes mix_model_request execute to an applied mix result', () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'mix_model_request',
          {
            'mode': 'execute',
            'assistant_message': 'Applying a vocal gain bump now.',
            'actions': [
              {
                'goal': {
                  'type': 'mix_request',
                  'intensity': 0.75,
                  'target': {
                    'scope': 'row',
                    'row_index': 0,
                    'confidence': 0.9,
                  },
                  'intents': [
                    {
                      'kind': 'gain',
                      'direction': 'up',
                      'confidence': 0.95,
                    }
                  ],
                }
              }
            ],
          },
          text: 'Applying a vocal gain bump now.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 5),
        mixModel: LocalMixingModel(),
      );

      final audio =
          await _makeAudioTrack(path: '/tmp/test_audio_mix_exec.wav', row: 0);
      final result = await pipeline.handleUserText(
        text: 'Turn this up a bit.',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1, 1, 1, 1, 1],
        rowPan: const [0.5, 0.5, 0.5, 0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          5,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1),
            AutomationPoint(x: 1000, volume: 1),
          ],
        ),
        bpmFallback: 120,
      );

      expect(result.hasMix, isTrue);
      expect(result.mixing, isNotNull);
      expect(result.mixing!.actions, isNotEmpty);
      expect(result.message, contains('Applying a vocal gain bump now.'));
      expect(result.meta?['tool'], 'mix_model_request');
      expect(result.meta?['mode'], 'execute');
    });

    test(
        'mix replies do not append local diagnostic notes to visible chat text',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'mix_model_request',
          {
            'mode': 'execute',
            'assistant_message': 'Pushing the mix toward the reference now.',
            'actions': [
              {
                'goal': {
                  'type': 'mix_request',
                  'intensity': 0.75,
                  'target': {
                    'scope': 'auto',
                    'confidence': 0.9,
                  },
                  'intents': [
                    {
                      'kind': 'balance',
                      'confidence': 0.95,
                    }
                  ],
                  'reference_target': {
                    'row_index': 1,
                    'confidence': 0.95,
                  },
                  'reference_mode': 'full_mix',
                  'reference_closeness': 'balanced',
                }
              }
            ],
          },
          text: 'Pushing the mix toward the reference now.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(
          rows: 2,
          rowApproxRms: const <int, double>{0: 0.11, 1: 0.28},
          rowAudioStats: const <int, Map<String, double>>{
            0: <String, double>{
              'centroid_hz': 1200.0,
              'spectral_rolloff_hz': 2200.0,
              'spectral_slope': -0.45,
              'hf_rms': 0.10,
              'bassiness': 0.16,
              'sibilance': 0.07,
              'side_ratio': 0.08,
              'phase_corr': 0.95,
              'stereo_imbalance': 0.03,
              'integrated_lufs_est': -18.0,
              'true_peak_dbfs': -6.0,
              'lra_est': 7.0,
              'transient_density': 0.52,
              'clip_ratio': 0.02,
              'st_rms_std': 0.12,
            },
            1: <String, double>{
              'centroid_hz': 3200.0,
              'spectral_rolloff_hz': 5600.0,
              'spectral_slope': -0.12,
              'hf_rms': 0.38,
              'bassiness': 0.32,
              'sibilance': 0.10,
              'side_ratio': 0.58,
              'phase_corr': 0.48,
              'stereo_imbalance': 0.02,
              'integrated_lufs_est': -10.5,
              'true_peak_dbfs': -1.8,
              'lra_est': 3.5,
              'transient_density': 0.28,
              'clip_ratio': 0.08,
              'st_rms_std': 0.06,
            },
          },
        ),
        mixModel: LocalMixingModel(),
      );

      final subject =
          await _makeAudioTrack(path: '/tmp/test_subject.wav', row: 0);
      final reference =
          await _makeAudioTrack(path: '/tmp/test_reference.wav', row: 1);
      final result = await pipeline.handleUserText(
        text: 'Match this closer to the reference.',
        audioTracks: <AudioTrack>[subject, reference],
        rowGain: const [1, 1],
        rowPan: const [0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          2,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1),
            AutomationPoint(x: 1000, volume: 1),
          ],
        ),
        bpmFallback: 120,
      );

      expect(result.hasMix, isTrue);
      expect(result.mixing, isNotNull);
      expect(result.mixing!.notes, isNotEmpty);
      expect(result.message, 'Pushing the mix toward the reference now.');
      expect(
        result.message,
        isNot(contains('The reference looks more like a single element')),
      );
    });

    test('unwraps wrapped mix_model_request calls and still produces a mix',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'mix_model_request',
          {
            'calls': [
              {
                'mode': 'execute',
                'assistant_message': 'Added reverb to the drums track.',
                'actions': [
                  {
                    'goal': {
                      'type': 'mix_request',
                      'intensity': 0.6,
                      'target': {
                        'scope': 'row',
                        'row_index': 0,
                        'confidence': 1.0,
                      },
                      'intents': [
                        {
                          'kind': 'reverb',
                          'direction': 'up',
                          'confidence': 0.9,
                        }
                      ],
                    }
                  }
                ],
              }
            ],
          },
          text: 'Added reverb to the drums track.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 5),
        mixModel: LocalMixingModel(),
      );

      final audio =
          await _makeAudioTrack(path: '/tmp/test_audio_mix_calls.wav', row: 0);
      final result = await pipeline.handleUserText(
        text: 'Add reverb to drums.',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1, 1, 1, 1, 1],
        rowPan: const [0.5, 0.5, 0.5, 0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          5,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1),
            AutomationPoint(x: 1000, volume: 1),
          ],
        ),
        bpmFallback: 120,
      );

      expect(result.hasMix, isTrue);
      expect(result.mixing, isNotNull);
      expect(result.mixing!.actions, isNotEmpty);
      expect(result.message, contains('Added reverb to the drums track.'));
      expect(result.meta?['tool'], 'mix_model_request');
      expect(result.meta?['mode'], 'execute');
    });

    test('routes mix_model_request propose to pending proposal message',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'mix_model_request',
          {
            'mode': 'propose',
            'assistant_message': 'I can tighten this with subtle EQ and gain.',
            'asks_permission': false,
            'actions': [
              {
                'goal': {
                  'type': 'mix_request',
                  'intensity': 0.6,
                  'target': {
                    'scope': 'row',
                    'row_index': 0,
                    'confidence': 0.9,
                  },
                  'intents': [
                    {
                      'kind': 'eq',
                      'descriptor': 'mud_cut',
                      'confidence': 0.8,
                    }
                  ],
                }
              }
            ],
          },
          text: 'I can tighten this with subtle EQ and gain.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 5),
        mixModel: LocalMixingModel(),
      );

      final audio = await _makeAudioTrack(
          path: '/tmp/test_audio_mix_propose.wav', row: 0);
      final result = await pipeline.handleUserText(
        text: 'Can you make this cleaner?',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1, 1, 1, 1, 1],
        rowPan: const [0.5, 0.5, 0.5, 0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          5,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1),
            AutomationPoint(x: 1000, volume: 1),
          ],
        ),
        bpmFallback: 120,
      );

      expect(result.hasMix, isFalse);
      expect(result.mixing, isNull);
      expect(
        result.message,
        contains('Reply "yes" to apply or "no" to cancel.'),
      );
      expect(result.meta?['tool'], 'mix_model_request');
      expect(result.meta?['mode'], 'propose');
    });

    test('proposal keeps assistant message primary and appends hint once',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'mix_model_request',
          {
            'mode': 'propose',
            'assistant_message':
                'I can clean this up with subtle EQ and level balancing.',
            'asks_permission': false,
            'actions': [
              {
                'goal': {
                  'type': 'mix_request',
                  'intensity': 0.6,
                  'target': {
                    'scope': 'row',
                    'row_index': 0,
                    'confidence': 0.9,
                  },
                  'intents': [
                    {
                      'kind': 'eq',
                      'descriptor': 'mud_cut',
                      'confidence': 0.8,
                    }
                  ],
                }
              }
            ],
          },
          text: 'I can clean this up with subtle EQ and level balancing.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 5),
        mixModel: LocalMixingModel(),
      );

      final audio = await _makeAudioTrack(
          path: '/tmp/test_audio_mix_propose_primary.wav', row: 0);
      final result = await pipeline.handleUserText(
        text: 'Clean this up a little.',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1, 1, 1, 1, 1],
        rowPan: const [0.5, 0.5, 0.5, 0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          5,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1),
            AutomationPoint(x: 1000, volume: 1),
          ],
        ),
        bpmFallback: 120,
      );

      expect(
        result.message.startsWith(
          'I can clean this up with subtle EQ and level balancing.',
        ),
        isTrue,
      );
      expect(
        RegExp('Reply "yes" to apply or "no" to cancel.')
            .allMatches(result.message)
            .length,
        1,
      );
    });

    test(
        'proposal does not duplicate approval hint if assistant already says it',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'mix_model_request',
          {
            'mode': 'propose',
            'assistant_message':
                'I can do that. Reply "yes" to apply or "no" to cancel.',
            'asks_permission': false,
            'actions': [
              {
                'goal': {
                  'type': 'mix_request',
                  'intensity': 0.6,
                  'target': {
                    'scope': 'row',
                    'row_index': 0,
                    'confidence': 0.9,
                  },
                  'intents': [
                    {
                      'kind': 'gain',
                      'direction': 'up',
                      'confidence': 0.8,
                    }
                  ],
                }
              }
            ],
          },
          text: 'I can do that. Reply "yes" to apply or "no" to cancel.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 5),
        mixModel: LocalMixingModel(),
      );

      final audio = await _makeAudioTrack(
          path: '/tmp/test_audio_mix_propose_dedupe.wav', row: 0);
      final result = await pipeline.handleUserText(
        text: 'Turn it up a little.',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1, 1, 1, 1, 1],
        rowPan: const [0.5, 0.5, 0.5, 0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          5,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1),
            AutomationPoint(x: 1000, volume: 1),
          ],
        ),
        bpmFallback: 120,
      );

      expect(
        RegExp('Reply "yes" to apply or "no" to cancel.')
            .allMatches(result.message)
            .length,
        1,
      );
    });

    test('proposal appends approval hint even when asks_permission is true',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'mix_model_request',
          {
            'mode': 'propose',
            'assistant_message': 'I can make that change.',
            'asks_permission': true,
            'actions': [
              {
                'goal': {
                  'type': 'mix_request',
                  'intensity': 0.6,
                  'target': {
                    'scope': 'row',
                    'row_index': 0,
                    'confidence': 0.9,
                  },
                  'intents': [
                    {
                      'kind': 'gain',
                      'direction': 'up',
                      'confidence': 0.8,
                    }
                  ],
                }
              }
            ],
          },
          text: 'I can make that change.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 5),
        mixModel: LocalMixingModel(),
      );

      final audio = await _makeAudioTrack(
          path: '/tmp/test_audio_mix_propose_ask_true.wav', row: 0);
      final result = await pipeline.handleUserText(
        text: 'Can you do that?',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1, 1, 1, 1, 1],
        rowPan: const [0.5, 0.5, 0.5, 0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          5,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1),
            AutomationPoint(x: 1000, volume: 1),
          ],
        ),
        bpmFallback: 120,
      );

      expect(result.message, startsWith('I can make that change.'));
      expect(
        result.message,
        contains('Reply "yes" to apply or "no" to cancel.'),
      );
    });

    test('runtime snapshots include master automation targets for AI planning',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'informational_response',
          {'message': 'Captured.'},
          text: 'Captured.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(
          rows: 2,
          masterEffects: const <EffectState>[
            EffectState(
              effectIndex: 0,
              name: 'Master Comp',
              isBypassed: false,
              parameters: <EffectParameterState>[
                EffectParameterState(
                  id: 'threshold',
                  name: 'Threshold',
                  type: 'float',
                  value: -9.0,
                  min: -60.0,
                  max: 0.0,
                ),
              ],
            ),
          ],
        ),
        mixModel: LocalMixingModel(),
      );

      final audio =
          await _makeAudioTrack(path: '/tmp/test_master_snapshot.wav', row: 0);
      await pipeline.handleUserText(
        text: 'Automate the master compressor threshold.',
        audioTracks: <AudioTrack>[audio],
        rowGain: const [1.0, 1.0],
        rowPan: const [0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          2,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1.0),
            AutomationPoint(x: 1000, volume: 1.0),
          ],
        ),
        bpmFallback: 120.0,
        selectedRowIndex: 0,
      );

      expect(fakeLlm.seenProjectSnapshot, contains('Master: '));
      expect(
        fakeLlm.seenProjectSnapshot,
        contains(
          'automation_targets=[gain | pan | fx0:Master Comp{Threshold}]',
        ),
      );
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains(
          'master_automation_targets=gain | pan | fx0:Master Comp{Threshold}',
        ),
      );
    });

    test('runtime snapshots expose human-readable row identity cues', () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'informational_response',
          {'message': 'Captured.'},
          text: 'Captured.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 4),
        mixModel: LocalMixingModel(),
      );

      final koreanTrack = await _makeAudioTrack(
        path: '/tmp/서울_korean_guide.wav',
        row: 0,
        label: 'Korean Guide',
      );
      final midiTrack = await _makeMidiTrack(
        path: '/tmp/bright_plucks.mid',
        row: 1,
        label: 'Bright Plucks',
      );
      final referenceTrack = await AudioTrack.create(
        file: File('/tmp/reference_mix.wav'),
        originalFile: File('/tmp/reference_mix.wav'),
        audioDuration: const Duration(seconds: 90),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 90),
        offset: 0.0,
        rowIndex: 2,
        rowId: 2,
        label: 'Reference Mix',
        clipKind: ClipKind.audio,
      );

      await pipeline.handleUserText(
        text: 'Match the project closer to the reference.',
        audioTracks: <AudioTrack>[koreanTrack, midiTrack, referenceTrack],
        rowNames: const <String>[
          'Korean Vox',
          'Pluck Bus',
          'Reference',
          '',
        ],
        rowGain: const [1.0, 1.0, 1.0, 1.0],
        rowPan: const [0.5, 0.5, 0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          4,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1.0),
            AutomationPoint(x: 1000, volume: 1.0),
          ],
        ),
        bpmFallback: 120.0,
        selectedRowIndex: 1,
        selectedClipIndices: const <int>[1],
        primarySelectedClipIndex: 1,
      );

      expect(fakeLlm.seenProjectSnapshot, contains('occupied_tracks=1,2,3'));
      expect(fakeLlm.seenProjectSnapshot, contains('bottom_occupied_track=3'));
      expect(fakeLlm.seenProjectSnapshot, contains('row_position=top-most'));
      expect(fakeLlm.seenProjectSnapshot, contains('row_name="Korean Vox"'));
      expect(fakeLlm.seenProjectSnapshot, contains('labels=[Korean Guide]'));
      expect(
        fakeLlm.seenProjectSnapshot,
        contains('files=[서울_korean_guide.wav]'),
      );
      expect(
        fakeLlm.seenProjectSnapshot,
        contains('instruments=[Sub Bass<mixroom.sub_bass>]'),
      );
      expect(
        fakeLlm.seenProjectSnapshot,
        contains(
          'Track 3: row_name="Reference" row_position=middle occupied_row_position=bottom-most-occupied',
        ),
      );
      expect(
        fakeLlm.seenProjectSnapshot,
        contains('reference_hints=[single_long_clip, long_form_audio]'),
      );
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains(
            'selected_row_context{row_index=1,track_number=2,row_name="Pluck Bus",row_position=middle'),
      );
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains('midi_state={none}'),
      );
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains('fx_chain=[none]'),
      );
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains('occupied_row_position=middle-occupied'),
      );
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains('master_context{gain=1.00,pan=0.50,fx_count=0'),
      );
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains('instrument_name=Sub Bass'),
      );
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains('clip_kind=midi'),
      );
    });

    test('runtime snapshots include concise fx chain state for AI planning',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'informational_response',
          {'message': 'Captured.'},
          text: 'Captured.',
        ),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(
          rows: 3,
          rowEffects: {
            1: const <EffectState>[
              EffectState(
                effectIndex: 0,
                name: 'Delay',
                isBypassed: false,
                parameters: <EffectParameterState>[
                  EffectParameterState(
                    id: 'mix',
                    name: 'Mix',
                    type: 'float',
                    value: 0.21,
                  ),
                  EffectParameterState(
                    id: 'feedback',
                    name: 'Feedback',
                    type: 'float',
                    value: 0.37,
                  ),
                ],
              ),
              EffectState(
                effectIndex: 1,
                name: 'Distortion',
                isBypassed: true,
                parameters: <EffectParameterState>[
                  EffectParameterState(
                    id: 'drive',
                    name: 'Drive',
                    type: 'float',
                    value: 0.64,
                  ),
                ],
              ),
            ],
          },
          masterEffects: const <EffectState>[
            EffectState(
              effectIndex: 0,
              name: 'Limiter',
              isBypassed: false,
              parameters: <EffectParameterState>[
                EffectParameterState(
                  id: 'ceiling',
                  name: 'Ceiling',
                  type: 'float',
                  value: -0.3,
                ),
              ],
            ),
          ],
        ),
        mixModel: LocalMixingModel(),
      );

      final track = await _makeAudioTrack(
        path: '/tmp/guitar_loop.wav',
        row: 1,
        label: 'Guitar Loop',
      );

      await pipeline.handleUserText(
        text: 'make the guitar harder',
        audioTracks: <AudioTrack>[track],
        rowGain: const [1.0, 1.0, 1.0],
        rowPan: const [0.5, 0.5, 0.5],
        rowAutomation: const <List<AutomationPoint>>[
          <AutomationPoint>[],
          <AutomationPoint>[],
          <AutomationPoint>[],
        ],
        bpmFallback: 120.0,
        selectedRowIndex: 1,
        selectedClipIndices: const <int>[0],
        primarySelectedClipIndex: 0,
      );

      expect(fakeLlm.seenProjectSnapshot,
          contains('fx_count=2 active_fx_count=1'));
      expect(
        fakeLlm.seenProjectSnapshot,
        contains(
          'fx_chain=[fx0:Delay(on){Mix=0.21, Feedback=0.37} | fx1:Distortion(byp){Drive=0.64}]',
        ),
      );
      expect(
        fakeLlm.seenProjectSnapshot,
        contains(
          'Master: gain=1.00 pan=0.50 fx_count=1 active_fx_count=1 fx_chain=[fx0:Limiter(on){Ceiling=-0.30}]',
        ),
      );
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains(
          'selected_row_context{row_index=1,track_number=2,row_position=middle,occupied_row_position=top-most-occupied,clip_count=1,clip_kinds=[audio:1]',
        ),
      );
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains(
          'fx_count=2,active_fx_count=1,fx_chain=[fx0:Delay(on){Mix=0.21, Feedback=0.37} | fx1:Distortion(byp){Drive=0.64}]',
        ),
      );
      expect(
        fakeLlm.seenProjectSnapshot,
        contains('arrangement={audio_hits=1,bars≈1,onsets=m1:b1.00}'),
      );
    });

    test('passes master automation clip actions through for executor handling',
        () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool(
          'daw_assistant_actions',
          {
            'assistant_message': 'Master automation clip queued.',
            'actions': [
              {
                'type': 'automation_edit',
                'data': {
                  'operation': 'create_clip',
                  'target': {
                    'scope': 'master',
                    'target_id': 'master:gain',
                  },
                  'start_ms': 200,
                  'length_ms': 600,
                },
              },
              {
                'type': 'automation_edit',
                'data': {
                  'operation': 'set_clip_points',
                  'target': {
                    'scope': 'master',
                    'target_id':
                        'masterfxid:${Uri.encodeComponent('Master Comp#0')}:${Uri.encodeComponent('threshold')}',
                  },
                  'clip_index': 0,
                  'points': [
                    {'x_ms': 0, 'value': 0.2},
                    {'x_ms': 600, 'value': 0.9},
                  ],
                },
              },
            ],
          },
          text: 'Master automation clip queued.',
        ),
      );

      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(
          rows: 2,
          masterEffects: const <EffectState>[
            EffectState(
              effectIndex: 0,
              name: 'Master Comp',
              isBypassed: false,
              parameters: <EffectParameterState>[
                EffectParameterState(
                  id: 'threshold',
                  name: 'Threshold',
                  type: 'float',
                  value: 0.4,
                  min: 0.0,
                  max: 1.0,
                ),
              ],
            ),
          ],
        ),
        mixModel: LocalMixingModel(),
      );

      final result = await pipeline.handleUserText(
        text: 'Automate the master compressor threshold.',
        audioTracks: const <AudioTrack>[],
        rowGain: const [1.0, 1.0],
        rowPan: const [0.5, 0.5],
        rowAutomation: List<List<AutomationPoint>>.generate(
          2,
          (_) => <AutomationPoint>[
            AutomationPoint(x: 0, volume: 1.0),
          ],
        ),
        bpmFallback: 120.0,
        selectedRowIndex: 0,
      );

      expect(result.hasAssistantActions, isTrue);
      expect(result.assistantActions, hasLength(2));
      expect(
        result.assistantActions.first.data['target']['scope'],
        equals('master'),
      );
      expect(
        result.assistantActions.first.data['target']['target_id'],
        equals('master:gain'),
      );
      expect(
        result.assistantActions.last.data['target']['target_id'],
        startsWith('masterfxid:'),
      );
    });
  });
}
