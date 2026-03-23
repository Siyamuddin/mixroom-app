import 'dart:async';
import 'dart:io';

import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:mixroom/ffmpeg/ffmpeg.dart';
import 'package:mixroom/helpers/audio_export_plan.dart';
import 'package:mixroom/helpers/audio_test_signal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProbedAudioFile {
  final String formatName;
  final String codecName;
  final int sampleRate;
  final int channelCount;
  final int? bitRate;
  final double durationSeconds;

  const ProbedAudioFile({
    required this.formatName,
    required this.codecName,
    required this.sampleRate,
    required this.channelCount,
    required this.bitRate,
    required this.durationSeconds,
  });
}

class ExportTestRowConfig {
  final int rowIndex;
  final String name;
  final double? gain0to3;
  final double? panMinus1To1;
  final List<Map<String, dynamic>>? trackAutomationPoints;
  final List<Map<String, dynamic>>? rowGainAutomationPoints;
  final List<Map<String, dynamic>>? rowPanAutomationPoints;

  const ExportTestRowConfig({
    required this.rowIndex,
    required this.name,
    this.gain0to3,
    this.panMinus1To1,
    this.trackAutomationPoints,
    this.rowGainAutomationPoints,
    this.rowPanAutomationPoints,
  });
}

class ExportTestClipConfig {
  final int clipIndex;
  final int rowIndex;
  final String inputPath;
  final double startSec;
  final double lengthSec;
  final double inFileOffsetSec;
  final double? clipGain0to3;
  final double? panMinus1To1;

  const ExportTestClipConfig({
    required this.clipIndex,
    required this.rowIndex,
    required this.inputPath,
    this.startSec = 0.0,
    this.lengthSec = 0.0,
    this.inFileOffsetSec = 0.0,
    this.clipGain0to3,
    this.panMinus1To1,
  });
}

class AudioExportIntegrationHarness {
  const AudioExportIntegrationHarness._();

