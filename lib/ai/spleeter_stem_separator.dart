import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mixroom/ffmpeg/ffmpeg.dart';
import 'package:fftea/fftea.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef SpleeterProgressCallback = void Function(
  SpleeterSeparationProgress progress,
);

class SpleeterSeparationProgress {
  const SpleeterSeparationProgress({
    required this.stage,
    required this.progress,
    required this.message,
  });

  final String stage;
  final double progress;
  final String message;
}

class SpleeterStemSeparator {
  static const int kSampleRate = 44100;
  static const int kChannels = 2;

  static const int _kNfft = 4096;
  static const int _kHop = 1024;
  static const int _kModelBins = 1024;
  static const int _kFftBins = (_kNfft ~/ 2) + 1; // 2049
  static const int _kFramesPerSplit = 512;

  static const int _kExpectedModelMinBytes = 8 * 1024 * 1024;
  static const String _kModelDirName = 'spleeter_fp16';
  static const String _kVocalsModelName = 'vocals.fp16.onnx';
  static const String _kAccompanimentModelName = 'accompaniment.fp16.onnx';

  static const String _kBundledVocalsAssetPath =
      'assets/models/spleeter_vocals.fp16.onnx';
  static const String _kBundledAccompanimentAssetPath =
      'assets/models/spleeter_accompaniment.fp16.onnx';

  static const String _kDefaultVocalsUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-spleeter-2stems-fp16/resolve/main/vocals.fp16.onnx';
  static const String _kDefaultAccompanimentUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-spleeter-2stems-fp16/resolve/main/accompaniment.fp16.onnx';

  SpleeterStemSeparator({
    OnnxRuntime? runtime,
    http.Client? httpClient,
    String? vocalsModelUrl,
    String? accompanimentModelUrl,
    String? vocalsModelPathOverride,
    String? accompanimentModelPathOverride,
  })  : _ort = runtime ?? OnnxRuntime(),
        _httpClient = httpClient ?? http.Client(),
        _vocalsModelUrl = (vocalsModelUrl?.trim().isNotEmpty ?? false)
            ? vocalsModelUrl!.trim()
            : _kDefaultVocalsUrl,
        _accompanimentModelUrl =
            (accompanimentModelUrl?.trim().isNotEmpty ?? false)
                ? accompanimentModelUrl!.trim()
                : _kDefaultAccompanimentUrl,
        _vocalsModelPathOverride =
            (vocalsModelPathOverride?.trim().isNotEmpty ?? false)
                ? vocalsModelPathOverride!.trim()
                : null,
        _accompanimentModelPathOverride =
            (accompanimentModelPathOverride?.trim().isNotEmpty ?? false)
                ? accompanimentModelPathOverride!.trim()
                : null;

  final OnnxRuntime _ort;
  final http.Client _httpClient;
  final String _vocalsModelUrl;
  final String _accompanimentModelUrl;
  final String? _vocalsModelPathOverride;
  final String? _accompanimentModelPathOverride;

  final FFT _fft = FFT(_kNfft);

  OrtSession? _vocalsSession;
  OrtSession? _accompanimentSession;
  Future<({OrtSession vocals, OrtSession accompaniment})>? _sessionLoadFuture;
  bool _disposed = false;

  Future<void> dispose() async {
    _disposed = true;
    final vocals = _vocalsSession;
    final accompaniment = _accompanimentSession;
    _vocalsSession = null;
    _accompanimentSession = null;
    if (vocals != null) {
      await vocals.close();
    }
    if (accompaniment != null) {
      await accompaniment.close();
    }
    _httpClient.close();
  }

  Future<void> prewarm({
    bool includeSession = false,
    SpleeterProgressCallback? onProgress,
  }) async {
    await _ensureModelFiles(onProgress: onProgress);
    if (includeSession) {
      await _ensureSessions(onProgress: onProgress);
    }
  }

