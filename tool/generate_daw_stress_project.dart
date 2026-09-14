import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

const _defaultRows = 99;
const _defaultClips = 400;
const _defaultSeed = 17;
const _sampleRate = 48000;
const _defaultMinClipDurationSeconds = 0.25;
const _defaultMaxClipDurationSeconds = 20.0;
const _midiInstrumentId = 'mixroom.basic_synth';
const _midiInstrumentName = 'Basic Synth';

Future<void> main(List<String> arguments) async {
  try {
    final options = StressProjectOptions.parse(arguments);
    final summary = await generateStressProject(options);
    stdout.writeln('Generated ${summary.projectName}');
    stdout.writeln('  project: ${summary.projectDirectory.path}');
    stdout.writeln('  rows: ${summary.rowCount}');
    stdout.writeln(
      '  clips: ${summary.clipCount} '
      '(${summary.audioClipCount} audio, ${summary.midiClipCount} MIDI)',
    );
    stdout.writeln('  seed: ${summary.seed}');
    if (summary.bundleFile != null) {
      stdout.writeln('  bundle: ${summary.bundleFile!.path}');
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 74;
  }
}

class StressProjectOptions {
  const StressProjectOptions({
    required this.outputDirectory,
    required this.rowCount,
    required this.clipCount,
    required this.seed,
    required this.projectName,
    this.minClipDurationSeconds = _defaultMinClipDurationSeconds,
    this.maxClipDurationSeconds = _defaultMaxClipDurationSeconds,
    this.bundleFile,
  });

  final Directory outputDirectory;
  final int rowCount;
  final int clipCount;
  final int seed;
  final String projectName;
  final double minClipDurationSeconds;
  final double maxClipDurationSeconds;
  final File? bundleFile;

  factory StressProjectOptions.parse(List<String> arguments) {
    String? outputPath;
    var rowCount = _defaultRows;
    int? clipCount;
    var seed = _defaultSeed;
    String? projectName;
    String? bundlePath;
    var minClipDurationSeconds = _defaultMinClipDurationSeconds;
    var maxClipDurationSeconds = _defaultMaxClipDurationSeconds;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--help' || argument == '-h') {
        throw const FormatException(
          'Generate a deterministic Mixroom DAW stress project.',
        );
      }
      if (!argument.startsWith('--')) {
        throw FormatException('Unexpected argument: $argument');
      }
      if (index + 1 >= arguments.length) {
        throw FormatException('Missing value for $argument');
      }
      final value = arguments[++index];
      switch (argument) {
        case '--output':
          outputPath = value;
        case '--rows':
          rowCount = _positiveInt(value, argument);
        case '--clips':
          clipCount = _positiveInt(value, argument);
        case '--seed':
          seed =
              int.tryParse(value) ??
              (throw FormatException('Invalid integer for $argument: $value'));
        case '--name':
          projectName = value.trim();
          if (projectName.isEmpty) {
            throw const FormatException('Project name cannot be empty.');
          }
        case '--bundle':
          bundlePath = value.trim();
          if (bundlePath.isEmpty) {
            throw const FormatException('Bundle path cannot be empty.');
          }
        case '--min-clip-seconds':
          minClipDurationSeconds = _positiveDouble(value, argument);
        case '--max-clip-seconds':
          maxClipDurationSeconds = _positiveDouble(value, argument);
        default:
          throw FormatException('Unknown option: $argument');
      }
    }

    if (outputPath == null || outputPath.trim().isEmpty) {
      throw const FormatException('--output is required.');
    }
    final resolvedClipCount = clipCount ?? _defaultClips;
    if (minClipDurationSeconds > maxClipDurationSeconds) {
      throw const FormatException(
        '--min-clip-seconds must not exceed --max-clip-seconds.',
      );
    }

    return StressProjectOptions(
      outputDirectory: Directory(outputPath),
      rowCount: rowCount,
      clipCount: resolvedClipCount,
      seed: seed,
      projectName:
          projectName ?? 'PRO-17 Stress ${rowCount}r ${resolvedClipCount}c',
      minClipDurationSeconds: minClipDurationSeconds,
      maxClipDurationSeconds: maxClipDurationSeconds,
      bundleFile: bundlePath == null ? null : File(bundlePath),
    );
  }

  static int _positiveInt(String value, String option) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      throw FormatException('$option must be a positive integer.');
    }
    return parsed;
  }

  static double _positiveDouble(String value, String option) {
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      throw FormatException('$option must be a positive number.');
    }
    return parsed;
  }
}

