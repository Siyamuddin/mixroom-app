import 'package:mixroom/models/models.dart';

class ReconciledTrackGroups {
  final List<TimelineRow> rows;
  final List<TrackGroup> groups;

  const ReconciledTrackGroups({
    required this.rows,
    required this.groups,
  });
}

class TimelineRowVisibilityEntry {
  final int visibleIndex;
  final int sourceIndex;
  final int rowId;
  final String groupId;
  final bool isGroupFirstRow;
  final bool isGroupCollapsed;
  final List<int> hiddenCollapsedSourceRows;

  const TimelineRowVisibilityEntry({
    required this.visibleIndex,
    required this.sourceIndex,
    required this.rowId,
    required this.groupId,
    this.isGroupFirstRow = false,
    this.isGroupCollapsed = false,
    this.hiddenCollapsedSourceRows = const <int>[],
  });
}

class TimelineRowVisibilityMap {
  final List<TimelineRowVisibilityEntry> entries;
  final Map<int, int> visibleIndexBySourceIndex;
  final Map<int, int> sourceIndexByVisibleIndex;

  const TimelineRowVisibilityMap({
    required this.entries,
    required this.visibleIndexBySourceIndex,
    required this.sourceIndexByVisibleIndex,
  });

  int get visibleRowCount => entries.length;

  int? visibleIndexForSourceIndex(int sourceIndex) {
    return visibleIndexBySourceIndex[sourceIndex];
  }

  int? sourceIndexForVisibleIndex(int visibleIndex) {
    return sourceIndexByVisibleIndex[visibleIndex];
  }
}

TimelineRow cloneTimelineRowForGroupReconcile(TimelineRow row) {
  return TimelineRow(
    rowId: row.rowId,
    name: row.name,
    iconId: row.iconId,
    kind: row.kind,
    instrumentId: row.instrumentId,
    instrumentName: row.instrumentName,
    instrumentParams: Map<String, double>.from(row.instrumentParams),
    hostedInstrumentStateBase64: row.hostedInstrumentStateBase64,
    roleOverride: row.roleOverride,
    groupId: row.groupId,
    color: row.color,
    inputDeviceName: row.inputDeviceName,
    inputChannelStart: row.inputChannelStart,
    inputChannelCount: row.inputChannelCount,
  );
}

TrackGroup cloneTrackGroupForGroupReconcile(TrackGroup group) {
  return TrackGroup(
    id: group.id,
    name: group.name,
    color: group.color,
    rowIds: List<int>.from(group.rowIds),
    gain: group.gain,
    pan: group.pan,
    muted: group.muted,
    soloed: group.soloed,
    collapsed: group.collapsed,
    effects: group.effects,
  );
}

ReconciledTrackGroups reconcileTrackGroupsForRows({
  required List<TimelineRow> rows,
  required List<TrackGroup> groups,
}) {
  final liveRowIds =
      rows.map((row) => row.rowId).where((rowId) => rowId >= 0).toSet();
  if (liveRowIds.isEmpty) {
    return ReconciledTrackGroups(
      rows: rows.map(cloneTimelineRowForGroupReconcile).toList(growable: false),
      groups: const <TrackGroup>[],
    );
  }

  final requestedMembership = <String, List<int>>{};
  for (final row in rows) {
    final groupId = row.groupId.trim();
    if (groupId.isEmpty || row.rowId < 0) continue;
    requestedMembership.putIfAbsent(groupId, () => <int>[]).add(row.rowId);
  }

  final nextGroups = <TrackGroup>[];
  final validGroupIds = <String>{};
  for (final group in groups) {
    final groupId = group.id.trim();
    if (groupId.isEmpty) continue;
    final rowIds = List<int>.from(
      requestedMembership[groupId] ?? const <int>[],
      growable: false,
    );
    if (rowIds.length < 2) continue;
    validGroupIds.add(groupId);
    nextGroups.add(
      TrackGroup(
        id: group.id,
        name: group.name,
        color: group.color,
        rowIds: rowIds,
        gain: group.gain,
        pan: group.pan,
        muted: group.muted,
        soloed: group.soloed,
        collapsed: group.collapsed,
        effects: group.effects,
      ),
    );
  }

  final nextRows = rows.map((row) {
    final groupId = row.groupId.trim();
    if (groupId.isEmpty) return cloneTimelineRowForGroupReconcile(row);
    if (!validGroupIds.contains(groupId)) {
      return row.copyWith(groupId: '');
    }
    return cloneTimelineRowForGroupReconcile(row);
  }).toList(growable: false);

  return ReconciledTrackGroups(rows: nextRows, groups: nextGroups);
}

