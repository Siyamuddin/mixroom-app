import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/screens/audio_timeline_pro.dart';
import 'package:mixroom/widgets/effects_panel.dart';

const double _kTestTimelineWidth = 800.0;
const double _kTestTimelineHeight = 600.0;
const double _kHeaderWidth = 80.0;
const double _kRulerHeight = 40.0;
const double _kInitialPixelsPerMs = 0.1;
const double _kClipDurationMs = 2000.0;
const int _kClipDurationMsInt = 2000;

Future<AudioTrack> _buildClip() {
  return AudioTrack.create(
    file: File('test_audio.wav'),
    originalFile: File('test_audio.wav'),
    audioDuration: const Duration(milliseconds: _kClipDurationMsInt),
    trimStart: Duration.zero,
    trimEnd: const Duration(milliseconds: _kClipDurationMsInt),
    offset: 0.0,
    rowIndex: 0,
    rowId: 1,
    engineClipId: 1,
    label: 'Fixture Clip',
  );
}

Offset _clipCenter(WidgetTester tester, {double additionalDx = 0.0}) {
  final topLeft = tester.getTopLeft(find.byType(AudioCanvasTimeline));
  final playheadPx = (_kTestTimelineWidth / 2.0) - _kHeaderWidth;
  final clipWidthPx = _kClipDurationMs * _kInitialPixelsPerMs;
  return topLeft +
      Offset(
        _kHeaderWidth + playheadPx + (clipWidthPx / 2.0) + additionalDx,
        _kRulerHeight + 40.0,
      );
}

Offset _clipLeftHandle(WidgetTester tester, {double additionalDx = 0.0}) {
  final topLeft = tester.getTopLeft(find.byType(AudioCanvasTimeline));
  final playheadPx = (_kTestTimelineWidth / 2.0) - _kHeaderWidth;
  return topLeft +
      Offset(
        _kHeaderWidth + playheadPx + 6.0 + additionalDx,
        _kRulerHeight + 40.0,
      );
}

