import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/audio_export_plan.dart';
import 'package:mixroom/helpers/audio_file_analysis.dart';
import 'package:mixroom/helpers/audio_test_signal.dart';
import 'package:path/path.dart' as p;

final List<int> _kHostExportWavSampleRates =
    AudioExportPlan.uiSampleRatesForFormat('wav');
final List<int> _kHostExportMp3SampleRates =
    AudioExportPlan.uiSampleRatesForFormat('mp3');
const List<int> _kHostExportWavBitDepths = [16, 24, 32];
const List<int> _kHostExportMp3Bitrates = [128, 192, 256, 320];
const List<int> _kHostExportMp3VbrQualities = [0, 2, 4, 6];
const List<double> _kHostExportNormalizeTargetsDb = [-0.3, -1.0, -2.0];
const List<String> _kHostExportResampleQualities = ['draft', 'good', 'best'];
const List<String> _kHostExportChannelModes = ['stereo', 'mono'];
// Skipped by default because this host ffmpeg export matrix is too heavy for
// routine `flutter test` runs. Keep this suite for explicit regression runs.
const String _kSkipHostExportReason =
    'Skipped by default: host ffmpeg export verification is too heavy for routine flutter test runs.';

class _HostMp3Case {
  final int sampleRate;
  final String channelMode;
  final String resampleQuality;
  final String mp3Mode;
  final int mp3BitrateKbps;
  final int mp3VbrQuality;

  const _HostMp3Case({
    required this.sampleRate,
    required this.channelMode,
    required this.resampleQuality,
    required this.mp3Mode,
    required this.mp3BitrateKbps,
    required this.mp3VbrQuality,
  });

  String get label {
    final modeLabel =
        mp3Mode == 'cbr' ? 'cbr_${mp3BitrateKbps}k' : 'vbr_q$mp3VbrQuality';
    return '${sampleRate}hz_${channelMode}_${resampleQuality}_$modeLabel';
  }
}

Future<void> _ensureFfmpegAvailable() async {
  final result = await Process.run('ffmpeg', ['-version']);
  if (result.exitCode != 0) {
    throw StateError(
      'ffmpeg CLI is required for host export verification.\n'
      '${result.stderr}',
    );
  }
}

Future<Directory> _createWorkingDirectory(String prefix) async {
  return Directory.systemTemp.createTemp('${prefix}_');
}

Future<void> _deleteDirectoryIfPresent(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}

