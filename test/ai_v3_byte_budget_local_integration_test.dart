import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_planner_service.dart';
import 'package:mixroom/ai/v3/ai_v3_preparer.dart';
import 'package:mixroom/ai/v3/ai_v3_transaction.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/screens/audio_editor.dart';

void main() {
  test(
    'byte-budget plan crosses the bridge, applies, verifies, and undoes',
    () async {
      final process = await Process.start(
        'python3',
        <String>[
          'tool/ai_v3_eval/local_v3_bridge.py',
          '--port',
          '0',
          '--scenario',
          'byte_budget_midi_success',
        ],
        workingDirectory: Directory.current.path,
        environment: <String, String>{
          ...Platform.environment,
          'PYTHONDONTWRITEBYTECODE': '1',
        },
      );
      final ready = Completer<Map<String, dynamic>>();
      final stderr = StringBuffer();
      final stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            try {
              final decoded = jsonDecode(line);
              if (decoded is Map &&
                  decoded['message'] == 'Local V3 bridge ready' &&
                  !ready.isCompleted) {
                ready.complete(Map<String, dynamic>.from(decoded));
              }
            } on FormatException {
              // The bridge emits JSON lines. Startup timeout includes stderr.
            }
          });
      final stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .listen(stderr.write);

      try {
        final readyPayload = await ready.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw StateError(
            'Local bridge did not start: ${stderr.toString()}',
          ),
        );
        final fixture = jsonDecode(
          File('backend/llm_proxy/tests/fixtures/row_rebuild_v1.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        final firstCase = (fixture['cases'] as List).first as Map;
        final contextData = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(firstCase['context'])) as Map,
        );
        contextData['profile'] = 'essential';
        contextData['state_digest'] = 'byte-budget-local-acceptance';
        contextData['request_mode'] = 'new_request';
        contextData['transport'] = <String, dynamic>{
          'playing': false,
          'recording': false,
        };
        contextData['selection'] = <String, dynamic>{
          'selected_row_ids': const <int>[100],
          'selected_clip_ids': const <String>['old0'],
        };
        contextData['master'] = <String, dynamic>{
          'gain_db': 0,
          'pan_signed': 0,
          'effects': const <Object>[],
        };
        contextData['capabilities'] = const <String>[];
        contextData['runtime_capabilities'] = const <String>[];
        final project = Map<String, dynamic>.from(contextData['project'] as Map)
          ..['project_id'] = 'byte-budget-local-project'
          ..['beat_unit'] = 4
          ..['plan_output_policy'] = aiV3PlanOutputPolicy
          ..['plan_command_policy'] = aiV3PlanCommandPolicy
          ..['generated_midi_policy'] = aiV3GeneratedMidiPolicy;
        contextData['project'] = project;
        final context = AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: 'byte-budget-local-acceptance',
          data: contextData,
        );
        final service = AiV3PlannerService(
          proxyApiBaseUrl: readyPayload['url'] as String,
          authTokenProvider: () async => 'local-test-token',
          commandTypes: const <String>{'midi.replace_notes'},
        );

        final result = await service.plan(
          context: context,
          originalRequest: 'Replace the MIDI clip with the large note set.',
        );
        expect(result.plan.commands, hasLength(1));
        final providerNotes =
            result.plan.commands.single.arguments['notes'] as List;
        expect(providerNotes, hasLength(513));

        final prepared = const AiV3CommandPreparer().prepare(
          plan: result.plan,
          context: context,
        );
        expect(prepared.actions, hasLength(1));
        final preparedNotes =
            prepared.actions.single.data['notes'] as List<dynamic>;
        expect(preparedNotes, hasLength(513));

        final clip = await AudioTrack.create(
          file: File('/tmp/pro118-byte-budget.mid'),
          originalFile: File('/tmp/pro118-byte-budget.mid'),
          audioDuration: const Duration(seconds: 4),
          trimStart: Duration.zero,
          trimEnd: const Duration(seconds: 4),
          offset: 0,
          rowIndex: 0,
          rowId: 100,
          label: 'Local acceptance MIDI',
          clipKind: ClipKind.midi,
          instrumentId: 'free-piano',
          instrumentName: 'Free Piano',
          midiNotes: <MidiNote>[
            MidiNote(
              id: 'before',
              pitch: 60,
              startBeat: 0,
              lengthBeats: 1,
              velocity: 0.7,
            ),
          ],
        );
        final before = clip.midiNotes
            .map((note) => note.toJson())
            .toList(growable: false);
        final nextNotes = <MidiNote>[
          for (var index = 0; index < preparedNotes.length; index++)
            MidiNote.fromJson(<String, dynamic>{
              ...Map<String, dynamic>.from(preparedNotes[index] as Map),
              'id': 'accepted-$index',
            }),
        ];
        final edit = EditMidiClipAction(
          tracks: <AudioTrack>[clip],
          originalIndex: 0,
          oldNotes: clip.midiNotes.map((note) => note.copy()).toList(),
          newNotes: nextNotes,
          oldInstrumentId: clip.instrumentId,
          oldInstrumentName: clip.instrumentName,
          oldInstrumentParams: Map<String, double>.from(clip.instrumentParams),
          newInstrumentId: clip.instrumentId,
          newInstrumentName: clip.instrumentName,
          newInstrumentParams: Map<String, double>.from(clip.instrumentParams),
          oldTrimEnd: clip.trimEnd,
          newTrimEnd: clip.trimEnd,
          oldAudioDuration: clip.audioDuration,
          newAudioDuration: clip.audioDuration,
          applyToClip: (target, notes, id, name, parameters, state) async {
            target.midiNotes = notes.map((note) => note.copy()).toList();
          },
        );
        final committed = <EditMidiClipAction>[];
        final transaction =
            await const AiV3LocalTransaction<EditMidiClipAction, int>().run(
              executeAndCapture: () async {
                await edit.redo();
                return <EditMidiClipAction>[edit];
              },
              verify: () async =>
                  clip.midiNotes.length == 513 &&
                  clip.midiNotes.last.pitch == nextNotes.last.pitch,
              observe: () async => <int>[clip.midiNotes.length],
              rollback: (action) => action.undo(),
              commit: (actions) async => committed.addAll(actions),
            );
        expect(transaction.observed, <int>[513]);
        expect(committed, hasLength(1));
        await committed.single.undo();
        expect(clip.midiNotes.map((note) => note.toJson()).toList(), before);

        final oversized = <String, dynamic>{
          'schema_version': aiV3PlanVersion,
          'outcome': 'respond',
          'user_message': 'No changes.',
          'commands': const <Object>[],
          'question_options': const <Object>[],
          'padding': 'x' * aiV3MaxSerializedPlanBytes,
        };
        expect(
          () => AiV3Plan.fromJson(oversized),
          throwsA(
            isA<AiV3ContractException>().having(
              (error) => error.code,
              'code',
              'v3_provider_plan_too_large',
            ),
          ),
        );
        expect(clip.midiNotes.map((note) => note.toJson()).toList(), before);
      } finally {
        process.kill(ProcessSignal.sigterm);
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        }
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
      }
    },
    skip: Platform.environment['PRO118_RUN_LOCAL_ACCEPTANCE'] == '1'
        ? false
        : 'set PRO118_RUN_LOCAL_ACCEPTANCE=1 for the local bridge check',
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
