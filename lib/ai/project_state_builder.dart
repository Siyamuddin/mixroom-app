import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:mixroom/models/models.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

import '../models/project_state.dart';
import 'instrument_classifier.dart';

const int _kProjectAnalysisMaxMono16kSamples = 16000 * 30;
const int _kPromptStatsWindowOutputSamples = 12000;
const int _kPromptStatsWindowCount = 6;
const int _kPromptStatsMaxSamples =
    _kPromptStatsWindowOutputSamples * _kPromptStatsWindowCount;
const Map<String, double> _kFallbackPromptRoleProbs = <String, double>{
  'vocals': 0.17,
  'drums': 0.17,
  'bass': 0.17,
  'guitar': 0.17,
  'synth': 0.16,
  'other': 0.16,
};

class ProjectStateBuilder {
  static const int _kMaxPersistentNativePromptAnalysisEntries = 256;
  static const int _kMaxPersistentClipAnalysisEntries = 256;

  final InstrumentClassifier classifier;
  final int maxRows;
  final LinkedHashMap<String, _CachedNativePromptAnalysis>
      _persistentNativePromptAnalysis = LinkedHashMap();
  final LinkedHashMap<String, _CachedClipPromptAnalysis>
      _persistentClipPromptAnalysis = LinkedHashMap();

  ProjectStateBuilder({required this.classifier, this.maxRows = 0});

  String _clipPathSignature(String path) {
    try {
      final stat = FileStat.statSync(path);
      return '$path|${stat.modified.millisecondsSinceEpoch}|${stat.size}';
    } catch (_) {
      return '$path|unavailable';
    }
  }

  String _promptAnalysisCacheKey(AudioTrack track) =>
      '${track.file.path}|${track.trimStart.inMilliseconds}|${track.trimEnd.inMilliseconds}';

  String _promptAnalysisSignature(
    String baseSignature,
    AudioTrack track,
  ) =>
      '$baseSignature|${track.trimStart.inMilliseconds}|${track.trimEnd.inMilliseconds}';

  Map<String, dynamic>? _loadPersistentNativePromptAnalysis(
    String path,
    String signature,
  ) {
    final cached = _persistentNativePromptAnalysis.remove(path);
    if (cached == null) return null;
    if (cached.signature != signature) return null;
    _persistentNativePromptAnalysis[path] = cached;
    return cached.payload;
  }

  void _storePersistentNativePromptAnalysis(
    String path,
    String signature,
    Map<String, dynamic> payload,
  ) {
    _persistentNativePromptAnalysis.remove(path);
    _persistentNativePromptAnalysis[path] = _CachedNativePromptAnalysis(
      signature: signature,
      payload: payload,
    );
    while (_persistentNativePromptAnalysis.length >
        _kMaxPersistentNativePromptAnalysisEntries) {
      _persistentNativePromptAnalysis.remove(
        _persistentNativePromptAnalysis.keys.first,
      );
    }
  }

  _CachedClipPromptAnalysis? _loadPersistentClipPromptAnalysis(
    String path,
    String signature,
  ) {
    final cached = _persistentClipPromptAnalysis.remove(path);
    if (cached == null) return null;
    if (cached.signature != signature) return null;
    _persistentClipPromptAnalysis[path] = cached;
    return cached;
  }

  void _storePersistentClipPromptAnalysis(
    String path,
    String signature, {
    required Map<String, double> roleProbs,
    required Map<String, double> audioStats,
    required Map<String, double> stereoStats,
  }) {
    _persistentClipPromptAnalysis.remove(path);
    _persistentClipPromptAnalysis[path] = _CachedClipPromptAnalysis(
      signature: signature,
      roleProbs: Map<String, double>.from(roleProbs),
      audioStats: Map<String, double>.from(audioStats),
      stereoStats: Map<String, double>.from(stereoStats),
    );
    while (_persistentClipPromptAnalysis.length >
        _kMaxPersistentClipAnalysisEntries) {
      _persistentClipPromptAnalysis.remove(
        _persistentClipPromptAnalysis.keys.first,
      );
    }
  }