  Future<void> separateVocalsInstrumental({
    required String inputPath,
    required String vocalsOutputPath,
    required String instrumentalOutputPath,
    SpleeterProgressCallback? onProgress,
  }) async {
    if (_disposed) {
      throw StateError('SpleeterStemSeparator is already disposed.');
    }

    final source = File(inputPath);
    if (!source.existsSync()) {
      throw FileSystemException('Input file not found.', inputPath);
    }

    _notify(
      onProgress,
      stage: 'prepare',
      progress: 0.0,
      message: 'Preparing stem separation.',
    );

    final sessions = await _ensureSessions(onProgress: onProgress);
    final tmpDir = await getTemporaryDirectory();
    final prepFile = File(
      p.join(
        tmpDir.path,
        'spleeter_prep_${DateTime.now().microsecondsSinceEpoch}.wav',
      ),
    );

    try {
      await _convertToModelInputWav(
        inputPath: inputPath,
        outputPath: prepFile.path,
      );
      final decoded = _decodePcmWav(await prepFile.readAsBytes());
      if (decoded == null || decoded.frameCount <= 0) {
        throw const FormatException(
          'Failed to decode preprocessed audio for Spleeter.',
        );
      }

      final separated = await _separate(
        vocalsSession: sessions.vocals,
        accompanimentSession: sessions.accompaniment,
        audio: decoded,
        onProgress: onProgress,
      );

      _notify(
        onProgress,
        stage: 'write',
        progress: 0.97,
        message: 'Writing stem files.',
      );

      final vocalsFile = File(vocalsOutputPath);
      final instrumentalFile = File(instrumentalOutputPath);
      await vocalsFile.parent.create(recursive: true);
      await instrumentalFile.parent.create(recursive: true);

      await _writeStereoPcm16Wav(
        path: vocalsFile.path,
        sampleRate: kSampleRate,
        left: separated.vocalsLeft,
        right: separated.vocalsRight,
      );
      await _writeStereoPcm16Wav(
        path: instrumentalFile.path,
        sampleRate: kSampleRate,
        left: separated.instrumentalLeft,
        right: separated.instrumentalRight,
      );

      _notify(
        onProgress,
        stage: 'done',
        progress: 1.0,
        message: 'Stem separation complete.',
      );
    } finally {
      if (prepFile.existsSync()) {
        await prepFile.delete();
      }
    }
  }

  Future<({OrtSession vocals, OrtSession accompaniment})> _ensureSessions({
    SpleeterProgressCallback? onProgress,
  }) async {
    if (_disposed) {
      throw StateError('SpleeterStemSeparator is already disposed.');
    }

    final vocals = _vocalsSession;
    final accompaniment = _accompanimentSession;
    if (vocals != null && accompaniment != null) {
      return (vocals: vocals, accompaniment: accompaniment);
    }

    final inFlight = _sessionLoadFuture;
    if (inFlight != null) return inFlight;

    final future = _loadSessions(onProgress: onProgress);
    _sessionLoadFuture = future;
    try {
      final loaded = await future;
      _vocalsSession = loaded.vocals;
      _accompanimentSession = loaded.accompaniment;
      return loaded;
    } finally {
      _sessionLoadFuture = null;
    }
  }

  Future<({OrtSession vocals, OrtSession accompaniment})> _loadSessions({
    SpleeterProgressCallback? onProgress,
  }) async {
    final modelFiles = await _ensureModelFiles(onProgress: onProgress);
    _notify(
      onProgress,
      stage: 'load_models',
      progress: 0.0,
      message: 'Loading stem separation models.',
    );

    final options = OrtSessionOptions(
      intraOpNumThreads: 2,
      interOpNumThreads: 1,
      useArena: true,
    );

    final vocals =
        await _ort.createSession(modelFiles.vocals.path, options: options);
    final accompaniment = await _ort
        .createSession(modelFiles.accompaniment.path, options: options);

    if (vocals.inputNames.isEmpty ||
        vocals.outputNames.isEmpty ||
        accompaniment.inputNames.isEmpty ||
        accompaniment.outputNames.isEmpty) {
      await vocals.close();
      await accompaniment.close();
      throw const FormatException('Spleeter model I/O names are invalid.');
    }

    return (vocals: vocals, accompaniment: accompaniment);
  }