class StressProjectSummary {
  const StressProjectSummary({
    required this.projectDirectory,
    required this.projectName,
    required this.rowCount,
    required this.clipCount,
    required this.audioClipCount,
    required this.midiClipCount,
    required this.seed,
    this.bundleFile,
  });

  final Directory projectDirectory;
  final String projectName;
  final int rowCount;
  final int clipCount;
  final int audioClipCount;
  final int midiClipCount;
  final int seed;
  final File? bundleFile;
}

Future<StressProjectSummary> generateStressProject(
  StressProjectOptions options,
) async {
  final projectDirectory = options.outputDirectory;
  if (await projectDirectory.exists()) {
    throw FileSystemException(
      'Refusing to overwrite an existing output directory.',
      projectDirectory.path,
    );
  }

  final audioDirectory = Directory('${projectDirectory.path}/audio');
  await audioDirectory.create(recursive: true);
  final sourceFile = File('${audioDirectory.path}/pro17_stress_source.wav');
  await _writeStressWave(
    sourceFile,
    durationSeconds: options.maxClipDurationSeconds.ceil(),
  );

  final random = math.Random(options.seed);
  final rows = <Map<String, Object?>>[];
  final rowStates = <Map<String, Object?>>[];
  final rowEffects = <Map<String, Object?>>[];
  final rowIds = <int>[];

  for (var rowIndex = 0; rowIndex < options.rowCount; rowIndex++) {
    final rowId = 17000 + rowIndex;
    rowIds.add(rowId);
    final isMidi = rowIndex.isOdd;
    rows.add(<String, Object?>{
      'rowId': rowId,
      'name': isMidi
          ? 'MIDI ${(rowIndex ~/ 2) + 1}'
          : 'Audio ${(rowIndex ~/ 2) + 1}',
      'iconId': isMidi ? 2 : 0,
      'kind': isMidi ? 'instrument' : 'audio',
      if (isMidi) 'instrumentId': _midiInstrumentId,
      if (isMidi) 'instrumentName': _midiInstrumentName,
      if (isMidi) 'instrumentParams': <String, double>{},
      'inputChannelStart': 0,
      'inputChannelCount': 1,
    });
    rowStates.add(<String, Object?>{
      'row': rowIndex,
      'rowId': rowId,
      'gain': 2.0,
      'pan': 0.5,
      'volumeAutomation': <Map<String, double>>[
        <String, double>{'x': 0.0, 'volume': 1.0},
        <String, double>{'x': 1.0, 'volume': 1.0},
      ],
      'automationLanes': <Object?>[],
      'automationClips': <Object?>[],
      'selectedAutomationTargetId': null,
      'muted': false,
      'soloed': false,
      'inputChannelStart': 0,
      'inputChannelCount': 1,
    });
    rowEffects.add(<String, Object?>{
      'row': rowIndex,
      'rowId': rowId,
      'effects': <Object?>[],
    });
  }

  final clipsPerRow = List<int>.filled(options.rowCount, 0);
  final tracks = <Map<String, Object?>>[];
  var audioClipCount = 0;
  var midiClipCount = 0;

  for (var clipIndex = 0; clipIndex < options.clipCount; clipIndex++) {
    final rowIndex = clipIndex % options.rowCount;
    final rowClipIndex = clipsPerRow[rowIndex]++;
    final isMidi = rowIndex.isOdd;
    final durationMs = _clipDurationMs(
      clipIndex,
      random,
      minSeconds: options.minClipDurationSeconds,
      maxSeconds: options.maxClipDurationSeconds,
    );
    final offsetSeconds = _clipOffsetSeconds(
      clipIndex: clipIndex,
      rowIndex: rowIndex,
      rowClipIndex: rowClipIndex,
      random: random,
    );
    final clipId = 'pro17_${isMidi ? 'midi' : 'audio'}_$clipIndex';

    if (isMidi) {
      midiClipCount++;
    } else {
      audioClipCount++;
    }

    tracks.add(<String, Object?>{
      'fileName': isMidi
          ? 'pro17_generated_midi_$clipIndex.wav'
          : sourceFile.uri.pathSegments.last,
      'label': '${isMidi ? 'MIDI' : 'Audio'} Clip ${clipIndex + 1}',
      'clipType': isMidi ? 'midi' : 'audio',
      'trimStartMs': 0,
      'trimEndMs': durationMs,
      'offset': offsetSeconds,
      'crossfade': 0.0,
      'gain': 2.0,
      'normalizeVolume': false,
      'normalizeGain': 1.0,
      'preNormalizeGain': 2.0,
      'pitchSemitones': 0.0,
      'isReversed': false,
      'sourceTempoBpm': isMidi ? 120.0 : 0.0,
      'stretchToProjectTempo': isMidi,
      'tempoStretchPreservePitch': isMidi,
      'tempoWarpMode': 'complex',
      'recordingLatencyMs': 0.0,
      'alignmentOffsetMs': 0.0,
      'rowIndex': rowIndex,
      'rowId': rowIds[rowIndex],
      'clipId': clipId,
      'automation': <Map<String, double>>[
        <String, double>{'x': 0.0, 'volume': 1.0},
        <String, double>{'x': 1.0, 'volume': 1.0},
      ],
      'instrumentId': isMidi ? _midiInstrumentId : '',
      'instrumentName': isMidi ? _midiInstrumentName : '',
      'instrumentParams': <String, double>{},
      'midiNotes': isMidi
          ? _midiNotes(clipIndex: clipIndex, durationMs: durationMs)
          : <Object?>[],
      'hostedInstrumentStateB64': '',
    });
  }

  final createdTimestamp = 1700000000000 + options.seed.abs();
  final project = <String, Object?>{
    'version': 6,
    'name': options.projectName,
    'nameConfirmed': true,
    'createdAt': createdTimestamp,
    // Keep deterministic musical content while making a directly installed
    // fixture easy to find at the top of the app's On Device project list.
    'lastOpenedAt': DateTime.now().millisecondsSinceEpoch,
    'projectId':
        'pro17-stress-${options.seed}-${options.rowCount}-${options.clipCount}',
    'tempoBpm': 120.0,
    'projectKey': 'C',
    'timeSignature': <String, int>{'numerator': 4, 'denominator': 4},
    'tempoStretchEnabled': false,
    'tempoStretchPreservePitchDefault': true,
    'rows': rows,
    'trackGroups': <Object?>[],
    'tracks': tracks,
    'rowStates': rowStates,
    'rowEffects': rowEffects,
    'master': <String, Object?>{
      'gain': 2.0,
      'pan': 0.5,
      'effects': <String, Object?>{'effects': <Object?>[]},
    },
    'ui': <String, Object?>{
      'showProducerCaptureUi': false,
      'desktopKeyboardMidiEnabled': false,
      'desktopSpacebarStopReturnsToStart': false,
      'allowMultipleExpandedRows': true,
      'expandRowsOnTrackSelect': true,
      'crossfadeMode': 'equal_power',
      'metronomeEnabled': false,
      'metronomeVolume': 0.5,
      'sampleRate': _sampleRate,
      'bufferSize': 512,
      'midiInputChannel': 0,
      'loopEnabled': false,
      'loopStartMs': 0,
      'loopEndMs': 0,
    },
  };

  final encoder = const JsonEncoder.withIndent('  ');
  await File(
    '${projectDirectory.path}/project.json',
  ).writeAsString('${encoder.convert(project)}\n', flush: true);

  final bundleFile = options.bundleFile;
  if (bundleFile != null) {
    await _writeImportableBundle(
      projectDirectory: projectDirectory,
      bundleFile: bundleFile,
    );
  }

  return StressProjectSummary(
    projectDirectory: projectDirectory,
    projectName: options.projectName,
    rowCount: options.rowCount,
    clipCount: options.clipCount,
    audioClipCount: audioClipCount,
    midiClipCount: midiClipCount,
    seed: options.seed,
    bundleFile: bundleFile,
  );
}

