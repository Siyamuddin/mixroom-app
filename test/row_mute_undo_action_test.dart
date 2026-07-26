import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';

void main() {
  test('row mute action applies, undoes, and redoes by stable row id',
      () async {
    final states = <int, bool>{42: false};
    final groups = <String, bool>{'group-a': false};
    final action = RowMuteUndoAction(
      rowId: 42,
      oldMuted: false,
      newMuted: true,
      groupId: 'group-a',
      oldGroupMuted: false,
      newGroupMuted: true,
      applyState: ({
        required rowId,
        required muted,
        required groupId,
        required groupMuted,
      }) async {
        if (!states.containsKey(rowId)) throw StateError('missing row');
        states[rowId] = muted;
        if (groupId.isNotEmpty && groupMuted != null) {
          groups[groupId] = groupMuted;
        }
      },
    );

    await action.redo();
    expect(states[42], isTrue);
    expect(groups['group-a'], isTrue);

    await action.undo();
    expect(states[42], isFalse);
    expect(groups['group-a'], isFalse);

    await action.redo();
    expect(states[42], isTrue);
    expect(groups['group-a'], isTrue);
  });

  test('row mute action does not fall back when its stable id is missing',
      () async {
    final action = RowMuteUndoAction(
      rowId: 42,
      oldMuted: false,
      newMuted: true,
      groupId: '',
      oldGroupMuted: null,
      newGroupMuted: null,
      applyState: ({
        required rowId,
        required muted,
        required groupId,
        required groupMuted,
      }) async {
        throw StateError('missing row $rowId');
      },
    );

    await expectLater(action.redo(), throwsStateError);
  });

  test('row solo action applies, undoes, and redoes by stable row id',
      () async {
    final states = <int, bool>{42: false};
    final groups = <String, bool>{'group-a': false};
    final action = RowSoloUndoAction(
      rowId: 42,
      oldSoloed: false,
      newSoloed: true,
      groupId: 'group-a',
      oldGroupSoloed: false,
      newGroupSoloed: true,
      applyState: ({
        required rowId,
        required soloed,
        required groupId,
        required groupSoloed,
      }) async {
        if (!states.containsKey(rowId)) throw StateError('missing row');
        states[rowId] = soloed;
        if (groupId.isNotEmpty && groupSoloed != null) {
          groups[groupId] = groupSoloed;
        }
      },
    );

    await action.redo();
    expect(states[42], isTrue);
    expect(groups['group-a'], isTrue);

    await action.undo();
    expect(states[42], isFalse);
    expect(groups['group-a'], isFalse);

    await action.redo();
    expect(states[42], isTrue);
    expect(groups['group-a'], isTrue);
  });

  test('row solo action does not fall back when its stable id is missing',
      () async {
    final action = RowSoloUndoAction(
      rowId: 42,
      oldSoloed: false,
      newSoloed: true,
      groupId: '',
      oldGroupSoloed: null,
      newGroupSoloed: null,
      applyState: ({
        required rowId,
        required soloed,
        required groupId,
        required groupSoloed,
      }) async {
        throw StateError('missing row $rowId');
      },
    );

    await expectLater(action.redo(), throwsStateError);
  });
}
