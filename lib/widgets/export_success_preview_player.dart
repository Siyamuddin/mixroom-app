import 'dart:async';
import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

class ExportSuccessPreviewPlayer extends StatefulWidget {
  final String filePath;
  final bool isVideo;

  const ExportSuccessPreviewPlayer({
    super.key,
    required this.filePath,
    required this.isVideo,
  });

  @override
  State<ExportSuccessPreviewPlayer> createState() =>
      _ExportSuccessPreviewPlayerState();
}

class _ExportSuccessPreviewPlayerState extends State<ExportSuccessPreviewPlayer> {
  final WaveformExtractionController _waveformExtractor =
      WaveformExtractionController();
  List<double> _waveform = const [];
  bool _waveformLoading = false;

  ja.AudioPlayer? _audioPlayer;
  VideoPlayerController? _videoController;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<ja.PlayerState>? _playerStateSub;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isSeeking = false;
  bool _isVideoReady = false;
  bool _audioReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _initVideo();
    } else {
      _initAudio();
    }
    _extractWaveform();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _audioPlayer?.dispose();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _waveformExtractor.stopWaveformExtraction();
    super.dispose();
  }

  Future<void> _initAudio() async {
    _audioPlayer = ja.AudioPlayer(handleAudioSessionActivation: false);
    _positionSub = _audioPlayer!.positionStream.listen((position) {
      if (_isSeeking || !mounted) return;
      setState(() {
        _position = position;
      });
    });
    _durationSub = _audioPlayer!.durationStream.listen((duration) {
      if (!mounted || duration == null) return;
      setState(() {
        _duration = duration;
      });
    });
    _playerStateSub = _audioPlayer!.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing &&
            state.processingState != ja.ProcessingState.completed;
      });
    });

    try {
      await _audioPlayer!.setFilePath(widget.filePath);
      if (!mounted) return;
      setState(() {
        _audioReady = true;
      });
    } catch (_) {
      // Keep the preview usable even if audio metadata fails to load.
      if (!mounted) return;
      setState(() {
        _audioReady = true;
      });
    }
  }

  Future<void> _initVideo() async {
    _videoController = VideoPlayerController.file(File(widget.filePath));
    _videoController!.addListener(_onVideoTick);

    try {
      await _videoController!.initialize();
      if (!mounted) return;
      setState(() {
        _isVideoReady = true;
        _duration = _videoController!.value.duration;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isVideoReady = true;
      });
    }
  }

  void _onVideoTick() {
    if (!mounted || _isSeeking) return;
    final controller = _videoController;
    if (controller == null) return;
    setState(() {
      _position = controller.value.position;
      _duration = controller.value.duration;
      _isPlaying = controller.value.isPlaying;
    });
  }

  Future<void> _extractWaveform() async {
    if (_waveformLoading || _waveform.isNotEmpty) return;
    _waveformLoading = true;
    setState(() {});

    try {
      final raw = await _waveformExtractor.extractWaveformData(
        path: widget.filePath,
        noOfSamples: 96,
      );
      if (!mounted) return;
      setState(() {
        _waveform = raw.isEmpty ? const [] : _normalizeWaveform(raw);
        _waveformLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _waveformLoading = false;
      });
    }
  }

  List<double> _normalizeWaveform(List<double> raw) {
    if (raw.isEmpty) return const [];
    final abs = raw.map((v) => v.abs()).toList();
    final maxVal = abs.reduce((a, b) => a > b ? a : b);
    if (maxVal <= 0) return List<double>.filled(abs.length, 0.0);
    return abs.map((v) => (v / maxVal).clamp(0.0, 1.0)).toList();
  }

  bool get _isReady {
    if (widget.isVideo) return _isVideoReady;
    return _audioReady;
  }

  bool get _canSeek => _duration > Duration.zero && _isReady;

  Future<void> _togglePlayback() async {
    if (!_isReady) return;
    if (widget.isVideo) {
      final controller = _videoController;
      if (controller == null || !controller.value.isInitialized) return;
      if (_isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
      return;
    }

    final player = _audioPlayer;
    if (player == null) return;
    if (_isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> _seekFromDx(double localX, double width) async {
    if (!_canSeek || width <= 1) return;
    final totalMs = _duration.inMilliseconds;
    final ratio = (localX / width).clamp(0.0, 1.0);
    final target = Duration(milliseconds: (totalMs * ratio).round());

    _isSeeking = true;
    try {
      if (widget.isVideo) {
        await _videoController?.seekTo(target);
      } else {
        await _audioPlayer?.seek(target);
      }
      if (mounted) {
        setState(() {
          _position = target;
        });
      }
    } finally {
      if (mounted) {
        _isSeeking = false;
      }
    }
  }

  String _formatClock(Duration duration) {
    final mins = duration.inMinutes;
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.filePath);
    final totalMs = _duration.inMilliseconds;
    final progress =
        totalMs <= 0 ? 0.0 : (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 12),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                iconSize: 26,
                visualDensity: VisualDensity.compact,
                color: Colors.white,
                disabledColor: Colors.white38,
                onPressed: _isReady ? _togglePlayback : null,
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              Expanded(
                child: Text(
                  '$fileName · ${_formatClock(_position)} / ${_formatClock(_duration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _canSeek
                    ? (d) => _seekFromDx(d.localPosition.dx, constraints.maxWidth)
                    : null,
                child: SizedBox(
                  height: 28,
                  child: _waveformLoading
                      ? const Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.8),
                          ),
                        )
                      : CustomPaint(
                          painter: _WaveformPreviewPainter(
                            waveform: _waveform,
                            progress: progress,
                            active: _isPlaying,
                          ),
                        ),
                ),
              );
            },
          ),
          const SizedBox(height: 2),
          if (!_isReady)
            const SizedBox(
              height: 14,
              child: Text(
                'Preparing preview...',
                style: TextStyle(color: Colors.white60, fontSize: 10.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaveformPreviewPainter extends CustomPainter {
  final List<double> waveform;
  final double progress;
  final bool active;

  const _WaveformPreviewPainter({
    required this.waveform,
    required this.progress,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bars = waveform.isEmpty ? List<double>.filled(64, 0.18) : waveform;
    final barPaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.7;
    final playedPaint = Paint()
      ..color = active ? const Color(0xFF7EECC2) : const Color(0xFF7DB4FF)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.7;
    final dxStep = size.width / bars.length;
    final centerY = size.height / 2;
    final playedX = size.width * progress.clamp(0.0, 1.0);

    for (int i = 0; i < bars.length; i++) {
      final x = (i + 0.5) * dxStep;
      final amp = bars[i].clamp(0.04, 1.0);
      final h = amp * (size.height * 0.78);
      final paint = x <= playedX ? playedPaint : barPaint;
      canvas.drawLine(
        Offset(x, centerY - h / 2),
        Offset(x, centerY + h / 2),
        paint,
      );
    }

    final headPaint = Paint()..color = Colors.white.withOpacity(0.9);
    canvas.drawCircle(Offset(playedX, centerY), 2.0, headPaint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPreviewPainter oldDelegate) {
    return oldDelegate.waveform != waveform ||
        oldDelegate.progress != progress ||
        oldDelegate.active != active;
  }
}
