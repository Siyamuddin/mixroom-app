import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
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

// Native offline export checks the actual engine graph, not a reconstructed
// test-only note list. Verify silence before placement and signal near both ends.
Future<void> _checkNativeAudio(
  String path,
  double start,
  double duration,
) async {
  final exported = await JuceAudioEngine.exportMix(
    path,
    wavDithering: false,
    bypassMasterProcessing: true,
    bypassGroupProcessing: true,
  );
  expect(exported, isNotEmpty);
  final bytes = await File(exported).readAsBytes();
  final data = ByteData.sublistView(bytes);
  expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
  var channels = 0, rate = 0, offset = 0, length = 0;
  for (var at = 12; at + 8 <= bytes.length;) {
    final name = ascii.decode(bytes.sublist(at, at + 4));
    final size = data.getUint32(at + 4, Endian.little);
    if (name == 'fmt ') {
      expect(data.getUint16(at + 8, Endian.little), 1);
      channels = data.getUint16(at + 10, Endian.little);
      rate = data.getUint32(at + 12, Endian.little);
      expect(data.getUint16(at + 22, Endian.little), 16);
    } else if (name == 'data') {
      offset = at + 8;
      length = size;
      break;
    }
    at += 8 + size + (size % 2);
  }
  expect(channels, greaterThan(0));
  expect(rate, greaterThan(0));
  expect(
    length / (2 * channels * rate),
    greaterThanOrEqualTo(start + duration - 0.02),
  );
  double peak(double from, double to) {
    var result = 0.0;
    for (
      var frame = (from * rate).ceil();
      frame < (to * rate).floor();
      frame++
    ) {
      for (var channel = 0; channel < channels; channel++) {
        final at = offset + (frame * channels + channel) * 2;
        final value = data.getInt16(at, Endian.little).abs() / 32768;
        if (value > result) result = value;
      }
    }
    return result;
  }

  expect(peak(0, start - 0.05), lessThan(0.0001));
  expect(peak(start + 0.05, start + 0.5), greaterThan(0.0001));
  expect(
    peak(start + duration - 0.5, start + duration - 0.05),
    greaterThan(0.0001),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'MIDI budget and complete-input native acceptance',
    (tester) async {
      const enabled = bool.fromEnvironment('AI_V3_GENERATED_MIDI_LOCAL_TEST');
      const inputAcceptance = bool.fromEnvironment(
        'AI_V3_INPUT_NOTES_LOCAL_TEST',
      );
      if (!enabled && !inputAcceptance) return;
      const url = String.fromEnvironment('AI_V3_LONG_API_BASE_URL');
      expect(Uri.parse(url).host, '127.0.0.1');
      expect(Uri.parse(url).scheme, 'http');
      Future<Map<String, dynamic>> health() async => Map<String, dynamic>.from(
        jsonDecode((await http.get(Uri.parse('$url/_local/health'))).body)
            as Map,
      );
      expect((await health())['provider_mode'], 'deterministic_fake');
      expect((await health())['request_count'], 0);
      final root = await Directory.systemTemp.createTemp('pro4_512_native_');
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
      Future<void> open({int expectedClips = 0}) async {
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
          final rows = snapshot['rows'] as List;
        return snapshot['project_ready'] == true && rows.length == 1 &&
              (snapshot['clips'] as List).length == expectedClips;
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

      await open();
      final before = controller.snapshot();
      expect(before['clips'], isEmpty);
      await controller.submit(
        'Create the deterministic 512-note guitar fixture.',
      );
      var created = controller.snapshot();
      expect(created['clips'], hasLength(1));
      final clip = (created['clips'] as List).single as Map;
      final expected = List.generate(
        512,
        (i) => <String, dynamic>{
          'pitch': 48 + i % 4 * 4,
          'start_beat': (i ~/ 4) * 0.125,
          'length_beats': 0.125,
          'velocity': 0.75,
        },
      );
      expect(clip['midi_notes'], expected);
      expect(clip['instrument_id'], 'sfz.guitar.clean_electric');
      final bpm = (created['tempo_bpm'] as num).toDouble();
      expect((clip['start_ms'] as num) * bpm / 60000, closeTo(4, 0.00001));
      expect((clip['length_ms'] as num) * bpm / 60000, closeTo(16, 0.00001));
      expect(created['undo_depth'], (before['undo_depth'] as int) + 1);
      await _checkNativeAudio(
        '${root.path}/created.wav',
        4 * 60 / bpm,
        16 * 60 / bpm,
      );
      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      expect(controller.snapshot()['clips'], created['clips']);
      if (inputAcceptance) {
        await controller.submit(
          'Add another separate 512-note guitar clip after the first.',
        );
        final expanded = controller.snapshot();
        expect(expanded['clips'], hasLength(2));
        for (final item in expanded['clips'] as List) {
          expect((item as Map)['midi_notes'], expected);
        }
        await controller.submit(
          'Rename the track to Complete 1024-note project. Keep all notes unchanged.',
        );
        created = controller.snapshot();
        expect(created['clips'], expanded['clips']);
        expect(
          ((created['rows'] as List).single as Map)['name'],
          'Complete 1024-note project',
        );
        expect(created['undo_depth'], (expanded['undo_depth'] as int) + 1);
        await controller.undo();
        expect(controller.snapshot()['rows'], expanded['rows']);
        expect(controller.snapshot()['clips'], expanded['clips']);
        await controller.redo();
        expect(controller.snapshot()['rows'], created['rows']);
        expect(controller.snapshot()['clips'], created['clips']);
        final stats = await health();
        expect(stats['request_count'], 3);
        expect(stats['provider_attempt_count'], 3);
        expect(stats['usage_finalize_count'], 3);
        expect(stats['usage_release_count'], 0);
      } else {
        await controller.submit(
          'Replace with the deterministic rejected 513-note fixture.',
        );
        final rejected = controller.snapshot();
        for (final key in ['clips', 'rows', 'undo_depth']) {
          expect(rejected[key], created[key]);
        }
        final stats = await health();
        expect(stats['request_count'], 2);
        expect(stats['provider_attempt_count'], 2);
        expect(stats['usage_finalize_count'], 1);
        expect(stats['usage_release_count'], 1);
      }
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      controller = AudioEditorEvaluationController();
      await open(expectedClips: (created['clips'] as List).length);
      if (inputAcceptance) {
        expect(
          ((controller.snapshot()['rows'] as List).single as Map)['name'],
          'Complete 1024-note project',
        );
      }
      List<Map> musicalClips(Map snapshot) => (snapshot['clips'] as List)
          .map((clip) => Map.of(clip as Map)..remove('file'))
          .toList();
      expect(musicalClips(controller.snapshot()), musicalClips(created));
      await _checkNativeAudio(
        '${root.path}/reopened.wav',
        4 * 60 / bpm,
        16 * 60 / bpm,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      // ignore: avoid_print
      print(
        inputAcceptance
            ? 'LOCAL_1024_INPUT_NATIVE: two exact 512-note clips, 1024-note request, '
                  'rename readback, undo/redo, save/reopen, native audio passed. Artifacts: ${root.path}'
            : 'LOCAL_512_NATIVE: exact 512 notes, native audio placement, undo/redo, '
                  '513 atomic rejection, save/reopen passed. Artifacts: ${root.path}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
