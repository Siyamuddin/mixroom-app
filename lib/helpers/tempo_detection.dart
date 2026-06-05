import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

class MixroomTempoDetection {
  static List<double> buildOnsetEnvelopeFromSamples(
    Float32List samples, {
    int frameSize = 1024,
    int hopSize = 128,
  }) {
    if (samples.length < frameSize || hopSize <= 0) return const <double>[];

    final fft = FFT(frameSize);
    final window = Float64List(frameSize);
    for (int i = 0; i < frameSize; i++) {
      window[i] = 0.5 - 0.5 * math.cos((2.0 * math.pi * i) / (frameSize - 1));
    }

    final frame = Float64List(frameSize);
    final previous = Float64List(frameSize);
    final env = <double>[];

    for (int offset = 0;
        offset + frameSize <= samples.length;
        offset += hopSize) {
      for (int i = 0; i < frameSize; i++) {
        frame[i] = samples[offset + i] * window[i];
      }

      final spectrum = fft.realFft(frame);
      double flux = 0.0;
      for (int bin = 2; bin < spectrum.length; bin++) {
        final c = spectrum[bin];
        final mag = math.log(1.0 + math.sqrt(c.x * c.x + c.y * c.y) * 18.0);
        final diff = mag - previous[bin];
        if (diff > 0.0) flux += diff;
        previous[bin] = mag;
      }
      env.add(flux);
    }

    return _highPassAndNormalize(env);
  }

  static double? detectTempoFromOnsetEnvelope(
    List<double> onsetEnv,
    double envSampleRateHz, {
    double? durationSec,
  }) {
    if (onsetEnv.length < 16 || envSampleRateHz <= 0.0) return null;

    final env = _highPassAndNormalize(onsetEnv);
    if (env.length < 16) return null;

    final minLag = math.max(1.0, envSampleRateHz * 60.0 / 220.0);
    final maxLag = math.min(env.length - 2.0, envSampleRateHz * 60.0 / 55.0);
    if (minLag >= maxLag) return null;

    double corrAtLag(double lag) {
      double s = 0.0;
      double normA = 0.0;
      double normB = 0.0;
      final start = math.max(1, lag.ceil());
      for (int i = start; i < env.length; i++) {
        final source = i - lag;
        final lo = source.floor();
        final frac = source - lo;
        if (lo < 0 || lo + 1 >= env.length) continue;
        final a = env[i];
        final b = env[lo] * (1.0 - frac) + env[lo + 1] * frac;
        s += a * b;
        normA += a * a;
        normB += b * b;
      }
      return s / math.sqrt(math.max(1.0e-9, normA * normB));
    }

    final peakTimesMs = _pickOnsetPeaksMs(env, envSampleRateHz);
    final consecutiveIois = <double>[];
    final pairIois = <double>[];
    for (int i = 1; i < peakTimesMs.length; i++) {
      final delta = peakTimesMs[i] - peakTimesMs[i - 1];
      if (delta >= 105.0 && delta <= 1800.0) consecutiveIois.add(delta);
    }
    for (int i = 0; i < peakTimesMs.length; i++) {
      for (int j = i + 1; j < peakTimesMs.length; j++) {
        final delta = peakTimesMs[j] - peakTimesMs[i];
        if (delta > 2400.0) break;
        if (delta >= 105.0) pairIois.add(delta);
      }
    }

    double loopPrior(double bpm) {
      final seconds = durationSec ?? (env.length / envSampleRateHz);
      if (!seconds.isFinite || seconds < 0.6 || seconds > 60.0) return 0.0;
      var best = 0.0;
      const beatCounts = <double>[1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64];
      for (final beats in beatCounts) {
        var candidate = beats * 60.0 / seconds;
        while (candidate < 75.0) {
          candidate *= 2.0;
        }
        while (candidate > 180.0) {
          candidate *= 0.5;
        }
        final rel = (math.log(bpm / candidate) / math.ln2).abs();
        if (rel < 0.035) best = math.max(best, 1.0 - rel / 0.035);
      }
      return best;
    }

    double bestScore = double.negativeInfinity;
    double bestBpm = 0.0;
    for (double bpm = 55.0; bpm <= 220.0; bpm += 0.1) {
      final lag = envSampleRateHz * 60.0 / bpm;
      if (lag < minLag || lag > maxLag) continue;

      double score = corrAtLag(lag);
      final lag2 = lag * 2.0;
      final lag4 = lag * 4.0;
      final halfLag = lag * 0.5;
      if (lag2 <= maxLag) score += 0.55 * corrAtLag(lag2);
      if (lag4 <= maxLag) score += 0.22 * corrAtLag(lag4);
      if (halfLag >= minLag) score += 0.06 * corrAtLag(halfLag);

      if (consecutiveIois.isNotEmpty) {
        final beatMs = 60000.0 / bpm;
        double ioiScore = 0.0;
        for (final ioi in consecutiveIois) {
          final ratio = ioi / beatMs;
          final nearest = ratio.round().clamp(1, 16);
          final err = (ratio - nearest).abs();
          if (err <= 0.055) ioiScore += 1.0 - err / 0.055;
        }
        score += 0.55 * (ioiScore / consecutiveIois.length);
      }

      if (pairIois.isNotEmpty) {
        final beatMs = 60000.0 / bpm;
        double pairScore = 0.0;
        for (final ioi in pairIois) {
          final ratio = ioi / beatMs;
          final nearest = ratio.round().clamp(1, 16);
          final logErr = (math.log(ratio / nearest) / math.ln2).abs();
          if (logErr <= 0.035) pairScore += 1.0 - logErr / 0.035;
        }
        score += 0.85 * (pairScore / pairIois.length);
      }

      score += 0.75 * loopPrior(bpm);
      if (score > bestScore) {
        bestScore = score;
        bestBpm = bpm;
      }
    }

    if (bestBpm <= 0.0 || bestScore <= 0.0) return null;
    while (bestBpm < 75.0) {
      bestBpm *= 2.0;
    }
    while (bestBpm > 180.0) {
      bestBpm *= 0.5;
    }
    return bestBpm.clamp(40.0, 240.0).toDouble();
  }

