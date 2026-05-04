import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mixroom/ai/chat_pipeline.dart';
import 'package:mixroom/ai/cloud_llm_service.dart';
import 'package:mixroom/ai/instrument_classifier.dart';
import 'package:mixroom/ai/local_mixing_model.dart';
import 'package:mixroom/ai/project_state_builder.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/models/mixing_result.dart';
import 'package:mixroom/models/project_state.dart';

class _FakeProjectStateBuilder extends ProjectStateBuilder {
  _FakeProjectStateBuilder({this.rows = 4})
      : super(classifier: InstrumentClassifier(), maxRows: rows);

  final int rows;

  @override
  Future<ProjectState> build({
    required List<AudioTrack> audioTracks,
    required double bpmFallback,
    required List<double> rowGain,
    required List<double> rowPan,
    required List<List<AutomationPoint>> rowAutomation,
    String projectKey = '',
    double masterGain0to3 = 1.0,
    double masterPan0to1 = 0.5,
    Map<int, String> roleOverrides = const {},
  }) async {
    final rowStates = List<RowState>.generate(rows, (row) {
      final rowTracks = audioTracks.where((t) => t.rowIndex == row).toList();
      return RowState(
        rowIndex: row,
        clips: const <ClipState>[],
        approxRms: rowTracks.isEmpty ? 0.0 : 0.2,
        approxCrest: rowTracks.isEmpty ? 0.0 : 1.4,
        roleProbs: const {
          'vocals': 0.2,
          'drums': 0.2,
          'bass': 0.2,
          'guitar': 0.2,
          'synth': 0.1,
          'other': 0.1,
        },
        roleConsistency: 1.0,
        clipTopRoles: const ['other'],
        audioStats: const {
          'centroid_hz': 1000.0,
          'zcr': 0.1,
          'hf_rms': 0.1,
          'sibilance': 0.1,
          'bassiness': 0.1,
        },
        interpretation: RowInterpretationState.empty,
        gain0to3: row < rowGain.length ? rowGain[row] : 1.0,
        pan0To1: row < rowPan.length ? rowPan[row] : 0.5,
        effects: const [],
        volumeAutomation: row < rowAutomation.length
            ? rowAutomation[row]
            : const <AutomationPoint>[],
        hasAudio: rowTracks.isNotEmpty,
      );
    });

    return ProjectState(
      bpm: bpmFallback,
      masterGain0to3: masterGain0to3,
      masterPan0to1: masterPan0to1,
      maxRows: rows,
      rows: rowStates,
      masterEffects: const <EffectState>[],
      overlapMatrix:
          List<List<int>>.generate(rows, (_) => List<int>.filled(rows, 0)),
      overlapRatioMatrix: List<List<double>>.generate(
          rows, (_) => List<double>.filled(rows, 0)),
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

CloudLlmService _mockCloudLlmService({
  required List<Map<String, dynamic>> output,
}) {
  final client = MockClient((_) async {
    return http.Response(jsonEncode({'output': output}), 200);
  });
  return CloudLlmService(
    apiKey: 'sk-test',
    model: 'gpt-4.1-mini',
    httpClient: client,
  );
}

Future<ChatPipelineResult> _runPrompt({
  required String prompt,
  required List<Map<String, dynamic>> output,
}) async {
  final pipeline = ChatPipeline(
    llm: _mockCloudLlmService(output: output),
    projectBuilder: _FakeProjectStateBuilder(rows: 4),
    mixModel: LocalMixingModel(),
  );
  final tracks = <AudioTrack>[
    await _makeAudioTrack(
      path: '/tmp/chat_prompt_e2e_vocal.wav',
      row: 0,
      label: 'Lead Vocal',
    ),
  ];
  return pipeline.handleUserText(
    text: prompt,
    audioTracks: tracks,
    rowGain: const [1.0, 1.0, 1.0, 1.0],
    rowPan: const [0.5, 0.5, 0.5, 0.5],
    rowAutomation: List<List<AutomationPoint>>.generate(
      4,
      (_) => <AutomationPoint>[
        AutomationPoint(x: 0, volume: 1.0),
      ],
    ),
    bpmFallback: 120.0,
    selectedRowIndex: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Prompt E2E (Mocked Project + Mocked LLM HTTP)', () {
    test(
        'add reverb on track 1 maps to executable effect_edit (no parser no-op)',
        () async {
      final result = await _runPrompt(
        prompt: 'add reverb on track 1',
        output: [
          {
            'type': 'function_call',
            'name': 'daw_assistant_actions',
            'arguments': {
              'actions': [
                {
                  'type': 'effect_edit',
                  'data': {
                    'operation': 'add',
                    'target': {'track': 1, 'plugin': 'reverb'},
                  },
                },
              ],
            },
          },
        ],
      );

      expect(result.hasAssistantActions, isTrue);
      expect(result.assistantActions, hasLength(1));
      final action = result.assistantActions.single;
      expect(action.type, 'effect_edit');
      final data = Map<String, dynamic>.from(action.data);
      final target = Map<String, dynamic>.from(data['target'] as Map);
      expect(data['row_index'], 0);
      expect(target['row_index'], 0);
      expect(target['effect_name'], 'reverb');
      expect(target['plugin_name'], 'reverb');
    });

    test('plugin remove call remains executable with missing assistant_message',
        () async {
      final result = await _runPrompt(
        prompt: 'remove gain from track 1',
        output: [
          {
            'type': 'function_call',
            'name': 'daw_assistant_actions',
            'arguments': {
              'actions': [
                {
                  'type': 'effect_edit',
                  'data': {
                    'operation': 'remove',
                    'target': {'track_number': 1, 'effect_name': 'Gain'},
                  },
                },
              ],
            },
          },
        ],
      );

      expect(result.hasAssistantActions, isTrue);
      final action = result.assistantActions.single;
      final data = Map<String, dynamic>.from(action.data);
      final target = Map<String, dynamic>.from(data['target'] as Map);
      expect(data['row_index'], 0);
      expect(target['row_index'], 0);
      expect(target['effect_name'], 'Gain');
    });

    test('multi-call DAW tool output keeps all actions instead of falling back',
        () async {
      final result = await _runPrompt(
        prompt: 'on track 1 add reverb then bypass it',
        output: [
          {
            'type': 'function_call',
            'name': 'daw_assistant_actions',
            'arguments': {
              'actions': [
                {
                  'type': 'effect_edit',
                  'data': {
                    'operation': 'add',
                    'target': {'row': 1, 'plugin_name': 'reverb'},
                  },
                },
              ],
            },
          },
          {
            'type': 'function_call',
            'name': 'daw_assistant_actions',
            'arguments': {
              'actions': [
                {
                  'type': 'effect_edit',
                  'data': {
                    'operation': 'bypass',
                    'target': {'row': 1, 'effect_name': 'reverb'},
                  },
                },
              ],
            },
          },
        ],
      );

      expect(result.hasAssistantActions, isTrue);
      expect(result.assistantActions, hasLength(2));
      expect(
        result.assistantActions.map((a) => a.type).toList(growable: false),
        equals(const ['effect_edit', 'effect_edit']),
      );
    });

    test('mix execute action still applies when assistant_message is omitted',
        () async {
      final result = await _runPrompt(
        prompt: 'turn up track 1',
        output: [
          {
            'type': 'function_call',
            'name': 'mix_model_request',
            'arguments': {
              'mode': 'execute',
              'actions': [
                {
                  'goal': {
                    'type': 'mix_request',
                    'intents': [
                      {
                        'kind': 'gain',
                        'direction': 'up',
                        'confidence': 0.9,
                      }
                    ],
                    'target': {
                      'scope': 'row',
                      'row_index': 0,
                      'confidence': 0.9,
                    },
                    'intensity': 0.25,
                  },
                },
              ],
            },
          },
        ],
      );

      expect(result.meta?['tool'], 'mix_model_request');
      final llmActions = result.meta?['llm_actions'] as List?;
      expect(llmActions, isNotNull);
      expect(llmActions, hasLength(1));
      expect(result.message, isNotEmpty);
    });
  });
}
