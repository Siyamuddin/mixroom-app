import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/widgets/daw_mobile_row_grouping_actions.dart';

Widget _harness({
  required Locale locale,
  required int selectedCount,
  required VoidCallback onCancel,
  required VoidCallback onGroup,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Align(
        alignment: Alignment.bottomRight,
        child: DawMobileRowGroupingActions(
          selectedCount: selectedCount,
          onCancel: onCancel,
          onGroup: onGroup,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('group stays disabled until two rows are selected', (
    tester,
  ) async {
    var cancelCount = 0;
    var groupCount = 0;

    await tester.pumpWidget(
      _harness(
        locale: const Locale('en'),
        selectedCount: 0,
        onCancel: () => cancelCount += 1,
        onGroup: () => groupCount += 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Group Rows'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    final groupFinder = find.byKey(const ValueKey('mobile_group_rows_button'));
    expect(tester.getSize(groupFinder).height, greaterThanOrEqualTo(44));
    await tester.tap(groupFinder);
    await tester.pump();
    expect(groupCount, 0);

    await tester.pumpWidget(
      _harness(
        locale: const Locale('en'),
        selectedCount: 1,
        onCancel: () => cancelCount += 1,
        onGroup: () => groupCount += 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    await tester.tap(groupFinder);
    await tester.pump();
    expect(groupCount, 0);

    await tester.pumpWidget(
      _harness(
        locale: const Locale('en'),
        selectedCount: 2,
        onCancel: () => cancelCount += 1,
        onGroup: () => groupCount += 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    await tester.tap(groupFinder);
    await tester.pump();
    expect(groupCount, 1);

    final cancelFinder = find.byKey(
      const ValueKey('mobile_cancel_group_rows_button'),
    );
    expect(tester.getSize(cancelFinder).height, greaterThanOrEqualTo(44));
    await tester.tap(cancelFinder);
    await tester.pump();
    expect(cancelCount, 1);
  });

  testWidgets('controls fit a narrow phone in every supported app language', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final locale in const <Locale>[
      Locale('en'),
      Locale('ko'),
      Locale('ja'),
    ]) {
      await tester.pumpWidget(
        _harness(
          locale: locale,
          selectedCount: 12,
          onCancel: () {},
          onGroup: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: locale.languageCode);
      final controlsRect = tester.getRect(
        find.byKey(const ValueKey('mobile_row_grouping_actions')),
      );
      // The production bottom row reserves 26 px for the flexible chat-bar
      // padding and 16 px after these actions at this width.
      expect(controlsRect.width, lessThanOrEqualTo(278));
      expect(controlsRect.height, greaterThanOrEqualTo(44));
    }
  });
}
