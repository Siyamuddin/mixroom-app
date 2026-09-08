import 'dart:collection';
import 'package:flutter/foundation.dart';

const double kWaveformDetailTileDurationMs = 2000.0;
const int kWaveformDetailSampleRate = 8000;
const int kWaveformDetailMaxCacheBytes = 16 * 1024 * 1024;
const double kWaveformDetailMinimumPixelsPerMs = 0.5;

@immutable
class WaveformDetailSourceRange {
  const WaveformDetailSourceRange(this.startMs, this.endMs);

  final double startMs;
  final double endMs;
}

WaveformDetailSourceRange? waveformDetailSourceRangeForTimelineIntersection({
  required double clipStartMs,
  required double timelineDurationMs,
  required double trimStartMs,
  required double trimEndMs,
  required double sourceDurationMs,
  required bool isReversed,
  required double viewportStartMs,
  required double viewportEndMs,
}) {
  if (!clipStartMs.isFinite ||
      !timelineDurationMs.isFinite ||
      timelineDurationMs <= 0.0 ||
      !trimStartMs.isFinite ||
      !trimEndMs.isFinite ||
      trimEndMs <= trimStartMs ||
      !sourceDurationMs.isFinite ||
      sourceDurationMs <= 0.0 ||
      !viewportStartMs.isFinite ||
      !viewportEndMs.isFinite ||
      viewportEndMs <= viewportStartMs) {
    return null;
  }
  final clipEndMs = clipStartMs + timelineDurationMs;
  final visibleStartMs = viewportStartMs
      .clamp(clipStartMs, clipEndMs)
      .toDouble();
  final visibleEndMs = viewportEndMs.clamp(clipStartMs, clipEndMs).toDouble();
  if (visibleEndMs <= visibleStartMs) return null;
  final rawSpanMs = trimEndMs - trimStartMs;
  final startRatio = ((visibleStartMs - clipStartMs) / timelineDurationMs)
      .clamp(0.0, 1.0)
      .toDouble();
  final endRatio = ((visibleEndMs - clipStartMs) / timelineDurationMs)
      .clamp(startRatio, 1.0)
      .toDouble();
  final firstSourceMs = isReversed
      ? trimEndMs - rawSpanMs * endRatio
      : trimStartMs + rawSpanMs * startRatio;
  final lastSourceMs = isReversed
      ? trimEndMs - rawSpanMs * startRatio
      : trimStartMs + rawSpanMs * endRatio;
  final startMs = firstSourceMs.clamp(0.0, sourceDurationMs).toDouble();
  final endMs = lastSourceMs.clamp(startMs, sourceDurationMs).toDouble();
  if (endMs <= startMs) return null;
  return WaveformDetailSourceRange(startMs, endMs);
}

List<int> waveformDetailTileIndicesForRange({
  required double sourceStartMs,
  required double sourceEndMs,
  required double sourceDurationMs,
  bool includeAdjacentPrefetch = true,
}) {
  if (!sourceStartMs.isFinite ||
      !sourceEndMs.isFinite ||
      !sourceDurationMs.isFinite ||
      sourceDurationMs <= 0.0 ||
      sourceEndMs <= sourceStartMs) {
    return const <int>[];
  }
  final sourceLastTile =
      ((sourceDurationMs - 0.000001) / kWaveformDetailTileDurationMs)
          .floor()
          .clamp(0, 1 << 30)
          .toInt();
  final firstVisibleTile = (sourceStartMs / kWaveformDetailTileDurationMs)
      .floor()
      .clamp(0, sourceLastTile)
      .toInt();
  final lastVisibleTile =
      ((sourceEndMs - 0.000001) / kWaveformDetailTileDurationMs)
          .floor()
          .clamp(firstVisibleTile, sourceLastTile)
          .toInt();
  final indices = <int>[
    for (var index = firstVisibleTile; index <= lastVisibleTile; index++) index,
  ];
  if (includeAdjacentPrefetch && firstVisibleTile > 0) {
    indices.add(firstVisibleTile - 1);
  }
  if (includeAdjacentPrefetch && lastVisibleTile < sourceLastTile) {
    indices.add(lastVisibleTile + 1);
  }
  return indices;
}

