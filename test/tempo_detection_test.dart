import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/tempo_detection.dart';

Float32List _rhythmicLoop({
  required double bpm,
  required int beats,
  int sampleRate = 48000,
}) {
  final durationSec = beats * 60.0 / bpm;
  final samples = Float32List((durationSec * sampleRate).ceil());
  final beatSamples = sampleRate * 60.0 / bpm;
  final transientLength = (sampleRate * 0.018).round();

  void addTransient(double positionSamples, double gain, double freqHz) {
    final start = positionSamples.round();
    for (int i = 0; i < transientLength; i++) {
      final index = start + i;
      if (index < 0 || index >= samples.length) break;
      final t = i / sampleRate;
      final env = math.exp(-i / (sampleRate * 0.004));
      samples[index] +=
          gain * env * math.sin(2.0 * math.pi * freqHz * t).toDouble();
    }
  }

  for (int beat = 0; beat < beats; beat++) {
    final base = beat * beatSamples;
    addTransient(base, beat % 4 == 0 ? 0.95 : 0.72, 160.0);
    addTransient(base + beatSamples * 0.5, 0.28, 880.0);
  }

  return samples;
}

double _detect(Float32List samples, {int sampleRate = 48000}) {
  const hopSize = 128;
  final env = MixroomTempoDetection.buildOnsetEnvelopeFromSamples(
    samples,
    hopSize: hopSize,
  );
  return MixroomTempoDetection.detectTempoFromOnsetEnvelope(
    env,
    sampleRate / hopSize,
    durationSec: samples.length / sampleRate,
  )!;
}

void main() {
  test('detects short 140 bpm rhythmic loops without snapping to 150', () {
    final bpm = _detect(_rhythmicLoop(bpm: 140, beats: 8));

    expect(bpm, closeTo(140, 1.0));
  });

  test('detects short 160 bpm rhythmic loops without drifting sharp', () {
    final bpm = _detect(_rhythmicLoop(bpm: 160, beats: 8));

    expect(bpm, closeTo(160, 1.0));
  });
}
