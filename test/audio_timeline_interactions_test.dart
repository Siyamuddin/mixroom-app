import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/helpers/tablet_daw_panel_layout.dart';
import 'package:mixroom/helpers/timeline_grid_policy.dart';
import 'package:mixroom/helpers/trackpad_touch_count.dart';
import 'package:mixroom/helpers/waveform_detail.dart';
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

void _setTestTargetPlatform(TargetPlatform? platform) {
  debugDefaultTargetPlatformOverride = platform;
  PlatformCapabilities.debugResetForCurrentPlatform();
}

Future<AudioTrack> _buildClip({
  int durationMs = _kClipDurationMsInt,
  int row = 0,
  int rowId = 1,
  int engineClipId = 1,
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
    engineClipId: engineClipId,
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

Future<AudioTrack> _buildMidiClip({
  int durationMs = _kClipDurationMsInt,
  int row = 0,
  int rowId = 1,
}) {
  return AudioTrack.create(
    file: File('test_midi_render.wav'),
    originalFile: File('test_midi_render.wav'),
    audioDuration: Duration(milliseconds: durationMs),
    trimStart: Duration.zero,
    trimEnd: Duration(milliseconds: durationMs),
    offset: 0.0,
    rowIndex: row,
    rowId: rowId,
    engineClipId: 3,
    label: 'MIDI Clip',
    clipKind: ClipKind.midi,
    instrumentId: 'sfz.vsco.upright_piano',
    instrumentName: 'Upright Piano',
    midiNotes: <MidiNote>[
      MidiNote(
        id: 'midi_note_test',
        pitch: 60,
        startBeat: 0.0,
        lengthBeats: 4.0,
        velocity: 0.9,
      ),
    ],
  );
}

Offset _clipCenter(
  WidgetTester tester, {
  double additionalDx = 0.0,
  double clipDurationMs = _kClipDurationMs,
  int row = 0,
  double rowHeight = 80.0,
}) {
  final topLeft = tester.getTopLeft(find.byType(AudioCanvasTimeline));
  final playheadPx = (_kTestTimelineWidth / 2.0) - _kHeaderWidth;
  final clipWidthPx = clipDurationMs * _kInitialPixelsPerMs;
  return topLeft +
      Offset(
        _kHeaderWidth + playheadPx + (clipWidthPx / 2.0) + additionalDx,
        _kRulerHeight + (row * rowHeight) + (rowHeight / 2.0),
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

Future<void> _sendTrackpadPanZoomUpdate(
  WidgetTester tester, {
  required Offset position,
  required Offset panDelta,
  int pointer = 99,
}) async {
  final gesture = await tester.createGesture(
    pointer: pointer,
    kind: PointerDeviceKind.trackpad,
  );
  await gesture.panZoomStart(position);
  await tester.pump();
  await gesture.panZoomUpdate(position, pan: panDelta);
  await tester.pump();
  await gesture.panZoomEnd();
  await tester.pump();
}

Future<void> _openRowHeaderMenu(WidgetTester tester, int row) async {
  final headerRect = tester.getRect(
    find.byKey(ValueKey('timeline_row_header_$row')),
  );
  await tester.longPressAt(headerRect.centerLeft + const Offset(22, 0));
  await tester.pumpAndSettle();
}

CustomPainter _timelineClipPainter(WidgetTester tester) {
  for (final customPaint in tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(AudioCanvasTimeline),
      matching: find.byType(CustomPaint),
    ),
  )) {
    final painter = customPaint.painter;
    if (painter == null) continue;
    try {
      final indices = (painter as dynamic).visibleClipIndices;
      if (indices is List<int>) return painter;
    } on NoSuchMethodError {
      // Other timeline painters do not expose clip visibility.
    }
  }
  fail('Timeline painter with visible clip indices was not found.');
}

List<int> _paintedTimelineClipIndices(WidgetTester tester) {
  final indices = (_timelineClipPainter(tester) as dynamic).visibleClipIndices;
  return List<int>.of(indices as List<int>);
}

double _paintedTimelineVerticalScrollOffset(WidgetTester tester) {
  for (final customPaint in tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(AudioCanvasTimeline),
      matching: find.byType(CustomPaint),
    ),
  )) {
    final painter = customPaint.painter;
    if (painter == null) continue;
    try {
      final offset = (painter as dynamic).verticalScrollOffset;
      if (offset is double) return offset;
    } on NoSuchMethodError {
      // Other timeline painters do not expose vertical scroll state.
    }
  }
  fail('Timeline painter with vertical scroll state was not found.');
}

ScrollController _timelineVerticalScrollController(WidgetTester tester) {
  final candidates = tester
      .widgetList<SingleChildScrollView>(
        find.descendant(
          of: find.byType(AudioCanvasTimeline),
          matching: find.byType(SingleChildScrollView),
        ),
      )
      .where(
        (scrollView) =>
            scrollView.scrollDirection == Axis.vertical &&
            scrollView.controller?.hasClients == true,
      )
      .map((scrollView) => scrollView.controller!)
      .toList(growable: false);
  if (candidates.isEmpty) {
    fail('Timeline vertical scroll controller was not found.');
  }
  candidates.sort(
    (a, b) => b.position.maxScrollExtent.compareTo(a.position.maxScrollExtent),
  );
  return candidates.first;
}

double _instrumentLanePopupOpacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(
        find.byKey(const ValueKey('instrument_lane_region_popup')),
      )
      .opacity;
}

Future<void> _openInstrumentLaneMenu(
  WidgetTester tester,
  Offset position,
) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.down(position);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _desktopDoubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(kDoubleTapMinTime);
  await tester.tapAt(position);
  await tester.pumpAndSettle();
}

Offset _desktopClipCenter(WidgetTester tester) {
  final timelineFinder = find.byType(AudioCanvasTimeline);
  final topLeft = tester.getTopLeft(timelineFinder);
  final timeline = tester.widget<AudioCanvasTimeline>(timelineFinder);
  final headerWidth = timeline.useTabletDawLayout
      ? (timeline.tabletSidePanelWidth ??
          TabletDawPanelLayout.leftExpandedWidth)
      : _kHeaderWidth;
  final clipWidthPx = _kClipDurationMs * _kInitialPixelsPerMs;
  return topLeft +
      Offset(
        headerWidth + (clipWidthPx / 2.0),
        _kRulerHeight + 40.0,
      );
}

Offset _tabletHeaderGainPoint(WidgetTester tester, int row) {
  final rect = tester.getRect(
    find.byKey(ValueKey('timeline_tablet_row_gain_$row')),
  );
  return rect.centerRight - const Offset(6, 0);
}

