import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/config/hackathon_config.dart';
import 'package:mixroom/screens/audio_editor.dart';

import 'ai_v3_eval_fixture.dart';
import 'test_harness.dart';

/// Run on macOS with --dart-define=MIXROOM_HACKATHON=true.
/// Uses a generated fixture only; never clears existing projects.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('voice A/B restores the exact verified native mix transaction', (
    tester,
  ) async {
    expect(
      HackathonConfig.enabled,
      isTrue,
      reason: 'This test requires the isolated hackathon profile.',
    );
    final fixture = await createDevelopmentEvalFixture('audio_small');
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
    final wait = Stopwatch()..start();
    while (!controller.isAttached ||
        controller.snapshot()['project_ready'] != true) {
      if (wait.elapsed > const Duration(seconds: 30))
        fail('Editor did not become ready.');
      await tester.pump(const Duration(milliseconds: 100));
    }
    final before = controller.snapshot();
    final row = (before['rows'] as List).first as Map;
    final rowId = row['row_id'];
    final initialMute = row['muted'] == true;
    await controller.executeV3Handoff({
      'schema_version': 'ai_v3_handoff_prototype_1',
      'decision': 'execute_now',
      'plan_id': 'voice-comparison-fixture',
      'execution_policy': 'auto_apply',
      'prepared_bundle': {
        'state_digest': controller.stateDigest,
        'execution_policy': 'auto_apply',
        'plan': {
          'commands': [
            {'type': 'row.set_muted'},
          ],
        },
        'actions': [
          {
            'type': 'row_mute',
            'data': {
              'operation': initialMute ? 'unmute' : 'mute',
              'target': {'scope': 'row', 'row_index': 0, 'row_id': rowId},
            },
          },
        ],
        'receipts': [
          {
            'command_id': 'mute',
            'type': 'row.set_muted',
            'status': 'prepared',
            'preview_label': 'Change vocal mute',
          },
        ],
      },
    });
    bool muted() =>
        ((controller.snapshot()['rows'] as List).first as Map)['muted'] == true;
    expect(muted(), !initialMute);
    final afterDepth = controller.snapshot()['undo_depth'];
    final a = await controller.voiceAction({
      'type': 'comparison.before',
      'arguments': {},
    });
    expect(a['status'], 'verified');
    expect(muted(), initialMute);
    final b = await controller.voiceAction({
      'type': 'comparison.after',
      'arguments': {},
    });
    expect(b['status'], 'verified');
    expect(muted(), !initialMute);
    expect(controller.snapshot()['undo_depth'], afterDepth);
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.directory.delete(recursive: true);
  });
}
