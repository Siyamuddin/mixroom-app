import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_ffmpeg_kit.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({
    required this.temporaryPath,
    required this.applicationDocumentsPath,
  });

  final String temporaryPath;
  final String applicationDocumentsPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      applicationDocumentsPath;
}

Uint8List _buildTestWavBytes({
  int sampleRate = 44100,
  int channels = 2,
  int durationMs = 300,
  double frequencyHz = 440.0,
}) {
  final sampleCount = math.max(1, (sampleRate * durationMs / 1000).round());
  const bytesPerSample = 2;
  final dataLength = sampleCount * channels * bytesPerSample;
  final totalLength = 44 + dataLength;
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes);

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
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  data.setUint16(32, channels * bytesPerSample, Endian.little);
  data.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);

  var offset = 44;
  for (var i = 0; i < sampleCount; i++) {
    final phase = 2.0 * math.pi * frequencyHz * i / sampleRate;
    final sample = (math.sin(phase) * 0.4 * 32767.0).round();
    for (var channel = 0; channel < channels; channel++) {
      data.setInt16(offset, sample, Endian.little);
      offset += 2;
    }
  }

  return bytes;
}

Future<Directory> _createProjectWithTone({
  required String name,
  required String fileName,
  required String label,
  required Uint8List bytes,
}) async {
  final projectDir = await ProjectManager.createNewProjectDir(name: name);
  final audioDir = ProjectManager.audioDir(projectDir);
  await File(p.join(audioDir.path, fileName)).writeAsBytes(bytes, flush: true);
  final json = await ProjectManager.readProjectJson(projectDir);
  json['tracks'] = <Map<String, dynamic>>[
    <String, dynamic>{
      'fileName': fileName,
      'label': label,
      'rowIndex': 0,
      'trimStartMs': 0,
      'trimEndMs': 300,
      'offset': 0.0,
      'gain': 2.0,
    },
  ];
  await ProjectManager.writeProjectJson(projectDir, json);
  return projectDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform originalPathProvider;
  late Directory sandboxRoot;
  late Directory tempDir;
  late Directory docsDir;
  late FakeFfmpegKit fakeFfmpegKit;

  setUp(() async {
    originalPathProvider = PathProviderPlatform.instance;
    sandboxRoot = await Directory.systemTemp.createTemp(
      'mixroom_project_bundle_update_',
    );
    tempDir = Directory(p.join(sandboxRoot.path, 'tmp'))
      ..createSync(recursive: true);
    docsDir = Directory(p.join(sandboxRoot.path, 'docs'))
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      temporaryPath: tempDir.path,
      applicationDocumentsPath: docsDir.path,
    );
    ProjectManager.setRootDirectoryForTesting(
      Directory(p.join(docsDir.path, 'mixroom_projects'))
        ..createSync(recursive: true),
    );
    fakeFfmpegKit = FakeFfmpegKit(
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger,
    );
    fakeFfmpegKit.install();
  });

  tearDown(() async {
    fakeFfmpegKit.uninstall();
    ProjectManager.setRootDirectoryForTesting(null);
    PathProviderPlatform.instance = originalPathProvider;
    if (await sandboxRoot.exists()) {
      await sandboxRoot.delete(recursive: true);
    }
  });

  test('updates an existing project folder in place', () async {
    final sourceBytes = _buildTestWavBytes();
    final sourceDir = await _createProjectWithTone(
      name: 'Source Mix',
      fileName: 'tone.wav',
      label: 'Tone',
      bytes: sourceBytes,
    );
    final sourceJson = await ProjectManager.readProjectJson(sourceDir);

    final destBytes = _buildTestWavBytes(frequencyHz: 220.0);
    final destDir = await _createProjectWithTone(
      name: 'Local Mix',
      fileName: 'old.wav',
      label: 'Old',
      bytes: destBytes,
    );
    final destJsonBefore = await ProjectManager.readProjectJson(destDir);
    final destProjectId = destJsonBefore['projectId'];
    final destCreatedAt = destJsonBefore['createdAt'];
    final destPath = destDir.path;

    final versionsDir = Directory(p.join(destDir.path, '.mixroom_versions'));
    await versionsDir.create(recursive: true);
    final versionsMarker = File(p.join(versionsDir.path, 'manifest.json'));
    await versionsMarker.writeAsString('{"keep":true}', flush: true);

    final bundlePath = await ProjectBundle.exportMixroomBundle(
      projectDir: sourceDir,
      audioMode: BundleAudioMode.preserveAsIs,
    );

    await ProjectBundleImport.updateProjectFromMixroomBundle(
      projectDir: destDir,
      bundleFile: File(bundlePath),
      audioStrategy: ImportAudioStrategy.keepAsBundled,
    );

    expect(destDir.path, destPath);
    expect(await destDir.exists(), isTrue);
    final destJson = await ProjectManager.readProjectJson(destDir);
    expect(destJson['projectId'], destProjectId);
    expect(destJson['createdAt'], destCreatedAt);
    expect(destJson['name'], p.basename(destDir.path));
    expect(destJson.containsKey('cloudProjectId'), isFalse);

    final tracks = (destJson['tracks'] as List?)?.cast<Map>() ?? const <Map>[];
    expect(tracks, hasLength(1));
    expect(tracks.first['fileName'], 'tone.wav');
    expect(tracks.first['label'], 'Tone');

    final importedAudio = File(
      p.join(ProjectManager.audioDir(destDir).path, 'tone.wav'),
    );
    expect(await importedAudio.exists(), isTrue);
    expect(await importedAudio.readAsBytes(), sourceBytes);
    expect(await versionsMarker.exists(), isTrue);
    expect(await versionsMarker.readAsString(), '{"keep":true}');
    expect(sourceJson['projectId'], isNot(destProjectId));
  });

  test('corrupt bundle leaves the existing project.json untouched', () async {
    final destDir = await _createProjectWithTone(
      name: 'Keep Mix',
      fileName: 'keep.wav',
      label: 'Keep',
      bytes: _buildTestWavBytes(),
    );
    final jsonFile = File(p.join(destDir.path, 'project.json'));
    final originalBytes = await jsonFile.readAsBytes();

    final corruptBundle = File(p.join(tempDir.path, 'corrupt.mixroom'));
    await corruptBundle.writeAsBytes(Uint8List.fromList(<int>[1, 2, 3, 4]));

    await expectLater(
      ProjectBundleImport.updateProjectFromMixroomBundle(
        projectDir: destDir,
        bundleFile: corruptBundle,
        audioStrategy: ImportAudioStrategy.keepAsBundled,
      ),
      throwsA(anything),
    );

    expect(await jsonFile.readAsBytes(), originalBytes);
    expect(
      await Directory(
        p.join(destDir.path, ProjectBundleImport.incomingUpdateDirectoryName),
      ).exists(),
      isFalse,
    );
  });

  test(
    'flac conversion remaps audio and removes files not in the bundle',
    () async {
      final sourceBytes = _buildTestWavBytes();
      final sourceDir = await _createProjectWithTone(
        name: 'Source Mix',
        fileName: 'tone.wav',
        label: 'Tone',
        bytes: sourceBytes,
      );
      final destBytes = _buildTestWavBytes(frequencyHz: 220.0);
      final destDir = await _createProjectWithTone(
        name: 'Local Mix',
        fileName: 'old.wav',
        label: 'Old',
        bytes: destBytes,
      );
      final leftover = File(
        p.join(ProjectManager.audioDir(destDir).path, 'leftover.wav'),
      );
      await leftover.writeAsBytes(destBytes, flush: true);

      final bundlePath = await ProjectBundle.exportMixroomBundle(
        projectDir: sourceDir,
        audioMode: BundleAudioMode.flacLossless,
      );

      await ProjectBundleImport.updateProjectFromMixroomBundle(
        projectDir: destDir,
        bundleFile: File(bundlePath),
        audioStrategy: ImportAudioStrategy.convertFlacToWav48k,
      );

      final destJson = await ProjectManager.readProjectJson(destDir);
      final tracks =
          (destJson['tracks'] as List?)?.cast<Map>() ?? const <Map>[];
      expect(tracks, hasLength(1));
      expect(tracks.first['fileName'], 'tone.wav');
      expect(
        await File(
          p.join(ProjectManager.audioDir(destDir).path, 'tone.wav'),
        ).exists(),
        isTrue,
      );
      expect(await leftover.exists(), isFalse);
      expect(
        await File(
          p.join(ProjectManager.audioDir(destDir).path, 'old.wav'),
        ).exists(),
        isFalse,
      );
      expect(
        await Directory(
          p.join(destDir.path, ProjectBundleImport.incomingUpdateDirectoryName),
        ).exists(),
        isFalse,
      );
      expect(
        await Directory(
          '${ProjectManager.audioDir(destDir).path}${ProjectBundleImport.outgoingUpdateSuffix}',
        ).exists(),
        isFalse,
      );
    },
  );

  test('failed ffmpeg conversion leaves the live project unchanged', () async {
    final sourceBytes = _buildTestWavBytes();
    final sourceDir = await _createProjectWithTone(
      name: 'Source Mix',
      fileName: 'tone.wav',
      label: 'Tone',
      bytes: sourceBytes,
    );
    final destBytes = _buildTestWavBytes(frequencyHz: 220.0);
    final destDir = await _createProjectWithTone(
      name: 'Local Mix',
      fileName: 'old.wav',
      label: 'Old',
      bytes: destBytes,
    );
    final jsonFile = File(p.join(destDir.path, 'project.json'));
    final originalJsonBytes = await jsonFile.readAsBytes();
    final oldAudio = File(
      p.join(ProjectManager.audioDir(destDir).path, 'old.wav'),
    );
    final originalAudioBytes = await oldAudio.readAsBytes();
    final compatDir = Directory(p.join(destDir.path, 'compatibility'));
    await compatDir.create(recursive: true);
    final compatMarker = File(p.join(compatDir.path, 'keep.txt'));
    await compatMarker.writeAsString('keep', flush: true);

    final bundlePath = await ProjectBundle.exportMixroomBundle(
      projectDir: sourceDir,
      audioMode: BundleAudioMode.flacLossless,
    );
    fakeFfmpegKit.failNext();

    await expectLater(
      ProjectBundleImport.updateProjectFromMixroomBundle(
        projectDir: destDir,
        bundleFile: File(bundlePath),
        audioStrategy: ImportAudioStrategy.convertFlacToWav48k,
      ),
      throwsA(isA<ProcessException>()),
    );

    expect(await jsonFile.readAsBytes(), originalJsonBytes);
    expect(await oldAudio.readAsBytes(), originalAudioBytes);
    expect(await compatMarker.readAsString(), 'keep');
    expect(
      await Directory(
        p.join(destDir.path, ProjectBundleImport.incomingUpdateDirectoryName),
      ).exists(),
      isFalse,
    );
    expect(
      await Directory(
        '${ProjectManager.audioDir(destDir).path}${ProjectBundleImport.outgoingUpdateSuffix}',
      ).exists(),
      isFalse,
    );
    expect(
      await Directory(
        '${compatDir.path}${ProjectBundleImport.outgoingUpdateSuffix}',
      ).exists(),
      isFalse,
    );
  });
}
