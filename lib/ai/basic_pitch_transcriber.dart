import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'ai_debug.dart';

class BasicPitchNoteEvent {
  const BasicPitchNoteEvent({
    required this.startSeconds,
    required this.endSeconds,
    required this.pitchMidi,
    required this.amplitude,
  });

  final double startSeconds;
  final double endSeconds;
  final int pitchMidi;
  final double amplitude;
}

class BasicPitchModelOutput {
  const BasicPitchModelOutput({
    required this.note,
    required this.onset,
    required this.contour,
  });

  final List<Float32List> note;
  final List<Float32List> onset;
  final List<Float32List> contour;
}

class BasicPitchTranscriber {
  BasicPitchTranscriber._();

  static final BasicPitchTranscriber instance = BasicPitchTranscriber._();

  static const String kModelAssetPath = 'assets/models/basic_pitch_nmp.onnx';

  static const int _inputSampleRate = 22050;
  static const int _sourceSampleRate = 16000;
  static const int _fftHop = 256;
  static const int _audioWindowLengthSeconds = 2;
  static const int _annotationFps = _inputSampleRate ~/ _fftHop;
  static const int _annotationFrames =
      _annotationFps * _audioWindowLengthSeconds;
  static const int _audioWindowSamples =
      _inputSampleRate * _audioWindowLengthSeconds - _fftHop;
  static const int _windowOverlapFrames = 30;
  static const int _windowOverlapSamples = _windowOverlapFrames * _fftHop;
  static const int _windowHopSamples =
      _audioWindowSamples - _windowOverlapSamples;
  static const int _notesBins = 88;
  static const int _contourBins = 264;
  static const int _midiOffset = 21;
  static const int _maxFreqIdx = 87;
  static const int _defaultMinNoteLen = 11;
  static const int _energyTolerance = 11;
  static const double _magicAlignmentOffset = 0.0018;
  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;
  Future<OrtSession?>? _sessionLoadFuture;

  Future<List<BasicPitchNoteEvent>> transcribeMono16k(
    Float32List mono16k, {
    double onsetThreshold = 0.5,
    double frameThreshold = 0.3,
  }) async {
    if (mono16k.isEmpty) return const <BasicPitchNoteEvent>[];
    final session = await _ensureSession();
    if (session == null) return const <BasicPitchNoteEvent>[];

    final resampled = _resampleLinear(
      mono16k,
      inputRate: _sourceSampleRate,
      outputRate: _inputSampleRate,
    );
    if (resampled.isEmpty) return const <BasicPitchNoteEvent>[];

    final output = await _runModel(session, resampled);
    if (output == null) return const <BasicPitchNoteEvent>[];

    return decodeOutputToNoteEvents(
      output,
      onsetThreshold: onsetThreshold,
      frameThreshold: frameThreshold,
    );
  }

  Future<OrtSession?> _ensureSession() async {
    final existing = _session;
    if (existing != null) return existing;
    final inflight = _sessionLoadFuture;
    if (inflight != null) return inflight;
    final future = _loadSession();
    _sessionLoadFuture = future;
    final loaded = await future;
    _sessionLoadFuture = null;
    return loaded;
  }

  Future<OrtSession?> _loadSession() async {
    try {
      final session = await _ort.createSessionFromAsset(kModelAssetPath);
      _session = session;
      aiDebugLog(
        'basic-pitch',
        'loaded model input=${session.inputNames} output=${session.outputNames}',
      );
      return session;
    } catch (error) {
      aiDebugLog('basic-pitch', 'model load failed error=$error');
      _session = null;
      return null;
    }
  }