Widget _buildHarness({
  required List<AudioTrack> clips,
  required Future<void> Function(int clipIndex, double newStartMs, int newRow)
      onMoveClipCommit,
  void Function(
    int clipIndex,
    double newTrimStartMs,
    double newTrimEndMs,
    double oldTrimStartMs,
    double oldTrimEndMs,
    double originalStartMs, {
    double? newStartMs,
  })? onTrimClipCommit,
  void Function(List<int> selectedClipIndices, int primaryClipIndex)?
      onSelectionChanged,
  List<String> rowEffects = const <String>[],
  List<Map<String, dynamic>> automationTargets = const <Map<String, dynamic>>[],
  Map<String, List<AutomationClipSnapshot>> initialAutomationClipsByTarget =
      const <String, List<AutomationClipSnapshot>>{},
  String initialSelectedAutomationTargetId = 'volume',
}) {
  final rows = <TimelineRow>[
    TimelineRow(rowId: 1, name: 'Track 1', iconId: 0),
  ];
  final rowGain = <double>[1.0];
  final rowPan = <double>[0.5];
  final rowMuted = <bool>[false];
  final rowSoloed = <bool>[false];
  final rowVolumeAutomation = <List<AutomationPoint>>[
    <AutomationPoint>[
      AutomationPoint(x: 0.0, volume: 1.0),
      AutomationPoint(x: 2000.0, volume: 1.0),
    ],
  ];
  String selectedAutomationTargetId = initialSelectedAutomationTargetId;
  final automationPointsByTarget = <String, List<AutomationPoint>>{};
  final automationClipsByTarget = <String, List<AutomationClipSnapshot>>{
    for (final entry in initialAutomationClipsByTarget.entries)
      entry.key:
          entry.value.map((clip) => clip.copyWith()).toList(growable: false),
  };

  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: _kTestTimelineWidth,
        height: _kTestTimelineHeight,
        child: AudioCanvasTimeline(
          rows: rows,
          clips: clips,
          rowGain: rowGain,
          rowPan: rowPan,
          rowMuted: rowMuted,
          rowSoloed: rowSoloed,
          rowVolumeAutomation: rowVolumeAutomation,
          getAutomationTargetsForRow: (_) => automationTargets,
          getSelectedAutomationTargetId: (_) => selectedAutomationTargetId,
          setSelectedAutomationTargetId: (_, targetId) {
            selectedAutomationTargetId = targetId;
          },
          getAutomationPointsForTarget: (_, targetId) =>
              automationPointsByTarget[targetId] ?? const <AutomationPoint>[],
          setAutomationPointsForTarget: (_, targetId, points) {
            automationPointsByTarget[targetId] =
                points.map((point) => point.copy()).toList(growable: false);
          },
          getAutomationClipsForTarget: (_, targetId) =>
              automationClipsByTarget[targetId] ??
              const <AutomationClipSnapshot>[],
          setAutomationClipsForTarget: (_, targetId, clipsForTarget) {
            automationClipsByTarget[targetId] =
                clipsForTarget.map((clip) => clip.copyWith()).toList(
                      growable: false,
                    );
          },
          onAutomationTargetCommit: (_, __, ___, ____) {},
          onAutomationClipsCommit: null,
          onRevealAutomationTarget: null,
          getStartMs: (clip) => clip.offset,
          getDurationMs: (clip) => clip.audioDuration.inMilliseconds.toDouble(),
          getTimelineDurationMs: (clip) =>
              clip.trimEnd.inMilliseconds.toDouble() -
              clip.trimStart.inMilliseconds.toDouble(),
          getTrimStartMs: (clip) => clip.trimStart.inMilliseconds.toDouble(),
          getTrimEndMs: (clip) => clip.trimEnd.inMilliseconds.toDouble(),
          getFullDurationMs: (clip) =>
              clip.audioDuration.inMilliseconds.toDouble(),
          getPeaks: (_) => List<double>.filled(32, 0.35, growable: false),
          getY: (clip) => clip.y,
          onSelectRow: (_) {},
          recordingInProgress: false,
          onToggleExpanded: (_) {},
          onAddRow: () async {},
          onInsertRowAbove: (_) async {},
          onInsertRowBelow: (_) async {},
          onDeleteRow: (_) async {},
          onMoveRow: (_, __) async {},
          onRenameRow: (_, __) async {},
          onSetRowIcon: (_, __) async {},
          onMoveClipCommit: onMoveClipCommit,
          onTrimClip: (_, __, ___, {newStartMs}) {},
          onTrimClipCommit: onTrimClipCommit ??
              (_, __, ___, ____, _____, ______, {newStartMs}) {},
          playheadMs: 0.0,
          onScrubRequested: (_) {},
          isPlaying: false,
          maxDuration: const Duration(seconds: 30),
          bpm: 120.0,
          beatsPerBar: 4,
          isRecording: false,
          recordingRowIndex: null,
          recordingStartMs: 0.0,
          recordingPeaks: const <double>[],
          getRowEffects: (_) async => rowEffects,
          getRowEffectIds: (_) async => List<String>.generate(
            rowEffects.length,
            (index) => 'fx_$index',
            growable: false,
          ),
          getRowEffectBypassState: (_, __) async => false,
          insertRowEffect: (_, __) async {},
          removeRowEffect: (_, __, ___, ____) async {},
          reorderRowEffects: (_, __, ___) async {},
          setRowEffectBypassed: (_, __, ___) async {},
          getRowPluginParameters: (_, __) async =>
              const <Map<String, dynamic>>[],
          setRowEffectParam: (_, __, ___, ____) async {},
          scanPlugins: () async => const <Map<String, dynamic>>[],
          setTrackAutomationPoints: (_, __) async {},
          onAutomationCommit: (_, __, ___) {},
          setRowGain: (_, __) async {},
          onRowGainCommit: (_, __, ___) {},
          muteRow: (_, __) async {},
          soloRow: (_, __) async {},
          setRowPan: (_, __) async {},
          onRowPanCommit: (_, __, ___) {},
          setClipGain: (_, __) async {},
          onClipGainCommit: (_, __, ___) {},
          setClipPitch: (_, __) async {},
          onClipPitchCommit: (_, __, ___) {},
          onDisableClipTempoFollow: (_) async {},
          onAdjustClipToTempo: (_) async {},
          onStretchClipToTempoPreservePitch: (_) async {},
          onDetectClipTempoAndSetProjectTempo: (_) async {},
          onStretchClip: (_, __, {newStartMs}) {},
          onStretchClipCommit: (_) async {},
          onCopyClip: (_) {},
          onDeleteClip: (_) async {},
          hasCopiedClip: false,
          onPasteClipAt: (_, __) {},
          onCopyClips: null,
          onDeleteClips: null,
          onCutClipAt: null,
          onOpenMidiClip: null,
          onStemSeparation: null,
          onSelectionChanged: onSelectionChanged,
          onLoopRegionChanged: null,
          onLoopToggle: null,
          mode: 'Pro',
          onPluginParamCommit: null,
          onPresetCommit: null,
          registerRowFxRefresher: null,
          registerRowFxPlaybackRefresher: null,
          onSnapSettingsChanged: null,
          meters: MeterBus(numRows: 1),
          getRowCompressorMeter: (_, __) async => const <double>[0.0, 0.0],
          getRowEqWaveform: (_, __, ___) async => const <double>[0.0, 0.0],
          onExternalSampleDrop: null,
          onExternalSampleDragEntered: null,
          externalSampleDragActive: false,
          tutorialHighlighter: null,
          bottomDockInset: 0.0,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('clips require selection before a drag begins', (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final moveCommits = <double>[];
    final selectionSnapshots = <List<int>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, newStartMs, __) async {
          moveCommits.add(newStartMs);
        },
        onSelectionChanged: (selectedClipIndices, _) {
          selectionSnapshots.add(
            selectedClipIndices.toList(growable: false),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    final initialCenter = _clipCenter(tester);
    await tester.dragFrom(initialCenter, const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(moveCommits, isEmpty);
    expect(selectionSnapshots, isNotEmpty);
    expect(selectionSnapshots.last, <int>[0]);

    final selectedCenter = _clipCenter(tester, additionalDx: 60.0);
    await tester.dragFrom(selectedCenter, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(moveCommits, hasLength(1));
  });

  testWidgets('trim handles require selection before trim begins',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final trimCommits = <Map<String, double?>>[];
    final selectionSnapshots = <List<int>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
        onTrimClipCommit: (
          _,
          newTrimStartMs,
          newTrimEndMs,
          __,
          ___,
          ____, {
          newStartMs,
        }) {
          trimCommits.add(<String, double?>{
            'newTrimStartMs': newTrimStartMs,
            'newTrimEndMs': newTrimEndMs,
            'newStartMs': newStartMs,
          });
        },
        onSelectionChanged: (selectedClipIndices, _) {
          selectionSnapshots.add(
            selectedClipIndices.toList(growable: false),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    final initialHandle = _clipLeftHandle(tester);
    await tester.dragFrom(initialHandle, const Offset(0, 30));
    await tester.pumpAndSettle();

    expect(trimCommits, isEmpty);
    expect(selectionSnapshots, isNotEmpty);
    expect(selectionSnapshots.last, <int>[0]);

    final selectedHandle = _clipLeftHandle(tester);
    await tester.dragFrom(selectedHandle, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(trimCommits, hasLength(1));
  });

  testWidgets('pinch zoom does not commit a clip drag', (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final moveCommits = <double>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, newStartMs, __) async {
          moveCommits.add(newStartMs);
        },
      ),
    );
    await tester.pumpAndSettle();

    final center = _clipCenter(tester);
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    final first = await tester.startGesture(
      center + const Offset(-20, 0),
      pointer: 1,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    final second = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    await first.moveBy(const Offset(-70, 0));
    await second.moveBy(const Offset(10, 0));
    await tester.pump();

    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(moveCommits, isEmpty);
  });

  testWidgets('pinch zoom does not leave an unselected clip selected',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final selectionSnapshots = <List<int>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
        onSelectionChanged: (selectedClipIndices, _) {
          selectionSnapshots.add(
            selectedClipIndices.toList(growable: false),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    final center = _clipCenter(tester);
    final first = await tester.startGesture(
      center + const Offset(-20, 0),
      pointer: 1,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    final second = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    await first.moveBy(const Offset(-70, 0));
    await second.moveBy(const Offset(10, 0));
    await tester.pump();

    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    if (selectionSnapshots.isNotEmpty) {
      expect(selectionSnapshots.last, isEmpty);
    }
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('selected_clip_popup')),
          )
          .opacity,
      0.0,
    );
  });

  testWidgets('effects panel preloads offstage before effects tab is shown',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
        rowEffects: const <String>['EQ', 'Delay', 'Reverb'],
      ),
    );
    await tester.pumpAndSettle();

    const headerTap = Offset(24, _kRulerHeight + 40.0);
    await tester.tapAt(headerTap);
    await tester.pumpAndSettle();

    expect(find.byType(RowEffectsPanel, skipOffstage: false), findsOneWidget);
    expect(find.byType(RowEffectsPanel), findsNothing);

    await tester.tap(find.text('Effects'));
    await tester.pumpAndSettle();

    expect(find.byType(RowEffectsPanel), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'clip popup appears on trim-handle selection without waiting for tap up',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final popupFinder = find.byKey(const ValueKey('selected_clip_popup'));

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(_clipLeftHandle(tester));
    await tester.pump();

    expect(tester.widget<AnimatedOpacity>(popupFinder).opacity, 1.0);
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.copy), findsOneWidget);

    await tester.tapAt(_clipCenter(tester, additionalDx: 260.0));
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedOpacity>(popupFinder).opacity, 0.0);
  });

  testWidgets(
      'paint tool clip selection shows popup without waiting for tap up',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final popupFinder = find.byKey(const ValueKey('selected_clip_popup'));

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.near_me_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paint'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      _clipCenter(tester),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    expect(tester.widget<AnimatedOpacity>(popupFinder).opacity, 1.0);
    expect(find.byIcon(Icons.copy), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('automation tab opens point-lane editor for selected target',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    const targetId = 'fxid:test:mix';

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
        automationTargets: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': targetId,
            'label': 'Mix',
            'fullLabel': 'Delay Mix',
            'paramId': 'mix',
            'min': 0.0,
            'max': 1.0,
            'isVolume': false,
            'isOrphan': false,
          },
        ],
        initialSelectedAutomationTargetId: targetId,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(24, _kRulerHeight + 40.0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Automation'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('automation_panel')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('automation_panel_title')), findsOneWidget);
    expect(find.byKey(const ValueKey('automation_panel_subtitle')),
        findsOneWidget);
    expect(find.text('Delay Mix'), findsWidgets);
    expect(
      find.byKey(const ValueKey('automation_clip_hit_automation_fixture')),
      findsNothing,
    );
  });
}
