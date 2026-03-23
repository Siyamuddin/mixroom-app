import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/signed_in_shell.dart';

void main() {
  Future<void> pumpWelcomeDialog(
    WidgetTester tester, {
    required Size size,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      buildSignedInShellWelcomeDialogForTest(firstName: 'Jamie'),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('welcome dialog fits and closes on a small phone',
      (tester) async {
    await pumpWelcomeDialog(
      tester,
      size: const Size(320, 568),
    );

    expect(find.text('Welcome to Mixroom'), findsOneWidget);
    expect(find.text('A DAW that stays readable.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your first three moves.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Ask, edit, or learn in plain language.'), findsOneWidget);
    expect(
        find.widgetWithText(FilledButton, 'Start Quick Tour'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Skip'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('welcome dialog fits on a wider but short phone', (tester) async {
    await pumpWelcomeDialog(
      tester,
      size: const Size(360, 640),
    );

    expect(find.text('Welcome to Mixroom'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
