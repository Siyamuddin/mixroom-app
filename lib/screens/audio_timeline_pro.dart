import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'dart:math' as math;
import 'package:mixroom/models/models.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mixroom/widgets/effects_panel.dart';
import 'package:mixroom/widgets/sample_browser_panel.dart';
import 'package:mixroom/helpers/app_haptics.dart';

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

  const _SampleDropPlacement({
    required this.row,
    required this.startMs,
    required this.endMs,
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

extension _TimelineToolUi on _TimelineTool {
  String get label {
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
  final List<TimelineRow> rows;
  final List<AudioTrack> clips;
  final List<double> rowGain;
  final List<double> rowPan;
  final List<bool> rowMuted;
  final List<bool> rowSoloed;
  final List<List<AutomationPoint>> rowVolumeAutomation;

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
  final Future<void> Function(int row) onInsertRowAbove;
  final Future<void> Function(int row) onInsertRowBelow;
  final Future<void> Function(int row) onDeleteRow;
  final Future<void> Function(int fromIndex, int toIndex) onMoveRow;
  final Future<void> Function(int row, String name) onRenameRow;
  final Future<void> Function(int row, int iconId) onSetRowIcon;
  final Future<void> Function(int clipIndex, double newStartMs, int newRowIndex)
      onMoveClipCommit;
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
  final double playheadMs;
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
  final Future<void> Function(int clipIndex, double semitones) setClipPitch;
  final void Function(int clipIndex, double oldPitch, double newPitch)?
      onClipPitchCommit;
  final Future<void> Function(int clipIndex) onDisableClipTempoFollow;
  final Future<void> Function(int clipIndex) onAdjustClipToTempo;
  final Future<void> Function(int clipIndex) onStretchClipToTempoPreservePitch;
  final Future<void> Function(int clipIndex)
      onDetectClipTempoAndSetProjectTempo;
  final void Function(int clipIndex, double newTimelineDurationMs,
      {double? newStartMs}) onStretchClip;
  final Future<void> Function(int clipIndex) onStretchClipCommit;
  final Future<void> Function(int clipIndex, String label)? onRenameClip;
  final void Function(int clipIndex) onCopyClip;
  final Future<void> Function(int clipIndex) onDeleteClip;
  final bool hasCopiedClip;
  final void Function(int row, double timeMs) onPasteClipAt;
  final VoidCallback? onClearCopiedClip;
  final void Function(List<int> clipIndices)? onCopyClips;
  final Future<void> Function(List<int> clipIndices)? onDeleteClips;
  final Future<void> Function(int clipIndex, double cutTimeMs)? onCutClipAt;
  final void Function(int clipIndex)? onOpenMidiClip;
  final void Function(int loopStartMs, int loopEndMs)? onLoopRegionChanged;
  final void Function(bool enabled)? onLoopToggle;
  final void Function(int row, int effectIndex, String paramId,
      dynamic oldValue, dynamic newValue)? onPluginParamCommit;
  final void Function(RowEffectsSnapshot before, RowEffectsSnapshot after)?
      onPresetCommit;
  final void Function(void Function(int row) refreshRowFx)?
      registerRowFxRefresher;
  final void Function(bool magnetEnabled, int quantizeDivisionsPerBar)?
      onSnapSettingsChanged;

  final MeterBus meters;
  final Future<List<double>> Function(int row, int effectIndex)
      getRowCompressorMeter;
  final Future<List<double>> Function(int row, int effectIndex, int sampleCount)
      getRowEqWaveform;
  final Future<void> Function(SampleDragData data, int row, double timeMs)?
      onExternalSampleDrop;
  final VoidCallback? onExternalSampleDragEntered;
  final bool externalSampleDragActive;

  final String mode; // "Basic" or "Pro"

  const AudioCanvasTimeline({
    Key? key,
    required this.rows,
    required this.rowGain,
    required this.rowPan,
    required this.rowMuted,
    required this.rowSoloed,
    required this.rowVolumeAutomation,
    required this.clips,
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
    required this.onInsertRowAbove,
    required this.onInsertRowBelow,
    required this.onDeleteRow,
    required this.onMoveRow,
    required this.onRenameRow,
    required this.onSetRowIcon,
    required this.onMoveClipCommit,
    required this.onTrimClip,
    required this.onTrimClipCommit,
    required this.playheadMs,
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
    required this.setClipPitch,
    required this.onClipPitchCommit,
    required this.onDisableClipTempoFollow,
    required this.onAdjustClipToTempo,
    required this.onStretchClipToTempoPreservePitch,
    required this.onDetectClipTempoAndSetProjectTempo,
    required this.onStretchClip,
    required this.onStretchClipCommit,
    this.onRenameClip,
    required this.onCopyClip,
    required this.onDeleteClip,
    required this.hasCopiedClip,
    required this.onPasteClipAt,
    this.onClearCopiedClip,
    this.onCopyClips,
    this.onDeleteClips,
    this.onCutClipAt,
    this.onOpenMidiClip,
    this.onLoopRegionChanged,
    this.onLoopToggle,
    required this.mode,
    this.onPluginParamCommit,
    this.onPresetCommit,
    this.registerRowFxRefresher,
    this.onSnapSettingsChanged,
    required this.meters,
    required this.getRowCompressorMeter,
    required this.getRowEqWaveform,
    this.onExternalSampleDrop,
    this.onExternalSampleDragEntered,
    this.externalSampleDragActive = false,
  }) : super(key: key);
  @override
  State<AudioCanvasTimeline> createState() => _AudioCanvasTimelineState();
}

class _AudioCanvasTimelineState extends State<AudioCanvasTimeline> {
  static const double kRowHeight = 80.0;
  static const double kExpandedRowHeight = kRowHeight *
      3; // try to make this dynamic to fit in all the stuff in the expanded area (risk of vertical overflow if too small)
  static const double kHeaderFooterHeight = 48.0;
  static const double kBottomInteractionPadding = 96.0;
  final List<double> _effectsPanelHeights = <double>[];

  static const double kHeaderWidth = 80.0;
  static const double kRulerHeight = 40.0;
  static const double kTrimHandleWidth = 12.0;
  static const double kTrimHitboxPadding =
      20.0; // === FIX ===: New constant for larger hitbox
  double _pixelsPerMs = 0.1; // Initial zoom level
  double _scrollOffsetMs = 0.0;
  int _selectedClipIndex = -1;
  final Set<int> _selectedClipIndices = <int>{};
  int _selectedRowIndex = 0;
  // final List<bool> _rowMuted = List.filled(kNumRows, false);
  final List<bool> _rowExpanded = <bool>[];
  final List<int> _expandedTab = <int>[]; // 0 = Volume, 1 = Effects
  final List<double> _rowYPositions = [];

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

  bool _pendingDrag = false;
  Offset? _pendingLocalDown;
  int _pendingClipIndex = -1;

  // Paste popup state
  bool _showPastePopup = false;
  int? _pasteRow;
  double? _pasteMs;
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
  final Set<String> _paintStrokeKeys = <String>{};
  bool _paintStrokeActive = false;
  int? _paintStrokeRow;
  double? _paintLastFingerMs;
  double? _paintLastPasteStartMs;
  double? _paintLastPasteEndMs;
  double? _paintClipDurationEstimateMs;
  final List<_PendingPaintPaste> _pendingPaintPastes = <_PendingPaintPaste>[];
  DateTime? _lastPaintClipboardHintAt;
  bool _deleteStrokeActive = false;
  final Set<int> _deleteStrokeClipObjectIds = <int>{};
  int? _cutPreviewClipIndex;
  double? _cutPreviewRawMs;
  double? _cutPreviewMs;

  bool _magnetEnabled = false;
  int _quantizeDivisionsPerBar = 4; // default: 1/4 note (legacy behavior)
  int? _highlightedSegmentRow;
  double? _highlightedSegmentStartMs;
  double? _highlightedSegmentEndMs;
  bool _loopEnabled = false;
  int?
      _loopStartMs; // made ints because when dragging loop handles, can get sub-ms numbers, but audio_editor converts to int
  int? _loopEndMs;
  bool _draggingLoopStart = false;
  bool _draggingLoopEnd = false;
  bool _draggingLoopRegion = false;
  bool _creatingLoopRegion = false;
  double? _loopDragOffsetMs;
  double? _loopCreateAnchorMs;
  double? _loopDragRegionFingerAnchorMs;
  int? _loopDragRegionStartAnchorMs;
  int? _loopDragRegionEndAnchorMs;

  double? _gainDragStart;
  double? _panDragStart;

  // for updating the UI of the effects when JUCE state has changed
  final Map<int, VoidCallback> _rowEffectRefreshers = {};
  Timer? _headerHoldTimer;
  Timer? _magnetHoldTimer;
  static const Duration _rowMenuHoldDelay = Duration(milliseconds: 140);
  static const double _headerTapMoveTolerance = 12.0;
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
  bool _magnetMenuShownFromHold = false;
  Offset? _magnetDownGlobalPos;
  final GlobalKey _externalSampleDropTargetKey = GlobalKey();
  int? _externalSampleDropRow;
  double? _externalSampleDropStartMs;
  double? _externalSampleDropEndMs;
  bool _externalSampleDragInsideTimeline = false;

  void _notifySnapSettingsChanged() {
    widget.onSnapSettingsChanged
        ?.call(_magnetEnabled, _quantizeDivisionsPerBar);
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
      _activeTrimHandleX = null;
      _trimClipIndex = null;
      _stretchClipIndex = null;
      _stretchStartTimelineDurationMs = null;
      _stretchOriginalStartMs = null;
      _stretchStartAnchorX = null;
      _stretchDurationUpdateMs = null;
    });
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

  void _onTimelinePointerDown(PointerDownEvent event) {
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

  void _onTimelinePointerUp(PointerUpEvent event) {
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
    if (_activeTool == _TimelineTool.paint) {
      _isUserInteracting = false;
      _interactionMode = '';
      _resetPaintStrokeState();
      return;
    }
    if (_activeTool == _TimelineTool.delete) {
      _resetDeleteStrokeState();
    }
  }

  void _onTimelinePointerCancel(PointerCancelEvent event) {
    if (_activeTool == _TimelineTool.cut) {
      _clearCutPreview();
      return;
    }
    if (_activeTool == _TimelineTool.paint) {
      _isUserInteracting = false;
      _interactionMode = '';
      _resetPaintStrokeState();
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
      color: const Color(0xFF1D2435),
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check, size: 16, color: Color(0xFF7FA7FF)),
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
      color: const Color(0xFF1D2435),
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  tool.label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check, size: 16, color: Color(0xFF7FA7FF)),
            ],
          ),
        );
      }).toList(),
    );

    if (selected == null || !mounted || selected == _activeTool) return;
    setState(() {
      _activeTool = selected;
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
    _selectedClipIndex = -1;
    _selectedClipIndices.clear();
    _clipPopupMs = null;
  }

  void _setSingleClipSelection(int clipIndex, {double? popupMs}) {
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
  }

  int? _rowForLocalY(double localY) {
    if (_rowCount <= 0) return null;
    double currentY = 0;
    for (int i = 0; i < _rowCount; i++) {
      double rowTotalHeight = kRowHeight;
      if (_rowExpanded[i]) {
        rowTotalHeight += (_expandedTab[i] == 0)
            ? kExpandedRowHeight
            : _effectsPanelHeights[i];
      }
      if (localY >= currentY && localY < currentY + rowTotalHeight) {
        return i;
      }
      currentY += rowTotalHeight;
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
    return _SampleDropPlacement(row: row, startMs: startMs, endMs: endMs);
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
        _externalSampleDropEndMs == placement.endMs) {
      return true;
    }
    setState(() {
      _externalSampleDropRow = placement.row;
      _externalSampleDropStartMs = placement.startMs;
      _externalSampleDropEndMs = placement.endMs;
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
      return;
    }
    _selectedClipIndex = _selectedClipIndices.reduce((a, b) => a > b ? a : b);
    _clipPopupMs = null;
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
        const SnackBar(
          content: Text('No copied clip to paint'),
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
    if (!widget.hasCopiedClip) return false;
    final startMs = _nextPaintStartForRow(row, desiredStartMs);
    final key = '$row:${startMs.round()}';
    if (_paintStrokeKeys.contains(key)) return false;

    final duration = _paintEstimatedClipDurationMs();
    _paintStrokeKeys.add(key);
    _pendingPaintPastes.add(_PendingPaintPaste(row: row, startMs: startMs));
    widget.onPasteClipAt(row, startMs);
    _paintLastPasteStartMs = startMs;
    _paintLastPasteEndMs = startMs + duration;
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

    if (!_magnetEnabled &&
        _pendingPaintPastes.isNotEmpty &&
        !resolvedLastPasteFromTimeline) {
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
    final expandedOffset = _rowYPositions[row] + kRowHeight;
    final usableHeight = kExpandedRowHeight - 24;
    return expandedOffset + 12 + (1 - v) * usableHeight;
  }

  final ScrollController _verticalScrollController = ScrollController();
  double _verticalScrollOffset = 0.0;

  double get _maxDurationMs => widget.maxDuration.inMilliseconds.toDouble();
  int get _rowCount => widget.rows.length;

  @override
  void initState() {
    super.initState();
    _syncRowUiState();
    _verticalScrollController.addListener(() {
      setState(() {
        _verticalScrollOffset = _verticalScrollController.offset;
      });
    });
    widget.registerRowFxRefresher?.call(_refreshRowFx);
    _notifySnapSettingsChanged();
  }

  @override
  void didUpdateWidget(covariant AudioCanvasTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clips.length != widget.clips.length) {
      _syncSelectionAfterClipTopologyChange();
      if (_pendingPaintPastes.isNotEmpty) {
        for (final pending in _pendingPaintPastes) {
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
            break;
          }
        }
        _pendingPaintPastes.clear();
      }
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
    _cancelMagnetHoldTimer();
    _verticalScrollController.dispose();
    super.dispose();
  }

  bool _isHoldEligibleInHeader(Offset localPos) {
    final bool onMuteArea =
        localPos.dx >= (kHeaderWidth - 30) && localPos.dy <= 30;
    final bool onSoloArea =
        localPos.dx >= (kHeaderWidth - 30) && localPos.dy >= (kRowHeight - 30);
    return !(onMuteArea || onSoloArea);
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

  void _handleHeaderTapSelectionAndExpand(int tappedRow) {
    final wasSelected = tappedRow == _selectedRowIndex;
    final oldExpanded = List<bool>.from(_rowExpanded);

    setState(() {
      if (!wasSelected) {
        _selectedRowIndex = tappedRow;
        widget.onSelectRow(tappedRow);
        for (int i = 0; i < _rowExpanded.length; i++) {
          _rowExpanded[i] = false;
        }
        return;
      }

      final shouldExpand = !_rowExpanded[tappedRow];
      for (int i = 0; i < _rowExpanded.length; i++) {
        _rowExpanded[i] = shouldExpand && i == tappedRow;
      }
    });

    for (int i = 0; i < oldExpanded.length && i < _rowExpanded.length; i++) {
      if (oldExpanded[i] != _rowExpanded[i]) {
        widget.onToggleExpanded(i);
      }
    }
  }

  void _syncRowUiState() {
    while (_rowExpanded.length < _rowCount) {
      _rowExpanded.add(false);
      _expandedTab.add(0);
      _effectsPanelHeights.add(kExpandedRowHeight);
    }
    if (_rowExpanded.length > _rowCount) {
      _rowExpanded.removeRange(_rowCount, _rowExpanded.length);
      _expandedTab.removeRange(_rowCount, _expandedTab.length);
      _effectsPanelHeights.removeRange(_rowCount, _effectsPanelHeights.length);
    }
    if (_selectedRowIndex >= _rowCount) {
      _selectedRowIndex = _rowCount == 0 ? -1 : _rowCount - 1;
    }
  }

  void _reconcileRowUiStateByRowId(List<TimelineRow> oldRows) {
    final oldExpandedById = <int, bool>{};
    final oldTabById = <int, int>{};
    final oldEffectsHeightById = <int, double>{};

    for (int i = 0; i < oldRows.length; i++) {
      final id = oldRows[i].rowId;
      if (i < _rowExpanded.length) oldExpandedById[id] = _rowExpanded[i];
      if (i < _expandedTab.length) oldTabById[id] = _expandedTab[i];
      if (i < _effectsPanelHeights.length) {
        oldEffectsHeightById[id] = _effectsPanelHeights[i];
      }
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
            .map((r) => oldTabById[r.rowId] ?? 0)
            .toList(growable: false),
      );
    _effectsPanelHeights
      ..clear()
      ..addAll(
        widget.rows
            .map((r) => oldEffectsHeightById[r.rowId] ?? kExpandedRowHeight)
            .toList(growable: false),
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

  // Helper to get the viewport width (the drawable timeline area)
  double _getViewportWidth(BuildContext context) {
    return MediaQuery.of(context).size.width - kHeaderWidth;
  }

  // Helper to get the playhead position in pixels (center of the viewport)
  double _getPlayheadPx(BuildContext context) {
    return _getViewportWidth(context) / 2;
  }

  double get _totalTimelineHeight {
    double total = _rowCount * kRowHeight;
    for (int i = 0; i < _rowCount; i++) {
      if (_rowExpanded[i]) {
        // total += kExpandedRowHeight;
        total += (_expandedTab[i] == 0)
            ? kExpandedRowHeight // volume tab always fixed
            : _effectsPanelHeights[i]; // effects tab dynamic
      }
    }
    return total;
  }

  double get _timelinePaintHeight => math.max(_totalTimelineHeight, kRowHeight);
  double get _scrollContentHeight =>
      _timelinePaintHeight + kHeaderFooterHeight + kBottomInteractionPadding;

  void _recalculateRowYPositions() {
    _rowYPositions.clear();

    double y = 0;
    for (int i = 0; i < _rowCount; i++) {
      _rowYPositions.add(y);
      y += kRowHeight;
      if (_rowExpanded[i]) {
        y += (_expandedTab[i] == 0)
            ? kExpandedRowHeight
            : _effectsPanelHeights[i];
      }
    }
  }

  double _automationLaneLocalY(double volume, double laneHeight) {
    const verticalPadding = 12.0;
    final usable = laneHeight - verticalPadding * 2;
    return verticalPadding + (1 - volume) * usable;
  }

  // ======================================================
  // AUTOMATION DRAG PRIORITY HANDLERS (inside timeline state)
  // ======================================================

  void _automationPanStart(int row, Offset pos, double laneHeight) {
    _automationBefore =
        widget.rowVolumeAutomation[row].map((p) => p.copy()).toList();

    // GIVE AUTOMATION PRIORITY RIGHT AWAY
    setState(() {
      _interactionMode = 'automation';
      _isUserInteracting = true;
    });

    if (!_rowExpanded[row]) return;
    if (_expandedTab[row] != 0) return;

    final lane = widget.rowVolumeAutomation[row];

    for (int i = 0; i < lane.length; i++) {
      final p = lane[i];

      // compute timeline-local px
      final px = (p.x - _scrollOffsetMs) * _pixelsPerMs;

      // compute LANE-local py
      final py = _automationLaneLocalY(p.volume, laneHeight);

      if ((pos - Offset(px, py)).distance < 20) {
        // compute the offset between finger and point Y
        final p = lane[i];
        final laneHeight = kExpandedRowHeight;
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

    final points = List<AutomationPoint>.from(widget.rowVolumeAutomation[row]);
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
    final laneHeight = kExpandedRowHeight;
    final usableHeight = laneHeight - verticalPadding * 2;

    // compensate for initial finger offset so there is NO jump
    final effectiveFingerY = pos.dy - (_automationFingerOffsetY ?? 0.0);

    // map finger Y → volume
    final normalized =
        1 - ((effectiveFingerY - verticalPadding) / usableHeight);
    p.volume = normalized.clamp(0.0, 1.0);

    if (_magnetEnabled) {
      if ((p.volume - 0.75).abs() < 0.03) {
        // small epsilon
        p.volume = 0.75;
      }
    }

    // Save
    widget.rowVolumeAutomation[row] = points;
    widget.setTrackAutomationPoints(
      row,
      points.map((p) => p.toMap()).toList(),
    ); // careful of doing on update, maybe better to do once on end
    setState(() {});
  }

  void _automationPanEnd(int row) {
    if (_interactionMode == 'automation') {
      final before = _automationBefore;
      final after = widget.rowVolumeAutomation[row];

      if (before != null && widget.onAutomationCommit != null) {
        widget.onAutomationCommit!(
            row, before, after.map((p) => p.copy()).toList());
      }

      _automationBefore = null;
      setState(() {
        _automationDragRow = null;
        _automationDragIndex = null;
        _interactionMode = '';
        _isUserInteracting = false;
        _automationFingerOffsetY = null;
      });
    }
  }

  Widget _buildInlineClipSheet(Widget child) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A2233).withOpacity(0.62),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: child,
        ),
      ),
    );
  }

  Color _clipControlAccent() => const Color(0xFF4D5566);

  Color _clipControlThumb() => const Color(0xFFB7BECC);

  String _clipTempoModeLabel(AudioTrack clip) {
    if (!clip.stretchToProjectTempo) return 'Tempo mode: Off';
    return clip.tempoStretchPreservePitch
        ? 'Tempo mode: Stretch (keep pitch)'
        : 'Tempo mode: Resample';
  }

  Color _clipTempoModeColor(AudioTrack clip) {
    if (!clip.stretchToProjectTempo) return Colors.white70;
    return clip.tempoStretchPreservePitch
        ? const Color(0xFFA8E9E1)
        : const Color(0xFFFFD5AA);
  }

  bool _isStretchToolForClip(AudioTrack clip) {
    return _activeTool == _TimelineTool.stretch && !clip.isMidi;
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
    final cardWidth = math.min(320.0, availableWidth);
    final panelHeight = isMidi ? 198.0 : 258.0;

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
    final thumbColor = _clipControlThumb();
    final tempoModeLabel = _clipTempoModeLabel(clip);
    final tempoModeColor = _clipTempoModeColor(clip);
    final clipName = clip.label.trim().isNotEmpty
        ? clip.label.trim()
        : (clip.isMidi ? 'MIDI Clip' : 'Audio Clip');

    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2233).withOpacity(0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    clipName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 18,
                    height: 18,
                  ),
                  splashRadius: 12,
                  onPressed: () => _openClipRenameDialog(clipIndex),
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: Colors.white70,
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 18,
                    height: 18,
                  ),
                  splashRadius: 12,
                  onPressed: _closeInlineClipControl,
                  icon: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            PrettyGainSlider(
              value: clip.gain.clamp(0.0, 3.0),
              trackColor: accentColor,
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
            const SizedBox(height: 6),
            Row(
              children: [
                const Text(
                  'Pitch:',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(width: 5),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Material(
                    color: Colors.transparent,
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: accentColor.withValues(alpha: 0.16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                          width: 0.8,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        splashColor: Colors.white.withValues(alpha: 0.12),
                        highlightColor: Colors.white.withValues(alpha: 0.05),
                        onTap: () {
                          final next =
                              (clip.pitchSemitones - 0.5).clamp(-12.0, 12.0);
                          clip.pitchSemitones = next;
                          unawaited(widget.setClipPitch(clipIndex, next));
                          if (mounted) setState(() {});
                        },
                        child: const Icon(
                          Icons.remove,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 5,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 11),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: accentColor,
                      inactiveTrackColor: accentColor.withOpacity(0.65),
                      thumbColor: thumbColor,
                    ),
                    child: Slider(
                      value: clip.pitchSemitones.clamp(-12.0, 12.0),
                      min: -12.0,
                      max: 12.0,
                      divisions: 48,
                      label:
                          '${clip.pitchSemitones >= 0 ? '+' : ''}${clip.pitchSemitones.toStringAsFixed(1)}st',
                      onChanged: (v) {
                        final next = v.clamp(-12.0, 12.0);
                        clip.pitchSemitones = next;
                        unawaited(widget.setClipPitch(clipIndex, next));
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Material(
                    color: Colors.transparent,
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: accentColor.withValues(alpha: 0.16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                          width: 0.8,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        splashColor: Colors.white.withValues(alpha: 0.12),
                        highlightColor: Colors.white.withValues(alpha: 0.05),
                        onTap: () {
                          final next =
                              (clip.pitchSemitones + 0.5).clamp(-12.0, 12.0);
                          clip.pitchSemitones = next;
                          unawaited(widget.setClipPitch(clipIndex, next));
                          if (mounted) setState(() {});
                        },
                        child: const Icon(
                          Icons.add,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${clip.pitchSemitones >= 0 ? '+' : ''}${clip.pitchSemitones.toStringAsFixed(1)}st',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                ),
              ],
            ),
            if (isMidi) ...[
              const SizedBox(height: 4),
              Text(
                'MIDI clips follow project BPM automatically.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                tempoModeLabel,
                style: TextStyle(
                  color: tempoModeColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          await widget.onDisableClipTempoFollow(clipIndex);
                          if (mounted) setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: !clip.stretchToProjectTempo
                                ? Colors.blueAccent.withOpacity(0.75)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Off',
                            style: TextStyle(
                              color: !clip.stretchToProjectTempo
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          await widget.onAdjustClipToTempo(clipIndex);
                          if (mounted) setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: clip.stretchToProjectTempo &&
                                    !clip.tempoStretchPreservePitch
                                ? Colors.blueAccent.withOpacity(0.75)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Resample',
                            style: TextStyle(
                              color: clip.stretchToProjectTempo &&
                                      !clip.tempoStretchPreservePitch
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          await widget
                              .onStretchClipToTempoPreservePitch(clipIndex);
                          if (mounted) setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: clip.stretchToProjectTempo &&
                                    clip.tempoStretchPreservePitch
                                ? Colors.blueAccent.withOpacity(0.75)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Stretch',
                            style: TextStyle(
                              color: clip.stretchToProjectTempo &&
                                      clip.tempoStretchPreservePitch
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await widget.onDetectClipTempoAndSetProjectTempo(clipIndex);
                    if (mounted) setState(() {});
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  icon: const Icon(Icons.auto_fix_high, size: 14),
                  label: const Text(
                    'Detect Tempo',
                    style: TextStyle(fontSize: 10.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openClipRenameDialog(int clipIndex) async {
    if (clipIndex < 0 || clipIndex >= widget.clips.length) return;
    final clip = widget.clips[clipIndex];
    final initialName = clip.label.trim().isNotEmpty
        ? clip.label.trim()
        : (clip.isMidi ? 'MIDI Clip' : 'Audio Clip');
    final controller = TextEditingController(text: initialName);

    final nextName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2233),
        title: const Text('Rename Clip', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 48,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Clip name',
            hintStyle: TextStyle(color: Colors.white54),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
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
        const SnackBar(
            content: Text('Tempo detection is only for audio clips.')),
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
                title: const Text(
                  'Adjust To Tempo (Resample)',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, 'adjust_resample'),
              ),
              ListTile(
                leading:
                    const Icon(Icons.drag_indicator, color: Color(0xFF2AAE9F)),
                title: const Text(
                  'Stretch To Tempo (Keep Pitch)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Stretch mode is shown with teal clip handles.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'adjust_stretch'),
              ),
              ListTile(
                leading: const Icon(Icons.auto_fix_high, color: Colors.white),
                title: const Text(
                  'Detect Tempo + Set Project BPM',
                  style: TextStyle(color: Colors.white),
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
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final iconColor = enabled ? color : color.withOpacity(0.45);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Center(
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }

  Widget _buildSelectedClipPopup(double viewportWidth, double viewportHeight) {
    final selectedIndices = _activeSelectedClipIndices();
    final hasSingleSelection = selectedIndices.length == 1;
    final singleSelectionIndex =
        hasSingleSelection ? selectedIndices.first : _selectedClipIndex;
    final bool visible = _selectedClipIndex >= 0 &&
        _selectedClipIndex < widget.clips.length &&
        _clipPopupMs != null;

    final rect = (visible ? _getClipRect(_selectedClipIndex) : null);
    final double popupWidth =
        math.min(116.0, math.max(84.0, viewportWidth - 8));
    const double popupHeight = 32;
    double left = kHeaderWidth;
    double top = -100;

    if (visible && rect != null) {
      final clipInTimelineX = rect.right >= 0 && rect.left <= viewportWidth;
      final clipInTimelineY = rect.bottom >= _verticalScrollOffset &&
          rect.top <= _verticalScrollOffset + viewportHeight;
      if (clipInTimelineX && clipInTimelineY) {
        final tapAnchorPx = (_clipPopupMs! - _scrollOffsetMs) * _pixelsPerMs;
        final minAnchorPx = rect.left + 6.0;
        final maxAnchorPx = rect.right - 6.0;
        final anchorPx = tapAnchorPx.isFinite
            ? tapAnchorPx
                .clamp(
                  minAnchorPx <= maxAnchorPx ? minAnchorPx : rect.left,
                  minAnchorPx <= maxAnchorPx ? maxAnchorPx : rect.right,
                )
                .toDouble()
            : (rect.left + rect.width / 2);
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
        final preferredAbove = rect.top - popupHeight - 4.0;
        final preferredBelow = rect.bottom + 4.0;
        if (preferredAbove >= minTop) {
          top = preferredAbove;
        } else if (preferredBelow <= maxTop) {
          top = preferredBelow;
        } else {
          top = preferredAbove.clamp(minTop, maxTop).toDouble();
        }
      }
    }

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        ignoring: !visible, // prevent clicks when invisible
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: Container(
            width: popupWidth,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            height: popupHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF000000).withOpacity(0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildClipPopupAction(
                    icon: Icons.copy,
                    color: Colors.white,
                    onTap: () {
                      _copySelectedClips();
                      setState(_clearClipSelection);
                    },
                  ),
                ),
                Container(width: 1, height: 16, color: Colors.white24),
                Expanded(
                  child: _buildClipPopupAction(
                    icon: Icons.tune,
                    color: Colors.white,
                    onTap: hasSingleSelection
                        ? () {
                            if (singleSelectionIndex >= 0) {
                              _openClipSettingsPanel(singleSelectionIndex);
                            }
                          }
                        : null,
                  ),
                ),
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
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPastePopup(double viewportWidth) {
    final bool visible =
        _showPastePopup && _pasteRow != null && _pasteMs != null;
    final bool showClearButton = widget.onClearCopiedClip != null;

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
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste,
                      size: 18, color: Colors.white),
                  onPressed: () {
                    if (_pasteRow != null && _pasteMs != null) {
                      widget.onPasteClipAt(_pasteRow!, _pasteMs!);
                    }
                    _clearPastePopup();
                  },
                ),
                if (showClearButton) ...[
                  Container(width: 1, height: 18, color: Colors.white24),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Clear clipboard',
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Color(0xFFFFA4A4)),
                    onPressed: () {
                      widget.onClearCopiedClip?.call();
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('Clipboard cleared'),
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
    // Calculate viewport
    final viewportWidth = _getViewportWidth(context);
    final playheadPx = _getPlayheadPx(context);
    _recalculateRowYPositions();

    // --- Center measure 1 (time = 0) on playhead initially ---
    if (_scrollOffsetMs == 0.0 && widget.playheadMs == 0.0) {
      // === FIX ===: Use new playheadPx
      _scrollOffsetMs = -(playheadPx) / _pixelsPerMs;
    }

    // case for Restart to beginning button (must only execute once)
    int expectedRestartMs =
        (_loopEnabled && _loopStartMs != null) ? _loopStartMs! : 0;

    final bool isRestart = (!widget.isPlaying) &&
        (widget.playheadMs - expectedRestartMs).abs() <
            0.01; // tiny epsilon, irrelevant cuz comparing with int

    if (isRestart) {
      final targetScrollMs = expectedRestartMs - (playheadPx) / _pixelsPerMs;
      if ((_scrollOffsetMs - targetScrollMs).abs() > 0.5) {
        _scrollOffsetMs = targetScrollMs;
        _clampScroll();
      }
    }

    // --- During playback, keep playhead centered dynamically ---
    // if ((widget.isPlaying && !_isUserInteracting) || widget.playheadMs == 0.0) {
    if (widget.isPlaying) {
      // || widget.playheadMs == 0.0) {
      // === FIX ===: Use new playheadPx
      final targetScrollMs = widget.playheadMs - (playheadPx) / _pixelsPerMs;

      // Keep playhead centered without scheduling extra frame callbacks.
      if ((_scrollOffsetMs - targetScrollMs).abs() > 0.5) {
        _scrollOffsetMs = targetScrollMs;
        _clampScroll(); // Apply clamping
      }
    }
    final List<double> expandedHeights = List.generate(_rowCount, (i) {
      if (!_rowExpanded[i]) return 0.0;
      return (_expandedTab[i] == 0)
          ? kExpandedRowHeight
          : _effectsPanelHeights[i];
    });

    return Container(
      constraints: const BoxConstraints(),
      color: const Color(0xFF1A1F2E),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time ruler
          _buildTimeRuler(viewportWidth),
          // Timeline + headers stacked
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final visibleTimelineHeight = constraints.maxHeight;
                return SingleChildScrollView(
                  controller: _verticalScrollController,
                  physics: _isUserInteracting &&
                              (_interactionMode == 'drag' ||
                                  _interactionMode == 'automation') ||
                          _activeTool == _TimelineTool.delete
                      ? const NeverScrollableScrollPhysics() // DISABLE V-SCROLL DURING DRAG
                      : const ClampingScrollPhysics(),
                  child: SizedBox(
                    height: _scrollContentHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // === Timeline background (waveforms, clips, playhead) ===
                        Positioned.fill(
                          left:
                              kHeaderWidth, // 👈 ensures waveform starts after header
                          child: Builder(
                            builder: (context) {
                              Widget timelineContent = Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: _onTimelinePointerDown,
                                onPointerMove: _onTimelinePointerMove,
                                onPointerHover: _onTimelinePointerHover,
                                onPointerUp: _onTimelinePointerUp,
                                onPointerCancel: _onTimelinePointerCancel,
                                child: GestureDetector(
                                  // dragStartBehavior: DragStartBehavior.start,
                                  // === FIX ===: Added all gesture handlers
                                  onScaleStart: _onScaleStart,
                                  onScaleUpdate: _onScaleUpdate,
                                  onScaleEnd: _onScaleEnd,
                                  onLongPressStart: _onTimelineLongPressStart,
                                  onLongPressMoveUpdate:
                                      _onTimelineLongPressMoveUpdate,
                                  onLongPressEnd: _onTimelineLongPressEnd,
                                  onTapDown: (details) =>
                                      _handleTapDown(details),
                                  onTapUp: _onTimelineTap,
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: ClipRect(
                                      child: RepaintBoundary(
                                        child: CustomPaint(
                                          painter: _TimelinePainter(
                                            clips: widget.clips,
                                            getStartMs: widget.getStartMs,
                                            getDurationMs: widget.getDurationMs,
                                            getTimelineDurationMs:
                                                widget.getTimelineDurationMs,
                                            getTrimStartMs:
                                                widget.getTrimStartMs,
                                            getTrimEndMs: widget.getTrimEndMs,
                                            getFullDurationMs:
                                                widget.getFullDurationMs,
                                            getPeaks: widget.getPeaks,
                                            pixelsPerMs: _pixelsPerMs,
                                            scrollOffsetMs: _scrollOffsetMs,
                                            viewportWidth: viewportWidth,
                                            playheadPx:
                                                playheadPx, // === FIX ===
                                            selectedClipIndex:
                                                _selectedClipIndex,
                                            selectedClipIndices:
                                                _selectedClipIndices.toList(
                                                    growable: false),
                                            stretchToolActive: _activeTool ==
                                                _TimelineTool.stretch,
                                            trimClipIndex:
                                                _trimClipIndex, // === FIX ===: Pass the active trim index
                                            // === FIX ===: Pass drag state to painter
                                            draggedClipIndex: _draggedClipIndex,
                                            draggedClipStartMs:
                                                _dragStartClipMs,
                                            draggedClipRowIndex: _dragStartRow,
                                            rowExpanded: _rowExpanded,
                                            kExpandedRowHeight:
                                                kExpandedRowHeight,
                                            verticalScrollOffset:
                                                _verticalScrollOffset,
                                            expandedTab: _expandedTab,
                                            effectsPanelHeights:
                                                _effectsPanelHeights,
                                            expandedHeights: expandedHeights,
                                            isRecording: widget.isRecording,
                                            recordingRowIndex:
                                                widget.recordingRowIndex,
                                            recordingStartMs:
                                                widget.recordingStartMs,
                                            recordingPeaks:
                                                widget.recordingPeaks,
                                            bpm: widget.bpm,
                                            beatsPerBar: widget.beatsPerBar,
                                            quantizeDivisions:
                                                _quantizeDivisionsPerBar,
                                            highlightedSegmentRow:
                                                _highlightedSegmentRow,
                                            highlightedSegmentStartMs:
                                                _highlightedSegmentStartMs,
                                            highlightedSegmentEndMs:
                                                _highlightedSegmentEndMs,
                                            sampleDropPreviewRow:
                                                _externalSampleDropRow,
                                            sampleDropPreviewStartMs:
                                                _externalSampleDropStartMs,
                                            sampleDropPreviewEndMs:
                                                _externalSampleDropEndMs,
                                            cutPreviewClipIndex:
                                                _cutPreviewClipIndex,
                                            cutPreviewMs: _cutPreviewMs,
                                          ),
                                          size: Size(
                                            viewportWidth,
                                            _timelinePaintHeight,
                                          ), //size: Size(viewportWidth, kNumRows * kRowHeight),
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
                                  final placement =
                                      _sampleDropPlacementForGlobalOffset(
                                    details.offset,
                                    data: details.data,
                                  );
                                  _clearExternalSampleDropPreview();
                                  if (placement == null) return;
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
                        if (_currentSelectionRect() != null)
                          _buildSelectionBoxOverlay(),
                        // Expanded row panels (Volume/Effects)
                        ..._buildExpandedRows(viewportWidth),

                        // if (_selectedClipIndex != -1) _buildSelectedClipPopup(viewportWidth),
                        _buildSelectedClipPopup(
                          viewportWidth,
                          visibleTimelineHeight,
                        ),
                        // if (_showPastePopup && _pasteRow != null && _pasteMs != null) _buildPastePopup(viewportWidth),
                        _buildPastePopup(viewportWidth),
                        _buildDeadZoneRowNames(viewportWidth),

                        // === Track headers (always on top) ===
                        Positioned(
                          left: 0,
                          top: 0, // _verticalScrollOffset,
                          bottom: 0,
                          // child: Builder(builder: (context) {
                          //   // (Your dynamic header width logic, left as-is)
                          //   double dynamicWidth = _AudioCanvasTimelineState.kHeaderWidth;
                          //   return Container(
                          //     height: _totalTimelineHeight,
                          //     width: dynamicWidth,
                          //     color: const Color(0xFF252B3A),
                          //     child: _buildTrackHeaders(dynamicWidth),
                          //   );
                          // }),
                          child: SizedBox(
                            width: _AudioCanvasTimelineState.kHeaderWidth,
                            child: SizedBox(
                              height: _scrollContentHeight,
                              child: _buildTrackHeadersContent(
                                  _AudioCanvasTimelineState.kHeaderWidth),
                            ),
                          ),
                        ),
                        _buildInlineClipControlOverlay(
                          viewportWidth,
                          visibleTimelineHeight,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
            color: const Color(0x334F70E4),
            border: Border.all(color: const Color(0xFF7FA7FF), width: 1.2),
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

      final double topY = _rowYPositions[row] + kRowHeight;
      list.add(
        Positioned(
          key: ValueKey('expanded_row_${widget.rows[row].rowId}'),
          left: kHeaderWidth,
          top: topY,
          width: viewportWidth,
          // height: (_expandedTab[row] == 0) ? kExpandedRowHeight : _effectsPanelHeights[row],
          // child:
          // _expandedTab[row] == 0 ? _buildVolumePanel(row) : _buildEffectsPanel(row),
          height: _expandedTab[row] == 0
              ? kExpandedRowHeight
              : null, //_effectsPanelHeights[row],
          child: ClipRect(
            // prevents overflow painting
            child: Container(
              // margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                // borderRadius: BorderRadius.circular(0),
                border: Border.all(
                    color: const Color.fromARGB(255, 47, 64, 117)
                        .withOpacity(0.28),
                    width: 0),
              ),
              // padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              // padding: const EdgeInsets.only(bottom: 0),
              child: _expandedTab[row] == 0
                  ? _buildVolumePanel(row)
                  : _buildEffectsPanel(row),
            ),
          ),
        ),
      );
    }

    return list;
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
                  color: Colors.black.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Text(
                  name.isEmpty ? 'Row ${row + 1}' : name,
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

  Widget _buildTabButton(int row, int tab, String label) {
    final bool selected = _expandedTab[row] == tab;

    return GestureDetector(
      onTap: () {
        setState(() {
          _expandedTab[row] = tab;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        height: 34,

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
                        Color(0xFF4F70E4), // top-left glossy blue
                        Color(0xFF2A3A8F), // bottom-right deep blue
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [
                        Color(0x332F3645), // light greyish-blue
                        Color(0x22212732), // darker muted tone
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 3))
              ],

              border: Border.all(
                color: selected
                    ? Colors.white.withOpacity(0.28)
                    : Colors.white.withOpacity(0.12),
                width: 1.2,
              ),
            ),

            alignment: Alignment.center,

            // === This makes the text shrink but never wrap ===
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1, // Never wrap
                overflow: TextOverflow.visible, // No ellipsis
                softWrap: false, // NEVER wrap to next line
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVolumePanel(int row) {
    return Padding(
      padding: const EdgeInsets.all(
          0), // const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

                return GestureDetector(
                  dragStartBehavior: DragStartBehavior.down,
                  behavior: HitTestBehavior.opaque,
                  child: _AutomationLane(
                    rowIndex: row,
                    points: widget.rowVolumeAutomation[row],
                    pixelsPerMs: _pixelsPerMs,
                    scrollOffsetMs: _scrollOffsetMs,
                    laneHeight: laneHeight,
                    timelineDurationMs: _maxDurationMs,
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
                  ),
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

          // === Background for Pan + Gain (same as automation background) ===
          Container(
            // margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF151A26).withOpacity(0.9),
              borderRadius: BorderRadius.circular(0),
            ),
            // padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: PrettyStereoSlider(
                    value:
                        widget.rowPan[row], // <-- plug in real per-track value
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
                  ),
                ),

                const SizedBox(height: 10),

                // === Gain slider ===
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: PrettyGainSlider(
                    value: widget.rowGain[row],
                    onChangeStart: (v) {
                      _gainDragStart = v;
                    },
                    onChanged: (v) {
                      setState(() => widget.rowGain[row] = v);
                      widget.setRowGain(row, v); // send to JUCE 0.0 → 3.0
                    },
                    onChangeEnd: (v) {
                      widget.onRowGainCommit!(
                          row, _gainDragStart!, widget.rowGain[row]);
                      _gainDragStart = null;
                    },
                  ),
                ),
              ],
            ),
          ),

          // const SizedBox(height: 6),
        ],
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
    return Container(
      decoration:
          BoxDecoration(color: const Color(0xFF151A26).withOpacity(0.9)),
      child: RowEffectsPanel(
        key: ValueKey("effect_panel_row_${widget.rows[row].rowId}"),
        rowIndex: row,
        mode: widget.mode,
        onHeightChanged: (h) {
          if (mounted) {
            setState(() {
              // print("row $row set to $h $kExpandedRowHeight");
              _effectsPanelHeights[row] = h;
              // _effectsPanelHeights[row] = math.max(h, kExpandedRowHeight);
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
        setTrackEffectParam: widget.setRowEffectParam,
        onPluginParamCommit: widget.onPluginParamCommit,
        onPresetCommit: widget.onPresetCommit,
        registerRefresh: (refreshFn) {
          _rowEffectRefreshers[widget.rows[row].rowId] = refreshFn;
        },
        projectBpm: widget.bpm,
        meters: widget.meters,
        getRowCompressorMeter: widget.getRowCompressorMeter,
        getRowEqWaveform: widget.getRowEqWaveform,
      ),
    );
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
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF4F70E4) : const Color(0x332F3645),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        alignment: Alignment.center,
        child: SvgPicture.asset(
          svgPath,
          height: size * 0.60,
          colorFilter: const ColorFilter.mode(
              Color.fromARGB(200, 255, 255, 255), BlendMode.srcIn),
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
    _loopDragOffsetMs = null;
    _loopCreateAnchorMs = null;
    _loopDragRegionFingerAnchorMs = null;
    _loopDragRegionStartAnchorMs = null;
    _loopDragRegionEndAnchorMs = null;
  }

  void _onRulerTapDown(TapDownDetails d) {}

  void _onRulerTapUp(TapUpDetails d) {
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
    final fingerX = d.localPosition.dx;
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

  void _onRulerPanUpdate(DragUpdateDetails d) {
    final fingerMsRaw = _rulerMsFromLocalX(d.localPosition.dx);
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
          color: const Color(0x332F3645),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24, width: 1),
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
    return Container(
      height: kRulerHeight,
      color: const Color(0xFF0F1419),
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
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: _onRulerTapDown,
                  onTapUp: _onRulerTapUp,
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
            ],
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
    await AppHaptics.impact(AppHapticImpact.medium);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1B2233),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.vertical_align_top, color: Colors.white),
              title: const Text('Insert Row Above',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'insert_above'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.vertical_align_bottom, color: Colors.white),
              title: const Text('Insert Row Below',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'insert_below'),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward, color: Colors.white),
              title:
                  const Text('Move Up', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'move_up'),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward, color: Colors.white),
              title: const Text('Move Down',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'move_down'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline,
                  color: Colors.white),
              title: const Text('Rename Row',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined, color: Colors.white),
              title: const Text('Choose Icon',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'icon'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Color(0xFFFFA4A4)),
              title: const Text('Delete Row',
                  style: TextStyle(color: Color(0xFFFFA4A4))),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == null) return;
    if (action == 'insert_above') return widget.onInsertRowAbove(row);
    if (action == 'insert_below') return widget.onInsertRowBelow(row);
    if (action == 'move_up' && row > 0) return widget.onMoveRow(row, row - 1);
    if (action == 'move_down' && row < _rowCount - 1)
      return widget.onMoveRow(row, row + 1);
    if (action == 'delete') return widget.onDeleteRow(row);

    if (action == 'rename') {
      final controller = TextEditingController(text: widget.rows[row].name);
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => MediaQuery.removeViewInsets(
          context: ctx,
          removeBottom: true,
          child: Dialog(
            alignment: Alignment.topCenter,
            insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
            backgroundColor: const Color(0xFF1A2233),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withOpacity(0.10)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.drive_file_rename_outline,
                          color: Color(0xFFB9D4FF)),
                      SizedBox(width: 8),
                      Text(
                        'Rename Row',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      maxLength: 32,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) =>
                          Navigator.pop(ctx, controller.text.trim()),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Row name',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.white70)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(ctx, controller.text.trim()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E6EEB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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
            title: const Text('Select Icon'),
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
                          color: const Color(0xFF2A3347),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_iconForRow(id), color: Colors.white),
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

          return Column(
            children: [
              _buildOneTrackHeader(row, isSelected, isMuted),
              if (isExpanded)
                SizedBox(
                  height: (_expandedTab[row] == 0)
                      ? kExpandedRowHeight
                      : _effectsPanelHeights[row],
                  width: dynamicWidth,
                  child: _buildHeaderTabs(row),
                ),
            ],
          );
        }),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            height: kHeaderFooterHeight - 8,
            child: Center(
              child: IconButton(
                onPressed: widget.onAddRow,
                icon: const Icon(Icons.add_circle_outline,
                    color: Colors.white, size: 28),
              ),
            ),
          ),
        ),
        const SizedBox(height: kBottomInteractionPadding),
      ],
    );
  }

  Widget _buildOneTrackHeader(int row, bool isSelected, bool isMuted) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _startRowMenuHold(row, e.localPosition, e.pointer),
      onPointerMove: _onHeaderPointerMove,
      onPointerUp: _onHeaderPointerUp,
      onPointerCancel: _onHeaderPointerCancel,
      child: Container(
        height: kRowHeight, // Fixed height
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color.fromARGB(255, 55, 73, 108)
              : const Color.fromARGB(255, 30, 41, 65), //Colors.transparent,
          border: const Border(
              bottom: BorderSide(color: Color(0xFF1A1F2E), width: 1)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 5,
              top: ((kRowHeight - 28) / 2) - 6,
              child: Icon(_iconForRow(widget.rows[row].iconId),
                  color: Colors.white, size: 28),
            ),
            if (isSelected)
              Positioned(
                left: 10,
                bottom: 1,
                child: Icon(
                  _rowExpanded[row]
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.white54,
                  size: 18,
                ),
              ),
            // === Mute button (top-right, tighter to edge) ===
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => setState(() {
                  bool newVal = !widget.rowMuted[row];
                  widget.muteRow(row, newVal);
                }),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color:
                        isMuted ? const Color(0xFF5B6B8C) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white30),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'M',
                    style: TextStyle(
                      color: isMuted ? Colors.white : Colors.white38,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            // === Solo button (bottom-right) ===
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  bool newVal = !widget.rowSoloed[row];
                  widget.soloRow(row, newVal);
                },
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: widget.rowSoloed[row]
                        ? const Color(0xFFFFB000)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white30),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'S',
                    style: TextStyle(
                      color:
                          widget.rowSoloed[row] ? Colors.black : Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      decoration: const BoxDecoration(
        color: Color.fromARGB(255, 30, 41, 65),
        border: Border(bottom: BorderSide(color: Color(0xFF1A1F2E), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),

          const SizedBox(height: 6),

          // === TABS ===
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTabButton(row, 0, "Volume"),
                const SizedBox(height: 6),
                _buildTabButton(row, 1, "Effects"),
              ],
            ),
          ),

          // === METERING ===
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AnimatedBuilder(
                animation: widget.meters,
                builder: (_, __) {
                  final f = widget.meters.rows[row];
                  return MiniStereoMeterPro(frame: f);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === FIX ===: New unified gesture handlers
  void _onScaleStart(ScaleStartDetails details) {
    if (_interactionMode == 'automation') return;
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
      }

      setState(() {});
      return; // EXIT EARLY — trim takes full control
    }

    // === 2. DRAG WAS INITIATED IN tapDown? → Continue drag ===
    if (_interactionMode == 'drag' && _draggedClipIndex != null) {
      // Already in drag mode — just continue
      return;
    }

    // --- STEP 3: No clip interaction, start Panning/Zooming ---
    _interactionMode = 'pan';
    _initialScrollMs = _scrollOffsetMs;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_activeTool == _TimelineTool.cut && _cutPreviewClipIndex != null) {
      return;
    }
    if (_activeTool == _TimelineTool.delete && _deleteStrokeActive) {
      return;
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

    if (_interactionMode == 'drag' && _draggedClipIndex != null) {
      final selected = _activeSelectedClipIndices();
      final draggingGroup = selected.length > 1 &&
          selected.contains(_draggedClipIndex!) &&
          _dragGroupStartMs.isNotEmpty &&
          _dragGroupStartRows.isNotEmpty;
      if (draggingGroup) {
        for (final index in selected) {
          final baseMs = _dragGroupStartMs[index];
          final baseRow = _dragGroupStartRows[index];
          if (baseMs == null || baseRow == null) continue;
          final nextStartMs =
              _quantizeMs(baseMs + _dragDeltaMs).clamp(0.0, double.infinity);
          final nextRow = (baseRow + _dragDeltaRows)
              .clamp(0, math.max(0, _rowCount - 1))
              .toInt();
          await widget.onMoveClipCommit(index, nextStartMs, nextRow);
        }
      } else {
        await widget.onMoveClipCommit(
            _draggedClipIndex!, _dragStartClipMs!, _dragStartRow!);
      }
    }

    if (_interactionMode == 'trim-start' || _interactionMode == 'trim-end') {
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

    if ((_interactionMode == 'stretch-start' ||
            _interactionMode == 'stretch-end') &&
        _stretchClipIndex != null &&
        _stretchDurationUpdateMs != null) {
      await widget.onStretchClipCommit(_stretchClipIndex!);
    }

    if (_interactionMode == 'pan') {
      // Request a final scrub
      final playheadPx = _getPlayheadPx(context);
      widget.onScrubRequested(_scrollOffsetMs + playheadPx / _pixelsPerMs);
    }

    // Reset all interaction states
    setState(() {
      _isUserInteracting = false;
      _interactionMode = '';
      _draggedClipIndex = null;
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
    if (_activeTool != _TimelineTool.pencil &&
        _activeTool != _TimelineTool.stretch) {
      return;
    }
    if (_interactionMode == 'automation') return;
    if (_getClipIndexAt(details.localPosition) != null) return;
    setState(() {
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
    if (_draggedClipIndex == null || _dragStartGlobalOffset == null) return;

    setState(() {
      final draggedIndex = _draggedClipIndex!;
      final draggedClip = widget.clips[draggedIndex];

      // Calculate TOTAL delta from drag start (for row)
      final totalDx = details.focalPoint.dx - _dragStartGlobalOffset!.dx;
      final totalDy = details.focalPoint.dy -
          _dragStartGlobalOffset!.dy; // === FIX ===: Use totalDy for row

      // Convert to delta in Ms
      final deltaMs = totalDx / _pixelsPerMs;
      final deltaRows = (totalDy / kRowHeight).round();
      _dragDeltaMs = deltaMs;
      _dragDeltaRows = deltaRows;

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
      final newRow = originalRow + deltaRows;

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

  void _handleTrimUpdate(ScaleUpdateDetails details) {
    if (_trimClipIndex == null || _trimStartAnchorX == null) return;

    final clip = widget.clips[_trimClipIndex!];
    final fullDuration = widget.getFullDurationMs(clip);

    // Amount user moved horizontally in pixels (local to timeline)
    final deltaPx = details.localFocalPoint.dx - _trimStartAnchorX!;
    // Convert movement delta to ms
    final deltaMs = deltaPx / _pixelsPerMs;

    double newTrimStart = _trimStartValue!;
    double newTrimEnd = _trimEndValue!;

    double? newStartMs;
    final originalStartMs = _trimOriginalStartMs!;

    if (_interactionMode == 'trim-start') {
      newTrimStart = (_trimStartValue! + deltaMs).clamp(0.0, newTrimEnd - 50.0);
      if (_magnetEnabled) {
        newTrimStart = _quantizeMs(newTrimStart);
      }

      final deltaTrim = newTrimStart - _trimStartValue!;
      final attemptedNewStartMs = originalStartMs + deltaTrim;

      if (attemptedNewStartMs < 0.0) {
        newStartMs = 0.0;
        final maxAllowedDeltaTrim = -originalStartMs;
        newTrimStart = (_trimStartValue! + maxAllowedDeltaTrim)
            .clamp(0.0, newTrimEnd - 50.0);
      } else {
        newStartMs =
            attemptedNewStartMs; // <-- This is the ripple move calculation
      }
    } else if (_interactionMode == 'trim-end') {
      newTrimEnd =
          (_trimEndValue! + deltaMs).clamp(newTrimStart + 50.0, fullDuration);

      if (_magnetEnabled) {
        newTrimEnd = _quantizeMs(newTrimEnd);
      }
      // newStartMs remains null, correctly signaling no position change
    }

    if (newStartMs != null) {
      widget.onTrimClip(_trimClipIndex!, newTrimStart, newTrimEnd,
          newStartMs: newStartMs);
    } else {
      widget.onTrimClip(
        _trimClipIndex!,
        newTrimStart,
        newTrimEnd,
        // newStartMs is omitted for trim-end
      );
    }
    newTrimStartUpdate = newTrimStart;
    newTrimEndUpdate = newTrimEnd;
    newStartMsUpdate = newStartMs;

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
    setState(() {
      // --- Handle Zoom ---
      if (details.scale != 1.0 && _initialPixelsPerMs != null) {
        final newPixelsPerMs =
            (_initialPixelsPerMs! * details.scale).clamp(0.0025, 1.0);

        // Zoom around the focal point
        final focalPointPx = details.localFocalPoint.dx;
        final focalPointMs = _scrollOffsetMs + focalPointPx / _pixelsPerMs;

        _scrollOffsetMs = focalPointMs - (focalPointPx / newPixelsPerMs);
        _pixelsPerMs = newPixelsPerMs;
      }

      // --- Handle Pan ---
      if (details.focalPointDelta.dx != 0) {
        _scrollOffsetMs -= details.focalPointDelta.dx / _pixelsPerMs;
      }

      // --- Clamping & Scrub ---
      _clampScroll();
      final playheadPx = _getPlayheadPx(context);
      widget.onScrubRequested(_scrollOffsetMs + playheadPx / _pixelsPerMs);
    });
  }

  double msFor128Bars(double bpm) {
    return 512 * (60000 / bpm);
  }

  void _clampScroll() {
    final viewportWidth = _getViewportWidth(context);
    final playheadPx = _getPlayheadPx(context);
    final viewMs = viewportWidth / _pixelsPerMs;

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
    double yOffset = 0;
    for (int i = 0; i < row; i++) {
      yOffset += kRowHeight;

      if (_rowExpanded[i]) {
        // Use dynamic height
        yOffset += (_expandedTab[i] == 0)
            ? kExpandedRowHeight
            : _effectsPanelHeights[i];
      }
    }

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
    final tapRow = (localY / kRowHeight).floor().clamp(0, _rowCount - 1);

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
    final localX = localPosition.dx;
    final localY = localPosition.dy;
    final tapMs = _scrollOffsetMs + localX / _pixelsPerMs;

    double currentY = 0;
    int tapRow = -1;

    // Find the row index by iterating through the visual layout
    for (int i = 0; i < _rowCount; i++) {
      double rowTotalHeight = kRowHeight;
      if (_rowExpanded[i]) {
        // Use dynamic height
        rowTotalHeight += (_expandedTab[i] == 0)
            ? kExpandedRowHeight
            : _effectsPanelHeights[i];
      }

      // maybe this was working just fine before (have here just in case)
      // if (localY >= currentY && localY < currentY + kRowHeight) {
      //   // Tapped in the non-expanded *main* track area
      //   tapRow = i;
      //   break;
      // } else if (localY >= currentY + kRowHeight && _rowExpanded[i] && localY < currentY + rowTotalHeight) {
      //   // Tapped in the *expanded* track area - still belongs to track 'i'
      //   tapRow = i;
      //   break;
      // }

      if (localY >= currentY && localY < currentY + rowTotalHeight) {
        tapRow = i;
        break;
      }
      currentY += rowTotalHeight;
    }

    if (tapRow == -1) return null;

    // Iterate backwards to prioritize clips drawn later
    // for (int i = widget.clips.length - 1; i >= 0; i--) {
    //   final clip = widget.clips[i];
    //   final startMs = widget.getStartMs(clip);
    //   // Use the trimmed duration for hit testing
    //   final visualDuration = widget.getTrimEndMs(clip) - widget.getTrimStartMs(clip);
    //   final endMs = startMs + visualDuration;
    //   final clipRow = clip.rowIndex; // <--- This is the definition that was checked

    //   if (clipRow == tapRow && tapMs >= startMs && tapMs <= endMs) {
    //     return i; // Return the index
    //   }
    // }
    // return null;

    // Collect all clips that collide at this tap (same row + tapMs inside their visible span)
    final candidates = <int>[];

    for (int i = 0; i < widget.clips.length; i++) {
      final clip = widget.clips[i];

      if (clip.rowIndex != tapRow) continue;

      final startMs = widget.getStartMs(clip);
      final visualDuration = widget.getTimelineDurationMs(clip);
      final endMs = startMs + visualDuration;

      if (tapMs >= startMs && tapMs <= endMs) {
        candidates.add(i);
      }
    }
    if (candidates.isEmpty) return null;

    // "Top" = drawn last. Your painter draws in list order,
    // so higher index wins.
    int topIndex = candidates.reduce((a, b) => a > b ? a : b);

    // Optional: if you want the *currently selected clip* to win
    // when it’s part of the overlap stack (DAW-style sticky selection),
    // uncomment this:
    //
    // if (_selectedClipIndex >= 0 && candidates.contains(_selectedClipIndex)) {
    //   topIndex = _selectedClipIndex;
    // }

    return topIndex;
  }

  void _handleTapDown(TapDownDetails details) {
    if (_interactionMode == 'automation') return;
    if (_activeTool == _TimelineTool.cut ||
        _activeTool == _TimelineTool.delete) {
      return;
    }
    if (_activeTool == _TimelineTool.paint &&
        _activeSelectedClipIndices().isEmpty) {
      return;
    }
    if (_selectionBoxActive) return;

    _clearPastePopup();

    // === 1. Reset any previous trim cue ===
    setState(() {
      _activeTrimHandleX = null;
      _trimClipIndex = null;
      _stretchClipIndex = null;
      _stretchStartTimelineDurationMs = null;
      _stretchOriginalStartMs = null;
      _stretchStartAnchorX = null;
      _stretchDurationUpdateMs = null;
    });

    final localPos = details.localPosition;
    final tappedClipIndex = _getClipIndexAt(localPos);

    if (tappedClipIndex == null) return;
    final wasAlreadySelected = _selectedClipIndices.contains(tappedClipIndex);
    final clipRect = _getClipRect(tappedClipIndex);
    if (clipRect == null) {
      if (!wasAlreadySelected) {
        setState(() {
          _setSingleClipSelection(tappedClipIndex, popupMs: null);
        });
      }
      return;
    }

    final localX = localPos.dx;
    final draggingGroup = _selectedClipIndices.length > 1 &&
        _selectedClipIndices.contains(tappedClipIndex);

    // === 3. PRIORITY 1: TRIM HANDLE HIT? (WINS OVER DRAG) ===
    final leftHandleHit = localX >= clipRect.left - kTrimHitboxPadding &&
        localX <= clipRect.left + kTrimHandleWidth + kTrimHitboxPadding;

    final rightHandleHit =
        localX >= clipRect.right - kTrimHandleWidth - kTrimHitboxPadding &&
            localX <= clipRect.right + kTrimHitboxPadding;

    if (!draggingGroup && (leftHandleHit || rightHandleHit)) {
      // TRIM WINS — show visual cue and prepare for trim
      setState(() {
        _setSingleClipSelection(tappedClipIndex, popupMs: null);
        _trimClipIndex = tappedClipIndex;
        _activeTrimHandleX = leftHandleHit ? clipRect.left : clipRect.right;
        // DO NOT set _interactionMode here — let onScaleStart do it
        // This ensures trim gesture starts cleanly
      });
      return; // STOP — do NOT allow drag
    }

    if (!wasAlreadySelected) {
      setState(() {
        _setSingleClipSelection(tappedClipIndex, popupMs: null);
      });
      return;
    }

    // === 4. PRIORITY 2: TAP ON CLIP BODY → PREPARE FOR DRAG ===
    if (clipRect.contains(localPos)) {
      // User tapped on clip body → will likely drag
      setState(() {
        _isUserInteracting = true;
        _interactionMode = 'drag'; // ← This disables vertical scroll
        _draggedClipIndex = tappedClipIndex;
        _dragStartGlobalOffset = details.globalPosition;
        _dragStartLocalOffset = localPos;
        _dragStartClipMs = widget.getStartMs(widget.clips[tappedClipIndex]);
        _dragStartRow = widget.clips[tappedClipIndex].rowIndex;
        _dragDeltaMs = 0.0;
        _dragDeltaRows = 0;
        _dragGroupStartMs.clear();
        _dragGroupStartRows.clear();
        if (draggingGroup) {
          final selected = _activeSelectedClipIndices();
          for (final index in selected) {
            _dragGroupStartMs[index] = widget.getStartMs(widget.clips[index]);
            _dragGroupStartRows[index] = widget.clips[index].rowIndex;
          }
        }
      });
      return;
    }

    // === 5. TAP ELSEWHERE → clear trim cue ===
    setState(() {
      _activeTrimHandleX = null;
      _trimClipIndex = null;
      _stretchClipIndex = null;
      _stretchStartTimelineDurationMs = null;
      _stretchOriginalStartMs = null;
      _stretchStartAnchorX = null;
      _stretchDurationUpdateMs = null;
    });
  }

  void _onTimelineTap(TapUpDetails details) {
    if (_interactionMode == 'automation') return;

    if (_activeTool == _TimelineTool.cut) {
      // Cut commits on raw pointer-up so drag-to-preview release also cuts.
      return;
    }

    if (_activeTool == _TimelineTool.paint) {
      final topIndex = _getClipIndexAt(details.localPosition);
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
      if (!widget.hasCopiedClip) {
        _showPaintClipboardHint();
        return;
      }
      _tryPaintAt(details.localPosition);
      return;
    }

    if (_activeTool == _TimelineTool.delete) {
      return;
    }

    if (_interactionMode == 'drag') {
      final tappedDragIndex = _draggedClipIndex;
      final dragStartGlobal = _dragStartGlobalOffset;
      final dragDistance = dragStartGlobal == null
          ? double.infinity
          : (details.globalPosition - dragStartGlobal).distance;
      const tapMovementTolerance = 8.0;
      final shouldTreatAsTap = dragDistance <= tapMovementTolerance;

      setState(() {
        _interactionMode = '';
        _draggedClipIndex = null;
        _pendingDrag = false; // unused I think
        _pendingLocalDown = null; // unused I think
        _isUserInteracting = false;
        _dragGroupStartMs.clear();
        _dragGroupStartRows.clear();
      });
      if (shouldTreatAsTap &&
          tappedDragIndex != null &&
          tappedDragIndex >= 0 &&
          tappedDragIndex < widget.clips.length &&
          widget.clips[tappedDragIndex].clipKind == ClipKind.midi) {
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
    final topIndex = _getClipIndexAt(details.localPosition);
    if (topIndex != null) {
      final topClip = widget.clips[topIndex];

      setState(() {
        _setSingleClipSelection(topIndex, popupMs: rawTapMs);
        _showPastePopup = false;
        _pasteRow = null;
        _pasteMs = null;
        _highlightedSegmentRow = null;
        _highlightedSegmentStartMs = null;
        _highlightedSegmentEndMs = null;
      });
      if (topClip.clipKind == ClipKind.midi) {
        widget.onOpenMidiClip?.call(topIndex);
      }
    } else {
      setState(() {
        _clearClipSelection();

        // If we have something copied, show paste popup here
        if (widget.hasCopiedClip) {
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
    if (_trimClipIndex != null) {
      setState(() {
        _activeTrimHandleX = null;
        _trimClipIndex = null;
        _stretchClipIndex = null;
        _stretchStartTimelineDurationMs = null;
        _stretchOriginalStartMs = null;
        _stretchStartAnchorX = null;
        _stretchDurationUpdateMs = null;
      });
    }
  }
}

class _ClipOverlapSpan {
  final int index;
  final double startMs;
  final double endMs;

  const _ClipOverlapSpan({
    required this.index,
    required this.startMs,
    required this.endMs,
  });
}

// === Custom painter for the timeline ===
class _TimelinePainter extends CustomPainter {
  final List<AudioTrack> clips;
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
  final int? cutPreviewClipIndex;
  final double? cutPreviewMs;
  final int _clipDataHash;
  final int _selectedClipIndicesHash;
  final int _rowExpandedHash;
  final int _expandedTabHash;
  final int _effectsPanelHeightsHash;
  final int _expandedHeightsHash;
  final int _recordingPeaksHash;

  _TimelinePainter({
    required this.clips,
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
    required this.cutPreviewClipIndex,
    required this.cutPreviewMs,
  })  : _clipDataHash = _computeClipDataHash(
          clips: clips,
          getStartMs: getStartMs,
          getTimelineDurationMs: getTimelineDurationMs,
          getTrimStartMs: getTrimStartMs,
          getTrimEndMs: getTrimEndMs,
          getFullDurationMs: getFullDurationMs,
          getPeaks: getPeaks,
        ),
        _selectedClipIndicesHash = _hashList(selectedClipIndices),
        _rowExpandedHash = _hashList(rowExpanded),
        _expandedTabHash = _hashList(expandedTab),
        _effectsPanelHeightsHash = _hashDoubleList(effectsPanelHeights),
        _expandedHeightsHash = _hashDoubleList(expandedHeights),
        _recordingPeaksHash = _hashDoubleList(recordingPeaks);

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
      hash = _hashCombine(hash, clip.clipKind.index);
      hash = _hashCombine(hash, clip.midiNotes.length);
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
      final isExpanded = rowExpanded[row];
      // final expandedHeight = isExpanded ? kExpandedRowHeight : 0;
      final expandedHeight = expandedHeights[row];

      final totalRowHeight = rowHeight + expandedHeight;

      // 1. Draw the main track background (alternating colors)
      final rect = Rect.fromLTWH(0, currentY, viewportWidth, rowHeight);
      final paint = Paint()
        ..color =
            row % 2 == 0 ? const Color(0xFF1A1F2E) : const Color(0xFF151A26);
      canvas.drawRect(rect, paint);

      // 2. Draw the expanded section background (transparent, but maybe a slight tint for debugging/visual separation)
      if (isExpanded) {
        final expandedRect = Rect.fromLTWH(
            0, currentY + rowHeight, viewportWidth, expandedHeight.toDouble());
        final expandedPaint = Paint()
          ..color = const Color(0xFF1A1F2E)
              .withOpacity(0.9); // Semi-transparent overlay
        canvas.drawRect(expandedRect, expandedPaint);
      }

      // 3. Draw horizontal grid lines for row separation (at the end of the total block)
      final linePaint = Paint()
        ..color = Colors.white.withOpacity(0.05)
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
      double highlightY = 0;
      for (int r = 0; r < highlightedSegmentRow!; r++) {
        highlightY += _AudioCanvasTimelineState.kRowHeight;
        if (rowExpanded[r]) {
          highlightY += expandedHeights[r];
        }
      }

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
            ..color = const Color(0xFF7FA7FF).withOpacity(0.16);
          final stroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0xFFBFD4FF).withOpacity(0.55);
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
      double previewY = 0;
      for (int r = 0; r < sampleDropPreviewRow!; r++) {
        previewY += _AudioCanvasTimelineState.kRowHeight;
        if (rowExpanded[r]) {
          previewY += expandedHeights[r];
        }
      }

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
          final fill = Paint()..color = const Color(0x7A6EE7B7);
          final stroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.15
            ..color = const Color(0xCCB7FFE3);
          canvas.drawRect(clipped, fill);
          canvas.drawRect(clipped, stroke);
        }
      }
    }

    // Draw vertical grid lines (unchanged)
    _drawGrid(canvas, size); // Note: _drawGrid doesn't use vertical position

    // === RECORDING PREVIEW ==========================================
    if (isRecording && recordingRowIndex != null) {
      final int recRow = recordingRowIndex!;

      // Compute the row's vertical position on screen
      double recY = 0;
      for (int r = 0; r < recRow; r++) {
        recY += _AudioCanvasTimelineState.kRowHeight;
        if (rowExpanded[r]) {
          recY += expandedHeights[r];
        }
      }

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

    final overlapByClip = _computeOverlapByClip();

    // Draw clips
    // ... (Clip drawing logic remains the same, but _drawClip needs modification) ...
    for (int i = 0; i < clips.length; i++) {
      if (i == draggedClipIndex) continue;
      _drawClip(canvas, i, false, overlapByClip);
    }
    if (draggedClipIndex != null) {
      _drawClip(canvas, draggedClipIndex!, true, overlapByClip);
    }
    _drawCutPreviewLine(canvas);

    // Draw playhead (centered)
    _drawPlayhead(canvas, size);

    canvas.restore(); // Always restore!
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

    final spansByRow = <int, List<_ClipOverlapSpan>>{};

    for (int i = 0; i < clips.length; i++) {
      final clip = clips[i];
      final startMs = (i == draggedClipIndex && draggedClipStartMs != null)
          ? draggedClipStartMs!
          : getStartMs(clip);
      final row = (i == draggedClipIndex && draggedClipRowIndex != null)
          ? draggedClipRowIndex!
          : clip.rowIndex;
      final visualDuration = getTimelineDurationMs(clip);
      if (visualDuration <= 0) continue;

      (spansByRow[row] ??= <_ClipOverlapSpan>[]).add(
        _ClipOverlapSpan(
          index: i,
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

  void _drawClip(
      Canvas canvas, int index, bool isDragging, List<bool> overlapByClip) {
    final clip = clips[index];

    // === FIX ===: Use drag state if provided
    final startMs = isDragging
        ? (draggedClipStartMs ?? getStartMs(clip))
        : getStartMs(clip);
    final trimStartMs = getTrimStartMs(clip);
    final trimEndMs = getTrimEndMs(clip);
    final peaks = getPeaks(clip);
    final visualDuration = getTimelineDurationMs(clip);
    final row =
        isDragging ? (draggedClipRowIndex ?? clip.rowIndex) : clip.rowIndex;

    double yOffset = 0;
    // for (int i = 0; i < row; i++) {
    //   yOffset += _AudioCanvasTimelineState.kRowHeight;
    //   if (rowExpanded[i]) {
    //     yOffset += kExpandedRowHeight;
    //   }
    // }
    for (int i = 0; i < row; i++) {
      yOffset += _AudioCanvasTimelineState.kRowHeight;

      if (rowExpanded[i]) {
        yOffset +=
            (expandedTab[i] == 0) ? kExpandedRowHeight : effectsPanelHeights[i];
      }
    }

    // visual left follows the new startMs
    final x = (startMs - scrollOffsetMs) * pixelsPerMs;
    final y =
        yOffset + 2; //final y = row * _AudioCanvasTimelineState.kRowHeight;
    final width = visualDuration * pixelsPerMs;
    const double height = _AudioCanvasTimelineState.kRowHeight - 4;

    // Skip if completely off-screen
    if (x + width < 0 || x > viewportWidth) return;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, width, height), // Use calculated y
      const Radius.circular(6),
    );
    final hasOverlap =
        index >= 0 && index < overlapByClip.length && overlapByClip[index];
    final isMidi = clip.clipKind == ClipKind.midi;
    final isSelected = selectedClipIndices.contains(index);
    final showEdgeHandles =
        selectedClipIndices.length <= 1 && index == selectedClipIndex;

    // Draw clip background
    final clipPaint = Paint()
      ..color = hasOverlap
          ? const Color(0xFF8B3A3A)
          : (isMidi
              ? (isSelected ? const Color(0xFF3F6C4A) : const Color(0xFF33593F))
              : (isSelected
                  ? const Color(0xFF4A5B7C)
                  : const Color(0xFF3A4A5C)));

    // === FIX ===: Make dragged clip semi-transparent
    if (isDragging) {
      clipPaint.color = clipPaint.color.withOpacity(0.6);
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
        fullDurationMs,
        stretchScale,
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
    // === NEW: Draw clip filename label ===
    _drawClipLabel(canvas, rect, clip);

    // Draw border
    final bool isTrimming = index == trimClipIndex; // === FIX ===

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2; // Increased width for better visibility

    if (isTrimming) {
      // === FIX ===: Trim mode halo
      borderPaint.color = const Color.fromARGB(255, 50, 139, 255);
      borderPaint.strokeWidth = 3;
    } else {
      // Existing border logic
      borderPaint.color =
          isSelected ? const Color(0xFF7A8B9C) : const Color(0xFF2A3A4C);
      borderPaint.strokeWidth = isSelected ? 2 : 1;
    }

    canvas.drawRRect(rect, borderPaint);

    // Draw edge handles if selected.
    if (showEdgeHandles && !isDragging) {
      _drawTrimHandles(
        canvas,
        rect,
        asStretchHandles: stretchToolActive && !isMidi,
        stretchEnabled: clip.stretchToProjectTempo,
        preservePitch: clip.tempoStretchPreservePitch,
      );
    }
  }

  void _drawWaveform(
    Canvas canvas,
    List<double> peaks,
    RRect rect,
    double trimStartMs,
    double fullDurationMs,
    double stretchScale,
  ) {
    if (peaks.isEmpty || rect.width <= 0 || rect.height <= 0) return;
    final safeFullDurationMs = fullDurationMs.clamp(1.0, double.infinity);
    final safeStretchScale = stretchScale.clamp(0.0001, double.infinity);
    final sourceMsPerPixel = 1.0 / (pixelsPerMs * safeStretchScale);
    if (!sourceMsPerPixel.isFinite || sourceMsPerPixel <= 0) return;

    final dpr =
        PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
    double snapToDevicePixel(double x) => (x * dpr).roundToDouble() / dpr;

    final visibleLeft = rect.left.clamp(0.0, viewportWidth).toDouble();
    final visibleRight = rect.right.clamp(0.0, viewportWidth).toDouble();
    if (visibleRight <= visibleLeft) return;

    final waveformPaint = Paint()
      ..color = const Color(0xFFF6FAFF).withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0 / dpr, 0.5)
      ..isAntiAlias = false;
    final centerY = rect.top + rect.height / 2;
    final maxAmplitude = rect.height / 2 - 4;
    if (maxAmplitude <= 0) return;

    final lastPeakIndex = peaks.length - 1;
    final sourceToPeak = lastPeakIndex / safeFullDurationMs;
    final path = Path();

    // Anchor bucketing to clip-local pixel columns to avoid temporal shimmer
    // when the clip scrolls by fractional pixels at zoomed-out scales.
    final startCol = math.max(0, (visibleLeft - rect.left).floor());
    final endCol = math.max(startCol + 1, (visibleRight - rect.left).ceil());
    final maxCol = rect.width.ceil();

    for (int col = startCol; col < endCol && col <= maxCol; col++) {
      final x0 = snapToDevicePixel(rect.left + col);

      final startSourceMs = trimStartMs + col.toDouble() * sourceMsPerPixel;
      final endSourceMs = trimStartMs + (col + 1.0) * sourceMsPerPixel;

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
        final amp = peaks[i].abs();
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
      ..color = const Color(0xFF9CF3A8).withOpacity(0.85)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
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

    if (notes.isEmpty) {
      final ghost = Paint()..color = Colors.white.withOpacity(0.16);
      final p = Path()
        ..moveTo(rect.left + 8, rect.bottom - 8)
        ..lineTo(rect.left + width * 0.32, rect.top + 8)
        ..lineTo(rect.left + width * 0.56, rect.bottom - 10)
        ..lineTo(rect.left + width * 0.82, rect.top + 10);
      canvas.drawPath(p, ghost);
      return;
    }

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
      previewPaint.color = Color.fromARGB(alpha, 159, 245, 174);
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
      ..color = const Color(0xFF000000).withOpacity(0.28); // translucent dark

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
    final handleColor = !asStretchHandles
        ? const Color.fromARGB(255, 40, 72, 168)
        : (!stretchEnabled
            ? const Color(0xFF687288)
            : (preservePitch
                ? const Color(0xFF2AAE9F)
                : const Color(0xFFD38A3D)));
    final handlePaint = Paint()
      ..color = handleColor
      ..style = PaintingStyle.fill;
    // Left trim handle
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.top, handleWidth, rect.height),
          const Radius.circular(4)),
      handlePaint,
    );
    // Right trim handle
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            rect.right - handleWidth, rect.top, handleWidth, rect.height),
        const Radius.circular(4),
      ),
      handlePaint,
    );
    // Draw handle grips
    final gripPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = 1.5;
    for (int i = 0; i < 3; i++) {
      final y = rect.top + rect.height / 2 + (i - 1) * 6;
      // Left grip
      canvas.drawLine(Offset(rect.left + 4, y),
          Offset(rect.left + handleWidth - 4, y), gripPaint);
      // Right grip
      canvas.drawLine(Offset(rect.right - handleWidth + 4, y),
          Offset(rect.right - 4, y), gripPaint);
    }
  }

  void _drawPlayhead(Canvas canvas, Size size) {
    // === FIX ===: Use playheadPx
    final x = playheadPx;
    const double rulerHeight = _AudioCanvasTimelineState.kRulerHeight;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    // extend playhead from just below ruler to bottom of timeline
    canvas.drawLine(
      Offset(x, -rulerHeight), // start right under the ruler area
      Offset(x, size.height),
      paint,
    );
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

    double yOffset = 0;
    for (int i = 0; i < row; i++) {
      yOffset += _AudioCanvasTimelineState.kRowHeight;
      if (rowExpanded[i]) {
        yOffset += expandedHeights[i];
      }
    }

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
    // Only repaint when timeline-visible state actually changes.
    return playheadPx != old.playheadPx || // playheadMs is not a prop
        bpm != old.bpm ||
        beatsPerBar != old.beatsPerBar ||
        scrollOffsetMs != old.scrollOffsetMs ||
        pixelsPerMs != old.pixelsPerMs ||
        viewportWidth != old.viewportWidth ||
        selectedClipIndex != old.selectedClipIndex ||
        _selectedClipIndicesHash != old._selectedClipIndicesHash ||
        draggedClipIndex != old.draggedClipIndex ||
        draggedClipStartMs != old.draggedClipStartMs ||
        draggedClipRowIndex != old.draggedClipRowIndex ||
        _rowExpandedHash != old._rowExpandedHash ||
        _expandedTabHash != old._expandedTabHash ||
        _effectsPanelHeightsHash != old._effectsPanelHeightsHash ||
        _expandedHeightsHash != old._expandedHeightsHash ||
        verticalScrollOffset != old.verticalScrollOffset ||
        stretchToolActive != old.stretchToolActive ||
        trimClipIndex != old.trimClipIndex ||
        _clipDataHash != old._clipDataHash ||
        quantizeDivisions != old.quantizeDivisions ||
        highlightedSegmentRow != old.highlightedSegmentRow ||
        highlightedSegmentStartMs != old.highlightedSegmentStartMs ||
        highlightedSegmentEndMs != old.highlightedSegmentEndMs ||
        sampleDropPreviewRow != old.sampleDropPreviewRow ||
        sampleDropPreviewStartMs != old.sampleDropPreviewStartMs ||
        sampleDropPreviewEndMs != old.sampleDropPreviewEndMs ||
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
    int barLabelStride;
    if (pxPerBar > 18) {
      barLabelStride = 1; // 1,2,3,4,...
    } else if (pxPerBar > 9) {
      barLabelStride = 2; // 1,3,5,...
    } else if (pxPerBar > 4.5) {
      barLabelStride = 4; // 1,5,9,...
    } else {
      barLabelStride = 8; // 1,9,17,...
    }

    // Draw bar markers
    final visibleStartMs = scrollOffsetMs;
    final visibleEndMs = scrollOffsetMs + viewportWidth / pixelsPerMs;
    final rawStartBar = (visibleStartMs / msPerBar).floor();
    final rawEndBar = (visibleEndMs / msPerBar).ceil();
    final startBar = math.max(0, math.min(rawStartBar, rawEndBar));
    final endBar = math.max(0, math.max(rawStartBar, rawEndBar));

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

class _AutomationLane extends StatefulWidget {
  final int rowIndex;
  final List<AutomationPoint> points; // x = timeMs, volume = 0..1
  final double pixelsPerMs;
  final double scrollOffsetMs;
  final double laneHeight;
  final double timelineDurationMs; // kept for future use, but not needed for x
  final ValueChanged<List<AutomationPoint>> onChanged;
  final void Function(Offset pos) onPanStartExternal;
  final void Function(Offset pos) onPanUpdateExternal;
  final VoidCallback onPanEndExternal;

  const _AutomationLane({
    Key? key,
    required this.rowIndex,
    required this.points,
    required this.pixelsPerMs,
    required this.scrollOffsetMs,
    required this.laneHeight,
    required this.timelineDurationMs,
    required this.onChanged,
    required this.onPanStartExternal,
    required this.onPanUpdateExternal,
    required this.onPanEndExternal,
  }) : super(key: key);

  @override
  State<_AutomationLane> createState() => _AutomationLaneState();
}

class _AutomationLaneState extends State<_AutomationLane> {
  static const double pointRadius = 8.0;
  static const double hitRadius = 20.0;
  static const double verticalPadding = 12.0;

  double get _usableHeight => widget.laneHeight - verticalPadding * 2;

  double _timeToPx(double timeMs) =>
      (timeMs - widget.scrollOffsetMs) * widget.pixelsPerMs;

  double _pxToTime(double px) =>
      (px / widget.pixelsPerMs) + widget.scrollOffsetMs;

  double _volumeToPy(double v) => verticalPadding + (1.0 - v) * _usableHeight;

  double _pyToVolume(double py) {
    double v = 1.0 - ((py - verticalPadding) / _usableHeight);
    return v.clamp(0.0, 1.0);
  }

  double _volToDb(double v) {
    if (v <= 0.0005) return double.negativeInfinity;
    return 20 * math.log(v) / math.log(10);
  }

  bool _dragging = false;

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

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
          // 1) Constructor
          () => PanGestureRecognizer()
            ..dragStartBehavior = DragStartBehavior.down,
          // 2) Initializer
          (PanGestureRecognizer instance) {
            // 👉 Start automation IMMEDIATELY on pointer down IF we are on a point.
            instance.onDown = (details) {
              final hit = _hitPoint(details.localPosition);
              if (hit != null) {
                // This will set _interactionMode = 'automation' and
                // _isUserInteracting = true in the parent.
                widget.onPanStartExternal(details.localPosition);
              }
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
      },
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (d) => _addPoint(d.localPosition),
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

  _AutomationPainter({
    required this.points,
    required this.scrollOffsetMs,
    required this.pixelsPerMs,
    required this.laneHeight,
    required this.verticalPadding,
  });

  double get _usableHeight => laneHeight - verticalPadding * 2;

  double _timeToPx(double timeMs) => (timeMs - scrollOffsetMs) * pixelsPerMs;

  double _volumeToPy(double v) => verticalPadding + (1.0 - v) * _usableHeight;

  double _volToDb(double v) {
    if (v <= 0.0001) return double.negativeInfinity;

    // Standard amplitude → dB
    final rawDb = 20 * math.log(v) / math.log(10);

    // Apply scaling so:
    // v=1.00 → +6 dB
    // v=0.75 →  0 dB
    // v=0.00 → -∞ dB
    return 2.401921537 * rawDb + 6.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const double axisWidth = 50;

    // 1) Dark background
    final bg = Paint()..color = const Color(0xFF151A26).withOpacity(0.9);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(0)),
        bg);

    // Horizontal guide lines
    final guidePaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;

    final topY = verticalPadding;
    final zeroY = _volumeToPy(0.75);
    final bottomY = verticalPadding + _usableHeight;

    canvas.drawLine(
        Offset(axisWidth, topY), Offset(size.width, topY), guidePaint);
    canvas.drawLine(
        Offset(axisWidth, zeroY), Offset(size.width, zeroY), guidePaint);
    canvas.drawLine(
        Offset(axisWidth, bottomY), Offset(size.width, bottomY), guidePaint);

    // Y-axis labels on the very left
    final tp = TextPainter(textDirection: TextDirection.ltr);

    // +6.0 dB (very top)
    tp.text = const TextSpan(
      text: "+6.0 dB",
      style: TextStyle(color: Colors.white70, fontSize: 10),
    );
    tp.layout();
    tp.paint(canvas, Offset(4, verticalPadding - 6));

    // +0.0 dB (~3/4 up)
    final zeroDbVolume = 0.75;
    final zeroDbPy = _volumeToPy(zeroDbVolume);
    tp.text = const TextSpan(
      text: "+0.0 dB",
      style: TextStyle(color: Colors.white70, fontSize: 10),
    );
    tp.layout();
    tp.paint(canvas, Offset(4, zeroDbPy - 6));

    // -∞ at bottom
    tp.text = const TextSpan(
      text: "-∞",
      style: TextStyle(color: Colors.white70, fontSize: 10),
    );
    tp.layout();
    tp.paint(canvas, Offset(4, verticalPadding + _usableHeight - 10));

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

    final clipRect =
        Rect.fromLTWH(axisWidth, 0, size.width - axisWidth, size.height);

    canvas.save();
    canvas.clipRect(clipRect);

    // ----- Automation curve inside the clipped area -----
    final linePaint = Paint()
      ..color = const Color(0xFF7AB9FF)
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

      final db = _volToDb(modelPoint.volume);
      final label = db.isInfinite ? "-∞" : "${db.toStringAsFixed(1)} dB";

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
        old.pixelsPerMs != pixelsPerMs;
  }
}

// -----------------------------------------------------------------------------
// BEAUTIFUL STYLED SLIDERS — Matches your screenshot exactly
// -----------------------------------------------------------------------------

class PrettyStereoSlider extends StatefulWidget {
  final double value; // 0 to 1
  final ValueChanged<double> onChangeStart, onChanged, onChangeEnd;

  const PrettyStereoSlider({
    super.key,
    required this.value,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<PrettyStereoSlider> createState() => _PrettyStereoSliderState();
}

class _PrettyStereoSliderState extends State<PrettyStereoSlider> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text("L", style: TextStyle(color: Colors.white, fontSize: 14)),

        const SizedBox(width: 6),

        // ⭐ THIS is the fix — Expanded makes the slider fill all space
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () {
              setState(() {
                widget.onChanged(0.5); // RESET to default
              });
            },
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: const Color(0xFF4D5566),
                inactiveTrackColor: const Color(0xFF4D5566),
                thumbColor: const Color(0xFFB7BECC),
              ),
              child: Slider(
                value: widget.value,
                min: 0,
                max: 1,
                label: widget.value.toStringAsFixed(3),
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
          ),
        ),

        const SizedBox(width: 6),

        Text("R", style: TextStyle(color: Colors.white, fontSize: 14)),
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
    this.dragStartBehavior = DragStartBehavior.down;
    this.minFlingDistance = 0;
    this.minFlingVelocity = 0;
  }

  @override
  void handleEvent(PointerEvent event) {
    // DO NOT auto-accept here!
    // This preserves tap, double-tap, long-press.
    super.handleEvent(event);
  }
}

class PrettyGainSlider extends StatefulWidget {
  final double value; // 0 - 3
  final ValueChanged<double> onChangeStart, onChanged, onChangeEnd;
  final bool showLabel;
  final Color trackColor;
  final Color thumbColor;

  const PrettyGainSlider({
    super.key,
    required this.value,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    this.showLabel = true,
    this.trackColor = const Color(0xFF4D5566),
    this.thumbColor = const Color(0xFFB7BECC),
  });

  @override
  State<PrettyGainSlider> createState() => _PrettyGainSliderState();
}

class _PrettyGainSliderState extends State<PrettyGainSlider> {
  double _gainToDb(double sliderValue) {
    if (sliderValue <= 0.0001) return double.negativeInfinity;

    // Match your DSP: perceptualGain = sliderValue^2 (clamped to 9)
    double perceptual = math.min(sliderValue * sliderValue, 9.0);

    return 20 * math.log(perceptual) / math.log(10); // log10
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (widget.showLabel)
          Text("Gain:", style: TextStyle(color: Colors.white, fontSize: 14)),
        if (widget.showLabel) const SizedBox(width: 6),

        // ⭐ FIX: Make slider stretch horizontally
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () {
              setState(() {
                widget.onChanged(1.0); // RESET to default
              });
            },
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: widget.trackColor,
                inactiveTrackColor: widget.trackColor.withOpacity(0.65),
                thumbColor: widget.thumbColor,
              ),
              child: Slider(
                value: widget.value,
                min: 0.0,
                max: 3.0,
                // divisions: 60,
                // label: () {
                //   final db = _gainToDb(widget.value);
                //   if (db.isInfinite) return "–∞ dB";
                //   return "${db.toStringAsFixed(1)} dB";
                // }(),
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
          ),
        ),

        // const SizedBox(width: 6),
        // SizedBox(
        //   width: 40, // Fixed width so layout never shifts
        //   child: Text(
        //     () {
        //       final db = _gainToDb(widget.value);
        //       if (db.isInfinite) return "–∞";
        //       return db > 0 ? "+${db.toStringAsFixed(1)} dB" : "${db.toStringAsFixed(1)} dB";
        //     }(),
        //     style: const TextStyle(color: Colors.white, fontSize: 12),
        //   ),
        // ),
        SizedBox(
          width: 50, // fixed width so slider never shifts
          child: Text(
            () {
              final db = _gainToDb(widget.value);
              if (db.isInfinite) return "–∞ dB";
              return db > 0
                  ? "+${db.toStringAsFixed(1)} dB"
                  : "${db.toStringAsFixed(1)} dB";
            }(),
            maxLines: 1,
            softWrap: false,
            overflow:
                TextOverflow.visible, // do NOT wrap, do NOT resize vertically
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12),
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

    double barH(double v) => (v.clamp(0.0, 1.0) as double) * s.height;

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
    final bg = Paint()..color = const Color(0xFF1A2230).withOpacity(0.95);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.10);

    c.drawRRect(r, bg);
    c.drawRRect(r, border);

    // --- Tick lines (subtle scale) ---
    final tick = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      final y = s.height * (i / 5.0);
      c.drawLine(
        Offset(1, y),
        Offset(s.width - 1, y),
        tick,
      );
    }

    // --- Meter paints ---
    final peakPaint = Paint()..color = Colors.white.withOpacity(0.80);
    final rmsPaint = Paint()..color = Colors.white.withOpacity(0.25);

    // --- Idle baseline (prevents “dead stick”) ---
    const idleFloor = 0.02;

    double barH(double v) => ((v + idleFloor).clamp(0.0, 1.0)) * s.height;

    // --- Lane gap between L/R ---
    const laneGap = 0.5;
    final laneW = (s.width - laneGap) / 2;

    // X positions
    final leftX = 0.0;
    final rightX = laneW + laneGap;

    // --- Left channel ---
    final rmsLH = barH(f.rmsL);
    final peakLH = barH(f.peakL);

    c.drawRect(
      Rect.fromLTWH(leftX, s.height - rmsLH, laneW, rmsLH),
      rmsPaint,
    );
    c.drawRect(
      Rect.fromLTWH(leftX, s.height - peakLH, laneW, peakLH),
      peakPaint,
    );

    // --- Right channel ---
    final rmsRH = barH(f.rmsR);
    final peakRH = barH(f.peakR);

    c.drawRect(
      Rect.fromLTWH(rightX, s.height - rmsRH, laneW, rmsRH),
      rmsPaint,
    );
    c.drawRect(
      Rect.fromLTWH(rightX, s.height - peakRH, laneW, peakRH),
      peakPaint,
    );

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
