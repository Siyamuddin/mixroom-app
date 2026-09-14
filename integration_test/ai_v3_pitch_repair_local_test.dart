import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'ai_v3_eval_fixture.dart';
import 'test_harness.dart';

class _LocalAuth extends IntegrationTestAuthService {
  @override
  Future<String?> getIdTokenOrNull() async => 'local-test-token';
  @override
  Future<String?> refreshIdTokenOrNull() async => 'local-test-token';
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'backend pitch patches execute, verify, undo and fail atomically',
    (tester) async {
      const enabled = bool.fromEnvironment('AI_V3_PITCH_REPAIR_LOCAL_TEST');
      if (!enabled) return;
      const url = String.fromEnvironment('AI_V3_LONG_API_BASE_URL');
      final uri = Uri.parse(url);
      expect(uri.scheme, 'http');
      expect(uri.host, '127.0.0.1');
      Future<Map<String, dynamic>> health() async => Map<String, dynamic>.from(
        jsonDecode((await http.get(Uri.parse('$url/_local/health'))).body)
            as Map,
      );
      expect((await health())['provider_mode'], 'deterministic_fake');
      expect((await health())['request_count'], 0);

      // All project files go under a new process-local /tmp root, never #132.
      final root = await Directory.systemTemp.createTemp(
        'pro4_pitch_repair_native_',
      );
      ProjectManager.setRootDirectoryForTesting(root);
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
      final auth = _LocalAuth();
      addTearDown(auth.dispose);
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        // Existing macOS integration-test semantics noise, not execution errors.
        if (text.contains(
              'A SemanticsNode with action "increase" needs to be annotated',
            ) ||
            (text.contains("'package:flutter/src/rendering/object.dart'") &&
                text.contains("'node.built'"))) {
          return;
        }
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);
      var controller = AudioEditorEvaluationController();
      Future<void> open() async {
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
        for (var i = 0; i < 300 && !controller.isAttached; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(controller.isAttached, isTrue);
        bool fixtureLoaded() {
          final snapshot = controller.snapshot();
          return snapshot['project_ready'] == true &&
              (snapshot['rows'] as List).length == 1 &&
              (snapshot['clips'] as List).isEmpty;
        }

        for (var i = 0; i < 300 && !fixtureLoaded(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          fixtureLoaded(),
          isTrue,
          reason:
              'Wait for the synthetic project, not just controller attachment',
        );
        await tester.pump(const Duration(seconds: 2));
      }

      List<Map> clips(Map snapshot) => (snapshot['clips'] as List).cast<Map>();
      void checkNotes(Map snapshot) {
        for (final clip in clips(snapshot)) {
          expect(clip['instrument_id'], 'sfz.guitar.clean_electric');
          for (final note in clip['midi_notes'] as List) {
            expect(note['pitch'], inInclusiveRange(40, 86));
            expect(note['velocity'], 0.8);
            expect(note['length_beats'], 4);
          }
        }
      }

      await open();
      final empty = controller.snapshot();
      await controller.submit(
        'Create two contrasting eight-bar guitar sections.',
      );
      final created = controller.snapshot();
      expect(clips(created), hasLength(2));
      checkNotes(created);
      final bpm = (created['tempo_bpm'] as num).toDouble();
      final starts = clips(
        created,
      ).map((c) => (c['start_ms'] as num) * bpm / 60000).toList()..sort();
      expect(starts[0], closeTo(0, 0.00001));
      expect(starts[1], closeTo(32, 0.00001));
      for (final clip in clips(created)) {
        expect((clip['length_ms'] as num) * bpm / 60000, closeTo(32, 0.00001));
        final notes = clip['midi_notes'] as List;
        expect(notes, hasLength(8));
        for (var i = 0; i < 8; i++) {
          expect(notes[i]['pitch'], i == 0 ? 48 : 47);
          expect(notes[i]['start_beat'], i * 4);
        }
      }
      expect(created['undo_depth'], (empty['undo_depth'] as int) + 1);
      await controller.undo();
      expect(controller.snapshot()['clips'], empty['clips']);
      await controller.redo();
      expect(controller.snapshot()['clips'], created['clips']);

      await controller.submit(
        'Replace the guitar notes while keeping its instrument and length.',
      );
      final replaced = controller.snapshot();
      checkNotes(replaced);
      expect(clips(replaced), hasLength(2));
      final changed = clips(replaced)
          .where((clip) => (clip['midi_notes'] as List)[1]['pitch'] == 52)
          .toList();
      expect(changed, hasLength(1));
      final editedId = changed.single['clip_id'];
      expect((changed.single['midi_notes'] as List).first['pitch'], 48);
      expect(
        (changed.single['length_ms'] as num) * bpm / 60000,
        closeTo(32, 0.00001),
      );
      expect(replaced['undo_depth'], (created['undo_depth'] as int) + 1);
      await controller.undo();
      expect(controller.snapshot()['clips'], created['clips']);
      await controller.redo();
      expect(controller.snapshot()['clips'], replaced['clips']);

      await controller.submit(
        'Append an eight-bar guitar section without changing the existing notes.',
      );
      final appended = controller.snapshot();
      checkNotes(appended);
      final edited = clips(
        appended,
      ).singleWhere((clip) => clip['clip_id'] == editedId);
      final oldNotes = changed.single['midi_notes'] as List;
      final newNotes = edited['midi_notes'] as List;
      expect(newNotes, hasLength(16));
      expect(newNotes.take(8).toList(), oldNotes);
      for (var i = 8; i < 16; i++) {
        expect(newNotes[i]['pitch'], i == 8 ? 48 : 55);
        expect(newNotes[i]['start_beat'], i * 4);
      }
      expect((edited['length_ms'] as num) * bpm / 60000, closeTo(64, 0.00001));
      expect(appended['undo_depth'], (replaced['undo_depth'] as int) + 1);
      await controller.undo();
      expect(controller.snapshot()['clips'], replaced['clips']);
      await controller.redo();
      expect(controller.snapshot()['clips'], appended['clips']);

      await controller.submit(
        'Replace the guitar notes again.',
      ); // Fixture's invalid patch.
      final failed = controller.snapshot();
      expect(failed['clips'], appended['clips']);
      expect(failed['rows'], appended['rows']);
      expect(failed['undo_depth'], appended['undo_depth']);
      final stats = await health();
      expect(stats['request_count'], 4);
      expect(stats['provider_attempt_count'], 8);
      expect(stats['usage_finalize_count'], 3);
      expect(stats['usage_release_count'], 1);
      expect(stats['pitch_repair_counts'], {
        'selected': 4,
        'applied': 3,
        'ineligible': 0,
        'failure': 1,
      });

      // Persistence and reopen coverage lives in the focused MIDI edit and
      // native identity suites. Keeping this bridge test scoped to request,
      // execution, undo/redo, and atomic rejection avoids a second editor
      // lifecycle competing with the live-frame integration binding.
      await tester.pumpWidget(const SizedBox.shrink());
      debugPrint(
        'LOCAL_PITCH_REPAIR_NATIVE: create/replace/append, exact notes, undo/redo, invalid no-change passed.',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
