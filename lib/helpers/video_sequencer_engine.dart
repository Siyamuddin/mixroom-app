import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum SequencerTrackType { video, audio }

enum SequencerTransitionType {
  crossDissolve,
  dipToBlack,
}

class SequencerTransition {
  SequencerTransition({
    required this.id,
    required this.fromClipId,
    required this.toClipId,
    required this.duration,
    this.type = SequencerTransitionType.crossDissolve,
  });

  final String id;
  final String fromClipId;
  final String toClipId;
  Duration duration;
  SequencerTransitionType type;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'fromClipId': fromClipId,
      'toClipId': toClipId,
      'durationMs': duration.inMilliseconds,
      'type': type.name,
    };
  }

  factory SequencerTransition.fromJson(Map<String, dynamic> json) {
    SequencerTransitionType parseType(String? raw) {
      if (raw == SequencerTransitionType.dipToBlack.name) {
        return SequencerTransitionType.dipToBlack;
      }
      return SequencerTransitionType.crossDissolve;
    }

    return SequencerTransition(
      id: (json['id'] as String?) ?? '',
      fromClipId: (json['fromClipId'] as String?) ?? '',
      toClipId: (json['toClipId'] as String?) ?? '',
      duration:
          Duration(milliseconds: (json['durationMs'] as num?)?.round() ?? 400),
      type: parseType(json['type'] as String?),
    );
  }
}

class SequencerClip {
  SequencerClip({
    required this.id,
    required this.trackType,
    required this.sourcePath,
    required this.label,
    required this.timelineStart,
    required this.sourceStart,
    required this.sourceDuration,
    required this.sourceTotalDuration,
    this.volume = 1.0,
    this.muted = false,
    this.thumbnailPath,
  });

  final String id;
  final SequencerTrackType trackType;
  final String sourcePath;
  String label;
  Duration timelineStart;
  Duration sourceStart;
  Duration sourceDuration;
  Duration sourceTotalDuration;
  double volume;
  bool muted;
  String? thumbnailPath;

  Duration get timelineEnd => timelineStart + sourceDuration;

  SequencerClip copyWith({
    String? label,
    Duration? timelineStart,
    Duration? sourceStart,
    Duration? sourceDuration,
    Duration? sourceTotalDuration,
    double? volume,
    bool? muted,
    String? thumbnailPath,
  }) {
    return SequencerClip(
      id: id,
      trackType: trackType,
      sourcePath: sourcePath,
      label: label ?? this.label,
      timelineStart: timelineStart ?? this.timelineStart,
      sourceStart: sourceStart ?? this.sourceStart,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      sourceTotalDuration: sourceTotalDuration ?? this.sourceTotalDuration,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'trackType': trackType.name,
      'sourcePath': sourcePath,
      'label': label,
      'timelineStartMs': timelineStart.inMilliseconds,
      'sourceStartMs': sourceStart.inMilliseconds,
      'sourceDurationMs': sourceDuration.inMilliseconds,
      'sourceTotalDurationMs': sourceTotalDuration.inMilliseconds,
      'volume': volume,
      'muted': muted,
      'thumbnailPath': thumbnailPath,
    };
  }

  factory SequencerClip.fromJson(Map<String, dynamic> json) {
    SequencerTrackType parseType(String? raw) {
      if (raw == SequencerTrackType.audio.name) return SequencerTrackType.audio;
      return SequencerTrackType.video;
    }

    return SequencerClip(
      id: (json['id'] as String?) ?? '',
      trackType: parseType(json['trackType'] as String?),
      sourcePath: (json['sourcePath'] as String?) ?? '',
      label: (json['label'] as String?) ?? 'Clip',
      timelineStart: Duration(
          milliseconds: (json['timelineStartMs'] as num?)?.round() ?? 0),
      sourceStart:
          Duration(milliseconds: (json['sourceStartMs'] as num?)?.round() ?? 0),
      sourceDuration: Duration(
          milliseconds: (json['sourceDurationMs'] as num?)?.round() ?? 0),
      sourceTotalDuration: Duration(
          milliseconds: (json['sourceTotalDurationMs'] as num?)?.round() ?? 0),
      volume: ((json['volume'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 2.0),
      muted: (json['muted'] as bool?) ?? false,
      thumbnailPath: json['thumbnailPath'] as String?,
    );
  }
}

class SequencerTrack {
  SequencerTrack({
    required this.id,
    required this.type,
    required this.name,
    this.muted = false,
    this.solo = false,
    List<SequencerClip>? clips,
  }) : clips = clips ?? <SequencerClip>[];

  final String id;
  final SequencerTrackType type;
  String name;
  bool muted;
  bool solo;
  final List<SequencerClip> clips;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'name': name,
      'muted': muted,
      'solo': solo,
      'clips': clips.map((c) => c.toJson()).toList(),
    };
  }

