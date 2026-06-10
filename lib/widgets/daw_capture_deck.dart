import 'dart:math' as math;

import 'package:flutter/material.dart';

class DawCaptureDeck extends StatelessWidget {
  const DawCaptureDeck({
    super.key,
    required this.desktop,
    required this.fullscreen,
    required this.busy,
    required this.recording,
    required this.playing,
    required this.recordingPeaks,
    required this.selectedRowName,
    required this.selectedClipLabel,
    required this.selectedClipCount,
    required this.canBounceSelection,
    required this.canFreezeRow,
    required this.canCleanUpRecording,
    required this.onFullscreenChanged,
    required this.onClose,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCaptureMix,
    required this.onOpenExport,
    required this.onBounceSelection,
    required this.onFreezeRow,
    required this.onCleanUpRecording,
  });

  final bool desktop;
  final bool fullscreen;
  final bool busy;
  final bool recording;
  final bool playing;
  final List<double> recordingPeaks;
  final String selectedRowName;
  final String selectedClipLabel;
  final int selectedClipCount;
  final bool canBounceSelection;
  final bool canFreezeRow;
  final bool canCleanUpRecording;
  final ValueChanged<bool> onFullscreenChanged;
  final VoidCallback onClose;
  final Future<void> Function() onStartRecording;
  final Future<void> Function() onStopRecording;
  final Future<void> Function() onCaptureMix;
  final Future<void> Function() onOpenExport;
  final Future<void> Function() onBounceSelection;
  final Future<void> Function() onFreezeRow;
  final Future<void> Function() onCleanUpRecording;

