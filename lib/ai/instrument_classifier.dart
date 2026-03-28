import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'ai_debug.dart';
import 'onnx_session_loader.dart';

class InstrumentClassifier {
  static const int _sr = 16000;
  static const int _frameSize = 15600; // ~0.975s at 16kHz
  static const int _numFrames = 3; // sample a few windows for robustness

  final bool enabled;
  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;

  InstrumentClassifier({this.enabled = true});

  Future<void> load() async {
    if (!enabled) return;
    try {
      _session = await createCpuSessionFromAsset(
        runtime: _ort,
        assetKey: 'assets/models/yamnet.onnx',
        scope: 'yamnet',
      );
      aiDebugLog('yamnet', 'classifier model loaded');
    } catch (e) {
      _session = null;
      aiDebugLog('yamnet', 'classifier model load failed error=$e');
    }
  }
  // Future<void> load() async {
  //   _session = await _ort.createSessionFromAsset('assets/models/yamnet.onnx');

  //   // Load model from Flutter assets
  //   // final bytes = await rootBundle.load('assets/models/yamnet.onnx');
  //   // final modelBytes = bytes.buffer.asUint8List();

  //   final options = OrtSessionOptions();
  //   // VERY important for mobile
  //   options.setIntraOpNumThreads(1);
  //   options.setInterOpNumThreads(1);
  //   options.setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableBasic);
  //   // options.setGraphOptimizationLevel(
  //   //   GraphOptimizationLevel.ORT_ENABLE_ALL,
  //   // );
  //   final directory = await getApplicationSupportDirectory();
  //   final modelPath = p.join(directory.path, 'yamnet.onnx');
  //   final modelFile = File(modelPath);

  //   if (!await modelFile.exists()) {
  //     print("Copying model asset to local storage...");
  //     final byteData = await rootBundle.load('assets/models/yamnet.onnx');

  //     // Ensure parent directory exists
  //     await modelFile.parent.create(recursive: true);

  //     await modelFile.writeAsBytes(
  //       byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
  //       flush: true,
  //     );
  //     print("Model copied to: $modelPath");
  //   }

  //   _session = OrtSession.fromFile(modelFile, options);
  //   // _session = OrtSession.fromBuffer(modelBytes, options);
  // }

  bool get isReady => !enabled || _session != null;

  /// pcm16k must be Float32 mono @ 16kHz (any length). We will sample frames.
  Future<Map<String, double>> classifyAudio(Float32List pcm16k) async {
    if (!enabled) return _fallback();
    final s = _session;

    if (s == null || pcm16k.isEmpty) return _fallback();

    // final inputName = s.inputNames.first;

    // Build a few fixed-size frames from the clip
    final frames = _pickFrames(pcm16k, frameSize: _frameSize, count: _numFrames);

    // Accumulate scores across frames
    List<double>? accum;
    int used = 0;

    for (final frame in frames) {
      // final outScores = _runOnce(s, inputName, frame);
      final outScores = await _runOnce(s, frame);
      if (outScores == null) continue;

      accum ??= List<double>.filled(outScores.length, 0.0);
      for (int i = 0; i < outScores.length; i++) {
        accum[i] += outScores[i];
      }
      used++;
    }

    if (accum == null || used == 0) return _fallback();
    for (int i = 0; i < accum.length; i++) {
      accum[i] /= used;
    }

    return _mapYamnetToRoles(accum);
  }

  Future<List<double>?> _runOnce(OrtSession session, Float32List frame) async {
    try {
      final inputName = session.inputNames.first;
      final outputName = session.outputNames.first;

      final inputTensor = await OrtValue.fromList(frame, [1, frame.length]);
      final inputs = {inputName: inputTensor};
      final outputs = await session.run(inputs);

      final result = outputs[outputName];
      if (result == null) return null;

      // 1. Get the nested list: e.g., [[0.1, 0.05, ...]]
      final List<dynamic> rawData = await result.asList();

      // 2. UNWRAP: Take the first inner list
      // rawData[0] is the Float32List containing the actual 521 scores
      final firstBatch = rawData.first;

      // 3. Convert that inner list to a standard Dart List<double>
      final List<double> scores = List<double>.from(firstBatch);

      // Cleanup
      await inputTensor.dispose();
      for (var value in outputs.values) {
        await value.dispose();
      }

      return scores;
    } catch (e) {
      aiDebugLog('yamnet', 'inference failed error=$e');
      return null;
    }
  }

  Future<void> dispose() async {
    final session = _session;
    _session = null;
    if (session == null) return;
    try {
      await session.close();
    } catch (_) {}
  }
  // List<double>? _runOnce(OrtSession session, String inputName, Float32List frame) {
  //   // Shape should match most YAMNet ONNX exports: [1, 15600]
  //   final inputTensor = OrtValueTensor.createTensorWithDataList(
  //     frame,
  //     [frame.length],
  //   );

