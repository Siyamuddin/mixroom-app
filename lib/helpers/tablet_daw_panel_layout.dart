import 'dart:math' as math;

class TabletDawPanelLayout {
  static const double expandedWidth = 272.0;
  static const double leftExpandedWidth = 272.0;
  static const double rightExpandedWidth = 326.0;
  static const double collapsedWidth = 0.0;
  static const double minExpandedWidth = 156.0;
  static const double compactExpandedWidth = 156.0;
  static const double leftTargetWidthRatio = 272.0 / 1387.0;
  static const double rightTargetWidthRatio = 326.0 / 1387.0;
  static const double minTimelineWidth = 520.0;
  static const double minResizableTimelineWidth = 400.0;
  static const double minUsableRightPanelWidth = 156.0;
  static const double minResizableRightPanelWidth = 248.0;
  static const double maxResizableRightPanelWidth = 920.0;
  static const double topBarProjectGap = 10.0;
  static const double topBarTrailingGap = 6.4;
  static const double topBarCompactControlPillWidth = 212.0;
  static const double topBarRegularControlPillWidth = 256.0;
  static const double topBarCompactTempoPillWidth = 220.0;
  static const double topBarRegularTempoPillWidth = 292.0;
  static const double topBarCompactGap = 6.0;
  static const double topBarRegularGap = 12.0;
  static const double topBarCompactMinAnalyzerWidth = 24.0;
  static const double topBarRegularMinAnalyzerWidth = 72.0;
  static const double topBarTabletTopInset = 8.0;
  static const double topBarTabletBottomInset = 6.0;
  static const double tabletRulerHeight = 40.0;
  static const double topControlMagnetShare = 0.16;
  static const double topControlQuantizeShare = 0.34;
  static const double bottomTabletChatMinWidth = 150.0;
  static const double bottomTabletChatOpenMaxWidth = 591.0;
  static const double bottomTabletChatMaxWidth = 760.0;
  static const double bottomTabletChatWidthRatio = 0.58;
  static const double rightPanelHeaderTopInset = 12.0;
  static const double rightPanelHeaderBottomInset = 8.0;
  static const double rightPanelHeaderHorizontalInset = 10.0;
  static const double rightPanelHeaderRegularGap = 10.0;
  static const double rightPanelHeaderCompactGap = 6.0;
  static const double rightPanelHeaderExportButtonSize = 48.0;
  static const double rightPanelHeaderMinSelectorWidth = 82.0;
  static const double compactLeftPanelShare = 0.5;

  static double reservedWidth({
    required bool usesTabletDawLayout,
    required bool collapsed,
    double? availableWidth,
    double? preferredRightPanelWidth,
  }) {
    if (!usesTabletDawLayout) return 0.0;
    if (collapsed) return collapsedWidth;
    return expandedRightPanelWidth(
      availableWidth: availableWidth,
      preferredRightPanelWidth: preferredRightPanelWidth,
    );
  }

  static double expandedPanelWidth({
    double? availableWidth,
    double? preferredRightPanelWidth,
  }) {
    return expandedRightPanelWidth(
      availableWidth: availableWidth,
      preferredRightPanelWidth: preferredRightPanelWidth,
    );
  }

  static double expandedLeftPanelWidth({double? availableWidth}) {
    final width = availableWidth;
    if (width == null || !width.isFinite || width <= 0) {
      return leftExpandedWidth;
    }
    final sideBudget = math.max(0.0, width - minTimelineWidth);
    if (sideBudget >= leftExpandedWidth + minUsableRightPanelWidth) {
      return leftExpandedWidth;
    }
    return (sideBudget * compactLeftPanelShare)
        .clamp(0.0, leftExpandedWidth)
        .toDouble();
  }

  static double expandedRightPanelWidth({
    double? availableWidth,
    double? preferredRightPanelWidth,
  }) {
    final width = availableWidth;
    final hasUserPreferredWidth = preferredRightPanelWidth != null &&
        preferredRightPanelWidth.isFinite &&
        preferredRightPanelWidth > 0;
    final preferred = boundedPreferredRightPanelWidth(
      preferredRightPanelWidth,
    );
    if (width == null || !width.isFinite || width <= 0) {
      return preferred;
    }
    final timelineReserve =
        hasUserPreferredWidth ? minResizableTimelineWidth : minTimelineWidth;
    final sideBudget = math.max(0.0, width - timelineReserve);
    final leftWidth = expandedLeftPanelWidth(availableWidth: width);
    if (sideBudget >= leftWidth + preferred) {
      return preferred;
    }
    final desiredTotal = leftWidth + preferred;
    if (sideBudget >= desiredTotal) return preferred;
    return (sideBudget - leftWidth).clamp(0.0, preferred).toDouble();
  }

