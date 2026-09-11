import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/config/analytics_config.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

import '../tool/generate_daw_stress_project.dart' as stress;
import 'test_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const enabled = bool.fromEnvironment('PRO17_REALTIME_PROFILE');
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
      'Offline realtime profile requires analytics disabled and '
      'loopback-only service endpoints.',
    );
  }

  testWidgets(
    'profiles deterministic large-project realtime paths',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'pro17_realtime_profile_',
      );
      addTearDown(() async {
        ProjectManager.setRootDirectoryForTesting(null);
        await root.delete(recursive: true);
      });
      ProjectManager.setRootDirectoryForTesting(root);

      for (final profileCase in _realtimeCases) {
        final fixture = await stress.generateStressProject(
          stress.StressProjectOptions(
            outputDirectory: Directory('${root.path}/${profileCase.name}'),
            rowCount: profileCase.rowCount,
            clipCount: profileCase.clipCount,
            seed: 17,
            projectName: 'PRO-17 realtime ${profileCase.name}',
          ),
        );
        if (profileCase.variant != _RealtimeVariant.mixed) {
          await _rewriteVariant(fixture.projectDirectory, profileCase.variant);
        }

        final controller = AudioEditorEvaluationController();
        await tester.pumpWidget(
          buildIntegrationTestApp(
            home: AudioEditorScreen(
              key: ValueKey<String>(profileCase.name),
              mode: 'edit',
              projectDir: fixture.projectDirectory,
              isProEntitled: true,
              evaluationController: controller,
            ),
          ),
        );
        for (
          var attempt = 0;
          attempt < 600 &&
              (!controller.isAttached ||
                  controller.snapshot()['project_ready'] != true);
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(controller.snapshot()['project_ready'], true);
        await tester.pump(const Duration(seconds: 2));

        await JuceAudioEngine.setMasterMeterEnabled(true);
        expect(await JuceAudioEngine.play(), true);
        await tester.pump(const Duration(seconds: 1));
        await JuceAudioEngine.resetRealtimePerformanceStats();
        final transportBefore = await JuceAudioEngine.getTransportSeconds();
        final stopwatch = Stopwatch()..start();
        var maximumMeterValue = 0.0;
        for (var sample = 0; sample < 50; sample++) {
          await tester.pump(const Duration(milliseconds: 100));
          final meterValues = await JuceAudioEngine.getMasterMeterValues();
          for (final value in meterValues) {
            if (value.isFinite && value.abs() > maximumMeterValue) {
              maximumMeterValue = value.abs();
            }
          }
        }
        stopwatch.stop();
        final transportAfter = await JuceAudioEngine.getTransportSeconds();
        final after = await JuceAudioEngine.getEngineDiagnostics();
        await JuceAudioEngine.pause();

        final callbackCount = after.realtimeCallbackCount;
        final wallSeconds = stopwatch.elapsedMicroseconds / 1000000.0;
        final transportSeconds = transportAfter - transportBefore;
        final observedCallbackBudgetMs =
            after.sampleRate > 0 && after.realtimeCallbackMaxSamples > 0
            ? 1000.0 * after.realtimeCallbackMaxSamples / after.sampleRate
            : 0.0;
        // This line contains aggregate synthetic performance measurements only.
        // It is intentionally easy to collect from the integration-test output.
        // ignore: avoid_print
        print(<String, Object>{
          'pro17_realtime_variant': profileCase.name,
          'rows': after.rowCount,
          'clips': after.clipCount,
          'callbacks': callbackCount,
          'over_budget_callbacks': after.realtimeCallbackOverBudgetCount,
          'observed_callback_frames': after.realtimeCallbackMaxSamples,
          'observed_callback_budget_ms': observedCallbackBudgetMs,
          'callback_last_ms': after.realtimeCallbackLastMs,
          'callback_average_ms': after.realtimeCallbackAvgMs,
          'callback_max_ms': after.realtimeCallbackMaxMs,
          'device_capacity_budget_ms': after.realtimeCallbackBudgetMs,
          'wall_seconds': wallSeconds,
          'transport_seconds': transportSeconds,
          'transport_wall_ratio': transportSeconds / wallSeconds,
          'maximum_master_meter': maximumMeterValue,
          'device_cpu_usage': after.cpuUsage,
        });

        expect(callbackCount, greaterThan(0));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

enum _RealtimeVariant { mixed, audioRows, midiRows }

class _RealtimeCase {
  const _RealtimeCase(this.name, this.rowCount, this.clipCount, this.variant);

  final String name;
  final int rowCount;
  final int clipCount;
  final _RealtimeVariant variant;
}

const _realtimeCases = <_RealtimeCase>[
  _RealtimeCase('mixed_20_20', 20, 20, _RealtimeVariant.mixed),
  _RealtimeCase('mixed_100_200', 100, 200, _RealtimeVariant.mixed),
  _RealtimeCase('mixed_200_500', 200, 500, _RealtimeVariant.mixed),
  _RealtimeCase('mixed_500_2000', 500, 2000, _RealtimeVariant.mixed),
  _RealtimeCase('audio_hotspot_500', 500, 500, _RealtimeVariant.audioRows),
  _RealtimeCase('midi_hotspot_500', 500, 500, _RealtimeVariant.midiRows),
];

Future<void> _rewriteVariant(
  Directory projectDirectory,
  _RealtimeVariant variant,
) async {
  final project = await ProjectManager.readProjectJson(projectDirectory);
  final rows = (project['rows'] as List).cast<Map<String, dynamic>>();
  final tracks = (project['tracks'] as List).cast<Map<String, dynamic>>();

  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    if (variant == _RealtimeVariant.midiRows) {
      row['kind'] = 'instrument';
      row['instrumentId'] = 'mixroom.basic_synth';
      row['instrumentName'] = 'Basic Synth';
      row['instrumentParams'] = <String, double>{};
    } else {
      row['kind'] = 'audio';
      row.remove('instrumentId');
      row.remove('instrumentName');
      row.remove('instrumentParams');
    }
  }

  for (var index = 0; index < tracks.length; index++) {
    final track = tracks[index];
    final rowIndex = index % rows.length;
    track['rowIndex'] = rowIndex;
    track['rowId'] = rows[rowIndex]['rowId'];
    track['offset'] = 0.0;
    track['trimStartMs'] = 0;
    track['trimEndMs'] = 5000;
    if (variant == _RealtimeVariant.audioRows) {
      track['clipType'] = 'audio';
      track['fileName'] = 'pro17_stress_source.wav';
      track['instrumentId'] = '';
      track['instrumentName'] = '';
      track['instrumentParams'] = <String, double>{};
      track['midiNotes'] = <Map<String, dynamic>>[];
    } else {
      track['clipType'] = 'midi';
      track['fileName'] = 'pro17_generated_midi_$index.wav';
      track['instrumentId'] = 'mixroom.basic_synth';
      track['instrumentName'] = 'Basic Synth';
      track['instrumentParams'] = <String, double>{};
      track['midiNotes'] = <Map<String, dynamic>>[
        for (var note = 0; note < 8; note++)
          <String, dynamic>{
            'id': 'pro17_${index}_$note',
            'pitch': 48 + (note % 12),
            'startBeat': note * 0.5,
            'lengthBeats': 0.4,
            'velocity': 0.7,
          },
      ];
    }
  }
  await ProjectManager.writeProjectJson(projectDirectory, project);
}