  Future<BasicPitchModelOutput?> _runModel(
    OrtSession session,
    Float32List audio22050,
  ) async {
    final outputNames = session.outputNames.toList(growable: false);
    if (session.inputNames.isEmpty || outputNames.isEmpty) {
      aiDebugLog('basic-pitch', 'session missing io names');
      return null;
    }

    final padded =
        Float32List(audio22050.length + (_windowOverlapSamples ~/ 2));
    padded.setRange(
      _windowOverlapSamples ~/ 2,
      (_windowOverlapSamples ~/ 2) + audio22050.length,
      audio22050,
    );

    final noteBatches = <List<Float32List>>[];
    final onsetBatches = <List<Float32List>>[];
    final contourBatches = <List<Float32List>>[];

    for (int start = 0; start < padded.length; start += _windowHopSamples) {
      final window = Float32List(_audioWindowSamples);
      final available = math.min(_audioWindowSamples, padded.length - start);
      if (available > 0) {
        window.setRange(0, available, padded, start);
      }

      OrtValue? inputTensor;
      Map<String, OrtValue>? outputs;
      try {
        inputTensor = await OrtValue.fromList(
          window,
          <int>[1, _audioWindowSamples, 1],
        );
        outputs = await session.run(
          <String, OrtValue>{session.inputNames.first: inputTensor},
        );
        final decoded = await _decodeBatchOutputs(outputs, outputNames);
        if (decoded == null) return null;
        noteBatches.add(decoded.note);
        onsetBatches.add(decoded.onset);
        contourBatches.add(decoded.contour);
      } catch (error) {
        aiDebugLog('basic-pitch', 'window inference failed error=$error');
        return null;
      } finally {
        if (outputs != null) {
          for (final value in outputs.values) {
            try {
              await value.dispose();
            } catch (_) {}
          }
        }
        if (inputTensor != null) {
          try {
            await inputTensor.dispose();
          } catch (_) {}
        }
      }
    }

    if (noteBatches.isEmpty || onsetBatches.isEmpty || contourBatches.isEmpty) {
      return null;
    }

    return BasicPitchModelOutput(
      note: _unwrapOutput(
        noteBatches,
        audioOriginalLength: audio22050.length,
      ),
      onset: _unwrapOutput(
        onsetBatches,
        audioOriginalLength: audio22050.length,
      ),
      contour: _unwrapOutput(
        contourBatches,
        audioOriginalLength: audio22050.length,
      ),
    );
  }

  Future<BasicPitchModelOutput?> _decodeBatchOutputs(
    Map<String, OrtValue> outputs,
    List<String> outputNames,
  ) async {
    final decoded = <String, List<Float32List>>{};
    for (final entry in outputs.entries) {
      final matrix = await _tensorToMatrix(entry.value);
      if (matrix != null) {
        decoded[entry.key] = matrix;
      }
    }
    if (decoded.isEmpty) return null;

    List<Float32List>? note;
    List<Float32List>? onset;
    List<Float32List>? contour;

    for (final entry in decoded.entries) {
      final matrix = entry.value;
      final bins = matrix.isEmpty ? 0 : matrix.first.length;
      if (bins == _contourBins &&
          (entry.key.contains(':0') ||
              entry.key.toLowerCase().contains('contour'))) {
        contour = matrix;
      } else if (bins == _notesBins &&
          (entry.key.contains(':1') ||
              entry.key.toLowerCase().contains('note'))) {
        note = matrix;
      } else if (bins == _notesBins &&
          (entry.key.contains(':2') ||
              entry.key.toLowerCase().contains('onset'))) {
        onset = matrix;
      }
    }

    contour ??= decoded.values.firstWhere(
      (matrix) => matrix.isNotEmpty && matrix.first.length == _contourBins,
      orElse: () => const <Float32List>[],
    );

    final noteCandidates = decoded.entries
        .where((entry) =>
            entry.value.isNotEmpty && entry.value.first.length == _notesBins)
        .map((entry) => MapEntry(entry.key, entry.value))
        .toList(growable: false);
    if (noteCandidates.length >= 2) {
      note ??= noteCandidates.reduce((a, b) {
        return _matrixMean(a.value) >= _matrixMean(b.value) ? a : b;
      }).value;
      onset ??= noteCandidates.reduce((a, b) {
        return _matrixMean(a.value) <= _matrixMean(b.value) ? a : b;
      }).value;
    } else if (noteCandidates.length == 1) {
      note ??= noteCandidates.first.value;
      onset ??= noteCandidates.first.value;
    }

    final resolvedNote = note;
    final resolvedOnset = onset;
    final resolvedContour = contour;
    if (resolvedNote == null ||
        resolvedOnset == null ||
        resolvedContour.isEmpty) {
      aiDebugLog(
        'basic-pitch',
        'failed to map outputs names=$outputNames decoded=${decoded.keys.toList()}',
      );
      return null;
    }

    return BasicPitchModelOutput(
      note: resolvedNote,
      onset: resolvedOnset,
      contour: resolvedContour,
    );
  }