  Future<ProjectState> build({
    required List<AudioTrack> audioTracks,
    required double bpmFallback,
    required List<double> rowGain,
    required List<double> rowPan,
    required List<List<AutomationPoint>> rowAutomation,
    double masterGain0to3 = 1.0,
    double masterPan0to1 = 0.5,
    Map<int, String> roleOverrides = const {},
  }) async {
    int inferredRows = 0;
    if (rowGain.length > inferredRows) inferredRows = rowGain.length;
    if (rowPan.length > inferredRows) inferredRows = rowPan.length;
    if (rowAutomation.length > inferredRows) {
      inferredRows = rowAutomation.length;
    }
    if (roleOverrides.isNotEmpty) {
      final overrideMax = roleOverrides.keys
          .where((k) => k >= 0)
          .fold<int>(-1, (acc, v) => math.max(acc, v));
      if (overrideMax >= 0) {
        inferredRows = math.max(inferredRows, overrideMax + 1);
      }
    }
    for (final t in audioTracks) {
      if (t.rowIndex >= 0) {
        inferredRows = math.max(inferredRows, t.rowIndex + 1);
      }
    }
    final effectiveMaxRows = math.max(1, math.max(maxRows, inferredRows));

    double gainForRow(int row) {
      if (row < 0 || row >= rowGain.length) return kDefaultGainUi;
      return rowGain[row].clamp(0.0, 3.0).toDouble();
    }

    double panForRow(int row) {
      if (row < 0 || row >= rowPan.length) return 0.5;
      return rowPan[row].clamp(0.0, 1.0).toDouble();
    }

    List<AutomationPoint> automationForRow(int row) {
      if (row < 0 || row >= rowAutomation.length) {
        return <AutomationPoint>[
          AutomationPoint(x: 0.0, volume: 1.0),
          AutomationPoint(x: 1.0, volume: 1.0),
        ];
      }
      return rowAutomation[row];
    }

    final clipsByRow = List.generate(effectiveMaxRows, (_) => <ClipState>[]);

    // Keep duration per clip for roleConsistency weighting
    final clipDurMsByRow = List.generate(effectiveMaxRows, (_) => <double>[]);

    for (final t in audioTracks) {
      final fileName = t.file.path.split('/').last.split('.').first;
      final row = t.rowIndex;
      if (row < 0 || row >= effectiveMaxRows) continue;

      final startMs = t.offset * 1000.0;
      final durMs =
          (t.trimEnd - t.trimStart).inMilliseconds.toDouble().clamp(0.0, 1e12);
      final endMs = startMs + durMs;

      clipsByRow[row].add(ClipState(
        startMs: startMs,
        endMs: endMs,
        fileName: fileName,
        gain0to3: t.gain,
        pitchSemitones: t.pitchSemitones,
      ));
      clipDurMsByRow[row].add(durMs);
    }

    final overlap = List.generate(
        effectiveMaxRows, (_) => List.filled(effectiveMaxRows, 0));
    final overlapRatio = List.generate(
        effectiveMaxRows, (_) => List<double>.filled(effectiveMaxRows, 0.0));
    for (var i = 0; i < effectiveMaxRows; i++) {
      for (var j = 0; j < effectiveMaxRows; j++) {
        if (i == j) continue;
        final ratio = _rowsOverlapRatio(clipsByRow[i], clipsByRow[j]);
        overlapRatio[i][j] = ratio;
        overlap[i][j] = ratio > 0.0 ? 1 : 0;
      }
    }

    final monoPcmCache = <String, List<double>>{};
    final roleProbCache = <String, Map<String, double>>{};
    final monoStatsCache = <String, Map<String, double>>{};
    final stereoStatsCache = <String, Map<String, double>>{};
    final nativePromptAnalysisCache = <String, Map<String, dynamic>>{};
    final clipPathSignatureCache = <String, String>{};

    final rows = <RowState>[];
    for (var row = 0; row < effectiveMaxRows; row++) {
      final effects = <EffectState>[];

      final names = await JuceAudioEngine.getTrackEffectsForRow(row);
      for (int i = 0; i < names.length; i++) {
        final params = await JuceAudioEngine.getTrackPluginParameters(row, i);

        effects.add(
          EffectState(
            effectIndex: i,
            name: names[i],
            isBypassed: await JuceAudioEngine.getRowEffectBypassState(row, i),
            parameters: params
                .map((p) =>
                    EffectParameterState.fromMap(Map<String, dynamic>.from(p)))
                .toList(),
          ),
        );
      }

      final gain0to3 = gainForRow(row);
      final pan = panForRow(row);
      final automation = automationForRow(row);

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
            interpretation: RowInterpretationState.empty,
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
      final rowRoleAccum = <String, double>{
        'vocals': 0,
        'guitar': 0,
        'bass': 0,
        'drums': 0,
        'synth': 0,
        'other': 0
      };

      final clipTopRoles = <String>[];
      final roleWeightByTop = <String, double>{};

      // Aggregate audio stats
      double wSum = 0;
      final acc = <String, double>{
        'centroid_hz': 0,
        'zcr': 0,
        'hf_rms': 0,
        'st_rms_mean': 0,
        'st_rms_p95': 0,
        'st_rms_std': 0,
        'transient_density': 0,
        'true_peak_dbfs': 0,
        'integrated_lufs_est': 0,
        'short_lufs_mean': 0,
        'short_lufs_p95': 0,
        'lra_est': 0,
        'clip_ratio': 0,
        'spectral_flatness': 0,
        'spectral_rolloff_hz': 0,
        'spectral_slope': 0,
        'spectral_flux': 0,
        'spectral_bandwidth_hz': 0,
        'silence_ratio': 0,
        'activity_ratio': 0,
        'onset_rate_hz': 0,
        'noise_floor_dbfs': 0,
        'phase_corr': 0,
        'side_ratio': 0,
        'stereo_imbalance': 0,
        'low': 0,
        'lowmid': 0,
        'mid': 0,
        'high': 0,
        'sibilance': 0,
        'bassiness': 0,
      };

      for (int i = 0; i < rowTracks.length; i++) {
        final clip = rowTracks[i];
        final clipPath = clip.file.path;
        final analysisKey = _promptAnalysisCacheKey(clip);
        final durMs =
            (i < clipDurMsByRow[row].length) ? clipDurMsByRow[row][i] : 0.0;
        final w = durMs.clamp(
            100.0, 30000.0); // weight by duration, clamp to avoid extremes

        Map<String, double>? probs = roleProbCache[analysisKey];
        Map<String, double>? stereoStats = stereoStatsCache[clipPath];
        Map<String, double>? stats = monoStatsCache[analysisKey];
        if (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS) {
          var nativeAnalysis = nativePromptAnalysisCache[analysisKey];
          if (nativeAnalysis == null) {
            final baseSignature = clipPathSignatureCache.putIfAbsent(
              clipPath,
              () => _clipPathSignature(clipPath),
            );
            final signature = _promptAnalysisSignature(baseSignature, clip);
            nativeAnalysis =
                _loadPersistentNativePromptAnalysis(analysisKey, signature);
          }
          if (nativeAnalysis == null) {
            try {
              nativeAnalysis = await JuceAudioEngine.analyzeAudioForPrompt(
                clipPath,
                trimStartMs: clip.trimStart.inMilliseconds.toDouble(),
                trimEndMs: clip.trimEnd.inMilliseconds.toDouble(),
              );
            } catch (error) {
              debugPrint(
                'ProjectStateBuilder: analyzeAudioForPrompt failed for $clipPath: $error',
              );
              nativeAnalysis = const <String, dynamic>{};
            }
            final baseSignature = clipPathSignatureCache.putIfAbsent(
              clipPath,
              () => _clipPathSignature(clipPath),
            );
            final signature = _promptAnalysisSignature(baseSignature, clip);
            _storePersistentNativePromptAnalysis(
              analysisKey,
              signature,
              nativeAnalysis,
            );
          }
          nativePromptAnalysisCache[analysisKey] = nativeAnalysis;

          probs = probs ?? _mapToDoubleMap(nativeAnalysis['roleProbs']);
          if (probs.isEmpty) {
            probs = _kFallbackPromptRoleProbs;
          }
          roleProbCache[analysisKey] = probs;

          stats = stats ?? _mapToDoubleMap(nativeAnalysis['audioStats']);
          if (stats.isEmpty) {
            stats = _analyzePcm16k(const <double>[]);
          }
          monoStatsCache[analysisKey] = stats;
          stereoStats = const <String, double>{};
          stereoStatsCache[clipPath] = stereoStats;
        } else {
          final baseSignature = clipPathSignatureCache.putIfAbsent(
            clipPath,
            () => _clipPathSignature(clipPath),
          );
          final signature = _promptAnalysisSignature(baseSignature, clip);
          final persistentAnalysis = _loadPersistentClipPromptAnalysis(
            analysisKey,
            signature,
          );
          if (persistentAnalysis != null) {
            probs = persistentAnalysis.roleProbs;
            stats = persistentAnalysis.audioStats;
            stereoStats = persistentAnalysis.stereoStats;
            roleProbCache[analysisKey] = probs;
            monoStatsCache[analysisKey] = stats;
            stereoStatsCache[clipPath] = stereoStats;
          }

          List<double>? pcm = monoPcmCache[clipPath];
          if (pcm == null && (probs == null || stats == null)) {
            try {
              final pcmRaw =
                  await JuceAudioEngine.decodeAudioMono16kForAnalysis(
                clipPath,
                maxOutputSamples: _kProjectAnalysisMaxMono16kSamples,
              );
              pcm = _toDoubleList(pcmRaw);
            } catch (error) {
              debugPrint(
                'ProjectStateBuilder: decodeAudioMono16kForAnalysis failed for $clipPath: $error',
              );
              pcm = const <double>[];
            }
            monoPcmCache[clipPath] = pcm;
          }

          if (probs == null) {
            final pcmForAnalysis = _sparsePromptAnalysisSlice(
              pcm ?? const <double>[],
              trimStartMs: clip.trimStart.inMilliseconds.toDouble(),
              trimEndMs: clip.trimEnd.inMilliseconds.toDouble(),
            );
            final Float32List pcmF32 = Float32List.fromList(
              pcmForAnalysis.map((x) => x.toDouble()).toList(growable: false),
            );
            probs = await classifier.classifyAudio(pcmF32);
            roleProbCache[analysisKey] = probs;
          }

          if (stereoStats == null) {
            try {
              stereoStats =
                  await JuceAudioEngine.analyzeAudioStereo16k(clipPath);
            } catch (error) {
              debugPrint(
                'ProjectStateBuilder: analyzeAudioStereo16k failed for $clipPath: $error',
              );
              stereoStats = const <String, double>{};
            }
            stereoStatsCache[clipPath] = stereoStats;
          }

          if (stats == null) {
            stats = _analyzePcm16k(
              _sparsePromptAnalysisSlice(
                pcm ?? const <double>[],
                trimStartMs: clip.trimStart.inMilliseconds.toDouble(),
                trimEndMs: clip.trimEnd.inMilliseconds.toDouble(),
              ),
              stereoStats: stereoStats,
            );
            monoStatsCache[analysisKey] = stats;
          }

          _storePersistentClipPromptAnalysis(
            analysisKey,
            signature,
            roleProbs: probs,
            audioStats: stats,
            stereoStats: stereoStats,
          );
        }

        probs.forEach((k, v) {
          rowRoleAccum[k] = (rowRoleAccum[k] ?? 0) + v;
        });

        final topRole = _topRoleFromProbs(probs);
        clipTopRoles.add(topRole);
        roleWeightByTop[topRole] = (roleWeightByTop[topRole] ?? 0) + w;
        wSum += w;
        for (final e in acc.entries) {
          acc[e.key] = (acc[e.key] ?? 0) + w * (stats[e.key] ?? 0.0);
        }
      }

      var roleProbs = _normalize(rowRoleAccum);

      // Compute roleConsistency
      double roleConsistency = 1.0;
      if (roleWeightByTop.isNotEmpty) {
        final totalW =
            roleWeightByTop.values.fold<double>(0.0, (a, b) => a + b);
        final maxW =
            roleWeightByTop.values.fold<double>(0.0, (a, b) => math.max(a, b));
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

      final interpretation = _buildRowInterpretation(
        rowIndex: row,
        clips: clipsByRow[row],
        roleProbs: roleProbs,
        roleConsistency: roleConsistency,
        clipTopRoles: clipTopRoles,
        audioStats: audioStats,
        approxRms: rms,
        approxCrest: crest,
        overlapRatios: overlapRatio[row],
      );

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
          interpretation: interpretation,
          gain0to3: gain0to3,
          pan0To1: pan,
          effects: effects,
          volumeAutomation: automation,
          hasAudio: hasAudio,
        ),
      );
    }

