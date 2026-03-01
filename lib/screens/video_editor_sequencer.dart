import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:mixroom/helpers/video_project_manager.dart';
import 'package:mixroom/helpers/video_sequencer_engine.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class VideoSequencerEditorScreen extends StatefulWidget {
  const VideoSequencerEditorScreen({
    super.key,
    required this.projectDir,
    this.initialImportPath,
  });

  final Directory projectDir;
  final String? initialImportPath;

  @override
  State<VideoSequencerEditorScreen> createState() =>
      _VideoSequencerEditorScreenState();
}

class _VideoSequencerEditorScreenState
    extends State<VideoSequencerEditorScreen> {
  static const Color _bg = Color(0xFF0B0C10);
  static const Color _panel = Color(0xFF111318);
  static const Color _panelSoft = Color(0xFF171A22);
  static const Color _stroke = Color(0xFF2B3140);
  static const Color _accent = Color(0xFF00C2FF);
  static const double _kChatBarFixedHeight = 50;
  static const double _kChatHistoryHeight = 340;
  static const double _kChatChromeOpacity = 0.08;
  static const double _kBottomDockApproxHeight = 72;

  late VideoSequencerEngine _engine;
  VideoPlayerController? _previewController;
  String? _previewClipId;

  Timer? _transportTimer;
  DateTime? _lastTransportTickAt;
  Timer? _saveDebounce;

  bool _loadingProject = true;
  bool _loadingMedia = false;
  bool _exporting = false;
  String? _busyLabel;

  final ScrollController _timelineScroll = ScrollController();
  final TextEditingController _chatTextController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final WaveformExtractionController _waveformExtractor =
      WaveformExtractionController();
  final Map<String, List<double>> _audioWaveformsByPath =
      <String, List<double>>{};
  final Set<String> _audioWaveformsLoading = <String>{};
  final Map<String, double> _clipDragDyAccumulator = <String, double>{};
  bool _snapEnabled = true;
  bool _autoFollowPlayhead = true;
  bool _chatExpanded = false;
  bool _chatInputActive = false;
  bool _chatHasText = false;
  bool _filePickerInFlight = false;
  final List<_EditorChatMessage> _chatMessages = <_EditorChatMessage>[];
  String? _selectedTransitionId;
  double _previewPlaybackSpeed = 1.0;
  double _timelineScaleBasePps = 120.0;
  bool _previewSyncInFlight = false;
  DateTime? _lastPreviewSyncAt;

  @override
  void initState() {
    super.initState();
    _engine = VideoSequencerEngine();
    _engine.addListener(_onEngineChanged);
    _chatTextController.addListener(_onChatTextChanged);
    _loadProjectState();
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChanged);
    _transportTimer?.cancel();
    _saveDebounce?.cancel();
    _timelineScroll.dispose();
    _chatTextController.removeListener(_onChatTextChanged);
    _chatTextController.dispose();
    _chatFocusNode.dispose();
    _waveformExtractor.stopWaveformExtraction();
    _previewController?.dispose();
    unawaited(_persistProjectState());
    super.dispose();
  }

  String get _projectName {
    final base = p.basename(widget.projectDir.path).trim();
    if (base.isEmpty) return 'Video Project';
    return base;
  }

  void _onChatTextChanged() {
    final hasText = _chatTextController.text.trim().isNotEmpty;
    if (_chatHasText == hasText || !mounted) return;
    setState(() => _chatHasText = hasText);
  }

  Future<void> _loadProjectState() async {
    final state = await VideoProjectManager.readState(widget.projectDir);
    final sequencerJson = state['sequencer'];

    VideoSequencerSnapshot? snapshot;
    if (sequencerJson is Map<String, dynamic>) {
      snapshot = VideoSequencerSnapshot.fromJson(sequencerJson);
    } else if (sequencerJson is Map) {
      snapshot = VideoSequencerSnapshot.fromJson(
          Map<String, dynamic>.from(sequencerJson));
    }

    final loadedEngine = VideoSequencerEngine(initial: snapshot);
    loadedEngine.addListener(_onEngineChanged);
    _engine.removeListener(_onEngineChanged);
    _engine = loadedEngine;

    _chatTextController.text = (state['chatDraft'] as String?) ?? '';
    _chatMessages
      ..clear()
      ..addAll(
        ((state['chatMessages'] as List?) ?? <dynamic>[]).whereType<Map>().map(
            (raw) =>
                _EditorChatMessage.fromJson(Map<String, dynamic>.from(raw))),
      );

    if ((widget.initialImportPath ?? '').trim().isNotEmpty &&
        _engine.videoTrack.clips.isEmpty) {
      await _addVideoClipFromPath(widget.initialImportPath!.trim(),
          preferredStart: Duration.zero);
    }

    _warmAudioWaveforms();
    await _syncPreviewToSequencer(force: true);
    if (!mounted) return;
    setState(() => _loadingProject = false);
  }

  Future<void> _persistProjectState() async {
    final payload = <String, dynamic>{
      'sequencer': _engine.toSnapshot().toJson(),
      'chatDraft': _chatTextController.text,
      'chatMessages': _chatMessages.map((m) => m.toJson()).toList(),
    };
    await VideoProjectManager.writeState(widget.projectDir, payload);
    await VideoProjectManager.touchProject(widget.projectDir);
  }

  void _scheduleStateSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_persistProjectState());
    });
  }

  void _onEngineChanged() {
    if (_selectedTransitionId != null &&
        _engine.transitionById(_selectedTransitionId!) == null) {
      _selectedTransitionId = null;
    }
    _warmAudioWaveforms();
    _syncTransportLoop();
    _scheduleStateSave();
    _schedulePreviewSync();
    if (_autoFollowPlayhead && _engine.isPlaying) {
      _autoScrollTimelineToPlayhead();
    }
    if (!mounted) return;
    setState(() {});
  }

  void _schedulePreviewSync({bool force = false}) {
    if (_previewSyncInFlight) return;
    final now = DateTime.now();
    final last = _lastPreviewSyncAt;
    if (!force &&
        _engine.isPlaying &&
        last != null &&
        now.difference(last).inMilliseconds < 55) {
      return;
    }
    _previewSyncInFlight = true;
    _lastPreviewSyncAt = now;
    unawaited(_syncPreviewToSequencer(force: force).whenComplete(() {
      _previewSyncInFlight = false;
    }));
  }

  void _syncTransportLoop() {
    if (_engine.isPlaying) {
      if (_transportTimer != null) return;
      _lastTransportTickAt = DateTime.now();
      _transportTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        final now = DateTime.now();
        final last = _lastTransportTickAt ?? now;
        _lastTransportTickAt = now;
        _engine.advanceBy(now.difference(last));
      });
      return;
    }
    _transportTimer?.cancel();
    _transportTimer = null;
    _lastTransportTickAt = null;
  }

  void _autoScrollTimelineToPlayhead({bool animated = false}) {
    if (!_timelineScroll.hasClients) return;
    final position = _timelineScroll.position;
    final viewport = position.viewportDimension;
    if (viewport <= 0) return;
    final playheadX =
        (_engine.playhead.inMilliseconds / 1000.0) * _engine.pixelsPerSecond;
    final left = position.pixels;
    final right = left + viewport;
    const edgePadding = 72.0;
    if (playheadX >= left + edgePadding && playheadX <= right - edgePadding) {
      return;
    }
    final target = (playheadX - viewport * 0.35).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 1.0) return;
    if (animated) {
      unawaited(_timelineScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      ));
      return;
    }
    _timelineScroll.jumpTo(target);
  }

  Future<void> _syncPreviewToSequencer({bool force = false}) async {
    if (!mounted) return;
    final clip = _engine.clipAtPlayhead(SequencerTrackType.video);
    if (clip == null) {
      if (_previewController != null) {
        await _previewController!.pause();
      }
      if (_previewClipId != null && mounted) {
        setState(() => _previewClipId = null);
      }
      return;
    }

    final clipFile = File(clip.sourcePath);
    if (!await clipFile.exists()) return;

    final local = _engine.localSourcePositionForClip(clip, _engine.playhead);
    final needsController =
        _previewController == null || _previewClipId != clip.id;

    if (needsController) {
      final old = _previewController;
      final next = VideoPlayerController.file(clipFile);
      try {
        await next.initialize();
      } catch (_) {
        await next.dispose();
        return;
      }

      _previewController = next;
      _previewClipId = clip.id;
      await old?.dispose();
      if (!mounted) return;
      setState(() {});
    }

    final controller = _previewController;
    if (controller == null || !controller.value.isInitialized) return;

    final driftMs = (controller.value.position - local).inMilliseconds.abs();
    if (force || driftMs > 110) {
      await controller.seekTo(local);
    }

    final clipTrack = _engine.trackForClip(clip.id);
    final trackAudible =
        clipTrack == null ? true : _engine.isTrackAudibleById(clipTrack.id);
    final targetVolume =
        (!trackAudible || clip.muted) ? 0.0 : clip.volume.clamp(0.0, 1.0);
    await controller.setVolume(targetVolume);
    await controller.setPlaybackSpeed(_previewPlaybackSpeed);

    if (_engine.isPlaying) {
      if (!controller.value.isPlaying) await controller.play();
    } else {
      if (controller.value.isPlaying) await controller.pause();
    }
  }

  Future<void> _pickVideoClip() async {
    final res = await _runFilePickerRequest<FilePickerResult?>(
      () => FilePicker.platform.pickFiles(type: FileType.video),
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.single.path;
    if (path == null || path.isEmpty) return;
    await _addVideoClipFromPath(path);
  }

  Future<void> _pickAudioClip() async {
    final res = await _runFilePickerRequest<FilePickerResult?>(
      () => FilePicker.platform.pickFiles(type: FileType.audio),
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.single.path;
    if (path == null || path.isEmpty) return;
    await _addAudioClipFromPath(path);
  }

  Future<T?> _runFilePickerRequest<T>(Future<T?> Function() request) async {
    if (_filePickerInFlight) return null;
    _filePickerInFlight = true;
    try {
      // Avoid presenting a native picker during an active Flutter route transition.
      await SchedulerBinding.instance.endOfFrame;
      return await request();
    } on PlatformException catch (e) {
      if (e.code != 'multiple_request') rethrow;
      await SchedulerBinding.instance.endOfFrame;
      try {
        return await request();
      } on PlatformException catch (retryError) {
        if (retryError.code == 'multiple_request') {
          debugPrint(
            'FilePicker still reported multiple_request after retry; dropping duplicate picker call.',
          );
          return null;
        }
        rethrow;
      }
    } finally {
      _filePickerInFlight = false;
    }
  }

  Future<void> _addVideoClipFromPath(
    String path, {
    Duration? preferredStart,
  }) async {
    setState(() {
      _loadingMedia = true;
      _busyLabel = 'Importing video...';
    });

    try {
      final duration = await _probeMediaDuration(path) ??
          await _probeVideoDurationFallback(path) ??
          const Duration(seconds: 5);

      _selectedTransitionId = null;
      _engine.addClip(
        type: SequencerTrackType.video,
        sourcePath: path,
        label: p.basename(path),
        sourceDuration: duration,
        sourceTotalDuration: duration,
        timelineStart: preferredStart,
      );
      await _syncPreviewToSequencer(force: true);
    } finally {
      if (mounted) {
        setState(() {
          _loadingMedia = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _addAudioClipFromPath(String path) async {
    setState(() {
      _loadingMedia = true;
      _busyLabel = 'Importing audio...';
    });

    try {
      final duration =
          await _probeMediaDuration(path) ?? const Duration(seconds: 4);
      _selectedTransitionId = null;
      _engine.addClip(
        type: SequencerTrackType.audio,
        sourcePath: path,
        label: p.basename(path),
        sourceDuration: duration,
        sourceTotalDuration: duration,
      );
      unawaited(_ensureWaveformForPath(path));
    } finally {
      if (mounted) {
        setState(() {
          _loadingMedia = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<Duration?> _probeMediaDuration(String path) async {
    try {
      final escaped = _ff(path);
      final session = await FFprobeKit.execute(
          '-v quiet -print_format json -show_format "$escaped"');
      final output = await session.getOutput();
      if (output == null || output.trim().isEmpty) return null;
      final data = jsonDecode(output);
      if (data is! Map) return null;
      final format = data['format'];
      if (format is! Map) return null;
      final rawDuration = format['duration']?.toString();
      final seconds = double.tryParse(rawDuration ?? '');
      if (seconds == null || !seconds.isFinite || seconds <= 0) return null;
      return Duration(milliseconds: (seconds * 1000).round());
    } catch (_) {
      return null;
    }
  }

  Future<bool> _probeHasAudioStream(String path) async {
    try {
      final escaped = _ff(path);
      final session = await FFprobeKit.execute(
          '-v error -select_streams a:0 -show_entries stream=index -of csv=p=0 "$escaped"');
      final output = await session.getOutput();
      if (output == null) return false;
      return output.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<Duration?> _probeVideoDurationFallback(String path) async {
    VideoPlayerController? c;
    try {
      c = VideoPlayerController.file(File(path));
      await c.initialize();
      if (!c.value.isInitialized) return null;
      final d = c.value.duration;
      if (d <= Duration.zero) return null;
      return d;
    } catch (_) {
      return null;
    } finally {
      await c?.dispose();
    }
  }

  void _togglePlayback() {
    if (_engine.totalDuration <= Duration.zero) return;
    HapticFeedback.selectionClick();
    if (_engine.isPlaying) {
      _engine.pause();
    } else {
      if (_engine.playhead >= _engine.totalDuration) {
        _engine.seek(Duration.zero);
      }
      _engine.play();
    }
  }

  void _restart() {
    HapticFeedback.selectionClick();
    _engine.restart();
    _schedulePreviewSync(force: true);
  }

  void _deleteSelectedClip() {
    HapticFeedback.selectionClick();
    _selectedTransitionId = null;
    _engine.removeSelectedClip();
  }

  void _duplicateSelectedClip() {
    HapticFeedback.selectionClick();
    _selectedTransitionId = null;
    final clip = _engine.selectedClip();
    if (clip == null) return;
    _engine.duplicateClip(clip.id);
  }

  void _splitSelectedClip() {
    _selectedTransitionId = null;
    final ok = _engine.splitSelectedClip();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Move playhead inside a clip to split.')),
      );
    }
  }

  Future<void> _addTransitionFromSelection() async {
    final selected = _engine.selectedClip();
    if (selected == null || selected.trackType != SequencerTrackType.video) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a video clip first.')),
      );
      return;
    }

    final next = _engine.nextVideoClip(selected.id);
    final prev = _engine.previousVideoClip(selected.id);
    final left = next != null ? selected : prev;
    final right = next ?? selected;
    if (left == null || right.id == left.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need two adjacent video clips.')),
      );
      return;
    }

    final created = _engine.addOrUpdateTransition(
      fromClipId: left.id,
      toClipId: right.id,
      duration: const Duration(milliseconds: 480),
      type: SequencerTransitionType.crossDissolve,
    );
    if (created == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to add transition here.')),
      );
      return;
    }
    setState(() => _selectedTransitionId = created.id);
  }

  void _removeSelectedTransition() {
    final id = _selectedTransitionId;
    if (id == null) return;
    _engine.removeTransition(id);
    setState(() => _selectedTransitionId = null);
  }

  Future<void> _showAddMediaSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.movie_creation_outlined,
                      color: Colors.white),
                  title: const Text('Add Video Clip',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickVideoClip();
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.audiotrack_rounded, color: Colors.white),
                  title: const Text('Add Audio Clip',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAudioClip();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _seekFromTimelineX(double localX) {
    final ms = (localX / _engine.pixelsPerSecond * 1000).round();
    _engine.seek(Duration(milliseconds: math.max(0, ms)));
    _schedulePreviewSync(force: true);
    if (_autoFollowPlayhead) {
      _autoScrollTimelineToPlayhead(animated: true);
    }
  }

  void _warmAudioWaveforms() {
    for (final track in _engine.audioTracks) {
      for (final clip in track.clips) {
        unawaited(_ensureWaveformForPath(clip.sourcePath));
      }
    }
  }

  Future<void> _ensureWaveformForPath(String path) async {
    if (_audioWaveformsByPath.containsKey(path)) return;
    if (_audioWaveformsLoading.contains(path)) return;
    _audioWaveformsLoading.add(path);
    if (mounted) setState(() {});

    try {
      final raw = await _waveformExtractor.extractWaveformData(
        path: path,
        noOfSamples: 120,
      );
      if (!mounted) return;
      setState(() {
        _audioWaveformsByPath[path] =
            raw.isEmpty ? const <double>[] : _normalizeWaveform(raw);
        _audioWaveformsLoading.remove(path);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _audioWaveformsByPath[path] = const <double>[];
        _audioWaveformsLoading.remove(path);
      });
    }
  }

  List<double> _normalizeWaveform(List<double> raw) {
    if (raw.isEmpty) return const <double>[];
    final abs = raw.map((v) => v.abs()).toList();
    final maxVal = abs.reduce(math.max);
    if (maxVal <= 0) return List<double>.filled(abs.length, 0.0);
    return abs.map((v) => (v / maxVal).clamp(0.0, 1.0)).toList();
  }

  void _adjustTransitionDurationFromDrag(
    SequencerTransition transition,
    double deltaDx, {
    required bool leadingHandle,
  }) {
    final signed = leadingHandle ? -deltaDx : deltaDx;
    final deltaMs = ((signed * 2.0) / _engine.pixelsPerSecond * 1000.0).round();
    if (deltaMs == 0) return;
    _engine.setTransitionDuration(
      transition.id,
      transition.duration + Duration(milliseconds: deltaMs),
    );
  }

  Duration _snapClipStart(
    SequencerTrack track,
    SequencerClip clip,
    Duration desiredStart,
  ) {
    if (!_snapEnabled) {
      return Duration(milliseconds: math.max(0, desiredStart.inMilliseconds));
    }
    const int gridMs = 50;
    var desiredMs = math.max(0, desiredStart.inMilliseconds);
    var snappedMs = ((desiredMs / gridMs).round()) * gridMs;

    final edgeThresholdMs =
        ((10 / _engine.pixelsPerSecond) * 1000).round().clamp(26, 130);
    for (final other in track.clips) {
      if (other.id == clip.id) continue;
      final startMs = other.timelineStart.inMilliseconds;
      final endMs = other.timelineEnd.inMilliseconds;
      if ((desiredMs - startMs).abs() <= edgeThresholdMs) {
        snappedMs = startMs;
      }
      if ((desiredMs - endMs).abs() <= edgeThresholdMs) {
        snappedMs = endMs;
      }
    }
    return Duration(milliseconds: math.max(0, snappedMs));
  }

  void _onClipPanStart(SequencerClip clip) {
    _clipDragDyAccumulator[clip.id] = 0.0;
  }

  void _onClipPanEnd(SequencerClip clip) {
    _clipDragDyAccumulator.remove(clip.id);
  }

  void _onClipPanUpdate(
    SequencerTrack track,
    SequencerClip clip,
    DragUpdateDetails details,
  ) {
    final deltaMs = (details.delta.dx / _engine.pixelsPerSecond * 1000).round();
    final desired = clip.timelineStart + Duration(milliseconds: deltaMs);
    final snapped = _snapClipStart(track, clip, desired);
    _engine.moveClip(clip.id, snapped);

    final accum = (_clipDragDyAccumulator[clip.id] ?? 0) + details.delta.dy;
    const threshold = 22.0;
    var nextAccum = accum;
    while (nextAccum.abs() >= threshold) {
      final direction = nextAccum > 0 ? 1 : -1;
      final moved = _engine.moveClipToNeighborTrack(
        clip.id,
        direction,
        desiredStart: snapped,
      );
      if (!moved) break;
      nextAccum -= direction * threshold;
    }
    _clipDragDyAccumulator[clip.id] = nextAccum;
  }

  void _trimClipFromLeftDrag(
    SequencerTrack track,
    SequencerClip clip,
    double deltaDx,
  ) {
    final deltaMs = (deltaDx / _engine.pixelsPerSecond * 1000).round();
    if (deltaMs == 0) return;

    final minDurMs = VideoSequencerEngine.minClipDuration.inMilliseconds;
    final oldTimelineStartMs = clip.timelineStart.inMilliseconds;
    final oldSourceStartMs = clip.sourceStart.inMilliseconds;
    final oldDurationMs = clip.sourceDuration.inMilliseconds;

    var previousEndMs = 0;
    for (final other in track.clips) {
      if (other.id == clip.id) continue;
      final endMs = other.timelineEnd.inMilliseconds;
      if (endMs <= oldTimelineStartMs && endMs > previousEndMs) {
        previousEndMs = endMs;
      }
    }

    final maxTimelineStartByDuration =
        oldTimelineStartMs + oldDurationMs - minDurMs;
    var desiredTimelineStartMs = (oldTimelineStartMs + deltaMs)
        .clamp(previousEndMs, maxTimelineStartByDuration);
    var appliedMs = desiredTimelineStartMs - oldTimelineStartMs;

    final minAppliedBySource = -oldSourceStartMs;
    final maxAppliedBySource = oldDurationMs - minDurMs;
    appliedMs = appliedMs.clamp(minAppliedBySource, maxAppliedBySource);
    if (appliedMs == 0) return;

    final newSourceStartMs = oldSourceStartMs + appliedMs;
    final newDurationMs = oldDurationMs - appliedMs;
    if (newDurationMs < minDurMs) return;

    _engine.trimClip(
      clip.id,
      newSourceStart: Duration(milliseconds: newSourceStartMs),
      newSourceDuration: Duration(milliseconds: newDurationMs),
    );
    _engine.moveClip(
      clip.id,
      Duration(milliseconds: oldTimelineStartMs + appliedMs),
    );
  }

  void _trimClipFromRightDrag(
    SequencerTrack track,
    SequencerClip clip,
    double deltaDx,
  ) {
    final deltaMs = (deltaDx / _engine.pixelsPerSecond * 1000).round();
    if (deltaMs == 0) return;

    final minDurMs = VideoSequencerEngine.minClipDuration.inMilliseconds;
    final oldDurationMs = clip.sourceDuration.inMilliseconds;
    final sourceMaxDurationMs = clip.sourceTotalDuration.inMilliseconds -
        clip.sourceStart.inMilliseconds;

    var nextStartMs = 1 << 30;
    for (final other in track.clips) {
      if (other.id == clip.id) continue;
      final startMs = other.timelineStart.inMilliseconds;
      if (startMs >= clip.timelineEnd.inMilliseconds && startMs < nextStartMs) {
        nextStartMs = startMs;
      }
    }
    final timelineGapMaxMs = nextStartMs == (1 << 30)
        ? 1 << 30
        : nextStartMs - clip.timelineStart.inMilliseconds;
    final maxAllowedMs = math.max(
      minDurMs,
      math.min(sourceMaxDurationMs, timelineGapMaxMs),
    );

    final desiredMs = (oldDurationMs + deltaMs).clamp(minDurMs, maxAllowedMs);
    if (desiredMs == oldDurationMs) return;

    _engine.trimClip(
      clip.id,
      newSourceDuration: Duration(milliseconds: desiredMs),
    );
  }

  void _nudgeSelectedClip(int direction) {
    final clip = _engine.selectedClip();
    if (clip == null) return;
    final stepMs = 33;
    final desired =
        clip.timelineStart + Duration(milliseconds: direction * stepMs);
    _engine.moveClip(
        clip.id, _snapClipStart(_engine.trackForClip(clip.id)!, clip, desired));
  }

  void _toggleSelectedClipMute() {
    final clip = _engine.selectedClip();
    if (clip == null) return;
    HapticFeedback.selectionClick();
    _engine.setClipMuted(clip.id, !clip.muted);
  }

  void _toggleSnap() {
    HapticFeedback.selectionClick();
    setState(() => _snapEnabled = !_snapEnabled);
  }

  void _toggleAutoFollow() {
    HapticFeedback.selectionClick();
    setState(() => _autoFollowPlayhead = !_autoFollowPlayhead);
    if (_autoFollowPlayhead) {
      _autoScrollTimelineToPlayhead(animated: true);
    }
  }

  void _zoomTimeline(double delta) {
    HapticFeedback.selectionClick();
    final target = (_engine.pixelsPerSecond + delta).clamp(60.0, 280.0);
    _engine.setPixelsPerSecond(target);
    if (_autoFollowPlayhead) {
      _autoScrollTimelineToPlayhead(animated: true);
    }
  }

  Future<void> _showClipQuickActions(SequencerClip clip) async {
    _engine.setSelectedClip(clip.id);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: Colors.white),
                title: const Text('Duplicate Clip',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _duplicateSelectedClip();
                },
              ),
              ListTile(
                leading: Icon(
                  clip.muted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  color: Colors.white,
                ),
                title: Text(
                  clip.muted ? 'Unmute Clip' : 'Mute Clip',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _engine.setClipMuted(clip.id, !clip.muted);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text('Delete Clip',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _deleteSelectedClip();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitChatMessage() async {
    final text = _chatTextController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _chatMessages.add(_EditorChatMessage(
        role: 'user',
        text: text,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
      _chatMessages.add(_EditorChatMessage(
        role: 'assistant',
        text:
            'Video AI placeholder: wiring to your Mixroom AI backend will be added here.',
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
      _chatTextController.clear();
      _chatExpanded = false;
      _chatInputActive = false;
    });
    _chatFocusNode.unfocus();
    _scheduleStateSave();
  }

  void _onChatBarTap() {
    setState(() {
      _chatExpanded = true;
      _chatInputActive = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chatFocusNode.requestFocus();
    });
  }

  void _dismissChatPanel() {
    setState(() {
      _chatExpanded = false;
      _chatInputActive = false;
    });
    _chatFocusNode.unfocus();
  }

  Future<void> _exportComposition() async {
    final videoClips = _engine.videoTracks
        .expand((t) => t.clips)
        .toList(growable: false)
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    final audioClips = _engine.audioTracks
        .expand((t) => t.clips)
        .toList(growable: false)
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));

    if (videoClips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one video clip to export.')),
      );
      return;
    }

    setState(() {
      _exporting = true;
      _busyLabel = 'Rendering export...';
    });

    try {
      final videoHasAudio = <String, bool>{};
      for (final clip in videoClips) {
        videoHasAudio[clip.id] = await _probeHasAudioStream(clip.sourcePath);
      }
      final audioClipHasAudio = <String, bool>{};
      for (final clip in audioClips) {
        audioClipHasAudio[clip.id] =
            await _probeHasAudioStream(clip.sourcePath);
      }

      final tmp = await getTemporaryDirectory();
      final outPath =
          '${tmp.path}/video_export_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final command = _buildFfmpegExportCommand(
        outputPath: outPath,
        videoClips: videoClips,
        audioClips: audioClips,
        videoHasAudio: videoHasAudio,
        audioClipHasAudio: audioClipHasAudio,
      );
      final session = await FFmpegKit.execute(command);
      final code = await session.getReturnCode();

      if (!ReturnCode.isSuccess(code)) {
        final logs = await session.getAllLogsAsString();
        throw Exception(logs ?? 'Export failed');
      }

      final saveName =
          '${_projectName.replaceAll(RegExp(r'[^a-zA-Z0-9_\\-]'), '_')}.mp4';
      final params = SaveFileDialogParams(
        sourceFilePath: outPath,
        fileName: saveName,
      );
      final savedPath = await FlutterFileDialog.saveFile(params: params);
      if (!mounted) return;

      if (savedPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Export created, but save was canceled.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export saved: $savedPath')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _busyLabel = null;
        });
      }
    }
  }

  String _buildFfmpegExportCommand({
    required String outputPath,
    required List<SequencerClip> videoClips,
    required List<SequencerClip> audioClips,
    required Map<String, bool> videoHasAudio,
    required Map<String, bool> audioClipHasAudio,
  }) {
    final inputArgs = <String>[];
    final videoInputIndexByClipId = <String, int>{};
    final audioInputIndexByClipId = <String, int>{};
    var inputIdx = 0;
    for (final clip in videoClips) {
      inputArgs.add('-i "${_ff(clip.sourcePath)}"');
      videoInputIndexByClipId[clip.id] = inputIdx;
      inputIdx += 1;
    }
    for (final clip in audioClips) {
      inputArgs.add('-i "${_ff(clip.sourcePath)}"');
      audioInputIndexByClipId[clip.id] = inputIdx;
      inputIdx += 1;
    }

    final totalSec = math.max(
      0.25,
      _engine.totalDuration.inMilliseconds / 1000.0,
    );
    final fadeInMsByVideoClip = <String, int>{};
    final fadeOutMsByVideoClip = <String, int>{};

    for (final transition in _engine.videoTransitions) {
      final from = _engine.videoClipById(transition.fromClipId);
      final to = _engine.videoClipById(transition.toClipId);
      if (from == null || to == null) continue;
      final fromTrack = _engine.trackForClip(from.id);
      final toTrack = _engine.trackForClip(to.id);
      if (fromTrack == null || toTrack == null || fromTrack.id != toTrack.id) {
        continue;
      }
      final boundaryGapMs =
          (to.timelineStart - from.timelineEnd).inMilliseconds.abs();
      if (boundaryGapMs > 140) continue;
      final fadeMs = math.min(
        transition.duration.inMilliseconds,
        math.min(from.sourceDuration.inMilliseconds,
            to.sourceDuration.inMilliseconds),
      );
      if (fadeMs <= 30) continue;
      fadeOutMsByVideoClip[from.id] =
          math.max(fadeOutMsByVideoClip[from.id] ?? 0, fadeMs);
      fadeInMsByVideoClip[to.id] =
          math.max(fadeInMsByVideoClip[to.id] ?? 0, fadeMs);
    }

    final filters = <String>[];
    for (final clip in videoClips) {
      final i = videoInputIndexByClipId[clip.id]!;
      final startSec = _sec(clip.sourceStart);
      final endSec = _sec(clip.sourceStart + clip.sourceDuration);
      final clipDurSec = clip.sourceDuration.inMilliseconds / 1000.0;
      var inFadeSec = (fadeInMsByVideoClip[clip.id] ?? 0) / 1000.0;
      var outFadeSec = (fadeOutMsByVideoClip[clip.id] ?? 0) / 1000.0;
      final maxCombined = math.max(0.0, clipDurSec - 0.04);
      if ((inFadeSec + outFadeSec) > maxCombined &&
          (inFadeSec + outFadeSec) > 0) {
        final scale = maxCombined / (inFadeSec + outFadeSec);
        inFadeSec *= scale;
        outFadeSec *= scale;
      }
      final videoFadeParts = <String>[];
      if (inFadeSec > 0.01) {
        videoFadeParts
            .add('fade=t=in:st=0:d=${inFadeSec.toStringAsFixed(3)}:alpha=1');
      }
      if (outFadeSec > 0.01) {
        final fadeOutStart = math.max(0.0, clipDurSec - outFadeSec);
        videoFadeParts.add(
            'fade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=${outFadeSec.toStringAsFixed(3)}:alpha=1');
      }
      final fadeChain =
          videoFadeParts.isEmpty ? '' : ',${videoFadeParts.join(',')}';
      filters.add(
          '[$i:v]trim=start=$startSec:end=$endSec,setpts=PTS-STARTPTS,fps=30,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,format=rgba$fadeChain[v$i]');
    }

    final videoTracks = _engine.videoTracks.toList(growable: false);
    for (int t = 0; t < videoTracks.length; t++) {
      final track = videoTracks[t];
      final sortedClips = List<SequencerClip>.from(track.clips)
        ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
      var acc = '[vt${t}_0]';
      filters.add(
          'color=c=black@0.0:s=1920x1080:r=30:d=${totalSec.toStringAsFixed(3)},format=rgba$acc');
      var step = 0;
      for (final clip in sortedClips) {
        final clipInput = videoInputIndexByClipId[clip.id];
        if (clipInput == null) continue;
        final startSec = _sec(clip.timelineStart);
        final endSec = _sec(clip.timelineEnd);
        final out = '[vt${t}_${step + 1}]';
        filters.add(
            '$acc[v$clipInput]overlay=shortest=0:eof_action=pass:enable=\'between(t,$startSec,$endSec)\'$out');
        acc = out;
        step += 1;
      }
      filters.add('$acc format=rgba[vtrack$t]');
    }

    var comp = '[vbase0]';
    filters.add(
        'color=c=black:s=1920x1080:r=30:d=${totalSec.toStringAsFixed(3)},format=rgba$comp');
    for (int t = 0; t < videoTracks.length; t++) {
      final out = '[vbase${t + 1}]';
      filters.add('$comp[vtrack$t]overlay=shortest=0:eof_action=pass$out');
      comp = out;
    }
    filters.add('$comp format=yuv420p[vout]');

    final audioInputs = <String>[];
    filters.add(
        'anullsrc=r=48000:cl=stereo,atrim=0:${totalSec.toStringAsFixed(3)}[sil]');

    for (final clip in videoClips) {
      if (videoHasAudio[clip.id] != true) continue;
      final i = videoInputIndexByClipId[clip.id];
      if (i == null) continue;
      final startSec = _sec(clip.sourceStart);
      final endSec = _sec(clip.sourceStart + clip.sourceDuration);
      final delayMs = math.max(0, clip.timelineStart.inMilliseconds);
      final clipTrack = _engine.trackForClip(clip.id);
      final trackAudible =
          clipTrack == null ? true : _engine.isTrackAudibleById(clipTrack.id);
      final volume =
          (!trackAudible || clip.muted) ? 0.0 : clip.volume.clamp(0.0, 2.0);

      final clipDurSec = clip.sourceDuration.inMilliseconds / 1000.0;
      var inFadeSec = (fadeInMsByVideoClip[clip.id] ?? 0) / 1000.0;
      var outFadeSec = (fadeOutMsByVideoClip[clip.id] ?? 0) / 1000.0;
      final maxCombined = math.max(0.0, clipDurSec - 0.04);
      if ((inFadeSec + outFadeSec) > maxCombined &&
          (inFadeSec + outFadeSec) > 0) {
        final scale = maxCombined / (inFadeSec + outFadeSec);
        inFadeSec *= scale;
        outFadeSec *= scale;
      }
      final audioFadeParts = <String>[];
      if (inFadeSec > 0.01) {
        audioFadeParts.add('afade=t=in:st=0:d=${inFadeSec.toStringAsFixed(3)}');
      }
      if (outFadeSec > 0.01) {
        final fadeOutStart = math.max(0.0, clipDurSec - outFadeSec);
        audioFadeParts.add(
            'afade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=${outFadeSec.toStringAsFixed(3)}');
      }
      final fades =
          audioFadeParts.isEmpty ? '' : ',${audioFadeParts.join(',')}';
      final label = '[va$i]';
      filters.add(
          '[$i:a]atrim=start=$startSec:end=$endSec,asetpts=PTS-STARTPTS$fades,volume=$volume,adelay=$delayMs|$delayMs$label');
      audioInputs.add(label);
    }

    for (final clip in audioClips) {
      if (audioClipHasAudio[clip.id] != true) continue;
      final i = audioInputIndexByClipId[clip.id];
      if (i == null) continue;
      final startSec = _sec(clip.sourceStart);
      final endSec = _sec(clip.sourceStart + clip.sourceDuration);
      final delayMs = math.max(0, clip.timelineStart.inMilliseconds);
      final clipTrack = _engine.trackForClip(clip.id);
      final trackAudible =
          clipTrack == null ? true : _engine.isTrackAudibleById(clipTrack.id);
      final volume =
          (!trackAudible || clip.muted) ? 0.0 : clip.volume.clamp(0.0, 2.0);
      final label = '[a$i]';
      filters.add(
          '[$i:a]atrim=start=$startSec:end=$endSec,asetpts=PTS-STARTPTS,volume=$volume,adelay=$delayMs|$delayMs$label');
      audioInputs.add(label);
    }

    if (audioInputs.isEmpty) {
      filters.add('[sil]anull[aout]');
    } else {
      final refs = audioInputs.join();
      filters.add(
          '[sil]$refs amix=inputs=${audioInputs.length + 1}:dropout_transition=0:normalize=0,aresample=async=1:first_pts=0[aout]');
    }

    return '${inputArgs.join(' ')} -filter_complex "${filters.join(';')}" '
        '-map "[vout]" -map "[aout]" '
        '-vsync 2 -r 30 -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p '
        '-c:a aac -b:a 192k -movflags +faststart -max_muxing_queue_size 4096 '
        '-y "${_ff(outputPath)}"';
  }

  String _ff(String path) => path.replaceAll('"', '\\"');

  String _sec(Duration d) => (d.inMilliseconds / 1000.0).toStringAsFixed(3);

  String _formatDuration(Duration d) {
    final totalMs = math.max(0, d.inMilliseconds);
    final h = totalMs ~/ 3600000;
    final m = (totalMs % 3600000) ~/ 60000;
    final s = (totalMs % 60000) ~/ 1000;
    final ms = (totalMs % 1000) ~/ 10;
    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    final xx = ms.toString().padLeft(2, '0');
    return '$hh:$mm:$ss.$xx';
  }

  Widget _buildTopBarIconButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: filled
                  ? const [Color(0xFF252B35), Color(0xFF191E26)]
                  : const [Color(0xFF191E26), Color(0xFF0F1319)],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: onTap == null ? 0.07 : 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.56),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.05),
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 16,
            color: onTap == null
                ? Colors.white.withValues(alpha: 0.30)
                : Colors.white.withValues(alpha: 0.92),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFF0C0D10),
            Color(0xFF090A0D),
            Color(0xFF07080A),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: SafeArea(
        top: true,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 5),
          child: SizedBox(
            height: 31,
            child: Row(
              children: [
                _buildTopBarIconButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                Container(
                  height: 23,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF1A202A), Color(0xFF10151D)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.46),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.expand_less_rounded,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '1080P',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 10.8,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _buildTopBarIconButton(
                  icon: Icons.ios_share_rounded,
                  onTap: _exporting ? null : _exportComposition,
                ),
                const SizedBox(width: 2),
                _buildTopBarIconButton(
                  icon: Icons.more_horiz_rounded,
                  onTap: _showEditorMoreSheet,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditorMoreSheet() async {
    final selectedClip = _engine.selectedClip();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.add_photo_alternate_outlined, color: Colors.white),
                title:
                    const Text('Add Media', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showAddMediaSheet();
                },
              ),
              ListTile(
                leading: Icon(
                  _autoFollowPlayhead
                      ? Icons.center_focus_weak_rounded
                      : Icons.center_focus_strong_rounded,
                  color: Colors.white,
                ),
                title: Text(
                  _autoFollowPlayhead ? 'Disable Playhead Follow' : 'Enable Playhead Follow',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _toggleAutoFollow();
                },
              ),
              ListTile(
                leading: Icon(
                  _snapEnabled ? Icons.grid_off_rounded : Icons.grid_on_rounded,
                  color: Colors.white,
                ),
                title: Text(
                  _snapEnabled ? 'Turn Snap Off' : 'Turn Snap On',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _toggleSnap();
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.copy_rounded,
                  color: selectedClip == null ? Colors.white30 : Colors.white,
                ),
                title: Text(
                  'Duplicate Selected Clip',
                  style: TextStyle(
                    color: selectedClip == null ? Colors.white38 : Colors.white,
                  ),
                ),
                onTap: selectedClip == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        _duplicateSelectedClip();
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPreviewStageCard() {
    final controller = _previewController;
    final hasVideo = controller != null && controller.value.isInitialized;
    final aspect = hasVideo ? controller.value.aspectRatio : 16 / 9;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF141922), Color(0xFF0A0D13)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.62),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xFF000000)),
                  child: hasVideo
                      ? VideoPlayer(controller)
                      : const Center(
                          child: Icon(
                            Icons.ondemand_video_rounded,
                            color: Colors.white54,
                            size: 52,
                          ),
                        ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.34),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.36),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 18,
            bottom: 18,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.60),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(
            right: -11,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.74),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.33),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
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

  Widget _buildTransportControlButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool emphasized = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: emphasized ? 33 : 29,
          height: emphasized ? 33 : 29,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: emphasized
                  ? const [Color(0xFF2A3240), Color(0xFF1A212C)]
                  : const [Color(0xFF1A202A), Color(0xFF11161E)],
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: onTap == null
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.white.withValues(alpha: emphasized ? 0.24 : 0.13),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.48),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.04),
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: emphasized ? 17 : 14.5,
            color: onTap == null
                ? Colors.white.withValues(alpha: 0.30)
                : Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantDockCard({required bool compact}) {
    final messages = _chatMessages.length > 18
        ? _chatMessages.sublist(_chatMessages.length - 18)
        : _chatMessages;
    return Container(
      margin: EdgeInsets.fromLTRB(12, compact ? 8 : 10, 12, 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _panelSoft.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _stroke.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 15, color: _accent.withValues(alpha: 0.92)),
              const SizedBox(width: 6),
              const Text(
                'Assistant (Placeholder)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: compact ? 132 : 172,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'Ask for cuts, pacing, captions, or scene ideas.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.56),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemBuilder: (_, i) => _buildChatMessageBubble(
                        messages[messages.length - 1 - i]),
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemCount: messages.length,
                  ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatTextController,
                    focusNode: _chatFocusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Type...',
                      hintStyle: TextStyle(color: Colors.white70),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitChatMessage(),
                  ),
                ),
                IconButton(
                  onPressed: _chatHasText ? _submitChatMessage : null,
                  icon: Icon(
                    Icons.send_rounded,
                    size: 18,
                    color: _chatHasText
                        ? _accent.withValues(alpha: 0.96)
                        : Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileToolContextPanel() {
    final selectedClip = _engine.selectedClip();
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 5),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF11161E), Color(0xFF0A0E14)],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.48),
            blurRadius: 11,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final minTextWidth = math.min(90.0, math.max(64.0, constraints.maxWidth * 0.32));
          final controls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTransportControlButton(
                icon: Icons.replay_rounded,
                onTap: _restart,
              ),
              const SizedBox(width: 6),
              _buildTransportControlButton(
                icon: _engine.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onTap: _togglePlayback,
                emphasized: true,
              ),
              const SizedBox(width: 6),
              _buildTransportControlButton(
                icon: Icons.undo_rounded,
                onTap: selectedClip == null ? null : () => _nudgeSelectedClip(-1),
              ),
              const SizedBox(width: 6),
              _buildTransportControlButton(
                icon: Icons.redo_rounded,
                onTap: selectedClip == null ? null : () => _nudgeSelectedClip(1),
              ),
              const SizedBox(width: 6),
              _buildTransportControlButton(
                icon: Icons.call_split_rounded,
                onTap: selectedClip == null ? null : _splitSelectedClip,
              ),
            ],
          );
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    width: minTextWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${_formatDuration(_engine.playhead)} / ${_formatDuration(_engine.totalDuration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.86),
                            fontSize: 9.8,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${_previewPlaybackSpeed.toStringAsFixed(2)}x  ·  ${_autoFollowPlayhead ? 'Follow' : 'Manual'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.52),
                            fontSize: 8.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  controls,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSpeedSheet() async {
    var draft = _previewPlaybackSpeed;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (_, setLocalState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Playback Speed',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.white,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: draft,
                        min: 0.25,
                        max: 2.0,
                        divisions: 7,
                        label: '${draft.toStringAsFixed(2)}x',
                        onChanged: (v) => setLocalState(() => draft = v),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          setState(() => _previewPlaybackSpeed = draft);
                          _schedulePreviewSync(force: true);
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showVolumeSheet() async {
    final clip = _engine.selectedClip();
    if (clip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a clip first.')),
      );
      return;
    }
    var draft = clip.volume.clamp(0.0, 2.0);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (_, setLocalState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Clip Volume',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.white,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: draft,
                        min: 0,
                        max: 2,
                        divisions: 8,
                        label: draft.toStringAsFixed(2),
                        onChanged: (v) => setLocalState(() => draft = v),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          _engine.setClipVolume(clip.id, draft);
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAnimationQuickAction() {
    final selected = _engine.selectedClip();
    if (selected == null || selected.trackType != SequencerTrackType.video) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a video clip first.')),
      );
      return;
    }
    unawaited(_addTransitionFromSelection());
  }

  Widget _buildBottomActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: Container(
          width: 60,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: onTap == null
                  ? const [Color(0xFF121418), Color(0xFF0E1116)]
                  : const [Color(0xFF1E2530), Color(0xFF121821)],
            ),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: onTap == null
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.11),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.44),
                blurRadius: 9,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16.5,
                color: onTap == null
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.88),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: onTap == null
                      ? Colors.white.withValues(alpha: 0.34)
                      : Colors.white.withValues(alpha: 0.8),
                  fontSize: 8.9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineHeader(double width) {
    final secCount = math.max(
      20,
      (_engine.totalDuration.inMilliseconds / 1000).ceil() + 5,
    );
    return SizedBox(
      width: width,
      height: 30,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _seekFromTimelineX(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => _seekFromTimelineX(d.localPosition.dx),
        onScaleStart: (_) => _timelineScaleBasePps = _engine.pixelsPerSecond,
        onScaleUpdate: (details) {
          if (details.pointerCount < 2) return;
          final next = (_timelineScaleBasePps * details.scale).clamp(60.0, 280.0);
          _engine.setPixelsPerSecond(next);
        },
        child: CustomPaint(
          painter: _RulerPainter(
            pixelsPerSecond: _engine.pixelsPerSecond,
            seconds: secCount,
            playheadMs: _engine.playhead.inMilliseconds.toDouble(),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackLane(SequencerTrack track, double width) {
    final isVideo = track.type == SequencerTrackType.video;
    final trackAudible = _engine.isTrackAudibleById(track.id);
    final sameTypeCount = track.type == SequencerTrackType.video
        ? _engine.videoTracks.length
        : _engine.audioTracks.length;
    final laneHeight = isVideo ? 88.0 : 82.0;
    const baseColor = Color(0xFF10131A);
    return Container(
      width: width,
      height: laneHeight,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: trackAudible ? 0.72 : 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _stroke.withValues(alpha: 0.8)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 10,
            right: 10,
            top: 7,
            child: Row(
              children: [
                Text(
                  track.name,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!trackAudible)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'Silent',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                _buildTrackTogglePill(
                  label: 'M',
                  active: track.muted,
                  onTap: () => _engine.setTrackMuted(track.id, !track.muted),
                  activeColor: const Color(0xFFFF8C8C),
                ),
                const SizedBox(width: 6),
                _buildTrackTogglePill(
                  label: 'S',
                  active: track.solo,
                  onTap: () => _engine.setTrackSolo(track.id, !track.solo),
                  activeColor: const Color(0xFF67D79D),
                ),
                if (sameTypeCount > 1) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _engine.removeTrack(track.id),
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.remove_circle_outline,
                        size: 15,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!trackAudible)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          for (final clip in track.clips) _buildClipCard(track, clip),
          Positioned(
            left: (_engine.playhead.inMilliseconds / 1000.0) *
                _engine.pixelsPerSecond,
            top: 0,
            bottom: 0,
            child: Container(
              width: 1.5,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClipCard(SequencerTrack track, SequencerClip clip) {
    final selected = clip.id == _engine.selectedClipId;
    final laneTop = track.type == SequencerTrackType.video ? 29.0 : 31.0;
    final laneHeight = track.type == SequencerTrackType.video ? 52.0 : 44.0;
    final left =
        (clip.timelineStart.inMilliseconds / 1000.0) * _engine.pixelsPerSecond;
    final width = math.max(
      56.0,
      (clip.sourceDuration.inMilliseconds / 1000.0) * _engine.pixelsPerSecond,
    );

    final color = track.type == SequencerTrackType.video
        ? const Color(0xFF5D5E66)
        : const Color(0xFF2D5B69);
    final faded = clip.muted ? 0.45 : 1.0;
    final waveform = track.type == SequencerTrackType.audio
        ? _audioWaveformsByPath[clip.sourcePath]
        : null;
    final waveformLoading = track.type == SequencerTrackType.audio &&
        _audioWaveformsLoading.contains(clip.sourcePath);
    if (track.type == SequencerTrackType.audio && waveform == null) {
      unawaited(_ensureWaveformForPath(clip.sourcePath));
    }

    return Positioned(
      left: left,
      top: laneTop,
      width: width,
      height: laneHeight,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTransitionId = null);
          _engine.setSelectedClip(clip.id);
        },
        onPanStart: (_) => _onClipPanStart(clip),
        onPanUpdate: (d) => _onClipPanUpdate(track, clip, d),
        onPanEnd: (_) => _onClipPanEnd(clip),
        onPanCancel: () => _onClipPanEnd(clip),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.82 * faded),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.38),
              width: selected ? 1.8 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    )
                  ]
                : const [],
          ),
          child: Stack(
            children: [
              if (selected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 12,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) =>
                        _trimClipFromLeftDrag(track, clip, d.delta.dx),
                    child: Center(
                      child: Container(
                        width: 2.4,
                        height: laneHeight - 10,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 12,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) =>
                        _trimClipFromRightDrag(track, clip, d.delta.dx),
                    child: Center(
                      child: Container(
                        width: 2.4,
                        height: laneHeight - 10,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
              if (waveform != null && waveform.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
                        child: CustomPaint(
                          painter: _ClipWaveformPainter(
                            samples: waveform,
                            color: Colors.white.withValues(alpha: 0.28 * faded),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (waveformLoading)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 5,
                  child: Container(
                    height: 1.8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    Icon(
                      track.type == SequencerTrackType.video
                          ? Icons.movie_creation_outlined
                          : Icons.audiotrack_rounded,
                      color: Colors.white.withValues(alpha: 0.95),
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        clip.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  Widget _buildTransitionsLane(SequencerTrack videoTrack, double width) {
    final clipIds = videoTrack.clips.map((c) => c.id).toSet();
    final transitions = _engine.videoTransitions
        .where((t) =>
            clipIds.contains(t.fromClipId) && clipIds.contains(t.toClipId))
        .toList(growable: false);
    return Container(
      width: width,
      height: 46,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF171A28).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _stroke.withValues(alpha: 0.8)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 10,
            top: 8,
            child: Text(
              '${videoTrack.name} Transitions',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final transition in transitions)
            _buildTransitionBadge(transition),
          Positioned(
            left: (_engine.playhead.inMilliseconds / 1000.0) *
                _engine.pixelsPerSecond,
            top: 0,
            bottom: 0,
            child: Container(
              width: 1.5,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransitionBadge(SequencerTransition transition) {
    final leftClip = _engine.videoClipById(transition.fromClipId);
    final rightClip = _engine.videoClipById(transition.toClipId);
    if (leftClip == null || rightClip == null) return const SizedBox.shrink();
    final selected = transition.id == _selectedTransitionId;

    final centerX = (leftClip.timelineEnd.inMilliseconds / 1000.0) *
        _engine.pixelsPerSecond;
    final width = math.max(
      26.0,
      (transition.duration.inMilliseconds / 1000.0) * _engine.pixelsPerSecond,
    );
    final left = centerX - width / 2;

    return Positioned(
      left: left,
      top: 15,
      width: width,
      height: 24,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTransitionId = transition.id);
          _engine.setSelectedClip(null);
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFA4BCFF).withValues(alpha: 0.8)
                      : const Color(0xFF8099E1).withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    width: selected ? 1.5 : 1.0,
                  ),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  transition.type == SequencerTransitionType.crossDissolve
                      ? 'Dissolve'
                      : 'Dip',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 14,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    setState(() => _selectedTransitionId = transition.id);
                    _engine.setSelectedClip(null);
                  },
                  onHorizontalDragUpdate: (d) {
                    _adjustTransitionDurationFromDrag(
                      transition,
                      d.delta.dx,
                      leadingHandle: true,
                    );
                  },
                  child: Center(
                    child: Container(
                      width: 2.2,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 14,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    setState(() => _selectedTransitionId = transition.id);
                    _engine.setSelectedClip(null);
                  },
                  onHorizontalDragUpdate: (d) {
                    _adjustTransitionDurationFromDrag(
                      transition,
                      d.delta.dx,
                      leadingHandle: false,
                    );
                  },
                  child: Center(
                    child: Container(
                      width: 2.2,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(999),
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
  }

  Widget _buildTimelineSection() {
    final contentSeconds = math.max(
      20.0,
      (_engine.totalDuration.inMilliseconds / 1000.0) + 6.0,
    );
    final contentWidth = math.max(460.0, contentSeconds * _engine.pixelsPerSecond);
    final selectedClip = _engine.selectedClip();

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 3, 10, 6),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0A0D13), Color(0xFF06080C)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.54),
                  blurRadius: 13,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      _formatDuration(_engine.playhead),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 9.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDuration(_engine.totalDuration),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 9.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _timelineScroll,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentWidth,
                          child: Column(
                            children: [
                              _buildTimelineHeader(contentWidth),
                              const SizedBox(height: 6),
                              _buildCompactVideoTrackLane(contentWidth),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        const SizedBox(height: 26),
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: _pickVideoClip,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: const Color(0xFF131821),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.36),
                                  blurRadius: 7,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            height: 67,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF171D27), Color(0xFF10151C)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              children: [
                _buildBottomActionButton(
                  icon: Icons.call_split_rounded,
                  label: 'Split',
                  onTap: selectedClip == null ? null : _splitSelectedClip,
                ),
                _buildBottomActionButton(
                  icon: Icons.copy_rounded,
                  label: 'Duplicate',
                  onTap: selectedClip == null ? null : _duplicateSelectedClip,
                ),
                _buildBottomActionButton(
                  icon: selectedClip?.muted == true
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  label: selectedClip?.muted == true ? 'Unmute' : 'Mute',
                  onTap: selectedClip == null ? null : _toggleSelectedClipMute,
                ),
                _buildBottomActionButton(
                  icon: Icons.speed_rounded,
                  label: 'Speed',
                  onTap: _showSpeedSheet,
                ),
                _buildBottomActionButton(
                  icon: Icons.volume_up_rounded,
                  label: 'Volume',
                  onTap: _showVolumeSheet,
                ),
                _buildBottomActionButton(
                  icon: Icons.auto_awesome_motion_rounded,
                  label: 'Animation',
                  onTap: _showAnimationQuickAction,
                ),
                _buildBottomActionButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  onTap: selectedClip == null ? null : _deleteSelectedClip,
                ),
                _buildBottomActionButton(
                  icon: _snapEnabled ? Icons.grid_on_rounded : Icons.grid_off_rounded,
                  label: _snapEnabled ? 'Snap On' : 'Snap Off',
                  onTap: _toggleSnap,
                ),
                _buildBottomActionButton(
                  icon: _autoFollowPlayhead
                      ? Icons.center_focus_strong_rounded
                      : Icons.center_focus_weak_rounded,
                  label: _autoFollowPlayhead ? 'Follow On' : 'Follow Off',
                  onTap: _toggleAutoFollow,
                ),
                _buildBottomActionButton(
                  icon: Icons.zoom_in_rounded,
                  label: 'Zoom +',
                  onTap: () => _zoomTimeline(24),
                ),
                _buildBottomActionButton(
                  icon: Icons.zoom_out_rounded,
                  label: 'Zoom -',
                  onTap: () => _zoomTimeline(-24),
                ),
                _buildBottomActionButton(
                  icon: Icons.add_box_outlined,
                  label: 'Media',
                  onTap: _showAddMediaSheet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactVideoTrackLane(double width) {
    final track = _engine.videoTrack;
    const laneHeight = 54.0;
    final playheadX = ((_engine.playhead.inMilliseconds / 1000.0) *
            _engine.pixelsPerSecond)
        .clamp(0.0, width - 2);
    return Container(
      width: width,
      height: laneHeight,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF101722), Color(0xFF090D14)],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
      ),
      child: Stack(
        children: [
          if (track.clips.isEmpty)
            Center(
              child: Text(
                'Add a video to begin',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.44),
                  fontSize: 10,
                ),
              ),
            ),
          for (final clip in track.clips)
            _buildCompactVideoClip(track: track, clip: clip, laneHeight: laneHeight),
          Positioned(
            left: playheadX,
            top: 0,
            bottom: 0,
            child: Container(
              width: 2,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactVideoClip({
    required SequencerTrack track,
    required SequencerClip clip,
    required double laneHeight,
  }) {
    final selected = clip.id == _engine.selectedClipId;
    final left =
        (clip.timelineStart.inMilliseconds / 1000.0) * _engine.pixelsPerSecond;
    final clipWidth = math.max(
      56.0,
      (clip.sourceDuration.inMilliseconds / 1000.0) * _engine.pixelsPerSecond,
    );
    final thumbCount = math.max(2, math.min(8, (clipWidth / 34).floor()));

    return Positioned(
      left: left,
      top: 4,
      width: clipWidth,
      height: laneHeight - 8,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _engine.setSelectedClip(clip.id);
          setState(() => _selectedTransitionId = null);
          if (_autoFollowPlayhead) {
            _autoScrollTimelineToPlayhead(animated: true);
          }
        },
        onLongPress: () => unawaited(_showClipQuickActions(clip)),
        onPanStart: (_) => _onClipPanStart(clip),
        onPanUpdate: (d) => _onClipPanUpdate(track, clip, d),
        onPanEnd: (_) => _onClipPanEnd(clip),
        onPanCancel: () => _onClipPanEnd(clip),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: selected
                  ? const [Color(0xFF737E94), Color(0xFF596276)]
                  : const [Color(0xFF5A6478), Color(0xFF485062)],
            ),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.95)
                  : Colors.white.withValues(alpha: 0.2),
              width: selected ? 1.3 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.36),
                      blurRadius: 9,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  for (int i = 0; i < thumbCount; i++)
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i == thumbCount - 1 ? 0 : 1),
                        color: i.isEven
                            ? Colors.white.withValues(alpha: 0.13)
                            : Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                ],
              ),
              Positioned(
                left: 4,
                right: 4,
                bottom: 2,
                child: Text(
                  clip.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.4,
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

  Widget _buildTrackTogglePill({
    required String label,
    required bool active,
    required VoidCallback onTap,
    required Color activeColor,
  }) {
    return Material(
      color: active
          ? activeColor.withValues(alpha: 0.24)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 26,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? activeColor.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.24),
              width: active ? 1.2 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active
                  ? activeColor.withValues(alpha: 0.95)
                  : Colors.white.withValues(alpha: 0.75),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatIcon() {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: const Icon(Icons.chat_bubble_outline_rounded,
          size: 16, color: Colors.white),
    );
  }

  Widget _buildChatBar() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onChatBarTap,
      child: Container(
        height: _kChatBarFixedHeight,
        margin: const EdgeInsets.fromLTRB(2, 0, 2, 0),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.44),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (!_chatInputActive) ...[
              _buildChatIcon(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ask AI for edits, captions, subtitles',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 14,
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                child: TextField(
                  controller: _chatTextController,
                  focusNode: _chatFocusNode,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: 'Ask CapCut AI...',
                    hintStyle: TextStyle(color: Colors.white70),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submitChatMessage(),
                  onTapOutside: (_) => _chatFocusNode.unfocus(),
                ),
              ),
              const SizedBox(width: 8),
              IgnorePointer(
                ignoring: !_chatHasText,
                child: Opacity(
                  opacity: _chatHasText ? 1 : 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _submitChatMessage,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                if (_chatExpanded) {
                  _dismissChatPanel();
                } else {
                  _onChatBarTap();
                }
              },
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                child: Icon(
                  _chatExpanded
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                  size: 19,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatHistoryPanel() {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final panelHeight = math.min(
        _kChatHistoryHeight, MediaQuery.of(context).size.height * 0.48);
    return Positioned(
      left: 12,
      right: 12,
      bottom: _kBottomDockApproxHeight + keyboardInset,
      child: IgnorePointer(
        ignoring: !_chatExpanded,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          offset: _chatExpanded ? Offset.zero : const Offset(0, 0.24),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            opacity: _chatExpanded ? 1 : 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  height: panelHeight,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: _kChatChromeOpacity),
                    borderRadius: BorderRadius.circular(22),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
                        child: Row(
                          children: [
                            const Text(
                              'Chat History',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: _dismissChatPanel,
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      Expanded(
                        child: _chatMessages.isEmpty
                            ? Center(
                                child: Text(
                                  'No chat messages yet.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                itemBuilder: (_, i) =>
                                    _buildChatMessageBubble(_chatMessages[i]),
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemCount: _chatMessages.length,
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
    );
  }

  Widget _buildChatMessageBubble(_EditorChatMessage m) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF3862A1).withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text(
          m.text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            height: 1.25,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomDock() {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildChatBar(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final dockBottomPadding = _kBottomDockApproxHeight + keyboardInset + 12;

    Widget content;
    if (_loadingProject) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      content = Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: keyboardInset + 4),
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final previewMaxByViewport = constraints.maxHeight * 0.37;
                  final previewMaxByReserve = constraints.maxHeight - 156;
                  final previewHeight = math.max(
                    96.0,
                    math.min(
                      248.0,
                      math.max(96.0, math.min(previewMaxByViewport, previewMaxByReserve)),
                    ),
                  );
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                        child: SizedBox(
                          height: previewHeight,
                          child: _buildPreviewStageCard(),
                        ),
                      ),
                      _buildMobileToolContextPanel(),
                      Expanded(child: _buildTimelineSection()),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF030304),
                    const Color(0xFF07080A),
                    const Color(0xFF0A0B0E),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: dockBottomPadding),
              child: content,
            ),
          ),
          _buildChatHistoryPanel(),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildBottomDock(),
          ),
          if (_loadingMedia || _exporting)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _busyLabel ?? 'Working...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
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
      resizeToAvoidBottomInset: true,
      key: const ValueKey('video_sequencer_editor'),
    );
  }
}

class _EditorChatMessage {
  _EditorChatMessage({
    required this.role,
    required this.text,
    required this.createdAtMs,
  });

  final String role;
  final String text;
  final int createdAtMs;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'role': role,
      'text': text,
      'createdAtMs': createdAtMs,
    };
  }

  factory _EditorChatMessage.fromJson(Map<String, dynamic> json) {
    return _EditorChatMessage(
      role: (json['role'] as String?) ?? 'assistant',
      text: (json['text'] as String?) ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.round() ?? 0,
    );
  }
}

class _ClipWaveformPainter extends CustomPainter {
  _ClipWaveformPainter({
    required this.samples,
    required this.color,
  });

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.max(1.0, size.width / (samples.length * 3.2))
      ..strokeCap = StrokeCap.round;

    final centerY = size.height * 0.5;
    final step = size.width / samples.length;
    for (int i = 0; i < samples.length; i++) {
      final x = (i + 0.5) * step;
      final amp = samples[i].clamp(0.0, 1.0);
      final h = math.max(1.0, amp * size.height * 0.45);
      canvas.drawLine(Offset(x, centerY - h), Offset(x, centerY + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ClipWaveformPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.samples.length != samples.length ||
        !identical(oldDelegate.samples, samples);
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.pixelsPerSecond,
    required this.seconds,
    required this.playheadMs,
  });

  final double pixelsPerSecond;
  final int seconds;
  final double playheadMs;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.24)
      ..strokeWidth = 1;
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.62),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );
    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i <= seconds; i++) {
      final x = i * pixelsPerSecond;
      final h = (i % 5 == 0) ? 14.0 : 9.0;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), line);

      if (i % 2 == 0) {
        tp.text = TextSpan(text: '${i}s', style: textStyle);
        tp.layout();
        tp.paint(canvas, Offset(x + 2, 2));
      }
    }

    final playheadX = (playheadMs / 1000.0) * pixelsPerSecond;
    final playheadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.94)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) {
    return oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.seconds != seconds ||
        oldDelegate.playheadMs != playheadMs;
  }
}