  Future<List<Float32List>?> _tensorToMatrix(OrtValue value) async {
    try {
      final dynamic raw = await value.asList();
      return _extractMatrix(raw);
    } catch (error) {
      aiDebugLog('basic-pitch', 'tensor decode failed error=$error');
      return null;
    }
  }

  List<Float32List>? _extractMatrix(dynamic raw) {
    if (raw is List && raw.isNotEmpty) {
      if (raw.length == 1 && raw.first is List) {
        return _extractMatrix(raw.first);
      }
      if (raw.first is List || raw.first is Float32List) {
        final out = <Float32List>[];
        for (final row in raw) {
          if (row is Float32List) {
            out.add(Float32List.fromList(row));
            continue;
          }
          if (row is List) {
            final values = <double>[];
            for (final value in row) {
              if (value is num) {
                values.add(value.toDouble());
              }
            }
            out.add(Float32List.fromList(values));
            continue;
          }
          return null;
        }
        return out;
      }
    }
    return null;
  }

  Float32List _resampleLinear(
    Float32List input, {
    required int inputRate,
    required int outputRate,
  }) {
    if (input.isEmpty || inputRate <= 0 || outputRate <= 0) {
      return Float32List(0);
    }
    if (inputRate == outputRate) return Float32List.fromList(input);
    final outputLength =
        math.max(1, (input.length * outputRate / inputRate).round());
    final output = Float32List(outputLength);
    final ratio = inputRate / outputRate;
    for (int i = 0; i < outputLength; i++) {
      final sourcePos = i * ratio;
      final left = sourcePos.floor();
      final right = math.min(input.length - 1, left + 1);
      final t = sourcePos - left;
      final leftValue = input[left];
      final rightValue = input[right];
      output[i] = (leftValue * (1.0 - t)) + (rightValue * t);
    }
    return output;
  }

  List<Float32List> _unwrapOutput(
    List<List<Float32List>> batches, {
    required int audioOriginalLength,
  }) {
    if (batches.isEmpty) return const <Float32List>[];
    final trimFrames = (_windowOverlapFrames * 0.5).floor();
    final framesPerWindow = _annotationFrames - _windowOverlapFrames;
    final expectedWindows = audioOriginalLength / _windowHopSamples;
    final expectedFrameCount = math.max(
      1,
      (expectedWindows * framesPerWindow).floor(),
    );

    final out = <Float32List>[];
    for (final batch in batches) {
      if (batch.isEmpty) continue;
      final safeStart = trimFrames.clamp(0, batch.length);
      final safeEnd = math.max(safeStart, batch.length - trimFrames);
      out.addAll(batch.sublist(safeStart, safeEnd));
    }
    if (out.length <= expectedFrameCount) return out;
    return out.sublist(0, expectedFrameCount);
  }

  @visibleForTesting
  List<BasicPitchNoteEvent> decodeOutputToNoteEvents(
    BasicPitchModelOutput output, {
    double onsetThreshold = 0.5,
    double frameThreshold = 0.3,
    bool inferOnsets = true,
    int minNoteLength = _defaultMinNoteLen,
    bool useMelodiaTrick = true,
  }) {
    final frames = _cloneMatrix(output.note);
    final onsets = _cloneMatrix(output.onset);
    final contours = output.contour;
    if (frames.isEmpty || onsets.isEmpty || contours.isEmpty) {
      return const <BasicPitchNoteEvent>[];
    }

    if (inferOnsets) {
      _augmentOnsetsFromFrames(onsets, frames);
    }

    final noteEvents = _decodePolyphonicNotes(
      frames: frames,
      onsets: onsets,
      onsetThreshold: onsetThreshold,
      frameThreshold: frameThreshold,
      minNoteLength: minNoteLength,
      useMelodiaTrick: useMelodiaTrick,
    );
    if (noteEvents.isEmpty) return const <BasicPitchNoteEvent>[];

    final times = _modelFramesToTime(contours.length);
    final out = <BasicPitchNoteEvent>[];
    for (final event in noteEvents) {
      final startIndex = event.$1.clamp(0, times.length - 1);
      final endIndex = event.$2.clamp(0, times.length - 1);
      final startSeconds = times[startIndex];
      final endSeconds = math.max(startSeconds + 0.02, times[endIndex]);
      out.add(
        BasicPitchNoteEvent(
          startSeconds: startSeconds,
          endSeconds: endSeconds,
          pitchMidi: event.$3,
          amplitude: event.$4.clamp(0.0, 1.0),
        ),
      );
    }
    return out;
  }