    final masterEffects = <EffectState>[];
    final masterNames = await JuceAudioEngine.getMasterEffects();
    for (int i = 0; i < masterNames.length; i++) {
      final params = await JuceAudioEngine.getMasterPluginParameters(i);
      masterEffects.add(
        EffectState(
          effectIndex: i,
          name: masterNames[i],
          isBypassed: await JuceAudioEngine.getMasterEffectBypassState(i),
          parameters: params
              .map((p) =>
                  EffectParameterState.fromMap(Map<String, dynamic>.from(p)))
              .toList(),
        ),
      );
    }

    final bpm = bpmFallback;

    return ProjectState(
        bpm: bpm,
        masterGain0to3: masterGain0to3,
        masterPan0to1: masterPan0to1,
        maxRows: effectiveMaxRows,
        rows: rows,
        masterEffects: masterEffects,
        overlapMatrix: overlap,
        overlapRatioMatrix: overlapRatio);
  }

  double _rowsOverlapRatio(List<ClipState> a, List<ClipState> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;

    final aMerged = _mergeIntervals(a);
    final bMerged = _mergeIntervals(b);
    final totalA = _totalIntervalMs(aMerged);
    final totalB = _totalIntervalMs(bMerged);
    final denom = math.min(totalA, totalB);
    if (denom <= 1e-6) return 0.0;

    double overlapMs = 0.0;
    for (final ia in aMerged) {
      for (final ib in bMerged) {
        final s = math.max(ia.$1, ib.$1);
        final e = math.min(ia.$2, ib.$2);
        if (e > s) overlapMs += (e - s);
      }
    }
    return (overlapMs / denom).clamp(0.0, 1.0);
  }

  List<(double, double)> _mergeIntervals(List<ClipState> clips) {
    final intervals = clips
        .map((c) => (c.startMs, c.endMs))
        .where((iv) => iv.$2 > iv.$1)
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));

    if (intervals.isEmpty) return const [];

    final out = <(double, double)>[];
    var curS = intervals.first.$1;
    var curE = intervals.first.$2;

    for (int i = 1; i < intervals.length; i++) {
      final s = intervals[i].$1;
      final e = intervals[i].$2;
      if (s <= curE) {
        if (e > curE) curE = e;
      } else {
        out.add((curS, curE));
        curS = s;
        curE = e;
      }
    }
    out.add((curS, curE));
    return out;
  }

  double _totalIntervalMs(List<(double, double)> intervals) {
    double sum = 0.0;
    for (final iv in intervals) {
      sum += (iv.$2 - iv.$1).clamp(0.0, double.infinity);
    }
    return sum;
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
  if (pcmRaw is List<num>) {
    return pcmRaw.map((e) => e.toDouble()).toList(growable: false);
  }
  if (pcmRaw is Iterable) {
    return pcmRaw.map((e) => (e as num).toDouble()).toList(growable: false);
  }
  return const <double>[];
}

