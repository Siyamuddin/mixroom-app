import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/screens/audio_timeline_pro.dart';
import 'package:path/path.dart' as p;

import 'test_harness.dart';

const Key _audioEditorScreenKey = Key('audio_editor_screen');
const String _orphanMessage =
    'This automation clip is orphaned. Undo the plugin removal or re-add the plugin to relink it.';
const String _longAutomationLabel =
    'Ghost Comp #2 • Threshold • Very Long Automation Target Name For Integration Testing';

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 45),
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
  Duration timeout = const Duration(seconds: 45),
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

Uint8List _silentWavBytes({
  int sampleRate = 48000,
  int channels = 1,
  int bitsPerSample = 16,
  int durationMs = 2000,
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

Future<Directory> _createAutomationFixtureProject({
  required String projectName,
  required String clipLabel,
  String patternId = '',
}) async {
  final dir = await ProjectManager.createNewProjectDir(name: projectName);
  final audioFile =
      File(p.join(ProjectManager.audioDir(dir).path, 'fixture.wav'));
  await audioFile.writeAsBytes(_silentWavBytes(), flush: true);

  final project = await ProjectManager.readProjectJson(dir);
  final orphanTargetId =
      'fxid:${Uri.encodeComponent('ghost-comp#1')}:${Uri.encodeComponent('threshold')}';
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
    RowStateSnapshot(
      row: 0,
      gain: 1.0,
      pan: 0.5,
      volumeAutomation: <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: 1.0),
        AutomationPoint(x: 2000.0, volume: 1.0),
      ],
      automationLanes: const <AutomationLaneSnapshot>[],
      selectedAutomationTargetId: orphanTargetId,
      automationClips: <AutomationClipSnapshot>[
        AutomationClipSnapshot(
          id: 'fixture_orphan_clip',
          targetId: orphanTargetId,
          label: clipLabel,
          patternId: patternId,
          row: 0,
          lane: 0,
          startMs: 0.0,
          lengthMs: 1000.0,
          muted: false,
          points: <AutomationPoint>[
            AutomationPoint(x: 0.0, volume: 0.2),
            AutomationPoint(x: 1000.0, volume: 0.8),
          ],
        ),
      ],
    ).toJson(),
  ];

  await ProjectManager.writeProjectJson(dir, project);
  return dir;
}

Future<Offset> _automationClipPoint(
  WidgetTester tester, {
  String clipId = 'fixture_orphan_clip',
}) async {
  final finder = find.byKey(ValueKey('automation_clip_hit_$clipId'));
  await _pumpUntilFound(tester, finder);
  return tester.getCenter(finder);
}

Future<void> _pumpEditorForProject(
    WidgetTester tester, Directory projectDir) async {
  await tester.pumpWidget(
    buildIntegrationTestApp(
      home: AudioEditorScreen(
        mode: 'Pro',
        projectDir: projectDir,
        isProEntitled: true,
      ),
    ),
  );

  await _pumpUntilFound(tester, find.byKey(_audioEditorScreenKey));
  await _pumpUntilFound(tester, find.byType(AudioCanvasTimeline));
  await _pumpUntilGone(tester, find.byType(CircularProgressIndicator));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await deleteAllProjects();
  });

  tearDown(() async {
    await deleteAllProjects();
  });

  testWidgets(
      'shared automation clip menu shows full label and can make unique',
      (tester) async {
    final projectDir = await _createAutomationFixtureProject(
      projectName: 'Automation Shared Fixture',
      clipLabel: _longAutomationLabel,
      patternId: 'pattern_shared_threshold',
    );
    await _pumpEditorForProject(tester, projectDir);

    await tester.longPressAt(await _automationClipPoint(tester));
    await _pumpFor(tester);

    expect(
      find.byKey(const ValueKey('automation_clip_menu_header')),
      findsOneWidget,
    );
    expect(find.textContaining(_longAutomationLabel), findsOneWidget);
    expect(
      find.byKey(const ValueKey('automation_clip_menu_make_unique')),
      findsOneWidget,
    );
    expect(find.text('Orphaned automation target'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('automation_clip_menu_make_unique')));
    await _pumpFor(tester);

    await tester.longPressAt(await _automationClipPoint(tester));
    await _pumpFor(tester);

    expect(
      find.byKey(const ValueKey('automation_clip_menu_make_unique')),
      findsNothing,
    );
  });

  testWidgets(
      'double tapping an automation clip opens editor with full target name',
      (tester) async {
    final projectDir = await _createAutomationFixtureProject(
      projectName: 'Automation Editor Fixture',
      clipLabel: _longAutomationLabel,
      patternId: 'pattern_shared_threshold',
    );
    await _pumpEditorForProject(tester, projectDir);

    final point = await _automationClipPoint(tester);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(point);
    await _pumpFor(tester);

    expect(
        find.byKey(const ValueKey('automation_editor_popup')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('automation_editor_title')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('automation_editor_subtitle')),
      findsOneWidget,
    );
    expect(find.textContaining(_longAutomationLabel), findsWidgets);
  });

  testWidgets('opening an orphan automation target shows recovery guidance',
      (tester) async {
    final projectDir = await _createAutomationFixtureProject(
      projectName: 'Automation Orphan Fixture',
      clipLabel: _longAutomationLabel,
    );
    await _pumpEditorForProject(tester, projectDir);

    await tester.longPressAt(await _automationClipPoint(tester));
    await _pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('automation_clip_menu_reveal')));
    await _pumpFor(tester);

    expect(find.text(_orphanMessage), findsOneWidget);
  });
}
