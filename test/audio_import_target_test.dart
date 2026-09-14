import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/audio_import_target.dart';

AudioImportTarget _resolve({
  required int selectedRow,
  required int rowCount,
  required int? creationLimit,
  Set<int> audioRows = const <int>{},
  Set<int> occupiedRows = const <int>{},
  Set<int> hiddenRows = const <int>{},
}) {
  return resolveAutoAudioImportTarget(
    selectedRow: selectedRow,
    rowCount: rowCount,
    creationLimit: creationLimit,
    isAudioRow: audioRows.contains,
    isOccupied: occupiedRows.contains,
    isHiddenByCollapsedGroup: hiddenRows.contains,
  );
}

void main() {
  test('selected empty audio row wins', () {
    final target = _resolve(
      selectedRow: 1,
      rowCount: 3,
      creationLimit: 8,
      audioRows: const <int>{0, 1, 2},
    );

    expect(target.kind, AudioImportTargetKind.existingRow);
    expect(target.row, 1);
  });

  test('selected MIDI row uses nearest empty audio row', () {
    final target = _resolve(
      selectedRow: 1,
      rowCount: 3,
      creationLimit: 8,
      audioRows: const <int>{0, 2},
      occupiedRows: const <int>{0},
    );

    expect(target.kind, AudioImportTargetKind.existingRow);
    expect(target.row, 2);
  });

  test('selected occupied audio row uses nearest empty audio row', () {
    final target = _resolve(
      selectedRow: 0,
      rowCount: 3,
      creationLimit: 8,
      audioRows: const <int>{0, 1, 2},
      occupiedRows: const <int>{0},
    );

    expect(target.kind, AudioImportTargetKind.existingRow);
    expect(target.row, 1);
  });

  test('new empty track below a piano track is chosen', () {
    final target = _resolve(
      selectedRow: 1,
      rowCount: 3,
      creationLimit: 8,
      audioRows: const <int>{0, 2},
    );

    expect(target.kind, AudioImportTargetKind.existingRow);
    expect(target.row, 2);
  });

  test('no empty audio under the limit creates a new row', () {
    final target = _resolve(
      selectedRow: 0,
      rowCount: 2,
      creationLimit: 5,
      audioRows: const <int>{0},
      occupiedRows: const <int>{0},
    );

    expect(target.kind, AudioImportTargetKind.createNewRow);
    expect(target.insertBelowRow, 0);
  });

  test('no empty audio at max rows is atLimit', () {
    final target = _resolve(
      selectedRow: 1,
      rowCount: 5,
      creationLimit: 5,
      audioRows: const <int>{0, 2, 4},
      occupiedRows: const <int>{0, 2, 4},
    );

    expect(target.kind, AudioImportTargetKind.atLimit);
    expect(target.row, isNull);
  });

  test('visible empty row beats a closer collapsed empty row', () {
    final target = _resolve(
      selectedRow: 0,
      rowCount: 4,
      creationLimit: 8,
      audioRows: const <int>{0, 1, 3},
      occupiedRows: const <int>{0},
      hiddenRows: const <int>{1},
    );

    expect(target.kind, AudioImportTargetKind.existingRow);
    expect(target.row, 3);
  });

  test('collapsed empty row is used when it is the only empty audio row', () {
    final target = _resolve(
      selectedRow: 0,
      rowCount: 3,
      creationLimit: 8,
      audioRows: const <int>{0, 2},
      occupiedRows: const <int>{0},
      hiddenRows: const <int>{2},
    );

    expect(target.kind, AudioImportTargetKind.existingRow);
    expect(target.row, 2);
  });

  test('empty project under the limit creates a new row', () {
    final target = _resolve(selectedRow: 0, rowCount: 0, creationLimit: 5);

    expect(target.kind, AudioImportTargetKind.createNewRow);
    expect(target.insertBelowRow, isNull);
  });

  test('equal distance prefers the empty audio row below', () {
    final target = _resolve(
      selectedRow: 1,
      rowCount: 3,
      creationLimit: 8,
      audioRows: const <int>{0, 2},
    );

    expect(target.kind, AudioImportTargetKind.existingRow);
    expect(target.row, 2);
  });

  test('selected empty audio row is used even if it is collapsed', () {
    final target = _resolve(
      selectedRow: 1,
      rowCount: 3,
      creationLimit: 8,
      audioRows: const <int>{0, 1, 2},
      occupiedRows: const <int>{0, 2},
      hiddenRows: const <int>{1},
    );

    expect(target.kind, AudioImportTargetKind.existingRow);
    expect(target.row, 1);
  });

  test('paid projects can create a row without a product-defined limit', () {
    final target = _resolve(
      selectedRow: 199,
      rowCount: 200,
      creationLimit: null,
      audioRows: Set<int>.from(List<int>.generate(200, (index) => index)),
      occupiedRows: Set<int>.from(List<int>.generate(200, (index) => index)),
    );

    expect(target.kind, AudioImportTargetKind.createNewRow);
    expect(target.insertBelowRow, 199);
  });
}