  factory SequencerTrack.fromJson(Map<String, dynamic> json) {
    SequencerTrackType parseType(String? raw) {
      if (raw == SequencerTrackType.audio.name) return SequencerTrackType.audio;
      return SequencerTrackType.video;
    }

    final rawClips = (json['clips'] as List?) ?? <dynamic>[];
    return SequencerTrack(
      id: (json['id'] as String?) ?? '',
      type: parseType(json['type'] as String?),
      name: (json['name'] as String?) ?? 'Track',
      muted: (json['muted'] as bool?) ?? false,
      solo: (json['solo'] as bool?) ?? false,
      clips: rawClips
          .whereType<Map>()
          .map((raw) => SequencerClip.fromJson(Map<String, dynamic>.from(raw)))
          .toList(),
    );
  }
}

class VideoSequencerSnapshot {
  VideoSequencerSnapshot({
    required this.tracks,
    required this.transitions,
    required this.playheadMs,
    required this.pixelsPerSecond,
    this.selectedClipId,
  });

  final List<SequencerTrack> tracks;
  final List<SequencerTransition> transitions;
  final int playheadMs;
  final double pixelsPerSecond;
  final String? selectedClipId;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'transitions': transitions.map((t) => t.toJson()).toList(),
      'playheadMs': playheadMs,
      'pixelsPerSecond': pixelsPerSecond,
      'selectedClipId': selectedClipId,
    };
  }

  factory VideoSequencerSnapshot.fromJson(Map<String, dynamic> json) {
    final rawTracks = (json['tracks'] as List?) ?? <dynamic>[];
    final rawTransitions = (json['transitions'] as List?) ?? <dynamic>[];
    return VideoSequencerSnapshot(
      tracks: rawTracks
          .whereType<Map>()
          .map((raw) => SequencerTrack.fromJson(Map<String, dynamic>.from(raw)))
          .toList(),
      transitions: rawTransitions
          .whereType<Map>()
          .map((raw) =>
              SequencerTransition.fromJson(Map<String, dynamic>.from(raw)))
          .toList(),
      playheadMs: (json['playheadMs'] as num?)?.round() ?? 0,
      pixelsPerSecond: ((json['pixelsPerSecond'] as num?)?.toDouble() ?? 120.0)
          .clamp(40.0, 360.0),
      selectedClipId: json['selectedClipId'] as String?,
    );
  }
}

class VideoSequencerEngine extends ChangeNotifier {
  static const Duration minClipDuration = Duration(milliseconds: 250);
  static const Duration minTransitionDuration = Duration(milliseconds: 80);
  static const Duration maxTransitionDuration = Duration(milliseconds: 1500);

  VideoSequencerEngine({VideoSequencerSnapshot? initial}) {
    if (initial != null && initial.tracks.isNotEmpty) {
      _tracks = initial.tracks;
      _transitions = initial.transitions;
      _playhead = Duration(milliseconds: math.max(0, initial.playheadMs));
      _pixelsPerSecond = initial.pixelsPerSecond.clamp(40.0, 360.0);
      _selectedClipId = initial.selectedClipId;
    } else {
      _tracks = <SequencerTrack>[
        SequencerTrack(
          id: _nextId('track'),
          type: SequencerTrackType.video,
          name: 'Video',
        ),
        SequencerTrack(
          id: _nextId('track'),
          type: SequencerTrackType.audio,
          name: 'Audio',
        ),
      ];
      _transitions = <SequencerTransition>[];
      _playhead = Duration.zero;
      _pixelsPerSecond = 120.0;
    }
    _sortAllTracks();
    _sanitizeTransitions();
  }