  //   final outputs = session.run(
  //     OrtRunOptions(),
  //     {inputName: inputTensor},
  //   );

  //   inputTensor.release();

  //   try {
  //     if (outputs.isEmpty || outputs.first is! OrtValueTensor) return null;

  //     final raw = (outputs.first as OrtValueTensor).value;
  //     if (raw is! List || raw.isEmpty || raw.first is! List) return null;

  //     return (raw.first as List).cast<num>().map((e) => e.toDouble()).toList();
  //   } finally {
  //     // IMPORTANT: release every output
  //     for (final o in outputs) {
  //       o?.release();
  //     }
  //   }
  // }

  List<Float32List> _pickFrames(
    Float32List pcm, {
    required int frameSize,
    required int count,
  }) {
    if (pcm.length <= frameSize) {
      // Pad short audio
      final padded = Float32List(frameSize);
      padded.setRange(0, pcm.length, pcm);
      return [padded];
    }

    // Choose start/mid/end-ish offsets
    final offsets = <int>[];
    if (count <= 1) {
      offsets.add((pcm.length - frameSize) ~/ 2);
    } else {
      for (int i = 0; i < count; i++) {
        final t = (count == 1) ? 0.5 : (i / (count - 1));
        final off = (t * (pcm.length - frameSize)).round();
        offsets.add(off.clamp(0, pcm.length - frameSize));
      }
    }

    return offsets.map((off) => pcm.sublist(off, off + frameSize)).toList();
  }

  Map<String, double> _mapYamnetToRoles(List<double> scores) {
    double vocals = 0, guitar = 0, bass = 0, drums = 0, synth = 0;

    for (int i = 0; i < scores.length; i++) {
      final s = scores[i];

      // Guitar classes
      if (i == 135 || i == 136 || i == 138 || i == 141) guitar += s;

      // Bass
      if (i == 137) bass += s;

      // Drums
      if (i >= 156 && i <= 168) drums += s;

      // Vocals
      if (i == 0 || i == 24 || i == 31 || i == 249) vocals += s;

      // Synth / keys
      if (i == 153 || i == 147 || i == 148) synth += s;
    }

    return _normalize({
      'vocals': vocals,
      'guitar': guitar,
      'bass': bass,
      'drums': drums,
      'synth': synth,
      'other': 0.01,
    });
  }

  Map<String, double> _normalize(Map<String, double> m) {
    final sum = m.values.fold(0.0, (a, b) => a + b);
    if (sum <= 0) return _fallback();
    return m.map((k, v) => MapEntry(k, v / sum));
  }

  Map<String, double> _fallback() => {
        'vocals': 0.17,
        'drums': 0.17,
        'bass': 0.17,
        'guitar': 0.17,
        'synth': 0.16,
        'other': 0.16,
      };
}

// import 'dart:math' as math;
// import 'dart:typed_data';
// import 'package:flutter/services.dart';
// import 'package:onnxruntime/onnxruntime.dart';

// class InstrumentClassifier {
//   static const _sampleRate = 16000;

//   OrtSession? _session;

//   Future<void> load() async {
//     OrtEnv.instance.init();

//     final bytes = await rootBundle.load('assets/models/yamnet.onnx');
//     final modelBuffer = bytes.buffer.asUint8List();

//     final options = OrtSessionOptions();
//     _session = OrtSession.fromBuffer(modelBuffer, options);
//   }

//   bool get isReady => _session != null;

//   /// pcm16k must be Float32 mono @ 16kHz
//   Map<String, double> classifyAudio(Float32List pcm16k) {
//     if (_session == null || pcm16k.isEmpty) {
//       return _fallback();
//     }
//     final inputName = _session!.inputNames.first;

//     final inputTensor = OrtValueTensor.createTensorWithDataList(
//       pcm16k,
//       [1, pcm16k.length],
//     );
//     print("aaa");
//     print(_session!.inputNames);
//     for (int i = 0; i < _session!.inputNames.length; i++) {
//       print(_session!.inputNames[i]);
//     }

//     final outputs = _session!.run(
//       OrtRunOptions(),
//       {inputName: inputTensor},
//     );
//     print("aaaa");
//     inputTensor.release();

//     if (outputs.isEmpty || outputs.first is! OrtValueTensor) {
//       return _fallback();
//     }
//     print("aaaaa");
//     final raw = (outputs.first as OrtValueTensor).value;
//     outputs.first?.release();

//     if (raw is! List || raw.isEmpty || raw.first is! List) {
//       return _fallback();
//     }
//     print("aaaaaaaa");
//     final scores = (raw.first as List).cast<num>().map((e) => e.toDouble()).toList();
//     print("ab");
//     return _mapYamnetToRoles(scores);
//   }