  Future<({File vocals, File accompaniment})> _ensureModelFiles({
    SpleeterProgressCallback? onProgress,
  }) async {
    final vocalsFile = await _vocalsModelFile();
    final accompanimentFile = await _accompanimentModelFile();

    if (!await _isUsableModelFile(vocalsFile)) {
      await _tryCopyBundledModelAsset(
        assetPath: _kBundledVocalsAssetPath,
        outputFile: vocalsFile,
        onProgress: onProgress,
      );
    }
    if (!await _isUsableModelFile(vocalsFile)) {
      await _downloadModelFile(
        modelUrl: _vocalsModelUrl,
        outputFile: vocalsFile,
        stage: 'download_vocals_model',
        onProgress: onProgress,
      );
    }
    if (!await _isUsableModelFile(vocalsFile)) {
      throw const FileSystemException('Spleeter vocals model is invalid.');
    }

    if (!await _isUsableModelFile(accompanimentFile)) {
      await _tryCopyBundledModelAsset(
        assetPath: _kBundledAccompanimentAssetPath,
        outputFile: accompanimentFile,
        onProgress: onProgress,
      );
    }
    if (!await _isUsableModelFile(accompanimentFile)) {
      await _downloadModelFile(
        modelUrl: _accompanimentModelUrl,
        outputFile: accompanimentFile,
        stage: 'download_accompaniment_model',
        onProgress: onProgress,
      );
    }
    if (!await _isUsableModelFile(accompanimentFile)) {
      throw const FileSystemException(
          'Spleeter accompaniment model is invalid.');
    }

    return (vocals: vocalsFile, accompaniment: accompanimentFile);
  }

  Future<File> _vocalsModelFile() async {
    if (_vocalsModelPathOverride != null) return File(_vocalsModelPathOverride);
    final supportDir = await getApplicationSupportDirectory();
    final modelDir =
        Directory(p.join(supportDir.path, 'models', _kModelDirName));
    await modelDir.create(recursive: true);
    return File(p.join(modelDir.path, _kVocalsModelName));
  }

  Future<File> _accompanimentModelFile() async {
    if (_accompanimentModelPathOverride != null) {
      return File(_accompanimentModelPathOverride);
    }
    final supportDir = await getApplicationSupportDirectory();
    final modelDir =
        Directory(p.join(supportDir.path, 'models', _kModelDirName));
    await modelDir.create(recursive: true);
    return File(p.join(modelDir.path, _kAccompanimentModelName));
  }

  Future<bool> _isUsableModelFile(File file) async {
    if (!await file.exists()) return false;
    final size = await file.length();
    return size >= _kExpectedModelMinBytes;
  }

