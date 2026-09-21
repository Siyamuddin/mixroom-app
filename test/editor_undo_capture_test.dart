import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/screens/audio_editor.dart';

class _CountingUndoAction extends EditorUndoAction {
  _CountingUndoAction(this.description, this.applyDelta);

  @override
  final String description;
  final int applyDelta;
  int value = 0;
  int redoCount = 0;
  int undoCount = 0;
  bool failUndo = false;

  @override
  Future<void> redo() async {
    redoCount += 1;
    value += applyDelta;
  }

  @override
  Future<void> undo() async {
    undoCount += 1;
    if (failUndo) throw StateError('undo failed');
    value -= applyDelta;
  }
}

void main() {
  test(
    'capture owner can execute and capture actions in its async zone',
    () async {
      final manager = EditorUndoManager();
      final action = _CountingUndoAction('internal', 1);

      final captured = await manager.captureActions(() async {
        await Future<void>.delayed(Duration.zero);
        await manager.execute(action);
      });

      expect(captured, <EditorUndoAction>[action]);
      expect(action.value, 1);
      expect(action.redoCount, 1);
      expect(manager.canUndo, isFalse);
      expect(manager.isCapturingActions, isFalse);
    },
  );

  test(
    'external mutations are rejected before their action executes',
    () async {
      final manager = EditorUndoManager();
      final captureStarted = Completer<void>();
      final releaseCapture = Completer<void>();
      final external = _CountingUndoAction('external', 1);

      final capture = manager.captureActions(() async {
        captureStarted.complete();
        await releaseCapture.future;
      });
      await captureStarted.future;

      await expectLater(
        manager.execute(external),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'undo_action_capture_external_mutation',
          ),
        ),
      );
      await expectLater(
        manager.executeWithoutAdd(external),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        manager.addWithoutExecute(external),
        throwsA(isA<StateError>()),
      );
      expect(external.value, 0);
      expect(external.redoCount, 0);

      releaseCapture.complete();
      await capture;
    },
  );

  test(
    'undo and redo do not traverse history while capture is active',
    () async {
      final manager = EditorUndoManager();
      final action = _CountingUndoAction('history', 1);
      await manager.execute(action);
      expect(manager.canUndo, isTrue);

      final captureStarted = Completer<void>();
      final releaseCapture = Completer<void>();
      final capture = manager.captureActions(() async {
        captureStarted.complete();
        await releaseCapture.future;
      });
      await captureStarted.future;

      expect(manager.canUndo, isFalse);
      expect(await manager.undo(), isNull);
      await manager.undoSteps(1);
      expect(action.value, 1);
      expect(action.undoCount, 0);

      releaseCapture.complete();
      await capture;
      expect(manager.canUndo, isTrue);
      expect(await manager.undo(), same(action));
      expect(action.value, 0);

      final redoCaptureStarted = Completer<void>();
      final releaseRedoCapture = Completer<void>();
      final redoCapture = manager.captureActions(() async {
        redoCaptureStarted.complete();
        await releaseRedoCapture.future;
      });
      await redoCaptureStarted.future;

      expect(manager.canRedo, isFalse);
      expect(await manager.redo(), isNull);
      await manager.redoSteps(1);
      expect(action.value, 0);

      releaseRedoCapture.complete();
      await redoCapture;
      expect(manager.canRedo, isTrue);
      expect(await manager.redo(), same(action));
      expect(action.value, 1);
    },
  );

  test('failed capture rolls back and releases scoped ownership', () async {
    final manager = EditorUndoManager();
    final internal = _CountingUndoAction('internal', 2);

    await expectLater(
      manager.captureActions(() async {
        await manager.execute(internal);
        throw StateError('later failure');
      }),
      throwsA(isA<StateError>()),
    );

    expect(internal.value, 0);
    expect(internal.redoCount, 1);
    expect(internal.undoCount, 1);
    expect(manager.isCapturingActions, isFalse);

    final later = _CountingUndoAction('later', 3);
    await manager.execute(later);
    expect(later.value, 3);
    expect(manager.canUndo, isTrue);
  });

  test('captured row deletions commit as one compound undo step', () async {
    final manager = EditorUndoManager();
    final first = _CountingUndoAction('delete row 2', -1);
    final second = _CountingUndoAction('delete row 1', -1);

    final captured = await manager.captureActions(() async {
      await manager.execute(first);
      await manager.execute(second);
    });
    await manager.addWithoutExecute(
      CompoundUndoAction('Delete 2 rows', captured),
    );

    expect(first.value, -1);
    expect(second.value, -1);
    expect(manager.undoHistoryNewestFirst, hasLength(1));
    expect(manager.undoHistoryNewestFirst.single.description, 'Delete 2 rows');

    await manager.undo();
    expect(first.value, 0);
    expect(second.value, 0);
    expect(first.undoCount, 1);
    expect(second.undoCount, 1);

    await manager.redo();
    expect(first.value, -1);
    expect(second.value, -1);
    expect(first.redoCount, 2);
    expect(second.redoCount, 2);
  });

  test('failed audio add rolls back a clip installed before the error', () async {
    final manager = EditorUndoManager();
    final tracks = <AudioTrack>[];
    var removeCallbacks = 0;
    final action = AddAudioTrackAction(
      addTrack:
          ({
            required File file,
            required int row,
            required double timeMs,
            Duration? trimStartRequested,
            Duration? trimEndRequested,
          }) async {
            tracks.add(
              await _testAudioTrack(
                row: row,
                rowId: 42,
                clipId: 'partially-added-clip',
              ),
            );
            throw StateError('fade sync failed');
          },
      tracks: tracks,
      file: File('/tmp/kick.wav'),
      row: 1,
      timeMs: 1250,
      onRemove: (_) async {
        removeCallbacks += 1;
      },
    );

    await expectLater(
      manager.captureActions(() => manager.execute(action)),
      throwsA(isA<StateError>()),
    );

    expect(tracks, isEmpty);
    expect(removeCallbacks, 1);
    expect(manager.canUndo, isFalse);
    expect(manager.isCapturingActions, isFalse);
  });

  test('new-row audio insert is one identity-stable compound undo step', () async {
    final manager = EditorUndoManager();
    final rowIds = <int>[1];
    final tracks = <AudioTrack>[];
    int? selectedRowId = 1;

    final rowAction = RowCreateUndoAction(
      previousSelectedRowId: selectedRowId,
      initialRowId: null,
      createRow: (preferredRowId) async {
        final rowId = preferredRowId ?? 42;
        rowIds.add(rowId);
        return rowId;
      },
      deleteRow: (rowId) async {
        rowIds.remove(rowId);
      },
      applySelection: (rowId) async {
        selectedRowId = rowId;
      },
    );
    final clipAction = AddAudioTrackAction(
      addTrack:
          ({
            required File file,
            required int row,
            required double timeMs,
            Duration? trimStartRequested,
            Duration? trimEndRequested,
          }) async {
            tracks.add(
              await _testAudioTrack(
                row: row,
                rowId: 42,
                clipId: 'new-row-clip',
                offsetSeconds: timeMs / 1000,
              ),
            );
          },
      restoreTrack: (payload) async {
        tracks.add(
          await _testAudioTrack(
            row: 1,
            rowId: 42,
            clipId: payload['clipId'] as String,
            offsetSeconds: 1.25,
          ),
        );
      },
      tracks: tracks,
      file: File('/tmp/kick.wav'),
      row: 1,
      timeMs: 1250,
    );

    final captured = await manager.captureActions(() async {
      await manager.execute(rowAction);
      await manager.execute(clipAction);
    });
    await manager.addWithoutExecute(
      CompoundUndoAction('Add audio on new row', captured),
    );

    expect(rowIds, <int>[1, 42]);
    expect(selectedRowId, 42);
    expect(tracks, hasLength(1));
    expect(tracks.single.rowId, 42);
    expect(tracks.single.offset, 1.25);
    expect(manager.undoHistoryNewestFirst, hasLength(1));

    await manager.undo();
    expect(tracks, isEmpty);
    expect(rowIds, <int>[1]);
    expect(selectedRowId, 1);

    await manager.redo();
    expect(rowIds, <int>[1, 42]);
    expect(selectedRowId, 42);
    expect(tracks, hasLength(1));
    expect(tracks.single.rowId, 42);
    expect(tracks.single.clipId, 'new-row-clip');
  });

  test('atomic editor row creation removes native row after apply failure', () async {
    final nativeRows = <int>{1};
    final visibleRows = <int>[1];
    var reconciliations = 0;

    await expectLater(
      createEditorRowAtomically(
        createNativeRow: () async {
          nativeRows.add(42);
          return 42;
        },
        applyCreatedRow: (rowId) async {
          visibleRows.add(rowId);
          throw StateError('mute sync failed');
        },
        removeNativeRow: (rowId) async => nativeRows.remove(rowId),
        restorePreviousState: () async {
          visibleRows
            ..clear()
            ..add(1);
        },
        reconcileFromEngine: () async {
          reconciliations += 1;
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'mute sync failed',
        ),
      ),
    );

    expect(nativeRows, <int>{1});
    expect(visibleRows, <int>[1]);
    expect(reconciliations, 0);
  });

  test('failed native row rollback reconciles editor state', () async {
    final nativeRows = <int>{1, 42};
    var restored = false;
    var reconciliations = 0;

    await expectLater(
      createEditorRowAtomically(
        createNativeRow: () async => 42,
        applyCreatedRow: (_) async => throw StateError('apply failed'),
        removeNativeRow: (_) async => false,
        restorePreviousState: () async {
          restored = true;
        },
        reconcileFromEngine: () async {
          reconciliations += 1;
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message.toString(),
          'message',
          contains('row_create_rollback_failed'),
        ),
      ),
    );

    expect(nativeRows, <int>{1, 42});
    expect(restored, isFalse);
    expect(reconciliations, 1);
  });
}

Future<AudioTrack> _testAudioTrack({
  required int row,
  required int rowId,
  required String clipId,
  double offsetSeconds = 0,
}) {
  return AudioTrack.create(
    file: File('/tmp/kick.wav'),
    originalFile: File('/tmp/kick.wav'),
    audioDuration: const Duration(seconds: 1),
    trimStart: Duration.zero,
    trimEnd: const Duration(seconds: 1),
    offset: offsetSeconds,
    rowIndex: row,
    rowId: rowId,
    engineClipId: -1,
    clipId: clipId,
    label: 'kick',
  );
}