  @override
  Widget build(BuildContext context) {
    final compact = !desktop || MediaQuery.sizeOf(context).width < 620;
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('daw_capture_deck'),
        decoration: BoxDecoration(
          color: const Color(0xF21B232B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: <Widget>[
              _CaptureDeckHeader(
                recording: recording,
                busy: busy,
                fullscreen: fullscreen,
                desktop: desktop,
                onFullscreenChanged: onFullscreenChanged,
                onClose: onClose,
              ),
              Expanded(
                child: compact
                    ? _buildCompactBody(context)
                    : _buildDesktopBody(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 7,
            child: _WaveformPane(
              recording: recording,
              playing: playing,
              busy: busy,
              peaks: recordingPeaks,
              selectedRowName: selectedRowName,
              selectedClipLabel: selectedClipLabel,
              selectedClipCount: selectedClipCount,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 250,
            child: _ActionColumn(
              busy: busy,
              recording: recording,
              canBounceSelection: canBounceSelection,
              canFreezeRow: canFreezeRow,
              canCleanUpRecording: canCleanUpRecording,
              onStartRecording: onStartRecording,
              onStopRecording: onStopRecording,
              onCaptureMix: onCaptureMix,
              onOpenExport: onOpenExport,
              onBounceSelection: onBounceSelection,
              onFreezeRow: onFreezeRow,
              onCleanUpRecording: onCleanUpRecording,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: <Widget>[
          Expanded(
            child: _WaveformPane(
              recording: recording,
              playing: playing,
              busy: busy,
              peaks: recordingPeaks,
              selectedRowName: selectedRowName,
              selectedClipLabel: selectedClipLabel,
              selectedClipCount: selectedClipCount,
            ),
          ),
          const SizedBox(height: 10),
          _CompactActionGrid(
            busy: busy,
            recording: recording,
            canBounceSelection: canBounceSelection,
            canFreezeRow: canFreezeRow,
            canCleanUpRecording: canCleanUpRecording,
            onStartRecording: onStartRecording,
            onStopRecording: onStopRecording,
            onCaptureMix: onCaptureMix,
            onOpenExport: onOpenExport,
            onBounceSelection: onBounceSelection,
            onFreezeRow: onFreezeRow,
            onCleanUpRecording: onCleanUpRecording,
          ),
        ],
      ),
    );
  }
}

class _CaptureDeckHeader extends StatelessWidget {
  const _CaptureDeckHeader({
    required this.recording,
    required this.busy,
    required this.fullscreen,
    required this.desktop,
    required this.onFullscreenChanged,
    required this.onClose,
  });

  final bool recording;
  final bool busy;
  final bool fullscreen;
  final bool desktop;
  final ValueChanged<bool> onFullscreenChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: recording ? const Color(0xFFFF4D4D) : Colors.white30,
              boxShadow: recording
                  ? <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFFFF4D4D).withValues(alpha: 0.55),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Capture Deck',
            style: TextStyle(
              color: Color(0xFFF7F7F7),
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          if (busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFEDEDED),
              ),
            ),
          const Spacer(),
          if (desktop)
            _HeaderIconButton(
              tooltip: fullscreen ? 'Restore' : 'Fullscreen',
              icon: fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              onPressed: () => onFullscreenChanged(!fullscreen),
            ),
          _HeaderIconButton(
            tooltip: 'Close',
            icon: Icons.close,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: Colors.white.withValues(alpha: 0.82),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _WaveformPane extends StatelessWidget {
  const _WaveformPane({
    required this.recording,
    required this.playing,
    required this.busy,
    required this.peaks,
    required this.selectedRowName,
    required this.selectedClipLabel,
    required this.selectedClipCount,
  });

  final bool recording;
  final bool playing;
  final bool busy;
  final List<double> peaks;
  final String selectedRowName;
  final String selectedClipLabel;
  final int selectedClipCount;

  @override
  Widget build(BuildContext context) {
    final clipText = selectedClipCount <= 0
        ? 'No clip selected'
        : selectedClipCount == 1
            ? selectedClipLabel
            : '$selectedClipCount clips selected';
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF10161D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 42,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 12),
                Icon(
                  recording ? Icons.fiber_manual_record : Icons.graphic_eq,
                  color: recording
                      ? const Color(0xFFFF4D4D)
                      : const Color(0xFF8EB8E8),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recording
                        ? 'Recording input'
                        : busy
                            ? 'Rendering audio'
                            : playing
                                ? 'Transport playing'
                                : 'Ready',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFEFEFEF),
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  selectedRowName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CustomPaint(
                  painter: _DeckWaveformPainter(
                    peaks: peaks,
                    recording: recording,
                    busy: busy,
                  ),
                ),
                if (peaks.isEmpty)
                  Center(
                    child: Text(
                      recording ? 'Waiting for input' : 'No live input yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: Text(
              clipText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    required this.busy,
    required this.recording,
    required this.canBounceSelection,
    required this.canFreezeRow,
    required this.canCleanUpRecording,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCaptureMix,
    required this.onOpenExport,
    required this.onBounceSelection,
    required this.onFreezeRow,
    required this.onCleanUpRecording,
  });

  final bool busy;
  final bool recording;
  final bool canBounceSelection;
  final bool canFreezeRow;
  final bool canCleanUpRecording;
  final Future<void> Function() onStartRecording;
  final Future<void> Function() onStopRecording;
  final Future<void> Function() onCaptureMix;
  final Future<void> Function() onOpenExport;
  final Future<void> Function() onBounceSelection;
  final Future<void> Function() onFreezeRow;
  final Future<void> Function() onCleanUpRecording;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _DeckActionButton(
          key: const ValueKey('capture_deck_record_button'),
          icon: recording ? Icons.stop : Icons.fiber_manual_record,
          label: recording ? 'Stop Recording' : 'Record Input',
          accent: recording ? const Color(0xFFFF6B5F) : const Color(0xFFFF4D4D),
          enabled: !busy,
          onPressed: recording ? onStopRecording : onStartRecording,
        ),
        const SizedBox(height: 10),
        _DeckActionButton(
          key: const ValueKey('capture_deck_capture_mix_button'),
          icon: Icons.waves,
          label: 'Capture DAW Output',
          enabled: !busy && !recording,
          onPressed: onCaptureMix,
        ),
        const SizedBox(height: 10),
        _DeckActionButton(
          key: const ValueKey('capture_deck_export_button'),
          icon: Icons.ios_share_rounded,
          label: 'Export Mix',
          enabled: !busy && !recording,
          onPressed: onOpenExport,
        ),
        const SizedBox(height: 10),
        _DeckActionButton(
          key: const ValueKey('capture_deck_cleanup_button'),
          icon: Icons.auto_fix_high,
          label: 'Clean Up Recording',
          accent: const Color(0xFF6ED3A6),
          enabled: !busy && !recording && canCleanUpRecording,
          onPressed: onCleanUpRecording,
        ),
        const SizedBox(height: 10),
        _DeckActionButton(
          key: const ValueKey('capture_deck_bounce_button'),
          icon: Icons.call_merge,
          label: 'Bounce Selected Clips',
          enabled: !busy && !recording && canBounceSelection,
          onPressed: onBounceSelection,
        ),
        const SizedBox(height: 10),
        _DeckActionButton(
          key: const ValueKey('capture_deck_freeze_button'),
          icon: Icons.ac_unit,
          label: 'Freeze Selected Track',
          enabled: !busy && !recording && canFreezeRow,
          onPressed: onFreezeRow,
        ),
      ],
    );
  }
}

class _CompactActionGrid extends StatelessWidget {
  const _CompactActionGrid({
    required this.busy,
    required this.recording,
    required this.canBounceSelection,
    required this.canFreezeRow,
    required this.canCleanUpRecording,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCaptureMix,
    required this.onOpenExport,
    required this.onBounceSelection,
    required this.onFreezeRow,
    required this.onCleanUpRecording,
  });

  final bool busy;
  final bool recording;
  final bool canBounceSelection;
  final bool canFreezeRow;
  final bool canCleanUpRecording;
  final Future<void> Function() onStartRecording;
  final Future<void> Function() onStopRecording;
  final Future<void> Function() onCaptureMix;
  final Future<void> Function() onOpenExport;
  final Future<void> Function() onBounceSelection;
  final Future<void> Function() onFreezeRow;
  final Future<void> Function() onCleanUpRecording;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _DeckMiniButton(
          key: const ValueKey('capture_deck_record_button'),
          icon: recording ? Icons.stop : Icons.fiber_manual_record,
          label: recording ? 'Stop' : 'Record',
          accent: const Color(0xFFFF4D4D),
          enabled: !busy,
          onPressed: recording ? onStopRecording : onStartRecording,
        ),
        _DeckMiniButton(
          key: const ValueKey('capture_deck_capture_mix_button'),
          icon: Icons.waves,
          label: 'Output',
          enabled: !busy && !recording,
          onPressed: onCaptureMix,
        ),
        _DeckMiniButton(
          key: const ValueKey('capture_deck_export_button'),
          icon: Icons.ios_share_rounded,
          label: 'Export',
          enabled: !busy && !recording,
          onPressed: onOpenExport,
        ),
        _DeckMiniButton(
          key: const ValueKey('capture_deck_cleanup_button'),
          icon: Icons.auto_fix_high,
          label: 'Clean',
          accent: const Color(0xFF6ED3A6),
          enabled: !busy && !recording && canCleanUpRecording,
          onPressed: onCleanUpRecording,
        ),
        _DeckMiniButton(
          key: const ValueKey('capture_deck_bounce_button'),
          icon: Icons.call_merge,
          label: 'Bounce',
          enabled: !busy && !recording && canBounceSelection,
          onPressed: onBounceSelection,
        ),
        _DeckMiniButton(
          key: const ValueKey('capture_deck_freeze_button'),
          icon: Icons.ac_unit,
          label: 'Freeze Track',
          enabled: !busy && !recording && canFreezeRow,
          onPressed: onFreezeRow,
        ),
      ],
    );
  }
}

