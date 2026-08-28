import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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

  test(
    'undoCurrentRecordId undoes only the matching current AI apply',
    () async {
      final manager = EditorUndoManager();
      final first = _CountingUndoAction('first', 1);
      final second = _CountingUndoAction('second', 2);
      await manager.addWithoutExecute(
        CompoundUndoAction('AI changes', <EditorUndoAction>[first]),
      );
      final firstId = manager.lastUndoRecord!.id;
      await manager.addWithoutExecute(
        CompoundUndoAction('AI changes', <EditorUndoAction>[second]),
      );
      final secondId = manager.lastUndoRecord!.id;

      expect(firstId, isNot(secondId));
      expect(manager.isCurrentUndoRecordId(firstId), isFalse);
      expect(manager.isCurrentUndoRecordId(secondId), isTrue);
      expect(await manager.undoCurrentRecordId(firstId), isNull);
      expect(first.undoCount, 0);
      expect(second.undoCount, 0);

      expect(await manager.undoCurrentRecordId(secondId), isNotNull);
      expect(second.undoCount, 1);
      expect(first.undoCount, 0);
      expect(manager.isCurrentUndoRecordId(secondId), isFalse);
      expect(manager.isCurrentUndoRecordId(firstId), isTrue);
    },
  );

  test(
    'undoCurrentRecordId ignores blank and unknown record ids',
    () async {
      final manager = EditorUndoManager();
      final action = _CountingUndoAction('only', 1);
      await manager.addWithoutExecute(
        CompoundUndoAction('AI changes', <EditorUndoAction>[action]),
      );

      expect(manager.isCurrentUndoRecordId(''), isFalse);
      expect(manager.isCurrentUndoRecordId('missing'), isFalse);
      expect(await manager.undoCurrentRecordId('missing'), isNull);
      expect(action.undoCount, 0);
      expect(manager.canUndo, isTrue);
    },
  );
}