Map<String, double> _mapToDoubleMap(dynamic raw) {
  if (raw is! Map) return const <String, double>{};
  final out = <String, double>{};
  for (final entry in raw.entries) {
    final key = entry.key?.toString();
    final value = entry.value;
    if (key == null || value is! num) continue;
    out[key] = value.toDouble();
  }
  return out;
}

String _topRoleFromProbs(Map<String, double> probs) {
  if (probs.isEmpty) return 'other';
  final entries = probs.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = entries.first.key;
  return top.isEmpty ? 'other' : top;
}

RowInterpretationState _buildRowInterpretation({
  required int rowIndex,
  required List<ClipState> clips,
  required Map<String, double> roleProbs,
  required double roleConsistency,
  required List<String> clipTopRoles,
  required Map<String, double> audioStats,
  required double approxRms,
  required double approxCrest,
  required List<double> overlapRatios,
}) {
  if (clips.isEmpty) {
    return RowInterpretationState.empty;
  }

  final sortedRoles = roleProbs.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topRole = sortedRoles.isEmpty ? 'other' : sortedRoles.first.key;
  final topProb = sortedRoles.isEmpty ? 0.0 : sortedRoles.first.value;
  final secondProb = sortedRoles.length >= 2 ? sortedRoles[1].value : 0.0;
  final topRoleMargin = (topProb - secondProb).clamp(0.0, 1.0);
  final roleEntropy = _roleEntropy(roleProbs).clamp(0.0, 1.0);

  final uniqueTopRoles = clipTopRoles.toSet();
  final clipsRoleDisagreement =
      (uniqueTopRoles.length <= 1 || clipTopRoles.isEmpty)
          ? 0.0
          : ((uniqueTopRoles.length - 1) / math.max(1, roleProbs.length - 1))
              .clamp(0.0, 1.0);

  final overlapDensity = overlapRatios.isEmpty
      ? 0.0
      : (overlapRatios
                  .where((v) => v > 0.0)
                  .fold<double>(0.0, (sum, v) => sum + v.clamp(0.0, 1.0)) /
              overlapRatios.length)
          .clamp(0.0, 1.0);

  final centroidHz = _stat(audioStats, 'centroid_hz');
  final zcr = _stat(audioStats, 'zcr');
  final hfRms = _stat(audioStats, 'hf_rms');
  final transientDensity = _stat(audioStats, 'transient_density');
  final spectralFlatness = _stat(audioStats, 'spectral_flatness');
  final spectralBandwidthHz = _stat(audioStats, 'spectral_bandwidth_hz');
  final onsetRateHz = _stat(audioStats, 'onset_rate_hz');
  final bassiness = _stat(audioStats, 'bassiness');
  final sibilance = _stat(audioStats, 'sibilance');
  final sideRatio = _stat(audioStats, 'side_ratio');
  final phaseCorr = _stat(audioStats, 'phase_corr', fallback: 1.0);
  final stereoImbalance = _stat(audioStats, 'stereo_imbalance');
  final lra = _stat(audioStats, 'lra_est');
  final truePeakDbfs = _stat(audioStats, 'true_peak_dbfs', fallback: -120.0);
  final integratedLufs =
      _stat(audioStats, 'integrated_lufs_est', fallback: -120.0);
  final stRmsStd = _stat(audioStats, 'st_rms_std');
  final silenceRatio = _stat(audioStats, 'silence_ratio');
  final activityRatio = _stat(audioStats, 'activity_ratio');
  final low = _stat(audioStats, 'low');
  final mid = _stat(audioStats, 'mid');
  final high = _stat(audioStats, 'high');

  final coverageMs = _totalClipIntervalMs(_mergeClipIntervals(clips));
  final shortestClipMs = clips.fold<double>(
    double.infinity,
    (minValue, clip) =>
        math.min(minValue, (clip.endMs - clip.startMs).clamp(0.0, 1e12)),
  );
  final longestClipMs = clips.fold<double>(
    0.0,
    (maxValue, clip) =>
        math.max(maxValue, (clip.endMs - clip.startMs).clamp(0.0, 1e12)),
  );
  final clipCount = clips.length;
  final uniqueFileCount =
      clips.map((clip) => (clip.fileName ?? '').trim()).toSet().length;
  final repeatedMaterialLikely =
      clipCount >= 2 && uniqueFileCount < clipCount && longestClipMs <= 20000.0;

  final lowHeavy = low > (mid + high) * 0.85 || bassiness >= 1.15;
  final bright = centroidHz >= 3600 || hfRms >= 0.58 || sibilance >= 0.42;
  final broadband =
      spectralBandwidthHz >= 2200 || (low > 0 && mid > 0 && high > 0);
  final percussiveLikely = transientDensity >= 0.34 || onsetRateHz >= 3.0;
  final sustainHeavyLikely =
      transientDensity <= 0.12 && stRmsStd <= 0.14 && silenceRatio <= 0.18;
  final tonalHarmonicLikely = spectralFlatness <= 0.22 && zcr <= 0.18;
  final noiseLikeLikely = spectralFlatness >= 0.45 && zcr >= 0.16;
  final highFreqPresenceLikely = bright;
  final lowEndAnchorLikely =
      (roleProbs['bass'] ?? 0.0) >= 0.28 || lowHeavy || centroidHz <= 650;
  final wideStereoLikely =
      sideRatio >= 0.20 || (phaseCorr <= 0.35 && stereoImbalance <= 0.55);
  final monoCenterLikely =
      sideRatio <= 0.08 && stereoImbalance <= 0.15 && phaseCorr >= 0.65;

  final multiRoleLikely = roleEntropy >= 0.72 ||
      topRoleMargin <= 0.16 ||
      roleConsistency <= 0.58 ||
      clipsRoleDisagreement >= 0.35;
  final singleSourceLikely = roleEntropy <= 0.45 &&
      topRoleMargin >= 0.28 &&
      roleConsistency >= 0.72 &&
      clipsRoleDisagreement <= 0.20;
  final fullMixLikely = multiRoleLikely &&
      broadband &&
      activityRatio >= 0.72 &&
      wideStereoLikely &&
      (clipCount <= 2 || coverageMs >= 15000.0);
  final compositeStemLikely =
      multiRoleLikely && !fullMixLikely && roleConsistency <= 0.74;
  final oneShotLikely =
      coverageMs <= 2500.0 && percussiveLikely && silenceRatio >= 0.12;
  final loopLikely = !oneShotLikely &&
      coverageMs >= 350.0 &&
      coverageMs <= 18000.0 &&
      (repeatedMaterialLikely || (clipCount >= 3 && shortestClipMs <= 16000.0));
  final fxOrTextureLikely = (roleProbs['other'] ?? 0.0) >= 0.32 &&
      spectralFlatness >= 0.34 &&
      transientDensity <= 0.24 &&
      !lowEndAnchorLikely;
  final busLikeLikely =
      fullMixLikely && overlapDensity >= 0.24 && clipCount >= 2;

  final alreadyLoudLikely =
      integratedLufs >= -14.0 || truePeakDbfs >= -1.5 || approxRms >= 0.33;
  final alreadyCompressedLikely =
      lra <= 4.0 && stRmsStd <= 0.09 && approxCrest <= 1.8;
  final broadbandProcessingRisk = fullMixLikely || busLikeLikely;
  final stemSpecificProcessingRisk =
      compositeStemLikely || (multiRoleLikely && !singleSourceLikely);
  final overprocessingRisk =
      alreadyLoudLikely || alreadyCompressedLikely || broadbandProcessingRisk;

  final sourceType = () {
    if (busLikeLikely) return 'bus_like';
    if (fullMixLikely) return 'full_mix';
    if (fxOrTextureLikely) return 'fx_texture';
    if (oneShotLikely) return 'one_shot';
    if (loopLikely) return 'loop';
    if (compositeStemLikely) return 'composite_stem';
    if (multiRoleLikely) return 'multi_role';
    return 'single_source';
  }();

  final transientProfile = () {
    if (oneShotLikely || percussiveLikely) return 'percussive';
    if (sustainHeavyLikely) return 'sustained';
    return 'mixed';
  }();

  final spectralProfile = () {
    if (noiseLikeLikely) return 'noise_like';
    if (broadband) return 'broadband';
    if (lowHeavy) return 'low_heavy';
    if (bright) return 'bright';
    return 'mid_focused';
  }();

  final stereoProfile = () {
    if (wideStereoLikely && phaseCorr < 0.1) return 'wide_phasey';
    if (wideStereoLikely) return 'wide';
    if (monoCenterLikely) return 'monoish';
    return 'moderate';
  }();

  final editRisk = () {
    if (broadbandProcessingRisk || stemSpecificProcessingRisk) return 'high';
    if (overprocessingRisk || loopLikely || oneShotLikely) return 'medium';
    return 'low';
  }();

  final classificationConfidence = ((1.0 - roleEntropy) * 0.45 +
          topRoleMargin * 0.35 +
          roleConsistency.clamp(0.0, 1.0) * 0.20)
      .clamp(0.0, 1.0);

  final notes = <String>[
    if (fullMixLikely)
      'Looks like a full mix or premaster rather than a clean stem.',
    if (compositeStemLikely) 'Likely combines multiple roles in one row.',
    if (loopLikely) 'Likely short repeating loop material.',
    if (oneShotLikely) 'Likely one-shot or hit rather than a continuous stem.',
    if (fxOrTextureLikely) 'Likely FX, ambience, or texture material.',
    if (busLikeLikely) 'Behaves like a grouped or bus-like layer.',
    if (alreadyLoudLikely || alreadyCompressedLikely)
      'Already loud/controlled; avoid aggressive additional processing.',
    if (wideStereoLikely && !monoCenterLikely)
      'Stereo width is part of the sound.',
    if (singleSourceLikely && classificationConfidence >= 0.7)
      'Role classification looks relatively clean and stable.',
  ];

  return RowInterpretationState(
    topRole: topRole,
    sourceType: sourceType,
    transientProfile: transientProfile,
    spectralProfile: spectralProfile,
    stereoProfile: stereoProfile,
    editRisk: editRisk,
    roleEntropy: roleEntropy,
    topRoleMargin: topRoleMargin,
    classificationConfidence: classificationConfidence,
    clipsRoleDisagreement: clipsRoleDisagreement,
    overlapDensity: overlapDensity,
    singleSourceLikely: singleSourceLikely,
    multiRoleLikely: multiRoleLikely,
    compositeStemLikely: compositeStemLikely,
    fullMixLikely: fullMixLikely,
    loopLikely: loopLikely,
    oneShotLikely: oneShotLikely,
    fxOrTextureLikely: fxOrTextureLikely,
    busLikeLikely: busLikeLikely,
    lowEndAnchorLikely: lowEndAnchorLikely,
    highFreqPresenceLikely: highFreqPresenceLikely,
    percussiveLikely: percussiveLikely,
    tonalHarmonicLikely: tonalHarmonicLikely,
    noiseLikeLikely: noiseLikeLikely,
    wideStereoLikely: wideStereoLikely,
    monoCenterLikely: monoCenterLikely,
    broadbandProcessingRisk: broadbandProcessingRisk,
    stemSpecificProcessingRisk: stemSpecificProcessingRisk,
    overprocessingRisk: overprocessingRisk,
    alreadyLoudLikely: alreadyLoudLikely,
    alreadyCompressedLikely: alreadyCompressedLikely,
    notes: notes,
  );
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

double _roleEntropy(Map<String, double> roleProbs) {
  if (roleProbs.isEmpty) return 0.0;
  final values =
      roleProbs.values.where((v) => v > 1e-9).toList(growable: false);
  if (values.isEmpty) return 0.0;
  final logDenom = math.log(values.length);
  if (logDenom <= 1e-9) return 0.0;
  var entropy = 0.0;
  for (final p in values) {
    entropy += -p * math.log(p);
  }
  return (entropy / logDenom).clamp(0.0, 1.0);
}

List<(double, double)> _mergeClipIntervals(List<ClipState> clips) {
  final intervals = clips
      .map((c) => (c.startMs, c.endMs))
      .where((iv) => iv.$2 > iv.$1)
      .toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));

  if (intervals.isEmpty) return const [];

  final out = <(double, double)>[];
  var curS = intervals.first.$1;
  var curE = intervals.first.$2;

  for (int i = 1; i < intervals.length; i++) {
    final s = intervals[i].$1;
    final e = intervals[i].$2;
    if (s <= curE) {
      if (e > curE) curE = e;
    } else {
      out.add((curS, curE));
      curS = s;
      curE = e;
    }
  }
  out.add((curS, curE));
  return out;
}

