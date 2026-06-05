import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'dart:math' as math;
import 'package:mixroom/models/models.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mixroom/widgets/effects_panel.dart';
import 'package:mixroom/widgets/sample_browser_panel.dart';
import 'package:mixroom/helpers/app_haptics.dart';
import 'package:mixroom/helpers/automation_clip_clone_helper.dart';
import 'package:mixroom/helpers/dbfs_meter_visuals.dart';
import 'package:mixroom/helpers/glass_ui_tokens.dart';
import 'package:mixroom/helpers/halo.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/helpers/mix_change_highlighter.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:uuid/uuid.dart';

class _QuantizePreset {
  final int divisionsPerBar;
  final String label;

  const _QuantizePreset({
    required this.divisionsPerBar,
    required this.label,
  });
}

class _SampleDropPlacement {
  final int row;
  final double startMs;
  final double endMs;
  final bool allowed;

  const _SampleDropPlacement({
    required this.row,
    required this.startMs,
    required this.endMs,
    required this.allowed,
  });
}

class _PendingPaintPaste {
  final int row;
  final double startMs;

  const _PendingPaintPaste({
    required this.row,
    required this.startMs,
  });
}

class _AddRowBubbleTailPainter extends CustomPainter {
  _AddRowBubbleTailPainter({
    required this.centerX,
    required this.color,
  });

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
  final _AutomationValueKind kind;
  final String signature;
  final bool clipRelative;
  final List<AutomationPoint> points;

  const _AutomationPointsClipboardEntry({
    required this.kind,
    required this.signature,
    required this.clipRelative,
    required this.points,
  });

  bool isCompatibleWith(
    _AutomationValueFormatter formatter, {
    required bool expectClipRelative,
  }) {
    if (kind != formatter.valueKind) return false;
    if (clipRelative != expectClipRelative) return false;
    if (kind == _AutomationValueKind.generic) {
      return signature == formatter.signature;
    }
    return true;
  }
}

class _AutomationAreaClipboardEntry {
  final _AutomationValueKind kind;
  final String signature;
  final double durationMs;
  final List<AutomationPoint> relativePoints;

  const _AutomationAreaClipboardEntry({
    required this.kind,
    required this.signature,
    required this.durationMs,
    required this.relativePoints,
  });

  bool isCompatibleWith(_AutomationValueFormatter formatter) {
    if (kind != formatter.valueKind) return false;
    if (kind == _AutomationValueKind.generic) {
      return signature == formatter.signature;
    }
    return true;
  }
}

enum _TimelineTool {
  pencil,
  stretch,
  paint,
  cut,
  delete,
}

enum _InlineClipControlKind {
  settings,
}

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
const Color _kTimelineUtilityBlue = Color(0xFF2B88DE);
const Color _kTimelineUtilityBlueDark = Color(0xFF1F69BA);
const Color _kTimelineClipAudio = Color(0xFF6A7A89);
const Color _kTimelineClipAudioSelected = Color(0xFFA36D35);
const Color _kTimelineClipAudioBorder = Color(0xFF8191A0);
const Color _kTimelineClipAudioSelectedBorder = Color(0xFFFFA04A);
const Color _kTimelineClipMidi = _kTimelineClipAudio;
const Color _kTimelineClipMidiSelected = _kTimelineClipAudioSelected;
const Color _kTimelineExpandedPanelSurface = Color.fromRGBO(98, 104, 110, 0.82);
const Color _kTimelineExpandedPanelSurfaceFx =
    Color.fromRGBO(92, 99, 106, 0.96);
const Color _kTimelineExpandedPanelBorder = Color.fromRGBO(255, 255, 255, 0.09);
const Color _kTimelineExpandedInnerSurface =
    Color.fromRGBO(244, 244, 244, 0.08);
const Color _kTimelineExpandedInnerSurfaceFx = Color(0xFF5E656D);

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

  const _EditorLayoutSpec({
    required this.bottomInteractionPadding,
  });

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

class AudioCanvasTimeline extends StatefulWidget {
  final AudioCanvasTimelineController? controller;
  final List<TimelineRow> rows;
  final List<AudioTrack> clips;
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
          int row, String targetId, List<AutomationClipSnapshot> clips)
      setAutomationClipsForTarget;
  final void Function(int row, String targetId, List<AutomationPoint> oldPoints,
      List<AutomationPoint> newPoints)? onAutomationTargetCommit;
  final void Function(
    int row,
    String targetId,
    List<AutomationClipSnapshot> oldClips,
    List<AutomationClipSnapshot> newClips,
  )? onAutomationClipsCommit;
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
  final Future<void> Function(int row) onInsertRowAbove;
  final Future<void> Function(int row) onInsertRowBelow;
  final Future<void> Function(int row)? onInsertInstrumentLaneAbove;
  final Future<void> Function(int row)? onInsertInstrumentLaneBelow;
  final Future<void> Function(int row)? onChangeInstrumentLane;
  final Future<void> Function(int row) onDeleteRow;
  final Future<void> Function(int fromIndex, int toIndex) onMoveRow;
  final Future<void> Function(int row, String name) onRenameRow;
  final Future<void> Function(int row, int iconId) onSetRowIcon;
  final Future<void> Function(int clipIndex, double newStartMs, int newRowIndex)
      onMoveClipCommit;
  final Future<void> Function(List<TimelineClipMoveRequest> moves)?
      onMoveClipsCommit;
  final void Function(int clipIndex, double trimStartMs, double trimEndMs,
      {double? newStartMs}) onTrimClip;
  final void Function(
    int clipIndex,
    double trimStartMs,
    double trimEndMs,
    double oldTrimStart,
    double oldTrimEnd,
    double oldOffset, {
    double? newStartMs,
  }) onTrimClipCommit;
  final ValueListenable<Duration> transportClockListenable;
  final void Function(double ms) onScrubRequested;
  final bool isPlaying;
  final Duration maxDuration;
  final double bpm;
  final int beatsPerBar;
  final double height;
  final bool isRecording;
  final int? recordingRowIndex;
  final double recordingStartMs;
  final List<double> recordingPeaks;
  final bool recordingInProgress; // sent from above if user is recording
  final int selectedClipIndex;
  final List<int> selectedClipIndices;

  // === Row FX callbacks ===
  final Future<List<String>> Function(int row) getRowEffects;
  final Future<List<String>> Function(int row) getRowEffectIds;
  final Future<bool> Function(int row, int effectIndex) getRowEffectBypassState;
  final Future<void> Function(int row, String pathOrName) insertRowEffect;
  final Future<void> Function(
          int row, int effectIndex, String name, bool applyingPreset)
      removeRowEffect;
  final Future<void> Function(int row, int from, int to) reorderRowEffects;
  final Future<void> Function(int row, int effectIndex, bool bypass)
      setRowEffectBypassed;
  final Future<List<Map<String, dynamic>>> Function(int row, int effectIndex)
      getRowPluginParameters;
  final Future<void> Function(
          int row, int effectIndex, String paramId, dynamic value)
      setRowEffectParam;
  final Future<List<Map<String, dynamic>>> Function() scanPlugins;
  final Future<bool> Function(int row, int effectIndex)? openTrackPluginEditor;
  final Future<void> Function(int row, List<Map<String, dynamic>> points)
      setTrackAutomationPoints;
  final void Function(int row, List<AutomationPoint> oldPoints,
      List<AutomationPoint> newPoints)? onAutomationCommit;
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
  final Future<void> Function(int clipIndex)? onOpenClipWarpEditor;
  final void Function(int clipIndex, double newTimelineDurationMs,
      {double? newStartMs}) onStretchClip;
  final Future<void> Function(int clipIndex) onStretchClipCommit;
  final Future<void> Function(int clipIndex, String label)? onRenameClip;
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
  final Future<void> Function(List<int> clipIndices)? onDeleteClips;
  final Future<void> Function(int clipIndex, double cutTimeMs)? onCutClipAt;
  final Future<void> Function(List<int> clipIndices)? onGlueClips;
  final void Function(int clipIndex)? onOpenMidiClip;
  final Future<void> Function(int row, double timeMs)?
      onCreateMidiClipInInstrumentLane;
  final Future<void> Function(int clipIndex)? onStemSeparation;
  final void Function(List<int> selectedClipIndices, int primaryClipIndex)?
      onSelectionChanged;
  final void Function(int loopStartMs, int loopEndMs)? onLoopRegionChanged;
  final void Function(bool enabled)? onLoopToggle;
  final void Function(int row, int effectIndex, String paramId,
      dynamic oldValue, dynamic newValue)? onPluginParamCommit;
  final void Function(RowEffectsSnapshot before, RowEffectsSnapshot after)?
      onPresetCommit;
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

  final String mode; // "Basic" or "Pro"

  const AudioCanvasTimeline({
    Key? key,
    this.controller,
    required this.rows,
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
    required this.onInsertRowAbove,
    required this.onInsertRowBelow,
    this.onInsertInstrumentLaneAbove,
    this.onInsertInstrumentLaneBelow,
    this.onChangeInstrumentLane,
    required this.onDeleteRow,
    required this.onMoveRow,
    required this.onRenameRow,
    required this.onSetRowIcon,
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
    this.height = 520,
    required this.isRecording,
    required this.recordingRowIndex,
    required this.recordingStartMs,
    required this.recordingPeaks,
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
    this.onOpenClipWarpEditor,
    required this.onStretchClip,
    required this.onStretchClipCommit,
    this.onRenameClip,
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
    this.onDeleteClips,
    this.onCutClipAt,
    this.onGlueClips,
    this.onOpenMidiClip,
    this.onCreateMidiClipInInstrumentLane,
    this.onStemSeparation,
    this.onSelectionChanged,
    this.onLoopRegionChanged,
    this.onLoopToggle,
    required this.mode,
    this.onPluginParamCommit,
    this.onPresetCommit,
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
  }) : super(key: key);
  @override
  State<AudioCanvasTimeline> createState() => _AudioCanvasTimelineState();
}

class AudioCanvasTimelineController {
  void Function(int row, {int tab})? _ensureRowExpanded;
  VoidCallback? _collapseExpandedRows;
  VoidCallback? _copySelectedClips;
  VoidCallback? _pasteCopiedClipsAfterSelection;

  void _bind({
    required void Function(int row, {int tab}) ensureRowExpanded,
    required VoidCallback collapseExpandedRows,
    required VoidCallback copySelectedClips,
    required VoidCallback pasteCopiedClipsAfterSelection,
  }) {
    _ensureRowExpanded = ensureRowExpanded;
    _collapseExpandedRows = collapseExpandedRows;
    _copySelectedClips = copySelectedClips;
    _pasteCopiedClipsAfterSelection = pasteCopiedClipsAfterSelection;
  }

  void _unbind({
    required void Function(int row, {int tab}) ensureRowExpanded,
    required VoidCallback collapseExpandedRows,
    required VoidCallback copySelectedClips,
    required VoidCallback pasteCopiedClipsAfterSelection,
  }) {
    if (identical(_ensureRowExpanded, ensureRowExpanded)) {
      _ensureRowExpanded = null;
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
  }

  void ensureRowExpanded(int row, {int tab = 0}) {
    _ensureRowExpanded?.call(row, tab: tab);
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
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 3,
              ),
              color: const Color.fromRGBO(244, 244, 244, 0.10),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: false,
                maxLength: widget.maxLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _close(_controller.text.trim()),
                style: const TextStyle(
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
  static const double kExpandedRowHeight = (kRowHeight * 3) +
      40.0; // keep extra headroom to avoid expanded-tab vertical overflow
  // Effects panel min height should be driven by left header content.
  static const double _kHeaderTabButtonHeight = 34.0;
  static const double _kHeaderTabGap = 6.0;
  static const double _kHeaderMeterHeight = 82.0;
  static const double _kHeaderDbfsReadoutHeight = 30.0;
  static const double _kHeaderDbfsReadoutGap = 6.0;
  static const double _kHeaderBottomPadding = 24.0;
  static const double _kHeaderTabsMinHeight = 12.0 + // top spacers
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
  // Match Volume tab baseline, but never go below measured header needs.
  static const double _kEffectsPanelMinHeight =
      (_kHeaderTabsMinHeight > kExpandedRowHeight)
          ? _kHeaderTabsMinHeight
          : kExpandedRowHeight;
  static const double kHeaderFooterHeight = 44.0;
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
      bottomInteractionPadding: kBottomInteractionPadding);

  static const double kHeaderWidth = 80.0;
  static const double kTimelineUnderlayLeft = 44.0;
  static const double kRulerHeight = 40.0;
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
  static const double _kMacWheelZoomSensitivity = 0.0025;
  static const double _kMinTimelinePixelsPerMs = 0.001;
  static const double _kMaxTimelinePixelsPerMs = 1.0;
  double _pixelsPerMs = 0.1; // Initial zoom level
  double _scrollOffsetMs = 0.0;
  int _selectedClipIndex = -1;
  final Set<int> _selectedClipIndices = <int>{};
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
  final Map<int, double> _dragGroupStartMs = <int, double>{};
  final Map<int, int> _dragGroupStartRows = <int, int>{};
  Offset? _dragStartLocalOffset; // Local position where drag started
  Offset?
      _dragStartGlobalOffset; // === FIX ===: Added for total vertical displacement tracking

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
  _AutomationClipClipboardEntry? _automationClipClipboard;
  static _AutomationPointsClipboardEntry? _automationPointsClipboard;
  static _AutomationAreaClipboardEntry? _automationAreaClipboard;

  bool _pendingDrag = false;
  bool _pendingDragStartedFromSelection = false;
  bool _tentativeClipSelectionActive = false;
  bool _suppressNextTimelineTapAfterTentativeSelectionCommit = false;
  bool _suppressNextTimelineTapAfterInstrumentLaneCreate = false;
  int? _pendingTapSelectionClipIndex;
  double? _pendingTapSelectionPopupMs;
  final Set<int> _activeTimelinePointers = <int>{};

  // Paste popup state
  bool _showPastePopup = false;
  int? _pasteRow;
  double? _pasteMs;
  _TimelineGestureSelectionSnapshot? _singleTouchSelectionSnapshot;
  double? _clipPopupMs;
  int? _inlineClipControlIndex;
  _InlineClipControlKind? _inlineClipControlKind;
  double? _inlineClipGainStart;
  double? _inlineClipPitchStart;
  _TimelineTool _activeTool = _TimelineTool.pencil;
  Offset? _toolMenuGlobalPos;

  bool _selectionBoxActive = false;
  Offset? _selectionBoxStart;
  Offset? _selectionBoxCurrent;
  int? _pendingSelectionBoxPointer;
  Offset? _pendingSelectionBoxStart;
  bool _suppressNextTimelineTapAfterSelectionBox = false;
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

  bool _magnetEnabled = false;
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

  double? _gainDragStart;
  double? _panDragStart;

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
    _QuantizePreset(divisionsPerBar: 6, label: '1/6'),
    _QuantizePreset(divisionsPerBar: 8, label: '1/8'),
    _QuantizePreset(divisionsPerBar: 16, label: '1/16'),
  ];
  int? _headerPointer;
  int? _headerRow;
  Offset? _headerDownPos;
  bool _headerEligible = false;
  bool _headerMoved = false;
  bool _headerMenuOpened = false;
  Timer? _deadZoneHoldTimer;
  int? _deadZonePointer;
  int? _deadZoneRow;
  Offset? _deadZoneDownGlobalPos;
  bool _deadZoneMoved = false;
  bool _suppressNextTimelineTapAfterDeadZoneHold = false;
  bool _magnetMenuShownFromHold = false;
  Offset? _magnetDownGlobalPos;
  final GlobalKey _externalSampleDropTargetKey = GlobalKey();
  int? _externalSampleDropRow;
  double? _externalSampleDropStartMs;
  double? _externalSampleDropEndMs;
  bool _externalSampleDropAllowed = true;
  bool _externalSampleDragInsideTimeline = false;
  List<_TimelineAutomationClipVisual> _timelineAutomationClipVisualCache =
      const <_TimelineAutomationClipVisual>[];

  void _notifySnapSettingsChanged() {
    widget.onSnapSettingsChanged
        ?.call(_magnetEnabled, _quantizeDivisionsPerBar);
  }

  bool get _hasPasteClipboard =>
      widget.hasCopiedClip || _automationClipClipboard != null;

  bool get _hasActiveAutomationClipDrag =>
      _automationClipDragRow != null &&
      _automationClipDragTargetId != null &&
      _automationClipDragId != null &&
      _automationClipDragMode != null;

  bool get _timelineHasMultiTouch => _activeTimelinePointers.length > 1;

