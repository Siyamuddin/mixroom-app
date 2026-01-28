import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mixroom/models/models.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

import '../models/project_state.dart';
import 'instrument_classifier.dart';

class ProjectStateBuilder {
  final InstrumentClassifier classifier;
  final int maxRows;

  ProjectStateBuilder({required this.classifier, this.maxRows = 5});

  Future<ProjectState> build({
    required List<AudioTrack> audioTracks,
    required double bpmFallback,
    required List<double> rowGain,
    required List<double> rowPan,
    required List<List<AutomationPoint>> rowAutomation,
    Map<int, String> roleOverrides = const {},
  }) async {
    final clipsByRow = List.generate(maxRows, (_) => <ClipState>[]);

    // Keep duration per clip for roleConsistency weighting
    final clipDurMsByRow = List.generate(maxRows, (_) => <double>[]);

    for (final t in audioTracks) {
      final fileName = t.file.path.split('/').last.split('.').first;
      final row = t.rowIndex;
      if (row < 0 || row >= maxRows) continue;

      final startMs = t.offset * 1000.0;
      final durMs = (t.trimEnd - t.trimStart).inMilliseconds.toDouble().clamp(0.0, 1e12);
      final endMs = startMs + durMs;

      clipsByRow[row].add(ClipState(startMs: startMs, endMs: endMs, fileName: fileName));
      clipDurMsByRow[row].add(durMs);
    }

    final overlap = List.generate(maxRows, (_) => List.filled(maxRows, 0));
    for (var i = 0; i < maxRows; i++) {
      for (var j = 0; j < maxRows; j++) {
        if (i == j) continue;
        overlap[i][j] = _rowsOverlap(clipsByRow[i], clipsByRow[j]) ? 1 : 0;
      }
    }

    final rows = <RowState>[];
    for (var row = 0; row < maxRows; row++) {
      final effects = <EffectState>[];

      final names = await JuceAudioEngine.getTrackEffectsForRow(row);
      for (int i = 0; i < names.length; i++) {
        final params = await JuceAudioEngine.getTrackPluginParameters(row, i);

        effects.add(
          EffectState(
            effectIndex: i,
            name: names[i],
            isBypassed: await JuceAudioEngine.getRowEffectBypassState(row, i),
            parameters: params.map((p) => EffectParameterState.fromMap(Map<String, dynamic>.from(p))).toList(),
          ),
        );
      }

      final gain0to3 = rowGain[row];
      final pan = rowPan[row];
      final automation = rowAutomation[row];

      final rowTracks = audioTracks.where((t) => t.rowIndex == row).toList();
      final hasAudio = rowTracks.isNotEmpty;

      if (!hasAudio) {
        rows.add(
          RowState(
            rowIndex: row,
            clips: const [],
            hasAudio: false,
            approxRms: 0,
            approxCrest: 0,
            roleProbs: const {},
            roleConsistency: 0,
            clipTopRoles: const [],
            audioStats: const {},
            gain0to3: gain0to3,
            pan0To1: pan,
            effects: effects,
            volumeAutomation: automation,
          ),
        );
        continue;
      }

      final rms = _approxRowRms(rowTracks);
      final crest = _approxRowCrest(rowTracks, rms);

      // Aggregate role probs + compute mixed-role warning
      final rowRoleAccum = <String, double>{'vocals': 0, 'guitar': 0, 'bass': 0, 'drums': 0, 'synth': 0, 'other': 0};

      final clipTopRoles = <String>[];
      final roleWeightByTop = <String, double>{};

      // Aggregate audio stats
      double wSum = 0;
      final acc = <String, double>{
        'centroid_hz': 0,
        'zcr': 0,
        'low': 0,
        'lowmid': 0,
        'mid': 0,
        'high': 0,
        'sibilance': 0,
        'bassiness': 0,
      };

      for (int i = 0; i < rowTracks.length; i++) {
        final clip = rowTracks[i];
        final durMs = (i < clipDurMsByRow[row].length) ? clipDurMsByRow[row][i] : 0.0;
        final w = durMs.clamp(100.0, 30000.0); // weight by duration, clamp to avoid extremes

        final pcmRaw = await JuceAudioEngine.decodeAudioMono16k(clip.file.path);
        final pcm = _toDoubleList(pcmRaw);

        final Float32List pcmF32 = Float32List.fromList(pcm.map((x) => x.toDouble()).toList(growable: false));
        final probs = await classifier.classifyAudio(pcmF32);

        // final probs = classifier.classifyAudio(pcm);
        probs.forEach((k, v) {
          rowRoleAccum[k] = (rowRoleAccum[k] ?? 0) + v;
        });

        final topRole = _topRoleFromProbs(probs);
        clipTopRoles.add(topRole);
        roleWeightByTop[topRole] = (roleWeightByTop[topRole] ?? 0) + w;

        final stats = _analyzePcm16k(pcm);
        wSum += w;
        for (final e in acc.entries) {
          acc[e.key] = (acc[e.key] ?? 0) + w * (stats[e.key] ?? 0.0);
        }
      }

      var roleProbs = _normalize(rowRoleAccum);

      // Compute roleConsistency
      double roleConsistency = 1.0;
      if (roleWeightByTop.isNotEmpty) {
        final totalW = roleWeightByTop.values.fold<double>(0.0, (a, b) => a + b);
        final maxW = roleWeightByTop.values.fold<double>(0.0, (a, b) => math.max(a, b));
        if (totalW > 1e-6) {
          roleConsistency = (maxW / totalW).clamp(0.0, 1.0);
        }
      }

      // Finalize audioStats
      final audioStats = <String, double>{};
      if (wSum > 1e-6) {
        for (final e in acc.entries) {
          audioStats[e.key] = (e.value / wSum);
        }
      } else {
        audioStats.addAll(acc.map((k, _) => MapEntry(k, 0.0)));
      }

      // Apply override: treat as fully consistent and set role probs hard
      final override = roleOverrides[row];
      if (override != null) {
        roleProbs = {
          'vocals': 0.0,
          'drums': 0.0,
          'bass': 0.0,
          'guitar': 0.0,
          'synth': 0.0,
          'other': 0.0,
          override: 1.0,
        };
        roleConsistency = 1.0;
      }

      rows.add(
        RowState(
          rowIndex: row,
          clips: clipsByRow[row],
          approxRms: rms,
          approxCrest: crest,
          roleProbs: roleProbs,
          roleConsistency: roleConsistency,
          clipTopRoles: clipTopRoles,
          audioStats: audioStats,
          gain0to3: gain0to3,
          pan0To1: pan,
          effects: effects,
          volumeAutomation: automation,
          hasAudio: hasAudio,
        ),
      );
    }

    final bpm = bpmFallback;
    final masterGain0to3 = 1.0;

    return ProjectState(bpm: bpm, masterGain0to3: masterGain0to3, maxRows: maxRows, rows: rows, overlapMatrix: overlap);
  }

