import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/audio_file_analysis.dart';
import 'package:mixroom/helpers/audio_test_signal.dart';

void main() {
  group('AudioFileAnalysis WAV parsing', () {
    test('parses deterministic PCM16 WAV data and compares bit-exactly', () {
      const spec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 2,
        duration: Duration(milliseconds: 250),
        frequencyHz: 997.0,
        amplitude: 0.2,
      );

      final bytes = AudioTestSignal.buildPcm16WavBytes(spec);
      final analysis = AudioFileAnalysis.parseWavBytes(bytes);
      final clone = AudioFileAnalysis.parseWavBytes(Uint8List.fromList(bytes));

      expect(analysis.sampleRate, spec.sampleRate);
      expect(analysis.channels, spec.channels);
      expect(analysis.bitsPerSample, 16);
      expect(analysis.frameCount, spec.frameCount);
      expect(analysis.pcmDataEquals(clone), isTrue);

      final mono = analysis.decodeNormalizedMono();
      final metrics = AudioFileAnalysis.measureSamples(mono);
      expect(metrics.peakAbsolute, greaterThan(0.18));
      expect(metrics.peakAbsolute, lessThan(0.21));
    });
  });

  group('AudioFileAnalysis sample comparison', () {
    test('finds the best alignment offset and reports a near-perfect match',
        () {
      final expected = <double>[0.25, -0.25, 0.75, -0.75, 0.5];
      final actual = <double>[0.0, 0.0, 0.25, -0.25, 0.75, -0.75, 0.5, 0.0];

      final result = AudioFileAnalysis.compareSamples(
        expected,
        actual,
        maxOffsetSamples: 3,
      );

      expect(result.bestOffsetSamples, 2);
      expect(result.comparedSamples, expected.length);
      expect(result.rmsError, lessThan(1e-12));
      expect(result.correlation, greaterThan(0.999999));
    });
  });

  group('AudioFileAnalysis MP3 parsing', () {
    test('detects likely CBR MP3 frame sequences', () {
      final bytes = Uint8List.fromList(<int>[
        ..._buildFakeMp3Frame(
          bitrateKbps: 128,
          sampleRate: 44100,
          vbrTag: 'Info',
        ),
        ..._buildFakeMp3Frame(
          bitrateKbps: 128,
          sampleRate: 44100,
        ),
        ..._buildFakeMp3Frame(
          bitrateKbps: 128,
          sampleRate: 44100,
        ),
      ]);

      final analysis = AudioFileAnalysis.parseMp3Bytes(bytes);

      expect(analysis.sampleRate, 44100);
      expect(analysis.channelCount, 2);
      expect(analysis.frameCount, 3);
      expect(analysis.nominalBitrateKbps, 128);
      expect(analysis.vbrTag, 'Info');
      expect(analysis.bitrateMode, Mp3BitrateMode.cbr);
    });

    test('detects likely VBR MP3 frame sequences', () {
      final bytes = Uint8List.fromList(<int>[
        ..._buildFakeMp3Frame(
          bitrateKbps: 128,
          sampleRate: 44100,
          vbrTag: 'Xing',
        ),
        ..._buildFakeMp3Frame(
          bitrateKbps: 160,
          sampleRate: 44100,
        ),
        ..._buildFakeMp3Frame(
          bitrateKbps: 192,
          sampleRate: 44100,
        ),
      ]);

      final analysis = AudioFileAnalysis.parseMp3Bytes(bytes);

      expect(analysis.sampleRate, 44100);
      expect(analysis.frameCount, 3);
      expect(analysis.observedBitratesKbps, {128, 160, 192});
      expect(analysis.vbrTag, 'Xing');
      expect(analysis.bitrateMode, Mp3BitrateMode.vbr);
    });
  });
}

Uint8List _buildFakeMp3Frame({
  required int bitrateKbps,
  required int sampleRate,
  String? vbrTag,
}) {
  const bitrateTable = <int>[
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
  const sampleRateTable = <int>[44100, 48000, 32000];

  final bitrateIndex = bitrateTable.indexOf(bitrateKbps);
  final sampleRateIndex = sampleRateTable.indexOf(sampleRate);
  expect(bitrateIndex, greaterThan(0));
  expect(sampleRateIndex, greaterThanOrEqualTo(0));

  final frameLength = ((144000 * bitrateKbps) ~/ sampleRate);
  final bytes = Uint8List(frameLength);
  bytes[0] = 0xFF;
  bytes[1] = 0xFB;
  bytes[2] = (bitrateIndex << 4) | (sampleRateIndex << 2);
  bytes[3] = 0x00;

  if (vbrTag != null) {
    final tagOffset = 36;
    for (var i = 0; i < vbrTag.length; i++) {
      bytes[tagOffset + i] = vbrTag.codeUnitAt(i);
    }
  }

  return bytes;
}
