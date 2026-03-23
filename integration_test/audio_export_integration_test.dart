import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/helpers/audio_file_analysis.dart';
import 'package:mixroom/helpers/audio_test_signal.dart';

import 'audio_export_test_support.dart';

class _WavVariantCase {
  final String name;
  final int sampleRate;
  final int wavBitDepth;
  final bool wavDithering;
  final String channelMode;
  final AudioTestSignalSpec expectedSpec;
  final String expectedCodec;

  const _WavVariantCase({
    required this.name,
    required this.sampleRate,
    required this.wavBitDepth,
    required this.wavDithering,
    required this.channelMode,
    required this.expectedSpec,
    required this.expectedCodec,
  });
}

class _Mp3VariantCase {
  final String name;
  final int sampleRate;
  final String channelMode;
  final int mp3BitrateKbps;
  final String mp3Mode;
  final int mp3VbrQuality;
  final Mp3BitrateMode expectedMode;
  final int? minBitrate;
  final int? maxBitrate;

  const _Mp3VariantCase({
    required this.name,
    required this.sampleRate,
    required this.channelMode,
    required this.mp3BitrateKbps,
    required this.mp3Mode,
    required this.mp3VbrQuality,
    required this.expectedMode,
    this.minBitrate,
    this.maxBitrate,
  });
}

List<double> _placeSamples(
  List<double> source, {
  required int totalFrames,
  int offsetFrames = 0,
  double gain = 1.0,
}) {
  final output = List<double>.filled(totalFrames, 0.0, growable: false);
  for (var i = 0; i < source.length; i++) {
    final outIndex = i + offsetFrames;
    if (outIndex < 0 || outIndex >= totalFrames) break;
    output[outIndex] += source[i] * gain;
  }
  return output;
}