Future<void> _writeImportableBundle({
  required Directory projectDirectory,
  required File bundleFile,
}) async {
  if (await bundleFile.exists()) {
    throw FileSystemException(
      'Refusing to overwrite an existing bundle.',
      bundleFile.path,
    );
  }
  await bundleFile.parent.create(recursive: true);

  final archive = Archive();
  final projectFile = File('${projectDirectory.path}/project.json');
  final projectBytes = await projectFile.readAsBytes();
  archive.addFile(
    ArchiveFile('project.json', projectBytes.length, projectBytes),
  );

  final metaBytes = utf8.encode(
    jsonEncode(<String, Object?>{
      'bundleVersion': 2,
      'audioMode': 'preserveAsIs',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'hasCompatibilityAudio': false,
      'fixture': 'PRO-17',
    }),
  );
  archive.addFile(ArchiveFile('meta.json', metaBytes.length, metaBytes));

  final audioDirectory = Directory('${projectDirectory.path}/audio');
  await for (final entity in audioDirectory.list(followLinks: false)) {
    if (entity is! File) continue;
    final bytes = await entity.readAsBytes();
    final name = entity.uri.pathSegments.last;
    archive.addFile(ArchiveFile('audio/$name', bytes.length, bytes));
  }

  final encoded = ZipEncoder().encode(archive);
  if (encoded.isEmpty) {
    throw const FileSystemException('Failed to encode stress project bundle.');
  }
  await bundleFile.writeAsBytes(encoded, flush: true);
}