  static List<double> _highPassAndNormalize(List<double> input) {
    if (input.isEmpty) return const <double>[];
    final out = List<double>.filled(input.length, 0.0);
    final radius = math.max(2, (input.length / 64).round());
    for (int i = 0; i < input.length; i++) {
      final start = math.max(0, i - radius);
      final end = math.min(input.length, i + radius + 1);
      double localMean = 0.0;
      for (int j = start; j < end; j++) {
        localMean += input[j];
      }
      localMean /= math.max(1, end - start);
      out[i] = math.max(0.0, input[i] - localMean);
    }

    final mean = out.reduce((a, b) => a + b) / out.length;
    double variance = 0.0;
    for (final v in out) {
      final d = v - mean;
      variance += d * d;
    }
    final std = math.sqrt(math.max(1.0e-12, variance / out.length));
    for (int i = 0; i < out.length; i++) {
      out[i] = math.max(0.0, (out[i] - mean) / std);
    }
    return out;
  }

  static List<double> _pickOnsetPeaksMs(List<double> env, double envHz) {
    if (env.length < 3) return const <double>[];
    final sorted = List<double>.from(env)..sort();
    final median = sorted[sorted.length ~/ 2];
    final highIndex =
        (sorted.length * 0.78).floor().clamp(0, sorted.length - 1).toInt();
    final high = sorted[highIndex];
    final threshold = math.max(0.25, median + (high - median) * 0.55);
    final minSpacing = math.max(1, (envHz * 0.075).round());
    var last = -minSpacing * 2;
    final peaks = <double>[];
    for (int i = 1; i < env.length - 1; i++) {
      final v = env[i];
      if (v < threshold || v <= env[i - 1] || v < env[i + 1]) continue;
      if (i - last < minSpacing) {
        if (peaks.isNotEmpty && v > env[last]) {
          peaks.removeLast();
          peaks.add(i * 1000.0 / envHz);
          last = i;
        }
        continue;
      }
      peaks.add(i * 1000.0 / envHz);
      last = i;
    }
    return peaks;
  }
}
