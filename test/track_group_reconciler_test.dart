import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/track_group_reconciler.dart';
import 'package:mixroom/models/models.dart';

void main() {
  group('reconcileTrackGroupsForRows', () {
    test('derives group row ids from row group membership in visual order', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 91, name: 'Bass', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 42, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 7, name: 'Vox', iconId: 0),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[42, 91, 999],
          collapsed: true,
          color: 0xFF79A8FF,
        ),
      ];

      final reconciled = reconcileTrackGroupsForRows(
        rows: rows,
        groups: groups,
      );

      expect(reconciled.groups, hasLength(1));
      expect(reconciled.groups.single.rowIds, <int>[91, 42]);
      expect(reconciled.groups.single.collapsed, isTrue);
      expect(reconciled.groups.single.color, 0xFF79A8FF);
      expect(reconciled.rows.map((row) => row.groupId), <String>[
        'band',
        'band',
        '',
      ]);
    });

    test('drops groups with fewer than two live row members', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Track 1', iconId: 0, groupId: 'dead'),
        TimelineRow(rowId: 2, name: 'Track 2', iconId: 0, groupId: 'solo'),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'dead',
          name: 'Dead Group',
          rowIds: <int>[99],
          collapsed: true,
        ),
        const TrackGroup(
          id: 'solo',
          name: 'Solo Group',
          rowIds: <int>[2],
          collapsed: true,
        ),
      ];

      final reconciled = reconcileTrackGroupsForRows(
        rows: rows,
        groups: groups,
      );

      expect(reconciled.groups, isEmpty);
      expect(reconciled.rows.map((row) => row.groupId), <String>['', '']);
    });

    test('clears row group id when its group record is missing or singleton',
        () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Track 1', iconId: 0, groupId: 'missing'),
        TimelineRow(rowId: 2, name: 'Track 2', iconId: 0, groupId: 'live'),
        TimelineRow(rowId: 3, name: 'Track 3', iconId: 0, groupId: 'live'),
        TimelineRow(rowId: 4, name: 'Track 4', iconId: 0, groupId: 'solo'),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'live',
          name: 'Live Group',
          rowIds: <int>[2, 3],
        ),
        const TrackGroup(
          id: 'solo',
          name: 'Solo Group',
          rowIds: <int>[4],
        ),
      ];

      final reconciled = reconcileTrackGroupsForRows(
        rows: rows,
        groups: groups,
      );

      expect(reconciled.groups.single.rowIds, <int>[2, 3]);
      expect(reconciled.rows[0].groupId, isEmpty);
      expect(reconciled.rows[1].groupId, 'live');
      expect(reconciled.rows[2].groupId, 'live');
      expect(reconciled.rows[3].groupId, isEmpty);
    });
  });

  group('buildTimelineRowVisibilityMap', () {
    test('keeps every row visible for open groups', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 3, name: 'Vox', iconId: 0),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[1, 2],
        ),
      ];

      final visibility = buildTimelineRowVisibilityMap(
        rows: rows,
        groups: groups,
      );

      expect(visibility.visibleRowCount, 3);
      expect(
        visibility.entries.map((entry) => entry.sourceIndex),
        <int>[0, 1, 2],
      );
      expect(visibility.visibleIndexForSourceIndex(1), 1);
      expect(visibility.sourceIndexForVisibleIndex(2), 2);
      expect(visibility.entries[0].isGroupCollapsed, isFalse);
    });

    test('collapses grouped child rows behind the first group row', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 10, name: 'Intro', iconId: 0),
        TimelineRow(rowId: 11, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 12, name: 'Bass', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 13, name: 'Keys', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 14, name: 'Vox', iconId: 0),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[11, 12, 13],
          collapsed: true,
        ),
      ];

      final visibility = buildTimelineRowVisibilityMap(
        rows: rows,
        groups: groups,
      );

      expect(visibility.visibleRowCount, 3);
      expect(
        visibility.entries.map((entry) => entry.sourceIndex),
        <int>[0, 1, 4],
      );
      expect(visibility.visibleIndexForSourceIndex(0), 0);
      expect(visibility.visibleIndexForSourceIndex(1), 1);
      expect(visibility.visibleIndexForSourceIndex(2), isNull);
      expect(visibility.visibleIndexForSourceIndex(3), isNull);
      expect(visibility.visibleIndexForSourceIndex(4), 2);
      expect(visibility.sourceIndexForVisibleIndex(1), 1);
      expect(visibility.entries[1].isGroupFirstRow, isTrue);
      expect(visibility.entries[1].isGroupCollapsed, isTrue);
      expect(visibility.entries[1].hiddenCollapsedSourceRows, <int>[2, 3]);
    });

    test('ignores missing group records instead of hiding rows', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Track 1', iconId: 0, groupId: 'missing'),
        TimelineRow(rowId: 2, name: 'Track 2', iconId: 0, groupId: 'missing'),
      ];

      final visibility = buildTimelineRowVisibilityMap(
        rows: rows,
        groups: const <TrackGroup>[],
      );

      expect(visibility.visibleRowCount, 2);
      expect(
        visibility.entries.map((entry) => entry.sourceIndex),
        <int>[0, 1],
      );
      expect(
          visibility.entries.any((entry) => entry.isGroupCollapsed), isFalse);
    });
  });

  group('resolveTrackGroupControlRowIndices', () {
    test('returns every grouped source row for the first visible group row',
        () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 3, name: 'Vox', iconId: 0),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[1, 2],
          collapsed: true,
        ),
      ];

      expect(
        resolveTrackGroupControlRowIndices(
          rows: rows,
          groups: groups,
          sourceIndex: 0,
        ),
        <int>[0, 1],
      );
    });

    test('returns grouped rows for the first row of an open group', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 3, name: 'Vox', iconId: 0),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[1, 2],
          collapsed: false,
        ),
      ];

      expect(
        resolveTrackGroupControlRowIndices(
          rows: rows,
          groups: groups,
          sourceIndex: 0,
        ),
        <int>[0, 1],
      );
    });

    test('keeps non-first open group rows scoped to themselves', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[1, 2],
          collapsed: false,
        ),
      ];

      expect(
        resolveTrackGroupControlRowIndices(
          rows: rows,
          groups: groups,
          sourceIndex: 1,
        ),
        <int>[1],
      );
    });

    test('returns no control rows for a hidden collapsed child row', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[1, 2],
          collapsed: true,
        ),
      ];

      expect(
        resolveTrackGroupControlRowIndices(
          rows: rows,
          groups: groups,
          sourceIndex: 1,
        ),
        isEmpty,
      );
    });

    test('returns only the source row for ungrouped controls', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 3, name: 'Vox', iconId: 0),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[1, 2],
          collapsed: true,
        ),
      ];

      expect(
        resolveTrackGroupControlRowIndices(
          rows: rows,
          groups: groups,
          sourceIndex: 2,
        ),
        <int>[2],
      );
    });
  });

  group('reorderRowsMovingGroupLeadAsUnit', () {
    test('moves a collapsed group lead down with its hidden children', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 3, name: 'Keys', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 4, name: 'Vox', iconId: 0),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[1, 2, 3],
          collapsed: true,
        ),
      ];

      final reordered = reorderRowsMovingGroupLeadAsUnit(
        rows: rows,
        groups: groups,
        fromIndex: 0,
        toIndex: 1,
      );

      expect(reordered.map((row) => row.rowId), <int>[4, 1, 2, 3]);
    });

    test('moves a group lead up with its children', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Vox', iconId: 0),
        TimelineRow(rowId: 2, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 3, name: 'Bass', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 4, name: 'Keys', iconId: 0, groupId: 'band'),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[2, 3, 4],
          collapsed: false,
        ),
      ];

      final reordered = reorderRowsMovingGroupLeadAsUnit(
        rows: rows,
        groups: groups,
        fromIndex: 1,
        toIndex: 0,
      );

      expect(reordered.map((row) => row.rowId), <int>[2, 3, 4, 1]);
    });

    test('drops an outside row after a target group instead of inside it', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Vox', iconId: 0),
        TimelineRow(rowId: 2, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 3, name: 'Bass', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 4, name: 'Keys', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 5, name: 'Lead', iconId: 0),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[2, 3, 4],
        ),
      ];

      final reordered = reorderRowsMovingGroupLeadAsUnit(
        rows: rows,
        groups: groups,
        fromIndex: 0,
        toIndex: 2,
      );

      expect(reordered.map((row) => row.rowId), <int>[2, 3, 4, 1, 5]);
    });

    test('drops an outside row before a target group instead of inside it', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 3, name: 'Keys', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 4, name: 'Vox', iconId: 0),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[1, 2, 3],
        ),
      ];

      final reordered = reorderRowsMovingGroupLeadAsUnit(
        rows: rows,
        groups: groups,
        fromIndex: 3,
        toIndex: 1,
      );

      expect(reordered.map((row) => row.rowId), <int>[4, 1, 2, 3]);
    });

    test('does not drag a child row out from under its group header', () {
      final rows = <TimelineRow>[
        TimelineRow(rowId: 1, name: 'Drums', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 2, name: 'Bass', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 3, name: 'Keys', iconId: 0, groupId: 'band'),
        TimelineRow(rowId: 4, name: 'Vox', iconId: 0),
      ];
      final groups = <TrackGroup>[
        const TrackGroup(
          id: 'band',
          name: 'Band',
          rowIds: <int>[1, 2, 3],
        ),
      ];

      final reordered = reorderRowsMovingGroupLeadAsUnit(
        rows: rows,
        groups: groups,
        fromIndex: 1,
        toIndex: 3,
      );

      expect(reordered.map((row) => row.rowId), <int>[1, 2, 3, 4]);
    });
  });
}