Widget _buildHarness({
  required List<AudioTrack> clips,
  required Future<void> Function(int clipIndex, double newStartMs, int newRow)
      onMoveClipCommit,
  AudioCanvasTimelineController? controller,
  List<TimelineRow>? rowsOverride,
  List<TrackGroup>? trackGroupsOverride,
  void Function(
    int clipIndex,
    double newTrimStartMs,
    double newTrimEndMs,
    double oldTrimStartMs,
    double oldTrimEndMs,
    double originalStartMs, {
    double? newStartMs,
  })? onTrimClipCommit,
  void Function(int row)? onSelectRow,
  void Function(
    List<int> selectedClipIndices,
    int primaryClipIndex,
    TimelineSelectionChangeOrigin origin,
  )?
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
  Future<void> Function(int row)? onDeleteRow,
  Future<void> Function(int clipIndex, double startMs)? onStartClipLoopPreview,
  Future<void> Function(int clipIndex, double startMs)? onSeekClipLoopPreview,
  Future<void> Function()? onStopClipLoopPreview,
  Future<void> Function()? onAddInstrumentLane,
  Future<void> Function()? onOpenCaptureDeck,
  Future<void> Function()? onGroupRowsPressed,
  Future<void> Function(int row)? onChangeInstrumentLane,
  Future<void> Function(int row, double timeMs)?
      onCreateMidiClipInInstrumentLane,
  void Function(int clipIndex)? onOpenMidiClip,
  void Function(int clipIndex)? onOpenAudioClipOptionsPanel,
  void Function(int clipIndex)? onCopyClip,
  void Function(List<int> clipIndices)? onCopyClips,
  Future<bool> Function(int row, double timeMs)? onPasteClipAt,
  Future<bool> Function(List<int> clipIndices, double pasteStartMs)?
      onStepDuplicateClips,
  VoidCallback? onClearCopiedClip,
  Future<void> Function(int row, bool muted)? onMuteRow,
  Future<void> Function(int row, bool soloed)? onSoloRow,
  List<bool>? rowMutedOverride,
  List<bool>? rowSoloedOverride,
  Future<void> Function(int row, double gain)? onSetRowGain,
  void Function(int row, double oldGain, double newGain)? onRowGainCommit,
  Future<void> Function(int row, double pan)? onSetRowPan,
  void Function(int row, double oldPan, double newPan)? onRowPanCommit,
  Future<void> Function(int row, int color)? onSetRowColor,
  Future<void> Function(int row, String pathOrName)? onInsertRowEffect,
  Future<void> Function(
    int row,
    int effectIndex,
    String name,
    bool applyingPreset,
  )? onRemoveRowEffect,
  Future<void> Function(int row, int from, int to)? onReorderRowEffects,
  Future<void> Function(int row, int effectIndex, bool bypass)?
      onSetRowEffectBypassed,
  Future<void> Function(
    int row,
    int effectIndex,
    String paramId,
    dynamic value,
  )? onSetRowEffectParam,
  Future<void> Function(
    int row,
    int effectIndex,
    String paramId,
    dynamic oldValue,
    dynamic newValue,
  )? onPluginParamCommit,
  void Function(int row, int effectIndex)? onRowEffectSelected,
  Future<void> Function(List<int> rows)? onCreateRowGroup,
  Future<void> Function(int row)? onRemoveRowFromGroup,
  Future<void> Function(String groupId)? onToggleRowGroupCollapsed,
  Future<void> Function(String groupId, String name)? onRenameRowGroup,
  bool rowGroupingSelectionMode = false,
  Set<int> groupingSelectedRows = const <int>{},
  void Function(int row)? onToggleGroupingRowSelection,
  bool useTabletDawLayout = false,
  bool allowMultipleExpandedRows = true,
  bool expandRowsOnTrackSelect = true,
  int clipTopologyRevision = -1,
  int selectedClipIndex = -1,
  List<int> selectedClipIndices = const <int>[],
  bool Function(int clipIndex)? canReplaceSamplerSource,
  Future<void> Function(int clipIndex)? onReplaceSamplerSource,
  bool hasCopiedClip = false,
  bool Function(int row)? canPasteClipAtRow,
  bool hasCopiedRowEffects = false,
  void Function(
    bool magnetEnabled,
    TimelineGridMode gridMode,
    int fixedQuantizeDivisionsPerBar,
  )? onSnapSettingsChanged,
  ValueNotifier<Duration>? transportClockListenable,
  void Function(double ms)? onScrubRequested,
  bool isPlaying = false,
  bool loopEnabled = false,
  int loopStartMs = 0,
  int loopEndMs = 0,
  VoidCallback? onTutorialTimelineScrolled,
  VoidCallback? onTutorialTimelineZoomed,
  ValueChanged<WaveformDetailViewport>? onWaveformDetailViewportSettled,
}) {
  final rows = rowsOverride ??
      <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Track 1', iconId: 0),
      ];
  final rowGain = List<double>.filled(rows.length, 1.0);
  final rowPan = List<double>.filled(rows.length, 0.5);
  final rowMuted = rowMutedOverride ?? List<bool>.filled(rows.length, false);
  final rowSoloed = rowSoloedOverride ?? List<bool>.filled(rows.length, false);
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
          controller: controller,
          allowMultipleExpandedRows: allowMultipleExpandedRows,
          expandRowsOnTrackSelect: expandRowsOnTrackSelect,
          rows: rows,
          trackGroups: trackGroupsOverride ?? const <TrackGroup>[],
          clips: clips,
          clipTopologyRevision: clipTopologyRevision,
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
          onWaveformDetailViewportSettled: onWaveformDetailViewportSettled,
          getY: (clip) => clip.y,
          onSelectRow: onSelectRow ?? (_) {},
          recordingInProgress: false,
          onToggleExpanded: (_) {},
          onAddRow: () async {},
          onAddInstrumentLane: onAddInstrumentLane,
          onOpenCaptureDeck: onOpenCaptureDeck,
          onGroupRowsPressed: onGroupRowsPressed,
          onInsertRowAbove: (_) async {},
          onInsertRowBelow: (_) async {},
          onChangeInstrumentLane: onChangeInstrumentLane,
          onDeleteRow: onDeleteRow ?? (_) async {},
          onMoveRow: (_, __) async {},
          onRenameRow: (_, __) async {},
          onRenameRowGroup: onRenameRowGroup,
          onSetRowIcon: (_, __) async {},
          onSetRowColor: onSetRowColor,
          onCreateRowGroup: onCreateRowGroup,
          onRemoveRowFromGroup: onRemoveRowFromGroup,
          onToggleRowGroupCollapsed: onToggleRowGroupCollapsed,
          rowGroupingSelectionMode: rowGroupingSelectionMode,
          groupingSelectedRows: groupingSelectedRows,
          onToggleGroupingRowSelection: onToggleGroupingRowSelection,
          onMoveClipCommit: onMoveClipCommit,
          onTrimClip: (_, __, ___, {newStartMs}) {},
          onTrimClipCommit: onTrimClipCommit ??
              (_, __, ___, ____, _____, ______, {newStartMs}) {},
          transportClockListenable: transportClockListenable ??
              ValueNotifier<Duration>(Duration.zero),
          onScrubRequested: onScrubRequested ?? (_) {},
          isPlaying: isPlaying,
          maxDuration: const Duration(seconds: 30),
          bpm: 120.0,
          beatsPerBar: 4,
          selectedClipIndex: selectedClipIndex,
          selectedClipIndices: selectedClipIndices,
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
          insertRowEffect: onInsertRowEffect ?? (_, __) async {},
          removeRowEffect: onRemoveRowEffect ?? (_, __, ___, ____) async {},
          reorderRowEffects: onReorderRowEffects ?? (_, __, ___) async {},
          setRowEffectBypassed: onSetRowEffectBypassed ?? (_, __, ___) async {},
          getRowPluginParameters: (_, __) async =>
              const <Map<String, dynamic>>[],
          setRowEffectParam: onSetRowEffectParam ?? (_, __, ___, ____) async {},
          scanPlugins: () async => const <Map<String, dynamic>>[],
          setTrackAutomationPoints: (_, __) async {},
          onAutomationCommit: (_, __, ___) {},
          setRowGain: onSetRowGain ?? (_, __) async {},
          onRowGainCommit: onRowGainCommit ?? (_, __, ___) {},
          muteRow: onMuteRow ?? (_, __) async {},
          soloRow: onSoloRow ?? (_, __) async {},
          setRowPan: onSetRowPan ?? (_, __) async {},
          onRowPanCommit: onRowPanCommit ?? (_, __, ___) {},
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
          onCopyClip: onCopyClip ?? (_) {},
          onCreateSamplerFromClip: onCreateSamplerFromClip,
          canReplaceSamplerSource: canReplaceSamplerSource,
          onReplaceSamplerSource: onReplaceSamplerSource,
          onDeleteClip: onDeleteClip ?? (_) async {},
          onStartClipLoopPreview: onStartClipLoopPreview,
          onSeekClipLoopPreview: onSeekClipLoopPreview,
          onStopClipLoopPreview: onStopClipLoopPreview,
          hasCopiedClip: hasCopiedClip,
          canPasteClipAtRow: canPasteClipAtRow,
          onPasteClipAt: onPasteClipAt ?? (_, __) async => false,
          onClearCopiedClip: onClearCopiedClip,
          onCopyClips: onCopyClips,
          onStepDuplicateClips: onStepDuplicateClips,
          onDeleteClips: null,
          onCutClipAt: null,
          onOpenMidiClip: onOpenMidiClip,
          onOpenAudioClipOptionsPanel: onOpenAudioClipOptionsPanel,
          onCreateMidiClipInInstrumentLane: onCreateMidiClipInInstrumentLane,
          onStemSeparation: null,
          onSelectionChanged: onSelectionChanged,
          onLoopRegionChanged: null,
          onLoopToggle: null,
          loopEnabled: loopEnabled,
          loopStartMs: loopStartMs,
          loopEndMs: loopEndMs,
          mode: 'Pro',
          onPluginParamCommit: onPluginParamCommit,
          onPresetCommit: null,
          onRowEffectSelected: onRowEffectSelected,
          onCopyRowEffects: onCopyRowEffects,
          onPasteRowEffects: onPasteRowEffects,
          onClearRowEffects: onClearRowEffects,
          hasCopiedRowEffects: hasCopiedRowEffects,
          registerRowFxRefresher: null,
          registerRowFxPlaybackRefresher: null,
          onSnapSettingsChanged: onSnapSettingsChanged,
          onTutorialTimelineScrolled: onTutorialTimelineScrolled,
          onTutorialTimelineZoomed: onTutorialTimelineZoomed,
          meters: MeterBus(numRows: rows.length),
          getRowCompressorMeter: (_, __) async => const <double>[0.0, 0.0],
          getRowEqWaveform: (_, __, ___) async => const <double>[0.0, 0.0],
          getRowStereoScope: (_, __, ___) async => const <double>[0.0, 0.0],
          onExternalSampleDrop: null,
          onExternalSampleDragEntered: null,
          externalSampleDragActive: false,
          tutorialHighlighter: null,
          bottomDockInset: 0.0,
          useTabletDawLayout: useTabletDawLayout,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mobile timeline pan seeks only after the gesture ends',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.android);
    try {
      final scrubs = <double>[];
      await tester.pumpWidget(
        _buildHarness(
          clips: const <AudioTrack>[],
          onMoveClipCommit: (_, __, ___) async {},
          onScrubRequested: scrubs.add,
          isPlaying: true,
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        _laneCenter(tester),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();

      expect(scrubs, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(scrubs, hasLength(1));
      expect(scrubs.single, greaterThan(500.0));
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('tablet long-press enters touch multi-select mode',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.android);
    try {
      final first = await _buildClip();
      final second = await _buildClip();
      second.offset = 2200.0;
      final selectionSnapshots = <List<int>>[];
      final moveCommits = <int>[];

      await tester.pumpWidget(
        _buildHarness(
          clips: <AudioTrack>[first, second],
          useTabletDawLayout: true,
          onMoveClipCommit: (clipIndex, _, __) async {
            moveCommits.add(clipIndex);
          },
          onSelectionChanged: (selectedClipIndices, _, __) {
            selectionSnapshots.add(
              selectedClipIndices.toList(growable: false),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPressAt(_clipCenter(tester));
      await tester.pumpAndSettle();
      expect(selectionSnapshots.last, <int>[0]);

      await tester.tapAt(_clipCenter(tester, additionalDx: 220.0));
      await tester.pumpAndSettle();
      expect(selectionSnapshots.last, <int>[0, 1]);

      await tester.dragFrom(
        _clipCenter(tester, additionalDx: 220.0),
        const Offset(40.0, 0.0),
      );
      await tester.pumpAndSettle();
      expect(moveCommits, <int>[0, 1]);
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets(
      'tablet long-press box selects and highlights clips from the bottom',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.android);
    try {
      final top = await _buildClip(row: 0, rowId: 1, engineClipId: 1);
      final bottom = await _buildClip(row: 1, rowId: 2, engineClipId: 2);
      final selectionSnapshots = <List<int>>[];
      const tabletRowHeight = 84.0;

      await tester.pumpWidget(
        _buildHarness(
          clips: <AudioTrack>[top, bottom],
          rowsOverride: <TimelineRow>[
            TimelineRow(rowId: 1, name: 'Track 1', iconId: 0),
            TimelineRow(rowId: 2, name: 'Track 2', iconId: 0),
          ],
          useTabletDawLayout: true,
          onMoveClipCommit: (_, __, ___) async {},
          onSelectionChanged: (selectedClipIndices, _, __) {
            selectionSnapshots.add(
              selectedClipIndices.toList(growable: false),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final bottomCenter = _clipCenter(
        tester,
        row: 1,
        rowHeight: tabletRowHeight,
      );
      final topCenter = _clipCenter(
        tester,
        row: 0,
        rowHeight: tabletRowHeight,
      );

      final upGesture = await tester.startGesture(bottomCenter);
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await tester.pump();
      expect(
        selectionSnapshots.where((snapshot) => snapshot.contains(1)),
        isNotEmpty,
        reason: 'starting clip must stay selected when the box begins',
      );

      await upGesture.moveTo(topCenter);
      await tester.pump();
      expect(selectionSnapshots.last, <int>[0, 1]);

      await upGesture.up();
      await tester.pumpAndSettle();
      expect(selectionSnapshots.last, <int>[0, 1]);

      selectionSnapshots.clear();
      final downGesture = await tester.startGesture(topCenter);
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await tester.pump();
      await downGesture.moveTo(bottomCenter);
      await tester.pump();
      expect(selectionSnapshots.last, <int>[0, 1]);
      await downGesture.up();
      await tester.pumpAndSettle();
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('desktop and tablet row scaling keeps its default and reaches 150%',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    final semantics = tester.ensureSemantics();
    try {
      final clip = await _buildClip();
      await tester.pumpWidget(
        _buildHarness(
          clips: <AudioTrack>[clip],
          useTabletDawLayout: true,
          onMoveClipCommit: (_, __, ___) async {},
        ),
      );
      await tester.pumpAndSettle();

      final rowHeader =
          find.byKey(const ValueKey('timeline_tablet_row_header_0'));
      final heightControl = find.bySemanticsLabel('Rows scrollbar and height');
      final semanticsHeightControl =
          find.semantics.byLabel('Rows scrollbar and height');
      expect(tester.getSize(rowHeader).height, 84.0);
      expect(tester.getSemantics(heightControl).value, '100%');

      for (var i = 0; i < 8; i++) {
        tester.semantics.increase(semanticsHeightControl);
        await tester.pumpAndSettle();
      }

      expect(tester.getSize(rowHeader).height, 126.0);
      expect(tester.getSemantics(heightControl).value, '150%');
    } finally {
      semantics.dispose();
      _setTestTargetPlatform(null);
    }
  });

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
        onSelectionChanged: (selectedClipIndices, _, __) {
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
        onSelectionChanged: (selectedClipIndices, _, __) {
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

  testWidgets('desktop mouse drag picks up an unselected clip immediately',
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
        onSelectionChanged: (selectedClipIndices, _, __) {
          selectionSnapshots.add(
            selectedClipIndices.toList(growable: false),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // This test covers free movement, independent of the default snap mode.
    await tester.tapAt(_magnetButtonCenter(tester));
    await tester.pumpAndSettle();

    final center = _clipCenter(tester);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(center);
    await tester.pump();
    await gesture.moveBy(const Offset(80.0, 0.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selectionSnapshots.where((snapshot) => snapshot.isNotEmpty).last,
        <int>[0]);
    expect(moveCommits, hasLength(1));
    expect(moveCommits.single, closeTo(800.0, 0.01));
  });

  testWidgets(
    'desktop three-finger trackpad drag starts a selection box on a clip',
    (tester) async {
      _setTestTargetPlatform(TargetPlatform.macOS);
      TrackpadTouchCount.debugTouchCount = 3;
      try {
        final clips = <AudioTrack>[
          await _buildClip(engineClipId: 1),
          await _buildClip(engineClipId: 2),
        ];
        clips[1].offset = 2200.0;
        final moveCommits = <int>[];
        final selectionSnapshots = <List<int>>[];

        await tester.pumpWidget(
          _buildHarness(
            clips: clips,
            onMoveClipCommit: (clipIndex, _, __) async {
              moveCommits.add(clipIndex);
            },
            onSelectionChanged: (selectedClipIndices, _, __) {
              selectionSnapshots.add(
                selectedClipIndices.toList(growable: false),
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(PlatformCapabilities.current.isDesktop, isTrue);
        expect(TrackpadTouchCount.current, 3);

        final start = _clipCenter(tester);
        final end = start + const Offset(-400.0, 0.0);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
        );
        await gesture.down(start);
        await tester.pump();
        await gesture.moveTo(end);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(moveCommits, isEmpty);
        expect(
          selectionSnapshots.where((snapshot) => snapshot.length >= 2),
          isNotEmpty,
          reason: 'three-finger drag should box-select, snapshots=$selectionSnapshots',
        );
        expect(selectionSnapshots.last.toSet(), <int>{0, 1});
      } finally {
        TrackpadTouchCount.debugReset();
        _setTestTargetPlatform(null);
      }
    },
  );

  testWidgets(
    'desktop cmd-click adds each clip instead of skipping earlier clips',
    (tester) async {
      _setTestTargetPlatform(TargetPlatform.macOS);
      try {
        final clips = <AudioTrack>[
          await _buildClip(engineClipId: 1),
          await _buildClip(engineClipId: 2),
        ];
        clips[1].offset = 2200.0;
        final moveCommits = <int>[];
        final selectionSnapshots = <List<int>>[];

        await tester.pumpWidget(
          _buildHarness(
            clips: clips,
            onMoveClipCommit: (clipIndex, _, __) async {
              moveCommits.add(clipIndex);
            },
            onSelectionChanged: (selectedClipIndices, _, __) {
              selectionSnapshots.add(
                selectedClipIndices.toList(growable: false),
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(PlatformCapabilities.current.isDesktop, isTrue);

        final topLeft = tester.getTopLeft(find.byType(AudioCanvasTimeline));
        final firstClipCenter = topLeft +
            Offset(
              _kHeaderWidth + (1000.0 * _kInitialPixelsPerMs),
              _kRulerHeight + 46.0,
            );
        final secondClipCenter = topLeft +
            Offset(
              _kHeaderWidth + (3200.0 * _kInitialPixelsPerMs),
              _kRulerHeight + 46.0,
            );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        for (final position in <Offset>[firstClipCenter, secondClipCenter]) {
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
            buttons: kPrimaryMouseButton,
          );
          await gesture.down(position);
          await tester.pump();
          await gesture.up();
          await tester.pump();
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        expect(moveCommits, isEmpty);
        expect(
          selectionSnapshots.last.toSet(),
          <int>{0, 1},
          reason: 'cmd-click should keep both clips, snapshots=$selectionSnapshots',
        );
      } finally {
        _setTestTargetPlatform(null);
      }
    },
  );

  testWidgets(
    'desktop cmd-drag on a clip still starts a selection box',
    (tester) async {
      _setTestTargetPlatform(TargetPlatform.macOS);
      try {
        final clips = <AudioTrack>[
          await _buildClip(engineClipId: 1),
          await _buildClip(engineClipId: 2),
        ];
        clips[1].offset = 2200.0;
        final moveCommits = <int>[];
        final selectionSnapshots = <List<int>>[];

        await tester.pumpWidget(
          _buildHarness(
            clips: clips,
            onMoveClipCommit: (clipIndex, _, __) async {
              moveCommits.add(clipIndex);
            },
            onSelectionChanged: (selectedClipIndices, _, __) {
              selectionSnapshots.add(
                selectedClipIndices.toList(growable: false),
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        final start = _clipCenter(tester);
        final end = start + const Offset(-400.0, 0.0);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
        );
        await gesture.down(start);
        await tester.pump();
        await gesture.moveTo(end);
        await tester.pump();
        await gesture.up();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        expect(moveCommits, isEmpty);
        expect(
          selectionSnapshots.where((snapshot) => snapshot.length >= 2),
          isNotEmpty,
          reason: 'cmd-drag should box-select, snapshots=$selectionSnapshots',
        );
        expect(selectionSnapshots.last.toSet(), <int>{0, 1});
      } finally {
        _setTestTargetPlatform(null);
      }
    },
  );

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
        onSnapSettingsChanged: (enabled, _, __) {
          snapStates.add(enabled);
        },
      ),
    );
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

  testWidgets('adaptive grid follows timeline zoom without parent churn',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final clips = <AudioTrack>[await _buildClip()];
      final controller = AudioCanvasTimelineController();
      final snapSettings = <(bool, TimelineGridMode, int)>[];
      final moveCommits = <double>[];
      final detailViewports = <WaveformDetailViewport>[];

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          controller: controller,
          onMoveClipCommit: (_, newStartMs, __) async {
            moveCommits.add(newStartMs);
          },
          onSnapSettingsChanged: (enabled, mode, fixedDivisions) {
            snapSettings.add((enabled, mode, fixedDivisions));
          },
          onWaveformDetailViewportSettled: detailViewports.add,
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.topControlsState.gridMode, TimelineGridMode.adaptive);
      expect(controller.topControlsState.quantizeDivisionsPerBar, 4);
      expect(snapSettings, <(bool, TimelineGridMode, int)>[
        (true, TimelineGridMode.adaptive, 4),
      ]);

      final center = _desktopClipCenter(tester);
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, -2000),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 181));

      expect(controller.topControlsState.gridMode, TimelineGridMode.adaptive);
      expect(controller.topControlsState.quantizeDivisionsPerBar, 512);
      expect(snapSettings, hasLength(1));
      expect(detailViewports.last.pixelsPerMs, 8.0);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.down(center);
      await tester.pump();
      await gesture.moveBy(const Offset(70, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(moveCommits, hasLength(1));
      expect(moveCommits.single, closeTo(7.8125, 0.01));
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('waveform detail viewport waits for settled final zoom',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final clip = await _buildClip();
      final viewports = <WaveformDetailViewport>[];
      Widget buildTimeline() => _buildHarness(
        clips: <AudioTrack>[clip],
        onMoveClipCommit: (_, __, ___) async {},
        onWaveformDetailViewportSettled: viewports.add,
      );
      await tester.pumpWidget(buildTimeline());
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(buildTimeline());
      await tester.pump(const Duration(milliseconds: 121));
      expect(viewports, hasLength(1));
      expect(viewports.single.pixelsPerMs, _kInitialPixelsPerMs);
      expect(viewports.single.visibleClipIds, <String>[clip.clipId]);
      viewports.clear();

      final center = _desktopClipCenter(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, -600),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, -600),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 179));
      expect(viewports, isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      expect(viewports, hasLength(1));
      expect(
        viewports.single.pixelsPerMs,
        greaterThanOrEqualTo(kWaveformDetailMinimumPixelsPerMs),
      );
      expect(viewports.single.visibleClipIds, <String>[clip.clipId]);
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('fixed grid override stays fixed while timeline zooms',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final clips = <AudioTrack>[await _buildClip()];
      final controller = AudioCanvasTimelineController();
      final snapSettings = <(bool, TimelineGridMode, int)>[];

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          controller: controller,
          onMoveClipCommit: (_, __, ___) async {},
          onSnapSettingsChanged: (enabled, mode, fixedDivisions) {
            snapSettings.add((enabled, mode, fixedDivisions));
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPressAt(_magnetButtonCenter(tester));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
        const ValueKey('timeline_quantize_menu_4'),
      ));
      await tester.pumpAndSettle();

      expect(controller.topControlsState.gridMode, TimelineGridMode.fixed);
      expect(controller.topControlsState.quantizeDivisionsPerBar, 4);
      expect(snapSettings.last, (true, TimelineGridMode.fixed, 4));

      final center = _desktopClipCenter(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, -1000),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.topControlsState.gridMode, TimelineGridMode.fixed);
      expect(controller.topControlsState.quantizeDivisionsPerBar, 4);
    } finally {
      _setTestTargetPlatform(null);
    }
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
        onSnapSettingsChanged: (enabled, _, __) {
          snapStates.add(enabled);
        },
      ),
    );
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

  testWidgets('desktop cmd clip drag locks horizontal position',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Track 1', iconId: 0),
      TimelineRow(rowId: 2, name: 'Track 2', iconId: 0),
    ];
    final clips = <AudioTrack>[await _buildClip()];
    final moveCommits = <({double startMs, int row})>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        rowsOverride: rows,
        onMoveClipCommit: (_, newStartMs, newRow) async {
          moveCommits.add((startMs: newStartMs, row: newRow));
        },
      ),
    );
    await tester.pumpAndSettle();

    final center = _clipCenter(tester);
    final lockKey = Platform.isMacOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(lockKey);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(center);
    await tester.pump();
    await gesture.moveBy(const Offset(120.0, 80.0));
    await tester.pump();
    await gesture.up();
    await tester.sendKeyUpEvent(lockKey);
    await tester.pumpAndSettle();

    expect(moveCommits, hasLength(1));
    expect(moveCommits.single.startMs, closeTo(0.0, 0.01));
    expect(moveCommits.single.row, 1);
  });

  testWidgets('desktop cmd trackpad scroll zooms without vertical movement',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final rows = List<TimelineRow>.generate(
        12,
        (index) => TimelineRow(
          rowId: index + 1,
          name: 'Track ${index + 1}',
          iconId: 0,
        ),
      );
      final clips = <AudioTrack>[await _buildClip()];
      var zoomEvents = 0;

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          rowsOverride: rows,
          onMoveClipCommit: (_, __, ___) async {},
          onTutorialTimelineZoomed: () => zoomEvents++,
        ),
      );
      await tester.pumpAndSettle();

      final clipCenter = _clipCenter(tester);
      final rowHeaderTopBefore = tester
          .getTopLeft(find.byKey(const ValueKey('timeline_row_header_1')))
          .dy;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await _sendTrackpadPanZoomUpdate(
        tester,
        position: clipCenter,
        panDelta: const Offset(120.0, 0.0),
      );
      await tester.pumpAndSettle();

      expect(zoomEvents, 0);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('timeline_row_header_1')))
            .dy,
        closeTo(rowHeaderTopBefore, 0.01),
      );

      await _sendTrackpadPanZoomUpdate(
        tester,
        position: clipCenter,
        panDelta: const Offset(0.0, 120.0),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(zoomEvents, 1);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('timeline_row_header_1')))
            .dy,
        closeTo(rowHeaderTopBefore, 0.01),
      );
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('desktop shift trackpad scroll pans without vertical movement',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final rows = List<TimelineRow>.generate(
        12,
        (index) => TimelineRow(
          rowId: index + 1,
          name: 'Track ${index + 1}',
          iconId: 0,
        ),
      );
      final clips = <AudioTrack>[await _buildClip()];
      var scrollEvents = 0;

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          rowsOverride: rows,
          onMoveClipCommit: (_, __, ___) async {},
          onTutorialTimelineScrolled: () => scrollEvents++,
        ),
      );
      await tester.pumpAndSettle();

      final clipCenter = _clipCenter(tester);
      final rowHeaderTopBefore = tester
          .getTopLeft(find.byKey(const ValueKey('timeline_row_header_1')))
          .dy;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await _sendTrackpadPanZoomUpdate(
        tester,
        position: clipCenter,
        panDelta: const Offset(120.0, 0.0),
      );
      await tester.pumpAndSettle();

      expect(scrollEvents, 0);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('timeline_row_header_1')))
            .dy,
        closeTo(rowHeaderTopBefore, 0.01),
      );

      await _sendTrackpadPanZoomUpdate(
        tester,
        position: clipCenter,
        panDelta: const Offset(0.0, 120.0),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(scrollEvents, 1);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('timeline_row_header_1')))
            .dy,
        closeTo(rowHeaderTopBefore, 0.01),
      );
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('desktop horizontal trackpad scroll pans timeline',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final rows = List<TimelineRow>.generate(
        12,
        (index) => TimelineRow(
          rowId: index + 1,
          name: 'Track ${index + 1}',
          iconId: 0,
        ),
      );
      final clips = <AudioTrack>[await _buildClip()];
      var scrollEvents = 0;

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          rowsOverride: rows,
          onMoveClipCommit: (_, __, ___) async {},
          loopEnabled: true,
          loopStartMs: 1000,
          loopEndMs: 3000,
          onTutorialTimelineScrolled: () => scrollEvents++,
        ),
      );
      await tester.pumpAndSettle();

      final clipCenter = _clipCenter(tester);
      final loopRightBefore = tester
          .getRect(find.byKey(const ValueKey('timeline_loop_region')))
          .right;
      final rowHeaderTopBefore = tester
          .getTopLeft(find.byKey(const ValueKey('timeline_row_header_1')))
          .dy;

      await _sendTrackpadPanZoomUpdate(
        tester,
        position: clipCenter,
        panDelta: const Offset(-160.0, 80.0),
      );
      await tester.pump();

      expect(scrollEvents, 1);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('timeline_loop_region')))
            .right,
        lessThan(loopRightBefore),
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('timeline_row_header_1')))
            .dy,
        closeTo(rowHeaderTopBefore, 0.01),
      );
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('desktop horizontal trackpad scroll eases after release',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final rows = List<TimelineRow>.generate(
        12,
        (index) => TimelineRow(
          rowId: index + 1,
          name: 'Track ${index + 1}',
          iconId: 0,
        ),
      );
      final clips = <AudioTrack>[await _buildClip()];

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          rowsOverride: rows,
          onMoveClipCommit: (_, __, ___) async {},
          loopEnabled: true,
          loopStartMs: 1000,
          loopEndMs: 3000,
        ),
      );
      await tester.pumpAndSettle();

      final clipCenter = _clipCenter(tester);
      final loopRightBefore = tester
          .getRect(find.byKey(const ValueKey('timeline_loop_region')))
          .right;
      final gesture = await tester.createGesture(
        pointer: 101,
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(clipCenter);
      await tester.pump();
      await gesture.panZoomUpdate(
        clipCenter,
        pan: const Offset(-180.0, 20.0),
      );
      await tester.pump();

      final loopRightDuringGesture = tester
          .getRect(find.byKey(const ValueKey('timeline_loop_region')))
          .right;
      await gesture.panZoomEnd();
      await tester.pump(const Duration(milliseconds: 32));

      final loopRightAfterEase = tester
          .getRect(find.byKey(const ValueKey('timeline_loop_region')))
          .right;
      expect(loopRightDuringGesture, lessThan(loopRightBefore));
      expect(loopRightAfterEase, lessThan(loopRightDuringGesture));
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('desktop shift trackpad scroll eases after release',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final rows = List<TimelineRow>.generate(
        12,
        (index) => TimelineRow(
          rowId: index + 1,
          name: 'Track ${index + 1}',
          iconId: 0,
        ),
      );
      final clips = <AudioTrack>[await _buildClip()];

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          rowsOverride: rows,
          onMoveClipCommit: (_, __, ___) async {},
          loopEnabled: true,
          loopStartMs: 1000,
          loopEndMs: 3000,
        ),
      );
      await tester.pumpAndSettle();

      final clipCenter = _clipCenter(tester);
      final loopRightBefore = tester
          .getRect(find.byKey(const ValueKey('timeline_loop_region')))
          .right;
      final gesture = await tester.createGesture(
        pointer: 102,
        kind: PointerDeviceKind.trackpad,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await gesture.panZoomStart(clipCenter);
      await tester.pump();
      await gesture.panZoomUpdate(
        clipCenter,
        pan: const Offset(0.0, 180.0),
      );
      await tester.pump();

      final loopRightDuringGesture = tester
          .getRect(find.byKey(const ValueKey('timeline_loop_region')))
          .right;
      await gesture.panZoomEnd();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(milliseconds: 32));

      final loopRightAfterEase = tester
          .getRect(find.byKey(const ValueKey('timeline_loop_region')))
          .right;
      expect(loopRightDuringGesture, lessThan(loopRightBefore));
      expect(loopRightAfterEase, lessThan(loopRightDuringGesture));
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('desktop vertical trackpad scroll does not pan timeline',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final rows = List<TimelineRow>.generate(
        12,
        (index) => TimelineRow(
          rowId: index + 1,
          name: 'Track ${index + 1}',
          iconId: 0,
        ),
      );
      final clips = <AudioTrack>[await _buildClip()];
      var scrollEvents = 0;

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          rowsOverride: rows,
          onMoveClipCommit: (_, __, ___) async {},
          loopEnabled: true,
          loopStartMs: 1000,
          loopEndMs: 3000,
          onTutorialTimelineScrolled: () => scrollEvents++,
        ),
      );
      await tester.pumpAndSettle();

      final clipCenter = _clipCenter(tester);
      final loopRightBefore = tester
          .getRect(find.byKey(const ValueKey('timeline_loop_region')))
          .right;

      await _sendTrackpadPanZoomUpdate(
        tester,
        position: clipCenter,
        panDelta: const Offset(-80.0, 160.0),
      );
      await tester.pumpAndSettle();

      expect(scrollEvents, 0);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('timeline_loop_region')))
            .right,
        closeTo(loopRightBefore, 0.01),
      );
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('desktop tiny horizontal trackpad release does not ease',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final rows = List<TimelineRow>.generate(
        12,
        (index) => TimelineRow(
          rowId: index + 1,
          name: 'Track ${index + 1}',
          iconId: 0,
        ),
      );
      final clips = <AudioTrack>[await _buildClip()];

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          rowsOverride: rows,
          onMoveClipCommit: (_, __, ___) async {},
          loopEnabled: true,
          loopStartMs: 1000,
          loopEndMs: 3000,
        ),
      );
      await tester.pumpAndSettle();

      final clipCenter = _clipCenter(tester);
      final gesture = await tester.createGesture(
        pointer: 103,
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(clipCenter);
      await tester.pump();
      await gesture.panZoomUpdate(
        clipCenter,
        pan: const Offset(-18.0, 4.0),
      );
      await tester.pump();

      final loopRightDuringGesture = tester
          .getRect(find.byKey(const ValueKey('timeline_loop_region')))
          .right;
      await gesture.panZoomEnd();
      await tester.pump(const Duration(milliseconds: 48));

      final loopRightAfterRelease = tester
          .getRect(find.byKey(const ValueKey('timeline_loop_region')))
          .right;
      expect(loopRightAfterRelease, closeTo(loopRightDuringGesture, 0.01));
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('desktop scrollbar starts comfortable and shrinks when zoomed',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final controller = AudioCanvasTimelineController();
      final clips = <AudioTrack>[await _buildClip()];
      final detailViewports = <WaveformDetailViewport>[];

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          controller: controller,
          onMoveClipCommit: (_, __, ___) async {},
          onWaveformDetailViewportSettled: detailViewports.add,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump();

      var state = controller.horizontalScrollbarState;
      expect(state.visible, isTrue);
      expect(state.thumbWidth, greaterThanOrEqualTo(72.0));
      expect(controller.topControlsState.quantizeDivisionsPerBar, 4);

      controller.beginHorizontalScrollbarDrag(
        state.thumbLeft + state.thumbWidth - 2.0,
      );
      controller.dragHorizontalScrollbarBy(-320.0);
      controller.endHorizontalScrollbarDrag();
      await tester.pumpAndSettle();

      state = controller.horizontalScrollbarState;
      expect(state.thumbWidth, lessThan(72.0));
      expect(state.thumbWidth, greaterThanOrEqualTo(36.0));
      expect(controller.topControlsState.quantizeDivisionsPerBar, 32);

      controller.beginHorizontalScrollbarDrag(
        state.thumbLeft + state.thumbWidth - 2.0,
      );
      controller.dragHorizontalScrollbarBy(-2000.0);
      controller.endHorizontalScrollbarDrag();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 181));

      state = controller.horizontalScrollbarState;
      expect(state.thumbLeft.isFinite, isTrue);
      expect(state.thumbWidth.isFinite, isTrue);
      expect(state.thumbWidth, greaterThanOrEqualTo(36.0));
      expect(controller.topControlsState.quantizeDivisionsPerBar, 512);
      expect(detailViewports.last.pixelsPerMs, 8.0);
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('desktop scrollbar track press jumps then captures drag',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final controller = AudioCanvasTimelineController();
      final clips = <AudioTrack>[await _buildClip()];

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          controller: controller,
          onMoveClipCommit: (_, __, ___) async {},
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump();

      var state = controller.horizontalScrollbarState;
      controller.beginHorizontalScrollbarDrag(
        state.thumbLeft + state.thumbWidth - 2.0,
      );
      controller.dragHorizontalScrollbarBy(-320.0);
      controller.endHorizontalScrollbarDrag();
      await tester.pumpAndSettle();

      state = controller.horizontalScrollbarState;
      final trackWidth = state.viewportWidth - (state.endInset * 2.0);
      final trackTravel = trackWidth - state.thumbWidth;
      expect(trackTravel, greaterThan(80.0));

      final trackPressX =
          state.endInset + (trackTravel * 0.5) + (state.thumbWidth / 2.0);
      controller.jumpHorizontalScrollbarTo(trackPressX);
      controller.beginHorizontalScrollbarDrag(trackPressX);
      await tester.pump();

      final afterPress = controller.horizontalScrollbarState;
      expect(afterPress.dragging, isTrue);
      expect(afterPress.thumbLeft, greaterThan(state.thumbLeft));

      controller.dragHorizontalScrollbarBy(48.0);
      controller.endHorizontalScrollbarDrag();
      await tester.pump();

      final afterDrag = controller.horizontalScrollbarState;
      expect(afterDrag.dragging, isFalse);
      expect(afterDrag.thumbLeft, greaterThan(afterPress.thumbLeft));
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('external loop state renders the timeline loop region',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline_loop_region')), findsNothing);

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
        loopEnabled: true,
        loopStartMs: 0,
        loopEndMs: 4000,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('timeline_loop_region')), findsOneWidget);
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

    expect(find.byKey(const ValueKey('instrument_lane_region_popup')),
        findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Add MIDI Region'), findsOneWidget);

    await tester.tap(find.text('Add MIDI Region'));
    await tester.pumpAndSettle();

    expect(createRequests, hasLength(1));
    expect(createRequests.single['row'], 0);
    expect(createRequests.single['timeMs'], isA<double>());
  });

  testWidgets('instrument lane menu stays anchored after vertical scrolling',
      (tester) async {
    final rows = List<TimelineRow>.generate(
      10,
      (index) => TimelineRow(
        rowId: index + 1,
        name: 'Keys ${index + 1}',
        iconId: 1,
        kind: TimelineRowKind.instrument,
        instrumentId: 'piano',
        instrumentName: 'Piano',
      ),
    );

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        onMoveClipCommit: (_, __, ___) async {},
        onCreateMidiClipInInstrumentLane: (_, __) async {},
      ),
    );
    await tester.pumpAndSettle();

    final verticalController = _timelineVerticalScrollController(tester);
    const scrollOffset = 160.0;
    verticalController.jumpTo(scrollOffset);
    await tester.pumpAndSettle();

    final timelineTopLeft = tester.getTopLeft(find.byType(AudioCanvasTimeline));
    final tapPosition = timelineTopLeft +
        const Offset(
          _kHeaderWidth + 240.0,
          _kRulerHeight + (4 * 80.0) + 40.0 - scrollOffset,
        );
    await _openInstrumentLaneMenu(tester, tapPosition);

    final popupRect = tester.getRect(
      find.byKey(const ValueKey('instrument_lane_region_popup')),
    );
    expect(popupRect.bottom, moreOrLessEquals(tapPosition.dy - 8.0));
  });

  testWidgets('instrument lane menu dismisses on cancel interactions',
      (tester) async {
    final rows = List<TimelineRow>.generate(
      10,
      (index) => TimelineRow(
        rowId: index + 1,
        name: 'Keys ${index + 1}',
        iconId: 1,
        kind: TimelineRowKind.instrument,
        instrumentId: 'piano',
        instrumentName: 'Piano',
      ),
    );

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        onMoveClipCommit: (_, __, ___) async {},
        onCreateMidiClipInInstrumentLane: (_, __) async {},
      ),
    );
    await tester.pumpAndSettle();

    await _openInstrumentLaneMenu(tester, _laneCenter(tester));
    expect(_instrumentLanePopupOpacity(tester), 1.0);

    final timelineTopLeft = tester.getTopLeft(find.byType(AudioCanvasTimeline));
    await tester.tapAt(timelineTopLeft + const Offset(400.0, 20.0));
    await tester.pumpAndSettle();
    expect(_instrumentLanePopupOpacity(tester), 0.0);

    await _openInstrumentLaneMenu(tester, _laneCenter(tester));
    expect(_instrumentLanePopupOpacity(tester), 1.0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_instrumentLanePopupOpacity(tester), 0.0);

    await _openInstrumentLaneMenu(tester, _laneCenter(tester));
    expect(_instrumentLanePopupOpacity(tester), 1.0);

    _timelineVerticalScrollController(tester).jumpTo(80.0);
    await tester.pumpAndSettle();
    expect(_instrumentLanePopupOpacity(tester), 0.0);
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

  testWidgets('collapsed row group header shows folded child count',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 3, name: 'Keys', iconId: 0, groupId: 'band'),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2, 3],
        collapsed: true,
      ),
    ];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('collapsed row group child rows do not occupy lane geometry',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      TimelineRow(
        rowId: 3,
        name: 'Keys',
        iconId: 0,
        kind: TimelineRowKind.instrument,
      ),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
        collapsed: true,
      ),
    ];
    final createRequests = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        onMoveClipCommit: (_, __, ___) async {},
        onCreateMidiClipInInstrumentLane: (row, _) async {
          createRequests.add(row);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPressAt(_laneCenter(tester, row: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('instrument_lane_region_popup')),
        findsOneWidget);
    expect(find.text('Add MIDI Region'), findsOneWidget);

    await tester.tap(find.text('Add MIDI Region'));
    await tester.pumpAndSettle();

    expect(createRequests, <int>[2]);
  });

  testWidgets('collapsed row group paints a member clip summary without errors',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Guitar', iconId: 0, groupId: 'band'),
      TimelineRow(
        rowId: 2,
        name: 'Keys',
        iconId: 1,
        kind: TimelineRowKind.instrument,
        groupId: 'band',
      ),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
        collapsed: true,
      ),
    ];
    final audioClip = await _buildClip(row: 0, rowId: 1);
    final midiClip = await _buildSamplerClip(row: 1, rowId: 2);

    await tester.pumpWidget(
      _buildHarness(
        clips: <AudioTrack>[audioClip, midiClip],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('group header mute fans out to grouped rows only',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 3, name: 'Vocal', iconId: 0),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
        collapsed: true,
      ),
    ];
    final muteRequests = <MapEntry<int, bool>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        onMoveClipCommit: (_, __, ___) async {},
        onMuteRow: (row, muted) async {
          muteRequests.add(MapEntry<int, bool>(row, muted));
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('M').first);
    await tester.pumpAndSettle();

    expect(
      muteRequests.map((entry) => '${entry.key}:${entry.value}').toList(),
      <String>['0:true', '1:true'],
    );
  });

  testWidgets('group header solo fans out to grouped rows only',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 3, name: 'Vocal', iconId: 0),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
        collapsed: true,
      ),
    ];
    final soloRequests = <MapEntry<int, bool>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        onMoveClipCommit: (_, __, ___) async {},
        onSoloRow: (row, soloed) async {
          soloRequests.add(MapEntry<int, bool>(row, soloed));
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('S').first);
    await tester.pumpAndSettle();

    expect(
      soloRequests.map((entry) => '${entry.key}:${entry.value}').toList(),
      <String>['0:true', '1:true'],
    );
  });

  for (final useTabletLayout in <bool>[false, true]) {
    final layoutName = useTabletLayout ? 'tablet' : 'desktop';

    testWidgets(
      '$layoutName mute and solo callbacks own the shared row state',
      (tester) async {
        final rowMuted = <bool>[false];
        final rowSoloed = <bool>[false];
        final callbackObservations = <String>[];

        await tester.pumpWidget(
          _buildHarness(
            clips: const <AudioTrack>[],
            onMoveClipCommit: (_, __, ___) async {},
            useTabletDawLayout: useTabletLayout,
            rowMutedOverride: rowMuted,
            rowSoloedOverride: rowSoloed,
            onMuteRow: (row, muted) async {
              callbackObservations.add('mute:$row:${rowMuted[row]}->$muted');
              rowMuted[row] = muted;
            },
            onSoloRow: (row, soloed) async {
              callbackObservations.add('solo:$row:${rowSoloed[row]}->$soloed');
              rowSoloed[row] = soloed;
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('M').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('S').first);
        await tester.pumpAndSettle();

        expect(
          callbackObservations,
          <String>['mute:0:false->true', 'solo:0:false->true'],
        );
        expect(rowMuted, <bool>[true]);
        expect(rowSoloed, <bool>[true]);
      },
    );
  }

  testWidgets('row grouping mode toggles row headers without expanding rows',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0),
    ];
    final toggledRows = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        rowGroupingSelectionMode: true,
        groupingSelectedRows: const <int>{1},
        onToggleGroupingRowSelection: toggledRows.add,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('timeline_row_header_0')));
    await tester.pumpAndSettle();

    expect(toggledRows, <int>[0]);
    expect(find.text('Volume'), findsNothing);
  });

  testWidgets('tablet row grouping mode toggles tablet row headers',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0),
    ];
    final toggledRows = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        rowGroupingSelectionMode: true,
        groupingSelectedRows: const <int>{1},
        onToggleGroupingRowSelection: toggledRows.add,
        useTabletDawLayout: true,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('timeline_tablet_row_header_0')));
    await tester.pumpAndSettle();

    expect(toggledRows, <int>[0]);
    expect(find.text('Volume'), findsNothing);
  });

  testWidgets('tablet group folder toggles children without expanding header',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 3, name: 'Vocal', iconId: 0),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
      ),
    ];
    final toggledGroups = <String>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        useTabletDawLayout: true,
        onToggleRowGroupCollapsed: (groupId) async {
          toggledGroups.add(groupId);
        },
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    final headerRect = tester.getRect(
      find.byKey(const ValueKey('timeline_tablet_row_header_0')),
    );
    await tester.tapAt(headerRect.topLeft + const Offset(55, 40));
    await tester.pumpAndSettle();

    expect(toggledGroups, <String>['band']);
    expect(find.byKey(const ValueKey('expanded_row_1')), findsNothing);
    expect(find.text('Volume'), findsNothing);
  });

  testWidgets('tablet row selection allows multiple expanded rows by default',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0),
    ];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        useTabletDawLayout: true,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('timeline_tablet_row_header_0')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('timeline_tablet_row_header_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('expanded_row_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('expanded_row_2')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('escape collapses expanded timeline rows', (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0),
    ];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        useTabletDawLayout: true,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('timeline_tablet_row_header_0')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('timeline_tablet_row_header_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('expanded_row_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('expanded_row_2')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('expanded_row_1')), findsNothing);
    expect(find.byKey(const ValueKey('expanded_row_2')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tablet row selection can limit expansion to one row',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0),
    ];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        useTabletDawLayout: true,
        allowMultipleExpandedRows: false,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('timeline_tablet_row_header_0')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('timeline_tablet_row_header_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('expanded_row_1')), findsNothing);
    expect(find.byKey(const ValueKey('expanded_row_2')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tablet row selection can avoid expanding newly selected rows',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0),
    ];
    final selectedRows = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        useTabletDawLayout: true,
        expandRowsOnTrackSelect: false,
        onMoveClipCommit: (_, __, ___) async {},
        onSelectRow: selectedRows.add,
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('timeline_tablet_row_header_0')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('timeline_tablet_row_header_1')));
    await tester.pumpAndSettle();

    expect(selectedRows, <int>[1]);
    expect(find.byKey(const ValueKey('expanded_row_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('expanded_row_2')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tablet grouping footer shows selected count and group CTA',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0),
      TimelineRow(rowId: 3, name: 'Vocal', iconId: 0),
    ];
    var groupPressed = 0;

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        rowGroupingSelectionMode: true,
        groupingSelectedRows: const <int>{0, 1},
        onGroupRowsPressed: () async {
          groupPressed += 1;
        },
        useTabletDawLayout: true,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Group Rows'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        rowGroupingSelectionMode: true,
        groupingSelectedRows: const <int>{0, 1},
        onGroupRowsPressed: () async {
          groupPressed += 1;
        },
        useTabletDawLayout: true,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('tablet_footer_group_rows_button')),
    );
    await tester.pumpAndSettle();

    expect(groupPressed, 1);
  });

  testWidgets('tablet row header gain updates and commits the touched row',
      (tester) async {
    final liveUpdates = <({int row, double gain})>[];
    final commits = <({int row, double oldGain, double newGain})>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: <TimelineRow>[
          TimelineRow(rowId: 1, name: 'Track 1', iconId: 0),
          TimelineRow(rowId: 2, name: 'Track 2', iconId: 0),
        ],
        useTabletDawLayout: true,
        onSetRowGain: (row, gain) async {
          liveUpdates.add((row: row, gain: gain));
        },
        onRowGainCommit: (row, oldGain, newGain) {
          commits.add((row: row, oldGain: oldGain, newGain: newGain));
        },
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(_tabletHeaderGainPoint(tester, 1));
    await tester.pumpAndSettle();

    expect(liveUpdates.map((entry) => entry.row), contains(1));
    expect(liveUpdates.map((entry) => entry.row), isNot(contains(0)));
    expect(commits.map((entry) => entry.row), contains(1));
    expect(commits.map((entry) => entry.row), isNot(contains(0)));
    expect(commits.last.oldGain, closeTo(1.0, 0.001));
    expect(commits.last.newGain, isNot(closeTo(1.0, 0.001)));
  });

  testWidgets('tablet row header gain does not trigger header long press',
      (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: <TimelineRow>[
          TimelineRow(rowId: 1, name: 'Track 1', iconId: 0),
          TimelineRow(rowId: 2, name: 'Track 2', iconId: 0),
        ],
        useTabletDawLayout: true,
        onSetRowColor: (_, __) async {},
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPressAt(_tabletHeaderGainPoint(tester, 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('row_color_choice_1_1')), findsNothing);

    final headerRect = tester.getRect(
      find.byKey(const ValueKey('timeline_tablet_row_header_1')),
    );
    await tester.longPressAt(headerRect.topLeft + const Offset(46, 24));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('row_color_choice_1_1')), findsOneWidget);
  });

  testWidgets('tablet row header gain value accepts typed dB', (tester) async {
    final liveUpdates = <({int row, double gain})>[];
    final commits = <({int row, double oldGain, double newGain})>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: <TimelineRow>[
          TimelineRow(rowId: 1, name: 'Track 1', iconId: 0),
          TimelineRow(rowId: 2, name: 'Track 2', iconId: 0),
        ],
        useTabletDawLayout: true,
        onSetRowGain: (row, gain) async {
          liveUpdates.add((row: row, gain: gain));
        },
        onRowGainCommit: (row, oldGain, newGain) {
          commits.add((row: row, oldGain: oldGain, newGain: newGain));
        },
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('timeline_tablet_row_gain_value_1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tablet_header_gain_db_field')),
      '-6',
    );
    await tester.tap(find.byKey(const ValueKey('tablet_header_gain_db_apply')));
    await tester.pumpAndSettle();

    expect(liveUpdates.map((entry) => entry.row), contains(1));
    expect(liveUpdates.map((entry) => entry.row), isNot(contains(0)));
    expect(commits.map((entry) => entry.row), contains(1));
    expect(commits.map((entry) => entry.row), isNot(contains(0)));
    expect(commits.last.oldGain, closeTo(1.0, 0.001));
    expect(commits.last.newGain, closeTo(1.8, 0.001));
  });

  testWidgets('tablet group header gain does not fan out to child rows',
      (tester) async {
    final liveUpdates = <({int row, double gain})>[];
    final commits = <({int row, double oldGain, double newGain})>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: <TimelineRow>[
          TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
          TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
          TimelineRow(rowId: 3, name: 'Vox', iconId: 0),
        ],
        trackGroupsOverride: const <TrackGroup>[
          TrackGroup(
            id: 'band',
            name: 'Band',
            rowIds: <int>[1, 2],
          ),
        ],
        useTabletDawLayout: true,
        onSetRowGain: (row, gain) async {
          liveUpdates.add((row: row, gain: gain));
        },
        onRowGainCommit: (row, oldGain, newGain) {
          commits.add((row: row, oldGain: oldGain, newGain: newGain));
        },
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(_tabletHeaderGainPoint(tester, 0));
    await tester.pumpAndSettle();

    expect(liveUpdates.map((entry) => entry.row), isNot(contains(1)));
    expect(liveUpdates.map((entry) => entry.row), isNot(contains(2)));
    expect(commits.map((entry) => entry.row), isNot(contains(1)));
    expect(commits.map((entry) => entry.row), isNot(contains(2)));
  });

  testWidgets('row long-press menu applies inline row color swatch',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0),
    ];
    final colorRequests = <MapEntry<int, int>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        onSetRowColor: (row, color) async {
          colorRequests.add(MapEntry<int, int>(row, color));
        },
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await _openRowHeaderMenu(tester, 0);

    await tester.tap(find.byKey(const ValueKey('row_color_choice_0_1')));
    await tester.pumpAndSettle();

    expect(
      colorRequests.map((entry) => '${entry.key}:${entry.value}').toList(),
      <String>['0:${const Color(0xFFFFA654).toARGB32()}'],
    );
  });

  testWidgets('group header row color fans out to grouped rows only',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 3, name: 'Vocal', iconId: 0),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
        collapsed: true,
      ),
    ];
    final colorRequests = <MapEntry<int, int>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        onSetRowColor: (row, color) async {
          colorRequests.add(MapEntry<int, int>(row, color));
        },
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await _openRowHeaderMenu(tester, 0);

    await tester.tap(find.byKey(const ValueKey('row_color_choice_0_1')));
    await tester.pumpAndSettle();

    expect(
      colorRequests.map((entry) => '${entry.key}:${entry.value}').toList(),
      <String>[
        '0:${const Color(0xFFFFA654).toARGB32()}',
        '1:${const Color(0xFFFFA654).toARGB32()}',
      ],
    );
  });

  testWidgets('row menu groups selected clip rows from long press',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0),
      TimelineRow(rowId: 3, name: 'Vocal', iconId: 0),
    ];
    final clips = <AudioTrack>[
      await _buildClip(row: 0, rowId: 1),
      await _buildClip(row: 1, rowId: 2),
    ];
    final groupRequests = <List<int>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        rowsOverride: rows,
        selectedClipIndex: 0,
        selectedClipIndices: const <int>[0, 1],
        onCreateRowGroup: (rows) async {
          groupRequests.add(rows.toList(growable: false));
        },
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await _openRowHeaderMenu(tester, 0);

    expect(find.text('Group Selected Rows'), findsOneWidget);

    await tester.tap(find.text('Group Selected Rows'));
    await tester.pumpAndSettle();

    expect(groupRequests, <List<int>>[
      <int>[0, 1],
    ]);
  });

  testWidgets('row menu hides create group action for a single row',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0),
    ];
    final groupRequests = <List<int>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        onCreateRowGroup: (rows) async {
          groupRequests.add(rows.toList(growable: false));
        },
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await _openRowHeaderMenu(tester, 0);

    expect(find.text('Create Row Group'), findsNothing);
    expect(find.text('Group Selected Rows'), findsNothing);
    expect(groupRequests, isEmpty);
  });

  testWidgets('row menu folds and removes an existing row group',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
      ),
    ];
    final toggledGroups = <String>[];
    final removedRows = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        onToggleRowGroupCollapsed: (groupId) async {
          toggledGroups.add(groupId);
        },
        onRemoveRowFromGroup: (row) async {
          removedRows.add(row);
        },
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await _openRowHeaderMenu(tester, 0);
    expect(find.text('Collapse Group'), findsOneWidget);
    expect(find.text('Remove From Group'), findsOneWidget);

    await tester.tap(find.text('Collapse Group'));
    await tester.pumpAndSettle();
    expect(toggledGroups, <String>['band']);

    await _openRowHeaderMenu(tester, 1);
    await tester.tap(find.text('Remove From Group'));
    await tester.pumpAndSettle();
    expect(removedRows, <int>[1]);
  });

  testWidgets('group header menu renames the group instead of the row',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
      ),
    ];
    final renamedGroups = <String, String>{};

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        onRenameRowGroup: (groupId, name) async {
          renamedGroups[groupId] = name;
        },
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await _openRowHeaderMenu(tester, 0);
    expect(find.text('Rename Group'), findsOneWidget);
    expect(find.text('Rename Row'), findsNothing);

    await tester.tap(find.text('Rename Group'));
    await tester.pumpAndSettle();
    expect(find.text('Rename Group'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Rhythm Bus');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(renamedGroups, <String, String>{'band': 'Rhythm Bus'});
  });

  testWidgets('group volume panel gain controls group bus only',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 3, name: 'Vocal', iconId: 0),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
        collapsed: true,
      ),
    ];
    final gainCommits = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        onMoveClipCommit: (_, __, ___) async {},
        onRowGainCommit: (row, _, __) {
          gainCommits.add(row);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(24, _kRulerHeight + 40.0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PrettyGainSlider), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(gainCommits, <int>[0]);
  });

  testWidgets('group volume panel pan controls group bus only', (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 3, name: 'Vocal', iconId: 0),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
        collapsed: true,
      ),
    ];
    final panCommits = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        onMoveClipCommit: (_, __, ___) async {},
        onRowPanCommit: (row, _, __) {
          panCommits.add(row);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(24, _kRulerHeight + 40.0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PrettyStereoSlider), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(panCommits, <int>[0]);
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

  testWidgets('selected MIDI clip popup exposes piano roll action',
      (tester) async {
    final clips = <AudioTrack>[await _buildMidiClip()];
    final rows = <TimelineRow>[
      TimelineRow(
        rowId: 1,
        name: 'Keys',
        iconId: 1,
        kind: TimelineRowKind.instrument,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
      ),
    ];
    final openRequests = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        rowsOverride: rows,
        onMoveClipCommit: (_, __, ___) async {},
        onOpenMidiClip: openRequests.add,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(_clipCenter(tester));
    await tester.pumpAndSettle();

    final pianoRollAction = find.byKey(
      const ValueKey('selected_clip_popup_open_piano_roll'),
    );
    expect(pianoRollAction, findsOneWidget);
    expect(
      tester.getRect(pianoRollAction).left,
      lessThan(tester.getRect(find.byIcon(Icons.copy)).left),
    );

    await tester.tap(pianoRollAction);
    await tester.pumpAndSettle();

    expect(openRequests, <int>[0]);
  });

  testWidgets('desktop double-click MIDI clip opens piano roll', (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      final clips = <AudioTrack>[await _buildMidiClip()];
      final rows = <TimelineRow>[
        TimelineRow(
          rowId: 1,
          name: 'Keys',
          iconId: 1,
          kind: TimelineRowKind.instrument,
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano',
        ),
      ];
      final openRequests = <int>[];

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          rowsOverride: rows,
          onMoveClipCommit: (_, __, ___) async {},
          onOpenMidiClip: openRequests.add,
        ),
      );
      await tester.pumpAndSettle();

      await _desktopDoubleTapAt(tester, _desktopClipCenter(tester));

      expect(openRequests, <int>[0]);
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets(
    'desktop double-click audio clip opens clip options panel',
    (tester) async {
      _setTestTargetPlatform(TargetPlatform.macOS);
      try {
        final clips = <AudioTrack>[await _buildClip()];
        final panelRequests = <int>[];

        await tester.pumpWidget(
          _buildHarness(
            clips: clips,
            useTabletDawLayout: true,
            onMoveClipCommit: (_, __, ___) async {},
            onOpenAudioClipOptionsPanel: panelRequests.add,
          ),
        );
        await tester.pumpAndSettle();

        await _desktopDoubleTapAt(tester, _desktopClipCenter(tester));

        expect(panelRequests, <int>[0]);
      } finally {
        _setTestTargetPlatform(null);
      }
    },
  );

  testWidgets(
    'desktop single click MIDI clip does not open piano roll',
    (tester) async {
      _setTestTargetPlatform(TargetPlatform.macOS);
      try {
        final clips = <AudioTrack>[await _buildMidiClip()];
        final rows = <TimelineRow>[
          TimelineRow(
            rowId: 1,
            name: 'Keys',
            iconId: 1,
            kind: TimelineRowKind.instrument,
            instrumentId: 'sfz.vsco.upright_piano',
            instrumentName: 'Upright Piano',
          ),
        ];
        final openRequests = <int>[];

        await tester.pumpWidget(
          _buildHarness(
            clips: clips,
            rowsOverride: rows,
            onMoveClipCommit: (_, __, ___) async {},
            onOpenMidiClip: openRequests.add,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tapAt(_desktopClipCenter(tester));
        await tester.pumpAndSettle();

        expect(openRequests, isEmpty);
        expect(
          find.byKey(const ValueKey('selected_clip_popup_open_piano_roll')),
          findsOneWidget,
        );
      } finally {
        _setTestTargetPlatform(null);
      }
    },
  );

  testWidgets(
    'phone second tap on selected MIDI clip still opens piano roll',
    (tester) async {
      _setTestTargetPlatform(TargetPlatform.android);
      try {
        final clips = <AudioTrack>[await _buildMidiClip()];
        final rows = <TimelineRow>[
          TimelineRow(
            rowId: 1,
            name: 'Keys',
            iconId: 1,
            kind: TimelineRowKind.instrument,
            instrumentId: 'sfz.vsco.upright_piano',
            instrumentName: 'Upright Piano',
          ),
        ];
        final openRequests = <int>[];

        await tester.pumpWidget(
          _buildHarness(
            clips: clips,
            rowsOverride: rows,
            onMoveClipCommit: (_, __, ___) async {},
            onOpenMidiClip: openRequests.add,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tapAt(_clipCenter(tester));
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
        expect(openRequests, isEmpty);
        expect(
          find.byKey(const ValueKey('selected_clip_popup_open_piano_roll')),
          findsOneWidget,
        );

        await tester.tapAt(_clipCenter(tester));
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();

        expect(openRequests, <int>[0]);
      } finally {
        _setTestTargetPlatform(null);
      }
    },
  );

  testWidgets(
    'tablet MIDI clip settings opens the side panel instead of overlay',
    (tester) async {
      final clips = <AudioTrack>[await _buildMidiClip()];
      final rows = <TimelineRow>[
        TimelineRow(
          rowId: 1,
          name: 'Keys',
          iconId: 1,
          kind: TimelineRowKind.instrument,
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano',
        ),
      ];
      final panelRequests = <int>[];

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          rowsOverride: rows,
          selectedClipIndex: 0,
          useTabletDawLayout: true,
          onMoveClipCommit: (_, __, ___) async {},
          onOpenAudioClipOptionsPanel: panelRequests.add,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('selected_clip_popup_clip_settings')),
      );
      await tester.pumpAndSettle();

      expect(panelRequests, <int>[0]);
      expect(find.text('No extra tempo mode is needed here.'), findsNothing);
    },
  );

  testWidgets(
    'tablet audio clip settings still opens the side panel',
    (tester) async {
      final clips = <AudioTrack>[await _buildClip()];
      final panelRequests = <int>[];

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          selectedClipIndex: 0,
          useTabletDawLayout: true,
          onMoveClipCommit: (_, __, ___) async {},
          onOpenAudioClipOptionsPanel: panelRequests.add,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('selected_clip_popup_clip_settings')),
      );
      await tester.pumpAndSettle();

      expect(panelRequests, <int>[0]);
    },
  );

  testWidgets(
    'tablet selection reports a new primary after clip settings opens',
    (tester) async {
      final first = await _buildClip(engineClipId: 1);
      final second = await _buildClip(engineClipId: 2);
      second.offset = 2200.0;
      final panelRequests = <int>[];
      final selectionSnapshots = <
        ({
          List<int> selected,
          int primary,
          TimelineSelectionChangeOrigin origin,
        })
      >[];

      await tester.pumpWidget(
        _buildHarness(
          clips: <AudioTrack>[first, second],
          selectedClipIndex: 0,
          useTabletDawLayout: true,
          onMoveClipCommit: (_, __, ___) async {},
          onOpenAudioClipOptionsPanel: panelRequests.add,
          onSelectionChanged: (selected, primary, origin) {
            selectionSnapshots.add((
              selected: List<int>.from(selected),
              primary: primary,
              origin: origin,
            ));
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('selected_clip_popup_clip_settings')),
      );
      await tester.pumpAndSettle();
      expect(panelRequests, <int>[0]);
      expect(selectionSnapshots.last.selected, isEmpty);
      expect(selectionSnapshots.last.primary, -1);

      await tester.tapAt(_clipCenter(tester, additionalDx: 220.0));
      await tester.pumpAndSettle();

      expect(selectionSnapshots.last.selected, <int>[1]);
      expect(selectionSnapshots.last.primary, 1);
      expect(
        selectionSnapshots.last.origin,
        TimelineSelectionChangeOrigin.interaction,
      );
    },
  );

  testWidgets(
    'topology reconciliation is distinct from the next user selection',
    (tester) async {
      final first = await _buildClip(engineClipId: 1);
      final second = await _buildClip(engineClipId: 2);
      second.offset = 2200.0;
      final origins = <TimelineSelectionChangeOrigin>[];

      Widget harness(List<AudioTrack> clips, int topologyRevision) {
        return _buildHarness(
          clips: clips,
          clipTopologyRevision: topologyRevision,
          onMoveClipCommit: (_, __, ___) async {},
          onSelectionChanged: (_, __, origin) => origins.add(origin),
        );
      }

      await tester.pumpWidget(harness(<AudioTrack>[first], 0));
      await tester.pumpAndSettle();
      origins.clear();

      await tester.pumpWidget(harness(<AudioTrack>[first, second], 1));
      await tester.pumpAndSettle();
      expect(origins, contains(TimelineSelectionChangeOrigin.reconciliation));
      origins.clear();

      await tester.tapAt(_clipCenter(tester, additionalDx: 220.0));
      await tester.pumpAndSettle();
      expect(origins.last, TimelineSelectionChangeOrigin.interaction);

      origins.clear();
      await tester.pumpWidget(harness(<AudioTrack>[first, second], 2));
      await tester.pumpAndSettle();
      expect(
        origins,
        contains(TimelineSelectionChangeOrigin.reconciliation),
      );

      origins.clear();
      await tester.tapAt(_clipCenter(tester));
      await tester.pumpAndSettle();
      expect(origins.last, TimelineSelectionChangeOrigin.interaction);
    },
  );

  testWidgets(
    'phone MIDI clip settings keeps the timeline overlay',
    (tester) async {
      final clips = <AudioTrack>[await _buildMidiClip()];
      final rows = <TimelineRow>[
        TimelineRow(
          rowId: 1,
          name: 'Keys',
          iconId: 1,
          kind: TimelineRowKind.instrument,
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano',
        ),
      ];
      final panelRequests = <int>[];

      await tester.pumpWidget(
        _buildHarness(
          clips: clips,
          rowsOverride: rows,
          selectedClipIndex: 0,
          onMoveClipCommit: (_, __, ___) async {},
          onOpenAudioClipOptionsPanel: panelRequests.add,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('selected_clip_popup_clip_settings')),
      );
      await tester.pumpAndSettle();

      expect(panelRequests, isEmpty);
      expect(find.text('No extra tempo mode is needed here.'), findsOneWidget);
    },
  );

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

  testWidgets('clip deletion cancels a drag that holds a stale clip index',
      (tester) async {
    final clips = <AudioTrack>[
      await _buildClip(),
      await _buildClip(),
      await _buildClip(),
    ];
    final moveRequests = <int>[];

    Widget harness(List<AudioTrack> currentClips) => _buildHarness(
          clips: currentClips,
          onMoveClipCommit: (clipIndex, _, __) async {
            moveRequests.add(clipIndex);
          },
        );

    await tester.pumpWidget(harness(clips));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(_clipCenter(tester));
    await gesture.moveBy(const Offset(24.0, 0.0));
    await tester.pump();

    // The topmost clip is index 2. Removing it while the pointer remains down
    // must invalidate the transient drag before another update arrives.
    await tester.pumpWidget(harness(clips.take(2).toList(growable: false)));
    await tester.pump();
    await gesture.moveBy(const Offset(24.0, 0.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(moveRequests, isEmpty);
  });

  testWidgets('desktop delete key removes selected clips', (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final deleteRequests = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        selectedClipIndex: 0,
        selectedClipIndices: const <int>[0],
        onMoveClipCommit: (_, __, ___) async {},
        onDeleteClip: (clipIndex) async {
          deleteRequests.add(clipIndex);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    expect(deleteRequests, <int>[0]);
  });

  testWidgets(
      'desktop backspace key removes the selected row when no clips are selected',
      (tester) async {
    final rowDeleteRequests = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        onMoveClipCommit: (_, __, ___) async {},
        onDeleteRow: (row) async {
          rowDeleteRequests.add(row);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(rowDeleteRequests, <int>[0]);
  });

  testWidgets('desktop command-c copies the selected clip', (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final copyRequests = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        selectedClipIndex: 0,
        selectedClipIndices: const <int>[0],
        onMoveClipCommit: (_, __, ___) async {},
        onCopyClip: copyRequests.add,
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(copyRequests, <int>[0]);
  });

  testWidgets('desktop command-v pastes copied clip at the playhead',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip(row: 1, rowId: 2)];
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Track 1', iconId: 0),
      TimelineRow(rowId: 2, name: 'Track 2', iconId: 0),
    ];
    final pasteRequests = <MapEntry<int, double>>[];
    final clock = ValueNotifier<Duration>(
      const Duration(milliseconds: 1234),
    );

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        rowsOverride: rows,
        selectedClipIndex: 0,
        selectedClipIndices: const <int>[0],
        hasCopiedClip: true,
        transportClockListenable: clock,
        onMoveClipCommit: (_, __, ___) async {},
        onPasteClipAt: (row, timeMs) async {
          pasteRequests.add(MapEntry<int, double>(row, timeMs));
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    // Preserve the exact playhead position being exercised by this test.
    await tester.tapAt(_magnetButtonCenter(tester));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(pasteRequests, hasLength(1));
    expect(pasteRequests.single.key, 1);
    expect(pasteRequests.single.value, 1234.0);
  });

  testWidgets('desktop command-v prefers the last empty timeline click',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final pasteRequests = <MapEntry<int, double>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        hasCopiedClip: true,
        onClearCopiedClip: () {},
        onMoveClipCommit: (_, __, ___) async {},
        onPasteClipAt: (row, timeMs) async {
          pasteRequests.add(MapEntry<int, double>(row, timeMs));
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    // Preserve the exact empty-lane click position being exercised here.
    await tester.tapAt(_magnetButtonCenter(tester));
    await tester.pumpAndSettle();

    final timelineTopLeft = tester.getTopLeft(find.byType(AudioCanvasTimeline));
    await tester.tapAt(
      timelineTopLeft + const Offset(_kHeaderWidth + 560.0, _kRulerHeight + 40),
    );
    await tester.pump();

    final popupRect =
        tester.getRect(find.byKey(const ValueKey('timeline_paste_popup')));
    expect(popupRect.width, 79.0);
    expect(popupRect.height, 36.0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(pasteRequests, hasLength(1));
    expect(pasteRequests.single.key, 0);
    expect(pasteRequests.single.value, 2400.0);
  });

  testWidgets('desktop paste popup appears on pointer down', (tester) async {
    final clips = <AudioTrack>[await _buildClip()];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        hasCopiedClip: true,
        onClearCopiedClip: () {},
        onMoveClipCommit: (_, __, ___) async {},
        onPasteClipAt: (_, __) async => true,
      ),
    );
    await tester.pumpAndSettle();

    final timelineTopLeft = tester.getTopLeft(find.byType(AudioCanvasTimeline));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(
      timelineTopLeft + const Offset(_kHeaderWidth + 560.0, _kRulerHeight + 40),
    );
    await tester.pump();

    final popupRect =
        tester.getRect(find.byKey(const ValueKey('timeline_paste_popup')));
    expect(popupRect.top, greaterThanOrEqualTo(0.0));
    expect(popupRect.height, 36.0);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('desktop command-b step duplicates the selected clip',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip(row: 1, rowId: 2)];
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Track 1', iconId: 0),
      TimelineRow(rowId: 2, name: 'Track 2', iconId: 0),
    ];
    final duplicateRequests = <MapEntry<List<int>, double>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        rowsOverride: rows,
        selectedClipIndex: 0,
        selectedClipIndices: const <int>[0],
        onMoveClipCommit: (_, __, ___) async {},
        onStepDuplicateClips: (clipIndices, pasteStartMs) async {
          duplicateRequests.add(
            MapEntry<List<int>, double>(
              clipIndices.toList(growable: false),
              pasteStartMs,
            ),
          );
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(duplicateRequests, hasLength(1));
    expect(duplicateRequests.single.key, <int>[0]);
    expect(duplicateRequests.single.value, 2000.0);
  });

  testWidgets('holding desktop command-b keeps step duplicating forward',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final duplicateRequests = <double>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        selectedClipIndex: 0,
        selectedClipIndices: const <int>[0],
        onMoveClipCommit: (_, __, ___) async {},
        onStepDuplicateClips: (_, pasteStartMs) async {
          duplicateRequests.add(pasteStartMs);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(duplicateRequests, <double>[2000.0, 4000.0, 6000.0]);
  });

  testWidgets('desktop command-b step duplicates a selected clip group',
      (tester) async {
    final clips = <AudioTrack>[
      await _buildClip(row: 0, rowId: 1),
      await _buildClip(row: 1, rowId: 2),
    ];
    clips[1].offset = 750.0;
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Track 1', iconId: 0),
      TimelineRow(rowId: 2, name: 'Track 2', iconId: 0),
    ];
    final duplicateRequests = <MapEntry<List<int>, double>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        rowsOverride: rows,
        selectedClipIndex: 1,
        selectedClipIndices: const <int>[0, 1],
        onMoveClipCommit: (_, __, ___) async {},
        onStepDuplicateClips: (clipIndices, pasteStartMs) async {
          duplicateRequests.add(
            MapEntry<List<int>, double>(
              clipIndices.toList(growable: false),
              pasteStartMs,
            ),
          );
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    // This test validates group spacing rather than snap quantization.
    await tester.tapAt(_magnetButtonCenter(tester));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(duplicateRequests, hasLength(1));
    expect(duplicateRequests.single.key, <int>[0, 1]);
    expect(duplicateRequests.single.value, 2750.0);
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
        onSelectionChanged: (selectedClipIndices, _, __) {
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

  testWidgets(
    'desktop group trim applies the same edge drag to every selected clip',
    (tester) async {
      _setTestTargetPlatform(TargetPlatform.macOS);
      try {
        final clips = <AudioTrack>[
          await _buildClip(engineClipId: 1),
          await _buildClip(engineClipId: 2),
        ];
        clips[1].offset = 2200.0;
        final trimCommits = <int>[];
        final moveCommits = <int>[];

        await tester.pumpWidget(
          _buildHarness(
            clips: clips,
            selectedClipIndex: 0,
            selectedClipIndices: const <int>[0, 1],
            onMoveClipCommit: (clipIndex, _, __) async {
              moveCommits.add(clipIndex);
            },
            onTrimClipCommit: (
              clipIndex,
              newTrimStartMs,
              newTrimEndMs,
              oldTrimStartMs,
              oldTrimEndMs,
              originalStartMs, {
              newStartMs,
            }) {
              trimCommits.add(clipIndex);
            },
          ),
        );
        await tester.pumpAndSettle();

        final clipWidthPx = _kClipDurationMs * _kInitialPixelsPerMs;
        final clip1LeftHandle = _clipCenter(tester) +
            Offset(
              -clipWidthPx -
                  _kTrimHandleGapPx -
                  (_kTrimHandleWidthPx / 2.0),
              0,
            );
        await tester.dragFrom(clip1LeftHandle, const Offset(80, 0));
        await tester.pumpAndSettle();

        expect(
          trimCommits.toSet(),
          <int>{0, 1},
          reason: 'trim=$trimCommits move=$moveCommits',
        );
      } finally {
        _setTestTargetPlatform(null);
      }
    },
  );

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

  testWidgets('scale gesture reaches the shared deep zoom ceiling',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final controller = AudioCanvasTimelineController();
    final detailViewports = <WaveformDetailViewport>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        controller: controller,
        onMoveClipCommit: (_, __, ___) async {},
        onWaveformDetailViewportSettled: detailViewports.add,
      ),
    );
    await tester.pumpAndSettle();

    final center = _clipCenter(tester);
    final gesture = await tester.createGesture(
      pointer: 103,
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center);
    await tester.pump();
    await gesture.panZoomUpdate(center, scale: 100.0);
    await tester.pump();
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 181));

    expect(controller.topControlsState.quantizeDivisionsPerBar, 512);
    expect(detailViewports.last.pixelsPerMs, 8.0);
  });

  testWidgets('pinch zoom does not leave an unselected clip selected',
      (tester) async {
    final clips = <AudioTrack>[await _buildClip()];
    final selectionSnapshots = <List<int>>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: clips,
        onMoveClipCommit: (_, __, ___) async {},
        onSelectionChanged: (selectedClipIndices, _, __) {
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
      'effect parameter geometry admits an off-screen clip on the next scroll',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.iOS);
    try {
      final controller = AudioCanvasTimelineController();
      final rows = List<TimelineRow>.generate(
        8,
        (index) => TimelineRow(
          rowId: index + 1,
          name: 'Track ${index + 1}',
          iconId: 0,
        ),
      );
      final upperClip = await _buildClip(row: 0, rowId: 1, engineClipId: 1);

      await tester.pumpWidget(
        _buildHarness(
          clips: <AudioTrack>[upperClip],
          controller: controller,
          rowsOverride: rows,
          rowEffects: const <String>['EQ'],
          onMoveClipCommit: (_, __, ___) async {},
        ),
      );
      await tester.pumpAndSettle();

      controller.ensureRowExpanded(7, tab: 1);
      await tester.pumpAndSettle();

      final effectsPanel = tester.widget<RowEffectsPanel>(
        find.byType(RowEffectsPanel),
      );
      effectsPanel.onHeightChanged(800.0);
      await tester.pumpAndSettle();

      final verticalController = _timelineVerticalScrollController(tester);
      verticalController.jumpTo(verticalController.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(_paintedTimelineClipIndices(tester), isNot(contains(0)));
      final painterWithoutClipZero = _timelineClipPainter(tester);

      effectsPanel.onHeightChanged(240.0);
      await tester.pumpAndSettle();

      expect(
        _paintedTimelineVerticalScrollOffset(tester),
        closeTo(verticalController.offset, 0.01),
      );

      final stableOffset = verticalController.offset;
      effectsPanel.onHeightChanged(240.0);
      await tester.pumpAndSettle();
      expect(verticalController.offset, stableOffset);

      verticalController.jumpTo(0.0);
      await tester.pumpAndSettle();
      expect(_paintedTimelineClipIndices(tester), contains(0));
      final painterWithClipZero = _timelineClipPainter(tester);
      expect(
        painterWithClipZero.shouldRepaint(painterWithoutClipZero),
        isTrue,
        reason: 'clip index 0 entering the viewport must invalidate paint',
      );
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('tablet effects tab shows horizontal device chain controls',
      (tester) async {
    final controller = AudioCanvasTimelineController();
    final selectedEffects = <MapEntry<int, int>>[];
    final bypassRequests = <String>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: <AudioTrack>[await _buildClip()],
        controller: controller,
        useTabletDawLayout: true,
        rowEffects: const <String>['EQ', 'Delay', 'Reverb'],
        onRowEffectSelected: (row, effectIndex) {
          selectedEffects.add(MapEntry<int, int>(row, effectIndex));
        },
        onSetRowEffectBypassed: (row, effectIndex, bypass) async {
          bypassRequests.add('$row:$effectIndex:$bypass');
        },
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    controller.ensureRowExpanded(0, tab: 1);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('device_add_effect')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('device_effect_bypass_0_1')), findsOneWidget);

    await tester.tap(find.text('Delay'));
    await tester.pumpAndSettle();
    expect(
      selectedEffects.map((entry) => '${entry.key}:${entry.value}').toList(),
      <String>['0:1'],
    );

    await tester.tap(find.byKey(const ValueKey('device_effect_bypass_0_1')));
    await tester.pumpAndSettle();
    expect(bypassRequests, <String>['0:1:true']);
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

  testWidgets('group effects menu paste and clear target the group header bus',
      (tester) async {
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 3, name: 'Vocal', iconId: 0),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
        collapsed: true,
      ),
    ];
    final pastedRows = <int>[];
    final clearedRows = <int>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        rowsOverride: rows,
        trackGroupsOverride: groups,
        onMoveClipCommit: (_, __, ___) async {},
        rowEffects: const <String>['EQ'],
        onPasteRowEffects: (row) async {
          pastedRows.add(row);
        },
        onClearRowEffects: (row) async {
          clearedRows.add(row);
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
    await tester
        .tap(find.byKey(const ValueKey('row_effects_menu_action_0_paste')));
    await tester.pumpAndSettle();
    expect(pastedRows, <int>[0]);

    await tester.tap(find.byKey(const ValueKey('row_effects_menu_0')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('row_effects_menu_action_0_clear')));
    await tester.pumpAndSettle();
    expect(clearedRows, <int>[0]);
  });

  testWidgets('group header effect actions target the group header bus',
      (tester) async {
    final controller = AudioCanvasTimelineController();
    final rows = <TimelineRow>[
      TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      TimelineRow(rowId: 3, name: 'Vocal', iconId: 0),
    ];
    final groups = <TrackGroup>[
      const TrackGroup(
        id: 'band',
        name: 'Band',
        rowIds: <int>[1, 2],
      ),
    ];
    final insertRequests = <String>[];
    final bypassRequests = <String>[];

    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        controller: controller,
        rowsOverride: rows,
        trackGroupsOverride: groups,
        useTabletDawLayout: true,
        onMoveClipCommit: (_, __, ___) async {},
        rowEffects: const <String>['EQ'],
        onInsertRowEffect: (row, pathOrName) async {
          insertRequests.add('$row:$pathOrName');
        },
        onSetRowEffectBypassed: (row, effectIndex, bypass) async {
          bypassRequests.add('$row:$effectIndex:$bypass');
        },
      ),
    );
    await tester.pumpAndSettle();

    controller.ensureRowExpanded(0, tab: 1);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('device_effect_bypass_0_0')));
    await tester.pumpAndSettle();
    expect(bypassRequests, <String>['0:0:true']);

    await tester.tap(find.byKey(const ValueKey('device_add_effect')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EQ Parametric'));
    await tester.pumpAndSettle();

    expect(insertRequests, <String>['0:EQ Parametric']);
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
    await tester.tap(find.byKey(const ValueKey('timeline_tool_menu_paint')));
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

  testWidgets('tool selector menu is wide enough for single-line labels',
      (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.near_me_outlined));
    await tester.pumpAndSettle();

    final itemRect =
        tester.getRect(find.byKey(const ValueKey('timeline_tool_menu_paint')));
    expect(itemRect.width, greaterThanOrEqualTo(176.0));
    final paintText = tester.widget<Text>(find.text('Paint').last);
    expect(paintText.maxLines, 1);
    expect(paintText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('tool selector toggles foreground grid rendering',
      (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.near_me_outlined));
    await tester.pumpAndSettle();
    var gridItem = tester.widget<CheckedPopupMenuItem<Object>>(
      find.byKey(const ValueKey('timeline_foreground_grid_toggle')),
    );
    expect(gridItem.checked, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('timeline_foreground_grid_toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.near_me_outlined));
    await tester.pumpAndSettle();
    gridItem = tester.widget<CheckedPopupMenuItem<Object>>(
      find.byKey(const ValueKey('timeline_foreground_grid_toggle')),
    );
    expect(gridItem.checked, isFalse);
  });

  testWidgets('number keys select timeline tools in toolbar order',
      (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(_laneCenter(tester));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline_active_tool_stretch')),
        findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline_active_tool_paint')),
        findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('timeline_active_tool_cut')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline_active_tool_delete')),
        findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline_active_tool_pencil')),
        findsOneWidget);
  });

  testWidgets('quantize menu exposes fixed 1/32 within trigger width',
      (tester) async {
    final controller = AudioCanvasTimelineController();
    await tester.pumpWidget(
      _buildHarness(
        clips: const <AudioTrack>[],
        controller: controller,
        onMoveClipCommit: (_, __, ___) async {},
      ),
    );
    await tester.pumpAndSettle();

    const triggerWidth = 30.0;
    await tester.longPressAt(_magnetButtonCenter(tester));
    await tester.pumpAndSettle();

    final fixedThirtySecond =
        find.byKey(const ValueKey('timeline_quantize_menu_32'));
    final itemRect = tester.getRect(fixedThirtySecond);
    expect(itemRect.width, closeTo(triggerWidth, 0.5));

    await tester.tap(fixedThirtySecond);
    await tester.pumpAndSettle();

    expect(controller.topControlsState.gridMode, TimelineGridMode.fixed);
    expect(controller.topControlsState.quantizeDivisionsPerBar, 32);
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
