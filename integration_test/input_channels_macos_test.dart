import 'dart:async';
import 'dart:io';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/helpers/mac_input_channel_policy.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/widgets/mac_input_channel_selector.dart';
import 'ai_v3_eval_fixture.dart';
import 'test_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    'input inventory refresh preserves unavailable saved routes and discards stale results',
    (tester) async {
      PlatformCapabilities.debugResetForCurrentPlatform();
      SharedPreferences.setMockInitialValues({
        'mixroom.daw_onboarding.seen.v1.integration-user': true,
        'mixroom.daw_onboarding.seen.v1.guest': true,
      });
      const channel = MethodChannel('juce_audio_engine');
      var capacity = 1;
      var inputReads = 0;
      var captureRequests = 0;
      Completer<void>? hold;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'setAudioRouteIntentV2' &&
            (call.arguments as Map)['intent'] != 'playbackOnly') {
          captureRequests++;
        }
        final response = await binding.defaultBinaryMessenger.delegate.send(
          channel.name,
          channel.codec.encodeMethodCall(call),
        );
        final result = response == null
            ? null
            : channel.codec.decodeEnvelope(response);
        if (call.method != 'getInputDeviceInfos') return result;
        inputReads++;
        final readCapacity = capacity;
        final waiting = hold;
        hold = null;
        if (waiting != null) await waiting.future;
        return (result as List)
            .map(
              (value) => {
                ...value as Map,
                'channelCount': readCapacity,
                'channelNames': List.filled(readCapacity, ''),
              },
            )
            .toList();
      });
      Future<void> pumpUntil(bool Function() ready) async {
        for (var i = 0; i < 300; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Timed out waiting for input settings');
      }

      Future<void> inputEvent() async {
        await binding.defaultBinaryMessenger.handlePlatformMessage(
          'juce_audio_engine/events',
          const StandardMethodCodec().encodeSuccessEnvelope({
            'event': 'macV2InputCapabilitiesChanged',
          }),
          (_) {},
        );
      }

      try {
        await deleteAllProjects();
        final fixture = await createDevelopmentEvalFixture('audio_small');
        final json = await ProjectManager.readProjectJson(fixture.directory);
        for (final row in json['rowStates'] as List) {
          row['inputChannelStart'] = 6;
          row['inputChannelCount'] = 2;
        }
        await ProjectManager.writeProjectJson(fixture.directory, json);
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
        await pumpUntil(
          () =>
              controller.isAttached &&
              (controller.snapshot()['clips'] as List).length == 2,
        );
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.identifier == 'daw.project_settings',
          ),
        );
        await pumpUntil(
          () =>
              find.byType(MacInputChannelSelector).evaluate().isNotEmpty &&
              tester
                      .widget<MacInputChannelSelector>(
                        find.byType(MacInputChannelSelector).first,
                      )
                      .status ==
                  null,
        );
        MacInputChannelSelector control() =>
            tester.widget<MacInputChannelSelector>(
              find.byType(MacInputChannelSelector).first,
            );
        expect(control().capacity, 1);
        expect(control().selection, const MacInputChannelOption(6, 2));
        expect(captureRequests, 0);
        final wait = Completer<void>();
        hold = wait;
        capacity = 8;
        final previousReads = inputReads;
        await inputEvent();
        await pumpUntil(() => inputReads > previousReads);
        capacity = 2;
        await inputEvent();
        wait.complete();
        await pumpUntil(
          () => control().status == null && control().capacity == 2,
        );
        expect(control().selection, const MacInputChannelOption(6, 2));
        control().onChanged(const MacInputChannelOption(0, 2));
        await tester.pump();
        expect(control().selection, const MacInputChannelOption(0, 2));
        expect(captureRequests, 0, reason: 'Discovery must not start capture');
        capacity = 1;
        await inputEvent();
        await pumpUntil(
          () => control().status == null && control().capacity == 1,
        );
        expect(
          control().selection,
          const MacInputChannelOption(0, 2),
          reason: 'Capacity shrink must not silently select mono',
        );
        debugPrint(
          '[PRO69-INPUT] real editor: saved route retained; latest inventory wins; explicit replacement retained across shrink; discovery opened no capture',
        );
      } finally {
        hold?.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
        await deleteAllProjects();
      }
    },
    skip: !Platform.isMacOS,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
