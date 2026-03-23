import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

enum Mp3BitrateMode { cbr, vbr, unknown }

class AudioSignalMetrics {
  final double peakAbsolute;
  final double rms;
  final double mean;

  const AudioSignalMetrics({
    required this.peakAbsolute,
    required this.rms,
    required this.mean,
  });

  double get peakDbfs => AudioFileAnalysis.dbfsFromAmplitude(peakAbsolute);
  double get rmsDbfs => AudioFileAnalysis.dbfsFromAmplitude(rms);
}

class AudioComparisonResult {
  final int comparedSamples;
  final int expectedLength;
  final int actualLength;
  final int bestOffsetSamples;
  final double maxAbsoluteError;
  final double meanAbsoluteError;
  final double rmsError;
  final double correlation;
  final bool bitExact;

  const AudioComparisonResult({
    required this.comparedSamples,
    required this.expectedLength,
    required this.actualLength,
    required this.bestOffsetSamples,
    required this.maxAbsoluteError,
    required this.meanAbsoluteError,
    required this.rmsError,
    required this.correlation,
    required this.bitExact,
  });
}

class WavFileAnalysis {
  final Uint8List _bytes;
  final int formatCode;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;

  const WavFileAnalysis({
    required Uint8List bytes,
    required this.formatCode,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  }) : _bytes = bytes;

  Uint8List get bytes => _bytes;
  int get bytesPerSample => (bitsPerSample / 8).round();
  int get bytesPerFrame => bytesPerSample * channels;
  int get frameCount => dataLength ~/ bytesPerFrame;
  Uint8List get pcmDataBytes =>
      Uint8List.sublistView(_bytes, dataOffset, dataOffset + dataLength);

  List<List<double>> decodeNormalizedChannels() {
    final data = ByteData.sublistView(_bytes);
    final output = List<List<double>>.generate(
      channels,
      (_) => List<double>.filled(frameCount, 0.0, growable: false),
      growable: false,
    );

    var offset = dataOffset;
    for (var frame = 0; frame < frameCount; frame++) {
      for (var channel = 0; channel < channels; channel++) {
        output[channel][frame] = _decodeWavSample(
          data,
          offset,
          formatCode,
          bitsPerSample,
        );
        offset += bytesPerSample;
      }
    }
    return output;
  }

  List<double> decodeNormalizedMono() {
    final channelSamples = decodeNormalizedChannels();
    if (channelSamples.isEmpty) return const <double>[];
    if (channelSamples.length == 1) {
      return List<double>.from(channelSamples.first, growable: false);
    }

    return List<double>.generate(
      frameCount,
      (index) {
        var sum = 0.0;
        for (final channel in channelSamples) {
          sum += channel[index];
        }
        return sum / channelSamples.length;
      },
      growable: false,
    );
  }

