import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Collapses whitespace runs so assertions survive reformatting.
String _normalized(String source) =>
    source.replaceAll(RegExp(r'\s+'), ' ').trim();

String _methodBody(String source, String signature, String nextSignature) {
  final start = source.indexOf(signature);
  final end = source.indexOf(nextSignature, start + signature.length);
  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  late String editor;

  setUpAll(() {
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  test(
    'overview and detail FFmpeg jobs use one failure-tolerant serial lane',
    () {
      expect(
        editor,
        contains(
          'Future<void> _waveformExtractionLane = Future<void>.value();',
        ),
      );

      final overviewEntry = _methodBody(
        editor,
        'Future<List<double>?> _extractWaveformData(',
        'Future<T> _runWaveformExtractionJob<T>(',
      );
      expect(overviewEntry, contains('_runWaveformExtractionJob('));
      expect(overviewEntry, isNot(contains('FFmpegKit.executeWithArguments')));

      final queuedMethod = _methodBody(
        editor,
        'Future<T> _runWaveformExtractionJob<T>(',
        'Future<WaveformDetailTile?> _extractWaveformDetailTile(',
      );
      expect(
        queuedMethod,
        contains('final previous = _waveformExtractionLane;'),
      );
      expect(queuedMethod, contains('await previous;'));
      expect(queuedMethod, contains('catch (_)'));
      expect(queuedMethod, contains('result.complete(await work())'));
      expect(queuedMethod, isNot(contains('FFmpegKit.executeWithArguments')));

      final detailEntry = _methodBody(
        editor,
        'Future<WaveformDetailTile?> _extractWaveformDetailTile(',
        'Future<WaveformDetailTile?> _extractWaveformDetailTileNow(',
      );
      expect(detailEntry, contains('_runWaveformExtractionJob('));
      expect(detailEntry, isNot(contains('FFmpegKit.executeWithArguments')));

      final detailWorker = _methodBody(
        editor,
        'Future<WaveformDetailTile?> _extractWaveformDetailTileNow(',
        'Future<List<double>?> _extractWaveformDataNow(',
      );
      expect(detailWorker, contains('FFmpegKit.executeWithArguments'));
      expect(detailWorker, contains("'-ss'"));
      expect(detailWorker, contains("'-t'"));
      expect(detailWorker, contains('byteLength > maximumBytes'));
      expect(detailWorker, contains('finally'));

      final workerMethod = _methodBody(
        editor,
        'Future<List<double>?> _extractWaveformDataNow(',
        'bool _isAllZeroWaveform(',
      );
      expect(workerMethod, contains('FFmpegKit.executeWithArguments'));
    },
  );

  test('the overview waveform cache never stores or serves silent peaks', () {
    // PRO-74: an all-zero overview array paints as an empty clip while the
    // audio still plays. Caching one against a file path made that state
    // permanent, because adopting it also marked the clip as extracted.
    final extractionMethod = _normalized(
      _methodBody(
        editor,
        'void _startWaveformExtraction(AudioTrack c) async {',
        'Future<void> _handleWaveformDetailViewport(',
      ),
    );

    // Reading from the cache must reject silent peaks.
    expect(
      extractionMethod,
      contains(
        'if (cached != null && cached.isNotEmpty && '
        '!_isAllZeroWaveform(cached)) {',
      ),
    );

    // Writing to the cache must reject them too.
    expect(
      extractionMethod,
      contains(
        '!_isAllZeroWaveform(waveform)) { '
        '_waveformCacheByPath[cacheKey] = waveform;',
      ),
    );

    // A silent result has to reach the retry path rather than be accepted, and
    // it has to do so before the success bookkeeping runs.
    expect(
      extractionMethod,
      contains(
        "_markWaveformExtractionFailed(cacheKey, waitingTracks, "
        "'silent result')",
      ),
    );
    final silentGuardIndex = extractionMethod.indexOf(
      'if (_isAllZeroWaveform(waveform)) {',
    );
    final successIndex = extractionMethod.indexOf(
      '_waveformFailureCountByPath.remove(cacheKey);',
    );
    expect(silentGuardIndex, greaterThanOrEqualTo(0));
    expect(successIndex, greaterThan(silentGuardIndex));

    // The normalize-visual path shares the same cache and must guard it too.
    final normalizeMethod = _normalized(
      _methodBody(
        editor,
        'Future<void> _ensureClipWaveformForNormalizeVisual(AudioTrack clip) '
            'async {',
        'Future<void> _handleToggleClipNormalize(',
      ),
    );
    expect(normalizeMethod, contains('if (!_isAllZeroWaveform(extracted)) {'));
  });

  test('quiet waveform bars survive device-pixel snapping', () {
    // PRO-74: a bar shorter than one device pixel snapped to a zero-length
    // stroke, and a butt-capped stroke with anti-aliasing off paints nothing,
    // so quiet audio disappeared instead of reading as a faint line.
    final timeline = File(
      'lib/screens/audio_timeline_pro.dart',
    ).readAsStringSync();
    final drawWaveform = _normalized(
      _methodBody(
        timeline,
        'void _drawWaveform(',
        'void _drawMidiPreview(',
      ),
    );
    // The collapsed case must be widened to a single device pixel before the
    // stroke is added to the path.
    final guardIndex = drawWaveform.indexOf('if (bottomY <= topY) {');
    final widenIndex = drawWaveform.indexOf('bottomY = topY + 1.0 / dpr;');
    final strokeIndex = drawWaveform.indexOf('path.lineTo(x0, bottomY);');
    expect(guardIndex, greaterThanOrEqualTo(0));
    expect(widenIndex, greaterThan(guardIndex));
    expect(strokeIndex, greaterThan(widenIndex));
  });
}
