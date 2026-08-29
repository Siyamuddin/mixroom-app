import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'dart:math' as math;
import 'package:mixroom/models/models.dart';
import 'package:mixroom/widgets/effects_panel.dart';
import 'package:mixroom/widgets/sample_browser_panel.dart';
import 'package:mixroom/helpers/app_haptics.dart';
import 'package:mixroom/helpers/automation_clip_clone_helper.dart';
import 'package:mixroom/helpers/dbfs_meter_visuals.dart';
import 'package:mixroom/helpers/desktop_editor_prefs.dart';
import 'package:mixroom/helpers/desktop_slider_wheel_sensitivity.dart';
import 'package:mixroom/helpers/glass_ui_tokens.dart';
import 'package:mixroom/helpers/halo.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/helpers/tablet_daw_panel_layout.dart';
import 'package:mixroom/helpers/track_group_reconciler.dart';
import 'package:mixroom/helpers/track_row_icons.dart';
import 'package:mixroom/helpers/mix_change_highlighter.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:mixroom/widgets/desktop_scrollable_slider.dart';
import 'package:uuid/uuid.dart';

@visibleForTesting
List<Offset> buildRecordingPreviewEnvelopePoints({
  required List<double> peaks,
  required List<double> peakTimesMs,
  required double durationMs,
}) {
  final sampleCount = math.min(peaks.length, peakTimesMs.length);
  if (sampleCount <= 0 || !durationMs.isFinite || durationMs <= 0.0) {
    return const <Offset>[];
  }

  double safeAmplitude(double value) =>
      value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;

  final points = <Offset>[];
  var lastTimeMs = 0.0;
  for (var index = 0; index < sampleCount; index++) {
    final rawTimeMs = peakTimesMs[index];
    if (!rawTimeMs.isFinite || rawTimeMs < 0.0 || rawTimeMs > durationMs) {
      continue;
    }
    final timeMs = math.max(lastTimeMs, rawTimeMs).toDouble();
    final amplitude = safeAmplitude(peaks[index]);
    if (points.isEmpty) {
      points.add(Offset(0.0, amplitude));
    }
    points.add(Offset(timeMs, amplitude));
    lastTimeMs = timeMs;
  }
  if (points.isEmpty) return const <Offset>[];

  // Accepted interval endpoints are immutable. The sole provisional point is
  // a continuation of the latest amplitude to the current playhead.
  if (points.last.dx < durationMs) {
    points.add(Offset(durationMs, points.last.dy));
  }
  return points;
}

class _QuantizePreset {
  final int divisionsPerBar;
  final String label;

  const _QuantizePreset({required this.divisionsPerBar, required this.label});
}

class SampleDropPlacement {
  final int row;
  final double startMs;
  final double endMs;
  final bool allowed;

  const SampleDropPlacement({
    required this.row,
    required this.startMs,
    required this.endMs,
    required this.allowed,
  });
}

class _PendingPaintPaste {
  final int row;
  final double startMs;

  const _PendingPaintPaste({required this.row, required this.startMs});
}

class _TimelinePasteTarget {
  final int row;
  final double startMs;

  const _TimelinePasteTarget({required this.row, required this.startMs});
}

class _AddRowBubbleTailPainter extends CustomPainter {
  _AddRowBubbleTailPainter({required this.centerX, required this.color});

  final double centerX;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final safeCenter = centerX.clamp(10.0, size.width - 10.0).toDouble();
    final path = Path()
      ..moveTo(safeCenter - 9.0, 0.0)
      ..lineTo(safeCenter + 9.0, 0.0)
      ..lineTo(safeCenter, 9.0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AddRowBubbleTailPainter oldDelegate) {
    return centerX != oldDelegate.centerX || color != oldDelegate.color;
  }
}

class TimelineClipMoveRequest {
  final int clipIndex;
  final double newStartMs;
  final int newRowIndex;

  const TimelineClipMoveRequest({
    required this.clipIndex,
    required this.newStartMs,
    required this.newRowIndex,
  });
}

class TimelineClipLayoutMutation {
  final int revision;
  final AudioTrack clip;

  const TimelineClipLayoutMutation({
    required this.revision,
    required this.clip,
  });
}

class _TimelineGestureSelectionSnapshot {
  final int selectedClipIndex;
  final List<int> selectedClipIndices;
  final double? clipPopupMs;
  final int? trimClipIndex;
  final double? activeTrimHandleX;
  final int? stretchClipIndex;
  final Map<String, String> selectedAutomationClipByLane;
  final String? automationClipMenuClipId;
  final bool showPastePopup;
  final int? pasteRow;
  final double? pasteMs;
  final int? highlightedSegmentRow;
  final double? highlightedSegmentStartMs;
  final double? highlightedSegmentEndMs;
  final int? inlineClipControlIndex;
  final _InlineClipControlKind? inlineClipControlKind;
  final double? inlineClipGainStart;
  final double? inlineClipPitchStart;

  const _TimelineGestureSelectionSnapshot({
    required this.selectedClipIndex,
    required this.selectedClipIndices,
    required this.clipPopupMs,
    required this.trimClipIndex,
    required this.activeTrimHandleX,
    required this.stretchClipIndex,
    required this.selectedAutomationClipByLane,
    required this.automationClipMenuClipId,
    required this.showPastePopup,
    required this.pasteRow,
    required this.pasteMs,
    required this.highlightedSegmentRow,
    required this.highlightedSegmentStartMs,
    required this.highlightedSegmentEndMs,
    required this.inlineClipControlIndex,
    required this.inlineClipControlKind,
    required this.inlineClipGainStart,
    required this.inlineClipPitchStart,
  });
}

class _AutomationClipClipboardEntry {
  final String targetId;
  final String targetLabel;
  final AutomationClipSnapshot clip;

  const _AutomationClipClipboardEntry({
    required this.targetId,
    required this.targetLabel,
    required this.clip,
  });
}

class _AutomationPointsClipboardEntry {
  final List<AutomationPoint> points;

  const _AutomationPointsClipboardEntry({required this.points});
}

class _AutomationAreaClipboardEntry {
  final double durationMs;
  final List<AutomationPoint> relativePoints;

  const _AutomationAreaClipboardEntry({
    required this.durationMs,
    required this.relativePoints,
  });
}

enum _TimelineTool { pencil, stretch, paint, cut, delete }

enum _TimelineTrackpadPanAxis { horizontal, vertical }

enum _InlineClipControlKind { settings }

const Color _kTimelineShellText = Color(0xFFF4F4F4);
const Color _kTimelineShellMutedText = Color(0xB8F4F4F4);
const Color _kTimelineShellFill = Color.fromRGBO(244, 244, 244, 0.12);
const Color _kTimelineWarmStart = Color.fromRGBO(112, 119, 126, 0.96);
const Color _kTimelineWarmEnd = Color.fromRGBO(78, 85, 92, 0.98);
const Color _kTimelineWarmBorder = Color.fromRGBO(206, 213, 220, 0.42);
const Color _kTimelineCanvas = Color(0xFF11161D);
const Color _kTimelineRowEven = Color(0xFF2F3236);
const Color _kTimelineRowOdd = Color(0xFF323539);
const Color _kTimelineRowDivider = Color.fromRGBO(255, 255, 255, 0.08);
const Color _kTimelineHeaderFocusedBlue = Color(0xFF7CA2CB);
const Color _kTimelineHeaderFocusedBlueDark = Color(0xFF5D7FA6);
const Color _kTimelineHeaderIdle = Color(0xFF464A4F);
const Color _kTimelineHeaderIdleDark = Color(0xFF32363B);
const Color _kTimelineHeaderSelected = Color(0xFF9A6A36);
const Color _kTimelineHeaderSelectedDark = Color(0xFF744B24);
const Color _kMasterAutomationLaneFill = Color(0xFF1D2733);
const Color _kMasterAutomationLaneHeader = Color(0xFF3F4751);
const Color _kMasterAutomationLaneBorder = Color.fromRGBO(255, 255, 255, 0.16);
const Color _kTimelineUtilityBlue = Color(0xFF2B88DE);
const Color _kTimelineUtilityBlueDark = Color(0xFF1F69BA);
const Color _kTimelineClipAudio = Color(0xFF6A7A89);
const Color _kTimelineClipAudioSelected = Color(0xFFA36D35);
const Color _kTimelineClipAudioBorder = Color(0xFF8191A0);
const Color _kTimelineClipAudioSelectedBorder = Color(0xFFFFA04A);
const Color _kTimelineClipMidi = _kTimelineClipAudio;
const Color _kTimelineClipMidiSelected = _kTimelineClipAudioSelected;
const Color _kTimelineExpandedPanelSurface = Color.fromRGBO(98, 104, 110, 0.82);
const Color _kTimelineExpandedPanelSurfaceFx = Color.fromRGBO(
  92,
  99,
  106,
  0.96,
);
const Color _kTimelineExpandedPanelBorder = Color.fromRGBO(255, 255, 255, 0.09);
const Color _kTimelineExpandedInnerSurface = Color.fromRGBO(
  244,
  244,
  244,
  0.08,
);
const Color _kTimelineExpandedInnerSurfaceFx = Color(0xFF5E656D);

const List<Color> _kTimelineRowColorPalette = <Color>[
  Color(0xFFFF6F7D),
  Color(0xFFFFA654),
  Color(0xFFFFDD66),
  Color(0xFF69E080),
  Color(0xFF6BD7F0),
  Color(0xFF79A8FF),
  Color(0xFFC78DFF),
  Color(0xFFFF7FE3),
];

Color _timelineCanvasColor() {
  if (!PlatformCapabilities.current.isDesktop) return _kTimelineCanvas;
  return const Color.fromRGBO(14, 26, 40, 0.22);
}

Color _timelineRowFillColor(bool isEven) {
  if (!PlatformCapabilities.current.isDesktop) {
    return isEven ? _kTimelineRowEven : _kTimelineRowOdd;
  }
  return isEven
      ? const Color.fromRGBO(48, 62, 82, 0.38)
      : const Color.fromRGBO(34, 48, 68, 0.34);
}

Color _timelineAutomationLaneFillColor(bool isEven) {
  if (!PlatformCapabilities.current.isDesktop) {
    return isEven ? const Color(0xFF1B1F24) : const Color(0xFF171B20);
  }
  return isEven
      ? const Color.fromRGBO(18, 31, 46, 0.34)
      : const Color.fromRGBO(12, 25, 40, 0.30);
}

Color _timelineExpandedFillColor() {
  if (!PlatformCapabilities.current.isDesktop) {
    return const Color(0xFF1A1D22).withValues(alpha: 0.94);
  }
  return const Color.fromRGBO(29, 44, 65, 0.46);
}

class _EditorLayoutSpec {
  final double bottomInteractionPadding;

  const _EditorLayoutSpec({required this.bottomInteractionPadding});

  factory _EditorLayoutSpec.fromSize(Size size) {
    final isDesktop = PlatformCapabilities.current.isDesktop;
    final width = size.width;
    if (!isDesktop) {
      return const _EditorLayoutSpec(bottomInteractionPadding: 191.0);
    }
    if (width >= 1700) {
      return const _EditorLayoutSpec(bottomInteractionPadding: 128.0);
    }
    if (width >= 1360) {
      return const _EditorLayoutSpec(bottomInteractionPadding: 116.0);
    }
    return const _EditorLayoutSpec(bottomInteractionPadding: 104.0);
  }
}

extension _TimelineToolUi on _TimelineTool {
  String get controllerLabel {
    switch (this) {
      case _TimelineTool.pencil:
        return 'Select';
      case _TimelineTool.stretch:
        return 'Stretch';
      case _TimelineTool.paint:
        return 'Paint';
      case _TimelineTool.cut:
        return 'Cut';
      case _TimelineTool.delete:
        return 'Delete';
    }
  }

  String label(BuildContext context) {
    switch (this) {
      case _TimelineTool.pencil:
        return L10n.translate(context, 'Select');
      case _TimelineTool.stretch:
        return L10n.translate(context, 'Stretch');
      case _TimelineTool.paint:
        return L10n.translate(context, 'Paint');
      case _TimelineTool.cut:
        return L10n.translate(context, 'Cut');
      case _TimelineTool.delete:
        return L10n.translate(context, 'Delete');
    }
  }

  IconData get icon {
    switch (this) {
      case _TimelineTool.pencil:
        return Icons.near_me_outlined;
      case _TimelineTool.stretch:
        return Icons.swap_horiz_rounded;
      case _TimelineTool.paint:
        return Icons.format_paint_outlined;
      case _TimelineTool.cut:
        return Icons.content_cut;
      case _TimelineTool.delete:
        return Icons.delete_outline;
    }
  }

  bool get flipHorizontally {
    switch (this) {
      case _TimelineTool.pencil:
        return true;
      case _TimelineTool.stretch:
      case _TimelineTool.paint:
      case _TimelineTool.cut:
      case _TimelineTool.delete:
        return false;
    }
  }
}

@immutable
class TimelineTopControlsState {
  final bool magnetEnabled;
  final int quantizeDivisionsPerBar;
  final String quantizeLabel;
  final String toolLabel;
  final IconData toolIcon;
  final bool toolIconFlipHorizontally;

  const TimelineTopControlsState({
    required this.magnetEnabled,
    required this.quantizeDivisionsPerBar,
    required this.quantizeLabel,
    required this.toolLabel,
    required this.toolIcon,
    required this.toolIconFlipHorizontally,
  });

  static const TimelineTopControlsState initial = TimelineTopControlsState(
    magnetEnabled: true,
    quantizeDivisionsPerBar: 4,
    quantizeLabel: '1/4',
    toolLabel: 'Select',
    toolIcon: Icons.near_me_outlined,
    toolIconFlipHorizontally: true,
  );
}

@immutable
class TimelineHorizontalScrollbarState {
  final bool visible;
  final double headerWidth;
  final double viewportWidth;
  final double thumbLeft;
  final double thumbWidth;
  final double thumbHeight;
  final double hitHeight;
  final double trackHeight;
  final double endInset;
  final bool dragging;
  final bool resizeStartActive;
  final bool resizeEndActive;

  const TimelineHorizontalScrollbarState({
    required this.visible,
    required this.headerWidth,
    required this.viewportWidth,
    required this.thumbLeft,
    required this.thumbWidth,
    required this.thumbHeight,
    required this.hitHeight,
    required this.trackHeight,
    required this.endInset,
    required this.dragging,
    required this.resizeStartActive,
    required this.resizeEndActive,
  });

  static const TimelineHorizontalScrollbarState hidden =
      TimelineHorizontalScrollbarState(
        visible: false,
        headerWidth: 0.0,
        viewportWidth: 0.0,
        thumbLeft: 0.0,
        thumbWidth: 0.0,
        thumbHeight: 12.0,
        hitHeight: 22.0,
        trackHeight: 4.0,
        endInset: 0.0,
        dragging: false,
        resizeStartActive: false,
        resizeEndActive: false,
      );

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TimelineHorizontalScrollbarState &&
            other.visible == visible &&
            other.headerWidth == headerWidth &&
            other.viewportWidth == viewportWidth &&
            other.thumbLeft == thumbLeft &&
            other.thumbWidth == thumbWidth &&
            other.thumbHeight == thumbHeight &&
            other.hitHeight == hitHeight &&
            other.trackHeight == trackHeight &&
            other.endInset == endInset &&
            other.dragging == dragging &&
            other.resizeStartActive == resizeStartActive &&
            other.resizeEndActive == resizeEndActive;
  }

  @override
  int get hashCode => Object.hash(
    visible,
    headerWidth,
    viewportWidth,
    thumbLeft,
    thumbWidth,
    thumbHeight,
    hitHeight,
    trackHeight,
    endInset,
    dragging,
    resizeStartActive,
    resizeEndActive,
  );
}

class AudioCanvasTimeline extends StatefulWidget {
  final AudioCanvasTimelineController? controller;
  final List<TimelineRow> rows;
  final List<TrackGroup> trackGroups;
  final List<AudioTrack> clips;
  final int clipTopologyRevision;
  final int clipLayoutRevision;
  final List<TimelineClipLayoutMutation> clipLayoutMutations;
  final int clipLayoutMutationFloorRevision;
  final int clipVisualRevision;
  final String clipOverlapMode;
  final List<double> rowGain;
  final List<double> rowPan;
  final List<bool> rowMuted;
  final List<bool> rowSoloed;
  final List<List<AutomationPoint>> rowVolumeAutomation;
  final List<Map<String, dynamic>> Function(int row) getAutomationTargetsForRow;
  final String Function(int row) getSelectedAutomationTargetId;
  final void Function(int row, String targetId) setSelectedAutomationTargetId;
  final List<AutomationPoint> Function(int row, String targetId)
  getAutomationPointsForTarget;
  final void Function(int row, String targetId, List<AutomationPoint> points)
  setAutomationPointsForTarget;
  final List<AutomationClipSnapshot> Function(int row, String targetId)
  getAutomationClipsForTarget;
  final void Function(
    int row,
    String targetId,
    List<AutomationClipSnapshot> clips,
  )
  setAutomationClipsForTarget;
  final void Function(
    int row,
    String targetId,
    List<AutomationPoint> oldPoints,
    List<AutomationPoint> newPoints,
  )?
  onAutomationTargetCommit;
  final void Function(
    int row,
    String targetId,
    List<AutomationClipSnapshot> oldClips,
    List<AutomationClipSnapshot> newClips,
  )?
  onAutomationClipsCommit;
  final Future<void> Function(int row, String targetId)?
  onRevealAutomationTarget;

  final double Function(AudioTrack) getStartMs;
  final double Function(AudioTrack)
  getDurationMs; // Should be: (trimEnd - trimStart)
  final double Function(AudioTrack) getTimelineDurationMs;
  final double Function(AudioTrack) getTrimStartMs;
  final double Function(AudioTrack) getTrimEndMs;
  final double Function(AudioTrack)
  getFullDurationMs; // === FIX ===: Added this helper
  final List<double> Function(AudioTrack) getPeaks;
  final double Function(AudioTrack) getY; // This doesn't seem to be used?
  final void Function(int row) onSelectRow;
  final void Function(int row) onToggleExpanded;
  final Future<void> Function() onAddRow;
  final Future<void> Function()? onAddInstrumentLane;
  final Future<void> Function()? onOpenCaptureDeck;
  final Future<void> Function()? onGroupRowsPressed;
  final VoidCallback? onCancelRowGroupingPressed;
  final Future<void> Function(int row) onInsertRowAbove;
  final Future<void> Function(int row) onInsertRowBelow;
  final Future<void> Function(int row)? onInsertInstrumentLaneAbove;
  final Future<void> Function(int row)? onInsertInstrumentLaneBelow;
  final Future<void> Function(int row)? onChangeInstrumentLane;
  final Future<void> Function(int row) onDeleteRow;
  final Future<void> Function(int fromIndex, int toIndex) onMoveRow;
  final Future<void> Function(int row, String name) onRenameRow;
  final Future<void> Function(String groupId, String name)? onRenameRowGroup;
  final Future<void> Function(int row, int iconId) onSetRowIcon;
  final Future<void> Function(int row, int color)? onSetRowColor;
  final Future<void> Function(List<int> rows)? onCreateRowGroup;
  final Future<void> Function(int row)? onRemoveRowFromGroup;
  final Future<void> Function(String groupId)? onToggleRowGroupCollapsed;
  final bool rowGroupingSelectionMode;
  final Set<int> groupingSelectedRows;
  final void Function(int row)? onToggleGroupingRowSelection;
  final Future<void> Function(int clipIndex, double newStartMs, int newRowIndex)
  onMoveClipCommit;
  final Future<void> Function(List<TimelineClipMoveRequest> moves)?
  onMoveClipsCommit;
  final void Function(
    int clipIndex,
    double trimStartMs,
    double trimEndMs, {
    double? newStartMs,
  })
  onTrimClip;
  final void Function(
    int clipIndex,
    double trimStartMs,
    double trimEndMs,
    double oldTrimStart,
    double oldTrimEnd,
    double oldOffset, {
    double? newStartMs,
  })
  onTrimClipCommit;
  final ValueListenable<Duration> transportClockListenable;
  final void Function(double ms) onScrubRequested;
  final bool isPlaying;
  final Duration maxDuration;
  final double bpm;
  final int beatsPerBar;
  final int beatUnit;
  final double height;
  final bool isRecording;
  final int? recordingRowIndex;
  final double recordingStartMs;
  final List<double> recordingPeaks;
  final List<double> recordingPeakTimesMs;
  final bool recordingInProgress; // sent from above if user is recording
  final int selectedClipIndex;
  final List<int> selectedClipIndices;

  // === Row FX callbacks ===
  final Future<List<String>> Function(int row) getRowEffects;
  final Future<List<String>> Function(int row) getRowEffectIds;
  final Future<bool> Function(int row, int effectIndex) getRowEffectBypassState;
  final Future<void> Function(int row, String pathOrName) insertRowEffect;
  final Future<void> Function(
    int row,
    int effectIndex,
    String name,
    bool applyingPreset,
  )
  removeRowEffect;
  final Future<void> Function(int row, int from, int to) reorderRowEffects;
  final Future<void> Function(int row, int effectIndex, bool bypass)
  setRowEffectBypassed;
  final Future<List<Map<String, dynamic>>> Function(int row, int effectIndex)
  getRowPluginParameters;
  final Future<void> Function(
    int row,
    int effectIndex,
    String paramId,
    dynamic value,
  )
  setRowEffectParam;
  final Future<List<Map<String, dynamic>>> Function() scanPlugins;
  final Future<void> Function(String pluginId)? onTogglePluginFavorite;
  final Future<void> Function()? onManagePlugins;
  final Future<bool> Function(int row, int effectIndex)? openTrackPluginEditor;
  final Future<void> Function(int row, List<Map<String, dynamic>> points)
  setTrackAutomationPoints;
  final void Function(
    int row,
    List<AutomationPoint> oldPoints,
    List<AutomationPoint> newPoints,
  )?
  onAutomationCommit;
  final Future<void> Function(int row, double gain) setRowGain;
  final Future<void> Function(int row, bool mute) muteRow;
  final Future<void> Function(int row, bool solo) soloRow;
  final void Function(int row, double oldGain, double newGain)? onRowGainCommit;
  final Future<void> Function(int row, double pan) setRowPan;
  final void Function(int row, double oldPan, double newPan)? onRowPanCommit;
  final Future<void> Function(int clipIndex, double gain) setClipGain;
  final void Function(int clipIndex, double oldGain, double newGain)?
  onClipGainCommit;
  final Future<void> Function(int clipIndex, bool normalizeVolume)?
  onToggleClipNormalize;
  final Future<void> Function(int clipIndex, double semitones) setClipPitch;
  final void Function(int clipIndex, double oldPitch, double newPitch)?
  onClipPitchCommit;
  final Future<void> Function(int clipIndex, bool reversed)? onSetClipReversed;
  final Future<void> Function(int clipIndex) onDisableClipTempoFollow;
  final Future<void> Function(int clipIndex) onAdjustClipToTempo;
  final Future<void> Function(int clipIndex) onStretchClipToTempoPreservePitch;
  final Future<void> Function(int clipIndex)
  onDetectClipTempoAndSetProjectTempo;
  final Future<void> Function(int clipIndex)? onOpenPitchLab;
  final void Function(
    int clipIndex,
    double newTimelineDurationMs, {
    double? newStartMs,
  })
  onStretchClip;
  final Future<void> Function(int clipIndex) onStretchClipCommit;
  final Future<void> Function(int clipIndex, String label)? onRenameClip;
  final void Function(int clipIndex)? onOpenAudioClipOptionsPanel;
  final Future<void> Function(int clipIndex)? onCreateSamplerFromClip;
  final bool Function(int clipIndex)? canReplaceSamplerSource;
  final Future<void> Function(int clipIndex)? onReplaceSamplerSource;
  final void Function(int clipIndex) onCopyClip;
  final Future<void> Function(int clipIndex) onDeleteClip;
  final Future<void> Function(int clipIndex, double startMs)?
  onStartClipLoopPreview;
  final Future<void> Function(int clipIndex, double startMs)?
  onSeekClipLoopPreview;
  final Future<void> Function()? onStopClipLoopPreview;
  final bool hasCopiedClip;
  final bool Function(int row)? canPasteClipAtRow;
  final Future<bool> Function(int row, double timeMs) onPasteClipAt;
  final VoidCallback? onClearCopiedClip;
  final void Function(List<int> clipIndices)? onCopyClips;
  final Future<bool> Function(List<int> clipIndices, double pasteStartMs)?
  onStepDuplicateClips;
  final DesktopShortcutBinding? copyClipsShortcutBinding;
  final DesktopShortcutBinding? pasteClipsShortcutBinding;
  final DesktopShortcutBinding? stepDuplicateClipsShortcutBinding;
  final List<DesktopShortcutBinding>? toolShortcutBindings;
  final Future<void> Function(List<int> clipIndices)? onDeleteClips;
  final Future<void> Function(int clipIndex, double cutTimeMs)? onCutClipAt;
  final Future<void> Function(List<int> clipIndices)? onGlueClips;
  final void Function(int clipIndex)? onOpenMidiClip;
  final bool Function(int clipIndex)? canOpenMidiInstrumentUi;
  final Future<bool> Function(int clipIndex)? onOpenMidiInstrumentUi;
  final Future<void> Function(int row, double timeMs)?
  onCreateMidiClipInInstrumentLane;
  final Future<void> Function(int clipIndex)? onStemSeparation;
  final void Function(List<int> selectedClipIndices, int primaryClipIndex)?
  onSelectionChanged;
  final void Function(int loopStartMs, int loopEndMs)? onLoopRegionChanged;
  final void Function(bool enabled)? onLoopToggle;
  final bool loopEnabled;
  final int loopStartMs;
  final int loopEndMs;
  final void Function(
    int row,
    int effectIndex,
    String paramId,
    dynamic oldValue,
    dynamic newValue,
  )?
  onPluginParamCommit;
  final void Function(RowEffectsSnapshot before, RowEffectsSnapshot after)?
  onPresetCommit;
  final void Function(int row, int effectIndex)? onRowEffectSelected;
  final int? selectedRowEffectRow;
  final int? selectedRowEffectIndex;
  final VoidCallback? onCopyRowEffects;
  final Future<void> Function(int row)? onPasteRowEffects;
  final Future<void> Function(int row)? onClearRowEffects;
  final bool hasCopiedRowEffects;
  final void Function(void Function(int row) refreshRowFx)?
  registerRowFxRefresher;
  final void Function(void Function(int row) refreshRowFxPlayback)?
  registerRowFxPlaybackRefresher;
  final void Function(bool magnetEnabled, int quantizeDivisionsPerBar)?
  onSnapSettingsChanged;
  final VoidCallback? onTutorialTimelineScrolled;
  final VoidCallback? onTutorialTimelineZoomed;
  final void Function(int row, bool expanded)? onRowExpansionChanged;
  final void Function(int row, int tab)? onRowTabSelected;
  final void Function(int row, bool expanded)? onTutorialRowExpansionChanged;
  final void Function(int row, int tab)? onTutorialRowTabSelected;
  final void Function(int row, int effectIndex, String effectName)?
  onTutorialRowEffectAdded;
  final void Function(int row, int effectIndex, String effectName)?
  onTutorialRowEffectOpened;

  final MeterBus meters;
  final Future<List<double>> Function(int row, int effectIndex)
  getRowCompressorMeter;
  final Future<List<double>> Function(int row, int effectIndex, int sampleCount)
  getRowEqWaveform;
  final Future<List<double>> Function(int row, int effectIndex, int pointCount)
  getRowStereoScope;
  final Future<void> Function(SampleDragData data, int row, double timeMs)?
  onExternalSampleDrop;
  final VoidCallback? onExternalSampleDragEntered;
  final bool externalSampleDragActive;
  final MixChangeHighlighter? tutorialHighlighter;
  final double bottomDockInset;
  final bool allPluginsEntitled;
  final VoidCallback? onUpgradeRequested;
  final bool useTabletDawLayout;
  final double? tabletSidePanelWidth;
  final bool allowMultipleExpandedRows;
  final bool expandRowsOnTrackSelect;
  final String? Function(int row)? frozenRowDescription;
  final void Function(int row)? onFrozenRowInfoPressed;

  final String mode; // "Basic" or "Pro"

  const AudioCanvasTimeline({
    Key? key,
    this.controller,
    required this.rows,
    this.trackGroups = const <TrackGroup>[],
    required this.rowGain,
    required this.rowPan,
    required this.rowMuted,
    required this.rowSoloed,
    required this.rowVolumeAutomation,
    required this.getAutomationTargetsForRow,
    required this.getSelectedAutomationTargetId,
    required this.setSelectedAutomationTargetId,
    required this.getAutomationPointsForTarget,
    required this.setAutomationPointsForTarget,
    required this.getAutomationClipsForTarget,
    required this.setAutomationClipsForTarget,
    required this.onAutomationTargetCommit,
    this.onAutomationClipsCommit,
    this.onRevealAutomationTarget,
    required this.clips,
    this.clipTopologyRevision = -1,
    this.clipLayoutRevision = -1,
    this.clipLayoutMutations = const <TimelineClipLayoutMutation>[],
    this.clipLayoutMutationFloorRevision = -1,
    this.clipVisualRevision = -1,
    required this.clipOverlapMode,
    required this.getStartMs,
    required this.getDurationMs,
    required this.getTimelineDurationMs,
    required this.getTrimStartMs,
    required this.getTrimEndMs,
    required this.getFullDurationMs, // === FIX ===
    required this.getPeaks,
    required this.getY,
    required this.onSelectRow,
    required this.recordingInProgress,
    required this.onToggleExpanded,
    required this.onAddRow,
    this.onAddInstrumentLane,
    this.onOpenCaptureDeck,
    this.onGroupRowsPressed,
    this.onCancelRowGroupingPressed,
    required this.onInsertRowAbove,
    required this.onInsertRowBelow,
    this.onInsertInstrumentLaneAbove,
    this.onInsertInstrumentLaneBelow,
    this.onChangeInstrumentLane,
    required this.onDeleteRow,
    required this.onMoveRow,
    required this.onRenameRow,
    this.onRenameRowGroup,
    required this.onSetRowIcon,
    this.onSetRowColor,
    this.onCreateRowGroup,
    this.onRemoveRowFromGroup,
    this.onToggleRowGroupCollapsed,
    this.rowGroupingSelectionMode = false,
    this.groupingSelectedRows = const <int>{},
    this.onToggleGroupingRowSelection,
    required this.onMoveClipCommit,
    this.onMoveClipsCommit,
    required this.onTrimClip,
    required this.onTrimClipCommit,
    required this.transportClockListenable,
    required this.onScrubRequested,
    required this.isPlaying,
    required this.maxDuration,
    required this.bpm,
    required this.beatsPerBar,
    this.beatUnit = 4,
    this.height = 520,
    required this.isRecording,
    required this.recordingRowIndex,
    required this.recordingStartMs,
    required this.recordingPeaks,
    this.recordingPeakTimesMs = const <double>[],
    this.selectedClipIndex = -1,
    this.selectedClipIndices = const <int>[],
    required this.getRowEffects,
    required this.getRowEffectIds,
    required this.getRowEffectBypassState,
    required this.insertRowEffect,
    required this.removeRowEffect,
    required this.reorderRowEffects,
    required this.setRowEffectBypassed,
    required this.getRowPluginParameters,
    required this.setRowEffectParam,
    required this.scanPlugins,
    this.onTogglePluginFavorite,
    this.onManagePlugins,
    this.openTrackPluginEditor,
    required this.setTrackAutomationPoints,
    required this.onAutomationCommit,
    required this.setRowGain,
    required this.onRowGainCommit,
    required this.muteRow,
    required this.soloRow,
    required this.setRowPan,
    required this.onRowPanCommit,
    required this.setClipGain,
    required this.onClipGainCommit,
    this.onToggleClipNormalize,
    required this.setClipPitch,
    required this.onClipPitchCommit,
    this.onSetClipReversed,
    required this.onDisableClipTempoFollow,
    required this.onAdjustClipToTempo,
    required this.onStretchClipToTempoPreservePitch,
    required this.onDetectClipTempoAndSetProjectTempo,
    this.onOpenPitchLab,
    required this.onStretchClip,
    required this.onStretchClipCommit,
    this.onRenameClip,
    this.onOpenAudioClipOptionsPanel,
    this.onCreateSamplerFromClip,
    this.canReplaceSamplerSource,
    this.onReplaceSamplerSource,
    required this.onCopyClip,
    required this.onDeleteClip,
    this.onStartClipLoopPreview,
    this.onSeekClipLoopPreview,
    this.onStopClipLoopPreview,
    required this.hasCopiedClip,
    this.canPasteClipAtRow,
    required this.onPasteClipAt,
    this.onClearCopiedClip,
    this.onCopyClips,
    this.onStepDuplicateClips,
    this.copyClipsShortcutBinding,
    this.pasteClipsShortcutBinding,
    this.stepDuplicateClipsShortcutBinding,
    this.toolShortcutBindings,
    this.onDeleteClips,
    this.onCutClipAt,
    this.onGlueClips,
    this.onOpenMidiClip,
    this.canOpenMidiInstrumentUi,
    this.onOpenMidiInstrumentUi,
    this.onCreateMidiClipInInstrumentLane,
    this.onStemSeparation,
    this.onSelectionChanged,
    this.onLoopRegionChanged,
    this.onLoopToggle,
    this.loopEnabled = false,
    this.loopStartMs = 0,
    this.loopEndMs = 0,
    required this.mode,
    this.onPluginParamCommit,
    this.onPresetCommit,
    this.onRowEffectSelected,
    this.selectedRowEffectRow,
    this.selectedRowEffectIndex,
    this.onCopyRowEffects,
    this.onPasteRowEffects,
    this.onClearRowEffects,
    this.hasCopiedRowEffects = false,
    this.registerRowFxRefresher,
    this.registerRowFxPlaybackRefresher,
    this.onSnapSettingsChanged,
    this.onTutorialTimelineScrolled,
    this.onTutorialTimelineZoomed,
    this.onRowExpansionChanged,
    this.onRowTabSelected,
    this.onTutorialRowExpansionChanged,
    this.onTutorialRowTabSelected,
    this.onTutorialRowEffectAdded,
    this.onTutorialRowEffectOpened,
    required this.meters,
    required this.getRowCompressorMeter,
    required this.getRowEqWaveform,
    required this.getRowStereoScope,
    this.onExternalSampleDrop,
    this.onExternalSampleDragEntered,
    this.externalSampleDragActive = false,
    this.tutorialHighlighter,
    this.bottomDockInset = 0.0,
    this.allPluginsEntitled = true,
    this.onUpgradeRequested,
    this.useTabletDawLayout = false,
    this.tabletSidePanelWidth,
    this.allowMultipleExpandedRows = true,
    this.expandRowsOnTrackSelect = true,
    this.frozenRowDescription,
    this.onFrozenRowInfoPressed,
  }) : super(key: key);
  @override
  State<AudioCanvasTimeline> createState() => _AudioCanvasTimelineState();
}

class AudioCanvasTimelineController {
  void Function(int row, {int tab})? _ensureRowExpanded;
  void Function(String targetId)? _showMasterAutomationLane;
  VoidCallback? _closeMasterAutomationLane;
  VoidCallback? _collapseExpandedRows;
  VoidCallback? _copySelectedClips;
  VoidCallback? _pasteCopiedClipsAfterSelection;
  VoidCallback? _toggleMagnet;
  Future<void> Function({Rect? anchorRect})? _showToolMenu;
  Future<void> Function({Rect? anchorRect})? _showQuantizeMenu;
  VoidCallback? _publishTopControlsState;
  void Function(double localX)? _beginHorizontalScrollbarDrag;
  void Function(double deltaX)? _dragHorizontalScrollbarBy;
  VoidCallback? _endHorizontalScrollbarDrag;
  void Function(double localX)? _jumpHorizontalScrollbarTo;
  void Function(Offset globalOffset, {SampleDragData? data})?
  _updateExternalSampleDropPreview;
  VoidCallback? _clearExternalSampleDropPreview;
  SampleDropPlacement? Function(Offset globalOffset, {SampleDragData? data})?
  _placementForExternalSampleDrop;
  final ValueNotifier<TimelineTopControlsState> _topControls =
      ValueNotifier<TimelineTopControlsState>(TimelineTopControlsState.initial);
  final ValueNotifier<TimelineHorizontalScrollbarState> _horizontalScrollbar =
      ValueNotifier<TimelineHorizontalScrollbarState>(
        TimelineHorizontalScrollbarState.hidden,
      );

  ValueListenable<TimelineTopControlsState> get topControlsListenable =>
      _topControls;

  TimelineTopControlsState get topControlsState => _topControls.value;

  ValueListenable<TimelineHorizontalScrollbarState>
  get horizontalScrollbarListenable => _horizontalScrollbar;

  TimelineHorizontalScrollbarState get horizontalScrollbarState =>
      _horizontalScrollbar.value;

  void _bind({
    required void Function(int row, {int tab}) ensureRowExpanded,
    required void Function(String targetId) showMasterAutomationLane,
    required VoidCallback closeMasterAutomationLane,
    required VoidCallback collapseExpandedRows,
    required VoidCallback copySelectedClips,
    required VoidCallback pasteCopiedClipsAfterSelection,
    required VoidCallback toggleMagnet,
    required Future<void> Function({Rect? anchorRect}) showToolMenu,
    required Future<void> Function({Rect? anchorRect}) showQuantizeMenu,
    required VoidCallback publishTopControlsState,
    required void Function(double localX) beginHorizontalScrollbarDrag,
    required void Function(double deltaX) dragHorizontalScrollbarBy,
    required VoidCallback endHorizontalScrollbarDrag,
    required void Function(double localX) jumpHorizontalScrollbarTo,
    required void Function(Offset globalOffset, {SampleDragData? data})
    updateExternalSampleDropPreview,
    required VoidCallback clearExternalSampleDropPreview,
    required SampleDropPlacement? Function(
      Offset globalOffset, {
      SampleDragData? data,
    })
    placementForExternalSampleDrop,
  }) {
    _ensureRowExpanded = ensureRowExpanded;
    _showMasterAutomationLane = showMasterAutomationLane;
    _closeMasterAutomationLane = closeMasterAutomationLane;
    _collapseExpandedRows = collapseExpandedRows;
    _copySelectedClips = copySelectedClips;
    _pasteCopiedClipsAfterSelection = pasteCopiedClipsAfterSelection;
    _toggleMagnet = toggleMagnet;
    _showToolMenu = showToolMenu;
    _showQuantizeMenu = showQuantizeMenu;
    _publishTopControlsState = publishTopControlsState;
    _beginHorizontalScrollbarDrag = beginHorizontalScrollbarDrag;
    _dragHorizontalScrollbarBy = dragHorizontalScrollbarBy;
    _endHorizontalScrollbarDrag = endHorizontalScrollbarDrag;
    _jumpHorizontalScrollbarTo = jumpHorizontalScrollbarTo;
    _updateExternalSampleDropPreview = updateExternalSampleDropPreview;
    _clearExternalSampleDropPreview = clearExternalSampleDropPreview;
    _placementForExternalSampleDrop = placementForExternalSampleDrop;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishTopControlsState?.call();
    });
  }

  void _unbind({
    required void Function(int row, {int tab}) ensureRowExpanded,
    required void Function(String targetId) showMasterAutomationLane,
    required VoidCallback closeMasterAutomationLane,
    required VoidCallback collapseExpandedRows,
    required VoidCallback copySelectedClips,
    required VoidCallback pasteCopiedClipsAfterSelection,
    required VoidCallback toggleMagnet,
    required Future<void> Function({Rect? anchorRect}) showToolMenu,
    required Future<void> Function({Rect? anchorRect}) showQuantizeMenu,
    required VoidCallback publishTopControlsState,
    required void Function(double localX) beginHorizontalScrollbarDrag,
    required void Function(double deltaX) dragHorizontalScrollbarBy,
    required VoidCallback endHorizontalScrollbarDrag,
    required void Function(double localX) jumpHorizontalScrollbarTo,
    required void Function(Offset globalOffset, {SampleDragData? data})
    updateExternalSampleDropPreview,
    required VoidCallback clearExternalSampleDropPreview,
    required SampleDropPlacement? Function(
      Offset globalOffset, {
      SampleDragData? data,
    })
    placementForExternalSampleDrop,
  }) {
    if (identical(_ensureRowExpanded, ensureRowExpanded)) {
      _ensureRowExpanded = null;
    }
    if (identical(_showMasterAutomationLane, showMasterAutomationLane)) {
      _showMasterAutomationLane = null;
    }
    if (identical(_closeMasterAutomationLane, closeMasterAutomationLane)) {
      _closeMasterAutomationLane = null;
    }
    if (identical(_collapseExpandedRows, collapseExpandedRows)) {
      _collapseExpandedRows = null;
    }
    if (identical(_copySelectedClips, copySelectedClips)) {
      _copySelectedClips = null;
    }
    if (identical(
      _pasteCopiedClipsAfterSelection,
      pasteCopiedClipsAfterSelection,
    )) {
      _pasteCopiedClipsAfterSelection = null;
    }
    if (identical(_toggleMagnet, toggleMagnet)) {
      _toggleMagnet = null;
    }
    if (identical(_showToolMenu, showToolMenu)) {
      _showToolMenu = null;
    }
    if (identical(_showQuantizeMenu, showQuantizeMenu)) {
      _showQuantizeMenu = null;
    }
    if (identical(_publishTopControlsState, publishTopControlsState)) {
      _publishTopControlsState = null;
    }
    if (identical(
      _beginHorizontalScrollbarDrag,
      beginHorizontalScrollbarDrag,
    )) {
      _beginHorizontalScrollbarDrag = null;
    }
    if (identical(_dragHorizontalScrollbarBy, dragHorizontalScrollbarBy)) {
      _dragHorizontalScrollbarBy = null;
    }
    if (identical(_endHorizontalScrollbarDrag, endHorizontalScrollbarDrag)) {
      _endHorizontalScrollbarDrag = null;
    }
    if (identical(_jumpHorizontalScrollbarTo, jumpHorizontalScrollbarTo)) {
      _jumpHorizontalScrollbarTo = null;
    }
    if (identical(
      _updateExternalSampleDropPreview,
      updateExternalSampleDropPreview,
    )) {
      _updateExternalSampleDropPreview = null;
    }
    if (identical(
      _clearExternalSampleDropPreview,
      clearExternalSampleDropPreview,
    )) {
      _clearExternalSampleDropPreview = null;
    }
    if (identical(
      _placementForExternalSampleDrop,
      placementForExternalSampleDrop,
    )) {
      _placementForExternalSampleDrop = null;
    }
  }

  void ensureRowExpanded(int row, {int tab = 0}) {
    _ensureRowExpanded?.call(row, tab: tab);
  }

  void showMasterAutomationLane(String targetId) {
    _showMasterAutomationLane?.call(targetId);
  }

  void closeMasterAutomationLane() {
    _closeMasterAutomationLane?.call();
  }

  void collapseExpandedRows() {
    _collapseExpandedRows?.call();
  }

  void copySelectedClips() {
    _copySelectedClips?.call();
  }

  void pasteCopiedClipsAfterSelection() {
    _pasteCopiedClipsAfterSelection?.call();
  }

  void toggleMagnet() {
    _toggleMagnet?.call();
  }

  Future<void> showToolMenu({Rect? anchorRect}) async {
    await _showToolMenu?.call(anchorRect: anchorRect);
  }

  Future<void> showQuantizeMenu({Rect? anchorRect}) async {
    await _showQuantizeMenu?.call(anchorRect: anchorRect);
  }

  void _setTopControlsState(TimelineTopControlsState state) {
    _topControls.value = state;
  }

  void beginHorizontalScrollbarDrag(double localX) {
    _beginHorizontalScrollbarDrag?.call(localX);
  }

  void dragHorizontalScrollbarBy(double deltaX) {
    _dragHorizontalScrollbarBy?.call(deltaX);
  }

  void endHorizontalScrollbarDrag() {
    _endHorizontalScrollbarDrag?.call();
  }

  void jumpHorizontalScrollbarTo(double localX) {
    _jumpHorizontalScrollbarTo?.call(localX);
  }

  void updateExternalSampleDropPreview(
    Offset globalOffset, {
    SampleDragData? data,
  }) {
    _updateExternalSampleDropPreview?.call(globalOffset, data: data);
  }

  void clearExternalSampleDropPreview() {
    _clearExternalSampleDropPreview?.call();
  }

  SampleDropPlacement? placementForExternalSampleDrop(
    Offset globalOffset, {
    SampleDragData? data,
  }) {
    return _placementForExternalSampleDrop?.call(globalOffset, data: data);
  }

  void _setHorizontalScrollbarState(TimelineHorizontalScrollbarState state) {
    if (_horizontalScrollbar.value == state) return;
    _horizontalScrollbar.value = state;
  }

  void dispose() {
    _topControls.dispose();
    _horizontalScrollbar.dispose();
  }
}

class _TimelineNameInputDialog extends StatefulWidget {
  const _TimelineNameInputDialog({
    required this.title,
    required this.initialName,
    required this.hintText,
    required this.maxLength,
  });

  final String title;
  final String initialName;
  final String hintText;
  final int maxLength;

  @override
  State<_TimelineNameInputDialog> createState() =>
      _TimelineNameInputDialogState();
}

class _TimelineNameInputDialogState extends State<_TimelineNameInputDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closing || !_focusNode.canRequestFocus) return;
      _focusNode.requestFocus();
    });
  }

  void _close(String? result) {
    if (_closing) return;
    _closing = true;
    _focusNode.unfocus();
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: MixroomShellDialog(
        alignment: Alignment.topCenter,
        insetPadding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
        radius: 24,
        color: const Color.fromRGBO(26, 38, 56, 0.92),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: const Icon(
                    Icons.drive_file_rename_outline,
                    color: Color(0xFFF4F4F4),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Color(0xFFF4F4F4),
                      fontSize: 17,
                      height: 22 / 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            MixroomShellSurface(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              color: const Color.fromRGBO(244, 244, 244, 0.10),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: false,
                maxLength: widget.maxLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _close(_controller.text.trim()),
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFFF4F4F4),
                  fontSize: 15,
                  height: 22 / 15,
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    fontFamily: 'Pretendard',
                    color: Colors.white.withValues(alpha: 0.48),
                    fontSize: 15,
                    height: 22 / 15,
                  ),
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 112,
                  child: MixroomShellDialogButton(
                    label: L10n.translate(context, 'Cancel'),
                    onPressed: () => _close(null),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 112,
                  child: MixroomShellDialogButton(
                    label: L10n.translate(context, 'Save'),
                    accent: true,
                    onPressed: () => _close(_controller.text.trim()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioCanvasTimelineState extends State<AudioCanvasTimeline> {
  static const double kRowHeight = 80.0;
  static const double kExpandedRowHeight =
      (kRowHeight * 3) +
      40.0; // keep extra headroom to avoid expanded-tab vertical overflow
  // Effects panel min height should be driven by left header content.
  static const double _kHeaderTabButtonHeight = 34.0;
  static const double _kHeaderTabGap = 6.0;
  static const double _kHeaderMeterHeight = 82.0;
  static const double _kHeaderDbfsReadoutHeight = 30.0;
  static const double _kHeaderDbfsReadoutGap = 6.0;
  static const double _kHeaderBottomPadding = 24.0;
  static const double _kHeaderTabsMinHeight =
      12.0 + // top spacers
      8.0 + // vertical padding around tab stack
      (_kHeaderTabButtonHeight * 3.0) +
      (_kHeaderTabGap * 2.0) +
      8.0 + // meter top spacing
      _kHeaderMeterHeight +
      _kHeaderDbfsReadoutGap +
      _kHeaderDbfsReadoutHeight +
      _kHeaderBottomPadding;
  static const Duration _kHeaderPeakHoldFreeze = Duration(milliseconds: 900);
  static const double _kHeaderPeakHoldDecayDbPerSec = 11.0;
  static const double kHeaderFooterHeight = 44.0;
  static const double _kTabletStickyFooterHeight = 96.0;
  static const double _kTabletStickyFooterBottomInset = 10.0;
  static const double _kTabletStickyFooterTotalHeight =
      _kTabletStickyFooterHeight + _kTabletStickyFooterBottomInset;
  static const double _kTabletRailTopInset = 10.0;
  static const double _kTabletFooterControlsBottomPadding =
      3.0 + _kTabletStickyFooterBottomInset;
  static const double _kTabletFooterButtonHeight = 38.0;
  static const double _kTabletFooterRowGap = 6.0;
  static const double _kTabletRowHeightMax = 84.0;
  static const double _kTabletRowHeightMinScale = 0.62;
  static const double _kTabletRowHeightMaxScale = 1.0;
  static const double _kTabletRailWheelResizeSensitivity = 0.0015;
  static const double _kTabletHeaderLedgeX = 27.0;
  static const double _kTabletRailCenterX = _kTabletHeaderLedgeX / 2.0;
  static const Color _kTabletRailLaneColor = Color.fromRGBO(17, 64, 103, 0.84);
  static const double _kTabletEffectsPanelMinHeight = 176.0;
  static const double kBottomInteractionPadding = 96.0;
  static const double _kExtraAddRowBottomPadding = 18.0;
  static const double _kAddRowPillHeight = 50.0;
  static const double _kAddRowSectionGap = 16.0;
  final List<double> _effectsPanelHeights = <double>[];
  final Map<int, double> _headerPeakHoldDbByRowId = <int, double>{};
  final Map<int, DateTime> _headerPeakHoldLastUpdateByRowId = <int, DateTime>{};
  final Map<int, DateTime> _headerPeakHoldFreezeUntilByRowId =
      <int, DateTime>{};
  _EditorLayoutSpec _editorLayoutSpec = const _EditorLayoutSpec(
    bottomInteractionPadding: kBottomInteractionPadding,
  );

  static const double kHeaderWidth = 80.0;
  static const double kTimelineUnderlayLeft = 44.0;
  static const double kRulerHeight = 40.0;
  static const double _kDesktopRulerExtraHeight = 6.0;
  static const double _kDesktopRulerContentYOffset = 5.0;
  static const double kTrimHandleWidth = 14.0;
  static const double kTrimHandleGap = 8.0;
  static const double kTrimHandleVerticalInset = 5.0;
  static const double kTrimHandleOuterHitboxPadding = 10.0;
  static const double kTrimHandleInnerHitboxPadding = 2.0;
  static const double _kTimelineAutomationLaneInset = 2.0;
  static const double _kTimelineAutomationLaneGap = 2.0;
  static const double _kTimelineAutomationLaneExpandedHeight =
      kRowHeight - (_kTimelineAutomationLaneInset * 2.0);
  static const double _kTimelineAutomationLaneCollapsedHeight = 20.0;
  static const double _kMasterAutomationLaneMinHeight = 312.0;
  static const double _kMacWheelZoomSensitivity = 0.0025;
  static const double _kMinTimelinePixelsPerMs = 0.001;
  static const double _kMaxTimelinePixelsPerMs = 1.0;
  static const double _kHorizontalScrollbarHeight = 12.0;
  static const double _kHorizontalScrollbarActiveHeight = 15.0;
  static const double _kHorizontalScrollbarHitHeight = 22.0;
  static const double _kHorizontalScrollbarTrackHeight = 4.0;
  static const double _kHorizontalScrollbarActiveTrackHeight = 6.0;
  static const double _kHorizontalScrollbarEndInset = 10.0;
  static const double _kHorizontalScrollbarEdgeHitZone = 14.0;
  static const double _kHorizontalScrollbarResizeSensitivity = 0.006;
  static const double _kHorizontalScrollbarComfortMinThumbWidth = 72.0;
  static const double _kHorizontalScrollbarZoomedMinThumbWidth = 36.0;
  static const double _kHorizontalScrollbarMinShrinkStartPixelsPerMs = 0.12;
  static const double _kHorizontalScrollbarMinShrinkEndPixelsPerMs = 0.45;
  static const double _kTrackpadHorizontalInertiaMinTravelPx = 44.0;
  static const double _kTrackpadHorizontalInertiaMinVelocityPxPerSecond = 260.0;
  late final FocusNode _timelineFocusNode;
  bool get _usesTabletDawLayout => widget.useTabletDawLayout;
  bool get _usesDesktopOrTabletDawLayout =>
      _usesTabletDawLayout || PlatformCapabilities.current.isDesktop;
  bool get _allowsMultipleExpandedRows =>
      _usesDesktopOrTabletDawLayout && widget.allowMultipleExpandedRows;
  double get _rowHeight => _usesTabletDawLayout
      ? _kTabletRowHeightMax * _tabletRowHeightScale
      : kRowHeight;
  double get _expandedRowHeight => (_rowHeight * 3.0) + 40.0;
  double get _timeRulerHeight => PlatformCapabilities.current.isDesktop
      ? kRulerHeight + _kDesktopRulerExtraHeight
      : kRulerHeight;
  double get _timeRulerContentYOffset => PlatformCapabilities.current.isDesktop
      ? _kDesktopRulerContentYOffset
      : 0.0;
  double get _effectsPanelMinHeight => _usesTabletDawLayout
      ? _kTabletEffectsPanelMinHeight
      : math.max(_kHeaderTabsMinHeight, _expandedRowHeight);
  double get _headerWidth => _usesTabletDawLayout
      ? (widget.tabletSidePanelWidth ?? TabletDawPanelLayout.leftExpandedWidth)
            .clamp(144.0, TabletDawPanelLayout.leftExpandedWidth)
            .toDouble()
      : kHeaderWidth;
  double get _timelineUnderlayLeft =>
      _usesTabletDawLayout ? _headerWidth : kTimelineUnderlayLeft;
  double _pixelsPerMs = 0.1; // Initial zoom level
  double _scrollOffsetMs = 0.0;
  int _selectedClipIndex = -1;
  final Set<int> _selectedClipIndices = <int>{};
  int _clipVisualStackCounter = 0;
  final Map<String, int> _clipVisualStackOrder = <String, int>{};
  int _clipSpatialIndexTopologyRevision = -1;
  int _clipSpatialIndexRevision = -1;
  int _clipSpatialIndexClipCount = -1;
  Map<int, _TimelineClipRowSpatialIndex> _clipSpatialIndexByRow =
      const <int, _TimelineClipRowSpatialIndex>{};
  final HashMap<AudioTrack, int> _clipSpatialIndexByClip =
      HashMap<AudioTrack, int>.identity();
  final HashMap<AudioTrack, _TimelineClipSpatialEntry> _clipSpatialEntryByClip =
      HashMap<AudioTrack, _TimelineClipSpatialEntry>.identity();
  int _selectedRowIndex = 0;
  // final List<bool> _rowMuted = List.filled(kNumRows, false);
  final List<bool> _rowExpanded = <bool>[];
  final List<int> _expandedTab =
      <int>[]; // 0 = Volume, 1 = Effects, 2 = Automation
  final List<double> _rowYPositions = [];
  double? _tutorialPanStartScrollMs;
  double? _tutorialPanStartPixelsPerMs;
  bool _tutorialScrollNotifiedForGesture = false;
  bool _tutorialZoomNotifiedForGesture = false;

  // === FIX ===: Unified drag/trim state
  bool _isUserInteracting =
      false; // True if dragging clip, trimming, OR panning
  String _interactionMode = '';

  // Drag state
  int? _draggedClipIndex;
  double? _dragStartClipMs;
  int? _dragStartRow;
  double _dragDeltaMs = 0.0;
  int _dragDeltaRows = 0;
  bool _dragXAxisLocked = false;
  final Map<int, double> _dragGroupStartMs = <int, double>{};
  final Map<int, int> _dragGroupStartRows = <int, int>{};
  Offset? _dragStartLocalOffset; // Local position where drag started
  Offset?
  _dragStartGlobalOffset; // === FIX ===: Added for total vertical displacement tracking
  int? _timelineKeyboardModifierPointer;

  // Trim state
  int? _trimClipIndex;
  double? _trimStartValue; // Original trim value at drag start
  double? _trimEndValue; // Original trim value at drag start
  double? _trimOriginalStartMs; // Original clip startMs at drag start
  double?
  _trimStartAnchorX; // === FIX ===: Anchor: Local X of where the touch began
  double? _trimTimelineScaleValue; // Source ms -> visible timeline ms
  double?
  _activeTrimHandleX; // === FIX ===: The X anchor for the visual cue/tap
  double? newTrimStartUpdate, newTrimEndUpdate, newStartMsUpdate;
  int? _stretchClipIndex;
  double? _stretchStartTimelineDurationMs;
  double? _stretchOriginalStartMs;
  double? _stretchStartAnchorX;
  double? _stretchDurationUpdateMs;

  // Pan/Zoom state
  double? _initialPixelsPerMs;
  double? _initialScrollMs;
  double _tabletRowHeightScale = _kTabletRowHeightMaxScale;
  String? _tabletRailDragMode;
  double _tabletRailDragStartScale = _kTabletRowHeightMaxScale;
  double _tabletRailDragStartScrollOffset = 0.0;
  double _tabletRailDragStartGlobalY = 0.0;
  bool _horizontalScrollbarDragging = false;
  String? _horizontalScrollbarDragMode;
  double _horizontalScrollbarDragAccumX = 0.0;
  double _horizontalScrollbarDragStartPixelsPerMs = 0.1;
  double _horizontalScrollbarDragAnchorLocalX = 0.0;
  double _horizontalScrollbarDragAnchorMs = 0.0;

  List<AutomationPoint>? _automationBefore;
  int? _automationDragRow;
  int? _automationDragIndex;
  Offset? _automationDragStart;
  double? _automationFingerOffsetY;
  double? _automationActiveLaneHeight;
  final Map<String, String> _selectedAutomationClipByLane = <String, String>{};
  List<AutomationClipSnapshot>? _automationClipDragBefore;
  int? _automationClipDragRow;
  String? _automationClipDragTargetId;
  String? _automationClipDragId;
  String? _automationClipDragMode;
  double _automationClipDragDxAccum = 0.0;
  AutomationClipSnapshot? _automationClipDragOrigin;
  final Map<int, int> _extraAutomationTimelineLanesByRow = <int, int>{};
  final Map<int, bool> _collapsedAutomationTimelineByRow = <int, bool>{};
  final Map<int, int> _automationLaneFocusByRow = <int, int>{};
  final Map<int, Future<void> Function(int effectIndex, String paramId)>
  _rowEffectParameterRevealers =
      <int, Future<void> Function(int effectIndex, String paramId)>{};
  _TimelineAutomationClipVisual? _pendingAutomationClipVisual;
  Offset? _pendingAutomationClipStartLocalOffset;
  String? _pendingAutomationClipInteractionMode;
  int? _automationClipMenuRow;
  String? _automationClipMenuTargetId;
  String? _automationClipMenuClipId;
  int? _automationEditorRow;
  String? _automationEditorTargetId;
  String? _masterAutomationEditorTargetId;
  int? _automationTargetPickerRow;
  _AutomationClipClipboardEntry? _automationClipClipboard;
  static _AutomationPointsClipboardEntry? _automationPointsClipboard;
  static _AutomationAreaClipboardEntry? _automationAreaClipboard;

  bool _pendingDrag = false;
  bool _pendingDragStartedFromSelection = false;
  bool _tentativeClipSelectionActive = false;
  bool _suppressNextTimelineTapAfterTentativeSelectionCommit = false;
  bool _desktopAdditiveSelectionGestureActive = false;
  bool _suppressNextTimelineTapAfterAdditiveSelection = false;
  bool _touchMultiSelectMode = false;
  bool _suppressNextTimelineTapAfterInstrumentLaneCreate = false;
  int? _pendingTapSelectionClipIndex;
  double? _pendingTapSelectionPopupMs;
  bool _desktopPrimaryPointerDownActive = false;
  String? _stepDuplicateShortcutSelectionKey;
  double? _stepDuplicateShortcutNextPasteMs;
  final Set<int> _activeTimelinePointers = <int>{};
  bool _timelineModifierTrackpadNavigationActive = false;
  double? _timelineModifierTrackpadNavigationVerticalOffset;
  _TimelineTrackpadPanAxis? _timelineTrackpadPanAxis;
  PointerPanZoomUpdateEvent? _lastTimelinePointerPanZoomUpdateEvent;
  Timer? _timelineTrackpadHorizontalInertiaTimer;
  Duration? _timelineTrackpadLastHorizontalPanTime;
  double _timelineTrackpadHorizontalVelocityPxPerSecond = 0.0;
  bool _timelineTrackpadHorizontalInertiaEligible = false;
  double _timelineTrackpadHorizontalTravelPx = 0.0;

  // Paste popup state
  bool _showPastePopup = false;
  int? _pasteRow;
  double? _pasteMs;
  bool _showInstrumentLaneRegionPopup = false;
  int? _instrumentLaneRegionRow;
  double? _instrumentLaneRegionMs;
  Offset? _instrumentLaneRegionAnchorLocal;
  _TimelineGestureSelectionSnapshot? _singleTouchSelectionSnapshot;
  double? _clipPopupMs;
  int? _inlineClipControlIndex;
  _InlineClipControlKind? _inlineClipControlKind;
  double? _inlineClipGainStart;
  double? _inlineClipPitchStart;
  _TimelineTool _activeTool = _TimelineTool.pencil;
  final GlobalKey _toolMenuButtonKey = GlobalKey();

  bool _selectionBoxActive = false;
  Offset? _selectionBoxStart;
  Offset? _selectionBoxCurrent;
  final Set<int> _selectionBoxBaseClipIndices = <int>{};
  int? _pendingSelectionBoxPointer;
  Offset? _pendingSelectionBoxStart;
  bool _suppressNextTimelineTapAfterSelectionBox = false;

  /// BandLab-style "selection armed" cue at the long-press point.
  Offset? _selectionArmIndicatorAt;
  static const double _selectionArmIndicatorHideDistance = 8.0;

  /// Resting ring size (28px diameter); pulse expands to [_selectionArmIndicatorPulseRadius].
  static const double _selectionArmIndicatorRadius = 14.0;

  /// Peak ring size during the one-shot arm pulse (visible around a fingertip).
  static const double _selectionArmIndicatorPulseRadius = 38.0;
  bool _foregroundGridEnabled = true;
  final Set<String> _paintStrokeKeys = <String>{};
  bool _paintStrokeActive = false;
  bool _paintGesturePlacedClip = false;
  int? _paintStrokeRow;
  double? _paintLastFingerMs;
  double? _paintLastPasteStartMs;
  double? _paintLastPasteEndMs;
  double? _paintClipDurationEstimateMs;
  final List<_PendingPaintPaste> _pendingPaintPastes = <_PendingPaintPaste>[];
  DateTime? _lastPaintClipboardHintAt;
  bool _deleteStrokeActive = false;
  int? _rightDeleteStrokePointer;
  final Set<int> _deleteStrokeClipObjectIds = <int>{};
  int? _clipLoopPreviewPointer;
  int? _clipLoopPreviewClipIndex;
  double? _clipLoopPreviewStartMs;
  double? _clipLoopPreviewFallbackMs;
  int? _cutPreviewClipIndex;
  double? _cutPreviewRawMs;
  double? _cutPreviewMs;

  bool _magnetEnabled = true;
  int _quantizeDivisionsPerBar = 4; // default: 1/4 note (legacy behavior)
  int? _highlightedSegmentRow;
  double? _highlightedSegmentStartMs;
  double? _highlightedSegmentEndMs;
  bool _automationRangeSelectionMode = false;
  int? _automationRangeSelectionRow;
  String? _automationRangeSelectionTargetId;
  double? _automationRangeSelectionStartMs;
  double? _automationRangeSelectionEndMs;
  bool _loopEnabled = false;
  int?
  _loopStartMs; // made ints because when dragging loop handles, can get sub-ms numbers, but audio_editor converts to int
  int? _loopEndMs;
  bool _draggingLoopStart = false;
  bool _draggingLoopEnd = false;
  bool _draggingLoopRegion = false;
  bool _creatingLoopRegion = false;
  bool _desktopPlayheadDragActive = false;
  bool _desktopSecondaryLoopDragActive = false;
  double? _loopDragOffsetMs;
  double? _loopCreateAnchorMs;
  double? _loopDragRegionFingerAnchorMs;
  int? _loopDragRegionStartAnchorMs;
  int? _loopDragRegionEndAnchorMs;

  double? _panDragStart;
  final Map<int, double> _gainDragStartByRow = <int, double>{};

  // for updating the UI of the effects when JUCE state has changed
  final Map<int, VoidCallback> _rowEffectRefreshers = {};
  final Map<int, VoidCallback> _rowEffectPlaybackRefreshers = {};
  final GlobalKey _addRowPillKey = GlobalKey();
  Timer? _headerHoldTimer;
  Timer? _magnetHoldTimer;
  static const Duration _rowMenuHoldDelay = Duration(milliseconds: 200);
  static const double _headerTapMoveTolerance = 12.0;
  static const double _deadZoneHoldMoveTolerance = 4.0;
  static const Duration _magnetHoldDelay = Duration(milliseconds: 160);
  static const List<_QuantizePreset> _quantizePresets = <_QuantizePreset>[
    _QuantizePreset(divisionsPerBar: 1, label: '1/1'),
    _QuantizePreset(divisionsPerBar: 2, label: '1/2'),
    _QuantizePreset(divisionsPerBar: 3, label: '1/3'),
    _QuantizePreset(divisionsPerBar: 4, label: '1/4'),
    _QuantizePreset(divisionsPerBar: 5, label: '1/5'),
    _QuantizePreset(divisionsPerBar: 6, label: '1/6'),
    _QuantizePreset(divisionsPerBar: 7, label: '1/7'),
    _QuantizePreset(divisionsPerBar: 8, label: '1/8'),
    _QuantizePreset(divisionsPerBar: 16, label: '1/16'),
  ];
  int? _headerPointer;
  int? _headerRow;
  Offset? _headerDownPos;
  bool _headerEligible = false;
  bool _headerMoved = false;
  bool _headerMenuOpened = false;
  final Map<int, int> _groupFoldHeaderPointerRows = <int, int>{};
  Timer? _deadZoneHoldTimer;
  int? _deadZonePointer;
  int? _deadZoneRow;
  Offset? _deadZoneDownGlobalPos;
  bool _deadZoneMoved = false;
  bool _suppressNextTimelineTapAfterDeadZoneHold = false;
  bool _magnetMenuShownFromHold = false;
  final GlobalKey _magnetButtonKey = GlobalKey();
  final GlobalKey _externalSampleDropTargetKey = GlobalKey();
  int? _externalSampleDropRow;
  double? _externalSampleDropStartMs;
  double? _externalSampleDropEndMs;
  bool _externalSampleDropAllowed = true;
  bool _externalSampleDragInsideTimeline = false;
  List<_TimelineAutomationClipVisual> _timelineAutomationClipVisualCache =
      const <_TimelineAutomationClipVisual>[];
  TimelineRowVisibilityMap? _cachedRowVisibilityMap;
  int? _cachedRowVisibilityHash;

  void _notifySnapSettingsChanged() {
    widget.onSnapSettingsChanged?.call(
      _magnetEnabled,
      _quantizeDivisionsPerBar,
    );
    _publishTopControlsState();
  }

  String _quantizeLabelForDivisions(int divisionsPerBar) {
    for (final preset in _quantizePresets) {
      if (preset.divisionsPerBar == divisionsPerBar) return preset.label;
    }
    return '1/$divisionsPerBar';
  }

  int _matchingQuantizeDivisionsForMeter() {
    return math.max(1, widget.beatsPerBar);
  }

  void _syncQuantizeToTimeSignature() {
    final nextDivisions = _matchingQuantizeDivisionsForMeter();
    if (_quantizeDivisionsPerBar == nextDivisions) return;
    setState(() {
      _quantizeDivisionsPerBar = nextDivisions;
      if (_magnetEnabled &&
          _pasteRow != null &&
          _pasteMs != null &&
          _showPastePopup) {
        final start = _segmentStartMsForTap(_pasteMs!);
        _pasteMs = start;
        _highlightedSegmentRow = _pasteRow;
        _highlightedSegmentStartMs = start;
        _highlightedSegmentEndMs = start + _quantizeIntervalMs();
      }
      _refreshCutPreviewFromCurrentRaw(inSetState: true);
    });
    _notifySnapSettingsChanged();
  }

  void _publishTopControlsState() {
    widget.controller?._setTopControlsState(
      TimelineTopControlsState(
        magnetEnabled: _magnetEnabled,
        quantizeDivisionsPerBar: _quantizeDivisionsPerBar,
        quantizeLabel: _quantizeLabelForDivisions(_quantizeDivisionsPerBar),
        toolLabel: _activeTool.controllerLabel,
        toolIcon: _activeTool.icon,
        toolIconFlipHorizontally: _activeTool.flipHorizontally,
      ),
    );
  }

  bool get _hasPasteClipboard =>
      widget.hasCopiedClip || _automationClipClipboard != null;

  bool get _hasActiveAutomationClipDrag =>
      _automationClipDragRow != null &&
      _automationClipDragTargetId != null &&
      _automationClipDragId != null &&
      _automationClipDragMode != null;

  bool get _timelineHasMultiTouch => _activeTimelinePointers.length > 1;

  bool get _timelineClipDragSnapEnabled =>
      _magnetEnabled &&
      !(_timelineKeyboardModifierPointer != null &&
          HardwareKeyboard.instance.isAltPressed);

  bool get _timelineClipDragXAxisLockPressed {
    final keyboard = HardwareKeyboard.instance;
    final pressed = keyboard.logicalKeysPressed;
    final metaPressed =
        keyboard.isMetaPressed ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    final controlPressed =
        keyboard.isControlPressed ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    return metaPressed || (!Platform.isMacOS && controlPressed);
  }

  bool get _desktopAdditiveSelectionModifierPressed {
    if (!PlatformCapabilities.current.isDesktop) return false;
    final keyboard = HardwareKeyboard.instance;
    final primaryModifier = Platform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    return primaryModifier || keyboard.isShiftPressed;
  }

  double _quantizeMsForTimelineClipDrag(double rawMs) {
    return _timelineClipDragSnapEnabled ? _quantizeMs(rawMs) : rawMs;
  }

  double _segmentStartMsForTimelineClipDrag(double rawMs) {
    return _timelineClipDragSnapEnabled ? _segmentStartMsForTap(rawMs) : rawMs;
  }

  bool _isInstrumentLane(int row) {
    return row >= 0 &&
        row < widget.rows.length &&
        widget.rows[row].isInstrumentLane;
  }

  TrackGroup? _groupForRow(int row) {
    if (row < 0 || row >= widget.rows.length) return null;
    final groupId = widget.rows[row].groupId.trim();
    if (groupId.isEmpty) return null;
    for (final group in widget.trackGroups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  TimelineRowVisibilityMap _rowVisibilityMap() {
    final hash = _rowVisibilityHash();
    final cached = _cachedRowVisibilityMap;
    if (cached != null && _cachedRowVisibilityHash == hash) {
      return cached;
    }
    final next = buildTimelineRowVisibilityMap(
      rows: widget.rows,
      groups: widget.trackGroups,
    );
    _cachedRowVisibilityHash = hash;
    _cachedRowVisibilityMap = next;
    return next;
  }

  int _rowVisibilityHash() {
    final rowHash = Object.hashAll(
      widget.rows.map((row) => Object.hash(row.rowId, row.groupId)),
    );
    final groupHash = Object.hashAll(
      widget.trackGroups.map(
        (group) => Object.hash(
          group.id,
          group.collapsed,
          Object.hashAll(group.rowIds),
        ),
      ),
    );
    return Object.hash(
      widget.rows.length,
      widget.trackGroups.length,
      rowHash,
      groupHash,
    );
  }

  TimelineRowVisibilityEntry? _visibilityEntryForSourceRow(int row) {
    if (row < 0 || row >= widget.rows.length) return null;
    final visibility = _rowVisibilityMap();
    final visibleIndex = visibility.visibleIndexForSourceIndex(row);
    if (visibleIndex == null) return null;
    return visibility.entries[visibleIndex];
  }

  bool _isSourceRowVisible(int row) {
    if (row < 0 || row >= widget.rows.length) return false;
    return _rowVisibilityMap().visibleIndexForSourceIndex(row) != null;
  }

  List<int> _rowsForGroupingAction(int anchorRow) {
    final rows = <int>{};
    if (anchorRow >= 0 && anchorRow < widget.rows.length) {
      rows.add(anchorRow);
    }
    for (final index in _selectedClipIndices) {
      if (index < 0 || index >= widget.clips.length) continue;
      final row = widget.clips[index].rowIndex;
      if (row >= 0 && row < widget.rows.length) rows.add(row);
    }
    final ordered = rows.toList()..sort();
    return ordered;
  }

  List<int> _headerControlRows(int row) {
    return resolveTrackGroupControlRowIndices(
      rows: widget.rows,
      groups: widget.trackGroups,
      sourceIndex: row,
    );
  }

  Future<void> _setHeaderRowsMuted(List<int> rows, bool muted) async {
    for (final row in rows) {
      if (row < 0 || row >= widget.rowMuted.length) continue;
      await widget.muteRow(row, muted);
    }
  }

  Future<void> _setHeaderRowsSoloed(List<int> rows, bool soloed) async {
    for (final row in rows) {
      if (row < 0 || row >= widget.rowSoloed.length) continue;
      await widget.soloRow(row, soloed);
    }
  }

  List<int> _mixControlRows(int row) {
    final visibilityEntry = _visibilityEntryForSourceRow(row);
    final isGroupLeadRow =
        _groupForRow(row) != null &&
        visibilityEntry != null &&
        visibilityEntry.isGroupFirstRow;
    if (isGroupLeadRow) return <int>[row];
    return <int>[row]
        .where((item) => item >= 0 && item < widget.rows.length)
        .toList(growable: false);
  }

  void _setMixRowsGainLive(List<int> rows, double gain) {
    setState(() {
      for (final item in rows) {
        if (item >= 0 && item < widget.rowGain.length) {
          widget.rowGain[item] = gain;
        }
      }
    });
    for (final item in rows) {
      if (item >= 0 && item < widget.rowGain.length) {
        unawaited(widget.setRowGain(item, gain));
      }
    }
  }

  void _snapshotMixRowsGain(List<int> rows) {
    _gainDragStartByRow
      ..clear()
      ..addEntries(
        rows
            .where((row) => row >= 0 && row < widget.rowGain.length)
            .map((row) => MapEntry<int, double>(row, widget.rowGain[row])),
      );
  }

  void _commitMixRowsGainFromSnapshot(List<int> rows) {
    final commit = widget.onRowGainCommit;
    if (commit == null) {
      _gainDragStartByRow.clear();
      return;
    }
    for (final item in rows) {
      if (item < 0 || item >= widget.rowGain.length) continue;
      final oldGain = _gainDragStartByRow[item] ?? widget.rowGain[item];
      commit(item, oldGain, widget.rowGain[item]);
    }
    _gainDragStartByRow.clear();
  }

  double _headerGainForRows(List<int> rows, int fallbackRow) {
    final validRows = rows
        .where((row) => row >= 0 && row < widget.rowGain.length)
        .toList(growable: false);
    if (validRows.isEmpty) {
      return fallbackRow >= 0 && fallbackRow < widget.rowGain.length
          ? widget.rowGain[fallbackRow]
          : 2.0;
    }
    final total = validRows.fold<double>(
      0.0,
      (sum, row) => sum + widget.rowGain[row],
    );
    return total / validRows.length;
  }

  void _updateHeaderGainFromLocalDx({
    required List<int> rows,
    required double localDx,
    required double width,
  }) {
    if (width <= 0 || rows.isEmpty) return;
    final normalized = (localDx / width).clamp(0.0, 1.0).toDouble();
    final gain = normalized * 3.0;
    _setMixRowsGainLive(rows, gain);
  }

  void _setMixRowsPanLive(List<int> rows, double pan) {
    setState(() {
      for (final item in rows) {
        if (item >= 0 && item < widget.rowPan.length) {
          widget.rowPan[item] = pan;
        }
      }
    });
    for (final item in rows) {
      if (item >= 0 && item < widget.rowPan.length) {
        unawaited(widget.setRowPan(item, pan));
      }
    }
  }

  void _commitMixRowsPan(List<int> rows, double oldPan, double newPan) {
    final commit = widget.onRowPanCommit;
    if (commit == null) return;
    for (final item in rows) {
      if (item >= 0 && item < widget.rowPan.length) {
        commit(item, oldPan, newPan);
      }
    }
  }

  Future<void> _setMixRowsColor(List<int> rows, int color) async {
    final setColor = widget.onSetRowColor;
    if (setColor == null) return;
    await Future.wait(
      rows
          .where((row) => row >= 0 && row < widget.rows.length)
          .map((row) => setColor(row, color)),
    );
  }

  bool _rowAllowsClip(int row, AudioTrack clip) {
    return _isInstrumentLane(row) ? clip.isMidi : !clip.isMidi;
  }

  void _clearPastePopup() {
    if (_showPastePopup ||
        _pasteRow != null ||
        _pasteMs != null ||
        _highlightedSegmentRow != null ||
        _highlightedSegmentStartMs != null ||
        _highlightedSegmentEndMs != null) {
      setState(() {
        _showPastePopup = false;
        _pasteRow = null;
        _pasteMs = null;
        _highlightedSegmentRow = null;
        _highlightedSegmentStartMs = null;
        _highlightedSegmentEndMs = null;
      });
    }
  }

  void _clearInstrumentLaneRegionPopupState() {
    _showInstrumentLaneRegionPopup = false;
    _instrumentLaneRegionRow = null;
    _instrumentLaneRegionMs = null;
    _instrumentLaneRegionAnchorLocal = null;
    _suppressNextTimelineTapAfterInstrumentLaneCreate = false;
  }

  void _clearCutPreview() {
    if (_cutPreviewClipIndex == null &&
        _cutPreviewRawMs == null &&
        _cutPreviewMs == null) {
      return;
    }
    setState(() {
      _cutPreviewClipIndex = null;
      _cutPreviewRawMs = null;
      _cutPreviewMs = null;
      _resetTrimInteractionState();
    });
  }

  void _resetTrimInteractionState() {
    _activeTrimHandleX = null;
    _trimClipIndex = null;
    _trimStartValue = null;
    _trimEndValue = null;
    _trimOriginalStartMs = null;
    _trimStartAnchorX = null;
    _trimTimelineScaleValue = null;
    newTrimStartUpdate = null;
    newTrimEndUpdate = null;
    newStartMsUpdate = null;
    _stretchClipIndex = null;
    _stretchStartTimelineDurationMs = null;
    _stretchOriginalStartMs = null;
    _stretchStartAnchorX = null;
    _stretchDurationUpdateMs = null;
  }

  double _resolvedCutMsForClip(int clipIndex, double rawMs) {
    if (clipIndex < 0 || clipIndex >= widget.clips.length) return rawMs;
    final clip = widget.clips[clipIndex];
    final startMs = widget.getStartMs(clip);
    final endMs = startMs + widget.getTimelineDurationMs(clip);
    double cutMs = _magnetEnabled ? _quantizeMs(rawMs) : rawMs;
    if (endMs <= startMs) {
      return startMs;
    }
    final minCut = startMs + 0.5;
    final maxCut = endMs - 0.5;
    if (minCut <= maxCut) {
      cutMs = cutMs.clamp(minCut, maxCut).toDouble();
    } else {
      cutMs = cutMs.clamp(startMs, endMs).toDouble();
    }
    return cutMs;
  }

  void _refreshCutPreviewFromCurrentRaw({bool inSetState = false}) {
    final clipIndex = _cutPreviewClipIndex;
    final rawMs = _cutPreviewRawMs;
    if (clipIndex == null || rawMs == null) return;
    final snapped = _resolvedCutMsForClip(clipIndex, rawMs);
    if (_cutPreviewMs != null && (_cutPreviewMs! - snapped).abs() < 0.0001) {
      return;
    }
    if (inSetState) {
      _cutPreviewMs = snapped;
      return;
    }
    setState(() {
      _cutPreviewMs = snapped;
    });
  }

  void _updateCutPreviewAtLocal(Offset local) {
    if (_activeTool != _TimelineTool.cut) {
      _clearCutPreview();
      return;
    }
    final clipIndex = _getClipIndexAt(local);
    if (clipIndex == null) {
      _clearCutPreview();
      return;
    }
    final rawMs = (_scrollOffsetMs + local.dx / _pixelsPerMs).clamp(
      0.0,
      double.infinity,
    );
    final snapped = _resolvedCutMsForClip(clipIndex, rawMs);
    final sameClip = _cutPreviewClipIndex == clipIndex;
    final sameRaw =
        _cutPreviewRawMs != null && (_cutPreviewRawMs! - rawMs).abs() < 0.0001;
    final sameSnapped =
        _cutPreviewMs != null && (_cutPreviewMs! - snapped).abs() < 0.0001;
    if (sameClip && sameRaw && sameSnapped) return;
    setState(() {
      _cutPreviewClipIndex = clipIndex;
      _cutPreviewRawMs = rawMs.toDouble();
      _cutPreviewMs = snapped;
    });
  }

  void _resetDeleteStrokeState() {
    _deleteStrokeActive = false;
    _rightDeleteStrokePointer = null;
    _deleteStrokeClipObjectIds.clear();
  }

  void _deleteClipAtLocal(Offset local) {
    final clipIndex = _getClipIndexAt(local);
    if (clipIndex == null ||
        clipIndex < 0 ||
        clipIndex >= widget.clips.length) {
      return;
    }
    final clipObjectId = identityHashCode(widget.clips[clipIndex]);
    if (_deleteStrokeClipObjectIds.contains(clipObjectId)) return;
    _deleteStrokeClipObjectIds.add(clipObjectId);
    unawaited(widget.onDeleteClip(clipIndex));
  }

  bool _isDesktopSecondaryTimelinePointer(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse &&
        event.kind != PointerDeviceKind.trackpad) {
      return false;
    }
    return (event.buttons & kSecondaryMouseButton) != 0;
  }

  double? _clipPreviewStartMsAtLocal(int clipIndex, Offset local) {
    if (clipIndex < 0 || clipIndex >= widget.clips.length) return null;
    final clip = widget.clips[clipIndex];
    final clipStartMs = widget.getStartMs(clip);
    final clipDurationMs = widget.getTimelineDurationMs(clip);
    if (!clipStartMs.isFinite || !clipDurationMs.isFinite) return null;
    if (clipDurationMs <= 1.0) return null;
    final rawMs = _scrollOffsetMs + (local.dx / _pixelsPerMs);
    return rawMs
        .clamp(clipStartMs, clipStartMs + math.max(1.0, clipDurationMs - 1.0))
        .toDouble();
  }

  Future<void> _startClipLoopPreviewAtLocal(int pointer, Offset local) async {
    final onStart = widget.onStartClipLoopPreview;
    if (onStart == null) return;
    final clipIndex = _getClipIndexAt(local);
    if (clipIndex == null) return;
    final startMs = _clipPreviewStartMsAtLocal(clipIndex, local);
    if (startMs == null) return;
    setState(() {
      _clipLoopPreviewPointer = pointer;
      _clipLoopPreviewClipIndex = clipIndex;
      _clipLoopPreviewStartMs = startMs;
      _clipLoopPreviewFallbackMs = startMs;
      _clearPendingSelectionBox();
      _clearClipSelection();
      _closeInlineClipControl();
    });
    await onStart(clipIndex, startMs);
  }

  void _seekClipLoopPreviewAtLocal(PointerMoveEvent event) {
    final clipIndex = _clipLoopPreviewClipIndex;
    final onSeek = widget.onSeekClipLoopPreview;
    if (clipIndex == null || onSeek == null) return;
    final startMs = _clipPreviewStartMsAtLocal(clipIndex, event.localPosition);
    if (startMs == null) return;
    if (_clipLoopPreviewFallbackMs != null &&
        (_clipLoopPreviewFallbackMs! - startMs).abs() < 4.0) {
      return;
    }
    setState(() {
      _clipLoopPreviewStartMs = startMs;
      _clipLoopPreviewFallbackMs = startMs;
    });
    unawaited(onSeek(clipIndex, startMs));
  }

  void _stopClipLoopPreview() {
    if (_clipLoopPreviewPointer == null && _clipLoopPreviewClipIndex == null) {
      return;
    }
    setState(() {
      _clipLoopPreviewPointer = null;
      _clipLoopPreviewClipIndex = null;
      _clipLoopPreviewStartMs = null;
      _clipLoopPreviewFallbackMs = null;
    });
    final onStop = widget.onStopClipLoopPreview;
    if (onStop != null) {
      unawaited(onStop());
    }
  }

  bool _isDesktopPrimaryTimelinePointer(PointerDownEvent event) {
    if (!PlatformCapabilities.current.isDesktop) return false;
    if (event.buttons != kPrimaryMouseButton) return false;
    return event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.trackpad;
  }

  bool _canStartSelectionBoxAt(
    Offset localPosition, {
    required bool allowStartingOverClip,
  }) {
    if (_activeTool != _TimelineTool.pencil &&
        _activeTool != _TimelineTool.stretch) {
      return false;
    }
    if (_hasActiveAutomationClipDrag || _interactionMode == 'automation') {
      return false;
    }
    final row = _rowForLocalY(localPosition.dy);
    if (row == null || !_isLocalYInMainTrackLane(row, localPosition.dy)) {
      return false;
    }
    if (_timelineAutomationClipAt(localPosition) != null) {
      return false;
    }
    if (!allowStartingOverClip &&
        _getGestureClipIndexAt(localPosition) != null) {
      return false;
    }
    return true;
  }

  bool _hasTimelineSelectionFeedback() {
    return _selectedClipIndex >= 0 ||
        _selectedClipIndices.isNotEmpty ||
        _selectedAutomationClipByLane.isNotEmpty ||
        _automationClipMenuClipId != null ||
        _clipPopupMs != null ||
        _showPastePopup ||
        _showInstrumentLaneRegionPopup ||
        _trimClipIndex != null ||
        _stretchClipIndex != null ||
        _activeTrimHandleX != null;
  }

  void _clearTimelineSelectionFeedback() {
    _resetTrimInteractionState();
    _clearPendingClipTapState();
    _clearPendingAutomationClipSelection();
    _clearAutomationClipMenu();
    _clearClipSelection();
    _showPastePopup = false;
    _pasteRow = null;
    _pasteMs = null;
    _clearInstrumentLaneRegionPopupState();
    _highlightedSegmentRow = null;
    _highlightedSegmentStartMs = null;
    _highlightedSegmentEndMs = null;
  }

  void _beginSelectionBoxAt(
    Offset localPosition, {
    bool preserveExistingSelection = false,
    bool showArmIndicator = false,
  }) {
    _cancelDeadZoneHoldTimer();
    _resetDeadZonePointerState();
    _clearPendingClipTapState();
    _clearPendingAutomationClipSelection();
    _clearAutomationClipMenu();
    _isUserInteracting = false;
    _interactionMode = '';
    _selectionBoxBaseClipIndices
      ..clear()
      ..addAll(
        preserveExistingSelection
            ? _activeSelectedClipIndices()
            : const <int>[],
      );
    final clipUnderStart = _getGestureClipIndexAt(localPosition);
    if (clipUnderStart != null) {
      _selectionBoxBaseClipIndices.add(clipUnderStart);
    }
    _selectionBoxActive = true;
    _selectionBoxStart = localPosition;
    _selectionBoxCurrent = localPosition;
    _selectionArmIndicatorAt = showArmIndicator ? localPosition : null;
    _clipPopupMs = null;
    _showPastePopup = false;
    _pasteRow = null;
    _pasteMs = null;
    _clearInstrumentLaneRegionPopupState();
    _highlightedSegmentRow = null;
    _highlightedSegmentStartMs = null;
    _highlightedSegmentEndMs = null;
    _updateSelectionFromRect(
      Rect.fromLTWH(localPosition.dx, localPosition.dy, 0, 0),
    );
  }

  void _clearSelectionArmIndicator() {
    _selectionArmIndicatorAt = null;
  }

  void _clearSelectionBoxGestureState() {
    _selectionBoxActive = false;
    _selectionBoxStart = null;
    _selectionBoxCurrent = null;
    _selectionBoxBaseClipIndices.clear();
    _clearSelectionArmIndicator();
  }

  void _maybeHideSelectionArmIndicatorForRect(Rect rect) {
    if (_selectionArmIndicatorAt == null) return;
    if (rect.longestSide >= _selectionArmIndicatorHideDistance ||
        rect.shortestSide >= _selectionArmIndicatorHideDistance) {
      _clearSelectionArmIndicator();
    }
  }

  void _clearPendingSelectionBox() {
    _pendingSelectionBoxPointer = null;
    _pendingSelectionBoxStart = null;
  }

  void _suppressImmediateTapAfterSelectionBox() {
    _suppressNextTimelineTapAfterSelectionBox = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _suppressNextTimelineTapAfterSelectionBox = false;
    });
  }

  void _requestTimelineFocus() {
    if (!_timelineFocusNode.canRequestFocus) return;
    _timelineFocusNode.requestFocus();
  }

  bool _showPastePopupForEmptyTimelinePointerDown(Offset localPos) {
    if (!_hasPasteClipboard ||
        _interactionMode == 'automation' ||
        _hasActiveAutomationClipDrag ||
        _selectionBoxActive ||
        _activeTool == _TimelineTool.cut ||
        _activeTool == _TimelineTool.delete ||
        _activeTool == _TimelineTool.paint) {
      return false;
    }
    if (_timelineAutomationClipAt(localPos) != null ||
        _getGestureClipIndexAt(localPos) != null) {
      return false;
    }

    final tapRow = _rowForLocalY(localPos.dy);
    if (tapRow == null ||
        (!_canPasteCopiedClipAtRow(tapRow) &&
            !_canPasteAutomationClipAt(tapRow))) {
      return false;
    }

    final rawTapMs = _scrollOffsetMs + localPos.dx / _pixelsPerMs;
    final needsVisualReset =
        _selectedClipIndex >= 0 ||
        _selectedClipIndices.isNotEmpty ||
        _selectedAutomationClipByLane.isNotEmpty ||
        _automationClipMenuClipId != null ||
        _trimClipIndex != null ||
        _stretchClipIndex != null ||
        _activeTrimHandleX != null;
    setState(() {
      if (needsVisualReset) {
        _resetTrimInteractionState();
        _clearClipSelection();
      }
      _setPastePopupTarget(tapRow, rawTapMs);
    });
    return true;
  }

  void _onTimelinePointerDown(PointerDownEvent event) {
    _requestTimelineFocus();
    _suppressNextTimelineTapAfterDeadZoneHold = false;
    _activeTimelinePointers.add(event.pointer);
    final keyboard = HardwareKeyboard.instance;
    final desktopSelectionModifierPressed = Platform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final desktopPrimaryPointer = _isDesktopPrimaryTimelinePointer(event);
    final primaryMouseOrTrackpadPointer =
        (event.kind == PointerDeviceKind.mouse ||
            event.kind == PointerDeviceKind.trackpad) &&
        event.buttons == kPrimaryMouseButton;
    _desktopPrimaryPointerDownActive = primaryMouseOrTrackpadPointer;
    final keyboardModifierDragPointer = primaryMouseOrTrackpadPointer;
    if (keyboardModifierDragPointer) {
      _timelineKeyboardModifierPointer = event.pointer;
    }
    if (_isDesktopSecondaryTimelinePointer(event)) {
      if (keyboard.isAltPressed) {
        unawaited(
          _startClipLoopPreviewAtLocal(event.pointer, event.localPosition),
        );
        return;
      }
      if (_canShowInstrumentLaneRegionMenuAt(event.localPosition)) {
        _showInstrumentLaneRegionMenuAt(event.localPosition);
        return;
      }
      _deleteStrokeActive = true;
      _rightDeleteStrokePointer = event.pointer;
      _deleteStrokeClipObjectIds.clear();
      _deleteClipAtLocal(event.localPosition);
      return;
    }
    final desktopBoxSelectionShortcut =
        desktopPrimaryPointer &&
        desktopSelectionModifierPressed &&
        _canStartSelectionBoxAt(
          event.localPosition,
          allowStartingOverClip: true,
        );
    if (desktopBoxSelectionShortcut) {
      setState(() {
        _clearPendingSelectionBox();
        _beginSelectionBoxAt(
          event.localPosition,
          preserveExistingSelection: true,
        );
      });
      return;
    }
    if (primaryMouseOrTrackpadPointer &&
        !desktopSelectionModifierPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed &&
        _showPastePopupForEmptyTimelinePointerDown(event.localPosition)) {
      return;
    }
    if (desktopPrimaryPointer &&
        _canStartSelectionBoxAt(
          event.localPosition,
          allowStartingOverClip: false,
        )) {
      if (_hasTimelineSelectionFeedback()) {
        setState(() {
          _clearTimelineSelectionFeedback();
          _pendingSelectionBoxPointer = event.pointer;
          _pendingSelectionBoxStart = event.localPosition;
        });
      } else {
        _pendingSelectionBoxPointer = event.pointer;
        _pendingSelectionBoxStart = event.localPosition;
      }
      return;
    }
    final isPrimaryLikePointer =
        event.kind != PointerDeviceKind.mouse ||
        event.buttons == kPrimaryMouseButton;
    final deadZoneRow = _deadZoneRowAtLocalPosition(event.localPosition);
    final canArmDeadZoneHold =
        isPrimaryLikePointer &&
        !PlatformCapabilities.current.isDesktop &&
        deadZoneRow != null &&
        (_activeTool == _TimelineTool.pencil ||
            _activeTool == _TimelineTool.stretch) &&
        !_selectionBoxActive &&
        !_hasActiveAutomationClipDrag &&
        _interactionMode != 'automation';
    if (canArmDeadZoneHold) {
      _startDeadZoneRowMenuHold(deadZoneRow, event.pointer, event.position);
    }
    if (_activeTimelinePointers.length == 1) {
      _singleTouchSelectionSnapshot = _captureGestureSelectionSnapshot();
    }
    final becameMultiTouch = _timelineHasMultiTouch;
    if (becameMultiTouch) {
      _cancelDeadZoneHoldTimer();
      _resetDeadZonePointerState();
      setState(() {
        final snapshot = _singleTouchSelectionSnapshot;
        if (snapshot != null) {
          _restoreGestureSelectionSnapshot(snapshot);
        }
        _timelineKeyboardModifierPointer = null;
        _clearPendingSelectionBox();
        _clearSelectionBoxGestureState();
        _clearPendingClipTapState();
        _clearPendingAutomationClipSelection();
        _clearAutomationClipMenu();
        if (_interactionMode == 'drag' && !_hasActiveAutomationClipDrag) {
          _interactionMode = '';
          _isUserInteracting = false;
        }
      });
      _singleTouchSelectionSnapshot = null;
    }
    if (isPrimaryLikePointer) {
      if (_activeTool == _TimelineTool.paint && !becameMultiTouch) {
        _paintGesturePlacedClip = false;
        final tappedClipIndex = _getGestureClipIndexAt(event.localPosition);
        if (tappedClipIndex != null) {
          _handleTapDown(
            TapDownDetails(
              globalPosition: event.position,
              localPosition: event.localPosition,
            ),
          );
          return;
        }
      }
      if (_activeTool != _TimelineTool.cut &&
          _activeTool != _TimelineTool.paint &&
          _activeTool != _TimelineTool.delete &&
          !becameMultiTouch &&
          !canArmDeadZoneHold) {
        _handleTapDown(
          TapDownDetails(
            globalPosition: event.position,
            localPosition: event.localPosition,
          ),
        );
      }
    }
    if (_activeTool == _TimelineTool.cut) {
      _updateCutPreviewAtLocal(event.localPosition);
      return;
    }
    if (_activeTool == _TimelineTool.paint) {
      if (_getGestureClipIndexAt(event.localPosition) == null &&
          _hasTimelineSelectionFeedback()) {
        setState(_clearTimelineSelectionFeedback);
      }
      _isUserInteracting = true;
      _interactionMode = 'paint';
      _resetPaintStrokeState();
      _startPaintStroke(event.localPosition);
      return;
    }
    if (_activeTool == _TimelineTool.delete) {
      _deleteStrokeActive = true;
      _deleteStrokeClipObjectIds.clear();
      _deleteClipAtLocal(event.localPosition);
    }
  }

  void _onTimelinePointerMove(PointerMoveEvent event) {
    _onDeadZonePointerMove(event);
    if (_clipLoopPreviewPointer == event.pointer) {
      _seekClipLoopPreviewAtLocal(event);
      return;
    }
    if (_rightDeleteStrokePointer == event.pointer && _deleteStrokeActive) {
      _deleteClipAtLocal(event.localPosition);
      return;
    }
    if (_pendingSelectionBoxPointer == event.pointer &&
        _pendingSelectionBoxStart != null) {
      final start = _pendingSelectionBoxStart!;
      if ((event.localPosition - start).distance >= 1.0) {
        setState(() {
          _clearPendingSelectionBox();
          _beginSelectionBoxAt(start);
          _selectionBoxCurrent = event.localPosition;
          final rect = _currentSelectionRect();
          if (rect != null) {
            _updateSelectionFromRect(rect);
            _maybeHideSelectionArmIndicatorForRect(rect);
          }
        });
      }
      return;
    }
    if (_selectionBoxActive && _selectionBoxStart != null) {
      setState(() {
        _selectionBoxCurrent = event.localPosition;
        final rect = _currentSelectionRect();
        if (rect != null) {
          _updateSelectionFromRect(rect);
          _maybeHideSelectionArmIndicatorForRect(rect);
        }
      });
      return;
    }
    if (_activeTool == _TimelineTool.cut) {
      _updateCutPreviewAtLocal(event.localPosition);
      return;
    }
    if (_activeTool == _TimelineTool.delete && _deleteStrokeActive) {
      _deleteClipAtLocal(event.localPosition);
    }
  }

  void _onTimelinePointerHover(PointerHoverEvent event) {
    if (_activeTool != _TimelineTool.cut) return;
    _updateCutPreviewAtLocal(event.localPosition);
  }

  void _onTimelinePointerSignal(PointerSignalEvent event) {
    _handleTimelineNavigationPointerSignal(event);
  }

  void _onTimelinePointerPanZoomStart(PointerPanZoomStartEvent event) {
    _stopTimelineTrackpadHorizontalInertia();
    _timelineTrackpadPanAxis = null;
    _lastTimelinePointerPanZoomUpdateEvent = null;
    _timelineTrackpadLastHorizontalPanTime = event.timeStamp;
    _timelineTrackpadHorizontalVelocityPxPerSecond = 0.0;
    _timelineTrackpadHorizontalInertiaEligible = false;
    _timelineTrackpadHorizontalTravelPx = 0.0;
    _beginTimelineModifierTrackpadNavigationLock();
  }

  void _onTimelinePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (_handleTimelineNavigationPointerPanZoomUpdate(event)) {
      _restoreTimelineModifierTrackpadNavigationVerticalOffset();
    }
  }

  void _onTimelinePointerPanZoomEnd(PointerPanZoomEndEvent event) {
    final shouldStartHorizontalInertia =
        _timelineTrackpadHorizontalInertiaEligible &&
        _timelineTrackpadHorizontalTravelPx >=
            _kTrackpadHorizontalInertiaMinTravelPx;
    _timelineTrackpadPanAxis = null;
    _lastTimelinePointerPanZoomUpdateEvent = null;
    _timelineTrackpadLastHorizontalPanTime = null;
    _timelineTrackpadHorizontalInertiaEligible = false;
    _timelineTrackpadHorizontalTravelPx = 0.0;
    _endTimelineModifierTrackpadNavigationLock();
    if (shouldStartHorizontalInertia) {
      _startTimelineTrackpadHorizontalInertia();
    }
  }

  void _onTimelineLeftChromePointerSignal(PointerSignalEvent event) {
    if (_handleTimelineNavigationPointerSignal(event, focalPointPx: 0.0)) {
      return;
    }
    _handleVerticalTimelinePointerSignal(event);
  }

  void _onTimelineLeftChromePointerPanZoomUpdate(
    PointerPanZoomUpdateEvent event,
  ) {
    if (_handleTimelineNavigationPointerPanZoomUpdate(
      event,
      focalPointPx: 0.0,
    )) {
      _restoreTimelineModifierTrackpadNavigationVerticalOffset();
    }
  }

  bool _handleTimelineNavigationPointerSignal(
    PointerSignalEvent event, {
    double? focalPointPx,
  }) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return false;
    if (event is! PointerScrollEvent) return false;

    final keyboard = HardwareKeyboard.instance;
    final cmdPressed = keyboard.isMetaPressed;
    final shiftPressed = keyboard.isShiftPressed;
    if (!cmdPressed && !shiftPressed) return false;
    _stopTimelineTrackpadHorizontalInertia();

    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolved,
    ) {
      if (resolved is! PointerScrollEvent) return;
      if (cmdPressed) {
        _handleMacTimelineZoom(resolved, focalPointPx: focalPointPx);
        return;
      }
      if (shiftPressed) {
        _handleMacTimelineHorizontalScroll(resolved);
      }
    });
    return true;
  }

  bool _handleTimelineNavigationPointerPanZoomUpdate(
    PointerPanZoomUpdateEvent event, {
    double? focalPointPx,
  }) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return false;
    if (identical(_lastTimelinePointerPanZoomUpdateEvent, event)) return true;
    _lastTimelinePointerPanZoomUpdateEvent = event;

    final keyboard = HardwareKeyboard.instance;
    final cmdPressed = keyboard.isMetaPressed;
    final shiftPressed = keyboard.isShiftPressed;

    if (cmdPressed) {
      _beginTimelineModifierTrackpadNavigationLock();
      _handleMacTimelineZoomDelta(
        event.localPanDelta,
        focalPointPx: focalPointPx ?? event.localPosition.dx,
      );
      return true;
    }
    if (shiftPressed) {
      _beginTimelineModifierTrackpadNavigationLock();
      _recordTimelineTrackpadHorizontalVelocity(
        event,
        scrollDeltaPx: event.localPanDelta.dy,
      );
      _handleMacTimelineHorizontalScrollDelta(event.localPanDelta);
      return true;
    }
    return _handleMacTimelineTrackpadHorizontalScroll(event);
  }

  bool _macTimelineNavigationModifierPressed() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return false;
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isMetaPressed || keyboard.isShiftPressed;
  }

  void _beginTimelineModifierTrackpadNavigationLock() {
    if (!_macTimelineNavigationModifierPressed()) return;
    _beginTimelineTrackpadNavigationLock();
  }

  void _beginTimelineTrackpadNavigationLock() {
    _timelineModifierTrackpadNavigationVerticalOffset ??=
        _verticalScrollController.hasClients
        ? _verticalScrollController.offset
        : null;
    if (_timelineModifierTrackpadNavigationActive) return;
    setState(() {
      _timelineModifierTrackpadNavigationActive = true;
    });
  }

  void _restoreTimelineModifierTrackpadNavigationVerticalOffset() {
    final lockedOffset = _timelineModifierTrackpadNavigationVerticalOffset;
    if (lockedOffset == null || !_verticalScrollController.hasClients) return;
    final position = _verticalScrollController.position;
    final target = lockedOffset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((_verticalScrollController.offset - target).abs() > 0.01) {
      _verticalScrollController.jumpTo(target);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_timelineModifierTrackpadNavigationActive ||
          !_verticalScrollController.hasClients) {
        return;
      }
      final position = _verticalScrollController.position;
      final target = lockedOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((_verticalScrollController.offset - target).abs() > 0.01) {
        _verticalScrollController.jumpTo(target);
      }
    });
  }

  void _endTimelineModifierTrackpadNavigationLock() {
    if (!_timelineModifierTrackpadNavigationActive &&
        _timelineModifierTrackpadNavigationVerticalOffset == null) {
      return;
    }
    _restoreTimelineModifierTrackpadNavigationVerticalOffset();
    setState(() {
      _timelineModifierTrackpadNavigationActive = false;
      _timelineModifierTrackpadNavigationVerticalOffset = null;
    });
  }

  bool _handleVerticalTimelinePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return false;
    if (!PlatformCapabilities.current.isDesktop) return false;

    final keyboard = HardwareKeyboard.instance;
    if ((defaultTargetPlatform == TargetPlatform.macOS &&
            (keyboard.isMetaPressed || keyboard.isShiftPressed)) ||
        keyboard.isControlPressed) {
      return false;
    }

    final delta = event.scrollDelta.dy;
    if (delta.abs() < 0.5 || delta.abs() < event.scrollDelta.dx.abs()) {
      return false;
    }
    if (!_verticalScrollController.hasClients) return false;

    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolved,
    ) {
      if (resolved is! PointerScrollEvent) return;
      if (!_verticalScrollController.hasClients) return;
      final position = _verticalScrollController.position;
      final nextOffset =
          (_verticalScrollController.offset + resolved.scrollDelta.dy)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
      if ((nextOffset - _verticalScrollController.offset).abs() <= 0.01) {
        return;
      }
      _verticalScrollController.jumpTo(nextOffset);
    });
    return true;
  }

  void _handleMacTimelineZoom(
    PointerScrollEvent event, {
    double? focalPointPx,
  }) {
    _handleMacTimelineZoomDelta(
      event.scrollDelta,
      focalPointPx: focalPointPx ?? event.localPosition.dx,
    );
  }

  void _handleMacTimelineZoomDelta(
    Offset delta, {
    required double focalPointPx,
  }) {
    final rawDelta = delta.dy;
    if (rawDelta == 0) return;

    bool didZoom = false;
    setState(() {
      final zoomFactor = math.exp(-rawDelta * _kMacWheelZoomSensitivity);
      final newPixelsPerMs = (_pixelsPerMs * zoomFactor).clamp(
        _kMinTimelinePixelsPerMs,
        _kMaxTimelinePixelsPerMs,
      );
      if ((newPixelsPerMs - _pixelsPerMs).abs() < 0.0001) return;

      final focalPx = focalPointPx
          .clamp(0.0, _getViewportWidth(context))
          .toDouble();
      final focalPointMs = _scrollOffsetMs + focalPx / _pixelsPerMs;
      _scrollOffsetMs = focalPointMs - (focalPx / newPixelsPerMs);
      _pixelsPerMs = newPixelsPerMs;
      _clampScroll();
      didZoom = true;
    });

    if (didZoom) {
      widget.onTutorialTimelineZoomed?.call();
    }
  }

  void _handleMacTimelineHorizontalScroll(PointerScrollEvent event) {
    _handleMacTimelineHorizontalScrollDelta(event.scrollDelta);
  }

  void _handleMacTimelineHorizontalScrollDelta(Offset delta) {
    final rawDelta = delta.dy;
    if (rawDelta == 0) return;

    setState(() {
      _scrollOffsetMs += rawDelta / _pixelsPerMs;
      _clampScroll();
    });

    widget.onTutorialTimelineScrolled?.call();
  }

  void _recordTimelineTrackpadHorizontalVelocity(
    PointerPanZoomUpdateEvent event, {
    required double scrollDeltaPx,
  }) {
    final previousTime = _timelineTrackpadLastHorizontalPanTime;
    _timelineTrackpadLastHorizontalPanTime = event.timeStamp;
    if (scrollDeltaPx.abs() < 0.5) return;

    _timelineTrackpadHorizontalTravelPx += scrollDeltaPx.abs();
    final elapsedSeconds = previousTime == null
        ? 1 / 60
        : (event.timeStamp - previousTime).inMicroseconds / 1000000.0;
    final safeElapsedSeconds = elapsedSeconds > 0 ? elapsedSeconds : 1 / 60;
    _timelineTrackpadHorizontalVelocityPxPerSecond =
        (scrollDeltaPx / safeElapsedSeconds).clamp(-4200.0, 4200.0);
    _timelineTrackpadHorizontalInertiaEligible =
        _timelineTrackpadHorizontalVelocityPxPerSecond.abs() >=
        _kTrackpadHorizontalInertiaMinVelocityPxPerSecond;
  }

  void _startTimelineTrackpadHorizontalInertia() {
    if (_timelineTrackpadHorizontalInertiaTimer != null) return;
    final velocity = _timelineTrackpadHorizontalVelocityPxPerSecond;
    _timelineTrackpadHorizontalVelocityPxPerSecond = 0.0;
    if (velocity.abs() < _kTrackpadHorizontalInertiaMinVelocityPxPerSecond ||
        _pixelsPerMs <= 0) {
      return;
    }

    final simulation = ClampingScrollSimulation(
      position: _scrollOffsetMs * _pixelsPerMs,
      velocity: velocity,
    );
    final stopwatch = Stopwatch()..start();
    const frame = Duration(milliseconds: 16);
    _timelineTrackpadHorizontalInertiaTimer = Timer.periodic(frame, (timer) {
      if (!mounted || _pixelsPerMs <= 0) {
        _stopTimelineTrackpadHorizontalInertia();
        return;
      }

      final elapsedSeconds = stopwatch.elapsedMicroseconds / 1000000.0;
      final nextScrollPx = simulation.x(elapsedSeconds);
      final before = _scrollOffsetMs;
      setState(() {
        _scrollOffsetMs = nextScrollPx / _pixelsPerMs;
        _clampScroll();
      });
      if (simulation.isDone(elapsedSeconds) ||
          (_scrollOffsetMs - before).abs() < 0.01) {
        _stopTimelineTrackpadHorizontalInertia();
      }
    });
  }

  void _stopTimelineTrackpadHorizontalInertia() {
    _timelineTrackpadHorizontalInertiaTimer?.cancel();
    _timelineTrackpadHorizontalInertiaTimer = null;
    _timelineTrackpadHorizontalVelocityPxPerSecond = 0.0;
    _timelineTrackpadHorizontalInertiaEligible = false;
    _timelineTrackpadHorizontalTravelPx = 0.0;
  }

  bool _handleMacTimelineTrackpadHorizontalScroll(
    PointerPanZoomUpdateEvent event,
  ) {
    final delta = event.localPanDelta;
    final horizontalDelta = delta.dx.abs();
    final verticalDelta = delta.dy.abs();
    if (_timelineTrackpadPanAxis == null) {
      if (horizontalDelta < 0.5 && verticalDelta < 0.5) return false;
      if (horizontalDelta <= verticalDelta) {
        _timelineTrackpadPanAxis = _TimelineTrackpadPanAxis.vertical;
        return false;
      }
      _timelineTrackpadPanAxis = _TimelineTrackpadPanAxis.horizontal;
    }
    if (_timelineTrackpadPanAxis != _TimelineTrackpadPanAxis.horizontal) {
      return false;
    }

    _beginTimelineTrackpadNavigationLock();
    final rawDelta = delta.dx;
    if (rawDelta.abs() < 0.5) return true;
    _recordTimelineTrackpadHorizontalVelocity(
      event,
      scrollDeltaPx: -event.localPanDelta.dx,
    );

    setState(() {
      _scrollOffsetMs -= rawDelta / _pixelsPerMs;
      _clampScroll();
    });

    widget.onTutorialTimelineScrolled?.call();
    return true;
  }

  void _onTimelinePointerUp(PointerUpEvent event) {
    _onDeadZonePointerUp(event);
    _activeTimelinePointers.remove(event.pointer);
    _desktopPrimaryPointerDownActive = false;
    if (_desktopAdditiveSelectionGestureActive) {
      _desktopAdditiveSelectionGestureActive = false;
      _timelineKeyboardModifierPointer = null;
      return;
    }
    if (_clipLoopPreviewPointer == event.pointer) {
      _stopClipLoopPreview();
      return;
    }
    if (_rightDeleteStrokePointer == event.pointer) {
      _resetDeleteStrokeState();
      return;
    }
    if (_pendingSelectionBoxPointer == event.pointer) {
      _clearPendingSelectionBox();
    }
    if (_selectionBoxActive) {
      setState(() {
        _clearSelectionBoxGestureState();
        _timelineKeyboardModifierPointer = null;
        _suppressImmediateTapAfterSelectionBox();
      });
      return;
    }
    if (_tentativeClipSelectionActive) {
      setState(() {
        if (_commitTentativeTapSelectionIfNeeded()) {
          _suppressNextTimelineTapAfterTentativeSelectionCommit = true;
        }
        _isUserInteracting = false;
        _interactionMode = '';
      });
      if (_activeTimelinePointers.isEmpty) {
        _singleTouchSelectionSnapshot = null;
      }
      return;
    }
    if (_activeTimelinePointers.isEmpty) {
      _singleTouchSelectionSnapshot = null;
    }
    if (_activeTool == _TimelineTool.cut) {
      final previewClipIndex = _cutPreviewClipIndex;
      final previewCutMs = _cutPreviewMs;
      if (previewClipIndex != null && previewCutMs != null) {
        widget.onCutClipAt?.call(previewClipIndex, previewCutMs);
      } else {
        final local = event.localPosition;
        final clipIndex = _getClipIndexAt(local);
        if (clipIndex != null) {
          final rawCutMs = _scrollOffsetMs + local.dx / _pixelsPerMs;
          final cutMs = _resolvedCutMsForClip(clipIndex, rawCutMs);
          widget.onCutClipAt?.call(clipIndex, cutMs);
        }
      }
      _clearCutPreview();
      return;
    }
    if (_activeTool == _TimelineTool.paint &&
        (_interactionMode == 'paint' || _paintStrokeActive)) {
      _isUserInteracting = false;
      _interactionMode = '';
      _resetPaintStrokeState();
      return;
    }
    final pendingAutomationClip = _pendingAutomationClipVisual;
    if (pendingAutomationClip != null) {
      final pendingMode = _pendingAutomationClipInteractionMode ?? 'open';
      setState(() {
        _clearPendingAutomationClipSelection();
        _dragStartGlobalOffset = null;
      });
      if (pendingMode == 'open') {
        _openAutomationClipEditor(pendingAutomationClip);
      }
      return;
    }
    if (_interactionMode != 'drag' && _pendingDrag) {
      setState(_clearPendingClipTapState);
    }
    if (_activeTool == _TimelineTool.delete) {
      _resetDeleteStrokeState();
    }
  }

  void _onTimelinePointerCancel(PointerCancelEvent event) {
    _onDeadZonePointerCancel(event);
    _activeTimelinePointers.remove(event.pointer);
    _desktopPrimaryPointerDownActive = false;
    _desktopAdditiveSelectionGestureActive = false;
    if (_timelineKeyboardModifierPointer == event.pointer) {
      _timelineKeyboardModifierPointer = null;
    }
    if (_clipLoopPreviewPointer == event.pointer) {
      _stopClipLoopPreview();
      return;
    }
    if (_rightDeleteStrokePointer == event.pointer) {
      _resetDeleteStrokeState();
      return;
    }
    if (_pendingSelectionBoxPointer == event.pointer) {
      _clearPendingSelectionBox();
    }
    if (_selectionBoxActive) {
      setState(_clearSelectionBoxGestureState);
    } else {
      _clearSelectionArmIndicator();
    }
    _tentativeClipSelectionActive = false;
    if (_activeTimelinePointers.isEmpty) {
      _singleTouchSelectionSnapshot = null;
    }
    _clearPendingAutomationClipSelection();
    _clearPendingClipTapState();
    if (_hasActiveAutomationClipDrag) {
      final row = _automationClipDragRow;
      final targetId = _automationClipDragTargetId;
      if (row != null && targetId != null) {
        _endAutomationClipDrag(row, targetId);
      }
      setState(() {
        _interactionMode = '';
        _isUserInteracting = false;
        _dragStartGlobalOffset = null;
      });
      return;
    }
    if (_activeTool == _TimelineTool.cut) {
      _clearCutPreview();
      return;
    }
    if (_activeTool == _TimelineTool.paint &&
        (_interactionMode == 'paint' || _paintStrokeActive)) {
      _isUserInteracting = false;
      _interactionMode = '';
      _resetPaintStrokeState();
      _paintGesturePlacedClip = false;
      return;
    }
    if (_activeTool == _TimelineTool.delete) {
      _resetDeleteStrokeState();
    }
  }

  double _msPerBar() {
    final msPerQuarter = 60000 / widget.bpm;
    final safeNumerator = math.max(1, widget.beatsPerBar);
    final safeDenominator = math.max(1, widget.beatUnit);
    return msPerQuarter * safeNumerator * 4.0 / safeDenominator;
  }

  double _quantizeIntervalMs() {
    final safeDivisions = math.max(1, _quantizeDivisionsPerBar);
    return _msPerBar() / safeDivisions;
  }

  double _segmentStartMsForTap(double rawMs) {
    final interval = _quantizeIntervalMs();
    if (interval <= 0) return rawMs;
    return (rawMs / interval).floorToDouble() * interval;
  }

  Rect? _globalRectForKey(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  RelativeRect? _menuPositionForGlobalRect(Rect rect, RenderBox overlay) {
    final overlayTopLeft = overlay.localToGlobal(Offset.zero);
    final anchor = rect.translate(-overlayTopLeft.dx, -overlayTopLeft.dy);
    return RelativeRect.fromLTRB(
      anchor.left,
      anchor.bottom,
      overlay.size.width - anchor.right,
      overlay.size.height - anchor.bottom,
    );
  }

  RelativeRect? _menuPositionForTrigger(GlobalKey key, RenderBox overlay) {
    final rect = _globalRectForKey(key);
    if (rect == null) return null;
    return _menuPositionForGlobalRect(rect, overlay);
  }

  Future<void> _showQuantizeMenu({Rect? anchorRect}) async {
    if (!mounted) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = anchorRect != null
        ? _menuPositionForGlobalRect(anchorRect, overlay)
        : _menuPositionForTrigger(_magnetButtonKey, overlay);
    if (position == null) return;
    final triggerWidth =
        anchorRect?.width ?? _globalRectForKey(_magnetButtonKey)?.width ?? 30.0;
    final compactItems = triggerWidth < 72;
    final selected = await showMenu<int>(
      context: context,
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 95),
        reverseDuration: Duration(milliseconds: 65),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      color: const Color(0xFF485660).withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      constraints: BoxConstraints.tightFor(width: triggerWidth),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      position: position,
      items: _quantizePresets.map((preset) {
        final isSelected = preset.divisionsPerBar == _quantizeDivisionsPerBar;
        return PopupMenuItem<int>(
          key: ValueKey('timeline_quantize_menu_${preset.divisionsPerBar}'),
          value: preset.divisionsPerBar,
          height: 36,
          padding: compactItems ? EdgeInsets.zero : null,
          child: compactItems
              ? Center(
                  child: Text(
                    preset.label,
                    style: TextStyle(
                      color: isSelected
                          ? _kTimelineWarmBorder
                          : _kTimelineShellMutedText,
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      fontFamily: 'Pretendard',
                    ),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        preset.label,
                        style: TextStyle(
                          color: isSelected
                              ? _kTimelineShellText
                              : _kTimelineShellMutedText,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check,
                        size: 16,
                        color: _kTimelineWarmBorder,
                      ),
                  ],
                ),
        );
      }).toList(),
    );

    if (selected == null || selected == _quantizeDivisionsPerBar) return;
    if (!mounted) return;
    setState(() {
      _quantizeDivisionsPerBar = selected;
      if (_magnetEnabled &&
          _pasteRow != null &&
          _pasteMs != null &&
          _showPastePopup) {
        final start = _segmentStartMsForTap(_pasteMs!);
        _pasteMs = start;
        _highlightedSegmentRow = _pasteRow;
        _highlightedSegmentStartMs = start;
        _highlightedSegmentEndMs = start + _quantizeIntervalMs();
      }
      _refreshCutPreviewFromCurrentRaw(inSetState: true);
    });
    _notifySnapSettingsChanged();
  }

  Future<void> _showToolMenu({Rect? anchorRect}) async {
    if (!mounted) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = anchorRect != null
        ? _menuPositionForGlobalRect(anchorRect, overlay)
        : _menuPositionForTrigger(_toolMenuButtonKey, overlay);
    if (position == null) return;
    final triggerWidth =
        anchorRect?.width ??
        _globalRectForKey(_toolMenuButtonKey)?.width ??
        30.0;
    final menuWidth = math.max(triggerWidth, 176.0);
    final selected = await showMenu<Object>(
      context: context,
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 95),
        reverseDuration: Duration(milliseconds: 65),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      color: const Color(0xFF485660).withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      constraints: BoxConstraints.tightFor(width: menuWidth),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      position: position,
      items: <PopupMenuEntry<Object>>[
        ..._TimelineTool.values.map((tool) {
          final isSelected = tool == _activeTool;
          return PopupMenuItem<Object>(
            key: ValueKey('timeline_tool_menu_${tool.name}'),
            value: tool,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _buildToolIcon(
                  tool,
                  size: 16,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tool.label(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color: isSelected
                          ? _kTimelineShellText
                          : _kTimelineShellMutedText,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontFamily: 'Pretendard',
                    ),
                  ),
                ),
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.check,
                      size: 16,
                      color: _kTimelineWarmBorder,
                    ),
                  ),
              ],
            ),
          );
        }),
        const PopupMenuDivider(height: 8),
        CheckedPopupMenuItem<Object>(
          key: const ValueKey('timeline_foreground_grid_toggle'),
          value: 'toggle_foreground_grid',
          checked: _foregroundGridEnabled,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            L10n.translate(context, 'Foreground grid'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _kTimelineShellText,
              fontWeight: _foregroundGridEnabled
                  ? FontWeight.w700
                  : FontWeight.w500,
              fontFamily: 'Pretendard',
            ),
          ),
        ),
      ],
    );

    if (selected == null || !mounted) return;
    if (selected == 'toggle_foreground_grid') {
      setState(() {
        _foregroundGridEnabled = !_foregroundGridEnabled;
      });
      return;
    }
    if (selected is _TimelineTool && selected != _activeTool) {
      _selectTimelineTool(selected);
    }
  }

  void _selectTimelineTool(_TimelineTool tool) {
    if (tool == _activeTool) return;
    setState(() {
      _activeTool = tool;
      _clearPendingSelectionBox();
      _clearSelectionBoxGestureState();
      _resetPaintStrokeState();
      _resetDeleteStrokeState();
      _showPastePopup = false;
      _pasteRow = null;
      _pasteMs = null;
      _highlightedSegmentRow = null;
      _highlightedSegmentStartMs = null;
      _highlightedSegmentEndMs = null;
      _cutPreviewClipIndex = null;
      _cutPreviewRawMs = null;
      _cutPreviewMs = null;
    });
    _publishTopControlsState();
  }

  int _fallbackTimelineToolShortcutIndex(LogicalKeyboardKey key) {
    return switch (key) {
      LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => 0,
      LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => 1,
      LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => 2,
      LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => 3,
      LogicalKeyboardKey.digit5 || LogicalKeyboardKey.numpad5 => 4,
      _ => -1,
    };
  }

  bool _isUnmodifiedShortcutBinding(DesktopShortcutBinding binding) {
    return !binding.meta && !binding.control && !binding.shift && !binding.alt;
  }

  bool _matchesDefaultToolNumpadShortcut(
    KeyEvent event,
    DesktopShortcutBinding binding,
    int index,
  ) {
    if (!_isUnmodifiedShortcutBinding(binding)) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed) {
      return false;
    }
    final expectedDigit = switch (index) {
      0 => LogicalKeyboardKey.digit1,
      1 => LogicalKeyboardKey.digit2,
      2 => LogicalKeyboardKey.digit3,
      3 => LogicalKeyboardKey.digit4,
      4 => LogicalKeyboardKey.digit5,
      _ => null,
    };
    final expectedNumpad = switch (index) {
      0 => LogicalKeyboardKey.numpad1,
      1 => LogicalKeyboardKey.numpad2,
      2 => LogicalKeyboardKey.numpad3,
      3 => LogicalKeyboardKey.numpad4,
      4 => LogicalKeyboardKey.numpad5,
      _ => null,
    };
    if (expectedDigit == null || expectedNumpad == null) return false;
    return binding.logicalKey == expectedDigit &&
        event.logicalKey == expectedNumpad;
  }

  _TimelineTool? _timelineToolForShortcutEvent(KeyEvent event) {
    final bindings = widget.toolShortcutBindings;
    if (bindings != null) {
      for (
        int i = 0;
        i < bindings.length && i < _TimelineTool.values.length;
        i++
      ) {
        if (_matchesTimelineShortcut(
              event,
              bindings[i],
              LogicalKeyboardKey.space,
            ) ||
            _matchesDefaultToolNumpadShortcut(event, bindings[i], i)) {
          return _TimelineTool.values[i];
        }
      }
      return null;
    }

    final index = _fallbackTimelineToolShortcutIndex(event.logicalKey);
    if (index < 0 || index >= _TimelineTool.values.length) return null;
    return _TimelineTool.values[index];
  }

  List<int> _activeSelectedClipIndices() {
    if (_selectedClipIndices.isNotEmpty) {
      final list =
          _selectedClipIndices
              .where((i) => i >= 0 && i < widget.clips.length)
              .toList()
            ..sort();
      if (list.isNotEmpty) return list;
    }
    if (_selectedClipIndex >= 0 && _selectedClipIndex < widget.clips.length) {
      return <int>[_selectedClipIndex];
    }
    return const <int>[];
  }

  bool _isClipIndexSelected(int index) {
    return index == _selectedClipIndex || _selectedClipIndices.contains(index);
  }

  String _clipVisualStackKey(AudioTrack clip, int fallbackIndex) {
    final clipId = clip.clipId.trim();
    if (clipId.isNotEmpty) return 'clip:$clipId';
    if (clip.engineClipId >= 0) return 'engine:${clip.engineClipId}';
    return 'index:$fallbackIndex';
  }

  int _clipVisualStackOrderForIndex(int index) {
    if (index < 0 || index >= widget.clips.length) return 0;
    return _clipVisualStackOrder[_clipVisualStackKey(
          widget.clips[index],
          index,
        )] ??
        0;
  }

  void _clearClipVisualStackOrder() {
    _clipVisualStackOrder.clear();
    _clipVisualStackCounter = 0;
  }

  void _setClipVisualStackSelection(
    Iterable<int> clipIndices, {
    int? primaryClipIndex,
  }) {
    _clearClipVisualStackOrder();
    final ordered =
        clipIndices
            .where((i) => i >= 0 && i < widget.clips.length)
            .toSet()
            .toList()
          ..sort();
    if (primaryClipIndex != null && ordered.remove(primaryClipIndex)) {
      ordered.add(primaryClipIndex);
    }
    for (final index in ordered) {
      _clipVisualStackOrder[_clipVisualStackKey(widget.clips[index], index)] =
          ++_clipVisualStackCounter;
    }
  }

  List<int> _clipHitTestOrder(Iterable<int> candidates) {
    return candidates.toSet().toList()..sort((a, b) {
      final stackCompare = _clipVisualStackOrderForIndex(
        b,
      ).compareTo(_clipVisualStackOrderForIndex(a));
      if (stackCompare != 0) return stackCompare;
      return b.compareTo(a);
    });
  }

  void _clearClipSelection() {
    _commitInlineClipControlIfNeeded();
    _clearInlineClipControlState();
    _clearAutomationClipSelection();
    _clearClipVisualStackOrder();
    _selectedClipIndex = -1;
    _selectedClipIndices.clear();
    _touchMultiSelectMode = false;
    _clipPopupMs = null;
    _emitSelectionChanged();
  }

  void _setSingleClipSelection(
    int clipIndex, {
    double? popupMs,
    bool emitSelectionChanged = true,
  }) {
    if (_inlineClipControlIndex != null &&
        _inlineClipControlIndex != clipIndex) {
      _commitInlineClipControlIfNeeded();
      _clearInlineClipControlState();
    }
    _selectedClipIndex = clipIndex;
    _selectedClipIndices
      ..clear()
      ..add(clipIndex);
    _setClipVisualStackSelection(<int>[clipIndex], primaryClipIndex: clipIndex);
    _clipPopupMs = popupMs;
    if (emitSelectionChanged) {
      _emitSelectionChanged();
    }
  }

  void _setPrimaryClipSelection(
    int clipIndex, {
    double? popupMs,
    bool preserveExistingSelection = false,
    bool emitSelectionChanged = true,
  }) {
    if (!preserveExistingSelection) {
      _setSingleClipSelection(
        clipIndex,
        popupMs: popupMs,
        emitSelectionChanged: emitSelectionChanged,
      );
      return;
    }
    if (_inlineClipControlIndex != null &&
        _inlineClipControlIndex != clipIndex) {
      _commitInlineClipControlIfNeeded();
      _clearInlineClipControlState();
    }
    _selectedClipIndex = clipIndex;
    _selectedClipIndices.add(clipIndex);
    _setClipVisualStackSelection(
      _selectedClipIndices,
      primaryClipIndex: clipIndex,
    );
    _clipPopupMs = null;
    if (emitSelectionChanged) {
      _emitSelectionChanged();
    }
  }

  void _toggleClipInSelection(int clipIndex) {
    if (clipIndex < 0 || clipIndex >= widget.clips.length) return;
    _commitInlineClipControlIfNeeded();
    _clearInlineClipControlState();
    _clearAutomationClipSelection();
    _clipPopupMs = null;
    if (_selectedClipIndices.remove(clipIndex)) {
      if (_selectedClipIndex == clipIndex) {
        _selectedClipIndex = _selectedClipIndices.isEmpty
            ? -1
            : _selectedClipIndices.reduce((a, b) => a > b ? a : b);
      }
    } else {
      _selectedClipIndices.add(clipIndex);
      _selectedClipIndex = clipIndex;
    }
    if (_selectedClipIndices.isEmpty) {
      _clearClipVisualStackOrder();
    } else {
      _setClipVisualStackSelection(
        _selectedClipIndices,
        primaryClipIndex: _selectedClipIndex,
      );
    }
    _emitSelectionChanged();
  }

  void _clearPendingClipDrag() {
    _pendingDrag = false;
    _pendingDragStartedFromSelection = false;
  }

  void _clearPendingClipTapState() {
    _pendingDrag = false;
    _pendingDragStartedFromSelection = false;
    _tentativeClipSelectionActive = false;
    _pendingTapSelectionClipIndex = null;
    _pendingTapSelectionPopupMs = null;
    _draggedClipIndex = null;
    _dragStartGlobalOffset = null;
    _dragStartLocalOffset = null;
    _dragXAxisLocked = false;
  }

  void _cancelClipGestureAfterTopologyChange() {
    _clearPendingClipTapState();
    _resetTrimInteractionState();
    _interactionMode = '';
    _isUserInteracting = false;
    _dragGroupStartMs.clear();
    _dragGroupStartRows.clear();
    _dragDeltaMs = 0.0;
    _dragDeltaRows = 0;
    _timelineKeyboardModifierPointer = null;
  }

  void _restoreTentativeClipSelectionIfNeeded() {
    if (!_tentativeClipSelectionActive) return;
    _tentativeClipSelectionActive = false;
    _pendingTapSelectionClipIndex = null;
    _pendingTapSelectionPopupMs = null;
  }

  bool _commitTentativeTapSelectionIfNeeded() {
    if (!_tentativeClipSelectionActive) return false;
    final pendingIndex = _pendingTapSelectionClipIndex;
    final pendingPopupMs = _pendingTapSelectionPopupMs;
    _tentativeClipSelectionActive = false;
    _pendingTapSelectionClipIndex = null;
    _pendingTapSelectionPopupMs = null;
    _clearPendingClipDrag();
    _draggedClipIndex = null;
    _dragStartGlobalOffset = null;
    _dragStartLocalOffset = null;
    if (pendingIndex != null &&
        pendingIndex >= 0 &&
        pendingIndex < widget.clips.length) {
      _setSingleClipSelection(pendingIndex, popupMs: pendingPopupMs);
    }
    _showPastePopup = false;
    _pasteRow = null;
    _pasteMs = null;
    _clearInstrumentLaneRegionPopupState();
    _highlightedSegmentRow = null;
    _highlightedSegmentStartMs = null;
    _highlightedSegmentEndMs = null;
    return true;
  }

  _TimelineGestureSelectionSnapshot _captureGestureSelectionSnapshot() {
    return _TimelineGestureSelectionSnapshot(
      selectedClipIndex: _selectedClipIndex,
      selectedClipIndices: _selectedClipIndices.toList(growable: false),
      clipPopupMs: _clipPopupMs,
      trimClipIndex: _trimClipIndex,
      activeTrimHandleX: _activeTrimHandleX,
      stretchClipIndex: _stretchClipIndex,
      selectedAutomationClipByLane: Map<String, String>.from(
        _selectedAutomationClipByLane,
      ),
      automationClipMenuClipId: _automationClipMenuClipId,
      showPastePopup: _showPastePopup,
      pasteRow: _pasteRow,
      pasteMs: _pasteMs,
      highlightedSegmentRow: _highlightedSegmentRow,
      highlightedSegmentStartMs: _highlightedSegmentStartMs,
      highlightedSegmentEndMs: _highlightedSegmentEndMs,
      inlineClipControlIndex: _inlineClipControlIndex,
      inlineClipControlKind: _inlineClipControlKind,
      inlineClipGainStart: _inlineClipGainStart,
      inlineClipPitchStart: _inlineClipPitchStart,
    );
  }

  void _restoreGestureSelectionSnapshot(
    _TimelineGestureSelectionSnapshot snapshot, {
    bool emitSelectionChanged = true,
  }) {
    _selectedClipIndex = snapshot.selectedClipIndex;
    _selectedClipIndices
      ..clear()
      ..addAll(snapshot.selectedClipIndices);
    _clipPopupMs = snapshot.clipPopupMs;
    _trimClipIndex = snapshot.trimClipIndex;
    _activeTrimHandleX = snapshot.activeTrimHandleX;
    _stretchClipIndex = snapshot.stretchClipIndex;
    _selectedAutomationClipByLane
      ..clear()
      ..addAll(snapshot.selectedAutomationClipByLane);
    _automationClipMenuClipId = snapshot.automationClipMenuClipId;
    _showPastePopup = snapshot.showPastePopup;
    _pasteRow = snapshot.pasteRow;
    _pasteMs = snapshot.pasteMs;
    _highlightedSegmentRow = snapshot.highlightedSegmentRow;
    _highlightedSegmentStartMs = snapshot.highlightedSegmentStartMs;
    _highlightedSegmentEndMs = snapshot.highlightedSegmentEndMs;
    _inlineClipControlIndex = snapshot.inlineClipControlIndex;
    _inlineClipControlKind = snapshot.inlineClipControlKind;
    _inlineClipGainStart = snapshot.inlineClipGainStart;
    _inlineClipPitchStart = snapshot.inlineClipPitchStart;
    if (emitSelectionChanged) {
      _emitSelectionChanged();
    }
  }

  String _formatAutomationEditorTime(double ms) {
    final clampedMs = math.max(0.0, ms);
    final totalSeconds = clampedMs / 1000.0;
    if (totalSeconds >= 60.0) {
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds - (minutes * 60);
      return '$minutes:${seconds.toStringAsFixed(1).padLeft(4, '0')}';
    }
    final decimals = totalSeconds >= 10.0 ? 1 : 2;
    return '${totalSeconds.toStringAsFixed(decimals)}s';
  }

  String _formatAutomationEditorRange(double startMs, double endMs) {
    return '${_formatAutomationEditorTime(startMs)} - ${_formatAutomationEditorTime(endMs)}';
  }

  void _revealAutomationRangeInViewport(double startMs, double endMs) {
    final viewportWidth = _getViewportWidth(context);
    if (viewportWidth <= 0 || _pixelsPerMs <= 0) return;
    final visibleStartMs = _scrollOffsetMs;
    final visibleEndMs = _scrollOffsetMs + (viewportWidth / _pixelsPerMs);
    final marginMs = 28.0 / _pixelsPerMs;
    final alreadyVisible =
        startMs >= (visibleStartMs + marginMs) &&
        endMs <= (visibleEndMs - marginMs);
    if (alreadyVisible) return;

    final centerMs = (startMs + endMs) / 2.0;
    _scrollOffsetMs = centerMs - ((viewportWidth / _pixelsPerMs) / 2.0);
    _clampScroll();
  }

  double _pendingClipDragActivationSlop() {
    final draggedIndex = _draggedClipIndex;
    final draggingGroup =
        draggedIndex != null &&
        _selectedClipIndices.length > 1 &&
        _selectedClipIndices.contains(draggedIndex);
    if (_pendingDragStartedFromSelection || draggingGroup) {
      return 4.0;
    }
    return 8.0;
  }

  bool _pendingClipDragExceededSlop(Offset globalPosition) {
    final dragStartGlobal = _dragStartGlobalOffset;
    if (dragStartGlobal == null) return false;
    final delta = globalPosition - dragStartGlobal;
    final threshold = _pendingClipDragActivationSlop();
    return delta.dx.abs() > threshold || delta.dy.abs() > threshold;
  }

  void _clearInlineClipControlState() {
    _inlineClipControlIndex = null;
    _inlineClipControlKind = null;
    _inlineClipGainStart = null;
    _inlineClipPitchStart = null;
  }

  void _commitInlineClipControlIfNeeded() {
    final clipIndex = _inlineClipControlIndex;
    final kind = _inlineClipControlKind;
    if (clipIndex == null ||
        kind == null ||
        clipIndex < 0 ||
        clipIndex >= widget.clips.length) {
      return;
    }
    final clip = widget.clips[clipIndex];
    final oldGain = _inlineClipGainStart;
    if (oldGain != null) {
      final newGain = clip.gain.clamp(0.0, 3.0);
      if ((newGain - oldGain).abs() > 0.0001) {
        widget.onClipGainCommit?.call(clipIndex, oldGain, newGain);
      }
    }
    final oldPitch = _inlineClipPitchStart;
    if (oldPitch != null) {
      final newPitch = clip.pitchSemitones.clamp(-12.0, 12.0);
      if ((newPitch - oldPitch).abs() > 0.0001) {
        widget.onClipPitchCommit?.call(clipIndex, oldPitch, newPitch);
      }
    }
  }

  void _closeInlineClipControl() {
    if (_inlineClipControlKind == null) return;
    setState(() {
      _commitInlineClipControlIfNeeded();
      _clearInlineClipControlState();
    });
  }

  void _syncSelectionAfterClipTopologyChange() {
    _selectedClipIndices.removeWhere((i) => i < 0 || i >= widget.clips.length);
    if (_inlineClipControlIndex != null &&
        (_inlineClipControlIndex! < 0 ||
            _inlineClipControlIndex! >= widget.clips.length)) {
      _clearInlineClipControlState();
    }
    if (_selectedClipIndex >= widget.clips.length) {
      _selectedClipIndex = -1;
      _clipPopupMs = null;
    }
    if (_selectedClipIndex >= 0 &&
        !_selectedClipIndices.contains(_selectedClipIndex)) {
      _selectedClipIndices.add(_selectedClipIndex);
    }
    if (_selectedClipIndices.isEmpty) {
      _selectedClipIndex = -1;
      _clipPopupMs = null;
      _clearClipVisualStackOrder();
    } else {
      _setClipVisualStackSelection(
        _selectedClipIndices,
        primaryClipIndex: _selectedClipIndex >= 0 ? _selectedClipIndex : null,
      );
    }
    _emitSelectionChanged();
  }

  void _syncSelectionFromWidgetConfig() {
    final nextSelected = widget.selectedClipIndices
        .where((i) => i >= 0 && i < widget.clips.length)
        .toSet();
    var nextPrimary = widget.selectedClipIndex;
    if (nextPrimary < 0 || nextPrimary >= widget.clips.length) {
      nextPrimary = -1;
    }
    if (nextPrimary >= 0) {
      nextSelected.add(nextPrimary);
    } else if (nextSelected.isNotEmpty) {
      nextPrimary = nextSelected.reduce((a, b) => a > b ? a : b);
    }

    final currentSelected = _selectedClipIndices.toList(growable: false)
      ..sort();
    final incomingSelected = nextSelected.toList(growable: false)..sort();
    if (_selectedClipIndex == nextPrimary &&
        listEquals(currentSelected, incomingSelected)) {
      return;
    }

    _selectedClipIndex = nextPrimary;
    _selectedClipIndices
      ..clear()
      ..addAll(nextSelected);
    if (_selectedClipIndex >= 0 &&
        !_selectedClipIndices.contains(_selectedClipIndex)) {
      _selectedClipIndices.add(_selectedClipIndex);
    }
    if (_selectedClipIndices.isEmpty) {
      _selectedClipIndex = -1;
      _clipPopupMs = null;
      _clearClipVisualStackOrder();
    } else {
      _setClipVisualStackSelection(
        _selectedClipIndices,
        primaryClipIndex: _selectedClipIndex >= 0 ? _selectedClipIndex : null,
      );
    }
  }

  int? _rowForLocalY(double localY) {
    if (_rowCount <= 0) return null;
    double currentY = _masterAutomationLanePaintHeight;
    for (int i = 0; i < _rowCount; i++) {
      if (!_isSourceRowVisible(i)) continue;
      final rowTotalHeight = _rowBlockHeightForIndex(i);
      if (localY >= currentY && localY < currentY + rowTotalHeight) {
        return i;
      }
      currentY += rowTotalHeight;
    }
    return null;
  }

  double _rowTopForIndex(int row) {
    if (row < 0 || row >= _rowCount) return 0.0;
    double y = _masterAutomationLanePaintHeight;
    for (int i = 0; i < row; i++) {
      if (!_isSourceRowVisible(i)) continue;
      y += _rowBlockHeightForIndex(i);
    }
    return y;
  }

  List<String> _automationTargetIdsForRow(int row) {
    final ids = <String>{'volume'};
    if (row < 0 || row >= _rowCount) return ids.toList(growable: false);
    final selected = widget.getSelectedAutomationTargetId(row).trim();
    if (selected.isNotEmpty) ids.add(selected);
    for (final target in widget.getAutomationTargetsForRow(row)) {
      final id = (target['id'] ?? '').toString().trim();
      if (id.isNotEmpty) ids.add(id);
    }
    return ids.toList(growable: false);
  }

  int _automationClipLaneCountForRow(int row) {
    if (row < 0 || row >= _rowCount) return 0;
    var maxLane = -1;
    for (final targetId in _automationTargetIdsForRow(row)) {
      final clips = widget.getAutomationClipsForTarget(row, targetId);
      for (final clip in clips) {
        final lane = math.max(0, clip.lane);
        if (lane > maxLane) maxLane = lane;
      }
    }
    return maxLane + 1;
  }

  int _automationLaneCountForRow(int row) {
    if (row < 0 || row >= _rowCount) return 0;
    final fromClips = _automationClipLaneCountForRow(row);
    final extra = math.max(0, _extraAutomationTimelineLanesByRow[row] ?? 0);
    return math.max(fromClips + extra, 0);
  }

  bool _isAutomationTimelineCollapsedForRow(int row) {
    return _collapsedAutomationTimelineByRow[row] == true;
  }

  int _automationTimelineVisibleLaneCountForRow(int row) {
    final laneCount = _automationLaneCountForRow(row);
    if (laneCount <= 0) return 0;
    if (_isAutomationTimelineCollapsedForRow(row)) {
      return 1;
    }
    return laneCount;
  }

  double _automationTimelineSingleLaneHeightForRow(int row) {
    return _isAutomationTimelineCollapsedForRow(row)
        ? _kTimelineAutomationLaneCollapsedHeight
        : _kTimelineAutomationLaneExpandedHeight;
  }

  int _normalizedAutomationLaneForRow(int row, int lane) {
    final laneCount = _automationLaneCountForRow(row);
    if (laneCount <= 0) return 0;
    return lane.clamp(0, laneCount - 1).toInt();
  }

  int _focusedAutomationLaneForRow(int row) {
    final laneCount = _automationLaneCountForRow(row);
    if (laneCount <= 0) return 0;
    final focused = _automationLaneFocusByRow[row] ?? 0;
    return focused.clamp(0, laneCount - 1).toInt();
  }

  bool _isAutomationEditorOpenForRow(int row) {
    return _automationEditorRow == row &&
        (_automationEditorTargetId?.trim().isNotEmpty ?? false);
  }

  void _clearPendingAutomationClipSelection() {
    _pendingAutomationClipVisual = null;
    _pendingAutomationClipStartLocalOffset = null;
    _pendingAutomationClipInteractionMode = null;
  }

  void _setAutomationClipMenuFor(_TimelineAutomationClipVisual clipVisual) {
    _automationClipMenuRow = clipVisual.row;
    _automationClipMenuTargetId = clipVisual.targetId;
    _automationClipMenuClipId = clipVisual.clip.id;
  }

  void _clearAutomationClipMenu() {
    _automationClipMenuRow = null;
    _automationClipMenuTargetId = null;
    _automationClipMenuClipId = null;
  }

  void _clearAutomationClipSelection() {
    _selectedAutomationClipByLane.clear();
    _clearAutomationClipMenu();
  }

  bool _isAutomationClipMenuVisibleFor(
    _TimelineAutomationClipVisual clipVisual,
  ) {
    return _automationClipMenuRow == clipVisual.row &&
        _automationClipMenuTargetId == clipVisual.targetId &&
        _automationClipMenuClipId == clipVisual.clip.id;
  }

  _TimelineAutomationClipVisual? _currentAutomationClipMenuVisual(
    List<_TimelineAutomationClipVisual> visuals,
  ) {
    final row = _automationClipMenuRow;
    final targetId = _automationClipMenuTargetId;
    final clipId = _automationClipMenuClipId;
    if (row == null || targetId == null || clipId == null) {
      return null;
    }
    for (final visual in visuals) {
      if (visual.row == row &&
          visual.targetId == targetId &&
          visual.clip.id == clipId) {
        return visual;
      }
    }
    return null;
  }

  Map<String, dynamic>? _automationTargetMetaById(int row, String targetId) {
    final targets = widget.getAutomationTargetsForRow(row);
    for (final target in targets) {
      final id = (target['id'] ?? '').toString().trim();
      if (id == targetId.trim()) {
        return Map<String, dynamic>.from(target);
      }
    }
    if (targetId.trim() == 'volume') {
      return <String, dynamic>{
        'id': 'volume',
        'label': 'Volume',
        'fullLabel': 'Volume',
        'isVolume': true,
        'isOrphan': false,
        'paramId': 'volume',
        'min': 0.0,
        'max': 1.0,
        'initialNormalized': 0.75,
      };
    }
    return null;
  }

  bool _isMasterAutomationTargetId(String targetId) {
    final normalized = targetId.trim().toLowerCase();
    return normalized.startsWith('master:') ||
        normalized.startsWith('masterfxid:');
  }

  bool get _isMasterAutomationLaneOpen =>
      _masterAutomationEditorTargetId != null &&
      _masterAutomationEditorTargetId!.trim().isNotEmpty &&
      _rowCount > 0;

  double get _masterAutomationLaneHeight =>
      math.max(_kMasterAutomationLaneMinHeight, _expandedRowHeight + 8.0);

  double get _masterAutomationLanePaintHeight =>
      _isMasterAutomationLaneOpen &&
          _automationTargetsForMasterLane().isNotEmpty
      ? _masterAutomationLaneHeight
      : 0.0;

  List<Map<String, dynamic>> _automationTargetsForMasterLane() {
    if (_rowCount <= 0) return const <Map<String, dynamic>>[];
    final targets = <Map<String, dynamic>>[];
    for (final raw in widget.getAutomationTargetsForRow(0)) {
      final target = Map<String, dynamic>.from(raw);
      final id = (target['id'] ?? '').toString().trim();
      if (id.isEmpty || !_isMasterAutomationTargetId(id)) continue;
      targets.add(target);
    }
    return targets;
  }

  String _resolveAutomationTargetIdFromTargets(
    List<Map<String, dynamic>> targets,
    String preferredTargetId,
  ) {
    final preferred = preferredTargetId.trim();
    if (preferred.isNotEmpty &&
        targets.any(
          (target) => (target['id'] ?? '').toString().trim() == preferred,
        )) {
      return preferred;
    }
    if (targets.isEmpty) return preferred.isEmpty ? 'volume' : preferred;
    return (targets.first['id'] ?? preferred).toString().trim();
  }

  List<Map<String, dynamic>> _automationTargetsForAutomationTab(int row) {
    if (row < 0 || row >= _rowCount) return const <Map<String, dynamic>>[];
    final targets = widget.getAutomationTargetsForRow(row);
    final filtered = <Map<String, dynamic>>[];
    for (final raw in targets) {
      final target = Map<String, dynamic>.from(raw);
      final id = (target['id'] ?? '').toString().trim();
      if (id.isEmpty || _isMasterAutomationTargetId(id)) continue;
      filtered.add(target);
    }
    final hasVolume = filtered.any(
      (target) => (target['id'] ?? '').toString().trim() == 'volume',
    );
    if (!hasVolume) {
      filtered.insert(0, <String, dynamic>{
        'id': 'volume',
        'label': 'Volume',
        'fullLabel': 'Volume',
        'isVolume': true,
        'isOrphan': false,
        'paramId': 'volume',
        'min': 0.0,
        'max': 1.0,
        'initialNormalized': 0.75,
      });
    }
    return filtered;
  }

  String _resolveAutomationTabTargetId(int row, String preferredTargetId) {
    final candidates = _automationTargetsForAutomationTab(row);
    if (candidates.isEmpty) return 'volume';
    final preferred = preferredTargetId.trim();
    final hasPreferred = candidates.any(
      (target) => (target['id'] ?? '').toString().trim() == preferred,
    );
    if (hasPreferred) return preferred;
    return (candidates.first['id'] ?? 'volume').toString().trim();
  }

  void _openAutomationTabForTarget({
    required int row,
    required String targetId,
    List<String> haloKeys = const <String>[],
  }) {
    if (row < 0 || row >= _rowCount) return;
    final resolvedTargetId = _resolveAutomationTabTargetId(row, targetId);
    final oldExpanded = List<bool>.from(_rowExpanded);
    setState(() {
      _clearAutomationClipMenu();
      _selectedRowIndex = row;
      widget.onSelectRow(row);
      widget.setSelectedAutomationTargetId(row, resolvedTargetId);
      _expandRowForFocusedTarget(row);
      _expandedTab[row] = _normalizeExpandedTab(2);
      _automationEditorRow = row;
      _automationEditorTargetId = resolvedTargetId;
      _automationTargetPickerRow = null;
    });
    _notifyRowExpansionChanges(oldExpanded);
    widget.onRowTabSelected?.call(row, 2);
    widget.onTutorialRowTabSelected?.call(row, 2);
    _triggerTimelineHalos(<String>['row:$row:automation_tab', ...haloKeys]);
  }

  void _expandRowForFocusedTarget(int row) {
    if (row < 0 || row >= _rowExpanded.length) return;
    if (_allowsMultipleExpandedRows) {
      _rowExpanded[row] = true;
      return;
    }
    for (int i = 0; i < _rowExpanded.length; i++) {
      _rowExpanded[i] = i == row;
    }
  }

  void _enforceSingleExpandedRowIfNeeded({bool notify = false}) {
    if (_allowsMultipleExpandedRows) return;
    var retainedExpandedRow = -1;
    if (_selectedRowIndex >= 0 &&
        _selectedRowIndex < _rowExpanded.length &&
        _rowExpanded[_selectedRowIndex]) {
      retainedExpandedRow = _selectedRowIndex;
    } else {
      retainedExpandedRow = _rowExpanded.indexWhere((expanded) => expanded);
    }
    if (retainedExpandedRow < 0) return;

    final oldExpanded = List<bool>.from(_rowExpanded);
    for (int i = 0; i < _rowExpanded.length; i++) {
      _rowExpanded[i] = i == retainedExpandedRow;
    }
    if (notify) {
      _notifyRowExpansionChanges(oldExpanded);
    }
  }

  void _notifyRowExpansionChanges(
    List<bool> oldExpanded, {
    bool notifyToggle = false,
  }) {
    var changed = false;
    for (int i = 0; i < oldExpanded.length && i < _rowExpanded.length; i++) {
      if (oldExpanded[i] == _rowExpanded[i]) continue;
      changed = true;
      if (notifyToggle) {
        widget.onToggleExpanded(i);
      }
      widget.onRowExpansionChanged?.call(i, _rowExpanded[i]);
      widget.onTutorialRowExpansionChanged?.call(i, _rowExpanded[i]);
    }
    if (changed) {
      final hasFloatingTimelineMenu =
          _selectedClipIndex >= 0 ||
          _selectedClipIndices.isNotEmpty ||
          _clipPopupMs != null ||
          _showPastePopup ||
          _pasteRow != null ||
          _automationClipMenuClipId != null;
      if (hasFloatingTimelineMenu && mounted) {
        setState(_clearTimelineSelectionFeedback);
      }
      _syncVerticalScrollOffsetAfterGeometryChange();
    }
  }

  String _haloSlug(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  void _applyExpandedTabStateForRow(int row, int normalizedTab) {
    if (row < 0 || row >= _rowCount) return;
    if (normalizedTab == 2) {
      final selectedTarget = _resolveAutomationTabTargetId(
        row,
        widget.getSelectedAutomationTargetId(row),
      );
      widget.setSelectedAutomationTargetId(row, selectedTarget);
      _automationEditorRow = row;
      _automationEditorTargetId = selectedTarget;
    } else if (_automationEditorRow == row) {
      _automationEditorRow = null;
      _automationEditorTargetId = null;
    }
    if (normalizedTab != 2 || _automationTargetPickerRow != row) {
      _automationTargetPickerRow = null;
    }
    _expandedTab[row] = normalizedTab;
    if (normalizedTab != 2 && _automationRangeSelectionRow == row) {
      _clearAutomationRangeSelectionMode();
    }
  }

  void _setExpandedTabForRow({
    required int row,
    required int tab,
    bool selectRow = false,
    bool expandOnlyThisRow = false,
    String? selectedAutomationTargetId,
  }) {
    if (row < 0 || row >= _rowCount) return;
    final normalizedTab = _normalizeExpandedTab(tab);
    final oldExpanded = List<bool>.from(_rowExpanded);
    setState(() {
      if (selectRow) {
        _selectedRowIndex = row;
        widget.onSelectRow(row);
      }
      if (selectedAutomationTargetId != null &&
          selectedAutomationTargetId.trim().isNotEmpty) {
        widget.setSelectedAutomationTargetId(row, selectedAutomationTargetId);
      }
      if (expandOnlyThisRow) {
        _expandRowForFocusedTarget(row);
      }
      _applyExpandedTabStateForRow(row, normalizedTab);
    });
    _notifyRowExpansionChanges(oldExpanded);
    widget.onRowTabSelected?.call(row, normalizedTab);
    widget.onTutorialRowTabSelected?.call(row, normalizedTab);
  }

  Future<Future<void> Function(int, String)?> _waitForRowParameterRevealer(
    int row, {
    int maxAttempts = 10,
  }) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted || row < 0 || row >= _rowCount) return null;
      final rowId = widget.rows[row].rowId;
      final revealer = _rowEffectParameterRevealers[rowId];
      if (revealer != null) return revealer;
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    return null;
  }

  void _triggerTimelineHalos(List<String> haloKeys) {
    final highlighter = widget.tutorialHighlighter;
    if (highlighter == null || haloKeys.isEmpty) return;
    final mapped = haloKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .map(HaloKey.new)
        .toList(growable: false);
    if (mapped.isEmpty) return;
    highlighter.trigger(mapped, duration: const Duration(milliseconds: 800));
  }

  void _setAutomationEditorFor(int row, String targetId) {
    if (row < 0 || row >= _rowCount) return;
    final resolvedTargetId = _resolveAutomationTabTargetId(row, targetId);
    _clearAutomationClipMenu();
    widget.setSelectedAutomationTargetId(row, resolvedTargetId);
    _selectedRowIndex = row;
    widget.onSelectRow(row);
    _expandRowForFocusedTarget(row);
    _expandedTab[row] = _normalizeExpandedTab(2);
    _automationEditorRow = row;
    _automationEditorTargetId = resolvedTargetId;
    _automationTargetPickerRow = null;
  }

  void _closeAutomationEditor() {
    if (_automationEditorRow == null && _automationEditorTargetId == null) {
      return;
    }
    setState(() {
      final row = _automationEditorRow;
      if (row != null && row >= 0 && row < _expandedTab.length) {
        _expandedTab[row] = _normalizeExpandedTab(0);
      }
      _automationEditorRow = null;
      _automationEditorTargetId = null;
      _automationTargetPickerRow = null;
    });
  }

  void _setFocusedAutomationLaneForRow(int row, int lane) {
    final normalized = _normalizedAutomationLaneForRow(row, lane);
    if ((_automationLaneFocusByRow[row] ?? 0) == normalized) return;
    _automationLaneFocusByRow[row] = normalized;
  }

  void _addAutomationTimelineLaneForRow(int row) {
    if (row < 0 || row >= _rowCount) return;
    final before = _automationLaneCountForRow(row);
    _extraAutomationTimelineLanesByRow[row] =
        math.max(0, _extraAutomationTimelineLanesByRow[row] ?? 0) + 1;
    final after = _automationLaneCountForRow(row);
    _setFocusedAutomationLaneForRow(row, math.max(0, after - 1));
    if (after != before) {
      setState(() {});
    }
  }

  void _toggleAutomationTimelineCollapseForRow(int row) {
    if (row < 0 || row >= _rowCount) return;
    final collapsed = _isAutomationTimelineCollapsedForRow(row);
    _collapsedAutomationTimelineByRow[row] = !collapsed;
    setState(() {});
  }

  void _swapAutomationTimelineLanesForRow(int row, int a, int b) {
    if (row < 0 || row >= _rowCount || a == b) return;
    final laneCount = _automationLaneCountForRow(row);
    if (laneCount <= 1) return;
    final from = a.clamp(0, laneCount - 1).toInt();
    final to = b.clamp(0, laneCount - 1).toInt();
    if (from == to) return;

    var changed = false;
    for (final targetId in _automationTargetIdsForRow(row)) {
      final before = _cloneAutomationClips(
        widget.getAutomationClipsForTarget(row, targetId),
      );
      if (before.isEmpty) continue;
      var targetChanged = false;
      final next = before
          .map((clip) {
            final lane = math.max(0, clip.lane);
            if (lane == from) {
              targetChanged = true;
              return clip.copyWith(lane: to);
            }
            if (lane == to) {
              targetChanged = true;
              return clip.copyWith(lane: from);
            }
            return clip.copyWith();
          })
          .toList(growable: false);
      if (!targetChanged) continue;
      changed = true;
      _applyAutomationClipsWithCommit(row, targetId, before, next);
    }
    if (!changed) return;
    _setFocusedAutomationLaneForRow(row, to);
    setState(() {});
  }

  double _automationTimelineLaneHeightForRow(int row) {
    return 0.0;
  }

  double _automationTimelineLaneTopForRowLane(int row, int lane) {
    final rowTop = _rowTopForIndex(row);
    final clampedLane = math.max(0, lane);
    final laneHeight = _automationTimelineSingleLaneHeightForRow(row);
    return rowTop +
        _rowHeight +
        _kTimelineAutomationLaneInset +
        (clampedLane * (laneHeight + _kTimelineAutomationLaneGap));
  }

  int _timelineAutomationLaneIndexAtLocalY(int row, double localY) {
    return 0;
  }

  double _expandedPanelHeightForRow(int row) {
    if (row < 0 || row >= _rowCount || !_rowExpanded[row]) return 0.0;
    if (_isAutomationEditorOpenForRow(row)) {
      return math.max(_expandedRowHeight, _effectsPanelMinHeight);
    }
    return _isFixedHeightExpandedTab(_expandedTab[row])
        ? math.max(_expandedRowHeight, _effectsPanelMinHeight)
        : _effectsPanelHeights[row];
  }

  double _rowBlockHeightForIndex(int row) {
    return _rowHeight + _expandedPanelHeightForRow(row);
  }

  String _headerPeakLevelLabel(double peakDb) {
    if (peakDb >= -0.1) return '0.0 dBFS';
    if (!peakDb.isFinite || peakDb <= -120.0) return '-∞ dBFS';
    return '${peakDb.toStringAsFixed(1)} dBFS';
  }

  Color _headerPeakLevelColor(double peakDb) {
    if (!peakDb.isFinite || peakDb <= -120.0) {
      return Colors.white.withValues(alpha: 0.50);
    }
    return DbfsMeterVisuals.statusColor(peakDb);
  }

  double _heldPeakDbForHeaderRow(int row, MeterFrame frame) {
    if (row < 0 || row >= _rowCount) return double.negativeInfinity;
    final rowId = widget.rows[row].rowId;
    final now = DateTime.now();
    final currentPeakDb = DbfsMeterVisuals.ampToDbfs(
      math.max(frame.peakL, frame.peakR),
    );

    final prevDb = _headerPeakHoldDbByRowId[rowId] ?? currentPeakDb;
    final lastUpdate = _headerPeakHoldLastUpdateByRowId[rowId] ?? now;
    final freezeUntil = _headerPeakHoldFreezeUntilByRowId[rowId] ?? now;
    final dt = (now.difference(lastUpdate).inMicroseconds / 1000000.0).clamp(
      0.0,
      0.25,
    );

    double heldDb = prevDb;
    if (!currentPeakDb.isFinite || currentPeakDb <= -120.0) {
      heldDb = double.negativeInfinity;
      _headerPeakHoldFreezeUntilByRowId[rowId] = now;
    } else if (currentPeakDb >= prevDb || !prevDb.isFinite) {
      heldDb = currentPeakDb;
      _headerPeakHoldFreezeUntilByRowId[rowId] = now.add(
        _kHeaderPeakHoldFreeze,
      );
    } else if (now.isAfter(freezeUntil)) {
      heldDb = math.max(
        currentPeakDb,
        prevDb - (_kHeaderPeakHoldDecayDbPerSec * dt),
      );
    }
    if (heldDb <= -120.0) {
      heldDb = double.negativeInfinity;
    }

    _headerPeakHoldDbByRowId[rowId] = heldDb;
    _headerPeakHoldLastUpdateByRowId[rowId] = now;
    return heldDb;
  }

  int _defaultAutomationClipRowForSourceRow(int row) {
    if (_rowCount <= 0) return 0;
    return (row + 1).clamp(0, _rowCount - 1).toInt();
  }

  int _preferredAutomationClipRowForTarget(int row, String targetId) {
    final normalized = targetId.trim().toLowerCase();
    final isMaster =
        normalized.startsWith('master:') ||
        normalized.startsWith('masterfxid:');
    if (!isMaster || _rowCount <= 0) {
      return _defaultAutomationClipRowForSourceRow(row);
    }
    _ensureClipSpatialIndex();
    final occupiedRows = _clipSpatialIndexByRow.keys;
    for (int candidate = 0; candidate < _rowCount; candidate++) {
      if (!occupiedRows.contains(candidate)) {
        return candidate;
      }
    }
    return 0;
  }

  bool _isLocalYInMainTrackLane(int row, double localY) {
    final rowTop = _rowTopForIndex(row);
    return localY >= rowTop && localY < rowTop + _rowHeight;
  }

  Map<String, String> _automationTargetLabelsForRow(int row) {
    final labels = <String, String>{'volume': 'Volume'};
    for (final target in widget.getAutomationTargetsForRow(row)) {
      final id = (target['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final label = (target['label'] ?? id).toString().trim();
      labels[id] = label.isEmpty ? id : label;
    }
    return labels;
  }

  List<_TimelineAutomationClipVisual> _timelineAutomationClipVisuals() {
    return const <_TimelineAutomationClipVisual>[];
    /*
    if (_rowCount <= 0) return const <_TimelineAutomationClipVisual>[];
    final visuals = <_TimelineAutomationClipVisual>[];
    const minWidthPx = 14.0;
    const clipTopInset = 2.0;
    const clipHeight = kRowHeight - 4.0;

    for (int row = 0; row < _rowCount; row++) {
      final labelsById = _automationTargetLabelsForRow(row);
      for (final targetId in _automationTargetIdsForRow(row)) {
        if (targetId.trim().isEmpty) continue;
        final targetMeta = _automationTargetMetaById(row, targetId);
        final targetLabel = labelsById[targetId] ?? targetId;
        final targetFullLabel =
            (targetMeta?['fullLabel'] ?? targetMeta?['label'] ?? targetLabel)
                .toString()
                .trim();
        final isOrphan = targetMeta?['isOrphan'] == true;
        final selectedClipId = _selectedAutomationClipIdFor(row, targetId);
        final laneClips = widget.getAutomationClipsForTarget(row, targetId);
        if (laneClips.isEmpty) continue;

        for (final clip in laneClips) {
          final displayRow =
              clip.row.clamp(0, math.max(0, _rowCount - 1)).toInt();
          final laneTop = _rowTopForIndex(displayRow) + clipTopInset;
          final left = (clip.startMs - _scrollOffsetMs) * _pixelsPerMs;
          final width = math.max(minWidthPx, clip.lengthMs * _pixelsPerMs);
          final rect = Rect.fromLTWH(left, laneTop, width, clipHeight);
          visuals.add(
            _TimelineAutomationClipVisual(
              row: row,
              displayRow: displayRow,
              targetId: targetId,
              targetLabel: targetLabel,
              fullTargetLabel: targetFullLabel.isNotEmpty
                  ? targetFullLabel
                  : (clip.label.trim().isNotEmpty
                      ? clip.label.trim()
                      : targetLabel),
              clip: clip,
              laneIndex: 0,
              rect: rect,
              isSelected: clip.id == selectedClipId,
              isOrphan: isOrphan,
            ),
          );
        }
      }
    }

    visuals.sort((a, b) {
      final rowCmp = a.displayRow.compareTo(b.displayRow);
      if (rowCmp != 0) return rowCmp;
      final startCmp = a.clip.startMs.compareTo(b.clip.startMs);
      if (startCmp != 0) return startCmp;
      if (a.isSelected != b.isSelected) {
        return a.isSelected ? 1 : -1;
      }
      return a.clip.id.compareTo(b.clip.id);
    });
    return visuals;
    */
  }

  _TimelineAutomationClipVisual? _timelineAutomationClipAt(Offset localPos) {
    final visuals = _timelineAutomationClipVisualCache.isNotEmpty
        ? _timelineAutomationClipVisualCache
        : _timelineAutomationClipVisuals();
    if (visuals.isEmpty) return null;
    _TimelineAutomationClipVisual? best;

    int compareVisuals(
      _TimelineAutomationClipVisual a,
      _TimelineAutomationClipVisual b,
    ) {
      final rowCmp = a.displayRow.compareTo(b.displayRow);
      if (rowCmp != 0) return rowCmp;
      final startCmp = a.clip.startMs.compareTo(b.clip.startMs);
      if (startCmp != 0) return startCmp;
      if (a.isSelected != b.isSelected) {
        return a.isSelected ? 1 : -1;
      }
      return a.clip.id.compareTo(b.clip.id);
    }

    for (final visual in visuals) {
      if (!visual.rect.contains(localPos)) continue;
      if (best == null || compareVisuals(visual, best!) > 0) {
        best = visual;
      }
    }

    return best;
  }

  Rect _automationClipMoveHandleRect(_TimelineAutomationClipVisual visual) {
    final width = math.min(22.0, math.max(14.0, visual.rect.width * 0.22));
    final height = math.min(20.0, math.max(14.0, visual.rect.height - 8.0));
    final top = visual.rect.top + ((visual.rect.height - height) / 2.0);
    return Rect.fromLTWH(visual.rect.left + 4.0, top, width, height);
  }

  bool _automationClipLeftTrimHandleHit(
    _TimelineAutomationClipVisual visual,
    Offset localPos,
  ) {
    final hitWidth = math.min(math.max(12.0, visual.rect.width * 0.18), 20.0);
    return localPos.dx >= visual.rect.left &&
        localPos.dx <= visual.rect.left + hitWidth;
  }

  bool _automationClipRightTrimHandleHit(
    _TimelineAutomationClipVisual visual,
    Offset localPos,
  ) {
    final hitWidth = math.min(math.max(12.0, visual.rect.width * 0.18), 20.0);
    return localPos.dx <= visual.rect.right &&
        localPos.dx >= visual.rect.right - hitWidth;
  }

  AutomationClipSnapshot? _activeDraggedAutomationClip() {
    final row = _automationClipDragRow;
    final targetId = _automationClipDragTargetId;
    final clipId = _automationClipDragId;
    if (row == null || targetId == null || clipId == null) return null;
    final laneClips = widget.getAutomationClipsForTarget(row, targetId);
    for (final clip in laneClips) {
      if (clip.id == clipId) return clip;
    }
    return null;
  }

  void _ensureClipSpatialIndex() {
    if (widget.clipLayoutRevision >= 0 &&
        _clipSpatialIndexRevision == widget.clipLayoutRevision &&
        _clipSpatialIndexClipCount == widget.clips.length) {
      return;
    }

    final liveClipLayoutGesture =
        _trimClipIndex != null ||
        _stretchClipIndex != null ||
        widget.recordingInProgress;
    if (liveClipLayoutGesture &&
        _clipSpatialIndexClipCount == widget.clips.length &&
        _clipSpatialIndexTopologyRevision == widget.clipTopologyRevision) {
      return;
    }

    final canApplyIncrementally =
        widget.clipLayoutRevision >= 0 &&
        widget.clipTopologyRevision >= 0 &&
        _clipSpatialIndexRevision >= widget.clipLayoutMutationFloorRevision &&
        _clipSpatialIndexTopologyRevision == widget.clipTopologyRevision &&
        _clipSpatialIndexClipCount == widget.clips.length;
    if (canApplyIncrementally && _applyClipSpatialIndexMutations()) {
      return;
    }

    final entriesByRow = <int, List<_TimelineClipSpatialEntry>>{};
    _clipSpatialIndexByClip.clear();
    _clipSpatialEntryByClip.clear();
    for (int index = 0; index < widget.clips.length; index++) {
      final clip = widget.clips[index];
      _clipSpatialIndexByClip[clip] = index;
      final entry = _spatialEntryForClip(clip, index);
      if (entry == null) continue;
      _clipSpatialEntryByClip[clip] = entry;
      (entriesByRow[clip.rowIndex] ??= <_TimelineClipSpatialEntry>[]).add(
        entry,
      );
    }

    _clipSpatialIndexByRow = entriesByRow.map(
      (row, entries) => MapEntry(row, _TimelineClipRowSpatialIndex(entries)),
    );
    _clipSpatialIndexTopologyRevision = widget.clipTopologyRevision;
    _clipSpatialIndexRevision = widget.clipLayoutRevision;
    _clipSpatialIndexClipCount = widget.clips.length;
  }

  _TimelineClipSpatialEntry? _spatialEntryForClip(AudioTrack clip, int index) {
    final startMs = widget.getStartMs(clip);
    final durationMs = widget.getTimelineDurationMs(clip);
    if (!startMs.isFinite || !durationMs.isFinite || durationMs <= 0.0) {
      return null;
    }
    return _TimelineClipSpatialEntry(
      clip: clip,
      clipIndex: index,
      rowIndex: clip.rowIndex,
      startMs: startMs,
      endMs: startMs + durationMs,
      snapStartMs: startMs + widget.getTrimStartMs(clip),
    );
  }

  bool _applyClipSpatialIndexMutations() {
    if (_clipSpatialIndexRevision == widget.clipLayoutRevision) return true;
    final mutations = widget.clipLayoutMutations
        .where((mutation) => mutation.revision > _clipSpatialIndexRevision)
        .toList(growable: false);
    if (mutations.isEmpty ||
        mutations.last.revision != widget.clipLayoutRevision) {
      return false;
    }

    final changedClips = HashSet<AudioTrack>.identity();
    final affectedRows = <int>{};
    for (final mutation in mutations) {
      final clip = mutation.clip;
      final index = _clipSpatialIndexByClip[clip];
      if (index == null ||
          index < 0 ||
          index >= widget.clips.length ||
          !identical(widget.clips[index], clip)) {
        return false;
      }
      changedClips.add(clip);
      final oldEntry = _clipSpatialEntryByClip[clip];
      if (oldEntry != null) affectedRows.add(oldEntry.rowIndex);
      affectedRows.add(clip.rowIndex);
    }

    final replacementEntries = <int, List<_TimelineClipSpatialEntry>>{};
    for (final row in affectedRows) {
      replacementEntries[row] =
          _clipSpatialIndexByRow[row]?.entries
              .where((entry) => !changedClips.contains(entry.clip))
              .toList(growable: true) ??
          <_TimelineClipSpatialEntry>[];
    }
    for (final clip in changedClips) {
      _clipSpatialEntryByClip.remove(clip);
      final index = _clipSpatialIndexByClip[clip]!;
      final entry = _spatialEntryForClip(clip, index);
      if (entry == null) continue;
      _clipSpatialEntryByClip[clip] = entry;
      (replacementEntries[clip.rowIndex] ??= <_TimelineClipSpatialEntry>[]).add(
        entry,
      );
    }

    final nextByRow = Map<int, _TimelineClipRowSpatialIndex>.from(
      _clipSpatialIndexByRow,
    );
    for (final row in affectedRows) {
      final entries = replacementEntries[row];
      if (entries == null || entries.isEmpty) {
        nextByRow.remove(row);
      } else {
        nextByRow[row] = _TimelineClipRowSpatialIndex(entries);
      }
    }
    _clipSpatialIndexByRow = nextByRow;
    _clipSpatialIndexRevision = widget.clipLayoutRevision;
    return true;
  }

  List<int> _visibleClipIndices({
    required double viewportWidth,
    required double visibleTimelineHeight,
    double leftExtensionPx = 0.0,
  }) {
    _ensureClipSpatialIndex();
    if (_clipSpatialIndexByRow.isEmpty || _pixelsPerMs <= 0.0) {
      return const <int>[];
    }

    const horizontalPrefetchPx = 96.0;
    final startMs =
        _scrollOffsetMs -
        ((leftExtensionPx + horizontalPrefetchPx) / _pixelsPerMs);
    final endMs =
        _scrollOffsetMs +
        ((viewportWidth + horizontalPrefetchPx) / _pixelsPerMs);
    final visibleTop = _verticalScrollOffset;
    final visibleBottom = visibleTop + visibleTimelineHeight;
    final visible = <int>{};

    for (final entry in _clipSpatialIndexByRow.entries) {
      final row = entry.key;
      if (row < 0 || row >= _rowCount || !_isSourceRowVisible(row)) continue;
      final rowTop = _rowTopForIndex(row);
      final rowBottom = rowTop + _rowHeight;
      if (rowBottom < visibleTop || rowTop > visibleBottom) continue;
      entry.value.addIntersecting(startMs, endMs, visible);
    }

    final dragged = _draggedClipIndex;
    if (dragged != null && dragged >= 0 && dragged < widget.clips.length) {
      visible.add(dragged);
    }
    for (final selected in _selectedClipIndices) {
      if (selected >= 0 && selected < widget.clips.length) {
        visible.add(selected);
      }
    }
    return visible.toList(growable: false);
  }

  int? _clipIndexAtRowAndMs(int row, double timeMs) {
    _ensureClipSpatialIndex();
    return _clipSpatialIndexByRow[row]?.topmostAt(timeMs);
  }

  double? _nearestClipBoundaryMs(
    int row,
    double timeMs, {
    double toleranceMs = 20.0,
  }) {
    _ensureClipSpatialIndex();
    return _clipSpatialIndexByRow[row]?.nearestBoundaryWithin(
      timeMs,
      toleranceMs,
    );
  }

  void _clearExternalSampleDropPreview() {
    final wasInsideTimeline = _externalSampleDragInsideTimeline;
    if (!wasInsideTimeline &&
        _externalSampleDropRow == null &&
        _externalSampleDropStartMs == null &&
        _externalSampleDropEndMs == null) {
      return;
    }
    setState(() {
      _externalSampleDragInsideTimeline = false;
      _externalSampleDropRow = null;
      _externalSampleDropStartMs = null;
      _externalSampleDropEndMs = null;
      _externalSampleDropAllowed = true;
    });
  }

  double _sampleDropDurationMs(SampleDragData? data) {
    final durationMs = data?.duration?.inMilliseconds.toDouble();
    if (durationMs != null && durationMs.isFinite && durationMs > 1) {
      return durationMs;
    }
    if (_magnetEnabled) {
      return _quantizeIntervalMs();
    }
    return 900.0;
  }

  SampleDropPlacement? _sampleDropPlacementForGlobalOffset(
    Offset globalOffset, {
    SampleDragData? data,
  }) {
    final targetContext = _externalSampleDropTargetKey.currentContext;
    if (targetContext == null) return null;
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    // Finder drag locations are Flutter-view logical coordinates (top-left
    // origin), which match DragTarget global coordinates on desktop.
    final local = renderObject.globalToLocal(globalOffset);
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > renderObject.size.width ||
        local.dy > renderObject.size.height) {
      return null;
    }
    final row = _rowForLocalY(local.dy);
    if (row == null) return null;
    final rawMs = (_scrollOffsetMs + local.dx / _pixelsPerMs)
        .clamp(0.0, double.infinity)
        .toDouble();
    final startMs = _magnetEnabled ? _segmentStartMsForTap(rawMs) : rawMs;
    final endMs = startMs + _sampleDropDurationMs(data);
    return SampleDropPlacement(
      row: row,
      startMs: startMs,
      endMs: endMs,
      allowed: !_isInstrumentLane(row),
    );
  }

  bool _updateExternalSampleDropPreview(
    Offset globalOffset, {
    SampleDragData? data,
    bool notifyEntered = false,
  }) {
    final placement = _sampleDropPlacementForGlobalOffset(
      globalOffset,
      data: data,
    );
    if (placement == null) {
      _clearExternalSampleDropPreview();
      return false;
    }
    if (notifyEntered && !_externalSampleDragInsideTimeline) {
      _externalSampleDragInsideTimeline = true;
      widget.onExternalSampleDragEntered?.call();
    }
    if (_externalSampleDropRow == placement.row &&
        _externalSampleDropStartMs == placement.startMs &&
        _externalSampleDropEndMs == placement.endMs &&
        _externalSampleDropAllowed == placement.allowed) {
      return true;
    }
    setState(() {
      _externalSampleDropRow = placement.row;
      _externalSampleDropStartMs = placement.startMs;
      _externalSampleDropEndMs = placement.endMs;
      _externalSampleDropAllowed = placement.allowed;
    });
    return true;
  }

  void _updateExternalSampleDropPreviewForOsDrag(
    Offset globalOffset, {
    SampleDragData? data,
  }) {
    _updateExternalSampleDropPreview(
      globalOffset,
      data: data,
      notifyEntered: true,
    );
  }

  Rect? _currentSelectionRect() {
    if (!_selectionBoxActive ||
        _selectionBoxStart == null ||
        _selectionBoxCurrent == null) {
      return null;
    }
    final left = math.min(_selectionBoxStart!.dx, _selectionBoxCurrent!.dx);
    final right = math.max(_selectionBoxStart!.dx, _selectionBoxCurrent!.dx);
    final top = math.min(_selectionBoxStart!.dy, _selectionBoxCurrent!.dy);
    final bottom = math.max(_selectionBoxStart!.dy, _selectionBoxCurrent!.dy);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  bool _rectsOverlapInclusive(Rect a, Rect b) {
    return a.left <= b.right &&
        b.left <= a.right &&
        a.top <= b.bottom &&
        b.top <= a.bottom;
  }

  void _updateSelectionFromRect(Rect rect) {
    final selected = <int>{..._selectionBoxBaseClipIndices};
    _ensureClipSpatialIndex();
    final startMs = _scrollOffsetMs + (rect.left / _pixelsPerMs);
    final endMs = _scrollOffsetMs + (rect.right / _pixelsPerMs);
    final candidates = <int>{};
    for (final entry in _clipSpatialIndexByRow.entries) {
      final row = entry.key;
      if (row < 0 || row >= _rowCount || !_isSourceRowVisible(row)) continue;
      final rowTop = _rowTopForIndex(row);
      final rowBottom = rowTop + _rowHeight;
      // Inclusive vertical overlap so a bottom-up or zero-width box still
      // considers the row it starts on or first touches.
      if (rect.bottom < rowTop || rect.top > rowBottom) continue;
      entry.value.addIntersecting(startMs, endMs, candidates);
    }
    for (final i in candidates) {
      final clipRect = _getClipRect(i);
      if (clipRect == null) continue;
      if (_rectsOverlapInclusive(rect, clipRect)) {
        selected.add(i);
      }
    }
    _selectedClipIndices
      ..clear()
      ..addAll(selected);
    if (_selectedClipIndices.isEmpty) {
      _selectedClipIndex = -1;
      _clipPopupMs = null;
      _clearClipVisualStackOrder();
      _emitSelectionChanged();
      return;
    }
    _selectedClipIndex = _selectedClipIndices.reduce((a, b) => a > b ? a : b);
    _clipPopupMs = null;
    _setClipVisualStackSelection(
      _selectedClipIndices,
      primaryClipIndex: _selectedClipIndex,
    );
    _emitSelectionChanged();
  }

  void _emitSelectionChanged() {
    final selected = _activeSelectedClipIndices();
    final primary = selected.isEmpty
        ? -1
        : (selected.contains(_selectedClipIndex)
              ? _selectedClipIndex
              : selected.last);
    widget.onSelectionChanged?.call(selected, primary);
  }

  Future<void> _deleteSelectedClips() async {
    final selected = _activeSelectedClipIndices();
    if (selected.isEmpty) return;
    if (widget.onDeleteClips != null && selected.length > 1) {
      await widget.onDeleteClips!(selected);
    } else {
      final descending = List<int>.from(selected)
        ..sort((a, b) => b.compareTo(a));
      for (final index in descending) {
        await widget.onDeleteClip(index);
      }
    }
    if (!mounted) return;
    setState(_clearClipSelection);
  }

  void _copySelectedClips() {
    final selected = _activeSelectedClipIndices();
    if (selected.isEmpty) return;
    if (widget.onCopyClips != null && selected.length > 1) {
      widget.onCopyClips!(selected);
    } else {
      widget.onCopyClip(selected.first);
    }
  }

  int? _selectionAnchorClipIndex(List<int> selected) {
    final valid = selected
        .where((i) => i >= 0 && i < widget.clips.length)
        .toList(growable: false);
    if (valid.isEmpty) return null;
    final ordered = List<int>.from(valid)
      ..sort((a, b) {
        final startCompare = widget
            .getStartMs(widget.clips[a])
            .compareTo(widget.getStartMs(widget.clips[b]));
        if (startCompare != 0) return startCompare;
        final rowCompare = widget.clips[a].rowIndex.compareTo(
          widget.clips[b].rowIndex,
        );
        if (rowCompare != 0) return rowCompare;
        return a.compareTo(b);
      });
    return ordered.first;
  }

  double? _selectionPasteStartMs(List<int> selected) {
    if (selected.isEmpty) return null;
    double? maxEndMs;
    for (final index in selected) {
      if (index < 0 || index >= widget.clips.length) continue;
      final clip = widget.clips[index];
      final endMs =
          widget.getStartMs(clip) + widget.getTimelineDurationMs(clip);
      maxEndMs = maxEndMs == null ? endMs : math.max(maxEndMs, endMs);
    }
    if (maxEndMs == null) return null;
    return _magnetEnabled ? _quantizeMsCeil(maxEndMs) : maxEndMs;
  }

  void _pasteCopiedClipsAfterSelection() {
    if (!widget.hasCopiedClip) return;
    final selected = _activeSelectedClipIndices();
    final anchorIndex = _selectionAnchorClipIndex(selected);
    final pasteStartMs = _selectionPasteStartMs(selected);
    if (anchorIndex == null || pasteStartMs == null) return;
    final row = widget.clips[anchorIndex].rowIndex;
    if (!_canPasteCopiedClipAtRow(row)) return;
    unawaited(widget.onPasteClipAt(row, pasteStartMs));
  }

  bool _canPasteCopiedClipAtRow(int row) {
    if (!widget.hasCopiedClip) return false;
    return widget.canPasteClipAtRow?.call(row) ?? true;
  }

  double _timelinePasteStartMs(double rawMs) {
    return _magnetEnabled ? _segmentStartMsForTap(rawMs) : rawMs;
  }

  int? _rowForPlayheadPaste() {
    if (_rowCount <= 0) return null;
    final selected = _activeSelectedClipIndices();
    if (selected.isNotEmpty) {
      final anchorIndex = _selectionAnchorClipIndex(selected);
      if (anchorIndex != null && anchorIndex < widget.clips.length) {
        final row = widget.clips[anchorIndex].rowIndex;
        if (row >= 0 && row < _rowCount) return row;
      }
    }
    if (_selectedRowIndex >= 0 && _selectedRowIndex < _rowCount) {
      return _selectedRowIndex;
    }
    return 0;
  }

  _TimelinePasteTarget? _timelineShortcutPasteTarget() {
    if (!_hasPasteClipboard) return null;
    if (_pasteRow != null &&
        _pasteMs != null &&
        _pasteRow! >= 0 &&
        _pasteRow! < _rowCount &&
        (_canPasteCopiedClipAtRow(_pasteRow!) ||
            _canPasteAutomationClipAt(_pasteRow!))) {
      return _TimelinePasteTarget(row: _pasteRow!, startMs: _pasteMs!);
    }

    final row = _rowForPlayheadPaste();
    if (row == null ||
        (!_canPasteCopiedClipAtRow(row) && !_canPasteAutomationClipAt(row))) {
      return null;
    }
    return _TimelinePasteTarget(
      row: row,
      startMs: _timelinePasteStartMs(_currentPlayheadMs),
    );
  }

  bool _pasteClipboardAt(int row, double startMs) {
    if (_automationClipClipboard != null && _canPasteAutomationClipAt(row)) {
      _pasteAutomationClipAt(row, startMs);
      return true;
    }
    if (!_canPasteCopiedClipAtRow(row)) return false;
    unawaited(widget.onPasteClipAt(row, startMs));
    return true;
  }

  bool _pasteClipboardFromTimelineShortcut() {
    final target = _timelineShortcutPasteTarget();
    if (target == null) return false;
    final pasted = _pasteClipboardAt(target.row, target.startMs);
    if (pasted) {
      _clearPastePopup();
    }
    return pasted;
  }

  String _stepDuplicateSelectionKey(List<int> selected) {
    return selected.join(',');
  }

  double? _selectionPasteStepMs(List<int> selected) {
    double? minStartMs;
    double? maxEndMs;
    for (final index in selected) {
      if (index < 0 || index >= widget.clips.length) continue;
      final clip = widget.clips[index];
      final startMs = widget.getStartMs(clip);
      final endMs = startMs + widget.getTimelineDurationMs(clip);
      minStartMs = minStartMs == null ? startMs : math.min(minStartMs, startMs);
      maxEndMs = maxEndMs == null ? endMs : math.max(maxEndMs, endMs);
    }
    if (minStartMs == null || maxEndMs == null) return null;
    final span = maxEndMs - minStartMs;
    if (!span.isFinite || span <= 0.1) return null;
    return span;
  }

  void _resetStepDuplicateShortcutRepeat() {
    _stepDuplicateShortcutSelectionKey = null;
    _stepDuplicateShortcutNextPasteMs = null;
  }

  bool _matchesTimelineShortcut(
    KeyEvent event,
    DesktopShortcutBinding? binding,
    LogicalKeyboardKey fallbackKey,
  ) {
    if (binding == null) {
      final keyboard = HardwareKeyboard.instance;
      return event.logicalKey == fallbackKey &&
          (keyboard.isMetaPressed || keyboard.isControlPressed);
    }
    final key = binding.logicalKey;
    if (key == null || event.logicalKey != key) return false;
    final keyboard = HardwareKeyboard.instance;
    if (binding.shift != keyboard.isShiftPressed) return false;
    if (binding.alt != keyboard.isAltPressed) return false;
    if (Platform.isMacOS) {
      if (binding.meta != keyboard.isMetaPressed) return false;
      if (binding.control != keyboard.isControlPressed) return false;
    } else {
      final wantsPrimary = binding.meta || binding.control;
      final primaryPressed = keyboard.isControlPressed;
      if (wantsPrimary != primaryPressed) return false;
      if (!wantsPrimary && keyboard.isMetaPressed) return false;
    }
    return true;
  }

  bool _isStepDuplicateShortcutKey(LogicalKeyboardKey key) {
    final bindingKey = widget.stepDuplicateClipsShortcutBinding?.logicalKey;
    return key == LogicalKeyboardKey.keyB ||
        (bindingKey != null && key == bindingKey);
  }

  bool _stepDuplicateSelectedClipsFromShortcut({required bool isRepeat}) {
    final duplicate = widget.onStepDuplicateClips;
    if (duplicate == null) return false;
    final selected = _activeSelectedClipIndices();
    if (selected.isEmpty) return false;
    final selectionKey = _stepDuplicateSelectionKey(selected);
    final repeatPasteStartMs =
        isRepeat && _stepDuplicateShortcutSelectionKey == selectionKey
        ? _stepDuplicateShortcutNextPasteMs
        : null;
    final pasteStartMs = repeatPasteStartMs ?? _selectionPasteStartMs(selected);
    if (pasteStartMs == null) return false;
    final stepMs = _selectionPasteStepMs(selected);
    if (stepMs != null) {
      final nextPasteStartMs = pasteStartMs + stepMs;
      _stepDuplicateShortcutSelectionKey = selectionKey;
      _stepDuplicateShortcutNextPasteMs = _magnetEnabled
          ? _quantizeMsCeil(nextPasteStartMs)
          : nextPasteStartMs;
    } else {
      _resetStepDuplicateShortcutRepeat();
    }
    unawaited(duplicate(selected, pasteStartMs));
    return true;
  }

  void _setPastePopupTarget(int row, double rawMs) {
    final quantizedStartMs = _segmentStartMsForTap(rawMs);
    final quantizedEndMs = quantizedStartMs + _quantizeIntervalMs();
    _clearInstrumentLaneRegionPopupState();
    _pasteRow = row;
    _pasteMs = _magnetEnabled ? quantizedStartMs : rawMs;
    _showPastePopup = true;
    if (_magnetEnabled) {
      _highlightedSegmentRow = row;
      _highlightedSegmentStartMs = quantizedStartMs;
      _highlightedSegmentEndMs = quantizedEndMs;
    } else {
      _highlightedSegmentRow = null;
      _highlightedSegmentStartMs = null;
      _highlightedSegmentEndMs = null;
    }
  }

  void _resetPaintStrokeState() {
    _paintStrokeActive = false;
    _paintStrokeRow = null;
    _paintLastFingerMs = null;
    _paintLastPasteStartMs = null;
    _paintLastPasteEndMs = null;
    _paintClipDurationEstimateMs = null;
    _pendingPaintPastes.clear();
    _paintStrokeKeys.clear();
  }

  void _showPaintClipboardHint() {
    final now = DateTime.now();
    final last = _lastPaintClipboardHintAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastPaintClipboardHintAt = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(L10n.translate(context, 'No copied clip to paint')),
          duration: Duration(milliseconds: 1200),
        ),
      );
  }

  double _paintSnapStart(double rawMs) {
    return _magnetEnabled ? _segmentStartMsForTap(rawMs) : rawMs;
  }

  double _quantizeMsCeil(double rawMs) {
    if (!_magnetEnabled) return rawMs;
    final interval = _quantizeIntervalMs();
    if (interval <= 0) return rawMs;
    return (rawMs / interval).ceil() * interval;
  }

  double _paintEstimatedClipDurationMs() {
    final estimated = _paintClipDurationEstimateMs;
    if (estimated != null && estimated.isFinite && estimated > 0.1) {
      return estimated;
    }
    if (_selectedClipIndex >= 0 && _selectedClipIndex < widget.clips.length) {
      final selectedDuration = widget.getTimelineDurationMs(
        widget.clips[_selectedClipIndex],
      );
      if (selectedDuration.isFinite && selectedDuration > 0.1) {
        return selectedDuration;
      }
    }
    if (_magnetEnabled) {
      final interval = _quantizeIntervalMs();
      if (interval.isFinite && interval > 0.1) return interval;
    }
    return 900.0;
  }

  double _nextPaintStartForRow(int row, double desiredStartMs) {
    double next = desiredStartMs;
    for (int i = 0; i < widget.clips.length + 8; i++) {
      if (next < 0) next = 0;
      final hitIndex = _clipIndexAtRowAndMs(row, next);
      if (hitIndex == null) {
        return _magnetEnabled ? _quantizeMsCeil(next) : next;
      }
      final clip = widget.clips[hitIndex];
      final clipEndMs =
          widget.getStartMs(clip) + widget.getTimelineDurationMs(clip);
      next = _magnetEnabled ? _quantizeMsCeil(clipEndMs) : clipEndMs;
    }
    return _magnetEnabled ? _quantizeMsCeil(next) : next;
  }

  bool _paintPasteAt(int row, double desiredStartMs) {
    if (!_canPasteCopiedClipAtRow(row)) return false;
    if (_pendingPaintPastes.isNotEmpty) return false;
    final startMs = _nextPaintStartForRow(row, desiredStartMs);
    final key = '$row:${startMs.round()}';
    if (_paintStrokeKeys.contains(key)) return false;

    final duration = _paintEstimatedClipDurationMs();
    _paintStrokeKeys.add(key);
    _paintGesturePlacedClip = true;
    _pendingPaintPastes.add(_PendingPaintPaste(row: row, startMs: startMs));
    unawaited(
      widget.onPasteClipAt(row, startMs).then((inserted) {
        if (!mounted || inserted) return;
        _pendingPaintPastes.removeWhere(
          (pending) =>
              pending.row == row && (pending.startMs - startMs).abs() <= 1.0,
        );
        _paintStrokeKeys.remove(key);
        if (_paintLastPasteStartMs != null &&
            (_paintLastPasteStartMs! - startMs).abs() <= 1.0) {
          _paintLastPasteStartMs = null;
          _paintLastPasteEndMs = null;
        }
      }),
    );
    _paintLastPasteStartMs = startMs;
    _paintLastPasteEndMs = null;
    _paintClipDurationEstimateMs = duration;
    return true;
  }

  void _startPaintStroke(Offset localPos) {
    if (!widget.hasCopiedClip) return;
    final row = _rowForLocalY(localPos.dy);
    if (row == null) return;
    final rawMs = (_scrollOffsetMs + localPos.dx / _pixelsPerMs)
        .clamp(0.0, double.infinity)
        .toDouble();
    final firstStart = _paintSnapStart(rawMs);

    _paintStrokeActive = true;
    _paintStrokeRow = row;
    _paintLastFingerMs = rawMs;
    _paintPasteAt(row, firstStart);
  }

  void _continuePaintStroke(Offset localPos) {
    if (!_paintStrokeActive || !widget.hasCopiedClip) return;
    final row = _rowForLocalY(localPos.dy);
    if (row == null || row != _paintStrokeRow) return;

    final rawMs = (_scrollOffsetMs + localPos.dx / _pixelsPerMs)
        .clamp(0.0, double.infinity)
        .toDouble();
    final lastFinger = _paintLastFingerMs;
    _paintLastFingerMs = rawMs;
    if (lastFinger != null && rawMs <= lastFinger) return;

    bool resolvedLastPasteFromTimeline = false;
    final lastPasteStart = _paintLastPasteStartMs;
    final paintRow = _paintStrokeRow;
    if (lastPasteStart != null && paintRow != null) {
      _ensureClipSpatialIndex();
      final candidates =
          _clipSpatialIndexByRow[paintRow]
              ?.indicesAt(lastPasteStart)
              .reversed ??
          const <int>[];
      for (final i in candidates) {
        final clip = widget.clips[i];
        final startMs = widget.getStartMs(clip);
        if ((startMs - lastPasteStart).abs() > 1.0) continue;
        final duration = widget.getTimelineDurationMs(clip);
        if (!duration.isFinite || duration <= 0.1) continue;
        _paintClipDurationEstimateMs = duration;
        _paintLastPasteEndMs = startMs + duration;
        resolvedLastPasteFromTimeline = true;
        break;
      }
    }

    if (_pendingPaintPastes.isNotEmpty && !resolvedLastPasteFromTimeline) {
      return;
    }

    final lastEnd = _paintLastPasteEndMs;
    if (lastEnd == null) return;
    final triggerStart = _magnetEnabled ? _quantizeMsCeil(lastEnd) : lastEnd;
    if (rawMs < triggerStart) return;

    var desired = triggerStart;
    while (rawMs >= desired) {
      final didPaste = _paintPasteAt(row, desired);
      if (!didPaste) break;
      final nextEnd = _paintLastPasteEndMs;
      if (nextEnd == null) break;
      desired = _magnetEnabled ? _quantizeMsCeil(nextEnd) : nextEnd;
    }
  }

  void _tryPaintAt(Offset localPos) {
    if (!widget.hasCopiedClip) return;
    final row = _rowForLocalY(localPos.dy);
    if (row == null) return;
    final rawMs = (_scrollOffsetMs + localPos.dx / _pixelsPerMs)
        .clamp(0.0, double.infinity)
        .toDouble();
    final paintMs = _paintSnapStart(rawMs);
    _paintPasteAt(row, paintMs);
  }

  void _cancelMagnetHoldTimer() {
    _magnetHoldTimer?.cancel();
    _magnetHoldTimer = null;
  }

  void _onMagnetTapDown(TapDownDetails details) {
    _magnetMenuShownFromHold = false;
    _cancelMagnetHoldTimer();
    _magnetHoldTimer = Timer(_magnetHoldDelay, () {
      _magnetHoldTimer = null;
      if (!mounted) return;
      _magnetMenuShownFromHold = true;
      AppHaptics.impact(AppHapticImpact.light);
      _showQuantizeMenu();
    });
  }

  void _onMagnetTapUp(TapUpDetails details) {
    _cancelMagnetHoldTimer();
  }

  void _onMagnetTapCancel() {
    _cancelMagnetHoldTimer();
  }

  double _volumeToPyHelper(double v, int row) {
    final expandedOffset =
        _rowTopForIndex(row) +
        _rowHeight +
        _automationTimelineLaneHeightForRow(row);
    final usableHeight = _expandedRowHeight - 24;
    return expandedOffset + 12 + (1 - v) * usableHeight;
  }

  final ScrollController _verticalScrollController = ScrollController();
  double _verticalScrollOffset = 0.0;

  void _syncVerticalScrollOffsetFromController({bool clampToExtent = false}) {
    if (!_verticalScrollController.hasClients) return;
    var nextOffset = _verticalScrollController.offset;
    if (clampToExtent) {
      final maxScroll = _verticalScrollController.position.maxScrollExtent;
      nextOffset = nextOffset.clamp(0.0, math.max(0.0, maxScroll)).toDouble();
      if ((nextOffset - _verticalScrollController.offset).abs() > 0.01) {
        _verticalScrollController.jumpTo(nextOffset);
      }
    }
    _verticalScrollOffset = nextOffset;
  }

  void _syncVerticalScrollOffsetAfterGeometryChange() {
    _syncVerticalScrollOffsetFromController(clampToExtent: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_verticalScrollController.hasClients) return;
      final before = _verticalScrollOffset;
      _syncVerticalScrollOffsetFromController(clampToExtent: true);
      if ((before - _verticalScrollOffset).abs() > 0.01) {
        setState(() {});
      }
    });
  }

  double get _maxDurationMs => widget.maxDuration.inMilliseconds.toDouble();
  int get _rowCount => widget.rows.length;
  double get _currentPlayheadMs =>
      widget.transportClockListenable.value.inMilliseconds.toDouble();

  @override
  void initState() {
    super.initState();
    _timelineFocusNode = FocusNode(debugLabel: 'Audio timeline');
    _syncLoopStateFromWidget();
    widget.controller?._bind(
      ensureRowExpanded: ensureRowExpanded,
      showMasterAutomationLane: showMasterAutomationLane,
      closeMasterAutomationLane: closeMasterAutomationLane,
      collapseExpandedRows: collapseExpandedRows,
      copySelectedClips: _copySelectedClips,
      pasteCopiedClipsAfterSelection: _pasteCopiedClipsAfterSelection,
      toggleMagnet: _toggleMagnetFromRuler,
      showToolMenu: _showToolMenu,
      showQuantizeMenu: _showQuantizeMenu,
      publishTopControlsState: _publishTopControlsState,
      beginHorizontalScrollbarDrag: _beginHorizontalScrollbarDrag,
      dragHorizontalScrollbarBy: _dragHorizontalScrollbarByDelta,
      endHorizontalScrollbarDrag: _endHorizontalScrollbarDrag,
      jumpHorizontalScrollbarTo: _jumpHorizontalScrollbarToLocalX,
      updateExternalSampleDropPreview:
          _updateExternalSampleDropPreviewForOsDrag,
      clearExternalSampleDropPreview: _clearExternalSampleDropPreview,
      placementForExternalSampleDrop: _sampleDropPlacementForGlobalOffset,
    );
    _syncRowUiState();
    _verticalScrollController.addListener(() {
      setState(() {
        _syncVerticalScrollOffsetFromController();
        if (_showInstrumentLaneRegionPopup) {
          _clearInstrumentLaneRegionPopupState();
          _highlightedSegmentRow = null;
          _highlightedSegmentStartMs = null;
          _highlightedSegmentEndMs = null;
        }
      });
    });
    widget.registerRowFxRefresher?.call(_refreshRowFx);
    widget.registerRowFxPlaybackRefresher?.call(_refreshRowFxPlayback);
    _syncSelectionFromWidgetConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifySnapSettingsChanged();
      _emitSelectionChanged();
    });
  }

  @override
  void didUpdateWidget(covariant AudioCanvasTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loopEnabled != widget.loopEnabled ||
        oldWidget.loopStartMs != widget.loopStartMs ||
        oldWidget.loopEndMs != widget.loopEndMs) {
      _syncLoopStateFromWidget();
    }
    if (oldWidget.beatsPerBar != widget.beatsPerBar ||
        oldWidget.beatUnit != widget.beatUnit) {
      _syncQuantizeToTimeSignature();
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._unbind(
        ensureRowExpanded: ensureRowExpanded,
        showMasterAutomationLane: showMasterAutomationLane,
        closeMasterAutomationLane: closeMasterAutomationLane,
        collapseExpandedRows: collapseExpandedRows,
        copySelectedClips: _copySelectedClips,
        pasteCopiedClipsAfterSelection: _pasteCopiedClipsAfterSelection,
        toggleMagnet: _toggleMagnetFromRuler,
        showToolMenu: _showToolMenu,
        showQuantizeMenu: _showQuantizeMenu,
        publishTopControlsState: _publishTopControlsState,
        beginHorizontalScrollbarDrag: _beginHorizontalScrollbarDrag,
        dragHorizontalScrollbarBy: _dragHorizontalScrollbarByDelta,
        endHorizontalScrollbarDrag: _endHorizontalScrollbarDrag,
        jumpHorizontalScrollbarTo: _jumpHorizontalScrollbarToLocalX,
        updateExternalSampleDropPreview:
            _updateExternalSampleDropPreviewForOsDrag,
        clearExternalSampleDropPreview: _clearExternalSampleDropPreview,
        placementForExternalSampleDrop: _sampleDropPlacementForGlobalOffset,
      );
      widget.controller?._bind(
        ensureRowExpanded: ensureRowExpanded,
        showMasterAutomationLane: showMasterAutomationLane,
        closeMasterAutomationLane: closeMasterAutomationLane,
        collapseExpandedRows: collapseExpandedRows,
        copySelectedClips: _copySelectedClips,
        pasteCopiedClipsAfterSelection: _pasteCopiedClipsAfterSelection,
        toggleMagnet: _toggleMagnetFromRuler,
        showToolMenu: _showToolMenu,
        showQuantizeMenu: _showQuantizeMenu,
        publishTopControlsState: _publishTopControlsState,
        beginHorizontalScrollbarDrag: _beginHorizontalScrollbarDrag,
        dragHorizontalScrollbarBy: _dragHorizontalScrollbarByDelta,
        endHorizontalScrollbarDrag: _endHorizontalScrollbarDrag,
        jumpHorizontalScrollbarTo: _jumpHorizontalScrollbarToLocalX,
        updateExternalSampleDropPreview:
            _updateExternalSampleDropPreviewForOsDrag,
        clearExternalSampleDropPreview: _clearExternalSampleDropPreview,
        placementForExternalSampleDrop: _sampleDropPlacementForGlobalOffset,
      );
    }
    if (oldWidget.clips.length != widget.clips.length) {
      // Clip indices are transient. A deletion or insertion can invalidate an
      // active drag/trim before its next pointer update is delivered.
      _cancelClipGestureAfterTopologyChange();
      _syncSelectionAfterClipTopologyChange();
      if (_pendingPaintPastes.isNotEmpty) {
        _ensureClipSpatialIndex();
        final remainingPending = <_PendingPaintPaste>[];
        for (final pending in _pendingPaintPastes) {
          var resolved = false;
          final candidates =
              _clipSpatialIndexByRow[pending.row]
                  ?.indicesAt(pending.startMs)
                  .reversed ??
              const <int>[];
          for (final i in candidates) {
            final clip = widget.clips[i];
            final startMs = widget.getStartMs(clip);
            if ((startMs - pending.startMs).abs() > 1.0) continue;
            final duration = widget.getTimelineDurationMs(clip);
            if (!duration.isFinite || duration <= 0.1) continue;
            _paintClipDurationEstimateMs = duration;
            if (_paintLastPasteStartMs != null &&
                (_paintLastPasteStartMs! - pending.startMs).abs() <= 1.0) {
              _paintLastPasteEndMs = pending.startMs + duration;
            }
            resolved = true;
            break;
          }
          if (!resolved) {
            remainingPending.add(pending);
          }
        }
        _pendingPaintPastes
          ..clear()
          ..addAll(remainingPending);
      }
    }
    if (oldWidget.selectedClipIndex != widget.selectedClipIndex ||
        !listEquals(
          oldWidget.selectedClipIndices,
          widget.selectedClipIndices,
        )) {
      _syncSelectionFromWidgetConfig();
    }
    final bool rowTopologyChanged =
        oldWidget.rows.length != widget.rows.length ||
        List.generate(
          math.min(oldWidget.rows.length, widget.rows.length),
          (i) => oldWidget.rows[i].rowId != widget.rows[i].rowId,
        ).any((v) => v);

    if (rowTopologyChanged) {
      _reconcileRowUiStateByRowId(oldWidget.rows);
    } else if (oldWidget.rows.length != widget.rows.length) {
      _syncRowUiState();
    }
    if (oldWidget.allowMultipleExpandedRows !=
        widget.allowMultipleExpandedRows) {
      _enforceSingleExpandedRowIfNeeded(notify: true);
    } else {
      _enforceSingleExpandedRowIfNeeded();
    }
    if (_automationEditorRow != null &&
        (_automationEditorRow! < 0 || _automationEditorRow! >= _rowCount)) {
      _automationEditorRow = null;
      _automationEditorTargetId = null;
    }
    final liveRowIds = widget.rows.map((row) => row.rowId).toSet();
    _headerPeakHoldDbByRowId.removeWhere(
      (rowId, _) => !liveRowIds.contains(rowId),
    );
    _headerPeakHoldLastUpdateByRowId.removeWhere(
      (rowId, _) => !liveRowIds.contains(rowId),
    );
    _headerPeakHoldFreezeUntilByRowId.removeWhere(
      (rowId, _) => !liveRowIds.contains(rowId),
    );
    _rowEffectParameterRevealers.removeWhere(
      (rowId, _) => !liveRowIds.contains(rowId),
    );
    _selectedAutomationClipByLane.removeWhere((laneKey, clipId) {
      final parts = laneKey.split('|');
      if (parts.length < 2) return true;
      final row = int.tryParse(parts.first);
      if (row == null || row < 0 || row >= _rowCount) return true;
      final targetId = parts.sublist(1).join('|');
      if (targetId.isEmpty) return true;
      final clips = widget.getAutomationClipsForTarget(row, targetId);
      return !clips.any((clip) => clip.id == clipId);
    });
    if (widget.onExternalSampleDrop == null &&
        (_externalSampleDropRow != null ||
            _externalSampleDropStartMs != null ||
            _externalSampleDropEndMs != null)) {
      _clearExternalSampleDropPreview();
    }
    if (!widget.externalSampleDragActive &&
        (_externalSampleDropRow != null ||
            _externalSampleDropStartMs != null ||
            _externalSampleDropEndMs != null ||
            _externalSampleDragInsideTimeline)) {
      _clearExternalSampleDropPreview();
    }
  }

  @override
  void dispose() {
    _cancelHeaderHoldTimer();
    _cancelDeadZoneHoldTimer();
    _cancelMagnetHoldTimer();
    _stopTimelineTrackpadHorizontalInertia();
    widget.controller?._unbind(
      ensureRowExpanded: ensureRowExpanded,
      showMasterAutomationLane: showMasterAutomationLane,
      closeMasterAutomationLane: closeMasterAutomationLane,
      collapseExpandedRows: collapseExpandedRows,
      copySelectedClips: _copySelectedClips,
      pasteCopiedClipsAfterSelection: _pasteCopiedClipsAfterSelection,
      toggleMagnet: _toggleMagnetFromRuler,
      showToolMenu: _showToolMenu,
      showQuantizeMenu: _showQuantizeMenu,
      publishTopControlsState: _publishTopControlsState,
      beginHorizontalScrollbarDrag: _beginHorizontalScrollbarDrag,
      dragHorizontalScrollbarBy: _dragHorizontalScrollbarByDelta,
      endHorizontalScrollbarDrag: _endHorizontalScrollbarDrag,
      jumpHorizontalScrollbarTo: _jumpHorizontalScrollbarToLocalX,
      updateExternalSampleDropPreview:
          _updateExternalSampleDropPreviewForOsDrag,
      clearExternalSampleDropPreview: _clearExternalSampleDropPreview,
      placementForExternalSampleDrop: _sampleDropPlacementForGlobalOffset,
    );
    widget.controller?._setHorizontalScrollbarState(
      TimelineHorizontalScrollbarState.hidden,
    );
    _verticalScrollController.dispose();
    _timelineFocusNode.dispose();
    super.dispose();
  }

  bool _isHoldEligibleInHeader(Offset localPos) {
    // Keep M/S interactions fully isolated from row-header tap/hold logic.
    if (_usesTabletDawLayout) {
      if (localPos.dx >= _headerWidth - 54.0) return false;
      final gainStripTop = math.max(0.0, _rowHeight - 38.0);
      final compactHeader = _rowHeight < 70.0;
      final gainSliderLeft =
          _kTabletHeaderLedgeX +
          (compactHeader ? 8.0 + 3.0 + 30.0 + 5.0 : 9.0 + 3.0);
      if (localPos.dy >= gainStripTop && localPos.dx >= gainSliderLeft) {
        return false;
      }
      return true;
    }
    const double msPillLeft = 44.0;
    final bool inMuteSoloPill = localPos.dx >= msPillLeft;
    return !inMuteSoloPill;
  }

  void _syncLoopStateFromWidget() {
    _loopEnabled = widget.loopEnabled;
    if (widget.loopEnabled) {
      _loopStartMs = widget.loopStartMs;
      _loopEndMs = widget.loopEndMs;
    } else {
      _loopStartMs = null;
      _loopEndMs = null;
    }
  }

  void _cancelHeaderHoldTimer() {
    _headerHoldTimer?.cancel();
    _headerHoldTimer = null;
  }

  void _resetHeaderPointerState() {
    _headerPointer = null;
    _headerRow = null;
    _headerDownPos = null;
    _headerEligible = false;
    _headerMoved = false;
    _headerMenuOpened = false;
  }

  void _startRowMenuHold(int row, Offset localPos, int pointer) {
    _cancelHeaderHoldTimer();
    _headerPointer = pointer;
    _headerRow = row;
    _headerDownPos = localPos;
    _headerEligible = _isHoldEligibleInHeader(localPos);
    _headerMoved = false;
    _headerMenuOpened = false;
    if (!_headerEligible) return;

    _headerHoldTimer = Timer(_rowMenuHoldDelay, () {
      if (!mounted) return;
      if (_headerPointer != pointer || _headerRow != row) return;
      if (row < 0 || row >= _rowCount) return;
      _headerMenuOpened = true;
      unawaited(_showRowMenu(row));
    });
  }

  void _markGroupFoldHeaderPointer(int row, PointerDownEvent event) {
    _groupFoldHeaderPointerRows[event.pointer] = row;
    if (_headerPointer == event.pointer) {
      _cancelHeaderHoldTimer();
      _resetHeaderPointerState();
    }
  }

  bool _isGroupFoldHeaderHit(int row, Offset localPosition) {
    final rowGroup = _groupForRow(row);
    final visibilityEntry = _visibilityEntryForSourceRow(row);
    final isGroupLeadRow =
        rowGroup != null && visibilityEntry?.isGroupFirstRow == true;
    if (!isGroupLeadRow) return false;

    if (_usesTabletDawLayout) {
      final compactHeader = _rowHeight < 70.0;
      final headerVerticalPadding = compactHeader ? 5.0 : 8.0;
      final headerHorizontalPadding = compactHeader ? 8.0 : 9.0;
      final folderSize = compactHeader ? 31.0 : 34.0;
      final folderLeft = _kTabletHeaderLedgeX + headerHorizontalPadding + 2.0;
      final folderTop = headerVerticalPadding;
      final foldRect = Rect.fromLTWH(
        folderLeft - 4.0,
        folderTop,
        folderSize + 12.0,
        math.max(36.0, _rowHeight - (headerVerticalPadding * 2.0)),
      );
      return foldRect.contains(localPosition);
    }

    const iconStripWidth = 44.0;
    final foldPillTop = math.max(0.0, _rowHeight * 0.58);
    return localPosition.dx >= 0.0 &&
        localPosition.dx <= iconStripWidth &&
        localPosition.dy >= foldPillTop &&
        localPosition.dy <= _rowHeight;
  }

  void _toggleGroupChildrenFromHeaderRow(int row) {
    final rowGroup = _groupForRow(row);
    final visibilityEntry = _visibilityEntryForSourceRow(row);
    final isGroupLeadRow =
        rowGroup != null && visibilityEntry?.isGroupFirstRow == true;
    if (!isGroupLeadRow || widget.onToggleRowGroupCollapsed == null) return;
    unawaited(widget.onToggleRowGroupCollapsed!(rowGroup.id));
  }

  void _handleHeaderPointerDown(int row, PointerDownEvent event) {
    _requestTimelineFocus();
    if (_groupFoldHeaderPointerRows.containsKey(event.pointer) ||
        _isGroupFoldHeaderHit(row, event.localPosition)) {
      _groupFoldHeaderPointerRows[event.pointer] = row;
      _cancelHeaderHoldTimer();
      _resetHeaderPointerState();
      return;
    }
    if (widget.rowGroupingSelectionMode) {
      _cancelHeaderHoldTimer();
      _resetHeaderPointerState();
      _headerPointer = event.pointer;
      _headerRow = row;
      _headerDownPos = event.localPosition;
      _headerEligible = true;
      _headerMoved = false;
      _headerMenuOpened = false;
      return;
    }
    if (PlatformCapabilities.current.isDesktop &&
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kSecondaryMouseButton) {
      _cancelHeaderHoldTimer();
      _resetHeaderPointerState();
      _showRowMenu(row);
      return;
    }
    _startRowMenuHold(row, event.localPosition, event.pointer);
  }

  void _onHeaderPointerMove(PointerMoveEvent e) {
    if (_headerPointer != e.pointer) return;
    if (_headerMoved) return;
    if (_headerDownPos == null) return;
    if (_headerRow == null) return;

    final movedBy = (e.localPosition - _headerDownPos!).distance;
    if (movedBy <= _headerTapMoveTolerance) return;

    _headerMoved = true;
    _cancelHeaderHoldTimer();
  }

  void _onHeaderPointerUp(PointerUpEvent e) {
    final groupFoldRow = _groupFoldHeaderPointerRows.remove(e.pointer);
    if (groupFoldRow != null) {
      _cancelHeaderHoldTimer();
      _resetHeaderPointerState();
      _toggleGroupChildrenFromHeaderRow(groupFoldRow);
      return;
    }
    if (_headerPointer != e.pointer) return;
    final row = _headerRow;
    if (row != null && _isGroupFoldHeaderHit(row, e.localPosition)) {
      _cancelHeaderHoldTimer();
      _resetHeaderPointerState();
      _toggleGroupChildrenFromHeaderRow(row);
      return;
    }
    final bool shouldToggleRow =
        row != null && _headerEligible && !_headerMoved && !_headerMenuOpened;

    _cancelHeaderHoldTimer();
    _resetHeaderPointerState();

    if (shouldToggleRow) {
      final int tappedRow = row;
      if (widget.rowGroupingSelectionMode) {
        widget.onToggleGroupingRowSelection?.call(tappedRow);
        return;
      }
      _handleHeaderTapSelectionAndExpand(tappedRow);
    }
  }

  void _onHeaderPointerCancel(PointerCancelEvent e) {
    if (_groupFoldHeaderPointerRows.remove(e.pointer) != null) {
      _cancelHeaderHoldTimer();
      _resetHeaderPointerState();
      return;
    }
    if (_headerPointer != e.pointer) return;
    _cancelHeaderHoldTimer();
    _resetHeaderPointerState();
  }

  void _cancelDeadZoneHoldTimer() {
    _deadZoneHoldTimer?.cancel();
    _deadZoneHoldTimer = null;
  }

  void _resetDeadZonePointerState() {
    _deadZonePointer = null;
    _deadZoneRow = null;
    _deadZoneDownGlobalPos = null;
    _deadZoneMoved = false;
  }

  void _startDeadZoneRowMenuHold(int row, int pointer, Offset globalPosition) {
    _cancelDeadZoneHoldTimer();
    _deadZonePointer = pointer;
    _deadZoneRow = row;
    _deadZoneDownGlobalPos = globalPosition;
    _deadZoneMoved = false;
    _deadZoneHoldTimer = Timer(_rowMenuHoldDelay, () {
      if (!mounted) return;
      if (_deadZonePointer != pointer || _deadZoneRow != row) return;
      if (row < 0 || row >= _rowCount) return;
      _suppressNextTimelineTapAfterDeadZoneHold = true;
      _showRowMenu(row);
      _cancelDeadZoneHoldTimer();
      _resetDeadZonePointerState();
    });
  }

  void _onDeadZonePointerMove(PointerMoveEvent event) {
    if (_deadZonePointer != event.pointer || _deadZoneMoved) return;
    final armedRow = _deadZoneRow;
    if (armedRow == null ||
        _deadZoneRowAtLocalPosition(event.localPosition) != armedRow) {
      _deadZoneMoved = true;
      _cancelDeadZoneHoldTimer();
      return;
    }
    final down = _deadZoneDownGlobalPos;
    if (down == null) return;
    final movedBy = (event.position - down).distance;
    if (movedBy <= _deadZoneHoldMoveTolerance) return;
    _deadZoneMoved = true;
    _cancelDeadZoneHoldTimer();
  }

  void _onDeadZonePointerUp(PointerUpEvent event) {
    if (_deadZonePointer != event.pointer) return;
    _cancelDeadZoneHoldTimer();
    _resetDeadZonePointerState();
  }

  void _onDeadZonePointerCancel(PointerCancelEvent event) {
    if (_deadZonePointer != event.pointer) return;
    _cancelDeadZoneHoldTimer();
    _resetDeadZonePointerState();
  }

  int? _deadZoneRowAtLocalPosition(Offset localPos) {
    if (_rowCount <= 0) return null;
    final zeroMsX = (0 - _scrollOffsetMs) * _pixelsPerMs;
    if (zeroMsX <= 12) return null;
    final viewportWidth = _getViewportWidth(context);
    final maxWidth = math.min(zeroMsX - 8, viewportWidth - 8);
    if (maxWidth <= 0) return null;
    final row = _rowForLocalY(localPos.dy);
    if (row == null || row < 0 || row >= _rowCount) return null;
    final top = _rowYPositions[row] + 8;
    const bubbleHeight = 28.0;
    final bubbleRect = Rect.fromLTWH(6.0, top, maxWidth, bubbleHeight);
    if (!bubbleRect.contains(localPos)) return null;
    return row;
  }

  void _handleHeaderTapSelectionAndExpand(int tappedRow) {
    final wasSelected = tappedRow == _selectedRowIndex;
    final oldExpanded = List<bool>.from(_rowExpanded);

    setState(() {
      if (!wasSelected) {
        if (!_allowsMultipleExpandedRows &&
            _automationEditorRow != null &&
            _automationEditorRow != tappedRow) {
          _automationEditorRow = null;
          _automationEditorTargetId = null;
        }
        _selectedRowIndex = tappedRow;
        widget.onSelectRow(tappedRow);
        if (widget.expandRowsOnTrackSelect) {
          if (_allowsMultipleExpandedRows) {
            _rowExpanded[tappedRow] = true;
          } else {
            for (int i = 0; i < _rowExpanded.length; i++) {
              _rowExpanded[i] = i == tappedRow;
            }
          }
        }
        return;
      }

      final shouldExpand = !_rowExpanded[tappedRow];
      if (!shouldExpand && _automationEditorRow == tappedRow) {
        _automationEditorRow = null;
        _automationEditorTargetId = null;
      }
      if (_allowsMultipleExpandedRows) {
        _rowExpanded[tappedRow] = shouldExpand;
      } else {
        for (int i = 0; i < _rowExpanded.length; i++) {
          _rowExpanded[i] = shouldExpand && i == tappedRow;
        }
      }
    });

    _notifyRowExpansionChanges(oldExpanded, notifyToggle: true);
  }

  void ensureRowExpanded(int row, {int tab = 0}) {
    if (row < 0 || row >= _rowCount) return;
    final normalizedTab = _normalizeExpandedTab(tab);
    final oldExpanded = List<bool>.from(_rowExpanded);
    setState(() {
      _selectedRowIndex = row;
      widget.onSelectRow(row);
      _expandRowForFocusedTarget(row);
      _expandedTab[row] = normalizedTab;
      if (normalizedTab != 2) {
        _automationEditorRow = null;
        _automationEditorTargetId = null;
        _automationTargetPickerRow = null;
      }
    });
    _notifyRowExpansionChanges(oldExpanded);
    widget.onRowTabSelected?.call(row, normalizedTab);
    widget.onTutorialRowTabSelected?.call(row, normalizedTab);
  }

  void showMasterAutomationLane(String targetId) {
    final normalizedTargetId = targetId.trim();
    if (normalizedTargetId.isEmpty || !_isMasterAutomationTargetId(targetId)) {
      return;
    }
    setState(() {
      _masterAutomationEditorTargetId = normalizedTargetId;
      _clearAutomationClipMenu();
      _automationTargetPickerRow = null;
    });
    _syncVerticalScrollOffsetAfterGeometryChange();
  }

  void closeMasterAutomationLane() {
    if (_masterAutomationEditorTargetId == null) return;
    setState(() {
      _masterAutomationEditorTargetId = null;
      if (_automationRangeSelectionRow == 0 &&
          _automationRangeSelectionTargetId != null &&
          _isMasterAutomationTargetId(_automationRangeSelectionTargetId!)) {
        _clearAutomationRangeSelectionMode();
      }
    });
    _syncVerticalScrollOffsetAfterGeometryChange();
  }

  void collapseExpandedRows() {
    if (_rowExpanded.every((expanded) => !expanded)) return;
    final oldExpanded = List<bool>.from(_rowExpanded);
    setState(() {
      for (int i = 0; i < _rowExpanded.length; i++) {
        _rowExpanded[i] = false;
      }
      _automationEditorRow = null;
      _automationEditorTargetId = null;
      _automationTargetPickerRow = null;
      _clearTimelineSelectionFeedback();
    });
    for (int i = 0; i < oldExpanded.length && i < _rowExpanded.length; i++) {
      if (oldExpanded[i] != _rowExpanded[i]) {
        widget.onRowExpansionChanged?.call(i, _rowExpanded[i]);
        widget.onTutorialRowExpansionChanged?.call(i, _rowExpanded[i]);
      }
    }
    _syncVerticalScrollOffsetAfterGeometryChange();
  }

  bool _hasTimelineEscapeDismissibleOverlay() {
    return _automationTargetPickerRow != null ||
        _automationClipMenuClipId != null ||
        _clipPopupMs != null ||
        _showPastePopup ||
        _pasteRow != null ||
        _showInstrumentLaneRegionPopup;
  }

  bool _dismissTimelineEscapeOverlay() {
    if (!_hasTimelineEscapeDismissibleOverlay()) return false;
    setState(() {
      _automationTargetPickerRow = null;
      _clearAutomationClipMenu();
      _clipPopupMs = null;
      _showPastePopup = false;
      _pasteRow = null;
      _pasteMs = null;
      _clearInstrumentLaneRegionPopupState();
      _highlightedSegmentRow = null;
      _highlightedSegmentStartMs = null;
      _highlightedSegmentEndMs = null;
    });
    return true;
  }

  bool _collapseExpandedTimelineState() {
    final hasExpandedRows = _rowExpanded.any((expanded) => expanded);
    final hasMasterAutomationLane = _masterAutomationEditorTargetId != null;
    if (!hasExpandedRows && !hasMasterAutomationLane) return false;

    final oldExpanded = List<bool>.from(_rowExpanded);
    setState(() {
      for (int i = 0; i < _rowExpanded.length; i++) {
        _rowExpanded[i] = false;
      }
      _masterAutomationEditorTargetId = null;
      if (_automationRangeSelectionTargetId != null &&
          _isMasterAutomationTargetId(_automationRangeSelectionTargetId!)) {
        _clearAutomationRangeSelectionMode();
      }
      _automationEditorRow = null;
      _automationEditorTargetId = null;
      _automationTargetPickerRow = null;
      _clearTimelineSelectionFeedback();
    });
    for (int i = 0; i < oldExpanded.length && i < _rowExpanded.length; i++) {
      if (oldExpanded[i] != _rowExpanded[i]) {
        widget.onRowExpansionChanged?.call(i, _rowExpanded[i]);
        widget.onTutorialRowExpansionChanged?.call(i, _rowExpanded[i]);
      }
    }
    _syncVerticalScrollOffsetAfterGeometryChange();
    return true;
  }

  KeyEventResult _handleTimelineKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      if (_isStepDuplicateShortcutKey(event.logicalKey) ||
          event.logicalKey == LogicalKeyboardKey.metaLeft ||
          event.logicalKey == LogicalKeyboardKey.metaRight ||
          event.logicalKey == LogicalKeyboardKey.controlLeft ||
          event.logicalKey == LogicalKeyboardKey.controlRight) {
        _resetStepDuplicateShortcutRepeat();
      }
      return KeyEventResult.ignored;
    }
    final isRepeat = event is KeyRepeatEvent;
    if (event is! KeyDownEvent && !isRepeat) {
      return KeyEventResult.ignored;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final primaryShortcutPressed =
        keyboard.isMetaPressed || keyboard.isControlPressed;
    if (!isRepeat &&
        _matchesTimelineShortcut(
          event,
          widget.copyClipsShortcutBinding,
          LogicalKeyboardKey.keyC,
        )) {
      if (_activeSelectedClipIndices().isEmpty) return KeyEventResult.ignored;
      _copySelectedClips();
      return KeyEventResult.handled;
    }
    if (!isRepeat &&
        _matchesTimelineShortcut(
          event,
          widget.pasteClipsShortcutBinding,
          LogicalKeyboardKey.keyV,
        )) {
      return _pasteClipboardFromTimelineShortcut()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (_matchesTimelineShortcut(
      event,
      widget.stepDuplicateClipsShortcutBinding,
      LogicalKeyboardKey.keyB,
    )) {
      return _stepDuplicateSelectedClipsFromShortcut(isRepeat: isRepeat)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (!isRepeat &&
        !primaryShortcutPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed &&
        (event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace)) {
      if (_activeSelectedClipIndices().isNotEmpty) {
        unawaited(_deleteSelectedClips());
        return KeyEventResult.handled;
      }
      if (_selectedRowIndex >= 0 && _selectedRowIndex < _rowCount) {
        unawaited(widget.onDeleteRow(_selectedRowIndex));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (!isRepeat &&
        !primaryShortcutPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      final tool = _timelineToolForShortcutEvent(event);
      if (tool != null) {
        _selectTimelineTool(tool);
        return KeyEventResult.handled;
      }
    }
    if (isRepeat || event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_dismissTimelineEscapeOverlay()) return KeyEventResult.handled;
    if (_collapseExpandedTimelineState()) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  void _syncRowUiState() {
    while (_rowExpanded.length < _rowCount) {
      _rowExpanded.add(false);
      _expandedTab.add(_normalizeExpandedTab(0));
      _effectsPanelHeights.add(_effectsPanelMinHeight);
    }
    if (_rowExpanded.length > _rowCount) {
      _rowExpanded.removeRange(_rowCount, _rowExpanded.length);
      _expandedTab.removeRange(_rowCount, _expandedTab.length);
      _effectsPanelHeights.removeRange(_rowCount, _effectsPanelHeights.length);
    }
    if (_selectedRowIndex >= _rowCount) {
      _selectedRowIndex = _rowCount == 0 ? -1 : _rowCount - 1;
    }
    if (_automationTargetPickerRow != null &&
        (_automationTargetPickerRow! < 0 ||
            _automationTargetPickerRow! >= _rowCount)) {
      _automationTargetPickerRow = null;
    }
    _extraAutomationTimelineLanesByRow.removeWhere(
      (row, _) => row < 0 || row >= _rowCount,
    );
    _collapsedAutomationTimelineByRow.removeWhere(
      (row, _) => row < 0 || row >= _rowCount,
    );
    _automationLaneFocusByRow.removeWhere(
      (row, _) => row < 0 || row >= _rowCount,
    );
    if (_rowCount <= 0) {
      _masterAutomationEditorTargetId = null;
    }
  }

  void _reconcileRowUiStateByRowId(List<TimelineRow> oldRows) {
    final oldExpandedById = <int, bool>{};
    final oldTabById = <int, int>{};
    final oldEffectsHeightById = <int, double>{};
    final oldExtraAutomationLanesById = <int, int>{};
    final oldCollapsedAutomationById = <int, bool>{};
    final oldAutomationLaneFocusById = <int, int>{};

    for (int i = 0; i < oldRows.length; i++) {
      final id = oldRows[i].rowId;
      if (i < _rowExpanded.length) oldExpandedById[id] = _rowExpanded[i];
      if (i < _expandedTab.length) oldTabById[id] = _expandedTab[i];
      if (i < _effectsPanelHeights.length) {
        oldEffectsHeightById[id] = _effectsPanelHeights[i];
      }
      oldExtraAutomationLanesById[id] = math.max(
        0,
        _extraAutomationTimelineLanesByRow[i] ?? 0,
      );
      oldCollapsedAutomationById[id] =
          _collapsedAutomationTimelineByRow[i] == true;
      oldAutomationLaneFocusById[id] = math.max(
        0,
        _automationLaneFocusByRow[i] ?? 0,
      );
    }

    final selectedRowId =
        (_selectedRowIndex >= 0 && _selectedRowIndex < oldRows.length)
        ? oldRows[_selectedRowIndex].rowId
        : null;
    _rowExpanded
      ..clear()
      ..addAll(
        widget.rows
            .map((r) => oldExpandedById[r.rowId] ?? false)
            .toList(growable: false),
      );
    _expandedTab
      ..clear()
      ..addAll(
        widget.rows
            .map((r) => _normalizeExpandedTab(oldTabById[r.rowId] ?? 0))
            .toList(growable: false),
      );
    _effectsPanelHeights
      ..clear()
      ..addAll(
        widget.rows
            .map((r) => oldEffectsHeightById[r.rowId] ?? _effectsPanelMinHeight)
            .toList(growable: false),
      );
    _extraAutomationTimelineLanesByRow
      ..clear()
      ..addEntries(
        widget.rows
            .asMap()
            .entries
            .where((entry) {
              final rowId = entry.value.rowId;
              return (oldExtraAutomationLanesById[rowId] ?? 0) > 0;
            })
            .map((entry) {
              final rowId = entry.value.rowId;
              return MapEntry(
                entry.key,
                oldExtraAutomationLanesById[rowId] ?? 0,
              );
            }),
      );
    _collapsedAutomationTimelineByRow
      ..clear()
      ..addEntries(
        widget.rows
            .asMap()
            .entries
            .where((entry) {
              final rowId = entry.value.rowId;
              return oldCollapsedAutomationById[rowId] == true;
            })
            .map((entry) {
              final rowId = entry.value.rowId;
              return MapEntry(
                entry.key,
                oldCollapsedAutomationById[rowId] == true,
              );
            }),
      );
    _automationLaneFocusByRow
      ..clear()
      ..addEntries(
        widget.rows.asMap().entries.map((entry) {
          final rowId = entry.value.rowId;
          return MapEntry(entry.key, oldAutomationLaneFocusById[rowId] ?? 0);
        }),
      );

    _selectedRowIndex = (selectedRowId == null)
        ? (_rowCount == 0 ? -1 : 0)
        : widget.rows.indexWhere((r) => r.rowId == selectedRowId);
    if (_selectedRowIndex < 0) {
      _selectedRowIndex = _rowCount == 0 ? -1 : 0;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (int row = 0; row < _rowCount; row++) {
        if (_rowExpanded[row] && _expandedTab[row] == 1) {
          _refreshRowFx(row);
        }
      }
    });
  }

  void _refreshRowFx(int row) {
    if (row < 0 || row >= _rowCount) return;
    final rowId = widget.rows[row].rowId;
    final refresh = _rowEffectRefreshers[rowId];
    if (refresh != null) {
      refresh();
    }
  }

  void _refreshRowFxPlayback(int row) {
    if (row < 0 || row >= _rowCount) return;
    if (!_rowExpanded[row]) return;
    if (_normalizeExpandedTab(_expandedTab[row]) != 1) return;
    final rowId = widget.rows[row].rowId;
    final refresh = _rowEffectPlaybackRefreshers[rowId];
    if (refresh != null) {
      refresh();
    }
  }

  // Helper to get the viewport width (the drawable timeline area)
  double _getViewportWidth(BuildContext context) {
    return _viewportWidthForTimelineWidth(_timelineWidgetWidth(context));
  }

  double _getPlayheadPx(BuildContext context) {
    if (PlatformCapabilities.current.isDesktop) {
      return (_currentPlayheadMs - _scrollOffsetMs) * _pixelsPerMs;
    }
    if (_usesTabletDawLayout) {
      return _getTabletDeviceCenterPlayheadPx(context);
    }
    if (!PlatformCapabilities.current.isDesktop) {
      return _getMobilePlayheadPxForTimelineWidth(
        _timelineWidgetWidth(context),
      );
    }
    return (_currentPlayheadMs - _scrollOffsetMs) * _pixelsPerMs;
  }

  double _getTabletDeviceCenterPlayheadPx(BuildContext context) {
    return (MediaQuery.sizeOf(context).width / 2.0) - _headerWidth;
  }

  double _desktopLeftDeadZoneMs(BuildContext context) {
    final deadZonePx = _getMobilePlayheadPxForTimelineWidth(
      _timelineWidgetWidth(context),
    );
    return math.max(0.0, deadZonePx) / _pixelsPerMs;
  }

  double _horizontalScrollbarContentEndMs() {
    return math.max(_maxDurationMs, msFor128Bars(widget.bpm));
  }

  double _horizontalScrollbarMinScrollMs(BuildContext context) {
    return PlatformCapabilities.current.isDesktop
        ? -_desktopLeftDeadZoneMs(context)
        : -_getPlayheadPx(context) / _pixelsPerMs;
  }

  double _horizontalScrollbarMaxScrollMs({
    required BuildContext context,
    required double viewportWidth,
  }) {
    final viewportMs = viewportWidth / _pixelsPerMs;
    return _horizontalScrollbarContentEndMs() - viewportMs;
  }

  void _setScrollOffsetFromHorizontalScrollbar({
    required double viewportWidth,
    required double targetScrollMs,
  }) {
    setState(() {
      _scrollOffsetMs = targetScrollMs;
      _clampScroll();
    });
    _publishHorizontalScrollbarState(viewportWidth: viewportWidth);
    widget.onTutorialTimelineScrolled?.call();
  }

  void _beginHorizontalScrollbarDrag(double localX) {
    if (_horizontalScrollbarDragging) return;
    final viewportWidth = _getViewportWidth(context);
    final metrics = _horizontalScrollbarMetrics(viewportWidth);
    var dragMode = 'scroll';
    var anchorLocalX = localX.clamp(0.0, viewportWidth).toDouble();
    var anchorMs = _scrollOffsetMs + anchorLocalX / _pixelsPerMs;
    if (metrics != null) {
      final thumbLeft = metrics.thumbLeft;
      final thumbRight = metrics.thumbLeft + metrics.thumbWidth;
      final clampedLocalX = localX.clamp(thumbLeft, thumbRight).toDouble();
      if (localX >= thumbLeft && localX <= thumbRight) {
        final edgeHitZone = math.min(
          _kHorizontalScrollbarEdgeHitZone,
          metrics.thumbWidth / 2.0,
        );
        if (clampedLocalX - thumbLeft <= edgeHitZone) {
          dragMode = 'resize_start';
          anchorLocalX = thumbRight;
        } else if (thumbRight - clampedLocalX <= edgeHitZone) {
          dragMode = 'resize_end';
          anchorLocalX = thumbLeft;
        }
      }
      anchorMs = _scrollOffsetMs + anchorLocalX / _pixelsPerMs;
    }
    setState(() {
      _horizontalScrollbarDragging = true;
      _horizontalScrollbarDragMode = dragMode;
      _horizontalScrollbarDragAccumX = 0.0;
      _horizontalScrollbarDragStartPixelsPerMs = _pixelsPerMs;
      _horizontalScrollbarDragAnchorLocalX = anchorLocalX;
      _horizontalScrollbarDragAnchorMs = anchorMs;
    });
    _publishHorizontalScrollbarState();
  }

  void _endHorizontalScrollbarDrag() {
    if (!_horizontalScrollbarDragging) return;
    setState(() {
      _horizontalScrollbarDragging = false;
      _horizontalScrollbarDragMode = null;
      _horizontalScrollbarDragAccumX = 0.0;
    });
    _publishHorizontalScrollbarState();
  }

  void _jumpHorizontalScrollbarToLocalX(double localX) {
    _jumpHorizontalScrollbarTo(
      viewportWidth: _getViewportWidth(context),
      localX: localX,
    );
  }

  void _dragHorizontalScrollbarByDelta(double deltaX) {
    if (_horizontalScrollbarDragMode == 'resize_start' ||
        _horizontalScrollbarDragMode == 'resize_end') {
      _resizeHorizontalScrollbarByDelta(deltaX);
      return;
    }
    _dragHorizontalScrollbarBy(
      viewportWidth: _getViewportWidth(context),
      deltaX: deltaX,
    );
  }

  void _resizeHorizontalScrollbarByDelta(double deltaX) {
    _horizontalScrollbarDragAccumX += deltaX;
    final resizeStart = _horizontalScrollbarDragMode == 'resize_start';
    final zoomDeltaPx = resizeStart
        ? _horizontalScrollbarDragAccumX
        : -_horizontalScrollbarDragAccumX;
    final nextPixelsPerMs =
        (_horizontalScrollbarDragStartPixelsPerMs *
                math.exp(zoomDeltaPx * _kHorizontalScrollbarResizeSensitivity))
            .clamp(_kMinTimelinePixelsPerMs, _kMaxTimelinePixelsPerMs)
            .toDouble();
    if ((nextPixelsPerMs - _pixelsPerMs).abs() < 0.000001) return;
    setState(() {
      _pixelsPerMs = nextPixelsPerMs;
      _scrollOffsetMs =
          _horizontalScrollbarDragAnchorMs -
          (_horizontalScrollbarDragAnchorLocalX / _pixelsPerMs);
      _clampScroll();
    });
    _publishHorizontalScrollbarState();
    widget.onTutorialTimelineZoomed?.call();
  }

  void _jumpHorizontalScrollbarTo({
    required double viewportWidth,
    required double localX,
  }) {
    final metrics = _horizontalScrollbarMetrics(viewportWidth);
    if (metrics == null || metrics.trackTravel <= 0.0) return;
    final targetThumbLeft =
        (localX - metrics.trackInset - (metrics.thumbWidth / 2.0)).clamp(
          0.0,
          metrics.trackTravel,
        );
    final targetRatio = targetThumbLeft / metrics.trackTravel;
    _setScrollOffsetFromHorizontalScrollbar(
      viewportWidth: viewportWidth,
      targetScrollMs:
          metrics.minScrollMs + (targetRatio * metrics.scrollableMs),
    );
  }

  void _dragHorizontalScrollbarBy({
    required double viewportWidth,
    required double deltaX,
  }) {
    final metrics = _horizontalScrollbarMetrics(viewportWidth);
    if (metrics == null || metrics.trackTravel <= 0.0) return;
    final scrollDeltaMs = (deltaX / metrics.trackTravel) * metrics.scrollableMs;
    _setScrollOffsetFromHorizontalScrollbar(
      viewportWidth: viewportWidth,
      targetScrollMs: _scrollOffsetMs + scrollDeltaMs,
    );
  }

  double _horizontalScrollbarMinThumbWidthForZoom() {
    const shrinkSpan =
        _kHorizontalScrollbarMinShrinkEndPixelsPerMs -
        _kHorizontalScrollbarMinShrinkStartPixelsPerMs;
    final progress = shrinkSpan <= 0.0
        ? 1.0
        : ((_pixelsPerMs - _kHorizontalScrollbarMinShrinkStartPixelsPerMs) /
                  shrinkSpan)
              .clamp(0.0, 1.0)
              .toDouble();
    return _kHorizontalScrollbarComfortMinThumbWidth -
        ((_kHorizontalScrollbarComfortMinThumbWidth -
                _kHorizontalScrollbarZoomedMinThumbWidth) *
            progress);
  }

  _HorizontalScrollbarMetrics? _horizontalScrollbarMetrics(
    double viewportWidth,
  ) {
    if (!viewportWidth.isFinite || viewportWidth <= 0.0 || _pixelsPerMs <= 0) {
      return null;
    }

    final minScrollMs = _horizontalScrollbarMinScrollMs(context);
    final maxScrollMs = math.max(
      minScrollMs,
      _horizontalScrollbarMaxScrollMs(
        context: context,
        viewportWidth: viewportWidth,
      ),
    );
    final scrollableMs = math.max(0.0, maxScrollMs - minScrollMs);

    final viewportMs = viewportWidth / _pixelsPerMs;
    final contentSpanMs = viewportMs + scrollableMs;
    if (!contentSpanMs.isFinite || contentSpanMs <= 0.0) return null;

    const trackInset = _kHorizontalScrollbarEndInset;
    final trackWidth = math.max(0.0, viewportWidth - (trackInset * 2.0));
    if (trackWidth <= 0.0) return null;

    final minThumbWidth = math.min(
      _horizontalScrollbarMinThumbWidthForZoom(),
      trackWidth,
    );
    final thumbWidth = (trackWidth * (viewportMs / contentSpanMs))
        .clamp(minThumbWidth, trackWidth)
        .toDouble();
    final trackTravel = math.max(0.0, trackWidth - thumbWidth);
    final thumbLeft = trackTravel <= 0.0
        ? trackInset
        : trackInset +
              (((_scrollOffsetMs - minScrollMs) / scrollableMs) * trackTravel)
                  .clamp(0.0, trackTravel)
                  .toDouble();

    return _HorizontalScrollbarMetrics(
      minScrollMs: minScrollMs,
      scrollableMs: scrollableMs,
      trackInset: trackInset,
      thumbLeft: thumbLeft,
      thumbWidth: thumbWidth,
      trackTravel: trackTravel,
    );
  }

  void _publishHorizontalScrollbarState({double? viewportWidth}) {
    final controller = widget.controller;
    if (controller == null) return;
    if (!PlatformCapabilities.current.isDesktop) {
      controller._setHorizontalScrollbarState(
        TimelineHorizontalScrollbarState.hidden,
      );
      return;
    }

    final effectiveViewportWidth = viewportWidth ?? _getViewportWidth(context);
    final metrics = _horizontalScrollbarMetrics(effectiveViewportWidth);
    if (metrics == null) {
      controller._setHorizontalScrollbarState(
        TimelineHorizontalScrollbarState.hidden,
      );
      return;
    }

    controller._setHorizontalScrollbarState(
      TimelineHorizontalScrollbarState(
        visible: true,
        headerWidth: _headerWidth,
        viewportWidth: effectiveViewportWidth,
        thumbLeft: metrics.thumbLeft,
        thumbWidth: metrics.thumbWidth,
        thumbHeight: _horizontalScrollbarDragging
            ? _kHorizontalScrollbarActiveHeight
            : _kHorizontalScrollbarHeight,
        hitHeight: _kHorizontalScrollbarHitHeight,
        trackHeight: _horizontalScrollbarDragging
            ? _kHorizontalScrollbarActiveTrackHeight
            : _kHorizontalScrollbarTrackHeight,
        endInset: metrics.trackInset,
        dragging: _horizontalScrollbarDragging,
        resizeStartActive: _horizontalScrollbarDragMode == 'resize_start',
        resizeEndActive: _horizontalScrollbarDragMode == 'resize_end',
      ),
    );
  }

  double _timelineWidgetWidth(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final width = renderObject.size.width;
      if (width.isFinite && width > 0) return width;
    }
    return MediaQuery.sizeOf(context).width;
  }

  double _viewportWidthForTimelineWidth(double timelineWidth) {
    return math.max(0.0, timelineWidth - _headerWidth);
  }

  double _getMobilePlayheadPxForTimelineWidth(double timelineWidth) {
    return (timelineWidth / 2.0) - _headerWidth;
  }

  void _jumpDesktopPlayheadToRulerX(double localDx) {
    final tappedMsRaw = _rulerMsFromLocalX(localDx);
    final tappedMs = _magnetEnabled ? _quantizeMs(tappedMsRaw) : tappedMsRaw;
    final safeTappedMs = math.max(0.0, tappedMs);
    widget.onScrubRequested(safeTappedMs);
  }

  int _normalizeExpandedTab(int tab) {
    if (tab == 1 || tab == 2) return tab;
    return 0;
  }

  bool _isFixedHeightExpandedTab(int tab) {
    final normalized = _normalizeExpandedTab(tab);
    return normalized == 0 || normalized == 2;
  }

  double get _totalTimelineHeight {
    double total = _masterAutomationLanePaintHeight;
    for (int i = 0; i < _rowCount; i++) {
      if (!_isSourceRowVisible(i)) continue;
      total += _rowBlockHeightForIndex(i);
    }
    return total;
  }

  double get _timelinePaintHeight => math.max(_totalTimelineHeight, _rowHeight);
  double get _scrollContentHeight {
    if (_usesTabletDawLayout) {
      return _timelinePaintHeight + _kTabletStickyFooterTotalHeight;
    }
    return _timelinePaintHeight +
        kHeaderFooterHeight +
        _kAddRowPillHeight +
        _kAddRowSectionGap +
        _editorLayoutSpec.bottomInteractionPadding +
        _kExtraAddRowBottomPadding;
  }

  void _recalculateRowYPositions() {
    _rowYPositions.clear();

    double y = _masterAutomationLanePaintHeight;
    for (int i = 0; i < _rowCount; i++) {
      _rowYPositions.add(y);
      if (_isSourceRowVisible(i)) {
        y += _rowBlockHeightForIndex(i);
      }
    }
  }

  _AutomationValueFormatter _automationValueFormatterForTarget(
    int row,
    String targetId,
  ) {
    final targetMeta = _automationTargetMetaById(row, targetId);
    final targetLabel = (targetMeta?['label'] ?? targetId).toString().trim();
    final targetParamId = (targetMeta?['paramId'] ?? targetId)
        .toString()
        .trim();
    final targetUnit = (targetMeta?['unit'] ?? '').toString().trim();
    return _AutomationValueFormatter(
      targetLabel: targetLabel.isEmpty ? targetId : targetLabel,
      targetParamId: targetParamId.isEmpty ? targetId : targetParamId,
      targetUnit: targetUnit,
      targetMin: (targetMeta?['min'] as num?)?.toDouble() ?? 0.0,
      targetMax: (targetMeta?['max'] as num?)?.toDouble() ?? 1.0,
      isVolumeLane: targetMeta?['isVolume'] == true || targetId == 'volume',
    );
  }

  double _automationLaneLocalY(
    double volume,
    double laneHeight, {
    _AutomationValueFormatter? formatter,
  }) {
    const verticalPadding = 12.0;
    final usable = laneHeight - verticalPadding * 2;
    final displayVolume =
        formatter?.displayNormalizedForStoredNormalized(volume) ?? volume;
    return verticalPadding + (1 - displayVolume) * usable;
  }

  bool _isAutomationLaneTabForRow(int row) {
    if (row < 0 || row >= _rowCount) return false;
    final tab = _normalizeExpandedTab(_expandedTab[row]);
    return tab == 0 || tab == 2 || _isAutomationEditorOpenForRow(row);
  }

  String _activeAutomationTargetIdForRow(int row) {
    if (row < 0 || row >= _rowCount) return 'volume';
    final normalizedTab = _normalizeExpandedTab(_expandedTab[row]);
    if (normalizedTab == 2 || _isAutomationEditorOpenForRow(row)) {
      final selected = widget.getSelectedAutomationTargetId(row).trim();
      return _resolveAutomationTabTargetId(row, selected);
    }
    return 'volume';
  }

  List<AutomationPoint> _activeAutomationPointsForRow(int row) {
    final targetId = _activeAutomationTargetIdForRow(row);
    if (targetId == 'volume') {
      return widget.rowVolumeAutomation[row];
    }
    return widget.getAutomationPointsForTarget(row, targetId);
  }

  void _setActiveAutomationPointsForRow(
    int row,
    String targetId,
    List<AutomationPoint> points,
  ) {
    if (targetId == 'volume') {
      widget.rowVolumeAutomation[row] = points;
      widget.setTrackAutomationPoints(
        row,
        points.map((p) => p.toMap()).toList(),
      );
      return;
    }
    widget.setAutomationPointsForTarget(row, targetId, points);
  }

  void _commitAutomationPointsForTarget(
    int row,
    String targetId,
    List<AutomationPoint> before,
    List<AutomationPoint> after,
  ) {
    _setActiveAutomationPointsForRow(row, targetId, after);
    if (targetId == 'volume') {
      widget.onAutomationCommit?.call(row, before, after);
      return;
    }
    widget.onAutomationTargetCommit?.call(row, targetId, before, after);
  }

  double _automationValueAtMs(List<AutomationPoint> points, double ms) {
    if (points.isEmpty) return 0.5;
    final sorted = points.map((p) => p.copy()).toList(growable: false)
      ..sort((a, b) => a.x.compareTo(b.x));
    if (ms <= sorted.first.x) return sorted.first.volume;
    for (int i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (ms < a.x || ms > b.x) continue;
      final span = b.x - a.x;
      if (span.abs() < 1e-9) return b.volume;
      final t = ((ms - a.x) / span).clamp(0.0, 1.0).toDouble();
      return a.volume + (b.volume - a.volume) * t;
    }
    return sorted.last.volume;
  }

  List<AutomationPoint> _automationPointsForRange(
    List<AutomationPoint> points, {
    required double startMs,
    required double endMs,
    required bool relativeToStart,
  }) {
    final safeStart = math.min(startMs, endMs);
    final safeEnd = math.max(startMs, endMs);
    if ((safeEnd - safeStart).abs() < 1e-6) {
      final value = _automationValueAtMs(points, safeStart);
      return <AutomationPoint>[
        AutomationPoint(x: relativeToStart ? 0.0 : safeStart, volume: value),
      ];
    }
    final sorted = points.map((p) => p.copy()).toList(growable: false)
      ..sort((a, b) => a.x.compareTo(b.x));
    final out = <AutomationPoint>[];
    final startValue = _automationValueAtMs(sorted, safeStart);
    final endValue = _automationValueAtMs(sorted, safeEnd);
    final offset = relativeToStart ? safeStart : 0.0;
    out.add(AutomationPoint(x: safeStart - offset, volume: startValue));
    for (final point in sorted) {
      if (point.x <= safeStart + 1e-6 || point.x >= safeEnd - 1e-6) continue;
      out.add(AutomationPoint(x: point.x - offset, volume: point.volume));
    }
    out.add(AutomationPoint(x: safeEnd - offset, volume: endValue));
    out.sort((a, b) => a.x.compareTo(b.x));
    return out;
  }

  bool _hasActiveLoopRange() {
    return _loopEnabled &&
        _loopStartMs != null &&
        _loopEndMs != null &&
        _loopEndMs! > _loopStartMs!;
  }

  bool _isAutomationRangeSelectionModeFor(int row, String targetId) {
    if (!_automationRangeSelectionMode) return false;
    if (_automationRangeSelectionRow != row) return false;
    return _automationRangeSelectionTargetId == targetId;
  }

  void _clearAutomationRangeSelectionMode({
    bool clearHighlightedSegment = false,
  }) {
    _automationRangeSelectionMode = false;
    _automationRangeSelectionRow = null;
    _automationRangeSelectionTargetId = null;
    _automationRangeSelectionStartMs = null;
    _automationRangeSelectionEndMs = null;
    if (clearHighlightedSegment) {
      _highlightedSegmentRow = null;
      _highlightedSegmentStartMs = null;
      _highlightedSegmentEndMs = null;
    }
  }

  double _normalizeValueToAutomationRange(
    double value, {
    required double min,
    required double max,
    double fallback = 0.5,
  }) {
    final span = max - min;
    if (!span.isFinite || span.abs() < 1e-9) {
      return fallback.clamp(0.0, 1.0).toDouble();
    }
    return ((value - min) / span).clamp(0.0, 1.0).toDouble();
  }

  double _automationTargetInitialNormalized(
    String targetId,
    Map<String, dynamic>? targetMeta,
  ) {
    final fallback = targetId == 'volume' ? 0.75 : 0.5;
    final fromInitial = (targetMeta?['initialNormalized'] as num?)?.toDouble();
    if (fromInitial != null && fromInitial.isFinite) {
      return fromInitial.clamp(0.0, 1.0).toDouble();
    }

    final min = (targetMeta?['min'] as num?)?.toDouble() ?? 0.0;
    final max = (targetMeta?['max'] as num?)?.toDouble() ?? 1.0;
    final fromRawValue = (targetMeta?['value'] as num?)?.toDouble();
    if (fromRawValue != null && fromRawValue.isFinite) {
      return _normalizeValueToAutomationRange(
        fromRawValue,
        min: min,
        max: max,
        fallback: fallback,
      );
    }

    return fallback;
  }

  bool _automationPointListsEqual(
    List<AutomationPoint> a,
    List<AutomationPoint> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if ((a[i].x - b[i].x).abs() > 1e-6 ||
          (a[i].volume - b[i].volume).abs() > 1e-6) {
        return false;
      }
    }
    return true;
  }

  String _automationLaneKey(int row, String targetId) => '$row|$targetId';

  List<AutomationClipSnapshot> _cloneAutomationClips(
    List<AutomationClipSnapshot> clips,
  ) {
    return clips.map((clip) => clip.copyWith()).toList(growable: false);
  }

  String _newAutomationPatternId(int row, String targetId) {
    return 'apat_${row}_${targetId}_${DateTime.now().microsecondsSinceEpoch}_${const Uuid().v4()}';
  }

  bool _automationClipListsEqual(
    List<AutomationClipSnapshot> a,
    List<AutomationClipSnapshot> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.targetId != y.targetId ||
          x.label != y.label ||
          x.patternId != y.patternId ||
          x.row != y.row ||
          x.lane != y.lane ||
          x.muted != y.muted ||
          (x.startMs - y.startMs).abs() > 1e-6 ||
          (x.lengthMs - y.lengthMs).abs() > 1e-6) {
        return false;
      }
      if (x.points.length != y.points.length) return false;
      for (int p = 0; p < x.points.length; p++) {
        final xp = x.points[p];
        final yp = y.points[p];
        if ((xp.x - yp.x).abs() > 1e-6 ||
            (xp.volume - yp.volume).abs() > 1e-6) {
          return false;
        }
      }
    }
    return true;
  }

  String? _selectedAutomationClipIdFor(int row, String targetId) {
    return _selectedAutomationClipByLane[_automationLaneKey(row, targetId)];
  }

  int? _selectedAutomationClipIndexFor(
    int row,
    String targetId,
    List<AutomationClipSnapshot> clips,
  ) {
    if (clips.isEmpty) return null;
    final id = _selectedAutomationClipIdFor(row, targetId);
    if (id != null && id.isNotEmpty) {
      final index = clips.indexWhere((clip) => clip.id == id);
      if (index >= 0) return index;
    }
    return null;
  }

  void _setSelectedAutomationClipFor(
    int row,
    String targetId,
    String? clipId, {
    int? lane,
  }) {
    final key = _automationLaneKey(row, targetId);
    if (clipId == null || clipId.isEmpty) {
      _selectedAutomationClipByLane.remove(key);
      return;
    }
    _selectedAutomationClipByLane[key] = clipId;
    if (lane != null) {
      _setFocusedAutomationLaneForRow(row, lane);
    }
  }

  AutomationClipSnapshot? _selectedAutomationClipForTarget(
    int row,
    String targetId, {
    List<AutomationClipSnapshot>? clipsOverride,
  }) {
    final clips = _cloneAutomationClips(
      clipsOverride ?? widget.getAutomationClipsForTarget(row, targetId),
    );
    final selectedIndex = _selectedAutomationClipIndexFor(row, targetId, clips);
    if (selectedIndex == null ||
        selectedIndex < 0 ||
        selectedIndex >= clips.length) {
      return null;
    }
    final selected = clips[selectedIndex];
    _setFocusedAutomationLaneForRow(row, selected.lane);
    return selected;
  }

  List<AutomationPoint> _automationClipPointsToAbsolute(
    AutomationClipSnapshot clip,
  ) {
    final start = clip.startMs;
    final end = clip.startMs + clip.lengthMs;
    final points =
        clip.points
            .map(
              (p) => AutomationPoint(
                x: (start + p.x).clamp(start, end).toDouble(),
                volume: p.volume.clamp(0.0, 1.0).toDouble(),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.x.compareTo(b.x));
    if (points.isEmpty) {
      return <AutomationPoint>[AutomationPoint(x: start, volume: 0.5)];
    }
    return points;
  }

  List<AutomationPoint> _automationClipPointsToRelative(
    AutomationClipSnapshot clip,
    List<AutomationPoint> absolutePoints,
  ) {
    final points =
        absolutePoints
            .map(
              (p) => AutomationPoint(
                x: (p.x - clip.startMs).clamp(0.0, clip.lengthMs).toDouble(),
                volume: p.volume.clamp(0.0, 1.0).toDouble(),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.x.compareTo(b.x));
    if (points.isEmpty) {
      final fallback = clip.points.isNotEmpty
          ? clip.points.first.volume.clamp(0.0, 1.0).toDouble()
          : 0.5;
      return <AutomationPoint>[AutomationPoint(x: 0.0, volume: fallback)];
    }
    return points;
  }

  bool _setSelectedAutomationClipPointsForTarget(
    int row,
    String targetId,
    List<AutomationPoint> absolutePoints, {
    List<AutomationClipSnapshot>? clipsOverride,
  }) {
    final current = _cloneAutomationClips(
      clipsOverride ?? widget.getAutomationClipsForTarget(row, targetId),
    );
    final selectedIndex = _selectedAutomationClipIndexFor(
      row,
      targetId,
      current,
    );
    if (selectedIndex == null ||
        selectedIndex < 0 ||
        selectedIndex >= current.length) {
      return false;
    }
    final selected = current[selectedIndex];
    final relative = _automationClipPointsToRelative(selected, absolutePoints);
    if (_automationPointListsEqual(selected.points, relative)) {
      return false;
    }
    final patternId = selected.patternId.trim();
    if (patternId.isNotEmpty) {
      for (int i = 0; i < current.length; i++) {
        if (current[i].patternId.trim() != patternId) continue;
        current[i] = current[i].copyWith(points: relative);
      }
    } else {
      current[selectedIndex] = selected.copyWith(points: relative);
    }
    widget.setAutomationClipsForTarget(row, targetId, current);
    _setSelectedAutomationClipFor(
      row,
      targetId,
      current[selectedIndex].id,
      lane: current[selectedIndex].lane,
    );
    return true;
  }

  void _focusAutomationEditorForRow(int row, String targetId) {
    if (row < 0 || row >= _rowCount) return;
    final oldExpanded = List<bool>.from(_rowExpanded);
    setState(() {
      _setAutomationEditorFor(row, targetId);
    });
    _notifyRowExpansionChanges(oldExpanded);
  }

  double _defaultAutomationClipLengthMs() {
    final oneBar = _msPerBar().clamp(120.0, _maxDurationMs);
    return oneBar.toDouble();
  }

  List<AutomationPoint> _defaultAutomationClipPointsForTarget(
    String targetId,
    double? initialNormalized,
  ) {
    final fallback = targetId == 'volume' ? 0.75 : 0.5;
    final value = (initialNormalized ?? fallback).clamp(0.0, 1.0).toDouble();
    return <AutomationPoint>[AutomationPoint(x: 0.0, volume: value)];
  }

  void _applyAutomationClipsWithCommit(
    int row,
    String targetId,
    List<AutomationClipSnapshot> oldClips,
    List<AutomationClipSnapshot> nextClips,
  ) {
    final clonedOld = _cloneAutomationClips(oldClips);
    final clonedNext = _cloneAutomationClips(nextClips);
    if (_automationClipListsEqual(clonedOld, clonedNext)) {
      return;
    }
    widget.setAutomationClipsForTarget(row, targetId, clonedNext);
    widget.onAutomationClipsCommit?.call(row, targetId, clonedOld, clonedNext);
    setState(() {});
  }

  void _insertAutomationClipForTarget({
    required int row,
    required String targetId,
    required String targetLabel,
    required double initialNormalized,
    int? lane,
  }) {
    widget.setSelectedAutomationTargetId(row, targetId);
    final before = _cloneAutomationClips(
      widget.getAutomationClipsForTarget(row, targetId),
    );
    final startRaw = _magnetEnabled
        ? _segmentStartMsForTap(_currentPlayheadMs)
        : _currentPlayheadMs;
    final startMs = startRaw.clamp(0.0, _maxDurationMs).toDouble();
    final lengthMs = _defaultAutomationClipLengthMs();
    final resolvedLane =
        lane ?? _suggestAutomationLaneForClip(row, startMs, lengthMs);
    final visualRow = _preferredAutomationClipRowForTarget(row, targetId);
    final id =
        'ui_clip_${DateTime.now().microsecondsSinceEpoch}_${row}_$targetId';
    final newClip = AutomationClipSnapshot(
      id: id,
      targetId: targetId,
      label: targetLabel.trim().isEmpty ? targetId : targetLabel,
      patternId: '',
      row: visualRow,
      lane: resolvedLane,
      startMs: startMs,
      lengthMs: lengthMs,
      muted: false,
      points: _defaultAutomationClipPointsForTarget(
        targetId,
        initialNormalized,
      ),
    );
    final next = [...before, newClip];
    _setSelectedAutomationClipFor(row, targetId, id, lane: resolvedLane);
    _applyAutomationClipsWithCommit(row, targetId, before, next);
  }

  int _suggestAutomationLaneForClip(int row, double startMs, double lengthMs) {
    return 0;
  }

  Future<void> _revealRowAutomationTarget(int row, String targetId) async {
    if (row < 0 || row >= _rowCount) return;
    if (_usesDesktopOrTabletDawLayout &&
        widget.onRevealAutomationTarget != null) {
      await widget.onRevealAutomationTarget!(row, targetId);
      return;
    }
    final targetMeta = _automationTargetMetaById(row, targetId);
    final isOrphan = targetMeta?['isOrphan'] == true;
    final effectIndex = (targetMeta?['effectIndex'] as num?)?.toInt() ?? -1;
    final paramId = (targetMeta?['paramId'] ?? targetId).toString().trim();
    final parsedTargetId = targetMeta == null
        ? targetId.trim().toLowerCase()
        : (targetMeta['id'] ?? targetId).toString().trim().toLowerCase();
    _setExpandedTabForRow(
      row: row,
      tab: effectIndex >= 0 && parsedTargetId != 'volume' ? 1 : 0,
      selectRow: true,
      expandOnlyThisRow: true,
      selectedAutomationTargetId: targetId,
    );

    if (effectIndex < 0 || parsedTargetId == 'volume') {
      final haloKeys = <String>['row:$row:volume_tab', 'row:$row:mixer'];
      if (parsedTargetId.contains('gain')) {
        haloKeys.add('row:$row:gain');
        haloKeys.add('row:$row:param:gain');
      } else if (parsedTargetId.contains('pan')) {
        haloKeys.add('row:$row:pan');
        haloKeys.add('row:$row:param:pan');
      } else {
        haloKeys.add('row:$row:volume_lane');
        haloKeys.add('row:$row:param:volume');
      }
      _triggerTimelineHalos(haloKeys);
      if (isOrphan) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                L10n.translate(
                  context,
                  'This automation target is orphaned. Undo the plugin removal or re-add the plugin to relink it.',
                ),
              ),
            ),
          );
      }
      return;
    }

    if (isOrphan) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              L10n.translate(
                context,
                'This automation target is orphaned. Undo the plugin removal or re-add the plugin to relink it.',
              ),
            ),
          ),
        );
      return;
    }

    // Follow the same tab transition lifecycle as manual Effects-tab navigation
    // before opening the target parameter page.
    _refreshRowFx(row);
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final rawLabel = (targetMeta?['label'] ?? '').toString().trim();
    final fallbackParamName = rawLabel.contains('•')
        ? rawLabel.split('•').last.trim()
        : (targetMeta?['paramId'] ?? paramId).toString().trim();
    final fallbackSlug = _haloSlug(fallbackParamName);
    final paramIdSlug = _haloSlug(paramId);
    final revealer = await _waitForRowParameterRevealer(row);
    if (revealer != null) {
      await revealer(effectIndex, paramId);
      if (!mounted) return;
      if (fallbackParamName.isNotEmpty &&
          fallbackParamName.toLowerCase() != paramId.toLowerCase()) {
        await revealer(effectIndex, fallbackParamName);
      }
      if (!mounted) return;
      final haloKeys = <String>[
        'row:$row:effects_tab',
        'row:$row:fx_index:$effectIndex',
        if (paramId.isNotEmpty) 'row:$row:fx_index:$effectIndex:param:$paramId',
        if (paramId.isNotEmpty)
          'row:$row:fx_index:$effectIndex:param:${paramId.toLowerCase()}',
        if (paramIdSlug.isNotEmpty)
          'row:$row:fx_index:$effectIndex:param:$paramIdSlug',
        if (fallbackParamName.isNotEmpty)
          'row:$row:fx_index:$effectIndex:param:$fallbackParamName',
        if (fallbackParamName.isNotEmpty)
          'row:$row:fx_index:$effectIndex:param:${fallbackParamName.toLowerCase()}',
        if (fallbackSlug.isNotEmpty)
          'row:$row:fx_index:$effectIndex:param:$fallbackSlug',
        if (fallbackParamName.isNotEmpty) 'row:$row:param:$fallbackParamName',
        if (fallbackSlug.isNotEmpty) 'row:$row:param:$fallbackSlug',
      ];
      _triggerTimelineHalos(haloKeys);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      _triggerTimelineHalos(haloKeys);
    }
  }

  void _openAutomationClipEditor(_TimelineAutomationClipVisual clipVisual) {
    final oldExpanded = List<bool>.from(_rowExpanded);
    setState(() {
      _setSelectedAutomationClipFor(
        clipVisual.row,
        clipVisual.targetId,
        clipVisual.clip.id,
        lane: clipVisual.clip.lane,
      );
      _setAutomationEditorFor(clipVisual.row, clipVisual.targetId);
      _revealAutomationRangeInViewport(
        clipVisual.clip.startMs,
        clipVisual.clip.startMs + clipVisual.clip.lengthMs,
      );
    });
    _notifyRowExpansionChanges(oldExpanded);
  }

  Future<void> _revealAutomationTargetForClip(
    _TimelineAutomationClipVisual clipVisual,
  ) async {
    _setSelectedAutomationClipFor(
      clipVisual.row,
      clipVisual.targetId,
      clipVisual.clip.id,
      lane: clipVisual.clip.lane,
    );
    await _revealRowAutomationTarget(clipVisual.row, clipVisual.targetId);
  }

  void _copyAutomationClipToClipboard(
    _TimelineAutomationClipVisual clipVisual,
  ) {
    _automationClipClipboard = _AutomationClipClipboardEntry(
      targetId: clipVisual.targetId,
      targetLabel: clipVisual.targetLabel,
      clip: clipVisual.clip.copyWith(),
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${L10n.translate(context, 'Clone ready for')} ${clipVisual.targetLabel}',
          ),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  String? _automationPasteTargetIdForRow(int row) {
    final clipboard = _automationClipClipboard;
    if (clipboard == null || row < 0 || row >= _rowCount) return null;
    final targets = widget.getAutomationTargetsForRow(row);
    for (final target in targets) {
      final candidate = (target['id'] ?? '').toString().trim();
      if (candidate == clipboard.targetId) {
        return candidate;
      }
    }
    return null;
  }

  bool _canPasteAutomationClipAt(int row) =>
      _automationPasteTargetIdForRow(row) != null;

  void _pasteAutomationClipAt(int row, double startMs) {
    final clipboard = _automationClipClipboard;
    final targetId = _automationPasteTargetIdForRow(row);
    if (clipboard == null || targetId == null) return;
    final before = _cloneAutomationClips(
      widget.getAutomationClipsForTarget(row, targetId),
    );
    final plan = buildAutomationClipClonePlan(
      existingClips: before,
      clipboardClip: clipboard.clip,
      row: row,
      targetId: targetId,
      startMs: startMs,
      maxDurationMs: _maxDurationMs,
      createClipId: () =>
          'ui_clip_${DateTime.now().microsecondsSinceEpoch}_${row}_$targetId',
      createPatternId: () => _newAutomationPatternId(row, targetId),
    );
    _automationClipClipboard = _AutomationClipClipboardEntry(
      targetId: clipboard.targetId,
      targetLabel: clipboard.targetLabel,
      clip: plan.updatedClipboardClip,
    );
    widget.setSelectedAutomationTargetId(row, targetId);
    _setSelectedAutomationClipFor(
      row,
      targetId,
      plan.clonedClip.id,
      lane: plan.clonedClip.lane,
    );
    _applyAutomationClipsWithCommit(row, targetId, before, plan.nextClips);
  }

  void _clearClipboard() {
    widget.onClearCopiedClip?.call();
    _automationClipClipboard = null;
    _automationPointsClipboard = null;
    _automationAreaClipboard = null;
  }

  Future<void> _handleAutomationClipMenuAction(
    String action,
    _TimelineAutomationClipVisual clipVisual,
  ) async {
    if (!mounted) return;
    setState(_clearAutomationClipMenu);
    switch (action) {
      case 'reveal':
        await _revealAutomationTargetForClip(clipVisual);
        break;
      case 'open':
        _openAutomationClipEditor(clipVisual);
        break;
      case 'copy':
        _copyAutomationClipToClipboard(clipVisual);
        break;
      case 'make_unique':
        _makeSelectedAutomationClipUniqueForTarget(
          clipVisual.row,
          clipVisual.targetId,
          clipId: clipVisual.clip.id,
        );
        break;
      case 'delete':
        _deleteSelectedAutomationClipForTarget(
          clipVisual.row,
          clipVisual.targetId,
        );
        break;
    }
  }

  void _makeSelectedAutomationClipUniqueForTarget(
    int row,
    String targetId, {
    String? clipId,
  }) {
    final before = _cloneAutomationClips(
      widget.getAutomationClipsForTarget(row, targetId),
    );
    final requestedClipId = (clipId ?? '').trim();
    final int? selectedIndex = requestedClipId.isNotEmpty
        ? before.indexWhere((clip) => clip.id == requestedClipId)
        : _selectedAutomationClipIndexFor(row, targetId, before);
    if (selectedIndex == null ||
        selectedIndex < 0 ||
        selectedIndex >= before.length) {
      return;
    }
    final current = before[selectedIndex];
    if (current.patternId.trim().isEmpty) {
      return;
    }
    final next = List<AutomationClipSnapshot>.from(before);
    next[selectedIndex] = current.copyWith(patternId: '');
    _setSelectedAutomationClipFor(
      row,
      targetId,
      next[selectedIndex].id,
      lane: next[selectedIndex].lane,
    );
    _applyAutomationClipsWithCommit(row, targetId, before, next);
  }

  void _deleteSelectedAutomationClipForTarget(int row, String targetId) {
    final before = _cloneAutomationClips(
      widget.getAutomationClipsForTarget(row, targetId),
    );
    final selectedIndex = _selectedAutomationClipIndexFor(
      row,
      targetId,
      before,
    );
    if (selectedIndex == null) return;
    final next = List<AutomationClipSnapshot>.from(before)
      ..removeAt(selectedIndex);
    _setSelectedAutomationClipFor(
      row,
      targetId,
      next.isNotEmpty ? next.last.id : null,
      lane: next.isNotEmpty ? next.last.lane : null,
    );
    _applyAutomationClipsWithCommit(row, targetId, before, next);
  }

  static const double _kAutomationClipMinLengthMs = 50.0;
  static const double _kAutomationClipResizeHandleWidthPx = 12.0;

  List<AutomationPoint> _shiftAutomationClipPoints(
    List<AutomationPoint> points,
    double startDeltaMs,
  ) {
    if (startDeltaMs.abs() < 1e-7) {
      return points.map((p) => p.copy()).toList(growable: false);
    }
    return points
        .map((p) => AutomationPoint(x: p.x - startDeltaMs, volume: p.volume))
        .toList(growable: false);
  }

  void _beginAutomationClipDrag(
    int row,
    String targetId,
    AutomationClipSnapshot clip,
    Offset localPos,
    double clipWidthPx, [
    String? modeOverride,
  ]) {
    _automationClipDragBefore = _cloneAutomationClips(
      widget.getAutomationClipsForTarget(row, targetId),
    );
    _automationClipDragRow = row;
    _automationClipDragTargetId = targetId;
    _automationClipDragId = clip.id;
    _automationClipDragDxAccum = 0.0;
    _automationClipDragOrigin = clip.copyWith();
    final handleWidth = math.min(
      _kAutomationClipResizeHandleWidthPx,
      clipWidthPx * 0.4,
    );
    if (modeOverride != null && modeOverride.isNotEmpty) {
      _automationClipDragMode = modeOverride;
    } else if (clipWidthPx <= (handleWidth * 2.0)) {
      _automationClipDragMode = 'move';
    } else {
      final onLeftHandle = localPos.dx <= handleWidth;
      final onRightHandle = localPos.dx >= (clipWidthPx - handleWidth);
      if (onLeftHandle && !onRightHandle) {
        _automationClipDragMode = 'trim_start';
      } else if (onRightHandle) {
        _automationClipDragMode = 'trim_end';
      } else {
        _automationClipDragMode = 'move';
      }
    }
    _setSelectedAutomationClipFor(row, targetId, clip.id, lane: clip.lane);
  }

  void _updateAutomationClipDrag(
    int row,
    String targetId,
    AutomationClipSnapshot clip,
    double deltaPx,
    Offset localPos,
  ) {
    if (_automationClipDragRow != row ||
        _automationClipDragTargetId != targetId ||
        _automationClipDragId != clip.id) {
      return;
    }
    final mode = _automationClipDragMode;
    final origin = _automationClipDragOrigin;
    if (mode == null || origin == null) return;

    final current = _cloneAutomationClips(
      widget.getAutomationClipsForTarget(row, targetId),
    );
    final index = current.indexWhere((c) => c.id == clip.id);
    if (index < 0) return;
    _automationClipDragDxAccum += deltaPx;
    final deltaMs = _automationClipDragDxAccum / _pixelsPerMs;

    if (mode == 'move') {
      var nextStart = origin.startMs + deltaMs;
      nextStart = _segmentStartMsForTimelineClipDrag(nextStart);
      nextStart = math.max(0.0, nextStart).toDouble();
      final hoveredRow = _rowForLocalY(localPos.dy);
      final nextRow =
          (hoveredRow ?? (localPos.dy < 0 ? 0 : math.max(0, _rowCount - 1)))
              .clamp(0, math.max(0, _rowCount - 1))
              .toInt();
      current[index] = origin.copyWith(
        startMs: nextStart,
        row: nextRow,
        lane: origin.lane,
      );
    } else if (mode == 'trim_end') {
      var nextEndMs = origin.startMs + origin.lengthMs + deltaMs;
      nextEndMs = _segmentStartMsForTimelineClipDrag(nextEndMs);
      final minEndMs = origin.startMs + _kAutomationClipMinLengthMs;
      nextEndMs = nextEndMs.clamp(minEndMs, _maxDurationMs).toDouble();
      final nextLength = (nextEndMs - origin.startMs)
          .clamp(_kAutomationClipMinLengthMs, _maxDurationMs)
          .toDouble();
      current[index] = origin.copyWith(lengthMs: nextLength);
    } else if (mode == 'trim_start') {
      var nextStart = origin.startMs + deltaMs;
      nextStart = _segmentStartMsForTimelineClipDrag(nextStart);
      final maxStart =
          origin.startMs + origin.lengthMs - _kAutomationClipMinLengthMs;
      nextStart = nextStart.clamp(0.0, maxStart).toDouble();
      var nextLength = (origin.startMs + origin.lengthMs) - nextStart;
      nextLength = nextLength
          .clamp(_kAutomationClipMinLengthMs, _maxDurationMs - nextStart)
          .toDouble();
      final startDelta = nextStart - origin.startMs;
      final shiftedPoints = _shiftAutomationClipPoints(
        origin.points,
        startDelta,
      );
      current[index] = origin.copyWith(
        startMs: nextStart,
        lengthMs: nextLength,
        points: shiftedPoints,
      );
    }

    widget.setAutomationClipsForTarget(row, targetId, current);
    _setFocusedAutomationLaneForRow(row, origin.lane);
    setState(() {});
  }

  void _endAutomationClipDrag(int row, String targetId) {
    final before = _automationClipDragBefore;
    final dragRow = _automationClipDragRow;
    final dragTarget = _automationClipDragTargetId;
    final dragged = _activeDraggedAutomationClip();
    if (before != null && dragRow == row && dragTarget == targetId) {
      final after = _cloneAutomationClips(
        widget.getAutomationClipsForTarget(row, targetId),
      );
      if (!_automationClipListsEqual(before, after)) {
        widget.onAutomationClipsCommit?.call(row, targetId, before, after);
      }
    }
    if (dragged != null) {
      _setFocusedAutomationLaneForRow(row, dragged.lane);
    }
    _automationClipDragBefore = null;
    _automationClipDragRow = null;
    _automationClipDragTargetId = null;
    _automationClipDragId = null;
    _automationClipDragMode = null;
    _automationClipDragDxAccum = 0.0;
    _automationClipDragOrigin = null;
  }

  // ======================================================
  // AUTOMATION DRAG PRIORITY HANDLERS (inside timeline state)
  // ======================================================

  void _automationPanStart(int row, Offset pos, double laneHeight) {
    if (!_isAutomationLaneTabForRow(row)) return;
    final lane = _activeAutomationPointsForRow(row);
    _automationBefore = lane.map((p) => p.copy()).toList();

    // GIVE AUTOMATION PRIORITY RIGHT AWAY
    setState(() {
      _interactionMode = 'automation';
      _isUserInteracting = true;
      _automationActiveLaneHeight = laneHeight;
    });

    for (int i = 0; i < lane.length; i++) {
      final p = lane[i];

      // compute timeline-local px
      final px = (p.x - _scrollOffsetMs) * _pixelsPerMs;

      // compute LANE-local py
      final formatter = _automationValueFormatterForTarget(
        row,
        _activeAutomationTargetIdForRow(row),
      );
      final py = _automationLaneLocalY(
        p.volume,
        laneHeight,
        formatter: formatter,
      );

      if ((pos - Offset(px, py)).distance < 20) {
        // compute the offset between finger and point Y
        final p = lane[i];
        final py = _automationLaneLocalY(
          p.volume,
          laneHeight,
          formatter: formatter,
        );
        setState(() {
          _interactionMode = 'automation';
          _isUserInteracting = true;
          _automationDragRow = row;
          _automationDragIndex = i;
          _automationDragStart = pos;

          _automationFingerOffsetY = pos.dy - py;
        });
        return;
      }
    }
  }

  void _masterAutomationPanStart(
    String targetId,
    Offset pos,
    double laneHeight,
  ) {
    if (!_isMasterAutomationLaneOpen || _rowCount <= 0) return;
    final normalizedTargetId = _resolveAutomationTargetIdFromTargets(
      _automationTargetsForMasterLane(),
      targetId,
    );
    if (normalizedTargetId.trim().isEmpty) return;
    const row = 0;
    final lane = widget.getAutomationPointsForTarget(row, normalizedTargetId);
    _automationBefore = lane.map((p) => p.copy()).toList();

    setState(() {
      _interactionMode = 'automation';
      _isUserInteracting = true;
      _automationActiveLaneHeight = laneHeight;
      _automationDragRow = row;
    });

    final formatter = _automationValueFormatterForTarget(
      row,
      normalizedTargetId,
    );
    for (int i = 0; i < lane.length; i++) {
      final p = lane[i];
      final px = (p.x - _scrollOffsetMs) * _pixelsPerMs;
      final py = _automationLaneLocalY(
        p.volume,
        laneHeight,
        formatter: formatter,
      );
      if ((pos - Offset(px, py)).distance < 20) {
        setState(() {
          _automationDragIndex = i;
          _automationDragStart = pos;
          _automationFingerOffsetY = pos.dy - py;
        });
        return;
      }
    }
  }

  void _masterAutomationPanUpdate(String targetId, Offset pos) {
    if (_interactionMode != 'automation') return;
    if (_automationDragIndex == null || _rowCount <= 0) return;
    final normalizedTargetId = _resolveAutomationTargetIdFromTargets(
      _automationTargetsForMasterLane(),
      targetId,
    );
    if (normalizedTargetId.trim().isEmpty) return;
    const row = 0;
    final formatter = _automationValueFormatterForTarget(
      row,
      normalizedTargetId,
    );
    final points = List<AutomationPoint>.from(
      widget.getAutomationPointsForTarget(row, normalizedTargetId),
    );
    final index = _automationDragIndex!;
    if (index < 0 || index >= points.length) return;
    final p = points[index];

    double newTimeMs = (pos.dx / _pixelsPerMs) + _scrollOffsetMs;
    if (_magnetEnabled) {
      newTimeMs = _quantizeMs(newTimeMs);
    }

    if (index != 0) {
      final minX = points[index - 1].x + 1;
      if (index < points.length - 1) {
        final maxX = points[index + 1].x - 1;
        p.x = newTimeMs.clamp(minX, maxX).toDouble();
      } else {
        p.x = newTimeMs < minX ? minX : newTimeMs;
      }
    }

    const verticalPadding = 12.0;
    final laneHeight =
        _automationActiveLaneHeight ?? _masterAutomationLaneHeight;
    final usableHeight = laneHeight - verticalPadding * 2;
    final effectiveFingerY = pos.dy - (_automationFingerOffsetY ?? 0.0);
    final displayNormalized =
        1 - ((effectiveFingerY - verticalPadding) / usableHeight);
    p.volume = formatter.storedNormalizedForDisplayNormalized(
      displayNormalized.clamp(0.0, 1.0).toDouble(),
    );

    widget.setAutomationPointsForTarget(row, normalizedTargetId, points);
    setState(() {});
  }

  void _masterAutomationPanEnd(String targetId) {
    if (_interactionMode != 'automation' || _rowCount <= 0) return;
    final normalizedTargetId = _resolveAutomationTargetIdFromTargets(
      _automationTargetsForMasterLane(),
      targetId,
    );
    const row = 0;
    final before = _automationBefore;
    final after = widget.getAutomationPointsForTarget(row, normalizedTargetId);
    if (before != null && normalizedTargetId.trim().isNotEmpty) {
      final copiedAfter = after.map((p) => p.copy()).toList(growable: false);
      widget.onAutomationTargetCommit?.call(
        row,
        normalizedTargetId,
        before,
        copiedAfter,
      );
    }

    _automationBefore = null;
    setState(() {
      _automationDragRow = null;
      _automationDragIndex = null;
      _interactionMode = '';
      _isUserInteracting = false;
      _automationFingerOffsetY = null;
      _automationActiveLaneHeight = null;
    });
  }

  void _automationPanUpdate(int row, Offset pos) {
    if (_interactionMode != 'automation') return;
    if (_automationDragIndex == null) return;
    if (!_isAutomationLaneTabForRow(row)) return;
    final targetId = _activeAutomationTargetIdForRow(row);
    final formatter = _automationValueFormatterForTarget(row, targetId);

    final points = List<AutomationPoint>.from(
      _activeAutomationPointsForRow(row),
    );
    final p = points[_automationDragIndex!];

    // ===== 1. Convert finger X → absolute timeMs =====
    final fingerX = pos.dx;
    double newTimeMs = (fingerX / _pixelsPerMs) + _scrollOffsetMs;
    if (_magnetEnabled) {
      // quantize to a bar marker first, and then to a clip start/end
      newTimeMs = _quantizeMs(newTimeMs);
      final clipBoundary = _nearestClipBoundaryMs(row, newTimeMs);
      if (clipBoundary != null) {
        newTimeMs = clipBoundary;
      }
    }

    // ===== 2. Constrain so points cannot pass neighbors =====
    if (_automationDragIndex != 0) {
      final minX = points[_automationDragIndex! - 1].x + 1;

      if (_automationDragIndex! < points.length - 1) {
        // has right neighbor → clamp both sides
        final maxX = points[_automationDragIndex! + 1].x - 1;
        p.x = newTimeMs.clamp(minX, maxX);
      } else {
        // last point → clamp only left side
        p.x = newTimeMs < minX ? minX : newTimeMs;
      }
    }

    // ===== 2. Convert finger Y → volume (lane-local coords) =====
    const verticalPadding = 12.0;
    final laneHeight = _automationActiveLaneHeight ?? kExpandedRowHeight;
    final usableHeight = laneHeight - verticalPadding * 2;

    // compensate for initial finger offset so there is NO jump
    final effectiveFingerY = pos.dy - (_automationFingerOffsetY ?? 0.0);

    // map finger Y → volume
    final displayNormalized =
        1 - ((effectiveFingerY - verticalPadding) / usableHeight);
    p.volume = formatter.storedNormalizedForDisplayNormalized(
      displayNormalized.clamp(0.0, 1.0).toDouble(),
    );

    if (_magnetEnabled && targetId == 'volume') {
      if ((p.volume - 0.75).abs() < 0.03) {
        // small epsilon
        p.volume = 0.75;
      }
    }

    // Save
    _setActiveAutomationPointsForRow(row, targetId, points);
    setState(() {});
  }

  void _automationPanEnd(int row) {
    if (_interactionMode == 'automation') {
      final targetId = _activeAutomationTargetIdForRow(row);
      final before = _automationBefore;
      final after = _activeAutomationPointsForRow(row);
      if (before != null) {
        final copiedAfter = after.map((p) => p.copy()).toList(growable: false);
        if (targetId == 'volume') {
          if (widget.onAutomationCommit != null) {
            widget.onAutomationCommit!(row, before, copiedAfter);
          }
        } else if (widget.onAutomationTargetCommit != null) {
          widget.onAutomationTargetCommit!(row, targetId, before, copiedAfter);
        }
      }

      _automationBefore = null;
      setState(() {
        _automationDragRow = null;
        _automationDragIndex = null;
        _interactionMode = '';
        _isUserInteracting = false;
        _automationFingerOffsetY = null;
        _automationActiveLaneHeight = null;
      });
    }
  }

  void _cancelAutomationPointInteraction() {
    if (_interactionMode != 'automation') return;
    setState(() {
      _automationBefore = null;
      _automationDragRow = null;
      _automationDragIndex = null;
      _interactionMode = '';
      _isUserInteracting = false;
      _automationFingerOffsetY = null;
      _automationActiveLaneHeight = null;
    });
  }

  void _automationLaneBackgroundPanStart() {
    if (PlatformCapabilities.current.isDesktop) {
      return;
    }
    if (_interactionMode == 'automation' || _hasActiveAutomationClipDrag) {
      return;
    }
    _clearPastePopup();
    setState(() {
      _isUserInteracting = true;
      _interactionMode = 'pan';
      _initialPixelsPerMs = _pixelsPerMs;
      _initialScrollMs = _scrollOffsetMs;
    });
  }

  void _automationLaneBackgroundPanUpdate(double deltaDx) {
    if (PlatformCapabilities.current.isDesktop) return;
    if (_interactionMode != 'pan') return;
    setState(() {
      _scrollOffsetMs -= deltaDx / _pixelsPerMs;
      _clampScroll();
    });
  }

  void _automationLaneBackgroundPanEnd() {
    if (PlatformCapabilities.current.isDesktop) return;
    if (_interactionMode != 'pan') return;
    final playheadPx = _getPlayheadPx(context);
    widget.onScrubRequested(_scrollOffsetMs + playheadPx / _pixelsPerMs);
    setState(() {
      _isUserInteracting = false;
      _interactionMode = '';
      _initialPixelsPerMs = null;
      _initialScrollMs = null;
    });
  }

  Widget _buildInlineClipSheet(Widget child) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: _timelineGlassPopupDecoration(radius: 24),
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontFamily: 'Pretendard'),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _timelineGlassPopupDecoration({
    double radius = 18,
    bool strong = false,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: strong
            ? const [
                Color.fromRGBO(58, 64, 74, 0.96),
                Color.fromRGBO(35, 41, 50, 0.98),
                Color.fromRGBO(24, 29, 36, 0.98),
              ]
            : const [
                Color.fromRGBO(52, 58, 68, 0.92),
                Color.fromRGBO(31, 37, 46, 0.94),
                Color.fromRGBO(24, 29, 36, 0.95),
              ],
        stops: const [0.0, 0.46, 1.0],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withValues(alpha: strong ? 0.11 : 0.10),
        strokeAlign: BorderSide.strokeAlignInside,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: strong ? 0.32 : 0.26),
          blurRadius: strong ? 30 : 24,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }

  Color _clipControlAccent() => const Color(0xFF8A919D);

  Color _clipControlInactiveTrack() => const Color(0xFF444B56);

  Color _clipControlThumb() => const Color(0xFFE4E7EC);

  bool _isStretchToolForClip(AudioTrack clip) {
    return _activeTool == _TimelineTool.stretch && !clip.isMidi;
  }

  Widget _buildInlineClipSection({
    required String title,
    String? subtitle,
    required Widget child,
    bool compact = false,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 9 : 12,
        compact ? 8 : 11,
        compact ? 9 : 12,
        compact ? 9 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
              if (trailing != null) ...[
                SizedBox(width: compact ? 8 : 10),
                trailing,
              ],
            ],
          ),
          if (subtitle != null) ...[
            SizedBox(height: compact ? 1.5 : 3),
            Padding(
              padding: EdgeInsets.only(right: trailing == null ? 0 : 84),
              child: Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.64),
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          SizedBox(height: compact ? 6 : 10),
          child,
        ],
      ),
    );
  }

  Widget _buildInlineClipHeaderAction({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Ink(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, size: 16, color: color.withValues(alpha: 0.9)),
        ),
      ),
    );
  }

  Widget _buildInlineClipModeOption({
    required String label,
    required bool selected,
    required Color selectedColor,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.all(2),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 6,
            vertical: compact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? selectedColor.withValues(alpha: 0.26)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    strokeAlign: BorderSide.strokeAlignInside,
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            strutStyle: StrutStyle(
              fontSize: compact ? 10 : 11,
              height: 1.18,
              forceStrutHeight: true,
            ),
            style: TextStyle(
              color: selected
                  ? const Color(0xFFF2F3F5)
                  : Colors.white.withValues(alpha: 0.68),
              fontSize: compact ? 10 : 11,
              height: 1.18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineClipActionPill({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color color = Colors.white,
    bool compact = false,
  }) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 9 : 12,
              vertical: compact ? 7 : 10,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: compact ? 12 : 14,
                  color: color.withValues(alpha: 0.9),
                ),
                SizedBox(width: compact ? 5 : 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.92),
                    fontSize: compact ? 10.5 : 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactNormalizeToggle({
    required bool enabled,
    required bool compact,
    required Future<void> Function()? onTap,
  }) {
    final activeColor = const Color(0xFFD7DBE2);
    final color = enabled
        ? const Color(0xFFF4F5F7)
        : Colors.white.withValues(alpha: 0.74);
    return Semantics(
      button: true,
      toggled: enabled,
      label: L10n.translate(context, 'Normalize'),
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1.0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap == null ? null : () => unawaited(onTap()),
            borderRadius: BorderRadius.circular(999),
            child: Ink(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: compact ? 5 : 6,
              ),
              decoration: BoxDecoration(
                color: enabled
                    ? activeColor.withValues(alpha: 0.34)
                    : Colors.white.withValues(alpha: 0.075),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: enabled
                      ? Colors.white.withValues(alpha: 0.42)
                      : Colors.white.withValues(alpha: 0.15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    enabled
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_rounded,
                    size: compact ? 18 : 20,
                    color: color,
                  ),
                  SizedBox(width: compact ? 4 : 5),
                  Text(
                    L10n.translate(context, 'Normalize'),
                    style: TextStyle(
                      color: color,
                      fontSize: compact ? 10 : 10.8,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _showTimelineNameInputDialog({
    required String title,
    required String initialName,
    required String hintText,
    int maxLength = 48,
  }) async {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.26),
      builder: (_) => _TimelineNameInputDialog(
        title: title,
        initialName: initialName,
        hintText: hintText,
        maxLength: maxLength,
      ),
    );
  }

  void _openClipSettingsPanel(int clipIndex) {
    if (clipIndex < 0 || clipIndex >= widget.clips.length) return;
    setState(() {
      if (_inlineClipControlKind == _InlineClipControlKind.settings &&
          _inlineClipControlIndex == clipIndex) {
        _commitInlineClipControlIfNeeded();
        _clearInlineClipControlState();
        return;
      }
      _commitInlineClipControlIfNeeded();
      _clearInlineClipControlState();
      // The editor replaces the quick-action strip. Keeping the selection
      // active would render both controls over the same mobile region.
      _clearClipSelection();
      _inlineClipControlIndex = clipIndex;
      _inlineClipControlKind = _InlineClipControlKind.settings;
      _inlineClipGainStart = widget.clips[clipIndex].gain.clamp(0.0, 3.0);
      _inlineClipPitchStart = widget.clips[clipIndex].pitchSemitones.clamp(
        -12.0,
        12.0,
      );
    });
  }

  Widget _buildInlineClipControlOverlay(
    double viewportWidth,
    double viewportHeight,
  ) {
    final clipIndex = _inlineClipControlIndex;
    final kind = _inlineClipControlKind;
    if (clipIndex == null ||
        kind == null ||
        clipIndex < 0 ||
        clipIndex >= widget.clips.length) {
      return const SizedBox.shrink();
    }
    if (kind != _InlineClipControlKind.settings) {
      return const SizedBox.shrink();
    }

    final clip = widget.clips[clipIndex];
    final rect = _getClipRect(clipIndex);
    if (rect == null) return const SizedBox.shrink();

    if (viewportWidth <= 20 || viewportHeight <= 20) {
      return const SizedBox.shrink();
    }

    final isMidi = clip.isMidi;
    final availableWidth = math.max(80.0, viewportWidth - 12.0);
    final cardWidth = math.min(360.0, availableWidth);
    final compactSheet = cardWidth <= 332.0 || viewportWidth <= 390.0;
    final estimatedPanelHeight = isMidi
        ? (compactSheet ? 164.0 : 184.0)
        : (compactSheet ? 248.0 : 284.0);
    final maxPanelHeight = math.max(160.0, viewportHeight - 12.0);
    final panelHeight = math.min(estimatedPanelHeight, maxPanelHeight);

    final minLeft = _headerWidth + 6.0;
    final maxLeft = math.max(
      minLeft,
      _headerWidth + viewportWidth - cardWidth - 6.0,
    );
    final anchorX = _headerWidth + rect.left + (rect.width / 2);
    final left = (anchorX - (cardWidth / 2)).clamp(minLeft, maxLeft).toDouble();

    final minTop = _verticalScrollOffset + 6.0;
    final maxTop = math.max(
      minTop,
      (_verticalScrollOffset + viewportHeight - panelHeight - 8.0).toDouble(),
    );
    final preferredBelow = rect.bottom + 8.0;
    final preferredAbove = rect.top - panelHeight - 8.0;
    final fitsBelow = preferredBelow >= minTop && preferredBelow <= maxTop;
    final fitsAbove = preferredAbove >= minTop && preferredAbove <= maxTop;
    final availableBelow = (maxTop - preferredBelow).abs();
    final availableAbove = (preferredAbove - minTop).abs();
    final double topCandidate;
    if (fitsAbove && !fitsBelow) {
      topCandidate = preferredAbove;
    } else if (fitsBelow && !fitsAbove) {
      topCandidate = preferredBelow;
    } else if (fitsAbove && fitsBelow) {
      topCandidate = availableAbove >= availableBelow
          ? preferredAbove
          : preferredBelow;
    } else {
      topCandidate = preferredAbove;
    }

    final top = topCandidate
        .clamp(minTop, maxTop > minTop ? maxTop : minTop)
        .toDouble();

    final accentColor = _clipControlAccent();
    final inactiveTrackColor = _clipControlInactiveTrack();
    final thumbColor = _clipControlThumb();
    final clipName = clip.label.trim().isNotEmpty
        ? clip.label.trim()
        : (clip.isMidi
              ? L10n.translate(context, 'MIDI Clip')
              : L10n.translate(context, 'Audio Clip'));

    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compactSheet ? 20 : 24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            constraints: BoxConstraints(maxHeight: panelHeight),
            padding: EdgeInsets.fromLTRB(
              compactSheet ? 10 : 12,
              compactSheet ? 10 : 12,
              compactSheet ? 10 : 12,
              compactSheet ? 10 : 12,
            ),
            decoration: _timelineGlassPopupDecoration(
              radius: compactSheet ? 20 : 24,
              strong: true,
            ),
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'Pretendard'),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            clipName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compactSheet ? 16 : 17,
                              fontWeight: FontWeight.w700,
                              height: 1.12,
                            ),
                          ),
                        ),
                        SizedBox(width: compactSheet ? 8 : 10),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildInlineClipHeaderAction(
                              icon: Icons.drive_file_rename_outline_rounded,
                              onTap: () => _openClipRenameDialog(clipIndex),
                            ),
                            const SizedBox(width: 6),
                            _buildInlineClipHeaderAction(
                              icon: Icons.close_rounded,
                              onTap: _closeInlineClipControl,
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: compactSheet ? 8 : 14),
                    _buildInlineClipSection(
                      title: L10n.translate(context, 'Tone'),
                      subtitle: compactSheet
                          ? null
                          : L10n.translate(
                              context,
                              'Quick level and pitch adjustments',
                            ),
                      compact: compactSheet,
                      trailing: !isMidi
                          ? _buildCompactNormalizeToggle(
                              enabled: clip.normalizeVolume,
                              compact: compactSheet,
                              onTap: widget.onToggleClipNormalize == null
                                  ? null
                                  : () async {
                                      await widget.onToggleClipNormalize!(
                                        clipIndex,
                                        !clip.normalizeVolume,
                                      );
                                      if (mounted) setState(() {});
                                    },
                            )
                          : null,
                      child: Column(
                        children: [
                          PrettyGainSlider(
                            value: clip.gain.clamp(0.0, 3.0),
                            trackColor: accentColor,
                            inactiveTrackColor: inactiveTrackColor,
                            thumbColor: thumbColor,
                            onChangeStart: (_) {},
                            onChanged: (v) {
                              final next = v.clamp(0.0, 3.0);
                              clip.gain = next;
                              unawaited(widget.setClipGain(clipIndex, next));
                              if (mounted) setState(() {});
                            },
                            onChangeEnd: (_) {},
                          ),
                          SizedBox(height: compactSheet ? 6 : 10),
                          Row(
                            children: [
                              Text(
                                L10n.translate(context, 'Pitch'),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compactSheet ? 12 : 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${clip.pitchSemitones >= 0 ? '+' : ''}${clip.pitchSemitones.toStringAsFixed(1)}st',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: compactSheet ? 11 : 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compactSheet ? 4 : 6),
                          Row(
                            children: [
                              SizedBox(
                                width: compactSheet ? 22 : 24,
                                height: compactSheet ? 22 : 24,
                                child: Material(
                                  color: Colors.transparent,
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(7),
                                      color: Colors.white.withValues(
                                        alpha: 0.07,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.10,
                                        ),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(7),
                                      splashColor: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      highlightColor: Colors.white.withValues(
                                        alpha: 0.05,
                                      ),
                                      onTap: () {
                                        final next = (clip.pitchSemitones - 0.5)
                                            .clamp(-12.0, 12.0);
                                        clip.pitchSemitones = next;
                                        unawaited(
                                          widget.setClipPitch(clipIndex, next),
                                        );
                                        if (mounted) setState(() {});
                                      },
                                      child: Icon(
                                        Icons.remove_rounded,
                                        size: compactSheet ? 13 : 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: compactSheet ? 6 : 8),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 5,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 11,
                                    ),
                                    overlayShape:
                                        SliderComponentShape.noOverlay,
                                    activeTrackColor: accentColor,
                                    inactiveTrackColor: inactiveTrackColor,
                                    thumbColor: thumbColor,
                                  ),
                                  child: DesktopScrollableSlider(
                                    value: clip.pitchSemitones.clamp(
                                      -12.0,
                                      12.0,
                                    ),
                                    min: -12.0,
                                    max: 12.0,
                                    divisions: 48,
                                    label:
                                        '${clip.pitchSemitones >= 0 ? '+' : ''}${clip.pitchSemitones.toStringAsFixed(1)}st',
                                    onChanged: (v) {
                                      final next = v.clamp(-12.0, 12.0);
                                      clip.pitchSemitones = next;
                                      unawaited(
                                        widget.setClipPitch(clipIndex, next),
                                      );
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                ),
                              ),
                              SizedBox(width: compactSheet ? 6 : 8),
                              SizedBox(
                                width: compactSheet ? 22 : 24,
                                height: compactSheet ? 22 : 24,
                                child: Material(
                                  color: Colors.transparent,
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(7),
                                      color: Colors.white.withValues(
                                        alpha: 0.07,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.10,
                                        ),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(7),
                                      splashColor: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      highlightColor: Colors.white.withValues(
                                        alpha: 0.05,
                                      ),
                                      onTap: () {
                                        final next = (clip.pitchSemitones + 0.5)
                                            .clamp(-12.0, 12.0);
                                        clip.pitchSemitones = next;
                                        unawaited(
                                          widget.setClipPitch(clipIndex, next),
                                        );
                                        if (mounted) setState(() {});
                                      },
                                      child: Icon(
                                        Icons.add_rounded,
                                        size: compactSheet ? 13 : 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isMidi) ...[
                      SizedBox(height: compactSheet ? 6 : 10),
                      _buildInlineClipSection(
                        title: L10n.translate(context, 'Tempo'),
                        subtitle: compactSheet
                            ? L10n.translate(context, 'Follows project BPM.')
                            : L10n.translate(
                                context,
                                'MIDI clips follow project BPM automatically.',
                              ),
                        compact: compactSheet,
                        child: Text(
                          L10n.translate(
                            context,
                            'No extra tempo mode is needed here.',
                          ),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: compactSheet ? 10 : 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ] else ...[
                      SizedBox(height: compactSheet ? 6 : 10),
                      _buildInlineClipSection(
                        title: L10n.translate(context, 'Tempo'),
                        subtitle: compactSheet
                            ? null
                            : L10n.translate(
                                context,
                                'Choose how this audio clip follows project BPM',
                              ),
                        compact: compactSheet,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: compactSheet ? 36 : 42,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.045),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _buildInlineClipModeOption(
                                    label: L10n.translate(context, 'Off'),
                                    selected: !clip.stretchToProjectTempo,
                                    selectedColor: const Color(0xFF8A919D),
                                    compact: compactSheet,
                                    onTap: () async {
                                      await widget.onDisableClipTempoFollow(
                                        clipIndex,
                                      );
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                  _buildInlineClipModeOption(
                                    label: L10n.translate(context, 'Resample'),
                                    selected:
                                        clip.stretchToProjectTempo &&
                                        !clip.tempoStretchPreservePitch,
                                    selectedColor: const Color(0xFF8A919D),
                                    compact: compactSheet,
                                    onTap: () async {
                                      await widget.onAdjustClipToTempo(
                                        clipIndex,
                                      );
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                  _buildInlineClipModeOption(
                                    label: L10n.translate(context, 'Stretch'),
                                    selected:
                                        clip.stretchToProjectTempo &&
                                        clip.tempoStretchPreservePitch,
                                    selectedColor: const Color(0xFF8A919D),
                                    compact: compactSheet,
                                    onTap: () async {
                                      await widget
                                          .onStretchClipToTempoPreservePitch(
                                            clipIndex,
                                          );
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: compactSheet ? 6 : 10),
                            Wrap(
                              spacing: compactSheet ? 5 : 8,
                              runSpacing: compactSheet ? 5 : 8,
                              children: [
                                _buildInlineClipActionPill(
                                  icon: Icons.swap_horiz_rounded,
                                  label: clip.isReversed
                                      ? L10n.translate(context, 'Reversed')
                                      : L10n.translate(context, 'Reverse'),
                                  color: clip.isReversed
                                      ? const Color(0xFFD7DBE2)
                                      : Colors.white,
                                  compact: compactSheet,
                                  onTap: widget.onSetClipReversed == null
                                      ? null
                                      : () async {
                                          await widget.onSetClipReversed!(
                                            clipIndex,
                                            !clip.isReversed,
                                          );
                                          if (mounted) setState(() {});
                                        },
                                ),
                                _buildInlineClipActionPill(
                                  icon: Icons.auto_fix_high_rounded,
                                  label: L10n.translate(context, 'Set BPM'),
                                  compact: compactSheet,
                                  onTap: () async {
                                    await widget
                                        .onDetectClipTempoAndSetProjectTempo(
                                          clipIndex,
                                        );
                                    if (mounted) setState(() {});
                                  },
                                ),
                                if (widget.onOpenPitchLab != null)
                                  _buildInlineClipActionPill(
                                    icon: Icons.graphic_eq_rounded,
                                    label: L10n.translate(context, 'Pitch Lab'),
                                    color: const Color(0xFF8BE7C8),
                                    compact: compactSheet,
                                    onTap: () async {
                                      _closeInlineClipControl();
                                      await widget.onOpenPitchLab!(clipIndex);
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                if (widget.onStemSeparation != null)
                                  _buildInlineClipActionPill(
                                    icon: Icons.library_music_outlined,
                                    label: L10n.translate(
                                      context,
                                      'Split vocals',
                                    ),
                                    compact: compactSheet,
                                    onTap: () async {
                                      await widget.onStemSeparation!(clipIndex);
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                if (widget.onCreateSamplerFromClip != null)
                                  _buildInlineClipActionPill(
                                    icon: Icons.keyboard_alt_outlined,
                                    label: L10n.translate(context, 'Sampler'),
                                    color: const Color(0xFFD7DBE2),
                                    compact: compactSheet,
                                    onTap: () async {
                                      _closeInlineClipControl();
                                      await widget.onCreateSamplerFromClip!(
                                        clipIndex,
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openClipRenameDialog(int clipIndex) async {
    if (clipIndex < 0 || clipIndex >= widget.clips.length) return;
    final clip = widget.clips[clipIndex];
    // Seed rename with the exact stored label so valid percent sequences in a
    // user-provided name are not silently normalized and then persisted.
    final initialName = clip.label.trim().isNotEmpty
        ? clip.label.trim()
        : (clip.isMidi
              ? L10n.translate(context, 'MIDI Clip')
              : L10n.translate(context, 'Audio Clip'));
    final nextName = await _showTimelineNameInputDialog(
      title: L10n.translate(context, 'Rename Clip'),
      initialName: initialName,
      hintText: L10n.translate(context, 'Clip name'),
      maxLength: 48,
    );

    if (!mounted || nextName == null || nextName.isEmpty) return;
    if (nextName == clip.label) return;

    if (widget.onRenameClip != null) {
      await widget.onRenameClip!(clipIndex, nextName);
    } else {
      clip.label = nextName;
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openClipTempoActionsSheet(int clipIndex) async {
    if (clipIndex < 0 || clipIndex >= widget.clips.length) return;
    final clip = widget.clips[clipIndex];
    if (clip.isMidi) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.translate(context, 'Tempo detection is only for audio clips.'),
          ),
        ),
      );
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      barrierColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) {
        return _buildInlineClipSheet(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.speed_rounded, color: Colors.white),
                title: Text(
                  L10n.translate(ctx, 'Adjust To Tempo (Resample)'),
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, 'adjust_resample'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.drag_indicator,
                  color: Color(0xFF2AAE9F),
                ),
                title: Text(
                  L10n.translate(ctx, 'Stretch To Tempo (Keep Pitch)'),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  L10n.translate(
                    ctx,
                    'Stretch mode is shown with teal clip handles.',
                  ),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'adjust_stretch'),
              ),
              ListTile(
                leading: const Icon(Icons.auto_fix_high, color: Colors.white),
                title: Text(
                  L10n.translate(ctx, 'Detect / Enter BPM'),
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, 'detect'),
              ),
            ],
          ),
        );
      },
    );

    if (action == null) return;
    if (action == 'adjust_resample') {
      await widget.onAdjustClipToTempo(clipIndex);
      return;
    }
    if (action == 'adjust_stretch') {
      await widget.onStretchClipToTempoPreservePitch(clipIndex);
      return;
    }
    if (action == 'detect') {
      await widget.onDetectClipTempoAndSetProjectTempo(clipIndex);
    }
  }

  Widget _buildClipPopupAction({
    Key? key,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    String? tooltip,
  }) {
    final enabled = onTap != null;
    final iconColor = enabled ? color : color.withOpacity(0.45);
    final action = Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(child: Icon(icon, size: 18, color: iconColor)),
      ),
    );
    if (tooltip == null || tooltip.trim().isEmpty) {
      return action;
    }
    return Tooltip(message: tooltip, child: action);
  }

  double _contentYToTimelineViewportY(double contentY) {
    return contentY - _verticalScrollOffset;
  }

  Widget _buildAutomationClipMenuOverlay(
    double viewportWidth,
    double viewportHeight,
    List<_TimelineAutomationClipVisual> visuals,
  ) {
    final visual = _currentAutomationClipMenuVisual(visuals);
    if (visual == null) {
      return const SizedBox.shrink();
    }

    final clipInTimelineX =
        visual.rect.right >= 0 && visual.rect.left <= viewportWidth;
    final clipInTimelineY =
        visual.rect.bottom >= _verticalScrollOffset &&
        visual.rect.top <= _verticalScrollOffset + viewportHeight;
    if (!clipInTimelineX || !clipInTimelineY) {
      return const SizedBox.shrink();
    }

    final actionCount = 4 + (visual.clip.patternId.trim().isNotEmpty ? 1 : 0);
    final popupWidth = math
        .min(viewportWidth - 8.0, (actionCount * 84.0) + 8.0)
        .clamp(280.0, 440.0)
        .toDouble();
    const double popupHeight = 38.0;
    final anchorPx = visual.rect.left + (visual.rect.width / 2.0);
    final minLeft = _headerWidth + 4.0;
    final maxLeft = math.max(
      minLeft,
      _headerWidth + viewportWidth - popupWidth - 4.0,
    );
    final left = (_headerWidth + anchorPx - (popupWidth / 2.0))
        .clamp(minLeft, maxLeft)
        .toDouble();
    const double minTop = 2.0;
    final maxTop = math.max(minTop, viewportHeight - popupHeight - 2.0);
    final visibleTop = _contentYToTimelineViewportY(visual.rect.top);
    final visibleBottom = _contentYToTimelineViewportY(visual.rect.bottom);
    final preferredAbove = visibleTop - popupHeight - 4.0;
    final preferredBelow = visibleBottom + 4.0;
    final top = preferredAbove >= minTop
        ? preferredAbove
        : (preferredBelow <= maxTop
              ? preferredBelow
              : preferredAbove.clamp(minTop, maxTop).toDouble());

    Widget menuAction({
      required Key key,
      required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final actionChildren = <Widget>[
      menuAction(
        key: const ValueKey('automation_clip_menu_reveal'),
        icon: Icons.tune_rounded,
        label: L10n.translate(context, 'Open param'),
        color: Colors.white,
        onTap: () {
          unawaited(_handleAutomationClipMenuAction('reveal', visual));
        },
      ),
      Container(width: 1, height: 16, color: Colors.white24),
      menuAction(
        key: const ValueKey('automation_clip_menu_open'),
        icon: Icons.auto_graph_rounded,
        label: L10n.translate(context, 'Edit points'),
        color: Colors.white,
        onTap: () {
          unawaited(_handleAutomationClipMenuAction('open', visual));
        },
      ),
      Container(width: 1, height: 16, color: Colors.white24),
      menuAction(
        key: const ValueKey('automation_clip_menu_copy'),
        icon: Icons.content_copy_rounded,
        label: L10n.translate(context, 'Clone'),
        color: Colors.white,
        onTap: () {
          unawaited(_handleAutomationClipMenuAction('copy', visual));
        },
      ),
    ];
    if (visual.clip.patternId.trim().isNotEmpty) {
      actionChildren.addAll(<Widget>[
        Container(width: 1, height: 16, color: Colors.white24),
        menuAction(
          key: const ValueKey('automation_clip_menu_make_unique'),
          icon: Icons.link_off_rounded,
          label: L10n.translate(context, 'Make unique'),
          color: const Color(0xFFFFD28F),
          onTap: () {
            unawaited(_handleAutomationClipMenuAction('make_unique', visual));
          },
        ),
      ]);
    }
    actionChildren.addAll(<Widget>[
      Container(width: 1, height: 16, color: Colors.white24),
      menuAction(
        key: const ValueKey('automation_clip_menu_delete'),
        icon: Icons.delete_outline,
        label: L10n.translate(context, 'Delete'),
        color: const Color(0xFFFFA4A4),
        onTap: () {
          unawaited(_handleAutomationClipMenuAction('delete', visual));
        },
      ),
    ]);

    return Positioned(
      left: left,
      top: top,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: popupWidth,
            height: popupHeight,
            decoration: _timelineGlassPopupDecoration(radius: 18).copyWith(
              border: Border.all(
                color: visual.isOrphan
                    ? const Color(0x66FF9A9A)
                    : Colors.white.withValues(alpha: 0.16),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'Pretendard'),
              child: Row(children: actionChildren),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAutomationClipTestOverlay(
    double viewportWidth,
    double viewportHeight,
    List<_TimelineAutomationClipVisual> visuals,
  ) {
    final children = <Widget>[];
    for (final visual in visuals) {
      final rect = visual.rect;
      if (rect.right <= 0 ||
          rect.left >= viewportWidth ||
          rect.bottom <= _verticalScrollOffset ||
          rect.top >= _verticalScrollOffset + viewportHeight) {
        continue;
      }
      children.add(
        Positioned(
          key: ValueKey('automation_clip_hit_${visual.clip.id}'),
          left: _headerWidth + rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.transparent),
            ),
          ),
        ),
      );
    }
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Stack(children: children);
  }

  bool _canCutSelectedClipAtPlayhead(int clipIndex) {
    if (widget.onCutClipAt == null) return false;
    if (clipIndex < 0 || clipIndex >= widget.clips.length) return false;
    final clip = widget.clips[clipIndex];
    if (clip.isMidi) return false;

    final startMs = widget.getStartMs(clip);
    final timelineDurationMs = widget.getTimelineDurationMs(clip);
    if (!startMs.isFinite ||
        !timelineDurationMs.isFinite ||
        timelineDurationMs <= 1.0) {
      return false;
    }

    final cutTimeMs = _currentPlayheadMs;
    final endMs = startMs + timelineDurationMs;
    if (cutTimeMs <= startMs + 1.0 || cutTimeMs >= endMs - 1.0) {
      return false;
    }

    final trimStartMs = widget.getTrimStartMs(clip);
    final trimEndMs = widget.getTrimEndMs(clip);
    final rawSpanMs = trimEndMs - trimStartMs;
    if (!rawSpanMs.isFinite || rawSpanMs <= 1.0) return false;

    final ratio = ((cutTimeMs - startMs) / timelineDurationMs).clamp(0.0, 1.0);
    final cutTrimMs = trimStartMs + rawSpanMs * ratio;
    const minTrimGapMs = 50.0;
    return cutTrimMs - trimStartMs >= minTrimGapMs &&
        trimEndMs - cutTrimMs >= minTrimGapMs;
  }

  Widget _buildSelectedClipPopup(double viewportWidth, double viewportHeight) {
    final selectedIndices = _activeSelectedClipIndices();
    final hasSingleSelection = selectedIndices.length == 1;
    final singleSelectionIndex = hasSingleSelection
        ? selectedIndices.first
        : _selectedClipIndex;
    final canSplitAtPlayhead =
        hasSingleSelection &&
        _canCutSelectedClipAtPlayhead(singleSelectionIndex);
    final canGlueSelection =
        selectedIndices.length >= 2 && widget.onGlueClips != null;
    final canCreateSampler =
        hasSingleSelection &&
        widget.onCreateSamplerFromClip != null &&
        singleSelectionIndex >= 0 &&
        singleSelectionIndex < widget.clips.length &&
        !widget.clips[singleSelectionIndex].isMidi;
    final canOpenPitchLab =
        hasSingleSelection &&
        widget.onOpenPitchLab != null &&
        singleSelectionIndex >= 0 &&
        singleSelectionIndex < widget.clips.length &&
        !widget.clips[singleSelectionIndex].isMidi;
    final canOpenMidiPianoRoll =
        hasSingleSelection &&
        widget.onOpenMidiClip != null &&
        singleSelectionIndex >= 0 &&
        singleSelectionIndex < widget.clips.length &&
        widget.clips[singleSelectionIndex].isMidi;
    final canReplaceSamplerSource =
        hasSingleSelection &&
        widget.onReplaceSamplerSource != null &&
        singleSelectionIndex >= 0 &&
        singleSelectionIndex < widget.clips.length &&
        widget.clips[singleSelectionIndex].isMidi &&
        (widget.canReplaceSamplerSource?.call(singleSelectionIndex) ?? false);
    final canOpenMidiInstrumentUi =
        hasSingleSelection &&
        widget.onOpenMidiInstrumentUi != null &&
        singleSelectionIndex >= 0 &&
        singleSelectionIndex < widget.clips.length &&
        widget.clips[singleSelectionIndex].isMidi &&
        (widget.canOpenMidiInstrumentUi?.call(singleSelectionIndex) ?? false);
    Rect? selectionRect;
    for (final index in selectedIndices) {
      final rect = _getClipRect(index);
      if (rect == null) continue;
      selectionRect = selectionRect?.expandToInclude(rect) ?? rect;
    }
    final bool visible =
        _inlineClipControlKind == null &&
        selectionRect != null &&
        selectedIndices.isNotEmpty &&
        !_isUserInteracting &&
        !_selectionBoxActive;
    const double popupActionWidth = 42.0;
    final int popupActionCount =
        (hasSingleSelection ? (canSplitAtPlayhead ? 5 : 4) : 3) +
        (canGlueSelection ? 1 : 0) +
        (canOpenPitchLab ? 1 : 0) +
        (canCreateSampler ? 1 : 0) +
        (canOpenMidiPianoRoll ? 1 : 0) +
        (canReplaceSamplerSource ? 1 : 0) +
        (canOpenMidiInstrumentUi ? 1 : 0);
    final double popupWidth = math.min(
      popupActionCount * popupActionWidth,
      math.max(84.0, viewportWidth - 8),
    );
    const double popupHeight = 36;
    double left = _headerWidth;
    double top = -100;

    if (visible) {
      final clipInTimelineX =
          selectionRect.right >= 0 && selectionRect.left <= viewportWidth;
      final clipInTimelineY =
          selectionRect.bottom >= _verticalScrollOffset &&
          selectionRect.top <= _verticalScrollOffset + viewportHeight;
      if (clipInTimelineX && clipInTimelineY) {
        final visibleClipLeft = selectionRect.left.clamp(0.0, viewportWidth);
        final visibleClipRight = selectionRect.right.clamp(0.0, viewportWidth);
        final hasVisibleClipSpan = visibleClipRight > visibleClipLeft + 1.0;
        final tapAnchorPx = _clipPopupMs == null
            ? double.nan
            : (_clipPopupMs! - _scrollOffsetMs) * _pixelsPerMs;
        final minAnchorPx =
            (hasVisibleClipSpan ? visibleClipLeft : selectionRect.left) + 6.0;
        final maxAnchorPx =
            (hasVisibleClipSpan ? visibleClipRight : selectionRect.right) - 6.0;
        final anchorPx = tapAnchorPx.isFinite
            ? tapAnchorPx
                  .clamp(
                    minAnchorPx <= maxAnchorPx
                        ? minAnchorPx
                        : (hasVisibleClipSpan
                              ? visibleClipLeft
                              : selectionRect.left),
                    minAnchorPx <= maxAnchorPx
                        ? maxAnchorPx
                        : (hasVisibleClipSpan
                              ? visibleClipRight
                              : selectionRect.right),
                  )
                  .toDouble()
            : (hasVisibleClipSpan
                  ? (visibleClipLeft + visibleClipRight) / 2.0
                  : (selectionRect.left + selectionRect.width / 2));
        final minLeft = _headerWidth + 4.0;
        final maxLeft = math.max(
          minLeft,
          _headerWidth + viewportWidth - popupWidth - 4.0,
        );
        left = (_headerWidth + anchorPx - (popupWidth / 2))
            .clamp(minLeft, maxLeft)
            .toDouble();

        const double minTop = 2.0;
        final maxTop = math.max(minTop, viewportHeight - popupHeight - 2.0);
        final visibleSelectionTop = _contentYToTimelineViewportY(
          selectionRect.top,
        );
        final visibleSelectionBottom = _contentYToTimelineViewportY(
          selectionRect.bottom,
        );
        final preferredAbove = visibleSelectionTop - popupHeight - 4.0;
        final preferredBelow = visibleSelectionBottom + 4.0;
        if (preferredAbove >= minTop) {
          top = preferredAbove;
        } else if (preferredBelow <= maxTop) {
          top = preferredBelow;
        } else {
          top = preferredAbove.clamp(minTop, maxTop).toDouble();
        }
      }
    }

    final popupChildren = <Widget>[];
    if (canOpenMidiPianoRoll) {
      popupChildren.addAll(<Widget>[
        Expanded(
          child: _buildClipPopupAction(
            key: const ValueKey('selected_clip_popup_open_piano_roll'),
            icon: Icons.piano_outlined,
            color: const Color(0xFF8BE7C8),
            onTap: () {
              final openMidiClip = widget.onOpenMidiClip;
              if (openMidiClip == null) return;
              setState(_clearClipSelection);
              openMidiClip(singleSelectionIndex);
            },
            tooltip: L10n.translate(context, 'Open piano roll'),
          ),
        ),
        Container(width: 1, height: 16, color: Colors.white24),
      ]);
    }
    popupChildren.addAll(<Widget>[
      Expanded(
        child: _buildClipPopupAction(
          icon: Icons.copy,
          color: Colors.white,
          onTap: () {
            _copySelectedClips();
            if (!mounted) return;
            setState(_clearClipSelection);
          },
          tooltip: L10n.translate(context, 'Copy'),
        ),
      ),
      Container(width: 1, height: 16, color: Colors.white24),
      Expanded(
        child: _buildClipPopupAction(
          icon: Icons.content_paste,
          color: Colors.white,
          onTap: widget.hasCopiedClip ? _pasteCopiedClipsAfterSelection : null,
          tooltip: L10n.translate(context, 'Place clone'),
        ),
      ),
    ]);
    if (hasSingleSelection) {
      popupChildren.addAll(<Widget>[
        Container(width: 1, height: 16, color: Colors.white24),
        Expanded(
          child: _buildClipPopupAction(
            key: const ValueKey('selected_clip_popup_clip_settings'),
            icon: Icons.tune,
            color: Colors.white,
            onTap: () {
              final openPanel = widget.onOpenAudioClipOptionsPanel;
              if (widget.useTabletDawLayout && openPanel != null) {
                setState(_clearClipSelection);
                openPanel(singleSelectionIndex);
                return;
              }
              _openClipSettingsPanel(singleSelectionIndex);
            },
            tooltip: L10n.translate(context, 'Clip settings'),
          ),
        ),
      ]);
    }
    if (canOpenMidiInstrumentUi) {
      popupChildren.addAll(<Widget>[
        Container(width: 1, height: 16, color: Colors.white24),
        Expanded(
          child: _buildClipPopupAction(
            key: const ValueKey('selected_clip_popup_open_instrument_ui'),
            icon: Icons.open_in_new_rounded,
            color: const Color(0xFF8BE7C8),
            onTap: () async {
              final openInstrumentUi = widget.onOpenMidiInstrumentUi;
              if (openInstrumentUi == null) return;
              setState(_clearClipSelection);
              await openInstrumentUi(singleSelectionIndex);
            },
            tooltip: L10n.translate(context, 'Open synth'),
          ),
        ),
      ]);
    }
    if (canSplitAtPlayhead) {
      popupChildren.addAll(<Widget>[
        Container(width: 1, height: 16, color: Colors.white24),
        Expanded(
          child: _buildClipPopupAction(
            key: const ValueKey('selected_clip_popup_split_at_playhead'),
            icon: Icons.content_cut_rounded,
            color: Colors.white,
            onTap: () {
              final onCutClipAt = widget.onCutClipAt;
              if (onCutClipAt == null) return;
              final cutMs = _currentPlayheadMs;
              setState(_clearClipSelection);
              unawaited(onCutClipAt(singleSelectionIndex, cutMs));
            },
            tooltip: L10n.translate(context, 'Split at playhead'),
          ),
        ),
      ]);
    }
    if (canCreateSampler) {
      popupChildren.addAll(<Widget>[
        Container(width: 1, height: 16, color: Colors.white24),
        Expanded(
          child: _buildClipPopupAction(
            key: const ValueKey('selected_clip_popup_sampler'),
            icon: Icons.keyboard_alt_outlined,
            color: const Color(0xFFD7DBE2),
            onTap: () async {
              final onCreateSamplerFromClip = widget.onCreateSamplerFromClip;
              if (onCreateSamplerFromClip == null) return;
              setState(_clearClipSelection);
              await onCreateSamplerFromClip(singleSelectionIndex);
            },
            tooltip: L10n.translate(context, 'Create sampler'),
          ),
        ),
      ]);
    }
    if (canOpenPitchLab) {
      popupChildren.addAll(<Widget>[
        Container(width: 1, height: 16, color: Colors.white24),
        Expanded(
          child: _buildClipPopupAction(
            key: const ValueKey('selected_clip_popup_pitch_lab'),
            icon: Icons.graphic_eq_rounded,
            color: const Color(0xFF8BE7C8),
            onTap: () async {
              final onOpenPitchLab = widget.onOpenPitchLab;
              if (onOpenPitchLab == null) return;
              await onOpenPitchLab(singleSelectionIndex);
            },
            tooltip: L10n.translate(context, 'Pitch Lab'),
          ),
        ),
      ]);
    }
    if (canReplaceSamplerSource) {
      popupChildren.addAll(<Widget>[
        Container(width: 1, height: 16, color: Colors.white24),
        Expanded(
          child: _buildClipPopupAction(
            key: const ValueKey('selected_clip_popup_replace_sampler_source'),
            icon: Icons.find_replace_rounded,
            color: const Color(0xFFD7DBE2),
            onTap: () async {
              final onReplaceSamplerSource = widget.onReplaceSamplerSource;
              if (onReplaceSamplerSource == null) return;
              setState(_clearClipSelection);
              await onReplaceSamplerSource(singleSelectionIndex);
            },
            tooltip: L10n.translate(context, 'Replace sampler source'),
          ),
        ),
      ]);
    }
    if (canGlueSelection) {
      popupChildren.addAll(<Widget>[
        Container(width: 1, height: 16, color: Colors.white24),
        Expanded(
          child: _buildClipPopupAction(
            key: const ValueKey('selected_clip_popup_glue'),
            icon: Icons.call_merge_rounded,
            color: Colors.white,
            onTap: () async {
              final onGlueClips = widget.onGlueClips;
              if (onGlueClips == null) return;
              final glueIndices = selectedIndices.toList(growable: false);
              setState(_clearClipSelection);
              await onGlueClips(glueIndices);
            },
            tooltip: L10n.translate(context, 'Glue clips'),
          ),
        ),
      ]);
    }
    popupChildren.addAll(<Widget>[
      Container(width: 1, height: 16, color: Colors.white24),
      Expanded(
        child: _buildClipPopupAction(
          icon: Icons.delete_outline,
          color: const Color(0xFFFFA4A4),
          onTap: () async {
            if (selectedIndices.isNotEmpty) {
              await _deleteSelectedClips();
            }
          },
          tooltip: L10n.translate(context, 'Delete'),
        ),
      ),
    ]);

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        ignoring: !visible, // prevent clicks when invisible
        child: AnimatedOpacity(
          key: const ValueKey('selected_clip_popup'),
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 70),
          curve: Curves.easeOut,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: popupWidth,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                height: popupHeight,
                decoration: _timelineGlassPopupDecoration(radius: 18),
                child: Row(children: popupChildren),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPastePopup(double viewportWidth) {
    final bool visible =
        _showPastePopup && _pasteRow != null && _pasteMs != null;
    final bool showClearButton =
        widget.onClearCopiedClip != null || _automationClipClipboard != null;

    const double popupHeight = 36;
    const double actionSize = 34;
    const double separatorWidth = 1;
    const double horizontalPadding = 4;
    const double borderWidthAllowance = 2;
    final double popupWidth =
        borderWidthAllowance +
        horizontalPadding * 2 +
        actionSize * (showClearButton ? 2 : 1) +
        (showClearButton ? separatorWidth : 0);

    double left = _headerWidth;
    double top = -100; // offscreen when hidden

    if (visible) {
      if (_rowCount == 0) {
        left = _headerWidth;
        top = -100;
      } else {
        double popupAnchorMs = _pasteMs!;
        if (!_isSourceRowVisible(_pasteRow!)) {
          return const SizedBox.shrink();
        }
        if (_highlightedSegmentRow == _pasteRow &&
            _highlightedSegmentStartMs != null &&
            _highlightedSegmentEndMs != null) {
          popupAnchorMs =
              (_highlightedSegmentStartMs! + _highlightedSegmentEndMs!) / 2.0;
        }
        final double px = (popupAnchorMs - _scrollOffsetMs) * _pixelsPerMs;

        if (px >= 0 && px <= viewportWidth) {
          // Compute properly only if on screen
          final row = _pasteRow!.clamp(0, _rowCount - 1);
          final rowTop = _rowYPositions[row];

          left = _headerWidth + px - popupWidth / 2;
          left = left.clamp(
            _headerWidth,
            _headerWidth + viewportWidth - popupWidth,
          );

          top = rowTop - popupHeight - 4;
          if (top < 0) top = 0;
        } else {
          // Offscreen in X → hide visually
          left = _headerWidth;
          top = -100;
        }
      }
    }

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        ignoring: !visible, // disable interactions when hidden
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 70),
          curve: Curves.easeOut,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                key: const ValueKey('timeline_paste_popup'),
                width: popupWidth,
                height: popupHeight,
                decoration: _timelineGlassPopupDecoration(radius: 18),
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: actionSize,
                      child: _buildClipPopupAction(
                        tooltip: L10n.translate(context, 'Place clone'),
                        icon: Icons.content_paste,
                        color: Colors.white,
                        onTap: () {
                          if (_pasteRow != null && _pasteMs != null) {
                            _pasteClipboardAt(_pasteRow!, _pasteMs!);
                          }
                          _clearPastePopup();
                        },
                      ),
                    ),
                    if (showClearButton) ...[
                      Container(
                        width: separatorWidth,
                        height: 18,
                        color: Colors.white24,
                      ),
                      SizedBox.square(
                        dimension: actionSize,
                        child: _buildClipPopupAction(
                          tooltip: L10n.translate(context, 'Clear clipboard'),
                          icon: Icons.delete_outline,
                          color: const Color(0xFFFFA4A4),
                          onTap: () {
                            _clearClipboard();
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    L10n.translate(
                                      context,
                                      'Clipboard cleared',
                                    ),
                                  ),
                                  duration: Duration(milliseconds: 1200),
                                ),
                              );
                            _clearPastePopup();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstrumentLaneRegionPopup(
    double viewportWidth,
    double viewportHeight,
  ) {
    final visible =
        _showInstrumentLaneRegionPopup &&
        _instrumentLaneRegionRow != null &&
        _instrumentLaneRegionMs != null &&
        _instrumentLaneRegionAnchorLocal != null;
    const double popupHeight = 36;
    const double popupWidth = 156;

    double left = _headerWidth;
    double top = -100;

    if (visible) {
      final row = _instrumentLaneRegionRow!;
      if (!_isSourceRowVisible(row)) {
        return const SizedBox.shrink();
      }
      final anchor = _instrumentLaneRegionAnchorLocal!;
      if (anchor.dx >= 0 && anchor.dx <= viewportWidth) {
        left = (_headerWidth + anchor.dx - popupWidth / 2)
            .clamp(_headerWidth, _headerWidth + viewportWidth - popupWidth)
            .toDouble();
        final anchorViewportY = _contentYToTimelineViewportY(anchor.dy);
        top = anchorViewportY - popupHeight - 8;
        if (top < 0) {
          top = anchorViewportY + 8;
        }
        top = top
            .clamp(0.0, math.max(0.0, viewportHeight - popupHeight))
            .toDouble();
      }
    }

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          key: const ValueKey('instrument_lane_region_popup'),
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: TapRegion(
            enabled: visible,
            onTapOutside: (_) {
              if (!_showInstrumentLaneRegionPopup) return;
              setState(() {
                _clearInstrumentLaneRegionPopupState();
                _highlightedSegmentRow = null;
                _highlightedSegmentStartMs = null;
                _highlightedSegmentEndMs = null;
              });
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('instrument_lane_region_popup_add'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      unawaited(_createMidiRegionFromInstrumentLanePopup());
                    },
                    child: Container(
                      width: popupWidth,
                      height: popupHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _timelineGlassPopupDecoration(radius: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add_rounded,
                            size: 18,
                            color: _kTimelineShellText,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              L10n.translate(context, 'Add MIDI Region'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _kTimelineShellText,
                                fontFamily: 'Pretendard',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _editorLayoutSpec = _EditorLayoutSpec.fromSize(MediaQuery.of(context).size);
    return LayoutBuilder(
      builder: (context, rootConstraints) {
        final timelineWidth = rootConstraints.hasBoundedWidth
            ? rootConstraints.maxWidth
            : _timelineWidgetWidth(context);
        final viewportWidth = _viewportWidthForTimelineWidth(timelineWidth);
        final mobilePlayheadPx = _usesTabletDawLayout
            ? _getTabletDeviceCenterPlayheadPx(context)
            : _getMobilePlayheadPxForTimelineWidth(timelineWidth);
        final headerWidth = _headerWidth;
        final timelineUnderlayLeft = _timelineUnderlayLeft;
        final timelineUnderlayWidth = math.max(
          0.0,
          headerWidth - timelineUnderlayLeft,
        );
        final rowVisibility = _rowVisibilityMap();
        final rowsHiddenByCollapsedGroups = rowVisibility.entries
            .expand((entry) => entry.hiddenCollapsedSourceRows)
            .toSet();
        _syncVerticalScrollOffsetFromController();
        _recalculateRowYPositions();
        _timelineAutomationClipVisualCache = _timelineAutomationClipVisuals();
        final List<double> expandedHeights = List.generate(_rowCount, (i) {
          if (!_rowExpanded[i]) return 0.0;
          return _expandedPanelHeightForRow(i);
        });
        final List<double> automationLaneHeights = List.generate(
          _rowCount,
          (i) => _automationTimelineLaneHeightForRow(i),
        );
        final timelineAutomationClipVisuals =
            _timelineAutomationClipVisualCache;
        final staticTrackHeaders = Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: SizedBox(
            width: headerWidth,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerSignal: _onTimelineLeftChromePointerSignal,
              onPointerPanZoomStart: _onTimelinePointerPanZoomStart,
              onPointerPanZoomUpdate: _onTimelineLeftChromePointerPanZoomUpdate,
              onPointerPanZoomEnd: _onTimelinePointerPanZoomEnd,
              child: RepaintBoundary(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minHeight: 0,
                    maxHeight: _scrollContentHeight,
                    child: SizedBox(
                      height: _scrollContentHeight,
                      child: _buildTrackHeadersContent(headerWidth),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        return Focus(
          focusNode: _timelineFocusNode,
          autofocus: true,
          onKeyEvent: _handleTimelineKeyEvent,
          child: Container(
            constraints: const BoxConstraints(),
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<Duration>(
                  valueListenable: widget.transportClockListenable,
                  builder: (context, _, __) {
                    final playheadPx = PlatformCapabilities.current.isDesktop
                        ? _getPlayheadPx(context)
                        : mobilePlayheadPx;
                    _syncPlaybackViewport(playheadPx);
                    return _buildTimeRuler(viewportWidth);
                  },
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final visibleTimelineHeight = constraints.maxHeight;
                      return Stack(
                        children: [
                          if (_usesTabletDawLayout)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: headerWidth,
                              child: RepaintBoundary(
                                child: _buildTabletLeftSectionShell(),
                              ),
                            ),
                          ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: SingleChildScrollView(
                              controller: _verticalScrollController,
                              physics:
                                  ((_pendingDrag ||
                                              _pendingAutomationClipVisual !=
                                                  null) &&
                                          _activeTool !=
                                              _TimelineTool.delete) ||
                                      _isUserInteracting &&
                                          (_interactionMode == 'drag' ||
                                              _interactionMode ==
                                                  'automation' ||
                                              _hasActiveAutomationClipDrag) ||
                                      _timelineModifierTrackpadNavigationActive ||
                                      _activeTool == _TimelineTool.delete
                                  ? const NeverScrollableScrollPhysics()
                                  : const ClampingScrollPhysics(),
                              child: SizedBox(
                                height: _scrollContentHeight,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ValueListenableBuilder<Duration>(
                                      valueListenable:
                                          widget.transportClockListenable,
                                      builder: (context, clock, __) {
                                        final playheadPx =
                                            PlatformCapabilities
                                                .current
                                                .isDesktop
                                            ? _getPlayheadPx(context)
                                            : mobilePlayheadPx;
                                        _syncPlaybackViewport(playheadPx);
                                        return _buildPlaybackDrivenTimelineLayers(
                                          viewportWidth: viewportWidth,
                                          visibleTimelineHeight:
                                              visibleTimelineHeight,
                                          playheadPx: playheadPx,
                                          transportMs:
                                              clock.inMicroseconds.toDouble() /
                                              1000.0,
                                          timelineUnderlayWidth:
                                              timelineUnderlayWidth,
                                          expandedHeights: expandedHeights,
                                          automationLaneHeights:
                                              automationLaneHeights,
                                          timelineAutomationClipVisuals:
                                              timelineAutomationClipVisuals,
                                          rowsHiddenByCollapsedGroups:
                                              rowsHiddenByCollapsedGroups,
                                        );
                                      },
                                    ),
                                    _buildMasterAutomationLane(viewportWidth),
                                    staticTrackHeaders,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_usesTabletDawLayout)
                            Positioned(
                              left: 0,
                              bottom: 0,
                              width: headerWidth,
                              child: RepaintBoundary(
                                child: _buildTabletHeaderFooter(headerWidth),
                              ),
                            ),
                          if (_usesTabletDawLayout)
                            Positioned(
                              left: 0,
                              top: _kTabletRailTopInset,
                              bottom: _kTabletFooterControlsBottomPadding,
                              child: RepaintBoundary(
                                child: _buildTabletVerticalCompressionRail(
                                  visibleTimelineHeight,
                                ),
                              ),
                            ),
                          _buildSelectedClipPopup(
                            viewportWidth,
                            visibleTimelineHeight,
                          ),
                          _buildInstrumentLaneRegionPopup(
                            viewportWidth,
                            visibleTimelineHeight,
                          ),
                          _buildAutomationClipMenuOverlay(
                            viewportWidth,
                            visibleTimelineHeight,
                            timelineAutomationClipVisuals,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _syncPlaybackViewport(double playheadPx) {
    if (PlatformCapabilities.current.isDesktop) {
      return;
    }
    if (_scrollOffsetMs == 0.0 && _currentPlayheadMs == 0.0) {
      _scrollOffsetMs = -(playheadPx) / _pixelsPerMs;
    }
    if (_isUserInteracting && _interactionMode == 'pan') {
      return;
    }

    final int expectedRestartMs = (_loopEnabled && _loopStartMs != null)
        ? _loopStartMs!
        : 0;
    final bool isRestart =
        (!widget.isPlaying) &&
        (_currentPlayheadMs - expectedRestartMs).abs() < 0.01;

    if (isRestart) {
      final targetScrollMs = expectedRestartMs - (playheadPx) / _pixelsPerMs;
      if ((_scrollOffsetMs - targetScrollMs).abs() > 0.5) {
        _scrollOffsetMs = targetScrollMs;
        _clampScroll();
      }
    }

    if (widget.isPlaying) {
      final targetScrollMs = _currentPlayheadMs - (playheadPx) / _pixelsPerMs;
      if ((_scrollOffsetMs - targetScrollMs).abs() > 0.5) {
        _scrollOffsetMs = targetScrollMs;
        _clampScroll();
      }
    }
  }

  Widget _buildPlaybackDrivenTimelineLayers({
    required double viewportWidth,
    required double visibleTimelineHeight,
    required double playheadPx,
    required double transportMs,
    required double timelineUnderlayWidth,
    required List<double> expandedHeights,
    required List<double> automationLaneHeights,
    required List<_TimelineAutomationClipVisual> timelineAutomationClipVisuals,
    required Set<int> rowsHiddenByCollapsedGroups,
  }) {
    final loopPreviewClipIndex = _clipLoopPreviewClipIndex;
    final loopPreviewActive = loopPreviewClipIndex != null;
    final loopPreviewTransportMs = loopPreviewActive ? transportMs : 0.0;
    final loopPreviewStartMs = loopPreviewActive
        ? _clipLoopPreviewStartMs
        : null;
    final loopPreviewFallbackMs = loopPreviewActive
        ? _clipLoopPreviewFallbackMs
        : null;
    final visibleClipIndices = _visibleClipIndices(
      viewportWidth: viewportWidth,
      visibleTimelineHeight: visibleTimelineHeight,
      leftExtensionPx: _headerWidth,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (timelineUnderlayWidth > 0.0)
          Positioned(
            left: _timelineUnderlayLeft,
            top: 0,
            bottom: 0,
            width: timelineUnderlayWidth,
            child: IgnorePointer(
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ColoredBox(
                    color: _timelineCanvasColor(),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _TimelinePainter(
                          rows: widget.rows,
                          clips: widget.clips,
                          visibleClipIndices: visibleClipIndices,
                          clipVisualRevision: widget.clipVisualRevision,
                          clipOverlapMode: widget.clipOverlapMode,
                          getStartMs: widget.getStartMs,
                          getDurationMs: widget.getDurationMs,
                          getTimelineDurationMs: widget.getTimelineDurationMs,
                          getTrimStartMs: widget.getTrimStartMs,
                          getTrimEndMs: widget.getTrimEndMs,
                          getFullDurationMs: widget.getFullDurationMs,
                          getPeaks: widget.getPeaks,
                          pixelsPerMs: _pixelsPerMs,
                          scrollOffsetMs:
                              _scrollOffsetMs -
                              (timelineUnderlayWidth / _pixelsPerMs),
                          viewportWidth: timelineUnderlayWidth,
                          rulerHeight: _timeRulerHeight,
                          playheadPx: playheadPx,
                          transportMs: loopPreviewTransportMs,
                          clipLoopPreviewClipIndex: loopPreviewClipIndex,
                          clipLoopPreviewStartMs: loopPreviewStartMs,
                          clipLoopPreviewFallbackMs: loopPreviewFallbackMs,
                          selectedClipIndex: _selectedClipIndex,
                          selectedClipIndices: _selectedClipIndices.toList(
                            growable: false,
                          ),
                          clipVisualStackOrder: _clipVisualStackOrder,
                          clipVisualStackRevision: _clipVisualStackCounter,
                          stretchToolActive:
                              _activeTool == _TimelineTool.stretch,
                          trimClipIndex: _trimClipIndex,
                          draggedClipIndex: _interactionMode == 'drag'
                              ? _draggedClipIndex
                              : null,
                          draggedClipStartMs: _interactionMode == 'drag'
                              ? _dragStartClipMs
                              : null,
                          draggedClipRowIndex: _interactionMode == 'drag'
                              ? _dragStartRow
                              : null,
                          rowExpanded: _rowExpanded,
                          rowHeight: _rowHeight,
                          kExpandedRowHeight: _expandedRowHeight,
                          verticalScrollOffset: _verticalScrollOffset,
                          expandedTab: _expandedTab,
                          effectsPanelHeights: _effectsPanelHeights,
                          expandedHeights: expandedHeights,
                          automationLaneHeights: automationLaneHeights,
                          masterAutomationLaneHeight:
                              _masterAutomationLanePaintHeight,
                          isRecording: widget.isRecording,
                          recordingRowIndex: widget.recordingRowIndex,
                          recordingStartMs: widget.recordingStartMs,
                          recordingPeaks: widget.recordingPeaks,
                          recordingPeakTimesMs: widget.recordingPeakTimesMs,
                          bpm: widget.bpm,
                          beatsPerBar: widget.beatsPerBar,
                          beatUnit: widget.beatUnit,
                          quantizeDivisions: _quantizeDivisionsPerBar,
                          foregroundGridEnabled: _foregroundGridEnabled,
                          highlightedSegmentRow: _highlightedSegmentRow,
                          highlightedSegmentStartMs: _highlightedSegmentStartMs,
                          highlightedSegmentEndMs: _highlightedSegmentEndMs,
                          sampleDropPreviewRow: _externalSampleDropRow,
                          sampleDropPreviewStartMs: _externalSampleDropStartMs,
                          sampleDropPreviewEndMs: _externalSampleDropEndMs,
                          sampleDropPreviewAllowed: _externalSampleDropAllowed,
                          cutPreviewClipIndex: _cutPreviewClipIndex,
                          cutPreviewMs: _cutPreviewMs,
                          automationClipVisuals: timelineAutomationClipVisuals,
                          rowsHiddenByCollapsedGroups:
                              rowsHiddenByCollapsedGroups,
                          leftVisibleExtensionPx:
                              _headerWidth - _timelineUnderlayLeft,
                        ),
                        size: Size(timelineUnderlayWidth, _timelinePaintHeight),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          left: _headerWidth,
          child: Builder(
            builder: (context) {
              Widget timelineContent = Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onTimelinePointerDown,
                onPointerMove: _onTimelinePointerMove,
                onPointerHover: _onTimelinePointerHover,
                onPointerSignal: _onTimelinePointerSignal,
                onPointerPanZoomStart: _onTimelinePointerPanZoomStart,
                onPointerPanZoomUpdate: _onTimelinePointerPanZoomUpdate,
                onPointerPanZoomEnd: _onTimelinePointerPanZoomEnd,
                onPointerUp: _onTimelinePointerUp,
                onPointerCancel: _onTimelinePointerCancel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  onLongPressStart: PlatformCapabilities.current.isDesktop
                      ? null
                      : _onTimelineLongPressStart,
                  onLongPressMoveUpdate: PlatformCapabilities.current.isDesktop
                      ? null
                      : _onTimelineLongPressMoveUpdate,
                  onLongPressEnd: PlatformCapabilities.current.isDesktop
                      ? null
                      : _onTimelineLongPressEnd,
                  onDoubleTapDown: _onTimelineDoubleTapDown,
                  onTapDown: _handleTapDown,
                  onTapUp: _onTimelineTap,
                  child: SizedBox.expand(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ClipRect(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _TimelinePainter(
                              rows: widget.rows,
                              clips: widget.clips,
                              visibleClipIndices: visibleClipIndices,
                              clipVisualRevision: widget.clipVisualRevision,
                              clipOverlapMode: widget.clipOverlapMode,
                              getStartMs: widget.getStartMs,
                              getDurationMs: widget.getDurationMs,
                              getTimelineDurationMs:
                                  widget.getTimelineDurationMs,
                              getTrimStartMs: widget.getTrimStartMs,
                              getTrimEndMs: widget.getTrimEndMs,
                              getFullDurationMs: widget.getFullDurationMs,
                              getPeaks: widget.getPeaks,
                              pixelsPerMs: _pixelsPerMs,
                              scrollOffsetMs: _scrollOffsetMs,
                              viewportWidth: viewportWidth,
                              rulerHeight: _timeRulerHeight,
                              playheadPx: playheadPx,
                              transportMs: loopPreviewTransportMs,
                              clipLoopPreviewClipIndex: loopPreviewClipIndex,
                              clipLoopPreviewStartMs: loopPreviewStartMs,
                              clipLoopPreviewFallbackMs: loopPreviewFallbackMs,
                              selectedClipIndex: _selectedClipIndex,
                              selectedClipIndices: _selectedClipIndices.toList(
                                growable: false,
                              ),
                              clipVisualStackOrder: _clipVisualStackOrder,
                              clipVisualStackRevision: _clipVisualStackCounter,
                              stretchToolActive:
                                  _activeTool == _TimelineTool.stretch,
                              trimClipIndex: _trimClipIndex,
                              draggedClipIndex: _interactionMode == 'drag'
                                  ? _draggedClipIndex
                                  : null,
                              draggedClipStartMs: _interactionMode == 'drag'
                                  ? _dragStartClipMs
                                  : null,
                              draggedClipRowIndex: _interactionMode == 'drag'
                                  ? _dragStartRow
                                  : null,
                              rowExpanded: _rowExpanded,
                              rowHeight: _rowHeight,
                              kExpandedRowHeight: _expandedRowHeight,
                              verticalScrollOffset: _verticalScrollOffset,
                              expandedTab: _expandedTab,
                              effectsPanelHeights: _effectsPanelHeights,
                              expandedHeights: expandedHeights,
                              automationLaneHeights: automationLaneHeights,
                              masterAutomationLaneHeight:
                                  _masterAutomationLanePaintHeight,
                              isRecording: widget.isRecording,
                              recordingRowIndex: widget.recordingRowIndex,
                              recordingStartMs: widget.recordingStartMs,
                              recordingPeaks: widget.recordingPeaks,
                              recordingPeakTimesMs: widget.recordingPeakTimesMs,
                              bpm: widget.bpm,
                              beatsPerBar: widget.beatsPerBar,
                              beatUnit: widget.beatUnit,
                              quantizeDivisions: _quantizeDivisionsPerBar,
                              foregroundGridEnabled: _foregroundGridEnabled,
                              highlightedSegmentRow: _highlightedSegmentRow,
                              highlightedSegmentStartMs:
                                  _highlightedSegmentStartMs,
                              highlightedSegmentEndMs: _highlightedSegmentEndMs,
                              sampleDropPreviewRow: _externalSampleDropRow,
                              sampleDropPreviewStartMs:
                                  _externalSampleDropStartMs,
                              sampleDropPreviewEndMs: _externalSampleDropEndMs,
                              sampleDropPreviewAllowed:
                                  _externalSampleDropAllowed,
                              cutPreviewClipIndex: _cutPreviewClipIndex,
                              cutPreviewMs: _cutPreviewMs,
                              automationClipVisuals:
                                  timelineAutomationClipVisuals,
                              rowsHiddenByCollapsedGroups:
                                  rowsHiddenByCollapsedGroups,
                              leftVisibleExtensionPx: 0.0,
                            ),
                            size: Size(viewportWidth, _timelinePaintHeight),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );

              if (widget.onExternalSampleDrop == null) {
                return timelineContent;
              }

              return DragTarget<SampleDragData>(
                key: _externalSampleDropTargetKey,
                onWillAcceptWithDetails: (details) {
                  return _updateExternalSampleDropPreview(
                    details.offset,
                    data: details.data,
                    notifyEntered: true,
                  );
                },
                onMove: (details) {
                  _updateExternalSampleDropPreview(
                    details.offset,
                    data: details.data,
                  );
                },
                onLeave: (_) {
                  _clearExternalSampleDropPreview();
                },
                onAcceptWithDetails: (details) async {
                  final placement = _sampleDropPlacementForGlobalOffset(
                    details.offset,
                    data: details.data,
                  );
                  _clearExternalSampleDropPreview();
                  if (placement == null || !placement.allowed) return;
                  await widget.onExternalSampleDrop!(
                    details.data,
                    placement.row,
                    placement.startMs,
                  );
                },
                builder: (_, candidateData, ___) {
                  final showDropOverlay =
                      candidateData.isNotEmpty ||
                      _externalSampleDragInsideTimeline ||
                      _externalSampleDropRow != null;
                  if (!showDropOverlay) return timelineContent;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      timelineContent,
                      IgnorePointer(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 90),
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(43, 136, 222, 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _externalSampleDropAllowed == false
                                  ? const Color.fromRGBO(255, 150, 120, 0.70)
                                  : const Color.fromRGBO(124, 185, 235, 0.62),
                              width: 1.4,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color.fromRGBO(15, 24, 34, 0.78),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _externalSampleDropAllowed == false
                                        ? Icons.block_rounded
                                        : Icons.add_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    _externalSampleDropAllowed == false
                                        ? L10n.translate(
                                            context,
                                            'Drop on an audio row',
                                          )
                                        : L10n.translate(
                                            context,
                                            'Drop audio here',
                                          ),
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        if (_currentSelectionRect() != null) _buildSelectionBoxOverlay(),
        if (_selectionArmIndicatorAt != null)
          _buildSelectionArmIndicatorOverlay(),
        ..._buildExpandedRows(viewportWidth),
        Positioned(
          top: _addRowSectionTop,
          left: 0,
          right: 0,
          child: Center(child: _buildAddRowPill()),
        ),
        _buildPastePopup(viewportWidth),
        _buildAutomationClipTestOverlay(
          viewportWidth,
          visibleTimelineHeight,
          timelineAutomationClipVisuals,
        ),
        if (!widget.useTabletDawLayout) _buildDeadZoneRowNames(viewportWidth),
        _buildInlineClipControlOverlay(viewportWidth, visibleTimelineHeight),
      ],
    );
  }

  Widget _buildSelectionBoxOverlay() {
    final rect = _currentSelectionRect();
    if (rect == null) return const SizedBox.shrink();
    return Positioned(
      left: _headerWidth + rect.left,
      top: _contentYToTimelineViewportY(rect.top),
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: const Color.fromRGBO(43, 136, 222, 0.18),
            border: Border.all(
              color: const Color.fromRGBO(107, 184, 255, 0.76),
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionArmIndicatorOverlay() {
    final point = _selectionArmIndicatorAt;
    if (point == null) return const SizedBox.shrink();
    // Layout to the pulse peak so the expanding ring is not clipped by the Stack.
    final layoutRadius = _selectionArmIndicatorPulseRadius;
    final layoutDiameter = layoutRadius * 2;
    final peakScale =
        _selectionArmIndicatorPulseRadius / _selectionArmIndicatorRadius;
    return Positioned(
      left: _headerWidth + point.dx - layoutRadius,
      top: _contentYToTimelineViewportY(point.dy) - layoutRadius,
      width: layoutDiameter,
      height: layoutDiameter,
      child: IgnorePointer(
        child: Center(
          child: _SelectionArmRing(
            key: ValueKey<Offset>(point),
            radius: _selectionArmIndicatorRadius,
            peakScale: peakScale,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildExpandedRows(double viewportWidth) {
    final list = <Widget>[];

    for (int row = 0; row < _rowCount; row++) {
      if (!_isSourceRowVisible(row)) continue;
      if (!_rowExpanded[row]) continue;
      final expandedTab = _expandedTab[row];
      final expandedHeight = _expandedPanelHeightForRow(row);

      final double topY = _rowYPositions[row] + _rowHeight;
      final normalizedExpandedTab = _normalizeExpandedTab(expandedTab);
      final automationTargetId = _activeAutomationTargetIdForRow(row);
      list.add(
        Positioned(
          key: ValueKey('expanded_row_${widget.rows[row].rowId}'),
          left: _headerWidth,
          top: topY,
          width: viewportWidth,
          height: expandedHeight,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: _onTimelinePointerSignal,
            onPointerPanZoomStart: _onTimelinePointerPanZoomStart,
            onPointerPanZoomUpdate: _onTimelinePointerPanZoomUpdate,
            onPointerPanZoomEnd: _onTimelinePointerPanZoomEnd,
            child: ClipRect(
              // prevents overflow painting
              child: Container(
                decoration: BoxDecoration(
                  color: normalizedExpandedTab == 1
                      ? _kTimelineExpandedPanelSurfaceFx
                      : _kTimelineExpandedPanelSurface,
                  border: Border(
                    top: BorderSide(color: _kTimelineExpandedPanelBorder),
                    bottom: BorderSide(color: _kTimelineExpandedPanelBorder),
                  ),
                ),
                child: _buildExpandedRowPanelContent(
                  row,
                  viewportWidth,
                  normalizedExpandedTab,
                  automationTargetId,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return list;
  }

  Widget _buildMasterAutomationLane(double viewportWidth) {
    if (!_isMasterAutomationLaneOpen || _rowCount <= 0) {
      return const SizedBox.shrink();
    }
    final targets = _automationTargetsForMasterLane();
    if (targets.isEmpty) return const SizedBox.shrink();
    final targetId = _resolveAutomationTargetIdFromTargets(
      targets,
      _masterAutomationEditorTargetId ?? '',
    );
    return Positioned(
      left: _headerWidth,
      top: 0,
      width: viewportWidth,
      height: _masterAutomationLanePaintHeight,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: _onTimelinePointerSignal,
        onPointerPanZoomStart: _onTimelinePointerPanZoomStart,
        onPointerPanZoomUpdate: _onTimelinePointerPanZoomUpdate,
        onPointerPanZoomEnd: _onTimelinePointerPanZoomEnd,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _kMasterAutomationLaneFill,
            border: Border(
              bottom: BorderSide(color: _kMasterAutomationLaneBorder),
            ),
          ),
          child: ValueListenableBuilder<Duration>(
            valueListenable: widget.transportClockListenable,
            builder: (context, _, child) {
              final playheadPx = _getPlayheadPx(context);
              return Stack(
                children: [
                  Positioned.fill(child: child!),
                  _buildMasterAutomationPlayhead(playheadPx),
                ],
              );
            },
            child: _buildAutomationPanel(
              0,
              targetId: targetId,
              availableTargetsOverride: targets,
              masterLane: true,
              onClose: closeMasterAutomationLane,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMasterAutomationLaneHeader(double width) {
    const iconStripWidth = 44.0;
    return Container(
      width: width,
      height: _masterAutomationLanePaintHeight,
      decoration: BoxDecoration(
        color: _kMasterAutomationLaneHeader,
        border: Border(
          right: BorderSide(color: _kMasterAutomationLaneBorder),
          bottom: BorderSide(color: _kMasterAutomationLaneBorder),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: iconStripWidth,
            child: ColoredBox(
              color: const Color.fromRGBO(42, 73, 103, 0.90),
              child: Center(
                child: Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: _kTimelineShellText.withValues(alpha: 0.92),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.translate(context, 'Master'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kTimelineShellText,
                      fontFamily: 'Pretendard',
                      fontSize: 12.2,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    L10n.translate(context, 'Automation'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _kTimelineShellMutedText,
                      fontFamily: 'Pretendard',
                      fontSize: 9.8,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                      letterSpacing: 0,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    L10n.translate(context, 'Master chain'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.46),
                      fontFamily: 'Pretendard',
                      fontSize: 9.4,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterAutomationPlayhead(double playheadPx) {
    return Positioned(
      left: playheadPx - 2.0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color.fromRGBO(240, 169, 87, 0.22),
              border: Border(
                left: BorderSide(color: const Color(0xFFF0A957), width: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedRowPanelContent(
    int row,
    double viewportWidth,
    int normalizedExpandedTab,
    String automationTargetId,
  ) {
    final visibleContent = switch (normalizedExpandedTab) {
      0 => _buildVolumePanel(row),
      2 => _buildAutomationPanel(row, targetId: automationTargetId),
      _ => null,
    };

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (visibleContent != null) Positioned.fill(child: visibleContent),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: normalizedExpandedTab != 1,
            child: Offstage(
              offstage: normalizedExpandedTab != 1,
              child: Align(
                alignment: Alignment.topLeft,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: viewportWidth,
                  maxWidth: viewportWidth,
                  minHeight: 0.0,
                  maxHeight: double.infinity,
                  child: SizedBox(
                    width: viewportWidth,
                    child: _buildEffectsPanel(row),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeadZoneRowNames(double viewportWidth) {
    final zeroMsX = (0 - _scrollOffsetMs) * _pixelsPerMs;
    if (zeroMsX <= 12 || _rowCount == 0) {
      return const SizedBox.shrink();
    }
    final maxWidth = math.min(zeroMsX - 8, viewportWidth - 8);
    const bubbleTextStyle = TextStyle(
      color: Colors.white70,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    const horizontalPadding = 8.0;
    const borderWidth = 1.0;
    final minVisibleTextPainter = TextPainter(
      text: const TextSpan(text: 'W…', style: bubbleTextStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final minBubbleWidth =
        (horizontalPadding * 2) +
        (borderWidth * 2) +
        minVisibleTextPainter.width;
    if (maxWidth <= minBubbleWidth) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: List.generate(_rowCount, (row) {
            if (!_isSourceRowVisible(row)) return const SizedBox.shrink();
            final name = widget.rows[row].name.trim();
            return Positioned(
              left: _headerWidth + 6,
              top: _rowYPositions[row] + 8,
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  name.isEmpty
                      ? '${L10n.translate(context, 'Row')} ${row + 1}'
                      : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bubbleTextStyle,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  String? _resolveRowEffectAutomationTargetId(
    int row,
    int effectIndex,
    String paramId,
  ) {
    final trimmedParamId = paramId.trim();
    if (trimmedParamId.isEmpty) return null;
    final targets = widget.getAutomationTargetsForRow(row);
    for (final target in targets) {
      final candidateEffectIndex = (target['effectIndex'] as num?)?.toInt();
      final candidateParamId = (target['paramId'] ?? target['id'] ?? '')
          .toString()
          .trim();
      if (candidateEffectIndex == effectIndex &&
          candidateParamId == trimmedParamId) {
        return (target['id'] ?? '').toString().trim();
      }
    }
    return null;
  }

  Future<void> _handleRowEffectAutomationRequest(
    int row,
    int effectIndex,
    String effectName,
    String paramId,
    String paramName,
  ) async {
    final targetId = _resolveRowEffectAutomationTargetId(
      row,
      effectIndex,
      paramId,
    );
    if (targetId == null || targetId.isEmpty) return;
    unawaited(AppHaptics.impact(AppHapticImpact.medium));
    _openAutomationTabForTarget(
      row: row,
      targetId: targetId,
      haloKeys: <String>[
        'row:$row:automation_tab',
        'row:$row:automation_lane',
        'row:$row:fx_index:$effectIndex',
        'row:$row:param:${paramName.trim()}',
        'row:$row:fx_index:$effectIndex:param:${paramName.trim()}',
      ],
    );
  }

  Widget _buildTabButton(int row, int tab, String label) {
    final bool selected = _normalizeExpandedTab(_expandedTab[row]) == tab;
    final List<HaloKey> haloKeys = <HaloKey>[];
    if (tab == 0) {
      haloKeys.add(HaloKey('row:$row:volume_tab'));
    } else if (tab == 1) {
      haloKeys.add(HaloKey('row:$row:effects_tab'));
    } else if (tab == 2) {
      haloKeys.add(HaloKey('row:$row:automation_tab'));
      haloKeys.add(HaloKey('row:$row:automation_tab:strong'));
    }

    Widget tabButton = GestureDetector(
      onTap: () {
        _setExpandedTabForRow(row: row, tab: tab);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        width: double.infinity,
        height: _kHeaderTabButtonHeight,

        // Force full width of header but never overflow text
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),

              // === Gradient bubble like screenshot ===
              gradient: selected
                  ? const LinearGradient(
                      colors: [_kTimelineWarmStart, _kTimelineWarmEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [
                        Color.fromRGBO(47, 53, 60, 0.94),
                        Color.fromRGBO(30, 35, 41, 0.96),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],

              border: Border.all(
                color: selected
                    ? _kTimelineWarmBorder
                    : Colors.white.withValues(alpha: 0.12),
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              // === This makes the text shrink but never wrap ===
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  L10n.translate(context, label),
                  maxLines: 1, // Never wrap
                  overflow: TextOverflow.visible, // No ellipsis
                  softWrap: false, // NEVER wrap to next line
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: selected
                        ? _kTimelineShellText
                        : Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tutorialHighlighter != null) {
      tabButton = MultiHalo(
        highlighter: widget.tutorialHighlighter!,
        haloKeys: haloKeys,
        borderRadius: BorderRadius.circular(20),
        child: tabButton,
      );
    }
    return tabButton;
  }

  Widget _buildVolumePanel(int row) {
    final mixControlRows = _mixControlRows(row);
    Widget panel = Container(
      decoration: const BoxDecoration(color: _kTimelineExpandedInnerSurface),
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === Automation graph placeholder ===
            // Expanded(
            //   child: Container(
            //     decoration: BoxDecoration(
            //       color: const Color.fromARGB(255, 67, 194, 74).withOpacity(0.15),
            //       // borderRadius: BorderRadius.circular(10),
            //     ),
            //   ),
            // ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double laneHeight = constraints.maxHeight;

                  return _AutomationLane(
                    rowIndex: row,
                    points: widget.rowVolumeAutomation[row],
                    pixelsPerMs: _pixelsPerMs,
                    scrollOffsetMs: _scrollOffsetMs,
                    laneHeight: laneHeight,
                    timelineDurationMs: _maxDurationMs,
                    targetLabel: 'Volume',
                    targetParamId: 'volume',
                    targetUnit: 'dB',
                    targetMin: 0.0,
                    targetMax: 1.0,
                    targetDefaultNormalized: null,
                    targetDisplayLabels: const <double, String>{},
                    isVolumeLane: true,
                    highlightStartMs: null,
                    highlightEndMs: null,
                    onChanged: (pts) {
                      final before = widget.rowVolumeAutomation[row];
                      widget.onAutomationCommit!(
                        // for updating undo/redo history
                        row,
                        before,
                        pts.map((p) => p.copy()).toList(),
                      );

                      setState(() => widget.rowVolumeAutomation[row] = pts);
                      widget.setTrackAutomationPoints(
                        row,
                        pts.map((p) => p.toMap()).toList(),
                      ); // careful of doing on update, maybe better to do once on end
                    },
                    onPanStartExternal: (pos) =>
                        _automationPanStart(row, pos, laneHeight),
                    onPanUpdateExternal: (pos) =>
                        _automationPanUpdate(row, pos),
                    onPanEndExternal: () => _automationPanEnd(row),
                    onPanCancelExternal: _cancelAutomationPointInteraction,
                    onBackgroundPanStartExternal:
                        _automationLaneBackgroundPanStart,
                    onBackgroundPanUpdateExternal:
                        _automationLaneBackgroundPanUpdate,
                    onBackgroundPanEndExternal: _automationLaneBackgroundPanEnd,
                  );
                },
              ),
            ),

            // const SizedBox(height: 6),

            // === L/R Stereo pan slider ===
            // Padding(
            //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            //   child: PrettyStereoSlider(
            //     value: _rowPan[row], // <-- plug in real per-track value
            //     onChanged: (v) {
            //       setState(() => _rowPan[row] = v);
            //     },
            //   ),
            // ),

            // const SizedBox(height: 10),

            // // === Gain slider ===
            // Padding(
            //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            //   child: PrettyGainSlider(
            //     value: _rowGain[row],
            //     onChanged: (v) {
            //       setState(() => _rowGain[row] = v);
            //     },
            //   ),
            // ),

            // === Background for Gain + Pan (same as automation background) ===
            Container(
              decoration: BoxDecoration(
                color: _kTimelineExpandedInnerSurface,
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                ),
              ),
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Builder(
                      builder: (context) {
                        Widget child = PrettyGainSlider(
                          value: widget.rowGain[row],
                          showStepButtons: _usesTabletDawLayout,
                          stackedLayout: _usesTabletDawLayout,
                          label: L10n.translate(context, 'Gain'),
                          onLongPress: () {
                            unawaited(
                              AppHaptics.impact(AppHapticImpact.medium),
                            );
                            _openAutomationTabForTarget(
                              row: row,
                              targetId: 'mix:gain',
                              haloKeys: <String>[
                                'row:$row:automation_tab',
                                'row:$row:volume_tab',
                                'row:$row:mixer',
                                'row:$row:gain',
                                'row:$row:param:gain',
                              ],
                            );
                          },
                          onChangeStart: (v) {
                            _snapshotMixRowsGain(mixControlRows);
                          },
                          onChanged: (v) {
                            _setMixRowsGainLive(mixControlRows, v);
                          },
                          onChangeEnd: (v) {
                            _commitMixRowsGainFromSnapshot(mixControlRows);
                          },
                        );
                        if (widget.tutorialHighlighter != null) {
                          child = MultiHalo(
                            highlighter: widget.tutorialHighlighter!,
                            haloKeys: <HaloKey>[
                              HaloKey('row:$row:gain'),
                              HaloKey('row:$row:param:gain'),
                            ],
                            borderRadius: BorderRadius.circular(10),
                            child: child,
                          );
                        }
                        return child;
                      },
                    ),
                  ),

                  const SizedBox(height: 10),

                  // === Pan slider ===
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Builder(
                      builder: (context) {
                        Widget child = PrettyStereoSlider(
                          value: widget.rowPan[row],
                          showStepButtons: _usesTabletDawLayout,
                          stackedLayout: _usesTabletDawLayout,
                          label: L10n.translate(context, 'Pan'),
                          onLongPress: () {
                            unawaited(
                              AppHaptics.impact(AppHapticImpact.medium),
                            );
                            _openAutomationTabForTarget(
                              row: row,
                              targetId: 'mix:pan',
                              haloKeys: <String>[
                                'row:$row:automation_tab',
                                'row:$row:volume_tab',
                                'row:$row:mixer',
                                'row:$row:pan',
                                'row:$row:param:pan',
                              ],
                            );
                          },
                          onChangeStart: (v) {
                            _panDragStart = v;
                          },
                          onChanged: (v) {
                            _setMixRowsPanLive(mixControlRows, v);
                          },
                          onChangeEnd: (v) {
                            _commitMixRowsPan(
                              mixControlRows,
                              _panDragStart!,
                              widget.rowPan[row],
                            );
                            _panDragStart = null;
                          },
                        );
                        if (widget.tutorialHighlighter != null) {
                          child = MultiHalo(
                            highlighter: widget.tutorialHighlighter!,
                            haloKeys: <HaloKey>[
                              HaloKey('row:$row:pan'),
                              HaloKey('row:$row:param:pan'),
                            ],
                            borderRadius: BorderRadius.circular(10),
                            child: child,
                          );
                        }
                        return child;
                      },
                    ),
                  ),
                ],
              ),
            ),

            // const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (widget.tutorialHighlighter != null) {
      panel = MultiHalo(
        highlighter: widget.tutorialHighlighter!,
        haloKeys: <HaloKey>[
          HaloKey('row:$row:mixer'),
          HaloKey('row:$row:volume_lane'),
          HaloKey('row:$row:param:volume'),
        ],
        borderRadius: BorderRadius.circular(10),
        child: panel,
      );
    }
    return panel;
  }

  Widget _buildAutomationPanel(
    int row, {
    required String targetId,
    VoidCallback? onClose,
    List<Map<String, dynamic>>? availableTargetsOverride,
    bool masterLane = false,
  }) {
    final availableTargets =
        availableTargetsOverride ?? _automationTargetsForAutomationTab(row);
    final activeTargetId = availableTargetsOverride == null
        ? _resolveAutomationTabTargetId(row, targetId)
        : _resolveAutomationTargetIdFromTargets(availableTargets, targetId);
    final activeTarget =
        _automationTargetMetaById(row, activeTargetId) ?? <String, dynamic>{};
    final lanePoints = activeTargetId == 'volume'
        ? widget.rowVolumeAutomation[row]
        : widget.getAutomationPointsForTarget(row, activeTargetId);
    final targetLabel = (activeTarget['label'] ?? activeTargetId)
        .toString()
        .trim();
    final targetFullLabel = (activeTarget['fullLabel'] ?? targetLabel)
        .toString()
        .trim();
    final targetParamId = (activeTarget['paramId'] ?? activeTargetId)
        .toString()
        .trim();
    final targetUnit = (activeTarget['unit'] ?? '').toString().trim();
    final targetMin = (activeTarget['min'] as num?)?.toDouble() ?? 0.0;
    final targetMax = (activeTarget['max'] as num?)?.toDouble() ?? 1.0;
    final targetDefaultNormalized = (activeTarget['defaultNormalized'] as num?)
        ?.toDouble();
    final targetDisplayLabels = <double, String>{};
    final rawDisplayLabels = activeTarget['displayLabels'];
    if (rawDisplayLabels is Map) {
      rawDisplayLabels.forEach((key, value) {
        final normalized = double.tryParse(key.toString());
        final label = value?.toString().trim() ?? '';
        if (normalized == null || label.isEmpty) return;
        targetDisplayLabels[normalized.clamp(0.0, 1.0).toDouble()] = label;
      });
    }
    final isVolumeTarget =
        (activeTarget['isVolume'] == true) || activeTargetId == 'volume';
    final isOrphanTarget = activeTarget['isOrphan'] == true;
    final formatter = _AutomationValueFormatter(
      targetLabel: targetLabel.isEmpty ? activeTargetId : targetLabel,
      targetParamId: targetParamId.isEmpty ? activeTargetId : targetParamId,
      targetUnit: targetUnit,
      targetMin: targetMin,
      targetMax: targetMax,
      pluginDisplayLabels: targetDisplayLabels,
      pluginDefaultNormalized: targetDefaultNormalized,
      isVolumeLane: isVolumeTarget,
    );
    final targetDisplayTitle = targetFullLabel.isEmpty
        ? (targetLabel.isEmpty ? activeTargetId : targetLabel)
        : targetFullLabel;
    final pickerRowKey = masterLane ? -1 : row;
    final rangeSelectionActiveForTarget = _isAutomationRangeSelectionModeFor(
      row,
      activeTargetId,
    );
    final bool hasRangeStart = _automationRangeSelectionStartMs != null;
    final bool hasRangeEnd = _automationRangeSelectionEndMs != null;
    final bool canConfirmRangeSelection =
        rangeSelectionActiveForTarget &&
        hasRangeStart &&
        hasRangeEnd &&
        (_automationRangeSelectionEndMs! - _automationRangeSelectionStartMs!)
                .abs() >
            1e-6;
    final editorSubtitle = isOrphanTarget
        ? 'Target unavailable'
        : rangeSelectionActiveForTarget
        ? (!hasRangeStart
              ? 'Tap start'
              : (hasRangeEnd ? 'Range locked' : 'Tap end'))
        : 'Point lane';

    bool hasAutomationDataForTarget(Map<String, dynamic> target) {
      if (target['hasAutomationData'] == true) return true;
      final id = (target['id'] ?? '').toString().trim();
      if (id.isEmpty) return false;

      final clips = widget.getAutomationClipsForTarget(row, id);
      if (clips.isNotEmpty) return true;

      if (id == 'volume') {
        final points = widget.rowVolumeAutomation[row];
        if (points.length > 1) return true;
        if (points.isNotEmpty && (points.first.volume - 0.75).abs() > 1e-6) {
          return true;
        }
      }
      return false;
    }

    String automationTargetLabel(Map<String, dynamic> target) {
      final id = (target['id'] ?? '').toString().trim();
      final rawLabel = (target['fullLabel'] ?? target['label'] ?? id)
          .toString()
          .trim();
      final label = rawLabel.isEmpty ? id : rawLabel;
      return L10n.translate(context, label);
    }

    void selectAutomationTarget(String nextTargetId) {
      if (nextTargetId.trim().isEmpty) return;
      setState(() {
        final resolved = availableTargetsOverride == null
            ? _resolveAutomationTabTargetId(row, nextTargetId)
            : _resolveAutomationTargetIdFromTargets(
                availableTargets,
                nextTargetId,
              );
        if (_isAutomationRangeSelectionModeFor(row, activeTargetId) &&
            resolved != activeTargetId) {
          _clearAutomationRangeSelectionMode();
        }
        if (masterLane) {
          _masterAutomationEditorTargetId = resolved;
        } else {
          widget.setSelectedAutomationTargetId(row, resolved);
          _automationEditorRow = row;
          _automationEditorTargetId = resolved;
        }
        _automationTargetPickerRow = null;
      });
    }

    final footerPadding = masterLane
        ? const EdgeInsets.fromLTRB(10, 4, 10, 6)
        : const EdgeInsets.fromLTRB(10, 4, 10, 8);
    final pickerHeight = masterLane ? 34.0 : 38.0;
    final pickerMenuHeight = masterLane ? 196.0 : 224.0;
    final footerGap = masterLane ? 5.0 : 7.0;
    final toolbarHeight = masterLane ? 22.0 : 24.0;

    double? laneHighlightStartMs;
    double? laneHighlightEndMs;
    final hasSharedHighlight =
        _highlightedSegmentRow == row &&
        _highlightedSegmentStartMs != null &&
        _highlightedSegmentEndMs != null &&
        _highlightedSegmentEndMs! > _highlightedSegmentStartMs!;
    if (hasSharedHighlight) {
      laneHighlightStartMs = _highlightedSegmentStartMs!;
      laneHighlightEndMs = _highlightedSegmentEndMs!;
    }
    if (rangeSelectionActiveForTarget && hasRangeStart) {
      final start = _automationRangeSelectionStartMs!;
      if (hasRangeEnd) {
        final end = _automationRangeSelectionEndMs!;
        laneHighlightStartMs = math.min(start, end);
        laneHighlightEndMs = math.max(start, end);
      } else {
        final previewWidthMs = _magnetEnabled
            ? _quantizeIntervalMs()
            : math.max(1.0, 14.0 / _pixelsPerMs);
        final previewEnd = (start + previewWidthMs)
            .clamp(start + 0.001, _maxDurationMs)
            .toDouble();
        laneHighlightStartMs = start;
        laneHighlightEndMs = previewEnd;
      }
    }

    void showAutomationSnackbar(String message) {
      final localized = L10n.translate(context, message);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(localized),
            duration: const Duration(milliseconds: 1300),
          ),
        );
    }

    void copyAutomationAreaForRange({
      required double startMs,
      required double endMs,
      required String successMessage,
    }) {
      final safeStart = math.min(startMs, endMs).clamp(0.0, _maxDurationMs);
      final safeEnd = math.max(startMs, endMs).clamp(0.0, _maxDurationMs);
      if (safeEnd - safeStart <= 0.0) {
        showAutomationSnackbar('Invalid range. Tap a different end point.');
        return;
      }
      final copiedRelative =
          _automationPointsForRange(
                lanePoints,
                startMs: safeStart.toDouble(),
                endMs: safeEnd.toDouble(),
                relativeToStart: true,
              )
              .map(
                (point) => AutomationPoint(
                  x: point.x,
                  volume: formatter.displayNormalizedForStoredNormalized(
                    point.volume,
                  ),
                ),
              )
              .toList(growable: false);
      _automationAreaClipboard = _AutomationAreaClipboardEntry(
        durationMs: safeEnd - safeStart,
        relativePoints: copiedRelative,
      );
      setState(() {
        _highlightedSegmentRow = row;
        _highlightedSegmentStartMs = safeStart.toDouble();
        _highlightedSegmentEndMs = safeEnd.toDouble();
      });
      showAutomationSnackbar(successMessage);
    }

    void copyAllAutomationPoints() {
      final copiedPoints = lanePoints
          .map(
            (point) => AutomationPoint(
              x: point.x,
              volume: formatter.displayNormalizedForStoredNormalized(
                point.volume,
              ),
            ),
          )
          .toList(growable: false);
      _automationPointsClipboard = _AutomationPointsClipboardEntry(
        points: copiedPoints,
      );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              L10n.translate(context, 'Copied all automation points'),
            ),
            duration: Duration(milliseconds: 1200),
          ),
        );
    }

    void pasteAllAutomationPoints() {
      final clipboard = _automationPointsClipboard;
      if (clipboard == null || clipboard.points.isEmpty) {
        return;
      }
      final before = lanePoints
          .map((point) => point.copy())
          .toList(growable: false);
      final copiedAfter = clipboard.points
          .map(
            (point) => AutomationPoint(
              x: point.x,
              volume: formatter.storedNormalizedForDisplayNormalized(
                point.volume,
              ),
            ),
          )
          .toList(growable: false);
      _commitAutomationPointsForTarget(
        row,
        activeTargetId,
        before,
        copiedAfter,
      );
      setState(() {});
    }

    void copyAutomationArea() {
      if (_hasActiveLoopRange()) {
        final loopStart = _loopStartMs!.toDouble();
        final loopEnd = _loopEndMs!.toDouble();
        if (rangeSelectionActiveForTarget) {
          setState(() {
            _clearAutomationRangeSelectionMode();
          });
        }
        copyAutomationAreaForRange(
          startMs: loopStart,
          endMs: loopEnd,
          successMessage:
              'Copied loop automation region ${_formatAutomationEditorRange(loopStart, loopEnd)}',
        );
        return;
      }
      setState(() {
        _automationRangeSelectionMode = true;
        _automationRangeSelectionRow = row;
        _automationRangeSelectionTargetId = activeTargetId;
        _automationRangeSelectionStartMs = null;
        _automationRangeSelectionEndMs = null;
        _highlightedSegmentRow = null;
        _highlightedSegmentStartMs = null;
        _highlightedSegmentEndMs = null;
      });
      showAutomationSnackbar('Tap start, then tap end to copy range');
    }

    void cancelAutomationRangeSelection() {
      if (!rangeSelectionActiveForTarget) return;
      setState(() {
        _clearAutomationRangeSelectionMode();
      });
      showAutomationSnackbar('Range selection cancelled');
    }

    void confirmAutomationRangeSelection() {
      if (!rangeSelectionActiveForTarget) return;
      final startMs = _automationRangeSelectionStartMs;
      final endMs = _automationRangeSelectionEndMs;
      if (startMs == null || endMs == null) {
        showAutomationSnackbar('Select start and end points first');
        return;
      }
      final safeStart = math.min(startMs, endMs);
      final safeEnd = math.max(startMs, endMs);
      if (safeEnd - safeStart <= 0.0) {
        showAutomationSnackbar('Tap a different end point');
        return;
      }
      copyAutomationAreaForRange(
        startMs: safeStart,
        endMs: safeEnd,
        successMessage:
            'Copied area ${_formatAutomationEditorRange(safeStart, safeEnd)}',
      );
      setState(() {
        _clearAutomationRangeSelectionMode();
      });
    }

    void handleAutomationRangeTap(Offset localPos) {
      if (!rangeSelectionActiveForTarget) return;
      final rawMs = (_scrollOffsetMs + localPos.dx / _pixelsPerMs)
          .clamp(0.0, _maxDurationMs)
          .toDouble();
      final tappedMs = _magnetEnabled ? _segmentStartMsForTap(rawMs) : rawMs;
      final startMs = _automationRangeSelectionStartMs;
      final endMs = _automationRangeSelectionEndMs;

      if (startMs == null || endMs != null) {
        setState(() {
          _automationRangeSelectionStartMs = tappedMs;
          _automationRangeSelectionEndMs = null;
        });
        showAutomationSnackbar(
          'Start ${_formatAutomationEditorTime(tappedMs)} set. Tap end point.',
        );
        return;
      }

      final safeStart = math.min(startMs, tappedMs);
      final safeEnd = math.max(startMs, tappedMs);
      if (safeEnd - safeStart <= 0.0) {
        showAutomationSnackbar('Tap a different end point');
        return;
      }

      setState(() {
        _automationRangeSelectionEndMs = tappedMs;
      });
      showAutomationSnackbar(
        'Range ${_formatAutomationEditorRange(safeStart, safeEnd)} selected. Tap Confirm.',
      );
    }

    void pasteAutomationAreaAtPlayhead() {
      final clipboard = _automationAreaClipboard;
      if (clipboard == null ||
          clipboard.relativePoints.isEmpty ||
          clipboard.durationMs <= 0.0) {
        return;
      }
      final playheadStart = _magnetEnabled
          ? _segmentStartMsForTap(_currentPlayheadMs)
          : _currentPlayheadMs;
      final startMs = playheadStart.clamp(0.0, _maxDurationMs).toDouble();
      final availableDuration = _maxDurationMs - startMs;
      if (availableDuration <= 1.0) return;
      final appliedDuration = math.min(clipboard.durationMs, availableDuration);
      final endMs = startMs + appliedDuration;
      final relativeSlice = _automationPointsForRange(
        clipboard.relativePoints,
        startMs: 0.0,
        endMs: appliedDuration,
        relativeToStart: true,
      );
      final pastedPoints = relativeSlice
          .map(
            (point) => AutomationPoint(
              x: startMs + point.x,
              volume: formatter.storedNormalizedForDisplayNormalized(
                point.volume,
              ),
            ),
          )
          .toList(growable: false);
      final before = lanePoints
          .map((point) => point.copy())
          .toList(growable: false);
      final merged = <AutomationPoint>[
        ...before
            .where(
              (point) => point.x < startMs - 1e-6 || point.x > endMs + 1e-6,
            )
            .map((point) => point.copy()),
        ...pastedPoints.map((point) => point.copy()),
      ]..sort((a, b) => a.x.compareTo(b.x));
      final compacted = <AutomationPoint>[];
      for (final point in merged) {
        if (compacted.isNotEmpty && (point.x - compacted.last.x).abs() < 1e-6) {
          compacted[compacted.length - 1] = point.copy();
        } else {
          compacted.add(point.copy());
        }
      }
      _commitAutomationPointsForTarget(row, activeTargetId, before, compacted);
      setState(() {
        _highlightedSegmentRow = row;
        _highlightedSegmentStartMs = startMs;
        _highlightedSegmentEndMs = endMs;
      });
    }

    Widget actionButton({
      required String label,
      required IconData icon,
      required VoidCallback? onTap,
      Color? accent,
      bool iconOnly = false,
    }) {
      final enabled = onTap != null;
      final foreground = enabled
          ? (accent ?? Colors.white.withValues(alpha: 0.84))
          : Colors.white.withValues(alpha: 0.28);
      return Padding(
        padding: const EdgeInsets.only(right: 5),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: iconOnly ? 8 : 9,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: enabled
                    ? (accent ?? Colors.white).withValues(alpha: 0.11)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12, color: foreground),
                  if (!iconOnly) ...[
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 10.1,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget toolbarAction({
      required String label,
      required IconData icon,
      required VoidCallback? onTap,
    }) {
      final enabled = onTap != null;
      final fg = enabled
          ? Colors.white.withValues(alpha: 0.84)
          : Colors.white.withValues(alpha: 0.3);
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: fg),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 10.6,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Container(
        key: const ValueKey('automation_panel'),
        decoration: BoxDecoration(
          color: _kTimelineExpandedInnerSurface,
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final laneHeight = constraints.maxHeight;
                  return Stack(
                    children: [
                      _AutomationLane(
                        rowIndex: row,
                        points: lanePoints,
                        pixelsPerMs: _pixelsPerMs,
                        scrollOffsetMs: _scrollOffsetMs,
                        laneHeight: laneHeight,
                        timelineDurationMs: _maxDurationMs,
                        targetLabel: targetLabel.isEmpty
                            ? activeTargetId
                            : targetLabel,
                        targetParamId: targetParamId.isEmpty
                            ? activeTargetId
                            : targetParamId,
                        targetUnit: targetUnit,
                        targetMin: targetMin,
                        targetMax: targetMax,
                        targetDefaultNormalized: targetDefaultNormalized,
                        targetDisplayLabels: targetDisplayLabels,
                        isVolumeLane: isVolumeTarget,
                        highlightStartMs: laneHighlightStartMs,
                        highlightEndMs: laneHighlightEndMs,
                        onChanged: (pts) {
                          if (rangeSelectionActiveForTarget) return;
                          final copiedAfter = pts
                              .map((p) => p.copy())
                              .toList(growable: false);
                          final before = lanePoints
                              .map((p) => p.copy())
                              .toList(growable: false);
                          _commitAutomationPointsForTarget(
                            row,
                            activeTargetId,
                            before,
                            copiedAfter,
                          );
                          setState(() {});
                        },
                        onPanStartExternal: (pos) => masterLane
                            ? _masterAutomationPanStart(
                                activeTargetId,
                                pos,
                                laneHeight,
                              )
                            : _automationPanStart(row, pos, laneHeight),
                        onPanUpdateExternal: (pos) => masterLane
                            ? _masterAutomationPanUpdate(activeTargetId, pos)
                            : _automationPanUpdate(row, pos),
                        onPanEndExternal: () => masterLane
                            ? _masterAutomationPanEnd(activeTargetId)
                            : _automationPanEnd(row),
                        onPanCancelExternal: _cancelAutomationPointInteraction,
                        onBackgroundPanStartExternal:
                            _automationLaneBackgroundPanStart,
                        onBackgroundPanUpdateExternal:
                            _automationLaneBackgroundPanUpdate,
                        onBackgroundPanEndExternal:
                            _automationLaneBackgroundPanEnd,
                      ),
                      if (rangeSelectionActiveForTarget)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) =>
                                handleAutomationRangeTap(details.localPosition),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: footerPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              targetDisplayTitle,
                              key: const ValueKey('automation_panel_title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: _kTimelineShellText,
                                fontSize: 12.4,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              editorSubtitle,
                              key: const ValueKey('automation_panel_subtitle'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _kTimelineShellMutedText,
                                fontSize: 9.4,
                                fontWeight: FontWeight.w500,
                                height: 1.1,
                                fontFamily: 'Pretendard',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isOrphanTarget)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: const Color(0xFFFFB3B3),
                          ),
                        ),
                      actionButton(
                        label: L10n.translate(context, 'Link'),
                        icon: Icons.link_rounded,
                        onTap: isOrphanTarget
                            ? null
                            : () {
                                unawaited(
                                  _revealRowAutomationTarget(
                                    row,
                                    activeTargetId,
                                  ),
                                );
                              },
                        accent: const Color(0xFFA6D6FF),
                        iconOnly: true,
                      ),
                      if (onClose != null)
                        IconButton(
                          tooltip: L10n.translate(
                            context,
                            'Close automation editor',
                          ),
                          onPressed: onClose,
                          padding: EdgeInsets.zero,
                          visualDensity: const VisualDensity(
                            horizontal: -3,
                            vertical: -3,
                          ),
                          constraints: const BoxConstraints.tightFor(
                            width: 24,
                            height: 24,
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  LayoutBuilder(
                    builder: (context, pickerConstraints) {
                      return MenuAnchor(
                        alignmentOffset: const Offset(0, 5),
                        onOpen: () {
                          if (_automationTargetPickerRow == pickerRowKey) {
                            return;
                          }
                          setState(
                            () => _automationTargetPickerRow = pickerRowKey,
                          );
                        },
                        onClose: () {
                          if (!mounted ||
                              _automationTargetPickerRow != pickerRowKey) {
                            return;
                          }
                          setState(() => _automationTargetPickerRow = null);
                        },
                        style: MenuStyle(
                          backgroundColor: const WidgetStatePropertyAll<Color>(
                            kMixroomGlassDropdownMenuColor,
                          ),
                          surfaceTintColor: const WidgetStatePropertyAll<Color>(
                            Colors.transparent,
                          ),
                          elevation: const WidgetStatePropertyAll<double>(10),
                          padding:
                              const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                                EdgeInsets.zero,
                              ),
                          shape: WidgetStatePropertyAll<OutlinedBorder>(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          side: WidgetStatePropertyAll<BorderSide>(
                            BorderSide(
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                          ),
                        ),
                        menuChildren: [
                          SizedBox(
                            width: pickerConstraints.maxWidth,
                            height: pickerMenuHeight,
                            child: Scrollbar(
                              child: ListView.separated(
                                padding: const EdgeInsets.all(7),
                                itemCount: availableTargets.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 5),
                                itemBuilder: (context, index) {
                                  final target = availableTargets[index];
                                  final id = (target['id'] ?? '')
                                      .toString()
                                      .trim();
                                  final selected = id == activeTargetId;
                                  final isOrphan = target['isOrphan'] == true;
                                  final hasAutomationData =
                                      hasAutomationDataForTarget(target);
                                  return MenuItemButton(
                                    onPressed: id.isEmpty
                                        ? null
                                        : () => selectAutomationTarget(id),
                                    style: ButtonStyle(
                                      padding:
                                          const WidgetStatePropertyAll<
                                            EdgeInsetsGeometry
                                          >(EdgeInsets.zero),
                                      minimumSize:
                                          const WidgetStatePropertyAll<Size>(
                                            Size.zero,
                                          ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      backgroundColor:
                                          const WidgetStatePropertyAll<Color>(
                                            Colors.transparent,
                                          ),
                                      overlayColor:
                                          WidgetStateProperty.resolveWith<
                                            Color?
                                          >((states) {
                                            if (states.contains(
                                              WidgetState.pressed,
                                            )) {
                                              return Colors.white.withValues(
                                                alpha: 0.08,
                                              );
                                            }
                                            if (states.contains(
                                              WidgetState.hovered,
                                            )) {
                                              return Colors.white.withValues(
                                                alpha: 0.055,
                                              );
                                            }
                                            return null;
                                          }),
                                    ),
                                    child: Container(
                                      height: 34,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? Colors.white.withValues(
                                                alpha: 0.105,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.025,
                                              ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: selected
                                              ? _kTimelineWarmBorder
                                              : Colors.white.withValues(
                                                  alpha: 0.055,
                                                ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            selected
                                                ? Icons.check_rounded
                                                : Icons.tune_rounded,
                                            size: selected ? 14 : 13,
                                            color: selected
                                                ? _kTimelineShellText
                                                : Colors.white.withValues(
                                                    alpha: 0.32,
                                                  ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              automationTargetLabel(target),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontFamily: 'Pretendard',
                                                color: selected
                                                    ? _kTimelineShellText
                                                    : Colors.white.withValues(
                                                        alpha: 0.78,
                                                      ),
                                                fontSize: 11.4,
                                                fontWeight: selected
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                                letterSpacing: 0,
                                              ),
                                            ),
                                          ),
                                          if (isOrphan) ...[
                                            const SizedBox(width: 7),
                                            Icon(
                                              Icons.warning_amber_rounded,
                                              size: 14,
                                              color: const Color(
                                                0xFFFFB3B3,
                                              ).withValues(alpha: 0.9),
                                            ),
                                          ] else if (hasAutomationData) ...[
                                            const SizedBox(width: 7),
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: _kTimelineShellMutedText
                                                    .withValues(alpha: 0.78),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                        builder: (context, controller, child) {
                          return Container(
                            height: pickerHeight,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.055),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  if (controller.isOpen) {
                                    controller.close();
                                  } else {
                                    controller.open();
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: _kTimelineWarmBorder
                                              .withValues(alpha: 0.82),
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              L10n.translate(
                                                context,
                                                'Parameters',
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.48,
                                                ),
                                                fontFamily: 'Pretendard',
                                                fontSize: 8.8,
                                                fontWeight: FontWeight.w700,
                                                height: 1.0,
                                                letterSpacing: 0,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              L10n.translate(
                                                context,
                                                targetDisplayTitle,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontFamily: 'Pretendard',
                                                color: _kTimelineShellText,
                                                fontSize: 11.6,
                                                fontWeight: FontWeight.w700,
                                                height: 1.0,
                                                letterSpacing: 0,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      AnimatedRotation(
                                        turns:
                                            _automationTargetPickerRow ==
                                                pickerRowKey
                                            ? 0.5
                                            : 0.0,
                                        duration: const Duration(
                                          milliseconds: 120,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        child: Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 20,
                                          color: Colors.white.withValues(
                                            alpha: 0.66,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  SizedBox(height: footerGap),
                  SizedBox(
                    height: toolbarHeight,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        toolbarAction(
                          label: L10n.translate(context, 'Copy'),
                          icon: Icons.content_copy_outlined,
                          onTap: copyAllAutomationPoints,
                        ),
                        toolbarAction(
                          label: L10n.translate(context, 'Paste'),
                          icon: Icons.content_paste_outlined,
                          onTap: _automationPointsClipboard != null
                              ? pasteAllAutomationPoints
                              : null,
                        ),
                        if (!rangeSelectionActiveForTarget)
                          toolbarAction(
                            label: L10n.translate(context, 'Copy range'),
                            icon: Icons.crop_free_rounded,
                            onTap: copyAutomationArea,
                          ),
                        if (rangeSelectionActiveForTarget)
                          toolbarAction(
                            label: L10n.translate(context, 'Cancel'),
                            icon: Icons.close_rounded,
                            onTap: cancelAutomationRangeSelection,
                          ),
                        if (rangeSelectionActiveForTarget)
                          toolbarAction(
                            label: L10n.translate(context, 'Confirm'),
                            icon: Icons.check_rounded,
                            onTap: canConfirmRangeSelection
                                ? confirmAutomationRangeSelection
                                : null,
                          ),
                        toolbarAction(
                          label: L10n.translate(context, 'Paste here'),
                          icon: Icons.vertical_align_top_rounded,
                          onTap: _automationAreaClipboard != null
                              ? pasteAutomationAreaAtPlayhead
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  //old placeholder
  // Widget _buildEffectsPanel(int row) {
  //   return Container(
  //     alignment: Alignment.center,
  //     child: const Text(
  //       "Effects UI coming soon",
  //       style: TextStyle(color: Colors.white54),
  //     ),
  //   );
  // }

  Widget _buildEffectsPanel(int row) {
    Widget panel = Material(
      type: MaterialType.canvas,
      color: _kTimelineExpandedInnerSurfaceFx,
      child: RowEffectsPanel(
        key: ValueKey("effect_panel_row_${widget.rows[row].rowId}"),
        rowIndex: row,
        mode: widget.mode,
        isProEntitled: widget.allPluginsEntitled,
        onUpgradeRequested: widget.onUpgradeRequested,
        minHeight: _effectsPanelMinHeight,
        onHeightChanged: (h) {
          if (!mounted || row < 0 || row >= _effectsPanelHeights.length) {
            return;
          }
          final nextHeight = math.max(h, _effectsPanelMinHeight);
          if ((_effectsPanelHeights[row] - nextHeight).abs() <= 0.5) return;
          setState(() {
            _effectsPanelHeights[row] = nextHeight;
          });
          _syncVerticalScrollOffsetAfterGeometryChange();
        },
        // callbacks
        getEffectsForRow: widget.getRowEffects,
        getEffectIdsForRow: widget.getRowEffectIds,
        getBypassStateForRow: widget.getRowEffectBypassState,
        setBypassForRow: widget.setRowEffectBypassed,
        reorderEffectsForRow: widget.reorderRowEffects,
        removeEffectFromRow: widget.removeRowEffect,
        insertEffectOnRow: widget.insertRowEffect,
        getTrackPluginParameters: widget.getRowPluginParameters,
        scanPlugins: widget.scanPlugins,
        onTogglePluginFavorite: widget.onTogglePluginFavorite,
        onManagePlugins: widget.onManagePlugins,
        openTrackPluginEditor: widget.openTrackPluginEditor,
        setTrackEffectParam: widget.setRowEffectParam,
        onRequestAutomateParameter: _handleRowEffectAutomationRequest,
        onPluginParamCommit: widget.onPluginParamCommit,
        onPresetCommit: widget.onPresetCommit,
        useDeviceChainLayout: _usesTabletDawLayout,
        openSelectedEffectInline: !_usesDesktopOrTabletDawLayout,
        selectedEffectIndex: widget.selectedRowEffectRow == row
            ? widget.selectedRowEffectIndex
            : null,
        onEffectSelected: _usesDesktopOrTabletDawLayout
            ? (effectIndex) {
                widget.onRowEffectSelected?.call(row, effectIndex);
              }
            : null,
        onCopyRowEffects: widget.onCopyRowEffects,
        onPasteRowEffects: widget.onPasteRowEffects == null
            ? null
            : () => widget.onPasteRowEffects!(row),
        onClearRowEffects: widget.onClearRowEffects == null
            ? null
            : () => widget.onClearRowEffects!(row),
        hasCopiedRowEffects: widget.hasCopiedRowEffects,
        onTutorialEffectAdded: widget.onTutorialRowEffectAdded,
        onTutorialEffectOpened: widget.onTutorialRowEffectOpened,
        registerRefresh: (refreshFn) {
          _rowEffectRefreshers[widget.rows[row].rowId] = refreshFn;
        },
        registerPlaybackRefresh: (refreshFn) {
          _rowEffectPlaybackRefreshers[widget.rows[row].rowId] = refreshFn;
        },
        registerParameterRevealer: (reveal) {
          _rowEffectParameterRevealers[widget.rows[row].rowId] = reveal;
        },
        projectBpm: widget.bpm,
        meters: widget.meters,
        getRowCompressorMeter: widget.getRowCompressorMeter,
        getRowEqWaveform: widget.getRowEqWaveform,
        getRowStereoScope: widget.getRowStereoScope,
        tutorialHighlighter: widget.tutorialHighlighter,
      ),
    );
    if (widget.tutorialHighlighter != null) {
      panel = MultiHalo(
        highlighter: widget.tutorialHighlighter!,
        haloKeys: <HaloKey>[
          HaloKey('row:$row:fx_list'),
          HaloKey('row:$row:effects_panel'),
        ],
        borderRadius: BorderRadius.circular(10),
        child: panel,
      );
    }
    return panel;
  }

  Widget _buildToggleButtonSvg({
    Key? key,
    required bool active,
    required VoidCallback onTap,
    GestureTapDownCallback? onTapDown,
    GestureTapUpCallback? onTapUp,
    GestureTapCancelCallback? onTapCancel,
    required String svgPath,
    double size = 30,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      onTapDown: onTapDown,
      onTapUp: onTapUp,
      onTapCancel: onTapCancel,
      child: SizedBox(
        width: size,
        height: size,
        child: Container(
          decoration: BoxDecoration(
            color: active
                ? const Color.fromRGBO(244, 244, 244, 0.24)
                : const Color.fromRGBO(31, 37, 45, 0.88),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            svgPath,
            height: size * 0.70,
            colorFilter: ColorFilter.mode(
              active
                  ? const Color.fromRGBO(244, 244, 244, 0.92)
                  : const Color.fromRGBO(244, 244, 244, 0.94),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

  // for the magnet button
  double _quantizeMs(double rawMs) {
    if (!_magnetEnabled) return rawMs;

    final double subdivision = _quantizeIntervalMs();
    if (subdivision <= 0) return rawMs;

    final double snapped = (rawMs / subdivision).round() * subdivision;
    return snapped;
  }

  bool _isHandleVisible(double handlePx, double viewportWidth) {
    return handlePx >= 0 && handlePx <= viewportWidth;
  }

  bool _hitHandle(double fingerX, double handleX) {
    const double hitWidth = 26.0; // ~13px on each side
    return fingerX >= handleX - hitWidth && fingerX <= handleX + hitWidth;
  }

  double _rulerMsFromLocalX(double localX) {
    return _scrollOffsetMs + localX / _pixelsPerMs;
  }

  void _notifyLoopStateChanged() {
    if (!_loopEnabled || _loopStartMs == null || _loopEndMs == null) return;
    widget.onLoopRegionChanged?.call(_loopStartMs!, _loopEndMs!);
  }

  void _setLoopRegion({
    required double startMs,
    required double endMs,
    bool notifyToggle = false,
  }) {
    final minStart = math.min(startMs, endMs);
    final maxEnd = math.max(startMs, endMs);
    final safeStart = math.max(0.0, minStart);
    final safeEnd = math.max(safeStart + 50.0, maxEnd);

    _loopEnabled = true;
    _loopStartMs = safeStart.toInt();
    _loopEndMs = safeEnd.toInt();
    if (notifyToggle) {
      widget.onLoopToggle?.call(true);
    }
    _notifyLoopStateChanged();
  }

  void _clearLoopRegion() {
    if (!_loopEnabled && _loopStartMs == null && _loopEndMs == null) return;
    setState(() {
      _loopEnabled = false;
      _loopStartMs = null;
      _loopEndMs = null;
      _draggingLoopStart = false;
      _draggingLoopEnd = false;
      _draggingLoopRegion = false;
      _creatingLoopRegion = false;
      _loopDragOffsetMs = null;
      _loopCreateAnchorMs = null;
      _loopDragRegionFingerAnchorMs = null;
      _loopDragRegionStartAnchorMs = null;
      _loopDragRegionEndAnchorMs = null;
    });
    widget.onLoopToggle?.call(false);
  }

  void _resetRulerDragState() {
    _draggingLoopStart = false;
    _draggingLoopEnd = false;
    _draggingLoopRegion = false;
    _creatingLoopRegion = false;
    _desktopPlayheadDragActive = false;
    _loopDragOffsetMs = null;
    _loopCreateAnchorMs = null;
    _loopDragRegionFingerAnchorMs = null;
    _loopDragRegionStartAnchorMs = null;
    _loopDragRegionEndAnchorMs = null;
  }

  void _onRulerTapDown(TapDownDetails d) {
    if (_selectedClipIndex < 0 && _selectedClipIndices.isEmpty) return;
    setState(() {
      _clearClipSelection();
    });
  }

  void _onDesktopRulerSecondaryTap(TapDownDetails d) {
    final tappedMsRaw = _rulerMsFromLocalX(d.localPosition.dx);
    final tappedMs = _magnetEnabled ? _quantizeMs(tappedMsRaw) : tappedMsRaw;
    final hasLoop = _loopEnabled && _loopStartMs != null && _loopEndMs != null;
    if (!hasLoop) {
      setState(() {
        _setLoopRegion(
          startMs: tappedMs,
          endMs: tappedMs + _msPerBar() * 4.0,
          notifyToggle: true,
        );
      });
      return;
    }

    final inside = tappedMs >= _loopStartMs! && tappedMs <= _loopEndMs!;
    if (!inside) {
      _clearLoopRegion();
    }
  }

  void _beginLoopInteractionAtRulerX(double fingerX) {
    final fingerMsRaw = _rulerMsFromLocalX(fingerX);
    final fingerMs = _magnetEnabled ? _quantizeMs(fingerMsRaw) : fingerMsRaw;
    final hasLoop = _loopEnabled && _loopStartMs != null && _loopEndMs != null;

    if (!hasLoop) {
      setState(() {
        _creatingLoopRegion = true;
        _loopCreateAnchorMs = fingerMs;
        _setLoopRegion(
          startMs: fingerMs,
          endMs: fingerMs + _msPerBar() * 4.0,
          notifyToggle: true,
        );
      });
      return;
    }

    final startPx = (_loopStartMs! - _scrollOffsetMs) * _pixelsPerMs;
    final endPx = (_loopEndMs! - _scrollOffsetMs) * _pixelsPerMs;
    final inside = fingerMs >= _loopStartMs! && fingerMs <= _loopEndMs!;

    setState(() {
      if (_isHandleVisible(startPx, _getViewportWidth(context)) &&
          _hitHandle(fingerX, startPx)) {
        _draggingLoopStart = true;
        _loopDragOffsetMs = _loopStartMs! - fingerMsRaw;
        return;
      }
      if (_isHandleVisible(endPx, _getViewportWidth(context)) &&
          _hitHandle(fingerX, endPx)) {
        _draggingLoopEnd = true;
        _loopDragOffsetMs = _loopEndMs! - fingerMsRaw;
        return;
      }

      if (inside) {
        _draggingLoopRegion = true;
        _loopDragRegionFingerAnchorMs = fingerMsRaw;
        _loopDragRegionStartAnchorMs = _loopStartMs;
        _loopDragRegionEndAnchorMs = _loopEndMs;
        return;
      }

      _creatingLoopRegion = true;
      _loopCreateAnchorMs = fingerMs;
      _setLoopRegion(
        startMs: fingerMs,
        endMs: fingerMs + _quantizeIntervalMs(),
        notifyToggle: false,
      );
    });
  }

  void _updateLoopInteractionAtRulerX(double fingerX) {
    final fingerMsRaw = _rulerMsFromLocalX(fingerX);
    final fingerMs = _magnetEnabled ? _quantizeMs(fingerMsRaw) : fingerMsRaw;

    setState(() {
      if (_creatingLoopRegion && _loopCreateAnchorMs != null) {
        _setLoopRegion(
          startMs: _loopCreateAnchorMs!,
          endMs: fingerMs,
          notifyToggle: false,
        );
        return;
      }

      if (_draggingLoopStart &&
          _loopDragOffsetMs != null &&
          _loopEndMs != null) {
        double target = fingerMsRaw + _loopDragOffsetMs!;
        target = _magnetEnabled ? _quantizeMs(target) : target;
        target = target.clamp(0.0, _loopEndMs! - 50.0);
        _loopStartMs = target.toInt();
        _notifyLoopStateChanged();
        return;
      }

      if (_draggingLoopEnd &&
          _loopDragOffsetMs != null &&
          _loopStartMs != null) {
        double target = fingerMsRaw + _loopDragOffsetMs!;
        target = _magnetEnabled ? _quantizeMs(target) : target;
        target = target.clamp(_loopStartMs! + 50.0, double.infinity);
        _loopEndMs = target.toInt();
        _notifyLoopStateChanged();
        return;
      }

      if (_draggingLoopRegion &&
          _loopDragRegionFingerAnchorMs != null &&
          _loopDragRegionStartAnchorMs != null &&
          _loopDragRegionEndAnchorMs != null) {
        final originalLength =
            (_loopDragRegionEndAnchorMs! - _loopDragRegionStartAnchorMs!)
                .toDouble();
        double deltaMs = fingerMsRaw - _loopDragRegionFingerAnchorMs!;
        double nextStart = _loopDragRegionStartAnchorMs! + deltaMs;
        if (_magnetEnabled) {
          nextStart = _quantizeMs(nextStart);
        }
        if (nextStart < 0) {
          nextStart = 0;
        }
        _loopStartMs = nextStart.toInt();
        _loopEndMs = (nextStart + originalLength).toInt();
        _notifyLoopStateChanged();
      }
    });
  }

  void _onDesktopRulerSecondaryPointerDown(PointerDownEvent event) {
    if (!PlatformCapabilities.current.isDesktop ||
        event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kSecondaryMouseButton) == 0) {
      return;
    }
    _desktopSecondaryLoopDragActive = true;
    _beginLoopInteractionAtRulerX(event.localPosition.dx);
  }

  void _onRulerPointerDown(PointerDownEvent event) {
    _requestTimelineFocus();
    if (PlatformCapabilities.current.isDesktop) {
      _onDesktopRulerSecondaryPointerDown(event);
    }
  }

  void _onDesktopRulerSecondaryPointerMove(PointerMoveEvent event) {
    if (!_desktopSecondaryLoopDragActive) return;
    if ((event.buttons & kSecondaryMouseButton) == 0) {
      setState(() {
        _desktopSecondaryLoopDragActive = false;
        _resetRulerDragState();
      });
      return;
    }
    _updateLoopInteractionAtRulerX(event.localPosition.dx);
  }

  void _onDesktopRulerSecondaryPointerUp(PointerEvent event) {
    if (!_desktopSecondaryLoopDragActive) return;
    setState(() {
      _desktopSecondaryLoopDragActive = false;
      _resetRulerDragState();
    });
  }

  void _onRulerTapUp(TapUpDetails d) {
    if (PlatformCapabilities.current.isDesktop) {
      _jumpDesktopPlayheadToRulerX(d.localPosition.dx);
      return;
    }
    final tappedMsRaw = _rulerMsFromLocalX(d.localPosition.dx);
    final tappedMs = _magnetEnabled ? _quantizeMs(tappedMsRaw) : tappedMsRaw;
    final hasLoop = _loopEnabled && _loopStartMs != null && _loopEndMs != null;
    if (!hasLoop) {
      setState(() {
        _setLoopRegion(
          startMs: tappedMs,
          endMs: tappedMs + _msPerBar() * 4.0,
          notifyToggle: true,
        );
      });
      return;
    }

    final inside = tappedMs >= _loopStartMs! && tappedMs <= _loopEndMs!;
    if (!inside) {
      _clearLoopRegion();
    }
  }

  void _onRulerPanStart(DragStartDetails d) {
    if (PlatformCapabilities.current.isDesktop) {
      setState(() {
        _desktopPlayheadDragActive = true;
      });
      _jumpDesktopPlayheadToRulerX(d.localPosition.dx);
      return;
    }
    _beginLoopInteractionAtRulerX(d.localPosition.dx);
  }

  void _onRulerPanUpdate(DragUpdateDetails d) {
    if (PlatformCapabilities.current.isDesktop) {
      if (_desktopPlayheadDragActive) {
        _jumpDesktopPlayheadToRulerX(d.localPosition.dx);
      }
      return;
    }
    _updateLoopInteractionAtRulerX(d.localPosition.dx);
  }

  void _onRulerPanEnd(DragEndDetails d) {
    setState(_resetRulerDragState);
  }

  Widget _buildToolMenuButton() {
    return GestureDetector(
      key: _toolMenuButtonKey,
      onTapDown: (_) {
        _showToolMenu();
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color.fromRGBO(31, 37, 45, 0.88),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: KeyedSubtree(
          key: ValueKey('timeline_active_tool_${_activeTool.name}'),
          child: _buildToolIcon(
            _activeTool,
            size: 16,
            color: const Color.fromARGB(220, 255, 255, 255),
          ),
        ),
      ),
    );
  }

  Widget _buildToolIcon(
    _TimelineTool tool, {
    required double size,
    required Color color,
  }) {
    final icon = Icon(tool.icon, size: size, color: color);
    if (!tool.flipHorizontally) return icon;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
      child: icon,
    );
  }

  void _toggleMagnetFromRuler() {
    setState(() {
      if (_magnetMenuShownFromHold) {
        _magnetMenuShownFromHold = false;
        return;
      }
      _magnetEnabled = !_magnetEnabled;
      if (!_magnetEnabled) {
        _highlightedSegmentRow = null;
        _highlightedSegmentStartMs = null;
        _highlightedSegmentEndMs = null;
      } else if (_pasteRow != null && _pasteMs != null && _showPastePopup) {
        final start = _segmentStartMsForTap(_pasteMs!);
        _pasteMs = start;
        _highlightedSegmentRow = _pasteRow;
        _highlightedSegmentStartMs = start;
        _highlightedSegmentEndMs = start + _quantizeIntervalMs();
      }
      _refreshCutPreviewFromCurrentRaw(inSetState: true);
      _notifySnapSettingsChanged();
    });
  }

  Widget _buildTabletRulerHeader({double? height}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Container(
        height: height ?? TabletDawPanelLayout.tabletRulerHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF485660).withValues(alpha: 0.80),
          border: Border(
            right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeRuler(double viewportWidth) {
    final isDesktop = PlatformCapabilities.current.isDesktop;
    final rulerHeight = _timeRulerHeight;
    final rulerContentYOffset = _timeRulerContentYOffset;
    const scrollbarOverlap = 0.0;
    if (isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _publishHorizontalScrollbarState(viewportWidth: viewportWidth);
      });
    }
    return SizedBox(
      height: rulerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: scrollbarOverlap,
            height: rulerHeight - scrollbarOverlap,
            child: Container(
              color: isDesktop
                  ? const Color.fromRGBO(18, 28, 40, 0.68)
                  : _timelineCanvasColor(),
              child: Stack(
                children: [
                  Row(
                    children: [
                      // Empty space for headers
                      SizedBox(
                        width: _headerWidth,
                        child: _usesTabletDawLayout
                            ? _buildTabletRulerHeader(height: rulerHeight)
                            : SizedBox(
                                height: rulerHeight,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // _buildToggleButton(
                                      //   size: 30, // smaller
                                      //   iconSize: 16, // smaller icon
                                      //   iconOn: Symbols.magnification_small,
                                      //   iconOff: Icons.push_pin_outlined,
                                      //   active: _magnetEnabled,
                                      //   onTap: () => setState(() => _magnetEnabled = !_magnetEnabled),
                                      // ),
                                      _buildToggleButtonSvg(
                                        key: _magnetButtonKey,
                                        active: _magnetEnabled,
                                        onTap: _toggleMagnetFromRuler,
                                        onTapDown: _onMagnetTapDown,
                                        onTapUp: _onMagnetTapUp,
                                        onTapCancel: _onMagnetTapCancel,
                                        svgPath: 'assets/magnet-solid-full.svg',
                                      ),
                                      _buildToolMenuButton(),
                                    ],
                                  ),
                                ),
                              ),
                      ),

                      // Ruler content
                      Expanded(
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerSignal: _onTimelinePointerSignal,
                          onPointerPanZoomStart: _onTimelinePointerPanZoomStart,
                          onPointerPanZoomUpdate:
                              _onTimelinePointerPanZoomUpdate,
                          onPointerPanZoomEnd: _onTimelinePointerPanZoomEnd,
                          onPointerDown: _onRulerPointerDown,
                          onPointerMove: isDesktop
                              ? _onDesktopRulerSecondaryPointerMove
                              : null,
                          onPointerUp: isDesktop
                              ? _onDesktopRulerSecondaryPointerUp
                              : null,
                          onPointerCancel: isDesktop
                              ? _onDesktopRulerSecondaryPointerUp
                              : null,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTapDown: _onRulerTapDown,
                            onTapUp: _onRulerTapUp,
                            onSecondaryTapDown: isDesktop
                                ? _onDesktopRulerSecondaryTap
                                : null,
                            onPanStart: _onRulerPanStart,
                            onPanUpdate: _onRulerPanUpdate,
                            onPanEnd: _onRulerPanEnd,
                            child: CustomPaint(
                              painter: _RulerPainter(
                                pixelsPerMs: _pixelsPerMs,
                                scrollOffsetMs: _scrollOffsetMs,
                                viewportWidth: viewportWidth,
                                bpm: widget.bpm,
                                beatsPerBar: widget.beatsPerBar,
                                beatUnit: widget.beatUnit,
                                quantizeDivisions: _quantizeDivisionsPerBar,
                                contentYOffset: rulerContentYOffset,
                              ),
                              size: Size(viewportWidth, rulerHeight),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isDesktop)
                    ValueListenableBuilder<Duration>(
                      valueListenable: widget.transportClockListenable,
                      builder: (context, _, __) {
                        final playheadPx = _getPlayheadPx(context);
                        return Positioned(
                          left: _headerWidth + playheadPx - 10,
                          top: 16 + rulerContentYOffset,
                          child: IgnorePointer(
                            child: SizedBox(
                              width: 20,
                              height: rulerHeight,
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.arrow_drop_down_rounded,
                                    size: 14,
                                    color: const Color(0xFFF0A957),
                                  ),
                                  Container(
                                    width: 2,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0A957),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  if (_loopEnabled)
                    _buildLoopRegion(viewportWidth, height: rulerHeight),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoopRegion(double viewportWidth, {double? height}) {
    if (_loopStartMs == null || _loopEndMs == null) {
      return const SizedBox.shrink();
    }

    final startPx = (_loopStartMs! - _scrollOffsetMs) * _pixelsPerMs;
    final endPx = (_loopEndMs! - _scrollOffsetMs) * _pixelsPerMs;

    double left = math.min(startPx, endPx) + _headerWidth;
    double width = (endPx - startPx).abs();

    // --- NEW FIX: Prevent overlap with the track headers ---
    if (left < _headerWidth) {
      width -= (_headerWidth - left);
      left = _headerWidth;
    }

    // If width is now negative, nothing to draw
    if (width <= 0) return const SizedBox.shrink();
    return Positioned(
      key: const ValueKey('timeline_loop_region'),
      left: left,
      top: 0,
      width: width,
      height: height ?? kRulerHeight,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFC5A5).withOpacity(0.33),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFFF9A6A), width: 2),
            boxShadow: [
              if (_draggingLoopStart || _draggingLoopEnd || _draggingLoopRegion)
                BoxShadow(
                  color: const Color(0xFFFF9A6A).withOpacity(0.25),
                  blurRadius: 12,
                  spreadRadius: 3,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRowMenu(int row) async {
    final isInstrumentLane =
        row >= 0 &&
        row < widget.rows.length &&
        widget.rows[row].isInstrumentLane;
    final groupingRows = _rowsForGroupingAction(row);
    final rowGroup = _groupForRow(row);
    final visibilityEntry = _visibilityEntryForSourceRow(row);
    final isGroupLeadRow =
        rowGroup != null && visibilityEntry?.isGroupFirstRow == true;
    final canRenameGroup = isGroupLeadRow && widget.onRenameRowGroup != null;
    final renameRowLabel = L10n.translate(context, 'Rename Row');
    final renameGroupLabel = L10n.translate(context, 'Rename Group');
    final rowNameHint = L10n.translate(context, 'Row name');
    final groupNameHint = L10n.translate(context, 'Group name');
    final currentRowColor = row >= 0 && row < widget.rows.length
        ? widget.rows[row].color
        : 0;
    final canCreateGroup =
        widget.onCreateRowGroup != null && groupingRows.length >= 2;
    final canEditGroup =
        rowGroup != null &&
        (widget.onRemoveRowFromGroup != null ||
            widget.onToggleRowGroupCollapsed != null);
    if (_selectedClipIndex >= 0 || _selectedClipIndices.isNotEmpty) {
      setState(() {
        _clearClipSelection();
      });
    }
    unawaited(AppHaptics.impact(AppHapticImpact.medium));
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF5F666D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.78;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onSetRowColor != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.palette_outlined,
                                color: _kTimelineShellText,
                                size: 22,
                              ),
                              const SizedBox(width: 16),
                              Text(
                                L10n.translate(ctx, 'Choose Row Color'),
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: _kTimelineShellText,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
                              _buildRowColorChoice(
                                key: ValueKey('row_color_choice_${row}_clear'),
                                context: ctx,
                                color: Colors.transparent,
                                value: 0,
                                selected: currentRowColor == 0,
                                clear: true,
                                onTap: () => Navigator.pop(ctx, 'color:0'),
                              ),
                              for (
                                var index = 0;
                                index < _kTimelineRowColorPalette.length;
                                index++
                              )
                                _buildRowColorChoice(
                                  key: ValueKey(
                                    'row_color_choice_${row}_$index',
                                  ),
                                  context: ctx,
                                  color: _kTimelineRowColorPalette[index],
                                  value: _kTimelineRowColorPalette[index]
                                      .toARGB32(),
                                  selected:
                                      currentRowColor ==
                                      _kTimelineRowColorPalette[index]
                                          .toARGB32(),
                                  onTap: () => Navigator.pop(
                                    ctx,
                                    'color:${_kTimelineRowColorPalette[index].toARGB32()}',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ListTile(
                    leading: const Icon(
                      Icons.vertical_align_top,
                      color: _kTimelineShellText,
                    ),
                    title: Text(
                      L10n.translate(ctx, 'Insert Audio Row Above'),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        color: _kTimelineShellText,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, 'insert_above'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.vertical_align_bottom,
                      color: _kTimelineShellText,
                    ),
                    title: Text(
                      L10n.translate(ctx, 'Insert Audio Row Below'),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        color: _kTimelineShellText,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, 'insert_below'),
                  ),
                  if (widget.onInsertInstrumentLaneAbove != null)
                    ListTile(
                      leading: const Icon(
                        Icons.piano_outlined,
                        color: _kTimelineShellText,
                      ),
                      title: Text(
                        L10n.translate(ctx, 'Insert Instrument Lane Above'),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: _kTimelineShellText,
                        ),
                      ),
                      onTap: () =>
                          Navigator.pop(ctx, 'insert_instrument_above'),
                    ),
                  if (widget.onInsertInstrumentLaneBelow != null)
                    ListTile(
                      leading: const Icon(
                        Icons.piano_outlined,
                        color: _kTimelineShellText,
                      ),
                      title: Text(
                        L10n.translate(ctx, 'Insert Instrument Lane Below'),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: _kTimelineShellText,
                        ),
                      ),
                      onTap: () =>
                          Navigator.pop(ctx, 'insert_instrument_below'),
                    ),
                  if (isInstrumentLane && widget.onChangeInstrumentLane != null)
                    ListTile(
                      leading: const Icon(
                        Icons.swap_horiz_rounded,
                        color: _kTimelineShellText,
                      ),
                      title: Text(
                        L10n.translate(ctx, 'Change Instrument'),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: _kTimelineShellText,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, 'change_instrument'),
                    ),
                  ListTile(
                    leading: const Icon(
                      Icons.arrow_upward,
                      color: _kTimelineShellText,
                    ),
                    title: Text(
                      L10n.translate(ctx, 'Move Up'),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        color: _kTimelineShellText,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, 'move_up'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.arrow_downward,
                      color: _kTimelineShellText,
                    ),
                    title: Text(
                      L10n.translate(ctx, 'Move Down'),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        color: _kTimelineShellText,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, 'move_down'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.drive_file_rename_outline,
                      color: _kTimelineShellText,
                    ),
                    title: Text(
                      L10n.translate(
                        ctx,
                        canRenameGroup ? 'Rename Group' : 'Rename Row',
                      ),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        color: _kTimelineShellText,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, 'rename'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.image_outlined,
                      color: _kTimelineShellText,
                    ),
                    title: Text(
                      L10n.translate(ctx, 'Choose Icon'),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        color: _kTimelineShellText,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, 'icon'),
                  ),
                  if (canCreateGroup)
                    ListTile(
                      leading: const Icon(
                        Icons.folder_outlined,
                        color: _kTimelineShellText,
                      ),
                      title: Text(
                        L10n.translate(
                          ctx,
                          groupingRows.length > 1
                              ? 'Group Selected Rows'
                              : 'Create Row Group',
                        ),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: _kTimelineShellText,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, 'create_group'),
                    ),
                  if (canEditGroup && widget.onToggleRowGroupCollapsed != null)
                    ListTile(
                      leading: Icon(
                        rowGroup.collapsed
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: _kTimelineShellText,
                      ),
                      title: Text(
                        L10n.translate(
                          ctx,
                          rowGroup.collapsed
                              ? 'Expand Group'
                              : 'Collapse Group',
                        ),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: _kTimelineShellText,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, 'toggle_group_fold'),
                    ),
                  if (canEditGroup && widget.onRemoveRowFromGroup != null)
                    ListTile(
                      leading: const Icon(
                        Icons.folder_off_outlined,
                        color: _kTimelineShellText,
                      ),
                      title: Text(
                        L10n.translate(ctx, 'Remove From Group'),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: _kTimelineShellText,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, 'remove_group'),
                    ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFFFA4A4),
                    ),
                    title: Text(
                      L10n.translate(ctx, 'Delete Row'),
                      style: const TextStyle(color: Color(0xFFFFA4A4)),
                    ),
                    onTap: () => Navigator.pop(ctx, 'delete'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (action == null) return;
    if (action.startsWith('color:')) {
      final selectedColor = int.tryParse(action.substring('color:'.length));
      if (selectedColor != null) {
        return _setMixRowsColor(_headerControlRows(row), selectedColor);
      }
      return;
    }
    if (action == 'insert_above') return widget.onInsertRowAbove(row);
    if (action == 'insert_below') return widget.onInsertRowBelow(row);
    if (action == 'insert_instrument_above') {
      return widget.onInsertInstrumentLaneAbove?.call(row);
    }
    if (action == 'insert_instrument_below') {
      return widget.onInsertInstrumentLaneBelow?.call(row);
    }
    if (action == 'change_instrument') {
      return widget.onChangeInstrumentLane?.call(row);
    }
    if (action == 'move_up' && row > 0) {
      return widget.onMoveRow(row, row - 1);
    }
    if (action == 'move_down' && row < _rowCount - 1) {
      return widget.onMoveRow(row, row + 1);
    }
    if (action == 'delete') {
      return widget.onDeleteRow(row);
    }
    if (action == 'create_group') {
      return widget.onCreateRowGroup?.call(groupingRows);
    }
    if (action == 'toggle_group_fold' && rowGroup != null) {
      return widget.onToggleRowGroupCollapsed?.call(rowGroup.id);
    }
    if (action == 'remove_group') {
      return widget.onRemoveRowFromGroup?.call(row);
    }

    if (action == 'rename') {
      final TrackGroup? groupToRename = canRenameGroup ? rowGroup : null;
      final renameGroup = groupToRename != null;
      final name = await _showTimelineNameInputDialog(
        title: renameGroup ? renameGroupLabel : renameRowLabel,
        initialName: renameGroup ? groupToRename.name : widget.rows[row].name,
        hintText: renameGroup ? groupNameHint : rowNameHint,
        maxLength: 32,
      );
      if (name != null && name.isNotEmpty) {
        if (renameGroup) {
          await widget.onRenameRowGroup!(groupToRename.id, name);
          return;
        }
        await widget.onRenameRow(row, name);
      }
      return;
    }

    if (action == 'icon') {
      final currentIconId = widget.rows[row].iconId;
      final selectedIconId = await showDialog<int>(
        context: context,
        builder: (ctx) {
          const ids = kTrackRowIconIds;
          final scrollController = ScrollController();
          final viewport = MediaQuery.of(ctx).size;
          final dialogWidth = math.min(264.0, viewport.width - 80.0);
          final gridHeight = math.min(
            300.0,
            math.max(180.0, viewport.height - 260.0),
          );
          return AlertDialog(
            backgroundColor: const Color(0xFF5F666D),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
            title: Text(
              L10n.translate(ctx, 'Select Icon'),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                color: _kTimelineShellText,
              ),
            ),
            content: SizedBox(
              width: dialogWidth,
              height: gridHeight,
              child: Scrollbar(
                controller: scrollController,
                thumbVisibility: PlatformCapabilities.current.isDesktop,
                child: GridView.builder(
                  controller: scrollController,
                  primary: false,
                  padding: const EdgeInsets.only(right: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: ids.length,
                  itemBuilder: (_, index) {
                    final id = ids[index];
                    final selected = id == currentIconId;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(ctx, id),
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.16)
                                : _kTimelineShellFill,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFFBDEFE3)
                                  : Colors.white.withValues(alpha: 0.12),
                              width: selected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Center(
                            child: buildTrackRowIcon(
                              id,
                              size: 22,
                              color: selected
                                  ? const Color(0xFFBDEFE3)
                                  : _kTimelineShellText,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
      if (selectedIconId != null) {
        await widget.onSetRowIcon(row, selectedIconId);
      }
    }

    if (action == 'color') {
      final currentColor = row >= 0 && row < widget.rows.length
          ? widget.rows[row].color
          : 0;
      final selectedColor = await showDialog<int>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF5F666D),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
            title: Text(
              L10n.translate(ctx, 'Choose Row Color'),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                color: _kTimelineShellText,
              ),
            ),
            content: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _buildRowColorChoice(
                  context: ctx,
                  color: Colors.transparent,
                  value: 0,
                  selected: currentColor == 0,
                  clear: true,
                ),
                for (final color in _kTimelineRowColorPalette)
                  _buildRowColorChoice(
                    context: ctx,
                    color: color,
                    value: color.toARGB32(),
                    selected: currentColor == color.toARGB32(),
                  ),
              ],
            ),
          );
        },
      );
      if (selectedColor != null) {
        await _setMixRowsColor(_headerControlRows(row), selectedColor);
      }
    }
  }

  Widget _buildRowColorChoice({
    Key? key,
    required BuildContext context,
    required Color color,
    required int value,
    required bool selected,
    bool clear = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap ?? () => Navigator.pop(context, value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: clear ? const Color.fromRGBO(244, 244, 244, 0.08) : color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: clear ? 0.22 : 0.12),
            width: selected ? 2 : 1,
          ),
          boxShadow: clear
              ? null
              : <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: 0.28),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
        ),
        child: clear
            ? Icon(
                Icons.format_color_reset_rounded,
                color: Colors.white.withValues(alpha: 0.74),
                size: 20,
              )
            : (selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 20,
                    )
                  : null),
      ),
    );
  }

  Widget _buildTrackHeadersContent(double dynamicWidth) {
    if (_rowCount == 0) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(
            left: _usesTabletDawLayout ? 31 : 0,
            right: _usesTabletDawLayout ? 10 : 0,
            top: _usesTabletDawLayout ? 10 : 0,
          ),
          child: _usesTabletDawLayout
              ? _buildTabletHeaderFooterButton(
                  label: L10n.translate(context, '+ Audio Row'),
                  semanticLabel: L10n.translate(context, '+ Audio Row'),
                  height: 38,
                  onTap: () => unawaited(widget.onAddRow()),
                )
              : IconButton(
                  onPressed: widget.onAddRow,
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
        ),
      );
    }

    return Column(
      children: [
        if (_masterAutomationLanePaintHeight > 0.0)
          _buildMasterAutomationLaneHeader(dynamicWidth),
        ...List.generate(_rowCount, (row) {
          if (!_isSourceRowVisible(row)) return const SizedBox.shrink();
          final isSelected = row == _selectedRowIndex;
          final isExpanded = _rowExpanded[row];
          final showsAutomationLane =
              _automationTimelineLaneHeightForRow(row) > 0.0;

          return Column(
            children: [
              _buildOneTrackHeader(row, isSelected),
              if (showsAutomationLane)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleAutomationTimelineCollapseForRow(row),
                  child: Container(
                    height: _automationTimelineLaneHeightForRow(row),
                    width: dynamicWidth,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2328),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _isAutomationTimelineCollapsedForRow(row)
                          ? Icon(
                              Icons.unfold_more_rounded,
                              size: 14,
                              color: const Color(0xFFE8AA62),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                L10n.translate(context, 'Automation'),
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Color(0xFFC7CDD4),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              if (isExpanded)
                SizedBox(
                  height: _expandedPanelHeightForRow(row),
                  width: dynamicWidth,
                  child: _buildHeaderTabs(row),
                ),
            ],
          );
        }),
        if (!_usesTabletDawLayout) const SizedBox(height: kHeaderFooterHeight),
        SizedBox(
          height: _usesTabletDawLayout
              ? _kTabletStickyFooterTotalHeight
              : _kAddRowPillHeight +
                    _kAddRowSectionGap +
                    _editorLayoutSpec.bottomInteractionPadding +
                    _kExtraAddRowBottomPadding,
        ),
      ],
    );
  }

  Widget _buildAddRowPill() {
    if (_usesTabletDawLayout) {
      return const SizedBox.shrink();
    }
    return Material(
      key: _addRowPillKey,
      color: Colors.transparent,
      child: InkWell(
        onTap: _showAddRowMenu,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: 116,
          height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color.fromRGBO(109, 123, 140, 0.72),
                Color.fromRGBO(70, 81, 95, 0.78),
              ],
            ),
            color: const Color.fromRGBO(66, 76, 90, 0.52),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.24),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Text(
              L10n.translate(context, 'Add Row'),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabletHeaderFooterButton({
    Key? key,
    required String label,
    required VoidCallback? onTap,
    String? semanticLabel,
    String? badgeLabel,
    double height = 38,
    Color? backgroundColor,
    Color? borderColor,
    Color? textColor,
  }) {
    final enabled = onTap != null;
    final resolvedBackgroundColor =
        backgroundColor ?? Color.fromRGBO(9, 19, 30, enabled ? 0.58 : 0.32);
    final resolvedBorderColor =
        borderColor ?? Colors.white.withValues(alpha: 0.10);
    final resolvedTextColor =
        textColor ?? Colors.white.withValues(alpha: enabled ? 0.86 : 0.40);
    return Semantics(
      key: key,
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              color: resolvedBackgroundColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: resolvedBorderColor),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 8,
                        right: badgeLabel == null ? 8 : 24,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          color: resolvedTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 22 / 12,
                        ),
                      ),
                    ),
                  ),
                ),
                if (badgeLabel != null)
                  Positioned(
                    right: 5,
                    top: 5,
                    child: ExcludeSemantics(
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8AA62),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.54),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          badgeLabel,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: Color(0xFF1A252F),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setTabletRowHeightScale(double value) {
    if (!_usesTabletDawLayout) return;
    final next = value
        .clamp(_kTabletRowHeightMinScale, _kTabletRowHeightMaxScale)
        .toDouble();
    if ((next - _tabletRowHeightScale).abs() < 0.002) return;
    setState(() {
      _tabletRowHeightScale = next;
      _syncVerticalScrollOffsetFromController(clampToExtent: true);
    });
    _syncVerticalScrollOffsetAfterGeometryChange();
  }

  double _tabletRailViewportHeight(double visibleTimelineHeight) {
    return math.max(
      96.0,
      visibleTimelineHeight -
          _kTabletRailTopInset -
          _kTabletFooterControlsBottomPadding,
    );
  }

  double _tabletRailMaxScroll(double visibleTimelineHeight) {
    return math.max(0.0, _scrollContentHeight - visibleTimelineHeight);
  }

  double _tabletRailThumbHeight(double visibleTimelineHeight) {
    final railHeight = _tabletRailViewportHeight(visibleTimelineHeight);
    final maxScroll = _tabletRailMaxScroll(visibleTimelineHeight);
    if (maxScroll <= 0.0) return railHeight;
    final contentHeight = math.max(1.0, _scrollContentHeight);
    final viewportHeight = visibleTimelineHeight.clamp(1.0, contentHeight);
    return (railHeight * (viewportHeight / contentHeight))
        .clamp(44.0, railHeight)
        .toDouble();
  }

  void _jumpTabletVerticalScroll(double offset, double visibleTimelineHeight) {
    if (!_verticalScrollController.hasClients) return;
    final maxScroll = _tabletRailMaxScroll(visibleTimelineHeight);
    final safeOffset = offset.clamp(0.0, maxScroll).toDouble();
    _verticalScrollController.jumpTo(safeOffset);
    _verticalScrollOffset = safeOffset;
  }

  void _handleTabletRailDragStart(
    DragStartDetails details,
    double visibleTimelineHeight,
  ) {
    final railHeight = _tabletRailViewportHeight(visibleTimelineHeight);
    final maxScroll = _tabletRailMaxScroll(visibleTimelineHeight);
    final thumbHeight = _tabletRailThumbHeight(visibleTimelineHeight);
    final thumbTravel = math.max(0.0, railHeight - thumbHeight);
    final thumbTop = maxScroll <= 0.0
        ? 0.0
        : (_verticalScrollOffset / maxScroll * thumbTravel)
              .clamp(0.0, thumbTravel)
              .toDouble();
    final localY = details.localPosition.dy.clamp(0.0, railHeight).toDouble();
    const edgeHitZone = 22.0;

    if (localY >= thumbTop && localY <= thumbTop + thumbHeight) {
      if (localY - thumbTop <= edgeHitZone) {
        _tabletRailDragMode = 'resize_top';
      } else if (thumbTop + thumbHeight - localY <= edgeHitZone) {
        _tabletRailDragMode = 'resize_bottom';
      } else {
        _tabletRailDragMode = 'scroll';
      }
    } else {
      _tabletRailDragMode = 'scroll';
      if (maxScroll > 0.0) {
        final targetTop = (localY - thumbHeight / 2)
            .clamp(0.0, thumbTravel)
            .toDouble();
        _jumpTabletVerticalScroll(
          thumbTravel <= 0.0 ? 0.0 : targetTop / thumbTravel * maxScroll,
          visibleTimelineHeight,
        );
      }
    }

    _tabletRailDragStartScale = _tabletRowHeightScale;
    _tabletRailDragStartScrollOffset = _verticalScrollOffset;
    _tabletRailDragStartGlobalY = details.globalPosition.dy;
    if (mounted) {
      setState(() {});
    }
  }

  void _handleTabletRailDragUpdate(
    DragUpdateDetails details,
    double visibleTimelineHeight,
  ) {
    final dragDy = details.globalPosition.dy - _tabletRailDragStartGlobalY;
    final mode = _tabletRailDragMode;
    if (mode == 'scroll') {
      final railHeight = _tabletRailViewportHeight(visibleTimelineHeight);
      final maxScroll = _tabletRailMaxScroll(visibleTimelineHeight);
      if (maxScroll <= 0.0) return;
      final thumbHeight = _tabletRailThumbHeight(visibleTimelineHeight);
      final thumbTravel = math.max(1.0, railHeight - thumbHeight);
      final scrollDelta = dragDy / thumbTravel * maxScroll;
      _jumpTabletVerticalScroll(
        _tabletRailDragStartScrollOffset + scrollDelta,
        visibleTimelineHeight,
      );
      return;
    }

    if (mode == 'resize_top' || mode == 'resize_bottom') {
      const dragRangePx = 260.0;
      final signedDy = mode == 'resize_top' ? dragDy : -dragDy;
      _setTabletRowHeightScale(
        _tabletRailDragStartScale + signedDy / dragRangePx,
      );
    }
  }

  void _handleTabletRailDragEnd() {
    if (!mounted) {
      _tabletRailDragMode = null;
      return;
    }
    setState(() {
      _tabletRailDragMode = null;
    });
  }

  void _onTabletRailPointerSignal(PointerSignalEvent event) {
    if (_handleTabletRailRowHeightPointerSignal(event)) return;
    _onTimelineLeftChromePointerSignal(event);
  }

  bool _handleTabletRailRowHeightPointerSignal(PointerSignalEvent event) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return false;
    if (event is! PointerScrollEvent) return false;
    if (!PlatformCapabilities.current.isDesktop) return false;
    if (!HardwareKeyboard.instance.isMetaPressed) return false;

    final rawDelta = event.scrollDelta.dy;
    if (rawDelta.abs() < 0.5 || rawDelta.abs() < event.scrollDelta.dx.abs()) {
      return false;
    }

    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolved,
    ) {
      if (resolved is! PointerScrollEvent) return;
      final delta = resolved.scrollDelta.dy;
      if (delta.abs() < 0.5) return;
      _setTabletRowHeightScale(
        _tabletRowHeightScale - delta * _kTabletRailWheelResizeSensitivity,
      );
    });
    return true;
  }

  Widget _buildTabletVerticalCompressionRail(double visibleTimelineHeight) {
    final railHeight = _tabletRailViewportHeight(visibleTimelineHeight);
    final maxScroll = _tabletRailMaxScroll(visibleTimelineHeight);
    final thumbHeight = _tabletRailThumbHeight(visibleTimelineHeight);
    final thumbTravel = math.max(0.0, railHeight - thumbHeight);
    final thumbTop = maxScroll <= 0.0
        ? 0.0
        : (_verticalScrollOffset / maxScroll * thumbTravel)
              .clamp(0.0, thumbTravel)
              .toDouble();
    final rowHeightPercent = (_tabletRowHeightScale * 100.0).round().clamp(
      62,
      100,
    );
    final dragMode = _tabletRailDragMode;
    final anyActive = dragMode != null;
    final resizingTop = dragMode == 'resize_top';
    final resizingBottom = dragMode == 'resize_bottom';
    final resizing = resizingTop || resizingBottom;
    final activeColor = const Color(0xFF7FC9E5);
    final resizeColor = const Color(0xFFFFC66D);
    final stateColor = resizing ? resizeColor : activeColor;
    const railCenterX = _kTabletRailCenterX;
    final railTrackWidth = anyActive ? 6.0 : 4.0;
    final railTrackLeft = math.max(0.0, railCenterX - (railTrackWidth / 2.0));
    final thumbWidth = anyActive ? 15.0 : 12.0;
    final thumbLeft = math.max(0.0, railCenterX - (thumbWidth / 2.0));

    return Semantics(
      slider: true,
      label: L10n.translate(context, 'Rows scrollbar and height'),
      value: '$rowHeightPercent%',
      increasedValue: '${(rowHeightPercent + 8).clamp(62, 100)}%',
      decreasedValue: '${(rowHeightPercent - 8).clamp(62, 100)}%',
      onIncrease: () => _setTabletRowHeightScale(_tabletRowHeightScale + 0.08),
      onDecrease: () => _setTabletRowHeightScale(_tabletRowHeightScale - 0.08),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: _onTabletRailPointerSignal,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onVerticalDragStart: (details) =>
              _handleTabletRailDragStart(details, visibleTimelineHeight),
          onVerticalDragUpdate: (details) =>
              _handleTabletRailDragUpdate(details, visibleTimelineHeight),
          onVerticalDragEnd: (_) => _handleTabletRailDragEnd(),
          onVerticalDragCancel: _handleTabletRailDragEnd,
          child: ExcludeSemantics(
            child: SizedBox(
              width: _kTabletHeaderLedgeX + 4,
              height: railHeight,
              child: Stack(
                alignment: Alignment.topLeft,
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(left: railTrackLeft),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 110),
                          width: railTrackWidth,
                          decoration: BoxDecoration(
                            color: anyActive
                                ? stateColor.withValues(alpha: 0.12)
                                : const Color(
                                    0xFF0A1521,
                                  ).withValues(alpha: 0.17),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: anyActive
                                  ? stateColor.withValues(alpha: 0.20)
                                  : Colors.white.withValues(alpha: 0.06),
                              width: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: thumbTop,
                    left: thumbLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 110),
                      width: thumbWidth,
                      height: thumbHeight,
                      decoration: BoxDecoration(
                        color: anyActive
                            ? const Color(0xFFF4F4F4).withValues(alpha: 0.72)
                            : const Color(0xFFF4F4F4).withValues(alpha: 0.44),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: anyActive
                              ? stateColor.withValues(
                                  alpha: resizing ? 0.66 : 0.52,
                                )
                              : Colors.white.withValues(alpha: 0.09),
                          width: anyActive ? 1.0 : 0.6,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: anyActive
                                ? stateColor.withValues(
                                    alpha: resizing ? 0.24 : 0.16,
                                  )
                                : Colors.black.withValues(alpha: 0.13),
                            blurRadius: resizing ? 15 : (anyActive ? 11 : 4),
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _TabletRailEndCap(
                            active: resizingTop,
                            resizing: resizing,
                          ),
                          Expanded(
                            child: Center(
                              child: Container(
                                width: 2,
                                height: math.max(12.0, thumbHeight * 0.34),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF15436C,
                                  ).withValues(alpha: anyActive ? 0.34 : 0.20),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ),
                          _TabletRailEndCap(
                            active: resizingBottom,
                            resizing: resizing,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabletLeftSectionShell() {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.zero,
          bottomRight: Radius.circular(34),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _kTabletRailLaneColor,
            border: Border(
              right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.25),
                blurRadius: 15,
                spreadRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _tabletGroupAccent(TrackGroup group) {
    if (group.color != 0) {
      return Color(group.color).withValues(alpha: 1.0);
    }
    return const Color(0xFF4ED8E2);
  }

  Widget _buildTabletHeaderFooter(double width) {
    final groupingSelectionCount = widget.groupingSelectedRows
        .where((row) => row >= 0 && row < widget.rows.length)
        .toSet()
        .length;
    final groupingLabel = widget.rowGroupingSelectionMode
        ? groupingSelectionCount >= 2
              ? 'Group'
              : 'Select'
        : 'Group';
    final groupingSemanticLabel = widget.rowGroupingSelectionMode
        ? groupingSelectionCount >= 2
              ? 'Group selected rows'
              : 'Select rows to group'
        : 'Group Rows';
    return SizedBox(
      height: _kTabletStickyFooterTotalHeight,
      child: Stack(
        children: [
          Positioned(
            left: _kTabletHeaderLedgeX,
            top: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    4,
                    11,
                    10,
                    3 + _kTabletStickyFooterBottomInset,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF123D62).withValues(alpha: 0.82),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF2E6E93).withValues(alpha: 0.34),
                        const Color(0xFF123D62).withValues(alpha: 0.72),
                        const Color(0xFF0A1E31).withValues(alpha: 0.80),
                      ],
                    ),
                    border: Border(
                      right: BorderSide(
                        color: Colors.white.withValues(alpha: 0.13),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildTabletHeaderFooterButton(
                              label: L10n.translate(context, '+ Audio Row'),
                              semanticLabel: L10n.translate(
                                context,
                                '+ Audio Row',
                              ),
                              height: _kTabletFooterButtonHeight,
                              onTap: () => unawaited(widget.onAddRow()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTabletHeaderFooterButton(
                              label: L10n.translate(context, '+ MIDI Row'),
                              semanticLabel: L10n.translate(
                                context,
                                '+ MIDI Row',
                              ),
                              height: _kTabletFooterButtonHeight,
                              onTap: widget.onAddInstrumentLane == null
                                  ? null
                                  : () => unawaited(
                                      widget.onAddInstrumentLane!(),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: _kTabletFooterRowGap),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildTabletHeaderFooterButton(
                                key: const ValueKey(
                                  'tablet_footer_group_rows_button',
                                ),
                                label: widget.rowGroupingSelectionMode
                                    ? L10n.translate(
                                        context,
                                        '$groupingLabel Rows',
                                      )
                                    : L10n.translate(context, 'Group Rows'),
                                semanticLabel: L10n.translate(
                                  context,
                                  groupingSemanticLabel,
                                ),
                                badgeLabel:
                                    widget.rowGroupingSelectionMode &&
                                        groupingSelectionCount > 0
                                    ? groupingSelectionCount.toString()
                                    : null,
                                height: _kTabletFooterButtonHeight,
                                onTap: widget.onGroupRowsPressed == null
                                    ? null
                                    : () => unawaited(
                                        widget.onGroupRowsPressed!(),
                                      ),
                              ),
                            ),
                            if (widget.rowGroupingSelectionMode &&
                                widget.onCancelRowGroupingPressed != null) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 72,
                                child: _buildTabletHeaderFooterButton(
                                  key: const ValueKey(
                                    'tablet_footer_cancel_group_rows_button',
                                  ),
                                  label: L10n.translate(context, 'Cancel'),
                                  semanticLabel: L10n.translate(
                                    context,
                                    'Cancel row grouping selection',
                                  ),
                                  height: _kTabletFooterButtonHeight,
                                  backgroundColor: const Color(
                                    0xFF8E3C46,
                                  ).withValues(alpha: 0.64),
                                  borderColor: const Color(
                                    0xFFFFA3AE,
                                  ).withValues(alpha: 0.26),
                                  textColor: const Color(
                                    0xFFFFDDE1,
                                  ).withValues(alpha: 0.96),
                                  onTap: widget.onCancelRowGroupingPressed,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddRowMenu() async {
    if (widget.onAddInstrumentLane == null &&
        widget.onOpenCaptureDeck == null) {
      await widget.onAddRow();
      return;
    }

    final pillContext = _addRowPillKey.currentContext;
    final pillBox = pillContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (pillBox == null || overlayBox == null || !pillBox.attached) {
      await widget.onAddRow();
      return;
    }

    final pillTopLeft = pillBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final pillRect = pillTopLeft & pillBox.size;
    const bubbleWidth = 224.0;
    final actionCount =
        1 +
        (widget.onAddInstrumentLane == null ? 0 : 1) +
        (widget.onOpenCaptureDeck == null ? 0 : 1);
    final bubbleHeight = 56.0 * actionCount;
    const gap = 10.0;
    final overlaySize = overlayBox.size;
    final left = (pillRect.center.dx - bubbleWidth / 2)
        .clamp(8.0, math.max(8.0, overlaySize.width - bubbleWidth - 8.0))
        .toDouble();
    final top = (pillRect.top - bubbleHeight - gap)
        .clamp(8.0, math.max(8.0, overlaySize.height - bubbleHeight - 8.0))
        .toDouble();
    final tailCenterX = (pillRect.center.dx - left)
        .clamp(22.0, bubbleWidth - 22.0)
        .toDouble();

    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: L10n.translate(context, 'Dismiss'),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, _, __) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: bubbleWidth,
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: bubbleWidth,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5F666D),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, 0.28),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildAnchoredAddRowAction(
                            context: ctx,
                            icon: Icons.multitrack_audio,
                            label: L10n.translate(ctx, 'Audio Row'),
                            value: 'audio',
                          ),
                          if (widget.onAddInstrumentLane != null) ...[
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                            _buildAnchoredAddRowAction(
                              context: ctx,
                              icon: Icons.piano_outlined,
                              label: L10n.translate(ctx, 'Instrument Lane'),
                              value: 'instrument',
                            ),
                          ],
                          if (widget.onOpenCaptureDeck != null) ...[
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                            _buildAnchoredAddRowAction(
                              context: ctx,
                              icon: Icons.fiber_manual_record,
                              label: L10n.translate(ctx, 'Capture Deck'),
                              value: 'capture_deck',
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      width: bubbleWidth,
                      height: 10,
                      child: CustomPaint(
                        painter: _AddRowBubbleTailPainter(
                          centerX: tailCenterX,
                          color: const Color(0xFF5F666D),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (ctx, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
    );
    if (action == 'audio') {
      await widget.onAddRow();
    } else if (action == 'instrument') {
      await widget.onAddInstrumentLane?.call();
    } else if (action == 'capture_deck') {
      await widget.onOpenCaptureDeck?.call();
    }
  }

  Widget _buildAnchoredAddRowAction({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, color: _kTimelineShellText, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: _kTimelineShellText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double get _addRowSectionTop => _timelinePaintHeight + kHeaderFooterHeight;

  Widget _buildTabletTrackHeaderButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
    required BorderRadius borderRadius,
    double fontSize = 15,
  }) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          unawaited(AppHaptics.impact(AppHapticImpact.light));
          onTap();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.90)
                : Colors.transparent,
            borderRadius: borderRadius,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Pretendard',
                color: active
                    ? const Color(0xFF15436C)
                    : Colors.white.withValues(alpha: 0.90),
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabletOneTrackHeader(int row, bool isSelected) {
    final isInstrumentLane = _isInstrumentLane(row);
    final groupingMode = widget.rowGroupingSelectionMode;
    final isGroupingSelected = widget.groupingSelectedRows.contains(row);
    final rowGroup = _groupForRow(row);
    final visibilityEntry = _visibilityEntryForSourceRow(row);
    final foldedChildCount =
        visibilityEntry?.hiddenCollapsedSourceRows.length ?? 0;
    final isGroupLeadRow =
        rowGroup != null && visibilityEntry?.isGroupFirstRow == true;
    final isGroupedChildRow = rowGroup != null && !isGroupLeadRow;
    final rowInfo = widget.rows[row];
    final frozenRowDescription = widget.frozenRowDescription?.call(row);
    final rowColor = rowInfo.color;
    final hasExplicitRowColor = rowColor != 0;
    final rowAccent = hasExplicitRowColor
        ? Color(rowColor).withValues(alpha: 1.0)
        : const Color(0xFF6F879B);
    final defaultSurfaceAccent = isInstrumentLane
        ? const Color(0xFF52C9BE)
        : const Color(0xFF6F879B);
    const defaultGroupSurfaceAccent = Color(0xFF4ED8E2);
    final groupAccent = rowGroup == null
        ? defaultGroupSurfaceAccent
        : _tabletGroupAccent(rowGroup);
    final headerSurfaceAccent = isGroupLeadRow
        ? defaultGroupSurfaceAccent
        : defaultSurfaceAccent;
    final hasExplicitGroupColor = isGroupLeadRow && rowGroup.color != 0;
    final showsHeaderColorDot = hasExplicitRowColor || hasExplicitGroupColor;
    final headerColorDotColor = hasExplicitGroupColor ? groupAccent : rowAccent;
    final baseSurface = isGroupLeadRow
        ? const Color(0xFF104A54)
        : isInstrumentLane
        ? const Color(0xFF146B6C)
        : const Color(0xFF123F6A);
    final selectedHeaderSurface = isGroupLeadRow
        ? const Color.fromRGBO(74, 185, 196, 0.94)
        : isInstrumentLane
        ? const Color.fromRGBO(83, 176, 159, 0.94)
        : const Color.fromRGBO(103, 147, 198, 0.94);
    final headerFillColor = isGroupingSelected
        ? const Color(0xFFE8AA62)
        : isSelected
        ? selectedHeaderSurface
        : Color.lerp(
            baseSurface,
            headerSurfaceAccent,
            isGroupLeadRow ? 0.18 : 0.08,
          )!.withValues(alpha: 0.86);
    final headerBorderColor = isGroupLeadRow
        ? defaultGroupSurfaceAccent.withValues(alpha: isSelected ? 0.82 : 0.36)
        : isSelected
        ? Colors.white.withValues(alpha: 0.44)
        : Colors.white.withValues(alpha: 0.10);
    final headerBorderWidth = isSelected ? 1.35 : 1.0;
    final headerControlRows = _headerControlRows(row);
    final headerMuted =
        headerControlRows.isNotEmpty &&
        headerControlRows.every(
          (item) => item >= 0 && item < widget.rowMuted.length
              ? widget.rowMuted[item]
              : false,
        );
    final headerSoloed =
        headerControlRows.isNotEmpty &&
        headerControlRows.every(
          (item) => item >= 0 && item < widget.rowSoloed.length
              ? widget.rowSoloed[item]
              : false,
        );
    final headerMixControlRows = _mixControlRows(row);
    final headerMixGain = _headerGainForRows(headerMixControlRows, row);
    final gainProgress = (headerMixGain / 3.0).clamp(0.0, 1.0).toDouble();
    final headerTitle = isGroupLeadRow
        ? rowGroup.name.trim().isEmpty
              ? 'Group'
              : rowGroup.name.trim()
        : rowInfo.name.trim().isEmpty
        ? 'Track ${row + 1}'
        : rowInfo.name.trim();
    final compactHeader = _rowHeight < 70.0;
    final headerVerticalPadding = compactHeader ? 5.0 : 8.0;
    final headerHorizontalPadding = compactHeader ? 8.0 : 9.0;
    final headerIconBox = compactHeader ? 30.0 : 28.0;
    final headerIconSize = compactHeader ? 23.0 : 24.0;
    final headerTitleFontSize = compactHeader ? 11.5 : 13.0;
    final headerSubtitleFontSize = compactHeader ? 10.0 : 12.0;
    final headerGainGap = compactHeader ? 3.0 : 5.0;
    final headerGainLeftInset = compactHeader ? headerIconBox + 5.0 : 0.0;
    final headerGainSliderHeight = compactHeader ? 18.0 : 22.0;
    const headerColorDotSize = 13.0;
    final headerTitleBandHeight = math
        .max(
          0.0,
          _rowHeight -
              (headerVerticalPadding * 2.0) -
              headerGainGap -
              headerGainSliderHeight,
        )
        .toDouble();
    const headerColorDotVerticalLift = 2.5;
    final headerColorDotTop = math
        .max(
          0.0,
          ((headerTitleBandHeight - headerColorDotSize) / 2.0) -
              headerColorDotVerticalLift,
        )
        .toDouble();
    const controlRadiusTop = BorderRadius.only(
      topLeft: Radius.circular(5),
      topRight: Radius.circular(5),
    );
    const controlRadiusBottom = BorderRadius.only(
      bottomLeft: Radius.circular(5),
      bottomRight: Radius.circular(5),
    );
    Widget headerColorDot() {
      if (!showsHeaderColorDot) {
        return const SizedBox.shrink();
      }
      return Container(
        width: headerColorDotSize,
        height: headerColorDotSize,
        decoration: BoxDecoration(
          color: headerColorDotColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.70),
            width: 1,
          ),
        ),
      );
    }

    Widget headerLeadingIcon() {
      if (isGroupLeadRow) {
        return Align(
          alignment: Alignment.center,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) => _markGroupFoldHeaderPointer(row, event),
            child: Material(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                onTap: null,
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: compactHeader ? 31 : 34,
                  height: compactHeader ? 31 : 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        rowGroup.collapsed
                            ? Icons.folder_rounded
                            : Icons.folder_open_rounded,
                        color: Colors.white,
                        size: compactHeader ? 21 : 23,
                      ),
                      Positioned(
                        right: compactHeader ? -3 : -2,
                        bottom: compactHeader ? -3 : -2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF0D3150,
                            ).withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.74),
                            ),
                          ),
                          child: Icon(
                            rowGroup.collapsed
                                ? Icons.keyboard_arrow_right_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: Colors.white,
                            size: compactHeader ? 15 : 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
      final leadingIcon = isInstrumentLane
          ? Icon(
              Icons.piano_outlined,
              color: Colors.white,
              size: headerIconSize,
            )
          : buildTrackRowIcon(
              rowInfo.iconId,
              size: headerIconSize,
              color: Colors.white,
            );
      return SizedBox(
        width: headerIconBox,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            leadingIcon,
            if (frozenRowDescription != null)
              Positioned(
                right: -5,
                top: -5,
                child: Tooltip(
                  message: frozenRowDescription,
                  child: InkResponse(
                    onTap: () => widget.onFrozenRowInfoPressed?.call(row),
                    radius: 13,
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    Widget selectedExpandCaret() {
      if (!isSelected || groupingMode) {
        return const SizedBox.shrink();
      }
      final rowExpanded = row >= 0 && row < _rowExpanded.length
          ? _rowExpanded[row]
          : false;
      final caretSize = compactHeader ? 15.0 : 16.0;
      return IgnorePointer(
        child: Container(
          width: caretSize,
          height: caretSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            rowExpanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            color: Colors.white.withValues(alpha: 0.88),
            size: compactHeader ? 13.0 : 14.0,
          ),
        ),
      );
    }

    Widget headerGainSlider() {
      return LayoutBuilder(
        builder: (context, constraints) {
          final knobSize = compactHeader ? 12.0 : 16.0;
          final trackHeight = compactHeader ? 10.0 : 12.0;
          final sliderHeight = headerGainSliderHeight;
          final width = constraints.maxWidth;
          final visualInset = knobSize / 2.0 + 3.0;
          final visualWidth = math.max(1.0, width - (visualInset * 2.0));
          final knobLeft =
              (visualInset + visualWidth * gainProgress - knobSize / 2.0)
                  .clamp(0.0, math.max(0.0, width - knobSize))
                  .toDouble();
          void updateGainFromLocalDx(double localDx) {
            _updateHeaderGainFromLocalDx(
              rows: headerMixControlRows,
              localDx: localDx - visualInset,
              width: visualWidth,
            );
          }

          void applyWheelGain(PointerScrollEvent event) {
            final direction = event.scrollDelta.dy.abs() < 1
                ? 0.0
                : event.scrollDelta.dy.sign * -1.0;
            if (direction == 0) return;
            final keyboard = HardwareKeyboard.instance;
            final modifier =
                DesktopSliderWheelSensitivityStore.multiplierForKeyboard(
                  keyboard,
                );
            final next = (headerMixGain + direction * 0.03 * modifier).clamp(
              0.0,
              3.0,
            );
            if ((next - headerMixGain).abs() < 0.000001) return;
            _snapshotMixRowsGain(headerMixControlRows);
            _setMixRowsGainLive(headerMixControlRows, next.toDouble());
            _commitMixRowsGainFromSnapshot(headerMixControlRows);
          }

          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent ||
                  !PlatformCapabilities.current.isDesktop) {
                return;
              }
              GestureBinding.instance.pointerSignalResolver.register(event, (
                resolved,
              ) {
                if (resolved is! PointerScrollEvent) return;
                applyWheelGain(resolved);
              });
            },
            child: GestureDetector(
              key: ValueKey('timeline_tablet_row_gain_$row'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                _snapshotMixRowsGain(headerMixControlRows);
                updateGainFromLocalDx(details.localPosition.dx);
                _commitMixRowsGainFromSnapshot(headerMixControlRows);
              },
              onDoubleTap: () {
                _snapshotMixRowsGain(headerMixControlRows);
                _setMixRowsGainLive(headerMixControlRows, 2.0);
                _commitMixRowsGainFromSnapshot(headerMixControlRows);
              },
              onHorizontalDragStart: (_) {
                _snapshotMixRowsGain(headerMixControlRows);
              },
              onHorizontalDragUpdate: (details) {
                updateGainFromLocalDx(details.localPosition.dx);
              },
              onHorizontalDragEnd: (_) {
                _commitMixRowsGainFromSnapshot(headerMixControlRows);
              },
              onHorizontalDragCancel: () {
                _gainDragStartByRow.clear();
              },
              child: SizedBox(
                height: sliderHeight,
                child: AnimatedBuilder(
                  animation: widget.meters,
                  builder: (_, __) {
                    final frame = row < widget.meters.rows.length
                        ? widget.meters.rows[row]
                        : MeterFrame.zero;
                    return Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _HeaderGainMeterSliderPainter(
                              frame: frame,
                              visualInset: visualInset,
                              trackHeight: trackHeight,
                            ),
                          ),
                        ),
                        Positioned(
                          left: knobLeft,
                          top: (sliderHeight - knobSize) / 2.0,
                          child: Container(
                            width: knobSize,
                            height: knobSize,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF4F4F4),
                              shape: BoxShape.circle,
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Color.fromRGBO(0, 0, 0, 0.34),
                                  blurRadius: 5,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: isGroupLeadRow
          ? '$headerTitle group row'
          : 'Track header $headerTitle',
      child: Listener(
        key: ValueKey('timeline_tablet_row_header_$row'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _handleHeaderPointerDown(row, e),
        onPointerMove: _onHeaderPointerMove,
        onPointerUp: _onHeaderPointerUp,
        onPointerCancel: _onHeaderPointerCancel,
        child: Container(
          height: _rowHeight,
          padding: EdgeInsets.fromLTRB(
            _kTabletHeaderLedgeX,
            0,
            compactHeader ? 5 : 7,
            0,
          ),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.055),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              if (isGroupedChildRow) ...[
                SizedBox(
                  width: 12,
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 2,
                      height: _rowHeight - 26,
                      decoration: BoxDecoration(
                        color: groupAccent.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
              ],
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  height: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    isGroupLeadRow
                        ? headerHorizontalPadding + 2
                        : headerHorizontalPadding + 3,
                    headerVerticalPadding,
                    headerHorizontalPadding,
                    headerVerticalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: headerFillColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: headerBorderColor,
                      width: headerBorderWidth,
                    ),
                    boxShadow: <BoxShadow>[
                      const BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.18),
                        blurRadius: 7,
                        offset: Offset(0, 2),
                      ),
                      if (isSelected)
                        BoxShadow(
                          color: selectedHeaderSurface.withValues(alpha: 0.24),
                          blurRadius: 12,
                          spreadRadius: 0.5,
                          offset: const Offset(0, 0),
                        ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      if (compactHeader)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: headerIconBox,
                          child: headerLeadingIcon(),
                        ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: compactHeader ? headerGainLeftInset : 0,
                              ),
                              child: Row(
                                children: [
                                  if (!compactHeader) ...[
                                    headerLeadingIcon(),
                                    const SizedBox(width: 7),
                                  ],
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: compactHeader ? 0 : 16,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              headerTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontFamily: 'Pretendard',
                                                color: Color(0xFFF4F4F4),
                                                fontSize: headerTitleFontSize,
                                                fontWeight: FontWeight.w700,
                                                height: 1.0,
                                              ),
                                            ),
                                          ),
                                          if (isSelected && !groupingMode) ...[
                                            const SizedBox(width: 4),
                                            selectedExpandCaret(),
                                          ],
                                          if (isGroupLeadRow &&
                                              foldedChildCount > 0) ...[
                                            const SizedBox(width: 5),
                                            Text(
                                              '+$foldedChildCount',
                                              maxLines: 1,
                                              overflow: TextOverflow.fade,
                                              softWrap: false,
                                              style: TextStyle(
                                                fontFamily: 'Pretendard',
                                                color: const Color(0xFFF4F4F4),
                                                fontSize:
                                                    headerSubtitleFontSize,
                                                fontWeight: FontWeight.w700,
                                                height: 1.0,
                                              ),
                                            ),
                                          ],
                                          if (compactHeader &&
                                              showsHeaderColorDot) ...[
                                            const SizedBox(width: 7),
                                            headerColorDot(),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: headerGainGap),
                          Padding(
                            padding: EdgeInsets.only(left: headerGainLeftInset),
                            child: headerGainSlider(),
                          ),
                        ],
                      ),
                      if (!compactHeader && showsHeaderColorDot)
                        Positioned(
                          top: headerColorDotTop,
                          right: 0,
                          child: headerColorDot(),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: compactHeader ? 56 : 31,
                height: math
                    .max(42.0, _rowHeight - 10.0)
                    .clamp(0.0, _rowHeight)
                    .toDouble(),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D3150).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: compactHeader
                      ? Row(
                          children: [
                            Expanded(
                              child: _buildTabletTrackHeaderButton(
                                label: 'M',
                                active: headerMuted,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(5),
                                  bottomLeft: Radius.circular(5),
                                ),
                                fontSize: 13,
                                onTap: () {
                                  final next = !headerMuted;
                                  unawaited(
                                    _setHeaderRowsMuted(
                                      headerControlRows,
                                      next,
                                    ),
                                  );
                                },
                              ),
                            ),
                            Container(
                              width: 1,
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                            Expanded(
                              child: _buildTabletTrackHeaderButton(
                                label: 'S',
                                active: headerSoloed,
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(5),
                                  bottomRight: Radius.circular(5),
                                ),
                                fontSize: 13,
                                onTap: () {
                                  final next = !headerSoloed;
                                  unawaited(
                                    _setHeaderRowsSoloed(
                                      headerControlRows,
                                      next,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: _buildTabletTrackHeaderButton(
                                label: 'M',
                                active: headerMuted,
                                borderRadius: controlRadiusTop,
                                onTap: () {
                                  final next = !headerMuted;
                                  unawaited(
                                    _setHeaderRowsMuted(
                                      headerControlRows,
                                      next,
                                    ),
                                  );
                                },
                              ),
                            ),
                            Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                            Expanded(
                              child: _buildTabletTrackHeaderButton(
                                label: 'S',
                                active: headerSoloed,
                                borderRadius: controlRadiusBottom,
                                onTap: () {
                                  final next = !headerSoloed;
                                  unawaited(
                                    _setHeaderRowsSoloed(
                                      headerControlRows,
                                      next,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (groupingMode)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: isGroupingSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: isGroupingSelected ? 0.90 : 0.40,
                        ),
                        width: 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: isGroupingSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: Color(0xFF2E3742),
                            size: 14,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOneTrackHeader(int row, bool isSelected) {
    if (_usesTabletDawLayout) {
      return _buildTabletOneTrackHeader(row, isSelected);
    }
    final isInstrumentLane = _isInstrumentLane(row);
    final groupingMode = widget.rowGroupingSelectionMode;
    final isGroupingSelected = widget.groupingSelectedRows.contains(row);
    final rowGroup = _groupForRow(row);
    final visibilityEntry = _visibilityEntryForSourceRow(row);
    final foldedChildCount =
        visibilityEntry?.hiddenCollapsedSourceRows.length ?? 0;
    final isGroupLeadRow =
        rowGroup != null && visibilityEntry?.isGroupFirstRow == true;
    final isGroupedChildRow = rowGroup != null && !isGroupLeadRow;
    final rowColor = row >= 0 && row < widget.rows.length
        ? widget.rows[row].color
        : 0;
    final rowAccent = rowColor == 0
        ? null
        : Color(rowColor).withValues(alpha: 1.0);
    final frozenRowDescription = widget.frozenRowDescription?.call(row);
    final headerControlRows = _headerControlRows(row);
    final headerMuted =
        headerControlRows.isNotEmpty &&
        headerControlRows.every(
          (item) => item >= 0 && item < widget.rowMuted.length
              ? widget.rowMuted[item]
              : false,
        );
    final headerSoloed =
        headerControlRows.isNotEmpty &&
        headerControlRows.every(
          (item) => item >= 0 && item < widget.rowSoloed.length
              ? widget.rowSoloed[item]
              : false,
        );
    const double iconStripWidth = 44;
    const double controlPillHeight = 72;
    const BorderRadius muteButtonRadius = BorderRadius.only(
      topLeft: Radius.circular(5),
      topRight: Radius.circular(5),
    );
    const BorderRadius soloButtonRadius = BorderRadius.only(
      bottomLeft: Radius.circular(5),
      bottomRight: Radius.circular(5),
    );
    Widget muteButton = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final newVal = !headerMuted;
          unawaited(_setHeaderRowsMuted(headerControlRows, newVal));
        },
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        borderRadius: muteButtonRadius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: headerMuted
                ? const Color.fromRGBO(103, 147, 198, 0.42)
                : Colors.transparent,
            borderRadius: muteButtonRadius,
          ),
          child: Text(
            'M',
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: headerMuted
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.72),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );

    if (widget.tutorialHighlighter != null) {
      muteButton = MultiHalo(
        highlighter: widget.tutorialHighlighter!,
        haloKeys: <HaloKey>[
          const HaloKey('tutorial:mute'),
          HaloKey('row:$row:mute'),
          HaloKey('row:$row:header:mute'),
        ],
        borderRadius: BorderRadius.circular(4),
        child: muteButton,
      );
    }

    Widget soloButton = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final newVal = !headerSoloed;
          unawaited(_setHeaderRowsSoloed(headerControlRows, newVal));
        },
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        borderRadius: soloButtonRadius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: headerSoloed
                ? const Color.fromRGBO(183, 127, 63, 0.42)
                : Colors.transparent,
            borderRadius: soloButtonRadius,
          ),
          child: Text(
            'S',
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: headerSoloed
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.72),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );

    if (widget.tutorialHighlighter != null) {
      soloButton = MultiHalo(
        highlighter: widget.tutorialHighlighter!,
        haloKeys: <HaloKey>[
          const HaloKey('tutorial:solo'),
          HaloKey('row:$row:solo'),
          HaloKey('row:$row:header:solo'),
        ],
        borderRadius: BorderRadius.circular(4),
        child: soloButton,
      );
    }

    Widget header = Listener(
      key: ValueKey('timeline_row_header_$row'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _handleHeaderPointerDown(row, e),
      onPointerMove: _onHeaderPointerMove,
      onPointerUp: _onHeaderPointerUp,
      onPointerCancel: _onHeaderPointerCancel,
      child: Container(
        height: _rowHeight,
        decoration: BoxDecoration(
          // Keep the header lane transparent so waveform/MIDI content can
          // remain visible under the M/S pill area.
          color: Colors.transparent,
          border: Border(
            bottom: BorderSide(color: _kTimelineRowDivider, width: 1),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: iconStripWidth,
              child: Container(
                height: double.infinity,
                color: isGroupingSelected
                    ? const Color.fromRGBO(232, 170, 98, 0.96)
                    : isSelected
                    ? (isInstrumentLane
                          ? const Color.fromRGBO(83, 176, 159, 0.94)
                          : const Color.fromRGBO(103, 147, 198, 0.94))
                    : (isInstrumentLane
                          ? const Color.fromRGBO(20, 96, 84, 0.88)
                          : const Color.fromRGBO(22, 64, 105, 0.82)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (rowAccent != null)
                      Container(
                        width: 16,
                        height: 3,
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: rowAccent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    isInstrumentLane
                        ? const Icon(
                            Icons.piano_outlined,
                            color: Colors.white,
                            size: 20,
                          )
                        : buildTrackRowIcon(
                            widget.rows[row].iconId,
                            size: 20,
                            color: Colors.white,
                          ),
                    if (frozenRowDescription != null)
                      Tooltip(
                        message: frozenRowDescription,
                        child: InkResponse(
                          onTap: () => widget.onFrozenRowInfoPressed?.call(row),
                          radius: 12,
                          child: Icon(
                            Icons.info_outline_rounded,
                            color: Colors.white.withValues(alpha: 0.92),
                            size: 14,
                          ),
                        ),
                      ),
                    if (isInstrumentLane)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Container(
                          width: 18,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    if (groupingMode) ...[
                      const SizedBox(height: 2),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: isGroupingSelected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: isGroupingSelected ? 0.90 : 0.40,
                            ),
                            width: 1.2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: isGroupingSelected
                            ? const Icon(
                                Icons.check_rounded,
                                color: Color(0xFF2E3742),
                                size: 13,
                              )
                            : null,
                      ),
                    ] else if (isSelected) ...[
                      const SizedBox(height: 1),
                      Icon(
                        _rowExpanded[row]
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.white.withValues(alpha: 0.84),
                        size: 12,
                      ),
                    ],
                    if (isGroupLeadRow) ...[
                      const SizedBox(height: 2),
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) =>
                            _markGroupFoldHeaderPointer(row, event),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: null,
                            child: Container(
                              height: 22,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.28),
                                ),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: const Color(
                                      0xFF4ED8E2,
                                    ).withValues(alpha: 0.20),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      rowGroup.collapsed
                                          ? Icons.keyboard_arrow_right_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    if (foldedChildCount > 0) ...[
                                      const SizedBox(width: 2),
                                      Text(
                                        '+$foldedChildCount',
                                        maxLines: 1,
                                        softWrap: false,
                                        style: const TextStyle(
                                          fontFamily: 'Pretendard',
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          height: 1.0,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else if (isGroupedChildRow) ...[
                      const SizedBox(height: 3),
                      Container(
                        width: 17,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF4ED8E2,
                          ).withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
            SizedBox(
              width: 31,
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  height: controlPillHeight,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(56, 63, 71, 0.92),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(child: muteButton),
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                      Expanded(child: soloButton),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.tutorialHighlighter != null) {
      header = MultiHalo(
        highlighter: widget.tutorialHighlighter!,
        haloKeys: <HaloKey>[HaloKey('row:$row'), HaloKey('row:$row:header')],
        borderRadius: BorderRadius.circular(6),
        child: header,
      );
    }
    return header;
  }

  // Widget _buildHeaderTabs(int row) {
  //   return Container(
  //     // height: kRowHeight, // Fixed height
  //     // padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  //     decoration: BoxDecoration(
  //       color: const Color.fromARGB(255, 30, 41, 65),
  //       // border: const Border(
  //       //   bottom: BorderSide(color: Color(0xFF1A1F2E), width: 1),
  //       // ),
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Padding(
  //           padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               _buildTabButton(row, 0, "Volume"),
  //               const SizedBox(height: 6),
  //               _buildTabButton(row, 1, "Effects"),
  //             ],
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildHeaderTabs(int row) {
    Widget tabletTabButton(
      int tab,
      String label,
      IconData icon, {
      bool expand = true,
      double? height,
    }) {
      final selected = _normalizeExpandedTab(_expandedTab[row]) == tab;
      final button = Semantics(
        button: true,
        selected: selected,
        label: L10n.translate(context, label),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _setExpandedTabForRow(row: row, tab: tab),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 13,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.95)
                        : Colors.white.withValues(alpha: 0.68),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      L10n.translate(context, label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        color: selected
                            ? Colors.white.withValues(alpha: 0.95)
                            : Colors.white.withValues(alpha: 0.68),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (expand) return Expanded(child: button);
      return SizedBox(width: double.infinity, height: height, child: button);
    }

    Widget tabletTabStrip({bool fillHeight = false}) {
      const tabletHeaderLeftInset = _kTabletHeaderLedgeX;
      Widget buildVerticalStrip({required double contentHeight}) {
        final children = <Widget>[
          tabletTabButton(0, 'Volume', Icons.tune_rounded),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
          tabletTabButton(1, 'Effects', Icons.graphic_eq_rounded),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
          tabletTabButton(2, 'Automation', Icons.timeline_rounded),
        ];
        return Padding(
          padding: EdgeInsets.fromLTRB(tabletHeaderLeftInset, 10, 8, 8),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              width: double.infinity,
              height: contentHeight,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Column(mainAxisSize: MainAxisSize.max, children: children),
            ),
          ),
        );
      }

      if (fillHeight) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 134.0;
            final contentHeight = math.min(
              116.0,
              math.max(0.0, availableHeight - 18.0),
            );
            return buildVerticalStrip(contentHeight: contentHeight);
          },
        );
      }

      final children = fillHeight
          ? <Widget>[]
          : <Widget>[
              tabletTabButton(0, 'Volume', Icons.tune_rounded),
              Container(width: 1, color: Colors.white.withValues(alpha: 0.07)),
              tabletTabButton(1, 'Effects', Icons.graphic_eq_rounded),
              Container(width: 1, color: Colors.white.withValues(alpha: 0.07)),
              tabletTabButton(2, 'Automation', Icons.timeline_rounded),
            ];
      return Padding(
        padding: fillHeight
            ? EdgeInsets.fromLTRB(tabletHeaderLeftInset, 10, 8, 8)
            : const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            width: double.infinity,
            height: fillHeight ? 116 : 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: fillHeight
                ? Column(mainAxisSize: MainAxisSize.min, children: children)
                : Row(children: children),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF20242A), Color(0xFF181C21)],
        ),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boundedHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : _effectsPanelMinHeight;
          final headerDbfsReadoutWidth = constraints.maxWidth.isFinite
              ? (constraints.maxWidth - 12.0).clamp(60.0, 86.0).toDouble()
              : 72.0;
          if (_usesTabletDawLayout) {
            final meterColumnWidth = constraints.maxWidth.isFinite
                ? (constraints.maxWidth * 0.28).clamp(58.0, 76.0).toDouble()
                : 68.0;
            final meterReadoutWidth = (meterColumnWidth - 2.0)
                .clamp(56.0, 74.0)
                .toDouble();
            return SizedBox(
              height: boundedHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 3, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tabletTabStrip(fillHeight: true)),
                    SizedBox(
                      width: meterColumnWidth,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 7, 0, 7),
                        child: AnimatedBuilder(
                          animation: widget.meters,
                          builder: (_, __) {
                            final f = row < widget.meters.rows.length
                                ? widget.meters.rows[row]
                                : MeterFrame.zero;
                            final heldPeakDb = _heldPeakDbForHeaderRow(row, f);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, meterConstraints) {
                                      final meterHeight =
                                          meterConstraints.maxHeight.isFinite
                                          ? math.max(
                                              0.0,
                                              meterConstraints.maxHeight,
                                            )
                                          : _kHeaderMeterHeight;
                                      return Align(
                                        alignment: Alignment.center,
                                        child: MiniStereoMeterPro(
                                          frame: f,
                                          height: meterHeight,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: _kHeaderDbfsReadoutGap),
                                HeaderDbfsReadoutPro(
                                  label: _headerPeakLevelLabel(heldPeakDb),
                                  color: _headerPeakLevelColor(heldPeakDb),
                                  width: meterReadoutWidth,
                                  height: _kHeaderDbfsReadoutHeight,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: boundedHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_usesTabletDawLayout)
                      tabletTabStrip()
                    else ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTabButton(row, 0, "Volume"),
                            const SizedBox(height: 6),
                            _buildTabButton(row, 1, "Effects"),
                            const SizedBox(height: 6),
                            _buildTabButton(row, 2, "Automation"),
                          ],
                        ),
                      ),
                    ],
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: _usesTabletDawLayout ? 7 : 8,
                        ),
                        child: AnimatedBuilder(
                          animation: widget.meters,
                          builder: (_, __) {
                            final f = row < widget.meters.rows.length
                                ? widget.meters.rows[row]
                                : MeterFrame.zero;
                            final heldPeakDb = _heldPeakDbForHeaderRow(row, f);
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MiniStereoMeterPro(
                                  frame: f,
                                  height: _kHeaderMeterHeight,
                                ),
                                const SizedBox(height: _kHeaderDbfsReadoutGap),
                                HeaderDbfsReadoutPro(
                                  label: _headerPeakLevelLabel(heldPeakDb),
                                  color: _headerPeakLevelColor(heldPeakDb),
                                  width: headerDbfsReadoutWidth,
                                  height: _kHeaderDbfsReadoutHeight,
                                ),
                                const SizedBox(height: _kHeaderBottomPadding),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // === FIX ===: New unified gesture handlers
  void _onScaleStart(ScaleStartDetails details) {
    _tutorialPanStartScrollMs = _scrollOffsetMs;
    _tutorialPanStartPixelsPerMs = _pixelsPerMs;
    _tutorialScrollNotifiedForGesture = false;
    _tutorialZoomNotifiedForGesture = false;
    if (_timelineHasMultiTouch) {
      _clearPendingSelectionBox();
      _clearPastePopup();
      setState(() {
        _clearSelectionBoxGestureState();
        _clearPendingClipTapState();
        _clearPendingAutomationClipSelection();
        _clearAutomationClipMenu();
        _isUserInteracting = true;
        _interactionMode = 'pan';
        _initialPixelsPerMs = _pixelsPerMs;
        _initialScrollMs = _scrollOffsetMs;
      });
      return;
    }
    if (_pendingSelectionBoxPointer != null || _selectionBoxActive) {
      _isUserInteracting = false;
      _interactionMode = '';
      _clearPendingClipDrag();
      return;
    }
    if (_interactionMode == 'automation') {
      return;
    }
    if (_activeTool == _TimelineTool.cut &&
        _getClipIndexAt(details.localFocalPoint) != null) {
      _isUserInteracting = false;
      _interactionMode = '';
      return;
    }
    if (_activeTool == _TimelineTool.delete) {
      _isUserInteracting = false;
      _interactionMode = '';
      return;
    }

    _isUserInteracting = true;
    _initialPixelsPerMs = _pixelsPerMs;
    _initialScrollMs = _scrollOffsetMs;

    _clearPastePopup();
    _dragDeltaMs = 0.0;
    _dragDeltaRows = 0;

    if (_activeTool == _TimelineTool.paint) {
      final selected = _activeSelectedClipIndices();
      final topIndex = _getClipIndexAt(details.localFocalPoint);
      final bool tappedSelectedClip =
          topIndex != null && selected.contains(topIndex);
      if (tappedSelectedClip) {
        // Let selected clips keep normal move/trim interactions in paint mode.
      } else {
        if (!widget.hasCopiedClip) {
          _isUserInteracting = false;
          _interactionMode = '';
          _showPaintClipboardHint();
          return;
        }
        _interactionMode = 'paint';
        if (!_paintStrokeActive) {
          _resetPaintStrokeState();
          _startPaintStroke(details.localFocalPoint);
        }
        return;
      }

      if (!widget.hasCopiedClip) {
        // No clipboard is fine here if user is interacting a selected clip.
      }
    }

    if (_selectionBoxActive) {
      _isUserInteracting = false;
      _interactionMode = '';
      _clearPendingClipDrag();
      return;
    }

    // === 1. TRIM HANDLE WAS TAPPED? → Start trim mode immediately ===
    if (_trimClipIndex != null && _activeTrimHandleX != null) {
      final clip = widget.clips[_trimClipIndex!];
      final clipRect = _getClipRect(_trimClipIndex!);
      if (clipRect == null) return;
      final isTrimStart =
          (_activeTrimHandleX! - clipRect.left).abs() <=
          (_activeTrimHandleX! - clipRect.right).abs();

      if (_isStretchToolForClip(clip)) {
        _interactionMode = isTrimStart ? 'stretch-start' : 'stretch-end';
        _stretchClipIndex = _trimClipIndex;
        _stretchStartTimelineDurationMs = widget.getTimelineDurationMs(clip);
        _stretchOriginalStartMs = widget.getStartMs(clip);
        _stretchStartAnchorX = details.localFocalPoint.dx;
        _stretchDurationUpdateMs = _stretchStartTimelineDurationMs;
      } else {
        _interactionMode = isTrimStart ? 'trim-start' : 'trim-end';
        _trimStartValue = widget.getTrimStartMs(clip);
        _trimEndValue = widget.getTrimEndMs(clip);
        _trimOriginalStartMs = widget.getStartMs(clip);
        _trimStartAnchorX = details.localFocalPoint.dx;
        _trimTimelineScaleValue = _trimTimelineScaleForClip(
          clip,
          trimStartMs: _trimStartValue!,
          trimEndMs: _trimEndValue!,
        );
        newTrimStartUpdate = _trimStartValue;
        newTrimEndUpdate = _trimEndValue;
        newStartMsUpdate = null;
      }

      setState(() {});
      return; // EXIT EARLY — trim takes full control
    }

    // === 2. DRAG WAS INITIATED IN tapDown? → Continue drag ===
    if (_pendingDrag && _draggedClipIndex != null) {
      return;
    }
    if (_pendingAutomationClipVisual != null &&
        _dragStartGlobalOffset != null) {
      return;
    }
    if (_interactionMode == 'drag' && _draggedClipIndex != null) {
      // Already in drag mode — just continue
      return;
    }

    // --- STEP 3: No committed clip interaction, start Panning/Zooming ---
    // Tentative first-touch clip selection is restored only after movement
    // crosses drag slop. That lets a true tap commit on tap-up without
    // notifying parent selection during swipe setup.
    _interactionMode = 'pan';
    _initialScrollMs = _scrollOffsetMs;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_pendingSelectionBoxPointer != null || _selectionBoxActive) {
      return;
    }
    if (_activeTool == _TimelineTool.cut && _cutPreviewClipIndex != null) {
      return;
    }
    if (_activeTool == _TimelineTool.delete && _deleteStrokeActive) {
      return;
    }
    if (_timelineHasMultiTouch &&
        _interactionMode != 'automation' &&
        _interactionMode != 'paint') {
      if (_pendingDrag ||
          _pendingAutomationClipVisual != null ||
          _interactionMode != 'pan') {
        setState(() {
          _restoreTentativeClipSelectionIfNeeded();
          _clearPendingClipTapState();
          _clearPendingAutomationClipSelection();
          _clearAutomationClipMenu();
          _isUserInteracting = true;
          _interactionMode = 'pan';
          _draggedClipIndex = null;
        });
      }
      _handlePanZoomUpdate(details);
      return;
    }
    if (_pendingAutomationClipVisual != null &&
        _dragStartGlobalOffset != null) {
      final pendingMode = _pendingAutomationClipInteractionMode ?? 'open';
      final dragDistance =
          (details.focalPoint - _dragStartGlobalOffset!).distance;
      const dragStartTolerance = 10.0;
      if (dragDistance <= dragStartTolerance) {
        return;
      }
      final pendingAutomationClip = _pendingAutomationClipVisual!;
      if (pendingMode == 'open') {
        setState(() {
          _clearPendingAutomationClipSelection();
          _clearAutomationClipMenu();
          _isUserInteracting = true;
          _interactionMode = 'pan';
          _initialPixelsPerMs = _pixelsPerMs;
          _initialScrollMs = _scrollOffsetMs;
        });
        _handlePanZoomUpdate(details);
        return;
      }
      setState(() {
        _clearPendingAutomationClipSelection();
        _clearAutomationClipMenu();
        _isUserInteracting = true;
        _beginAutomationClipDrag(
          pendingAutomationClip.row,
          pendingAutomationClip.targetId,
          pendingAutomationClip.clip,
          _pendingAutomationClipStartLocalOffset ??
              (details.localFocalPoint - pendingAutomationClip.rect.topLeft),
          pendingAutomationClip.rect.width,
          pendingMode,
        );
        _interactionMode = switch (_automationClipDragMode) {
          'trim_start' => 'trim-start',
          'trim_end' => 'trim-end',
          _ => 'drag',
        };
      });
      final row = _automationClipDragRow;
      final targetId = _automationClipDragTargetId;
      final draggedClip = _activeDraggedAutomationClip();
      if (row != null && targetId != null && draggedClip != null) {
        _updateAutomationClipDrag(
          row,
          targetId,
          draggedClip,
          details.focalPoint.dx - _dragStartGlobalOffset!.dx,
          details.localFocalPoint,
        );
      }
      return;
    }
    if (_pendingDrag &&
        _draggedClipIndex != null &&
        _dragStartGlobalOffset != null) {
      if (!_pendingClipDragExceededSlop(details.focalPoint)) {
        return;
      }
      setState(() {
        _clearPendingClipDrag();
        _isUserInteracting = true;
        _interactionMode = 'drag';
        _clipPopupMs = null;
        _dragDeltaMs = 0.0;
        _dragDeltaRows = 0;
        _dragXAxisLocked = false;
        _dragGroupStartMs.clear();
        _dragGroupStartRows.clear();
        final draggedIndex = _draggedClipIndex;
        if (draggedIndex != null &&
            draggedIndex >= 0 &&
            draggedIndex < widget.clips.length) {
          final draggingGroup =
              _selectedClipIndices.length > 1 &&
              _selectedClipIndices.contains(draggedIndex);
          if (draggingGroup) {
            final selected = _activeSelectedClipIndices();
            for (final index in selected) {
              _dragGroupStartMs[index] = widget.getStartMs(widget.clips[index]);
              _dragGroupStartRows[index] = widget.clips[index].rowIndex;
            }
          }
        }
      });
    }
    if (_tentativeClipSelectionActive &&
        (_dragStartGlobalOffset == null ||
            _pendingClipDragExceededSlop(details.focalPoint))) {
      setState(_restoreTentativeClipSelectionIfNeeded);
    }
    if (!_isUserInteracting) return;

    if (_interactionMode == 'automation') return;

    if (_interactionMode == 'paint') {
      _continuePaintStroke(details.localFocalPoint);
      return;
    }

    switch (_interactionMode) {
      case 'drag':
        _handleDragUpdate(details);
        break;
      case 'trim-start':
      case 'trim-end':
        _handleTrimUpdate(details);
        break;
      case 'stretch-start':
      case 'stretch-end':
        _handleStretchUpdate(details);
        break;
      case 'pan':
      default:
        _handlePanZoomUpdate(details);
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) async {
    if (_interactionMode == 'automation') {
      setState(() {
        _interactionMode = '';
        _isUserInteracting = false;
      });
      return;
    }

    if (_interactionMode == 'paint') {
      setState(() {
        _resetPaintStrokeState();
        _interactionMode = '';
        _isUserInteracting = false;
      });
      return;
    }

    if (_tentativeClipSelectionActive) {
      setState(() {
        if (_commitTentativeTapSelectionIfNeeded()) {
          _suppressNextTimelineTapAfterTentativeSelectionCommit = true;
        }
      });
      return;
    }

    if (_interactionMode == 'drag' && _draggedClipIndex != null) {
      final selected = _activeSelectedClipIndices();
      final draggingGroup =
          selected.length > 1 &&
          selected.contains(_draggedClipIndex!) &&
          _dragGroupStartMs.isNotEmpty &&
          _dragGroupStartRows.isNotEmpty;
      if (draggingGroup) {
        final moves = <TimelineClipMoveRequest>[];
        for (final index in selected) {
          final baseMs = _dragGroupStartMs[index];
          final baseRow = _dragGroupStartRows[index];
          if (baseMs == null || baseRow == null) continue;
          final nextStartMs =
              (_dragXAxisLocked
                      ? baseMs
                      : _quantizeMsForTimelineClipDrag(baseMs + _dragDeltaMs))
                  .clamp(0.0, double.infinity);
          final nextRow = (baseRow + _dragDeltaRows)
              .clamp(0, math.max(0, _rowCount - 1))
              .toInt();
          if (!_rowAllowsClip(nextRow, widget.clips[index])) {
            moves.clear();
            break;
          }
          moves.add(
            TimelineClipMoveRequest(
              clipIndex: index,
              newStartMs: nextStartMs,
              newRowIndex: nextRow,
            ),
          );
        }
        if (moves.isNotEmpty && widget.onMoveClipsCommit != null) {
          await widget.onMoveClipsCommit!(moves);
        } else {
          for (final move in moves) {
            await widget.onMoveClipCommit(
              move.clipIndex,
              move.newStartMs,
              move.newRowIndex,
            );
          }
        }
      } else {
        final nextRow = _dragStartRow!;
        if (_rowAllowsClip(nextRow, widget.clips[_draggedClipIndex!])) {
          await widget.onMoveClipCommit(
            _draggedClipIndex!,
            _dragStartClipMs!,
            nextRow,
          );
        }
      }
    } else if (_interactionMode == 'drag' && _hasActiveAutomationClipDrag) {
      final row = _automationClipDragRow;
      final targetId = _automationClipDragTargetId;
      if (row != null && targetId != null) {
        _endAutomationClipDrag(row, targetId);
      }
    }

    if (_interactionMode == 'trim-start' || _interactionMode == 'trim-end') {
      if (_hasActiveAutomationClipDrag) {
        final row = _automationClipDragRow;
        final targetId = _automationClipDragTargetId;
        if (row != null && targetId != null) {
          _endAutomationClipDrag(row, targetId);
        }
      } else {
        if (newStartMsUpdate != null) {
          widget.onTrimClipCommit(
            _trimClipIndex!,
            newTrimStartUpdate!,
            newTrimEndUpdate!,
            _trimStartValue!,
            _trimEndValue!,
            _trimOriginalStartMs!,
            newStartMs: newStartMsUpdate,
          );
        } else {
          widget.onTrimClipCommit(
            _trimClipIndex!,
            newTrimStartUpdate!,
            newTrimEndUpdate!,
            _trimStartValue!,
            _trimEndValue!,
            _trimOriginalStartMs!,
          );
        }
      }
    }

    if ((_interactionMode == 'stretch-start' ||
            _interactionMode == 'stretch-end') &&
        _stretchClipIndex != null &&
        _stretchDurationUpdateMs != null) {
      await widget.onStretchClipCommit(_stretchClipIndex!);
    }

    if (_interactionMode == 'pan') {
      // Request a final scrub
      if (!PlatformCapabilities.current.isDesktop) {
        final playheadPx = _getPlayheadPx(context);
        widget.onScrubRequested(_scrollOffsetMs + playheadPx / _pixelsPerMs);
      }
    }

    // Reset all interaction states
    setState(() {
      _clearPendingClipDrag();
      _isUserInteracting = false;
      _interactionMode = '';
      _draggedClipIndex = null;
      _pendingDragStartedFromSelection = false;
      _dragStartLocalOffset = null;
      _dragGroupStartMs.clear();
      _dragGroupStartRows.clear();
      _timelineKeyboardModifierPointer = null;
      _dragXAxisLocked = false;
      // _dragStartClipMs and _dragStartRow are kept for the painter until commit
      // _activeTrimHandleX = null;
      _trimClipIndex = null;
      _trimStartValue = null;
      _trimEndValue = null;
      _trimOriginalStartMs = null;
      _trimStartAnchorX = null; // === FIX ===
      _trimTimelineScaleValue = null;
      newTrimStartUpdate = null;
      newTrimEndUpdate = null;
      newStartMsUpdate = null;
      _stretchClipIndex = null;
      _stretchStartTimelineDurationMs = null;
      _stretchOriginalStartMs = null;
      _stretchStartAnchorX = null;
      _stretchDurationUpdateMs = null;
      _initialPixelsPerMs = null;
      _initialScrollMs = null;
      _dragDeltaMs = 0.0;
      _dragDeltaRows = 0;
      _dragXAxisLocked = false;
    });
  }

  void _onTimelineLongPressStart(LongPressStartDetails details) {
    _clearPendingAutomationClipSelection();
    if (_activeTool == _TimelineTool.pencil &&
        _canShowInstrumentLaneRegionMenuAt(details.localPosition)) {
      _showInstrumentLaneRegionMenuAt(details.localPosition);
      return;
    }
    if (_activeTool != _TimelineTool.pencil &&
        _activeTool != _TimelineTool.stretch) {
      return;
    }
    if (_interactionMode == 'automation' || _hasActiveAutomationClipDrag) {
      return;
    }
    final tappedAutomationClip = _timelineAutomationClipAt(
      details.localPosition,
    );
    if (tappedAutomationClip != null) {
      widget.setSelectedAutomationTargetId(
        tappedAutomationClip.row,
        tappedAutomationClip.targetId,
      );
      setState(() {
        _clearClipSelection();
        _setSelectedAutomationClipFor(
          tappedAutomationClip.row,
          tappedAutomationClip.targetId,
          tappedAutomationClip.clip.id,
          lane: tappedAutomationClip.clip.lane,
        );
        _setAutomationClipMenuFor(tappedAutomationClip);
      });
      return;
    }
    if (!_canStartSelectionBoxAt(
      details.localPosition,
      allowStartingOverClip: true,
    )) {
      return;
    }
    setState(() {
      _resetTrimInteractionState();
      _clearPastePopup();
      _touchMultiSelectMode = true;
      _beginSelectionBoxAt(details.localPosition, showArmIndicator: true);
    });
    unawaited(AppHaptics.impact(AppHapticImpact.medium));
  }

  void _onTimelineLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_selectionBoxActive) return;
    setState(() {
      _selectionBoxCurrent = details.localPosition;
      final rect = _currentSelectionRect();
      if (rect != null) {
        _updateSelectionFromRect(rect);
        _maybeHideSelectionArmIndicatorForRect(rect);
      }
    });
  }

  void _onTimelineLongPressEnd(LongPressEndDetails details) {
    if (!_selectionBoxActive && _selectionArmIndicatorAt == null) return;
    setState(() {
      _clearSelectionBoxGestureState();
      _suppressImmediateTapAfterSelectionBox();
    });
  }

  // --- Drag/Trim/Pan Handlers ---

  void _handleDragUpdate(ScaleUpdateDetails details) {
    if (_selectionBoxActive || _pendingSelectionBoxPointer != null) {
      return;
    }
    if (_hasActiveAutomationClipDrag) {
      final row = _automationClipDragRow;
      final targetId = _automationClipDragTargetId;
      final draggedClip = _activeDraggedAutomationClip();
      if (row != null && targetId != null && draggedClip != null) {
        _updateAutomationClipDrag(
          row,
          targetId,
          draggedClip,
          details.focalPointDelta.dx,
          details.localFocalPoint,
        );
      }
      return;
    }
    final draggedIndex = _draggedClipIndex;
    if (draggedIndex == null || _dragStartGlobalOffset == null) return;
    if (draggedIndex < 0 || draggedIndex >= widget.clips.length) {
      setState(_cancelClipGestureAfterTopologyChange);
      return;
    }

    setState(() {
      final draggedClip = widget.clips[draggedIndex];

      // Calculate TOTAL delta from drag start (for row)
      final totalDx = details.focalPoint.dx - _dragStartGlobalOffset!.dx;
      final xLocked = _timelineClipDragXAxisLockPressed;
      _dragXAxisLocked = xLocked;

      // Convert to delta in Ms
      final deltaMs = xLocked ? 0.0 : totalDx / _pixelsPerMs;
      _dragDeltaMs = deltaMs;

      // Convert total vertical displacement to row index
      // Use the *original* row index to calculate the new one based on total vertical drag
      final draggingGroup =
          _selectedClipIndices.length > 1 &&
          _selectedClipIndices.contains(draggedIndex) &&
          _dragGroupStartMs.isNotEmpty &&
          _dragGroupStartRows.isNotEmpty;
      final originalRow = draggingGroup
          ? (_dragGroupStartRows[draggedIndex] ?? draggedClip.rowIndex)
          : draggedClip.rowIndex;
      final originalStartMs = draggingGroup
          ? (_dragGroupStartMs[draggedIndex] ?? widget.getStartMs(draggedClip))
          : widget.getStartMs(draggedClip);
      final hoveredRow = _rowForLocalY(details.localFocalPoint.dy);
      int newRow =
          hoveredRow ??
          (details.localFocalPoint.dy < 0 ? 0 : math.max(0, _rowCount - 1));
      _dragDeltaRows = newRow - originalRow;

      // Update the *temporary* drag state
      // The painter will use these values to draw the ghost clip
      _dragStartClipMs = xLocked
          ? originalStartMs
          : _quantizeMsForTimelineClipDrag(
              originalStartMs + deltaMs,
            ); // === FIX ===: Start from original clip position + delta
      _dragStartRow = newRow; // === FIX ===: Use the calculated new row

      // Clamp row
      if (_rowCount > 0) {
        _dragStartRow = _dragStartRow?.clamp(0, _rowCount - 1);
      }
      // Clamp time
      if (_dragStartClipMs! < 0) _dragStartClipMs = 0;

      // REMOVED: _dragStartLocalOffset update is not needed here since we use _dragStartGlobalOffset
    });
  }

  double _trimTimelineScaleForClip(
    AudioTrack clip, {
    required double trimStartMs,
    required double trimEndMs,
  }) {
    final rawVisibleMs = (trimEndMs - trimStartMs).clamp(1.0, double.infinity);
    final timelineVisibleMs = widget
        .getTimelineDurationMs(clip)
        .clamp(1.0, double.infinity);
    return (timelineVisibleMs / rawVisibleMs).clamp(0.0001, double.infinity);
  }

  double _sanitizeTrimMs(
    double value, {
    required double min,
    required double max,
  }) {
    if (!value.isFinite) return min;
    return value.clamp(min, max).toDouble().roundToDouble();
  }

  void _handleTrimUpdate(ScaleUpdateDetails details) {
    if (_hasActiveAutomationClipDrag) {
      final row = _automationClipDragRow;
      final targetId = _automationClipDragTargetId;
      final draggedClip = _activeDraggedAutomationClip();
      if (row != null && targetId != null && draggedClip != null) {
        _updateAutomationClipDrag(
          row,
          targetId,
          draggedClip,
          details.focalPointDelta.dx,
          details.localFocalPoint,
        );
      }
      return;
    }
    final trimClipIndex = _trimClipIndex;
    if (trimClipIndex == null || _trimStartAnchorX == null) return;
    if (trimClipIndex < 0 || trimClipIndex >= widget.clips.length) {
      setState(_cancelClipGestureAfterTopologyChange);
      return;
    }

    final clip = widget.clips[trimClipIndex];
    final fullDuration = widget.getFullDurationMs(clip);
    final isReversed = clip.isReversed;
    final timelineScale = (_trimTimelineScaleValue ?? 1.0).clamp(
      0.0001,
      double.infinity,
    );
    const minRawTrimMs = 50.0;
    final minTimelineTrimMs = minRawTrimMs * timelineScale;
    final originalStartMs = _trimOriginalStartMs!;
    final originalVisibleDurationMs =
        (_trimEndValue! - _trimStartValue!) * timelineScale;
    final originalVisibleEndMs = originalStartMs + originalVisibleDurationMs;
    final minVisibleStartMs = math.max(
      0.0,
      originalStartMs -
          ((isReversed ? (fullDuration - _trimEndValue!) : _trimStartValue!) *
              timelineScale),
    );
    final maxVisibleEndMs =
        originalStartMs +
        ((isReversed ? _trimEndValue! : (fullDuration - _trimStartValue!)) *
            timelineScale);

    // Amount user moved horizontally in pixels (local to timeline)
    final deltaPx = details.localFocalPoint.dx - _trimStartAnchorX!;
    // Convert movement delta to visible timeline ms.
    final deltaTimelineMs = deltaPx / _pixelsPerMs;

    double newTrimStart = _trimStartValue!;
    double newTrimEnd = _trimEndValue!;

    double? newStartMs;

    if (_interactionMode == 'trim-start') {
      double targetVisibleStartMs = originalStartMs + deltaTimelineMs;
      targetVisibleStartMs = _quantizeMsForTimelineClipDrag(
        targetVisibleStartMs,
      );
      targetVisibleStartMs = targetVisibleStartMs
          .clamp(minVisibleStartMs, originalVisibleEndMs - minTimelineTrimMs)
          .toDouble();
      final deltaVisibleMs = targetVisibleStartMs - originalStartMs;
      if (isReversed) {
        newTrimEnd = (_trimEndValue! - (deltaVisibleMs / timelineScale)).clamp(
          newTrimStart + minRawTrimMs,
          fullDuration,
        );
      } else {
        newTrimStart = (_trimStartValue! + (deltaVisibleMs / timelineScale))
            .clamp(0.0, newTrimEnd - minRawTrimMs);
      }
      newStartMs = targetVisibleStartMs;
    } else if (_interactionMode == 'trim-end') {
      double targetVisibleEndMs = originalVisibleEndMs + deltaTimelineMs;
      targetVisibleEndMs = _quantizeMsForTimelineClipDrag(targetVisibleEndMs);
      targetVisibleEndMs = targetVisibleEndMs
          .clamp(originalStartMs + minTimelineTrimMs, maxVisibleEndMs)
          .toDouble();
      final deltaVisibleMs = targetVisibleEndMs - originalVisibleEndMs;
      if (isReversed) {
        newTrimStart = (_trimStartValue! - (deltaVisibleMs / timelineScale))
            .clamp(0.0, newTrimEnd - minRawTrimMs);
      } else {
        newTrimEnd = (_trimEndValue! + (deltaVisibleMs / timelineScale)).clamp(
          newTrimStart + minRawTrimMs,
          fullDuration,
        );
      }
      // newStartMs remains null, correctly signaling no position change
    }

    final minTrimWindowMs = minRawTrimMs.roundToDouble();
    final maxTrimStart = math.max(0.0, fullDuration - minTrimWindowMs);
    var sanitizedTrimStart = _sanitizeTrimMs(
      newTrimStart,
      min: 0.0,
      max: maxTrimStart,
    );
    var sanitizedTrimEnd = _sanitizeTrimMs(
      newTrimEnd,
      min: sanitizedTrimStart + minTrimWindowMs,
      max: fullDuration,
    );
    if (sanitizedTrimEnd < sanitizedTrimStart + minTrimWindowMs) {
      sanitizedTrimEnd = (sanitizedTrimStart + minTrimWindowMs).clamp(
        0.0,
        fullDuration,
      );
      if (sanitizedTrimEnd >= fullDuration) {
        sanitizedTrimStart = (sanitizedTrimEnd - minTrimWindowMs).clamp(
          0.0,
          maxTrimStart,
        );
      }
      sanitizedTrimStart = sanitizedTrimStart.roundToDouble();
      sanitizedTrimEnd = sanitizedTrimEnd.roundToDouble();
    }
    final sanitizedNewStartMs = newStartMs == null
        ? null
        : _sanitizeTrimMs(
            newStartMs,
            min: minVisibleStartMs,
            max: originalVisibleEndMs - minTimelineTrimMs,
          );

    if (newTrimStartUpdate == sanitizedTrimStart &&
        newTrimEndUpdate == sanitizedTrimEnd &&
        newStartMsUpdate == sanitizedNewStartMs) {
      return;
    }

    if (sanitizedNewStartMs != null) {
      widget.onTrimClip(
        _trimClipIndex!,
        sanitizedTrimStart,
        sanitizedTrimEnd,
        newStartMs: sanitizedNewStartMs,
      );
    } else {
      widget.onTrimClip(
        _trimClipIndex!,
        sanitizedTrimStart,
        sanitizedTrimEnd,
        // newStartMs is omitted for trim-end
      );
    }
    newTrimStartUpdate = sanitizedTrimStart;
    newTrimEndUpdate = sanitizedTrimEnd;
    newStartMsUpdate = sanitizedNewStartMs;

    setState(() {});
  }

  void _handleStretchUpdate(ScaleUpdateDetails details) {
    if (_stretchClipIndex == null ||
        _stretchStartAnchorX == null ||
        _stretchStartTimelineDurationMs == null ||
        _stretchOriginalStartMs == null) {
      return;
    }

    final clipIndex = _stretchClipIndex!;
    if (clipIndex < 0 || clipIndex >= widget.clips.length) return;
    final clip = widget.clips[clipIndex];
    if (clip.isMidi) return;

    const minDurationMs = 50.0;
    final deltaPx = details.localFocalPoint.dx - _stretchStartAnchorX!;
    final deltaMs = deltaPx / _pixelsPerMs;

    final originalStartMs = _stretchOriginalStartMs!;
    final originalDurationMs = _stretchStartTimelineDurationMs!;
    final originalEndMs = originalStartMs + originalDurationMs;

    double newDurationMs = originalDurationMs;
    double? newStartMs;

    if (_interactionMode == 'stretch-start') {
      double targetStartMs = originalStartMs + deltaMs;
      targetStartMs = _quantizeMsForTimelineClipDrag(targetStartMs);
      targetStartMs = targetStartMs
          .clamp(0.0, originalEndMs - minDurationMs)
          .toDouble();
      newDurationMs = (originalEndMs - targetStartMs).clamp(
        minDurationMs,
        36000000.0,
      );
      newStartMs = targetStartMs;
    } else if (_interactionMode == 'stretch-end') {
      double targetEndMs = originalEndMs + deltaMs;
      targetEndMs = _quantizeMsForTimelineClipDrag(targetEndMs);
      targetEndMs = targetEndMs.clamp(
        originalStartMs + minDurationMs,
        36000000.0,
      );
      newDurationMs = (targetEndMs - originalStartMs).clamp(
        minDurationMs,
        36000000.0,
      );
      newStartMs = null;
    }

    widget.onStretchClip(clipIndex, newDurationMs, newStartMs: newStartMs);
    _stretchDurationUpdateMs = newDurationMs;

    setState(() {});
  }

  void _handlePanZoomUpdate(ScaleUpdateDetails details) {
    bool didZoom = false;
    bool didScroll = false;
    final trackpadNavigationGestureActive =
        _timelineModifierTrackpadNavigationActive ||
        _timelineTrackpadPanAxis != null;
    final allowDesktopPointerPan =
        !trackpadNavigationGestureActive &&
        (!PlatformCapabilities.current.isDesktop || _timelineHasMultiTouch);
    setState(() {
      // --- Handle Zoom ---
      if (details.scale != 1.0 && _initialPixelsPerMs != null) {
        final newPixelsPerMs = (_initialPixelsPerMs! * details.scale).clamp(
          _kMinTimelinePixelsPerMs,
          _kMaxTimelinePixelsPerMs,
        );
        didZoom = didZoom || (newPixelsPerMs - _pixelsPerMs).abs() > 0.0001;

        // Zoom around the focal point
        final focalPointPx = details.localFocalPoint.dx;
        final focalPointMs = _scrollOffsetMs + focalPointPx / _pixelsPerMs;

        _scrollOffsetMs = focalPointMs - (focalPointPx / newPixelsPerMs);
        _pixelsPerMs = newPixelsPerMs;
      }

      // --- Handle Pan ---
      if (allowDesktopPointerPan && details.focalPointDelta.dx != 0) {
        _scrollOffsetMs -= details.focalPointDelta.dx / _pixelsPerMs;
        didScroll = true;
      }

      // Panning and zooming are navigation. Keep audio parked while the
      // gesture is active, then seek once when the gesture ends.
      _clampScroll();
    });

    if (!_tutorialScrollNotifiedForGesture) {
      final start = _tutorialPanStartScrollMs ?? _scrollOffsetMs;
      final movedEnough = (_scrollOffsetMs - start).abs() >= 80.0;
      if (didScroll && movedEnough) {
        _tutorialScrollNotifiedForGesture = true;
        widget.onTutorialTimelineScrolled?.call();
      }
    }
    if (!_tutorialZoomNotifiedForGesture) {
      final startZoom = _tutorialPanStartPixelsPerMs ?? _pixelsPerMs;
      final safeStartZoom = startZoom <= 0 ? 0.0001 : startZoom;
      final zoomRatio = (_pixelsPerMs / safeStartZoom);
      final zoomedEnough =
          (zoomRatio - 1.0).abs() >= 0.08 ||
          (_pixelsPerMs - startZoom).abs() >= 0.002;
      if (didZoom && zoomedEnough) {
        _tutorialZoomNotifiedForGesture = true;
        widget.onTutorialTimelineZoomed?.call();
      }
    }
  }

  double msFor128Bars(double bpm) {
    final msPerQuarter = 60000 / bpm;
    final safeNumerator = math.max(1, widget.beatsPerBar);
    final safeDenominator = math.max(1, widget.beatUnit);
    return 128 * msPerQuarter * safeNumerator * 4.0 / safeDenominator;
  }

  void _clampScroll() {
    if (PlatformCapabilities.current.isDesktop) {
      final viewportMs = _getViewportWidth(context) / _pixelsPerMs;
      final minScroll = -_desktopLeftDeadZoneMs(context);
      final maxScroll = widget.isRecording
          ? double.maxFinite
          : math.max(_maxDurationMs, msFor128Bars(widget.bpm)) - viewportMs;
      if (!maxScroll.isFinite || maxScroll <= minScroll) {
        _scrollOffsetMs = minScroll;
      } else {
        _scrollOffsetMs = _scrollOffsetMs.clamp(minScroll, maxScroll);
      }
      return;
    }
    final playheadPx = _getPlayheadPx(context);

    // Allow scrolling so 0ms is at the playhead
    final minScroll = -(playheadPx) / _pixelsPerMs;
    // Allow scrolling so maxDuration is at the playhead
    // if recording, then don't clamp the end scroll
    // else, set max scroll to at least 128 bars (no matter bpm)
    final maxScroll = widget.isRecording
        ? double.maxFinite
        : math.max(_maxDurationMs, msFor128Bars(widget.bpm)) -
              (playheadPx / _pixelsPerMs);

    // Don't allow scrolling past min/max if the content is smaller than the view
    if (maxScroll < minScroll) {
      final centerScroll = (minScroll + maxScroll) / 2;
      _scrollOffsetMs = centerScroll;
    } else {
      _scrollOffsetMs = _scrollOffsetMs.clamp(minScroll, maxScroll);
    }
  }

  Rect? _getClipRect(int clipIndex) {
    if (clipIndex < 0 || clipIndex >= widget.clips.length) return null;
    final clip = widget.clips[clipIndex];

    final startMs = widget.getStartMs(clip);
    final trimStart = widget.getTrimStartMs(clip);
    final trimEnd = trimStart + widget.getTimelineDurationMs(clip);
    final row = clip.rowIndex;
    if (!_isSourceRowVisible(row)) return null;

    final x = (startMs - _scrollOffsetMs) * _pixelsPerMs;
    final width = (trimEnd - trimStart) * _pixelsPerMs;
    final yOffset = _rowTopForIndex(row);

    final y = yOffset + 2;
    final height = _rowHeight - 4;

    return Rect.fromLTWH(x, y, width, height);
  }

  // ADD THIS NEW METHOD TO _AudioCanvasTimelineState
  AudioTrack? _getClipAt(Offset localPosition) {
    final localX = localPosition.dx;
    final localY = localPosition.dy;

    // Calculate the time (in Ms) and row index corresponding to the tap
    final tapMs = _scrollOffsetMs + localX / _pixelsPerMs;
    if (_rowCount == 0) return null;
    final tapRow = _rowForLocalY(localY);
    if (tapRow == null || !_isLocalYInMainTrackLane(tapRow, localY)) {
      return null;
    }

    _ensureClipSpatialIndex();
    final candidates =
        _clipSpatialIndexByRow[tapRow]?.indicesAt(tapMs) ?? const <int>[];
    for (final i in _clipHitTestOrder(candidates)) {
      final clip = widget.clips[i];
      final startMs = widget.getStartMs(clip);
      final durationMs = widget.getTimelineDurationMs(clip);
      final endMs = startMs + durationMs;
      final clipRow = clip.rowIndex;

      if (clipRow == tapRow && tapMs >= startMs && tapMs <= endMs) {
        return clip;
      }
    }
    return null;
  }

  // === MODIFIED: Correctly map localY to the actual track row index ===
  int? _getClipIndexAt(Offset localPosition) {
    return _getClipIndexAtInternal(localPosition);
  }

  int? _getGestureClipIndexAt(Offset localPosition) {
    return _getClipIndexAtInternal(
      localPosition,
      includeTrimHandleHitbox: true,
    );
  }

  Rect _leftTrimHandleRect(Rect clipRect) {
    return Rect.fromLTWH(
      clipRect.left - kTrimHandleGap - kTrimHandleWidth,
      clipRect.top + kTrimHandleVerticalInset,
      kTrimHandleWidth,
      math.max(1.0, clipRect.height - (kTrimHandleVerticalInset * 2.0)),
    );
  }

  Rect _rightTrimHandleRect(Rect clipRect) {
    return Rect.fromLTWH(
      clipRect.right + kTrimHandleGap,
      clipRect.top + kTrimHandleVerticalInset,
      kTrimHandleWidth,
      math.max(1.0, clipRect.height - (kTrimHandleVerticalInset * 2.0)),
    );
  }

  Rect _leftTrimHandleHitbox(Rect clipRect) {
    final handleRect = _leftTrimHandleRect(clipRect);
    return Rect.fromLTRB(
      handleRect.left - kTrimHandleOuterHitboxPadding,
      handleRect.top - kTrimHandleOuterHitboxPadding,
      handleRect.right + kTrimHandleInnerHitboxPadding,
      handleRect.bottom + kTrimHandleOuterHitboxPadding,
    );
  }

  Rect _rightTrimHandleHitbox(Rect clipRect) {
    final handleRect = _rightTrimHandleRect(clipRect);
    return Rect.fromLTRB(
      handleRect.left - kTrimHandleInnerHitboxPadding,
      handleRect.top - kTrimHandleOuterHitboxPadding,
      handleRect.right + kTrimHandleOuterHitboxPadding,
      handleRect.bottom + kTrimHandleOuterHitboxPadding,
    );
  }

  bool _isLocalPositionInLeftTrimHandleHitbox(
    Rect clipRect,
    Offset localPosition,
  ) {
    return _leftTrimHandleHitbox(clipRect).contains(localPosition);
  }

  bool _isLocalPositionInRightTrimHandleHitbox(
    Rect clipRect,
    Offset localPosition,
  ) {
    return _rightTrimHandleHitbox(clipRect).contains(localPosition);
  }

  int? _getClipIndexAtInternal(
    Offset localPosition, {
    bool includeTrimHandleHitbox = false,
  }) {
    final localX = localPosition.dx;
    final localY = localPosition.dy;
    final tapMs = _scrollOffsetMs + localX / _pixelsPerMs;
    final tapRow = _rowForLocalY(localY);
    if (tapRow == null || !_isLocalYInMainTrackLane(tapRow, localY)) {
      return null;
    }
    if (includeTrimHandleHitbox &&
        _selectedClipIndices.length == 1 &&
        _selectedClipIndex >= 0 &&
        _selectedClipIndex < widget.clips.length) {
      final selectedClip = widget.clips[_selectedClipIndex];
      if (selectedClip.rowIndex == tapRow) {
        final selectedClipRect = _getClipRect(_selectedClipIndex);
        if (selectedClipRect != null &&
            (_isLocalPositionInLeftTrimHandleHitbox(
                  selectedClipRect,
                  localPosition,
                ) ||
                _isLocalPositionInRightTrimHandleHitbox(
                  selectedClipRect,
                  localPosition,
                ))) {
          return _selectedClipIndex;
        }
      }
    }
    _ensureClipSpatialIndex();
    final candidates =
        _clipSpatialIndexByRow[tapRow]?.indicesAt(tapMs) ?? const <int>[];
    for (final i in _clipHitTestOrder(candidates)) {
      final clip = widget.clips[i];
      if (clip.rowIndex != tapRow) continue;

      final startMs = widget.getStartMs(clip);
      final endMs = startMs + widget.getTimelineDurationMs(clip);
      if (tapMs >= startMs && tapMs <= endMs) {
        return i;
      }
      if (!includeTrimHandleHitbox || !_isClipIndexSelected(i)) {
        continue;
      }
      final clipRect = _getClipRect(i);
      if (clipRect == null) continue;
      if (_isLocalPositionInLeftTrimHandleHitbox(clipRect, localPosition) ||
          _isLocalPositionInRightTrimHandleHitbox(clipRect, localPosition)) {
        return i;
      }
    }
    return null;
  }

  void _handleTapDown(TapDownDetails details) {
    if (_interactionMode == 'automation' || _hasActiveAutomationClipDrag) {
      return;
    }
    if (_activeTool == _TimelineTool.cut ||
        _activeTool == _TimelineTool.delete) {
      return;
    }
    if (_selectionBoxActive) return;
    if (_desktopAdditiveSelectionGestureActive) return;

    final touchedClipIndex = _getGestureClipIndexAt(details.localPosition);
    final touchShouldAddClip =
        !PlatformCapabilities.current.isDesktop &&
        _touchMultiSelectMode &&
        touchedClipIndex != null &&
        !_selectedClipIndices.contains(touchedClipIndex);
    final additiveClipIndex =
        (_desktopAdditiveSelectionModifierPressed || touchShouldAddClip)
        ? touchedClipIndex
        : null;
    if (additiveClipIndex != null) {
      setState(() {
        _resetTrimInteractionState();
        _clearPendingClipTapState();
        _clearPastePopup();
        _desktopAdditiveSelectionGestureActive = true;
        _suppressNextTimelineTapAfterAdditiveSelection = true;
        _toggleClipInSelection(additiveClipIndex);
      });
      return;
    }

    _clearPastePopup();
    _tentativeClipSelectionActive = false;

    final localPos = details.localPosition;
    final tappedClipIndexForPaint = _getGestureClipIndexAt(localPos);
    if (_activeTool == _TimelineTool.paint &&
        _activeSelectedClipIndices().isEmpty &&
        tappedClipIndexForPaint == null) {
      return;
    }
    final tappedAutomationClip = _timelineAutomationClipAt(localPos);
    if (tappedAutomationClip != null) {
      final isSelectedClip =
          _selectedAutomationClipIdFor(
            tappedAutomationClip.row,
            tappedAutomationClip.targetId,
          ) ==
          tappedAutomationClip.clip.id;
      String interactionMode = 'open';
      if (isSelectedClip) {
        if (_automationClipRightTrimHandleHit(tappedAutomationClip, localPos)) {
          interactionMode = 'trim_end';
        } else if (_automationClipLeftTrimHandleHit(
          tappedAutomationClip,
          localPos,
        )) {
          interactionMode = 'trim_start';
        } else if (_automationClipMoveHandleRect(
          tappedAutomationClip,
        ).contains(localPos)) {
          interactionMode = 'move';
        }
      }
      widget.setSelectedAutomationTargetId(
        tappedAutomationClip.row,
        tappedAutomationClip.targetId,
      );
      setState(() {
        _resetTrimInteractionState();
        _clearClipSelection();
        _setSelectedAutomationClipFor(
          tappedAutomationClip.row,
          tappedAutomationClip.targetId,
          tappedAutomationClip.clip.id,
          lane: tappedAutomationClip.clip.lane,
        );
        _pendingAutomationClipVisual = tappedAutomationClip;
        _pendingAutomationClipStartLocalOffset =
            localPos - tappedAutomationClip.rect.topLeft;
        _pendingAutomationClipInteractionMode = interactionMode;
        _dragStartGlobalOffset = details.globalPosition;
      });
      return;
    }
    _clearPendingAutomationClipSelection();
    final tappedClipIndex = tappedClipIndexForPaint;

    if (tappedClipIndex == null) {
      final tapRow = _rowForLocalY(localPos.dy);
      final rawTapMs = _scrollOffsetMs + localPos.dx / _pixelsPerMs;
      final canPasteHere =
          tapRow != null &&
          (_canPasteCopiedClipAtRow(tapRow) ||
              _canPasteAutomationClipAt(tapRow));
      final needsVisualReset =
          _selectedClipIndex >= 0 ||
          _selectedClipIndices.isNotEmpty ||
          _selectedAutomationClipByLane.isNotEmpty ||
          _automationClipMenuClipId != null ||
          _trimClipIndex != null ||
          _stretchClipIndex != null ||
          _activeTrimHandleX != null;
      if (needsVisualReset) {
        setState(() {
          _resetTrimInteractionState();
          _clearClipSelection();
          if (canPasteHere) {
            _setPastePopupTarget(tapRow, rawTapMs);
          }
        });
      } else if (canPasteHere) {
        setState(() {
          _setPastePopupTarget(tapRow, rawTapMs);
        });
      }
      return;
    }
    final wasAlreadySelected = _selectedClipIndices.contains(tappedClipIndex);
    final clipRect = _getClipRect(tappedClipIndex);
    if (clipRect == null) {
      if (!wasAlreadySelected) {
        setState(() {
          _resetTrimInteractionState();
          _tentativeClipSelectionActive = true;
          _pendingTapSelectionClipIndex = tappedClipIndex;
          _pendingTapSelectionPopupMs = null;
          _dragStartGlobalOffset = details.globalPosition;
        });
      }
      return;
    }

    final tapPopupMs = _scrollOffsetMs + localPos.dx / _pixelsPerMs;
    final draggingGroup =
        _selectedClipIndices.length > 1 &&
        _selectedClipIndices.contains(tappedClipIndex);

    // === 3. PRIORITY 1: TRIM HANDLE HIT? (WINS OVER DRAG) ===
    final leftHandleHit = _isLocalPositionInLeftTrimHandleHitbox(
      clipRect,
      localPos,
    );
    final rightHandleHit = _isLocalPositionInRightTrimHandleHitbox(
      clipRect,
      localPos,
    );

    if (!draggingGroup && (leftHandleHit || rightHandleHit)) {
      setState(() {
        _resetTrimInteractionState();
        _tentativeClipSelectionActive = !wasAlreadySelected;
        if (wasAlreadySelected) {
          _setSingleClipSelection(tappedClipIndex, popupMs: tapPopupMs);
          _trimClipIndex = tappedClipIndex;
          _activeTrimHandleX = leftHandleHit ? clipRect.left : clipRect.right;
        } else {
          _pendingTapSelectionClipIndex = tappedClipIndex;
          _pendingTapSelectionPopupMs = tapPopupMs;
          _dragStartGlobalOffset = details.globalPosition;
        }
        // Only clips that were already selected can arm trim/stretch in the
        // same gesture. First touch selects; a follow-up gesture can edit.
      });
      return; // STOP — do NOT allow drag
    }

    // === 4. PRIORITY 2: TAP ON CLIP BODY → SELECT FIRST, DRAG ON FOLLOW-UP ===
    if (clipRect.contains(localPos)) {
      final clip = widget.clips[tappedClipIndex];
      final desktopDirectDrag =
          _desktopPrimaryPointerDownActive && !wasAlreadySelected;
      final canBeginDrag =
          _activeTool == _TimelineTool.paint ||
          wasAlreadySelected ||
          draggingGroup ||
          desktopDirectDrag;
      final tentativeSelection =
          !canBeginDrag && !wasAlreadySelected && !draggingGroup;
      setState(() {
        _resetTrimInteractionState();
        _clearPendingClipDrag();
        _tentativeClipSelectionActive = tentativeSelection;
        if (tentativeSelection) {
          _pendingTapSelectionClipIndex = tappedClipIndex;
          _pendingTapSelectionPopupMs = tapPopupMs;
          _dragStartGlobalOffset = details.globalPosition;
        } else {
          _setPrimaryClipSelection(
            tappedClipIndex,
            preserveExistingSelection: draggingGroup,
            popupMs: tapPopupMs,
          );
        }
        if (canBeginDrag) {
          _pendingDrag = true;
          _pendingDragStartedFromSelection =
              wasAlreadySelected || desktopDirectDrag;
          _draggedClipIndex = tappedClipIndex;
          _dragStartGlobalOffset = details.globalPosition;
          _dragStartLocalOffset = localPos;
          _dragStartClipMs = widget.getStartMs(clip);
          _dragStartRow = clip.rowIndex;
          _dragDeltaMs = 0.0;
          _dragDeltaRows = 0;
          _dragXAxisLocked = false;
          _dragGroupStartMs.clear();
          _dragGroupStartRows.clear();
        }
      });
      return;
    }

    // === 5. TAP ELSEWHERE → clear trim cue ===
    setState(() {
      _resetTrimInteractionState();
    });
  }

  void _onTimelineDoubleTapDown(TapDownDetails details) {
    final tappedAutomationClip = _timelineAutomationClipAt(
      details.localPosition,
    );
    if (tappedAutomationClip == null) return;
    setState(() {
      _setSelectedAutomationClipFor(
        tappedAutomationClip.row,
        tappedAutomationClip.targetId,
        tappedAutomationClip.clip.id,
        lane: tappedAutomationClip.clip.lane,
      );
      _clearPendingAutomationClipSelection();
    });
    _openAutomationClipEditor(tappedAutomationClip);
  }

  bool _canShowInstrumentLaneRegionMenuAt(Offset localPosition) {
    if (widget.onCreateMidiClipInInstrumentLane == null) {
      return false;
    }
    final tapRow = _rowForLocalY(localPosition.dy);
    if (tapRow == null ||
        !_isInstrumentLane(tapRow) ||
        _getGestureClipIndexAt(localPosition) != null) {
      return false;
    }
    return true;
  }

  void _showInstrumentLaneRegionMenuAt(Offset localPosition) {
    if (!_canShowInstrumentLaneRegionMenuAt(localPosition)) {
      return;
    }
    final tapRow = _rowForLocalY(localPosition.dy);
    if (tapRow == null) return;

    final rawTapMs = _scrollOffsetMs + localPosition.dx / _pixelsPerMs;
    final quantizedStartMs = _segmentStartMsForTap(rawTapMs);
    final quantizedEndMs = quantizedStartMs + _quantizeIntervalMs();
    final tapMsForPaste = _magnetEnabled ? quantizedStartMs : rawTapMs;

    setState(() {
      _resetTrimInteractionState();
      _clearClipSelection();
      _showPastePopup = false;
      _pasteRow = null;
      _pasteMs = null;
      _showInstrumentLaneRegionPopup = true;
      _instrumentLaneRegionRow = tapRow;
      _instrumentLaneRegionMs = tapMsForPaste;
      _instrumentLaneRegionAnchorLocal = localPosition;
      _highlightedSegmentRow = _magnetEnabled ? tapRow : null;
      _highlightedSegmentStartMs = _magnetEnabled ? quantizedStartMs : null;
      _highlightedSegmentEndMs = _magnetEnabled ? quantizedEndMs : null;
      _clearSelectionBoxGestureState();
      _suppressNextTimelineTapAfterInstrumentLaneCreate = true;
    });
  }

  Future<void> _createMidiRegionFromInstrumentLanePopup() async {
    final create = widget.onCreateMidiClipInInstrumentLane;
    final row = _instrumentLaneRegionRow;
    final ms = _instrumentLaneRegionMs;
    if (create == null || row == null || ms == null) return;
    setState(() {
      _clearInstrumentLaneRegionPopupState();
      _highlightedSegmentRow = null;
      _highlightedSegmentStartMs = null;
      _highlightedSegmentEndMs = null;
      _showPastePopup = false;
      _pasteRow = null;
      _pasteMs = null;
    });
    await create(row, ms);
  }

  void _onTimelineTap(TapUpDetails details) {
    _timelineKeyboardModifierPointer = null;
    if (_suppressNextTimelineTapAfterAdditiveSelection) {
      _suppressNextTimelineTapAfterAdditiveSelection = false;
      return;
    }
    if (_suppressNextTimelineTapAfterSelectionBox) {
      _suppressNextTimelineTapAfterSelectionBox = false;
      return;
    }
    if (_suppressNextTimelineTapAfterDeadZoneHold) {
      _suppressNextTimelineTapAfterDeadZoneHold = false;
      return;
    }
    if (_suppressNextTimelineTapAfterTentativeSelectionCommit) {
      _suppressNextTimelineTapAfterTentativeSelectionCommit = false;
      return;
    }
    if (_suppressNextTimelineTapAfterInstrumentLaneCreate) {
      _suppressNextTimelineTapAfterInstrumentLaneCreate = false;
      return;
    }
    if (_pendingDrag) {
      setState(_clearPendingClipTapState);
    }
    final pendingAutomationClip = _pendingAutomationClipVisual;
    if (pendingAutomationClip != null) {
      final pendingMode = _pendingAutomationClipInteractionMode ?? 'open';
      setState(() {
        _clearPendingAutomationClipSelection();
        _dragStartGlobalOffset = null;
      });
      if (pendingMode == 'open') {
        _openAutomationClipEditor(pendingAutomationClip);
      }
      return;
    }
    if (_interactionMode == 'automation') return;
    if (_hasActiveAutomationClipDrag) {
      final row = _automationClipDragRow;
      final targetId = _automationClipDragTargetId;
      if (row != null && targetId != null) {
        _endAutomationClipDrag(row, targetId);
        _focusAutomationEditorForRow(row, targetId);
      }
      setState(() {
        _interactionMode = '';
        _isUserInteracting = false;
        _dragStartGlobalOffset = null;
      });
      return;
    }
    if (_activeTool == _TimelineTool.cut) {
      // Cut commits on raw pointer-up so drag-to-preview release also cuts.
      return;
    }

    if (_activeTool == _TimelineTool.paint) {
      if (_paintGesturePlacedClip) {
        _paintGesturePlacedClip = false;
        setState(() {
          _showPastePopup = false;
          _pasteRow = null;
          _pasteMs = null;
          _clearInstrumentLaneRegionPopupState();
          _highlightedSegmentRow = null;
          _highlightedSegmentStartMs = null;
          _highlightedSegmentEndMs = null;
        });
        return;
      }
      final topIndex = _getGestureClipIndexAt(details.localPosition);
      if (topIndex != null) {
        setState(() {
          _setSingleClipSelection(
            topIndex,
            popupMs: _scrollOffsetMs + details.localPosition.dx / _pixelsPerMs,
          );
          _showPastePopup = false;
          _pasteRow = null;
          _pasteMs = null;
          _clearInstrumentLaneRegionPopupState();
          _highlightedSegmentRow = null;
          _highlightedSegmentStartMs = null;
          _highlightedSegmentEndMs = null;
        });
        return;
      }
      if (_activeSelectedClipIndices().isNotEmpty) {
        setState(() {
          _clearClipSelection();
          _showPastePopup = false;
          _pasteRow = null;
          _pasteMs = null;
          _clearInstrumentLaneRegionPopupState();
          _highlightedSegmentRow = null;
          _highlightedSegmentStartMs = null;
          _highlightedSegmentEndMs = null;
          _activeTrimHandleX = null;
          _trimClipIndex = null;
          _stretchClipIndex = null;
          _stretchStartTimelineDurationMs = null;
          _stretchOriginalStartMs = null;
          _stretchStartAnchorX = null;
          _stretchDurationUpdateMs = null;
        });
        return;
      }
      if (!_hasPasteClipboard) {
        _showPaintClipboardHint();
        return;
      }
      _tryPaintAt(details.localPosition);
      return;
    }

    if (_activeTool == _TimelineTool.delete) {
      return;
    }

    if (_tentativeClipSelectionActive) {
      setState(_commitTentativeTapSelectionIfNeeded);
      return;
    }

    if (_interactionMode == 'drag') {
      final tappedDragIndex = _draggedClipIndex;
      final shouldTreatAsTap = !_pendingClipDragExceededSlop(
        details.globalPosition,
      );
      final tapPopupMs =
          _scrollOffsetMs + details.localPosition.dx / _pixelsPerMs;
      final shouldSelectClip =
          shouldTreatAsTap &&
          tappedDragIndex != null &&
          tappedDragIndex >= 0 &&
          tappedDragIndex < widget.clips.length;
      final shouldOpenMidiFromRetap =
          shouldSelectClip &&
          _selectedClipIndices.contains(tappedDragIndex) &&
          widget.clips[tappedDragIndex].clipKind == ClipKind.midi;

      setState(() {
        final preserveDraggedGroupSelection =
            shouldSelectClip &&
            _selectedClipIndices.length > 1 &&
            _selectedClipIndices.contains(tappedDragIndex);
        _interactionMode = '';
        _draggedClipIndex = null;
        _clearPendingClipDrag();
        _isUserInteracting = false;
        _dragGroupStartMs.clear();
        _dragGroupStartRows.clear();
        _resetTrimInteractionState();
        if (shouldSelectClip) {
          _setPrimaryClipSelection(
            tappedDragIndex,
            popupMs: preserveDraggedGroupSelection ? null : tapPopupMs,
            preserveExistingSelection: preserveDraggedGroupSelection,
          );
        }
      });
      if (shouldOpenMidiFromRetap) {
        widget.onOpenMidiClip?.call(tappedDragIndex);
      }
      return;
    }

    final localX = details.localPosition.dx;
    final localY = details.localPosition.dy;
    final rawTapMs = _scrollOffsetMs + localX / _pixelsPerMs;

    final tapRow = _rowForLocalY(localY);
    if (tapRow == null) return;
    final topIndex = _getGestureClipIndexAt(details.localPosition);

    // If a MIDI clip is already selected, allow forgiving re-taps around it
    // so opening piano roll remains easy even when zoomed out.
    if (topIndex == null &&
        _selectedClipIndex >= 0 &&
        _selectedClipIndex < widget.clips.length) {
      final selectedClip = widget.clips[_selectedClipIndex];
      if (selectedClip.clipKind == ClipKind.midi &&
          selectedClip.rowIndex == tapRow) {
        final selectedRect = _getClipRect(_selectedClipIndex);
        if (selectedRect != null) {
          final forgivingRect = selectedRect.inflate(24.0);
          if (forgivingRect.contains(details.localPosition)) {
            widget.onOpenMidiClip?.call(_selectedClipIndex);
            return;
          }
        }
      }
    }

    if (topIndex != null) {
      final clip = widget.clips[topIndex];
      final wasSelected = _selectedClipIndices.contains(topIndex);
      if (clip.clipKind == ClipKind.midi && wasSelected) {
        widget.onOpenMidiClip?.call(topIndex);
        return;
      }
      final preserveExistingSelection =
          _selectedClipIndices.length > 1 &&
          _selectedClipIndices.contains(topIndex);

      setState(() {
        _resetTrimInteractionState();
        _setPrimaryClipSelection(
          topIndex,
          popupMs: preserveExistingSelection ? null : rawTapMs,
          preserveExistingSelection: preserveExistingSelection,
        );
        _showPastePopup = false;
        _pasteRow = null;
        _pasteMs = null;
        _clearInstrumentLaneRegionPopupState();
        _highlightedSegmentRow = null;
        _highlightedSegmentStartMs = null;
        _highlightedSegmentEndMs = null;
      });
    } else {
      setState(() {
        _resetTrimInteractionState();
        _clearClipSelection();
        final canPasteHere =
            _canPasteCopiedClipAtRow(tapRow) ||
            _canPasteAutomationClipAt(tapRow);

        // If we have something copied, show paste popup here
        if (canPasteHere) {
          _setPastePopupTarget(tapRow, rawTapMs);
        } else {
          _showPastePopup = false;
          _pasteRow = null;
          _pasteMs = null;
          _clearInstrumentLaneRegionPopupState();
          _highlightedSegmentRow = null;
          _highlightedSegmentStartMs = null;
          _highlightedSegmentEndMs = null;
        }
      });
    }
  }
}

class _HorizontalScrollbarMetrics {
  final double minScrollMs;
  final double scrollableMs;
  final double trackInset;
  final double thumbLeft;
  final double thumbWidth;
  final double trackTravel;

  const _HorizontalScrollbarMetrics({
    required this.minScrollMs,
    required this.scrollableMs,
    required this.trackInset,
    required this.thumbLeft,
    required this.thumbWidth,
    required this.trackTravel,
  });
}

class _ClipOverlapSpan {
  final int index;
  final int row;
  final double startMs;
  final double endMs;

  const _ClipOverlapSpan({
    required this.index,
    required this.row,
    required this.startMs,
    required this.endMs,
  });
}

class _TimelineClipSpatialEntry {
  const _TimelineClipSpatialEntry({
    required this.clip,
    required this.clipIndex,
    required this.rowIndex,
    required this.startMs,
    required this.endMs,
    required this.snapStartMs,
  });

  final AudioTrack clip;
  final int clipIndex;
  final int rowIndex;
  final double startMs;
  final double endMs;
  final double snapStartMs;
}

class _TimelineClipRowSpatialIndex {
  _TimelineClipRowSpatialIndex(List<_TimelineClipSpatialEntry> source)
    : entries = List<_TimelineClipSpatialEntry>.from(source)
        ..sort((a, b) {
          final byStart = a.startMs.compareTo(b.startMs);
          if (byStart != 0) return byStart;
          return a.clipIndex.compareTo(b.clipIndex);
        }) {
    var leafBase = 1;
    while (leafBase < entries.length) {
      leafBase <<= 1;
    }
    _treeLeafBase = leafBase;
    _maxEndTree = List<double>.filled(leafBase * 2, double.negativeInfinity);
    for (int index = 0; index < entries.length; index++) {
      _maxEndTree[leafBase + index] = entries[index].endMs;
    }
    for (int node = leafBase - 1; node > 0; node--) {
      _maxEndTree[node] = math.max(
        _maxEndTree[node << 1],
        _maxEndTree[(node << 1) | 1],
      );
    }
    _boundaryMs = <double>[
      for (final entry in entries) ...<double>[entry.snapStartMs, entry.endMs],
    ]..sort();
  }

  final List<_TimelineClipSpatialEntry> entries;
  late final int _treeLeafBase;
  late final List<double> _maxEndTree;
  late final List<double> _boundaryMs;

  int _upperBoundStart(double timeMs) {
    var low = 0;
    var high = entries.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (entries[middle].startMs <= timeMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  double? nearestBoundaryWithin(double timeMs, double toleranceMs) {
    if (_boundaryMs.isEmpty || toleranceMs < 0.0) return null;
    var low = 0;
    var high = _boundaryMs.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_boundaryMs[middle] < timeMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    double? nearest;
    var nearestDistance = double.infinity;
    for (final index in <int>[low - 1, low]) {
      if (index < 0 || index >= _boundaryMs.length) continue;
      final boundary = _boundaryMs[index];
      final distance = (boundary - timeMs).abs();
      if (distance <= toleranceMs && distance < nearestDistance) {
        nearest = boundary;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  void addIntersecting(double startMs, double endMs, Set<int> output) {
    if (entries.isEmpty || endMs < startMs) return;
    final rightExclusive = _upperBoundStart(endMs);
    _queryIntersecting(
      node: 1,
      nodeLeft: 0,
      nodeRight: _treeLeafBase,
      rightExclusive: rightExclusive,
      minimumEndMs: startMs,
      onMatch: output.add,
    );
  }

  int? topmostAt(double timeMs) {
    final candidates = indicesAt(timeMs);
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) => a > b ? a : b);
  }

  List<int> indicesAt(double timeMs) {
    final matches = <int>[];
    if (entries.isEmpty) return matches;
    _queryIntersecting(
      node: 1,
      nodeLeft: 0,
      nodeRight: _treeLeafBase,
      rightExclusive: _upperBoundStart(timeMs),
      minimumEndMs: timeMs,
      onMatch: matches.add,
    );
    return matches;
  }

  void _queryIntersecting({
    required int node,
    required int nodeLeft,
    required int nodeRight,
    required int rightExclusive,
    required double minimumEndMs,
    required void Function(int clipIndex) onMatch,
  }) {
    if (nodeLeft >= rightExclusive || _maxEndTree[node] < minimumEndMs) {
      return;
    }
    if (nodeRight - nodeLeft == 1) {
      if (nodeLeft < entries.length) {
        onMatch(entries[nodeLeft].clipIndex);
      }
      return;
    }
    final middle = nodeLeft + ((nodeRight - nodeLeft) >> 1);
    _queryIntersecting(
      node: node << 1,
      nodeLeft: nodeLeft,
      nodeRight: middle,
      rightExclusive: rightExclusive,
      minimumEndMs: minimumEndMs,
      onMatch: onMatch,
    );
    _queryIntersecting(
      node: (node << 1) | 1,
      nodeLeft: middle,
      nodeRight: nodeRight,
      rightExclusive: rightExclusive,
      minimumEndMs: minimumEndMs,
      onMatch: onMatch,
    );
  }
}

class _ClipCrossfadeVisual {
  final int row;
  final double startMs;
  final double endMs;
  final String curveMode;

  const _ClipCrossfadeVisual({
    required this.row,
    required this.startMs,
    required this.endMs,
    required this.curveMode,
  });
}

class _TabletRailEndCap extends StatelessWidget {
  const _TabletRailEndCap({required this.active, required this.resizing});

  final bool active;
  final bool resizing;

  @override
  Widget build(BuildContext context) {
    final accent = resizing ? const Color(0xFFFFC66D) : const Color(0xFF7FC9E5);
    final colorAlpha = active
        ? 0.76
        : resizing
        ? 0.46
        : 0.28;
    final glowAlpha = active
        ? 0.46
        : resizing
        ? 0.24
        : 0.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      width: active ? 14 : (resizing ? 12 : 9),
      height: active ? 8 : (resizing ? 6 : 5),
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: resizing
            ? accent.withValues(alpha: colorAlpha)
            : const Color(0xFF15436C).withValues(alpha: colorAlpha),
        borderRadius: BorderRadius.circular(99),
        border: active || resizing
            ? Border.all(
                color: Colors.white.withValues(alpha: active ? 0.56 : 0.34),
                width: 0.6,
              )
            : null,
        boxShadow: active || resizing
            ? <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: glowAlpha),
                  blurRadius: active ? 10 : 7,
                  spreadRadius: active ? 1.4 : 0.8,
                ),
              ]
            : const <BoxShadow>[],
      ),
    );
  }
}

class _TimelineAutomationClipVisual {
  final int row;
  final int displayRow;
  final String targetId;
  final String targetLabel;
  final String fullTargetLabel;
  final AutomationClipSnapshot clip;
  final int laneIndex;
  final Rect rect;
  final bool isSelected;
  final bool isOrphan;

  const _TimelineAutomationClipVisual({
    required this.row,
    required this.displayRow,
    required this.targetId,
    required this.targetLabel,
    required this.fullTargetLabel,
    required this.clip,
    required this.laneIndex,
    required this.rect,
    required this.isSelected,
    required this.isOrphan,
  });
}

class _CollapsedGroupSummary {
  final String groupId;
  final int leadRow;
  final Set<int> memberRows;
  final List<int> clipIndices;
  final double startMs;
  final double endMs;

  const _CollapsedGroupSummary({
    required this.groupId,
    required this.leadRow,
    required this.memberRows,
    required this.clipIndices,
    required this.startMs,
    required this.endMs,
  });
}

// === Custom painter for the timeline ===
class _TimelinePainter extends CustomPainter {
  final List<TimelineRow> rows;
  final List<AudioTrack> clips;
  final List<int> visibleClipIndices;
  final String clipOverlapMode;
  final double Function(AudioTrack) getStartMs;
  final double Function(AudioTrack) getDurationMs;
  final double Function(AudioTrack) getTimelineDurationMs;
  final double Function(AudioTrack) getTrimStartMs;
  final double Function(AudioTrack) getTrimEndMs;
  final double Function(AudioTrack) getFullDurationMs;
  final List<double> Function(AudioTrack) getPeaks;
  final double pixelsPerMs;
  final double scrollOffsetMs;
  final double viewportWidth;
  final double rulerHeight;
  final double playheadPx; // === FIX ===: Use playheadPx
  final double transportMs;
  final int? clipLoopPreviewClipIndex;
  final double? clipLoopPreviewStartMs;
  final double? clipLoopPreviewFallbackMs;
  final int selectedClipIndex;
  final List<int> selectedClipIndices;
  final Map<String, int> clipVisualStackOrder;
  final bool stretchToolActive;
  final int? trimClipIndex; // === FIX ===: Added for trim halo/indicator
  // === FIX ===: Updated drag properties
  final int? draggedClipIndex;
  final double? draggedClipStartMs;
  final int? draggedClipRowIndex;
  final List<bool> rowExpanded; // === NEW ===
  final double rowHeight;
  final double kExpandedRowHeight; // === NEW ===
  final double verticalScrollOffset;
  final List<int> expandedTab;
  final List<double> effectsPanelHeights;
  final List<double> expandedHeights;
  final List<double> automationLaneHeights;
  final double masterAutomationLaneHeight;
  final bool isRecording;
  final int? recordingRowIndex;
  final double recordingStartMs;
  final List<double> recordingPeaks;
  final List<double> recordingPeakTimesMs;
  final double bpm;
  final int beatsPerBar;
  final int beatUnit;
  final int quantizeDivisions;
  final bool foregroundGridEnabled;
  final int? highlightedSegmentRow;
  final double? highlightedSegmentStartMs;
  final double? highlightedSegmentEndMs;
  final int? sampleDropPreviewRow;
  final double? sampleDropPreviewStartMs;
  final double? sampleDropPreviewEndMs;
  final bool sampleDropPreviewAllowed;
  final int? cutPreviewClipIndex;
  final double? cutPreviewMs;
  final List<_TimelineAutomationClipVisual> automationClipVisuals;
  final Set<int> rowsHiddenByCollapsedGroups;
  final double? leftVisibleExtensionPx;
  final int _clipDataHash;
  final int _automationClipHash;
  final int _rowsHiddenByCollapsedGroupsHash;
  final int _selectedClipIndicesHash;
  final int _clipVisualStackOrderHash;
  final int _rowExpandedHash;
  final int _expandedTabHash;
  final int _effectsPanelHeightsHash;
  final int _expandedHeightsHash;
  final int _automationLaneHeightsHash;
  final int _recordingPeaksHash;
  final int _recordingPeakTimesHash;
  final int _rowKindHash;
  final int _rowVisualHash;

  _TimelinePainter({
    required this.rows,
    required this.clips,
    required this.visibleClipIndices,
    required int clipVisualRevision,
    required this.clipOverlapMode,
    required this.getStartMs,
    required this.getDurationMs,
    required this.getTimelineDurationMs,
    required this.getTrimStartMs,
    required this.getTrimEndMs,
    required this.getFullDurationMs,
    required this.getPeaks,
    required this.pixelsPerMs,
    required this.scrollOffsetMs,
    required this.viewportWidth,
    required this.rulerHeight,
    required this.playheadPx, // === FIX ===
    required this.transportMs,
    required this.clipLoopPreviewClipIndex,
    required this.clipLoopPreviewStartMs,
    required this.clipLoopPreviewFallbackMs,
    required this.selectedClipIndex,
    required this.selectedClipIndices,
    required this.clipVisualStackOrder,
    required int clipVisualStackRevision,
    required this.stretchToolActive,
    this.trimClipIndex, // === FIX ===: Add to constructor
    this.draggedClipIndex,
    this.draggedClipStartMs,
    this.draggedClipRowIndex,
    required this.rowExpanded,
    required this.rowHeight,
    required this.kExpandedRowHeight,
    required this.verticalScrollOffset,
    required this.expandedTab,
    required this.effectsPanelHeights,
    required this.expandedHeights,
    required this.automationLaneHeights,
    required this.masterAutomationLaneHeight,
    required this.isRecording,
    required this.recordingRowIndex,
    required this.recordingStartMs,
    required this.recordingPeaks,
    required this.recordingPeakTimesMs,
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.quantizeDivisions,
    required this.foregroundGridEnabled,
    required this.highlightedSegmentRow,
    required this.highlightedSegmentStartMs,
    required this.highlightedSegmentEndMs,
    required this.sampleDropPreviewRow,
    required this.sampleDropPreviewStartMs,
    required this.sampleDropPreviewEndMs,
    required this.sampleDropPreviewAllowed,
    required this.cutPreviewClipIndex,
    required this.cutPreviewMs,
    required this.automationClipVisuals,
    required this.rowsHiddenByCollapsedGroups,
    this.leftVisibleExtensionPx,
  }) : _clipDataHash = clipVisualRevision,
       _automationClipHash = _computeAutomationClipHash(automationClipVisuals),
       _rowsHiddenByCollapsedGroupsHash = _hashList(
         (rowsHiddenByCollapsedGroups.toList()..sort()),
       ),
       _selectedClipIndicesHash = _hashList(selectedClipIndices),
       _clipVisualStackOrderHash = clipVisualStackRevision,
       _rowExpandedHash = _hashList(rowExpanded),
       _expandedTabHash = _hashList(expandedTab),
       _effectsPanelHeightsHash = _hashDoubleList(effectsPanelHeights),
       _expandedHeightsHash = _hashDoubleList(expandedHeights),
       _automationLaneHeightsHash = _hashDoubleList(automationLaneHeights),
       _recordingPeaksHash = _hashDoubleList(recordingPeaks),
       _recordingPeakTimesHash = _hashDoubleList(recordingPeakTimesMs),
       _rowKindHash = _hashList(
         rows
             .map((row) => row.kind == TimelineRowKind.instrument ? 1 : 0)
             .toList(growable: false),
       ),
       _rowVisualHash = _hashList(
         rows
             .map((row) => Object.hash(row.rowId, row.color, row.groupId))
             .toList(growable: false),
       );

  static int _computeAutomationClipHash(
    List<_TimelineAutomationClipVisual> clips,
  ) {
    var hash = 0;
    for (final visual in clips) {
      hash = _hashCombine(hash, visual.row);
      hash = _hashCombine(hash, visual.displayRow);
      hash = _hashCombine(hash, visual.laneIndex);
      hash = _hashCombine(hash, visual.targetId);
      hash = _hashCombine(hash, visual.isOrphan);
      hash = _hashCombine(hash, visual.clip.id);
      hash = _hashCombine(hash, visual.clip.patternId);
      hash = _hashCombine(hash, visual.clip.muted);
      hash = _hashCombine(hash, visual.isSelected);
      hash = _hashCombine(hash, _quantizeDouble(visual.rect.left));
      hash = _hashCombine(hash, _quantizeDouble(visual.rect.top));
      hash = _hashCombine(hash, _quantizeDouble(visual.rect.width));
      hash = _hashCombine(hash, _quantizeDouble(visual.rect.height));
    }
    return _hashFinish(hash);
  }

  static int _quantizeDouble(double value, {int scale = 1000}) {
    if (!value.isFinite) return 0;
    return (value * scale).round();
  }

  static int _hashDoubleList(List<double> values, {int scale = 1000}) {
    var hash = 0;
    for (final value in values) {
      hash = _hashCombine(hash, _quantizeDouble(value, scale: scale));
    }
    return _hashFinish(hash);
  }

  static int _hashList(List<dynamic> values) {
    var hash = 0;
    for (final value in values) {
      hash = _hashCombine(hash, value);
    }
    return _hashFinish(hash);
  }

  static int _hashCombine(int hash, Object? value) {
    hash = 0x1fffffff & (hash + value.hashCode);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int _hashFinish(int hash) {
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }

  double _automationLaneHeightForRow(int row) {
    if (row < 0 || row >= automationLaneHeights.length) return 0.0;
    return automationLaneHeights[row];
  }

  double _rowBlockHeight(int row) {
    final expanded = row >= 0 && row < expandedHeights.length
        ? expandedHeights[row]
        : 0.0;
    return rowHeight + _automationLaneHeightForRow(row) + expanded;
  }

  double _rowTopForIndex(int row) {
    double y = masterAutomationLaneHeight;
    for (int i = 0; i < row; i++) {
      if (_isRowHiddenByCollapsedGroup(i)) continue;
      y += _rowBlockHeight(i);
    }
    return y;
  }

  bool _isRowHiddenByCollapsedGroup(int row) {
    return rowsHiddenByCollapsedGroups.contains(row);
  }

  Map<String, _CollapsedGroupSummary> _collapsedGroupSummaries() {
    if (rowsHiddenByCollapsedGroups.isEmpty || rows.isEmpty || clips.isEmpty) {
      return const <String, _CollapsedGroupSummary>{};
    }

    final leadRowByGroupId = <String, int>{};
    final memberRowsByGroupId = <String, Set<int>>{};
    for (int row = 0; row < rows.length; row++) {
      final groupId = rows[row].groupId.trim();
      if (groupId.isEmpty) continue;
      memberRowsByGroupId.putIfAbsent(groupId, () => <int>{}).add(row);
      if (!_isRowHiddenByCollapsedGroup(row)) {
        leadRowByGroupId.putIfAbsent(groupId, () => row);
      }
    }

    final collapsedGroupIds = <String>{};
    for (final row in rowsHiddenByCollapsedGroups) {
      if (row < 0 || row >= rows.length) continue;
      final groupId = rows[row].groupId.trim();
      if (groupId.isNotEmpty && leadRowByGroupId.containsKey(groupId)) {
        collapsedGroupIds.add(groupId);
      }
    }
    if (collapsedGroupIds.isEmpty) {
      return const <String, _CollapsedGroupSummary>{};
    }

    final summaries = <String, _CollapsedGroupSummary>{};
    for (final groupId in collapsedGroupIds) {
      final leadRow = leadRowByGroupId[groupId];
      final memberRows = memberRowsByGroupId[groupId];
      if (leadRow == null || memberRows == null || memberRows.isEmpty) {
        continue;
      }

      final memberClipIndices = <int>[];
      double? startMs;
      double? endMs;
      for (final i in visibleClipIndices) {
        if (i < 0 || i >= clips.length) continue;
        final clip = clips[i];
        if (!memberRows.contains(clip.rowIndex)) continue;
        final clipStart = getStartMs(clip);
        final clipEnd = clipStart + getTimelineDurationMs(clip);
        if (clipEnd <= clipStart) continue;
        memberClipIndices.add(i);
        startMs = startMs == null ? clipStart : math.min(startMs, clipStart);
        endMs = endMs == null ? clipEnd : math.max(endMs, clipEnd);
      }

      if (memberClipIndices.isEmpty || startMs == null || endMs == null) {
        continue;
      }
      summaries[groupId] = _CollapsedGroupSummary(
        groupId: groupId,
        leadRow: leadRow,
        memberRows: memberRows,
        clipIndices: memberClipIndices,
        startMs: startMs,
        endMs: endMs,
      );
    }

    return summaries;
  }

  bool _isClipRepresentedByCollapsedGroup(
    AudioTrack clip,
    Map<String, _CollapsedGroupSummary> summaries,
  ) {
    if (summaries.isEmpty ||
        clip.rowIndex < 0 ||
        clip.rowIndex >= rows.length) {
      return false;
    }
    final groupId = rows[clip.rowIndex].groupId.trim();
    if (groupId.isEmpty) return false;
    final summary = summaries[groupId];
    return summary != null && summary.memberRows.contains(clip.rowIndex);
  }

  Color? _rowAccentColor(int row) {
    if (row < 0 || row >= rows.length) return null;
    final value = rows[row].color;
    if (value == 0) return null;
    return Color(value);
  }

  Color _clipFillColorForRow({
    required int row,
    required bool isMidi,
    required bool isSelected,
    required bool hasOverlap,
  }) {
    if (hasOverlap) return const Color(0xFFC06767);
    final accent = _rowAccentColor(row);
    if (accent == null) {
      return isMidi
          ? (isSelected ? _kTimelineClipMidiSelected : _kTimelineClipMidi)
          : (isSelected ? _kTimelineClipAudioSelected : _kTimelineClipAudio);
    }
    final alpha = isSelected ? 0.88 : 0.70;
    return accent.withValues(alpha: alpha);
  }

  Color _clipBorderColorForRow({required int row, required bool isSelected}) {
    final accent = _rowAccentColor(row);
    if (accent == null) {
      return isSelected
          ? _kTimelineClipAudioSelectedBorder
          : _kTimelineClipAudioBorder;
    }
    return isSelected
        ? Color.lerp(accent, Colors.white, 0.34)!.withValues(alpha: 0.95)
        : Color.lerp(accent, Colors.white, 0.18)!.withValues(alpha: 0.84);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // canvas.translate(0, -verticalScrollOffset); // ← APPLY VERTICAL SCROLL
    // Keep track of the current vertical position
    if (masterAutomationLaneHeight > 0.0) {
      final masterRect = Rect.fromLTWH(
        0,
        0,
        viewportWidth,
        masterAutomationLaneHeight,
      );
      canvas.drawRect(masterRect, Paint()..color = _kMasterAutomationLaneFill);
      canvas.drawLine(
        Offset(0, masterAutomationLaneHeight),
        Offset(viewportWidth, masterAutomationLaneHeight),
        Paint()
          ..color = _kMasterAutomationLaneBorder
          ..strokeWidth = 1,
      );
    }

    double currentY = masterAutomationLaneHeight;

    // convert playheadPx → ms
    final double playheadMs = scrollOffsetMs + playheadPx / pixelsPerMs;

    // Draw row backgrounds
    for (int row = 0; row < rowExpanded.length; row++) {
      if (_isRowHiddenByCollapsedGroup(row)) continue;
      final automationLaneHeight = _automationLaneHeightForRow(row);
      final isExpanded = rowExpanded[row];
      final expandedHeight = expandedHeights[row];
      final totalRowHeight = rowHeight + automationLaneHeight + expandedHeight;

      // 1. Draw the main track background (alternating colors)
      final rect = Rect.fromLTWH(0, currentY, viewportWidth, rowHeight);
      final paint = Paint()..color = _timelineRowFillColor(row.isEven);
      canvas.drawRect(rect, paint);

      if (automationLaneHeight > 0.0) {
        final automationRect = Rect.fromLTWH(
          0,
          currentY + rowHeight,
          viewportWidth,
          automationLaneHeight,
        );
        final automationPaint = Paint()
          ..color = _timelineAutomationLaneFillColor(row.isEven);
        canvas.drawRect(automationRect, automationPaint);
      }

      // 2. Draw the expanded section background (transparent, but maybe a slight tint for debugging/visual separation)
      if (isExpanded) {
        final expandedTop = currentY + rowHeight + automationLaneHeight;
        final expandedRect = Rect.fromLTWH(
          0,
          expandedTop,
          viewportWidth,
          expandedHeight.toDouble(),
        );
        final expandedPaint = Paint()..color = _timelineExpandedFillColor();
        canvas.drawRect(expandedRect, expandedPaint);
      }

      // 3. Draw horizontal grid lines for row separation (at the end of the total block)
      final linePaint = Paint()
        ..color = _kTimelineRowDivider
        ..strokeWidth = 1;

      canvas.drawLine(
        Offset(0, currentY + totalRowHeight),
        Offset(viewportWidth, currentY + totalRowHeight),
        linePaint,
      );

      currentY += totalRowHeight;
    }

    if (highlightedSegmentRow != null &&
        highlightedSegmentStartMs != null &&
        highlightedSegmentEndMs != null &&
        highlightedSegmentRow! >= 0 &&
        highlightedSegmentRow! < rowExpanded.length &&
        !_isRowHiddenByCollapsedGroup(highlightedSegmentRow!)) {
      final highlightY = _rowTopForIndex(highlightedSegmentRow!);

      final startX =
          (highlightedSegmentStartMs! - scrollOffsetMs) * pixelsPerMs;
      final endX = (highlightedSegmentEndMs! - scrollOffsetMs) * pixelsPerMs;
      final width = endX - startX;
      if (width > 0) {
        final rect = Rect.fromLTWH(
          startX,
          highlightY + 2,
          width,
          rowHeight - 4,
        );
        final clipped = rect.intersect(
          Rect.fromLTWH(0, 0, viewportWidth, size.height),
        );
        if (clipped.width > 0 && clipped.height > 0) {
          final fill = Paint()
            ..color = const Color.fromRGBO(43, 136, 222, 0.16);
          final stroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color.fromRGBO(107, 184, 255, 0.58);
          canvas.drawRect(clipped, fill);
          canvas.drawRect(clipped, stroke);
        }
      }
    }

    if (sampleDropPreviewRow != null &&
        sampleDropPreviewStartMs != null &&
        sampleDropPreviewEndMs != null &&
        sampleDropPreviewRow! >= 0 &&
        sampleDropPreviewRow! < rowExpanded.length &&
        !_isRowHiddenByCollapsedGroup(sampleDropPreviewRow!)) {
      final previewY = _rowTopForIndex(sampleDropPreviewRow!);

      final startX = (sampleDropPreviewStartMs! - scrollOffsetMs) * pixelsPerMs;
      final endX = (sampleDropPreviewEndMs! - scrollOffsetMs) * pixelsPerMs;
      final width = endX - startX;
      if (width > 0) {
        final rect = Rect.fromLTWH(startX, previewY + 2, width, rowHeight - 4);
        final clipped = rect.intersect(
          Rect.fromLTWH(0, 0, viewportWidth, size.height),
        );
        if (clipped.width > 0 && clipped.height > 0) {
          final fill = Paint()
            ..color = sampleDropPreviewAllowed
                ? const Color(0x7A6EE7B7)
                : const Color(0x66FF4F5E);
          final stroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.15
            ..color = sampleDropPreviewAllowed
                ? const Color(0xCCB7FFE3)
                : const Color(0xCCFFB1B8);
          canvas.drawRect(clipped, fill);
          canvas.drawRect(clipped, stroke);
        }
      }
    }

    final bool isMsUnderlayPass = (leftVisibleExtensionPx ?? 0.0) > 0.0;

    // Avoid drawing full-height vertical guides in the M/S passthrough strip.
    if (!isMsUnderlayPass && !foregroundGridEnabled) {
      _drawGrid(canvas, size); // Note: _drawGrid doesn't use vertical position
    }

    // === RECORDING PREVIEW ==========================================
    if (isRecording && recordingRowIndex != null) {
      final int recRow = recordingRowIndex!;
      if (!_isRowHiddenByCollapsedGroup(recRow)) {
        // Compute the row's vertical position on screen
        final recY = _rowTopForIndex(recRow);

        // final double recRowHeight = _AudioCanvasTimelineState.kRowHeight;
        // final Rect recRect = Rect.fromLTWH(
        //   0,
        //   recY,
        //   viewportWidth,
        //   recRowHeight,
        // );

        final double recYTop = recY + 2;
        final double recHeight = rowHeight - 4;

        final Rect recRect = Rect.fromLTWH(
          0,
          recYTop,
          viewportWidth,
          recHeight,
        );

        final double recDurationMs = playheadMs - recordingStartMs;
        if (recDurationMs > 0) {
          _paintRecordingPreview(
            canvas,
            recRect,
            pixelsPerMs,
            recordingStartMs - scrollOffsetMs,
            recDurationMs,
            recordingPeaks,
            recordingPeakTimesMs,
          );
        }
      }
    }
    // ================================================================

    final overlapMode = _normalizedClipOverlapMode();
    final overlappingClipIndices = overlapMode == 'off'
        ? _computeOverlapByClip()
        : const <int>{};
    final crossfadeVisuals = _crossfadeModeActive(overlapMode)
        ? _computeCrossfadeVisuals(curveMode: overlapMode)
        : const <_ClipCrossfadeVisual>[];
    final draggingGroup =
        draggedClipIndex != null &&
        selectedClipIndices.length > 1 &&
        selectedClipIndices.contains(draggedClipIndex) &&
        draggedClipStartMs != null &&
        draggedClipRowIndex != null;
    final invalidDragRow = _invalidDragTargetRow(draggingGroup);
    if (invalidDragRow != null) {
      final y = _rowTopForIndex(invalidDragRow);
      final rect = Rect.fromLTWH(0, y, viewportWidth, rowHeight);
      final fill = Paint()..color = const Color(0x66FF4F5E);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xCCFFB1B8);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect.deflate(1), stroke);
    }

    final collapsedGroupSummaries = _collapsedGroupSummaries();
    _drawCollapsedGroupSummaries(canvas, collapsedGroupSummaries);

    for (final i in _clipPaintOrder()) {
      if (draggingGroup && selectedClipIndices.contains(i)) continue;
      if (!draggingGroup && i == draggedClipIndex) continue;
      if (_isClipRepresentedByCollapsedGroup(
        clips[i],
        collapsedGroupSummaries,
      )) {
        continue;
      }
      _drawClip(canvas, i, false, overlappingClipIndices);
    }
    if (draggingGroup) {
      for (final index in selectedClipIndices) {
        if (index < 0 || index >= clips.length) continue;
        if (_isClipRepresentedByCollapsedGroup(
          clips[index],
          collapsedGroupSummaries,
        )) {
          continue;
        }
        _drawClip(canvas, index, true, overlappingClipIndices);
      }
    } else if (draggedClipIndex != null) {
      final clip = clips[draggedClipIndex!];
      if (!_isClipRepresentedByCollapsedGroup(clip, collapsedGroupSummaries)) {
        _drawClip(canvas, draggedClipIndex!, true, overlappingClipIndices);
      }
    }
    _drawCrossfadeVisuals(canvas, crossfadeVisuals);
    if (!isMsUnderlayPass && foregroundGridEnabled) {
      _drawGrid(canvas, size);
    }
    _drawSelectedClipHandlesOverlay(canvas);
    _drawTimelineAutomationClips(canvas, size);
    _drawCutPreviewLine(canvas);

    // Draw playhead (centered)
    if (!isMsUnderlayPass) {
      _drawPlayhead(canvas, size);
    }

    canvas.restore(); // Always restore!
  }

  String _normalizedClipOverlapMode() {
    switch (clipOverlapMode.trim().toLowerCase()) {
      case 'none':
      case 'off':
        return 'off';
      case 'cut':
        return 'cut';
      case 'linear':
      case 'linear_crossfade':
      case 'linear-crossfade':
      case 'fade':
      case 'x':
        return 'linear';
      case 'eqp':
      case 'equal_power':
      case 'equal-power':
      case 'equalpower':
      case 'crossfade':
        return 'equal_power';
      case 's_curve':
      case 's-curve':
      case 'scurve':
        return 's_curve';
      default:
        return 'equal_power';
    }
  }

  bool _crossfadeModeActive(String mode) =>
      mode == 'linear' || mode == 'equal_power' || mode == 's_curve';

  bool _isClipSelected(int index) {
    return index == selectedClipIndex || selectedClipIndices.contains(index);
  }

  String _clipVisualStackKey(AudioTrack clip, int fallbackIndex) {
    final clipId = clip.clipId.trim();
    if (clipId.isNotEmpty) return 'clip:$clipId';
    if (clip.engineClipId >= 0) return 'engine:${clip.engineClipId}';
    return 'index:$fallbackIndex';
  }

  int _clipVisualStackOrderForIndex(int index) {
    if (index < 0 || index >= clips.length) return 0;
    return clipVisualStackOrder[_clipVisualStackKey(clips[index], index)] ?? 0;
  }

  List<int> _clipPaintOrder() {
    return List<int>.from(visibleClipIndices)..sort((a, b) {
      final stackCompare = _clipVisualStackOrderForIndex(
        a,
      ).compareTo(_clipVisualStackOrderForIndex(b));
      if (stackCompare != 0) return stackCompare;
      return a.compareTo(b);
    });
  }

  bool _rowAllowsClip(int row, AudioTrack clip) {
    if (row < 0 || row >= rows.length) return false;
    final rowIsInstrument = rows[row].isInstrumentLane;
    return rowIsInstrument ? clip.isMidi : !clip.isMidi;
  }

  void _drawCollapsedGroupSummaries(
    Canvas canvas,
    Map<String, _CollapsedGroupSummary> summaries,
  ) {
    if (summaries.isEmpty) return;
    final leftExtension = leftVisibleExtensionPx ?? 0.0;
    final viewportClip = Rect.fromLTRB(
      -leftExtension,
      0,
      viewportWidth,
      double.infinity,
    );

    for (final summary in summaries.values) {
      if (summary.leadRow < 0 || summary.leadRow >= rowExpanded.length) {
        continue;
      }
      if (_isRowHiddenByCollapsedGroup(summary.leadRow)) continue;
      final widthMs = summary.endMs - summary.startMs;
      if (widthMs <= 0) continue;

      final x = (summary.startMs - scrollOffsetMs) * pixelsPerMs;
      final width = widthMs * pixelsPerMs;
      if (x + width < -leftExtension || x > viewportWidth) continue;

      final y = _rowTopForIndex(summary.leadRow) + 2.0;
      final height = rowHeight - 4.0;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        const Radius.circular(7),
      );
      final visibleRect = rect.outerRect.intersect(viewportClip);
      if (visibleRect.width <= 0 || visibleRect.height <= 0) continue;

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            const Color(0xFFE5EAF0).withValues(alpha: 0.74),
            const Color(0xFF9EA8B1).withValues(alpha: 0.72),
          ],
        ).createShader(rect.outerRect);
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..color = Colors.white.withValues(alpha: 0.70);

      canvas.save();
      canvas.clipRect(viewportClip);
      canvas.drawRRect(rect, fillPaint);

      for (final clipIndex in summary.clipIndices) {
        if (clipIndex < 0 || clipIndex >= clips.length) continue;
        final clip = clips[clipIndex];
        final clipStartMs = getStartMs(clip);
        final clipDurationMs = getTimelineDurationMs(clip);
        if (clipDurationMs <= 0) continue;
        final clipX = (clipStartMs - scrollOffsetMs) * pixelsPerMs;
        final clipWidth = clipDurationMs * pixelsPerMs;
        if (clipX + clipWidth < -leftExtension || clipX > viewportWidth) {
          continue;
        }
        final clipRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            clipX,
            rect.outerRect.top + 5.0,
            clipWidth,
            math.max(4.0, rect.outerRect.height - 10.0),
          ),
          const Radius.circular(4),
        );
        canvas.save();
        canvas.clipRRect(rect);
        if (clip.isMidi) {
          _drawMidiPreview(
            canvas,
            clipRect,
            clip.midiNotes,
            getTrimStartMs(clip),
            getTrimEndMs(clip),
            sourceBpm: clip.sourceTempoBpm > 0.0 ? clip.sourceTempoBpm : bpm,
          );
        } else {
          final peaks = getPeaks(clip);
          if (peaks.isNotEmpty) {
            final fullDurationMs = getFullDurationMs(clip);
            final rawVisibleMs = (getTrimEndMs(clip) - getTrimStartMs(clip))
                .clamp(1.0, double.infinity);
            final timelineVisibleMs = getTimelineDurationMs(
              clip,
            ).clamp(1.0, double.infinity);
            _drawWaveform(
              canvas,
              peaks,
              clipRect,
              getTrimStartMs(clip),
              getTrimEndMs(clip),
              fullDurationMs,
              timelineVisibleMs / rawVisibleMs,
              gainScale: _clipEffectiveGainLinear(clip),
              isReversed: clip.isReversed,
              color: Colors.white.withValues(alpha: 0.78),
            );
          }
        }
        canvas.restore();
      }

      canvas.drawRRect(rect, borderPaint);
      canvas.restore();
    }
  }

  int? _invalidDragTargetRow(bool draggingGroup) {
    final targetRow = draggedClipRowIndex;
    if (draggedClipIndex == null ||
        targetRow == null ||
        targetRow < 0 ||
        targetRow >= rows.length) {
      return null;
    }
    if (_isRowHiddenByCollapsedGroup(targetRow)) return null;
    if (draggingGroup) {
      final origin = clips[draggedClipIndex!];
      final deltaRows = targetRow - origin.rowIndex;
      for (final index in selectedClipIndices) {
        if (index < 0 || index >= clips.length) continue;
        final clip = clips[index];
        final row = (clip.rowIndex + deltaRows).clamp(0, rows.length - 1);
        if (_isRowHiddenByCollapsedGroup(row.toInt())) return row.toInt();
        if (!_rowAllowsClip(row.toInt(), clip)) return row.toInt();
      }
      return null;
    }
    final clip = clips[draggedClipIndex!];
    return _rowAllowsClip(targetRow, clip) ? null : targetRow;
  }

  double _clipGainUiToLinear(double gainUi) {
    const dbMin = -60.0;
    const dbMax = 6.0;
    const uiMin = 0.0;
    const uiUnity = 2.0;
    const uiMax = 3.0;

    final userGain = gainUi.clamp(uiMin, uiMax).toDouble();
    final db = userGain <= uiUnity
        ? dbMin +
              ((0.0 - dbMin) *
                  ((userGain - uiMin) / (uiUnity - uiMin)).clamp(0.0, 1.0))
        : (dbMax * ((userGain - uiUnity) / (uiMax - uiUnity)).clamp(0.0, 1.0));
    if (db <= dbMin + 0.001) return 0.0;
    return math.pow(10.0, db / 20.0).toDouble();
  }

  double _clipEffectiveGainLinear(AudioTrack clip) {
    final normalizeGain = (!clip.isMidi && clip.normalizeVolume)
        ? clip.normalizeGain.clamp(0.0, 64.0).toDouble()
        : 1.0;
    return _clipGainUiToLinear(clip.gain) * normalizeGain;
  }

  // void _drawGrid(Canvas canvas, Size size) {
  //   final paint = Paint()
  //     ..color = const Color.fromARGB(255, 255, 255, 255).withOpacity(0.05)
  //     ..strokeWidth = 1;

  //   final startSecond = math.max(0, (scrollOffsetMs / 1000).floor());
  //   final endSecond = ((scrollOffsetMs + viewportWidth / pixelsPerMs) / 1000).ceil();
  //   for (int sec = startSecond; sec <= endSecond; sec++) {
  //     // === FIX ===: Removed offset
  //     final x = (sec * 1000 - scrollOffsetMs) * pixelsPerMs;
  //     if (x >= 0 && x <= viewportWidth) {
  //       canvas.drawLine(
  //         Offset(x, 0),
  //         Offset(x, size.height),
  //         paint,
  //       );
  //     }
  //   }
  //   // Horizontal grid lines... (unchanged)
  //   // for (int row = 1; row < _AudioCanvasTimelineState.kNumRows; row++) {
  //   //   canvas.drawLine(
  //   //     Offset(0, row * _AudioCanvasTimelineState.kRowHeight),
  //   //     Offset(viewportWidth, row * _AudioCanvasTimelineState.kRowHeight),
  //   //     paint,
  //   //   );
  //   // }
  // }

  void _drawGrid(Canvas canvas, Size size) {
    final safeBeatsPerBar = math.max(1, beatsPerBar);
    final safeBeatUnit = math.max(1, beatUnit);
    final msPerBar = (60000 / bpm) * safeBeatsPerBar * 4.0 / safeBeatUnit;
    final msPerBeat = msPerBar / safeBeatsPerBar;
    final pxPerBar = msPerBar * pixelsPerMs;
    final zoomVisibility = ((pxPerBar - 3.0) / 18.0).clamp(0.0, 1.0);
    final opacityScale = 0.35 + (0.65 * zoomVisibility);

    final majorPaint = Paint()
      ..color = Colors.white.withOpacity(0.08 * opacityScale)
      ..strokeWidth = 1.5;

    final beatPaint = Paint()
      ..color = Colors.white.withOpacity(0.06 * opacityScale)
      ..strokeWidth = 1.1;

    final minorPaint = Paint()
      ..color = Colors.white.withOpacity(0.04 * opacityScale)
      ..strokeWidth = 1;

    final subdivisions = math.max(1, quantizeDivisions);
    final msPerSubdivision = msPerBar / subdivisions;

    final visibleStartMs = scrollOffsetMs;
    final visibleEndMs = scrollOffsetMs + viewportWidth / pixelsPerMs;

    // ✅ CLAMP so nothing appears before bar 1
    final rawStartBar = (visibleStartMs / msPerBar).floor();
    final rawEndBar = (visibleEndMs / msPerBar).ceil();
    final startBar = math.max(0, math.min(rawStartBar, rawEndBar));
    final endBar = math.max(0, math.max(rawStartBar, rawEndBar));

    for (int bar = startBar; bar <= endBar; bar++) {
      final barMs = bar * msPerBar;
      final barX = (barMs - scrollOffsetMs) * pixelsPerMs;

      if (barX >= 0 && barX <= viewportWidth) {
        // === BAR LINE ===
        canvas.drawLine(Offset(barX, 0), Offset(barX, size.height), majorPaint);
      }

      // Subdivisions inside each bar are driven by magnet quantize setting.
      for (int sub = 1; sub < subdivisions; sub++) {
        final subMs = barMs + sub * msPerSubdivision;
        final subX = (subMs - scrollOffsetMs) * pixelsPerMs;

        if (subX >= 0 && subX <= viewportWidth) {
          canvas.drawLine(
            Offset(subX, 0),
            Offset(subX, size.height),
            minorPaint,
          );
        }
      }

      for (int beat = 1; beat < safeBeatsPerBar; beat++) {
        final beatMs = barMs + (beat * msPerBeat);
        final beatX = (beatMs - scrollOffsetMs) * pixelsPerMs;
        if (beatX >= 0 && beatX <= viewportWidth) {
          canvas.drawLine(
            Offset(beatX, 0),
            Offset(beatX, size.height),
            beatPaint,
          );
        }
      }
    }
  }

  Set<int> _computeOverlapByClip() {
    const double overlapEpsilonMs = 0.5;
    final overlap = <int>{};
    if (visibleClipIndices.length < 2) return overlap;
    final draggingGroup =
        draggedClipIndex != null &&
        selectedClipIndices.length > 1 &&
        selectedClipIndices.contains(draggedClipIndex) &&
        draggedClipStartMs != null &&
        draggedClipRowIndex != null;
    final draggedOrigin = draggingGroup ? clips[draggedClipIndex!] : null;
    final dragDeltaMs = draggingGroup && draggedOrigin != null
        ? draggedClipStartMs! - getStartMs(draggedOrigin)
        : 0.0;
    final dragDeltaRows = draggingGroup && draggedOrigin != null
        ? draggedClipRowIndex! - draggedOrigin.rowIndex
        : 0;

    final spansByRow = <int, List<_ClipOverlapSpan>>{};

    for (final i in visibleClipIndices) {
      if (i < 0 || i >= clips.length) continue;
      final clip = clips[i];
      final previewedInGroup = draggingGroup && selectedClipIndices.contains(i);
      final startMs = previewedInGroup
          ? getStartMs(clip) + dragDeltaMs
          : (i == draggedClipIndex && draggedClipStartMs != null)
          ? draggedClipStartMs!
          : getStartMs(clip);
      final row = previewedInGroup
          ? clip.rowIndex + dragDeltaRows
          : (i == draggedClipIndex && draggedClipRowIndex != null)
          ? draggedClipRowIndex!
          : clip.rowIndex;
      final visualDuration = getTimelineDurationMs(clip);
      if (visualDuration <= 0) continue;

      (spansByRow[row] ??= <_ClipOverlapSpan>[]).add(
        _ClipOverlapSpan(
          index: i,
          row: row,
          startMs: startMs,
          endMs: startMs + visualDuration,
        ),
      );
    }

    for (final spans in spansByRow.values) {
      if (spans.length < 2) continue;
      spans.sort((a, b) => a.startMs.compareTo(b.startMs));

      var furthestEnd = double.negativeInfinity;
      var furthestIndex = -1;

      for (final span in spans) {
        // Treat near-equal boundaries as touching, not overlapping.
        if (span.startMs < (furthestEnd - overlapEpsilonMs)) {
          overlap.add(span.index);
          if (furthestIndex >= 0) {
            overlap.add(furthestIndex);
          }
        }
        if (span.endMs > furthestEnd) {
          furthestEnd = span.endMs;
          furthestIndex = span.index;
        }
      }
    }

    return overlap;
  }

  List<_ClipCrossfadeVisual> _computeCrossfadeVisuals({
    required String curveMode,
  }) {
    const double overlapEpsilonMs = 0.5;
    final visuals = <_ClipCrossfadeVisual>[];
    if (visibleClipIndices.length < 2) return visuals;
    final draggingGroup =
        draggedClipIndex != null &&
        selectedClipIndices.length > 1 &&
        selectedClipIndices.contains(draggedClipIndex) &&
        draggedClipStartMs != null &&
        draggedClipRowIndex != null;
    final draggedOrigin = draggingGroup ? clips[draggedClipIndex!] : null;
    final dragDeltaMs = draggingGroup && draggedOrigin != null
        ? draggedClipStartMs! - getStartMs(draggedOrigin)
        : 0.0;
    final dragDeltaRows = draggingGroup && draggedOrigin != null
        ? draggedClipRowIndex! - draggedOrigin.rowIndex
        : 0;

    final spansByRow = <int, List<_ClipOverlapSpan>>{};
    for (final i in visibleClipIndices) {
      if (i < 0 || i >= clips.length) continue;
      final clip = clips[i];
      if (clip.clipKind == ClipKind.midi) continue;
      final previewedInGroup = draggingGroup && selectedClipIndices.contains(i);
      final startMs = previewedInGroup
          ? getStartMs(clip) + dragDeltaMs
          : (i == draggedClipIndex && draggedClipStartMs != null)
          ? draggedClipStartMs!
          : getStartMs(clip);
      final row = previewedInGroup
          ? clip.rowIndex + dragDeltaRows
          : (i == draggedClipIndex && draggedClipRowIndex != null)
          ? draggedClipRowIndex!
          : clip.rowIndex;
      if (_isRowHiddenByCollapsedGroup(row)) continue;
      final visualDuration = getTimelineDurationMs(clip);
      if (visualDuration <= 0) continue;
      (spansByRow[row] ??= <_ClipOverlapSpan>[]).add(
        _ClipOverlapSpan(
          index: i,
          row: row,
          startMs: startMs,
          endMs: startMs + visualDuration,
        ),
      );
    }

    for (final spans in spansByRow.values) {
      if (spans.length < 2) continue;
      spans.sort((a, b) => a.startMs.compareTo(b.startMs));
      for (int i = 0; i < spans.length - 1; i++) {
        final left = spans[i];
        for (int j = i + 1; j < spans.length; j++) {
          final right = spans[j];
          if (right.startMs >= left.endMs - overlapEpsilonMs) break;
          final startMs = math.max(left.startMs, right.startMs);
          final endMs = math.min(left.endMs, right.endMs);
          if (endMs <= startMs + overlapEpsilonMs) continue;
          visuals.add(
            _ClipCrossfadeVisual(
              row: left.row,
              startMs: startMs,
              endMs: endMs,
              curveMode: curveMode,
            ),
          );
        }
      }
    }
    return visuals;
  }

  void _drawCrossfadeVisuals(
    Canvas canvas,
    List<_ClipCrossfadeVisual> visuals,
  ) {
    if (visuals.isEmpty) return;
    final leftExtension = leftVisibleExtensionPx ?? 0.0;
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFBFD8FF).withValues(alpha: 0.035);
    final envelopeShadePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF06111E).withValues(alpha: 0.24);
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFFE6F0FF).withValues(alpha: 0.34);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.72);

    for (final visual in visuals) {
      if (visual.row < 0 || visual.row >= rowExpanded.length) continue;
      if (_isRowHiddenByCollapsedGroup(visual.row)) continue;
      final left = (visual.startMs - scrollOffsetMs) * pixelsPerMs;
      final right = (visual.endMs - scrollOffsetMs) * pixelsPerMs;
      if (right < -leftExtension || left > viewportWidth) continue;
      final top = _rowTopForIndex(visual.row) + 2.0;
      final height = rowHeight - 4.0;
      final fullRect = Rect.fromLTRB(
        left,
        top + 1.0,
        right,
        top + height - 1.0,
      );
      final visibleClip = Rect.fromLTRB(
        -leftExtension,
        top,
        viewportWidth,
        top + height,
      );
      final visibleRect = fullRect.intersect(visibleClip);
      if (fullRect.width <= 1.0 ||
          fullRect.height <= 1.0 ||
          visibleRect.width <= 1.0 ||
          visibleRect.height <= 1.0) {
        continue;
      }

      final rrect = RRect.fromRectAndRadius(
        fullRect,
        const Radius.circular(3.5),
      );
      canvas.save();
      canvas.clipRect(visibleClip);
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, borderPaint);

      final insetRect = fullRect.deflate(1.5);
      if (visual.curveMode == 'linear') {
        final underBothLines = Path()
          ..moveTo(insetRect.left, insetRect.bottom)
          ..lineTo(
            insetRect.left + (insetRect.width * 0.5),
            insetRect.center.dy,
          )
          ..lineTo(insetRect.right, insetRect.bottom)
          ..close();
        canvas.drawPath(underBothLines, envelopeShadePaint);
        canvas.drawLine(insetRect.topLeft, insetRect.bottomRight, linePaint);
        canvas.drawLine(insetRect.bottomLeft, insetRect.topRight, linePaint);
      } else {
        double shapedGain(double t) {
          t = t.clamp(0.0, 1.0);
          if (visual.curveMode == 's_curve') {
            final s = t * t * (3.0 - (2.0 * t));
            return math.sin(s * math.pi * 0.5);
          }
          return math.sin(t * math.pi * 0.5);
        }

        double fadeOutY(double t) {
          final gain = shapedGain(1.0 - t);
          return insetRect.top + (insetRect.height * (1.0 - gain));
        }

        double fadeInY(double t) {
          final gain = shapedGain(t);
          return insetRect.bottom - (insetRect.height * gain);
        }

        const samples = 28;
        final fadeOut = Path();
        final fadeIn = Path();
        final underBothCurves = Path()
          ..moveTo(insetRect.left, insetRect.bottom);
        for (int i = 0; i <= samples; i++) {
          final t = i / samples;
          final x = insetRect.left + (insetRect.width * t);
          final outY = fadeOutY(t);
          final inY = fadeInY(t);
          if (i == 0) {
            fadeOut.moveTo(x, outY);
            fadeIn.moveTo(x, inY);
          } else {
            fadeOut.lineTo(x, outY);
            fadeIn.lineTo(x, inY);
          }
          underBothCurves.lineTo(x, math.max(outY, inY));
        }
        underBothCurves
          ..lineTo(insetRect.right, insetRect.bottom)
          ..close();
        canvas.drawPath(underBothCurves, envelopeShadePaint);
        canvas.drawPath(fadeOut, linePaint);
        canvas.drawPath(fadeIn, linePaint);
      }
      canvas.restore();
    }
  }

  void _drawClip(
    Canvas canvas,
    int index,
    bool isDragging,
    Set<int> overlapByClip,
  ) {
    final clip = clips[index];
    final draggingGroup =
        draggedClipIndex != null &&
        selectedClipIndices.length > 1 &&
        selectedClipIndices.contains(draggedClipIndex) &&
        draggedClipStartMs != null &&
        draggedClipRowIndex != null;
    final previewedInGroup =
        draggingGroup && isDragging && selectedClipIndices.contains(index);
    final draggedOrigin = draggingGroup ? clips[draggedClipIndex!] : null;
    final dragDeltaMs = previewedInGroup && draggedOrigin != null
        ? draggedClipStartMs! - getStartMs(draggedOrigin)
        : 0.0;
    final dragDeltaRows = previewedInGroup && draggedOrigin != null
        ? draggedClipRowIndex! - draggedOrigin.rowIndex
        : 0;

    // === FIX ===: Use drag state if provided
    final startMs = previewedInGroup
        ? getStartMs(clip) + dragDeltaMs
        : isDragging
        ? (draggedClipStartMs ?? getStartMs(clip))
        : getStartMs(clip);
    final trimStartMs = getTrimStartMs(clip);
    final trimEndMs = getTrimEndMs(clip);
    final peaks = getPeaks(clip);
    final visualDuration = getTimelineDurationMs(clip);
    final row = previewedInGroup
        ? clip.rowIndex + dragDeltaRows
        : isDragging
        ? (draggedClipRowIndex ?? clip.rowIndex)
        : clip.rowIndex;
    if (_isRowHiddenByCollapsedGroup(row)) return;

    final yOffset = _rowTopForIndex(row);

    // visual left follows the new startMs
    final x = (startMs - scrollOffsetMs) * pixelsPerMs;
    final y =
        yOffset + 2; //final y = row * _AudioCanvasTimelineState.kRowHeight;
    final width = visualDuration * pixelsPerMs;
    final double height = rowHeight - 4;

    // Skip if completely off-screen
    final leftExtension = leftVisibleExtensionPx ?? 0.0;
    if (x + width < -leftExtension || x > viewportWidth) return;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, width, height), // Use calculated y
      const Radius.circular(6),
    );
    final hasOverlap = overlapByClip.contains(index);
    final isMidi = clip.clipKind == ClipKind.midi;
    final isSelected = _isClipSelected(index);
    final isLoopPreview = clipLoopPreviewClipIndex == index;
    final showEdgeHandles =
        selectedClipIndices.length <= 1 && index == selectedClipIndex;

    // Draw clip background
    final clipPaint = Paint()
      ..color = _clipFillColorForRow(
        row: row,
        isMidi: isMidi,
        isSelected: isSelected,
        hasOverlap: hasOverlap,
      );

    // === FIX ===: Make dragged clip semi-transparent
    if (isDragging) {
      clipPaint.color = clipPaint.color.withValues(alpha: 0.62);
    }

    canvas.drawRRect(rect, clipPaint);

    // Draw waveform for audio clips even when very zoomed out.
    if (!isMidi && peaks.isNotEmpty && width > 0.5) {
      canvas.save();
      canvas.clipRRect(rect); // This is the crucial clipping/stencil

      final fullDurationMs = getFullDurationMs(clip);
      final rawVisibleMs = (trimEndMs - trimStartMs).clamp(
        1.0,
        double.infinity,
      );
      final timelineVisibleMs = getTimelineDurationMs(
        clip,
      ).clamp(1.0, double.infinity);
      final stretchScale = timelineVisibleMs / rawVisibleMs;

      _drawWaveform(
        canvas,
        peaks,
        rect,
        trimStartMs,
        trimEndMs,
        fullDurationMs,
        stretchScale,
        gainScale: _clipEffectiveGainLinear(clip),
        isReversed: clip.isReversed,
      );

      canvas.restore();
    }
    if (isMidi && width > 16) {
      canvas.save();
      canvas.clipRRect(rect);
      _drawMidiPreview(
        canvas,
        rect,
        clip.midiNotes,
        trimStartMs,
        trimEndMs,
        sourceBpm: clip.sourceTempoBpm > 0.0 ? clip.sourceTempoBpm : bpm,
      );
      canvas.restore();
    }
    // Hide clip labels in the M/S passthrough underlay strip.
    final bool paintClipLabelInThisPass =
        (leftVisibleExtensionPx ?? 0.0) == 0.0;
    if (paintClipLabelInThisPass) {
      _drawClipLabel(canvas, rect, clip);
    }

    if (isLoopPreview) {
      final clipStartMs = startMs;
      final clipEndMs = startMs + visualDuration;
      final previewStart = (clipLoopPreviewStartMs ?? clipStartMs)
          .clamp(clipStartMs, clipEndMs)
          .toDouble();
      final current = (transportMs >= clipStartMs && transportMs <= clipEndMs)
          ? transportMs
          : (clipLoopPreviewFallbackMs ?? previewStart);
      final previewNow = current.clamp(previewStart, clipEndMs).toDouble();
      final startX =
          rect.left +
          ((previewStart - clipStartMs) / visualDuration) * rect.width;
      final nowX =
          rect.left +
          ((previewNow - clipStartMs) / visualDuration) * rect.width;
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF7BE0FF).withValues(alpha: 0.15);
      final sweepPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF7BE0FF).withValues(alpha: 0.24);
      final lineGlow = Paint()
        ..color = const Color(0xFF7BE0FF).withValues(alpha: 0.54)
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round;
      final linePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round;
      canvas.save();
      canvas.clipRRect(rect);
      canvas.drawRRect(rect, fillPaint);
      if (nowX > startX + 0.5) {
        canvas.drawRect(
          Rect.fromLTRB(startX, rect.top, nowX, rect.bottom),
          sweepPaint,
        );
      }
      canvas.drawLine(
        Offset(nowX, rect.top + 3),
        Offset(nowX, rect.bottom - 3),
        lineGlow,
      );
      canvas.drawLine(
        Offset(nowX, rect.top + 3),
        Offset(nowX, rect.bottom - 3),
        linePaint,
      );
      canvas.restore();
    }

    // Draw border
    final bool isTrimming = index == trimClipIndex; // === FIX ===

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2; // Increased width for better visibility

    if (isLoopPreview) {
      borderPaint.color = const Color(0xFF7BE0FF);
      borderPaint.strokeWidth = 2.5;
    } else if (isTrimming) {
      // === FIX ===: Trim mode halo
      borderPaint.color = const Color(0xFF69B8FF);
      borderPaint.strokeWidth = 3;
    } else {
      // Existing border logic
      borderPaint.color = _clipBorderColorForRow(
        row: row,
        isSelected: isSelected,
      );
      borderPaint.strokeWidth = isSelected ? 2 : 1;
    }

    canvas.drawRRect(rect, borderPaint);

    // Draw edge handles if selected.
    if (showEdgeHandles && !isDragging) {
      // Handles are painted in a final overlay pass so neighboring clips never
      // cover them when clips are adjacent.
    }
  }

  void _drawSelectedClipHandlesOverlay(Canvas canvas) {
    if (selectedClipIndices.length != 1) return;
    if (selectedClipIndex < 0 || selectedClipIndex >= clips.length) return;
    if (draggedClipIndex == selectedClipIndex) return;

    final clip = clips[selectedClipIndex];
    if (_isRowHiddenByCollapsedGroup(clip.rowIndex)) return;
    final startMs = getStartMs(clip);
    final trimStartMs = getTrimStartMs(clip);
    final trimEndMs = getTrimEndMs(clip);
    final visualDuration = getTimelineDurationMs(clip);
    final x = (startMs - scrollOffsetMs) * pixelsPerMs;
    final y = _rowTopForIndex(clip.rowIndex) + 2;
    final width = visualDuration * pixelsPerMs;
    final double height = rowHeight - 4;
    final leftExtension = leftVisibleExtensionPx ?? 0.0;
    if (x + width < -leftExtension || x > viewportWidth) return;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, width, height),
      const Radius.circular(6),
    );
    final isMidi = clip.clipKind == ClipKind.midi;
    if (visualDuration <= 0 || (trimEndMs - trimStartMs) <= 0) return;

    _drawTrimHandles(
      canvas,
      rect,
      asStretchHandles: stretchToolActive && !isMidi,
      stretchEnabled: clip.stretchToProjectTempo,
      preservePitch: clip.tempoStretchPreservePitch,
    );
  }

  Color _automationColorForTarget(String targetId, {bool isOrphan = false}) {
    if (isOrphan) {
      return const Color(0xFFD25C68);
    }
    const palette = <Color>[
      Color(0xFF4D8DF0),
      Color(0xFF42B985),
      Color(0xFFE19A44),
      Color(0xFF58B9CF),
      Color(0xFFD36D61),
      Color(0xFF89B45B),
    ];
    var hash = 0;
    for (final rune in targetId.runes) {
      hash = ((hash * 31) + rune) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  void _drawAutomationClipPointPreview(
    Canvas canvas,
    Rect rect,
    AutomationClipSnapshot clip,
  ) {
    if (rect.width <= 2.0 || rect.height <= 2.0) return;

    final points =
        clip.points
            .map(
              (p) => AutomationPoint(
                x: p.x.clamp(0.0, clip.lengthMs).toDouble(),
                volume: p.volume.clamp(0.0, 1.0).toDouble(),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.x.compareTo(b.x));
    if (points.isEmpty) return;

    final safeLength = clip.lengthMs.abs() < 1e-6 ? 1.0 : clip.lengthMs;
    Offset toOffset(AutomationPoint p) {
      final t = (p.x / safeLength).clamp(0.0, 1.0).toDouble();
      final x = rect.left + (t * rect.width);
      final y = rect.bottom - (p.volume * rect.height);
      return Offset(x, y.clamp(rect.top, rect.bottom));
    }

    final path = Path();
    if (points.length == 1) {
      final y = toOffset(points.first).dy;
      path.moveTo(rect.left, y);
      path.lineTo(rect.right, y);
    } else {
      final first = toOffset(points.first);
      path.moveTo(rect.left, first.dy);
      path.lineTo(first.dx, first.dy);
      for (int i = 1; i < points.length; i++) {
        final o = toOffset(points[i]);
        path.lineTo(o.dx, o.dy);
      }
      final last = toOffset(points.last);
      path.lineTo(rect.right, last.dy);
    }

    final previewPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = clip.muted
          ? Colors.white.withOpacity(0.22)
          : Colors.white.withOpacity(0.78);
    canvas.drawPath(path, previewPaint);

    if (rect.width > 20 && rect.height > 10) {
      final pointPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = clip.muted
            ? Colors.white.withOpacity(0.34)
            : Colors.white.withOpacity(0.9);
      for (final p in points) {
        final o = toOffset(p);
        canvas.drawCircle(o, 1.7, pointPaint);
      }
    }
  }

  void _drawTimelineAutomationClips(Canvas canvas, Size size) {
    if (automationClipVisuals.isEmpty) return;
    final textPainter = TextPainter(
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    );

    for (final visual in automationClipVisuals) {
      if (_isRowHiddenByCollapsedGroup(visual.displayRow)) continue;
      final rect = visual.rect;
      final leftExtension = leftVisibleExtensionPx ?? 0.0;
      if (rect.right <= -leftExtension ||
          rect.left >= viewportWidth ||
          rect.bottom <= 0 ||
          rect.top >= size.height) {
        continue;
      }

      final clipped = rect.intersect(
        Rect.fromLTWH(0, 0, viewportWidth, size.height),
      );
      if (clipped.width <= 0 || clipped.height <= 0) continue;
      final rrect = RRect.fromRectAndRadius(clipped, const Radius.circular(6));
      final baseColor = _automationColorForTarget(
        visual.targetId,
        isOrphan: visual.isOrphan,
      );
      final fillColor = visual.clip.muted
          ? const Color(0x665E5E5E)
          : (visual.isSelected
                ? baseColor.withOpacity(0.92)
                : baseColor.withOpacity(0.72));
      final borderColor = visual.isSelected
          ? Colors.white.withOpacity(0.9)
          : Colors.white.withOpacity(0.34);
      final fillPaint = Paint()..color = fillColor;
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = visual.isSelected ? 1.2 : 1.0
        ..color = borderColor;
      canvas.drawRRect(rrect, fillPaint);

      final previewRect = rect.deflate(2.0);
      if (previewRect.width > 2.0 && previewRect.height > 2.0) {
        canvas.save();
        canvas.clipRRect(rrect);
        _drawAutomationClipPointPreview(canvas, previewRect, visual.clip);
        canvas.restore();
      }

      canvas.drawRRect(rrect, borderPaint);

      if (!stretchToolActive &&
          visual.isSelected &&
          clipped.width > 20 &&
          clipped.height > 8) {
        _drawTrimHandles(
          canvas,
          rrect,
          asStretchHandles: false,
          stretchEnabled: false,
          preservePitch: false,
        );

        final handleWidth = math.min(
          22.0,
          math.max(14.0, clipped.width * 0.22),
        );
        final handleHeight = math.min(
          20.0,
          math.max(14.0, clipped.height - 8.0),
        );
        final handleRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            clipped.left + 4.0,
            clipped.top + ((clipped.height - handleHeight) / 2.0),
            handleWidth,
            handleHeight,
          ),
          const Radius.circular(7),
        );
        final handleFill = Paint()
          ..color = Colors.black.withValues(alpha: 0.22);
        final handleStroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.white.withValues(alpha: 0.18);
        final dotPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.white.withValues(alpha: 0.7);
        canvas.drawRRect(handleRect, handleFill);
        canvas.drawRRect(handleRect, handleStroke);

        final centerX = handleRect.left + (handleRect.width / 2.0);
        final centerY = handleRect.top + (handleRect.height / 2.0);
        for (final dx in const [-3.0, 3.0]) {
          for (final dy in const [-4.0, 0.0, 4.0]) {
            canvas.drawCircle(
              Offset(centerX + dx, centerY + dy),
              1.0,
              dotPaint,
            );
          }
        }
      }

      if (clipped.width < 28 || clipped.height < 13) continue;
      final label = visual.targetLabel;
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          color: visual.clip.muted
              ? Colors.white60
              : Colors.white.withOpacity(0.94),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      );
      final labelLeftInset = visual.isSelected
          ? math.min(30.0, math.max(20.0, clipped.width * 0.28))
          : 4.0;
      textPainter.layout(
        maxWidth: math.max(0.0, clipped.width - (labelLeftInset + 4.0)),
      );
      if (textPainter.width <= 0.0) continue;
      final textY = (clipped.top + (clipped.height - textPainter.height) / 2.0)
          .toDouble();
      textPainter.paint(canvas, Offset(clipped.left + labelLeftInset, textY));
    }
  }

  void _drawWaveform(
    Canvas canvas,
    List<double> peaks,
    RRect rect,
    double trimStartMs,
    double trimEndMs,
    double fullDurationMs,
    double stretchScale, {
    required double gainScale,
    required bool isReversed,
    Color? color,
  }) {
    if (peaks.isEmpty || rect.width <= 0 || rect.height <= 0) return;
    final safeGainScale = gainScale.clamp(0.0, 64.0).toDouble();
    final safeFullDurationMs = fullDurationMs.clamp(1.0, double.infinity);
    final safeStretchScale = stretchScale.clamp(0.0001, double.infinity);
    final sourceMsPerPixel = 1.0 / (pixelsPerMs * safeStretchScale);
    if (!sourceMsPerPixel.isFinite || sourceMsPerPixel <= 0) return;

    final dpr =
        PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
    double snapToDevicePixel(double x) => (x * dpr).roundToDouble() / dpr;

    final leftExtension = leftVisibleExtensionPx ?? 0.0;
    final visibleLeft = rect.left
        .clamp(-leftExtension, viewportWidth)
        .toDouble();
    final visibleRight = rect.right
        .clamp(-leftExtension, viewportWidth)
        .toDouble();
    if (visibleRight <= visibleLeft) return;

    final waveformPaint = Paint()
      ..color = color ?? const Color(0xFFF4F7FA).withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0 / dpr, 0.5)
      ..isAntiAlias = false;
    final centerY = rect.top + rect.height / 2;
    final maxAmplitude = rect.height / 2 - 1.5;
    if (maxAmplitude <= 0) return;

    final lastPeakIndex = peaks.length - 1;
    final sourceToPeak = lastPeakIndex / safeFullDurationMs;
    // `peaks` already reflects clip reversal through `displayWaveformData`.
    // For reversed clips, the visible trimmed window therefore starts at the
    // mirrored source offset rather than the forward trim start.
    final visibleSourceStartMs = isReversed
        ? (safeFullDurationMs - trimEndMs).clamp(0.0, safeFullDurationMs)
        : trimStartMs.clamp(0.0, safeFullDurationMs);
    final path = Path();

    // Anchor bucketing to clip-local pixel columns to avoid temporal shimmer
    // when the clip scrolls by fractional pixels at zoomed-out scales.
    final startCol = math.max(0, (visibleLeft - rect.left).floor());
    final endCol = math.max(startCol + 1, (visibleRight - rect.left).ceil());
    final maxCol = rect.width.ceil();

    for (int col = startCol; col < endCol && col <= maxCol; col++) {
      final x0 = snapToDevicePixel(rect.left + col);

      final startSourceMs =
          visibleSourceStartMs + col.toDouble() * sourceMsPerPixel;
      final endSourceMs = visibleSourceStartMs + (col + 1.0) * sourceMsPerPixel;

      final clampedStartMs = startSourceMs
          .clamp(0.0, safeFullDurationMs)
          .toDouble();
      final clampedEndMs = endSourceMs
          .clamp(clampedStartMs, safeFullDurationMs)
          .toDouble();

      int i0 = (clampedStartMs * sourceToPeak).floor().clamp(0, lastPeakIndex);
      int i1 = (clampedEndMs * sourceToPeak).ceil().clamp(i0 + 1, peaks.length);
      if (i1 <= i0) {
        i1 = math.min(peaks.length, i0 + 1);
      }

      double maxAmp = 0.0;
      for (int i = i0; i < i1; i++) {
        final amp = peaks[i].abs() * safeGainScale;
        if (amp > maxAmp) {
          maxAmp = amp;
        }
      }
      if (maxAmp <= 0.0001) continue;

      final barHeight = maxAmp.clamp(0.0, 1.0) * maxAmplitude;
      final topY = snapToDevicePixel(centerY - barHeight);
      final bottomY = snapToDevicePixel(centerY + barHeight);
      path.moveTo(x0, topY);
      path.lineTo(x0, bottomY);
    }

    canvas.drawPath(path, waveformPaint);
  }

  void _drawMidiPreview(
    Canvas canvas,
    RRect rect,
    List<MidiNote> notes,
    double trimStartMs,
    double trimEndMs, {
    required double sourceBpm,
  }) {
    final beatMs = (60000.0 / sourceBpm.clamp(1.0, 1000000.0)).clamp(
      1.0,
      1000000.0,
    );
    final previewPaint = Paint()
      ..color = const Color(0xFFB8E8B9).withValues(alpha: 0.78)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1.0;

    final height = rect.height;
    final width = rect.width;
    final rangeStartMs = trimStartMs;
    final rangeEndMs = trimEndMs;
    final visibleMs = (rangeEndMs - rangeStartMs).clamp(1.0, double.infinity);

    for (int i = 0; i <= 4; i++) {
      final y = rect.top + (i / 4.0) * height;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), linePaint);
    }

    if (notes.isEmpty) return;

    const int minPitch = 36;
    const int maxPitch = 84;
    const double minNoteWidth = 2.5;

    for (final note in notes) {
      final startMs = note.startBeat * beatMs;
      final endMs = (note.startBeat + note.lengthBeats) * beatMs;
      if (endMs <= rangeStartMs || startMs >= rangeEndMs) continue;

      final clampedStart = math.max(startMs, rangeStartMs);
      final clampedEnd = math.min(endMs, rangeEndMs);
      final noteStartNorm = (clampedStart - rangeStartMs) / visibleMs;
      final noteEndNorm = (clampedEnd - rangeStartMs) / visibleMs;

      final x = rect.left + noteStartNorm * width;
      final w = math.max(minNoteWidth, (noteEndNorm - noteStartNorm) * width);
      final pitchNorm =
          ((note.pitch.clamp(minPitch, maxPitch) - minPitch) /
                  (maxPitch - minPitch))
              .toDouble();
      final y = rect.bottom - (pitchNorm * height) - 4.0;

      final alpha = (140 + (note.velocity.clamp(0.0, 1.0) * 90)).round();
      previewPaint.color = Color.fromARGB(alpha, 168, 228, 178);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y.clamp(rect.top + 2.0, rect.bottom - 8.0), w, 5.0),
          const Radius.circular(2),
        ),
        previewPaint,
      );
    }
  }

  void _drawClipLabel(Canvas canvas, RRect rect, AudioTrack clip) {
    const double labelHeight = 18.0;
    const double horizontalPadding = 6.0;

    String labelName = clip.label;
    if (labelName.isEmpty) {
      labelName = clip.isMidi
          ? (clip.instrumentName.isNotEmpty ? clip.instrumentName : "MIDI Clip")
          : "Audio Clip";
    }
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…",
    );

    tp.text = TextSpan(
      text: labelName,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
    );

    // tp.layout(
    //   maxWidth: rect.width - horizontalPadding * 2, //rect.width * 0.6 - horizontalPadding * 2,
    // );

    // Keep the sticky-left behavior so the name stays readable when the clip's
    // true left edge has scrolled past the viewport.
    final double labelLeft = math.max(0.0, rect.left);
    final double availableWidth = rect.right - labelLeft;
    if (availableWidth <= horizontalPadding * 2) return;

    final usableWidth = math.max(0.0, availableWidth - horizontalPadding * 2);

    // If there is no room to render even an ellipsis glyph, hide the label
    // region entirely so only the clip body/waveform remains visible.
    final minTextPainter = TextPainter(
      text: const TextSpan(
        text: '…',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (usableWidth < minTextPainter.width) return;

    tp.layout(maxWidth: usableWidth);

    final textWidth = tp.width;

    // Background should fit exactly the rendered text while staying within the
    // clip's right edge.
    double labelWidth = textWidth + horizontalPadding * 2;

    // If resulting width is too narrow to show text, hide label.
    if (textWidth <= 0.0) return;
    if (labelWidth > availableWidth) labelWidth = availableWidth;
    if (labelWidth <= horizontalPadding * 2) return;

    // Label background
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelLeft, //rect.left,
        rect.top,
        labelWidth, // Clip label area as wide as text
        labelHeight,
      ),
      const Radius.circular(
        4,
      ), //TODO: think about making this not circular and have squared corner
    );

    final bgPaint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.26);

    canvas.save();
    canvas.clipRRect(rect);
    canvas.drawRRect(bgRect, bgPaint);
    // Draw text centered vertically within the label area
    tp.paint(
      canvas,
      Offset(
        labelLeft + horizontalPadding,
        rect.top + (labelHeight - tp.height) / 2,
      ),
    );
    canvas.restore();
  }

  void _drawTrimHandles(
    Canvas canvas,
    RRect rect, {
    required bool asStretchHandles,
    required bool stretchEnabled,
    required bool preservePitch,
  }) {
    const handleWidth = _AudioCanvasTimelineState.kTrimHandleWidth;
    const handleGap = _AudioCanvasTimelineState.kTrimHandleGap;
    const verticalInset = _AudioCanvasTimelineState.kTrimHandleVerticalInset;
    final handleColor = !asStretchHandles
        ? const Color(0xFF397FBE)
        : (!stretchEnabled
              ? const Color(0xFF65707C)
              : (preservePitch
                    ? const Color(0xFF2AAE9F)
                    : const Color(0xFFD38A3D)));
    final handlePaint = Paint()
      ..color = handleColor
      ..style = PaintingStyle.fill;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final handleHeight = math.max(1.0, rect.height - (verticalInset * 2.0));
    final leftRect = Rect.fromLTWH(
      rect.left - handleGap - handleWidth,
      rect.top + verticalInset,
      handleWidth,
      handleHeight,
    );
    final rightRect = Rect.fromLTWH(
      rect.right + handleGap,
      rect.top + verticalInset,
      handleWidth,
      handleHeight,
    );
    final leftRRect = RRect.fromRectAndRadius(
      leftRect,
      const Radius.circular(6),
    );
    final rightRRect = RRect.fromRectAndRadius(
      rightRect,
      const Radius.circular(6),
    );
    // Left trim handle
    canvas.drawRRect(leftRRect.shift(const Offset(0, 1)), shadowPaint);
    canvas.drawRRect(leftRRect, handlePaint);
    // Right trim handle
    canvas.drawRRect(rightRRect.shift(const Offset(0, 1)), shadowPaint);
    canvas.drawRRect(rightRRect, handlePaint);
    // Draw handle grips
    final gripPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.62)
      ..strokeWidth = 1.5;
    for (int i = 0; i < 3; i++) {
      final y = rect.top + rect.height / 2 + (i - 1) * 6;
      // Left grip
      canvas.drawLine(
        Offset(leftRect.left + 4, y),
        Offset(leftRect.right - 4, y),
        gripPaint,
      );
      // Right grip
      canvas.drawLine(
        Offset(rightRect.left + 4, y),
        Offset(rightRect.right - 4, y),
        gripPaint,
      );
    }
  }

  void _drawPlayhead(Canvas canvas, Size size) {
    // === FIX ===: Use playheadPx
    final x = playheadPx;
    final glowPaint = Paint()
      ..color = const Color.fromRGBO(240, 169, 87, 0.22)
      ..strokeWidth = 4;
    final paint = Paint()
      ..color = const Color(0xFFF0A957)
      ..strokeWidth = 1.5;
    final blockedRanges = <Offset>[];
    double rowTop = masterAutomationLaneHeight;
    for (int row = 0; row < rowExpanded.length; row++) {
      if (_isRowHiddenByCollapsedGroup(row)) continue;
      final automationLaneHeight = _automationLaneHeightForRow(row);
      final expandedHeight = row < expandedHeights.length
          ? expandedHeights[row]
          : 0.0;
      final expandedIsEffects =
          row < expandedTab.length && expandedTab[row] == 1;
      if (rowExpanded[row] && expandedIsEffects && expandedHeight > 0.0) {
        final blockTop = rowTop + rowHeight + automationLaneHeight;
        final blockBottom = blockTop + expandedHeight;
        blockedRanges.add(Offset(blockTop, blockBottom));
      }
      rowTop += rowHeight + automationLaneHeight + expandedHeight;
    }

    void drawSegment(double top, double bottom) {
      if (bottom <= top) return;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), glowPaint);
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }

    final startY = -rulerHeight;
    final endY = size.height;
    if (blockedRanges.isEmpty) {
      drawSegment(startY, endY);
      return;
    }

    blockedRanges.sort((a, b) => a.dx.compareTo(b.dx));
    double cursor = startY;
    for (final range in blockedRanges) {
      final blockTop = range.dx.clamp(startY, endY).toDouble();
      final blockBottom = range.dy.clamp(startY, endY).toDouble();
      if (blockBottom <= blockTop) continue;
      if (blockTop > cursor) {
        drawSegment(cursor, blockTop);
      }
      if (blockBottom > cursor) {
        cursor = blockBottom;
      }
      if (cursor >= endY) break;
    }
    if (cursor < endY) {
      drawSegment(cursor, endY);
    }
  }

  void _drawCutPreviewLine(Canvas canvas) {
    if (cutPreviewClipIndex == null || cutPreviewMs == null) return;
    final clipIndex = cutPreviewClipIndex!;
    if (clipIndex < 0 || clipIndex >= clips.length) return;
    final clip = clips[clipIndex];
    final row = clip.rowIndex;
    if (row < 0 || row >= rowExpanded.length) return;
    if (_isRowHiddenByCollapsedGroup(row)) return;

    final clipStartMs = getStartMs(clip);
    final clipEndMs = clipStartMs + getTimelineDurationMs(clip);
    if (clipEndMs <= clipStartMs) return;

    final clampedCutMs = cutPreviewMs!.clamp(clipStartMs, clipEndMs).toDouble();
    final x = (clampedCutMs - scrollOffsetMs) * pixelsPerMs;
    if (x < 0 || x > viewportWidth) return;

    final yOffset = _rowTopForIndex(row);

    final top = yOffset + 3;
    final bottom = yOffset + rowHeight - 3;
    if (bottom <= top) return;

    final glowPaint = Paint()
      ..color = const Color(0xCC9DBBFF)
      ..strokeWidth = 4;
    final linePaint = Paint()
      ..color = const Color(0xFFF2F6FF)
      ..strokeWidth = 1.5;

    canvas.drawLine(Offset(x, top), Offset(x, bottom), glowPaint);
    canvas.drawLine(Offset(x, top), Offset(x, bottom), linePaint);
  }

  void _paintRecordingPreview(
    Canvas canvas,
    Rect rowRect,
    double msToPx,
    double recStartMs,
    double recDurationMs,
    List<double> peaks,
    List<double> peakTimesMs,
  ) {
    final envelope = buildRecordingPreviewEnvelopePoints(
      peaks: peaks,
      peakTimesMs: peakTimesMs,
      durationMs: recDurationMs,
    );
    if (envelope.isEmpty) return;

    final double left = recStartMs * msToPx;

    final paint = Paint()
      ..color = const Color(0xCCFF4A4A)
      ..style = PaintingStyle.fill;

    final double centerY = rowRect.center.dy;
    final double maxHeight = rowRect.height * 0.7;

    final Path path = Path();
    // TOP EDGE
    for (int i = 0; i < envelope.length; i++) {
      final point = envelope[i];
      final double x = left + point.dx * msToPx;
      final double y = centerY - point.dy * maxHeight * 0.5;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // BOTTOM EDGE (reverse)
    for (int i = envelope.length - 1; i >= 0; i--) {
      final point = envelope[i];
      final double x = left + point.dx * msToPx;
      final double y = centerY + point.dy * maxHeight * 0.5;
      path.lineTo(x, y);
    }

    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) {
    final loopPreviewVisible =
        clipLoopPreviewClipIndex != null ||
        old.clipLoopPreviewClipIndex != null;
    final loopPreviewChanged =
        clipLoopPreviewClipIndex != old.clipLoopPreviewClipIndex ||
        clipLoopPreviewStartMs != old.clipLoopPreviewStartMs ||
        clipLoopPreviewFallbackMs != old.clipLoopPreviewFallbackMs ||
        (loopPreviewVisible && transportMs != old.transportMs);

    // Only repaint when timeline-visible state actually changes.
    return playheadPx != old.playheadPx || // playheadMs is not a prop
        loopPreviewChanged ||
        bpm != old.bpm ||
        beatsPerBar != old.beatsPerBar ||
        beatUnit != old.beatUnit ||
        scrollOffsetMs != old.scrollOffsetMs ||
        pixelsPerMs != old.pixelsPerMs ||
        viewportWidth != old.viewportWidth ||
        rulerHeight != old.rulerHeight ||
        masterAutomationLaneHeight != old.masterAutomationLaneHeight ||
        clipOverlapMode != old.clipOverlapMode ||
        (leftVisibleExtensionPx ?? 0.0) !=
            (old.leftVisibleExtensionPx ?? 0.0) ||
        _rowsHiddenByCollapsedGroupsHash !=
            old._rowsHiddenByCollapsedGroupsHash ||
        selectedClipIndex != old.selectedClipIndex ||
        _selectedClipIndicesHash != old._selectedClipIndicesHash ||
        _clipVisualStackOrderHash != old._clipVisualStackOrderHash ||
        draggedClipIndex != old.draggedClipIndex ||
        draggedClipStartMs != old.draggedClipStartMs ||
        draggedClipRowIndex != old.draggedClipRowIndex ||
        _rowKindHash != old._rowKindHash ||
        _rowExpandedHash != old._rowExpandedHash ||
        _expandedTabHash != old._expandedTabHash ||
        _effectsPanelHeightsHash != old._effectsPanelHeightsHash ||
        _expandedHeightsHash != old._expandedHeightsHash ||
        _automationLaneHeightsHash != old._automationLaneHeightsHash ||
        _rowVisualHash != old._rowVisualHash ||
        stretchToolActive != old.stretchToolActive ||
        trimClipIndex != old.trimClipIndex ||
        _clipDataHash < 0 ||
        old._clipDataHash < 0 ||
        _clipDataHash != old._clipDataHash ||
        !listEquals(visibleClipIndices, old.visibleClipIndices) ||
        _automationClipHash != old._automationClipHash ||
        quantizeDivisions != old.quantizeDivisions ||
        foregroundGridEnabled != old.foregroundGridEnabled ||
        highlightedSegmentRow != old.highlightedSegmentRow ||
        highlightedSegmentStartMs != old.highlightedSegmentStartMs ||
        highlightedSegmentEndMs != old.highlightedSegmentEndMs ||
        sampleDropPreviewRow != old.sampleDropPreviewRow ||
        sampleDropPreviewStartMs != old.sampleDropPreviewStartMs ||
        sampleDropPreviewEndMs != old.sampleDropPreviewEndMs ||
        sampleDropPreviewAllowed != old.sampleDropPreviewAllowed ||
        cutPreviewClipIndex != old.cutPreviewClipIndex ||
        cutPreviewMs != old.cutPreviewMs ||
        isRecording != old.isRecording ||
        recordingRowIndex != old.recordingRowIndex ||
        recordingStartMs != old.recordingStartMs ||
        _recordingPeaksHash != old._recordingPeaksHash ||
        _recordingPeakTimesHash != old._recordingPeakTimesHash;
  }
}

// === Custom painter for the ruler ===
class _RulerPainter extends CustomPainter {
  final double pixelsPerMs;
  final double scrollOffsetMs;
  final double viewportWidth;
  final double bpm;
  final int beatsPerBar;
  final int beatUnit;
  final int quantizeDivisions;
  final double contentYOffset;
  _RulerPainter({
    required this.pixelsPerMs,
    required this.scrollOffsetMs,
    required this.viewportWidth,
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.quantizeDivisions,
    required this.contentYOffset,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    final safeBeatsPerBar = math.max(1, beatsPerBar);
    final safeBeatUnit = math.max(1, beatUnit);
    final msPerBar = (60000 / bpm) * safeBeatsPerBar * 4.0 / safeBeatUnit;
    final msPerBeat = msPerBar / safeBeatsPerBar;
    final pxPerBar = msPerBar * pixelsPerMs;
    final zoomVisibility = ((pxPerBar - 3.0) / 18.0).clamp(0.0, 1.0);
    // Keep ruler ticks readable, but dim a bit more at low zoom.
    final tickOpacityScale = 0.65 + (0.35 * zoomVisibility);

    final majorTickPaint = Paint()
      ..color = Colors.white.withOpacity(0.7 * tickOpacityScale)
      ..strokeWidth = 1.5;
    final minorTickPaint = Paint()
      ..color = Colors.white.withOpacity(0.3 * tickOpacityScale)
      ..strokeWidth = 1;

    // Calculate beat duration
    final subdivisions = math.max(1, quantizeDivisions);
    final msPerSubdivision = msPerBar / subdivisions;
    // Draw bar markers
    final visibleStartMs = scrollOffsetMs;
    final visibleEndMs = scrollOffsetMs + viewportWidth / pixelsPerMs;
    final rawStartBar = (visibleStartMs / msPerBar).floor();
    final rawEndBar = (visibleEndMs / msPerBar).ceil();
    final startBar = math.max(0, math.min(rawStartBar, rawEndBar));
    final endBar = math.max(0, math.max(rawStartBar, rawEndBar));
    const minLabelSpacingPx = 24.0;
    var barLabelStride = 1;
    while (barLabelStride * pxPerBar < minLabelSpacingPx &&
        barLabelStride < 512) {
      barLabelStride *= 2;
    }

    for (int bar = startBar; bar <= endBar; bar++) {
      final barMs = bar * msPerBar;
      // === FIX ===: Removed offset
      final x = (barMs - scrollOffsetMs) * pixelsPerMs;
      if (x >= 0 && x <= viewportWidth) {
        // Draw major tick
        canvas.drawLine(
          Offset(x, size.height - 15),
          Offset(x, size.height),
          majorTickPaint,
        );
        // Draw bar number ONLY if stride matches
        if (bar % barLabelStride == 0) {
          textPainter.text = TextSpan(
            text: '${bar + 1}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          );
          textPainter.layout();
          textPainter.paint(
            canvas,
            Offset(x - textPainter.width / 2, 5 + contentYOffset),
          );
        }
      }
      // Draw quantize subdivisions within the bar.
      for (int sub = 1; sub < subdivisions; sub++) {
        final subMs = barMs + sub * msPerSubdivision;
        final subX = (subMs - scrollOffsetMs) * pixelsPerMs;
        if (subX >= 0 && subX <= viewportWidth) {
          canvas.drawLine(
            Offset(subX, size.height - 8),
            Offset(subX, size.height),
            minorTickPaint,
          );
        }
      }
      for (int beat = 1; beat < safeBeatsPerBar; beat++) {
        final beatMs = barMs + (beat * msPerBeat);
        final beatX = (beatMs - scrollOffsetMs) * pixelsPerMs;
        if (beatX >= 0 && beatX <= viewportWidth) {
          canvas.drawLine(
            Offset(beatX, size.height - 10),
            Offset(beatX, size.height),
            majorTickPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) {
    return scrollOffsetMs != oldDelegate.scrollOffsetMs ||
        pixelsPerMs != oldDelegate.pixelsPerMs ||
        bpm != oldDelegate.bpm ||
        beatsPerBar != oldDelegate.beatsPerBar ||
        beatUnit != oldDelegate.beatUnit ||
        quantizeDivisions != oldDelegate.quantizeDivisions ||
        contentYOffset != oldDelegate.contentYOffset;
  }
}

/* ===================================================================
   AUTOMATION LANE (PER ROW) - uses AutomationPoint.x as timeMs
   =================================================================== */

class _AutomationPointValueInputDialog extends StatefulWidget {
  const _AutomationPointValueInputDialog({
    required this.formatter,
    required this.initialText,
    required this.targetLabel,
  });

  final _AutomationValueFormatter formatter;
  final String initialText;
  final String targetLabel;

  @override
  State<_AutomationPointValueInputDialog> createState() =>
      _AutomationPointValueInputDialogState();
}

class _AutomationPointValueInputDialogState
    extends State<_AutomationPointValueInputDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _errorText;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closing || !_focusNode.canRequestFocus) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _close(double? result) {
    if (_closing) return;
    _closing = true;
    _focusNode.unfocus();
    Navigator.of(context).pop(result);
  }

  void _submit() {
    final parsed = widget.formatter.parseInputToNormalized(_controller.text);
    if (parsed == null) {
      setState(() {
        _errorText =
            '${L10n.translate(context, 'Enter a valid')} ${widget.formatter.inputLabel.toLowerCase()}';
      });
      return;
    }
    _close(parsed);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MixroomShellDialog(
      radius: 24,
      color: const Color.fromRGBO(26, 38, 56, 0.92),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.translate(context, 'Type Automation Value'),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: Color(0xFFF4F4F4),
              fontSize: 17,
              height: 22 / 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.targetLabel,
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 13,
              height: 18 / 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          MixroomShellSurface(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            color: const Color.fromRGBO(244, 244, 244, 0.10),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: false,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                color: Color(0xFFF4F4F4),
                fontSize: 15,
                height: 22 / 15,
              ),
              decoration: InputDecoration(
                hintText: widget.formatter.inputHint,
                hintStyle: TextStyle(
                  fontFamily: 'Pretendard',
                  color: Colors.white.withValues(alpha: 0.48),
                  fontSize: 15,
                  height: 22 / 15,
                ),
                errorText: _errorText,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                width: 112,
                child: MixroomShellDialogButton(
                  label: L10n.translate(context, 'Cancel'),
                  onPressed: () => _close(null),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 112,
                child: MixroomShellDialogButton(
                  label: L10n.translate(context, 'Set Value'),
                  accent: true,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AutomationLane extends StatefulWidget {
  final int rowIndex;
  final List<AutomationPoint> points; // x = timeMs, volume = 0..1
  final double pixelsPerMs;
  final double scrollOffsetMs;
  final double laneHeight;
  final double timelineDurationMs; // kept for future use, but not needed for x
  final String targetLabel;
  final String targetParamId;
  final String targetUnit;
  final double targetMin;
  final double targetMax;
  final double? targetDefaultNormalized;
  final Map<double, String> targetDisplayLabels;
  final bool isVolumeLane;
  final double? highlightStartMs;
  final double? highlightEndMs;
  final ValueChanged<List<AutomationPoint>> onChanged;
  final void Function(Offset pos) onPanStartExternal;
  final void Function(Offset pos) onPanUpdateExternal;
  final VoidCallback onPanEndExternal;
  final VoidCallback onPanCancelExternal;
  final VoidCallback onBackgroundPanStartExternal;
  final ValueChanged<double> onBackgroundPanUpdateExternal;
  final VoidCallback onBackgroundPanEndExternal;

  const _AutomationLane({
    Key? key,
    required this.rowIndex,
    required this.points,
    required this.pixelsPerMs,
    required this.scrollOffsetMs,
    required this.laneHeight,
    required this.timelineDurationMs,
    required this.targetLabel,
    required this.targetParamId,
    required this.targetUnit,
    required this.targetMin,
    required this.targetMax,
    required this.targetDefaultNormalized,
    required this.targetDisplayLabels,
    required this.isVolumeLane,
    this.highlightStartMs,
    this.highlightEndMs,
    required this.onChanged,
    required this.onPanStartExternal,
    required this.onPanUpdateExternal,
    required this.onPanEndExternal,
    required this.onPanCancelExternal,
    required this.onBackgroundPanStartExternal,
    required this.onBackgroundPanUpdateExternal,
    required this.onBackgroundPanEndExternal,
  }) : super(key: key);

  @override
  State<_AutomationLane> createState() => _AutomationLaneState();
}

class _AutomationPointPanGestureRecognizer extends PanGestureRecognizer {
  _AutomationPointPanGestureRecognizer({
    required this.shouldAcceptGlobalPosition,
  });

  final bool Function(Offset globalPosition) shouldAcceptGlobalPosition;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!shouldAcceptGlobalPosition(event.position)) {
      resolvePointer(event.pointer, GestureDisposition.rejected);
      return;
    }
    super.addAllowedPointer(event);
  }
}

class _AutomationLaneBackgroundHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  _AutomationLaneBackgroundHorizontalDragRecognizer({
    required this.shouldAcceptGlobalPosition,
  });

  final bool Function(Offset globalPosition) shouldAcceptGlobalPosition;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!shouldAcceptGlobalPosition(event.position)) {
      resolvePointer(event.pointer, GestureDisposition.rejected);
      return;
    }
    super.addAllowedPointer(event);
  }
}

class _AutomationLaneState extends State<_AutomationLane> {
  static const double hitRadius = 20.0;
  static const double verticalPadding = 12.0;
  static _AutomationPointClipboardEntry? _pointClipboard;

  double get _usableHeight => widget.laneHeight - verticalPadding * 2;
  _AutomationValueFormatter get _valueFormatter => _AutomationValueFormatter(
    targetLabel: widget.targetLabel,
    targetParamId: widget.targetParamId,
    targetUnit: widget.targetUnit,
    targetMin: widget.targetMin,
    targetMax: widget.targetMax,
    pluginDisplayLabels: widget.targetDisplayLabels,
    pluginDefaultNormalized: widget.targetDefaultNormalized,
    isVolumeLane: widget.isVolumeLane,
  );

  double _timeToPx(double timeMs) =>
      (timeMs - widget.scrollOffsetMs) * widget.pixelsPerMs;

  double _pxToTime(double px) =>
      (px / widget.pixelsPerMs) + widget.scrollOffsetMs;

  double _volumeToPy(double v) {
    final display = _valueFormatter.displayNormalizedForStoredNormalized(v);
    return verticalPadding + (1.0 - display) * _usableHeight;
  }

  double _pyToVolume(double py) {
    final display = 1.0 - ((py - verticalPadding) / _usableHeight);
    return _valueFormatter.storedNormalizedForDisplayNormalized(
      display.clamp(0.0, 1.0).toDouble(),
    );
  }

  // ---------- Hit test ----------

  int? _hitPoint(Offset pos) {
    for (int i = 0; i < widget.points.length; i++) {
      final p = widget.points[i];
      final px = _timeToPx(p.x); // x = timeMs
      final py = _volumeToPy(p.volume);

      if ((pos - Offset(px, py)).distance <= hitRadius) {
        return i;
      }
    }
    return null;
  }

  // ---------- Point actions ----------
  void _addPoint(Offset pos) {
    final t = _pxToTime(pos.dx); // absolute ms
    final v = _pyToVolume(pos.dy); // 0..1

    final newPoint = AutomationPoint(x: t, volume: v);

    final updated = List<AutomationPoint>.from(widget.points)..add(newPoint);
    updated.sort((a, b) => a.x.compareTo(b.x));

    widget.onChanged(updated);
  }

  void _deletePoint(int index) {
    if (index == 0) return;

    if (widget.points.length <= 1) return; // keep at least one
    final updated = List<AutomationPoint>.from(widget.points)..removeAt(index);
    widget.onChanged(updated);
  }

  void _setPointValue(int index, double normalized) {
    if (index < 0 || index >= widget.points.length) return;
    final updated = widget.points.map((p) => p.copy()).toList(growable: false);
    updated[index].volume = normalized.clamp(0.0, 1.0).toDouble();
    widget.onChanged(updated);
  }

  bool _canMatchPreviousPoint(int index) =>
      index > 0 && index < widget.points.length;

  void _setPointToPreviousValue(int index) {
    if (!_canMatchPreviousPoint(index)) return;
    _setPointValue(index, widget.points[index - 1].volume);
  }

  String _pointValueLabel(int index) {
    if (index < 0 || index >= widget.points.length) return '';
    return _valueFormatter.formatValueLabel(widget.points[index].volume);
  }

  bool _canPastePointValue() {
    final clipboard = _pointClipboard;
    if (clipboard == null) return false;
    return clipboard.isCompatibleWith(_valueFormatter);
  }

  String _pasteSubtitle() {
    final clipboard = _pointClipboard;
    if (clipboard == null) return 'No copied value';
    if (!_canPastePointValue()) {
      return 'Copied value is for another parameter type';
    }
    return 'Paste ${clipboard.formattedValue}';
  }

  void _copyPointValue(int index) {
    if (index < 0 || index >= widget.points.length) return;
    final formatter = _valueFormatter;
    final normalized = widget.points[index].volume;
    _pointClipboard = _AutomationPointClipboardEntry(
      kind: formatter.valueKind,
      rawValue: formatter.rawValueForNormalized(normalized),
      formattedValue: formatter.formatValueLabel(normalized),
      signature: formatter.signature,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${L10n.translate(context, 'Copied automation value')} ${_pointValueLabel(index)}',
        ),
      ),
    );
  }

  void _pastePointValue(int index) {
    final clipboard = _pointClipboard;
    if (clipboard == null) return;
    if (!clipboard.isCompatibleWith(_valueFormatter)) return;
    final normalized = _valueFormatter.normalizedForRawValue(
      clipboard.rawValue,
    );
    _setPointValue(index, normalized);
  }

  Future<void> _typePointValue(int index) async {
    if (index < 0 || index >= widget.points.length) return;
    final formatter = _valueFormatter;
    final typedNormalized = await showDialog<double>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.26),
      builder: (_) => _AutomationPointValueInputDialog(
        formatter: formatter,
        initialText: formatter.editableValueText(widget.points[index].volume),
        targetLabel: widget.targetLabel,
      ),
    );
    if (!mounted || typedNormalized == null) return;
    _setPointValue(index, typedNormalized);
  }

  Future<void> _showPointMenu(int index) async {
    if (index < 0 || index >= widget.points.length) return;
    final currentValue = _pointValueLabel(index);
    final canMatchPrevious = _canMatchPreviousPoint(index);
    final canPaste = _canPastePointValue();
    final previousValue = canMatchPrevious
        ? _pointValueLabel(index - 1)
        : L10n.translate(context, 'No left point');
    final canDelete =
        index > 0 && widget.points.length > 1 && index < widget.points.length;
    await AppHaptics.impact(AppHapticImpact.medium);
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1B2233),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                widget.targetLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                L10n.translate(sheetContext, 'Automation point'),
                style: TextStyle(color: Colors.white.withOpacity(0.62)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_outlined),
              title: Text(L10n.translate(sheetContext, 'Copy value')),
              subtitle: Text(currentValue),
              onTap: () => Navigator.pop(sheetContext, 'copy'),
            ),
            ListTile(
              enabled: canPaste,
              leading: const Icon(Icons.content_paste_outlined),
              title: Text(L10n.translate(sheetContext, 'Paste value')),
              subtitle: Text(_pasteSubtitle()),
              onTap: canPaste
                  ? () => Navigator.pop(sheetContext, 'paste')
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: Text(L10n.translate(sheetContext, 'Type value')),
              subtitle: Text(currentValue),
              onTap: () => Navigator.pop(sheetContext, 'type'),
            ),
            ListTile(
              enabled: canMatchPrevious,
              leading: const Icon(Icons.keyboard_double_arrow_left_rounded),
              title: Text(
                L10n.translate(sheetContext, 'Set to Value of Previous Point'),
              ),
              subtitle: Text(
                canMatchPrevious
                    ? '${L10n.translate(sheetContext, 'Match')} $previousValue'
                    : previousValue,
              ),
              onTap: canMatchPrevious
                  ? () => Navigator.pop(sheetContext, 'match_previous')
                  : null,
            ),
            ListTile(
              enabled: canDelete,
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(L10n.translate(sheetContext, 'Delete point')),
              onTap: canDelete
                  ? () => Navigator.pop(sheetContext, 'delete')
                  : null,
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'copy':
        _copyPointValue(index);
        break;
      case 'paste':
        _pastePointValue(index);
        break;
      case 'type':
        await _typePointValue(index);
        break;
      case 'match_previous':
        _setPointToPreviousValue(index);
        break;
      case 'delete':
        _deletePoint(index);
        break;
    }
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _AutomationPointPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _AutomationPointPanGestureRecognizer
            >(
              // 1) Constructor
              () => _AutomationPointPanGestureRecognizer(
                shouldAcceptGlobalPosition: (globalPosition) {
                  final renderObject = context.findRenderObject();
                  if (renderObject is! RenderBox) return false;
                  final localPosition = renderObject.globalToLocal(
                    globalPosition,
                  );
                  return _hitPoint(localPosition) != null;
                },
              )..dragStartBehavior = DragStartBehavior.down,
              // 2) Initializer
              (_AutomationPointPanGestureRecognizer instance) {
                instance.onDown = (details) {
                  widget.onPanStartExternal(details.localPosition);
                };

                // Normal drag updates: always pass current pointer position.
                instance.onUpdate = (details) {
                  widget.onPanUpdateExternal(details.localPosition);
                };

                // End of drag.
                instance.onEnd = (details) {
                  widget.onPanEndExternal();
                };

                // covers the case of a double-tap (calls onDown but never onEnd)
                instance.onCancel = () {
                  widget.onPanEndExternal();
                };
              },
            ),
        _AutomationLaneBackgroundHorizontalDragRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _AutomationLaneBackgroundHorizontalDragRecognizer
            >(
              () => _AutomationLaneBackgroundHorizontalDragRecognizer(
                shouldAcceptGlobalPosition: (globalPosition) {
                  final renderObject = context.findRenderObject();
                  if (renderObject is! RenderBox) return false;
                  final localPosition = renderObject.globalToLocal(
                    globalPosition,
                  );
                  return _hitPoint(localPosition) == null;
                },
              )..dragStartBehavior = DragStartBehavior.down,
              (_AutomationLaneBackgroundHorizontalDragRecognizer instance) {
                instance.onStart = (_) {
                  widget.onBackgroundPanStartExternal();
                };
                instance.onUpdate = (details) {
                  final deltaDx = details.primaryDelta ?? details.delta.dx;
                  if (deltaDx == 0.0) return;
                  widget.onBackgroundPanUpdateExternal(deltaDx);
                };
                instance.onEnd = (_) {
                  widget.onBackgroundPanEndExternal();
                };
                instance.onCancel = () {
                  widget.onBackgroundPanEndExternal();
                };
              },
            ),
      },
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (d) async {
          final hit = _hitPoint(d.localPosition);
          if (hit != null) {
            widget.onPanCancelExternal();
            await _showPointMenu(hit);
            return;
          }
          _addPoint(d.localPosition);
        },
        onSecondaryTapDown: PlatformCapabilities.current.isDesktop
            ? (d) async {
                final hit = _hitPoint(d.localPosition);
                if (hit == null) return;
                widget.onPanCancelExternal();
                await _showPointMenu(hit);
              }
            : null,
        onDoubleTapDown: (d) {
          final hit = _hitPoint(d.localPosition);
          if (hit != null) {
            _deletePoint(hit);
            // widget.onPanEndExternal();
          }
        },
        child: CustomPaint(
          painter: _AutomationPainter(
            points: widget.points,
            scrollOffsetMs: widget.scrollOffsetMs,
            pixelsPerMs: widget.pixelsPerMs,
            laneHeight: widget.laneHeight,
            verticalPadding: verticalPadding,
            targetLabel: widget.targetLabel,
            targetParamId: widget.targetParamId,
            targetUnit: widget.targetUnit,
            targetMin: widget.targetMin,
            targetMax: widget.targetMax,
            targetDefaultNormalized: widget.targetDefaultNormalized,
            targetDisplayLabels: widget.targetDisplayLabels,
            isVolumeLane: widget.isVolumeLane,
            highlightStartMs: widget.highlightStartMs,
            highlightEndMs: widget.highlightEndMs,
          ),
          size: Size(double.infinity, widget.laneHeight),
        ),
      ),
    );
  }
}

/* ===================================================================
   Painter
   =================================================================== */

class _AutomationPainter extends CustomPainter {
  final List<AutomationPoint> points; // x = timeMs, volume = 0..1
  final double scrollOffsetMs;
  final double pixelsPerMs;
  final double laneHeight;
  final double verticalPadding;
  final String targetLabel;
  final String targetParamId;
  final String targetUnit;
  final double targetMin;
  final double targetMax;
  final double? targetDefaultNormalized;
  final Map<double, String> targetDisplayLabels;
  final bool isVolumeLane;
  final double? highlightStartMs;
  final double? highlightEndMs;

  _AutomationPainter({
    required this.points,
    required this.scrollOffsetMs,
    required this.pixelsPerMs,
    required this.laneHeight,
    required this.verticalPadding,
    required this.targetLabel,
    required this.targetParamId,
    required this.targetUnit,
    required this.targetMin,
    required this.targetMax,
    required this.targetDefaultNormalized,
    required this.targetDisplayLabels,
    required this.isVolumeLane,
    required this.highlightStartMs,
    required this.highlightEndMs,
  });

  double get _usableHeight => laneHeight - verticalPadding * 2;

  double _timeToPx(double timeMs) => (timeMs - scrollOffsetMs) * pixelsPerMs;

  double _volumeToPy(double v) => verticalPadding + (1.0 - v) * _usableHeight;

  _AutomationValueFormatter get _valueFormatter => _AutomationValueFormatter(
    targetLabel: targetLabel,
    targetParamId: targetParamId,
    targetUnit: targetUnit,
    targetMin: targetMin,
    targetMax: targetMax,
    pluginDisplayLabels: targetDisplayLabels,
    pluginDefaultNormalized: targetDefaultNormalized,
    isVolumeLane: isVolumeLane,
  );

  double _displayNormalizedForStoredNormalized(double normalized) {
    return _valueFormatter.displayNormalizedForStoredNormalized(normalized);
  }

  double get _midGuideNormalized {
    return _valueFormatter.midGuideStoredNormalized;
  }

  String _formatValueLabel(double normalized) {
    return _valueFormatter.formatValueLabel(normalized);
  }

  List<_AutomationAxisTick> _axisTicks() {
    return <_AutomationAxisTick>[
      _AutomationAxisTick(
        storedNormalized: 1.0,
        displayNormalized: _displayNormalizedForStoredNormalized(1.0),
        label: _formatValueLabel(1.0),
      ),
      _AutomationAxisTick(
        storedNormalized: _midGuideNormalized,
        displayNormalized: _displayNormalizedForStoredNormalized(
          _midGuideNormalized,
        ),
        label: _formatValueLabel(_midGuideNormalized),
      ),
      _AutomationAxisTick(
        storedNormalized: 0.0,
        displayNormalized: _displayNormalizedForStoredNormalized(0.0),
        label: _formatValueLabel(0.0),
      ),
    ];
  }

  void _paintAxisLabel(
    Canvas canvas,
    TextPainter tp,
    String text,
    double centerY,
  ) {
    tp.text = TextSpan(
      text: text,
      style: const TextStyle(color: Colors.white70, fontSize: 10),
    );
    tp.layout(maxWidth: 64);
    final maxDy = math.max(0.0, laneHeight - tp.height);
    final dy = (centerY - tp.height / 2).clamp(0.0, maxDy).toDouble();
    tp.paint(canvas, Offset(4, dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0.0 || laneHeight <= 0.0) return;
    const double axisWidth = 44;
    final hasHighlightWindow =
        highlightStartMs != null &&
        highlightEndMs != null &&
        highlightEndMs! > highlightStartMs!;

    // 1) Lane background
    final bg = Paint()..color = const Color.fromRGBO(111, 117, 123, 0.34);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(0)),
      bg,
    );

    // Horizontal guide lines
    final guidePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;

    final axisTicks = _axisTicks();
    for (final tick in axisTicks) {
      final y = _volumeToPy(tick.displayNormalized);
      canvas.drawLine(Offset(axisWidth, y), Offset(size.width, y), guidePaint);
    }

    // Y-axis labels on the very left
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final tick in axisTicks) {
      _paintAxisLabel(
        canvas,
        tp,
        tick.label,
        _volumeToPy(tick.displayNormalized),
      );
    }

    if (points.isEmpty) return;

    // // Automation curve
    // final linePaint = Paint()
    //   ..color = const Color(0xFF7AB9FF)
    //   ..strokeWidth = 2
    //   ..style = PaintingStyle.stroke
    //   ..strokeCap = StrokeCap.round;

    // final path = Path();

    // // Convert to pixel positions
    // final pixelPoints = points.map((p) {
    //   return Offset(
    //     _timeToPx(p.x), // x is timeMs
    //     _volumeToPy(p.volume),
    //   );
    // }).toList();

    // path.moveTo(pixelPoints.first.dx, pixelPoints.first.dy);
    // for (int i = 1; i < pixelPoints.length; i++) {
    //   path.lineTo(pixelPoints[i].dx, pixelPoints[i].dy);
    // }
    // canvas.drawPath(path, linePaint);

    // // Draw points
    // final fill = Paint()..color = Colors.white;
    // final stroke = Paint()
    //   ..color = Colors.black
    //   ..strokeWidth = 1.5
    //   ..style = PaintingStyle.stroke;

    // for (final p in pixelPoints) {
    //   canvas.drawCircle(p, 5, fill);
    //   canvas.drawCircle(p, 5, stroke);
    // }

    // // Labels next to each point
    // for (int i = 0; i < points.length; i++) {
    //   final modelPoint = points[i];
    //   final p = pixelPoints[i];

    //   final db = _volToDb(modelPoint.volume);
    //   final label = db.isInfinite ? "-∞" : "${db.toStringAsFixed(1)} dB";

    //   tp.text = TextSpan(
    //     text: label,
    //     style: const TextStyle(color: Colors.white70, fontSize: 9),
    //   );
    //   tp.layout();
    //   tp.paint(canvas, Offset(p.dx + 8, p.dy - 6));
    // }

    // ====================================================
    // Clip all automation drawings so nothing enters Y-axis
    // ====================================================

    final clipRect = Rect.fromLTWH(
      axisWidth,
      0,
      math.max(0.0, size.width - axisWidth),
      size.height,
    );

    canvas.save();
    canvas.clipRect(clipRect);

    if (hasHighlightWindow) {
      final startX = _timeToPx(highlightStartMs!).clamp(axisWidth, size.width);
      final endX = _timeToPx(highlightEndMs!).clamp(axisWidth, size.width);
      final left = math.min(startX, endX).toDouble();
      final right = math.max(startX, endX).toDouble();
      final windowRect = Rect.fromLTRB(left, 0, right, size.height);
      if (windowRect.width > 0.0) {
        final outsideShade = Paint()
          ..color = const Color(0xFF02060D).withValues(alpha: 0.34);
        final windowFill = Paint()
          ..color = const Color(0xFF6EA7FF).withValues(alpha: 0.07);
        final windowStroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = Colors.white.withValues(alpha: 0.22);

        if (windowRect.left > axisWidth) {
          canvas.drawRect(
            Rect.fromLTRB(axisWidth, 0, windowRect.left, size.height),
            outsideShade,
          );
        }
        if (windowRect.right < size.width) {
          canvas.drawRect(
            Rect.fromLTRB(windowRect.right, 0, size.width, size.height),
            outsideShade,
          );
        }
        canvas.drawRect(windowRect, windowFill);
        canvas.drawRect(windowRect, windowStroke);
      }
    }

    // ----- Automation curve inside the clipped area -----
    final linePaint = Paint()
      ..color = const Color(0xFFC3CBD4)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    // Convert to pixel positions
    final pixelPoints = points.map((p) {
      return Offset(
        _timeToPx(p.x), // x is timeMs
        _volumeToPy(_displayNormalizedForStoredNormalized(p.volume)),
      );
    }).toList();
    path.moveTo(pixelPoints.first.dx, pixelPoints.first.dy);
    for (int i = 1; i < pixelPoints.length; i++) {
      path.lineTo(pixelPoints[i].dx, pixelPoints[i].dy);
    }
    canvas.drawPath(path, linePaint);

    // ----- Points -----
    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final p in pixelPoints) {
      canvas.drawCircle(p, 5, fill);
      canvas.drawCircle(p, 5, stroke);
    }

    // ----- Point labels -----
    for (int i = 0; i < points.length; i++) {
      final modelPoint = points[i];
      final p = pixelPoints[i];

      final label = _formatValueLabel(modelPoint.volume);

      tp.text = TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white70, fontSize: 9),
      );
      tp.layout();
      tp.paint(canvas, Offset(p.dx + 8, p.dy - 6));
    }

    // End of clipped content
    canvas.restore();

    // Vertical boundary line
    // final boundaryPaint = Paint()
    //   ..color = Colors.white.withOpacity(0.15)
    //   ..strokeWidth = 1;

    // double axisWidth = 60; // Space taken by Y labels + margin

    // canvas.drawLine(
    //   Offset(axisWidth, verticalPadding),
    //   Offset(axisWidth, verticalPadding + _usableHeight),
    //   boundaryPaint,
    // );
  }

  @override
  bool shouldRepaint(_AutomationPainter old) {
    return old.points != points ||
        old.scrollOffsetMs != scrollOffsetMs ||
        old.pixelsPerMs != pixelsPerMs ||
        old.laneHeight != laneHeight ||
        old.verticalPadding != verticalPadding ||
        old.targetLabel != targetLabel ||
        old.targetParamId != targetParamId ||
        old.targetUnit != targetUnit ||
        old.targetMin != targetMin ||
        old.targetMax != targetMax ||
        old.targetDefaultNormalized != targetDefaultNormalized ||
        old.targetDisplayLabels != targetDisplayLabels ||
        old.highlightStartMs != highlightStartMs ||
        old.highlightEndMs != highlightEndMs ||
        old.isVolumeLane != isVolumeLane;
  }
}

class _AutomationAxisTick {
  const _AutomationAxisTick({
    required this.storedNormalized,
    required this.displayNormalized,
    required this.label,
  });

  final double storedNormalized;
  final double displayNormalized;
  final String label;
}

class _AutomationPointClipboardEntry {
  final _AutomationValueKind kind;
  final double rawValue;
  final String formattedValue;
  final String signature;

  const _AutomationPointClipboardEntry({
    required this.kind,
    required this.rawValue,
    required this.formattedValue,
    required this.signature,
  });

  bool isCompatibleWith(_AutomationValueFormatter formatter) {
    if (kind != formatter.valueKind) return false;
    if (kind == _AutomationValueKind.generic) {
      return signature == formatter.signature;
    }
    return true;
  }
}

enum _AutomationValueKind {
  volumeDb,
  gainUiDb,
  percent,
  db,
  hz,
  seconds,
  milliseconds,
  ratio,
  semitone,
  cents,
  generic,
}

const double _kGainAutomationUiUnity = 2.0;
const double _kGainAutomationDbMin = -60.0;
const double _kGainAutomationDbMax = 6.0;

class _AutomationValueFormatter {
  final String targetLabel;
  final String targetParamId;
  final String targetUnit;
  final double targetMin;
  final double targetMax;
  final Map<double, String> pluginDisplayLabels;
  final double? pluginDefaultNormalized;
  final bool isVolumeLane;

  const _AutomationValueFormatter({
    required this.targetLabel,
    required this.targetParamId,
    this.targetUnit = '',
    required this.targetMin,
    required this.targetMax,
    this.pluginDisplayLabels = const <double, String>{},
    this.pluginDefaultNormalized,
    required this.isVolumeLane,
  });

  String get signature =>
      '${targetLabel.trim().toLowerCase()}|${targetParamId.trim().toLowerCase()}|${targetUnit.trim().toLowerCase()}|$targetMin|$targetMax|$isVolumeLane|${pluginDisplayLabels.entries.map((e) => '${e.key}:${e.value}').join('|')}';

  double _normalizedToTargetValue(double normalized) {
    final span = targetMax - targetMin;
    if (!span.isFinite || span.abs() < 1e-9) {
      return normalized.clamp(0.0, 1.0).toDouble();
    }
    return targetMin + span * normalized.clamp(0.0, 1.0).toDouble();
  }

  double _targetValueToNormalized(double rawValue) {
    final span = targetMax - targetMin;
    if (!span.isFinite || span.abs() < 1e-9) {
      return rawValue.clamp(0.0, 1.0).toDouble();
    }
    return ((rawValue - targetMin) / span).clamp(0.0, 1.0).toDouble();
  }

  double get _logDisplayMin {
    if (!targetMin.isFinite || !targetMax.isFinite || targetMax <= 0.0) {
      return double.nan;
    }
    if (targetMin > 0.0) return targetMin;
    switch (valueKind) {
      case _AutomationValueKind.hz:
        return math.max(1.0, math.min(20.0, targetMax / 1000.0));
      case _AutomationValueKind.seconds:
        return math.max(0.001, targetMax / 1000.0);
      case _AutomationValueKind.milliseconds:
        return math.max(1.0, targetMax / 1000.0);
      case _AutomationValueKind.ratio:
        return math.max(0.01, targetMax / 1000.0);
      case _AutomationValueKind.volumeDb:
      case _AutomationValueKind.gainUiDb:
      case _AutomationValueKind.percent:
      case _AutomationValueKind.db:
      case _AutomationValueKind.semitone:
      case _AutomationValueKind.cents:
      case _AutomationValueKind.generic:
        return double.nan;
    }
  }

  bool get _hasLogDisplayRange {
    final min = _logDisplayMin;
    if (!min.isFinite || !targetMax.isFinite) return false;
    return min > 0.0 && targetMax > min;
  }

  bool get _usesLogDisplay {
    if (!_hasLogDisplayRange) return false;
    final ratio = targetMax / _logDisplayMin;
    switch (valueKind) {
      case _AutomationValueKind.hz:
        return ratio >= 2.0;
      case _AutomationValueKind.seconds:
      case _AutomationValueKind.milliseconds:
      case _AutomationValueKind.ratio:
        return ratio >= 8.0;
      case _AutomationValueKind.volumeDb:
      case _AutomationValueKind.gainUiDb:
      case _AutomationValueKind.percent:
      case _AutomationValueKind.db:
      case _AutomationValueKind.semitone:
      case _AutomationValueKind.cents:
      case _AutomationValueKind.generic:
        return false;
    }
  }

  double _displayNormalizedForRawValue(double rawValue) {
    if (!_usesLogDisplay) return _targetValueToNormalized(rawValue);
    final logMin = _logDisplayMin;
    if (!logMin.isFinite || logMin <= 0.0) {
      return _targetValueToNormalized(rawValue);
    }
    if (targetMin <= 0.0 && rawValue <= targetMin + 0.000001) {
      return 0.0;
    }
    final minLog = math.log(logMin);
    final maxLog = math.log(targetMax);
    final span = maxLog - minLog;
    if (!span.isFinite || span.abs() < 1e-9) {
      return _targetValueToNormalized(rawValue);
    }
    final safeRaw = rawValue.clamp(logMin, targetMax).toDouble();
    return ((math.log(safeRaw) - minLog) / span).clamp(0.0, 1.0).toDouble();
  }

  double _rawValueForDisplayNormalized(double displayNormalized) {
    final clamped = displayNormalized.clamp(0.0, 1.0).toDouble();
    if (!_usesLogDisplay) return _normalizedToTargetValue(clamped);
    if (clamped <= 0.000001) return targetMin;
    final logMin = _logDisplayMin;
    if (!logMin.isFinite || logMin <= 0.0) {
      return _normalizedToTargetValue(clamped);
    }
    final minLog = math.log(logMin);
    final maxLog = math.log(targetMax);
    final span = maxLog - minLog;
    if (!span.isFinite || span.abs() < 1e-9) {
      return _normalizedToTargetValue(clamped);
    }
    return math
        .exp(minLog + (span * clamped))
        .clamp(targetMin, targetMax)
        .toDouble();
  }

  double get midGuideStoredNormalized {
    if (isVolumeLane) return 0.75;
    final pluginDefault = pluginDefaultNormalized;
    if (pluginDefault != null && pluginDefault.isFinite) {
      return pluginDefault.clamp(0.0, 1.0).toDouble();
    }
    if (valueKind == _AutomationValueKind.gainUiDb) {
      return _targetValueToNormalized(_kGainAutomationUiUnity);
    }
    if (_usesLogDisplay) {
      return _targetValueToNormalized(_rawValueForDisplayNormalized(0.5));
    }
    return 0.5;
  }

  String? _pluginDisplayLabelFor(double normalized) {
    if (pluginDisplayLabels.isEmpty) return null;
    final clamped = normalized.clamp(0.0, 1.0).toDouble();
    for (final entry in pluginDisplayLabels.entries) {
      if ((entry.key - clamped).abs() <= 0.0005) {
        final label = entry.value.trim();
        if (label.isNotEmpty) return label;
      }
    }
    return null;
  }

  String _trimTrailingZeros(String text) {
    if (!text.contains('.')) return text;
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _formatNumber(double value, {int maxDecimals = 2}) {
    if (!value.isFinite) return value.toString();
    final absValue = value.abs();
    final decimals = absValue >= 1000
        ? 0
        : (absValue >= 100
              ? 1
              : (absValue >= 10 ? math.min(maxDecimals, 1) : maxDecimals));
    return _trimTrailingZeros(value.toStringAsFixed(decimals));
  }

  bool _containsAny(String haystack, List<String> needles) {
    for (final needle in needles) {
      if (haystack.contains(needle)) return true;
    }
    return false;
  }

  String get _targetParamContext {
    final lowerLabel = targetLabel.trim().toLowerCase();
    final paramLabel = lowerLabel.contains('•')
        ? lowerLabel.split('•').last.trim()
        : lowerLabel;
    return '$paramLabel ${targetParamId.trim().toLowerCase()}';
  }

  bool _containsTimeUnitToken(String haystack) {
    return RegExp(
      r'(^|[^a-z0-9])(ms|msec|millisecond|milliseconds|s|sec|secs|second|seconds)($|[^a-z0-9])',
    ).hasMatch(haystack);
  }

  String get _normalizedUnit {
    final raw = targetUnit.trim().toLowerCase();
    if (raw.isEmpty) return '';
    if (raw == 'hz' || raw == 'khz') return raw;
    if (raw == 'db' || raw == 'dB'.toLowerCase()) return 'db';
    if (raw == '%' || raw == 'percent' || raw == 'percentage') return '%';
    if (raw == 'ms' || raw == 'millisecond' || raw == 'milliseconds') {
      return 'ms';
    }
    if (raw == 's' || raw == 'sec' || raw == 'second' || raw == 'seconds') {
      return 's';
    }
    if (raw == 'deg' || raw == 'degree' || raw == 'degrees' || raw == '°') {
      return 'deg';
    }
    if (raw == 'st' || raw == 'semitone' || raw == 'semitones') return 'st';
    if (raw == 'ct' || raw == 'cent' || raw == 'cents') return 'ct';
    if (raw == 'q') return 'q';
    return raw;
  }

  _AutomationValueKind get valueKind {
    if (isVolumeLane) return _AutomationValueKind.volumeDb;

    final context = _targetParamContext;
    final unit = _normalizedUnit;
    final min = targetMin;
    final max = targetMax;
    final span = max - min;
    final hasValidRange = span.isFinite && span.abs() >= 1e-9;
    final looksNormalizedRange = min >= -0.001 && max <= 1.001;
    final looksUnipolarPercentRange = min >= -0.1 && max <= 100.1;
    final looksBipolarPercentRange = min >= -100.1 && max <= 100.1;
    final looksPercentRange =
        hasValidRange &&
        (looksUnipolarPercentRange || looksBipolarPercentRange);

    final hasDbHint =
        unit == 'db' ||
        _containsAny(context, const ['db', 'threshold', 'ceiling']);
    final hasGainHint = _containsAny(context, const [
      'gain',
      'level',
      'trim',
      'makeup',
      'boost',
      'attenuation',
    ]);
    if (hasGainHint && min >= -0.001 && max > 1.001 && max <= 3.001) {
      return _AutomationValueKind.gainUiDb;
    }
    if (hasDbHint) {
      return _AutomationValueKind.db;
    }

    if (unit == 'hz' ||
        unit == 'khz' ||
        _containsAny(context, const [
          'freq',
          'frequency',
          'cutoff',
          'hz',
          'highpass',
          'lowpass',
        ]) ||
        (hasValidRange && min >= 0.0 && max >= 1500.0 && max <= 50000.0)) {
      return _AutomationValueKind.hz;
    }

    final hasPercentHint = _containsAny(context, const [
      'mix',
      'wet',
      'dry',
      'amount',
      'depth',
      'feedback',
      'size',
      'room',
      'damp',
      'damping',
      'diffusion',
      'density',
      'drive',
      'spread',
      'width',
      'pan',
      'pump',
      'sustain',
      'speed',
      'smooth',
      'swing',
      'correction',
      '%',
    ]);
    final looksCanonicalPercentRange =
        hasValidRange && min >= -0.001 && max >= 99.9 && max <= 100.1;
    if (unit == '%' ||
        (looksPercentRange &&
            (hasPercentHint ||
                looksNormalizedRange ||
                looksCanonicalPercentRange))) {
      return _AutomationValueKind.percent;
    }

    final hasTimeHint =
        _containsAny(context, const [
          'attack',
          'release',
          'decay',
          'delay',
          'predelay',
          'pre-delay',
          'pre delay',
          'hold',
          'time',
        ]) ||
        _containsTimeUnitToken(context);
    if (unit == 'ms' || unit == 's' || hasTimeHint) {
      if (unit == 'ms' ||
          _containsTimeUnitToken(context) ||
          (hasValidRange && max > 20.0)) {
        return _AutomationValueKind.milliseconds;
      }
      return _AutomationValueKind.seconds;
    }

    if (unit == 'st' ||
        _containsAny(context, const ['semitone', 'semi-tone'])) {
      return _AutomationValueKind.semitone;
    }
    if (unit == 'ct' || _containsAny(context, const ['cents'])) {
      return _AutomationValueKind.cents;
    }
    if (_containsAny(context, const ['ratio'])) {
      return _AutomationValueKind.ratio;
    }

    if (hasGainHint && (min < 0.0 || max > 2.5)) {
      return _AutomationValueKind.db;
    }

    return _AutomationValueKind.generic;
  }

  double _volToDb(double value) {
    if (value <= 0.0001) return double.negativeInfinity;
    final clamped = value.clamp(0.0, 1.0).toDouble();
    final gain = clamped >= 0.75
        ? (1.0 + ((clamped - 0.75) / 0.25))
        : (clamped / 0.75);
    if (gain <= 0.0001) return double.negativeInfinity;
    return 20 * math.log(gain) / math.log(10);
  }

  double _dbToVol(double db) {
    if (!db.isFinite && db.isNegative) return 0.0;
    final gain = math.pow(10.0, db / 20.0).toDouble();
    if (gain <= 1.0) {
      return (gain * 0.75).clamp(0.0, 0.75);
    }
    return (0.75 + ((gain - 1.0) * 0.25)).clamp(0.75, 1.0);
  }

  double _gainUiToDb(double gainUi) {
    final min = targetMin.isFinite ? targetMin : 0.0;
    final max = targetMax.isFinite && targetMax > min ? targetMax : 3.0;
    final unity = _kGainAutomationUiUnity.clamp(min, max).toDouble();
    final clamped = gainUi.clamp(min, max).toDouble();
    if (clamped <= unity) {
      final t = ((clamped - min) / (unity - min)).clamp(0.0, 1.0).toDouble();
      return _kGainAutomationDbMin + ((0.0 - _kGainAutomationDbMin) * t);
    }
    final t = ((clamped - unity) / (max - unity)).clamp(0.0, 1.0).toDouble();
    return _kGainAutomationDbMax * t;
  }

  double _dbToGainUi(double db) {
    final min = targetMin.isFinite ? targetMin : 0.0;
    final max = targetMax.isFinite && targetMax > min ? targetMax : 3.0;
    final unity = _kGainAutomationUiUnity.clamp(min, max).toDouble();
    if (!db.isFinite && db.isNegative) return min;
    final clampedDb = db
        .clamp(_kGainAutomationDbMin, _kGainAutomationDbMax)
        .toDouble();
    if (clampedDb <= 0.0) {
      final t =
          ((clampedDb - _kGainAutomationDbMin) / (0.0 - _kGainAutomationDbMin))
              .clamp(0.0, 1.0);
      return (min + ((unity - min) * t)).clamp(min, max).toDouble();
    }
    final t = (clampedDb / _kGainAutomationDbMax).clamp(0.0, 1.0);
    return (unity + ((max - unity) * t)).clamp(min, max).toDouble();
  }

  double _gainDbToDisplayNormalized(double db) {
    if (!db.isFinite && db.isNegative) return 0.0;
    final clampedDb = db
        .clamp(_kGainAutomationDbMin, _kGainAutomationDbMax)
        .toDouble();
    if (clampedDb <= 0.0) {
      final t =
          ((clampedDb - _kGainAutomationDbMin) / (0.0 - _kGainAutomationDbMin))
              .clamp(0.0, 1.0)
              .toDouble();
      return (t * 0.75).clamp(0.0, 0.75).toDouble();
    }
    final t = (clampedDb / _kGainAutomationDbMax).clamp(0.0, 1.0).toDouble();
    return (0.75 + (t * 0.25)).clamp(0.75, 1.0).toDouble();
  }

  double _displayNormalizedToGainDb(double displayNormalized) {
    final clamped = displayNormalized.clamp(0.0, 1.0).toDouble();
    if (clamped <= 0.0) return double.negativeInfinity;
    if (clamped <= 0.75) {
      final t = (clamped / 0.75).clamp(0.0, 1.0).toDouble();
      return _kGainAutomationDbMin + ((0.0 - _kGainAutomationDbMin) * t);
    }
    final t = ((clamped - 0.75) / 0.25).clamp(0.0, 1.0).toDouble();
    return _kGainAutomationDbMax * t;
  }

  double displayNormalizedForStoredNormalized(double normalized) {
    final clamped = normalized.clamp(0.0, 1.0).toDouble();
    if (valueKind != _AutomationValueKind.gainUiDb) {
      return _displayNormalizedForRawValue(_normalizedToTargetValue(clamped));
    }
    final raw = _normalizedToTargetValue(clamped);
    if (raw <= targetMin + 0.000001) return 0.0;
    return _gainDbToDisplayNormalized(_gainUiToDb(raw));
  }

  double storedNormalizedForDisplayNormalized(double displayNormalized) {
    final clamped = displayNormalized.clamp(0.0, 1.0).toDouble();
    if (valueKind != _AutomationValueKind.gainUiDb) {
      return _targetValueToNormalized(_rawValueForDisplayNormalized(clamped));
    }
    if (clamped <= 0.000001) {
      return _targetValueToNormalized(targetMin);
    }
    return _targetValueToNormalized(
      _dbToGainUi(_displayNormalizedToGainDb(clamped)),
    );
  }

  double rawValueForNormalized(double normalized) {
    final clamped = normalized.clamp(0.0, 1.0).toDouble();
    switch (valueKind) {
      case _AutomationValueKind.volumeDb:
        return _volToDb(clamped);
      case _AutomationValueKind.gainUiDb:
        return _gainUiToDb(_normalizedToTargetValue(clamped));
      case _AutomationValueKind.percent:
      case _AutomationValueKind.db:
      case _AutomationValueKind.hz:
      case _AutomationValueKind.seconds:
      case _AutomationValueKind.milliseconds:
      case _AutomationValueKind.ratio:
      case _AutomationValueKind.semitone:
      case _AutomationValueKind.cents:
      case _AutomationValueKind.generic:
        return _normalizedToTargetValue(clamped);
    }
  }

  double normalizedForRawValue(double rawValue) {
    switch (valueKind) {
      case _AutomationValueKind.volumeDb:
        return _dbToVol(rawValue);
      case _AutomationValueKind.gainUiDb:
        return _targetValueToNormalized(_dbToGainUi(rawValue));
      case _AutomationValueKind.percent:
      case _AutomationValueKind.db:
      case _AutomationValueKind.hz:
      case _AutomationValueKind.seconds:
      case _AutomationValueKind.milliseconds:
      case _AutomationValueKind.ratio:
      case _AutomationValueKind.semitone:
      case _AutomationValueKind.cents:
      case _AutomationValueKind.generic:
        return _targetValueToNormalized(rawValue);
    }
  }

  String formatValueLabel(double normalized) {
    final clamped = normalized.clamp(0.0, 1.0).toDouble();

    if (isVolumeLane) {
      final db = _volToDb(clamped);
      if (db.isInfinite) return '-∞';
      final value = _formatNumber(db.abs(), maxDecimals: 1);
      final sign = db >= 0 ? '+' : '-';
      return '$sign$value dB';
    }

    final pluginLabel = _pluginDisplayLabelFor(clamped);
    if (pluginLabel != null) return pluginLabel;

    final raw = _normalizedToTargetValue(clamped);
    switch (valueKind) {
      case _AutomationValueKind.volumeDb:
        final db = _volToDb(clamped);
        if (db.isInfinite) return '-∞';
        final value = _formatNumber(db.abs(), maxDecimals: 1);
        final sign = db >= 0 ? '+' : '-';
        return '$sign$value dB';
      case _AutomationValueKind.gainUiDb:
        final db = _gainUiToDb(raw);
        if (db.isInfinite || raw <= targetMin + 0.000001) return '-∞';
        final value = _formatNumber(db.abs(), maxDecimals: 1);
        final sign = db >= 0 ? '+' : '-';
        return '$sign$value dB';
      case _AutomationValueKind.percent:
        final looksNormalizedRange = targetMin >= -0.001 && targetMax <= 1.001;
        final pct = looksNormalizedRange ? raw * 100.0 : raw;
        return '${_formatNumber(pct, maxDecimals: 1)}%';
      case _AutomationValueKind.db:
        final sign = raw > 0 ? '+' : '';
        return '$sign${_formatNumber(raw, maxDecimals: 1)} dB';
      case _AutomationValueKind.hz:
        if (raw.abs() >= 1000.0) {
          return '${_formatNumber(raw / 1000.0, maxDecimals: 2)} kHz';
        }
        return '${_formatNumber(raw, maxDecimals: raw.abs() >= 100 ? 0 : 1)} Hz';
      case _AutomationValueKind.seconds:
        if (raw.abs() < 1.0) {
          return '${_formatNumber(raw * 1000.0, maxDecimals: 0)} ms';
        }
        return '${_formatNumber(raw, maxDecimals: 2)} s';
      case _AutomationValueKind.milliseconds:
        if (raw.abs() >= 1000.0) {
          return '${_formatNumber(raw / 1000.0, maxDecimals: 2)} s';
        }
        return '${_formatNumber(raw, maxDecimals: raw.abs() >= 100 ? 0 : 1)} ms';
      case _AutomationValueKind.ratio:
        if (raw <= 0.0) return _formatNumber(raw, maxDecimals: 2);
        return '${_formatNumber(raw, maxDecimals: 2)}:1';
      case _AutomationValueKind.semitone:
        final sign = raw > 0 ? '+' : '';
        return '$sign${_formatNumber(raw, maxDecimals: 1)} st';
      case _AutomationValueKind.cents:
        final sign = raw > 0 ? '+' : '';
        return '$sign${_formatNumber(raw, maxDecimals: 0)} ct';
      case _AutomationValueKind.generic:
        final unit = _normalizedUnit;
        if (unit == 'deg') return '${_formatNumber(raw, maxDecimals: 0)}°';
        if (unit == 'q') return '${_formatNumber(raw, maxDecimals: 2)} Q';
        if (unit.isNotEmpty) {
          return '${_formatNumber(raw, maxDecimals: 2)} $targetUnit';
        }
        return _formatNumber(raw, maxDecimals: 2);
    }
  }

  String editableValueText(double normalized) => formatValueLabel(normalized);

  String get inputLabel {
    switch (valueKind) {
      case _AutomationValueKind.volumeDb:
      case _AutomationValueKind.gainUiDb:
        return 'volume value';
      case _AutomationValueKind.percent:
        return 'percent value';
      case _AutomationValueKind.db:
        return 'dB value';
      case _AutomationValueKind.hz:
        return 'frequency value';
      case _AutomationValueKind.seconds:
      case _AutomationValueKind.milliseconds:
        return 'time value';
      case _AutomationValueKind.ratio:
        return 'ratio value';
      case _AutomationValueKind.semitone:
        return 'semitone value';
      case _AutomationValueKind.cents:
        return 'cent value';
      case _AutomationValueKind.generic:
        return 'numeric value';
    }
  }

  String get inputHint {
    switch (valueKind) {
      case _AutomationValueKind.volumeDb:
      case _AutomationValueKind.gainUiDb:
        return 'e.g. 0 dB, -12, -inf';
      case _AutomationValueKind.percent:
        return 'e.g. 50%';
      case _AutomationValueKind.db:
        return 'e.g. -6 dB';
      case _AutomationValueKind.hz:
        return 'e.g. 1200 Hz or 1.2 kHz';
      case _AutomationValueKind.seconds:
      case _AutomationValueKind.milliseconds:
        return 'e.g. 250 ms or 0.25 s';
      case _AutomationValueKind.ratio:
        return 'e.g. 4:1';
      case _AutomationValueKind.semitone:
        return 'e.g. +7 st';
      case _AutomationValueKind.cents:
        return 'e.g. -25 ct';
      case _AutomationValueKind.generic:
        return 'Enter a numeric value';
    }
  }

  double? _extractFirstNumber(String input) {
    final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(input);
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }

  bool _hasSecondsUnit(String input) {
    return RegExp(r'(^|[^a-z])s(ec(ond)?s?)?($|[^a-z])').hasMatch(input) &&
        !input.contains('ms');
  }

  double? parseInputToNormalized(String input) {
    final lower = input.trim().toLowerCase();
    if (lower.isEmpty) return null;

    if (valueKind == _AutomationValueKind.volumeDb ||
        valueKind == _AutomationValueKind.gainUiDb) {
      if (lower == '-∞' ||
          lower == '-inf' ||
          lower == 'inf-' ||
          lower == 'off') {
        return 0.0;
      }
      final db = _extractFirstNumber(lower);
      if (db == null) return null;
      return valueKind == _AutomationValueKind.volumeDb
          ? _dbToVol(db)
          : _targetValueToNormalized(_dbToGainUi(db));
    }

    var parsed = _extractFirstNumber(lower);
    if (parsed == null) return null;

    switch (valueKind) {
      case _AutomationValueKind.volumeDb:
        return _dbToVol(parsed);
      case _AutomationValueKind.gainUiDb:
        return _targetValueToNormalized(_dbToGainUi(parsed));
      case _AutomationValueKind.percent:
        final looksNormalizedRange = targetMin >= -0.001 && targetMax <= 1.001;
        if (looksNormalizedRange) {
          parsed /= 100.0;
        }
        return _targetValueToNormalized(parsed);
      case _AutomationValueKind.db:
        return _targetValueToNormalized(parsed);
      case _AutomationValueKind.hz:
        if (lower.contains('khz') ||
            RegExp(r'(^|[^a-z])k($|[^a-z])').hasMatch(lower)) {
          parsed *= 1000.0;
        }
        return _targetValueToNormalized(parsed);
      case _AutomationValueKind.seconds:
        if (lower.contains('ms')) {
          parsed /= 1000.0;
        }
        return _targetValueToNormalized(parsed);
      case _AutomationValueKind.milliseconds:
        if (_hasSecondsUnit(lower)) {
          parsed *= 1000.0;
        }
        return _targetValueToNormalized(parsed);
      case _AutomationValueKind.ratio:
        return _targetValueToNormalized(parsed);
      case _AutomationValueKind.semitone:
        return _targetValueToNormalized(parsed);
      case _AutomationValueKind.cents:
        return _targetValueToNormalized(parsed);
      case _AutomationValueKind.generic:
        return _targetValueToNormalized(parsed);
    }
  }
}

// -----------------------------------------------------------------------------
// BEAUTIFUL STYLED SLIDERS — Matches your screenshot exactly
// -----------------------------------------------------------------------------

class _SliderStepButton extends StatelessWidget {
  const _SliderStepButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: Material(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(
              icon,
              size: 15,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ),
      ),
    );
  }
}

class PrettyStereoSlider extends StatefulWidget {
  final double value; // 0 to 1
  final ValueChanged<double> onChangeStart, onChanged, onChangeEnd;
  final VoidCallback? onLongPress;
  final bool showStepButtons;
  final bool stackedLayout;
  final String? label;

  const PrettyStereoSlider({
    super.key,
    required this.value,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    this.onLongPress,
    this.showStepButtons = false,
    this.stackedLayout = false,
    this.label,
  });

  @override
  State<PrettyStereoSlider> createState() => _PrettyStereoSliderState();
}

double _pan01ToSignedPercent(double pan01) {
  final clamped = pan01.clamp(0.0, 1.0).toDouble();
  return ((clamped - 0.5) * 2.0) * 100.0;
}

String _panReadoutText(BuildContext context, double pan01) {
  final signedPercent = _pan01ToSignedPercent(pan01);
  if (signedPercent.abs() < 2.0) return L10n.translate(context, 'Center');
  final rounded = signedPercent.abs().round();
  return signedPercent < 0 ? 'L $rounded%' : 'R $rounded%';
}

class _SliderDefaultMarkerPainter extends CustomPainter {
  final double positionFraction;
  final Color color;
  final double edgeInset;

  const _SliderDefaultMarkerPainter({
    required this.positionFraction,
    required this.color,
    this.edgeInset = 12.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final clampedFraction = positionFraction.clamp(0.0, 1.0);
    final trackWidth = math.max(0.0, size.width - (edgeInset * 2));
    if (trackWidth <= 0.0) return;

    final x = edgeInset + (trackWidth * clampedFraction);
    final centerY = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(x, centerY - 8), Offset(x, centerY + 8), paint);
  }

  @override
  bool shouldRepaint(covariant _SliderDefaultMarkerPainter oldDelegate) {
    return oldDelegate.positionFraction != positionFraction ||
        oldDelegate.color != color ||
        oldDelegate.edgeInset != edgeInset;
  }
}

class _PrettyStereoSliderState extends State<PrettyStereoSlider> {
  void _commitImmediatePan(double nextValue) {
    final current = widget.value.clamp(0.0, 1.0).toDouble();
    final next = nextValue.clamp(0.0, 1.0).toDouble();
    if ((current - next).abs() < 1.0e-6) return;
    widget.onChangeStart(current);
    setState(() {});
    widget.onChanged(next);
    widget.onChangeEnd(next);
  }

  Future<void> _showPanAdjustDialog() async {
    var percentValue = _pan01ToSignedPercent(
      widget.value,
    ).clamp(-100.0, 100.0).toDouble();
    final controller = TextEditingController(
      text: _formatPanPercentInput(percentValue),
    );
    final submitted = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF252A32),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          title: Text(
            L10n.translate(dialogContext, 'Set pan'),
            style: const TextStyle(color: Colors.white),
          ),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              void setPercent(double next) {
                percentValue = next.clamp(-100.0, 100.0).toDouble();
                controller.text = _formatPanPercentInput(percentValue);
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                setDialogState(() {});
              }

              double? parsePercentInput(String text) {
                final normalized = text
                    .trim()
                    .replaceAll(',', '.')
                    .replaceAll('+', '')
                    .replaceAll('%', '');
                if (normalized.isEmpty || normalized == '-') return null;
                final parsed = double.tryParse(normalized);
                if (parsed == null || !parsed.isFinite) return null;
                return parsed.clamp(-100.0, 100.0).toDouble();
              }

              final previewPan01 = ((percentValue / 100.0) + 1.0) / 2.0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: L10n.translate(context, 'Pan left'),
                        onPressed: () => setPercent(percentValue - 1.0),
                        icon: const Icon(Icons.remove, color: Colors.white),
                      ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+\-.,%]'),
                            ),
                          ],
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            suffixText: '%',
                            suffixStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                            helperText: '-100 left, 0 center, +100 right',
                            helperStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.60),
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.08),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.42),
                              ),
                            ),
                            isDense: true,
                          ),
                          onChanged: (text) {
                            final parsed = parsePercentInput(text);
                            if (parsed == null) return;
                            percentValue = parsed;
                            setDialogState(() {});
                          },
                          onSubmitted: (text) {
                            Navigator.of(
                              dialogContext,
                            ).pop(parsePercentInput(text));
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: L10n.translate(context, 'Pan right'),
                        onPressed: () => setPercent(percentValue + 1.0),
                        icon: const Icon(Icons.add, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _panReadoutText(context, previewPan01),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.76),
                      fontSize: 13,
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(L10n.translate(dialogContext, 'Cancel')),
            ),
            TextButton(
              onPressed: () {
                final normalized = controller.text
                    .trim()
                    .replaceAll(',', '.')
                    .replaceAll('+', '')
                    .replaceAll('%', '');
                Navigator.of(dialogContext).pop(
                  normalized.isEmpty
                      ? null
                      : double.tryParse(
                          normalized,
                        )?.clamp(-100.0, 100.0).toDouble(),
                );
              },
              child: Text(L10n.translate(dialogContext, 'Apply')),
            ),
          ],
        );
      },
    );
    if (submitted == null || !submitted.isFinite) return;
    _commitImmediatePan(((submitted / 100.0) + 1.0) / 2.0);
  }

  String _formatPanPercentInput(double percent) {
    final clamped = percent.clamp(-100.0, 100.0).toDouble();
    if (clamped.abs() < 0.5) return '0';
    return clamped.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    const sliderThumbRadius = 11.0;
    final labelWidth = widget.showStepButtons ? 42.0 : null;
    final readoutWidth = widget.showStepButtons ? 64.0 : 58.0;
    final readoutText = _panReadoutText(context, widget.value);
    final labelText = widget.label ?? L10n.translate(context, 'Pan');

    Widget stepButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
    }) {
      return _SliderStepButton(icon: icon, tooltip: tooltip, onTap: onTap);
    }

    Widget valueButton({double width = 58.0}) {
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showPanAdjustDialog();
          });
        },
        child: SizedBox(
          width: width,
          height: 28,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                readoutText,
                maxLines: 1,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),
      );
    }

    Widget sliderTrack() {
      final activeTrackColor = widget.stackedLayout
          ? const Color(0xFF778492)
          : const Color(0xFF4D5566);
      final inactiveTrackColor = widget.stackedLayout
          ? const Color(0xFF596574)
          : const Color(0xFF4D5566);
      final markerColor = widget.stackedLayout
          ? Colors.white.withValues(alpha: 0.34)
          : Colors.white.withValues(alpha: 0.24);
      final thumbColor = widget.stackedLayout
          ? const Color(0xFFE8EDF4)
          : const Color(0xFFB7BECC);
      final trackBody = SizedBox(
        height: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SliderDefaultMarkerPainter(
                    positionFraction: 0.5,
                    color: markerColor,
                    edgeInset: sliderThumbRadius + 1,
                  ),
                ),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: sliderThumbRadius,
                ),
                overlayShape: SliderComponentShape.noOverlay,
                showValueIndicator: ShowValueIndicator.onDrag,
                valueIndicatorTextStyle: const TextStyle(
                  color: Color.fromARGB(255, 0, 0, 0),
                  fontSize: 12,
                ),
                activeTrackColor: activeTrackColor,
                inactiveTrackColor: inactiveTrackColor,
                thumbColor: thumbColor,
              ),
              child: DesktopScrollableSlider(
                value: widget.value,
                min: 0,
                max: 1,
                divisions: 200,
                label: readoutText,
                onChangeStart: (v) {
                  widget.onChangeStart(v);
                },
                onChanged: (v) {
                  setState(() {});
                  widget.onChanged(v);
                },
                onChangeEnd: (v) {
                  widget.onChangeEnd(v);
                },
              ),
            ),
          ],
        ),
      );
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: widget.onLongPress,
        onDoubleTap: () {
          _commitImmediatePan(0.5);
        },
        child: trackBody,
      );
    }

    if (widget.stackedLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  labelText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              stepButton(
                icon: Icons.remove,
                tooltip: L10n.translate(context, 'Pan left'),
                onTap: () => _commitImmediatePan(widget.value - 0.005),
              ),
              const SizedBox(width: 6),
              valueButton(width: 64.0),
              const SizedBox(width: 6),
              stepButton(
                icon: Icons.add,
                tooltip: L10n.translate(context, 'Pan right'),
                onTap: () => _commitImmediatePan(widget.value + 0.005),
              ),
            ],
          ),
          const SizedBox(height: 7),
          sliderTrack(),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            '${L10n.translate(context, 'Pan')}:',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        const SizedBox(width: 6),
        if (widget.showStepButtons) ...[
          stepButton(
            icon: Icons.remove,
            tooltip: L10n.translate(context, 'Pan left'),
            onTap: () => _commitImmediatePan(widget.value - 0.005),
          ),
          const SizedBox(width: 3),
        ],
        Expanded(child: sliderTrack()),
        if (widget.showStepButtons) ...[
          const SizedBox(width: 3),
          stepButton(
            icon: Icons.add,
            tooltip: L10n.translate(context, 'Pan right'),
            onTap: () => _commitImmediatePan(widget.value + 0.005),
          ),
        ],
        SizedBox(width: widget.showStepButtons ? 6 : 4),
        valueButton(width: readoutWidth),
      ],
    );
  }
}

class ImmediatePanGestureRecognizer extends PanGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    // Accept the gesture immediately on pointer down
    if (event is PointerDownEvent) {
      resolve(GestureDisposition.accepted);
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    // Prevent long delays when ending
    super.didStopTrackingLastPointer(pointer);
  }
}

class ZeroSlopPanGestureRecognizer extends PanGestureRecognizer {
  int? hitIndex; // store which point we touched

  ZeroSlopPanGestureRecognizer() {
    // Remove slop so drag starts immediately
    dragStartBehavior = DragStartBehavior.down;
    minFlingDistance = 0;
    minFlingVelocity = 0;
  }

  @override
  void handleEvent(PointerEvent event) {
    // DO NOT auto-accept here!
    // This preserves tap, double-tap, long-press.
    super.handleEvent(event);
  }
}

class PrettyGainSlider extends StatefulWidget {
  final double value; // 0 - maxValue
  final double maxValue;
  final ValueChanged<double> onChangeStart, onChanged, onChangeEnd;
  final bool showLabel;
  final Color trackColor;
  final Color inactiveTrackColor;
  final Color thumbColor;
  final VoidCallback? onLongPress;
  final bool showStepButtons;
  final bool stackedLayout;
  final String? label;

  const PrettyGainSlider({
    super.key,
    required this.value,
    this.maxValue = 3.0,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    this.showLabel = true,
    this.trackColor = const Color(0xFF4D5566),
    this.inactiveTrackColor = const Color(0xFF333A45),
    this.thumbColor = const Color(0xFFB7BECC),
    this.onLongPress,
    this.showStepButtons = false,
    this.stackedLayout = false,
    this.label,
  });

  @override
  State<PrettyGainSlider> createState() => _PrettyGainSliderState();
}

class _PrettyGainSliderState extends State<PrettyGainSlider> {
  static const double _unityUi = 2.0;
  static const double _dbMin = -60.0;
  static const double _dbMax = 6.0;

  double get _unity => math.min(_unityUi, widget.maxValue);

  double _gainToDb(double sliderValue) {
    final clamped = sliderValue.clamp(0.0, widget.maxValue).toDouble();
    final unity = _unity;

    if (clamped <= unity) {
      final t = unity <= 0.0 ? 0.0 : (clamped / unity).clamp(0.0, 1.0);
      return _dbMin + ((0.0 - _dbMin) * t);
    }

    final t = (widget.maxValue <= unity)
        ? 0.0
        : ((clamped - unity) / (widget.maxValue - unity)).clamp(0.0, 1.0);
    return 0.0 + ((_dbMax - 0.0) * t);
  }

  double _dbToGainUi(double dbValue) {
    final unity = _unity;
    final clampedDb = dbValue.clamp(_dbMin, _dbMax).toDouble();

    if (clampedDb <= 0.0) {
      final t = ((clampedDb - _dbMin) / (0.0 - _dbMin)).clamp(0.0, 1.0);
      return unity * t;
    }

    final t = (_dbMax <= 0.0) ? 0.0 : (clampedDb / _dbMax).clamp(0.0, 1.0);
    return unity + ((widget.maxValue - unity) * t);
  }

  double _gainUiToVisualValue(double gainUi) {
    const dbMin = -60.0;
    final unity = _unity;
    final db = _gainToDb(gainUi);

    if (db <= 0.0) {
      final ampMin = math.pow(10.0, dbMin / 20.0).toDouble();
      final amp = math.pow(10.0, db / 20.0).toDouble();
      final normalizedAmp = ((amp - ampMin) / (1.0 - ampMin))
          .clamp(0.0, 1.0)
          .toDouble();
      final curved = math.sqrt(normalizedAmp);
      return unity * curved;
    }

    final positiveRange = widget.maxValue - unity;
    if (positiveRange <= 0.0) return unity;
    return unity + (positiveRange * (gainUi - unity) / positiveRange);
  }

  double _visualValueToGainUi(double visualValue) {
    const dbMin = -60.0;
    final unity = _unity;
    final clamped = visualValue.clamp(0.0, widget.maxValue).toDouble();

    if (clamped <= unity) {
      final ampMin = math.pow(10.0, dbMin / 20.0).toDouble();
      final curved = (unity <= 0.0) ? 0.0 : (clamped / unity).clamp(0.0, 1.0);
      final normalizedAmp = curved * curved;
      final amp = ampMin + ((1.0 - ampMin) * normalizedAmp);
      final db = 20.0 * math.log(amp) / math.ln10;
      return _dbToGainUi(db);
    }

    return clamped;
  }

  void _commitImmediateGain(double nextValue) {
    final current = widget.value.clamp(0.0, widget.maxValue).toDouble();
    final next = nextValue.clamp(0.0, widget.maxValue).toDouble();
    if ((current - next).abs() < 1.0e-6) return;
    widget.onChangeStart(current);
    setState(() {});
    widget.onChanged(next);
    widget.onChangeEnd(next);
  }

  Future<void> _showGainAdjustDialog() async {
    var dbValue = _gainToDb(widget.value).clamp(_dbMin, _dbMax).toDouble();
    final controller = TextEditingController(text: _formatGainDbInput(dbValue));
    final submitted = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF252A32),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          title: Text(
            L10n.translate(dialogContext, 'Set gain'),
            style: const TextStyle(color: Colors.white),
          ),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              void setDb(double next) {
                dbValue = next.clamp(_dbMin, _dbMax).toDouble();
                controller.text = _formatGainDbInput(dbValue);
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                setDialogState(() {});
              }

              double? parseDbInput(String text) {
                final normalized = text
                    .trim()
                    .replaceAll(',', '.')
                    .replaceAll('+', '');
                if (normalized.isEmpty || normalized == '-') return null;
                final parsed = double.tryParse(normalized);
                if (parsed == null || !parsed.isFinite) return null;
                return parsed.clamp(_dbMin, _dbMax).toDouble();
              }

              final dbText = _gainReadoutText(_dbToGainUi(dbValue));
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: L10n.translate(context, 'Decrease gain'),
                        onPressed: () => setDb(dbValue - 0.25),
                        icon: const Icon(Icons.remove, color: Colors.white),
                      ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+\-.,]'),
                            ),
                          ],
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            suffixText: 'dB',
                            suffixStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                            helperText: '-60 to +6 dB',
                            helperStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.60),
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.08),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.42),
                              ),
                            ),
                            isDense: true,
                          ),
                          onChanged: (text) {
                            final parsed = parseDbInput(text);
                            if (parsed == null) return;
                            dbValue = parsed;
                            setDialogState(() {});
                          },
                          onSubmitted: (text) {
                            Navigator.of(dialogContext).pop(parseDbInput(text));
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: L10n.translate(context, 'Increase gain'),
                        onPressed: () => setDb(dbValue + 0.25),
                        icon: const Icon(Icons.add, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    dbText,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.76),
                      fontSize: 13,
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(L10n.translate(dialogContext, 'Cancel')),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  controller.text.trim().isEmpty
                      ? null
                      : double.tryParse(
                          controller.text
                              .trim()
                              .replaceAll(',', '.')
                              .replaceAll('+', ''),
                        )?.clamp(_dbMin, _dbMax).toDouble(),
                );
              },
              child: Text(L10n.translate(dialogContext, 'Apply')),
            ),
          ],
        );
      },
    );
    if (submitted == null || !submitted.isFinite) return;
    _commitImmediateGain(_dbToGainUi(submitted));
  }

  String _formatGainDbInput(double db) {
    final clamped = db.clamp(_dbMin, _dbMax).toDouble();
    if (clamped.abs() < 0.05) return '0';
    return clamped.toStringAsFixed(1);
  }

  String _gainReadoutText(double gainUi) {
    final db = _gainToDb(gainUi);
    if (db.isInfinite) return '–∞ dB';
    return db > 0
        ? '+${db.toStringAsFixed(1)} dB'
        : '${db.toStringAsFixed(1)} dB';
  }

  @override
  Widget build(BuildContext context) {
    const sliderThumbRadius = 11.0;
    final labelWidth = widget.showStepButtons ? 42.0 : null;
    final readoutWidth = widget.showStepButtons ? 64.0 : 50.0;
    final visualValue = _gainUiToVisualValue(widget.value);
    final gainReadoutText = _gainReadoutText(widget.value);
    final labelText = widget.label ?? L10n.translate(context, 'Gain');
    final unityVisualValue = _gainUiToVisualValue(_unity);
    final unityFraction = widget.maxValue <= 0.0
        ? 0.0
        : (unityVisualValue / widget.maxValue).clamp(0.0, 1.0).toDouble();

    Widget stepButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
    }) {
      return _SliderStepButton(icon: icon, tooltip: tooltip, onTap: onTap);
    }

    Widget valueButton({double width = 50.0}) {
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showGainAdjustDialog();
          });
        },
        child: SizedBox(
          width: width,
          height: 28,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                gainReadoutText,
                maxLines: 1,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),
      );
    }

    Widget sliderTrack() {
      final activeTrackColor = widget.stackedLayout
          ? const Color(0xFFC2D0DF)
          : widget.trackColor;
      final inactiveTrackColor = widget.stackedLayout
          ? const Color(0xFF596574)
          : widget.inactiveTrackColor;
      final markerColor = widget.stackedLayout
          ? Colors.white.withValues(alpha: 0.36)
          : Colors.white.withValues(alpha: 0.24);
      final thumbColor = widget.stackedLayout
          ? const Color(0xFFF4F7FB)
          : widget.thumbColor;
      final trackBody = SizedBox(
        height: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SliderDefaultMarkerPainter(
                    positionFraction: unityFraction,
                    color: markerColor,
                    edgeInset: sliderThumbRadius + 1,
                  ),
                ),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: sliderThumbRadius,
                ),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: activeTrackColor,
                inactiveTrackColor: inactiveTrackColor,
                thumbColor: thumbColor,
              ),
              child: DesktopScrollableSlider(
                value: visualValue.clamp(0.0, widget.maxValue),
                min: 0.0,
                max: widget.maxValue,
                divisions: 300,
                onChangeStart: (v) {
                  widget.onChangeStart(_visualValueToGainUi(v));
                },
                onChanged: (v) {
                  setState(() {});
                  widget.onChanged(_visualValueToGainUi(v));
                },
                onChangeEnd: (v) {
                  widget.onChangeEnd(_visualValueToGainUi(v));
                },
              ),
            ),
          ],
        ),
      );
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: widget.onLongPress,
        onDoubleTap: () {
          _commitImmediateGain(_unity); // reset to unity gain (0 dB)
        },
        child: trackBody,
      );
    }

    if (widget.stackedLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  labelText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              stepButton(
                icon: Icons.remove,
                tooltip: L10n.translate(context, 'Decrease gain'),
                onTap: () => _commitImmediateGain(
                  _dbToGainUi(_gainToDb(widget.value) - 0.25),
                ),
              ),
              const SizedBox(width: 6),
              valueButton(width: 64.0),
              const SizedBox(width: 6),
              stepButton(
                icon: Icons.add,
                tooltip: L10n.translate(context, 'Increase gain'),
                onTap: () => _commitImmediateGain(
                  _dbToGainUi(_gainToDb(widget.value) + 0.25),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          sliderTrack(),
        ],
      );
    }

    return Row(
      children: [
        if (widget.showLabel)
          SizedBox(
            width: labelWidth,
            child: Text(
              L10n.translate(context, 'Gain:'),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        if (widget.showLabel) const SizedBox(width: 6),
        if (widget.showStepButtons) ...[
          stepButton(
            icon: Icons.remove,
            tooltip: L10n.translate(context, 'Decrease gain'),
            onTap: () => _commitImmediateGain(
              _dbToGainUi(_gainToDb(widget.value) - 0.25),
            ),
          ),
          const SizedBox(width: 3),
        ],

        // ⭐ FIX: Make slider stretch horizontally
        Expanded(child: sliderTrack()),
        if (widget.showStepButtons) ...[
          const SizedBox(width: 3),
          stepButton(
            icon: Icons.add,
            tooltip: L10n.translate(context, 'Increase gain'),
            onTap: () => _commitImmediateGain(
              _dbToGainUi(_gainToDb(widget.value) + 0.25),
            ),
          ),
        ],

        SizedBox(width: widget.showStepButtons ? 6 : 4),
        valueButton(width: readoutWidth),

        // Text("+19 dB", style: TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}

class _HeaderGainMeterSliderPainter extends CustomPainter {
  const _HeaderGainMeterSliderPainter({
    required this.frame,
    required this.visualInset,
    required this.trackHeight,
  });

  final MeterFrame frame;
  final double visualInset;
  final double trackHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final trackWidth = math.max(1.0, size.width - (visualInset * 2.0));
    final trackRect = Rect.fromLTWH(
      visualInset,
      (size.height - trackHeight) / 2.0,
      trackWidth,
      trackHeight,
    );
    final trackRRect = RRect.fromRectAndRadius(
      trackRect,
      const Radius.circular(99),
    );

    canvas.drawRRect(
      trackRRect,
      Paint()..color = const Color(0xFF151C25).withValues(alpha: 0.92),
    );

    const laneGap = 1.0;
    final laneHeight = math.max(1.0, (trackHeight - laneGap) / 2.0);
    final topLane = Rect.fromLTWH(
      trackRect.left,
      trackRect.top,
      trackRect.width,
      laneHeight,
    );
    final bottomLane = Rect.fromLTWH(
      trackRect.left,
      topLane.bottom + laneGap,
      trackRect.width,
      laneHeight,
    );

    void drawLane({
      required Rect laneRect,
      required double rms,
      required double peak,
    }) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(laneRect, const Radius.circular(99)),
        Paint()..color = Colors.white.withValues(alpha: 0.045),
      );

      final rmsWidth = laneRect.width * DbfsMeterVisuals.ampToUnit(rms);
      final peakWidth = laneRect.width * DbfsMeterVisuals.ampToUnit(peak);
      if (rmsWidth > 0.5) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              laneRect.left,
              laneRect.top,
              rmsWidth,
              laneRect.height,
            ),
            const Radius.circular(99),
          ),
          Paint()
            ..shader = DbfsMeterVisuals.horizontalGradient(
              opacity: 0.86,
            ).createShader(laneRect),
        );
      }
      if (peakWidth > rmsWidth + 0.5) {
        canvas.drawRect(
          Rect.fromLTWH(
            laneRect.left + rmsWidth,
            laneRect.top,
            peakWidth - rmsWidth,
            laneRect.height,
          ),
          Paint()
            ..shader = DbfsMeterVisuals.horizontalGradient(
              opacity: 0.30,
            ).createShader(laneRect),
        );
      }
      if (peakWidth > 0.5) {
        final peakDb = DbfsMeterVisuals.ampToDbfs(peak);
        final x = (laneRect.left + peakWidth)
            .clamp(laneRect.left, laneRect.right)
            .toDouble();
        canvas.drawLine(
          Offset(x, laneRect.top),
          Offset(x, laneRect.bottom),
          Paint()
            ..color = DbfsMeterVisuals.statusColor(
              peakDb,
            ).withValues(alpha: 0.72)
            ..strokeWidth = 1.0,
        );
      }
    }

    canvas.save();
    canvas.clipRRect(trackRRect);
    drawLane(laneRect: topLane, rms: frame.rmsL, peak: frame.peakL);
    drawLane(laneRect: bottomLane, rms: frame.rmsR, peak: frame.peakR);

    final unityX = trackRect.left + (trackRect.width * (2.0 / 3.0));
    canvas.drawLine(
      Offset(unityX, trackRect.top + 1.0),
      Offset(unityX, trackRect.bottom - 1.0),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..strokeWidth = 1.0,
    );
    canvas.restore();

    canvas.drawRRect(
      trackRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withValues(alpha: 0.14),
    );
  }

  @override
  bool shouldRepaint(covariant _HeaderGainMeterSliderPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.visualInset != visualInset ||
        oldDelegate.trackHeight != trackHeight;
  }
}

class MiniStereoMeter extends StatelessWidget {
  final MeterFrame frame;
  final double width;
  final double height;

  const MiniStereoMeter({
    super.key,
    required this.frame,
    this.width = 10,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _MiniStereoMeterPainter(frame),
    );
  }
}

class _MiniStereoMeterPainter extends CustomPainter {
  final MeterFrame f;
  _MiniStereoMeterPainter(this.f);

  @override
  void paint(Canvas c, Size s) {
    final bg = Paint()..color = const Color(0xFF0F1419).withOpacity(0.9);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.12);

    final fill = Paint()..color = Colors.white.withOpacity(0.75);
    final rms = Paint()..color = Colors.white.withOpacity(0.25);

    final r = RRect.fromRectAndRadius(
      Offset.zero & s,
      const Radius.circular(3),
    );
    c.drawRRect(r, bg);
    c.drawRRect(r, border);

    final halfW = s.width / 2;

    double barH(double v) => v.clamp(0.0, 1.0).toDouble() * s.height;

    // L
    final rmsLH = barH(f.rmsL);
    final peakLH = barH(f.peakL);
    c.drawRect(Rect.fromLTWH(0, s.height - rmsLH, halfW, rmsLH), rms);
    c.drawRect(Rect.fromLTWH(0, s.height - peakLH, halfW, peakLH), fill);

    // R
    final rmsRH = barH(f.rmsR);
    final peakRH = barH(f.peakR);
    c.drawRect(Rect.fromLTWH(halfW, s.height - rmsRH, halfW, rmsRH), rms);
    c.drawRect(Rect.fromLTWH(halfW, s.height - peakRH, halfW, peakRH), fill);

    // clip dot (latched)
    // if (f.clip) {
    //   final p = Paint()..color = const Color(0xFFFF4A4A);
    //   c.drawCircle(Offset(s.width - 3.5, 3.5), 2.3, p);
    // }
  }

  @override
  bool shouldRepaint(covariant _MiniStereoMeterPainter old) => old.f != f;
}

class MiniStereoMeterPro extends StatelessWidget {
  final MeterFrame frame;
  final double width;
  final double height;

  const MiniStereoMeterPro({
    super.key,
    required this.frame,
    this.width = 12,
    // NOTE: this height is only safe because parent expanded height is fixed
    // Depends on kExpandedRowHeight being at least 240
    this.height = 82,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _MiniStereoMeterProPainter(frame),
    );
  }
}

class _MiniStereoMeterProPainter extends CustomPainter {
  final MeterFrame f;
  _MiniStereoMeterProPainter(this.f);

  @override
  void paint(Canvas c, Size s) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & s,
      const Radius.circular(0), // const Radius.circular(5),
    );

    // --- Background slot (always visible) ---
    final bg = Paint()..color = const Color(0xFF1A2230).withValues(alpha: 0.95);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.10);

    c.drawRRect(r, bg);
    c.drawRRect(r, border);

    // --- Tick lines (subtle scale) ---
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    for (final db in const [-36.0, -24.0, -15.0, -10.0, -6.0, -3.0]) {
      final y = s.height * (1.0 - DbfsMeterVisuals.dbfsToUnit(db));
      c.drawLine(Offset(1, y), Offset(s.width - 1, y), tick);
    }

    // --- Lane gap between L/R ---
    const laneGap = 0.5;
    final laneW = (s.width - laneGap) / 2;

    // X positions
    final leftX = 0.0;
    final rightX = laneW + laneGap;

    void drawLane({
      required double left,
      required double rms,
      required double peak,
    }) {
      final laneRect = Rect.fromLTWH(left, 0, laneW, s.height);
      c.drawRect(
        laneRect,
        Paint()..color = Colors.white.withValues(alpha: 0.04),
      );

      final rmsHeight = s.height * DbfsMeterVisuals.ampToUnit(rms);
      final peakHeight = s.height * DbfsMeterVisuals.ampToUnit(peak);
      if (rmsHeight > 0.0) {
        c.drawRect(
          Rect.fromLTWH(
            laneRect.left,
            laneRect.bottom - rmsHeight,
            laneRect.width,
            rmsHeight,
          ),
          Paint()
            ..shader = DbfsMeterVisuals.verticalGradient(
              opacity: 0.94,
            ).createShader(laneRect),
        );
      }
      if (peakHeight > rmsHeight) {
        c.drawRect(
          Rect.fromLTWH(
            laneRect.left,
            laneRect.bottom - peakHeight,
            laneRect.width,
            peakHeight - rmsHeight,
          ),
          Paint()
            ..shader = DbfsMeterVisuals.verticalGradient(
              opacity: 0.32,
            ).createShader(laneRect),
        );
      }
      if (peakHeight > 0.5) {
        final peakDb = DbfsMeterVisuals.ampToDbfs(peak);
        final peakPaint = Paint()
          ..color = DbfsMeterVisuals.statusColor(peakDb)
          ..strokeWidth = 1.0;
        final peakY = (laneRect.bottom - peakHeight)
            .clamp(laneRect.top, laneRect.bottom)
            .toDouble();
        c.drawLine(
          Offset(laneRect.left, peakY),
          Offset(laneRect.right, peakY),
          peakPaint,
        );
      }
    }

    drawLane(left: leftX, rms: f.rmsL, peak: f.peakL);
    drawLane(left: rightX, rms: f.rmsR, peak: f.peakR);

    // --- Clip indicator ---
    // if (f.clip) {
    //   final clipPaint = Paint()..color = const Color(0xFFFF4A4A);
    //   c.drawCircle(
    //     Offset(s.width - 3.8, 3.8),
    //     2.4,
    //     clipPaint,
    //   );
    // }
  }

  @override
  bool shouldRepaint(covariant _MiniStereoMeterProPainter old) => old.f != f;
}

class HeaderDbfsReadoutPro extends StatelessWidget {
  final String label;
  final Color color;
  final double width;
  final double height;

  const HeaderDbfsReadoutPro({
    super.key,
    required this.label,
    required this.color,
    this.width = 72,
    this.height = 30,
  });

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = width < 64.0 ? 5.0 : 8.0;
    return SizedBox(
      width: width,
      height: height,
      child: Align(
        alignment: Alignment.topCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.17),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.46)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 3,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.12,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hollow fingertip ring shown when marquee selection arms on long-press.
class _SelectionArmRing extends StatefulWidget {
  final double radius;
  final double peakScale;

  const _SelectionArmRing({
    super.key,
    required this.radius,
    required this.peakScale,
  });

  @override
  State<_SelectionArmRing> createState() => _SelectionArmRingState();
}

class _SelectionArmRingState extends State<_SelectionArmRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    // One-shot pulse: rest → peak (radius 38) → rest, same shape as 1.0→1.15→1.0.
    final peak = widget.peakScale;
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: peak,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: peak,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 45,
      ),
    ]).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) {
        return Transform.scale(scale: _scale.value, child: child);
      },
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(
              color: const Color.fromRGBO(107, 184, 255, 0.95),
              width: 3.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(43, 136, 222, 0.35),
                blurRadius: 12,
                spreadRadius: 0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