  bool pcmDataEquals(WavFileAnalysis other) {
    if (formatCode != other.formatCode ||
        sampleRate != other.sampleRate ||
        channels != other.channels ||
        bitsPerSample != other.bitsPerSample ||
        dataLength != other.dataLength) {
      return false;
    }

    final a = pcmDataBytes;
    final b = other.pcmDataBytes;
    if (a.lengthInBytes != b.lengthInBytes) return false;
    for (var i = 0; i < a.lengthInBytes; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class Mp3FileAnalysis {
  final bool hasId3v2Tag;
  final int sampleRate;
  final int channelCount;
  final int frameCount;
  final Set<int> observedBitratesKbps;
  final int averageBitrateKbps;
  final double estimatedDurationSeconds;
  final String? vbrTag;

  const Mp3FileAnalysis({
    required this.hasId3v2Tag,
    required this.sampleRate,
    required this.channelCount,
    required this.frameCount,
    required this.observedBitratesKbps,
    required this.averageBitrateKbps,
    required this.estimatedDurationSeconds,
    required this.vbrTag,
  });

  Mp3BitrateMode get bitrateMode {
    if (vbrTag == 'Xing' || vbrTag == 'VBRI') {
      return Mp3BitrateMode.vbr;
    }
    if (vbrTag == 'Info') {
      return Mp3BitrateMode.cbr;
    }
    if (observedBitratesKbps.length > 1) {
      return Mp3BitrateMode.vbr;
    }
    if (observedBitratesKbps.length == 1) {
      return Mp3BitrateMode.cbr;
    }
    return Mp3BitrateMode.unknown;
  }

  int? get nominalBitrateKbps {
    if (observedBitratesKbps.isEmpty) return null;
    if (observedBitratesKbps.length == 1) {
      return observedBitratesKbps.first;
    }
    return averageBitrateKbps;
  }
}

class AudioFileAnalysis {
  const AudioFileAnalysis._();

  static Future<WavFileAnalysis> parseWavFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return parseWavBytes(bytes);
  }

  static WavFileAnalysis parseWavBytes(Uint8List bytes) {
    if (bytes.lengthInBytes < 44) {
      throw const FormatException('WAV file is too small');
    }

    if (_ascii(bytes, 0, 4) != 'RIFF' || _ascii(bytes, 8, 12) != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE file');
    }

    final data = ByteData.sublistView(bytes);
    int? formatCode;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataOffset;
    int? dataLength;

    var cursor = 12;
    while (cursor + 8 <= bytes.lengthInBytes) {
      final chunkId = _ascii(bytes, cursor, cursor + 4);
      final chunkSize = data.getUint32(cursor + 4, Endian.little);
      final chunkDataStart = cursor + 8;
      final chunkDataEnd = math.min(
        bytes.lengthInBytes,
        chunkDataStart + chunkSize,
      );

      if (chunkId == 'fmt ') {
        if (chunkSize < 16 || chunkDataEnd - chunkDataStart < 16) {
          throw const FormatException('Invalid WAV fmt chunk');
        }
        var detectedFormatCode = data.getUint16(chunkDataStart, Endian.little);
        if (detectedFormatCode == 0xFFFE && chunkSize >= 40) {
          detectedFormatCode =
              data.getUint16(chunkDataStart + 24, Endian.little);
        }
        formatCode = detectedFormatCode;
        channels = data.getUint16(chunkDataStart + 2, Endian.little);
        sampleRate = data.getUint32(chunkDataStart + 4, Endian.little);
        bitsPerSample = data.getUint16(chunkDataStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkDataStart;
        dataLength = chunkDataEnd - chunkDataStart;
      }

      cursor = chunkDataStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (formatCode == null ||
        channels == null ||
        sampleRate == null ||
        bitsPerSample == null ||
        dataOffset == null ||
        dataLength == null) {
      throw const FormatException('Incomplete WAV file');
    }

    return WavFileAnalysis(
      bytes: bytes,
      formatCode: formatCode,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      dataOffset: dataOffset,
      dataLength: dataLength,
    );
  }

  static Future<Mp3FileAnalysis> parseMp3File(String path) async {
    final bytes = await File(path).readAsBytes();
    return parseMp3Bytes(bytes);
  }

  static Mp3FileAnalysis parseMp3Bytes(Uint8List bytes) {
    if (bytes.lengthInBytes < 4) {
      throw const FormatException('MP3 file is too small');
    }

    final hasId3v2 = _ascii(bytes, 0, 3) == 'ID3';
    var offset = hasId3v2 ? _skipId3v2(bytes) : 0;
    _Mp3FrameHeader? firstHeader;
    String? vbrTag;
    final observedBitrates = <int>[];
    var frameCount = 0;
    var totalSamples = 0;
    var lockedToFrameSequence = false;

    while (offset + 4 <= bytes.lengthInBytes) {
      final header = _tryParseMp3FrameHeader(bytes, offset);
      if (header == null) {
        if (lockedToFrameSequence) break;
        offset++;
        continue;
      }

      lockedToFrameSequence = true;
      firstHeader ??= header;
      if (frameCount == 0) {
        vbrTag = _detectMp3VbrTag(bytes, offset, header.frameLength);
      }

      observedBitrates.add(header.bitrateKbps);
      frameCount++;
      totalSamples += header.samplesPerFrame;

      final nextOffset = offset + header.frameLength;
      if (nextOffset <= offset) break;
      offset = nextOffset;
    }

    if (firstHeader == null || frameCount == 0) {
      throw const FormatException('Unable to locate MP3 frames');
    }

    final averageBitrate = observedBitrates.isEmpty
        ? 0
        : (observedBitrates.reduce((a, b) => a + b) / observedBitrates.length)
            .round();

    return Mp3FileAnalysis(
      hasId3v2Tag: hasId3v2,
      sampleRate: firstHeader.sampleRate,
      channelCount: firstHeader.channelCount,
      frameCount: frameCount,
      observedBitratesKbps: observedBitrates.toSet(),
      averageBitrateKbps: averageBitrate,
      estimatedDurationSeconds: totalSamples / firstHeader.sampleRate,
      vbrTag: vbrTag,
    );
  }

  static AudioSignalMetrics measureSamples(List<double> samples) {
    if (samples.isEmpty) {
      return const AudioSignalMetrics(
        peakAbsolute: 0.0,
        rms: 0.0,
        mean: 0.0,
      );
    }

    var peak = 0.0;
    var sum = 0.0;
    var sumSquares = 0.0;
    for (final sample in samples) {
      final absValue = sample.abs();
      if (absValue > peak) peak = absValue;
      sum += sample;
      sumSquares += sample * sample;
    }

    final length = samples.length.toDouble();
    return AudioSignalMetrics(
      peakAbsolute: peak,
      rms: math.sqrt(sumSquares / length),
      mean: sum / length,
    );
  }

  static double dbfsFromAmplitude(double amplitude) {
    if (amplitude <= 0.0) return double.negativeInfinity;
    return 20.0 * math.log(amplitude) / math.ln10;
  }

  static AudioComparisonResult compareSamples(
    List<double> expected,
    List<double> actual, {
    int maxOffsetSamples = 0,
  }) {
    if (expected.isEmpty || actual.isEmpty) {
      return AudioComparisonResult(
        comparedSamples: 0,
        expectedLength: expected.length,
        actualLength: actual.length,
        bestOffsetSamples: 0,
        maxAbsoluteError: double.infinity,
        meanAbsoluteError: double.infinity,
        rmsError: double.infinity,
        correlation: 0.0,
        bitExact: false,
      );
    }

    AudioComparisonResult? best;
    for (var offset = -maxOffsetSamples; offset <= maxOffsetSamples; offset++) {
      final expectedStart = offset < 0 ? -offset : 0;
      final actualStart = offset > 0 ? offset : 0;
      final comparedSamples = math.min(
        expected.length - expectedStart,
        actual.length - actualStart,
      );
      if (comparedSamples <= 0) continue;

      var maxAbsoluteError = 0.0;
      var sumAbsoluteError = 0.0;
      var sumSquaredError = 0.0;
      var dot = 0.0;
      var expectedEnergy = 0.0;
      var actualEnergy = 0.0;
      var exact = true;

      for (var i = 0; i < comparedSamples; i++) {
        final expectedSample = expected[expectedStart + i];
        final actualSample = actual[actualStart + i];
        final error = actualSample - expectedSample;
        final absError = error.abs();
        if (absError > maxAbsoluteError) {
          maxAbsoluteError = absError;
        }
        if (absError != 0.0) exact = false;
        sumAbsoluteError += absError;
        sumSquaredError += error * error;
        dot += expectedSample * actualSample;
        expectedEnergy += expectedSample * expectedSample;
        actualEnergy += actualSample * actualSample;
      }

      final rmsError = math.sqrt(sumSquaredError / comparedSamples);
      final meanAbsoluteError = sumAbsoluteError / comparedSamples;
      final correlation = expectedEnergy > 0.0 && actualEnergy > 0.0
          ? dot / math.sqrt(expectedEnergy * actualEnergy)
          : 0.0;

      final result = AudioComparisonResult(
        comparedSamples: comparedSamples,
        expectedLength: expected.length,
        actualLength: actual.length,
        bestOffsetSamples: offset,
        maxAbsoluteError: maxAbsoluteError,
        meanAbsoluteError: meanAbsoluteError,
        rmsError: rmsError,
        correlation: correlation,
        bitExact: exact &&
            offset == 0 &&
            expected.length == actual.length &&
            comparedSamples == expected.length,
      );

      if (best == null ||
          result.rmsError < best.rmsError ||
          (result.rmsError == best.rmsError &&
              result.correlation > best.correlation) ||
          (result.rmsError == best.rmsError &&
              result.correlation == best.correlation &&
              result.comparedSamples > best.comparedSamples)) {
        best = result;
      }
    }

    return best ??
        AudioComparisonResult(
          comparedSamples: 0,
          expectedLength: expected.length,
          actualLength: actual.length,
          bestOffsetSamples: 0,
          maxAbsoluteError: double.infinity,
          meanAbsoluteError: double.infinity,
          rmsError: double.infinity,
          correlation: 0.0,
          bitExact: false,
        );
  }

  static String _ascii(Uint8List bytes, int start, int end) {
    if (start < 0 || end > bytes.lengthInBytes || start >= end) return '';
    return String.fromCharCodes(bytes.sublist(start, end));
  }

  static int _skipId3v2(Uint8List bytes) {
    if (bytes.lengthInBytes < 10 || _ascii(bytes, 0, 3) != 'ID3') {
      return 0;
    }
    final size = ((bytes[6] & 0x7F) << 21) |
        ((bytes[7] & 0x7F) << 14) |
        ((bytes[8] & 0x7F) << 7) |
        (bytes[9] & 0x7F);
    return math.min(bytes.lengthInBytes, 10 + size);
  }

  static String? _detectMp3VbrTag(
    Uint8List bytes,
    int frameOffset,
    int frameLength,
  ) {
    final searchEnd = math.min(
      bytes.lengthInBytes,
      frameOffset + math.min(frameLength, 160),
    );
    for (var cursor = frameOffset + 4; cursor + 4 <= searchEnd; cursor++) {
      final tag = _ascii(bytes, cursor, cursor + 4);
      if (tag == 'Xing' || tag == 'Info' || tag == 'VBRI') {
        return tag;
      }
    }
    return null;
  }

  static _Mp3FrameHeader? _tryParseMp3FrameHeader(
    Uint8List bytes,
    int offset,
  ) {
    if (offset + 4 > bytes.lengthInBytes) return null;
    final b0 = bytes[offset];
    final b1 = bytes[offset + 1];
    final b2 = bytes[offset + 2];
    final b3 = bytes[offset + 3];

    if (b0 != 0xFF || (b1 & 0xE0) != 0xE0) return null;

    final versionBits = (b1 >> 3) & 0x03;
    if (versionBits == 0x01) return null;
    final layerBits = (b1 >> 1) & 0x03;
    if (layerBits != 0x01) return null;

    final bitrateIndex = (b2 >> 4) & 0x0F;
    final sampleRateIndex = (b2 >> 2) & 0x03;
    final paddingBit = (b2 >> 1) & 0x01;
    if (bitrateIndex == 0 || bitrateIndex == 0x0F || sampleRateIndex == 0x03) {
      return null;
    }

    final channelMode = (b3 >> 6) & 0x03;
    final version = switch (versionBits) {
      0x03 => _Mp3MpegVersion.v1,
      0x02 => _Mp3MpegVersion.v2,
      0x00 => _Mp3MpegVersion.v25,
      _ => null,
    };
    if (version == null) return null;

    final bitrateKbps = _mp3BitrateKbps(version, bitrateIndex);
    final sampleRate = _mp3SampleRate(version, sampleRateIndex);
    if (bitrateKbps == null || sampleRate == null) return null;

    final samplesPerFrame = version == _Mp3MpegVersion.v1 ? 1152 : 576;
    final frameLength = version == _Mp3MpegVersion.v1
        ? ((144000 * bitrateKbps) ~/ sampleRate) + paddingBit
        : ((72000 * bitrateKbps) ~/ sampleRate) + paddingBit;
    if (frameLength <= 0 || offset + frameLength > bytes.lengthInBytes) {
      return null;
    }

    return _Mp3FrameHeader(
      sampleRate: sampleRate,
      bitrateKbps: bitrateKbps,
      channelCount: channelMode == 0x03 ? 1 : 2,
      frameLength: frameLength,
      samplesPerFrame: samplesPerFrame,
    );
  }

  static int? _mp3BitrateKbps(_Mp3MpegVersion version, int bitrateIndex) {
    const mpeg1Layer3 = <int>[
      0,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      160,
      192,
      224,
      256,
      320,
      0,
    ];
    const mpeg2Layer3 = <int>[
      0,
      8,
      16,
      24,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      144,
      160,
      0,
    ];
    final table = version == _Mp3MpegVersion.v1 ? mpeg1Layer3 : mpeg2Layer3;
    final value = table[bitrateIndex];
    return value > 0 ? value : null;
  }

  static int? _mp3SampleRate(_Mp3MpegVersion version, int sampleRateIndex) {
    const v1 = <int>[44100, 48000, 32000];
    const v2 = <int>[22050, 24000, 16000];
    const v25 = <int>[11025, 12000, 8000];
    final table = switch (version) {
      _Mp3MpegVersion.v1 => v1,
      _Mp3MpegVersion.v2 => v2,
      _Mp3MpegVersion.v25 => v25,
    };
    return table[sampleRateIndex];
  }
}

enum _Mp3MpegVersion { v1, v2, v25 }

class _Mp3FrameHeader {
  final int sampleRate;
  final int bitrateKbps;
  final int channelCount;
  final int frameLength;
  final int samplesPerFrame;

  const _Mp3FrameHeader({
    required this.sampleRate,
    required this.bitrateKbps,
    required this.channelCount,
    required this.frameLength,
    required this.samplesPerFrame,
  });
}

double _decodeWavSample(
  ByteData data,
  int offset,
  int formatCode,
  int bitsPerSample,
) {
  if (formatCode == 3) {
    switch (bitsPerSample) {
      case 32:
        return data.getFloat32(offset, Endian.little);
      case 64:
        return data.getFloat64(offset, Endian.little);
      default:
        throw FormatException(
          'Unsupported floating-point WAV bit depth: $bitsPerSample',
        );
    }
  }

  switch (bitsPerSample) {
    case 8:
      return (data.getUint8(offset) - 128) / 128.0;
    case 16:
      return data.getInt16(offset, Endian.little) / 32768.0;
    case 24:
      var sample = data.getUint8(offset) |
          (data.getUint8(offset + 1) << 8) |
          (data.getUint8(offset + 2) << 16);
      if ((sample & 0x800000) != 0) {
        sample -= 0x1000000;
      }
      return sample / 8388608.0;
    case 32:
      return data.getInt32(offset, Endian.little) / 2147483648.0;
    default:
      throw FormatException('Unsupported PCM WAV bit depth: $bitsPerSample');
  }
}
