import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/daw_add_menu_config.dart';

void main() {
  test('tablet add menu matches Figma add-elements actions', () {
    final actions = buildDawAddMenuActions(
      usesTabletAddMenu: true,
      selectedGroupRowCount: 3,
      rowGroupingSelectionMode: true,
    );

    expect(
      actions.map((action) => '${action.id}:${action.title}').toList(),
      <String>[
        'audio:Add Audio Clip',
        'instrument:Add Instrument Lane',
        'sample_browser:Open File Browser',
      ],
    );
    expect(actions.any((action) => action.id == 'group_rows'), isFalse);
  });

  test('tablet add menu uses compact Figma width', () {
    expect(
      resolveDawAddMenuWidth(
        usesTabletAddMenu: true,
        defaultWidth: 288,
        availableWidth: 1000,
      ),
      kDawTabletAddMenuWidth,
    );
  });

  test('non-tablet add menu keeps default width', () {
    expect(
      resolveDawAddMenuWidth(
        usesTabletAddMenu: false,
        defaultWidth: 288,
        availableWidth: 1000,
      ),
      288,
    );
  });

  test('add menu width respects available space', () {
    expect(
      resolveDawAddMenuWidth(
        usesTabletAddMenu: true,
        defaultWidth: 288,
        availableWidth: 180,
      ),
      180,
    );
  });

  test('non-tablet add menu preserves row and grouping actions', () {
    final actions = buildDawAddMenuActions(
      usesTabletAddMenu: false,
      selectedGroupRowCount: 2,
      rowGroupingSelectionMode: false,
    );

    expect(
      actions.map((action) => '${action.id}:${action.title}').toList(),
      <String>[
        'audio_row:+ Audio Row',
        'instrument:+ MIDI Row',
        'group_rows:Group 2 Rows',
        'sample_browser:Open File Browser',
      ],
    );
    final groupAction =
        actions.singleWhere((action) => action.id == 'group_rows');
    expect(groupAction.subtitle, 'Apply changes and effects together');
    expect(groupAction.showSelectedCount, isTrue);
  });

  test('non-tablet grouping prompt reflects row selection mode', () {
    final actions = buildDawAddMenuActions(
      usesTabletAddMenu: false,
      selectedGroupRowCount: 1,
      rowGroupingSelectionMode: true,
    );

    final groupAction =
        actions.singleWhere((action) => action.id == 'group_rows');
    expect(groupAction.title, 'Select & Group Rows');
    expect(groupAction.subtitle, 'Tap row headers to select rows');
    expect(groupAction.showSelectedCount, isTrue);
  });
}
