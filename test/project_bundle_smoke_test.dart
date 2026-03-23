import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _ffmpegMethodChannel = MethodChannel('flutter.arthenica.com/ffmpeg_kit');
const _ffmpegEventMethodChannel =
    MethodChannel('flutter.arthenica.com/ffmpeg_kit_event');

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

class _FakeFfmpegKit {
  _FakeFfmpegKit(this._binaryMessenger);

  final TestDefaultBinaryMessenger _binaryMessenger;
  final Map<int, List<String>> _sessionArgs = <int, List<String>>{};
  final List<List<String>> executedCommands = <List<String>>[];
  int _nextSessionId = 1;

  void install() {
    _binaryMessenger.setMockMethodCallHandler(
      _ffmpegMethodChannel,
      _handleMethodCall,
    );
    _binaryMessenger.setMockMethodCallHandler(
      _ffmpegEventMethodChannel,
      _handleEventCall,
    );
  }

  void uninstall() {
    _binaryMessenger.setMockMethodCallHandler(_ffmpegMethodChannel, null);
    _binaryMessenger.setMockMethodCallHandler(_ffmpegEventMethodChannel, null);
  }

  Future<Object?> _handleEventCall(MethodCall call) async {
    if (call.method == 'listen' || call.method == 'cancel') {
      return null;
    }
    throw MissingPluginException(
        'Unhandled ffmpeg event method ${call.method}');
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'getLogLevel':
        return 0;
      case 'getPlatform':
        return 'test';
      case 'getArch':
        return 'x86_64';
      case 'getPackageName':
        return 'mock-package';
      case 'enableRedirection':
        return null;
      case 'isLTSBuild':
        return false;
      case 'setLogLevel':
        return null;
      case 'ffmpegSession':
        final args =
            ((call.arguments as Map)['arguments'] as List).cast<String>();
        final sessionId = _nextSessionId++;
        _sessionArgs[sessionId] = List<String>.from(args);
        return <String, Object>{
          'sessionId': sessionId,
          'createTime': DateTime.now().millisecondsSinceEpoch,
          'startTime': DateTime.now().millisecondsSinceEpoch,
          'command': args.join(' '),
        };
      case 'ffmpegSessionExecute':
        final sessionId = (call.arguments as Map)['sessionId'] as int;
        final args = _sessionArgs[sessionId];
        if (args == null) {
          throw StateError('Missing mock ffmpeg session $sessionId');
        }
        executedCommands.add(List<String>.from(args));
        await _executeFfmpegCommand(args);
        return null;
    }

    throw MissingPluginException('Unhandled ffmpeg method ${call.method}');
  }

  Future<void> _executeFfmpegCommand(List<String> args) async {
    final inputFlagIndex = args.indexOf('-i');
    if (inputFlagIndex < 0 || inputFlagIndex + 1 >= args.length) {
      throw StateError('Mock ffmpeg command missing input: $args');
    }
    final inputPath = args[inputFlagIndex + 1];
    final outputPath = args.last;
    await File(outputPath).parent.create(recursive: true);
    await File(inputPath).copy(outputPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform originalPathProvider;
  late Directory sandboxRoot;
  late Directory tempDir;
  late Directory docsDir;
  late _FakeFfmpegKit fakeFfmpegKit;

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
    fakeFfmpegKit = _FakeFfmpegKit(
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

  test('project bundle export/import preserves bundled audio and track mapping',
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

    final importedAudio =
        File(p.join(ProjectManager.audioDir(importedDir).path, 'tone.wav'));
    expect(await importedAudio.exists(), isTrue);
    expect(await importedAudio.readAsBytes(), sourceBytes);

    final reparsed = jsonDecode(
            await File(p.join(importedDir.path, 'project.json')).readAsString())
        as Map<String, dynamic>;
    expect(
      ((reparsed['tracks'] as List).first as Map)['fileName'],
      'tone.wav',
    );
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

    final importedAudio =
        File(p.join(ProjectManager.audioDir(importedDir).path, 'tone.wav'));
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
  });
}
