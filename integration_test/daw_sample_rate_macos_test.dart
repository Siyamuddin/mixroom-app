import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:mixroom/helpers/audio_test_signal.dart';
import 'package:mixroom/helpers/daw_output_sample_rate.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';

import 'ai_v3_eval_fixture.dart';
import 'test_harness.dart';

Future<void> _waitUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
  }
  fail('Timed out opening the DAW project');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'mixroom.daw_onboarding.seen.v1.integration-user': true,
      'mixroom.daw_onboarding.seen.v1.guest': true,
    });
  });

  testWidgets(
    'saved project follows output clock and renders audio',
    (tester) async {
      PlatformCapabilities.debugResetForCurrentPlatform();
      // Set the output clock in Audio MIDI Setup before running this test.
      // The same test works at 44.1, 48, or any other supported hardware rate.
      expect(
        await JuceAudioEngine.initialiseForImplementation(
          BluetoothImplementationV2.v2,
        ),
        isTrue,
      );
      final before = await JuceAudioEngine.getAudioRouteSnapshotV2();
      await JuceAudioEngine.shutdown();
      final hardwareRate = before.session.sampleRateHz;
      expect(hardwareRate, isNotNull);
      expect(hardwareRate!, greaterThan(0));
      final requests = <int>[];
      const channel = MethodChannel('juce_audio_engine');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'applyAudioRouteConfigurationV2') {
          final args = call.arguments as Map;
          if (args['updateHardwarePreferences'] == true) {
            requests.add(args['preferredSampleRateHz'] as int);
          }
        }
        // Observe the real editor-to-native boundary, without replacing native audio.
        final response = await binding.defaultBinaryMessenger.delegate.send(
          channel.name,
          channel.codec.encodeMethodCall(call),
        );
        return response == null ? null : channel.codec.decodeEnvelope(response);
      });
      try {
        await deleteAllProjects(); // Test harness installs an isolated temporary root.
        final fixture = await createDevelopmentEvalFixture('audio_small');
        final project = await ProjectManager.readProjectJson(fixture.directory);
        (project['ui'] as Map)['sampleRate'] = hardwareRate == 44100
            ? 48000
            : 44100;
        await ProjectManager.writeProjectJson(fixture.directory, project);
        await AudioTestSignal.writePcm16WavFile(
          File(
            '${ProjectManager.audioDir(fixture.directory).path}/guide_vocal.wav',
          ),
          const AudioTestSignalSpec(
            sampleRate: 44100,
            channels: 1,
            duration: Duration(milliseconds: 1200),
            frequencyHz: 220,
            amplitude: 0.02,
          ),
        );
        final controller = AudioEditorEvaluationController();
        await tester.pumpWidget(
          buildIntegrationTestApp(
            home: ExcludeSemantics(
              child: AudioEditorScreen(
                mode: 'edit',
                projectDir: fixture.directory,
                isProEntitled: true,
                evaluationController: controller,
              ),
            ),
          ),
        );
        debugPrint('[PRO69] waiting for project clips');
        await _waitUntil(
          tester,
          () =>
              controller.isAttached &&
              (controller.snapshot()['clips'] as List).length == 2 &&
              requests.isNotEmpty,
        );
        expect(
          requests,
          everyElement(0),
          reason: 'Project load must never request a saved clock',
        );
        debugPrint('[PRO69] project requests=$requests; checking native clock');
        final actual = await JuceAudioEngine.getAudioRouteSnapshotV2();
        expect(verifiedDawOutputSampleRate(actual), hardwareRate.round());
        expect(
          actual.inputs,
          isEmpty,
          reason: 'Opening a project needs no microphone',
        );
        debugPrint('[PRO69] opening project settings');
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.identifier == 'daw.project_settings',
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.byKey(ValueKey('daw-sample-rate:${hardwareRate.round()}')),
          findsOneWidget,
        );
        debugPrint('[PRO69] settings clock verified; checking audio meter');
        await JuceAudioEngine.setMasterMeterEnabled(true);
        expect(await JuceAudioEngine.play(), isTrue);
        var signal = false;
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          final meter = await JuceAudioEngine.getMasterMeterValues();
          signal = signal || meter.any((value) => value > 0.0001);
        }
        expect(
          signal,
          isTrue,
          reason: 'The loaded clip must reach the output meter',
        );
        await JuceAudioEngine.pause();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.identifier == 'daw.project_settings',
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final record = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier == 'daw.transport.record',
        );
        await tester.tap(record);
        await _waitUntil(
          tester,
          () =>
              (controller.snapshot()['transport'] as Map)['recording'] == true,
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(record);
        await _waitUntil(
          tester,
          () =>
              (controller.snapshot()['transport'] as Map)['recording'] ==
                  false &&
              (controller.snapshot()['clips'] as List).length == 3,
        );
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.identifier == 'daw.project_settings',
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.byKey(ValueKey('daw-sample-rate:${hardwareRate.round()}')),
          findsOneWidget,
          reason:
              'Recording recovery must publish its verified clock to settings',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
        await deleteAllProjects();
      }
    },
    skip: !Platform.isMacOS,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets(
    'manual rates and buffer-only edits use verified hardware clocks',
    (tester) async {
      expect(
        await JuceAudioEngine.initialiseForImplementation(
          BluetoothImplementationV2.v2,
        ),
        isTrue,
      );
      final original = await JuceAudioEngine.startAudioRouteMonitoringV2();
      final originalRate = original.session.sampleRateHz!.round();
      final originalBuffer = original.juce.bufferFrames!;
      try {
        // This hardware test requires an output supporting both standard rates.
        for (final rate in [44100, 48000]) {
          var snapshot = await JuceAudioEngine.getAudioRouteSnapshotV2();
          final changed = await JuceAudioEngine.applyAudioRouteConfigurationV2(
            snapshot.generation!,
            preferredSampleRateHz: rate,
            preferredBufferFrames: originalBuffer,
            updateHardwarePreferences: true,
          );
          expect(changed.succeeded, isTrue, reason: changed.diagnosticCode);
          expect(verifiedDawOutputSampleRate(changed.snapshot), rate);
          JuceAudioEngine.acceptVerifiedAudioRouteTransitionV2(changed);
          snapshot = await JuceAudioEngine.getAudioRouteSnapshotV2();
          final buffer = originalBuffer == 256 ? 512 : 256;
          final automatic =
              await JuceAudioEngine.applyAudioRouteConfigurationV2(
                snapshot.generation!,
                preferredSampleRateHz: 0,
                preferredBufferFrames: buffer,
                updateHardwarePreferences: true,
              );
          expect(automatic.succeeded, isTrue, reason: automatic.diagnosticCode);
          expect(verifiedDawOutputSampleRate(automatic.snapshot), rate);
          expect(automatic.snapshot.juce.bufferFrames, buffer);
          JuceAudioEngine.acceptVerifiedAudioRouteTransitionV2(automatic);
          final rejected = await JuceAudioEngine.applyAudioRouteConfigurationV2(
            automatic.generation,
            preferredSampleRateHz: -1,
            preferredBufferFrames: buffer,
            updateHardwarePreferences: true,
          );
          expect(rejected.succeeded, isFalse);
          expect(rejected.diagnosticCode, 'unsupported_hardware_settings');
          expect(verifiedDawOutputSampleRate(rejected.snapshot), rate);
          debugPrint(
            '[PRO69] hardware/device/graph=$rate buffer=$buffer; invalid request preserved clock',
          );
        }
      } finally {
        final current = await JuceAudioEngine.getAudioRouteSnapshotV2();
        final restored = await JuceAudioEngine.applyAudioRouteConfigurationV2(
          current.generation!,
          preferredSampleRateHz: originalRate,
          preferredBufferFrames: originalBuffer,
          updateHardwarePreferences: true,
        );
        expect(
          restored.succeeded,
          isTrue,
          reason: 'Restore original hardware settings',
        );
        await JuceAudioEngine.stopAudioRouteMonitoringV2();
        await JuceAudioEngine.shutdown();
      }
    },
    skip: !Platform.isMacOS,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets(
    'sample-rate control reflects native capabilities',
    (tester) async {
      PlatformCapabilities.debugResetForCurrentPlatform();
      await deleteAllProjects();
      final fixture = await createDevelopmentEvalFixture('audio_small');
      final controller = AudioEditorEvaluationController();
      try {
        await tester.pumpWidget(
          buildIntegrationTestApp(
            home: ExcludeSemantics(
              child: AudioEditorScreen(
                mode: 'edit',
                projectDir: fixture.directory,
                isProEntitled: true,
                evaluationController: controller,
              ),
            ),
          ),
        );
        await _waitUntil(
          tester,
          () =>
              controller.isAttached &&
              (controller.snapshot()['clips'] as List).length == 2,
        );
        final snapshot = await JuceAudioEngine.getAudioRouteSnapshotV2();
        final rate = verifiedDawOutputSampleRate(snapshot);
        expect(rate, isNotNull);
        expect(snapshot.outputs.single.sampleRateChangeable, isNotNull);
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.identifier == 'daw.project_settings',
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        final field = find.byKey(ValueKey('daw-sample-rate:$rate'));
        expect(field, findsOneWidget);
        final choices = selectableDawOutputSampleRates(
          snapshot,
          commonRates: const [44100, 48000, 88200, 96000],
        );
        if (choices.isEmpty) {
          expect(tester.widget(field), isA<InputDecorator>());
        } else {
          final dropdown = tester.widget<DropdownButtonFormField<int>>(field);
          // Inspect the underlying menu to ensure unsupported presets aren't offered.
          final menu = tester.widget<DropdownButton<int>>(
            find.descendant(
              of: field,
              matching: find.byType(DropdownButton<int>),
            ),
          );
          expect(
            menu.items!.where((item) => item.enabled).map((item) => item.value),
            choices,
          );
          expect(dropdown.onChanged, isNotNull);
        }
        debugPrint(
          '[PRO69] output=$rate changeable=${snapshot.outputs.single.sampleRateChangeable} choices=$choices',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await deleteAllProjects();
      }
    },
    skip: !Platform.isMacOS,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
