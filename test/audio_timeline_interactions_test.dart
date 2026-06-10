import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
const double _kTrimHandleWidthPx = 14.0;
const double _kTrimHandleGapPx = 8.0;

Future<AudioTrack> _buildClip({
  int durationMs = _kClipDurationMsInt,
  int row = 0,
  int rowId = 1,
}) {
  return AudioTrack.create(
    file: File('test_audio.wav'),
    originalFile: File('test_audio.wav'),
    audioDuration: Duration(milliseconds: durationMs),
    trimStart: Duration.zero,
    trimEnd: Duration(milliseconds: durationMs),
    offset: 0.0,
    rowIndex: row,
    rowId: rowId,
    engineClipId: 1,
    label: 'Fixture Clip',
  );
}

Future<AudioTrack> _buildSamplerClip({
  int durationMs = _kClipDurationMsInt,
  int row = 0,
  int rowId = 1,
}) {
  return AudioTrack.create(
    file: File('test_sampler_render.wav'),
    originalFile: File('test_sampler_source.wav'),
    audioDuration: Duration(milliseconds: durationMs),
    trimStart: Duration.zero,
    trimEnd: Duration(milliseconds: durationMs),
    offset: 0.0,
    rowIndex: row,
    rowId: rowId,
    engineClipId: 2,
    label: 'Kick Sampler',
    clipKind: ClipKind.midi,
    instrumentId: 'sfz_asset:/tmp/kick.sfz',
    instrumentName: 'Kick Sampler',
    instrumentParams: const <String, double>{
      'sampleStartNorm': 0.0,
      'sampleEndNorm': 1.0,
    },
    midiNotes: <MidiNote>[
      MidiNote(
        id: 'sampler_note_test',
        pitch: 60,
        startBeat: 0.0,
        lengthBeats: 4.0,
        velocity: 0.92,
      ),
    ],
  );
}

Offset _clipCenter(
  WidgetTester tester, {
  double additionalDx = 0.0,
  double clipDurationMs = _kClipDurationMs,
}) {
  final topLeft = tester.getTopLeft(find.byType(AudioCanvasTimeline));
  final playheadPx = (_kTestTimelineWidth / 2.0) - _kHeaderWidth;
  final clipWidthPx = clipDurationMs * _kInitialPixelsPerMs;
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
        _kHeaderWidth +
            playheadPx -
            _kTrimHandleGapPx -
            (_kTrimHandleWidthPx / 2.0) +
            additionalDx,
        _kRulerHeight + 40.0,
      );
}

Offset _laneCenter(WidgetTester tester, {int row = 0}) {
  final topLeft = tester.getTopLeft(find.byType(AudioCanvasTimeline));
  return topLeft +
      Offset(
        _kHeaderWidth + 240.0,
        _kRulerHeight + (row * 80.0) + 40.0,
      );
}

Offset _magnetButtonCenter(WidgetTester tester) {
  final topLeft = tester.getTopLeft(find.byType(AudioCanvasTimeline));
  return topLeft + const Offset(21.0, 20.0);
}

