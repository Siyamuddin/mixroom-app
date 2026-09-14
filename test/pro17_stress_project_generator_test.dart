import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/generate_daw_stress_project.dart';

void main() {
  test(
    'generates alternating real-audio and MIDI stress project rows',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('pro17_generator_');
      addTearDown(() => sandbox.delete(recursive: true));
      final output = Directory('${sandbox.path}/stress-project');

      final summary = await generateStressProject(
        StressProjectOptions(
          outputDirectory: output,
          rowCount: 8,
          clipCount: 24,
          seed: 17,
          projectName: 'PRO-17 Test Fixture',
        ),
      );

      final json =
          jsonDecode(await File('${output.path}/project.json').readAsString())
              as Map<String, dynamic>;
      final rows = (json['rows'] as List).cast<Map<String, dynamic>>();
      final tracks = (json['tracks'] as List).cast<Map<String, dynamic>>();

      expect(summary.audioClipCount, 12);
      expect(summary.midiClipCount, 12);
      expect(rows, hasLength(8));
      expect(tracks, hasLength(24));
      expect(rows[0]['kind'], 'audio');
      expect(rows[1]['kind'], 'instrument');
      expect(rows[1]['instrumentId'], 'mixroom.basic_synth');
      expect(
        tracks.where((track) => track['clipType'] == 'audio'),
        hasLength(12),
      );
      expect(
        tracks.where((track) => track['clipType'] == 'midi'),
        hasLength(12),
      );
      expect(
        tracks.map((track) => track['trimEndMs'] as int).toSet().length,
        greaterThan(3),
      );
      expect(
        tracks
            .map((track) => track['offset'] as double)
            .reduce((a, b) => a > b ? a : b),
        greaterThan(900),
      );
      expect(
        File('${output.path}/audio/pro17_stress_source.wav').lengthSync(),
        greaterThan(1000000),
      );
    },
  );

  test('refuses to overwrite an existing output directory', () async {
    final sandbox = await Directory.systemTemp.createTemp('pro17_generator_');
    addTearDown(() => sandbox.delete(recursive: true));

    expect(
      () => generateStressProject(
        StressProjectOptions(
          outputDirectory: sandbox,
          rowCount: 2,
          clipCount: 2,
          seed: 17,
          projectName: 'Existing',
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('accepts fixtures across the former row boundary', () {
    for (final count in [99, 100, 101, 120]) {
      final options = StressProjectOptions.parse(<String>[
        '--output',
        '/tmp/pro17-row-boundary',
        '--rows',
        '$count',
      ]);
      expect(options.rowCount, count);
    }
  });

  test('writes an importable mobile bundle when requested', () async {
    final sandbox = await Directory.systemTemp.createTemp('pro17_bundle_');
    addTearDown(() => sandbox.delete(recursive: true));
    final output = Directory('${sandbox.path}/stress-project');
    final bundle = File('${sandbox.path}/PRO-17-stress.mixroom');

    final summary = await generateStressProject(
      StressProjectOptions(
        outputDirectory: output,
        rowCount: 4,
        clipCount: 8,
        seed: 17,
        projectName: 'PRO-17 Bundle Fixture',
        bundleFile: bundle,
      ),
    );

    expect(summary.bundleFile?.path, bundle.path);
    final archive = ZipDecoder().decodeBytes(await bundle.readAsBytes());
    final names = archive.map((entry) => entry.name).toSet();
    expect(
      names,
      containsAll(<String>{
        'project.json',
        'meta.json',
        'audio/pro17_stress_source.wav',
      }),
    );
  });

  test('accepts fixtures across the former clip boundary', () {
    for (final count in [499, 500, 501, 600]) {
      final options = StressProjectOptions.parse(<String>[
        '--output',
        '/tmp/pro17-clip-boundary',
        '--clips',
        '$count',
      ]);
      expect(options.clipCount, count);
    }
  });

  test('still rejects invalid counts', () {
    for (final option in ['--rows', '--clips']) {
      for (final value in ['0', '-1', '1.5', 'NaN', 'abc']) {
        expect(
          () => StressProjectOptions.parse([
            '--output',
            '/tmp/pro17-invalid',
            option,
            value,
          ]),
          throwsFormatException,
        );
      }
    }
  });

  test('generates all 120 rows and 600 mixed clips without omission', () async {
    final sandbox = await Directory.systemTemp.createTemp('pro17_capacity_');
    addTearDown(() => sandbox.delete(recursive: true));
    final output = Directory('${sandbox.path}/stress-project');
    final summary = await generateStressProject(
      StressProjectOptions(
        outputDirectory: output,
        rowCount: 120,
        clipCount: 600,
        seed: 17,
        projectName: 'PRO-17 Capacity',
      ),
    );
    final project =
        jsonDecode(await File('${output.path}/project.json').readAsString())
            as Map;
    final rows = project['rows'] as List;
    final tracks = project['tracks'] as List;
    expect(rows, hasLength(120));
    expect(tracks, hasLength(600));
    expect(tracks.map((track) => track['clipId']).toSet(), hasLength(600));
    expect(summary.audioClipCount, 300);
    expect(summary.midiClipCount, 300);
    expect(
      File('${output.path}/audio/pro17_stress_source.wav').existsSync(),
      true,
    );
  });

  test('99-row fixture still occupies the 15-minute timeline zone', () async {
    final sandbox = await Directory.systemTemp.createTemp('pro17_zones_');
    addTearDown(() => sandbox.delete(recursive: true));
    final output = Directory('${sandbox.path}/stress-project');

    await generateStressProject(
      StressProjectOptions(
        outputDirectory: output,
        rowCount: 99,
        clipCount: 400,
        seed: 17,
        projectName: 'PRO-17 Timeline Zones',
      ),
    );

    final json =
        jsonDecode(await File('${output.path}/project.json').readAsString())
            as Map<String, dynamic>;
    final tracks = (json['tracks'] as List).cast<Map<String, dynamic>>();
    final maxOffset = tracks
        .map((track) => (track['offset'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);
    expect(maxOffset, greaterThan(900));
  });

  test('long-clip fixture uses real 30-second to 5-minute media', () async {
    final sandbox = await Directory.systemTemp.createTemp('pro17_long_');
    addTearDown(() => sandbox.delete(recursive: true));
    final output = Directory('${sandbox.path}/stress-project');

    await generateStressProject(
      StressProjectOptions(
        outputDirectory: output,
        rowCount: 6,
        clipCount: 24,
        seed: 17099,
        projectName: 'PRO-17 Long Clips',
        minClipDurationSeconds: 30,
        maxClipDurationSeconds: 300,
      ),
    );

    final json =
        jsonDecode(await File('${output.path}/project.json').readAsString())
            as Map<String, dynamic>;
    final tracks = (json['tracks'] as List).cast<Map<String, dynamic>>();
    final durations = tracks
        .map((track) => (track['trimEndMs'] as num).toInt())
        .toList();
    expect(durations.reduce(math.min), 30000);
    expect(durations.reduce(math.max), 300000);
    expect(
      File('${output.path}/audio/pro17_stress_source.wav').lengthSync(),
      greaterThan(28000000),
    );
    expect(
      tracks.where((track) => (track['offset'] as num) >= 1200),
      isNotEmpty,
    );
  });
}
