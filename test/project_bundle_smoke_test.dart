import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_compatibility_service.dart';
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
      'mixroom_project_bundle_smoke_',
    );
    tempDir = Directory(p.join(sandboxRoot.path, 'tmp'))
      ..createSync(recursive: true);
    docsDir = Directory(p.join(sandboxRoot.path, 'docs'))
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      temporaryPath: tempDir.path,
      applicationDocumentsPath: docsDir.path,
    );
    fakeFfmpegKit = FakeFfmpegKit(
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger,
    );
    fakeFfmpegKit.install();
  });

  tearDown(() async {
    fakeFfmpegKit.uninstall();
    PathProviderPlatform.instance = originalPathProvider;
    if (await sandboxRoot.exists()) {
      await sandboxRoot.delete(recursive: true);
    }
  });

  test(
    'project bundle export/import preserves bundled audio and track mapping',
    () async {
      final projectDir = await ProjectManager.createNewProjectDir(
        name: 'Bundle Smoke',
      );
      final audioDir = ProjectManager.audioDir(projectDir);
      final sourceFile = File(p.join(audioDir.path, 'tone.wav'));
      final sourceBytes = _buildTestWavBytes();
      await sourceFile.writeAsBytes(sourceBytes, flush: true);

      final json = await ProjectManager.readProjectJson(projectDir);
      json['tracks'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'fileName': 'tone.wav',
          'label': 'Tone',
          'rowIndex': 0,
          'trimStartMs': 0,
          'trimEndMs': 300,
          'offset': 0.0,
          'gain': 2.0,
        },
      ];
      await ProjectManager.writeProjectJson(projectDir, json);

      final bundlePath = await ProjectBundle.exportMixroomBundle(
        projectDir: projectDir,
        audioMode: BundleAudioMode.preserveAsIs,
      );
      final bundleFile = File(bundlePath);
      expect(await bundleFile.exists(), isTrue);
      expect(await bundleFile.length(), greaterThan(1024));
      final canonical = await ProjectBundle.readCanonicalProjectJsonFromBundle(
        bundleFile,
      );
      expect(canonical, isNotNull);
      expect((canonical!['tracks'] as List).single['fileName'], 'tone.wav');

      final importedDir = await ProjectBundleImport.importMixroomBundle(
        bundleFile: bundleFile,
        audioStrategy: ImportAudioStrategy.keepAsBundled,
      );

      final importedJson = await ProjectManager.readProjectJson(importedDir);
      expect(importedJson['name'], p.basename(importedDir.path));

      final tracks =
          (importedJson['tracks'] as List?)?.cast<Map>() ?? const <Map>[];
      expect(tracks, hasLength(1));
      expect(tracks.first['fileName'], 'tone.wav');

      final importedAudio = File(
        p.join(ProjectManager.audioDir(importedDir).path, 'tone.wav'),
      );
      expect(await importedAudio.exists(), isTrue);
      expect(await importedAudio.readAsBytes(), sourceBytes);

      final reparsed =
          jsonDecode(
                await File(
                  p.join(importedDir.path, 'project.json'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(
        ((reparsed['tracks'] as List).first as Map)['fileName'],
        'tone.wav',
      );
    },
  );

  test('project bundle sharing strips cloud sync metadata', () async {
    final projectDir = await ProjectManager.createNewProjectDir(
      name: 'Cloud Metadata Bundle',
    );
    final json = await ProjectManager.readProjectJson(projectDir);
    json['cloudProjectId'] = 'personal-cloud-project';
    json['cloudDocumentRevision'] = 7;
    json['cloudSyncedAt'] = '2026-05-07T00:00:00Z';
    await ProjectManager.writeProjectJson(projectDir, json);

    final bundlePath = await ProjectBundle.exportMixroomBundle(
      projectDir: projectDir,
      audioMode: BundleAudioMode.preserveAsIs,
    );
    final importedDir = await ProjectBundleImport.importMixroomBundle(
      bundleFile: File(bundlePath),
      audioStrategy: ImportAudioStrategy.keepAsBundled,
    );

    final localJson = await ProjectManager.readProjectJson(projectDir);
    expect(localJson['cloudProjectId'], 'personal-cloud-project');

    final importedJson = await ProjectManager.readProjectJson(importedDir);
    expect(importedJson.containsKey('cloudProjectId'), isFalse);
    expect(importedJson.containsKey('cloudDocumentRevision'), isFalse);
    expect(importedJson.containsKey('cloudSyncedAt'), isFalse);
  });

  test(
    'project bundle flac export/import path remaps filenames and runs ffmpeg',
    () async {
      final projectDir = await ProjectManager.createNewProjectDir(
        name: 'Bundle Smoke Flac',
      );
      final audioDir = ProjectManager.audioDir(projectDir);
      final sourceFile = File(p.join(audioDir.path, 'tone.wav'));
      final sourceBytes = _buildTestWavBytes();
      await sourceFile.writeAsBytes(sourceBytes, flush: true);

      final json = await ProjectManager.readProjectJson(projectDir);
      json['tracks'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'fileName': 'tone.wav',
          'label': 'Tone',
          'rowIndex': 0,
          'trimStartMs': 0,
          'trimEndMs': 300,
          'offset': 0.0,
          'gain': 2.0,
        },
      ];
      await ProjectManager.writeProjectJson(projectDir, json);

      final bundlePath = await ProjectBundle.exportMixroomBundle(
        projectDir: projectDir,
        audioMode: BundleAudioMode.flacLossless,
      );
      final bundleFile = File(bundlePath);
      expect(await bundleFile.exists(), isTrue);

      final importedDir = await ProjectBundleImport.importMixroomBundle(
        bundleFile: bundleFile,
        audioStrategy: ImportAudioStrategy.convertFlacToWav48k,
      );

      final importedJson = await ProjectManager.readProjectJson(importedDir);
      final tracks =
          (importedJson['tracks'] as List?)?.cast<Map>() ?? const <Map>[];
      expect(tracks, hasLength(1));
      expect(tracks.first['fileName'], 'tone.wav');

      final importedAudio = File(
        p.join(ProjectManager.audioDir(importedDir).path, 'tone.wav'),
      );
      expect(await importedAudio.exists(), isTrue);
      expect(await importedAudio.readAsBytes(), sourceBytes);

      expect(fakeFfmpegKit.executedCommands, hasLength(2));
      expect(
        fakeFfmpegKit.executedCommands.first,
        containsAllInOrder(<String>['-c:a', 'flac']),
      );
      expect(
        fakeFfmpegKit.executedCommands.last,
        containsAllInOrder(<String>['-c:a', 'pcm_s16le', '-ar', '48000']),
      );
    },
  );

  test('cloud source bundle can omit a stale compatible version', () async {
    final projectDir = await ProjectManager.createNewProjectDir(
      name: 'Source Only Cloud Bundle',
    );
    final json = await ProjectManager.readProjectJson(projectDir);
    json['rowEffects'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'row': 0,
        'effects': <Map<String, dynamic>>[
          <String, dynamic>{
            'effectId': 'vst3:com.acme.delay',
            'pluginOrigin': 'third_party',
          },
        ],
      },
    ];
    await ProjectManager.writeProjectJson(projectDir, json);
    final staleCompatibilityDir = ProjectCompatibilityService.directoryFor(
      projectDir,
    );
    await staleCompatibilityDir.create(recursive: true);
    await File(
      p.join(staleCompatibilityDir.path, 'stale.txt'),
    ).writeAsString('stale');

    expect(
      ProjectBundle.exportMixroomBundle(
        projectDir: projectDir,
        audioMode: BundleAudioMode.preserveAsIs,
      ),
      throwsA(isA<StateError>()),
    );

    final bundlePath = await ProjectBundle.exportMixroomBundle(
      projectDir: projectDir,
      audioMode: BundleAudioMode.preserveAsIs,
      requireCurrentCompatibility: false,
    );
    final importedDir = await ProjectBundleImport.importMixroomBundle(
      bundleFile: File(bundlePath),
      audioStrategy: ImportAudioStrategy.keepAsBundled,
    );
    final importedJson = await ProjectManager.readProjectJson(importedDir);
    final importedEffects =
        ((importedJson['rowEffects'] as List).single as Map)['effects'] as List;
    expect((importedEffects.single as Map)['effectId'], contains('acme'));
    expect(
      await ProjectCompatibilityService.directoryFor(importedDir).exists(),
      isFalse,
    );
  });

  test('project bundle preserves a current compatible audio copy', () async {
    final projectDir = await ProjectManager.createNewProjectDir(
      name: 'Compatible Bundle',
    );
    final json = await ProjectManager.readProjectJson(projectDir);
    json['rowEffects'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'row': 0,
        'effects': <Map<String, dynamic>>[
          <String, dynamic>{
            'effectId': 'vst3:com.acme.delay',
            'pluginOrigin': 'third_party',
          },
        ],
      },
    ];
    await ProjectManager.writeProjectJson(projectDir, json);
    final dependency = ProjectCompatibilityService.inspect(
      json,
    ).dependencies.single;
    final audioDir = ProjectCompatibilityService.audioDirectoryFor(projectDir);
    await audioDir.create(recursive: true);
    const fileName = 'compatibility/audio/frozen.wav';
    await File(p.join(projectDir.path, fileName)).writeAsBytes(<int>[1]);
    await ProjectCompatibilityService.writeCompatibleCopy(
      projectDir: projectDir,
      sourceProject: json,
      artifacts: <ProjectCompatibilityArtifact>[
        ProjectCompatibilityArtifact(
          dependencyKey: dependency.key,
          fileName: fileName,
          fingerprint: ProjectCompatibilityService.artifactFingerprint(
            json,
            dependency,
          ),
          trackJson: <String, dynamic>{
            'fileName': fileName,
            'label': 'Frozen audio',
            'clipType': 'audio',
            'rowIndex': 0,
            'clipId': 'frozen-0',
          },
          replacementRows: const <int>[0],
        ),
      ],
    );

    final bundlePath = await ProjectBundle.exportMixroomBundle(
      projectDir: projectDir,
      audioMode: BundleAudioMode.preserveAsIs,
    );
    final importedDir = await ProjectBundleImport.importMixroomBundle(
      bundleFile: File(bundlePath),
      audioStrategy: ImportAudioStrategy.keepAsBundled,
    );
    expect(await ProjectCompatibilityService.isCurrent(importedDir), isTrue);
    final source = await ProjectManager.readProjectJson(importedDir);
    final opened = await ProjectCompatibilityService.resolveForOpen(
      projectDir: importedDir,
      sourceProject: source,
      canHostExternalPlugins: false,
      hasPlugin: (_) => false,
    );
    expect(opened.usingCompatibleAudio, isTrue);
  });
}
