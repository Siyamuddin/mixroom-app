import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/widgets/auth_figma_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('macOS auth back button clears the native title bar', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      expect(mixroomAuthCornerBackButtonTopInset(), 42);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('non-macOS auth back button keeps its original inset', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      expect(mixroomAuthCornerBackButtonTopInset(), 10);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop auth uses the wide optimized background', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    PlatformCapabilities.debugResetForCurrentPlatform();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox.expand(child: MixroomAuthBackground()),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        kMixroomDesktopAuthBackgroundAsset,
      );
      expect(image.fit, BoxFit.cover);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      PlatformCapabilities.debugResetForCurrentPlatform();
    }
  });
}
