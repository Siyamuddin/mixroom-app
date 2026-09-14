import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/chat_pipeline.dart';
import 'package:mixroom/ai/cloud_llm_service.dart';
import 'package:mixroom/ai/instrument_classifier.dart';
import 'package:mixroom/ai/local_mixing_model.dart';
import 'package:mixroom/ai/magnitude_predictor.dart';
import 'package:mixroom/ai/project_state_builder.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_mix_materializer.dart';
import 'package:mixroom/ai/v3/ai_v3_planner_service.dart';
import 'package:mixroom/ai/v3/ai_v3_preparer.dart';
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
    String? conversationSessionId,
    MixingResult? pendingMix,
    Map<String, dynamic> clientContext = const <String, dynamic>{},
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
    String? conversationSessionId,
    MixingResult? pendingMix,
    Map<String, dynamic> clientContext = const <String, dynamic>{},
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

class _FakeAiV3Planner implements AiV3Planner {
  int callCount = 0;
  String? seenRequest;

  @override
  Future<AiV3PlannerResult> plan({
    required AiV3CoreContext context,
    required String originalRequest,
    String? promptTraceId,
  }) async {
    callCount += 1;
    seenRequest = originalRequest;
    return const AiV3PlannerResult(
      plan: AiV3Plan(
        outcome: 'respond',
        userMessage: 'V3 handled the request.',
        commands: <AiV3Command>[],
      ),
      meta: <String, dynamic>{'architecture': 'test_v3'},
    );
  }
}

class _StaticAiV3Planner implements AiV3Planner {
  _StaticAiV3Planner(this.nextPlan);

  final AiV3Plan nextPlan;
  int callCount = 0;
  final List<AiV3CoreContext> seenContexts = <AiV3CoreContext>[];

  @override
  Future<AiV3PlannerResult> plan({
    required AiV3CoreContext context,
    required String originalRequest,
    String? promptTraceId,
  }) async {
    callCount += 1;
    seenContexts.add(context);
    return AiV3PlannerResult(
      plan: nextPlan,
      meta: const <String, dynamic>{'architecture': 'test_v3'},
    );
  }
}

class _FailingAiV3Planner implements AiV3Planner {
  const _FailingAiV3Planner(this.code);

  final String code;

  @override
  Future<AiV3PlannerResult> plan({
    required AiV3CoreContext context,
    required String originalRequest,
    String? promptTraceId,
  }) {
    throw AiV3PlannerException(code);
  }
}

class _ConfirmingAiV3Preparer extends AiV3CommandPreparer {
  const _ConfirmingAiV3Preparer();

  @override
  AiV3PreparedBundle prepare({
    required AiV3Plan plan,
    required AiV3CoreContext context,
    Map<String, double> detectedTempoByClipId = const <String, double>{},
    Map<String, AiV3ClipBoundaryAnalysis> boundaryAnalysisByClipId =
        const <String, AiV3ClipBoundaryAnalysis>{},
  }) {
    final prepared = super.prepare(
      plan: plan,
      context: context,
      detectedTempoByClipId: detectedTempoByClipId,
      boundaryAnalysisByClipId: boundaryAnalysisByClipId,
    );
    return AiV3PreparedBundle(
      plan: prepared.plan,
      stateDigest: prepared.stateDigest,
      actions: prepared.actions,
      receipts: prepared.receipts,
      preview: prepared.preview,
      executionPolicy: AiV3ExecutionPolicy.confirm,
    );
  }
}

class _FailingAiV3Preparer extends AiV3CommandPreparer {
  const _FailingAiV3Preparer(
    this.code, {
    this.commandType,
    this.commandIndex,
    this.effectId,
    this.parameterId,
    this.reason,
  });

  final String code;
  final String? commandType;
  final int? commandIndex;
  final String? effectId;
  final String? parameterId;
  final String? reason;

  @override
  AiV3PreparedBundle prepare({
    required AiV3Plan plan,
    required AiV3CoreContext context,
    Map<String, double> detectedTempoByClipId = const <String, double>{},
    Map<String, AiV3ClipBoundaryAnalysis> boundaryAnalysisByClipId =
        const <String, AiV3ClipBoundaryAnalysis>{},
  }) {
    throw AiV3PreparationException(
      code,
      commandType: commandType,
      commandIndex: commandIndex,
      effectId: effectId,
      parameterId: parameterId,
      reason: reason,
    );
  }
}

class _FailingAiV3MixGoalMaterializer extends AiV3MixGoalMaterializer {
  _FailingAiV3MixGoalMaterializer(this.code, {this.effectId, this.reason})
    : super(
        mixModel: LocalMixingModel(),
        magnitudePredictor: const NoopMixingMagnitudePredictor(),
      );

  final String code;
  final String? effectId;
  final String? reason;

  @override
  Future<AiV3MixMaterializationResult> materialize({
    required AiV3PreparedBundle bundle,
    required ProjectState project,
    required Map<int, String> roleOverrides,
    required bool bypassLearnedMagnitudes,
    required Set<String> allowedEffectIds,
    String? projectId,
  }) async {
    throw AiV3PreparationException(
      code,
      commandType: 'mix.apply_goal',
      effectId: effectId,
      reason: reason,
    );
  }
}

Map<String, dynamic> _v3ClientContext() => <String, dynamic>{
  'ai_v3_row_state': <Map<String, dynamic>>[
    <String, dynamic>{'row_id': 101, 'muted': false, 'soloed': false},
  ],
  'ai_v3_clip_timeline_lengths_ms': <String, double>{},
  'ai_v3_playhead_ms': 0,
  'ai_v3_transport': <String, dynamic>{
    'playing': false,
    'recording': false,
    'metronome_enabled': false,
    'loop_enabled': false,
    'loop_start_ms': 0,
    'loop_end_ms': 0,
  },
  'current_rows': 1,
  'max_rows': 32,
};

class _FakeProjectStateBuilder extends ProjectStateBuilder {
  _FakeProjectStateBuilder({
    this.rows = 5,
    this.masterEffects = const <EffectState>[],
    this.rowEffects = const <int, List<EffectState>>{},
    this.rowAudioStats = const <int, Map<String, double>>{},
    // Kept available for focused fixtures even when the broad smoke suite
    // uses the default empty interpretation map.
    // ignore: unused_element_parameter
    this.rowInterpretations = const <int, RowInterpretationState>{},
    this.rowApproxRms = const <int, double>{},
    // ignore: unused_element_parameter
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
    String projectKey = '',
    double masterGain0to3 = 1.0,
    double masterPan0to1 = 0.5,
    Map<int, String> roleOverrides = const {},
    List<TimelineRow> timelineRows = const <TimelineRow>[],
    List<TrackGroup> trackGroups = const <TrackGroup>[],
  }) async {
    final rowStates = List<RowState>.generate(rows, (row) {
      final rowTracks = audioTracks.where((t) => t.rowIndex == row).toList();
      final clips = rowTracks
          .map(
            (t) => ClipState(
              startMs: t.offset * 1000.0,
              endMs:
                  t.offset * 1000.0 +
                  (t.trimEnd - t.trimStart).inMilliseconds.toDouble(),
              fileName: t.file.path.split('/').last,
              gain0to3: t.gain,
              pitchSemitones: t.pitchSemitones,
            ),
          )
          .toList();

      return RowState(
        rowIndex: row,
        rowId: row < timelineRows.length ? timelineRows[row].rowId : row,
        rowName: row < timelineRows.length ? timelineRows[row].name : '',
        laneKind: row < timelineRows.length
            ? timelineRows[row].kind.wireName
            : 'audio',
        instrumentId: row < timelineRows.length
            ? timelineRows[row].instrumentId
            : '',
        instrumentName: row < timelineRows.length
            ? timelineRows[row].instrumentName
            : '',
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
        audioStats:
            rowAudioStats[row] ??
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

    final overlapMatrix = List<List<int>>.generate(
      rows,
      (_) => List<int>.filled(rows, 0),
    );
    final overlapRatioMatrix = List<List<double>>.generate(
      rows,
      (_) => List<double>.filled(rows, 0),
    );

    return ProjectState(
      bpm: bpmFallback,
      masterGain0to3: masterGain0to3,
      masterPan0to1: masterPan0to1,
      maxRows: rows,
      rows: rowStates,
      trackGroups: trackGroups,
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
    test('V3-disabled project chat keeps the existing V1 route', () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool('informational_response', const <String, dynamic>{
          'message': 'V1 handled the request.',
        }, text: 'V1 handled the request.'),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 1),
        mixModel: LocalMixingModel(),
      );

      final result = await pipeline.handleUserText(
        text: 'Tell me about this project.',
        audioTracks: const <AudioTrack>[],
        rowGain: const <double>[1.0],
        rowPan: const <double>[0.5],
        rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
        bpmFallback: 120,
        clientContext: const <String, dynamic>{},
      );

      expect(fakeLlm.seenUserText, 'Tell me about this project.');
      expect(result.hasAiV3Handoff, isFalse);
      expect(result.message, 'V1 handled the request.');
    });

    test('V3-enabled project chat uses V3 and does not call V1', () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool('informational_response', const <String, dynamic>{
          'message': 'Unexpected V1 result.',
        }, text: 'Unexpected V1 result.'),
      );
      final fakeV3 = _FakeAiV3Planner();
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 1),
        mixModel: LocalMixingModel(),
        aiV3Planner: fakeV3,
      );

