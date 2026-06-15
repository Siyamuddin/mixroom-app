import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const double kTabletShortestSideBreakpoint = 600.0;

const List<DeviceOrientation> kPhonePortraitOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
];

const List<DeviceOrientation> kTabletLandscapeOrientations =
    <DeviceOrientation>[
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

bool isTabletLogicalSize(Size logicalSize) {
  if (logicalSize.width <= 0 || logicalSize.height <= 0) {
    return false;
  }
  return logicalSize.shortestSide >= kTabletShortestSideBreakpoint;
}

bool isTabletLogicalWindowOrDisplaySize({
  required Size? logicalWindowSize,
  required Size? logicalDisplaySize,
}) {
  if (logicalWindowSize != null && isTabletLogicalSize(logicalWindowSize)) {
    return true;
  }
  if (logicalDisplaySize != null && isTabletLogicalSize(logicalDisplaySize)) {
    return true;
  }
  return false;
}

List<DeviceOrientation> preferredOrientationsForWindow({
  required TargetPlatform targetPlatform,
  required bool isWeb,
  required Size? logicalSize,
  Size? logicalDisplaySize,
}) {
  if (isWeb) {
    return const <DeviceOrientation>[];
  }

  switch (targetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      if (isTabletLogicalWindowOrDisplaySize(
        logicalWindowSize: logicalSize,
        logicalDisplaySize: logicalDisplaySize,
      )) {
        return kTabletLandscapeOrientations;
      }
      return kPhonePortraitOrientations;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return const <DeviceOrientation>[];
  }
}

Size? currentFlutterViewLogicalSize() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) {
    return null;
  }

  final view = views.first;
  final physicalSize = view.physicalSize;
  final devicePixelRatio = view.devicePixelRatio;
  if (physicalSize.isEmpty || devicePixelRatio <= 0) {
    return null;
  }

  return physicalSize / devicePixelRatio;
}

Size? currentFlutterDisplayLogicalSize() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) {
    return null;
  }

  final display = views.first.display;
  final physicalSize = display.size;
  final devicePixelRatio = display.devicePixelRatio;
  if (physicalSize.isEmpty || devicePixelRatio <= 0) {
    return null;
  }

  return physicalSize / devicePixelRatio;
}

Future<void> applyPreferredOrientationsForCurrentWindow() {
  return SystemChrome.setPreferredOrientations(
    preferredOrientationsForWindow(
      targetPlatform: defaultTargetPlatform,
      isWeb: kIsWeb,
      logicalSize: currentFlutterViewLogicalSize(),
      logicalDisplaySize: currentFlutterDisplayLogicalSize(),
    ),
  );
}
