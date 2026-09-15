import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class ProjectUndoSnapshotRecord {
  const ProjectUndoSnapshotRecord({
    required this.id,
    required this.description,
    required this.timestampMs,
    required this.before,
    required this.after,
    this.command,
  });

  final String id;
  final String description;
  final int timestampMs;
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;
  final Map<String, dynamic>? command;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'description': description,
    'timestampMs': timestampMs,
    'before': before,
    'after': after,
    if (command != null) 'command': command,
  };

  factory ProjectUndoSnapshotRecord.fromJson(Map<String, dynamic> json) {
    return ProjectUndoSnapshotRecord(
      id: (json['id'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      timestampMs:
          (json['timestampMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      before: ((json['before'] as Map?) ?? const <String, dynamic>{})
          .cast<String, dynamic>(),
      after: ((json['after'] as Map?) ?? const <String, dynamic>{})
          .cast<String, dynamic>(),
      command: (json['command'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

class ProjectUndoHistorySnapshot {
  const ProjectUndoHistorySnapshot({required this.undo, required this.redo});

  final List<ProjectUndoSnapshotRecord> undo;
  final List<ProjectUndoSnapshotRecord> redo;

  bool get isEmpty => undo.isEmpty && redo.isEmpty;

  Map<String, dynamic> toJson({
    int maxEntries = ProjectUndoHistoryStore.defaultMaxEntries,
  }) {
    return <String, dynamic>{
      'schemaVersion': 1,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'undo': ProjectUndoHistoryStore.tailRecords(
        undo,
        maxEntries,
      ).map((record) => record.toJson()).toList(),
      'redo': ProjectUndoHistoryStore.tailRecords(
        redo,
        maxEntries,
      ).map((record) => record.toJson()).toList(),
    };
  }

  factory ProjectUndoHistorySnapshot.fromJsonValue(Object? value) {
    if (value is! Map) {
      return const ProjectUndoHistorySnapshot(
        undo: <ProjectUndoSnapshotRecord>[],
        redo: <ProjectUndoSnapshotRecord>[],
      );
    }
    final json = value.cast<String, dynamic>();
    return ProjectUndoHistorySnapshot(
      undo: ProjectUndoHistoryStore.decodeRecords(json['undo']),
      redo: ProjectUndoHistoryStore.decodeRecords(json['redo']),
    );
  }
}

class ProjectUndoHistoryStore {
  static const int defaultMaxEntries = 30;
  static const String _dirName = '.mixroom_undo';
  static const String _manifestName = 'history.json';

  const ProjectUndoHistoryStore();

  Future<ProjectUndoHistorySnapshot> load(Directory projectDir) async {
    final file = _manifestFile(projectDir);
    if (!await file.exists()) {
      return const ProjectUndoHistorySnapshot(
        undo: <ProjectUndoSnapshotRecord>[],
        redo: <ProjectUndoSnapshotRecord>[],
      );
    }
    final decoded = await compute<String, Object?>(
      jsonDecode,
      await file.readAsString(),
      debugLabel: 'project-undo-history-json-decode',
    );
    if (decoded is! Map) {
      return const ProjectUndoHistorySnapshot(
        undo: <ProjectUndoSnapshotRecord>[],
        redo: <ProjectUndoSnapshotRecord>[],
      );
    }
    return ProjectUndoHistorySnapshot.fromJsonValue(decoded);
  }

  Future<void> save({
    required Directory projectDir,
    required List<ProjectUndoSnapshotRecord> undo,
    required List<ProjectUndoSnapshotRecord> redo,
    int maxEntries = defaultMaxEntries,
  }) async {
    final dir = _historyDir(projectDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final payload = ProjectUndoHistorySnapshot(
      undo: undo,
      redo: redo,
    ).toJson(maxEntries: maxEntries);
    final encoded = await compute<Object?, String>(
      jsonEncode,
      payload,
      debugLabel: 'project-undo-history-json-encode',
    );
    await _manifestFile(projectDir).writeAsString(encoded);
  }

  static List<ProjectUndoSnapshotRecord> decodeRecords(Object? raw) {
    final list = raw is List ? raw : const <Object?>[];
    final output = <ProjectUndoSnapshotRecord>[];
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        output.add(ProjectUndoSnapshotRecord.fromJson(item));
      } else if (item is Map) {
        output.add(
          ProjectUndoSnapshotRecord.fromJson(item.cast<String, dynamic>()),
        );
      }
    }
    return output;
  }

  static List<ProjectUndoSnapshotRecord> tailRecords(
    List<ProjectUndoSnapshotRecord> records,
    int maxEntries,
  ) {
    if (records.length <= maxEntries) return List.of(records);
    return records.sublist(records.length - maxEntries);
  }

  /// Folder that holds the persisted undo history of [projectDir].
  static Directory directoryFor(Directory projectDir) {
    return Directory(p.join(projectDir.path, _dirName));
  }

  Directory _historyDir(Directory projectDir) => directoryFor(projectDir);

  File _manifestFile(Directory projectDir) {
    return File(p.join(_historyDir(projectDir).path, _manifestName));
  }
}