  late List<SequencerTrack> _tracks;
  late List<SequencerTransition> _transitions;
  Duration _playhead = Duration.zero;
  bool _isPlaying = false;
  double _pixelsPerSecond = 120.0;
  String? _selectedClipId;
  int _idCounter = 0;

  List<SequencerTrack> get tracks => _tracks;
  List<SequencerTrack> get videoTracks => _tracks
      .where((t) => t.type == SequencerTrackType.video)
      .toList(growable: false);
  List<SequencerTrack> get audioTracks => _tracks
      .where((t) => t.type == SequencerTrackType.audio)
      .toList(growable: false);
  List<SequencerTransition> get videoTransitions => _transitions;
  Duration get playhead => _playhead;
  bool get isPlaying => _isPlaying;
  double get pixelsPerSecond => _pixelsPerSecond;
  String? get selectedClipId => _selectedClipId;

  SequencerTrack get videoTrack => _ensureTrack(SequencerTrackType.video);
  SequencerTrack get audioTrack => _ensureTrack(SequencerTrackType.audio);

  Duration get totalDuration {
    int maxMs = 0;
    for (final track in _tracks) {
      for (final clip in track.clips) {
        maxMs = math.max(maxMs, clip.timelineEnd.inMilliseconds);
      }
    }
    return Duration(milliseconds: maxMs);
  }

  VideoSequencerSnapshot toSnapshot() {
    return VideoSequencerSnapshot(
      tracks: _tracks
          .map((t) => SequencerTrack(
                id: t.id,
                type: t.type,
                name: t.name,
                muted: t.muted,
                solo: t.solo,
                clips: t.clips.map((c) => c.copyWith()).toList(),
              ))
          .toList(),
      transitions: _transitions
          .map((t) => SequencerTransition(
                id: t.id,
                fromClipId: t.fromClipId,
                toClipId: t.toClipId,
                duration: t.duration,
                type: t.type,
              ))
          .toList(),
      playheadMs: _playhead.inMilliseconds,
      pixelsPerSecond: _pixelsPerSecond,
      selectedClipId: _selectedClipId,
    );
  }

  void setPixelsPerSecond(double value) {
    final next = value.clamp(40.0, 360.0);
    if ((_pixelsPerSecond - next).abs() < 0.01) return;
    _pixelsPerSecond = next;
    notifyListeners();
  }

  void setSelectedClip(String? clipId) {
    if (_selectedClipId == clipId) return;
    _selectedClipId = clipId;
    notifyListeners();
  }

  void seek(Duration value) {
    final max = totalDuration.inMilliseconds;
    final ms = value.inMilliseconds.clamp(0, math.max(max, 0)).toInt();
    final next = Duration(milliseconds: ms);
    if (next == _playhead) return;
    _playhead = next;
    notifyListeners();
  }

  void restart() {
    _playhead = Duration.zero;
    _isPlaying = false;
    notifyListeners();
  }

