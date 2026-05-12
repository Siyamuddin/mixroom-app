import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_undo_history_store.dart';

ProjectUndoSnapshotRecord _record(int index) {
  return ProjectUndoSnapshotRecord(
    id: 'record_$index',
    description: 'Edit $index',
    timestampMs: 1000 + index,
    before: <String, dynamic>{
      'tempoBpm': 120 + index,
      'tracks': <Object?>[],
    },
    after: <String, dynamic>{
      'tempoBpm': 121 + index,
      'tracks': <Object?>[],
    },
    command: index.isEven
        ? <String, dynamic>{
            'type': 'clipGain',
            'clipIndex': index,
            'oldGain': 1.0,
            'newGain': 1.2,
          }
        : null,
  );
}

void main() {
  test('saves, loads, and trims persisted undo history', () async {
    final root = await Directory.systemTemp.createTemp('mixroom_undo_history_');
    try {
      final projectDir = Directory('${root.path}/project')
        ..createSync(recursive: true);
      const store = ProjectUndoHistoryStore();
      final records = List<ProjectUndoSnapshotRecord>.generate(
        5,
        (index) => _record(index),
      );

      await store.save(
        projectDir: projectDir,
        undo: records,
        redo: records.reversed.toList(growable: false),
        maxEntries: 3,
      );

      final loaded = await store.load(projectDir);
      expect(loaded.undo.map((record) => record.id), <String>[
        'record_2',
        'record_3',
        'record_4',
      ]);
      expect(loaded.redo.map((record) => record.id), <String>[
        'record_2',
        'record_1',
        'record_0',
      ]);
      expect(loaded.undo.last.after['tempoBpm'], 125);
      expect(loaded.undo.first.command?['type'], 'clipGain');
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test('loads empty history when no manifest exists', () async {
    final root = await Directory.systemTemp.createTemp('mixroom_undo_empty_');
    try {
      const store = ProjectUndoHistoryStore();
      final loaded = await store.load(root);
      expect(loaded.undo, isEmpty);
      expect(loaded.redo, isEmpty);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test('encodes and decodes project json undo history payloads', () {
    final records = List<ProjectUndoSnapshotRecord>.generate(
      4,
      (index) => _record(index),
    );

    final payload = ProjectUndoHistorySnapshot(
      undo: records,
      redo: records.reversed.toList(growable: false),
    ).toJson(maxEntries: 2);

    final decoded = ProjectUndoHistorySnapshot.fromJsonValue(payload);
    expect(decoded.undo.map((record) => record.id), <String>[
      'record_2',
      'record_3',
    ]);
    expect(decoded.redo.map((record) => record.id), <String>[
      'record_1',
      'record_0',
    ]);
  });
}
