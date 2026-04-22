import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'project_manager.dart';

enum AudioProjectSaveMode {
  autosave,
  checkpoint,
}

abstract class AudioProjectPersistence {
  Future<Map<String, dynamic>> loadProjectState(Directory projectDir);

  Future<void> saveProjectState({
    required Directory projectDir,
    required Map<String, dynamic> projectState,
    required AudioProjectSaveMode mode,
  });
}

class JsonAudioProjectPersistence implements AudioProjectPersistence {
  @override
  Future<Map<String, dynamic>> loadProjectState(Directory projectDir) {
    return ProjectManager.readProjectJson(projectDir);
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
      return;
    } on FileSystemException {
      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(target.path);
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
