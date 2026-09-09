import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'ai_v3_eval_fixture.dart';
import 'test_harness.dart';

class _Auth extends IntegrationTestAuthService {
  @override
  Future<String?> getIdTokenOrNull() async => 'local-live-eval-token';
  @override
  Future<String?> refreshIdTokenOrNull() async => 'local-live-eval-token';
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'local guitar follow-up produces two playable sections',
    (tester) async {
      if (!const bool.fromEnvironment('AI_V3_PITCH_LIVE_ACCEPTANCE')) return;
      final fixture = await createDevelopmentEvalFixture('empty_one_row');
      final project = await ProjectManager.readProjectJson(fixture.directory);
      final row = (project['rows'] as List).single as Map;
      row.addAll(<String, dynamic>{
        'kind': 'instrument',
        'name': 'Electric Guitar',
        'instrumentId': 'sfz.guitar.clean_electric',
        'instrumentName': 'Electric Guitar',
        'instrumentParams': <String, double>{},
      });
      await ProjectManager.writeProjectJson(fixture.directory, project);
      final auth = _Auth();
      addTearDown(auth.dispose);
      final controller = AudioEditorEvaluationController();
      await tester.pumpWidget(
        buildIntegrationTestApp(
          authServiceOverride: auth,
          home: AudioEditorScreen(
            mode: 'edit',
            projectDir: fixture.directory,
            isProEntitled: true,
            evaluationController: controller,
          ),
        ),
      );
      final wait = Stopwatch()..start();
      while (!controller.isAttached &&
          wait.elapsed < const Duration(seconds: 30)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.isAttached, isTrue);
      await tester.pump(const Duration(seconds: 2));
      await controller.submit(
        'electric guitar heavy metal 16 bars suoper rich chord prog',
      );
      var after = controller.snapshot();
      if ((after['clips'] as List).isEmpty) {
        await controller.submit('Create two contrasting 8-bar sections');
        after = controller.snapshot();
      }
      await File(
        '/tmp/pro4-pitch-native-readback.json',
      ).writeAsString(jsonEncode(after));
      final clips = (after['clips'] as List).whereType<Map>().toList();
      expect(clips, hasLength(2));
      final bpm = (after['tempo_bpm'] as num).toDouble();
      for (final clip in clips) {
        expect(clip['instrument_id'], 'sfz.guitar.clean_electric');
        expect((clip['length_ms'] as num) * bpm / 60000, closeTo(32, .00001));
        final notes = clip['midi_notes'] as List;
        expect(notes, isNotEmpty);
        for (final note in notes) {
          expect(note['pitch'], inInclusiveRange(40, 86));
        }
      }
      final starts =
          clips.map((c) => (c['start_ms'] as num) * bpm / 60000).toList()
            ..sort();
      expect(starts[0], closeTo(0, .00001));
      expect(starts[1], closeTo(32, .00001));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