  List<Float32List> _cloneMatrix(List<Float32List> matrix) {
    return matrix
        .map((row) => Float32List.fromList(row))
        .toList(growable: false);
  }

  void _augmentOnsetsFromFrames(
    List<Float32List> onsets,
    List<Float32List> frames,
  ) {
    if (onsets.isEmpty || frames.isEmpty) return;
    final nFrames = math.min(onsets.length, frames.length);
    final nFreqs = math.min(onsets.first.length, frames.first.length);
    double maxOnset = 0.0;
    for (int t = 0; t < nFrames; t++) {
      for (int f = 0; f < nFreqs; f++) {
        maxOnset = math.max(maxOnset, onsets[t][f]);
      }
    }

    final frameDiff = List<Float32List>.generate(
      nFrames,
      (_) => Float32List(nFreqs),
      growable: false,
    );
    double maxDiff = 0.0;
    for (int t = 0; t < nFrames; t++) {
      for (int f = 0; f < nFreqs; f++) {
        double bestDiff = double.infinity;
        for (int n = 1; n <= 2; n++) {
          double diff = 0.0;
          if (t >= n) {
            diff = frames[t][f] - frames[t - n][f];
            if (diff < 0.0) diff = 0.0;
          }
          bestDiff = math.min(bestDiff, diff);
        }
        final value = bestDiff.isFinite ? bestDiff : 0.0;
        frameDiff[t][f] = value;
        if (value > maxDiff) maxDiff = value;
      }
    }
    if (maxOnset <= 0.0 || maxDiff <= 0.0) return;

    final scale = maxOnset / maxDiff;
    for (int t = 0; t < nFrames; t++) {
      for (int f = 0; f < nFreqs; f++) {
        final inferred = frameDiff[t][f] * scale;
        if (inferred > onsets[t][f]) {
          onsets[t][f] = inferred;
        }
      }
    }
  }

