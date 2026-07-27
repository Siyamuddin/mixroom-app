import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';

void main() {
  test('row creation tracks runtime ids and restores selection', () async {
    var nextRowId = 100;
    final rows = <int>{10, 20};
    int? selection = 20;
    final action = RowCreateUndoAction(
      previousSelectedRowId: selection,
      createRow: (preferredRowId) async {
        final id = preferredRowId ?? nextRowId++;
        if (rows.contains(id)) throw StateError('collision');
        rows.add(id);
        return id;
      },
      deleteRow: (rowId) async {
        if (!rows.remove(rowId)) throw StateError('missing');
      },
      applySelection: (rowId) async => selection = rowId,
    );

    await action.redo();
    final firstId = action.currentRowId;
    expect(rows, contains(firstId));
    expect(selection, firstId);

    await action.undo();
    expect(rows, isNot(contains(firstId)));
    expect(selection, 20);

    await action.redo();
    expect(action.currentRowId, firstId);
    expect(rows, contains(action.currentRowId));
    expect(selection, action.currentRowId);
  });

  test('row creation rolls back if selection application fails', () async {
    final rows = <int>{10};
    final action = RowCreateUndoAction(
      previousSelectedRowId: 10,
      createRow: (_) async {
        rows.add(20);
        return 20;
      },
      deleteRow: (rowId) async {
        rows.remove(rowId);
      },
      applySelection: (_) async => throw StateError('selection failed'),
    );

    await expectLater(action.redo(), throwsStateError);
    expect(rows, <int>{10});
  });

  test('row creation rejects a retained identity collision', () async {
    final rows = <int>{10};
    final action = RowCreateUndoAction(
      previousSelectedRowId: 10,
      createRow: (preferredRowId) async {
        final id = preferredRowId ?? 20;
        if (rows.contains(id)) throw StateError('collision');
        rows.add(id);
        return id;
      },
      deleteRow: (rowId) async {
        if (!rows.remove(rowId)) throw StateError('missing');
      },
      applySelection: (_) async {},
    );

    await action.redo();
    await action.undo();
    rows.add(20);

    await expectLater(action.redo(), throwsStateError);
    expect(rows, <int>{10, 20});
  });
}
