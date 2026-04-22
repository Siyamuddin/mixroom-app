import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/audio_project_persistence.dart';

void main() {
  group('JsonAudioProjectPersistence', () {
    late Directory sandbox;
    late Directory projectDir;
    late JsonAudioProjectPersistence persistence;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp(
        'mixroom_audio_project_persistence_test_',
      );
      projectDir = Directory('${sandbox.path}/Project')
        ..createSync(recursive: true);
      persistence = JsonAudioProjectPersistence();
    });

    tearDown(() async {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    test('writes and loads project state through project.json', () async {
      await persistence.saveProjectState(
        projectDir: projectDir,
        projectState: <String, dynamic>{
          'name': 'First Save',
          'tracks': <Map<String, dynamic>>[],
        },
        mode: AudioProjectSaveMode.autosave,
      );

      await persistence.saveProjectState(
        projectDir: projectDir,
        projectState: <String, dynamic>{
          'name': 'Second Save',
          'tracks': <Map<String, dynamic>>[
            <String, dynamic>{'fileName': 'tone.wav'},
          ],
        },
        mode: AudioProjectSaveMode.checkpoint,
      );

      final loaded = await persistence.loadProjectState(projectDir);
      expect(loaded['name'], 'Second Save');
      expect((loaded['tracks'] as List), hasLength(1));

      final rawFile = File('${projectDir.path}/project.json');
      expect(await rawFile.exists(), isTrue);
      final decoded =
          jsonDecode(await rawFile.readAsString()) as Map<String, dynamic>;
      expect(decoded['name'], 'Second Save');
    });
  });

  group('AutosaveCoordinator', () {
    test('coalesces overlapping saves', () async {
      final firstSaveCompleter = Completer<void>();
      var saveCount = 0;

      final coordinator = AutosaveCoordinator(
        performSave: () async {
          saveCount += 1;
          if (saveCount == 1) {
            await firstSaveCompleter.future;
          }
        },
      );

      coordinator.schedule(debounce: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      coordinator.schedule(debounce: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      firstSaveCompleter.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(saveCount, 2);
      coordinator.dispose();
    });

    test('flush waits for an in-flight save to finish', () async {
      final firstSaveCompleter = Completer<void>();
      var saveCount = 0;

      final coordinator = AutosaveCoordinator(
        performSave: () async {
          saveCount += 1;
          if (saveCount == 1) {
            await firstSaveCompleter.future;
          }
        },
      );

      coordinator.schedule(debounce: Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final flushFuture = coordinator.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(saveCount, 1);

      firstSaveCompleter.complete();
      await flushFuture;

      expect(saveCount, 1);
      coordinator.dispose();
    });
  });
}
