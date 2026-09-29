import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';

void main() {
  testWidgets('mobile Add Project remains enabled while idle', (tester) async {
    var addTaps = 0;
    await _pumpApp(
      tester,
      MixroomMainBottomDock(
        selectedTab: MixroomMainTab.projects,
        onTabSelected: (_) {},
        onAddTap: () => addTaps++,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('mixroom-create-project-button')),
    );

    expect(addTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile Add Project is disabled while creation is in progress', (
    tester,
  ) async {
    var addTaps = 0;
    await _pumpApp(
      tester,
      MixroomMainBottomDock(
        selectedTab: MixroomMainTab.projects,
        onTabSelected: (_) {},
        onAddTap: () => addTaps++,
        creatingProject: true,
      ),
    );

    final addButton = find.byKey(
      const ValueKey('mixroom-create-project-button'),
    );
    expect(addButton, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<MixroomShellRoundButton>(addButton).active, isTrue);

    for (var i = 0; i < 10; i++) {
      await tester.tap(addButton);
    }

    expect(addTaps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Add Project remains enabled while idle', (tester) async {
    var addTaps = 0;
    await _pumpApp(
      tester,
      MixroomMainSideRail(
        selectedTab: MixroomMainTab.projects,
        onTabSelected: (_) {},
        onAddTap: () => addTaps++,
      ),
    );

    await tester.tap(find.byTooltip('New Project'));

    expect(addTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Add Project is disabled while creation is in progress', (
    tester,
  ) async {
    var addTaps = 0;
    await _pumpApp(
      tester,
      MixroomMainSideRail(
        selectedTab: MixroomMainTab.projects,
        onTabSelected: (_) {},
        onAddTap: () => addTaps++,
        creatingProject: true,
      ),
    );

    final addButton = find.byTooltip('Creating project…');
    expect(addButton, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    for (var i = 0; i < 10; i++) {
      await tester.tap(addButton);
    }

    expect(addTaps, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpApp(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1360, 788));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  );
}
