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

  test('waveform FFmpeg jobs use one failure-tolerant serial lane', () {
    expect(
      editor,
      contains('Future<void> _waveformExtractionLane = Future<void>.value();'),
    );

    final queuedMethod = _methodBody(
      editor,
      'Future<List<double>?> _extractWaveformData(',
      'Future<List<double>?> _extractWaveformDataNow(',
    );
    expect(queuedMethod, contains('final previous = _waveformExtractionLane;'));
    expect(queuedMethod, contains('await previous;'));
    expect(queuedMethod, contains('catch (_)'));
    expect(queuedMethod, contains('await _extractWaveformDataNow('));
    expect(queuedMethod, isNot(contains('FFmpegKit.executeWithArguments')));

    final workerMethod = _methodBody(
      editor,
      'Future<List<double>?> _extractWaveformDataNow(',
      'bool _isAllZeroWaveform(',
    );
    expect(workerMethod, contains('FFmpegKit.executeWithArguments'));
  });
}
