import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mixroom/helpers/desktop_editor_prefs.dart';

enum DesktopPanelPreset {
  topHalf,
  bottomHalf,
  leftHalf,
  leftThird,
  rightHalf,
  rightThird,
}

enum _DesktopPanelMenuAction {
  enterFullscreen,
  exitFullscreen,
  topHalf,
  bottomHalf,
  leftHalf,
  leftThird,
  rightHalf,
  rightThird,
  resetDefault,
}

enum _DesktopPanelEdge {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class DesktopPanelShell extends StatefulWidget {
  const DesktopPanelShell({
    super.key,
    required this.availableBounds,
    required this.layout,
    required this.fullscreen,
    required this.onFullscreenChanged,
    required this.onLayoutChanged,
    required this.child,
    this.minWidth = 320,
    this.minHeight = 220,
    this.topContextMenuHeight = 14,
    this.onResetLayout,
  });

  final Rect availableBounds;
  final DesktopEditorWindowLayout layout;
  final bool fullscreen;
  final ValueChanged<bool> onFullscreenChanged;
  final ValueChanged<DesktopEditorWindowLayout> onLayoutChanged;
  final Widget child;
  final double minWidth;
  final double minHeight;
  final double topContextMenuHeight;
  final VoidCallback? onResetLayout;

  @override
  State<DesktopPanelShell> createState() => _DesktopPanelShellState();
}

class _DesktopPanelMenuRow extends StatelessWidget {
  const _DesktopPanelMenuRow({
    required this.label,
    required this.icon,
  });

  final String label;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        icon,
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _DesktopPanelPresetIcon extends StatelessWidget {
  const _DesktopPanelPresetIcon({
    this.preset,
    this.maximize = false,
    this.reset = false,
  });

  final DesktopPanelPreset? preset;
  final bool maximize;
  final bool reset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 18,
      child: CustomPaint(
        painter: _DesktopPanelPresetIconPainter(
          preset: preset,
          maximize: maximize,
          reset: reset,
        ),
      ),
    );
  }
}

class _DesktopPanelPresetIconPainter extends CustomPainter {
  const _DesktopPanelPresetIconPainter({
    required this.preset,
    required this.maximize,
    required this.reset,
  });

  final DesktopPanelPreset? preset;
  final bool maximize;
  final bool reset;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    final framePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final fillPaint = Paint()
      ..color = const Color(0xFF7DD5FF).withValues(alpha: 0.82)
      ..style = PaintingStyle.fill;
    final faintPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(outer, faintPaint);

    final inset = 2.0;
    final inner = Rect.fromLTWH(
      inset,
      inset,
      size.width - (inset * 2),
      size.height - (inset * 2),
    );
    final fillRect = reset
        ? Rect.fromCenter(
            center: inner.center,
            width: inner.width * 0.58,
            height: inner.height * 0.58,
          )
        : _presetFillRect(inner);

    canvas.drawRRect(
      RRect.fromRectAndRadius(fillRect, const Radius.circular(2.5)),
      fillPaint,
    );

