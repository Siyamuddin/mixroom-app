import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'dart:math' as math;
import 'package:mixroom/models/models.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mixroom/widgets/effects_panel.dart';

class AudioCanvasTimeline extends StatefulWidget {
  final List<AudioTrack> clips;
  final List<double> rowGain;
  final List<double> rowPan;
  final List<bool> rowMuted;
  final List<bool> rowSoloed;
  final List<List<AutomationPoint>> rowVolumeAutomation;

  final double Function(AudioTrack) getStartMs;
  final double Function(AudioTrack) getDurationMs; // Should be: (trimEnd - trimStart)
  final double Function(AudioTrack) getTrimStartMs;
  final double Function(AudioTrack) getTrimEndMs;
  final double Function(AudioTrack) getFullDurationMs; // === FIX ===: Added this helper
  final List<double> Function(AudioTrack) getPeaks;
  final double Function(AudioTrack) getY; // This doesn't seem to be used?
  final void Function(int row) onSelectRow;
  final void Function(int row) onToggleRecord;
  final void Function(int row) onToggleExpanded;
  final void Function(int clipIndex, double newStartMs, int newRowIndex) onMoveClipCommit;
  final void Function(int clipIndex, double trimStartMs, double trimEndMs, {double? newStartMs}) onTrimClip;
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
  final Future<bool> Function(int row, int effectIndex) getRowEffectBypassState;
  final Future<void> Function(int row, String pathOrName) insertRowEffect;
  final Future<void> Function(int row, int effectIndex, String name, bool applyingPreset) removeRowEffect;
  final Future<void> Function(int row, int from, int to) reorderRowEffects;
  final Future<void> Function(int row, int effectIndex, bool bypass) setRowEffectBypassed;
  final Future<List<Map<String, dynamic>>> Function(int row, int effectIndex) getRowPluginParameters;
  final Future<void> Function(int row, int effectIndex, String paramId, dynamic value) setRowEffectParam;
  final Future<List<Map<String, dynamic>>> Function() scanPlugins;
  final Future<void> Function(int row, List<Map<String, dynamic>> points) setTrackAutomationPoints;
  final void Function(int row, List<AutomationPoint> oldPoints, List<AutomationPoint> newPoints)? onAutomationCommit;
  final Future<void> Function(int row, double gain) setRowGain;
  final Future<void> Function(int row, bool mute) muteRow;
  final Future<void> Function(int row, bool solo) soloRow;
  final void Function(int row, double oldGain, double newGain)? onRowGainCommit;
  final Future<void> Function(int row, double pan) setRowPan;
  final void Function(int row, double oldPan, double newPan)? onRowPanCommit;
  final void Function(int clipIndex) onCopyClip;
  final void Function(int clipIndex) onDeleteClip;
  final bool hasCopiedClip;
  final void Function(int row, double timeMs) onPasteClipAt;
  final void Function(int loopStartMs, int loopEndMs)? onLoopRegionChanged;
  final void Function(bool enabled)? onLoopToggle;
  final void Function(int row, int effectIndex, String paramId, dynamic oldValue, dynamic newValue)?
      onPluginParamCommit;
  final void Function(RowEffectsSnapshot before, RowEffectsSnapshot after)? onPresetCommit;
  final void Function(void Function(int row) refreshRowFx)? registerRowFxRefresher;

  final MeterBus meters;
  final Future<List<double>> Function(int row, int effectIndex) getRowCompressorMeter;

  final String mode; // "Basic" or "Pro"

  const AudioCanvasTimeline({
    Key? key,
    required this.rowGain,
    required this.rowPan,
    required this.rowMuted,
    required this.rowSoloed,
    required this.rowVolumeAutomation,
    required this.clips,
    required this.getStartMs,
    required this.getDurationMs,
    required this.getTrimStartMs,
    required this.getTrimEndMs,
    required this.getFullDurationMs, // === FIX ===
    required this.getPeaks,
    required this.getY,
    required this.onSelectRow,
    required this.recordingInProgress,
    required this.onToggleRecord,
    required this.onToggleExpanded,
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
    required this.onCopyClip,
    required this.onDeleteClip,
    required this.hasCopiedClip,
    required this.onPasteClipAt,
    this.onLoopRegionChanged,
    this.onLoopToggle,
    required this.mode,
    this.onPluginParamCommit,
    this.onPresetCommit,
    this.registerRowFxRefresher,
    required this.meters,
    required this.getRowCompressorMeter,
  }) : super(key: key);
  @override
  State<AudioCanvasTimeline> createState() => _AudioCanvasTimelineState();
}

class _AudioCanvasTimelineState extends State<AudioCanvasTimeline> {
  static const int kNumRows = 5;
  static const double kRowHeight = 80.0;
  static const double kExpandedRowHeight = kRowHeight *
      3; // try to make this dynamic to fit in all the stuff in the expanded area (risk of vertical overflow if too small)
  final List<double> _effectsPanelHeights = List.filled(kNumRows, kExpandedRowHeight);

  static const double kHeaderWidth = 80.0;
  static const double kRulerHeight = 40.0;
  static const double kTrimHandleWidth = 12.0;
  static const double kTrimHitboxPadding = 20.0; // === FIX ===: New constant for larger hitbox
  double _pixelsPerMs = 0.1; // Initial zoom level
  double _scrollOffsetMs = 0.0;
  int _selectedClipIndex = -1;
  int _selectedRowIndex = 0;
  // final List<bool> _rowMuted = List.filled(kNumRows, false);
  final List<bool> _rowExpanded = List.filled(kNumRows, false);
  final List<int> _expandedTab = List.filled(kNumRows, 0); // 0 = Volume, 1 = Effects
  final List<double> _rowYPositions = [];
  int? _recordRowIndex;

  // === FIX ===: Unified drag/trim state
  bool _isUserInteracting = false; // True if dragging clip, trimming, OR panning
  String _interactionMode = ''; // 'pan', 'drag', 'trim-start', 'trim-end'

  // Drag state
  int? _draggedClipIndex;
  double? _dragStartClipMs;
  int? _dragStartRow;
  Offset? _dragStartLocalOffset; // Local position where drag started
  Offset? _dragStartGlobalOffset; // === FIX ===: Added for total vertical displacement tracking

  // Trim state
  int? _trimClipIndex;
  double? _trimStartValue; // Original trim value at drag start
  double? _trimEndValue; // Original trim value at drag start
  double? _trimOriginalStartMs; // Original clip startMs at drag start
  double? _trimStartAnchorX; // === FIX ===: Anchor: Local X of where the touch began
  double? _activeTrimHandleX; // === FIX ===: The X anchor for the visual cue/tap
  double? newTrimStartUpdate, newTrimEndUpdate, newStartMsUpdate;

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

  bool _magnetEnabled = false;
  bool _loopEnabled = false;
  int?
      _loopStartMs; // made ints because when dragging loop handles, can get sub-ms numbers, but audio_editor converts to int
  int? _loopEndMs;
  bool _draggingLoopStart = false;
  bool _draggingLoopEnd = false;
  double? _loopDragOffsetMs;

  double? _gainDragStart;
  double? _panDragStart;

  // for updating the UI of the effects when JUCE state has changed
  final Map<int, VoidCallback> _rowEffectRefreshers = {};

  void _clearPastePopup() {
    if (_showPastePopup || _pasteRow != null || _pasteMs != null) {
      setState(() {
        _showPastePopup = false;
        _pasteRow = null;
        _pasteMs = null;
      });
    }
  }

  double _volumeToPyHelper(double v, int row) {
    final expandedOffset = _rowYPositions[row] + kRowHeight;
    final usableHeight = kExpandedRowHeight - 24;
    return expandedOffset + 12 + (1 - v) * usableHeight;
  }