//   Map<String, double> _mapYamnetToRoles(List<double> scores) {
//     double vocals = 0, guitar = 0, bass = 0, drums = 0, synth = 0;

//     for (int i = 0; i < scores.length; i++) {
//       final s = scores[i];

//       // Guitar classes
//       if (i == 135 || i == 136 || i == 138 || i == 141) guitar += s;

//       // Bass
//       if (i == 137) bass += s;

//       // Drums
//       if (i >= 156 && i <= 168) drums += s;

//       // Vocals
//       if (i == 0 || i == 24 || i == 31 || i == 249) vocals += s;

//       // Synth / keys
//       if (i == 153 || i == 147 || i == 148) synth += s;
//     }

//     final map = {
//       'vocals': vocals,
//       'guitar': guitar,
//       'bass': bass,
//       'drums': drums,
//       'synth': synth,
//       'other': 0.01,
//     };

//     return _normalize(map);
//   }

//   Map<String, double> _normalize(Map<String, double> m) {
//     final sum = m.values.fold(0.0, (a, b) => a + b);
//     if (sum <= 0) return _fallback();
//     return m.map((k, v) => MapEntry(k, v / sum));
//   }

//   Map<String, double> _fallback() => {
//         'vocals': 0.17,
//         'drums': 0.17,
//         'bass': 0.17,
//         'guitar': 0.17,
//         'synth': 0.16,
//         'other': 0.16,
//       };
// }

// import 'dart:math' as math;
// import 'dart:typed_data';
// import 'package:flutter/services.dart';
// import 'package:onnxruntime/onnxruntime.dart';

// class InstrumentClassifier {
//   OrtSession? _session;

//   Future<void> loadFromAsset(String assetPath) async {
//     // 1. Initialize the ONNX environment (Required once)
//     OrtEnv.instance.init();

//     final bytes = await rootBundle.load(assetPath);
//     final modelBuffer = bytes.buffer.asUint8List();

//     // 2. Create session options (Required as the 2nd argument)
//     final sessionOptions = OrtSessionOptions();

//     // 3. Pass the options to fromBuffer
//     _session = OrtSession.fromBuffer(modelBuffer, sessionOptions);
//   }

//   bool get isReady => _session != null;

//   Map<String, double> classify1DFeatures(List<double> features) {
//     final session = _session;
//     if (session == null) return _fallback();

//     if (session.inputNames.isEmpty) return _fallback();

//     final inputName = session.inputNames.first;

//     // --- Create input tensor ---
//     final inputTensor = OrtValueTensor.createTensorWithDataList(
//       Float32List.fromList(features),
//       [1, features.length],
//     );

//     // --- Run inference ---
//     final runOptions = OrtRunOptions();
//     final outputs = session.run(
//       runOptions,
//       {inputName: inputTensor},
//     );

//     if (outputs.isEmpty) return _fallback();

//     final outputValue = outputs.first;
//     // Check for null and type
//     if (outputValue == null || outputValue is! OrtValueTensor) return _fallback();

//     // --- Extract raw tensor data ---
//     // Use .value instead of getTensorDataAsList()
//     final value = outputValue.value;
//     if (value == null) return _fallback();

//     List<double> logits;

//     if (value is List<double>) {
//       logits = value;
//     } else if (value is List && value.isNotEmpty && value.first is List) {
//       logits = (value.first as List).cast<num>().map((e) => e.toDouble()).toList();
//     } else {
//       return _fallback();
//     }

//     // --- Cleanup resources (Crucial for FFI/Memory Management) ---
//     inputTensor.release();
//     runOptions.release();
//     for (var element in outputs) {
//       element?.release();
//     }

//     final probs = _softmax(logits);

//     const roles = ['vocals', 'drums', 'bass', 'guitar', 'synth', 'other'];

//     final result = <String, double>{};
//     for (int i = 0; i < roles.length; i++) {
//       result[roles[i]] = i < probs.length ? probs[i] : 0.0;
//     }

//     return _normalize(result);
//   }

//   // ------------------------
//   // Helpers
//   // ------------------------

//   Map<String, double> _fallback() => {
//         'vocals': 0.17,
//         'drums': 0.17,
//         'bass': 0.17,
//         'guitar': 0.17,
//         'synth': 0.16,
//         'other': 0.16,
//       };

//   List<double> _softmax(List<double> x) {
//     final maxVal = x.reduce((a, b) => a > b ? a : b);
//     final exps = x.map((v) => math.exp(v - maxVal)).toList();
//     final sum = exps.fold<double>(0, (a, b) => a + b);
//     if (sum == 0) return List.filled(x.length, 1.0 / x.length);
//     return exps.map((e) => e / sum).toList();
//   }

//   Map<String, double> _normalize(Map<String, double> m) {
//     final sum = m.values.fold<double>(0, (a, b) => a + b);
//     return m.map((k, v) => MapEntry(k, v / sum));
//   }
// }
