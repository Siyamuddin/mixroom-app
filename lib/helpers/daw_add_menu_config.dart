class DawAddMenuActionConfig {
  const DawAddMenuActionConfig({
    required this.id,
    required this.title,
    this.subtitle,
    this.showSelectedCount = false,
  });

  final String id;
  final String title;
  final String? subtitle;
  final bool showSelectedCount;
}

const double kDawTabletAddMenuWidth = 230.0;

double resolveDawAddMenuWidth({
  required bool usesTabletAddMenu,
  required double defaultWidth,
  required double availableWidth,
}) {
  final desiredWidth =
      usesTabletAddMenu ? kDawTabletAddMenuWidth : defaultWidth;
  return desiredWidth.clamp(0.0, availableWidth).toDouble();
}

List<DawAddMenuActionConfig> buildDawAddMenuActions({
  required bool usesTabletAddMenu,
  required int selectedGroupRowCount,
  required bool rowGroupingSelectionMode,
}) {
  final actions = <DawAddMenuActionConfig>[
    DawAddMenuActionConfig(
      id: usesTabletAddMenu ? 'audio' : 'audio_row',
      title: usesTabletAddMenu ? 'Add Audio Clip' : '+ Audio Row',
    ),
    DawAddMenuActionConfig(
      id: 'instrument',
      title: usesTabletAddMenu ? 'Add Instrument Lane' : '+ MIDI Row',
    ),
  ];

  if (!usesTabletAddMenu) {
    final canGroupRows = selectedGroupRowCount >= 2;
    actions.add(
      DawAddMenuActionConfig(
        id: 'group_rows',
        title: canGroupRows ? 'Group Rows' : 'Select & Group Rows',
        subtitle: canGroupRows
            ? 'Apply changes and effects together'
            : rowGroupingSelectionMode
                ? 'Tap row headers to select rows'
                : 'Choose rows to group',
        showSelectedCount: selectedGroupRowCount > 0,
      ),
    );
  }

  actions.add(
    const DawAddMenuActionConfig(
      id: 'sample_browser',
      title: 'Open File Browser',
      subtitle: 'Audition folders and drag and drop',
    ),
  );

  return actions;
}
