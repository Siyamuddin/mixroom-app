import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/orientation_policy.dart';

void main() {
  group('preferredOrientationsForWindow', () {
    test('locks phones on mobile platforms to portrait', () {
      expect(
        preferredOrientationsForWindow(
          targetPlatform: TargetPlatform.iOS,
          isWeb: false,
          logicalSize: const Size(393, 852),
        ),
        kPhonePortraitOrientations,
      );
      expect(
        preferredOrientationsForWindow(
          targetPlatform: TargetPlatform.android,
          isWeb: false,
          logicalSize: const Size(412, 915),
        ),
        kPhonePortraitOrientations,
      );
    });

    test('locks tablets on mobile platforms to landscape', () {
      expect(
        preferredOrientationsForWindow(
          targetPlatform: TargetPlatform.iOS,
          isWeb: false,
          logicalSize: const Size(834, 1194),
        ),
        kTabletLandscapeOrientations,
      );
      expect(
        preferredOrientationsForWindow(
          targetPlatform: TargetPlatform.android,
          isWeb: false,
          logicalSize: const Size(1280, 800),
        ),
        kTabletLandscapeOrientations,
      );
    });

    test('uses display size when an iPad window reports narrow launch metrics',
        () {
      expect(
        preferredOrientationsForWindow(
          targetPlatform: TargetPlatform.iOS,
          isWeb: false,
          logicalSize: const Size(562, 768),
          logicalDisplaySize: const Size(1024, 768),
        ),
        kTabletLandscapeOrientations,
      );
    });

    test('leaves desktop and web unrestricted', () {
      expect(
        preferredOrientationsForWindow(
          targetPlatform: TargetPlatform.macOS,
          isWeb: false,
          logicalSize: const Size(1024, 768),
        ),
        const <DeviceOrientation>[],
      );
      expect(
        preferredOrientationsForWindow(
          targetPlatform: TargetPlatform.iOS,
          isWeb: true,
          logicalSize: const Size(834, 1194),
        ),
        const <DeviceOrientation>[],
      );
    });
  });

  group('isTabletLogicalSize', () {
    test('uses the 600 dp shortest-side breakpoint', () {
      expect(isTabletLogicalSize(const Size(599, 900)), isFalse);
      expect(isTabletLogicalSize(const Size(600, 900)), isTrue);
      expect(isTabletLogicalSize(const Size(900, 600)), isTrue);
      expect(isTabletLogicalSize(Size.zero), isFalse);
    });
  });

  group('isTabletLogicalWindowOrDisplaySize', () {
    test('accepts either tablet window or tablet display dimensions', () {
      expect(
        isTabletLogicalWindowOrDisplaySize(
          logicalWindowSize: const Size(562, 768),
          logicalDisplaySize: const Size(1024, 768),
        ),
        isTrue,
      );
      expect(
        isTabletLogicalWindowOrDisplaySize(
          logicalWindowSize: const Size(430, 932),
          logicalDisplaySize: const Size(430, 932),
        ),
        isFalse,
      );
    });
  });
}