  bool _rowsOverlap(List<ClipState> a, List<ClipState> b) {
    for (final ca in a) {
      for (final cb in b) {
        final overlaps = ca.startMs < cb.endMs && cb.startMs < ca.endMs;
        if (overlaps) return true;
      }
    }
    return false;
  }

  double _approxRowRms(List<AudioTrack> tracks) {
    if (tracks.isEmpty) return 0.0;
    double sum = 0.0;
    int count = 0;

    for (final t in tracks) {
      final data = t.normWaveformData;
      if (data.isEmpty) continue;
      for (final v in data) {
        sum += (v * v);
        count++;
      }
    }
    if (count == 0) return 0.0;
    return math.sqrt(sum / count).clamp(0.0, 1.0);
  }

  double _approxRowCrest(List<AudioTrack> tracks, double rms) {
    if (tracks.isEmpty) return 0.0;
    double peak = 0.0;
    for (final t in tracks) {
      for (final v in t.normWaveformData) {
        peak = math.max(peak, v.abs());
      }
    }
    if (rms <= 1e-6) return (peak > 0 ? 10.0 : 0.0);
    return (peak / rms).clamp(0.0, 20.0);
  }
}

List<double> _toDoubleList(dynamic pcmRaw) {
  if (pcmRaw is List<double>) return pcmRaw;
  if (pcmRaw is List<num>) return pcmRaw.map((e) => e.toDouble()).toList(growable: false);
  if (pcmRaw is Iterable) return pcmRaw.map((e) => (e as num).toDouble()).toList(growable: false);
  return const <double>[];
}