  static Future<Directory> createWorkingDirectory(String prefix) async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(
      p.join(
        tempDir.path,
        '${prefix}_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File> writeFixtureWav(
    Directory directory,
    String name,
    AudioTestSignalSpec spec,
  ) async {
    final file = File(p.join(directory.path, '$name.wav'));
    return AudioTestSignal.writePcm16WavFile(file, spec);
  }

  static Future<String> exportWithPlan({
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

    final session = await FFmpegKit.execute(args.join(' '));
    await ensureSessionSucceeded(session, 'Audio export');
    return outputPath;
  }

  static Future<String> decodeToAnalysisWav({
    required String inputPath,
    required Directory workingDirectory,
    required String fileStem,
    required int sampleRate,
    required int channels,
  }) async {
    final outputPath = p.join(workingDirectory.path, '$fileStem.analysis.wav');
    final session = await FFmpegKit.execute(
      '-y -i "$inputPath" -ac $channels -ar $sampleRate -c:a pcm_f32le "$outputPath"',
    );
    await ensureSessionSucceeded(session, 'Audio decode');
    return outputPath;
  }

  static Future<ProbedAudioFile> probeAudioFile(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final information = session.getMediaInformation();
    if (information == null) {
      throw StateError('Missing FFprobe media information for $path');
    }

    final audioStream = information.getStreams().firstWhere(
          (stream) => stream.getType() == 'audio',
          orElse: () => throw StateError('No audio stream found in $path'),
        );

    return ProbedAudioFile(
      formatName: information.getFormat() ?? '',
      codecName: audioStream.getCodec() ?? '',
      sampleRate: int.tryParse(audioStream.getSampleRate() ?? '') ?? 0,
      channelCount: audioStream.getNumberProperty('channels')?.toInt() ?? 0,
      bitRate: int.tryParse(
        audioStream.getBitrate() ?? information.getBitrate() ?? '',
      ),
      durationSeconds: double.tryParse(information.getDuration() ?? '') ?? 0.0,
    );
  }

  static Future<String> renderSingleClipMix({
    required String inputPath,
    required Directory workingDirectory,
    int sampleRate = 48000,
  }) async {
    await JuceAudioEngine.shutdown();
    await JuceAudioEngine.initialise();

    final rowIdsByIndex = await _prepareRows(
      const [
        ExportTestRowConfig(rowIndex: 0, name: 'Integration Track'),
      ],
    );
    final rowId = rowIdsByIndex[0];
    if (rowId == null) {
      throw StateError('Unable to resolve a JUCE row for export testing');
    }

    await JuceAudioEngine.loadClip(
      0,
      rowId,
      inputPath,
      startSec: 0.0,
      lengthSec: 0.0,
      inFileOffsetSec: 0.0,
    );

    await _waitForTrackDuration(0);

    final rawPath = p.join(workingDirectory.path, 'raw_mix.wav');
    final exportedPath = await JuceAudioEngine.exportMix(
      rawPath,
      format: 'wav',
      sampleRate: sampleRate,
      wavBitDepth: 16,
      wavDithering: false,
    );
    if (exportedPath.isEmpty) {
      throw StateError('JUCE exportMix returned an empty path');
    }
    return exportedPath;
  }

  static Future<void> configureMix({
    required List<ExportTestRowConfig> rows,
    required List<ExportTestClipConfig> clips,
  }) async {
    if (rows.isEmpty) {
      throw StateError('configureMix requires at least one row');
    }

    final sortedRows = List<ExportTestRowConfig>.from(rows)
      ..sort((a, b) => a.rowIndex.compareTo(b.rowIndex));
    for (var i = 0; i < sortedRows.length; i++) {
      if (sortedRows[i].rowIndex != i) {
        throw StateError(
          'Export test rows must use contiguous row indices starting at 0',
        );
      }
    }

    await JuceAudioEngine.shutdown();
    await JuceAudioEngine.initialise();

    final rowIdsByIndex = await _prepareRows(sortedRows);

    final sortedClips = List<ExportTestClipConfig>.from(clips)
      ..sort((a, b) => a.clipIndex.compareTo(b.clipIndex));
    for (final clip in sortedClips) {
      final rowId = rowIdsByIndex[clip.rowIndex];
      if (rowId == null) {
        throw StateError('Missing JUCE row for clip ${clip.clipIndex}');
      }
      await JuceAudioEngine.loadClip(
        clip.clipIndex,
        rowId,
        clip.inputPath,
        startSec: clip.startSec,
        lengthSec: clip.lengthSec,
        inFileOffsetSec: clip.inFileOffsetSec,
      );
    }

    for (final clip in sortedClips) {
      await _waitForTrackDuration(clip.clipIndex);
      if (clip.clipGain0to3 != null) {
        await JuceAudioEngine.setClipGain(clip.clipIndex, clip.clipGain0to3!);
      }
      if (clip.panMinus1To1 != null) {
        await JuceAudioEngine.setClipPan(clip.clipIndex, clip.panMinus1To1!);
      }
    }

    for (final row in sortedRows) {
      if (row.gain0to3 != null) {
        await JuceAudioEngine.setRowGain(row.rowIndex, row.gain0to3!);
      }
      if (row.panMinus1To1 != null) {
        await JuceAudioEngine.setRowPan(row.rowIndex, row.panMinus1To1!);
      }
      if (row.trackAutomationPoints != null) {
        await JuceAudioEngine.setTrackAutomationPoints(
          row.rowIndex,
          row.trackAutomationPoints!,
        );
      }
      if (row.rowGainAutomationPoints != null) {
        await JuceAudioEngine.setRowGainAutomationPoints(
          row.rowIndex,
          row.rowGainAutomationPoints!,
        );
      }
      if (row.rowPanAutomationPoints != null) {
        await JuceAudioEngine.setRowPanAutomationPoints(
          row.rowIndex,
          row.rowPanAutomationPoints!,
        );
      }
    }

    // Native bridge automation and row-state mutations are dispatched asynchronously.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await JuceAudioEngine.seekTransport(0.0);
    await JuceAudioEngine.setAutomationTransport(0.0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  static Future<String> exportCurrentMix({
    required Directory workingDirectory,
    required String fileName,
    String format = 'wav',
    int sampleRate = 44100,
    int wavBitDepth = 16,
    bool wavDithering = true,
    int mp3BitrateKbps = 192,
  }) async {
    final outputPath = p.join(workingDirectory.path, fileName);
    final exportedPath = await JuceAudioEngine.exportMix(
      outputPath,
      format: format,
      sampleRate: sampleRate,
      wavBitDepth: wavBitDepth,
      wavDithering: wavDithering,
      mp3BitrateKbps: mp3BitrateKbps,
    );
    if (exportedPath.isEmpty) {
      throw StateError('JUCE exportMix returned an empty path');
    }
    final outFile = File(exportedPath);
    if (!await outFile.exists() || (await outFile.length()) <= 0) {
      throw StateError('Export output file missing: $exportedPath');
    }
    return exportedPath;
  }

  static Future<void> ensureSessionSucceeded(
    Session session,
    String operation,
  ) async {
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) return;

    final logs = await session.getLogs();
    final messages = logs
        .map((log) => log.getMessage().trim())
        .where((message) => message.isNotEmpty)
        .toList();
    final tail = messages.length <= 8
        ? messages.join('\n')
        : messages.sublist(messages.length - 8).join('\n');
    throw StateError(
      '$operation failed with return code $returnCode${tail.isEmpty ? '' : '\n$tail'}',
    );
  }

  static Future<void> deleteDirectoryIfPresent(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  static Future<void> resetEngine() async {
    await JuceAudioEngine.shutdown();
  }

  static Future<void> _waitForTrackDuration(
    int clipIndex, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final duration = await JuceAudioEngine.getTrackDuration(clipIndex);
      if (duration > 0.0) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('Timed out waiting for track $clipIndex to load');
  }

  static Future<Map<int, int>> _prepareRows(
    List<ExportTestRowConfig> rows,
  ) async {
    var currentRows = await JuceAudioEngine.getRows();
    while (currentRows.length > rows.length) {
      final rowId = currentRows.last['rowId'];
      if (rowId is! int) {
        throw StateError('Missing JUCE rowId while trimming rows');
      }
      final removed = await JuceAudioEngine.removeRow(rowId);
      if (!removed) {
        throw StateError('Unable to remove extra JUCE row $rowId');
      }
      currentRows = await JuceAudioEngine.getRows();
    }

    while (currentRows.length < rows.length) {
      final nextConfig = rows[currentRows.length];
      final rowId = await JuceAudioEngine.addRow(nextConfig.name, iconId: 0);
      if (rowId < 0) {
        throw StateError('Unable to create JUCE row ${nextConfig.rowIndex}');
      }
      currentRows = await JuceAudioEngine.getRows();
    }

    currentRows = await JuceAudioEngine.getRows();
    if (currentRows.length != rows.length) {
      throw StateError(
        'Expected ${rows.length} JUCE rows, found ${currentRows.length}',
      );
    }

    final rowIdsByIndex = <int, int>{};
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowMap = currentRows[i];
      final rowId = rowMap['rowId'];
      if (rowId is! int) {
        throw StateError('Missing JUCE rowId for row ${row.rowIndex}');
      }
      final renamed = await JuceAudioEngine.renameRow(rowId, row.name);
      if (!renamed) {
        throw StateError('Unable to rename JUCE row ${row.rowIndex}');
      }
      rowIdsByIndex[row.rowIndex] = rowId;
    }

    return rowIdsByIndex;
  }
}