  List<(int, int, int, double)> _decodePolyphonicNotes({
    required List<Float32List> frames,
    required List<Float32List> onsets,
    required double onsetThreshold,
    required double frameThreshold,
    required int minNoteLength,
    required bool useMelodiaTrick,
  }) {
    final nFrames = frames.length;
    if (nFrames == 0) return const <(int, int, int, double)>[];
    final nFreqs = frames.first.length;
    final remainingEnergy = _cloneMatrix(frames);

    final peakPairs = <(int, int)>[];
    for (int f = 0; f < nFreqs; f++) {
      for (int t = 1; t < nFrames - 1; t++) {
        final current = onsets[t][f];
        if (current < onsetThreshold) continue;
        if (current > onsets[t - 1][f] && current >= onsets[t + 1][f]) {
          peakPairs.add((t, f));
        }
      }
    }
    peakPairs.sort((a, b) {
      final byTime = b.$1.compareTo(a.$1);
      if (byTime != 0) return byTime;
      return b.$2.compareTo(a.$2);
    });

    final noteEvents = <(int, int, int, double)>[];
    for (final peak in peakPairs) {
      final noteStart = peak.$1;
      final freqIdx = peak.$2;
      if (noteStart >= nFrames - 1) continue;

      int i = noteStart + 1;
      int silenceFrames = 0;
      while (i < nFrames - 1 && silenceFrames < _energyTolerance) {
        if (remainingEnergy[i][freqIdx] < frameThreshold) {
          silenceFrames += 1;
        } else {
          silenceFrames = 0;
        }
        i += 1;
      }
      i -= silenceFrames;
      if (i - noteStart <= minNoteLength) continue;

      for (int t = noteStart; t < i; t++) {
        remainingEnergy[t][freqIdx] = 0.0;
        if (freqIdx < _maxFreqIdx) remainingEnergy[t][freqIdx + 1] = 0.0;
        if (freqIdx > 0) remainingEnergy[t][freqIdx - 1] = 0.0;
      }

      final amplitude = _meanColumn(frames, noteStart, i, freqIdx);
      noteEvents.add((noteStart, i, freqIdx + _midiOffset, amplitude));
    }

    if (!useMelodiaTrick) return noteEvents;

    while (true) {
      final maxPos = _argMax(remainingEnergy);
      if (maxPos == null) break;
      final maxEnergy = remainingEnergy[maxPos.$1][maxPos.$2];
      if (maxEnergy <= frameThreshold) break;

      final iMid = maxPos.$1;
      final freqIdx = maxPos.$2;
      remainingEnergy[iMid][freqIdx] = 0.0;

      int i = iMid + 1;
      int silenceFrames = 0;
      while (i < nFrames - 1 && silenceFrames < _energyTolerance) {
        if (remainingEnergy[i][freqIdx] < frameThreshold) {
          silenceFrames += 1;
        } else {
          silenceFrames = 0;
        }
        remainingEnergy[i][freqIdx] = 0.0;
        if (freqIdx < _maxFreqIdx) remainingEnergy[i][freqIdx + 1] = 0.0;
        if (freqIdx > 0) remainingEnergy[i][freqIdx - 1] = 0.0;
        i += 1;
      }
      final iEnd = i - 1 - silenceFrames;

      i = iMid - 1;
      silenceFrames = 0;
      while (i > 0 && silenceFrames < _energyTolerance) {
        if (remainingEnergy[i][freqIdx] < frameThreshold) {
          silenceFrames += 1;
        } else {
          silenceFrames = 0;
        }
        remainingEnergy[i][freqIdx] = 0.0;
        if (freqIdx < _maxFreqIdx) remainingEnergy[i][freqIdx + 1] = 0.0;
        if (freqIdx > 0) remainingEnergy[i][freqIdx - 1] = 0.0;
        i -= 1;
      }
      final iStart = i + 1 + silenceFrames;
      if (iEnd - iStart <= minNoteLength) continue;

      final amplitude = _meanColumn(frames, iStart, iEnd, freqIdx);
      noteEvents.add((iStart, iEnd, freqIdx + _midiOffset, amplitude));
    }

    noteEvents.sort((a, b) {
      final byStart = a.$1.compareTo(b.$1);
      if (byStart != 0) return byStart;
      return a.$3.compareTo(b.$3);
    });
    return noteEvents;
  }

  (int, int)? _argMax(List<Float32List> matrix) {
    int? bestT;
    int? bestF;
    double bestValue = double.negativeInfinity;
    for (int t = 0; t < matrix.length; t++) {
      final row = matrix[t];
      for (int f = 0; f < row.length; f++) {
        if (row[f] > bestValue) {
          bestValue = row[f];
          bestT = t;
          bestF = f;
        }
      }
    }
    if (bestT == null || bestF == null) return null;
    return (bestT, bestF);
  }

  double _meanColumn(
    List<Float32List> matrix,
    int start,
    int end,
    int column,
  ) {
    if (end <= start) return 0.0;
    double sum = 0.0;
    int count = 0;
    for (int t = start; t < end && t < matrix.length; t++) {
      if (column < matrix[t].length) {
        sum += matrix[t][column];
        count += 1;
      }
    }
    return count <= 0 ? 0.0 : sum / count;
  }

  double _matrixMean(List<Float32List> matrix) {
    if (matrix.isEmpty) return 0.0;
    double sum = 0.0;
    int count = 0;
    for (final row in matrix) {
      for (final value in row) {
        sum += value;
        count += 1;
      }
    }
    return count <= 0 ? 0.0 : sum / count;
  }

  List<double> _modelFramesToTime(int nFrames) {
    final times = List<double>.filled(nFrames, 0.0, growable: false);
    final windowOffset = (_fftHop / _inputSampleRate) *
            (_annotationFrames - (_audioWindowSamples / _fftHop)) +
        _magicAlignmentOffset;
    for (int i = 0; i < nFrames; i++) {
      final originalTime = (i * _fftHop) / _inputSampleRate;
      final windowNumber = (i / _annotationFrames).floorToDouble();
      times[i] = originalTime - (windowOffset * windowNumber);
    }
    return times;
  }
}
