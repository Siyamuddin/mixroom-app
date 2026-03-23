import 'dart:io';
import 'dart:math' as math;

import 'package:mixroom/ffmpeg/ffmpeg.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<List<double>> extractNormalizedWaveformWithFfmpeg({
  required String filePath,
  required int targetBars,
  int pcmRate = 8000,
  double amplify = 4.0,
}) async {
  if (targetBars <= 0) return const <double>[];

  final tmpDir = await getTemporaryDirectory();
  final rawPath = p.join(
    tmpDir.path,
    'waveform_${filePath.hashCode}_${DateTime.now().microsecondsSinceEpoch}.raw',
  );

  try {
    await FFmpegKit.execute(
      '-v error -i "$filePath" -ac 1 -ar $pcmRate -f s16le -y "$rawPath"',
    );

    final rawFile = File(rawPath);
    if (!await rawFile.exists()) {
      return const <double>[];
    }

    final bytes = await rawFile.readAsBytes();
    if (bytes.length < 2) {
      return const <double>[];
    }

    final totalSamples = bytes.length ~/ 2;
    if (totalSamples <= 0) {
      return const <double>[];
    }

    final out = List<double>.filled(targetBars, 0.0, growable: false);
    for (int i = 0; i < targetBars; i++) {
      int start = (i * totalSamples / targetBars).floor();
      int end = ((i + 1) * totalSamples / targetBars).floor();
      start = start.clamp(0, totalSamples);
      end = end.clamp(0, totalSamples);
      if (end <= start) continue;

      double sumSq = 0.0;
      int count = 0;
      for (int s = start; s < end; s++) {
        final bi = s * 2;
        int v = bytes[bi] | (bytes[bi + 1] << 8);
        if ((v & 0x8000) != 0) {
          v -= 0x10000;
        }
        final sample = v / 32768.0;
        sumSq += sample * sample;
        count++;
      }
      if (count > 0) {
        out[i] = math.sqrt(sumSq / count).clamp(0.0, 1.0);
      }
    }

    return out.map((v) {
      final amplified = v * amplify;
      if (amplified > 1.0) return 1.0;
      if (amplified < 0.0) return 0.0;
      return amplified;
    }).toList(growable: false);
  } finally {
    try {
      final rawFile = File(rawPath);
      if (await rawFile.exists()) {
        await rawFile.delete();
      }
    } catch (_) {}
  }
}