@immutable
class WaveformDetailSource {
  const WaveformDetailSource({
    required this.path,
    required this.cacheKey,
    required this.durationMs,
  });

  final String path;
  final String cacheKey;
  final double durationMs;
}

@immutable
class WaveformDetailTileRequest {
  const WaveformDetailTileRequest({
    required this.source,
    required this.tileIndex,
  });

  final WaveformDetailSource source;
  final int tileIndex;

  double get startMs => tileIndex * kWaveformDetailTileDurationMs;

  double get durationMs => (source.durationMs - startMs)
      .clamp(0.0, kWaveformDetailTileDurationMs)
      .toDouble();

  String get key => '${source.cacheKey}|$tileIndex';
}

@immutable
class WaveformDetailTile {
  const WaveformDetailTile({
    required this.sourceKey,
    required this.tileIndex,
    required this.startMs,
    required this.sampleRate,
    required this.amplitudes,
  });

  final String sourceKey;
  final int tileIndex;
  final double startMs;
  final int sampleRate;
  final Float32List amplitudes;

  int get payloadBytes => amplitudes.lengthInBytes;

  double get endMs => startMs + (amplitudes.length * 1000.0 / sampleRate);

  double? peakForRange(double rangeStartMs, double rangeEndMs) {
    if (amplitudes.isEmpty || rangeEndMs <= startMs || rangeStartMs >= endMs) {
      return null;
    }
    final start = rangeStartMs.clamp(startMs, endMs).toDouble();
    final end = rangeEndMs.clamp(start, endMs).toDouble();
    var first = (((start - startMs) * sampleRate) / 1000.0).floor();
    var last = (((end - startMs) * sampleRate) / 1000.0).ceil();
    first = first.clamp(0, amplitudes.length - 1);
    last = last.clamp(first + 1, amplitudes.length);
    var peak = 0.0;
    for (var index = first; index < last; index++) {
      final value = amplitudes[index];
      if (value > peak) peak = value;
    }
    return peak;
  }
}

abstract interface class WaveformDetailLookup implements Listenable {
  double? peakForSourceRange(
    String sourcePath,
    double sourceStartMs,
    double sourceEndMs,
  );
}

typedef WaveformDetailTileLoader =
    Future<WaveformDetailTile?> Function(WaveformDetailTileRequest request);