double _totalClipIntervalMs(List<(double, double)> intervals) {
  var sum = 0.0;
  for (final iv in intervals) {
    sum += (iv.$2 - iv.$1).clamp(0.0, double.infinity);
  }
  return sum;
}

double _stat(
  Map<String, double> stats,
  String key, {
  double fallback = 0.0,
}) {
  final value = stats[key];
  if (value == null || !value.isFinite) return fallback;
  return value;
}

/// Lightweight static analysis using Goertzel magnitudes at a few bands.
/// Sample rate assumed 16k (decodeAudioMono16k).
///
/// Audio-stats glossary (keys emitted in `audioStats`):
/// - `centroid_hz`: spectral centroid; "brightness center of mass" in Hz.
/// - `zcr`: zero-crossing rate; rough noisiness/brightness proxy.
/// - `hf_rms`: high-frequency RMS proxy from first-difference energy.
/// - `st_rms_mean`: mean short-time RMS across frames.
/// - `st_rms_p95`: 95th percentile short-time RMS (near-loudest frames).
/// - `st_rms_std`: short-time RMS variability over time.
/// - `transient_density`: fraction of frames with abrupt energy rise.
/// - `true_peak_dbfs`: max absolute sample as dBFS (0 dBFS = full scale).
/// - `integrated_lufs_est`: coarse integrated loudness estimate (LUFS).
/// - `short_lufs_mean`: mean short-window LUFS estimate.
/// - `short_lufs_p95`: 95th percentile short-window LUFS estimate.
/// - `lra_est`: loudness-range estimate from short-window LUFS spread.
/// - `clip_ratio`: fraction of samples near full scale (possible clipping).
/// - `spectral_flatness`: tonality vs noise-likeness (0 tonal, 1 noisy).
/// - `spectral_rolloff_hz`: frequency below which ~85% spectral energy lies.
/// - `spectral_slope`: tilt of spectrum (negative = darker, positive = brighter).
/// - `spectral_flux`: frame-to-frame spectral change amount.
/// - `spectral_bandwidth_hz`: spread of spectral energy around centroid.
/// - `silence_ratio`: fraction of samples below low-amplitude threshold.
/// - `activity_ratio`: non-silence fraction (`1 - silence_ratio`).
/// - `onset_rate_hz`: estimated transient/onset events per second.
/// - `noise_floor_dbfs`: lower-percentile amplitude level as dBFS.
/// - `phase_corr`: L/R phase correlation (-1 opposite, +1 in-phase).
/// - `side_ratio`: side energy relative to mid (stereo width proxy).
/// - `stereo_imbalance`: L/R energy imbalance (0 centered, 1 imbalanced).
/// - `low`: coarse low-band energy proxy (Goertzel aggregate).
/// - `lowmid`: coarse low-mid energy proxy.
/// - `mid`: coarse mid-band energy proxy.
/// - `high`: coarse high-band energy proxy.
/// - `sibilance`: high-band emphasis vs lower bands.
/// - `bassiness`: low-band emphasis vs mid/high bands.
Map<String, double> _analyzePcm16k(
  List<double> pcm, {
  Map<String, double> stereoStats = const {},
}) {
  const fs = 16000.0;
  if (pcm.isEmpty) {
    return const {
      'centroid_hz': 0,
      'zcr': 0,
      'hf_rms': 0,
      'st_rms_mean': 0,
      'st_rms_p95': 0,
      'st_rms_std': 0,
      'transient_density': 0,
      'true_peak_dbfs': -120,
      'integrated_lufs_est': -120,
      'short_lufs_mean': -120,
      'short_lufs_p95': -120,
      'lra_est': 0,
      'clip_ratio': 0,
      'spectral_flatness': 0,
      'spectral_rolloff_hz': 0,
      'spectral_slope': 0,
      'spectral_flux': 0,
      'spectral_bandwidth_hz': 0,
      'silence_ratio': 0,
      'activity_ratio': 0,
      'onset_rate_hz': 0,
      'noise_floor_dbfs': -120,
      'phase_corr': 1,
      'side_ratio': 0,
      'stereo_imbalance': 0,
      'low': 0,
      'lowmid': 0,
      'mid': 0,
      'high': 0,
      'sibilance': 0,
      'bassiness': 0,
    };
  }

  final n = math.min(pcm.length, _kPromptStatsMaxSamples);
  final x = pcm.sublist(0, n);

  double sumSq = 0.0;
  for (final v in x) {
    sumSq += v * v;
  }
  final baseRms = math.sqrt(sumSq / math.max(1, x.length)).clamp(0.0, 1.0);

  // ZCR
  int zc = 0;
  for (int i = 1; i < x.length; i++) {
    final a = x[i - 1];
    final b = x[i];
    if ((a >= 0 && b < 0) || (a < 0 && b >= 0)) zc++;
  }
  final zcr = (zc / math.max(1, x.length - 1)).clamp(0.0, 1.0);

  double hfSumSq = 0.0;
  for (int i = 1; i < x.length; i++) {
    final hp = x[i] - x[i - 1];
    hfSumSq += hp * hp;
  }
  final hfRaw = math.sqrt(hfSumSq / math.max(1, x.length - 1));
  final hfRms = (hfRaw / (baseRms + 1e-9)).clamp(0.0, 1.0);

  final st = _windowedRmsStats(x, frameSize: 512, hop: 256);
  final lufsStats = _lufsStats16k(x);

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

  // centroid approx
  double num = 0;
  mags.forEach((f, m) => num += f * m);
  final centroidHz = (num / mags.values.fold<double>(1e-9, (a, b) => a + b))
      .clamp(0.0, 8000.0);

  final sibilance = (high / (mid + lowmid + low + 1e-9)).clamp(0.0, 5.0);
  final bassiness = (low / (mid + high + 1e-9)).clamp(0.0, 5.0);
  final truePeak = x.fold<double>(0.0, (m, v) => math.max(m, v.abs()));
  final truePeakDbfs = _linToDb(truePeak).clamp(-120.0, 0.0);
  final clipCount = x.where((v) => v.abs() >= 0.995).length;
  final clipRatio = (clipCount / math.max(1, x.length)).clamp(0.0, 1.0);
  final silenceCount = x.where((v) => v.abs() < 0.01).length;
  final silenceRatio = (silenceCount / math.max(1, x.length)).clamp(0.0, 1.0);
  final activityRatio = (1.0 - silenceRatio).clamp(0.0, 1.0);

  final spectralFlatness = _spectralFlatness(mags).clamp(0.0, 1.0);
  final spectralRolloffHz = _spectralRolloffHz(mags, 0.85).clamp(0.0, 8000.0);
  final spectralSlope = _spectralSlope(mags).clamp(-2.0, 2.0);
  final spectralFlux = _spectralFluxProxy(x, fs).clamp(0.0, 1.0);
  final spectralBandwidthHz =
      _spectralBandwidthHz(mags, centroidHz).clamp(0.0, 8000.0);
  final onsetRateHz = _onsetRateHz(x, fs).clamp(0.0, 20.0);

  final absValues = x.map((v) => v.abs()).toList()..sort();
  final noiseFloorAmp = _percentile(absValues, 0.10);
  final noiseFloorDbfs = _linToDb(noiseFloorAmp).clamp(-120.0, 0.0);

  final phaseCorr = (stereoStats['phase_corr'] ?? 1.0).clamp(-1.0, 1.0);
  final sideRatio = (stereoStats['side_ratio'] ?? 0.0).clamp(0.0, 2.0);
  final stereoImbalance =
      (stereoStats['stereo_imbalance'] ?? 0.0).clamp(0.0, 1.0);

  return {
    'centroid_hz': centroidHz,
    'zcr': zcr,
    'hf_rms': hfRms,
    'st_rms_mean': st.mean,
    'st_rms_p95': st.p95,
    'st_rms_std': st.std,
    'transient_density': st.transientDensity,
    'true_peak_dbfs': truePeakDbfs,
    'integrated_lufs_est': lufsStats.integratedLufs,
    'short_lufs_mean': lufsStats.shortMeanLufs,
    'short_lufs_p95': lufsStats.shortP95Lufs,
    'lra_est': lufsStats.lra,
    'clip_ratio': clipRatio,
    'spectral_flatness': spectralFlatness,
    'spectral_rolloff_hz': spectralRolloffHz,
    'spectral_slope': spectralSlope,
    'spectral_flux': spectralFlux,
    'spectral_bandwidth_hz': spectralBandwidthHz,
    'silence_ratio': silenceRatio,
    'activity_ratio': activityRatio,
    'onset_rate_hz': onsetRateHz,
    'noise_floor_dbfs': noiseFloorDbfs,
    'phase_corr': phaseCorr,
    'side_ratio': sideRatio,
    'stereo_imbalance': stereoImbalance,
    'low': low,
    'lowmid': lowmid,
    'mid': mid,
    'high': high,
    'sibilance': sibilance,
    'bassiness': bassiness,
  };
}

