import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/screens/login.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:mixroom/widgets/auth_figma_shell.dart';
import 'package:mixroom/widgets/mixroom_animated_atmosphere.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('desktop sign-in keeps native SSO controls and fits',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _pumpDesktopApp(
        tester,
        providers: [
          ChangeNotifierProvider<AuthService>(
            create: (_) => AuthService(restoreSessionOnInit: false),
          ),
        ],
        child: const LoginScreen(),
      );

      expect(find.byType(MixroomAuthDesktopHero), findsOneWidget);
      expect(_semanticButton('Continue with Google'), findsOneWidget);
      expect(_semanticButton('Continue with Apple'), findsOneWidget);
      expect(_semanticButton('Continue with Kakao'), findsOneWidget);
      expect(find.text('Or continue with'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);

      final atmosphere = tester.widget<MixroomAnimatedAtmosphere>(
        find.descendant(
          of: find.byType(MixroomAuthBackground),
          matching: find.byType(MixroomAnimatedAtmosphere),
        ),
      );
      expect(atmosphere.particleOpacity, greaterThan(0));

      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop shell titlebar and rail align without home particles',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _pumpDesktopApp(
        tester,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const MixroomShellBackground(),
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: MixroomDesktopTitleBar(),
            ),
            Positioned(
              left: 10,
              top: kMixroomDesktopTitleBarHeight + 12,
              bottom: 18,
              child: MixroomMainSideRail(
                selectedTab: MixroomMainTab.projects,
                onTabSelected: (_) {},
                onAddTap: () {},
              ),
            ),
          ],
        ),
      );

      expect(find.text('Desktop'), findsOneWidget);
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.byTooltip('Platform'), findsOneWidget);
      expect(find.byTooltip('Projects'), findsOneWidget);
      expect(find.byTooltip('Account'), findsOneWidget);
      expect(find.byTooltip('New Project'), findsOneWidget);

      expect(
        tester.getSize(find.byType(MixroomDesktopTitleBar)).height,
        kMixroomDesktopTitleBarHeight,
      );
      expect(
        tester.getSize(find.byType(MixroomMainSideRail)).width,
        kMixroomDesktopRailWidth,
      );

      final atmosphere = tester.widget<MixroomAnimatedAtmosphere>(
        find.descendant(
          of: find.byType(MixroomShellBackground),
          matching: find.byType(MixroomAnimatedAtmosphere),
        ),
      );
      expect(atmosphere.reactive, isTrue);
      expect(atmosphere.particleOpacity, 0);
      expect(atmosphere.waveOpacity, greaterThan(0));

      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Finder _semanticButton(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
    description: 'Semantics button labeled "$label"',
  );
}

Future<void> _pumpDesktopApp(
  WidgetTester tester, {
  required Widget child,
  List<SingleChildWidget> providers = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(1360, 788));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  final localeProvider = LocaleProvider();
  addTearDown(localeProvider.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
        ...providers,
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, provider, _) {
          return MaterialApp(
            locale: L10n.resolveSupportedLocale(provider.locale),
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: TickerMode(
                enabled: false,
                child: child,
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