  Future<void> _tryCopyBundledModelAsset({
    required String assetPath,
    required File outputFile,
    SpleeterProgressCallback? onProgress,
  }) async {
    try {
      _notify(
        onProgress,
        stage: 'prepare_model',
        progress: 0.0,
        message: 'Preparing bundled stem separation models.',
      );

      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.length < _kExpectedModelMinBytes) {
        return;
      }
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(bytes, flush: true);
    } on FlutterError {
      // Optional bundle path: fallback download is handled by caller.
    } on Exception {
      // Optional bundle path: fallback download is handled by caller.
    }
  }

  Future<void> _downloadModelFile({
    required String modelUrl,
    required File outputFile,
    required String stage,
    SpleeterProgressCallback? onProgress,
  }) async {
    final uri = Uri.tryParse(modelUrl);
    if (uri == null) {
      throw FormatException('Invalid model URL: $modelUrl');
    }

    _notify(
      onProgress,
      stage: stage,
      progress: 0.0,
      message: 'Downloading stem separation model.',
    );

    final request = http.Request('GET', uri);
    final response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Spleeter model download failed (HTTP ${response.statusCode}).',
        uri: uri,
      );
    }

    final tmpFile = File('${outputFile.path}.download');
    if (tmpFile.existsSync()) {
      await tmpFile.delete();
    }
    await tmpFile.parent.create(recursive: true);

    final sink = tmpFile.openWrite();
    var received = 0;
    final total = response.contentLength ?? 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final progress = (received / total).clamp(0.0, 1.0).toDouble();
          _notify(
            onProgress,
            stage: stage,
            progress: progress,
            message:
                'Downloading stem separation model ${(progress * 100).toStringAsFixed(0)}%.',
          );
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (received <= 0) {
      if (tmpFile.existsSync()) {
        await tmpFile.delete();
      }
      throw const HttpException('Spleeter model download returned no bytes.');
    }

    if (outputFile.existsSync()) {
      await outputFile.delete();
    }
    await tmpFile.rename(outputFile.path);
  }

  Future<void> _convertToModelInputWav({
    required String inputPath,
    required String outputPath,
  }) async {
    final inputEscaped = inputPath.replaceAll('"', r'\"');
    final outputEscaped = outputPath.replaceAll('"', r'\"');
    final command =
        '-y -i "$inputEscaped" -vn -ac 2 -ar $kSampleRate -c:a pcm_s16le "$outputEscaped"';
    final session = await FFmpegKit.execute(command);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code) || !File(outputPath).existsSync()) {
      throw const ProcessException(
        'ffmpeg',
        <String>[],
        'Failed to preprocess audio for Spleeter.',
      );
    }
  }

  Future<_SeparatedStereoPcm> _separate({
    required OrtSession vocalsSession,
    required OrtSession accompanimentSession,
    required _DecodedStereoPcm audio,
    SpleeterProgressCallback? onProgress,
  }) async {
    final frameCount = frameCountForSamples(audio.frameCount);
    final paddedFrameCount = paddedFrameCountForModel(frameCount);
    final splitCount = paddedFrameCount ~/ _kFramesPerSplit;
    final reconLength = ((frameCount - 1) * _kHop) + _kNfft;
    final finalLength = math.min(audio.frameCount, reconLength);

    final window = periodicHannWindow();
    final stftCh0 = _computeStft(
      audio.left,
      frameCount: frameCount,
      window: window,
    );
    final stftCh1 = _computeStft(
      audio.right,
      frameCount: frameCount,
      window: window,
    );

    final vocalsLeft = Float32List(reconLength);
    final vocalsRight = Float32List(reconLength);
    final accompanimentLeft = Float32List(reconLength);
    final accompanimentRight = Float32List(reconLength);
    final norm = Float32List(reconLength);

    final vocalsInputName = vocalsSession.inputNames.first;
    final vocalsOutputName = vocalsSession.outputNames.first;
    final accompanimentInputName = accompanimentSession.inputNames.first;
    final accompanimentOutputName = accompanimentSession.outputNames.first;

    final spectraVocals = Float64x2List(_kNfft);
    final spectraAccompaniment = Float64x2List(_kNfft);
    const double eps = 1e-10;
    const double halfEps = eps / 2.0;

    for (int frame = 0; frame < frameCount; frame++) {
      final frameStart = frame * _kHop;
      for (int n = 0; n < _kNfft; n++) {
        final dst = frameStart + n;
        if (dst >= reconLength) break;
        final w = window[n];
        norm[dst] += (w * w).toDouble();
      }
    }

    for (int split = 0; split < splitCount; split++) {
      final splitFrameStart = split * _kFramesPerSplit;
      final framesInBatch = _kFramesPerSplit;
      final inputLen = kChannels * framesInBatch * _kModelBins;
      final input = Float32List(inputLen);

      _fillModelInputForChannel(
        input: input,
        channel: 0,
        stft: stftCh0,
        splitFrameStart: splitFrameStart,
        framesInBatch: framesInBatch,
      );
      _fillModelInputForChannel(
        input: input,
        channel: 1,
        stft: stftCh1,
        splitFrameStart: splitFrameStart,
        framesInBatch: framesInBatch,
      );

      OrtValue? inputTensor;
      Map<String, OrtValue>? vocalsOutputs;
      Map<String, OrtValue>? accompanimentOutputs;
      try {
        inputTensor = await OrtValue.fromList(
          input,
          <int>[kChannels, 1, _kFramesPerSplit, _kModelBins],
        );

        vocalsOutputs = await vocalsSession
            .run(<String, OrtValue>{vocalsInputName: inputTensor});
        accompanimentOutputs = await accompanimentSession.run(
          <String, OrtValue>{accompanimentInputName: inputTensor},
        );

        final vocalsValue = vocalsOutputs[vocalsOutputName] ??
            (vocalsOutputs.isNotEmpty ? vocalsOutputs.values.first : null);
        final accompanimentValue =
            accompanimentOutputs[accompanimentOutputName] ??
                (accompanimentOutputs.isNotEmpty
                    ? accompanimentOutputs.values.first
                    : null);

        if (vocalsValue == null || accompanimentValue == null) {
          throw const FormatException('Spleeter output tensors not found.');
        }

        final vocalsRaw = await vocalsValue.asFlattenedList();
        final accompanimentRaw = await accompanimentValue.asFlattenedList();
        if (vocalsRaw.length < inputLen || accompanimentRaw.length < inputLen) {
          throw FormatException(
            'Spleeter output shape mismatch: ${vocalsRaw.length}/${accompanimentRaw.length} < $inputLen',
          );
        }

        for (int localFrame = 0; localFrame < framesInBatch; localFrame++) {
          final globalFrame = splitFrameStart + localFrame;
          if (globalFrame >= frameCount) break;

          _reconstructFrameForSource(
            channel: 0,
            globalFrame: globalFrame,
            localFrame: localFrame,
            framesInBatch: framesInBatch,
            sourceOutRaw: vocalsRaw,
            otherSourceOutRaw: accompanimentRaw,
            stft: stftCh0,
            output: vocalsLeft,
            window: window,
            spectraScratch: spectraVocals,
            eps: eps,
            halfEps: halfEps,
          );
          _reconstructFrameForSource(
            channel: 0,
            globalFrame: globalFrame,
            localFrame: localFrame,
            framesInBatch: framesInBatch,
            sourceOutRaw: accompanimentRaw,
            otherSourceOutRaw: vocalsRaw,
            stft: stftCh0,
            output: accompanimentLeft,
            window: window,
            spectraScratch: spectraAccompaniment,
            eps: eps,
            halfEps: halfEps,
          );
          _reconstructFrameForSource(
            channel: 1,
            globalFrame: globalFrame,
            localFrame: localFrame,
            framesInBatch: framesInBatch,
            sourceOutRaw: vocalsRaw,
            otherSourceOutRaw: accompanimentRaw,
            stft: stftCh1,
            output: vocalsRight,
            window: window,
            spectraScratch: spectraVocals,
            eps: eps,
            halfEps: halfEps,
          );
          _reconstructFrameForSource(
            channel: 1,
            globalFrame: globalFrame,
            localFrame: localFrame,
            framesInBatch: framesInBatch,
            sourceOutRaw: accompanimentRaw,
            otherSourceOutRaw: vocalsRaw,
            stft: stftCh1,
            output: accompanimentRight,
            window: window,
            spectraScratch: spectraAccompaniment,
            eps: eps,
            halfEps: halfEps,
          );
        }
      } finally {
        if (inputTensor != null) {
          await inputTensor.dispose();
        }
        if (vocalsOutputs != null) {
          for (final value in vocalsOutputs.values) {
            await value.dispose();
          }
        }
        if (accompanimentOutputs != null) {
          for (final value in accompanimentOutputs.values) {
            await value.dispose();
          }
        }
      }

      final progress = ((split + 1) / math.max(1, splitCount)).clamp(0.0, 1.0);
      _notify(
        onProgress,
        stage: 'infer',
        progress: progress.toDouble(),
        message: 'Separating stems (${split + 1}/$splitCount).',
      );
      if (split + 1 < splitCount) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    for (int i = 0; i < finalLength; i++) {
      final w = norm[i];
      if (w > 1e-8) {
        vocalsLeft[i] = _clampAudio(vocalsLeft[i] / w);
        vocalsRight[i] = _clampAudio(vocalsRight[i] / w);
        accompanimentLeft[i] = _clampAudio(accompanimentLeft[i] / w);
        accompanimentRight[i] = _clampAudio(accompanimentRight[i] / w);
      } else {
        vocalsLeft[i] = 0.0;
        vocalsRight[i] = 0.0;
        accompanimentLeft[i] = 0.0;
        accompanimentRight[i] = 0.0;
      }
    }

    return _SeparatedStereoPcm(
      vocalsLeft: Float32List.sublistView(vocalsLeft, 0, finalLength),
      vocalsRight: Float32List.sublistView(vocalsRight, 0, finalLength),
      instrumentalLeft:
          Float32List.sublistView(accompanimentLeft, 0, finalLength),
      instrumentalRight:
          Float32List.sublistView(accompanimentRight, 0, finalLength),
    );
  }

  void _fillModelInputForChannel({
    required Float32List input,
    required int channel,
    required _StftData stft,
    required int splitFrameStart,
    required int framesInBatch,
  }) {
    final channelOffset = channel * framesInBatch * _kModelBins;
    for (int localFrame = 0; localFrame < framesInBatch; localFrame++) {
      final globalFrame = splitFrameStart + localFrame;
      if (globalFrame >= stft.frameCount) continue;
      final stftFrameOffset = globalFrame * _kFftBins;
      final inputFrameOffset = channelOffset + (localFrame * _kModelBins);
      for (int bin = 0; bin < _kModelBins; bin++) {
        final re = stft.real[stftFrameOffset + bin];
        final im = stft.imag[stftFrameOffset + bin];
        input[inputFrameOffset + bin] = math.sqrt(re * re + im * im).toDouble();
      }
    }
  }

  void _reconstructFrameForSource({
    required int channel,
    required int globalFrame,
    required int localFrame,
    required int framesInBatch,
    required List<dynamic> sourceOutRaw,
    required List<dynamic> otherSourceOutRaw,
    required _StftData stft,
    required Float32List output,
    required Float32List window,
    required Float64x2List spectraScratch,
    required double eps,
    required double halfEps,
  }) {
    final stftFrameOffset = globalFrame * _kFftBins;
    final modelFrameOffset =
        ((channel * framesInBatch + localFrame) * _kModelBins);

    for (int bin = 0; bin < _kFftBins; bin++) {
      double mask = 0.0;
      if (bin < _kModelBins) {
        final src = (sourceOutRaw[modelFrameOffset + bin] as num).toDouble();
        final other =
            (otherSourceOutRaw[modelFrameOffset + bin] as num).toDouble();
        final srcSq = src * src;
        final otherSq = other * other;
        final denom = srcSq + otherSq + eps;
        mask = (srcSq + halfEps) / denom;
      }

      final re = stft.real[stftFrameOffset + bin] * mask;
      final im = stft.imag[stftFrameOffset + bin] * mask;
      spectraScratch[bin] = Float64x2(re.toDouble(), im.toDouble());
    }

    spectraScratch[0] = Float64x2(spectraScratch[0].x, 0.0);
    spectraScratch[_kNfft ~/ 2] = Float64x2(spectraScratch[_kNfft ~/ 2].x, 0.0);
    for (int bin = 1; bin < (_kNfft ~/ 2); bin++) {
      final z = spectraScratch[bin];
      spectraScratch[_kNfft - bin] = Float64x2(z.x, -z.y);
    }

    final frame = _fft.realInverseFft(spectraScratch);
    final sampleStart = globalFrame * _kHop;
    for (int n = 0; n < _kNfft; n++) {
      final dst = sampleStart + n;
      if (dst >= output.length) break;
      output[dst] += (frame[n] * window[n]).toDouble();
    }
  }

  _StftData _computeStft(
    Float32List samples, {
    required int frameCount,
    required Float32List window,
  }) {
    final real = Float32List(frameCount * _kFftBins);
    final imag = Float32List(frameCount * _kFftBins);
    final frameComplex = Float64x2List(_kNfft);

    for (int frame = 0; frame < frameCount; frame++) {
      final frameStart = frame * _kHop;
      for (int n = 0; n < _kNfft; n++) {
        final src = frameStart + n;
        final sample = src < samples.length ? samples[src] : 0.0;
        frameComplex[n] = Float64x2((sample * window[n]).toDouble(), 0.0);
      }
      _fft.inPlaceFft(frameComplex);

      final outOffset = frame * _kFftBins;
      for (int bin = 0; bin < _kFftBins; bin++) {
        final z = frameComplex[bin];
        real[outOffset + bin] = z.x.toDouble();
        imag[outOffset + bin] = z.y.toDouble();
      }
    }

    return _StftData(frameCount: frameCount, real: real, imag: imag);
  }

  static double _clampAudio(double value) {
    return value.clamp(-1.0, 1.0).toDouble();
  }

  @visibleForTesting
  static int frameCountForSamples(
    int sampleCount, {
    int nFft = _kNfft,
    int hop = _kHop,
  }) {
    if (sampleCount <= 0) return 1;
    if (sampleCount <= nFft) return 1;
    return ((sampleCount - nFft) ~/ hop) + 1;
  }

  @visibleForTesting
  static int paddedFrameCountForModel(
    int frameCount, {
    int framesPerSplit = _kFramesPerSplit,
  }) {
    if (frameCount <= 0) return framesPerSplit;
    final rem = frameCount % framesPerSplit;
    if (rem == 0) return frameCount;
    return frameCount + (framesPerSplit - rem);
  }

  @visibleForTesting
  static Float32List periodicHannWindow({int size = _kNfft}) {
    final w = Float32List(size);
    if (size <= 0) return w;
    final denom = size.toDouble();
    for (int i = 0; i < size; i++) {
      w[i] = (0.5 - 0.5 * math.cos((2.0 * math.pi * i) / denom)).toDouble();
    }
    return w;
  }

  void _notify(
    SpleeterProgressCallback? onProgress, {
    required String stage,
    required double progress,
    required String message,
  }) {
    if (onProgress == null) return;
    onProgress(
      SpleeterSeparationProgress(
        stage: stage,
        progress: progress.clamp(0.0, 1.0).toDouble(),
        message: message,
      ),
    );
  }

  _DecodedStereoPcm? _decodePcmWav(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final riff = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
    final wave = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
    if (riff != 'RIFF' || wave != 'WAVE') return null;

    final fmtChunkStart = _findWavChunk(bytes, 'fmt ');
    final dataChunkStart = _findWavChunk(bytes, 'data');
    if (fmtChunkStart < 0 || dataChunkStart < 0) return null;

    final fmtSize =
        ByteData.sublistView(bytes, fmtChunkStart + 4, fmtChunkStart + 8)
            .getUint32(0, Endian.little);
    if (fmtSize < 16) return null;
    final fmt = ByteData.sublistView(
      bytes,
      fmtChunkStart + 8,
      fmtChunkStart + 8 + fmtSize,
    );

    final audioFormat = fmt.getUint16(0, Endian.little);
    final channels = fmt.getUint16(2, Endian.little);
    final sampleRate = fmt.getUint32(4, Endian.little);
    final bitsPerSample = fmt.getUint16(14, Endian.little);
    if (audioFormat != 1 || (channels != 1 && channels != 2)) return null;
    if (bitsPerSample != 16) return null;

    final dataSize = ByteData.sublistView(
      bytes,
      dataChunkStart + 4,
      dataChunkStart + 8,
    ).getUint32(0, Endian.little);
    final dataOffset = dataChunkStart + 8;
    if (dataOffset + dataSize > bytes.length) return null;

    final frameSize = channels * 2;
    final frameCount = dataSize ~/ frameSize;
    if (frameCount <= 0) return null;

    final left = Float32List(frameCount);
    final right = Float32List(frameCount);
    final data = ByteData.sublistView(bytes, dataOffset, dataOffset + dataSize);

    int ptr = 0;
    for (int i = 0; i < frameCount; i++) {
      final l = data.getInt16(ptr, Endian.little) / 32768.0;
      ptr += 2;
      final r = channels == 2 ? data.getInt16(ptr, Endian.little) / 32768.0 : l;
      if (channels == 2) ptr += 2;
      left[i] = l.clamp(-1.0, 1.0).toDouble();
      right[i] = r.clamp(-1.0, 1.0).toDouble();
    }

    if (sampleRate != kSampleRate) {
      debugPrint(
        'SpleeterStemSeparator: unexpected sample rate $sampleRate. Expected $kSampleRate.',
      );
    }

    return _DecodedStereoPcm(
      sampleRate: sampleRate,
      left: left,
      right: right,
    );
  }

  int _findWavChunk(Uint8List bytes, String chunkId) {
    for (int i = 12; i + 8 <= bytes.length;) {
      final id = ascii.decode(bytes.sublist(i, i + 4), allowInvalid: true);
      final size =
          ByteData.sublistView(bytes, i + 4, i + 8).getUint32(0, Endian.little);
      if (id == chunkId) return i;
      i += 8 + size + (size.isOdd ? 1 : 0);
    }
    return -1;
  }

  Future<void> _writeStereoPcm16Wav({
    required String path,
    required int sampleRate,
    required Float32List left,
    required Float32List right,
  }) async {
    final frameCount = math.min(left.length, right.length);
    const int channels = 2;
    const int bitsPerSample = 16;
    const int bytesPerSample = bitsPerSample ~/ 8;
    final dataSize = frameCount * channels * bytesPerSample;
    final totalSize = 44 + dataSize;
    final bytes = Uint8List(totalSize);
    final bd = ByteData.view(bytes.buffer);

    void writeAscii(int offset, String value) {
      for (int i = 0; i < value.length; i++) {
        bd.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    bd.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
    bd.setUint16(32, channels * bytesPerSample, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    bd.setUint32(40, dataSize, Endian.little);

    int ptr = 44;
    for (int i = 0; i < frameCount; i++) {
      final l = (left[i].clamp(-1.0, 1.0) * 32767.0).round();
      final r = (right[i].clamp(-1.0, 1.0) * 32767.0).round();
      bd.setInt16(ptr, l, Endian.little);
      bd.setInt16(ptr + 2, r, Endian.little);
      ptr += 4;
    }

    await File(path).writeAsBytes(bytes, flush: true);
  }
}

class _StftData {
  const _StftData({
    required this.frameCount,
    required this.real,
    required this.imag,
  });

  final int frameCount;
  final Float32List real;
  final Float32List imag;
}

class _DecodedStereoPcm {
  const _DecodedStereoPcm({
    required this.sampleRate,
    required this.left,
    required this.right,
  });

  final int sampleRate;
  final Float32List left;
  final Float32List right;

  int get frameCount => math.min(left.length, right.length);
}

class _SeparatedStereoPcm {
  const _SeparatedStereoPcm({
    required this.vocalsLeft,
    required this.vocalsRight,
    required this.instrumentalLeft,
    required this.instrumentalRight,
  });

  final Float32List vocalsLeft;
  final Float32List vocalsRight;
  final Float32List instrumentalLeft;
  final Float32List instrumentalRight;
}
