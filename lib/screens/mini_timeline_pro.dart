// lib/mini_timeline_pro.dart
import 'dart:io';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// MiniTimelinePro (with gutter + exact playhead centering)
class MiniTimelinePro<TVideo, TAudio> extends StatefulWidget {
  // Data
  final List<TVideo> video;
  final List<List<TAudio>> audio;

  // Extractors
  final double Function(TVideo) getVideoStartMs;
  final double Function(TVideo) getVideoDurationMs;
  final String Function(TVideo) getVideoThumbPath;
  final String Function(TVideo)? getVideoLabel;

  final double Function(TAudio) getAudioStartMs;
  final double Function(TAudio) getAudioDurationMs;
  final List<double>? Function(TAudio)? getAudioPeaks;

  // Interaction
  final double playheadMs; // pass -1 to hide
  final void Function(double ms)? onScrubRequested;

  // Layout/behavior
  final double initialPixelsPerSecond;
  final double minPixelsPerSecond;
  final double maxPixelsPerSecond;
  final double height;
  final double rowGap;
  final double trackHPad;
  final ScrollController? scrollController;

  // Behavior flags
  final bool autoFollow;
  final double followEdgePadding;
  final bool fixedPlayhead;
  final double playheadAnchorFraction;

  const MiniTimelinePro({
    super.key,
    // data
    required this.video,
    required this.audio,
    // getters
    required this.getVideoStartMs,
    required this.getVideoDurationMs,
    required this.getVideoThumbPath,
    required this.getAudioStartMs,
    required this.getAudioDurationMs,
    this.getVideoLabel,
    this.getAudioPeaks,
    // interaction
    this.playheadMs = -1,
    this.onScrubRequested,
    // layout/behavior
    this.initialPixelsPerSecond = 140,
    this.minPixelsPerSecond = 10, // allow much deeper zoom-out
    this.maxPixelsPerSecond = 640, // a bit more zoom-in headroom
    this.height = 280,
    this.rowGap = 10,
    this.trackHPad = 12,
    this.scrollController,
    // flags
    this.autoFollow = true,
    this.followEdgePadding = 60,
    this.fixedPlayhead = true, // continuous follow by default
    this.playheadAnchorFraction = 0.5, // centered
  });

  @override
  State<MiniTimelinePro<TVideo, TAudio>> createState() => _MiniTimelineProState<TVideo, TAudio>();
}

class _MiniTimelineProState<TVideo, TAudio> extends State<MiniTimelinePro<TVideo, TAudio>> {
  // zoom
  late double _pps;
  bool _gestureZooming = false;

  // internal controller fallback (if none provided)
  late final ScrollController _ownScroll;
  ScrollController get _scroll => widget.scrollController ?? _ownScroll;

  // Right pad (ms) used to give some breathing room for scroll/playhead
  static const double _rightPadMs = 1000.0;

  // Pointer-based pinch state (Listener)
  final Map<int, Offset> _activePointers = {};
  double? _pinchInitialPps;
  double? _pinchInitialDistance; // px between first two pointers
  double? _pinchInitialViewLeft; // scroll offset at pinch start
  double? _pinchFocalViewportX; // focal x within viewport at pinch start
  double? _pinchFocalMs; // focal time at pinch start

  @override
  void initState() {
    super.initState();
    _pps = widget.initialPixelsPerSecond;
    _ownScroll = ScrollController();
  }

  @override
  void dispose() {
    _ownScroll.dispose();
    super.dispose();
  }

  double _msToPx(double ms) => ms / 1000 * _pps;
  double _pxToMs(double px) => px / _pps * 1000;

  double _contentMs() {
    double ms = 0;
    for (final v in widget.video) {
      ms = max(ms, widget.getVideoStartMs(v) + widget.getVideoDurationMs(v));
    }
    for (final track in widget.audio) {
      for (final a in track) {
        ms = max(ms, widget.getAudioStartMs(a) + widget.getAudioDurationMs(a));
      }
    }
    return ms + _rightPadMs; // right pad
  }

  double _contentMsWithoutPad() => max(0.0, _contentMs() - _rightPadMs);

