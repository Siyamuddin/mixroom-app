/*






// import 'dart:math';
// import 'dart:math' as math;
// import 'package:flutter/foundation.dart';
// import 'package:flutter/gestures.dart';
// import 'package:flutter/material.dart';
// import 'package:mixroom/models/models.dart';

// class AudioCanvasTimeline extends StatefulWidget {
//   // Data
//   final List<AudioTrack> clips;
//   final int? selectedClipIndex;

//   // Extractors
//   final double Function(AudioTrack clip) getStartMs; // offset on timeline (ms)
//   final double Function(AudioTrack clip) getDurationMs;
//   final double Function(AudioTrack clip) getTrimStartMs;
//   final double Function(AudioTrack clip) getTrimEndMs;
//   final List<double>? Function(AudioTrack clip)? getPeaks;

//   // NEW: rows (1-based)
//   final int Function(AudioTrack clip) getRowIndex;
//   final int numRows;

//   // Selection
//   final void Function(int clipIndex)? onSelectClip;
//   final VoidCallback? onDeselectAll;

//   // Movement (drag)
//   final void Function(int clipIndex, double newStartMs, int newRowIndex)? onMoveClipPreview; // optional
//   final void Function(int clipIndex, double newStartMs, int newRowIndex)? onMoveClipCommit;

//   // Trimming
//   final void Function(int clipIndex, double previewTrimStartMs, double previewTrimEndMs)? onTrimPreview;
//   final void Function(
//     int clipIndex,
//     bool isStartHandle,
//     double finalTrimStartMs,
//     double finalTrimEndMs, {
//     double? newStartMsIfStartTrim,
//   })? onTrimCommit;

//   // Legacy
//   final void Function(int clipIndex, double newTrimStartMs, double newTrimEndMs, {double? newStartMs})? onTrimClip;

//   // Transport / scrub
//   final double playheadMs; // -1 to hide
//   final void Function(double ms)? onScrubRequested;
//   final bool isPlaying; // NEW: optional visual affordances (not strictly used)

//   // Zoom/scroll
//   final double initialPixelsPerSecond;
//   final double minPixelsPerSecond;
//   final double maxPixelsPerSecond;

//   // Ruler
//   final double bpm;
//   final int beatsPerBar;
//   final ValueChanged<double>? onBpmChanged;

//   // UX
//   final bool snapToGrid;
//   final double snapStrength; // 0..1
//   final double fineDragMultiplier; // 0.12 for precise drag

//   // Layout
//   final double height; // viewport height
//   final double clipHeight; // visual height of a clip
//   final double verticalPadding; // top/bottom padding

//   // NEW: row/headers UI
//   final double rowGap; // gap between rows
//   final double headerWidth; // left sticky header column width
//   final int selectedRowIndex; // always-selected row (1-based)
//   // final Map<int, bool> rowMuted; // row -> muted?
//   final List<bool> rowMuted;
//   final List<bool> rowExpanded;
//   final int? recordRowIndex; // which row armed (1-based) or null
//   // final Map<int, bool>? rowExpanded; // optional
//   final void Function(int row)? onSelectRow;
//   final void Function(int row)? onToggleMute;
//   final void Function(int row)? onToggleRecord;
//   final void Function(int row)? onToggleExpanded;

//   const AudioCanvasTimeline({
//     super.key,
//     required this.clips,
//     this.selectedClipIndex,
//     required this.getStartMs,
//     required this.getDurationMs,
//     required this.getTrimStartMs,
//     required this.getTrimEndMs,
//     this.getPeaks,
//     // NEW:
//     required this.getRowIndex,
//     required this.numRows,
//     this.onSelectClip,
//     this.onMoveClipPreview,
//     this.onMoveClipCommit,
//     this.onDeselectAll,
//     this.onTrimPreview,
//     this.onTrimCommit,
//     this.onTrimClip,
//     this.playheadMs = -1,
//     this.onScrubRequested,
//     this.isPlaying = false,
//     this.initialPixelsPerSecond = 180,
//     this.minPixelsPerSecond = 10,
//     this.maxPixelsPerSecond = 900,
//     required this.bpm,
//     this.beatsPerBar = 4,
//     this.onBpmChanged,
//     this.snapToGrid = false,
//     this.snapStrength = 0.75,
//     this.fineDragMultiplier = 0.12,
//     this.height = 520,
//     this.clipHeight = 88,
//     this.verticalPadding = 80,

//     // NEW:
//     this.rowGap = 8,
//     this.headerWidth = 132,
//     required this.selectedRowIndex,
//     required this.rowMuted,
//     this.recordRowIndex,
//     required this.rowExpanded,
//     this.onSelectRow,
//     this.onToggleMute,
//     this.onToggleRecord,
//     this.onToggleExpanded,
//   });

//   @override
//   State<AudioCanvasTimeline> createState() => _AudioCanvasTimelineState();
// }

// class _AudioCanvasTimelineState extends State<AudioCanvasTimeline> with TickerProviderStateMixin {
//   // Zoom
//   late double _pps;
//   late final AnimationController _zoomCtrl;
//   double _animFromPps = 0, _animToPps = 0;

//   // Scroll
//   final ScrollController _rulerScroll = ScrollController();
//   final ScrollController _hScroll = ScrollController();
//   final ScrollController _vScroll = ScrollController();
//   bool _isClipDragActive = false;

//   // Viewport size cache
//   double _viewportW = 0, _viewportH = 0;

//   // Drag state
//   bool _fineDrag = false;
//   int? _dragCi;
//   double _dragOriginStartMs = 0;
//   int _dragOriginRow = 1; // NEW: row at drag start
//   double _dragDxPx = 0;
//   double _dragDyPx = 0;
//   double? _pinchStartDistance;

//   // Trim PREVIEW
//   final Map<int, double> _trimPreviewStart = {};
//   final Map<int, double> _trimPreviewEnd = {};

//   // Constants
//   static const double _rightPadMs = 1500.0;
//   static const double _bottomPad = 200.0;

//   double? _pendingPlayheadMs;

//   // Loop
//   bool _loopEnabled = false;
//   double _loopStartMs = 0.0;
//   double _loopEndMs = 0.0;

//   // Ruler gutter (kept)
//   static const double kLoopBtnW = 44;
//   static const double kLoopBtnH = 24;
//   static const double kLoopInset = 8;
//   late final double _rulerLeftInset = kLoopInset + kLoopBtnW + 6;

//   int _pointerCount = 0;

//   // Persist left-edge after start trim until model accepts
//   final Map<int, double> _pendingLeftShiftMs = {};
//   final Map<int, double> _lastModelStartMs = {};

//   // Helpers: rows
//   double get _rowHeight => widget.clipHeight + widget.rowGap;
//   double _rowToY(int row1Based) => widget.verticalPadding + (row1Based - 1) * _rowHeight;
//   int _yToNearestRow1Based(double y) {
//     final clamped = y.clamp(widget.verticalPadding, widget.verticalPadding + (widget.numRows - 1) * _rowHeight);
//     final idx = ((clamped - widget.verticalPadding) / _rowHeight).round() + 1;
//     return idx.clamp(1, widget.numRows);
//   }

//   @override
//   void initState() {
//     super.initState();
//     _pps = widget.initialPixelsPerSecond;
//     _zoomCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120))
//       ..addListener(() {
//         final t = Curves.easeOutCubic.transform(_zoomCtrl.value);
//         setState(() => _pps = _animFromPps + (_animToPps - _animFromPps) * t);
//       });

//     // Sync ruler with horizontal canvas scroll
//     _hScroll.addListener(() {
//       if (_rulerScroll.hasClients) {
//         _rulerScroll.jumpTo(_hScroll.offset.clamp(
//           _rulerScroll.position.minScrollExtent,
//           _rulerScroll.position.maxScrollExtent,
//         ));
//       }
//     });
//   }

//   @override
//   void dispose() {
//     _zoomCtrl.dispose();
//     _hScroll.dispose();
//     _rulerScroll.dispose();
//     _vScroll.dispose();
//     super.dispose();
//   }

//   @override
//   void didUpdateWidget(covariant AudioCanvasTimeline oldWidget) {
//     super.didUpdateWidget(oldWidget);

//     if (oldWidget.playheadMs != widget.playheadMs) _pendingPlayheadMs = null;

//     for (int ci = 0; ci < widget.clips.length; ci++) {
//       final now = widget.getStartMs(widget.clips[ci]);
//       final last = _lastModelStartMs[ci];
//       if (last != null && now != last) {
//         _pendingLeftShiftMs.remove(ci);
//       }
//       _lastModelStartMs[ci] = now;
//     }

//     if (!identical(widget.clips, oldWidget.clips) || widget.clips.length != oldWidget.clips.length) {
//       _isClipDragActive = false;
//       _dragCi = null;
//       _dragDxPx = 0;
//       _dragDyPx = 0;
//       _pendingLeftShiftMs.clear();
//     }
//   }

//   // Time/px
//   double _msToPx(double ms) => ms / 1000.0 * _pps;
//   double _pxToMs(double px) => px / _pps * 1000.0;

//   double _projectEndMs() {
//     double end = 0;
//     for (var c in widget.clips) {
//       final s = widget.getStartMs(c);
//       final v = (widget.getTrimEndMs(c) - widget.getTrimStartMs(c)).clamp(1.0, widget.getDurationMs(c));
//       end = max(end, s + v);
//     }
//     return end + _rightPadMs;
//   }

//   double _contentHeight() {
//     final rowsH = widget.verticalPadding * 2 + widget.numRows * _rowHeight;
//     return max(_viewportH, rowsH + _bottomPad);
//   }

//   // Grid/snap
//   double _msPerBeat(double bpm) => 60000.0 / (bpm <= 0 ? 120.0 : bpm);
//   double _snapMs(double rawMs) {
//     if (!widget.snapToGrid || widget.bpm <= 0) return rawMs;
//     final beat = _msPerBeat(widget.bpm);
//     final snapped = (rawMs / beat).round() * beat;
//     return rawMs * (1.0 - widget.snapStrength) + snapped * widget.snapStrength;
//   }

//   // Zoom with anchor
//   void _zoomAroundContentX(double focalContentX, double factor) {
//     final oldPps = _pps;
//     final target = (oldPps * factor).clamp(widget.minPixelsPerSecond, widget.maxPixelsPerSecond);
//     final viewLeftPx = _hScroll.hasClients ? _hScroll.offset : 0.0;
//     final focalViewportX = focalContentX - viewLeftPx;
//     final worldMs = _pxToMs(viewLeftPx + focalViewportX);

//     setState(() => _pps = target);
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (!mounted || !_hScroll.hasClients) return;
//       final newLeftPx = _msToPx(worldMs) - focalViewportX;
//       final contentW = max(_viewportW, _msToPx(_projectEndMs()));
//       final maxScroll = max(0.0, contentW - _viewportW);
//       _hScroll.jumpTo(newLeftPx.clamp(0.0, maxScroll));
//     });
//   }

//   // Overlap helper (same row)
//   bool _wouldOverlapSameRow(int movingIndex, int targetRow, double newLeftMs, double newRightMs) {
//     for (int i = 0; i < widget.clips.length; i++) {
//       if (i == movingIndex) continue;
//       final c = widget.clips[i];
//       if (widget.getRowIndex(c) != targetRow) continue;
//       final s = widget.getStartMs(c);
//       final v = (widget.getTrimEndMs(c) - widget.getTrimStartMs(c)).clamp(1.0, widget.getDurationMs(c));
//       final e = s + v;
//       if (newLeftMs < e && newRightMs > s) return true;
//     }
//     return false;
//   }

//   double _msToUiPx(double ms) => _rulerLeftInset + widget.headerWidth + _msToPx(ms);
//   double _uiLocalPxToMs(double localXInContent) =>
//       _pxToMs((_hScroll.hasClients ? _hScroll.offset : 0.0) + localXInContent);

//   @override
//   Widget build(BuildContext context) {
//     final rulerH = 34.0;
//     final playheadToUse = _pendingPlayheadMs ?? widget.playheadMs;

//     const Color kRulerBg = Color(0xFF273A59);

//     return LayoutBuilder(builder: (context, c) {
//       _viewportW = c.maxWidth;
//       _viewportH = widget.height;
//       final contentW = max(_viewportW, _msToPx(_projectEndMs()));
//       final contentH = _contentHeight();

//       return Listener(
//         onPointerDown: (_) => setState(() => _pointerCount++),
//         onPointerUp: (_) => setState(() => _pointerCount = (_pointerCount - 1).clamp(0, 10)),
//         onPointerCancel: (_) => setState(() => _pointerCount = (_pointerCount - 1).clamp(0, 10)),
//         child: SizedBox(
//           height: widget.height,
//           child: Column(
//             children: [
//               // RULER
//               Container(
//                 height: rulerH,
//                 color: kRulerBg,
//                 child: Stack(
//                   children: [
//                     Positioned.fill(
//                       child: Row(
//                         children: [
//                           SizedBox(width: _rulerLeftInset + widget.headerWidth), // gutter + headers
//                           Expanded(
//                             child: SingleChildScrollView(
//                               controller: _rulerScroll,
//                               scrollDirection: Axis.horizontal,
//                               physics: const NeverScrollableScrollPhysics(),
//                               child: SizedBox(
//                                 width: _msToPx(_projectEndMs()),
//                                 height: rulerH,
//                                 child: GestureDetector(
//                                   behavior: HitTestBehavior.opaque,
//                                   onDoubleTapDown: null,
//                                   onTapDown: (d) {
//                                     final ms = _uiLocalPxToMs(d.localPosition.dx);
//                                     setState(() => _pendingPlayheadMs = ms.clamp(0.0, _projectEndMs()));
//                                     widget.onScrubRequested?.call(ms);
//                                   },
//                                   onPanUpdate: (d) {
//                                     final ms = _uiLocalPxToMs(d.localPosition.dx);
//                                     setState(() => _pendingPlayheadMs = ms.clamp(0.0, _projectEndMs()));
//                                     widget.onScrubRequested?.call(ms);
//                                   },
//                                   child: CustomPaint(
//                                     size: Size(_msToPx(_projectEndMs()), rulerH),
//                                     painter: _BarsBeatsPainter(
//                                       pps: _pps,
//                                       bpm: widget.bpm,
//                                       beatsPerBar: widget.beatsPerBar,
//                                       tickColor: Colors.white.withOpacity(0.45),
//                                       textColor: Colors.white,
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                     // Loop pill (fixed)
//                     Positioned(
//                       left: kLoopInset,
//                       top: (rulerH - kLoopBtnH) / 2,
//                       width: kLoopBtnW,
//                       height: kLoopBtnH,
//                       child: _LoopPillButton(
//                         enabled: _loopEnabled,
//                         onToggle: () {
//                           setState(() {
//                             _loopEnabled = !_loopEnabled;
//                             if (_loopEnabled) {
//                               final startMs = (_pendingPlayheadMs ?? widget.playheadMs).clamp(0.0, _projectEndMs());
//                               final msPerBeat = 60000.0 / (widget.bpm <= 0 ? 120.0 : widget.bpm);
//                               final fourBarsMs = msPerBeat * widget.beatsPerBar * 4;
//                               _loopStartMs = startMs;
//                               _loopEndMs = (_loopStartMs + fourBarsMs).clamp(_loopStartMs + 1.0, _projectEndMs());
//                             }
//                           });
//                         },
//                       ),
//                     ),
//                   ],
//                 ),
//               ),

//               // BODY (headers + canvas)
//               Expanded(
//                 child: Row(
//                   children: [
//                     // LEFT: sticky headers (square)
//                     Container(
//                       width: widget.headerWidth,
//                       color: Theme.of(context).colorScheme.surface, // sticks to far left
//                       child: SingleChildScrollView(
//                         controller: _vScroll,
//                         scrollDirection: Axis.vertical,
//                         physics:
//                             _isClipDragActive ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
//                         child: SizedBox(
//                           height: contentH,
//                           child: Column(
//                             children: [
//                               SizedBox(height: widget.verticalPadding - widget.rowGap / 2),
//                               for (int row = 1; row <= widget.numRows; row++)
//                                 _TrackHeader(
//                                   row: row,
//                                   title: 'Track $row',
//                                   height: widget.clipHeight,
//                                   isSelected: widget.selectedRowIndex == row,
//                                   // isMuted: widget.rowMuted[row] == true,
//                                   isMuted: (row - 1 < widget.rowMuted.length) && widget.rowMuted[row - 1],
//                                   isArmed: widget.recordRowIndex == row,
//                                   onTap: () => widget.onSelectRow?.call(row),
//                                   onToggleMute: () => widget.onToggleMute?.call(row),
//                                   onToggleRecord: () => widget.onToggleRecord?.call(row),
//                                 ),
//                               const SizedBox(height: _bottomPad),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),

//                     // RIGHT: scrollable canvas (V + H)
//                     Expanded(
//                       child: SingleChildScrollView(
//                         controller: _vScroll,
//                         scrollDirection: Axis.vertical,
//                         physics:
//                             _isClipDragActive ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
//                         child: SizedBox(
//                           height: contentH,
//                           child: Row(
//                             children: [
//                               SizedBox(width: _rulerLeftInset), // keep ruler's left gutter aligned
//                               Expanded(
//                                 child: SingleChildScrollView(
//                                   controller: _hScroll,
//                                   scrollDirection: Axis.horizontal,
//                                   physics: _isClipDragActive
//                                       ? const NeverScrollableScrollPhysics()
//                                       : const ClampingScrollPhysics(),
//                                   child: GestureDetector(
//                                     behavior: HitTestBehavior.opaque,
//                                     // pinch zoom
//                                     onScaleStart: (d) {
//                                       if (_isClipDragActive) return;
//                                       if (_pointerCount < 2) return;
//                                       _pinchStartDistance = 1.0;
//                                     },
//                                     onScaleUpdate: (d) {
//                                       if (_isClipDragActive) return;
//                                       if (_pointerCount < 2) return;
//                                       if (d.scale == 1.0) return;
//                                       final relative = (_pinchStartDistance ?? 1.0) == 0
//                                           ? 1.0
//                                           : d.scale / (_pinchStartDistance ?? 1.0);
//                                       _pinchStartDistance = d.scale;

//                                       final viewLeft = _hScroll.hasClients ? _hScroll.offset : 0.0;
//                                       final focalContentX = viewLeft + d.focalPoint.dx;
//                                       _zoomAroundContentX(focalContentX, relative);
//                                     },
//                                     onScaleEnd: (_) => _pinchStartDistance = null,

//                                     child: SizedBox(
//                                       width: _msToPx(_projectEndMs()),
//                                       child: Stack(
//                                         children: [
//                                           // Grid (bars only)
//                                           Positioned.fill(
//                                             child: CustomPaint(
//                                               painter: _BeatGridPainter(
//                                                 pps: _pps,
//                                                 bpm: widget.bpm,
//                                                 beatsPerBar: widget.beatsPerBar,
//                                                 color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
//                                               ),
//                                             ),
//                                           ),

//                                           // Row separators (subtle)
//                                           Positioned.fill(
//                                             child: IgnorePointer(
//                                               child: CustomPaint(
//                                                 painter: _RowLinesPainter(
//                                                   rowCount: widget.numRows,
//                                                   rowHeight: _rowHeight,
//                                                   topOffset: widget.verticalPadding - widget.rowGap / 2,
//                                                   color: Theme.of(context).dividerColor.withOpacity(0.25),
//                                                 ),
//                                               ),
//                                             ),
//                                           ),

//                                           // Clips
//                                           for (int ci = 0; ci < widget.clips.length; ci++)
//                                             _buildClip(ci, Theme.of(context).colorScheme),

//                                           // Overlap overlays (legal; visual only)
//                                           ..._buildOverlapOverlays(),

//                                           // Playhead
//                                           if (playheadToUse >= 0)
//                                             Positioned(
//                                               left: _msToUiPx(playheadToUse),
//                                               top: 0,
//                                               width: 2,
//                                               height: _contentHeight(),
//                                               child: Container(color: Theme.of(context).colorScheme.secondary),
//                                             ),
//                                         ],
//                                       ),
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       );
//     });
//   }

//   Widget _buildClip(int ci, ColorScheme cs) {
//     final clip = widget.clips[ci];

//     // Model values
//     final modelStartMs = widget.getStartMs(clip);
//     final totalDurMs = widget.getDurationMs(clip);
//     final baseTrimS = widget.getTrimStartMs(clip);
//     final baseTrimE = widget.getTrimEndMs(clip);
//     final baseRow = widget.getRowIndex(clip).clamp(1, widget.numRows);

//     // Preview trims
//     final trimStartMs = _trimPreviewStart[ci] ?? baseTrimS;
//     final trimEndMs = _trimPreviewEnd[ci] ?? baseTrimE;
//     final visibleDurMs = (trimEndMs - trimStartMs).clamp(1.0, totalDurMs);

//     // Persisted left-edge shift after start-trim until parent updates offset
//     final leftShiftMs = _pendingLeftShiftMs[ci] ?? (trimStartMs - baseTrimS);

//     // Drag state
//     final isDragging = _dragCi == ci;
//     final dxMs = _pxToMs(_dragDxPx * (_fineDrag ? widget.fineDragMultiplier : 1.0));
//     final previewStartMs = isDragging ? (modelStartMs + dxMs).clamp(0.0, double.infinity) : modelStartMs;

//     // NEW: vertical snapping to rows
//     final startRowAtDrag = isDragging ? _dragOriginRow : baseRow;
//     final rawY = isDragging ? (_rowToY(_dragOriginRow) + _dragDyPx) : _rowToY(baseRow);
//     final previewRow = isDragging ? _yToNearestRow1Based(rawY) : baseRow;
//     final topY = _rowToY(previewRow);

//     // Visible edges on timeline (start-trim shifts left edge)
//     final visibleLeftStartMs = (previewStartMs + leftShiftMs).clamp(0.0, double.infinity);
//     final visibleEndMs = visibleLeftStartMs + visibleDurMs;

//     // Selection & color (kept simple, no "invalid" red since overlaps are legal)
//     final isSelected = (widget.selectedClipIndex == ci);
//     final color = cs.primary.withOpacity(0.12);

//     // Waveform
//     final peaks = widget.getPeaks?.call(clip) ?? const <double>[];
//     final startFrac = (trimStartMs / totalDurMs).clamp(0.0, 1.0);
//     final endFrac = (trimEndMs / totalDurMs).clamp(0.0, 1.0);

//     return Positioned(
//       left: _msToUiPx(visibleLeftStartMs),
//       top: topY,
//       width: max(4.0, _msToPx(visibleDurMs)),
//       height: widget.clipHeight,
//       child: _FreeClip(
//         cs: cs,
//         isSelected: isSelected,
//         color: color,
//         invalidOutline: false,
//         peaks: peaks,
//         trimStartMs: trimStartMs,
//         trimEndMs: trimEndMs,
//         totalDurationMs: totalDurMs,

//         onTapSelect: () => widget.onSelectClip?.call(ci),

//         // DRAG
//         onBeginDrag: (_) {
//           setState(() {
//             _dragCi = ci;
//             _dragDxPx = 0;
//             _dragDyPx = 0;
//             _fineDrag = false;
//             _dragOriginStartMs = modelStartMs;
//             _dragOriginRow = baseRow;
//             _isClipDragActive = true;
//           });
//         },
//         onDragUpdate: (deltaDx, deltaDy) {
//           setState(() {
//             _dragDxPx += deltaDx;
//             _dragDyPx += deltaDy;
//           });

//           // H-autoscroll
//           final msDelta = (_dragDxPx / _pps) * 1000.0 * (_fineDrag ? widget.fineDragMultiplier : 1.0);
//           final previewLeft = max(0.0, (_dragOriginStartMs + msDelta) + leftShiftMs);
//           final clipX = _msToPx(previewLeft);
//           final viewLeft = _hScroll.offset;
//           final viewRight = viewLeft + (_viewportW - (_rulerLeftInset + widget.headerWidth));
//           if (clipX > viewRight - 60) {
//             _hScroll.jumpTo(min(_hScroll.position.maxScrollExtent,
//                 clipX - ((_viewportW - (_rulerLeftInset + widget.headerWidth)) - 60)));
//           } else if (clipX < viewLeft + 60) {
//             _hScroll.jumpTo(max(0.0, clipX - 60));
//           }

//           // V-autoscroll for rows
//           final top = _rowToY(_yToNearestRow1Based(_rowToY(_dragOriginRow) + _dragDyPx));
//           final viewTop = _vScroll.offset;
//           final viewBot = viewTop + (_viewportH - 24);
//           if (top < viewTop + 40) {
//             _vScroll.jumpTo(max(0.0, top - 40));
//           } else if (top + widget.clipHeight > viewBot - 40) {
//             _vScroll.jumpTo(min(_vScroll.position.maxScrollExtent, top + widget.clipHeight - (_viewportH - 24) + 40));
//           }
//         },
//         onDragEnd: () {
//           final msDelta = (_dragDxPx / _pps) * 1000.0 * (_fineDrag ? widget.fineDragMultiplier : 1.0);
//           final targetStartMs = (modelStartMs + msDelta).clamp(0.0, double.infinity);
//           final targetRow = _yToNearestRow1Based(_rowToY(_dragOriginRow) + _dragDyPx);

//           // (Overlaps allowed) → just commit
//           widget.onMoveClipCommit?.call(ci, _snapMs(targetStartMs), targetRow);

//           setState(() {
//             _dragCi = null;
//             _dragDxPx = 0;
//             _dragDyPx = 0;
//             _isClipDragActive = false;
//           });
//         },
//         onLongPressToggleFine: () => setState(() => _fineDrag = true),

//         // TRIM
//         onBeginTrim: (isStart) {
//           setState(() {
//             _isClipDragActive = true;
//             _trimPreviewStart[ci] = trimStartMs;
//             _trimPreviewEnd[ci] = trimEndMs;
//           });
//         },
//         onUpdateTrim: (isStart, newS, newE) {
//           final minDur = 10.0;
//           double s = newS.clamp(0.0, totalDurMs - minDur);
//           double e = newE.clamp(s + minDur, totalDurMs);
//           setState(() {
//             _trimPreviewStart[ci] = s;
//             _trimPreviewEnd[ci] = e;
//           });
//           widget.onTrimPreview?.call(ci, s, e);
//         },
//         onEndTrim: (isStart) {
//           final s = _trimPreviewStart[ci] ?? baseTrimS;
//           final e = _trimPreviewEnd[ci] ?? baseTrimE;

//           if (isStart) {
//             final delta = s - baseTrimS; // left edge moved
//             final proposedNewStart = max(0.0, modelStartMs + delta);

//             setState(() => _pendingLeftShiftMs[ci] = delta);

//             widget.onTrimCommit?.call(ci, true, s, e, newStartMsIfStartTrim: proposedNewStart);
//             widget.onTrimClip?.call(ci, s, e, newStartMs: proposedNewStart);
//           } else {
//             widget.onTrimCommit?.call(ci, false, s, e);
//             widget.onTrimClip?.call(ci, s, e);
//           }

//           setState(() {
//             _isClipDragActive = false;
//             _trimPreviewStart.remove(ci);
//             _trimPreviewEnd.remove(ci);
//           });
//         },
//       ),
//     );
//   }

//   // Compute all overlap rectangles within the same row and paint a translucent red band
//   List<Widget> _buildOverlapOverlays() {
//     final List<Widget> overlays = [];
//     final clips = widget.clips;

//     // Build per-row lists of (leftMs, rightMs, row)
//     final perRow = <int, List<_Seg>>{};
//     for (int i = 0; i < clips.length; i++) {
//       final c = clips[i];
//       final row = widget.getRowIndex(c).clamp(1, widget.numRows);
//       final s = widget.getStartMs(c);
//       final v = (widget.getTrimEndMs(c) - widget.getTrimStartMs(c)).clamp(1.0, widget.getDurationMs(c));
//       final e = s + v;
//       perRow.putIfAbsent(row, () => []).add(_Seg(i, s, e));
//     }

//     final paint = Colors.redAccent.withOpacity(0.18);

//     perRow.forEach((row, segs) {
//       if (segs.length < 2) return;
//       // Sweep line over sorted edges to find >1 coverage
//       final events = <_Edge>[];
//       for (final s in segs) {
//         events.add(_Edge(s.l, 1));
//         events.add(_Edge(s.r, -1));
//       }
//       events.sort((a, b) => a.x.compareTo(b.x));

//       int cover = 0;
//       double? start;
//       for (final e in events) {
//         final prev = cover;
//         cover += e.d;
//         if (prev < 2 && cover >= 2) {
//           start = e.x;
//         } else if (prev >= 2 && cover < 2) {
//           final end = e.x;
//           if (start != null && end > start) {
//             final leftPx = _msToUiPx(start);
//             final wPx = _msToPx(end - start);
//             overlays.add(Positioned(
//               left: leftPx,
//               top: _rowToY(row),
//               width: max(1.0, wPx),
//               height: widget.clipHeight,
//               child: IgnorePointer(child: Container(color: paint)),
//             ));
//           }
//           start = null;
//         }
//       }
//     });

//     return overlays;
//   }
// }

// class _Seg {
//   final int idx;
//   final double l;
//   final double r;
//   _Seg(this.idx, this.l, this.r);
// }

// class _Edge {
//   final double x;
//   final int d;
//   _Edge(this.x, this.d);
// }

// // ===== Track Header (square, sticky) =====
// class _TrackHeader extends StatelessWidget {
//   final int row;
//   final String title;
//   final double height;
//   final bool isSelected;
//   final bool isMuted;
//   final bool isArmed;
//   final VoidCallback onTap;
//   final VoidCallback onToggleMute;
//   final VoidCallback onToggleRecord;

//   const _TrackHeader({
//     required this.row,
//     required this.title,
//     required this.height,
//     required this.isSelected,
//     required this.isMuted,
//     required this.isArmed,
//     required this.onTap,
//     required this.onToggleMute,
//     required this.onToggleRecord,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 8.0),
//       child: Material(
//         color: isSelected ? cs.secondary.withOpacity(0.18) : cs.surfaceVariant.withOpacity(0.35),
//         borderRadius: BorderRadius.zero, // SQUARE
//         child: InkWell(
//           onTap: onTap,
//           child: SizedBox(
//             height: height,
//             width: double.infinity,
//             child: Stack(
//               children: [
//                 Positioned.fill(
//                   child: Padding(
//                     padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
//                     child: Align(
//                       alignment: Alignment.centerLeft,
//                       child: Text(title,
//                           style: TextStyle(
//                             color: Colors.white.withOpacity(0.95),
//                             fontWeight: FontWeight.w600,
//                           )),
//                     ),
//                   ),
//                 ),
//                 // Mute (top-right)
//                 Positioned(
//                   right: 8,
//                   top: 6,
//                   child: _HeaderSquareButton(
//                     label: 'M',
//                     active: isMuted,
//                     onTap: onToggleMute,
//                   ),
//                 ),
//                 // Record (bottom-right)
//                 Positioned(
//                   right: 8,
//                   bottom: 6,
//                   child: _HeaderSquareButton(
//                     label: '●',
//                     active: isArmed,
//                     onTap: onToggleRecord,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _HeaderSquareButton extends StatelessWidget {
//   final String label;
//   final bool active;
//   final VoidCallback onTap;
//   const _HeaderSquareButton({required this.label, required this.active, required this.onTap});

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     return Material(
//       color: active ? cs.error.withOpacity(0.85) : Colors.white.withOpacity(0.15),
//       borderRadius: BorderRadius.zero, // SQUARE
//       child: InkWell(
//         onTap: onTap,
//         child: SizedBox(
//           width: 28,
//           height: 22,
//           child: Center(
//             child: Text(
//               label,
//               style: TextStyle(
//                 fontWeight: FontWeight.w800,
//                 color: active ? Colors.white : Colors.white.withOpacity(0.95),
//                 fontSize: 12,
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// // ===== Row lines painter (subtle separators) =====
// class _RowLinesPainter extends CustomPainter {
//   final int rowCount;
//   final double rowHeight;
//   final double topOffset;
//   final Color color;
//   _RowLinesPainter({required this.rowCount, required this.rowHeight, required this.topOffset, required this.color});

//   @override
//   void paint(Canvas canvas, Size size) {
//     final p = Paint()
//       ..color = color
//       ..strokeWidth = 1.0;
//     for (int r = 0; r < rowCount; r++) {
//       final y = topOffset + r * rowHeight + rowHeight; // bottom line of each row block
//       canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
//     }
//   }

//   @override
//   bool shouldRepaint(covariant _RowLinesPainter old) =>
//       old.rowCount != rowCount || old.rowHeight != rowHeight || old.topOffset != topOffset || old.color != color;
// }

// /// ===== Free clip (draggable in X/Y) =====
// class _FreeClip extends StatefulWidget {
//   final ColorScheme cs;
//   final bool isSelected;
//   final Color color;
//   final bool invalidOutline;
//   final List<double> peaks; // normalized [-1..1]
//   final double trimStartMs;
//   final double trimEndMs;
//   final double totalDurationMs;

//   final VoidCallback onTapSelect;
//   final void Function(Offset globalPosInClip)? onBeginDrag;
//   final void Function(double dx, double dy)? onDragUpdate;
//   final VoidCallback onDragEnd;
//   final VoidCallback onLongPressToggleFine;

//   // Trim lifecycle (preview inside parent; commit onEndTrim)
//   final void Function(bool isStart) onBeginTrim;
//   final void Function(bool isStart, double newTrimStartMs, double newTrimEndMs) onUpdateTrim;
//   final void Function(bool isStart) onEndTrim;

//   const _FreeClip({
//     required this.cs,
//     required this.isSelected,
//     required this.color,
//     required this.invalidOutline,
//     required this.peaks,
//     required this.trimStartMs,
//     required this.trimEndMs,
//     required this.totalDurationMs,
//     required this.onTapSelect,
//     this.onBeginDrag,
//     this.onDragUpdate,
//     required this.onDragEnd,
//     required this.onLongPressToggleFine,
//     required this.onBeginTrim,
//     required this.onUpdateTrim,
//     required this.onEndTrim,
//   });

//   @override
//   State<_FreeClip> createState() => _FreeClipState();
// }

// class _FreeClipState extends State<_FreeClip> {
//   static const double _handleW = 20.0; // easier to grab
//   static const double _minTrimMs = 10.0; // cannot trim to zero

//   Offset? _lastGlobal;
//   bool _isTrimming = false;
//   bool _lockDrag = false;

//   void _setTrimming(bool v) => setState(() => _isTrimming = v);

//   @override
//   Widget build(BuildContext context) {
//     final peaks = widget.peaks;
//     final trimS = widget.trimStartMs;
//     final trimE = widget.trimEndMs;
//     final totalDurationMs = widget.totalDurationMs;
//     final startFrac = (trimS / totalDurationMs).clamp(0.0, 1.0);
//     final endFrac = (trimE / totalDurationMs).clamp(0.0, 1.0);

//     // DRAG recognizer that wins the arena when needed
//     return RawGestureDetector(
//       gestures: {
//         _AlwaysWinPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<_AlwaysWinPanGestureRecognizer>(
//           () => _AlwaysWinPanGestureRecognizer(),
//           (g) {
//             g
//               ..onDown = (_) {/* reserve if needed */}
//               ..onStart = (d) {
//                 // Auto-select so drag always works, even if user didn't tap first.
//                 _lastGlobal = d.globalPosition;
//                 final parent = context.findAncestorStateOfType<_AudioCanvasTimelineState>();
//                 if (parent?._pointerCount != null && parent!._pointerCount >= 2) return; // let pinch win
//                 // Trigger selection immediately
//                 // (We call the same callback used by tap)
//                 if (mounted) {
//                   // Call the onTapSelect from parent by finding our widget via context
//                   // but we have direct access already:
//                 }
//                 // Since we don't have a direct ref here, just synthesize a tap:
//                 widget.onTapSelect();