  final ScrollController _verticalScrollController = ScrollController();
  double _verticalScrollOffset = 0.0;

  double get _maxDurationMs => widget.maxDuration.inMilliseconds.toDouble();

  @override
  void initState() {
    super.initState();
    _verticalScrollController.addListener(() {
      setState(() {
        _verticalScrollOffset = _verticalScrollController.offset;
      });
    });
    widget.registerRowFxRefresher?.call(_refreshRowFx);
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    super.dispose();
  }

  void _refreshRowFx(int row) {
    final refresh = _rowEffectRefreshers[row];
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
    double total = kNumRows * kRowHeight;
    for (int i = 0; i < kNumRows; i++) {
      if (_rowExpanded[i]) {
        // total += kExpandedRowHeight;
        total += (_expandedTab[i] == 0)
            ? kExpandedRowHeight // volume tab always fixed
            : _effectsPanelHeights[i]; // effects tab dynamic
      }
    }
    return total;
  }

  void _recalculateRowYPositions() {
    _rowYPositions.clear();

    double y = 0;
    for (int i = 0; i < _AudioCanvasTimelineState.kNumRows; i++) {
      _rowYPositions.add(y);
      y += kRowHeight;
      if (_rowExpanded[i]) {
        y += (_expandedTab[i] == 0) ? kExpandedRowHeight : _effectsPanelHeights[i];
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
    _automationBefore = widget.rowVolumeAutomation[row].map((p) => p.copy()).toList();

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
        final trimEnd = widget.getTrimEndMs(clip) + widget.getStartMs(clip);

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
    final normalized = 1 - ((effectiveFingerY - verticalPadding) / usableHeight);
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
        widget.onAutomationCommit!(row, before, after.map((p) => p.copy()).toList());
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

  Widget _buildSelectedClipPopup(double viewportWidth) {
    final bool visible = _selectedClipIndex >= 0 && _selectedClipIndex < widget.clips.length && _clipPopupMs != null;

    // If invisible, we still build (to animate) but we ignore pointer events
    final clip = (visible ? widget.clips[_selectedClipIndex!] : null);
    final rect = (visible ? _getClipRect(_selectedClipIndex!) : null);

    const double popupHeight = 32;

    // If invisible or no rect yet, place it off-screen safely
    double left = kHeaderWidth;
    double top = -100;

    if (visible && rect != null) {
      // left = kHeaderWidth + rect.left + rect.width / 2;
      // top = rect.top - popupHeight - 4;

      // left = left.clamp(
      //   kHeaderWidth + 4,
      //   kHeaderWidth + viewportWidth - 4,
      // );
      // if (top < 0) top = 0;

      final double px = (_clipPopupMs! - _scrollOffsetMs) * _pixelsPerMs;

      // if (px >= 0 && px <= viewportWidth) {
      left = kHeaderWidth + px - 60; // - popupWidth / 2;
      if (left > rect.right) left = rect.right;
      if (left < rect.left + kHeaderWidth) left = rect.left + kHeaderWidth;
      // left = left.clamp(rect.left + kHeaderWidth, rect.right + kHeaderWidth);

      top = rect.top - popupHeight - 4;
      if (top < 0) top = 0;
      // } else {
      // Offscreen in X → hide visually
      // left = kHeaderWidth;
      // top = -100;
      // }
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
            padding: const EdgeInsets.symmetric(horizontal: 10),
            height: popupHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF000000).withOpacity(0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.copy, size: 18, color: Colors.white),
                  onPressed: () {
                    if (_selectedClipIndex >= 0) widget.onCopyClip(_selectedClipIndex!);
                    setState(() => _selectedClipIndex = -1);
                  },
                ),
                Container(width: 1, height: 18, color: Colors.white24),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFFFA4A4)),
                  onPressed: () {
                    if (_selectedClipIndex >= 0) {
                      widget.onDeleteClip(_selectedClipIndex!);
                      setState(() => _selectedClipIndex = -1);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPastePopup(double viewportWidth) {
    final bool visible = _showPastePopup && _pasteRow != null && _pasteMs != null;

    const double popupHeight = 32;
    const double popupWidth = 70;

    double left = kHeaderWidth;
    double top = -100; // offscreen when hidden

    if (visible) {
      final double px = (_pasteMs! - _scrollOffsetMs) * _pixelsPerMs;

      if (px >= 0 && px <= viewportWidth) {
        // Compute properly only if on screen
        final row = _pasteRow!.clamp(0, kNumRows - 1);
        final rowTop = _rowYPositions[row];

        left = kHeaderWidth + px - popupWidth / 2;
        left = left.clamp(kHeaderWidth, kHeaderWidth + viewportWidth - popupWidth);

        top = rowTop - popupHeight - 4;
        if (top < 0) top = 0;
      } else {
        // Offscreen in X → hide visually
        left = kHeaderWidth;
        top = -100;
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
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.content_paste, size: 18, color: Colors.white),
                onPressed: () {
                  if (_pasteRow != null && _pasteMs != null) {
                    widget.onPasteClipAt(_pasteRow!, _pasteMs!);
                  }
                  _clearPastePopup();
                },
              ),
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
    int expectedRestartMs = (_loopEnabled && _loopStartMs != null) ? _loopStartMs! : 0;

    final bool isRestart = (!widget.isPlaying) &&
        (widget.playheadMs - expectedRestartMs).abs() < 0.01; // tiny epsilon, irrelevant cuz comparing with int

    if (isRestart) {
      final targetScrollMs = expectedRestartMs - (playheadPx) / _pixelsPerMs;
      if ((_scrollOffsetMs - targetScrollMs).abs() > 0.5) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _scrollOffsetMs = targetScrollMs;
              _clampScroll();
            });
          }
        });
      }
    }

    // --- During playback, keep playhead centered dynamically ---
    // if ((widget.isPlaying && !_isUserInteracting) || widget.playheadMs == 0.0) {
    if (widget.isPlaying) {
      // || widget.playheadMs == 0.0) {
      // === FIX ===: Use new playheadPx
      final targetScrollMs = widget.playheadMs - (playheadPx) / _pixelsPerMs;

      // Allow a small threshold to prevent jitter. this actually does *not* seem to affect app energy impact
      // if ((targetScrollMs - _scrollOffsetMs).abs() > (1.0 / _pixelsPerMs)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _scrollOffsetMs = targetScrollMs;
            _clampScroll(); // Apply clamping
          });
        }
      });
      // }
    }
    final List<double> expandedHeights = List.generate(kNumRows, (i) {
      if (!_rowExpanded[i]) return 0.0;
      return (_expandedTab[i] == 0) ? kExpandedRowHeight : _effectsPanelHeights[i];
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
            child: SingleChildScrollView(
              controller: _verticalScrollController,
              physics: _isUserInteracting && (_interactionMode == 'drag' || _interactionMode == 'automation')
                  ? const NeverScrollableScrollPhysics() // DISABLE V-SCROLL DURING DRAG
                  : const ClampingScrollPhysics(),
              child: SizedBox(
                height: _totalTimelineHeight, //kNumRows * kRowHeight,
                child: Stack(
                  children: [
                    // === Timeline background (waveforms, clips, playhead) ===
                    Positioned.fill(
                      left: kHeaderWidth, // 👈 ensures waveform starts after header
                      child: GestureDetector(
                        // dragStartBehavior: DragStartBehavior.start,
                        // === FIX ===: Added all gesture handlers
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        onScaleEnd: _onScaleEnd,
                        onTapDown: (details) => _handleTapDown(details),
                        onTapUp: (details) => _onTimelineTap(details, viewportWidth),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ClipRect(
                            child: CustomPaint(
                              painter: _TimelinePainter(
                                clips: widget.clips,
                                getStartMs: widget.getStartMs,
                                getDurationMs: widget.getDurationMs,
                                getTrimStartMs: widget.getTrimStartMs,
                                getTrimEndMs: widget.getTrimEndMs,
                                getPeaks: widget.getPeaks,
                                pixelsPerMs: _pixelsPerMs,
                                scrollOffsetMs: _scrollOffsetMs,
                                viewportWidth: viewportWidth,
                                playheadPx: playheadPx, // === FIX ===
                                selectedClipIndex: _selectedClipIndex,
                                trimClipIndex: _trimClipIndex, // === FIX ===: Pass the active trim index
                                // === FIX ===: Pass drag state to painter
                                draggedClipIndex: _draggedClipIndex,
                                draggedClipStartMs: _dragStartClipMs,
                                draggedClipRowIndex: _dragStartRow,
                                rowExpanded: _rowExpanded,
                                kExpandedRowHeight: kExpandedRowHeight,
                                verticalScrollOffset: _verticalScrollOffset,
                                expandedTab: _expandedTab,
                                effectsPanelHeights: _effectsPanelHeights,
                                expandedHeights: expandedHeights,
                                isRecording: widget.isRecording,
                                recordingRowIndex: widget.recordingRowIndex,
                                recordingStartMs: widget.recordingStartMs,
                                recordingPeaks: widget.recordingPeaks,
                                bpm: widget.bpm,
                                beatsPerBar: widget.beatsPerBar,
                              ),
                              size: Size(
                                viewportWidth,
                                _totalTimelineHeight,
                              ), //size: Size(viewportWidth, kNumRows * kRowHeight),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Expanded row panels (Volume/Effects)
                    ..._buildExpandedRows(viewportWidth),

                    // if (_selectedClipIndex != -1) _buildSelectedClipPopup(viewportWidth),
                    _buildSelectedClipPopup(viewportWidth),
                    // if (_showPastePopup && _pasteRow != null && _pasteMs != null) _buildPastePopup(viewportWidth),
                    _buildPastePopup(viewportWidth),

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
                        child: _buildTrackHeadersContent(_AudioCanvasTimelineState.kHeaderWidth),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildExpandedRows(double viewportWidth) {
    final list = <Widget>[];

    for (int row = 0; row < kNumRows; row++) {
      if (!_rowExpanded[row]) continue;

      final double topY = _rowYPositions[row] + kRowHeight;
      list.add(
        Positioned(
          left: kHeaderWidth,
          top: topY,
          width: viewportWidth,
          // height: (_expandedTab[row] == 0) ? kExpandedRowHeight : _effectsPanelHeights[row],
          // child:
          // _expandedTab[row] == 0 ? _buildVolumePanel(row) : _buildEffectsPanel(row),
          height: _expandedTab[row] == 0 ? kExpandedRowHeight : null, //_effectsPanelHeights[row],
          child: ClipRect(
            // prevents overflow painting
            child: Container(
              // margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                // borderRadius: BorderRadius.circular(0),
                border: Border.all(color: const Color.fromARGB(255, 47, 64, 117).withOpacity(0.28), width: 0),
              ),
              // padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              // padding: const EdgeInsets.only(bottom: 0),
              child: _expandedTab[row] == 0 ? _buildVolumePanel(row) : _buildEffectsPanel(row),
            ),
          ),
        ),
      );
    }

    return list;
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
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 3))],

              border: Border.all(
                color: selected ? Colors.white.withOpacity(0.28) : Colors.white.withOpacity(0.12),
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
      padding: const EdgeInsets.all(0), // const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    onPanStartExternal: (pos) => _automationPanStart(row, pos, laneHeight),
                    onPanUpdateExternal: (pos) => _automationPanUpdate(row, pos),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: PrettyStereoSlider(
                    value: widget.rowPan[row], // <-- plug in real per-track value
                    onChangeStart: (v) {
                      _panDragStart = v;
                    },
                    onChanged: (v) {
                      setState(() => widget.rowPan[row] = v);
                      widget.setRowPan(row, v);
                    },
                    onChangeEnd: (v) {
                      widget.onRowPanCommit!(row, _panDragStart!, widget.rowPan[row]);
                      _panDragStart = null;
                    },
                  ),
                ),

                const SizedBox(height: 10),

                // === Gain slider ===
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      widget.onRowGainCommit!(row, _gainDragStart!, widget.rowGain[row]);
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
      decoration: BoxDecoration(color: const Color(0xFF151A26).withOpacity(0.9)),
      child: RowEffectsPanel(
        key: ValueKey("effect_panel_row_$row"),
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
          _rowEffectRefreshers[row] = refreshFn;
        },
        projectBpm: widget.bpm,
        meters: widget.meters,
        getRowCompressorMeter: widget.getRowCompressorMeter,
      ),
    );
  }

  Widget _buildToggleButton({
    required IconData iconOn,
    required IconData iconOff,
    required bool active,
    required VoidCallback onTap,
    double size = 32,
    double iconSize = 20,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF4F70E4) : const Color(0x332F3645),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        alignment: Alignment.center,
        child: Icon(active ? iconOn : iconOff, size: iconSize, color: const Color.fromARGB(200, 255, 255, 255)),
      ),
    );
  }

  Widget _buildToggleButtonSvg({
    required bool active,
    required VoidCallback onTap,
    required String svgPath,
    double size = 30,
  }) {
    return GestureDetector(
      onTap: onTap,
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
          colorFilter: const ColorFilter.mode(Color.fromARGB(200, 255, 255, 255), BlendMode.srcIn),
        ),
      ),
    );
  }

  // for the magnet button
  double _quantizeMs(double rawMs) {
    if (!_magnetEnabled) return rawMs;

    final double msPerBeat = 60000 / widget.bpm;
    final double msPerBar = msPerBeat * widget.beatsPerBar;

    // Subdivide: bar → 1/2 → 1/4 → 1/8
    final double subdivision = msPerBar / 4.0;

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

  void _onRulerTapDown(TapDownDetails d) {
    if (!_loopEnabled) return;

    final localX = d.localPosition.dx;
    final viewportWidth = context.size!.width - kHeaderWidth;

    final startPx = (_loopStartMs! - _scrollOffsetMs) * _pixelsPerMs;
    final endPx = (_loopEndMs! - _scrollOffsetMs) * _pixelsPerMs;

    if (_isHandleVisible(startPx, viewportWidth) && _hitHandle(localX, startPx)) {
      setState(() => _draggingLoopStart = true);
      return;
    }
    if (_isHandleVisible(endPx, viewportWidth) && _hitHandle(localX, endPx)) {
      setState(() => _draggingLoopEnd = true);
      return;
    }
  }

  void _onRulerPanStart(DragStartDetails d) {
    if (!_loopEnabled) return;

    final fingerX = d.localPosition.dx;
    final fingerMs = _scrollOffsetMs + fingerX / _pixelsPerMs;

    if (_draggingLoopStart) {
      _loopDragOffsetMs = _loopStartMs! - fingerMs; // <-- critical
    }
    if (_draggingLoopEnd) {
      _loopDragOffsetMs = _loopEndMs! - fingerMs; // <-- critical
    }
  }

  // void _onRulerPanUpdate(DragUpdateDetails d) {
  //   if (!_loopEnabled) return;

  //   final deltaMs = d.delta.dx / _pixelsPerMs;

  //   // note: so this whole toInt() and toDouble() back and forth is because
  //   //       the result of the dragging could be sub millisecond level, but
  //   //       in the Dart level, we just have time at the millisecond level (ex. Duration(milliseconds: ____)).
  //   //       so we're fine sacrificing that sub-millisecond precision, cuz this is just
  //   //       for setting a loop start/end point. _loopStartMs and playheadMs need to be
  //   //       same so that in restart condition, they're interpreted as same number
  //   //       rather than diff numbers cuz of comparing int (playheadMs) to double (_loopStartMs).
  //   //       so this is really done in order for restart button to work with a
  //   //       loopStartMs that has been adjusted.
  //   if (_draggingLoopStart) {
  //     double snapped = _quantizeMs(_loopStartMs! + deltaMs);

  //     // clamp so start < end
  //     snapped = snapped.clamp(0, _loopEndMs! - 50);
  //     _loopStartMs = snapped.toInt();

  //     widget.onLoopRegionChanged?.call(_loopStartMs!, _loopEndMs!);
  //   }

  //   if (_draggingLoopEnd) {
  //     double snapped = _quantizeMs(_loopEndMs! + deltaMs);

  //     // clamp so end > start
  //     snapped = snapped.clamp(_loopStartMs! + 50, double.infinity);
  //     _loopEndMs = snapped.toInt();

  //     widget.onLoopRegionChanged?.call(_loopStartMs!, _loopEndMs!);
  //   }
  // }

  void _onRulerPanUpdate(DragUpdateDetails d) {
    if (!_loopEnabled || _loopDragOffsetMs == null) return;

    final fingerX = d.localPosition.dx;
    final fingerMs = _scrollOffsetMs + fingerX / _pixelsPerMs;

    // preserve offset → no first-frame teleport
    double target = fingerMs + _loopDragOffsetMs!;

    setState(() {
      if (_draggingLoopStart) {
        double snapped = _magnetEnabled ? _quantizeMs(target) : target;
        snapped = snapped.clamp(0, _loopEndMs! - 50.0);
        _loopStartMs = snapped.toInt();
        widget.onLoopRegionChanged?.call(_loopStartMs!, _loopEndMs!);
      }

      if (_draggingLoopEnd) {
        double snapped = _magnetEnabled ? _quantizeMs(target) : target;
        snapped = snapped.clamp(_loopStartMs! + 50.0, double.infinity);
        _loopEndMs = snapped.toInt();
        widget.onLoopRegionChanged?.call(_loopStartMs!, _loopEndMs!);
      }
    });
  }

  void _onRulerPanEnd(DragEndDetails d) {
    _draggingLoopStart = false;
    _draggingLoopEnd = false;
    _loopDragOffsetMs = null;
  }

  void _onRulerTapUp(TapUpDetails d) {
    setState(() {
      _draggingLoopStart = false;
      _draggingLoopEnd = false;
      _loopDragOffsetMs = null;
    });
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
                        onTap: () => setState(() => _magnetEnabled = !_magnetEnabled),
                        svgPath: 'assets/magnet-solid-full.svg',
                      ),
                      _buildToggleButton(
                        size: 30,
                        iconSize: 16,
                        iconOn: Icons.loop,
                        iconOff: Icons.loop_outlined,
                        active: _loopEnabled,
                        onTap: () {
                          setState(() {
                            _loopEnabled = !_loopEnabled;

                            if (_loopEnabled) {
                              final msPerBeat = 60000 / widget.bpm;
                              final msPerBar = msPerBeat * widget.beatsPerBar;

                              // Start at current playhead
                              _loopStartMs = widget.playheadMs.toInt();

                              // Default: 4 bars
                              _loopEndMs = (_loopStartMs! + msPerBar * 4).toInt();

                              // NEW: notify audio_editor
                              widget.onLoopToggle?.call(true);
                              widget.onLoopRegionChanged?.call(_loopStartMs!, _loopEndMs!);
                            } else {
                              _loopStartMs = null;
                              _loopEndMs = null;
                              widget.onLoopToggle?.call(false);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Ruler content
              Expanded(
                child: CustomPaint(
                  painter: _RulerPainter(
                    pixelsPerMs: _pixelsPerMs,
                    scrollOffsetMs: _scrollOffsetMs,
                    viewportWidth: viewportWidth,
                    bpm: widget.bpm,
                    beatsPerBar: widget.beatsPerBar,
                  ),
                  size: Size(viewportWidth, kRulerHeight),
                ),
              ),
              // Expanded(
              //   child: GestureDetector(
              //     behavior: HitTestBehavior.deferToChild, // IMPORTANT: capture taps
              //     onTapDown: _onRulerTapDown,
              //     onPanStart: _onRulerPanStart,
              //     onPanUpdate: _onRulerPanUpdate,
              //     onPanEnd: _onRulerPanEnd,
              //     child: CustomPaint(
              //       painter: _RulerPainter(
              //         pixelsPerMs: _pixelsPerMs,
              //         scrollOffsetMs: _scrollOffsetMs,
              //         viewportWidth: viewportWidth,
              //         bpm: widget.bpm,
              //         beatsPerBar: widget.beatsPerBar,
              //       ),
              //       size: Size(viewportWidth, kRulerHeight),
              //     ),
              //   ),
              // ),
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          if (!_loopEnabled) return;

          final dx = d.localPosition.dx + left - kHeaderWidth;
          final startPx = (_loopStartMs! - _scrollOffsetMs) * _pixelsPerMs;
          final endPx = (_loopEndMs! - _scrollOffsetMs) * _pixelsPerMs;

          const double hit = 34; // easier to grab with finger

          // start handle
          if ((dx - startPx).abs() <= hit) {
            setState(() => _draggingLoopStart = true);
            return;
          }

          // end handle
          if ((dx - endPx).abs() <= hit) {
            setState(() => _draggingLoopEnd = true);
            return;
          }
        },
        onPanStart: _onRulerPanStart,
        onPanUpdate: _onRulerPanUpdate,
        onPanEnd: _onRulerPanEnd,
        onTapUp: _onRulerTapUp,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFC5A5).withOpacity(0.33),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFFF9A6A), width: 2),
            boxShadow: [
              if (_draggingLoopStart || _draggingLoopEnd)
                BoxShadow(color: const Color(0xFFFF9A6A).withOpacity(0.25), blurRadius: 12, spreadRadius: 3),
            ],
          ),
        ),
      ),
    );

    // return Positioned(
    //   left: left,
    //   top: 0,
    //   width: width,
    //   height: kRulerHeight,
    //   child: GestureDetector(
    //     behavior: HitTestBehavior.opaque, // IMPORTANT: capture taps
    //     onTapDown: _onRulerTapDown,
    //     onPanStart: _onRulerPanStart,
    //     onPanUpdate: _onRulerPanUpdate,
    //     onPanEnd: _onRulerPanEnd,
    //     onTapUp: _onRulerTapUp,
    //     child: Container(
    //       decoration: BoxDecoration(
    //         color: const Color(0xFFFFC5A5).withOpacity(0.33),
    //         borderRadius: BorderRadius.circular(4),
    //         border: Border.all(color: const Color(0xFFFF9A6A), width: 2),
    //         boxShadow: [
    //           if (_draggingLoopStart || _draggingLoopEnd)
    //             BoxShadow(
    //               color: const Color(0xFFFF9A6A).withOpacity(0.25),
    //               blurRadius: 12,
    //               spreadRadius: 3,
    //             ),
    //         ],
    //       ),
    //     ),
    //   ),
    // );
  }

  Widget _buildTrackHeadersContent(double dynamicWidth) {
    return Column(
      children: List.generate(kNumRows, (row) {
        final isSelected = row == _selectedRowIndex;
        final isMuted = widget.rowMuted[row];
        final isRecording = _recordRowIndex == row;
        final isExpanded = _rowExpanded[row];

        return Column(
          children: [
            _buildOneTrackHeader(row, isSelected, isMuted, isRecording),
            if (isExpanded)
              SizedBox(
                height: (_expandedTab[row] == 0) ? kExpandedRowHeight : _effectsPanelHeights[row],
                width: dynamicWidth,
                child: _buildHeaderTabs(row),
              ),
          ],
        );
      }),
    );
  }

  Widget _buildOneTrackHeader(int row, bool isSelected, bool isMuted, bool isRecording) {
    return GestureDetector(
      onTap: () => setState(() {
        _selectedRowIndex = row;
        widget.onSelectRow(row);

        _rowExpanded[row] = !_rowExpanded[row];
        widget.onToggleExpanded(row);
      }),
      child: Container(
        height: kRowHeight, // Fixed height
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color.fromARGB(255, 55, 73, 108)
              : const Color.fromARGB(255, 30, 41, 65), //Colors.transparent,
          border: const Border(bottom: BorderSide(color: Color(0xFF1A1F2E), width: 1)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ... (Track header content unchanged, except using 'kRowHeight') ...
            // === Track number + arrow cluster (top-left) ===
            Positioned(
              left: 10,
              top: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${row + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => setState(() {
                      _rowExpanded[row] = !_rowExpanded[row];
                      widget.onToggleExpanded(row);
                    }),
                    child: Icon(
                      _rowExpanded[row] ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: Colors.white38,
                      size: 22,
                    ),
                  ),
                ],
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
                    color: isMuted ? const Color(0xFF5B6B8C) : Colors.transparent,
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
            // === Record button (bottom-right, smaller + tucked) ===
            Positioned(
              bottom: 1,
              right: -0.3,
              child: GestureDetector(
                onTap: () => setState(() {
                  if (!widget.recordingInProgress) {
                    _recordRowIndex = isRecording ? null : row;
                    widget.onToggleRecord(row);
                  }
                }),
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRecording ? Colors.red : Colors.transparent,
                    border: Border.all(color: isRecording ? Colors.red : Colors.white30, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.mic, size: 14, color: isRecording ? Colors.white : Colors.white30),
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

          // === SOLO BUTTON (RIGHT-ALIGNED) ===
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 7.5),
              child: GestureDetector(
                onTap: () {
                  bool newVal = !widget.rowSoloed[row];
                  widget.soloRow(row, newVal);
                },
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: widget.rowSoloed[row] ? const Color(0xFFFFB000) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white30),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'S',
                    style: TextStyle(
                      color: widget.rowSoloed[row] ? Colors.black : Colors.white38,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

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
    _isUserInteracting = true;
    _initialPixelsPerMs = _pixelsPerMs;
    _initialScrollMs = _scrollOffsetMs;

    _clearPastePopup();

    if (_interactionMode == 'automation') return;

    // === 1. TRIM HANDLE WAS TAPPED? → Start trim mode immediately ===
    if (_trimClipIndex != null && _activeTrimHandleX != null) {
      final clip = widget.clips[_trimClipIndex!];
      final clipRect = _getClipRect(_trimClipIndex!)!;
      final isTrimStart =
          (details.localFocalPoint.dx - clipRect.left).abs() < (details.localFocalPoint.dx - clipRect.right).abs();

      _interactionMode = isTrimStart ? 'trim-start' : 'trim-end';

      _trimStartValue = widget.getTrimStartMs(clip);
      _trimEndValue = widget.getTrimEndMs(clip);
      _trimOriginalStartMs = widget.getStartMs(clip);
      _trimStartAnchorX = details.localFocalPoint.dx;

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
    if (!_isUserInteracting) return;

    if (_interactionMode == 'automation') return;

    switch (_interactionMode) {
      case 'drag':
        _handleDragUpdate(details);
        break;
      case 'trim-start':
      case 'trim-end':
        _handleTrimUpdate(details);
        break;
      case 'pan':
      default:
        _handlePanZoomUpdate(details);
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_interactionMode == 'automation') {
      setState(() {
        _interactionMode = '';
        _isUserInteracting = false;
      });
      return;
    }

    if (_interactionMode == 'drag' && _draggedClipIndex != null) {
      // Commit the drag
      widget.onMoveClipCommit(_draggedClipIndex!, _dragStartClipMs!, _dragStartRow!);
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
      // _dragStartClipMs and _dragStartRow are kept for the painter until commit
      // _activeTrimHandleX = null;
      _trimClipIndex = null;
      _trimStartValue = null;
      _trimEndValue = null;
      _trimOriginalStartMs = null;
      _trimStartAnchorX = null; // === FIX ===
      _initialPixelsPerMs = null;
      _initialScrollMs = null;
    });
  }

  // --- Drag/Trim/Pan Handlers ---

  void _handleDragUpdate(ScaleUpdateDetails details) {
    if (_draggedClipIndex == null || _dragStartGlobalOffset == null) return;

    setState(() {
      // Calculate TOTAL delta from drag start (for row)
      final totalDx = details.focalPoint.dx - _dragStartGlobalOffset!.dx;
      final totalDy = details.focalPoint.dy - _dragStartGlobalOffset!.dy; // === FIX ===: Use totalDy for row

      // Convert to delta in Ms
      final deltaMs = totalDx / _pixelsPerMs;

      // Convert total vertical displacement to row index
      // Use the *original* row index to calculate the new one based on total vertical drag
      final originalRow = widget.clips[_draggedClipIndex!].rowIndex;
      final newRow =
          originalRow + (totalDy / kRowHeight).round(); // === FIX ===: Calculate new row from total displacement

      // Update the *temporary* drag state
      // The painter will use these values to draw the ghost clip
      _dragStartClipMs = _quantizeMs(
        (widget.getStartMs(widget.clips[_draggedClipIndex!])) + deltaMs,
      ); // === FIX ===: Start from original clip position + delta
      _dragStartRow = newRow; // === FIX ===: Use the calculated new row

      // Clamp row
      _dragStartRow = _dragStartRow?.clamp(0, kNumRows - 1);
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
        newTrimStart = (_trimStartValue! + maxAllowedDeltaTrim).clamp(0.0, newTrimEnd - 50.0);
      } else {
        newStartMs = attemptedNewStartMs; // <-- This is the ripple move calculation
      }
    } else if (_interactionMode == 'trim-end') {
      newTrimEnd = (_trimEndValue! + deltaMs).clamp(newTrimStart + 50.0, fullDuration);

      if (_magnetEnabled) {
        newTrimEnd = _quantizeMs(newTrimEnd);
      }
      // newStartMs remains null, correctly signaling no position change
    }

    if (newStartMs != null) {
      widget.onTrimClip(_trimClipIndex!, newTrimStart, newTrimEnd, newStartMs: newStartMs);
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

  void _handlePanZoomUpdate(ScaleUpdateDetails details) {
    setState(() {
      // --- Handle Zoom ---
      if (details.scale != 1.0 && _initialPixelsPerMs != null) {
        final newPixelsPerMs = (_initialPixelsPerMs! * details.scale).clamp(0.0025, 1.0);

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
        : math.max(_maxDurationMs, msFor128Bars(widget.bpm)) - (playheadPx / _pixelsPerMs);

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
    final trimEnd = widget.getTrimEndMs(clip);
    final row = clip.rowIndex;

    final x = (startMs - _scrollOffsetMs) * _pixelsPerMs;
    final width = (trimEnd - trimStart) * _pixelsPerMs;
    double yOffset = 0;
    for (int i = 0; i < row; i++) {
      yOffset += kRowHeight;

      if (_rowExpanded[i]) {
        // Use dynamic height
        yOffset += (_expandedTab[i] == 0) ? kExpandedRowHeight : _effectsPanelHeights[i];
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
    final tapRow = (localY / kRowHeight).floor().clamp(0, kNumRows - 1);

    // Iterate backwards to prioritize clips drawn later (higher index clips are usually drawn on top)
    for (int i = widget.clips.length - 1; i >= 0; i--) {
      final clip = widget.clips[i];
      final startMs = widget.getStartMs(clip);
      final durationMs = widget.getDurationMs(clip);
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
    for (int i = 0; i < kNumRows; i++) {
      double rowTotalHeight = kRowHeight;
      if (_rowExpanded[i]) {
        // Use dynamic height
        rowTotalHeight += (_expandedTab[i] == 0) ? kExpandedRowHeight : _effectsPanelHeights[i];
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
      final visualDuration = widget.getTrimEndMs(clip) - widget.getTrimStartMs(clip);
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

    _clearPastePopup();

    // === 1. Reset any previous trim cue ===
    setState(() {
      _activeTrimHandleX = null;
      _trimClipIndex = null;
    });

    final localPos = details.localPosition;
    final tappedClipIndex = _getClipIndexAt(localPos);

    // === 2. MUST CHECK: Are we tapping on the SELECTED clip? ===
    if (tappedClipIndex == null || tappedClipIndex != _selectedClipIndex) {
      return; // Not on selected clip → nothing to trim or drag
    }

    // if (tappedClipIndex == null) return;

    // // ALWAYS select the topmost tapped clip FIRST
    // if (_selectedClipIndex != tappedClipIndex) {
    //   setState(() {
    //     _selectedClipIndex = tappedClipIndex;
    //   });
    // }

    final clipRect = _getClipRect(tappedClipIndex);
    if (clipRect == null) return;

    final localX = localPos.dx;

    // === 3. PRIORITY 1: TRIM HANDLE HIT? (WINS OVER DRAG) ===
    final leftHandleHit =
        localX >= clipRect.left - kTrimHitboxPadding && localX <= clipRect.left + kTrimHandleWidth + kTrimHitboxPadding;

    final rightHandleHit = localX >= clipRect.right - kTrimHandleWidth - kTrimHitboxPadding &&
        localX <= clipRect.right + kTrimHitboxPadding;

    if (leftHandleHit || rightHandleHit) {
      // TRIM WINS — show visual cue and prepare for trim
      setState(() {
        _trimClipIndex = tappedClipIndex;
        _activeTrimHandleX = leftHandleHit ? clipRect.left : clipRect.right;
        // DO NOT set _interactionMode here — let onScaleStart do it
        // This ensures trim gesture starts cleanly
      });
      return; // STOP — do NOT allow drag
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
      });
      return;
    }

    // === 5. TAP ELSEWHERE → clear trim cue ===
    setState(() {
      _activeTrimHandleX = null;
      _trimClipIndex = null;
    });
  }

  void _onTimelineTap(TapUpDetails details, double viewportWidth) {
    if (_interactionMode == 'automation') return;

    if (_interactionMode == 'drag') {
      setState(() {
        _interactionMode = '';
        _draggedClipIndex = null;
        _pendingDrag = false; // unused I think
        _pendingLocalDown = null; // unused I think
        _isUserInteracting = false;
      });
      return;
    }

    final localX = details.localPosition.dx;
    final localY = details.localPosition.dy;
    // === MODIFIED: Use new row calculation logic ===
    final tapMs = _scrollOffsetMs + localX / _pixelsPerMs;

    double currentY = 0;
    int tapRow = -1;
    for (int i = 0; i < kNumRows; i++) {
      double rowTotalHeight = kRowHeight;

      if (_rowExpanded[i]) {
        // Use dynamic height
        rowTotalHeight += (_expandedTab[i] == 0) ? kExpandedRowHeight : _effectsPanelHeights[i];
      }

      if (localY >= currentY && localY < currentY + rowTotalHeight) {
        tapRow = i;
        break;
      }
      currentY += rowTotalHeight;
    }
    if (tapRow == -1) return;
    //     bool tappedClip = false;
    //     for (int i = 0; i < widget.clips.length; i++) {
    //       final clip = widget.clips[i];
    //       final startMs = widget.getStartMs(clip);
    // // Use the trimmed duration for hit testing in the tap handler
    //       final visualDuration = widget.getTrimEndMs(clip) - widget.getTrimStartMs(clip);
    //       final endMs = startMs + visualDuration;
    //       if (clip.rowIndex == tapRow && tapMs >= startMs && tapMs <= endMs) {
    //         setState(() => _selectedClipIndex = i);
    //         _clipPopupMs = tapMs;
    //         tappedClip = true;
    //         break;
    //       }
    //     }
    bool tappedClip = false;

    // Collect all clips that collide at this tap point
    final candidates = <int>[];

    for (int i = 0; i < widget.clips.length; i++) {
      final clip = widget.clips[i];

      if (clip.rowIndex != tapRow) continue;

      final startMs = widget.getStartMs(clip);
      final visualDuration = widget.getTrimEndMs(clip) - widget.getTrimStartMs(clip);
      final endMs = startMs + visualDuration;

      if (tapMs >= startMs && tapMs <= endMs) {
        candidates.add(i);
      }
    }

    if (candidates.isNotEmpty) {
      // Pick the topmost clip (drawn last = highest index)
      final topIndex = candidates.reduce((a, b) => a > b ? a : b);

      setState(() => _selectedClipIndex = topIndex);
      _clipPopupMs = tapMs;
      tappedClip = true;
    }

    if (!tappedClip) {
      setState(() {
        _selectedClipIndex = -1;

        // If we have something copied, show paste popup here
        if (widget.hasCopiedClip) {
          _pasteRow = tapRow;
          _pasteMs = tapMs;
          _showPastePopup = true;
        } else {
          _clearPastePopup();
        }
      });
      // === FIX ===: Scrub on empty space tap
      // widget.onScrubRequested(tapMs);
    }
    if (_trimClipIndex != null) {
      setState(() {
        _activeTrimHandleX = null;
        _trimClipIndex = null;
      });
    }
  }
}

// === Custom painter for the timeline ===
class _TimelinePainter extends CustomPainter {
  final List<AudioTrack> clips;
  final double Function(AudioTrack) getStartMs;
  final double Function(AudioTrack) getDurationMs;
  final double Function(AudioTrack) getTrimStartMs;
  final double Function(AudioTrack) getTrimEndMs;
  final List<double> Function(AudioTrack) getPeaks;
  final double pixelsPerMs;
  final double scrollOffsetMs;
  final double viewportWidth;
  final double playheadPx; // === FIX ===: Use playheadPx
  final int selectedClipIndex;
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

  _TimelinePainter({
    required this.clips,
    required this.getStartMs,
    required this.getDurationMs,
    required this.getTrimStartMs,
    required this.getTrimEndMs,
    required this.getPeaks,
    required this.pixelsPerMs,
    required this.scrollOffsetMs,
    required this.viewportWidth,
    required this.playheadPx, // === FIX ===
    required this.selectedClipIndex,
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
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // canvas.translate(0, -verticalScrollOffset); // ← APPLY VERTICAL SCROLL
    // Keep track of the current vertical position
    double currentY = 0;

    // convert playheadPx → ms
    final double playheadMs = scrollOffsetMs + playheadPx / pixelsPerMs;

    // Draw row backgrounds
    for (int row = 0; row < _AudioCanvasTimelineState.kNumRows; row++) {
      final rowHeight = _AudioCanvasTimelineState.kRowHeight;
      final isExpanded = rowExpanded[row];
      // final expandedHeight = isExpanded ? kExpandedRowHeight : 0;
      final expandedHeight = expandedHeights[row];

      final totalRowHeight = rowHeight + expandedHeight;

      // 1. Draw the main track background (alternating colors)
      final rect = Rect.fromLTWH(0, currentY, viewportWidth, rowHeight);
      final paint = Paint()..color = row % 2 == 0 ? const Color(0xFF1A1F2E) : const Color(0xFF151A26);
      canvas.drawRect(rect, paint);

      // 2. Draw the expanded section background (transparent, but maybe a slight tint for debugging/visual separation)
      if (isExpanded) {
        final expandedRect = Rect.fromLTWH(0, currentY + rowHeight, viewportWidth, expandedHeight.toDouble());
        final expandedPaint = Paint()..color = const Color(0xFF1A1F2E).withOpacity(0.9); // Semi-transparent overlay
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

    // Draw clips
    // ... (Clip drawing logic remains the same, but _drawClip needs modification) ...
    for (int i = 0; i < clips.length; i++) {
      if (i == draggedClipIndex) continue;
      _drawClip(canvas, i, false);
    }
    if (draggedClipIndex != null) {
      _drawClip(canvas, draggedClipIndex!, true);
    }

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
    final majorPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1.5;

    final minorPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1;

    final msPerBeat = 60000 / bpm;
    final msPerBar = msPerBeat * beatsPerBar;

    final visibleStartMs = scrollOffsetMs;
    final visibleEndMs = scrollOffsetMs + viewportWidth / pixelsPerMs;

    // ✅ CLAMP so nothing appears before bar 1
    final startBar = math.max(0, (visibleStartMs / msPerBar).floor());
    final endBar = (visibleEndMs / msPerBar).ceil();

    for (int bar = startBar; bar <= endBar; bar++) {
      final barMs = bar * msPerBar;
      final barX = (barMs - scrollOffsetMs) * pixelsPerMs;

      if (barX >= 0 && barX <= viewportWidth) {
        // === BAR LINE ===
        canvas.drawLine(Offset(barX, 0), Offset(barX, size.height), majorPaint);
      }

      // === BEAT LINES ===
      for (int beat = 1; beat < beatsPerBar; beat++) {
        final beatMs = barMs + beat * msPerBeat;
        final beatX = (beatMs - scrollOffsetMs) * pixelsPerMs;

        if (beatX >= 0 && beatX <= viewportWidth) {
          canvas.drawLine(Offset(beatX, 0), Offset(beatX, size.height), minorPaint);
        }
      }
    }
  }

  void _drawClip(Canvas canvas, int index, bool isDragging) {
    final clip = clips[index];

    // === FIX ===: Use drag state if provided
    final startMs = isDragging ? (draggedClipStartMs ?? getStartMs(clip)) : getStartMs(clip);
    final durationMs = getDurationMs(clip); // Duration (width) doesn't change on drag
    final trimStartMs = getTrimStartMs(clip);
    final trimEndMs = getTrimEndMs(clip);
    final peaks = getPeaks(clip);
    final visualDuration = trimEndMs - trimStartMs;
    final row = isDragging ? (draggedClipRowIndex ?? clip.rowIndex) : clip.rowIndex;

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
        yOffset += (expandedTab[i] == 0) ? kExpandedRowHeight : effectsPanelHeights[i];
      }
    }

    // visual left follows the new startMs
    final x = (startMs - scrollOffsetMs) * pixelsPerMs;
    final y = yOffset + 2; //final y = row * _AudioCanvasTimelineState.kRowHeight;
    final width = visualDuration * pixelsPerMs;
    const double height = _AudioCanvasTimelineState.kRowHeight - 4;

    // Skip if completely off-screen
    if (x + width < 0 || x > viewportWidth) return;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, width, height), // Use calculated y
      const Radius.circular(6),
    );
    // ... (Overlap check logic is unchanged) ...
    final thisEnd = startMs + visualDuration;
    bool hasOverlap = false;
    for (int i = 0; i < clips.length; i++) {
      if (i == index) continue;
      final otherClip = clips[i];
      if (otherClip.rowIndex != row) continue;

      final otherStart = getStartMs(otherClip);
      // Explicitly use trimmed duration for other clip's end time
      final otherTrimmedDuration = getTrimEndMs(otherClip) - getTrimStartMs(otherClip);
      final otherEnd = otherStart + otherTrimmedDuration;

      if (!(thisEnd <= otherStart || startMs >= otherEnd)) {
        hasOverlap = true;
        break;
      }
    }

    // Draw clip background
    final clipPaint = Paint()
      ..color = hasOverlap
          ? const Color(0xFF8B3A3A)
          : (index == selectedClipIndex ? const Color(0xFF4A5B7C) : const Color(0xFF3A4A5C));

    // === FIX ===: Make dragged clip semi-transparent
    if (isDragging) {
      clipPaint.color = clipPaint.color.withOpacity(0.6);
    }

    canvas.drawRRect(rect, clipPaint);

    // Draw waveform
    if (peaks.isNotEmpty && width > 30) {
      canvas.save();
      canvas.clipRRect(rect); // This is the crucial clipping/stencil

      // 1. Get the total pixel width of the ORIGINAL, UNTRIMMED file
      final fullDurationMs = clip.audioDuration.inMilliseconds.toDouble();
      final waveDrawWidth = fullDurationMs * pixelsPerMs;

      // === MODIFIED CALL ===: Pass the visual, trimmed RRect (rect)
      // and the full duration info for internal calculation.
      _drawWaveform(
        canvas,
        peaks, // Assuming 'peaks' is the FULL waveform data
        rect, // Pass the visual, trimmed RRect
        trimStartMs,
        trimEndMs,
        fullDurationMs,
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
      borderPaint.color = index == selectedClipIndex ? const Color(0xFF7A8B9C) : const Color(0xFF2A3A4C);
      borderPaint.strokeWidth = index == selectedClipIndex ? 2 : 1;
    }

    canvas.drawRRect(rect, borderPaint);

    // Draw trim handles if selected
    if (index == selectedClipIndex && !isDragging) {
      _drawTrimHandles(canvas, rect);
    }
  }

  void _drawWaveform(
    Canvas canvas,
    List<double> peaks,
    RRect rect,
    double trimStartMs,
    double trimEndMs,
    double fullDurationMs,
  ) {
    if (peaks.isEmpty) return;
    // Total width of the waveform if it were fully visible (in pixels)
    final fullWaveformWidth = fullDurationMs * pixelsPerMs;

    // 1. Calculate the offset required to make the waveform's 0ms point
    // align with the clip's visual start point (rect.left).
    // The visual clip has been shifted left by the amount of the scroll offset
    // AND the clip's starting time (getStartMs(clip)).
    // To correctly draw the waveform inside this visible rect:
    // We must shift the waveform drawing context to the LEFT by the amount of
    // the source material that was trimmed off the start (trimStartMs).
    final trimOffsetPx = trimStartMs * pixelsPerMs;

    // The visible clip (rect) is already positioned correctly on the screen
    // based on the clip's *current* start time and the scroll offset.

    // === CRITICAL TRANSFORMATION FIX ===
    // Shift the canvas LEFT by the trimOffsetPx.
    // This makes the point corresponding to trimStartMs (in the full waveform)
    // align with the current canvas's 0 X-coordinate.
    canvas.translate(-trimOffsetPx, 0);

    // Now, draw the FULL waveform starting at the visual rect's X position.
    // Since the canvas is translated, rect.left now corresponds to the
    // on-screen position where the full waveform should begin drawing.
    final drawRect = Rect.fromLTWH(rect.left, rect.top, fullWaveformWidth, rect.height);

    final waveformPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.fill;
    final centerY = rect.top + rect.height / 2;
    final maxAmplitude = rect.height / 2 - 4;

    final numPeaks = peaks.length;
    // Base calculations on FULL width to maintain correct peak spacing
    final pixelsPerPeak = fullWaveformWidth / numPeaks;

    for (int i = 0; i < numPeaks; i++) {
      final amplitude = peaks[i].abs().clamp(0.0, 1.0);
      final barHeight = amplitude * maxAmplitude;

      // X position is relative to the clip's visual start (drawRect.left) + the peak index
      final x = drawRect.left + i * pixelsPerPeak;
      final barWidth = math.max(1.0, pixelsPerPeak);

      // This drawRect is relative to the transformed canvas
      canvas.drawRect(Rect.fromLTWH(x, centerY - barHeight, barWidth, barHeight * 2), waveformPaint);

      // Optimization: if peaks are denser than pixels, skip forward
      // if (pixelsPerPeak < 1.0) {
      //   i += (1.0 / pixelsPerPeak).floor() - 1;
      // }
    }
  }

  void _drawClipLabel(Canvas canvas, RRect rect, AudioTrack clip) {
    const double labelHeight = 18.0;
    const double horizontalPadding = 6.0;

    String labelName = clip.label.isEmpty ? "Audio Clip" : clip.label;

    final tp = TextPainter(textDirection: TextDirection.ltr, maxLines: 1, ellipsis: "…");

    tp.text = TextSpan(
      text: labelName,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white),
    );

    // tp.layout(
    //   maxWidth: rect.width - horizontalPadding * 2, //rect.width * 0.6 - horizontalPadding * 2,
    // );

    final usableWidth = math.max(0.0, rect.width - horizontalPadding * 2);

    tp.layout(maxWidth: usableWidth);

    final textWidth = tp.width;

    // Background should fit exactly the rendered text
    double labelWidth = textWidth + horizontalPadding * 2;

    // If the label would be forced to clamp into a near-zero range, hide it (prevents jitter)
    if (rect.right <= labelWidth + 1.0) return;

    // keep label visible: clamp to [0..clipRight-labelWidth]
    final double labelLeft = rect.left.clamp(0.0, rect.right - labelWidth);

    // Clamp so we never exceed clip width
    labelWidth = labelWidth.clamp(0, rect.width);

    // Label background
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelLeft, //rect.left,
        rect.top,
        labelWidth, // Clip label area as wide as text
        labelHeight,
      ),
      const Radius.circular(4), //TODO: think about making this not circular and have squared corner
    );

    final bgPaint = Paint()..color = const Color(0xFF000000).withOpacity(0.28); // translucent dark

    canvas.drawRRect(bgRect, bgPaint);
    // Draw text centered vertically within the label area
    tp.paint(canvas, Offset(labelLeft + horizontalPadding, rect.top + (labelHeight - tp.height) / 2));
  }

  void _drawTrimHandles(Canvas canvas, RRect rect) {
    // ... (This function is unchanged, leaving as-is)
    const handleWidth = _AudioCanvasTimelineState.kTrimHandleWidth;
    final handlePaint = Paint()
      ..color = const Color.fromARGB(255, 40, 72, 168)
      ..style = PaintingStyle.fill;
    // Left trim handle
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(rect.left, rect.top, handleWidth, rect.height), const Radius.circular(4)),
      handlePaint,
    );
    // Right trim handle
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.right - handleWidth, rect.top, handleWidth, rect.height),
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
      canvas.drawLine(Offset(rect.left + 4, y), Offset(rect.left + handleWidth - 4, y), gripPaint);
      // Right grip
      canvas.drawLine(Offset(rect.right - handleWidth + 4, y), Offset(rect.right - 4, y), gripPaint);
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
    // === FIX ===: Updated properties
    return playheadPx != old.playheadPx || // playheadMs is not a prop
        scrollOffsetMs != old.scrollOffsetMs ||
        pixelsPerMs != old.pixelsPerMs ||
        selectedClipIndex != old.selectedClipIndex ||
        draggedClipIndex != old.draggedClipIndex ||
        draggedClipStartMs != old.draggedClipStartMs ||
        draggedClipRowIndex != old.draggedClipRowIndex ||
        !listEquals(rowExpanded, old.rowExpanded) ||
        verticalScrollOffset != old.verticalScrollOffset ||
        trimClipIndex != old.trimClipIndex ||
        getTrimStartMs != old.getTrimStartMs ||
        getTrimEndMs != old.getTrimEndMs ||
        isRecording != old.isRecording ||
        recordingRowIndex != old.recordingRowIndex ||
        recordingStartMs != old.recordingStartMs ||
        !listEquals(recordingPeaks, old.recordingPeaks);
  }

  bool listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// === Custom painter for the ruler ===
class _RulerPainter extends CustomPainter {
  final double pixelsPerMs;
  final double scrollOffsetMs;
  final double viewportWidth;
  final double bpm;
  final int beatsPerBar;
  _RulerPainter({
    required this.pixelsPerMs,
    required this.scrollOffsetMs,
    required this.viewportWidth,
    required this.bpm,
    required this.beatsPerBar,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr, textAlign: TextAlign.center);
    final majorTickPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.5;
    final minorTickPaint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 1;
    // Calculate beat duration
    final msPerBeat = 60000 / bpm;
    final msPerBar = msPerBeat * beatsPerBar;

    final pxPerBar = msPerBar * pixelsPerMs;
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
    final startBar = math.max(0, (scrollOffsetMs / msPerBar).floor());
    final endBar = ((scrollOffsetMs + viewportWidth / pixelsPerMs) / msPerBar).ceil();
    for (int bar = startBar; bar <= endBar; bar++) {
      final barMs = bar * msPerBar;
      // === FIX ===: Removed offset
      final x = (barMs - scrollOffsetMs) * pixelsPerMs;
      if (x >= 0 && x <= viewportWidth) {
        // Draw major tick
        canvas.drawLine(Offset(x, size.height - 15), Offset(x, size.height), majorTickPaint);
        // Draw bar number ONLY if stride matches
        if (bar % barLabelStride == 0) {
          textPainter.text = TextSpan(
            text: '${bar + 1}',
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(x - textPainter.width / 2, 5));
        }
      }
      // Draw beat markers within the bar
      for (int beat = 1; beat < beatsPerBar; beat++) {
        final beatMs = barMs + beat * msPerBeat;
        // === FIX ===: Removed offset
        final beatX = (beatMs - scrollOffsetMs) * pixelsPerMs;
        if (beatX >= 0 && beatX <= viewportWidth) {
          canvas.drawLine(Offset(beatX, size.height - 8), Offset(beatX, size.height), minorTickPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) {
    return scrollOffsetMs != oldDelegate.scrollOffsetMs || pixelsPerMs != oldDelegate.pixelsPerMs;
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

  double _timeToPx(double timeMs) => (timeMs - widget.scrollOffsetMs) * widget.pixelsPerMs;

  double _pxToTime(double px) => (px / widget.pixelsPerMs) + widget.scrollOffsetMs;

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
        PanGestureRecognizer: GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
          // 1) Constructor
          () => PanGestureRecognizer()..dragStartBehavior = DragStartBehavior.down,
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
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(0)), bg);

    // Horizontal guide lines
    final guidePaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;

    final topY = verticalPadding;
    final zeroY = _volumeToPy(0.75);
    final bottomY = verticalPadding + _usableHeight;

    canvas.drawLine(Offset(axisWidth, topY), Offset(size.width, topY), guidePaint);
    canvas.drawLine(Offset(axisWidth, zeroY), Offset(size.width, zeroY), guidePaint);
    canvas.drawLine(Offset(axisWidth, bottomY), Offset(size.width, bottomY), guidePaint);

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

    final clipRect = Rect.fromLTWH(axisWidth, 0, size.width - axisWidth, size.height);

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
    return old.points != points || old.scrollOffsetMs != scrollOffsetMs || old.pixelsPerMs != pixelsPerMs;
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
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
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

  const PrettyGainSlider({
    super.key,
    required this.value,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
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
        // Text("–∞", style: TextStyle(color: Colors.white, fontSize: 12)),
        Text("Gain:", style: TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(width: 6),

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
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: const Color(0xFF4D5566),
                inactiveTrackColor: const Color(0xFF4D5566),
                thumbColor: const Color(0xFFB7BECC),
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
              return db > 0 ? "+${db.toStringAsFixed(1)} dB" : "${db.toStringAsFixed(1)} dB";
            }(),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible, // do NOT wrap, do NOT resize vertically
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

    final r = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(3));
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
