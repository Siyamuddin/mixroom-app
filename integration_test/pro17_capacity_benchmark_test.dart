import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/config/analytics_config.dart';
import 'package:mixroom/helpers/daw_performance_probe.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';
import '../tool/generate_daw_stress_project.dart' as stress;
import 'test_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const enabled = bool.fromEnvironment('PRO17_PERF');
  if (!enabled) return;
  if (AnalyticsConfig.hasPostHog ||
      AnalyticsConfig.sentryDsn.isNotEmpty ||
      const String.fromEnvironment('APP_API_BASE_URL') !=
          'http://127.0.0.1:1' ||
      const String.fromEnvironment('SUBSCRIPTION_API_BASE_URL') !=
          'http://127.0.0.1:1' ||
      const String.fromEnvironment('LLM_PROXY_API_BASE_URL') !=
          'http://127.0.0.1:1') {
    throw StateError(
      'Offline benchmark requires empty POSTHOG_API_KEY and '
      'SENTRY_DSN and loopback-only APP/SUBSCRIPTION/LLM endpoints.',
    );
  }
  final rowCounts = const String.fromEnvironment(
    'PRO17_ROWS',
    defaultValue: '40,99',
  ).split(',').map(int.parse);
  final clipCounts = const String.fromEnvironment(
    'PRO17_CLIPS',
    defaultValue: '20,100,200,400',
  ).split(',').map(int.parse);
  const samples = int.fromEnvironment('PRO17_SAMPLES', defaultValue: 20);
  const runs = int.fromEnvironment('PRO17_RUNS', defaultValue: 2);
  const label = String.fromEnvironment('PRO17_LABEL', defaultValue: 'baseline');

  // Keep one live binding lifecycle for the matrix. Separate testWidgets calls
  // reset ServicesBinding state even when the native window stays foregrounded.
  testWidgets('PRO17 $label capacity matrix', (tester) async {
    for (final rows in rowCounts) {
      for (final clips in clipCounts) {
        // A desktop runner can start Dart before AppKit activates its window.
        // Readiness waiting is outside measurement; never time hidden frames.
        for (
          var attempt = 0;
          attempt < 300 && binding.lifecycleState != AppLifecycleState.resumed;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          binding.lifecycleState,
          AppLifecycleState.resumed,
          reason: 'Benchmark window did not become foreground-ready.',
        );
        final root = await Directory.systemTemp.createTemp(
          'pro17_${label}_${rows}r_${clips}c_',
        );
        ProjectManager.setRootDirectoryForTesting(root);
        addTearDown(() => ProjectManager.setRootDirectoryForTesting(null));
        final fixture = await stress.generateStressProject(
          stress.StressProjectOptions(
            outputDirectory: Directory('${root.path}/PRO-17 benchmark'),
            rowCount: rows,
            clipCount: clips,
            seed: 17,
            projectName: 'PRO-17 $label ${rows}r ${clips}c',
          ),
        );
        final middle = ((rows ~/ 2) ~/ 2) * 2;
        // Reserve one existing empty audio row for the empty-row measurement.
        final project = await ProjectManager.readProjectJson(
          fixture.projectDirectory,
        );
        for (final track in project['tracks'] as List) {
          if (track['rowIndex'] == middle) {
            track['rowIndex'] = middle + 2;
            track['rowId'] = 17000 + middle + 2;
          }
        }
        await ProjectManager.writeProjectJson(
          fixture.projectDirectory,
          project,
        );
        final controller = AudioEditorEvaluationController();
        await tester.pumpWidget(
          buildIntegrationTestApp(
            home: AudioEditorScreen(
              mode: 'edit',
              projectDir: fixture.projectDirectory,
              isProEntitled: true,
              evaluationController: controller,
            ),
          ),
        );
        for (
          var i = 0;
          i < 3000 &&
              (!controller.isAttached ||
                  controller.snapshot()['project_ready'] != true);
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(controller.snapshot()['project_ready'], true);
        expect(controller.snapshot()['rows'], hasLength(rows));
        expect(controller.snapshot()['clips'], hasLength(clips));
        await tester.pump(const Duration(seconds: 3));
        // Project loading can briefly yield focus while the desktop runner
        // creates its native window. Never record hidden-window timings, but
        // allow the same bounded readiness window used before mounting.
        for (
          var attempt = 0;
          attempt < 300 && binding.lifecycleState != AppLifecycleState.resumed;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          binding.lifecycleState,
          AppLifecycleState.resumed,
          reason: 'Benchmark window did not regain foreground readiness.',
        );
        final log = File('${root.path}/measurements.jsonl');
        var liveRows = rows, liveClips = clips;
        final probe = DawPerformanceProbe(
          isEnabled: () => true,
          context: () => DawPerformanceContext(
            projectId: 'pro17-synthetic',
            projectName: fixture.projectName,
            rowCount: liveRows,
            clipCount: liveClips,
          ),
          logFile: log,
        );
        probe.startMonitoring();
        addTearDown(() async {
          probe.stopMonitoring();
          await probe.flushLogs();
        });
        for (var run = 0; run < runs; run++) {
          for (final operation in [
            'add_row',
            'remove_row',
            'remove_populated_row',
            'move_row_up',
            'move_row_down',
            'add_clip',
            'delete_clip',
          ]) {
            for (var sample = -2; sample < samples; sample++) {
              expect(
                binding.lifecycleState,
                AppLifecycleState.resumed,
                reason:
                    'Foreground focus is required; repeat this case after a focus interruption.',
              );
              final before = controller.snapshot();
              final span = probe.beginOperation(
                operation,
                metadata: {
                  'run': run,
                  'sample': sample,
                  'warmup': sample < 0,
                  'variant': label,
                },
              );
              try {
                await controller.performanceAction(
                  operation == 'remove_populated_row'
                      ? 'remove_row'
                      : operation,
                  [
                        'add_clip',
                        'delete_clip',
                        'remove_populated_row',
                      ].contains(operation)
                      ? 0
                      : middle,
                  span,
                  sourcePath:
                      '${fixture.projectDirectory.path}/audio/pro17_stress_source.wav',
                );
                span.finish();
                await tester.pump().timeout(const Duration(seconds: 5));
                expect(
                  binding.lifecycleState,
                  AppLifecycleState.resumed,
                  reason:
                      'Discard this case: the app lost foreground focus during measurement.',
                );
                final after = controller.snapshot();
                expect(
                  after['undo_depth'],
                  (before['undo_depth'] as int) + 1,
                  reason: '$operation must execute, not silently decline',
                );
                if (operation == 'add_row') {
                  expect(after['rows'], hasLength(rows + 1));
                }
                if (operation.startsWith('remove_')) {
                  expect(after['rows'], hasLength(rows - 1));
                }
                if (operation == 'add_clip') {
                  expect(after['clips'], hasLength(clips + 1));
                }
                if (operation == 'delete_clip') {
                  expect(after['clips'], hasLength(clips - 1));
                }
                await controller.undo();
                final restored = controller.snapshot();
                liveRows = (restored['rows'] as List).length;
                liveClips = (restored['clips'] as List).length;
                expect(liveRows, rows);
                expect(liveClips, clips);
                expect(
                  restored['rows'],
                  before['rows'],
                  reason: '$operation undo must restore exact row state',
                );
                expect(
                  restored['clips'],
                  before['clips'],
                  reason: '$operation undo must restore exact clip state',
                );
                await tester.pump(const Duration(milliseconds: 100));
              } catch (error) {
                span.fail(error);
                rethrow;
              }
            }
          }
        }
        probe.stopMonitoring();
        await probe.flushLogs();
        // Aggregate analysis is performed outside the timed path.
        // ignore: avoid_print -- Machine-readable integration-runner artifact.
        print(
          'PRO17_BENCHMARK_COMPLETE ${jsonEncode({'variant': label, 'rows': rows, 'clips': clips, 'runs': runs, 'samples': samples, 'log': log.path})}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      }
    }
  }, timeout: const Timeout(Duration(minutes: 45)));
}
