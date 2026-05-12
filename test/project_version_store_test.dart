import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/helpers/project_version_store.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform originalPathProvider;
  late Directory sandboxRoot;
  late Directory tempDir;
  late Directory docsDir;

  setUp(() async {
    originalPathProvider = PathProviderPlatform.instance;
    sandboxRoot = await Directory.systemTemp.createTemp(
      'mixroom_project_versions_',
    );
    tempDir = Directory(p.join(sandboxRoot.path, 'tmp'))
      ..createSync(recursive: true);
    docsDir = Directory(p.join(sandboxRoot.path, 'docs'))
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      temporaryPath: tempDir.path,
      applicationDocumentsPath: docsDir.path,
    );
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPathProvider;
    if (await sandboxRoot.exists()) {
      await sandboxRoot.delete(recursive: true);
    }
  });

  test(
      'creates deduped lightweight snapshots and restores as a new project copy',
      () async {
    const store = ProjectVersionStore();
    final projectDir = await ProjectManager.createNewProjectDir(
      name: 'Versioned Song',
    );
    final initialJson = await ProjectManager.readProjectJson(projectDir);
    final originalProjectId = initialJson['projectId'];
    final audioDir = ProjectManager.audioDir(projectDir);
    await File(p.join(audioDir.path, 'tone.wav')).writeAsBytes(
      List<int>.filled(128, 1),
      flush: true,
    );
    initialJson['tracks'] = [
      {
        'fileName': 'tone.wav',
        'label': 'Tone',
      }
    ];
    await ProjectManager.writeProjectJson(projectDir, initialJson);

    final first = await store.maybeCreateSnapshot(
      projectDir: projectDir,
      reason: ProjectVersionReason.autosave,
      minInterval: Duration.zero,
    );
    expect(first, isNotNull);
    expect(first!.sizeBytes, greaterThan(0));
    expect(first.snapshotFileName.endsWith('.json'), isTrue);
    expect(
      await File(
        p.join(projectDir.path, '.mixroom_versions', 'bundles',
            '${first.id}.mixroom'),
      ).exists(),
      isFalse,
    );

    final duplicate = await store.maybeCreateSnapshot(
      projectDir: projectDir,
      reason: ProjectVersionReason.autosave,
      minInterval: Duration.zero,
    );
    expect(duplicate, isNull);

    final changedJson = await ProjectManager.readProjectJson(projectDir);
    changedJson['tempoBpm'] = 132;
    await ProjectManager.writeProjectJson(projectDir, changedJson);
    final second = await store.maybeCreateSnapshot(
      projectDir: projectDir,
      reason: ProjectVersionReason.manualSave,
      minInterval: Duration.zero,
      maxEntries: 1,
    );
    expect(second, isNotNull);

    final entries = await store.listVersions(projectDir);
    expect(entries, hasLength(1));
    expect(entries.single.id, second!.id);

    final restoredDir = await store.restoreVersionAsCopy(
      projectDir: projectDir,
      versionId: second.id,
    );
    expect(restoredDir.path, isNot(projectDir.path));

    final restoredJson = await ProjectManager.readProjectJson(restoredDir);
    expect(restoredJson['projectId'], isNot(originalProjectId));
    expect((restoredJson['name'] as String), contains('Restored'));
    expect(restoredJson['tempoBpm'], 132);
    expect(
      await File(p.join(ProjectManager.audioDir(restoredDir).path, 'tone.wav'))
          .exists(),
      isTrue,
    );
  });
}