TimelineRowVisibilityMap buildTimelineRowVisibilityMap({
  required List<TimelineRow> rows,
  required List<TrackGroup> groups,
}) {
  final groupById = <String, TrackGroup>{
    for (final group in groups)
      if (group.id.trim().isNotEmpty) group.id.trim(): group,
  };
  final firstSourceIndexByGroupId = <String, int>{};
  for (int i = 0; i < rows.length; i++) {
    final groupId = rows[i].groupId.trim();
    if (groupId.isEmpty || !groupById.containsKey(groupId)) continue;
    firstSourceIndexByGroupId.putIfAbsent(groupId, () => i);
  }

  final entries = <TimelineRowVisibilityEntry>[];
  final visibleBySource = <int, int>{};
  final sourceByVisible = <int, int>{};
  final hiddenSourceRowsByGroupId = <String, List<int>>{};

  for (int sourceIndex = 0; sourceIndex < rows.length; sourceIndex++) {
    final row = rows[sourceIndex];
    final groupId = row.groupId.trim();
    final group = groupById[groupId];
    final isGrouped = groupId.isNotEmpty && group != null;
    final isFirstRow =
        isGrouped && firstSourceIndexByGroupId[groupId] == sourceIndex;
    final isCollapsed = isGrouped && group.collapsed;

    if (isCollapsed && !isFirstRow) {
      hiddenSourceRowsByGroupId
          .putIfAbsent(groupId, () => <int>[])
          .add(sourceIndex);
      continue;
    }

    final visibleIndex = entries.length;
    visibleBySource[sourceIndex] = visibleIndex;
    sourceByVisible[visibleIndex] = sourceIndex;
    entries.add(
      TimelineRowVisibilityEntry(
        visibleIndex: visibleIndex,
        sourceIndex: sourceIndex,
        rowId: row.rowId,
        groupId: groupId,
        isGroupFirstRow: isFirstRow,
        isGroupCollapsed: isCollapsed,
      ),
    );
  }

  if (hiddenSourceRowsByGroupId.isEmpty) {
    return TimelineRowVisibilityMap(
      entries: entries,
      visibleIndexBySourceIndex: visibleBySource,
      sourceIndexByVisibleIndex: sourceByVisible,
    );
  }

  final entriesWithHiddenRows = entries.map((entry) {
    if (!entry.isGroupFirstRow || !entry.isGroupCollapsed) return entry;
    return TimelineRowVisibilityEntry(
      visibleIndex: entry.visibleIndex,
      sourceIndex: entry.sourceIndex,
      rowId: entry.rowId,
      groupId: entry.groupId,
      isGroupFirstRow: entry.isGroupFirstRow,
      isGroupCollapsed: entry.isGroupCollapsed,
      hiddenCollapsedSourceRows: List<int>.from(
        hiddenSourceRowsByGroupId[entry.groupId] ?? const <int>[],
      ),
    );
  }).toList(growable: false);

  return TimelineRowVisibilityMap(
    entries: entriesWithHiddenRows,
    visibleIndexBySourceIndex: visibleBySource,
    sourceIndexByVisibleIndex: sourceByVisible,
  );
}

List<int> resolveTrackGroupControlRowIndices({
  required List<TimelineRow> rows,
  required List<TrackGroup> groups,
  required int sourceIndex,
}) {
  if (sourceIndex < 0 || sourceIndex >= rows.length) return const <int>[];
  final visibility = buildTimelineRowVisibilityMap(rows: rows, groups: groups);
  final visibleIndex = visibility.visibleIndexForSourceIndex(sourceIndex);
  if (visibleIndex == null) return const <int>[];
  final entry = visibility.entries[visibleIndex];
  if (!entry.isGroupFirstRow || entry.groupId.trim().isEmpty) {
    return <int>[sourceIndex];
  }

  TrackGroup? group;
  for (final item in groups) {
    if (item.id == entry.groupId) {
      group = item;
      break;
    }
  }
  if (group == null) return <int>[sourceIndex];

  final rowIds = group.rowIds.toSet();
  final groupId = group.id.trim();
  final resolved = <int>[];
  for (int row = 0; row < rows.length; row++) {
    final item = rows[row];
    if (rowIds.contains(item.rowId) ||
        (groupId.isNotEmpty && item.groupId == groupId)) {
      resolved.add(row);
    }
  }
  return resolved.isEmpty ? <int>[sourceIndex] : resolved;
}