List<double> _sparsePromptAnalysisSlice(
  List<double> pcm, {
  required double trimStartMs,
  required double trimEndMs,
}) {
  if (pcm.isEmpty) return const <double>[];

  const samplesPerMs = 16.0;
  final safeStartMs = trimStartMs.isFinite ? math.max(0.0, trimStartMs) : 0.0;
  final safeEndMs = trimEndMs.isFinite ? math.max(safeStartMs, trimEndMs) : 0.0;

  final startSample = math.min(
    pcm.length,
    math.max(0, (safeStartMs * samplesPerMs).round()),
  );
  var endSample = safeEndMs > safeStartMs
      ? math.min(
          pcm.length,
          math.max(startSample, (safeEndMs * samplesPerMs).round()),
        )
      : pcm.length;
  if (endSample <= startSample) {
    endSample = pcm.length;
  }
  final available = endSample - startSample;
  if (available <= 0) return const <double>[];
  if (available <= _kPromptStatsWindowOutputSamples) {
    return pcm.sublist(startSample, endSample);
  }

  final maxOffset = available - _kPromptStatsWindowOutputSamples;
  final sparse = <double>[];
  for (int i = 0; i < _kPromptStatsWindowCount; i++) {
    final t = _kPromptStatsWindowCount <= 1
        ? 0.5
        : i / (_kPromptStatsWindowCount - 1);
    final offset = startSample + (t * maxOffset).round();
    final windowEnd = math.min(
      endSample,
      offset + _kPromptStatsWindowOutputSamples,
    );
    if (windowEnd <= offset) continue;
    sparse.addAll(pcm.sublist(offset, windowEnd));
  }
  return sparse.isEmpty ? pcm.sublist(startSample, endSample) : sparse;
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

double _linToDb(double linear) {
  return 20.0 * math.log(math.max(linear, 1e-9)) / math.ln10;
}

class _LufsStats {
  final double integratedLufs;
  final double shortMeanLufs;
  final double shortP95Lufs;
  final double lra;

  const _LufsStats({
    required this.integratedLufs,
    required this.shortMeanLufs,
    required this.shortP95Lufs,
    required this.lra,
  });
}

_LufsStats _lufsStats16k(List<double> x) {
  if (x.isEmpty) {
    return const _LufsStats(
      integratedLufs: -120.0,
      shortMeanLufs: -120.0,
      shortP95Lufs: -120.0,
      lra: 0.0,
    );
  }

  // Very lightweight K-weight-ish proxy.
  final kw = List<double>.filled(x.length, 0.0);
  if (x.isNotEmpty) kw[0] = x[0];
  for (int i = 1; i < x.length; i++) {
    kw[i] = x[i] - (0.97 * x[i - 1]);
  }

  double sumSq = 0.0;
  for (final v in kw) {
    sumSq += v * v;
  }
  final meanSq = sumSq / math.max(1, kw.length);
  final integrated =
      (-0.691 + (10.0 * math.log(math.max(meanSq, 1e-12)) / math.ln10))
          .clamp(-120.0, 0.0);

  // Approx short-term with 400ms windows / 200ms hop.
  const frame = 6400;
  const hop = 3200;
  final shortLufs = <double>[];
  for (int s = 0; s < kw.length; s += hop) {
    final e = math.min(s + frame, kw.length);
    if (e <= s) break;
    double ss = 0.0;
    for (int i = s; i < e; i++) {
      final v = kw[i];
      ss += v * v;
    }
    final ms = ss / (e - s);
    final lufs = (-0.691 + (10.0 * math.log(math.max(ms, 1e-12)) / math.ln10))
        .clamp(-120.0, 0.0);
    shortLufs.add(lufs);
    if (e == kw.length) break;
  }

  if (shortLufs.isEmpty) {
    return _LufsStats(
      integratedLufs: integrated,
      shortMeanLufs: integrated,
      shortP95Lufs: integrated,
      lra: 0.0,
    );
  }

  final mean = shortLufs.reduce((a, b) => a + b) / shortLufs.length;
  final sorted = List<double>.from(shortLufs)..sort();
  final p95 = _percentile(sorted, 0.95);
  final p10 = _percentile(sorted, 0.10);
  final lra = (p95 - p10).clamp(0.0, 40.0);

  return _LufsStats(
    integratedLufs: integrated,
    shortMeanLufs: mean.clamp(-120.0, 0.0),
    shortP95Lufs: p95.clamp(-120.0, 0.0),
    lra: lra,
  );
}

double _spectralFlatness(Map<double, double> mags) {
  if (mags.isEmpty) return 0.0;
  final vals = mags.values.map((m) => math.max(m, 1e-12)).toList();
  final logMean =
      vals.map((v) => math.log(v)).reduce((a, b) => a + b) / vals.length;
  final geo = math.exp(logMean);
  final arith = vals.reduce((a, b) => a + b) / vals.length;
  return (geo / math.max(arith, 1e-12)).clamp(0.0, 1.0);
}

double _spectralRolloffHz(Map<double, double> mags, double pct) {
  if (mags.isEmpty) return 0.0;
  final entries = mags.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  final total = entries.fold<double>(0.0, (a, e) => a + e.value);
  if (total <= 1e-12) return 0.0;
  final target = total * pct.clamp(0.0, 1.0);
  double acc = 0.0;
  for (final e in entries) {
    acc += e.value;
    if (acc >= target) return e.key;
  }
  return entries.last.key;
}

double _spectralSlope(Map<double, double> mags) {
  if (mags.length < 2) return 0.0;
  final xs = <double>[];
  final ys = <double>[];
  mags.forEach((f, m) {
    xs.add(math.log(math.max(f, 1.0)));
    ys.add(math.log(math.max(m, 1e-12)));
  });
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = ys.reduce((a, b) => a + b) / ys.length;
  double num = 0.0;
  double den = 0.0;
  for (int i = 0; i < xs.length; i++) {
    final dx = xs[i] - mx;
    num += dx * (ys[i] - my);
    den += dx * dx;
  }
  if (den <= 1e-12) return 0.0;
  return num / den;
}

double _spectralBandwidthHz(Map<double, double> mags, double centroidHz) {
  if (mags.isEmpty) return 0.0;
  final total = mags.values.fold<double>(0.0, (a, b) => a + b);
  if (total <= 1e-12) return 0.0;
  double num = 0.0;
  mags.forEach((f, m) {
    final d = f - centroidHz;
    num += m * d * d;
  });
  return math.sqrt(num / total);
}

double _onsetRateHz(List<double> x, double sampleRate) {
  if (x.length < 1024 || sampleRate <= 0.0) return 0.0;
  const frame = 512;
  const hop = 256;
  final frameRms = <double>[];

  for (int s = 0; s + frame <= x.length; s += hop) {
    double ss = 0.0;
    for (int i = s; i < s + frame; i++) {
      final v = x[i];
      ss += v * v;
    }
    frameRms.add(math.sqrt(ss / frame));
  }

  if (frameRms.length < 2) return 0.0;
  int onsets = 0;
  for (int i = 1; i < frameRms.length; i++) {
    final delta = frameRms[i] - frameRms[i - 1];
    if (delta > 0.06 && frameRms[i] > 0.02) {
      onsets++;
    }
  }

  final durationSec = x.length / sampleRate;
  if (durationSec <= 1e-6) return 0.0;
  return onsets / durationSec;
}

double _spectralFluxProxy(List<double> x, double fs) {
  if (x.length < 1024) return 0.0;
  const freqs = <double>[100, 250, 500, 1000, 3000, 6000];
  const frame = 512;
  const hop = 256;
  List<double>? prev;
  double fluxAcc = 0.0;
  int count = 0;

  for (int s = 0; s + frame <= x.length; s += hop) {
    final chunk = x.sublist(s, s + frame);
    final cur = <double>[];
    for (final f in freqs) {
      cur.add(_goertzelMag(chunk, fs, f));
    }
    if (prev != null) {
      double ss = 0.0;
      for (int i = 0; i < cur.length; i++) {
        final d = cur[i] - prev[i];
        if (d > 0) ss += d * d;
      }
      fluxAcc += math.sqrt(ss / cur.length);
      count++;
    }
    prev = cur;
  }

  if (count == 0) return 0.0;
  // rough normalization
  return (fluxAcc / count / 2.5).clamp(0.0, 1.0);
}

class _ShortTermRmsStats {
  final double mean;
  final double p95;
  final double std;
  final double transientDensity;

  const _ShortTermRmsStats({
    required this.mean,
    required this.p95,
    required this.std,
    required this.transientDensity,
  });
}

_ShortTermRmsStats _windowedRmsStats(
  List<double> x, {
  required int frameSize,
  required int hop,
}) {
  if (x.isEmpty || frameSize <= 0 || hop <= 0) {
    return const _ShortTermRmsStats(
      mean: 0.0,
      p95: 0.0,
      std: 0.0,
      transientDensity: 0.0,
    );
  }

  final frames = <double>[];
  for (int start = 0; start < x.length; start += hop) {
    final end = math.min(start + frameSize, x.length);
    if (end <= start) break;
    double ss = 0.0;
    for (int i = start; i < end; i++) {
      final v = x[i];
      ss += v * v;
    }
    final rms = math.sqrt(ss / (end - start)).clamp(0.0, 1.0);
    frames.add(rms);
    if (end == x.length) break;
  }

  if (frames.isEmpty) {
    return const _ShortTermRmsStats(
      mean: 0.0,
      p95: 0.0,
      std: 0.0,
      transientDensity: 0.0,
    );
  }

  final mean = (frames.reduce((a, b) => a + b) / frames.length).clamp(0.0, 1.0);

  double varAcc = 0.0;
  for (final v in frames) {
    final d = v - mean;
    varAcc += d * d;
  }
  final std = math.sqrt(varAcc / frames.length).clamp(0.0, 1.0);

  final sorted = List<double>.from(frames)..sort();
  final p95 = _percentile(sorted, 0.95).clamp(0.0, 1.0);

  int transientCount = 0;
  for (int i = 1; i < frames.length; i++) {
    if ((frames[i] - frames[i - 1]) > 0.06) transientCount++;
  }
  final transientDensity =
      (transientCount / math.max(1, frames.length - 1)).clamp(0.0, 1.0);

  return _ShortTermRmsStats(
    mean: mean,
    p95: p95,
    std: std,
    transientDensity: transientDensity,
  );
}

double _percentile(List<double> sorted, double q) {
  if (sorted.isEmpty) return 0.0;
  if (sorted.length == 1) return sorted.first;
  final qq = q.clamp(0.0, 1.0);
  final pos = qq * (sorted.length - 1);
  final lo = pos.floor();
  final hi = pos.ceil();
  if (lo == hi) return sorted[lo];
  final t = pos - lo;
  return sorted[lo] * (1.0 - t) + sorted[hi] * t;
}

class _CachedNativePromptAnalysis {
  final String signature;
  final Map<String, dynamic> payload;

  const _CachedNativePromptAnalysis({
    required this.signature,
    required this.payload,
  });
}

class _CachedClipPromptAnalysis {
  final String signature;
  final Map<String, double> roleProbs;
  final Map<String, double> audioStats;
  final Map<String, double> stereoStats;

  const _CachedClipPromptAnalysis({
    required this.signature,
    required this.roleProbs,
    required this.audioStats,
    required this.stereoStats,
  });
}