//                 widget.onBeginDrag?.call(d.globalPosition);
//                 parent?._isClipDragActive = true;
//               }
//               ..onUpdate = (d) {
//                 final parent = context.findAncestorStateOfType<_AudioCanvasTimelineState>();
//                 if (parent?._pointerCount != null && parent!._pointerCount >= 2) return;

//                 if (_lockDrag || !widget.isSelected || _lastGlobal == null) return;
//                 final dx = d.globalPosition.dx - _lastGlobal!.dx;
//                 final dy = d.globalPosition.dy - _lastGlobal!.dy;
//                 _lastGlobal = d.globalPosition;
//                 widget.onDragUpdate?.call(dx, dy);
//               }
//               ..onEnd = (_) {
//                 if (_lockDrag || !widget.isSelected) return;
//                 widget.onDragEnd();
//                 final parent = context.findAncestorStateOfType<_AudioCanvasTimelineState>();
//                 parent?._isClipDragActive = false;
//               };
//           },
//         ),
//       },
//       behavior: HitTestBehavior.opaque,
//       child: GestureDetector(
//         behavior: HitTestBehavior.opaque,
//         onTap: widget.onTapSelect,
//         onLongPressStart: (_) => widget.onLongPressToggleFine(),
//         child: AnimatedContainer(
//           duration: const Duration(milliseconds: 120),
//           transform: _isTrimming ? (Matrix4.identity()..scale(1.03)) : Matrix4.identity(),
//           curve: Curves.easeOut,
//           decoration: BoxDecoration(
//             color: widget.color.withOpacity(0.18),
//             borderRadius: BorderRadius.circular(12),
//             border: Border.all(
//               color: widget.isSelected ? Colors.white : widget.cs.outlineVariant.withOpacity(0.45),
//               width: widget.isSelected ? 2 : 1,
//             ),
//             boxShadow: widget.isSelected
//                 ? [
//                     BoxShadow(
//                         color: Colors.white.withOpacity(0.2),
//                         blurRadius: 10,
//                         spreadRadius: 2,
//                         offset: const Offset(0, 2)),
//                     BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 4)),
//                   ]
//                 : [],
//           ),
//           clipBehavior: Clip.antiAlias,
//           child: Stack(
//             children: [
//               // waveform (mirrored min/max; zoom-accurate because it uses actual widget width)
//               Positioned.fill(
//                 child: CustomPaint(
//                   isComplex: true,
//                   willChange: true,
//                   painter: _WavePainterDoubleSided(
//                     samples: peaks,
//                     startFrac: startFrac,
//                     endFrac: endFrac,
//                     color: widget.cs.onSurface.withOpacity(0.92),
//                     filled: true, // set false for bar-style
//                   ),
//                 ),
//               ),
//               // trim handles (selected only)
//               if (widget.isSelected)
//                 Positioned.fill(
//                   child: Row(
//                     children: [
//                       // LEFT
//                       _TrimHandle(
//                         side: AxisDirection.left,
//                         width: _handleW,
//                         onStart: () {
//                           widget.onBeginTrim(true);
//                           _setTrimming(true);
//                           _lockDrag = true;
//                         },
//                         onDrag: (dx) {
//                           final w = context.size?.width ?? 1;
//                           final visible = (trimE - trimS).clamp(_minTrimMs, totalDurationMs);
//                           final msPerPx = visible / w;
//                           double newS = (trimS + dx * msPerPx).clamp(0.0, trimE - _minTrimMs);
//                           widget.onUpdateTrim(true, newS, trimE); // preview only
//                         },
//                         onEnd: () {
//                           _setTrimming(false);
//                           _lockDrag = false;
//                           widget.onEndTrim(true); // commit up-chain
//                         },
//                         glowOnTouch: true,
//                       ),
//                       const Expanded(child: SizedBox()),
//                       // RIGHT
//                       _TrimHandle(
//                         side: AxisDirection.right,
//                         width: _handleW,
//                         onStart: () {
//                           widget.onBeginTrim(false);
//                           _setTrimming(true);
//                           _lockDrag = true;
//                         },
//                         onDrag: (dx) {
//                           final w = context.size?.width ?? 1;
//                           final visible = (trimE - trimS).clamp(_minTrimMs, totalDurationMs);
//                           final msPerPx = visible / w;
//                           double newE = (trimE + dx * msPerPx).clamp(trimS + _minTrimMs, totalDurationMs);
//                           widget.onUpdateTrim(false, trimS, newE); // preview only
//                         },
//                         onEnd: () {
//                           _setTrimming(false);
//                           _lockDrag = false;
//                           widget.onEndTrim(false); // commit up-chain
//                         },
//                         glowOnTouch: true,
//                       ),
//                     ],
//                   ),
//                 ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _TrimHandle extends StatefulWidget {
//   final AxisDirection side;
//   final double width;
//   final void Function(double dx) onDrag;
//   final VoidCallback onStart;
//   final VoidCallback onEnd;
//   final bool glowOnTouch;