    if (reset) {
      final arrowPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.82)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final arrowPath = Path()
        ..moveTo(inner.left + 3, inner.top + 5)
        ..quadraticBezierTo(
          inner.center.dx,
          inner.top - 2,
          inner.right - 4,
          inner.top + 5,
        );
      canvas.drawPath(arrowPath, arrowPaint);
      final head = Path()
        ..moveTo(inner.left + 3, inner.top + 5)
        ..lineTo(inner.left + 7, inner.top + 4)
        ..moveTo(inner.left + 3, inner.top + 5)
        ..lineTo(inner.left + 5, inner.top + 1);
      canvas.drawPath(head, arrowPaint);
    }

    if (maximize) {
      final cornerPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.84)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      const corner = 5.0;
      canvas.drawLine(
        Offset(inner.left + 2, inner.top + 2),
        Offset(inner.left + corner, inner.top + 2),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(inner.left + 2, inner.top + 2),
        Offset(inner.left + 2, inner.top + corner),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(inner.right - 2, inner.bottom - 2),
        Offset(inner.right - corner, inner.bottom - 2),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(inner.right - 2, inner.bottom - 2),
        Offset(inner.right - 2, inner.bottom - corner),
        cornerPaint,
      );
    }

    canvas.drawRRect(outer, framePaint);
  }

  Rect _presetFillRect(Rect bounds) {
    switch (preset) {
      case DesktopPanelPreset.topHalf:
        return Rect.fromLTWH(
          bounds.left,
          bounds.top,
          bounds.width,
          bounds.height * 0.5,
        );
      case DesktopPanelPreset.bottomHalf:
        return Rect.fromLTWH(
          bounds.left,
          bounds.center.dy,
          bounds.width,
          bounds.height * 0.5,
        );
      case DesktopPanelPreset.leftHalf:
        return Rect.fromLTWH(
          bounds.left,
          bounds.top,
          bounds.width * 0.5,
          bounds.height,
        );
      case DesktopPanelPreset.leftThird:
        return Rect.fromLTWH(
          bounds.left,
          bounds.top,
          bounds.width / 3,
          bounds.height,
        );
      case DesktopPanelPreset.rightHalf:
        return Rect.fromLTWH(
          bounds.center.dx,
          bounds.top,
          bounds.width * 0.5,
          bounds.height,
        );
      case DesktopPanelPreset.rightThird:
        return Rect.fromLTWH(
          bounds.right - (bounds.width / 3),
          bounds.top,
          bounds.width / 3,
          bounds.height,
        );
      case null:
        return bounds;
    }
  }

  @override
  bool shouldRepaint(covariant _DesktopPanelPresetIconPainter oldDelegate) {
    return oldDelegate.preset != preset ||
        oldDelegate.maximize != maximize ||
        oldDelegate.reset != reset;
  }
}

class _DesktopPanelShellState extends State<DesktopPanelShell> {
  Rect? _liveRect;
  Rect? _interactionStartRect;
  Offset? _interactionStartGlobal;
  _DesktopPanelEdge? _activeResizeEdge;
  bool _dragActive = false;

  bool get _isInteracting =>
      _dragActive ||
      _activeResizeEdge != null ||
      _interactionStartRect != null ||
      _interactionStartGlobal != null;

  @override
  void initState() {
    super.initState();
    _syncLiveRect();
  }