String _topRoleFromProbs(Map<String, double> probs) {
  if (probs.isEmpty) return 'other';
  final entries = probs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final top = entries.first.key;
  return top.isEmpty ? 'other' : top;
}

Map<String, double> _normalize(Map<String, double> m) {
  final sum = m.values.fold<double>(0.0, (a, b) => a + b);
  if (sum <= 1e-9) {
    final n = m.length;
    if (n == 0) return {};
    final v = 1.0 / n;
    return m.map((k, _) => MapEntry(k, v));
  }
  return m.map((k, v) => MapEntry(k, v / sum));
}

/// Lightweight static analysis using Goertzel magnitudes at a few bands.
/// Sample rate assumed 16k (decodeAudioMono16k).
Map<String, double> _analyzePcm16k(List<double> pcm) {
  const fs = 16000.0;
  if (pcm.isEmpty) {
    return const {
      'centroid_hz': 0,
      'zcr': 0,
      'low': 0,
      'lowmid': 0,
      'mid': 0,
      'high': 0,
      'sibilance': 0,
      'bassiness': 0,
    };
  }

  // Use at most ~1.5 sec for speed
  final n = math.min(pcm.length, 24000);
  final x = pcm.sublist(0, n);

  // ZCR
  int zc = 0;
  for (int i = 1; i < x.length; i++) {
    final a = x[i - 1];
    final b = x[i];
    if ((a >= 0 && b < 0) || (a < 0 && b >= 0)) zc++;
  }
  final zcr = (zc / math.max(1, x.length - 1)).clamp(0.0, 1.0);

  // Goertzel freqs (<= 8k nyquist)
  final mags = <double, double>{
    100: _goertzelMag(x, fs, 100),
    250: _goertzelMag(x, fs, 250),
    500: _goertzelMag(x, fs, 500),
    1000: _goertzelMag(x, fs, 1000),
    3000: _goertzelMag(x, fs, 3000),
    6000: _goertzelMag(x, fs, 6000),
    7500: _goertzelMag(x, fs, 7500),
  };

  final low = mags[100]! + mags[250]!;
  final lowmid = mags[500]!;
  final mid = mags[1000]! + mags[3000]!;
  final high = mags[6000]! + mags[7500]!;

  final total = (low + lowmid + mid + high).clamp(1e-9, 1e12);

  // centroid approx
  double num = 0;
  mags.forEach((f, m) => num += f * m);
  final centroidHz = (num / mags.values.fold<double>(1e-9, (a, b) => a + b)).clamp(0.0, 8000.0);

  final sibilance = (high / (mid + lowmid + low + 1e-9)).clamp(0.0, 5.0);
  final bassiness = (low / (mid + high + 1e-9)).clamp(0.0, 5.0);

  return {
    'centroid_hz': centroidHz,
    'zcr': zcr,
    'low': low,
    'lowmid': lowmid,
    'mid': mid,
    'high': high,
    'sibilance': sibilance,
    'bassiness': bassiness,
  };
}

double _goertzelMag(List<double> x, double fs, double freq) {
  final w = 2.0 * math.pi * (freq / fs);
  final cosw = math.cos(w);
  final sinw = math.sin(w);
  final coeff = 2.0 * cosw;

  double s0 = 0, s1 = 0, s2 = 0;
  for (int i = 0; i < x.length; i++) {
    s0 = x[i] + coeff * s1 - s2;
    s2 = s1;
    s1 = s0;
  }

  final real = s1 - s2 * cosw;
  final imag = s2 * sinw;
  return math.sqrt(real * real + imag * imag);
}
