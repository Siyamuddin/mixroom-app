import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/widgets/remote_welcome_onboarding_screen.dart';

void main() {
  testWidgets('onboarding pages use the full safe width while swiping',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(),
          child: RemoteWelcomeOnboardingScreen(
            onCompleted: _noop,
          ),
        ),
      ),
    );
    await tester.pump();

    final pageViewRect = tester.getRect(find.byType(PageView));
    expect(pageViewRect.left, 0);
    expect(pageViewRect.right, 390);
  });

  testWidgets('onboarding uses the start button only on the fourth page',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(),
          child: RemoteWelcomeOnboardingScreen(
            onCompleted: _noop,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Get Started!'), findsNothing);

    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
    }

    expect(find.text('Next'), findsNothing);
    expect(find.text('Get Started!'), findsOneWidget);
  });
}

void _noop() {}
