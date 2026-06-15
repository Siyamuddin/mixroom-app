import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/tablet_daw_panel_layout.dart';

void main() {
  test('reserves no side panel width outside tablet DAW layout', () {
    expect(
      TabletDawPanelLayout.reservedWidth(
        usesTabletDawLayout: false,
        collapsed: false,
      ),
      0,
    );
  });

  test('reserves collapsed or expanded tablet DAW panel width', () {
    expect(TabletDawPanelLayout.collapsedWidth, 0);
    expect(
      TabletDawPanelLayout.reservedWidth(
        usesTabletDawLayout: true,
        collapsed: false,
      ),
      TabletDawPanelLayout.rightExpandedWidth,
    );
    expect(
      TabletDawPanelLayout.expandedLeftPanelWidth(),
      TabletDawPanelLayout.leftExpandedWidth,
    );
    expect(
      TabletDawPanelLayout.reservedWidth(
        usesTabletDawLayout: true,
        collapsed: true,
      ),
      TabletDawPanelLayout.collapsedWidth,
    );
  });

  test('scales expanded side panels for compact iPad landscape widths', () {
    expect(
      TabletDawPanelLayout.reservedWidth(
        usesTabletDawLayout: true,
        collapsed: false,
        availableWidth: 1024,
      ),
      closeTo(232.0, 0.001),
    );
    expect(
      TabletDawPanelLayout.expandedLeftPanelWidth(availableWidth: 1024),
      closeTo(272.0, 0.001),
    );
    expect(
      1024 -
          TabletDawPanelLayout.expandedLeftPanelWidth(availableWidth: 1024) -
          TabletDawPanelLayout.reservedWidth(
            usesTabletDawLayout: true,
            collapsed: false,
            availableWidth: 1024,
          ),
      greaterThanOrEqualTo(TabletDawPanelLayout.minTimelineWidth),
    );
  });

  test('preserves target side panels on wide tablet canvases', () {
    expect(
      TabletDawPanelLayout.reservedWidth(
        usesTabletDawLayout: true,
        collapsed: false,
        availableWidth: 1387,
      ),
      closeTo(TabletDawPanelLayout.rightExpandedWidth, 0.001),
    );
    expect(
      TabletDawPanelLayout.expandedLeftPanelWidth(availableWidth: 1387),
      closeTo(272.0, 0.001),
    );
  });

  test('uses full right panel width when iPad landscape has room', () {
    expect(
      TabletDawPanelLayout.reservedWidth(
        usesTabletDawLayout: true,
        collapsed: false,
        availableWidth: 1194,
      ),
      closeTo(TabletDawPanelLayout.rightExpandedWidth, 0.001),
    );
  });

  test('bounds user-resized right panel width', () {
    expect(
      TabletDawPanelLayout.boundedPreferredRightPanelWidth(120),
      TabletDawPanelLayout.minResizableRightPanelWidth,
    );
    expect(
      TabletDawPanelLayout.boundedPreferredRightPanelWidth(360),
      360,
    );
    expect(
      TabletDawPanelLayout.boundedPreferredRightPanelWidth(1100),
      TabletDawPanelLayout.maxResizableRightPanelWidth,
    );
  });

  test('lets user-resized right panel compress center workspace further', () {
    final defaultRightPanelWidth = TabletDawPanelLayout.reservedWidth(
      usesTabletDawLayout: true,
      collapsed: false,
      availableWidth: 1024,
    );
    final resizedRightPanelWidth = TabletDawPanelLayout.reservedWidth(
      usesTabletDawLayout: true,
      collapsed: false,
      availableWidth: 1024,
      preferredRightPanelWidth: 920,
    );
    final leftPanelWidth =
        TabletDawPanelLayout.expandedLeftPanelWidth(availableWidth: 1024);

    expect(defaultRightPanelWidth, closeTo(232.0, 0.001));
    expect(resizedRightPanelWidth, closeTo(352.0, 0.001));
    expect(
      1024 - leftPanelWidth - resizedRightPanelWidth,
      closeTo(TabletDawPanelLayout.minResizableTimelineWidth, 0.001),
    );
  });

  test('shrinks side panels before violating the minimum timeline width', () {
    final leftPanelWidth =
        TabletDawPanelLayout.expandedLeftPanelWidth(availableWidth: 800);
    final rightPanelWidth = TabletDawPanelLayout.reservedWidth(
      usesTabletDawLayout: true,
      collapsed: false,
      availableWidth: 800,
    );
    expect(leftPanelWidth, closeTo(140.0, 0.001));
    expect(rightPanelWidth, closeTo(140.0, 0.001));
    expect(800 - leftPanelWidth - rightPanelWidth, closeTo(520.0, 0.001));
  });

  test('keeps the tablet left rail width when the right rail can remain usable',
      () {
    final leftPanelWidth =
        TabletDawPanelLayout.expandedLeftPanelWidth(availableWidth: 950);
    final rightPanelWidth = TabletDawPanelLayout.reservedWidth(
      usesTabletDawLayout: true,
      collapsed: false,
      availableWidth: 950,
    );
    expect(leftPanelWidth, closeTo(272.0, 0.001));
    expect(
        rightPanelWidth,
        greaterThanOrEqualTo(
          TabletDawPanelLayout.minUsableRightPanelWidth,
        ));
  });

  test('keeps compact iPad top bar controls inside the center budget', () {
    const screenWidth = 1024.0;
    final leftPanelWidth = TabletDawPanelLayout.expandedLeftPanelWidth(
        availableWidth: screenWidth);
    final rightPanelWidth = TabletDawPanelLayout.reservedWidth(
      usesTabletDawLayout: true,
      collapsed: false,
      availableWidth: screenWidth,
    );
    final projectHeaderWidth = leftPanelWidth - 12.0;
    final centerWidth = TabletDawPanelLayout.topBarCenterAvailableWidth(
      screenWidth: screenWidth,
      topBarLeftPadding: 12.0,
      topBarRightPadding: 16.0,
      projectHeaderWidth: projectHeaderWidth,
      rightReservedWidth: rightPanelWidth,
    );
    final compact = TabletDawPanelLayout.usesCompactTopBar(centerWidth);
    final requiredWithAnalyzer = TabletDawPanelLayout.topBarCenterRequiredWidth(
      compactTablet: true,
      compact: compact,
      includeAnalyzer: true,
      includeControlPill: false,
    );
    expect(compact, isTrue);
    expect(centerWidth, greaterThanOrEqualTo(requiredWithAnalyzer));
  });

  test('keeps analyzer after moving tablet tool controls into the left rail',
      () {
    const screenWidth = 950.0;
    final leftPanelWidth = TabletDawPanelLayout.expandedLeftPanelWidth(
        availableWidth: screenWidth);
    final rightPanelWidth = TabletDawPanelLayout.reservedWidth(
      usesTabletDawLayout: true,
      collapsed: false,
      availableWidth: screenWidth,
    );
    final projectHeaderWidth = leftPanelWidth - 12.0;
    final centerWidth = TabletDawPanelLayout.topBarCenterAvailableWidth(
      screenWidth: screenWidth,
      topBarLeftPadding: 12.0,
      topBarRightPadding: 16.0,
      projectHeaderWidth: projectHeaderWidth,
      rightReservedWidth: rightPanelWidth,
    );
    final compact = TabletDawPanelLayout.usesCompactTopBar(centerWidth);
    final requiredWithAnalyzer = TabletDawPanelLayout.topBarCenterRequiredWidth(
      compactTablet: true,
      compact: compact,
      includeAnalyzer: true,
      includeControlPill: false,
    );
    final requiredWithoutAnalyzer =
        TabletDawPanelLayout.topBarCenterRequiredWidth(
      compactTablet: true,
      compact: compact,
      includeAnalyzer: false,
      includeControlPill: false,
    );
    expect(compact, isTrue);
    expect(centerWidth, greaterThanOrEqualTo(requiredWithAnalyzer));
    expect(centerWidth, greaterThanOrEqualTo(requiredWithoutAnalyzer));
  });

  test('allocates wider tool segment than quantize segment in top controls',
      () {
    for (final pillWidth in <double>[
      TabletDawPanelLayout.topBarCompactControlPillWidth,
      TabletDawPanelLayout.topBarRegularControlPillWidth,
    ]) {
      final magnetWidth = TabletDawPanelLayout.topControlMagnetWidth(pillWidth);
      final toolWidth = TabletDawPanelLayout.topControlToolWidth(pillWidth);
      final quantizeWidth =
          TabletDawPanelLayout.topControlQuantizeWidth(pillWidth);
      expect(toolWidth, greaterThan(quantizeWidth));
      if (pillWidth == TabletDawPanelLayout.topBarCompactControlPillWidth) {
        expect(quantizeWidth, greaterThanOrEqualTo(52.0));
      }
      expect(quantizeWidth, lessThan(magnetWidth + toolWidth));
      expect(
        magnetWidth + toolWidth + quantizeWidth + 2.0,
        closeTo(pillWidth, 0.001),
      );
    }
  });

  test('scales tablet bottom chat width toward the full Figma frame', () {
    expect(
      TabletDawPanelLayout.bottomTabletChatMaxWidthForScreen(850),
      closeTo(850 * TabletDawPanelLayout.bottomTabletChatWidthRatio, 0.001),
    );
    expect(
      TabletDawPanelLayout.bottomTabletChatMaxWidthForScreen(1024),
      closeTo(1024 * TabletDawPanelLayout.bottomTabletChatWidthRatio, 0.001),
    );
    expect(
      TabletDawPanelLayout.bottomTabletChatMaxWidthForScreen(1387),
      closeTo(TabletDawPanelLayout.bottomTabletChatMaxWidth, 0.001),
    );
    expect(
      TabletDawPanelLayout.bottomTabletChatMaxWidthForScreen(1600),
      closeTo(TabletDawPanelLayout.bottomTabletChatMaxWidth, 0.001),
    );
  });

  test('keeps right panel header controls inside default rail widths', () {
    final panelWidth = TabletDawPanelLayout.reservedWidth(
      usesTabletDawLayout: true,
      collapsed: false,
      availableWidth: 1024,
    );
    final compact =
        TabletDawPanelLayout.usesCompactRightPanelHeader(panelWidth);
    final selectorWidth = TabletDawPanelLayout.rightPanelHeaderSelectorWidth(
      panelWidth: panelWidth,
      compact: compact,
    );
    final requiredWidth = TabletDawPanelLayout.rightPanelHeaderRequiredWidth(
      compact: compact,
    );
    expect(compact, isFalse);
    expect(
      selectorWidth,
      greaterThanOrEqualTo(
        TabletDawPanelLayout.rightPanelHeaderMinSelectorWidth,
      ),
    );
    expect(panelWidth, greaterThanOrEqualTo(requiredWidth));
  });

  test('right panel header still fits at minimum usable rail width', () {
    const panelWidth = TabletDawPanelLayout.minUsableRightPanelWidth;
    final compact =
        TabletDawPanelLayout.usesCompactRightPanelHeader(panelWidth);
    final selectorWidth = TabletDawPanelLayout.rightPanelHeaderSelectorWidth(
      panelWidth: panelWidth,
      compact: compact,
    );
    final requiredWidth = TabletDawPanelLayout.rightPanelHeaderRequiredWidth(
      compact: compact,
    );
    expect(compact, isTrue);
    expect(
      selectorWidth,
      greaterThanOrEqualTo(
        TabletDawPanelLayout.rightPanelHeaderMinSelectorWidth,
      ),
    );
    expect(
      selectorWidth +
          TabletDawPanelLayout.rightPanelHeaderGap(compact: compact) +
          TabletDawPanelLayout.rightPanelHeaderExportButtonSize +
          (TabletDawPanelLayout.rightPanelHeaderHorizontalInset * 2.0),
      closeTo(panelWidth, 0.001),
    );
    expect(panelWidth, greaterThanOrEqualTo(requiredWidth));
  });
}