int _clipDurationMs(
  int clipIndex,
  math.Random random, {
  required double minSeconds,
  required double maxSeconds,
}) {
  final minMs = (minSeconds * 1000).round();
  final maxMs = (maxSeconds * 1000).round();
  if (minMs == maxMs) return minMs;
  const fractions = <double>[0.0, 0.08, 0.18, 0.32, 0.5, 0.68, 0.82, 1.0];
  final fraction =
      fractions[(clipIndex + random.nextInt(fractions.length)) %
          fractions.length];
  return (minMs + (maxMs - minMs) * fraction).round().clamp(minMs, maxMs);
}

double _clipOffsetSeconds({
  required int clipIndex,
  required int rowIndex,
  required int rowClipIndex,
  required math.Random random,
}) {
  const zoneStarts = <double>[0.0, 60.0, 300.0, 900.0, 1200.0];
  // Use clip order directly so every fixture shape deterministically exercises
  // all timeline zones. Mixing row modulo values here can alias for particular
  // row counts (notably 99) and accidentally skip the 15-minute zone.
  final zone = clipIndex % zoneStarts.length;
  final spread = (rowIndex % 17) * 0.8;
  final repeatedClipSpacing = rowClipIndex * 10.0;
  final jitter = random.nextInt(3000) / 1000.0;
  return zoneStarts[zone] + spread + repeatedClipSpacing + jitter;
}

List<Map<String, Object>> _midiNotes({
  required int clipIndex,
  required int durationMs,
}) {
  final durationBeats = math.max(0.5, durationMs / 500.0);
  final noteCount = math.max(1, math.min(24, durationBeats.ceil()));
  const scale = <int>[0, 2, 4, 7, 9];
  return List<Map<String, Object>>.generate(noteCount, (noteIndex) {
    final startBeat = noteIndex * durationBeats / noteCount;
    final nextBeat = (noteIndex + 1) * durationBeats / noteCount;
    return <String, Object>{
      'id': 'pro17_note_${clipIndex}_$noteIndex',
      'pitch':
          48 +
          scale[(clipIndex + noteIndex) % scale.length] +
          12 * ((clipIndex ~/ scale.length) % 2),
      'startBeat': startBeat,
      'lengthBeats': math.max(0.125, (nextBeat - startBeat) * 0.75),
      'velocity': 0.55 + ((clipIndex + noteIndex) % 4) * 0.1,
    };
  });
}

Future<void> _writeStressWave(File file, {required int durationSeconds}) async {
  final sampleCount = _sampleRate * durationSeconds;
  final dataSize = sampleCount * 2;
  final bytes = Uint8List(44 + dataSize);
  final header = ByteData.sublistView(bytes);

  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes[offset + index] = value.codeUnitAt(index);
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, _sampleRate, Endian.little);
  header.setUint32(28, _sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataSize, Endian.little);

  final oneSecondBytes = Uint8List(_sampleRate * 2);
  final oneSecondData = ByteData.sublistView(oneSecondBytes);
  for (var sample = 0; sample < _sampleRate; sample++) {
    final time = sample / _sampleRate;
    final envelope = 0.65 + 0.2 * math.sin(2 * math.pi * 0.25 * time);
    final value =
        envelope *
        (0.18 * math.sin(2 * math.pi * 110 * time) +
            0.09 * math.sin(2 * math.pi * 220 * time) +
            0.04 * math.sin(2 * math.pi * 330 * time));
    oneSecondData.setInt16(sample * 2, (value * 32767).round(), Endian.little);
  }
  for (var second = 0; second < durationSeconds; second++) {
    bytes.setRange(
      44 + second * oneSecondBytes.length,
      44 + (second + 1) * oneSecondBytes.length,
      oneSecondBytes,
    );
  }
  await file.writeAsBytes(bytes, flush: true);
}

const _usage = '''
Usage:
  dart tool/generate_daw_stress_project.dart \\
    --output <new-project-directory> [options]

Options:
  --rows <count>   Number of alternating audio/MIDI rows (default: 99)
  --clips <count>  Total clips, round-robin across rows (default: 400)
  --seed <integer> Deterministic layout seed (default: 17)
  --name <name>    Project display name
  --bundle <path>  Also write an importable .mixroom bundle for mobile devices
  --min-clip-seconds <seconds>  Shortest clip duration (default: 0.25)
  --max-clip-seconds <seconds>  Longest clip and WAV duration (default: 20)
''';
