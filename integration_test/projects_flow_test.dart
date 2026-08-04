import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/screens/signed_in_shell.dart';
import 'package:path/path.dart' as p;

import 'test_harness.dart';

const Key _projectsScreenKey = Key('projects_screen');
const Key _newProjectCardKey = Key('projects_new_project_card');
const Key _audioEditorScreenKey = Key('audio_editor_screen');
const Key _editorBackButtonKey = Key('audio_editor_back_button');
const Key _projectSettingsButtonKey =
    Key('audio_editor_project_settings_button');
const Key _projectSettingsDialogKey = Key('project_settings_dialog');
const Key _projectSettingsNameFieldKey = Key('project_settings_name_field');
const Key _projectSettingsProducerCaptureSwitchKey =
    Key('project_settings_producer_capture_switch');
const Key _projectSettingsCloseButtonKey = Key('project_settings_close_button');
const Key _masterPluginsButtonKey = Key('audio_editor_master_plugins_button');
const Key _masterRackKey = Key('audio_editor_master_rack');
const Key _masterEffectsTabKey = ValueKey('master_tab_effects');
const Key _masterEffectsPanelKey = ValueKey('master_effects_panel');
const Key _projectsRenameDialogKey = ValueKey('projects_rename_dialog');
const Key _projectsRenameFieldKey = ValueKey('projects_rename_field');
const Key _projectsRenameSaveKey = ValueKey('projects_rename_save');
const Key _projectsDeleteDialogKey = ValueKey('projects_delete_dialog');
const Key _projectsDeleteConfirmKey = ValueKey('projects_delete_confirm');
const Key _addEffectKey = ValueKey('add_effect');
const Key _pitchShiftEffectTileKey = ValueKey('master_effect_Pitch Shift#1');
const Key _pitchShiftParamKey =
    ValueKey('master_param_0_pitch_shift_semitones');

Finder _semanticsIdentifier(String identifier) => find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.identifier == identifier,
      description: 'Semantics identifier $identifier',
    );

void _ignoreKnownEditorSemanticsAssertion() {
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains(
          'A SemanticsNode with action "increase" needs to be annotated',
        ) ||
        (message.contains("'package:flutter/src/rendering/object.dart'") &&
            message.contains("'node.built'"))) {
      return;
    }
    previousHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousHandler);
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 200),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out waiting for finder: $finder');
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 200),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
  fail('Timed out waiting for finder to disappear: $finder');
}

Future<void> _pumpFor(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 900),
  Duration step = const Duration(milliseconds: 100),
}) async {
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    await tester.pump(step);
    elapsed += step;
  }
}

String _projectToken(String name) => Uri.encodeComponent(name.trim());

Finder _projectTile(String name) =>
    find.byKey(ValueKey('project_tile_${_projectToken(name)}'));

Finder _projectEditButton(String name) =>
    find.byKey(ValueKey('project_edit_${_projectToken(name)}'));

Future<void> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(
    buildIntegrationTestApp(
      home: const SignedInShell(),
    ),
  );

  await _pumpUntilFound(tester, find.byKey(_projectsScreenKey));
}

Future<void> _openProjectFromList(
    WidgetTester tester, String projectName) async {
  final tileFinder = _projectTile(projectName);
  await _pumpUntilFound(tester, tileFinder,
      timeout: const Duration(seconds: 45));
  await tester.tap(tileFinder);
  await tester.pump();
  await _pumpUntilFound(
    tester,
    find.byKey(_audioEditorScreenKey),
    timeout: const Duration(seconds: 45),
  );
}

Future<void> _returnToProjectsFromEditor(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump(const Duration(milliseconds: 300));
  await _pumpUntilFound(
    tester,
    find.byKey(_projectsScreenKey),
    timeout: const Duration(seconds: 45),
  );
}

Future<void> _openMasterEffects(WidgetTester tester) async {
  await tester.tap(find.byKey(_masterPluginsButtonKey));
  await tester.pump();
  await _pumpUntilFound(tester, find.byKey(_masterRackKey));
  await tester.tap(find.byKey(_masterEffectsTabKey));
  await tester.pump();
  await _pumpUntilFound(tester, find.byKey(_masterEffectsPanelKey));
}

