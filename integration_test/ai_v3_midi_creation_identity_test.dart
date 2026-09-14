import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'ai_v3_eval_fixture.dart';
import 'test_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'two unreferenced guitar sections verify and undo atomically',
    (tester) async {
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
      (project['rows'] as List).single.addAll(<String, dynamic>{
        'kind': 'instrument',
        'name': 'Electric Guitar',
        'instrumentId': 'sfz.guitar.clean_electric',
        'instrumentName': 'Electric Guitar',
        'instrumentParams': <String, double>{},
      });
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
      for (var i = 0; i < 300 && !controller.isAttached; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.isAttached, isTrue);
      await tester.pump(const Duration(seconds: 2));
      final before = controller.snapshot();
      final rowId = (before['rows'] as List).single['row_id'];
      final bpm = (before['tempo_bpm'] as num).toDouble();
      final actions = <Map<String, dynamic>>[
        for (var section = 0; section < 2; section++)
          {
            'type': 'midi_compose',
            'data': <String, dynamic>{
              // Actual preparer shape when no later command references this output.
              'operation': 'create_clip',
              'start_ms': section * 32 * 60000 / bpm,
              'length_beats': 32.0,
              'exact_notes': true,
              'create_new_clip': true,
              'instrument_id': 'sfz.guitar.clean_electric',
              'target': {
                'scope': 'row',
                'row_index': 0,
                'row_id': rowId,
                'instrument_id': 'sfz.guitar.clean_electric',
              },
              'notes': [
                for (var i = 0; i < 8; i++)
                  {
                    'pitch': 40 + section * 7,
                    'start_beat': i * 4.0,
                    'length_beats': 4.0,
                    'velocity': 0.8,
                  },
              ],
            },
          },
      ];
      Map<String, dynamic> handoff(
        List<Map<String, dynamic>> selected, {
        String? digest,
      }) => {
        'schema_version': 'ai_v3_handoff_prototype_1',
        'decision': 'execute_now',
        'plan_id': 'offline-midi-identity',
        'execution_policy': 'auto_apply',
        'prepared_bundle': {
          'state_digest': digest ?? controller.stateDigest,
          'execution_policy': 'auto_apply',
          'plan': {'user_message': 'Created two sections.'},
          'actions': selected,
          'receipts': [
            for (var i = 0; i < selected.length; i++)
              {
                'command_id': 'section-$i',
                'type': 'midi.create_clip',
                'status': 'prepared',
                'preview_label': 'Create section',
              },
          ],
        },
      };
      final originalDigest = controller.stateDigest;
      await controller.executeV3Handoff(handoff(actions));
      final applied = controller.snapshot();
      final clips = (applied['clips'] as List).cast<Map>();
      expect(clips, hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(clips[i]['instrument_id'], 'sfz.guitar.clean_electric');
        expect(clips[i]['start_ms'], closeTo(i * 32 * 60000 / bpm, .001));
        expect(clips[i]['length_ms'], closeTo(32 * 60000 / bpm, .001));
        expect(clips[i]['midi_notes'], (actions[i]['data'] as Map)['notes']);
      }
      expect(applied['undo_depth'], (before['undo_depth'] as int) + 1);
      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      expect(controller.snapshot()['clips'], applied['clips']);

      // A stale plan must still be rejected without adding clips or undo entries.
      await controller.executeV3Handoff(
        handoff(actions, digest: originalDigest),
      );
      expect(controller.snapshot()['clips'], applied['clips']);
      expect(controller.snapshot()['undo_depth'], applied['undo_depth']);
      await controller.undo();

      // Even indistinguishable layered clips must resolve by actual identity.
      (actions[1]['data'] as Map)['start_ms'] = 0.0;
      (actions[1]['data'] as Map)['notes'] =
          (actions[0]['data'] as Map)['notes'];
      await controller.executeV3Handoff(handoff(actions));
      final layered = (controller.snapshot()['clips'] as List).cast<Map>();
      expect(layered, hasLength(2));
      expect(layered[0]['clip_id'], isNot(layered[1]['clip_id']));
      expect(layered.map((clip) => clip['start_ms']), everyElement(0.0));
      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);

      // Existing resource-producing actions retain their binding path.
      for (var i = 0; i < 2; i++) {
        (actions[i]['data'] as Map)['command_id'] = 'section-$i';
      }
      await controller.executeV3Handoff(handoff(actions));
      expect(controller.snapshot()['clips'], hasLength(2));
      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      for (final action in actions) {
        (action['data'] as Map).remove('command_id');
      }
      final rollbackBefore = controller.snapshot();
      await controller.executeV3Handoff(
        handoff([
          ...actions,
          {
            'type': 'row_rename',
            'data': {
              'operation': 'rename',
              'new_name': '',
              'target': {'scope': 'row', 'row_index': 0, 'row_id': rowId},
            },
          },
        ]),
      );
      expect(controller.snapshot()['clips'], rollbackBefore['clips']);
      expect(controller.snapshot()['rows'], rollbackBefore['rows']);
      expect(controller.snapshot()['undo_depth'], rollbackBefore['undo_depth']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