List<TimelineRow> reorderRowsMovingGroupLeadAsUnit({
  required List<TimelineRow> rows,
  required List<TrackGroup> groups,
  required int fromIndex,
  required int toIndex,
}) {
  final clonedRows =
      rows.map(cloneTimelineRowForGroupReconcile).toList(growable: false);
  if (fromIndex < 0 ||
      fromIndex >= rows.length ||
      toIndex < 0 ||
      toIndex >= rows.length ||
      fromIndex == toIndex) {
    return clonedRows;
  }

  ({int start, int end})? groupBlockForIndex(int index) {
    if (index < 0 || index >= rows.length) return null;
    final groupId = rows[index].groupId.trim();
    if (groupId.isEmpty) return null;
    TrackGroup? group;
    for (final item in groups) {
      if (item.id == groupId) {
        group = item;
        break;
      }
    }
    if (group == null) return null;
    final memberRowIds = group.rowIds.toSet();
    final memberIndices = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.groupId.trim() == groupId || memberRowIds.contains(row.rowId)) {
        memberIndices.add(i);
      }
    }
    if (memberIndices.isEmpty) return null;
    memberIndices.sort();
    return (start: memberIndices.first, end: memberIndices.last);
  }

  final resolvedGroupRows = resolveTrackGroupControlRowIndices(
    rows: rows,
    groups: groups,
    sourceIndex: fromIndex,
  )..sort();
  final movingRows =
      resolvedGroupRows.length > 1 && resolvedGroupRows.first == fromIndex
          ? resolvedGroupRows
          : <int>[fromIndex];
  final movingRowSet = movingRows.toSet();
  final sourceBlock = groupBlockForIndex(fromIndex);
  if (sourceBlock != null &&
      sourceBlock.start != fromIndex &&
      (toIndex < sourceBlock.start || toIndex > sourceBlock.end)) {
    return clonedRows;
  }

  var effectiveToIndex = toIndex;
  final targetBlock = groupBlockForIndex(toIndex);
  if (targetBlock != null &&
      !movingRowSet.contains(targetBlock.start) &&
      !movingRowSet.contains(targetBlock.end)) {
    effectiveToIndex =
        toIndex > fromIndex ? targetBlock.end : targetBlock.start;
  }

  int insertionIndexBeforeRemoval;
  if (effectiveToIndex > fromIndex) {
    var anchorIndex = effectiveToIndex;
    if (movingRowSet.contains(anchorIndex)) {
      anchorIndex = movingRows.last + 1;
    }
    if (anchorIndex >= rows.length) return clonedRows;
    insertionIndexBeforeRemoval = anchorIndex + 1;
  } else {
    var anchorIndex = effectiveToIndex;
    if (movingRowSet.contains(anchorIndex)) {
      anchorIndex = movingRows.first - 1;
    }
    if (anchorIndex < 0) return clonedRows;
    insertionIndexBeforeRemoval = anchorIndex;
  }

  final moving =
      movingRows.map((index) => cloneTimelineRowForGroupReconcile(rows[index]));
  final remaining = <TimelineRow>[];
  for (var index = 0; index < rows.length; index++) {
    if (movingRowSet.contains(index)) continue;
    remaining.add(cloneTimelineRowForGroupReconcile(rows[index]));
  }

  final removedBeforeInsertion =
      movingRows.where((index) => index < insertionIndexBeforeRemoval).length;
  final adjustedInsertionIndex =
      (insertionIndexBeforeRemoval - removedBeforeInsertion)
          .clamp(0, remaining.length)
          .toInt();
  remaining.insertAll(adjustedInsertionIndex, moving);
  return remaining;
}
