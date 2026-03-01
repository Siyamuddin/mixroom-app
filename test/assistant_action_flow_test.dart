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
    MixingResult? pendingMix,
  }) async {
    seenUserText = userText;
    seenProjectSnapshot = projectSnapshot;
    seenSelectionSnapshot = selectionSnapshot;
    return _next;
  }
}

class _FakeProjectStateBuilder extends ProjectStateBuilder {
  _FakeProjectStateBuilder({this.rows = 5})
      : super(classifier: InstrumentClassifier(), maxRows: rows);

  final int rows;

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
        approxRms: rowTracks.isEmpty ? 0.0 : 0.2,
        approxCrest: rowTracks.isEmpty ? 0.0 : 1.5,
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
        audioStats: const {
          'centroid_hz': 1200.0,
          'zcr': 0.1,
          'hf_rms': 0.1,
          'sibilance': 0.1,
          'bassiness': 0.1,
        },
        gain0to3: row < rowGain.length ? rowGain[row] : 1.0,
        pan0To1: row < rowPan.length ? rowPan[row] : 0.5,
        effects: const [],
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
      expect(result.assistantActions.length, 7);
      expect(
        result.assistantActions.map((a) => a.type).toSet(),
        equals(const {
          'tutorial',
          'clarify',
          'clip_edit',
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
      expect(result.message, contains('Apply these changes? (yes / no)'));
      expect(result.meta?['tool'], 'mix_model_request');
      expect(result.meta?['mode'], 'propose');
    });
  });

  group('Assistant Action Executor Coverage', () {
    test(
        'chat pipeline uses structured role override APIs (no local text regex)',
        () async {
      final pipelineSource =
          File('lib/ai/chat_pipeline.dart').readAsStringSync();
      expect(pipelineSource.contains('setRoleOverride('), isTrue);
      expect(pipelineSource.contains('clearRoleOverride('), isTrue);
      expect(pipelineSource.contains('_parseRoleOverride('), isFalse);
      expect(pipelineSource.contains('automation_targets='), isTrue);
      expect(
        pipelineSource.contains('selected_row_automation_targets='),
        isTrue,
      );
    });

    test('audio_editor has executor branches for all added assistant actions',
        () async {
      final source = File('lib/screens/audio_editor.dart').readAsStringSync();

      for (final actionType in const [
        "case 'tutorial':",
        "case 'clarify':",
        "case 'clip_edit':",
        "case 'automation_edit':",
        "case 'midi_compose':",
        "case 'stem_separate':",
        "case 'role_override':",
      ]) {
        expect(source.contains(actionType), isTrue, reason: actionType);
      }

      expect(source.contains("if (operation == 'trim')"), isTrue);
      expect(source.contains("operation == 'dialog_cleanup'"), isTrue);
      expect(source.contains("operation == 'dialog_remove_range'"), isTrue);
      expect(source.contains("operation == 'dialog_tighten_pauses'"), isTrue);
      expect(source.contains("operation == 'dialog_lift_quiet'"), isTrue);
      expect(source.contains('_applyDialogClipEditOperation('), isTrue);

      for (final op in const [
        "case 'cut':",
        "case 'move':",
        "case 'stretch':",
        "case 'tempo_follow':",
        "case 'tempo_detect_set_project':",
        "case 'delete':",
        "case 'duplicate':",
      ]) {
        expect(source.contains(op), isTrue, reason: op);
      }

      expect(source.contains("_normalizeClipEditOperation("), isTrue);
      expect(
        source.contains('AssistantActionUtils.normalizeClipEditOperation('),
        isTrue,
      );
      expect(source.contains("_applyAutoBpmAlignAction("), isTrue);
      expect(source.contains("_estimateAutoTrimBoundsMs("), isTrue);
      expect(
        source.contains('AssistantActionUtils.estimateAutoTrimBoundsMs('),
        isTrue,
      );
      expect(source.contains("'tutorial:mute'"), isTrue);
      expect(source.contains("'row:\$row:effects_tab'"), isTrue);
      expect(source.contains("'row:\$row:fx_list'"), isTrue);
      expect(source.contains('tutorialTargetSequenceForStep'), isTrue);
      expect(source.contains("normalized.startsWith('row:')"), isTrue);

      expect(source.contains('rawOperation'), isTrue);
      expect(source.contains("'set' || 'replace' => 'set_points'"), isTrue);
      expect(source.contains("operation == 'add_ramp'"), isTrue);
      expect(source.contains("operation == 'clear'"), isTrue);
      expect(
        source.contains(
            "operation == 'create_clip' || operation == 'apply_template'"),
        isTrue,
      );
      expect(source.contains("operation == 'duplicate_clip'"), isTrue);
      expect(source.contains("operation == 'move_clip'"), isTrue);
      expect(source.contains("operation == 'delete_clip'"), isTrue);
      expect(source.contains("operation == 'clear_clips'"), isTrue);
      expect(source.contains("operation == 'toggle_clip_mute'"), isTrue);
      expect(source.contains("operation == 'set_clip_points'"), isTrue);
      expect(source.contains("final rawPoints = (data['points'] as List?)"),
          isTrue);
      expect(source.contains('_isPluginAutomationIntent('), isTrue);
      expect(source.contains('allowVolumeFallback'), isTrue);
      expect(source.contains("'effect_name'"), isTrue);
      expect(source.contains("'plugin_name'"), isTrue);
      expect(source.contains('_resolveKickSourceClipIndexFromAction('), isTrue);
      expect(source.contains('_detectKickTimelineOnsetsMsForClip('), isTrue);
      expect(source.contains("normalizedTemplate == 'sidechain_from_kick'"),
          isTrue);

      expect(source.contains('_fallbackMidiNotesFromProgression('), isTrue);
      expect(source.contains('_midiPitchFromRaw('), isTrue);
      expect(source.contains("_normalizeMidiComposeOperation("), isTrue);
      expect(source.contains("operation == 'chop_notes'"), isTrue);
      expect(source.contains('_chopMidiNotesFromActionData('), isTrue);
      expect(source.contains('AssistantActionUtils.chopMidiNotes('), isTrue);
      expect(source.contains("'velocity_decay_per_slice'"), isTrue);
      expect(source.contains("'velocity_jitter'"), isTrue);
      expect(source.contains('_handleStemSeparationForClip('), isTrue);
      expect(source.contains('_applyRoleOverrideAction('), isTrue);
      expect(
        source.contains('Created vocal/instrumental stems with Spleeter.'),
        isTrue,
      );

      final llmPromptSource =
          File('lib/ai/cloud_llm_service.dart').readAsStringSync();
      expect(llmPromptSource.contains('target.effect_index + target.param_id'),
          isTrue);
      expect(llmPromptSource.contains('target.effect_name + target.param_name'),
          isTrue);
      expect(llmPromptSource.contains('value_mode: "real"'), isTrue);
      expect(llmPromptSource.contains('velocity_decay_per_slice'), isTrue);
      expect(llmPromptSource.contains('sidechain_from_kick'), isTrue);
      expect(llmPromptSource.contains('dialog_cleanup'), isTrue);
      expect(llmPromptSource.contains('dialog_remove_range'), isTrue);
      expect(llmPromptSource.contains('dialog_tighten_pauses'), isTrue);
      expect(llmPromptSource.contains('dialog_lift_quiet'), isTrue);
    });

    test('timeline/editor wiring contains stem button + selection callback',
        () async {
      final timeline =
          File('lib/screens/audio_timeline_pro.dart').readAsStringSync();
      expect(timeline.contains('onStemSeparation'), isTrue);
      expect(timeline.contains('onSelectionChanged'), isTrue);
      expect(timeline.contains('Separate Vocals / Instrumental'), isTrue);
      expect(timeline.contains('_emitSelectionChanged()'), isTrue);
      expect(timeline.contains("HaloKey('row:\$row:effects_tab')"), isTrue);
      expect(timeline.contains("HaloKey('row:\$row:fx_list')"), isTrue);
      expect(timeline.contains("HaloKey('row:\$row:mute')"), isTrue);
      expect(timeline.contains("HaloKey('row:\$row:solo')"), isTrue);

      final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
      expect(editor.contains('onStemSeparation:'), isTrue);
      expect(editor.contains('_handleStemSeparationForClip'), isTrue);
      expect(editor.contains('onSelectionChanged:'), isTrue);
      expect(editor.contains("HaloKey('tutorial:toolbar')"), isTrue);
      expect(editor.contains("HaloKey('tutorial:timeline')"), isTrue);
      expect(editor.contains("HaloKey('tutorial:piano_roll')"), isTrue);
      expect(
          editor.contains('selectedClipIndices: _timelineSelectedClipIndices'),
          isTrue);
      expect(
          editor.contains(
              'primarySelectedClipIndex: _timelinePrimarySelectedClipIndex'),
          isTrue);

      final effectsPanel =
          File('lib/widgets/effects_panel.dart').readAsStringSync();
      expect(effectsPanel.contains("row:\$row:fx_index:\$effectIndex"), isTrue);
      expect(effectsPanel.contains("row:\$row:param:"), isTrue);
      expect(
          effectsPanel.contains("row:\${widget.rowIndex}:add_effect"), isTrue);
    });
  });
}
