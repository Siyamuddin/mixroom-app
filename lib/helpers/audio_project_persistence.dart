import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum AudioProjectSaveMode {
  autosave,
  checkpoint,
}

enum AudioProjectLoadSource {
  primary,
  autosaveBackup,
  checkpointBackup,
}

class AudioProjectRecoverySnapshot {
  const AudioProjectRecoverySnapshot({
    required this.mode,
    required this.file,
    required this.modifiedAt,
  });

  final AudioProjectSaveMode mode;
  final File file;
  final DateTime modifiedAt;
}

class AudioProjectLoadResult {
  const AudioProjectLoadResult({
    required this.projectState,
    required this.source,
    required this.availableSnapshots,
    this.sourceFile,
    this.warningMessage,
  });

  final Map<String, dynamic> projectState;
  final AudioProjectLoadSource source;
  final List<AudioProjectRecoverySnapshot> availableSnapshots;
  final File? sourceFile;
  final String? warningMessage;

  bool get usedRecoveryBackup => source != AudioProjectLoadSource.primary;
}

abstract class AudioProjectPersistence {
  Future<AudioProjectLoadResult> loadProjectState(Directory projectDir);

  Future<void> saveProjectState({
    required Directory projectDir,
    required Map<String, dynamic> projectState,
    required AudioProjectSaveMode mode,
  });
}

class JsonAudioProjectPersistence implements AudioProjectPersistence {
  static const String _recoveryDirName = '.mixroom_recovery';
  static const int _autosaveHistoryLimit = 8;
  static const int _checkpointHistoryLimit = 6;

  @override
  Future<AudioProjectLoadResult> loadProjectState(Directory projectDir) async {
    final primaryFile = File(p.join(projectDir.path, 'project.json'));
    final snapshots = await _listRecoverySnapshots(projectDir);

    try {
      final decoded = await _readProjectFile(primaryFile);
      return AudioProjectLoadResult(
        projectState: decoded,
        source: AudioProjectLoadSource.primary,
        sourceFile: primaryFile,
        availableSnapshots: snapshots,
      );
    } catch (primaryError) {
      for (final fallback in snapshots) {
        try {
          final decoded = await _readProjectFile(fallback.file);
          return AudioProjectLoadResult(
            projectState: decoded,
            source: fallback.mode == AudioProjectSaveMode.autosave
                ? AudioProjectLoadSource.autosaveBackup
                : AudioProjectLoadSource.checkpointBackup,
            sourceFile: fallback.file,
            availableSnapshots: snapshots,
            warningMessage:
                'Recovered project from ${fallback.mode.name} backup after the primary project file could not be read.',
          );
        } catch (_) {
          continue;
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> saveProjectState({
    required Directory projectDir,
    required Map<String, dynamic> projectState,
    required AudioProjectSaveMode mode,
  }) async {
    final target = File(p.join(projectDir.path, 'project.json'));
    final temp = File('${target.path}.tmp');
    final encoded = await compute<Map<String, dynamic>, String>(
      _encodeProjectState,
      Map<String, dynamic>.from(projectState),
      debugLabel: switch (mode) {
        AudioProjectSaveMode.autosave => 'project-autosave-json-encode',
        AudioProjectSaveMode.checkpoint => 'project-checkpoint-json-encode',
      },
    );

    await temp.writeAsString(encoded, flush: true);
    try {
      await temp.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(target.path);
    }
    await _writeRecoverySnapshot(
      projectDir: projectDir,
      encodedProjectState: encoded,
      mode: mode,
    );
  }

  Future<Map<String, dynamic>> _readProjectFile(File file) async {
    final encoded = await file.readAsString();
    return compute<String, Map<String, dynamic>>(
      _decodeProjectState,
      encoded,
      debugLabel: 'project-json-decode',
    );
  }

  Directory _recoveryDir(
    Directory projectDir,
    AudioProjectSaveMode mode,
  ) {
    return Directory(
      p.join(projectDir.path, _recoveryDirName, mode.name),
    );
  }

  Future<List<AudioProjectRecoverySnapshot>> _listRecoverySnapshots(
    Directory projectDir,
  ) async {
    final snapshots = <AudioProjectRecoverySnapshot>[];
    for (final mode in AudioProjectSaveMode.values) {
      final dir = _recoveryDir(projectDir, mode);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
          continue;
        }
        final stat = await entity.stat();
        snapshots.add(
          AudioProjectRecoverySnapshot(
            mode: mode,
            file: entity,
            modifiedAt: stat.modified,
          ),
        );
      }
    }
    snapshots.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return snapshots;
  }

  Future<void> _writeRecoverySnapshot({
    required Directory projectDir,
    required String encodedProjectState,
    required AudioProjectSaveMode mode,
  }) async {
    final dir = _recoveryDir(projectDir, mode);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(
      p.join(
        dir.path,
        '${DateTime.now().millisecondsSinceEpoch}_${mode.name}.json',
      ),
    );
    await file.writeAsString(encodedProjectState, flush: true);
    await _trimRecoverySnapshots(projectDir, mode);
  }

  Future<void> _trimRecoverySnapshots(
    Directory projectDir,
    AudioProjectSaveMode mode,
  ) async {
    final dir = _recoveryDir(projectDir, mode);
    if (!await dir.exists()) return;
    final files = await dir
        .list(followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort(
      (a, b) => b.path.toLowerCase().compareTo(a.path.toLowerCase()),
    );
    final maxCount = switch (mode) {
      AudioProjectSaveMode.autosave => _autosaveHistoryLimit,
      AudioProjectSaveMode.checkpoint => _checkpointHistoryLimit,
    };
    for (var i = maxCount; i < files.length; i++) {
      try {
        await files[i].delete();
      } catch (_) {}
    }
  }
}

class AutosaveCoordinator {
  final Future<void> Function() performSave;
  final void Function(Object error, StackTrace stackTrace)? onError;

  Timer? _timer;
  bool _dirty = false;
  bool _inFlight = false;
  Completer<void>? _activeSaveCompleter;

  AutosaveCoordinator({
    required this.performSave,
    this.onError,
  });

  bool get isDirty => _dirty;
  bool get isInFlight => _inFlight;

  void markDirty() {
    _dirty = true;
  }

  void clearDirty() {
    _dirty = false;
    _timer?.cancel();
    _timer = null;
  }

  void schedule({
    Duration debounce = const Duration(seconds: 1),
  }) {
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;

    while (true) {
      if (_inFlight) {
        final activeSaveCompleter = _activeSaveCompleter;
        if (activeSaveCompleter != null) {
          await activeSaveCompleter.future;
          continue;
        }
      }

      if (!_dirty) {
        return;
      }

      _dirty = false;
      _inFlight = true;
      final saveCompleter = Completer<void>();
      _activeSaveCompleter = saveCompleter;
      try {
        await performSave();
      } catch (error, stackTrace) {
        _dirty = true;
        onError?.call(error, stackTrace);
        return;
      } finally {
        _inFlight = false;
        final activeSaveCompleter = _activeSaveCompleter;
        _activeSaveCompleter = null;
        activeSaveCompleter?.complete();
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

String _encodeProjectState(Map<String, dynamic> projectState) {
  return jsonEncode(projectState);
}

Map<String, dynamic> _decodeProjectState(String encoded) {
  final decoded = jsonDecode(encoded);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Project state must decode to a JSON object.');
  }
  return decoded;
}