//   const _TrimHandle({
//     required this.side,
//     required this.width,
//     required this.onDrag,
//     required this.onStart,
//     required this.onEnd,
//     this.glowOnTouch = true,
//   });

//   @override
//   State<_TrimHandle> createState() => _TrimHandleState();
// }

// class _TrimHandleState extends State<_TrimHandle> {
//   Offset? _last;
//   bool _isActive = false;

//   @override
//   Widget build(BuildContext context) {
//     final bool isLeft = widget.side == AxisDirection.left;
//     final accent = Theme.of(context).colorScheme.secondary;

//     return GestureDetector(
//       behavior: HitTestBehavior.translucent,
//       onPanDown: (_) {
//         setState(() => _isActive = true);
//         final parent = context.findAncestorStateOfType<_FreeClipState>();
//         parent?._setTrimming(true);
//         parent?._lockDrag = true;
//       },
//       onPanStart: (d) {
//         _last = d.globalPosition;
//         widget.onStart();
//       },
//       onPanUpdate: (d) {
//         final dx = d.globalPosition.dx - (_last ?? d.globalPosition).dx;
//         _last = d.globalPosition;
//         widget.onDrag(dx);
//       },
//       onPanEnd: (_) {
//         setState(() => _isActive = false);
//         final parent = context.findAncestorStateOfType<_FreeClipState>();
//         parent?._setTrimming(false);
//         parent?._lockDrag = false;
//         widget.onEnd();
//       },
//       child: AnimatedContainer(
//         duration: const Duration(milliseconds: 120),
//         curve: Curves.easeOut,
//         width: widget.width,
//         decoration: BoxDecoration(
//           gradient: LinearGradient(
//             colors: isLeft
//                 ? [
//                     (_isActive && widget.glowOnTouch ? accent.withOpacity(0.45) : Colors.white.withOpacity(0.15)),
//                     Colors.transparent
//                   ]
//                 : [
//                     Colors.transparent,
//                     (_isActive && widget.glowOnTouch ? accent.withOpacity(0.45) : Colors.white.withOpacity(0.15))
//                   ],
//           ),
//           boxShadow: _isActive && widget.glowOnTouch
//               ? [
//                   BoxShadow(
//                       color: accent.withOpacity(0.55),
//                       blurRadius: 10,
//                       spreadRadius: 2,
//                       offset: Offset(isLeft ? 2 : -2, 0))
//                 ]
//               : [
//                   BoxShadow(
//                       color: Colors.white.withOpacity(0.15),
//                       blurRadius: 6,
//                       spreadRadius: 2,
//                       offset: Offset(isLeft ? 2 : -2, 0))
//                 ],
//         ),
//         child: Center(
//           child: AnimatedContainer(
//             duration: const Duration(milliseconds: 120),
//             width: 3,
//             height: double.infinity,
//             decoration: BoxDecoration(
//               color: _isActive ? accent : Colors.white.withOpacity(0.85),
//               borderRadius: BorderRadius.circular(2),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// /// ===== Ruler & Grid Painters =====
// class _BarsBeatsRuler extends StatelessWidget {
//   final double width;
//   final double height;
//   final double pps;
//   final double bpm;
//   final int beatsPerBar;
//   final Color tickColor;
//   final Color textColor;
//   final void Function(double localX)? onTapOrDrag;
//   final void Function(double dx, double scale)? onDoubleTapZoom;
//   const _BarsBeatsRuler(
//       {required this.width,
//       required this.height,
//       required this.pps,
//       required this.bpm,
//       required this.beatsPerBar,
//       required this.tickColor,
//       required this.textColor,
//       this.onTapOrDrag,
//       this.onDoubleTapZoom});
//   @override
//   Widget build(BuildContext context) {
//     // Solid background block to separate from timeline
//     const rulerBg = Color(0xFF273A59);