List<Map<String, dynamic>> _masterEffectsFromJson(Map<String, dynamic> json) {
  final master = (json['master'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  final effectsWrapper = (master['effects'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  return ((effectsWrapper['effects'] as List?) ?? const <dynamic>[])
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList(growable: false);
}

Uint8List _silentWavBytes({
  int sampleRate = 48000,
  int channels = 1,
  int bitsPerSample = 16,
  int durationMs = 1200,
}) {
  final samplesPerChannel = ((sampleRate * durationMs) / 1000).round();
  final bytesPerSample = bitsPerSample ~/ 8;
  final blockAlign = channels * bytesPerSample;
  final byteRate = sampleRate * blockAlign;
  final dataSize = samplesPerChannel * blockAlign;
  final buffer = Uint8List(44 + dataSize);
  final data = ByteData.sublistView(buffer);

  void writeAscii(int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      buffer[offset + i] = value.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + dataSize, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, byteRate, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataSize, Endian.little);
  return buffer;
}

Future<Directory> _createAudioFixtureProject({
  required String projectName,
}) async {
  final dir = await ProjectManager.createNewProjectDir(name: projectName);
  final audioFile =
      File(p.join(ProjectManager.audioDir(dir).path, 'fixture.wav'));
  await audioFile.writeAsBytes(_silentWavBytes(), flush: true);

  final project = await ProjectManager.readProjectJson(dir);
  project['rows'] = <Map<String, dynamic>>[
    <String, dynamic>{'name': 'Track 1', 'iconId': 0},
  ];
  project['tracks'] = <Map<String, dynamic>>[
    <String, dynamic>{
      'fileName': 'fixture.wav',
      'label': 'Fixture Audio',
      'rowIndex': 0,
      'offset': 0.0,
      'gain': 1.0,
    },
  ];
  project['rowStates'] = <Map<String, dynamic>>[
    <String, dynamic>{
      'row': 0,
      'gain': 1.0,
      'pan': 0.5,
      'volumeAutomation': <Map<String, dynamic>>[
        <String, dynamic>{'x': 0.0, 'volume': 1.0},
        <String, dynamic>{'x': 1200.0, 'volume': 1.0},
      ],
      'automationLanes': const <Map<String, dynamic>>[],
      'automationClips': const <Map<String, dynamic>>[],
    },
  ];

  await ProjectManager.writeProjectJson(dir, project);
  return dir;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await deleteAllProjects();
  });

  tearDown(() async {
    await deleteAllProjects();
  });

  testWidgets('signed-in shell shows projects screen', (tester) async {
    await _pumpShell(tester);

    expect(find.byKey(_projectsScreenKey), findsOneWidget);
    expect(find.byKey(_newProjectCardKey), findsOneWidget);
  });

  testWidgets('new project flow opens the audio editor', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(_newProjectCardKey));
    await tester.pump();

    await _pumpUntilFound(
      tester,
      find.byKey(_audioEditorScreenKey),
      timeout: const Duration(seconds: 45),
    );

    expect(find.byKey(_audioEditorScreenKey), findsOneWidget);
    final projects = await ProjectManager.listProjects();
    expect(projects.length, 1);
    await _returnToProjectsFromEditor(tester);
  });

  testWidgets('existing project opens from the list', (tester) async {
    const projectName = 'Integration Test Project';
    await ProjectManager.createNewProjectDir(name: projectName);

    await _pumpShell(tester);
    await _openProjectFromList(tester, projectName);

    expect(find.byKey(_audioEditorScreenKey), findsOneWidget);
    await _returnToProjectsFromEditor(tester);
  });

  testWidgets('project card rename and delete actions update the list',
      (tester) async {
    const originalName = 'Project Action Fixture';
    const renamedName = 'Project Action Fixture Renamed';
    await ProjectManager.createNewProjectDir(name: originalName);

    await _pumpShell(tester);
    await _pumpUntilFound(tester, _projectEditButton(originalName));

    await tester.tap(_projectEditButton(originalName));
    await _pumpFor(tester);
    await tester.tap(find.text('Rename'));
    await _pumpFor(tester);

    await _pumpUntilFound(tester, find.byKey(_projectsRenameDialogKey));
    await tester.enterText(find.byKey(_projectsRenameFieldKey), renamedName);
    await tester.tap(find.byKey(_projectsRenameSaveKey));
    await _pumpUntilGone(tester, find.byKey(_projectsRenameDialogKey));
    await _pumpUntilFound(
      tester,
      _projectTile(renamedName),
      timeout: const Duration(seconds: 45),
    );

    final renamedProjects = await ProjectManager.listProjects();
    expect(renamedProjects.length, 1);
    expect(renamedProjects.single.name, renamedName);

    await tester.tap(_projectEditButton(renamedName));
    await _pumpFor(tester);
    await tester.tap(find.text('Delete'));
    await _pumpFor(tester);

    await _pumpUntilFound(tester, find.byKey(_projectsDeleteDialogKey));
    await tester.tap(find.byKey(_projectsDeleteConfirmKey));
    await _pumpUntilGone(
      tester,
      _projectTile(renamedName),
      timeout: const Duration(seconds: 45),
    );

    final projects = await ProjectManager.listProjects();
    expect(projects, isEmpty);
  });

  testWidgets(
      'new project settings can rename and persist producer capture state',
      (tester) async {
    const renamedName = 'Release Confidence Flow';

    await _pumpShell(tester);
    await tester.tap(find.byKey(_newProjectCardKey));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(_audioEditorScreenKey),
      timeout: const Duration(seconds: 45),
    );

    await tester.tap(find.byKey(_projectSettingsButtonKey));
    await tester.pump();
    await _pumpUntilFound(tester, find.byKey(_projectSettingsDialogKey));

    await tester.enterText(
        find.byKey(_projectSettingsNameFieldKey), renamedName);
    final producerSwitchFinder =
        find.byKey(_projectSettingsProducerCaptureSwitchKey);
    await tester.ensureVisible(producerSwitchFinder);
    expect(tester.widget<Switch>(producerSwitchFinder).value, isFalse);
    await tester.tap(producerSwitchFinder);
    await _pumpFor(tester);
    expect(tester.widget<Switch>(producerSwitchFinder).value, isTrue);

    final closeButtonFinder = find.byKey(_projectSettingsCloseButtonKey);
    await tester.ensureVisible(closeButtonFinder);
    await tester.tap(closeButtonFinder);
    await _pumpUntilGone(tester, find.byKey(_projectSettingsDialogKey));

    await _returnToProjectsFromEditor(tester);
    await _pumpUntilFound(
      tester,
      _projectTile(renamedName),
      timeout: const Duration(seconds: 45),
    );

    final projects = await ProjectManager.listProjects();
    expect(projects.length, 1);
    expect(projects.single.name, renamedName);

    final savedJson = await ProjectManager.readProjectJson(projects.single.dir);
    final uiSettings = (savedJson['ui'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    expect(uiSettings['showProducerCaptureUi'], isTrue);

    await _openProjectFromList(tester, renamedName);
    await tester.tap(find.byKey(_projectSettingsButtonKey));
    await tester.pump();
    await _pumpUntilFound(tester, find.byKey(_projectSettingsDialogKey));

    final nameField =
        tester.widget<TextFormField>(find.byKey(_projectSettingsNameFieldKey));
    expect(nameField.initialValue, renamedName);
    expect(tester.widget<Switch>(producerSwitchFinder).value, isTrue);

    await tester.ensureVisible(closeButtonFinder);
    await tester.tap(closeButtonFinder);
    await _pumpUntilGone(tester, find.byKey(_projectSettingsDialogKey));
    await _returnToProjectsFromEditor(tester);
  });

  testWidgets(
      'audio routing launcher opens the sheet and preserves a pending name edit',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    const originalName = 'Routing Original';
    const renamedName = 'Routing Name Draft';
    final projectDir =
        await ProjectManager.createNewProjectDir(name: originalName);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        home: AudioEditorScreen(
          mode: 'edit',
          projectDir: projectDir,
          isProEntitled: true,
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(_audioEditorScreenKey),
      timeout: const Duration(seconds: 45),
    );
    await _pumpUntilFound(
      tester,
      _semanticsIdentifier('daw.project_settings'),
      timeout: const Duration(seconds: 45),
    );

    await tester.tap(_semanticsIdentifier('daw.project_settings'));
    await tester.pump();
    await _pumpUntilFound(tester, find.byKey(_projectSettingsNameFieldKey));
    await tester.enterText(
        find.byKey(_projectSettingsNameFieldKey), renamedName);

    final routingLauncher = _semanticsIdentifier('daw.audio_routing');
    await tester.ensureVisible(routingLauncher);
    await tester.tap(routingLauncher);
    await _pumpUntilGone(tester, find.byKey(_projectSettingsNameFieldKey));
    await _pumpUntilFound(tester, find.text('Audio Routing'));
    expect(find.text('Input'), findsWidgets);
    expect(find.text('Output'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await _pumpUntilGone(tester, find.text('Audio Routing'));

    final projects = await ProjectManager.listProjects();
    expect(projects.single.name, renamedName);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'master effects can be added edited bypassed and deleted across saves',
      (tester) async {
    const projectName = 'Master Effects Fixture';
    final projectDir =
        await _createAudioFixtureProject(projectName: projectName);

    await _pumpShell(tester);
    await _openProjectFromList(tester, projectName);
    await _openMasterEffects(tester);

    final addEffectFinder = find.descendant(
      of: find.byKey(_masterEffectsPanelKey),
      matching: find.byKey(_addEffectKey),
    );
    await _pumpUntilFound(tester, addEffectFinder);
    await tester.tap(addEffectFinder);
    await _pumpFor(tester);
    await _pumpUntilFound(tester, find.text('Pitch Shift'));
    await tester.tap(find.text('Pitch Shift').last);
    await _pumpFor(tester, duration: const Duration(seconds: 1));

    await _pumpUntilFound(tester, find.byKey(_pitchShiftEffectTileKey));
    await tester.tap(find.byKey(_pitchShiftEffectTileKey));
    await _pumpFor(tester);
    await _pumpUntilFound(tester, find.byKey(_pitchShiftParamKey));

    final semitonesFieldFinder = find.descendant(
      of: find.byKey(_pitchShiftParamKey),
      matching: find.byType(TextFormField),
    );
    await tester.tap(semitonesFieldFinder);
    await tester.enterText(semitonesFieldFinder, '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFor(tester, duration: const Duration(seconds: 1));

    await _returnToProjectsFromEditor(tester);
    final afterInsertJson = await ProjectManager.readProjectJson(projectDir);
    final afterInsertEffects = _masterEffectsFromJson(afterInsertJson);
    expect(afterInsertEffects.length, 1);
    expect(afterInsertEffects.single['effectId'], 'Pitch Shift');
    expect(afterInsertEffects.single['bypassed'], isFalse);
    final insertParams =
        (afterInsertEffects.single['params'] as Map).cast<String, dynamic>();
    expect((insertParams['Semitones'] as num).toDouble(), closeTo(5.0, 0.001));

    await _openProjectFromList(tester, projectName);
    await _openMasterEffects(tester);
    await _pumpUntilFound(tester, find.byKey(_pitchShiftEffectTileKey));

    final bypassSwitchFinder = find.descendant(
      of: find.byKey(_pitchShiftEffectTileKey),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(bypassSwitchFinder).value, isTrue);
    await tester.tap(bypassSwitchFinder);
    await _pumpFor(tester, duration: const Duration(seconds: 1));
    expect(tester.widget<Switch>(bypassSwitchFinder).value, isFalse);

    await _returnToProjectsFromEditor(tester);
    final afterBypassJson = await ProjectManager.readProjectJson(projectDir);
    final afterBypassEffects = _masterEffectsFromJson(afterBypassJson);
    expect(afterBypassEffects.length, 1);
    expect(afterBypassEffects.single['bypassed'], isTrue);

    await _openProjectFromList(tester, projectName);
    await _openMasterEffects(tester);
    await _pumpUntilFound(tester, find.byKey(_pitchShiftEffectTileKey));

    final deleteButtonFinder = find.descendant(
      of: find.byKey(_pitchShiftEffectTileKey),
      matching: find.byIcon(Icons.delete_outline),
    );
    await tester.tap(deleteButtonFinder);
    await _pumpFor(tester);
    await _pumpUntilFound(tester, find.text('Delete Effect?'));
    await tester.tap(find.text('Delete'));
    await _pumpFor(tester, duration: const Duration(seconds: 1));
    await _pumpUntilGone(tester, find.byKey(_pitchShiftEffectTileKey));

    await _returnToProjectsFromEditor(tester);
    final afterDeleteJson = await ProjectManager.readProjectJson(projectDir);
    final afterDeleteEffects = _masterEffectsFromJson(afterDeleteJson);
    expect(afterDeleteEffects, isEmpty);
  });
}