  void play() {
    if (_isPlaying) return;
    _isPlaying = true;
    notifyListeners();
  }

  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    notifyListeners();
  }

  void advanceBy(Duration delta) {
    if (!_isPlaying) return;
    if (delta <= Duration.zero) return;
    final next = _playhead + delta;
    final max = totalDuration;
    if (next >= max) {
      _playhead = max;
      _isPlaying = false;
      notifyListeners();
      return;
    }
    _playhead = next;
    notifyListeners();
  }

  SequencerClip addClip({
    required SequencerTrackType type,
    required String sourcePath,
    required String label,
    required Duration sourceDuration,
    Duration sourceStart = Duration.zero,
    Duration? timelineStart,
    Duration? sourceTotalDuration,
    String? thumbnailPath,
  }) {
    final typedTracks =
        _tracks.where((t) => t.type == type).toList(growable: false);
    final track =
        typedTracks.isNotEmpty ? typedTracks.last : _ensureTrack(type);
    final duration =
        sourceDuration < minClipDuration ? minClipDuration : sourceDuration;
    final maxSource = sourceTotalDuration ?? sourceDuration;
    final preferred = timelineStart ?? _playhead;
    final start = _resolveNonOverlappingStart(track, preferred, duration);

    final clip = SequencerClip(
      id: _nextId('clip'),
      trackType: type,
      sourcePath: sourcePath,
      label: label,
      timelineStart: start,
      sourceStart: sourceStart,
      sourceDuration: duration,
      sourceTotalDuration: maxSource,
      thumbnailPath: thumbnailPath,
    );
    track.clips.add(clip);
    _sortTrack(track);
    _selectedClipId = clip.id;
    if (type == SequencerTrackType.video) _sanitizeTransitions();
    notifyListeners();
    return clip;
  }

  bool removeSelectedClip() {
    final clipId = _selectedClipId;
    if (clipId == null) return false;
    return removeClip(clipId);
  }

  bool removeClip(String clipId) {
    for (final track in _tracks) {
      final idx = track.clips.indexWhere((c) => c.id == clipId);
      if (idx == -1) continue;
      final removed = track.clips[idx];
      track.clips.removeAt(idx);
      if (_selectedClipId == clipId) _selectedClipId = null;
      if (removed.trackType == SequencerTrackType.video) {
        _removeTransitionsTouchingClip(clipId);
        _sanitizeTransitions();
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  bool moveClip(String clipId, Duration desiredStart) {
    final located = _findClip(clipId);
    if (located == null) return false;
    final track = located.track;
    final clip = located.clip;

    final safeStart =
        Duration(milliseconds: math.max(0, desiredStart.inMilliseconds));
    final resolved = _resolveNonOverlappingStart(
      track,
      safeStart,
      clip.sourceDuration,
      excludingId: clip.id,
    );
    if (resolved == clip.timelineStart) return false;
    clip.timelineStart = resolved;
    _sortTrack(track);
    if (track.type == SequencerTrackType.video) _sanitizeTransitions();
    notifyListeners();
    return true;
  }

  bool setClipVolume(String clipId, double volume) {
    final located = _findClip(clipId);
    if (located == null) return false;
    final next = volume.clamp(0.0, 2.0);
    if ((located.clip.volume - next).abs() < 0.0001) return false;
    located.clip.volume = next;
    notifyListeners();
    return true;
  }

  bool setClipMuted(String clipId, bool muted) {
    final located = _findClip(clipId);
    if (located == null) return false;
    if (located.clip.muted == muted) return false;
    located.clip.muted = muted;
    notifyListeners();
    return true;
  }

  bool setClipThumbnailPath(String clipId, String? thumbnailPath) {
    final located = _findClip(clipId);
    if (located == null) return false;
    if (located.clip.thumbnailPath == thumbnailPath) return false;
    located.clip.thumbnailPath = thumbnailPath;
    notifyListeners();
    return true;
  }

  bool setTrackMuted(String trackId, bool muted) {
    final track = _trackById(trackId);
    if (track == null) return false;
    if (track.muted == muted) return false;
    track.muted = muted;
    notifyListeners();
    return true;
  }

  bool setTrackSolo(String trackId, bool solo) {
    final track = _trackById(trackId);
    if (track == null) return false;
    if (track.solo == solo) return false;
    track.solo = solo;
    notifyListeners();
    return true;
  }

  bool isTrackAudibleById(String trackId) {
    final track = _trackById(trackId);
    if (track == null) return false;
    final hasSolo = _tracks.any((t) => t.solo);
    if (hasSolo) return track.solo;
    return !track.muted;
  }

  bool isTrackAudible(SequencerTrackType type) {
    final track = _trackByType(type);
    if (track == null) return false;
    return isTrackAudibleById(track.id);
  }

  SequencerTrack addTrack(SequencerTrackType type, {String? name}) {
    final nextIndex = _tracks.where((t) => t.type == type).length + 1;
    final track = SequencerTrack(
      id: _nextId('track'),
      type: type,
      name: name?.trim().isNotEmpty == true
          ? name!.trim()
          : '${type == SequencerTrackType.video ? 'Video' : 'Audio'} $nextIndex',
    );
    _tracks.add(track);
    notifyListeners();
    return track;
  }

  bool removeTrack(String trackId) {
    final trackIdx = _tracks.indexWhere((t) => t.id == trackId);
    if (trackIdx == -1) return false;
    final track = _tracks[trackIdx];
    final sameType =
        _tracks.where((t) => t.type == track.type).toList(growable: false);
    if (sameType.length <= 1) return false;

    final target = sameType.firstWhere((t) => t.id != track.id);
    if (track.clips.isNotEmpty) {
      for (final clip in track.clips) {
        final resolved = _resolveNonOverlappingStart(
          target,
          clip.timelineStart,
          clip.sourceDuration,
        );
        clip.timelineStart = resolved;
        target.clips.add(clip);
      }
      _sortTrack(target);
    }

    _tracks.removeAt(trackIdx);
    if (track.type == SequencerTrackType.video) {
      _sanitizeTransitions();
    }
    notifyListeners();
    return true;
  }

  bool moveClipToTrack(
    String clipId,
    String targetTrackId, {
    Duration? desiredStart,
  }) {
    final located = _findClip(clipId);
    final target = _trackById(targetTrackId);
    if (located == null || target == null) return false;
    if (located.track.type != target.type) return false;

    final start = desiredStart ?? located.clip.timelineStart;
    final resolved = _resolveNonOverlappingStart(
      target,
      Duration(milliseconds: math.max(0, start.inMilliseconds)),
      located.clip.sourceDuration,
      excludingId: located.clip.id,
    );

    final sourceTrack = located.track;
    final clip = located.clip;
    if (sourceTrack.id == target.id && resolved == clip.timelineStart) {
      return false;
    }

    sourceTrack.clips.removeWhere((c) => c.id == clip.id);
    clip.timelineStart = resolved;
    target.clips.add(clip);
    _sortTrack(sourceTrack);
    _sortTrack(target);
    if (target.type == SequencerTrackType.video) {
      _sanitizeTransitions();
    }
    notifyListeners();
    return true;
  }

  bool moveClipToNeighborTrack(String clipId, int direction,
      {Duration? desiredStart}) {
    if (direction == 0) return false;
    final located = _findClip(clipId);
    if (located == null) return false;
    final pool = _tracks
        .where((t) => t.type == located.track.type)
        .toList(growable: false);
    final idx = pool.indexWhere((t) => t.id == located.track.id);
    if (idx == -1) return false;
    final nextIdx = (idx + direction).clamp(0, pool.length - 1);
    if (nextIdx == idx) return false;
    return moveClipToTrack(
      clipId,
      pool[nextIdx].id,
      desiredStart: desiredStart,
    );
  }

  bool trimClip(
    String clipId, {
    Duration? newSourceStart,
    Duration? newSourceDuration,
  }) {
    final located = _findClip(clipId);
    if (located == null) return false;
    final clip = located.clip;

    final start = newSourceStart ?? clip.sourceStart;
    final duration = newSourceDuration ?? clip.sourceDuration;
    final boundedStart =
        Duration(milliseconds: math.max(0, start.inMilliseconds));
    final boundedDuration = Duration(
      milliseconds: math.max(
        minClipDuration.inMilliseconds,
        duration.inMilliseconds,
      ),
    );

    final maxEndMs = math.max(
      boundedStart.inMilliseconds + minClipDuration.inMilliseconds,
      clip.sourceTotalDuration.inMilliseconds,
    );
    final maxAllowedEnd = math.min(
      boundedStart.inMilliseconds + boundedDuration.inMilliseconds,
      maxEndMs,
    );
    final finalDuration = Duration(
      milliseconds: math.max(
        minClipDuration.inMilliseconds,
        maxAllowedEnd - boundedStart.inMilliseconds,
      ),
    );

    if (clip.sourceStart == boundedStart &&
        clip.sourceDuration == finalDuration) {
      return false;
    }

    clip.sourceStart = boundedStart;
    clip.sourceDuration = finalDuration;

    final track = located.track;
    clip.timelineStart = _resolveNonOverlappingStart(
      track,
      clip.timelineStart,
      clip.sourceDuration,
      excludingId: clip.id,
    );
    _sortTrack(track);
    if (track.type == SequencerTrackType.video) _sanitizeTransitions();
    notifyListeners();
    return true;
  }

  bool splitSelectedClip() {
    final clipId = _selectedClipId;
    if (clipId == null) return false;
    return splitClip(clipId, _playhead);
  }

  SequencerClip? duplicateClip(
    String clipId, {
    Duration gap = const Duration(milliseconds: 120),
  }) {
    final located = _findClip(clipId);
    if (located == null) return null;
    final source = located.clip;
    final track = located.track;

    final desiredStart = source.timelineEnd + gap;
    final resolvedStart = _resolveNonOverlappingStart(
      track,
      desiredStart,
      source.sourceDuration,
    );

    final duplicate = SequencerClip(
      id: _nextId('clip'),
      trackType: source.trackType,
      sourcePath: source.sourcePath,
      label: source.label,
      timelineStart: resolvedStart,
      sourceStart: source.sourceStart,
      sourceDuration: source.sourceDuration,
      sourceTotalDuration: source.sourceTotalDuration,
      volume: source.volume,
      muted: source.muted,
      thumbnailPath: source.thumbnailPath,
    );
    track.clips.add(duplicate);
    _sortTrack(track);
    _selectedClipId = duplicate.id;
    if (track.type == SequencerTrackType.video) _sanitizeTransitions();
    notifyListeners();
    return duplicate;
  }

  bool splitClip(String clipId, Duration splitAtTimeline) {
    final located = _findClip(clipId);
    if (located == null) return false;
    final clip = located.clip;
    final track = located.track;

    if (splitAtTimeline <= clip.timelineStart ||
        splitAtTimeline >= clip.timelineEnd) {
      return false;
    }

    final leftDuration = splitAtTimeline - clip.timelineStart;
    final rightDuration = clip.sourceDuration - leftDuration;

    if (leftDuration < minClipDuration || rightDuration < minClipDuration) {
      return false;
    }

    final rightClip = SequencerClip(
      id: _nextId('clip'),
      trackType: clip.trackType,
      sourcePath: clip.sourcePath,
      label: '${clip.label} (Part 2)',
      timelineStart: splitAtTimeline,
      sourceStart: clip.sourceStart + leftDuration,
      sourceDuration: rightDuration,
      sourceTotalDuration: clip.sourceTotalDuration,
      volume: clip.volume,
      muted: clip.muted,
      thumbnailPath: clip.thumbnailPath,
    );

    clip.sourceDuration = leftDuration;
    track.clips.add(rightClip);
    _sortTrack(track);
    _selectedClipId = rightClip.id;
    if (track.type == SequencerTrackType.video) _sanitizeTransitions();
    notifyListeners();
    return true;
  }

  SequencerTransition? addOrUpdateTransition({
    required String fromClipId,
    required String toClipId,
    Duration duration = const Duration(milliseconds: 450),
    SequencerTransitionType type = SequencerTransitionType.crossDissolve,
  }) {
    final from = _videoClipById(fromClipId);
    final to = _videoClipById(toClipId);
    if (from == null || to == null) return null;
    if (!_areAdjacentInVideoTrack(from.id, to.id)) return null;

    final maxAllowed = _maxTransitionDurationForPair(from, to);
    if (maxAllowed <= 40) return null;
    final clampedDuration = Duration(
      milliseconds: duration.inMilliseconds.clamp(
        minTransitionDuration.inMilliseconds,
        maxAllowed,
      ),
    );

    final existing = _transitions.firstWhere(
      (t) => t.fromClipId == from.id && t.toClipId == to.id,
      orElse: () => SequencerTransition(
        id: '',
        fromClipId: '',
        toClipId: '',
        duration: Duration.zero,
      ),
    );
    if (existing.id.isNotEmpty) {
      existing.duration = clampedDuration;
      existing.type = type;
      notifyListeners();
      return existing;
    }

    final transition = SequencerTransition(
      id: _nextId('transition'),
      fromClipId: from.id,
      toClipId: to.id,
      duration: clampedDuration,
      type: type,
    );
    _transitions.add(transition);
    _sanitizeTransitions();
    notifyListeners();
    return transition;
  }

  bool removeTransition(String transitionId) {
    final idx = _transitions.indexWhere((t) => t.id == transitionId);
    if (idx == -1) return false;
    _transitions.removeAt(idx);
    notifyListeners();
    return true;
  }

  bool setTransitionDuration(String transitionId, Duration duration) {
    final transition = transitionById(transitionId);
    if (transition == null) return false;
    final from = _videoClipById(transition.fromClipId);
    final to = _videoClipById(transition.toClipId);
    if (from == null || to == null) return false;
    final maxAllowed = _maxTransitionDurationForPair(from, to);
    if (maxAllowed <= 40) return false;

    final clamped = Duration(
      milliseconds: duration.inMilliseconds.clamp(
        minTransitionDuration.inMilliseconds,
        maxAllowed,
      ),
    );
    if (clamped == transition.duration) return false;
    transition.duration = clamped;
    notifyListeners();
    return true;
  }

  bool setTransitionType(
      String transitionId, SequencerTransitionType transitionType) {
    final transition = transitionById(transitionId);
    if (transition == null) return false;
    if (transition.type == transitionType) return false;
    transition.type = transitionType;
    notifyListeners();
    return true;
  }

  SequencerTransition? transitionById(String id) {
    for (final t in _transitions) {
      if (t.id == id) return t;
    }
    return null;
  }

  SequencerTransition? transitionBetweenClips(
      String fromClipId, String toClipId) {
    for (final t in _transitions) {
      if (t.fromClipId == fromClipId && t.toClipId == toClipId) {
        return t;
      }
    }
    return null;
  }

  SequencerClip? selectedClip() {
    final id = _selectedClipId;
    if (id == null) return null;
    return _findClip(id)?.clip;
  }

  SequencerClip? previousVideoClip(String clipId) {
    final located = _findClip(clipId);
    if (located == null || located.track.type != SequencerTrackType.video) {
      return null;
    }
    final clips = List<SequencerClip>.from(located.track.clips)
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    final idx = clips.indexWhere((c) => c.id == clipId);
    if (idx <= 0) return null;
    return clips[idx - 1];
  }

  SequencerClip? nextVideoClip(String clipId) {
    final located = _findClip(clipId);
    if (located == null || located.track.type != SequencerTrackType.video) {
      return null;
    }
    final clips = List<SequencerClip>.from(located.track.clips)
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    final idx = clips.indexWhere((c) => c.id == clipId);
    if (idx < 0 || idx >= clips.length - 1) return null;
    return clips[idx + 1];
  }

  SequencerClip? clipAtPlayhead(SequencerTrackType type) {
    final scoped = _tracks.where((t) => t.type == type).toList(growable: false);
    final tracksInZOrder =
        type == SequencerTrackType.video ? scoped.reversed : scoped;
    for (final track in tracksInZOrder) {
      for (final clip in track.clips) {
        if (_playhead >= clip.timelineStart && _playhead < clip.timelineEnd) {
          return clip;
        }
      }
    }
    return null;
  }

  List<SequencerClip> clipsAtPlayhead(SequencerTrackType type) {
    final result = <SequencerClip>[];
    final scoped = _tracks.where((t) => t.type == type).toList(growable: false);
    final tracksInZOrder =
        type == SequencerTrackType.video ? scoped.reversed : scoped;
    for (final track in tracksInZOrder) {
      for (final clip in track.clips) {
        if (_playhead >= clip.timelineStart && _playhead < clip.timelineEnd) {
          result.add(clip);
        }
      }
    }
    return result;
  }

  Duration localSourcePositionForClip(
      SequencerClip clip, Duration timelinePos) {
    final local = timelinePos - clip.timelineStart;
    final raw = clip.sourceStart + local;
    final minMs = clip.sourceStart.inMilliseconds;
    final maxMs = (clip.sourceStart + clip.sourceDuration).inMilliseconds;
    final bounded = raw.inMilliseconds.clamp(minMs, maxMs).toInt();
    return Duration(milliseconds: bounded);
  }

  SequencerClip? videoClipById(String clipId) => _videoClipById(clipId);

  int maxTransitionDurationForPairIds(String fromClipId, String toClipId) {
    final from = _videoClipById(fromClipId);
    final to = _videoClipById(toClipId);
    if (from == null || to == null) return 0;
    return _maxTransitionDurationForPair(from, to);
  }

  SequencerTrack? trackForClip(String clipId) => _findClip(clipId)?.track;

  _TrackClipRef? _findClip(String clipId) {
    for (final track in _tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) {
          return _TrackClipRef(track: track, clip: clip);
        }
      }
    }
    return null;
  }

  SequencerClip? _videoClipById(String clipId) {
    for (final track in _tracks) {
      if (track.type != SequencerTrackType.video) continue;
      for (final clip in track.clips) {
        if (clip.id == clipId) return clip;
      }
    }
    return null;
  }

  bool _areAdjacentInVideoTrack(String fromClipId, String toClipId) {
    final fromRef = _findClip(fromClipId);
    final toRef = _findClip(toClipId);
    if (fromRef == null || toRef == null) return false;
    if (fromRef.track.id != toRef.track.id) return false;
    if (fromRef.track.type != SequencerTrackType.video) return false;

    final clips = List<SequencerClip>.from(fromRef.track.clips)
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    final fromIdx = clips.indexWhere((c) => c.id == fromClipId);
    if (fromIdx < 0 || fromIdx >= clips.length - 1) return false;
    return clips[fromIdx + 1].id == toClipId;
  }

  int _maxTransitionDurationForPair(SequencerClip a, SequencerClip b) {
    final aMs = a.sourceDuration.inMilliseconds;
    final bMs = b.sourceDuration.inMilliseconds;
    final pairMs = math.min(aMs, bMs);
    final adaptive = (pairMs * 0.45).floor();
    return math.min(
        maxTransitionDuration.inMilliseconds, math.max(40, adaptive));
  }

  void _removeTransitionsTouchingClip(String clipId) {
    _transitions.removeWhere(
      (t) => t.fromClipId == clipId || t.toClipId == clipId,
    );
  }

  void _sanitizeTransitions() {
    final validPairs = <String>{};
    final toRemove = <String>{};

    for (final t in _transitions) {
      final from = _videoClipById(t.fromClipId);
      final to = _videoClipById(t.toClipId);
      final pairKey = '${t.fromClipId}->${t.toClipId}';
      if (from == null || to == null) {
        toRemove.add(t.id);
        continue;
      }
      if (!_areAdjacentInVideoTrack(from.id, to.id)) {
        toRemove.add(t.id);
        continue;
      }
      if (validPairs.contains(pairKey)) {
        toRemove.add(t.id);
        continue;
      }

      validPairs.add(pairKey);
      final maxAllowed = _maxTransitionDurationForPair(from, to);
      t.duration = Duration(
        milliseconds: t.duration.inMilliseconds.clamp(
          minTransitionDuration.inMilliseconds,
          maxAllowed,
        ),
      );
    }

    if (toRemove.isNotEmpty) {
      _transitions.removeWhere((t) => toRemove.contains(t.id));
    }
  }

  SequencerTrack? _trackByType(SequencerTrackType type) {
    for (final track in _tracks) {
      if (track.type == type) return track;
    }
    return null;
  }

  SequencerTrack? _trackById(String id) {
    for (final track in _tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  SequencerTrack _ensureTrack(SequencerTrackType type) {
    final existing = _trackByType(type);
    if (existing != null) return existing;
    final track = SequencerTrack(
      id: _nextId('track'),
      type: type,
      name: type == SequencerTrackType.video ? 'Video 1' : 'Audio 1',
    );
    _tracks.add(track);
    return track;
  }

  String _nextId(String prefix) {
    _idCounter += 1;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
  }

  void _sortTrack(SequencerTrack track) {
    track.clips.sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
  }

  void _sortAllTracks() {
    for (final t in _tracks) {
      _sortTrack(t);
    }
  }

  Duration _resolveNonOverlappingStart(
    SequencerTrack track,
    Duration desiredStart,
    Duration duration, {
    String? excludingId,
  }) {
    final clips = track.clips.where((c) => c.id != excludingId).toList()
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    var current =
        Duration(milliseconds: math.max(0, desiredStart.inMilliseconds));
    for (final clip in clips) {
      final desiredEnd = current + duration;
      if (desiredEnd <= clip.timelineStart) break;
      if (current >= clip.timelineEnd) continue;
      current = clip.timelineEnd;
    }
    return current;
  }
}

class _TrackClipRef {
  _TrackClipRef({required this.track, required this.clip});

  final SequencerTrack track;
  final SequencerClip clip;
}