class WaveformDetailProvider extends ChangeNotifier
    implements WaveformDetailLookup {
  WaveformDetailProvider({
    required WaveformDetailTileLoader loadTile,
    required bool Function() overviewWorkPending,
    this.maxCacheBytes = kWaveformDetailMaxCacheBytes,
  }) : _loadTile = loadTile,
       _overviewWorkPending = overviewWorkPending;

  final WaveformDetailTileLoader _loadTile;
  final bool Function() _overviewWorkPending;
  final int maxCacheBytes;
  final LinkedHashMap<String, WaveformDetailTile> _cache =
      LinkedHashMap<String, WaveformDetailTile>();
  final Map<String, String> _sourceKeyByPath = <String, String>{};
  final LinkedHashMap<String, WaveformDetailTileRequest> _desired =
      LinkedHashMap<String, WaveformDetailTileRequest>();

  bool _detailJobActive = false;
  bool _disposed = false;
  int _generation = 0;
  int _mutationDepth = 0;
  int _cachePayloadBytes = 0;

  @visibleForTesting
  int get cachePayloadBytes => _cachePayloadBytes;

  @visibleForTesting
  int get cachedTileCount => _cache.length;

  @visibleForTesting
  bool get detailJobActive => _detailJobActive;

  @visibleForTesting
  int get desiredTileCount => _desired.length;

  void requestTiles(Iterable<WaveformDetailTileRequest> requests) {
    if (_disposed) return;
    _desired.clear();
    for (final request in requests) {
      if (request.tileIndex < 0 || request.durationMs <= 0.0) continue;
      _sourceKeyByPath[request.source.path] = request.source.cacheKey;
      if (!_cache.containsKey(request.key)) {
        _desired[request.key] = request;
      } else {
        _touch(request.key);
      }
    }
    _pump();
  }

  void resumeAfterOverviewWork() {
    if (_disposed) return;
    _pump();
  }

  void beginMutation() {
    if (_disposed) return;
    _mutationDepth++;
  }

  void endMutation() {
    if (_disposed) return;
    if (_mutationDepth <= 0) return;
    _mutationDepth--;
    if (_mutationDepth == 0) {
      _pump();
    }
  }

  void clear() {
    if (_disposed) return;
    _generation++;
    _desired.clear();
    _cache.clear();
    _sourceKeyByPath.clear();
    _cachePayloadBytes = 0;
    notifyListeners();
  }

  @override
  double? peakForSourceRange(
    String sourcePath,
    double sourceStartMs,
    double sourceEndMs,
  ) {
    if (_disposed ||
        !sourceStartMs.isFinite ||
        !sourceEndMs.isFinite ||
        sourceEndMs <= sourceStartMs) {
      return null;
    }
    final sourceKey = _sourceKeyByPath[sourcePath];
    if (sourceKey == null) return null;
    final firstTile = (sourceStartMs / kWaveformDetailTileDurationMs).floor();
    final lastTile = ((sourceEndMs - 0.000001) / kWaveformDetailTileDurationMs)
        .floor();
    var peak = 0.0;
    for (var tileIndex = firstTile; tileIndex <= lastTile; tileIndex++) {
      final key = '$sourceKey|$tileIndex';
      final tile = _cache[key];
      if (tile == null) return null;
      final tileStart = tileIndex * kWaveformDetailTileDurationMs;
      final partStart = sourceStartMs
          .clamp(tileStart, tileStart + kWaveformDetailTileDurationMs)
          .toDouble();
      final partEnd = sourceEndMs
          .clamp(tileStart, tileStart + kWaveformDetailTileDurationMs)
          .toDouble();
      if (partEnd > tile.endMs + 0.001) return null;
      final tilePeak = tile.peakForRange(partStart, partEnd);
      if (tilePeak == null) return null;
      if (tilePeak > peak) peak = tilePeak;
    }
    return peak;
  }

  void _touch(String key) {
    final tile = _cache.remove(key);
    if (tile != null) _cache[key] = tile;
  }

  void _insert(WaveformDetailTile tile) {
    final key = '${tile.sourceKey}|${tile.tileIndex}';
    final replaced = _cache.remove(key);
    if (replaced != null) _cachePayloadBytes -= replaced.payloadBytes;
    if (tile.payloadBytes > maxCacheBytes) return;
    while (_cachePayloadBytes + tile.payloadBytes > maxCacheBytes &&
        _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      final removed = _cache.remove(oldestKey);
      if (removed != null) _cachePayloadBytes -= removed.payloadBytes;
    }
    _cache[key] = tile;
    _cachePayloadBytes += tile.payloadBytes;
  }

  void _pump() {
    if (_disposed || _detailJobActive || _overviewWorkPending()) return;
    WaveformDetailTileRequest? next;
    for (final entry in _desired.entries) {
      if (!_cache.containsKey(entry.key)) {
        next = entry.value;
        break;
      }
    }
    if (next == null) return;
    _detailJobActive = true;
    final generation = _generation;
    final request = next;
    _loadTile(request)
        .then((tile) {
          if (_disposed || generation != _generation || tile == null) return;
          _insert(tile);
          if (_mutationDepth > 0) return;
          if (_desired.containsKey(request.key)) notifyListeners();
        })
        .catchError((Object _) => null)
        .whenComplete(() {
          _detailJobActive = false;
          if (_disposed) return;
          if (generation == _generation) {
            _desired.remove(request.key);
          }
          _pump();
        });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _desired.clear();
    _cache.clear();
    _sourceKeyByPath.clear();
    _cachePayloadBytes = 0;
    super.dispose();
  }
}

@immutable
class WaveformDetailViewport {
  const WaveformDetailViewport({
    required this.timelineStartMs,
    required this.timelineEndMs,
    required this.pixelsPerMs,
    required this.visibleClipIds,
  });

  final double timelineStartMs;
  final double timelineEndMs;
  final double pixelsPerMs;
  final List<String> visibleClipIds;
}