class _DeckActionButton extends StatelessWidget {
  const _DeckActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.accent,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final Future<void> Function() onPressed;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? const Color(0xFF8EB8E8);
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: enabled ? () => onPressed() : null,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: color.withValues(alpha: 0.26),
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.045),
          foregroundColor: const Color(0xFFF8F8F8),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: enabled
                  ? color.withValues(alpha: 0.34)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
        icon: Icon(icon, size: 19),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DeckMiniButton extends StatelessWidget {
  const _DeckMiniButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.accent,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final Future<void> Function() onPressed;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? const Color(0xFF8EB8E8);
    return SizedBox(
      width: 104,
      height: 42,
      child: ElevatedButton(
        onPressed: enabled ? () => onPressed() : null,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: color.withValues(alpha: 0.22),
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.045),
          foregroundColor: const Color(0xFFF8F8F8),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: color.withValues(alpha: 0.28)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 17),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckWaveformPainter extends CustomPainter {
  const _DeckWaveformPainter({
    required this.peaks,
    required this.recording,
    required this.busy,
  });

  final List<double> peaks;
  final bool recording;
  final bool busy;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      final y = size.height * i / 6.0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8.0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final centerY = size.height / 2.0;
    final waveformPaint = Paint()
      ..color = (recording ? const Color(0xFFFF5E57) : const Color(0xFF8EB8E8))
          .withValues(alpha: busy ? 0.55 : 0.90)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, size.width / 360.0);

    final source = peaks;
    final visibleCount = math.max(12, (size.width / 3.4).floor());
    final start = math.max(0, source.length - visibleCount);
    final count = source.length - start;
    if (count <= 0) return;

    for (var i = 0; i < count; i++) {
      final x = count == 1 ? 0.0 : size.width * i / (count - 1);
      final peak = source[start + i].clamp(0.0, 1.0).toDouble();
      final height = math.max(3.0, peak * size.height * 0.86);
      canvas.drawLine(
        Offset(x, centerY - height / 2.0),
        Offset(x, centerY + height / 2.0),
        waveformPaint,
      );
    }

    final playheadPaint = Paint()
      ..color = Colors.white.withValues(alpha: recording ? 0.82 : 0.42)
      ..strokeWidth = 1.4;
    canvas.drawLine(
      Offset(size.width - 18, 8),
      Offset(size.width - 18, size.height - 8),
      playheadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DeckWaveformPainter oldDelegate) {
    return oldDelegate.peaks != peaks ||
        oldDelegate.recording != recording ||
        oldDelegate.busy != busy;
  }
}