  static double boundedPreferredRightPanelWidth(double? width) {
    if (width == null || !width.isFinite || width <= 0) {
      return rightExpandedWidth;
    }
    return width
        .clamp(minResizableRightPanelWidth, maxResizableRightPanelWidth)
        .toDouble();
  }

  static bool usesCompactTopBar(double availableWidth) {
    return availableWidth.isFinite && availableWidth < 660.0;
  }

  static double topBarControlPillWidth({required bool compactTablet}) {
    return compactTablet
        ? topBarCompactControlPillWidth
        : topBarRegularControlPillWidth;
  }

  static double topBarTempoPillWidth({required bool compactTablet}) {
    return compactTablet
        ? topBarCompactTempoPillWidth
        : topBarRegularTempoPillWidth;
  }

  static double topBarGap({required bool compact}) {
    return compact ? topBarCompactGap : topBarRegularGap;
  }

  static double topBarMinAnalyzerWidth({required bool compact}) {
    return compact
        ? topBarCompactMinAnalyzerWidth
        : topBarRegularMinAnalyzerWidth;
  }

  static double topBarCenterAvailableWidth({
    required double screenWidth,
    required double topBarLeftPadding,
    required double topBarRightPadding,
    required double projectHeaderWidth,
    required double rightReservedWidth,
  }) {
    return (screenWidth -
            rightReservedWidth -
            topBarLeftPadding -
            topBarRightPadding -
            projectHeaderWidth -
            topBarProjectGap -
            topBarTrailingGap)
        .clamp(0.0, double.infinity)
        .toDouble();
  }

  static double topBarCenterRequiredWidth({
    required bool compactTablet,
    required bool compact,
    required bool includeAnalyzer,
    bool includeControlPill = true,
  }) {
    final gap = topBarGap(compact: compact);
    final controlWidth = includeControlPill
        ? topBarControlPillWidth(compactTablet: compactTablet) + gap
        : 0.0;
    return controlWidth +
        topBarTempoPillWidth(compactTablet: compactTablet) +
        (includeAnalyzer ? gap + topBarMinAnalyzerWidth(compact: compact) : 0);
  }

  static double topControlMagnetWidth(double pillWidth) {
    final segmentWidth = math.max(0.0, pillWidth - 2.0);
    return segmentWidth * topControlMagnetShare;
  }

  static double topControlQuantizeWidth(double pillWidth) {
    final segmentWidth = math.max(0.0, pillWidth - 2.0);
    return segmentWidth * topControlQuantizeShare;
  }

  static double topControlToolWidth(double pillWidth) {
    final segmentWidth = math.max(0.0, pillWidth - 2.0);
    return segmentWidth -
        topControlMagnetWidth(pillWidth) -
        topControlQuantizeWidth(pillWidth);
  }

  static double bottomTabletChatMaxWidthForScreen(double screenWidth) {
    if (!screenWidth.isFinite || screenWidth <= 0) {
      return bottomTabletChatMinWidth;
    }
    return (screenWidth * bottomTabletChatWidthRatio)
        .clamp(bottomTabletChatMinWidth, bottomTabletChatMaxWidth)
        .toDouble();
  }

  static bool usesCompactRightPanelHeader(double panelWidth) {
    return panelWidth.isFinite && panelWidth < 224.0;
  }

  static double rightPanelHeaderGap({required bool compact}) {
    return compact ? rightPanelHeaderCompactGap : rightPanelHeaderRegularGap;
  }

  static double rightPanelHeaderSelectorWidth({
    required double panelWidth,
    required bool compact,
  }) {
    return (panelWidth -
            (rightPanelHeaderHorizontalInset * 2.0) -
            rightPanelHeaderExportButtonSize -
            rightPanelHeaderGap(compact: compact))
        .clamp(rightPanelHeaderMinSelectorWidth, double.infinity)
        .toDouble();
  }

  static double rightPanelHeaderRequiredWidth({required bool compact}) {
    return rightPanelHeaderMinSelectorWidth +
        rightPanelHeaderGap(compact: compact) +
        rightPanelHeaderExportButtonSize +
        (rightPanelHeaderHorizontalInset * 2.0);
  }
}
