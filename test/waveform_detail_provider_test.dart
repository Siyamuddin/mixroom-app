import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/waveform_detail.dart';

WaveformDetailSource _source({
  String path = '/audio/source.wav',
  String cacheKey = 'source|100|1',
  double durationMs = 10000.0,
}) => WaveformDetailSource(
  path: path,
  cacheKey: cacheKey,
  durationMs: durationMs,
);

WaveformDetailTile _tile(
  WaveformDetailTileRequest request,
  List<double> amplitudes,
) => WaveformDetailTile(
  sourceKey: request.source.cacheKey,
  tileIndex: request.tileIndex,
  startMs: request.startMs,
  sampleRate: 2,
  amplitudes: Float32List.fromList(amplitudes),
);

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('timeline intersections map through trim stretch and reversal', () {
    final forward = waveformDetailSourceRangeForTimelineIntersection(
      clipStartMs: 1000.0,
      timelineDurationMs: 4000.0,
      trimStartMs: 2000.0,
      trimEndMs: 4000.0,
      sourceDurationMs: 6000.0,
      isReversed: false,
      viewportStartMs: 2000.0,
      viewportEndMs: 3000.0,
    );
    final reversed = waveformDetailSourceRangeForTimelineIntersection(
      clipStartMs: 1000.0,
      timelineDurationMs: 4000.0,
      trimStartMs: 2000.0,
      trimEndMs: 4000.0,
      sourceDurationMs: 6000.0,
      isReversed: true,
      viewportStartMs: 2000.0,
      viewportEndMs: 3000.0,
    );

    expect(forward?.startMs, 2500.0);
    expect(forward?.endMs, 3000.0);
    expect(reversed?.startMs, 3000.0);
    expect(reversed?.endMs, 3500.0);
  });

  test('tile range prioritizes visible tiles before adjacent prefetch', () {
    expect(
      waveformDetailTileIndicesForRange(
        sourceStartMs: 2200.0,
        sourceEndMs: 6100.0,
        sourceDurationMs: 10000.0,
      ),
      <int>[1, 2, 3, 0, 4],
    );
  });

  test('tile requests align to two seconds and shorten at source end', () {
    final source = _source(durationMs: 4500.0);
    final middle = WaveformDetailTileRequest(source: source, tileIndex: 1);
    final finalTile = WaveformDetailTileRequest(source: source, tileIndex: 2);

    expect(middle.startMs, 2000.0);
    expect(middle.durationMs, 2000.0);
    expect(finalTile.startMs, 4000.0);
    expect(finalTile.durationMs, 500.0);
  });

  test(
    'provider runs one detail job and keeps only latest desired viewport',
    () async {
      final started = <int>[];
      final completers = <int, Completer<WaveformDetailTile?>>{};
      final source = _source();
      final provider = WaveformDetailProvider(
        loadTile: (request) {
          started.add(request.tileIndex);
          return (completers[request.tileIndex] =
                  Completer<WaveformDetailTile?>())
              .future;
        },
        overviewWorkPending: () => false,
      );
      addTearDown(provider.dispose);

      provider.requestTiles(<WaveformDetailTileRequest>[
        WaveformDetailTileRequest(source: source, tileIndex: 0),
        WaveformDetailTileRequest(source: source, tileIndex: 1),
      ]);
      expect(started, <int>[0]);
      expect(provider.detailJobActive, isTrue);

      provider.requestTiles(<WaveformDetailTileRequest>[
        WaveformDetailTileRequest(source: source, tileIndex: 4),
      ]);
      expect(started, <int>[0]);
      expect(provider.desiredTileCount, 1);

      completers[0]!.complete(null);
      await _flushAsync();
      expect(started, <int>[0, 4]);
    },
  );

  test(
    'overview work prevents detail from starting until explicitly resumed',
    () async {
      var overviewBusy = true;
      var loads = 0;
      final source = _source();
      final provider = WaveformDetailProvider(
        loadTile: (request) async {
          loads++;
          return _tile(request, const <double>[0.2, 0.5]);
        },
        overviewWorkPending: () => overviewBusy,
      );
      addTearDown(provider.dispose);

      provider.requestTiles(<WaveformDetailTileRequest>[
        WaveformDetailTileRequest(source: source, tileIndex: 0),
      ]);
      expect(loads, 0);

      overviewBusy = false;
      provider.resumeAfterOverviewWork();
      await _flushAsync();
      expect(loads, 1);
    },
  );

  test('lookup requires complete coverage across tile boundaries', () async {
    final source = _source(durationMs: 4000.0);
    final provider = WaveformDetailProvider(
      loadTile: (request) async => request.tileIndex == 0
          ? _tile(request, const <double>[0.1, 0.7, 0.2, 0.3])
          : _tile(request, const <double>[0.4, 0.9, 0.2, 0.1]),
      overviewWorkPending: () => false,
    );
    addTearDown(provider.dispose);

    provider.requestTiles(<WaveformDetailTileRequest>[
      WaveformDetailTileRequest(source: source, tileIndex: 0),
    ]);
    await _flushAsync();
    expect(provider.peakForSourceRange(source.path, 1500.0, 2500.0), isNull);

    provider.requestTiles(<WaveformDetailTileRequest>[
      WaveformDetailTileRequest(source: source, tileIndex: 0),
      WaveformDetailTileRequest(source: source, tileIndex: 1),
    ]);
    await _flushAsync();
    expect(
      provider.peakForSourceRange(source.path, 1500.0, 2500.0),
      closeTo(0.4, 0.0001),
    );
  });

  test(
    'cache evicts least recently requested tiles at its byte limit',
    () async {
      final source = _source(durationMs: 6000.0);
      final provider = WaveformDetailProvider(
        maxCacheBytes: 16,
        loadTile: (request) async =>
            _tile(request, const <double>[0.1, 0.2, 0.3, 0.4]),
        overviewWorkPending: () => false,
      );
      addTearDown(provider.dispose);

      provider.requestTiles(<WaveformDetailTileRequest>[
        WaveformDetailTileRequest(source: source, tileIndex: 0),
      ]);
      await _flushAsync();
      provider.requestTiles(<WaveformDetailTileRequest>[
        WaveformDetailTileRequest(source: source, tileIndex: 1),
      ]);
      await _flushAsync();

      expect(provider.cachePayloadBytes, 16);
      expect(provider.cachedTileCount, 1);
      expect(provider.peakForSourceRange(source.path, 0.0, 100.0), isNull);
      expect(
        provider.peakForSourceRange(source.path, 2000.0, 2100.0),
        isNotNull,
      );
    },
  );

  test('cached viewport requests refresh LRU recency', () async {
    final source = _source(durationMs: 6000.0);
    final provider = WaveformDetailProvider(
      maxCacheBytes: 32,
      loadTile: (request) async =>
          _tile(request, const <double>[0.1, 0.2, 0.3, 0.4]),
      overviewWorkPending: () => false,
    );
    addTearDown(provider.dispose);

    for (final tileIndex in <int>[0, 1]) {
      provider.requestTiles(<WaveformDetailTileRequest>[
        WaveformDetailTileRequest(source: source, tileIndex: tileIndex),
      ]);
      await _flushAsync();
    }
    provider.requestTiles(<WaveformDetailTileRequest>[
      WaveformDetailTileRequest(source: source, tileIndex: 0),
      WaveformDetailTileRequest(source: source, tileIndex: 2),
    ]);
    await _flushAsync();

    expect(provider.peakForSourceRange(source.path, 0.0, 100.0), isNotNull);
    expect(provider.peakForSourceRange(source.path, 2000.0, 2100.0), isNull);
    expect(provider.peakForSourceRange(source.path, 4000.0, 4100.0), isNotNull);
  });

  test('a changed source fingerprint cannot read stale path data', () async {
    final oldSource = _source(cacheKey: 'source|100|1');
    final newSource = _source(cacheKey: 'source|200|2');
    final pendingNew = Completer<WaveformDetailTile?>();
    final provider = WaveformDetailProvider(
      loadTile: (request) async {
        if (request.source.cacheKey == oldSource.cacheKey) {
          return _tile(request, const <double>[0.8, 0.2]);
        }
        return pendingNew.future;
      },
      overviewWorkPending: () => false,
    );
    addTearDown(provider.dispose);

    provider.requestTiles(<WaveformDetailTileRequest>[
      WaveformDetailTileRequest(source: oldSource, tileIndex: 0),
    ]);
    await _flushAsync();
    expect(provider.peakForSourceRange(oldSource.path, 0.0, 100.0), isNotNull);

    final newRequest = WaveformDetailTileRequest(
      source: newSource,
      tileIndex: 0,
    );
    provider.requestTiles(<WaveformDetailTileRequest>[newRequest]);
    expect(provider.peakForSourceRange(newSource.path, 0.0, 100.0), isNull);
    pendingNew.complete(_tile(newRequest, const <double>[0.4, 0.1]));
    await _flushAsync();
    expect(
      provider.peakForSourceRange(newSource.path, 0.0, 100.0),
      closeTo(0.4, 0.0001),
    );
  });

  test('clear invalidates an in-flight result', () async {
    final source = _source();
    final completer = Completer<WaveformDetailTile?>();
    late WaveformDetailTileRequest activeRequest;
    final provider = WaveformDetailProvider(
      loadTile: (request) {
        activeRequest = request;
        return completer.future;
      },
      overviewWorkPending: () => false,
    );
    addTearDown(provider.dispose);

    provider.requestTiles(<WaveformDetailTileRequest>[
      WaveformDetailTileRequest(source: source, tileIndex: 0),
    ]);
    provider.clear();
    completer.complete(_tile(activeRequest, const <double>[0.8, 0.2]));
    await _flushAsync();

    expect(provider.cachedTileCount, 0);
    expect(provider.peakForSourceRange(source.path, 0.0, 100.0), isNull);
  });

  test('a completed stale viewport tile does not request a repaint', () async {
    final source = _source();
    final completers = <int, Completer<WaveformDetailTile?>>{};
    final provider = WaveformDetailProvider(
      loadTile: (request) =>
          (completers[request.tileIndex] = Completer<WaveformDetailTile?>())
              .future,
      overviewWorkPending: () => false,
    );
    addTearDown(provider.dispose);
    var notifications = 0;
    provider.addListener(() => notifications++);

    final staleRequest = WaveformDetailTileRequest(
      source: source,
      tileIndex: 0,
    );
    provider.requestTiles(<WaveformDetailTileRequest>[staleRequest]);
    provider.requestTiles(<WaveformDetailTileRequest>[
      WaveformDetailTileRequest(source: source, tileIndex: 2),
    ]);
    completers[0]!.complete(_tile(staleRequest, const <double>[0.8, 0.2]));
    await _flushAsync();

    expect(notifications, 0);
    expect(provider.cachedTileCount, 1);
    expect(completers.containsKey(2), isTrue);
  });

  test('a failed detail load leaves the provider usable', () async {
    final source = _source();
    var attempts = 0;
    final provider = WaveformDetailProvider(
      loadTile: (request) async {
        attempts++;
        if (attempts == 1) throw StateError('decode failed');
        return _tile(request, const <double>[0.3, 0.6]);
      },
      overviewWorkPending: () => false,
    );
    addTearDown(provider.dispose);

    provider.requestTiles(<WaveformDetailTileRequest>[
      WaveformDetailTileRequest(source: source, tileIndex: 0),
      WaveformDetailTileRequest(source: source, tileIndex: 1),
    ]);
    await _flushAsync();

    expect(attempts, 2);
    expect(
      provider.peakForSourceRange(source.path, 2000.0, 2100.0),
      isNotNull,
    );
  });
}