  @override
  void didUpdateWidget(covariant DesktopPanelShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isInteracting &&
        (oldWidget.layout != widget.layout ||
            oldWidget.availableBounds != widget.availableBounds ||
            oldWidget.fullscreen != widget.fullscreen)) {
      _syncLiveRect();
    }
  }

  void _syncLiveRect() {
    _liveRect = _rectFromLayout(widget.layout);
  }

  Rect _rectFromLayout(DesktopEditorWindowLayout layout) {
    final bounds = widget.availableBounds;
    final width = (bounds.width * layout.widthFraction)
        .clamp(widget.minWidth, bounds.width);
    final height = (bounds.height * layout.heightFraction)
        .clamp(widget.minHeight, bounds.height);
    final left = bounds.left +
        ((bounds.width - width) * layout.leftFraction)
            .clamp(0.0, bounds.width - width);
    final top = bounds.top +
        ((bounds.height - height) * layout.topFraction)
            .clamp(0.0, bounds.height - height);
    return _clampRect(Rect.fromLTWH(left, top, width, height));
  }

  DesktopEditorWindowLayout _layoutFromRect(Rect rect) {
    final bounds = widget.availableBounds;
    final safeWidth = bounds.width <= 0.0 ? 1.0 : bounds.width;
    final safeHeight = bounds.height <= 0.0 ? 1.0 : bounds.height;
    final widthFraction = (rect.width / safeWidth).clamp(0.15, 1.0);
    final heightFraction = (rect.height / safeHeight).clamp(0.15, 1.0);
    final leftFraction = safeWidth <= rect.width
        ? 0.0
        : ((rect.left - bounds.left) / (safeWidth - rect.width))
            .clamp(0.0, 1.0);
    final topFraction = safeHeight <= rect.height
        ? 0.0
        : ((rect.top - bounds.top) / (safeHeight - rect.height))
            .clamp(0.0, 1.0);
    return DesktopEditorWindowLayout(
      leftFraction: leftFraction,
      topFraction: topFraction,
      widthFraction: widthFraction,
      heightFraction: heightFraction,
    );
  }

  Rect _clampRect(Rect rect) {
    final bounds = widget.availableBounds;
    final width = rect.width.clamp(widget.minWidth, bounds.width);
    final height = rect.height.clamp(widget.minHeight, bounds.height);
    final left = rect.left.clamp(bounds.left, bounds.right - width);
    final top = rect.top.clamp(bounds.top, bounds.bottom - height);
    return Rect.fromLTWH(left, top, width, height);
  }

  Rect _presetRect(DesktopPanelPreset preset) {
    final bounds = widget.availableBounds;
    switch (preset) {
      case DesktopPanelPreset.topHalf:
        return Rect.fromLTWH(
          bounds.left,
          bounds.top,
          bounds.width,
          bounds.height * 0.5,
        );
      case DesktopPanelPreset.bottomHalf:
        return Rect.fromLTWH(
          bounds.left,
          bounds.top + (bounds.height * 0.5),
          bounds.width,
          bounds.height * 0.5,
        );
      case DesktopPanelPreset.leftHalf:
        return Rect.fromLTWH(
          bounds.left,
          bounds.top,
          bounds.width * 0.5,
          bounds.height,
        );
      case DesktopPanelPreset.leftThird:
        return Rect.fromLTWH(
          bounds.left,
          bounds.top,
          bounds.width / 3,
          bounds.height,
        );
      case DesktopPanelPreset.rightHalf:
        return Rect.fromLTWH(
          bounds.left + (bounds.width * 0.5),
          bounds.top,
          bounds.width * 0.5,
          bounds.height,
        );
      case DesktopPanelPreset.rightThird:
        return Rect.fromLTWH(
          bounds.right - (bounds.width / 3),
          bounds.top,
          bounds.width / 3,
          bounds.height,
        );
    }
  }

  void _beginDrag(DragStartDetails details) {
    if (widget.fullscreen) return;
    _dragActive = true;
    _interactionStartRect = _liveRect ?? _rectFromLayout(widget.layout);
    _interactionStartGlobal = details.globalPosition;
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_dragActive ||
        _interactionStartRect == null ||
        _interactionStartGlobal == null) {
      return;
    }
    final delta = details.globalPosition - _interactionStartGlobal!;
    setState(() {
      _liveRect = _clampRect(
        _interactionStartRect!.shift(delta),
      );
    });
  }

  void _endDrag([DragEndDetails? _]) {
    if (!_dragActive) return;
    _dragActive = false;
    _commitLiveRect();
  }

  void _beginResize(_DesktopPanelEdge edge, DragStartDetails details) {
    if (widget.fullscreen) return;
    _activeResizeEdge = edge;
    _interactionStartRect = _liveRect ?? _rectFromLayout(widget.layout);
    _interactionStartGlobal = details.globalPosition;
  }

  void _updateResize(DragUpdateDetails details) {
    if (_activeResizeEdge == null ||
        _interactionStartRect == null ||
        _interactionStartGlobal == null) {
      return;
    }
    final start = _interactionStartRect!;
    final delta = details.globalPosition - _interactionStartGlobal!;
    double left = start.left;
    double top = start.top;
    double right = start.right;
    double bottom = start.bottom;

    switch (_activeResizeEdge!) {
      case _DesktopPanelEdge.left:
        left += delta.dx;
        break;
      case _DesktopPanelEdge.right:
        right += delta.dx;
        break;
      case _DesktopPanelEdge.top:
        top += delta.dy;
        break;
      case _DesktopPanelEdge.bottom:
        bottom += delta.dy;
        break;
      case _DesktopPanelEdge.topLeft:
        left += delta.dx;
        top += delta.dy;
        break;
      case _DesktopPanelEdge.topRight:
        right += delta.dx;
        top += delta.dy;
        break;
      case _DesktopPanelEdge.bottomLeft:
        left += delta.dx;
        bottom += delta.dy;
        break;
      case _DesktopPanelEdge.bottomRight:
        right += delta.dx;
        bottom += delta.dy;
        break;
    }

    if (right - left < widget.minWidth) {
      if (_activeResizeEdge == _DesktopPanelEdge.left ||
          _activeResizeEdge == _DesktopPanelEdge.topLeft ||
          _activeResizeEdge == _DesktopPanelEdge.bottomLeft) {
        left = right - widget.minWidth;
      } else {
        right = left + widget.minWidth;
      }
    }

    if (bottom - top < widget.minHeight) {
      if (_activeResizeEdge == _DesktopPanelEdge.top ||
          _activeResizeEdge == _DesktopPanelEdge.topLeft ||
          _activeResizeEdge == _DesktopPanelEdge.topRight) {
        top = bottom - widget.minHeight;
      } else {
        bottom = top + widget.minHeight;
      }
    }

    setState(() {
      _liveRect = _clampRect(Rect.fromLTRB(left, top, right, bottom));
    });
  }

  void _endResize([DragEndDetails? _]) {
    if (_activeResizeEdge == null) return;
    _activeResizeEdge = null;
    _commitLiveRect();
  }

  void _commitLiveRect() {
    final liveRect = _liveRect;
    _interactionStartRect = null;
    _interactionStartGlobal = null;
    if (liveRect == null) return;
    widget.onLayoutChanged(_layoutFromRect(liveRect));
  }

  Future<void> _showPanelMenu(Offset globalPosition) async {
    final selection = await showMenu<_DesktopPanelMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      color: const Color(0xFF17202B),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      items: <PopupMenuEntry<_DesktopPanelMenuAction>>[
        PopupMenuItem<_DesktopPanelMenuAction>(
          value: widget.fullscreen
              ? _DesktopPanelMenuAction.exitFullscreen
              : _DesktopPanelMenuAction.enterFullscreen,
          child: _DesktopPanelMenuRow(
            label: widget.fullscreen ? 'Restore Window' : 'Maximize',
            icon: _DesktopPanelPresetIcon(
              preset: widget.fullscreen ? null : DesktopPanelPreset.topHalf,
              maximize: !widget.fullscreen,
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_DesktopPanelMenuAction>(
          value: _DesktopPanelMenuAction.topHalf,
          child: _DesktopPanelMenuRow(
            label: 'Top Half',
            icon: _DesktopPanelPresetIcon(
              preset: DesktopPanelPreset.topHalf,
            ),
          ),
        ),
        PopupMenuItem<_DesktopPanelMenuAction>(
          value: _DesktopPanelMenuAction.bottomHalf,
          child: _DesktopPanelMenuRow(
            label: 'Bottom Half',
            icon: _DesktopPanelPresetIcon(
              preset: DesktopPanelPreset.bottomHalf,
            ),
          ),
        ),
        PopupMenuItem<_DesktopPanelMenuAction>(
          value: _DesktopPanelMenuAction.leftHalf,
          child: _DesktopPanelMenuRow(
            label: 'Left 1/2',
            icon: _DesktopPanelPresetIcon(
              preset: DesktopPanelPreset.leftHalf,
            ),
          ),
        ),
        PopupMenuItem<_DesktopPanelMenuAction>(
          value: _DesktopPanelMenuAction.leftThird,
          child: _DesktopPanelMenuRow(
            label: 'Left 1/3',
            icon: _DesktopPanelPresetIcon(
              preset: DesktopPanelPreset.leftThird,
            ),
          ),
        ),
        PopupMenuItem<_DesktopPanelMenuAction>(
          value: _DesktopPanelMenuAction.rightHalf,
          child: _DesktopPanelMenuRow(
            label: 'Right 1/2',
            icon: _DesktopPanelPresetIcon(
              preset: DesktopPanelPreset.rightHalf,
            ),
          ),
        ),
        PopupMenuItem<_DesktopPanelMenuAction>(
          value: _DesktopPanelMenuAction.rightThird,
          child: _DesktopPanelMenuRow(
            label: 'Right 1/3',
            icon: _DesktopPanelPresetIcon(
              preset: DesktopPanelPreset.rightThird,
            ),
          ),
        ),
        if (widget.onResetLayout !=
            null) ...<PopupMenuEntry<_DesktopPanelMenuAction>>[
          const PopupMenuDivider(),
          PopupMenuItem<_DesktopPanelMenuAction>(
            value: _DesktopPanelMenuAction.resetDefault,
            child: _DesktopPanelMenuRow(
              label: 'Reset Default Window',
              icon: _DesktopPanelPresetIcon(reset: true),
            ),
          ),
        ],
      ],
    );

    if (!mounted || selection == null) return;
    switch (selection) {
      case _DesktopPanelMenuAction.enterFullscreen:
        widget.onFullscreenChanged(true);
        return;
      case _DesktopPanelMenuAction.exitFullscreen:
        widget.onFullscreenChanged(false);
        return;
      case _DesktopPanelMenuAction.topHalf:
        _applyPreset(DesktopPanelPreset.topHalf);
        return;
      case _DesktopPanelMenuAction.bottomHalf:
        _applyPreset(DesktopPanelPreset.bottomHalf);
        return;
      case _DesktopPanelMenuAction.leftHalf:
        _applyPreset(DesktopPanelPreset.leftHalf);
        return;
      case _DesktopPanelMenuAction.leftThird:
        _applyPreset(DesktopPanelPreset.leftThird);
        return;
      case _DesktopPanelMenuAction.rightHalf:
        _applyPreset(DesktopPanelPreset.rightHalf);
        return;
      case _DesktopPanelMenuAction.rightThird:
        _applyPreset(DesktopPanelPreset.rightThird);
        return;
      case _DesktopPanelMenuAction.resetDefault:
        widget.onResetLayout?.call();
        return;
    }
  }

  void _applyPreset(DesktopPanelPreset preset) {
    final nextRect = _clampRect(_presetRect(preset));
    setState(() {
      _liveRect = nextRect;
    });
    if (widget.fullscreen) {
      widget.onFullscreenChanged(false);
    }
    widget.onLayoutChanged(_layoutFromRect(nextRect));
  }

  Widget _buildResizeHandle({
    required Alignment alignment,
    required MouseCursor cursor,
    required _DesktopPanelEdge edge,
    double? width,
    double? height,
  }) {
    return Align(
      alignment: alignment,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (details) => _beginResize(edge, details),
          onPanUpdate: _updateResize,
          onPanEnd: _endResize,
          child: SizedBox(
            width: width ?? 16,
            height: height ?? 16,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.fullscreen
        ? widget.availableBounds
        : (_liveRect ?? _rectFromLayout(widget.layout));
    final shellPadding =
        widget.fullscreen ? EdgeInsets.zero : const EdgeInsets.all(8);
    final dragStripHeight = widget.fullscreen ? 0.0 : 10.0;
    final topMenuHeight = widget.fullscreen
        ? 0.0
        : widget.topContextMenuHeight.clamp(0.0, rect.height);

    return Positioned.fromRect(
      rect: rect,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (!widget.fullscreen &&
              event.localPosition.dy <= topMenuHeight &&
              event.kind == PointerDeviceKind.mouse &&
              event.buttons == kSecondaryMouseButton) {
            _showPanelMenu(event.position);
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Padding(
              padding: shellPadding,
              child: widget.child,
            ),
            if (!widget.fullscreen)
              Positioned(
                left: 22,
                right: 22,
                top: 0,
                height: dragStripHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: _beginDrag,
                  onPanUpdate: _updateDrag,
                  onPanEnd: _endDrag,
                  child: const SizedBox.expand(),
                ),
              ),
            if (!widget.fullscreen) ...<Widget>[
              _buildResizeHandle(
                alignment: Alignment.centerLeft,
                cursor: SystemMouseCursors.resizeLeftRight,
                edge: _DesktopPanelEdge.left,
                width: 14,
                height: double.infinity,
              ),
              _buildResizeHandle(
                alignment: Alignment.centerRight,
                cursor: SystemMouseCursors.resizeLeftRight,
                edge: _DesktopPanelEdge.right,
                width: 14,
                height: double.infinity,
              ),
              _buildResizeHandle(
                alignment: Alignment.topCenter,
                cursor: SystemMouseCursors.resizeUpDown,
                edge: _DesktopPanelEdge.top,
                width: double.infinity,
                height: 14,
              ),
              _buildResizeHandle(
                alignment: Alignment.bottomCenter,
                cursor: SystemMouseCursors.resizeUpDown,
                edge: _DesktopPanelEdge.bottom,
                width: double.infinity,
                height: 14,
              ),
              _buildResizeHandle(
                alignment: Alignment.topLeft,
                cursor: SystemMouseCursors.resizeUpLeftDownRight,
                edge: _DesktopPanelEdge.topLeft,
              ),
              _buildResizeHandle(
                alignment: Alignment.topRight,
                cursor: SystemMouseCursors.resizeUpRightDownLeft,
                edge: _DesktopPanelEdge.topRight,
              ),
              _buildResizeHandle(
                alignment: Alignment.bottomLeft,
                cursor: SystemMouseCursors.resizeUpRightDownLeft,
                edge: _DesktopPanelEdge.bottomLeft,
              ),
              _buildResizeHandle(
                alignment: Alignment.bottomRight,
                cursor: SystemMouseCursors.resizeUpLeftDownRight,
                edge: _DesktopPanelEdge.bottomRight,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