      final result = await pipeline.handleUserText(
        text: 'Tell me about this project.',
        audioTracks: const <AudioTrack>[],
        rowGain: const <double>[1.0],
        rowPan: const <double>[0.5],
        rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
        bpmFallback: 120,
        timelineRows: <TimelineRow>[
          TimelineRow(rowId: 101, name: 'Audio 1', iconId: 0),
        ],
        clientContext: _v3ClientContext(),
      );

      expect(fakeLlm.seenUserText, isNull);
      expect(fakeV3.callCount, 1, reason: result.toString());
      expect(fakeV3.seenRequest, 'Tell me about this project.');
      expect(result.hasAiV3Handoff, isTrue);
      expect(result.aiV3Handoff?['decision'], 'respond');
      expect(result.message, 'V3 handled the request.');
    });

    test('V3 plan diagnostics expose structure without command payloads', () {
      const privateClipId = 'private-clip-id-that-must-not-be-logged';
      const privateEffectValue = 'private-effect-value';
      const privateStyle = 'private-style-description';
      final summary = aiV3PlanDiagnosticSummary(
        const AiV3Plan(
          outcome: 'plan',
          userMessage: 'private planner message',
          commands: <AiV3Command>[
            AiV3Command(
              commandId: 'midi',
              type: 'midi.replace_notes',
              arguments: <String, dynamic>{
                'clip_id': privateClipId,
                'notes': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'pitch': 64,
                    'start_beat': 0,
                    'length_beats': 1,
                    'velocity': 100,
                  },
                ],
              },
            ),
            AiV3Command(
              commandId: 'effect',
              type: 'effect.ensure_configured',
              arguments: <String, dynamic>{
                'row_id': 101,
                'parameters': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'parameter_id': 'drive',
                    'value': privateEffectValue,
                  },
                ],
              },
            ),
            AiV3Command(
              commandId: 'mix',
              type: 'mix.apply_goal',
              arguments: <String, dynamic>{
                'target': <String, dynamic>{'scope': 'row', 'row_id': 101},
                'style_tags': <String>[privateStyle],
              },
            ),
          ],
        ),
      );

      expect(summary['command_count'], 3);
      expect(summary['command_type_counts'], <String, int>{
        'effect.ensure_configured': 1,
        'midi.replace_notes': 1,
        'mix.apply_goal': 1,
      });
      expect(summary, isNot(contains('row_ids')));
      expect(summary['target_scopes'], <String>['row']);
      expect(summary['has_midi_commands'], isTrue);
      expect(summary['has_direct_effect_commands'], isTrue);
      expect(summary['has_mix_goal'], isTrue);
      final encoded = summary.toString();
      expect(encoded, isNot(contains(privateClipId)));
      expect(encoded, isNot(contains(privateEffectValue)));
      expect(encoded, isNot(contains(privateStyle)));
      expect(encoded, isNot(contains('private planner message')));
      expect(encoded, isNot(contains('pitch')));
      expect(encoded, isNot(contains('velocity')));
    });

    test(
      'invalid V3 planner output returns an actionable safe result',
      () async {
        final pipeline = ChatPipeline(
          llm: _FakeCloudLlmService(
            LlmResult.text('Unexpected V1 result.', null),
          ),
          projectBuilder: _FakeProjectStateBuilder(rows: 1),
          mixModel: LocalMixingModel(),
          aiV3Planner: const _FailingAiV3Planner('v3_planner_contract_invalid'),
        );

        final result = await pipeline.handleUserText(
          text: 'Replace this instrument and add more musical parts.',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: <TimelineRow>[
            TimelineRow(rowId: 101, name: 'Epic Melody', iconId: 1),
          ],
          clientContext: _v3ClientContext(),
        );

        expect(result.hasAiV3Handoff, isTrue);
        expect(result.aiV3Handoff?['decision'], 'blocked');
        expect(
          result.aiV3Handoff?['error_code'],
          'v3_planner_contract_invalid',
        );
        expect(
          result.message,
          'That request did not finish correctly. Nothing was changed. '
          'Please try again.',
        );
        expect(result.message, isNot(contains('AI request failed')));
        expect(pipeline.hasActiveAiV3PendingPlan(), isFalse);
      },
    );

    test('V3 input capacity failure explains the safe rejection', () async {
      final pipeline = ChatPipeline(
        llm: _FakeCloudLlmService(
          LlmResult.text('Unexpected V1 result.', null),
        ),
        projectBuilder: _FakeProjectStateBuilder(rows: 1),
        mixModel: LocalMixingModel(),
        aiV3Planner: const _FailingAiV3Planner('v3_context_request_limit'),
      );
      final result = await pipeline.handleUserText(
        text: 'Rebalance.',
        audioTracks: const <AudioTrack>[],
        rowGain: const [1.0],
        rowPan: const [0.5],
        rowAutomation: const <List<AutomationPoint>>[[]],
        bpmFallback: 120,
        timelineRows: [TimelineRow(rowId: 101, name: 'Guitar', iconId: 1)],
        clientContext: _v3ClientContext(),
      );
      expect(result.aiV3Handoff?['decision'], 'blocked');
      expect(result.message, contains('exceeds the AI context capacity'));
      expect(result.message, contains('Nothing was changed'));
      expect(pipeline.hasActiveAiV3PendingPlan(), isFalse);
    });

    test('V3 timeout response is accurate for short requests', () async {
      final pipeline = ChatPipeline(
        llm: _FakeCloudLlmService(
          LlmResult.text('Unexpected V1 result.', null),
        ),
        projectBuilder: _FakeProjectStateBuilder(rows: 1),
        mixModel: LocalMixingModel(),
        aiV3Planner: const _FailingAiV3Planner('v3_planner_timeout'),
      );

      final result = await pipeline.handleUserText(
        text: 'Make the guitar richer.',
        audioTracks: const <AudioTrack>[],
        rowGain: const <double>[1.0],
        rowPan: const <double>[0.5],
        rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
        bpmFallback: 120,
        timelineRows: <TimelineRow>[
          TimelineRow(rowId: 101, name: 'Guitar', iconId: 1),
        ],
        clientContext: _v3ClientContext(),
      );

      expect(result.hasAiV3Handoff, isTrue);
      expect(result.aiV3Handoff?['decision'], 'blocked');
      expect(result.aiV3Handoff?['error_code'], 'v3_planner_timeout');
      expect(
        result.message,
        'The AI service did not finish this request in time. '
        'Nothing was changed. Try again.',
      );
      expect(result.message, isNot(contains('large request')));
      expect(pipeline.hasActiveAiV3PendingPlan(), isFalse);
    });

    test(
      'clear mutating V3 request executes immediately without a pending plan',
      () async {
        final fakeLlm = _FakeCloudLlmService(
          LlmResult.text('Unexpected V1 result.', null),
        );
        final planner = _StaticAiV3Planner(
          const AiV3Plan(
            outcome: 'plan',
            userMessage: 'Lowering Audio 1 by 2 dB.',
            commands: <AiV3Command>[
              AiV3Command(
                commandId: 'gain',
                type: 'row.adjust_gain_db',
                arguments: <String, dynamic>{'row_id': 101, 'delta_db': -2},
              ),
            ],
          ),
        );
        final pipeline = ChatPipeline(
          llm: fakeLlm,
          projectBuilder: _FakeProjectStateBuilder(rows: 1),
          mixModel: LocalMixingModel(),
          aiV3Planner: planner,
        );

        final result = await pipeline.handleUserText(
          text: 'Lower Audio 1 by 2 dB.',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: <TimelineRow>[
            TimelineRow(rowId: 101, name: 'Audio 1', iconId: 0),
          ],
          clientContext: _v3ClientContext(),
        );

        expect(result.aiV3Handoff?['decision'], 'execute_now');
        expect(result.aiV3Handoff?['execution_policy'], 'auto_apply');
        expect(
          (result.aiV3Handoff?['prepared_bundle'] as Map)['execution_policy'],
          'auto_apply',
        );
        expect(pipeline.hasActiveAiV3PendingPlan(), isFalse);
        expect(result.message, isEmpty);
        expect(fakeLlm.seenUserText, isNull);

        final bundle = Map<String, dynamic>.from(
          result.aiV3Handoff?['prepared_bundle'] as Map,
        );
        final completionMessage = aiV3VerifiedConversationMessage(bundle);
        pipeline.recordAiV3Execution(
          handoff: result.aiV3Handoff!,
          result: const <String, dynamic>{'status': 'succeeded'},
          conversationMessage: completionMessage,
        );
        await pipeline.handleUserText(
          text: 'What did you change?',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: <TimelineRow>[
            TimelineRow(rowId: 101, name: 'Audio 1', iconId: 0),
          ],
          clientContext: _v3ClientContext(),
        );
        final secondConversation =
            planner.seenContexts.last.data['conversation'] as List;
        expect(
          secondConversation.whereType<Map>().any(
            (entry) =>
                entry['role'] == 'assistant' &&
                entry['content'] == completionMessage,
          ),
          isTrue,
        );
      },
    );

    test(
      'already-satisfied plan returns an honest no-change response',
      () async {
        final planner = _StaticAiV3Planner(
          const AiV3Plan(
            outcome: 'plan',
            userMessage: 'I will keep Audio 1 unmuted.',
            commands: <AiV3Command>[
              AiV3Command(
                commandId: 'mute',
                type: 'row.set_muted',
                arguments: <String, dynamic>{'row_id': 101, 'muted': false},
              ),
            ],
          ),
        );
        final pipeline = ChatPipeline(
          llm: _FakeCloudLlmService(
            LlmResult.text('Unexpected V1 result.', null),
          ),
          projectBuilder: _FakeProjectStateBuilder(rows: 1),
          mixModel: LocalMixingModel(),
          aiV3Planner: planner,
        );

        final result = await pipeline.handleUserText(
          text: 'Keep Audio 1 unmuted.',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: <TimelineRow>[
            TimelineRow(rowId: 101, name: 'Audio 1', iconId: 0),
          ],
          clientStateDigest: 'no-op-state',
          clientContext: _v3ClientContext(),
        );

        expect(result.aiV3Handoff?['decision'], 'respond');
        expect(result.aiV3Handoff?['reason'], 'already_satisfied');
        expect(
          result.message,
          'No changes were needed:\n- Unmuted Audio 1 (already set)',
        );
        expect(result.message, isNot(contains('I will')));
        expect(pipeline.hasActiveAiV3PendingPlan(), isFalse);
      },
    );

    test('clarification options survive the V3 handoff exactly', () async {
      final planner = _StaticAiV3Planner(
        const AiV3Plan(
          outcome: 'clarify',
          userMessage: 'Which vocal row should I change?',
          commands: <AiV3Command>[],
          questionOptions: <String>['Lead Vocal', 'Backing Vocal'],
        ),
      );
      final pipeline = ChatPipeline(
        llm: _FakeCloudLlmService(
          LlmResult.text('Unexpected V1 result.', null),
        ),
        projectBuilder: _FakeProjectStateBuilder(rows: 1),
        mixModel: LocalMixingModel(),
        aiV3Planner: planner,
      );

      final result = await pipeline.handleUserText(
        text: 'Make the vocal louder.',
        audioTracks: const <AudioTrack>[],
        rowGain: const <double>[1.0],
        rowPan: const <double>[0.5],
        rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
        bpmFallback: 120,
        timelineRows: <TimelineRow>[
          TimelineRow(rowId: 101, name: 'Audio 1', iconId: 0),
        ],
        clientContext: _v3ClientContext(),
      );

      const expected =
          'Which vocal row should I change?\n\n'
          '• Lead Vocal\n'
          '• Backing Vocal';
      expect(result.message, expected);
      expect(result.aiV3Handoff?['decision'], 'clarify');
      expect(result.aiV3Handoff?['message'], expected);
      expect(pipeline.hasActiveAiV3PendingPlan(), isFalse);
    });

    test('clarification fallback uses structured bullets', () async {
      const message = 'The clips are on different rows. Which should I do?';
      final planner = _StaticAiV3Planner(
        const AiV3Plan(
          outcome: 'clarify',
          userMessage: message,
          commands: <AiV3Command>[],
          questionOptions: <String>[
            'Move one clip, then glue them',
            'Keep the clips separate',
          ],
        ),
      );
      final pipeline = ChatPipeline(
        llm: _FakeCloudLlmService(
          LlmResult.text('Unexpected V1 result.', null),
        ),
        projectBuilder: _FakeProjectStateBuilder(rows: 1),
        mixModel: LocalMixingModel(),
        aiV3Planner: planner,
      );

      final result = await pipeline.handleUserText(
        text: 'Glue these clips.',
        audioTracks: const <AudioTrack>[],
        rowGain: const <double>[1.0],
        rowPan: const <double>[0.5],
        rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
        bpmFallback: 120,
        timelineRows: <TimelineRow>[
          TimelineRow(rowId: 101, name: 'Audio 1', iconId: 0),
        ],
        clientContext: _v3ClientContext(),
      );

      const expected =
          '$message\n\n'
          '• Move one clip, then glue them\n'
          '• Keep the clips separate';
      expect(result.message, expected);
      expect(result.aiV3Handoff?['message'], expected);
      expect(result.message, isNot(contains('Options:')));
    });

    test(
      'factual preparation block explains the prerequisite without preview',
      () async {
        final logs = <String>[];
        final previousPrint = foundation.debugPrint;
        foundation.debugPrint = (String? message, {int? wrapWidth}) {
          logs.add(message ?? '');
        };
        addTearDown(() => foundation.debugPrint = previousPrint);
        final planner = _StaticAiV3Planner(
          const AiV3Plan(
            outcome: 'plan',
            userMessage: 'Creating another row.',
            commands: <AiV3Command>[
              AiV3Command(
                commandId: 'create',
                type: 'row.create',
                arguments: <String, dynamic>{
                  'name': 'Audio 2',
                  'lane': <String, dynamic>{'kind': 'audio'},
                  'position': <String, dynamic>{'kind': 'end'},
                },
              ),
            ],
          ),
        );
        final pipeline = ChatPipeline(
          llm: _FakeCloudLlmService(
            LlmResult.text('Unexpected V1 result.', null),
          ),
          projectBuilder: _FakeProjectStateBuilder(rows: 1),
          mixModel: LocalMixingModel(),
          aiV3Planner: planner,
          aiV3Preparer: const _FailingAiV3Preparer('v3_row_capacity_exceeded'),
        );

        final result = await pipeline.handleUserText(
          text: 'Create another audio row.',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: <TimelineRow>[
            TimelineRow(rowId: 101, name: 'Audio 1', iconId: 0),
          ],
          clientContext: _v3ClientContext(),
        );

        expect(result.aiV3Handoff?['decision'], 'blocked');
        expect(
          result.aiV3Handoff?['message'],
          'This project has reached its row limit. '
          'Delete an existing row before creating another one.',
        );
        expect(result.message, result.aiV3Handoff?['message']);
        final meta = result.meta!;
        expect(meta['preparation_failure_stage'], 'command_preparation');
        expect(meta['preparation_error_code'], 'v3_row_capacity_exceeded');
        final diagnosticLogs = logs
            .where((line) => line.startsWith('[AI.v3-preparation] '))
            .toList();
        if (const bool.fromEnvironment('AI_V3_LOCAL_VALIDATION_DIAGNOSTICS')) {
          expect(diagnosticLogs, hasLength(1));
          final diagnostic =
              jsonDecode(
                    diagnosticLogs.single.substring(
                      '[AI.v3-preparation] '.length,
                    ),
                  )
                  as Map;
          expect(diagnostic.keys.toSet(), {
            'code',
            'stage',
            'stage_elapsed_ms',
            'total_elapsed_ms',
            'command_count',
          });
          expect(diagnostic['code'], 'v3_row_capacity_exceeded');
          expect(diagnostic['stage'], 'command_preparation');
          expect(diagnostic['command_count'], 1);
          expect(diagnosticLogs.single, isNot(contains('Audio 2')));
          expect(
            diagnosticLogs.single,
            isNot(contains('Create another audio row.')),
          );
        } else {
          expect(diagnosticLogs, isEmpty);
        }
        expect(
          (meta['plan_diagnostic'] as Map)['command_type_counts'],
          <String, int>{'row.create': 1},
        );
        expect(pipeline.hasActiveAiV3PendingPlan(), isFalse);
      },
    );

    test(
      'V3 reports mix materialization failures as a distinct stage',
      () async {
        final planner = _StaticAiV3Planner(
          const AiV3Plan(
            outcome: 'plan',
            userMessage: 'Adjusting Audio 1.',
            commands: <AiV3Command>[
              AiV3Command(
                commandId: 'gain',
                type: 'row.adjust_gain_db',
                arguments: <String, dynamic>{'row_id': 101, 'delta_db': -2},
              ),
            ],
          ),
        );
        final pipeline = ChatPipeline(
          llm: _FakeCloudLlmService(
            LlmResult.text('Unexpected V1 result.', null),
          ),
          projectBuilder: _FakeProjectStateBuilder(rows: 1),
          mixModel: LocalMixingModel(),
          aiV3Planner: planner,
          aiV3MixMaterializer: _FailingAiV3MixGoalMaterializer(
            'v3_mix_action_target_invalid',
          ),
        );

        final result = await pipeline.handleUserText(
          text: 'Adjust Audio 1.',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: <TimelineRow>[
            TimelineRow(rowId: 101, name: 'Audio 1', iconId: 0),
          ],
          clientContext: _v3ClientContext(),
        );

        expect(result.aiV3Handoff?['decision'], 'blocked');
        final meta = result.meta!;
        expect(meta['preparation_failure_stage'], 'mix_materialization');
        expect(meta['preparation_error_code'], 'v3_mix_action_target_invalid');
        expect(
          (meta['plan_diagnostic'] as Map)['command_type_counts'],
          <String, int>{'row.adjust_gain_db': 1},
        );
        expect(pipeline.hasActiveAiV3PendingPlan(), isFalse);
      },
    );

    test(
      'unavailable mix effects use the actionable effect response',
      () async {
        final planner = _StaticAiV3Planner(
          const AiV3Plan(
            outcome: 'plan',
            userMessage: 'Making Audio 1 more intense.',
            commands: <AiV3Command>[
              AiV3Command(
                commandId: 'gain',
                type: 'row.adjust_gain_db',
                arguments: <String, dynamic>{'row_id': 101, 'delta_db': -2},
              ),
            ],
          ),
        );
        final pipeline = ChatPipeline(
          llm: _FakeCloudLlmService(
            LlmResult.text('Unexpected V1 result.', null),
          ),
          projectBuilder: _FakeProjectStateBuilder(rows: 1),
          mixModel: LocalMixingModel(),
          aiV3Planner: planner,
          aiV3MixMaterializer: _FailingAiV3MixGoalMaterializer(
            'v3_effect_id_unknown',
            effectId: 'Distortion',
            reason: 'effect_unavailable',
          ),
        );

        final result = await pipeline.handleUserText(
          text: 'Make Audio 1 more intense.',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: <TimelineRow>[
            TimelineRow(rowId: 101, name: 'Audio 1', iconId: 0),
          ],
          clientContext: _v3ClientContext(),
        );

        expect(result.aiV3Handoff?['decision'], 'clarify');
        expect(result.message, contains('Distortion'));
        expect(
          result.message,
          isNot(contains('I could not safely prepare every requested change')),
        );
        expect(
          result.meta?['preparation_failure_stage'],
          'mix_materialization',
        );
        expect(result.meta?['preparation_error_code'], 'v3_effect_id_unknown');
        expect(pipeline.hasActiveAiV3PendingPlan(), isFalse);
      },
    );

    test(
      'effect contract failures are actionable and expose only safe diagnostics',
      () async {
        final planner = _StaticAiV3Planner(
          const AiV3Plan(
            outcome: 'plan',
            userMessage: 'Making the guitar richer.',
            commands: <AiV3Command>[
              AiV3Command(
                commandId: 'distortion',
                type: 'effect.ensure_configured',
                arguments: <String, dynamic>{
                  'row_id': 101,
                  'effect_id': 'Distortion',
                  'parameters': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'parameter_id': 'Unsupported Amount',
                      'value': 0.73,
                    },
                  ],
                },
              ),
            ],
          ),
        );
        final pipeline = ChatPipeline(
          llm: _FakeCloudLlmService(
            LlmResult.text('Unexpected V1 result.', null),
          ),
          projectBuilder: _FakeProjectStateBuilder(rows: 1),
          mixModel: LocalMixingModel(),
          aiV3Planner: planner,
          aiV3Preparer: const _FailingAiV3Preparer(
            'v3_effect_parameter_unknown',
            commandType: 'effect.ensure_configured',
            commandIndex: 0,
            effectId: 'Distortion',
            parameterId: 'Unsupported Amount',
            reason: 'unknown_parameter',
          ),
        );

        final result = await pipeline.handleUserText(
          text: 'Secret prompt text that must not enter diagnostics.',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: <TimelineRow>[
            TimelineRow(rowId: 101, name: 'Guitar', iconId: 0),
          ],
          clientContext: _v3ClientContext(),
        );

        expect(result.aiV3Handoff?['decision'], 'clarify');
        expect(result.message, contains('Distortion'));
        expect(result.message, contains('Unsupported Amount'));
        expect(
          result.message,
          isNot(contains('I could not safely prepare every requested change')),
        );
        final diagnostic = result.meta!['preparation_diagnostic'] as Map;
        expect(diagnostic, <String, dynamic>{
          'command_type': 'effect.ensure_configured',
          'command_index': 0,
          'effect_id': 'Distortion',
          'parameter_id': 'Unsupported Amount',
          'reason': 'unknown_parameter',
        });
        expect(diagnostic.toString(), isNot(contains('0.73')));
        expect(diagnostic.toString(), isNot(contains('Secret prompt')));

        final releasePipeline = ChatPipeline(
          llm: _FakeCloudLlmService(
            LlmResult.text('Unexpected V1 result.', null),
          ),
          projectBuilder: _FakeProjectStateBuilder(rows: 1),
          mixModel: LocalMixingModel(),
          aiV3Planner: planner,
          aiV3Preparer: const _FailingAiV3Preparer(
            'v3_effect_parameter_unknown',
            commandType: 'effect.ensure_configured',
            commandIndex: 0,
            effectId: 'Distortion',
            parameterId: 'Unsupported Amount',
            reason: 'unknown_parameter',
          ),
          exposeAiV3TechnicalDetails: false,
        );
        final releaseResult = await releasePipeline.handleUserText(
          text: 'Make the guitar richer.',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: <TimelineRow>[
            TimelineRow(rowId: 101, name: 'Guitar', iconId: 0),
          ],
          clientContext: _v3ClientContext(),
        );
        expect(releaseResult.message, isNot(contains('Distortion')));
        expect(releaseResult.message, isNot(contains('Unsupported Amount')));
        expect(releaseResult.message, isNot(contains('parameter')));
      },
    );

    test(
      'empty-project mixing failure explains the missing material',
      () async {
        final planner = _StaticAiV3Planner(
          const AiV3Plan(
            outcome: 'plan',
            userMessage: 'Mixing the complete project.',
            commands: <AiV3Command>[
              AiV3Command(
                commandId: 'mix',
                type: 'mix.apply_goal',
                arguments: <String, dynamic>{
                  'target': <String, dynamic>{'scope': 'all_rows'},
                  'intents': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'kind': 'balance',
                      'direction': null,
                      'descriptor': null,
                    },
                  ],
                  'intensity': 0.5,
                  'execution_profile': 'producer_safe',
                  'audibility': 'noticeable',
                  'style_tags': <String>[],
                  'reset_fx': false,
                  'reference': null,
                },
              ),
            ],
          ),
        );
        final pipeline = ChatPipeline(
          llm: _FakeCloudLlmService(
            LlmResult.text('Unexpected V1 result.', null),
          ),
          projectBuilder: _FakeProjectStateBuilder(rows: 1),
          mixModel: LocalMixingModel(),
          aiV3Planner: planner,
        );

        final result = await pipeline.handleUserText(
          text: 'Mix the complete project.',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: <TimelineRow>[
            TimelineRow(rowId: 101, name: 'Audio 1', iconId: 0),
          ],
          clientStateDigest: 'empty-mix-state',
          clientContext: _v3ClientContext(),
        );

        expect(result.aiV3Handoff?['decision'], 'blocked');
        expect(result.aiV3Handoff?['error_code'], 'v3_mix_audio_missing');
        expect(
          result.message,
          'There is no playable audio or MIDI material to mix. '
          'Add material to the project, then try again.',
        );
        expect(pipeline.hasActiveAiV3PendingPlan(), isFalse);
      },
    );

    test(
      'future confirmation policy preserves Apply and Cancel handoff',
      () async {
        final planner = _StaticAiV3Planner(
          const AiV3Plan(
            outcome: 'plan',
            userMessage: 'Preparing the requested change.',
            commands: <AiV3Command>[
              AiV3Command(
                commandId: 'gain',
                type: 'row.adjust_gain_db',
                arguments: <String, dynamic>{'row_id': 101, 'delta_db': -2},
              ),
            ],
          ),
        );
        final pipeline = ChatPipeline(
          llm: _FakeCloudLlmService(
            LlmResult.text('Unexpected V1 result.', null),
          ),
          projectBuilder: _FakeProjectStateBuilder(rows: 1),
          mixModel: LocalMixingModel(),
          aiV3Planner: planner,
          aiV3Preparer: const _ConfirmingAiV3Preparer(),
        );
        final timelineRows = <TimelineRow>[
          TimelineRow(rowId: 101, name: 'Audio 1', iconId: 0),
        ];

        final preview = await pipeline.handleUserText(
          text: 'Run the future external operation.',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: timelineRows,
          clientStateDigest: 'future-confirm-state',
          clientContext: _v3ClientContext(),
        );
        expect(preview.aiV3Handoff?['decision'], 'ask_confirmation');
        expect(pipeline.hasActiveAiV3PendingPlan(), isTrue);

        final apply = await pipeline.handleUserText(
          text: 'apply',
          audioTracks: const <AudioTrack>[],
          rowGain: const <double>[1.0],
          rowPan: const <double>[0.5],
          rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
          bpmFallback: 120,
          timelineRows: timelineRows,
          clientStateDigest: 'future-confirm-state',
          clientContext: _v3ClientContext(),
        );
        expect(apply.aiV3Handoff?['decision'], 'execute_now');
        expect(apply.aiV3Handoff?['confirmation_granted'], isTrue);
        expect(
          (apply.aiV3Handoff?['prepared_bundle'] as Map)['execution_policy'],
          'confirm',
        );
        expect(pipeline.hasActiveAiV3PendingPlan(), isFalse);
      },
    );

    test(
      'verified execution details report receipts without repeating plan',
      () {
        expect(
          aiV3VerifiedExecutionDetails(const <String, dynamic>{
            'plan': <String, dynamic>{'user_message': 'Ajustando la mezcla.'},
            'receipts': <Map<String, dynamic>>[
              <String, dynamic>{
                'status': 'prepared',
                'preview_label': 'Lower Guitar by 1.5 dB',
              },
              <String, dynamic>{
                'status': 'already_satisfied',
                'preview_label': 'Keep Piano unchanged',
              },
            ],
          }),
          <String>[
            'Lower Guitar by 1.5 dB',
            'Keep Piano unchanged (already set)',
          ],
        );
      },
    );

    test('runtime no-op receipts are updated without mutating preparation', () {
      final bundle = <String, dynamic>{
        'receipts': <Map<String, dynamic>>[
          <String, dynamic>{
            'command_id': 'mix-row',
            'status': 'prepared',
            'expanded_action_count': 2,
            'preview_label': 'Mix Drums',
          },
          <String, dynamic>{
            'command_id': 'mute-row',
            'status': 'prepared',
            'expanded_action_count': 1,
            'preview_label': 'Mute Synth',
          },
        ],
      };

      final verified = aiV3BundleWithRuntimeAlreadySatisfiedReceipts(
        bundle,
        const <String>{'mix-row'},
      );
      final verifiedReceipts = (verified['receipts'] as List)
          .cast<Map<String, dynamic>>();
      final originalReceipts = (bundle['receipts'] as List)
          .cast<Map<String, dynamic>>();

      expect(verifiedReceipts.first['status'], 'already_satisfied');
      expect(verifiedReceipts.first['expanded_action_count'], 0);
      expect(verifiedReceipts.last['status'], 'prepared');
      expect(verifiedReceipts.last['expanded_action_count'], 1);
      expect(originalReceipts.first['status'], 'prepared');
      expect(originalReceipts.first['expanded_action_count'], 2);
      expect(aiV3VerifiedExecutionDetails(verified), <String>[
        'Mix Drums (already set)',
        'Mute Synth',
      ]);
    });

    test('verified execution details allow receipt localization', () {
      expect(
        aiV3VerifiedExecutionDetails(
          const <String, dynamic>{
            'receipts': <Map<String, dynamic>>[
              <String, dynamic>{
                'status': 'prepared',
                'verified_label': 'Set up Chorus on Chords',
                'verified_l10n_key': 'Set up {effect} on {target}.',
                'verified_l10n_args': <String, String>{
                  'effect': 'Chorus',
                  'target': 'Chords',
                },
              },
            ],
          },
          receiptLabelLocalizer: (receipt, fallback) {
            expect(receipt['verified_l10n_key'], isNotEmpty);
            return 'Chords에 Chorus를 추가하고 설정했습니다.';
          },
        ),
        <String>['Chords에 Chorus를 추가하고 설정했습니다.'],
      );
    });

    test(
      'already-satisfied completion is factual rather than future tense',
      () {
        expect(
          aiV3AlreadySatisfiedConversationMessage(const <String, dynamic>{
            'plan': <String, dynamic>{
              'user_message': 'I will make Piano blue.',
            },
            'receipts': <Map<String, dynamic>>[
              <String, dynamic>{
                'status': 'already_satisfied',
                'preview_label': 'Set Piano color to blue',
              },
            ],
          }),
          'No changes were needed:\n'
          '- Set Piano color to blue (already set)',
        );
      },
    );

    test('verified execution details expand materialized mix summaries', () {
      expect(
        aiV3VerifiedExecutionDetails(
          const <String, dynamic>{
            'plan': <String, dynamic>{
              'user_message': 'Apply a subtle polish to the master.',
            },
            'receipts': <Map<String, dynamic>>[
              <String, dynamic>{
                'command_id': 'mix-master',
                'type': 'mix.apply_goal',
                'status': 'prepared',
                'preview_label': 'Mix Master Bus',
              },
            ],
          },
          executionSummariesByCommandId: const <String, List<String>>{
            'mix-master': <String>[
              '• Added Compressor to Master Bus •',
              '• Adjusted Threshold from 0.50 to 0.42 on Compressor (Master Bus) •',
            ],
          },
        ),
        <String>[
          'Added Compressor to Master Bus',
          'Adjusted Threshold from 0.50 to 0.42 on Compressor (Master Bus)',
        ],
      );
    });

    test('verified completion uses the planner summary after success', () {
      const bundle = <String, dynamic>{
        'plan': <String, dynamic>{'user_message': 'Deleted Track 3.'},
        'receipts': <Map<String, dynamic>>[
          <String, dynamic>{
            'command_id': 'delete-track-3',
            'type': 'row.delete',
            'status': 'prepared',
            'preview_label': 'Delete Track 3',
          },
        ],
      };
      expect(aiV3VerifiedCompletionMessage(bundle), 'Deleted Track 3.');
      expect(
        aiV3VerifiedConversationMessage(bundle),
        'Done:\n- Delete Track 3',
      );
    });

    test('verified receipts take precedence over runtime action notices', () {
      expect(
        aiV3VerifiedExecutionDetails(
          const <String, dynamic>{
            'receipts': <Map<String, dynamic>>[
              <String, dynamic>{
                'command_id': 'gain',
                'status': 'prepared',
                'preview_label': 'Adjust Automation Lead by -0.5 dB',
              },
            ],
          },
          executionSummariesByCommandId: const <String, List<String>>{
            'gain': <String>['Adjust Automation Lead by -0.5 dB'],
          },
          actionNotices: const <String>[
            '• Adjusted Gain from -1.0 dB to -1.5 dB on Automation Lead •',
          ],
        ),
        <String>['Adjust Automation Lead by -0.5 dB'],
      );
    });

    test('verified action notices retain every committed command detail', () {
      expect(
        aiV3VerifiedExecutionDetails(
          const <String, dynamic>{
            'receipts': <Map<String, dynamic>>[
              <String, dynamic>{
                'command_id': 'rename',
                'status': 'prepared',
                'preview_label': 'Rename Keys to Custom Keys',
                'verified_label': 'Renamed row to Custom Keys',
              },
              <String, dynamic>{
                'command_id': 'instrument',
                'status': 'prepared',
                'preview_label': 'Set Custom Keys instrument to Dream Pad',
                'verified_label': 'Changed Custom Keys instrument to Dream Pad',
              },
            ],
          },
          actionNotices: const <String>[
            '• Renamed row to Custom Keys •',
            '• Changed Custom Keys instrument to Dream Pad •',
          ],
        ),
        <String>[
          'Renamed row to Custom Keys',
          'Changed Custom Keys instrument to Dream Pad',
        ],
      );
    });

    test(
      'forwards all added assistant action types via daw_assistant_actions',
      () async {
        final fakeLlm = _FakeCloudLlmService(
          LlmResult.tool('daw_assistant_actions', {
            'assistant_message': 'Stubbed assistant response.',
            'actions': [
              {
                'type': 'project_edit',
                'data': {'operation': 'set_tempo', 'tempo_bpm': 156},
              },
              {
                'type': 'sample_insert',
                'data': {
                  'operation': 'insert_audio_clips',
                  'items': [
                    {
                      'library_path':
                          'Starter Kit v1/Processed Drums/Kick-01.mp3',
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
                    },
                  ],
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
                  'target': {'scope': 'selected'},
                },
              },
              {
                'type': 'effect_edit',
                'data': {
                  'operation': 'remove',
                  'target': {'row_index': 0, 'effect_name': 'Gain'},
                },
              },
              {
                'type': 'row_group_edit',
                'data': {
                  'operation': 'create',
                  'row_indices': [0, 1],
                  'group_name': 'Drum Bus',
                },
              },
              {
                'type': 'row_color_edit',
                'data': {
                  'operation': 'set',
                  'target': {'row_index': 0},
                  'color_name': 'orange',
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
                      'velocity': 0.8,
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
          }, text: 'Stubbed assistant response.'),
        );

        final pipeline = ChatPipeline(
          llm: fakeLlm,
          projectBuilder: _FakeProjectStateBuilder(rows: 5),
          mixModel: LocalMixingModel(),
        );

        final audio = await _makeAudioTrack(
          path: '/tmp/test_audio.wav',
          row: 0,
        );
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
        expect(result.assistantActions.length, 12);
        expect(
          result.assistantActions.map((a) => a.type).toSet(),
          equals(const {
            'project_edit',
            'sample_insert',
            'tutorial',
            'clarify',
            'clip_edit',
            'effect_edit',
            'row_group_edit',
            'row_color_edit',
            'automation_edit',
            'midi_compose',
            'stem_separate',
            'role_override',
          }),
        );

        expect(fakeLlm.seenSelectionSnapshot, isNotNull);
        expect(fakeLlm.seenSelectionSnapshot, contains('selected_row_index=0'));
        expect(
          fakeLlm.seenSelectionSnapshot,
          contains('selected_clip_indices=0'),
        );
        expect(
          fakeLlm.seenSelectionSnapshot,
          contains('primary_selected_clip_index=0'),
        );
        expect(fakeLlm.seenSelectionSnapshot, contains('selected_clip[0]'));
        expect(
          fakeLlm.seenSelectionSnapshot,
          contains('selected_row_automation_targets='),
        );
      },
    );

    test(
      'selection snapshot forwards automation clip metadata for AI targeting',
      () async {
        final fakeLlm = _FakeCloudLlmService(
          LlmResult.tool('informational_response', {
            'message': 'Captured.',
          }, text: 'Captured.'),
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
            (_) => <AutomationPoint>[AutomationPoint(x: 0, volume: 1.0)],
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
        expect(
          fakeLlm.seenSelectionSnapshot,
          contains('pattern_id=pat_shared'),
        );
      },
    );

    test(
      'accepts full operation surface in a single stubbed action payload',
      () async {
        final actions = <Map<String, dynamic>>[
          for (final op in const [
            'trim',
            'auto_trim',
            'cut',
            'stretch',
            'glue',
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
                'target': {'clip_index': 0},
              },
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
                'target': {'row_index': 0, 'effect_name': 'Gain'},
              },
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
                'target': {'row_index': 0},
              },
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
              'role': 'drums',
            },
          },
        ];

        final fakeLlm = _FakeCloudLlmService(
          LlmResult.tool('daw_assistant_actions', {
            'assistant_message': 'Surface test.',
            'actions': actions,
          }, text: 'Surface test.'),
        );

        final pipeline = ChatPipeline(
          llm: fakeLlm,
          projectBuilder: _FakeProjectStateBuilder(rows: 5),
          mixModel: LocalMixingModel(),
        );

        final audio = await _makeAudioTrack(
          path: '/tmp/test_audio_2.wav',
          row: 0,
        );
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
            'glue',
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
      },
    );

    test(
      'delegates broad move-to-beginning clip commands to the LLM',
      () async {
        final fakeLlm = _FakeCloudLlmService(
          LlmResult.tool('daw_assistant_actions', {
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
          }, text: 'Moved all clips to the beginning.'),
        );
        final pipeline = ChatPipeline(
          llm: fakeLlm,
          projectBuilder: _FakeProjectStateBuilder(rows: 2),
          mixModel: LocalMixingModel(),
        );

        final audio = await _makeAudioTrack(
          path: '/tmp/test_audio.wav',
          row: 0,
        );
        final result = await pipeline.handleUserText(
          text: 'move all clips to beginning',
          audioTracks: <AudioTrack>[audio],
          rowGain: const [1.0, 1.0],
          rowPan: const [0.5, 0.5],
          rowAutomation: List<List<AutomationPoint>>.generate(
            2,
            (_) => <AutomationPoint>[AutomationPoint(x: 0, volume: 1.0)],
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
      },
    );

    test('delegates broad move-to-measure clip commands to the LLM', () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool('daw_assistant_actions', {
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
        }, text: 'Moved all clips to measure 3.'),
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
      expect(result.assistantActions.single.data['target'], <String, dynamic>{
        'scope': 'all',
      });
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

      final audio = await _makeAudioTrack(
        path: '/tmp/test_audio_info.wav',
        row: 0,
      );
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

    test(
      'stores clarify text in conversation instead of hidden assistant copy',
      () async {
        final fakeLlm = _QueuedFakeCloudLlmService(<LlmResult>[
          LlmResult.tool('daw_assistant_actions', {
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
          }, text: 'Done.'),
          LlmResult.tool('informational_response', {
            'cancels_pending': false,
          }, text: 'Captured.'),
        ]);
        final pipeline = ChatPipeline(
          llm: fakeLlm,
          projectBuilder: _FakeProjectStateBuilder(rows: 2),
          mixModel: LocalMixingModel(),
        );

        final audio = await _makeAudioTrack(
          path: '/tmp/test_audio_clarify.wav',
          row: 0,
        );
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
      },
    );

    test(
      'does not persist guessed assistant copy for direct effect edits',
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
                    'target': {'row_index': 0, 'effect_name': 'Gain'},
                  },
                },
              ],
            },
            text: 'Removed the Clipper plugin from track 1.',
          ),
          LlmResult.tool('informational_response', {
            'cancels_pending': false,
          }, text: 'Captured.'),
        ]);
        final pipeline = ChatPipeline(
          llm: fakeLlm,
          projectBuilder: _FakeProjectStateBuilder(rows: 2),
          mixModel: LocalMixingModel(),
        );

        final audio = await _makeAudioTrack(
          path: '/tmp/test_audio_effect_edit.wav',
          row: 0,
        );
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
      },
    );

    test(
      'merges wrapped daw_assistant_actions calls into one action list',
      () async {
        final fakeLlm = _FakeCloudLlmService(
          LlmResult.tool('daw_assistant_actions', {
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
                        },
                      ],
                    },
                  },
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
                        },
                      ],
                    },
                  },
                ],
              },
            ],
          }, text: 'Showing you in the UI.'),
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
      },
    );

    test('routes mix_model_request execute to an applied mix result', () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool('mix_model_request', {
          'mode': 'execute',
          'assistant_message': 'Applying a vocal gain bump now.',
          'actions': [
            {
              'goal': {
                'type': 'mix_request',
                'intensity': 0.75,
                'target': {'scope': 'row', 'row_index': 0, 'confidence': 0.9},
                'intents': [
                  {'kind': 'gain', 'direction': 'up', 'confidence': 0.95},
                ],
              },
            },
          ],
        }, text: 'Applying a vocal gain bump now.'),
      );
      final pipeline = ChatPipeline(
        llm: fakeLlm,
        projectBuilder: _FakeProjectStateBuilder(rows: 5),
        mixModel: LocalMixingModel(),
      );

      final audio = await _makeAudioTrack(
        path: '/tmp/test_audio_mix_exec.wav',
        row: 0,
      );
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
          LlmResult.tool('mix_model_request', {
            'mode': 'execute',
            'assistant_message': 'Pushing the mix toward the reference now.',
            'actions': [
              {
                'goal': {
                  'type': 'mix_request',
                  'intensity': 0.75,
                  'target': {'scope': 'auto', 'confidence': 0.9},
                  'intents': [
                    {'kind': 'balance', 'confidence': 0.95},
                  ],
                  'reference_target': {'row_index': 1, 'confidence': 0.95},
                  'reference_mode': 'full_mix',
                  'reference_closeness': 'balanced',
                },
              },
            ],
          }, text: 'Pushing the mix toward the reference now.'),
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

        final subject = await _makeAudioTrack(
          path: '/tmp/test_subject.wav',
          row: 0,
        );
        final reference = await _makeAudioTrack(
          path: '/tmp/test_reference.wav',
          row: 1,
        );
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
      },
    );

    test(
      'unwraps wrapped mix_model_request calls and still produces a mix',
      () async {
        final fakeLlm = _FakeCloudLlmService(
          LlmResult.tool('mix_model_request', {
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
                        },
                      ],
                    },
                  },
                ],
              },
            ],
          }, text: 'Added reverb to the drums track.'),
        );
        final pipeline = ChatPipeline(
          llm: fakeLlm,
          projectBuilder: _FakeProjectStateBuilder(rows: 5),
          mixModel: LocalMixingModel(),
        );

        final audio = await _makeAudioTrack(
          path: '/tmp/test_audio_mix_calls.wav',
          row: 0,
        );
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
      },
    );

    test(
      'routes mix_model_request propose to pending proposal message',
      () async {
        final fakeLlm = _FakeCloudLlmService(
          LlmResult.tool(
            'mix_model_request',
            {
              'mode': 'propose',
              'assistant_message':
                  'I can tighten this with subtle EQ and gain.',
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
                      },
                    ],
                  },
                },
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
          path: '/tmp/test_audio_mix_propose.wav',
          row: 0,
        );
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
      },
    );

    test(
      'proposal keeps assistant message primary and appends hint once',
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
                      },
                    ],
                  },
                },
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
          path: '/tmp/test_audio_mix_propose_primary.wav',
          row: 0,
        );
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
          RegExp(
            'Reply "yes" to apply or "no" to cancel.',
          ).allMatches(result.message).length,
          1,
        );
      },
    );

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
                      {'kind': 'gain', 'direction': 'up', 'confidence': 0.8},
                    ],
                  },
                },
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
          path: '/tmp/test_audio_mix_propose_dedupe.wav',
          row: 0,
        );
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
          RegExp(
            'Reply "yes" to apply or "no" to cancel.',
          ).allMatches(result.message).length,
          1,
        );
      },
    );

    test(
      'proposal appends approval hint even when asks_permission is true',
      () async {
        final fakeLlm = _FakeCloudLlmService(
          LlmResult.tool('mix_model_request', {
            'mode': 'propose',
            'assistant_message': 'I can make that change.',
            'asks_permission': true,
            'actions': [
              {
                'goal': {
                  'type': 'mix_request',
                  'intensity': 0.6,
                  'target': {'scope': 'row', 'row_index': 0, 'confidence': 0.9},
                  'intents': [
                    {'kind': 'gain', 'direction': 'up', 'confidence': 0.8},
                  ],
                },
              },
            ],
          }, text: 'I can make that change.'),
        );
        final pipeline = ChatPipeline(
          llm: fakeLlm,
          projectBuilder: _FakeProjectStateBuilder(rows: 5),
          mixModel: LocalMixingModel(),
        );

        final audio = await _makeAudioTrack(
          path: '/tmp/test_audio_mix_propose_ask_true.wav',
          row: 0,
        );
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
      },
    );

    test(
      'runtime snapshots include master automation targets for AI planning',
      () async {
        final fakeLlm = _FakeCloudLlmService(
          LlmResult.tool('informational_response', {
            'message': 'Captured.',
          }, text: 'Captured.'),
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

        final audio = await _makeAudioTrack(
          path: '/tmp/test_master_snapshot.wav',
          row: 0,
        );
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
      },
    );

    test('runtime snapshots expose human-readable row identity cues', () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool('informational_response', {
          'message': 'Captured.',
        }, text: 'Captured.'),
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
        rowNames: const <String>['Korean Vox', 'Pluck Bus', 'Reference', ''],
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
          'Track 3: row_name="Reference" row_color=unset row_position=middle occupied_row_position=bottom-most-occupied',
        ),
      );
      expect(
        fakeLlm.seenProjectSnapshot,
        contains('reference_hints=[single_long_clip, long_form_audio]'),
      );
      expect(
        fakeLlm.seenSelectionSnapshot,
        contains(
          'selected_row_context{row_index=1,track_number=2,row_name="Pluck Bus",row_position=middle',
        ),
      );
      expect(fakeLlm.seenSelectionSnapshot, contains('midi_state={none}'));
      expect(fakeLlm.seenSelectionSnapshot, contains('fx_chain=[none]'));
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
      expect(fakeLlm.seenSelectionSnapshot, contains('clip_kind=midi'));
    });

    test('runtime snapshots include concise fx chain state for AI planning', () async {
      final fakeLlm = _FakeCloudLlmService(
        LlmResult.tool('informational_response', {
          'message': 'Captured.',
        }, text: 'Captured.'),
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

      expect(
        fakeLlm.seenProjectSnapshot,
        contains('fx_count=2 active_fx_count=1'),
      );
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

    test(
      'passes master automation clip actions through for executor handling',
      () async {
        final fakeLlm = _FakeCloudLlmService(
          LlmResult.tool('daw_assistant_actions', {
            'assistant_message': 'Master automation clip queued.',
            'actions': [
              {
                'type': 'automation_edit',
                'data': {
                  'operation': 'create_clip',
                  'target': {'scope': 'master', 'target_id': 'master:gain'},
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
          }, text: 'Master automation clip queued.'),
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
            (_) => <AutomationPoint>[AutomationPoint(x: 0, volume: 1.0)],
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
      },
    );

    test(
      'passes group-scoped row actions through with group context',
      () async {
        final fakeLlm = _FakeCloudLlmService(
          LlmResult.tool('daw_assistant_actions', {
            'assistant_message': 'Drum bus compression queued.',
            'actions': [
              {
                'type': 'ensure_effect',
                'data': {
                  'target': {
                    'scope': 'group',
                    'group_id': 'drum_bus',
                    'group_name': 'Drum Bus',
                  },
                  'effect_name_contains': 'compressor',
                },
              },
              {
                'type': 'adjust_effect_param_by_name',
                'data': {
                  'target': {'scope': 'group', 'group_id': 'drum_bus'},
                  'effect_name_contains': 'compressor',
                  'param_name': 'Threshold',
                  'mode': 'set',
                  'value': -18.0,
                },
              },
            ],
          }, text: 'Drum bus compression queued.'),
        );

        final pipeline = ChatPipeline(
          llm: fakeLlm,
          projectBuilder: _FakeProjectStateBuilder(rows: 3),
          mixModel: LocalMixingModel(),
        );
        final tracks = <AudioTrack>[
          await _makeAudioTrack(path: '/tmp/kick.wav', row: 0, label: 'Kick'),
          await _makeAudioTrack(path: '/tmp/snare.wav', row: 1, label: 'Snare'),
        ];
        final rows = <TimelineRow>[
          TimelineRow(rowId: 101, name: 'Kick', iconId: 0, groupId: 'drum_bus'),
          TimelineRow(
            rowId: 102,
            name: 'Snare',
            iconId: 0,
            groupId: 'drum_bus',
          ),
          TimelineRow(rowId: 103, name: 'Vocal', iconId: 0),
        ];
        final groups = <TrackGroup>[
          TrackGroup(
            id: 'drum_bus',
            name: 'Drum Bus',
            rowIds: <int>[101, 102],
            collapsed: true,
            effects: <EffectSnapshot>[
              EffectSnapshot(
                'mixroom://compressor',
                false,
                const <String, dynamic>{},
                displayName: 'Compressor',
              ),
            ],
          ),
        ];

        final result = await pipeline.handleUserText(
          text: 'Compress the drum bus.',
          audioTracks: tracks,
          rowGain: const [1.0, 1.0, 1.0],
          rowPan: const [0.5, 0.5, 0.5],
          rowAutomation: List<List<AutomationPoint>>.generate(
            3,
            (_) => <AutomationPoint>[AutomationPoint(x: 0, volume: 1.0)],
          ),
          bpmFallback: 120.0,
          timelineRows: rows,
          trackGroups: groups,
        );

        expect(fakeLlm.seenProjectSnapshot, contains('Group "Drum Bus"'));
        expect(fakeLlm.seenProjectSnapshot, contains('group_id=drum_bus'));
        expect(fakeLlm.seenProjectSnapshot, contains('member_tracks=1,2'));
        expect(fakeLlm.seenProjectSnapshot, contains('fx_chain=[Compressor]'));
        expect(fakeLlm.seenProjectSnapshot, contains('Track 1:'));
        expect(fakeLlm.seenProjectSnapshot, contains('group_id=drum_bus'));
        expect(result.hasAssistantActions, isTrue);
        expect(result.assistantActions, hasLength(2));
        expect(
          result.assistantActions.first.data['target']['scope'],
          equals('group'),
        );
        expect(
          result.assistantActions.first.data['target']['group_id'],
          equals('drum_bus'),
        );
        expect(
          result.assistantActions.last.data['target']['group_id'],
          equals('drum_bus'),
        );
      },
    );
  });
}
