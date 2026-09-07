import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/screens/audio_timeline_pro.dart';
import 'package:mixroom/widgets/desktop_scrollable_slider.dart';

import 'ai_v3_eval_fixture.dart';
import 'test_harness.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
  fail('Timed out waiting for clip inspector state.');
}

Future<void> _pumpUi(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 300));

Future<({AudioEditorEvaluationController controller, Directory directory})>
_openInspectorFixture(WidgetTester tester) async {
  await deleteAllProjects();
  final fixture = await createDevelopmentEvalFixture('clip_inspector_mixed');
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
  await _pumpUntil(
    tester,
    () =>
        controller.isAttached &&
        find.byType(AudioCanvasTimeline).evaluate().isNotEmpty &&
        (controller.snapshot()['clips'] as List).length == 3,
  );
  return (controller: controller, directory: fixture.directory);
}

Map<String, dynamic> _clip(
  AudioEditorEvaluationController controller,
  String clipId,
) {
  return (controller.snapshot()['clips'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((clip) => clip['clip_id'] == clipId);
}

Finder _inspector(String clipId) =>
    find.byKey(ValueKey('tablet_clip_options_$clipId'));

Finder _nameField(String clipId) =>
    find.byKey(ValueKey('tablet_audio_clip_name_$clipId'));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUp(() async {
    await deleteAllProjects();
  });

  tearDown(() async {
    await deleteAllProjects();
  });

  testWidgets('open inspector follows audio and MIDI targets', (tester) async {
    final fixture = await _openInspectorFixture(tester);
    final controller = fixture.controller;

    controller.openClipInspector('inspector_audio_a');
    await _pumpUi(tester);
    expect(_inspector('inspector_audio_a'), findsOneWidget);
    expect(find.text('Audio Clip Options'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(_nameField('inspector_audio_a'))
          .controller!
          .text,
      'Audio A',
    );
    expect(
      tester
          .widget<PrettyGainSlider>(
            find.byKey(const ValueKey('tablet_clip_gain_inspector_audio_a')),
          )
          .value,
      1.25,
    );
    expect(
      tester
          .widget<DesktopScrollableSlider>(
            find.byKey(const ValueKey('tablet_clip_pitch_inspector_audio_a')),
          )
          .value,
      -2.5,
    );
    expect(find.text('Normalize'), findsOneWidget);

    controller.selectClipForInspector('inspector_audio_b');
    await _pumpUi(tester);
    expect(_inspector('inspector_audio_a'), findsNothing);
    expect(_inspector('inspector_audio_b'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(_nameField('inspector_audio_b'))
          .controller!
          .text,
      'Audio B',
    );
    expect(
      tester
          .widget<PrettyGainSlider>(
            find.byKey(const ValueKey('tablet_clip_gain_inspector_audio_b')),
          )
          .value,
      2.6,
    );
    expect(
      tester
          .widget<DesktopScrollableSlider>(
            find.byKey(const ValueKey('tablet_clip_pitch_inspector_audio_b')),
          )
          .value,
      4.0,
    );

    controller.selectClipForInspector('inspector_midi');
    await _pumpUi(tester);
    expect(_inspector('inspector_midi'), findsOneWidget);
    expect(find.text('MIDI Clip Options'), findsOneWidget);
    expect(find.text('No extra tempo mode is needed here.'), findsOneWidget);
    expect(find.text('Normalize'), findsNothing);

    controller.selectClipForInspector(null);
    await _pumpUi(tester);
    expect(_inspector('inspector_midi'), findsOneWidget);

    controller.closeClipInspector();
    controller.selectClipForInspector('inspector_audio_a');
    await _pumpUi(tester);
    expect(
      find.byKey(const ValueKey('tablet_clip_options_inspector_audio_a')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  }, semanticsEnabled: false);

  testWidgets(
    'enter and checkmark repaint the timeline label immediately',
    (tester) async {
      final fixture = await _openInspectorFixture(tester);
      final controller = fixture.controller;
      controller.openClipInspector('inspector_audio_a');
      await _pumpUi(tester);

      final revisionBeforeEnter = tester
          .widget<AudioCanvasTimeline>(find.byType(AudioCanvasTimeline).first)
          .clipVisualRevision;
      await tester.tap(_nameField('inspector_audio_a'));
      await tester.enterText(_nameField('inspector_audio_a'), 'Entered A');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _pumpUntil(
        tester,
        () => _clip(controller, 'inspector_audio_a')['label'] == 'Entered A',
      );
      expect(
        tester
            .widget<AudioCanvasTimeline>(find.byType(AudioCanvasTimeline).first)
            .clipVisualRevision,
        greaterThan(revisionBeforeEnter),
      );

      final revisionBeforeCheckmark = tester
          .widget<AudioCanvasTimeline>(find.byType(AudioCanvasTimeline).first)
          .clipVisualRevision;
      await tester.tap(
        find.descendant(
          of: _inspector('inspector_audio_a'),
          matching: find.byIcon(Icons.edit_rounded),
        ),
      );
      await tester.enterText(_nameField('inspector_audio_a'), 'Checked A');
      await tester.tap(
        find.descendant(
          of: _inspector('inspector_audio_a'),
          matching: find.byIcon(Icons.check_rounded),
        ),
      );
      await _pumpUntil(
        tester,
        () => _clip(controller, 'inspector_audio_a')['label'] == 'Checked A',
      );
      expect(
        tester
            .widget<AudioCanvasTimeline>(find.byType(AudioCanvasTimeline).first)
            .clipVisualRevision,
        greaterThan(revisionBeforeCheckmark),
      );

      await controller.undo();
      await _pumpUntil(
        tester,
        () => _clip(controller, 'inspector_audio_a')['label'] == 'Entered A',
      );
      expect(
        tester
            .widget<TextFormField>(_nameField('inspector_audio_a'))
            .controller!
            .text,
        'Entered A',
      );

      await controller.redo();
      await _pumpUntil(
        tester,
        () => _clip(controller, 'inspector_audio_a')['label'] == 'Checked A',
      );
      expect(
        tester
            .widget<TextFormField>(_nameField('inspector_audio_a'))
            .controller!
            .text,
        'Checked A',
      );

      await tester.tap(
        find.descendant(
          of: _inspector('inspector_audio_a'),
          matching: find.byIcon(Icons.edit_rounded),
        ),
      );
      await tester.enterText(_nameField('inspector_audio_a'), 'Active draft');
      await controller.undo();
      await _pumpUntil(
        tester,
        () => _clip(controller, 'inspector_audio_a')['label'] == 'Entered A',
      );
      expect(
        tester
            .widget<TextFormField>(_nameField('inspector_audio_a'))
            .controller!
            .text,
        'Active draft',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'switching commits rename and gesture edits to their source',
    (tester) async {
      final fixture = await _openInspectorFixture(tester);
      final controller = fixture.controller;
      final initialUndoDepth = controller.snapshot()['undo_depth'] as int;

      controller.openClipInspector('inspector_audio_a');
      await _pumpUi(tester);
      await tester.tap(_nameField('inspector_audio_a'));
      await tester.enterText(_nameField('inspector_audio_a'), 'Renamed A');
      controller.selectClipForInspector('inspector_audio_a');
      await tester.pump();
      expect(find.text('Renamed A'), findsOneWidget);

      controller.selectClipForInspector('inspector_audio_b');
      await _pumpUntil(
        tester,
        () => _clip(controller, 'inspector_audio_a')['label'] == 'Renamed A',
      );
      expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);
      expect(
        tester
            .widget<TextFormField>(_nameField('inspector_audio_b'))
            .controller!
            .text,
        'Audio B',
      );

      controller.selectClipForInspector('inspector_audio_a');
      await _pumpUi(tester);
      final gain = tester.widget<PrettyGainSlider>(
        find.byKey(const ValueKey('tablet_clip_gain_inspector_audio_a')),
      );
      gain.onChangeStart(gain.value);
      gain.onChanged(1.6);
      controller.selectClipForInspector('inspector_audio_b');
      await _pumpUntil(
        tester,
        () => (_clip(controller, 'inspector_audio_a')['gain'] as double) == 1.6,
      );
      expect(_clip(controller, 'inspector_audio_b')['gain'], 2.6);

      controller.selectClipForInspector('inspector_audio_a');
      await _pumpUi(tester);
      final pitch = tester.widget<DesktopScrollableSlider>(
        find.byKey(const ValueKey('tablet_clip_pitch_inspector_audio_a')),
      );
      pitch.onChangeStart?.call(pitch.value);
      pitch.onChanged?.call(3.5);
      controller.selectClipForInspector('inspector_audio_b');
      await _pumpUntil(
        tester,
        () =>
            (_clip(controller, 'inspector_audio_a')['pitch_semitones']
                as double) ==
            3.5,
      );
      expect(_clip(controller, 'inspector_audio_b')['pitch_semitones'], 4.0);

      await controller.undo();
      await _pumpUi(tester);
      expect(_clip(controller, 'inspector_audio_a')['pitch_semitones'], -2.5);

      final undoDepthBeforeNoOpRenames = controller.snapshot()['undo_depth'];
      controller.selectClipForInspector('inspector_audio_a');
      await _pumpUi(tester);
      await tester.tap(_nameField('inspector_audio_a'));
      controller.selectClipForInspector('inspector_audio_b');
      await _pumpUi(tester);
      expect(controller.snapshot()['undo_depth'], undoDepthBeforeNoOpRenames);

      controller.selectClipForInspector('inspector_audio_a');
      await _pumpUi(tester);
      await tester.tap(_nameField('inspector_audio_a'));
      await tester.enterText(_nameField('inspector_audio_a'), '   ');
      controller.selectClipForInspector('inspector_audio_b');
      await _pumpUi(tester);
      expect(controller.snapshot()['undo_depth'], undoDepthBeforeNoOpRenames);
      expect(_clip(controller, 'inspector_audio_a')['label'], 'Renamed A');

      await tester.pumpWidget(const SizedBox.shrink());
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'topology changes preserve identity and remove missing target',
    (tester) async {
      final fixture = await _openInspectorFixture(tester);
      final controller = fixture.controller;
      controller.openClipInspector('inspector_audio_b');
      await _pumpUi(tester);

      await controller.deleteClip('inspector_audio_a');
      await _pumpUntil(
        tester,
        () =>
            (controller.snapshot()['clips'] as List).length == 2 &&
            _inspector('inspector_audio_b').evaluate().isNotEmpty,
      );
      expect(_inspector('inspector_audio_b'), findsOneWidget);

      await controller.deleteClip('inspector_audio_b');
      await _pumpUntil(
        tester,
        () => _inspector('inspector_audio_b').evaluate().isEmpty,
      );
      expect(_inspector('inspector_audio_b'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
    semanticsEnabled: false,
  );
}