Widget _buildHarness({
  required List<AudioTrack> clips,
  required Future<void> Function(int clipIndex, double newStartMs, int newRow)
      onMoveClipCommit,
  List<TimelineRow>? rowsOverride,
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
  VoidCallback? onCopyRowEffects,
  Future<void> Function(int row)? onPasteRowEffects,
  Future<void> Function(int row)? onClearRowEffects,
  Future<void> Function(int clipIndex)? onCreateSamplerFromClip,
  Future<void> Function(int clipIndex)? onDeleteClip,
  Future<void> Function(int clipIndex, double startMs)? onStartClipLoopPreview,
  Future<void> Function(int clipIndex, double startMs)? onSeekClipLoopPreview,
  Future<void> Function()? onStopClipLoopPreview,
  Future<void> Function()? onAddInstrumentLane,
  Future<void> Function()? onOpenCaptureDeck,
  Future<void> Function(int row)? onChangeInstrumentLane,
  Future<void> Function(int row, double timeMs)?
      onCreateMidiClipInInstrumentLane,
  bool Function(int clipIndex)? canReplaceSamplerSource,
  Future<void> Function(int clipIndex)? onReplaceSamplerSource,
  bool hasCopiedClip = false,
  bool Function(int row)? canPasteClipAtRow,
  bool hasCopiedRowEffects = false,
  void Function(bool magnetEnabled, int quantizeDivisionsPerBar)?
      onSnapSettingsChanged,
}) {
  final rows = rowsOverride ??
      <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Track 1', iconId: 0),
      ];
  final rowGain = List<double>.filled(rows.length, 1.0);
  final rowPan = List<double>.filled(rows.length, 0.5);
  final rowMuted = List<bool>.filled(rows.length, false);
  final rowSoloed = List<bool>.filled(rows.length, false);
  final rowVolumeAutomation = List<List<AutomationPoint>>.generate(
    rows.length,
    (_) => <AutomationPoint>[
      AutomationPoint(x: 0.0, volume: 1.0),
      AutomationPoint(x: 2000.0, volume: 1.0),
    ],
  );
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
          clipOverlapMode: 'off',
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
          onAddInstrumentLane: onAddInstrumentLane,
          onOpenCaptureDeck: onOpenCaptureDeck,
          onInsertRowAbove: (_) async {},
          onInsertRowBelow: (_) async {},
          onChangeInstrumentLane: onChangeInstrumentLane,
          onDeleteRow: (_) async {},
          onMoveRow: (_, __) async {},
          onRenameRow: (_, __) async {},
          onSetRowIcon: (_, __) async {},
          onMoveClipCommit: onMoveClipCommit,
          onTrimClip: (_, __, ___, {newStartMs}) {},
          onTrimClipCommit: onTrimClipCommit ??
              (_, __, ___, ____, _____, ______, {newStartMs}) {},
          transportClockListenable: ValueNotifier<Duration>(Duration.zero),
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
          onCreateSamplerFromClip: onCreateSamplerFromClip,
          canReplaceSamplerSource: canReplaceSamplerSource,
          onReplaceSamplerSource: onReplaceSamplerSource,
          onDeleteClip: onDeleteClip ?? (_) async {},
          onStartClipLoopPreview: onStartClipLoopPreview,
          onSeekClipLoopPreview: onSeekClipLoopPreview,
          onStopClipLoopPreview: onStopClipLoopPreview,
          hasCopiedClip: hasCopiedClip,
          canPasteClipAtRow: canPasteClipAtRow,
          onPasteClipAt: (_, __) async => false,
          onCopyClips: null,
          onDeleteClips: null,
          onCutClipAt: null,
          onOpenMidiClip: null,
          onCreateMidiClipInInstrumentLane: onCreateMidiClipInInstrumentLane,
          onStemSeparation: null,
          onSelectionChanged: onSelectionChanged,
          onLoopRegionChanged: null,
          onLoopToggle: null,
          mode: 'Pro',
          onPluginParamCommit: null,
          onPresetCommit: null,
          onCopyRowEffects: onCopyRowEffects,
          onPasteRowEffects: onPasteRowEffects,
          onClearRowEffects: onClearRowEffects,
          hasCopiedRowEffects: hasCopiedRowEffects,
          registerRowFxRefresher: null,
          registerRowFxPlaybackRefresher: null,
          onSnapSettingsChanged: onSnapSettingsChanged,
          meters: MeterBus(numRows: rows.length),
          getRowCompressorMeter: (_, __) async => const <double>[0.0, 0.0],
          getRowEqWaveform: (_, __, ___) async => const <double>[0.0, 0.0],
          getRowStereoScope: (_, __, ___) async => const <double>[0.0, 0.0],
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
  testWidgets('swiping an unselected clip does not select or move it',
      (tester) async {
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
    expect(
      selectionSnapshots.where((snapshot) => snapshot.isNotEmpty),
      isEmpty,
    );
  });

  testWidgets('clips require tap selection before a drag begins',
      (tester) async {
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
    await tester.tapAt(initialCenter);
    await tester.pumpAndSettle();

    expect(selectionSnapshots, isNotEmpty);
    expect(selectionSnapshots.last, <int>[0]);

    final selectedCenter = _clipCenter(tester, additionalDx: 60.0);
    await tester.dragFrom(selectedCenter, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(moveCommits, hasLength(1));
  });

  testWidgets('desktop clip drag snaps to grid when magnet is enabled',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final moveCommits = <double>[];
    final snapStates = <bool>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, newStartMs, __) async {
          moveCommits.add(newStartMs);
        },
        onSnapSettingsChanged: (enabled, _) {
          snapStates.add(enabled);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(_magnetButtonCenter(tester));
    await tester.pumpAndSettle();
    expect(snapStates.last, isTrue);

    final center = _clipCenter(tester);
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(center);
    await tester.pump();
    await gesture.moveBy(const Offset(155.0, 0.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(moveCommits, hasLength(1));
    expect(moveCommits.single, closeTo(1500.0, 0.01));
  });

  testWidgets('desktop alt clip drag overrides enabled snap grid',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final moveCommits = <double>[];
    final snapStates = <bool>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, newStartMs, __) async {
          moveCommits.add(newStartMs);
        },
        onSnapSettingsChanged: (enabled, _) {
          snapStates.add(enabled);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(_magnetButtonCenter(tester));
    await tester.pumpAndSettle();
    expect(snapStates.last, isTrue);

    final center = _clipCenter(tester);
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(center);
    await tester.pump();
    await gesture.moveBy(const Offset(155.0, 0.0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(moveCommits, hasLength(1));
    expect(moveCommits.single, closeTo(1550.0, 0.01));
    expect(snapStates.last, isTrue);
  });

  testWidgets('audio clips cannot be dropped onto instrument lanes',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Audio', iconId: 0),
      TimelineRow(
        rowId: 2,
        name: 'Keys',
        iconId: 1,
        kind: TimelineRowKind.instrument,
        instrumentId: 'piano',
        instrumentName: 'Piano',
      ),
    ];
    final clips = <AudioTrack>[await _buildClip()];
    final moveCommits = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        rowsOverride: rows,
        onMoveClipCommit: (_, __, newRow) async {
          moveCommits.add(newRow);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(_clipCenter(tester));
    await tester.pumpAndSettle();
    await tester.dragFrom(_clipCenter(tester), const Offset(0.0, 80.0));
    await tester.pumpAndSettle();

    expect(moveCommits, isEmpty);
  });

  testWidgets('tapping an empty instrument lane does not create a MIDI clip',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(
        rowId: 1,
        name: 'Keys',
        iconId: 1,
        kind: TimelineRowKind.instrument,
        instrumentId: 'piano',
        instrumentName: 'Piano',
      ),
    ];
    final createRequests = <Map<String, Object>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        onMoveClipCommit: (_, __, ___) async {},
        onCreateMidiClipInInstrumentLane: (row, timeMs) async {
          createRequests.add(<String, Object>{
            'row': row,
            'timeMs': timeMs,
          });
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(_laneCenter(tester));
    await tester.pumpAndSettle();

    expect(createRequests, isEmpty);
  });

  testWidgets('empty instrument lane menu can create a MIDI clip',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(
        rowId: 1,
        name: 'Keys',
        iconId: 1,
        kind: TimelineRowKind.instrument,
        instrumentId: 'piano',
        instrumentName: 'Piano',
      ),
    ];
    final createRequests = <Map<String, Object>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        onMoveClipCommit: (_, __, ___) async {},
        onCreateMidiClipInInstrumentLane: (row, timeMs) async {
          createRequests.add(<String, Object>{
            'row': row,
            'timeMs': timeMs,
          });
        },
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(_laneCenter(tester));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Add MIDI Region'), findsOneWidget);

    await tester.tap(find.text('Add MIDI Region'));
    await tester.pumpAndSettle();

    expect(createRequests, hasLength(1));
    expect(createRequests.single['row'], 0);
    expect(createRequests.single['timeMs'], isA<double>());
  });

  testWidgets('add row menu can create an instrument lane', (tester) async {
    var instrumentAdds = 0;

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        onMoveClipCommit: (_, __, ___) async {},
        onAddInstrumentLane: () async {
          instrumentAdds += 1;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Row'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instrument Lane'));
    await tester.pumpAndSettle();

    expect(instrumentAdds, 1);
  });

  testWidgets('invalid copied clips do not block instrument-lane MIDI menu',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(
        rowId: 1,
        name: 'Keys',
        iconId: 1,
        kind: TimelineRowKind.instrument,
        instrumentId: 'piano',
        instrumentName: 'Piano',
      ),
    ];

    final createRequests = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        hasCopiedClip: true,
        canPasteClipAtRow: (_) => false,
        onMoveClipCommit: (_, __, ___) async {},
        onCreateMidiClipInInstrumentLane: (row, _) async {
          createRequests.add(row);
        },
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(_laneCenter(tester));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add MIDI Region'));
    await tester.pumpAndSettle();

    expect(createRequests, <int>[0]);
  });

  testWidgets('selected audio clip popup exposes sampler action',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final samplerRequests = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
        onCreateSamplerFromClip: (clipIndex) async {
          samplerRequests.add(clipIndex);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(_clipCenter(tester));
    await tester.pumpAndSettle();

    final samplerAction =
        find.byKey(const ValueKey('selected_clip_popup_sampler'));
    expect(samplerAction, findsOneWidget);

    await tester.tap(samplerAction);
    await tester.pumpAndSettle();

    expect(samplerRequests, <int>[0]);
  });

  testWidgets('selected sampler clip popup exposes replace source action',
      (tester) async {
    final clips = <AudioTrack>[await _buildSamplerClip()];
    final rows = <TimelineRow>[
      TimelineRow(
        rowId: 1,
        name: 'Kick Sampler',
        iconId: 1,
        kind: TimelineRowKind.instrument,
        instrumentId: 'sfz_asset:/tmp/kick.sfz',
        instrumentName: 'Kick Sampler',
      ),
    ];
    final replaceRequests = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        rowsOverride: rows,
        onMoveClipCommit: (_, __, ___) async {},
        canReplaceSamplerSource: (clipIndex) => clipIndex == 0,
        onReplaceSamplerSource: (clipIndex) async {
          replaceRequests.add(clipIndex);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(_clipCenter(tester));
    await tester.pumpAndSettle();

    final replaceAction = find.byKey(
      const ValueKey('selected_clip_popup_replace_sampler_source'),
    );
    expect(replaceAction, findsOneWidget);

    await tester.tap(replaceAction);
    await tester.pumpAndSettle();

    expect(replaceRequests, <int>[0]);
  });

  testWidgets('desktop right-click deletes clips under the pointer',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final deleteRequests = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
        onDeleteClip: (clipIndex) async {
          deleteRequests.add(clipIndex);
        },
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(_clipCenter(tester));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(deleteRequests, <int>[0]);
  });

  testWidgets('desktop alt right-hold starts clip loop preview from pointer',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final starts = <double>[];
    final seeks = <double>[];
    var stops = 0;
    final deletes = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
        onDeleteClip: (clipIndex) async {
          deletes.add(clipIndex);
        },
        onStartClipLoopPreview: (clipIndex, startMs) async {
          expect(clipIndex, 0);
          starts.add(startMs);
        },
        onSeekClipLoopPreview: (clipIndex, startMs) async {
          expect(clipIndex, 0);
          seeks.add(startMs);
        },
        onStopClipLoopPreview: () async {
          stops += 1;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final center = _clipCenter(tester);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(center);
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(deletes, isEmpty);
    expect(starts, hasLength(1));
    expect(starts.single, closeTo(1000.0, 1.0));
    expect(seeks, isNotEmpty);
    expect(stops, 1);
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
    expect(
      selectionSnapshots.where((snapshot) => snapshot.isNotEmpty),
      isEmpty,
    );

    await tester.tapAt(_clipCenter(tester));
    await tester.pumpAndSettle();

    expect(selectionSnapshots, isNotEmpty);
    expect(selectionSnapshots.last, <int>[0]);

    final selectedHandle = _clipLeftHandle(tester);
    await tester.dragFrom(selectedHandle, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(trimCommits, hasLength(1));
  });

  testWidgets('tiny selected clips drag from the body instead of arming trim',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip(durationMs: 60)];
    final moveCommits = <double>[];
    final trimCommits = <Map<String, double?>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, newStartMs, __) async {
          moveCommits.add(newStartMs);
        },
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
      ),
    );
    await tester.pumpAndSettle();

    final clipCenter = _clipCenter(tester, clipDurationMs: 60.0);
    await tester.tapAt(clipCenter);
    await tester.pumpAndSettle();

    await tester.dragFrom(clipCenter, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(moveCommits, hasLength(1));
    expect(trimCommits, isEmpty);
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

  testWidgets('row effects menu exposes copy, paste, and clear actions',
      (tester) async {
    bool copied = false;
    int? pastedRow;
    int? clearedRow;

    await tester.pumpWidget(
      _buildHarness(
        clips: <AudioTrack>[await _buildClip()],
        onMoveClipCommit: (_, __, ___) async {},
        rowEffects: const <String>['EQ'],
        onCopyRowEffects: () {
          copied = true;
        },
        onPasteRowEffects: (row) async {
          pastedRow = row;
        },
        onClearRowEffects: (row) async {
          clearedRow = row;
        },
        hasCopiedRowEffects: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(24, _kRulerHeight + 40.0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Effects'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('row_effects_menu_0')));
    await tester.pumpAndSettle();

    final panelFinder = find.byKey(const ValueKey('row_effects_menu_panel_0'));
    expect(panelFinder, findsOneWidget);
    expect(
      find.descendant(of: panelFinder, matching: find.text('Copy effects')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panelFinder, matching: find.text('Paste effects')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panelFinder, matching: find.text('Clear effects')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const ValueKey('row_effects_menu_action_0_copy')));
    await tester.pumpAndSettle();
    expect(copied, isTrue);

    await tester.tap(find.byKey(const ValueKey('row_effects_menu_0')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('row_effects_menu_action_0_paste')));
    await tester.pumpAndSettle();
    expect(pastedRow, 0);

    await tester.tap(find.byKey(const ValueKey('row_effects_menu_0')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('row_effects_menu_action_0_clear')));
    await tester.pumpAndSettle();
    expect(clearedRow, 0);
  });

  testWidgets('trim handle zone stays inert while clip is unselected',
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

    expect(tester.widget<AnimatedOpacity>(popupFinder).opacity, 0.0);

    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tapAt(_clipCenter(tester));
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedOpacity>(popupFinder).opacity, 1.0);
    expect(find.byIcon(Icons.copy), findsOneWidget);
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
