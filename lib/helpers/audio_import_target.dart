enum AudioImportTargetKind { existingRow, createNewRow, atLimit }

class AudioImportTarget {
  const AudioImportTarget.existing(this.row)
    : kind = AudioImportTargetKind.existingRow,
      insertBelowRow = null;

  const AudioImportTarget.createNew({this.insertBelowRow})
    : kind = AudioImportTargetKind.createNewRow,
      row = null;

  const AudioImportTarget.atLimit()
    : kind = AudioImportTargetKind.atLimit,
      row = null,
      insertBelowRow = null;

  final AudioImportTargetKind kind;
  final int? row;
  final int? insertBelowRow;
}

/// Picks where the + button / file-browser insert should put an audio clip.
///
/// Order: selected empty audio row, else nearest empty audio row (visible
/// preferred over collapsed), else create a new row, else the track limit.
AudioImportTarget resolveAutoAudioImportTarget({
  required int selectedRow,
  required int rowCount,
  required int maxRows,
  required bool Function(int row) isAudioRow,
  required bool Function(int row) isOccupied,
  required bool Function(int row) isHiddenByCollapsedGroup,
}) {
  if (rowCount <= 0) {
    if (maxRows > 0) {
      return const AudioImportTarget.createNew();
    }
    return const AudioImportTarget.atLimit();
  }

  final safeSelected = selectedRow.clamp(0, rowCount - 1);

  bool isUsableEmptyAudio(int row, {required bool requireVisible}) {
    if (row < 0 || row >= rowCount) return false;
    if (!isAudioRow(row)) return false;
    if (isOccupied(row)) return false;
    if (requireVisible && isHiddenByCollapsedGroup(row)) return false;
    return true;
  }

  if (isUsableEmptyAudio(safeSelected, requireVisible: false)) {
    return AudioImportTarget.existing(safeSelected);
  }

  int? nearestEmpty({required bool requireVisible}) {
    for (int distance = 1; distance < rowCount; distance++) {
      final below = safeSelected + distance;
      if (isUsableEmptyAudio(below, requireVisible: requireVisible)) {
        return below;
      }
      final above = safeSelected - distance;
      if (isUsableEmptyAudio(above, requireVisible: requireVisible)) {
        return above;
      }
    }
    return null;
  }

  final visibleEmpty = nearestEmpty(requireVisible: true);
  if (visibleEmpty != null) {
    return AudioImportTarget.existing(visibleEmpty);
  }

  final anyEmpty = nearestEmpty(requireVisible: false);
  if (anyEmpty != null) {
    return AudioImportTarget.existing(anyEmpty);
  }

  if (rowCount < maxRows) {
    return AudioImportTarget.createNew(insertBelowRow: safeSelected);
  }
  return const AudioImportTarget.atLimit();
}