String _dequotePlanArg(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

List<String> _argvFromPlan(List<String> args) {
  return args.map(_dequotePlanArg).toList(growable: false);
}

Future<void> _runFfmpeg(List<String> args, {required String label}) async {
  final result = await Process.run(
    'ffmpeg',
    ['-hide_banner', '-loglevel', 'error', ...args],
  );
  if (result.exitCode != 0) {
    throw StateError(
      '$label failed with exit code ${result.exitCode}\n'
      'stdout:\n${result.stdout}\n'
      'stderr:\n${result.stderr}',
    );
  }
}

Future<String> _exportWithPlan({
  required String inputPath,
  required String outputPath,
  required String format,
  required int sampleRate,
  required int wavBitDepth,
  required bool wavDithering,
  required int mp3BitrateKbps,
  required String mp3Mode,
  required int mp3VbrQuality,
  required String channelMode,
  required bool normalize,
  required double normalizeTargetDb,
  required String resampleQuality,
}) async {
  final args = AudioExportPlan.buildFfmpegArgs(
    inputPath: inputPath,
    outputPath: outputPath,
    format: format,
    sampleRate: sampleRate,
    wavBitDepth: wavBitDepth,
    wavDithering: wavDithering,
    mp3BitrateKbps: mp3BitrateKbps,
    mp3Mode: mp3Mode,
    mp3VbrQuality: mp3VbrQuality,
    channelMode: channelMode,
    normalize: normalize,
    normalizeTargetDb: normalizeTargetDb,
    resampleQuality: resampleQuality,
  );
  await _runFfmpeg(_argvFromPlan(args), label: 'Export $outputPath');
  return outputPath;
}

Future<String> _decodeToAnalysisWav({
  required String inputPath,
  required String outputPath,
  required int sampleRate,
  required int channels,
}) async {
  await _runFfmpeg(
    [
      '-y',
      '-i',
      inputPath,
      '-ac',
      '$channels',
      '-ar',
      '$sampleRate',
      '-c:a',
      'pcm_f32le',
      outputPath,
    ],
    label: 'Decode $inputPath',
  );
  return outputPath;
}

AudioTestSignalSpec _resampledSpec({
  required AudioTestSignalSpec source,
  required int sampleRate,
  required String channelMode,
}) {
  return AudioTestSignalSpec(
    sampleRate: sampleRate,
    channels: channelMode == 'mono' ? 1 : 2,
    duration: source.duration,
    frequencyHz: source.frequencyHz,
    amplitude: source.amplitude,
    channelPhaseOffsetRadians:
        channelMode == 'mono' ? 0.0 : source.channelPhaseOffsetRadians,
  );
}

double _wavRmsThreshold({
  required int bitDepth,
  required bool dithering,
  required String resampleQuality,
}) {
  var threshold = 0.0025;
  if (bitDepth == 16) threshold += 0.0008;
  if (dithering) threshold += 0.0008;
  if (resampleQuality == 'draft') threshold += 0.0012;
  if (resampleQuality == 'good') threshold += 0.0004;
  return threshold;
}

double _wavPeakThreshold({
  required int bitDepth,
  required bool dithering,
  required String resampleQuality,
}) {
  var threshold = 0.015;
  if (bitDepth == 16) threshold += 0.004;
  if (dithering) threshold += 0.004;
  if (resampleQuality == 'draft') threshold += 0.01;
  if (resampleQuality == 'good') threshold += 0.004;
  return threshold;
}

double _wavCorrelationThreshold(String resampleQuality) {
  switch (resampleQuality) {
    case 'draft':
      return 0.9965;
    case 'good':
      return 0.998;
    case 'best':
    default:
      return 0.9985;
  }
}

Future<void> _assertWavMatchesTone({
  required String label,
  required String outputPath,
  required AudioTestSignalSpec expectedSpec,
  required int expectedBitDepth,
  required int maxOffsetSamples,
  required double rmsThreshold,
  required double peakThreshold,
  required double correlationThreshold,
}) async {
  final analysis = await AudioFileAnalysis.parseWavFile(outputPath);
  final comparison = AudioFileAnalysis.compareSamples(
    AudioTestSignal.generateMonoSamples(expectedSpec),
    analysis.decodeNormalizedMono(),
    maxOffsetSamples: maxOffsetSamples,
  );

  expect(analysis.sampleRate, expectedSpec.sampleRate, reason: label);
  expect(analysis.channels, expectedSpec.channels, reason: label);
  expect(analysis.bitsPerSample, expectedBitDepth, reason: label);
  expect(
    comparison.rmsError,
    lessThan(rmsThreshold),
    reason: '$label rms=${comparison.rmsError}',
  );
  expect(
    comparison.maxAbsoluteError,
    lessThan(peakThreshold),
    reason: '$label max=${comparison.maxAbsoluteError}',
  );
  expect(
    comparison.correlation,
    greaterThan(correlationThreshold),
    reason: '$label corr=${comparison.correlation}',
  );
}

Future<void> _assertStereoChannelsMatch({
  required String label,
  required String outputPath,
  required AudioTestSignalSpec expectedSpec,
  required int maxOffsetSamples,
  required double rmsThreshold,
  required double peakThreshold,
  required double correlationThreshold,
}) async {
  final analysis = await AudioFileAnalysis.parseWavFile(outputPath);
  final actualChannels = analysis.decodeNormalizedChannels();
  final expectedChannels = AudioTestSignal.generateChannelSamples(expectedSpec);
  expect(actualChannels.length, expectedChannels.length, reason: label);

  for (var channel = 0; channel < expectedChannels.length; channel++) {
    final comparison = AudioFileAnalysis.compareSamples(
      expectedChannels[channel],
      actualChannels[channel],
      maxOffsetSamples: maxOffsetSamples,
    );
    expect(
      comparison.rmsError,
      lessThan(rmsThreshold),
      reason: '$label channel=$channel rms=${comparison.rmsError}',
    );
    expect(
      comparison.maxAbsoluteError,
      lessThan(peakThreshold),
      reason: '$label channel=$channel max=${comparison.maxAbsoluteError}',
    );
    expect(
      comparison.correlation,
      greaterThan(correlationThreshold),
      reason: '$label channel=$channel corr=${comparison.correlation}',
    );
  }
}

void main() {
  setUpAll(() async {
    await _ensureFfmpegAvailable();
  });

  test(
    'host WAV export matrix stays structurally correct and numerically accurate',
    () async {
      Directory? workingDirectory;
      try {
        const sourceSpec = AudioTestSignalSpec(
          sampleRate: 48000,
          channels: 2,
          duration: Duration(milliseconds: 600),
          frequencyHz: 997.0,
          amplitude: 0.2,
        );

        workingDirectory = await _createWorkingDirectory('audio_export_wav_vm');
        final sourceFile = await AudioTestSignal.writePcm16WavFile(
          File(p.join(workingDirectory.path, 'source.wav')),
          sourceSpec,
        );

        for (final sampleRate in _kHostExportWavSampleRates) {
          for (final channelMode in _kHostExportChannelModes) {
            for (final bitDepth in _kHostExportWavBitDepths) {
              for (final dithering in const [false, true]) {
                for (final resampleQuality in _kHostExportResampleQualities) {
                  final label =
                      'wav_${sampleRate}_${channelMode}_${bitDepth}bit_'
                      '${dithering ? 'dither' : 'nodither'}_$resampleQuality';
                  final outputPath =
                      p.join(workingDirectory.path, '$label.wav');
                  final expectedSpec = _resampledSpec(
                    source: sourceSpec,
                    sampleRate: sampleRate,
                    channelMode: channelMode,
                  );

                  await _exportWithPlan(
                    inputPath: sourceFile.path,
                    outputPath: outputPath,
                    format: 'wav',
                    sampleRate: sampleRate,
                    wavBitDepth: bitDepth,
                    wavDithering: dithering,
                    mp3BitrateKbps: 192,
                    mp3Mode: 'cbr',
                    mp3VbrQuality: 2,
                    channelMode: channelMode,
                    normalize: false,
                    normalizeTargetDb: -1.0,
                    resampleQuality: resampleQuality,
                  );

                  await _assertWavMatchesTone(
                    label: label,
                    outputPath: outputPath,
                    expectedSpec: expectedSpec,
                    expectedBitDepth: bitDepth,
                    maxOffsetSamples: 2048,
                    rmsThreshold: _wavRmsThreshold(
                      bitDepth: bitDepth,
                      dithering: dithering,
                      resampleQuality: resampleQuality,
                    ),
                    peakThreshold: _wavPeakThreshold(
                      bitDepth: bitDepth,
                      dithering: dithering,
                      resampleQuality: resampleQuality,
                    ),
                    correlationThreshold:
                        _wavCorrelationThreshold(resampleQuality),
                  );
                }
              }
            }
          }
        }
      } finally {
        if (workingDirectory != null) {
          await _deleteDirectoryIfPresent(workingDirectory);
        }
      }
    },
    skip: _kSkipHostExportReason,
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test(
    'host WAV normalization matrix raises level without clipping',
    () async {
      Directory? workingDirectory;
      try {
        const sourceSpec = AudioTestSignalSpec(
          sampleRate: 48000,
          channels: 2,
          duration: Duration(milliseconds: 700),
          frequencyHz: 613.0,
          amplitude: 0.04,
        );

        workingDirectory =
            await _createWorkingDirectory('audio_export_wav_normalize_vm');
        final sourceFile = await AudioTestSignal.writePcm16WavFile(
          File(p.join(workingDirectory.path, 'source.wav')),
          sourceSpec,
        );
        final sourceMetrics = AudioFileAnalysis.measureSamples(
          AudioTestSignal.generateMonoSamples(sourceSpec),
        );

        for (final sampleRate in _kHostExportWavSampleRates) {
          for (final channelMode in _kHostExportChannelModes) {
            for (final bitDepth in _kHostExportWavBitDepths) {
              for (final resampleQuality in _kHostExportResampleQualities) {
                for (final targetDb in _kHostExportNormalizeTargetsDb) {
                  final label =
                      'wav_norm_${sampleRate}_${channelMode}_${bitDepth}bit_'
                      '${targetDb.toStringAsFixed(1)}db_$resampleQuality';
                  final outputPath =
                      p.join(workingDirectory.path, '$label.wav');

                  await _exportWithPlan(
                    inputPath: sourceFile.path,
                    outputPath: outputPath,
                    format: 'wav',
                    sampleRate: sampleRate,
                    wavBitDepth: bitDepth,
                    wavDithering: true,
                    mp3BitrateKbps: 192,
                    mp3Mode: 'cbr',
                    mp3VbrQuality: 2,
                    channelMode: channelMode,
                    normalize: true,
                    normalizeTargetDb: targetDb,
                    resampleQuality: resampleQuality,
                  );

                  final analysis = await AudioFileAnalysis.parseWavFile(
                    outputPath,
                  );
                  final metrics = AudioFileAnalysis.measureSamples(
                    analysis.decodeNormalizedMono(),
                  );

                  expect(analysis.sampleRate, sampleRate, reason: label);
                  expect(
                    analysis.channels,
                    channelMode == 'mono' ? 1 : 2,
                    reason: label,
                  );
                  expect(analysis.bitsPerSample, bitDepth, reason: label);
                  expect(metrics.peakAbsolute, lessThan(1.0), reason: label);
                  expect(
                    metrics.peakDbfs,
                    lessThanOrEqualTo(math.min(0.0, targetDb + 0.8)),
                    reason: '$label peak=${metrics.peakDbfs}',
                  );
                  expect(
                    metrics.peakDbfs,
                    greaterThan(sourceMetrics.peakDbfs + 6.0),
                    reason: '$label peak=${metrics.peakDbfs}',
                  );
                  expect(
                    metrics.rmsDbfs,
                    greaterThan(sourceMetrics.rmsDbfs + 6.0),
                    reason: '$label rms=${metrics.rmsDbfs}',
                  );
                }
              }
            }
          }
        }
      } finally {
        if (workingDirectory != null) {
          await _deleteDirectoryIfPresent(workingDirectory);
        }
      }
    },
    skip: _kSkipHostExportReason,
    timeout: const Timeout(Duration(minutes: 8)),
  );

  test(
    'host WAV stereo export preserves distinct left and right channels',
    () async {
      Directory? workingDirectory;
      try {
        const sourceSpec = AudioTestSignalSpec(
          sampleRate: 48000,
          channels: 2,
          duration: Duration(milliseconds: 700),
          frequencyHz: 997.0,
          amplitude: 0.18,
          channelPhaseOffsetRadians: math.pi / 2,
        );

        workingDirectory =
            await _createWorkingDirectory('audio_export_wav_stereo_vm');
        final sourceFile = await AudioTestSignal.writePcm16WavFile(
          File(p.join(workingDirectory.path, 'source.wav')),
          sourceSpec,
        );
        final outputPath = await _exportWithPlan(
          inputPath: sourceFile.path,
          outputPath: p.join(workingDirectory.path, 'stereo_out.wav'),
          format: 'wav',
          sampleRate: 96000,
          wavBitDepth: 24,
          wavDithering: false,
          mp3BitrateKbps: 192,
          mp3Mode: 'cbr',
          mp3VbrQuality: 2,
          channelMode: 'stereo',
          normalize: false,
          normalizeTargetDb: -1.0,
          resampleQuality: 'best',
        );

        await _assertStereoChannelsMatch(
          label: 'wav_stereo_phase',
          outputPath: outputPath,
          expectedSpec: _resampledSpec(
            source: sourceSpec,
            sampleRate: 96000,
            channelMode: 'stereo',
          ),
          maxOffsetSamples: 2048,
          rmsThreshold: 0.003,
          peakThreshold: 0.03,
          correlationThreshold: 0.998,
        );
      } finally {
        if (workingDirectory != null) {
          await _deleteDirectoryIfPresent(workingDirectory);
        }
      }
    },
    skip: _kSkipHostExportReason,
  );

  test(
    'host MP3 export matrix decodes cleanly across all user-facing options',
    () async {
      Directory? workingDirectory;
      try {
        const sourceSpec = AudioTestSignalSpec(
          sampleRate: 48000,
          channels: 2,
          duration: Duration(milliseconds: 700),
          frequencyHz: 431.0,
          amplitude: 0.17,
        );

        workingDirectory = await _createWorkingDirectory('audio_export_mp3_vm');
        final sourceFile = await AudioTestSignal.writePcm16WavFile(
          File(p.join(workingDirectory.path, 'source.wav')),
          sourceSpec,
        );

        final cases = <_HostMp3Case>[
          for (final sampleRate in _kHostExportMp3SampleRates)
            for (final channelMode in _kHostExportChannelModes)
              for (final resampleQuality in _kHostExportResampleQualities)
                for (final bitrate in _kHostExportMp3Bitrates)
                  _HostMp3Case(
                    sampleRate: sampleRate,
                    channelMode: channelMode,
                    resampleQuality: resampleQuality,
                    mp3Mode: 'cbr',
                    mp3BitrateKbps: bitrate,
                    mp3VbrQuality: 2,
                  ),
          for (final sampleRate in _kHostExportMp3SampleRates)
            for (final channelMode in _kHostExportChannelModes)
              for (final resampleQuality in _kHostExportResampleQualities)
                for (final quality in _kHostExportMp3VbrQualities)
                  _HostMp3Case(
                    sampleRate: sampleRate,
                    channelMode: channelMode,
                    resampleQuality: resampleQuality,
                    mp3Mode: 'vbr',
                    mp3BitrateKbps: 192,
                    mp3VbrQuality: quality,
                  ),
        ];

        for (final testCase in cases) {
          final outputPath =
              p.join(workingDirectory.path, '${testCase.label}.mp3');
          final decodedPath =
              p.join(workingDirectory.path, '${testCase.label}.analysis.wav');

          await _exportWithPlan(
            inputPath: sourceFile.path,
            outputPath: outputPath,
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
            resampleQuality: testCase.resampleQuality,
          );

          final mp3Analysis = await AudioFileAnalysis.parseMp3File(outputPath);
          expect(mp3Analysis.sampleRate, testCase.sampleRate,
              reason: testCase.label);
          expect(
            mp3Analysis.channelCount,
            testCase.channelMode == 'mono' ? 1 : 2,
            reason: testCase.label,
          );
          if (testCase.mp3Mode == 'cbr') {
            expect(
              mp3Analysis.bitrateMode,
              Mp3BitrateMode.cbr,
              reason: testCase.label,
            );
            expect(
              mp3Analysis.nominalBitrateKbps,
              testCase.mp3BitrateKbps,
              reason: testCase.label,
            );
          } else {
            expect(
              mp3Analysis.bitrateMode,
              Mp3BitrateMode.vbr,
              reason: testCase.label,
            );
          }

          await _decodeToAnalysisWav(
            inputPath: outputPath,
            outputPath: decodedPath,
            sampleRate: testCase.sampleRate,
            channels: testCase.channelMode == 'mono' ? 1 : 2,
          );
          final decodedAnalysis =
              await AudioFileAnalysis.parseWavFile(decodedPath);
          final expectedSpec = _resampledSpec(
            source: sourceSpec,
            sampleRate: testCase.sampleRate,
            channelMode: testCase.channelMode,
          );
          final comparison = AudioFileAnalysis.compareSamples(
            AudioTestSignal.generateMonoSamples(expectedSpec),
            decodedAnalysis.decodeNormalizedMono(),
            maxOffsetSamples: 4608,
          );

          expect(
            decodedAnalysis.sampleRate,
            testCase.sampleRate,
            reason: testCase.label,
          );
          expect(
            decodedAnalysis.channels,
            testCase.channelMode == 'mono' ? 1 : 2,
            reason: testCase.label,
          );
          expect(
            comparison.rmsError,
            lessThan(0.04),
            reason: '${testCase.label} rms=${comparison.rmsError}',
          );
          expect(
            comparison.maxAbsoluteError,
            lessThan(0.24),
            reason: '${testCase.label} max=${comparison.maxAbsoluteError}',
          );
          expect(
            comparison.correlation,
            greaterThan(0.97),
            reason: '${testCase.label} corr=${comparison.correlation}',
          );
        }
      } finally {
        if (workingDirectory != null) {
          await _deleteDirectoryIfPresent(workingDirectory);
        }
      }
    },
    skip: _kSkipHostExportReason,
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'host MP3 normalization preserves headroom while raising level',
    () async {
      Directory? workingDirectory;
      try {
        const sourceSpec = AudioTestSignalSpec(
          sampleRate: 48000,
          channels: 2,
          duration: Duration(milliseconds: 700),
          frequencyHz: 997.0,
          amplitude: 0.04,
        );

        workingDirectory =
            await _createWorkingDirectory('audio_export_mp3_normalize_vm');
        final sourceFile = await AudioTestSignal.writePcm16WavFile(
          File(p.join(workingDirectory.path, 'source.wav')),
          sourceSpec,
        );
        final sourceMetrics = AudioFileAnalysis.measureSamples(
          AudioTestSignal.generateMonoSamples(sourceSpec),
        );

        for (final targetDb in _kHostExportNormalizeTargetsDb) {
          for (final resampleQuality in _kHostExportResampleQualities) {
            final activeCases = [
              _HostMp3Case(
                sampleRate: 44100,
                channelMode: 'stereo',
                resampleQuality: resampleQuality,
                mp3Mode: 'cbr',
                mp3BitrateKbps: 192,
                mp3VbrQuality: 2,
              ),
              _HostMp3Case(
                sampleRate: 48000,
                channelMode: 'mono',
                resampleQuality: resampleQuality,
                mp3Mode: 'vbr',
                mp3BitrateKbps: 192,
                mp3VbrQuality: 2,
              ),
            ];
            for (final testCase in activeCases) {
              final label =
                  '${testCase.label}_${targetDb.toStringAsFixed(1)}db';
              final outputPath = p.join(workingDirectory.path, '$label.mp3');
              final decodedPath =
                  p.join(workingDirectory.path, '$label.analysis.wav');

              await _exportWithPlan(
                inputPath: sourceFile.path,
                outputPath: outputPath,
                format: 'mp3',
                sampleRate: testCase.sampleRate,
                wavBitDepth: 16,
                wavDithering: true,
                mp3BitrateKbps: testCase.mp3BitrateKbps,
                mp3Mode: testCase.mp3Mode,
                mp3VbrQuality: testCase.mp3VbrQuality,
                channelMode: testCase.channelMode,
                normalize: true,
                normalizeTargetDb: targetDb,
                resampleQuality: testCase.resampleQuality,
              );

              await _decodeToAnalysisWav(
                inputPath: outputPath,
                outputPath: decodedPath,
                sampleRate: testCase.sampleRate,
                channels: testCase.channelMode == 'mono' ? 1 : 2,
              );

              final metrics = AudioFileAnalysis.measureSamples(
                (await AudioFileAnalysis.parseWavFile(decodedPath))
                    .decodeNormalizedMono(),
              );
              expect(metrics.peakAbsolute, lessThan(1.0), reason: label);
              expect(
                metrics.peakDbfs,
                lessThanOrEqualTo(math.min(0.0, targetDb + 1.0)),
                reason: '$label peak=${metrics.peakDbfs}',
              );
              expect(
                metrics.peakDbfs,
                greaterThan(sourceMetrics.peakDbfs + 4.0),
                reason: '$label peak=${metrics.peakDbfs}',
              );
              expect(
                metrics.rmsDbfs,
                greaterThan(sourceMetrics.rmsDbfs + 4.0),
                reason: '$label rms=${metrics.rmsDbfs}',
              );
            }
          }
        }
      } finally {
        if (workingDirectory != null) {
          await _deleteDirectoryIfPresent(workingDirectory);
        }
      }
    },
    skip: _kSkipHostExportReason,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test('host MP3 stereo export preserves distinct channels after decode',
      () async {
    Directory? workingDirectory;
    try {
      const sourceSpec = AudioTestSignalSpec(
        sampleRate: 48000,
        channels: 2,
        duration: Duration(milliseconds: 700),
        frequencyHz: 997.0,
        amplitude: 0.18,
        channelPhaseOffsetRadians: math.pi / 2,
      );

      workingDirectory =
          await _createWorkingDirectory('audio_export_mp3_lr_vm');
      final sourceFile = await AudioTestSignal.writePcm16WavFile(
        File(p.join(workingDirectory.path, 'source.wav')),
        sourceSpec,
      );

      final cases = <_HostMp3Case>[
        const _HostMp3Case(
          sampleRate: 44100,
          channelMode: 'stereo',
          resampleQuality: 'best',
          mp3Mode: 'cbr',
          mp3BitrateKbps: 320,
          mp3VbrQuality: 2,
        ),
        const _HostMp3Case(
          sampleRate: 48000,
          channelMode: 'stereo',
          resampleQuality: 'best',
          mp3Mode: 'vbr',
          mp3BitrateKbps: 192,
          mp3VbrQuality: 0,
        ),
      ];

      for (final testCase in cases) {
        final label = testCase.label;
        final outputPath = p.join(workingDirectory.path, '$label.mp3');
        final decodedPath =
            p.join(workingDirectory.path, '$label.analysis.wav');
        await _exportWithPlan(
          inputPath: sourceFile.path,
          outputPath: outputPath,
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
          resampleQuality: testCase.resampleQuality,
        );
        await _decodeToAnalysisWav(
          inputPath: outputPath,
          outputPath: decodedPath,
          sampleRate: testCase.sampleRate,
          channels: 2,
        );

        await _assertStereoChannelsMatch(
          label: label,
          outputPath: decodedPath,
          expectedSpec: _resampledSpec(
            source: sourceSpec,
            sampleRate: testCase.sampleRate,
            channelMode: 'stereo',
          ),
          maxOffsetSamples: 4608,
          rmsThreshold: 0.045,
          peakThreshold: 0.28,
          correlationThreshold: 0.965,
        );
      }
    } finally {
      if (workingDirectory != null) {
        await _deleteDirectoryIfPresent(workingDirectory);
      }
      }
  }, skip: _kSkipHostExportReason);
}
