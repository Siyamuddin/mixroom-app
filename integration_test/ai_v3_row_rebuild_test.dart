import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_preparer.dart';
import 'package:mixroom/ai/v3/ai_v3_resources.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'ai_v3_eval_fixture.dart';
import 'test_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'ordered full rebuild executes and restores atomically',
    (tester) async {
      var completedAllChecks = false;
      addTearDown(() {
        if (const String.fromEnvironment('PRO4_REBUILD_CONTROL').isEmpty) {
          expect(
            completedAllChecks,
            isTrue,
            reason: 'The full native acceptance sequence must finish.',
          );
        }
      });
      final root = await Directory.systemTemp.createTemp(
        'pro4_rebuild_native_',
      );
      ProjectManager.setRootDirectoryForTesting(root);
      addTearDown(() => ProjectManager.setRootDirectoryForTesting(null));
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains(
              'A SemanticsNode with action "increase" needs to be annotated',
            ) ||
            (text.contains("'package:flutter/src/rendering/object.dart'") &&
                text.contains("'node.built'")))
          return;
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);
      final fixture = await createDevelopmentEvalFixture('empty_one_row');
      final project = await ProjectManager.readProjectJson(fixture.directory);
      const instrument = String.fromEnvironment(
        'PRO4_REBUILD_INSTRUMENT',
        defaultValue: 'sfz.guitar.clean_electric',
      );
      final template = Map<String, dynamic>.from(
        (project['rows'] as List).single as Map,
      );
      project['rows'] = [
        for (var i = 0; i < 6; i++)
          {
            ...template,
            'rowId': 100 + i,
            'kind': 'instrument',
            'name': 'Old $i',
            'instrumentId': instrument,
            'instrumentName': 'Electric Guitar',
            'instrumentParams': <String, double>{},
          },
      ];
      await ProjectManager.writeProjectJson(fixture.directory, project);
      final controller = AudioEditorEvaluationController();
      await tester.pumpWidget(
        buildIntegrationTestApp(
          home: AudioEditorScreen(
            mode: 'edit',
            projectDir: fixture.directory,
            isProEntitled: true,
            evaluationController: controller,
          ),
        ),
      );
      for (
        var i = 0;
        i < 600 &&
            (!controller.isAttached ||
                controller.snapshot()['project_ready'] != true);
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.isAttached, isTrue);
      expect(
        controller.snapshot()['project_ready'],
        isTrue,
        reason: 'Do not execute edits while engine/project loading is active.',
      );
      const control = String.fromEnvironment('PRO4_REBUILD_CONTROL');
      if (control == 'load') {
        // Diagnostic control: no AI preparation, execution, or undo occurs.
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(controller.snapshot()['rows'], hasLength(6));
        await tester.pumpWidget(const SizedBox.shrink());
        return;
      }
      Map<String, dynamic> command(
        String id,
        String type,
        Map<String, dynamic> args,
      ) => {'command_id': id, 'type': type, 'arguments': args};
      final note = {
        'pitch': 60,
        'start_beat': 0.0,
        'length_beats': 1.0,
        'velocity': 0.7,
      };
      Future<void> execute(
        List<Map<String, dynamic>> commands, {
        bool fail = false,
        bool staleRowIndices = false,
      }) async {
        final snapshot = controller.snapshot();
        final rows = (snapshot['rows'] as List).cast<Map>();
        final context = AiV3CoreContext(
          profile: AiV3ContextProfile.essential,
          stateDigest: controller.stateDigest,
          data: {
            'project': {
              'plan_command_policy': aiV3PlanCommandPolicy,
              'bpm': snapshot['tempo_bpm'],
              'beats_per_bar': 4,
              'row_capacity': {
                'current_rows': rows.length,
                'max_rows': 6,
                'can_create': rows.length < 6,
              },
            },
            'transport': {
              'playing': false,
              'recording': false,
              'loop_enabled': false,
            },
            'rows': [
              for (var i = 0; i < rows.length; i++)
                {
                  'row_id': rows[i]['row_id'],
                  'display_index': i,
                  'name': rows[i]['name'],
                  'lane_kind': 'instrument',
                  'instrument_id': instrument,
                },
            ],
            'clips': [
              for (final raw in snapshot['clips'] as List)
                {
                  ...Map<String, dynamic>.from(raw as Map),
                  'kind': 'midi',
                  'length_beats':
                      (raw['length_ms'] as num) *
                      (snapshot['tempo_bpm'] as num) /
                      60000,
                },
            ],
            'groups': [],
            'effects': [],
            'library_assets': [],
            'instruments': [instrument],
            'instrument_catalog': [
              {
                'instrument_id': instrument,
                'name': 'Electric Guitar',
                'playable_pitch_ranges': [
                  {'low': 40, 'high': 86},
                ],
              },
            ],
          },
        );
        final plan = AiV3Plan.fromJson(
          {
            'schema_version': aiV3PlanVersion,
            'outcome': 'plan',
            'user_message': 'Rebuilt the synthetic arrangement.',
            'commands': commands,
            'question_options': [],
          },
          allowResourceRefs: true,
          resourceRefCommandTypes: aiV3RuntimeResourceRefConsumerTypes,
        );
        final bundle = const AiV3CommandPreparer()
            .prepare(plan: plan, context: context)
            .toJson();
        if (staleRowIndices) {
          for (final action in bundle['actions'] as List) {
            final target = action['data']['target'];
            if (target is Map && target['row_id'] is int) {
              target['row_index'] = 0;
            }
          }
        }
        if (fail)
          (bundle['actions'] as List).add({
            'type': 'row_rename',
            'data': {
              'operation': 'rename',
              'new_name': '',
              'resource_consumer_type': 'row.rename',
              'expected_name': '',
              'target': {
                'scope': 'row',
                'resource_ref': {'command_id': 'new0', 'output': 'row'},
              },
            },
          });
        await controller.executeV3Handoff({
          'schema_version': 'ai_v3_handoff_prototype_1',
          'decision': 'execute_now',
          'plan_id': 'offline-rebuild',
          'confirmation_granted': true,
          'execution_policy': 'auto_apply',
          'prepared_bundle': bundle,
        });
      }

      final ids = (controller.snapshot()['rows'] as List)
          .map((r) => r['row_id'] as int)
          .toList();
      expect(ids, hasLength(6));
      await execute([
        for (var i = 0; i < 6; i++)
          command('seed$i', 'midi.create_clip', {
            'destination': {'row_id': ids[i]},
            'start_beat': 0,
            'length_beats': 8,
            'notes': [note],
          }),
      ]);
      final before = controller.snapshot();
      expect(before['clips'], hasLength(6));
      if (control == 'seed' || control == 'delete' || control == 'seed-undo') {
        // Diagnostic controls isolate creation and a single deletion from rebuild.
        if (control == 'delete') {
          await execute([
            command('delete-control', 'row.delete', {'row_id': ids.first}),
          ]);
        }
        if (control == 'seed-undo') {
          await controller.undo();
        }
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          controller.snapshot()['clips'],
          hasLength(
            control == 'seed-undo'
                ? 0
                : control == 'delete'
                ? 5
                : 6,
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        return;
      }
      final commands = <Map<String, dynamic>>[
        for (var i = 0; i < 5; i++)
          command('delete$i', 'row.delete', {'row_id': ids[i]}),
        for (var i = 0; i < 4; i++) ...[
          command('new$i', 'row.create', {
            'name': 'New $i',
            'lane': {'kind': 'midi', 'instrument_id': instrument},
            'position': {'kind': 'end'},
          }),
          command('music$i', 'midi.create_clip', {
            'destination': {
              'row_ref': {'command_id': 'new$i', 'output': 'row'},
            },
            'start_beat': 0,
            'length_beats': 8,
            'notes': [
              {...note, 'pitch': 60 + i},
            ],
          }),
          if (i == 0) command('last', 'row.delete', {'row_id': ids.last}),
        ],
      ];
      await execute(commands);
      debugPrint('REBUILD_CHECKPOINT applied');
      final after = controller.snapshot();
      expect(after['rows'], hasLength(4));
      expect(after['clips'], hasLength(4));
      for (final row in after['rows'] as List) {
        expect(ids, isNot(contains(row['row_id'])));
      }
      for (final clip in after['clips'] as List) {
        final row = (after['rows'] as List).singleWhere(
          (row) => row['row_id'] == clip['row_id'],
        );
        final part = int.parse((row['name'] as String).split(' ').last);
        expect(clip['midi_notes'], [
          {...note, 'pitch': 60 + part},
        ]);
        expect(clip['instrument_id'], instrument);
      }
      if (control == 'rebuild') {
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(controller.snapshot()['rows'], after['rows']);
        expect(controller.snapshot()['clips'], after['clips']);
        await tester.pumpWidget(const SizedBox.shrink());
        return;
      }
      await controller.undo();
      debugPrint('REBUILD_CHECKPOINT undo');
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      debugPrint('REBUILD_CHECKPOINT redo');
      expect(controller.snapshot()['rows'], after['rows']);
      expect(controller.snapshot()['clips'], after['clips']);
      await controller.undo();
      final rollbackBefore = controller.snapshot();
      if (const bool.fromEnvironment(
        'PRO4_REBUILD_INJECT_FAILURE',
        defaultValue: true,
      )) {
        await execute(commands, fail: true);
        debugPrint('REBUILD_CHECKPOINT rollback');
        expect(controller.snapshot()['rows'], rollbackBefore['rows']);
        expect(controller.snapshot()['clips'], rollbackBefore['clips']);
        expect(
          controller.snapshot()['undo_depth'],
          rollbackBefore['undo_depth'],
        );
      }

      // Referenced clip outputs use the same stable destination rule.
      await execute([
        ...commands,
        command('referenced-notes', 'midi.replace_notes', {
          'clip_ref': {'command_id': 'music0', 'output': 'midi_clip'},
          'notes': [note],
        }),
      ]);
      expect(controller.snapshot()['rows'], hasLength(4));
      expect(controller.snapshot()['clips'], hasLength(4));
      await controller.undo();
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);

      // A stable existing destination survives deletion before creation.
      await execute([
        command('remove-first', 'row.delete', {'row_id': ids.first}),
        command('existing-destination', 'midi.create_clip', {
          'destination': {'row_id': ids.last},
          'start_beat': 8,
          'length_beats': 8,
          'notes': [note],
        }),
      ], staleRowIndices: true);
      expect(controller.snapshot()['rows'], hasLength(5));
      expect(controller.snapshot()['clips'], hasLength(6));
      final extra = (controller.snapshot()['clips'] as List)
          .where((clip) => (clip['start_ms'] as num) > 0)
          .single;
      expect(extra['row_id'], ids.last);
      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);

      // Removing the actual new destination retires its creation expectations.
      await execute([
        command('make-room', 'row.delete', {'row_id': ids.first}),
        commands[5],
        commands[6],
        command('remove-new', 'row.delete', {
          'row_ref': {'command_id': 'new0', 'output': 'row'},
        }),
      ]);
      expect(controller.snapshot()['rows'], hasLength(5));
      expect(controller.snapshot()['clips'], hasLength(5));
      expect(
        (controller.snapshot()['rows'] as List).map((r) => r['name']),
        isNot(contains('New 0')),
      );
      await controller.undo();
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      // The larger command ceiling must execute as one reversible transaction.
      final commandBudgetBefore = controller.snapshot();
      final budgetCommands = [
        for (var i = 0; i < 32; i++)
          command('budget$i', 'row.rename', {
            'row_id': ids[i % ids.length],
            'new_name': 'Budget $i',
          }),
      ];
      await execute(budgetCommands);
      final commandBudgetAfter = controller.snapshot();
      for (var i = 0; i < ids.length; i++) {
        final last = i + ((31 - i) ~/ ids.length) * ids.length;
        final row = (commandBudgetAfter['rows'] as List).singleWhere(
          (r) => r['row_id'] == ids[i],
        );
        expect(row['name'], 'Budget $last');
      }
      expect(commandBudgetAfter['clips'], commandBudgetBefore['clips']);
      await controller.undo();
      expect(controller.snapshot()['rows'], commandBudgetBefore['rows']);
      await controller.redo();
      expect(controller.snapshot()['rows'], commandBudgetAfter['rows']);
      await controller.undo();
      final budgetRollbackBefore = controller.snapshot();
      await execute(budgetCommands, fail: true);
      expect(controller.snapshot()['rows'], budgetRollbackBefore['rows']);
      expect(controller.snapshot()['clips'], budgetRollbackBefore['clips']);
      expect(
        controller.snapshot()['undo_depth'],
        budgetRollbackBefore['undo_depth'],
      );
      print('COMMAND_BUDGET_CHECKPOINT 32_execution_undo_redo_rollback_passed');
      await tester.pumpWidget(const SizedBox.shrink());
      completedAllChecks = true;
      // Synchronous completion marker: do not lose it to throttled debug logs.
      print('REBUILD_CHECKPOINT all_checks_completed');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
