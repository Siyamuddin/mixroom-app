import 'dart:convert';
import 'dart:io';

import 'package:mixroom/helpers/audio_file_analysis.dart';

Future<void> main(List<String> args) async {
  final parsed = _parseArgs(args);
  final filePath = parsed['file'];
  if (filePath == null || filePath.isEmpty) {
    _printUsage(stderr);
    exitCode = 64;
    return;
  }

  final file = File(filePath);
  if (!await file.exists()) {
    stderr.writeln('File not found: $filePath');
    exitCode = 66;
    return;
  }

  final ext = file.path.split('.').last.toLowerCase();
  if (ext == 'wav') {
    final analysis = await AudioFileAnalysis.parseWavFile(file.path);
    final mono = analysis.decodeNormalizedMono();
    final metrics = AudioFileAnalysis.measureSamples(mono);
    final report = <String, Object?>{
      'type': 'wav',
      'path': file.path,
      'formatCode': analysis.formatCode,
      'sampleRate': analysis.sampleRate,
      'channels': analysis.channels,
      'bitsPerSample': analysis.bitsPerSample,
      'frameCount': analysis.frameCount,
      'durationSeconds': analysis.frameCount / analysis.sampleRate,
      'peakDbfs': metrics.peakDbfs,
      'rmsDbfs': metrics.rmsDbfs,
    };

    final expectedPath = parsed['expected'];
    if (expectedPath != null && expectedPath.isNotEmpty) {
      final expected = await AudioFileAnalysis.parseWavFile(expectedPath);
      final comparison = AudioFileAnalysis.compareSamples(
        expected.decodeNormalizedMono(),
        mono,
        maxOffsetSamples: int.tryParse(parsed['max-offset'] ?? '') ?? 0,
      );
      report['expectedPath'] = expectedPath;
      report['pcmBitExact'] = analysis.pcmDataEquals(expected);
      report['comparison'] = <String, Object?>{
        'bestOffsetSamples': comparison.bestOffsetSamples,
        'comparedSamples': comparison.comparedSamples,
        'rmsError': comparison.rmsError,
        'maxAbsoluteError': comparison.maxAbsoluteError,
        'meanAbsoluteError': comparison.meanAbsoluteError,
        'correlation': comparison.correlation,
        'bitExact': comparison.bitExact,
      };
    }

    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    return;
  }

  if (ext == 'mp3') {
    final analysis = await AudioFileAnalysis.parseMp3File(file.path);
    final report = <String, Object?>{
      'type': 'mp3',
      'path': file.path,
      'sampleRate': analysis.sampleRate,
      'channels': analysis.channelCount,
      'frameCount': analysis.frameCount,
      'bitrateMode': analysis.bitrateMode.name,
      'nominalBitrateKbps': analysis.nominalBitrateKbps,
      'averageBitrateKbps': analysis.averageBitrateKbps,
      'estimatedDurationSeconds': analysis.estimatedDurationSeconds,
      'vbrTag': analysis.vbrTag,
      'hasId3v2Tag': analysis.hasId3v2Tag,
      'observedBitratesKbps': analysis.observedBitratesKbps.toList()..sort(),
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    return;
  }

  stderr.writeln('Unsupported file type: .$ext');
  exitCode = 65;
}

Map<String, String> _parseArgs(List<String> args) {
  final values = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    final key = arg.substring(2);
    if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
      values[key] = 'true';
      continue;
    }
    values[key] = args[++i];
  }
  return values;
}

void _printUsage(IOSink sink) {
  sink.writeln(
    'Usage: dart run tool/audio_export_analyze.dart --file <path> '
    '[--expected <wav>] [--max-offset <samples>]',
  );
}