//     return Container(
//       color: rulerBg,
//       child: GestureDetector(
//         behavior: HitTestBehavior.opaque,
//         // (3) No double-tap action anymore
//         onDoubleTapDown: null,
//         // (4) Tap = instant scrub + instant visual (see section 4)
//         onTapDown: (d) => onTapOrDrag?.call(d.localPosition.dx),
//         onPanUpdate: (d) => onTapOrDrag?.call(d.localPosition.dx),
//         child: CustomPaint(
//           size: Size(width, height),
//           painter: _BarsBeatsPainter(
//             pps: pps,
//             bpm: bpm,
//             beatsPerBar: beatsPerBar,
//             tickColor: Colors.white.withOpacity(0.45), // looks better on dark bg
//             textColor: Colors.white,
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _BarsBeatsPainter extends CustomPainter {
//   final double pps;
//   final double bpm;
//   final int beatsPerBar;
//   final Color tickColor;
//   final Color textColor;
//   _BarsBeatsPainter(
//       {required this.pps,
//       required this.bpm,
//       required this.beatsPerBar,
//       required this.tickColor,
//       required this.textColor});
//   @override
//   void paint(Canvas canvas, Size size) {
//     final p = Paint()
//       ..color = tickColor
//       ..strokeWidth = 1;

//     final tp = TextPainter(textAlign: TextAlign.center, textDirection: TextDirection.ltr);
//     final msPerBeat = 60000.0 / (bpm <= 0 ? 120.0 : bpm);
//     final pxPerBeat = (msPerBeat / 1000.0) * pps;

//     // Subdivision ticks remain only on ruler (not grid)
//     int subdivision = 4;
//     if (pxPerBeat < 30)
//       subdivision = 1;
//     else if (pxPerBeat < 60) subdivision = 2;
//     final pxPerSub = pxPerBeat / subdivision;

//     for (double x = 0; x <= size.width; x += pxPerSub) {
//       final subIndex = (x / pxPerSub).round();
//       final isBeat = subIndex % subdivision == 0;
//       final beatIndex = (x / pxPerBeat).round();
//       final isBar = isBeat && (beatIndex % beatsPerBar == 0);

//       // ticks at the bottom of the ruler strip
//       final h = isBar ? 16.0 : (isBeat ? 12.0 : 6.0);
//       canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), p);

//       if (isBar) {
//         // (1) start bars at 0, not 1; number per bar
//         final barNum = (beatIndex / beatsPerBar).round(); // 0,1,2,...

//         // (2) center the number ON TOP of the bar line
//         final label = TextSpan(text: '$barNum', style: TextStyle(fontSize: 10, color: textColor));
//         tp.text = label;
//         tp.layout(); // width for centering
//         final textX = x - tp.width / 2;
//         final textY = 2.0; // a little padding from the top
//         tp.paint(canvas, Offset(textX, textY));
//       }
//     }
//   }

//   @override
//   bool shouldRepaint(covariant _BarsBeatsPainter old) =>
//       old.pps != pps ||
//       old.bpm != bpm ||
//       old.beatsPerBar != beatsPerBar ||
//       old.tickColor != tickColor ||
//       old.textColor != textColor;
// }

// class _BeatGridPainter extends CustomPainter {
//   final double pps; // pixels per second
//   final double bpm;
//   final int beatsPerBar;
//   final Color color;

//   // Optional styling knobs (tweak if you like)
//   final double barOpacity;
//   final double barStrokeWidth;

//   _BeatGridPainter({
//     required this.pps,
//     required this.bpm,
//     required this.beatsPerBar,
//     required this.color,
//     this.barOpacity = 0.16,
//     this.barStrokeWidth = 1.0,
//   });

//   @override
//   void paint(Canvas canvas, Size size) {
//     if (pps <= 0 || size.width <= 0 || size.height <= 0) return;

//     final msPerBeat = 60000.0 / (bpm <= 0 ? 120.0 : bpm);
//     final pxPerBeat = (msPerBeat / 1000.0) * pps;
//     if (pxPerBeat <= 0) return;

//     final p = Paint()
//       ..color = color.withOpacity(barOpacity)
//       ..strokeWidth = barStrokeWidth;

//     // Draw ONLY bar (measure) lines; skip beat subdivisions.
//     for (double x = 0; x <= size.width; x += pxPerBeat) {
//       final beatIndex = (x / pxPerBeat).round();
//       final isBar = beatIndex % beatsPerBar == 0;
//       if (isBar) {
//         canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
//       }
//     }
//   }

//   @override
//   bool shouldRepaint(covariant _BeatGridPainter old) =>
//       old.pps != pps ||
//       old.bpm != bpm ||
//       old.beatsPerBar != beatsPerBar ||
//       old.color != color ||
//       old.barOpacity != barOpacity ||
//       old.barStrokeWidth != barStrokeWidth;
// }

// /// ===== Waveform Painter (double-sided, DAW-style, trim-aware) =====
// class _WavePainterDoubleSided extends CustomPainter {
//   final List<double> samples; // normalized -1..1 for the FULL file
//   final double startFrac; // 0..1 (trimStart / totalDuration)
//   final double endFrac; // 0..1 (trimEnd   / totalDuration)
//   final Color color;
//   final bool filled; // true = filled "butterfly", false = bars

//   _WavePainterDoubleSided({
//     required this.samples,
//     required this.startFrac,
//     required this.endFrac,
//     required this.color,
//     this.filled = true,
//   });

//   @override
//   void paint(Canvas canvas, Size size) {
//     if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;

//     final mid = size.height / 2.0;
//     final total = samples.length;
//     final iStart = (startFrac.clamp(0.0, 1.0) * (total - 1)).floor();
//     final iEnd = (endFrac.clamp(0.0, 1.0) * (total - 1)).ceil();
//     final window = (iEnd - iStart + 1).clamp(1, total);

//     final widthPx = size.width.ceil();
//     final spp = window / widthPx.clamp(1, window).toDouble(); // samples per pixel in visible window

//     if (filled) {
//       // Build top and bottom paths for a smooth filled mirror shape
//       final top = Path();
//       final bot = Path();

//       for (int x = 0; x < widthPx; x++) {
//         final center = (x + 0.5) * spp + iStart;
//         final halfWin = spp < 1.5 ? 1 : spp.ceil();
//         final j0 = (center - halfWin).floor().clamp(iStart, iEnd);
//         final j1 = (center + halfWin).ceil().clamp(iStart, iEnd);

//         double minAmp = 1.0;
//         double maxAmp = -1.0;
//         for (int j = j0; j <= j1; j++) {
//           final v = samples[j];
//           if (v < minAmp) minAmp = v;
//           if (v > maxAmp) maxAmp = v;
//         }

//         // Double-sided magnitude (Ableton/FL look)
//         final mag = math.max(maxAmp.abs(), minAmp.abs()).clamp(0.0, 1.0);
//         final yTop = mid - mag * mid;
//         final yBot = mid + mag * mid;

//         final dx = x + 0.5;
//         if (x == 0) {
//           top.moveTo(dx, yTop);
//           bot.moveTo(dx, yBot);
//         } else {
//           top.lineTo(dx, yTop);
//           bot.lineTo(dx, yBot);
//         }
//       }

//       // Close into a single butterfly path: top left→right, bottom right→left
//       final path = Path.from(top)
//         ..lineTo(widthPx.toDouble(), mid)
//         ..addPath(bot, Offset.zero)
//         ..lineTo(0, mid)
//         ..close();

//       final fill = Paint()
//         ..style = PaintingStyle.fill
//         ..shader = LinearGradient(
//           begin: Alignment.topCenter,
//           end: Alignment.bottomCenter,
//           colors: [color.withOpacity(0.35), color.withOpacity(0.10)],
//         ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

//       final edge = Paint()
//         ..color = color.withOpacity(0.85)
//         ..style = PaintingStyle.stroke
//         ..strokeWidth = 1.0;

//       canvas.drawPath(path, fill);
//       canvas.drawPath(top, edge);
//       canvas.drawPath(bot, edge);
//     } else {
//       // Lightweight bar style (per-pixel mirrored sticks)
//       final stroke = Paint()
//         ..color = color.withOpacity(0.95)
//         ..style = PaintingStyle.stroke
//         ..strokeWidth = 1.0
//         ..isAntiAlias = false;

//       for (int x = 0; x < widthPx; x++) {
//         final center = (x + 0.5) * spp + iStart;
//         final halfWin = spp < 1.5 ? 1 : spp.ceil();
//         final j0 = (center - halfWin).floor().clamp(iStart, iEnd);
//         final j1 = (center + halfWin).ceil().clamp(iStart, iEnd);

//         double minAmp = 1.0, maxAmp = -1.0;
//         for (int j = j0; j <= j1; j++) {
//           final v = samples[j];
//           if (v < minAmp) minAmp = v;
//           if (v > maxAmp) maxAmp = v;
//         }

//         final mag = math.max(maxAmp.abs(), minAmp.abs()).clamp(0.0, 1.0);
//         final yTop = mid - mag * mid;
//         final yBot = mid + mag * mid;

//         final dx = x + 0.5;
//         canvas.drawLine(Offset(dx, mid), Offset(dx, yTop), stroke);
//         canvas.drawLine(Offset(dx, mid), Offset(dx, yBot), stroke);
//       }
//     }
//   }

//   @override
//   bool shouldRepaint(covariant _WavePainterDoubleSided old) =>
//       !identical(old.samples, samples) ||
//       old.startFrac != startFrac ||
//       old.endFrac != endFrac ||
//       old.color != color ||
//       old.filled != filled;
// }

// class _LoopPillButton extends StatelessWidget {
//   final bool enabled;
//   final VoidCallback onToggle;
//   const _LoopPillButton({required this.enabled, required this.onToggle});

//   @override
//   Widget build(BuildContext context) {
//     return Material(
//       color: Colors.white.withOpacity(enabled ? 0.22 : 0.12),
//       borderRadius: BorderRadius.circular(999),
//       elevation: 2,
//       shadowColor: Colors.black.withOpacity(0.35),
//       child: InkWell(
//         onTap: onToggle,
//         borderRadius: BorderRadius.circular(999),
//         child: Center(
//           child: Icon(
//             enabled ? Icons.repeat_on : Icons.repeat,
//             size: 16,
//             color: Colors.white,
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _AlwaysWinPanGestureRecognizer extends PanGestureRecognizer {
//   @override
//   void rejectGesture(int pointer) {
//     acceptGesture(pointer);
//   }
// }

/*

// AudioCanvasTimeline — freeform, row-less audio timeline (BandLab-style)
// Fully audio-only. Clips can be placed at any vertical position; JUCE cares
// only about time (start/duration). This widget provides:
// - Bars/Beats ruler (BPM-aware) with buttery zoom/pan
// - Freeform clip dragging in X (time) and Y (visual lane), with snapping
// - Long-press fine-drag (reduced sensitivity) for micro placement
// - Hovering/floating visual while dragging; other clips remain immutable
// - Overlap detection: on drop, do NOT commit when overlapping. Show soft red
//   invalid state; keep clip selected and floating so user can resolve.
// - Trimming: PREVIEW during drag, COMMIT on release (prevents teleport).
//   When START trim changes, we also propose newStartMs for offset shift.
// - Selection: tap a clip => onSelectClip(index).
// - High-detail waveform rendering (mirrored min/max, zoom-accurate)
// - BandLab-inspired colors and modern shadows

import 'dart:math';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mixroom/models/models.dart';

class AudioCanvasTimeline extends StatefulWidget {
  // Data (flat list of clips — row-less)
  final List<AudioTrack> clips;
  final int? selectedClipIndex;

  // Extractors
  final double Function(AudioTrack clip) getStartMs; // clip offset on timeline (ms)
  final double Function(AudioTrack clip) getDurationMs; // TOTAL audio length (ms)
  final double Function(AudioTrack clip) getTrimStartMs; // trim-in within file (ms)
  final double Function(AudioTrack clip) getTrimEndMs; // trim-out within file (ms)
  final List<double>? Function(AudioTrack clip)? getPeaks; // normalized [-1..1]
  final double Function(AudioTrack clip) getY; // visual-only vertical position

  // Selection
  final void Function(int clipIndex)? onSelectClip;
  final VoidCallback? onDeselectAll;

  // Movement (drag)
  final void Function(int clipIndex, double newStartMs, double newY)? onMoveClipPreview; // optional
  final void Function(int clipIndex, double newStartMs, double newY)? onMoveClipCommit; // commit on drop

  // Trimming (stable API)
  final void Function(int clipIndex, double previewTrimStartMs, double previewTrimEndMs)? onTrimPreview;
  final void Function(
    int clipIndex,
    bool isStartHandle,
    double finalTrimStartMs,
    double finalTrimEndMs, {
    double? newStartMsIfStartTrim,
  })? onTrimCommit;

  // Legacy (still supported): called from onTrimCommit for back-compat.
  final void Function(int clipIndex, double newTrimStartMs, double newTrimEndMs, {double? newStartMs})? onTrimClip;

  // Transport / scrub
  final double playheadMs; // -1 to hide
  final void Function(double ms)? onScrubRequested;

  // Zoom/scroll
  final double initialPixelsPerSecond;
  final double minPixelsPerSecond;
  final double maxPixelsPerSecond;

  // Ruler (bars/beats)
  final double bpm;
  final int beatsPerBar;
  final ValueChanged<double>? onBpmChanged;

  // UX
  final bool snapToGrid;
  final double snapStrength; // 0..1
  final double fineDragMultiplier; // 0.12 for precise drag

  // Layout
  final double height; // viewport height
  final double clipHeight; // visual height of a clip
  final double verticalPadding; // top/bottom padding in canvas

  const AudioCanvasTimeline({
    super.key,
    required this.clips,
    this.selectedClipIndex,
    required this.getStartMs,
    required this.getDurationMs,
    required this.getTrimStartMs,
    required this.getTrimEndMs,
    this.getPeaks,
    required this.getY,
    this.onSelectClip,
    this.onMoveClipPreview,
    this.onMoveClipCommit,
    this.onDeselectAll,
    // trim
    this.onTrimPreview,
    this.onTrimCommit,
    this.onTrimClip, // legacy
    // transport
    this.playheadMs = -1,
    this.onScrubRequested,
    // zoom
    this.initialPixelsPerSecond = 180,
    this.minPixelsPerSecond = 10,
    this.maxPixelsPerSecond = 900,
    // ruler
    required this.bpm,
    this.beatsPerBar = 4,
    this.onBpmChanged,
    // UX
    this.snapToGrid = false,
    this.snapStrength = 0.75,
    this.fineDragMultiplier = 0.12,
    // layout
    this.height = 520,
    this.clipHeight = 88,
    this.verticalPadding = 80,
  });

  @override
  State<AudioCanvasTimeline> createState() => _AudioCanvasTimelineState();
}

class _AudioCanvasTimelineState extends State<AudioCanvasTimeline> with TickerProviderStateMixin {
  // Zoom
  late double _pps; // pixels per second
  late final AnimationController _zoomCtrl;
  double _animFromPps = 0, _animToPps = 0;

  // Scroll
  final ScrollController _rulerScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();
  bool _isClipDragActive = false; // disables scroll while true

  // Viewport size cache
  double _viewportW = 0, _viewportH = 0;

  // Drag state
  bool _fineDrag = false;
  int? _dragCi; // dragging clip index
  double _dragOriginStartMs = 0; // clip start at begin
  double _dragOriginY = 0; // clip y at begin
  double _dragDxPx = 0; // cumulative dx (px) since start
  double _dragDyPx = 0; // cumulative dy (px)
  double? _pinchStartDistance; // relative scale tracker
  double? _pinchStartPps; // (kept for future use if needed)

  // Trim PREVIEW state (per-clip, not mutating your model while dragging)
  final Map<int, double> _trimPreviewStart = {};
  final Map<int, double> _trimPreviewEnd = {};

  // Constants
  static const double _rightPadMs = 1500.0;
  static const double _bottomPad = 200.0;

  double? _pendingPlayheadMs; // transient local preview for instant feedback

  // Loop function
  bool _loopEnabled = false;
  double _loopStartMs = 0.0;
  double _loopEndMs = 0.0; // 0 = unset; we’ll default later

  // Left gutter so ruler’s loop pill doesn’t cover bar 0 or clips.
  static const double kLoopBtnW = 44;
  static const double kLoopBtnH = 24;
  static const double kLoopInset = 8;
  final double _leftGutterPx = kLoopInset + kLoopBtnW + 6; // ruler+timeline share this gutter

  int _pointerCount = 0; // track fingers for reliable pinch

// ---- Persist left-edge after a start-trim until parent updates offset ----
  final Map<int, double> _pendingLeftShiftMs = {}; // ci -> (trimStart - baseTrimS)
  final Map<int, double> _lastModelStartMs = {}; // ci -> last seen getStartMs

  @override
  void initState() {
    super.initState();
    _pps = widget.initialPixelsPerSecond;
    _zoomCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120))
      ..addListener(() {
        final t = Curves.easeOutCubic.transform(_zoomCtrl.value);
        setState(() => _pps = _animFromPps + (_animToPps - _animFromPps) * t);
      });

    // Sync ruler with horizontal canvas scroll
    _hScroll.addListener(() {
      if (_rulerScroll.hasClients) {
        _rulerScroll.jumpTo(_hScroll.offset.clamp(
          _rulerScroll.position.minScrollExtent,
          _rulerScroll.position.maxScrollExtent,
        ));
      }
    });
  }

  @override
  void dispose() {
    _zoomCtrl.dispose();
    _hScroll.dispose();
    _rulerScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AudioCanvasTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Drop preview as soon as parent reports a new playhead
    if (oldWidget.playheadMs != widget.playheadMs) _pendingPlayheadMs = null;

    // Clear local left-shift when the model offset changes to our proposed value
    for (int ci = 0; ci < widget.clips.length; ci++) {
      final now = widget.getStartMs(widget.clips[ci]);
      final last = _lastModelStartMs[ci];
      if (last != null && now != last) {
        _pendingLeftShiftMs.remove(ci); // parent accepted new offset: stop applying local shift
      }
      _lastModelStartMs[ci] = now;
    }

    // Reset gesture locks if clip list changed (after import, etc.)
    if (!identical(widget.clips, oldWidget.clips) || widget.clips.length != oldWidget.clips.length) {
      _isClipDragActive = false;
      _dragCi = null;
      _dragDxPx = 0;
      _dragDyPx = 0;
      _pendingLeftShiftMs.clear(); // avoid stale shifts
    }
  }

  // Time/px
  double _msToPx(double ms) => ms / 1000.0 * _pps;
  double _pxToMs(double px) => px / _pps * 1000.0;

  double _projectEndMs() {
    double end = 0;
    for (var c in widget.clips) {
      // Use VISIBLE end (start + (trimEnd-trimStart)) to size canvas sensibly
      final s = widget.getStartMs(c);
      final v = (widget.getTrimEndMs(c) - widget.getTrimStartMs(c)).clamp(1.0, widget.getDurationMs(c));
      end = max(end, s + v);
    }
    return end + _rightPadMs;
  }

  double _contentHeight() {
    double maxY = 0;
    for (var c in widget.clips) {
      maxY = max(maxY, widget.getY(c));
    }
    return max(_viewportH, maxY + widget.clipHeight + widget.verticalPadding + _bottomPad);
  }

  // Snapping/grid
  double _msPerBeat(double bpm) => 60000.0 / (bpm <= 0 ? 120.0 : bpm);
  double _snapMs(double rawMs) {
    if (!widget.snapToGrid || widget.bpm <= 0) return rawMs;
    final beat = _msPerBeat(widget.bpm);
    final snapped = (rawMs / beat).round() * beat;
    return rawMs * (1.0 - widget.snapStrength) + snapped * widget.snapStrength;
  }

  // Zoom with exact world anchor (no drift)
  void _zoomAroundContentX(double focalContentX, double factor) {
    final oldPps = _pps;
    final target = (oldPps * factor).clamp(widget.minPixelsPerSecond, widget.maxPixelsPerSecond);
    final viewLeftPx = _hScroll.hasClients ? _hScroll.offset : 0.0;
    final focalViewportX = focalContentX - viewLeftPx;
    final worldMs = _pxToMs(viewLeftPx + focalViewportX);

    setState(() => _pps = target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hScroll.hasClients) return;
      final newLeftPx = _msToPx(worldMs) - focalViewportX;
      final contentW = max(_viewportW, _msToPx(_projectEndMs()));
      final maxScroll = max(0.0, contentW - _viewportW);
      _hScroll.jumpTo(newLeftPx.clamp(0.0, maxScroll));
    });
  }

  // Overlap detection (using VISIBLE durations)
  bool _wouldOverlap(int movingIndex, double newStartMs, double newEndMs) {
    for (int i = 0; i < widget.clips.length; i++) {
      if (i == movingIndex) continue;
      final c = widget.clips[i];
      final s = widget.getStartMs(c);
      final v = (widget.getTrimEndMs(c) - widget.getTrimStartMs(c)).clamp(1.0, widget.getDurationMs(c));
      final e = s + v;
      if (newStartMs < e && newEndMs > s) return true;
    }
    return false;
  }

  double _msToUiPx(double ms) => _leftGutterPx + _msToPx(ms); // for drawing (clips, playhead, grid)
  double _uiLocalPxToMs(double localXInContent) =>
      _pxToMs((_hScroll.hasClients ? _hScroll.offset : 0.0) + localXInContent);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rulerH = 34.0;
    final playheadToUse = _pendingPlayheadMs ?? widget.playheadMs;

    const Color kRulerBg = Color(0xFF273A59);
    const double kLoopBtnW = 44; // pill width (adjust to taste)
    const double kLoopBtnH = 24; // pill height
    const double kLoopInset = 8; // gap from very left edge
    final double _leftRulerInset = kLoopInset + kLoopBtnW + 6; // padding for ruler content

    return LayoutBuilder(builder: (context, c) {
      _viewportW = c.maxWidth;
      _viewportH = widget.height;
      final contentW = max(_viewportW, _msToPx(_projectEndMs()));
      final contentH = _contentHeight();

      return Listener(
        onPointerDown: (_) => setState(() => _pointerCount++),
        onPointerUp: (_) => setState(() => _pointerCount = (_pointerCount - 1).clamp(0, 10)),
        onPointerCancel: (_) => setState(() => _pointerCount = (_pointerCount - 1).clamp(0, 10)),
        child: SizedBox(
          height: widget.height,
          child: Column(
            children: [
              // ---- RULER ROW (fixed loop pill + padded ruler content) ----
              Container(
                height: rulerH,
                color: kRulerBg,
                child: Stack(
                  children: [
                    // Scrollable ruler content, padded by the gutter
                    Positioned.fill(
                      child: Row(
                        children: [
                          SizedBox(width: _leftGutterPx),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _rulerScroll,
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: SizedBox(
                                width: _msToPx(_projectEndMs()),
                                height: rulerH,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onDoubleTapDown: null, // no action on double tap
                                  onTapDown: (d) {
                                    final ms = _uiLocalPxToMs(d.localPosition.dx);
                                    setState(() => _pendingPlayheadMs = ms.clamp(0.0, _projectEndMs()));
                                    widget.onScrubRequested?.call(ms);
                                  },
                                  onPanUpdate: (d) {
                                    final ms = _uiLocalPxToMs(d.localPosition.dx);
                                    setState(() => _pendingPlayheadMs = ms.clamp(0.0, _projectEndMs()));
                                    widget.onScrubRequested?.call(ms);
                                  },
                                  child: CustomPaint(
                                    size: Size(_msToPx(_projectEndMs()), rulerH),
                                    painter: _BarsBeatsPainter(
                                      pps: _pps,
                                      bpm: widget.bpm,
                                      beatsPerBar: widget.beatsPerBar,
                                      tickColor: Colors.white.withOpacity(0.45),
                                      textColor: Colors.white, // bars start at 0, centered label (you already patched)
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Loop pill (fixed at left)
                    Positioned(
                      left: kLoopInset,
                      top: (rulerH - kLoopBtnH) / 2,
                      width: kLoopBtnW,
                      height: kLoopBtnH,
                      child: _LoopPillButton(
                        enabled: _loopEnabled,
                        onToggle: () {
                          setState(() {
                            _loopEnabled = !_loopEnabled;
                            if (_loopEnabled) {
                              final startMs = (_pendingPlayheadMs ?? widget.playheadMs).clamp(0.0, _projectEndMs());
                              final msPerBeat = 60000.0 / (widget.bpm <= 0 ? 120.0 : widget.bpm);
                              final fourBarsMs = msPerBeat * widget.beatsPerBar * 4;
                              _loopStartMs = startMs;
                              _loopEndMs = (_loopStartMs + fourBarsMs).clamp(_loopStartMs + 1.0, _projectEndMs());
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Canvas (both directions scrollable)
              // ---- CANVAS with left gutter matching the ruler ----
              Expanded(
                child: SingleChildScrollView(
                  controller: _vScroll,
                  scrollDirection: Axis.vertical,
                  physics: _isClipDragActive ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                  child: SizedBox(
                    height: _contentHeight(),
                    child: Row(
                      children: [
                        SizedBox(width: _leftGutterPx), // fixed gutter at left (matches ruler)
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _hScroll,
                            scrollDirection: Axis.horizontal,
                            physics: _isClipDragActive
                                ? const NeverScrollableScrollPhysics()
                                : const ClampingScrollPhysics(),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,

                              // Bulletproof pinch: require two pointers; ignore if a clip drag is active
                              onScaleStart: (d) {
                                if (_isClipDragActive) return;
                                if (_pointerCount < 2) return;
                                _pinchStartDistance = 1.0;
                              },
                              onScaleUpdate: (d) {
                                if (_isClipDragActive) return;
                                if (_pointerCount < 2) return;
                                if (d.scale == 1.0) return;
                                final relative =
                                    (_pinchStartDistance ?? 1.0) == 0 ? 1.0 : d.scale / (_pinchStartDistance ?? 1.0);
                                _pinchStartDistance = d.scale;

                                final viewLeft = _hScroll.hasClients ? _hScroll.offset : 0.0;
                                final focalContentX = viewLeft + d.focalPoint.dx;
                                _zoomAroundContentX(focalContentX, relative);
                              },
                              onScaleEnd: (_) => _pinchStartDistance = null,

                              child: SizedBox(
                                width: _msToPx(_projectEndMs()),
                                child: Stack(
                                  children: [
                                    // Grid (bars only)
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _BeatGridPainter(
                                          pps: _pps,
                                          bpm: widget.bpm,
                                          beatsPerBar: widget.beatsPerBar,
                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
                                        ),
                                      ),
                                    ),

                                    // Clips
                                    for (int ci = 0; ci < widget.clips.length; ci++)
                                      _buildClip(ci, Theme.of(context).colorScheme),

                                    // Playhead (use preview if present)
                                    if ((_pendingPlayheadMs ?? widget.playheadMs) >= 0)
                                      Positioned(
                                        left: _msToUiPx(_pendingPlayheadMs ?? widget.playheadMs),
                                        top: 0,
                                        width: 2,
                                        height: _contentHeight(),
                                        child: Container(color: Theme.of(context).colorScheme.secondary),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      );
    });
  }

  Widget _buildClip(int ci, ColorScheme cs) {
    final clip = widget.clips[ci];

    // Model values
    final modelStartMs = widget.getStartMs(clip); // <-- was startMsModel
    final totalDurMs = widget.getDurationMs(clip);
    final baseTrimS = widget.getTrimStartMs(clip);
    final baseTrimE = widget.getTrimEndMs(clip);
    final y0 = widget.getY(clip);

    // Preview trims during gesture
    final trimStartMs = _trimPreviewStart[ci] ?? baseTrimS;
    final trimEndMs = _trimPreviewEnd[ci] ?? baseTrimE;
    final visibleDurMs = (trimEndMs - trimStartMs).clamp(1.0, totalDurMs);

    // Persisted left-edge shift after a start-trim until parent updates offset
    final leftShiftMs = _pendingLeftShiftMs[ci] ?? (trimStartMs - baseTrimS);

    // Drag state
    final isDragging = _dragCi == ci;
    final dxMs = _pxToMs(_dragDxPx * (_fineDrag ? widget.fineDragMultiplier : 1.0));
    final previewModelStart = isDragging ? (modelStartMs + dxMs).clamp(0.0, double.infinity) : modelStartMs;
    final newY = isDragging ? (y0 + _dragDyPx).clamp(0.0, double.infinity) : y0;

    // Visible left/right on the timeline (DAW-style: start-trim moves left edge)
    final visibleLeftStartMs = (previewModelStart + leftShiftMs).clamp(0.0, double.infinity);
    final visibleEndMs = visibleLeftStartMs + visibleDurMs;

    // Selection & color
    final isSelected = (widget.selectedClipIndex == ci); // <-- define isSelected here
    final invalid = isDragging && _wouldOverlap(ci, visibleLeftStartMs, visibleEndMs);
    final palette = _bandLabPalette(cs);
    final color = invalid ? Colors.redAccent.withOpacity(0.35) : Color(0x1E8CB8FF); //palette[ci % palette.length];

    // Waveform data
    final peaks = widget.getPeaks?.call(clip) ?? const <double>[];
    final startFrac = (trimStartMs / totalDurMs).clamp(0.0, 1.0);
    final endFrac = (trimEndMs / totalDurMs).clamp(0.0, 1.0);

    return Positioned(
      left: _msToUiPx(visibleLeftStartMs), // gutter-aware
      top: newY,
      width: max(4.0, _msToPx(visibleDurMs)),
      height: widget.clipHeight,
      child: _FreeClip(
        cs: cs,
        color: color,
        invalidOutline: invalid,
        isSelected: isSelected,
        peaks: peaks,
        trimStartMs: trimStartMs,
        trimEndMs: trimEndMs,
        totalDurationMs: totalDurMs,

        onTapSelect: () => widget.onSelectClip?.call(ci),

        // DRAG
        onBeginDrag: (_) {
          setState(() {
            _dragCi = ci;
            _dragDxPx = 0;
            _dragDyPx = 0;
            _fineDrag = false;
            _dragOriginStartMs = modelStartMs; // <-- use modelStartMs
            _dragOriginY = y0;
            _isClipDragActive = true;
          });
        },
        onDragUpdate: (deltaDx, deltaDy) {
          setState(() {
            _dragDxPx += deltaDx;
            _dragDyPx += deltaDy;
          });

          // autoscroll based on visible left edge
          final msDelta = (_dragDxPx / _pps) * 1000.0 * (_fineDrag ? widget.fineDragMultiplier : 1.0);
          final previewLeft = max(0.0, (_dragOriginStartMs + msDelta) + leftShiftMs);
          final clipX = _msToPx(previewLeft);
          final viewLeft = _hScroll.offset;
          final viewRight = viewLeft + (_viewportW - _leftGutterPx);
          if (clipX > viewRight - 60) {
            _hScroll.jumpTo(min(_hScroll.position.maxScrollExtent, clipX - ((_viewportW - _leftGutterPx) - 60)));
          } else if (clipX < viewLeft + 60) {
            _hScroll.jumpTo(max(0.0, clipX - 60));
          }
        },
        onDragEnd: () {
          final msDelta = (_dragDxPx / _pps) * 1000.0 * (_fineDrag ? widget.fineDragMultiplier : 1.0);
          final targetModelStart = (modelStartMs + msDelta).clamp(0.0, double.infinity);
          final targetY = max(0.0, y0 + _dragDyPx);

          // Commit using model start (leftShiftMs is visual-only until parent updates)
          if (!_wouldOverlap(ci, targetModelStart + leftShiftMs, targetModelStart + leftShiftMs + visibleDurMs)) {
            widget.onMoveClipCommit?.call(ci, _snapMs(targetModelStart), targetY);
          }
          setState(() {
            _dragCi = null;
            _dragDxPx = 0;
            _dragDyPx = 0;
            _isClipDragActive = false;
          });
        },
        onLongPressToggleFine: () => setState(() => _fineDrag = true),

        // TRIM
        onBeginTrim: (isStart) {
          setState(() {
            _isClipDragActive = true;
            _trimPreviewStart[ci] = trimStartMs;
            _trimPreviewEnd[ci] = trimEndMs;
          });
        },
        onUpdateTrim: (isStart, newS, newE) {
          final minDur = 10.0;
          double s = newS.clamp(0.0, totalDurMs - minDur);
          double e = newE.clamp(s + minDur, totalDurMs);
          setState(() {
            _trimPreviewStart[ci] = s;
            _trimPreviewEnd[ci] = e;
          });
          widget.onTrimPreview?.call(ci, s, e);
        },
        onEndTrim: (isStart) {
          final s = _trimPreviewStart[ci] ?? baseTrimS;
          final e = _trimPreviewEnd[ci] ?? baseTrimE;

          if (isStart) {
            final delta = s - baseTrimS; // left edge moved by delta
            final proposedNewStart = max(0.0, modelStartMs + delta);

            // persist visually until parent updates offset to proposedNewStart
            setState(() => _pendingLeftShiftMs[ci] = delta);

            widget.onTrimCommit?.call(ci, true, s, e, newStartMsIfStartTrim: proposedNewStart);
            widget.onTrimClip?.call(ci, s, e, newStartMs: proposedNewStart); // legacy
          } else {
            widget.onTrimCommit?.call(ci, false, s, e);
            widget.onTrimClip?.call(ci, s, e);
          }

          setState(() {
            _isClipDragActive = false;
            _trimPreviewStart.remove(ci);
            _trimPreviewEnd.remove(ci);
          });
        },
      ),
    );
  }
}

/// ===== Free clip (draggable in X/Y) =====
class _FreeClip extends StatefulWidget {
  final ColorScheme cs;
  final bool isSelected;
  final Color color;
  final bool invalidOutline;
  final List<double> peaks; // normalized [-1..1]
  final double trimStartMs;
  final double trimEndMs;
  final double totalDurationMs;

  final VoidCallback onTapSelect;
  final void Function(Offset globalPosInClip)? onBeginDrag;
  final void Function(double dx, double dy)? onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onLongPressToggleFine;

  // Trim lifecycle (preview inside parent; commit onEndTrim)
  final void Function(bool isStart) onBeginTrim;
  final void Function(bool isStart, double newTrimStartMs, double newTrimEndMs) onUpdateTrim;
  final void Function(bool isStart) onEndTrim;

  const _FreeClip({
    required this.cs,
    required this.isSelected,
    required this.color,
    required this.invalidOutline,
    required this.peaks,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.totalDurationMs,
    required this.onTapSelect,
    this.onBeginDrag,
    this.onDragUpdate,
    required this.onDragEnd,
    required this.onLongPressToggleFine,
    required this.onBeginTrim,
    required this.onUpdateTrim,
    required this.onEndTrim,
  });

  @override
  State<_FreeClip> createState() => _FreeClipState();
}

class _FreeClipState extends State<_FreeClip> {
  static const double _handleW = 20.0; // easier to grab
  static const double _minTrimMs = 10.0; // cannot trim to zero

  Offset? _lastGlobal;
  bool _isTrimming = false;
  bool _lockDrag = false;

  void _setTrimming(bool v) => setState(() => _isTrimming = v);

  @override
  Widget build(BuildContext context) {
    final peaks = widget.peaks;
    final trimS = widget.trimStartMs;
    final trimE = widget.trimEndMs;
    final totalDurationMs = widget.totalDurationMs;
    final startFrac = (trimS / totalDurationMs).clamp(0.0, 1.0);
    final endFrac = (trimE / totalDurationMs).clamp(0.0, 1.0);

    // DRAG recognizer that wins the arena when needed
    return RawGestureDetector(
      gestures: {
        _AlwaysWinPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<_AlwaysWinPanGestureRecognizer>(
          () => _AlwaysWinPanGestureRecognizer(),
          (g) {
            g
              ..onDown = (_) {/* reserve if needed */}
              ..onStart = (d) {
                // Auto-select so drag always works, even if user didn't tap first.
                _lastGlobal = d.globalPosition;
                final parent = context.findAncestorStateOfType<_AudioCanvasTimelineState>();
                if (parent?._pointerCount != null && parent!._pointerCount >= 2) return; // let pinch win
                // Trigger selection immediately
                // (We call the same callback used by tap)
                if (mounted) {
                  // Call the onTapSelect from parent by finding our widget via context
                  // but we have direct access already:
                }
                // Since we don't have a direct ref here, just synthesize a tap:
                widget.onTapSelect();

                widget.onBeginDrag?.call(d.globalPosition);
                parent?._isClipDragActive = true;
              }
              ..onUpdate = (d) {
                final parent = context.findAncestorStateOfType<_AudioCanvasTimelineState>();
                if (parent?._pointerCount != null && parent!._pointerCount >= 2) return;

                if (_lockDrag || !widget.isSelected || _lastGlobal == null) return;
                final dx = d.globalPosition.dx - _lastGlobal!.dx;
                final dy = d.globalPosition.dy - _lastGlobal!.dy;
                _lastGlobal = d.globalPosition;
                widget.onDragUpdate?.call(dx, dy);
              }
              ..onEnd = (_) {
                if (_lockDrag || !widget.isSelected) return;
                widget.onDragEnd();
                final parent = context.findAncestorStateOfType<_AudioCanvasTimelineState>();
                parent?._isClipDragActive = false;
              };
          },
        ),
      },
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTapSelect,
        onLongPressStart: (_) => widget.onLongPressToggleFine(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: _isTrimming ? (Matrix4.identity()..scale(1.03)) : Matrix4.identity(),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected ? Colors.white : widget.cs.outlineVariant.withOpacity(0.45),
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                        color: Colors.white.withOpacity(0.2),
                        blurRadius: 10,
                        spreadRadius: 2,
                        offset: const Offset(0, 2)),
                    BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 4)),
                  ]
                : [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // waveform (mirrored min/max; zoom-accurate because it uses actual widget width)
              Positioned.fill(
                child: CustomPaint(
                  isComplex: true,
                  willChange: true,
                  painter: _WavePainterDoubleSided(
                    samples: peaks,
                    startFrac: startFrac,
                    endFrac: endFrac,
                    color: widget.cs.onSurface.withOpacity(0.92),
                    filled: true, // set false for bar-style
                  ),
                ),
              ),
              // trim handles (selected only)
              if (widget.isSelected)
                Positioned.fill(
                  child: Row(
                    children: [
                      // LEFT
                      _TrimHandle(
                        side: AxisDirection.left,
                        width: _handleW,
                        onStart: () {
                          widget.onBeginTrim(true);
                          _setTrimming(true);
                          _lockDrag = true;
                        },
                        onDrag: (dx) {
                          final w = context.size?.width ?? 1;
                          final visible = (trimE - trimS).clamp(_minTrimMs, totalDurationMs);
                          final msPerPx = visible / w;
                          double newS = (trimS + dx * msPerPx).clamp(0.0, trimE - _minTrimMs);
                          widget.onUpdateTrim(true, newS, trimE); // preview only
                        },
                        onEnd: () {
                          _setTrimming(false);
                          _lockDrag = false;
                          widget.onEndTrim(true); // commit up-chain
                        },
                        glowOnTouch: true,
                      ),
                      const Expanded(child: SizedBox()),
                      // RIGHT
                      _TrimHandle(
                        side: AxisDirection.right,
                        width: _handleW,
                        onStart: () {
                          widget.onBeginTrim(false);
                          _setTrimming(true);
                          _lockDrag = true;
                        },
                        onDrag: (dx) {
                          final w = context.size?.width ?? 1;
                          final visible = (trimE - trimS).clamp(_minTrimMs, totalDurationMs);
                          final msPerPx = visible / w;
                          double newE = (trimE + dx * msPerPx).clamp(trimS + _minTrimMs, totalDurationMs);
                          widget.onUpdateTrim(false, trimS, newE); // preview only
                        },
                        onEnd: () {
                          _setTrimming(false);
                          _lockDrag = false;
                          widget.onEndTrim(false); // commit up-chain
                        },
                        glowOnTouch: true,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrimHandle extends StatefulWidget {
  final AxisDirection side;
  final double width;
  final void Function(double dx) onDrag;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final bool glowOnTouch;

  const _TrimHandle({
    required this.side,
    required this.width,
    required this.onDrag,
    required this.onStart,
    required this.onEnd,
    this.glowOnTouch = true,
  });

  @override
  State<_TrimHandle> createState() => _TrimHandleState();
}

class _TrimHandleState extends State<_TrimHandle> {
  Offset? _last;
  bool _isActive = false;

  @override
  Widget build(BuildContext context) {
    final bool isLeft = widget.side == AxisDirection.left;
    final accent = Theme.of(context).colorScheme.secondary;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanDown: (_) {
        setState(() => _isActive = true);
        final parent = context.findAncestorStateOfType<_FreeClipState>();
        parent?._setTrimming(true);
        parent?._lockDrag = true;
      },
      onPanStart: (d) {
        _last = d.globalPosition;
        widget.onStart();
      },
      onPanUpdate: (d) {
        final dx = d.globalPosition.dx - (_last ?? d.globalPosition).dx;
        _last = d.globalPosition;
        widget.onDrag(dx);
      },
      onPanEnd: (_) {
        setState(() => _isActive = false);
        final parent = context.findAncestorStateOfType<_FreeClipState>();
        parent?._setTrimming(false);
        parent?._lockDrag = false;
        widget.onEnd();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: widget.width,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isLeft
                ? [
                    (_isActive && widget.glowOnTouch ? accent.withOpacity(0.45) : Colors.white.withOpacity(0.15)),
                    Colors.transparent
                  ]
                : [
                    Colors.transparent,
                    (_isActive && widget.glowOnTouch ? accent.withOpacity(0.45) : Colors.white.withOpacity(0.15))
                  ],
          ),
          boxShadow: _isActive && widget.glowOnTouch
              ? [
                  BoxShadow(
                      color: accent.withOpacity(0.55),
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: Offset(isLeft ? 2 : -2, 0))
                ]
              : [
                  BoxShadow(
                      color: Colors.white.withOpacity(0.15),
                      blurRadius: 6,
                      spreadRadius: 2,
                      offset: Offset(isLeft ? 2 : -2, 0))
                ],
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 3,
            height: double.infinity,
            decoration: BoxDecoration(
              color: _isActive ? accent : Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

// Ensures our clip drags always win over ScrollView drags
class _AlwaysWinPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);
  }
}

/// ===== Ruler & Grid Painters =====
class _BarsBeatsRuler extends StatelessWidget {
  final double width;
  final double height;
  final double pps;
  final double bpm;
  final int beatsPerBar;
  final Color tickColor;
  final Color textColor;
  final void Function(double localX)? onTapOrDrag;
  final void Function(double dx, double scale)? onDoubleTapZoom;
  const _BarsBeatsRuler(
      {required this.width,
      required this.height,
      required this.pps,
      required this.bpm,
      required this.beatsPerBar,
      required this.tickColor,
      required this.textColor,
      this.onTapOrDrag,
      this.onDoubleTapZoom});
  @override
  Widget build(BuildContext context) {
    // Solid background block to separate from timeline
    const rulerBg = Color(0xFF273A59);

    return Container(
      color: rulerBg,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // (3) No double-tap action anymore
        onDoubleTapDown: null,
        // (4) Tap = instant scrub + instant visual (see section 4)
        onTapDown: (d) => onTapOrDrag?.call(d.localPosition.dx),
        onPanUpdate: (d) => onTapOrDrag?.call(d.localPosition.dx),
        child: CustomPaint(
          size: Size(width, height),
          painter: _BarsBeatsPainter(
            pps: pps,
            bpm: bpm,
            beatsPerBar: beatsPerBar,
            tickColor: Colors.white.withOpacity(0.45), // looks better on dark bg
            textColor: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _BarsBeatsPainter extends CustomPainter {
  final double pps;
  final double bpm;
  final int beatsPerBar;
  final Color tickColor;
  final Color textColor;
  _BarsBeatsPainter(
      {required this.pps,
      required this.bpm,
      required this.beatsPerBar,
      required this.tickColor,
      required this.textColor});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = tickColor
      ..strokeWidth = 1;

    final tp = TextPainter(textAlign: TextAlign.center, textDirection: TextDirection.ltr);
    final msPerBeat = 60000.0 / (bpm <= 0 ? 120.0 : bpm);
    final pxPerBeat = (msPerBeat / 1000.0) * pps;

    // Subdivision ticks remain only on ruler (not grid)
    int subdivision = 4;
    if (pxPerBeat < 30)
      subdivision = 1;
    else if (pxPerBeat < 60) subdivision = 2;
    final pxPerSub = pxPerBeat / subdivision;

    for (double x = 0; x <= size.width; x += pxPerSub) {
      final subIndex = (x / pxPerSub).round();
      final isBeat = subIndex % subdivision == 0;
      final beatIndex = (x / pxPerBeat).round();
      final isBar = isBeat && (beatIndex % beatsPerBar == 0);

      // ticks at the bottom of the ruler strip
      final h = isBar ? 16.0 : (isBeat ? 12.0 : 6.0);
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), p);

      if (isBar) {
        // (1) start bars at 0, not 1; number per bar
        final barNum = (beatIndex / beatsPerBar).round(); // 0,1,2,...

        // (2) center the number ON TOP of the bar line
        final label = TextSpan(text: '$barNum', style: TextStyle(fontSize: 10, color: textColor));
        tp.text = label;
        tp.layout(); // width for centering
        final textX = x - tp.width / 2;
        final textY = 2.0; // a little padding from the top
        tp.paint(canvas, Offset(textX, textY));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarsBeatsPainter old) =>
      old.pps != pps ||
      old.bpm != bpm ||
      old.beatsPerBar != beatsPerBar ||
      old.tickColor != tickColor ||
      old.textColor != textColor;
}

class _BeatGridPainter extends CustomPainter {
  final double pps; // pixels per second
  final double bpm;
  final int beatsPerBar;
  final Color color;

  // Optional styling knobs (tweak if you like)
  final double barOpacity;
  final double barStrokeWidth;

  _BeatGridPainter({
    required this.pps,
    required this.bpm,
    required this.beatsPerBar,
    required this.color,
    this.barOpacity = 0.16,
    this.barStrokeWidth = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pps <= 0 || size.width <= 0 || size.height <= 0) return;

    final msPerBeat = 60000.0 / (bpm <= 0 ? 120.0 : bpm);
    final pxPerBeat = (msPerBeat / 1000.0) * pps;
    if (pxPerBeat <= 0) return;

    final p = Paint()
      ..color = color.withOpacity(barOpacity)
      ..strokeWidth = barStrokeWidth;

    // Draw ONLY bar (measure) lines; skip beat subdivisions.
    for (double x = 0; x <= size.width; x += pxPerBeat) {
      final beatIndex = (x / pxPerBeat).round();
      final isBar = beatIndex % beatsPerBar == 0;
      if (isBar) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BeatGridPainter old) =>
      old.pps != pps ||
      old.bpm != bpm ||
      old.beatsPerBar != beatsPerBar ||
      old.color != color ||
      old.barOpacity != barOpacity ||
      old.barStrokeWidth != barStrokeWidth;
}

/// ===== Waveform Painter (double-sided, DAW-style, trim-aware) =====
class _WavePainterDoubleSided extends CustomPainter {
  final List<double> samples; // normalized -1..1 for the FULL file
  final double startFrac; // 0..1 (trimStart / totalDuration)
  final double endFrac; // 0..1 (trimEnd   / totalDuration)
  final Color color;
  final bool filled; // true = filled "butterfly", false = bars

  _WavePainterDoubleSided({
    required this.samples,
    required this.startFrac,
    required this.endFrac,
    required this.color,
    this.filled = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;

    final mid = size.height / 2.0;
    final total = samples.length;
    final iStart = (startFrac.clamp(0.0, 1.0) * (total - 1)).floor();
    final iEnd = (endFrac.clamp(0.0, 1.0) * (total - 1)).ceil();
    final window = (iEnd - iStart + 1).clamp(1, total);

    final widthPx = size.width.ceil();
    final spp = window / widthPx.clamp(1, window).toDouble(); // samples per pixel in visible window

    if (filled) {
      // Build top and bottom paths for a smooth filled mirror shape
      final top = Path();
      final bot = Path();

      for (int x = 0; x < widthPx; x++) {
        final center = (x + 0.5) * spp + iStart;
        final halfWin = spp < 1.5 ? 1 : spp.ceil();
        final j0 = (center - halfWin).floor().clamp(iStart, iEnd);
        final j1 = (center + halfWin).ceil().clamp(iStart, iEnd);

        double minAmp = 1.0;
        double maxAmp = -1.0;
        for (int j = j0; j <= j1; j++) {
          final v = samples[j];
          if (v < minAmp) minAmp = v;
          if (v > maxAmp) maxAmp = v;
        }

        // Double-sided magnitude (Ableton/FL look)
        final mag = math.max(maxAmp.abs(), minAmp.abs()).clamp(0.0, 1.0);
        final yTop = mid - mag * mid;
        final yBot = mid + mag * mid;

        final dx = x + 0.5;
        if (x == 0) {
          top.moveTo(dx, yTop);
          bot.moveTo(dx, yBot);
        } else {
          top.lineTo(dx, yTop);
          bot.lineTo(dx, yBot);
        }
      }

      // Close into a single butterfly path: top left→right, bottom right→left
      final path = Path.from(top)
        ..lineTo(widthPx.toDouble(), mid)
        ..addPath(bot, Offset.zero)
        ..lineTo(0, mid)
        ..close();

      final fill = Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.35), color.withOpacity(0.10)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

      final edge = Paint()
        ..color = color.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawPath(path, fill);
      canvas.drawPath(top, edge);
      canvas.drawPath(bot, edge);
    } else {
      // Lightweight bar style (per-pixel mirrored sticks)
      final stroke = Paint()
        ..color = color.withOpacity(0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..isAntiAlias = false;

      for (int x = 0; x < widthPx; x++) {
        final center = (x + 0.5) * spp + iStart;
        final halfWin = spp < 1.5 ? 1 : spp.ceil();
        final j0 = (center - halfWin).floor().clamp(iStart, iEnd);
        final j1 = (center + halfWin).ceil().clamp(iStart, iEnd);

        double minAmp = 1.0, maxAmp = -1.0;
        for (int j = j0; j <= j1; j++) {
          final v = samples[j];
          if (v < minAmp) minAmp = v;
          if (v > maxAmp) maxAmp = v;
        }

        final mag = math.max(maxAmp.abs(), minAmp.abs()).clamp(0.0, 1.0);
        final yTop = mid - mag * mid;
        final yBot = mid + mag * mid;

        final dx = x + 0.5;
        canvas.drawLine(Offset(dx, mid), Offset(dx, yTop), stroke);
        canvas.drawLine(Offset(dx, mid), Offset(dx, yBot), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainterDoubleSided old) =>
      !identical(old.samples, samples) ||
      old.startFrac != startFrac ||
      old.endFrac != endFrac ||
      old.color != color ||
      old.filled != filled;
}

/// ===== Palette & placeholders =====
List<Color> _bandLabPalette(ColorScheme cs) {
  return [
    const Color(0xFFEB5757),
    const Color(0xFF27AE60),
    const Color(0xFF2D9CDB),
    const Color(0xFFF2994A),
    const Color(0xFF9B51E0),
    const Color(0xFF56CCF2),
    const Color(0xFFFF66C4)
  ].map((c) => Color.alphaBlend(c.withOpacity(0.65), cs.surface)).toList();
}

List<double> _placeholderPeaks(int n) {
  final r = Random(12);
  return List<double>.generate(n, (i) {
    final base = sin(i / 9) * 0.7 + sin(i / 21) * 0.3;
    final noise = (r.nextDouble() - 0.5) * 0.18;
    return (base + noise).clamp(-1.0, 1.0);
  });
}

class _LoopOverlay extends StatefulWidget {
  final double pps;
  final double startMs;
  final double endMs;
  final Color color;
  final void Function(double dxPx) onDragLeft;
  final void Function(double dxPx) onDragRight;
  final void Function(double dxPx) onDragWhole;

  const _LoopOverlay({
    required this.pps,
    required this.startMs,
    required this.endMs,
    required this.color,
    required this.onDragLeft,
    required this.onDragRight,
    required this.onDragWhole,
  });

  @override
  State<_LoopOverlay> createState() => _LoopOverlayState();
}

class _LoopOverlayState extends State<_LoopOverlay> {
  Offset? _last;

  @override
  Widget build(BuildContext context) {
    final left = widget.startMs / 1000.0 * widget.pps;
    final width = ((widget.endMs - widget.startMs) / 1000.0) * widget.pps;

    return Stack(
      children: [
        // Drag the whole region
        Positioned(
          left: left,
          top: 0,
          width: width,
          height: double.infinity,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (d) => _last = d.globalPosition,
            onPanUpdate: (d) {
              final dx = d.globalPosition.dx - (_last ?? d.globalPosition).dx;
              _last = d.globalPosition;
              widget.onDragWhole(dx);
            },
            onPanEnd: (_) => _last = null,
            child: Container(
              color: widget.color, // semi-transparent red band
            ),
          ),
        ),

        // Left handle
        Positioned(
          left: left - 6,
          top: 0,
          width: 12,
          height: double.infinity,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (d) => _last = d.globalPosition,
              onPanUpdate: (d) {
                final dx = d.globalPosition.dx - (_last ?? d.globalPosition).dx;
                _last = d.globalPosition;
                widget.onDragLeft(dx);
              },
              onPanEnd: (_) => _last = null,
              child: Container(color: Colors.transparent),
            ),
          ),
        ),

        // Right handle
        Positioned(
          left: left + width - 6,
          top: 0,
          width: 12,
          height: double.infinity,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (d) => _last = d.globalPosition,
              onPanUpdate: (d) {
                final dx = d.globalPosition.dx - (_last ?? d.globalPosition).dx;
                _last = d.globalPosition;
                widget.onDragRight(dx);
              },
              onPanEnd: (_) => _last = null,
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
      ],
    );
  }
}
 
class _LoopPillButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onToggle;
  const _LoopPillButton({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(enabled ? 0.22 : 0.12),
      borderRadius: BorderRadius.circular(999),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.35),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(999),
        child: Center(
          child: Icon(
            enabled ? Icons.repeat_on : Icons.repeat,
            size: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// Thin red band inside the ruler to show loop range (visual only)
class _LoopBandPainter extends CustomPainter {
  final double pps;
  final double startMs;
  final double endMs;
  final Color color;
  final double leftInsetPx;
  _LoopBandPainter({
    required this.pps,
    required this.startMs,
    required this.endMs,
    required this.color,
    required this.leftInsetPx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final left = leftInsetPx + (startMs / 1000.0) * pps;
    final width = ((endMs - startMs) / 1000.0) * pps;
    final rect = Rect.fromLTWH(left, 0, width, size.height);
    final paint = Paint()..color = color;
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _LoopBandPainter old) =>
      old.pps != pps ||
      old.startMs != startMs ||
      old.endMs != endMs ||
      old.color != color ||
      old.leftInsetPx != leftInsetPx;
}

*/

// ---------------------------------------------------------------------------

// AudioCanvasTimeline — freeform, row-less audio timeline (BandLab-style)
// Fully audio-only. Clips can be placed at any vertical position; JUCE cares
// only about time (start/duration). This widget provides:
// - Bars/Beats ruler (BPM-aware) with buttery zoom/pan
// - Freeform clip dragging in X (time) and Y (visual lane), with snapping
// - Long-press fine-drag (reduced sensitivity) for micro placement
// - Hovering/floating visual while dragging; other clips remain immutable
// - Overlap detection: on drop, do NOT commit when overlapping. Show soft red
//   invalid state; keep clip selected and floating so user can resolve.
// - Trimming: PREVIEW during drag, COMMIT on release (prevents teleport).
//   When START trim changes, we also propose newStartMs for offset shift.
// - Selection: tap a clip => onSelectClip(index).
// - High-detail waveform rendering (catmull-rom-ish)
// - BandLab-inspired colors and modern shadows
//
// New (optional) callbacks for robust trim behavior:
//   onTrimPreview(int i, double previewStartMs, double previewEndMs)
//   onTrimCommit (int i, bool isStartHandle, double finalStartMs, double finalEndMs, {double? newStartMsIfStartTrim})
//
// Back-compat: if you still pass onTrimClip, we’ll call it from onTrimCommit.
//
// Example glue:
//
// AudioCanvasTimeline<AudioClip>(
//   clips: _audioTracks,
//   getStartMs: (c) => c.offset * 1000.0,
//   getDurationMs: (c) => c.audioDuration.inMilliseconds.toDouble(), // TOTAL length
//   getTrimStartMs: (c) => c.trimStart.inMilliseconds.toDouble(),
//   getTrimEndMs:   (c) => c.trimEnd.inMilliseconds.toDouble(),
//   getPeaks: (c) => c.normWaveformData,
//   getY: (c) => c.y,
//   selectedClipIndex: _selectedTrackIndex,
//   onSelectClip: (i) => setState(() => _selectedTrackIndex = i),
//   onMoveClipCommit: (i, newStartMs, newY) {
//     final clip = _audioTracks[i];
//     clip.offset = newStartMs / 1000.0;
//     clip.y = newY;
//     setState(() {});
//     JuceAudioEngine.moveClip(i, clip.offset);
//   },
//   onTrimPreview: (i, s, e) { /* optional UI */ },
//   onTrimCommit: (i, isStart, s, e, {double? newStartMsIfStartTrim}) {
//     final c = _audioTracks[i];
//     c.trimStart = Duration(milliseconds: s.round());
//     c.trimEnd   = Duration(milliseconds: e.round());
//     if (isStart && newStartMsIfStartTrim != null) {
//       c.offset = newStartMsIfStartTrim / 1000.0;
//       JuceAudioEngine.moveClip(i, c.offset);
//     }
//     setState(() {});
//     JuceAudioEngine.trimClip(i, s / 1000.0, e / 1000.0);
//   },
//   playheadMs: _globalAudioClock.inMilliseconds.toDouble(),
//   onScrubRequested: (ms) => JuceAudioEngine.seekGlobal(ms / 1000.0),
//   bpm: _projectBpm,
//   onBpmChanged: (b) { setState(() => _projectBpm = b); JuceAudioEngine.setProjectBpm(b); },
// )

import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ==== BEGIN PATCH: helpers for reliable timeline ====
enum _DragMode { none, moveClip, trimStart, trimEnd, timelinePanZoom }

class _TimelineViewport {
  double pxPerSecond;
  final double minPxPerSecond;
  final double maxPxPerSecond;
  double scrollX; // pixels

  _TimelineViewport({
    this.pxPerSecond = 120,
    this.minPxPerSecond = 20,
    this.maxPxPerSecond = 2000,
    this.scrollX = 0,
  });

  double timeToPx(double tSeconds) => tSeconds * pxPerSecond - scrollX;
  double pxToTime(double xPx) => (xPx + scrollX) / pxPerSecond;

  void zoomAt(double anchorX, double scaleDelta) {
    final old = pxPerSecond;
    pxPerSecond = (pxPerSecond * scaleDelta).clamp(minPxPerSecond, maxPxPerSecond);
    final timeAtAnchor = (anchorX + scrollX) / old;
    scrollX = timeAtAnchor * pxPerSecond - anchorX;
    if (scrollX.isNaN || scrollX < 0) scrollX = 0;
  }

  void panByPixels(double dx) {
    scrollX = (scrollX + dx).clamp(0.0, double.maxFinite);
  }
}

class _DragState {
  _DragMode mode = _DragMode.none;
  int? clipId;

  // invariant anchors
  double dragStartTime = 0; // timeline time at pointer-down
  double clipStartOffset = 0; // (pointer time - clip.start) to avoid teleport

  // for trims
  double origClipStart = 0;
  double origClipEnd = 0;

  // pinch zoom
  double lastScale = 1;
}
// ==== END PATCH ====

class AudioCanvasTimeline<TClip> extends StatefulWidget {
  // Data (flat list of clips — row-less)
  final List<TClip> clips;
  final int? selectedClipIndex;

  // Extractors
  final double Function(TClip clip) getStartMs; // clip offset on timeline (ms)
  final double Function(TClip clip) getDurationMs; // TOTAL audio length (ms)
  final double Function(TClip clip) getTrimStartMs; // trim-in within file (ms)
  final double Function(TClip clip) getTrimEndMs; // trim-out within file (ms)
  final List<double>? Function(TClip clip)? getPeaks;
  final double Function(TClip clip) getY; // visual-only vertical position

  // Selection
  final void Function(int clipIndex)? onSelectClip;
  final VoidCallback? onDeselectAll;

  // Movement (drag)
  final void Function(int clipIndex, double newStartMs, double newY)? onMoveClipPreview; // optional
  final void Function(int clipIndex, double newStartMs, double newY)? onMoveClipCommit; // commit on drop

  // Trimming — new, production-stable:
  final void Function(int clipIndex, double previewTrimStartMs, double previewTrimEndMs)? onTrimPreview;
  final void Function(
    int clipIndex,
    bool isStartHandle,
    double finalTrimStartMs,
    double finalTrimEndMs, {
    double? newStartMsIfStartTrim,
  })? onTrimCommit;

  // Legacy (still supported): called from onTrimCommit for back-compat.
  final void Function(int clipIndex, double newTrimStartMs, double newTrimEndMs, {double? newStartMs})? onTrimClip;

  // Transport / scrub
  final double playheadMs; // -1 to hide
  final void Function(double ms)? onScrubRequested;

  // Zoom/scroll
  final double initialPixelsPerSecond;
  final double minPixelsPerSecond;
  final double maxPixelsPerSecond;

  // Ruler (bars/beats)
  final double bpm;
  final int beatsPerBar;
  final ValueChanged<double>? onBpmChanged;

  // UX
  final bool snapToGrid;
  final double snapStrength; // 0..1
  final double fineDragMultiplier; // 0.12 for precise drag

  // Layout
  final double height; // viewport height
  final double clipHeight; // visual height of a clip
  final double verticalPadding; // top/bottom padding in canvas

  const AudioCanvasTimeline({
    super.key,
    required this.clips,
    this.selectedClipIndex,
    required this.getStartMs,
    required this.getDurationMs,
    required this.getTrimStartMs,
    required this.getTrimEndMs,
    this.getPeaks,
    required this.getY,
    this.onSelectClip,
    this.onMoveClipPreview,
    this.onMoveClipCommit,
    this.onDeselectAll,
    // trim
    this.onTrimPreview,
    this.onTrimCommit,
    this.onTrimClip, // legacy
    // transport
    this.playheadMs = -1,
    this.onScrubRequested,
    // zoom
    this.initialPixelsPerSecond = 180,
    this.minPixelsPerSecond = 10,
    this.maxPixelsPerSecond = 900,
    // ruler
    required this.bpm,
    this.beatsPerBar = 4,
    this.onBpmChanged,
    // UX
    this.snapToGrid = true,
    this.snapStrength = 0.75,
    this.fineDragMultiplier = 0.12,
    // layout
    this.height = 520,
    this.clipHeight = 88,
    this.verticalPadding = 80,
  });

  @override
  State<AudioCanvasTimeline<TClip>> createState() => _AudioCanvasTimelineState<TClip>();
}

class _AudioCanvasTimelineState<TClip> extends State<AudioCanvasTimeline<TClip>> with TickerProviderStateMixin {
  // Zoom
  late double _pps; // pixels per second
  late final AnimationController _zoomCtrl;
  double _animFromPps = 0, _animToPps = 0;

  // Scroll
  final ScrollController _rulerScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();
  bool _isClipDragActive = false; // disables scroll while true

  // Viewport size cache
  double _viewportW = 0, _viewportH = 0;

  // Pinch state (horizontal zoom)
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double? _pinchStartPps;
  double? _pinchFocalViewportX;

  // Drag state
  bool _fineDrag = false;
  int? _dragCi; // dragging clip index
  double _dragOriginStartMs = 0; // clip start at begin
  double _dragOriginY = 0; // clip y at begin
  double _dragDxPx = 0; // cumulative dx (px) since start
  double _dragDyPx = 0; // cumulative dy (px)

  // Trim PREVIEW state (per-clip, not mutating your model while dragging)
  final Map<int, double> _trimPreviewStart = {};
  final Map<int, double> _trimPreviewEnd = {};

  // Constants
  static const double _rightPadMs = 1500.0;
  static const double _bottomPad = 200.0;

  // ==== BEGIN PATCH: state fields ====
  final _TimelineViewport _view = _TimelineViewport();
  final _DragState _drag = _DragState();

  int? _selectedClipId;
  static const double _handleW = 14;
  static const double _handleHit = 18;
  // ==== END PATCH ====

  @override
  void initState() {
    super.initState();
    _pps = widget.initialPixelsPerSecond;
    _zoomCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120))
      ..addListener(() {
        final t = Curves.easeOutCubic.transform(_zoomCtrl.value);
        setState(() => _pps = _animFromPps + (_animToPps - _animFromPps) * t);
      });

    // Sync ruler with horizontal canvas scroll
    _hScroll.addListener(() {
      if (_rulerScroll.hasClients) {
        _rulerScroll.jumpTo(_hScroll.offset.clamp(
          _rulerScroll.position.minScrollExtent,
          _rulerScroll.position.maxScrollExtent,
        ));
      }
    });
  }

  @override
  void dispose() {
    _zoomCtrl.dispose();
    _hScroll.dispose();
    _rulerScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

// ==== BEGIN PATCH: helpers inside State ====
  TClip? _clipById(int id) {
    // Adapt this to your data source if needed.
    try {
      return widget.clips.firstWhere((c) => c!.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Returns which thing was hit: a trim handle, the clip, or the background.
  ({_DragMode mode, int? id}) _hit(Offset pos) {
    // Iterate topmost first: if you render clips in order, reverse for hit priority.
    for (final c in widget.clips.reversed) {
      final x1 = _view.timeToPx(c.startSec);
      final x2 = _view.timeToPx(c.endSec);
      final y1 = c.y;
      final y2 = c.y + c.height;

      final inside = (pos.dx >= x1 && pos.dx <= x2 && pos.dy >= y1 && pos.dy <= y2);
      if (!inside) continue;

      if ((pos.dx - x1).abs() <= _handleHit) return (mode: _DragMode.trimStart, id: c.id);
      if ((pos.dx - x2).abs() <= _handleHit) return (mode: _DragMode.trimEnd, id: c.id);
      return (mode: _DragMode.moveClip, id: c.id);
    }
    return (mode: _DragMode.timelinePanZoom, id: null);
  }

  void _lockOnPointerDown(Offset pos) {
    final hit = _hit(pos);
    _drag.mode = hit.mode;
    _drag.clipId = hit.id;

    final t = _view.pxToTime(pos.dx);
    _drag.dragStartTime = t;

    if (_drag.mode == _DragMode.moveClip && _drag.clipId != null) {
      final c = _clipById(_drag.clipId!)!;
      _drag.clipStartOffset = t - c.startSec; // Prevents teleporting
      _selectedClipId = c.id;
      onSelectClip?.call(c.id); // if you expose this callback
    } else if ((_drag.mode == _DragMode.trimStart || _drag.mode == _DragMode.trimEnd) && _drag.clipId != null) {
      final c = _clipById(_drag.clipId!)!;
      _drag.origClipStart = c.startSec;
      _drag.origClipEnd = c.endSec;
      _selectedClipId = c.id;
      onSelectClip?.call(c.id);
    } else {
      _drag.lastScale = 1;
    }
    setState(() {});
  }
// ==== END PATCH ====

  // Time/px
  double _msToPx(double ms) => ms / 1000.0 * _pps;
  double _pxToMs(double px) => px / _pps * 1000.0;

  double _projectEndMs() {
    double end = 0;
    for (var c in widget.clips) {
      // Use VISIBLE end (start + (trimEnd-trimStart)) to size canvas sensibly
      final s = widget.getStartMs(c);
      final v = (widget.getTrimEndMs(c) - widget.getTrimStartMs(c)).clamp(1.0, widget.getDurationMs(c));
      end = max(end, s + v);
    }
    return end + _rightPadMs;
  }

  double _contentHeight() {
    double maxY = 0;
    for (var c in widget.clips) {
      maxY = max(maxY, widget.getY(c));
    }
    return max(_viewportH, maxY + widget.clipHeight + widget.verticalPadding + _bottomPad);
  }

  // Snapping/grid
  double _msPerBeat(double bpm) => 60000.0 / (bpm <= 0 ? 120.0 : bpm);
  double _snapMs(double rawMs) {
    if (!widget.snapToGrid || widget.bpm <= 0) return rawMs;
    final beat = _msPerBeat(widget.bpm);
    final snapped = (rawMs / beat).round() * beat;
    return rawMs * (1.0 - widget.snapStrength) + snapped * widget.snapStrength;
  }

  // Zoom with exact world anchor (no drift)
  void _zoomAroundContentX(double focalContentX, double factor) {
    final oldPps = _pps;
    final target = (oldPps * factor).clamp(widget.minPixelsPerSecond, widget.maxPixelsPerSecond);
    final viewLeftPx = _hScroll.hasClients ? _hScroll.offset : 0.0;
    final focalViewportX = focalContentX - viewLeftPx;
    final worldMs = _pxToMs(viewLeftPx + focalViewportX);

    setState(() => _pps = target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hScroll.hasClients) return;
      final newLeftPx = _msToPx(worldMs) - focalViewportX;
      final contentW = max(_viewportW, _msToPx(_projectEndMs()));
      final maxScroll = max(0.0, contentW - _viewportW);
      _hScroll.jumpTo(newLeftPx.clamp(0.0, maxScroll));
    });
  }

  // Pinch handling (horizontal only)
  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
  }

  void _onPointerMove(PointerMoveEvent e) {
    // Two-finger pinch detection happens in Gesture layer; we let ruler double-tap handle discrete zoom.
    _pointers[e.pointer] = e.localPosition;
  }

  void _onPointerUpOrCancel(int pointer) {
    _pointers.remove(pointer);
  }

  // Overlap detection (using VISIBLE durations)
  bool _wouldOverlap(int movingIndex, double newStartMs, double newEndMs) {
    for (int i = 0; i < widget.clips.length; i++) {
      if (i == movingIndex) continue;
      final c = widget.clips[i];
      final s = widget.getStartMs(c);
      final v = (widget.getTrimEndMs(c) - widget.getTrimStartMs(c)).clamp(1.0, widget.getDurationMs(c));
      final e = s + v;
      if (newStartMs < e && newEndMs > s) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rulerH = 34.0;

    return LayoutBuilder(builder: (context, c) {
      _viewportW = c.maxWidth;
      _viewportH = widget.height;
      final contentW = max(_viewportW, _msToPx(_projectEndMs()));
      final contentH = _contentHeight();

      return Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: (e) => _onPointerUpOrCancel(e.pointer),
        onPointerCancel: (e) => _onPointerUpOrCancel(e.pointer),
        child: SizedBox(
          height: widget.height,
          child: Column(
            children: [
              // Ruler row
              SingleChildScrollView(
                controller: _rulerScroll,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: contentW,
                  height: rulerH,
                  child: _BarsBeatsRuler(
                    width: contentW,
                    height: rulerH,
                    pps: _pps,
                    bpm: widget.bpm,
                    beatsPerBar: widget.beatsPerBar,
                    tickColor: cs.onSurface.withOpacity(0.35),
                    textColor: cs.onSurface.withOpacity(0.9),
                    onTapOrDrag: (localX) {
                      final ms = _pxToMs((_hScroll.hasClients ? _hScroll.offset : 0.0) + localX);
                      widget.onScrubRequested?.call(ms.clamp(0.0, _projectEndMs()));
                    },
                    onDoubleTapZoom: (dx, scale) => _zoomAroundContentX((_hScroll.offset) + dx, 1.6),
                  ),
                ),
              ),

              // Canvas (both directions scrollable)
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (_) => _isClipDragActive,
                  child: SingleChildScrollView(
                    controller: _vScroll,
                    scrollDirection: Axis.vertical,
                    physics: _isClipDragActive ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                    child: SizedBox(
                      height: contentH,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (_) => _isClipDragActive,
                        child: SingleChildScrollView(
                          controller: _hScroll,
                          scrollDirection: Axis.horizontal,
                          physics:
                              _isClipDragActive ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                          child: SizedBox(
                            width: contentW,
                            child: Stack(
                              children: [
                                // Tap area behind everything
                                Positioned.fill(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (_) => widget.onDeselectAll?.call(),
                                    child: CustomPaint(
                                      painter: _BeatGridPainter(
                                        pps: _pps,
                                        bpm: widget.bpm,
                                        beatsPerBar: widget.beatsPerBar,
                                        color: cs.onSurface.withOpacity(0.06),
                                      ),
                                    ),
                                  ),
                                ),

                                // Clips
                                for (int ci = 0; ci < widget.clips.length; ci++) _buildClip(ci, cs),

                                // Playhead
                                if (widget.playheadMs >= 0)
                                  Positioned(
                                    left: _msToPx(widget.playheadMs),
                                    top: 0,
                                    width: 2,
                                    height: contentH,
                                    child: Container(color: cs.secondary),
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
            ],
          ),
        ),
      );
    });
  }

  Widget _buildClip(int ci, ColorScheme cs) {
    final c = widget.clips[ci];

    final startMsModel = widget.getStartMs(c);
    final totalDurMs = widget.getDurationMs(c); // total audio file duration
    final baseTrimS = widget.getTrimStartMs(c);
    final baseTrimE = widget.getTrimEndMs(c);

    // Use PREVIEW trims if present (during gesture), else model values
    final trimStartMs = _trimPreviewStart[ci] ?? baseTrimS;
    final trimEndMs = _trimPreviewEnd[ci] ?? baseTrimE;

    final visibleDurMs = (trimEndMs - trimStartMs).clamp(1.0, totalDurMs);
    final y = widget.getY(c);
    final isSelected = (widget.selectedClipIndex == ci);

    // Drag preview position (never reads model while dragging)
    final isDragging = _dragCi == ci;
    final dxMs = _pxToMs(_dragDxPx * (_fineDrag ? widget.fineDragMultiplier : 1.0));
    final newStartMs = isDragging ? (startMsModel + dxMs).clamp(0.0, double.infinity) : startMsModel;
    final newY = isDragging ? max(0.0, y + _dragDyPx) : y;
    final endMs = newStartMs + visibleDurMs;

    final invalid = isDragging && _wouldOverlap(ci, newStartMs, endMs);

    final palette = _bandLabPalette(cs);
    final color = invalid ? Colors.redAccent.withOpacity(0.35) : palette[ci % palette.length];

    return Positioned(
      left: _msToPx(newStartMs),
      top: newY,
      width: max(4.0, _msToPx(visibleDurMs)),
      height: widget.clipHeight,
      child: _FreeClip<TClip>(
        cs: cs,
        color: color,
        invalidOutline: invalid,
        clip: c,
        isSelected: isSelected,
        getPeaks: widget.getPeaks,
        getTrimStartMs: (_) => trimStartMs,
        getTrimEndMs: (_) => trimEndMs,
        getDurationMs: widget.getDurationMs,
        onTapSelect: () => widget.onSelectClip?.call(ci),

        // DRAG
        onBeginDrag: (_) {
          setState(() {
            _dragCi = ci;
            _dragDxPx = 0;
            _dragDyPx = 0;
            _fineDrag = false;
            _dragOriginStartMs = startMsModel;
            _dragOriginY = y;
            _isClipDragActive = true; // disable scrolls immediately
          });
        },
        onDragUpdate: (deltaDx, deltaDy) {
          setState(() {
            _dragDxPx += deltaDx;
            _dragDyPx += deltaDy;
          });

          final scale = _fineDrag ? widget.fineDragMultiplier : 1.0;
          final msDelta = (_dragDxPx / _pps) * 1000.0 * scale;
          final previewStart = max(0.0, _dragOriginStartMs + msDelta);
          widget.onMoveClipPreview?.call(ci, _snapMs(previewStart), max(0.0, _dragOriginY + _dragDyPx));

          // edge autoscroll horizontally
          final viewLeft = _hScroll.offset;
          final viewRight = viewLeft + _viewportW;
          final clipX = _msToPx(previewStart);
          if (clipX > viewRight - 60) {
            _hScroll.jumpTo(min(_hScroll.position.maxScrollExtent, clipX - _viewportW + 60));
          } else if (clipX < viewLeft + 60) {
            _hScroll.jumpTo(max(0.0, clipX - 60));
          }
        },
        onDragEnd: () {
          final scale = _fineDrag ? widget.fineDragMultiplier : 1.0;
          final msDelta = (_dragDxPx / _pps) * 1000.0 * scale;
          final targetStart = _snapMs(max(0.0, _dragOriginStartMs + msDelta));
          final targetY = max(0.0, _dragOriginY + _dragDyPx);

          if (!_wouldOverlap(ci, targetStart, targetStart + visibleDurMs)) {
            widget.onMoveClipCommit?.call(ci, targetStart, targetY);
          }
          setState(() {
            _dragCi = null;
            _dragDxPx = 0;
            _dragDyPx = 0;
            _isClipDragActive = false;
          });
        },
        onLongPressToggleFine: () => setState(() => _fineDrag = true),

        // TRIM (PREVIEW during drag; COMMIT once on release)
        onBeginTrim: (isStart, s, e) {
          setState(() {
            _isClipDragActive = true; // lock scrolls while trimming
            _trimPreviewStart[ci] = s;
            _trimPreviewEnd[ci] = e;
          });
        },
        onUpdateTrim: (isStart, newS, newE) {
          // hard clamps: 0..totalDurMs and maintain min size
          final total = totalDurMs;
          final minDur = 10.0;
          double s = newS.clamp(0.0, total - minDur);
          double e = newE.clamp(s + minDur, total);

          setState(() {
            _trimPreviewStart[ci] = s;
            _trimPreviewEnd[ci] = e;
          });
          widget.onTrimPreview?.call(ci, s, e);
        },
        onEndTrim: (isStart, _, __) {
          // Commit once using the preview values
          final s = _trimPreviewStart[ci] ?? baseTrimS;
          final e = _trimPreviewEnd[ci] ?? baseTrimE;

          if (isStart) {
            final delta = s - baseTrimS;
            final proposedNewStart = max(0.0, startMsModel + delta);

            // New API
            widget.onTrimCommit?.call(ci, true, s, e, newStartMsIfStartTrim: proposedNewStart);
            // Back-compat
            widget.onTrimClip?.call(ci, s, e, newStartMs: proposedNewStart);
          } else {
            widget.onTrimCommit?.call(ci, false, s, e);
            widget.onTrimClip?.call(ci, s, e);
          }

          setState(() {
            _isClipDragActive = false;
            _trimPreviewStart.remove(ci);
            _trimPreviewEnd.remove(ci);
          });
        },
      ),
    );
  }
}

/// ===== Free clip (draggable in X/Y) =====
class _FreeClip<TClip> extends StatefulWidget {
  final ColorScheme cs;
  final bool isSelected;
  final Color color;
  final bool invalidOutline;
  final TClip clip;
  final List<double>? Function(TClip)? getPeaks;
  final double Function(TClip) getTrimStartMs;
  final double Function(TClip) getTrimEndMs;
  final double Function(TClip) getDurationMs; // total duration

  final VoidCallback onTapSelect;
  final void Function(Offset globalPosInClip)? onBeginDrag;
  final void Function(double dx, double dy)? onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onLongPressToggleFine;

  // Trim lifecycle (preview inside parent; commit onEndTrim)
  final void Function(bool isStart, double trimStartMs, double trimEndMs) onBeginTrim;
  final void Function(bool isStart, double newTrimStartMs, double newTrimEndMs) onUpdateTrim;
  final void Function(bool isStart, double finalTrimStartMs, double finalTrimEndMs) onEndTrim;

  const _FreeClip({
    required this.cs,
    required this.isSelected,
    required this.color,
    required this.invalidOutline,
    required this.clip,
    required this.getPeaks,
    required this.getTrimStartMs,
    required this.getTrimEndMs,
    required this.getDurationMs,
    required this.onTapSelect,
    this.onBeginDrag,
    this.onDragUpdate,
    required this.onDragEnd,
    required this.onLongPressToggleFine,
    required this.onBeginTrim,
    required this.onUpdateTrim,
    required this.onEndTrim,
  });

  @override
  State<_FreeClip<TClip>> createState() => _FreeClipState<TClip>();
}

class _FreeClipState<TClip> extends State<_FreeClip<TClip>> {
  static const double _handleW = 20.0; // easier to grab
  static const double _minTrimMs = 10.0; // cannot trim to zero

  Offset? _lastGlobal;
  bool _isTrimming = false;
  bool _lockDrag = false;

  void _setTrimming(bool v) => setState(() => _isTrimming = v);

  @override
  Widget build(BuildContext context) {
    final peaks = widget.getPeaks?.call(widget.clip) ?? const <double>[];
    final trimS = widget.getTrimStartMs(widget.clip);
    final trimE = widget.getTrimEndMs(widget.clip);
    final totalDurationMs = widget.getDurationMs(widget.clip);

    // DRAG recognizer that wins the arena when needed
    return RawGestureDetector(
      gestures: {
        _AlwaysWinPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<_AlwaysWinPanGestureRecognizer>(
          () => _AlwaysWinPanGestureRecognizer(),
          (g) {
            g
              ..onDown = (_) {/* reserve if needed */}
              ..onStart = (d) {
                if (_lockDrag || !widget.isSelected) return;
                _lastGlobal = d.globalPosition;
                widget.onBeginDrag?.call(d.globalPosition);
                final parent = context.findAncestorStateOfType<_AudioCanvasTimelineState>();
                parent?._isClipDragActive = true;
              }
              ..onUpdate = (d) {
                if (_lockDrag || !widget.isSelected || _lastGlobal == null) return;
                final dx = d.globalPosition.dx - _lastGlobal!.dx;
                final dy = d.globalPosition.dy - _lastGlobal!.dy;
                _lastGlobal = d.globalPosition;
                widget.onDragUpdate?.call(dx, dy);
              }
              ..onEnd = (_) {
                if (_lockDrag || !widget.isSelected) return;
                widget.onDragEnd();
                final parent = context.findAncestorStateOfType<_AudioCanvasTimelineState>();
                parent?._isClipDragActive = false;
              };
          },
        ),
      },
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTapSelect,
        onLongPressStart: (_) => widget.onLongPressToggleFine(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: _isTrimming ? (Matrix4.identity()..scale(1.03)) : Matrix4.identity(),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected ? Colors.white : widget.cs.outlineVariant.withOpacity(0.45),
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                        color: Colors.white.withOpacity(0.2),
                        blurRadius: 10,
                        spreadRadius: 2,
                        offset: const Offset(0, 2)),
                    BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 4)),
                  ]
                : [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // waveform
              Positioned.fill(
                child: CustomPaint(
                  painter: _WavePainter(
                    samples: peaks.isEmpty ? _placeholderPeaks(800) : peaks,
                    color: widget.cs.onSurface.withOpacity(0.92),
                  ),
                ),
              ),
              // trim handles (selected only)
              if (widget.isSelected)
                Positioned.fill(
                  child: Row(
                    children: [
                      // LEFT
                      _TrimHandle(
                        side: AxisDirection.left,
                        width: _handleW,
                        onStart: () {
                          widget.onBeginTrim(true, trimS, trimE);
                          _setTrimming(true);
                          _lockDrag = true;
                        },
                        onDrag: (dx) {
                          final w = context.size?.width ?? 1;
                          final visible = (trimE - trimS).clamp(_minTrimMs, totalDurationMs);
                          final msPerPx = visible / w;
                          double newS = (trimS + dx * msPerPx).clamp(0.0, trimE - _minTrimMs);
                          widget.onUpdateTrim(true, newS, trimE); // preview only
                        },
                        onEnd: (finalS, finalE) {
                          _setTrimming(false);
                          _lockDrag = false;
                          widget.onEndTrim(true, finalS, finalE); // commit up-chain
                        },
                        glowOnTouch: true,
                      ),
                      const Expanded(child: SizedBox()),
                      // RIGHT
                      _TrimHandle(
                        side: AxisDirection.right,
                        width: _handleW,
                        onStart: () {
                          widget.onBeginTrim(false, trimS, trimE);
                          _setTrimming(true);
                          _lockDrag = true;
                        },
                        onDrag: (dx) {
                          final w = context.size?.width ?? 1;
                          final visible = (trimE - trimS).clamp(_minTrimMs, totalDurationMs);
                          final msPerPx = visible / w;
                          double newE = (trimE + dx * msPerPx).clamp(trimS + _minTrimMs, totalDurationMs);
                          widget.onUpdateTrim(false, trimS, newE); // preview only
                        },
                        onEnd: (finalS, finalE) {
                          _setTrimming(false);
                          _lockDrag = false;
                          widget.onEndTrim(false, finalS, finalE); // commit up-chain
                        },
                        glowOnTouch: true,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrimHandle extends StatefulWidget {
  final AxisDirection side;
  final double width;
  final void Function(double dx) onDrag;
  final VoidCallback onStart;
  final void Function(double finalTrimStartMs, double finalTrimEndMs) onEnd;
  final bool glowOnTouch;

  const _TrimHandle({
    required this.side,
    required this.width,
    required this.onDrag,
    required this.onStart,
    required this.onEnd,
    this.glowOnTouch = true,
  });

  @override
  State<_TrimHandle> createState() => _TrimHandleState();
}

class _TrimHandleState extends State<_TrimHandle> {
  Offset? _last;
  bool _isActive = false;

  @override
  Widget build(BuildContext context) {
    final bool isLeft = widget.side == AxisDirection.left;
    final accent = Theme.of(context).colorScheme.secondary;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanDown: (_) {
        setState(() => _isActive = true);
        final parent = context.findAncestorStateOfType<_FreeClipState>();
        parent?._setTrimming(true);
        parent?._lockDrag = true;
      },
      onPanStart: (d) {
        _last = d.globalPosition;
        widget.onStart();
      },
      onPanUpdate: (d) {
        final dx = d.globalPosition.dx - (_last ?? d.globalPosition).dx;
        _last = d.globalPosition;
        widget.onDrag(dx);
      },
      onPanEnd: (_) {
        setState(() => _isActive = false);
        // End values are owned by parent (preview maps). We just signal end.
        // Parent commits via onEndTrim.
        final parent = context.findAncestorStateOfType<_FreeClipState>();
        parent?._setTrimming(false);
        parent?._lockDrag = false;

        // We don't know final values here; parent passes them when calling onEndTrim.
        widget.onEnd(0, 0); // ignored in parent; kept for signature consistency.
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: widget.width,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isLeft
                ? [
                    (_isActive && widget.glowOnTouch ? accent.withOpacity(0.45) : Colors.white.withOpacity(0.15)),
                    Colors.transparent
                  ]
                : [
                    Colors.transparent,
                    (_isActive && widget.glowOnTouch ? accent.withOpacity(0.45) : Colors.white.withOpacity(0.15))
                  ],
          ),
          boxShadow: _isActive && widget.glowOnTouch
              ? [
                  BoxShadow(
                      color: accent.withOpacity(0.55),
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: Offset(isLeft ? 2 : -2, 0))
                ]
              : [
                  BoxShadow(
                      color: Colors.white.withOpacity(0.15),
                      blurRadius: 6,
                      spreadRadius: 2,
                      offset: Offset(isLeft ? 2 : -2, 0))
                ],
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 3,
            height: double.infinity,
            decoration: BoxDecoration(
              color: _isActive ? accent : Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

// Ensures our clip drags always win over ScrollView drags
class _AlwaysWinPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);
  }
}

/// ===== Ruler & Grid Painters =====
class _BarsBeatsRuler extends StatelessWidget {
  final double width;
  final double height;
  final double pps;
  final double bpm;
  final int beatsPerBar;
  final Color tickColor;
  final Color textColor;
  final void Function(double localX)? onTapOrDrag;
  final void Function(double dx, double scale)? onDoubleTapZoom;
  const _BarsBeatsRuler(
      {required this.width,
      required this.height,
      required this.pps,
      required this.bpm,
      required this.beatsPerBar,
      required this.tickColor,
      required this.textColor,
      this.onTapOrDrag,
      this.onDoubleTapZoom});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => onTapOrDrag?.call(d.localPosition.dx),
      onPanUpdate: (d) => onTapOrDrag?.call(d.localPosition.dx),
      onDoubleTapDown: (d) => onDoubleTapZoom?.call(d.localPosition.dx, 1.6),
      child: CustomPaint(
        size: Size(width, height),
        painter: _BarsBeatsPainter(
          pps: pps,
          bpm: bpm,
          beatsPerBar: beatsPerBar,
          tickColor: tickColor,
          textColor: textColor,
        ),
      ),
    );
  }
}

class _BarsBeatsPainter extends CustomPainter {
  final double pps;
  final double bpm;
  final int beatsPerBar;
  final Color tickColor;
  final Color textColor;
  _BarsBeatsPainter(
      {required this.pps,
      required this.bpm,
      required this.beatsPerBar,
      required this.tickColor,
      required this.textColor});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = tickColor
      ..strokeWidth = 1;
    final tp = TextPainter(textAlign: TextAlign.left, textDirection: TextDirection.ltr);
    final msPerBeat = 60000.0 / (bpm <= 0 ? 120.0 : bpm);
    final pxPerBeat = (msPerBeat / 1000.0) * pps;
    int subdivision = 4;
    if (pxPerBeat < 30)
      subdivision = 1;
    else if (pxPerBeat < 60) subdivision = 2;
    final pxPerSub = pxPerBeat / subdivision;
    for (double x = 0; x <= size.width; x += pxPerSub) {
      final subIndex = (x / pxPerSub).round();
      final isBeat = subIndex % subdivision == 0;
      final beatIndex = (x / pxPerBeat).round();
      final isBar = beatIndex % beatsPerBar == 0 && isBeat;
      final h = isBar ? 16.0 : (isBeat ? 12.0 : 6.0);
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), p);
      if (isBar) {
        final barNum = (beatIndex / beatsPerBar).round() + 1;
        tp.text = TextSpan(text: '$barNum', style: TextStyle(fontSize: 10, color: textColor));
        tp.layout();
        tp.paint(canvas, Offset(x + 4, size.height - 20));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarsBeatsPainter old) =>
      old.pps != pps ||
      old.bpm != bpm ||
      old.beatsPerBar != beatsPerBar ||
      old.tickColor != tickColor ||
      old.textColor != textColor;
}

class _BeatGridPainter extends CustomPainter {
  final double pps;
  final double bpm;
  final int beatsPerBar;
  final Color color;
  _BeatGridPainter({required this.pps, required this.bpm, required this.beatsPerBar, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    final msPerBeat = 60000.0 / (bpm <= 0 ? 120.0 : bpm);
    final pxPerBeat = (msPerBeat / 1000.0) * pps;
    if (pxPerBeat <= 0) return;
    for (double x = 0; x <= size.width; x += pxPerBeat) {
      final isBar = ((x / pxPerBeat).round() % beatsPerBar == 0);
      final a = isBar ? 0.16 : 0.08;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p..color = color.withOpacity(a));
    }
  }

  @override
  bool shouldRepaint(covariant _BeatGridPainter old) =>
      old.pps != pps || old.bpm != bpm || old.beatsPerBar != beatsPerBar || old.color != color;
}

/// ===== Waveform Painter =====
class _WavePainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  _WavePainter({required this.samples, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;
    final mid = size.height / 2;
    final path = Path();
    double sampleAt(double t) {
      final x = t * (samples.length - 1);
      final i = x.floor();
      final frac = x - i;
      double s(int idx) => samples[idx.clamp(0, samples.length - 1)];
      final s0 = s(i - 1), s1 = s(i), s2 = s(i + 1), s3 = s(i + 2);
      final m1 = 0.5 * (s2 - s0);
      final m2 = 0.5 * (s3 - s1);
      final a = 2 * pow(frac, 3) - 3 * pow(frac, 2) + 1;
      final b = -2 * pow(frac, 3) + 3 * pow(frac, 2);
      final c = pow(frac, 3) - 2 * pow(frac, 2) + frac;
      final d = pow(frac, 3) - pow(frac, 2);
      return (a * s1 + b * s2 + c * m1 + d * m2).toDouble();
    }

    final steps = max(1, size.width.toInt());
    for (int x = 0; x <= steps; x++) {
      final t = x / steps;
      final v = sampleAt(t);
      final y = mid - v * (size.height * 0.45);
      if (x == 0)
        path.moveTo(0, y);
      else
        path.lineTo(x.toDouble(), y);
    }
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..isAntiAlias = true;
    final fill = Paint()
      ..shader = LinearGradient(
              colors: [color.withOpacity(0.22), color.withOpacity(0.06)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter)
          .createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    final fillPath = Path.from(path)
      ..lineTo(size.width, mid)
      ..lineTo(0, mid)
      ..close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => !identical(old.samples, samples) || old.color != color;
}

/// ===== Palette & placeholders =====
List<Color> _bandLabPalette(ColorScheme cs) {
  return [
    const Color(0xFFEB5757),
    const Color(0xFF27AE60),
    const Color(0xFF2D9CDB),
    const Color(0xFFF2994A),
    const Color(0xFF9B51E0),
    const Color(0xFF56CCF2),
    const Color(0xFFFF66C4)
  ].map((c) => Color.alphaBlend(c.withOpacity(0.65), cs.surface)).toList();
}

List<double> _placeholderPeaks(int n) {
  final r = Random(12);
  return List<double>.generate(n, (i) {
    final base = sin(i / 9) * 0.7 + sin(i / 21) * 0.3;
    final noise = (r.nextDouble() - 0.5) * 0.18;
    return (base + noise).clamp(-1.0, 1.0);
  });
}






*/