  // Keep playhead visible / pinned when it changes
  @override
  void didUpdateWidget(covariant MiniTimelinePro<TVideo, TAudio> old) {
    super.didUpdateWidget(old);
    if (!mounted) return;
    if (widget.playheadMs != old.playheadMs) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _followPlayheadNow(_lastViewportW);
      });
    }
  }

  // === Layout-measured viewport width (for exact centering) ===
  double _lastViewportW = 0;

  // Compute gutter (left spacer) based on current viewport width and fixedPlayhead
  double _gutterPxFor(double viewportW) => widget.fixedPlayhead ? viewportW * widget.playheadAnchorFraction : 0.0;

  // Follow behavior (uses gutter-aware coordinates)
  void _followPlayheadNow(double viewportW) {
    if (!_scroll.hasClients || viewportW <= 0 || widget.playheadMs < 0) return;

    final gutter = _gutterPxFor(viewportW);

    // NEW: ensure scroll extent always equals full content length in px (even zoomed out)
    final contentLenPxNoPad = _msToPx(_contentMsWithoutPad());
    final contentLenPxWithPad = _msToPx(_contentMs());
    final contentW = max(viewportW + contentLenPxWithPad, viewportW);

    final playXWithGutter = gutter + _msToPx(widget.playheadMs);

    if (widget.fixedPlayhead) {
      // Pin playhead to anchor position (continuous follow)
      final anchorX = viewportW * widget.playheadAnchorFraction;
      double target = playXWithGutter - anchorX; // this equals msToPx(playhead) when fixed

      // clamp target to both scroll extent AND real content end (no pad)
      final maxScrollExtent = max(0.0, contentW - viewportW);
      final maxFollow = contentLenPxNoPad;
      target = target.clamp(0.0, min(maxScrollExtent, maxFollow));

      _scroll.jumpTo(target); // immediate for smooth ticking
      return;
    }

    if (!widget.autoFollow) return;

    // Edge-follow nudge
    final left = _scroll.offset;
    final right = left + viewportW;
    final edge = widget.followEdgePadding;
    double target = left;

    if (playXWithGutter > right - edge) {
      target = playXWithGutter + edge - viewportW;
    } else if (playXWithGutter < left + edge) {
      target = max(0, playXWithGutter - edge);
    } else {
      return;
    }

    final maxScrollExtent = max(0.0, contentW - viewportW);
    final maxFollow = contentLenPxNoPad;
    target = target.clamp(0.0, min(maxScrollExtent, maxFollow));

    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  // Zoom keeping the content point under the fingers stable (gutter-aware).
  void _zoomAround(double focalContentX, double factor, double viewportW) {
    final old = _pps;
    final next = (_pps * factor).clamp(widget.minPixelsPerSecond, widget.maxPixelsPerSecond);
    if (next == old) return;

    final gutter = _gutterPxFor(viewportW);

    if (_scroll.hasClients) {
      final viewLeft = _scroll.offset;
      final focalViewportX = focalContentX - viewLeft;
      final focalMs = _pxToMs(max(0.0, focalContentX - gutter));

      setState(() => _pps = next);

      // adjust scroll AFTER new layout
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;

        // Recompute content width with our "always scrollable" rule
        final contentLenPxNoPad = _msToPx(_contentMsWithoutPad());
        final contentLenPxWithPad = _msToPx(_contentMs());
        final contentW = max(viewportW + contentLenPxWithPad, viewportW);

        final newContentXWithGutter = gutter + _msToPx(focalMs);
        var newViewLeft = max(0.0, newContentXWithGutter - focalViewportX);

        final maxScrollExtent = max(0.0, contentW - viewportW);
        final maxFollow = contentLenPxNoPad;
        newViewLeft = newViewLeft.clamp(0.0, min(maxScrollExtent, maxFollow));

        _scroll.jumpTo(newViewLeft);
        _followPlayheadNow(viewportW);
      });
    } else {
      // Not yet attached: just set zoom, try follow later
      setState(() => _pps = next);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _followPlayheadNow(viewportW);
      });
    }
  }

  // ===== Listener-based pinch/zoom helpers =====

  Offset _averageLocalPosition() {
    if (_activePointers.isEmpty) return Offset.zero;
    if (_activePointers.length == 1) {
      return _activePointers.values.first;
    }
    final it = _activePointers.values.iterator;
    it..moveNext();
    final a = it.current;
    it..moveNext();
    final b = it.current;
    return Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  }

  double _currentPointerSpan() {
    if (_activePointers.length < 2) return 0.0;
    final it = _activePointers.values.iterator;
    it..moveNext();
    final a = it.current;
    it..moveNext();
    final b = it.current;
    return (a - b).distance.abs();
  }

  void _startPinch() {
    if (_activePointers.length < 2) return;
    _gestureZooming = true;
    _pinchInitialPps = _pps;
    _pinchInitialViewLeft = _scroll.hasClients ? _scroll.offset : 0.0;

    final focalViewport = _averageLocalPosition();
    _pinchFocalViewportX = focalViewport.dx;

    final gutter = _gutterPxFor(_lastViewportW);
    final contentX = (_pinchInitialViewLeft ?? 0.0) + (_pinchFocalViewportX ?? 0.0);
    _pinchFocalMs = _pxToMs(max(0.0, contentX - gutter));

    _pinchInitialDistance = _currentPointerSpan();
  }

  void _updatePinch() {
    if (_activePointers.length < 2 ||
        _pinchInitialPps == null ||
        _pinchInitialDistance == null ||
        _pinchInitialViewLeft == null ||
        _pinchFocalViewportX == null ||
        _pinchFocalMs == null) {
      return;
    }

    final newSpan = _currentPointerSpan();
    if (newSpan <= 0) return;

    // More sensitive factor bounds
    double factor = newSpan / (_pinchInitialDistance!.clamp(1.0, double.infinity));
    factor = factor.clamp(0.6, 1.6);

    final targetPps = (_pinchInitialPps! * factor).clamp(widget.minPixelsPerSecond, widget.maxPixelsPerSecond);

    if (targetPps == _pps) return;
    setState(() => _pps = targetPps);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;

      final gutter = _gutterPxFor(_lastViewportW);
      final contentLenPxNoPad = _msToPx(_contentMsWithoutPad());
      final contentLenPxWithPad = _msToPx(_contentMs());
      final contentW = max(_lastViewportW + contentLenPxWithPad, _lastViewportW);

      final newContentXWithGutter = gutter + _msToPx(_pinchFocalMs!);
      var newViewLeft = max(0.0, newContentXWithGutter - _pinchFocalViewportX!);

      final maxScrollExtent = max(0.0, contentW - _lastViewportW);
      final maxFollow = contentLenPxNoPad;
      newViewLeft = newViewLeft.clamp(0.0, min(maxScrollExtent, maxFollow));

      _scroll.jumpTo(newViewLeft);
      _followPlayheadNow(_lastViewportW);
    });
  }

  void _endPinchIfNeeded() {
    if (_activePointers.length < 2) {
      _gestureZooming = false;
      _pinchInitialPps = null;
      _pinchInitialDistance = null;
      _pinchInitialViewLeft = null;
      _pinchFocalViewportX = null;
      _pinchFocalMs = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rulerH = 28.0;
    final videoRowH = 84.0;
    final audioRowH = 84.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportW = constraints.maxWidth;
        _lastViewportW = viewportW;

        final gutter = _gutterPxFor(viewportW);

        // NEW: make child width always viewport + content length (with pad)
        final contentLenPxWithPad = _msToPx(_contentMs());
        final contentW = max(viewportW + contentLenPxWithPad, viewportW);

        // Compute playhead X in viewport coordinates
        double playheadViewportX = 0;
        if (widget.playheadMs >= 0) {
          if (widget.fixedPlayhead) {
            playheadViewportX = viewportW * widget.playheadAnchorFraction;
          } else {
            final contentXWithGutter = gutter + _msToPx(widget.playheadMs);
            final left = _scroll.hasClients ? _scroll.offset : 0.0;
            playheadViewportX = contentXWithGutter - left;
          }
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent e) {
            _activePointers[e.pointer] = e.localPosition;
            if (_activePointers.length == 2) _startPinch();
          },
          onPointerMove: (PointerMoveEvent e) {
            _activePointers[e.pointer] = e.localPosition;
            if (_activePointers.length >= 2) _updatePinch();
          },
          onPointerUp: (PointerUpEvent e) {
            _activePointers.remove(e.pointer);
            _endPinchIfNeeded();
          },
          onPointerCancel: (PointerCancelEvent e) {
            _activePointers.remove(e.pointer);
            _endPinchIfNeeded();
          },
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                // Scrollable content
                SingleChildScrollView(
                  controller: _scroll,
                  physics: _gestureZooming ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentW,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ----- Ruler -----
                        _Ruler(
                          width: contentW,
                          height: rulerH,
                          pixelsPerSecond: _pps,
                          gutter: gutter,
                          onTapOrDrag: (localX) {
                            final contentX = localX + (_scroll.hasClients ? _scroll.offset : 0.0);
                            var ms = _pxToMs(max(0.0, contentX - gutter));
                            final maxSeekMs = _contentMsWithoutPad();
                            ms = ms.clamp(0.0, maxSeekMs);

                            widget.onScrubRequested?.call(ms);
                            _followPlayheadNow(viewportW);
                          },
                        ),

                        // ----- Tracks -----
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: widget.trackHPad),
                          child: Column(
                            children: [
                              _VideoRow<TVideo>(
                                height: videoRowH,
                                cs: cs,
                                segments: widget.video,
                                msToPx: (ms) => gutter - widget.trackHPad + _msToPx(ms),
                                getStartMs: widget.getVideoStartMs,
                                getDurationMs: widget.getVideoDurationMs,
                                getThumbPath: widget.getVideoThumbPath,
                                getLabel: widget.getVideoLabel,
                              ),
                              SizedBox(height: widget.rowGap),
                              for (int i = 0; i < widget.audio.length; i++) ...[
                                _AudioRow<TAudio>(
                                  height: audioRowH,
                                  cs: cs,
                                  segments: widget.audio[i],
                                  msToPx: (ms) => gutter - widget.trackHPad + _msToPx(ms),
                                  getStartMs: widget.getAudioStartMs,
                                  getDurationMs: widget.getAudioDurationMs,
                                  getPeaks: widget.getAudioPeaks,
                                ),
                                if (i != widget.audio.length - 1) SizedBox(height: widget.rowGap),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Playhead overlay (viewport coordinates)
                if (widget.playheadMs >= 0)
                  IgnorePointer(
                    child: Padding(
                      padding: EdgeInsets.only(top: rulerH),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: _PlayheadLine(
                          height: widget.height - rulerH,
                          color: cs.secondary,
                          xPx: playheadViewportX,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ---------- Ruler ----------
class _Ruler extends StatelessWidget {
  final double width;
  final double height;
  final double pixelsPerSecond;
  final double gutter;
  final void Function(double localX)? onTapOrDrag;
  const _Ruler({
    required this.width,
    required this.height,
    required this.pixelsPerSecond,
    required this.gutter,
    this.onTapOrDrag,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onTapOrDrag?.call(d.localPosition.dx),
        onPanUpdate: (d) => onTapOrDrag?.call(d.localPosition.dx),
        child: CustomPaint(
          size: Size(width, height),
          painter: _RulerPainter(
            pps: pixelsPerSecond,
            gutter: gutter,
            tickColor: cs.onSurface.withOpacity(0.35),
            textColor: cs.onSurface.withOpacity(0.9),
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final double pps;
  final double gutter;
  final Color tickColor;
  final Color textColor;
  _RulerPainter({
    required this.pps,
    required this.gutter,
    required this.tickColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = tickColor
      ..strokeWidth = 1;
    final tp = TextPainter(textAlign: TextAlign.left, textDirection: TextDirection.ltr);

    // Adaptive grid
    final secPx = pps;
    double major = secPx; // 1s
    double minor = secPx / 4; // 250ms
    if (pps < 70) {
      major = secPx * 2;
      minor = secPx / 2;
    }
    if (pps > 240) {
      major = secPx / 2;
      minor = secPx / 8;
    }

    for (double x = gutter; x <= size.width; x += minor) {
      final isMajor = ((x - gutter) / major - ((x - gutter) / major).round()).abs() < 0.001;
      final h = isMajor ? 14.0 : 7.0;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), p);
      if (isMajor) {
        final sec = ((x - gutter) / secPx).toStringAsFixed(1);
        tp.text = TextSpan(text: '${sec}s', style: TextStyle(fontSize: 10, color: textColor));
        tp.layout();
        tp.paint(canvas, Offset(x + 3, size.height - 18));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.pps != pps || old.gutter != gutter || old.tickColor != tickColor || old.textColor != textColor;
}

/// ---------- Tracks ----------
class _VideoRow<T> extends StatelessWidget {
  final double height;
  final ColorScheme cs;
  final List<T> segments;
  final double Function(double) msToPx; // gutter-aware (+ corrected for trackHPad)
  final double Function(T) getStartMs;
  final double Function(T) getDurationMs;
  final String Function(T) getThumbPath;
  final String Function(T)? getLabel;

  const _VideoRow({
    required this.height,
    required this.cs,
    required this.segments,
    required this.msToPx,
    required this.getStartMs,
    required this.getDurationMs,
    required this.getThumbPath,
    this.getLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          for (final s in segments)
            Positioned(
              left: msToPx(getStartMs(s)),
              top: 6,
              width: max(4.0, msToPx(getDurationMs(s)) - msToPx(0)),
              height: height - 12,
              child: _TiledThumbBlock(
                thumbPath: getThumbPath(s),
                label: getLabel?.call(s),
                cs: cs,
              ),
            ),
        ],
      ),
    );
  }
}

class _TiledThumbBlock extends StatelessWidget {
  final String thumbPath;
  final String? label;
  final ColorScheme cs;
  const _TiledThumbBlock({required this.thumbPath, required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.08),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: FileImage(File(thumbPath)),
                  fit: BoxFit.fitHeight,
                  alignment: Alignment.centerLeft,
                  repeat: ImageRepeat.repeatX,
                ),
              ),
            ),
          ),
          if (label != null)
            Positioned(
              left: 8,
              top: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(label!, style: TextStyle(fontSize: 11, color: cs.onSurface)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AudioRow<T> extends StatelessWidget {
  final double height;
  final ColorScheme cs;
  final List<T> segments;
  final double Function(double) msToPx; // gutter-aware (+ corrected for trackHPad)
  final double Function(T) getStartMs;
  final double Function(T) getDurationMs;
  final List<double>? Function(T)? getPeaks;

  const _AudioRow({
    required this.height,
    required this.cs,
    required this.segments,
    required this.msToPx,
    required this.getStartMs,
    required this.getDurationMs,
    this.getPeaks,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          for (final s in segments)
            Positioned(
              left: msToPx(getStartMs(s)),
              top: 6,
              width: max(4.0, msToPx(getDurationMs(s)) - msToPx(0)),
              height: height - 12,
              child: _AudioBlock(
                peaks: getPeaks?.call(s),
                cs: cs,
              ),
            ),
        ],
      ),
    );
  }
}

class _AudioBlock extends StatelessWidget {
  final List<double>? peaks; // normalized [-1..1]
  final ColorScheme cs;
  const _AudioBlock({required this.peaks, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.08),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _WavePainter(
          (peaks == null || peaks!.isEmpty) ? _placeholderPeaks(400) : peaks!,
          color: cs.onSurface.withOpacity(0.75),
        ),
      ),
    );
  }
}

/// ---------- Playhead ----------
class _PlayheadLine extends StatelessWidget {
  final double height;
  final Color color;
  final double xPx; // viewport X (not content X)
  const _PlayheadLine({required this.height, required this.color, required this.xPx});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(xPx, 0),
      child: Container(
        width: 2,
        height: height,
        color: color,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: 14,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      ),
    );
  }
}

/// ---------- Painters ----------
class _WavePainter extends CustomPainter {
  final List<double> samples; // [-1..1], any length
  final Color color;
  _WavePainter(this.samples, {required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0) return;
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    final mid = size.height / 2;
    final last = samples.length - 1;

    for (int x = 0; x < size.width; x++) {
      final t = x / max(1.0, size.width - 1); // 0..1
      final f = t * last; // fractional index
      final i0 = f.floor();
      final i1 = min(last, i0 + 1);
      final lerp = f - i0;
      final v = samples[i0] * (1 - lerp) + samples[i1] * lerp;
      final h = (v.abs() * (size.height * 0.9));
      canvas.drawLine(Offset(x.toDouble(), mid - h / 2), Offset(x.toDouble(), mid + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => !identical(old.samples, samples) || old.color != color;
}

List<double> _placeholderPeaks(int n) {
  final r = Random(12);
  return List<double>.generate(n, (i) {
    final base = sin(i / 9) * 0.7 + sin(i / 21) * 0.3;
    final noise = (r.nextDouble() - 0.5) * 0.18;
    return (base + noise).clamp(-1.0, 1.0);
  });
}



// OLD UI SCRUBBER LOGIC, MAYBE USE THIS IF NEEDED
// Expanded(
//   child: _audioOnly
//       ? Slider(
//           value: _globalAudioClock.inMilliseconds
//               .toDouble()
//               .clamp(0.0, overallDuration.inMilliseconds.toDouble()),
//           min: 0,
//           max: overallDuration.inMilliseconds.toDouble(),
//           onChangeStart: (value) async {
//             _audioAutomationTimer?.cancel();
//             for (var track in _audioTracks) {
//               // await track.player.pause();
//               track.audioStarted = false; // Reset flag on pause so that resume triggers play.
//             }
//             JuceAudioEngine.pause();
//             _audioEditorStateSetter!(() {
//               _isPlaying = false;
//             });
//           },
//           onChanged: (value) {
//             final newPos = Duration(milliseconds: value.toInt());
//             // Update the UI immediately:
//             _audioEditorStateSetter!(() {
//               _globalAudioClock = newPos;
//             });
//             // For each track, calculate the effective seek position:
//             for (int i = 0; i < _audioTracks.length; i++) {
//               final track = _audioTracks[i];
//               final offsetDuration = Duration(milliseconds: (track.offset * 1000).round());
//               Duration effectivePos;
//               if (newPos < offsetDuration) {
//                 effectivePos = track.trimStart;
//               } else {
//                 effectivePos = track.trimStart + (newPos - offsetDuration);
//                 if (effectivePos > track.trimEnd) {
//                   effectivePos = track.trimEnd;
//                 }
//               }
//               // Kick off the seek without awaiting:
//               // track.player.seek(effectivePos);
//               JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
//             }
//             // Update automation (you can call this synchronously or asynchronously).
//             _updateAudioAutomation(newPos);
//           },
//           onChangeEnd: (value) async {
//             _audioAutomationTimer?.cancel();
//             for (var track in _audioTracks) {
//               // await track.player.pause();
//               track.audioStarted = false; // Reset flag on pause so that resume triggers play.
//             }
//             JuceAudioEngine.pause();
//             _audioEditorStateSetter!(() {
//               _isPlaying = false;
//             });
//           },
//         )
//       : Slider(
//           value: currentValue,
//           min: 0,
//           max: maxValue,
//           onChangeStart: (value) {
//             for (var track in _audioTracks) {
//               track.audioStartTimer?.cancel();
//             }
//             _pausePlayback();
//             _stopTicker();
//             setState(() {
//               _isScrubbing = true;
//               _scrubPosition = Duration(milliseconds: value.toInt());
//             });
//           },
//           onChanged: (value) {
//             setState(() {
//               _scrubPosition = Duration(milliseconds: value.toInt());
//             });
//           },
//           onChangeEnd: (value) async {
//             final newPosition = Duration(milliseconds: value.toInt());
//             setState(() {
//               _isScrubbing = false;
//               _videoPosition = newPosition;
//               _scrubPosition = newPosition;
//             });

//             await seekTo(newPosition);
//             await JuceAudioEngine.seekVideoAudio(newPosition.inMicroseconds / 1e6);

//             for (int i = 0; i < _audioTracks.length; i++) {
//               final track = _audioTracks[i];
//               final effectivePos = _calculateEffectiveAudioPositionForTrack(track, newPosition);

//               await JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
//               setState(() {
//                 track.currentPosition = effectivePos;
//               });
//             }

//             if (_isPlaying) {
//               _resumePlayback();
//               _startTicker();
//             }
//           },
//         ),