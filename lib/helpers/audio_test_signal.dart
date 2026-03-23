import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class AudioTestSignalSpec {
  final int sampleRate;
  final int channels;
  final Duration duration;
  final double frequencyHz;
  final double amplitude;
  final double channelPhaseOffsetRadians;

  const AudioTestSignalSpec({
    required this.sampleRate,
    required this.channels,
    required this.duration,
    required this.frequencyHz,
    this.amplitude = 0.25,
    this.channelPhaseOffsetRadians = 0.0,
  })  : assert(sampleRate > 0),
        assert(channels > 0),
        assert(amplitude >= 0.0),
        assert(amplitude <= 1.0);

  int get frameCount =>
      math.max(1, (sampleRate * duration.inMicroseconds / 1000000).round());
}

class AudioTestSignal {
  const AudioTestSignal._();

  static List<List<double>> generateChannelSamples(AudioTestSignalSpec spec) {
    final channels = List<List<double>>.generate(
      spec.channels,
      (_) => List<double>.filled(spec.frameCount, 0.0, growable: false),
      growable: false,
    );
    final twoPiF = 2.0 * math.pi * spec.frequencyHz;

    for (var channel = 0; channel < spec.channels; channel++) {
      final phaseOffset = channel * spec.channelPhaseOffsetRadians;
      final samples = channels[channel];
      for (var i = 0; i < spec.frameCount; i++) {
        final t = i / spec.sampleRate;
        samples[i] = spec.amplitude * math.sin(twoPiF * t + phaseOffset);
      }
    }

    return channels;
  }

  static List<double> generateMonoSamples(AudioTestSignalSpec spec) {
    final channels = generateChannelSamples(spec);
    if (channels.isEmpty) return const <double>[];
    if (channels.length == 1) return List<double>.from(channels.first);

    return List<double>.generate(
      spec.frameCount,
      (index) {
        var sum = 0.0;
        for (final channel in channels) {
          sum += channel[index];
        }
        return sum / channels.length;
      },
      growable: false,
    );
  }

  static List<double> generateInterleavedSamples(AudioTestSignalSpec spec) {
    final channels = generateChannelSamples(spec);
    final output = List<double>.filled(spec.frameCount * spec.channels, 0.0,
        growable: false);
    var outIndex = 0;
    for (var frame = 0; frame < spec.frameCount; frame++) {
      for (var channel = 0; channel < spec.channels; channel++) {
        output[outIndex++] = channels[channel][frame];
      }
    }
    return output;
  }

  static Uint8List buildPcm16WavBytes(AudioTestSignalSpec spec) {
    const bytesPerSample = 2;
    final frameCount = spec.frameCount;
    final dataLength = frameCount * spec.channels * bytesPerSample;
    final totalLength = 44 + dataLength;
    final bytes = Uint8List(totalLength);
    final data = ByteData.sublistView(bytes);
    final channels = generateChannelSamples(spec);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        data.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, totalLength - 8, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, spec.channels, Endian.little);
    data.setUint32(24, spec.sampleRate, Endian.little);
    data.setUint32(
      28,
      spec.sampleRate * spec.channels * bytesPerSample,
      Endian.little,
    );
    data.setUint16(32, spec.channels * bytesPerSample, Endian.little);
    data.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, dataLength, Endian.little);

    var offset = 44;
    for (var frame = 0; frame < frameCount; frame++) {
      for (var channel = 0; channel < spec.channels; channel++) {
        final sample = channels[channel][frame].clamp(-1.0, 1.0);
        final pcm = (sample * 32767.0).round().clamp(-32768, 32767);
        data.setInt16(offset, pcm, Endian.little);
        offset += 2;
      }
    }

    return bytes;
  }

  static Future<File> writePcm16WavFile(
    File file,
    AudioTestSignalSpec spec,
  ) async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(buildPcm16WavBytes(spec), flush: true);
    return file;
  }
}
