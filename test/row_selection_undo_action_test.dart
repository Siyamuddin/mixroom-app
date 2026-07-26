import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';

void main() {
  test('row selection action applies, undoes, and redoes stable row ids',
      () async {
    int? selectedRowId = 10;
    final applied = <int?>[];
    final action = RowSelectionUndoAction(
      previousRowId: 10,
      finalRowId: 20,
      applySelection: (rowId) async {
        selectedRowId = rowId;
        applied.add(rowId);
      },
    );

    await action.redo();
    expect(selectedRowId, 20);
    await action.undo();
    expect(selectedRowId, 10);
    await action.redo();
    expect(selectedRowId, 20);
    expect(applied, <int?>[20, 10, 20]);
  });

  test('row role override action applies, undoes, and redoes by stable row id',
      () async {
    final roles = <int, String>{10: 'vocals'};
    final action = RowRoleOverrideUndoAction(
      rowId: 10,
      oldRole: 'vocals',
      newRole: 'drums',
      applyRole: ({required rowId, required role}) async {
        if (!roles.containsKey(rowId)) throw StateError('missing row');
        roles[rowId] = role;
      },
    );

    await action.redo();
    expect(roles[10], 'drums');
    await action.undo();
    expect(roles[10], 'vocals');
    await action.redo();
    expect(roles[10], 'drums');
  });

  test('row role override action does not fall back from a missing stable id',
      () async {
    final action = RowRoleOverrideUndoAction(
      rowId: 10,
      oldRole: '',
      newRole: 'bass',
      applyRole: ({required rowId, required role}) async {
        throw StateError('missing row $rowId');
      },
    );

    await expectLater(action.redo(), throwsStateError);
  });
}