  bool _isInstrumentLane(int row) {
    return row >= 0 &&
        row < widget.rows.length &&
        widget.rows[row].isInstrumentLane;
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
    final rawMs =
        (_scrollOffsetMs + local.dx / _pixelsPerMs).clamp(0.0, double.infinity);
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

  Future<void> _startClipLoopPreviewAtLocal(
    int pointer,
    Offset local,
  ) async {
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

  void _beginSelectionBoxAt(Offset localPosition) {
    _cancelDeadZoneHoldTimer();
    _resetDeadZonePointerState();
    _clearPendingClipTapState();
    _clearPendingAutomationClipSelection();
    _clearAutomationClipMenu();
    _selectionBoxActive = true;
    _selectionBoxStart = localPosition;
    _selectionBoxCurrent = localPosition;
    _clipPopupMs = null;
    _showPastePopup = false;
    _pasteRow = null;
    _pasteMs = null;
    _highlightedSegmentRow = null;
    _highlightedSegmentStartMs = null;
    _highlightedSegmentEndMs = null;
    _updateSelectionFromRect(
      Rect.fromLTWH(localPosition.dx, localPosition.dy, 0, 0),
    );
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

  void _onTimelinePointerDown(PointerDownEvent event) {
    _suppressNextTimelineTapAfterDeadZoneHold = false;
    _activeTimelinePointers.add(event.pointer);
    final keyboard = HardwareKeyboard.instance;
    final desktopSelectionModifierPressed =
        Platform.isMacOS ? keyboard.isMetaPressed : keyboard.isControlPressed;
    final desktopPrimaryPointer = _isDesktopPrimaryTimelinePointer(event);
    if (_isDesktopSecondaryTimelinePointer(event)) {
      if (keyboard.isAltPressed) {
        unawaited(
          _startClipLoopPreviewAtLocal(event.pointer, event.localPosition),
        );
        return;
      }
      if (_canShowInstrumentLaneRegionMenuAt(event.localPosition)) {
        unawaited(_showInstrumentLaneRegionMenuAt(event.localPosition));
        return;
      }
      _deleteStrokeActive = true;
      _rightDeleteStrokePointer = event.pointer;
      _deleteStrokeClipObjectIds.clear();
      _deleteClipAtLocal(event.localPosition);
      return;
    }
    final desktopBoxSelectionShortcut = desktopPrimaryPointer &&
        desktopSelectionModifierPressed &&
        _canStartSelectionBoxAt(
          event.localPosition,
          allowStartingOverClip: true,
        );
    if (desktopBoxSelectionShortcut) {
      setState(() {
        _clearPendingSelectionBox();
        _beginSelectionBoxAt(event.localPosition);
      });
      return;
    }
    if (desktopPrimaryPointer &&
        _canStartSelectionBoxAt(
          event.localPosition,
          allowStartingOverClip: false,
        )) {
      _pendingSelectionBoxPointer = event.pointer;
      _pendingSelectionBoxStart = event.localPosition;
      return;
    }
    final isPrimaryLikePointer = event.kind != PointerDeviceKind.mouse ||
        event.buttons == kPrimaryMouseButton;
    final deadZoneRow = _deadZoneRowAtLocalPosition(event.localPosition);
    final canArmDeadZoneHold = isPrimaryLikePointer &&
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
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    if (event is! PointerScrollEvent) return;

    final keyboard = HardwareKeyboard.instance;
    final cmdPressed = keyboard.isMetaPressed;
    final shiftPressed = keyboard.isShiftPressed;
    if (!cmdPressed && !shiftPressed) return;

    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (PointerSignalEvent resolved) {
        if (resolved is! PointerScrollEvent) return;
        if (cmdPressed) {
          _handleMacTimelineZoom(resolved);
          return;
        }
        if (shiftPressed) {
          _handleMacTimelineHorizontalScroll(resolved);
        }
      },
    );
  }

  void _handleMacTimelineZoom(PointerScrollEvent event) {
    final rawDelta = event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (rawDelta == 0) return;

    bool didZoom = false;
    setState(() {
      final zoomFactor = math.exp(-rawDelta * _kMacWheelZoomSensitivity);
      final newPixelsPerMs = (_pixelsPerMs * zoomFactor)
          .clamp(_kMinTimelinePixelsPerMs, _kMaxTimelinePixelsPerMs);
      if ((newPixelsPerMs - _pixelsPerMs).abs() < 0.0001) return;

      final focalPointPx = event.localPosition.dx;
      final focalPointMs = _scrollOffsetMs + focalPointPx / _pixelsPerMs;
      _scrollOffsetMs = focalPointMs - (focalPointPx / newPixelsPerMs);
      _pixelsPerMs = newPixelsPerMs;
      _clampScroll();
      didZoom = true;

      if (!PlatformCapabilities.current.isDesktop) {
        final playheadPx = _getPlayheadPx(context);
        widget.onScrubRequested(_scrollOffsetMs + playheadPx / _pixelsPerMs);
      }
    });

    if (didZoom) {
      widget.onTutorialTimelineZoomed?.call();
    }
  }

  void _handleMacTimelineHorizontalScroll(PointerScrollEvent event) {
    final rawDelta = event.scrollDelta.dx.abs() >= event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (rawDelta == 0) return;

    setState(() {
      _scrollOffsetMs += rawDelta / _pixelsPerMs;
      _clampScroll();
      if (!PlatformCapabilities.current.isDesktop) {
        final playheadPx = _getPlayheadPx(context);
        widget.onScrubRequested(_scrollOffsetMs + playheadPx / _pixelsPerMs);
      }
    });

    widget.onTutorialTimelineScrolled?.call();
  }

  void _onTimelinePointerUp(PointerUpEvent event) {
    _onDeadZonePointerUp(event);
    _activeTimelinePointers.remove(event.pointer);
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
        _selectionBoxActive = false;
        _selectionBoxStart = null;
        _selectionBoxCurrent = null;
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
        _selectionBoxActive = false;
        _selectionBoxStart = null;
        _selectionBoxCurrent = null;
      });
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
    final msPerBeat = 60000 / widget.bpm;
    return msPerBeat * widget.beatsPerBar;
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

  Future<void> _showQuantizeMenu() async {
    final globalPos = _magnetDownGlobalPos;
    if (globalPos == null || !mounted) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<int>(
      context: context,
      color: kMixroomGlassDropdownMenuColor,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      position: RelativeRect.fromLTRB(
        globalPos.dx + 8,
        globalPos.dy + 10,
        overlay.size.width - globalPos.dx,
        overlay.size.height - globalPos.dy,
      ),
      items: _quantizePresets.map((preset) {
        final isSelected = preset.divisionsPerBar == _quantizeDivisionsPerBar;
        return PopupMenuItem<int>(
          value: preset.divisionsPerBar,
          height: 36,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  preset.label,
                  style: TextStyle(
                    color: isSelected
                        ? _kTimelineShellText
                        : _kTimelineShellMutedText,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check, size: 16, color: _kTimelineWarmBorder),
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

  Future<void> _showToolMenu() async {
    final globalPos = _toolMenuGlobalPos;
    if (globalPos == null || !mounted) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<_TimelineTool>(
      context: context,
      color: kMixroomGlassDropdownMenuColor,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      position: RelativeRect.fromLTRB(
        globalPos.dx + 8,
        globalPos.dy + 10,
        overlay.size.width - globalPos.dx,
        overlay.size.height - globalPos.dy,
      ),
      items: _TimelineTool.values.map((tool) {
        final isSelected = tool == _activeTool;
        return PopupMenuItem<_TimelineTool>(
          value: tool,
          height: 38,
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
                  style: TextStyle(
                    color: isSelected
                        ? _kTimelineShellText
                        : _kTimelineShellMutedText,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check, size: 16, color: _kTimelineWarmBorder),
            ],
          ),
        );
      }).toList(),
    );

    if (selected == null || !mounted || selected == _activeTool) return;
    setState(() {
      _activeTool = selected;
      _clearPendingSelectionBox();
      _selectionBoxActive = false;
      _selectionBoxStart = null;
      _selectionBoxCurrent = null;
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
  }

  List<int> _activeSelectedClipIndices() {
    if (_selectedClipIndices.isNotEmpty) {
      final list = _selectedClipIndices
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

  void _clearClipSelection() {
    _commitInlineClipControlIfNeeded();
    _clearInlineClipControlState();
    _clearAutomationClipSelection();
    _selectedClipIndex = -1;
    _selectedClipIndices.clear();
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
    _clipPopupMs = null;
    if (emitSelectionChanged) {
      _emitSelectionChanged();
    }
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
      selectedAutomationClipByLane:
          Map<String, String>.from(_selectedAutomationClipByLane),
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

  void _revealAutomationRangeInViewport(
    double startMs,
    double endMs,
  ) {
    final viewportWidth = _getViewportWidth(context);
    if (viewportWidth <= 0 || _pixelsPerMs <= 0) return;
    final visibleStartMs = _scrollOffsetMs;
    final visibleEndMs = _scrollOffsetMs + (viewportWidth / _pixelsPerMs);
    final marginMs = 28.0 / _pixelsPerMs;
    final alreadyVisible = startMs >= (visibleStartMs + marginMs) &&
        endMs <= (visibleEndMs - marginMs);
    if (alreadyVisible) return;

    final centerMs = (startMs + endMs) / 2.0;
    _scrollOffsetMs = centerMs - ((viewportWidth / _pixelsPerMs) / 2.0);
    _clampScroll();
  }

  double _pendingClipDragActivationSlop() {
    final draggedIndex = _draggedClipIndex;
    final draggingGroup = draggedIndex != null &&
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
    }
  }

  int? _rowForLocalY(double localY) {
    if (_rowCount <= 0) return null;
    double currentY = 0;
    for (int i = 0; i < _rowCount; i++) {
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
    double y = 0.0;
    for (int i = 0; i < row; i++) {
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
      _TimelineAutomationClipVisual clipVisual) {
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
      for (int i = 0; i < _rowCount; i++) {
        _rowExpanded[i] = i == row;
      }
      _expandedTab[row] = _normalizeExpandedTab(2);
      _automationEditorRow = row;
      _automationEditorTargetId = resolvedTargetId;
    });
    for (int i = 0; i < oldExpanded.length && i < _rowExpanded.length; i++) {
      if (oldExpanded[i] != _rowExpanded[i]) {
        widget.onRowExpansionChanged?.call(i, _rowExpanded[i]);
        widget.onTutorialRowExpansionChanged?.call(i, _rowExpanded[i]);
      }
    }
    widget.onRowTabSelected?.call(row, 2);
    widget.onTutorialRowTabSelected?.call(row, 2);
    _triggerTimelineHalos(
      <String>[
        'row:$row:automation_tab',
        ...haloKeys,
      ],
    );
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
        for (int i = 0; i < _rowCount; i++) {
          _rowExpanded[i] = i == row;
        }
      }
      _applyExpandedTabStateForRow(row, normalizedTab);
    });
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

  void _setAutomationEditorFor(
    int row,
    String targetId,
  ) {
    if (row < 0 || row >= _rowCount) return;
    final resolvedTargetId = _resolveAutomationTabTargetId(row, targetId);
    _clearAutomationClipMenu();
    widget.setSelectedAutomationTargetId(row, resolvedTargetId);
    _selectedRowIndex = row;
    widget.onSelectRow(row);
    for (int i = 0; i < _rowCount; i++) {
      _rowExpanded[i] = i == row;
    }
    _expandedTab[row] = _normalizeExpandedTab(2);
    _automationEditorRow = row;
    _automationEditorTargetId = resolvedTargetId;
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
      final next = before.map((clip) {
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
      }).toList(growable: false);
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
        kRowHeight +
        _kTimelineAutomationLaneInset +
        (clampedLane * (laneHeight + _kTimelineAutomationLaneGap));
  }

  int _timelineAutomationLaneIndexAtLocalY(int row, double localY) {
    return 0;
  }

  double _expandedPanelHeightForRow(int row) {
    if (row < 0 || row >= _rowCount || !_rowExpanded[row]) return 0.0;
    if (_isAutomationEditorOpenForRow(row)) {
      return math.max(kExpandedRowHeight, _kEffectsPanelMinHeight);
    }
    return _isFixedHeightExpandedTab(_expandedTab[row])
        ? math.max(kExpandedRowHeight, _kEffectsPanelMinHeight)
        : _effectsPanelHeights[row];
  }

  double _rowBlockHeightForIndex(int row) {
    return kRowHeight + _expandedPanelHeightForRow(row);
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
    final dt = (now.difference(lastUpdate).inMicroseconds / 1000000.0)
        .clamp(0.0, 0.25);

    double heldDb = prevDb;
    if (!currentPeakDb.isFinite || currentPeakDb <= -120.0) {
      heldDb = double.negativeInfinity;
      _headerPeakHoldFreezeUntilByRowId[rowId] = now;
    } else if (currentPeakDb >= prevDb || !prevDb.isFinite) {
      heldDb = currentPeakDb;
      _headerPeakHoldFreezeUntilByRowId[rowId] =
          now.add(_kHeaderPeakHoldFreeze);
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
    final isMaster = normalized.startsWith('master:') ||
        normalized.startsWith('masterfxid:');
    if (!isMaster || _rowCount <= 0) {
      return _defaultAutomationClipRowForSourceRow(row);
    }
    final occupiedRows = widget.clips
        .map((clip) => clip.rowIndex)
        .where((rowIndex) => rowIndex >= 0 && rowIndex < _rowCount)
        .toSet();
    for (int candidate = 0; candidate < _rowCount; candidate++) {
      if (!occupiedRows.contains(candidate)) {
        return candidate;
      }
    }
    return 0;
  }

  bool _isLocalYInMainTrackLane(int row, double localY) {
    final rowTop = _rowTopForIndex(row);
    return localY >= rowTop && localY < rowTop + kRowHeight;
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

  Color _automationColorForTarget(
    String targetId, {
    bool isOrphan = false,
  }) {
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
    return Rect.fromLTWH(
      visual.rect.left + 4.0,
      top,
      width,
      height,
    );
  }

  bool _automationClipLeftTrimHandleHit(
    _TimelineAutomationClipVisual visual,
    Offset localPos,
  ) {
    final hitWidth = math.min(
      math.max(12.0, visual.rect.width * 0.18),
      20.0,
    );
    return localPos.dx >= visual.rect.left &&
        localPos.dx <= visual.rect.left + hitWidth;
  }

  bool _automationClipRightTrimHandleHit(
    _TimelineAutomationClipVisual visual,
    Offset localPos,
  ) {
    final hitWidth = math.min(
      math.max(12.0, visual.rect.width * 0.18),
      20.0,
    );
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

  int? _clipIndexAtRowAndMs(int row, double timeMs) {
    int? topIndex;
    for (int i = 0; i < widget.clips.length; i++) {
      final clip = widget.clips[i];
      if (clip.rowIndex != row) continue;
      final startMs = widget.getStartMs(clip);
      final endMs = startMs + widget.getTimelineDurationMs(clip);
      if (timeMs >= startMs && timeMs <= endMs) {
        topIndex = topIndex == null ? i : math.max(topIndex, i);
      }
    }
    return topIndex;
  }

  void _clearExternalSampleDropPreview() {
    _externalSampleDragInsideTimeline = false;
    if (_externalSampleDropRow == null &&
        _externalSampleDropStartMs == null &&
        _externalSampleDropEndMs == null) {
      return;
    }
    setState(() {
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

  _SampleDropPlacement? _sampleDropPlacementForGlobalOffset(
    Offset globalOffset, {
    SampleDragData? data,
  }) {
    final targetContext = _externalSampleDropTargetKey.currentContext;
    if (targetContext == null) return null;
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
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
    return _SampleDropPlacement(
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
    final placement =
        _sampleDropPlacementForGlobalOffset(globalOffset, data: data);
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

  void _updateSelectionFromRect(Rect rect) {
    final selected = <int>{};
    for (int i = 0; i < widget.clips.length; i++) {
      final clipRect = _getClipRect(i);
      if (clipRect == null) continue;
      if (rect.overlaps(clipRect)) {
        selected.add(i);
      }
    }
    _selectedClipIndices
      ..clear()
      ..addAll(selected);
    if (_selectedClipIndices.isEmpty) {
      _selectedClipIndex = -1;
      _clipPopupMs = null;
      _emitSelectionChanged();
      return;
    }
    _selectedClipIndex = _selectedClipIndices.reduce((a, b) => a > b ? a : b);
    _clipPopupMs = null;
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
        final rowCompare =
            widget.clips[a].rowIndex.compareTo(widget.clips[b].rowIndex);
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
    unawaited(
      widget.onPasteClipAt(row, pasteStartMs),
    );
  }

  bool _canPasteCopiedClipAtRow(int row) {
    if (!widget.hasCopiedClip) return false;
    return widget.canPasteClipAtRow?.call(row) ?? true;
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
      final selectedDuration =
          widget.getTimelineDurationMs(widget.clips[_selectedClipIndex]);
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
      for (int i = widget.clips.length - 1; i >= 0; i--) {
        final clip = widget.clips[i];
        if (clip.rowIndex != paintRow) continue;
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
    _magnetDownGlobalPos = details.globalPosition;
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
    final expandedOffset = _rowTopForIndex(row) +
        kRowHeight +
        _automationTimelineLaneHeightForRow(row);
    final usableHeight = kExpandedRowHeight - 24;
    return expandedOffset + 12 + (1 - v) * usableHeight;
  }

  final ScrollController _verticalScrollController = ScrollController();
  double _verticalScrollOffset = 0.0;

  double get _maxDurationMs => widget.maxDuration.inMilliseconds.toDouble();
  int get _rowCount => widget.rows.length;
  double get _currentPlayheadMs =>
      widget.transportClockListenable.value.inMilliseconds.toDouble();

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(
      ensureRowExpanded: ensureRowExpanded,
      collapseExpandedRows: collapseExpandedRows,
      copySelectedClips: _copySelectedClips,
      pasteCopiedClipsAfterSelection: _pasteCopiedClipsAfterSelection,
    );
    _syncRowUiState();
    _verticalScrollController.addListener(() {
      setState(() {
        _verticalScrollOffset = _verticalScrollController.offset;
      });
    });
    widget.registerRowFxRefresher?.call(_refreshRowFx);
    widget.registerRowFxPlaybackRefresher?.call(_refreshRowFxPlayback);
    _syncSelectionFromWidgetConfig();
    _notifySnapSettingsChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emitSelectionChanged();
    });
  }

  @override
  void didUpdateWidget(covariant AudioCanvasTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._unbind(
        ensureRowExpanded: ensureRowExpanded,
        collapseExpandedRows: collapseExpandedRows,
        copySelectedClips: _copySelectedClips,
        pasteCopiedClipsAfterSelection: _pasteCopiedClipsAfterSelection,
      );
      widget.controller?._bind(
        ensureRowExpanded: ensureRowExpanded,
        collapseExpandedRows: collapseExpandedRows,
        copySelectedClips: _copySelectedClips,
        pasteCopiedClipsAfterSelection: _pasteCopiedClipsAfterSelection,
      );
    }
    if (oldWidget.clips.length != widget.clips.length) {
      _syncSelectionAfterClipTopologyChange();
      if (_pendingPaintPastes.isNotEmpty) {
        final remainingPending = <_PendingPaintPaste>[];
        for (final pending in _pendingPaintPastes) {
          var resolved = false;
          for (int i = widget.clips.length - 1; i >= 0; i--) {
            final clip = widget.clips[i];
            if (clip.rowIndex != pending.row) continue;
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
            oldWidget.selectedClipIndices, widget.selectedClipIndices)) {
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
    if (_automationEditorRow != null &&
        (_automationEditorRow! < 0 || _automationEditorRow! >= _rowCount)) {
      _automationEditorRow = null;
      _automationEditorTargetId = null;
    }
    final liveRowIds = widget.rows.map((row) => row.rowId).toSet();
    _headerPeakHoldDbByRowId
        .removeWhere((rowId, _) => !liveRowIds.contains(rowId));
    _headerPeakHoldLastUpdateByRowId
        .removeWhere((rowId, _) => !liveRowIds.contains(rowId));
    _headerPeakHoldFreezeUntilByRowId
        .removeWhere((rowId, _) => !liveRowIds.contains(rowId));
    _rowEffectParameterRevealers
        .removeWhere((rowId, _) => !liveRowIds.contains(rowId));
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
    widget.controller?._unbind(
      ensureRowExpanded: ensureRowExpanded,
      collapseExpandedRows: collapseExpandedRows,
      copySelectedClips: _copySelectedClips,
      pasteCopiedClipsAfterSelection: _pasteCopiedClipsAfterSelection,
    );
    _verticalScrollController.dispose();
    super.dispose();
  }

  bool _isHoldEligibleInHeader(Offset localPos) {
    // Keep M/S interactions fully isolated from row-header tap/hold logic.
    const double msPillLeft = 44.0;
    final bool inMuteSoloPill = localPos.dx >= msPillLeft;
    return !inMuteSoloPill;
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
      _showRowMenu(row);
    });
  }

  void _handleHeaderPointerDown(int row, PointerDownEvent event) {
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
    if (_headerPointer != e.pointer) return;
    final row = _headerRow;
    final bool shouldToggleRow =
        row != null && _headerEligible && !_headerMoved && !_headerMenuOpened;

    _cancelHeaderHoldTimer();
    _resetHeaderPointerState();

    if (shouldToggleRow) {
      final int tappedRow = row;
      _handleHeaderTapSelectionAndExpand(tappedRow);
    }
  }

  void _onHeaderPointerCancel(PointerCancelEvent e) {
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
        if (_automationEditorRow != null && _automationEditorRow != tappedRow) {
          _automationEditorRow = null;
          _automationEditorTargetId = null;
        }
        _selectedRowIndex = tappedRow;
        widget.onSelectRow(tappedRow);
        for (int i = 0; i < _rowExpanded.length; i++) {
          _rowExpanded[i] = false;
        }
        return;
      }

      final shouldExpand = !_rowExpanded[tappedRow];
      if (!shouldExpand && _automationEditorRow == tappedRow) {
        _automationEditorRow = null;
        _automationEditorTargetId = null;
      }
      for (int i = 0; i < _rowExpanded.length; i++) {
        _rowExpanded[i] = shouldExpand && i == tappedRow;
      }
    });

    for (int i = 0; i < oldExpanded.length && i < _rowExpanded.length; i++) {
      if (oldExpanded[i] != _rowExpanded[i]) {
        widget.onToggleExpanded(i);
        widget.onRowExpansionChanged?.call(i, _rowExpanded[i]);
        widget.onTutorialRowExpansionChanged?.call(i, _rowExpanded[i]);
      }
    }
  }

  void ensureRowExpanded(int row, {int tab = 0}) {
    if (row < 0 || row >= _rowCount) return;
    final normalizedTab = _normalizeExpandedTab(tab);
    final oldExpanded = List<bool>.from(_rowExpanded);
    setState(() {
      _selectedRowIndex = row;
      widget.onSelectRow(row);
      for (int i = 0; i < _rowCount; i++) {
        _rowExpanded[i] = i == row;
      }
      _expandedTab[row] = normalizedTab;
      if (normalizedTab != 2) {
        _automationEditorRow = null;
        _automationEditorTargetId = null;
      }
    });
    for (int i = 0; i < oldExpanded.length && i < _rowExpanded.length; i++) {
      if (oldExpanded[i] != _rowExpanded[i]) {
        widget.onRowExpansionChanged?.call(i, _rowExpanded[i]);
        widget.onTutorialRowExpansionChanged?.call(i, _rowExpanded[i]);
      }
    }
    widget.onRowTabSelected?.call(row, normalizedTab);
    widget.onTutorialRowTabSelected?.call(row, normalizedTab);
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
    });
    for (int i = 0; i < oldExpanded.length && i < _rowExpanded.length; i++) {
      if (oldExpanded[i] != _rowExpanded[i]) {
        widget.onRowExpansionChanged?.call(i, _rowExpanded[i]);
        widget.onTutorialRowExpansionChanged?.call(i, _rowExpanded[i]);
      }
    }
  }

  void _syncRowUiState() {
    while (_rowExpanded.length < _rowCount) {
      _rowExpanded.add(false);
      _expandedTab.add(_normalizeExpandedTab(0));
      _effectsPanelHeights.add(_kEffectsPanelMinHeight);
    }
    if (_rowExpanded.length > _rowCount) {
      _rowExpanded.removeRange(_rowCount, _rowExpanded.length);
      _expandedTab.removeRange(_rowCount, _expandedTab.length);
      _effectsPanelHeights.removeRange(_rowCount, _effectsPanelHeights.length);
    }
    if (_selectedRowIndex >= _rowCount) {
      _selectedRowIndex = _rowCount == 0 ? -1 : _rowCount - 1;
    }
    _extraAutomationTimelineLanesByRow
        .removeWhere((row, _) => row < 0 || row >= _rowCount);
    _collapsedAutomationTimelineByRow
        .removeWhere((row, _) => row < 0 || row >= _rowCount);
    _automationLaneFocusByRow
        .removeWhere((row, _) => row < 0 || row >= _rowCount);
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
      oldExtraAutomationLanesById[id] =
          math.max(0, _extraAutomationTimelineLanesByRow[i] ?? 0);
      oldCollapsedAutomationById[id] =
          _collapsedAutomationTimelineByRow[i] == true;
      oldAutomationLaneFocusById[id] =
          math.max(0, _automationLaneFocusByRow[i] ?? 0);
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
            .map(
                (r) => oldEffectsHeightById[r.rowId] ?? _kEffectsPanelMinHeight)
            .toList(growable: false),
      );
    _extraAutomationTimelineLanesByRow
      ..clear()
      ..addEntries(
        widget.rows.asMap().entries.where((entry) {
          final rowId = entry.value.rowId;
          return (oldExtraAutomationLanesById[rowId] ?? 0) > 0;
        }).map((entry) {
          final rowId = entry.value.rowId;
          return MapEntry(entry.key, oldExtraAutomationLanesById[rowId] ?? 0);
        }),
      );
    _collapsedAutomationTimelineByRow
      ..clear()
      ..addEntries(
        widget.rows.asMap().entries.where((entry) {
          final rowId = entry.value.rowId;
          return oldCollapsedAutomationById[rowId] == true;
        }).map((entry) {
          final rowId = entry.value.rowId;
          return MapEntry(entry.key, oldCollapsedAutomationById[rowId] == true);
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
    return MediaQuery.of(context).size.width - kHeaderWidth;
  }

  double _getPlayheadPx(BuildContext context) {
    if (!PlatformCapabilities.current.isDesktop) {
      return (MediaQuery.of(context).size.width / 2) - kHeaderWidth;
    }
    return (_currentPlayheadMs - _scrollOffsetMs) * _pixelsPerMs;
  }

  double _desktopLeftDeadZoneMs(BuildContext context) {
    final deadZonePx = (MediaQuery.of(context).size.width / 2) - kHeaderWidth;
    return math.max(0.0, deadZonePx) / _pixelsPerMs;
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
    double total = 0.0;
    for (int i = 0; i < _rowCount; i++) {
      total += _rowBlockHeightForIndex(i);
    }
    return total;
  }

  double get _timelinePaintHeight => math.max(_totalTimelineHeight, kRowHeight);
  double get _scrollContentHeight =>
      _timelinePaintHeight +
      kHeaderFooterHeight +
      _kAddRowPillHeight +
      _kAddRowSectionGap +
      _editorLayoutSpec.bottomInteractionPadding +
      _kExtraAddRowBottomPadding;

  void _recalculateRowYPositions() {
    _rowYPositions.clear();

    double y = 0;
    for (int i = 0; i < _rowCount; i++) {
      _rowYPositions.add(y);
      y += _rowBlockHeightForIndex(i);
    }
  }

  double _automationLaneLocalY(double volume, double laneHeight) {
    const verticalPadding = 12.0;
    final usable = laneHeight - verticalPadding * 2;
    return verticalPadding + (1 - volume) * usable;
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
        clipsOverride ?? widget.getAutomationClipsForTarget(row, targetId));
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
    final points = clip.points
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
    final points = absolutePoints
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
    final selectedIndex =
        _selectedAutomationClipIndexFor(row, targetId, current);
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
    setState(() {
      _setAutomationEditorFor(row, targetId);
    });
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
    return <AutomationPoint>[
      AutomationPoint(x: 0.0, volume: value),
    ];
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

  int _suggestAutomationLaneForClip(
    int row,
    double startMs,
    double lengthMs,
  ) {
    return 0;
  }

  Future<void> _revealRowAutomationTarget(int row, String targetId) async {
    if (row < 0 || row >= _rowCount) return;
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
      final haloKeys = <String>[
        'row:$row:volume_tab',
        'row:$row:mixer',
      ];
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
    await widget.onRevealAutomationTarget?.call(
      clipVisual.row,
      clipVisual.targetId,
    );
    if (!mounted) return;
    await _revealRowAutomationTarget(clipVisual.row, clipVisual.targetId);
  }

  void _copyAutomationClipToClipboard(
      _TimelineAutomationClipVisual clipVisual) {
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

  void _deleteSelectedAutomationClipForTarget(
    int row,
    String targetId,
  ) {
    final before = _cloneAutomationClips(
      widget.getAutomationClipsForTarget(row, targetId),
    );
    final selectedIndex =
        _selectedAutomationClipIndexFor(row, targetId, before);
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
        .map(
          (p) => AutomationPoint(
            x: p.x - startDeltaMs,
            volume: p.volume,
          ),
        )
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
    _setSelectedAutomationClipFor(
      row,
      targetId,
      clip.id,
      lane: clip.lane,
    );
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
      if (_magnetEnabled) {
        nextStart = _segmentStartMsForTap(nextStart);
      }
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
      if (_magnetEnabled) {
        nextEndMs = _segmentStartMsForTap(nextEndMs);
      }
      final minEndMs = origin.startMs + _kAutomationClipMinLengthMs;
      nextEndMs = nextEndMs.clamp(minEndMs, _maxDurationMs).toDouble();
      final nextLength = (nextEndMs - origin.startMs)
          .clamp(_kAutomationClipMinLengthMs, _maxDurationMs)
          .toDouble();
      current[index] = origin.copyWith(lengthMs: nextLength);
    } else if (mode == 'trim_start') {
      var nextStart = origin.startMs + deltaMs;
      if (_magnetEnabled) {
        nextStart = _segmentStartMsForTap(nextStart);
      }
      final maxStart =
          origin.startMs + origin.lengthMs - _kAutomationClipMinLengthMs;
      nextStart = nextStart.clamp(0.0, maxStart).toDouble();
      var nextLength = (origin.startMs + origin.lengthMs) - nextStart;
      nextLength = nextLength
          .clamp(_kAutomationClipMinLengthMs, _maxDurationMs - nextStart)
          .toDouble();
      final startDelta = nextStart - origin.startMs;
      final shiftedPoints =
          _shiftAutomationClipPoints(origin.points, startDelta);
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
      final py = _automationLaneLocalY(p.volume, laneHeight);

      if ((pos - Offset(px, py)).distance < 20) {
        // compute the offset between finger and point Y
        final p = lane[i];
        final py = _automationLaneLocalY(p.volume, laneHeight);
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

  void _automationPanUpdate(int row, Offset pos) {
    if (_interactionMode != 'automation') return;
    if (_automationDragIndex == null) return;
    if (!_isAutomationLaneTabForRow(row)) return;
    final targetId = _activeAutomationTargetIdForRow(row);

    final points =
        List<AutomationPoint>.from(_activeAutomationPointsForRow(row));
    final p = points[_automationDragIndex!];

    // ===== 1. Convert finger X → absolute timeMs =====
    final fingerX = pos.dx;
    double newTimeMs = (fingerX / _pixelsPerMs) + _scrollOffsetMs;
    if (_magnetEnabled) {
      // quantize to a bar marker first, and then to a clip start/end
      newTimeMs = _quantizeMs(newTimeMs);
      for (final clip in widget.clips) {
        if (clip.rowIndex != row) continue;

        final trimStart = widget.getTrimStartMs(clip) + widget.getStartMs(clip);
        final trimEnd =
            widget.getStartMs(clip) + widget.getTimelineDurationMs(clip);

        if ((newTimeMs - trimStart).abs() < 20) newTimeMs = trimStart;
        if ((newTimeMs - trimEnd).abs() < 20) newTimeMs = trimEnd;
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
    final normalized =
        1 - ((effectiveFingerY - verticalPadding) / usableHeight);
    p.volume = normalized.clamp(0.0, 1.0);

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
      final playheadPx = _getPlayheadPx(context);
      widget.onScrubRequested(_scrollOffsetMs + playheadPx / _pixelsPerMs);
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
    return Opacity(
      opacity: onTap == null ? 0.45 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap == null ? null : () => unawaited(onTap()),
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 9 : 10,
              vertical: compact ? 5 : 6,
            ),
            decoration: BoxDecoration(
              color: enabled
                  ? activeColor.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.075),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: enabled
                    ? Colors.white.withValues(alpha: 0.30)
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
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: compact ? 11 : 12,
                  color: color,
                ),
                SizedBox(width: compact ? 4 : 5),
                Text(
                  L10n.translate(context, 'Normalize'),
                  style: TextStyle(
                    color: color,
                    fontSize: compact ? 10 : 10.8,
                    fontWeight: FontWeight.w700,
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
      _inlineClipControlIndex = clipIndex;
      _inlineClipControlKind = _InlineClipControlKind.settings;
      _inlineClipGainStart = widget.clips[clipIndex].gain.clamp(0.0, 3.0);
      _inlineClipPitchStart =
          widget.clips[clipIndex].pitchSemitones.clamp(-12.0, 12.0);
    });
  }

  Widget _buildInlineClipControlOverlay(
      double viewportWidth, double viewportHeight) {
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

    final minLeft = kHeaderWidth + 6.0;
    final maxLeft =
        math.max(minLeft, kHeaderWidth + viewportWidth - cardWidth - 6.0);
    final anchorX = kHeaderWidth + rect.left + (rect.width / 2);
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
      topCandidate =
          availableAbove >= availableBelow ? preferredAbove : preferredBelow;
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
                              context, 'Quick level and pitch adjustments'),
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
                                      color:
                                          Colors.white.withValues(alpha: 0.07),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.10),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(7),
                                      splashColor:
                                          Colors.white.withValues(alpha: 0.12),
                                      highlightColor:
                                          Colors.white.withValues(alpha: 0.05),
                                      onTap: () {
                                        final next = (clip.pitchSemitones - 0.5)
                                            .clamp(-12.0, 12.0);
                                        clip.pitchSemitones = next;
                                        unawaited(widget.setClipPitch(
                                            clipIndex, next));
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
                                  child: Slider(
                                    value:
                                        clip.pitchSemitones.clamp(-12.0, 12.0),
                                    min: -12.0,
                                    max: 12.0,
                                    divisions: 48,
                                    label:
                                        '${clip.pitchSemitones >= 0 ? '+' : ''}${clip.pitchSemitones.toStringAsFixed(1)}st',
                                    onChanged: (v) {
                                      final next = v.clamp(-12.0, 12.0);
                                      clip.pitchSemitones = next;
                                      unawaited(
                                          widget.setClipPitch(clipIndex, next));
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
                                      color:
                                          Colors.white.withValues(alpha: 0.07),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.10),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(7),
                                      splashColor:
                                          Colors.white.withValues(alpha: 0.12),
                                      highlightColor:
                                          Colors.white.withValues(alpha: 0.05),
                                      onTap: () {
                                        final next = (clip.pitchSemitones + 0.5)
                                            .clamp(-12.0, 12.0);
                                        clip.pitchSemitones = next;
                                        unawaited(widget.setClipPitch(
                                            clipIndex, next));
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
                            : L10n.translate(context,
                                'MIDI clips follow project BPM automatically.'),
                        compact: compactSheet,
                        child: Text(
                          L10n.translate(
                              context, 'No extra tempo mode is needed here.'),
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
                            : L10n.translate(context,
                                'Choose how this audio clip follows project BPM'),
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
                                      await widget
                                          .onDisableClipTempoFollow(clipIndex);
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                  _buildInlineClipModeOption(
                                    label: L10n.translate(context, 'Resample'),
                                    selected: clip.stretchToProjectTempo &&
                                        !clip.tempoStretchPreservePitch,
                                    selectedColor: const Color(0xFF8A919D),
                                    compact: compactSheet,
                                    onTap: () async {
                                      await widget
                                          .onAdjustClipToTempo(clipIndex);
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                  _buildInlineClipModeOption(
                                    label: L10n.translate(context, 'Stretch'),
                                    selected: clip.stretchToProjectTempo &&
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
                                if (widget.onOpenClipWarpEditor != null &&
                                    PlatformCapabilities.current.isDesktop)
                                  _buildInlineClipActionPill(
                                    icon: Icons.blur_linear_rounded,
                                    label: L10n.translate(context, 'Warp Pro'),
                                    color: const Color(0xFF78D9FF),
                                    compact: compactSheet,
                                    onTap: () async {
                                      _closeInlineClipControl();
                                      await widget
                                          .onOpenClipWarpEditor!(clipIndex);
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                if (widget.onStemSeparation != null)
                                  _buildInlineClipActionPill(
                                    icon: Icons.library_music_outlined,
                                    label:
                                        L10n.translate(context, 'Split vocals'),
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
                                      await widget
                                          .onCreateSamplerFromClip!(clipIndex);
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
                leading:
                    const Icon(Icons.drag_indicator, color: Color(0xFF2AAE9F)),
                title: Text(
                  L10n.translate(ctx, 'Stretch To Tempo (Keep Pitch)'),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  L10n.translate(
                      ctx, 'Stretch mode is shown with teal clip handles.'),
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
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Center(
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
    if (tooltip == null || tooltip.trim().isEmpty) {
      return action;
    }
    return Tooltip(
      message: tooltip,
      child: action,
    );
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
    final clipInTimelineY = visual.rect.bottom >= _verticalScrollOffset &&
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
    final minLeft = kHeaderWidth + 4.0;
    final maxLeft =
        math.max(minLeft, kHeaderWidth + viewportWidth - popupWidth - 4.0);
    final left = (kHeaderWidth + anchorPx - (popupWidth / 2.0))
        .clamp(minLeft, maxLeft)
        .toDouble();
    final minTop = _verticalScrollOffset + 2.0;
    final maxTop = math.max(
      minTop,
      _verticalScrollOffset + viewportHeight - popupHeight - 2.0,
    );
    final preferredAbove = visual.rect.top - popupHeight - 4.0;
    final preferredBelow = visual.rect.bottom + 4.0;
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
          left: kHeaderWidth + rect.left,
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
    final singleSelectionIndex =
        hasSingleSelection ? selectedIndices.first : _selectedClipIndex;
    final canSplitAtPlayhead = hasSingleSelection &&
        _canCutSelectedClipAtPlayhead(singleSelectionIndex);
    final canGlueSelection =
        selectedIndices.length >= 2 && widget.onGlueClips != null;
    final canCreateSampler = hasSingleSelection &&
        widget.onCreateSamplerFromClip != null &&
        singleSelectionIndex >= 0 &&
        singleSelectionIndex < widget.clips.length &&
        !widget.clips[singleSelectionIndex].isMidi;
    final canReplaceSamplerSource = hasSingleSelection &&
        widget.onReplaceSamplerSource != null &&
        singleSelectionIndex >= 0 &&
        singleSelectionIndex < widget.clips.length &&
        widget.clips[singleSelectionIndex].isMidi &&
        (widget.canReplaceSamplerSource?.call(singleSelectionIndex) ?? false);
    Rect? selectionRect;
    for (final index in selectedIndices) {
      final rect = _getClipRect(index);
      if (rect == null) continue;
      selectionRect = selectionRect?.expandToInclude(rect) ?? rect;
    }
    final bool visible = selectionRect != null &&
        selectedIndices.isNotEmpty &&
        !_isUserInteracting &&
        !_selectionBoxActive;
    final int popupActionCount =
        (hasSingleSelection ? (canSplitAtPlayhead ? 5 : 4) : 3) +
            (canGlueSelection ? 1 : 0) +
            (canCreateSampler ? 1 : 0) +
            (canReplaceSamplerSource ? 1 : 0);
    final double popupWidth = math.min(
      popupActionCount * 38.0,
      math.max(84.0, viewportWidth - 8),
    );
    const double popupHeight = 32;
    double left = kHeaderWidth;
    double top = -100;

    if (visible) {
      final clipInTimelineX =
          selectionRect.right >= 0 && selectionRect.left <= viewportWidth;
      final clipInTimelineY = selectionRect.bottom >= _verticalScrollOffset &&
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
        final minLeft = kHeaderWidth + 4.0;
        final maxLeft =
            math.max(minLeft, kHeaderWidth + viewportWidth - popupWidth - 4.0);
        left = (kHeaderWidth + anchorPx - (popupWidth / 2))
            .clamp(minLeft, maxLeft)
            .toDouble();

        final minTop = _verticalScrollOffset + 2.0;
        final maxTop = math.max(
          minTop,
          _verticalScrollOffset + viewportHeight - popupHeight - 2.0,
        );
        final preferredAbove = selectionRect.top - popupHeight - 4.0;
        final preferredBelow = selectionRect.bottom + 4.0;
        if (preferredAbove >= minTop) {
          top = preferredAbove;
        } else if (preferredBelow <= maxTop) {
          top = preferredBelow;
        } else {
          top = preferredAbove.clamp(minTop, maxTop).toDouble();
        }
      }
    }

    final popupChildren = <Widget>[
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
    ];
    if (hasSingleSelection) {
      popupChildren.addAll(<Widget>[
        Container(width: 1, height: 16, color: Colors.white24),
        Expanded(
          child: _buildClipPopupAction(
            icon: Icons.tune,
            color: Colors.white,
            onTap: () => _openClipSettingsPanel(singleSelectionIndex),
            tooltip: L10n.translate(context, 'Clip settings'),
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

    const double popupHeight = 32;
    final double popupWidth = showClearButton ? 116 : 70;

    double left = kHeaderWidth;
    double top = -100; // offscreen when hidden

    if (visible) {
      if (_rowCount == 0) {
        left = kHeaderWidth;
        top = -100;
      } else {
        double popupAnchorMs = _pasteMs!;
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

          left = kHeaderWidth + px - popupWidth / 2;
          left = left.clamp(
              kHeaderWidth, kHeaderWidth + viewportWidth - popupWidth);

          top = rowTop - popupHeight - 4;
          if (top < 0) top = 0;
        } else {
          // Offscreen in X → hide visually
          left = kHeaderWidth;
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: Container(
            width: popupWidth,
            height: popupHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF000000).withOpacity(0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: L10n.translate(context, 'Place clone'),
                  icon: const Icon(Icons.content_paste,
                      size: 18, color: Colors.white),
                  onPressed: () {
                    if (_pasteRow != null && _pasteMs != null) {
                      if (_automationClipClipboard != null &&
                          _canPasteAutomationClipAt(_pasteRow!)) {
                        _pasteAutomationClipAt(_pasteRow!, _pasteMs!);
                      } else if (_canPasteCopiedClipAtRow(_pasteRow!)) {
                        unawaited(widget.onPasteClipAt(_pasteRow!, _pasteMs!));
                      }
                    }
                    _clearPastePopup();
                  },
                ),
                if (showClearButton) ...[
                  Container(width: 1, height: 18, color: Colors.white24),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: L10n.translate(context, 'Clear clipboard'),
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Color(0xFFFFA4A4)),
                    onPressed: () {
                      _clearClipboard();
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                                L10n.translate(context, 'Clipboard cleared')),
                            duration: Duration(milliseconds: 1200),
                          ),
                        );
                      _clearPastePopup();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _editorLayoutSpec = _EditorLayoutSpec.fromSize(MediaQuery.of(context).size);
    final viewportWidth = _getViewportWidth(context);
    final timelineUnderlayWidth =
        math.max(0.0, kHeaderWidth - kTimelineUnderlayLeft);
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
    final timelineAutomationClipVisuals = _timelineAutomationClipVisualCache;
    final staticTrackHeaders = Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: SizedBox(
        width: _AudioCanvasTimelineState.kHeaderWidth,
        child: RepaintBoundary(
          child: SizedBox(
            height: _scrollContentHeight,
            child: _buildTrackHeadersContent(
              _AudioCanvasTimelineState.kHeaderWidth,
            ),
          ),
        ),
      ),
    );

    return Container(
      constraints: const BoxConstraints(),
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<Duration>(
            valueListenable: widget.transportClockListenable,
            builder: (context, _, __) {
              final playheadPx = _getPlayheadPx(context);
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
                    ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        scrollbars: false,
                      ),
                      child: SingleChildScrollView(
                        controller: _verticalScrollController,
                        physics: ((_pendingDrag ||
                                        _pendingAutomationClipVisual != null) &&
                                    _activeTool != _TimelineTool.delete) ||
                                _isUserInteracting &&
                                    (_interactionMode == 'drag' ||
                                        _interactionMode == 'automation' ||
                                        _hasActiveAutomationClipDrag) ||
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
                                  final playheadPx = _getPlayheadPx(context);
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
                                  );
                                },
                              ),
                              staticTrackHeaders,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _syncPlaybackViewport(double playheadPx) {
    if (PlatformCapabilities.current.isDesktop) {
      return;
    }
    if (_scrollOffsetMs == 0.0 && _currentPlayheadMs == 0.0) {
      _scrollOffsetMs = -(playheadPx) / _pixelsPerMs;
    }

    final int expectedRestartMs =
        (_loopEnabled && _loopStartMs != null) ? _loopStartMs! : 0;
    final bool isRestart = (!widget.isPlaying) &&
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
  }) {
    final loopPreviewClipIndex = _clipLoopPreviewClipIndex;
    final loopPreviewActive = loopPreviewClipIndex != null;
    final loopPreviewTransportMs = loopPreviewActive ? transportMs : 0.0;
    final loopPreviewStartMs =
        loopPreviewActive ? _clipLoopPreviewStartMs : null;
    final loopPreviewFallbackMs =
        loopPreviewActive ? _clipLoopPreviewFallbackMs : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (timelineUnderlayWidth > 0.0)
          Positioned(
            left: kTimelineUnderlayLeft,
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
                          clipOverlapMode: widget.clipOverlapMode,
                          getStartMs: widget.getStartMs,
                          getDurationMs: widget.getDurationMs,
                          getTimelineDurationMs: widget.getTimelineDurationMs,
                          getTrimStartMs: widget.getTrimStartMs,
                          getTrimEndMs: widget.getTrimEndMs,
                          getFullDurationMs: widget.getFullDurationMs,
                          getPeaks: widget.getPeaks,
                          pixelsPerMs: _pixelsPerMs,
                          scrollOffsetMs: _scrollOffsetMs -
                              (timelineUnderlayWidth / _pixelsPerMs),
                          viewportWidth: timelineUnderlayWidth,
                          playheadPx: playheadPx,
                          transportMs: loopPreviewTransportMs,
                          clipLoopPreviewClipIndex: loopPreviewClipIndex,
                          clipLoopPreviewStartMs: loopPreviewStartMs,
                          clipLoopPreviewFallbackMs: loopPreviewFallbackMs,
                          selectedClipIndex: _selectedClipIndex,
                          selectedClipIndices:
                              _selectedClipIndices.toList(growable: false),
                          stretchToolActive:
                              _activeTool == _TimelineTool.stretch,
                          trimClipIndex: _trimClipIndex,
                          draggedClipIndex: _interactionMode == 'drag'
                              ? _draggedClipIndex
                              : null,
                          draggedClipStartMs: _interactionMode == 'drag'
                              ? _dragStartClipMs
                              : null,
                          draggedClipRowIndex:
                              _interactionMode == 'drag' ? _dragStartRow : null,
                          rowExpanded: _rowExpanded,
                          kExpandedRowHeight: kExpandedRowHeight,
                          verticalScrollOffset: _verticalScrollOffset,
                          expandedTab: _expandedTab,
                          effectsPanelHeights: _effectsPanelHeights,
                          expandedHeights: expandedHeights,
                          automationLaneHeights: automationLaneHeights,
                          isRecording: widget.isRecording,
                          recordingRowIndex: widget.recordingRowIndex,
                          recordingStartMs: widget.recordingStartMs,
                          recordingPeaks: widget.recordingPeaks,
                          bpm: widget.bpm,
                          beatsPerBar: widget.beatsPerBar,
                          quantizeDivisions: _quantizeDivisionsPerBar,
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
                          leftVisibleExtensionPx:
                              kHeaderWidth - kTimelineUnderlayLeft,
                        ),
                        size: Size(
                          timelineUnderlayWidth,
                          _timelinePaintHeight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          left: kHeaderWidth,
          child: Builder(
            builder: (context) {
              Widget timelineContent = Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onTimelinePointerDown,
                onPointerMove: _onTimelinePointerMove,
                onPointerHover: _onTimelinePointerHover,
                onPointerSignal: _onTimelinePointerSignal,
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
                  onTapUp: _onTimelineTap,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ClipRect(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _TimelinePainter(
                            rows: widget.rows,
                            clips: widget.clips,
                            clipOverlapMode: widget.clipOverlapMode,
                            getStartMs: widget.getStartMs,
                            getDurationMs: widget.getDurationMs,
                            getTimelineDurationMs: widget.getTimelineDurationMs,
                            getTrimStartMs: widget.getTrimStartMs,
                            getTrimEndMs: widget.getTrimEndMs,
                            getFullDurationMs: widget.getFullDurationMs,
                            getPeaks: widget.getPeaks,
                            pixelsPerMs: _pixelsPerMs,
                            scrollOffsetMs: _scrollOffsetMs,
                            viewportWidth: viewportWidth,
                            playheadPx: playheadPx,
                            transportMs: loopPreviewTransportMs,
                            clipLoopPreviewClipIndex: loopPreviewClipIndex,
                            clipLoopPreviewStartMs: loopPreviewStartMs,
                            clipLoopPreviewFallbackMs: loopPreviewFallbackMs,
                            selectedClipIndex: _selectedClipIndex,
                            selectedClipIndices:
                                _selectedClipIndices.toList(growable: false),
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
                            kExpandedRowHeight: kExpandedRowHeight,
                            verticalScrollOffset: _verticalScrollOffset,
                            expandedTab: _expandedTab,
                            effectsPanelHeights: _effectsPanelHeights,
                            expandedHeights: expandedHeights,
                            automationLaneHeights: automationLaneHeights,
                            isRecording: widget.isRecording,
                            recordingRowIndex: widget.recordingRowIndex,
                            recordingStartMs: widget.recordingStartMs,
                            recordingPeaks: widget.recordingPeaks,
                            bpm: widget.bpm,
                            beatsPerBar: widget.beatsPerBar,
                            quantizeDivisions: _quantizeDivisionsPerBar,
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
                            leftVisibleExtensionPx: 0.0,
                          ),
                          size: Size(viewportWidth, _timelinePaintHeight),
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
                builder: (_, __, ___) => timelineContent,
              );
            },
          ),
        ),
        if (_currentSelectionRect() != null) _buildSelectionBoxOverlay(),
        ..._buildExpandedRows(viewportWidth),
        Positioned(
          top: _addRowSectionTop,
          left: 0,
          right: 0,
          child: Center(
            child: _buildAddRowPill(),
          ),
        ),
        _buildSelectedClipPopup(viewportWidth, visibleTimelineHeight),
        _buildPastePopup(viewportWidth),
        _buildAutomationClipMenuOverlay(
          viewportWidth,
          visibleTimelineHeight,
          timelineAutomationClipVisuals,
        ),
        _buildAutomationClipTestOverlay(
          viewportWidth,
          visibleTimelineHeight,
          timelineAutomationClipVisuals,
        ),
        _buildDeadZoneRowNames(viewportWidth),
        _buildInlineClipControlOverlay(viewportWidth, visibleTimelineHeight),
      ],
    );
  }

  Widget _buildSelectionBoxOverlay() {
    final rect = _currentSelectionRect();
    if (rect == null) return const SizedBox.shrink();
    return Positioned(
      left: kHeaderWidth + rect.left,
      top: rect.top,
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

  List<Widget> _buildExpandedRows(double viewportWidth) {
    final list = <Widget>[];

    for (int row = 0; row < _rowCount; row++) {
      if (!_rowExpanded[row]) continue;
      final expandedTab = _expandedTab[row];
      final expandedHeight = _expandedPanelHeightForRow(row);

      final double topY = _rowYPositions[row] + kRowHeight;
      final normalizedExpandedTab = _normalizeExpandedTab(expandedTab);
      final automationTargetId = _activeAutomationTargetIdForRow(row);
      list.add(
        Positioned(
          key: ValueKey('expanded_row_${widget.rows[row].rowId}'),
          left: kHeaderWidth,
          top: topY,
          width: viewportWidth,
          height: expandedHeight,
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
      );
    }

    return list;
  }

  Widget _buildExpandedRowPanelContent(
    int row,
    double viewportWidth,
    int normalizedExpandedTab,
    String automationTargetId,
  ) {
    final visibleContent = switch (normalizedExpandedTab) {
      0 => _buildVolumePanel(row),
      2 => _buildAutomationPanel(
          row,
          targetId: automationTargetId,
        ),
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
    final minBubbleWidth = (horizontalPadding * 2) +
        (borderWidth * 2) +
        minVisibleTextPainter.width;
    if (maxWidth <= minBubbleWidth) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: List.generate(_rowCount, (row) {
            final name = widget.rows[row].name.trim();
            return Positioned(
              left: kHeaderWidth + 6,
              top: _rowYPositions[row] + 8,
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                padding: const EdgeInsets.symmetric(
                    horizontal: horizontalPadding, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
      final candidateParamId =
          (target['paramId'] ?? target['id'] ?? '').toString().trim();
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
    final targetId =
        _resolveRowEffectAutomationTargetId(row, effectIndex, paramId);
    if (targetId == null || targetId.isEmpty) return;
    await AppHaptics.impact(AppHapticImpact.medium);
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
                      colors: [
                        _kTimelineWarmStart,
                        _kTimelineWarmEnd,
                      ],
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
                  label,
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
    Widget panel = Container(
      decoration: const BoxDecoration(
        color: _kTimelineExpandedInnerSurface,
      ),
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
                    targetMin: 0.0,
                    targetMax: 1.0,
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
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Builder(
                      builder: (context) {
                        Widget child = PrettyGainSlider(
                          value: widget.rowGain[row],
                          onLongPress: () {
                            unawaited(
                                AppHaptics.impact(AppHapticImpact.medium));
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
                            _gainDragStart = v;
                          },
                          onChanged: (v) {
                            setState(() => widget.rowGain[row] = v);
                            widget.setRowGain(row, v);
                          },
                          onChangeEnd: (v) {
                            widget.onRowGainCommit!(
                                row, _gainDragStart!, widget.rowGain[row]);
                            _gainDragStart = null;
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Builder(
                      builder: (context) {
                        Widget child = PrettyStereoSlider(
                          value: widget.rowPan[row],
                          onLongPress: () {
                            unawaited(
                                AppHaptics.impact(AppHapticImpact.medium));
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
                            setState(() => widget.rowPan[row] = v);
                            widget.setRowPan(row, v);
                          },
                          onChangeEnd: (v) {
                            widget.onRowPanCommit!(
                                row, _panDragStart!, widget.rowPan[row]);
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
  }) {
    final availableTargets = _automationTargetsForAutomationTab(row);
    final activeTargetId = _resolveAutomationTabTargetId(row, targetId);
    final activeTarget =
        _automationTargetMetaById(row, activeTargetId) ?? <String, dynamic>{};
    final lanePoints = activeTargetId == 'volume'
        ? widget.rowVolumeAutomation[row]
        : widget.getAutomationPointsForTarget(row, activeTargetId);
    final targetLabel =
        (activeTarget['label'] ?? activeTargetId).toString().trim();
    final targetFullLabel =
        (activeTarget['fullLabel'] ?? targetLabel).toString().trim();
    final targetParamId =
        (activeTarget['paramId'] ?? activeTargetId).toString().trim();
    final targetMin = (activeTarget['min'] as num?)?.toDouble() ?? 0.0;
    final targetMax = (activeTarget['max'] as num?)?.toDouble() ?? 1.0;
    final isVolumeTarget =
        (activeTarget['isVolume'] == true) || activeTargetId == 'volume';
    final isOrphanTarget = activeTarget['isOrphan'] == true;
    final formatter = _AutomationValueFormatter(
      targetLabel: targetLabel.isEmpty ? activeTargetId : targetLabel,
      targetParamId: targetParamId.isEmpty ? activeTargetId : targetParamId,
      targetMin: targetMin,
      targetMax: targetMax,
      isVolumeLane: isVolumeTarget,
    );
    final bool clipboardMatchesSelection =
        _automationPointsClipboard?.isCompatibleWith(
              formatter,
              expectClipRelative: false,
            ) ??
            false;
    final bool areaClipboardMatchesSelection =
        _automationAreaClipboard?.isCompatibleWith(formatter) ?? false;
    final accentColor = _automationColorForTarget(
      activeTargetId,
      isOrphan: isOrphanTarget,
    );
    final targetDisplayTitle = targetFullLabel.isEmpty
        ? (targetLabel.isEmpty ? activeTargetId : targetLabel)
        : targetFullLabel;
    final rangeSelectionActiveForTarget =
        _isAutomationRangeSelectionModeFor(row, activeTargetId);
    final bool hasRangeStart = _automationRangeSelectionStartMs != null;
    final bool hasRangeEnd = _automationRangeSelectionEndMs != null;
    final bool canConfirmRangeSelection = rangeSelectionActiveForTarget &&
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

    double? laneHighlightStartMs;
    double? laneHighlightEndMs;
    final hasSharedHighlight = _highlightedSegmentRow == row &&
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
      final copiedRelative = _automationPointsForRange(
        lanePoints,
        startMs: safeStart.toDouble(),
        endMs: safeEnd.toDouble(),
        relativeToStart: true,
      );
      _automationAreaClipboard = _AutomationAreaClipboardEntry(
        kind: formatter.valueKind,
        signature: formatter.signature,
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
      final copiedPoints =
          lanePoints.map((point) => point.copy()).toList(growable: false);
      _automationPointsClipboard = _AutomationPointsClipboardEntry(
        kind: formatter.valueKind,
        signature: formatter.signature,
        clipRelative: false,
        points: copiedPoints,
      );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content:
                Text(L10n.translate(context, 'Copied all automation points')),
            duration: Duration(milliseconds: 1200),
          ),
        );
    }

    void pasteAllAutomationPoints() {
      final clipboard = _automationPointsClipboard;
      if (clipboard == null ||
          !clipboardMatchesSelection ||
          clipboard.points.isEmpty) {
        return;
      }
      final before =
          lanePoints.map((point) => point.copy()).toList(growable: false);
      final copiedAfter =
          clipboard.points.map((point) => point.copy()).toList(growable: false);
      _commitAutomationPointsForTarget(
          row, activeTargetId, before, copiedAfter);
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
          !areaClipboardMatchesSelection ||
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
          .map((point) =>
              AutomationPoint(x: startMs + point.x, volume: point.volume))
          .toList(growable: false);
      final before =
          lanePoints.map((point) => point.copy()).toList(growable: false);
      final merged = <AutomationPoint>[
        ...before
            .where(
                (point) => point.x < startMs - 1e-6 || point.x > endMs + 1e-6)
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
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.10),
            ),
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
                        targetLabel:
                            targetLabel.isEmpty ? activeTargetId : targetLabel,
                        targetParamId: targetParamId.isEmpty
                            ? activeTargetId
                            : targetParamId,
                        targetMin: targetMin,
                        targetMax: targetMax,
                        isVolumeLane: isVolumeTarget,
                        highlightStartMs: laneHighlightStartMs,
                        highlightEndMs: laneHighlightEndMs,
                        onChanged: (pts) {
                          if (rangeSelectionActiveForTarget) return;
                          final copiedAfter =
                              pts.map((p) => p.copy()).toList(growable: false);
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
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
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
                                      row, activeTargetId),
                                );
                              },
                        accent: const Color(0xFFA6D6FF),
                        iconOnly: true,
                      ),
                      if (onClose != null)
                        IconButton(
                          tooltip: L10n.translate(
                              context, 'Close automation editor'),
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
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _kTimelineShellFill,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: accentColor.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: activeTargetId,
                              isExpanded: true,
                              dropdownColor: kMixroomGlassDropdownMenuColor,
                              iconEnabledColor: _kTimelineShellMutedText,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: _kTimelineShellText,
                                fontSize: 11.6,
                                fontWeight: FontWeight.w600,
                              ),
                              onChanged: (nextTargetId) {
                                if (nextTargetId == null ||
                                    nextTargetId.trim().isEmpty) {
                                  return;
                                }
                                setState(() {
                                  final resolved =
                                      _resolveAutomationTabTargetId(
                                    row,
                                    nextTargetId,
                                  );
                                  if (_isAutomationRangeSelectionModeFor(
                                        row,
                                        activeTargetId,
                                      ) &&
                                      resolved != activeTargetId) {
                                    _clearAutomationRangeSelectionMode();
                                  }
                                  widget.setSelectedAutomationTargetId(
                                    row,
                                    resolved,
                                  );
                                  _automationEditorRow = row;
                                  _automationEditorTargetId = resolved;
                                });
                              },
                              items: availableTargets.map((target) {
                                final id =
                                    (target['id'] ?? '').toString().trim();
                                final fullLabel = (target['fullLabel'] ??
                                        target['label'] ??
                                        id)
                                    .toString()
                                    .trim();
                                final label =
                                    fullLabel.isEmpty ? id : fullLabel;
                                final hasAutomationData =
                                    hasAutomationDataForTarget(target);
                                return DropdownMenuItem<String>(
                                  value: id,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (hasAutomationData) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: accentColor.withValues(
                                              alpha: 0.92,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }).toList(growable: false),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 24,
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
                          onTap: clipboardMatchesSelection
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
                          onTap: areaClipboardMatchesSelection
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
        minHeight: _kEffectsPanelMinHeight,
        onHeightChanged: (h) {
          if (mounted) {
            setState(() {
              // Keep effects tab at least as tall as the header-side tab stack.
              _effectsPanelHeights[row] = math.max(h, _kEffectsPanelMinHeight);
            });
          }
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
        openTrackPluginEditor: widget.openTrackPluginEditor,
        setTrackEffectParam: widget.setRowEffectParam,
        onRequestAutomateParameter: _handleRowEffectAutomationRequest,
        onPluginParamCommit: widget.onPluginParamCommit,
        onPresetCommit: widget.onPresetCommit,
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
    required bool active,
    required VoidCallback onTap,
    GestureTapDownCallback? onTapDown,
    GestureTapUpCallback? onTapUp,
    GestureTapCancelCallback? onTapCancel,
    required String svgPath,
    double size = 30,
  }) {
    return GestureDetector(
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
                ? const Color.fromRGBO(244, 244, 244, 0.92)
                : const Color.fromRGBO(31, 37, 45, 0.88),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active
                  ? const Color.fromRGBO(43, 53, 63, 0.58)
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
                  ? const Color.fromRGBO(35, 45, 54, 0.96)
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
      onTapDown: (details) {
        _toolMenuGlobalPos = details.globalPosition;
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
        child: _buildToolIcon(
          _activeTool,
          size: 16,
          color: const Color.fromARGB(220, 255, 255, 255),
        ),
      ),
    );
  }

  Widget _buildToolIcon(
    _TimelineTool tool, {
    required double size,
    required Color color,
  }) {
    final icon = Icon(
      tool.icon,
      size: size,
      color: color,
    );
    if (!tool.flipHorizontally) return icon;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
      child: icon,
    );
  }

  Widget _buildTimeRuler(double viewportWidth) {
    final isDesktop = PlatformCapabilities.current.isDesktop;
    return Container(
      height: kRulerHeight,
      color: isDesktop
          ? const Color.fromRGBO(18, 28, 40, 0.68)
          : _timelineCanvasColor(),
      child: Stack(
        children: [
          Row(
            children: [
              // Empty space for headers
              SizedBox(
                width: kHeaderWidth,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        active: _magnetEnabled,
                        onTap: () => setState(() {
                          if (_magnetMenuShownFromHold) {
                            _magnetMenuShownFromHold = false;
                            return;
                          }
                          _magnetEnabled = !_magnetEnabled;
                          if (!_magnetEnabled) {
                            _highlightedSegmentRow = null;
                            _highlightedSegmentStartMs = null;
                            _highlightedSegmentEndMs = null;
                          } else if (_pasteRow != null &&
                              _pasteMs != null &&
                              _showPastePopup) {
                            final start = _segmentStartMsForTap(_pasteMs!);
                            _pasteMs = start;
                            _highlightedSegmentRow = _pasteRow;
                            _highlightedSegmentStartMs = start;
                            _highlightedSegmentEndMs =
                                start + _quantizeIntervalMs();
                          }
                          _refreshCutPreviewFromCurrentRaw(inSetState: true);
                          _notifySnapSettingsChanged();
                        }),
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

              // Ruler content
              Expanded(
                child: Listener(
                  onPointerDown:
                      isDesktop ? _onDesktopRulerSecondaryPointerDown : null,
                  onPointerMove:
                      isDesktop ? _onDesktopRulerSecondaryPointerMove : null,
                  onPointerUp:
                      isDesktop ? _onDesktopRulerSecondaryPointerUp : null,
                  onPointerCancel:
                      isDesktop ? _onDesktopRulerSecondaryPointerUp : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: _onRulerTapDown,
                    onTapUp: _onRulerTapUp,
                    onSecondaryTapDown:
                        isDesktop ? _onDesktopRulerSecondaryTap : null,
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
                        quantizeDivisions: _quantizeDivisionsPerBar,
                      ),
                      size: Size(viewportWidth, kRulerHeight),
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
                  left: kHeaderWidth + playheadPx - 10,
                  top: 16,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: 20,
                      height: kRulerHeight,
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
          if (_loopEnabled) _buildLoopRegion(viewportWidth),
        ],
      ),
    );
  }

  Widget _buildLoopRegion(double viewportWidth) {
    if (_loopStartMs == null || _loopEndMs == null) {
      return const SizedBox.shrink();
    }

    final startPx = (_loopStartMs! - _scrollOffsetMs) * _pixelsPerMs;
    final endPx = (_loopEndMs! - _scrollOffsetMs) * _pixelsPerMs;

    double left = math.min(startPx, endPx) + kHeaderWidth;
    double width = (endPx - startPx).abs();

    // --- NEW FIX: Prevent overlap with the track headers ---
    if (left < kHeaderWidth) {
      width -= (kHeaderWidth - left);
      left = kHeaderWidth;
    }

    // If width is now negative, nothing to draw
    if (width <= 0) return const SizedBox.shrink();
    return Positioned(
      left: left,
      top: 0,
      width: width,
      height: kRulerHeight,
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
                    spreadRadius: 3),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForRow(int iconId) {
    switch (iconId) {
      case 1:
        return Icons.piano;
      case 2:
        return Icons.graphic_eq;
      case 3:
        return Icons.queue_music;
      case 4:
        return Symbols.music_note;
      case 5:
        return Symbols.podcasts;
      default:
        return Symbols.audio_file;
    }
  }

  Future<void> _showRowMenu(int row) async {
    final isInstrumentLane = row >= 0 &&
        row < widget.rows.length &&
        widget.rows[row].isInstrumentLane;
    if (_selectedClipIndex >= 0 || _selectedClipIndices.isNotEmpty) {
      setState(() {
        _clearClipSelection();
      });
    }
    await AppHaptics.impact(AppHapticImpact.medium);
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
                  ListTile(
                    leading: const Icon(Icons.vertical_align_top,
                        color: _kTimelineShellText),
                    title: Text(L10n.translate(ctx, 'Insert Audio Row Above'),
                        style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: _kTimelineShellText)),
                    onTap: () => Navigator.pop(ctx, 'insert_above'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.vertical_align_bottom,
                        color: _kTimelineShellText),
                    title: Text(L10n.translate(ctx, 'Insert Audio Row Below'),
                        style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: _kTimelineShellText)),
                    onTap: () => Navigator.pop(ctx, 'insert_below'),
                  ),
                  if (widget.onInsertInstrumentLaneAbove != null)
                    ListTile(
                      leading: const Icon(Icons.piano_outlined,
                          color: _kTimelineShellText),
                      title: Text(
                          L10n.translate(ctx, 'Insert Instrument Lane Above'),
                          style: const TextStyle(
                              fontFamily: 'Pretendard',
                              color: _kTimelineShellText)),
                      onTap: () =>
                          Navigator.pop(ctx, 'insert_instrument_above'),
                    ),
                  if (widget.onInsertInstrumentLaneBelow != null)
                    ListTile(
                      leading: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: _kTimelineShellText),
                      title: Text(
                          L10n.translate(ctx, 'Insert Instrument Lane Below'),
                          style: const TextStyle(
                              fontFamily: 'Pretendard',
                              color: _kTimelineShellText)),
                      onTap: () =>
                          Navigator.pop(ctx, 'insert_instrument_below'),
                    ),
                  if (isInstrumentLane && widget.onChangeInstrumentLane != null)
                    ListTile(
                      leading: const Icon(Icons.swap_horiz_rounded,
                          color: _kTimelineShellText),
                      title: Text(L10n.translate(ctx, 'Change Instrument'),
                          style: const TextStyle(
                              fontFamily: 'Pretendard',
                              color: _kTimelineShellText)),
                      onTap: () => Navigator.pop(ctx, 'change_instrument'),
                    ),
                  ListTile(
                    leading: const Icon(Icons.arrow_upward,
                        color: _kTimelineShellText),
                    title: Text(L10n.translate(ctx, 'Move Up'),
                        style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: _kTimelineShellText)),
                    onTap: () => Navigator.pop(ctx, 'move_up'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.arrow_downward,
                        color: _kTimelineShellText),
                    title: Text(L10n.translate(ctx, 'Move Down'),
                        style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: _kTimelineShellText)),
                    onTap: () => Navigator.pop(ctx, 'move_down'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.drive_file_rename_outline,
                        color: _kTimelineShellText),
                    title: Text(L10n.translate(ctx, 'Rename Row'),
                        style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: _kTimelineShellText)),
                    onTap: () => Navigator.pop(ctx, 'rename'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.image_outlined,
                        color: _kTimelineShellText),
                    title: Text(L10n.translate(ctx, 'Choose Icon'),
                        style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: _kTimelineShellText)),
                    onTap: () => Navigator.pop(ctx, 'icon'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline,
                        color: Color(0xFFFFA4A4)),
                    title: Text(L10n.translate(ctx, 'Delete Row'),
                        style: const TextStyle(color: Color(0xFFFFA4A4))),
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
    if (action == 'move_up' && row > 0) return widget.onMoveRow(row, row - 1);
    if (action == 'move_down' && row < _rowCount - 1)
      return widget.onMoveRow(row, row + 1);
    if (action == 'delete') return widget.onDeleteRow(row);

    if (action == 'rename') {
      final name = await _showTimelineNameInputDialog(
        title: L10n.translate(context, 'Rename Row'),
        initialName: widget.rows[row].name,
        hintText: L10n.translate(context, 'Row name'),
        maxLength: 32,
      );
      if (name != null && name.isNotEmpty) {
        await widget.onRenameRow(row, name);
      }
      return;
    }

    if (action == 'icon') {
      final selectedIconId = await showDialog<int>(
        context: context,
        builder: (ctx) {
          const ids = [0, 1, 2, 3, 4, 5];
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
                  fontFamily: 'Pretendard', color: _kTimelineShellText),
            ),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ids
                  .map(
                    (id) => InkWell(
                      onTap: () => Navigator.pop(ctx, id),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _kTimelineShellFill,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child:
                            Icon(_iconForRow(id), color: _kTimelineShellText),
                      ),
                    ),
                  )
                  .toList(),
            ),
          );
        },
      );
      if (selectedIconId != null) {
        await widget.onSetRowIcon(row, selectedIconId);
      }
    }
  }

  Widget _buildTrackHeadersContent(double dynamicWidth) {
    if (_rowCount == 0) {
      return Align(
        alignment: Alignment.topCenter,
        child: IconButton(
          onPressed: widget.onAddRow,
          icon: const Icon(Icons.add_circle_outline,
              color: Colors.white, size: 30),
        ),
      );
    }

    return Column(
      children: [
        ...List.generate(_rowCount, (row) {
          final isSelected = row == _selectedRowIndex;
          final isMuted = widget.rowMuted[row];
          final isExpanded = _rowExpanded[row];
          final showsAutomationLane =
              _automationTimelineLaneHeightForRow(row) > 0.0;

          return Column(
            children: [
              _buildOneTrackHeader(row, isSelected, isMuted),
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
                              child: const Text(
                                'Automation',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
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
        const SizedBox(height: kHeaderFooterHeight),
        SizedBox(
          height: _kAddRowPillHeight +
              _kAddRowSectionGap +
              _editorLayoutSpec.bottomInteractionPadding +
              _kExtraAddRowBottomPadding,
        ),
      ],
    );
  }

  Widget _buildAddRowPill() {
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
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
            ),
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

    final pillTopLeft =
        pillBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final pillRect = pillTopLeft & pillBox.size;
    const bubbleWidth = 224.0;
    final actionCount = 1 +
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
    final tailCenterX =
        (pillRect.center.dx - left).clamp(22.0, bubbleWidth - 22.0).toDouble();

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

  Widget _buildOneTrackHeader(int row, bool isSelected, bool isMuted) {
    final isInstrumentLane = _isInstrumentLane(row);
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
        onTap: () => setState(() {
          final newVal = !widget.rowMuted[row];
          widget.muteRow(row, newVal);
        }),
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
            color: isMuted
                ? const Color.fromRGBO(103, 147, 198, 0.42)
                : Colors.transparent,
            borderRadius: muteButtonRadius,
          ),
          child: Text(
            'M',
            style: TextStyle(
              fontFamily: 'Pretendard',
              color:
                  isMuted ? Colors.white : Colors.white.withValues(alpha: 0.72),
              fontSize: 13,
              fontWeight: FontWeight.w700,
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
          final newVal = !widget.rowSoloed[row];
          widget.soloRow(row, newVal);
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
            color: widget.rowSoloed[row]
                ? const Color.fromRGBO(183, 127, 63, 0.42)
                : Colors.transparent,
            borderRadius: soloButtonRadius,
          ),
          child: Text(
            'S',
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: widget.rowSoloed[row]
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.72),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
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
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _handleHeaderPointerDown(row, e),
      onPointerMove: _onHeaderPointerMove,
      onPointerUp: _onHeaderPointerUp,
      onPointerCancel: _onHeaderPointerCancel,
      child: Container(
        height: kRowHeight, // Fixed height
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
                color: isSelected
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
                    Icon(
                      isInstrumentLane
                          ? Icons.piano_outlined
                          : _iconForRow(widget.rows[row].iconId),
                      color: Colors.white,
                      size: 20,
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
                    if (isSelected) ...[
                      const SizedBox(height: 1),
                      Icon(
                        _rowExpanded[row]
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.white.withValues(alpha: 0.84),
                        size: 12,
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
        haloKeys: <HaloKey>[
          HaloKey('row:$row'),
          HaloKey('row:$row:header'),
        ],
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
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF20242A),
            Color(0xFF181C21),
          ],
        ),
        border: Border(
          bottom:
              BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boundedHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : _kEffectsPanelMinHeight;
          final headerDbfsReadoutWidth = constraints.maxWidth.isFinite
              ? (constraints.maxWidth - 12.0).clamp(60.0, 86.0).toDouble()
              : 72.0;
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: boundedHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
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
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
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
      final isTrimStart = (_activeTrimHandleX! - clipRect.left).abs() <=
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
        _dragGroupStartMs.clear();
        _dragGroupStartRows.clear();
        final draggedIndex = _draggedClipIndex;
        if (draggedIndex != null &&
            draggedIndex >= 0 &&
            draggedIndex < widget.clips.length) {
          final draggingGroup = _selectedClipIndices.length > 1 &&
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
      final draggingGroup = selected.length > 1 &&
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
              _quantizeMs(baseMs + _dragDeltaMs).clamp(0.0, double.infinity);
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
              _draggedClipIndex!, _dragStartClipMs!, nextRow);
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
    });
  }

  void _onTimelineLongPressStart(LongPressStartDetails details) {
    _clearPendingAutomationClipSelection();
    if (_activeTool == _TimelineTool.pencil &&
        _canShowInstrumentLaneRegionMenuAt(details.localPosition)) {
      unawaited(_showInstrumentLaneRegionMenuAt(details.localPosition));
      return;
    }
    if (_activeTool != _TimelineTool.pencil &&
        _activeTool != _TimelineTool.stretch) {
      return;
    }
    if (_interactionMode == 'automation' || _hasActiveAutomationClipDrag) {
      return;
    }
    final tappedAutomationClip =
        _timelineAutomationClipAt(details.localPosition);
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
    if (_getGestureClipIndexAt(details.localPosition) != null) return;
    setState(() {
      _clearAutomationClipMenu();
      _selectionBoxActive = true;
      _selectionBoxStart = details.localPosition;
      _selectionBoxCurrent = details.localPosition;
      _clipPopupMs = null;
      _updateSelectionFromRect(Rect.fromLTWH(
          details.localPosition.dx, details.localPosition.dy, 0, 0));
    });
  }

  void _onTimelineLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_selectionBoxActive) return;
    setState(() {
      _selectionBoxCurrent = details.localPosition;
      final rect = _currentSelectionRect();
      if (rect != null) {
        _updateSelectionFromRect(rect);
      }
    });
  }

  void _onTimelineLongPressEnd(LongPressEndDetails details) {
    if (!_selectionBoxActive) return;
    setState(() {
      _selectionBoxActive = false;
      _selectionBoxStart = null;
      _selectionBoxCurrent = null;
    });
  }

  // --- Drag/Trim/Pan Handlers ---

  void _handleDragUpdate(ScaleUpdateDetails details) {
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
    if (_draggedClipIndex == null || _dragStartGlobalOffset == null) return;

    setState(() {
      final draggedIndex = _draggedClipIndex!;
      final draggedClip = widget.clips[draggedIndex];

      // Calculate TOTAL delta from drag start (for row)
      final totalDx = details.focalPoint.dx - _dragStartGlobalOffset!.dx;

      // Convert to delta in Ms
      final deltaMs = totalDx / _pixelsPerMs;
      _dragDeltaMs = deltaMs;

      // Convert total vertical displacement to row index
      // Use the *original* row index to calculate the new one based on total vertical drag
      final draggingGroup = _selectedClipIndices.length > 1 &&
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
      int newRow = hoveredRow ??
          (details.localFocalPoint.dy < 0 ? 0 : math.max(0, _rowCount - 1));
      _dragDeltaRows = newRow - originalRow;

      // Update the *temporary* drag state
      // The painter will use these values to draw the ghost clip
      _dragStartClipMs = _quantizeMs(
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
    final timelineVisibleMs =
        widget.getTimelineDurationMs(clip).clamp(1.0, double.infinity);
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
    if (_trimClipIndex == null || _trimStartAnchorX == null) return;

    final clip = widget.clips[_trimClipIndex!];
    final fullDuration = widget.getFullDurationMs(clip);
    final isReversed = clip.isReversed;
    final timelineScale =
        (_trimTimelineScaleValue ?? 1.0).clamp(0.0001, double.infinity);
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
    final maxVisibleEndMs = originalStartMs +
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
      if (_magnetEnabled) {
        targetVisibleStartMs = _quantizeMs(targetVisibleStartMs);
      }
      targetVisibleStartMs = targetVisibleStartMs
          .clamp(minVisibleStartMs, originalVisibleEndMs - minTimelineTrimMs)
          .toDouble();
      final deltaVisibleMs = targetVisibleStartMs - originalStartMs;
      if (isReversed) {
        newTrimEnd = (_trimEndValue! - (deltaVisibleMs / timelineScale))
            .clamp(newTrimStart + minRawTrimMs, fullDuration);
      } else {
        newTrimStart = (_trimStartValue! + (deltaVisibleMs / timelineScale))
            .clamp(0.0, newTrimEnd - minRawTrimMs);
      }
      newStartMs = targetVisibleStartMs;
    } else if (_interactionMode == 'trim-end') {
      double targetVisibleEndMs = originalVisibleEndMs + deltaTimelineMs;
      if (_magnetEnabled) {
        targetVisibleEndMs = _quantizeMs(targetVisibleEndMs);
      }
      targetVisibleEndMs = targetVisibleEndMs
          .clamp(
            originalStartMs + minTimelineTrimMs,
            maxVisibleEndMs,
          )
          .toDouble();
      final deltaVisibleMs = targetVisibleEndMs - originalVisibleEndMs;
      if (isReversed) {
        newTrimStart = (_trimStartValue! - (deltaVisibleMs / timelineScale))
            .clamp(0.0, newTrimEnd - minRawTrimMs);
      } else {
        newTrimEnd = (_trimEndValue! + (deltaVisibleMs / timelineScale))
            .clamp(newTrimStart + minRawTrimMs, fullDuration);
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
      sanitizedTrimEnd =
          (sanitizedTrimStart + minTrimWindowMs).clamp(0.0, fullDuration);
      if (sanitizedTrimEnd >= fullDuration) {
        sanitizedTrimStart =
            (sanitizedTrimEnd - minTrimWindowMs).clamp(0.0, maxTrimStart);
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
      if (_magnetEnabled) {
        targetStartMs = _quantizeMs(targetStartMs);
      }
      targetStartMs =
          targetStartMs.clamp(0.0, originalEndMs - minDurationMs).toDouble();
      newDurationMs =
          (originalEndMs - targetStartMs).clamp(minDurationMs, 36000000.0);
      newStartMs = targetStartMs;
    } else if (_interactionMode == 'stretch-end') {
      double targetEndMs = originalEndMs + deltaMs;
      if (_magnetEnabled) {
        targetEndMs = _quantizeMs(targetEndMs);
      }
      targetEndMs =
          targetEndMs.clamp(originalStartMs + minDurationMs, 36000000.0);
      newDurationMs =
          (targetEndMs - originalStartMs).clamp(minDurationMs, 36000000.0);
      newStartMs = null;
    }

    widget.onStretchClip(
      clipIndex,
      newDurationMs,
      newStartMs: newStartMs,
    );
    _stretchDurationUpdateMs = newDurationMs;

    setState(() {});
  }

  void _handlePanZoomUpdate(ScaleUpdateDetails details) {
    bool didZoom = false;
    bool didScroll = false;
    final allowDesktopPointerPan =
        !PlatformCapabilities.current.isDesktop || _timelineHasMultiTouch;
    setState(() {
      // --- Handle Zoom ---
      if (details.scale != 1.0 && _initialPixelsPerMs != null) {
        final newPixelsPerMs = (_initialPixelsPerMs! * details.scale)
            .clamp(_kMinTimelinePixelsPerMs, _kMaxTimelinePixelsPerMs);
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

      // --- Clamping & Scrub ---
      _clampScroll();
      if (!PlatformCapabilities.current.isDesktop) {
        final playheadPx = _getPlayheadPx(context);
        widget.onScrubRequested(_scrollOffsetMs + playheadPx / _pixelsPerMs);
      }
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
      final zoomedEnough = (zoomRatio - 1.0).abs() >= 0.08 ||
          (_pixelsPerMs - startZoom).abs() >= 0.002;
      if (didZoom && zoomedEnough) {
        _tutorialZoomNotifiedForGesture = true;
        widget.onTutorialTimelineZoomed?.call();
      }
    }
  }

  double msFor128Bars(double bpm) {
    return 512 * (60000 / bpm);
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

    final x = (startMs - _scrollOffsetMs) * _pixelsPerMs;
    final width = (trimEnd - trimStart) * _pixelsPerMs;
    final yOffset = _rowTopForIndex(row);

    final y = yOffset + 2;
    const height = kRowHeight - 4;

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

    // Iterate backwards to prioritize clips drawn later (higher index clips are usually drawn on top)
    for (int i = widget.clips.length - 1; i >= 0; i--) {
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
    for (int i = widget.clips.length - 1; i >= 0; i--) {
      final clip = widget.clips[i];
      if (clip.rowIndex != tapRow) continue;

      final startMs = widget.getStartMs(clip);
      final endMs = startMs + widget.getTimelineDurationMs(clip);
      if (tapMs >= startMs && tapMs <= endMs) {
        return i;
      }
      if (!includeTrimHandleHitbox || !_selectedClipIndices.contains(i)) {
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
      final isSelectedClip = _selectedAutomationClipIdFor(
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
        } else if (_automationClipMoveHandleRect(tappedAutomationClip)
            .contains(localPos)) {
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
      final quantizedStartMs = _segmentStartMsForTap(rawTapMs);
      final quantizedEndMs = quantizedStartMs + _quantizeIntervalMs();
      final tapMsForPaste = _magnetEnabled ? quantizedStartMs : rawTapMs;
      final canPasteHere = tapRow != null &&
          (_canPasteCopiedClipAtRow(tapRow) ||
              _canPasteAutomationClipAt(tapRow));
      final needsVisualReset = _selectedClipIndex >= 0 ||
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
            _pasteRow = tapRow;
            _pasteMs = tapMsForPaste;
            _showPastePopup = true;
            if (_magnetEnabled) {
              _highlightedSegmentRow = tapRow;
              _highlightedSegmentStartMs = quantizedStartMs;
              _highlightedSegmentEndMs = quantizedEndMs;
            } else {
              _highlightedSegmentRow = null;
              _highlightedSegmentStartMs = null;
              _highlightedSegmentEndMs = null;
            }
          }
        });
      } else if (canPasteHere) {
        setState(() {
          _pasteRow = tapRow;
          _pasteMs = tapMsForPaste;
          _showPastePopup = true;
          if (_magnetEnabled) {
            _highlightedSegmentRow = tapRow;
            _highlightedSegmentStartMs = quantizedStartMs;
            _highlightedSegmentEndMs = quantizedEndMs;
          } else {
            _highlightedSegmentRow = null;
            _highlightedSegmentStartMs = null;
            _highlightedSegmentEndMs = null;
          }
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
    final draggingGroup = _selectedClipIndices.length > 1 &&
        _selectedClipIndices.contains(tappedClipIndex);

    // === 3. PRIORITY 1: TRIM HANDLE HIT? (WINS OVER DRAG) ===
    final leftHandleHit =
        _isLocalPositionInLeftTrimHandleHitbox(clipRect, localPos);
    final rightHandleHit =
        _isLocalPositionInRightTrimHandleHitbox(clipRect, localPos);

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
      final canBeginDrag = _activeTool == _TimelineTool.paint ||
          wasAlreadySelected ||
          draggingGroup;
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
          _pendingDragStartedFromSelection = wasAlreadySelected;
          _draggedClipIndex = tappedClipIndex;
          _dragStartGlobalOffset = details.globalPosition;
          _dragStartLocalOffset = localPos;
          _dragStartClipMs = widget.getStartMs(clip);
          _dragStartRow = clip.rowIndex;
          _dragDeltaMs = 0.0;
          _dragDeltaRows = 0;
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
    final tappedAutomationClip =
        _timelineAutomationClipAt(details.localPosition);
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

  Future<void> _showInstrumentLaneRegionMenuAt(Offset localPosition) async {
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
      _highlightedSegmentRow = _magnetEnabled ? tapRow : null;
      _highlightedSegmentStartMs = _magnetEnabled ? quantizedStartMs : null;
      _highlightedSegmentEndMs = _magnetEnabled ? quantizedEndMs : null;
      _selectionBoxActive = false;
      _selectionBoxStart = null;
      _selectionBoxCurrent = null;
      _suppressNextTimelineTapAfterInstrumentLaneCreate = true;
    });

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF5F666D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.add_rounded,
                color: _kTimelineShellText,
              ),
              title: Text(
                L10n.translate(ctx, 'Add MIDI Region'),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: _kTimelineShellText,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'add_midi_region'),
            ),
            ListTile(
              leading: const Icon(
                Icons.close_rounded,
                color: _kTimelineShellText,
              ),
              title: Text(
                L10n.translate(ctx, 'Cancel'),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: _kTimelineShellText,
                ),
              ),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _highlightedSegmentRow = null;
      _highlightedSegmentStartMs = null;
      _highlightedSegmentEndMs = null;
      _showPastePopup = false;
      _pasteRow = null;
      _pasteMs = null;
    });
    if (action != 'add_midi_region') return;
    final create = widget.onCreateMidiClipInInstrumentLane;
    if (create == null) return;
    await create(tapRow, tapMsForPaste);
  }

  void _onTimelineTap(TapUpDetails details) {
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
          _highlightedSegmentRow = null;
          _highlightedSegmentStartMs = null;
          _highlightedSegmentEndMs = null;
        });
        return;
      }
      final topIndex = _getGestureClipIndexAt(details.localPosition);
      if (topIndex != null) {
        setState(() {
          _setSingleClipSelection(topIndex,
              popupMs:
                  _scrollOffsetMs + details.localPosition.dx / _pixelsPerMs);
          _showPastePopup = false;
          _pasteRow = null;
          _pasteMs = null;
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
      final shouldTreatAsTap =
          !_pendingClipDragExceededSlop(details.globalPosition);
      final tapPopupMs =
          _scrollOffsetMs + details.localPosition.dx / _pixelsPerMs;
      final shouldSelectClip = shouldTreatAsTap &&
          tappedDragIndex != null &&
          tappedDragIndex >= 0 &&
          tappedDragIndex < widget.clips.length;
      final shouldOpenMidiFromRetap = shouldSelectClip &&
          _selectedClipIndices.contains(tappedDragIndex) &&
          widget.clips[tappedDragIndex].clipKind == ClipKind.midi;

      setState(() {
        final preserveDraggedGroupSelection = shouldSelectClip &&
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
    final quantizedStartMs = _segmentStartMsForTap(rawTapMs);
    final quantizedEndMs = quantizedStartMs + _quantizeIntervalMs();
    final tapMsForPaste = _magnetEnabled ? quantizedStartMs : rawTapMs;

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
      final preserveExistingSelection = _selectedClipIndices.length > 1 &&
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
        _highlightedSegmentRow = null;
        _highlightedSegmentStartMs = null;
        _highlightedSegmentEndMs = null;
      });
    } else {
      setState(() {
        _resetTrimInteractionState();
        _clearClipSelection();
        final canPasteHere = _canPasteCopiedClipAtRow(tapRow) ||
            _canPasteAutomationClipAt(tapRow);

        // If we have something copied, show paste popup here
        if (canPasteHere) {
          _pasteRow = tapRow;
          _pasteMs = tapMsForPaste;
          _showPastePopup = true;
          if (_magnetEnabled) {
            _highlightedSegmentRow = tapRow;
            _highlightedSegmentStartMs = quantizedStartMs;
            _highlightedSegmentEndMs = quantizedEndMs;
          } else {
            _highlightedSegmentRow = null;
            _highlightedSegmentStartMs = null;
            _highlightedSegmentEndMs = null;
          }
        } else {
          _showPastePopup = false;
          _pasteRow = null;
          _pasteMs = null;
          _highlightedSegmentRow = null;
          _highlightedSegmentStartMs = null;
          _highlightedSegmentEndMs = null;
        }
      });
    }
  }
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

// === Custom painter for the timeline ===
class _TimelinePainter extends CustomPainter {
  final List<TimelineRow> rows;
  final List<AudioTrack> clips;
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
  final double playheadPx; // === FIX ===: Use playheadPx
  final double transportMs;
  final int? clipLoopPreviewClipIndex;
  final double? clipLoopPreviewStartMs;
  final double? clipLoopPreviewFallbackMs;
  final int selectedClipIndex;
  final List<int> selectedClipIndices;
  final bool stretchToolActive;
  final int? trimClipIndex; // === FIX ===: Added for trim halo/indicator
  // === FIX ===: Updated drag properties
  final int? draggedClipIndex;
  final double? draggedClipStartMs;
  final int? draggedClipRowIndex;
  final List<bool> rowExpanded; // === NEW ===
  final double kExpandedRowHeight; // === NEW ===
  final double verticalScrollOffset;
  final List<int> expandedTab;
  final List<double> effectsPanelHeights;
  final List<double> expandedHeights;
  final List<double> automationLaneHeights;
  final bool isRecording;
  final int? recordingRowIndex;
  final double recordingStartMs;
  final List<double> recordingPeaks;
  final double bpm;
  final int beatsPerBar;
  final int quantizeDivisions;
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
  final double? leftVisibleExtensionPx;
  final int _clipDataHash;
  final int _automationClipHash;
  final int _selectedClipIndicesHash;
  final int _rowExpandedHash;
  final int _expandedTabHash;
  final int _effectsPanelHeightsHash;
  final int _expandedHeightsHash;
  final int _automationLaneHeightsHash;
  final int _recordingPeaksHash;
  final int _rowKindHash;

  _TimelinePainter({
    required this.rows,
    required this.clips,
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
    required this.playheadPx, // === FIX ===
    required this.transportMs,
    required this.clipLoopPreviewClipIndex,
    required this.clipLoopPreviewStartMs,
    required this.clipLoopPreviewFallbackMs,
    required this.selectedClipIndex,
    required this.selectedClipIndices,
    required this.stretchToolActive,
    this.trimClipIndex, // === FIX ===: Add to constructor
    this.draggedClipIndex,
    this.draggedClipStartMs,
    this.draggedClipRowIndex,
    required this.rowExpanded,
    required this.kExpandedRowHeight,
    required this.verticalScrollOffset,
    required this.expandedTab,
    required this.effectsPanelHeights,
    required this.expandedHeights,
    required this.automationLaneHeights,
    required this.isRecording,
    required this.recordingRowIndex,
    required this.recordingStartMs,
    required this.recordingPeaks,
    required this.bpm,
    required this.beatsPerBar,
    required this.quantizeDivisions,
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
    this.leftVisibleExtensionPx,
  })  : _clipDataHash = _computeClipDataHash(
          clips: clips,
          getStartMs: getStartMs,
          getTimelineDurationMs: getTimelineDurationMs,
          getTrimStartMs: getTrimStartMs,
          getTrimEndMs: getTrimEndMs,
          getFullDurationMs: getFullDurationMs,
          getPeaks: getPeaks,
        ),
        _automationClipHash = _computeAutomationClipHash(automationClipVisuals),
        _selectedClipIndicesHash = _hashList(selectedClipIndices),
        _rowExpandedHash = _hashList(rowExpanded),
        _expandedTabHash = _hashList(expandedTab),
        _effectsPanelHeightsHash = _hashDoubleList(effectsPanelHeights),
        _expandedHeightsHash = _hashDoubleList(expandedHeights),
        _automationLaneHeightsHash = _hashDoubleList(automationLaneHeights),
        _recordingPeaksHash = _hashDoubleList(recordingPeaks),
        _rowKindHash = _hashList(rows
            .map((row) => row.kind == TimelineRowKind.instrument ? 1 : 0)
            .toList(growable: false));

  static int _computeClipDataHash({
    required List<AudioTrack> clips,
    required double Function(AudioTrack) getStartMs,
    required double Function(AudioTrack) getTimelineDurationMs,
    required double Function(AudioTrack) getTrimStartMs,
    required double Function(AudioTrack) getTrimEndMs,
    required double Function(AudioTrack) getFullDurationMs,
    required List<double> Function(AudioTrack) getPeaks,
  }) {
    var hash = 0;
    for (final clip in clips) {
      final peaks = getPeaks(clip);
      hash = _hashCombine(hash, clip.rowIndex);
      hash = _hashCombine(hash, clip.label);
      hash = _hashCombine(hash, clip.instrumentName);
      hash = _hashCombine(hash, clip.clipKind.index);
      hash = _hashCombine(hash, clip.midiNotes.length);
      hash = _hashCombine(hash, _quantizeDouble(clip.gain));
      hash = _hashCombine(hash, clip.normalizeVolume);
      hash = _hashCombine(hash, _quantizeDouble(clip.normalizeGain));
      hash = _hashCombine(hash, _quantizeDouble(clip.sourceTempoBpm));
      hash = _hashCombine(hash, _hashMidiNotes(clip.midiNotes));
      hash = _hashCombine(hash, _quantizeDouble(getStartMs(clip)));
      hash = _hashCombine(hash, _quantizeDouble(getTimelineDurationMs(clip)));
      hash = _hashCombine(hash, _quantizeDouble(getTrimStartMs(clip)));
      hash = _hashCombine(hash, _quantizeDouble(getTrimEndMs(clip)));
      hash = _hashCombine(hash, _quantizeDouble(getFullDurationMs(clip)));
      hash = _hashCombine(hash, peaks.length);
      hash = _hashCombine(hash, identityHashCode(peaks));
    }
    return _hashFinish(hash);
  }

  static int _hashMidiNotes(List<MidiNote> notes) {
    var hash = 0;
    for (final note in notes) {
      hash = _hashCombine(hash, note.pitch);
      hash = _hashCombine(hash, _quantizeDouble(note.startBeat));
      hash = _hashCombine(hash, _quantizeDouble(note.lengthBeats));
      hash = _hashCombine(hash, _quantizeDouble(note.velocity));
    }
    return _hashFinish(hash);
  }

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
    final expanded =
        row >= 0 && row < expandedHeights.length ? expandedHeights[row] : 0.0;
    return _AudioCanvasTimelineState.kRowHeight +
        _automationLaneHeightForRow(row) +
        expanded;
  }

  double _rowTopForIndex(int row) {
    double y = 0.0;
    for (int i = 0; i < row; i++) {
      y += _rowBlockHeight(i);
    }
    return y;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // canvas.translate(0, -verticalScrollOffset); // ← APPLY VERTICAL SCROLL
    // Keep track of the current vertical position
    double currentY = 0;

    // convert playheadPx → ms
    final double playheadMs = scrollOffsetMs + playheadPx / pixelsPerMs;

    // Draw row backgrounds
    for (int row = 0; row < rowExpanded.length; row++) {
      final rowHeight = _AudioCanvasTimelineState.kRowHeight;
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
            0, expandedTop, viewportWidth, expandedHeight.toDouble());
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
        highlightedSegmentRow! < rowExpanded.length) {
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
          _AudioCanvasTimelineState.kRowHeight - 4,
        );
        final clipped =
            rect.intersect(Rect.fromLTWH(0, 0, viewportWidth, size.height));
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
        sampleDropPreviewRow! < rowExpanded.length) {
      final previewY = _rowTopForIndex(sampleDropPreviewRow!);

      final startX = (sampleDropPreviewStartMs! - scrollOffsetMs) * pixelsPerMs;
      final endX = (sampleDropPreviewEndMs! - scrollOffsetMs) * pixelsPerMs;
      final width = endX - startX;
      if (width > 0) {
        final rect = Rect.fromLTWH(
          startX,
          previewY + 2,
          width,
          _AudioCanvasTimelineState.kRowHeight - 4,
        );
        final clipped =
            rect.intersect(Rect.fromLTWH(0, 0, viewportWidth, size.height));
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
    if (!isMsUnderlayPass) {
      _drawGrid(canvas, size); // Note: _drawGrid doesn't use vertical position
    }

    // === RECORDING PREVIEW ==========================================
    if (isRecording && recordingRowIndex != null) {
      final int recRow = recordingRowIndex!;

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
      final double recHeight = _AudioCanvasTimelineState.kRowHeight - 4;

      final Rect recRect = Rect.fromLTWH(0, recYTop, viewportWidth, recHeight);

      final double recDurationMs = playheadMs - recordingStartMs;
      if (recDurationMs > 0) {
        _paintRecordingPreview(
          canvas,
          recRect,
          pixelsPerMs,
          recordingStartMs - scrollOffsetMs,
          recDurationMs,
          recordingPeaks,
        );
      }
    }
    // ================================================================

    final overlapMode = _normalizedClipOverlapMode();
    final overlapByClip = overlapMode == 'off'
        ? _computeOverlapByClip()
        : List<bool>.filled(clips.length, false, growable: false);
    final crossfadeVisuals = _crossfadeModeActive(overlapMode)
        ? _computeCrossfadeVisuals(curveMode: overlapMode)
        : const <_ClipCrossfadeVisual>[];
    final draggingGroup = draggedClipIndex != null &&
        selectedClipIndices.length > 1 &&
        selectedClipIndices.contains(draggedClipIndex) &&
        draggedClipStartMs != null &&
        draggedClipRowIndex != null;
    final invalidDragRow = _invalidDragTargetRow(draggingGroup);
    if (invalidDragRow != null) {
      final y = _rowTopForIndex(invalidDragRow);
      final rect = Rect.fromLTWH(
        0,
        y,
        viewportWidth,
        _AudioCanvasTimelineState.kRowHeight,
      );
      final fill = Paint()..color = const Color(0x66FF4F5E);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xCCFFB1B8);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect.deflate(1), stroke);
    }

    // Draw clips
    // ... (Clip drawing logic remains the same, but _drawClip needs modification) ...
    for (int i = 0; i < clips.length; i++) {
      if (draggingGroup && selectedClipIndices.contains(i)) continue;
      if (!draggingGroup && i == draggedClipIndex) continue;
      _drawClip(canvas, i, false, overlapByClip);
    }
    if (draggingGroup) {
      for (final index in selectedClipIndices) {
        if (index < 0 || index >= clips.length) continue;
        _drawClip(canvas, index, true, overlapByClip);
      }
    } else if (draggedClipIndex != null) {
      _drawClip(canvas, draggedClipIndex!, true, overlapByClip);
    }
    _drawSelectedClipHandlesOverlay(canvas);
    _drawCrossfadeVisuals(canvas, crossfadeVisuals);
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

  bool _rowAllowsClip(int row, AudioTrack clip) {
    if (row < 0 || row >= rows.length) return false;
    final rowIsInstrument = rows[row].isInstrumentLane;
    return rowIsInstrument ? clip.isMidi : !clip.isMidi;
  }

  int? _invalidDragTargetRow(bool draggingGroup) {
    final targetRow = draggedClipRowIndex;
    if (draggedClipIndex == null ||
        targetRow == null ||
        targetRow < 0 ||
        targetRow >= rows.length) {
      return null;
    }
    if (draggingGroup) {
      final origin = clips[draggedClipIndex!];
      final deltaRows = targetRow - origin.rowIndex;
      for (final index in selectedClipIndices) {
        if (index < 0 || index >= clips.length) continue;
        final clip = clips[index];
        final row = (clip.rowIndex + deltaRows).clamp(0, rows.length - 1);
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
    final msPerBar = (60000 / bpm) * beatsPerBar;
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
        final isBeatBoundary = (sub * beatsPerBar) % subdivisions == 0;

        if (subX >= 0 && subX <= viewportWidth) {
          canvas.drawLine(
            Offset(subX, 0),
            Offset(subX, size.height),
            isBeatBoundary ? beatPaint : minorPaint,
          );
        }
      }
    }
  }

  List<bool> _computeOverlapByClip() {
    const double overlapEpsilonMs = 0.5;
    final overlap = List<bool>.filled(clips.length, false, growable: false);
    if (clips.length < 2) return overlap;
    final draggingGroup = draggedClipIndex != null &&
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

    for (int i = 0; i < clips.length; i++) {
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
          overlap[span.index] = true;
          if (furthestIndex >= 0) {
            overlap[furthestIndex] = true;
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
    if (clips.length < 2) return visuals;
    final draggingGroup = draggedClipIndex != null &&
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
    for (int i = 0; i < clips.length; i++) {
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
      final left = (visual.startMs - scrollOffsetMs) * pixelsPerMs;
      final right = (visual.endMs - scrollOffsetMs) * pixelsPerMs;
      if (right < -leftExtension || left > viewportWidth) continue;
      final top = _rowTopForIndex(visual.row) + 2.0;
      const height = _AudioCanvasTimelineState.kRowHeight - 4.0;
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
              insetRect.left + (insetRect.width * 0.5), insetRect.center.dy)
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
      Canvas canvas, int index, bool isDragging, List<bool> overlapByClip) {
    final clip = clips[index];
    final draggingGroup = draggedClipIndex != null &&
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

    final yOffset = _rowTopForIndex(row);

    // visual left follows the new startMs
    final x = (startMs - scrollOffsetMs) * pixelsPerMs;
    final y =
        yOffset + 2; //final y = row * _AudioCanvasTimelineState.kRowHeight;
    final width = visualDuration * pixelsPerMs;
    const double height = _AudioCanvasTimelineState.kRowHeight - 4;

    // Skip if completely off-screen
    final leftExtension = leftVisibleExtensionPx ?? 0.0;
    if (x + width < -leftExtension || x > viewportWidth) return;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, width, height), // Use calculated y
      const Radius.circular(6),
    );
    final hasOverlap =
        index >= 0 && index < overlapByClip.length && overlapByClip[index];
    final isMidi = clip.clipKind == ClipKind.midi;
    final isSelected = selectedClipIndices.contains(index);
    final isLoopPreview = clipLoopPreviewClipIndex == index;
    final showEdgeHandles =
        selectedClipIndices.length <= 1 && index == selectedClipIndex;

    // Draw clip background
    final clipPaint = Paint()
      ..color = hasOverlap
          ? const Color(0xFFC06767)
          : (isMidi
              ? (isSelected ? _kTimelineClipMidiSelected : _kTimelineClipMidi)
              : (isSelected
                  ? _kTimelineClipAudioSelected
                  : _kTimelineClipAudio));

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
      final rawVisibleMs =
          (trimEndMs - trimStartMs).clamp(1.0, double.infinity);
      final timelineVisibleMs =
          getTimelineDurationMs(clip).clamp(1.0, double.infinity);
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
      final startX = rect.left +
          ((previewStart - clipStartMs) / visualDuration) * rect.width;
      final nowX = rect.left +
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
      borderPaint.color = isSelected
          ? _kTimelineClipAudioSelectedBorder
          : _kTimelineClipAudioBorder;
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
    final startMs = getStartMs(clip);
    final trimStartMs = getTrimStartMs(clip);
    final trimEndMs = getTrimEndMs(clip);
    final visualDuration = getTimelineDurationMs(clip);
    final x = (startMs - scrollOffsetMs) * pixelsPerMs;
    final y = _rowTopForIndex(clip.rowIndex) + 2;
    final width = visualDuration * pixelsPerMs;
    const double height = _AudioCanvasTimelineState.kRowHeight - 4;
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

  Color _automationColorForTarget(
    String targetId, {
    bool isOrphan = false,
  }) {
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

    final points = clip.points
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
      final rect = visual.rect;
      final leftExtension = leftVisibleExtensionPx ?? 0.0;
      if (rect.right <= -leftExtension ||
          rect.left >= viewportWidth ||
          rect.bottom <= 0 ||
          rect.top >= size.height) {
        continue;
      }

      final clipped =
          rect.intersect(Rect.fromLTWH(0, 0, viewportWidth, size.height));
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

        final handleWidth =
            math.min(22.0, math.max(14.0, clipped.width * 0.22));
        final handleHeight =
            math.min(20.0, math.max(14.0, clipped.height - 8.0));
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
                Offset(centerX + dx, centerY + dy), 1.0, dotPaint);
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
      double stretchScale,
      {required double gainScale,
      required bool isReversed}) {
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
    final visibleLeft =
        rect.left.clamp(-leftExtension, viewportWidth).toDouble();
    final visibleRight =
        rect.right.clamp(-leftExtension, viewportWidth).toDouble();
    if (visibleRight <= visibleLeft) return;

    final waveformPaint = Paint()
      ..color = const Color(0xFFF4F7FA).withValues(alpha: 0.78)
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

      final clampedStartMs =
          startSourceMs.clamp(0.0, safeFullDurationMs).toDouble();
      final clampedEndMs =
          endSourceMs.clamp(clampedStartMs, safeFullDurationMs).toDouble();

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

  void _drawMidiPreview(Canvas canvas, RRect rect, List<MidiNote> notes,
      double trimStartMs, double trimEndMs,
      {required double sourceBpm}) {
    final beatMs =
        (60000.0 / sourceBpm.clamp(1.0, 1000000.0)).clamp(1.0, 1000000.0);
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
      final pitchNorm = ((note.pitch.clamp(minPitch, maxPitch) - minPitch) /
              (maxPitch - minPitch))
          .toDouble();
      final y = rect.bottom - (pitchNorm * height) - 4.0;

      final alpha = (140 + (note.velocity.clamp(0.0, 1.0) * 90)).round();
      previewPaint.color = Color.fromARGB(alpha, 168, 228, 178);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x,
            y.clamp(rect.top + 2.0, rect.bottom - 8.0),
            w,
            5.0,
          ),
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
        textDirection: TextDirection.ltr, maxLines: 1, ellipsis: "…");

    tp.text = TextSpan(
      text: labelName,
      style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white),
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
          4), //TODO: think about making this not circular and have squared corner
    );

    final bgPaint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.26);

    canvas.save();
    canvas.clipRRect(rect);
    canvas.drawRRect(bgRect, bgPaint);
    // Draw text centered vertically within the label area
    tp.paint(
        canvas,
        Offset(labelLeft + horizontalPadding,
            rect.top + (labelHeight - tp.height) / 2));
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
    const double rulerHeight = _AudioCanvasTimelineState.kRulerHeight;
    final glowPaint = Paint()
      ..color = const Color.fromRGBO(240, 169, 87, 0.22)
      ..strokeWidth = 4;
    final paint = Paint()
      ..color = const Color(0xFFF0A957)
      ..strokeWidth = 1.5;
    final blockedRanges = <Offset>[];
    double rowTop = 0.0;
    for (int row = 0; row < rowExpanded.length; row++) {
      final rowHeight = _AudioCanvasTimelineState.kRowHeight;
      final automationLaneHeight = _automationLaneHeightForRow(row);
      final expandedHeight =
          row < expandedHeights.length ? expandedHeights[row] : 0.0;
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

    final clipStartMs = getStartMs(clip);
    final clipEndMs = clipStartMs + getTimelineDurationMs(clip);
    if (clipEndMs <= clipStartMs) return;

    final clampedCutMs = cutPreviewMs!.clamp(clipStartMs, clipEndMs).toDouble();
    final x = (clampedCutMs - scrollOffsetMs) * pixelsPerMs;
    if (x < 0 || x > viewportWidth) return;

    final yOffset = _rowTopForIndex(row);

    final top = yOffset + 3;
    final bottom = yOffset + _AudioCanvasTimelineState.kRowHeight - 3;
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
  ) {
    if (recDurationMs <= 0 || peaks.isEmpty) return;

    final double left = recStartMs * msToPx;
    final double right = left + recDurationMs * msToPx;
    final double width = right - left;
    if (width <= 0) return;

    final paint = Paint()
      ..color = const Color(0xCCFF4A4A)
      ..style = PaintingStyle.fill;

    final double centerY = rowRect.center.dy;
    final double maxHeight = rowRect.height * 0.7;

    final Path path = Path();
    final int n = peaks.length;

    // TOP EDGE
    for (int i = 0; i < n; i++) {
      final double x = left + (i / (n - 1)) * width;
      final double amp = peaks[i].clamp(0.0, 1.0);
      final double y = centerY - amp * maxHeight * 0.5;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // BOTTOM EDGE (reverse)
    for (int i = n - 1; i >= 0; i--) {
      final double x = left + (i / (n - 1)) * width;
      final double amp = peaks[i].clamp(0.0, 1.0);
      final double y = centerY + amp * maxHeight * 0.5;
      path.lineTo(x, y);
    }

    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) {
    final loopPreviewVisible = clipLoopPreviewClipIndex != null ||
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
        scrollOffsetMs != old.scrollOffsetMs ||
        pixelsPerMs != old.pixelsPerMs ||
        viewportWidth != old.viewportWidth ||
        clipOverlapMode != old.clipOverlapMode ||
        (leftVisibleExtensionPx ?? 0.0) !=
            (old.leftVisibleExtensionPx ?? 0.0) ||
        selectedClipIndex != old.selectedClipIndex ||
        _selectedClipIndicesHash != old._selectedClipIndicesHash ||
        draggedClipIndex != old.draggedClipIndex ||
        draggedClipStartMs != old.draggedClipStartMs ||
        draggedClipRowIndex != old.draggedClipRowIndex ||
        _rowKindHash != old._rowKindHash ||
        _rowExpandedHash != old._rowExpandedHash ||
        _expandedTabHash != old._expandedTabHash ||
        _effectsPanelHeightsHash != old._effectsPanelHeightsHash ||
        _expandedHeightsHash != old._expandedHeightsHash ||
        _automationLaneHeightsHash != old._automationLaneHeightsHash ||
        stretchToolActive != old.stretchToolActive ||
        trimClipIndex != old.trimClipIndex ||
        _clipDataHash != old._clipDataHash ||
        _automationClipHash != old._automationClipHash ||
        quantizeDivisions != old.quantizeDivisions ||
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
        _recordingPeaksHash != old._recordingPeaksHash;
  }
}

// === Custom painter for the ruler ===
class _RulerPainter extends CustomPainter {
  final double pixelsPerMs;
  final double scrollOffsetMs;
  final double viewportWidth;
  final double bpm;
  final int beatsPerBar;
  final int quantizeDivisions;
  _RulerPainter({
    required this.pixelsPerMs,
    required this.scrollOffsetMs,
    required this.viewportWidth,
    required this.bpm,
    required this.beatsPerBar,
    required this.quantizeDivisions,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
        textDirection: TextDirection.ltr, textAlign: TextAlign.center);
    final msPerBar = (60000 / bpm) * beatsPerBar;
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
    while (
        barLabelStride * pxPerBar < minLabelSpacingPx && barLabelStride < 512) {
      barLabelStride *= 2;
    }

    for (int bar = startBar; bar <= endBar; bar++) {
      final barMs = bar * msPerBar;
      // === FIX ===: Removed offset
      final x = (barMs - scrollOffsetMs) * pixelsPerMs;
      if (x >= 0 && x <= viewportWidth) {
        // Draw major tick
        canvas.drawLine(Offset(x, size.height - 15), Offset(x, size.height),
            majorTickPaint);
        // Draw bar number ONLY if stride matches
        if (bar % barLabelStride == 0) {
          textPainter.text = TextSpan(
            text: '${bar + 1}',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(x - textPainter.width / 2, 5));
        }
      }
      // Draw quantize subdivisions within the bar.
      for (int sub = 1; sub < subdivisions; sub++) {
        final subMs = barMs + sub * msPerSubdivision;
        final subX = (subMs - scrollOffsetMs) * pixelsPerMs;
        final isBeatBoundary = (sub * beatsPerBar) % subdivisions == 0;
        if (subX >= 0 && subX <= viewportWidth) {
          final tickTop = isBeatBoundary ? size.height - 10 : size.height - 8;
          final tickPaint = isBeatBoundary ? majorTickPaint : minorTickPaint;
          canvas.drawLine(
            Offset(subX, tickTop),
            Offset(subX, size.height),
            tickPaint,
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
        quantizeDivisions != oldDelegate.quantizeDivisions;
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
  final double targetMin;
  final double targetMax;
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
    required this.targetMin,
    required this.targetMax,
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
        targetMin: widget.targetMin,
        targetMax: widget.targetMax,
        isVolumeLane: widget.isVolumeLane,
      );

  double _timeToPx(double timeMs) =>
      (timeMs - widget.scrollOffsetMs) * widget.pixelsPerMs;

  double _pxToTime(double px) =>
      (px / widget.pixelsPerMs) + widget.scrollOffsetMs;

  double _volumeToPy(double v) => verticalPadding + (1.0 - v) * _usableHeight;

  double _pyToVolume(double py) {
    double v = 1.0 - ((py - verticalPadding) / _usableHeight);
    return v.clamp(0.0, 1.0);
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
              '${L10n.translate(context, 'Copied automation value')} ${_pointValueLabel(index)}')),
    );
  }

  void _pastePointValue(int index) {
    final clipboard = _pointClipboard;
    if (clipboard == null) return;
    if (!clipboard.isCompatibleWith(_valueFormatter)) return;
    final normalized =
        _valueFormatter.normalizedForRawValue(clipboard.rawValue);
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
              onTap:
                  canPaste ? () => Navigator.pop(sheetContext, 'paste') : null,
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
                _AutomationPointPanGestureRecognizer>(
          // 1) Constructor
          () => _AutomationPointPanGestureRecognizer(
            shouldAcceptGlobalPosition: (globalPosition) {
              final renderObject = context.findRenderObject();
              if (renderObject is! RenderBox) return false;
              final localPosition = renderObject.globalToLocal(globalPosition);
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
                _AutomationLaneBackgroundHorizontalDragRecognizer>(
          () => _AutomationLaneBackgroundHorizontalDragRecognizer(
            shouldAcceptGlobalPosition: (globalPosition) {
              final renderObject = context.findRenderObject();
              if (renderObject is! RenderBox) return false;
              final localPosition = renderObject.globalToLocal(globalPosition);
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
            targetMin: widget.targetMin,
            targetMax: widget.targetMax,
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
  final double targetMin;
  final double targetMax;
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
    required this.targetMin,
    required this.targetMax,
    required this.isVolumeLane,
    required this.highlightStartMs,
    required this.highlightEndMs,
  });

  double get _usableHeight => laneHeight - verticalPadding * 2;

  double _timeToPx(double timeMs) => (timeMs - scrollOffsetMs) * pixelsPerMs;

  double _volumeToPy(double v) => verticalPadding + (1.0 - v) * _usableHeight;

  double _normalizedToTargetValue(double normalized) {
    final span = targetMax - targetMin;
    if (!span.isFinite || span.abs() < 1e-9) {
      return normalized.clamp(0.0, 1.0).toDouble();
    }
    return targetMin + span * normalized.clamp(0.0, 1.0).toDouble();
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
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }

  String get _targetContext {
    return '${targetLabel.trim().toLowerCase()} ${targetParamId.trim().toLowerCase()}';
  }

  _AutomationValueKind get _valueKind {
    if (isVolumeLane) return _AutomationValueKind.volumeDb;

    final context = _targetContext;
    final min = targetMin;
    final max = targetMax;
    final span = max - min;
    final hasValidRange = span.isFinite && span.abs() >= 1e-9;
    final looksNormalizedRange = min >= -0.001 && max <= 1.001;
    final looksPercentRange = min >= -0.1 && max <= 100.1;

    if (_containsAny(context, const [
          'freq',
          'frequency',
          'cutoff',
          'hz',
          'highpass',
          'lowpass',
          'band'
        ]) ||
        (hasValidRange && min >= 0.0 && max >= 1500.0 && max <= 50000.0)) {
      return _AutomationValueKind.hz;
    }

    if (_containsAny(context, const [
      'attack',
      'release',
      'decay',
      'delay',
      'predelay',
      'pre-delay',
      'pre delay',
      'hold',
      'time',
      'ms',
      'sec',
      'second'
    ])) {
      if (_containsAny(context, const ['ms', 'millisecond']) ||
          (hasValidRange && max > 20.0)) {
        return _AutomationValueKind.milliseconds;
      }
      return _AutomationValueKind.seconds;
    }

    if (_containsAny(context, const ['semitone', 'semi-tone'])) {
      return _AutomationValueKind.semitone;
    }
    if (_containsAny(context, const ['cents'])) {
      return _AutomationValueKind.cents;
    }
    if (_containsAny(context, const ['ratio'])) {
      return _AutomationValueKind.ratio;
    }

    final hasDbHint =
        _containsAny(context, const ['db', 'threshold', 'ceiling']);
    final hasGainHint = _containsAny(
      context,
      const ['gain', 'level', 'trim', 'makeup', 'boost', 'attenuation'],
    );
    if (hasDbHint || (hasGainHint && (min < 0.0 || max > 2.5))) {
      return _AutomationValueKind.db;
    }

    final hasPercentHint = _containsAny(
      context,
      const [
        'mix',
        'wet',
        'dry',
        'amount',
        'depth',
        'feedback',
        'width',
        'pan',
        '%'
      ],
    );
    if (looksPercentRange && (hasPercentHint || looksNormalizedRange)) {
      return _AutomationValueKind.percent;
    }

    return _AutomationValueKind.generic;
  }

  double get _midGuideNormalized => isVolumeLane ? 0.75 : 0.5;

  double _volToDb(double v) {
    if (v <= 0.0001) return double.negativeInfinity;
    final clamped = v.clamp(0.0, 1.0).toDouble();
    final gain =
        clamped >= 0.75 ? (1.0 + ((clamped - 0.75) / 0.25)) : (clamped / 0.75);
    if (gain <= 0.0001) return double.negativeInfinity;
    return 20 * math.log(gain) / math.log(10);
  }

  String _formatValueLabel(double normalized) {
    final clamped = normalized.clamp(0.0, 1.0).toDouble();

    if (isVolumeLane) {
      final db = _volToDb(clamped);
      if (db.isInfinite) return '-∞';
      final value = _formatNumber(db.abs(), maxDecimals: 1);
      final sign = db >= 0 ? '+' : '-';
      return '$sign$value dB';
    }

    final raw = _normalizedToTargetValue(clamped);
    switch (_valueKind) {
      case _AutomationValueKind.volumeDb:
        final db = _volToDb(clamped);
        if (db.isInfinite) return '-∞';
        final value = _formatNumber(db.abs(), maxDecimals: 1);
        final sign = db >= 0 ? '+' : '-';
        return '$sign$value dB';
      case _AutomationValueKind.percent:
        final min = targetMin;
        final max = targetMax;
        final looksNormalizedRange = min >= -0.001 && max <= 1.001;
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
        return _formatNumber(raw, maxDecimals: 2);
    }
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
    final hasHighlightWindow = highlightStartMs != null &&
        highlightEndMs != null &&
        highlightEndMs! > highlightStartMs!;

    // 1) Lane background
    final bg = Paint()..color = const Color.fromRGBO(111, 117, 123, 0.34);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(0)),
        bg);

    // Horizontal guide lines
    final guidePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;

    final topY = _volumeToPy(1.0);
    final middleY = _volumeToPy(_midGuideNormalized);
    final bottomY = _volumeToPy(0.0);

    canvas.drawLine(
        Offset(axisWidth, topY), Offset(size.width, topY), guidePaint);
    canvas.drawLine(
        Offset(axisWidth, middleY), Offset(size.width, middleY), guidePaint);
    canvas.drawLine(
        Offset(axisWidth, bottomY), Offset(size.width, bottomY), guidePaint);

    // Y-axis labels on the very left
    final tp = TextPainter(textDirection: TextDirection.ltr);
    _paintAxisLabel(canvas, tp, _formatValueLabel(1.0), topY);
    _paintAxisLabel(
        canvas, tp, _formatValueLabel(_midGuideNormalized), middleY);
    _paintAxisLabel(canvas, tp, _formatValueLabel(0.0), bottomY);

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
        _volumeToPy(p.volume),
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
        old.targetMin != targetMin ||
        old.targetMax != targetMax ||
        old.highlightStartMs != highlightStartMs ||
        old.highlightEndMs != highlightEndMs ||
        old.isVolumeLane != isVolumeLane;
  }
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

class _AutomationValueFormatter {
  final String targetLabel;
  final String targetParamId;
  final double targetMin;
  final double targetMax;
  final bool isVolumeLane;

  const _AutomationValueFormatter({
    required this.targetLabel,
    required this.targetParamId,
    required this.targetMin,
    required this.targetMax,
    required this.isVolumeLane,
  });

  String get signature =>
      '${targetLabel.trim().toLowerCase()}|${targetParamId.trim().toLowerCase()}|$targetMin|$targetMax|$isVolumeLane';

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

  String get _targetContext {
    return '${targetLabel.trim().toLowerCase()} ${targetParamId.trim().toLowerCase()}';
  }

  _AutomationValueKind get valueKind {
    if (isVolumeLane) return _AutomationValueKind.volumeDb;

    final context = _targetContext;
    final min = targetMin;
    final max = targetMax;
    final span = max - min;
    final hasValidRange = span.isFinite && span.abs() >= 1e-9;
    final looksNormalizedRange = min >= -0.001 && max <= 1.001;
    final looksPercentRange = min >= -0.1 && max <= 100.1;

    if (_containsAny(context, const [
          'freq',
          'frequency',
          'cutoff',
          'hz',
          'highpass',
          'lowpass',
          'band'
        ]) ||
        (hasValidRange && min >= 0.0 && max >= 1500.0 && max <= 50000.0)) {
      return _AutomationValueKind.hz;
    }

    if (_containsAny(context, const [
      'attack',
      'release',
      'decay',
      'delay',
      'predelay',
      'pre-delay',
      'pre delay',
      'hold',
      'time',
      'ms',
      'sec',
      'second'
    ])) {
      if (_containsAny(context, const ['ms', 'millisecond']) ||
          (hasValidRange && max > 20.0)) {
        return _AutomationValueKind.milliseconds;
      }
      return _AutomationValueKind.seconds;
    }

    if (_containsAny(context, const ['semitone', 'semi-tone'])) {
      return _AutomationValueKind.semitone;
    }
    if (_containsAny(context, const ['cents'])) {
      return _AutomationValueKind.cents;
    }
    if (_containsAny(context, const ['ratio'])) {
      return _AutomationValueKind.ratio;
    }

    final hasDbHint =
        _containsAny(context, const ['db', 'threshold', 'ceiling']);
    final hasGainHint = _containsAny(
      context,
      const ['gain', 'level', 'trim', 'makeup', 'boost', 'attenuation'],
    );
    if (hasDbHint || (hasGainHint && (min < 0.0 || max > 2.5))) {
      return _AutomationValueKind.db;
    }

    final hasPercentHint = _containsAny(
      context,
      const [
        'mix',
        'wet',
        'dry',
        'amount',
        'depth',
        'feedback',
        'width',
        'pan',
        '%'
      ],
    );
    if (looksPercentRange && (hasPercentHint || looksNormalizedRange)) {
      return _AutomationValueKind.percent;
    }

    return _AutomationValueKind.generic;
  }

  double _volToDb(double value) {
    if (value <= 0.0001) return double.negativeInfinity;
    final clamped = value.clamp(0.0, 1.0).toDouble();
    final gain =
        clamped >= 0.75 ? (1.0 + ((clamped - 0.75) / 0.25)) : (clamped / 0.75);
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

  double rawValueForNormalized(double normalized) {
    final clamped = normalized.clamp(0.0, 1.0).toDouble();
    if (valueKind == _AutomationValueKind.volumeDb) {
      return _volToDb(clamped);
    }
    return _normalizedToTargetValue(clamped);
  }

  double normalizedForRawValue(double rawValue) {
    if (valueKind == _AutomationValueKind.volumeDb) {
      return _dbToVol(rawValue);
    }
    return _targetValueToNormalized(rawValue);
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

    final raw = _normalizedToTargetValue(clamped);
    switch (valueKind) {
      case _AutomationValueKind.volumeDb:
        final db = _volToDb(clamped);
        if (db.isInfinite) return '-∞';
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
        return _formatNumber(raw, maxDecimals: 2);
    }
  }

  String editableValueText(double normalized) => formatValueLabel(normalized);

  String get inputLabel {
    switch (valueKind) {
      case _AutomationValueKind.volumeDb:
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

    if (valueKind == _AutomationValueKind.volumeDb) {
      if (lower == '-∞' ||
          lower == '-inf' ||
          lower == 'inf-' ||
          lower == 'off') {
        return 0.0;
      }
      final db = _extractFirstNumber(lower);
      if (db == null) return null;
      return _dbToVol(db);
    }

    var parsed = _extractFirstNumber(lower);
    if (parsed == null) return null;

    switch (valueKind) {
      case _AutomationValueKind.volumeDb:
        return _dbToVol(parsed);
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

class PrettyStereoSlider extends StatefulWidget {
  final double value; // 0 to 1
  final ValueChanged<double> onChangeStart, onChanged, onChangeEnd;
  final VoidCallback? onLongPress;

  const PrettyStereoSlider({
    super.key,
    required this.value,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    this.onLongPress,
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

    canvas.drawLine(
      Offset(x, centerY - 8),
      Offset(x, centerY + 8),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SliderDefaultMarkerPainter oldDelegate) {
    return oldDelegate.positionFraction != positionFraction ||
        oldDelegate.color != color ||
        oldDelegate.edgeInset != edgeInset;
  }
}

class _PrettyStereoSliderState extends State<PrettyStereoSlider> {
  @override
  Widget build(BuildContext context) {
    const sliderThumbRadius = 11.0;
    const readoutWidth = 58.0;
    final readoutText = _panReadoutText(context, widget.value);

    return Row(
      children: [
        Text(
          '${L10n.translate(context, 'Pan')}:',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: widget.onLongPress,
            onDoubleTap: () {
              setState(() {
                widget.onChanged(0.5); // RESET to default
              });
            },
            child: SizedBox(
              height: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _SliderDefaultMarkerPainter(
                          positionFraction: 0.5,
                          color: Colors.white.withValues(alpha: 0.24),
                          edgeInset: sliderThumbRadius + 1,
                        ),
                      ),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: sliderThumbRadius),
                      overlayShape: SliderComponentShape.noOverlay,
                      showValueIndicator: ShowValueIndicator.onDrag,
                      valueIndicatorTextStyle: const TextStyle(
                        color: Color.fromARGB(255, 0, 0, 0),
                        fontSize: 12,
                      ),
                      activeTrackColor: const Color(0xFF4D5566),
                      inactiveTrackColor: const Color(0xFF4D5566),
                      thumbColor: const Color(0xFFB7BECC),
                    ),
                    child: Slider(
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
            ),
          ),
        ),
        SizedBox(
          width: readoutWidth,
          child: Text(
            readoutText,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
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
  });

  @override
  State<PrettyGainSlider> createState() => _PrettyGainSliderState();
}

class _PrettyGainSliderState extends State<PrettyGainSlider> {
  static const double _unityUi = 2.0;

  double get _unity => math.min(_unityUi, widget.maxValue);

  double _gainToDb(double sliderValue) {
    const dbMin = -60.0;
    const dbMax = 6.0;
    final clamped = sliderValue.clamp(0.0, widget.maxValue).toDouble();
    final unity = _unity;

    if (clamped <= unity) {
      final t = unity <= 0.0 ? 0.0 : (clamped / unity).clamp(0.0, 1.0);
      return dbMin + ((0.0 - dbMin) * t);
    }

    final t = (widget.maxValue <= unity)
        ? 0.0
        : ((clamped - unity) / (widget.maxValue - unity)).clamp(0.0, 1.0);
    return 0.0 + ((dbMax - 0.0) * t);
  }

  double _dbToGainUi(double dbValue) {
    const dbMin = -60.0;
    const dbMax = 6.0;
    final unity = _unity;
    final clampedDb = dbValue.clamp(dbMin, dbMax).toDouble();

    if (clampedDb <= 0.0) {
      final t = ((clampedDb - dbMin) / (0.0 - dbMin)).clamp(0.0, 1.0);
      return unity * t;
    }

    final t = (dbMax <= 0.0) ? 0.0 : (clampedDb / dbMax).clamp(0.0, 1.0);
    return unity + ((widget.maxValue - unity) * t);
  }

  double _gainUiToVisualValue(double gainUi) {
    const dbMin = -60.0;
    final unity = _unity;
    final db = _gainToDb(gainUi);

    if (db <= 0.0) {
      final ampMin = math.pow(10.0, dbMin / 20.0).toDouble();
      final amp = math.pow(10.0, db / 20.0).toDouble();
      final normalizedAmp =
          ((amp - ampMin) / (1.0 - ampMin)).clamp(0.0, 1.0).toDouble();
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

  double _gainUiToPercent(double gainUi) {
    final unity = _unity;
    if (unity <= 0.0) return 0.0;
    return ((gainUi.clamp(0.0, widget.maxValue).toDouble() / unity) * 100.0)
        .clamp(0.0, _maxPercent)
        .toDouble();
  }

  double get _maxPercent {
    final unity = _unity;
    if (unity <= 0.0) return 100.0;
    return (widget.maxValue / unity) * 100.0;
  }

  double _percentToGainUi(double percent) {
    final unity = _unity;
    final clampedPercent = percent.clamp(0.0, _maxPercent).toDouble();
    return ((clampedPercent / 100.0) * unity)
        .clamp(0.0, widget.maxValue)
        .toDouble();
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
    var percent = _gainUiToPercent(widget.value);
    final controller = TextEditingController(
      text: percent.round().toString(),
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
            L10n.translate(dialogContext, 'Set gain'),
            style: const TextStyle(color: Colors.white),
          ),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              void setPercent(double next) {
                percent = next.clamp(0.0, _maxPercent).toDouble();
                controller.text = percent.round().toString();
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                setDialogState(() {});
              }

              final dbText = _gainReadoutText(_percentToGainUi(percent));
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: L10n.translate(context, 'Decrease gain'),
                        onPressed: () => setPercent(percent - 5.0),
                        icon: const Icon(Icons.remove, color: Colors.white),
                      ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]')),
                          ],
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            suffixText: '%',
                            suffixStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                            helperText: '100% = 0 dB',
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
                            final parsed = double.tryParse(text.trim());
                            if (parsed == null || !parsed.isFinite) {
                              return;
                            }
                            percent = parsed.clamp(0.0, _maxPercent).toDouble();
                            setDialogState(() {});
                          },
                          onSubmitted: (text) {
                            Navigator.of(dialogContext)
                                .pop(double.tryParse(text.trim()));
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: L10n.translate(context, 'Increase gain'),
                        onPressed: () => setPercent(percent + 5.0),
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
                Navigator.of(dialogContext)
                    .pop(double.tryParse(controller.text.trim()));
              },
              child: Text(L10n.translate(dialogContext, 'Apply')),
            ),
          ],
        );
      },
    );
    if (submitted == null || !submitted.isFinite) return;
    _commitImmediateGain(_percentToGainUi(submitted));
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
    final visualValue = _gainUiToVisualValue(widget.value);
    final gainReadoutText = _gainReadoutText(widget.value);
    final unityVisualValue = _gainUiToVisualValue(_unity);
    final unityFraction = widget.maxValue <= 0.0
        ? 0.0
        : (unityVisualValue / widget.maxValue).clamp(0.0, 1.0).toDouble();

    return Row(
      children: [
        if (widget.showLabel)
          Text(L10n.translate(context, 'Gain:'),
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        if (widget.showLabel) const SizedBox(width: 6),

        // ⭐ FIX: Make slider stretch horizontally
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: widget.onLongPress,
            onDoubleTap: () {
              _commitImmediateGain(_unity); // reset to unity gain (0 dB)
            },
            child: SizedBox(
              height: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _SliderDefaultMarkerPainter(
                          positionFraction: unityFraction,
                          color: Colors.white.withValues(alpha: 0.24),
                          edgeInset: sliderThumbRadius + 1,
                        ),
                      ),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: sliderThumbRadius),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: widget.trackColor,
                      inactiveTrackColor: widget.inactiveTrackColor,
                      thumbColor: widget.thumbColor,
                    ),
                    child: Slider(
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
            ),
          ),
        ),

        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _showGainAdjustDialog();
            });
          },
          child: SizedBox(
            width: 50, // fixed width so slider never shifts
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
        ),

        // Text("+19 dB", style: TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
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

    final r =
        RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(3));
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
      c.drawLine(
        Offset(1, y),
        Offset(s.width - 1, y),
        tick,
      );
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
            ..shader =
                DbfsMeterVisuals.verticalGradient(opacity: 0.94).createShader(
              laneRect,
            ),
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
            ..shader =
                DbfsMeterVisuals.verticalGradient(opacity: 0.32).createShader(
              laneRect,
            ),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