AudioSignalMetrics _measureWindow(
  List<double> samples, {
  required int sampleRate,
  required int startMs,
  required int endMs,
}) {
  final start = math.max(0, (sampleRate * startMs / 1000).round());
  final end = math.min(samples.length, (sampleRate * endMs / 1000).round());
  if (end <= start) {
    return const AudioSignalMetrics(peakAbsolute: 0.0, rms: 0.0, mean: 0.0);
  }
  return AudioFileAnalysis.measureSamples(samples.sublist(start, end));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('JUCE raw mix export stays numerically close to the source clip',
      (tester) async {
    Directory? workingDirectory;
    addTearDown(() async {
      if (workingDirectory != null) {
        await AudioExportIntegrationHarness.deleteDirectoryIfPresent(
          workingDirectory!,
        );
      }
      await AudioExportIntegrationHarness.resetEngine();
    });

    await tester.runAsync(() async {
      const spec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 2,
        duration: Duration(milliseconds: 700),
        frequencyHz: 997.0,
        amplitude: 0.2,
      );

      workingDirectory =
          await AudioExportIntegrationHarness.createWorkingDirectory(
        'audio_export_raw_mix',
      );
      final sourceFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'source',
        spec,
      );

      final rawMixPath =
          await AudioExportIntegrationHarness.renderSingleClipMix(
        inputPath: sourceFile.path,
        workingDirectory: workingDirectory!,
        sampleRate: 48000,
      );

      final sourceAnalysis =
          await AudioFileAnalysis.parseWavFile(sourceFile.path);
      final mixAnalysis = await AudioFileAnalysis.parseWavFile(rawMixPath);
      final comparison = AudioFileAnalysis.compareSamples(
        sourceAnalysis.decodeNormalizedMono(),
        mixAnalysis.decodeNormalizedMono(),
        maxOffsetSamples: 32,
      );

      expect(mixAnalysis.sampleRate, 48000);
      expect(mixAnalysis.channels, 2);
      expect(mixAnalysis.bitsPerSample, 16);
      expect(
        mixAnalysis.frameCount,
        inInclusiveRange(
          sourceAnalysis.frameCount - 32,
          sourceAnalysis.frameCount + 32,
        ),
      );
      expect(comparison.rmsError, lessThan(0.0002));
      expect(comparison.maxAbsoluteError, lessThan(0.0025));
      expect(comparison.correlation, greaterThan(0.9999));
    });
  });

  testWidgets('JUCE export preserves stereo channels for phase-offset sources',
      (tester) async {
    Directory? workingDirectory;
    addTearDown(() async {
      if (workingDirectory != null) {
        await AudioExportIntegrationHarness.deleteDirectoryIfPresent(
          workingDirectory!,
        );
      }
      await AudioExportIntegrationHarness.resetEngine();
    });

    await tester.runAsync(() async {
      final spec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 2,
        duration: const Duration(milliseconds: 850),
        frequencyHz: 997.0,
        amplitude: 0.18,
        channelPhaseOffsetRadians: math.pi / 2,
      );

      workingDirectory =
          await AudioExportIntegrationHarness.createWorkingDirectory(
        'audio_export_stereo_preservation',
      );
      final sourceFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'stereo_source',
        spec,
      );

      await AudioExportIntegrationHarness.configureMix(
        rows: const [
          ExportTestRowConfig(rowIndex: 0, name: 'Stereo Track'),
        ],
        clips: [
          ExportTestClipConfig(
            clipIndex: 0,
            rowIndex: 0,
            inputPath: sourceFile.path,
          ),
        ],
      );
      final outputPath = await AudioExportIntegrationHarness.exportCurrentMix(
        workingDirectory: workingDirectory!,
        fileName: 'stereo_mix.wav',
        format: 'wav',
        sampleRate: 48000,
        wavBitDepth: 16,
        wavDithering: false,
      );

      final outputAnalysis = await AudioFileAnalysis.parseWavFile(outputPath);
      final actualChannels = outputAnalysis.decodeNormalizedChannels();
      final expectedChannels = AudioTestSignal.generateChannelSamples(spec);
      expect(actualChannels.length, 2);

      final leftComparison = AudioFileAnalysis.compareSamples(
        expectedChannels[0],
        actualChannels[0],
        maxOffsetSamples: 32,
      );
      final rightComparison = AudioFileAnalysis.compareSamples(
        expectedChannels[1],
        actualChannels[1],
        maxOffsetSamples: 32,
      );

      expect(leftComparison.rmsError, lessThan(0.0002));
      expect(leftComparison.maxAbsoluteError, lessThan(0.0025));
      expect(leftComparison.correlation, greaterThan(0.9999));
      expect(rightComparison.rmsError, lessThan(0.0002));
      expect(rightComparison.maxAbsoluteError, lessThan(0.0025));
      expect(rightComparison.correlation, greaterThan(0.9999));
    });
  });

  testWidgets(
      'native direct WAV export and raw-plus-FFmpeg export stay numerically aligned',
      (tester) async {
    Directory? workingDirectory;
    addTearDown(() async {
      if (workingDirectory != null) {
        await AudioExportIntegrationHarness.deleteDirectoryIfPresent(
          workingDirectory!,
        );
      }
      await AudioExportIntegrationHarness.resetEngine();
    });

    await tester.runAsync(() async {
      final spec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 2,
        duration: const Duration(milliseconds: 900),
        frequencyHz: 613.0,
        amplitude: 0.2,
        channelPhaseOffsetRadians: math.pi / 3,
      );

      workingDirectory =
          await AudioExportIntegrationHarness.createWorkingDirectory(
        'audio_export_branch_parity',
      );
      final sourceFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'source',
        spec,
      );

      await AudioExportIntegrationHarness.configureMix(
        rows: const [
          ExportTestRowConfig(rowIndex: 0, name: 'Parity Track'),
        ],
        clips: [
          ExportTestClipConfig(
            clipIndex: 0,
            rowIndex: 0,
            inputPath: sourceFile.path,
          ),
        ],
      );

      final directPath = await AudioExportIntegrationHarness.exportCurrentMix(
        workingDirectory: workingDirectory!,
        fileName: 'direct.wav',
        format: 'wav',
        sampleRate: 48000,
        wavBitDepth: 16,
        wavDithering: false,
      );
      final rawPath = await AudioExportIntegrationHarness.exportCurrentMix(
        workingDirectory: workingDirectory!,
        fileName: 'raw_32.wav',
        format: 'wav',
        sampleRate: 48000,
        wavBitDepth: 32,
        wavDithering: false,
      );
      final convertedPath = await AudioExportIntegrationHarness.exportWithPlan(
        inputPath: rawPath,
        outputPath: '${workingDirectory!.path}/converted.wav',
        format: 'wav',
        sampleRate: 48000,
        wavBitDepth: 16,
        wavDithering: false,
        mp3BitrateKbps: 192,
        mp3Mode: 'cbr',
        mp3VbrQuality: 2,
        channelMode: 'stereo',
        normalize: false,
        normalizeTargetDb: -1.0,
        resampleQuality: 'best',
      );

      final directAnalysis = await AudioFileAnalysis.parseWavFile(directPath);
      final convertedAnalysis =
          await AudioFileAnalysis.parseWavFile(convertedPath);
      final directChannels = directAnalysis.decodeNormalizedChannels();
      final convertedChannels = convertedAnalysis.decodeNormalizedChannels();

      expect(directAnalysis.sampleRate, 48000);
      expect(convertedAnalysis.sampleRate, 48000);
      expect(directAnalysis.bitsPerSample, 16);
      expect(convertedAnalysis.bitsPerSample, 16);
      expect(directChannels.length, 2);
      expect(convertedChannels.length, 2);

      for (var channel = 0; channel < 2; channel++) {
        final comparison = AudioFileAnalysis.compareSamples(
          directChannels[channel],
          convertedChannels[channel],
          maxOffsetSamples: 32,
        );
        expect(comparison.rmsError, lessThan(0.0004));
        expect(comparison.maxAbsoluteError, lessThan(0.004));
        expect(comparison.correlation, greaterThan(0.9998));
      }
    });
  });

  testWidgets(
      'JUCE export respects row pan, clip offsets, and overlap across rows',
      (tester) async {
    Directory? workingDirectory;
    addTearDown(() async {
      if (workingDirectory != null) {
        await AudioExportIntegrationHarness.deleteDirectoryIfPresent(
          workingDirectory!,
        );
      }
      await AudioExportIntegrationHarness.resetEngine();
    });

    await tester.runAsync(() async {
      const leftSpec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 1,
        duration: Duration(milliseconds: 900),
        frequencyHz: 431.0,
        amplitude: 0.16,
      );
      const rightSpec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 1,
        duration: Duration(milliseconds: 600),
        frequencyHz: 883.0,
        amplitude: 0.12,
      );

      workingDirectory =
          await AudioExportIntegrationHarness.createWorkingDirectory(
        'audio_export_pan_offset_overlap',
      );
      final leftFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'left_source',
        leftSpec,
      );
      final rightFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'right_source',
        rightSpec,
      );

      await AudioExportIntegrationHarness.configureMix(
        rows: const [
          ExportTestRowConfig(
            rowIndex: 0,
            name: 'Left Row',
            panMinus1To1: 0.0,
          ),
          ExportTestRowConfig(
            rowIndex: 1,
            name: 'Right Row',
            panMinus1To1: 1.0,
          ),
        ],
        clips: [
          ExportTestClipConfig(
            clipIndex: 0,
            rowIndex: 0,
            inputPath: leftFile.path,
          ),
          ExportTestClipConfig(
            clipIndex: 1,
            rowIndex: 1,
            inputPath: rightFile.path,
            startSec: 0.18,
          ),
        ],
      );
      final outputPath = await AudioExportIntegrationHarness.exportCurrentMix(
        workingDirectory: workingDirectory!,
        fileName: 'pan_offset_mix.wav',
        format: 'wav',
        sampleRate: 48000,
        wavBitDepth: 16,
        wavDithering: false,
      );

      final outputAnalysis = await AudioFileAnalysis.parseWavFile(outputPath);
      final actualChannels = outputAnalysis.decodeNormalizedChannels();
      expect(actualChannels.length, 2);

      final totalFrames = outputAnalysis.frameCount;
      final expectedLeft = _placeSamples(
        AudioTestSignal.generateMonoSamples(leftSpec),
        totalFrames: totalFrames,
      );
      final expectedRight = _placeSamples(
        AudioTestSignal.generateMonoSamples(rightSpec),
        totalFrames: totalFrames,
        offsetFrames: (rightSpec.sampleRate * 0.18).round(),
      );

      final leftComparison = AudioFileAnalysis.compareSamples(
        expectedLeft,
        actualChannels[0],
        maxOffsetSamples: 64,
      );
      final rightComparison = AudioFileAnalysis.compareSamples(
        expectedRight,
        actualChannels[1],
        maxOffsetSamples: 64,
      );

      expect(leftComparison.rmsError, lessThan(0.002));
      expect(leftComparison.maxAbsoluteError, lessThan(0.02));
      expect(leftComparison.correlation, greaterThan(0.998));
      expect(rightComparison.rmsError, lessThan(0.002));
      expect(rightComparison.maxAbsoluteError, lessThan(0.02));
      expect(rightComparison.correlation, greaterThan(0.998));
    });
  });

  testWidgets('track volume automation changes the exported envelope',
      (tester) async {
    Directory? workingDirectory;
    addTearDown(() async {
      if (workingDirectory != null) {
        await AudioExportIntegrationHarness.deleteDirectoryIfPresent(
          workingDirectory!,
        );
      }
      await AudioExportIntegrationHarness.resetEngine();
    });

    await tester.runAsync(() async {
      const spec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 2,
        duration: Duration(milliseconds: 800),
        frequencyHz: 997.0,
        amplitude: 0.18,
      );

      workingDirectory =
          await AudioExportIntegrationHarness.createWorkingDirectory(
        'audio_export_track_automation',
      );
      final sourceFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'source',
        spec,
      );

      await AudioExportIntegrationHarness.configureMix(
        rows: const [
          ExportTestRowConfig(
            rowIndex: 0,
            name: 'Automated Track',
            trackAutomationPoints: [
              {'x': 0.0, 'volume': 1.0},
              {'x': 390.0, 'volume': 1.0},
              {'x': 410.0, 'volume': 0.0},
              {'x': 800.0, 'volume': 0.0},
            ],
          ),
        ],
        clips: [
          ExportTestClipConfig(
            clipIndex: 0,
            rowIndex: 0,
            inputPath: sourceFile.path,
          ),
        ],
      );
      final outputPath = await AudioExportIntegrationHarness.exportCurrentMix(
        workingDirectory: workingDirectory!,
        fileName: 'track_automation.wav',
        format: 'wav',
        sampleRate: 48000,
        wavBitDepth: 16,
        wavDithering: false,
      );

      final outputAnalysis = await AudioFileAnalysis.parseWavFile(outputPath);
      final outputMono = outputAnalysis.decodeNormalizedMono();
      final earlyMetrics = _measureWindow(
        outputMono,
        sampleRate: 48000,
        startMs: 80,
        endMs: 300,
      );
      final lateMetrics = _measureWindow(
        outputMono,
        sampleRate: 48000,
        startMs: 560,
        endMs: 760,
      );

      expect(earlyMetrics.rms, greaterThan(0.08));
      expect(lateMetrics.peakAbsolute, lessThan(0.02));
      expect(earlyMetrics.rms, greaterThan(lateMetrics.rms * 20.0));
    });
  });

  testWidgets(
      'WAV export applies sample rate, mono downmix, and bit depth settings',
      (tester) async {
    Directory? workingDirectory;
    addTearDown(() async {
      if (workingDirectory != null) {
        await AudioExportIntegrationHarness.deleteDirectoryIfPresent(
          workingDirectory!,
        );
      }
      await AudioExportIntegrationHarness.resetEngine();
    });

    await tester.runAsync(() async {
      const sourceSpec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 2,
        duration: Duration(milliseconds: 700),
        frequencyHz: 997.0,
        amplitude: 0.2,
      );
      const expectedSpec = AudioTestSignalSpec(
        sampleRate: 44100,
        channels: 1,
        duration: Duration(milliseconds: 700),
        frequencyHz: 997.0,
        amplitude: 0.2,
      );

      workingDirectory =
          await AudioExportIntegrationHarness.createWorkingDirectory(
        'audio_export_wav_settings',
      );
      final sourceFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'source',
        sourceSpec,
      );
      final outputPath = await AudioExportIntegrationHarness.exportWithPlan(
        inputPath: sourceFile.path,
        outputPath: '${workingDirectory!.path}/out.wav',
        format: 'wav',
        sampleRate: 44100,
        wavBitDepth: 24,
        wavDithering: false,
        mp3BitrateKbps: 192,
        mp3Mode: 'cbr',
        mp3VbrQuality: 2,
        channelMode: 'mono',
        normalize: false,
        normalizeTargetDb: -1.0,
        resampleQuality: 'best',
      );

      final outputAnalysis = await AudioFileAnalysis.parseWavFile(outputPath);
      final probed =
          await AudioExportIntegrationHarness.probeAudioFile(outputPath);
      final comparison = AudioFileAnalysis.compareSamples(
        AudioTestSignal.generateMonoSamples(expectedSpec),
        outputAnalysis.decodeNormalizedMono(),
        maxOffsetSamples: 16,
      );

      expect(outputAnalysis.sampleRate, 44100);
      expect(outputAnalysis.channels, 1);
      expect(outputAnalysis.bitsPerSample, 24);
      expect(probed.codecName, 'pcm_s24le');
      expect(probed.sampleRate, 44100);
      expect(probed.channelCount, 1);
      expect(comparison.rmsError, lessThan(0.002));
      expect(comparison.maxAbsoluteError, lessThan(0.01));
      expect(comparison.correlation, greaterThan(0.999));
    });
  });

  testWidgets('WAV export variants across bit depths stay numerically accurate',
      (tester) async {
    Directory? workingDirectory;
    addTearDown(() async {
      if (workingDirectory != null) {
        await AudioExportIntegrationHarness.deleteDirectoryIfPresent(
          workingDirectory!,
        );
      }
    });

    await tester.runAsync(() async {
      const sourceSpec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 2,
        duration: Duration(milliseconds: 900),
        frequencyHz: 997.0,
        amplitude: 0.2,
        channelPhaseOffsetRadians: math.pi / 4,
      );
      const cases = <_WavVariantCase>[
        _WavVariantCase(
          name: 'wav16_stereo_48k',
          sampleRate: 48000,
          wavBitDepth: 16,
          wavDithering: true,
          channelMode: 'stereo',
          expectedSpec: AudioTestSignalSpec(
            sampleRate: 48000,
            channels: 2,
            duration: Duration(milliseconds: 900),
            frequencyHz: 997.0,
            amplitude: 0.2,
            channelPhaseOffsetRadians: math.pi / 4,
          ),
          expectedCodec: 'pcm_s16le',
        ),
        _WavVariantCase(
          name: 'wav24_mono_44k1',
          sampleRate: 44100,
          wavBitDepth: 24,
          wavDithering: false,
          channelMode: 'mono',
          expectedSpec: AudioTestSignalSpec(
            sampleRate: 44100,
            channels: 1,
            duration: Duration(milliseconds: 900),
            frequencyHz: 997.0,
            amplitude: 0.2,
          ),
          expectedCodec: 'pcm_s24le',
        ),
        _WavVariantCase(
          name: 'wav32_stereo_96k',
          sampleRate: 96000,
          wavBitDepth: 32,
          wavDithering: false,
          channelMode: 'stereo',
          expectedSpec: AudioTestSignalSpec(
            sampleRate: 96000,
            channels: 2,
            duration: Duration(milliseconds: 900),
            frequencyHz: 997.0,
            amplitude: 0.2,
            channelPhaseOffsetRadians: math.pi / 4,
          ),
          expectedCodec: 'pcm_f32le',
        ),
      ];

      workingDirectory =
          await AudioExportIntegrationHarness.createWorkingDirectory(
        'audio_export_wav_matrix',
      );
      final sourceFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'source',
        sourceSpec,
      );

      for (final testCase in cases) {
        final outputPath = await AudioExportIntegrationHarness.exportWithPlan(
          inputPath: sourceFile.path,
          outputPath: '${workingDirectory!.path}/${testCase.name}.wav',
          format: 'wav',
          sampleRate: testCase.sampleRate,
          wavBitDepth: testCase.wavBitDepth,
          wavDithering: testCase.wavDithering,
          mp3BitrateKbps: 192,
          mp3Mode: 'cbr',
          mp3VbrQuality: 2,
          channelMode: testCase.channelMode,
          normalize: false,
          normalizeTargetDb: -1.0,
          resampleQuality: 'best',
        );

        final outputAnalysis = await AudioFileAnalysis.parseWavFile(outputPath);
        final probed =
            await AudioExportIntegrationHarness.probeAudioFile(outputPath);
        final comparison = AudioFileAnalysis.compareSamples(
          AudioTestSignal.generateMonoSamples(testCase.expectedSpec),
          outputAnalysis.decodeNormalizedMono(),
          maxOffsetSamples: 128,
        );

        expect(outputAnalysis.sampleRate, testCase.sampleRate);
        expect(
          outputAnalysis.channels,
          testCase.channelMode == 'mono' ? 1 : 2,
        );
        expect(outputAnalysis.bitsPerSample, testCase.wavBitDepth);
        expect(probed.codecName, testCase.expectedCodec);
        expect(
          comparison.rmsError,
          lessThan(0.003),
          reason: testCase.name,
        );
        expect(
          comparison.maxAbsoluteError,
          lessThan(0.02),
          reason: testCase.name,
        );
        expect(
          comparison.correlation,
          greaterThan(0.998),
          reason: testCase.name,
        );
      }
    });
  });

  testWidgets('MP3 CBR export yields stable metadata and decodes cleanly',
      (tester) async {
    Directory? workingDirectory;
    addTearDown(() async {
      if (workingDirectory != null) {
        await AudioExportIntegrationHarness.deleteDirectoryIfPresent(
          workingDirectory!,
        );
      }
      await AudioExportIntegrationHarness.resetEngine();
    });

    await tester.runAsync(() async {
      const spec = AudioTestSignalSpec(
        sampleRate: 44100,
        channels: 2,
        duration: Duration(milliseconds: 900),
        frequencyHz: 997.0,
        amplitude: 0.18,
      );

      workingDirectory =
          await AudioExportIntegrationHarness.createWorkingDirectory(
        'audio_export_mp3_cbr',
      );
      final sourceFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'source',
        spec,
      );
      final outputPath = await AudioExportIntegrationHarness.exportWithPlan(
        inputPath: sourceFile.path,
        outputPath: '${workingDirectory!.path}/out_cbr.mp3',
        format: 'mp3',
        sampleRate: 44100,
        wavBitDepth: 16,
        wavDithering: true,
        mp3BitrateKbps: 128,
        mp3Mode: 'cbr',
        mp3VbrQuality: 2,
        channelMode: 'stereo',
        normalize: false,
        normalizeTargetDb: -1.0,
        resampleQuality: 'best',
      );

      final mp3Analysis = await AudioFileAnalysis.parseMp3File(outputPath);
      final probed =
          await AudioExportIntegrationHarness.probeAudioFile(outputPath);
      final decodedPath =
          await AudioExportIntegrationHarness.decodeToAnalysisWav(
        inputPath: outputPath,
        workingDirectory: workingDirectory!,
        fileStem: 'decoded_cbr',
        sampleRate: 44100,
        channels: 2,
      );
      final decodedWav = await AudioFileAnalysis.parseWavFile(decodedPath);
      final comparison = AudioFileAnalysis.compareSamples(
        AudioTestSignal.generateMonoSamples(spec),
        decodedWav.decodeNormalizedMono(),
        maxOffsetSamples: 4096,
      );

      expect(mp3Analysis.bitrateMode, Mp3BitrateMode.cbr);
      expect(mp3Analysis.nominalBitrateKbps, 128);
      expect(mp3Analysis.sampleRate, 44100);
      expect(mp3Analysis.channelCount, 2);
      expect(probed.codecName, 'mp3');
      expect(probed.sampleRate, 44100);
      expect(probed.channelCount, 2);
      expect(probed.bitRate ?? 0, inInclusiveRange(120000, 136000));
      expect(comparison.rmsError, lessThan(0.03));
      expect(comparison.maxAbsoluteError, lessThan(0.2));
      expect(comparison.correlation, greaterThan(0.98));
    });
  });

  testWidgets('MP3 export variants across mode and bitrate decode cleanly',
      (tester) async {
    Directory? workingDirectory;
    addTearDown(() async {
      if (workingDirectory != null) {
        await AudioExportIntegrationHarness.deleteDirectoryIfPresent(
          workingDirectory!,
        );
      }
    });

    await tester.runAsync(() async {
      const sourceSpec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 2,
        duration: Duration(milliseconds: 900),
        frequencyHz: 613.0,
        amplitude: 0.17,
      );
      const cases = <_Mp3VariantCase>[
        _Mp3VariantCase(
          name: 'mp3_cbr_128_stereo_44k1',
          sampleRate: 44100,
          channelMode: 'stereo',
          mp3BitrateKbps: 128,
          mp3Mode: 'cbr',
          mp3VbrQuality: 2,
          expectedMode: Mp3BitrateMode.cbr,
          minBitrate: 120000,
          maxBitrate: 136000,
        ),
        _Mp3VariantCase(
          name: 'mp3_cbr_320_mono_48k',
          sampleRate: 48000,
          channelMode: 'mono',
          mp3BitrateKbps: 320,
          mp3Mode: 'cbr',
          mp3VbrQuality: 2,
          expectedMode: Mp3BitrateMode.cbr,
          minBitrate: 300000,
          maxBitrate: 332000,
        ),
        _Mp3VariantCase(
          name: 'mp3_vbr_q0_stereo_44k1',
          sampleRate: 44100,
          channelMode: 'stereo',
          mp3BitrateKbps: 192,
          mp3Mode: 'vbr',
          mp3VbrQuality: 0,
          expectedMode: Mp3BitrateMode.vbr,
        ),
        _Mp3VariantCase(
          name: 'mp3_vbr_q4_mono_48k',
          sampleRate: 48000,
          channelMode: 'mono',
          mp3BitrateKbps: 192,
          mp3Mode: 'vbr',
          mp3VbrQuality: 4,
          expectedMode: Mp3BitrateMode.vbr,
        ),
      ];

      workingDirectory =
          await AudioExportIntegrationHarness.createWorkingDirectory(
        'audio_export_mp3_matrix',
      );
      final sourceFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'source',
        sourceSpec,
      );

      for (final testCase in cases) {
        final outputPath = await AudioExportIntegrationHarness.exportWithPlan(
          inputPath: sourceFile.path,
          outputPath: '${workingDirectory!.path}/${testCase.name}.mp3',
          format: 'mp3',
          sampleRate: testCase.sampleRate,
          wavBitDepth: 16,
          wavDithering: true,
          mp3BitrateKbps: testCase.mp3BitrateKbps,
          mp3Mode: testCase.mp3Mode,
          mp3VbrQuality: testCase.mp3VbrQuality,
          channelMode: testCase.channelMode,
          normalize: false,
          normalizeTargetDb: -1.0,
          resampleQuality: 'best',
        );

        final mp3Analysis = await AudioFileAnalysis.parseMp3File(outputPath);
        final probed =
            await AudioExportIntegrationHarness.probeAudioFile(outputPath);
        final decodedPath =
            await AudioExportIntegrationHarness.decodeToAnalysisWav(
          inputPath: outputPath,
          workingDirectory: workingDirectory!,
          fileStem: '${testCase.name}_decoded',
          sampleRate: testCase.sampleRate,
          channels: testCase.channelMode == 'mono' ? 1 : 2,
        );
        final decodedWav = await AudioFileAnalysis.parseWavFile(decodedPath);
        final expectedMono = AudioTestSignal.generateMonoSamples(
          AudioTestSignalSpec(
            sampleRate: testCase.sampleRate,
            channels: testCase.channelMode == 'mono' ? 1 : 2,
            duration: const Duration(milliseconds: 900),
            frequencyHz: 613.0,
            amplitude: 0.17,
          ),
        );
        final comparison = AudioFileAnalysis.compareSamples(
          expectedMono,
          decodedWav.decodeNormalizedMono(),
          maxOffsetSamples: 4096,
        );

        expect(mp3Analysis.bitrateMode, testCase.expectedMode);
        expect(mp3Analysis.sampleRate, testCase.sampleRate);
        expect(
          mp3Analysis.channelCount,
          testCase.channelMode == 'mono' ? 1 : 2,
        );
        expect(probed.codecName, 'mp3');
        expect(probed.sampleRate, testCase.sampleRate);
        expect(
          probed.channelCount,
          testCase.channelMode == 'mono' ? 1 : 2,
        );
        if (testCase.minBitrate != null && testCase.maxBitrate != null) {
          expect(
            probed.bitRate ?? 0,
            inInclusiveRange(testCase.minBitrate!, testCase.maxBitrate!),
          );
        }
        expect(comparison.rmsError, lessThan(0.035));
        expect(comparison.maxAbsoluteError, lessThan(0.22));
        expect(comparison.correlation, greaterThan(0.975));
      }
    });
  });

  testWidgets('MP3 VBR export is detected as VBR and decodes cleanly',
      (tester) async {
    Directory? workingDirectory;
    addTearDown(() async {
      if (workingDirectory != null) {
        await AudioExportIntegrationHarness.deleteDirectoryIfPresent(
          workingDirectory!,
        );
      }
      await AudioExportIntegrationHarness.resetEngine();
    });

    await tester.runAsync(() async {
      const spec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 2,
        duration: Duration(milliseconds: 900),
        frequencyHz: 997.0,
        amplitude: 0.18,
      );

      workingDirectory =
          await AudioExportIntegrationHarness.createWorkingDirectory(
        'audio_export_mp3_vbr',
      );
      final sourceFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'source',
        spec,
      );
      final outputPath = await AudioExportIntegrationHarness.exportWithPlan(
        inputPath: sourceFile.path,
        outputPath: '${workingDirectory!.path}/out_vbr.mp3',
        format: 'mp3',
        sampleRate: 48000,
        wavBitDepth: 16,
        wavDithering: true,
        mp3BitrateKbps: 192,
        mp3Mode: 'vbr',
        mp3VbrQuality: 2,
        channelMode: 'mono',
        normalize: false,
        normalizeTargetDb: -1.0,
        resampleQuality: 'best',
      );

      final mp3Analysis = await AudioFileAnalysis.parseMp3File(outputPath);
      final probed =
          await AudioExportIntegrationHarness.probeAudioFile(outputPath);
      final decodedPath =
          await AudioExportIntegrationHarness.decodeToAnalysisWav(
        inputPath: outputPath,
        workingDirectory: workingDirectory!,
        fileStem: 'decoded_vbr',
        sampleRate: 48000,
        channels: 1,
      );
      final decodedWav = await AudioFileAnalysis.parseWavFile(decodedPath);
      final expectedMono = AudioTestSignal.generateMonoSamples(
        const AudioTestSignalSpec(
          sampleRate: 48000,
          channels: 1,
          duration: Duration(milliseconds: 900),
          frequencyHz: 997.0,
          amplitude: 0.18,
        ),
      );
      final comparison = AudioFileAnalysis.compareSamples(
        expectedMono,
        decodedWav.decodeNormalizedMono(),
        maxOffsetSamples: 4096,
      );

      expect(mp3Analysis.bitrateMode, Mp3BitrateMode.vbr);
      expect(mp3Analysis.sampleRate, 48000);
      expect(mp3Analysis.channelCount, 1);
      expect(probed.codecName, 'mp3');
      expect(probed.sampleRate, 48000);
      expect(probed.channelCount, 1);
      expect(comparison.rmsError, lessThan(0.03));
      expect(comparison.maxAbsoluteError, lessThan(0.2));
      expect(comparison.correlation, greaterThan(0.98));
    });
  });

  testWidgets('normalization raises level without exceeding the ceiling',
      (tester) async {
    Directory? workingDirectory;
    addTearDown(() async {
      if (workingDirectory != null) {
        await AudioExportIntegrationHarness.deleteDirectoryIfPresent(
          workingDirectory!,
        );
      }
      await AudioExportIntegrationHarness.resetEngine();
    });

    await tester.runAsync(() async {
      const spec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 2,
        duration: Duration(milliseconds: 700),
        frequencyHz: 997.0,
        amplitude: 0.04,
      );

      workingDirectory =
          await AudioExportIntegrationHarness.createWorkingDirectory(
        'audio_export_normalize',
      );
      final sourceFile = await AudioExportIntegrationHarness.writeFixtureWav(
        workingDirectory!,
        'source',
        spec,
      );

      final sourceMetrics = AudioFileAnalysis.measureSamples(
        AudioTestSignal.generateMonoSamples(spec),
      );

      final outputPath = await AudioExportIntegrationHarness.exportWithPlan(
        inputPath: sourceFile.path,
        outputPath: '${workingDirectory!.path}/normalized.wav',
        format: 'wav',
        sampleRate: 48000,
        wavBitDepth: 16,
        wavDithering: true,
        mp3BitrateKbps: 192,
        mp3Mode: 'cbr',
        mp3VbrQuality: 2,
        channelMode: 'stereo',
        normalize: true,
        normalizeTargetDb: -1.0,
        resampleQuality: 'best',
      );

      final outputAnalysis = await AudioFileAnalysis.parseWavFile(outputPath);
      final outputMetrics = AudioFileAnalysis.measureSamples(
        outputAnalysis.decodeNormalizedMono(),
      );

      expect(outputMetrics.peakDbfs, lessThanOrEqualTo(-0.5));
      expect(outputMetrics.peakDbfs, greaterThan(sourceMetrics.peakDbfs + 6.0));
      expect(outputMetrics.rmsDbfs, greaterThan(sourceMetrics.rmsDbfs + 6.0));
    });
  });
}
