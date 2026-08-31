import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
