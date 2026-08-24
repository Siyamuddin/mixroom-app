import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_timeline_pro.dart';

void main() {
  test('advancing the playhead never moves accepted peak endpoints', () {
    final earlier = buildRecordingPreviewEnvelopePoints(
      peaks: const <double>[0.1, 0.2, 0.3],
      peakTimesMs: const <double>[50, 100, 150],
      durationMs: 200,
    );
    final later = buildRecordingPreviewEnvelopePoints(
      peaks: const <double>[0.1, 0.2, 0.3],
      peakTimesMs: const <double>[50, 100, 150],
      durationMs: 260,
    );

    expect(earlier, const <Offset>[
      Offset(0, 0.1),
      Offset(50, 0.1),
      Offset(100, 0.2),
      Offset(150, 0.3),
      Offset(200, 0.3),
    ]);
    expect(
      later.sublist(0, earlier.length - 1),
      earlier.sublist(0, earlier.length - 1),
    );
    expect(later.last, const Offset(260, 0.3));
  });

  test('adding a peak never moves previously accepted endpoints', () {
    final before = buildRecordingPreviewEnvelopePoints(
      peaks: const <double>[0.1, 0.2, 0.3],
      peakTimesMs: const <double>[50, 100, 150],
      durationMs: 200,
    );
    final after = buildRecordingPreviewEnvelopePoints(
      peaks: const <double>[0.1, 0.2, 0.3, 0.4],
      peakTimesMs: const <double>[50, 100, 150, 200],
      durationMs: 250,
    );

    final acceptedBefore = before.sublist(0, before.length - 1);
    expect(after.sublist(0, acceptedBefore.length), acceptedBefore);
    expect(after[4], const Offset(200, 0.4));
    expect(after.last, const Offset(250, 0.4));
  });

  test('irregular polling intervals retain transport-aligned times', () {
    final points = buildRecordingPreviewEnvelopePoints(
      peaks: const <double>[0.2, 0.8, 0.3, 0.6],
      peakTimesMs: const <double>[42, 117, 169, 281],
      durationMs: 320,
    );

    expect(points.map((point) => point.dx), const <double>[
      0,
      42,
      117,
      169,
      281,
      320,
    ]);
  });

  test('the sole temporary endpoint reaches the playhead unchanged', () {
    final points = buildRecordingPreviewEnvelopePoints(
      peaks: const <double>[0.2, 0.8, 0.3],
      peakTimesMs: const <double>[43, 121, 179],
      durationMs: 237,
    );

    expect(points.last, const Offset(237, 0.3));
    expect(points[points.length - 2], const Offset(179, 0.3));
  });

  test('silence and a sudden peak remain finite and stationary', () {
    final before = buildRecordingPreviewEnvelopePoints(
      peaks: const <double>[0, 0, 0, 0.9],
      peakTimesMs: const <double>[50, 100, 150, 200],
      durationMs: 225,
    );
    final later = buildRecordingPreviewEnvelopePoints(
      peaks: const <double>[0, 0, 0, 0.9],
      peakTimesMs: const <double>[50, 100, 150, 200],
      durationMs: 275,
    );

    expect(
      later.sublist(0, before.length - 1),
      before.sublist(0, before.length - 1),
    );
    expect(later.last, const Offset(275, 0.9));
    expect(
      later.every((point) => point.dx.isFinite && point.dy.isFinite),
      isTrue,
    );
  });

  test('zero and one peak produce finite preview geometry', () {
    expect(
      buildRecordingPreviewEnvelopePoints(
        peaks: const <double>[],
        peakTimesMs: const <double>[],
        durationMs: 100,
      ),
      isEmpty,
    );

    final points = buildRecordingPreviewEnvelopePoints(
      peaks: const <double>[0.5],
      peakTimesMs: const <double>[50],
      durationMs: 100,
    );
    expect(points, const <Offset>[
      Offset(0, 0.5),
      Offset(50, 0.5),
      Offset(100, 0.5),
    ]);
  });

  test('malformed samples cannot create non-finite geometry', () {
    final points = buildRecordingPreviewEnvelopePoints(
      peaks: const <double>[double.nan, 2, -1, 0.4],
      peakTimesMs: const <double>[20, double.nan, 80, 120],
      durationMs: 150,
    );

    expect(points.last.dx, 150);
    expect(
      points.every((point) => point.dx.isFinite && point.dy.isFinite),
      isTrue,
    );
    expect(points.every((point) => point.dy >= 0 && point.dy <= 1), isTrue);
  });

  test('zoom and scrolling only transform immutable time coordinates', () {
    final points = buildRecordingPreviewEnvelopePoints(
      peaks: const <double>[0.2, 0.4],
      peakTimesMs: const <double>[50, 125],
      durationMs: 175,
    );
    final acceptedTimes = points
        .sublist(0, points.length - 1)
        .map((point) => point.dx)
        .toList(growable: false);

    final normal = acceptedTimes.map((time) => (time - 20) * 0.5).toList();
    final zoomed = acceptedTimes.map((time) => (time - 40) * 2.0).toList();

    expect(acceptedTimes, const <double>[0, 50, 125]);
    expect(normal, const <double>[-10, 15, 52.5]);
    expect(zoomed, const <double>[-80, 20, 170]);
    expect(
      points.sublist(0, points.length - 1).map((point) => point.dx),
      acceptedTimes,
    );
  });

  test('recording peak polling is serialized and generation guarded', () {
    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();

    expect(editor, contains('const Duration(milliseconds: 50)'));
    expect(editor, contains('_recordingPeakPollBusy = true;'));
    expect(editor, contains('peakGeneration != _recordingPeakGeneration'));
    expect(editor, contains('final acceptedElapsedMs ='));
    expect(editor, contains('_globalAudioClock.inMicroseconds.toDouble()'));
    expect(editor, isNot(contains('_recordingPeakClock')));
    expect(editor, contains('_recordingPeaks.add('));
    expect(editor, contains('_recordingPeakTimesMs.add(elapsedMs);'));
    expect(
      RegExp(
        r'_stopRecordingPeakPolling\(clearSamples: true\);',
      ).allMatches(editor).length,
      greaterThanOrEqualTo(5),
    );
  });
}
